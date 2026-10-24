# Transfer mutation log (M2 slice 2)

- **Date:** 2026-10-23, branch `m2/blocking-transfer`, on top of `fb1a5cb`, in the container
  (Chez 10.4.0, libcurl 8.20.0 with GnuTLS 3.8.13, Node 24.18.0).
- **Plan:** [M2 plan](2026-10-19-m2-plan.md) §5. The amendments this slice needs are the lead's
  to write.
- **Harness (scratch, not kept):** `build/verify/m2s2/work/mutate.py` copies `src/`, `tests/`
  and `.plans/` into `build/verify/m2s2/mut/NAME/`, applies one edit, and refuses an edit whose
  old text is absent or appears more than once. `run-mutants.sh` runs each mutant's named suites
  in its own tree, one at a time, each with its own exit status and output. A mutant counts as
  caught only when a suite exits non-zero with a `FAIL` line naming a test.
- **Result:** 44 mutants, 46 runs, all caught by a named test, on the final tree. Two needed new
  tests first (below, marked *first run*).

## The brief's mutations

- `lock-object` removed: caught, 3 runs of 3, by `the lock: a 50-byte drip, 10 ms apart, beside a thread that collects every 2 ms...` alone: `(refused perform-failed 23)`, the hook never called, so a collection moved write-body before its first chunk. A run on the tree before the last tests were added failed 38 tests: every transfer after the first collection answered 23, with nothing recorded.
- the guard removed from write-body: caught, by `a raise inside the callable, through CHUNK-HOOK: callback-raised, 23, recording the very object raised...`.
- the limit check removed: caught, by `body limit 10 against http /status/200: (refused body-limit 23)...` and 12 more.
- the limit's `>` made `>=`: caught, by `body limit 11 against http /status/200: (response 200 ...)...` and 7 more.
- `MAXFILESIZE_LARGE` set to the limit, not limit+1: caught, by `body limit 10 against http /status/200: (refused body-limit 23)...` and 12 more.
- the slist not freed: caught, by `a request header whose value holds every char U+0001 to U+00FF but CR and LF arrives in /raw/echo byte for byte...` and 32 more (the slist count left at 1).
- the error buffer not freed: caught, by `shared: GET http /status/200, whole, and the counts back at zero` and 86 more (a block left).
- `NOBODY` ignored: caught, by `NOBODY: head of /echo gets no body...` and `NOBODY: head of /status/200 gets its headers and no body`.
- `USERAGENT` copied as UTF-8: caught, by `USERAGENT: chars U+0080 to U+00FF arrive in /raw/echo as exactly those bytes...`.
- response headers decoded as UTF-8: caught, by `shared: GET raw /raw/header-bytes, whole, and the counts back at zero`.
- the value scan cut to its first position (header value and user agent): caught, by `a header value with U+0 at each of its places, and alone, is refused as embedded-nul...` and 14 more.
- the token scan cut to its first position: caught, by `every char from U+0000 to U+00FF that is no tchar ... is refused as not-a-token...` and 3 more.
- the header-list scan cut to its first header: caught, by `every header is checked, the last of three among them, and the user agent after them`.
- the token allowlist narrowed (`~` dropped): caught, by `every tchar, alone, and all of them together, is a name the request takes`.
- the token allowlist widened (`char-alphabetic?` for a-z): caught, by `every char from U+0000 to U+00FF that is no tchar...` and `a name's offending char at each place is refused...`.
- the token allowlist widened (`:` added): caught, by the same two and 2 more.
- `bind-blocking`'s `__collect_safe` removed: caught, by `src/ holds to the table: no violation` and `the scan of src/ finds curl_easy_perform bound once, through bind-blocking, with __collect_safe`.
- `curl_easy_perform` bound through `bind-required`: caught, by the same two.
- write-body's `__collect_safe` removed: caught, by `src/ holds to the table: no violation` and `the scan of src/ finds write-body defined once, a foreign-callable with __collect_safe...`.
- a seam addition loosened (`lock-object` also allowed to `(curl private native)`): caught, by `callable-elsewhere: rule (f): ...` and `each library-only-chez-names entry lists exactly the libraries under src/ that import its name`.
- a seam addition loosened (`foreign-callable`'s entry removed): caught, by `callable-elsewhere: rule (f): ...`.
- `LONG` sent to the off-t binding, in `option-bindings`: caught, by `option-bindings: long and values to the long binding...` and `option-binding: each CURLOT code to its binding...`.
- `LONG` sent to the off-t binding, in `option-setter`: caught, by `option-setter: long is native's curl-easy-setopt-long...`.
- a version row's answer changed (8.20.0's conflicting-content-length 8 made 18): caught, by `varying: GET raw /raw/conflicting-content-length, as this libcurl's row says...`.
- a shared answer changed (short-body's 18 made 56): caught, by `shared: GET raw /raw/short-body, whole, and the counts back at zero`.
- `nextheader` with request 0, not -1: caught, by `with FOLLOWLOCATION set through perform-transfer-with, a followed redirect answers the last request's status, headers and body...`.
- the CURLU freed before the easy handle is cleaned up (the easy handle's extent made outermost): caught, by `re-entering a transfer through a continuation captured in CHUNK-HOOK raises from call-with-parsed-url, the outermost extent...` and `perform-transfer-with's extents each stand once, each inside exactly those before it...`. *First run:* survived, 133 of 133 passing, natively and under the memory gate's Valgrind options (0 errors, nothing definitely lost): 8.20.0's `curl_easy_cleanup` reads no CURLU it was handed. Both tests were added for it.

## Rules nothing above covers

- `make-curl-request-error` takes any reason: caught, by `the request-error constructor refuses a symbol that is no reason...`.
- `make-curl-transfer-error` takes any reason: caught, by `the transfer-error constructor refuses a symbol that is no reason...`.
- `call-with-latin-1-c-string`'s scan cut to its first position: caught, by `call-with-latin-1-c-string refuses "a\x0;b" as &curl-embedded-nul...` and 6 more.
- `call-with-latin-1-c-string` copying UTF-8: caught, by `call-with-latin-1-c-string hands C one byte per char and a NUL...` and `...writes the NUL itself...`.
- `curl-slist-append` counting every append: caught, by `a string list is counted slist once it holds a string, still once after a second...` and 87 more (counts left). *First run:* the suite died with glibc's `free(): invalid pointer`, exit 134, and no test named: the extra count let the test's second free reach C. The test now tries that free only once the count reads zero.
- `curl-header`'s last field, `anchor`, dropped: caught, by `curl-header is the whole of struct curl_header: its ftype-sizeof is sizeof(struct curl_header)`.
- `curl_easy_nextheader`'s `unsigned int` origin bound `int`: caught, by `prototype: "curl_easy_nextheader" bound through bind-required as (uptr int int uptr) -> uptr fits a declaration its row gives`.
- write-body's `void *` parameter typed `int`: caught, by `callable: write-body defined through foreign-callable as (uptr size_t size_t int) -> size_t fits its typedef's declaration`.
- `curl_easy_nextheader` bound without `required-entry`: caught, by `decoy lacks-curl_easy_nextheader: a library without curl_easy_nextheader is missing-api, naming it`.
- the effective URL read as Latin-1: caught, by `the effective URL: ... é in a path reads back as é`.
- `CURL_HTTP_VERSION_1_1` read as `http/1.0`: caught, by `http-version-symbol: ...` and 43 more, every HTTP/1.1 answer.
- the raised object dropped from `callback-raised`: caught, by `a raise inside the callable, through CHUNK-HOOK: ... recording the very object raised...`.
- an unknown option taken as id 0: caught, by `an option the loaded libcurl does not know raises unknown-option, naming it...`.
- setopt's code unchecked: caught, by `an option libcurl refuses raises setopt-failed, naming it, with its code...`.
- the easy handle's extent made to enclose the header list's (the slist freed first): caught, by `perform-transfer-with's extents each stand once, each inside exactly those before it...`.
- `call-with-parsed-url`'s re-entry check removed: caught, by `re-entering a transfer through a continuation ... raises from call-with-parsed-url...` (the next extent in, `call-with-sink`, refused instead).
- the origin's `header-bytes` script ending at 0xFE: caught, by `raw /raw/header-bytes: the whole bytes, then eof`. The run also failed the two SIGKILL lifecycle tests, an artifact of the copy: their child Chez is started with `--libdirs src:tests:build/scheme-libs`, and the copy has no `build/`. Both pass in the checkout.

## Fix round 1

- **Date:** 2026-10-23, the same branch, in the container. Harness: `mutate2.py` and
  `run-mutants.sh`, into `build/verify/m2s2/mut2/` (scratch). The review's probes are in
  `build/verify/m2s2/review/`.
- **New tests watched failing first:** the round's tests were run against the old `src/`,
  kept unchanged in `build/verify/m2s2/mut/header-bytes-script-changed/`. Its
  `transfer.sls` gained only the four new exports, defined as the old code would answer
  them. 17 tests failed by name there: every whitespace, empty-agent, duplicates-field,
  changed-request, seam, escape, socket, option-cache and race test. The rest hold rules
  the old code already kept, and each mutant below shows them failing. The hermetic test
  was watched failing with `http_proxy=http://127.0.0.1:9`: it named `("http_proxy")`, and
  92 other tests failed, their transfers sent to the proxy.
- **Result:** 35 mutants, 36 runs, every one caught by a named test once the race tests were
  strengthened (below).

### 1. A check on a caller's mutable data, then a use of it

- the snapshot not taken (the request's own lists and strings sent): caught, by `a request changed after it was made is refused by perform-transfer, at each field...` and `a header value another thread flips between c and CR...`.
- the snapshot checked, the originals sent: caught, 3 runs of 3, by `a header value another thread flips between c and CR while 300 transfers run...`. *First run:* survived 1 of 2 at 30 transfers, then 1 of 4 at 100. The flipper flipped 500 times, then slept; 187 of 200 transfers were refused, and 1 injected. A flipper that never slept injected 42 of 200, but held Valgrind's one running thread for over 10 minutes. The flipper now flips 1,000,000 times between sleeps of no time: measured, 21 of 300 injected natively, and 300 transfers took 13 s under the gate's Valgrind, both outcomes seen.
- `call-with-c-string` checking the caller's string, not its copy: caught, 3 runs of 3, by `call-with-c-string, while another thread flips a char of its string to U+0000...`, with at least 82 cut strings in 2000 calls each run. *First run:* 2 to 5 cut in 300 calls, while the flipper slept between bursts of 500.
- `call-with-latin-1-c-string` likewise: caught, 3 runs of 3, by its U+0000 and U+0100 tests, with at least 52 odd outcomes each run.
- url's `checked-input` checking the caller's string: caught, 3 runs of 3, by `url-normalize, while another thread flips a char of its URL to U+0000...`, with at least 91 of call-with-c-string's own `&curl-embedded-nul` in place of the URL refusal each run. (These counts are from the failing test's printed value, which the suite cuts at 3000 characters, so each is a floor.)
- **The race tests' shape, measured** (`flip-probe.sps`, scratch): the flipper flips 100,000 times between sleeps of no time, once in each state, and the caller yields before every tenth call. Natively that gave 128 cut strings in 2000 calls of the mutant; under the gate's Valgrind, which runs one thread at a time, the 2000 calls took 1.8 s with both states seen. Without the yields Valgrind saw only one state; with a flipper that never slept, test-memory-safety ran over 13 minutes there.
- the option name never copied, in `checked-settings` and in `option-named`: caught, by `the option cache keeps a copy of each name...`. Removing one copy alone leaves the other, so each is a backstop for the other, and neither alone fails a test.

### 2. Control leaving write-body other than by its return

- `call-hook`'s after thunk not raising on an escape: caught, by `CHUNK-HOOK escaping through a continuation captured outside the transfer...`, `...an earlier chunk's continuation from a later chunk...` and `after both, this process holds as many sockets as before...`.
- the hook called bare, outside `call-hook`: caught, by the same three.
- `call-hook`'s inner guard removed, so a raise from the hook reads as an escape: caught, by `a raise inside the callable, through CHUNK-HOOK: ... recording the very object raised...`.
- `call-hook`'s before thunk, which refuses a re-entry, is a backstop no route reaches: an escape leaves through the after thunk first, and a re-entry from outside the transfer meets the outermost extent's refusal first. No mutant of it was made.

### 3. The test seam, held to ADR-0009's rules, narrowed

- the owned check removed: caught, by `the test seam refuses each owned option this libcurl knows, by id...` and `an alias of an owned option is refused as owned-option...`.
- the type check removed: caught, by `the test seam refuses an option of every other CURLOT type as unsupported-type...`.
- the range check removed: caught, by `the test seam's values are checked before anything native...`.
- the owned check made by name, not id: caught, by `an alias of an owned option is refused as owned-option: FILE is WRITEDATA's id, and RTSPHEADER HTTPHEADER's`.
- the twin `PUT` dropped from the deny-list: caught, by `owned-option-names, written out...`.
- the request fields' options left off the deny-list: caught, by `owned-option-names, written out...`, `every request field's option is an owned option...` and the alias test.

### 4. The always-set options

- `PROTOCOLS_STR` removed: caught, by `perform-transfer-with sets PROTOCOLS_STR and REDIR_PROTOCOLS_STR to "http,https", and NOSIGNAL to 1, each exactly once...`. The redirect test passes on it: `REDIR_PROTOCOLS_STR` still refuses the FTP redirect.
- `REDIR_PROTOCOLS_STR` removed: caught, by the same structural test. The redirect test passes on it too: `PROTOCOLS_STR` still refuses FTP, since libcurl checks a followed URL against both.
- `NOSIGNAL` removed: caught, by the structural test.
- both pins removed: caught, by the structural test and `REDIR_PROTOCOLS_STR, observed: FOLLOWLOCATION through the test seam, to ftp://127.0.0.1:1/...`.
- `PROTOCOLS_STR` set only inside a `when`: caught, by the structural test.

### 5. Whitespace, the empty user agent, and a User-Agent header

- the ends unchecked: caught, by the four `... with SP/HTAB/VT/FF first, last, ... are refused as surrounding-whitespace...` tests and the changed-request test.
- the ends checked before the char scan: caught, by `the char scan comes first...`.
- VT and FF left out: caught, by the VT and FF tests.
- U+00A0 added to the set: caught, by `whitespace inside a value is the value's: ... U+00A0, at the ends, are each taken...`.
- duplicates-field unchecked: caught, by `a header named User-Agent, in any case, beside a user agent, is refused as duplicates-field...`.
- duplicates-field compared by case: caught, by the same test.
- an empty user agent taken: caught, by `an empty user agent is an assertion violation...`.

### 7. The review's survivors

- `timeout-x10`: caught, by both `TIMEOUT_MS 300 against ...: 28, no sooner than 300 ms and sooner than 600`. The bound: 301 to 304 ms natively, 303 to 386 ms under the gate's Valgrind, 8 runs of each.
- `timeout-x2`: caught, by the same two.
- `errbuf-uncut`: caught, by `libcurl's texts for reset-after-pause: ...` and 12 more.
- `strerror-of-0`: caught, by the same 13.
- `sink-never-deleted`: caught, by `shared: GET http /status/200, whole, and the counts back at zero` and 85 more: the count falls only when a key is removed, so a table that keeps its keys keeps its count.
- the count lowered while the key is kept, the old code's way: caught, by `inside the callable, ... and the live-transfer table holds it...` and `once every transfer has ended, the live-transfer table is empty...`.
- `shared-in-rows`, short-body moved into every row: caught, by `each varying case has different answers in two rows at least...`.
- the same in test-url, 7.85.0's `a b` made 3, as 8.5.0's and 8.20.0's: caught, by test-url's test of the same name.

### The review's probes, rerun on the fixed tree

- `escape-only.sps`, under the gate's Valgrind options: the escape is refused, and the
  transfer raises `callback-raised` (uncaught there, so exit 255); `definitely lost: 0 bytes
  in 0 blocks`, `ERROR SUMMARY: 0 errors`. It was 744 bytes definitely lost.
- `escape-fds.sps`: stops at its first escape, which now raises. A copy with each escape
  guarded (`work/escape-fds-guarded.sps`): `sockets: before 0, after 5 returns 0, after 5
  escapes 0`, counts all zero.
- `stale.sps`: `(raised "... Failed writing received data to disk/application") calls 2`,
  counts all zero: `callback-raised`, 23, never "attempt to return to stale foreign context".
- `seam-raw.sps`: `PROTOCOLS` and `REDIR_PROTOCOLS` -1 refused as owned-option before
  anything native; the control, FOLLOWLOCATION alone to `file:///etc/passwd`, `Unsupported
  protocol`; `WRITEFUNCTION` 0 refused as owned-option. Both cases refused.
- `ws-header.sps`: refused at its first case, `(("X-Space" . " "))`, as surrounding-whitespace;
  each later case is refused by its own test in test-transfer.
- `proxy.sps`: with no proxy variable, 200; with `http_proxy=http://127.0.0.1:9`, `(refused
  perform-failed 7)`: the transfer still goes to the proxy, which is M4's policy, and
  test-transfer's first test names the variable.

## Fix round 2

- **Date:** 2026-10-24, the same branch, in the container. Harness: `mutate3.py` and
  `run-shard.sh` (four shards at once), into `build/verify/m2s2/mut5/` (scratch). The
  review's probes are in `build/verify/m2s2/review2/`.
- **New tests watched failing first:** against round 1's code (`work/r2/oldtree`), the Host,
  option-name U+0000 and three structural pin tests failed; the scenarios' block died with
  `Exception in raise: no engine active`, and the live table read 1; test-url's and
  test-memory-safety's four sweeps failed. The lock tests failed against this round's tree
  before `locked`: `other-thread-blocked` in both suites, and `(no-definition locked)` in
  each structural test.
- **Result:** 33 mutants, 33 runs. 26 caught by a named test; 7 survive, each a backstop
  (below).

### A finding past the brief: a mutex held across an engine's expiry

The first run (`mut3/`) had 4 of 11 test-transfer mutants hung at the 600 s bound,
3 of them by no test named. One rerun, with a flushed line as each test began, stopped in
`two threads, each with its own transfer, at once`. From /proc, all four threads were in
futex waits, and the two transfer threads waited on one heap mutex. Chez's `with-mutex`
takes its mutex in a plain dynamic-wind's before thunk. An engine that runs out between
the take and the wind leaves the mutex held, with no after thunk to release it.
`work/r2/lockleak.sps`, sweeping at step 1, found this in each of `live-transfer-count`,
`cached-option-names` and `native-counts`. After each, another thread was
`other-thread-blocked`. Chez's mutexes are recursive, so the thread that leaked a mutex
never blocks on it. The mutants had only moved where the step-13 sweep's expiries fell.
With the fix, every mutex in transfer.sls, counters.sls and memory.sls is held through
`locked`, `(critical-section (with-mutex lock (thunk)))`, and the probe prints
`other-thread-ran` for all three. The sweeps over transfers now run at every tick: about
800 engines in 29 ms natively. test-transfer flushes each verdict, and its sweeps and
timers run under a guard.

### 1. Asynchronous escapes

- `perform-not-critical`: caught, by `a transfer in an engine that runs out at every tick...`, the timer test, and `...as many sockets as before` (before 0, after 14).
- `get-part-old-shape`, `url-handle-not-critical`: caught, by test-url's url-normalize and url-resolve sweeps.
- `c-bytes-block-before-extent`, `c-bytes-not-critical`: caught, by both C-string sweeps.
- `within-not-critical`, `within-make-before-extent`: caught, by the every-tick sweep, the refused-at-connect sweep and the timer test. `within-make-before-extent` survived the step-13 sweep in `mut4/`, and that is why the sweeps now run at every tick.
- `getinfo-long-slot-before-extent`, `getinfo-string-slot-before-extent`: caught, by the same three.
- `transfer-locked-not-critical`, `option-named-bare-mutex`, `live-count-bare-mutex`: caught, by `locked, read from transfer.sls...`, the lock sweep and `after the sweep and the timers, no mutex is left held...`. Each then hangs at its bound in the two-threads test, as designed: the failures are named first.
- `counters-locked-not-critical`, `native-counts-bare-mutex`: caught, by test-memory-safety's native-counts sweep and `locked, read from src/curl/private/counters.sls...`. `memory-locked-not-critical`: caught, by memory.sls's structural test.
- **Survived, as backstops:** `block-not-critical`, `free-block-not-critical`, `url-get-count-not-critical`, `curl-url-wrapper-not-critical`, `curl-free-not-critical`, `easy-init-not-critical` and `slist-record-not-critical`. Each wrapper's every caller already runs it inside a critical extent, and an engine or timer counts no tick inside one. In the slist record, no procedure call lies between the append's return and its record, so no safe point either. They guard keyboard interrupts and collect requests, which no test can place. Seen directly, such a leak is uncounted, so only Valgrind would see it.

### 2. Host

- `second-host-unchecked`, `host-case-sensitive`: caught, by `a second Host header, in any case, is refused as duplicates-field...`.

### 3. The pins

- `pin-in-body-after-perform`, `pin-uncalled-lambda`: caught, by `the easy handle's extent sets the pins first...` and the observed REDIR test.
- `protocols-undone`, `redir-undone`: caught, by `the names PROTOCOLS_STR, ... stand in transfer.sls only as quoted data...`.
- `pins-numbers-skipped`: caught, by `set-pinned-options!, read from transfer.sls, is exactly the loop...`.
- `pins-widened`: caught, by `pinned-options, written out...`.

### 5 and 6. The user agent and curl-easy-option

- `agent-original-sent`: caught, by `a user agent another thread flips between c and CR while 300 transfers run...`.
- `option-nul-unchecked`: caught, by the U+0000 test and the race test. `option-original-passed`: caught, by `curl-easy-option, while another thread flips a char of its name to U+0000...`.

### The probes, rerun on the final tree

- `engine4.sps`: at 300, `EXPIRED with 0 chunks in`; at 1100, 1300 and 1700, `complete
  (response 40); hook calls 40`. Counts all 0, live 0 and sockets 0 to 0 in every run.
  Under the gate's Valgrind, at 1100 and at 1300, the transfer completes, with
  `definitely lost: 0 bytes in 0 blocks` and `ERROR SUMMARY: 0 errors`.
- `optnul.sps`: `Exception in curl-easy-option: an option's name holds U+0000 with irritant
  "URL\x0;junk"`.
- `rewrites.sps` and `work/r2/rewrites-more.sps`:
  - two Hosts, in any case, are refused as duplicates-field;
  - one Host is sent first, `Host: a.example`, ahead of Accept;
  - everything else goes out as given, in order, repeats kept: Accept ×2, Connection ×2,
    User-Agent ×2, Cookie ×2, Authorization, Content-Type, TE, Proxy-Connection,
    `Expect: 100-continue`, and the empty Expect as `Expect:`;
  - `Content-Length: 5` and `Transfer-Encoding: chunked` go out on a GET, unrefused, so a
    server waits for a body that never comes.
- check-variadic stand-ins (`work/r2/cv/run.sh`, check-variadic.sh unchanged since):
  - norow: `FAILED control: tests/test-transfer.sps found no row ...: add the row it
    printed above ..., then rerun`;
  - a FAIL line: exit 1, `naming 1 failing tests`;
  - a crash: exit 255, `dying by an uncaught raise`;
  - a hang: exit 124, `timed out: no exit within 5s, which counts as failing`;
  - the real test-transfer on x86-64: `FAILED ... it exited 0, naming no test`.

## Fix round 3

- **Date:** 2026-10-24, the same branch, in the container. The maintainer's decision:
  allow escapes, and count them (ADR-0013, amended 2026-10-23). Harness: `mutate4.py` and
  `run-shard6.sh`, into `build/verify/m2s2/mut6/` (scratch).
- **New tests watched failing first:** the round's tests were run against round 2's tree,
  rebuilt in `work/r3/oldtree`. Seven tests failed by name in test-transfer, and two in
  test-conditions:
  - both framing-header tests;
  - the pins' structural test (`no-perform-after`, before the `(perform)` form);
  - the two child sweeps and the child timers, each with `no-inside`;
  - the interrupt test, with `(fired (20))`: the handler ran only once all 20 bytes had
    come;
  - the reasons list, and the constructor's nine reasons.
- **Result:** 5 mutants, 5 runs, each caught by a named test.

### The probe behind the child's design

`work/r3/sweep-kinds.sps` runs a step-1 sweep and tallies each engine by its outcome and the
counts it left:
- `/status/200`: 631 ran out with nothing left, 12 escaped with one easy left each, and 1
  completed. Sockets went from 0 to 11.
- `/chunked`: 632, 32 and 1. Sockets went from 0 to 31.
- refused at connect: 1341, 2 and 1. Sockets stayed at 0. With no callback, its two escapes
  fall around the call, between the mark and `curl_easy_perform`.
- with a CHUNK-HOOK: `Exception in raise: no engine active`, raised out of the engine call.
  The hook's after thunk turns the engine's expiry into a raise, which write-body's guard
  records, and the engine is left unable to finish. So no child case has a hook it could
  escape from, and transfer.sls states this as a limit.

### Mutants

- `performing-check-removed`, so `curl_easy_cleanup` runs on an escaped handle: caught, by
  - both child sweeps and the child timers (`no-inside`: every escape now leaves zero
    counts);
  - `once every case has run...` (`(sockets (0 31) inside 0)`: cleanup on a handle left
    mid-perform did not close its socket).
- `mark-cleared-before-perform`: caught, by
  - the whole sweep (`(inside 1 refused 1)`: only the window between the marks escaped);
  - the timers (`no-inside`);
  - the after test (`(sockets (0 31) inside 2)`).
- `perform-critical-again`: caught, by
  - the whole sweep (`(inside 2 refused 2)`);
  - the timers (`no-inside`);
  - `interrupts are not put off while perform runs...` (`(fired (20))`).

  On its first run, the sweep test passed on the two window escapes alone. The whole sweep
  must now escape inside more often than the refused one, which runs no callback.
- `framing-narrowed`, Transfer-Encoding dropped: caught, by both framing-header tests.
- `framing-case-sensitive`: caught, by `a header named Content-Length or Transfer-Encoding,
  in any case, is refused as framing-header...`.

### The floor lane's sockets (7.85.0)

- On 7.85.0 an inside escape left about 2.8 sockets, 98 for 35 escapes, so the bound of one
  per escape belonged to 8.20.0. The child now counts sockets before and after each case.
  The suite holds that every case that completed, or ran out outside perform, left no new
  socket, and that an inside escape left some. An inside escape may leave any number: that
  is libcurl's leak.
- `performing-check-removed` and `mark-cleared-before-perform`: caught by the new test.
  The cases they misjudged as run out outside perform left a socket each: cleanup on a
  handle left mid-perform does not close its connection.
- The rerun showed `perform-critical-again` passing the whole sweep's comparison once: the
  windows around the call gave the whole sweep 3 inside escapes against the refused
  sweep's 2. The whole sweep must now escape more than twice the refused sweep's count
  plus one. That gave `(inside 2 refused 2)` and `(inside 1 refused 1)`, failing, in 2 runs
  of each mutant. The real tree had 32 against 2. The timer and interrupt tests caught
  `perform-critical-again` in every run.

### The child's run, bounded and judged

- The coordinator's loaded run failed 4 child tests as `no-cases`. Reproduced exactly with
  this round's child beside round 3's suite (`work/r3/race`): the same 4 failures, each
  `(no-cases (0 ((sweep "whole" 1 expired (...) 0) ...`. The trailing 0 is the new
  sockets field, which the old suite's shapes did not match. The run fell between the
  child's edit and the suite's, so load was not the cause. Each failure printed the whole
  run, cut at 3000 characters, so the output only looked cut short. Even so, the child
  had no bound at all.
- Now the child runs under GNU timeout, `-s KILL` after 180 s, through (curl-testing)'s
  bounded-script with that bound. `run-problem` judges the run before any case does:
  `child-timed-out`, `child-exited`, `child-output-ended-early`,
  `child-printed-an-unknown-shape` or `child-wrote-on-stderr`. Every child test then names
  that problem alone. The reader is tested on fixed runs.
- Mutants, each failing the 7 child tests by that name:
  - `child-bound-1`: `(child-timed-out 1)`;
  - `child-cut-short`, an `(exit 0)` after the sweeps:
    `(child-output-ended-early (sweep "refused" 769 ...))`;
  - `child-old-shape`, sweep cases without sockets:
    `(child-printed-an-unknown-shape (sweep "whole" 1 expired ...))`.
- The child's time: 7.8 s natively. Beside 4 busy loops on 18 cores, 7.3 to 7.5 s, and
  `make test-memory MEMORY_SUITES=tests/test-transfer.sps` passed in 37 s. Beside 36, it
  took 38.8 s, and the same test-memory passed in 145 s. Each socket count, a shell
  started per case, is now read once.
