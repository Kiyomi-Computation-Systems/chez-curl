#!r6rs
;;; M5 slice 2's Location probe, chez-curl's half (2026-10-28; the M5 plan,
;;; section 5.1).
;;;
;;;   scheme --libdirs src --program probe.sps CASES
;;;
;;; CASES holds one line per transfer, LABEL METHOD URL, the lines run.sh
;;; also hands the C probe, ../redirect-url/probe.c. Each URL is fetched
;;; through an engine, as the high level fetches one, and the first header
;;; the response holds whose name is Location, A to Z folded, is resolved
;;; against the URL from its Latin-1 string's bytes: curl_url_set of the
;;; whole URL on the URL's handle, flags 0, as the C probe's r0 does it,
;;; and as curl-url-resolve's bytevector reference will. Prints, per line:
;;;
;;;   LABEL METHOD rc=0 status=S location=V amount=N r0=R utf8=yes|no
;;;
;;; V and R as the C probe's show() prints them; location=none when the
;;; response holds no Location; r0=ucN for a refusal; utf8 whether R's
;;; bytes read as strict UTF-8, which chez-curl requires of every answer.
;;; A failed transfer prints rc=CODE alone, from &curl-transfer-error.
(import (rnrs)
        (curl)
        (curl private url)
        (curl private native)
        (curl private constants))

(define (hex2 n)
  (let ((s (number->string n 16)))
    (string-downcase (if (< n 16) (string-append "0" s) s))))

;; show : String (U Bytevector #f) -> String
;; The C probe's show(): " TAG=" then each byte, \xHH outside 0x21 to 0x7e
;; and for a backslash; past 120 bytes, the first 40 and the length.
(define (show tag bytes)
  (string-append
   " " tag "="
   (if (not bytes)
       "NULL"
       (let* ((len (bytevector-length bytes))
              (cut (if (> len 120) 40 len)))
         (let loop ((i 0) (acc '()))
           (if (= i cut)
               (string-append (apply string-append (reverse acc))
                              (if (< cut len)
                                  (string-append "...(len " (number->string len) ")")
                                  ""))
               (let ((c (bytevector-u8-ref bytes i)))
                 (loop (+ i 1)
                       (cons (if (or (< c #x21) (> c #x7e) (= c 92))
                                 (string-append "\\x" (hex2 c))
                                 (string (integer->char c)))
                             acc)))))))))

(define (latin-1-bytes s)
  (let ((b (make-bytevector (string-length s))))
    (do ((i 0 (+ i 1))) ((= i (string-length s)) b)
      (bytevector-u8-set! b i (char->integer (string-ref s i))))))

(define (fold-a-z c)
  (if (char<=? #\A c #\Z) (integer->char (+ (char->integer c) 32)) c))

(define (location? name)
  (and (= (string-length name) 8)
       (let loop ((i 0))
         (or (= i 8)
             (and (char=? (fold-a-z (string-ref name i)) (string-ref "location" i))
                  (loop (+ i 1)))))))

(define strict-utf-8
  (make-transcoder (utf-8-codec) (eol-style none) (error-handling-mode raise)))

(define (utf-8? bytes)
  (guard (e ((i/o-decoding-error? e) #f))
    (bytevector->string bytes strict-utf-8)
    #t))

;; resolve : String String -> (U Bytevector String)
;; VALUE's Latin-1 bytes resolved against BASE: the answer's bytes, or
;; "ucN" for a refusal.
(define (resolve base value)
  (call-with-parsed-url base
    (lambda (handle)
      (let ((code (call-with-latin-1-c-string value
                    (lambda (address) (curl-url-set handle curlupart-url address 0)))))
        (if (eqv? code curlue-ok)
            (let-values (((c a) (curl-url-get handle curlupart-url 0)))
              (if (eqv? c curlue-ok)
                  (let ((bytes (c-string->bytevector a)))
                    (curl-free a)
                    bytes)
                  (string-append "get-uc" (number->string c))))
            (string-append "uc" (number->string code)))))))

(define (split-line line)
  (let loop ((i 0) (start 0) (acc '()))
    (cond ((= i (string-length line))
           (reverse (cons (substring line start i) acc)))
          ((and (char=? (string-ref line i) #\space) (< (length acc) 2))
           (loop (+ i 1) (+ i 1) (cons (substring line start i) acc)))
          (else (loop (+ i 1) start acc)))))

(define (probe engine label method url)
  (let ((out (current-output-port)))
    (put-string out (string-append label " " method))
    (guard (e ((curl-transfer-error? e)
               (put-string out (string-append " rc=" (number->string (curl-transfer-error-code e)))))
              (#t
               (put-string out " rc=raise:")
               (put-string out (if (message-condition? e)
                                   (let ((m (condition-message e)))
                                     (list->string (map (lambda (c) (if (char=? c #\space) #\_ c))
                                                        (string->list m))))
                                   "?"))))
      (let* ((request (make-curl-request url 'method (if (string=? method "HEAD") 'head 'get)
                                         'timeout-ms 5000 'proxy #f))
             (response (curl-token-await (curl-submit engine request)))
             (found (filter (lambda (h) (location? (car h))) (curl-response-headers response))))
        (put-string out (string-append " rc=0 status=" (number->string (curl-response-status response))))
        (if (null? found)
            (put-string out " location=none")
            (let* ((value (cdar found))
                   (answer (resolve url value)))
              (put-string out (show "location" (latin-1-bytes value)))
              (put-string out (string-append " amount=" (number->string (length found))))
              (if (string? answer)
                  (put-string out (string-append " r0=" answer))
                  (begin
                    (put-string out (show "r0" answer))
                    (put-string out (if (utf-8? answer) " utf8=yes" " utf8=no"))))))))
    (newline out)))

(define cases
  (let ((args (command-line)))
    (unless (= (length args) 2)
      (error 'probe "usage: probe.sps CASES"))
    (call-with-input-file (cadr args)
      (lambda (port)
        (let loop ((acc '()))
          (let ((line (get-line port)))
            (if (eof-object? line)
                (reverse acc)
                (loop (cons (split-line line) acc)))))))))

(let ((info (loaded-libcurl)))
  (put-string (current-output-port)
              (string-append "libcurl " (libcurl-info-version info) " at "
                             (libcurl-info-path info) "\n")))
(let ((engine (make-curl-engine)))
  (for-each (lambda (c) (probe engine (car c) (cadr c) (caddr c))) cases)
  (curl-engine-stop engine))
(put-string (current-output-port)
            (string-append "-- " (number->string (length cases)) " probes\n"))
