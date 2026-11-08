#!r6rs
;;; tests/mime-abandon.sps: a child of tests/test-multipart.sps, which reads
;;; the one datum it prints. An engine failed by a fault planted at perform,
;;; and a transfer of a multipart body, live as the engine fails, its mime
;;; made with its easy handle: with abandon as its argument, the engine's
;;; failure abandons every live transfer's easy handle, as for one whose
;;; removal failed, through the private seam make-curl-engine-abandoning;
;;; with free, it frees each, as a failure does (make-faulty-curl-engine),
;;; the control. It prints (OUTCOME COUNTS): the transfer's outcome, as
;;; data, and every count, once the engine's stop has returned. An abandoned
;;; handle keeps its mime, which a live handle could still read: both stay
;;; counted, for good, so this runs in a process of its own (the M8 plan,
;;; section 3.4). A transfer to port 9 on 127.0.0.1 never connects before
;;; the fault, which the first perform raises, and its data part needs no
;;; file.
(import (rnrs)
        (curl)
        (curl private counters)
        (only (curl private engine) make-curl-engine-abandoning make-faulty-curl-engine))

(define how (let ((args (cdr (command-line)))) (if (pair? args) (car args) "none")))

(define engine
  (cond ((string=? how "abandon") (make-curl-engine-abandoning 'perform))
        ((string=? how "free") (make-faulty-curl-engine 'perform))
        (else (assertion-violation 'mime-abandon "the argument is abandon or free" how))))

(define token
  (curl-submit engine (make-curl-request "http://127.0.0.1:9/" 'method 'post 'proxy #f
                                         'timeout-ms 20000
                                         'body '(multipart ("field" "value")))))

(define outcome
  (if (curl-token-wait token 20000)
      (let ((o (curl-token-outcome token)))
        (cond ((curl-engine-error? o) (list 'engine-error (curl-engine-error-reason o)))
              ((curl-response? o) (list 'response (curl-response-status o)))
              (else (list 'other))))
      '(not-done)))

(curl-engine-stop engine)

(write (list outcome (native-counts)))
(newline)
