# Traps: the full accounts

`AGENTS.md` carries the one-line rule for each trap; this file keeps the
incident behind it. Most came from chez-curl's sibling repositories,
chez-cmark-gfm and chez-libuv, where each shipped a passing test or a
working-looking build that was wrong. None is obvious from reading the code.
Each account names the repository it happened in. Add an incident under its
trap, newest last, naming the repository.

## Why "prefer a check to a comment"

This is not abstract. The rule about empty tests was already written down
in `AGENTS.md`, and five tests violating it shipped anyway; it only started
holding once it carried an executable standard. A Makefile comment requiring
the `chez-srfi` submodule and `Akku.lock` to name the same commit was
violated *in the same commit that introduced it*, and only became true once
it was `make check-pins`. When a comment is load-bearing, that is the signal
it should not be a comment. (chez-cmark-gfm)

## Tests

* **`0` is truthy in Scheme, and `guard` returns the body's value when nothing
  raises.** So `(test-assert "…" (guard (e ((pred e) #t) (#t #f)) (accessor x)))`
  passes even when `accessor` never raises — freed pointer fields are zeroed, and
  `0` satisfies `test-assert`. Assert on *what was raised*, compared against an
  expected value, with a distinct sentinel for the no-raise case. Three tests
  guarding the liveness mechanism passed against code with that mechanism deleted.
  (chez-cmark-gfm and chez-libuv)
* **SRFI-64 turns any exception in a test's *actual* expression into `#f`**
  (`%test-evaluate-with-catch` in `vendor/chez-srfi/%3a64/testing-impl.scm`,
  which the R6RS branch defines as `(guard (ex (else #F)) …)`). An assertion
  expecting `#f` therefore passes when the code under test raises. Never make
  `#f` the expected value of an assertion that can raise — use a sentinel the
  failure path cannot produce: `'agree (or (compare …) 'agree)`. A whole
  differential leg reported 79/79 green against a `cmark-gfm` that crashed on
  every fixture, because the helper's raise on a non-zero exit was swallowed.
  (chez-cmark-gfm and chez-libuv)
* **SRFI-64 does not catch an exception in a test's *expected* expression.**
  `%test-comp2body` evaluates `expected` before `%test-evaluate-with-catch` runs
  the actual one. A raise there escapes the runner: the suite dies with exit 255,
  no FAIL line names that test, and every later test is skipped. `make test`
  still names the suite FAIL, but the test that failed goes unnamed. Compute an
  expected value that can raise beforehand, under a `guard` with a sentinel.
  Reproduced with `(test-equal "b" (car '()) 'x)`. Found while building
  `tests/test-discovery.sps`, whose oracle shells out. A suite's top-level
  definitions are the same: they run before its first test, so a raise there
  ends the suite with no test named. `tests/test-native.sps` guards its
  `(define info …)` for this reason. (chez-curl, M0 slice 3)
* **An uncaught raise in a program skips Chez's `exit-handler`.** It also
  skips `abort-handler` and `reset-handler`; only `base-exception-handler` is
  called. Reproduced with a program that sets `(exit-handler …)` and then
  evaluates `(car '())`: exit 255, and the handler printed nothing. A suite's
  top-level cleanup, such as removing a temporary directory, has to hook
  `base-exception-handler` as well. `make-process-temp-directory` in
  `(curl-testing)` does. (chez-curl, M0 slice 3)
* **A path cut at whitespace gets the wrong directory removed.** The first C
  oracle took `mktemp -d`'s output up to the first space. With
  `TMPDIR='/x/can ary'` and `/x/can` present, it compiled into `/x/can` and ran
  `rm -rf` on it. Take a temporary directory's name from the command's one
  line, check that it is absolute and exists, and remove it under
  `dynamic-wind`. (chez-curl, M0 slice 3)
* **Under `--foreground`, `timeout` does not time out the command's
  children.** Its own help says so. `make test` passes `--foreground` so that
  Ctrl-C reaches a suite at once. A suite named HUNG can therefore leave a
  child running: a `check-seam` mutant without its depth limit spun on after
  its suite was killed. After a HUNG, look for orphans. (chez-curl, M0 slice 3)
* **Every `tests/test-*.sps` must end with its own `(exit …)`.** SRFI-64 does not set
  a process exit status, so a suite missing that line always reports success and
  `make test` stays green through real failures. Anything appended *after* it is
  dead code — a sabotage test added that way silently never runs.
  (chez-cmark-gfm and chez-libuv)
* **Chez evaluates argument expressions right-to-left in compiled library code**,
  left-to-right when interpreted. Never let an assertion's meaning depend on
  which argument runs first: one named "rejected before anything is allocated"
  was in fact satisfied by the *last* argument's accessor raising.
  (chez-cmark-gfm and chez-libuv)

  `map` is the same: R6RS leaves the order of its calls open. In Chez 10.4.0, a `set!`
  inside the procedure saw `(map f '(1 2 3 4 5 6))` call f on 5 6 3 4 1 2, compiled and
  interpreted alike. M1 slice 2's stop check recorded its probes out of order that way.
  It uses `for-each`, which goes in order.
  (chez-curl)

  A `let`'s inits are arguments too: `let` is a lambda applied to them. M2 slice 2's
  transfer read `(let ((code (curl-easy-perform easy)) (recorded (sink-recorded sink))) ...)`,
  and `recorded` was read before the transfer ran, so every body-limit and callback-raised
  case came back `perform-failed`. The suite caught it, and `let*` fixed it. A probe library
  ran `(let ((a (note! 'first)) (b (note! 'second))) ...)` second first, on Chez 10.4.0.
  (chez-curl)
* **An assertion passes whenever some *other* rule can produce the value it
  expects.** `AGENTS.md` gives the rule; here is what it looked like four times
  in one stage of chez-cmark-gfm, each one green and each one empty. A
  `*COMMENT*`-in-`blockquote` fixture survived narrowing `block-comment-parents`
  to `'(*TOP*)`, because `blockquote` is also in `cr-before-close` and
  contributes the identical newline. An empty-URL assertion could not
  distinguish "empty routes to encoding" from "empty routes to rejection",
  because `percent-encode("")` and the rejection branch both yield `""`. A
  `contains?` probe for `"  indented\n"` still matched after the serializer was
  turned into a pretty-printer, because the injected indent lands immediately in
  front of the content's own two spaces — the substring survived the corruption
  it existed to detect. And a functional-update test cannot tell "carried from
  the argument" from "rebuilt from the default" while its base record holds the
  default for the field the update leaves alone; two of `sxml-options-with`'s
  three fields were unpinned that way. Assert the whole rendering rather than a
  substring, give the fixture a neighbour that cannot produce the same bytes by
  another route, and build the base out of non-default values. (chez-cmark-gfm)

  In chez-curl, the first run of `tests/guix-env-launcher.sh`, made before
  `scripts/guix-env-enter` existed, passed
  `T6 enter on host: points at scripts/guix-env`, a `grep -F "scripts/guix-env"`
  on stderr. The refusal it meant to find never ran. dash's own error,
  `cannot open …/scripts/guix-env-enter`, contains that string. The check now
  compares the whole of stderr. (chez-curl)

  In M2 slice 1, five rules passed with a narrower rule in their place. The builder's own 58
  mutants had all been caught, and a review's and the lead's mutants found these:
  - `require-http-scheme` was tested only on `file:///etc/passwd`, so a check that refused only
    `file` passed. The libcurl lists 19 other schemes;
  - the NUL refusal was tested at one position, so a scan that skipped the first or the last
    character passed, and C read `"abc\x0;"` as `abc`;
  - every URL was ASCII, so decoding as Latin-1 passed;
  - the prototype check's tables could be loosened along with a binding, so getinfo's
    destination bound `int` passed once more.

  Each is now tested on inputs a narrower rule gets wrong: every position, bytes where the
  encodings differ, the whole complement, and tables written out. (chez-curl)

* **An exit status is taken modulo 256.** Chez's `(exit 256)` exits 0, and
  `(exit #t)` exits 1 (both measured at the pin). An exit form that reported its
  failure count would pass a suite with exactly 256 failures. `suite-exit-status`
  answers 0 or 1, never a count. (chez-curl)
* **A suite cannot vouch for the verdict it exits through.**
  `tests/test-curl-testing.sps` tests `suite-exit-status` and ends, like every
  suite, by exiting with it. In slice 2's first mutation run, `suite-exit-status`
  rewritten to ignore failures made that suite's own assertions fail, and then
  exit 0 through the broken verdict, so `make test` passed. The suite now exits 1
  on any failure of its own before it reaches the shared form. (chez-curl)
* **A setter that refuses a value keeps the one it had.** libcurl 8.20 refuses a negative
  `RTSP_CLIENT_CSEQ` with `CURLE_BAD_FUNCTION_ARGUMENT` and leaves the earlier value in
  place. So a round trip that sets the same sentinel twice, and does not assert setopt's
  code, reads the first value back after the second never arrived. Slice 6 planted a refused
  second value: with the sentinel reused, the round trip passed; with two distinct
  sentinels, it failed. Give each call its own sentinel, and assert every code. (chez-curl)
* **SRFI-64 keeps one result per runner.** A test run inside another test's actual
  expression overwrites the outer test's name and expected value. The outer verdict is then
  reported under the inner test's name. In M1's first lifecycle run, a failing check came
  out as a FAIL of a test that had passed. A four-line suite reproduces it:
  `(test-equal "outer, which fails" 2 (begin (test-equal "inner, which passes" 1 1) 1))`
  prints `FAIL inner, which passes`. Do the work in a definition, and test its outcome
  after. (chez-curl)

* **A check on a caller's string or list, then a use of it, checks something else.** Scheme
  strings and pairs are mutable. M2 slice 2's request was checked when it was made, and
  held the caller's strings. A `string-set!` after `make-transfer-request` put CR LF into a
  header value and the user agent, and the transfer sent `X-Injected: yes`, both ways. Now
  every check of caller data runs on a private copy, and the copy is what is used: the
  transfer's snapshot, the C-string helpers, URL checking and the option cache. Tests flip
  chars from another thread while the strings are in use. (chez-curl)

* **A sweep's evidence of reaching a place needs a control that cannot reach it.** M2 slice
  2's engine sweep required some expiry to land inside `curl_easy_perform`. With a critical
  section put back around perform, two expiries still landed "inside", around the call
  itself, and the test passed. It now also sweeps a transfer refused at connect, which never
  calls back, and requires the whole transfer to land inside more often. (chez-curl)

## Chez and the FFI

* **`foreign-procedure` resolves its entry point when the expression is evaluated,
  not when the procedure is first called.** Every binding must be defined after
  `load-shared-object`, which is why the load is written as a definition placed
  ahead of them in `native.sls`. Getting this wrong fails at *import* time, not at
  first use, so the error points nowhere near the mistake.
  (chez-cmark-gfm and chez-libuv)
* **Chez invokes an imported library's body only when a binding is
  *referenced*.** A probe that merely imports `(cmark gfm)` never forces
  `native.sls`'s body to run, so discovery never happens and
  `CHEZ_CMARK_GFM_LIBS` is never even read. A subprocess test written that way
  printed "unexpectedly imported" and exited 0 against libraries that cannot
  possibly load. Any test asserting something about load-time behaviour must
  *call* into the library — `tests/load-failed-probe.sps` calls
  `markdown->html` for exactly this reason. The same property is what makes
  `make check-purity` meaningful and what limits it. (chez-cmark-gfm)
* **A `guard` in a program cannot catch a raise from an imported library's
  body.** Chez invokes the libraries a program references before the
  program's body runs, so the program dies with exit 255 before its first
  line. Measured at the pin: a library whose body raised `boom` killed a
  program that wrapped its only call in `(guard (e (#t …)) …)`, and `body ran`
  never printed. `tests/refusal-probe.sps` and `tests/preflight.sps` don't
  import `(curl)`. They `eval` the call in `(environment '(rnrs) '(curl))`
  inside the guard. `(environment '(curl))` alone lacks `let`. (chez-curl,
  M0 slice 3)
* **What happens at a library's next reference depends on what its body
  raised.** Measured at the pin, with one library per kind of raise:
  - **After a serious condition** (`&serious`, `&error`, `&assertion`,
    `&violation`), Chez runs the body again in full. With a decoy libcurl
    refused for `missing-api`, three guarded references ran the whole load
    three times, `curl_global_init` included. A changed `CHEZ_CURL_LIBCURL`
    would have loaded a second libcurl, which ADR-0002 forbids.
  - **After anything else** (a symbol, a number, `&warning`, a bare
    `&message`), the library is wedged. Every later reference raises `cyclic
    dependency involving invocation of library`, and the body never runs
    again.
  - **While the body is still running,** a first reference from a second
    thread raises the same `cyclic dependency` error, rather than waiting.

  So the load records its first failure in `(curl private load-state)`, whose
  own body cannot raise, and raises only serious conditions. The two-thread
  case is open until M3. (chez-curl, M0 slice 3)
* **Chez's `system` stops silently at a NUL.** The command goes to C as a
  NUL-terminated string, so whatever follows the NUL is dropped. Measured at the
  pin: `echo before`, then a NUL, then `> /tmp/nul-out` printed `before` to
  stdout and wrote no file. Redirections written after the command are the part
  that goes missing. `capture-command` refuses an argument holding a NUL rather
  than quote it. (chez-curl)
* **A value meant to outlive a failed load must live outside the library that
  loads.** Once `(curl private native)` has raised, any reference to one of
  its bindings runs its body again and raises again. So when the
  `libcurl-info` record and its accessors were defined in native, a caller
  could not read the report that a refusal carries. Mutant LB11 shows the
  probe and the preflight dying with exit 255. The record lives in `(curl
  private libcurl-info)`, whose body cannot raise. (chez-curl, M0 slice 3)
* **In the Guix container, loading libcurl leaks one block in Guix's glibc.**
  `dlopen` runs p11-kit's constructor, which calls `newlocale`, and
  `compute_locale_search_path` loses the block. That function comes from Guix's
  `GUIX_LOCPATH` patch to glibc, not from upstream. `valgrind
  --errors-for-leak-kinds=definite` exits 9 on `tests/test-native.sps`: 171
  bytes definitely lost with the container's `GUIX_LOCPATH`, 103 without it,
  and 0 for an empty program (M0 slice 3). A C program that only `dlopen`s
  libcurl, or `libp11-kit` alone, loses the same block, under every locale
  setting. On Ubuntu 24.04, which loads p11-kit through both of its libcurls,
  nothing is lost (measured in Docker, 2026-10-16). It is not chez-curl's leak.
  ADR-0014 now allows one suppression for it, in the container only.
  (chez-curl)

* **A layout check by offset alone passes a field that is too narrow.** In slice 4, a
  mutation declared `curl_version_info_data`'s `ssl_version_num` as `int`, where C has
  `long`. The next field is a pointer, aligned to 8, so padding kept every offset the same.
  Only the size check failed, and `test-native` still passed. The review then showed that a
  `double` written for a pointer passes offset and size together. `test-constants` now
  compares each field's offset, size and kind. (chez-curl)
* **A function ftype binds C without `foreign-procedure`.**
  `(define-ftype F (function (int) int))` and `(ftype-ref F () (make-ftype-pointer F "abs"))`
  call libc's `abs`, and `make-ftype-pointer` given a lambda makes a callable. Slice 4's
  review used this in `native.sls`: it bound `curl_easy_perform` as a plain call and made a
  write callback. `check-seam`, `test-collect-safe` and `test-constants` all passed. The
  first fix let only `(curl private layouts)` import `define-ftype`. The review of that fix
  reached it from another library anyway, with `make test` green, three ways:
  - layouts re-exported it;
  - a macro in layouts took it as an argument;
  - layouts exported a macro that expands to it.

  Now no library may re-export a Chez name, and layouts is held to struct `define-ftype`
  forms alone. A rule on who imports a keyword is not a rule on who can use it. (chez-curl)
* **On x86-64, a variadic binding without `(__varargs_after 2)` works.** Integer and
  pointer arguments after the named ones travel in the same registers either way. Measured
  in slice 6: with the annotation removed, every value `test-variadic` sets arrives, and
  every answer is the same. Apple arm64 passes them on the stack, so by its ABI the same
  binding hands libcurl garbage there. That is
  predicted, not yet measured. `test-collect-safe` requires the annotation everywhere, and only
  `make check-variadic` on Apple arm64 can watch a missing one fail. (chez-curl)
* **An `int` binding for a 64-bit variadic argument looks like it works.** Chez passes the
  `int` zero-extended, so -1 reaches libcurl's `va_arg(curl_off_t)` as 4294967295.
  `MAXFILESIZE_LARGE` then answered `CURLE_OK` where -1 must be refused. Chez's own range
  check refuses only values beyond 32 bits. So a test of a 64-bit binding must pass a
  negative value whose answer differs from its zero-extended twin's, as `test-variadic`'s
  -1 through the `curl_off_t` binding does. (chez-curl)

* **libcurl's cleanup reads nothing a transfer handed it, so a wrong free order passes.**
  M2 slice 2 freed the `CURLU`, the header list and the error buffer before
  `curl_easy_cleanup`, in a mutant. Transfers with headers, a user agent and a body limit
  answered correctly, every count came back to zero, and Valgrind under the gate's options
  found 0 errors, on libcurl 8.20.0. A later libcurl may read them there. So the order is
  held by a check that reads the transfer's nesting, not by behaviour. (chez-curl)

* **A continuation out of a foreign callable abandons its C caller.** M2 slice 2's review
  invoked an outer continuation from inside `write-body`, through the test hook. The
  transfer's extents then ran `curl_easy_cleanup` while libcurl was still inside its
  callback: 744 bytes were definitely lost under the gate's Valgrind, with a socket left
  open each time, while every count read zero. A continuation saved in one chunk's call and
  invoked in a later one raised `attempt to return to stale foreign context`, outside the
  callable's guard. Now caller code inside the callable runs in a `dynamic-wind` whose
  after thunk turns any exit but a return into a raise, which the guard records. (chez-curl)

  An asynchronous handler escapes the same way, at any safe point. The scoped review of the
  fix ran a transfer inside a Chez engine: when its fuel ran out inside `write-body`, but
  outside the hook, a socket was left open and 744 bytes were definitely lost, with every
  count at zero. A timer-interrupt handler, or a keyboard interrupt and then `reset`, does
  the same. And at fuel 300 an expiry between `curl_url_get` and its `dynamic-wind` left a
  `curl-string` counted for good. A `critical-section` around `curl_easy_perform` moved the
  expiry to after it returned, but deferred the thread's own collections and Ctrl-C until the
  transfer ended: an 80 MB body grew the peak heap by 472 MB against 344 MB. So that was
  reversed (ADR-0013, amended 2026-10-23): an escape from perform is allowed, chez-curl
  never calls libcurl on that handle again, and it stays counted. Each native object is
  made, or freed, in one short critical section with the record of it: its count, and the
  variable its free reads. (chez-curl)
* **`with-mutex` takes its mutex before its own `dynamic-wind`.** An engine's expiry between
  the two left the mutex held. Chez's mutexes are recursive, so the thread that held it never
  noticed, but every other thread then blocked on it: 4 of 11 mutants hung in the two-thread
  test, every thread in a futex wait. So every mutex is held through `critical-section`
  around `with-mutex`. (chez-curl)
* **An after thunk that raises during an engine's expiry kills the engine.** The test hook's
  refusal of a continuation exit raises in its `dynamic-wind`'s after thunk. When an engine's
  fuel ran out inside the hook, that raise came during the engine's own unwind, and the call
  failed with `Exception in raise: no engine active`, in the first scoped review and again
  in fix round 3. A refusal in an after thunk is safe against a caller's continuation, not
  against an engine. (chez-curl)

## Checks and environment

* **Node's `socket.destroy()` closes with a FIN, not a reset.** M1's plan had the byte
  probe "reset mid-request" with it. A server sees that as a clean end, so a test of how it
  survives a reset would have passed without one ever being sent. Measured on Node 24.18.0:
  `destroy()` reaches the peer as `end`, and `resetAndDestroy()` as `ECONNRESET`. The
  probe's `--reset` uses the second, and `test-curl-testing` checks what the peer saw.
  (chez-curl)

  Over TLS it is worse. Measured on Node 20.10.0 and 24.18.0 alike:
  - `resetAndDestroy()` on a TLS socket throws `ERR_INVALID_HANDLE_TYPE`;
  - a server that wraps a `net` socket in `tls.TLSSocket` and resets the `net` socket sends
    the reset, and the client sees its data, then `ECONNRESET`;
  - a client that hands `tls.connect` its own `net` socket and resets that one still
    reaches the server as an `end`.

  So `raw-tls` resets the socket it wrapped, and the probe refuses `--reset` with `--tls`
  ([TLS mutation log](tls-mutation-log.md), §1.4). (chez-curl)
* **LibreSSL 3.3.6, the Mac's `/usr/bin/openssl`, differs from OpenSSL where a check
  would not notice.** Measured in Docker, on Alpine 3.14's package and on one built from
  its tarball:
  - **`s_client -verify_return_error` exits 0 when verification fails,** where OpenSSL
    exits 1. A check that reads the exit status passes on the Mac against an expired leaf.
  - **`req` takes the config's subject over `-subj` when the config says `prompt = no`.**
    The first PKI script made every leaf `CN=placeholder`, and each still verified,
    because nothing checks a leaf's subject.
  - **It has no `-verify_hostname`, `-verify_ip`, `-checkhost` or `-ext`.** This one is
    loud: it prints its usage and exits 1.

  The checks read verify codes, the served leaf and its SAN line, and the PKI script's
  config has no subject (ADR-0005, amended 2026-10-18). (chez-curl)
* **curl's `./configure` turns on every optional library it finds.**
  - In 7.85.0, brotli's default is `off`, and only `no` skips the search
    (`configure.ac`).
  - In Docker `ubuntu:24.04`, the floor build's features word was 1361625749 with the
    prereqs alone, and 1975043741 with ten more `-dev` packages installed. With the prereqs
    alone it also had no zlib and no HTTP/2: `libcurl4-openssl-dev` only suggests their
    headers.
  - `configure` only warns about an option it doesn't know, so a misspelt `--without-…`
    does nothing.
  - IPv6 is decided by running a socket test, unless `--enable-ipv6` is given.

  `build-curl.sh` now names every library, passes `--enable-option-checking=fatal`, and
  checks what the install lists (ADR-0017). (chez-curl)
* **A shell's `wait` may print `Killed` on stderr when the child it waits for died of a
  signal.** Measured with `sleep 5 & p=$!; kill -9 $p; wait $p`, which gives status 137 in
  every case:
  - Ubuntu 24.04's dash prints `Killed`;
  - bash 5 run as `bash -c` prints it too;
  - bash 3.2 in POSIX mode, macOS's `/bin/sh`, prints `Killed` (and `Terminated` for
    SIGTERM), per the second review.

  Only bash 5 run as `sh`, the container's `/bin/sh`, prints nothing, so no check run in
  the container sees it. The origin's runner sends its own stderr to `/dev/null`. The
  Debian Docker run caught it. (chez-curl)

  dash writes `Killed` to the stderr the killed command's own redirections set. In
  `node:20.10.0-bookworm`, `timeout -s KILL 1 sleep 5 2>/tmp/e` left `Killed` in `/tmp/e`.
  So slice 1's `bounded` put `Killed` into the stderr it captured, on Debian and macOS but
  not in Guix. M1 slice 2's Node 20 run caught it. `bounded` now runs `timeout` in a
  subshell, sends the shell's own stderr to `/dev/null`, and exits with the subshell's
  status. (chez-curl)
* **Over TLS, every record reaches the reader as its own chunk, even when TCP joined
  them.** M1 slice 2's review kept Nagle's algorithm on `raw-tls`'s TCP socket, and every
  suite stayed green. Slice 1's drip rules are lower bounds from the connect, plus "each
  byte arrives alone", and over TLS each byte still arrived alone. Yet two bytes came 0 ms
  apart: with Nagle on, the first gap of a 20 ms drip was 0 to 2 ms in every run. The
  suite now judges TLS timing between arrivals: each body byte at least half the drip's
  gap after the one before it. Its gaps were measured over 10 runs, idle and under 24
  busy loops ([TLS mutation log](tls-mutation-log.md), §3.3). The suite then passed 20
  of 20 runs under that load. (chez-curl)
* **TLS picks ALPN by the server's preference, so the chosen protocol cannot show a client
  that reorders its list.** The review's probe mutants offered only the last protocol, or
  the list reversed. Both passed, because every multi-protocol row overlapped the server
  only in its last entry. The stand-in servers now report the whole offered list through
  `ALPNCallback`, which Node 20.10.0 and 24.18.0 both have, and rows overlap only first,
  and only last. (chez-curl)
* **An end seen after a stop proves the stop only if nothing but the stop can explain it.**
  M1 slice 2 took three tries.
  - **First,** one waiting state per face, and any eof taken as the stop's. A mutant that
    closed idle connections after 100 ms passed, since its eof came first. So did one that
    stopped tracking a face's TCP sockets: no connection was held mid-handshake, where an
    untracked one makes `server.close()` wait. That origin exited 14 s after its stdin
    ended, against 57 ms.
  - **Second,** every waiting state, and each probe silent 300 ms after it opened. Two
    other causes still passed:
    - **Node's own `server.close()`.** Node 24 ends idle HTTP/2 sessions within 3 ms,
      where Node 20 ends none. So a face that tracked nothing passed on Node 24, the
      container's, and failed only on Node 20.
    - **Idle timers.** The silence was checked long before the stop, and ends were
      accepted for 2000 ms after it, so a 1200 ms handshake timeout passed.
  - **Third,** that rule, with two sets of probes more than B apart and a bound B. The
    third review found two more causes:
    - **a state left out:** a raw script still playing between writes. A stop that spared
      it took 9.8 s, and passed;
    - **one schedule for every connection:** a watchdog or a load shedder ended both sets
      at once, after the stop. Two sets rule out only timers keyed to each connection.
  - **The rule that held:**
    - cover the states `close()` never ends: a stream with its body to come, a TLS state
      before the handshake, a script still playing;
    - require silence right up to the stop;
    - bound the call's return by B = 500 ms after the stop;
    - open two sets of probes more than B apart;
    - run it all twice on fresh origins, the second held 700 ms longer before the stop.

    Every face, untracked and closed at each of 100 ms to 5 s or never, failed on both
    Node versions. So did the watchdog, the shedder and the spared player.

  (chez-curl)
* **A mutation harness that runs `A; B` reports only B's status.** M1 slice 2's harness
  ran two suites for some cases, and a failure in the first counted as caught only when
  the second failed too. Such cases now fail if either suite fails, and the six were
  rerun. (chez-curl)
* **OpenSSL 3's `s_client` prints a `Verify return code` line for each TLS 1.3 session
  ticket it reads before stdin ends, and how many it reads depends on timing.**
  - **Measured:** Node sends two tickets. On OpenSSL 3.5.7 and 3.0.11, with stdin at its
    end at once (`</dev/null`), three of 200 runs had three code lines while other jobs
    ran. So did 73 of 200 under 24 busy loops, and none of 80 on an idle machine. Ending
    stdin 300 ms late gives three every time, and LibreSSL 3.3.6 still prints only one.
  - **What the extra lines look like:** each sits in a `Post-Handshake New Session Ticket
    arrived:` block, indented. LibreSSL indents its only line the same way, so indentation
    tells nothing. `-no_ticket` changes nothing.
  - **The first rule broke:** "exactly one code line" passed on an idle machine and failed
    by chance under load. The first `make test-memory` of slice 2 caught it.
  - **The rule now:** the first code line is the handshake's. Each later one needs its own
    ticket header, and must agree with the first. Every ticket's code matched the
    handshake's on every face ([TLS mutation log](tls-mutation-log.md), §2.2).
    (chez-curl)
* **A child of `open-process-ports` stays a zombie until Chez's next collection.**
  Measured at 10.4.0: one second after the child exited, `/proc/PID/status` said `Z
  (zombie)`; after a `(collect)`, the pid was gone. Until then `kill -0 PID` succeeds on a
  dead process, so liveness is never judged by the pid alone. (chez-curl)
* **`nm` cannot show a curl API that was configured out.** curl compiles a stub in its
  place: with `CURL_DISABLE_GETOPTIONS`, `curl_easy_option_by_name` returns NULL, and with
  the header API off, `curl_easy_header` answers "not built in" (7.85.0's source). Both
  symbols were exported in every disabled-API build. Only a call shows the difference,
  which is why the load probes them. (chez-curl)

* **A check that reads a library's import form does not see everything the
  library can import.** Each of these reached `(http-client session)` from a
  `(curl …)` library while the first `check-seam` reported "the seam holds":
  - `(import (for (http-client) expand))`. R6RS has `for` as well as `only`,
    `except`, `prefix` and `rename`.
  - `(import …)` as a body form, or inside a `let`, once the library imports
    `(chezscheme)`, or just its `import`. `(scheme)` is another name for
    `(chezscheme)`. The review found this; the builder's probe had imported
    only `(rnrs)`, and its log recorded "`import` is no body form".
  - `eval`, `interpret` or `compile` on an import form.
  - A file the check doesn't read but Chez loads.
    - `(library-extensions)` lists `.chezscheme.sls .ss .sls .scm .sch`.
    - A compiled `.so` with no source beside it loads as the library.
    - A `.chezscheme.sls` shadows the `.sls` beside it.

  A first fix denied those names. A second review then got through with
  `import-only`, `top-level-value 'eval` and `$primitive`. A regular file named
  `.#g.sls`, hidden by a skip meant for Emacs lock files, also loaded. Deny
  lists lose to Chez's many routes, so `check-seam` now admits only what an
  allowlist names, and skips only dangling `.#` links. (chez-curl, M0 slice 3)
* **Guix's `gcc` writes `guile: warning: failed to install locale` to
  stderr** on every link, because its linker wrapper is a Guile script. Judge
  a compile by its exit status, never by an empty stderr. (chez-curl, M0
  slice 3)
* **Deleting a subsystem disarms the checks built around it, and they stay
  green.** Release 2.0 removed the C shim and produced seven of these in one
  branch. `make check-purity` poisoned `CHEZ_CMARK_GFM_SHIM`, which the same
  release had replaced with `CHEZ_CMARK_GFM_LIBS` — nothing read the poison, so
  the gate passed unconditionally, including for regressions it existed to
  catch. A CI step asserted `! -e build/lib`, a path only the deleted shim rules
  ever created. `deps-info` branched on `$(HAVE_PKG)`; with the variable gone
  Make expanded it to empty and it reported "vendored" forever — a dangling Make
  variable is not an error. A CI job named for the vendored build passed while
  Homebrew's copy silently satisfied discovery first: green for the wrong
  reason, which is worse than red. And a `no-library` job grepped only for remedy
  text that the preflight's catch-all `else` prints for *any* condition, so it
  could not identify the failure it claimed to test.
  None of these fail, so no gate surfaces them. On any deletion, ask of every
  surviving check "what would make this fail now?" and treat "nothing" as a
  defect — then prove it by breaking the guarded thing and watching it go red.
  A passing CI job is evidence a check *ran*, not that it works.
  (chez-cmark-gfm)
* **An alias for the Chez binary must be neither a symlink nor a wrapper
  script.** A `chez` symlink to Guix's `scheme` aborts with `cannot find
  compatible chez.boot in search path "%x:%x/../lib/csv%v/%m:…"`: Chez
  derives its boot-file name from the invoked name. A wrapper script that
  `exec`s `scheme` fixes that and passes `make test`, but hides Chez from
  Valgrind: Valgrind traces the shell, the shell execs Chez uninstrumented,
  and `make test-memory` reported success over 21 suites without printing a
  single `ERROR SUMMARY`. Point `CHEZ` at the real binary, which is what
  chez-cmark-gfm's `manifest.scm` search path does. `make check-guix` asserts that
  `valgrind $CHEZ` prints an `ERROR SUMMARY`. (chez-cmark-gfm)

  In chez-curl, `scripts/guix-env-enter` exports `CHEZ` as the profile's
  `bin/scheme`. `make check-guix` asserts that it lies under the profile and
  is an ELF binary, and that `valgrind $CHEZ` prints an `ERROR SUMMARY`. Its
  mutation log records each wrapper and symlink failing. (chez-curl)
* **Anything between the memory tool and Chez gets checked instead of
  Chez.** Valgrind checks the command it is handed and does not follow an
  exec. `valgrind … timeout 900 scheme …` therefore checked timeout's two
  allocations while Chez ran natively and exited 0. chez-libuv's #14 wrote that shape,
  and the Linux gate stayed green from 2026-08-30 to 2026-09-27; v0.6.0 and
  v0.7.0 shipped on it. On macOS, `DYLD_INSERT_LIBRARIES` is lost two ways.
  SIP purges it when it launches a protected binary such as `/bin/sh`, and
  the ASan arm's `sh -c` never loaded ASan from v0.1 on. ASan's Darwin
  runtime also strips itself from the variable in whatever process it loads
  into, so under `timeout` it is `timeout` that gets ASan. Put wrappers
  *outside* the tool, and put the preload on the `chez` command itself.
  `make check-memory-gate` holds this: it plants defects and requires the
  real recipe to fail on each, with the tool's own report in the log. Watch
  it go red whenever you touch either `test-memory` recipe. (chez-libuv)
* **`guix shell --pure` does not stop a login shell from rebuilding `PATH`.**
  `--pure` clears the environment once, at entry. A later login shell
  (`bash -l`) re-sources `~/.bash_profile` and `~/.profile`. On the
  maintainer's machine those put `~/.guix-home/profile/bin` ahead of the
  environment, so `scheme` and `git` resolved to the host's copies while
  everything still passed.
  `scripts/guix-env` uses `--container`, whose `HOME` is empty; `make
  check-guix` asserts both that (`isolated-home`) and that a login shell
  runs the pinned binaries, comparing resolved paths. Do not assume you
  know how a tool builds its shell: when Claude Code ran inside the
  container (chez-cmark-gfm's ADR-0018, since withdrawn), its Bash tool put `/bin:/usr/bin`
  ahead of the profile, which a `bash -l` check never showed. `guix shell
  --check` diagnoses clobbering for a `--pure` shell. (chez-cmark-gfm)
* **`guix shell -m` serves its cached profile while the manifest is no newer
  than the cache.** In slice 2, a mutation driver copied the tree with `tar`,
  which keeps file times, and a baseline case flaked: a copy's changed
  `manifest.scm` was older than the cache entry for that path, so the container
  ran the old toolchain. Measured at the pin: once a profile with git was
  cached, a manifest without git, dated 2020, still got git. A manifest
  rewritten within a second of the cache was missed too. `touch` a manifest
  that a mutation changes. (chez-curl)
* **In an empty submodule directory, `git -C` answers for the superproject.**
  `git -C vendor/chez-srfi rev-parse HEAD` in an uninitialised submodule
  returns the superproject's HEAD, so `check-pins` reported pin drift against
  the wrong repository instead of saying the submodule was not checked out. The
  first fix tested for `vendor/chez-srfi/.git`, but the slice 2 review showed an
  empty `.git` directory passes that test and still gets the superproject's
  answer. `check-pins` now compares `git -C vendor/chez-srfi rev-parse
  --show-toplevel` with the directory itself. (chez-curl)
* **In a git worktree, `.git` points outside the working directory.** Its
  `.git` is a file naming a directory inside the main repository's `.git`, and
  the container shares only the working directory. Slice 2 first put git in
  the container so `make test` could run `check-pins`. Its review found that
  `make test` and `make check-guix` then failed in every worktree, with
  `fatal: not a git repository: (null)`, where slice 1 had worked. The container
  has no git again, and `check-pins` runs on the host and in CI. (chez-curl)
* **A constants check says nothing about a library whose headers it did not compile
  against.** Found by slice 4's review, not by an incident. CI's floor lane will load curl
  7.85.0 through the override, while the runner's 8.5.0 headers sit on the compiler's
  default path. The review appended a field that 7.85.0 lacks to `curl-version-info-data`,
  and it passed against 8.20.0's headers. `test-constants` now requires the headers to be
  no newer than the library chez-curl loads. Measured: with a decoy that reports 7.85.0 as
  the override, it fails, naming headers `0x081400` against library `0x075500`. (chez-curl)
* **Claude Code's Write tool drops trailing whitespace.** In slice 4, a fixture whose point
  was a trailing space lost it when written, and the mutation driver's empty-diff refusal
  caught it. Measured: two trailing spaces and a trailing tab were both dropped. Build such
  a file in code, and check its bytes. (chez-curl)
* **A bare `mktemp -d` honours `TMPDIR` on Linux and ignores it on macOS.** The first
  macOS run (2026-10-16: an M1, Homebrew's Chez 10.4.1, Apple's libcurl 8.7.1) failed 11
  tests in `test-curl-testing` and `test-library-loading`, which had passed on Linux since
  slice 2.
  Each test that set `TMPDIR` found its directory elsewhere, and a newline in `TMPDIR`
  never reached the answer. `make-temp-directory` now hands `mktemp` a template under
  `$TMPDIR`, which GNU and BSD `mktemp` read alike. On Linux, a fake `mktemp` that ignores
  `TMPDIR` when given no template reproduced the 11 failures by name, and the Mac then
  passed every suite. (chez-curl)
* **Valgrind reads options that no command line shows.** It adds `VALGRIND_OPTS`, then
  `~/.valgrindrc`, then `./.valgrindrc`, to the options it is given. In slice 5, a
  suppression of `fun:*` passed through `VALGRIND_OPTS` turned the planted 777-byte leak
  from exit 9 to exit 0, with `suppressed: 777 bytes`, under the gate's exact command.
  `make test-memory` refuses to run while any of the three is present. (chez-curl)
* **Valgrind cannot see into Chez's heap.** Measured under slice 5's gate, both of these
  passed with 0 errors and nothing definitely lost:
  - a `memcpy` of 24 bytes into a 23-byte bytevector, through a `u8*` argument;
  - a 777-byte `foreign-alloc` block, wrapped in an ftype pointer and dropped, which
    Valgrind called "still reachable", even after a full collection.

  Chez's heap is one block to Valgrind, and any raw address an object ever held there counts
  as a live reference. The planted defects pass only because they use shapes Valgrind can
  see: a `foreign-alloc` block, and an address kept as a fixnum. Bytevector copies get
  their bound from one checked wrapper (ADR-0001, amended), and leaks of foreign memory
  from the counters, as a gate (ADR-0014, amended). (chez-curl)
* **`--command-line-only=yes` does not stop `VALGRIND_LIB`.** It stops `VALGRIND_OPTS` and
  both `.valgrindrc` files. But with `VALGRIND_LIB` pointed at a copy of Valgrind's library
  directory, Valgrind read the copy's `default.supp`, and a catch-all entry there passed
  the planted leak. Measured on 3.27 here, and on Ubuntu's 3.22 in Docker. (chez-curl)
* **A suite under Valgrind can forge Valgrind's lines.** The guest runs in Valgrind's own
  process, so it shares the PID in `==PID==`. Measured: a program printing
  `==PID== ERROR SUMMARY: 0 errors` put a line the gate would have trusted next to the real
  one. Valgrind now writes to its own `--log-file`, and the gate reads only that.
  (chez-curl)
* **A make variable that feeds both a command and its check widens both.** The suppression
  file's path fed both Valgrind's `--suppressions` and the gate's allowlist of suppressions
  files. So `make test-memory MEMORY_SUPPRESSION_FILE=<a catch-all>` passed the planted
  overrun. The path is now fixed with `override`. (chez-curl)
* **A text check for a value cannot see the value redefined.** Slice 5 first wrote the CI
  floors once, as two env lines that every step referred to, and `check-floors` refused the
  version text anywhere else. A job-level `env:` setting `CURL_FLOOR_VERSION: "8.1.3"`
  passed, so the floor lane would have tested a libcurl that is not the floor. Now the build
  scripts read `packaging/floors.sexp` themselves, and no workflow may name a floor key.
  Make the consumer read the source, rather than checking that copies match. (chez-curl)
* **A check whose empty output means pass, passes when the checker fails.** The gate's awk
  printed what was wrong, and nothing meant pass. With an awk that exits 2 first on `PATH`,
  a wrapper `CHEZ` that hid Chez from Valgrind passed. Now awk must exit 0 and print exactly
  `ok`. (chez-curl)
* **An allowlist of names still passes a macro's pattern variable spelt as one of them.**
  `((_ uptr) (foreign-procedure "memcpy" (uptr uptr size_t) uptr))`, used as
  `(bind-memcpy u8*)`, passed a reader that allowed `uptr`, and Chez bound a `u8*` memcpy that
  copied one bytevector into another. `test-collect-safe` now treats every pattern symbol as
  no type at all. (chez-curl)
* **A reader that tracks a binding macro by its name at a form's head misses every other
  route to it.** Slice 6's review bound `curl_easy_setopt` with no `(__varargs_after 2)`
  three ways, each passing `make test` and `check-variadic`: the use inside quasiquote, an
  `identifier-syntax` alias of `bind-required`, and `bind-required` passed to another macro.
  The last also bound a plain `curl_easy_perform` with an unmarked `u8*`, and
  `test-collect-safe` passed 67/67. The hole dated from slice 4. A wrapper's name is now held
  to a use's head and its own `define-syntax`. (chez-curl)
* **A macro can take apart a form it is handed, and bind what it rebuilds.** The reader reads
  the form as written. In slice 6's fix rounds, each of these bound an entry the reader never
  saw. A probe handed `(foreign-procedure "labs" ...)`, and Chez answered `no entry for
  "abs"`:
  - a new `syntax-rules` macro rewriting a wrapper use's entry;
  - a `syntax-case` taking its own template apart;
  - a binder whose pattern took an operand apart;
  - a procedural macro handing its input to a procedure in another library;
  - one taking its input back from `syntax-violation`'s condition with `guard`;
  - one rebinding `syntax-violation` with `let`;
  - one importing another library's `syntax-violation`;
  - one building a binding from strings in another library.

  Now every macro `src/` defines is a row of `known-macros`, and a plain macro may not touch
  its input, raise anywhere but in tail position, or import beyond whole `(rnrs ...)` and
  `(only (chezscheme) ...)`. Two Chez facts help: it refuses a raw symbol in a transformer's
  output, and a second `syntax-violation` beside a whole `(rnrs)`. (chez-curl)
* **A flat pattern still lets a use hand a macro its head.** The scoped review of the fix
  rounds gave `load-step` a second clause, `((_ head operand ...) (head operand ...))`,
  which passed every plain rule. native.sls then wrote
  `(load-step define-syntax bind-quietly ...)`, a macro defined where no `define-syntax`
  heads a form, and bound an entry through it. `test-collect-safe` passed 102/102, and Chez
  answered `no entry` for the hidden name. Now the three macro keywords stand only at a
  written head, and no pattern variable heads a form in a listed macro's template.
  (chez-curl)
* **A `case` clause's datums are data.** The reader walked them as code, and counted a
  `foreign-procedure` there as a binding that Chez never makes. A phantom like that can
  keep a count while another route hides the real binding. (chez-curl)
* **A check that knows a library by its name must hold it to its name's path.** Chez finds
  a library by its path, in each library directory in turn, and `tests/` is on the suites'
  path. A `src/` library importing `(curl private extra)` from `tests/` passed `check-seam`,
  and its binding was out of `test-collect-safe`'s reach. With every import required to be
  defined under `src/`, a second definition, as a second form in `conditions.sls`, still
  passed, while Chez loaded the `tests/` copy and `test-variadic` died with `no entry`. Now
  each `src/` file holds one library, at its name's path. (chez-curl)
* **A crash proves nothing about the assertions after it.** `check-variadic`'s first arm64
  step took any non-zero exit of a mutant without the annotation anywhere. There, getinfo
  writes through a garbage pointer before any setopt assertion is read. The step now
  mutates one binding at a time and requires a named failure through it. (chez-curl)
* **Nothing checks a binding's parameter types against libcurl's prototypes.** With
  getinfo's destination typed `int`, `test-variadic` passed, since `foreign-alloc`'s slot
  lies below 2^31 here and Chez's range check never fires. A `long` typed `int` passed too,
  until slice 6's fix round added negative `long` cases. (chez-curl)

  M2 slice 1 built the check: each binding is held to a prototype row, and each row to the
  header. The review then loosened getinfo's row to `int` together with its binding, and
  every suite passed, since the row was the check's only record of what is right. Now the
  type map, the enum names and the variadic lists are written out in the suite. Even then, the
  C side alone could not tell an enum from `unsigned int`: gcc 16.2, gcc 13.3 and clang 18.1.3
  each accept one for the other. So each row's spelling is held to the preprocessed headers'
  own. (chez-curl)
* **The counters gate counts per process.** The decoys' refusals run in child probes, which
  neither `suite-exit-status` nor Valgrind reads. The review kept the header probe's counted
  block on a refused load, and every suite passed. Every child that reaches native now prints
  its counts, and its suite asserts them zero. (chez-curl)
* **`pgrep -f` finds the shell that runs it.** An agent waited for its mutation run with
  `until ! pgrep -f "mut/run.py"; do sleep 10; done`, through `bash -c`. That shell's own
  command line holds the pattern, so `pgrep` always found it, and the wait never ended. M2
  slice 1's builder sat on it for about 14 hours before reporting, and kept waking after.
  Three loops of the same shape from M0 slice 5, waiting on `mutate.py run`, had run every 5
  seconds for six days, holding that slice's agent open. Reproduced: `bash -c 'pgrep -f
  "zz-other-marker"'` matches itself. Wait on a PID, with `wait` or `kill -0`, or on a file
  the job writes when it ends. (chez-curl)
* **libuv before 1.52 reads a reset as an end.** `test-origin`'s `reset-mid-body` row read
  `eof` in one of four floor-lane runs, where the origin had reset. libuv 1.46.0, Node
  20.10.0's, ends a read on HUP after a partial read, without reading again, and a reset
  brings HUP. So a probe that reads the last data and the reset in one wakeup reports the
  end of a FIN. A client that blocked its loop for 200 ms read an end in 50 runs of 50, plain
  and over TLS, while one read(2) of its fd still threw `ECONNRESET`. The probe now reads the
  fd once on each end. Each origin suite stops the probe across a script's last write and
  its reset: on Node 20.10.0 that failed without the fix, and on 24.18.0 it passes either
  way (ADR-0005, amended). (chez-curl)
* **A version manager's shim can write to stderr on every call.** On the maintainer's Mac,
  `node` was asdf 0.15's Bash shim, which prints a notice about upgrading to asdf 0.16 to
  stderr each time it runs. Node itself ran: it reported v20.10.0. But every check that
  wants an origin or a probe to write nothing to stderr failed, 68 tests across
  `test-curl-testing`, `test-origin` and `test-origin-tls`. With `NODE="$(asdf which
  node)"`, the real binary, all three passed. (chez-curl)
* **macOS's poll(2) does not support devices, and LibreSSL's `s_client` polls stdin.** Every
  TLS check was measured on LibreSSL 3.3.6, but built on Linux, where poll reads
  `/dev/null` as at its end. On the maintainer's Mac, `/usr/bin/openssl s_client` with
  stdin at `/dev/null` completed each handshake and printed the right codes, then wrote
  `poll error` and exited 1. That failed 17 tests across `test-origin-tls` and
  `test-curl-testing`. With an empty pipe, `: | openssl s_client`, it printed `DONE` and
  exited 0. OpenSSL 3.6.3 passed on that Mac because its `s_client` waits with select().
  `s-client` now hands `openssl` an empty pipe, and `test-curl-testing` holds it to one
  through a stand-in that reports its stdin, so a `/dev/null` fails on Linux too.
  (chez-curl)
* **Valgrind runs one thread at a time, so a thread that never sleeps starves the rest.**
  In M2's planning, a collecting thread with no pause ran 92,297 collections under
  Valgrind while the transfer beside it timed out with no callback. M2 slice 2's race tests,
  a thread flipping a string's chars, then held the gate over 10 minutes with a flipper
  that spun. Pace such a thread: the lock test sleeps 2 ms between collections, and the
  flippers yield in each state. (chez-curl)
* **One protocol pin hides the other's removal.** libcurl checks a followed URL against both
  `PROTOCOLS_STR` and `REDIR_PROTOCOLS_STR`, so a redirect to `ftp://` is refused with
  either one alone. M2 slice 2's redirect test caught only both removed. Each pin is held by
  a test that reads the transfer's options as data. (chez-curl)
* **An ambient proxy variable diverts every transfer.** libcurl reads `http_proxy` and the
  rest from the environment. With `http_proxy=http://127.0.0.1:9`, a transfer to the origin
  answered 7, and a proxy that answered would have fed the suite its answers. So
  `test-transfer`'s first test fails, naming the variable, when one is set. chez-curl's
  proxy policy is M4's. (chez-curl)
