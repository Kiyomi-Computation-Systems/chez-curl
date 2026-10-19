#!r6rs
;;; The suite for the test instrument (M1 plan, sections 3 to 7; ADR-0005,
;;; amended): the origin, tests/origin.mjs, as the byte probe,
;;; tests/wire-probe.mjs, sees it. No check here uses libcurl or the curl
;;; command line.
;;;
;;; Every expected output is written here, by hand, never read from
;;; origin.mjs: a script's bytes changed there fail a test here. Each
;;; scenario's test asserts the whole bytes received and how the connection
;;; ended. The well-formed face's bytes are those Node 20.10.0 and 24.18.0
;;; were measured to write (.plans/instrument-mutation-log.md): they agree.
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
         (list "a path outside /raw/" (get "/content-length"))
         (list "a request line of two words" "GET /raw/content-length\r\n\r\n")
         (list "a request line of four words" "GET /raw/content-length HTTP/1.1 x\r\n\r\n")
         (list "garbage" (string-append (string #\nul #\x1 #\xff) " garbage\r\n\r\n"))))

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
               '("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" eof)))))

;; The scenarios' tests run here, in a definition, and the verdict on their
;; origin after. SRFI-64 keeps one result per runner: tests run inside another
;; test's actual expression overwrite its name and expected value, so a raise
;; from the origin's cleanup would be reported under the last scenario's name.
(define scenarios-outcome
  (outcome (lambda () (call-with-origin (lambda (o) (scenarios o) 'done)))))

(test-equal "the scenarios' origin starts, serves them all, and stops"
  '(returned done)
  scenarios-outcome)

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
;;   Node 24.18.0 and 20.10.0, build/verify/m1s2/measure5/close-untracked-*):
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
;; was 35 to 43 ms, and 49 to 76 ms with Chez under Valgrind
;; (build/verify/m1s2/measure5/stop-spread-*). The stop ends a connection
;; with a FIN, or with a reset when the client's bytes are still unread, as
;; a starved origin can leave them: both are the stop's.
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
        ;; on a slow machine too (2.9 to 5 s on one or two CPUs with Valgrind,
        ;; measured by the review).
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
  "usage: node tests/wire-probe.mjs [--reset | --half-close] [--tls SERVERNAME [--alpn LIST]] [--deadline MS] HOST PORT HEX IDLE-MS\n")

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

(define origin-usage "usage: node tests/origin.mjs [--pki DIR]\n")

(test-equal "it takes no argument, or --pki DIR: any other exits 2, naming them on stderr, and nothing on stdout"
  (list (list 2 "" (string-append "origin: it takes no argument, or --pki DIR, and was given [\"--nope\"]\n"
                                  origin-usage))
        (list 2 "" (string-append "origin: it takes no argument, or --pki DIR, and was given [\"--pki\"]\n"
                                  origin-usage))
        (list 2 "" (string-append "origin: it takes no argument, or --pki DIR, and was given [\"--pki\",\"a\",\"b\"]\n"
                                  origin-usage))
        (list 2 "" (string-append "origin: it takes no argument, or --pki DIR, and was given [\"--PKI\",\"a\"]\n"
                                  origin-usage))
        (list 2 "" (string-append "origin: --pki takes DIR, a directory, and was given an empty one\n" origin-usage)))
  (map (lambda (args) (bounded* (append (list node "tests/origin.mjs") args)))
       '(("--nope") ("--pki") ("--pki" "a" "b") ("--PKI" "a") ("--pki" ""))))

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
                           " --libdirs tests:build/scheme-libs --program tests/origin-child.sps"
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
