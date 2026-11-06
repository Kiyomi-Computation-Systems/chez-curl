;;; refusal-probe.sps: the call's own refusals, at each entry, as the
;;; caller's handler meets them: for each ENTRY (request port go parallel)
;;; and REFUSAL, the caller's with-exception-handler records whether
;;; interrupts were on where it ran (a take of no time from a fresh
;;; mailbox, refused inside a critical section, as the drive's
;;; interrupts-on? judges it), then hands the condition on; the guard
;;; outside reads what left. REFUSAL: unknown-key ('bogus 1, the high
;;; level's); not-a-body ('body 42, the high level's); scheme (an ftp://
;;; URL, (curl)'s &curl-url-error from the URL's read); header (a header
;;; name with a space, (curl)'s &curl-request-error from make-curl-request);
;;; prior-knowledge (http-version http/2-prior-knowledge on https://, which
;;; only http-parallel's curl-request-check refuses before a submit). Prints
;;; (refusal ENTRY REFUSAL INTERRUPTS-ON-IN-HANDLER WHAT-LEFT): WHAT-LEFT
;;; (compounded? KIND WHO). Run from a copy's root.
(import (chezscheme) (curl) (http-client) (curl private counters))

(define (interrupts-on?)
  (guard (e ((and (assertion-violation? e) (who-condition? e)
                  (eq? (condition-who e) 'curl-mailbox-take))
             #f))
    (curl-mailbox-take (make-curl-mailbox) 0)
    #t))

(define session (make-http-session 'timeout-ms 5000))
(define url "http://127.0.0.1:9/never")

(define (keys-of refusal)
  (case refusal
    ((unknown-key) (values url '(bogus 1)))
    ((not-a-body) (values url '(body 42)))
    ((scheme) (values "ftp://127.0.0.1/x" '()))
    ((header) (values url '(headers (("Bad Name" . "v")))))
    ((prior-knowledge) (values "https://127.0.0.1:9/never" '(http-version http/2-prior-knowledge)))))

(define (run entry refusal)
  (let-values (((u keys) (keys-of refusal)))
    (case entry
      ((request) (apply http-request session (if (eq? refusal 'not-a-body) 'post 'get) u keys))
      ((port) (apply call-with-response-port session (if (eq? refusal 'not-a-body) 'post 'get) u
                     (append keys (list (lambda (r p) 'proc-called)))))
      ((go) (call-with-request-group session
              (lambda (go) (apply go (if (eq? refusal 'not-a-body) 'post 'get) u keys))))
      ((parallel) (http-parallel session (list (cons (if (eq? refusal 'not-a-body) 'post 'get)
                                                     (cons u keys))))))))

(for-each
 (lambda (entry)
   (for-each
    (lambda (refusal)
      (let* ((seen 'handler-not-run)
             (left (guard (e (#t (if (condition? e)
                                     (list (if (http-exchange? e) 'compounded 'not-compounded)
                                           (cond ((http-request-error? e) (list 'http-request-error (http-request-error-reason e)))
                                                 ((curl-url-error? e) 'curl-url-error)
                                                 ((curl-request-error? e) (list 'curl-request-error (curl-request-error-reason e)))
                                                 ((assertion-violation? e) 'assertion)
                                                 ((curl-transfer-error? e) (list 'transfer (curl-transfer-error-reason e)))
                                                 (else 'other))
                                           (if (who-condition? e) (condition-who e) 'no-who))
                                     (list 'non-condition e))))
                     (with-exception-handler
                       (lambda (c) (set! seen (interrupts-on?)) (raise-continuable c))
                       (lambda () (run entry refusal) 'no-refusal)))))
        (write (list 'refusal entry refusal (list 'interrupts-on-in-handler seen) left))
        (newline)))
    '(unknown-key not-a-body scheme header prior-knowledge)))
 '(request port go parallel))
(http-session-close session)
(write (list 'counts (native-counts)))
(newline)
