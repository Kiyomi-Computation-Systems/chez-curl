;;; timer-probe.sps: for every ENTRY (request port go parallel), WHERE
;;; (enter parse) and ACTION (raise-cond cont-cond raise-false cont-sym), one
;;; call whose seam, at WHERE's first hit, sets the timer to 1 tick; the
;;; timer's handler then does ACTION, as sigint-child.sps's Ctrl-C handler
;;; does. Prints (timer ENTRY WHERE ACTION OUTCOME TRAIL RETURNED HOLDS):
;;; TRAIL the seam's marks before the handler ran, or never; HOLDS the
;;; engine's live and queued counts and the transfer count 300 ms after.
;;; Run from a copy's root.
(import (chezscheme) (curl) (http-client) (curl-testing)
        (only (http-client private call) http-session-engine)
        (only (curl private engine) curl-engine-live-count curl-engine-queued-count)
        (only (curl private conditions) make-curl-engine-error)
        (curl private counters)
        (curl private gate))

(define planted (condition (make-curl-engine-error 'stopped #f)
                           (make-message-condition "planted by the timer's handler")))
(define planted-warning (condition (make-warning) (make-message-condition "planted warning")))

(define (described e)
  (cond ((eq? e planted) '(the-planted-condition))
        ((eq? e planted-warning) '(the-planted-warning))
        ((condition? e)
         (list (if (http-exchange? e) 'compounded 'not-compounded)
               (if (and (message-condition? e)
                        (member (condition-message e)
                                '("planted by the timer's handler" "planted warning")))
                   'carries-the-plant 'no-plant)
               (cond ((non-continuable-violation? e) 'non-continuable)
                     ((assertion-violation? e) 'assertion)
                     ((warning? e) 'warning)
                     ((curl-error? e) 'curl-error)
                     ((error? e) 'error)
                     ((violation? e) 'violation)
                     (else 'other))
               (if (who-condition? e) (condition-who e) 'no-who)
               (if (message-condition? e) (condition-message e) 'no-message)))
        (else (list 'non-condition e))))

(define (run-entry session entry url)
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
    (else (error 'timer-probe "no entry" entry))))

(define (one session entry where action url)
  (let ((trail '()) (handler-trail 'never) (armed #t) (returned 0)
        (previous (timer-interrupt-handler)))
    (gate-set! (lambda (w)
                 (set! trail (cons w trail))
                 (when (and armed (eq? w where))
                   (set! armed #f)
                   (set-timer 1))))
    (let ((outcome
           (guard (e (#t (list 'raised (described e))))
             (with-exception-handler
               (lambda (c)
                 (cond ((and (eq? action 'cont-cond) (condition? c) (warning? c))
                        (set! returned (+ returned 1)) 'ignored)
                       ((and (eq? action 'cont-sym) (eq? c 'tick))
                        (set! returned (+ returned 1)) 'ignored)
                       (else (raise-continuable c))))
               (lambda ()
                 (timer-interrupt-handler
                  (lambda ()
                    (set! handler-trail (reverse trail))
                    (case action
                      ((raise-cond) (raise planted))
                      ((cont-cond) (raise-continuable planted-warning))
                      ((raise-false) (raise #f))
                      ((cont-sym) (raise-continuable 'tick)))))
                 (run-entry session entry url))))))
      (set-timer 0)
      (timer-interrupt-handler previous)
      (gate-set! #f)
      (sleep (make-time 'time-duration 300000000 0))
      (let ((engine (http-session-engine session)))
        (list 'timer entry where action outcome handler-trail returned
              (list (curl-engine-live-count engine) (curl-engine-queued-count engine)
                    (cdr (assq 'transfer (native-counts)))))))))

(call-with-origin
 (lambda (o)
   (let* ((f (origin-face o 'http))
          (url (string-append "http://" (car f) ":" (number->string (cdr f)) "/status/200"))
          (session (make-http-session 'timeout-ms 20000)))
     (for-each
      (lambda (entry)
        (for-each
         (lambda (where)
           (for-each
            (lambda (action)
              (write (one session entry where action url))
              (newline)
              (flush-output-port (current-output-port)))
            '(raise-cond cont-cond raise-false cont-sym)))
         '(enter parse)))
      '(request port go parallel))
     (http-session-close session)
     (write (list 'counts (native-counts)))
     (newline))))
