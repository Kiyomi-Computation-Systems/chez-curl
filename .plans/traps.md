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

  It happened again in M7 slice 2: the credentials' control-char rule was tested with the char
  at index 1 alone, and the `Authorization` rule with one header, so a scan from index 1, under
  which `(bearer "\nX-Inj: 1")` wrote a header of its own, and a check of the first header alone,
  passed every suite; and only five passing chars were sampled, so refusing `"` passed. The
  slice's review found all three. Each char U+0000 to U+00FF and four above now stands at the
  first, a middle and the last index of every part, and `Authorization` first, in the middle and
  last of three headers. (chez-curl, M7 slice 2)

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

* **A by-version test passes on every libcurl it has no row for, when both sides answer "no
  row".** Slice 1's `spin-rows` control and slice 2's answer table and attempt rows each computed
  `(no-row-for VERSION)` as the expected value and as the actual one, so a missing row matched
  itself. The review's mutant deleted 8.20.0's rows, and test-upload and test-stream still passed
  on 8.20.0, 52 and 74 tests, as on the base
  ([research](research/m6/slice2-build/review/results/mut-no-row.log)). The 8.7.1 row slice 2
  left for the Mac would have passed there, measuring nothing. A missing row's expected value is
  one no measurement can give, and its actual value is the measurement, so the failure prints the
  row to add. (chez-curl, M6 slice 2's review)

* **A full TCP buffer is not a stable full.** A put on an upload whose server read nothing waited
  on a full buffer and timed out; a later put was taken anyway, libcurl having handed 2,031,616
  bytes, in 7 runs of 7, one at 1,966,080
  ([research](research/m6/slice2-build/results/full-buffer-repro-guix-8.20.0.log)). Why the
  room came back is not shown. A test that needs libcurl to stop asking for the body holds the
  transfer where it never asks: an `https` request to a plaintext face, whose handshake never
  ends. (chez-curl, M6 slice 2's build)

  The test slice 2 kept on the kernel failed on CI's current lane, 3 runs of 3. Its fill called
  the buffer full only after a put timed out and a further 500 ms passed with nothing taken.
  There libcurl had taken one 64 KiB piece more by the end of each of the fill's one-second
  rounds, read at 1,049, 2,050, 3,051, 4,051 and 5,052 ms, so that quiet never came before the
  sink began to read at 5 s ([research](research/ci-first-run/)). When within each round it
  took them, the trace cannot say. 8.5.0 stalled at once on the same run's GnuTLS lane, and here
  a kernel let more in once at most, then held. The runner's `net.core.rmem_max` is 1 MiB, the
  Docker lanes' here 4 MiB; whether that matters is not shown. The fill now asks only that
  nothing be taken through the put's own 500 ms bound, and on the runner's next run it stalled
  at 550 ms. A check of a full kernel asks for no quiet past one put's bound. (chez-curl, CI's
  first run)

* **A row read from one run cannot show a cell that splits.** 8.7.1's rows in test-upload were
  read from the Mac's first run, whose HTTP/2 200 ended 200 in both framings; the rerun's sized
  cell ended 55 ([research](research/m6/slice2-build/results/)). 8.20.0's cell had split the
  same way across the measurement's runs. A new row comes from two runs at least, and a cell
  they disagree on asserts only what both showed. (chez-curl, M6 slice 2, the Mac's runs)
* **A failure's code can be a race that Valgrind settles the other way.** HTTP/2 by prior
  knowledge to the origin's HTTP/1.1 face failed with one code natively on every lane, 30 of 30
  on each Docker lane and 10 of 10 on Guix's: 52 on 7.85.0, 56 on 8.5.0, 16 on 8.20.0 and 8.23.0. Under the memory gate's Valgrind it was
  mostly 55, the send failing: all 30 on OpenSSL's 8.5.0, 9 of 30 on 8.20.0, and on 7.85.0 52,
  55 and 16 each ([research](research/m7/slice1/valgrind-race/)). The builder's reading, not
  measured: the face's 400 and the end of its connection race libcurl's next send. A by-version test holding one code
  per row passed natively and failed the gate every time. A row of a failure's code is read
  natively and under the gate, and holds every code either gave. (chez-curl, M7 slice 1) And a
  row from runs that all agreed can still miss a code: Apple's 8.7.1 gave 16 in every run
  through M7 slice 3, then 56 through the engine three runs of three at slice 4, where curl's
  own tool gave 56 6 times of 200 against the origin as it was before the slice
  ([log](research/m7/slice4/results/mac-8.7.1-pk-h1-and-test-version.log)). A row of a racing
  code is read many times, not twice. (chez-curl, M7 slice 4, the Mac's run)
* **libcurl resends after a 417 only on a connection it keeps.** A caller's `Expect:
  100-continue` answered 417 makes libcurl send the request again inside the transfer, and a
  server that answers 417 to every such request makes it loop until `MAXREDIRS`; but 7.85.0
  and 8.20.0 resend only when the connection is not to close (`lib/http.c`,
  `!conn->bits.close`). With `Connection: close` the transfer ended at its 417, one request,
  where a kept connection made 51 (curl's tool on 8.20.0,
  [research](research/m7/slice2/verify/)). `node:http` cannot keep a connection whose request
  body never comes, so a test of the loop runs on the origin's raw face. (chez-curl, M7 slice 2)
* **Chez prints every field of a record that is not opaque, and `record-rtd` opens it.** A
  token handed to an assertion as its irritant printed its plan, and so its request's
  credentials, and through the engine's table another live request's Bearer token; `(write
  request)` printed the password too. A check that a refusal holds no secret walked pairs and
  vectors, so it could not see one inside a record either. Every record that holds a request, a
  plan, a token or credentials is opaque, and a test searches the printed text of each, and of
  each condition, and holds `record-rtd` raising on it ([review](research/m7/slice2/review/)).
  (chez-curl, M7 slice 2)
* **A 200 through a named proxy does not show the proxy was used.** A proxy URL whose userinfo
  decodes to a byte from 0x00 to 0x1F, `http://u%0D%0Ax:p@127.0.0.1:P/` among them, makes 7.85.0
  and Ubuntu's 8.5.0 drop the proxy and send the request straight to the origin, which answered
  200 while the proxy logged nothing; 8.20.0 and 8.23.0 fail 3. 7.85.0's `parse_proxy` jumps to
  its error path with its result still `CURLE_OK` when the decode fails (`lib/url.c:2512-2517`).
  Measured through the engine on the five lanes, twice, and again in my rerun
  ([research](research/m7/slice3/), [verify](research/m7/slice3/verify/)). A test of a proxy
  asserts the proxy's log, never the response alone. A variable's proxy goes the same way:
  `https_proxy`, `http_proxy` or `all_proxy` whose user or password decodes to 0x00 to 0x1F sent
  7.85.0 and Ubuntu's 8.5.0 direct, 200, the proxy logging nothing, where `%7F` went through it
  (the builder's probe on five lanes, and mine on 7.85.0 and 8.5.0,
  [verify](research/m7/slice3/verify/results/env-userinfo-floor-openssl.log)). chez-curl does
  not parse the variables (ADR-0024); README.org says so. (chez-curl, M7 slice 3)
* **Chez's record accessors print the object they refuse.** `(curl-request-url
  "http://u:PW@h/")` raised `"http://u:PW@h/" is not of type #<record type curl-request>`, the
  same for every raw accessor of the request and the responses
  ([verify](research/m7/slice3/verify/results/accessor-leak-guix-8.20.0.log)). An opaque record
  stops its own fields printing, not a caller's misplaced argument: wrap each public accessor,
  and name a wrong argument by its kind. (chez-curl, M7 slice 3's fix round)
* **A refusal can print the value a caller put in the wrong place.** `make-curl-request`,
  `curl-request-with`, `make-http-session`, `call-with-http-session` and `http-get` refused a
  non-symbol where a key belongs as `unknown-key`, naming it: a proxy URL, or slice 2's
  credentials list, given without its key printed its password, nine cases of nine; the leak
  test, which searched the proxy's own refusals, never looked there. The builder had already
  found `call-with-http-session`'s missing procedure printing a proxy URL the same way. A
  refusal names a caller's value by its field or its kind wherever it could hold a secret
  ([review](research/m7/slice3/review/), my rerun in [verify](research/m7/slice3/verify/)).
  (chez-curl, M7 slice 3's review)

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
  case is settled for M3: Chez locks no library's invocation, so an engine
  loads libcurl before its thread starts (ADR-0002, amended 2026-10-24).
  (chez-curl, M0 slice 3)
* **A top-level program runs every library body it reaches before its first
  line.** In a program importing `(curl private engine)` alone, and referring to
  it only on its last line, libcurl was already mapped at its first expression:
  the program's invoke requirements, and theirs, run first. So in a program no
  thread can make a first reference, and the M3 plan's check of the engine's
  load, a child whose first reference is `make-curl-engine`, passed with that
  early reference removed, 20 runs of 20: it could not fail, and was dropped.
  Only `eval`, in an `environment` that loaded a library without invoking it,
  reaches the race (spike E1's `load-race.sps`). (chez-curl, M3 slice 2)
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
  variable its free reads. M3 slice 2 deleted that path: the engine's thread runs no caller
  code, but for a process-wide `collect-request-handler`, which could escape there, and the
  window rule is all that stays (ADR-0013, amended 2026-10-25). (chez-curl)
* **`with-mutex` takes its mutex before its own `dynamic-wind`.** An engine's expiry between
  the two left the mutex held. Chez's mutexes are recursive, so the thread that held it never
  noticed, but every other thread then blocked on it: 4 of 11 mutants hung in the two-thread
  test, every thread in a futex wait. So every mutex is held through `critical-section`
  around `with-mutex`, and no hold waits (below). (chez-curl)
* **An after thunk that raises during an engine's expiry kills the engine.** The test hook's
  refusal of a continuation exit raises in its `dynamic-wind`'s after thunk. When an engine's
  fuel ran out inside the hook, that raise came during the engine's own unwind, and the call
  failed with `Exception in raise: no engine active`, in the first scoped review and again
  in fix round 3. A refusal in an after thunk is safe against a caller's continuation, not
  against an engine. (chez-curl)

* **A loop that waits in a plain foreign call stalls every other thread's
  collection up to about 500 times the wait.** Chez checks for a pending event
  only when a thread's event counter runs out, and `default-timer-ticks` is
  1000. A loop round a plain `curl_multi_poll` spends about two ticks per poll,
  so it checks about every 500 polls, and a collection another thread asks for
  waits until the next check: a lone one 51 to 466 polls in spike E1, by when it
  was asked. The worker's collections, close together, each waited 459. Beside a plain poll of 1 ms, its 15 ms of
  allocation took 5.4 s, and beside one of 300 ms it never finished. That looks
  like a deadlock, and isn't. `__collect_safe` deactivates the thread, so a
  collection need not wait: 15 ms. Spike E1 spent more ticks per turn, and the
  wait shrank to match: 87 polls with 9 more, 9 with 99, 1 with 999. A check
  that times one collection can pass by luck; ask for them back to back. The E5
  series measured 10 s behind a 300 ms timer, whose callback ran Scheme each
  turn; how many ticks that spent is unmeasured. (chez-curl, the M3 plan and
  spike E1)
* **Chez gives Ctrl-C to the main thread alone, and a waiting thread answers
  it late.** `c/schsig.c` drops SIGINT in any thread but the main one. A main
  thread in `condition-wait` ran its keyboard-interrupt handler only when the
  wait ended, 3 s later, even with timed waits of 100 ms in a loop: the event
  counter again. Leaving a critical section runs pending events at once, so
  timed waits each inside their own `critical-section` answered within one
  wait. But a thread waiting inside a critical section stays active: Chez's
  `condition-wait` deactivates it only with interrupts on. So every other
  thread's collection waited for the wait to end, a median 80 ms of 100, and a
  prototype engine's transfers, awaited so, took 100 or 200 ms each, its own
  thread held in a collection. A wait whose mutex a critical `dynamic-wind`
  held, waiting with interrupts on, answered Ctrl-C and stalled no collection
  in a test, but deadlocked in use: a waiter holding the mutex with interrupts
  on joined a collection, while a thread blocked on that mutex with interrupts
  off stayed active, and four caller threads hung within 1 s. So a wait polls,
  holding nothing while it sleeps (ADR-0013, amended 2026-10-25, after the
  slice's review). Spike E1 sent SIGINT to the other thread's id instead: the handler never
  ran. On Linux, Chez installs its handler without `SA_RESTART`, so the signal
  ended that thread's `sleep` and `curl_multi_poll` at about 1 s, but not its
  `condition-wait`. So a signal the kernel hands an engine's thread is lost,
  and ends its poll early. glibc's `system` also ignores SIGINT in the whole
  process while its command runs (`system(3)`): a Ctrl-C test captures nothing
  while it waits. (chez-curl, the M3 plan, spike E1 and M3 slice 2)
* **Chez's UTF-8 decoders drop a leading byte-order mark, the strict one too.** `utf8->string`,
  and `bytevector->string` with a transcoder whose error-handling mode is `raise`, read EF BB
  BF at a bytevector's start as nothing, and keep the next one: two give one U+FEFF. M5 slice
  1's strict decode of `curl_url_get`'s answers would have answered `"x"` for the query of
  `http://h.example/p?\xFEFF;x`; it puts the character back, and `test-url-parts` holds a query
  and a fragment that begin with it. (chez-curl, M5 slice 1)
* **Under Valgrind a collection takes about 140 ms, so a timed window can catch one.**
  test-engine's check that a failed engine's second stop returns within 50 ms took 142 to 145
  ms in 2 of 3 Valgrind runs on M5 slice 1's branch, which allocates more, and passed on main;
  a copy that counted `(collections)` showed one in the window. `(collect)` just before a short
  timed window opens leaves none due inside it ([research](research/m5/valgrind-collect/)).
  (chez-curl, M5 slice 1)
* **An engine's expiry can have a window of a few ticks, which a coarse sweep steps over.**
  On a copy of `run-parallel` without its closed check, an expiry let a resumed `http-parallel`
  enter calls into its closed group only at fuels 4,436 to 4,454 of 2,000 to 6,000, swept by 2,
  for four calls ([research](research/m5/group/traps/)). M5 slice 4's first engine sweep, by
  100, missed it, and that mutant survived. A narrower window, where only a call never entered
  is cancelled, held 3 ticks, 4,242 to 4,244 ([research](research/m5/group/engine/)), and moved
  between runs: a sweep by 2 hit it once or not at all, and a mutant there survived one run and
  died the next. Find the band first, then sweep it by single ticks, beside an evidence test
  that the sweep landed there. (chez-curl, M5 slice 4)
* **`engine-block` suspends an engine at once, even inside a critical section,** where a
  timer's expiry waits for a later event check: the expire procedure ran before the rest of the
  section ([research](research/m5/group/engine/), `engine-semantics.out`). A test that places
  an expiry with `engine-block` must call it outside every section, or it tests a place no real
  expiry reaches. An expiry runs every after thunk before the expire procedure, and every
  before thunk again on resume. (chez-curl, M5 slice 4, its third review)
* **A raise made inside a critical section runs its handler there, with interrupts off.** A
  `with-exception-handler` handler around `go` saw interrupts off for the `closed` that `go`'s
  recheck raised inside its entry's section, and on for the same refusal raised outside one
  (`go-recheck-round2.out`, `go-recheck-round3.out`): such a handler cannot wait, and Ctrl-C
  waits for it. A section answers a refusal as data, and the raise comes once it has ended.
  (chez-curl, M5 slice 4, its third review)
* **`(collect)` raises while another thread is active.** With a thread asleep inside a critical
  section, as `call-with-engine-held`'s holder can be, `(collect)` raised "cannot collect when
  multiple threads are active", and `(collect-rendezvous)` waited the 2,000 ms until that thread
  left its section, then returned ([research](research/m5/group/traps/)). Collect before such a
  thread starts, or rendezvous, which waits for it. M5 slice 4's builder met it planting a held
  engine. (chez-curl, M5 slice 4)
* **Under Valgrind a sleep of no time may not let another thread run.** test-url's flip test
  yielded with `(sleep (make-time 'time-duration 0 0))` so its flipper would run; in one of three
  runs on M5 slice 1's branch the flipper never did, 0 refusals of 1000, where 1 ms gave 490 to
  500 in each of six ([research](research/m5/valgrind-yield/)). A thread that must let another
  run sleeps for real. (chez-curl, M5 slice 1)
* **A timer's sweep cannot show what a keyboard interrupt does as a critical section ends.** The
  M6 plan's port probe swept a timer's expiry across a custom port's `read!` a tick at a time and
  lost no byte, on every path ([research](research/m6/ports/), C10). Its review then blocked a
  `read!`'s take on its mutex, as `locked` holds one, sent SIGINT, and let the holder go: a
  handler that escaped as the take's section ended lost the piece the take had removed, under
  `get-bytevector-some` and `get-u8` alike, 3 runs of 3, two the review's and one mine
  ([research](research/m6/review/)); one that returned lost none. A take that must not lose
  leaves what it took in place inside its section, and removes it after, the last thing before it
  returns. That opens a second trap: the producer side can pause between the take's section and
  its removal, so a resume the take decides once is never queued. The second review's model of
  that take stalled 44, 45 and 55 times in 50,000 pieces ([research](research/m6/review2/));
  deciding the resume at every look, 0. (chez-curl, the M6 plan's two reviews)

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
  - **The fatal check stops at an option a newer curl dropped.** 8.20.0's `./configure`
    has no `librtmp`, `wolfssh`, `hyper` or `msh3` options, all on the floor's line, and
    8.23.0 drops `smb` and `tls-srp` too. So `build-curl.sh --current` has a line of its
    own, read against 8.20.0's `--help`, which also names two libraries curl 8 looks for:
    libuv, and Apple's IDN (ADR-0020). (chez-curl, 2026-10-26)
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

  A server reads it so too. CI's first run, on Node 22.23.4, failed test-curl-testing's check
  that the peer sees the probe's reset: its stand-in server, which judged by Node's events,
  recorded a FIN. Every Node 20 and 22 release to 20.20.2 and 22.23.4 bundles a libuv older
  than 1.52, 22.23.4 1.51.0 (nodejs.org's release index, kept), and the probe's comment had
  said 22 only to 22.22.0. A
  server whose loop was blocked 200 ms as each connection arrived read an end in 20 runs of 20
  on 22.23.4 and 20.10.0, while one read(2) of its fd threw `ECONNRESET`; 24.18.0 read the
  reset 20 of 20 ([research](research/ci-first-run/)). The stand-in now blocks so and reads
  its fd once on each end; without the read the check fails on both. (chez-curl, CI's first
  run)
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
  flippers yield in each state. (chez-curl) **Pace the loop that races it too.** A flip test's
  refusal waits for nothing, so the next attempt can read the flipper's same CR, the flipper
  never run between: test-unsupported's list's-string flip test saw only refusals, all 300,
  in 6 runs of 20 under the memory gate on `main`'s tree, 5 of 20 on the carried branch's, and
  CI's memory job at `473b1b4`; with the loop sleeping 1 ms after a refusal, 0 of 20, and it
  still failed when CR was let through ([verify](research/m7/carried/verify/flip/)).
  test-transfer's two flip tests got the same pause after failing 5 runs of 22 there
  ([guard](research/m7/carried/guard/), the fix round). test-transfer-tls's CA-file flip test,
  the same shape, passed 32 of 32, why not measured. (chez-curl, after M7)
* **One protocol pin hides the other's removal.** libcurl checks a followed URL against both
  `PROTOCOLS_STR` and `REDIR_PROTOCOLS_STR`, so a redirect to `ftp://` is refused with
  either one alone. M2 slice 2's redirect test caught only both removed. Each pin is held by
  a test that reads the transfer's options as data. (chez-curl)
* **An ambient proxy variable diverts every transfer.** libcurl reads `http_proxy` and the
  rest from the environment. With `http_proxy=http://127.0.0.1:9`, a transfer to the origin
  answered 7, and a proxy that answered would have fed the suite its answers. So
  `test-transfer`'s first test fails, naming the variable, when one is set. chez-curl's
  proxy policy is M4's. (chez-curl)
* **Guix's libcurl writes `SSL_CERT_FILE` and `SSL_CERT_DIR` over a transfer's CA
  settings.** Guix patches libcurl (`curl-use-ssl-cert-env.patch`) to read both at
  `curl_global_init`. For 8.20.0 it then sets them as `CAINFO` and `CAPATH` in
  `Curl_ssl_easy_config_complete`, which runs when a transfer starts, after every setopt.
  In M2 slice 3's measurement, a request whose CA file was the run CA was refused, 60, with
  `SSL_CERT_FILE` at another CA. One naming the other CA passed with `SSL_CERT_DIR` at a
  directory holding the run CA. A Guix profile with `nss-certs` exports both, and so does
  the maintainer's host. The container passes neither, so only a shell outside it, or a
  child given one, shows it. Guix's 8.6.0 carried an older version of the patch, which set
  them as a handle's defaults, so a request's settings won there: the override is the
  patch version's, not Guix's. `test-transfer-tls` fails first when either is set. Since M4
  slice 3 a submit refuses a CA file on a Guix libcurl with either set, and the suite pins
  that refusal (ADR-0018; ADR-0024). (chez-curl)
* **Ubuntu's libcurl trusts its default `CAPATH` beside `CAINFO`.** It is built with
  `/etc/ssl/certs` as its CA directory, and setting `CAINFO` leaves that in place. So a
  request naming one CA file also trusts the whole system store. No test lane's store
  trusts the run CA, so every behavioural case passed either way. Only a throwaway
  container with the run CA installed in its store showed it: a CA file naming the other
  CA passed on Ubuntu's 8.5.0, with OpenSSL and with GnuTLS, until `CAPATH` was cleared.
  The transfer clears it, and `test-transfer-tls` holds the settings as data (ADR-0018).
  (chez-curl)
* **Apple's LibreSSL checks the keychain when a CA file fails.** Reported as curl issue
  12604 (2024), and called intended by Apple: with `--cacert`, a server the CA file does not
  verify still passes if the keychain trusts it. It is in Apple's LibreSSL, not curl. The
  Mac's libcurl is MultiSSL, and its drift row reads `SecureTransport (LibreSSL/3.3.6)`, which
  this entry first read as a library process selecting SecureTransport. That row is read before
  the init: the init puts LibreSSL in use unless `CURL_SSL_BACKEND` names another, by a C probe
  and by chez-curl alike, and the Makefile sets `secure-transport` for the Mac's suites
  ([mac](research/m7/carried/mac/mac-8.7.1-backend.log), after M7; the MultiSSL entry below).
  No test can show the fallback without adding a CA to the keychain. (curl, chez-curl)
* **A stalled name lookup blocks libcurl's teardown, and a timeout, for about
  10 s.** libcurl resolves on a thread, and by default waits for it. With a DNS
  server that never answers:
  - on 7.85.0 and Ubuntu's 8.5.0, a cancel blocked in `curl_multi_remove_handle`
    for 9.7 s, and a 1 s timeout arrived at 10 s, from inside one
    `curl_multi_perform` call;
  - on 8.20.0, `curl_multi_cleanup` blocked as long, and so did
    `curl_easy_cleanup` after `curl_easy_perform`, which M2's blocking path
    bound plain: 9 s, until M3 slice 2 deleted it (spike E1).

  An engine thread would hold every transfer for that time. `QUICK_EXIT` and
  `CURLMOPT_QUICK_EXIT` make libcurl leave the thread behind instead, and from
  M3 slice 3 every engine sets both where libcurl knows them. The container
  cannot stall a lookup, since it has no `/etc/resolv.conf`. A stand-in
  `getaddrinfo`, `tests/stall-getaddrinfo.c`, preloaded, stalls libcurl's
  resolver as a silent DNS server did, on every Linux libcurl recorded, and
  `test-engine` runs it, with a control per option. macOS has no `LD_PRELOAD`
  (ADR-0019, amended 2026-10-25). (curl, the M3 plan)
* **On 7.85.0 and 8.5.0, a multi option's answer says nothing of its value.** A probe set
  each long `CURLMOPT_` to values from -(2^62) to 2^40. 7.85.0 and Ubuntu's 8.5.0
  answered `CURLM_OK` to every value of every option they know; only 8.20.0 refused
  some, a negative `MAX_TOTAL_CONNECTIONS` among them. So on the Mac's 8.7.1 a
  `curl_multi_setopt` binding that drops its annotation might pass any check by code.
  Measured on the Mac on 2026-10-26, Apple's 8.7.1 answers as 7.85.0 and 8.5.0 do,
  `CURLM_OK` to every value of every long option it knows.
  `test-variadic` watches the value arrive by behaviour: at `MAX_TOTAL_CONNECTIONS`
  1 two drips run one after the other, and at 2 together (ADR-0001, amended
  2026-10-25). (chez-curl, M3 slice 3)
* **A probe that polls once more before it reads its clock reports late.** The
  two-drip probe drained the last transfer's message, polled 100 ms, and only then
  saw that both were done and stopped its clock. Its "both done" times, 1,108 to
  1,113 and 2,120 to 2,225 ms, went into ADR-0001 about 100 ms late; the times it
  read as each message came, 1,007 to 1,013 and 2,017 to 2,124 ms, did not. The
  variadic agent found it by its suite's own clock. Stop the clock where the
  condition is first seen. (chez-curl, M3 slice 3)
* **Setting `C_INCLUDE_PATH` drops what it held.** GCC adds the variable's
  directories to its default search path, but in the Guix container the variable is
  the only route to glibc's and the kernel's headers: it names the profile's include
  directory. Set to the
  floor curl's headers alone, `curl/system.h`'s `sys/socket.h` could not find
  `asm/socket.h`, and every compile failed, exit 1. Prepended,
  `C_INCLUDE_PATH=DIR:$C_INCLUDE_PATH`, the compile passed. Ubuntu keeps its system
  headers on the compiler's default path, so CI's floor lane does not hit it.
  (chez-curl, M3 slice 3)
* **A thread a suite forks must answer whatever it raises, and its waiter must be
  bounded.** `test-engine`'s two caller threads awaited a shared transfer with no
  `guard`, and the main thread waited for them on a `condition-wait` with no bound. On
  curl 8.23.0 the shared transfer failed, both threads died printing "Exception in
  curl-transfer", and the suite hung until `make test` killed it at 300 s: `HUNG`, no
  test named. Now each thread's raise is its answer, and the wait polls under a bound,
  so the check fails by name. (chez-curl, curl 8.23.0)
* **curl 8.23.0 reuses, without checking it, a connection that went back to its pool
  under 1 s before, however old.** `Curl_cpool_conn_seems_healthy` checks an idle
  connection only when its last check is 1000 ms old, and `Curl_cpool_return` sets that
  check each time a connection goes back to the pool; 8.20.0 checked each one before
  reuse. I first wrote "under 1 s old": the review showed 55 with connections 1.8 s old,
  returned at once. A server that closes a connection without `Connection: close`, as the
  raw face does after every script, leaves it in the pool, dead. On 8.23.0 the next
  transfer reuses it, retries on the next as each dies, and after five retries gives up
  with `CURLE_SEND_ERROR`, 55, "Connection died, tried 5 times before giving up": six such
  connections back in the pool within the last second fail the transfer after them.
  Six need six transfers live together: drips whose submits spread past one drip's length
  share connections.
  So `test-engine`'s checks that run drips together each make an engine of their own,
  and `reuse-verdicts` pins each libcurl's answer by version (ADR-0020, amended
  2026-10-26). (chez-curl, curl 8.23.0)
* **A failed transfer's timings move with the version, and 8.23.0 fills pretransfer even when
  nothing was sent.** M4's plan had a failure carry its timings, so a retry policy could tell
  whether a request went out. Measured on five libcurls (M4 slice 1): for a connect that was
  refused, 8.20.0 reports a total of 0, 7.85.0 and 8.5.0 the time it took, and 8.23.0
  pretransfer and starttransfer too, 95 µs; for a TLS handshake ended by the connect timeout,
  8.23.0's pretransfer is 301 ms. `CURLINFO_REQUEST_SIZE` was 0 on every failure that sent
  nothing, on all five. A test of "the request was sent" by a timing passes on one libcurl
  and lies on the next.

  The request size is no head length either: it sums every send of every attempt, the
  body's too. Measured with a fresh handle per transfer, it was the head's exact length, and
  `test-request` asserted that. Through one engine on curl 8.23.0, which reuses a dead
  connection unchecked, the head went out twice and the size read 150 for 75: the `current`
  lane failed, as the slice's review had predicted from libcurl's source. A request-size
  check runs on an engine of its own, its pool empty. (chez-curl, M4 slice 1)
* **A `while read` loop whose body runs a command that reads stdin loses the rest of its
  list.** The slice's mutation runner read its mutants with `while read`, and ran
  `scripts/guix-env` in the loop's body; the container's shell read the rest of the list from
  the same stdin, and the sweep ended after five of 27 mutants, printing `done` as if it had
  finished. Give every command in such a loop `< /dev/null`, and check the count of results
  against the list's. (chez-curl, M4 slice 1)
* **A waiter's sleeps keep the phase of its start, and a probe's events can share it.** The
  slice's delay probe paused each transfer a multiple of 10 ms, from its submit, and a wait's
  polling sleeps, doubling to 10 ms from the same submit, read every 10 ms after in one phase.
  So every completion met the wait at the same point of its sleep, and the delay read 0.9 to
  3.2 ms where it spans 0 to 10. Pauses spread over every residue modulo 10 gave 0 to 9.6. A
  probe of a periodic waiter spreads its events over every phase of the period.
  (chez-curl, M4 slice 2)
* **A Chez timer cannot plant an escape where a keyboard interrupt lands.** A timer that runs
  out inside a critical section runs its handler at a later event check, which can be the
  1000-tick counter's whole run after the section ends; a keyboard interrupt made pending
  inside the section runs as it ends. A sweep of `set-timer` from 1 to 300 ticks escaped
  before the take at 1 to 6 and after it had returned at 7 to 26, never between, where a
  SIGINT escapes between; from 27, the take ended first. To plant an escape at a section's end, hold the mutex the code blocks on, inside
  that section, from another thread, and signal meanwhile. (chez-curl, M4 slice 2)
* **GnuTLS answers a malformed PKCS#11 URL as it answers a missing file: 77.** The slice's
  probe judged a CA path read as a PKCS#11 URL by 60 and one read as a file by 77, a missing
  file's code. `pkcs11:ca.pem` answered 77 with a file of that name beside the probe, a copy
  of the run CA: GnuTLS had parsed it as a URL, failed, and never opened the file. Only a
  file that is there, and trusted, tells "read as a file": each path tried became one, and
  200 alone counted. (chez-curl, M4 slice 3)
* **ADR-0002's world is libc's, not libcurl's.** Spike E1's Chez, built on Ubuntu, loaded
  Guix's libcurl 8.20.0 from the store through its path, and libc came from `/usr/lib`, so
  the world read FHS. A C probe built in the same Ubuntu showed that libcurl still writing
  `SSL_CERT_FILE` over the CA file. M4's first draft keyed Guix's override on the world, and
  would have let that through. The file a library is mapped from is its own: the
  `/proc/self/maps` line holding one of its entry points, symlinks resolved. And a copy of
  that file out of the store still carries the patch: the slice's review loaded one, and
  only the patch's own string tells it. (chez-curl, M4 slice 3)
* **Chez folds Unicode, so a fold meant for ASCII takes more.** `char-downcase` makes U+212A
  KELVIN SIGN `k`; `char-foldcase`, and so `string-ci=?` and `char-ci=?`, make U+017F LATIN
  SMALL LETTER LONG S `s` too. A prefix rule written with any of them refuses `p`, U+212A,
  `cs11:` as `pkcs11:`, though GnuTLS compares bytes and reads it as a file. Fold A to Z
  alone where the other side compares bytes, and test both chars. (chez-curl, M4 slice 3)
* **A MultiSSL libcurl names its first backend as the one in use until `curl_global_init`
  picks one.** `curl_version_info`'s `ssl_version` read `SecureTransport (LibreSSL/3.3.6)` on
  Apple's 8.7.1 before the init, and `(SecureTransport) LibreSSL/3.3.6` after it
  (`lib/vtls/vtls.c`, `multissl_version`). ADR-0018 read the first, and recorded the Mac's
  transfers as SecureTransport's; they ran on LibreSSL, whose keychain fallback undid a CA
  file. The features read before the init are the first backend's too: the Mac's drift row
  lacks HTTPS-proxy, which the probe after the init has. Read the backend in use after the
  init, the text outside parentheses. And name it as curl does: 8.7.1's SecureTransport is
  `secure-transport`, and `securetransport` reached it only because an unknown name falls to
  the first backend. (chez-curl, M4 slice 3)
* **libcurl 8.7.0 and 8.7.1 count no request bytes.** `CURLINFO_REQUEST_SIZE` read 0 on all 21
  of slice 1's probe transfers, the 200s among them, where 8.6.0 and 8.8.0 counted each
  request. Slice 1 measured five libcurls without them, and its check failed only when the
  Mac, which ships 8.7.1, first ran it. curl 8.8.0's release notes list the fix, bug 13269. A
  count measured on some versions says nothing of a version between them.
  (chez-curl, M4 slice 3)
* **An option on one easy handle can reach past its transfer.** Through chez-curl's hatch, a
  request with `RESOLVE` made a later request on the same engine, which never named it,
  reach its address on all five Linux libcurls: the DNS cache is the multi handle's. A
  `DOH_URL`'s lookups went through `https_proxy` with the transfer's `PROXY ""`; and
  `SSLENGINE_DEFAULT` sets OpenSSL's default for the process, by curl's source. A review of
  one option's effects reads what the transfer shares: its multi handle, its process, the
  process's streams. (chez-curl, M4 slice 4)
* **Some options make libcurl call its default read callback, which reads stdin.**
  `RESUME_FROM` beside a body set by `POSTFIELDSIZE_LARGE` and `COPYPOSTFIELDS` made 7.85.0
  read 11 bytes of stdin on the transferring thread, then send the body's first 5 bytes as
  bytes 3 to 7 of 8. 8.5.0, 8.20.0 and 8.23.0 answered 43. `COOKIEFILE "-"` read stdin on
  all five. (chez-curl, M4 slice 4)
* **libcurl's header checks read `HTTPHEADER` alone.** Through `http_proxy`, a
  `PROXYHEADER` of `Content-Length: 5` went out beside libcurl's own `Content-Length: 3`, and
  one of `Transfer-Encoding: chunked` beside it too, on all five Linux libcurls. A rule that
  holds the request's headers must hold every list that adds headers.
  (chez-curl, M4 slice 4)
* **A probe that watches fd 0's offset cannot see a read through `/dev/stdin`.** Reopening
  `/dev/stdin` on a regular file makes a file description of its own, with its own offset,
  so `SSLCERT "/dev/stdin"` left fd 0's offset at 0 whether or not it read. Watch a pipe's
  contents instead. (chez-curl, M4 slice 4)
* **A check of an order held by one element cannot see the order.** test-check-nothreads
  sorted `src/`'s files directory by directory, so `curl/` came before `curl.sls`, where the
  program sorts whole paths, `.` before `/`. It passed while `(curl)` was the only public
  library; `(curl unsupported)` failed it. (chez-curl, M4 slice 4)
* **Setting one part of a URL changes its percent-encoding's hex case, one way or the other by
  version.** `curl_url_set` of `CURLUPART_QUERY`, with `CURLU_APPENDQUERY` or without, wrote
  `%3D` as `%3d` on 7.85.0, 8.5.0 and 8.20.0, and `%3d` as `%3D` on 8.23.0; a whole URL parsed
  kept the case it was given on all five. So no case an encoder picks goes out alike when a
  part is set: ADR-0028 writes the URL and parses it whole. (chez-curl, M5 slice 1)
* **Setting a fragment part stores its bytes unchecked.** `curl_url_set` of
  `CURLUPART_FRAGMENT`, flags 0, put a space, a tab, a CR, 0x01 and 0x7F into the URL raw, and
  kept a raw 0xE9, on all five Linux libcurls, where a whole URL parsed refuses the first five;
  and it moved the hex case as a query's set does. `CURLU_URLENCODE` encodes `%` too, so `%e9`
  became `%25e9`, another fragment. ADR-0029 writes the URL and parses it whole, encoding a
  header's bytes first. (chez-curl, M5 slice 2)
* **On 8.20.0 and 8.23.0, libcurl's own resolution of a lone `#F` answers as
  `curl-url-with-fragment` does, but for hex given in lower case, which it raises.** Both keep
  the URL, and both encode a space, a control byte and a byte above 0x7F in upper case; so a
  test of the lone-`#` rule whose fragment held `%E9` passed every test there with the rule
  replaced by `curl-url-resolve`. Only lower-case hex, `%e9`, tells the two apart on those
  versions: the location probe's fragment log shows `#%e9x` resolved to `%E9x` and written whole
  as `%e9x`. (chez-curl, M5 slice 2)
* **libcurl treats a raw byte above 0x7F in a reference by where it sits.** Resolved against a
  base, `/caf\xE9` and `?q=caf\xE9` came back as `%e9` or `%E9`, by version, but
  `http://h.example/caf\xE9` came back holding the raw byte, on all five Linux libcurls, and was
  refused as not UTF-8. The location probe's 62 cases put every Latin-1 byte in a relative
  reference, so it said no resolution came back raw; the slice's review found the absolute one.
  A header's bytes are now encoded before they are resolved (ADR-0029, amended).
  (chez-curl, M5 slice 2)
* **libcurl gives an IPv6 host without its zone ID.** `curl_url_get` of the host of
  `http://[fe80::1%25eth0]/` and of `%25eth1` is `[fe80::1]` for both, on all five Linux
  libcurls; the zone is a part of its own, `CURLUPART_ZONEID`. An origin rule that compared
  hosts alone sent a call's credentials to another zone: the slice's review planted the
  redirect. (chez-curl, M5 slice 2)
* **libcurl resends a request HTTP/2 refused, a `post` among them, five times.** A server that
  answered each stream with `RST_STREAM`, `REFUSED_STREAM`, counted every request six times on
  all five Linux libcurls, then libcurl failed it with 56; the request size summed the six. A check
  that counts a retry's attempts at the origin over HTTP/2 counts libcurl's own resends too.
  (chez-curl, M5 slice 3)
* **A guard on `curl-error?` around an await cannot tell the transfer's failure from the
  caller's.** An interrupt handler that ran inside the await and raised a `&curl-error`, its
  own call's failure say, was read as the transfer's: with a retry policy the call resent a
  `post` while the first was still live, and left one running after it escaped. The first fix,
  to take a raise only when the token is done and awaiting it again raises that very object,
  awaited inside the guard's clause, with interrupts on: a handler that raised there was lost or
  misread, 100 of 100 calls in a storm raising `#f`. Wait with no guard around the wait, then
  read the done token's outcome as data, by `curl-token-outcome`. (chez-curl, M5 slice 3, its
  reviews)
* **A keyboard interrupt made pending inside a critical section runs as the section ends, still
  inside any guard wrapped around the section.** The drive's guard that read a submit's
  refusal wrapped the submit's critical section, so a Ctrl-C handler that raised a `&curl-error`
  as the section ended was read as the submit's refusal. The guard now sits inside the section,
  where only the submit's own raises reach it; a SIGINT child in `test-http-client` holds it.
  (chez-curl, M5 slice 3, its fix round)
* **libcurl decodes a host's percent-encoding, so a UTF-8 string can come back as bytes that
  are not UTF-8.** `http://caf%E9.example/` came back from `curl_url_get` as `caf` and the byte
  0xE9, whole and as the host, on all five Linux libcurls; `%C3` alone came back as a lone
  lead byte, and `%41` as `A`. The user info, the path, the query and the fragment kept their
  `%XX`. `utf8->string` would have read the byte as U+FFFD, and named a host no one gave, so
  every URL function refuses such an answer as `not-utf-8`. (chez-curl, M5 slice 1)
* **An engine's queue and live table both miss a token it is setting up.** The turn empties
  its queue in one hold of the engine's mutex and enters each transfer in its live table in a
  later one, after `start-transfer!`, so `curl-engine-queued-count` plus
  `curl-engine-live-count` reads 0 for a token neither done nor live. M5 slice 1's escape test
  used that sum as its witness and failed 5 of 40 runs under load; a probe then saw the gap
  on 299 of 300 submits ([research](research/m5/engine-window/)). Each count is read in a hold
  of its own, so the engine can also move the token between the two reads: the witness read 2
  once, for one transfer ([research](research/m5/http-client/witness/)). Read the token, or
  wait past the setup. (chez-curl, M5 slice 1)
  - **And the queue holds a token cancelled while queued after it is done.** The cancel ends
    such a token at once, on the caller's thread, but its submit stays in the queue until the
    engine's next turn takes it: read right after the cancel, the queued count was 1 for a done
    token in 3 of 3 runs, and 0 within 50 ms ([research](research/m5/group/traps/)). M5 slice
    4's turn child first read the counts `(0 1 0)` just after a group's escape. Read the live
    and transfer counts, or let the queue settle. (chez-curl, M5 slice 4)
* **libcurl rewinds a read callback's body before its next attempt, so a `PREREQFUNCTION` alone
  never sees a resend of a body it read from.** The M6 plan's first design refused a streamed body's
  second attempt in the prerequest callable, with no `SEEKFUNCTION`. On all five Linux libcurls
  the rewind failed first: `prereq_calls=1` and 65, or 56 on 7.85.0, with no seek and with one
  that answers `CANTSEEK` ([research](research/m6/pause/results/round2/)). The 42 the design
  cited came only where a seek had restarted the body. Refuse in the seek callable, and record
  the reason, so it wins over libcurl's code. (chez-curl, the M6 plan's review)
* **libcurl 7.85.0 and 8.5.0 lose a refusal the write callback makes inside `curl_easy_pause`'s
  replay:** the call answered 23, and the transfer then ended 0 without the chunk it refused,
  16,307 to 16,384 bytes, where 8.20.0 and 8.23.0 ended it with 23 ([research](research/m6/pause/results/round2/)).
  Treat any answer but 0 from `curl_easy_pause` as the transfer's failure. And **Ubuntu's 8.5.0
  spins `curl_multi_poll` while a transfer is paused,** 6.2 to 7.0 million returns in 3 s at
  100% of a core, which curl fixed in 8.6.0 (#12632). (chez-curl, the M6 plan)
* **On Apple's 8.7.1, one HTTP/2 stream's trouble fails its whole connection.** A write
  callback's error on one stream failed the other on the same connection with 16 (curl #13292,
  fixed in 8.8.0), so a body limit on one call could fail another; and a paused stream beside an
  active one filled libcurl's 64 MiB cap in 234 ms on loopback, and the active stream ended 56
  ([research](research/m6/pause/results/mac-8.7.1.log)). Every Linux libcurl failed the refusing
  stream alone. On 8.7.0 and 8.7.1 the engine does not multiplex (ADR-0030, amended).
  (chez-curl, the M6 plan, the Mac's run)
* **And 8.7.1 resends a streamed body from its middle:** it logs the failed rewind, 65, and sends
  the request again, reading on where the body stood. A reset after 81,920 bytes of an 8 MiB
  body brought a second request with its last 7,389,184 bytes
  ([research](research/m6/pause/results/mac-8.7.1-split.log)). The Linux libcurls end with 65
  before the next attempt. Only the prerequest callable sees that attempt, and it runs before
  the attempt's head is sent. (chez-curl, the M6 plan, the Mac's run)
* **Guix's libcurl 8.20.0 reads back, inside `curl_multi_perform`, a `curl_multi_wakeup` made
  before it,** so the `curl_multi_poll` after it waits for libcurl's own events, up to its
  bound. A C loop stepping as the engine does, waking its poll once a turn inside
  `curl_easy_pause` or between that call and the perform, saw 14 of 14 polls last 100 ms or
  more, up to 1005.1 ms, in each of three runs; a wakeup made after the perform ended the poll
  at once, 15 of 15. Marks around each call place the eventfd's `read` inside the perform, under
  `strace`. 7.85.0, both 8.5.0 builds, 8.23.0 and upstream's 8.20.0 with OpenSSL keep it
  ([research](research/m6/slice1/results/)). The M6 prototype's drains of 1 MiB took up to
  10,139 ms for it. The engine looks at its queue between its read and its poll, and skips the
  poll when a message is queued (ADR-0012, amended 2026-10-30). (chez-curl, M6 slice 1)
* **A caller's `Expect: 100-continue` makes libcurl resend a request inside one transfer on a
  417,** as an auth round or a followed redirect does. A streamed `post` naming it, against a
  server that answered 417 once, published the 417's head while its pieces and outcome were the
  resend's 200, on 7.85.0, 8.5.0 and Guix's 8.20.0; against one that answered 417 every time,
  two transfers made 62 requests on 8.20.0, then each failed: "Number of redirects hit maximum
  amount"
  ([research](research/m6/slice1-review/results/)). The M6 plan's "one transfer, one request"
  rule had listed only auth and redirects. A stream refuses the header as `stream-with-rounds`.
  (chez-curl, M6 slice 1's review)
* **A custom port serves bytes Chez has buffered to any thread, without calling `read!`.** After
  the owner's `get-u8`, another thread's `get-u8`, `lookahead-u8` and `get-bytevector-n` returned
  the buffered bytes and raised nothing, though `read!` checks the thread
  ([research](research/m6/slice1-review/port-thread.sps)). A thread rule held in `read!` holds
  only for reads that reach it, and for the close. And another thread's `get-bytevector-n` that
  needs more than was buffered takes the buffered bytes, then raises at `read!`, and loses them:
  the owner's next byte was 128, after 127 buffered
  ([research](research/m6/slice1-review2/results/port-overread-guix-8.20.0.log)). (chez-curl,
  M6 slice 1's reviews)
* **Which `Expect` values make libcurl wait for a 100 moves with the version.** 7.85.0 and both
  8.5.0 builds waited on `100-continue` anywhere in the value, in any ASCII case:
  `x100-continue`, `y100-continuez`, `a 100-continue` and `100-continue;q=1`; 8.20.0 and 8.23.0
  only on an element of a comma list ([research](research/m6/slice1-fix/expect/results/)). A
  rule held by one version's matching misses the other's: the stream's refusal matches the
  floor's, which covers the newer. (chez-curl, M6 slice 1's fix round)
* **A take, then a wait for the token's end, can wait out its bound on a stream.** The take's
  look queues a resume while the take still lends its piece; if the engine's replay runs before
  the take removes it, the replay counts the piece, pauses again, and no further look queues the
  next resume. The review's probe held the take at the gate seam: `(done-within-3s #f)`, then one
  more look ended it `(body-limit 23)` ([research](research/m6/slice1-review/replay-limit-race.sps)).
  A test that reads a stream's outcome drains it with `curl-token-next-piece`, which looks, first.
  (chez-curl, M6 slice 1's review)
* **Apple's 8.7.1 hands a chunk the write callback refused inside `curl_easy_pause`'s replay to it
  again, after the call answered 23.** The plan's probe saw it in the next perform
  ([research](research/m6/pause/results/mac-8.7.1.log), `W-replay-error`); slice 1's engine,
  which takes such a transfer out at once, met it there anyway, and the stream appended the
  refused chunk after the failure was recorded
  ([research](research/m6/slice1/results/mac-8.7.1-make-test.log)). No Linux libcurl calls the
  callback again. A callable refuses every call once its transfer has a reason recorded.
  (chez-curl, M6 slice 1, the Mac's run)
* **libcurl calls a read callback no more once it has read a sized body whole.** A put past
  `body-length` made after that, before the server answered, reached no callable, and a mutant
  that left its refusal to the read callback ended the transfer 200, on 7.85.0, Ubuntu's 8.5.0
  and Guix's 8.20.0 ([research](research/m6/slice2-build/results/)), though 7.85.0 and 8.5.0 offer
  65,536 bytes to the body's last byte. A refusal the read callback owns is read where the
  outcome is, too (ADR-0030, amended 2026-10-31). (chez-curl, M6 slice 2's build)
* **7.85.0's poll spins during a paused HTTP/2 upload only once DATA has gone.** With pacing
  off, an upload paused after 4,096 bytes spun in 8 runs of 10, 2,000 ms of CPU in a 2 s pause;
  one paused before its first byte, in none of 10
  ([research](research/m6/slice2-build/results/)). A control that pauses first measures nothing.
  (chez-curl, M6 slice 2's build)
* **A server's answer written as it accepts a connection races the client's request.** Natively
  on loopback, libcurl's request and its first ask for the body came first in 100 runs of 100,
  on all five Linux libcurls, so the early answer never reached the header callable first. Under
  the memory gate's Valgrind on 8.5.0 the answer came first, 20 of 20, and a 0 ms sleep after
  connect let it come first once in 4 on 7.85.0
  ([research](research/m6/slice2-build/results/)). A test that needs the answer first holds the
  client after connect, by a seam; one that cannot hold it asserts what holds both ways.
  (chez-curl, M6 slice 2's build)

  An answer written as the head arrives races libcurl's first ask for the body the same way.
  test-upload's body-asked check held `#t` for `/raw/answer`, 5 runs of 5 on each lane, and on
  CI's memory lane 8.5.0 read the answer first once: `#f` ([research](research/ci-first-run/)),
  which Valgrind here, at half a CPU too, did not repeat.
  A prerequest hold does not order it: the answer waits for the head, which the hold delays too,
  and held runs read `#t` on 7.85.0 and 8.5.0. The case now asserts what holds both ways, that
  its bit is whether the read callable was ever asked. (chez-curl, CI's first run)

  Over HTTP/2 too: `/answer`, written as the headers arrive, came before libcurl's first ask under
  the memory gate on 8.5.0 in 9 runs of 40, 4 of 20 on M7 slice 4's tree and 5 of 20 on main's,
  libcurl then never asking, and CI's memory job read `#f` on two attempts of three on PR #45
  ([races](research/m7/slice4/races/)). Its server now holds the answer, `hold=KEY`, until the
  test has seen the ask and ended the body. (chez-curl, M7 slice 4, CI)

* **On 8.20.0 and 8.23.0, an HTTP/2 3xx that arrives before a request's body is sent whole never
  ends the transfer.** libcurl logs "HTTP error before end of send, stop sending", aborts the
  upload, holds the whole response, then waits for its timeout: "Operation timed out after 5006
  milliseconds with 10 out of 10 bytes received", or for ever with none. A 413 or a 503 ends at
  once; 7.85.0 and 8.5.0 end every one. A whole body meets it as a streamed one does, and so does
  curl's own command-line tool ([verify](research/m6/slice3/verify/results/)). The measurement's
  server sent `Location` with its 3xx alone, which could not tell the status from the header: a
  probe that crossed them showed the status alone matters. A server that varies two things
  together hides which one a client answers. (chez-curl, M6 slice 3's measurements)
* **On macOS, two threads' calls of `system` run one after the other.** Each of two Chez
  threads ran `system "sleep 1"` at once: on Linux both ended at about 1,002 ms, on the Mac the
  second at about 2,035 ms, 3 runs of 3 ([research](research/m6/slice3-build/results/), the
  `mac-system-*` logs). A test-origin check made a release through capture-command 800 ms into
  a 5 s probe run the same way: on Linux the release arrived in time; on the Mac it ran only
  once the probe had given up, and the check failed though `/raw/release` answered `released`.
  A check that needs two commands running at once starts the long one through
  `open-process-ports`, which does not call `system`. (chez-curl, M6 slice 3, the Mac's run)
* **libcurl's `curl_easy_nextheader` walks every header it holds on each call, so reading n
  headers costs n².** Each call counts, from the first header, every one that shares the name
  of the one it returns: the loop is in `lib/headers.c` on 7.85.0, 8.20.0 and 8.23.0. 7.85.0
  caps no response's headers; 8.7.1 and 8.20.0 cap them at 300 KiB, 8.20.0 at 5,000 too. So on
  7.85.0 a GET of 100,000 headers took 30.4 to 31.5 s, all of it CPU, after the transfer had
  ended, and 50,000 took 7.3 to 7.7 s; 8.5.0 took 20,000, under its cap, in 1.9 s
  ([research](research/ci-first-run/)). test-transfer's 100,000 outlasted its 60 s bound on CI's
  floor lane once in three runs, and is now 50,000, still past every cap. A check of many headers
  stays near the newer caps. (chez-curl, CI's first run)
* **`FRESH_CONNECT` keeps the transfer that sets it off other connections, never others off
  its own,** and 7.85.0 reads `FORBID_REUSE` only as a transfer ends (`lib/multi.c:703`). So on
  7.85.0 a transfer through the environment's proxy, with no credentials, joined as a second
  HTTP/2 stream a live tunnel a named proxy's transfer had opened with alice's, both options
  set on it, and got 200; alone it was refused 407. Two runs of the review's probe and my rerun
  ([review](research/m7/slice3/review/), [verify](research/m7/slice3/verify/)). Only an engine
  that does not multiplex kept it off (ADR-0037, decision 11). A rule that keeps a connection
  to one transfer covers every transfer that could join it, not the one that set it.
  (chez-curl, M7 slice 3's review)
* **A socket `http.Server` hands its `connect` event is half-open:** `allowHalfOpen` is true, so
  a client's FIN ends nothing, and a stand-in proxy that keeps a refused `CONNECT`'s connection
  open never sees its count fall to 0. Destroy the socket on `'end'`. Measured by the builder's
  `halfopen.mjs` on Node 24.18.0, and by me on 24.18.0 and 20.10.0: 1 connection open after 1 s
  without the handler, 0 with it ([build](research/m7/slice3/build/),
  [verify](research/m7/slice3/verify/results/halfopen-node-20.log)). (chez-curl, M7 slice 3)
* **`curl_url` reports an empty query as `""` on 7.85.0 and 8.5.0, and as none from 8.20.0:**
  `http://h:3128/?` read `""` there and `CURLUE_NO_QUERY` on 8.20.0 and 8.23.0, with and
  without `CURLU_NON_SUPPORT_SCHEME` (the builder's probe on the five lanes,
  [`urlprobe-table.txt`](research/m7/slice3/build/results/urlprobe-table.txt)). A `(not query)`
  check passed in the container and refused `/?` on the floor. Read an empty part as none.
  (chez-curl, M7 slice 3's build)
* **A MultiSSL libcurl's features word, read before `curl_global_init`, holds none of the bits
  a backend sets.** `curl_version_info` computes the word at each call from the backend in use,
  and before the init that is the selector, which "supports nothing" (8.7.1
  `lib/version.c:424-428`, `lib/vtls/vtls.c:1306-1308`). chez-curl read its HTTPS-proxy check from
  the load's record, built before the init, so on Apple's 8.7.1 every `https://` proxy was refused
  `https-proxy-unsupported`, 29 failures in test-proxy
  ([Mac log](research/m7/slice3/results/mac-8.7.1-make-test.log)); no Linux lane is MultiSSL. Now
  the call after the init that reads the backend reads the word too, and the decoy libcurl's
  MultiSSL build sets the bit at its init, so a check that reads the word before fails on Linux.
  (chez-curl, M7 slice 3, the Mac's run)
* **A loaded cookie past the `Cookie` line's cap leaves every request to its host unterminated.**
  `COOKIELIST` caps no loaded line's name and value, where a server's `Set-Cookie` is held to
  4,096 bytes. When the first cookie a request would send passes 8,190 bytes, libcurl has written
  `Cookie: `, counts no cookie, and so writes no line end: the head's own last CRLF ends that
  line, the head never ends, and the request waits for its timeout, 28 (8.20.0
  `lib/http.c:2557-2600`). On all five lanes through the engine, and in plain C on a bare handle
  from a value of 8,180 bytes (8,150 on 7.85.0, whose cap counts the head built before the
  `Cookie` line, so a server's 4 KB cookie and a 4,200-byte path hang it too)
  ([verify](research/m7/slice4/verify/)). A stand-in that logs whole heads alone shows nothing:
  log a head left open when its connection closes. A load now caps name and value at 4,096
  (ADR-0035, decision 7). (chez-curl, M7 slice 4's measurement)
* **`node:http` drops a head its client leaves open:** a connection that ends mid-head reaches
  the server only as `clientError` `HPE_INVALID_EOF_STATE`, `bytesParsed` 0, `rawPacket`
  undefined, so an origin that logs requests saw nothing of libcurl's unterminated `Cookie:`
  head. A `'data'` listener of the server's own on each connection sees the bytes, and Node keeps
  parsing from the same events. Shown by the builder's `open-head-node.mjs`, and by me on Node
  24.18.0 and 20.10.0 ([build](research/m7/slice4/build/),
  [verify](research/m7/slice4/verify/results/trap-open-head-node-20.log)). (chez-curl, M7 slice 4)
* **`display-condition` prints every field of a condition that has no `&message`:** one holding a
  secret printed it, `&held: "S3cr3t"`; with a message it prints the who, the message and the
  irritants alone. Shown by the builder's `display-condition.sps`, and by me on Chez 10.4.0
  ([verify](research/m7/slice4/verify/results/trap-display-condition-guix.log)). A condition that
  can hold a secret carries a message. (chez-curl, M7 slice 4)
* **7.85.0 and 8.5.0 list a deleted or expired cookie only until libcurl next adds or sends
  one:** 7.85.0 purges as a cookie is added, as a transfer gathers the cookies it sends, and as a
  file is written, never as the jar is read out (`lib/cookie.c:1033`, `:1427`, `:1665`). The
  plan's probe loaded an expired line among fourteen, and read it as dropped on every lane; loaded
  alone it is listed. A test of what such a jar lists reads it out before anything else touches
  it. (chez-curl, M7 slice 4)
* **libcurl reads a cookie prefix's case one way for a load and another for a server's
  `Set-Cookie`:** 7.85.0, 8.20.0 and Apple's 8.7.1 match a loaded name's `__Secure-` or `__Host-`
  in any case, a `Set-Cookie` name's in its own case alone (8.20.0 `lib/cookie.c:499`, `:742`).
  So a server's `__secure-a`, not `Secure`, was stored and read out, then dropped as it was loaded
  back, every load answering 0: five lines out, one back, on 8.20.0. The load rule had been
  written from a matrix with no prefixed name. A load now refuses a prefixed line that breaks
  its prefix's rule (ADR-0035, decision 10). (chez-curl, M7 slice 4's review)
* **A failed engine completes its tokens before it frees its jars:** a jar's state read as soon
  as the failure's token is done can still be `live`. The builder's `failed-jar-state.sps`, six at
  once, 100 runs each: 17 of 600 reads saw `live`, and 26 of 600 in my run; after
  `curl-engine-stop` returned, all 600 read `closed`
  ([build](research/m7/slice4/build/results/failed-jar-state-guix-6x.log),
  [verify](research/m7/slice4/verify/results/trap-failed-jar-state-guix-6x.log)). The builder's
  first test of a hold let go once read it before the stop, and failed under load. Read what a
  failure leaves after the stop. (chez-curl, M7 slice 4's fix round)
* **`char-numeric?` takes Latin-1's other numerics:** U+00B2, U+00B3, U+00B9 and U+00BC to
  U+00BE, each of which `string->number` reads as `#f`. A digits check by `char-numeric?` let
  U+00B2 into an expiry, which then raised from `<=` where the rule meant to refuse it
  ([verify](research/m7/slice4/verify/results/trap-char-numeric-guix.log)). Where the other side
  reads ASCII digits, compare `#\0` to `#\9`. (chez-curl, M7 slice 4's review)
* **A collection requested while a thread sleeps inside a critical section stalls every other
  thread at its next event check, and a Ctrl-C made pending meanwhile runs where the stalled
  thread stopped.** test-group's children hold the engine's mutex from a thread that sleeps inside
  `call-with-engine-held`'s section; a collection the main thread asked for then waited for the
  hold's end, and so did the main thread, before go's submit had blocked. Its handler ran after
  the release in go's request building, where `call-state`'s guard compounded the child's planted
  `&curl-error`: CI's memory job, two attempts of three on PR #45. A collection planted 1 KiB past
  the child's ready line gave CI's answer, `(raise #f #t after-release ...)`, and main's tree
  failed as readily under planted collections; and submit-child, stalled so, passed with nothing
  submitted ([races](research/m7/slice4/races/), `results/trip-*`). The children now
  `collect-rendezvous` before the hold, hold until the signal has been sent, and assert that
  `(collections)` did not move between the hold's start and the handler. (chez-curl, M7 slice 4,
  CI) **The same stall reached test-http-client's and test-mailbox's children,** never checked
  for it until after M7: with a collection planted at the ready line, http-client's raise-child
  left compounded 1 time of 10, and its escape-child passed 10 of 10 though stalled, its output
  unable to show it; the mailbox child read `before` or `returned` 9 times of 20, M5's `escape
  before` on the floor lane among them. test-engine's child holds nothing, and the plant moved
  nothing there. Hold until the signal is sent, too: with a fixed 1 s hold and the signal at
  3.5 s, http-client's children passed, their handler run in the await, not the section
  ([races](research/m7/carried/races/), `results/children/`, mutant `f3`). (chez-curl, after M7)
* **libcurl 8.5.0 can read nothing from an HTTP/2 transfer paused for sending.** `drain_stream`
  sets the OUT bit beside IN while the upload is open (`lib/http2.c:211-218`), and
  `Curl_readwrite` returns at once when a paused direction's bit is set
  (`lib/transfer.c:1019-1056`), so the response can wait until the body resumes. Under the
  memory gate, a held `/answer` to a streamed body left paused hung 7 times of 160, the origin
  having answered within 1 ms of its release ([races](research/m7/slice4/races/),
  `results/hold-hang-*`). **It is a race, not a rule:** with the answer held and released as the
  request went out, racing libcurl's first ask for the body, a head wait saw nothing 9 times in
  4,760 native runs and 6 in 800 under Valgrind, on 8.5.0 alone; with the answer sent as the
  head arrived, 0 of 144; and 7.85.0, 8.20.0 and 8.23.0 never stalled. Stalled with nothing put,
  the wait ended only at the transfer's timeout, 28; the body's end brought the head 1 to 35 ms
  later ([guard](research/m7/carried/guard/), `results/lane-*-held*.log`). A test that needs the
  head before its body ends the body, or puts, first, and a check that the stall is gone takes
  hundreds of runs, not a handful. (chez-curl, M7 slice 4, CI; amended after M7)
* **A `guard` whose clauses decline a raise rewinds into it to re-raise it,** running every
  before thunk between again: R6RS re-raises a declined object "in the dynamic environment of the
  original call to raise". Inside `call-with-flagged-url`'s critical wind, whose before thunk
  refuses re-entry once its handle is freed, a Ctrl-C or timer handler's `(raise #f)` or
  `(raise-continuable 'tick)` came out of `call-state`'s `condition?` guard as
  `call-with-parsed-url`'s re-entry refusal, compounded, at every entry of the high level; in
  pure Chez, a declined symbol came out as a before thunk's raise, that thunk run twice
  ([guard](research/m7/carried/guard/), `results/guard-rewind.log`, `results/sigint-today.log`,
  rerun in `verify/`). A guard that must pass a raise on unchanged takes it `#t` and answers it
  as data. (chez-curl, after M7)
* **A large primitive copy makes no event check while it runs,** so it holds off a Ctrl-C and
  every other thread's collection with no critical section. A Ctrl-C raised just before a
  256 MiB `bytevector-copy` ran 206 to 208 ms later, before a 64 Mi-char `string-copy` 228 ms,
  before `string->utf8` of it 142 ms; the same 256 MiB copied in 4 KiB pieces answered it at
  once ([guard](research/m7/carried/guard/), `verify/copy-hold.log`). A call's checks copy its
  body so: the 256 MiB one held another thread's collection 149 ms (`results/cost-today.log`).
  A hold measured by a thread that asks for collections back to back counts the gaps its
  wake-ups wait too, and a collection just after a copy moves the new object, so time a Ctrl-C
  to see the copy alone. (chez-curl, after M7)
* **Node's HTTP/2 over TLS lost an `RST_STREAM` queued behind a write in progress.**
  test-origin-tls's `/refuse` read SETTINGS, its ACK and eof, no `RST_STREAM`: `main`'s floor run at `a075629`, and
  under the gate 5 runs of 21. Instrumented, the refusal first flushed the pending SETTINGS ACK
  and queued the frame behind it; TLSWrap reports a write that finished at once only at the next
  immediate; the client's close_notify, read with the request, ended Node's TLS socket at once,
  since the server was not half-open; and the frame's write then failed, `UV_EPROTO`. On 2 CPUs
  beside three busy loops, 76 of 200 refusals lost it; idle, 1 of 400. h2c never did, its writes
  finishing at once and its FIN in a read of its own, nor a refusal with nothing pending. The
  origin's HTTP/2 faces are now half-open and end a connection at the next immediate after the
  client's, and a test stops the origin across a request to force the order; `main`'s origin
  fails it every time ([races](research/m7/carried/races/), `results/`; rerun as mutant `o0`).
  (chez-curl, after M7)
* **A planted collection lands only where allocation next takes fresh space past its trip.**
  `(collect-trip-bytes 1024)` set just after a `collect-rendezvous`, with nothing much allocated
  after it, never fired, and the mutant that planted it passed every test; with 64 KiB allocated
  after it, the plant landed and the test failed ([races](research/m7/carried/races/), mutants
  `f2a` and `f2`, rerun in `verify/`). A plant allocates past its trip, or shows that it fired.
  (chez-curl, after M7)
* **A group submits a redirect's next hop inside its step's critical section,** before a Ctrl-C
  made pending there runs, so the raise's cancel races the engine's thread starting that
  transfer. test-call-checks' raise row at a step held 1 transfer started at every entry, and
  the OpenSSL lane started 2 once; with the child's handler made to sleep 100 ms, go and
  `http-parallel` started 2 in 10 runs of 10, `http-request` and `call-with-response-port` 1
  ([guard](research/m7/carried/guard/), the fix round's tally; rerun in `verify/`). A single call
  submits after its section. Count a group's started transfers there as one or two. (chez-curl,
  after M7)
