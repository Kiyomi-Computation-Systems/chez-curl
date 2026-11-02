#!r6rs
;; Review probe: the hatch's ALTSVC_CTRL alone, no ALTSVC file, beside a
;; caller's Expect: 100-continue, against a face that answers 417 with
;; Alt-Svc. Prints, for each case, which face answered the transfer.
(import (rnrs)
        (only (chezscheme) open-process-ports getenv)
        (curl) (curl unsupported) (curl-testing))

(define pki (make-test-pki))
(define ca (string-append pki "/ca.pem"))

(define ports
  (call-with-values
    (lambda () (open-process-ports (string-append (or (getenv "NODE") "node")
                                                  " .plans/research/m7/slice1/review/altsvc417.mjs " pki)
                                   'line (native-transcoder)))
    list))
(define to-node (car ports))
(define from-node (cadr ports))
(define line (get-line from-node))
(display (string-append "ports " line "\n"))

;; port-of : String -> String
(define (port-of key)
  (let* ((k (string-append "\"" key "\":"))
         (n (string-length line)) (m (string-length k)))
    (let loop ((i 0))
      (if (string=? (substring line i (+ i m)) k)
          (let digits ((j (+ i m)))
            (if (and (< j n) (char-numeric? (string-ref line j)))
                (digits (+ j 1))
                (substring line (+ i m) j)))
          (loop (+ i 1))))))

(define a-port (port-of "a"))

(define (run tag path version ctrl)
  (let* ((engine (make-curl-engine))
         (r0 (make-curl-request (string-append "https://127.0.0.1:" a-port path)
                                'method 'post 'body (string->utf8 "hello")
                                'headers '(("Expect" . "100-continue"))
                                'ca-file ca 'proxy #f 'timeout-ms 10000
                                'http-version version))
         (r (if ctrl (curl-request-with-options r0 (list (cons "ALTSVC_CTRL" ctrl))) r0))
         (answer (guard (e (#t (list 'raised (describe e))))
                   (let ((resp (curl-token-await (curl-submit engine r))))
                     (list (curl-response-status resp) (curl-response-http-version resp)
                           (let ((s (utf8->string (curl-response-body resp)))) (if (> (string-length s) 60) (substring s 0 60) s)))))))
    (curl-engine-stop engine)
    (write (list tag path version ctrl answer))
    (newline)))

(for-each (lambda (args) (apply run args))
          '((control "/to-c" #f #f)
            (ctrl "/to-c" #f 24)
            (control "/to-c" http/1.1 #f)
            (ctrl "/to-c" http/1.1 24)
            (control "/to-d" #f #f)
            (ctrl "/to-d" #f 24)
            (ctrl "/to-d" http/1.1 24)))

(close-port to-node)
(exit 0)
