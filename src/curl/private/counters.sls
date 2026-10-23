#!r6rs
;;; (curl private counters): a count of every native object chez-curl
;;; holds, by kind (ADR-0014, decision 7, amended; M2 plan, section 3.2).
;;;
;;; Each count rises when an object of its kind is made, and falls when it
;;; is freed. The counts are per process in M2. They sit behind one mutex,
;;; since two threads may each make and free objects at once. There is no
;;; reset: a suite compares the counts before and after, and
;;; (curl-testing)'s suite-exit-status fails a suite whose counts are not
;;; all zero at its end. They are the leak gate for foreign memory a Chez
;;; object held, which Valgrind sees as still reachable.
;;;
;;; It never loads libcurl, so any suite can import it. R6RS forbids
;;; assigning an exported variable, so the counts are reached through
;;; procedures.
(library (curl private counters)
  (export native-kinds count-up! count-down! native-counts)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) make-mutex with-mutex))

  ;; native-kinds : (Listof Symbol)
  ;; The kinds of native object counted, in the order native-counts
  ;; answers them:
  ;;
  ;;   block        a foreign block, from (curl private memory)
  ;;   easy         an easy handle, from curl_easy_init
  ;;   url          a CURLU handle, from curl_url
  ;;   slist        a string list (M2, slice 2)
  ;;   curl-string  a string libcurl made, for curl_free
  ;;   transfer     a transfer (M2, slice 2)
  (define native-kinds '(block easy url slist curl-string transfer))

  ;; The counts, one per kind, in native-kinds order, and the mutex every
  ;; read and write holds.
  (define counts (make-vector (length native-kinds) 0))
  (define lock (make-mutex))

  ;; kind-index : Symbol Symbol -> Natural
  ;; Where KIND's count stands; an assertion violation from WHO for a
  ;; symbol that is not a kind.
  (define (kind-index who kind)
    (let loop ((kinds native-kinds) (i 0))
      (cond ((null? kinds)
             (assertion-violation who "not a kind of native object chez-curl counts" kind))
            ((eq? (car kinds) kind) i)
            (else (loop (cdr kinds) (+ i 1))))))

  ;; count-up! : Symbol -> Void
  ;; One more object of KIND.
  (define (count-up! kind)
    (let ((i (kind-index 'count-up! kind)))
      (with-mutex lock
        (vector-set! counts i (+ (vector-ref counts i) 1)))))

  ;; count-down! : Symbol -> Void
  ;; One object of KIND fewer. A count at zero stays at zero, and the call
  ;; raises an assertion violation: one more object freed than was made is
  ;; a double free.
  (define (count-down! kind)
    (let* ((i (kind-index 'count-down! kind))
           (was (with-mutex lock
                  (let ((n (vector-ref counts i)))
                    (when (> n 0)
                      (vector-set! counts i (- n 1)))
                    n))))
      (when (= was 0)
        (assertion-violation 'count-down!
                             "more objects of this kind freed than made: a double free"
                             kind))))

  ;; native-counts : -> (Listof (Pairof Symbol Natural))
  ;; Every kind with its count, in native-kinds order, read at one moment.
  (define (native-counts)
    (let ((now (with-mutex lock (vector->list counts))))
      (map cons native-kinds now))))
