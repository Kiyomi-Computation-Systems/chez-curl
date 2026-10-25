;;; Spike E1: transfers driven through the multi interface on an engine
;;; thread, with a write callable, while another thread collects about once
;;; a millisecond. ADR-0013's decision 5 asks which call each callback fires
;;; from, and whether one callable may serve a __collect_safe call and a
;;; plain one.
;;;
;;;   deliver.sps CALLABLE PERFORM RUNS
;;;
;;; CALLABLE and PERFORM are each safe (__collect_safe) or plain: how the
;;; write callable and curl_multi_perform are declared. curl_multi_poll is
;;; __collect_safe throughout. Each run makes a fresh engine thread with four
;;; transfers on one multi handle, against the test origin: two drips, of
;;; 200 bytes 5 ms apart and of 150 bytes 7 ms apart, a 200 and an echo.
;;;
;;; Prints, for each run: each transfer's CURLcode, status and byte count;
;;; how many callbacks fired inside curl_multi_perform, inside
;;; curl_multi_poll and elsewhere; how many ran on a thread other than the
;;; engine's; how many collections the other thread made; and the longest
;;; single call of each multi entry point, in ms.
(import (chezscheme) (curl private native) (curl private libcurl-info) (curl-testing))

(define args (command-line-arguments))
(define callable-mode (string->symbol (car args)))
(define perform-mode (string->symbol (cadr args)))
(define runs (string->number (caddr args)))
(define info (loaded-libcurl))

(define easy-init (foreign-procedure "curl_easy_init" () uptr))
(define easy-cleanup (foreign-procedure "curl_easy_cleanup" (uptr) void))
(define multi-init (foreign-procedure "curl_multi_init" () uptr))
(define multi-cleanup (foreign-procedure "curl_multi_cleanup" (uptr) int))
(define multi-add (foreign-procedure "curl_multi_add_handle" (uptr uptr) int))
(define multi-remove (foreign-procedure "curl_multi_remove_handle" (uptr uptr) int))
(define perform-plain (foreign-procedure "curl_multi_perform" (uptr uptr) int))
(define perform-safe (foreign-procedure __collect_safe "curl_multi_perform" (uptr uptr) int))
(define multi-perform (if (eq? perform-mode 'safe) perform-safe perform-plain))
(define poll
  (foreign-procedure __collect_safe "curl_multi_poll" (uptr uptr unsigned-int int uptr) int))
(define info-read (foreign-procedure "curl_multi_info_read" (uptr uptr) uptr))
(define memcpy-into (foreign-procedure "memcpy" (u8* uptr size_t) uptr))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6))))

;; The longest single call of each entry point, in ms.
(define longest (make-eq-hashtable))
(define-syntax timed
  (syntax-rules ()
    ((_ name e)
     (let* ((t0 (now-ms)) (v e))
       (hashtable-update! longest 'name (lambda (old) (max old (- (now-ms) t0))) 0)
       v))))

(define where 'other)                   ; set by the engine thread around its calls
(define engine-thread #f)
(define counts (make-eq-hashtable))
(define off-thread 0)
(define bodies (make-eqv-hashtable))
(define (on-write data size nmemb key)
  (let* ((n (* size nmemb)) (bv (make-bytevector n)))
    (hashtable-update! counts where (lambda (c) (+ c 1)) 0)
    (unless (eqv? (get-thread-id) engine-thread) (set! off-thread (+ off-thread 1)))
    (memcpy-into bv data n)
    (hashtable-update! bodies key (lambda (l) (cons bv l)) '())
    n))
(define write-safe (foreign-callable __collect_safe on-write (uptr size_t size_t uptr) size_t))
(define write-plain (foreign-callable on-write (uptr size_t size_t uptr) size_t))
(define write-callable (if (eq? callable-mode 'safe) write-safe write-plain))
(lock-object write-callable)
(define write-entry (foreign-callable-entry-point write-callable))

(define (option-id name) (car (curl-easy-option name)))
;; c-copy : String -> Natural
;; S as a NUL-terminated copy in foreign memory, which the caller frees.
(define (c-copy s)
  (let* ((bv (string->utf8 s)) (n (bytevector-length bv)) (p (foreign-alloc (+ n 1))))
    (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i)))
    (foreign-set! 'unsigned-8 p n 0)
    p))
(define (set-string! h name s)
  (let* ((p (c-copy s)) (code (curl-easy-setopt-pointer h (option-id name) p)))
    (foreign-free p)
    (unless (zero? code) (error 'set-string! "setopt failed" name code))))
(define (set-long! h name v)
  (let ((code (curl-easy-setopt-long h (option-id name) v)))
    (unless (zero? code) (error 'set-long! "setopt failed" name code))))

(define curlinfo-response-code #x200002)

;; run-engine : (Listof String) -> (Listof (List Key Code Status))
;; On a fresh engine thread: one easy handle per URL, all on one multi
;; handle, driven by perform and poll until each is done, then taken apart.
(define (run-engine urls)
  (let ((mx (make-mutex)) (cv (make-condition)) (result #f))
    (fork-thread
     (lambda ()
       (set! engine-thread (get-thread-id))
       (let* ((m (timed multi_init (multi-init)))
              (running (foreign-alloc 8))
              (numfds (foreign-alloc 8))
              (handles (map (lambda (url key)
                              (let ((h (easy-init)))
                                (set-string! h "URL" url)
                                (set-long! h "NOSIGNAL" 1)
                                (set-long! h "TIMEOUT_MS" 20000)
                                (curl-easy-setopt-pointer h (option-id "WRITEFUNCTION") write-entry)
                                (curl-easy-setopt-pointer h (option-id "WRITEDATA") key)
                                (timed multi_add_handle (multi-add m h))
                                (cons h key)))
                            urls (iota (length urls)))))
         (let loop ((done '()))
           (set! where 'perform)
           (timed multi_perform (multi-perform m running))
           (set! where 'other)
           (let drain ((done done))
             (let ((msg (timed multi_info_read (info-read m numfds))))
               (if (zero? msg)
                   (if (< (length done) (length urls))
                       (begin
                         (set! where 'poll)
                         (timed multi_poll (poll m 0 0 1000 numfds))
                         (set! where 'other)
                         (loop done))
                       (begin
                         (for-each (lambda (hk)
                                     (timed multi_remove_handle (multi-remove m (car hk)))
                                     (timed easy_cleanup (easy-cleanup (car hk))))
                                   handles)
                         (timed multi_cleanup (multi-cleanup m))
                         (foreign-free running)
                         (foreign-free numfds)
                         (with-mutex mx (set! result done) (condition-broadcast cv))))
                   (let* ((h (foreign-ref 'uptr msg 8))
                          (code (foreign-ref 'int msg 16))
                          (key (cdr (assv h handles))))
                     (drain (cons (list key code
                                        (let-values (((c v) (curl-easy-getinfo-long
                                                             h curlinfo-response-code)))
                                          v))
                                  done))))))))))
    (with-mutex mx (let wait () (unless result (condition-wait cv mx) (wait))))
    (list-sort (lambda (a b) (< (car a) (car b))) result)))

(define (base origin face)
  (let ((f (origin-face origin face)))
    (string-append "http://" (car f) ":" (number->string (cdr f)))))

(define (byte-count key)
  (fold-left + 0 (map bytevector-length (hashtable-ref bodies key '()))))

(call-with-origin
 (lambda (origin)
   (do ((r 1 (+ r 1))) ((> r runs))
     (hashtable-clear! counts)
     (hashtable-clear! bodies)
     (hashtable-clear! longest)
     (set! off-thread 0)
     (let ((stop #f) (collections 0) (mx (make-mutex)) (cv (make-condition)) (stopped #f))
       (fork-thread
        (lambda ()
          (let loop ()
            (unless stop
              (make-bytevector 100000 1)
              (collect-rendezvous)
              (set! collections (+ collections 1))
              (sleep (make-time 'time-duration 1000000 0))
              (loop)))
          (with-mutex mx (set! stopped #t) (condition-broadcast cv))))
       (let ((results (run-engine
                       (list (string-append (base origin 'raw) "/raw/drip?bytes=200&gap=5")
                             (string-append (base origin 'raw) "/raw/drip?bytes=150&gap=7")
                             (string-append (base origin 'http) "/status/200")
                             (string-append (base origin 'http) "/echo")))))
         (set! stop #t)
         (with-mutex mx (let wait () (unless stopped (condition-wait cv mx) (wait))))
         (printf "deliver, callable ~a, perform ~a, libcurl ~a, run ~a: ~s; callbacks in perform ~a, in poll ~a, elsewhere ~a, off the engine thread ~a; collections ~a; longest ~s\n"
                 callable-mode perform-mode (libcurl-info-version info) r
                 (map (lambda (x) (append x (list (byte-count (car x))))) results)
                 (hashtable-ref counts 'perform 0) (hashtable-ref counts 'poll 0)
                 (hashtable-ref counts 'other 0) off-thread collections
                 (list-sort (lambda (a b) (string<? (symbol->string (car a)) (symbol->string (car b))))
                            (map (lambda (k) (cons k (/ (round (* 10 (hashtable-ref longest k 0))) 10)))
                                 (vector->list (hashtable-keys longest))))))))))
