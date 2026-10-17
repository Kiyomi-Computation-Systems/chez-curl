#!r6rs
;;; The suite for the variadic bindings of (curl private native), in a
;;; process of its own: curl_easy_setopt, bound once per value type, and
;;; curl_easy_getinfo, each with (__varargs_after 2) (ADR-0001, decision 1).
;;; It imports native, so the whole load runs before its first line, as in
;;; tests/test-native.sps.
;;;
;;; Each binding must deliver its value, or a test fails by name. No
;;; transfer runs: libcurl stores what setopt gives it, and getinfo reads it
;;; back, or answers by its code.
;;;
;;;   pointer  PRIVATE through curl-easy-setopt-pointer, read back through
;;;            curl-easy-getinfo as CURLINFO_PRIVATE. libcurl keeps the
;;;            pointer and never dereferences it, so any value round-trips:
;;;            two sentinels with high bits set, each above 2^32.
;;;   long     RTSP_CLIENT_CSEQ through curl-easy-setopt-long, read back as
;;;            CURLINFO_RTSP_CLIENT_CSEQ. Needs a libcurl built with RTSP.
;;;            libcurl 8.20 clamps a value above 2^31-1 and refuses a
;;;            negative one with CURLE_BAD_FUNCTION_ARGUMENT, keeping the
;;;            value it had, so the two sentinels lie in [1, 2^31-1], each
;;;            setopt's code is asserted, and they differ: a refused second
;;;            value would read back as the first.
;;;            So the round trip never sees a long's sign or high half.
;;;            MAXFILESIZE does: a long libcurl has no readback for, but
;;;            answers by sign: 0 and 2^40 are CURLE_OK, -1 and -(2^40)
;;;            CURLE_BAD_FUNCTION_ARGUMENT. Chez passes an int zero-extended,
;;;            so a binding that typed the long int would hand libcurl -1 as
;;;            2^32-1, which it takes; and Chez itself refuses 2^40 and
;;;            -(2^40) for an int.
;;;   off_t    MAXFILESIZE_LARGE through curl-easy-setopt-off-t. libcurl
;;;            has no readback for it, but answers by sign: 0 and 2^62 are
;;;            CURLE_OK, -1 and -(2^62) CURLE_BAD_FUNCTION_ARGUMENT. So the
;;;            high half and the sign must both arrive.
;;;
;;; Options are looked up by name, through curl-easy-option, never written
;;; as numbers (ADR-0001, decision 2). Each one's CURLOT type code must be
;;; the one its binding passes.
;;;
;;; Before each getinfo the slot it writes holds a poison, distinct from
;;; every sentinel, so a getinfo that writes nothing reads the poison, never
;;; the last answer. Each step runs in turn under let*: Chez evaluates a
;;; call's arguments in no fixed order (AGENTS.md).
;;;
;;; Where this suite can fail: x86-64 and Linux arm64 pass variadic integer
;;; and pointer arguments as they pass named ones, so a binding without
;;; (__varargs_after 2) passes here too. Apple arm64 passes them on the
;;; stack: there, setopt reads garbage, and getinfo may write through a
;;; garbage pointer and crash. make check-variadic removes the convention
;;; in a copy, from the template and then from each binding alone, and
;;; requires this suite to fail on arm64osx and tarm64osx: by name, naming
;;; that binding's tests, for each setopt binding alone.
;;;
;;; It frees what it makes: the easy handle with curl_easy_cleanup, and the
;;; slot with foreign-free. make test-memory runs it under Valgrind.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) foreign-alloc foreign-free foreign-ref foreign-set!)
        (curl-testing)
        (curl private constants)
        (curl private native))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; --- the values -----------------------------------------------------------------

;; Pointers: each above 2^32, so its high half must arrive, the second with
;; bit 63 set.
(define pointer-sentinels '(#x0123456789ABCDEF #xFEDCBA9876543210))
(define pointer-poison #x5A5A5A5A5A5A5A5A)

;; Longs: in [1, 2^31-1], which libcurl 8.20 neither clamps nor refuses.
(define long-sentinels '(1234567 2000000011))
(define long-poison -1)

;; long, by its sign: each value, and whether libcurl takes it.
(define long-cases
  (list (cons 0 'ok) (cons -1 'refused) (cons (expt 2 40) 'ok) (cons (- (expt 2 40)) 'refused)))

;; off_t: each value, and whether libcurl takes it.
(define off-t-cases
  (list (cons 0 'ok) (cons -1 'refused) (cons (- (expt 2 62)) 'refused) (cons (expt 2 62) 'ok)))

(define (hex n) (string-append "#x" (number->string n 16)))

;; curlot : Symbol -> (U Natural (List 'no-curlot Symbol))
;; NAME's CURLOT type code from (curl private constants); a sentinel when it
;; has none, so an expected value never raises.
(define (curlot name)
  (guard (e (#t (list 'no-curlot name)))
    (let ((entry (assq name curlot-types)))
      (if (and entry (integer? (cdr entry))) (cdr entry) (list 'no-curlot name)))))

;; --- the options, by name ---------------------------------------------------------

;; looked-up : String -> (U (Pairof Integer Natural) (List 'unknown String) (List 'raised String))
(define (looked-up name)
  (guard (e (#t (list 'raised (describe e))))
    (or (curl-easy-option name) (list 'unknown name))))

(define private (looked-up "PRIVATE"))
(define cseq (looked-up "RTSP_CLIENT_CSEQ"))
(define maxfilesize (looked-up "MAXFILESIZE"))
(define maxfilesize-large (looked-up "MAXFILESIZE_LARGE"))

;; id-of : Any -> Any
;; The option's id; else the failed lookup, which no binding takes, so the
;; test that hands it on fails.
(define (id-of option)
  (if (and (pair? option) (integer? (car option))) (car option) option))

;; type-of : Any -> Any
(define (type-of option)
  (if (and (pair? option) (integer? (car option))) (list 'type (cdr option)) option))

;; --- the handle and the slot -------------------------------------------------------

(define easy (guard (e (#t 0)) (curl-easy-init)))
(define slot (guard (e (#t 0)) (foreign-alloc 8)))

;; pointer-trip : Natural -> (List 'setopt Any 'getinfo Any 'read Any)
;; PRIVATE set to VALUE, then read back into the poisoned slot.
(define (pointer-trip value)
  (let* ((set (curl-easy-setopt-pointer easy (id-of private) value))
         (poisoned (foreign-set! 'uptr slot 0 pointer-poison))
         (got (curl-easy-getinfo easy curlinfo-private slot))
         (back (foreign-ref 'uptr slot 0)))
    (list 'setopt set 'getinfo got 'read back)))

;; long-trip : Integer -> (List 'setopt Any 'getinfo Any 'read Any)
;; RTSP_CLIENT_CSEQ set to VALUE, then read back into the poisoned slot.
(define (long-trip value)
  (let* ((set (curl-easy-setopt-long easy (id-of cseq) value))
         (poisoned (foreign-set! 'long slot 0 long-poison))
         (got (curl-easy-getinfo easy curlinfo-rtsp-client-cseq slot))
         (back (foreign-ref 'long slot 0)))
    (list 'setopt set 'getinfo got 'read back)))

(test-begin "variadic")

(test-equal "curl-easy-init answers a handle, and foreign-alloc a slot for getinfo"
  '(handle slot)
  (list (if (and (integer? easy) (positive? easy)) 'handle easy)
        (if (and (integer? slot) (positive? slot)) 'slot slot)))

(unless (and (integer? easy) (positive? easy) (integer? slot) (positive? slot))
  (exit 1))

;; --- the suite's own values ---------------------------------------------------------
;; Each design rule above, held: a sentinel used twice, or one libcurl
;; clamps, would let a value that never arrived pass.

(test-equal "the pointer sentinels are two, distinct, each above 2^32, and none is the poison"
  '(two distinct high not-poison)
  (list (if (= (length pointer-sentinels) 2) 'two (length pointer-sentinels))
        (if (= (car pointer-sentinels) (cadr pointer-sentinels)) 'same 'distinct)
        (if (for-all (lambda (v) (> v (expt 2 32))) pointer-sentinels) 'high 'low)
        (if (memv pointer-poison pointer-sentinels) 'poison 'not-poison)))

(test-equal "the long sentinels are two, distinct, each in [1, 2^31-1], and none is the poison"
  '(two distinct in-range not-poison)
  (list (if (= (length long-sentinels) 2) 'two (length long-sentinels))
        (if (= (car long-sentinels) (cadr long-sentinels)) 'same 'distinct)
        (if (for-all (lambda (v) (<= 1 v (- (expt 2 31) 1))) long-sentinels) 'in-range 'out-of-range)
        (if (memv long-poison long-sentinels) 'poison 'not-poison)))

;; A long typed int arrives zero-extended: -1 as 2^32-1, which libcurl
;; takes. And Chez refuses an int beyond 32 bits before any call.
(test-equal "the long cases are -1, whose 32-bit twin libcurl takes, and two beyond 32 bits, one each way, each answer as its sign says"
  '(minus-one beyond-32-bits signs-agree)
  (list (if (assv -1 long-cases) 'minus-one 'no-minus-one)
        (if (and (exists (lambda (c) (> (car c) (expt 2 32))) long-cases)
                 (exists (lambda (c) (< (car c) (- (expt 2 31)))) long-cases))
            'beyond-32-bits
            'within-32-bits)
        (if (for-all (lambda (c) (eq? (cdr c) (if (negative? (car c)) 'refused 'ok))) long-cases)
            'signs-agree
            'signs-disagree)))

;; --- each option, and its type ----------------------------------------------------------

(test-equal "PRIVATE is known to the loaded libcurl as CURLOT_OBJECT, the pointer curl-easy-setopt-pointer passes"
  (list 'type (curlot 'object))
  (type-of private))

(test-equal "RTSP_CLIENT_CSEQ is known to the loaded libcurl as CURLOT_LONG, the long curl-easy-setopt-long passes"
  (list 'type (curlot 'long))
  (type-of cseq))

(test-equal "MAXFILESIZE is known to the loaded libcurl as CURLOT_LONG, the long curl-easy-setopt-long passes"
  (list 'type (curlot 'long))
  (type-of maxfilesize))

(test-equal "MAXFILESIZE_LARGE is known to the loaded libcurl as CURLOT_OFF_T, the curl_off_t curl-easy-setopt-off-t passes"
  (list 'type (curlot 'off-t))
  (type-of maxfilesize-large))

(test-equal "curl-easy-option answers #f for a name the loaded libcurl does not know"
  'unknown
  (if (curl-easy-option "NO_SUCH_OPTION") 'known 'unknown))

;; --- the round trips -------------------------------------------------------------------

(for-each
 (lambda (value)
   (test-equal (string-append "PRIVATE set to " (hex value)
                              " through curl-easy-setopt-pointer reads back exactly through curl-easy-getinfo")
     (list 'setopt curle-ok 'getinfo curle-ok 'read value)
     (pointer-trip value)))
 pointer-sentinels)

(for-each
 (lambda (value)
   (test-equal (string-append "RTSP_CLIENT_CSEQ set to " (number->string value)
                              " through curl-easy-setopt-long reads back exactly through curl-easy-getinfo")
     (list 'setopt curle-ok 'getinfo curle-ok 'read value)
     (long-trip value)))
 long-sentinels)

;; --- long, by its sign ----------------------------------------------------------------------

(for-each
 (lambda (case)
   (let ((value (car case)) (taken? (eq? (cdr case) 'ok)))
     (test-equal (string-append "MAXFILESIZE set to " (number->string value)
                                " through curl-easy-setopt-long answers "
                                (if taken? "CURLE_OK" "CURLE_BAD_FUNCTION_ARGUMENT"))
       (if taken? curle-ok curle-bad-function-argument)
       (curl-easy-setopt-long easy (id-of maxfilesize) value))))
 long-cases)

;; --- off_t, by its sign --------------------------------------------------------------------

(for-each
 (lambda (case)
   (let ((value (car case)) (taken? (eq? (cdr case) 'ok)))
     (test-equal (string-append "MAXFILESIZE_LARGE set to " (number->string value)
                                " through curl-easy-setopt-off-t answers "
                                (if taken? "CURLE_OK" "CURLE_BAD_FUNCTION_ARGUMENT"))
       (if taken? curle-ok curle-bad-function-argument)
       (curl-easy-setopt-off-t easy (id-of maxfilesize-large) value))))
 off-t-cases)

;; --- freeing what it made --------------------------------------------------------------------

(curl-easy-cleanup easy)
(foreign-free slot)

(test-end "variadic")

(exit (suite-exit-status runner))
