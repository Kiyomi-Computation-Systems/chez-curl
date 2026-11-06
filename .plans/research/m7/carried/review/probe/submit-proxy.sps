;;; submit-proxy.sps MODE FROM TO STEP: the low level's curl-submit, called
;;; with interrupts on, of a request whose proxy is a URL string, so its
;;; checks run check-proxy-url (src/curl/private/transfer.sls), whose guard
;;; takes &curl-url-error alone around proxy-url-reading's URL parse, a
;;; critical wind that refuses re-entry. Nothing is fetched: each token is
;;; cancelled once submitted.
;;;
;;;   engine  the submit inside a Chez engine of FUEL ticks, FUEL from FROM
;;;           to TO by STEP; an expiry resumed with 10^8 ticks.
;;;   timer   the submit under a timer set to N ticks, whose handler raises
;;;           the symbol tick continuably, which the caller's handler
;;;           returns from: the submit should go on and answer its token.
;;;
;;; Prints one (row N HOW OUTCOME) per run, then (summary CLASS COUNT
;;; FIRST-FIVE) for each class: submitted, re-entry (an assertion violation
;;; whose message holds "re-entered"), or (other WHO MESSAGE).
(import (chezscheme) (curl) (curl private counters))

(define args (command-line-arguments))
(define mode (string->symbol (list-ref args 0)))
(define from (string->number (list-ref args 1)))
(define to (string->number (list-ref args 2)))
(define step (string->number (list-ref args 3)))

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

(define engine (make-curl-engine))
(define request (make-curl-request "http://127.0.0.1:9/never" 'proxy "http://127.0.0.1:9" 'timeout-ms 5000))

(define (submitted token)
  (curl-token-cancel token)
  (guard (e (#t #f)) (curl-token-await token))
  '(submitted))

(define (run-engine fuel)
  (let ((eng (make-engine (lambda () (guard (e (#t (classify e))) (submitted (curl-submit engine request)))))))
    (eng fuel
         (lambda (ticks value) (cons 'no-expiry value))
         (lambda (next)
           (cons 'expired (next 100000000 (lambda (ticks value) value) (lambda (next) '(other expired-again))))))))

(define (run-timer n)
  (let* ((previous (timer-interrupt-handler))
         (outcome
          (guard (e (#t (classify e)))
            (with-exception-handler
              (lambda (c) (if (eq? c 'tick) 'ignored (raise-continuable c)))
              (lambda ()
                (timer-interrupt-handler (lambda () (raise-continuable 'tick)))
                (set-timer n)
                (let ((token (curl-submit engine request)))
                  (set-timer 0)
                  (submitted token)))))))
    (set-timer 0)
    (timer-interrupt-handler previous)
    (cons 'timer outcome)))

(let loop ((n from) (classes '()))
  (if (> n to)
      (for-each (lambda (entry)
                  (write (list 'summary (car entry) (length (cdr entry))
                               (let take ((l (reverse (cdr entry))) (k 5))
                                 (if (or (null? l) (= k 0)) '() (cons (car l) (take (cdr l) (- k 1)))))))
                  (newline))
                (reverse classes))
      (let* ((row (if (eq? mode 'engine) (run-engine n) (run-timer n)))
             (class (let ((c (cdr row))) (if (eq? (car c) 'submitted) 'submitted (list (car c) (cadr c)))))
             (hit (assoc class classes)))
        (write (list 'row n (car row) (cdr row)))
        (newline)
        (loop (+ n step)
              (if hit
                  (begin (set-cdr! hit (cons n (cdr hit))) classes)
                  (cons (list class n) classes))))))

(curl-engine-stop engine)
(write (list 'counts (native-counts)))
(newline)
