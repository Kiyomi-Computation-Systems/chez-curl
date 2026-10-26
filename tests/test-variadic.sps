#!r6rs
;;; The suite for the variadic bindings of (curl private native), in a
;;; process of its own: curl_easy_setopt, bound once per value type,
;;; curl_easy_getinfo, and curl_multi_setopt, bound once for a long, each
;;; with (__varargs_after 2) (ADR-0001, decision 1, amended 2026-10-25). It
;;; imports native, so the whole load runs before its first line, as in
;;; tests/test-native.sps.
;;;
;;; Each binding must deliver its value, or a test fails by name. For the
;;; easy bindings no transfer runs: libcurl stores what setopt gives it, and
;;; getinfo reads it back, or answers by its code.
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
;;;   multi    MAX_TOTAL_CONNECTIONS through curl-multi-setopt-long. No long
;;;            multi option answers by its value before libcurl 8.20.0, so
;;;            the check is by its effect, against the test origin: two
;;;            drips of 10 bytes, 100 ms apart, in one multi handle of their
;;;            own, driven by perform, info_read and poll until both are
;;;            done. At 1 the second waits for the first, and is done about
;;;            1 s after it; at 2 they run together, done within 60 ms of
;;;            each other (measured on four Linux libcurls, and under
;;;            Valgrind). So the second done 500 ms or more after the first
;;;            is serial, and sooner together. The gap, not the time since
;;;            the start: Valgrind's first transfer in a process runs late,
;;;            so a run together that came first finished at 1,793 to
;;;            1,863 ms under Valgrind and load, past any absolute
;;;            threshold. A value that did not arrive gives both settings the
;;;            same answer, unless it differs between the two calls, so one
;;;            of them fails. The bodies go to a file of each run's own, as
;;;            WRITEDATA, a FILE * from fopen, through libcurl's default
;;;            write callback, so nothing of them reaches this suite's
;;;            output and no Scheme callable runs inside curl_multi_perform,
;;;            which is __collect_safe; the file must hold both bodies
;;;            whole.
;;;            By its sign: what -1 answers, written out here per libcurl
;;;            version, CURLM_BAD_FUNCTION_ARGUMENT on 8.20.0 and CURLM_OK
;;;            on 7.85.0 and 8.5.0. A libcurl with no row fails by name, and
;;;            the suite prints the row it would need. 2^40 answers CURLM_OK
;;;            on every one. A binding that typed the long int would hand
;;;            8.20.0 -1 as 2^32-1, which it takes, and Chez refuses 2^40.
;;;            The drips hand libcurl a URL and a FILE * through
;;;            curl-easy-setopt-pointer, so they run only when PRIVATE read
;;;            back exactly through it: a pointer that did not arrive would
;;;            have libcurl read or write through garbage.
;;;
;;; Options are looked up by name, through curl-easy-option, never written
;;; as numbers (ADR-0001, decision 2). Each one's CURLOT type code must be
;;; the one its binding passes. A multi option has no lookup by name, so
;;; MAX_TOTAL_CONNECTIONS comes from (curl private constants).
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
;;; that binding's tests, for each setopt binding alone, the multi one
;;; included.
;;;
;;; It frees what it makes: each easy handle with curl_easy_cleanup, each
;;; multi handle with curl_multi_cleanup, each FILE * with fclose, and the
;;; slot with foreign-free. make test-memory runs it under Valgrind. The
;;; test origin runs under NODE, from the working directory, which holds
;;; tests/origin.mjs.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) foreign-alloc foreign-free foreign-ref foreign-set! foreign-procedure
              current-time time-second time-nanosecond)
        (curl-testing)
        (curl private constants)
        (curl private libcurl-info)
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

;; The multi long, by its effect: MAX_TOTAL_CONNECTIONS at 1, which alone
;; makes two transfers to one origin wait for each other, and at 2.
(define serial-setting 1)
(define together-setting 2)

;; Each drip: this many bytes, one every this many ms.
(define drip-bytes 10)
(define drip-gap-ms 100)

;; Measured (ADR-0001, amended 2026-10-25), between the two transfers'
;; messages, on the four Linux libcurls and under the gate's Valgrind, idle
;; and under load: the widest gap together, and the narrowest one after
;; the other.
(define together-widest-gap-ms 54)
(define serial-narrowest-gap-ms 1008)

;; The second done this many ms or more after the first is serial; sooner,
;; together.
(define drip-gap-threshold-ms 500)

;; How long a poll waits at most, and how long the drips may take in all
;; before the suite gives up on them and frees their handles.
(define drip-poll-ms 100)
(define drip-deadline-ms 10000)

;; The multi long, by its sign: what MAX_TOTAL_CONNECTIONS set to -1
;; answers, by libcurl version, each measured (ADR-0001, amended
;; 2026-10-25). 8.20.0 refuses a negative value with
;; CURLM_BAD_FUNCTION_ARGUMENT, 10; 7.85.0 and 8.5.0 take it. A libcurl
;; with no row here fails by name, and the suite prints the row to add.
(define minus-one-rows
  '(("7.85.0" 0)
    ("8.5.0" 0)
    ("8.20.0" 10)))

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
(define url-option (looked-up "URL"))
(define writedata (looked-up "WRITEDATA"))
(define nosignal (looked-up "NOSIGNAL"))

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

;; --- the multi handle's long --------------------------------------------------------

;; in-turn : (A -> B) (Listof A) -> (Listof B)
;; PROC applied to each of XS, first to last, each call after the one
;; before: map calls its procedure in no fixed order (AGENTS.md).
(define (in-turn proc xs)
  (if (null? xs)
      '()
      (let* ((head (proc (car xs)))
             (tail (in-turn proc (cdr xs))))
        (cons head tail))))

;; now-ms : -> Integer
;; Milliseconds on the monotonic clock.
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; libc's, for the drips' bodies: libcurl's default write callback hands
;; each to fwrite on WRITEDATA, a FILE * these open and close. Native loads
;; libcurl, and libc with it, before this program's first line.
(define fopen (foreign-procedure "fopen" (string string) uptr))
(define fclose (foreign-procedure "fclose" (uptr) int))

;; multi-answer : Integer -> Any
;; MAX_TOTAL_CONNECTIONS set to VALUE through curl-multi-setopt-long on a
;; fresh multi handle, which is then freed: (setopt CODE cleanup CODE). A
;; raise from the setopt is its answer, and the handle is still freed.
(define (multi-answer value)
  (guard (e (#t (list 'raised (describe e))))
    (let ((multi (curl-multi-init)))
      (if (eqv? multi 0)
          (list 'no-multi-handle)
          (let* ((set (guard (e (#t (list 'raised (describe e))))
                        (curl-multi-setopt-long multi curlmopt-max-total-connections value)))
                 (freed (curl-multi-cleanup multi)))
            (list 'setopt set 'cleanup freed))))))

;; drip-url : Origin -> String
(define (drip-url origin)
  (let ((face (origin-face origin 'raw)))
    (string-append "http://" (car face) ":" (number->string (cdr face))
                   "/raw/drip?bytes=" (number->string drip-bytes)
                   "&gap=" (number->string drip-gap-ms))))

;; drip-easy : String Positive-Integer -> (Pairof Natural (Listof Any))
;; A fresh easy handle for URL, its body to SINK, a FILE *, and the codes
;; of its three setopts, URL, WRITEDATA and NOSIGNAL, in turn; (0) when
;; libcurl could make no handle. libcurl copies the URL.
(define (drip-easy url sink)
  (let ((easy (curl-easy-init)))
    (if (eqv? easy 0)
        (list 0)
        (let* ((u (call-with-c-string url
                    (lambda (address) (curl-easy-setopt-pointer easy (id-of url-option) address))))
               (w (curl-easy-setopt-pointer easy (id-of writedata) sink))
               (n (curl-easy-setopt-long easy (id-of nosignal) 1)))
          (list easy u w n)))))

;; drive : Positive-Integer (Listof Positive-Integer)
;;         -> (List (U 'done 'timed-out (List Symbol Integer)) (U Integer #f) Integer
;;                  (Listof (Pairof Natural Any)))
;; Runs EASIES in MULTI, by perform, info_read and poll, until each is
;; done, a call answers other than CURLM_OK, or drip-deadline-ms pass: how
;; it ended, the ms until the first was done and until it ended, and each
;; done transfer's easy handle with its CURLcode. The counts go through
;; slot.
(define (drive multi easies)
  (let ((start (now-ms)))
    (let loop ((done '()) (first-ms #f))
      (let-values (((code running) (curl-multi-perform multi slot)))
        (if (not (eqv? code curlm-ok))
            (list (list 'perform code) first-ms (- (now-ms) start) done)
            (let drain ((done done) (first-ms first-ms))
              (let* ((message (curl-multi-info-read multi slot))
                     (elapsed (- (now-ms) start)))
                (cond (message
                       (drain (cons (cons (cadr message)
                                          (if (eqv? (car message) curlmsg-done)
                                              (caddr message)
                                              (list 'msg (car message))))
                                    done)
                              (or first-ms elapsed)))
                      ((>= (length done) (length easies)) (list 'done first-ms elapsed done))
                      ((>= elapsed drip-deadline-ms) (list 'timed-out first-ms elapsed done))
                      (else
                       (let ((polled (curl-multi-poll multi drip-poll-ms)))
                         (if (eqv? polled curlm-ok)
                             (loop done first-ms)
                             (list (list 'poll polled) first-ms (- (now-ms) start) done))))))))))))

;; drips-in-multi : String Positive-Integer Integer -> Any
;; Two drips of URL, each body to SINK, in one fresh multi handle with
;; MAX_TOTAL_CONNECTIONS set to VALUE through curl-multi-setopt-long, then
;; every handle freed: the setopt's code, each easy handle's setopt codes,
;; each add's code, each transfer's CURLcode, the verdict, serial or
;; together, by how long after the first the second was done, each
;; removal's code and the multi
;; handle's cleanup's. It prints when the first and both were done.
(define (drips-in-multi url sink value)
  (let ((multi (curl-multi-init)))
    (if (eqv? multi 0)
        (list 'no-multi-handle)
        (let* ((set (guard (e (#t (list 'raised (describe e))))
                      (curl-multi-setopt-long multi curlmopt-max-total-connections value)))
               (made (in-turn (lambda (i) (drip-easy url sink)) '(1 2)))
               (easies (filter positive? (map car made)))
               (added (in-turn (lambda (easy) (curl-multi-add-handle multi easy)) easies))
               (ran (drive multi easies))
               (removed (in-turn (lambda (easy) (curl-multi-remove-handle multi easy)) easies))
               (cleaned (in-turn curl-easy-cleanup easies))
               (freed (curl-multi-cleanup multi))
               (ending (car ran))
               (both-ms (caddr ran)))
          (put-string (current-output-port)
            (string-append "test-variadic: two drips at MAX_TOTAL_CONNECTIONS "
                           (number->string value) ": "
                           (if (symbol? ending) (symbol->string ending) "failed")
                           ", the first done at "
                           (if (cadr ran) (number->string (cadr ran)) "none")
                           " ms, both at " (number->string both-ms) " ms\n"))
          (list 'setopt set
                'set (map cdr made)
                'added added
                'results (map (lambda (easy)
                                (let ((result (assv easy (cadddr ran))))
                                  (if result (cdr result) 'not-done)))
                              (map car made))
                'verdict (cond ((not (eq? ending 'done)) ending)
                               ((>= (- both-ms (cadr ran)) drip-gap-threshold-ms) 'serial)
                               (else 'together))
                'removed removed
                'cleanup freed)))))

;; sorted-bytes : String -> (U String (List 'unreadable String))
;; The bytes of the file at PATH, sorted, one char per byte.
(define (sorted-bytes path)
  (guard (e (#t (list 'unreadable (describe e))))
    (let ((bytes (call-with-port (open-file-input-port path) get-bytevector-all)))
      (if (eof-object? bytes)
          ""
          (list->string (map integer->char (list-sort < (bytevector->u8-list bytes))))))))

;; two-drips : String String Integer -> Any
;; drips-in-multi's answer, the bodies written to a file of their own in
;; DIR, as WRITEDATA, a FILE * from fopen, so nothing of them reaches this
;; suite's output; then the fclose's code and the file's bytes, sorted.
(define (two-drips url dir value)
  (let* ((path (string-append dir "/bodies-" (number->string value)))
         (sink (fopen path "w")))
    (if (eqv? sink 0)
        (list 'no-sink path)
        (let* ((answer (drips-in-multi url sink value))
               (closed (fclose sink)))
          (append answer (list 'closed closed 'bodies (sorted-bytes path)))))))

;; Both drips' bodies, sorted: tests/origin.mjs's drip sends a, b, c and
;; on, one byte a gap, drip-bytes of them.
(define bodies-expected "aabbccddeeffgghhiijj")

;; drips-expected : Symbol -> (Listof Any)
;; two-drips' whole answer when every call answers OK, both bodies arrive
;; whole in their file, and VERDICT holds.
(define (drips-expected verdict)
  (list 'setopt curlm-ok
        'set (list (list curle-ok curle-ok curle-ok) (list curle-ok curle-ok curle-ok))
        'added (list curlm-ok curlm-ok)
        'results (list curle-ok curle-ok)
        'verdict verdict
        'removed (list curlm-ok curlm-ok)
        'cleanup curlm-ok
        'closed 0
        'bodies bodies-expected))

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

;; The drips' threshold must part the measured gaps, each drip must take a
;; second or more, so that the second's wait shows, and only 1 serialises;
;; two drips one after the other must end well before the deadline.
(test-equal "the drip settings are 1 and 2, each drip takes 1000 ms or more, the gap threshold lies between the widest measured gap together and the narrowest one after the other, and two drips in turn fit the deadline twice over"
  '(one-then-two at-least-a-second between below-deadline)
  (list (if (and (= serial-setting 1) (= together-setting 2)) 'one-then-two
            (list serial-setting together-setting))
        (if (>= (* drip-bytes drip-gap-ms) 1000) 'at-least-a-second (* drip-bytes drip-gap-ms))
        (if (< together-widest-gap-ms drip-gap-threshold-ms serial-narrowest-gap-ms) 'between
            drip-gap-threshold-ms)
        (if (< (* 4 drip-bytes drip-gap-ms) drip-deadline-ms) 'below-deadline drip-deadline-ms)))

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

(test-equal "URL is known to the loaded libcurl as CURLOT_STRING, the char * curl-easy-setopt-pointer passes"
  (list 'type (curlot 'string))
  (type-of url-option))

(test-equal "WRITEDATA is known to the loaded libcurl as CURLOT_CBPTR, the void * curl-easy-setopt-pointer passes"
  (list 'type (curlot 'cbptr))
  (type-of writedata))

(test-equal "NOSIGNAL is known to the loaded libcurl as CURLOT_LONG, the long curl-easy-setopt-long passes"
  (list 'type (curlot 'long))
  (type-of nosignal))

(test-equal "curl-easy-option answers #f for a name the loaded libcurl does not know"
  'unknown
  (if (curl-easy-option "NO_SUCH_OPTION") 'known 'unknown))

;; --- the round trips -------------------------------------------------------------------

;; Each pointer round trip's sentinel and answer, kept for the drips below.
(define pointer-answers '())

(for-each
 (lambda (value)
   (let ((answer (guard (e (#t (list 'raised (describe e)))) (pointer-trip value))))
     (set! pointer-answers (cons (cons value answer) pointer-answers))
     (test-equal (string-append "PRIVATE set to " (hex value)
                                " through curl-easy-setopt-pointer reads back exactly through curl-easy-getinfo")
       (list 'setopt curle-ok 'getinfo curle-ok 'read value)
       answer)))
 pointer-sentinels)

;; pointer-delivers? : Boolean
;; Every pointer sentinel read back exactly.
(define pointer-delivers?
  (and (= (length pointer-answers) (length pointer-sentinels))
       (for-all (lambda (entry)
                  (equal? (cdr entry) (list 'setopt curle-ok 'getinfo curle-ok 'read (car entry))))
                pointer-answers)))

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

;; --- the multi long, by its effect: two drips -------------------------------------------

;; Both runs, in one origin and one temporary directory, under a guard; or
;; why they did not run: they hand libcurl a URL and a FILE * through
;; curl-easy-setopt-pointer.
(define drips
  (if (not pointer-delivers?)
      (list 'not-run "PRIVATE did not read back through curl-easy-setopt-pointer, which hands libcurl the drips' URL and FILE *")
      (guard (e (#t (list 'raised (describe e))))
        (call-with-temp-directory
         (lambda (dir)
           (call-with-origin
            (lambda (origin)
              (let* ((url (drip-url origin))
                     (serial (two-drips url dir serial-setting))
                     (together (two-drips url dir together-setting)))
                (list 'ran serial together)))))))))

;; drips-answer : Natural -> Any
;; The Nth run's answer, 1 serial and 2 together, or why none ran.
(define (drips-answer n)
  (if (and (pair? drips) (eq? (car drips) 'ran)) (list-ref drips n) drips))

(test-equal (string-append "two drips with MAX_TOTAL_CONNECTIONS set to " (number->string serial-setting)
                           " through curl-multi-setopt-long run one after the other: the second is done "
                           (number->string drip-gap-threshold-ms)
                           " ms or more after the first, and every call and both transfers answer OK")
  (drips-expected 'serial)
  (drips-answer 1))

(test-equal (string-append "two drips with MAX_TOTAL_CONNECTIONS set to " (number->string together-setting)
                           " through curl-multi-setopt-long run together: the second is done within "
                           (number->string drip-gap-threshold-ms)
                           " ms of the first, and every call and both transfers answer OK")
  (drips-expected 'together)
  (drips-answer 2))

;; --- the multi long, by its sign ------------------------------------------------------------

;; The loaded libcurl's version, and its rows in minus-one-rows.
(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

(define version-text
  (if (string? version) version "of no version read"))

(define version-rows
  (filter (lambda (row) (equal? (car row) version)) minus-one-rows))

(define minus-one-answer (multi-answer -1))

;; No row: say so on the error port, with the row to add.
(unless (= (length version-rows) 1)
  (let ((err (current-error-port)))
    (put-string err
      (string-append
       "test-variadic: " (if (null? version-rows) "no row" "more than one row")
       " of minus-one-rows, what MAX_TOTAL_CONNECTIONS set to -1 answers, is for libcurl "
       version-text ".\n"
       "test-variadic: if it is one to support, review its answer, and add this row to\n"
       "test-variadic: minus-one-rows in tests/test-variadic.sps:\n\n    "
       (call-with-string-output-port
        (lambda (p)
          (write (list version
                       (if (and (list? minus-one-answer) (= (length minus-one-answer) 4)
                                (eq? (car minus-one-answer) 'setopt))
                           (cadr minus-one-answer)
                           minus-one-answer))
                 p)))
       "\n\n"))
    (flush-output-port err)))

(test-equal (string-append "the loaded libcurl's version, " version-text
                           ", has exactly one row in minus-one-rows, what MAX_TOTAL_CONNECTIONS set to -1 answers")
  (list version)
  (map car version-rows))

(let ((wanted (if (= (length version-rows) 1) (cadr (car version-rows)) (list 'no-row version))))
  (test-equal (string-append "MAX_TOTAL_CONNECTIONS set to -1 through curl-multi-setopt-long answers "
                             (if (integer? wanted) (string-append (number->string wanted) ", ") "")
                             "as libcurl " version-text "'s row says"
                             (if (integer? wanted) "" ", which it lacks")
                             ", and its handle is freed")
    (list 'setopt wanted 'cleanup curlm-ok)
    minus-one-answer))

(test-equal "MAX_TOTAL_CONNECTIONS set to 2^40 through curl-multi-setopt-long answers CURLM_OK on every libcurl, and its handle is freed"
  (list 'setopt curlm-ok 'cleanup curlm-ok)
  (multi-answer (expt 2 40)))

;; --- freeing what it made --------------------------------------------------------------------

(curl-easy-cleanup easy)
(foreign-free slot)

(test-end "variadic")

(exit (suite-exit-status runner))
