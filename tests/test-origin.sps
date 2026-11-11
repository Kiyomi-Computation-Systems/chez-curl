#!r6rs
;;; The suite for the test instrument (ADR-0005): the origin,
;;; tests/origin.mjs, as the byte probe, tests/wire-probe.mjs, sees it. No
;;; check here uses libcurl or the curl command line.
;;;
;;; Every expected output is written here, by hand, never read from
;;; origin.mjs: a script's bytes changed there fail a test here. Each
;;; scenario's test asserts the whole bytes received and how the connection
;;; ended. The well-formed face's bytes are those Node 20.10.0 and 24.18.0
;;; were measured to write: they agree.
;;;
;;; The scenarios run against one origin, so the suite starts Node a few
;;; times, not once a test. Then the lifecycle: loopback faces, OS ports, the
;;; exit on stdin's end, how long an origin outlives a child Chez killed with
;;; SIGKILL, connections open when the origin stops, and bad clients. A client that
;;; resets mid-request is the probe, with --reset: its destroy() reaches the
;;; origin as a FIN (measured). One that half-closes is the probe, with
;;; --half-close.
;;;
;;; Every wait here is bounded by the monotonic clock, checked before each
;;; read. Every process it spawns ends with its call: probes and commands
;;; through capture-command, which waits for them; the origin's own runs under
;;; (curl-testing)'s bounded, GNU timeout, which kills its command and leaves
;;; nothing behind; and the two
;;; it leaves running, a probe and a child Chez, through open-process-ports,
;;; which hands them no pipe of an origin's (measured), each killed after.
;;;
;;; make test runs it from the repository root, with CHEZ exported, and NODE
;;; when set. Each computation that can raise runs under a guard that names
;;; what was raised: SRFI-64 turns a raise in the actual expression into #f,
;;; and dies on one in an expected expression or a top-level definition.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (auth-testing)
        (only (chezscheme) current-time getenv input-port-ready? machine-type make-time
              open-process-ports sleep time-nanosecond time-second))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

(test-begin "origin")

;; --- helpers ----------------------------------------------------------------

(define chez (getenv "CHEZ"))
(define node (let ((n (getenv "NODE"))) (if (and n (not (string=? n ""))) n "node")))

;; outcome : (-> Any) -> (U (List 'returned Any) (List 'raised String))
(define (outcome thunk)
  (guard (e (#t (list 'raised (describe e))))
    (list 'returned (thunk))))

;; latin-1 : Bytevector -> String
;; Each byte as the character of its code, so a failure prints the bytes.
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; octets : String -> Bytevector
;; Each character, all below 256, as the byte of its code.
(define (octets text)
  (u8-list->bytevector (map char->integer (string->list text))))

;; exchange : Origin Symbol String Natural -> (U (List String End) (List 'raised String))
;; Sends TEXT to FACE and answers the whole bytes received, as text, and how
;; the connection ended.
(define (exchange origin face text idle)
  (guard (e (#t (list 'raised (describe e))))
    (let ((p (wire-probe origin face (octets text) idle)))
      (list (latin-1 (probe-bytes p)) (probe-end p)))))

;; get : String String ... -> String
;; A GET request head for TARGET, with these header lines after Host.
(define (get target . headers)
  (apply string-append "GET " target " HTTP/1.1\r\nHost: 127.0.0.1\r\n"
         (append headers (list "\r\n"))))

(define close "Connection: close\r\n")

;; head-text : Natural Natural -> String
;; What /raw/head?total=TOTAL&line=LINE writes, built here by the route's
;; rule, written out: the status line, HTTP/1.1 200 OK, 17 bytes, and
;; content-length: 0, 19, then lines x-000001 on of LINE bytes, CR LF in,
;; their values v repeated, until the head, its empty line in, holds TOTAL
;; bytes: the last line takes what is left, and a remainder too short for a
;; line of its own, its name and ": " and CR LF and one v, goes to the line
;; before.
(define (head-text total line)
  (let* ((name (lambda (i) (let ((digits (number->string i)))
                             (string-append "x-" (make-string (- 6 (string-length digits)) #\0) digits))))
         (line-of (lambda (i n) (string-append (name i) ": " (make-string (- n 12) #\v) "\r\n"))))
    (let loop ((left (- total 17 2 19)) (i 1) (lines '()))
      (cond ((>= left line) (loop (- left line) (+ i 1) (cons (line-of i line) lines)))
            ((>= left 13) (loop 0 (+ i 1) (cons (line-of i left) lines)))
            ((and (> left 0) (pair? lines))
             (loop 0 i (cons (string-append (substring (car lines) 0 (- (string-length (car lines)) 2))
                                            (make-string left #\v) "\r\n")
                             (cdr lines))))
            (else (apply string-append "HTTP/1.1 200 OK\r\ncontent-length: 0\r\n"
                         (reverse (cons "\r\n" lines))))))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; arrival : (Listof (Pair Natural Natural)) Natural -> (U Natural #f)
;; When the chunk holding byte INDEX arrived.
(define (arrival arrivals index)
  (let loop ((rest arrivals) (ms #f))
    (if (and (pair? rest) (<= (caar rest) index))
        (loop (cdr rest) (cdar rest))
        ms)))

;; same-text : String String -> (U 'same (List 'differs Natural Natural))
;; For outputs too long to print: whether GOT is WANT, or where they part,
;; and GOT's length.
(define (same-text want got)
  (if (string=? want got)
      'same
      (let loop ((i 0))
        (if (and (< i (string-length want)) (< i (string-length got))
                 (char=? (string-ref want i) (string-ref got i)))
            (loop (+ i 1))
            (list 'differs i (string-length got))))))

;; now-ms : -> Integer
;; Milliseconds on the monotonic clock.
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; hex : String -> String
;; TEXT's bytes as lower-case hex, for the probe's command line.
(define (hex text)
  (apply string-append
         (map (lambda (b)
                (string (string-ref "0123456789abcdef" (div b 16))
                        (string-ref "0123456789abcdef" (mod b 16))))
              (bytevector->u8-list (octets text)))))

;; shell-word : String -> String
;; S as one POSIX shell word, in single quotes.
(define (shell-word s)
  (call-with-string-output-port
   (lambda (p)
     (put-char p #\')
     (string-for-each (lambda (c) (if (char=? c #\') (put-string p "'\\''") (put-char p c))) s)
     (put-char p #\'))))

;; read-line-within : Binary-Input-Port Natural -> (U String #f)
;; The first line PORT gives within MS milliseconds, or #f: (curl-testing)'s
;; read-within, which reads the clock before every read.
(define (read-line-within port ms)
  (let-values (((how bytes) (read-within port ms (lambda (b) (and (memv 10 (bytevector->u8-list b)) #t)) #t)))
    (and (eq? how 'done)
         (let ((text (latin-1 bytes)))
           (let loop ((i 0))
             (if (char=? (string-ref text i) #\newline) (substring text 0 i) (loop (+ i 1))))))))

;; probe-at : String Natural Natural -> End
;; How a connection to HOST:PORT ends, sending nothing, through the probe
;; program itself, for an address or an origin no Origin of this process
;; names.
(define (probe-at host port idle)
  (let ((answer (capture-command (list node "tests/wire-probe.mjs" host (number->string port)
                                       "" (number->string idle)))))
    (if (= (car answer) 0)
        (probe-end (parse-wire-probe (cadr answer)))
        (list 'probe-failed answer))))

;; The fixed 400 the raw face writes, by hand.
(define bad-request
  '("HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof))

;; pattern-text : Natural -> String
;; The first N bytes of the stream scripts' body, byte i being i mod 251,
;; as Latin-1 text, written here, never read from the origin.
(define (pattern-text n)
  (let loop ((i (- n 1)) (chars '()))
    (if (< i 0)
        (list->string chars)
        (loop (- i 1) (cons (integer->char (mod i 251)) chars)))))

;; counted-text : String -> String
;; The raw face's 200 with BODY, Content-Length and Connection: close.
(define (counted-text body)
  (string-append "HTTP/1.1 200 OK\r\nContent-Length: " (number->string (string-length body))
                 "\r\nConnection: close\r\n\r\n" body))

;; last-word : String -> String
;; TEXT's last word before its final newline.
(define (last-word text)
  (let* ((end (let loop ((i (string-length text)))
                (if (and (> i 0) (char=? (string-ref text (- i 1)) #\newline)) (loop (- i 1)) i)))
         (start (let loop ((i end))
                  (if (and (> i 0) (not (char=? (string-ref text (- i 1)) #\space))) (loop (- i 1)) i))))
    (substring text start end)))

;; report-fields : String -> (U (List Natural (U Natural Symbol)) #f)
;; The stalls script's answer's two values, written and stalled, from the
;; whole response: (W S), S a natural or none; #f for any other answer.
(define (report-fields response)
  (let* ((at (let loop ((i 0))
               (cond ((> (+ i 4) (string-length response)) #f)
                     ((string=? (substring response i (+ i 4)) "\r\n\r\n") (+ i 4))
                     (else (loop (+ i 1))))))
         (body (and at (substring response at (string-length response))))
         (port (and body (open-string-input-port body)))
         (words (and port (let loop ((found '()))
                            (let ((datum (guard (e (#t 'unreadable)) (read port))))
                              (if (eof-object? datum) (reverse found) (loop (cons datum found))))))))
    (and words (= (length words) 4) (eq? (car words) 'written) (eq? (caddr words) 'stalled)
         (integer? (cadr words)) (or (integer? (cadddr words)) (eq? (cadddr words) 'none))
         (list (cadr words) (cadddr words)))))

;; non-reader : String
;; Node's own client, run as node -e NON-READER HOST PORT TARGET: it
;; connects, sends a GET of TARGET, reads nothing, and after 1000 ms goes,
;; exiting 0; a connection error exits 1.
(define non-reader
  (string-append
   "const net = require('node:net');"
   "const [host, port, target] = process.argv.slice(1);"
   "const socket = net.connect(Number(port), host, () => {"
   "  socket.write(`GET ${target} HTTP/1.1\\r\\nHost: 127.0.0.1\\r\\n\\r\\n`);"
   "  socket.pause();"
   "  setTimeout(() => { socket.destroy(); process.exit(0); }, 1000);"
   "});"
   "socket.on('error', () => process.exit(1));"))

(test-equal "CHEZ names the Chez to spawn"
  'set
  (if (and chez (not (string=? chez ""))) 'set 'unset))

;; --- the scenarios, against one origin ----------------------------------------

;; raw-row : Origin String String Symbol [Natural] -> Unit
;; NAME's test: a GET of TARGET on the raw face gets exactly WANT, then END.
(define (raw-row origin target want end . idle)
  (test-equal (string-append "raw " target ": the whole bytes, then " (symbol->string end))
    (list want end)
    (exchange origin 'raw (get target) (if (null? idle) 2000 (car idle)))))

;; http-row : Origin String String String -> Unit
;; NAME's test: REQUEST on the well-formed face gets exactly WANT, then eof.
(define (http-row origin name request want)
  (test-equal (string-append "http " name ": the whole bytes Node writes, then eof")
    (list want 'eof)
    (exchange origin 'http request 2000)))

;; linux? : Boolean
;; Whether this Chez runs on Linux: its machine types end in le (ta6le,
;; tarm64le, ...).
(define linux?
  (let ((m (symbol->string (machine-type))))
    (and (>= (string-length m) 2) (string=? (substring m (- (string-length m) 2) (string-length m)) "le"))))

;; iota : Natural -> (Listof Natural)
(define (iota n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; in-order : (Any -> Any) (Listof Any) -> (Listof Any)
;; PROC of each of ITEMS, called first to last: map calls its procedure in
;; no fixed order, and the retry script's answers depend on the requests
;; before them.
(define (in-order proc items)
  (let loop ((rest items) (answers '()))
    (if (null? rest)
        (reverse answers)
        (let ((answer (proc (car rest))))
          (loop (cdr rest) (cons answer answers))))))

;; --- the sinks' summaries ---------------------------------------------------
;; A summary line holds times, which no run can fix: the G of gap=G@B and
;; each list entry's T. shape writes each as ~ once it is a time as the
;; origin writes one, so a test asserts the rest of the line, and the
;; response around it, whole, and judges the times by bounds.

;; digit? : Char -> Boolean
(define (digit? c) (and (char<=? #\0 c) (char<=? c #\9)))

;; time? : String -> Boolean
;; Whether TEXT is ms to one decimal: digits, no leading zero but a lone 0,
;; a dot, one digit.
(define (time? text)
  (let ((n (string-length text)))
    (and (>= n 3)
         (char=? (string-ref text (- n 2)) #\.)
         (digit? (string-ref text (- n 1)))
         (for-all digit? (string->list (substring text 0 (- n 2))))
         (or (= n 3) (not (char=? (string-ref text 0) #\0))))))

;; tenths : String -> Integer
;; A time as time? reads one, in tenths of a ms.
(define (tenths text)
  (let ((n (string-length text)))
    (+ (* 10 (string->number (substring text 0 (- n 2)))) (string->number (substring text (- n 1) n)))))

;; split-text : String Char -> (Listof String)
;; TEXT's pieces between each SEP, empty ones included.
(define (split-text text sep)
  (let loop ((i 0) (start 0) (pieces '()))
    (cond ((= i (string-length text)) (reverse (cons (substring text start i) pieces)))
          ((char=? (string-ref text i) sep) (loop (+ i 1) (+ i 1) (cons (substring text start i) pieces)))
          (else (loop (+ i 1) start pieces)))))

;; join-text : (Listof String) String -> String
(define (join-text pieces sep)
  (if (null? pieces)
      ""
      (fold-left (lambda (joined piece) (string-append joined sep piece)) (car pieces) (cdr pieces))))

;; prefix? : String String -> Boolean
(define (prefix? start s)
  (and (<= (string-length start) (string-length s)) (string=? start (substring s 0 (string-length start)))))

;; shape : String -> (List String (Listof String))
;; A summary line TEXT with the G of its gap=G@B and the T of each of its
;; list's T:N as ~, each one time? takes, and those times, in order. Any
;; other text is left as it is, so a time written any other way shows.
(define (shape text)
  (let ((times '()))
    (define (timed t)
      (if (time? t) (begin (set! times (cons t times)) "~") t))
    (define (each-in-order proc items)
      (let loop ((rest items) (done '()))
        (if (null? rest) (reverse done) (let ((d (proc (car rest)))) (loop (cdr rest) (cons d done))))))
    (let ((shaped
           (each-in-order
            (lambda (word)
              (cond ((prefix? "gap=" word)
                     (let ((parts (split-text (substring word 4 (string-length word)) #\@)))
                       (if (= (length parts) 2) (string-append "gap=" (timed (car parts)) "@" (cadr parts)) word)))
                    ((prefix? "list=" word)
                     (string-append
                      "list="
                      (join-text (each-in-order
                                  (lambda (entry)
                                    (let ((parts (split-text entry #\:)))
                                      (if (= (length parts) 2) (string-append (timed (car parts)) ":" (cadr parts)) entry)))
                                  (split-text (substring word 5 (string-length word)) #\,))
                                 ",")))
                    (else word)))
            (split-text text #\space))))
      (list (join-text shaped " ") (reverse times)))))

;; shape-response : String -> (List String (Listof String))
;; A whole HTTP/1.1 response TEXT, its head's Content-Length line written
;; Content-Length: L when it is the body's length, and its body shaped; and
;; the body's times. A response with no head's end is left as it is.
(define (shape-response text)
  (let ((at (let loop ((i 0))
              (cond ((> (+ i 4) (string-length text)) #f)
                    ((string=? (substring text i (+ i 4)) "\r\n\r\n") i)
                    (else (loop (+ i 1)))))))
    (if (not at)
        (list text '())
        (let* ((body (substring text (+ at 4) (string-length text)))
               (length-line (string-append "Content-Length: " (number->string (string-length body))))
               ;; Each line but the last keeps its CR.
               (lines (map (lambda (line)
                             (cond ((string=? line length-line) "Content-Length: L")
                                   ((string=? line (string-append length-line "\r")) "Content-Length: L\r")
                                   (else line)))
                           (split-text (substring text 0 at) #\newline)))
               (shaped (shape body)))
          (list (string-append (join-text lines "\n") "\r\n\r\n" (car shaped)) (cadr shaped))))))

;; sink-exchange : Origin Symbol String Natural -> (U (List String End (Listof String)) (List 'raised String))
;; TEXT sent to FACE, as exchange sends it: the response shaped, how the
;; connection ended, and the response's times.
(define (sink-exchange o face text idle)
  (let ((got (exchange o face text idle)))
    (if (eq? (car got) 'raised)
        got
        (let ((shaped (shape-response (car got))))
          (list (car shaped) (cadr got) (cadr shaped))))))

;; split-probe : Origin Symbol String Natural Natural Natural String ... -> Probe
;; The probe, with OPTIONS and --split OFFSET:MS, against FACE: TEXT's first
;; OFFSET bytes, then, MS ms after the kernel took them, the rest. It raises
;; when the probe does not exit 0, or parse-wire-probe refuses its output.
(define (split-probe o face text offset ms idle . options)
  (let* ((f (origin-face o face))
         (answer (capture-command
                  (append (list node "tests/wire-probe.mjs") options
                          (list "--split" (string-append (number->string offset) ":" (number->string ms))
                                (car f) (number->string (cdr f)) (hex text) (number->string idle))))))
    (unless (= (car answer) 0) (error 'split-probe "the probe did not exit 0" answer))
    (parse-wire-probe (cadr answer))))

;; post : String String ... -> String
;; A POST request head for TARGET, with these header lines after Host.
(define (post target . headers)
  (apply string-append "POST " target " HTTP/1.1\r\nHost: 127.0.0.1\r\n" (append headers (list "\r\n"))))

(define (scenarios o)
  ;; --- the raw face: framing
  (raw-row o "/raw/content-length" "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" 'eof)
  (raw-row o "/raw/chunked"
           "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n1\r\n\n\r\n0\r\n\r\n" 'eof)
  (raw-row o "/raw/chunked-extensions-trailers"
           (string-append "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: X-Trailer\r\n\r\n"
                          "C;name=value\r\nhello world\n\r\n0;last\r\nX-Trailer: done\r\n\r\n")
           'eof)
  (raw-row o "/raw/chunked-tiny"
           (string-append "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
                          "1\r\nh\r\n1\r\ne\r\n1\r\nl\r\n1\r\nl\r\n1\r\no\r\n1\r\n\n\r\n0\r\n\r\n")
           'eof)
  (raw-row o "/raw/close-delimited" "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nhello\n" 'eof)
  (raw-row o "/raw/http10" "HTTP/1.0 200 OK\r\n\r\nhello\n" 'eof)

  ;; --- the raw face: drips. The bytes, and two lower bounds on their timing.
  ;; - The last body byte comes at least N x GAP ms after the probe connected.
  ;;   The probe takes that time before it sends the request, and the origin
  ;;   waits GAP before each byte, so no delay in either process can make the
  ;;   bound fail on a right origin.
  ;; - The last body byte comes at least half of (N-1) x GAP ms after the
  ;;   first, so the bytes are spread, not held back and sent together. Half,
  ;;   because the probe may see the first byte late: the arrivals are when
  ;;   the probe read each byte, not when the origin wrote it.
  ;; - Each body byte i, from 0, comes at least (i+1) x GAP ms after the probe
  ;;   connected, by the same argument as the first bound.
  ;; - On the 25 ms row, each body byte is an arrival of its own: bytes held
  ;;   back and sent in pairs would arrive together. Not on the 2 ms row, where
  ;;   the probe may read two in one chunk.
  (for-each
   (lambda (row)
     (let ((n (car row)) (gap (cadr row)) (head (caddr row)) (body (cadddr row)))
       (test-equal (string-append "raw /raw/drip?bytes=" (number->string n) "&gap=" (number->string gap)
                                  ": the whole bytes, then eof, the last body byte at least "
                                  (number->string (* n gap)) " ms after connecting and "
                                  "half of " (number->string (* (- n 1) gap)) " ms after the first")
         (list (string-append head body) 'eof 'late-enough 'spread-enough 'each-late-enough
               (if (= gap 25) 'own-arrivals 'not-held))
         (guard (e (#t (list 'raised (describe e))))
           (let* ((p (wire-probe o 'raw (octets (get (string-append "/raw/drip?bytes=" (number->string n)
                                                                 "&gap=" (number->string gap))))
                            2000))
                  (first (arrival (probe-arrivals p) (string-length head)))
                  (last (arrival (probe-arrivals p) (+ (string-length head) n -1)))
                  (since (and last (probe-connected p) (- last (probe-connected p))))
                  (spread (and first last (- last first))))
             (list (latin-1 (probe-bytes p)) (probe-end p)
                   (if (and since (>= since (* n gap)))
                       'late-enough
                       (list 'since-connected since (probe-connected p) (probe-arrivals p)))
                   (if (and spread (>= (* 2 spread) (* (- n 1) gap)))
                       'spread-enough
                       (list 'spread spread (probe-arrivals p)))
                   (let ((early (filter (lambda (i)
                                          (let ((at (arrival (probe-arrivals p) (+ (string-length head) i))))
                                            (not (and at (probe-connected p)
                                                      (>= (- at (probe-connected p)) (* (+ i 1) gap))))))
                                        (iota n))))
                     (if (null? early)
                         'each-late-enough
                         (list 'early-bytes early (probe-connected p) (probe-arrivals p))))
                   (if (= gap 25)
                       (let ((offsets (map car (probe-arrivals p))))
                         (if (for-all (lambda (i) (memv (+ (string-length head) i) offsets)) (iota n))
                             'own-arrivals
                             (list 'shared-arrivals (probe-arrivals p))))
                       'not-held)))))))
   '((4 25 "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\n" "abcd")
     (1 1 "HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\n" "a")
     (28 2 "HTTP/1.1 200 OK\r\nContent-Length: 28\r\n\r\n" "abcdefghijklmnopqrstuvwxyzab")))
  (raw-row o "/raw/drip?bytes=4096&gap=5000" "HTTP/1.1 200 OK\r\nContent-Length: 4096\r\n\r\n" 'timeout 300)
  (raw-row o "/raw/stall-after-head" "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n" 'timeout 150)

  ;; --- the raw face: a script that pauses mid-body for ms, 1 to 60000
  (test-equal "raw /raw/pause-mid-body?ms=50: the whole bytes, then eof, \" world\" at least 50 ms after connecting"
    (list "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello world" 'eof 'late-enough)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((p (wire-probe o 'raw (octets (get "/raw/pause-mid-body?ms=50")) 2000))
             (at (arrival (probe-arrivals p) (string-length "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello"))))
        (list (latin-1 (probe-bytes p)) (probe-end p)
              (if (and at (probe-connected p) (>= (- at (probe-connected p)) 50))
                  'late-enough
                  (list 'world-at at 'connected (probe-connected p)))))))
  (raw-row o "/raw/pause-mid-body?ms=1" "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello world" 'eof)
  (raw-row o "/raw/pause-mid-body?ms=60000" "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello" 'timeout 300)
  (raw-row o "/raw/reset-after-pause?ms=1" "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello wor" 'reset)
  (raw-row o "/raw/stall-before-head" "" 'timeout 150)

  ;; --- the raw face: oversized
  (raw-row o "/raw/big-header?bytes=1" "HTTP/1.1 200 OK\r\nX-Big: a\r\n\r\n" 'eof)
  (raw-row o "/raw/big-header?bytes=5" "HTTP/1.1 200 OK\r\nX-Big: aaaaa\r\n\r\n" 'eof)
  (raw-row o "/raw/many-headers?count=1" "HTTP/1.1 200 OK\r\nX-H-1: v\r\n\r\n" 'eof)
  (raw-row o "/raw/many-headers?count=3"
           "HTTP/1.1 200 OK\r\nX-H-1: v\r\nX-H-2: v\r\nX-H-3: v\r\n\r\n" 'eof)
  (test-equal "raw /raw/big-header?bytes=1048576, the most it takes: the whole bytes, then eof"
    '(same eof)
    (let ((got (exchange o 'raw (get "/raw/big-header?bytes=1048576") 5000)))
      (if (eq? (car got) 'raised)
          got
          (list (same-text (string-append "HTTP/1.1 200 OK\r\nX-Big: " (make-string 1048576 #\a)
                                          "\r\n\r\n")
                           (car got))
                (cadr got)))))
  (test-equal "raw /raw/many-headers?count=100000, the most it takes: the whole bytes, then eof"
    '(same eof)
    (let ((got (exchange o 'raw (get "/raw/many-headers?count=100000") 5000)))
      (if (eq? (car got) 'raised)
          got
          (list (same-text
                 (call-with-string-output-port
                  (lambda (p)
                    (put-string p "HTTP/1.1 200 OK\r\n")
                    (let loop ((i 1))
                      (when (<= i 100000)
                        (put-string p "X-H-") (put-string p (number->string i)) (put-string p ": v\r\n")
                        (loop (+ i 1))))
                    (put-string p "\r\n")))
                 (car got))
                (cadr got)))))

  ;; --- the raw face: protocol errors
  (raw-row o "/raw/bad-status-line" "HTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" 'eof)
  (raw-row o "/raw/bad-status-code" "HTTP/1.1 2000 OK\r\nContent-Length: 6\r\n\r\nhello\n" 'eof)
  (raw-row o "/raw/bad-chunk-size"
           "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nhello\n\r\n0\r\n\r\n" 'eof)
  (raw-row o "/raw/short-body" "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" 'eof)
  (raw-row o "/raw/reset-mid-body" "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" 'reset)
  (raw-row o "/raw/conflicting-content-length"
           "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\nhello\n" 'eof)
  (raw-row o "/raw/chunked-and-content-length"
           "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nTransfer-Encoding: chunked\r\n\r\n6\r\nhello\n\r\n0\r\n\r\n"
           'eof)
  (raw-row o "/raw/header-no-colon"
           "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nX-No-Colon\r\n\r\nhello\n" 'eof)
  (raw-row o "/raw/nul-in-header"
           "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nX-Nul: a\x0;b\r\n\r\nhello\n" 'eof)
  ;; Every byte a header value can hold but CR and LF, 0x01 to 0xFF in
  ;; order, between an a and a z: the bytes where Latin-1 and UTF-8 part, and
  ;; the control bytes, written out here from their codes.
  (raw-row o "/raw/header-bytes"
           (string-append "HTTP/1.1 200 OK\r\nX-Bytes: a"
                          (list->string
                           (map integer->char
                                (filter (lambda (b) (not (memv b '(10 13))))
                                        (map (lambda (i) (+ i 1)) (iota 255)))))
                          "z\r\nContent-Length: 0\r\n\r\n")
           'eof)
  (raw-row o "/raw/close-before-response" "" 'eof)
  (raw-row o "/raw/http09" "hello\n" 'eof)

  ;; --- the raw face: tolerated
  (raw-row o "/raw/bare-lf" "HTTP/1.1 200 OK\nContent-Length: 6\n\nhello\n" 'eof)

  ;; --- the raw face: echo. The head's exact bytes, and not the body after it.
  (test-equal "raw /raw/echo: the request head's exact bytes as the body, and nothing sent after the head"
    (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: 60\r\n\r\n"
                         "GET /raw/echo HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Spaced:  a b \r\n\r\n")
          'eof)
    (exchange o 'raw (string-append (get "/raw/echo" "X-Spaced:  a b \r\n") "a body") 2000))

  ;; --- the raw face: location, a status and Location headers of any bytes.
  ;; Its head, written out here: the status line, each Location in order,
  ;; then Content-Length: 0 and Connection: close.
  (let ((head (lambda (code . locations)
                (apply string-append "HTTP/1.1 " code " Redirect\r\n"
                       (append (map (lambda (l) (string-append "Location: " l "\r\n")) locations)
                               (list "Content-Length: 0\r\nConnection: close\r\n\r\n")))))
        ;; every byte but CR and LF, 0x00 to 0xFF, in order
        (bytes (filter (lambda (b) (not (memv b '(10 13)))) (iota 256)))
        (hex2 (lambda (b upper?)
                (let ((digits (if upper? "0123456789ABCDEF" "0123456789abcdef")))
                  (string #\% (string-ref digits (div b 16)) (string-ref digits (mod b 16)))))))
    (raw-row o "/raw/location?code=302&to=%2Fx" (head "302" "/x") 'eof)
    (raw-row o "/raw/location?code=200" (head "200") 'eof)
    (raw-row o "/raw/location?code=599&ms=0&to=a+b=c" (head "599" "a+b=c") 'eof)
    (raw-row o "/raw/location?to=%2Ffirst&to=&code=307&to=%2Fthird" (head "307" "/first" "" "/third") 'eof)
    (test-equal "raw /raw/location: every byte but CR and LF, 0x00 to 0xFF, each as %XX in upper-case hex, then in lower, comes back as its byte, in order"
      (let ((value (list->string (map integer->char bytes))))
        (list (list (head "301" value) 'eof) (list (head "301" value) 'eof)))
      (map (lambda (upper?)
             (exchange o 'raw
                       (get (apply string-append "/raw/location?code=301&to="
                                   (map (lambda (b) (hex2 b upper?)) bytes)))
                       2000))
           '(#t #f)))
    (test-equal "raw /raw/location?code=307&key=loc-1&to=%2Fx: the whole bytes, then eof; the head counted for its key, as /sink counts it, so http's /seen reads 1, and 0 for a key never given"
      (list (list (head "307" "/x") 'eof) (seen-text 1) (seen-text 0))
      (guard (e (#t (list 'raised (describe e))))
        (let* ((answer (exchange o 'raw (get "/raw/location?code=307&key=loc-1&to=%2Fx") 2000))
               (one (seen-of o "loc-1"))
               (never (seen-of o "loc-never")))
          (list answer one never))))
    (test-equal "raw /raw/location?code=302&ms=200&to=%2Fx: the whole bytes, then eof, the first at least 200 ms after connecting"
      (list (head "302" "/x") 'eof 'late-enough)
      (guard (e (#t (list 'raised (describe e))))
        (let* ((p (wire-probe o 'raw (octets (get "/raw/location?code=302&ms=200&to=%2Fx")) 2000))
               (at (arrival (probe-arrivals p) 0)))
          (list (latin-1 (probe-bytes p)) (probe-end p)
                (if (and at (probe-connected p) (>= (- at (probe-connected p)) 200))
                    'late-enough
                    (list 'first-at at 'connected (probe-connected p))))))))

  ;; --- the raw face: retry, a key's first requests failed, then a 200, and
  ;; the key's count, which attempts reads. Each check has keys of its own:
  ;; the counts live as long as the origin, across the scenarios.
  (let ((ok (lambda (n)
              (let ((body (string-append "attempt " (number->string n) "\n")))
                (string-append "HTTP/1.1 200 OK\r\nContent-Length: " (number->string (string-length body))
                               "\r\nConnection: close\r\n\r\n" body))))
        (failed (lambda (code after n)
                  (let ((body (string-append "attempt " (number->string n) "\n")))
                    (string-append "HTTP/1.1 " code " Retry\r\n"
                                   (if after (string-append "Retry-After: " after "\r\n") "")
                                   "Content-Length: " (number->string (string-length body))
                                   "\r\nConnection: close\r\n\r\n" body))))
        (counted (lambda (n)
                   (let ((body (string-append "attempts " (number->string n) "\n")))
                     (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: "
                                          (number->string (string-length body))
                                          "\r\nConnection: close\r\n\r\n" body)
                           'eof)))))
    (test-equal "raw /raw/retry, how=close, fail=2: the first two requests get nothing and an eof, the third and fourth a 200 that names their attempt; attempts reads 4"
      (list (list "" 'eof) (list "" 'eof) (list (ok 3) 'eof) (list (ok 4) 'eof) (counted 4))
      (in-order (lambda (target) (exchange o 'raw (get target) 2000))
           '("/raw/retry?key=close-2&fail=2&how=close" "/raw/retry?key=close-2&fail=2&how=close"
             "/raw/retry?key=close-2&fail=2&how=close" "/raw/retry?key=close-2&fail=2&how=close"
             "/raw/attempts?key=close-2")))
    (test-equal "raw /raw/retry, how=reset, fail=1: the first request gets nothing and a reset, the second the 200; attempts reads 2"
      (list (list "" 'reset) (list (ok 2) 'eof) (counted 2))
      (in-order (lambda (target) (exchange o 'raw (get target) 2000))
           '("/raw/retry?key=reset-1&fail=1&how=reset" "/raw/retry?key=reset-1&fail=1&how=reset"
             "/raw/attempts?key=reset-1")))
    (test-equal "raw /raw/retry, how=status: CODE, the Retry-After's bytes as given, percent-decoded, and none without after; then the 200"
      (list (list (failed "503" "1" 1) 'eof) (list (ok 2) 'eof)
            (list (failed "429" "Wed, 21 Oct 2026 07:28:00 GMT" 1) 'eof)
            (list (failed "500" #f 1) 'eof) (list (failed "500" #f 2) 'eof) (list (ok 3) 'eof))
      (in-order (lambda (target) (exchange o 'raw (get target) 2000))
           '("/raw/retry?key=status-1&fail=1&how=status&code=503&after=1"
             "/raw/retry?code=503&after=1&how=status&fail=1&key=status-1"
             "/raw/retry?key=status-date&fail=1&how=status&code=429&after=Wed%2C%2021%20Oct%202026%2007%3a28%3A00%20GMT"
             "/raw/retry?key=status-none&fail=2&how=status&code=500"
             "/raw/retry?key=status-none&fail=2&how=status&code=500"
             "/raw/retry?key=status-none&fail=2&how=status&code=500")))
    (test-equal "raw /raw/retry: fail=0 answers the 200 at once; each key counts alone, whatever its other parameters; attempts reads 0 for a key never counted"
      (list (list (ok 1) 'eof) (list (ok 1) 'eof) (list "" 'eof) (list (ok 2) 'eof) (counted 0)
            (counted 1) (counted 2))
      (in-order (lambda (target) (exchange o 'raw (get target) 2000))
           '("/raw/retry?key=zero&fail=0&how=close" "/raw/retry?key=Other.key_1-x&fail=0&how=reset"
             "/raw/retry?key=mixed&fail=1&how=close" "/raw/retry?key=mixed&fail=0&how=status&code=503"
             "/raw/attempts?key=never-counted" "/raw/attempts?key=zero" "/raw/attempts?key=mixed")))
    (test-equal "raw /raw/retry, then=stall: past its failures every request gets nothing, the connection held open until the client goes; then=ok, given, answers as the default does; each counted"
      (list (list "" 'eof) (list "" 'timeout) (list "" 'timeout) (counted 3)
            (list "" 'reset) (list (ok 2) 'eof) (counted 2))
      (in-order (lambda (row) (exchange o 'raw (get (car row)) (cadr row)))
                '(("/raw/retry?key=stall-1&fail=1&how=close&then=stall" 2000)
                  ("/raw/retry?then=stall&key=stall-1&fail=1&how=close" 300)
                  ("/raw/retry?key=stall-1&fail=1&how=close&then=stall" 300)
                  ("/raw/attempts?key=stall-1" 2000)
                  ("/raw/retry?key=then-ok&fail=1&how=reset&then=ok" 2000)
                  ("/raw/retry?key=then-ok&fail=1&how=reset&then=ok" 2000)
                  ("/raw/attempts?key=then-ok" 2000))))
    (test-equal "raw /raw/attempts counts nothing itself: read twice it answers 1 both times, and the next retry is the second attempt"
      (list (list "" 'eof) (counted 1) (counted 1) (list (ok 2) 'eof) (counted 2))
      (in-order (lambda (target) (exchange o 'raw (get target) 2000))
                '("/raw/retry?key=read-twice&fail=1&how=close" "/raw/attempts?key=read-twice"
                  "/raw/attempts?key=read-twice" "/raw/retry?key=read-twice&fail=1&how=close"
                  "/raw/attempts?key=read-twice")))
    (test-equal "raw /raw/retry: a query it refuses gets the fixed 400 and counts nothing"
      (list bad-request bad-request (counted 0))
      (in-order (lambda (target) (exchange o 'raw (get target) 2000))
           '("/raw/retry?key=refused&fail=1&how=close&x=1" "/raw/retry?key=refused&fail=101&how=close"
             "/raw/attempts?key=refused"))))

  ;; --- the raw face: hold, a key's requests held for ms, counted while
  ;; held, and most, which reads the key's count now and the most held at
  ;; once. Each check has keys of its own: the counts live as long as the
  ;; origin, across the scenarios.
  (let ((held "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nheld\n")
        (most (lambda (now at-most)
                (let ((body (string-append "held " (number->string now) " most "
                                           (number->string at-most) "\n")))
                  (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: "
                                       (number->string (string-length body))
                                       "\r\nConnection: close\r\n\r\n" body)
                        'eof)))))
    (test-equal "raw /raw/hold?key=hold-one&ms=200: the whole bytes, then eof, the first at least 200 ms after connecting; most then reads none held, 1 at most"
      (list held 'eof 'late-enough (most 0 1))
      (guard (e (#t (list 'raised (describe e))))
        (let* ((p (wire-probe o 'raw (octets (get "/raw/hold?key=hold-one&ms=200")) 2000))
               (at (arrival (probe-arrivals p) 0)))
          (list (latin-1 (probe-bytes p)) (probe-end p)
                (if (and at (probe-connected p) (>= (- at (probe-connected p)) 200))
                    'late-enough
                    (list 'first-at at 'connected (probe-connected p)))
                (exchange o 'raw (get "/raw/most?key=hold-one") 2000)))))
    (test-equal "raw /raw/hold, one after the other: two holds of one key count 1 at most, ms=0 among them, and key and ms in either order; most reads 0 and 0 for a key never held, and counts nothing itself"
      (list (list held 'eof) (list held 'eof) (most 0 1) (most 0 0) (most 0 1))
      (in-order (lambda (target) (exchange o 'raw (get target) 2000))
                '("/raw/hold?key=hold-seq&ms=50" "/raw/hold?ms=0&key=hold-seq" "/raw/most?key=hold-seq"
                  "/raw/most?key=hold-never" "/raw/most?key=hold-seq")))
    (test-equal "raw /raw/hold: a query it refuses gets the fixed 400 and counts nothing"
      (list bad-request bad-request (most 0 0))
      (in-order (lambda (target) (exchange o 'raw (get target) 2000))
                '("/raw/hold?key=hold-refused&ms=1&x=1" "/raw/hold?key=hold-refused&ms=60001"
                  "/raw/most?key=hold-refused")))
    ;; Two probes in one shell, each in the background, the second's output
    ;; on stderr: each holds 1000 ms, and both start within Node's start-up
    ;; time of each other, far under that.
    (test-equal "raw /raw/hold, two at once: two holds of one key, each 1000 ms, both started together, count 2 at most, each answered its whole bytes and eof; then none held"
      (list (list held 'eof) (list held 'eof) (most 0 2))
      (guard (e (#t (list 'raised (describe e))))
        (let* ((port (number->string (cdr (origin-face o 'raw))))
               (text (hex (get "/raw/hold?key=hold-two&ms=1000")))
               (r (capture-command
                   (list "sh" "-c"
                         (string-append
                          "\"$1\" tests/wire-probe.mjs 127.0.0.1 \"$2\" \"$3\" 3000 & a=$!\n"
                          "\"$1\" tests/wire-probe.mjs 127.0.0.1 \"$2\" \"$3\" 3000 1>&2 & b=$!\n"
                          "wait \"$a\"; sa=$?\n"
                          "wait \"$b\"; sb=$?\n"
                          "[ \"$sa\" -eq 0 ] && [ \"$sb\" -eq 0 ]\n")
                         "sh" node port text))))
          (if (= (car r) 0)
              (let ((one (parse-wire-probe (cadr r)))
                    (two (parse-wire-probe (caddr r))))
                (list (list (latin-1 (probe-bytes one)) (probe-end one))
                      (list (latin-1 (probe-bytes two)) (probe-end two))
                      (exchange o 'raw (get "/raw/most?key=hold-two") 2000)))
              (list 'probes-failed r))))))

  ;; --- the raw face: the fixed 400, for every NAME or parameter it refuses
  (for-each
   (lambda (row)
     (test-equal (string-append "raw: the fixed 400 for " (car row))
       bad-request
       (exchange o 'raw (cadr row) 2000)))
   (list (list "an unknown NAME" (get "/raw/nope"))
         (list "a parameter on a script that takes none" (get "/raw/content-length?bytes=1"))
         (list "an empty query" (get "/raw/content-length?"))
         (list "drip bytes=0, below its range" (get "/raw/drip?bytes=0&gap=10"))
         (list "drip bytes=4097, above its range" (get "/raw/drip?bytes=4097&gap=1"))
         (list "drip gap=0, below its range" (get "/raw/drip?bytes=1&gap=0"))
         (list "drip gap=5001, above its range" (get "/raw/drip?bytes=1&gap=5001"))
         (list "drip without gap" (get "/raw/drip?bytes=1"))
         (list "drip with an unknown parameter" (get "/raw/drip?bytes=1&gap=1&x=1"))
         (list "drip with bytes twice" (get "/raw/drip?bytes=1&bytes=2&gap=1"))
         (list "drip with a leading zero" (get "/raw/drip?bytes=01&gap=1"))
         (list "drip with a value that is no number" (get "/raw/drip?bytes=x&gap=1"))
         (list "big-header bytes=0" (get "/raw/big-header?bytes=0"))
         (list "big-header bytes=1048577" (get "/raw/big-header?bytes=1048577"))
         (list "many-headers count=0" (get "/raw/many-headers?count=0"))
         (list "many-headers count=100001" (get "/raw/many-headers?count=100001"))
         (list "pause-mid-body ms=0" (get "/raw/pause-mid-body?ms=0"))
         (list "pause-mid-body ms=60001" (get "/raw/pause-mid-body?ms=60001"))
         (list "pause-mid-body without ms" (get "/raw/pause-mid-body"))
         (list "reset-after-pause ms=0" (get "/raw/reset-after-pause?ms=0"))
         (list "reset-after-pause ms=60001" (get "/raw/reset-after-pause?ms=60001"))
         (list "reset-after-pause without ms" (get "/raw/reset-after-pause"))
         (list "location without a query" (get "/raw/location"))
         (list "location with an empty query" (get "/raw/location?"))
         (list "location without code" (get "/raw/location?to=%2Fx"))
         (list "location code=199, below its range" (get "/raw/location?code=199"))
         (list "location code=600, above its range" (get "/raw/location?code=600"))
         (list "location code twice" (get "/raw/location?code=302&code=302"))
         (list "location code with a leading zero" (get "/raw/location?code=0302"))
         (list "location code that is no number" (get "/raw/location?code=3x2"))
         (list "location ms=60001, above its range" (get "/raw/location?code=302&ms=60001"))
         (list "location ms twice" (get "/raw/location?code=302&ms=1&ms=1"))
         (list "location ms with a leading zero" (get "/raw/location?code=302&ms=01"))
         (list "location with an unknown parameter" (get "/raw/location?code=302&x=1"))
         (list "location with a pair that has no =" (get "/raw/location?code=302&to"))
         (list "location with a % and no hex after it" (get "/raw/location?code=302&to=%zz"))
         (list "location with a % and one hex digit" (get "/raw/location?code=302&to=a%4"))
         (list "location key twice" (get "/raw/location?code=302&key=lk&key=lk"))
         (list "location key past retry's characters" (get "/raw/location?code=302&key=a%2Fb"))
         (list "retry without a query" (get "/raw/retry"))
         (list "retry with an empty query" (get "/raw/retry?"))
         (list "retry without key" (get "/raw/retry?fail=1&how=close"))
         (list "retry without fail" (get "/raw/retry?key=k&how=close"))
         (list "retry without how" (get "/raw/retry?key=k&fail=1"))
         (list "retry with an empty key" (get "/raw/retry?key=&fail=1&how=close"))
         (list "retry with a key of 65 chars" (get (string-append "/raw/retry?key=" (make-string 65 #\k)
                                                                  "&fail=1&how=close")))
         (list "retry with a key holding a char outside A-Z, a-z, 0-9, ., _ and -"
               (get "/raw/retry?key=a%2Fb&fail=1&how=close"))
         (list "retry with key twice" (get "/raw/retry?key=k&key=k&fail=1&how=close"))
         (list "retry fail=101, above its range" (get "/raw/retry?key=k&fail=101&how=close"))
         (list "retry fail with a leading zero" (get "/raw/retry?key=k&fail=01&how=close"))
         (list "retry fail that is no number" (get "/raw/retry?key=k&fail=x&how=close"))
         (list "retry with an unknown how" (get "/raw/retry?key=k&fail=1&how=drop"))
         (list "retry how=status without code" (get "/raw/retry?key=k&fail=1&how=status"))
         (list "retry how=close with code" (get "/raw/retry?key=k&fail=1&how=close&code=503"))
         (list "retry how=reset with after" (get "/raw/retry?key=k&fail=1&how=reset&after=1"))
         (list "retry code=199, below its range" (get "/raw/retry?key=k&fail=1&how=status&code=199"))
         (list "retry code=600, above its range" (get "/raw/retry?key=k&fail=1&how=status&code=600"))
         (list "retry after twice" (get "/raw/retry?key=k&fail=1&how=status&code=503&after=1&after=2"))
         (list "retry after with a % and no hex after it" (get "/raw/retry?key=k&fail=1&how=status&code=503&after=%zz"))
         (list "retry with an unknown parameter" (get "/raw/retry?key=k&fail=1&how=close&x=1"))
         (list "retry with a pair that has no =" (get "/raw/retry?key=k&fail=1&how=close&after"))
         (list "retry with an unknown then" (get "/raw/retry?key=k&fail=1&how=close&then=hang"))
         (list "retry with then twice" (get "/raw/retry?key=k&fail=1&how=close&then=ok&then=stall"))
         (list "attempts without a query" (get "/raw/attempts"))
         (list "attempts with an empty key" (get "/raw/attempts?key="))
         (list "attempts with another parameter" (get "/raw/attempts?key=k&x=1"))
         (list "attempts without key" (get "/raw/attempts?x=k"))
         (list "hold without a query" (get "/raw/hold"))
         (list "hold without key" (get "/raw/hold?ms=1"))
         (list "hold without ms" (get "/raw/hold?key=k"))
         (list "hold with key twice" (get "/raw/hold?key=k&key=k&ms=1"))
         (list "hold with ms twice" (get "/raw/hold?key=k&ms=1&ms=1"))
         (list "hold ms=60001, above its range" (get "/raw/hold?key=k&ms=60001"))
         (list "hold ms with a leading zero" (get "/raw/hold?key=k&ms=01"))
         (list "hold ms that is no number" (get "/raw/hold?key=k&ms=x"))
         (list "hold with an empty key" (get "/raw/hold?key=&ms=1"))
         (list "hold with a key holding a char outside A-Z, a-z, 0-9, ., _ and -"
               (get "/raw/hold?key=a%2Fb&ms=1"))
         (list "hold with an unknown parameter" (get "/raw/hold?key=k&ms=1&x=1"))
         (list "hold with a pair that has no =" (get "/raw/hold?key=k&ms=1&x"))
         (list "most without a query" (get "/raw/most"))
         (list "most with an empty key" (get "/raw/most?key="))
         (list "most with another parameter" (get "/raw/most?key=k&x=1"))
         (list "pattern without a query" (get "/raw/pattern"))
         (list "pattern without key" (get "/raw/pattern?bytes=1&chunk=1"))
         (list "pattern without bytes" (get "/raw/pattern?key=k&chunk=1"))
         (list "pattern without chunk" (get "/raw/pattern?key=k&bytes=1"))
         (list "pattern bytes=0, below its range" (get "/raw/pattern?key=k&bytes=0&chunk=1"))
         (list "pattern bytes=268435457, above its range" (get "/raw/pattern?key=k&bytes=268435457&chunk=1"))
         (list "pattern chunk=0, below its range" (get "/raw/pattern?key=k&bytes=1&chunk=0"))
         (list "pattern chunk=1048577, above its range" (get "/raw/pattern?key=k&bytes=1&chunk=1048577"))
         (list "pattern delay=60001, above its range" (get "/raw/pattern?key=k&bytes=1&chunk=1&delay=60001"))
         (list "pattern gap=60001, above its range" (get "/raw/pattern?key=k&bytes=1&chunk=1&gap=60001"))
         (list "pattern with an unknown framing" (get "/raw/pattern?key=k&bytes=1&chunk=1&framing=close"))
         (list "pattern with bytes twice" (get "/raw/pattern?key=k&bytes=1&bytes=1&chunk=1"))
         (list "pattern with framing twice" (get "/raw/pattern?key=k&bytes=1&chunk=1&framing=length&framing=length"))
         (list "pattern with an unknown parameter" (get "/raw/pattern?key=k&bytes=1&chunk=1&x=1"))
         (list "pattern bytes with a leading zero" (get "/raw/pattern?key=k&bytes=01&chunk=1"))
         (list "pattern with an empty key" (get "/raw/pattern?key=&bytes=1&chunk=1"))
         (list "stalls without a query" (get "/raw/stalls"))
         (list "stalls with another parameter" (get "/raw/stalls?key=k&x=1"))
         (list "early with a parameter" (get "/raw/early?x=1"))
         (list "head n=0, below its range" (get "/raw/head?n=0"))
         (list "head n=100001, above its range" (get "/raw/head?n=100001"))
         (list "head line=12, below its range" (get "/raw/head?line=12"))
         (list "head n twice" (get "/raw/head?n=2&n=2"))
         (list "head n beside total" (get "/raw/head?n=2&total=100"))
         (list "head bigch without big" (get "/raw/head?bigch=X"))
         (list "head bigch of two chars" (get "/raw/head?big=20&bigch=XY"))
         (list "head big=8, below its range" (get "/raw/head?big=8"))
         (list "head tl without tn" (get "/raw/head?tl=20"))
         (list "head pre with a status of 200" (get "/raw/head?pre=200:1:16"))
         (list "head pre of 17 heads"
               (get (string-append "/raw/head?pre=100:0:16"
                                   (apply string-append (map (lambda (i) ",100:0:16") (iota 16))))))
         (list "head same=0" (get "/raw/head?same=0"))
         (list "head with an unknown parameter" (get "/raw/head?x=1"))
         (list "head with a pair that has no =" (get "/raw/head?n"))
         (list "head hname without line" (get "/raw/head?n=2&hname=1"))
         (list "head hname with line=21, a name of 17 bytes too long for it" (get "/raw/head?n=2&line=21&hname=1"))
         (list "head hname=0" (get "/raw/head?n=2&line=32&hname=0"))
         (list "head tname without tn" (get "/raw/head?n=2&tname=1"))
         (list "head v10=2" (get "/raw/head?v10=2"))
         (list "head-auth with a name neither a. nor b." (get "/raw/head-auth?n=2"))
         (list "head-auth with an a. spec it refuses" (get "/raw/head-auth?a.n=0"))
         (list "head417 with a name neither a. nor b." (get "/raw/head417?key=k&b.n=2&x=1"))
         (list "head417 without key" (get "/raw/head417?a.n=2&b.n=2"))
         (list "head417 with key twice" (get "/raw/head417?key=k&key=k"))
         (list "a path outside /raw/" (get "/content-length"))
         (list "a request line of two words" "GET /raw/content-length\r\n\r\n")
         (list "a request line of four words" "GET /raw/content-length HTTP/1.1 x\r\n\r\n")
         (list "garbage" (string-append (string #\nul #\x1 #\xff) " garbage\r\n\r\n"))))

  ;; --- the raw face: the stream scripts. The pattern's body is byte i mod
  ;; 251, written by hand here; its record is the stalls script's answer.
  (raw-row o "/raw/pattern?key=p1&bytes=600&chunk=256"
           (string-append "HTTP/1.1 200 OK\r\nContent-Length: 600\r\nConnection: close\r\n\r\n"
                          (pattern-text 600))
           'eof)
  (raw-row o "/raw/stalls?key=p1" (counted-text "written 600 stalled none\n") 'eof)
  (raw-row o "/raw/pattern?key=p2&bytes=600&chunk=256&framing=chunked"
           (string-append "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
                          "100\r\n" (substring (pattern-text 600) 0 256) "\r\n"
                          "100\r\n" (substring (pattern-text 600) 256 512) "\r\n"
                          "58\r\n" (substring (pattern-text 600) 512 600) "\r\n"
                          "0\r\n\r\n")
           'eof)
  (raw-row o "/raw/pattern?key=p3&bytes=1&chunk=1&framing=length"
           (string-append "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nConnection: close\r\n\r\n"
                          (pattern-text 1))
           'eof)
  (raw-row o "/raw/stalls?key=p-never" (counted-text "written 0 stalled none\n") 'eof)
  ;; --- the raw face: the head routes (ADR-0040): a head of the size and
  ;; shape its query names, a Digest round's two answers, and a 417 and its
  ;; resend's, each written here by hand, or for a large one by this
  ;; suite's own generator, head-text
  (raw-row o "/raw/head" "HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n" 'eof)
  (raw-row o "/raw/head?n=3"
           "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-000001: vvvv\r\nx-000002: vvvv\r\n\r\n" 'eof)
  (raw-row o "/raw/head?n=2&line=20"
           "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-000001: vvvvvvvv\r\n\r\n" 'eof)
  (raw-row o "/raw/head?n=3&same=1"
           "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-same: vvvvvv\r\nx-same: vvvvvv\r\n\r\n" 'eof)
  (raw-row o "/raw/head?n=1&big=20"
           "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-big: aaaaaaaaaaa\r\n\r\n" 'eof)
  (raw-row o "/raw/head?big=20&bigch=X"
           "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-big: XXXXXXXXXXX\r\n\r\n" 'eof)
  (raw-row o "/raw/head?n=2&tn=2"
           (string-append "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\nx-000001: vvvv\r\n\r\n"
                          "0\r\nx-000001: vvvv\r\nx-000002: vvvv\r\n\r\n")
           'eof)
  (raw-row o "/raw/head?n=1&tn=1&tl=20"
           (string-append "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n"
                          "0\r\nx-000001: vvvvvvvv\r\n\r\n")
           'eof)
  (raw-row o "/raw/head?pre=100:0:16,103:2:20&n=2"
           (string-append "HTTP/1.1 100 Continue\r\n\r\n"
                          "HTTP/1.1 103 Early Hints\r\nx-000001: vvvvvvvv\r\nx-000002: vvvvvvvv\r\n\r\n"
                          "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-000001: vvvv\r\n\r\n")
           'eof)
  ;; hname names each generated line as a status line begins, HTTP/1.1 and a
  ;; space; tname, the first trailer HTTP/x; v10, each head HTTP/1.0. Each
  ;; line keeps its bytes.
  (raw-row o "/raw/head?n=3&line=32&hname=1"
           (string-append "HTTP/1.1 200 OK\r\ncontent-length: 0\r\n"
                          "HTTP/1.1 x-000001: vvvvvvvvvvv\r\nHTTP/1.1 x-000002: vvvvvvvvvvv\r\n\r\n")
           'eof)
  (raw-row o "/raw/head?n=2&tn=2&tname=1"
           (string-append "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\nx-000001: vvvv\r\n\r\n"
                          "0\r\nHTTP/x: vvvvvv\r\nx-000002: vvvv\r\n\r\n")
           'eof)
  (raw-row o "/raw/head?pre=103:1:16&n=2&v10=1"
           (string-append "HTTP/1.0 103 Early Hints\r\nx-000001: vvvv\r\n\r\n"
                          "HTTP/1.0 200 OK\r\ncontent-length: 0\r\nx-000001: vvvv\r\n\r\n")
           'eof)
  ;; total: 60 bytes, the status line's 17, content-length's 19 and the end's
  ;; 2 leave 22: one line of 16, and 6 too few for another, which go to it.
  (raw-row o "/raw/head?total=60"
           "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-000001: vvvvvvvvvv\r\n\r\n" 'eof)
  (for-each
   (lambda (spec)
     (let* ((total (car spec)) (line (cadr spec)) (want (head-text total line)))
       (test-equal (string-append "raw /raw/head?total=" (number->string total) "&line=" (number->string line)
                                  ": the head of exactly that many bytes, as this suite builds it, then eof")
         (list total 'same 'eof)
         (let ((a (exchange o 'raw (get (string-append "/raw/head?total=" (number->string total)
                                                       "&line=" (number->string line)))
                            2000)))
           (if (and (pair? a) (string? (car a)))
               (list (string-length (car a)) (same-text want (car a)) (cadr a))
               a)))))
   '((102400 256) (102401 256) (200 40)))
  (raw-row o "/raw/head-auth?a.n=2&b.n=3"
           (string-append "HTTP/1.1 401 Unauthorized\r\n"
                          "www-authenticate: Digest realm=\"chez-curl-test\", qop=\"auth\", nonce=\"n0\", algorithm=MD5\r\n"
                          "content-length: 0\r\nx-000001: vvvv\r\n\r\n")
           'eof)
  (test-equal "raw /raw/head-auth?a.n=2&b.n=3 with an Authorization header, unchecked: b.'s 200, then eof"
    '("HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-000001: vvvv\r\nx-000002: vvvv\r\n\r\n" eof)
    (exchange o 'raw (get "/raw/head-auth?a.n=2&b.n=3" "Authorization: Digest anything\r\n") 2000))
  ;; The 417's resend: KEY's first request's Expect gets a.'s 417 as its
  ;; head arrives; its next bytes, a letter, begin the resend, whose Expect
  ;; gets a 100 Continue, whose body is read, then b.'s 200, and the end. The
  ;; key holds the 417, not the connection: a resend on a new connection
  ;; gets the 100 Continue and the 200 too, and a key's first request
  ;; without Expect gets the 200 at once.
  (test-equal "raw /raw/head417?key=K&a.n=2&b.n=3: K's first Expect gets a 417 by a., kept alive; the resend's 100 Continue, its body read, then a 200 by b., then eof; a resend on a new connection gets the same; a first request without Expect gets the 200 at once"
    (let ((refused "HTTP/1.1 417 Expectation Failed\r\ncontent-length: 0\r\nx-000001: vvvv\r\n\r\n")
          (answered (string-append "HTTP/1.1 100 Continue\r\n\r\n"
                                   "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-000001: vvvv\r\nx-000002: vvvv\r\n\r\n")))
      (list (list (string-append refused answered) 'eof)
            (list refused 'timeout)
            (list answered 'eof)
            (list "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nx-000001: vvvv\r\nx-000002: vvvv\r\n\r\n" 'eof)))
    (let* ((expect (lambda (key) (post (string-append "/raw/head417?key=" key "&a.n=2&b.n=3")
                                       "Expect: 100-continue\r\n" "Content-Length: 3\r\n")))
           (same (exchange o 'raw (string-append (expect "h1") (expect "h1") "abc") 2000))
           (first (exchange o 'raw (expect "h2") 300))
           (again (exchange o 'raw (string-append (expect "h2") "abc") 2000))
           (plain (exchange o 'raw (string-append (post "/raw/head417?key=h3&a.n=2&b.n=3" "Content-Length: 3\r\n")
                                                  "abc")
                            2000)))
      (list same first again plain)))
  (raw-row o "/raw/early"
           (string-append "HTTP/1.1 100 Continue\r\n\r\n"
                          "HTTP/1.1 103 Early Hints\r\nLink: </style.css>; rel=preload; as=style\r\n\r\n"
                          "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nearly\n")
           'eof)
  ;; The delay and the gap: lower bounds alone, as the drips' are. The body
  ;; comes at least DELAY ms after the probe connected, and its last write
  ;; at least DELAY plus each GAP; the head comes before the body, in an
  ;; arrival of its own.
  (test-equal "raw /raw/pattern?key=p4&bytes=3&chunk=1&delay=300&gap=100: the whole bytes, then eof; the head before the body, which comes 300 ms or more after the probe connected, its last byte 500 ms or more"
    (list (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\n"
                               (pattern-text 3))
                'eof)
          'head-first 'body-after-delay 'last-after-gaps)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((p (wire-probe o 'raw (octets (get "/raw/pattern?key=p4&bytes=3&chunk=1&delay=300&gap=100")) 2000))
             (head (string-length "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\n"))
             (connected (probe-connected p))
             (first (arrival (probe-arrivals p) head))
             (last (arrival (probe-arrivals p) (+ head 2))))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and first (< (arrival (probe-arrivals p) (- head 1)) first)) 'head-first
                  (list 'head (arrival (probe-arrivals p) (- head 1)) 'body first))
              (if (and first (>= (- first connected) 300)) 'body-after-delay (list 'connected connected 'body first))
              (if (and last (>= (- last connected) 500)) 'last-after-gaps (list 'connected connected 'last last))))))
  ;; Where the writes stalled: a client that reads nothing, Node's own, as
  ;; the probe always reads. It sends its request, reads nothing for
  ;; 1000 ms, then goes; the record then names the offset of the first write
  ;; the kernel had not taken 100 ms on, short of the body's end, and the
  ;; bytes it took, at least that offset.
  (test-equal "raw /raw/pattern of 64 MiB, 65536 bytes a write, to a client that reads nothing: /raw/stalls then names an offset short of the body's end, past 0, where its writes first stalled, and bytes taken at least that offset, and short of the end"
    '(stalled offset-in-range written-from-offset written-short)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((f (origin-face o 'raw))
             (run (capture-command
                   (list node "-e" non-reader (car f) (number->string (cdr f))
                         "/raw/pattern?key=p5&bytes=67108864&chunk=65536")))
             (answer (exchange o 'raw (get "/raw/stalls?key=p5") 2000))
             (fields (and (pair? answer) (string? (car answer)) (report-fields (car answer)))))
        (if (not (and (= (car run) 0) fields))
            (list 'no-report run answer)
            (let ((written (car fields)) (stalled (cadr fields)))
              (list (if (integer? stalled) 'stalled (list 'stalled stalled))
                    (if (and (integer? stalled) (< 0 stalled 67108864)) 'offset-in-range stalled)
                    (if (and (integer? stalled) (>= written stalled)) 'written-from-offset (list written stalled))
                    (if (< written 67108864) 'written-short written)))))))

  ;; --- the http face: the stream routes, and the CONNECT proxy
  (http-row o "/pattern/600" (get "/pattern/600" close)
            (string-append "HTTP/1.1 200 OK\r\nContent-Length: 600\r\nConnection: close\r\n\r\n"
                           (pattern-text 600)))
  (http-row o "/pattern/600?delay=0" (get "/pattern/600?delay=0" close)
            (string-append "HTTP/1.1 200 OK\r\nContent-Length: 600\r\nConnection: close\r\n\r\n"
                           (pattern-text 600)))
  (test-equal "http /pattern/40000?delay=300: the whole bytes, then eof; the head flushed before the body, which comes 300 ms or more after the probe connected"
    (list (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: 40000\r\nConnection: close\r\n\r\n"
                               (pattern-text 40000))
                'eof)
          'head-first 'body-after-delay)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((p (wire-probe o 'http (octets (get "/pattern/40000?delay=300" close)) 2000))
             (head (string-length "HTTP/1.1 200 OK\r\nContent-Length: 40000\r\nConnection: close\r\n\r\n"))
             (first (arrival (probe-arrivals p) head)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and first (< (arrival (probe-arrivals p) (- head 1)) first)) 'head-first
                  (list 'head (arrival (probe-arrivals p) (- head 1)) 'body first))
              (if (and first (>= (- first (probe-connected p)) 300)) 'body-after-delay
                  (list 'connected (probe-connected p) 'body first))))))
  (http-row o "/early, a 100, a 103 with Link, then the final head"
            (get "/early" close)
            (string-append "HTTP/1.1 100 Continue\r\n\r\n"
                           "HTTP/1.1 103 Early Hints\r\nLink: </style.css>; rel=preload; as=style\r\n\r\n"
                           "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nearly\n"))
  (for-each
   (lambda (target)
     (http-row o (string-append target ": not a stream route, 404") (get target close)
               "HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n"))
   '("/pattern/0" "/pattern/01" "/pattern/268435457" "/pattern/600?delay=60001" "/pattern/600?x=1"
     "/pattern/600?delay=" "/pattern" "/early?x=1" "/connects?x=1" "/connection"))
  ;; The proxy's arm: the next CONNECT it answers 200 carries the lines
  ;; /proxy-arm names, once; the one after carries none.
  (test-equal "the CONNECT proxy, armed by /proxy-arm?n=2&line=20: the next tunnel's 200 carries two lines of 20 bytes, then raw's bytes; the one after carries none; /proxy-arm refuses no n, n=100001 and line=12, each 404, and http's /head, HTTP/2's route, is 404"
    (let ((tunnelled (lambda (lines)
                       (list (string-append "HTTP/1.1 200 Connection Established\r\n" lines "\r\n"
                                            "HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n")
                             'eof)))
          (not-found '("HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n" eof)))
      (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
            (tunnelled "x-000001: vvvvvvvv\r\nx-000002: vvvvvvvv\r\n")
            (tunnelled "")
            not-found not-found not-found not-found))
    (let* ((connect (string-append "CONNECT 127.0.0.1:" (number->string (cdr (origin-face o 'raw))) " HTTP/1.1\r\n"
                                   "Host: 127.0.0.1\r\n\r\n" (get "/raw/head")))
           (armed (exchange o 'http (get "/proxy-arm?n=2&line=20" close) 2000))
           (first (exchange o 'http connect 2000))
           (second (exchange o 'http connect 2000)))
      (list armed first second
            (exchange o 'http (get "/proxy-arm" close) 2000)
            (exchange o 'http (get "/proxy-arm?n=100001" close) 2000)
            (exchange o 'http (get "/proxy-arm?n=1&line=12" close) 2000)
            (exchange o 'http (get "/head?n=2" close) 2000))))
  (test-equal "the CONNECT proxy: a tunnel to the raw face, its request sent behind the CONNECT, gets the tunnel's 200, then raw's bytes, then eof, and is counted; a CONNECT to 127.0.0.1:1, no face of the origin, and to another host, each gets a 403, and the end, and is not; /connects tells each count"
    (let ((connects (lambda (n) (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: "
                                                      (number->string (string-length (string-append "connects " (number->string n) "\n")))
                                                      "\r\nConnection: close\r\n\r\nconnects " (number->string n) "\n")
                                       'eof)))
          (refused '("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" eof)))
      (list 'counted
            '("HTTP/1.1 200 Connection Established\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)
            'one-more refused refused 'no-more))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((count (lambda ()
                      (let ((a (exchange o 'http (get "/connects" close) 2000)))
                        (and (pair? a) (string? (car a))
                             (let ((n (string->number (last-word (car a))))) n)))))
             (c0 (count))
             (port (number->string (cdr (origin-face o 'raw))))
             (tunnel (exchange o 'http (string-append "CONNECT 127.0.0.1:" port " HTTP/1.1\r\nHost: 127.0.0.1:" port
                                                      "\r\n\r\n" (get "/raw/content-length"))
                               2000))
             (c1 (count))
             (nowhere (exchange o 'http "CONNECT 127.0.0.1:1 HTTP/1.1\r\nHost: 127.0.0.1:1\r\n\r\n" 2000))
             (elsewhere (exchange o 'http (string-append "CONNECT 127.0.0.2:" port " HTTP/1.1\r\nHost: 127.0.0.2:" port "\r\n\r\n") 2000))
             (c2 (count)))
        (list (if (integer? c0) 'counted c0)
              tunnel
              (if (and (integer? c0) (eqv? c1 (+ c0 1))) 'one-more (list c0 c1))
              nowhere elsewhere
              (if (eqv? c2 c1) 'no-more (list c1 c2))))))

  ;; --- the raw face: the request head's 64 KiB limit, from both sides. The
  ;; padding is counted from the lengths of the text around it, so each head
  ;; is exactly the size its test names. They travel through the probe's
  ;; @FILE: no argument holds 64 KiB of hex.
  (let ((padded (lambda (total)
                  (let ((before "GET /raw/content-length HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Pad: ")
                        (after "\r\n\r\n"))
                    (string-append before
                                   (make-string (- total (string-length before) (string-length after)) #\a)
                                   after)))))
    (test-equal "raw: a head of exactly 65536 bytes, CRLF CRLF included, is read and served"
      '(65536 ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
      (list (string-length (padded 65536)) (exchange o 'raw (padded 65536) 2000)))
    (test-equal "raw: a head of 65537 bytes, CRLF CRLF included, gets the fixed 400"
      (list 65537 bad-request)
      (list (string-length (padded 65537)) (exchange o 'raw (padded 65537) 2000)))
    (test-equal "raw: 65536 bytes with no CRLF CRLF, the most the head may hold, get the fixed 400"
      bad-request
      (exchange o 'raw (make-string 65536 #\a) 2000))
    (test-equal "raw: 70000 bytes with no CRLF CRLF at all get the fixed 400"
      bad-request
      (exchange o 'raw (make-string 70000 #\a) 2000)))

  ;; --- the well-formed face: status, as measured on Node 20.10.0 and 24.18.0
  (for-each
   (lambda (row)
     (http-row o (string-append "/status/" (car row)) (get (string-append "/status/" (car row)) close)
               (cadr row)))
   '(("200" "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n")
     ("204" "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
     ("205" "HTTP/1.1 205 Reset Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
     ("299" "HTTP/1.1 299 unknown\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 299\n")
     ("304" "HTTP/1.1 304 Not Modified\r\nConnection: close\r\n\r\n")
     ("418" "HTTP/1.1 418 I'm a Teapot\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 418\n")
     ("503" "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 503\n")
     ("599" "HTTP/1.1 599 unknown\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 599\n")))

  ;; --- the well-formed face: every redirect status, Location decoded
  (for-each
   (lambda (row)
     (http-row o (string-append "/redirect/" (car row))
               (get (string-append "/redirect/" (car row) "?to=%2Fstatus%2F200") close)
               (cadr row)))
   '(("300" "HTTP/1.1 300 Multiple Choices\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 300\n")
     ("301" "HTTP/1.1 301 Moved Permanently\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 301\n")
     ("302" "HTTP/1.1 302 Found\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 302\n")
     ("303" "HTTP/1.1 303 See Other\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 303\n")
     ("304" "HTTP/1.1 304 Not Modified\r\nLocation: /status/200\r\nConnection: close\r\n\r\n")
     ("305" "HTTP/1.1 305 Use Proxy\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 305\n")
     ("306" "HTTP/1.1 306 unknown\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 306\n")
     ("307" "HTTP/1.1 307 Temporary Redirect\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 307\n")
     ("308" "HTTP/1.1 308 Permanent Redirect\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 308\n")))
  (http-row o "/redirect/302 to an absolute URL"
            (get "/redirect/302?to=http%3A%2F%2F127.0.0.1%3A1%2Fa%3Fb%3Dc" close)
            "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/a?b=c\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 302\n")

  ;; --- the well-formed face: chunked, echo, and everything else
  (http-row o "/chunked" (get "/chunked" close)
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n6\r\nalpha\n\r\n5\r\nbeta\n\r\n6\r\ngamma\n\r\n0\r\n\r\n")
  (http-row o "/echo, a POST with headers and a body"
            (string-append "POST /echo?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Two: a\r\nx-lower: b\r\n"
                           "Content-Length: 4\r\nConnection: close\r\n\r\nbody")
            (string-append "HTTP/1.1 200 OK\r\nContent-Length: 101\r\nConnection: close\r\n\r\n"
                           "POST /echo?x=1 HTTP/1.1\nHost: 127.0.0.1\nX-Two: a\nx-lower: b\n"
                           "Content-Length: 4\nConnection: close\n\nbody"))
  ;; --- the well-formed face as a stand-in proxy: a target in absolute form
  (http-row o "an absolute-form target, as a proxy is sent one: /echo routed by its path, the first line the target as it came"
            "GET http://127.0.0.1:1/echo?x=1 HTTP/1.1\r\nHost: 127.0.0.1:1\r\nConnection: close\r\n\r\n"
            (string-append "HTTP/1.1 200 OK\r\nContent-Length: 78\r\nConnection: close\r\n\r\n"
                           "GET http://127.0.0.1:1/echo?x=1 HTTP/1.1\nHost: 127.0.0.1:1\nConnection: close\n\n"))
  (http-row o "an absolute-form target to /status/200 is routed by its path"
            "GET http://127.0.0.1:1/status/200 HTTP/1.1\r\nHost: 127.0.0.1:1\r\nConnection: close\r\n\r\n"
            "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n")
  (for-each
   (lambda (target)
     (http-row o (string-append target ", in absolute form, is 404")
               (string-append "GET " target " HTTP/1.1\r\nHost: 127.0.0.1:1\r\nConnection: close\r\n\r\n")
               "HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n"))
   '("http://127.0.0.1:1" "http://127.0.0.1:1?x=1" "https://127.0.0.1:1/status/200"
     "http://127.0.0.1:1/nowhere"))
  (for-each
   (lambda (target)
     (http-row o (string-append target ": anything else is 404") (get target close)
               "HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n"))
   '("/nowhere" "/status/199" "/status/600" "/status/200?x=1" "/redirect/309?to=%2F"
     "/redirect/302" "/redirect/302?to=" "/redirect/302?to=%zz" "/redirect/302?to=a%0Db"
     "/redirect/302?to=a&b=c" "/chunked?x=1"))
  (test-equal "http: a request without Connection: close gets Connection: keep-alive, and the connection stays open"
    '("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: keep-alive\r\n\r\nstatus 200\n" timeout)
    (exchange o 'http (get "/status/200") 200))
  (http-row o "an HTTP/1.0 request, which Node closes"
            "GET /status/200 HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n"
            "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n")
  (http-row o "garbage, which Node refuses" "garbage\r\n\r\n"
            "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")

  ;; --- lifecycle: loopback faces, and what the announcement says
  (test-equal "loopback only: every face's announced address is 127.0.0.1"
    '("127.0.0.1" "127.0.0.1" "127.0.0.1")
    (map (lambda (face) (car (origin-face o face))) '(http raw h2c)))
  (test-equal "the announcement's node is the version the Node that ran it reports"
    (list 0 (string-append (origin-node o) "\n") "")
    (capture-command (list node "--version")))
  ;; On Linux all of 127/8 is loopback, so a face bound to any address but
  ;; 127.0.0.1 alone (0.0.0.0, ::) takes a connection to 127.0.0.2. Elsewhere
  ;; 127.0.0.2 is not a loopback address by default, so the check says
  ;; nothing there.
  (unless linux? (test-skip 1))
  (test-equal "loopback by connection, on Linux: each face refuses 127.0.0.2, so it listens on 127.0.0.1 alone (skipped elsewhere, where 127.0.0.2 is no loopback address by default)"
    '((refused "ECONNREFUSED") (refused "ECONNREFUSED") (refused "ECONNREFUSED"))
    (map (lambda (face) (probe-at "127.0.0.2" (cdr (origin-face o face)) 200)) '(http raw h2c)))

  ;; --- lifecycle: bad clients end only their own connection. The probe,
  ;; with --reset, sends part of a request head, then resets: a destroy()
  ;; would reach the origin as a FIN (measured).
  (for-each
   (lambda (face)
     (test-equal (string-append "a bad client: a reset mid-request on the " (symbol->string face)
                                " face ends only its connection, and the next request is served")
       (list '("" reset-sent)
             (if (eq? face 'raw)
                 '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)
                 '("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" eof)))
       (guard (e (#t (list 'raised (describe e))))
         (let ((reset (wire-probe-reset o face (octets "GET /raw/content-length HTTP/1.1\r\nHost: 127.0.0.1\r\n"))))
           ;; Time for the origin to take the reset in, and die of it if it
           ;; would.
           (pause-ms 100)
           (list (list (latin-1 (probe-bytes reset)) (probe-end reset))
                 (if (eq? face 'raw)
                     (exchange o 'raw (get "/raw/content-length") 2000)
                     (exchange o 'http (get "/status/200" close) 2000)))))))
   '(raw http))
  (test-equal "a bad client: one that vanishes during a drip ends only its connection, and the next request is served"
    '(("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n" timeout)
      ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
    (let ((vanished (exchange o 'raw (get "/raw/drip?bytes=3&gap=200") 50)))
      ;; Past the drip's next byte, which would be written to a closed
      ;; connection.
      (pause-ms 300)
      (list vanished (exchange o 'raw (get "/raw/content-length") 2000))))
  ;; --- lifecycle: a client that half-closes after its request is served whole
  (for-each
   (lambda (row)
     (test-equal (string-append "a half-closing client: " (car row)
                                ", sent with a FIN after it, gets the whole response, and the next request is served")
       (list (cadddr row) (list-ref row 5))
       (guard (e (#t (list 'raised (describe e))))
         (let ((p (wire-probe-half-close o (cadr row) (octets (caddr row)) 2000)))
           (list (list (latin-1 (probe-bytes p)) (probe-end p))
                 (exchange o (cadr row) (list-ref row 4) 2000))))))
   (list (list "a raw drip" 'raw (get "/raw/drip?bytes=3&gap=20")
               '("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc" eof)
               (get "/raw/content-length") '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
         (list "raw content-length" 'raw (get "/raw/content-length")
               '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)
               (get "/raw/content-length") '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
         (list "http /status/200" 'http (get "/status/200")
               '("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: keep-alive\r\n\r\nstatus 200\n" eof)
               (get "/status/200" close)
               '("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" eof))))
  (sink-scenarios o)
  (parts-scenarios o)
  (json-scenarios o)
  (duplex-scenarios o))

;; --- the parts route --------------------------------------------------------------
;; The bodies are built here, byte by byte, and their SHA-256 values were
;; computed on the host (sha256sum, and Python's hashlib, agreeing), never
;; by the origin.
(define sha-parts-a "6454d8e0ec08abcb72817eedcf3a0387bc99943457ed00a3c524da70615a4792")
(define sha-parts-b "8ef0beb3fac58a2130d1bc15fc7b3970d6f34b8b0e3a30b0312902ae1c602205")
;; the first 16 hex digits of each part's: "hi|\\" then 0x01; the pattern's
;; 300 bytes; "abc"
(define sha16-hi "2430cdfdae1a3ce9")
(define sha16-p300 "43f9b5d59eb10881")
(define sha16-abc "ba7816bf8f01cfea")

;; parts-body-a : String
;; Two parts, boundary BND, then the closing delimiter and CR LF: a, its data
;; hi|, a backslash and 0x01; f, a filename and a type, the pattern's 300
;; bytes.
(define parts-body-a
  (string-append "--BND\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nhi|\\" (string (integer->char 1))
                 "\r\n--BND\r\nContent-Disposition: form-data; name=\"f\"; filename=\"p.bin\"\r\n"
                 "Content-Type: application/octet-stream\r\n\r\n" (pattern-text 300) "\r\n--BND--\r\n"))

;; parts-body-b : String
;; Four bytes of preamble, then a part the body ends inside.
(define parts-body-b "xx\r\n--BND\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nabc")

;; parts-report-a : String String -> String
;; /parts' report for parts-body-a, on FACE, its Expect EXPECT.
(define (parts-report-a face expect)
  (string-append "parts " face " method=POST cl=478 te=- expect=" expect
                 " ct=multipart/form-data;_boundary=BND bytes=478 sha256=" sha-parts-a
                 " boundary=BND preamble=0 closed=1 epilogue=2 count=2\n"
                 "part 0 headers=Content-Disposition: form-data; name=\"a\" len=5 sha256=" sha16-hi
                 " pattern=bad@0 data=hi\\x7c\\\\\\x01\n"
                 "part 1 headers=Content-Disposition: form-data; name=\"f\"; filename=\"p.bin\"|"
                 "Content-Type: application/octet-stream len=300 sha256=" sha16-p300 " pattern=ok data=-\n"))

;; parts-report-b : String -> String
(define (parts-report-b face)
  (string-append "parts " face " method=PUT cl=58 te=- expect=- ct=multipart/form-data;_boundary=BND bytes=58 sha256="
                 sha-parts-b " boundary=BND preamble=4 closed=0 epilogue=- count=1\n"
                 "part 0 headers=Content-Disposition: form-data; name=\"a\" len=3 sha256=" sha16-abc
                 " pattern=bad@0 data=abc unterminated\n"))

;; parts-answer : String String ... -> String
;; The http face's whole 200 for REPORT, with Connection: close, after the
;; header lines PADS.
(define (parts-answer report . pads)
  (apply string-append "HTTP/1.1 200 OK\r\n"
         (append pads
                 (list "Content-Length: " (number->string (string-length report))
                       "\r\nConnection: close\r\n\r\n" report))))

;; parts-503 : String -> String
;; The http face's whole 503 for REPORT, with Connection: close.
(define (parts-503 report)
  (string-append "HTTP/1.1 503 Service Unavailable\r\nContent-Length: " (number->string (string-length report))
                 "\r\nConnection: close\r\n\r\n" report))

(define (parts-scenarios o)
  (define ct "Content-Type: multipart/form-data; boundary=BND\r\n")
  (define (sized body) (string-append "Content-Length: " (number->string (string-length body)) "\r\n"))
  (test-equal "http /parts, two parts by Content-Length: the report, whole, each part's headers, length, hash, pattern and escaped data, then eof; /seen reads 1"
    (list (list (parts-answer (parts-report-a "http" "-")) 'eof) (seen-text 1))
    (let* ((r (exchange o 'http (string-append (post "/parts?key=pt-a" ct (sized parts-body-a) close) parts-body-a)
                        2000))
           (seen (seen-of o "pt-a")))
      (list r seen)))
  (test-equal "http /parts, a PUT whose body ends inside its one part, after a preamble of 4 bytes: preamble=4, closed=0, the part unterminated"
    (list (parts-answer (parts-report-b "http")) 'eof)
    (exchange o 'http (string-append "PUT /parts?key=pt-b HTTP/1.1\r\nHost: 127.0.0.1\r\n" ct (sized parts-body-b)
                                     close "\r\n" parts-body-b)
              2000))
  (test-equal "http /parts, a body with no boundary: boundary=-, no part read"
    (list (parts-answer (string-append "parts http method=POST cl=3 te=- expect=- ct=text/plain bytes=3 sha256="
                                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                                       " boundary=- preamble=- closed=0 epilogue=- count=0\n"))
          'eof)
    (exchange o 'http (string-append (post "/parts?key=pt-none" "Content-Type: text/plain\r\n" "Content-Length: 3\r\n"
                                           close)
                                     "abc")
              2000))
  (test-equal "http /parts?lines=6: the answer carries 6 header lines in all, x-p0 to x-p3 before Content-Length and Connection"
    (list (parts-answer (parts-report-a "http" "-") "x-p0: v\r\n" "x-p1: v\r\n" "x-p2: v\r\n" "x-p3: v\r\n") 'eof)
    (exchange o 'http (string-append (post "/parts?key=pt-lines&lines=6" ct (sized parts-body-a) close) parts-body-a)
              2000))
  (test-equal "http /parts with Expect: 100-continue: a 100 at once, then the report"
    (list (string-append "HTTP/1.1 100 Continue\r\n\r\n" (parts-answer (parts-report-a "http" "100-continue")))
          'eof)
    (exchange o 'http (string-append (post "/parts?key=pt-continue" ct (sized parts-body-a)
                                           "Expect: 100-continue\r\n" close)
                                     parts-body-a)
              2000))
  (test-equal "http /parts?hold=1 with Expect: counted as its head arrives, its 100 and its report only once /raw/release names its key, 800 ms on; held without Expect, answered at once"
    (list (seen-text 1) released-text 'held-until-released
          (list (string-append "HTTP/1.1 100 Continue\r\n\r\n" (parts-answer (parts-report-a "http" "100-continue")))
                'eof)
          (list (parts-answer (parts-report-a "http" "-")) 'eof))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((finish (spawned-probe o 'http (string-append (post "/parts?key=pt-hold&hold=1" ct (sized parts-body-a)
                                                                 "Expect: 100-continue\r\n" close)
                                                           parts-body-a)
                                    5000))
             (seen (begin (pause-ms 400) (seen-of o "pt-hold")))
             (released (begin (pause-ms 400) (exchange o 'raw (get "/raw/release?key=pt-hold") 2000)))
             (p (finish))
             (first (arrival (probe-arrivals p) 0))
             (unheld (exchange o 'http (string-append (post "/parts?key=pt-unheld&hold=1" ct (sized parts-body-a) close)
                                                      parts-body-a)
                               2000)))
        (list seen released
              (if (and first (>= first 700)) 'held-until-released (list 'first-byte-at first))
              (list (latin-1 (probe-bytes p)) (probe-end p))
              unheld))))
  (test-equal "http /parts?fail=2: the first two requests of its key answered 503, each with its report, the third 200"
    (list (list (parts-503 (parts-report-a "http" "-")) 'eof) (list (parts-503 (parts-report-a "http" "-")) 'eof)
          (list (parts-answer (parts-report-a "http" "-")) 'eof))
    (in-order (lambda (n)
                (exchange o 'http (string-append (post "/parts?key=pt-fail&fail=2" ct (sized parts-body-a) close)
                                                 parts-body-a)
                          2000))
              '(1 2 3)))
  (test-equal "http /parts: a query it refuses is 404, and counts nothing: no key, lines=1, lines=100001, hold twice, fail=0, fail=11, another name"
    (list not-found-close not-found-close not-found-close not-found-close not-found-close not-found-close
          not-found-close (seen-text 0))
    (let* ((rows (in-order (lambda (target)
                             (exchange o 'http (string-append (post target "Content-Length: 0\r\n" close)) 2000))
                      '("/parts" "/parts?key=pt-refused&lines=1" "/parts?key=pt-refused&lines=100001"
                        "/parts?key=pt-refused&hold=1&hold=1" "/parts?key=pt-refused&fail=0"
                        "/parts?key=pt-refused&fail=11" "/parts?key=pt-refused&x=1")))
           (seen (seen-of o "pt-refused")))
      (append rows (list seen)))))

;; --- the JSON route ----------------------------------------------------------------
;; Each answer's body is written out here, by the route's rule, as the bytes
;; JSON.stringify writes; each request is built here, byte by byte.

;; json-head : String String -> String
;; The http face's head of STATUS, its status line's code and reason, for
;; the JSON BODY, its bytes each a char, as Latin-1 reads them, with
;; Connection: close.
(define (json-head status body)
  (string-append "HTTP/1.1 " status "\r\nContent-Type: application/json\r\nContent-Length: "
                 (number->string (string-length body)) "\r\nConnection: close\r\n\r\n"))

;; json-answer : String String -> (List String Symbol)
;; The http face's whole answer of STATUS with the JSON BODY, its bytes
;; each a char, as Latin-1 reads them: its head, then BODY; then eof.
(define (json-answer status body)
  (list (string-append (json-head status body) body) 'eof))

;; json-h2 : String
;; Node's own HTTP/2 client, run as node -e JSON-H2 HOST PORT against h2c:
;; on one session, one after another, a GET of /json?page=2 with Accept:
;; application/json; a POST of /json with that Accept, Content-Type:
;; application/json and the body [1, 2]; and a GET of /json with no Accept.
;; It prints one line, a list of each answer as (STATUS TYPE LENGTH BODY),
;; TYPE and LENGTH its content-type and content-length, or #f, and BODY a
;; string, as Chez reads it, and exits 0; an error prints (failed CODE), and
;; 10 s on it prints (deadline); either exits 1.
(define json-h2
  (string-append
   "const http2 = require('node:http2');"
   "const [host, port] = process.argv.slice(1);"
   "const fail = (code) => { console.log(`(failed ${code})`); process.exit(1); };"
   "setTimeout(() => { console.log('(deadline)'); process.exit(1); }, 10000);"
   "const session = http2.connect(`http://${host}:${port}`);"
   "session.on('error', (err) => fail(err.code));"
   "const field = (v) => (v === undefined ? '#f' : JSON.stringify(v));"
   "const ask = (headers, body) => new Promise((resolve) => {"
   "  const s = session.request(headers); let head = null; const chunks = [];"
   "  s.on('response', (h) => { head = h; });"
   "  s.on('data', (c) => chunks.push(c));"
   "  s.on('end', () => resolve(`(${head[':status']} ${field(head['content-type'])} ${field(head['content-length'])} ${JSON.stringify(Buffer.concat(chunks).toString('latin1'))})`));"
   "  s.on('error', (err) => fail(err.code));"
   "  s.end(body);"
   "});"
   "(async () => {"
   "  const out = [];"
   "  out.push(await ask({ ':method': 'GET', ':path': '/json?page=2', accept: 'application/json' }));"
   "  out.push(await ask({ ':method': 'POST', ':path': '/json', accept: 'application/json',"
   "                       'content-type': 'application/json' }, '[1, 2]'));"
   "  out.push(await ask({ ':method': 'GET', ':path': '/json' }));"
   "  session.close(); console.log(`(${out.join(' ')})`); process.exit(0);"
   "})().catch((err) => fail(err.code));"))

(define (json-scenarios o)
  (define accept-json "Accept: application/json\r\n")
  (define ct-json "Content-Type: application/json\r\n")
  ;; with-body : String String String String ... -> String
  ;; METHOD of TARGET, with these header lines after Host, then
  ;; Content-Length, Connection: close, and BODY.
  (define (with-body method target body . headers)
    (apply string-append method " " target " HTTP/1.1\r\nHost: 127.0.0.1\r\n"
           (append headers (list "Content-Length: " (number->string (string-length body)) "\r\n" close "\r\n"
                                 body))))
  (define (json-row name request want)
    (test-equal (string-append "http /json, " name ": the whole answer, then eof")
      want
      (exchange o 'http request 2000)))
  (define post-ada "{ \"name\": \"Ada\", \"n\": [1, 2.5, null, true] }")
  (define ada-201
    (json-answer "201 Created"
                 (string-append "{\"method\":\"POST\",\"target\":\"/json?x=1\",\"content-type\":\"application/json\","
                                "\"bytes\":44,\"json\":{\"name\":\"Ada\",\"n\":[1,2.5,null,true]}}")))
  ;; --- Accept
  (json-row "a GET with Accept: application/json: 200, its method, target and Accept"
            (get "/json" accept-json close)
            (json-answer "200 OK" "{\"method\":\"GET\",\"target\":\"/json\",\"accept\":\"application/json\"}"))
  (for-each
   (lambda (row)
     (json-row (string-append "a GET with " (car row) ": 406, the Accept it got")
               (apply get "/json" (append (cadr row) (list close)))
               (json-answer "406 Not Acceptable"
                            (string-append "{\"error\":\"not-acceptable\",\"accept\":" (caddr row) "}"))))
   '(("no Accept" () "null")
     ("Accept: */* alone, which libcurl sends unless told" ("Accept: */*\r\n") "\"*/*\"")
     ("Accept: text/html" ("Accept: text/html\r\n") "\"text/html\"")
     ("Accept: application/json-seq, a type that only begins application/json"
      ("Accept: application/json-seq\r\n") "\"application/json-seq\"")))
  (for-each
   (lambda (row)
     (json-row (string-append "a GET with " (car row) ": 200, the Accept it got")
               (apply get "/json" (append (cadr row) (list close)))
               (json-answer "200 OK" (string-append "{\"method\":\"GET\",\"target\":\"/json\",\"accept\":"
                                                    (caddr row) "}"))))
   '(("application/json's parameters, q among them" ("Accept: application/json; q=0.5;v=1\r\n")
      "\"application/json; q=0.5;v=1\"")
     ("several ranges, application/json the second" ("Accept: text/html,  application/json\t,*/*\r\n")
      "\"text/html,  application/json\\t,*/*\"")
     ("Application/JSON, in another case" ("Accept: Application/JSON\r\n") "\"Application/JSON\"")
     ("two Accept lines, application/json the second's, joined by a comma"
      ("Accept: text/html\r\n" "accept: application/json\r\n") "\"text/html, application/json\"")
     ("Accept: application/json;q=0, its q ignored as every parameter is" ("Accept: application/json;q=0\r\n")
      "\"application/json;q=0\"")
     ("Accept and Content-Type: text/plain, which a GET's answer never reads"
      ("Accept: application/json\r\n" "Content-Type: text/plain\r\n") "\"application/json\"")))
  (json-row "a GET of /json?page=2&q=a%20b: 200, its target as received, the query in it"
            (get "/json?page=2&q=a%20b" accept-json close)
            (json-answer "200 OK"
                         "{\"method\":\"GET\",\"target\":\"/json?page=2&q=a%20b\",\"accept\":\"application/json\"}"))
  (let ((twice (json-answer "200 OK" "{\"method\":\"GET\",\"target\":\"/json?twice=1\",\"accept\":\"application/json\"}")))
    (test-equal "http /json: the same GET twice gets the same bytes, as nothing is kept"
      (list twice twice)
      (in-order (lambda (n) (exchange o 'http (get "/json?twice=1" accept-json close) 2000)) '(1 2))))
  (json-row "a HEAD with Accept: the 200's head, its Content-Type and its Content-Length, and no body"
            (string-append "HEAD /json HTTP/1.1\r\nHost: 127.0.0.1\r\n" accept-json close "\r\n")
            (list (json-head "200 OK" "{\"method\":\"HEAD\",\"target\":\"/json\",\"accept\":\"application/json\"}")
                  'eof))
  ;; --- a body: Content-Type, then the body
  (json-row "a POST with both headers and a JSON body: 201, the body parsed, its byte count, and what came with it"
            (with-body "POST" "/json?x=1" post-ada accept-json ct-json)
            ada-201)
  (test-equal "http /json: the same POST twice gets the same bytes, as nothing is kept"
    (list ada-201 ada-201)
    (in-order (lambda (n) (exchange o 'http (with-body "POST" "/json?x=1" post-ada accept-json ct-json) 2000))
              '(1 2)))
  (for-each
   (lambda (row)
     (json-row (string-append "a POST with " (car row) ": 201, the Content-Type it got")
               (with-body "POST" "/json" "[]" accept-json (cadr row))
               (json-answer "201 Created" (string-append "{\"method\":\"POST\",\"target\":\"/json\",\"content-type\":"
                                                         (caddr row) ",\"bytes\":2,\"json\":[]}"))))
   '(("Content-Type: application/json; charset=utf-8" "Content-Type: application/json; charset=utf-8\r\n"
      "\"application/json; charset=utf-8\"")
     ("Content-Type: Application/Json, in another case" "Content-Type: Application/Json\r\n"
      "\"Application/Json\"")))
  (json-row "a PATCH with both headers: 201, as a POST is"
            (with-body "PATCH" "/json" "{}" accept-json ct-json)
            (json-answer "201 Created"
                         "{\"method\":\"PATCH\",\"target\":\"/json\",\"content-type\":\"application/json\",\"bytes\":2,\"json\":{}}"))
  (json-row "a PUT of malformed JSON with both headers: 400, not-json, as a POST's is"
            (with-body "PUT" "/json" "[1," accept-json ct-json)
            (json-answer "400 Bad Request" "{\"error\":\"not-json\",\"bytes\":3}"))
  (json-row "a PUT of JSON with both headers: 201, the body parsed"
            (with-body "PUT" "/json" "[1, {\"a\": null}]" accept-json ct-json)
            (json-answer "201 Created"
                         "{\"method\":\"PUT\",\"target\":\"/json\",\"content-type\":\"application/json\",\"bytes\":16,\"json\":[1,{\"a\":null}]}"))
  ;; U+00E9 is C3 A9 in UTF-8, and U+1F600 F0 9F 98 80; JSON.stringify
  ;; writes both as they are, so the answer's UTF-8 holds the same bytes.
  (json-row "a POST of a string holding U+00E9 and U+1F600, as UTF-8: 201, the body's 14 bytes, and the string back as UTF-8 bytes"
            (with-body "POST" "/json" "{\"s\":\"\xc3;\xa9;\xf0;\x9f;\x98;\x80;\"}" accept-json ct-json)
            (json-answer "201 Created"
                         (string-append "{\"method\":\"POST\",\"target\":\"/json\",\"content-type\":\"application/json\","
                                        "\"bytes\":14,\"json\":{\"s\":\"\xc3;\xa9;\xf0;\x9f;\x98;\x80;\"}}")))
  (json-row "a POST with two Content-Type lines, application/json then text/plain: 415, the two read joined"
            (with-body "POST" "/json" "{}" accept-json ct-json "Content-Type: text/plain\r\n")
            (json-answer "415 Unsupported Media Type"
                         "{\"error\":\"unsupported-media-type\",\"content-type\":\"application/json, text/plain\"}"))
  (json-row "a PUT with no Content-Type: 415, as a POST's is"
            (with-body "PUT" "/json" "{}" accept-json)
            (json-answer "415 Unsupported Media Type" "{\"error\":\"unsupported-media-type\",\"content-type\":null}"))
  (json-row "a DELETE with a body that is no JSON and no Content-Type: 200, its body unread"
            (with-body "DELETE" "/json" "x" accept-json)
            (json-answer "200 OK" "{\"method\":\"DELETE\",\"target\":\"/json\",\"accept\":\"application/json\"}"))
  (for-each
   (lambda (row)
     (json-row (string-append "a POST of {} with " (car row) ": 415, the Content-Type it got")
               (apply with-body "POST" "/json" "{}" accept-json (cadr row))
               (json-answer "415 Unsupported Media Type"
                            (string-append "{\"error\":\"unsupported-media-type\",\"content-type\":" (caddr row) "}"))))
   '(("no Content-Type" () "null")
     ("Content-Type: text/plain" ("Content-Type: text/plain\r\n") "\"text/plain\"")
     ("Content-Type: application/json-patch+json" ("Content-Type: application/json-patch+json\r\n")
      "\"application/json-patch+json\"")))
  (for-each
   (lambda (row)
     (json-row (string-append "a POST with both headers and " (car row) ": 400, " (cadr row) ", its byte count")
               (with-body "POST" "/json" (caddr row) accept-json ct-json)
               (json-answer "400 Bad Request"
                            (string-append "{\"error\":\"" (cadr row) "\",\"bytes\":"
                                           (number->string (string-length (caddr row))) "}"))))
   '(("a trailing comma" "not-json" "{\"a\":1,}")
     ("no body" "not-json" "")
     ("a byte-order mark before {}" "not-json" "\xef;\xbb;\xbf;{}")
     ("a string holding the byte 0xFF" "not-utf-8" "\"\xff;\"")
     ("a string holding ED A0 80, an encoded surrogate" "not-utf-8" "\"\xed;\xa0;\x80;\"")))
  ;; --- the rules' order
  (json-row "a POST with no Accept, Content-Type: text/plain, and a body that is no JSON: 406, Accept read first"
            (with-body "POST" "/json" "{" "Content-Type: text/plain\r\n")
            (json-answer "406 Not Acceptable" "{\"error\":\"not-acceptable\",\"accept\":null}"))
  (json-row "a POST with Accept, Content-Type: text/plain, and a body that is no JSON: 415, Content-Type read before the body"
            (with-body "POST" "/json" "{" accept-json "Content-Type: text/plain\r\n")
            (json-answer "415 Unsupported Media Type"
                         "{\"error\":\"unsupported-media-type\",\"content-type\":\"text/plain\"}"))
  ;; --- HTTP/2, on h2c, through Node's own client
  (test-equal "h2c /json, through Node's client: a GET with Accept 200, its :path whole, query in, as target; a POST 201; a GET without Accept 406; each content-type application/json and its content-length"
    (map (lambda (row)
           (list (car row) "application/json" (number->string (string-length (cadr row))) (cadr row)))
         '((200 "{\"method\":\"GET\",\"target\":\"/json?page=2\",\"accept\":\"application/json\"}")
           (201 "{\"method\":\"POST\",\"target\":\"/json\",\"content-type\":\"application/json\",\"bytes\":6,\"json\":[1,2]}")
           (406 "{\"error\":\"not-acceptable\",\"accept\":null}")))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((f (origin-face o 'h2c))
             (r (capture-command (list node "-e" json-h2 (car f) (number->string (cdr f))))))
        (if (= (car r) 0)
            (read (open-string-input-port (cadr r)))
            (list 'exit r))))))

;; --- the sinks ------------------------------------------------------------------
;; Each test has keys of its own: the counts live as long as the origin, and
;; every face shares them. The SHA-256 values were computed on the host
;; (sha256sum, and Python's hashlib, agreeing), never by the origin.
(define sha-p10 "1f825aa2f0020ef7cf91dfa30da4668d791c5d4824fc8e41354b89ec05795ab3")
(define sha-p20 "e7aebf577f60412f0312d442c70a1fa6148c090bf5bab404caec29482ae779e8")
;; the pattern's 10 bytes, byte 7 an x
(define sha-p10-bad7 "140d0e63c9a8ee404243d667825bb70b26fdb28e3dbed1daef57f17fe12fc931")
(define sha-hello-world "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
(define sha-hello "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
(define sha-empty "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

;; The raw sink's head, and the http face's for a client that closes.
(define raw-sink-head "HTTP/1.1 200 OK\r\nContent-Length: L\r\nConnection: close\r\n\r\n")
(define http-sink-head "HTTP/1.1 200 OK\r\nContent-Length: L\r\nConnection: close\r\n\r\n")

;; seen-text : Natural -> (List String Symbol)
;; The http face's answer to /seen with Connection: close, C the count.
(define (seen-text c)
  (let ((body (string-append "seen " (number->string c) "\n")))
    (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: " (number->string (string-length body))
                         "\r\nConnection: close\r\n\r\n" body)
          'eof)))

;; sunk-text : Natural -> (List String Symbol)
;; /raw/sunk's whole answer for N bytes read, and its end.
(define (sunk-text n)
  (let ((body (string-append "sunk " (number->string n) "\n")))
    (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: " (number->string (string-length body))
                         "\r\nConnection: close\r\n\r\n" body)
          'eof)))

;; released-text : (List String Symbol)
;; /raw/release's whole answer, and its end.
(define released-text
  '("HTTP/1.1 200 OK\r\nContent-Length: 9\r\nConnection: close\r\n\r\nreleased\n" eof))

;; spawned-probe : Origin Symbol String Natural -> (-> Probe)
;; A wire probe of TEXT to FACE, idle bound IDLE ms, started through
;; open-process-ports, not capture-command, so that another probe can run
;; while it waits: on macOS, two threads' system calls run one after the
;; other, so a release made 800 ms into a 5 s probe, both through
;; capture-command, arrived after it. Answers a thunk that reads the probe's
;; output to its end, closes its pipes, and parses it.
(define (spawned-probe o face text idle)
  (let-values (((to from err pid)
                (open-process-ports
                 (string-append "exec " (shell-word node) " tests/wire-probe.mjs --deadline "
                                (number->string (wire-probe-deadline))
                                " 127.0.0.1 " (number->string (cdr (origin-face o face)))
                                " " (shell-word (hex text)) " " (number->string idle))
                 (buffer-mode block) #f)))
    (lambda ()
      (let ((out (get-bytevector-all from)))
        (for-each (lambda (port) (guard (e (#t #f)) (close-port port))) (list to from err))
        (parse-wire-probe (if (eof-object? out) "" (latin-1 out)))))))

;; seen-of : Origin String -> (List String Symbol)
(define (seen-of o key)
  (exchange o 'http (get (string-append "/seen?key=" key) close) 2000))

(define not-found-close
  '("HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n" eof))

(define ok-kept "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: keep-alive\r\n\r\nok\n")

(define (sink-scenarios o)
  (define p10 (pattern-text 10))
  (define bad7 (string-append (substring p10 0 7) "x" (substring p10 8 10)))

  ;; --- the raw face: /raw/sink. Its head and body sent in one write arrive
  ;; in one socket data event, the head's, so the body's one arrival is at
  ;; 0.0 ms.
  (test-equal "raw /raw/sink, 10 bytes of the pattern by Content-Length, sent with the head: the summary, whole, one arrival at 0.0 ms, then eof"
    (list (string-append raw-sink-head "sink raw method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10
                         " pattern=ok arrivals=1 gap=~@0 seen=1\n")
          'eof '("0.0"))
    (sink-exchange o 'raw (string-append (post "/raw/sink?key=rs-sized" "Content-Length: 10\r\n") p10) 2000))
  (test-equal "raw /raw/sink?list=1, a chunked body with an extension and a trailer: its decoded bytes summed up and listed, the framing dropped"
    (list (string-append raw-sink-head "sink raw method=POST cl=- te=chunked expect=- ct=- bytes=11 sha256="
                         sha-hello-world " pattern=bad@0 arrivals=1 gap=~@0 seen=1 list=~:11\n")
          'eof '("0.0" "0.0"))
    (sink-exchange o 'raw (string-append (post "/raw/sink?key=rs-chunked&list=1" "Transfer-Encoding: chunked\r\n")
                                         "5;name=value\r\nhello\r\n6\r\n world\r\n0;last\r\nX-Trailer: done\r\n\r\n")
                   2000))
  ;; The pattern's first 20 bytes hold an LF at 10 and a CR at 13: a chunk
  ;; is read by its size, not by lines. Its size in upper case, 0C, and
  ;; Chunked framing in any case, te= the value as sent.
  (test-equal "raw /raw/sink, the pattern's 20 bytes in two chunks, one holding a CR and an LF: pattern=ok, and the SHA-256 of the 20 bytes"
    (list (string-append raw-sink-head "sink raw method=POST cl=- te=Chunked expect=- ct=- bytes=20 sha256=" sha-p20
                         " pattern=ok arrivals=1 gap=~@0 seen=1\n")
          'eof '("0.0"))
    (let ((p20 (pattern-text 20)))
      (sink-exchange o 'raw (string-append (post "/raw/sink?key=rs-chunks" "Transfer-Encoding: Chunked\r\n")
                                           "0C\r\n" (substring p20 0 12) "\r\n8;x=y\r\n" (substring p20 12 20)
                                           "\r\n0\r\n\r\n")
                     2000)))
  ;; Up to the last chunk's size line with the head, its trailer 300 ms on:
  ;; the answer waits for the trailers' end.
  (test-equal "raw /raw/sink, a chunked body whose trailer comes 300 ms after its last chunk: the summary only once the trailers have ended"
    (list (list (string-append raw-sink-head "sink raw method=POST cl=- te=chunked expect=- ct=- bytes=5 sha256=" sha-hello
                               " pattern=bad@0 arrivals=1 gap=~@0 seen=1\n")
                'eof)
          'after-the-trailer)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((first (string-append (post "/raw/sink?key=rs-trailer" "Transfer-Encoding: chunked\r\n") "5\r\nhello\r\n0\r\n"))
             (p (split-probe o 'raw (string-append first "X-Trailer: done\r\n\r\n") (string-length first) 300 2000))
             (at (arrival (probe-arrivals p) 0)))
        (list (list (car (shape-response (latin-1 (probe-bytes p)))) (probe-end p))
              (if (and at (>= (- at (probe-connected p)) 300)) 'after-the-trailer
                  (list 'connected (probe-connected p) 'first at))))))
  (test-equal "raw /raw/sink, a GET with no framing: no body, the empty SHA-256, no arrival, gap=-"
    (list (string-append raw-sink-head "sink raw method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                         " pattern=ok arrivals=0 gap=- seen=1\n")
          'eof '())
    (sink-exchange o 'raw (get "/raw/sink?key=rs-none") 2000))
  (test-equal "raw /raw/sink, 10 bytes, byte 7 an x: pattern=bad@7, and that body's SHA-256"
    (list (string-append raw-sink-head "sink raw method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10-bad7
                         " pattern=bad@7 arrivals=1 gap=~@0 seen=1\n")
          'eof '("0.0"))
    (sink-exchange o 'raw (string-append (post "/raw/sink?key=rs-bad" "Content-Length: 10\r\n") bad7) 2000))
  ;; Content-Type twice, its name in two cases, the second's value with a
  ;; space and a tab inside, and spaces and tabs around: trimmed, joined by
  ;; a comma, each space and tab inside an _.
  (test-equal "raw /raw/sink, a PUT with Expect and Content-Type twice: the method as sent, each value trimmed, repeats joined by a comma, whitespace inside as _"
    (list (string-append raw-sink-head "sink raw method=PUT cl=0 te=- expect=100-continue ct=a,b_c_d bytes=0 sha256="
                         sha-empty " pattern=ok arrivals=0 gap=- seen=1\n")
          'eof '())
    (sink-exchange o 'raw (string-append "PUT /raw/sink?key=rs-headers HTTP/1.1\r\nHost: 127.0.0.1\r\ncontent-TYPE: a\r\n"
                                         "EXPECT:100-continue\r\nContent-Type: \t b c\td \t\r\nContent-Length: 0\r\n\r\n")
                   2000))
  (test-equal "raw /raw/sink, one key twice: seen counts 1, then 2; http's /seen then reads 2, twice, counting nothing, and 0 for a key never counted"
    (list (list (string-append raw-sink-head "sink raw method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                               " pattern=ok arrivals=0 gap=- seen=1\n")
                'eof '())
          (list (string-append raw-sink-head "sink raw method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                               " pattern=ok arrivals=0 gap=- seen=2\n")
                'eof '())
          (seen-text 2) (seen-text 2) (seen-text 0))
    (in-order (lambda (thunk) (thunk))
              (list (lambda () (sink-exchange o 'raw (get "/raw/sink?key=rs-twice") 2000))
                    (lambda () (sink-exchange o 'raw (get "/raw/sink?key=rs-twice") 2000))
                    (lambda () (seen-of o "rs-twice"))
                    (lambda () (seen-of o "rs-twice"))
                    (lambda () (seen-of o "rs-never")))))
  ;; The body came with the head, so its arrival is the head's, 0.0 ms,
  ;; though the origin reads it only once the hold ends.
  (test-equal "raw /raw/sink?hold=300: the summary, whole, its arrival the head's at 0.0 ms, then eof, its first byte 300 ms or more after the probe connected; hold=0 answers as none does"
    (list (list (string-append raw-sink-head "sink raw method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10
                               " pattern=ok arrivals=1 gap=~@0 seen=1\n")
                'eof '("0.0"))
          'held
          (list (string-append raw-sink-head "sink raw method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10
                               " pattern=ok arrivals=1 gap=~@0 seen=1\n")
                'eof '("0.0")))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((p (wire-probe o 'raw (octets (string-append (post "/raw/sink?key=rs-hold&hold=300" "Content-Length: 10\r\n")
                                                          p10))
                            2000))
             (first (arrival (probe-arrivals p) 0)))
        (list (let ((shaped (shape-response (latin-1 (probe-bytes p))))) (list (car shaped) (probe-end p) (cadr shaped)))
              (if (and first (>= (- first (probe-connected p)) 300)) 'held (list 'connected (probe-connected p) 'first first))
              (sink-exchange o 'raw (string-append (post "/raw/sink?key=rs-hold0&hold=0" "Content-Length: 10\r\n") p10)
                             2000)))))
  ;; The body in two parts, 4 bytes with the head, then 6 bytes 300 ms on:
  ;; two arrivals, the first with the head at 0.0 ms, the longest wait the
  ;; one before the second, 4 bytes in. Half the split, as a lower bound: the
  ;; origin may see the first part late.
  (test-equal "raw /raw/sink?list=1, its body split 4 then 6 bytes, 300 ms apart: two arrivals listed, the first at 0.0 ms, gap=G@4, G the second's time, 150 ms or more"
    (list (list (string-append raw-sink-head "sink raw method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10
                               " pattern=ok arrivals=2 gap=~@4 seen=1 list=~:4,~:6\n")
                'eof)
          'first-at-0 'gap-is-the-second 'gap-long-enough)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/sink?key=rs-gap&list=1" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000))
             (shaped (shape-response (latin-1 (probe-bytes p))))
             (times (cadr shaped)))
        (list (list (car shaped) (probe-end p))
              (if (and (= (length times) 3) (string=? (cadr times) "0.0")) 'first-at-0 (list 'times times))
              (if (and (= (length times) 3) (string=? (car times) (caddr times))) 'gap-is-the-second (list 'times times))
              (if (and (= (length times) 3) (>= (tenths (car times)) 1500)) 'gap-long-enough (list 'times times))))))
  (test-equal "raw /raw/sink: a client that half-closes before its body's end gets nothing, then eof, and was counted"
    (list '("" eof) (seen-text 1))
    (guard (e (#t (list 'raised (describe e))))
      (let ((p (wire-probe-half-close o 'raw (octets (string-append (post "/raw/sink?key=rs-gone" "Content-Length: 10\r\n")
                                                                    "abcd"))
                                      2000)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p)) (seen-of o "rs-gone")))))
  (test-equal "raw /raw/sink: a client that resets before its body's end ends only its connection, and the next request is served"
    (list '("" reset-sent) '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
    (guard (e (#t (list 'raised (describe e))))
      (let ((p (wire-probe-reset o 'raw (octets (string-append (post "/raw/sink?key=rs-reset" "Content-Length: 10\r\n")
                                                               "abcd")))))
        (pause-ms 100)
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (exchange o 'raw (get "/raw/content-length") 2000)))))
  (for-each
   (lambda (row)
     (test-equal (string-append "raw /raw/sink: framing it cannot read gets the fixed 400: " (car row))
       bad-request
       (exchange o 'raw (cadr row) 2000)))
   (list (list "a Transfer-Encoding that is not chunked" (post "/raw/sink?key=rs-f1" "Transfer-Encoding: gzip\r\n"))
         (list "a Content-Length that is not digits" (post "/raw/sink?key=rs-f2" "Content-Length: 1x\r\n"))
         (list "a Content-Length twice, joined as 5,5" (post "/raw/sink?key=rs-f3" "Content-Length: 5\r\nContent-Length: 5\r\n"))
         (list "a chunk size that is not hex" (string-append (post "/raw/sink?key=rs-f4" "Transfer-Encoding: chunked\r\n")
                                                             "zz\r\nhello\r\n0\r\n\r\n"))
         (list "a chunk size of 9 hex digits" (string-append (post "/raw/sink?key=rs-f5" "Transfer-Encoding: chunked\r\n")
                                                             "000000001\r\nh\r\n0\r\n\r\n"))
         (list "a chunk's bytes not followed by CRLF" (string-append (post "/raw/sink?key=rs-f6" "Transfer-Encoding: chunked\r\n")
                                                                    "1\r\nab\r\n0\r\n\r\n"))
         (list "a size line ending in a bare LF" (string-append (post "/raw/sink?key=rs-f7" "Transfer-Encoding: chunked\r\n")
                                                               "1\na\r\n0\r\n\r\n"))))
  (test-equal "raw /raw/sink and /raw/answer: a query either refuses gets the fixed 400, and a refused sink counts nothing"
    (append (map (lambda (target) bad-request)
                 '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22))
            (list (seen-text 0)))
    (in-order (lambda (target) (if (string=? target "seen") (seen-of o "rs-refused") (exchange o 'raw (get target) 2000)))
              '("/raw/sink" "/raw/sink?" "/raw/sink?key=" "/raw/sink?key=rs-refused&key=rs-refused"
                "/raw/sink?key=rs-refused&hold=60001" "/raw/sink?key=rs-refused&hold=01"
                "/raw/sink?key=rs-refused&hold=x" "/raw/sink?key=rs-refused&list=0"
                "/raw/sink?key=rs-refused&list=1&list=1" "/raw/sink?key=rs-refused&x=1"
                "/raw/sink?hold=1&list=1" "/raw/sink?key=rs-refused&hold"
                "/raw/sink?key=a%2Fb"
                "/raw/answer" "/raw/answer?status=200" "/raw/answer?close=1" "/raw/answer?status=199&close=1"
                "/raw/answer?status=600&close=0" "/raw/answer?status=200&close=2"
                "/raw/answer?status=200&close=1&close=1" "/raw/answer?status=200&close=1&x=1"
                "/raw/answer?status=0200&close=1"
                "seen")))

  ;; --- the raw face: /raw/answer, before the body. The request's head goes
  ;; first, its body 300 ms on: an answer read before then came before the
  ;; body was sent.
  (test-equal "raw /raw/answer?status=413&close=1: the answer, Connection: close, then eof, both before the body is sent 300 ms on"
    (list (list "HTTP/1.1 413 Answer\r\nContent-Length: 11\r\nConnection: close\r\n\r\nanswer 413\n" 'eof)
          'before-the-body)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/answer?status=413&close=1" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (string-length head) 300 2000)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (< (- (probe-ended p) (probe-connected p)) 300) 'before-the-body
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
  (test-equal "raw /raw/answer?status=200&close=0: the answer, no Connection, before the body's last 6 bytes are sent 300 ms on; eof only after them"
    (list (list "HTTP/1.1 200 Answer\r\nContent-Length: 11\r\n\r\nanswer 200\n" 'eof)
          'answered-before 'ended-after)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/answer?status=200&close=0" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000))
             (last (arrival (probe-arrivals p) (- (string-length "HTTP/1.1 200 Answer\r\nContent-Length: 11\r\n\r\nanswer 200\n") 1))))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and last (< (- last (probe-connected p)) 300)) 'answered-before
                  (list 'connected (probe-connected p) 'last last))
              (if (>= (- (probe-ended p) (probe-connected p)) 300) 'ended-after
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
  (test-equal "raw /raw/answer?status=599&close=0, a GET with no body: the answer, then eof at once"
    '("HTTP/1.1 599 Answer\r\nContent-Length: 11\r\n\r\nanswer 599\n" eof)
    (exchange o 'raw (get "/raw/answer?close=0&status=599") 2000))

  ;; --- the raw face: /raw/arm, an answer before the request. The face
  ;; answers its next connection as it accepts it, before a byte is read:
  ;; a probe that sends nothing gets it, and so does one that sends a
  ;; request, whose script never plays; the connection after plays its
  ;; script as ever.
  (test-equal "raw /raw/arm?status=413: the arm's answer, then eof; the next connection, sending nothing, gets HTTP/1.1 413 Early with a close and its body, then eof; the one after plays /raw/content-length's script"
    (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
          '("HTTP/1.1 413 Early\r\nContent-Length: 10\r\nConnection: close\r\n\r\nearly 413\n" eof)
          '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((arm (exchange o 'raw (get "/raw/arm?status=413") 2000))
             (early (exchange o 'raw "" 2000))
             (after (exchange o 'raw (get "/raw/content-length") 2000)))
        (list arm early after))))
  (test-equal "raw /raw/arm?status=200: the next connection, sending a request for /raw/content-length, gets HTTP/1.1 200 Early, its request never played; the one after plays the script"
    (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
          '("HTTP/1.1 200 Early\r\nContent-Length: 10\r\nConnection: close\r\n\r\nearly 200\n" eof)
          '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((arm (exchange o 'raw (get "/raw/arm?status=200") 2000))
             (early (exchange o 'raw (get "/raw/content-length") 2000))
             (after (exchange o 'raw (get "/raw/content-length") 2000)))
        (list arm early after))))
  (test-equal "raw /raw/arm: a query it refuses gets the fixed 400 and arms nothing: none, no status, 199, 600, 0200, status twice, and another name; the next connection plays its script"
    (append (map (lambda (q) (list q bad-request))
                 '("/raw/arm" "/raw/arm?status=" "/raw/arm?status=199" "/raw/arm?status=600"
                   "/raw/arm?status=0200" "/raw/arm?status=200&status=200" "/raw/arm?status=200&x=1"))
            '(("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((refused (map (lambda (q) (list q (exchange o 'raw (get q) 2000)))
                           '("/raw/arm" "/raw/arm?status=" "/raw/arm?status=199" "/raw/arm?status=600"
                             "/raw/arm?status=0200" "/raw/arm?status=200&status=200" "/raw/arm?status=200&x=1")))
             (after (exchange o 'raw (get "/raw/content-length") 2000)))
        (append refused (list after)))))

  ;; --- the http face: /sink, read by node:http
  (test-equal "http /sink, 10 bytes of the pattern by Content-Length: the summary, whole, one arrival, then eof"
    (list (string-append http-sink-head "sink http method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10
                         " pattern=ok arrivals=1 gap=~@0 seen=1\n")
          'eof 1)
    (let ((r (sink-exchange o 'http (string-append (post "/sink?key=hs-sized" "Content-Length: 10\r\n" close) p10) 2000)))
      (if (= (length r) 3) (list (car r) (cadr r) (length (caddr r))) r)))
  (test-equal "http /sink?list=1, a chunked body with an extension and a Content-Type: te=chunked, the decoded bytes, ct with _ for its space, one arrival listed"
    (list (string-append http-sink-head "sink http method=PATCH cl=- te=chunked expect=- ct=text/plain;_charset=x bytes=5 sha256="
                         sha-hello " pattern=bad@0 arrivals=1 gap=~@0 seen=1 list=~:5\n")
          'eof 2)
    (let ((r (sink-exchange o 'http (string-append "PATCH /sink?list=1&key=hs-chunked HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                                                   "Transfer-Encoding: chunked\r\nContent-Type: text/plain; charset=x\r\n"
                                                   close "\r\n5;a=b\r\nhello\r\n0\r\n\r\n")
                            2000)))
      (if (= (length r) 3) (list (car r) (cadr r) (length (caddr r))) r)))
  (test-equal "http /sink without Connection: close: Connection: keep-alive, and the connection stays open"
    (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: L\r\nConnection: keep-alive\r\n\r\n"
                         "sink http method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                         " pattern=ok arrivals=0 gap=- seen=1\n")
          'timeout '())
    (sink-exchange o 'http (get "/sink?key=hs-kept") 300))
  ;; node:http's first data event comes a little after the head's, so G,
  ;; the wait before the second, is the second's time less the first's.
  (test-equal "http /sink?list=1, its body split 4 then 6 bytes, 300 ms apart: two arrivals, gap=G@4, G the second's time less the first's, 150 ms or more"
    (list (list (string-append http-sink-head "sink http method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10
                               " pattern=ok arrivals=2 gap=~@4 seen=1 list=~:4,~:6\n")
                'eof)
          'gap-between-the-two 'gap-long-enough)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/sink?key=hs-gap&list=1" "Content-Length: 10\r\n" close))
             (p (split-probe o 'http (string-append head p10) (+ (string-length head) 4) 300 2000))
             (shaped (shape-response (latin-1 (probe-bytes p))))
             (times (cadr shaped)))
        (list (list (car shaped) (probe-end p))
              (if (and (= (length times) 3) (= (tenths (car times)) (- (tenths (caddr times)) (tenths (cadr times)))))
                  'gap-between-the-two (list 'times times))
              (if (and (= (length times) 3) (>= (tenths (car times)) 1500)) 'gap-long-enough (list 'times times))))))
  (test-equal "http /sink, one key twice, and a key the raw face counted: seen 1 then 2 in the summaries, and /seen reads 2, and the raw face's 1"
    (list (list (string-append http-sink-head "sink http method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                               " pattern=ok arrivals=0 gap=- seen=1\n")
                'eof '())
          (list (string-append http-sink-head "sink http method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                               " pattern=ok arrivals=0 gap=- seen=2\n")
                'eof '())
          (seen-text 2) (seen-text 1))
    (in-order (lambda (thunk) (thunk))
              (list (lambda () (sink-exchange o 'http (get "/sink?key=hs-twice" close) 2000))
                    (lambda () (sink-exchange o 'http (get "/sink?key=hs-twice" close) 2000))
                    (lambda () (seen-of o "hs-twice"))
                    (lambda () (seen-of o "rs-sized")))))
  (test-equal "http: /answer and /refuse are HTTP/2's routes, 404 here, and the refuse counts nothing"
    (list not-found-close not-found-close (seen-text 0))
    (in-order (lambda (thunk) (thunk))
              (list (lambda () (exchange o 'http (get "/answer?status=200" close) 2000))
                    (lambda () (exchange o 'http (get "/refuse?key=hr-refuse&at=0" close) 2000))
                    (lambda () (seen-of o "hr-refuse")))))
  (test-equal "http: a query /sink, /seen or /close-after refuses is 404, and a refused sink counts nothing"
    (append (map (lambda (n) not-found-close) '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18))
            (list (seen-text 0)))
    (in-order (lambda (target) (if (string=? target "seen") (seen-of o "hs-refused") (exchange o 'http (get target close) 2000)))
              '("/sink" "/sink?" "/sink?key=" "/sink?key=hs-refused&key=hs-refused" "/sink?key=hs-refused&list=0"
                "/sink?key=hs-refused&list=1&list=1" "/sink?key=hs-refused&x=1" "/sink?list=1" "/sink?key=a%2Fb"
                "/seen" "/seen?key=hs-refused&x=1" "/seen?key=hs-refused&key=hs-refused" "/seen?key="
                "/close-after" "/close-after?then=nope" "/close-after?then=fin&then=fin" "/close-after?then=fin&x=1"
                "/close-after?then=" "seen")))

  ;; --- the http face: /close-after. The next request on the connection goes
  ;; 200 ms after the first, once its answer has come.
  (let ((after (lambda (then) (get (string-append "/close-after?then=" then)))))
    (test-equal "http /close-after?then=fin: ok, kept alive, then eof with nothing after it, 50 ms or more after connecting"
      (list (list ok-kept 'eof) 'late-enough)
      (guard (e (#t (list 'raised (describe e))))
        (let ((p (wire-probe o 'http (octets (after "fin")) 2000)))
          (list (list (latin-1 (probe-bytes p)) (probe-end p))
                (if (>= (- (probe-ended p) (probe-connected p)) 50) 'late-enough
                    (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
    (test-equal "http /close-after?then=kill: the next request, read whole, gets no answer, and an eof only after it was sent; it was counted"
      (list (list ok-kept 'eof) 'after-the-request (seen-text 1))
      (guard (e (#t (list 'raised (describe e))))
        (let ((p (split-probe o 'http (string-append (after "kill") (post "/sink?key=hk-whole" "Content-Length: 5\r\n") "hello")
                              (string-length (after "kill")) 200 2000)))
          (list (list (latin-1 (probe-bytes p)) (probe-end p))
                (if (>= (- (probe-ended p) (probe-connected p)) 200) 'after-the-request
                    (list 'connected (probe-connected p) 'ended (probe-ended p)))
                (seen-of o "hk-whole")))))
    ;; The next request's body is 5 bytes short of its Content-Length: kill
    ;; waits for the rest, so the probe's idle bound, 500 ms, ends it.
    (test-equal "http /close-after?then=kill: a next request whose body never ends is read, not cut, until the client goes; it was counted"
      (list (list ok-kept 'timeout) (seen-text 1))
      (guard (e (#t (list 'raised (describe e))))
        (let ((p (split-probe o 'http (string-append (after "kill") (post "/sink?key=hk-short" "Content-Length: 10\r\n") "hello")
                              (string-length (after "kill")) 200 500)))
          (list (list (latin-1 (probe-bytes p)) (probe-end p)) (seen-of o "hk-short")))))
    (test-equal "http /close-after?then=cuthead: the next request, its body 5 bytes short, is cut by a FIN as its head arrives; it was counted"
      (list (list ok-kept 'eof) (seen-text 1))
      (guard (e (#t (list 'raised (describe e))))
        (let ((p (split-probe o 'http (string-append (after "cuthead") (post "/sink?key=hc-short" "Content-Length: 10\r\n") "hello")
                              (string-length (after "cuthead")) 200 2000)))
          (list (list (latin-1 (probe-bytes p)) (probe-end p)) (seen-of o "hc-short")))))
    (test-equal "http /close-after?then=resethead: the next request, its body 5 bytes short, is cut by a reset as its head arrives; it was counted"
      (list (list ok-kept 'reset) (seen-text 1))
      (guard (e (#t (list 'raised (describe e))))
        (let ((p (split-probe o 'http (string-append (after "resethead") (post "/sink?key=hr-short" "Content-Length: 10\r\n") "hello")
                              (string-length (after "resethead")) 200 2000)))
          (list (list (latin-1 (probe-bytes p)) (probe-end p)) (seen-of o "hr-short")))))
    (test-equal "http /close-after: a mark is its connection's: a request on another connection is served"
      (list (list ok-kept 'timeout)
            '("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" eof))
      (in-order (lambda (thunk) (thunk))
                (list (lambda () (exchange o 'http (after "cuthead") 300))
                      (lambda () (exchange o 'http (get "/status/200" close) 2000)))))))

;; --- the stream calls' scripts -------------------------------------------------
;; Each test has keys of its own, as the sinks' do. A request's head goes
;; first and the rest of it 300 ms on, by the probe's --split, so a byte
;; read sooner than 300 ms after connecting came before the rest was sent,
;; and one read later, after.

;; early-text : String (U String #f) Boolean -> String
;; The answer /raw/answer-at and /raw/arm write, by hand: HTTP/1.1 S Early,
;; a Location of TO when given, Content-Length: 10, Connection: close when
;; CLOSE?, and the body early S.
(define (early-text status to close?)
  (string-append "HTTP/1.1 " status " Early\r\n"
                 (if to (string-append "Location: " to "\r\n") "")
                 "Content-Length: 10\r\n"
                 (if close? "Connection: close\r\n" "")
                 "\r\nearly " status "\n"))

;; uploader : String
;; Node's own client, run as node -e UPLOADER KIND HOST PORT BYTES, KIND
;; raw, raw-tls, h2c or h2: it posts BYTES bytes of the pattern to the
;; face's mirror, sized, 65511 bytes a write, each awaited until its socket
;; or stream takes it, reading nothing, until every write is taken, or none
;; has been for 500 ms; then it reads, writes the rest, and reads the
;; answer to its end. It prints (uploaded STALL TAKEN "HEAD" GOT CHECK):
;; STALL is stalled and the bytes taken then, or whole; TAKEN the bytes
;; taken in all; HEAD the response's head, or over HTTP/2 its :status and
;; content-length; GOT the body's bytes; CHECK ok when each byte i is i mod
;; 251, else the first that is not. An error prints (failed CODE), and 30 s
;; on it prints (deadline); either exits 1.
(define uploader
  (string-append
   "const net = require('node:net'); const tls = require('node:tls'); const http2 = require('node:http2');"
   "const [kind, host, port, totalText] = process.argv.slice(1);"
   "const total = Number(totalText);"
   "const block = Buffer.alloc(65511); for (let i = 0; i < block.length; i++) block[i] = i % 251;"
   "let taken = 0, last = performance.now(), stall = null, got = 0, bad = null, head = null, buf = Buffer.alloc(0);"
   "let out = null, resume = null, watch = null;"
   "const fail = (code) => { console.log(`(failed ${code})`); process.exit(1); };"
   "setTimeout(() => { console.log('(deadline)'); process.exit(1); }, 30000);"
   "const take = (chunk) => { for (let i = 0; i < chunk.length; i++) if (bad === null && chunk[i] !== (got + i) % 251) bad = got + i; got += chunk.length; };"
   "const pump = () => {"
   "  if (taken >= total) { if (kind.startsWith('h2')) out.end(); return; }"
   "  const n = Math.min(block.length, total - taken);"
   "  out.write(block.subarray(0, n), (err) => { if (!err) { taken += n; last = performance.now(); pump(); } });"
   "};"
   "const start = () => {"
   "  last = performance.now();"
   "  watch = setInterval(() => {"
   "    if (taken >= total || performance.now() - last >= 500) {"
   "      clearInterval(watch); stall = taken < total ? `stalled ${taken}` : 'whole'; resume();"
   "    }"
   "  }, 20);"
   "  pump();"
   "};"
   "const done = () => { console.log(`(uploaded ${stall} ${taken} ${JSON.stringify(head)} ${got} ${bad === null ? 'ok' : bad})`); process.exit(0); };"
   "if (kind.startsWith('raw')) {"
   "  out = kind === 'raw' ? net.connect(Number(port), host)"
   "    : tls.connect({ host, port: Number(port), servername: 'localhost', rejectUnauthorized: false, ALPNProtocols: ['http/1.1'] });"
   "  out.on('data', (chunk) => {"
   "    if (head === null) {"
   "      buf = Buffer.concat([buf, chunk]); const at = buf.indexOf('\\r\\n\\r\\n'); if (at < 0) return;"
   "      head = buf.subarray(0, at).toString('latin1'); chunk = buf.subarray(at + 4);"
   "    }"
   "    take(chunk);"
   "  });"
   "  out.pause();"
   "  out.on('end', done);"
   "  out.on('error', (err) => fail(err.code));"
   "  resume = () => out.resume();"
   "  out.on(kind === 'raw' ? 'connect' : 'secureConnect', () => {"
   "    out.write(`POST /raw/mirror HTTP/1.1\\r\\nHost: 127.0.0.1\\r\\nContent-Length: ${total}\\r\\n\\r\\n`); start();"
   "  });"
   "} else {"
   "  const session = http2.connect(`${kind === 'h2c' ? 'http' : 'https'}://${host}:${port}`, { servername: 'localhost', rejectUnauthorized: false });"
   "  session.on('error', (err) => fail(err.code));"
   "  out = session.request({ ':method': 'POST', ':path': '/mirror', 'content-length': String(total) });"
   "  out.on('response', (h) => { head = `:status ${h[':status']} content-length ${h['content-length']}`; });"
   "  out.on('data', take);"
   "  out.pause();"
   "  out.on('end', () => { session.close(); done(); });"
   "  out.on('error', (err) => fail(err.code));"
   "  resume = () => out.resume();"
   "  session.on('connect', start);"
   "}"))

;; upload : Origin Symbol Natural -> List
;; The uploader's line against FACE's mirror, BYTES bytes, read as data, its
;; STALL's bytes written short-of-the-end when they are past 0 and short of
;; BYTES; or (exit STATUS STDOUT STDERR) when it did not exit 0.
(define (upload o face bytes)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((f (origin-face o face))
           (r (capture-command (list node "-e" uploader (symbol->string face) (car f)
                                     (number->string (cdr f)) (number->string bytes)))))
      (if (not (= (car r) 0))
          (list 'exit r)
          (let ((line (read (open-string-input-port (cadr r)))))
            (if (and (list? line) (> (length line) 3) (eq? (cadr line) 'stalled)
                     (integer? (caddr line)) (< 0 (caddr line) bytes))
                (cons* (car line) 'stalled 'short-of-the-end (cdddr line))
                line))))))

;; without-cr : String -> String
;; LINE without its last char when that is a CR.
(define (without-cr line)
  (let ((n (string-length line)))
    (if (and (> n 0) (char=? (string-ref line (- n 1)) #\return)) (substring line 0 (- n 1)) line)))

;; seq-response : String -> (List String (U Symbol List) (Listof String))
;; A /raw/seq response TEXT: its head, its CRLF CRLF left off, the Sink
;; line's times written ~ as shape writes them; whether its body is the
;; first N bytes of the pattern, N its Content-Length, by same-text; and the
;; Sink line's times.
(define (seq-response text)
  (let ((at (let loop ((i 0))
              (cond ((> (+ i 4) (string-length text)) #f)
                    ((string=? (substring text i (+ i 4)) "\r\n\r\n") i)
                    (else (loop (+ i 1)))))))
    (if (not at)
        (list text 'no-head '())
        (let* ((times '())
               ;; Each line but the last keeps its CR.
               (lines (in-order (lambda (line)
                                  (if (prefix? "Sink: " line)
                                      (let ((shaped (shape (substring (without-cr line) 6 (string-length (without-cr line))))))
                                        (set! times (cadr shaped))
                                        (string-append "Sink: " (car shaped)
                                                       (if (string=? line (without-cr line)) "" "\r")))
                                      line))
                                (split-text (substring text 0 at) #\newline)))
               (body (substring text (+ at 4) (string-length text)))
               (length-line (exists (lambda (line) (and (prefix? "Content-Length: " line) (without-cr line))) lines))
               (n (and length-line (string->number (substring length-line 16 (string-length length-line))))))
          (list (join-text lines "\n")
                (if n (same-text (pattern-text n) body) 'no-length)
                times)))))

(define (duplex-scenarios o)
  (define p10 (pattern-text 10))

  ;; --- the raw face: /raw/cut, a connection ended once N bytes of what
  ;; follows the head have come, nothing written; counted as a sink counts
  (test-equal "raw /raw/cut?key=cut-4&after=4, the body's first 4 bytes with the head and the rest 300 ms on: nothing written, eof, before the rest is sent; the request counted once for its key, by http's /seen"
    (list (list "" 'eof) 'before-the-rest (seen-text 1))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/cut?key=cut-4&after=4" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (< (- (probe-ended p) (probe-connected p)) 300) 'before-the-rest
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))
              (seen-of o "cut-4")))))
  (test-equal "raw /raw/cut?key=cut-6&after=6, the body's first 4 bytes with the head and the rest 300 ms on: nothing written, and eof only once the rest is sent"
    (list (list "" 'eof) 'after-the-rest)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/cut?key=cut-6&after=6" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (>= (- (probe-ended p) (probe-connected p)) 300) 'after-the-rest
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
  (test-equal "raw /raw/cut?key=cut-0&after=0: nothing written, eof, as the head arrives, the body 300 ms on never awaited"
    (list (list "" 'eof) 'before-the-body)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/cut?key=cut-0&after=0" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (string-length head) 300 2000)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (< (- (probe-ended p) (probe-connected p)) 300) 'before-the-body
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
  (test-equal "raw /raw/cut: a query it refuses gets the fixed 400, and counts nothing"
    (append (map (lambda (target) bad-request) '(1 2 3 4 5 6 7 8 9))
            (list (seen-text 0)))
    (in-order (lambda (target) (if (string=? target "seen") (seen-of o "cut-refused") (exchange o 'raw (get target) 2000)))
              '("/raw/cut" "/raw/cut?key=cut-refused" "/raw/cut?after=1" "/raw/cut?key=cut-refused&after=268435457"
                "/raw/cut?key=cut-refused&after=01" "/raw/cut?key=cut-refused&after=1&after=1"
                "/raw/cut?key=cut-refused&after=1&x=1" "/raw/cut?key=a%2Fb&after=1" "/raw/cut?key=cut-refused&after=x"
                "seen")))

  ;; --- the raw face: /raw/sunk, the bytes a raw sink has read for its key,
  ;; whether or not the client went first
  (test-equal "raw /raw/sunk?key=KEY: a sink whose client sent 4 of its 10 body bytes, wrote nothing, and was left; one sent its body whole, read 10; a key no sink has read, 0; the query counts nothing"
    (list (list "" 'timeout) (sunk-text 4) (sunk-text 10) (sunk-text 0) (seen-text 0))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((short (exchange o 'raw (string-append (post "/raw/sink?key=sunk-4" "Content-Length: 10\r\n")
                                                    (substring p10 0 4))
                              300))
             (whole (exchange o 'raw (string-append (post "/raw/sink?key=sunk-10" "Content-Length: 10\r\n") p10) 2000))
             (four (exchange o 'raw (get "/raw/sunk?key=sunk-4") 2000))
             (ten (exchange o 'raw (get "/raw/sunk?key=sunk-10") 2000))
             (none (exchange o 'raw (get "/raw/sunk?key=sunk-none") 2000))
             (counted (seen-of o "sunk-none")))
        (list short four ten none counted))))
  (test-equal "raw /raw/sunk and /raw/release: a query either refuses gets the fixed 400"
    (map (lambda (target) bad-request) '(1 2 3 4 5 6 7 8))
    (in-order (lambda (target) (exchange o 'raw (get target) 2000))
              '("/raw/sunk" "/raw/sunk?key=a%2Fb" "/raw/sunk?key=k&x=1" "/raw/sunk?x=1"
                "/raw/release" "/raw/release?key=a%2Fb" "/raw/release?key=k&x=1" "/raw/release?x=1")))

  ;; --- the raw face: answer-at's hold, its answer's last byte held until
  ;; /raw/release names its key
  (test-equal "raw /raw/answer-at?status=200&after=0&close=0&hold=KEY, a POST of 10 bytes with its head: the answer but its last byte at once, the last 200 ms or more later, once /raw/release?key=KEY, from another connection 800 ms on, has answered released; then eof"
    (list (list (early-text "200" #f #f) 'eof) 'held-until-released released-text)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((finish (spawned-probe o 'raw (string-append (post "/raw/answer-at?status=200&after=0&close=0&hold=hold-1"
                                                                "Content-Length: 10\r\n")
                                                          p10)
                                       5000))
             (released (begin (pause-ms 800) (exchange o 'raw (get "/raw/release?key=hold-1") 2000)))
             (p (finish))
             (n (string-length (early-text "200" #f #f)))
             (last (arrival (probe-arrivals p) (- n 1)))
             (before (arrival (probe-arrivals p) (- n 2))))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and last before (>= (- last before) 200)) 'held-until-released
                  (list 'before before 'last last))
              released))))
  (test-equal "raw /raw/release?key=KEY before answer-at's hold=KEY: released, then the answer whole at once, then eof"
    (list released-text (list (early-text "200" #f #f) 'eof))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((released (exchange o 'raw (get "/raw/release?key=hold-2") 2000))
             (answer (exchange o 'raw (string-append (post "/raw/answer-at?status=200&after=0&close=0&hold=hold-2"
                                                           "Content-Length: 10\r\n")
                                                     p10)
                               2000)))
        (list released answer))))
  (test-equal "raw /raw/answer-at: a hold it refuses gets the fixed 400"
    (list bad-request bad-request bad-request)
    (in-order (lambda (target) (exchange o 'raw (get target) 2000))
              '("/raw/answer-at?status=200&after=0&hold=a%2Fb" "/raw/answer-at?status=200&after=0&hold=h&hold=h"
                "/raw/answer-at?status=200&after=0&hold=")))

  ;; --- the raw face: /raw/answer-at, an answer once N body bytes have come
  (test-equal "raw /raw/answer-at?status=303&after=0&to=%2Fx, a POST whose body comes 300 ms after its head: the answer, its Location, no Connection, before the body is sent; eof only after it"
    (list (list (early-text "303" "/x" #f) 'eof) 'answered-before 'ended-after)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/answer-at?status=303&after=0&to=%2Fx" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (string-length head) 300 2000))
             (last (arrival (probe-arrivals p) (- (string-length (early-text "303" "/x" #f)) 1))))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and last (< (- last (probe-connected p)) 300)) 'answered-before
                  (list 'connected (probe-connected p) 'last last))
              (if (>= (- (probe-ended p) (probe-connected p)) 300) 'ended-after
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
  (test-equal "raw /raw/answer-at?status=413&after=4&close=1, the body's first 4 bytes with the head and the rest 300 ms on: the answer with Connection: close, then eof, both before the rest is sent"
    (list (list (early-text "413" #f #t) 'eof) 'before-the-rest)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/answer-at?status=413&after=4&close=1" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (< (- (probe-ended p) (probe-connected p)) 300) 'before-the-rest
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
  (for-each
   (lambda (close)
     (test-equal (string-append "raw /raw/answer-at?status=413&after=5&close=" close
                                ", the body's first 4 bytes with the head and the rest 300 ms on: the answer only once the rest is sent, then eof")
       (list (list (early-text "413" #f (string=? close "1")) 'eof) 'after-the-rest)
       (guard (e (#t (list 'raised (describe e))))
         (let* ((head (post (string-append "/raw/answer-at?status=413&after=5&close=" close) "Content-Length: 10\r\n"))
                (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000))
                (first (arrival (probe-arrivals p) 0)))
           (list (list (latin-1 (probe-bytes p)) (probe-end p))
                 (if (and first (>= (- first (probe-connected p)) 300)) 'after-the-rest
                     (list 'connected (probe-connected p) 'first first)))))))
   '("0" "1"))
  ;; Chunked, the answer at 4 body bytes: the first chunk, 4 bytes, with the
  ;; head, the next chunk and the last 300 ms on.
  (test-equal "raw /raw/answer-at?status=200&after=4, chunked, its first chunk of 4 bytes with the head and the rest 300 ms on: the answer before the rest; eof only after the last chunk"
    (list (list (early-text "200" #f #f) 'eof) 'answered-before 'ended-after)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((first (string-append (post "/raw/answer-at?after=4&status=200" "Transfer-Encoding: chunked\r\n") "4\r\nabcd\r\n"))
             (p (split-probe o 'raw (string-append first "6\r\nefghij\r\n0\r\n\r\n") (string-length first) 300 2000))
             (last (arrival (probe-arrivals p) (- (string-length (early-text "200" #f #f)) 1))))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and last (< (- last (probe-connected p)) 300)) 'answered-before
                  (list 'connected (probe-connected p) 'last last))
              (if (>= (- (probe-ended p) (probe-connected p)) 300) 'ended-after
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
  ;; A body shorter than N: answered at its end, its last chunk 300 ms on.
  (test-equal "raw /raw/answer-at?status=200&after=100, a chunked body of 10 bytes whose last chunks come 300 ms after its first: the answer only at the body's end, then eof"
    (list (list (early-text "200" #f #f) 'eof) 'at-the-end)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((first (string-append (post "/raw/answer-at?status=200&after=100" "Transfer-Encoding: chunked\r\n") "5\r\nhello\r\n"))
             (p (split-probe o 'raw (string-append first "5\r\nworld\r\n0\r\n\r\n") (string-length first) 300 2000))
             (at (arrival (probe-arrivals p) 0)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and at (>= (- at (probe-connected p)) 300)) 'at-the-end
                  (list 'connected (probe-connected p) 'first at))))))
  (test-equal "raw /raw/answer-at: a GET, no body, after=1 and close=1: the answer at once, then eof; after=0 and close=0 alike, with no Connection"
    (list (list (early-text "599" #f #t) 'eof) (list (early-text "200" #f #f) 'eof))
    (list (exchange o 'raw (get "/raw/answer-at?status=599&after=1&close=1") 2000)
          (exchange o 'raw (get "/raw/answer-at?close=0&after=0&status=200") 2000)))
  (let ((bytes (filter (lambda (b) (not (memv b '(10 13)))) (iota 256)))
        (hex2 (lambda (b upper?)
                (let ((digits (if upper? "0123456789ABCDEF" "0123456789abcdef")))
                  (string #\% (string-ref digits (div b 16)) (string-ref digits (mod b 16)))))))
    (test-equal "raw /raw/answer-at: to holding every byte but CR and LF, 0x00 to 0xFF, as %XX in upper-case hex, then in lower: the Location holds each byte, in order"
      (let ((value (list->string (map integer->char bytes))))
        (list (list (early-text "302" value #t) 'eof) (list (early-text "302" value #t) 'eof)))
      (map (lambda (upper?)
             (exchange o 'raw (get (apply string-append "/raw/answer-at?status=302&after=0&close=1&to="
                                          (map (lambda (b) (hex2 b upper?)) bytes)))
                       2000))
           '(#t #f))))
  ;; A chunk size that is no hex before the answer: the fixed 400 in its
  ;; place. After it, with the answer gone, the end alone.
  (test-equal "raw /raw/answer-at: framing it cannot read before the answer gets the fixed 400, not the answer; after it, the answer and the end"
    (list bad-request bad-request bad-request (list (early-text "200" #f #f) 'eof))
    (list (exchange o 'raw (post "/raw/answer-at?status=200&after=0" "Transfer-Encoding: gzip\r\n") 2000)
          (exchange o 'raw (post "/raw/answer-at?status=200&after=1" "Content-Length: 1x\r\n") 2000)
          (exchange o 'raw (string-append (post "/raw/answer-at?status=200&after=100" "Transfer-Encoding: chunked\r\n")
                                          "zz\r\nhello\r\n0\r\n\r\n")
                    2000)
          (exchange o 'raw (string-append (post "/raw/answer-at?status=200&after=0" "Transfer-Encoding: chunked\r\n")
                                          "zz\r\nhello\r\n0\r\n\r\n")
                    2000)))
  (test-equal "raw /raw/answer-at: a query it refuses gets the fixed 400"
    (map (lambda (q) (list q bad-request))
         '("/raw/answer-at" "/raw/answer-at?" "/raw/answer-at?after=0" "/raw/answer-at?status=200"
           "/raw/answer-at?status=199&after=0" "/raw/answer-at?status=600&after=0" "/raw/answer-at?status=0200&after=0"
           "/raw/answer-at?status=200&after=268435457" "/raw/answer-at?status=200&after=01"
           "/raw/answer-at?status=200&after=x" "/raw/answer-at?status=200&after=0&close=2"
           "/raw/answer-at?status=200&after=0&close=1&close=1" "/raw/answer-at?status=200&status=200&after=0"
           "/raw/answer-at?status=200&after=0&after=0" "/raw/answer-at?status=200&after=0&to=%2Fa&to=%2Fb"
           "/raw/answer-at?status=200&after=0&to=%zz" "/raw/answer-at?status=200&after=0&to=a%4"
           "/raw/answer-at?status=200&after=0&x=1" "/raw/answer-at?status=200&after=0&close"))
    (map (lambda (q) (list q (exchange o 'raw (get q) 2000)))
         '("/raw/answer-at" "/raw/answer-at?" "/raw/answer-at?after=0" "/raw/answer-at?status=200"
           "/raw/answer-at?status=199&after=0" "/raw/answer-at?status=600&after=0" "/raw/answer-at?status=0200&after=0"
           "/raw/answer-at?status=200&after=268435457" "/raw/answer-at?status=200&after=01"
           "/raw/answer-at?status=200&after=x" "/raw/answer-at?status=200&after=0&close=2"
           "/raw/answer-at?status=200&after=0&close=1&close=1" "/raw/answer-at?status=200&status=200&after=0"
           "/raw/answer-at?status=200&after=0&after=0" "/raw/answer-at?status=200&after=0&to=%2Fa&to=%2Fb"
           "/raw/answer-at?status=200&after=0&to=%zz" "/raw/answer-at?status=200&after=0&to=a%4"
           "/raw/answer-at?status=200&after=0&x=1" "/raw/answer-at?status=200&after=0&close")))

  ;; --- the raw face: /raw/arm's mode and to
  (test-equal "raw /raw/arm?status=303&mode=keep&to=%2Fa: the next connection gets the answer, its Location, no Connection, before its request's body is sent; the face then reads that request to its body's end, and only then the eof; the one after plays its script"
    (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
          (list (early-text "303" "/a" #f) 'eof) 'answered-before 'ended-after
          '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((arm (exchange o 'raw (get "/raw/arm?status=303&mode=keep&to=%2Fa") 2000))
             (head (post "/raw/content-length" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000))
             (last (arrival (probe-arrivals p) (- (string-length (early-text "303" "/a" #f)) 1)))
             (after (exchange o 'raw (get "/raw/content-length") 2000)))
        (list arm (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and last (< (- last (probe-connected p)) 300)) 'answered-before
                  (list 'connected (probe-connected p) 'last last))
              (if (>= (- (probe-ended p) (probe-connected p)) 300) 'ended-after
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))
              after))))
  (test-equal "raw /raw/arm?status=200&mode=cut&after=4: the next connection gets the answer, no Connection, before its request's body is sent; once the body's first 4 bytes have come, the connection ends, nothing more written, before the rest is sent 300 ms on; the one after plays its script"
    (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
          (list (early-text "200" #f #f) 'eof) 'ended-before-the-rest
          '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((arm (exchange o 'raw (get "/raw/arm?status=200&mode=cut&after=4") 2000))
             (head (post "/raw/content-length" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000))
             (after (exchange o 'raw (get "/raw/content-length") 2000)))
        (list arm (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (< (- (probe-ended p) (probe-connected p)) 300) 'ended-before-the-rest
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))
              after))))
  (test-equal "raw /raw/arm?status=200&mode=cut&after=6: with only the body's first 4 bytes sent with the head, the connection ends only once the rest is sent 300 ms on"
    (list (list (early-text "200" #f #f) 'eof) 'ended-after-the-rest)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((arm (exchange o 'raw (get "/raw/arm?status=200&mode=cut&after=6") 2000))
             (head (post "/raw/content-length" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (>= (- (probe-ended p) (probe-connected p)) 300) 'ended-after-the-rest
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
  (test-equal "raw /raw/arm: after with no mode cut, and mode cut with no after, each get the fixed 400 and arm nothing; the next connection plays its script"
    (list bad-request bad-request bad-request bad-request
          '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
    (in-order (lambda (target) (exchange o 'raw (get target) 2000))
              '("/raw/arm?status=200&after=4" "/raw/arm?status=200&mode=keep&after=4" "/raw/arm?status=200&mode=cut"
                "/raw/arm?status=200&mode=cut&after=268435457" "/raw/content-length")))
  ;; Kept, the face waits for a request: one that sends nothing waits too.
  (test-equal "raw /raw/arm?status=200&mode=keep: the next connection, sending nothing, gets the answer, no Connection, and stays open until the client goes"
    (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
          (list (early-text "200" #f #f) 'timeout))
    (list (exchange o 'raw (get "/raw/arm?mode=keep&status=200") 2000)
          (exchange o 'raw "" 300)))
  (test-equal "raw /raw/arm?status=413&mode=close: the bytes of an arm with no mode, Connection: close, then eof"
    (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
          (list (early-text "413" #f #t) 'eof))
    (list (exchange o 'raw (get "/raw/arm?status=413&mode=close") 2000)
          (exchange o 'raw "" 2000)))
  (let ((bytes (filter (lambda (b) (not (memv b '(10 13)))) (iota 256))))
    (test-equal "raw /raw/arm: to holding every byte but CR and LF, 0x00 to 0xFF, as %XX: the Location holds each byte, in order, closed by default and kept with mode=keep"
      (let ((value (list->string (map integer->char bytes))))
        (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
              (list (early-text "301" value #t) 'eof)
              '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
              (list (early-text "308" value #f) 'eof)))
      (let ((to (apply string-append
                       (map (lambda (b) (string #\% (string-ref "0123456789ABCDEF" (div b 16))
                                                (string-ref "0123456789abcdef" (mod b 16))))
                            bytes))))
        (in-order (lambda (thunk) (thunk))
                  (list (lambda () (exchange o 'raw (get (string-append "/raw/arm?status=301&to=" to)) 2000))
                        (lambda () (exchange o 'raw "" 2000))
                        (lambda () (exchange o 'raw (get (string-append "/raw/arm?to=" to "&mode=keep&status=308")) 2000))
                        (lambda () (exchange o 'raw (get "/raw/content-length") 2000)))))))
  (test-equal "raw /raw/arm: a mode or a to it refuses gets the fixed 400 and arms nothing; the next connection plays its script"
    (append (map (lambda (q) (list q bad-request))
                 '("/raw/arm?status=200&mode=open" "/raw/arm?status=200&mode=" "/raw/arm?status=200&mode=keep&mode=keep"
                   "/raw/arm?status=200&to=%2Fa&to=%2Fb" "/raw/arm?status=200&to=%zz" "/raw/arm?mode=keep"))
            '(("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((refused (in-order (lambda (q) (list q (exchange o 'raw (get q) 2000)))
                                '("/raw/arm?status=200&mode=open" "/raw/arm?status=200&mode=" "/raw/arm?status=200&mode=keep&mode=keep"
                                  "/raw/arm?status=200&to=%2Fa&to=%2Fb" "/raw/arm?status=200&to=%zz" "/raw/arm?mode=keep")))
             (after (exchange o 'raw (get "/raw/content-length") 2000)))
        (append refused (list after)))))

  ;; --- the raw face: /raw/mirror, the body written back as it comes
  (test-equal "raw /raw/mirror, 10 bytes by Content-Length, 4 with the head and 6 300 ms on: its head and the first 4 bytes back before the rest is sent, then the rest, then eof"
    (list (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\n" p10) 'eof)
          'first-four-before 'ended-after)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/mirror" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000))
             (fourth (arrival (probe-arrivals p)
                              (+ (string-length "HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\n") 3))))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and fourth (< (- fourth (probe-connected p)) 300)) 'first-four-before
                  (list 'connected (probe-connected p) 'fourth fourth))
              (if (>= (- (probe-ended p) (probe-connected p)) 300) 'ended-after
                  (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
  ;; Chunked, one chunk of 10 bytes split across two writes, 300 ms apart:
  ;; each data event's piece goes back as a chunk of its own, 5 and 5.
  (test-equal "raw /raw/mirror, chunked, one chunk of 10 bytes split after its fifth, 300 ms apart: Transfer-Encoding: chunked, each piece back as its own chunk, the first before the rest is sent, then the last chunk and eof"
    (list (list (string-append "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
                               "5\r\nhello\r\n5\r\nworld\r\n0\r\n\r\n")
                'eof)
          'first-before)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((first (string-append (post "/raw/mirror" "Transfer-Encoding: chunked\r\n") "a\r\nhello"))
             (p (split-probe o 'raw (string-append first "world\r\n0\r\n\r\n") (string-length first) 300 2000))
             (piece (arrival (probe-arrivals p)
                             (+ (string-length "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n5\r\nhello\r\n") -1))))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and piece (< (- piece (probe-connected p)) 300)) 'first-before
                  (list 'connected (probe-connected p) 'piece piece))))))
  (test-equal "raw /raw/mirror, chunked in one write, two chunks with an extension and a trailer: the decoded pieces, each its own chunk, the extension and the trailer dropped"
    (list (string-append "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
                         "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n")
          'eof)
    (exchange o 'raw (string-append (post "/raw/mirror" "Transfer-Encoding: chunked\r\n")
                                    "5;name=value\r\nhello\r\n6\r\n world\r\n0;last\r\nX-Trailer: done\r\n\r\n")
              2000))
  (test-equal "raw /raw/mirror, a GET with no body: Content-Length: 0, then eof; Content-Length: 0 sent alike"
    (list '("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" eof)
          '("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" eof))
    (list (exchange o 'raw (get "/raw/mirror") 2000)
          (exchange o 'raw (post "/raw/mirror" "Content-Length: 0\r\n") 2000)))
  (test-equal "raw /raw/mirror, 64 MiB to a client that reads nothing: its upload stalls past 0 and short of the end, the face's writes and so its reads paused; once it reads, the rest goes, and the whole body comes back"
    (list 'uploaded 'stalled 'short-of-the-end 67108864
          "HTTP/1.1 200 OK\r\nContent-Length: 67108864\r\nConnection: close" 67108864 'ok)
    (upload o 'raw 67108864))
  (test-equal "raw /raw/mirror: a query, and framing it cannot read, get the fixed 400"
    (list bad-request bad-request bad-request bad-request)
    (list (exchange o 'raw (get "/raw/mirror?x=1") 2000)
          (exchange o 'raw (get "/raw/mirror?") 2000)
          (exchange o 'raw (post "/raw/mirror" "Transfer-Encoding: gzip\r\n") 2000)
          (exchange o 'raw (post "/raw/mirror" "Content-Length: 1x\r\n") 2000)))

  ;; --- the raw face: /raw/seq, a sink's summary in a header, then a body
  (test-equal "raw /raw/seq?key=sq-post&bytes=600, 10 bytes of the pattern: Sink: the summary, Content-Length: 600, Connection: close, then 600 bytes of the pattern, then eof"
    (list (string-append "HTTP/1.1 200 OK\r\nSink: sink raw method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10
                         " pattern=ok arrivals=1 gap=~@0 seen=1\r\nContent-Length: 600\r\nConnection: close")
          'same '("0.0") 'eof)
    (guard (e (#t (list 'raised (describe e))))
      (let ((p (wire-probe o 'raw (octets (string-append (post "/raw/seq?key=sq-post&bytes=600" "Content-Length: 10\r\n") p10))
                           2000)))
        (append (seq-response (latin-1 (probe-bytes p))) (list (probe-end p))))))
  (test-equal "raw /raw/seq?key=sq-zero&bytes=0, a GET: Sink: the summary of no body, Content-Length: 0, no body, then eof"
    (list (string-append "HTTP/1.1 200 OK\r\nSink: sink raw method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                         " pattern=ok arrivals=0 gap=- seen=1\r\nContent-Length: 0\r\nConnection: close")
          'same '() 'eof)
    (guard (e (#t (list 'raised (describe e))))
      (let ((p (wire-probe o 'raw (octets (get "/raw/seq?bytes=0&key=sq-zero")) 2000)))
        (append (seq-response (latin-1 (probe-bytes p))) (list (probe-end p))))))
  (test-equal "raw /raw/seq?key=sq-long&bytes=100000: the pattern's 100000 bytes, past several of its writes, whole, then eof"
    (list (string-append "HTTP/1.1 200 OK\r\nSink: sink raw method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                         " pattern=ok arrivals=0 gap=- seen=1\r\nContent-Length: 100000\r\nConnection: close")
          'same '() 'eof)
    (guard (e (#t (list 'raised (describe e))))
      (let ((p (wire-probe o 'raw (octets (get "/raw/seq?key=sq-long&bytes=100000")) 2000)))
        (append (seq-response (latin-1 (probe-bytes p))) (list (probe-end p))))))
  (test-equal "raw /raw/seq, its body split 4 then 6 bytes, 300 ms apart: the answer only once the body is whole"
    (list (string-append "HTTP/1.1 200 OK\r\nSink: sink raw method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10
                         " pattern=ok arrivals=2 gap=~@4 seen=1\r\nContent-Length: 3\r\nConnection: close")
          'same 'eof 'after-the-body)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/seq?key=sq-split&bytes=3" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw (string-append head p10) (+ (string-length head) 4) 300 2000))
             (got (seq-response (latin-1 (probe-bytes p))))
             (first (arrival (probe-arrivals p) 0)))
        (list (car got) (cadr got) (probe-end p)
              (if (and first (>= (- first (probe-connected p)) 300)) 'after-the-body
                  (list 'connected (probe-connected p) 'first first))))))
  (test-equal "raw /raw/seq and /raw/sink share a key's count: seq seen=1, sink seen=2, seq seen=3; http's /seen then reads 3"
    (list (list (string-append "HTTP/1.1 200 OK\r\nSink: sink raw method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                               " pattern=ok arrivals=0 gap=- seen=1\r\nContent-Length: 1\r\nConnection: close")
                'same '())
          (list (string-append raw-sink-head "sink raw method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                               " pattern=ok arrivals=0 gap=- seen=2\n")
                'eof '())
          (list (string-append "HTTP/1.1 200 OK\r\nSink: sink raw method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                               " pattern=ok arrivals=0 gap=- seen=3\r\nContent-Length: 1\r\nConnection: close")
                'same '())
          (seen-text 3))
    (in-order (lambda (thunk) (thunk))
              (list (lambda () (let ((a (exchange o 'raw (get "/raw/seq?key=sq-count&bytes=1") 2000)))
                                 (if (eq? (car a) 'raised) a (seq-response (car a)))))
                    (lambda () (sink-exchange o 'raw (get "/raw/sink?key=sq-count") 2000))
                    (lambda () (let ((a (exchange o 'raw (get "/raw/seq?key=sq-count&bytes=1") 2000)))
                                 (if (eq? (car a) 'raised) a (seq-response (car a)))))
                    (lambda () (seen-of o "sq-count")))))
  (test-equal "raw /raw/seq: a query it refuses gets the fixed 400 and counts nothing; framing it cannot read gets the fixed 400, counted"
    (append (map (lambda (n) bad-request) '(1 2 3 4 5 6 7 8 9 10 11))
            (list (seen-text 0) bad-request (seen-text 1)))
    (in-order (lambda (target)
                (cond ((string=? target "seen") (seen-of o "sq-refused"))
                      ((string=? target "seen-bad") (seen-of o "sq-bad"))
                      ((string=? target "bad") (exchange o 'raw (post "/raw/seq?key=sq-bad&bytes=1" "Content-Length: 1x\r\n") 2000))
                      (else (exchange o 'raw (get target) 2000))))
              '("/raw/seq" "/raw/seq?" "/raw/seq?key=sq-refused" "/raw/seq?bytes=1" "/raw/seq?key=sq-refused&bytes=268435457"
                "/raw/seq?key=sq-refused&bytes=01" "/raw/seq?key=&bytes=1" "/raw/seq?key=sq-refused&key=sq-refused&bytes=1"
                "/raw/seq?key=sq-refused&bytes=1&bytes=1" "/raw/seq?key=sq-refused&bytes=1&x=1" "/raw/seq?key=a%2Fb&bytes=1"
                "seen" "bad" "seen-bad")))

  ;; --- the raw face: /raw/retry's slow. The gap is judged between the
  ;; probe's arrivals: the body's first byte, then the rest, MS ms on; half
  ;; of it as the bound, as the drips', since the probe may read the first
  ;; late.
  (test-equal "raw /raw/retry, how=status, slow=300: the failure's head and its body's first byte, then the rest 150 ms or more after it and 300 ms or more after connecting, then eof; the next request's 200 comes whole, as without slow"
    (let ((body "attempt 1\n"))
      (list (list (string-append "HTTP/1.1 503 Retry\r\nContent-Length: 10\r\nConnection: close\r\n\r\n" body) 'eof)
            'rest-after-the-first 'rest-late-enough
            '("HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\nattempt 2\n" eof)))
    (guard (e (#t (list 'raised (describe e))))
      (let* ((p (wire-probe o 'raw (octets (get "/raw/retry?key=slow-1&fail=1&how=status&code=503&slow=300")) 2000))
             (head (string-length "HTTP/1.1 503 Retry\r\nContent-Length: 10\r\nConnection: close\r\n\r\n"))
             (first (arrival (probe-arrivals p) head))
             (rest (arrival (probe-arrivals p) (+ head 1)))
             (next (exchange o 'raw (get "/raw/retry?key=slow-1&fail=1&how=status&code=503&slow=300") 2000)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and first rest (>= (* 2 (- rest first)) 300)) 'rest-after-the-first
                  (list 'first first 'rest rest (probe-arrivals p)))
              (if (and rest (>= (- rest (probe-connected p)) 300)) 'rest-late-enough
                  (list 'connected (probe-connected p) 'rest rest))
              next))))
  (test-equal "raw /raw/retry, slow=0 and a Retry-After: the bytes as without slow"
    (list (list "HTTP/1.1 429 Retry\r\nRetry-After: 1\r\nContent-Length: 10\r\nConnection: close\r\n\r\nattempt 1\n" 'eof))
    (list (exchange o 'raw (get "/raw/retry?key=slow-0&fail=1&how=status&code=429&after=1&slow=0") 2000)))
  (test-equal "raw /raw/retry: slow with how=close or how=reset, above its range, with a leading zero, no number, or twice, gets the fixed 400 and counts nothing"
    (append (map (lambda (n) bad-request) '(1 2 3 4 5 6))
            (list (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nattempts 0\n") 'eof)))
    (in-order (lambda (target) (exchange o 'raw (get target) 2000))
              '("/raw/retry?key=slow-refused&fail=1&how=close&slow=1" "/raw/retry?key=slow-refused&fail=1&how=reset&slow=1"
                "/raw/retry?key=slow-refused&fail=1&how=status&code=503&slow=60001"
                "/raw/retry?key=slow-refused&fail=1&how=status&code=503&slow=01"
                "/raw/retry?key=slow-refused&fail=1&how=status&code=503&slow=x"
                "/raw/retry?key=slow-refused&fail=1&how=status&code=503&slow=1&slow=1"
                "/raw/attempts?key=slow-refused"))))

;; The scenarios' tests run here, in a definition, and the verdict on their
;; origin after. SRFI-64 keeps one result per runner: tests run inside another
;; test's actual expression overwrite its name and expected value, so a raise
;; from the origin's cleanup would be reported under the last scenario's name.
(define scenarios-outcome
  (outcome (lambda () (call-with-origin (lambda (o) (scenarios o) 'done)))))

(test-equal "the scenarios' origin starts, serves them all, and stops"
  '(returned done)
  scenarios-outcome)

;; --- the auth route ---------------------------------------------------------------
;; Each test runs on an origin of its own, so its connections are numbered
;; from 1 there, in the order this suite opens them, one a probe. The
;; Authorization headers are written here: Basic's base64 and Digest's
;; responses by (auth-testing), which tests/test-auth.sps holds to RFC
;; 1321's, FIPS 180-4's and RFC 4648's vectors, never by the origin.

;; make-list-of : Natural Any -> (Listof Any)
(define (make-list-of n x) (if (= n 0) '() (cons x (make-list-of (- n 1) x))))

;; with-origin : (Origin -> Any) -> (U (List 'returned Any) (List 'raised String))
(define (with-origin proc)
  (outcome (lambda () (call-with-origin proc))))

;; closed : String -> String
;; The http face's whole response with Connection: close: STATUS-LINE,
;; HEADERS, each "Name: value", then Content-Length and BODY.
(define (closed status-line headers body)
  (string-append status-line "\r\n"
                 (apply string-append (map (lambda (h) (string-append h "\r\n")) headers))
                 "Content-Length: " (number->string (string-length body)) "\r\nConnection: close\r\n\r\n" body))

(define auth-ok (list (closed "HTTP/1.1 200 OK" '() "auth ok\n") 'eof))

;; refused-with : String -> (List String Symbol)
;; The 401 the auth route answers with the challenge CHALLENGE, or none for #f.
(define (refused-with challenge)
  (list (closed "HTTP/1.1 401 Unauthorized" (if challenge (list (string-append "WWW-Authenticate: " challenge)) '())
                "unauthorized\n")
        'eof))

(define basic-challenge "Basic realm=\"chez-curl-test\"")
(define bearer-challenge "Bearer realm=\"chez-curl-test\"")

;; basic-of : String -> String
;; "Basic " and the base64 of TEXT's Latin-1 bytes.
(define (basic-of text) (string-append "Basic " (base64-encode (octets text))))

;; digest-of : Symbol String String String String String (U String #f) (U String #f) String -> String
;; A Digest Authorization value, as libcurl writes one: HASH md5 or
;; sha-256, ALG its token, the account's USER and PASS, NONCE, URI, and
;; with QOP auth, CNONCE and nc 00000001; RESPONSE, when a string, in
;; place of the right one.
(define (digest-of hash alg user pass nonce uri qop cnonce response)
  (let ((right (digest-response hash (octets user) "chez-curl-test" (octets pass) nonce cnonce
                                (and qop "00000001") qop "GET" uri)))
    (string-append "Digest username=\"" user "\", realm=\"chez-curl-test\", nonce=\"" nonce "\", uri=\"" uri "\", "
                   (if qop (string-append "cnonce=\"" cnonce "\", nc=00000001, qop=" qop ", ") "")
                   "response=\"" (if (string? response) response right) "\", opaque=\"opq5ccb\", algorithm=" alg)))

;; logged : Origin String -> (List String Symbol)
;; The auth log of KEY, by the http face, Connection: close.
(define (logged o key)
  (exchange o 'http (get (string-append "/auth-log?key=" key) close) 2000))

;; log-text : String (Listof String) -> (List String Symbol)
;; /auth-log's whole answer for KEY's LINES.
(define (log-text key lines)
  (list (closed "HTTP/1.1 200 OK" '()
                (apply string-append "log " key " " (number->string (length lines)) "\n"
                       (map (lambda (l) (string-append l "\n")) lines)))
        'eof))

(define (auth-scenarios)
  (test-equal "the auth route's Basic: no credentials, a 401 with Basic's challenge; the account's, 200; a wrong password, 401; a post's body read and logged, the pattern's and one with a stray byte; the log, each request on its connection, whole"
    (list 'returned
          (list (refused-with basic-challenge) auth-ok (refused-with basic-challenge) auth-ok auth-ok
                (log-text "b" (list "request 1 face=http conn=1 method=GET body=0 verdict=none status=401 authorization=-"
                                    "request 2 face=http conn=2 method=GET body=0 verdict=ok status=200 authorization=Basic dXNlcjpwYXNz"
                                    "request 3 face=http conn=3 method=GET body=0 verdict=bad status=401 authorization=Basic dXNlcjp3cm9uZw=="
                                    "request 4 face=http conn=4 method=POST body=10 verdict=ok status=200 authorization=Basic dXNlcjpwYXNz"
                                    "request 5 face=http conn=5 method=POST body=10:bad@7 verdict=ok status=200 authorization=Basic dXNlcjpwYXNz"))))
    (with-origin
     (lambda (o)
       (let* ((p10 (pattern-text 10))
              (bad7 (string-append (substring p10 0 7) "x" (substring p10 8 10)))
              (a (exchange o 'http (get "/auth?key=b&ch=basic" close) 2000))
              (b (exchange o 'http (get "/auth?key=b&ch=basic" "Authorization: Basic dXNlcjpwYXNz\r\n" close) 2000))
              (c (exchange o 'http (get "/auth?key=b&ch=basic" (string-append "Authorization: " (basic-of "user:wrong") "\r\n") close) 2000))
              (d (exchange o 'http (string-append (post "/auth?key=b&ch=basic" "Authorization: Basic dXNlcjpwYXNz\r\n"
                                                        "Content-Length: 10\r\n" close) p10) 2000))
              (e (exchange o 'http (string-append (post "/auth?key=b&ch=basic" "Authorization: Basic dXNlcjpwYXNz\r\n"
                                                        "Content-Length: 10\r\n" close) bad7) 2000))
              (log (logged o "b")))
         (list a b c d e log)))))

  (test-equal "the auth route's Bearer: no credentials, a 401 with Bearer's challenge; the token, 200; Basic credentials that pass, judged ok but not the route's scheme, 401; a scheme it does not know, other; a second Authorization header, logged as one more beside the first, which is judged"
    (list 'returned
          (list (refused-with bearer-challenge) auth-ok (refused-with bearer-challenge) (refused-with bearer-challenge)
                auth-ok
                (log-text "t" (list "request 1 face=http conn=1 method=GET body=0 verdict=none status=401 authorization=-"
                                    "request 2 face=http conn=2 method=GET body=0 verdict=ok status=200 authorization=Bearer tok123"
                                    "request 3 face=http conn=3 method=GET body=0 verdict=ok status=401 authorization=Basic dXNlcjpwYXNz"
                                    "request 4 face=http conn=4 method=GET body=0 verdict=other status=401 authorization=Negotiate abc"
                                    "request 5 face=http conn=5 method=GET body=0 verdict=ok status=200 authorization=Bearer tok123 (+1 more)"))))
    (with-origin
     (lambda (o)
       (let* ((a (exchange o 'http (get "/auth?key=t&ch=bearer" close) 2000))
              (b (exchange o 'http (get "/auth?key=t&ch=bearer" "Authorization: Bearer tok123\r\n" close) 2000))
              (c (exchange o 'http (get "/auth?key=t&ch=bearer" "Authorization: Basic dXNlcjpwYXNz\r\n" close) 2000))
              (d (exchange o 'http (get "/auth?key=t&ch=bearer" "Authorization: Negotiate abc\r\n" close) 2000))
              (e (exchange o 'http (get "/auth?key=t&ch=bearer" "Authorization: Bearer tok123\r\n"
                                        "Authorization: Bearer other\r\n" close) 2000))
              (log (logged o "t")))
         (list a b c d e log)))))

  (let* ((uri "/auth?key=d&ch=digest&nonce=abc&qop=none")
         (challenge "Digest realm=\"chez-curl-test\", nonce=\"abc\", opaque=\"opq5ccb\", algorithm=MD5"))
    (test-equal "the auth route's Digest with no qop: no credentials, a 401 with the challenge, its nonce the query's; the response computed here, 200; a wrong one, bad(response); another uri, its response computed for it, bad(uri); a nonce never issued, bad(nonce); the log whole"
      (list 'returned
            (list (refused-with challenge) auth-ok (refused-with challenge) (refused-with challenge) (refused-with challenge)
                  (log-text "d"
                            (list "request 1 face=http conn=1 method=GET body=0 verdict=none status=401 authorization=-"
                                  (string-append "request 2 face=http conn=2 method=GET body=0 verdict=ok status=200 authorization="
                                                 (digest-of 'md5 "MD5" "user" "pass" "abc" uri #f #f #f))
                                  (string-append "request 3 face=http conn=3 method=GET body=0 verdict=bad(response) status=401 authorization="
                                                 (digest-of 'md5 "MD5" "user" "pass" "abc" uri #f #f "00000000000000000000000000000000"))
                                  (string-append "request 4 face=http conn=4 method=GET body=0 verdict=bad(uri) status=401 authorization="
                                                 (digest-of 'md5 "MD5" "user" "pass" "abc" "/other" #f #f #f))
                                  (string-append "request 5 face=http conn=5 method=GET body=0 verdict=bad(nonce) status=401 authorization="
                                                 (digest-of 'md5 "MD5" "user" "pass" "never" uri #f #f #f))))))
      (with-origin
       (lambda (o)
         (let* ((with (lambda (value) (exchange o 'http (get uri (string-append "Authorization: " value "\r\n") close) 2000)))
                (a (exchange o 'http (get uri close) 2000))
                (b (with (digest-of 'md5 "MD5" "user" "pass" "abc" uri #f #f #f)))
                (c (with (digest-of 'md5 "MD5" "user" "pass" "abc" uri #f #f "00000000000000000000000000000000")))
                (d (with (digest-of 'md5 "MD5" "user" "pass" "abc" "/other" #f #f #f)))
                (e (with (digest-of 'md5 "MD5" "user" "pass" "never" uri #f #f #f)))
                (log (logged o "d")))
           (list a b c d e log))))))

  (let* ((uri "/auth?key=s&ch=digest&alg=SHA-256&nonce=xyz")
         (challenge "Digest realm=\"chez-curl-test\", qop=\"auth\", nonce=\"xyz\", opaque=\"opq5ccb\", algorithm=SHA-256"))
    (test-equal "the auth route's Digest by SHA-256 with qop auth: the challenge offers qop=\"auth\"; the response computed here, with its cnonce and nc, 200; one with no qop where it was offered, its response RFC 2069's, bad(qop,nc,cnonce)"
      (list 'returned
            (list (refused-with challenge) auth-ok (refused-with challenge)
                  (log-text "s"
                            (list "request 1 face=http conn=1 method=GET body=0 verdict=none status=401 authorization=-"
                                  (string-append "request 2 face=http conn=2 method=GET body=0 verdict=ok status=200 authorization="
                                                 (digest-of 'sha-256 "SHA-256" "user" "pass" "xyz" uri "auth" "c0ffee" #f))
                                  (string-append "request 3 face=http conn=3 method=GET body=0 verdict=bad(qop,nc,cnonce) status=401 authorization="
                                                 (digest-of 'sha-256 "SHA-256" "user" "pass" "xyz" uri #f #f #f))))))
      (with-origin
       (lambda (o)
         (let* ((with (lambda (value) (exchange o 'http (get uri (string-append "Authorization: " value "\r\n") close) 2000)))
                (a (exchange o 'http (get uri close) 2000))
                (b (with (digest-of 'sha-256 "SHA-256" "user" "pass" "xyz" uri "auth" "c0ffee" #f)))
                (c (with (digest-of 'sha-256 "SHA-256" "user" "pass" "xyz" uri #f #f #f)))
                (log (logged o "s")))
           (list a b c log))))))

  (let ((uri "/auth?key=st&ch=digest&stale=forever&nonce=st&qop=none"))
    (test-equal "the auth route's stale=forever: each Digest answer that passes gets a 401 with a fresh nonce, the query's and a count, and stale=true"
      (list 'returned
            (list (refused-with "Digest realm=\"chez-curl-test\", nonce=\"st-1\", opaque=\"opq5ccb\", algorithm=MD5, stale=true")
                  (refused-with "Digest realm=\"chez-curl-test\", nonce=\"st-2\", opaque=\"opq5ccb\", algorithm=MD5, stale=true")))
      (with-origin
       (lambda (o)
         (let* ((first (exchange o 'http (get uri close) 2000))
                (with (lambda (nonce)
                        (exchange o 'http (get uri (string-append "Authorization: " (digest-of 'md5 "MD5" "user" "pass" nonce uri #f #f #f)
                                                                  "\r\n")
                                               close)
                                  2000)))
                (a (with "st"))
                (b (with "st-1")))
           (list a b))))))

  (test-equal "the auth route's other answers: none, a 401 with no challenge, credentials that pass or not; open, a 200 to any; size=5, the pattern's first five bytes; an account in the query, its bytes percent-decoded, a UTF-8 user and an empty password, and a token"
    (list 'returned
          (list (refused-with #f) auth-ok
                (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\n" (pattern-text 5)) 'eof)
                auth-ok auth-ok))
    (with-origin
     (lambda (o)
       (let* ((a (exchange o 'http (get "/auth?key=n&ch=none" "Authorization: Basic dXNlcjpwYXNz\r\n" close) 2000))
              (b (exchange o 'http (get "/auth?key=n&ch=open" close) 2000))
              (c (exchange o 'http (get "/auth?key=n&ch=open&size=5" close) 2000))
              (d (exchange o 'http (get "/auth?key=n&ch=basic&u=%C3%bcser&p="
                                        (string-append "Authorization: " (basic-of "\xC3;\xBC;ser:") "\r\n") close)
                           2000))
              (e (exchange o 'http (get "/auth?key=n&ch=bearer&tok=%41b" "Authorization: Bearer Ab\r\n" close) 2000)))
         (list a b c d e)))))

  (test-equal "the auth routes refuse a query by /sink's rules, 404: none, no key, no ch, an unknown ch, an unknown name, a name twice, an unknown alg, a size of 0, a malformed %, and /auth-log with no key or another name; /auth-log for a key never seen is its empty log"
    (list 'returned
          (append (make-list-of 11 not-found-close) (list (log-text "never" '()))))
    (with-origin
     (lambda (o)
       (map (lambda (target) (exchange o 'http (get target close) 2000))
            '("/auth" "/auth?ch=basic" "/auth?key=k" "/auth?key=k&ch=ntlm" "/auth?key=k&ch=basic&x=1"
              "/auth?key=k&ch=basic&ch=basic" "/auth?key=k&ch=digest&alg=MD4" "/auth?key=k&ch=open&size=0"
              "/auth?key=k&ch=basic&u=%G1" "/auth-log" "/auth-log?key=k&x=1" "/auth-log?key=never")))))

  ;; One connection, four requests in one write: the first and third carry
  ;; Expect: 100-continue, the third its body after its head anyway; each
  ;; answered in turn, the connection kept, so the probe ends by its idle
  ;; bound.
  (test-equal "/raw/auth417 keeps its connection: a request whose Expect holds 100-continue gets a 417 as its head arrives; the next bytes decide, a letter the next request, a body the refused one's, dropped; one without gets its body read and a 200; each logged to the key's auth log"
    (list 'returned
          (list (list (string-append "HTTP/1.1 417 Expectation Failed\r\nContent-Length: 19\r\n\r\nexpectation failed\n"
                                     "HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nauth ok\n"
                                     "HTTP/1.1 417 Expectation Failed\r\nContent-Length: 19\r\n\r\nexpectation failed\n"
                                     "HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nauth ok\n")
                      'timeout)
                (log-text "e" (list "request 1 face=raw conn=1 method=POST body=- verdict=ok status=417 authorization=Basic dXNlcjpwYXNz"
                                    "request 2 face=raw conn=1 method=POST body=5 verdict=none status=200 authorization=-"
                                    "request 3 face=raw conn=1 method=POST body=- verdict=none status=417 authorization=-"
                                    "request 4 face=raw conn=1 method=GET body=0 verdict=none status=200 authorization=-"))))
    (with-origin
     (lambda (o)
       (let* ((p5 (pattern-text 5))
              (a (exchange o 'raw (string-append (post "/raw/auth417?key=e" "Authorization: Basic dXNlcjpwYXNz\r\n"
                                                       "Expect: 100-continue\r\n" "Content-Length: 5\r\n")
                                                 (post "/raw/auth417?key=e" "Content-Length: 5\r\n") p5
                                                 (post "/raw/auth417?key=e" "Expect: 100-Continue\r\n" "Content-Length: 5\r\n") p5
                                                 (get "/raw/auth417?key=e"))
                           500))
              (log (logged o "e")))
         (list a log))))))

(auth-scenarios)

;; --- the proxy ------------------------------------------------------------------------
;; Each test runs on an origin of its own, so the proxy's connections are
;; numbered from 1 there, in the order this suite's probes open them; a
;; probe that reads /proxy-log comes direct, and is no proxy's. The
;; credentials are written here, by (auth-testing)'s base64, which
;; tests/test-auth.sps holds to RFC 4648's vectors.

;; proxy-log-of : Origin -> (U String (List 'raised String))
;; The whole of /proxy-log?from=0, its body, once the proxy holds no
;; connection open, waited for up to 5 s; what came last otherwise.
(define (proxy-log-of o)
  (let ((deadline (+ (now-ms) 5000)))
    (let loop ()
      (let* ((a (exchange o 'http (get "/proxy-log?from=0" close) 2000))
             (text (and (pair? a) (string? (car a)) (body-of (car a)))))
        (cond ((not text) a)
              ((or (contains-text? text " open 0\n") (>= (now-ms) deadline)) text)
              (else (pause-ms 20) (loop)))))))

;; body-of : String -> String
;; RESPONSE's text after its head's CRLF CRLF, or all of it with none.
(define (body-of response)
  (let loop ((i 0))
    (cond ((> (+ i 4) (string-length response)) response)
          ((string=? (substring response i (+ i 4)) "\r\n\r\n") (substring response (+ i 4) (string-length response)))
          (else (loop (+ i 1))))))

;; contains-text? : String String -> Boolean
(define (contains-text? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n) (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

;; proxy-log-text : (Listof String) -> String
;; The log /proxy-log?from=0 answers with LINES and no connection open.
(define (proxy-log-text lines)
  (apply string-append "proxy-log " (number->string (length lines)) " open 0\n"
         (map (lambda (line) (string-append line "\n")) lines)))

;; settled : Origin (-> Any) -> Any
;; THUNK's answer, once the proxy holds no connection open after it, so
;; the next probe's lines come after its close.
(define (settled o thunk)
  (let ((answer (thunk)))
    (proxy-log-of o)
    answer))

;; connect-text : String . String -> String
;; A CONNECT of TARGET, its Host, then HEADERS, each a whole line, as a
;; client writes one.
(define (connect-text target . headers)
  (apply string-append "CONNECT " target " HTTP/1.1\r\nHost: " target "\r\n" (append headers (list "\r\n"))))

;; basic-line : String -> String
;; A Proxy-Authorization line of Basic for BYTES, a string of chars below
;; 256, each its byte.
(define (basic-line bytes)
  (string-append "Proxy-Authorization: Basic " (base64-encode (octets bytes)) "\r\n"))

;; refusal-bytes : Natural String (U String #f) -> String
;; The proxy's refusal STATUS REASON, with CHALLENGE when given.
(define (refusal-bytes status reason challenge)
  (let ((body (string-append "proxy " (number->string status) "\n")))
    (string-append "HTTP/1.1 " (number->string status) " " reason "\r\n"
                   (if challenge (string-append "Proxy-Authenticate: " challenge "\r\n") "")
                   "Content-Length: " (number->string (string-length body)) "\r\n\r\n" body)))

(define proxy-challenge "Basic realm=\"chez-curl-proxy\"")
(define tunnel-200 "HTTP/1.1 200 Connection Established\r\n\r\n")
(define forbidden-end "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")

(define (proxy-scenarios)
  (test-equal "the proxy's refusals: a CONNECT to refuse-S.invalid gets S, 403, 407 with Basic's challenge, 502 or 503, Content-Length and proxy S, the connection kept, so the probe ends by its idle bound; a client's end then ends it, eof; close.invalid ends at once, nothing written; any other host, refuse-404 among them, and 127.0.0.1 at a port no face has, 403 and the end; the log, each CONNECT with its answer and its head's bytes, then its close"
    (let ((head (lambda (target) (string-length (connect-text target)))))
      (list 'returned
            (list (list (refusal-bytes 403 "Forbidden" #f) 'timeout)
                  (list (refusal-bytes 407 "Proxy Authentication Required" proxy-challenge) 'timeout)
                  (list (refusal-bytes 502 "Bad Gateway" #f) 'timeout)
                  (list (refusal-bytes 503 "Service Unavailable" #f) 'timeout)
                  (list (refusal-bytes 503 "Service Unavailable" #f) 'eof)
                  '("" eof)
                  (list forbidden-end 'eof)
                  (list forbidden-end 'eof)
                  (proxy-log-text
                   (list (string-append "connect http conn=1 target=refuse-403.invalid:443 answer=403 head="
                                        (number->string (head "refuse-403.invalid:443")) " auth=-")
                         "close http conn=1"
                         (string-append "connect http conn=2 target=refuse-407.invalid:443 answer=407 head="
                                        (number->string (head "refuse-407.invalid:443")) " auth=-")
                         "close http conn=2"
                         (string-append "connect http conn=3 target=refuse-502.invalid:8080 answer=502 head="
                                        (number->string (head "refuse-502.invalid:8080")) " auth=-")
                         "close http conn=3"
                         (string-append "connect http conn=4 target=refuse-503.invalid:1 answer=503 head="
                                        (number->string (head "refuse-503.invalid:1")) " auth=-")
                         "close http conn=4"
                         (string-append "connect http conn=5 target=refuse-503.invalid:1 answer=503 head="
                                        (number->string (head "refuse-503.invalid:1")) " auth=-")
                         "close http conn=5"
                         (string-append "connect http conn=6 target=close.invalid:443 answer=close head="
                                        (number->string (head "close.invalid:443")) " auth=-")
                         "close http conn=6"
                         (string-append "connect http conn=7 target=refuse-404.invalid:443 answer=403 head="
                                        (number->string (head "refuse-404.invalid:443")) " auth=-")
                         "close http conn=7"
                         (string-append "connect http conn=8 target=127.0.0.1:1 answer=403 head="
                                        (number->string (head "127.0.0.1:1")) " auth=-")
                         "close http conn=8")))))
    (with-origin
     (lambda (o)
       (let* ((one (lambda (text) (settled o (lambda () (exchange o 'http text 300)))))
              (a (one (connect-text "refuse-403.invalid:443")))
              (b (one (connect-text "refuse-407.invalid:443")))
              (c (one (connect-text "refuse-502.invalid:8080")))
              (d (one (connect-text "refuse-503.invalid:1")))
              (e (settled o (lambda ()
                              (guard (x (#t (list 'raised (describe x))))
                                (let ((p (wire-probe-half-close o 'http (octets (connect-text "refuse-503.invalid:1")) 2000)))
                                  (list (latin-1 (probe-bytes p)) (probe-end p)))))))
              (f (one (connect-text "close.invalid:443")))
              (g (one (connect-text "refuse-404.invalid:443")))
              (h (one (connect-text "127.0.0.1:1"))))
         (list a b c d e f g h (proxy-log-of o))))))

  ;; The tests whose bytes name the origin's ports build them from it, and
  ;; answer same, or what was wanted and what came.
  (test-equal "the proxy's tunnels: CONNECT 127.0.0.1 at the raw face, a request behind it, gets the tunnel's 200, then raw's bytes, then eof; at the http face, a GET behind it, the tunnel's 200, then the face's answer, logged as an inner request through the proxy's connection; a direct request after is no inner one; the log whole"
    '(returned same)
    (with-origin
     (lambda (o)
       (let* ((raw (string-append "127.0.0.1:" (number->string (cdr (origin-face o 'raw)))))
              (http (string-append "127.0.0.1:" (number->string (cdr (origin-face o 'http)))))
              (want (list (list (string-append tunnel-200 "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n") 'eof)
                          (list (string-append tunnel-200 "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n") 'eof)
                          (list "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" 'eof)
                          (proxy-log-text
                           (list (string-append "connect http conn=1 target=" raw " answer=200 head="
                                                (number->string (string-length (connect-text raw))) " auth=-")
                                 "close http conn=1"
                                 (string-append "connect http conn=2 target=" http " answer=200 head="
                                                (number->string (string-length (connect-text http))) " auth=-")
                                 "inner http via=2 method=GET target=/status/200"
                                 "close http conn=2"))))
              (a (settled o (lambda () (exchange o 'http (string-append (connect-text raw) (get "/raw/content-length")) 2000))))
              (b (settled o (lambda () (exchange o 'http (string-append (connect-text http) (get "/status/200" close)) 2000))))
              (c (settled o (lambda () (exchange o 'http (get "/status/200" close) 2000))))
              (got (list a b c (proxy-log-of o))))
         (if (equal? want got) 'same (list 'want want 'got got))))))

  (test-equal "the proxy's Basic, a CONNECT to localhost at a face: no Proxy-Authorization, 407 with the challenge; alice and s3cret, the tunnel; bob and hunter2 too, the scheme in lower case; alice with another password, a byte more, Bearer, or a second header behind a wrong first, 407; each decoded on the log, a byte outside the printable as \\xNN"
    '(returned same)
    (with-origin
     (lambda (o)
       (let* ((port (number->string (cdr (origin-face o 'http))))
              (target (string-append "localhost:" port))
              (behind (get "/status/204" close))
              (denied (list (refusal-bytes 407 "Proxy Authentication Required" proxy-challenge) 'timeout))
              (passed (list (string-append tunnel-200 "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n") 'eof))
              (cases (list (list "" "")
                           (list (basic-line "alice:s3cret") behind)
                           (list (string-append "Proxy-Authorization: basic " (base64-encode (octets "bob:hunter2")) "\r\n") behind)
                           (list (basic-line "alice:wrong") "")
                           (list (basic-line "alice:s3cret ") "")
                           (list "Proxy-Authorization: Bearer s3cret\r\n" "")
                           (list (string-append (basic-line "eve:\r\n\xff;") (basic-line "alice:s3cret")) "")))
              (head (lambda (c) (string-length (connect-text target (car c)))))
              (want (list denied passed passed denied denied denied denied
                          (proxy-log-text
                           (list (string-append "connect http conn=1 target=" target " answer=407 head="
                                                (number->string (head (list-ref cases 0))) " auth=-")
                                 "close http conn=1"
                                 (string-append "connect http conn=2 target=" target " answer=200 head="
                                                (number->string (head (list-ref cases 1))) " auth=basic:alice:s3cret")
                                 "inner http via=2 method=GET target=/status/204"
                                 "close http conn=2"
                                 (string-append "connect http conn=3 target=" target " answer=200 head="
                                                (number->string (head (list-ref cases 2))) " auth=basic:bob:hunter2")
                                 "inner http via=3 method=GET target=/status/204"
                                 "close http conn=3"
                                 (string-append "connect http conn=4 target=" target " answer=407 head="
                                                (number->string (head (list-ref cases 3))) " auth=basic:alice:wrong")
                                 "close http conn=4"
                                 (string-append "connect http conn=5 target=" target " answer=407 head="
                                                (number->string (head (list-ref cases 4))) " auth=basic:alice:s3cret ")
                                 "close http conn=5"
                                 (string-append "connect http conn=6 target=" target " answer=407 head="
                                                (number->string (head (list-ref cases 5))) " auth=other:Bearer s3cret")
                                 "close http conn=6"
                                 (string-append "connect http conn=7 target=" target " answer=407 head="
                                                (number->string (head (list-ref cases 6))) " auth=basic:eve:\\x0d\\x0a\\xff (+1 more)")
                                 "close http conn=7"))))
              ;; Each case in turn, then the log: map's order is no order,
              ;; and append's arguments run right to left.
              (got (let loop ((rest cases) (found '()))
                     (if (null? rest)
                         (reverse (cons (proxy-log-of o) found))
                         (let ((a (settled o (lambda ()
                                               (exchange o 'http (string-append (connect-text target (caar rest))
                                                                                (cadar rest))
                                                         (if (string=? (cadar rest) "") 300 2000))))))
                           (loop (cdr rest) (cons a found)))))))
         (if (equal? want got) 'same (list 'want want 'got got))))))

  (test-equal "the proxy's log of a request in absolute form: its method, its target as it came, and its first Proxy-Authorization decoded, the face answering by its path; one by its path alone is no proxy's"
    (list 'returned
          (list (list "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" 'eof)
                (list "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n" 'eof)
                (list "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" 'eof)
                (proxy-log-text
                 '("request http conn=1 method=GET target=http://127.0.0.1:1/status/200 auth=basic:u\\x0d\\x0ax:\\xffp"
                   "close http conn=1"
                   "request http conn=2 method=POST target=http://a.example/status/204 auth=other:Digest x=\"y\""
                   "close http conn=2"))))
    (with-origin
     (lambda (o)
       (let* ((a (settled o (lambda () (exchange o 'http (string-append "GET http://127.0.0.1:1/status/200 HTTP/1.1\r\nHost: 127.0.0.1:1\r\n"
                                                                        (basic-line "u\r\nx:\xff;p") close "\r\n")
                                                 2000))))
              (b (settled o (lambda () (exchange o 'http (string-append "POST http://a.example/status/204 HTTP/1.1\r\nHost: a.example\r\n"
                                                                        "Proxy-Authorization: Digest x=\"y\"\r\nContent-Length: 0\r\n"
                                                                        close "\r\n")
                                                 2000))))
              (c (settled o (lambda () (exchange o 'http (get "/status/200" close) 2000)))))
         (list a b c (proxy-log-of o))))))

  (test-equal "/proxy-log refuses a query by /sink's rules, 404: none, an empty from, a word, a sign, a leading zero, another name, from twice; from past the end answers the head alone; on an origin no proxy has served, the empty log"
    (list 'returned
          (append (make-list-of 7 '("HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n" eof))
                  (list (list (closed "HTTP/1.1 200 OK" '() "proxy-log 0 open 0\n") 'eof)
                        (list (closed "HTTP/1.1 200 OK" '() "proxy-log 0 open 0\n") 'eof))))
    (with-origin
     (lambda (o)
       (map (lambda (target) (exchange o 'http (get target close) 2000))
            '("/proxy-log" "/proxy-log?from=" "/proxy-log?from=x" "/proxy-log?from=-1" "/proxy-log?from=01"
              "/proxy-log?to=0" "/proxy-log?from=0&from=0" "/proxy-log?from=5" "/proxy-log?from=0"))))))

(proxy-scenarios)

;; --- the cookie route ----------------------------------------------------------------
;; Each test runs on an origin of its own. Every expected byte is written
;; here, never read from the origin.

;; cookie-quoted : String -> String
;; TEXT, a Latin-1 string, as the cookie route quotes a value: printable
;; ASCII as it is, but \ as \\ and " as \x22, every other byte \xNN, lower
;; case, inside quotes.
(define (cookie-quoted text)
  (string-append
   "\""
   (apply string-append
          (map (lambda (c)
                 (let ((b (char->integer c)))
                   (cond ((= b #x5c) "\\\\")
                         ((or (< b #x20) (> b #x7e) (= b #x22))
                          (string #\\ #\x (string-ref "0123456789abcdef" (div b 16))
                                  (string-ref "0123456789abcdef" (mod b 16))))
                         (else (string c)))))
               (string->list text)))
   "\""))

;; cookie-log-text : String (Listof String) -> (List String Symbol)
;; /cookie-log's whole answer for KEY's LINES, Connection: close.
(define (cookie-log-text key lines)
  (list (closed "HTTP/1.1 200 OK" '()
                (apply string-append "cookie-log " key " " (number->string (length lines)) "\n"
                       (map (lambda (l) (string-append l "\n")) lines)))
        'eof))

;; cookie-logged : Origin String -> (List String Symbol)
(define (cookie-logged o key)
  (exchange o 'http (get (string-append "/cookie-log?key=" key) close) 2000))

(define (cookie-scenarios)
  (test-equal "the cookie route: each set= a Set-Cookie, its bytes as given, a tab, a quote and 0xE9 among them, in order; the status and Location the query names; the request's Host and every Cookie header, in any case, each value whole, as its body; numbered for its key"
    (list 'returned
          (list (list (closed "HTTP/1.1 302 Found"
                              (list "Set-Cookie: a=1" (string-append "Set-Cookie: b=" (string (integer->char #xE9)) "\tx\"")
                                    "Location: http://b.a.localhost:1/x")
                              (string-append "request 1 face=http host=" (cookie-quoted "127.0.0.1") " cookies=2 cookie="
                                             (cookie-quoted "n=1; m=\"2\"") " cookie="
                                             (cookie-quoted (string (integer->char #xE9) #\\ #\;)) "\n"))
                      'eof)
                (list (closed "HTTP/1.1 200 OK" '()
                              (string-append "request 2 face=http host=" (cookie-quoted "127.0.0.1") " cookies=0\n"))
                      'eof)
                (list "HTTP/1.1 204 No Content\r\nSet-Cookie: z=\r\nConnection: close\r\n\r\n" 'eof)))
    (with-origin
     (lambda (o)
       (let* ((a (exchange o 'http (get "/cookies?key=c1&set=a%3D1&set=b%3D%E9%09x%22&status=302&to=http%3A%2F%2Fb.a.localhost%3A1%2Fx"
                                        "Cookie: n=1; m=\"2\"\r\n"
                                        (string-append "cOOKIE: " (string (integer->char #xE9) #\\ #\;) "\r\n")
                                        close)
                           2000))
              (b (exchange o 'http (get "/cookies?key=c1" close) 2000))
              (c (exchange o 'http (get "/cookies?status=204&key=c2&set=z%3D" close) 2000)))
         (list a b c)))))

  (test-equal "the cookie route's log, whole: each request's line, in order, a 204's among them, and none for another key"
    (list 'returned
          (list (cookie-log-text "c3" (list (string-append "request 1 face=http host=" (cookie-quoted "127.0.0.1") " cookies=1 cookie=" (cookie-quoted "k=1"))
                                            (string-append "request 2 face=http host=" (cookie-quoted "a.localhost:9") " cookies=0")))
                (cookie-log-text "c4" '())))
    (with-origin
     (lambda (o)
       (exchange o 'http (get "/cookies?key=c3" "Cookie: k=1\r\n" close) 2000)
       (exchange o 'http (string-append "GET /cookies?key=c3&status=204 HTTP/1.1\r\nHost: a.localhost:9\r\n" close "\r\n") 2000)
       (list (cookie-logged o "c3") (cookie-logged o "c4")))))

  (test-equal "the cookie route refuses, 404, a query that breaks its rules: no key, a key twice, a status out of range, a set= holding 0x01, 0x0A or 0x7F, a malformed %, a to= with a space, a pad= of another letter, a name it does not take; and logs none of them"
    (list 'returned
          (append (make-list-of 10 (list (closed "HTTP/1.1 404 Not Found" '() "not found\n") 'eof))
                  (list (cookie-log-text "c5" '()))))
    (with-origin
     (lambda (o)
       (append
        (map (lambda (target) (exchange o 'http (get target close) 2000))
             '("/cookies?set=a%3D1" "/cookies?key=c5&key=c5" "/cookies?key=c5&status=199"
               "/cookies?key=c5&set=a%01" "/cookies?key=c5&set=a%0A" "/cookies?key=c5&set=a%7F"
               "/cookies?key=c5&set=a%2" "/cookies?key=c5&to=a%20b" "/cookies?key=c5&pad=pq"
               "/cookies?key=c5&nope=1"))
        (list (cookie-logged o "c5"))))))

  (test-equal "the http face keeps a cookie route's connection alive: two requests on one connection, each answered in turn, Connection: keep-alive"
    (let ((body (lambda (n) (string-append "request " n " face=http host=" (cookie-quoted "127.0.0.1") " cookies=0\n"))))
      (list 'returned
            (list (string-append
                   "HTTP/1.1 200 OK\r\nSet-Cookie: k=1\r\nContent-Length: "
                   (number->string (string-length (body "1"))) "\r\nConnection: keep-alive\r\n\r\n" (body "1")
                   (closed "HTTP/1.1 200 OK" '() (body "2")))
                  'eof)))
    (with-origin
     (lambda (o)
       (exchange o 'http (string-append (get "/cookies?key=c6&set=k%3D1") (get "/cookies?key=c6" close)) 2000))))

  (test-equal "a head left open as its connection closes is logged to its /cookies request's key, its bytes and what followed its request line, quoted; a whole one, and an open head of another route, log none; Node answers the open one 400"
    (list 'returned
          (list (list "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n" 'eof)
                (list "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n" 'eof)
                (cookie-log-text "c7" (list (string-append "request 1 face=http host=" (cookie-quoted "127.0.0.1") " cookies=0")
                                            (string-append "open-head face=http bytes=78 headers="
                                                           (cookie-quoted "Host: 127.0.0.1\r\nAccept: */*\r\nCookie: \r\n"))))))
    (with-origin
     (lambda (o)
       (let* ((whole (exchange o 'http (get "/cookies?key=c7" close) 2000))
              (open (let ((p (wire-probe-half-close o 'http (octets "GET /cookies?key=c7&pad=ppp HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: */*\r\nCookie: \r\n") 2000)))
                      (list (latin-1 (probe-bytes p)) (probe-end p))))
              (other (let ((p (wire-probe-half-close o 'http (octets "GET /status/200?key=c7 HTTP/1.1\r\nHost: 127.0.0.1\r\n") 2000)))
                       (list (latin-1 (probe-bytes p)) (probe-end p)))))
         (list open other (cookie-logged o "c7")))))))

(cookie-scenarios)

;; --- lifecycle: OS ports, two origins at once ---------------------------------

(test-equal "OS ports: two origins at once announce four ports, none 0 and all different, and both serve"
  '(returned (distinct
              (("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)
               ("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" eof))
              (("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)
               ("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" eof))))
  (outcome
   (lambda ()
     (call-with-origin
      (lambda (a)
        (call-with-origin
         (lambda (b)
           (let* ((ports (map (lambda (o face) (cdr (origin-face o face)))
                              (list a a b b) '(http raw http raw)))
                  (serves (lambda (o)
                            (list (exchange o 'raw (get "/raw/content-length") 2000)
                                  (exchange o 'http (get "/status/200" close) 2000)))))
             (list (if (and (not (memv 0 ports))
                            (= (length ports)
                               (length (fold-left (lambda (seen p) (if (memv p seen) seen (cons p seen)))
                                                  '() ports))))
                       'distinct
                       (list 'ports ports))
                   (serves a)
                   (serves b))))))))))

;; --- lifecycle: the exit on stdin's end -----------------------------------------

(define refused '(("" (refused "ECONNREFUSED")) ("" (refused "ECONNREFUSED")) ("" (refused "ECONNREFUSED"))))

;; bounded* : (Listof String) -> (List Integer String String)
(define (bounded* args) (apply bounded args))

(test-equal "the announcement's pid is the Node process the call started: alive during the call, gone after it"
  '(returned (0 1))
  (outcome
   (lambda ()
     (let* ((during #f)
            (o (call-with-origin
                (lambda (o)
                  (set! during (car (capture-command (list "kill" "-0" (number->string (origin-pid o))))))
                  o))))
       (list during (car (capture-command (list "kill" "-0" (number->string (origin-pid o))))))))))

;; --- lifecycle: the stop ---------------------------------------------------------
;; An end proves the stop only when nothing but the origin's stop can
;; explain it: its destroy, or its exit, which closes every socket alike at
;; the TCP level, so no check here tells the two apart. Three other things
;; end connections, and the check rules out each by its mechanism:
;;
;; - Node's own server.close(). It ends some waiting states with nothing
;;   tracked, so an end there proves nothing; each face here also waits in
;;   states it does not end. Untracked, close() ends, by face (measured on
;;   Node 24.18.0 and 20.10.0):
;;     http   idle after a whole keep-alive response, within 1 ms, on both;
;;            never a connection with nothing sent, a partial head, or a body
;;            still to come
;;     raw    nothing, on both: a net.Server's close() ends no connection
;;     h2c    on 24, every session within 3 ms: nothing sent, a partial
;;            preface, the preface done; on 20, nothing; on both, never a
;;            stream open with its request body still to come
;;   tests/test-origin-tls.sps holds the TLS faces to the same.
;; - An idle timer of the face's own: it ends a connection some L ms after
;;   its last activity. So every probe must still hold its state, (connected
;;   ...) and exactly that state's bytes and no end, when it is read once
;;   more just before PROC returns. And the call must return within B, 500
;;   ms, of PROC's return, by this process's monotonic clock: the origin
;;   exits only once every face's close() has seen each of its connections
;;   end, so every connection ended within B of the stop. Two sets of
;;   probes, the second opened 700 ms, more than B, after the first holds its
;;   states, then leave no L that ends both sets inside that window: one set
;;   would end before the stop, or the other more than B after it.
;;
;; - One schedule that ends every connection at once: a reap at a phase
;;   fixed from the origin's start, or a shed once enough are open. The two
;;   sets do not rule it out, so the check runs twice, each time on a fresh
;;   origin, the second holding both sets 700 ms, more than B, longer before
;;   the stop: a schedule fixed to the origin's start, or to the sets'
;;   opening, cannot fall inside both windows.
;;
;; B is three times the slowest measured, 150 ms under 24 busy loops; idle it
;; was 35 to 43 ms, and 49 to 76 ms with Chez under Valgrind. The stop ends a
;; connection with a FIN, or with a reset when the client's bytes are still
;; unread, as a starved origin can leave them: both are the stop's.
;;
;; The states held are those the table below names. Some a client can leave
;; a face in are not held by any check: an HTTP/2 response its client's
;; flow-control window holds back, a TLS handshake whose whole ClientHello
;; came but not the client's Finished, and a response the client does not
;; read.

;; The plaintext faces' waiting states: a name, the face, the probe's
;; options, none, and the bytes it sends and gets before the stop, both as
;; hex. h2c sends its SETTINGS, empty, at once, and its ACK of the client's
;; once they come.
(define h2-preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
(define empty-settings (string #\nul #\nul #\nul #\x4 #\nul #\nul #\nul #\nul #\nul))
(define plaintext-waiting-states
  (list (list "connected, nothing sent" 'http '() "" "")
        (list "a partial request head" 'http '() (hex "GET /status/200 HTTP/1.1\r\nHost: 127.0.0.1\r\n") "")
        (list "idle after a whole keep-alive response" 'http '() (hex (get "/status/200"))
              (hex "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: keep-alive\r\n\r\nstatus 200\n"))
        (list "a request head sent, its body still to come" 'http '()
              (hex "POST /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 10\r\n\r\nhello") "")
        (list "connected, nothing sent" 'raw '() "" "")
        (list "a partial request head" 'raw '() (hex "GET /raw/content-length HTTP/1.1\r\n") "")
        (list "a stalled script, before its head" 'raw '() (hex (get "/raw/stall-before-head")) "")
        (list "a stalled script, after its head" 'raw '() (hex (get "/raw/stall-after-head"))
              (hex "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n"))
        ;; pause-mid-body waits 60 s between its writes: longer than any stop,
        ;; on a slow machine too (2.9 to 5 s on one or two CPUs with Valgrind).
        (list "a script playing, between two of its writes" 'raw '() (hex (get "/raw/pause-mid-body?ms=60000"))
              (hex "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello"))
        (list "a script playing, between two of its writes, the client half-closed" 'raw '("--half-close")
              (hex (get "/raw/pause-mid-body?ms=60000"))
              (hex "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello"))
        (list "connected, nothing sent" 'h2c '() "" "000000040000000000")
        (list "a partial connection preface" 'h2c '() (hex "PRI * HTTP/2.0\r\n") "000000040000000000")
        (list "the connection preface done, nothing more" 'h2c '()
              (hex (string-append h2-preface empty-settings))
              "000000040000000000000000040100000000")
        ;; HEADERS for POST /echo, END_HEADERS alone: :method POST, :scheme
        ;; http, then :path and :authority as literals.
        (list "a stream open, its request body still to come" 'h2c '()
              (hex (string-append h2-preface empty-settings
                                  (string #\nul #\nul #\x14 #\x1 #\x4 #\nul #\nul #\nul #\x1 #\x83 #\x86 #\x4 #\x5)
                                  "/echo" (string #\x1 #\x9) "localhost"))
              "000000040000000000000000040100000000")))

;; A Probe here is a vector: #(STATE TO FROM ERR PID TEXT PIPE-ENDED)
(define (probe-state p) (vector-ref p 0))
(define (probe-from p) (vector-ref p 2))
(define (probe-pid p) (vector-ref p 4))
(define (probe-text p) (vector-ref p 5))

;; spawn : Origin State -> Probe
(define (spawn o state)
  (let-values (((to from err pid)
                (open-process-ports
                 (apply string-append
                        "exec " (shell-word node) " tests/wire-probe.mjs"
                        (append (map (lambda (w) (string-append " " (shell-word w))) (caddr state))
                                (list " 127.0.0.1 " (number->string (cdr (origin-face o (cadr state))))
                                      " " (shell-word (cadddr state)) " 20000")))
                 (buffer-mode block) #f)))
    (vector state to from err pid "" #f)))

;; drain! : Probe -> Unit
;; Appends to the probe's text all its pipe holds now, never waiting.
(define (drain! p)
  (let loop ()
    (when (and (not (vector-ref p 6)) (input-port-ready? (probe-from p)))
      (let ((bytes (get-bytevector-some (probe-from p))))
        (if (eof-object? bytes)
            (vector-set! p 6 #t)
            (begin (vector-set! p 5 (string-append (probe-text p) (latin-1 bytes))) (loop)))))))

;; lines-of : String -> (U (Listof Any) #f)
;; TEXT's whole lines read as data; #f when its last line is not whole.
(define (lines-of text)
  (and (or (zero? (string-length text)) (char=? (string-ref text (- (string-length text) 1)) #\newline))
       (guard (e (#t #f))
         (let ((port (open-string-input-port text)))
           (let loop ((found '()))
             (let ((d (read port))) (if (eof-object? d) (reverse found) (loop (cons d found)))))))))

;; held : Probe -> (U 'waiting 'settling List)
;; Whether the probe holds its state: (connected MS), then data lines that
;; hold exactly its BEFORE bytes, and no end. settling when its lines so far
;; are a start of that; anything else, as evidence.
(define (held p)
  (let* ((text (probe-text p))
         (want (list-ref (probe-state p) 4))
         (data (lines-of text)))
    (cond ((not data) 'settling)
          ((null? data) 'settling)
          ((not (and (pair? (car data)) (eq? (caar data) 'connected))) (list 'not-connected text))
          ((not (for-all (lambda (d) (and (list? d) (= (length d) 4) (eq? (car d) 'data))) (cdr data)))
           (list 'ended text))
          (else
           (let ((got (apply string-append (map cadddr (cdr data)))))
             (cond ((string=? got want) 'waiting)
                   ((and (< (string-length got) (string-length want))
                         (string=? got (substring want 0 (string-length got))))
                    'settling)
                   (else (list 'received text))))))))

;; open-set : Origin (Listof State) -> (Listof Probe)
;; One probe per state, from open-process-ports, so that it holds no pipe
;; of the origin's, each read until it holds its state, within 10000 ms.
(define (open-set o states)
  (let ((probes '()))
    (for-each (lambda (state) (set! probes (append probes (list (spawn o state))))) states)
    (let ((deadline (+ (now-ms) 10000)))
      (let loop ()
        (for-each drain! probes)
        (when (and (< (now-ms) deadline)
                   (exists (lambda (p) (eq? (held p) 'settling)) probes))
          (pause-ms 5)
          (loop))))
    probes))

;; kill-probes : (Listof Probe) -> Unit
(define (kill-probes probes)
  (for-each (lambda (p)
              (capture-command (list "kill" "-9" (number->string (probe-pid p))))
              (for-each (lambda (port) (guard (e (#t #f)) (close-port port)))
                        (list (vector-ref p 1) (vector-ref p 2) (vector-ref p 3))))
            probes))

;; stop-check : (Listof State) ((Origin -> Any) -> Any) Natural Natural -> (List Natural (Listof List))
;; Set A, then, GAP ms after set A holds its states, set B, against the
;; origin CALL starts; HOLD ms after set B holds its states, each probe read
;; once more, and PROC returns. The answer: the ms from PROC's return to the
;; call's, and, for each probe, set A's then set B's, its state's name and
;; face, whether it held its state then, and how its connection ended.
(define (stop-check states call gap hold)
  (let ((all '()) (stopped-at #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let* ((before
                (call
                 (lambda (o)
                   (let* ((a (open-set o states))
                          (a-held (now-ms)))
                     (set! all a)
                     (pause-ms (max 0 (- (+ a-held gap) (now-ms))))
                     (let ((b (open-set o states)))
                       (set! all (append a b))
                       (pause-ms hold)
                       (for-each drain! all)
                       (let ((verdicts (map held all)))
                         (set! stopped-at (now-ms))
                         verdicts))))))
               (took (- (now-ms) stopped-at))
               (deadline (+ (now-ms) 2000)))
          (let loop ()
            (for-each drain! all)
            (when (and (< (now-ms) deadline) (exists (lambda (p) (not (vector-ref p 6))) all))
              (pause-ms 5)
              (loop)))
          (list took
                (map (lambda (p held-then)
                       (list (car (probe-state p)) (cadr (probe-state p)) held-then
                             (guard (e (#t (list 'unparsed (describe e))))
                               (probe-end (parse-wire-probe (probe-text p))))))
                     all before))))
      (lambda () (kill-probes all)))))

;; stop-verdict : (List Natural (Listof List)) -> List
(define (stop-verdict result)
  (list (if (<= (car result) 500) 'within-500-ms (list 'took (car result)))
        (map (lambda (row)
               (list (car row) (cadr row) (caddr row)
                     (if (memq (cadddr row) '(eof reset)) 'ended-by-the-stop (cadddr row))))
             (cadr result))))

(for-each
 (lambda (hold name)
   (test-equal (string-append "stopping ends every connection to a plaintext face, in each waiting state its table names: " name
                              ", each still holding its state as PROC returns, the call returning within 500 ms of PROC, and each probe's end the stop's")
     (list 'returned
           (list 'within-500-ms
                 (map (lambda (state) (list (car state) (cadr state) 'waiting 'ended-by-the-stop))
                      (append plaintext-waiting-states plaintext-waiting-states))))
     (outcome (lambda () (stop-verdict (stop-check plaintext-waiting-states call-with-origin 700 hold))))))
 '(0 700)
 '("two sets of probes, the second opened 700 ms after the first holds its states, the stop at once"
   "the same on a fresh origin, both sets held 700 ms longer before the stop"))

;; --- the probe: a reset that arrives with the last bytes ----------------------

;; signal-probe : Probe String -> Integer
;; kill's exit status, sending the probe SIGNAL, as -STOP or -CONT.
(define (signal-probe p signal)
  (car (capture-command (list "kill" signal (number->string (probe-pid p))))))

;; stopped-across : Origin -> List
;; What the probe saw of raw's reset-after-pause?ms=1000 when it is stopped
;; (SIGSTOP) from the moment it holds the script's first write until 3000 ms
;; later, then continued: the bytes, its end, and whether the last bytes were
;; read at least 2000 ms after the first, so only after the stop. The script's
;; last write and its reset both come during the stop, so the probe wakes to
;; find them waiting at once. libuv before 1.52 then reports an end and never
;; reads the reset; on Node 20.10.0 it did in 50 runs of 50 (measured).
(define (stopped-across o)
  (let ((probes '())
        (first-write "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello"))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (set! probes (open-set o (list (list "reset after a pause" 'raw '()
                                             (hex (get "/raw/reset-after-pause?ms=1000"))
                                             (hex first-write)))))
        (let ((p (car probes)))
          (if (not (eq? (held p) 'waiting))
              (list 'not-held (probe-text p))
              (let* ((stopped (signal-probe p "-STOP"))
                     (continued (begin (pause-ms 3000) (signal-probe p "-CONT")))
                     (deadline (+ (now-ms) 10000)))
                (let loop ()
                  (drain! p)
                  (when (and (not (vector-ref p 6)) (< (now-ms) deadline))
                    (pause-ms 5)
                    (loop)))
                (if (not (and (eqv? stopped 0) (eqv? continued 0)))
                    (list 'kill stopped continued)
                    (let* ((answer (parse-wire-probe (probe-text p)))
                           (n (string-length first-write))
                           (first (arrival (probe-arrivals answer) (- n 1)))
                           (last (arrival (probe-arrivals answer) n)))
                      (list (latin-1 (probe-bytes answer)) (probe-end answer)
                            (if (and first last (>= (- last first) 2000))
                                'read-after-the-stop
                                (list 'first first 'last last)))))))))
      (lambda () (kill-probes probes)))))

(test-equal "the probe, stopped across raw /raw/reset-after-pause?ms=1000's last write and reset, then continued: the whole bytes, then reset, the last bytes read only after the stop"
  (list 'returned (list "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello wor" 'reset 'read-after-the-stop))
  (outcome (lambda () (call-with-origin stopped-across))))

(test-equal "exits on stdin's end: once call-with-origin returns, every face refuses connections"
  (list 'returned refused)
  (outcome
   (lambda ()
     (let ((o (call-with-origin (lambda (o) o))))
       (list (exchange o 'http (get "/status/200" close) 2000)
             (exchange o 'raw (get "/raw/content-length") 2000)
             (exchange o 'h2c "" 2000))))))

(test-equal "with stdin at its end from the start, it announces its five keys, then exits 0, writing nothing to stderr"
  '(0 ("node" "pid" "http" "raw" "h2c") "")
  (guard (e (#t (list 'raised (describe e))))
    (let* ((answer (bounded node "tests/origin.mjs"))
           (out (cadr answer))
           (n (string-length out)))
      (list (car answer)
            (if (and (> n 0) (char=? (string-ref out (- n 1)) #\newline))
                (map car (read-announcement (substring out 0 (- n 1))))
                (list 'no-line out))
            (caddr answer)))))

;; --- the probe's own refusals ---------------------------------------------------

(define probe-usage
  "usage: node tests/wire-probe.mjs [--reset | --half-close] [--tls SERVERNAME [--alpn LIST]] [--split OFFSET:MS] [--deadline MS] HOST PORT HEX IDLE-MS\n")

(test-equal "the probe refuses a usage error with exit 2, its problem and its usage on stderr"
  (list (list 2 "" (string-append "wire-probe: it takes 4 arguments after its options, and was given 3\n"
                                  probe-usage))
        (list 2 "" (string-append "wire-probe: it takes 4 arguments after its options, and was given 5\n"
                                  probe-usage))
        (list 2 "" (string-append "wire-probe: --reset and --half-close cannot both be given\n" probe-usage))
        (list 2 "" (string-append "wire-probe: --deadline takes a positive natural, its milliseconds\n"
                                  probe-usage))
        (list 2 "" (string-append "wire-probe: --deadline takes a positive natural, its milliseconds\n"
                                  probe-usage))
        (list 2 "" (string-append "wire-probe: HEX is not pairs of lower-case hex digits\n" probe-usage))
        (list 2 "" (string-append "wire-probe: HEX names \"/no/such/file.hex\", which cannot be read: ENOENT\n"
                                  probe-usage))
        (list 2 "" (string-append "wire-probe: HEX is not pairs of lower-case hex digits\n" probe-usage)))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((upper (string-append dir "/upper.hex")))
         (call-with-port (open-file-output-port upper (file-options no-fail) (buffer-mode block)
                                                (native-transcoder))
           (lambda (p) (put-string p "4A")))
         (map (lambda (args) (bounded* (cons node (cons "tests/wire-probe.mjs" args))))
              (list '("127.0.0.1" "1" "")
                    '("--reset" "127.0.0.1" "1" "" "100" "extra")
                    '("--reset" "--half-close" "127.0.0.1" "1" "" "100")
                    '("--deadline" "0" "127.0.0.1" "1" "" "100")
                    '("--deadline")
                    '("127.0.0.1" "1" "4A" "100")
                    '("127.0.0.1" "1" "@/no/such/file.hex" "100")
                    (list "127.0.0.1" "1" (string-append "@" upper) "100"))))))))

(test-equal "the probe refuses each misuse of --split with exit 2, its problem and its usage on stderr"
  (map (lambda (problem) (list 2 "" (string-append "wire-probe: " problem "\n" probe-usage)))
       '("--split takes OFFSET:MS, two positive naturals"
         "--split takes OFFSET:MS, two positive naturals"
         "--split takes OFFSET:MS, two positive naturals"
         "--split takes OFFSET:MS, two positive naturals"
         "--split takes OFFSET:MS, two positive naturals"
         "--split takes OFFSET:MS, two positive naturals"
         "--split's OFFSET, 2, is not fewer than HEX's 2 bytes"
         "--split's OFFSET, 3, is not fewer than HEX's 2 bytes"
         "--split's OFFSET, 1, is not fewer than HEX's 0 bytes"))
  (map (lambda (args) (bounded* (cons node (cons "tests/wire-probe.mjs" args))))
       '(("--split")
         ("--split" "0:10" "127.0.0.1" "1" "6162" "100")
         ("--split" "1:0" "127.0.0.1" "1" "6162" "100")
         ("--split" "1" "127.0.0.1" "1" "6162" "100")
         ("--split" "01:10" "127.0.0.1" "1" "6162" "100")
         ("--split" "1:10:5" "127.0.0.1" "1" "6162" "100")
         ("--split" "2:10" "127.0.0.1" "1" "6162" "100")
         ("--split" "3:10" "127.0.0.1" "1" "6162" "100")
         ("--split" "1:10" "127.0.0.1" "1" "" "100"))))

;; The probe's --split, by the http face's /echo, which answers once the
;; whole request has come: a head split in two arrives whole, in order, and
;; its answer only once the rest is sent, MS ms on.
(test-equal "the probe's --split OFFSET:MS: /echo, its head split after 10 bytes for 300 ms, answers the whole head, then eof, 300 ms or more after connecting"
  '(returned (("HTTP/1.1 200 OK\r\nContent-Length: 65\r\nConnection: close\r\n\r\nGET /echo HTTP/1.1\nHost: 127.0.0.1\nX-Split: 1\nConnection: close\n\n" eof)
              late-enough))
  (outcome
   (lambda ()
     (call-with-origin
      (lambda (o)
        (let ((p (split-probe o 'http (get "/echo" "X-Split: 1\r\n" close) 10 300 2000)))
          (list (list (latin-1 (probe-bytes p)) (probe-end p))
                (let ((first (arrival (probe-arrivals p) 0)))
                  (if (and first (>= (- first (probe-connected p)) 300)) 'late-enough
                      (list 'connected (probe-connected p) 'first first))))))))))

(define origin-usage "usage: node tests/origin.mjs [--pki DIR | --selftest [PLANT]]\n")

(test-equal "it takes no argument, --pki DIR, or --selftest [PLANT]: any other exits 2, naming them on stderr, and nothing on stdout; a plant it does not know too"
  (list (list 2 "" (string-append "origin: it takes no argument, --pki DIR, or --selftest [PLANT], and was given [\"--nope\"]\n"
                                  origin-usage))
        (list 2 "" (string-append "origin: it takes no argument, --pki DIR, or --selftest [PLANT], and was given [\"--pki\"]\n"
                                  origin-usage))
        (list 2 "" (string-append "origin: it takes no argument, --pki DIR, or --selftest [PLANT], and was given [\"--pki\",\"a\",\"b\"]\n"
                                  origin-usage))
        (list 2 "" (string-append "origin: it takes no argument, --pki DIR, or --selftest [PLANT], and was given [\"--PKI\",\"a\"]\n"
                                  origin-usage))
        (list 2 "" (string-append "origin: --pki takes DIR, a directory, and was given an empty one\n" origin-usage))
        (list 2 "" (string-append "origin: --selftest plants nc-before-nonce or sess-ignored, and was given \"bogus\"\n"
                                  origin-usage))
        (list 2 "" (string-append "origin: it takes no argument, --pki DIR, or --selftest [PLANT], and was given [\"--selftest\",\"a\",\"b\"]\n"
                                  origin-usage)))
  (map (lambda (args) (bounded* (append (list node "tests/origin.mjs") args)))
       '(("--nope") ("--pki") ("--pki" "a" "b") ("--PKI" "a") ("--pki" "") ("--selftest" "bogus")
         ("--selftest" "a" "b"))))

;; The auth route's Digest arithmetic is held to RFC 2617's and RFC 7616's
;; published examples by the origin's own self-test, and that self-test is
;; seen to fail: each plant breaks the arithmetic, and the checks it breaks
;; are named. nc-before-nonce breaks the three qop vectors; sess-ignored the
;; -sess control alone, which no vector covers.
;; swapped : Symbol String String String String String String String String String -> String
;; nc-before-nonce's response, computed here: H(HA1:nc:nonce:cnonce:qop:HA2).
(define (swapped hash user realm pass nonce cnonce nc qop method uri)
  (let ((h (if (eq? hash 'md5) md5-hex sha256-hex))
        (b (lambda parts (octets (apply string-append parts)))))
    (h (b (h (b user ":" realm ":" pass)) ":" nc ":" nonce ":" cnonce ":" qop ":" (h (b method ":" uri))))))

(test-equal "the origin's --selftest passes its 13 checks, the Digest vectors and four controls among them, exit 0; with each plant it fails the checks that plant breaks, naming each and the answer the plant gives, computed here, exit 1"
  (list (list 0 "selftest ok 13\n" "")
        (list 1 (string-append
                 "selftest FAIL rfc2617 md5 auth: got "
                 (swapped 'md5 "Mufasa" "testrealm@host.com" "Circle Of Life" "dcd98b7102dd2f0e8b11d0f600bfb0c093"
                          "0a4f113b" "00000001" "auth" "GET" "/dir/index.html")
                 ", want 6629fae49393a05397450978507c4ef1\n"
                 "selftest FAIL rfc7616 md5 auth: got "
                 (swapped 'md5 "Mufasa" "http-auth@example.org" "Circle of Life" "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v"
                          "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ" "00000001" "auth" "GET" "/dir/index.html")
                 ", want 8ca523f5e9506fed4657c9700eebdbec\n"
                 "selftest FAIL rfc7616 sha-256 auth: got "
                 (swapped 'sha-256 "Mufasa" "http-auth@example.org" "Circle of Life" "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v"
                          "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ" "00000001" "auth" "GET" "/dir/index.html")
                 ", want 753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1\n")
              "")
        (list 1 "selftest FAIL -sess made no difference\n" ""))
  (map (lambda (args) (bounded* (append (list node "tests/origin.mjs") args)))
       '(("--selftest") ("--selftest" "nc-before-nonce") ("--selftest" "sess-ignored"))))

;; --- lifecycle: how long the origin outlives a suite killed with SIGKILL -----
;; Its stdin ends once every process holding the pipe's write end has gone:
;; the suite, and any probe or command the suite was running when it died,
;; children of system, which inherit Chez's pipe ends. So the origin outlives
;; a dead suite by at most the longest of those, each ended by its own bound:
;; wire-probe-deadline for a probe, bounded's 10 s for a command.

;; sigkill-check : (Listof String) Natural -> (List (Listof End) Symbol)
;; Runs tests/origin-child.sps with ARGS, and kills it with SIGKILL once it
;; has printed its line and each face has answered a probe. The answer: how
;; those probes ended, and whether every face refused within BOUND ms of the
;; kill, by the monotonic clock, read before each round of probes.
(define (sigkill-check args bound)
  (call-with-temp-directory
   (lambda (dir)
     (let-values (((to from err pid)
                   (open-process-ports
                    (apply string-append "exec env TMPDIR=" (shell-word dir) " " (shell-word chez)
                           " --libdirs src:tests:build/scheme-libs --program tests/origin-child.sps"
                           (map (lambda (arg) (string-append " " (shell-word arg))) args))
                    (buffer-mode block) #f)))
       (let ((line #f) (killed #f))
         (dynamic-wind
           (lambda () #f)
           (lambda ()
             (set! line (read-line-within from 10000))
             (unless line (error 'sigkill "the child Chez printed no line"))
             (let* ((datum (read (open-string-input-port line)))
                    (ports (cdr datum))
                    (before (map (lambda (port) (probe-at "127.0.0.1" port 200)) ports)))
               (capture-command (list "kill" "-9" (number->string pid)))
               (set! killed #t)
               (let* ((killed-at (now-ms)) (deadline (+ killed-at bound)))
                 (list before
                       (let loop ()
                         (cond ((> (now-ms) deadline) 'still-served-after-the-bound)
                               ((for-all (lambda (port) (equal? (probe-at "127.0.0.1" port 100)
                                                                '(refused "ECONNREFUSED")))
                                         ports)
                                (if (<= (- (now-ms) killed-at) bound)
                                    'refused-within-the-bound
                                    (list 'refused-after (- (now-ms) killed-at))))
                               (else (pause-ms 50) (loop))))))))
           (lambda ()
             (unless killed (capture-command (list "kill" "-9" (number->string pid))))
             ;; An origin that outlived the check must not outlive the suite.
             (guard (e (#t #f))
               (when line
                 (capture-command (list "kill" "-9" (number->string (car (read (open-string-input-port line))))))))
             (close-port to) (close-port from) (close-port err))))))))

(test-equal "a suite killed with SIGKILL while idle: within 5 s every face of its origin refuses connections"
  '(returned ((timeout timeout timeout) refused-within-the-bound))
  (outcome (lambda () (sigkill-check '() 5000))))

(test-equal "a suite killed with SIGKILL during a probe: its origin lives until the probe's wire-probe-deadline, 2000 ms, ends the probe; within 2000 ms of it plus 2000 ms of slack every face refuses connections"
  '(returned ((timeout timeout timeout) refused-within-the-bound))
  (outcome (lambda () (sigkill-check '("probe") 4000))))

(test-end "origin")

(exit (suite-exit-status runner))
