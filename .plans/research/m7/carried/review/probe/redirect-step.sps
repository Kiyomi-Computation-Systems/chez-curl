;;; redirect-step.sps MODE FROM TO STEP [PATH]: does the class call-state's section
;;; closed live on in a redirect's step? exchange-step's follow parses the
;;; Location and the URLs it compares (src/http-client/private/exchange.sls,
;;; follow), with interrupts on, between the drive's await of one hop and
;;; its submit of the next, two of those parses inside a guard that takes
;;; &curl-url-error alone. A call: http-get of /redirect/302?to=/status/200
;;; on the origin's http face; PATH, when given, in its place, as the
;;; control: /status/200, a call with no redirect.
;;;
;;;   engine  the call inside a Chez engine of FUEL ticks, FUEL from FROM to
;;;           TO by STEP; an expiry resumed with 10^8 ticks.
;;;   timer   the call under a timer set to N ticks at its start, N from FROM
;;;           to TO by STEP, whose handler raises the symbol tick
;;;           continuably; the caller's with-exception-handler returns from
;;;           tick, so the documented answer is the call resumed, 200.
;;;
;;; Prints one (row N CLASS DETAIL) per run, then (summary CLASS COUNT
;;; FIRST-FIVE) for each class, then the native counts. CLASS: answered
;;; (status 200), re-entry (an assertion violation whose message holds
;;; "re-entered"), or (other WHO MESSAGE).
(import (chezscheme) (curl) (http-client) (curl-testing) (curl private counters))

(define args (command-line-arguments))
(define mode (string->symbol (list-ref args 0)))
(define from (string->number (list-ref args 1)))
(define to (string->number (list-ref args 2)))
(define step (string->number (list-ref args 3)))
(define path (if (> (length args) 4) (list-ref args 4) "/redirect/302?to=%2Fstatus%2F200"))

(define (holds? text part)
  (let ((n (string-length text)) (k (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i k) n)
           (or (string=? (substring text i (+ i k)) part) (loop (+ i 1)))))))

(define (classify e)
  (cond ((and (condition? e) (message-condition? e) (holds? (condition-message e) "re-entered"))
         (list 're-entry (and (who-condition? e) (condition-who e))))
        ((condition? e)
         (list 'other (and (who-condition? e) (condition-who e))
               (and (message-condition? e) (condition-message e))))
        (else (list 'other 'non-condition e))))

(define (run-engine session url fuel)
  (let ((eng (make-engine
              (lambda ()
                (guard (e (#t (classify e)))
                  (list 'answered (http-response-status (http-get session url))))))))
    (eng fuel
         (lambda (ticks value) (cons 'no-expiry value))
         (lambda (next)
           (cons 'expired
                 (next 100000000 (lambda (ticks value) value) (lambda (next) '(other expired-again))))))))

(define (run-timer session url n)
  (let ((previous (timer-interrupt-handler)))
    (let ((outcome
           (guard (e (#t (classify e)))
             (with-exception-handler
               (lambda (c) (if (eq? c 'tick) 'ignored (raise-continuable c)))
               (lambda ()
                 (timer-interrupt-handler (lambda () (raise-continuable 'tick)))
                 (set-timer n)
                 (list 'answered (http-response-status (http-get session url))))))))
      (set-timer 0)
      (timer-interrupt-handler previous)
      (cons 'timer outcome))))

(call-with-origin
 (lambda (o)
   (let* ((f (origin-face o 'http))
          (url (string-append "http://" (car f) ":" (number->string (cdr f))
                              path))
          (session (make-http-session 'timeout-ms 20000)))
     (let loop ((n from) (classes '()))
       (if (> n to)
           (begin
             (for-each (lambda (entry)
                         (write (list 'summary (car entry) (length (cdr entry))
                                      (let take ((l (reverse (cdr entry))) (k 5))
                                        (if (or (null? l) (= k 0)) '() (cons (car l) (take (cdr l) (- k 1)))))))
                         (newline))
                       (reverse classes))
             (http-session-close session))
           (let* ((row (if (eq? mode 'engine) (run-engine session url n) (run-timer session url n)))
                  (class (let ((c (cdr row))) (if (eq? (car c) 'answered) 'answered (list (car c) (cadr c)))))
                  (hit (assoc class classes)))
             (write (list 'row n (car row) (cdr row)))
             (newline)
             (loop (+ n step)
                   (if hit
                       (begin (set-cdr! hit (cons n (cdr hit))) classes)
                       (cons (list class n) classes)))))))))

(write (list 'counts (native-counts)))
(newline)
