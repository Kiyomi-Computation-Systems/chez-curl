;;; Review 3 probe: go's recheck after a resume, placed by engine-block in
;;; PREPARE (outside every section of the group's, where a real expiry can
;;; land), through the private call-with-group.
;;;  G1: call 0's prepare blocks the engine. Resumed, go must raise closed.
;;;      A with-exception-handler handler around go records whether it runs
;;;      with interrupts on (disable-interrupts answers 1) and escapes.
;;;  G2: call 0 is entered, call 1's prepare blocks: call 0's await raises
;;;      cancelled, call 1's go raises closed.
;;;  G3: as G1, then a later go (its first check) under the same handler;
;;;      then the procedure blocks the engine a second time and returns:
;;;      the second resume must reach the join's answer.
(import (chezscheme) (curl) (http-client)
        (only (http-client private call) http-session-engine call-request)
        (only (http-client private drive) call-with-group monotonic-ns)
        (only (http-client private exchange) make-exchange)
        (only (curl private transfer) transfers-started)
        (curl private counters))

(define (interrupts-on?)
  (let ((n (disable-interrupts))) (enable-interrupts) (= n 1)))

(define (class e)
  (cond ((and (condition? e) (http-group-error? e))
         (list (http-group-error-reason e) (and (who-condition? e) (condition-who e))))
        ((condition? e) (list 'other (and (who-condition? e) (condition-who e))
                              (and (message-condition? e) (condition-message e))))
        (else (list 'non-condition e))))

(define (prepare-in s block-on)
  (lambda (method url plist)
    (when (equal? url block-on) (engine-block))
    (let-values (((request redirects allow-downgrade retry) (call-request s method url plist)))
      (make-exchange method url request (curl-request-timeout-ms request)
                     (monotonic-ns) redirects allow-downgrade retry))))

;; go under a with-exception-handler handler that escapes with what it saw.
(define (go-seen go url)
  (call/cc
   (lambda (k)
     (with-exception-handler
      (lambda (e) (k (list 'handler 'interrupts-on (interrupts-on?) (class e))))
      (lambda () (go 'get url) 'answered-a-pending)))))

(define (engine-run thunk)
  (let* ((expiries 0) (at #f) (result '(never)) (eng (make-engine thunk)))
    (let resume ((e eng))
      (e 100000000
         (lambda (left v) (set! result v))
         (lambda (next)
           (set! expiries (+ expiries 1))
           (unless at (set! at (transfers-started)))
           (if (< expiries 5) (resume next) (set! result '(too-many))))))
    (list 'expiries expiries 'result result 'started-after (and at (- (transfers-started) at)))))

(define u0 "http://127.0.0.1:1/zero")
(define u1 "http://127.0.0.1:1/one")
(define u2 "http://127.0.0.1:1/two")

;; G1
(let ((s (make-http-session 'timeout-ms 5000)))
  (write (list 'G1
               (engine-run
                (lambda ()
                  (guard (e (#t (list 'group-raised (class e))))
                    (call-with-group (http-session-engine s) #f (lambda () 0.5) (prepare-in s u0)
                      (lambda (go) (go-seen go u0))))))))
  (newline)
  (http-session-close s))

;; G2
(let ((s (make-http-session 'timeout-ms 5000)))
  (write (list 'G2
               (engine-run
                (lambda ()
                  (guard (e (#t (list 'group-raised (class e))))
                    (call-with-group (http-session-engine s) #f (lambda () 0.5) (prepare-in s u1)
                      (lambda (go)
                        (let* ((p0 (go 'get u0))
                               (r1 (go-seen go u1)))
                          (list 'await0 (guard (e (#t (class e))) (http-await p0) 'answered)
                                'go1 r1)))))))))
  (newline)
  (http-session-close s))

;; G3
(let ((s (make-http-session 'timeout-ms 5000)))
  (write (list 'G3
               (engine-run
                (lambda ()
                  (guard (e (#t (list 'group-raised (class e))))
                    (call-with-group (http-session-engine s) #f (lambda () 0.5) (prepare-in s u0)
                      (lambda (go)
                        (let* ((r0 (go-seen go u0))
                               (r2 (go-seen go u2)))
                          (engine-block)
                          (list 'go0 r0 'go2 r2 'returned)))))))))
  (newline)
  (http-session-close s))
(write (list 'counts (native-counts))) (newline)
