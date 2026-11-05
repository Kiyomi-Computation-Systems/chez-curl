# M7 slice 4's prototype patch (2026-11-03), applied by make-prototype.sh to
# a copy of src/ in build/m7s4/src. It adds, as little as the measurement
# needs (the brief's "The prototype", items 1 to 6):
#   1. bindings: curl_share_init, curl_share_setopt through bind-variadic with
#      an int value (share.c reads va_arg(param, int) for CURLSHOPT_SHARE and
#      UNSHARE, 7.85.0 to 8.23.0), curl_share_cleanup; a getinfo for
#      CURLINFO_COOKIELIST's struct curl_slist *, counted as slist, a walk of
#      it through a curl_slist ftype, and curl_slist_free_all after;
#   2. the constants those need, from the headers;
#   3. a share kind in (curl private counters), each share made and freed in
#      one critical section with its count;
#   4. a jar on the engine's thread: a record of its engine, its share, a
#      handle of its own attached to the share, a state (pending, live,
#      closing, closed, abandoned) and a holder count; make, read out, load
#      and close as messages queued beside submits and taken in the order
#      queued; set-up! raising the count, take-out! lowering it; a close that
#      sets closing, the share freed when the count reaches zero; shut-down!
#      and fail-engine! answering every queued jar message;
#   5. a cookie-jar request key that sets SHARE, then COOKIEFILE "", and a
#      prototype-only switch, set-jar-order!, for the other order;
#   6. read-out lines as bytevectors, and loads of bytevectors.
# It also adds, for the measurement alone: make with a list of
# curl_share_setopt calls in place of SHARE COOKIE (items 2 and 11), a peek
# that reads a closing jar, and a probe that calls curl_share_cleanup on a
# live jar's share, with its handle attached or detached (item 1 (c)).
# The refusal reasons cookie-jar-engine, cookie-jar-closed and cookie-line
# join curl-request-error-reasons. Nothing refuses a caller's Cookie or Host
# beside a jar: item 7 measures them. The hatch is unchanged.
import sys

root = sys.argv[1]


def patch(rel, changes):
    path = f"{root}/{rel}"
    text = open(path, encoding="utf-8").read()
    for old, new in changes:
        n = text.count(old)
        assert n == 1, (rel, "found", n, old[:80])
        text = text.replace(old, new)
    open(path, "w", encoding="utf-8").write(text)


# ---------------------------------------------------------------- constants
patch("curl/private/constants.sls", [
    ("""          curlmopt-max-total-connections curlmopt-quick-exit curlmopt-pipelining curlpipe-nothing""",
     """          curlmopt-max-total-connections curlmopt-quick-exit curlmopt-pipelining curlpipe-nothing
          curlshopt-share curlshopt-unshare curl-lock-data-cookie curl-lock-data-hsts
          curlshe-ok curlshe-in-use curlinfo-cookielist"""),
    ("""  (define seek-set 0))""",
     """  (define seek-set 0)

  ;; The share interface (M7 slice 4's prototype): CURLSHoption, curl_lock_data
  ;; and CURLSHcode, curl/curl.h, alike 7.85.0 to 8.23.0 but HSTS, 7.88.0;
  ;; CURLINFO_COOKIELIST, CURLINFO_SLIST + 28.
  (define curlshopt-share 1)
  (define curlshopt-unshare 2)
  (define curl-lock-data-cookie 2)
  (define curl-lock-data-hsts 7)
  (define curlshe-ok 0)
  (define curlshe-in-use 2)
  (define curlinfo-cookielist 4194332))"""),
])

# ---------------------------------------------------------------- counters
patch("curl/private/counters.sls", [
    ("""  (define native-kinds '(block easy url slist curl-string transfer multi))""",
     """  (define native-kinds '(block easy url slist curl-string transfer multi share))"""),
])

# ---------------------------------------------------------------- layouts
patch("curl/private/layouts.sls", [
    ("""  (export curl-version-info-data curl-easyoption curl-header curl-msg curl-blob)""",
     """  (export curl-version-info-data curl-easyoption curl-header curl-msg curl-blob curl-slist)"""),
    ("""      (flags unsigned-int))))""",
     """      (flags unsigned-int)))

  ;; curl-slist : Ftype
  ;; struct curl_slist, curl/curl.h: what CURLINFO_COOKIELIST answers a
  ;; pointer to (M7 slice 4's prototype).
  (define-ftype curl-slist
    (struct
      (data uptr)
      (next uptr))))"""),
])

# ---------------------------------------------------------------- native
patch("curl/private/native.sls", [
    ("""          curl-easy-pause)""",
     """          curl-easy-pause
          curl-share-init curl-share-setopt-int curl-share-cleanup
          curl-easy-getinfo-cookielist curl-slist-strings)"""),
    ("""    (load-step (bind-variadic "curl_multi_setopt" (uptr int long) int info)))""",
     """    (load-step (bind-variadic "curl_multi_setopt" (uptr int long) int info)))

  ;; The share interface (M7 slice 4's prototype). CURLSH *curl_share_init(void);
  ;; CURLSHcode curl_share_cleanup(CURLSH *); CURLSHcode
  ;; curl_share_setopt(CURLSH *, CURLSHoption, ...), variadic after option,
  ;; bound for an int: share.c reads va_arg(param, int) for SHARE and UNSHARE.
  (define raw-curl-share-init (load-step (bind-required "curl_share_init" () uptr info)))

  (define raw-curl-share-cleanup
    (load-step (bind-required "curl_share_cleanup" (uptr) int info)))

  (define raw-curl-share-setopt-int
    (load-step (bind-variadic "curl_share_setopt" (uptr int int) int info)))"""),
    ("""  ;; curl-easy-pause : Positive-Integer Integer -> Integer""",
     """  ;; curl-share-init : -> Natural
  ;; A fresh share's address, counted as share and owned by this thread, in
  ;; one critical section; 0, counted as nothing, when libcurl made none.
  (define (curl-share-init)
    (critical-section
     (let ((share (raw-curl-share-init)))
       (unless (eqv? share 0)
         (count-up! 'share)
         (own! share 'share))
       share)))

  ;; curl-share-setopt-int : Positive-Integer Integer Integer -> Integer
  ;; SHARE, this thread's, a CURLSHoption and an int: the CURLSHcode.
  (define (curl-share-setopt-int share option value)
    (check-owner 'curl-share-setopt share 'share)
    (raw-curl-share-setopt-int share option value))

  ;; curl-share-cleanup : Positive-Integer -> Integer
  ;; Frees SHARE, this thread's: the CURLSHcode. On CURLSHE_OK it is counted
  ;; down and forgotten, in the critical section of the call; any other
  ;; code leaves it counted, and live, as curl-multi-cleanup does.
  (define (curl-share-cleanup share)
    (check-owner 'curl-share-cleanup share 'share)
    (critical-section
     (let ((code (raw-curl-share-cleanup share)))
       (when (eqv? code curlshe-ok)
         (count-down! 'share)
         (disown! share))
       code)))

  ;; curl-easy-getinfo-cookielist : Positive-Integer -> (Values Integer Natural)
  ;; The CURLcode of CURLINFO_COOKIELIST on EASY, this thread's, and the
  ;; struct curl_slist * it wrote, counted as slist and owned by this thread
  ;; in the critical section of the call; 0 for none, or unless the code is
  ;; CURLE_OK. The caller frees it with curl-slist-free-all.
  (define (curl-easy-getinfo-cookielist easy)
    (let ((slot #f))
      (dynamic-wind #t
        (lambda () (set! slot (foreign-block (foreign-sizeof 'void*))))
        (lambda ()
          (critical-section
           (let ((code (curl-easy-getinfo easy curlinfo-cookielist slot)))
             (if (eqv? code curle-ok)
                 (let ((head (foreign-ref 'uptr slot 0)))
                   (unless (eqv? head 0)
                     (count-up! 'slist)
                     (own! head 'slist))
                   (values code head))
                 (values code 0)))))
        (lambda () (free-foreign-block! slot)))))

  ;; curl-slist-strings : Positive-Integer -> (Listof Bytevector)
  ;; Each string of the list LIST, this thread's, in its order, as bytes
  ;; copied up to its NUL: the walk of struct curl_slist by data and next.
  (define (curl-slist-strings list)
    (check-owner 'curl-slist-strings list 'slist)
    (let walk ((node list) (found '()))
      (if (eqv? node 0)
          (reverse found)
          (let* ((cell (make-ftype-pointer curl-slist node))
                 (bytes (or (c-string->bytevector (ftype-ref curl-slist (data) cell)) (make-bytevector 0))))
            (walk (ftype-ref curl-slist (next) cell) (cons bytes found))))))

  ;; curl-easy-pause : Positive-Integer Integer -> Integer"""),
])

# ---------------------------------------------------------------- conditions
patch("curl/private/conditions.sls", [
    ("""      proxy-tls-without-https-proxy proxy-tls-in-tls https-proxy-unsupported))""",
     """      proxy-tls-without-https-proxy proxy-tls-in-tls https-proxy-unsupported
      cookie-jar-engine cookie-jar-closed cookie-line))"""),
])

# ---------------------------------------------------------------- transfer
patch("curl/private/transfer.sls", [
    ("""          plan-body-length curl-request-with-upload-fault planted-upload-fault upload-plant-split!
          upload-split-commit!)""",
     """          plan-body-length curl-request-with-upload-fault planted-upload-fault upload-plant-split!
          upload-split-commit!
          curl-cookie-jar? make-cookie-jar-record cookie-jar-engine cookie-jar-share
          cookie-jar-share-set! cookie-jar-handle cookie-jar-handle-set! cookie-jar-state
          cookie-jar-state-set! cookie-jar-holders cookie-jar-holders-set! cookie-jar-log
          cookie-jar-log-set! plan-jar curl-request-cookie-jar jar-settings jar-order set-jar-order!)"""),
    ("""      stream-buffer body-length http-version credentials proxy-ca-file proxy-verify))""",
     """      stream-buffer body-length http-version credentials proxy-ca-file proxy-verify cookie-jar))

  ;; A cookie jar (M7 slice 4's prototype): its engine; and, written on the
  ;; engine's thread under the engine's mutex, its share's address and its
  ;; own handle's, #f while not made or once freed; its state, pending,
  ;; live, closing, closed or abandoned; how many transfers hold it; and a
  ;; log, newest first, of each curl_share_cleanup and close: (STEP HOLDERS
  ;; CODE).
  (define-record-type (curl-cookie-jar make-cookie-jar-record curl-cookie-jar?)
    (fields (immutable engine cookie-jar-engine)
            (mutable share cookie-jar-share cookie-jar-share-set!)
            (mutable handle cookie-jar-handle cookie-jar-handle-set!)
            (mutable state cookie-jar-state cookie-jar-state-set!)
            (mutable holders cookie-jar-holders cookie-jar-holders-set!)
            (mutable log cookie-jar-log cookie-jar-log-set!))
    (opaque #t))

  ;; jar-order : -> (U 'share-first 'file-first)
  ;; set-jar-order! : (U 'share-first 'file-first) -> Void
  ;; The order a transfer sets a jar's two options in, process-wide: a
  ;; prototype-only switch, for item 3. share-first by default.
  (define jar-order-cell (vector 'share-first))
  (define (jar-order) (vector-ref jar-order-cell 0))
  (define (set-jar-order! order) (vector-set! jar-order-cell 0 order))

  ;; jar-settings : Natural Symbol -> (Listof (Pairof String (U Natural String)))
  ;; A jar's settings on a transfer, in order: SHARE at SHARE-ADDRESS, then
  ;; COOKIEFILE "", or the other way round for file-first. Pure.
  (define (jar-settings share-address order)
    (if (eq? order 'file-first)
        (list (cons "COOKIEFILE" "") (cons "SHARE" share-address))
        (list (cons "SHARE" share-address) (cons "COOKIEFILE" ""))))"""),
    ("""            (immutable options curl-request-options))
    ;; Opaque: Chez prints a record's every field, and record-rtd opens""",
     """            (immutable options curl-request-options)
            (immutable cookie-jar curl-request-cookie-jar))
    ;; Opaque: Chez prints a record's every field, and record-rtd opens"""),
    ("""                           body-length http-version credentials proxy-ca-file proxy-verify
                           fault follow options)""",
     """                           body-length http-version credentials proxy-ca-file proxy-verify
                           fault follow options cookie-jar)"""),
    ("""      (unless (boolean? follow) (wrong "follow is #t or #f" follow))""",
     """      (unless (boolean? follow) (wrong "follow is #t or #f" follow))
      (unless (or (not cookie-jar) (curl-cookie-jar? cookie-jar))
        (wrong "a cookie-jar is a jar, or #f" cookie-jar))"""),
    ("""                        credentials (path-copy who 'proxy-ca-file proxy-ca-file) proxy-verify
                        fault follow options)))""",
     """                        credentials (path-copy who 'proxy-ca-file proxy-ca-file) proxy-verify
                        fault follow options cookie-jar)))"""),
    ("""                     (given 'proxy-verify curl-request-proxy-verify)
                     fault follow options))""",
     """                     (given 'proxy-verify curl-request-proxy-verify)
                     fault follow options
                     (given 'cookie-jar curl-request-cookie-jar)))"""),
    ("""    (new-curl-request "" 'get '() #f #f #f #f #f #f #t 'environment #f #f #f #f #f #t #f #f '()))""",
     """    (new-curl-request "" 'get '() #f #f #f #f #f #f #t 'environment #f #f #f #f #f #t #f #f '() #f))"""),
    ("""            (immutable tunnel) (immutable unmultiplex))""",
     """            (immutable tunnel) (immutable unmultiplex) (immutable jar))"""),
    ("""                   (curl-request-proxy-verify request) tunnel unmultiplex))))""",
     """                   (curl-request-proxy-verify request) tunnel unmultiplex
                   (curl-request-cookie-jar request)))))"""),
    ("""              (credentials-settings (plan-credentials plan)))
    (set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer)""",
     """              (credentials-settings (plan-credentials plan)))
    (let ((jar (plan-jar plan)))
      (when jar
        (for-each (lambda (setting)
                    (if (string? (cdr setting))
                        (set-string-option! easy (car setting) (cdr setting) buffer)
                        (set-option! easy (car setting) (cdr setting) buffer)))
                  (jar-settings (cookie-jar-share jar) (jar-order)))))
    (set-tls-options! easy (plan-ca-file plan) (plan-verify plan) buffer)"""),
])

# ---------------------------------------------------------------- engine
JAR_SECTION = r'''  ;; --- the cookie jar: M7 slice 4's measuring prototype, not the build's shape ---------
  ;; A jar's messages are queued beside submits, (KIND JAR REPLY ARG), and a
  ;; turn takes them with its submits in the order queued. A reply is a
  ;; vector #(STATE ANSWER), STATE pending or done, written under the
  ;; engine's mutex; an answer is (ok VALUE COST), (refused REASON ...) or
  ;; (raised CONDITION). The engine's thread alone makes, uses and frees a
  ;; jar's share and its handle, each in one critical section with its
  ;; count and its record.

  (define jar-kinds '(jar-make jar-read jar-peek jar-load jar-close jar-probe))

  ;; jar-refusal : Symbol -> Condition
  (define (jar-refusal reason)
    (condition (make-curl-request-error 'cookie-jar 'cookie-jar reason)
               (make-who-condition 'curl-submit)
               (make-message-condition
                (if (eq? reason 'cookie-jar-engine)
                    "the request's cookie jar is another engine's"
                    "the request's cookie jar is not live"))
               (make-irritants-condition (list reason))))

  ;; post-jar! : Engine Symbol Jar Any -> Reply
  ;; KIND's message for JAR, with ARG, queued, with the wakeup, in one hold;
  ;; an engine not running refuses it, as a submit is refused.
  (define (post-jar! engine kind jar arg)
    (let* ((reply (vector 'pending #f))
           (refusal
            (locked (curl-engine-lock engine)
              (lambda ()
                (case (engine-state engine)
                  ((running)
                   (curl-engine-queue-set! engine (cons (list kind jar reply arg) (curl-engine-queue engine)))
                   (curl-multi-wakeup (engine-multi engine))
                   #f)
                  ((failing failed) (engine-failure engine))
                  (else (engine-error 'stopped #f)))))))
      (when refusal (raise refusal))
      reply))

  ;; curl-cookie-jar-post-make! : Engine (Listof (Pairof Integer Integer)) -> (Values Jar Reply)
  ;; A jar of ENGINE's, pending, and its make queued: a share, OPS's
  ;; curl_share_setopt calls in order, (OPTION . VALUE) each, then the jar's
  ;; handle, attached. The default jar's OPS are ((1 . 2)), SHARE COOKIE.
  (define (curl-cookie-jar-post-make! engine ops)
    (check-engine 'curl-cookie-jar-post-make! engine)
    (let ((jar (make-cookie-jar-record engine #f #f 'pending 0 '())))
      (values jar (post-jar! engine 'jar-make jar (map (lambda (op) (cons (car op) (cdr op))) ops)))))

  ;; curl-cookie-jar-post! : Jar Symbol Any -> Reply
  ;; KIND's message for JAR queued: jar-read, jar-peek (a read that a
  ;; closing jar answers too), jar-load (ARG a list of bytevectors, copied,
  ;; none holding a 0 byte), jar-close, jar-probe (ARG attached or detached).
  (define (curl-cookie-jar-post! jar kind arg)
    (unless (curl-cookie-jar? jar)
      (assertion-violation 'curl-cookie-jar-post! "not a cookie jar" jar))
    (unless (memq kind (cdr jar-kinds))
      (assertion-violation 'curl-cookie-jar-post! "not a jar message" kind))
    (when (eq? kind 'jar-load)
      (for-each (lambda (line)
                  (unless (bytevector? line)
                    (assertion-violation 'curl-cookie-jar-post! "a line is a bytevector" line))
                  (let scan ((i 0))
                    (when (< i (bytevector-length line))
                      (when (= (bytevector-u8-ref line i) 0)
                        (assertion-violation 'curl-cookie-jar-post! "a line holds a 0 byte, which C would read as its end" line))
                      (scan (+ i 1)))))
                arg))
    (post-jar! (cookie-jar-engine jar) kind jar
               (if (eq? kind 'jar-load) (map bytevector-copy arg) arg)))

  ;; curl-cookie-jar-reply-wait : Jar Reply Natural -> (U Answer #f)
  (define (curl-cookie-jar-reply-wait jar reply ms)
    (wait-until 'curl-cookie-jar-reply-wait (curl-engine-lock (cookie-jar-engine jar))
                (lambda () (and (eq? (vector-ref reply 0) 'done) (vector-ref reply 1)))
                (deadline-after 'curl-cookie-jar-reply-wait ms)))

  (define (curl-cookie-jar-state jar)
    (locked (curl-engine-lock (cookie-jar-engine jar)) (lambda () (cookie-jar-state jar))))
  (define (curl-cookie-jar-holders jar)
    (locked (curl-engine-lock (cookie-jar-engine jar)) (lambda () (cookie-jar-holders jar))))
  (define (curl-cookie-jar-log jar)
    (locked (curl-engine-lock (cookie-jar-engine jar)) (lambda () (reverse (cookie-jar-log jar)))))
  (define (curl-engine-jar-count engine)
    (locked (curl-engine-lock engine) (lambda () (length (engine-jars engine)))))

  ;; answer! : Engine Reply Any -> Void
  (define (answer! engine reply value)
    (locked (curl-engine-lock engine)
      (lambda ()
        (when (eq? (vector-ref reply 0) 'pending)
          (vector-set! reply 1 value)
          (vector-set! reply 0 'done)))))

  (define (jar-state-of engine jar)
    (locked (curl-engine-lock engine) (lambda () (cookie-jar-state jar))))

  (define (jar-usable? engine jar)
    (and (eq? (cookie-jar-engine jar) engine) (eq? (jar-state-of engine jar) 'live)))

  ;; jar-message! : Engine Message -> Void
  ;; One jar message, carried out on the engine's thread, and answered; a
  ;; raise is its answer, never the engine's failure.
  (define (jar-message! engine message)
    (let ((kind (car message)) (jar (cadr message)) (reply (caddr message)) (arg (cadddr message)))
      (answer! engine reply
               (guard (e (#t (list 'raised e)))
                 (if (not (eq? (cookie-jar-engine jar) engine))
                     (list 'refused 'cookie-jar-engine)
                     (case kind
                       ((jar-make) (make-jar! engine jar arg))
                       ((jar-read) (read-jar! engine jar #f))
                       ((jar-peek) (read-jar! engine jar #t))
                       ((jar-load) (load-jar! engine jar arg))
                       ((jar-close) (close-jar! engine jar))
                       ((jar-probe) (probe-jar! engine jar arg))
                       (else (list 'refused 'unknown-message))))))))

  ;; make-jar! : Engine Jar (Listof (Pairof Integer Integer)) -> Answer
  (define (make-jar! engine jar ops)
    (let ((lock (curl-engine-lock engine)))
      (critical-section
       (let ((share (curl-share-init)))
         (when (eqv? share 0)
           (error 'make-curl-cookie-jar "curl_share_init returned NULL"))
         (locked lock (lambda () (cookie-jar-share-set! jar share)))))
      (guard (e (#t (free-jar! engine jar 'make-failed) (raise e)))
        (let ((codes (let loop ((rest ops) (found '()))
                       (if (null? rest)
                           (reverse found)
                           (let* ((op (car rest))
                                  (code (curl-share-setopt-int (cookie-jar-share jar) (car op) (cdr op))))
                             (loop (cdr rest) (cons (list (car op) (cdr op) code) found)))))))
          (critical-section
           (let ((easy (curl-easy-init)))
             (when (eqv? easy 0)
               (error 'make-curl-cookie-jar "curl_easy_init returned NULL"))
             (locked lock (lambda () (cookie-jar-handle-set! jar easy)))))
          (let ((code (curl-easy-setopt-pointer (cookie-jar-handle jar) (car (option-named "SHARE"))
                                                (cookie-jar-share jar))))
            (locked lock
              (lambda ()
                (cookie-jar-state-set! jar 'live)
                (engine-jars-set! engine (cons jar (engine-jars engine)))))
            (list 'ok (list codes code) 0))))))

  ;; free-jar! : Engine Jar Symbol -> Integer
  ;; JAR's handle freed, then its share, each in one critical section with
  ;; its record; the cleanup's answer logged under STEP, and on CURLSHE_OK
  ;; the jar marked closed and let go in the same section. Answers the
  ;; cleanup's code, 0 for a jar with no share.
  (define (free-jar! engine jar step)
    (let ((lock (curl-engine-lock engine)))
      (critical-section
       (let ((easy (cookie-jar-handle jar)))
         (when easy
           (curl-easy-cleanup easy)
           (locked lock (lambda () (cookie-jar-handle-set! jar #f))))))
      (critical-section
       (let ((share (cookie-jar-share jar)))
         (if (not share)
             0
             (let ((code (curl-share-cleanup share)))
               (locked lock
                 (lambda ()
                   (cookie-jar-log-set! jar (cons (list step (cookie-jar-holders jar) code) (cookie-jar-log jar)))
                   (when (eqv? code curlshe-ok)
                     (cookie-jar-share-set! jar #f)
                     (cookie-jar-state-set! jar 'closed)
                     (engine-jars-set! engine (remq jar (engine-jars engine))))))
               code))))))

  ;; read-jar! : Engine Jar Boolean -> Answer
  ;; CURLINFO_COOKIELIST through JAR's handle, walked and freed: (ok (CODE
  ;; LINES) (GETINFO-NS WALK-NS FREE-NS)), the times on this thread.
  (define (read-jar! engine jar peek)
    (let ((state (jar-state-of engine jar)))
      (if (not (or (eq? state 'live) (and peek (eq? state 'closing) (cookie-jar-handle jar))))
          (list 'refused 'cookie-jar-closed state)
          (let ((t0 (monotonic-ns)))
            (let-values (((code head) (curl-easy-getinfo-cookielist (cookie-jar-handle jar))))
              (let* ((t1 (monotonic-ns))
                     (lines (if (eqv? head 0)
                                '()
                                (guard (e (#t (curl-slist-free-all head) (raise e)))
                                  (curl-slist-strings head))))
                     (t2 (monotonic-ns)))
                (unless (eqv? head 0) (curl-slist-free-all head))
                (let ((t3 (monotonic-ns)))
                  (list 'ok (list code lines) (list (- t1 t0) (- t2 t1) (- t3 t2))))))))))

  ;; load-jar! : Engine Jar (Listof Bytevector) -> Answer
  ;; Each line set as COOKIELIST on JAR's handle, a NUL-terminated counted
  ;; copy: (ok CODES (TOTAL-NS SETOPT-NS)).
  (define (load-jar! engine jar lines)
    (if (not (eq? (jar-state-of engine jar) 'live))
        (list 'refused 'cookie-jar-closed (jar-state-of engine jar))
        (let ((id (car (option-named "COOKIELIST"))) (handle (cookie-jar-handle jar)) (t0 (monotonic-ns)))
          (let loop ((rest lines) (codes '()) (spent 0))
            (if (null? rest)
                (list 'ok (reverse codes) (list (- (monotonic-ns) t0) spent))
                (let* ((bytes (car rest))
                       (n (bytevector-length bytes))
                       (c (make-bytevector (+ n 1) 0)))
                  (bytevector-copy! bytes 0 c 0 n)
                  (let-values (((code took)
                                (call-with-foreign-bytes c
                                  (lambda (address)
                                    (let* ((a (monotonic-ns))
                                           (code (curl-easy-setopt-pointer handle id address))
                                           (b (monotonic-ns)))
                                      (values code (- b a)))))))
                    (loop (cdr rest) (cons code codes) (+ spent took)))))))))

  ;; close-jar! : Engine Jar -> Answer
  ;; A live JAR set closing, and freed at once when no transfer holds it:
  ;; (ok STATE 0), STATE as it stands after.
  (define (close-jar! engine jar)
    (let ((lock (curl-engine-lock engine)))
      (when (eq? (jar-state-of engine jar) 'live)
        (locked lock
          (lambda ()
            (cookie-jar-state-set! jar 'closing)
            (cookie-jar-log-set! jar (cons (list 'close (cookie-jar-holders jar) #f) (cookie-jar-log jar)))))
        (when (= (locked lock (lambda () (cookie-jar-holders jar))) 0)
          (free-jar! engine jar 'close)))
      (list 'ok (jar-state-of engine jar) 0)))

  ;; probe-jar! : Engine Jar (U 'attached 'detached) -> Answer
  ;; curl_share_cleanup on JAR's share, its handle left attached, or detached
  ;; first and attached again after a refusal: (ok CODE 0), logged. A share
  ;; the probe frees is let go, the jar freed-by-probe.
  (define (probe-jar! engine jar how)
    (let ((share (cookie-jar-share jar)) (handle (cookie-jar-handle jar)) (id (car (option-named "SHARE"))))
      (if (not share)
          (list 'refused 'no-share)
          (begin
            (when (and handle (eq? how 'detached)) (curl-easy-setopt-pointer handle id 0))
            (let ((code (critical-section
                         (let ((code (curl-share-cleanup share)))
                           (when (eqv? code curlshe-ok)
                             (locked (curl-engine-lock engine)
                               (lambda ()
                                 (cookie-jar-share-set! jar #f)
                                 (cookie-jar-state-set! jar 'freed-by-probe))))
                           code))))
              (let ((holders (curl-cookie-jar-holders jar)))
                (locked (curl-engine-lock engine)
                  (lambda () (cookie-jar-log-set! jar (cons (list (list 'probe how) holders code) (cookie-jar-log jar))))))
              (when (and handle (eq? how 'detached) (not (eqv? code curlshe-ok)))
                (curl-easy-setopt-pointer handle id share))
              (list 'ok code 0))))))

  ;; release! : Engine Token -> Void
  ;; TOKEN's hold on its jar let go, once, and the count lowered; a closing
  ;; jar the count leaves at zero freed.
  (define (release! engine token)
    (let* ((lock (curl-engine-lock engine))
           (jar (locked lock
                  (lambda ()
                    (let ((jar (hashtable-ref (engine-holds engine) token #f)))
                      (when jar
                        (hashtable-delete! (engine-holds engine) token)
                        (cookie-jar-holders-set! jar (- (cookie-jar-holders jar) 1)))
                      jar)))))
      (when (and jar
                 (locked lock (lambda () (and (eq? (cookie-jar-state jar) 'closing)
                                              (= (cookie-jar-holders jar) 0)))))
        (free-jar! engine jar 'release))))

'''

patch("curl/private/engine.sls", [
    ("""          curl-engine-stale-cancels call-with-engine-held""",
     """          curl-engine-stale-cancels call-with-engine-held
          curl-cookie-jar-post-make! curl-cookie-jar-post! curl-cookie-jar-reply-wait
          curl-cookie-jar-state curl-cookie-jar-holders curl-cookie-jar-log curl-engine-jar-count"""),
    ("""            (mutable probe engine-probe engine-probe-set!))""",
     """            (mutable probe engine-probe engine-probe-set!)
            (mutable jars engine-jars engine-jars-set!)
            (immutable holds engine-holds))"""),
    ("""                                      seams (make-vector 1 0) #f 0 0 #f #f)))""",
     """                                      seams (make-vector 1 0) #f 0 0 #f #f '() (make-eq-hashtable))))"""),
    ("""                (case (engine-state engine)
                  ((running)
                   (curl-engine-queue-set! engine (cons (cons 'submit token) (curl-engine-queue engine)))
                   (curl-multi-wakeup (engine-multi engine))
                   #f)
                  ((failing failed) (engine-failure engine))
                  (else (engine-error 'stopped #f)))))))
      (when refusal (raise refusal))
      token))""",
     """                (case (engine-state engine)
                  ((running)
                   (let ((jar (plan-jar plan)))
                     (cond ((and jar (not (eq? (cookie-jar-engine jar) engine))) (jar-refusal 'cookie-jar-engine))
                           ((and jar (not (eq? (cookie-jar-state jar) 'live))) (jar-refusal 'cookie-jar-closed))
                           (else
                            (curl-engine-queue-set! engine (cons (cons 'submit token) (curl-engine-queue engine)))
                            (curl-multi-wakeup (engine-multi engine))
                            #f))))
                  ((failing failed) (engine-failure engine))
                  (else (engine-error 'stopped #f)))))))
      (when refusal (raise refusal))
      token))"""),
    ("""  ;; --- completing a token ----------------------------------------------------------------""",
     JAR_SECTION + """  ;; --- completing a token ----------------------------------------------------------------"""),
    ("""              (for-each (lambda (message)
                          (when (eq? (car message) 'submit) (set-up! engine multi (cdr message))))
                        messages)""",
     """              (for-each (lambda (message)
                          (cond ((eq? (car message) 'submit) (set-up! engine multi (cdr message)))
                                ((memq (car message) jar-kinds) (jar-message! engine message))))
                        messages)"""),
    ("""  (define (set-up! engine multi token)
    (unless (curl-token-done? token)
      (fault-at! engine 'setup)
      (when (plan-unmultiplex (curl-token-plan token)) (stop-multiplexing! engine multi))
      (let ((live (guard (e (#t (complete! engine token e '()) #f))
                    (start-transfer! (curl-token-plan token)
                                     (not (memq 'transfer (engine-without engine)))
                                     (engine-moves engine)
                                     (engine-seams engine)))))
        (when live
          (token-live-set! token live)
          (locked (curl-engine-lock engine)
            (lambda () (hashtable-set! (engine-live engine) (live-transfer-easy live) (cons token live))))
          (let ((code (curl-multi-add-handle multi (live-transfer-easy live))))
            (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_add_handle code)))))))""",
     """  (define (set-up! engine multi token)
    (unless (curl-token-done? token)
      (fault-at! engine 'setup)
      (let ((jar (plan-jar (curl-token-plan token))))
        (if (and jar (not (jar-usable? engine jar)))
            (complete! engine token
                       (jar-refusal (if (eq? (cookie-jar-engine jar) engine) 'cookie-jar-closed 'cookie-jar-engine))
                       '())
            (begin
              (when (plan-unmultiplex (curl-token-plan token)) (stop-multiplexing! engine multi))
              (let ((live (guard (e (#t (complete! engine token e '()) #f))
                            (start-transfer! (curl-token-plan token)
                                             (not (memq 'transfer (engine-without engine)))
                                             (engine-moves engine)
                                             (engine-seams engine)))))
                (when live
                  (token-live-set! token live)
                  (locked (curl-engine-lock engine)
                    (lambda ()
                      (hashtable-set! (engine-live engine) (live-transfer-easy live) (cons token live))
                      (when jar
                        (hashtable-set! (engine-holds engine) token jar)
                        (cookie-jar-holders-set! jar (+ (cookie-jar-holders jar) 1)))))
                  (let ((code (curl-multi-add-handle multi (live-transfer-easy live))))
                    (unless (eqv? code curlm-ok) (multi-failed 'curl_multi_add_handle code))))))))))"""),
    ("""      (free-transfer! live)
      (fault-at! engine 'free)""",
     """      (free-transfer! live)
      (release! engine token)
      (fault-at! engine 'free)"""),
    ("""    (for-each (lambda (message)
                (when (eq? (car message) 'submit)
                  (complete! engine (cdr message) (transfer-ended 'stopped) '())))
              messages)
    (for-each (lambda (message)
                (when (eq? (car message) 'cancel) (cancel! engine multi (cdr message))))
              messages)""",
     """    (for-each (lambda (message)
                (when (eq? (car message) 'submit)
                  (complete! engine (cdr message) (transfer-ended 'stopped) '())))
              messages)
    (for-each (lambda (message)
                (when (memq (car message) jar-kinds)
                  (answer! engine (caddr message) (list 'refused 'stopped))))
              messages)
    (for-each (lambda (message)
                (when (eq? (car message) 'cancel) (cancel! engine multi (cdr message))))
              messages)"""),
    ("""    (unless (live-empty? engine)
      (error 'curl-engine-stop "the table of live transfers is not empty after a stop"))""",
     """    (unless (live-empty? engine)
      (error 'curl-engine-stop "the table of live transfers is not empty after a stop"))
    (for-each (lambda (jar) (free-jar! engine jar 'stop))
              (locked (curl-engine-lock engine) (lambda () (engine-jars engine))))"""),
    ("""      (for-each (lambda (message)
                  (when (eq? (car message) 'submit)
                    (complete! engine (cdr message) failure '())))
                (append (engine-batch engine) queued))""",
     """      (for-each (lambda (message)
                  (when (eq? (car message) 'submit)
                    (complete! engine (cdr message) failure '()))
                  (when (memq (car message) jar-kinds)
                    (answer! engine (caddr message) (list 'refused 'failed failure))))
                (append (engine-batch engine) queued))"""),
    ("""                      (guard (e (#t #f)) (free-transfer! live))""",
     """                      (guard (e (#t #f)) (free-transfer! live))
                      (when removed (guard (e (#t #f)) (release! engine token)))"""),
    ("""      (when multi
        (guard (e (#t #f)) (curl-multi-cleanup multi)))""",
     """      (for-each (lambda (jar)
                  (guard (e (#t #f))
                    (unless (eqv? (free-jar! engine jar 'fail) curlshe-ok)
                      (locked lock (lambda () (cookie-jar-state-set! jar 'abandoned))))))
                (locked lock (lambda () (engine-jars engine))))
      (when multi
        (guard (e (#t #f)) (curl-multi-cleanup multi)))"""),
])
print("prototype.py: patched", root)
