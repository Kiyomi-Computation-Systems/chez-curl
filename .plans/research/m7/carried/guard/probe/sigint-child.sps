;;; sigint-child.sps URL ENTRY WHERE ACTION: one call, whose checks block at
;;; WHERE on a mutex another thread holds until the parent has sent SIGINT
;;; (the file GUARD_CHILD_SENT names, made once the kill has returned), so
;;; the Ctrl-C handler runs where Chez runs a keyboard interrupt made
;;; pending inside that section: as the outermost critical section around
;;; WHERE ends (AGENTS.md; traps.md, "A Chez timer cannot plant an escape").
;;;
;;; ENTRY: request (http-get), port (call-with-response-port), go (a group's
;;; go, then its await) or parallel (http-parallel of one spec).
;;; WHERE: enter, the first form of call-state's checks; or parse, the first
;;; form of the first URL parse's body (the copy's seam, probe/gate.sls).
;;; ACTION, what the handler does: raise-cond, (raise PLANTED), a
;;; &curl-engine-error of the child's own; cont-cond, (raise-continuable
;;; WARNING), a &warning, which the caller's handler returns from when the
;;; condition it is handed is a warning?, as test-http-client's M5 test
;;; does; raise-false, (raise #f); cont-sym, (raise-continuable 'tick),
;;; which the caller's handler returns from when handed 'tick itself.
;;;
;;; Prints (ready PID), then
;;;   (result ENTRY WHERE ACTION OUTCOME TRAIL QUIET HOLDS RETURNED)
;;; OUTCOME (returned V) or (raised DESCRIPTION); TRAIL the seam's marks
;;; before the handler ran, in order, or never; QUIET as test-group's
;;; child-hold reads it; HOLDS the engine's live and queued counts and the
;;; transfer count 500 ms after the release; RETURNED how many times the
;;; caller's handler returned. Then (counts COUNTS) once the session is
;;; closed.
(import (chezscheme) (curl) (http-client)
        (only (http-client private call) http-session-engine)
        (only (curl private engine) curl-engine-live-count curl-engine-queued-count)
        (only (curl private conditions) make-curl-engine-error)
        (curl private counters)
        (curl private gate))

(define args (command-line-arguments))
(define url (list-ref args 0))
(define entry (string->symbol (list-ref args 1)))
(define where (string->symbol (list-ref args 2)))
(define action (string->symbol (list-ref args 3)))

(define child-sent (getenv "GUARD_CHILD_SENT"))
(define (until-sent)
  (let wait ((n 0))
    (unless (or (and child-sent (file-exists? child-sent)) (>= n 2000))
      (sleep (make-time 'time-duration 10000000 0))
      (wait (+ n 1)))))

(define session (make-http-session 'timeout-ms 20000))
(define engine (http-session-engine session))
(define gate-lock (make-mutex))
(define flag-lock (make-mutex))
(define holding #f)
(define released #f)
(define held-collections #f)
(define handler-collections #f)
(define (flag get) (critical-section (with-mutex flag-lock (get))))
(define (quiet)
  (if (and held-collections (eqv? held-collections handler-collections))
      'quiet
      (list 'collected held-collections handler-collections)))

(define trail '())
(define handler-trail 'never)
(define armed #t)
(define returned 0)

(define planted (condition (make-curl-engine-error 'stopped #f)
                           (make-message-condition "planted by the child's Ctrl-C handler")))
(define planted-warning (condition (make-warning) (make-message-condition "planted warning")))

;; described : Any -> Datum
(define (described e)
  (cond ((eq? e planted) '(the-planted-condition))
        ((eq? e planted-warning) '(the-planted-warning))
        ((condition? e)
         (list (if (http-exchange? e) 'compounded 'not-compounded)
               (if (and (message-condition? e)
                        (member (condition-message e)
                                '("planted by the child's Ctrl-C handler" "planted warning")))
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

(collect-rendezvous)
(fork-thread
 (lambda ()
   (critical-section
    (with-mutex gate-lock
      (critical-section (with-mutex flag-lock (set! held-collections (collections)) (set! holding #t)))
      (until-sent)))
   (critical-section (with-mutex flag-lock (set! released #t)))))
(let spin ()
  (unless (flag (lambda () holding))
    (sleep (make-time 'time-duration 1000000 0))
    (spin)))

(gate-set! (lambda (w)
             (set! trail (cons w trail))
             (when (and armed (eq? w where))
               (set! armed #f)
               (critical-section (with-mutex gate-lock #t)))))

(define (run-entry)
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
    (else (error 'sigint-child "no entry" entry))))

(define outcome
  (guard (e (#t (list 'raised (described e))))
    (with-exception-handler
      (lambda (c)
        (cond ((and (eq? action 'cont-cond) (condition? c) (warning? c))
               (set! returned (+ returned 1)) 'ignored)
              ((and (eq? action 'cont-sym) (eq? c 'tick))
               (set! returned (+ returned 1)) 'ignored)
              (else (raise-continuable c))))
      (lambda ()
        (keyboard-interrupt-handler
         (lambda ()
           (set! handler-collections (collections))
           (set! handler-trail (reverse trail))
           (case action
             ((raise-cond) (raise planted))
             ((cont-cond) (raise-continuable planted-warning))
             ((raise-false) (raise #f))
             ((cont-sym) (raise-continuable 'tick)))))
        (write (list 'ready (get-process-id)))
        (newline)
        (flush-output-port (current-output-port))
        (run-entry)))))
(keyboard-interrupt-handler void)
(gate-set! #f)
(let spin ()
  (unless (flag (lambda () released))
    (sleep (make-time 'time-duration 1000000 0))
    (spin)))
(sleep (make-time 'time-duration 500000000 0))
(define holds (list (curl-engine-live-count engine) (curl-engine-queued-count engine)
                    (cdr (assq 'transfer (native-counts)))))
(write (list 'result entry where action outcome handler-trail (quiet) holds returned))
(newline)
(http-session-close session)
(write (list 'counts (native-counts)))
(newline)
