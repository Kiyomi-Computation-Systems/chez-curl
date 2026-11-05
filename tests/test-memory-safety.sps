#!r6rs
;;; The suite for chez-curl's memory foundations (M2 plan, sections 3.2 to
;;; 3.4, and 4.2 and 4.3):
;;;
;;;   counters     (curl private counters): a count per kind of native
;;;                object, behind one mutex, with no reset. A count-down
;;;                below zero is a double free, and raises
;;;   blocks       (curl private memory): counted foreign blocks, and a
;;;                table of the live ones, so freeing any other address
;;;                raises before free runs
;;;   copies       (curl private native)'s copy-foreign->bytevector! and
;;;                copy-bytevector->foreign!, the one checked wrapper for
;;;                every copy between a bytevector and foreign memory
;;;                (ADR-0001, amended 2026-10-16). Valgrind cannot see an
;;;                overrun into a bytevector, so each bound is held here, at
;;;                its edges, in both directions, on both of each copy's
;;;                paths: memcpy into or out of the bytevector itself, at
;;;                offset 0, and through a fresh bytevector, past it, since
;;;                Chez's u8* hands C a bytevector's first byte. memcpy's
;;;                two bindings are held unexported
;;;   C strings    call-with-c-string and c-string->bytevector: UTF-8 and a
;;;                NUL, U+0000 refused; call-with-latin-1-c-string, one byte
;;;                per char and a NUL, U+0000 and every char above U+00FF
;;;                refused (ADR-0001, amended 2026-10-23)
;;;
;;; The foreign side of each copy is read and written here with Chez's own
;;; foreign-ref and foreign-set!, never through the copies under test, and
;;; every answer is compared whole: the bytevector, or the block, with bytes
;;; on each side of the span that the copy must leave alone.
;;;
;;; A test that raises a count on purpose lowers it again under
;;; dynamic-wind, and this suite exits through suite-exit-status, which
;;; fails it if any count is left. Each expected value is one the code under
;;; test cannot produce by failing: SRFI-64 makes #f of a raise in the
;;; actual expression, so none is #f, and each refusal is compared, who and
;;; irritants, against a no-raise sentinel.
;;;
;;; The counters and the blocks never load libcurl, and are imported. The
;;; copies and the C strings live in (curl private native), whose body is
;;; the load, and the load reads curl_version_info's strings through them.
;;; So this suite reaches native through eval, under a guard: a copy broken
;;; so badly that the load fails names the tests that use it, and the
;;; counters' and blocks' tests still run, where an import would kill the
;;; suite, unnamed, before its first line (.plans/traps.md). make
;;; test-memory runs it under Valgrind.
(import (rnrs)
        (rnrs eval)
        (rnrs mutable-strings)
        (srfi :64)
        (only (chezscheme) foreign-ref foreign-set! fork-thread thread-join getenv
              library-exports sleep make-time make-engine)
        (curl-testing)
        (curl private counters)
        (curl private memory)
        (curl private conditions))

;; native-load : (U 'loaded (List 'raised String))
;; Whether (curl private native) loaded: its body runs at this first
;; reference, under a guard.
(define native-load
  (guard (e (#t (list 'raised (describe e))))
    (eval '(loaded-libcurl) (environment '(curl private native)))
    'loaded))

;; native-procedure : Symbol -> Procedure
;; NAME's procedure in (curl private native); when the load failed, or NAME
;; is not exported, a procedure that raises that, with NAME, every time it
;; is called, so each test that calls it fails by name.
(define (native-procedure name)
  (guard (e (#t (lambda args (error name "(curl private native) could not be reached" (describe e)))))
    (eval name (environment '(curl private native)))))

(define copy-foreign->bytevector! (native-procedure 'copy-foreign->bytevector!))
(define copy-bytevector->foreign! (native-procedure 'copy-bytevector->foreign!))
(define call-with-c-string (native-procedure 'call-with-c-string))
(define c-string->bytevector (native-procedure 'c-string->bytevector))
(define call-with-latin-1-c-string (native-procedure 'call-with-latin-1-c-string))

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

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS), (other TEXT) for
;; any other raise, or (no-raise VALUE).
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)))

;; counts-with : (Listof (Pairof Symbol Integer)) -> (Listof (Pairof Symbol Integer))
;; zero-counts, with each kind in CHANGES at its count.
(define (counts-with changes)
  (map (lambda (entry) (cond ((assq (car entry) changes) => (lambda (c) c)) (else entry)))
       zero-counts))

;; with-counts : (Listof Symbol) (-> Any) -> Any
;; THUNK's answer, with one more of each kind in KINDS counted while it runs.
(define (with-counts kinds thunk)
  (dynamic-wind
    (lambda () (for-each count-up! kinds))
    thunk
    (lambda () (for-each count-down! kinds))))

;; --- the foreign side, read and written apart from the copies ------------------------------

;; poke! : Natural (Listof Natural) -> Void
(define (poke! address bytes)
  (let loop ((i 0) (bytes bytes))
    (unless (null? bytes)
      (foreign-set! 'unsigned-8 address i (car bytes))
      (loop (+ i 1) (cdr bytes)))))

;; peek : Natural Natural -> (Listof Natural)
(define (peek address n)
  (let loop ((i (- n 1)) (found '()))
    (if (< i 0) found (loop (- i 1) (cons (foreign-ref 'unsigned-8 address i) found)))))

;; iota-from : Natural Natural -> (Listof Natural)
(define (iota-from start n)
  (if (= n 0) '() (cons start (iota-from (+ start 1) (- n 1)))))

;; make-list-of : Natural Any -> (Listof Any)
(define (make-list-of n x) (if (= n 0) '() (cons x (make-list-of (- n 1) x))))

;; with-block : Natural (Natural -> Any) -> Any
;; THUNK's answer, given a counted block of SIZE bytes, freed after.
(define (with-block size proc)
  (let ((block (foreign-block size)))
    (dynamic-wind
      (lambda () #f)
      (lambda () (proc block))
      (lambda () (free-foreign-block! block)))))

(test-begin "memory-safety")

(test-equal "(curl private native) loads, reached through eval"
  'loaded
  native-load)

;; --- counters --------------------------------------------------------------------------------

;; No reset, and no back door to the table: each library exports exactly
;; these, written out here.
(define (sorted-names names)
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) names))

(test-equal "(curl private counters) exports exactly native-kinds, count-up!, count-down! and native-counts: no reset; (curl private memory) exactly foreign-block and free-foreign-block!"
  (list (sorted-names '(native-kinds count-up! count-down! native-counts))
        (sorted-names '(foreign-block free-foreign-block!)))
  (list (sorted-names (library-exports '(curl private counters)))
        (sorted-names (library-exports '(curl private memory)))))

(test-equal "native-kinds: block, easy, url, slist, curl-string, transfer, multi and share, in that order"
  '(block easy url slist curl-string transfer multi share)
  native-kinds)

(test-equal "native-counts: every kind, in native-kinds' order, each zero at the start"
  zero-counts
  (native-counts))

(test-equal "count-up! raises its kind's count by one, and count-down! lowers it, each kind apart"
  (list (counts-with '((easy . 1))) (counts-with '((easy . 2) (url . 1))) zero-counts)
  (let* ((one (with-counts '(easy) native-counts))
         (two (with-counts '(easy easy url) native-counts)))
    (list one two (native-counts))))

(test-equal "count-up! and count-down! refuse a symbol that is no kind, as an assertion violation, and count nothing"
  (list '(assertion-violation count-up! (blocks))
        '(assertion-violation count-down! (blocks))
        '(assertion-violation count-up! ("block"))
        zero-counts)
  (let* ((a (raised (lambda () (count-up! 'blocks))))
         (b (raised (lambda () (count-down! 'blocks))))
         (c (raised (lambda () (count-up! "block")))))
    (list a b c (native-counts))))

(test-equal "a count-down below zero, a double free, raises an assertion violation and leaves the count at zero"
  (list '(assertion-violation count-down! (slist)) zero-counts
        (counts-with '((slist . 1))) zero-counts)
  (let* ((refused (raised (lambda () (count-down! 'slist))))
         (after (native-counts))
         (up (with-counts '(slist) native-counts)))
    (list refused after up (native-counts))))

;; Every kind, each alone: a counter that lost one kind's index, or raised
;; below zero for some kinds only, passes a test of one or two. Written out
;; here, not read from native-kinds.
(define every-kind '(block easy url slist curl-string transfer multi share))

(for-each
 (lambda (kind)
   (test-equal (string-append "count-up! of " (symbol->string kind)
                              " counts that kind alone, and count-down! takes it back")
     (list (counts-with (list (cons kind 1))) zero-counts)
     (let ((during (with-counts (list kind) native-counts)))
       (list during (native-counts))))
   (test-equal (string-append "count-down! of " (symbol->string kind)
                              " at zero raises, a double free, and leaves every count at zero")
     (list (list 'assertion-violation 'count-down! (list kind)) zero-counts)
     (let ((r (raised (lambda () (count-down! kind)))))
       (list r (native-counts)))))
 every-kind)

;; Several threads count one kind up, all of them, and then down, many times
;; each. Without the mutex, two threads read the same count and each writes
;; it plus one, losing one: the ups fall short, the downs reach zero early
;; and raise, or the count ends above zero.
(define thread-count 8)
(define steps 20000)

(test-equal "the mutex: 8 threads count transfer up 20000 times each, then down as often, with no raise, and the count is 160000 between and zero after"
  (list (make-list-of thread-count 'no-raise) (* thread-count steps)
        (make-list-of thread-count 'no-raise) zero-counts)
  (let* ((run (lambda (step results i)
                (lambda ()
                  (vector-set! results i
                               (guard (e (#t (list 'raised (describe e))))
                                 (let loop ((n 0))
                                   (when (< n steps) (step 'transfer) (loop (+ n 1))))
                                 'no-raise)))))
         ;; Each thread writes its own slot; thread-join answers nothing.
         (join-all (lambda (step)
                     (let* ((results (make-vector thread-count 'never-ran))
                            (threads (map (lambda (i) (fork-thread (run step results i)))
                                          (iota-from 0 thread-count))))
                       (for-each thread-join threads)
                       (vector->list results))))
         (ups (join-all count-up!))
         (between (cdr (assq 'transfer (native-counts))))
         (downs (join-all count-down!)))
    (list ups between downs (native-counts))))

;; --- blocks ----------------------------------------------------------------------------------

(test-equal "foreign-block: an address, counted as a block while it lives; free-foreign-block! frees it, and the count is zero after"
  (list 'address (counts-with '((block . 1))) zero-counts)
  (let* ((block (foreign-block 16))
         (inside (native-counts)))
    (free-foreign-block! block)
    (list (if (and (integer? block) (exact? block) (> block 0)) 'address block)
          inside (native-counts))))

(test-equal "a block is writable over its whole size"
  (iota-from 1 16)
  (with-block 16 (lambda (block) (poke! block (iota-from 1 16)) (peek block 16))))

(test-equal "foreign-block refuses a size that is no positive exact integer: 0, -1, 1.5, 8.0 and \"8\", counting nothing"
  (list '(assertion-violation foreign-block (0)) '(assertion-violation foreign-block (-1))
        '(assertion-violation foreign-block (1.5)) '(assertion-violation foreign-block (8.0))
        '(assertion-violation foreign-block ("8")) zero-counts)
  (let* ((a (raised (lambda () (foreign-block 0))))
         (b (raised (lambda () (foreign-block -1))))
         (c (raised (lambda () (foreign-block 1.5))))
         (d (raised (lambda () (foreign-block 8.0))))
         (e (raised (lambda () (foreign-block "8")))))
    (list a b c d e (native-counts))))

;; The live table holds every block, not the last one alone: two live at
;; once, each freed, in the order they were made, then a third after.
(test-equal "two blocks live at once are both counted, and each frees, the first made first; a block of 1 byte is one too"
  (list (counts-with '((block . 2))) (counts-with '((block . 1))) zero-counts
        (counts-with '((block . 1))) zero-counts)
  (let* ((first (foreign-block 8))
         (second (foreign-block 8))
         (both (native-counts))
         (one-left (begin (free-foreign-block! first) (native-counts)))
         (none (begin (free-foreign-block! second) (native-counts)))
         (tiny (foreign-block 1))
         (tiny-live (native-counts)))
    (free-foreign-block! tiny)
    (list both one-left none tiny-live (native-counts))))

(test-equal "free-foreign-block! refuses what is no address at all, and counts nothing"
  (list '(assertion-violation free-foreign-block! (x)) zero-counts)
  (let ((r (raised (lambda () (free-foreign-block! 'x)))))
    (list r (native-counts))))

;; A dead address: freed already, or never one of memory's. Freeing either
;; would make glibc abort the process, or worse, so the refusal must come
;; before free runs. A child Chez does it, so that free running anyway
;; fails this test by name, not the whole suite with SIGABRT.
(define dead-address-program
  (string-append
   "(import (rnrs) (curl private memory) (curl private counters))\n"
   "(define block (foreign-block 16))\n"
   "(free-foreign-block! block)\n"
   "(define (try thunk)\n"
   "  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))\n"
   "             (list (condition-who e)\n"
   "                   (if (equal? (condition-irritants e) (list block)) 'that-block (condition-irritants e)))))\n"
   "    (thunk)\n"
   "    'no-raise))\n"
   "(let* ((again (try (lambda () (free-foreign-block! block))))\n"
   "       (never (try (lambda () (free-foreign-block! 4096)))))\n"
   "  (write (list again never (native-counts)))\n"
   "  (newline))\n"))

(test-equal "free-foreign-block! refuses a dead address, freed already or never allocated, before free runs: in a child Chez, which goes on to print"
  (list 0
        "((free-foreign-block! that-block) (free-foreign-block! (4096)) ((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)))\n"
        "")
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((program (string-append dir "/dead-address.sps")))
         (call-with-port (open-file-output-port program (file-options) (buffer-mode block)
                                                (make-transcoder (utf-8-codec)))
           (lambda (p) (put-string p dead-address-program)))
         (capture-command (list (getenv "CHEZ") "--libdirs" "src:tests:build/scheme-libs"
                                "--program" program)))))))

;; --- the checked copies ------------------------------------------------------------------------

(define ee #xEE)

;; into-bytevector : Natural Natural Natural Natural -> (List Any (Listof Natural))
;; Copies N bytes from a 16-byte block holding 1 to 16, at FROM, into a
;; LENGTH-byte bytevector of #xEE at OFFSET: what the copy answered or
;; raised, then the whole bytevector.
(define (into-bytevector from length offset n)
  (with-block 16
    (lambda (block)
      (poke! block (iota-from 1 16))
      (let* ((bv (make-bytevector length ee))
             (r (raised (lambda () (copy-foreign->bytevector! (+ block from) bv offset n) 'copied))))
        (list r (bytevector->u8-list bv))))))

;; into-foreign : Natural Natural Natural Natural -> (List Any (Listof Natural))
;; Copies N bytes of a LENGTH-byte bytevector holding 101, 102, ..., from
;; OFFSET, into a 16-byte block of #xAA at TO: what the copy answered or
;; raised, then the whole block.
(define (into-foreign to length offset n)
  (with-block 16
    (lambda (block)
      (poke! block (make-list-of 16 #xAA))
      (let* ((bv (u8-list->bytevector (iota-from 101 length)))
             (r (raised (lambda () (copy-bytevector->foreign! bv offset (+ block to) n) 'copied))))
        (list r (peek block 16))))))

(define copied '(no-raise copied))

;; foreign -> bytevector

(test-equal "copy-foreign->bytevector!, offset 0: memcpy into the bytevector itself; the bytes after the span untouched"
  (list copied (list 3 4 5 6 ee ee ee ee ee ee))
  (into-bytevector 2 10 0 4))

(test-equal "copy-foreign->bytevector!, offset past 0: through a bytevector of its own; the bytes on each side of the span untouched"
  (list copied (list ee ee ee 3 4 5 6 7 ee ee))
  (into-bytevector 2 10 3 5))

(test-equal "copy-foreign->bytevector!: offset 0 and N the length, the whole bytevector, passes"
  (list copied (iota-from 1 6))
  (into-bytevector 0 6 0 6))

(test-equal "copy-foreign->bytevector!: offset + N the length, past 0, passes"
  (list copied (list ee ee 1 2 3 4))
  (into-bytevector 0 6 2 4))

(test-equal "copy-foreign->bytevector!: offset 0 and N one more than the length is refused before C, and the bytevector is untouched"
  (list '(assertion-violation copy-foreign->bytevector! (0 7 6)) (make-list-of 6 ee))
  (into-bytevector 0 6 0 7))

(test-equal "copy-foreign->bytevector!: offset + N one more than the length, past 0, is refused before C, and the bytevector is untouched"
  (list '(assertion-violation copy-foreign->bytevector! (2 5 6)) (make-list-of 6 ee))
  (into-bytevector 0 6 2 5))

(test-equal "copy-foreign->bytevector!: N = 0 at the length passes and copies nothing, and so it does into an empty bytevector"
  (list (list copied (make-list-of 6 ee)) (list copied '()))
  (list (into-bytevector 0 6 6 0) (into-bytevector 0 0 0 0)))

(test-equal "copy-foreign->bytevector!: an offset at the length and N = 1 is refused"
  (list '(assertion-violation copy-foreign->bytevector! (6 1 6)) (make-list-of 6 ee))
  (into-bytevector 0 6 6 1))

;; bytevector -> foreign

(test-equal "copy-bytevector->foreign!, offset 0: memcpy out of the bytevector itself; the block's bytes after the span untouched"
  (list copied (append (list #xAA #xAA 101 102 103 104) (make-list-of 10 #xAA)))
  (into-foreign 2 10 0 4))

(test-equal "copy-bytevector->foreign!, offset past 0: through a bytevector of its own; the block's bytes on each side of the span untouched"
  (list copied (append (list #xAA #xAA 104 105 106 107 108) (make-list-of 9 #xAA)))
  (into-foreign 2 10 3 5))

(test-equal "copy-bytevector->foreign!: offset 0 and N the length passes"
  (list copied (append (iota-from 101 6) (make-list-of 10 #xAA)))
  (into-foreign 0 6 0 6))

(test-equal "copy-bytevector->foreign!: offset + N the length, past 0, passes"
  (list copied (append (list 103 104 105 106) (make-list-of 12 #xAA)))
  (into-foreign 0 6 2 4))

(test-equal "copy-bytevector->foreign!: offset 0 and N one more than the length is refused before C, and the block is untouched"
  (list '(assertion-violation copy-bytevector->foreign! (0 7 6)) (make-list-of 16 #xAA))
  (into-foreign 0 6 0 7))

(test-equal "copy-bytevector->foreign!: offset + N one more than the length, past 0, is refused before C, and the block is untouched"
  (list '(assertion-violation copy-bytevector->foreign! (2 5 6)) (make-list-of 16 #xAA))
  (into-foreign 0 6 2 5))

(test-equal "copy-bytevector->foreign!: N = 0 at the length passes and copies nothing, and so it does from an empty bytevector"
  (list (list copied (make-list-of 16 #xAA)) (list copied (make-list-of 16 #xAA)))
  (list (into-foreign 0 6 6 0) (into-foreign 0 0 0 0)))

;; each argument's type, both ways

;; refusals : Symbol -> (Listof Any)
;; What each bad argument makes the copy WHO raise, in the order below.
(define (refusals who)
  (with-block 8
    (lambda (block)
      (let ((bv (make-bytevector 4 0)))
        (map (lambda (args)
               (raised (lambda ()
                         (if (eq? who 'copy-foreign->bytevector!)
                             (apply copy-foreign->bytevector! args)
                             (copy-bytevector->foreign! (cadr args) (caddr args)
                                                        (car args) (cadddr args)))
                         'copied)))
             ;; (ADDRESS BYTEVECTOR OFFSET N)
             (list (list 0 bv 0 1)
                   (list -8 bv 0 1)
                   (list 8.0 bv 0 1)
                   (list "8" bv 0 1)
                   (list block "four" 0 1)
                   (list block bv -1 1)
                   (list block bv 1.0 1)
                   (list block bv 'one 1)
                   (list block bv 0 -1)
                   (list block bv 0 2.0)
                   (list block bv 0 'two)))))))

(for-each
 (lambda (who)
   (test-equal (string-append (symbol->string who)
                              ": an address that is 0, negative or inexact, or no number; a bytevector that is none; an offset or N negative, inexact or no number: each refused, naming it")
     (map (lambda (irritants) (list 'assertion-violation who irritants))
          '((0) (-8) (8.0) ("8") ("four") (-1) (1.0) (one) (-1) (2.0) (two)))
     (refusals who)))
 '(copy-foreign->bytevector! copy-bytevector->foreign!))

;; memcpy's two bindings are the copies' alone. Read native.sls as data:
;; the names bound to memcpy, none exported, plain or renamed, and none
;; referenced but in their own definitions and the copies'. And eval of
;; each in the library's environment raises, so neither is reachable.
(define native-source "src/curl/private/native.sls")

;; occurs? : Symbol Any -> Boolean
(define (occurs? name x)
  (cond ((eq? x name) #t)
        ((pair? x) (or (occurs? name (car x)) (occurs? name (cdr x))))
        ((vector? x) (occurs? name (vector->list x)))
        (else #f)))

;; holds-string? : String Any -> Boolean
(define (holds-string? s x)
  (cond ((and (string? x) (string=? x s)) #t)
        ((pair? x) (or (holds-string? s (car x)) (holds-string? s (cdr x))))
        (else #f)))

;; memcpy-reading : (U (List Natural (Listof Symbol) (Listof Any)) (List 'unreadable String))
;; How many names native.sls binds to memcpy, which of them it exports, and
;; each body form, but their own definitions and the copies', that names
;; one.
(define memcpy-reading
  (guard (e (#t (list 'unreadable (describe e))))
    (let* ((form (call-with-port (open-file-input-port native-source (file-options)
                                                       (buffer-mode block)
                                                       (make-transcoder (utf-8-codec)))
                   read))
           (exports (cdr (caddr form)))
           (body (cddddr form))
           (raw-defines (filter (lambda (f)
                                  (and (pair? f) (eq? (car f) 'define) (pair? (cdr f))
                                       (symbol? (cadr f)) (holds-string? "memcpy" (cddr f))))
                                body))
           (names (map cadr raw-defines))
           (exported (filter (lambda (name)
                               (exists (lambda (spec)
                                         (or (eq? spec name)
                                             (and (pair? spec) (eq? (car spec) 'rename)
                                                  (exists (lambda (pair) (and (pair? pair) (eq? (car pair) name)))
                                                          (cdr spec)))))
                                       exports))
                             names))
           (copies '(copy-foreign->bytevector! copy-bytevector->foreign!))
           (elsewhere (filter (lambda (f)
                                (and (not (memq f raw-defines))
                                     (not (and (pair? f) (eq? (car f) 'define) (pair? (cdr f))
                                               (pair? (cadr f)) (memq (car (cadr f)) copies)))
                                     (exists (lambda (name) (occurs? name f)) names)))
                              body)))
      (list (length names) exported elsewhere names))))

(test-equal "native.sls binds memcpy twice, exports neither binding, plain or renamed, and names them only in the two checked copies"
  '(2 () ())
  (if (eq? (car memcpy-reading) 'unreadable)
      memcpy-reading
      (list (car memcpy-reading) (cadr memcpy-reading) (caddr memcpy-reading))))

(test-equal "neither memcpy binding is reachable from outside native: eval of each name in its environment raises, where a checked copy's name, the control, is bound"
  '(bound unbound unbound)
  (if (eq? (car memcpy-reading) 'unreadable)
      memcpy-reading
      (map (lambda (name)
             (guard (e (#t 'unbound))
               (if (procedure? (eval name (environment '(curl private native))))
                   'bound
                   (list 'not-a-procedure name))))
           (cons 'copy-foreign->bytevector! (cadddr memcpy-reading)))))

;; --- C strings ----------------------------------------------------------------------------------

;; c-bytes : String -> Any
;; What call-with-c-string hands C for STRING, read with foreign-ref up to
;; and with its NUL; c-string->bytevector's answer for the same address;
;; and the counts while PROC runs. Or what was raised.
(define (c-bytes string)
  (guard (e ((curl-embedded-nul? e) (list 'embedded-nul (curl-embedded-nul-string e)))
            (#t (list 'other (describe e))))
    (call-with-c-string string
      (lambda (address)
        (let loop ((i 0) (found '()))
          (let ((b (foreign-ref 'unsigned-8 address i)))
            (if (= b 0)
                (list (reverse (cons 0 found))
                      (bytevector->u8-list (c-string->bytevector address))
                      (native-counts))
                (loop (+ i 1) (cons b found)))))))))

(test-equal "call-with-c-string hands C UTF-8 and a NUL: é is 195 169, λ is 206 187, € is 226 130 172, U+1F600 is 240 159 152 128; c-string->bytevector reads them back without the NUL; one block is counted while PROC runs"
  (list (list '(195 169 0) '(195 169) (counts-with '((block . 1))))
        (list '(206 187 0) '(206 187) (counts-with '((block . 1))))
        (list '(226 130 172 0) '(226 130 172) (counts-with '((block . 1))))
        (list '(240 159 152 128 0) '(240 159 152 128) (counts-with '((block . 1))))
        (list '(0) '() (counts-with '((block . 1))))
        zero-counts)
  (let* ((a (c-bytes "é"))
         (b (c-bytes "λ"))
         (e (c-bytes "\x20AC;"))
         (c (c-bytes "\x1F600;"))
         (d (c-bytes "")))
    (list a b e c d (native-counts))))

;; at-raise : (-> Any) -> (List Any (Listof (Pairof Symbol Natural)))
;; What THUNK raised, through HANDLE, and the native counts at the moment of
;; the raise: read by a handler that runs before any dynamic-wind's after
;; thunk, then raises on. The counts after are a separate reading.
(define (at-raise thunk handle)
  (let ((seen 'no-raise))
    (let ((r (guard (e (#t (handle e)))
               (with-exception-handler
                 (lambda (c) (set! seen (native-counts)) (raise c))
                 thunk))))
      (list r seen))))

;; U+0000 at every place a scan can miss: first, in the middle, last, the
;; whole string, and beside characters past ASCII on both sides. "Before
;; anything is allocated" is read at the raise: a refusal made once the
;; block existed shows it there, though the block is freed by the time
;; the raise is caught.
(for-each
 (lambda (string)
   (test-equal (string-append "call-with-c-string refuses " (call-with-string-output-port (lambda (p) (write string p)))
                              " as &curl-embedded-nul, naming it, with nothing allocated at the raise, and PROC not run")
     (list (list (list 'embedded-nul string) zero-counts) 'proc-not-run zero-counts)
     (let* ((ran #f)
            (r (at-raise (lambda () (call-with-c-string string (lambda (address) (set! ran #t) 'ran)))
                         (lambda (e)
                           (if (curl-embedded-nul? e)
                               (list 'embedded-nul (curl-embedded-nul-string e))
                               (list 'other (describe e)))))))
       (list r (if ran 'proc-ran 'proc-not-run) (native-counts)))))
 '("\x0;abc" "a\x0;b" "abc\x0;" "\x0;" "\xE9;\x0;\x3BB;" "\x1F600;\x0;" "\x20AC;\x0;"))

(test-equal "&curl-embedded-nul is a &curl-error"
  '(#t #t)
  (let ((c (make-curl-embedded-nul "a\x0;b")))
    (list (curl-error? c) (error? c))))

(test-equal "the round trip: a string through call-with-c-string and c-string->bytevector comes back the same"
  "http://example.com/λ/é?q=\x1F600;"
  (call-with-c-string "http://example.com/λ/é?q=\x1F600;"
    (lambda (address) (utf8->string (c-string->bytevector address)))))

;; The NUL is written, not found: the block call-with-c-string makes for a
;; 39-byte string is 40 bytes, and malloc's last one freed, of that size,
;; was filled with #xFF first, so a copy that left the NUL out leaves #xFF
;; where it belongs. Valgrind, which never reuses a block at once, calls a
;; NUL left unwritten an uninitialised read.
(test-equal "call-with-c-string writes the NUL itself: a fresh block that held #xFF reads the string's bytes, then 0"
  (append (bytevector->u8-list (string->utf8 "abcdefghijklmnopqrstuvwxyz0123456789ABC")) '(0))
  (begin
    (with-block 40 (lambda (block) (poke! block (make-list-of 40 #xFF))))
    (call-with-c-string "abcdefghijklmnopqrstuvwxyz0123456789ABC"
      (lambda (address) (peek address 40)))))

(test-equal "c-string->bytevector answers #f for NULL, and calls nothing: compared as the symbol null"
  'null
  (let ((r (c-string->bytevector 0))) (if (eq? r #f) 'null r)))

(test-equal "call-with-c-string: a raise from PROC frees the block, and reaches the caller"
  (list 'proc-raised zero-counts)
  (let ((r (guard (e ((eq? e 'from-proc) 'proc-raised))
             (call-with-c-string "abc" (lambda (address) (raise 'from-proc))))))
    (list r (native-counts))))

(test-equal "call-with-c-string: re-entering PROC through a continuation, once the block is freed, raises, and PROC runs once"
  (list '(assertion-violation call-with-c-string) 1 zero-counts)
  (let ((k #f) (runs 0))
    (let ((r (guard (e ((and (assertion-violation? e) (who-condition? e))
                        (list 'assertion-violation (condition-who e)))
                       (#t (list 'other (describe e))))
               (call-with-c-string "abc"
                 (lambda (address)
                   (call/cc (lambda (c) (set! k c)))
                   (set! runs (+ runs 1))))
               (if (= runs 1) (k #f) (list 'reentered runs)))))
      (list r runs (native-counts)))))

(test-equal "call-with-c-string refuses what is no string, and a PROC that is no procedure"
  (list '(assertion-violation call-with-c-string (abc))
        '(assertion-violation call-with-c-string (not-a-procedure))
        zero-counts)
  (let* ((a (raised (lambda () (call-with-c-string 'abc (lambda (address) address)))))
         (b (raised (lambda () (call-with-c-string "abc" 'not-a-procedure)))))
    (list a b (native-counts))))

;; --- Latin-1 C strings (ADR-0001, amended 2026-10-23) ------------------------------------

;; latin-1-bytes : String -> Any
;; What call-with-latin-1-c-string hands C for STRING, read with foreign-ref
;; up to and with its NUL; c-string->bytevector's answer for the same
;; address; and the counts while PROC runs. Or what was raised.
(define (latin-1-bytes string)
  (guard (e ((curl-embedded-nul? e) (list 'embedded-nul (curl-embedded-nul-string e)))
            ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other (describe e))))
    (call-with-latin-1-c-string string
      (lambda (address)
        (let loop ((i 0) (found '()))
          (let ((b (foreign-ref 'unsigned-8 address i)))
            (if (= b 0)
                (list (reverse (cons 0 found))
                      (bytevector->u8-list (c-string->bytevector address))
                      (native-counts))
                (loop (+ i 1) (cons b found)))))))))

;; every-latin-1 : String
;; Every char from U+0001 to U+00FF, in order: each byte but NUL, where
;; Latin-1 and UTF-8 differ from 0x80 on.
(define every-latin-1
  (list->string (map integer->char (iota-from 1 255))))

(test-equal "call-with-latin-1-c-string hands C one byte per char and a NUL: every char from U+0001 to U+00FF as its own code, é as 233, never UTF-8's 195 169; c-string->bytevector reads them back without the NUL; one block is counted while PROC runs"
  (list (list (append (iota-from 1 255) '(0)) (iota-from 1 255) (counts-with '((block . 1))))
        (list '(233 0) '(233) (counts-with '((block . 1))))
        (list '(97 255 98 0) '(97 255 98) (counts-with '((block . 1))))
        (list '(0) '() (counts-with '((block . 1))))
        zero-counts)
  (let* ((a (latin-1-bytes every-latin-1))
         (b (latin-1-bytes "\xE9;"))
         (c (latin-1-bytes "a\xFF;b"))
         (d (latin-1-bytes "")))
    (list a b c d (native-counts))))

;; U+0000 at every place a scan can miss, beside chars past ASCII.
(for-each
 (lambda (string)
   (test-equal (string-append "call-with-latin-1-c-string refuses " (call-with-string-output-port (lambda (p) (write string p)))
                              " as &curl-embedded-nul, naming it, with nothing allocated at the raise, and PROC not run")
     (list (list (list 'embedded-nul string) zero-counts) 'proc-not-run zero-counts)
     (let* ((ran #f)
            (r (at-raise (lambda () (call-with-latin-1-c-string string (lambda (address) (set! ran #t) 'ran)))
                         (lambda (e)
                           (if (curl-embedded-nul? e)
                               (list 'embedded-nul (curl-embedded-nul-string e))
                               (list 'other (describe e)))))))
       (list r (if ran 'proc-ran 'proc-not-run) (native-counts)))))
 '("\x0;abc" "a\x0;b" "abc\x0;" "\x0;" "\xE9;\x0;\xFF;"))

;; A char above U+00FF at every place, U+0100, the first, among them; and
;; which refusal comes first when the string holds both: its first
;; offending char's.
(for-each
 (lambda (string)
   (test-equal (string-append "call-with-latin-1-c-string refuses " (call-with-string-output-port (lambda (p) (write string p)))
                              ", a char above U+00FF, with an assertion violation naming the string, nothing allocated at the raise, and PROC not run")
     (list (list (list 'assertion-violation 'call-with-latin-1-c-string (list string)) zero-counts)
           'proc-not-run zero-counts)
     (let* ((ran #f)
            (r (at-raise (lambda () (call-with-latin-1-c-string string (lambda (address) (set! ran #t) 'ran)))
                         (lambda (e)
                           (if (and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
                               (list 'assertion-violation (condition-who e) (condition-irritants e))
                               (list 'other (describe e)))))))
       (list r (if ran 'proc-ran 'proc-not-run) (native-counts)))))
 '("\x100;abc" "a\x100;b" "abc\x100;" "\x100;" "\xFF;\x20AC;" "\x1F600;" "\x100;\x0;"))

(test-equal "call-with-latin-1-c-string: a NUL before a char above U+00FF is refused as the NUL"
  (list 'embedded-nul "a\x0;\x100;")
  (latin-1-bytes "a\x0;\x100;"))

(test-equal "call-with-latin-1-c-string writes the NUL itself: a fresh block that held #xFF reads the string's bytes, then 0"
  (append (iota-from 160 39) '(0))
  (let ((string (list->string (map integer->char (iota-from 160 39)))))
    (with-block 40 (lambda (block) (poke! block (make-list-of 40 #xFF))))
    (call-with-latin-1-c-string string
      (lambda (address) (peek address 40)))))

(test-equal "call-with-latin-1-c-string: a raise from PROC frees the block, and reaches the caller"
  (list 'proc-raised zero-counts)
  (let ((r (guard (e ((eq? e 'from-proc) 'proc-raised))
             (call-with-latin-1-c-string "abc" (lambda (address) (raise 'from-proc))))))
    (list r (native-counts))))

(test-equal "call-with-latin-1-c-string: re-entering PROC through a continuation, once the block is freed, raises, and PROC runs once"
  (list '(assertion-violation call-with-latin-1-c-string) 1 zero-counts)
  (let ((k #f) (runs 0))
    (let ((r (guard (e ((and (assertion-violation? e) (who-condition? e))
                        (list 'assertion-violation (condition-who e)))
                       (#t (list 'other (describe e))))
               (call-with-latin-1-c-string "abc"
                 (lambda (address)
                   (call/cc (lambda (c) (set! k c)))
                   (set! runs (+ runs 1))))
               (if (= runs 1) (k #f) (list 'reentered runs)))))
      (list r runs (native-counts)))))

(test-equal "call-with-latin-1-c-string refuses what is no string, and a PROC that is no procedure"
  (list '(assertion-violation call-with-latin-1-c-string (abc))
        '(assertion-violation call-with-latin-1-c-string (not-a-procedure))
        zero-counts)
  (let* ((a (raised (lambda () (call-with-latin-1-c-string 'abc (lambda (address) address)))))
         (b (raised (lambda () (call-with-latin-1-c-string "abc" 'not-a-procedure)))))
    (list a b (native-counts))))

;; --- check-then-use: a string another thread changes -------------------------------------
;; Each C string is a copy that is checked, then encoded: the one copy. A
;; check of the caller's string, then an encoding of it, lets a second
;; thread change it between the two, so C could read a NUL that was never
;; refused. Here a thread flips one char between a and U+0000, or a char
;; past Latin-1, as fast as it can, while this one makes C strings of the
;; string: each is refused, or reaches C whole, never cut.

;; yield : -> Unit
;; A sleep of no time: a system call, at which Valgrind, which runs one
;; thread at a time, lets another thread run. Natively the threads run on
;; cores of their own throughout.
(define (yield) (sleep (make-time 'time-duration 0 0)))

;; while-flipping : String Natural Char Char (-> Any) -> Any
;; THUNK's answer, while another thread sets STRING's char at INDEX to A,
;; then B, 100000 times as fast as it can, then yields with it B; does so
;; again, then yields with it A; and over again. It is stopped, and joined,
;; after. Natively it spins most of the time; under Valgrind it yields once
;; in each state, so both reach THUNK's calls, and holds no thread up long.
(define (while-flipping string index a b thunk)
  (let* ((stop #f)
         (flip (lambda ()
                 (let loop ((i 0))
                   (when (< i 100000)
                     (string-set! string index a)
                     (string-set! string index b)
                     (loop (+ i 1))))))
         (flipper (fork-thread
                   (lambda ()
                     (let loop ()
                       (unless stop
                         (flip)
                         (yield)
                         (flip)
                         (string-set! string index a)
                         (yield)
                         (loop)))))))
    (dynamic-wind
      (lambda () #f)
      thunk
      (lambda () (set! stop #t) (thread-join flipper)))))

;; c-length : Natural -> Natural
;; The C string at ADDRESS's length, read with foreign-ref.
(define (c-length address)
  (let loop ((i 0)) (if (= (foreign-ref 'unsigned-8 address i) 0) i (loop (+ i 1)))))

;; race-outcomes : Procedure Char -> (List (Listof Any) (Listof Symbol))
;; 2000 calls of MAKE on "xax", its a flipped with BAD, with a yield before
;; every tenth: the outcomes that are neither a refusal nor the whole
;; string, and which of refused and whole were seen. Natively each call
;; races the flipper on another core. Under Valgrind, which runs one thread
;; at a time, the flipper runs only at the yields, which leave the string in
;; either state, and the calls never race it.
(define (race-outcomes make bad)
  (let ((s (string #\x #\a #\x)))
    (while-flipping s 1 bad #\a
      (lambda ()
        (let loop ((i 0) (odd '()) (seen '()))
          (if (= i 2000)
              (list (reverse odd) (filter (lambda (k) (memq k seen)) '(refused whole)))
              (let ((o (begin
                         (when (= (mod i 10) 0) (yield))
                         (guard (e ((curl-embedded-nul? e) 'refused)
                                 ((and (assertion-violation? e) (who-condition? e)
                                       (eq? (condition-who e) 'call-with-latin-1-c-string))
                                  'refused)
                                 (#t (list 'raised (describe e))))
                         (make s (lambda (address)
                                   (let ((n (c-length address)))
                                     (if (= n 3) 'whole (list 'cut n)))))))))
                (loop (+ i 1)
                      (if (memq o '(refused whole)) odd (cons o odd))
                      (if (memq o seen) seen (cons o seen))))))))))

(for-each
 (lambda (row)
   (test-equal (string-append (car row) ", while another thread flips a char of its string to "
                              (cadddr row) ": 2000 calls each refused or whole, none cut, both seen, and nothing left")
     (list '() '(refused whole) zero-counts)
     (let ((r (race-outcomes (cadr row) (caddr row))))
       (append r (list (native-counts))))))
 (list (list "call-with-c-string" call-with-c-string #\nul "U+0000")
       (list "call-with-latin-1-c-string" call-with-latin-1-c-string #\nul "U+0000")
       (list "call-with-latin-1-c-string" call-with-latin-1-c-string (integer->char #x100) "U+0100")))


;; --- asynchronous escapes: an engine's fuel running out anywhere ------------------------
;; An engine that runs out of fuel leaves through a continuation at its next
;; safe point, running the after thunks; an abandoned one is never resumed.
;; Each sweep runs THUNK in a fresh engine with fuel 1, 1+STEP, 1+2 STEP and
;; so on, abandoning each that runs out, until one completes: a native
;; object made but not yet recorded where its free finds it, at any of those
;; points, would stay made, and counted or not.

;; engine-sweep : (-> Any) Natural -> (List Symbol Natural)
;; (completed EXPIRED), EXPIRED the engines that ran out first; or
;; (never-completed EXPIRED) past 100000 fuel.
(define (engine-sweep thunk step)
  (let loop ((fuel 1) (expired 0))
    (cond ((> fuel 100000) (list 'never-completed expired))
          (((make-engine thunk) fuel (lambda (ticks v) #t) (lambda (e) #f)) (list 'completed expired))
          (else (loop (+ fuel step) (+ expired 1))))))

;; swept : (List Symbol Natural) -> Any
;; completed-after-expiries when the sweep completed after more than ten
;; engines ran out, its positive evidence; else the sweep itself.
(define (swept result)
  (if (and (eq? (car result) 'completed) (> (cadr result) 10)) 'completed-after-expiries result))

(for-each
 (lambda (row)
   (test-equal (string-append (car row) " in an engine that runs out at every tick, each abandoned, until one completes: it completes, and no native object is left")
     (list 'completed-after-expiries zero-counts)
     (list (swept (engine-sweep (cadr row) 1)) (native-counts))))
 (list (list "call-with-c-string" (lambda () (call-with-c-string "abc" (lambda (address) address))))
       (list "call-with-latin-1-c-string" (lambda () (call-with-latin-1-c-string "abc" (lambda (address) address))))))

;; --- a mutex held across an asynchronous escape ----------------------------------------
;; Chez's with-mutex is a dynamic-wind whose before thunk takes the mutex,
;; so an engine that runs out between the take and the wind leaves it
;; held, with no after thunk to release it, and every other thread then
;; blocks on it. The sweeps above ran out at every tick of a block made
;; and freed, under the blocks' mutex and the counts'; this one runs out at
;; every tick of native-counts, under the counts'.

;; other-thread-can : (-> Any) -> Symbol
;; other-thread-ran when THUNK, run in a fresh thread, returns within 10 s;
;; other-thread-raised when it raises; other-thread-blocked when it does
;; neither. A mutex this thread left held blocks another thread, never this
;; one: Chez's mutexes are recursive. A blocked thread is left blocked.
(define (other-thread-can thunk)
  (let ((done #f))
    (fork-thread (lambda () (guard (e (#t (set! done 'raised))) (thunk) (set! done 'ran))))
    (let loop ((i 0))
      (cond ((eq? done 'ran) 'other-thread-ran)
            ((eq? done 'raised) 'other-thread-raised)
            ((= i 1000) 'other-thread-blocked)
            (else (sleep (make-time 'time-duration 10000000 0)) (loop (+ i 1)))))))

(test-equal "an engine that runs out at every tick of native-counts, each abandoned, until one completes: it completes, and after every sweep another thread reads the counts, and makes and frees a block: no mutex is left held"
  '((completed expired-first) other-thread-ran)
  (let ((r (engine-sweep native-counts 1)))
    (list (if (and (eq? (car r) 'completed) (> (cadr r) 0)) '(completed expired-first) r)
          (other-thread-can (lambda () (native-counts) (free-foreign-block! (foreign-block 1)))))))

;; --- the mutexes, read from the libraries as data ---------------------------------------
;; counters.sls and memory.sls each hold their mutex through locked, inside
;; a critical section, so no engine's expiry, nor timer, falls between the
;; take and its dynamic-wind, nor abandons an update half made. The limit:
;; this holds a with-mutex added by accident, not a rewrite made to pass,
;; such as a mutex reached under another name.

;; library-form : String -> Any
;; The library form in the file at PATH, or what went wrong.
(define (library-form path)
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      read)))

;; definition-of : Any Symbol -> Any
;; The (define (NAME ...) ...) form in LIBRARY's body, or (no-definition NAME).
(define (definition-of library name)
  (or (and (list? library) (> (length library) 4)
           (find (lambda (f) (and (pair? f) (eq? (car f) 'define) (pair? (cdr f))
                                  (pair? (cadr f)) (eq? (car (cadr f)) name)))
                 (cddddr library)))
      (list 'no-definition name)))

;; symbol-count : Symbol Any -> Natural
(define (symbol-count name x)
  (cond ((eq? x name) 1)
        ((pair? x) (+ (symbol-count name (car x)) (symbol-count name (cdr x))))
        (else 0)))

(for-each
 (lambda (path)
   (let ((library (library-form path)))
     (test-equal (string-append "locked, read from " path ", holds its mutex inside a critical section; with-mutex stands twice there, in its import and in locked, and mutex-acquire and mutex-release nowhere")
       '((define (locked lock thunk) (critical-section (with-mutex lock (thunk)))) 2 0 0)
       (list (definition-of library 'locked)
             (symbol-count 'with-mutex library)
             (symbol-count 'mutex-acquire library)
             (symbol-count 'mutex-release library)))))
 '("src/curl/private/counters.sls" "src/curl/private/memory.sls"))

(test-equal "the reader: a definition found by name, a symbol counted at any depth, and a missing definition named"
  '((define (b x) (f x x)) 4 (no-definition c))
  (let ((library '(library (x) (export) (import (only (y) f)) (define (a) 1) (define (b x) (f x x)))))
    (list (definition-of library 'b) (symbol-count 'x library) (definition-of library 'c))))

(test-end "memory-safety")

(exit (suite-exit-status runner))
