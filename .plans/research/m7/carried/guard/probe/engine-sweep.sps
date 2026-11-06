;;; engine-sweep.sps ENTRY LO HI STEP: for each fuel F from LO to HI by
;;; STEP, one call of ENTRY (request port go parallel) inside a Chez engine
;;; of F ticks against the origin's http face, a fast 200; when it expires,
;;; the seam's marks so far are read, and the engine resumed with 10^8
;;; ticks. Prints (engine ENTRY F TRAIL OUTCOME): TRAIL the marks at the
;;; expiry, in order (enter, parse, parse-end, ..., exit), or completed when
;;; the fuel outlasted the call; OUTCOME what the resumed call answered,
;;; (returned V) or (raised DESCRIPTION). Run from a copy's root.
(import (chezscheme) (curl) (http-client) (curl-testing)
        (curl private counters)
        (curl private gate))

(define args (command-line-arguments))
(define entry (string->symbol (list-ref args 0)))
(define lo (string->number (list-ref args 1)))
(define hi (string->number (list-ref args 2)))
(define step (string->number (list-ref args 3)))

(define (described e)
  (cond ((condition? e)
         (list (if (http-exchange? e) 'compounded 'not-compounded)
               (cond ((assertion-violation? e) 'assertion)
                     ((http-group-error? e) (list 'group (http-group-error-reason e)))
                     ((curl-transfer-error? e) 'transfer-error)
                     ((curl-error? e) 'curl-error)
                     ((error? e) 'error)
                     (else 'other))
               (if (who-condition? e) (condition-who e) 'no-who)
               (if (message-condition? e) (condition-message e) 'no-message)))
        (else (list 'non-condition e))))

(define (run-entry session url)
  (guard (e (#t (list 'raised (described e))))
    (case entry
      ((request) (list 'returned (http-response-status (http-get session url))))
      ((port)
       (list 'returned
             (call-with-response-port session 'get url
               (lambda (r p)
                 (let loop ()
                   (unless (eof-object? (get-bytevector-some p)) (loop)))
                 (http-response-status r)))))
      ((go)
       (list 'returned
             (call-with-request-group session
               (lambda (go) (http-response-status (http-await (go 'get url)))))))
      ((parallel)
       (list 'returned (map http-response-status (http-parallel session (list (list 'get url))))))
      (else (error 'engine-sweep "no entry" entry)))))

(call-with-origin
 (lambda (o)
   (let* ((f (origin-face o 'http))
          (url (string-append "http://" (car f) ":" (number->string (cdr f)) "/status/200"))
          (session (make-http-session 'timeout-ms 20000)))
     (let loop ((fuel lo))
       (when (<= fuel hi)
         (let* ((trail '())
                (armed (gate-set! (lambda (w) (set! trail (cons w trail)))))
                (eng (make-engine (lambda () (run-entry session url))))
                (row (eng fuel
                          (lambda (ticks value) (list 'completed value))
                          (lambda (next)
                            (let ((at (reverse trail)))
                              (list at
                                    (next 100000000
                                          (lambda (ticks value) value)
                                          (lambda (next) '(expired-again)))))))))
           (gate-set! #f)
           (write (list 'engine entry fuel (car row) (cadr row)))
           (newline)
           (loop (+ fuel step)))))
     (http-session-close session)
     (write (list 'counts (native-counts)))
     (newline))))
