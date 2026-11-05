#!/usr/bin/env python3
"""build/m7s4b/mutants.py: M7 slice 4's mutants, each a copy of the tree with
one rule broken, the suites that must notice, and the tests that must fail.

  mutants.py make [NAME...]   copy and mutate each (all by default) under
                              build/m7s4b/mut/NAME; write build/m7s4b/mut/jobs
  mutants.py check [NAME...]  read each mutant's logs: killed when every
                              expected test failed by name, else SURVIVED

The jobs run in the container: scripts/guix-env sh build/m7s4b/mut-run.sh.
From the repository's root, on the host."""
import os, re, subprocess, sys

E = 'src/curl/private/engine.sls'
T = 'src/curl/private/transfer.sls'
N = 'src/curl/private/native.sls'
C = 'tests/test-cookies.sps'

COOKIES = ['tests/test-cookies.sps']

M = []


def mutant(name, edits, suites, expect):
    M.append(dict(name=name, edits=edits, suites=suites, expect=expect))


# --- control: nothing broken; every suite the mutants run passes ----------------------
mutant('control', [], None, [])

# --- the engine: holds, frees, messages ----------------------------------------------
mutant('hold-not-raised', [(E, """                      (when jar
                        (hashtable-set! (engine-holds engine) token jar)""", """                      (when #f
                        (hashtable-set! (engine-holds engine) token jar)""")],
       COOKIES, ['a close while two transfers hold the jar'])

mutant('hold-not-lowered', [(E, """      (free-transfer! live)
      (release! engine token)
      (fault-at! engine 'free)""", """      (free-transfer! live)
      (fault-at! engine 'free)""")],
       COOKIES, ['a close while two transfers hold the jar', 'a close crossing a submit, controlled'])

mutant('hold-before-start', [(E, """              (when (plan-unmultiplex (curl-token-plan token)) (stop-multiplexing! engine multi))
              (let ((live""", """              (when (plan-unmultiplex (curl-token-plan token)) (stop-multiplexing! engine multi))
              (when jar
                (locked (curl-engine-lock engine)
                  (lambda ()
                    (hashtable-set! (engine-holds engine) token jar)
                    (cookie-jar-holders-set! jar (+ (cookie-jar-holders jar) 1)))))
              (let ((live"""), (E, """                      (when jar
                        (hashtable-set! (engine-holds engine) token jar)
                        (cookie-jar-holders-set! jar (+ (cookie-jar-holders jar) 1)))))""", """                      #f))""")],
       COOKIES, ['a transfer whose start raises holds the jar not at all'])

mutant('fail-releases-abandoned', [(E, """(when (or removed (not easy)) (guard (e (#t #f)) (release! engine token)))""",
                                    """(when #t (guard (e (#t #f)) (release! engine token)))""")],
       COOKIES, ['a failed engine that abandons a live transfer'])

mutant('fail-keeps-freed', [(E, """(when (or removed (not easy)) (guard (e (#t #f)) (release! engine token)))""",
                             """(when #f (guard (e (#t #f)) (release! engine token)))""")],
       COOKIES, ['a failed engine, its fault planted at perform', 'a failed engine that abandons a live transfer'])

mutant('share-before-handle', [(E, """      (critical-section
       (let ((easy (cookie-jar-handle jar)))
         (when easy
           (curl-easy-cleanup easy)
           (locked lock (lambda () (cookie-jar-handle-set! jar #f))))))
      (critical-section
       (let* ((share (cookie-jar-share jar))
              (code (if share (curl-share-cleanup share) curlshe-ok)))
         (when (eqv? code curlshe-ok)
           (locked lock
             (lambda ()
               (cookie-jar-share-set! jar #f)
               (cookie-jar-state-set! jar 'closed)
               (engine-jars-set! engine (remq jar (engine-jars engine))))))
         code))))""", """      (let ((code
             (critical-section
              (let* ((share (cookie-jar-share jar))
                     (code (if share (curl-share-cleanup share) curlshe-ok)))
                (when (eqv? code curlshe-ok)
                  (locked lock
                    (lambda ()
                      (cookie-jar-share-set! jar #f)
                      (cookie-jar-state-set! jar 'closed)
                      (engine-jars-set! engine (remq jar (engine-jars engine))))))
                code))))
        (critical-section
         (let ((easy (cookie-jar-handle jar)))
           (when easy
             (curl-easy-cleanup easy)
             (locked lock (lambda () (cookie-jar-handle-set! jar #f))))))
        code)))""")],
       COOKIES, ['a stop frees every jar', 'a close while two transfers hold the jar'])

mutant('close-ignores-holders', [(E, """                   (begin (cookie-jar-state-set! jar 'closing)
                          (= (cookie-jar-holders jar) 0)))))""", """                   (begin (cookie-jar-state-set! jar 'closing)
                          #t))))""")],
       COOKIES, ['a close while two transfers hold the jar'])

mutant('setup-no-check', [(E, """        (if (and jar (not (jar-usable? engine jar)))""", """        (if #f""")],
       COOKIES, ['a close crossing a submit, controlled', 'a close crossing a submit, on an engine that waits'])

mutant('submit-no-closed-check', [(E, """                         ((and jar (not (eq? (cookie-jar-state jar) 'live)))
                          (jar-refusal who 'cookie-jar-closed))""", """                         (#f
                          (jar-refusal who 'cookie-jar-closed))""")],
       COOKIES, ['a close while two transfers hold the jar', 'a close crossing a submit, controlled'])

mutant('submit-no-engine-check', [(E, """                   (cond ((and jar (not (eq? (cookie-jar-engine jar) engine)))
                          (jar-refusal who 'cookie-jar-engine))""", """                   (cond (#f
                          (jar-refusal who 'cookie-jar-engine))""")],
       COOKIES, ["a submit refuses another engine's jar"])

mutant('jar-after-submits', [(E, """                            ((jar) (jar-message! engine message))
                            (else #f)))
                        messages)""", """                            (else #f)))
                        messages)
              (for-each (lambda (message) (when (eq? (car message) 'jar) (jar-message! engine message)))
                        messages)""")],
       COOKIES, ['a close crossing a submit, controlled'])

mutant('jar-before-submits', [(E, """              (for-each (lambda (message)
                          (case (car message)
                            ((submit) (set-up! engine multi (cdr message)))
                            ((jar) (jar-message! engine message))
                            (else #f)))
                        messages)""", """              (for-each (lambda (message) (when (eq? (car message) 'jar) (jar-message! engine message)))
                        messages)
              (for-each (lambda (message) (when (eq? (car message) 'submit) (set-up! engine multi (cdr message))))
                        messages)""")],
       COOKIES, ['a close crossing a submit, controlled'])

mutant('jar-after-perform', [(E, """                            ((jar) (jar-message! engine message))
                            (else #f)))""", """                            (else #f)))"""), (E, """              (read-finished! engine multi)
              (unless (locked (curl-engine-lock engine) (lambda () (pair? (curl-engine-queue engine))))""",
                                """              (read-finished! engine multi)
              (for-each (lambda (message) (when (eq? (car message) 'jar) (jar-message! engine message)))
                        messages)
              (unless (locked (curl-engine-lock engine) (lambda () (pair? (curl-engine-queue engine))))""")],
       COOKIES, ['a close crossing a submit, controlled'])

mutant('stop-unanswered', [(E, """    (answer-jar-messages! engine messages (engine-error 'stopped #f))""", """    #f""")],
       COOKIES, ['every jar message is answered'])

mutant('fail-unanswered', [(E, """      (answer-jar-messages! engine (append (engine-batch engine) queued) failure)""", """      #f""")],
       COOKIES, ['every jar message is answered'])

mutant('stop-keeps-jars', [(E, """    (unless (null? (free-jars! engine))""", """    (unless #t""")],
       COOKIES, ['a stop frees every jar'])

mutant('fail-keeps-jars', [(E, """                  (free-jars! engine)))""", """                  '()))""")],
       COOKIES, ['a failed engine, its fault planted at perform'])

mutant('share-unset', [(E, """(let loop ((rest (or ops share-settings)) (found '()))""",
                        """(let loop ((rest (or ops '())) (found '()))""")],
       COOKIES, ['across requests and hosts, three labels deep'])

mutant('share-hsts', [(T, """(define share-settings (list (cons curlshopt-share curl-lock-data-cookie)))""",
                       """(define share-settings (list (cons curlshopt-share curl-lock-data-cookie) (cons curlshopt-share 7)))""")],
       COOKIES, ['share-settings, written out whole'])

mutant('settings-swapped', [(T, """          (list (cons (car names) share-address) (cons (cadr names) ""))""",
                             """          (list (cons (cadr names) "") (cons (car names) share-address))""")],
       COOKIES, ['jar-settings, written out whole'])

mutant('no-cookiefile', [(T, """          (list (cons (car names) share-address) (cons (cadr names) ""))""",
                          """          (list (cons (car names) share-address))""")],
       COOKIES, ['jar-settings, written out whole'])

mutant('read-closed-allowed', [(E, """                          (live-jar! engine jar 'curl-cookie-jar-cookies)
""", "")],
       COOKIES, ['a close while two transfers hold the jar'])

mutant('load-closed-allowed', [(E, """                          (live-jar! engine jar 'curl-cookie-jar-load!)
""", "")],
       COOKIES, ['a close while two transfers hold the jar'])

mutant('read-out-waits-inside-sections', [(E, """    (define who 'curl-cookie-jar-cookies)
    (check-jar who jar)
    (require-interrupts-on who)""", """    (define who 'curl-cookie-jar-cookies)
    (check-jar who jar)""")],
       COOKIES, ['inside a critical section, each jar procedure'])

# --- the load rule, cookie-line-fault --------------------------------------------------
mutant('rule-latin-1', [(T, """((exists (lambda (c) (> c 255)) codes) 'not-latin-1)""",
                         """((exists (lambda (c) (> c #x10FFFF)) codes) 'not-latin-1)""")],
       COOKIES, ['every control char a load refuses'])

mutant('rule-7f', [(T, """(or (and (< c #x20) (not (= c 9))) (= c #x7F))""", """(or (and (< c #x20) (not (= c 9))) #f)""")],
       COOKIES, ['every control char a load refuses'])

mutant('rule-cr', [(T, """(or (and (< c #x20) (not (= c 9))) (= c #x7F))""", """(or (and (< c #x0D) (not (= c 9))) (= c #x7F))""")],
       COOKIES, ['every control char a load refuses'])

mutant('set-cookie-exact', [(T, """((string-starts? (ascii-folded line) "set-cookie:") 'set-cookie)""",
                             """((string-starts? line "Set-Cookie:") 'set-cookie)""")],
       COOKIES, ['a line starting Set-Cookie:'])


mutant('fields-eight', [(T, """(if (not (= (length fields) 7))""", """(if (not (>= (length fields) 7))""")],
       COOKIES, ['seven fields alone'])

mutant('domain-hash', [(T, """((or (= (string-length domain) 0) (char=? (string-ref domain 0) #\\#)) 'domain)""",
                        """((= (string-length domain) 0) 'domain)""")],
       COOKIES, ['the domain: #HttpOnly_ in that case exactly'])

mutant('httponly-any-case', [(T, """(domain (if (string-starts? given "#HttpOnly_")""",
                              """(domain (if (string-starts? (ascii-folded given) "#httponly_")""")],
       COOKIES, ['the domain: #HttpOnly_ in that case exactly'])

mutant('tail-any-case', [(T, """((not (member tail '("TRUE" "FALSE"))) 'tail-match)""",
                          """((not (member (ascii-folded tail) '("true" "false"))) 'tail-match)""")],
       COOKIES, ['the tail-match field is TRUE or FALSE exactly'])

mutant('leading-dot-off', [(T, """((not (eq? (char=? (string-ref domain 0) #\\.) (string=? tail "TRUE"))) 'leading-dot)""",
                            """(#f 'leading-dot)""")],
       COOKIES, ['a dot before the domain exactly when the tail-match is TRUE'])

mutant('path-off', [(T, """((not (string-starts? path "/")) 'path)""", """(#f 'path)""")],
       COOKIES, ['the path starts with /'])

mutant('secure-off', [(T, """((not (member secure '("TRUE" "FALSE"))) 'secure)""", """(#f 'secure)""")],
       COOKIES, ['the secure field is TRUE or FALSE exactly'])

mutant('expiry-no-limit', [(T, """(<= (string->number expiry 10) expiry-limit)""", """#t""")],
       COOKIES, ['the expiry is decimal digits'])

mutant('expiry-number', [(T, """((not (and (digits? expiry) (<= (string->number expiry 10) expiry-limit))) 'expiry)""",
                          """((not (let ((n (string->number expiry 10))) (and n (<= n expiry-limit)))) 'expiry)""")],
       COOKIES, ['the expiry is decimal digits'])

mutant('name-off', [(T, """((= (string-length name) 0) 'name)""", """(#f 'name)""")],
       COOKIES, ['a name: an empty one is name'])

mutant('size-one-more', [(T, """((> (+ (string-length name) (string-length value)) cookie-line-limit) 'size)""",
                          """((> (+ (string-length name) (string-length value)) (+ cookie-line-limit 1)) 'size)""")],
       COOKIES, ['the name and the value at most 4,096 chars together'])

mutant('size-name-only', [(T, """((> (+ (string-length name) (string-length value)) cookie-line-limit) 'size)""",
                           """((> (string-length name) cookie-line-limit) 'size)""")],
       COOKIES, ['the name and the value at most 4,096 chars together'])

mutant('rules-order', [(T, """        ((exists (lambda (c) (> c 255)) codes) 'not-latin-1)
        ((exists (lambda (c) (or (and (< c #x20) (not (= c 9))) (= c #x7F))) codes) 'control-byte)""",
                        """        ((exists (lambda (c) (or (and (< c #x20) (not (= c 9))) (= c #x7F))) codes) 'control-byte)
        ((exists (lambda (c) (> c 255)) codes) 'not-latin-1)""")],
       COOKIES, ['the rules in order'])

# --- the load and the read-out ---------------------------------------------------------
mutant('refusal-names-line', [(T, """                                (make-irritants-condition (list index rule))))))""",
                               """                                (make-irritants-condition (list index rule (car rest)))))))""")],
       COOKIES,
       ['cookie-line-bytes refuses the first line that breaks a rule', "no exit prints a cookie's value"])

mutant('load-partial', [(E, """    (let ((bytes (cookie-line-bytes who lines))
          (engine (cookie-jar-engine jar)))""", """    (let ((bytes (guard (e ((curl-request-error? e)
                            (reply-of who (cookie-jar-engine jar)
                                      (post-jar! (cookie-jar-engine jar) 'load jar
                                                 (cookie-line-bytes who (let take ((rest lines) (n (curl-request-error-value e)))
                                                                          (if (= n 0) '() (cons (car rest) (take (cdr rest) (- n 1))))))))
                            (raise e)))
                   (cookie-line-bytes who lines)))
          (engine (cookie-jar-engine jar)))""")],
       COOKIES, ['a load checks every line before it loads any'])

mutant('load-late-copy', [(E, """    (let ((bytes (cookie-line-bytes who lines))
          (engine (cookie-jar-engine jar)))
      (reply-of who engine (post-jar! engine 'load jar bytes))""", """    (let ((bytes (begin (cookie-line-bytes who lines) lines))
          (engine (cookie-jar-engine jar)))
      (reply-of who engine (post-jar! engine 'load jar bytes))"""),
                          (E, """                          (jar-load-lines! 'curl-cookie-jar-load! (cookie-jar-handle jar) arg""",
                           """                          (jar-load-lines! 'curl-cookie-jar-load! (cookie-jar-handle jar)
                                           (if (and (pair? arg) (string? (car arg))) (cookie-line-bytes 'curl-cookie-jar-load! arg) arg)""")],
       COOKIES, ['a load takes its copies as it is called'])

mutant('cookielist-unread', [(T, """                   (code (or answer given)))
              (unless (eqv? code curle-ok)
                (error who "libcurl refused a cookie line""", """                   (code curle-ok))
              (unless (eqv? code curle-ok)
                (error who "libcurl refused a cookie line""")],
       COOKIES, ["libcurl's every answer is read"])

mutant('readout-unread', [(T, """        (let ((code (or answer given)))
          (unless (eqv? code curle-ok)
            (error who "curl_easy_getinfo answered a CURLcode for CURLINFO_COOKIELIST" code)))""",
                           """        (let ((code curle-ok))
          (unless (eqv? code curle-ok)
            (error who "curl_easy_getinfo answered a CURLcode for CURLINFO_COOKIELIST" code)))""")],
       COOKIES, ["libcurl's every answer is read"])

mutant('share-setopt-unread', [(E, """                       (unless (or ops (eqv? code curlshe-ok))""", """                       (unless #t""")],
       COOKIES, ["libcurl's every answer is read"])

mutant('readout-utf8', [(E, """      (map bytes->latin-1 (reply-of who engine (post-jar! engine 'read jar #f)))))""",
                         """      (map utf8->string (reply-of who engine (post-jar! engine 'read jar #f)))))""")],
       COOKIES, ['bytes above 0x7F, Latin-1 both ways'])

mutant('load-utf8', [(T, """      (map (lambda (line) (u8-list->bytevector (map char->integer (string->list line)))) copies)))""",
                      """      (map string->utf8 copies)))""")],
       COOKIES, ['cookie-line-bytes: each line a Latin-1 copy', 'bytes above 0x7F, Latin-1 both ways'])

mutant('slist-not-freed', [(T, """        (unless (eqv? head 0) (curl-slist-free-all head))
        (let ((code (or answer given)))""", """        (let ((code (or answer given)))""")],
       COOKIES, ['every count is zero at the end'])

# --- the key, and cookie-beside-jar ----------------------------------------------------
mutant('key-untyped', [(T, """      (unless (or (not cookie-jar) (curl-cookie-jar? cookie-jar))""", """      (unless #t""")],
       COOKIES, ['cookie-jar: #f by default'])

mutant('beside-foldcase', [(T, """                  (when (member (ascii-folded (car header)) '("cookie" "host"))""",
                            """                  (when (member (string-foldcase (car header)) '("cookie" "host"))""")],
       COOKIES, ['the check folds A to Z alone'])

mutant('beside-first-only', [(T, """                    (refuse-field who 'header-name (car header) 'cookie-beside-jar)))
                headers)))""", """                    (refuse-field who 'header-name (car header) 'cookie-beside-jar)))
                (if (pair? headers) (list (car headers)) '()))))""")],
       COOKIES, ['beside a jar, a header named Cookie or Host'])

mutant('beside-no-host', [(T, """                  (when (member (ascii-folded (car header)) '("cookie" "host"))""",
                           """                  (when (member (ascii-folded (car header)) '("cookie"))""")],
       COOKIES, ['beside a jar, a header named Cookie or Host'])

mutant('beside-not-at-submit', [(T, """      (check-cookie-beside-jar who (unchecked-curl-request-cookie-jar request) (car fields))""", """      #f""")],
       COOKIES, ['a header renamed Cookie after the request was made'])

mutant('beside-not-at-make', [(T, """        (check-cookie-beside-jar who cookie-jar header-copies))""", """        #f)""")],
       COOKIES, ['beside a jar, a header named Cookie or Host'])

mutant('owned-no-cookielist', [(T, """              "COOKIE" "COOKIELIST" "COOKIESESSION")""", """              "COOKIE" "COOKIESESSION")""")],
       ['tests/test-unsupported.sps', 'tests/test-transfer.sps'],
       ['SHARE and COOKIEFILE, the cookie-jar field', 'owned-option-names, written out'])

mutant('field-options-swapped', [(T, """      (cookie-jar "SHARE" "COOKIEFILE")""", """      (cookie-jar "COOKIEFILE" "SHARE")""")],
       COOKIES + ['tests/test-transfer.sps'],
       ['the cookie-jar field sets SHARE then COOKIEFILE', 'request-field-options, written out'])

# --- printing --------------------------------------------------------------------------
mutant('jar-not-opaque', [(T, """    ;; #<curl-cookie-jar>.
    (opaque #t))""", """    ;; #<curl-cookie-jar>.
    (opaque #f))""")],
       COOKIES, ['a jar is opaque'])

mutant('response-not-opaque', [(T, """    ;; #<curl-response>.
    (opaque #t))""", """    ;; #<curl-response>.
    (opaque #f))""")],
       COOKIES, ["no exit prints a cookie's value"])

mutant('head-not-opaque', [(T, """    ;; Opaque, as a response is: its headers can hold a Set-Cookie.
    (opaque #t))""", """    ;; Opaque, as a response is: its headers can hold a Set-Cookie.
    (opaque #f))""")],
       COOKIES, ["no exit prints a cookie's value"])

mutant('accessor-unchecked', [(T, """  (define curl-request-cookie-jar
    (checked-accessor 'curl-request-cookie-jar curl-request? "a request" unchecked-curl-request-cookie-jar))""",
                               """  (define (curl-request-cookie-jar r) (unchecked-curl-request-cookie-jar r))""")],
       ['tests/test-printed.sps'], ['prints the password in what it raises'])

# --- natives and counts ----------------------------------------------------------------
mutant('kinds-no-share', [('src/curl/private/counters.sls', """(define native-kinds '(block easy url slist curl-string transfer multi share))""",
                           """(define native-kinds '(block easy url slist curl-string transfer multi))""")],
       ['tests/test-memory-safety.sps', 'tests/test-curl-testing.sps'],
       ['native-kinds: block, easy, url, slist, curl-string, transfer, multi and share'])

mutant('share-uncounted', [(N, """       (unless (eqv? share 0)
         (count-up! 'share)
         (own! share 'share))""", """       (unless (eqv? share 0)
         (own! share 'share))"""), (N, """       (when (eqv? code curlshe-ok)
         (count-down! 'share)
         (disown! share))""", """       (when (eqv? code curlshe-ok)
         (disown! share))""")],
       COOKIES, ['a jar is made on its engine, live, holding no transfer'])

mutant('share-counted-down-in-use', [(N, """       (when (eqv? code curlshe-ok)
         (count-down! 'share)
         (disown! share))""", """       (count-down! 'share)
       (when (eqv? code curlshe-ok)
         (disown! share))""")],
       COOKIES, ['a failed engine that abandons a live transfer'])

mutant('share-owner-unchecked', [(N, """    (check-owner 'curl-share-setopt share 'share)
""", "")],
       ['tests/test-native.sps'], ['every exported native procedure that takes a handle'])

mutant('cleanup-owner-unchecked', [(N, """    (check-owner 'curl-share-cleanup share 'share)
""", "")],
       ['tests/test-native.sps'], ['every exported native procedure that takes a handle'])

mutant('cookielist-owner-unchecked', [(N, """    (check-owner 'curl-easy-getinfo easy 'easy)
    (let ((slot #f))""", """    (let ((slot #f))""")],
       ['tests/test-native.sps'], ['every exported native procedure that takes a handle'])

mutant('slist-walk-owner-unchecked', [(N, """    (check-owner 'curl-slist-strings list 'slist)
""", "")],
       ['tests/test-native.sps'], ['every exported native procedure that takes a handle'])

mutant('share-setopt-value-lost', [(N, """    (raw-curl-share-setopt-int share option value))""", """    (raw-curl-share-setopt-int share option 2))""")],
       ['tests/test-variadic.sps'], [' through curl-share-setopt-int '])

mutant('share-setopt-plain', [(N, """    (load-step (bind-variadic "curl_share_setopt" (uptr int int) int info)))""",
                               """    (load-step (bind-required "curl_share_setopt" (uptr int int) int info)))""")],
       ['tests/test-collect-safe.sps'], ['curl_share_setopt once, for an int'])

mutant('cookielist-id-wrong', [('src/curl/private/constants.sls', """  (define curlinfo-cookielist #x40001C))""",
                                """  (define curlinfo-cookielist #x40001D))""")],
       ['tests/test-constants.sps'], ['curlinfo-cookielist is CURLINFO_COOKIELIST'])

mutant('slist-layout-swapped', [('src/curl/private/layouts.sls', """      (data uptr)
      (next uptr))))""", """      (next uptr)
      (data uptr))))""")],
       ['tests/test-constants.sps'], ["struct curl_slist.next has the header's offset", "struct curl_slist.data has the header's offset"])

# --- the high level --------------------------------------------------------------------
mutant('session-cookies-default', [('src/http-client/private/call.sls', """              (refuse 'make-http-session 'cookies (shown-value v) 'not-a-boolean "cookies is #t or #f"))
            v)
          #f)))""", """              (refuse 'make-http-session 'cookies (shown-value v) 'not-a-boolean "cookies is #t or #f"))
            v)
          #t)))""")],
       COOKIES, ['a session without cookies sends none and keeps none', 'of a session without cookies, an assertion violation'])

mutant('call-drops-jar', [('src/http-client/private/call.sls', """                                   'cookie-jar (curl-request-cookie-jar defaults))""",
                           """                                   'cookie-jar #f)""")],
       COOKIES, ['a session with cookies: its calls carry the jar'])

mutant('hop-drops-jar', [('src/http-client/private/exchange.sls', """                         'cookie-jar (curl-request-cookie-jar last))))""",
                          """                         'cookie-jar #f)))""")],
       COOKIES, ["a redirect's hops carry the session's jar"])

mutant('session-on-no-stop', [('src/http-client/private/call.sls', """                    (guard (e (#t (curl-engine-stop engine) (raise e)))""",
                               """                    (guard (e (#t (raise e)))""")],
       COOKIES, ["a session's Cookie or Host header beside its cookies is refused"])

# --- the origin ------------------------------------------------------------------------
mutant('origin-cookies-joined', [('tests/origin.mjs', """    if (name === 'cookie') cookies.push(pairs[i + 1]);""",
                                  """    if (name === 'cookie') { if (cookies.length > 0) cookies[0] += `; ${pairs[i + 1]}`; else cookies.push(pairs[i + 1]); }""")],
       ['tests/test-origin.sps'], ['the cookie route: each set='])

mutant('origin-no-open-head', [('tests/origin.mjs', """      if (pending.length > 0) openHead(face, pending);""", """      void openHead;""")],
       ['tests/test-origin.sps'], ['a head left open as its connection closes'])

mutant('origin-set-cookie-utf8', [('tests/origin.mjs', """  for (const bytes of r.set) headers.push('Set-Cookie', bytes.toString('latin1'));""",
                                   """  for (const bytes of r.set) headers.push('Set-Cookie', bytes.toString('utf8'));""")],
       ['tests/test-origin.sps'], ['the cookie route: each set='])


# --- the written-out lists, and the rest ---------------------------------------------
mutant('reason-missing', [('src/curl/private/conditions.sls', """      cookie-line cookie-jar-engine cookie-jar-closed cookie-beside-jar))""",
                            """      cookie-line cookie-jar-engine cookie-jar-closed))""")],
       ['tests/test-conditions.sps'], ['the request-error reasons are exactly'])

mutant('cookies-a-call-key', [('src/http-client/private/call.sls', """  (define call-keys (append request-session-keys policy-keys '(body form params body-length)))""",
                                """  (define call-keys (append request-session-keys policy-keys '(cookies body form params body-length)))""")],
       ['tests/test-http-client.sps'], ['the keys, written out'])

mutant('http-response-not-opaque', [('src/http-client/private/exchange.sls', """    ;; section 3.5). A response prints as #<http-response>.
    (opaque #t))""", """    ;; section 3.5). A response prints as #<http-response>.
    (opaque #f))""")],
       COOKIES, ["no exit prints a cookie's value"])

mutant('share-cleanup-proto', [(N, """    (load-step (bind-required "curl_share_cleanup" (uptr) int info)))""",
                                """    (load-step (bind-required "curl_share_cleanup" (uptr) uptr info)))""")],
       ['tests/test-constants.sps'], ['prototype: "curl_share_cleanup" bound through bind-required'])

mutant('conventions-row-missing', [('tests/foreign-conventions.sls', """          (list "curl_share_init" '() cannot-block)
""", "")],
       ['tests/test-collect-safe.sps'], ['src/ holds to the table: no violation'])

mutant('origin-accepts-ctl', [('tests/origin.mjs', """      if (bytes === null || bytes.some((b) => (b < 0x20 && b !== 0x09) || b === 0x7f)) return null;""",
                               """      if (bytes === null) return null;""")],
       ['tests/test-origin.sps'], ['the cookie route refuses, 404'])

# --- the fix round: decisions 10 and 12, and the review's four survivors ------------------
mutant('prefix-off', [(T, """                   ((prefix-broken? name tail path secure) 'prefix)""",
                       """                   (#f 'prefix)""")],
       COOKIES, ['a __Secure- name, in every one of its 64 A to Z cases', 'a __Host- name, in every one of its 16 A to Z cases'])

mutant('prefix-own-case', [(T, """    (let ((folded (ascii-folded name)))
      (cond ((string-starts? folded "__secure-") (not (string=? secure "TRUE")))
            ((string-starts? folded "__host-")""", """    (let ((folded name))
      (cond ((string-starts? folded "__Secure-") (not (string=? secure "TRUE")))
            ((string-starts? folded "__Host-")""")],
       COOKIES, ['a __Secure- name, in every one of its 64 A to Z cases', 'a __Host- name, in every one of its 16 A to Z cases'])

mutant('secure-prefix-unchecked', [(T, """      (cond ((string-starts? folded "__secure-") (not (string=? secure "TRUE")))""",
                                    """      (cond ((string-starts? folded "__secure-") #f)""")],
       COOKIES, ['a __Secure- name, in every one of its 64 A to Z cases'])

mutant('host-secure-unchecked', [(T, """             (not (and (string=? secure "TRUE") (string=? path "/") (string=? tail "FALSE"))))""",
                                  """             (not (and #t (string=? path "/") (string=? tail "FALSE"))))""")],
       COOKIES, ['a __Host- name, in every one of its 16 A to Z cases'])

mutant('host-path-unchecked', [(T, """             (not (and (string=? secure "TRUE") (string=? path "/") (string=? tail "FALSE"))))""",
                                """             (not (and (string=? secure "TRUE") #t (string=? tail "FALSE"))))""")],
       COOKIES, ['a __Host- name, in every one of its 16 A to Z cases'])

mutant('host-tail-unchecked', [(T, """             (not (and (string=? secure "TRUE") (string=? path "/") (string=? tail "FALSE"))))""",
                                """             (not (and (string=? secure "TRUE") (string=? path "/") #t)))""")],
       COOKIES, ['a __Host- name, in every one of its 16 A to Z cases'])

mutant('prefix-without-dash', [(T, """      (cond ((string-starts? folded "__secure-") (not (string=? secure "TRUE")))""",
                                """      (cond ((string-starts? folded "__secure") (not (string=? secure "TRUE")))""")],
       COOKIES, ['a name that only nearly holds a prefix is taken'])

mutant('separator-off', [(T, """                   ((or (string-holds? name #\\;) (string-holds? name #\\=) (string-holds? value #\\;))
                    'separator)""", """                   (#f
                    'separator)""")],
       COOKIES, ['a ; in the name or the value, or an = in the name'])

mutant('separator-name-semicolon', [(T, """((or (string-holds? name #\\;) (string-holds? name #\\=) (string-holds? value #\\;))""",
                                     """((or #f (string-holds? name #\\=) (string-holds? value #\\;))""")],
       COOKIES, ['a ; in the name or the value, or an = in the name'])

mutant('separator-name-equals', [(T, """((or (string-holds? name #\\;) (string-holds? name #\\=) (string-holds? value #\\;))""",
                                  """((or (string-holds? name #\\;) #f (string-holds? value #\\;))""")],
       COOKIES, ['a ; in the name or the value, or an = in the name'])

mutant('separator-value-semicolon', [(T, """((or (string-holds? name #\\;) (string-holds? name #\\=) (string-holds? value #\\;))""",
                                      """((or (string-holds? name #\\;) (string-holds? name #\\=) #f)""")],
       COOKIES, ['a ; in the name or the value, or an = in the name'])

mutant('separator-value-equals', [(T, """((or (string-holds? name #\\;) (string-holds? name #\\=) (string-holds? value #\\;))""",
                                   """((or (string-holds? name #\\;) (string-holds? name #\\=) (string-holds? value #\\;) (string-holds? value #\\=))""")],
       COOKIES, ['a ; in the name or the value, or an = in the name'])

mutant('separator-first-only', [(T, """    (exists (lambda (x) (char=? x c)) (string->list s)))""",
                                 """    (and (> (string-length s) 0) (char=? (string-ref s 0) c)))""")],
       COOKIES, ['a ; in the name or the value, or an = in the name'])

mutant('separator-after-size', [(T, """                   ((or (string-holds? name #\\;) (string-holds? name #\\=) (string-holds? value #\\;))
                    'separator)
                   ((> (+ (string-length name) (string-length value)) cookie-line-limit) 'size)""",
                                 """                   ((> (+ (string-length name) (string-length value)) cookie-line-limit) 'size)
                   ((or (string-holds? name #\\;) (string-holds? name #\\=) (string-holds? value #\\;))
                    'separator)""")],
       COOKIES, ['the rules in order'])

# The review's four survivors (.plans/research/m7/slice4/review/mutants.py).
mutant('fail-batch-unanswered', [(E, "(answer-jar-messages! engine (append (engine-batch engine) queued) failure)",
                                  "(answer-jar-messages! engine queued failure)")],
       COOKIES, ['a load and a read-out queued in one hold behind a submit whose set-up fails the engine'])

mutant('control-enumerated', [(T, "((exists (lambda (c) (or (and (< c #x20) (not (= c 9))) (= c #x7F))) codes) 'control-byte)",
                               "((exists (lambda (c) (memv c '(0 1 10 13 31 127))) codes) 'control-byte)")],
       COOKIES, ['every control char a load refuses'])

mutant('expiry-char-numeric', [(T, "(for-all (lambda (c) (char<=? #\\0 c #\\9)) (string->list s))",
                                "(for-all char-numeric? (string->list s))")],
       COOKIES, ['the expiry against every Latin-1 char but the ten digits'])

mutant('release-twice', [(E, """                            (hashtable-delete! (engine-holds engine) token)
                            (cookie-jar-holders-set! jar (- (cookie-jar-holders jar) 1))""",
                          """                            (cookie-jar-holders-set! jar (- (cookie-jar-holders jar) 1))""")],
       COOKIES, ["a fault after take-out! has let a transfer's hold go"])

ROOT = os.getcwd()
MUT = os.path.join(ROOT, 'build/m7s4b/mut')


def control_suites():
    found = []
    for m in M:
        for s in (m['suites'] or []):
            if s not in found:
                found.append(s)
    return found


def make(names):
    os.makedirs(MUT, exist_ok=True)
    jobs = []
    for m in M:
        if names and m['name'] not in names:
            continue
        dest = os.path.join(MUT, m['name'])
        os.makedirs(dest, exist_ok=True)
        subprocess.run(['rsync', '-a', '--delete', '--exclude', '/build', '--exclude', '/.git',
                        '--exclude', '/.plans/research', '--exclude', '/logs', './', dest + '/'], check=True)
        # A child Chez a suite spawns names build/scheme-libs relative to
        # the copy: the tree's own, linked.
        os.makedirs(os.path.join(dest, 'build'), exist_ok=True)
        link = os.path.join(dest, 'build', 'scheme-libs')
        if not os.path.islink(link):
            os.symlink(os.path.join(ROOT, 'build', 'scheme-libs'), link)
        for rel, old, new in m['edits']:
            path = os.path.join(dest, rel)
            text = open(path, encoding='latin-1').read()
            n = text.count(old)
            if n != 1:
                sys.exit(f"mutants: {m['name']}: OLD stands {n} times in {rel}: {old[:60]!r}")
            open(path, 'w', encoding='latin-1').write(text.replace(old, new))
        suites = m['suites'] if m['suites'] is not None else control_suites()
        for s in suites:
            jobs.append(f"{m['name']} {s}")
    open(os.path.join(MUT, 'jobs'), 'w').write('\n'.join(jobs) + '\n')
    print(f'mutants: {len(jobs)} jobs in build/m7s4b/mut/jobs')


def fails(name, suite):
    log = os.path.join(MUT, name, 'logs', os.path.basename(suite).replace('.sps', '.log'))
    if not os.path.exists(log):
        return None, []
    lines = open(log, encoding='latin-1').read().splitlines()
    status = lines[-1] if lines else 'empty'
    return status, [l[5:] for l in lines if l.startswith('FAIL ')]


def check(names):
    killed = survived = 0
    for m in M:
        if names and m['name'] not in names:
            continue
        suites = m['suites'] if m['suites'] is not None else control_suites()
        all_fails = []
        statuses = []
        for s in suites:
            status, f = fails(m['name'], s)
            statuses.append(f'{os.path.basename(s)}: {status}')
            all_fails.extend((os.path.basename(s), x) for x in f)
        if m['name'] == 'control':
            ok = not all_fails and all(st.endswith('exit 0') for st in statuses)
            print(f"control: {'pass' if ok else 'FAIL'}; " + '; '.join(statuses))
            for s, f in all_fails:
                print(f'    {s}: FAIL {f[:160]}')
            continue
        missing = [e for e in m['expect'] if not any(e in f for _, f in all_fails)]
        verdict = 'killed' if not missing and all_fails else 'SURVIVED'
        if verdict == 'killed':
            killed += 1
        else:
            survived += 1
        print(f"{m['name']}: {verdict}; " + '; '.join(statuses))
        for s, f in all_fails:
            print(f'    {s}: FAIL {f[:200]}')
        for e in missing:
            print(f'    expected and not seen: {e}')
    print(f'mutants: {killed} killed, {survived} survived')


if __name__ == '__main__':
    cmd, names = sys.argv[1], sys.argv[2:]
    if cmd == 'make':
        make(names)
    elif cmd == 'check':
        check(names)
    else:
        sys.exit(__doc__)
