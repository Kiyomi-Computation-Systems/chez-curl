# Loading mutation log (M0 slice 3)

Evidence for the checks M0 slice 3 added, one part per step:

1. [The pure core](#the-pure-core): `require-threaded`, the conditions, the constants, discovery and verify.
2. [`check-seam`](#check-seam): the import-graph check (ADR-0007).
3. [The native layer](#the-native-layer): `(curl private native)`, `(curl)`, the refusal probe,
   the decoys and `make build`.
4. [Review fixes: loading](#review-fixes-loading): the load runs once per process, NULL strings,
   a C oracle, discovery by platform, raises that are not refusals, an in-process suite, and the
   library's report on a refusal.
5. [Review fixes: check-seam and require-threaded](#review-fixes-check-seam-and-require-threaded):
   no run-time imports, every library in a family, unread file endings named, Emacs lock files
   skipped, `(http-client …)` libraries ordered through `(curl)`, and the Chez 10.4.0 floor.
6. [Second review fixes](#second-review-fixes): `check-seam` as allowlists, with a standing test for every rule,
   the `.#` skip for dangling links only, the oracle's temporary directory, the Chez floor's pre-release edge,
   and an opaque report.

## The pure core

Evidence that the checks M0 slice 3's first step added fail through the property each claims
to guard ([harness plan](2026-10-04-harness-plan.md) §6,
[ADR-0001](decisions/0001-bind-libcurl-directly.md),
[ADR-0002](decisions/0002-runtime-libcurl-discovery.md),
[ADR-0003](decisions/0003-libcurl-floor-7-85.md)). The step is the pure core of loading:

- `src/curl/private/require-threaded.sls`, the refusal of a non-threaded Chez;
- `src/curl/private/conditions.sls`, `&curl-error` and its two subtypes;
- `src/curl/private/constants.sls`, the header constants loading needs;
- `src/curl/private/discovery.sls`, ADR-0002's search as a pure function;
- `src/curl/private/verify.sls`, ADR-0003's decisions on a loaded library's answers;
- `tests/test-require-threaded.sps`, `tests/test-conditions.sps`, `tests/test-discovery.sps`
  and `tests/test-verify.sps`;
- `LIBDIRS` in the `Makefile`, which now starts with `src`.

A driver in the session scratchpad ran every mutation. It froze a snapshot of the working tree,
without `.git`, `build/` or `.claude/`, and gave each mutation a fresh copy of it. It applied the
mutation by exact-text replacement, aborting unless the target occurred exactly once, and it
refused a mutation whose diff was empty. It touched the copy's `manifest.scm` (`traps.md`, the
stale `guix shell -m` profile) and ran `scripts/guix-env make test` from inside the copy, so the
container saw only that copy. A mutation counts as killed only when `make test` exits non-zero
and every expected line appears whole in its output: the suite's `FAIL <test name>` line, or
`make test`'s `test: FAIL <suite>` line. Each output was kept verbatim. The working tree was
never edited.

Each mutation ran in its own copy, so the clean rerun after each one is the baseline itself,
made on the same snapshot. **Result** quotes each run's `FAIL` lines with the suite's expected
and actual values, its `Exception` and `test:` lines, and nothing else. A line longer than 240
characters is cut, and says how much was cut.

Cases are named `CD` (conditions), `CN` (constants, through the verify suite), `VF` (verify),
`DS` (discovery), `RT` (the refusal), `RS` (the source tree the refusal suite reads), `RC` (that
suite's own checker) and `MK` (the Makefile).

### Red runs

**Before any code existed:** the four suites written, no `src/`, and the Makefile as `9bacc6d`
left it. `make test` exited 2. Three suites died at import, with no test run:

```
=== tests/test-conditions.sps
Exception: library (curl private conditions) not found
test: FAIL tests/test-conditions.sps (exit 255)
```

and the same for `test-discovery` and `test-verify`. `test-require-threaded` ran, and failed
seven tests by name:

```
FAIL src/ defines (curl private require-threaded)
  expected: defined
  actual:   absent
FAIL the scan read src/: conditions, constants, discovery and verify
  expected: (read read read read)
  actual:   (missed missed missed missed)
FAIL the order rows are live: src/ holds a library besides the refusal
  expected: live
  actual:   no-rows
FAIL the refusal exports nothing
  expected: ()
  actual:   no-refusal-source
FAIL the refusal asks (threaded?)
  expected: asks
  actual:   never-asks
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   no-refusal-source
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   no-refusal-source
# of expected passes      7
# of unexpected failures  7
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 2, failed 4, hung 0
```

The seven that passed are the checker's own seeded rows, which test code in the suite, not in
`src/`. RC1 to RC7 and RC11 fail each of them.

**Against stubs:** `LIBDIRS` changed, and five stub libraries with the real export lists. Each
stub procedure raised `not written yet`, each exported value was the symbol `not-written-yet`,
and the stub refusal exported nothing and refused nothing. No stub imported the refusal.
`make test` exited 2:

| Suite | Passed | Failed |
|---|---|---|
| `test-conditions` | 0 | 9 |
| `test-discovery` | 1 | 39 |
| `test-require-threaded` | 12 | 6 |
| `test-verify` | 0 | 18 |

Sixty-one actual values were `#f`, SRFI-64's rendering of a raise in the actual expression. No
expected value in these suites is `#f`. The two refusal tests in `test-conditions` got
`(other-raise "Exception in conditions: not written yet")`. The three exported lists got
`not-written-yet`, and the four import-order rows `absent`.

The passes:

- **`test-discovery`'s `the real /proc/self/maps is read on Linux, and only there`.** It tests
  the suite's own reader, so no library code can fail it. DS42 does.
- **`test-require-threaded`'s twelve.** The checker's seven seeded rows, plus five rows the stub
  satisfied as well as the real refusal: it is defined, the scan read the four libraries, rows
  exist, it exports nothing, and it loads. RS5, RS6, RC8, RC10, RT3 and RT5 fail those.

One test was written after these runs:
`libcurl-candidates refuses a Linux world that is neither guix nor fhs`. DS43 fails it.

### Baseline

On `9bacc6d` plus this step, as the snapshot every mutation copied (sha256 of its files, the
submodule aside, `9f553f4fc0a1b0d580e9620e44d7e34973ab7fe73a7e8996346dec46a65697b9`).
`make test` exited 0:

```
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
check-suites: every suite ends with (exit (suite-exit-status runner)) (6 checked)
=== tests/test-conditions.sps
%%%% Starting test conditions
# of expected passes      9
test: pass tests/test-conditions.sps
=== tests/test-curl-testing.sps
%%%% Starting test curl-testing
# of expected passes      26
test: pass tests/test-curl-testing.sps
=== tests/test-discovery.sps
%%%% Starting test discovery
this Chez's binary: /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme
# of expected passes      41
test: pass tests/test-discovery.sps
=== tests/test-manifest.sps
%%%% Starting test manifest
# of expected passes      4
test: pass tests/test-manifest.sps
=== tests/test-require-threaded.sps
%%%% Starting test require-threaded
# of expected passes      18
test: pass tests/test-require-threaded.sps
=== tests/test-verify.sps
%%%% Starting test verify
# of expected passes      18
test: pass tests/test-verify.sps
test: ran 6, passed 6, failed 0, hung 0
```

### Mutations

112 mutations ran. 108 were killed, each with every expected line present. Four survived, as
they were expected to: CN6, CN7 and CN8, constants nothing reads yet, and RC9, a scan root no
test can tell from `src/` today (see Not covered). Every one of the 86 tests in the four suites
was failed by name by at least one mutant. Coverage, at the end, lists which.

#### `(curl private conditions)`

##### CD1. `&curl-error` under `&serious`, not `&error`

**Guards:** &curl-error is an &error.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
- (define-condition-type &curl-error &error
+ (define-condition-type &curl-error &serious
```
**Result:** killed, exit 2:

```
FAIL make-curl-error: an error and a curl-error, and neither subtype
  expected: (#t #t #f #f)
  actual:   (#f #t #f #f)
FAIL library-unavailable: an error and a curl-error, not a wrong-thread
  expected: (#t #t #t #f)
  actual:   (#f #t #t #f)
FAIL wrong-thread: an error and a curl-error, not a library-unavailable
  expected: (#t #t #f #t)
  actual:   (#f #t #f #t)
test: FAIL tests/test-conditions.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CD2. `&curl-library-unavailable` directly under `&error`

**Guards:** &curl-library-unavailable is a &curl-error.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
- (define-condition-type &curl-library-unavailable &curl-error
+ (define-condition-type &curl-library-unavailable &error
```
**Result:** killed, exit 2:

```
FAIL library-unavailable: an error and a curl-error, not a wrong-thread
  expected: (#t #t #t #f)
  actual:   (#t #f #t #f)
test: FAIL tests/test-conditions.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CD3. `&curl-wrong-thread` directly under `&error`

**Guards:** &curl-wrong-thread is a &curl-error.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
- (define-condition-type &curl-wrong-thread &curl-error
+ (define-condition-type &curl-wrong-thread &error
```
**Result:** killed, exit 2:

```
FAIL wrong-thread: an error and a curl-error, not a library-unavailable
  expected: (#t #t #f #t)
  actual:   (#t #f #f #t)
test: FAIL tests/test-conditions.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CD4. The path and detail accessors swapped

**Guards:** each accessor reads its own field.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
-     (path curl-library-unavailable-path)
-     (source curl-library-unavailable-source)
-     (detail curl-library-unavailable-detail)
+     (path curl-library-unavailable-detail)
+     (source curl-library-unavailable-source)
+     (detail curl-library-unavailable-path)
```
**Result:** killed, exit 2:

```
FAIL library-unavailable carries its reason, path, source, detail and candidates
  expected: (load-failed "/opt/curl/lib/libcurl.so.4" override "libnghttp2.so.14: cannot open shared object file" ("/opt/curl/lib/libcurl.so.4" "/usr/lib/libcurl.so.4"))
  actual:   (load-failed "libnghttp2.so.14: cannot open shared object file" override "/opt/curl/lib/libcurl.so.4" ("/opt/curl/lib/libcurl.so.4" "/usr/lib/libcurl.so.4"))
test: FAIL tests/test-conditions.sps (exit 1)
FAIL override: a relative path is invalid-override, carrying the value, with no fallback
  expected: (refused invalid-override #f override "lib/libcurl.so.4" ())
  actual:   (refused invalid-override "lib/libcurl.so.4" override #f ())
FAIL override: a bare name is invalid-override
  expected: (refused invalid-override #f override "libcurl.so.4" ())
  actual:   (refused invalid-override "libcurl.so.4" override #f ())
FAIL override: set but empty is invalid-override
  expected: (refused invalid-override #f override "" ())
  actual:   (refused invalid-override "" override #f ())
test: FAIL tests/test-discovery.sps (exit 1)
FAIL check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.84.255" ())
  actual:   (refused below-floor "7.84.255" system "/usr/lib/aarch64-linux-gnu/libcurl.so.4" ())
FAIL check-version: every feature but SSL is no-ssl, with the version, path and source
  expected: (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "8.20.0" ())
  actual:   (refused no-ssl "8.20.0" override "/usr/lib/aarch64-linux-gnu/libcurl.so.4" ())
FAIL check-version: below the floor and without SSL, below-floor wins
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-home "7.81.0" ())
  actual:   (refused below-floor "7.81.0" guix-home "/usr/lib/aarch64-linux-gnu/libcurl.so.4" ())
FAIL check-apis: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-profile "curl_easy_option_by_name" ())
  actual:   (refused missing-api "curl_easy_option_by_name" guix-profile "/usr/lib/aarch64-linux-gnu/libcurl.so.4" ())
FAIL check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-system "curl_easy_header" ())
  actual:   (refused missing-api "curl_easy_header" guix-system "/usr/lib/aarch64-linux-gnu/libcurl.so.4" ())
FAIL check-apis: with both APIs missing, the option probe is named: it runs first
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_option_by_name" ())
  actual:   (refused missing-api "curl_easy_option_by_name" system "/usr/lib/aarch64-linux-gnu/libcurl.so.4" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 3, failed 3, hung 0
```

##### CD5. The constructor stores path and source swapped

**Guards:** the constructor stores its arguments in order.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
- (unchecked-make-curl-library-unavailable reason path source detail candidates))
+ (unchecked-make-curl-library-unavailable reason source path detail candidates))
```
**Result:** killed, exit 2:

```
FAIL library-unavailable carries its reason, path, source, detail and candidates
  expected: (load-failed "/opt/curl/lib/libcurl.so.4" override "libnghttp2.so.14: cannot open shared object file" ("/opt/curl/lib/libcurl.so.4" "/usr/lib/libcurl.so.4"))
  actual:   (load-failed override "/opt/curl/lib/libcurl.so.4" "libnghttp2.so.14: cannot open shared object file" ("/opt/curl/lib/libcurl.so.4" "/usr/lib/libcurl.so.4"))
test: FAIL tests/test-conditions.sps (exit 1)
FAIL override: a relative path is invalid-override, carrying the value, with no fallback
  expected: (refused invalid-override #f override "lib/libcurl.so.4" ())
  actual:   (refused invalid-override override #f "lib/libcurl.so.4" ())
FAIL override: a bare name is invalid-override
  expected: (refused invalid-override #f override "libcurl.so.4" ())
  actual:   (refused invalid-override override #f "libcurl.so.4" ())
FAIL override: set but empty is invalid-override
  expected: (refused invalid-override #f override "" ())
  actual:   (refused invalid-override override #f "" ())
test: FAIL tests/test-discovery.sps (exit 1)
FAIL check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.84.255" ())
  actual:   (refused below-floor system "/usr/lib/aarch64-linux-gnu/libcurl.so.4" "7.84.255" ())
FAIL check-version: every feature but SSL is no-ssl, with the version, path and source
  expected: (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "8.20.0" ())
  actual:   (refused no-ssl override "/usr/lib/aarch64-linux-gnu/libcurl.so.4" "8.20.0" ())
FAIL check-version: below the floor and without SSL, below-floor wins
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-home "7.81.0" ())
  actual:   (refused below-floor guix-home "/usr/lib/aarch64-linux-gnu/libcurl.so.4" "7.81.0" ())
FAIL check-apis: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-profile "curl_easy_option_by_name" ())
  actual:   (refused missing-api guix-profile "/usr/lib/aarch64-linux-gnu/libcurl.so.4" "curl_easy_option_by_name" ())
FAIL check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-system "curl_easy_header" ())
  actual:   (refused missing-api guix-system "/usr/lib/aarch64-linux-gnu/libcurl.so.4" "curl_easy_header" ())
FAIL check-apis: with both APIs missing, the option probe is named: it runs first
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_option_by_name" ())
  actual:   (refused missing-api system "/usr/lib/aarch64-linux-gnu/libcurl.so.4" "curl_easy_option_by_name" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 3, failed 3, hung 0
```

##### CD6. `missing-api` dropped from the reasons

**Guards:** the six reasons, all of them.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
- '(invalid-override not-found load-failed below-floor no-ssl missing-api))
+ '(invalid-override not-found load-failed below-floor no-ssl))
```
**Result:** killed, exit 2:

```
FAIL the reasons are exactly ADR-0002's and ADR-0003's six, in order
  expected: (invalid-override not-found load-failed below-floor no-ssl missing-api)
  actual:   (invalid-override not-found load-failed below-floor no-ssl)
FAIL the constructor takes each of the six reasons
  expected: (invalid-override not-found load-failed below-floor no-ssl missing-api)
  actual:   #f
test: FAIL tests/test-conditions.sps (exit 1)
FAIL check-apis: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-profile "curl_easy_option_by_name" ())
  actual:   (assertion-violation make-curl-library-unavailable)
FAIL check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-system "curl_easy_header" ())
  actual:   (assertion-violation make-curl-library-unavailable)
FAIL check-apis: with both APIs missing, the option probe is named: it runs first
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_option_by_name" ())
  actual:   (assertion-violation make-curl-library-unavailable)
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (readable readable other-raise other-raise)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 4, failed 2, hung 0
```

##### CD7. A seventh reason

**Guards:** the six reasons, no more.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
- '(invalid-override not-found load-failed below-floor no-ssl missing-api))
+ '(invalid-override not-found load-failed below-floor no-ssl missing-api unsupported))
```
**Result:** killed, exit 2:

```
FAIL the reasons are exactly ADR-0002's and ADR-0003's six, in order
  expected: (invalid-override not-found load-failed below-floor no-ssl missing-api)
  actual:   (invalid-override not-found load-failed below-floor no-ssl missing-api unsupported)
test: FAIL tests/test-conditions.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CD8. The reason check deleted

**Guards:** the constructor refuses any other reason.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
-     (unless (memq reason curl-library-unavailable-reasons)
-       (assertion-violation 'make-curl-library-unavailable
-                            "not a reason chez-curl refuses a libcurl for"
-                            reason))
+ (deleted)
```
**Result:** killed, exit 2:

```
FAIL the constructor refuses a symbol that is not a reason
  expected: (assertion-violation make-curl-library-unavailable (library-missing))
  actual:   no-raise
FAIL the constructor refuses a reason spelled as a string
  expected: (assertion-violation make-curl-library-unavailable ("not-found"))
  actual:   no-raise
test: FAIL tests/test-conditions.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CD9. A reason spelled as a string taken

**Guards:** a reason is a symbol, not a string.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
- (unless (memq reason curl-library-unavailable-reasons)
+ (unless (memq (if (string? reason) (string->symbol reason) reason) curl-library-unavailable-reasons)
```
**Result:** killed, exit 2:

```
FAIL the constructor refuses a reason spelled as a string
  expected: (assertion-violation make-curl-library-unavailable ("not-found"))
  actual:   no-raise
test: FAIL tests/test-conditions.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CD10. `error`, not `assertion-violation`

**Guards:** the refusal is an assertion violation.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
-       (assertion-violation 'make-curl-library-unavailable
+       (error 'make-curl-library-unavailable
```
**Result:** killed, exit 2:

```
FAIL the constructor refuses a symbol that is not a reason
  expected: (assertion-violation make-curl-library-unavailable (library-missing))
  actual:   (other-raise "Exception in make-curl-library-unavailable: not a reason chez-curl refuses a libcurl for with irritant library-missing")
FAIL the constructor refuses a reason spelled as a string
  expected: (assertion-violation make-curl-library-unavailable ("not-found"))
  actual:   (other-raise "Exception in make-curl-library-unavailable: not a reason chez-curl refuses a libcurl for with irritant \"not-found\"")
test: FAIL tests/test-conditions.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CD11. Expected and actual swapped

**Guards:** expected and actual are kept apart.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
-     (expected curl-wrong-thread-expected)
-     (actual curl-wrong-thread-actual)))
+     (expected curl-wrong-thread-actual)
+     (actual curl-wrong-thread-expected)))
```
**Result:** killed, exit 2:

```
FAIL wrong-thread carries who, expected and actual
  expected: (curl-multi-poll 3 7)
  actual:   (curl-multi-poll 7 3)
test: FAIL tests/test-conditions.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

#### `(curl private constants)`, through the verify suite

##### CN1. `CURL_VERSION_SSL` as 1<<3

**Guards:** CURL_VERSION_SSL is 1<<2.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
- (define curl-version-ssl #x00000004)
+ (define curl-version-ssl #x00000008)
```
**Result:** killed, exit 2:

```
FAIL check-version: every feature but SSL is no-ssl, with the version, path and source
  expected: (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "8.20.0" ())
  actual:   (returned #t)
FAIL check-version: SSL, 1<<2, alone is enough
  expected: (returned #t)
  actual:   (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "8.20.0" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CN2. `CURLHE_NOT_BUILT_IN` as 6

**Guards:** CURLHE_NOT_BUILT_IN is 7.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
- (define curlhe-not-built-in 7)
+ (define curlhe-not-built-in 6)
```
**Result:** killed, exit 2:

```
FAIL check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-system "curl_easy_header" ())
  actual:   (returned #t)
FAIL check-apis: every other header code is accepted
  expected: ((returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t))
  actual:   ((returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_header" ()) (returned #t) (returned #t))
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (readable readable readable no-raise)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CN3. Two feature bits swapped

**Guards:** each feature has its own bit.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
- '((ipv6         . #x00000001)     ; CURL_VERSION_IPV6         (1<<0)
-       (kerberos4    . #x00000002)
+ '((ipv6         . #x00000002)     ; CURL_VERSION_IPV6         (1<<0)
+       (kerberos4    . #x00000001)
```
**Result:** killed, exit 2:

```
FAIL feature-names: each bit alone names its own CURL_VERSION_ feature
  expected: ((ipv6) (kerberos4) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (http2) (gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi-ssl)  …[71 more characters]
  actual:   ((kerberos4) (ipv6) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (http2) (gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi-ssl)  …[71 more characters]
FAIL feature-names: only the bits that are set
  expected: (ipv6 ssl http2 threadsafe)
  actual:   (kerberos4 ssl http2 threadsafe)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CN4. `threadsafe` moved to the front

**Guards:** the table is in curl.h's order.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
-   (define curl-version-features
-     '((ipv6         . #x00000001)
+   (define curl-version-features
+     '((threadsafe   . #x40000000)
+       (ipv6         . #x00000001)
```

In `src/curl/private/constants.sls`:

```diff
-       (gsasl        . #x20000000)     ; CURL_VERSION_GSASL        (1<<29)
-       (threadsafe   . #x40000000)))   ; CURL_VERSION_THREADSAFE   (1<<30)
+       (gsasl        . #x20000000)))   ; CURL_VERSION_GSASL        (1<<29)
```
**Result:** killed, exit 2:

```
FAIL feature-names: every bit set names every feature, in curl.h's order
  expected: (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl th …[9 more characters]
  actual:   (threadsafe ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hs …[9 more characters]
FAIL feature-names: only the bits that are set
  expected: (ipv6 ssl http2 threadsafe)
  actual:   (threadsafe ipv6 ssl http2)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CN5. `gsasl` dropped from the table

**Guards:** every bit in curl.h is in the table.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
-       (gsasl        . #x20000000)     ; CURL_VERSION_GSASL        (1<<29)
+ (deleted)
```
**Result:** killed, exit 2:

```
FAIL feature-names: each bit alone names its own CURL_VERSION_ feature
  expected: ((ipv6) (kerberos4) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (http2) (gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi-ssl)  …[71 more characters]
  actual:   ((ipv6) (kerberos4) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (http2) (gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi-ssl)  …[75 more characters]
FAIL feature-names: every bit set names every feature, in curl.h's order
  expected: (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl th …[9 more characters]
  actual:   (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts threadsa …[13 more characters]
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### CN6. `CURLE_OK` as 1

**Guards:** CURLE_OK is 0 (no consumer until native.sls; slice 4 checks it).
**Mutation:** In `src/curl/private/constants.sls`:

```diff
- (define curle-ok 0)
+ (define curle-ok 1)
```
**Result:** survived, as expected: exit 0, and `make test` printed `test: ran 6, passed 6, failed 0, hung 0`.

##### CN7. `CURL_GLOBAL_DEFAULT` as 0

**Guards:** CURL_GLOBAL_DEFAULT is 3 (no consumer until native.sls; slice 4 checks it).
**Mutation:** In `src/curl/private/constants.sls`:

```diff
- (define curl-global-default 3)
+ (define curl-global-default 0)
```
**Result:** survived, as expected: exit 0, and `make test` printed `test: ran 6, passed 6, failed 0, hung 0`.

##### CN8. `CURLVERSION_TENTH` as 11

**Guards:** CURLVERSION_TENTH is 9 (no consumer until native.sls; slice 4 checks it).
**Mutation:** In `src/curl/private/constants.sls`:

```diff
- (define curlversion-tenth 9)
+ (define curlversion-tenth 11)
```
**Result:** survived, as expected: exit 0, and `make test` printed `test: ran 6, passed 6, failed 0, hung 0`.

#### `(curl private verify)`

##### VF1. The floor at 7.84.0

**Guards:** the floor is 7.85.0, not 7.84.0.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- (define libcurl-floor #x075500)
+ (define libcurl-floor #x075400)
```
**Result:** killed, exit 2:

```
FAIL the floor is 7.85.0, #x075500
  expected: 480512
  actual:   480256
FAIL check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.84.255" ())
  actual:   (returned #t)
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (no-raise readable readable readable)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF2. The floor at 7.85.1

**Guards:** the floor is 7.85.0, not 7.85.1.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- (define libcurl-floor #x075500)
+ (define libcurl-floor #x075501)
```
**Result:** killed, exit 2:

```
FAIL the floor is 7.85.0, #x075500
  expected: 480512
  actual:   480513
FAIL check-version: the floor itself, #x075500, is accepted
  expected: (returned #t)
  actual:   (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.85.0" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF3. `<=`, not `<`

**Guards:** the floor itself is accepted.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- ((< version-num libcurl-floor)
+ ((<= version-num libcurl-floor)
```
**Result:** killed, exit 2:

```
FAIL check-version: the floor itself, #x075500, is accepted
  expected: (returned #t)
  actual:   (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.85.0" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF4. The SSL check deleted

**Guards:** SSL is required.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-       ((zero? (bitwise-and features curl-version-ssl))
-        (refuse 'no-ssl path source version-string
-                (string-append "libcurl " version-string
-                               " was built without SSL; name another with CHEZ_CURL_LIBCURL")))
+ (deleted)
```
**Result:** killed, exit 2:

```
FAIL check-version: every feature but SSL is no-ssl, with the version, path and source
  expected: (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "8.20.0" ())
  actual:   (returned #t)
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (readable no-raise readable readable)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF5. Any feature taken for SSL

**Guards:** SSL is the bit checked, not any feature.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- ((zero? (bitwise-and features curl-version-ssl))
+ ((zero? features)
```
**Result:** killed, exit 2:

```
FAIL check-version: every feature but SSL is no-ssl, with the version, path and source
  expected: (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "8.20.0" ())
  actual:   (returned #t)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF6. SSL checked before the floor

**Guards:** below-floor wins over no-ssl.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-       ((< version-num libcurl-floor)
-        (refuse 'below-floor
+       ((zero? (bitwise-and features curl-version-ssl))
+        (refuse 'no-ssl path source version-string "no ssl"))
+       ((< version-num libcurl-floor)
+        (refuse 'below-floor
```
**Result:** killed, exit 2:

```
FAIL check-version: below the floor and without SSL, below-floor wins
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-home "7.81.0" ())
  actual:   (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-home "7.81.0" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF7. below-floor's path and source swapped

**Guards:** below-floor carries the path and source, each in its field.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- (refuse 'below-floor path source version-string
+ (refuse 'below-floor source path version-string
```
**Result:** killed, exit 2:

```
FAIL check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.84.255" ())
  actual:   (refused below-floor system "/usr/lib/aarch64-linux-gnu/libcurl.so.4" "7.84.255" ())
FAIL check-version: below the floor and without SSL, below-floor wins
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-home "7.81.0" ())
  actual:   (refused below-floor guix-home "/usr/lib/aarch64-linux-gnu/libcurl.so.4" "7.81.0" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF8. below-floor carries the floor's version

**Guards:** below-floor carries the library's version, not the floor's.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- (refuse 'below-floor path source version-string
+ (refuse 'below-floor path source "7.85.0"
```
**Result:** killed, exit 2:

```
FAIL check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.84.255" ())
  actual:   (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.85.0" ())
FAIL check-version: below the floor and without SSL, below-floor wins
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-home "7.81.0" ())
  actual:   (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-home "7.85.0" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF9. no-ssl carries the version number, not its string

**Guards:** no-ssl carries the version string.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- (refuse 'no-ssl path source version-string
+ (refuse 'no-ssl path source (number->string version-num 16)
```
**Result:** killed, exit 2:

```
FAIL check-version: every feature but SSL is no-ssl, with the version, path and source
  expected: (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "8.20.0" ())
  actual:   (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "81400" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF10. The options probe deleted

**Guards:** the options API is probed.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-       ((not option-found?)
-        (refuse 'missing-api path source "curl_easy_option_by_name"
-                "libcurl was built without its options API (--disable-get-easy-options); name another with CHEZ_CURL_LIBCURL"))
+ (deleted)
```
**Result:** killed, exit 2:

```
FAIL check-apis: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-profile "curl_easy_option_by_name" ())
  actual:   (returned #t)
FAIL check-apis: with both APIs missing, the option probe is named: it runs first
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_option_by_name" ())
  actual:   (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_header" ())
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (readable readable no-raise readable)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF11. The header probe deleted

**Guards:** the header API is probed.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-       ((= header-code curlhe-not-built-in)
-        (refuse 'missing-api path source "curl_easy_header"
-                "libcurl was built without its header API (--disable-headers-api); name another with CHEZ_CURL_LIBCURL"))
+ (deleted)
```
**Result:** killed, exit 2:

```
FAIL check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-system "curl_easy_header" ())
  actual:   (returned #t)
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (readable readable readable no-raise)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF12. Every header code from 7 up refused

**Guards:** only CURLHE_NOT_BUILT_IN refuses.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- ((= header-code curlhe-not-built-in)
+ ((>= header-code curlhe-not-built-in)
```
**Result:** killed, exit 2:

```
FAIL check-apis: every other header code is accepted
  expected: ((returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t))
  actual:   ((returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_header" ()) (refused missing-api "/usr/lib/aarch …[57 more characters]
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF13. The header probe first

**Guards:** the options probe runs first.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-       ((not option-found?)
-        (refuse 'missing-api path source "curl_easy_option_by_name"
-                "libcurl was built without its options API (--disable-get-easy-options); name another with CHEZ_CURL_LIBCURL"))
-       ((= header-code curlhe-not-built-in)
-        (refuse 'missing-api path source "curl_easy_header"
-                "libcurl was built without its header API (--disable-headers-api); name another with CHEZ_CURL_LIBCURL"))
+       ((= header-code curlhe-not-built-in)
+        (refuse 'missing-api path source "curl_easy_header"
+                "libcurl was built without its header API (--disable-headers-api); name another with CHEZ_CURL_LIBCURL"))
+       ((not option-found?)
+        (refuse 'missing-api path source "curl_easy_option_by_name"
+                "libcurl was built without its options API (--disable-get-easy-options); name another with CHEZ_CURL_LIBCURL"))
```
**Result:** killed, exit 2:

```
FAIL check-apis: with both APIs missing, the option probe is named: it runs first
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_option_by_name" ())
  actual:   (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_header" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF14. The boolean check deleted

**Guards:** the options probe's answer is a boolean.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-     (unless (boolean? option-found?)
-       (assertion-violation 'check-apis
-                            "the option probe's answer is not a boolean"
-                            option-found?))
+ (deleted)
```
**Result:** killed, exit 2:

```
FAIL check-apis: the option probe's answer is a boolean, so a NULL pointer, 0, is refused
  expected: (assertion-violation check-apis)
  actual:   (returned #t)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF15. A bare condition raised

**Guards:** a refusal carries a who and a message.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-     (raise (condition (make-curl-library-unavailable reason path source detail '())
-                       (make-who-condition 'chez-curl)
-                       (make-message-condition message)
-                       (make-irritants-condition (list path))))))
+     (raise (make-curl-library-unavailable reason path source detail '()))))
```
**Result:** killed, exit 2:

```
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (bare bare bare bare)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF16. The two API names swapped

**Guards:** each probe names its own API.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- (refuse 'missing-api path source "curl_easy_option_by_name"
-                "libcurl was built without its options API
+ (refuse 'missing-api path source "curl_easy_header"
+                "libcurl was built without its options API
```

In `src/curl/private/verify.sls`:

```diff
- (refuse 'missing-api path source "curl_easy_header"
-                "libcurl was built without its header API
+ (refuse 'missing-api path source "curl_easy_option_by_name"
+                "libcurl was built without its header API
```
**Result:** killed, exit 2:

```
FAIL check-apis: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-profile "curl_easy_option_by_name" ())
  actual:   (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-profile "curl_easy_header" ())
FAIL check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-system "curl_easy_header" ())
  actual:   (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-system "curl_easy_option_by_name" ())
FAIL check-apis: with both APIs missing, the option probe is named: it runs first
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_option_by_name" ())
  actual:   (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_header" ())
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF17. Unknown bits dropped

**Guards:** unknown bits are reported.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-      (unknown-bits (bitwise-and features (bitwise-not known-bits)))))
+      '()))
```
**Result:** killed, exit 2:

```
FAIL feature-names: a bit not in the table comes back as an integer, after the names
  expected: (ssl 2147483648 8589934592)
  actual:   (ssl)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF18. Unknown bits first

**Guards:** unknown bits come after the names.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-     (append
-      (map car (filter (lambda (entry) (not (zero? (bitwise-and features (cdr entry)))))
-                       curl-version-features))
-      (unknown-bits (bitwise-and features (bitwise-not known-bits)))))
+     (append
+      (unknown-bits (bitwise-and features (bitwise-not known-bits)))
+      (map car (filter (lambda (entry) (not (zero? (bitwise-and features (cdr entry)))))
+                       curl-version-features))))
```
**Result:** killed, exit 2:

```
FAIL feature-names: a bit not in the table comes back as an integer, after the names
  expected: (ssl 2147483648 8589934592)
  actual:   (2147483648 8589934592 ssl)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF19. Unknown bits as their index

**Guards:** an unknown bit is its value, not its index.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- (else (loop (- bits bit) (* bit 2) (cons bit found))))))
+ (else (loop (- bits bit) (* bit 2) (cons (- (bitwise-length bit) 1) found))))))
```
**Result:** killed, exit 2:

```
FAIL feature-names: a bit not in the table comes back as an integer, after the names
  expected: (ssl 2147483648 8589934592)
  actual:   (ssl 31 33)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF20. The names of the unset bits

**Guards:** the names are those of the set bits.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- (lambda (entry) (not (zero? (bitwise-and features (cdr entry)))))
+ (lambda (entry) (zero? (bitwise-and features (cdr entry))))
```
**Result:** killed, exit 2:

```
FAIL feature-names: each bit alone names its own CURL_VERSION_ feature
  expected: ((ipv6) (kerberos4) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (http2) (gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi-ssl)  …[71 more characters]
  actual:   ((kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl thread …[6915 more characters]
FAIL feature-names: every bit set names every feature, in curl.h's order
  expected: (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl th …[9 more characters]
  actual:   ()
FAIL feature-names: only the bits that are set
  expected: (ipv6 ssl http2 threadsafe)
  actual:   (kerberos4 libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl)
FAIL feature-names: a bit not in the table comes back as an integer, after the names
  expected: (ssl 2147483648 8589934592)
  actual:   (ipv6 kerberos4 libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl thread …[27 more characters]
FAIL feature-names: no bits, no names
  expected: ()
  actual:   (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl th …[9 more characters]
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF21. The names reversed

**Guards:** the names come in the table's order.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-      (map car (filter
+      (reverse (map car (filter
```

In `src/curl/private/verify.sls`:

```diff
-                       curl-version-features))
+                       curl-version-features)))
```
**Result:** killed, exit 2:

```
FAIL feature-names: every bit set names every feature, in curl.h's order
  expected: (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl th …[9 more characters]
  actual:   (threadsafe gsasl hsts unicode zstd http3 altsvc brotli multi-ssl https-proxy psl unix-sockets kerberos5 gssapi http2 ntlm-wb tlsauth-srp curldebug conv sspi idn largefile spnego asynchdns debug gssnegotiate ntlm libz ssl kerber …[9 more characters]
FAIL feature-names: only the bits that are set
  expected: (ipv6 ssl http2 threadsafe)
  actual:   (threadsafe http2 ssl ipv6)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF22. Unknown bits highest first

**Guards:** unknown bits come lowest first.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-       (cond ((zero? bits) (reverse found))
+       (cond ((zero? bits) found)
```
**Result:** killed, exit 2:

```
FAIL feature-names: a bit not in the table comes back as an integer, after the names
  expected: (ssl 2147483648 8589934592)
  actual:   (ssl 8589934592 2147483648)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF23. check-version answers the version number

**Guards:** check-version answers #t.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-       (else #t)))
- 
-   ;; check-apis
+       (else version-num)))
+ 
+   ;; check-apis
```
**Result:** killed, exit 2:

```
FAIL check-version: the floor itself, #x075500, is accepted
  expected: (returned #t)
  actual:   (returned 480512)
FAIL check-version: SSL, 1<<2, alone is enough
  expected: (returned #t)
  actual:   (returned 529408)
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### VF24. check-apis answers `ok`

**Guards:** check-apis answers #t.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
- (--disable-headers-api); name another with CHEZ_CURL_LIBCURL"))
-       (else #t)))
+ (--disable-headers-api); name another with CHEZ_CURL_LIBCURL"))
+       (else 'ok)))
```
**Result:** killed, exit 2:

```
FAIL check-apis: an option found and header code 3 are accepted
  expected: (returned #t)
  actual:   (returned ok)
FAIL check-apis: every other header code is accepted
  expected: ((returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t))
  actual:   ((returned ok) (returned ok) (returned ok) (returned ok) (returned ok) (returned ok) (returned ok) (returned ok) (returned ok))
test: FAIL tests/test-verify.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

#### `(curl private discovery)`

##### DS1. The override's source is `system`

**Guards:** the override's source is override.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- ((absolute? override) (values override 'override))
+ ((absolute? override) (values override 'system))
```
**Result:** killed, exit 2:

```
FAIL override: an absolute CHEZ_CURL_LIBCURL is chosen as given, with source override
  expected: (chose "/opt/curl/lib/libcurl.so.4" override)
  actual:   (chose "/opt/curl/lib/libcurl.so.4" system)
FAIL override: it is never checked with exists?, since loading decides
  expected: ((chose "/opt/curl/lib/libcurl.so.4" override) ())
  actual:   ((chose "/opt/curl/lib/libcurl.so.4" system) ())
FAIL override: chosen on macOS, over Apple's
  expected: (chose "/opt/curl/lib/libcurl.so.4" override)
  actual:   (chose "/opt/curl/lib/libcurl.so.4" system)
FAIL override: chosen on a platform with no list
  expected: (chose "/opt/curl/lib/libcurl.so.4" override)
  actual:   (chose "/opt/curl/lib/libcurl.so.4" system)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS2. The override checked with exists?

**Guards:** the override is never checked with exists?.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- ((absolute? override) (values override 'override))
+ ((and (absolute? override) (exists? override)) (values override 'override))
```
**Result:** killed, exit 2:

```
FAIL override: it is never checked with exists?, since loading decides
  expected: ((chose "/opt/curl/lib/libcurl.so.4" override) ())
  actual:   ((refused invalid-override #f override "/opt/curl/lib/libcurl.so.4" ()) ("/opt/curl/lib/libcurl.so.4"))
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS3. Any string taken as the override

**Guards:** a relative override is refused.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- ((absolute? override) (values override 'override))
+ ((string? override) (values override 'override))
```
**Result:** killed, exit 2:

```
FAIL override: a relative path is invalid-override, carrying the value, with no fallback
  expected: (refused invalid-override #f override "lib/libcurl.so.4" ())
  actual:   (chose "lib/libcurl.so.4" override)
FAIL override: a bare name is invalid-override
  expected: (refused invalid-override #f override "libcurl.so.4" ())
  actual:   (chose "libcurl.so.4" override)
FAIL override: set but empty is invalid-override
  expected: (refused invalid-override #f override "" ())
  actual:   (chose "" override)
FAIL choose-libcurl: every refusal carries a who and a message, for the default handler
  expected: (readable readable)
  actual:   (no-raise readable)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS4. An empty override taken as unset

**Guards:** an empty override is not unset.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-         ((not override)
+         ((or (not override) (string=? override ""))
```
**Result:** killed, exit 2:

```
FAIL override: set but empty is invalid-override
  expected: (refused invalid-override #f override "" ())
  actual:   (chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS5. An invalid override falls back to the search

**Guards:** an invalid override has no fallback.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-         (else
-          (refuse 'invalid-override #f 'override override '()
-                  "CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for"
-                  override)))))
+         (else
+          (first-existing (libcurl-candidates (libcurl-world maps-text)
+                                              machine-type getenv)
+                          exists?)))))
```
**Result:** killed, exit 2:

```
FAIL override: a relative path is invalid-override, carrying the value, with no fallback
  expected: (refused invalid-override #f override "lib/libcurl.so.4" ())
  actual:   (chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment)
FAIL override: a bare name is invalid-override
  expected: (refused invalid-override #f override "libcurl.so.4" ())
  actual:   (chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment)
FAIL override: set but empty is invalid-override
  expected: (refused invalid-override #f override "" ())
  actual:   (chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS6. Any path holding a / taken as absolute

**Guards:** absolute means a leading /, not any /.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-   (define (absolute? s)
-     (and (> (string-length s) 0) (char=? (string-ref s 0) #\/)))
+   (define (absolute? s)
+     (and (line-path s) #t))
```
**Result:** killed, exit 2:

```
FAIL override: a relative path is invalid-override, carrying the value, with no fallback
  expected: (refused invalid-override #f override "lib/libcurl.so.4" ())
  actual:   (chose "lib/libcurl.so.4" override)
FAIL guix: a relative GUIX_PROFILE contributes nothing
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/lib …[26 more characters]
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-us …[75 more characters]
FAIL guix: a relative HOME contributes neither home candidate
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("home/ana/.guix-profile/lib/libcurl.so.4" . …[83 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS7. The override ignored on macOS

**Guards:** the override holds on macOS.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-         ((not override)
+         ((or (not override) (eq? (machine-platform machine-type) 'macos))
```
**Result:** killed, exit 2:

```
FAIL override: chosen on macOS, over Apple's
  expected: (chose "/opt/curl/lib/libcurl.so.4" override)
  actual:   (chose "/usr/lib/libcurl.4.dylib" macos-system)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS8. The override ignored on a platform with no list

**Guards:** the override holds on a platform with no list.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-         ((not override)
+         ((or (not override) (not (machine-platform machine-type)))
```
**Result:** killed, exit 2:

```
FAIL override: chosen on a platform with no list
  expected: (chose "/opt/curl/lib/libcurl.so.4" override)
  actual:   (refused not-found #f #f #f ())
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS9. Only ta6le and tarm64le are Linux

**Guards:** every machine type ending in le is Linux.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-       (cond ((string-suffix? "le" name) 'linux)
+       (cond ((memq machine-type '(ta6le tarm64le)) 'linux)
```
**Result:** killed, exit 2:

```
FAIL platform: a machine type ending in le is Linux
  expected: (chose "/usr/lib/libcurl.so.4" system)
  actual:   (refused not-found #f #f #f ())
FAIL fhs: an unknown Linux machine type has no triple directory
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system))
  actual:   ()
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS10. Only tarm64osx is macOS

**Guards:** every machine type ending in osx is macOS.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-             ((string-suffix? "osx" name) 'macos)
+             ((eq? machine-type 'tarm64osx) 'macos)
```
**Result:** killed, exit 2:

```
FAIL platform: a machine type ending in osx is macOS, on both architectures
  expected: ((chose "/usr/lib/libcurl.4.dylib" macos-system) (chose "/usr/lib/libcurl.4.dylib" macos-system))
  actual:   ((refused not-found #f #f #f ()) (chose "/usr/lib/libcurl.4.dylib" macos-system))
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS11. Any other platform taken for Linux

**Guards:** any other platform has no candidates.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-             (else #f))))
- 
-   ;; linux-triple
+             (else 'linux))))
+ 
+   ;; linux-triple
```
**Result:** killed, exit 2:

```
FAIL platform: any other has no candidates, so not-found with an empty list
  expected: ((refused not-found #f #f #f ()) (refused not-found #f #f #f ()) (refused not-found #f #f #f ()))
  actual:   ((chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment) (chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment) (chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment))
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS12. Apple's library checked with exists?

**Guards:** macOS's candidate is returned without exists?.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-               (let ((apple (car (libcurl-candidates #f machine-type getenv))))
-                 (values (car apple) (cdr apple))))
+               (first-existing (libcurl-candidates #f machine-type getenv) exists?))
```
**Result:** killed, exit 2:

```
FAIL macos: Apple's /usr/lib/libcurl.4.dylib, returned without asking exists?
  expected: ((chose "/usr/lib/libcurl.4.dylib" macos-system) ())
  actual:   ((refused not-found #f #f #f ("/usr/lib/libcurl.4.dylib")) ("/usr/lib/libcurl.4.dylib"))
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS13. macOS consults the world

**Guards:** macOS does not consult the world.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-               (let ((apple (car (libcurl-candidates #f machine-type getenv))))
+               (let ((apple (car (libcurl-candidates (libcurl-world maps-text) machine-type getenv))))
```

In `src/curl/private/discovery.sls`:

```diff
-       ((macos) (list (cons "/usr/lib/libcurl.4.dylib" 'macos-system)))
+       ((macos) (if (eq? world 'guix) (guix-candidates getenv) (list (cons "/usr/lib/libcurl.4.dylib" 'macos-system))))
```
**Result:** killed, exit 2:

```
FAIL macos: the world is not consulted, so a Guix maps text changes nothing
  expected: (chose "/usr/lib/libcurl.4.dylib" macos-system)
  actual:   (chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS14. Only the first line of the maps read

**Guards:** every line of the maps is read.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- (exists guix-libc? (map line-path (lines maps-text)))
+ (guix-libc? (line-path (car (lines maps-text))))
```
**Result:** killed, exit 2:

```
FAIL world: libc.so.6 under /gnu/store/, on any line, is guix
  expected: guix
  actual:   fhs
FAIL guix: a standard directory is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
  actual:   (chose "/usr/local/lib/libcurl.so.4" system)
FAIL guix: precedence: each candidate wins over every one after it
  expected: ((chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment) (chose "/home/ana/work/profile/lib/libcurl.so.4" guix-profile) (chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) (chose "/home/ana/.guix-profile …[105 more characters]
  actual:   ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) (refused not-found #f #f #f …[773 more characters]
FAIL guix: probing asks in order, and stops at the first that exists
  expected: ((chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4"))
  actual:   ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
FAIL discovery reads no variable but CHEZ_CURL_LIBCURL, GUIX_ENVIRONMENT, GUIX_PROFILE and HOME
  expected: ("CHEZ_CURL_LIBCURL" "GUIX_ENVIRONMENT" "GUIX_PROFILE" "HOME")
  actual:   ("CHEZ_CURL_LIBCURL")
FAIL the real /proc/self/maps: guix exactly when this Chez's binary lies under /gnu/store/
  expected: guix
  actual:   fhs
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS15. Any file under /gnu/store/ makes the world Guix

**Guards:** only libc decides the world.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-          (string-prefix? "/gnu/store/" path)
-          (string=? (basename path) "libc.so.6")))
+          (string-prefix? "/gnu/store/" path)))
```
**Result:** killed, exit 2:

```
FAIL world: other libraries from /gnu/store/ in an FHS process are fhs
  expected: fhs
  actual:   guix
FAIL world: a basename that only resembles libc.so.6 is fhs
  expected: fhs
  actual:   guix
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS16. A path ending in libc.so.6

**Guards:** the basename is libc.so.6, not one ending in it.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- (string=? (basename path) "libc.so.6")
+ (string-suffix? "libc.so.6" path)
```
**Result:** killed, exit 2:

```
FAIL world: a basename that only resembles libc.so.6 is fhs
  expected: fhs
  actual:   guix
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS17. A basename starting with libc.so.6

**Guards:** the basename is libc.so.6, not one starting with it.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- (string=? (basename path) "libc.so.6")
+ (string-prefix? "libc.so.6" (basename path))
```
**Result:** killed, exit 2:

```
FAIL world: a basename that only resembles libc.so.6 is fhs
  expected: fhs
  actual:   guix
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS18. /gnu/store/ anywhere in the path

**Guards:** /gnu/store/ is at the root, not anywhere in the path.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-          (string-prefix? "/gnu/store/" path)
+          (let loop ((i 0)) (and (<= (+ i 11) (string-length path)) (or (string=? (substring path i (+ i 11)) "/gnu/store/") (loop (+ i 1)))))
```
**Result:** killed, exit 2:

```
FAIL world: libc.so.6 under a /gnu/store/ that is not at the root is fhs
  expected: fhs
  actual:   guix
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS19. An unreadable maps text taken for Guix

**Guards:** an unreadable maps text is FHS.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-     (if (and maps-text (exists guix-libc?
+     (if (or (not maps-text) (exists guix-libc?
```
**Result:** killed, exit 2:

```
FAIL world: an unreadable /proc/self/maps, #f, is fhs
  expected: fhs
  actual:   guix
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS20. A libc.so.6 anywhere makes the world Guix

**Guards:** libc must lie under /gnu/store/.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-          (string-prefix? "/gnu/store/" path)
-          (string=? (basename path) "libc.so.6")))
+          (string=? (basename path) "libc.so.6")))
```
**Result:** killed, exit 2:

```
FAIL platform: a machine type ending in le is Linux
  expected: (chose "/usr/lib/libcurl.so.4" system)
  actual:   (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
FAIL world: libc.so.6 under /usr/lib is fhs
  expected: fhs
  actual:   guix
FAIL world: other libraries from /gnu/store/ in an FHS process are fhs
  expected: fhs
  actual:   guix
FAIL world: a basename that only resembles libc.so.6 is fhs
  expected: fhs
  actual:   guix
FAIL world: libc.so.6 under a /gnu/store/ that is not at the root is fhs
  expected: fhs
  actual:   guix
FAIL fhs: a Guix profile is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4"))
  actual:   (chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment)
FAIL fhs: precedence: each candidate wins over every one after it
  expected: ((chose "/usr/local/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl.so.4" system) (chose "/usr/lib64/libcurl.so.4" system) (chose "/usr/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnut …[17 more characters]
  actual:   ((refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pr …[1038 more characters]
FAIL fhs: the GnuTLS build is chosen only when no libcurl.so.4 exists
  expected: ((chose "/usr/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system))
  actual:   ((refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pr …[279 more characters]
FAIL not-found lists every path it checked, in order, with no path, source or detail
  expected: ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
  actual:   ((refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pr …[250 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS21. GUIX_PROFILE before GUIX_ENVIRONMENT

**Guards:** GUIX_ENVIRONMENT before GUIX_PROFILE.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-        (profile-candidate environment 'guix-environment)
-        (profile-candidate profile 'guix-profile)
+        (profile-candidate profile 'guix-profile)
+        (profile-candidate environment 'guix-environment)
```
**Result:** killed, exit 2:

```
FAIL guix: the candidate list, in ADR-0002's order
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" …[85 more characters]
  actual:   (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" …[85 more characters]
FAIL guix: HOME unset contributes neither home candidate
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
  actual:   (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
FAIL guix: a relative HOME contributes neither home candidate
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
  actual:   (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
FAIL guix: a standard directory is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
  actual:   (refused not-found #f #f #f ("/home/ana/work/profile/lib/libcurl.so.4" "/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
FAIL guix: precedence: each candidate wins over every one after it
  expected: ((chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment) (chose "/home/ana/work/profile/lib/libcurl.so.4" guix-profile) (chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) (chose "/home/ana/.guix-profile …[105 more characters]
  actual:   ((chose "/home/ana/work/profile/lib/libcurl.so.4" guix-profile) (chose "/home/ana/work/profile/lib/libcurl.so.4" guix-profile) (chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) (chose "/home/ana/.guix-profile/lib …[101 more characters]
FAIL guix: probing asks in order, and stops at the first that exists
  expected: ((chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4"))
  actual:   ((chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) ("/home/ana/work/profile/lib/libcurl.so.4" "/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4"))
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS22. ~/.guix-profile before ~/.guix-home/profile

**Guards:** ~/.guix-home/profile before ~/.guix-profile.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-        (profile-candidate (and home (string-append home "/.guix-home/profile"))
-                           'guix-home)
-        (profile-candidate (and home (string-append home "/.guix-profile"))
-                           'guix-user-profile)
+        (profile-candidate (and home (string-append home "/.guix-profile"))
+                           'guix-user-profile)
+        (profile-candidate (and home (string-append home "/.guix-home/profile"))
+                           'guix-home)
```
**Result:** killed, exit 2:

```
FAIL guix: the candidate list, in ADR-0002's order
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" …[85 more characters]
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/home/ana/.guix-home/profile/lib/libcu …[85 more characters]
FAIL guix: GUIX_ENVIRONMENT unset contributes nothing
  expected: (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[22 more characters]
  actual:   (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/run/current-system/profile/lib/libcurl …[22 more characters]
FAIL guix: GUIX_ENVIRONMENT set but empty contributes nothing
  expected: (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[22 more characters]
  actual:   (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/run/current-system/profile/lib/libcurl …[22 more characters]
FAIL guix: a relative GUIX_PROFILE contributes nothing
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/lib …[26 more characters]
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/run/current-system/profile/lib/lib …[26 more characters]
FAIL guix: a standard directory is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
  actual:   (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
FAIL guix: precedence: each candidate wins over every one after it
  expected: ((chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment) (chose "/home/ana/work/profile/lib/libcurl.so.4" guix-profile) (chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) (chose "/home/ana/.guix-profile …[105 more characters]
  actual:   ((chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment) (chose "/home/ana/work/profile/lib/libcurl.so.4" guix-profile) (chose "/home/ana/.guix-profile/lib/libcurl.so.4" guix-user-profile) (chose "/home/ana/.guix-prof …[108 more characters]
FAIL guix: probing asks in order, and stops at the first that exists
  expected: ((chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4"))
  actual:   ((chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib …[16 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS23. Guix System's profile dropped

**Guards:** Guix System's profile is a candidate.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-        (profile-candidate "/run/current-system/profile" 'guix-system))))
+        '())))
```
**Result:** killed, exit 2:

```
FAIL guix: the candidate list, in ADR-0002's order
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" …[85 more characters]
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" …[22 more characters]
FAIL guix: GUIX_ENVIRONMENT unset contributes nothing
  expected: (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[22 more characters]
  actual:   (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile))
FAIL guix: GUIX_ENVIRONMENT set but empty contributes nothing
  expected: (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[22 more characters]
  actual:   (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile))
FAIL guix: a relative GUIX_PROFILE contributes nothing
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/lib …[26 more characters]
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile))
FAIL guix: HOME unset contributes neither home candidate
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile))
FAIL guix: a relative HOME contributes neither home candidate
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile))
FAIL guix: a standard directory is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
  actual:   (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4"))
FAIL guix: precedence: each candidate wins over every one after it
  expected: ((chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment) (chose "/home/ana/work/profile/lib/libcurl.so.4" guix-profile) (chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) (chose "/home/ana/.guix-profile …[105 more characters]
  actual:   ((chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment) (chose "/home/ana/work/profile/lib/libcurl.so.4" guix-profile) (chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) (chose "/home/ana/.guix-profile …[244 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS24. An empty GUIX_ENVIRONMENT taken

**Guards:** an empty GUIX_ENVIRONMENT contributes nothing.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- (environment (absolute-or-false (getenv "GUIX_ENVIRONMENT")))
+ (environment (getenv "GUIX_ENVIRONMENT"))
```
**Result:** killed, exit 2:

```
FAIL guix: GUIX_ENVIRONMENT set but empty contributes nothing
  expected: (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[22 more characters]
  actual:   (("/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile)  …[63 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS25. A relative GUIX_PROFILE taken

**Guards:** a relative GUIX_PROFILE contributes nothing.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- (profile (absolute-or-false (getenv "GUIX_PROFILE")))
+ (profile (getenv "GUIX_PROFILE"))
```
**Result:** killed, exit 2:

```
FAIL guix: a relative GUIX_PROFILE contributes nothing
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/lib …[26 more characters]
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-us …[75 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS26. A relative HOME taken

**Guards:** a relative HOME contributes nothing.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- (home (absolute-or-false (getenv "HOME"))))
+ (home (getenv "HOME")))
```
**Result:** killed, exit 2:

```
FAIL guix: a relative HOME contributes neither home candidate
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("home/ana/.guix-profile/lib/libcurl.so.4" . …[83 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS27. An unset variable taken as the empty string

**Guards:** an unset variable contributes nothing.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-   (define (absolute-or-false s)
-     (and s (absolute? s) s))
+   (define (absolute-or-false s)
+     (if s (and (absolute? s) s) ""))
```
**Result:** killed, exit 2:

```
FAIL guix: GUIX_ENVIRONMENT unset contributes nothing
  expected: (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[22 more characters]
  actual:   (("/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile)  …[63 more characters]
FAIL guix: HOME unset contributes neither home candidate
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/.guix-profile/lib/libcurl.so.4" . guix-user-profi …[67 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS28. The standard directories after the Guix ones

**Guards:** a Guix world never yields a standard directory.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-          ((guix) (guix-candidates getenv))
+          ((guix) (append (guix-candidates getenv) (fhs-candidates (linux-triple machine-type))))
```
**Result:** killed, exit 2:

```
FAIL guix: the candidate list, in ADR-0002's order
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" …[85 more characters]
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" …[309 more characters]
FAIL guix: GUIX_ENVIRONMENT unset contributes nothing
  expected: (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[22 more characters]
  actual:   (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[246 more characters]
FAIL guix: GUIX_ENVIRONMENT set but empty contributes nothing
  expected: (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[22 more characters]
  actual:   (("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/libcurl …[246 more characters]
FAIL guix: a relative GUIX_PROFILE contributes nothing
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/lib …[26 more characters]
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/.guix-home/profile/lib/libcurl.so.4" . guix-home) ("/home/ana/.guix-profile/lib/libcurl.so.4" . guix-user-profile) ("/run/current-system/profile/lib/lib …[250 more characters]
FAIL guix: HOME unset contributes neither home candidate
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system) ("/usr/local/lib/libcurl.so.4" . system) ( …[182 more characters]
FAIL guix: a relative HOME contributes neither home candidate
  expected: (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system))
  actual:   (("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-profile) ("/run/current-system/profile/lib/libcurl.so.4" . guix-system) ("/usr/local/lib/libcurl.so.4" . system) ( …[182 more characters]
FAIL guix: a standard directory is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
  actual:   (chose "/usr/local/lib/libcurl.so.4" system)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS29. The Guix profiles after the standard directories

**Guards:** an FHS world never yields a Guix profile.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-          ((fhs) (fhs-candidates (linux-triple machine-type)))
+          ((fhs) (append (fhs-candidates (linux-triple machine-type)) (guix-candidates getenv)))
```
**Result:** killed, exit 2:

```
FAIL fhs: the candidate list for ta6le, in ADR-0002's order
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" . system) ("/ …[309 more characters]
FAIL fhs: the candidate list for tarm64le, under aarch64-linux-gnu
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl-gnutls.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl-gnutls.so.4" . system) ( …[311 more characters]
FAIL fhs: an unknown Linux machine type has no triple directory
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/gnu/store/aaa-profile/lib/libcurl.so.4" . guix-environment) ("/home/ana/work/profile/lib/libcurl.so.4" . guix-p …[198 more characters]
FAIL fhs: a Guix profile is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4"))
  actual:   (chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment)
FAIL not-found lists every path it checked, in order, with no path, source or detail
  expected: ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
  actual:   ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" "/gnu/store/aaa-profile/lib/l …[588 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS30. Every candidate asked, the first kept

**Guards:** probing stops at the first that exists.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-     (let loop ((rest candidates))
-       (cond
-         ((null? rest)
-          (let ((paths (map car candidates)))
-            (refuse 'not-found #f #f #f paths
-                    "no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path"
-                    paths)))
-         ((exists? (caar rest)) (values (caar rest) (cdar rest)))
-         (else (loop (cdr rest))))))
+     (let ((found (filter (lambda (c) (exists? (car c))) candidates)))
+       (if (null? found)
+           (let ((paths (map car candidates)))
+             (refuse 'not-found #f #f #f paths
+                     "no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path"
+                     paths))
+           (values (caar found) (cdar found)))))
```
**Result:** killed, exit 2:

```
FAIL guix: probing asks in order, and stops at the first that exists
  expected: ((chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4"))
  actual:   ((chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) ("/run/current-system/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/gnu/store/aaa-profil …[63 more characters]
FAIL not-found lists every path it checked, in order, with no path, source or detail
  expected: ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
  actual:   ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/lib/x86_64-linux-gnu …[144 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS31. Candidates probed last first

**Guards:** probing goes in the list's order.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-     (let loop ((rest candidates))
+     (let loop ((rest (reverse candidates)))
```
**Result:** killed, exit 2:

```
FAIL guix: precedence: each candidate wins over every one after it
  expected: ((chose "/gnu/store/aaa-profile/lib/libcurl.so.4" guix-environment) (chose "/home/ana/work/profile/lib/libcurl.so.4" guix-profile) (chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) (chose "/home/ana/.guix-profile …[105 more characters]
  actual:   ((chose "/run/current-system/profile/lib/libcurl.so.4" guix-system) (chose "/run/current-system/profile/lib/libcurl.so.4" guix-system) (chose "/run/current-system/profile/lib/libcurl.so.4" guix-system) (chose "/run/current-syste …[108 more characters]
FAIL guix: probing asks in order, and stops at the first that exists
  expected: ((chose "/home/ana/.guix-home/profile/lib/libcurl.so.4" guix-home) ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4"))
  actual:   ((chose "/run/current-system/profile/lib/libcurl.so.4" guix-system) ("/run/current-system/profile/lib/libcurl.so.4"))
FAIL fhs: precedence: each candidate wins over every one after it
  expected: ((chose "/usr/local/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl.so.4" system) (chose "/usr/lib64/libcurl.so.4" system) (chose "/usr/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnut …[17 more characters]
  actual:   ((chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libc …[88 more characters]
FAIL fhs: the GnuTLS build is chosen only when no libcurl.so.4 exists
  expected: ((chose "/usr/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system))
  actual:   ((chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system))
FAIL not-found lists every path it checked, in order, with no path, source or detail
  expected: ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
  actual:   ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/lib/x86_64-linux-gnu …[144 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS32. /usr/lib before /usr/lib64

**Guards:** /usr/lib64 before /usr/lib.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-           '("/usr/lib64/libcurl.so.4"
-             "/usr/lib/libcurl.so.4")
+           '("/usr/lib/libcurl.so.4"
+             "/usr/lib64/libcurl.so.4")
```
**Result:** killed, exit 2:

```
FAIL fhs: the candidate list for ta6le, in ADR-0002's order
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" . system))
FAIL fhs: the candidate list for tarm64le, under aarch64-linux-gnu
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl-gnutls.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl-gnutls.so.4" . system))
FAIL fhs: an unknown Linux machine type has no triple directory
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system))
FAIL fhs: a Guix profile is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4"))
  actual:   (refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4"))
FAIL fhs: precedence: each candidate wins over every one after it
  expected: ((chose "/usr/local/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl.so.4" system) (chose "/usr/lib64/libcurl.so.4" system) (chose "/usr/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnut …[17 more characters]
  actual:   ((chose "/usr/local/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl.so.4" system) (chose "/usr/lib/libcurl.so.4" system) (chose "/usr/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls …[15 more characters]
FAIL not-found lists every path it checked, in order, with no path, source or detail
  expected: ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
  actual:   ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS33. The GnuTLS build second

**Guards:** the GnuTLS build comes last.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-           (if triple (list (string-append "/usr/lib/" triple "/libcurl.so.4")) '())
+           (if triple (list (string-append "/usr/lib/" triple "/libcurl.so.4") (string-append "/usr/lib/" triple "/libcurl-gnutls.so.4")) '())
```

In `src/curl/private/discovery.sls`:

```diff
-           (if triple
-               (list (string-append "/usr/lib/" triple "/libcurl-gnutls.so.4"))
-               '()))))
+           '())))
```
**Result:** killed, exit 2:

```
FAIL fhs: the candidate list for ta6le, in ADR-0002's order
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system))
FAIL fhs: the candidate list for tarm64le, under aarch64-linux-gnu
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl-gnutls.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl-gnutls.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system))
FAIL fhs: a Guix profile is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4"))
  actual:   (refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4"))
FAIL fhs: precedence: each candidate wins over every one after it
  expected: ((chose "/usr/local/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl.so.4" system) (chose "/usr/lib64/libcurl.so.4" system) (chose "/usr/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnut …[17 more characters]
  actual:   ((chose "/usr/local/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system)  …[63 more characters]
FAIL fhs: the GnuTLS build is chosen only when no libcurl.so.4 exists
  expected: ((chose "/usr/lib/libcurl.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system))
  actual:   ((chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system) (chose "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" system))
FAIL not-found lists every path it checked, in order, with no path, source or detail
  expected: ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
  actual:   ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS34. arm64-linux-gnu for tarm64le

**Guards:** tarm64le's triple is aarch64-linux-gnu.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- ((tarm64le) "aarch64-linux-gnu")
+ ((tarm64le) "arm64-linux-gnu")
```
**Result:** killed, exit 2:

```
FAIL fhs: the candidate list for tarm64le, under aarch64-linux-gnu
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/aarch64-linux-gnu/libcurl-gnutls.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/arm64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/arm64-linux-gnu/libcurl-gnutls.so.4" . system))
FAIL triple table: ta6le and tarm64le, and no other machine type
  expected: ("x86_64-linux-gnu" "aarch64-linux-gnu" #f #f #f #f)
  actual:   ("x86_64-linux-gnu" "arm64-linux-gnu" #f #f #f #f)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS35. A triple for a6le too

**Guards:** only ta6le and tarm64le have a triple.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- ((ta6le) "x86_64-linux-gnu")
+ ((ta6le a6le) "x86_64-linux-gnu")
```
**Result:** killed, exit 2:

```
FAIL triple table: ta6le and tarm64le, and no other machine type
  expected: ("x86_64-linux-gnu" "aarch64-linux-gnu" #f #f #f #f)
  actual:   ("x86_64-linux-gnu" "aarch64-linux-gnu" "x86_64-linux-gnu" #f #f #f)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS36. An unknown machine type taken for x86_64

**Guards:** an unknown Linux machine type has no triple directory.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-          ((fhs) (fhs-candidates (linux-triple machine-type)))
+          ((fhs) (fhs-candidates (or (linux-triple machine-type) "x86_64-linux-gnu")))
```
**Result:** killed, exit 2:

```
FAIL fhs: an unknown Linux machine type has no triple directory
  expected: (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system))
  actual:   (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" . system))
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS37. not-found lists nothing

**Guards:** not-found lists what it checked.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-            (refuse 'not-found #f #f #f paths
+            (refuse 'not-found #f #f #f '()
```
**Result:** killed, exit 2:

```
FAIL guix: a standard directory is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
  actual:   (refused not-found #f #f #f ())
FAIL fhs: a Guix profile is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4"))
  actual:   (refused not-found #f #f #f ())
FAIL not-found lists every path it checked, in order, with no path, source or detail
  expected: ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
  actual:   ((refused not-found #f #f #f ()) ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4"))
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS38. not-found names a source

**Guards:** not-found names no source.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
- (refuse 'not-found #f #f #f paths
+ (refuse 'not-found #f 'system #f paths
```
**Result:** killed, exit 2:

```
FAIL platform: any other has no candidates, so not-found with an empty list
  expected: ((refused not-found #f #f #f ()) (refused not-found #f #f #f ()) (refused not-found #f #f #f ()))
  actual:   ((refused not-found #f system #f ()) (refused not-found #f system #f ()) (refused not-found #f system #f ()))
FAIL guix: a standard directory is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system/pro …[24 more characters]
  actual:   (refused not-found #f system #f ("/gnu/store/aaa-profile/lib/libcurl.so.4" "/home/ana/work/profile/lib/libcurl.so.4" "/home/ana/.guix-home/profile/lib/libcurl.so.4" "/home/ana/.guix-profile/lib/libcurl.so.4" "/run/current-system …[28 more characters]
FAIL fhs: a Guix profile is never chosen, even when every one exists
  expected: (refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4"))
  actual:   (refused not-found #f system #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4"))
FAIL not-found lists every path it checked, in order, with no path, source or detail
  expected: ((refused not-found #f #f #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcurl.so …[144 more characters]
  actual:   ((refused not-found #f system #f ("/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) ("/usr/local/lib/libcur …[148 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS39. A bare condition raised

**Guards:** a refusal carries a who and a message.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-     (raise (condition (make-curl-library-unavailable reason path source detail
-                                                      candidates)
-                       (make-who-condition 'chez-curl)
-                       (make-message-condition message)
-                       (make-irritants-condition (list irritant)))))
+     (raise (make-curl-library-unavailable reason path source detail candidates)))
```
**Result:** killed, exit 2:

```
FAIL choose-libcurl: every refusal carries a who and a message, for the default handler
  expected: (readable readable)
  actual:   (bare bare)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS40. DYLD_LIBRARY_PATH read on macOS

**Guards:** nothing reads DYLD_* or LD_LIBRARY_PATH.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-               (let ((apple (car (libcurl-candidates #f machine-type getenv))))
+               (let ((apple (if (getenv "DYLD_LIBRARY_PATH") (cons (string-append (getenv "DYLD_LIBRARY_PATH") "/libcurl.4.dylib") 'macos-system) (car (libcurl-candidates #f machine-type getenv)))))
```
**Result:** killed, exit 2:

```
FAIL discovery reads no variable but CHEZ_CURL_LIBCURL, GUIX_ENVIRONMENT, GUIX_PROFILE and HOME
  expected: ("CHEZ_CURL_LIBCURL" "GUIX_ENVIRONMENT" "GUIX_PROFILE" "HOME")
  actual:   ("CHEZ_CURL_LIBCURL" "DYLD_LIBRARY_PATH" "GUIX_ENVIRONMENT" "GUIX_PROFILE" "HOME")
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS41. `macos-system` dropped from the sources

**Guards:** the eight sources.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-       guix-system system macos-system))
+       guix-system system))
```
**Result:** killed, exit 2:

```
FAIL libcurl-sources: exactly the eight sources, in order
  expected: (override guix-environment guix-profile guix-home guix-user-profile guix-system system macos-system)
  actual:   (override guix-environment guix-profile guix-home guix-user-profile guix-system system)
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS42. The suite reads the wrong file for /proc/self/maps

**Guards:** the suite reads the real /proc/self/maps.
**Mutation:** In `tests/test-discovery.sps`:

```diff
- (open-file-input-port "/proc/self/maps"
+ (open-file-input-port "/proc/self/mapz"
```
**Result:** killed, exit 2:

```
FAIL the real /proc/self/maps is read on Linux, and only there
  expected: read
  actual:   unread
FAIL the real /proc/self/maps: guix exactly when this Chez's binary lies under /gnu/store/
  expected: guix
  actual:   fhs
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### DS43. Any other Linux world taken as FHS

**Guards:** a Linux world is guix or fhs, and nothing else.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-          (else (assertion-violation 'libcurl-candidates "not a world: guix or fhs"
-                                     world))))
+          (else (fhs-candidates (linux-triple machine-type)))))
```
**Result:** killed, exit 2:

```
FAIL libcurl-candidates refuses a Linux world that is neither guix nor fhs
  expected: (assertion-violation libcurl-candidates)
  actual:   (chose (("/usr/local/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl.so.4" . system) ("/usr/lib64/libcurl.so.4" . system) ("/usr/lib/libcurl.so.4" . system) ("/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4" . syst …[5 more characters]
test: FAIL tests/test-discovery.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

#### `(curl private require-threaded)` and its suite

RS mutations change the tree the suite reads, and the suite must fail by name. RC mutations change the suite's own checker. RT mutations change the refusal.

##### RS1. conditions.sls imports (rnrs) first

**Guards:** conditions.sls imports the refusal first.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
-   (import (curl private require-threaded)
-           (rnrs))
+   (import (rnrs)
+           (curl private require-threaded))
```
**Result:** killed, exit 2:

```
FAIL src/curl/private/conditions.sls imports (curl private require-threaded) first
  expected: first
  actual:   not-first
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RS2. constants.sls without the refusal

**Guards:** constants.sls imports the refusal.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
-   (import (curl private require-threaded)
-           (rnrs))
+   (import (rnrs))
```
**Result:** killed, exit 2:

```
FAIL src/curl/private/constants.sls imports (curl private require-threaded) first
  expected: first
  actual:   absent
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RS3. discovery.sls imports the refusal last

**Guards:** discovery.sls imports the refusal first.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-   (import (curl private require-threaded)
-           (rnrs)
-           (curl private conditions))
+   (import (rnrs)
+           (curl private conditions)
+           (curl private require-threaded))
```
**Result:** killed, exit 2:

```
FAIL src/curl/private/discovery.sls imports (curl private require-threaded) first
  expected: first
  actual:   not-first
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RS4. verify.sls imports the refusal last

**Guards:** verify.sls imports the refusal first.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-   (import (curl private require-threaded)
-           (rnrs)
-           (curl private conditions)
-           (curl private constants))
+   (import (rnrs)
+           (curl private conditions)
+           (curl private constants)
+           (curl private require-threaded))
```
**Result:** killed, exit 2:

```
FAIL src/curl/private/verify.sls imports (curl private require-threaded) first
  expected: first
  actual:   not-first
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RS5. The refusal deleted

**Guards:** src/ holds the refusal.
**Mutation:** `src/curl/private/require-threaded.sls` deleted.
**Result:** killed, exit 2:

```
Exception: library (curl private require-threaded) not found
test: FAIL tests/test-conditions.sps (exit 255)
Exception: library (curl private require-threaded) not found
test: FAIL tests/test-discovery.sps (exit 255)
FAIL src/ defines (curl private require-threaded)
  expected: defined
  actual:   absent
FAIL the refusal exports nothing
  expected: ()
  actual:   no-refusal-source
FAIL the refusal asks (threaded?)
  expected: asks
  actual:   never-asks
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   no-refusal-source
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   no-refusal-source
test: FAIL tests/test-require-threaded.sps (exit 1)
Exception: library (curl private require-threaded) not found
test: FAIL tests/test-verify.sps (exit 255)
test: ran 6, passed 2, failed 4, hung 0
```

##### RS6. An empty src/

**Guards:** an empty src/ fails, never passes for want of rows.
**Mutation:** `src/curl/private/require-threaded.sls`, `src/curl/private/conditions.sls`, `src/curl/private/constants.sls`, `src/curl/private/discovery.sls`, `src/curl/private/verify.sls` deleted.
**Result:** killed, exit 2:

```
Exception: library (curl private conditions) not found
test: FAIL tests/test-conditions.sps (exit 255)
Exception: library (curl private conditions) not found
test: FAIL tests/test-discovery.sps (exit 255)
FAIL src/ defines (curl private require-threaded)
  expected: defined
  actual:   absent
FAIL the scan read src/: conditions, constants, discovery and verify
  expected: (read read read read)
  actual:   (missed missed missed missed)
FAIL the order rows are live: src/ holds a library besides the refusal
  expected: live
  actual:   no-rows
FAIL the refusal exports nothing
  expected: ()
  actual:   no-refusal-source
FAIL the refusal asks (threaded?)
  expected: asks
  actual:   never-asks
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   no-refusal-source
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   no-refusal-source
test: FAIL tests/test-require-threaded.sps (exit 1)
Exception: library (curl private conditions) not found
test: FAIL tests/test-verify.sps (exit 255)
test: ran 6, passed 2, failed 4, hung 0
```

##### RS7. A new library without the refusal

**Guards:** a new library without the refusal gets a row, and fails it.
**Mutation:** `src/curl/private/extra.sls` created:

```scheme
#!r6rs
(library (curl private extra)
  (export extra)
  (import (rnrs))
  (define extra 1))
```
**Result:** killed, exit 2:

```
FAIL src/curl/private/extra.sls imports (curl private require-threaded) first
  expected: first
  actual:   absent
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RS8. A source under src/ that is no library

**Guards:** a source under src/ that is no library fails its row.
**Mutation:** `src/curl/private/notes.sls` created:

```scheme
#!r6rs
(import (rnrs))
```
**Result:** killed, exit 2:

```
FAIL src/curl/private/notes.sls imports (curl private require-threaded) first
  expected: first
  actual:   not-a-library
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC1. The checker answers first for any list

**Guards:** the checker does not answer first for everything.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-           ((equal? (car names) refusal-library) 'first)
+           (#t 'first)
```
**Result:** killed, exit 2:

```
FAIL the refusal after (rnrs) is not first
  expected: not-first
  actual:   first
FAIL no refusal among the imports is absent
  expected: absent
  actual:   first
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC2. The checker has no case for no imports

**Guards:** the checker finds no imports at all absent.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-     (cond ((null? names) 'absent)
+     (cond
```
**Result:** killed, exit 2:

```
FAIL no imports at all is absent
  expected: absent
  actual:   #f
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC3. The refusal anywhere taken as first

**Guards:** the checker requires the refusal first, not anywhere.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-           ((equal? (car names) refusal-library) 'first)
+           ((member refusal-library names) 'first)
```
**Result:** killed, exit 2:

```
FAIL the refusal after (rnrs) is not first
  expected: not-first
  actual:   first
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC4. Wrappers not seen through

**Guards:** the checker sees through import wrappers.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-            (memq (car spec) '(only except prefix rename for library))
+            (memq (car spec) '())
```
**Result:** killed, exit 2:

```
FAIL a wrapped or versioned refusal is the same library
  expected: (first first first)
  actual:   (absent absent first)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC5. A reference's version kept

**Guards:** the checker drops a reference's version.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-   (if (or (not (pair? ref)) (pair? (car ref)))
-       '()
+   (if (not (pair? ref))
+       '()
```
**Result:** killed, exit 2:

```
FAIL a wrapped or versioned refusal is the same library
  expected: (first first first)
  actual:   (first first absent)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC6. Any datum taken for a library form

**Guards:** the checker tells a library form from anything else.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-   (if (library-form? form)
-       (import-order (cdr (cadddr form)))
-       'not-a-library))
+   (import-order (cdr (cadddr form))))
```
**Result:** killed, exit 2:

```
FAIL a file whose first datum is no library form is not a library
  expected: not-a-library
  actual:   #f
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC7. Dotfiles read

**Guards:** the scan skips dotfiles.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-          (not (char=? (string-ref name 0) #\.))
-          (string=? (substring name (- n 4) n) ".sls"))))
+          (string=? (substring name (- n 4) n) ".sls"))))
```
**Result:** killed, exit 2:

```
FAIL the scan reads .sls sources and skips the dotfiles beside them
  expected: (read skipped skipped skipped skipped)
  actual:   (read read read skipped skipped)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC8. The scan rooted at tests/

**Guards:** the scan reads src/, not another directory.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
- (sls-files "src")
+ (sls-files "tests")
```
**Result:** killed, exit 2:

```
FAIL src/ defines (curl private require-threaded)
  expected: defined
  actual:   absent
FAIL the scan read src/: conditions, constants, discovery and verify
  expected: (read read read read)
  actual:   (missed missed missed missed)
FAIL tests/curl-testing.sls imports (curl private require-threaded) first
  expected: first
  actual:   absent
FAIL the refusal exports nothing
  expected: ()
  actual:   no-refusal-source
FAIL the refusal asks (threaded?)
  expected: asks
  actual:   never-asks
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   no-refusal-source
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   no-refusal-source
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC9. The scan rooted at src/curl/private

**Guards:** the scan root is src/ itself (all of today's libraries lie in src/curl/private).
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
- (sls-files "src")
+ (sls-files "src/curl/private")
```
**Result:** survived, as expected: exit 0, and `make test` printed `test: ran 6, passed 6, failed 0, hung 0`.

##### RC10. No library covered

**Guards:** the rows cover every library but the refusal.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-   (filter (lambda (entry) (not (equal? (form-name (cdr entry)) refusal-library)))
-           libraries))
+   (filter (lambda (entry) #f)
+           libraries))
```
**Result:** killed, exit 2:

```
FAIL the order rows are live: src/ holds a library besides the refusal
  expected: live
  actual:   no-rows
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RC11. Names compared with eq?

**Guards:** the checker compares library names as lists, with equal?.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-           ((equal? (car names) refusal-library) 'first)
+           ((eq? (car names) refusal-library) 'first)
```
**Result:** killed, exit 2:

```
FAIL the refusal first among the imports is first
  expected: first
  actual:   absent
FAIL a wrapped or versioned refusal is the same library
  expected: (first first first)
  actual:   (absent absent absent)
FAIL src/curl/private/conditions.sls imports (curl private require-threaded) first
  expected: first
  actual:   absent
FAIL src/curl/private/constants.sls imports (curl private require-threaded) first
  expected: first
  actual:   absent
FAIL src/curl/private/discovery.sls imports (curl private require-threaded) first
  expected: first
  actual:   absent
FAIL src/curl/private/verify.sls imports (curl private require-threaded) first
  expected: first
  actual:   absent
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RT1. The refusal's message changed

**Guards:** the refusal names chez-curl's requirement.
**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
- "chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one.
+ "chez-curl requires threads, and (threaded?) is #f in this one.
```
**Result:** killed, exit 2:

```
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   "Exception in chez-curl: chez-curl requires threads, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads (require-threaded-chez)"
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RT2. The refusal never asks

**Guards:** the refusal asks (threaded?).
**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
-       (if (threaded?)
+       (if #t
```
**Result:** killed, exit 2:

```
FAIL the refusal asks (threaded?)
  expected: asks
  actual:   never-asks
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RT3. The refusal inverted

**Guards:** the refusal refuses only a non-threaded Chez.
**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
-       (if (threaded?)
+       (if (not (threaded?))
```
**Result:** killed, exit 2:

```
Exception in chez-curl: chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads (require-threaded-chez) at line 33, char 3 of src/curl/private/require-threaded.sls
test: FAIL tests/test-conditions.sps (exit 255)
Exception in chez-curl: chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads (require-threaded-chez) at line 33, char 3 of src/curl/private/require-threaded.sls
test: FAIL tests/test-discovery.sps (exit 255)
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   refused-by-name
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
Exception in chez-curl: chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads (require-threaded-chez) at line 33, char 3 of src/curl/private/require-threaded.sls
test: FAIL tests/test-verify.sps (exit 255)
test: ran 6, passed 2, failed 4, hung 0
```

##### RT4. The refusal only prints

**Guards:** the refusal raises, not only prints.
**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
-           (syntax-violation
-            'chez-curl
-            "chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads"
-            x))))
+           (begin
+             (display "chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one.\n")
+             #'(define threaded-chez-checked #f)))))
```
**Result:** killed, exit 2:

```
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RT5. The refusal exports its macro

**Guards:** the refusal exports nothing.
**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
-   (export)
+   (export require-threaded-chez)
```
**Result:** killed, exit 2:

```
FAIL the refusal exports nothing
  expected: ()
  actual:   (require-threaded-chez)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

##### RT6. The refusal's who changed

**Guards:** the refusal is chez-curl's.
**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
-            'chez-curl
+            'require-threaded
```
**Result:** killed, exit 2:

```
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   "Exception in require-threaded: chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads (require-threaded-chez)"
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 6, passed 5, failed 1, hung 0
```

#### The Makefile

##### MK1. src/ off Chez's library path

**Guards:** make test puts src/ on Chez's library path.
**Mutation:** In `Makefile`:

```diff
- LIBDIRS := src:tests:$(SRFI_LIBS)
+ LIBDIRS := tests:$(SRFI_LIBS)
```
**Result:** killed, exit 2:

```
Exception: library (curl private conditions) not found
test: FAIL tests/test-conditions.sps (exit 255)
Exception: library (curl private conditions) not found
test: FAIL tests/test-discovery.sps (exit 255)
Exception: library (curl private conditions) not found
test: FAIL tests/test-verify.sps (exit 255)
test: ran 6, passed 3, failed 3, hung 0
```

### Last run

After the last change to any source, suite or the Makefile, on the working tree:

- `scripts/guix-env sh -c 'make test && make check-test-fails'` exited 0. `make test` ended
  `test: ran 6, passed 6, failed 0, hung 0`, and `check-test-fails` ended
  `check-test-fails: make test failed, as it must, in all 8 cases`.
- `make check-guix`, on the host, ended `check-guix: ALL CHECKS PASSED`.

### Findings

- **SRFI-64 evaluates `test-equal`'s expected expression outside its catch.**
  `%test-comp2body` in `vendor/chez-srfi/%3a64/testing-impl.scm` binds `(let ((exp expected))
  …)` before it calls `%test-evaluate-with-catch` on the actual expression. A raise in the
  expected expression therefore escapes the test. The suite dies there, with no `FAIL` line for
  that test, and the tests after it never run. Measured in the container:

  ```scheme
  (test-equal "a raise in the actual expression" 'x (car '()))
  (test-equal "a raise in the expected expression" (car '()) 'x)
  (test-equal "after it" 'y 'y)
  ```

  printed `FAIL a raise in the actual expression`, then `Exception in car: () is not a pair`,
  and exited 255. `make test` still names the suite `FAIL`, so nothing passes vacuously, but the
  evidence of which test failed is lost. `tests/test-discovery.sps` computes its real-maps
  oracle, `binary-world`, at top level under a `guard` that answers a sentinel, for this reason.
- **A test name shared by two suites makes its `FAIL` line ambiguous.** The first drafts of
  `test-discovery` and `test-verify` each had a test named `every refusal carries a who and a
  message, for the default handler`. A mutant could then be counted as killed by the other
  suite's failure. Each now names its procedure, and no two tests in the four suites share a
  name.
- **The refusal reaches every dependent by name.** RT3 inverts it, so this threaded Chez takes
  the refusing branch. Every suite that imports a `(curl private …)` library then died at
  import with the refusal's own text, `Exception in chez-curl: chez-curl needs a threaded Chez
  Scheme, …`, not with an error from the library it imported.
- **`#!r6rs` is fine in a library under `src/`.** Chez's library loader expands all five, and
  `read` skips the line, so `tests/test-require-threaded.sps` reads each library form first.
- **Inside the container, Chez's process id is small, and `/proc/<pid>/exe` still resolves.**
  `get-process-id` answered 3 in a probe; the container has its own PID namespace and its own
  `/proc`. `readlink -f` on `$CHEZ` and on `/proc/<pid>/exe` both give
  `/gnu/store/…-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme`: the profile's `bin/scheme` is a
  symlink to the package's `bin/scheme`, itself a symlink.

### Not covered

- **CN6, CN7 and CN8 survive.** `curle-ok`, `curl-global-default` and `curlversion-tenth` have no
  reader until `native.sls`. Slice 4's compiled C program is their check (ADR-0001). The feature
  table, `curl-version-ssl` and `curlhe-not-built-in` are read by `(curl private verify)`, and
  its suite writes their values out from the headers, so CN1 to CN5 die there.
- **RC9 survives.** A scan rooted at `src/curl/private` reads every library this step wrote,
  since all of them live there. chez-libuv's C6 is the same blind spot, caught there by a
  library outside that directory. When `(curl)` lands as `src/curl.sls`, add it to the row `the
  scan read src/: …`, and RC9 dies.
- **The real-maps test's FHS and macOS halves.** It ran only in the Guix container, where the
  binary and libc both lie under `/gnu/store/`. No FHS Chez exists on this host. It first runs in
  the FHS world on slice 5's CI, and off Linux only if the maintainer runs the suite on a Mac.
- **The refusal on a real `--nothreads` Chez.** RT1 to RT6 test a copy expanded with
  `(threaded?)` replaced by `#f`. The non-threaded CI lane (harness plan §4) runs the real thing.
- **Argument types.** Only two inputs are checked: the reason, by the constructor, and the
  option probe's answer, by `check-apis`. A path, source, detail or candidate list of the wrong
  type is stored as given, and a version number or header code that is not an integer raises
  from `<` or `=` with Chez's own message.
- **Odd maps lines.** A libc mapped as `…/libc.so.6 (deleted)` does not make the world Guix. No
  test has such a line.
- **A profile variable with a trailing slash** gives a candidate with `//lib/`. The loader
  accepts it. No test sets one.
- **Message text.** Never asserted, by design (ADR-0002). The `who` and `message` are asserted
  present, in one test per refusing library.

### Coverage

Every test in the four suites, with the mutants that failed it by name.

**`test-conditions`**

| Test | Failed by |
|---|---|
| make-curl-error: an error and a curl-error, and neither subtype | CD1 |
| library-unavailable: an error and a curl-error, not a wrong-thread | CD1, CD2 |
| library-unavailable carries its reason, path, source, detail and candidates | CD4, CD5 |
| the reasons are exactly ADR-0002's and ADR-0003's six, in order | CD6, CD7 |
| the constructor takes each of the six reasons | CD6 |
| the constructor refuses a symbol that is not a reason | CD8, CD10 |
| the constructor refuses a reason spelled as a string | CD8, CD9, CD10 |
| wrong-thread: an error and a curl-error, not a library-unavailable | CD1, CD3 |
| wrong-thread carries who, expected and actual | CD11 |

**`test-verify`**

| Test | Failed by |
|---|---|
| the floor is 7.85.0, #x075500 | VF1, VF2 |
| check-version: the floor itself, #x075500, is accepted | VF2, VF3, VF23 |
| check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source | CD4, CD5, VF1, VF7, VF8 |
| check-version: every feature but SSL is no-ssl, with the version, path and source | CD4, CD5, CN1, VF4, VF5, VF9 |
| check-version: SSL, 1<<2, alone is enough | CN1, VF23 |
| check-version: below the floor and without SSL, below-floor wins | CD4, CD5, VF6, VF7, VF8 |
| check-apis: an option found and header code 3 are accepted | VF24 |
| check-apis: no option by name is missing-api, naming curl_easy_option_by_name | CD4, CD5, CD6, VF10, VF16 |
| check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header | CD4, CD5, CD6, CN2, VF11, VF16 |
| check-apis: every other header code is accepted | CN2, VF12, VF24 |
| check-apis: with both APIs missing, the option probe is named: it runs first | CD4, CD5, CD6, VF10, VF13, VF16 |
| check-apis: the option probe's answer is a boolean, so a NULL pointer, 0, is refused | VF14 |
| check-version and check-apis: every refusal carries a who and a message, for the default handler | CD6, CN2, VF1, VF4, VF10, VF11, VF15 |
| feature-names: each bit alone names its own CURL_VERSION_ feature | CN3, CN5, VF20 |
| feature-names: every bit set names every feature, in curl.h's order | CN4, CN5, VF20, VF21 |
| feature-names: only the bits that are set | CN3, CN4, VF20, VF21 |
| feature-names: a bit not in the table comes back as an integer, after the names | VF17, VF18, VF19, VF20, VF22 |
| feature-names: no bits, no names | VF20 |

**`test-discovery`**

| Test | Failed by |
|---|---|
| override: an absolute CHEZ_CURL_LIBCURL is chosen as given, with source override | DS1 |
| override: it is never checked with exists?, since loading decides | DS1, DS2 |
| override: a relative path is invalid-override, carrying the value, with no fallback | CD4, CD5, DS3, DS5, DS6 |
| override: a bare name is invalid-override | CD4, CD5, DS3, DS5 |
| override: set but empty is invalid-override | CD4, CD5, DS3, DS4, DS5 |
| override: chosen on macOS, over Apple's | DS1, DS7 |
| override: chosen on a platform with no list | DS1, DS8 |
| platform: a machine type ending in le is Linux | DS9, DS20 |
| platform: a machine type ending in osx is macOS, on both architectures | DS10 |
| platform: any other has no candidates, so not-found with an empty list | DS11, DS38 |
| macos: Apple's /usr/lib/libcurl.4.dylib, returned without asking exists? | DS12 |
| macos: the world is not consulted, so a Guix maps text changes nothing | DS13 |
| world: libc.so.6 under /gnu/store/, on any line, is guix | DS14 |
| world: libc.so.6 under /usr/lib is fhs | DS20 |
| world: an unreadable /proc/self/maps, #f, is fhs | DS19 |
| world: other libraries from /gnu/store/ in an FHS process are fhs | DS15, DS20 |
| world: a basename that only resembles libc.so.6 is fhs | DS15, DS16, DS17, DS20 |
| world: libc.so.6 under a /gnu/store/ that is not at the root is fhs | DS18, DS20 |
| guix: the candidate list, in ADR-0002's order | DS21, DS22, DS23, DS28 |
| guix: GUIX_ENVIRONMENT unset contributes nothing | DS22, DS23, DS27, DS28 |
| guix: GUIX_ENVIRONMENT set but empty contributes nothing | DS22, DS23, DS24, DS28 |
| guix: a relative GUIX_PROFILE contributes nothing | DS6, DS22, DS23, DS25, DS28 |
| guix: HOME unset contributes neither home candidate | DS21, DS23, DS27, DS28 |
| guix: a relative HOME contributes neither home candidate | DS6, DS21, DS23, DS26, DS28 |
| guix: a standard directory is never chosen, even when every one exists | DS14, DS21, DS22, DS23, DS28, DS37, DS38 |
| guix: precedence: each candidate wins over every one after it | DS14, DS21, DS22, DS23, DS31 |
| guix: probing asks in order, and stops at the first that exists | DS14, DS21, DS22, DS30, DS31 |
| fhs: the candidate list for ta6le, in ADR-0002's order | DS29, DS32, DS33 |
| fhs: the candidate list for tarm64le, under aarch64-linux-gnu | DS29, DS32, DS33, DS34 |
| fhs: an unknown Linux machine type has no triple directory | DS9, DS29, DS32, DS36 |
| fhs: a Guix profile is never chosen, even when every one exists | DS20, DS29, DS32, DS33, DS37, DS38 |
| fhs: precedence: each candidate wins over every one after it | DS20, DS31, DS32, DS33 |
| fhs: the GnuTLS build is chosen only when no libcurl.so.4 exists | DS20, DS31, DS33 |
| triple table: ta6le and tarm64le, and no other machine type | DS34, DS35 |
| not-found lists every path it checked, in order, with no path, source or detail | DS20, DS29, DS30, DS31, DS32, DS33, DS37, DS38 |
| choose-libcurl: every refusal carries a who and a message, for the default handler | DS3, DS39 |
| discovery reads no variable but CHEZ_CURL_LIBCURL, GUIX_ENVIRONMENT, GUIX_PROFILE and HOME | DS14, DS40 |
| libcurl-sources: exactly the eight sources, in order | DS41 |
| the real /proc/self/maps is read on Linux, and only there | DS42 |
| the real /proc/self/maps: guix exactly when this Chez's binary lies under /gnu/store/ | DS14, DS42 |
| libcurl-candidates refuses a Linux world that is neither guix nor fhs | DS43 |

**`test-require-threaded`**

| Test | Failed by |
|---|---|
| the refusal first among the imports is first | RC11 |
| the refusal after (rnrs) is not first | RC1, RC3 |
| no refusal among the imports is absent | RC1 |
| no imports at all is absent | RC2 |
| a wrapped or versioned refusal is the same library | RC11, RC4, RC5 |
| a file whose first datum is no library form is not a library | RC6 |
| the scan reads .sls sources and skips the dotfiles beside them | RC7 |
| src/ defines (curl private require-threaded) | RS5, RS6, RC8 |
| the scan read src/: conditions, constants, discovery and verify | RS6, RC8 |
| the order rows are live: src/ holds a library besides the refusal | RS6, RC10 |
| src/curl/private/conditions.sls imports (curl private require-threaded) first | RS1, RC11 |
| src/curl/private/constants.sls imports (curl private require-threaded) first | RS2, RC11 |
| src/curl/private/discovery.sls imports (curl private require-threaded) first | RS3, RC11 |
| src/curl/private/verify.sls imports (curl private require-threaded) first | RS4, RC11 |
| the refusal exports nothing | RS5, RS6, RC8, RT5 |
| the refusal asks (threaded?) | RS5, RS6, RC8, RT2 |
| on this threaded Chez, the refusal lets its library load | RS5, RS6, RC8, RT3 |
| where (threaded?) is #f, the refusal raises its message at expansion | RS5, RS6, RC8, RT1, RT2, RT3, RT4, RT6 |

## check-seam

Evidence that `make check-seam` fails through the property each of its rules claims to guard
([ADR-0007](decisions/0007-one-repo-checked-seam.md), [global constraints](global-constraints.md),
"Layout and names"), and that `make test` and `make check-test-fails` notice if it stops. Every
mutation was applied to a fresh copy of the working tree, made without `.git`, `build/` and `src/`,
in the session scratchpad. The working tree was never edited, and it has no `src/`: every planted
library lives in a copy. A driver planted the files, ran the check through `scripts/guix-env`, and
compared the exit status and the whole output with text written by hand before the program
existed, never a substring. It refused a mutation that changed nothing, and kept every failure
verbatim. Baseline: `9bacc6d` plus this slice. Each mutation ran in its own copy, so the clean
rerun after each one is the baseline itself; the last section runs the finished tree once more.

There are three kinds of mutation:

- A **case** is a state mutation: files planted in a copy. The check is right, so it must pass, or
  fail by name, and **Result** quotes its own output. `make` turns the program's exit 1 into its
  own 2. Cases are named `P` (legal trees), `A` (rule a), `B` (rule b), `M` (several problems),
  and, for what the check refuses to pass over, `N` (no library), `U` (unreadable), `D` (no library
  form), `I` (imports it cannot read), `L` (links), `X` (no argument) and `T` (no Chez).
- A **code** mutant (`CM`) breaks the program. The driver runs every case against it, with the
  program run directly, and **Result** names the cases that failed. A mutant that fails no case has
  survived.
- A **make** mutant (`MM`) breaks the Makefile or `tests/check-test-fails.sh`.

The check reads each `.sls` under `src` with Chez's `read` and evaluates nothing. A library is a
`(curl ...)` library when the first identifier of its name is `curl`. Rule (a): such a library may
import nothing from `(http-client ...)`. Rule (b): an `(http-client ...)` library may import from
`(curl ...)` only the libraries in `public-curl`, `((curl))`. It looks through `for`, `only`,
`except`, `prefix`, `rename` and `library`, and drops a version reference.

### Red run, before the program existed

The Makefile (target, `.PHONY` entry and `test`'s prerequisite), the `seam` case of
`tests/check-test-fails.sh` and the cases were written first. `tests/check-seam.sps` did not exist.

- **`make check-seam`:** `Exception in load-program: failed for tests/check-seam.sps: no such file or directory`, exit 2.
- **The cases:** the first set had 38 and gave `1 passed, 37 failed`. The final set of 43, run with
  the program removed from a copy of the finished tree, gave `1 passed, 42 failed`. All 42 failed
  their output check. Six also failed their exit status: P0 to P4 wanted 0 and got make's 2, and X1
  wanted 1 and got Chez's 255. The other 36 want a failure, and pass their status check by absence,
  since make exits 2 for a missing program as for a failing one; CM21 and CM22 fail those checks.
  T1 passed: `scripts/require-tools` runs before the program, and MM6 is what fails it.
- **`make test`,** in a copy holding the legal pair: `check-suites` printed its line, then the
  same `Exception in load-program` line, and make stopped at `check-seam` with exit 2. No suite ran.
- **`make check-test-fails`,** in the same copy: `seam`, `fails`, `no-tests`, `hangs` and
  `no-suites` failed, each with `make test`'s lines in place of the wanted ones. The other four
  passed, since `check-suites` stops `make test` before `check-seam`: `exit-line`, `early-exit`,
  `nested-exit` and `empty`.

P4, D8, D9, D10 and I3 were written after the program passed the first 38, as were the added specs
of I1 and the file `src/curlsls` of N3. Their red run is the one above, and each has a mutant that
fails it: CM44 (P4), CM40 and CM41 (D8), CM42 and CM48 (D9), CM49 (D10), CM50 (I3), CM45 (N3's
`src/curlsls`), and CM35, CM37, CM38, CM47 and CM48 (I1's added specs). One mutant survived the
first pass: see Findings.

### Baseline

In the worktree, which has no `src/`, `make check-seam` exits 2 with the no-libraries message
(it is N1, run for real):

```
check-seam: no libraries: src holds no .sls file, so there is no seam to check
check-seam: FAILED (problems: 1)
```

In a copy holding the legal pair (P0), `scripts/guix-env sh -c 'make test && make check-test-fails'`
exits 0. The tails of both are under Clean rerun. All 43 cases pass, each in its own copy through
`make check-seam` (X1 runs the program with no argument instead), and all but T1 again with the
program run directly on every case in one container call.

### Legal trees pass

The base of every case is the legal pair: `src/curl.sls`, `(curl)`, importing `(curl private x)` and `(rnrs)`; `src/curl/private/x.sls`; and `src/http-client.sls`, `(http-client)`, importing `(curl)` and `(rnrs)`. Each starts with `#!r6rs`, as the project's libraries do, so every case also shows that line reading.

#### P0. The legal pair

**Guards:** A tree that obeys the seam passes, and the verdict counts what it read.
**Mutation:** The base: `(curl)` imports `(curl private x)`, and `(http-client)` imports `(curl)`. Each file starts with `#!r6rs`.
**Result:** exit 0, and the whole output:
```
check-seam: the seam holds (3 libraries in 3 files checked)
```

#### P1. Legal imports in every shape

**Guards:** No false positive for the wrappers, versions and other libraries.
**Mutation:** Five more libraries: `(curl private y)`, `(curl unsupported)` and `(http-client session)`, `(http-client private store)`, `(http-client versioned (1 0))`. Between them they import `(rnrs (6))`, `(chezscheme)`, `(srfi :64)`, `(for (only (curl) x) run expand)`, `(prefix (curl (1 0)) c:)`, `(rename (http-client session) (x y))`, `(library (http-client))`, `(except (curl) hidden)` and `(http-client)`.
**Result:** exit 0, and the whole output:
```
check-seam: the seam holds (8 libraries in 8 files checked)
```

#### P2. Tests are exempt

**Guards:** Only `src/` is read (ADR-0007).
**Mutation:** `tests/exempt-curl.sls` is a `(curl exempt)` importing `(http-client)`, and `tests/exempt-http.sls` an `(http-client exempt)` importing `(curl private x)`.
**Result:** exit 0, and the whole output:
```
check-seam: the seam holds (3 libraries in 3 files checked)
```

#### P3. Other families

**Guards:** A library is a (curl ...) or (http-client ...) library when the first identifier of its name says so.
**Mutation:** `(curl-extras)` imports `(http-client)`, and `(http-client-extras)` imports `(curl private x)`.
**Result:** exit 0, and the whole output:
```
check-seam: the seam holds (5 libraries in 5 files checked)
```

#### P4. Two libraries in one file

**Guards:** The count is of libraries, not files.
**Mutation:** `src/curl/pair.sls` holds two legal libraries.
**Result:** exit 0, and the whole output:
```
check-seam: the seam holds (5 libraries in 4 files checked)
```

### Rule (a): a (curl ...) library imports (http-client ...)

#### A1. A (curl ...) library imports an (http-client ...) library

**Guards:** Rule (a), in its plainest form.
**Mutation:** `src/curl/planted.sls`, `(library (curl planted) …)`, imports `(http-client session)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/planted.sls: (curl planted) imports (http-client session), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### A2. The (curl) library itself

**Guards:** Rule (a) covers `(curl)`, not only `(curl ...)` with a tail.
**Mutation:** `src/curl.sls`, the legal base's `(curl)`, gains `(http-client)` among its imports.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl.sls: (curl) imports (http-client), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### A3. Through `only`

**Guards:** The `only` wrapper is looked through.
**Mutation:** `(curl via-only)` imports `(only (http-client via-only) x)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/via-only.sls: (curl via-only) imports (http-client via-only), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### A4. Through `except`

**Guards:** The `except` wrapper is looked through.
**Mutation:** `(curl via-except)` imports `(except (http-client via-except) x)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/via-except.sls: (curl via-except) imports (http-client via-except), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### A5. Through `prefix`

**Guards:** The `prefix` wrapper is looked through.
**Mutation:** `(curl via-prefix)` imports `(prefix (http-client via-prefix) h:)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/via-prefix.sls: (curl via-prefix) imports (http-client via-prefix), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### A6. Through `rename`

**Guards:** The `rename` wrapper is looked through.
**Mutation:** `(curl via-rename)` imports `(rename (http-client via-rename) (x y))`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/via-rename.sls: (curl via-rename) imports (http-client via-rename), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### A7. Through `library`

**Guards:** The `library` wrapper is looked through.
**Mutation:** `(curl via-library)` imports `(library (http-client via-library))`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/via-library.sls: (curl via-library) imports (http-client via-library), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### A8. Through `for`

**Guards:** R6RS's `for` wrapper is looked through. The brief named five wrappers and left this one out.
**Mutation:** `(curl via-for)` imports `(for (http-client via-for) run expand)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/via-for.sls: (curl via-for) imports (http-client via-for), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### A9. A version reference

**Guards:** A trailing version reference does not hide a name, on the import or on the importing library.
**Mutation:** `(curl versioned (2))` imports `(http-client via-version (1 0))`. The complaint names both without their versions.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/versioned.sls: (curl versioned) imports (http-client via-version), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### A10. Wrappers inside wrappers

**Guards:** The wrappers compose.
**Mutation:** `(curl via-nested)` imports `(only (prefix (for (library (http-client via-nested (1))) expand) h:) x)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/via-nested.sls: (curl via-nested) imports (http-client via-nested), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

### Rule (b): an (http-client ...) library imports a (curl ...) library that is not public

#### B1. An (http-client ...) library imports (curl private ...)

**Guards:** Rule (b), in its plainest form.
**Mutation:** `src/http-client/planted.sls`, `(http-client planted)`, imports `(curl)`, which is legal, and `(curl private y)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/http-client/planted.sls: (http-client planted) imports (curl private y), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))
check-seam: FAILED (problems: 1)
```

#### B2. The escape hatch

**Guards:** `(curl unsupported)` is out of the high level's reach (ADR-0009).
**Mutation:** `(http-client hatch)` imports `(curl unsupported)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/http-client/hatch.sls: (http-client hatch) imports (curl unsupported), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))
check-seam: FAILED (problems: 1)
```

#### B3. Through wrappers and a version

**Guards:** Rule (b) sees through the wrappers and a version reference.
**Mutation:** `(http-client wrapped)` imports `(for (only (curl private z (1)) x) run)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/http-client/wrapped.sls: (http-client wrapped) imports (curl private z), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))
check-seam: FAILED (problems: 1)
```

#### B4. An (http-client private ...) library

**Guards:** Rule (b) binds `(http-client private ...)` too.
**Mutation:** `(http-client private p)` imports `(prefix (curl private w) w:)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/http-client/private/p.sls: (http-client private p) imports (curl private w), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))
check-seam: FAILED (problems: 1)
```

### More than one problem

#### M1. Both rules, in different directories

**Guards:** Every bad file is named, in path order, and subdirectories are entered.
**Mutation:** `src/curl/aaa.sls` breaks rule (a) and `src/http-client/deep/er/zzz.sls` breaks rule (b). The second is written first.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/aaa.sls: (curl aaa) imports (http-client m1a), but no (curl ...) library may import an (http-client ...) library
check-seam: src/http-client/deep/er/zzz.sls: (http-client zzz) imports (curl private m1z), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))
check-seam: FAILED (problems: 2)
```

#### M2. Two bad imports in one file

**Guards:** Every bad import of a library is named, in import order.
**Mutation:** `(curl two)` imports `(http-client first)`, `(rnrs)`, then `(http-client second)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/two.sls: (curl two) imports (http-client first), but no (curl ...) library may import an (http-client ...) library
check-seam: src/curl/two.sls: (curl two) imports (http-client second), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 2)
```

#### M3. The bad import comes last

**Guards:** The whole import list is read.
**Mutation:** `(curl last)` imports `(rnrs)`, `(chezscheme)`, `(curl private x)`, `(srfi :64)`, then `(http-client last-import)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/last.sls: (curl last) imports (http-client last-import), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

### It fails closed

A check that passes on nothing, or on what it could not read, is vacuous.

#### N1. No src/

**Guards:** A check that passes on nothing is vacuous.
**Mutation:** The copy has no `src/` at all, which is the worktree's own state.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: no libraries: src holds no .sls file, so there is no seam to check
check-seam: FAILED (problems: 1)
```

#### N2. An empty src/

**Guards:** As N1.
**Mutation:** `src/` is an empty directory.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: no libraries: src holds no .sls file, so there is no seam to check
check-seam: FAILED (problems: 1)
```

#### N3. Files, but no .sls

**Guards:** Only `.sls` files are libraries.
**Mutation:** `src/curl.scm`, `src/notes.txt`, `src/curl/x.sls.bak` and `src/curlsls`; each of the three code files holds a library that imports `(http-client)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: no libraries: src holds no .sls file, so there is no seam to check
check-seam: FAILED (problems: 1)
```

#### U1. A file the reader cannot read

**Guards:** An unreadable library is named, not a crash.
**Mutation:** `src/curl/broken.sls` ends inside an unclosed `(import (rnrs)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/broken.sls: it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 60 of #<input port src/curl/broken.sls>; the character position might differ
check-seam: FAILED (problems: 1)
```

#### U2. An #!eof literal

**Guards:** A reader that stops at `#!eof` must not answer for the file after it.
**Mutation:** `src/curl.sls` is a legal library, then `#!eof`, then `(curl hidden)` importing `(http-client hidden)`. The file has no `#!r6rs` line; see Findings.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl.sls: it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file
check-seam: FAILED (problems: 1)
```

#### D1. A first datum that is no library

**Guards:** The first datum must be a library form.
**Mutation:** `src/curl/d1.sls` holds `(define x 1)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/d1.sls: datum 1 is (define x 1), not a library form
check-seam: FAILED (problems: 1)
```

#### D2. No datum

**Guards:** A file with no datum is named.
**Mutation:** `src/curl/d2.sls` holds `#!r6rs` and a comment.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/d2.sls: it holds no datum, so it holds no library form
check-seam: FAILED (problems: 1)
```

#### D3. A program

**Guards:** A program's import is not read as a library's.
**Mutation:** `src/http-client/d3.sls` holds `(import (rnrs) (curl private x))`, which rule (b) would flag if it were a library.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/http-client/d3.sls: datum 1 is (import (rnrs) (curl private x)), not a library form
check-seam: FAILED (problems: 1)
```

#### D4. No import clause

**Guards:** A library form needs its export and import clauses.
**Mutation:** `src/curl/d4.sls` holds `(library (curl d4) (export))`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/d4.sls: datum 1 is (library (curl d4) (export)), not a library form
check-seam: FAILED (problems: 1)
```

#### D5. A second datum

**Guards:** A datum after the library is named.
**Mutation:** `src/curl/d5.sls` is a legal library followed by `(display "hi")`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/d5.sls: datum 2 is (display "hi"), not a library form
check-seam: FAILED (problems: 1)
```

#### D6. A second library

**Guards:** Every library form in a file is checked.
**Mutation:** `src/curl/d6.sls` holds a legal `(curl d6a)` and then `(curl d6b)`, which imports `(http-client d6)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/d6.sls: (curl d6b) imports (http-client d6), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

#### D7. A long datum

**Guards:** A datum over 60 characters is cut to 57 and three dots.
**Mutation:** `src/curl/d7.sls` holds a 70-character `(define …)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/d7.sls: datum 1 is (define the-quick-brown-fox-jumps-over-the-lazy-dog-again..., not a library form
check-seam: FAILED (problems: 1)
```

#### D8. Clauses swapped, missing or misspelled

**Guards:** Both clause heads are checked, each on its own.
**Mutation:** `d8a.sls` has import before export, `d8b.sls` has a `define` where the import clause belongs, and `d8c.sls` says `exports`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/d8a.sls: datum 1 is (library (curl a) (import (rnrs)) (export x)), not a library form
check-seam: src/curl/d8b.sls: datum 1 is (library (curl b) (export x) (define x 1)), not a library form
check-seam: src/curl/d8c.sls: datum 1 is (library (curl c) (exports x) (import (rnrs))), not a library form
check-seam: FAILED (problems: 3)
```

#### D9. A name with no identifier, or an improper one

**Guards:** A library whose name cannot be read cannot hide its imports.
**Mutation:** `src/curl/d9.sls` holds `(library (1 2) (export) (import (http-client)))`, and `d9b.sls` holds `(library (curl . x) …)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/d9.sls: datum 1 is (library (1 2) (export) (import (http-client))), not a library form
check-seam: src/curl/d9b.sls: datum 1 is (library (curl . x) (export) (import (http-client))), not a library form
check-seam: FAILED (problems: 2)
```

#### D10. An R7RS define-library

**Guards:** Only a `library` form is read as a library. Chez does not load `define-library`.
**Mutation:** `src/curl/d10.sls` holds `(define-library (curl d10) (export) (import (http-client)))`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/d10.sls: datum 1 is (define-library (curl d10) (export) (import (http-client))), not a library form
check-seam: FAILED (problems: 1)
```

#### I1. Imports that are no import sets

**Guards:** An import the check cannot read is named, never skipped.
**Mutation:** `(curl i1)` imports `()`, `foo`, `(only)`, `(library)`, `(library (http-client x1) extra)`, `(library (http-client . y))`, `(1 2)` and `(http-client . x)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/i1.sls: (curl i1) has an import it cannot read: ()
check-seam: src/curl/i1.sls: (curl i1) has an import it cannot read: foo
check-seam: src/curl/i1.sls: (curl i1) has an import it cannot read: (only)
check-seam: src/curl/i1.sls: (curl i1) has an import it cannot read: (library)
check-seam: src/curl/i1.sls: (curl i1) has an import it cannot read: (library (http-client x1) extra)
check-seam: src/curl/i1.sls: (curl i1) has an import it cannot read: (library (http-client . y))
check-seam: src/curl/i1.sls: (curl i1) has an import it cannot read: (1 2)
check-seam: src/curl/i1.sls: (curl i1) has an import it cannot read: (http-client . x)
check-seam: FAILED (problems: 8)
```

#### I3. A long import it cannot read

**Guards:** The cut applies to an import as it does to a datum.
**Mutation:** `(curl i3)` imports an improper list over 60 characters long.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/i3.sls: (curl i3) has an import it cannot read: (this-is-a-really-long-import-set-name-that-goes-past-six...
check-seam: FAILED (problems: 1)
```

#### I2. An import set that contains itself

**Guards:** A cyclic datum ends the walk instead of hanging it.
**Mutation:** `(curl i2)` imports `#0=(only #0# x)`. The file has no `#!r6rs` line; see Findings.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/i2.sls: (curl i2) has an import it cannot read: #0=(only #0# x)
check-seam: FAILED (problems: 1)
```

#### L1. A symbolic link to a directory

**Guards:** A tree of libraries behind a link is named, not skipped.
**Mutation:** `src/linked` is a link to `../elsewhere`, which holds `bad.sls`, a `(curl bad)` importing `(http-client linked)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/linked: it is a symbolic link to a directory, which this check does not follow
check-seam: FAILED (problems: 1)
```

#### X1. No directory argument

**Guards:** The program refuses to guess a directory.
**Mutation:** The program is run with no argument: `$CHEZ --program tests/check-seam.sps`.
**Result:** exit 1, the program's own status, and the whole output:
```
check-seam: usage: scheme --program tests/check-seam.sps DIR
```

#### T1. No Chez

**Guards:** `require-tools` names a missing Chez and the goal.
**Mutation:** `CHEZ=/nonexistent/scheme make check-seam`.
**Result:** exit 2, and the whole output, make's own `***` line aside:
```
make check-seam: /nonexistent/scheme not found.
Install the missing tools, then run make check-seam again.
```

### Code mutants

55 mutants of `tests/check-seam.sps`, each in its own copy, each run against all 43 cases. The first pass had 46 of them and the 9 make mutants, and killed all but CM35 (Findings). The cases that kill it were added, CM47 to CM55 and MM10 were written, and the whole set ran again: **55 of 55 code mutants killed, 0 survived.** The entries below are from that last run.

#### CM1. Rule (a) deleted

**Guards:** Rule (a): A1 to A10, D6, M1 to M3.
**Mutation:**
```
-((and (family? 'curl name) (family? 'http-client imported))
+((and #f (family? 'curl name) (family? 'http-client imported))
```
**Result:** killed by 14 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, D6, M1, M2, M3. For example A10 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM2. Rule (a) exempts the (curl) library itself

**Guards:** A2: rule (a) covers `(curl)` itself.
**Mutation:**
```
-((and (family? 'curl name) (family? 'http-client imported))
+((and (family? 'curl name) (pair? (cdr name)) (family? 'http-client imported))
```
**Result:** killed by 1 case: A2. For example A2 exited 0 (wanted 1) and printed `check-seam: the seam holds (3 libraries in 3 files checked)`.

#### CM3. Rule (b) deleted

**Guards:** Rule (b): B1 to B4 and M1.
**Mutation:**
```
-((and (family? 'http-client name) (family? 'curl imported)
+((and #f (family? 'http-client name) (family? 'curl imported)
```
**Result:** killed by 5 cases: B1, B2, B3, B4, M1. For example B1 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM4. The public list widened to (curl unsupported)

**Guards:** The public list is exactly `((curl))`, and every rule (b) message names it.
**Mutation:**
```
-(define public-curl '((curl)))
+(define public-curl '((curl) (curl unsupported)))
```
**Result:** killed by 5 cases: B1, B2, B3, B4, M1. For example B2 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM5. The escape hatch accepted, the public list left alone

**Guards:** B2: `(curl unsupported)` is on no list.
**Mutation:**
```
-(not (member imported public-curl)))
+(not (or (member imported public-curl) (and (pair? (cdr imported)) (eq? (cadr imported) 'unsupported)))))
```
**Result:** killed by 1 case: B2. For example B2 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM6. Private libraries accepted, the public list left alone

**Guards:** B1, B3 and B4: `(curl private ...)` is on no list.
**Mutation:**
```
-(not (member imported public-curl)))
+(not (or (member imported public-curl) (and (pair? (cdr imported)) (eq? (cadr imported) 'private)))))
```
**Result:** killed by 4 cases: B1, B3, B4, M1. For example B1 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM7. The public list empty

**Guards:** P0: `(curl)` is public.
**Mutation:**
```
-(define public-curl '((curl)))
+(define public-curl '())
```
**Result:** killed by 38 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, I1, I2, I3, L1, M1, M2, M3, P0, P1, P2, P3, P4, U1, U2. For example P0 exited 1 (wanted 0) and printed `check-seam: src/http-client.sls: (http-client) imports (curl), but an (http-client ...) library may import only the public (curl ...) libraries ()`.

#### CM8. The `for` wrapper not looked through

**Guards:** A8.
**Mutation:**
```
-(define wrappers '(for only except prefix rename))
+(define wrappers '(only except prefix rename))
```
**Result:** killed by 3 cases: A8, A10, B3. For example A10 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM9. The `only` wrapper not looked through

**Guards:** A3.
**Mutation:**
```
-(define wrappers '(for only except prefix rename))
+(define wrappers '(for except prefix rename))
```
**Result:** killed by 5 cases: A3, A10, B3, I1, I2. For example A10 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM10. The `except` wrapper not looked through

**Guards:** A4.
**Mutation:**
```
-(define wrappers '(for only except prefix rename))
+(define wrappers '(for only prefix rename))
```
**Result:** killed by 1 case: A4. For example A4 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM11. The `prefix` wrapper not looked through

**Guards:** A5.
**Mutation:**
```
-(define wrappers '(for only except prefix rename))
+(define wrappers '(for only except rename))
```
**Result:** killed by 3 cases: A5, A10, B4. For example A10 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM12. The `rename` wrapper not looked through

**Guards:** A6.
**Mutation:**
```
-(define wrappers '(for only except prefix rename))
+(define wrappers '(for only except prefix))
```
**Result:** killed by 1 case: A6. For example A6 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM13. The `library` wrapper not looked through

**Guards:** A7.
**Mutation:**
```
-((eq? (car spec) 'library)
+((eq? (car spec) 'library-off)
```
**Result:** killed by 3 cases: A7, A10, I1. For example A10 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM14. The version reference kept in the name

**Guards:** A version reference is dropped from a name.
**Mutation:**
```
-(and (pair? found) (reverse found))))))
+(and (pair? found) ref)))))
```
**Result:** killed by 4 cases: A9, A10, B3, P1. For example P1 exited 1 (wanted 0) and printed `check-seam: src/http-client/session.sls: (http-client session) imports (curl (1 0)), but an (http-client ...) library may import only the public (c...`.

#### CM15. Only a library's first import examined

**Guards:** Every import is read, not only the first.
**Mutation:**
```
-(cdr (cadddr form))))))
+(let ((specs (cdr (cadddr form)))) (if (null? specs) specs (list (car specs))))))))
```
**Result:** killed by 21 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, D6, I1, I2, I3, M1, M2, M3. For example A10 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM16. Only a file's first datum examined

**Guards:** Every datum is read, not only the first.
**Mutation:**
```
-(loop (cdr rest) (+ n 1)))))))
+'())))))
```
**Result:** killed by 2 cases: D5, D6. For example D5 exited 0 (wanted 1) and printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM17. Subdirectories not entered

**Guards:** Subdirectories are entered.
**Mutation:**
```
-(let ((below (walk path)))
+(let ((below (cons '() '())))
```
**Result:** killed by 35 cases: A1, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, I1, I2, I3, M1, M2, M3, P0, P1, P2, P3, P4, U1. For example A10 exited 0 (wanted 1) and printed `check-seam: the seam holds (2 libraries in 2 files checked)`.

#### CM18. The no-libraries guard deleted

**Guards:** N1 to N3: no library is a failure.
**Mutation:**
```
-(if (null? files)
+(if #f
```
**Result:** killed by 3 cases: N1, N2, N3. For example N1 exited 0 (wanted 1) and printed `check-seam: the seam holds (0 libraries in 0 files checked)`.

#### CM19. An unreadable file skipped without a word

**Guards:** U1 and U2: an unreadable file is named.
**Mutation:**
```
-(cons (list (string-append path ": it cannot be read as data: " (cadr found)))
+(cons (begin (cadr found) '())
```
**Result:** killed by 2 cases: U1, U2. For example U1 exited 0 (wanted 1) and printed `check-seam: the seam holds (3 libraries in 4 files checked)`.

#### CM20. A datum that is not a library form skipped without a word

**Guards:** D1 to D5, D7 to D9: a datum that is no library form is named.
**Mutation:**
```
-(list (string-append path ": datum " (number->string n)
-" is " (abbreviated (car rest))
-", not a library form")))
+'()))
```
**Result:** killed by 42 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, I1, I2, I3, L1, M1, M2, M3, N1, N2, N3, P0, P1, P2, P3, P4, U1, U2, X1. For example A10 exited 255 (wanted 1) and printed `Exception in read: unexpected close parenthesis at line 184, char 50 of ../../tests/check-seam.sps`.

#### CM21. Exit 0 on a failure

**Guards:** A failure exits non-zero.
**Mutation:**
```
-(exit 1))))))
+(exit 0))))))
```
**Result:** killed by 36 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, I1, I2, I3, L1, M1, M2, M3, N1, N2, N3, U1, U2. For example A10 exited 0 (wanted 1).

#### CM22. The number of problems as the exit status

**Guards:** The status is 0 or 1, never a count (an exit status wraps at 256).
**Mutation:**
```
-(exit 1))))))
+(exit (length complaints)))))))
```
**Result:** killed by 5 cases: D8, D9, I1, M1, M2. For example D8 exited 3 (wanted 1).

#### CM23. Only the first problem printed

**Guards:** Every problem is named, not only the first.
**Mutation:**
```
-(for-each (lambda (c) (say (current-error-port) c)) complaints)
+(say (current-error-port) (car complaints))
```
**Result:** killed by 5 cases: D8, D9, I1, M1, M2.

#### CM24. Every file read, not only .sls

**Guards:** Only `.sls` files are read.
**Mutation:**
```
-((suffix? (car names) ".sls")
+(#t
```
**Result:** killed by 1 case: N3. For example N3 printed `check-seam: src/curl.scm: (curl scm) imports (http-client), but no (curl ...) library may import an (http-client ...) library`.

#### CM25. The #!eof guard deleted

**Guards:** U2: an `#!eof` is named.
**Mutation:**
```
-((port-eof? port) (list 'data (reverse found)))
+(#t (list 'data (reverse found)))
```
**Result:** killed by 1 case: U2. For example U2 exited 0 (wanted 1) and printed `check-seam: the seam holds (3 libraries in 3 files checked)`.

#### CM26. A symbolic link to a directory skipped without a word

**Guards:** L1: a link is named.
**Mutation:**
```
-(loop (cdr names) files (cons path links)))
+(loop (cdr names) files links))
```
**Result:** killed by 1 case: L1. For example L1 exited 0 (wanted 1) and printed `check-seam: the seam holds (3 libraries in 3 files checked)`.

#### CM27. Symbolic links to directories followed

**Guards:** L1: a link is not followed, so a link cycle cannot loop the walk.
**Mutation:**
```
-((file-directory? path #f)
+((file-directory? path)
```
**Result:** killed by 1 case: L1. For example L1 printed `check-seam: src/linked/bad.sls: (curl bad) imports (http-client linked), but no (curl ...) library may import an (http-client ...) library`.

#### CM28. The nesting limit deleted

**Guards:** I2: a cyclic import set ends the walk.
**Mutation:**
```
-((or (not (list? spec)) (null? spec) (> depth max-depth)) #f)
+((or (not (list? spec)) (null? spec) #f) #f)
```
**Result:** killed by 1 case: I2. For example I2 exited 124 (wanted 1).

#### CM29. An import it cannot read accepted

**Guards:** I1 and I2: an import the check cannot read is named.
**Mutation:**
```
-((not imported)
-(list (string-append path ": " (written name)
-" has an import it cannot read: "
-(abbreviated spec))))
+((not imported) '())
```
**Result:** killed by 3 cases: I1, I2, I3. For example I1 exited 0 (wanted 1).

#### CM30. No cut for a long datum

**Guards:** D7: a long datum is cut.
**Mutation:**
```
-(if (> (string-length text) 60)
+(if #f
```
**Result:** killed by 2 cases: D7, I3. For example D7 printed `check-seam: src/curl/d7.sls: datum 1 is (define the-quick-brown-fox-jumps-over-the-lazy-dog-again-and-again 1), not a library form`.

#### CM31. The cut one character late

**Guards:** D7: the cut is at 57.
**Mutation:**
```
-(string-append (substring text 0 57) "...")
+(string-append (substring text 0 58) "...")
```
**Result:** killed by 2 cases: D7, I3. For example D7 printed `check-seam: src/curl/d7.sls: datum 1 is (define the-quick-brown-fox-jumps-over-the-lazy-dog-again-..., not a library form`.

#### CM32. A family by string prefix, so curl-extras is a (curl ...) library

**Guards:** P3: the first identifier of a name makes a family, not a prefix of it.
**Mutation:**
```
-(and (pair? name) (eq? (car name) first)))
+(and (pair? name) (let ((s (symbol->string (car name))) (f (symbol->string first))) (and (>= (string-length s) (string-length f)) (string=? (substring s 0 (string-length f)) f)))))
```
**Result:** killed by 1 case: P3. For example P3 exited 1 (wanted 0) and printed `check-seam: src/curl-extras.sls: (curl-extras) imports (http-client), but no (curl ...) library may import an (http-client ...) library`.

#### CM33. The usage check deleted

**Guards:** X1: a missing argument is refused.
**Mutation:**
```
-(if (not (= (length args) 1))
+(if #f
```
**Result:** killed by 1 case: X1. For example X1 exited 255 (wanted 1) and printed `Exception in car: () is not a pair`.

#### CM34. Files not sorted

**Guards:** M1: the files are named in path order.
**Mutation:**
```
-(files (list-sort string<? (car found)))
+(files (car found))
```
**Result:** killed by 2 cases: D8, M1. For example D8 printed `check-seam: src/curl/d8a.sls: datum 1 is (library (curl a) (import (rnrs)) (export x)), not a library form`.

#### CM35. An improper list taken for a reference

**Guards:** D9 and I1: an improper reference is no name.
**Mutation:**
```
-(and (list? ref)
+(and (or (list? ref) (pair? ref))
```
**Result:** killed by 2 cases: D9, I1. For example D9 printed `check-seam: src/curl/d9b.sls: (curl) imports (http-client), but no (curl ...) library may import an (http-client ...) library`.

#### CM36. A wrapper's arity not checked

**Guards:** I1: `(only)` is no import set.
**Mutation:**
```
-(and (>= (length spec) 2) (spec-name (cadr spec) (+ depth 1))))
+(spec-name (cadr spec) (+ depth 1)))
```
**Result:** killed by 1 case: I1. For example I1 exited 255 (wanted 1).

#### CM37. A library wrapper's arity not checked

**Guards:** I1: `(library)` is no import set.
**Mutation:**
```
-(and (= (length spec) 2) (reference-name (cadr spec))))
+(reference-name (cadr spec)))
```
**Result:** killed by 1 case: I1. For example I1 exited 255 (wanted 1).

#### CM38. A library wrapper may take two or more arguments

**Guards:** I1: `(library x extra)` is no import set.
**Mutation:**
```
-(and (= (length spec) 2) (reference-name (cadr spec))))
+(and (>= (length spec) 2) (reference-name (cadr spec))))
```
**Result:** killed by 1 case: I1. For example I1 printed `check-seam: src/curl/i1.sls: (curl i1) imports (http-client x1), but no (curl ...) library may import an (http-client ...) library`.

#### CM39. A library form of any length

**Guards:** D4: a library form has four parts at least.
**Mutation:**
```
-(>= (length datum) 4)
+#t
```
**Result:** killed by 1 case: D4. For example D4 exited 255 (wanted 1) and printed `Exception in cadddr: incorrect list structure (library (curl d4) (export))`.

#### CM40. The export clause not checked

**Guards:** D8: the third part is an export clause.
**Mutation:**
```
-(headed? 'export (caddr datum))
+#t
```
**Result:** killed by 1 case: D8. For example D8 printed `check-seam: FAILED (problems: 2)`.

#### CM41. The import clause not checked

**Guards:** D8: the fourth part is an import clause.
**Mutation:**
```
-(headed? 'import (cadddr datum))
+#t
```
**Result:** killed by 1 case: D8. For example D8 printed `check-seam: src/curl/d8b.sls: (curl b) has an import it cannot read: x`.

#### CM42. The library name not checked

**Guards:** D9: the name of a library has an identifier.
**Mutation:**
```
-(reference-name (cadr datum))
+#t
```
**Result:** killed by 1 case: D9. For example D9 exited 0 (wanted 1) and printed `check-seam: the seam holds (5 libraries in 5 files checked)`.

#### CM43. A missing directory raises

**Guards:** N1: a missing directory is a failure the check names.
**Mutation:**
```
-(found (if (file-directory? root) (walk root) (cons '() '())))
+(found (walk root))
```
**Result:** killed by 1 case: N1. For example N1 exited 255 (wanted 1) and printed `Exception in directory-list: failed for src: no such file or directory`.

#### CM44. One library counted per file

**Guards:** P4: the count is of libraries.
**Mutation:**
```
-(length (filter library-form? (cadr found))))
+1)
```
**Result:** killed by 1 case: P4. For example P4 printed `check-seam: the seam holds (4 libraries in 4 files checked)`.

#### CM45. A name that only ends in sls read

**Guards:** N3: `.sls` is the whole suffix.
**Mutation:**
```
-((suffix? (car names) ".sls")
+((suffix? (car names) "sls")
```
**Result:** killed by 1 case: N3. For example N3 printed `check-seam: src/curlsls: (curl sls) imports (http-client), but no (curl ...) library may import an (http-client ...) library`.

#### CM46. An import that is not a list reaches car

**Guards:** I1: an import that is no list is named.
**Mutation:**
```
-((or (not (list? spec)) (null? spec) (> depth max-depth)) #f)
+((or (null? spec) (> depth max-depth)) #f)
```
**Result:** killed by 1 case: I1. For example I1 exited 255 (wanted 1).

#### CM47. An empty import set reaches car

**Guards:** I1: `()` is no import set.
**Mutation:**
```
-((or (not (list? spec)) (null? spec) (> depth max-depth)) #f)
+((or (not (list? spec)) (> depth max-depth)) #f)
```
**Result:** killed by 1 case: I1. For example I1 exited 255 (wanted 1).

#### CM48. A reference with no identifier answers an empty name

**Guards:** D9 and I1: a reference with no identifier is no name.
**Mutation:**
```
-(and (pair? found) (reverse found))))))
+(reverse found)))))
```
**Result:** killed by 2 cases: D9, I1. For example D9 printed `check-seam: FAILED (problems: 1)`.

#### CM49. Any four-part list taken for a library form

**Guards:** D10: only a `library` form is a library.
**Mutation:**
```
-(eq? (car datum) 'library)
+#t
```
**Result:** killed by 1 case: D10. For example D10 printed `check-seam: src/curl/d10.sls: (curl d10) imports (http-client), but no (curl ...) library may import an (http-client ...) library`.

#### CM50. A malformed import written whole, not cut

**Guards:** I3: the cut applies to an import it cannot read.
**Mutation:**
```
-(abbreviated spec))))
+(written spec))))
```
**Result:** killed by 1 case: I3. For example I3 printed `check-seam: src/curl/i3.sls: (curl i3) has an import it cannot read: (this-is-a-really-long-import-set-name-that-goes-past-sixty-characters . x)`.

#### CM51. A datum numbered from the wrong step

**Guards:** D5: a datum is numbered from 1, a step at a time.
**Mutation:**
```
-(loop (cdr rest) (+ n 1)))))))
+(loop (cdr rest) (+ n 2)))))))
```
**Result:** killed by 1 case: D5. For example D5 printed `check-seam: src/curl/d5.sls: datum 3 is (display "hi"), not a library form`.

#### CM52. The problems counted in files

**Guards:** M2: the count counts problems, not files.
**Mutation:**
```
-(number->string (length complaints)) ")"))
+(number->string (length files)) ")"))
```
**Result:** killed by 36 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, I1, I2, I3, L1, M1, M2, M3, N1, N2, N3, U1, U2. For example A10 printed `check-seam: FAILED (problems: 4)`.

#### CM53. The public list searched with memq

**Guards:** P0: `(curl)` is found on the public list by `equal?`.
**Mutation:**
```
-(not (member imported public-curl)))
+(not (memq imported public-curl)))
```
**Result:** killed by 38 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, I1, I2, I3, L1, M1, M2, M3, P0, P1, P2, P3, P4, U1, U2. For example P0 exited 1 (wanted 0) and printed `check-seam: src/http-client.sls: (http-client) imports (curl), but an (http-client ...) library may import only the public (curl ...) libraries ((c...`.

#### CM54. A library's imports named in reverse order

**Guards:** M2: the imports of one library are named in order.
**Mutation:**
```
-(cdr (cadddr form))))))
+(reverse (cdr (cadddr form)))))))
```
**Result:** killed by 2 cases: I1, M2. For example I1 printed `check-seam: src/curl/i1.sls: (curl i1) has an import it cannot read: (1 2)`.

#### CM55. Files named in reverse path order

**Guards:** M1: the files are named in ascending path order.
**Mutation:**
```
-(files (list-sort string<? (car found)))
+(files (list-sort string>? (car found)))
```
**Result:** killed by 3 cases: D8, D9, M1. For example D8 printed `check-seam: src/curl/d8b.sls: datum 1 is (library (curl b) (export x) (define x 1)), not a library form`.

### Make and script mutants

#### MM1. The `check-seam` prerequisite dropped from `test`

**Guards:** The `seam` case of `check-test-fails`: `make test` runs `check-seam`.
**Mutation:**
```
-test: deps check-help check-suites check-seam ## Run every tests/test-*.sps under timeout; fail if one fails or hangs, or none exists
+test: deps check-help check-suites ## Run every tests/test-*.sps under timeout; fail if one fails or hangs, or none exists
```
**Result:** `make check-test-fails` exit 2, with these lines:
```
check-test-fails: FAILED seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs: make test exited 0
check-test-fails: FAILED seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs: make test's lines differ
```

#### MM2. `check-seam` left out of `.PHONY`

**Guards:** `check-help`: a listed target is in `.PHONY`.
**Mutation:**
```
-.PHONY: help check-help check-guix check-guix-inside deps check-pins test check-suites check-seam check-test-fails
+.PHONY: help check-help check-guix check-guix-inside deps check-pins test check-suites check-test-fails
```
**Result:** `make check-help` exit 2:
```
check-help: make help lists 'check-seam', which is not in .PHONY
```

#### MM3. `check-seam` without its help text

**Guards:** `check-help`: a `.PHONY` target is listed.
**Mutation:**
```
-check-seam: ## Fail unless no (curl ...) library imports (http-client ...), and (http-client ...) imports only (curl)
+check-seam: Fail unless no (curl ...) library imports (http-client ...), and (http-client ...) imports only (curl)
```
**Result:** `make check-help` exit 2:
```
check-help: make help does not list .PHONY target 'check-seam'; give it a '## ' description on its target line
```

#### MM4. The recipe reads tests, not src

**Guards:** The recipe reads `src`.
**Mutation:**
```
-@$(CHEZ) --program tests/check-seam.sps src
+@$(CHEZ) --program tests/check-seam.sps tests
```
**Result:** killed by 3 cases: A1, N1, P0. For example A1 exited 0 (wanted 2) and printed `check-seam: the seam holds (1 libraries in 1 files checked)`.

#### MM5. The recipe names no directory

**Guards:** The recipe names the directory.
**Mutation:**
```
-@$(CHEZ) --program tests/check-seam.sps src
+@$(CHEZ) --program tests/check-seam.sps
```
**Result:** killed by 3 cases: A1, N1, P0. For example P0 exited 2 (wanted 0) and printed `check-seam: usage: scheme --program tests/check-seam.sps DIR`.

#### MM6. The require-tools line deleted

**Guards:** T1: the recipe checks for Chez first.
**Mutation:**
```
-@scripts/require-tools "$(GOAL)" $(CHEZ)
```
**Result:** killed by 1 case: T1. For example T1 printed `make: /nonexistent/scheme: No such file or directory`.

#### MM7. The recipe's verdict thrown away

**Guards:** The recipe's status reaches make.
**Mutation:**
```
-@$(CHEZ) --program tests/check-seam.sps src
+@-$(CHEZ) --program tests/check-seam.sps src
```
**Result:** killed by 2 cases: A1, N1. For example A1 exited 0 (wanted 2) and printed `make: [Makefile:215: check-seam] Error 1 (ignored)`.

#### MM8. The seam plant imports a legal library

**Guards:** The `seam` case plants a real violation.
**Mutation:**
```
-(import (rnrs) (http-client session))
+(import (rnrs) (curl private session))
```
**Result:** `make check-test-fails` exit 2, with these lines:
```
check-test-fails: FAILED seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs: make test exited 0
check-test-fails: FAILED seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs: make test's lines differ
```

#### MM9. The fixture (http-client) library imports a private (curl ...) library

**Guards:** The copy's own `src/` is legal, so that only the planted fault can fail a case.
**Mutation:**
```
-(import (rnrs) (curl))
+(import (rnrs) (curl) (curl private x))
```
**Result:** `make check-test-fails` exit 2, with these lines:
```
check-test-fails: FAILED fails: a failing suite is named FAIL, and the suites after it run: make test's lines differ
check-test-fails: FAILED no-tests: a suite that runs no test is named FAIL, and the suites after it run: make test's lines differ
check-test-fails: FAILED hangs: a suite that never ends is named HUNG, and the suites after it run: make test's lines differ
check-test-fails: FAILED seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs: make test's lines differ
check-test-fails: FAILED no-suites: make test refuses to pass with no suite to run: make test's lines differ
survivors: []
```

#### MM10. The plant suite left in the copy for the seam case

**Guards:** The `seam` case starts from a copy whose plant suite is gone, so that `check-suites` passes and `check-seam` runs.
**Mutation:**
```
-# The plant is gone, so only the after-suite is left to check.
-rm -f "$copy/$plant"
```
**Result:** `make check-test-fails` exit 2, with these lines:
```
check-test-fails: FAILED seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs: make test's lines differ
survivors: []
```

### Clean rerun

After the last change to the program, the Makefile, `tests/check-test-fails.sh` and the cases:

**The worktree** (no `src/`), `scripts/guix-env make check-seam`:

```
check-seam: no libraries: src holds no .sls file, so there is no seam to check
check-seam: FAILED (problems: 1)
make: *** [Makefile:215: check-seam] Error 1
exit status: 2
```

**A copy holding the legal pair,** `scripts/guix-env sh -c 'make test && make check-test-fails'`, the check lines and the tail:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
check-seam: the seam holds (3 libraries in 3 files checked)
test: ran 2, passed 2, failed 0, hung 0
check-test-fails: ok fails: a failing suite is named FAIL, and the suites after it run
check-test-fails: ok no-tests: a suite that runs no test is named FAIL, and the suites after it run
check-test-fails: ok hangs: a suite that never ends is named HUNG, and the suites after it run
check-test-fails: ok exit-line: check-suites names a suite without the shared exit form, and no suite runs
check-test-fails: ok early-exit: check-suites names a suite that exits before its verdict, and no suite runs
check-test-fails: ok nested-exit: check-suites names an exit inside a form before the verdict, and no suite runs
check-test-fails: ok empty: check-suites names a suite with no datum, and no suite runs
check-test-fails: ok seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs
check-test-fails: ok no-suites: make test refuses to pass with no suite to run
check-test-fails: make test failed, as it must, in all 9 cases
exit status: 0
```

**The cases,** layer by layer: `make check-seam` in a fresh copy per case, and the program on every case in one container call:

```
layer 1 (make check-seam in a fresh copy per case)
43 passed, 0 failed
layer 2 (the program on every case, one container call)
42 passed, 0 failed
```

`make check-help` exits 0 with `check-seam` in `.PHONY` and in `make help`.

### Findings

- **The brief's wrappers left out `for`.** R6RS's import sets also include
  `(for <import set> <import level> ...)`. A check that looked through only `only`, `except`,
  `prefix`, `rename` and `library` passes `(import (for (http-client) expand))`. A8 is the case,
  and CM8 the mutant that fails it.
- **`#!r6rs` changes what `read` accepts.** Under it Chez refuses datum labels and `#!eof`. U2 and
  I2 first carried the line, since every library does, and both failed their whole-output
  comparison: the check named the file unreadable, in Chez's words, and never reached the guard
  under test.
  ```
  check-seam: src/curl.sls: it cannot be read as data: Exception in read: #!eof syntax is not allowed in #!r6rs mode before file-position 92 of #<input port src/curl.sls>; the character position might differ
  check-seam: src/curl/i2.sls: it cannot be read as data: Exception in read: #<n>= mark syntax is not allowed in #!r6rs mode before file-position 59 of #<input port src/curl/i2.sls>; the character position might differ
  ```
  Both files now omit the line. In a library that carries it the reader is the stronger fence,
  and the two guards cannot be reached.
- **Chez's loader stops at `#!eof` too.** Measured: a script printing `a`, then `#!eof`, then a form
  printing `b`, printed `a` alone under `scheme --script` and `scheme -q < file`. A library after
  an `#!eof` would never load. The check names the file anyway: a reader that stopped there
  silently would be answering for a file it had not read.
- **`write` of a cyclic datum warns on stderr** (`Warning in write: cycle detected; proceeding with
  (print-graph #t)`) before it prints the labelled datum. I2's first run showed the line ahead of
  the complaint. `written` binds `print-graph` to `#t`.
- ~~**`import` is no body form in Chez 10.4.** In a library, a second `(import (inner-a))` after the
  header, and one inside a `let` body, each fail with `attempt to reference unbound identifier
  import` (a probe loading `(inner-a)`, then each). The header is the only static import to read.~~
  **Corrected 2026-10-16: this is false.** The probe's library imported only `(rnrs)`, which does
  not export `import`, so `import` was unbound in it. `(chezscheme)` exports `import`, and a
  library that imports it, or imports `import` from it, may write `(import ...)` as a body form
  and inside a `let` body. The header is not the only static import to read. A review measured
  it: `(library (curl evil) (export leak) (import (chezscheme)) (import (http-client session))
  ...)` loads, and `leak` returns the `(http-client session)` library's value, while this check
  said `the seam holds`. `(only (chezscheme) import)` does the same. See
  [Review fixes: check-seam and require-threaded](#review-fixes-check-seam-and-require-threaded).
- **CM35 survived the first pass.** `reference-name`'s `list?` guard was reached only by a library's
  own name and by the `library` wrapper: `spec-name` already refuses an improper spec. No case had
  an improper name or `(library (a . b))`. D9's second file and I1's `(library (http-client . y))`
  now fail it.
- **`check-suites` stops `make test` before `check-seam` runs,** and the `empty` case of
  `check-test-fails` leaves an empty `tests/test-0-plant.sps` behind. The `seam` case removes it
  first (MM10 leaves it, and the case then reads `check-suites`' complaint instead of the seam's).
- **Chez resolves a library through five extensions:** `(library-extensions)` is `.chezscheme.sls`,
  `.ss`, `.sls`, `.scm` and `.sch`. The check reads `.sls` only, as the brief says, and N3 shows a
  `src/curl.scm` ignored. See Not covered.

### Not covered

- **Libraries in other files Chez would load.** A library at `src/http-client/x.ss`, `.scm` or
  `.sch` is found by Chez's search and read by nothing here. `.chezscheme.sls` ends in `.sls` and is read.
  *Closed 2026-10-16: the review fixes name these files, and the compiled `.so` ones.*
- **A third family.** Only direct imports are held to the rules, and a library whose name starts
  with neither `curl` nor `http-client` is held to none. Measured, with no case: `(curl x)` importing
  `(util)`, which imports `(http-client)`, gives `check-seam: the seam holds (2 libraries in 2 files
  checked)` and exit 0. P3 shows the same property from the other side.
  *Closed 2026-10-16: every library under `src/` must belong to a family, and P3 became F2.*
- **Imports made at run time:** `eval` over an `environment`, `load`, and files an `include` pulls in.
  *Closed 2026-10-16 for the names that reach them: rule (c) of the review fixes.*
- **A library's declared name against its path.** A file is judged by the name it declares, and the
  check does not look at where the file is.
- **Measured once, with no case.** A link to a regular `.sls` file is read, and a violation behind
  it is named. `src` as a link to a directory is followed. A byte order mark before the library
  reads fine. An editor's lock file, Emacs's `.#x.sls`, a dangling link, is named as unreadable:
  ```
  check-seam: src/curl/.#x.sls: it cannot be read as data: Exception in open-file-input-port: failed for src/curl/.#x.sls: no such file or directory
  ```
  *Closed 2026-10-16 for the lock file: a name starting with `.#` is skipped (cases K1 to K3).*
- **The `seam` case plants rule (a) only.** Rule (b) and the fail-closed rules reach `make test`
  through the same exit status, and are checked here through `make check-seam`.
- **`check-test-fails`' own `src/`.** The copy holds two stub libraries. If `make test` starts to
  build or load `src/`, the stubs must satisfy it.
- **The real `src/`.** This tree has none. The first real run is after the libraries land.
- **Other platforms.** Every run was Linux, amd64, in the container. macOS and arm64 were not run;
  `directory-list` and `file-directory?` with its link argument are Chez's own.


## The native layer

Evidence that the checks M0 slice 3's third step added fail through the property each claims
to guard ([ADR-0001](decisions/0001-bind-libcurl-directly.md),
[ADR-0002](decisions/0002-runtime-libcurl-discovery.md),
[ADR-0003](decisions/0003-libcurl-floor-7-85.md), [global constraints](global-constraints.md),
"Loading libcurl"). The step is the native layer and what reaches it:

- `src/curl/private/native.sls`, `(curl private native)`: the load, as definitions in the order
  they run;
- `src/curl.sls`, `(curl)`, the first public library;
- `curlh-header` in `src/curl/private/constants.sls`;
- `tests/refusal-probe.sps`, the probe, and `tests/preflight.sps`, which `make build` runs;
- `tests/decoy-libcurl.c`, a stand-in libcurl compiled per case at test time;
- `tests/test-library-loading.sps`, the suite;
- `export CHEZ` and the `build` target in the `Makefile`;
- `(curl)` and `(curl private native)` in `tests/test-require-threaded.sps`'s liveness row.

A driver in the session scratchpad ran every mutation, as in the first part. It froze a snapshot
of the working tree, without `.git`, `build/` or `.claude/`, and gave each mutation a fresh copy
of it. It applied the mutation by exact-text replacement, aborting unless each target occurred
exactly once, and it refused a mutation that changed nothing. It touched the copy's
`manifest.scm` and ran `scripts/guix-env sh -c '<command>'` from inside the copy, four copies at
a time. The command was `make test` unless the case says otherwise. A mutation counts as killed
only when the command exits non-zero and every expected line appears whole in its output: the
suite's `FAIL <test name>` lines and `make test`'s `test: FAIL <suite>` line, or, for a Makefile
mutant, `check-help`'s own line or Chez's exception. Each output was kept verbatim. The working
tree was never edited.

**Result** quotes each `FAIL` line, with the expected and actual values of the first three, then
the `Exception`, `check-help` and `test:` lines. Lines are not cut: a decoy's call log ends the
line, and is often the difference. Two long paths are shortened. `$T` is the suite's `mktemp -d`
directory, a fresh `/tmp/tmp.XXXXXXXXXX` in each run. `$P` is the container's profile,
`/gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile`.

Cases are named `NL` (the native layer), `CN` (constants), `CU` (`(curl)`), `RC` (the first
part's checker, rerun), `PR` (the probe), `PF` (the preflight), `TS` (the suite and the decoy),
`MK` (the Makefile) and `ST` (the environment, with no change to the tree).

### Measured first: a guard in a program cannot catch a raise from an imported library's body

The brief asked for this before the probe was written. `(raiser)` exports `v`, defined as
`(raise 'boom)`, and `f`, which returns `v`. Three programs, run with Chez 10.4.0 in the
container:

```scheme
;; p1: imports (raiser), and calls f inside a guard
(import (rnrs) (raiser))
(display "body starts\n")
(guard (e (#t (display "caught ") (write e) (newline) (exit 3)))
  (display (f)))

;; p2: imports no (raiser), and evaluates (f) in its environment inside the guard
(import (rnrs) (only (chezscheme) eval environment))
(display "body starts\n")
(guard (e (#t (display "caught ") (write e) (newline) (exit 3)))
  (display (eval '(f) (environment '(raiser)))))

;; p3: as p1, with the call to f inside a procedure the guard calls
```

```
== p1
Exception occurred with non-condition value boom
exit 255
== p2
body starts
caught boom
exit 3
== p3
Exception occurred with non-condition value boom
exit 255
```

In p1 and p3, `body starts` never prints: Chez runs `(raiser)`'s body before the program's own,
because the program references one of its bindings. No guard in the body can catch that raise.
So `tests/refusal-probe.sps` and `tests/preflight.sps` import no `(curl)`. Each evaluates
`(loaded-libcurl)` in `(environment '(rnrs) '(curl))` inside its guard, as p2 does. PR1 and PF3
put the plain import back, and every refusal then escapes, exit 255.

### Red run, before the code existed

The suite, the probe, the preflight, the decoy, the `Makefile` changes and the liveness row were
written first. There was no `native.sls` and no `curl.sls`. `make test` exited 2:

- **`test-library-loading`:** 5 passed, 28 failed. Every probe and preflight run got
  `Exception in environment: library (curl) not found`, as `(raised . "…")` from the probe, exit
  2, or on stderr from the preflight, exit 255. Each decoy compiled, exit 0:

  ```
  FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
    expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
    actual:   (0 2 ((raised . "Exception in environment: library (curl) not found")) "")
  FAIL (curl) exports loaded-libcurl, the info record's accessors and the conditions
    actual:   (not-expanded "Exception in environment: library (curl) not found")
  # of expected passes      5
  # of unexpected failures  28
  test: FAIL tests/test-library-loading.sps (exit 1)
  ```

  The five that passed check the suite's own setup, which no library code can fail: `CHEZ` is
  set, `mktemp -d` made a directory, `CHEZ_CURL_LIBCURL` is absolute, this process never loaded
  libcurl, and the scratch directory is removed. MK2, TS4, ST1, TS3 and TS2 fail them.
- **`test-require-threaded`:** 17 passed, and the liveness row failed:

  ```
  FAIL the scan read src/: (curl), conditions, constants, discovery, native and verify
    expected: (read read read read read read)
    actual:   (missed read read read missed read)
  test: FAIL tests/test-require-threaded.sps (exit 1)
  test: ran 7, passed 5, failed 2, hung 0
  ```

- **`make build`:** `Exception in environment: library (curl) not found`, and make exited 2.

The first run with the code was red too, for a reason worth keeping: see Findings, on
`environment`.

### Baseline

On the working tree as the snapshot froze it (sha256 of its files, the submodule aside,
`082aa1ecc6577121188478391b0a873abf1d52092c4fe83a7fddb8df7fb6fd68`), each in a fresh copy:

- **`make test`** exited 0:

  ```
  check-suites: every suite ends with (exit (suite-exit-status runner)) (7 checked)
  check-seam: the seam holds (7 libraries in 7 files checked)
  test: pass tests/test-conditions.sps
  test: pass tests/test-curl-testing.sps
  test: pass tests/test-discovery.sps
  # of expected passes      33
  test: pass tests/test-library-loading.sps
  test: pass tests/test-manifest.sps
  # of expected passes      20
  test: pass tests/test-require-threaded.sps
  test: pass tests/test-verify.sps
  test: ran 7, passed 7, failed 0, hung 0
  ```

- **`env -u CHEZ make test`**, MK2's command, exited 0 with the same last line. With `CHEZ` gone
  from the environment, make's `CHEZ ?= scheme` is exported, and `env` finds `scheme` on the
  container's `PATH`.
- **`make build`** exited 0:

  ```
  chez-curl: libcurl loaded and accepted
    path:     $P/lib/libcurl.so.4 (override)
    version:  8.20.0
    TLS:      GnuTLS/3.8.13
    features: ipv6 ssl libz asynchdns spnego largefile idn tlsauth-srp http2 gssapi kerberos5 unix-sockets psl https-proxy altsvc zstd hsts threadsafe
    host:     x86_64-unknown-linux-gnu
  ```

- **`make check-test-fails`** exited 0, ending `check-test-fails: make test failed, as it must,
  in all 9 cases`.

65 mutations ran. 64 were killed, each with every expected line present. One survived, as it was
expected to: NL33, a field after the last one read (see Not covered). Every one of the 33 tests
in `test-library-loading`, the changed liveness row and the two new import-order rows was failed
by name by at least one mutant. Coverage, at the end, lists which. Step 1's CN6, CN7 and CN8,
which survived there, are killed here, and so is RC9.

### The load order

#### NL1. curl_global_init before the version check

**Guards:** check-version runs before curl_global_init, so a refused library is never initialised.
**Mutation:** In `src/curl/private/native.sls`, `version-checked` moved from before `curl-global-init` to after `global-initialized`:

```diff
@@
  
-   (define version-checked
-     (check-version (libcurl-info-version info) (libcurl-info-version-number info)
-                    (libcurl-info-features info) libcurl-path libcurl-source))
  
@@
        #t))
+   (define version-checked
+     (check-version (libcurl-info-version info) (libcurl-info-version-number info)
+                    (libcurl-info-features info) libcurl-path libcurl-source))
  
```
**Result:** killed, exit 2:

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL2. The options probe before check-version

**Guards:** no probe runs before the floor and SSL are checked.
**Mutation:** In `src/curl/private/native.sls`, `curl-easy-option-by-name` and `option-found?` moved from steps 6 and 7 to just after `info`, ahead of `version-checked`:

```diff
@@
         (c-string (ftype-ref curl-version-info-data (host) version-data)))))
+   (define curl-easy-option-by-name
+     (bind-required "curl_easy_option_by_name" (string) uptr))
+   (define option-found?
+     (not (zero? (curl-easy-option-by-name "URL"))))
  
@@
    ;; const struct curl_easyoption *curl_easy_option_by_name(const char *name)
-   (define curl-easy-option-by-name
-     (bind-required "curl_easy_option_by_name" (string) uptr))
  
@@
    ;; check-apis refuses anything else, since NULL as 0 would be true.
-   (define option-found?
-     (not (zero? (curl-easy-option-by-name "URL"))))
  
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_global_init(3) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_global_init(3) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9) curl_easy_option_by_name(URL)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL3. curl_global_init called twice

**Guards:** curl_global_init runs exactly once.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (let ((code (curl-global-init curl-global-default)))
+     (let ((code (begin (curl-global-init curl-global-default)
+                        (curl-global-init curl-global-default))))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
  expected: (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_global_init(3)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL4. The probes before curl_global_init

**Guards:** curl_global_init runs before the API probes.
**Mutation:** In `src/curl/private/native.sls`, step 5, `curl-global-init` and `global-initialized`, moved from before step 6 to after `header-code`:

```diff
@@
  
-   ;; --- 5. curl_global_init, exactly once ---------------------------------------------
- 
-   ;; CURLcode curl_global_init(long flags)
-   (define curl-global-init (bind-required "curl_global_init" (long) int))
- 
-   (define global-initialized
-     (let ((code (curl-global-init curl-global-default)))
-       (unless (= code curle-ok)
-         (refuse 'load-failed libcurl-path libcurl-source
-                 (string-append "curl_global_init returned " (number->string code))
-                 "curl_global_init failed, so this libcurl cannot be used; name another with CHEZ_CURL_LIBCURL"))
-       #t))
  
@@
          code)))
+   ;; --- 5. curl_global_init, exactly once ---------------------------------------------
+ 
+   ;; CURLcode curl_global_init(long flags)
+   (define curl-global-init (bind-required "curl_global_init" (long) int))
+ 
+   (define global-initialized
+     (let ((code (curl-global-init curl-global-default)))
+       (unless (= code curle-ok)
+         (refuse 'load-failed libcurl-path libcurl-source
+                 (string-append "curl_global_init returned " (number->string code))
+                 "curl_global_init failed, so this libcurl cannot be used; name another with CHEZ_CURL_LIBCURL"))
+       #t))
  
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_global_init(3)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_global_init(3)")) "")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
  expected: (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_global_init(3)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### `foreign-entry?` before every required binding

#### NL5. The foreign-entry? check deleted

**Guards:** every required entry point is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (unless (foreign-entry? name)
-       (refuse 'missing-api libcurl-path libcurl-source name
-               (string-append "the library has no " name
-                              ", so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL"))))
+     #t)
```
**Result:** killed, exit 2:

```
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
  expected: (0 1 ((reason . missing-api) (path . "$T/not-curl.so") (source . override) (detail . "curl_version_info") (candidates) (calls . "")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_version_info\"") (calls . "")) "")
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_global_init.so") (source . override) (detail . "curl_global_init") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_global_init\"") (calls . "curl_version_info(9)")) "")
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_option_by_name.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_option_by_name\"") (calls . "curl_version_info(9) curl_global_init(3)")) "")
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL6. curl_version_info bound without the check

**Guards:** curl_version_info is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define curl-version-info (bind-required "curl_version_info" (int) uptr))
+   (define curl-version-info (foreign-procedure "curl_version_info" (int) uptr))
```
**Result:** killed, exit 2:

```
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
  expected: (0 1 ((reason . missing-api) (path . "$T/not-curl.so") (source . override) (detail . "curl_version_info") (candidates) (calls . "")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_version_info\"") (calls . "")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL7. curl_global_init bound without the check

**Guards:** curl_global_init is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define curl-global-init (bind-required "curl_global_init" (long) int))
+   (define curl-global-init (foreign-procedure "curl_global_init" (long) int))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_global_init.so") (source . override) (detail . "curl_global_init") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_global_init\"") (calls . "curl_version_info(9)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL8. curl_easy_option_by_name bound without the check

**Guards:** curl_easy_option_by_name is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (bind-required "curl_easy_option_by_name" (string) uptr))
+     (foreign-procedure "curl_easy_option_by_name" (string) uptr))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_option_by_name.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_option_by_name\"") (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL9. curl_easy_init bound without the check

**Guards:** curl_easy_init is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define curl-easy-init (bind-required "curl_easy_init" () uptr))
+   (define curl-easy-init (foreign-procedure "curl_easy_init" () uptr))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_init.so") (source . override) (detail . "curl_easy_init") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_init\"") (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL10. curl_easy_header bound without the check

**Guards:** curl_easy_header is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (bind-required "curl_easy_header" (uptr string size_t unsigned-int int uptr) int))
+     (foreign-procedure "curl_easy_header" (uptr string size_t unsigned-int int uptr) int))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_header.so") (source . override) (detail . "curl_easy_header") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_header\"") (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL11. curl_easy_cleanup bound without the check

**Guards:** curl_easy_cleanup is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define curl-easy-cleanup (bind-required "curl_easy_cleanup" (uptr) void))
+   (define curl-easy-cleanup (foreign-procedure "curl_easy_cleanup" (uptr) void))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_cleanup.so") (source . override) (detail . "curl_easy_cleanup") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_cleanup\"") (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### The probes and `check-apis`

#### NL12. The option probe passes the pointer, not a boolean

**Guards:** check-apis gets a boolean: NULL as 0 would be true.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (not (zero? (curl-easy-option-by-name "URL"))))
+     (curl-easy-option-by-name "URL"))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception in check-apis: the option probe's answer is not a boolean with irritant 124310222126528") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception in check-apis: the option probe's answer is not a boolean with irritant 135356877069760") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception in check-apis: the option probe's answer is not a boolean with irritant 0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL the real libcurl through the override: loaded, as curl --version names it
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with curl --version's version and TLS
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL13. check-apis never called

**Guards:** the probes' answers are checked.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (check-apis option-found? header-code libcurl-path libcurl-source))
+     #t)
```
**Result:** killed, exit 2:

```
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/options-off.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  expected: (0 1 ((reason . missing-api) (path . "$T/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/headers-off.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL14. check-version never called

**Guards:** the version and features are checked.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (check-version (libcurl-info-version info) (libcurl-info-version-number info)
-                    (libcurl-info-features info) libcurl-path libcurl-source))
+     #t)
```
**Result:** killed, exit 2:

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 0 ((loaded . "$T/below-floor.so") (source . override) (version . "7.84.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 0 ((loaded . "$T/no-ssl.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL15. The option probe asks for url

**Guards:** the options probe asks for the name URL, which every libcurl knows.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (not (zero? (curl-easy-option-by-name "URL"))))
+     (not (zero? (curl-easy-option-by-name "url"))))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/accepted.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(url) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/ssl-null.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(url) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(url) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL16. The header probe asks for origin 0

**Guards:** the header probe passes CURLH_HEADER.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-              (code (curl-easy-header easy "Content-Type" 0 curlh-header -1 hout)))
+              (code (curl-easy-header easy "Content-Type" 0 0 -1 hout)))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,0,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,0,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,0,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL17. The header probe passes NULL for hout

**Guards:** the header probe passes a slot for hout.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-              (code (curl-easy-header easy "Content-Type" 0 curlh-header -1 hout)))
+              (code (curl-easy-header easy "Content-Type" 0 curlh-header -1 0)))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,NULL) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,NULL) curl_easy_cleanup(handle)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,NULL) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL18. The header probe asks for request 0

**Guards:** the header probe asks for the most recent request, -1.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-              (code (curl-easy-header easy "Content-Type" 0 curlh-header -1 hout)))
+              (code (curl-easy-header easy "Content-Type" 0 curlh-header 0 hout)))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,0,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,0,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,0,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL19. The probe handle never cleaned up

**Guards:** the probe's easy handle is cleaned up.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-         (curl-easy-cleanup easy)
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL20. Another handle cleaned up

**Guards:** curl_easy_cleanup gets the handle the probe made.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-         (curl-easy-cleanup easy)
+         (curl-easy-cleanup 0)
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(other)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(other)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(other)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL21. curl_easy_init's NULL taken

**Guards:** a NULL from curl_easy_init is load-failed, and curl_easy_header never gets it.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-       (when (zero? easy)
+       (when #f
```
**Result:** killed, exit 2:

```
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
  expected: (0 1 ((reason . load-failed) (path . "$T/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init()")) "")
  actual:   (0 0 ((loaded . "$T/easy-init-null.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(other,Content-Type,0,1,-1,hout) curl_easy_cleanup(other)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL22. curl_version_info's NULL read

**Guards:** a NULL from curl_version_info is load-failed, never dereferenced.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-       (when (zero? address)
+       (when #f
```
**Result:** killed, exit 2:

```
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
  expected: (0 1 ((reason . load-failed) (path . "$T/version-info-null.so") (source . override) (detail . "curl_version_info returned NULL") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception: invalid memory reference.  Some debugging context lost") (calls . "curl_version_info(9)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### `curl_global_init`

#### NL23. curl_global_init's answer ignored

**Guards:** a non-zero curl_global_init is load-failed.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-       (unless (= code curle-ok)
+       (unless #t
```
**Result:** killed, exit 2:

```
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
  expected: (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 0 ((loaded . "$T/init-fails.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL24. curl_global_init's refusal does not name the code

**Guards:** the detail is "curl_global_init returned <code>".
**Mutation:** In `src/curl/private/native.sls`:

```diff
-                 (string-append "curl_global_init returned " (number->string code))
+                 "curl_global_init failed"
```
**Result:** killed, exit 2:

```
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
  expected: (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init failed") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### The load, once, and discovery's inputs

#### NL25. A failed load falls back to the next candidate

**Guards:** after a failed load no other candidate is tried (ADR-0002, decision 3). Only discovery's choice falls back here; the override still refuses.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (guard (e (#t (refuse 'load-failed libcurl-path libcurl-source (loader-message e)
-                           "the loader refused this libcurl; name one this Chez can load with CHEZ_CURL_LIBCURL, an absolute path")))
+     (guard (e (#t (if (eq? libcurl-source 'override)
+                       (refuse 'load-failed libcurl-path libcurl-source (loader-message e)
+                               "the loader refused this libcurl; name one this Chez can load with CHEZ_CURL_LIBCURL, an absolute path")
+                       (let ((failed libcurl-path))
+                         (let-values (((path source)
+                                       (choose-libcurl getenv (machine-type) (maps-text)
+                                                       (lambda (p) (and (not (string=? p failed))
+                                                                        (regular-file? p))))))
+                           (set! libcurl-path path)
+                           (set! libcurl-source source)
+                           (load-shared-object path)
+                           #t)))))
```
**Result:** killed, exit 2:

```
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
  expected: (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . guix-environment) (detail . "(while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short") (candidates)) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-profile) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL26. The loader's raise escapes

**Guards:** a failed load is load-failed, never Chez's raw loader error.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (guard (e (#t (refuse 'load-failed libcurl-path libcurl-source (loader-message e)
-                           "the loader refused this libcurl; name one this Chez can load with CHEZ_CURL_LIBCURL, an absolute path")))
+     (begin
```
**Result:** killed, exit 2:

```
FAIL a text file is load-failed, with the loader's message
  expected: (1 ((reason . load-failed) (path . "$T/not-a-library.so") (source . override) (detail . "(while loading $T/not-a-library.so) $T/not-a-library.so: file too short") (candidates)) "")
  actual:   (2 ((raised . "Exception: (while loading $T/not-a-library.so) $T/not-a-library.so: file too short")) "")
FAIL a path that does not exist is load-failed, with the loader's message
  expected: (1 ((reason . load-failed) (path . "$T/no-such-dir/libcurl.so.4") (source . override) (detail . "(while loading $T/no-such-dir/libcurl.so.4) $T/no-such-dir/libcurl.so.4: cannot open shared object file: No such file or directory") (candidates)) "")
  actual:   (2 ((raised . "Exception: (while loading $T/no-such-dir/libcurl.so.4) $T/no-such-dir/libcurl.so.4: cannot open shared object file: No such file or directory")) "")
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
  expected: (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . guix-environment) (detail . "(while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short") (candidates)) "")
  actual:   (2 ((raised . "Exception: (while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL27. load-failed carries the path as its detail

**Guards:** load-failed's detail is the loader's own message.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (guard (e (#t (refuse 'load-failed libcurl-path libcurl-source (loader-message e)
+     (guard (e (#t (refuse 'load-failed libcurl-path libcurl-source libcurl-path
```
**Result:** killed, exit 2:

```
FAIL a text file is load-failed, with the loader's message
  expected: (1 ((reason . load-failed) (path . "$T/not-a-library.so") (source . override) (detail . "(while loading $T/not-a-library.so) $T/not-a-library.so: file too short") (candidates)) "")
  actual:   (1 ((reason . load-failed) (path . "$T/not-a-library.so") (source . override) (detail . "$T/not-a-library.so") (candidates)) "")
FAIL a path that does not exist is load-failed, with the loader's message
  expected: (1 ((reason . load-failed) (path . "$T/no-such-dir/libcurl.so.4") (source . override) (detail . "(while loading $T/no-such-dir/libcurl.so.4) $T/no-such-dir/libcurl.so.4: cannot open shared object file: No such file or directory") (candidates)) "")
  actual:   (1 ((reason . load-failed) (path . "$T/no-such-dir/libcurl.so.4") (source . override) (detail . "$T/no-such-dir/libcurl.so.4") (candidates)) "")
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
  expected: (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . guix-environment) (detail . "(while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short") (candidates)) "")
  actual:   (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . guix-environment) (detail . "$T/broken-profile/lib/libcurl.so.4") (candidates)) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL28. The maps never read

**Guards:** discovery gets /proc/self/maps, so it sees the Guix world.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (and (linux-machine? (machine-type))
+     (and #f
```
**Result:** killed, exit 2:

```
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
  expected: (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
  actual:   (1 ((reason . not-found) (path . #f) (source . #f) (detail . #f) (candidates "/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) "")
FAIL guix: with no profile to search, not-found lists every candidate checked
  expected: (1 ((reason . not-found) (path . #f) (source . #f) (detail . #f) (candidates "$T/home/.guix-home/profile/lib/libcurl.so.4" "$T/home/.guix-profile/lib/libcurl.so.4" "/run/current-system/profile/lib/libcurl.so.4")) "")
  actual:   (1 ((reason . not-found) (path . #f) (source . #f) (detail . #f) (candidates "/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) "")
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
  expected: (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . guix-environment) (detail . "(while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short") (candidates)) "")
  actual:   (1 ((reason . not-found) (path . #f) (source . #f) (detail . #f) (candidates "/usr/local/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl.so.4" "/usr/lib64/libcurl.so.4" "/usr/lib/libcurl.so.4" "/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4")) "")
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL29. Symlinks not followed

**Guards:** the existence check follows symlinks: Guix's libcurl.so.4 is one.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-       (file-regular? path)))
+       (file-regular? path #f)))
```
**Result:** killed, exit 2:

```
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
  expected: (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
  actual:   (1 ((reason . not-found) (path . #f) (source . #f) (detail . #f) (candidates "$P/lib/libcurl.so.4" "/home/kishu/.guix-home/profile/lib/libcurl.so.4" "/home/kishu/.guix-profile/lib/libcurl.so.4" "/run/current-system/profile/lib/libcurl.so.4")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL30. The source reported as override

**Guards:** the report carries the source discovery named.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define libcurl-source (cdr chosen))
+   (define libcurl-source 'override)
```
**Result:** killed, exit 2:

```
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
  expected: (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . override) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
  expected: (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . guix-environment) (detail . "(while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short") (candidates)) "")
  actual:   (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . override) (detail . "(while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short") (candidates)) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### Reading `curl_version_info_data`

#### NL31. A NULL string read as ""

**Guards:** a NULL ssl_version is #f, never the empty string.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (and (not (zero? address))
+     (if (zero? address) ""
```
**Result:** killed, exit 2:

```
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . "") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL32. host and ssl_version swapped in the ftype

**Guards:** the ftype follows the header's field order.
**Mutation:** In `src/curl/private/native.sls`:

```diff
+       (ssl-version uptr)
+       (features unsigned-int)
-       (features unsigned-int)
-       (ssl-version uptr)
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "decoy-host") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . "decoy-host") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL the real libcurl through the override: loaded, as curl --version names it
  expected: (0 ((loaded . "$P/lib/libcurl.so.4") (source . override) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . override) (version . "8.20.0") (ssl-version . "x86_64-unknown-linux-gnu")) "")
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with curl --version's version and TLS
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL33. ssl_version_num dropped from the ftype

**Guards:** nothing yet: every field after ssl_version is unread, and slice 4 checks the layout.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-       (ssl-version-num long)
```
**Result:** survived, as expected: exit 0, and `make test` printed `test: ran 7, passed 7, failed 0, hung 0`.

#### NL34. The features read from version_num

**Guards:** the features word is the features field.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (let ((features (ftype-ref curl-version-info-data (features) version-data)))
+     (let ((features (ftype-ref curl-version-info-data (version-num) version-data)))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/accepted.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/ssl-null.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9)")) "")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
  expected: (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/init-fails.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl through the override: loaded, as curl --version names it
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with curl --version's version and TLS
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL35. The record built with ssl_version and host swapped

**Guards:** each report field is read from its own struct field.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-        (c-string (ftype-ref curl-version-info-data (ssl-version) version-data))
-        (c-string (ftype-ref curl-version-info-data (host) version-data)))))
+        (c-string (ftype-ref curl-version-info-data (host) version-data))
+        (c-string (ftype-ref curl-version-info-data (ssl-version) version-data)))))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "decoy-host") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . "decoy-host") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL the real libcurl through the override: loaded, as curl --version names it
  expected: (0 ((loaded . "$P/lib/libcurl.so.4") (source . override) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . override) (version . "8.20.0") (ssl-version . "x86_64-unknown-linux-gnu")) "")
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with curl --version's version and TLS
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### The constants

#### CN9. CURLH_HEADER as 2

**Guards:** curlh-header is curl/header.h's CURLH_HEADER, (1 << 0).
**Mutation:** In `src/curl/private/constants.sls`:

```diff
-   (define curlh-header 1)
+   (define curlh-header 2)
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,2,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,2,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,2,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### CN6. `CURLE_OK` as 1 (rerun)

**Guards:** curle-ok is CURLE_OK, 0.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
-   (define curle-ok 0)
+   (define curle-ok 1)
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/accepted.so") (source . override) (detail . "curl_global_init returned 0") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/ssl-null.so") (source . override) (detail . "curl_global_init returned 0") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/options-off.so") (source . override) (detail . "curl_global_init returned 0") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl through the override: loaded, as curl --version names it
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with curl --version's version and TLS
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### CN7. `CURL_GLOBAL_DEFAULT` as 0 (rerun)

**Guards:** curl-global-default is CURL_GLOBAL_DEFAULT, 3.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
-   (define curl-global-default 3)
+   (define curl-global-default 0)
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(0) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(0) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
  expected: (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (calls . "curl_version_info(9) curl_global_init(0)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### CN8. `CURLVERSION_TENTH` as 11 (rerun)

**Guards:** curlversion-tenth is CURLVERSION_TENTH, 9.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
-   (define curlversion-tenth 9))
+   (define curlversion-tenth 11))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(11) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(11) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(11)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### `(curl)` and the refusal's rows

#### CU1. libcurl-info-host not exported

**Guards:** (curl) exports every accessor of the report.
**Mutation:** In `src/curl.sls`:

```diff
-    libcurl-info-ssl-version libcurl-info-host
+    libcurl-info-ssl-version
```
**Result:** killed, exit 2:

```
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  expected: (0 "chez-curl: libcurl loaded and accepted\n  path:     $T/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")
  actual:   (255 "" "Exception: attempt to reference unbound identifier libcurl-info-host\n")
FAIL preflight, the real libcurl: exit 0, with curl --version's version and TLS
  expected: (0 "  version:  8.20.0" "  TLS:      GnuTLS/3.8.13")
  actual:   (255 absent absent)
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n")
  actual:   (255 "" "Exception: attempt to reference unbound identifier libcurl-info-host\n")
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
FAIL (curl) exports loaded-libcurl, the info record's accessors and the conditions
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### CU2. (curl) defines its own curl-error?

**Guards:** (curl) re-exports the conditions; it never redefines one.
**Mutation:** In `src/curl.sls`:

```diff
-           (curl private conditions)
-           (curl private native)))
+           (except (curl private conditions) curl-error?)
+           (curl private native))
+   (define (curl-error? x) (error? x)))
```
**Result:** killed, exit 2:

```
FAIL (curl)'s conditions are (curl private conditions)'s own
  expected: (same same same same same same same same same same same same same same same)
  actual:   (different same same same same same same same same same same same same same same)
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### CU3. (curl) imports the refusal second

**Guards:** (curl) imports (curl private require-threaded) first (ADR-0001).
**Mutation:** In `src/curl.sls`:

```diff
-   (import (curl private require-threaded)
-           (rnrs)
+   (import (rnrs)
+           (curl private require-threaded)
```
**Result:** killed, exit 2:

```
FAIL src/curl.sls imports (curl private require-threaded) first
  expected: first
  actual:   not-first
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### NL36. native.sls imports the refusal second

**Guards:** native.sls imports (curl private require-threaded) first (ADR-0001).
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (import (curl private require-threaded)
-           (rnrs)
+   (import (rnrs)
+           (curl private require-threaded)
```
**Result:** killed, exit 2:

```
FAIL src/curl/private/native.sls imports (curl private require-threaded) first
  expected: first
  actual:   not-first
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### RC9. The scan rooted at src/curl/private (rerun)

**Guards:** the scan root is src/ itself; (curl) lies outside src/curl/private.
**Mutation:** In `tests/test-require-threaded.sps`:

```diff
-   (map (lambda (path) (cons path (first-datum path))) (sls-files "src")))
+   (map (lambda (path) (cons path (first-datum path))) (sls-files "src/curl/private")))
```
**Result:** killed, exit 2:

```
FAIL the scan read src/: (curl), conditions, constants, discovery, native and verify
  expected: (read read read read read read)
  actual:   (missed read read read read read)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### The probe

#### PR1. The probe imports (curl), and its guard comes too late

**Guards:** the probe forces (curl)'s body inside its guard, so a refusal is printed, never escapes.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
-         (curl private conditions))
+         (curl private conditions)
+         (curl))
-     (let ((report (eval '(let ((info (loaded-libcurl)))
+     (let ((report (let ((info (loaded-libcurl)))
-                                  (libcurl-info-ssl-version info)))
-                         (environment '(rnrs) '(curl)))))
+                                  (libcurl-info-ssl-version info)))))
```
**Result:** killed, exit 2:

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 255 () "Exception in chez-curl: libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL with irritant \"$T/below-floor.so\"\n")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 255 () "Exception in chez-curl: libcurl 7.85.0 was built without SSL; name another with CHEZ_CURL_LIBCURL with irritant \"$T/no-ssl.so\"\n")
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
  expected: (0 1 ((reason . load-failed) (path . "$T/version-info-null.so") (source . override) (detail . "curl_version_info returned NULL") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 255 () "Exception in chez-curl: curl_version_info returned NULL, so this libcurl cannot say what it is; name another with CHEZ_CURL_LIBCURL with irritant \"$T/version-info-null.so\"\n")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### PR2. The probe catches a refusal as any other raise

**Guards:** a refusal prints its reason and fields.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
-   (guard (e ((curl-library-unavailable? e)
+   (guard (e ((and #f (curl-library-unavailable? e))
```
**Result:** killed, exit 2:

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in chez-curl: libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL with irritant \"$T/below-floor.so\"") (calls . "curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in chez-curl: libcurl 7.85.0 was built without SSL; name another with CHEZ_CURL_LIBCURL with irritant \"$T/no-ssl.so\"") (calls . "curl_version_info(9)")) "")
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
  expected: (0 1 ((reason . load-failed) (path . "$T/version-info-null.so") (source . override) (detail . "curl_version_info returned NULL") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in chez-curl: curl_version_info returned NULL, so this libcurl cannot say what it is; name another with CHEZ_CURL_LIBCURL with irritant \"$T/version-info-null.so\"") (calls . "curl_version_info(9)")) "")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### PR3. The probe exits 0 after a refusal

**Guards:** the probe exits 1 after a refusal.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
-              1)
+              0)
```
**Result:** killed, exit 2:

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 0 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 0 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (calls . "curl_version_info(9)")) "")
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
  expected: (0 1 ((reason . load-failed) (path . "$T/version-info-null.so") (source . override) (detail . "curl_version_info returned NULL") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 0 ((reason . load-failed) (path . "$T/version-info-null.so") (source . override) (detail . "curl_version_info returned NULL") (candidates) (calls . "curl_version_info(9)")) "")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### PR4. The probe never prints the call log

**Guards:** the probe prints a decoy's call log.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
- (when (foreign-entry? "decoy_calls")
+ (when #f
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f)) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates)) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### The preflight

#### PF1. The preflight exits 0 after a refusal

**Guards:** make build fails when libcurl is refused.
**Mutation:** In `tests/preflight.sps`:

```diff
-              (exit 1))))
+              (exit 0))))
```
**Result:** killed, exit 2:

```
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n")
  actual:   (0 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n")
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
  expected: (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
  actual:   (0 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### PF2. The preflight exits 1 after a load

**Guards:** make build passes when libcurl is accepted.
**Mutation:** In `tests/preflight.sps`:

```diff
-     (exit 0)))
+     (exit 1)))
```
**Result:** killed, exit 2:

```
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  expected: (0 "chez-curl: libcurl loaded and accepted\n  path:     $T/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")
  actual:   (1 "chez-curl: libcurl loaded and accepted\n  path:     $T/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")
FAIL preflight, the real libcurl: exit 0, with curl --version's version and TLS
  expected: (0 "  version:  8.20.0" "  TLS:      GnuTLS/3.8.13")
  actual:   (1 "  version:  8.20.0" "  TLS:      GnuTLS/3.8.13")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### PF3. The preflight's guard comes too late

**Guards:** the preflight forces (curl)'s body inside its guard, so a refusal gets its reason and remedy.
**Mutation:** In `tests/preflight.sps`:

```diff
-         (curl private conditions))
+         (curl private conditions)
+         (curl))
-   (let ((report (eval '(let ((info (loaded-libcurl)))
+   (let ((report (let ((info (loaded-libcurl)))
-                                (libcurl-info-host info)))
-                       (environment '(rnrs) '(curl))))
+                                (libcurl-info-host info))))
```
**Result:** killed, exit 2:

```
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n")
  actual:   (255 "" "Exception in chez-curl: CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for with irritant \"libcurl.so.4\"\n")
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
  expected: (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
  actual:   (255 "" "Exception in chez-curl: no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path with irritant (\"$T/home/.guix-home/profile/lib/libcurl.so.4\" \"$T/home/.guix-profile/lib/libcurl.so.4\" \"/run/current-system/profile/lib/libcurl.so.4\")\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### PF4. The refusal on stdout

**Guards:** a refusal goes to stderr, the report to stdout.
**Mutation:** In `tests/preflight.sps`:

```diff
-            (let ((err (current-error-port))
+            (let ((err (current-output-port))
```
**Result:** killed, exit 2:

```
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n")
  actual:   (1 "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n" "")
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
  expected: (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
  actual:   (1 "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n" "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### PF5. No remedy line

**Guards:** a refusal ends with its remedy.
**Mutation:** In `tests/preflight.sps`:

```diff
-              (say err "  remedy:     " (if (message-condition? e)
-                                             (condition-message e)
-                                             "name a usable libcurl with CHEZ_CURL_LIBCURL, an absolute path"))
```
**Result:** killed, exit 2:

```
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n")
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n")
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
  expected: (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### PF6. The candidates on one line

**Guards:** not-found lists each candidate on its own line.
**Mutation:** In `tests/preflight.sps`:

```diff
-                    (for-each (lambda (path) (say err "    " path)) candidates)))
+                    (say err "    " (words candidates))))
```
**Result:** killed, exit 2:

```
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
  expected: (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4 $T/home/.guix-profile/lib/libcurl.so.4 /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### PF7. The reason line dropped

**Guards:** a refusal prints (reason . SYMBOL), the contract (ADR-0015).
**Mutation:** In `tests/preflight.sps`:

```diff
-              (write (cons 'reason (curl-library-unavailable-reason e)) err)
-              (newline err)
```
**Result:** killed, exit 2:

```
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n")
  actual:   (1 "" "chez-curl: libcurl refused\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n")
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
  expected: (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
  actual:   (1 "" "chez-curl: libcurl refused\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### The suite and the decoy

#### TS1. The decoy cannot find libcurl's headers

**Guards:** a decoy that does not compile fails its case, never skips it (ADR-0001).
**Mutation:** In `tests/decoy-libcurl.c`:

```diff
- #include <curl/header.h>
+ #include <curl/no-such-header.h>
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (ssl-version . "DecoyTLS/1.0") (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (1 1 ((reason . load-failed) (path . "$T/accepted.so") (source . override) (detail . "(while loading $T/accepted.so) $T/accepted.so: cannot open shared object file: No such file or directory") (candidates)) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (ssl-version . #f) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (1 1 ((reason . load-failed) (path . "$T/ssl-null.so") (source . override) (detail . "(while loading $T/ssl-null.so) $T/ssl-null.so: cannot open shared object file: No such file or directory") (candidates)) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (calls . "curl_version_info(9)")) "")
  actual:   (1 1 ((reason . load-failed) (path . "$T/below-floor.so") (source . override) (detail . "(while loading $T/below-floor.so) $T/below-floor.so: cannot open shared object file: No such file or directory") (candidates)) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### TS2. The scratch directory left behind

**Guards:** the suite removes its scratch directory.
**Mutation:** In `tests/test-library-loading.sps`:

```diff
- (capture-command (list "rm" "-rf" scratch))
+ (capture-command (list "true"))
```
**Result:** killed, exit 2:

```
FAIL the scratch directory is removed
  expected: removed
  actual:   left
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### TS3. The suite loads libcurl itself

**Guards:** reading (curl)'s exports never runs its body in the suite's process.
**Mutation:** In `tests/test-library-loading.sps`:

```diff
+ (eval '(loaded-libcurl) (environment '(curl)))
+ 
```
**Result:** killed, exit 2:

```
FAIL this suite's own process never loaded libcurl
  expected: not-loaded
  actual:   loaded
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### TS4. mktemp makes a file

**Guards:** the suite stops, failing, without a scratch directory.
**Mutation:** In `tests/test-library-loading.sps`:

```diff
-     (let ((answer (capture-command '("mktemp" "-d"))))
+     (let ((answer (capture-command '("mktemp"))))
```
**Result:** killed, exit 2:

```
FAIL mktemp -d made a scratch directory
  expected: made
  actual:   not-made
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### TS5. The oracle takes the token before libcurl/

**Guards:** the real libcurl's version and TLS backend are compared with curl --version's.
**Mutation:** In `tests/test-library-loading.sps`:

```diff
-           (list (substring (car tail) 8 (string-length (car tail))) (cadr tail))
+           (list (substring (car tail) 8 (string-length (car tail))) (car tail))
```
**Result:** killed, exit 2:

```
FAIL the real libcurl through the override: loaded, as curl --version names it
  expected: (0 ((loaded . "$P/lib/libcurl.so.4") (source . override) (version . "8.20.0") (ssl-version . "libcurl/8.20.0")) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . override) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
  expected: (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (ssl-version . "libcurl/8.20.0")) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
FAIL preflight, the real libcurl: exit 0, with curl --version's version and TLS
  expected: (0 "  version:  8.20.0" "  TLS:      libcurl/8.20.0")
  actual:   (0 "  version:  8.20.0" "  TLS:      GnuTLS/3.8.13")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### The Makefile and the environment

#### MK2. CHEZ not exported

**Guards:** make test exports CHEZ to the suites. In the container CHEZ is already in the environment, so this runs make test with it unset, when only the export can supply it.
**Mutation:** In `Makefile`:

```diff
- export CHEZ
```
**Command:** `env -u CHEZ make test`, not `make test`.
**Result:** killed, exit 2:

```
FAIL CHEZ names the Chez to spawn
  expected: set
  actual:   unset
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### MK3. build left out of .PHONY

**Guards:** build is a .PHONY target, as check-help requires.
**Mutation:** In `Makefile`:

```diff
- .PHONY: help check-help check-guix check-guix-inside deps check-pins build test check-suites check-seam check-test-fails
+ .PHONY: help check-help check-guix check-guix-inside deps check-pins test check-suites check-seam check-test-fails
```
**Result:** killed, exit 2:

```
check-help: make help lists 'build', which is not in .PHONY
make: *** [Makefile:57: check-help] Error 1
```

#### MK4. build without help text

**Guards:** build is listed by make help.
**Mutation:** In `Makefile`:

```diff
- build: ## Load libcurl as (curl) would and name it; fail with the reason when it is refused
+ build:
```
**Result:** killed, exit 2:

```
check-help: make help does not list .PHONY target 'build'; give it a '## ' description on its target line
make: *** [Makefile:57: check-help] Error 1
```

#### MK5. build without src/ on the library path

**Guards:** make build runs the preflight with src/ on Chez's library path.
**Mutation:** In `Makefile`:

```diff
- 	@$(CHEZ) --libdirs src --program tests/preflight.sps
+ 	@$(CHEZ) --libdirs tests --program tests/preflight.sps
```
**Command:** `make build`, not `make test`.
**Result:** killed, exit 2:

```
Exception: library (curl private conditions) not found
make: *** [Makefile:179: build] Error 255
```

#### ST1. CHEZ_CURL_LIBCURL unset for make test

**Guards:** the suite needs the real libcurl named by absolute path, and fails without it.
**Mutation:** none to the tree. The command was `unset CHEZ_CURL_LIBCURL; make test`.
**Result:** killed, exit 2:

```
FAIL CHEZ_CURL_LIBCURL names the real libcurl, by absolute path
  expected: absolute
  actual:   not-absolute
FAIL the real libcurl through the override: loaded, as curl --version names it
  expected: (0 ((loaded . #f) (source . override) (version . "8.20.0") (ssl-version . "GnuTLS/3.8.13")) "")
  actual:   #f
FAIL preflight, the real libcurl: exit 0, with curl --version's version and TLS
  expected: (0 "  version:  8.20.0" "  TLS:      GnuTLS/3.8.13")
  actual:   #f
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### Clean rerun

After the last change to any source, suite, the decoy or the `Makefile`, on the working tree:

- `scripts/guix-env sh -c 'make test && make check-test-fails && make build'` exited 0. `make
  test` ended `test: ran 7, passed 7, failed 0, hung 0`, `check-test-fails` ended
  `check-test-fails: make test failed, as it must, in all 9 cases`, and `make build` printed the
  baseline's report, with the real path.
- `make check-guix`, on the host, ended `check-guix: ALL CHECKS PASSED`.

### Findings

- **A guard in a program cannot catch a raise from an imported library's body.** Measured
  above. The probe and the preflight evaluate `(loaded-libcurl)` inside their guards.
- **`(environment '(curl))` holds `(curl)`'s exports and nothing else.** The first run with the
  code failed every probe and preflight run with `Exception: attempt to reference unbound
  identifier let`: the evaluated form's own `let` was unbound. Both now evaluate in
  `(environment '(rnrs) '(curl))`.
- **Expanding a library does not run it.** `environment` and `library-exports` expand `(curl)`
  without running its body. Evaluating a re-exported binding runs only the library that defines
  it (measured with a library that printed from its body and re-exported another's procedure).
  So the suite reads `(curl)`'s exports, and compares its conditions with `(curl private
  conditions)`'s, without loading libcurl in its own process. `this suite's own process never
  loaded libcurl` holds that, and TS3 fails it.
- **Chez runs a library's body again at each later reference after the body raised.** Measured
  with a program that evaluates `(loaded-libcurl)` three times, each under its own guard:

  ```
  == the options-off decoy
  first: Exception in chez-curl: libcurl was built without its options API (--disable-get-easy-options); name another with CHEZ_CURL_LIBCURL with irritant "$T/off.so"
  second: Exception in chez-curl: libcurl was built without its options API (--disable-get-easy-options); name another with CHEZ_CURL_LIBCURL with irritant "$T/off.so"
  third: Exception in chez-curl: libcurl was built without its options API (--disable-get-easy-options); name another with CHEZ_CURL_LIBCURL with irritant "$T/off.so"
  calls: curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)
  == the below-floor decoy
  first: Exception in chez-curl: libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL with irritant "$T/below.so"
  second: Exception in chez-curl: libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL with irritant "$T/below.so"
  third: Exception in chez-curl: libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL with irritant "$T/below.so"
  calls: curl_version_info(9) curl_version_info(9) curl_version_info(9)
  ```

  Every retry loads the library and reads its version again. After a refusal that comes after
  `curl_global_init`, every retry calls `curl_global_init` again. A program that imports `(curl)`
  dies at the first refusal, so only `eval` or a REPL can retry. A retry made after changing
  `CHEZ_CURL_LIBCURL` would load a second libcurl into the process, which ADR-0002 rules out.
  `(raiser)`, whose body raised a non-condition directly, behaved differently: its second
  reference raised `cyclic dependency involving invocation of library (raiser)`. Nothing tests
  this yet; see Not covered.
- **An unbound identifier in an evaluated form raises before any of the form runs.** CU1 took
  `libcurl-info-host` out of `(curl)`'s exports. The bare-name preflight then failed with
  `attempt to reference unbound identifier libcurl-info-host`, exit 255, not with its refusal,
  though `(loaded-libcurl)` comes first in the form. `environment` gives an immutable
  environment, and the reference fails when the form is expanded.
- **Chez's loader raises a format condition.** Its components are `&assertion &format &message
  &irritants`, the message is `(while loading ~a) ~a`, and the irritants are the path and the
  `dlerror` text. load-failed's detail is that message, formatted. The suite's oracle formats the
  raise of the same loader, for the same path, in its own process.
- **Guix's `gcc` writes `guile: warning: failed to install locale` on stderr.** Its `ld-wrapper`
  is a Guile script. So a decoy's compile is judged by its exit status alone.
- **The ftype's layout is the header's, on x86_64.** A C program printing `offsetof` for every
  field of `curl_version_info_data` and the ftype's `ftype-&ref` offsets gave the same numbers,
  0 to 192 for `gsasl_version`. Slice 4 makes that a check.
- **`curl --version` agrees with the loaded library.** In the container, its first line is
  `curl 8.20.0 (x86_64-unknown-linux-gnu) libcurl/8.20.0 GnuTLS/3.8.13 …`. It has 18 features,
  and `make build` names 18.
- **The preflight cannot reach its guard without `(curl private conditions)`.** MK5 ran it with
  `--libdirs tests`. It died at that static import, `Exception: library (curl private
  conditions) not found`, before its `eval`. The driver first expected the `(curl)` message, and
  marked the run unexpected until that was corrected.

### Not covered

- **NL33 survives.** Every field of the ftype after `ssl_version` is unread. Dropping one moves
  only later offsets, so nothing fails. Slice 4's `offsetof` check covers them (ADR-0001,
  decision 4).
- **A retry after a refusal.** See Findings: each later reference runs the load again,
  `curl_global_init` included, and could load a second library. No test makes a second
  reference. This needs a decision.
- **The FHS branches.** The suite's FHS case ran once, forced in a lab copy. In the Guix world it
  failed as it should: `expected: (0 (source . system) standard)`,
  `actual: (0 (source . guix-environment) not-standard)`. It first runs for real on slice 5's
  FHS CI.
- **`make build`'s recipe.** `make test` runs the preflight itself, not `make build`. MK5 is
  killed only by running `make build`.
- **The header probe's `hout` slot is freed.** The decoy cannot see `foreign-free`. The memory
  gate (ADR-0014) will.
- **NULL `version` or `host`.** A NULL is read as `#f`. A `#f` version then reaches
  `check-version`, whose message `string-append` raises an assertion violation, not a refusal. No
  decoy has either. Only `ssl_version`'s NULL is tested.
- **The loader-message fallback.** A loader raise without a format condition is printed with
  `display-condition`. Chez 10.4.0's loader never raises one.
- **The real library's probe arguments.** Only the decoy logs them. The real library is held to
  the outcome: loaded, with `curl --version`'s version and TLS backend.
- **The oracle on other builds.** It takes the token after `libcurl/X`. On macOS, Apple's curl
  prints `(SecureTransport) LibreSSL/…` there, and a multi-SSL build lists several backends.
- **`not-found` outside the container on Guix System.** There
  `/run/current-system/profile/lib/libcurl.so.4` may exist, and the case would load it.
- **The preflight's remedy text.** It prints the refusal's message as the remedy. Only
  invalid-override's and not-found's are asserted.
- **`capture-command`'s capture files** still use fixed-pattern names in `$TMPDIR` (slice 2's
  carry-forward). The suite's own files go under `mktemp -d`.
- **Other platforms.** Every run was Linux, amd64, in the container.

### Coverage

Every test this step added or changed, with the mutants that failed it by name.

**`test-library-loading`**

| Test | Failed by |
|---|---|
| CHEZ names the Chez to spawn | MK2 |
| mktemp -d made a scratch directory | TS4 |
| decoy accepted: the control loads, calling curl_global_init exactly once, after the version | NL2, NL3, NL4, NL12, NL15, NL16, NL17, NL18, NL19, NL20, NL32, NL34, NL35, CN9, CN6, CN7, CN8, PR4, TS1 |
| decoy ssl-null: a NULL ssl_version is reported as #f | NL2, NL3, NL4, NL12, NL15, NL16, NL17, NL18, NL19, NL20, NL31, NL32, NL34, NL35, CN9, CN6, CN7, CN8, PR4, TS1 |
| decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info | NL1, NL2, NL14, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info | NL1, NL2, NL14, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it | NL22, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs | NL2, NL3, NL4, NL23, NL24, NL34, CN7, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name | NL2, NL3, NL4, NL12, NL13, NL15, NL16, NL17, NL18, NL19, NL20, NL34, CN9, CN6, CN7, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header | NL2, NL3, NL4, NL12, NL13, NL15, NL16, NL17, NL18, NL19, NL20, NL34, CN9, CN6, CN7, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs | NL2, NL3, NL4, NL15, NL21, NL34, CN6, CN7, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info | NL5, NL6, PR1, PR2, PR3, PR4, TS1 |
| decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it | NL2, NL4, NL5, NL7, NL34, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it | NL2, NL3, NL4, NL5, NL8, NL34, CN6, CN7, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it | NL2, NL3, NL4, NL5, NL9, NL34, CN6, CN7, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it | NL2, NL3, NL4, NL5, NL10, NL34, CN6, CN7, CN8, PR1, PR2, PR3, PR4, TS1 |
| decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it | NL2, NL3, NL4, NL5, NL11, NL34, CN6, CN7, CN8, PR1, PR2, PR3, PR4, TS1 |
| CHEZ_CURL_LIBCURL names the real libcurl, by absolute path | ST1 |
| the real libcurl through the override: loaded, as curl --version names it | NL12, NL32, NL34, NL35, CN6, TS5, ST1 |
| a bare name in the override is invalid-override, carrying it | PR1, PR2, PR3 |
| a text file is load-failed, with the loader's message | NL26, NL27, PR1, PR2, PR3 |
| a path that does not exist is load-failed, with the loader's message | NL26, NL27, PR1, PR2, PR3 |
| guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4 | NL12, NL28, NL29, NL30, NL32, NL34, NL35, CN6, TS5 |
| guix: with no profile to search, not-found lists every candidate checked | NL28, PR1, PR2, PR3 |
| guix: a candidate that fails to load is load-failed, and the next is never tried | NL25, NL26, NL27, NL28, NL30, PR1, PR2, PR3 |
| preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host | NL12, NL15, NL32, NL34, NL35, CN6, CU1, PF2, TS1 |
| preflight, the real libcurl: exit 0, with curl --version's version and TLS | NL12, NL32, NL34, NL35, CN6, CU1, PF2, TS5, ST1 |
| preflight, a bare name: exit 1, refused as invalid-override, with the remedy | CU1, PF1, PF3, PF4, PF5, PF7 |
| preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line | NL28, CU1, PF1, PF3, PF4, PF5, PF6, PF7 |
| (curl) exports loaded-libcurl, the info record's accessors and the conditions | CU1 |
| (curl)'s conditions are (curl private conditions)'s own | CU2 |
| this suite's own process never loaded libcurl | TS3 |
| the scratch directory is removed | TS2 |

**`test-require-threaded`**, the rows this step changed or added

| Test | Failed by |
|---|---|
| the scan read src/: (curl), conditions, constants, discovery, native and verify | RC9 |
| src/curl.sls imports (curl private require-threaded) first | CU3 |
| src/curl/private/native.sls imports (curl private require-threaded) first | NL36 |

## Review fixes: loading

Evidence that the fixes to the native layer's review fail through the property each claims to
guard ([ADR-0001](decisions/0001-bind-libcurl-directly.md),
[ADR-0002](decisions/0002-runtime-libcurl-discovery.md),
[ADR-0003](decisions/0003-libcurl-floor-7-85.md), [global constraints](global-constraints.md),
"Loading libcurl"). The review found eight things; each fix, and what it added:

1. **A refusal sticks: libcurl is loaded at most once per process.**
   `src/curl/private/load-state.sls`, `(curl private load-state)`, holds the load's first
   failure. It exports `load-failure`, `record-load-failure!`, `as-serious` and the `load-step`
   macro. Every step of `native.sls`'s body that can raise runs inside `load-step`, and its first
   definition raises a recorded failure again. The probe now references `loaded-libcurl` three
   times and prints `(again . (A B))`; the suite expects `same` twice in every case. A new case
   changes `CHEZ_CURL_LIBCURL` between references (`--then-override`) and checks that a second
   decoy's marker never enters the process (`--marker`, `DECOY_MARKER`). `tests/test-load-state.sps`
   is new.
2. **A NULL `version` is `load-failed`,** detail `"curl_version_info returned no version"`
   (`DECOY_VERSION_NULL`). A NULL `host` stays `#f` (`DECOY_HOST_NULL`), and the probe prints
   the host.
3. **A C oracle replaces `curl --version`.** `tests/libcurl-oracle.c` `dlopen`s the path the
   probe loaded and prints five fields of `curl_version_info(CURLVERSION_TENTH)`.
   `tests/libcurl-oracle.sls`, `(libcurl-oracle)`, compiles and runs it, and owns `c-compiler`,
   which splits `$CC` at whitespace for every compile. The probe prints the same five fields,
   and the suite compares them one test per field. The real-library cases take their path from
   the probe, so they hold with the override set or unset.
4. **Discovery's case branches on the platform, then the world.** macOS expects
   `macos-system`, the Guix world `guix-environment` and `not-found`, FHS `system`, and any other
   platform `not-found` with no candidate.
5. **A raise that is not a refusal is seen.** `tests/fixtures/raising/curl.sls` is a `(curl)`
   whose `loaded-libcurl` raises a plain `error`. Run with `--libdirs
   tests/fixtures/raising:src`, the probe must print `(raised . …)` and exit 2, and the preflight
   must die in Chez's default handler, exit 255, with no reason line.
6. **`tests/test-native.sps` loads libcurl in its own process,** so the memory gate (ADR-0014)
   will run the load. It asserts the record's five fields against the C oracle.
7. **A refusal made after the version read carries the library's report.**
   `&curl-library-unavailable` has a sixth field, `library`: a `libcurl-info` or `#f`. The
   record moved to `src/curl/private/libcurl-info.sls`, `(curl private libcurl-info)`, whose
   body cannot raise (see Findings). `check-version` and `check-apis` take the report. The probe
   prints `(library . L)`, and the preflight prints the version, TLS backend and features of a
   refusal that has them.
8. **Nits.** The invalid-override message adds "set one, or unset it to use discovery". A
   comment in the suite says the preflight's tests assert its whole output, and every refusal
   test the reason symbol.

`tests/test-require-threaded.sps`'s liveness row gained `libcurl-info` and `load-state`; no
other line of it changed.

A driver in the session scratchpad ran every mutation, as in the parts above. It froze a snapshot
of the working tree, without `.git`, `build/` or `.claude/`, and gave each mutation a fresh copy
of it. It applied the mutation by exact-text replacement, aborting unless each target occurred
exactly once, and it refused a mutation that changed nothing. It touched the copy's
`manifest.scm` and ran `scripts/guix-env sh -c '<command>'` from inside the copy, four copies at
a time. The command was `make test` unless the case says otherwise. A mutation counts as killed
only when the command exits non-zero and every expected line appears whole in its output: the
suites' `FAIL <test name>` lines and `make test`'s `test: FAIL <suite>` lines. Each output was
kept verbatim. The working tree was never edited.

**Result** quotes each `FAIL` line, with the expected and actual values of the first three, then
the `Exception` and `test:` lines. `$T` is the suite's `mktemp -d` directory, a fresh
`/tmp/tmp.XXXXXXXXXX` in each run, and `$P` is the container's profile,
`/gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile`.

Cases are named `LS` (the load state and the steps inside `load-step`), `VN` (a NULL version),
`NL` (the native layer: new cases from 37 on, and reruns), `OR` (the oracle), `DS` (discovery's
branches), `PR` and `PF` (the probe and the preflight), `LB` (the report on a refusal), `MS` (the
message), `CU` (`(curl)`) and `ST` (the environment, with no change to the tree).

### Measured first: what a library body's raise leaves behind

The reviewer's `q.sps` defines eight libraries whose bodies print, then raise one kind of
object each, and references each twice through `eval`, under a guard. Run with Chez 10.4.0 in
the container:

```
== (k1)                                    raise (make-message-condition "m")
  body k1 runs
  raised: m
  raised: cyclic dependency involving invocation of library ~s
== (k2)                                    raise (make-warning)
  body k2 runs
  raised: #<condition &warning>
  raised: cyclic dependency involving invocation of library ~s
== (k3)                                    raise (make-serious-condition)
  body k3 runs
  raised: #<condition &serious>
  body k3 runs
  raised: #<condition &serious>
== (k4)                                    raise (make-violation)
  body k4 runs
  raised: #<condition &violation>
  body k4 runs
  raised: #<condition &violation>
== (k5)                                    raise (make-assertion-violation)
  body k5 runs
  raised: #<condition &assertion>
  body k5 runs
  raised: #<condition &assertion>
== (k6)                                    raise (condition (make-error) (make-message-condition "e"))
  body k6 runs
  raised: e
  body k6 runs
  raised: e
== (k7)                                    raise 'sym
  body k7 runs
  raised: sym
  raised: cyclic dependency involving invocation of library ~s
== (k8)                                    raise 42
  body k8 runs
  raised: 42
  raised: cyclic dependency involving invocation of library ~s
```

(The right-hand column, what each body raised, is added here from `lib/k1.sls` to `lib/k8.sls`.)
After a serious condition the body runs again in full; after anything else the library is
wedged. `tests/test-load-state.sps` keeps both facts as tests: "Chez wedges a library whose body
raised a symbol (the reason for load-step)" and "through load-step, the same raise is serious, so
the body runs again, never wedged".

### Red runs

Each fix that changed `src/` had its tests written first, and `scripts/guix-env sh -c 'make
test'` run on the working tree before the code. Items 3 to 6 changed only tests; their checks
are watched failing by the mutants below.

**Item 1, before `load-state.sls` existed.** The probe made its three references, the suite
expected `(again same same)`, and the sticky case and `tests/test-load-state.sps` were written.
`make test` exited 2. `test-library-loading` failed 19 tests, every refusal case: each later
reference ran the load again and raised a fresh refusal, and each decoy's log shows the load
three times. The sticky case loaded the second decoy, whose marker entered the process. The two
accepted decoys and the real library passed: a body that did not raise is not run again.

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (again (refused below-floor) (refused below-floor)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
  expected: (0 1 ((reason . missing-api) (path . "$T/not-curl.so") (source . override) (detail . "curl_version_info") (candidates) (again same same) (calls . "")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/not-curl.so") (source . override) (detail . "curl_version_info") (candidates) (again (refused missing-api) (refused missing-api)) (calls . "")) "")
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
  expected: (0 0 1 ((reason . missing-api) (path . "$T/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (again same same) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 1 ((reason . missing-api) (path . "$T/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (again (loaded "$T/sticks-then.so") (loaded "$T/sticks-then.so")) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
test: FAIL tests/test-library-loading.sps (exit 1)
Exception: library (curl private load-state) not found
test: FAIL tests/test-load-state.sps (exit 255)
FAIL the scan read src/: (curl), conditions, constants, discovery, load-state, native and verify
  expected: (read read read read read read read)
  actual:   (read read read read missed read read)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 8, passed 5, failed 3, hung 0
```

In the sticky case the call log cannot tell the two decoys apart: the second, accepted, makes
the same six calls the first did before its refusal. The evidence is `(again (loaded
"$T/sticks-then.so") …)` and `(marker . present)`: a second libcurl was loaded into the
process.

**Item 2, before the NULL check.** The decoy with a NULL `version` was not refused at all. It
loaded and was accepted, reported with `(version . #f)`: the floor is checked on `version_num`,
so the NULL string never reached the message that would have raised on it. The native layer's
own Not covered entry had predicted an assertion violation instead.

```
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 0 ((loaded . "$T/version-null.so") (source . override) (version . #f) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 8, passed 7, failed 1, hung 0
```

The `host-null` case passed in the same run: a NULL `host` was already `#f`. NL31 watches it
fail.

**Item 7, before `libcurl-info.sls` and the sixth field.** `test-conditions` and `test-verify`
died at import, and the liveness row missed `libcurl-info`. In `test-library-loading` 42 of 47
tests failed: the probe and the preflight reference `curl-library-unavailable-library`, which
did not exist, so every run of either died at expansion, exit 255.

```
Exception: library (curl private libcurl-info) not found
test: FAIL tests/test-conditions.sps (exit 255)
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 255 () "Exception: attempt to reference unbound identifier curl-library-unavailable-library at line 119, char 39 of tests/refusal-probe.sps\n")
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
  actual:   (255 "" "Exception: attempt to reference unbound identifier curl-library-unavailable-library at line 52, char 30 of tests/preflight.sps\n")
FAIL (curl) exports loaded-libcurl, the info record's accessors and the conditions
FAIL (curl)'s conditions are (curl private conditions)'s own
FAIL (curl)'s report accessors are (curl private libcurl-info)'s own
  expected: (same same same same same same same same same)
  actual:   (raised "Exception in environment: library (curl private libcurl-info) not found")
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL the scan read src/: (curl), conditions, constants, discovery, libcurl-info, load-state, native and verify
  expected: (read read read read read read read read)
  actual:   (read read read read missed read read read)
test: FAIL tests/test-require-threaded.sps (exit 1)
Exception: library (curl private libcurl-info) not found
test: FAIL tests/test-verify.sps (exit 255)
test: ran 9, passed 5, failed 4, hung 0
```

These failures name the right tests for the wrong reason: nothing could run. The LB mutants
below are the evidence that each check fails through its own property.

**Item 8, before the message changed.**

```
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for; set one, or unset it to use discovery\n")
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl; it is loaded as given, and never searched for\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

**Items 5 and 6 passed at once.** The probe's catch-all and the preflight's default handler
already did the right thing for the raising fixture, and the native layer already reported the
real library's fields correctly. PR5, PF8, NT1, NT2 and NL37 to NL39 fail them.

### Baseline

On the working tree as the snapshot froze it (sha256 of its files, the submodule aside,
`a1526dd159168321ea5cda7bee3275ed5134bfe646e4ad72dc857132d02a87cd`), each in a fresh copy:

- **`make test`** exited 0:

  ```
  check-suites: every suite ends with (exit (suite-exit-status runner)) (9 checked)
  check-seam: the seam holds (9 libraries in 9 files checked)
  test: pass tests/test-conditions.sps
  test: pass tests/test-curl-testing.sps
  test: pass tests/test-discovery.sps
  # of expected passes      48
  test: pass tests/test-library-loading.sps
  # of expected passes      12
  test: pass tests/test-load-state.sps
  test: pass tests/test-manifest.sps
  # of expected passes      8
  test: pass tests/test-native.sps
  test: pass tests/test-require-threaded.sps
  test: pass tests/test-verify.sps
  test: ran 9, passed 9, failed 0, hung 0
  ```

- **`make build`** exited 0, with the native layer's report unchanged:

  ```
  chez-curl: libcurl loaded and accepted
    path:     $P/lib/libcurl.so.4 (override)
    version:  8.20.0
    TLS:      GnuTLS/3.8.13
    features: ipv6 ssl libz asynchdns spnego largefile idn tlsauth-srp http2 gssapi kerberos5 unix-sockets psl https-proxy altsvc zstd hsts threadsafe
    host:     x86_64-unknown-linux-gnu
  ```

- **`make check-test-fails`** exited 0, ending `check-test-fails: make test failed, as it must,
  in all 9 cases`.
- **ST1 and ST2**, below, ran `make test` with the override unset and with `CC` as two words.
  Both passed, as they must.

81 mutations ran. 79 were killed, each with every expected line present. Two survived, as
expected: LS12 and LS20, steps that cannot raise (see Not covered). Every test these fixes
added or changed was failed by name by at least one mutant; Coverage, at the end, lists which.
The reruns NL1 to NL12, NL25, CU1, PR1, PR2 and PF1 to PF3 were rewritten against the new text
and killed again, as were NL31, NL32, NL34 and NL35. Every mutant was applied to one snapshot.
On a first pass three predictions were wrong (LS13, NL34, LB10), LS30's edit left a parenthesis
over, and NT1 killed `tests/test-native.sps` before its first test, which the suite now guards
against. Each was corrected and rerun; Findings has what they showed.


### A refusal sticks

#### LS1. The recorded failure is never raised again

**Guards:** the first definition of native's body raises the recorded failure, so the load runs once.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-       (when failure (raise failure))
+       (when #f (raise failure))
```
**Result:** killed, exit 2:

```
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again (refused load-failed) (refused load-failed)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused below-floor) (refused below-floor)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again (refused no-ssl) (refused no-ssl)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS2. load-step records nothing

**Guards:** load-step records the failure it raises.
**Mutation:** In `src/curl/private/load-state.sls`:

```diff
-                        (record-load-failure! c)
```
**Result:** killed, exit 2:

```
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again (refused load-failed) (refused load-failed)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused below-floor) (refused below-floor)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again (refused no-ssl) (refused no-ssl)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL load-step records what it raised
FAIL a later load-step raises its own serious condition, unchanged, and the first stays recorded
FAIL record-load-failure! keeps the first failure
test: FAIL tests/test-load-state.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### LS3. load-step raises what was raised, unmade serious

**Guards:** load-step makes a raise serious before recording and raising it.
**Mutation:** In `src/curl/private/load-state.sls`:

```diff
-        (guard (e (#t (let ((c (as-serious e)))
+        (guard (e (#t (let ((c e))
```
**Result:** killed, exit 2:

```
FAIL load-step raises a symbol made serious, carrying it
  expected: (#t #t chez-curl (boom))
  actual:   (#t #f record-load-failure! (boom))
FAIL load-step records what it raised
  expected: recorded-what-was-raised
  actual:   none
FAIL a later load-step raises its own serious condition, unchanged, and the first stays recorded
  expected: (raised-itself first-kept)
  actual:   (raised-itself replaced)
FAIL record-load-failure! keeps the first failure
test: FAIL tests/test-load-state.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS4. as-serious answers everything unchanged

**Guards:** as-serious makes a non-serious raise an &error carrying it.
**Mutation:** In `src/curl/private/load-state.sls`:

```diff
-     (if (serious-condition? obj)
+     (if #t
```
**Result:** killed, exit 2:

```
FAIL as-serious makes a symbol or a number an error from chez-curl, carrying it
  expected: ((#t #t chez-curl (boom)) (#t #t chez-curl (42)))
  actual:   ((not-a-condition boom) (not-a-condition 42))
FAIL as-serious makes a warning or a bare message an error, carrying it
  expected: (carried carried)
  actual:   ((#f #f #f #f) (#f #f #f #f))
FAIL load-step raises a symbol made serious, carrying it
  expected: (#t #t chez-curl (boom))
  actual:   (#t #f record-load-failure! (boom))
FAIL load-step records what it raised
FAIL a later load-step raises its own serious condition, unchanged, and the first stays recorded
FAIL record-load-failure! keeps the first failure
test: FAIL tests/test-load-state.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS5. record-load-failure! keeps the last failure

**Guards:** the first failure stays recorded.
**Mutation:** In `src/curl/private/load-state.sls`:

```diff
-     (unless failure
-       (set! failure c)))
+     (set! failure c))
```
**Result:** killed, exit 2:

```
FAIL a later load-step raises its own serious condition, unchanged, and the first stays recorded
  expected: (raised-itself first-kept)
  actual:   (raised-itself replaced)
FAIL record-load-failure! keeps the first failure
  expected: first-kept
  actual:   replaced
test: FAIL tests/test-load-state.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS6. record-load-failure! takes a condition that is not serious

**Guards:** only a serious condition is recorded: a non-serious one, raised again, would wedge native.
**Mutation:** In `src/curl/private/load-state.sls`:

```diff
-     (unless (serious-condition? c)
+     (unless #t
```
**Result:** killed, exit 2:

```
FAIL record-load-failure! refuses a condition that is not serious
  expected: refused
  actual:   no-raise
test: FAIL tests/test-load-state.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS26. A failure recorded from the start

**Guards:** nothing is recorded until a step fails.
**Mutation:** In `src/curl/private/load-state.sls`:

```diff
-   (define failure #f)
+   (define failure (make-error))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception occurred with condition components:\n  0. &error") (again same same)) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception occurred with condition components:\n  0. &error") (again same same)) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception occurred with condition components:\n  0. &error") (again same same)) "")
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe, in this environment, loads one by absolute path
FAIL the C oracle read the real libcurl
FAIL the real libcurl: the probe's version is the C oracle's
FAIL the real libcurl: the probe's version-num is the C oracle's
FAIL the real libcurl: the probe's features is the C oracle's
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL nothing is recorded at first
FAIL load-step answers its expression's value, and records nothing
FAIL load-step records what it raised
FAIL a later load-step raises its own serious condition, unchanged, and the first stays recorded
FAIL record-load-failure! keeps the first failure
test: FAIL tests/test-load-state.sps (exit 1)
Exception occurred with condition components:
test: FAIL tests/test-native.sps (exit 255)
test: ran 9, passed 6, failed 3, hung 0
```

#### LS27. load-step answers #t, not its expression's value

**Guards:** load-step answers its expression's value.
**Mutation:** In `src/curl/private/load-state.sls`:

```diff
-          expr)))))
+          (begin expr #t))))))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception in car: #t is not a pair") (again (raised "Exception in car: #t is not a pair") (raised "Exception in car: #t is not a pair"))) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception in car: #t is not a pair") (again (raised "Exception in car: #t is not a pair") (raised "Exception in car: #t is not a pair"))) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception in car: #t is not a pair") (again (raised "Exception in car: #t is not a pair") (raised "Exception in car: #t is not a pair"))) "")
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe, in this environment, loads one by absolute path
FAIL the C oracle read the real libcurl
FAIL the real libcurl: the probe's version is the C oracle's
FAIL the real libcurl: the probe's version-num is the C oracle's
FAIL the real libcurl: the probe's features is the C oracle's
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL load-step answers its expression's value, and records nothing
test: FAIL tests/test-load-state.sps (exit 1)
Exception in car: #t is not a pair
test: FAIL tests/test-native.sps (exit 255)
test: ran 9, passed 6, failed 3, hung 0
```

#### LS28. as-serious wraps a serious condition too

**Guards:** a serious condition is raised as itself, so a refusal stays a refusal.
**Mutation:** In `src/curl/private/load-state.sls`:

```diff
-     (if (serious-condition? obj)
+     (if #f
```
**Result:** killed, exit 2:

```
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in chez-curl: loading libcurl raised something other than a serious condition with irritant #<compound condition>") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in chez-curl: loading libcurl raised something other than a serious condition with irritant #<compound condition>") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in chez-curl: loading libcurl raised something other than a serious condition with irritant #<compound condition>") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL as-serious answers a serious condition itself
FAIL a later load-step raises its own serious condition, unchanged, and the first stays recorded
test: FAIL tests/test-load-state.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### LS29. The wedge test's bare library goes through load-step

**Guards:** the wedge test sees a wedge: its control raises a bare symbol.
**Mutation:** In `tests/test-load-state.sps`:

```diff
-   (twice '(load-state-fixture bare) '(raise 'boom)))
+   (twice '(load-state-fixture bare) '(load-step (raise 'boom))))
```
**Result:** killed, exit 2:

```
FAIL Chez wedges a library whose body raised a symbol (the reason for load-step)
  expected: ((raised boom) wedged)
  actual:   (raised-serious raised-serious)
test: FAIL tests/test-load-state.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS30. load-step is the expression alone

**Guards:** load-step catches, makes serious, records and raises again.
**Mutation:** In `src/curl/private/load-state.sls`:

```diff
-        (guard (e (#t (let ((c (as-serious e)))
-                        (record-load-failure! c)
-                        (raise c))))
-          expr)))))
+        expr))))
```
**Result:** killed, exit 2:

```
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again (refused load-failed) (refused load-failed)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused below-floor) (refused below-floor)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again (refused no-ssl) (refused no-ssl)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL load-step raises a symbol made serious, carrying it
FAIL load-step records what it raised
FAIL a later load-step raises its own serious condition, unchanged, and the first stays recorded
FAIL record-load-failure! keeps the first failure
FAIL through load-step, the same raise is serious, so the body runs again, never wedged
test: FAIL tests/test-load-state.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

### Every step inside `load-step`

#### LS7. `chosen` without load-step

**Guards:** `chosen` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `chosen`'s `load-step` became `begin`:

```diff
@@
    (define chosen
-     (load-step
+     (begin
       (call-with-values
```
**Result:** killed, exit 2:

```
FAIL a bare name in the override is invalid-override, carrying it
  expected: (1 ((reason . invalid-override) (path . #f) (source . override) (detail . "libcurl.so.4") (candidates) (library . #f) (again same same)) "")
  actual:   (1 ((reason . invalid-override) (path . #f) (source . override) (detail . "libcurl.so.4") (candidates) (library . #f) (again (refused invalid-override) (refused invalid-override))) "")
FAIL guix: with no profile to search, not-found lists every candidate checked
  expected: (1 ((reason . not-found) (path . #f) (source . #f) (detail . #f) (candidates "$T/home/.guix-home/profile/lib/libcurl.so.4" "$T/home/.guix-profile/lib/libcurl.so.4" "/run/current-system/profile/lib/libcurl.so.4") (library . #f) (again same same)) "")
  actual:   (1 ((reason . not-found) (path . #f) (source . #f) (detail . #f) (candidates "$T/home/.guix-home/profile/lib/libcurl.so.4" "$T/home/.guix-profile/lib/libcurl.so.4" "/run/current-system/profile/lib/libcurl.so.4") (library . #f) (again (refused not-found) (refused not-found))) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS8. `libcurl-loaded` without load-step

**Guards:** `libcurl-loaded` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `libcurl-loaded`'s `load-step` became `begin`:

```diff
@@
    (define libcurl-loaded
-     (load-step
+     (begin
       (guard (e (#t (refuse 'load-failed libcurl-path libcurl-source #f (loader-message e)
```
**Result:** killed, exit 2:

```
FAIL a text file is load-failed, with the loader's message
  expected: (1 ((reason . load-failed) (path . "$T/not-a-library.so") (source . override) (detail . "(while loading $T/not-a-library.so) $T/not-a-library.so: file too short") (candidates) (library . #f) (again same same)) "")
  actual:   (1 ((reason . load-failed) (path . "$T/not-a-library.so") (source . override) (detail . "(while loading $T/not-a-library.so) $T/not-a-library.so: file too short") (candidates) (library . #f) (again (refused load-failed) (refused load-failed))) "")
FAIL a path that does not exist is load-failed, with the loader's message
  expected: (1 ((reason . load-failed) (path . "$T/no-such-dir/libcurl.so.4") (source . override) (detail . "(while loading $T/no-such-dir/libcurl.so.4) $T/no-such-dir/libcurl.so.4: cannot open shared object file: No such file or directory") (candidates) (library . #f) (again same same)) "")
  actual:   (1 ((reason . load-failed) (path . "$T/no-such-dir/libcurl.so.4") (source . override) (detail . "(while loading $T/no-such-dir/libcurl.so.4) $T/no-such-dir/libcurl.so.4: cannot open shared object file: No such file or directory") (candidates) (library . #f) (again (refused load-failed) (refused load-failed))) "")
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
  expected: (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . guix-environment) (detail . "(while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short") (candidates) (library . #f) (again same same)) "")
  actual:   (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . guix-environment) (detail . "(while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short") (candidates) (library . #f) (again (refused load-failed) (refused load-failed))) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS9. `curl-version-info` without load-step

**Guards:** `curl-version-info` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `curl-version-info`'s `load-step` became `begin`:

```diff
@@
    ;; curl_version_info_data *curl_version_info(CURLversion age)
-   (define curl-version-info (load-step (bind-required "curl_version_info" (int) uptr #f)))
+   (define curl-version-info (begin (bind-required "curl_version_info" (int) uptr #f)))
  
```
**Result:** killed, exit 2:

```
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
  expected: (0 1 ((reason . missing-api) (path . "$T/not-curl.so") (source . override) (detail . "curl_version_info") (candidates) (library . #f) (again same same) (calls . "")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/not-curl.so") (source . override) (detail . "curl_version_info") (candidates) (library . #f) (again (refused missing-api) (refused missing-api)) (calls . "")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS10. `version-data` without load-step

**Guards:** `version-data` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `version-data`'s `load-step` became `begin`:

```diff
@@
    (define version-data
-     (load-step
+     (begin
       (let ((address (curl-version-info curlversion-tenth)))
```
**Result:** killed, exit 2:

```
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
  expected: (0 1 ((reason . load-failed) (path . "$T/version-info-null.so") (source . override) (detail . "curl_version_info returned NULL") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/version-info-null.so") (source . override) (detail . "curl_version_info returned NULL") (candidates) (library . #f) (again (refused load-failed) (refused load-failed)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS11. `version-string` without load-step

**Guards:** `version-string` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `version-string`'s `load-step` became `begin`:

```diff
@@
    (define version-string
-     (load-step
+     (begin
       (or (c-string (ftype-ref curl-version-info-data (version) version-data))
```
**Result:** killed, exit 2:

```
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again (refused load-failed) (refused load-failed)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS12. `info` without load-step

**Guards:** `info` runs inside load-step. It cannot raise, so nothing can tell: expected to survive.
**Mutation:** In `src/curl/private/native.sls`, `info`'s `load-step` became `begin`:

```diff
@@
    (define info
-     (load-step
+     (begin
       (let ((features (ftype-ref curl-version-info-data (features) version-data)))
```
**Result:** passed, as expected: exit 0, and `make test` printed `test: ran 9, passed 9, failed 0, hung 0`.

#### LS13. `version-checked` without load-step

**Guards:** `version-checked` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `version-checked`'s `load-step` became `begin`:

```diff
@@
    (define version-checked
-     (load-step
+     (begin
       (check-version (libcurl-info-version info) (libcurl-info-version-number info)
```
**Result:** killed, exit 2:

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused below-floor) (refused below-floor)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again (refused no-ssl) (refused no-ssl)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS14. `curl-global-init` without load-step

**Guards:** `curl-global-init` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `curl-global-init`'s `load-step` became `begin`:

```diff
@@
    ;; CURLcode curl_global_init(long flags)
-   (define curl-global-init (load-step (bind-required "curl_global_init" (long) int info)))
+   (define curl-global-init (begin (bind-required "curl_global_init" (long) int info)))
  
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_global_init.so") (source . override) (detail . "curl_global_init") (candidates) (library "$T/lacks-curl_global_init.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/lacks-curl_global_init.so") (source . override) (detail . "curl_global_init") (candidates) (library "$T/lacks-curl_global_init.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused missing-api) (refused missing-api)) (calls . "curl_version_info(9) curl_version_info(9) curl_version_info(9)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS15. `global-initialized` without load-step

**Guards:** `global-initialized` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `global-initialized`'s `load-step` became `begin`:

```diff
@@
    (define global-initialized
-     (load-step
+     (begin
       (let ((code (curl-global-init curl-global-default)))
```
**Result:** killed, exit 2:

```
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
  expected: (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (library "$T/init-fails.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (library "$T/init-fails.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused load-failed) (refused load-failed)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS16. `curl-easy-option-by-name` without load-step

**Guards:** `curl-easy-option-by-name` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `curl-easy-option-by-name`'s `load-step` became `begin`:

```diff
@@
    (define curl-easy-option-by-name
-     (load-step (bind-required "curl_easy_option_by_name" (string) uptr info)))
+     (begin (bind-required "curl_easy_option_by_name" (string) uptr info)))
  
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_option_by_name.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/lacks-curl_easy_option_by_name.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_option_by_name.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/lacks-curl_easy_option_by_name.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused missing-api) (refused missing-api)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS17. `curl-easy-init` without load-step

**Guards:** `curl-easy-init` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `curl-easy-init`'s `load-step` became `begin`:

```diff
@@
    ;; CURL *curl_easy_init(void)
-   (define curl-easy-init (load-step (bind-required "curl_easy_init" () uptr info)))
+   (define curl-easy-init (begin (bind-required "curl_easy_init" () uptr info)))
  
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_init.so") (source . override) (detail . "curl_easy_init") (candidates) (library "$T/lacks-curl_easy_init.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_init.so") (source . override) (detail . "curl_easy_init") (candidates) (library "$T/lacks-curl_easy_init.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused missing-api) (refused missing-api)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS18. `curl-easy-header` without load-step

**Guards:** `curl-easy-header` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `curl-easy-header`'s `load-step` became `begin`:

```diff
@@
    (define curl-easy-header
-     (load-step
+     (begin
       (bind-required "curl_easy_header" (uptr string size_t unsigned-int int uptr) int info)))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_header.so") (source . override) (detail . "curl_easy_header") (candidates) (library "$T/lacks-curl_easy_header.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_header.so") (source . override) (detail . "curl_easy_header") (candidates) (library "$T/lacks-curl_easy_header.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused missing-api) (refused missing-api)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS19. `curl-easy-cleanup` without load-step

**Guards:** `curl-easy-cleanup` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `curl-easy-cleanup`'s `load-step` became `begin`:

```diff
@@
    ;; void curl_easy_cleanup(CURL *easy)
-   (define curl-easy-cleanup (load-step (bind-required "curl_easy_cleanup" (uptr) void info)))
+   (define curl-easy-cleanup (begin (bind-required "curl_easy_cleanup" (uptr) void info)))
  
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_cleanup.so") (source . override) (detail . "curl_easy_cleanup") (candidates) (library "$T/lacks-curl_easy_cleanup.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_cleanup.so") (source . override) (detail . "curl_easy_cleanup") (candidates) (library "$T/lacks-curl_easy_cleanup.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused missing-api) (refused missing-api)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS20. `option-found?` without load-step

**Guards:** `option-found?` runs inside load-step. It cannot raise, so nothing can tell: expected to survive.
**Mutation:** In `src/curl/private/native.sls`, `option-found?`'s `load-step` became `begin`:

```diff
@@
    (define option-found?
-     (load-step (not (zero? (curl-easy-option-by-name "URL")))))
+     (begin (not (zero? (curl-easy-option-by-name "URL")))))
  
```
**Result:** passed, as expected: exit 0, and `make test` printed `test: ran 9, passed 9, failed 0, hung 0`.

#### LS21. `header-code` without load-step

**Guards:** `header-code` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `header-code`'s `load-step` became `begin`:

```diff
@@
    (define header-code
-     (load-step
+     (begin
       (let ((easy (curl-easy-init)))
```
**Result:** killed, exit 2:

```
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
  expected: (0 1 ((reason . load-failed) (path . "$T/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library "$T/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init()")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library "$T/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused load-failed) (refused load-failed)) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init()")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS22. `apis-checked` without load-step

**Guards:** `apis-checked` runs inside load-step, so its raise is recorded and the load never runs again.
**Mutation:** In `src/curl/private/native.sls`, `apis-checked`'s `load-step` became `begin`:

```diff
@@
    (define apis-checked
-     (load-step
+     (begin
       (check-apis option-found? header-code libcurl-path libcurl-source info)))
```
**Result:** killed, exit 2:

```
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused missing-api) (refused missing-api)) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  expected: (0 1 ((reason . missing-api) (path . "$T/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "$T/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "$T/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again (refused missing-api) (refused missing-api)) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
  expected: (0 0 1 ((reason . missing-api) (path . "$T/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "$T/sticks-then.so") (again same same) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 1 ((reason . missing-api) (path . "$T/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "$T/sticks-then.so") (again (loaded "$T/sticks-then.so") (loaded "$T/sticks-then.so")) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

### The probe's own checks

#### LS23. The probe ignores --then-override

**Guards:** the sticky case really changes CHEZ_CURL_LIBCURL between references.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
-     (putenv "CHEZ_CURL_LIBCURL" path)
```
**Result:** killed, exit 2:

```
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
  expected: (0 0 1 ((reason . missing-api) (path . "$T/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "$T/sticks-then.so") (again same same) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 1 ((reason . missing-api) (path . "$T/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "$T/sticks.so") (again same same) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS24. The probe always reports the marker absent

**Guards:** the marker is seen when its build is loaded, so its absence means something.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
-     (show 'marker (if (foreign-entry? marker) 'present 'absent))))
+     (show 'marker 'absent)))
```
**Result:** killed, exit 2:

```
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
  expected: (0 ((loaded . "$T/marked.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 ((loaded . "$T/marked.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LS25. The probe calls every later reference the same

**Guards:** the probe compares each later reference with the first.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
-   (cond ((eq? (cdr answer) (cdr first)) 'same)
+   (cond (#t 'same)
```
**Result:** killed, exit 2:

```
FAIL a raise that is not a refusal: the probe prints it as raised, and exits 2
  expected: (2 ((raised . "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal") (again (raised "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal") (raised "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal"))) "")
  actual:   (2 ((raised . "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal") (again same same)) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

### NULL strings

#### VN1. A NULL version taken

**Guards:** a NULL version is load-failed, never a record whose version is #f.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-      (or (c-string (ftype-ref curl-version-info-data (version) version-data))
+      (if #t (c-string (ftype-ref curl-version-info-data (version) version-data))
```
**Result:** killed, exit 2:

```
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 0 ((loaded . "$T/version-null.so") (source . override) (version . #f) (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL31. A NULL string read as "" (rerun)

**Guards:** NULL is #f: ssl_version and host are #f, and a NULL version is refused.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (and (not (zero? address))
+     (if (zero? address) ""
```
**Result:** killed, exit 2:

```
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 0 ((loaded . "$T/version-null.so") (source . override) (version . "") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

### The record, in a process of its own

#### NT1. loaded-libcurl answers the record in a list

**Guards:** loaded-libcurl answers a libcurl-info.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define (loaded-libcurl) info))
+   (define (loaded-libcurl) (list info)))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 255 () "Exception in libcurl-info-path: (#[#{libcurl-info gfv7h0zvtu5rtmuc8wws5qz0m-18} \"$T/accepted.so\" override \"7.85.0\" 480512 1073807373 (ipv6 ssl libz http2 threadsafe) \"DecoyTLS/1.0\" \"decoy-host\"]) is not of type #<record type libcurl-info>\n")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 255 () "Exception in libcurl-info-path: (#[#{libcurl-info itj8saf6r3k81nqhy6ygjr3rl-18} \"$T/ssl-null.so\" override \"7.85.0\" 480512 1073807373 (ipv6 ssl libz http2 threadsafe) #f \"decoy-host\"]) is not of type #<record type libcurl-info>\n")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 255 () "Exception in libcurl-info-path: (#[#{libcurl-info ea5vg4fjfjx3m8ofh8dv9z8t8-18} \"$T/host-null.so\" override \"7.85.0\" 480512 1073807373 (ipv6 ssl libz http2 threadsafe) \"DecoyTLS/1.0\" #f]) is not of type #<record type libcurl-info>\n")
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL the real libcurl: the probe, in this environment, loads one by absolute path
FAIL the C oracle read the real libcurl
FAIL the real libcurl: the probe's version is the C oracle's
FAIL the real libcurl: the probe's version-num is the C oracle's
FAIL the real libcurl: the probe's features is the C oracle's
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL loaded-libcurl answers a libcurl-info
FAIL loaded-libcurl answers the same record at every call
FAIL the C oracle read the loaded libcurl
FAIL the record's version is the C oracle's
FAIL the record's version-num is the C oracle's
FAIL the record's features is the C oracle's
FAIL the record's ssl-version is the C oracle's
FAIL the record's host is the C oracle's
test: FAIL tests/test-native.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### NT2. loaded-libcurl answers a fresh copy at each call

**Guards:** loaded-libcurl answers the one record the load built.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define (loaded-libcurl) info))
+   (define (loaded-libcurl)
+     (make-libcurl-info (libcurl-info-path info) (libcurl-info-source info)
+                        (libcurl-info-version info) (libcurl-info-version-number info)
+                        (libcurl-info-features info) (libcurl-info-feature-names info)
+                        (libcurl-info-ssl-version info) (libcurl-info-host info))))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again (loaded "$T/accepted.so") (loaded "$T/accepted.so")) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again (loaded "$T/ssl-null.so") (loaded "$T/ssl-null.so")) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again (loaded "$T/host-null.so") (loaded "$T/host-null.so")) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL loaded-libcurl answers the same record at every call
test: FAIL tests/test-native.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

### The C oracle

#### NL32. host and ssl_version swapped in the ftype (rerun)

**Guards:** the ftype reads each field at its own offset.
**Mutation:** In `src/curl/private/native.sls`:

```diff
+       (ssl-version uptr)
+       (features unsigned-int)
-       (features unsigned-int)
-       (ssl-version uptr)
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "decoy-host") (host . "DecoyTLS/1.0") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "decoy-host") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "DecoyTLS/1.0") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL the record's ssl-version is the C oracle's
FAIL the record's host is the C oracle's
test: FAIL tests/test-native.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### NL34. The features read from version_num (rerun)

**Guards:** the features word is read from its own field.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-      (let ((features (ftype-ref curl-version-info-data (features) version-data)))
+      (let ((features (ftype-ref curl-version-info-data (version-num) version-data)))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/accepted.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/accepted.so" override "7.85.0" 480512 480512 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/ssl-null.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/ssl-null.so" override "7.85.0" 480512 480512 #f "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/host-null.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/host-null.so" override "7.85.0" 480512 480512 "DecoyTLS/1.0" #f) (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe, in this environment, loads one by absolute path
FAIL the C oracle read the real libcurl
FAIL the real libcurl: the probe's version is the C oracle's
FAIL the real libcurl: the probe's version-num is the C oracle's
FAIL the real libcurl: the probe's features is the C oracle's
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
test: FAIL tests/test-library-loading.sps (exit 1)
Exception in chez-curl: libcurl 8.20.0 was built without SSL; name another with CHEZ_CURL_LIBCURL with irritant "$P/lib/libcurl.so.4"
test: FAIL tests/test-native.sps (exit 255)
test: ran 9, passed 7, failed 2, hung 0
```

#### NL37. The features word read without its IPv6 bit

**Guards:** the record holds the features word as read.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-      (let ((features (ftype-ref curl-version-info-data (features) version-data)))
+      (let ((features (bitwise-and (ftype-ref curl-version-info-data (features) version-data)
+                                   (bitwise-not 1))))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807372) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807372) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807372) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe's features is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL the record's features is the C oracle's
test: FAIL tests/test-native.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### NL38. version_num read one high

**Guards:** the record holds version_num as read.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-         (ftype-ref curl-version-info-data (version-num) version-data)
+         (+ 1 (ftype-ref curl-version-info-data (version-num) version-data))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480513) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480513) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480513) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe's version-num is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL the record's version-num is the C oracle's
test: FAIL tests/test-native.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### NL39. The version read from the host field

**Guards:** the record holds the version string as read.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-      (or (c-string (ftype-ref curl-version-info-data (version) version-data))
+      (or (c-string (ftype-ref curl-version-info-data (host) version-data))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "decoy-host") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "decoy-host") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/host-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe's version is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL the record's version is the C oracle's
test: FAIL tests/test-native.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### NL35. The record built with ssl_version and host swapped (rerun)

**Guards:** each record field holds its own value.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-         (c-string (ftype-ref curl-version-info-data (ssl-version) version-data))
-         (c-string (ftype-ref curl-version-info-data (host) version-data))))))
+         (c-string (ftype-ref curl-version-info-data (host) version-data))
+         (c-string (ftype-ref curl-version-info-data (ssl-version) version-data))))))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "decoy-host") (host . "DecoyTLS/1.0") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "decoy-host") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "DecoyTLS/1.0") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL the record's ssl-version is the C oracle's
FAIL the record's host is the C oracle's
test: FAIL tests/test-native.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### OR1. The oracle reads the features from version_num

**Guards:** the C oracle and the native layer are compared field by field: a disagreement fails.
**Mutation:** In `tests/libcurl-oracle.c`:

```diff
-   printf("(features . %u)\n", (unsigned int)data->features);
+   printf("(features . %u)\n", (unsigned int)data->version_num);
```
**Result:** killed, exit 2:

```
FAIL the real libcurl: the probe's features is the C oracle's
  expected: (features . 529408)
  actual:   (features . 1430210445)
FAIL the real libcurl through the override: loaded, with the C oracle's report
  expected: (0 ((loaded . "$P/lib/libcurl.so.4") (source . override) (version . "8.20.0") (version-num . 529408) (features . 529408) (ssl-version . "GnuTLS/3.8.13") (host . "x86_64-unknown-linux-gnu") (again same same)) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . override) (version . "8.20.0") (version-num . 529408) (features . 1430210445) (ssl-version . "GnuTLS/3.8.13") (host . "x86_64-unknown-linux-gnu") (again same same)) "")
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
  expected: (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (version-num . 529408) (features . 529408) (ssl-version . "GnuTLS/3.8.13") (host . "x86_64-unknown-linux-gnu") (again same same)) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (version-num . 529408) (features . 1430210445) (ssl-version . "GnuTLS/3.8.13") (host . "x86_64-unknown-linux-gnu") (again same same)) "")
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL the record's features is the C oracle's
test: FAIL tests/test-native.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### OR2. CC not split

**Guards:** CC is cut at whitespace, so CC='ccache gcc' works.
**Mutation:** In `tests/libcurl-oracle.sls`:

```diff
-       (if (null? words) '("cc") words)))
+       (if (null? words) '("cc") (list (or (getenv "CC") "cc")))))
```
**Result:** killed, exit 2:

```
FAIL CC is cut at whitespace, so CC='ccache gcc' runs ccache, with gcc as its argument
  expected: (("ccache" "gcc") ("gcc" "-m64") ("cc") ("cc"))
  actual:   ((" ccache\tgcc ") ("gcc -m64") ("cc") ("cc"))
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### OR3. The oracle never compiled: no headers

**Guards:** a failed oracle compile fails the real-library cases by name, never skips them.
**Mutation:** In `tests/libcurl-oracle.c`:

```diff
- #include <curl/curl.h>
+ #include <curl/no-such-header.h>
```
**Result:** killed, exit 2:

```
FAIL the C oracle read the real libcurl
  expected: read
  actual:   (no-oracle compile (1 "" "tests/libcurl-oracle.c:26:10: fatal error: curl/no-such-header.h: No such file or directory\n   26 | #include <curl/no-such-header.h>\n      |          ^~~~~~~~~~~~~~~~~~~~~~~\ncompilation terminated.\n"))
FAIL the real libcurl: the probe's version is the C oracle's
  expected: (version no-oracle)
  actual:   (version . "8.20.0")
FAIL the real libcurl: the probe's version-num is the C oracle's
  expected: (version-num no-oracle)
  actual:   (version-num . 529408)
FAIL the real libcurl: the probe's features is the C oracle's
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL the C oracle read the loaded libcurl
FAIL the record's version is the C oracle's
FAIL the record's version-num is the C oracle's
FAIL the record's features is the C oracle's
FAIL the record's ssl-version is the C oracle's
FAIL the record's host is the C oracle's
test: FAIL tests/test-native.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### ST1. CHEZ_CURL_LIBCURL unset for make test (rerun)

**Guards:** the real-library cases take their path from what the probe loaded, so they hold with the override unset.
**Mutation:** none to the tree. The command was `unset CHEZ_CURL_LIBCURL; make test && make build`.
**Result:** passed, as expected: exit 0, and `make test` printed `test: ran 9, passed 9, failed 0, hung 0`.

#### ST2. CC as two words, 'env' and the compiler

**Guards:** every compile runs $CC's words: the decoys' and the oracle's.
**Mutation:** none to the tree. The command was `CC="env $CC" make test`.
**Result:** passed, as expected: exit 0, and `make test` printed `test: ran 9, passed 9, failed 0, hung 0`.

### Discovery, by platform and then world

#### DS1. The platform read as macOS

**Guards:** the macOS branch asserts that discovery loads Apple's library.
**Mutation:** In `tests/test-library-loading.sps`:

```diff
-     (cond ((string-suffix? "le" name) 'linux)
+     (cond ((string-suffix? "le" name) 'macos)
```
**Result:** killed, exit 2:

```
FAIL macos: with the override unset, discovery loads Apple's /usr/lib/libcurl.4.dylib
  expected: (0 ((loaded . "/usr/lib/libcurl.4.dylib") (source . macos-system) no-oracle run (1 "" "libcurl-oracle: /usr/lib/libcurl.4.dylib: cannot open shared object file: No such file or directory\n") (again same same)) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (version-num . 529408) (features . 1430210445) (ssl-version . "GnuTLS/3.8.13") (host . "x86_64-unknown-linux-gnu") (again same same)) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### DS2. The world read as FHS

**Guards:** the FHS branch asserts that discovery loads the first standard candidate, source system.
**Mutation:** In `tests/test-library-loading.sps`:

```diff
- (define world (libcurl-world (if (string? real-maps) real-maps #f)))
+ (define world 'fhs)
```
**Result:** killed, exit 2:

```
FAIL fhs: with the override unset, discovery loads the first standard candidate that exists, source system
  expected: (0 ((loaded . #f) (source . system) no-oracle no-path #f (again same same)) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (version-num . 529408) (features . 1430210445) (ssl-version . "GnuTLS/3.8.13") (host . "x86_64-unknown-linux-gnu") (again same same)) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### DS3. The platform read as neither

**Guards:** the branch for any other platform asserts not-found, with no candidate.
**Mutation:** In `tests/test-library-loading.sps`:

```diff
-     (cond ((string-suffix? "le" name) 'linux)
+     (cond ((string-suffix? "le" name) 'other)
```
**Result:** killed, exit 2:

```
FAIL another platform: with the override unset, not-found, having no candidate
  expected: (1 ((reason . not-found) (path . #f) (source . #f) (detail . #f) (candidates) (library . #f) (again same same)) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-environment) (version . "8.20.0") (version-num . 529408) (features . 1430210445) (ssl-version . "GnuTLS/3.8.13") (host . "x86_64-unknown-linux-gnu") (again same same)) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

### A raise that is not a refusal

#### PR5. The probe's catch-all prints a refusal

**Guards:** the probe reports a raise that is not a refusal as raised, exit 2, never as load-failed.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
-      (show 'raised (text (cdr first)))
-      2)))
+      (show 'reason 'load-failed)
+      1)))
```
**Result:** killed, exit 2:

```
FAIL a raise that is not a refusal: the probe prints it as raised, and exits 2
  expected: (2 ((raised . "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal") (again (raised "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal") (raised "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal"))) "")
  actual:   (1 ((reason . load-failed) (again (raised "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal") (raised "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal"))) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### PF8. The preflight gains a catch-all that prints a refusal

**Guards:** a raise that is not a refusal reaches Chez's default handler, with no reason line.
**Mutation:** In `tests/preflight.sps`:

```diff
-              (exit 1))))
+              (exit 1)))
+            (#t (let ((err (current-error-port)))
+                  (say err "chez-curl: libcurl refused")
+                  (write '(reason . load-failed) err)
+                  (newline err)
+                  (exit 1))))
```
**Result:** killed, exit 2:

```
FAIL preflight, a raise that is not a refusal: Chez's default handler, exit 255, and no reason line
  expected: (255 "" "Exception in loaded-libcurl: the raising fixture raises a plain error, not a refusal\n")
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . load-failed)\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

### The report on a refusal

#### LB1. check-version gets no report

**Guards:** below-floor and no-ssl carry the report.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-                     (libcurl-info-features info) libcurl-path libcurl-source info)))
+                     (libcurl-info-features info) libcurl-path libcurl-source #f)))
```
**Result:** killed, exit 2:

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
  expected: (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       $T/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL\n")
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       $T/below-floor.so\n  source:     override\n  detail:     7.84.0\n  candidates: none\n  remedy:     libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LB2. check-apis gets no report

**Guards:** missing-api from a probe carries the report.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-      (check-apis option-found? header-code libcurl-path libcurl-source info)))
+      (check-apis option-found? header-code libcurl-path libcurl-source #f)))
```
**Result:** killed, exit 2:

```
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  expected: (0 1 ((reason . missing-api) (path . "$T/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "$T/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
  expected: (0 0 1 ((reason . missing-api) (path . "$T/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "$T/sticks-then.so") (again same same) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 1 ((reason . missing-api) (path . "$T/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library . #f) (then-override . "$T/sticks-then.so") (again same same) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LB3. curl_global_init's refusal carries no report

**Guards:** load-failed from curl_global_init carries the report.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-          (refuse 'load-failed libcurl-path libcurl-source info
+          (refuse 'load-failed libcurl-path libcurl-source #f
```
**Result:** killed, exit 2:

```
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
  expected: (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (library "$T/init-fails.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/init-fails.so") (source . override) (detail . "curl_global_init returned 2") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LB4. A missing entry point bound after the version carries no report

**Guards:** missing-api for an entry point bound after curl_version_info carries the report.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-       (refuse 'missing-api libcurl-path libcurl-source library name
+       (refuse 'missing-api libcurl-path libcurl-source #f name
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_global_init.so") (source . override) (detail . "curl_global_init") (candidates) (library "$T/lacks-curl_global_init.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/lacks-curl_global_init.so") (source . override) (detail . "curl_global_init") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_option_by_name.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/lacks-curl_easy_option_by_name.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_option_by_name.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_init.so") (source . override) (detail . "curl_easy_init") (candidates) (library "$T/lacks-curl_easy_init.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_init.so") (source . override) (detail . "curl_easy_init") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LB5. curl_easy_init's refusal carries no report

**Guards:** load-failed from curl_easy_init carries the report.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-          (refuse 'load-failed libcurl-path libcurl-source info "curl_easy_init returned NULL"
+          (refuse 'load-failed libcurl-path libcurl-source #f "curl_easy_init returned NULL"
```
**Result:** killed, exit 2:

```
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
  expected: (0 1 ((reason . load-failed) (path . "$T/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library "$T/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init()")) "")
  actual:   (0 1 ((reason . load-failed) (path . "$T/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init()")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LB6. verify's refusals drop the report

**Guards:** check-version and check-apis put the report they are given in the refusal.
**Mutation:** In `src/curl/private/verify.sls`:

```diff
-                                                      library)
+                                                      #f)
```
**Result:** killed, exit 2:

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 1 ((reason . missing-api) (path . "$T/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source
FAIL check-version: every feature but SSL is no-ssl, with the version, path and source
FAIL check-version: below the floor and without SSL, below-floor wins
FAIL check-apis: no option by name is missing-api, naming curl_easy_option_by_name
FAIL check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header
FAIL check-apis: with both APIs missing, the option probe is named: it runs first
test: FAIL tests/test-verify.sps (exit 1)
test: ran 9, passed 7, failed 2, hung 0
```

#### LB7. The constructor takes any library

**Guards:** a library is a libcurl-info or #f.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
-     (unless (or (not library) (libcurl-info? library))
+     (unless #t
```
**Result:** killed, exit 2:

```
FAIL the constructor refuses a library that is neither a libcurl-info nor #f
  expected: (assertion-violation make-curl-library-unavailable ("8.20.0"))
  actual:   no-raise
test: FAIL tests/test-conditions.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LB8. (curl) does not export curl-library-unavailable-library

**Guards:** (curl) exports the refusal's library accessor.
**Mutation:** In `src/curl.sls`:

```diff
-    curl-library-unavailable-candidates curl-library-unavailable-library
+    curl-library-unavailable-candidates
```
**Result:** killed, exit 2:

```
FAIL (curl) exports loaded-libcurl, the info record's accessors and the conditions
  expected: (&curl-error &curl-library-unavailable &curl-wrong-thread curl-error? curl-library-unavailable-candidates curl-library-unavailable-detail curl-library-unavailable-library curl-library-unavailable-path curl-library-unavailable-reason curl-library-unavailable-reasons curl-library-unavailable-source curl-library-unavailable? curl-wrong-thread-actual curl-wrong-thread-expected curl-wrong-thread-who curl-wrong-thread? libcurl-info-feature-names libcurl-info-features libcurl-info-host libcurl-info-path libcurl-info-source libcurl-info-ssl-version libcurl-info-version libcurl-info-version-number libcurl-info? loaded-libcurl)
  actual:   (&curl-error &curl-library-unavailable &curl-wrong-thread curl-error? curl-library-unavailable-candidates curl-library-unavailable-detail curl-library-unavailable-path curl-library-unavailable-reason curl-library-unavailable-reasons curl-library-unavailable-source curl-library-unavailable? curl-wrong-thread-actual curl-wrong-thread-expected curl-wrong-thread-who curl-wrong-thread? libcurl-info-feature-names libcurl-info-features libcurl-info-host libcurl-info-path libcurl-info-source libcurl-info-ssl-version libcurl-info-version libcurl-info-version-number libcurl-info? loaded-libcurl)
FAIL (curl)'s conditions are (curl private conditions)'s own
  expected: (same same same same same same same same same same same same same same same same)
  actual:   (raised "Exception: attempt to reference unbound identifier curl-library-unavailable-library")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LB9. The preflight never prints the report of a refusal

**Guards:** make build names the version, TLS backend and features of a library it refused.
**Mutation:** In `tests/preflight.sps`:

```diff
-                (when library
+                (when #f
```
**Result:** killed, exit 2:

```
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
  expected: (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       $T/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL\n")
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       $T/below-floor.so\n  source:     override\n  detail:     7.84.0\n  candidates: none\n  remedy:     libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LB10. (curl) wraps a report accessor of its own

**Guards:** (curl) re-exports the report's accessors, never wraps one.
**Mutation:** In `src/curl.sls`:

```diff
-           (curl private libcurl-info)
-           (curl private native)))
+           (except (curl private libcurl-info) libcurl-info-version)
+           (prefix (only (curl private libcurl-info) libcurl-info-version) private:)
+           (curl private native))
+   (define (libcurl-info-version info) (private:libcurl-info-version info)))
```
**Result:** killed, exit 2:

```
FAIL (curl)'s report accessors are (curl private libcurl-info)'s own
  expected: (same same same same same same same same same)
  actual:   (same same same different same same same same same)
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### LB11. A report accessor that comes from native

**Guards:** the report's accessors live outside native: one of native's would invoke native, whose body raises its refusal again, so a refusal's report could not be read.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (export loaded-libcurl)
+   (export loaded-libcurl libcurl-info-version)
-           (curl private libcurl-info)
+           (except (curl private libcurl-info) libcurl-info-version)
+           (prefix (only (curl private libcurl-info) libcurl-info-version) private:)
-   (define (loaded-libcurl) info))
+   (define (loaded-libcurl) info)
+   (define (libcurl-info-version info) (private:libcurl-info-version info)))
```
**Mutation:** In `src/curl.sls`:

```diff
-           (curl private libcurl-info)
+           (except (curl private libcurl-info) libcurl-info-version)
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception: attempt to reference undefined variable libcurl-info-version at line 238, char 22 of src/curl/private/native.sls") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception: attempt to reference undefined variable libcurl-info-version at line 238, char 22 of src/curl/private/native.sls") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception: attempt to reference undefined variable libcurl-info-version at line 238, char 22 of src/curl/private/native.sls") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe, in this environment, loads one by absolute path
FAIL the C oracle read the real libcurl
FAIL the real libcurl: the probe's version is the C oracle's
FAIL the real libcurl: the probe's version-num is the C oracle's
FAIL the real libcurl: the probe's features is the C oracle's
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
FAIL (curl)'s report accessors are (curl private libcurl-info)'s own
FAIL this suite's own process never loaded libcurl
test: FAIL tests/test-library-loading.sps (exit 1)
Exception: attempt to reference undefined variable libcurl-info-version at line 238, char 22 of src/curl/private/native.sls
test: FAIL tests/test-native.sps (exit 255)
test: ran 9, passed 7, failed 2, hung 0
```

#### CD1. The constructor drops the library

**Guards:** the refusal carries the library it is given.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
-                                              library))
+                                              #f))
```
**Result:** killed, exit 2:

```
FAIL library-unavailable carries its reason, path, source, detail, candidates and library
  expected: (below-floor "/opt/curl/lib/libcurl.so.4" override "libnghttp2.so.14: cannot open shared object file" ("/opt/curl/lib/libcurl.so.4" "/usr/lib/libcurl.so.4") the-report)
  actual:   (below-floor "/opt/curl/lib/libcurl.so.4" override "libnghttp2.so.14: cannot open shared object file" ("/opt/curl/lib/libcurl.so.4" "/usr/lib/libcurl.so.4") #f)
test: FAIL tests/test-conditions.sps (exit 1)
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source
FAIL check-version: every feature but SSL is no-ssl, with the version, path and source
FAIL check-version: below the floor and without SSL, below-floor wins
FAIL check-apis: no option by name is missing-api, naming curl_easy_option_by_name
FAIL check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header
FAIL check-apis: with both APIs missing, the option probe is named: it runs first
test: FAIL tests/test-verify.sps (exit 1)
test: ran 9, passed 6, failed 3, hung 0
```

#### CD2. The constructor refuses #f for the library

**Guards:** a refusal made before the version read carries #f.
**Mutation:** In `src/curl/private/conditions.sls`:

```diff
-     (unless (or (not library) (libcurl-info? library))
+     (unless (libcurl-info? library)
```
**Result:** killed, exit 2:

```
FAIL library-unavailable's library may be #f: no report was read
  expected: no-report
  actual:   #f
FAIL the constructor takes each of the six reasons
  expected: (invalid-override not-found load-failed below-floor no-ssl missing-api)
  actual:   #f
test: FAIL tests/test-conditions.sps (exit 1)
FAIL override: a relative path is invalid-override, carrying the value, with no fallback
  expected: (refused invalid-override #f override "lib/libcurl.so.4" ())
  actual:   (assertion-violation make-curl-library-unavailable)
FAIL override: a bare name is invalid-override
FAIL override: set but empty is invalid-override
FAIL platform: any other has no candidates, so not-found with an empty list
FAIL guix: a standard directory is never chosen, even when every one exists
FAIL fhs: a Guix profile is never chosen, even when every one exists
FAIL not-found lists every path it checked, in order, with no path, source or detail
FAIL choose-libcurl: every refusal carries a who and a message, for the default handler
test: FAIL tests/test-discovery.sps (exit 1)
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 6, failed 3, hung 0
```

### The override's message

#### MS1. The invalid-override message without the discovery remedy

**Guards:** the remedy says the override can be unset.
**Mutation:** In `src/curl/private/discovery.sls`:

```diff
-                  "CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for; set one, or unset it to use discovery"
+                  "CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for"
```
**Result:** killed, exit 2:

```
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for; set one, or unset it to use discovery\n")
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

### Reruns of the logged mutants

#### NL1. curl_global_init before the version check (rerun)

**Guards:** check-version runs before curl_global_init, so a refused library is never initialised.
**Mutation:** In `src/curl/private/native.sls`, `version-checked` moved from before `curl-global-init` to after `global-initialized`:

```diff
@@
  
-   (define version-checked
-     (load-step
-      (check-version (libcurl-info-version info) (libcurl-info-version-number info)
-                     (libcurl-info-features info) libcurl-path libcurl-source info)))
  
@@
         #t)))
+   (define version-checked
+     (load-step
+      (check-version (libcurl-info-version info) (libcurl-info-version-number info)
+                     (libcurl-info-features info) libcurl-path libcurl-source info)))
  
```
**Result:** killed, exit 2:

```
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL2. The options probe before check-version (rerun)

**Guards:** no probe runs before the floor and SSL are checked.
**Mutation:** In `src/curl/private/native.sls`, `curl-easy-option-by-name` and `option-found?` moved from steps 6 and 7 to just after `info`, ahead of `version-checked`:

```diff
@@
          (c-string (ftype-ref curl-version-info-data (host) version-data))))))
+   (define curl-easy-option-by-name
+     (load-step (bind-required "curl_easy_option_by_name" (string) uptr info)))
+   (define option-found?
+     (load-step (not (zero? (curl-easy-option-by-name "URL")))))
  
@@
    ;; const struct curl_easyoption *curl_easy_option_by_name(const char *name)
-   (define curl-easy-option-by-name
-     (load-step (bind-required "curl_easy_option_by_name" (string) uptr info)))
  
@@
    ;; check-apis refuses anything else, since NULL as 0 would be true.
-   (define option-found?
-     (load-step (not (zero? (curl-easy-option-by-name "URL")))))
  
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_global_init(3) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_global_init(3) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_global_init(3) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL3. curl_global_init called twice (rerun)

**Guards:** curl_global_init runs exactly once.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-      (let ((code (curl-global-init curl-global-default)))
+      (let ((code (begin (curl-global-init curl-global-default)
+                         (curl-global-init curl-global-default))))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL4. The probes before curl_global_init (rerun)

**Guards:** curl_global_init runs before the API probes.
**Mutation:** In `src/curl/private/native.sls`, step 5, `curl-global-init` and `global-initialized`, moved from before step 6 to after `header-code`:

```diff
@@
  
-   ;; --- 5. curl_global_init, exactly once ---------------------------------------------
- 
-   ;; CURLcode curl_global_init(long flags)
-   (define curl-global-init (load-step (bind-required "curl_global_init" (long) int info)))
- 
-   (define global-initialized
-     (load-step
-      (let ((code (curl-global-init curl-global-default)))
-        (unless (= code curle-ok)
-          (refuse 'load-failed libcurl-path libcurl-source info
-                  (string-append "curl_global_init returned " (number->string code))
-                  "curl_global_init failed, so this libcurl cannot be used; name another with CHEZ_CURL_LIBCURL"))
-        #t)))
  
@@
           code))))
+   ;; --- 5. curl_global_init, exactly once ---------------------------------------------
+ 
+   ;; CURLcode curl_global_init(long flags)
+   (define curl-global-init (load-step (bind-required "curl_global_init" (long) int info)))
+ 
+   (define global-initialized
+     (load-step
+      (let ((code (curl-global-init curl-global-default)))
+        (unless (= code curle-ok)
+          (refuse 'load-failed libcurl-path libcurl-source info
+                  (string-append "curl_global_init returned " (number->string code))
+                  "curl_global_init failed, so this libcurl cannot be used; name another with CHEZ_CURL_LIBCURL"))
+        #t)))
  
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_global_init(3)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_global_init(3)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle) curl_global_init(3)")) "")
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL5. The foreign-entry? check deleted (rerun)

**Guards:** every required entry point is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (unless (foreign-entry? name)
-       (refuse 'missing-api libcurl-path libcurl-source library name
-               (string-append "the library has no " name
-                              ", so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL"))))
+     #t)
```
**Result:** killed, exit 2:

```
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
  expected: (0 1 ((reason . missing-api) (path . "$T/not-curl.so") (source . override) (detail . "curl_version_info") (candidates) (library . #f) (again same same) (calls . "")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_version_info\"") (again same same) (calls . "")) "")
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_global_init.so") (source . override) (detail . "curl_global_init") (candidates) (library "$T/lacks-curl_global_init.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_global_init\"") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_option_by_name.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/lacks-curl_easy_option_by_name.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_option_by_name\"") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL6. curl_version_info bound without the check (rerun)

**Guards:** curl_version_info is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define curl-version-info (load-step (bind-required "curl_version_info" (int) uptr #f)))
+   (define curl-version-info (load-step (foreign-procedure "curl_version_info" (int) uptr)))
```
**Result:** killed, exit 2:

```
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
  expected: (0 1 ((reason . missing-api) (path . "$T/not-curl.so") (source . override) (detail . "curl_version_info") (candidates) (library . #f) (again same same) (calls . "")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_version_info\"") (again same same) (calls . "")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL7. curl_global_init bound without the check (rerun)

**Guards:** curl_global_init is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define curl-global-init (load-step (bind-required "curl_global_init" (long) int info)))
+   (define curl-global-init (load-step (foreign-procedure "curl_global_init" (long) int)))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_global_init.so") (source . override) (detail . "curl_global_init") (candidates) (library "$T/lacks-curl_global_init.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_global_init\"") (again same same) (calls . "curl_version_info(9)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL8. curl_easy_option_by_name bound without the check (rerun)

**Guards:** curl_easy_option_by_name is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (load-step (bind-required "curl_easy_option_by_name" (string) uptr info)))
+     (load-step (foreign-procedure "curl_easy_option_by_name" (string) uptr)))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_option_by_name.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "$T/lacks-curl_easy_option_by_name.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_option_by_name\"") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL9. curl_easy_init bound without the check (rerun)

**Guards:** curl_easy_init is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define curl-easy-init (load-step (bind-required "curl_easy_init" () uptr info)))
+   (define curl-easy-init (load-step (foreign-procedure "curl_easy_init" () uptr)))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_init.so") (source . override) (detail . "curl_easy_init") (candidates) (library "$T/lacks-curl_easy_init.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_init\"") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL10. curl_easy_header bound without the check (rerun)

**Guards:** curl_easy_header is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-      (bind-required "curl_easy_header" (uptr string size_t unsigned-int int uptr) int info)))
+      (foreign-procedure "curl_easy_header" (uptr string size_t unsigned-int int uptr) int)))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_header.so") (source . override) (detail . "curl_easy_header") (candidates) (library "$T/lacks-curl_easy_header.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_header\"") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL11. curl_easy_cleanup bound without the check (rerun)

**Guards:** curl_easy_cleanup is asked of foreign-entry? before it is bound.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-   (define curl-easy-cleanup (load-step (bind-required "curl_easy_cleanup" (uptr) void info)))
+   (define curl-easy-cleanup (load-step (foreign-procedure "curl_easy_cleanup" (uptr) void)))
```
**Result:** killed, exit 2:

```
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
  expected: (0 1 ((reason . missing-api) (path . "$T/lacks-curl_easy_cleanup.so") (source . override) (detail . "curl_easy_cleanup") (candidates) (library "$T/lacks-curl_easy_cleanup.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
  actual:   (0 2 ((raised . "Exception in foreign-procedure: no entry for \"curl_easy_cleanup\"") (again same same) (calls . "curl_version_info(9) curl_global_init(3)")) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### NL12. The option probe passes the pointer, not a boolean (rerun)

**Guards:** check-apis gets a boolean: NULL as 0 would be true.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-     (load-step (not (zero? (curl-easy-option-by-name "URL")))))
+     (load-step (curl-easy-option-by-name "URL")))
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception in check-apis: the option probe's answer is not a boolean with irritant 123812462255552") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception in check-apis: the option probe's answer is not a boolean with irritant 130361457470912") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 2 ((raised . "Exception in check-apis: the option probe's answer is not a boolean with irritant 133937145032128") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL the real libcurl: the probe, in this environment, loads one by absolute path
FAIL the C oracle read the real libcurl
FAIL the real libcurl: the probe's version is the C oracle's
FAIL the real libcurl: the probe's version-num is the C oracle's
FAIL the real libcurl: the probe's features is the C oracle's
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
test: FAIL tests/test-library-loading.sps (exit 1)
Exception in check-apis: the option probe's answer is not a boolean with irritant 128378973008536
test: FAIL tests/test-native.sps (exit 255)
test: ran 9, passed 7, failed 2, hung 0
```

#### NL25. A failed load falls back to the next candidate (rerun)

**Guards:** after a failed load no other candidate is tried (ADR-0002, decision 3). Only discovery's choice falls back here; the override still refuses.
**Mutation:** In `src/curl/private/native.sls`:

```diff
-      (guard (e (#t (refuse 'load-failed libcurl-path libcurl-source #f (loader-message e)
-                            "the loader refused this libcurl; name one this Chez can load with CHEZ_CURL_LIBCURL, an absolute path")))
+      (guard (e (#t (if (eq? libcurl-source 'override)
+                        (refuse 'load-failed libcurl-path libcurl-source #f (loader-message e)
+                                "the loader refused this libcurl; name one this Chez can load with CHEZ_CURL_LIBCURL, an absolute path")
+                        (let ((failed libcurl-path))
+                          (let-values (((path source)
+                                        (choose-libcurl getenv (machine-type) (maps-text)
+                                                        (lambda (p) (and (not (string=? p failed))
+                                                                         (regular-file? p))))))
+                            (set! libcurl-path path)
+                            (set! libcurl-source source)
+                            (load-shared-object path)
+                            #t)))))
```
**Result:** killed, exit 2:

```
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
  expected: (1 ((reason . load-failed) (path . "$T/broken-profile/lib/libcurl.so.4") (source . guix-environment) (detail . "(while loading $T/broken-profile/lib/libcurl.so.4) $T/broken-profile/lib/libcurl.so.4: file too short") (candidates) (library . #f) (again same same)) "")
  actual:   (0 ((loaded . "$P/lib/libcurl.so.4") (source . guix-profile) (version . "8.20.0") (version-num . 529408) (features . 1430210445) (ssl-version . "GnuTLS/3.8.13") (host . "x86_64-unknown-linux-gnu") (again same same)) "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### CU1. libcurl-info-host not exported (rerun)

**Guards:** (curl) exports every accessor of the report.
**Mutation:** In `src/curl.sls`:

```diff
-    libcurl-info-ssl-version libcurl-info-host
+    libcurl-info-ssl-version
```
**Result:** killed, exit 2:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "$T/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 255 () "Exception: attempt to reference unbound identifier libcurl-info-host\n")
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "$T/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 255 () "Exception: attempt to reference unbound identifier libcurl-info-host\n")
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "$T/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version_info(9) curl_global_init(3) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")
  actual:   (0 255 () "Exception: attempt to reference unbound identifier libcurl-info-host\n")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL the real libcurl: the probe, in this environment, loads one by absolute path
FAIL the C oracle read the real libcurl
FAIL the real libcurl: the probe's version is the C oracle's
FAIL the real libcurl: the probe's version-num is the C oracle's
FAIL the real libcurl: the probe's features is the C oracle's
FAIL the real libcurl: the probe's ssl-version is the C oracle's
FAIL the real libcurl: the probe's host is the C oracle's
FAIL the real libcurl through the override: loaded, with the C oracle's report
FAIL guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
FAIL (curl) exports loaded-libcurl, the info record's accessors and the conditions
FAIL (curl)'s report accessors are (curl private libcurl-info)'s own
test: FAIL tests/test-library-loading.sps (exit 1)
Exception: attempt to reference unbound identifier libcurl-info-host at line 53, char 20 of tests/test-native.sps
test: FAIL tests/test-native.sps (exit 255)
test: ran 9, passed 7, failed 2, hung 0
```

#### PR1. The probe imports (curl), and its guard comes too late (rerun)

**Guards:** the probe forces (curl)'s body inside its guard, so a refusal is printed, never escapes.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
-         (curl private conditions))
+         (curl private conditions)
+         (curl))
-     (cons 'loaded (eval '(loaded-libcurl) (environment '(rnrs) '(curl))))))
+     (cons 'loaded (loaded-libcurl))))
```
**Result:** killed, exit 2:

```
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 255 () "Exception in chez-curl: curl_version_info returned no version string, so this libcurl cannot say what it is; name another with CHEZ_CURL_LIBCURL with irritant \"$T/version-null.so\"\n")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 255 () "Exception in chez-curl: libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL with irritant \"$T/below-floor.so\"\n")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 255 () "Exception in chez-curl: libcurl 7.85.0 was built without SSL; name another with CHEZ_CURL_LIBCURL with irritant \"$T/no-ssl.so\"\n")
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### PR2. The probe catches a refusal as any other raise (rerun)

**Guards:** a refusal prints its reason and fields.
**Mutation:** In `tests/refusal-probe.sps`:

```diff
-   (guard (e ((curl-library-unavailable? e) (cons 'refused e))
+   (guard (e ((and #f (curl-library-unavailable? e)) (cons 'refused e))
```
**Result:** killed, exit 2:

```
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "$T/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in chez-curl: curl_version_info returned no version string, so this libcurl cannot say what it is; name another with CHEZ_CURL_LIBCURL with irritant \"$T/version-null.so\"") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "$T/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "$T/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in chez-curl: libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL with irritant \"$T/below-floor.so\"") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "$T/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "$T/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same same) (calls . "curl_version_info(9)")) "")
  actual:   (0 2 ((raised . "Exception in chez-curl: libcurl 7.85.0 was built without SSL; name another with CHEZ_CURL_LIBCURL with irritant \"$T/no-ssl.so\"") (again same same) (calls . "curl_version_info(9)")) "")
FAIL decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it
FAIL decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it
FAIL decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it
FAIL decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it
FAIL decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it
FAIL decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it
FAIL a bare name in the override is invalid-override, carrying it
FAIL a text file is load-failed, with the loader's message
FAIL a path that does not exist is load-failed, with the loader's message
FAIL guix: with no profile to search, not-found lists every candidate checked
FAIL guix: a candidate that fails to load is load-failed, and the next is never tried
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### PF1. The preflight exits 0 after a refusal (rerun)

**Guards:** make build fails when libcurl is refused.
**Mutation:** In `tests/preflight.sps`:

```diff
-              (exit 1))))
+              (exit 0))))
```
**Result:** killed, exit 2:

```
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for; set one, or unset it to use discovery\n")
  actual:   (0 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for; set one, or unset it to use discovery\n")
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
  expected: (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       $T/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL\n")
  actual:   (0 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       $T/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL\n")
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
  expected: (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
  actual:   (0 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### PF2. The preflight exits 1 after a load (rerun)

**Guards:** make build passes when libcurl is accepted.
**Mutation:** In `tests/preflight.sps`:

```diff
-     (exit 0)))
+     (exit 1)))
```
**Result:** killed, exit 2:

```
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  expected: (0 "chez-curl: libcurl loaded and accepted\n  path:     $T/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")
  actual:   (1 "chez-curl: libcurl loaded and accepted\n  path:     $T/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")
FAIL preflight, the real libcurl: exit 0, with the C oracle's report
  expected: (0 "chez-curl: libcurl loaded and accepted\n  path:     $P/lib/libcurl.so.4 (override)\n  version:  8.20.0\n  TLS:      GnuTLS/3.8.13\n  features: ipv6 ssl libz asynchdns spnego largefile idn tlsauth-srp http2 gssapi kerberos5 unix-sockets psl https-proxy altsvc zstd hsts threadsafe\n  host:     x86_64-unknown-linux-gnu\n" "")
  actual:   (1 "chez-curl: libcurl loaded and accepted\n  path:     $P/lib/libcurl.so.4 (override)\n  version:  8.20.0\n  TLS:      GnuTLS/3.8.13\n  features: ipv6 ssl libz asynchdns spnego largefile idn tlsauth-srp http2 gssapi kerberos5 unix-sockets psl https-proxy altsvc zstd hsts threadsafe\n  host:     x86_64-unknown-linux-gnu\n" "")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

#### PF3. The preflight's guard comes too late (rerun)

**Guards:** the preflight forces (curl)'s body inside its guard, so a refusal gets its reason and remedy.
**Mutation:** In `tests/preflight.sps`:

```diff
-         (curl private conditions))
+         (curl private conditions)
+         (curl))
-   (let ((report (eval '(let ((info (loaded-libcurl)))
+   (let ((report (let ((info (loaded-libcurl)))
-                                (libcurl-info-host info)))
-                       (environment '(rnrs) '(curl))))
+                                (libcurl-info-host info))))
```
**Result:** killed, exit 2:

```
FAIL preflight, a bare name: exit 1, refused as invalid-override, with the remedy
  expected: (1 "" "chez-curl: libcurl refused\n(reason . invalid-override)\n  path:       none\n  source:     override\n  detail:     libcurl.so.4\n  candidates: none\n  remedy:     CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for; set one, or unset it to use discovery\n")
  actual:   (255 "" "Exception in chez-curl: CHEZ_CURL_LIBCURL must be an absolute path to libcurl, which is loaded as given and never searched for; set one, or unset it to use discovery with irritant \"libcurl.so.4\"\n")
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
  expected: (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       $T/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL\n")
  actual:   (255 "" "Exception in chez-curl: libcurl 7.84.0 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL with irritant \"$T/below-floor.so\"\n")
FAIL preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line
  expected: (1 "" "chez-curl: libcurl refused\n(reason . not-found)\n  path:       none\n  source:     none\n  detail:     none\n  candidates:\n    $T/home/.guix-home/profile/lib/libcurl.so.4\n    $T/home/.guix-profile/lib/libcurl.so.4\n    /run/current-system/profile/lib/libcurl.so.4\n  remedy:     no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path\n")
  actual:   (255 "" "Exception in chez-curl: no libcurl found among the candidates; name one with CHEZ_CURL_LIBCURL, an absolute path with irritant (\"$T/home/.guix-home/profile/lib/libcurl.so.4\" \"$T/home/.guix-profile/lib/libcurl.so.4\" \"/run/current-system/profile/lib/libcurl.so.4\")\n")
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 9, passed 8, failed 1, hung 0
```

### Clean rerun

After the last change to any source, suite, probe, fixture or the decoy, on the working tree:

- `scripts/guix-env sh -c 'make test && make check-test-fails && make build'` exited 0. `make
  test` ended `test: ran 9, passed 9, failed 0, hung 0`, `check-test-fails` ended
  `check-test-fails: make test failed, as it must, in all 9 cases`, and `make build` printed the
  baseline's report.
- `make check-guix`, on the host, ended `check-guix: ALL CHECKS PASSED`.

### Findings

- **A library body's raise either re-runs it or wedges it.** Measured above. `load-step` makes
  every raise serious, and `(curl private load-state)` keeps the first, so native's body raises
  the same refusal at every reference and nothing runs twice.
- **A NULL `version` was accepted, not refused.** See the red run for item 2. The native layer's
  Not covered entry expected an assertion violation from `check-version`'s message, but that
  message is built only on a refusal, and a NULL version at the floor with SSL is not one.
- **A refusal's report is readable only because its accessors live outside native.** LB11 gave
  native an accessor of its own and `(curl)` took it from there. Reading a refusal's report then
  referenced native, whose body raised the refusal again inside the probe's handler, and every
  refusal that carries a report escaped with exit 255. Hence `(curl private libcurl-info)`.
- **A definition in `(curl)` invokes only what its body references.** LB10 gave `(curl)` a
  wrapper of its own around `libcurl-info-version`. Referencing it did not invoke native, so no
  refusal escaped, and only the identity test failed. This extends the native layer's finding
  that evaluating a re-exported binding runs only the library that defines it.
- **`record-load-failure!`'s check backs up `as-serious`.** With `as-serious` disabled (LS3, LS4)
  the library still never wedged: `record-load-failure!` refused the bare symbol with an
  assertion violation, which is serious, carrying the symbol. Only LS30, `load-step` taken away
  whole, wedged the fixture library.
- **A suite's top-level definitions run before its first test.** NT1 made `loaded-libcurl`
  answer a list. `tests/test-native.sps` first died at `(libcurl-info-path info)` in its oracle's
  definition, exit 255, with no test named. The definition now reads a path only from a record,
  and NT1 fails the suite's tests by name.
- **The preflight makes one reference, so it cannot see a load that runs twice.** LS13 took
  `load-step` from the floor check. The decoy cases failed by name and the preflight's
  below-floor case passed.
- **The features word now feeds the floor check, so NL34 changed shape.** Read from
  `version_num`, the real library's word lacked `CURL_VERSION_SSL`, so it was refused as `no-ssl`
  and `test-native.sps` died at import. NL37 to NL39 change one field each and leave the library
  acceptable, so `test-native.sps` names the field.
- **The memory gate will see a leak that is not chez-curl's.** Run once by hand under the
  ADR-0014 command, `test-native.sps` passed its 8 tests and Valgrind exited 9: `171 bytes in 1
  blocks are definitely lost`, allocated by `newlocale` in p11-kit's constructor, run by
  `dlopen` when GnuTLS's libcurl loads. The same command on an empty program reported no error.
  ADR-0014 allows no suppression file, so slice 5 needs a decision.
- **Guix's `gcc` builds and runs a `dlopen` program with `-ldl`.** The oracle compiled and ran
  in the container. glibc 2.41 has `dlopen` in libc; `-ldl` links its stub.
- **`(rnrs)`'s `command-line` under `--program`** answers the program's path, then its
  arguments: `("args.sps" "--then-override" "/x" "--marker" "m")`.

### Not covered

- **LS12 and LS20 survive, as expected.** `info` and `option-found?` run inside `load-step`, but
  neither can raise, so nothing can tell. `libcurl-path` and `libcurl-source` are not wrapped at
  all: they take the car and cdr of `chosen`.
- **Two threads making the first reference at once.** The reviewer's `t.sps` showed the second
  thread gets `cyclic dependency` while the first is still loading. Recorded for M3; not fixed.
- **The branches for macOS, FHS and any other platform** run only there. DS1 to DS3 force each
  in the container, where each fails as it must. The FHS branch first runs for real in slice 5's
  Linux CI. The macOS branch runs only on a maintainer's Mac: AGENTS.md rules out macOS CI.
- **The oracle on macOS.** `-ldl` and `dlopen` of Apple's library from the dyld shared cache are
  unmeasured.
- **A `&warning` raised continuably inside a step** now aborts the load: `load-step`'s guard
  catches everything. No step raises one today.
- **The header probe's `foreign-free`.** `test-native.sps` runs it in-process for the memory
  gate, which is subject to the p11-kit finding above.
- **The record's `feature-names`** is not compared with the oracle. It is derived from the
  features word, which is, by `feature-names`, which `tests/test-verify.sps` holds to curl.h.
- **`capture-command`'s capture files** still use fixed-pattern names in `$TMPDIR` (slice 2's
  carry-forward). The oracle's files go under its own `mktemp -d`.
- **Other platforms.** Every run was Linux, amd64, in the container.

### Coverage

Every test these fixes added or changed, with the mutants that failed it by name.

**`test-library-loading`**

| Test | Failed by |
|---|---|
| CC is cut at whitespace, so CC='ccache gcc' runs ccache, with gcc as its argument | OR2 |
| decoy accepted: the control loads, calling curl_global_init exactly once, after the version | LS26, LS27, NT1, NT2, NL32, NL34, NL37, NL38, NL39, NL35, LB11, NL2, NL3, NL4, NL12, CU1 |
| decoy ssl-null: a NULL ssl_version is reported as #f | LS26, LS27, NL31, NT1, NT2, NL32, NL34, NL37, NL38, NL39, NL35, LB11, NL2, NL3, NL4, NL12, CU1 |
| decoy host-null: a NULL host is reported as #f | LS26, LS27, NL31, NT1, NT2, NL32, NL34, NL37, NL38, NL39, NL35, LB11, NL2, NL3, NL4, NL12, CU1 |
| decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info | LS1, LS2, LS26, LS27, LS28, LS30, LS11, VN1, NL31, NL39, CD2, PR1, PR2 |
| decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info | LS1, LS2, LS26, LS27, LS28, LS30, LS13, NL32, NL34, NL37, NL38, NL39, NL35, LB1, LB6, LB11, CD1, NL1, NL2, CU1, PR1, PR2 |
| decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info | LS1, LS2, LS26, LS27, LS28, LS30, LS13, NL32, NL34, NL37, NL38, NL39, NL35, LB1, LB6, LB11, CD1, NL1, NL2, CU1, PR1, PR2 |
| decoy version-info-null: curl_version_info answering NULL is load-failed, and nothing runs after it | LS1, LS2, LS26, LS27, LS28, LS30, LS10, CD2, PR1, PR2 |
| decoy init-fails: curl_global_init failing is load-failed, naming its code, and no probe runs | LS1, LS2, LS26, LS27, LS28, LS30, LS15, NL32, NL34, NL37, NL38, NL39, NL35, LB3, LB11, CD1, NL2, NL3, NL4, CU1, PR1, PR2 |
| decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name | LS1, LS2, LS26, LS27, LS28, LS30, LS22, NL32, NL34, NL37, NL38, NL39, NL35, LB2, LB6, LB11, CD1, NL2, NL3, NL4, NL12, CU1, PR1, PR2 |
| decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header | LS1, LS2, LS26, LS27, LS28, LS30, LS22, NL32, NL34, NL37, NL38, NL39, NL35, LB2, LB6, LB11, CD1, NL2, NL3, NL4, NL12, CU1, PR1, PR2 |
| decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs | LS1, LS2, LS26, LS27, LS28, LS30, LS21, NL32, NL34, NL37, NL38, NL39, NL35, LB5, LB11, CD1, NL2, NL3, NL4, CU1, PR1, PR2 |
| decoy not-curl: a library with no curl_* function is missing-api, naming curl_version_info | LS1, LS2, LS26, LS27, LS28, LS30, LS9, CD2, NL5, NL6, PR1, PR2 |
| a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new | LS1, LS2, LS26, LS27, LS28, LS30, LS22, LS23, NL32, NL34, NL37, NL38, NL39, NL35, LB2, LB6, LB11, CD1, NL2, NL3, NL4, NL12, CU1, PR1, PR2 |
| decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry? | LS26, LS27, LS24, NT1, NT2, NL32, NL34, NL37, NL38, NL39, NL35, LB11, NL2, NL3, NL4, NL12, CU1 |
| decoy lacks-curl_global_init: a library without curl_global_init is missing-api, naming it | LS1, LS2, LS26, LS27, LS28, LS30, LS14, NL32, NL34, NL37, NL38, NL39, NL35, LB4, LB11, CD1, NL2, NL4, NL5, NL7, CU1, PR1, PR2 |
| decoy lacks-curl_easy_option_by_name: a library without curl_easy_option_by_name is missing-api, naming it | LS1, LS2, LS26, LS27, LS28, LS30, LS16, NL32, NL34, NL37, NL38, NL39, NL35, LB4, LB11, CD1, NL2, NL3, NL4, NL5, NL8, CU1, PR1, PR2 |
| decoy lacks-curl_easy_init: a library without curl_easy_init is missing-api, naming it | LS1, LS2, LS26, LS27, LS28, LS30, LS17, NL32, NL34, NL37, NL38, NL39, NL35, LB4, LB11, CD1, NL2, NL3, NL4, NL5, NL9, CU1, PR1, PR2 |
| decoy lacks-curl_easy_header: a library without curl_easy_header is missing-api, naming it | LS1, LS2, LS26, LS27, LS28, LS30, LS18, NL32, NL34, NL37, NL38, NL39, NL35, LB4, LB11, CD1, NL2, NL3, NL4, NL5, NL10, CU1, PR1, PR2 |
| decoy lacks-curl_easy_cleanup: a library without curl_easy_cleanup is missing-api, naming it | LS1, LS2, LS26, LS27, LS28, LS30, LS19, NL32, NL34, NL37, NL38, NL39, NL35, LB4, LB11, CD1, NL2, NL3, NL4, NL5, NL11, CU1, PR1, PR2 |
| the real libcurl: the probe, in this environment, loads one by absolute path | LS26, LS27, NT1, NL34, LB11, NL12, CU1 |
| the C oracle read the real libcurl | LS26, LS27, NT1, NL34, OR3, LB11, NL12, CU1 |
| the real libcurl: the probe's version is the C oracle's | LS26, LS27, NT1, NL34, NL39, OR3, LB11, NL12, CU1 |
| the real libcurl: the probe's version-num is the C oracle's | LS26, LS27, NT1, NL34, NL38, OR3, LB11, NL12, CU1 |
| the real libcurl: the probe's features is the C oracle's | LS26, LS27, NT1, NL34, NL37, OR1, OR3, LB11, NL12, CU1 |
| the real libcurl: the probe's ssl-version is the C oracle's | LS26, LS27, NT1, NL32, NL34, NL35, OR3, LB11, NL12, CU1 |
| the real libcurl: the probe's host is the C oracle's | LS26, LS27, NT1, NL32, NL34, NL35, OR3, LB11, NL12, CU1 |
| the real libcurl through the override: loaded, with the C oracle's report | LS26, LS27, NT1, NT2, NL32, NL34, NL37, NL38, NL39, NL35, OR1, OR3, LB11, NL12, CU1 |
| a bare name in the override is invalid-override, carrying it | LS1, LS2, LS26, LS28, LS30, LS7, CD2, PR1, PR2 |
| a text file is load-failed, with the loader's message | LS1, LS2, LS26, LS27, LS28, LS30, LS8, CD2, PR1, PR2 |
| a path that does not exist is load-failed, with the loader's message | LS1, LS2, LS26, LS27, LS28, LS30, LS8, CD2, PR1, PR2 |
| a raise that is not a refusal: the probe prints it as raised, and exits 2 | LS25, PR5 |
| macos: with the override unset, discovery loads Apple's /usr/lib/libcurl.4.dylib | DS1 |
| guix: with the override unset, discovery finds $GUIX_ENVIRONMENT/lib/libcurl.so.4 | LS26, LS27, NT1, NT2, NL32, NL34, NL37, NL38, NL39, NL35, OR1, OR3, LB11, NL12, CU1 |
| guix: with no profile to search, not-found lists every candidate checked | LS1, LS2, LS26, LS28, LS30, LS7, CD2, PR1, PR2 |
| guix: a candidate that fails to load is load-failed, and the next is never tried | LS1, LS2, LS26, LS27, LS28, LS30, LS8, CD2, NL25, PR1, PR2 |
| fhs: with the override unset, discovery loads the first standard candidate that exists, source system | DS2 |
| another platform: with the override unset, not-found, having no candidate | DS3 |
| preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host | LS26, LS27, NT1, NL32, NL34, NL37, NL39, NL35, LB11, NL12, CU1, PF2 |
| preflight, the real libcurl: exit 0, with the C oracle's report | LS26, LS27, NT1, NL32, NL34, NL37, NL39, NL35, OR1, OR3, LB11, NL12, CU1, PF2 |
| preflight, a bare name: exit 1, refused as invalid-override, with the remedy | LS26, LS28, CD2, MS1, CU1, PF1, PF3 |
| preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read | LS26, LS27, LS28, NL32, NL34, NL37, NL39, NL35, LB1, LB6, LB9, LB11, CD1, CU1, PF1, PF3 |
| preflight, a raise that is not a refusal: Chez's default handler, exit 255, and no reason line | PF8 |
| preflight, guix, no profile to search: exit 1, not-found, every candidate on its own line | LS26, LS28, CD2, CU1, PF1, PF3 |
| (curl) exports loaded-libcurl, the info record's accessors and the conditions | LB8, CU1 |
| (curl)'s conditions are (curl private conditions)'s own | LB8 |
| (curl)'s report accessors are (curl private libcurl-info)'s own | LB10, LB11, CU1 |

**`test-native`**

| Test | Failed by |
|---|---|
| loaded-libcurl answers a libcurl-info | NT1 |
| loaded-libcurl answers the same record at every call | NT1, NT2 |
| the C oracle read the loaded libcurl | NT1, OR3 |
| the record's version is the C oracle's | NT1, NL39, OR3 |
| the record's version-num is the C oracle's | NT1, NL38, OR3 |
| the record's features is the C oracle's | NT1, NL37, OR1, OR3 |
| the record's ssl-version is the C oracle's | NT1, NL32, NL35, OR3 |
| the record's host is the C oracle's | NT1, NL32, NL35, OR3 |

**`test-load-state`**

| Test | Failed by |
|---|---|
| nothing is recorded at first | LS26 |
| load-step answers its expression's value, and records nothing | LS26, LS27 |
| as-serious answers a serious condition itself | LS28 |
| as-serious makes a symbol or a number an error from chez-curl, carrying it | LS4 |
| as-serious makes a warning or a bare message an error, carrying it | LS4 |
| load-step raises a symbol made serious, carrying it | LS3, LS4, LS30 |
| load-step records what it raised | LS2, LS3, LS4, LS26, LS30 |
| a later load-step raises its own serious condition, unchanged, and the first stays recorded | LS2, LS3, LS4, LS5, LS26, LS28, LS30 |
| record-load-failure! keeps the first failure | LS2, LS3, LS4, LS5, LS26, LS30 |
| record-load-failure! refuses a condition that is not serious | LS6 |
| Chez wedges a library whose body raised a symbol (the reason for load-step) | LS29 |
| through load-step, the same raise is serious, so the body runs again, never wedged | LS30 |

**`test-conditions`**

| Test | Failed by |
|---|---|
| library-unavailable carries its reason, path, source, detail, candidates and library | CD1 |
| library-unavailable's library may be #f: no report was read | CD2 |
| the constructor refuses a library that is neither a libcurl-info nor #f | LB7 |

**`test-verify`**

| Test | Failed by |
|---|---|
| check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source | LB6, CD1 |
| check-version: every feature but SSL is no-ssl, with the version, path and source | LB6, CD1 |
| check-version: below the floor and without SSL, below-floor wins | LB6, CD1 |
| check-apis: no option by name is missing-api, naming curl_easy_option_by_name | LB6, CD1 |
| check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header | LB6, CD1 |
| check-apis: with both APIs missing, the option probe is named: it runs first | LB6, CD1 |

## Review fixes: check-seam and require-threaded

Evidence for the fixes to the review findings on M0 slice 3's `check-seam` and the
`require-threaded` rule, made on 2026-10-16 ([ADR-0007](decisions/0007-one-repo-checked-seam.md),
[ADR-0001](decisions/0001-bind-libcurl-directly.md) decision 6, [global constraints](global-constraints.md),
"Layout and names"). There are six fixes:

1. **A route round the seam closed.** `import` is a body form when a library imports it from `(chezscheme)`,
   and `include` and `eval` reach other libraries the same way. Rule (c): a library under `src/` may import
   `(chezscheme)` only as `(only (chezscheme) name ...)`, with no name from `forbidden-chez-names`, and
   none may import `(rnrs eval)`. The same list holds for `(scheme)`, which is `(chezscheme)`.
2. **Every library belongs to a family:** the first identifier of its name is `curl` or `http-client`.
   Rule (d). Without it, `(curl x)` imports `(util)`, which imports `(http-client)`.
3. **Files Chez could load that the check does not read are named:** those ending in `.ss`, `.scm`, `.sch`
   or `.chezscheme.sls`, and the compiled `.so` and `.chezscheme.so`.
4. **Emacs lock files are skipped:** a name starting with `.#`.
5. **`require-threaded`'s order rule.** An `(http-client ...)` library satisfies it by importing `(curl)`
   first, since `check-seam` forbids it the refusal itself and `(curl)` imports the refusal first.
6. **The Chez floor.** `(curl private require-threaded)` also refuses, at expansion and by name, a Chez older
   than 10.4.0.

Every mutation was applied to a fresh copy of the working tree, made without `.git`, with `manifest.scm`
touched (`traps.md`, the stale `guix shell -m` profile), in the session scratchpad. The working tree was
never edited by a mutation. The `check-seam` cases are the part 2 driver's: files planted in a copy, the
program run on them, and the exit status and the whole output compared with text written by hand before the
program was changed, never a substring. They run in two layers: `make check-seam` in a fresh copy per case,
and the program on every case in one container call. A **code** mutant (`SM`) breaks `tests/check-seam.sps`
and runs every case against it. The mutants of the order rule's checker (`TM`) and of the refusal (`FR`)
change `tests/test-require-threaded.sps` or `src/curl/private/require-threaded.sls` and run `make test`;
a mutant counts as killed only when `make test` exits non-zero and the suite names the failing row. The
driver refused a mutation whose diff was empty, and a mutation whose target did not occur exactly once.
Every failure is kept verbatim, with one cut: a line over 240 characters is cut, and says how much.

### Corrections and changes to part 2

- **A finding of part 2 was false, and is corrected in place.** It said `import` is no body form in Chez
  10.4, from a probe whose library imported only `(rnrs)`. `(rnrs)` does not export `import`.
  `(chezscheme)` does.
- **Part 2's cases that change.** P1 and M3 imported `(chezscheme)` whole, which rule (c) now refuses, and
  import `(only (chezscheme) format)`. P3 said `(curl-extras)` and `(http-client-extras)` are legal other
  families; rule (d) now fails both, and the case became F2. N3 holds a `src/curl.scm`, which is now named,
  so it prints two problems. Part 2's three "Not covered" bullets about other extensions, a third family
  and run-time imports, and its lock-file bullet, are marked closed.
- **The case ids of this part** are new: `C` (rule c), `F` (families), `EX` (extensions), `K` (lock files),
  and P5 and P6 (legal trees). Mutants: `SM` (the program), `TM` (the order rule's checker), `FR` (the
  refusal), `HC` (the order-rule conflict, reproduced).

### Measured first

Each was measured in the container before any code changed. `(library-extensions)`, `(library-list)` and
`library-exports` are Chez's own.

- **The reviewer's bypass loads, and `check-seam` passes it.** `exp/seam` holds `(curl evil)`, which imports
  `(chezscheme)` and then writes `(import (http-client session))` as a second import clause, `(curl evil2)`,
  which imports `import` from `(chezscheme)` and uses it inside a `let`, and `(http-client session)`.
  Run through `--libdirs`, `(leak)` and `(leak2)` both return `"from http-client"`. Copied into a copy of the
  tree's `src/` and run with the program as it was: `check-seam: the seam holds (10 libraries in 10 files
  checked)`, exit 0.
- **`(scheme)` is `(chezscheme)`.** `(library-list)` holds `(rnrs) (chezscheme) (scheme) ... (rnrs eval)
  ... (chezscheme csv7) (scheme csv7)`. `library-exports` of `(chezscheme)` and of `(scheme)` hold, among
  the names rule (c) cares about, `eval interaction-environment interpret environment import load
  load-library library-directories include`. `(rnrs eval)` holds `environment eval`. No other library of the
  list exports one. `include-library-declarations` is in none: it is a declaration, and is on the list
  anyway.
- **`interpret` and `compile` do what `eval` does.** Libraries importing `(scheme)`, `(only (chezscheme)
  interpret)` and `(only (chezscheme) compile)` each reached `(http-client session)`'s value
  (`(interpret '(begin (import (http-client session)) session-secret))`) and each passed `check-seam`. With
  the others from the reviewer's, five libraries returned `"from http-client"` in one program and the check
  said `the seam holds (6 libraries in 6 files checked)`.
- **`(library-extensions)` is** `((.chezscheme.sls . .chezscheme.so) (.ss . .so) (.sls . .so) (.scm . .so)
  (.sch . .so))`.
- **A `.so` file alone is a library.** `compile-library` wrote `src/curl/real.so` from `real.sls`; with
  `real.sls` moved away, a program importing `(curl real)` loaded the object and printed `"from sls"`. A
  `real.chezscheme.sls` shadowed `real.sls` (the program printed `"from chezscheme.sls"`), and `real.ss`,
  `real.scm` and `real.sch` each loaded.
- **The two rules of `require-threaded`'s order disagree.** Part 1's suite required every library under
  `src/` to import the refusal first, and `check-seam` forbids an `(http-client ...)` library to import it.
  HC1 to HC3 reproduce it below.

### Red runs

**`check-seam`, the 22 new cases and 41 older ones against the program as it was.** That is 63 cases in the
container layer, which skips T1. K4 and the one-character names in P5 came later: K4 after SM58 survived,
and the names with SM62 and SM63. `44 passed, 19 failed`. The 19 that failed:

`C1-reviewer-repro C2-scheme-alias C3-wrappers C4-forbidden-names C5-several-names C6-rnrs-eval C7-http-client-too C8-malformed-only C9-no-family-too EX1-extensions EX2-only-unread EX3-nested-and-link F1-laundering F2-other-families F3-name-anywhere F4-second-library F5-all-three-rules K1-lock-files N3-no-sls`

Eighteen of the 22 new cases fail, and so does N3, which this part changed. P5, P6, K2 and K3 passed: they
say what the check must go on doing, and no change was due to them. P5 and P6 are the legal trees, K3 holds
the lock-file rule to `.#`, and K2 holds a dangling link that is no lock file to being named. The mutants
SM48, SM49, SM62 and SM63 fail P5, SM5, SM6 and SM10 fail P6, SM56 fails K3, and only mutants that break
nearly every case (SM11, SM36, SM46, SM63) fail K2. The head of the output:
```
FAIL C1-reviewer-repro: exit status 0, wanted 1
FAIL C1-reviewer-repro: output
    1,3c1
    < check-seam: src/curl/evil.sls: (curl evil) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: src/curl/evil2.sls: (curl evil2) imports import from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directo [cut 35 characters]
    < check-seam: FAILED (problems: 2)
    ---
    > check-seam: the seam holds (6 libraries in 6 files checked)
FAIL C2-scheme-alias: exit status 0, wanted 1
FAIL C2-scheme-alias: output
    1,2c1
    < check-seam: src/curl/viascheme.sls: (curl viascheme) imports (scheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: FAILED (problems: 1)
    ---
    > check-seam: the seam holds (4 libraries in 4 files checked)
FAIL C3-wrappers: exit status 0, wanted 1
FAIL C3-wrappers: output
    1,10c1
    < check-seam: src/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: src/curl/w2.sls: (curl w2) imports (prefix (chezscheme) c:), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: src/curl/w3.sls: (curl w3) imports (rename (chezscheme) (car kar)), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: src/curl/w4.sls: (curl w4) imports (for (chezscheme) expand), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: src/curl/w5.sls: (curl w5) imports (library (chezscheme)), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: src/curl/w6.sls: (curl w6) imports (for (only (chezscheme) format) expand), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: src/curl/w7.sls: (curl w7) imports (only (prefix (chezscheme) c:) c:format), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: src/curl/w8.sls: (curl w8) imports (only (library (chezscheme)) format), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: src/curl/w9.sls: (curl w9) imports (only (scheme) format), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
    < check-seam: FAILED (problems: 9)
    ---
FAIL C4-forbidden-names: exit status 0, wanted 1
FAIL C4-forbidden-names: output
    1,13c1
    < check-seam: src/curl/n01.sls: (curl n01) imports import from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories [cut 31 characters]
    < check-seam: src/curl/n02.sls: (curl n02) imports include from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directorie [cut 32 characters]
```

**The order rule's rows against the old checker.** The new rows, with `required-first` answering the
refusal for every library, which is what the checker did (TM1):
```
%%%% Starting test require-threaded
FAIL an (http-client ...) library importing (curl) first is first
  expected: first
  actual:   absent
FAIL an (http-client) library is held to the same rule
  expected: first
  actual:   absent
FAIL an (http-client ...) library importing (rnrs) before (curl) is not first
  expected: not-first
  actual:   absent
FAIL an (http-client ...) library without (curl) is absent, even with the refusal first
  expected: (absent absent)
  actual:   (absent first)
FAIL a wrapped or versioned (curl) is the same library
  expected: (first first first)
  actual:   (absent absent absent)
FAIL the refusal asks (scheme-version-number)
  expected: asks
  actual:   never-asks
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
# of expected passes      25
# of unexpected failures  8
suite-exit-status: exit 1 (pass 25, fail 8, xpass 0): a suite needs a pass, and no fail or xpass
```

**The floor's rows against the refusal as it was.** The suite as finished, the library unchanged. The
accepted rows pass: nothing asks for a version yet, so every Chez is accepted.
```
%%%% Starting test require-threaded
FAIL the refusal asks (scheme-version-number)
  expected: asks
  actual:   never-asks
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
# of expected passes      30
# of unexpected failures  3
suite-exit-status: exit 1 (pass 30, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
```

### Legal trees pass

The base of every case is part 2's legal pair, `(curl)` importing `(curl private x)`, and `(http-client)` importing `(curl)`.

#### P5. Files that only look like Chez sources

**Guards:** Only the endings of `(library-extensions)` are named, not any file that looks like one: `.ss.txt`, `.scm.bak`, names like `class` and `also` that end in `ss` and `so` without a dot, one-character names, and a directory named `dir.ss` or `dir.so`, which is entered.
**Mutation:** Files `src/README`, `src/q`, `src/curl/{notes.ss.txt, x.scm.bak, sls, ss, so, also, class, foo.ssx, schemes, .gitkeep, a}`, and two legal libraries in `src/curl/dir.ss/` and `src/curl/dir.so/`.
**Result:** exit 0, and the whole output:
```
check-seam: the seam holds (5 libraries in 5 files checked)
```

#### P6. What rule (c) allows

**Guards:** No false positive: `only` over `(chezscheme)`, with a version, with no name, with names that merely look forbidden (`evaluate`, `interaction-env`, `compile-file`), and the forbidden names imported with `only` from another library.
**Mutation:** Six more libraries: `(only (chezscheme) format display-condition)`, `(only (chezscheme (10 4)) getenv)`, `(only (chezscheme))`, `(only (chezscheme) evaluate load-shared-object interaction-env imported compile-file)`, `(only (curl private x) eval import load)`, and an `(http-client ok6)` importing `(curl)`, `(only (chezscheme) format)` and `(chezscheme csv7)`.
**Result:** exit 0, and the whole output:
```
check-seam: the seam holds (9 libraries in 9 files checked)
```

### Rule (c): `(chezscheme)` and `(rnrs eval)`

#### C1. The reviewer's bypass

**Guards:** Rule (c) on the libraries that passed the check. `(import (chezscheme))` is named for its shape, and `import` for its name. The second import clause of `evil.sls` is not read, and need not be.
**Mutation:** `exp/seam`: `(curl evil)` and `(curl evil2)` as the reviewer wrote them, and `(http-client session)`, over the legal pair.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/evil.sls: (curl evil) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/evil2.sls: (curl evil2) imports import from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: FAILED (problems: 2)
```

#### C2. The alias (scheme)

**Guards:** `(scheme)` is `(chezscheme)`.
**Mutation:** `(curl viascheme)` imports `(scheme)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/viascheme.sls: (curl viascheme) imports (scheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: FAILED (problems: 1)
```

#### C3. Every shape but a plain `only`

**Guards:** Only `(only (chezscheme) name ...)` is accepted: not `except`, `prefix`, `rename`, `for`, `library`, an `only` over one of them, or an `only` over `(scheme)`.
**Mutation:** Nine libraries, `w1` to `w9`, each importing `(chezscheme)` in one of those shapes.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/w2.sls: (curl w2) imports (prefix (chezscheme) c:), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/w3.sls: (curl w3) imports (rename (chezscheme) (car kar)), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/w4.sls: (curl w4) imports (for (chezscheme) expand), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/w5.sls: (curl w5) imports (library (chezscheme)), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/w6.sls: (curl w6) imports (for (only (chezscheme) format) expand), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/w7.sls: (curl w7) imports (only (prefix (chezscheme) c:) c:format), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/w8.sls: (curl w8) imports (only (library (chezscheme)) format), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/w9.sls: (curl w9) imports (only (scheme) format), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: FAILED (problems: 9)
```

#### C4. Each forbidden name

**Guards:** Every name of `forbidden-chez-names` is named, one per library, so dropping one from the list fails this case.
**Mutation:** Twelve libraries, `n01` to `n12`, each `(only (chezscheme) <name>)`, for `import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/n01.sls: (curl n01) imports import from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n02.sls: (curl n02) imports include from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n03.sls: (curl n03) imports include-library-declarations from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n04.sls: (curl n04) imports eval from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n05.sls: (curl n05) imports environment from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n06.sls: (curl n06) imports interaction-environment from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n07.sls: (curl n07) imports load from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n08.sls: (curl n08) imports load-library from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n09.sls: (curl n09) imports library-directories from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n10.sls: (curl n10) imports interpret from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n11.sls: (curl n11) imports compile from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/n12.sls: (curl n12) imports load-program from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: FAILED (problems: 12)
```

#### C5. Several names in one import

**Guards:** Each forbidden name is its own problem, in the order the import lists them, and the legal names around them are not.
**Mutation:** `(only (chezscheme) format load display-condition eval)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/several.sls: (curl several) imports load from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/curl/several.sls: (curl several) imports eval from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: FAILED (problems: 2)
```

#### C6. `(rnrs eval)`

**Guards:** `(rnrs eval)` is refused whole, through every wrapper and with a version.
**Mutation:** Five libraries importing `(rnrs eval)`, `(only (rnrs eval) eval)`, `(for (rnrs eval) expand)`, `(prefix (rnrs eval) e:)` and `(rnrs eval (6))`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/e1.sls: (curl e1) imports (rnrs eval), but no library under src/ may import (rnrs eval)
check-seam: src/curl/e2.sls: (curl e2) imports (rnrs eval), but no library under src/ may import (rnrs eval)
check-seam: src/curl/e3.sls: (curl e3) imports (rnrs eval), but no library under src/ may import (rnrs eval)
check-seam: src/curl/e4.sls: (curl e4) imports (rnrs eval), but no library under src/ may import (rnrs eval)
check-seam: src/curl/e5.sls: (curl e5) imports (rnrs eval), but no library under src/ may import (rnrs eval)
check-seam: FAILED (problems: 5)
```

#### C7. An `(http-client ...)` library

**Guards:** The rule is not for `(curl ...)` alone, and a library with several bad imports gets a problem for each, in import order.
**Mutation:** `(http-client chez)` imports `(curl)`, `(only (chezscheme) eval)`, `(rnrs eval)` and `(chezscheme)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/http-client/chez.sls: (http-client chez) imports eval from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: src/http-client/chez.sls: (http-client chez) imports (rnrs eval), but no library under src/ may import (rnrs eval)
check-seam: src/http-client/chez.sls: (http-client chez) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: FAILED (problems: 3)
```

#### C8. A name that is no identifier

**Guards:** An `only` list holding a number or a string cannot be read, and is said so, not passed over.
**Mutation:** `(only (chezscheme) 5)`, `(only (chezscheme) format "eval")` and `(only (chezscheme) . eval)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/m1.sls: (curl m1) has an import it cannot read: (only (chezscheme) 5)
check-seam: src/curl/m1.sls: (curl m1) has an import it cannot read: (only (chezscheme) format "eval")
check-seam: src/curl/m1.sls: (curl m1) has an import it cannot read: (only (chezscheme) . eval)
check-seam: FAILED (problems: 3)
```

#### C9. A library in no family

**Guards:** Rule (c) is not limited to the two families.
**Mutation:** `(util)` imports `(chezscheme)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/util.sls: (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client
check-seam: src/util.sls: (util) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: FAILED (problems: 2)
```

### Rule (d): every library belongs to a family

#### F1. Laundering through a third library

**Guards:** The path round the seam: `(curl launder)` imports `(util)`, which imports `(http-client)`. Neither import breaks rules (a) and (b), so the library in the middle is what is refused.
**Mutation:** `src/curl/launder.sls` and `src/util.sls`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/util.sls: (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client
check-seam: FAILED (problems: 1)
```

#### F2. Other families

**Guards:** `curl-extras` and `http-client-extras` are in neither family. Part 2 case P3 held the opposite, and was replaced.
**Mutation:** `(curl-extras)` imports `(http-client)`, and `(http-client-extras)` imports `(curl private x)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl-extras.sls: (curl-extras) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client
check-seam: src/http-client-extras.sls: (http-client-extras) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client
check-seam: FAILED (problems: 2)
```

#### F3. A family name later in the name

**Guards:** The first identifier decides: `(foo curl)` and `(srfi curl)` are in no family, and a version after the name is dropped.
**Mutation:** `(foo curl)`, `(srfi curl)` and `(util (1 0))`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/foo.sls: (foo curl) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client
check-seam: src/srfi.sls: (srfi curl) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client
check-seam: src/versioned.sls: (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client
check-seam: FAILED (problems: 3)
```

#### F4. The second library of a file

**Guards:** Every library form in a file is held to the rule.
**Mutation:** `src/curl/two.sls` holds `(curl two-a)` and `(util2)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/two.sls: (util2) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client
check-seam: FAILED (problems: 1)
```

#### F5. All three rules at once

**Guards:** A library in no family that imports `(rnrs eval)`, `(http-client)` and `(only (chezscheme) eval)` gets the family problem, then the import problems in import order. The `(http-client)` import is no problem of its own: the library is not a `(curl ...)` one.
**Mutation:** `(util3)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/util3.sls: (util3) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client
check-seam: src/util3.sls: (util3) imports (rnrs eval), but no library under src/ may import (rnrs eval)
check-seam: src/util3.sls: (util3) imports eval from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: FAILED (problems: 3)
```

### Files Chez could load but the check does not read

#### EX1. Every other extension

**Guards:** The source endings `.ss`, `.scm`, `.sch` and `.chezscheme.sls`, and the compiled `.so` and `.chezscheme.so`, each named, in path order, for its longest ending.
**Mutation:** `src/curl/e-ss.ss`, `e-scm.scm`, `e-sch.sch`, `e-csls.chezscheme.sls` (each a legal library), and `e-so.so` and `e-cso.chezscheme.so` (each holding `object`).
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/e-csls.chezscheme.sls: Chez could load a library from a file ending in .chezscheme.sls, and this check does not read one; rename it or keep it out of src/
check-seam: src/curl/e-cso.chezscheme.so: Chez could load a library from a file ending in .chezscheme.so, and this check does not read one; rename it or keep it out of src/
check-seam: src/curl/e-sch.sch: Chez could load a library from a file ending in .sch, and this check does not read one; rename it or keep it out of src/
check-seam: src/curl/e-scm.scm: Chez could load a library from a file ending in .scm, and this check does not read one; rename it or keep it out of src/
check-seam: src/curl/e-so.so: Chez could load a library from a file ending in .so, and this check does not read one; rename it or keep it out of src/
check-seam: src/curl/e-ss.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/
check-seam: FAILED (problems: 6)
```

#### EX2. Nothing but a `.ss` library

**Guards:** A tree whose only library is in a `.ss` file has no library for the check, and says so as well as naming the file.
**Mutation:** `src/curl.ss`, and nothing else.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: no libraries: src holds no .sls file, so there is no seam to check
check-seam: src/curl.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/
check-seam: FAILED (problems: 2)
```

#### EX3. Nested files and links

**Guards:** A file deep in the tree, a symbolic link to a `.scm` file and a dangling link to a `.ss` file are all named: they are named for their endings, not their targets.
**Mutation:** `src/curl/private/deep/z.scm`, `src/curl/lnk.scm` (a link to `elsewhere/real.scm`) and `src/curl/dangling.ss` (a link to `nowhere`).
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/dangling.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/
check-seam: src/curl/lnk.scm: Chez could load a library from a file ending in .scm, and this check does not read one; rename it or keep it out of src/
check-seam: src/curl/private/deep/z.scm: Chez could load a library from a file ending in .scm, and this check does not read one; rename it or keep it out of src/
check-seam: FAILED (problems: 3)
```

### Emacs lock files

#### K1. Lock files are skipped

**Guards:** A name starting with `.#` is skipped whatever it is: a dangling link ending in `.sls`, `.ss` or `.so`, a link in the root, a regular file that would not read, and a directory holding a library that breaks the seam.
**Mutation:** `src/curl/.#x.sls`, `src/.#curl.sls`, `src/curl/.#y.ss` and `src/curl/.#z.so` (links to `me@host.1234:1700000000`), `src/curl/.#w.sls` (the text `junk`), and `src/.#dir/bad.sls`, a `(curl bad)` importing `(http-client)`.
**Result:** exit 0, and the whole output:
```
check-seam: the seam holds (3 libraries in 3 files checked)
```

#### K2. A dangling link that is no lock file

**Guards:** The skip is for `.#`, not for dangling links: one that is named like a source is still named.
**Mutation:** `src/curl/dangle.sls`, a link to `nowhere`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/dangle.sls: it cannot be read as data: Exception in open-file-input-port: failed for src/curl/dangle.sls: no such file or directory
check-seam: FAILED (problems: 1)
```

#### K3. Another dotfile

**Guards:** The skip is not for every dotfile: an AppleDouble file such as `._native.sls` is read, and named.
**Mutation:** `src/curl/._native.sls` holding `junk`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/._native.sls: datum 1 is junk, not a library form
check-seam: FAILED (problems: 1)
```

#### K4. `.#` inside a name

**Guards:** Only a name that starts with `.#` is skipped. Found by SM58, which survived the first run.
**Mutation:** `src/curl/x.#bad.sls`, a `(curl xbad)` importing `(http-client)`.
**Result:** exit 2 (make's; the program exits 1), and the whole output:
```
check-seam: src/curl/x.#bad.sls: (curl xbad) imports (http-client), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

### The cases against the finished program

Layer 1 (`make check-seam` in a fresh copy per case, 65 cases): `65 passed, 0 failed`. Layer 2 (the program on every
case, one container call, 64 cases: T1 needs make): `64 passed, 0 failed`. Both after the last change to the program.

### Code mutants: `check-seam`

A mutant is killed when it fails at least one case, by exit status or by its whole output. The first run
held SM1 to SM61, and SM58 survived: see Findings. SM62 to SM64 came with the later cases. All 64 are
killed.

#### SM1. Rule (c) deleted: nothing is said of a (chezscheme) import

**Guards:** The dispatch to rule (c): without it nothing is said of a `(chezscheme)` import.
**Mutation:**
```diff
-       (chez-complaints path name spec))
+       '())
```
**Result:** killed by 9 cases: C1, C2, C3, C4, C5, C7, C8, C9, F5. For example C1-reviewer-repro exited 0 (wanted 1).

#### SM2. The alias (scheme) not taken for (chezscheme)

**Guards:** The alias: `(scheme)` is held to rule (c).
**Mutation:**
```diff
-(define chez-names '((chezscheme) (scheme)))
+(define chez-names '((chezscheme)))
```
**Result:** killed by 2 cases: C2, C3. For example C2-scheme-alias exited 0 (wanted 1).

#### SM3. A prefix over (chezscheme) taken for an only

**Guards:** Only an `only` is accepted: a `prefix` over `(chezscheme)` brings in names under other names.
**Mutation:**
```diff
-  (and (eq? (car spec) 'only)
+  (and (memq (car spec) '(only prefix))
```
**Result:** killed by 1 case: C3.

#### SM4. An only over any wrapper of (chezscheme), or over (scheme), taken for an only over (chezscheme)

**Guards:** The `only` must be over `(chezscheme)` itself, not over `(scheme)` or another wrapper of it.
**Mutation:**
```diff
-       (equal? (reference-name (cadr spec)) '(chezscheme))
+       #t
```
**Result:** killed by 1 case: C3.

#### SM5. The version reference kept: only (chezscheme (10 4)) is no only over (chezscheme)

**Guards:** A version after `(chezscheme)` is dropped, as it is everywhere else.
**Mutation:**
```diff
-       (equal? (reference-name (cadr spec)) '(chezscheme))
+       (equal? (cadr spec) '(chezscheme))
```
**Result:** killed by 1 case: P6. For example P6-chez-legal exited 1 (wanted 0).

#### SM6. An only with no name refused

**Guards:** An `only` with no name is legal, and is not a shape problem.
**Mutation:**
```diff
-       (cddr spec)))
+       (and (pair? (cddr spec)) (cddr spec))))
```
**Result:** killed by 1 case: P6. For example P6-chez-legal exited 1 (wanted 0).

#### SM7. A name that is no identifier passed over

**Guards:** A name that is no identifier is said so.
**Mutation:**
```diff
-       (list (cannot-read path name spec)))
+       '())
```
**Result:** killed by 1 case: C8.

#### SM8. Only the first forbidden name of an import list named

**Guards:** Every forbidden name in one import is named, not the first.
**Mutation:**
```diff
-            (filter (lambda (id) (memq id forbidden-chez-names)) names))))))
+            (let ((one (find (lambda (id) (memq id forbidden-chez-names)) names))) (if one (list one) '())))))))
```
**Result:** killed by 1 case: C5.

#### SM9. Forbidden names named in reverse import order

**Guards:** The problems of one import come in the import's order.
**Mutation:**
```diff
-            (filter (lambda (id) (memq id forbidden-chez-names)) names))))))
+            (reverse (filter (lambda (id) (memq id forbidden-chez-names)) names)))))))
```
**Result:** killed by 1 case: C5.

#### SM10. A forbidden name named only when it is the first name of the list

**Guards:** A forbidden name anywhere in the list, not only first.
**Mutation:**
```diff
-            (filter (lambda (id) (memq id forbidden-chez-names)) names))))))
+            (filter (lambda (id) (memq id forbidden-chez-names)) (list (car names))))))))
```
**Result:** killed by 2 cases: C5, P6. For example C5-several-names exited 0 (wanted 1).

#### SM11. The forbidden-name check also run on other libraries imported with only

**Guards:** The forbidden names are rule (c)'s, for `(chezscheme)` alone: `(only (curl private x) eval)` is fine.
**Mutation:**
```diff
-      ((member imported chez-names)
+      ((or (member imported chez-names) (equal? imported '(curl private x)))
```
**Result:** killed by 58 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, C1, C2, C3, C4, C5, C6, C7, C8, C9, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, EX1, EX3, F1, F2, F3, F4, F5, I1, I2, I3, K1, K2, K3, K4, L1, M1, M2, M3, P0, P1, P2, P4, P5, P6, U1. For example K1-lock-files exited 1 (wanted 0).

#### SM12. An (http-client ...) library exempt from rule (c)

**Guards:** Rule (c) holds for an `(http-client ...)` library.
**Mutation:**
```diff
-      ((member imported chez-names)
+      ((and (member imported chez-names) (not (family? 'http-client name)))
```
**Result:** killed by 1 case: C7.

#### SM13. A library in neither family exempt from rule (c)

**Guards:** Rule (c) holds for a library in no family.
**Mutation:**
```diff
-      ((member imported chez-names)
+      ((and (member imported chez-names) (memq (car name) families))
```
**Result:** killed by 2 cases: C9, F5.

#### SM14. A (curl ...) library exempt from rule (c)

**Guards:** Rule (c) holds for a `(curl ...)` library.
**Mutation:**
```diff
-      ((member imported chez-names)
+      ((and (member imported chez-names) (not (family? 'curl name)))
```
**Result:** killed by 6 cases: C1, C2, C3, C4, C5, C8. For example C1-reviewer-repro exited 0 (wanted 1).

#### SM15. The shape complaint does not name the import

**Guards:** The shape problem names the import.
**Mutation:**
```diff
-                            (abbreviated spec)
+                            "(chezscheme)"
```
**Result:** killed by 2 cases: C2, C3.

#### SM16. The forbidden-name complaint does not name the name

**Guards:** The name problem names the name.
**Mutation:**
```diff
-                             (symbol->string id)
+                             "it"
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM17. The shape complaint deleted: a wrapper over (chezscheme) passes silently

**Guards:** The shape problem exists.
**Mutation:**
```diff
-       (list (string-append path ": " (written name) " imports "
-                            (abbreviated spec)
-                            ", but (chezscheme), and its alias (scheme), may be"
-                            " imported only as (only (chezscheme) name ...)")))
+       '())
```
**Result:** killed by 5 cases: C1, C2, C3, C7, C9. For example C2-scheme-alias exited 0 (wanted 1).

#### SM18. Forbidden name import dropped from the list

**Guards:** The name `import` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM19. Forbidden name include dropped from the list

**Guards:** The name `include` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM20. Forbidden name include-library-declarations dropped from the list

**Guards:** The name `include-library-declarations` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include eval environment interaction-environment load load-library library-directories interpret compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM21. Forbidden name eval dropped from the list

**Guards:** The name `eval` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include include-library-declarations environment interaction-environment load load-library library-directories interpret compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM22. Forbidden name environment dropped from the list

**Guards:** The name `environment` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include include-library-declarations eval interaction-environment load load-library library-directories interpret compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM23. Forbidden name interaction-environment dropped from the list

**Guards:** The name `interaction-environment` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include include-library-declarations eval environment load load-library library-directories interpret compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM24. Forbidden name load dropped from the list

**Guards:** The name `load` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include include-library-declarations eval environment interaction-environment load-library library-directories interpret compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM25. Forbidden name load-library dropped from the list

**Guards:** The name `load-library` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include include-library-declarations eval environment interaction-environment load library-directories interpret compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM26. Forbidden name library-directories dropped from the list

**Guards:** The name `library-directories` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include include-library-declarations eval environment interaction-environment load load-library interpret compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM27. Forbidden name interpret dropped from the list

**Guards:** The name `interpret` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include include-library-declarations eval environment interaction-environment load load-library library-directories compile load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM28. Forbidden name compile dropped from the list

**Guards:** The name `compile` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret load-program))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM29. Forbidden name load-program dropped from the list

**Guards:** The name `load-program` is on the list: C4 has a library that imports it.
**Mutation:**
```diff
-  '(import include include-library-declarations eval environment
-    interaction-environment load load-library library-directories
-    interpret compile load-program))
+  '(import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile))
```
**Result:** killed by 5 cases: C1, C4, C5, C7, F5.

#### SM30. (rnrs eval) not refused

**Guards:** `(rnrs eval)` is refused.
**Mutation:**
```diff
-(define eval-libraries '((rnrs eval)))
+(define eval-libraries '())
```
**Result:** killed by 3 cases: C6, C7, F5. For example C6-rnrs-eval exited 0 (wanted 1).

#### SM31. The (rnrs eval) rule runs after the seam rules, so (rnrs eval) is never reached for a (curl ...) library

**Guards:** It is refused for a `(curl ...)` library too.
**Mutation:**
```diff
-      ((member imported eval-libraries)
+      ((and (member imported eval-libraries) (not (family? 'curl name)))
```
**Result:** killed by 1 case: C6. For example C6-rnrs-eval exited 0 (wanted 1).

#### SM32. The family rule deleted

**Guards:** Rule (d) exists.
**Mutation:**
```diff
-     (if (memq (car name) families)
+     (if #t
```
**Result:** killed by 6 cases: C9, F1, F2, F3, F4, F5. For example F1-laundering exited 0 (wanted 1).

#### SM33. A family by any identifier of the name

**Guards:** The first identifier of the name decides, not any identifier.
**Mutation:**
```diff
-     (if (memq (car name) families)
+     (if (or (memq (car name) families) (memq 'curl name))
```
**Result:** killed by 1 case: F3.

#### SM34. A family by string prefix

**Guards:** The first identifier is `curl` or `http-client`, not a prefix of one.
**Mutation:**
```diff
-     (if (memq (car name) families)
+     (if (let ((s (symbol->string (car name)))) (or (prefix? s "curl") (prefix? s "http-client")))
```
**Result:** killed by 1 case: F2. For example F2-other-families exited 0 (wanted 1).

#### SM35. Util added to the families

**Guards:** The families are two.
**Mutation:**
```diff
-(define families '(curl http-client))
+(define families '(curl http-client util))
```
**Result:** killed by 6 cases: C9, F1, F2, F3, F4, F5. For example F1-laundering exited 0 (wanted 1).

#### SM36. Http-client dropped from the families

**Guards:** `http-client` is one of them.
**Mutation:**
```diff
-(define families '(curl http-client))
+(define families '(curl))
```
**Result:** killed by 59 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, C1, C2, C3, C4, C5, C6, C7, C8, C9, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, EX1, EX3, F1, F2, F3, F4, F5, I1, I2, I3, K1, K2, K3, K4, L1, M1, M2, M3, P0, P1, P2, P4, P5, P6, U1, U2. For example K1-lock-files exited 1 (wanted 0).

#### SM37. The family complaint does not name the families

**Guards:** The problem names the families.
**Mutation:**
```diff
-                              (joined " or " (map symbol->string families)))))
+                              "curl")))
```
**Result:** killed by 6 cases: C9, F1, F2, F3, F4, F5.

#### SM38. The unread files not looked for

**Guards:** The unread files are looked for.
**Mutation:**
```diff
-            ((unread-ending (car names))
+            ((and #f (unread-ending (car names)))
```
**Result:** killed by 4 cases: EX1, EX2, EX3, N3. For example EX1-extensions exited 0 (wanted 1).

#### SM39. The ending .ss not looked for

**Guards:** A file ending in `.ss` is named.
**Mutation:**
```diff
-              (remp (lambda (ext) (string=? ext ".sls"))
+              (remp (lambda (ext) (member ext '(".sls" ".ss")))
```
**Result:** killed by 3 cases: EX1, EX2, EX3.

#### SM40. The ending .scm not looked for

**Guards:** A file ending in `.scm` is named.
**Mutation:**
```diff
-              (remp (lambda (ext) (string=? ext ".sls"))
+              (remp (lambda (ext) (member ext '(".sls" ".scm")))
```
**Result:** killed by 3 cases: EX1, EX3, N3.

#### SM41. The ending .sch not looked for

**Guards:** A file ending in `.sch` is named.
**Mutation:**
```diff
-              (remp (lambda (ext) (string=? ext ".sls"))
+              (remp (lambda (ext) (member ext '(".sls" ".sch")))
```
**Result:** killed by 1 case: EX1.

#### SM42. The ending .chezscheme.sls not looked for

**Guards:** A file ending in `.chezscheme.sls` is named.
**Mutation:**
```diff
-              (remp (lambda (ext) (string=? ext ".sls"))
+              (remp (lambda (ext) (member ext '(".sls" ".chezscheme.sls")))
```
**Result:** killed by 1 case: EX1.

#### SM43. The ending .so not looked for

**Guards:** A file ending in `.so` is named.
**Mutation:**
```diff
-              (remp (lambda (ext) (string=? ext ".sls"))
+              (remp (lambda (ext) (member ext '(".sls" ".so")))
```
**Result:** killed by 1 case: EX1.

#### SM44. The ending .chezscheme.so not looked for

**Guards:** A file ending in `.chezscheme.so` is named.
**Mutation:**
```diff
-              (remp (lambda (ext) (string=? ext ".sls"))
+              (remp (lambda (ext) (member ext '(".sls" ".chezscheme.so")))
```
**Result:** killed by 1 case: EX1.

#### SM45. The compiled endings left out

**Guards:** The compiled endings are named too.
**Mutation:**
```diff
-                    (apply append (map (lambda (pair) (list (car pair) (cdr pair)))
+                    (apply append (map (lambda (pair) (list (car pair)))
```
**Result:** killed by 1 case: EX1.

#### SM46. .sls files taken for unread too

**Guards:** `.sls` files are read, not named.
**Mutation:**
```diff
-              (remp (lambda (ext) (string=? ext ".sls"))
+              (remp (lambda (ext) #f)
```
**Result:** killed by 59 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, C1, C2, C3, C4, C5, C6, C7, C8, C9, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, EX1, EX3, F1, F2, F3, F4, F5, I1, I2, I3, K1, K2, K3, K4, L1, M1, M2, M3, P0, P1, P2, P4, P5, P6, U1, U2. For example K1-lock-files exited 1 (wanted 0).

#### SM47. The endings not sorted longest first

**Guards:** A file is named for its longest ending.
**Mutation:**
```diff
-   (lambda (a b) (> (string-length a) (string-length b)))
+   (lambda (a b) #f)
```
**Result:** killed by 1 case: EX1.

#### SM48. An ending matched without its dot

**Guards:** An ending has its dot: `class` and `also` are not `.ss` and `.so`.
**Mutation:**
```diff
-  (find (lambda (ext) (suffix? name ext)) unread-extensions))
+  (find (lambda (ext) (suffix? name (substring ext 1 (string-length ext)))) unread-extensions))
```
**Result:** killed by 1 case: P5. For example P5-other-files-ignored exited 1 (wanted 0).

#### SM49. A directory named like an unread file taken for one

**Guards:** A directory named like an unread file is entered.
**Mutation:**
```diff
+            ((unread-ending (car names))
+             (loop (cdr names) files links (cons path unread)))
```
**Result:** killed by 2 cases: K1, P5. For example K1-lock-files exited 1 (wanted 0).

#### SM50. The unread files not printed

**Guards:** The unread files are printed.
**Mutation:**
```diff
-                    unread)
+                    '())
```
**Result:** killed by 4 cases: EX1, EX2, EX3, N3. For example EX1-extensions exited 0 (wanted 1).

#### SM51. The unread files not sorted

**Guards:** They are printed in path order.
**Mutation:**
```diff
-             (unread (list-sort string<? (caddr found)))
+             (unread (caddr found))
```
**Result:** killed by 2 cases: EX1, EX3.

#### SM52. The unread file named by its first ending, not its longest

**Guards:** The longest ending is named.
**Mutation:**
```diff
-  (find (lambda (ext) (suffix? name ext)) unread-extensions))
+  (find (lambda (ext) (suffix? name ext)) (reverse unread-extensions)))
```
**Result:** killed by 1 case: EX1.

#### SM53. The unread files not counted as a problem (printed after the count)

**Guards:** They count as problems.
**Mutation:**
```diff
-                               (number->string (length complaints)) ")"))
+                               (number->string (- (length complaints) (length unread))) ")"))
```
**Result:** killed by 4 cases: EX1, EX2, EX3, N3.

#### SM54. Unread files of subdirectories lost

**Guards:** Those in subdirectories are found.
**Mutation:**
```diff
-                     (append (caddr below) unread))))
+                     unread)))
```
**Result:** killed by 2 cases: EX1, EX3. For example EX1-extensions exited 0 (wanted 1).

#### SM55. Lock files not skipped

**Guards:** Lock files are skipped.
**Mutation:**
```diff
-            ((prefix? (car names) ".#")
+            ((and #f (prefix? (car names) ".#"))
```
**Result:** killed by 1 case: K1. For example K1-lock-files exited 1 (wanted 0).

#### SM56. Every dotfile skipped, not only lock files

**Guards:** Only lock files are skipped: `._native.sls` is read.
**Mutation:**
```diff
-            ((prefix? (car names) ".#")
+            ((prefix? (car names) ".")
```
**Result:** killed by 1 case: K3. For example K3-other-dotfile exited 0 (wanted 1).

#### SM57. Only a lock file that is not a directory skipped

**Guards:** A lock file is skipped whatever it is: a directory too.
**Mutation:**
```diff
-            ((prefix? (car names) ".#")
+            ((and (prefix? (car names) ".#") (not (file-directory? path #f)))
```
**Result:** killed by 1 case: K1. For example K1-lock-files exited 1 (wanted 0).

#### SM58. A name with .# anywhere skipped

**Guards:** Only a name that starts with `.#` is skipped.
**Mutation:**
```diff
-            ((prefix? (car names) ".#")
+            ((let loop ((i 0)) (and (<= (+ i 2) (string-length (car names))) (or (string=? (substring (car names) i (+ i 2)) ".#") (loop (+ i 1)))))
```
**Result:** killed by 1 case: K4. For example K4-hash-inside-name exited 0 (wanted 1).

#### SM59. A lock file skipped only when it is a dangling link (not a regular file)

**Guards:** A lock file is skipped even when it is a regular file.
**Mutation:**
```diff
-            ((prefix? (car names) ".#")
+            ((and (prefix? (car names) ".#") (not (file-exists? path)))
```
**Result:** killed by 1 case: K1. For example K1-lock-files exited 1 (wanted 0).

#### SM60. A name starting with # skipped

**Guards:** The skip is for `.#`, not for `#`.
**Mutation:**
```diff
-            ((prefix? (car names) ".#")
+            ((prefix? (car names) "#")
```
**Result:** killed by 1 case: K1. For example K1-lock-files exited 1 (wanted 0).

#### SM61. The lock file test after the others: .#y.ss is named, and .#dir entered

**Guards:** The skip comes before the other tests: `.#y.ss` is not named, and `.#dir` is not entered.
**Mutation:**
```diff
-            ((prefix? (car names) ".#")
-             (loop (cdr names) files links unread))
+            ((prefix? (car names) ".#")
+             (loop (cdr names) files links unread))
```
**Result:** killed by 1 case: K1. For example K1-lock-files exited 1 (wanted 0).

#### SM62. The prefix test reaches past a name shorter than the prefix

**Guards:** The prefix test holds for a name shorter than the prefix.
**Mutation:**
```diff
-    (and (>= n m) (string=? (substring s 0 m) prefix))))
+    (string=? (substring s 0 m) prefix)))
```
**Result:** killed by 1 case: P5. For example P5-other-files-ignored exited 255 (wanted 0).

#### SM63. The suffix test reaches past a name shorter than the suffix

**Guards:** The suffix test holds for a name shorter than the suffix.
**Mutation:**
```diff
-    (and (>= n m) (string=? (substring s (- n m) n) suffix))))
+    (string=? (substring s (- n m) n) suffix)))
```
**Result:** killed by 61 cases: A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, B1, B2, B3, B4, C1, C2, C3, C4, C5, C6, C7, C8, C9, D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, EX1, EX2, EX3, F1, F2, F3, F4, F5, I1, I2, I3, K1, K2, K3, K4, L1, M1, M2, M3, N3, P0, P1, P2, P4, P5, P6, U1, U2. For example A10-nested exited 255 (wanted 1).

#### SM64. check-seam exits 0 on a failure, so make test passes on the planted seam

**Guards:** the end of the chain: `make test` fails because `check-seam` exits 1. Every rule above reaches
`make test` through that one status, and the `seam` case of `tests/check-test-fails.sh` is what holds it.
**Mutation:** the last `(exit 1)` of `tests/check-seam.sps`, the one after the problems are printed, becomes
`(exit 0)`.
**Result:** killed by `make check-test-fails`, exit 2:
```
check-test-fails exit 2
check-test-fails: FAILED seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs: make test exited 0
check-test-fails: FAILED seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs: make test's lines differ
```

No case was added to `tests/check-test-fails.sh`. The new rules print their problems, count them and exit
1 by the code the `seam` case already plants against, and SM64 shows that case fails when it is broken.

### Mutants of the order rule's checker: `tests/test-require-threaded.sps`

#### TM1. The (http-client ...) case dropped: every library must import the refusal first

**Guards:** The order rule for an `(http-client ...)` library: a library of that family needs `(curl)` first.
**Mutation:**
```diff
-  (if (and (pair? name) (eq? (car name) 'http-client))
-      '(curl)
-      refusal-library))
+  refusal-library)
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL an (http-client ...) library importing (curl) first is first
  expected: first
  actual:   absent
FAIL an (http-client) library is held to the same rule
  expected: first
  actual:   absent
FAIL an (http-client ...) library importing (rnrs) before (curl) is not first
  expected: not-first
  actual:   absent
FAIL an (http-client ...) library without (curl) is absent, even with the refusal first
  expected: (absent absent)
  actual:   (absent first)
[5 more lines]
```

#### TM2. Every library must import (curl) first

**Guards:** It is only for that family: every other library needs the refusal.
**Mutation:**
```diff
-  (if (and (pair? name) (eq? (car name) 'http-client))
-      '(curl)
-      refusal-library))
+  '(curl))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL a (curl ...) library is not excused by importing (curl) first
  expected: (absent not-first)
  actual:   (first first)
FAIL a library in neither family needs the refusal first
  expected: (absent absent first first)
  actual:   (first first absent absent)
FAIL http-client-extras is no (http-client ...) library
  expected: (absent first)
  actual:   (first absent)
FAIL src/curl/private/conditions.sls imports (curl) first
  expected: first
  actual:   absent
[17 more lines]
```

#### TM3. An (http-client ...) library is any library with http-client in its name

**Guards:** The family is the first identifier of the name: `(foo http-client)` needs the refusal. Found by the first run, where it survived.
**Mutation:**
```diff
-  (if (and (pair? name) (eq? (car name) 'http-client))
+  (if (and (pair? name) (memq 'http-client name))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL a library in neither family needs the refusal first
  expected: (absent absent first first)
  actual:   (absent first first absent)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### TM4. (curl ...) libraries are excused by importing (curl) first, too

**Guards:** `(curl)` does not excuse a `(curl ...)` library.
**Mutation:**
```diff
-  (if (and (pair? name) (eq? (car name) 'http-client))
+  (if (and (pair? name) (memq (car name) '(curl http-client)))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL a (curl ...) library is not excused by importing (curl) first
  expected: (absent not-first)
  actual:   (first first)
FAIL src/curl/private/conditions.sls imports (curl) first
  expected: first
  actual:   absent
FAIL src/curl/private/constants.sls imports (curl) first
  expected: first
  actual:   absent
FAIL src/curl/private/discovery.sls imports (curl) first
  expected: first
  actual:   absent
[11 more lines]
```

#### TM5. An (http-client ...) library is one whose first identifier starts with http-client

**Guards:** The family is `http-client`, not a name that starts with it.
**Mutation:**
```diff
-  (if (and (pair? name) (eq? (car name) 'http-client))
+  (if (and (pair? name) (let ((s (symbol->string (car name)))) (and (>= (string-length s) 11) (string=? (substring s 0 11) "http-client"))))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL http-client-extras is no (http-client ...) library
  expected: (absent first)
  actual:   (first absent)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### TM6. The rule for an (http-client ...) library is asked of the second import, not the first

**Guards:** The library required is the first import, not the second.
**Mutation:**
```diff
-          ((equal? (car names) required) 'first)
+          ((and (pair? (cdr names)) (equal? (cadr names) required)) 'first)
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL the refusal first among the imports is first
  expected: first
  actual:   absent
FAIL the refusal after (rnrs) is not first
  expected: not-first
  actual:   first
FAIL a wrapped or versioned refusal is the same library
  expected: (first first first)
  actual:   (absent absent absent)
FAIL an (http-client ...) library importing (curl) first is first
  expected: first
  actual:   absent
[38 more lines]
```

#### TM7. As-version replaces nothing

**Guards:** The floor rows substitute a version: a copy that is not changed would load.
**Mutation:**
```diff
-             (if (equal? e '(scheme-version-number))
+             (if (equal? e '(scheme-version-numberx))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### TM8. Version-calls counts nothing

**Guards:** The suite counts the calls it substitutes.
**Mutation:**
```diff
-                            (if (equal? e '(scheme-version-number)) 1 (version-calls e)))
+                            (if (equal? e '(scheme-version-numberx)) 1 (version-calls e)))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL the refusal asks (scheme-version-number)
  expected: asks
  actual:   never-asks
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### TM9. Expand-refusal reports every syntax violation as loaded

**Guards:** The suite tells a refusal from a load.
**Mutation:**
```diff
-                 (list 'refused (condition-who e) (condition-message e)))
+                 'loaded)
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### TM10. Expand-refusal reports the text of every raise, not the refusal

**Guards:** The suite tells a refusal from any other raise.
**Mutation:**
```diff
-      (guard (e ((and (syntax-violation? e) (who-condition? e) (message-condition? e))
+      (guard (e ((and #f (syntax-violation? e) (who-condition? e) (message-condition? e))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0 (require-supported-chez)"
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9 (require-supported-chez)"
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

### Mutants of the refusal: `src/curl/private/require-threaded.sls`

#### FR1. The floor check deleted

**Guards:** The floor check exists.
**Mutation:**
```diff
-           ((older? have minimum)
+           ((and #f (older? have minimum))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR2. The floor raised to 10.5.0

**Guards:** The floor is not above 10.4.0: this Chez, 10.4.0, is accepted.
**Mutation:**
```diff
-      (define minimum '(10 4 0))
+      (define minimum '(10 5 0))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
test: FAIL tests/test-conditions.sps (exit 255)
test: FAIL tests/test-discovery.sps (exit 255)
test: FAIL tests/test-library-loading.sps (exit 255)
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.5.0 or later, and this one is 10.4.0 (require-supported-chez)"
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.5.0 or later, and this one is 10.3.0")
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.5.0 or later, and this one is 9.5.9")
[10 more lines]
```

#### FR3. The floor lowered to 10.3.0

**Guards:** The floor is not below 10.4.0: 10.3.0 is refused.
**Mutation:**
```diff
-      (define minimum '(10 4 0))
+      (define minimum '(10 3 0))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.3.0 or later, and this one is 9.5.9")
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR4. The floor lowered to 9.5.0

**Guards:** The floor is not 9.5.0: 9.5.9 is refused.
**Mutation:**
```diff
-      (define minimum '(10 4 0))
+      (define minimum '(9 5 0))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR5. Only the major version compared

**Guards:** The minor version is compared when the major is the floor's.
**Mutation:**
```diff
-        (cond ((null? want) #f)
-              ((< (car have) (car want)) #t)
-              ((> (car have) (car want)) #f)
-              (else (older? (cdr have) (cdr want)))))
+        (< (car have) (car want)))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR6. Only the minor version compared

**Guards:** The major version is compared: 9.5.9 has the higher minor.
**Mutation:**
```diff
-        (cond ((null? want) #f)
-              ((< (car have) (car want)) #t)
-              ((> (car have) (car want)) #f)
-              (else (older? (cdr have) (cdr want)))))
+        (< (cadr have) (cadr want)))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
FAIL where (scheme-version-number) answers 11.0.0, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 11.0.0")
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR7. Older when the major or the minor is lower, as a later major does not count

**Guards:** A later major version is accepted whatever its minor. Found by the first run, where it survived, and the 11.0.0 row came from it.
**Mutation:**
```diff
-        (cond ((null? want) #f)
-              ((< (car have) (car want)) #t)
-              ((> (car have) (car want)) #f)
-              (else (older? (cdr have) (cdr want)))))
+        (or (< (car have) (car want)) (< (cadr have) (cadr want))))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 11.0.0, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 11.0.0")
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR8. The floor itself refused: <= for <

**Guards:** The floor itself is accepted.
**Mutation:**
```diff
-              ((< (car have) (car want)) #t)
+              ((<= (car have) (car want)) #t)
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
test: FAIL tests/test-conditions.sps (exit 255)
test: FAIL tests/test-discovery.sps (exit 255)
test: FAIL tests/test-library-loading.sps (exit 255)
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0 (require-supported-chez)"
FAIL where (scheme-version-number) answers 10.4.0, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0")
FAIL where (scheme-version-number) answers 10.5.1, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.5.1")
[7 more lines]
```

#### FR9. A later major version refused: > not told apart

**Guards:** A later major version is not refused.
**Mutation:**
```diff
-              ((> (car have) (car want)) #f)
+              ((> (car have) (car want)) #t)
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.5.1, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.5.1")
FAIL where (scheme-version-number) answers 11.0.0, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 11.0.0")
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR10. Every Chez refused

**Guards:** Some Chez is accepted.
**Mutation:**
```diff
-        (cond ((null? want) #f)
-              ((< (car have) (car want)) #t)
-              ((> (car have) (car want)) #f)
-              (else (older? (cdr have) (cdr want)))))
+        #t)
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
test: FAIL tests/test-conditions.sps (exit 255)
test: FAIL tests/test-discovery.sps (exit 255)
test: FAIL tests/test-library-loading.sps (exit 255)
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0 (require-supported-chez)"
FAIL where (scheme-version-number) answers 10.4.0, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0")
FAIL where (scheme-version-number) answers 10.5.1, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.5.1")
[10 more lines]
```

#### FR11. The message does not name the floor

**Guards:** The message names the floor.
**Mutation:**
```diff
-             (string-append "chez-curl needs Chez Scheme " (dotted minimum)
+             (string-append "chez-curl needs Chez Scheme " "?"
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme ? or later, and this one is 10.3.0")
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme ? or later, and this one is 9.5.9")
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR12. The message does not name the version found

**Guards:** The message names the version found.
**Mutation:**
```diff
-                            " or later, and this one is " (dotted have))
+                            " or later, and this one is " "?")
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is ?")
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is ?")
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR13. The version written with dashes

**Guards:** The version is written with dots.
**Mutation:**
```diff
-                    (string-append text "." (number->string (car rest)))))))
+                    (string-append text "-" (number->string (car rest)))))))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10-4-0 or later, and this one is 10-3-0")
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10-4-0 or later, and this one is 9-5-9")
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR14. The three numbers read in the wrong order

**Guards:** The three numbers are major, minor and patch, in that order.
**Mutation:**
```diff
-      (let-values (((major minor patch) (scheme-version-number)))
+      (let-values (((minor major patch) (scheme-version-number)))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
test: FAIL tests/test-conditions.sps (exit 255)
test: FAIL tests/test-discovery.sps (exit 255)
test: FAIL tests/test-library-loading.sps (exit 255)
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 4.10.0 (require-supported-chez)"
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 3.10.0")
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 5.9.9")
[16 more lines]
```

#### FR15. The floor refusal raised by another who

**Guards:** The refusal is raised by `chez-curl`.
**Mutation:**
```diff
-             'chez-curl
+             'curl
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   (refused curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR16. The floor refusal raised as an error, not a syntax violation

**Guards:** The floor refusal is a syntax violation, not an `error`. First written with an anchor that did not match; the driver said so and refused it.
**Mutation:**
```diff
-            (syntax-violation
-             'chez-curl
-             (string-append "chez-curl needs Chez Scheme " (dotted minimum)
-                            " or later, and this one is " (dotted have))
-             x))
+           (error 'chez-curl (string-append "chez-curl needs Chez Scheme " (dotted minimum) " or later, and this one is " (dotted have))))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0"
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9"
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR17. The floor refused at run time, not at expansion

**Guards:** The floor refusal comes at expansion: a check moved into the library body would not fire while it is loaded. First written with an anchor that did not match.
**Mutation:**
```diff
-            (syntax-violation
-             'chez-curl
-             (string-append "chez-curl needs Chez Scheme " (dotted minimum)
-                            " or later, and this one is " (dotted have))
-             x))
+           #'(define supported-chez-checked (error 'chez-curl "too old")))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR18. The version no longer asked: the floor met by a constant

**Guards:** The version is asked of Chez, not assumed.
**Mutation:**
```diff
-      (let-values (((major minor patch) (scheme-version-number)))
+      (let-values (((major minor patch) (values 10 4 0)))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL the refusal asks (scheme-version-number)
  expected: asks
  actual:   never-asks
FAIL where (scheme-version-number) answers 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where (scheme-version-number) answers 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR19. The thread check deleted

**Guards:** The thread refusal still exists.
**Mutation:**
```diff
-           ((not (threaded?))
+           ((and #f (not (threaded?)))
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   loaded
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### FR20. The thread refusal message loses its marker

**Guards:** The thread refusal still carries its message.
**Mutation:**
```diff
-             "chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads"
+             "needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads"
```
**Result:** killed. `make test exit 2`; the lines that name it:
```
FAIL where (threaded?) is #f, the refusal raises its message at expansion
  expected: refused-by-name
  actual:   "Exception in chez-curl: needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads (require-supported-chez)"
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
survivors: []
```

### The order rule's conflict, reproduced

**Guards:** the real tree, with the first `(http-client)` library in it. A scratch copy of the tree gets
`src/http-client.sls`; `make test`'s `check-seam`, `# of expected passes` of `require-threaded`, and its
`FAIL` rows are the evidence. `make test` itself was run, and its lines are kept.

#### HC1. An `(http-client)` library importing `(curl)` first

**Mutation:** `src/http-client.sls` is `(library (http-client) (export client-version) (import (curl) (rnrs)) ...)`.
**Result:** `make test` exits 0. `require-threaded` gains one row, `src/http-client.sls imports (curl) first`:
```
check-seam: the seam holds (8 libraries in 8 files checked)
# of expected passes      35
test: ran 7, passed 7, failed 0, hung 0
```

#### HC2. The same, under the old checker

**Mutation:** HC1's tree, with `required-first` answering the refusal for every library (TM1), which is what the checker did.
**Result:** `make test` exits 2: `check-seam` passes the library, and the suite refuses it.
```
check-seam: the seam holds (8 libraries in 8 files checked)
FAIL an (http-client ...) library importing (curl) first is first
  expected: first
  actual:   absent
FAIL an (http-client) library is held to the same rule
  expected: first
  actual:   absent
FAIL an (http-client ...) library importing (rnrs) before (curl) is not first
  expected: not-first
  actual:   absent
FAIL an (http-client ...) library without (curl) is absent, even with the refusal first
  expected: (absent absent)
  actual:   (absent first)
FAIL a wrapped or versioned (curl) is the same library
  expected: (first first first)
  actual:   (absent absent absent)
FAIL src/http-client.sls imports (curl private require-threaded) first
  expected: first
  actual:   absent
# of expected passes      29
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 7, passed 6, failed 1, hung 0
```

#### HC3. An `(http-client)` library importing the refusal first, which the old checker wanted

**Mutation:** `src/http-client.sls` imports `(curl private require-threaded)`, `(curl)` and `(rnrs)`.
**Result:** `make test` exits 2, stopped by `check-seam`, before any suite:
```
check-seam: src/http-client.sls: (http-client) imports (curl private require-threaded), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))
check-seam: FAILED (problems: 1)
```

### The reviewer's libraries, in a copy of the tree

**Guards:** the stop condition: `exp/seam` copied into a scratch copy's `src/` makes `make check-seam`
fail by name, and made it pass before.

**Mutation:** the three files of `exp/seam` copied over `src/` of a copy of the finished tree, and of a
copy of the tree as it was.
**Result, the finished tree,** `scripts/guix-env make check-seam`:
```
check-seam: src/curl/evil.sls: (curl evil) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: src/curl/evil2.sls: (curl evil2) imports import from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment load load-library library-directories interpret compile load-program
check-seam: FAILED (problems: 2)
make: *** [Makefile:232: check-seam] Error 1
exit 2
```

**Result, the tree as it was:**
```
check-seam: the seam holds (10 libraries in 10 files checked)
exit 0
```

### Part 2's mutants, run again

The 55 code mutants and 10 make mutants of part 2, against the finished program and Makefile, with this
part's cases. 61 applied as written, and each was killed: the 51 code mutants by at least one case, the
make mutants by `check-help`, `check-test-fails` or the `make check-seam` cases they name. CM26, CM29, CM43 and CM50 mutate code
that moved, and the driver refused them. They were written again against the new code, and killed by L1
(CM26), C8, I1, I2 and I3 (CM29), N1 (CM43) and I3 (CM50). All 65 are killed. The output is kept in the
scratchpad.

### Clean rerun

After the last change to the program, the suite, the refusal and the Makefile, in the finished tree,
`scripts/guix-env sh -c 'make test && make check-test-fails'` (exit 0). The check lines, the rows of
`require-threaded`, and the tail:
```
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
check-suites: every suite ends with (exit (suite-exit-status runner)) (7 checked)
check-seam: the seam holds (7 libraries in 7 files checked)
=== tests/test-require-threaded.sps
%%%% Starting test require-threaded
# of expected passes      34
test: pass tests/test-require-threaded.sps

test: pass tests/test-verify.sps
test: ran 7, passed 7, failed 0, hung 0
check-test-fails: ok fails: a failing suite is named FAIL, and the suites after it run
check-test-fails: ok no-tests: a suite that runs no test is named FAIL, and the suites after it run
check-test-fails: ok hangs: a suite that never ends is named HUNG, and the suites after it run
check-test-fails: ok exit-line: check-suites names a suite without the shared exit form, and no suite runs
check-test-fails: ok early-exit: check-suites names a suite that exits before its verdict, and no suite runs
check-test-fails: ok nested-exit: check-suites names an exit inside a form before the verdict, and no suite runs
check-test-fails: ok empty: check-suites names a suite with no datum, and no suite runs
check-test-fails: ok seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs
check-test-fails: ok no-suites: make test refuses to pass with no suite to run
check-test-fails: make test failed, as it must, in all 9 cases
```

`scripts/guix-env sh -c 'make check-help && make check-seam'` exits 0 with `check-seam: the seam holds (7
libraries in 7 files checked)`. `tests/check-test-fails.sh` is unchanged: its copy's two stub libraries
satisfy every new rule.

### Findings

- **`.chezscheme.sls` is named, not read.** It ends in `.sls`, which part 2 read. Chez prefers it to a
  `.sls` of the same name, so the file a library loads from is no longer the one that is read; it is
  refused with the other endings (EX1).
- **The brief's list for rule (c) left three routes open.** `(scheme)` is `(chezscheme)`, and `interpret`,
  `compile` and `load-program` do what `eval` and `load` do. Each was measured (see Measured first) and is
  on the list: the list is `forbidden-chez-names`, and the first nine names are the brief's.
- **A `.so` alone is a library,** so the compiled endings are named with the sources. Only a `.so` with no
  source beside it was measured.
- **The first run of the mutants left three alive,** and each was a missing row or case, not a missing
  code: SM58 (a `.#` inside a name was skipped), TM3 (a name that holds `http-client` but starts with
  something else) and FR7 (a later major version, 11.0.0, was refused by a check on the minor alone). K4,
  a row for `(foo http-client)` and an 11.0.0 row were added, and the three died. FR16 and FR17 were
  refused by the driver for an anchor that did not match, and were written again.
- **One mutant would be equivalent and is not in the list:** `older?` comparing the major and the minor but
  not the patch. The floor's patch is 0, and no Chez is older than 10.4.0 by its patch alone.
- **TM1 is the old checker,** and its failing rows are the red run of the order rule. A rule whose only
  test is in the suite that also holds the rule cannot be shown red any other way.
- **The refusal reads `scheme-version-number` as three values.** The suite substitutes `(values M m p)`
  for the call. It cannot run the real procedure on a Chez older than 10.4.0: none was here.

### Not covered

- **A Chez older than 10.4.0, and a non-threaded one.** None was run. The refusals are expanded from copies
  with the calls replaced, as the threaded one was.
- **Other names that load or evaluate.** The list is not every such name: `visit`, `revisit`,
  `load-compiled-from-port`, `compile-file` and `system` are not on it, and a library may import them. A
  library might run another's body with them, `(visit '(http-client session))` for one. Not measured, and
  not measured whether any of them gives it a binding.
- **Case.** The endings are matched as written. On a case-insensitive file system, macOS's default,
  `src/curl/x.SLS` might be found by Chez for `(curl x)` and not named here. Not run: Linux only.
- **A library whose name and path disagree.** A file is still judged by the name it declares.
- **Imports through a library outside `src/`.** `(curl x)` importing a library in `tests/` or on the
  path that imports `(http-client)` is not seen: tests are exempt (ADR-0007), and only `src/` is read.
- **Every run was Linux, amd64, in the container.**

## Second review fixes

Evidence for the fixes to the second review's findings on M0 slice 3, made on 2026-10-16
([ADR-0007](decisions/0007-one-repo-checked-seam.md), [ADR-0001](decisions/0001-bind-libcurl-directly.md)
decision 6, [traps](traps.md), "Checks and environment"). There are six fixes:

1. **`check-seam` holds allowlists, not a denylist.** `forbidden-chez-names` is gone. `allowed-chez-names` lists the
   19 names `src/` imports from `(chezscheme)`: the 18 it imported before this part, and `scheme-version`, which
   fix 5 added. A library may import `(chezscheme)` only as `(only (chezscheme) name ...)`, every name on the list.
   It may import nothing but the `(rnrs ...)` libraries other than `(rnrs eval)`, that form, and `(curl ...)` and
   `(http-client ...)` libraries (rule (e)): `(scheme)`, `(chezscheme csv7)`, `($system)` and any third-party library
   fail, named. `(rnrs eval)` keeps a message of its own. The reviewer's `import-only`, `top-level-value` and
   `$primitive` fail by name; they passed before.
2. **The `.#` skip is for dangling symbolic links.** Emacs's lock file is one. A `.#` regular file, a directory,
   and a link that resolves are read and checked like any other entry: Chez loads a library from `.#g.sls` as it
   does from `g.sls`. `tests/test-require-threaded.sps` skipped every dotfile by its name; it uses the same rule.
3. **Every `check-seam` rule has a standing test.** `tests/test-check-seam.sps` runs the program on 32 fixture
   trees under `tests/fixtures/seam/`, on an empty directory and a missing one, and with no argument and with two,
   and asserts the exit status and the whole of stdout and stderr. It also requires `allowed-chez-names` to equal
   the names `src/` imports, `rnrs-libraries` to equal Chez's `(rnrs ...)` libraries but `(rnrs eval)`, and every
   fixture directory to be a case.
4. **The oracle's temporary directory.** `(curl-testing)` gained `call-with-temp-directory`,
   `make-process-temp-directory` and `remove-temp-directory`. mktemp's answer is one line: an absolute path to
   a directory that exists, else the call raises and removes nothing. `libcurl-oracle` uses the first, whose
   removal is in a `dynamic-wind`. `tests/test-library-loading.sps` uses the second, which removes its directory
   when the process exits, by `exit` or by a raise nothing guards.
5. **The Chez floor's edges.** `(curl private require-threaded)` refuses `10.4.0-pre-release.N` and accepts
   `10.5.0-pre-release.N` and 10.10.0. It asks `(scheme-version #t)`, only at the floor, and not
   `(scheme-pre-release)`.
6. **`libcurl-info` is opaque.** `record-rtd` on a genuine report raises.

Every mutation was applied to a fresh copy of the working tree, made without `.git`, `.claude` and `build/`, with
`manifest.scm` touched (`traps.md`, the stale `guix shell -m` profile), in the session scratchpad. The working tree
was never edited by a mutation. The driver refused a mutation whose diff was empty and one whose target did not
occur exactly once; it refused AL23 for an anchor that did not match, and the mutant was written again. Each
command ran the suite alone, so its `FAIL` lines show, and then `make test`. A mutant counts as killed only when
the command exits non-zero and every expected line appears whole in its output: the test's `FAIL` line, with the
test's full name. Three mutants loop (AL33, TD15 and TD19). They ran under `timeout` or `ulimit`, and a watcher killed
any `check-seam` or probe Chez left running after 45 or 20 seconds. Every output is kept verbatim, with one cut: a
line over 240 characters is cut, and says how much. **Result** quotes each run's `FAIL` lines with the suite's
expected and actual values, its counts, and `make test`'s `test: FAIL` or `HUNG` and `check-seam:` lines.

Part 5 already has mutants named `SM`, `TM` and `FR`, so the mutants here are named `AL` (the allowlists and the
rest of `tests/check-seam.sps`), `SC` (the scan in `tests/test-require-threaded.sps`), `FL` (the floor), `TD`
(`(curl-testing)`'s directories), `OC` (the oracle), `OP` (the record), `FX` (the fixtures), `SR` (the real tree under
`src/`) and `RV` (the reviewer's trees).

### Corrections and changes to earlier parts

- **Part 5 said "Emacs lock files (`.#*`) are skipped".** A name starting with `.#` is skipped only when it is a
  dangling symbolic link. Part 5's SM58 (a `.#` inside a name was skipped), K2 and K3 lived in the scratch
  driver; AL49 to AL51 and the `dangling-*` fixtures replace them.
- **Part 5's `forbidden-chez-names`** (twelve names) **is `allowed-chez-names`** (nineteen). Part 5's findings
  about `interpret`, `compile` and `load-program` still hold: none is on the list.
- **Part 5's `check-seam` cases are fixtures now.** They were files planted in a copy by a scratch driver, so
  deleting a rule left `make test` and `make check-test-fails` green. They run in `make test`.
- **Part 5 said no Chez older than 10.4.0 was here.** Chez 10.2.0 is in the Guix store, and the refusal ran on
  it, below. The suite still expands copies of the refusal's source: the store is no part of the project.

### Measured first

Each was measured before any code changed, in the container or, for the stored Chez versions, on the host with
the store's own binary.

- **The reviewer's trees pass the old program.** `exp/seam/src` holds `import-only`, `top-level-value`, `($system)`,
  `$primitive`, `expand` and `#%eval` libraries, each meant to reach `(http-client target)`, and `exp/dot/src` a
  regular `.#g.sls`. Both, run through the program as it stood when this part began (`STOP-BEFORE`):
```
=== seam-src
check-seam: the seam holds (7 libraries in 7 files checked)
exit 0
=== dot-src
check-seam: the seam holds (2 libraries in 2 files checked)
exit 0
```
- **`#%eval` alone is no bypass.** `exp/seam/src/curl/h.sls` imports only `(rnrs)` and writes `#%eval`, which reads
  as `($primitive eval)`. `$primitive` is syntax that `(chezscheme)` exports, so the library does not expand:
  `Exception in environment: attempt to reference unbound identifier $primitive`. The allowlist keeps `$primitive`
  from being imported, which closes this route too.
- **`(scheme-pre-release)` exists in 10.4.0 and answers `#f`.** It takes no argument (`procedure-arity-mask` 1), and
  `(scheme-pre-release 1)` raises an argument-count error. It answers `#f` for a release and a positive fixnum for
  a pre-release (`csug/system.stex` and `s/7.ss` in the Chez source; the Guix store holds 10.2.0, 10.4.0 and 10.4.1,
  and all three export it). `(scheme-version-number)` answers the numbers of the release the pre-release precedes,
  and `10.4.0-pre-release.N` comes before 10.4.0. `(scheme-version #t)` adds `-pre-release.N` to the text for a
  pre-release, and `(scheme-version)` never does. Both answer `"Chez Scheme Version 10.4.0"` here.
- **A name a Chez lacks is a bare error at import.** `(only (chezscheme) scheme-build-number)` on 10.4.0:
  `Exception: missing import for scheme-build-number (only (chezscheme) ...)`. `scheme-pre-release` is in 10.2.0,
  10.4.0 and 10.4.1; it was not measured on an older Chez (none is here), and the refusal exists for one. Importing
  a name such a Chez might lack would replace the refusal with that error. So the refusal asks `scheme-version`,
  which every Chez has, with `#t`, and only at the floor, where the Chez takes the argument.
- **The refusal on a real older Chez.** `(curl private require-threaded)` imported by a program, with `--libdirs src`
  and the store's own binaries (`STOP-OLDER-CHEZ`):
```
== chez-scheme-10.2.0
Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.2.0 (require-supported-chez) at line 92, char 3 of src/curl/private/require-threaded.sls
== chez-scheme-10.4.0
Chez Scheme Version 10.4.0 loaded
== chez-scheme-10.4.1
Chez Scheme Version 10.4.1 loaded
```
- **An uncaught raise does not call the exit handler.** A program that sets `(exit-handler)` and then raises exits 255
  without calling it. `abort-handler` and `reset-handler` are not called either. `(base-exception-handler)` is: `base
  handler ran`, then Chez's message, exit 255. `(exit 1)` calls the exit handler. A `warning` goes through the same
  base handler, and the program goes on. A program that falls off its last form calls neither handler: the
  first run of the `make-process-temp-directory` rows, before `(exit 0)` ended them, answered `(0 under-tmpdir () left)`.
  The programs and their output are in the scratchpad's `MEASURE.txt`.
- **R6RS bodies take no definition after an expression.** `(define (f) (define a 1) (display a) (define b 2) b)`
  in `#!r6rs`: `Exception: invalid context for definition (define b (+ a 1))`. So `tests/test-library-loading.sps`, flat
  top-level forms with its scratch directory in the middle, cannot be wrapped in one `dynamic-wind`.
- **`putenv` cannot unset.** Chez has no `unsetenv`, and no foreign entry for one (`no entry for "unsetenv"`). The
  suites that set `TMPDIR` put it back to its old value, or to `/tmp` when it was unset, which is where `mktemp` and
  `capture-command` go anyway.
- **`record-rtd` on an opaque record raises** `&assertion`, who `record-rtd`, message `"~s is not a record"`. On a
  record that is not opaque it answers the type, and `(record-type-name rtd)` is `tr`.
- **Chez writes the symbol `.#g` as `\x2E;\x23;g`.** The first expectation for `lock-regular` and `lock-directory`
  guessed `\x2e;#g`. The green run showed the difference, and the text became what Chez writes.
- **`library-list` names 26 `(rnrs ...)` libraries**, `(rnrs eval)` among them. `rnrs-libraries` lists the other 25.

### Red runs

**`check-seam`'s new cases against the program as it was.** The cases were written first, and the suite then
had 35 rows. Nine failed by name, and 26 passed: they say what the program already did (rules (a) to (d), the
unread endings, the fail-closed cases), and are held by the mutants below. In `lock-regular` and `lock-directory`
the expected symbol was the first guess above; the actual values, `holds` and `no libraries`, are the red
(`SEAM-RED`):
```
%%%% Starting test check-seam
FAIL name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body
  expected: (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL name-top-level-value: a name outside allowed-chez-names: top-level-value, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL name-primitive: a name outside allowed-chez-names: $primitive, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environment  [cut 106 characters]
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but a library may not import any of: import include include-library-declarations eval environment interaction-environ [cut 3438 characters]
FAIL unlisted-libraries: a library not on the import allowlist: a third-party one, (chezscheme csv7), ($system), (scheme csv7), a test library, a near-family name, an (rnrs ...) name R6RS lacks
  expected: (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 2165 characters]
  actual:   (0 "check-seam: the seam holds (9 libraries in 9 files checked)\n" "")
FAIL lock-regular: a .# regular file is no lock file: it is read and checked
  expected: (1 "" "check-seam: tests/fixtures/seam/lock-regular/curl/.#g.sls: (curl \\x2e;#g) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
FAIL lock-directory: a .# directory is no lock file: it is walked
  expected: (1 "" "check-seam: tests/fixtures/seam/lock-directory/curl/.#dir/bad.sls: (curl \\x2e;#dir bad) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n" [cut 1 characters]
  actual:   (1 "" "check-seam: no libraries: tests/fixtures/seam/lock-directory holds no .sls file, so there is no seam to check\ncheck-seam: FAILED (problems: 1)\n")
FAIL lock-symlink-live: a .# symbolic link that resolves to a library is no lock file: it is read
  expected: (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of expected passes      26
# of unexpected failures  9
suite-exit-status: exit 1 (pass 26, fail 9, xpass 0): a suite needs a pass, and no fail or xpass
```

**`libcurl-oracle` against the old oracle,** with `call-with-temp-directory` already in `(curl-testing)` and the
oracle not yet using it (`ORACLE-RED`). The first row is the reviewer's finding: the compile went into
the first word of mktemp's answer, a directory beside the real one, and the removal destroyed it, `destroyed`, and
left the real one, `left`:
```
%%%% Starting test library-loading
FAIL the oracle, with TMPDIR holding a space: the same report, the directory beside it kept, its own removed
  expected: (same kept removed)
  actual:   (same destroyed left)
FAIL the oracle, with a newline in TMPDIR: no oracle, and the directory named by the first line kept
  expected: (no-oracle kept)
  actual:   ((version . "8.20.0") destroyed)
FAIL the oracle, when a raise comes inside its directory: it answers no-oracle, and has removed the directory
  expected: (no-oracle raised 1 ())
  actual:   (no-oracle raised 1 ("tmp.CYZpekCDP4"))
# of expected passes      48
# of unexpected failures  3
suite-exit-status: exit 1 (pass 48, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
```

**`(curl-testing)`'s directory rows against the old behaviour** (mktemp's first word, no removal when PROC raises or
escapes, no checks, no hooks), `TEMP-RED`. Seventeen of 47 rows fail, and 30 pass:
```
%%%% Starting test curl-testing
FAIL call-with-temp-directory: the directory is removed when PROC raises, and the raise goes on
  expected: (boom removed)
  actual:   (boom left)
FAIL call-with-temp-directory: the directory is removed when PROC escapes
  expected: (escaped removed)
  actual:   (escaped left)
FAIL call-with-temp-directory: TMPDIR holding a space is one path; the directory beside it survives
  expected: (inside kept removed)
  actual:   (elsewhere destroyed left)
FAIL call-with-temp-directory: a newline in TMPDIR makes two lines, which it refuses; the directory named by the first survives
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
FAIL call-with-temp-directory refuses a mktemp that answers a relative path, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise kept called)
FAIL call-with-temp-directory refuses a mktemp that answers a path that is not there, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise kept called)
FAIL call-with-temp-directory refuses a mktemp that answers an empty line, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise kept called)
FAIL call-with-temp-directory refuses a mktemp that answers no newline, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
FAIL call-with-temp-directory refuses a mktemp that answers two lines, the first a directory, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
FAIL call-with-temp-directory refuses a mktemp that answers a directory and exit 1, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
FAIL remove-temp-directory: only an absolute path other than /
  expected: ((assertion-violation remove-temp-directory ("relative/dir")) (assertion-violation remove-temp-directory ("/")) (assertion-violation remove-temp-directory ("")) kept)
  actual:   (no-raise no-raise no-raise kept)
FAIL remove-temp-directory: a directory still there after rm is a raise
  expected: ((other-raise "could not remove the directory") still-there)
  actual:   (no-raise still-there)
FAIL make-process-temp-directory: removed by exit, which keeps its status
  expected: (3 under-tmpdir () removed)
  actual:   (3 under-tmpdir () left)
FAIL make-process-temp-directory: removed by a raise nothing guards, status 255
  expected: (255 under-tmpdir () removed)
  actual:   (255 under-tmpdir () left)
FAIL make-process-temp-directory: removed by a raise of a non-condition too
  expected: (255 under-tmpdir () removed)
  actual:   (255 under-tmpdir () left)
FAIL make-process-temp-directory: a raise a guard catches does not remove it
  expected: (0 under-tmpdir ("kept") removed)
  actual:   (0 under-tmpdir ("kept") left)
FAIL make-process-temp-directory: a warning, which goes on, does not remove it
  expected: (0 under-tmpdir ("kept") removed)
  actual:   (0 under-tmpdir ("kept") left)
# of expected passes      30
# of unexpected failures  17
```

**The refusal's rows against the refusal as it was.** First written for `(scheme-pre-release)` (`RT-RED`), and then
pointed at `(scheme-version #t)` when the older Chez was considered. FL1 and FL2 below are the same red for the
final rows:
```
%%%% Starting test require-threaded
FAIL the refusal asks (scheme-pre-release)
  expected: asks
  actual:   never-asks
FAIL where Chez is 10.3.0-pre-release.2, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0-pre-release.2")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
FAIL where Chez is 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   loaded
FAIL where Chez is 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.7")
  actual:   loaded
# of expected passes      44
# of unexpected failures  4
suite-exit-status: exit 1 (pass 44, fail 4, xpass 0): a suite needs a pass, and no fail or xpass
```

**The record's opacity against the record as it was** (`OPAQUE-RED`):
```
%%%% Starting test native
FAIL the report is opaque: record-rtd on a genuine one raises an assertion violation
  expected: (assertion-violation record-rtd)
  actual:   (no-raise libcurl-info)
# of expected passes      8
# of unexpected failures  1
suite-exit-status: exit 1 (pass 8, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
```

**The real tree against the allowlist** (`SEAM-REAL-NEW-NAME`). The refusal had begun to import `scheme-version`, and
`allowed-chez-names` did not list it yet. `make check-seam` named the file and the name; adding the name to the list
was the reviewed change:
```
check-seam: src/curl/private/require-threaded.sls: (curl private require-threaded) imports scheme-version from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: FAILED (problems: 1)
make: *** [Makefile:233: check-seam] Error 1
```


### Code mutants: `check-seam`'s allowlists (fix 1) and its standing tests (fix 3)

93 mutations ran. 92 were killed, each with every expected line present. One survived, AL48, which the next group
explains. Two controls passed, as they must (FX1, SR5), and the reviewer's two trees fail by name (RV1, RV2).
Each mutant here breaks or weakens one rule of `tests/check-seam.sps` and runs `tests/test-check-seam.sps`, whose cases
name what failed. The table after the last group says which mutants failed each case. All 54 ran against the finished
suite, with 41 rows. A first run of 49, against the suite as it stood before three `dangling-*` fixtures and two list
rows were added, ended with AL23 refused for an anchor that did not match, AL43 with the wrong rows expected, and AL49
alive (Findings). Every output quoted here is from the second run.

#### AL1. Allowed-chez-names also lists import-only

**Guards:** `name-import-only`, "allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)".
**Mutation:**
In `tests/check-seam.sps`:
```diff
-make-ftype-pointer scheme-version scheme-version-number threaded?))
+make-ftype-pointer scheme-version scheme-version-number threaded? import-only))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body
  expected: (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  expected: (define-ftype display-condition file-regular? foreign-alloc foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof format format-condition? ftype-ref getenv load-shared-object machine-type make-ftype-pointer sc [cut 45 characters]
  actual:   (define-ftype display-condition file-regular? foreign-alloc foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof format format-condition? ftype-ref getenv import-only load-shared-object machine-type make-ftyp [cut 57 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL2. Allowed-chez-names also lists eval

**Guards:** `names-several`, `names-denylisted`, "allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)".
**Mutation:**
In `tests/check-seam.sps`:
```diff
-make-ftype-pointer scheme-version scheme-version-number threaded?))
+make-ftype-pointer scheme-version scheme-version-number threaded? eval))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1747 characters]
FAIL allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  expected: (define-ftype display-condition file-regular? foreign-alloc foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof format format-condition? ftype-ref getenv load-shared-object machine-type make-ftype-pointer sc [cut 45 characters]
  actual:   (define-ftype display-condition eval file-regular? foreign-alloc foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof format format-condition? ftype-ref getenv load-shared-object machine-type make-ftype-point [cut 50 characters]
# of unexpected failures  3
suite-exit-status: exit 1 (pass 38, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL3. Allowed-chez-names loses format, which src/ and the legal tree import

**Guards:** `legal`, "allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)".
**Mutation:**
In `tests/check-seam.sps`:
```diff
-foreign-sizeof format
-    format-condition?
+foreign-sizeof
+    format-condition?
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl.sls: (curl) imports format from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/legal/curl/private/thing.sls: (curl [cut 151 characters]
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports format from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sl [cut 315 characters]
FAIL allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  expected: (define-ftype display-condition file-regular? foreign-alloc foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof format format-condition? ftype-ref getenv load-shared-object machine-type make-ftype-pointer sc [cut 45 characters]
  actual:   (define-ftype display-condition file-regular? foreign-alloc foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof format-condition? ftype-ref getenv load-shared-object machine-type make-ftype-pointer scheme-ve [cut 38 characters]
# of unexpected failures  3
suite-exit-status: exit 1 (pass 38, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: src/curl/private/native.sls: (curl private native) imports format from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: FAILED (problems: 1)
make: *** [Makefile:235: check-seam] Error 1
make test exit 2
```

#### AL4. The name filter inverted: it complains about the listed names

**Guards:** `name-import-only`, `name-top-level-value`, `name-primitive`, `names-several`, and 1 more.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(remp (lambda (id) (memq id allowed-chez-names)) names)
+(filter (lambda (id) (memq id allowed-chez-names)) names)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl.sls: (curl) imports format from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/legal/curl.sls: (curl) imports thre [cut 308 characters]
FAIL name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body
  expected: (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL name-top-level-value: a name outside allowed-chez-names: top-level-value, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL name-primitive: a name outside allowed-chez-names: $primitive, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports format from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sl [cut 150 characters]
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  6
suite-exit-status: exit 1 (pass 35, fail 6, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: src/curl/private/native.sls: (curl private native) imports define-ftype from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports ftype-ref from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports make-ftype-pointer from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports foreign-procedure from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports foreign-entry? from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports load-shared-object from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports foreign-alloc from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports foreign-free from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports foreign-ref from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports foreign-sizeof from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports format from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports format-condition? from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports display-condition from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports getenv from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports machine-type from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/native.sls: (curl private native) imports file-regular? from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/require-threaded.sls: (curl private require-threaded) imports threaded? from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: src/curl/private/require-threaded.sls: (curl private require-threaded) imports scheme-version from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
[4 more lines]
```

#### AL5. No name is ever complained about

**Guards:** `name-import-only`, `name-top-level-value`, `name-primitive`, `names-several`, and 1 more.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(remp (lambda (id) (memq id allowed-chez-names)) names)
+'()
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body
  expected: (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL name-top-level-value: a name outside allowed-chez-names: top-level-value, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL name-primitive: a name outside allowed-chez-names: $primitive, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  5
suite-exit-status: exit 1 (pass 36, fail 5, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL6. Only the first name outside the list is named

**Guards:** `names-several`, `names-denylisted`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(remp (lambda (id) (memq id allowed-chez-names)) names)
+(let ((bad (remp (lambda (id) (memq id allowed-chez-names)) names))) (if (pair? bad) (list (car bad)) bad))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL7. The message leaves out the name

**Guards:** `name-import-only`, `name-top-level-value`, `name-primitive`, `names-several`, and 1 more.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(symbol->string id)
-                             " from (chezscheme), but allowed-chez-names in"
+"a name"
+                             " from (chezscheme), but allowed-chez-names in"
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body
  expected: (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports a name from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
FAIL name-top-level-value: a name outside allowed-chez-names: top-level-value, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports a name from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
FAIL name-primitive: a name outside allowed-chez-names: $primitive, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports a name from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports a name from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sl [cut 147 characters]
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports a name from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1844 characters]
# of unexpected failures  5
suite-exit-status: exit 1 (pass 36, fail 5, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL8. (scheme) is no alias of (chezscheme)

**Guards:** `scheme-alias`, `chez-wrapped`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(define chez-names '((chezscheme) (scheme)))
+(define chez-names '((chezscheme)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL scheme-alias: (scheme), the alias, imported whole
  expected: (1 "" "check-seam: tests/fixtures/seam/scheme-alias/curl/s.sls: (curl s) imports (scheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/scheme-alias/curl/s.sls: (curl s) imports (scheme), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (h [cut 63 characters]
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1920 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL9. (chezscheme) imported whole is no complaint

**Guards:** `chez-whole`, `scheme-alias`, `chez-wrapped`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(not names)
-       (list (string-append path ": " (written name) " imports "
-                            (abbreviated spec)
+(and #f names)
+       (list (string-append path ": " (written name) " imports "
+                            (abbreviated spec)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL chez-whole: (chezscheme) imported whole
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-whole/curl/w.sls: (curl w) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (255 "" "Exception in for-all: #f is not a proper list\n")
FAIL scheme-alias: (scheme), the alias, imported whole
  expected: (1 "" "check-seam: tests/fixtures/seam/scheme-alias/curl/s.sls: (curl s) imports (scheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (255 "" "Exception in for-all: #f is not a proper list\n")
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (255 "" "Exception in for-all: #f is not a proper list\n")
# of unexpected failures  3
suite-exit-status: exit 1 (pass 38, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL10. Except is no import-set wrapper

**Guards:** `chez-wrapped`, `legal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(define wrappers '(for only except prefix rename))
+(define wrappers '(for only prefix rename))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl/private/thing.sls: (curl private thing) imports (except), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and  [cut 80 characters]
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and  [cut 1917 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL11. For is no import-set wrapper

**Guards:** `chez-wrapped`, `legal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(define wrappers '(for only except prefix rename))
+(define wrappers '(only except prefix rename))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl/private/thing.sls: (curl private thing) imports (for), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (cu [cut 77 characters]
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1948 characters]
FAIL rnrs-eval: (rnrs eval), plain and wrapped
  expected: (1 "" "check-seam: tests/fixtures/seam/rnrs-eval/curl/e1.sls: (curl e1) imports (rnrs eval), but no library under src/ may import (rnrs eval)\ncheck-seam: tests/fixtures/seam/rnrs-eval/curl/e2.sls: (curl e2) imports (rnrs eval), [cut 87 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/rnrs-eval/curl/e1.sls: (curl e1) imports (rnrs eval), but no library under src/ may import (rnrs eval)\ncheck-seam: tests/fixtures/seam/rnrs-eval/curl/e2.sls: (curl e2) imports (for), but a [cut 195 characters]
# of unexpected failures  3
suite-exit-status: exit 1 (pass 38, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL12. Prefix is no import-set wrapper

**Guards:** `chez-wrapped`, `legal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(define wrappers '(for only except prefix rename))
+(define wrappers '(for only except rename))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl/private/thing.sls: (curl private thing) imports (prefix), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and  [cut 80 characters]
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1954 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL13. Rename is no import-set wrapper

**Guards:** `chez-wrapped`, `legal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(define wrappers '(for only except prefix rename))
+(define wrappers '(for only except prefix))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl/private/thing.sls: (curl private thing) imports (rename), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and  [cut 80 characters]
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1911 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL14. Only is no import-set wrapper

**Guards:** `chez-wrapped`, `legal`, `name-import-only`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(define wrappers '(for only except prefix rename))
+(define wrappers '(for except prefix rename))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl.sls: (curl) imports (only), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (http-client .. [cut 841 characters]
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 2055 characters]
FAIL name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body
  expected: (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports (only), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and  [cut 65 characters]
FAIL name-top-level-value: a name outside allowed-chez-names: top-level-value, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports (only), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...)  [cut 69 characters]
FAIL name-primitive: a name outside allowed-chez-names: $primitive, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports (only), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (h [cut 63 characters]
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports (only), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (ht [cut 62 characters]
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports (only), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and  [cut 65 characters]
FAIL names-not-symbols: an only over (chezscheme) with a name that is no identifier
  expected: (1 "" "check-seam: tests/fixtures/seam/names-not-symbols/curl/n.sls: (curl n) has an import it cannot read: (only (chezscheme) 42)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-not-symbols/curl/n.sls: (curl n) imports (only), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and [cut 66 characters]
FAIL rnrs-eval: (rnrs eval), plain and wrapped
  expected: (1 "" "check-seam: tests/fixtures/seam/rnrs-eval/curl/e1.sls: (curl e1) imports (rnrs eval), but no library under src/ may import (rnrs eval)\ncheck-seam: tests/fixtures/seam/rnrs-eval/curl/e2.sls: (curl e2) imports (rnrs eval), [cut 87 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/rnrs-eval/curl/e1.sls: (curl e1) imports (rnrs eval), but no library under src/ may import (rnrs eval)\ncheck-seam: tests/fixtures/seam/rnrs-eval/curl/e2.sls: (curl e2) imports (only), but  [cut 196 characters]
FAIL unlisted-libraries: a library not on the import allowlist: a third-party one, (chezscheme csv7), ($system), (scheme csv7), a test library, a near-family name, an (rnrs ...) name R6RS lacks
  expected: (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 2165 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 2158 characters]
FAIL cannot-read-import: an import it cannot read: a number, an empty list, a bare only, and a cyclic datum
  expected: (1 "" "check-seam: tests/fixtures/seam/cannot-read-import/curl/m1.sls: (curl m1) has an import it cannot read: 42\ncheck-seam: tests/fixtures/seam/cannot-read-import/curl/m2.sls: (curl m2) has an import it cannot read: ()\ncheck [cut 264 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/cannot-read-import/curl/m1.sls: (curl m1) has an import it cannot read: 42\ncheck-seam: tests/fixtures/seam/cannot-read-import/curl/m2.sls: (curl m2) has an import it cannot read: ()\ncheck [cut 539 characters]
# of unexpected failures  11
suite-exit-status: exit 1 (pass 30, fail 11, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: src/curl/private/native.sls: (curl private native) imports (only), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (http-client ...) librarie [cut 1 characters]
check-seam: src/curl/private/require-threaded.sls: (curl private require-threaded) imports (only), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (http- [cut 21 characters]
check-seam: FAILED (problems: 2)
[2 more lines]
```

#### AL15. (library ...) is no import-set wrapper

**Guards:** `chez-wrapped`, `legal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-((eq? (car spec) 'library)
-     (and (= (length spec) 2) (reference-name (cadr spec))))
+((eq? (car spec) 'library)
+     #f)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl/private/thing.sls: (curl private thing) has an import it cannot read: (library (rnrs unicode))\ncheck-seam: FAILED (problems: 1)\n")
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1718 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL16. (rnrs eval) has no message of its own: its branch is gone

**Guards:** `rnrs-eval`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-      ((member imported eval-libraries)
-       (list (string-append path ": " (written name) " imports "
-                            (written imported)
-                            ", but no library under src/ may import "
-                            (written imported))))
+
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL rnrs-eval: (rnrs eval), plain and wrapped
  expected: (1 "" "check-seam: tests/fixtures/seam/rnrs-eval/curl/e1.sls: (curl e1) imports (rnrs eval), but no library under src/ may import (rnrs eval)\ncheck-seam: tests/fixtures/seam/rnrs-eval/curl/e2.sls: (curl e2) imports (rnrs eval), [cut 87 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/rnrs-eval/curl/e1.sls: (curl e1) imports (rnrs eval), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and  [cut 315 characters]
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL17. (rnrs eval) is on the allowlist and its branch is gone

**Guards:** `rnrs-eval`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-      ((member imported eval-libraries)
-       (list (string-append path ": " (written name) " imports "
-                            (written imported)
-                            ", but no library under src/ may import "
-                            (written imported))))
+
```
In `tests/check-seam.sps`:
```diff
-(define rnrs-libraries
-  '((rnrs) (rnrs base)
+(define rnrs-libraries
+  '((rnrs) (rnrs eval) (rnrs base)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL rnrs-eval: (rnrs eval), plain and wrapped
  expected: (1 "" "check-seam: tests/fixtures/seam/rnrs-eval/curl/e1.sls: (curl e1) imports (rnrs eval), but no library under src/ may import (rnrs eval)\ncheck-seam: tests/fixtures/seam/rnrs-eval/curl/e2.sls: (curl e2) imports (rnrs eval), [cut 87 characters]
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)
  expected: ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs enums) (rnrs exceptions) (rnrs files) (rnrs hashtables) (rnrs io ports) (rnrs i [cut 228 characters]
  actual:   ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs enums) (rnrs eval) (rnrs exceptions) (rnrs files) (rnrs hashtables) (rnrs io po [cut 240 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL18. A library off the allowlist is no complaint

**Guards:** `unlisted-libraries`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-      (else
-       (list (string-append path ": " (written name) " imports "
-                            (written imported)
-                            ", but a library under src/ may import only the"
+      ((not (not imported)) '())
+      (else
+       (list (string-append path ": " (written name) " imports "
+                            (written imported)
+                            ", but a library under src/ may import only the"
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL unlisted-libraries: a library not on the import allowlist: a third-party one, (chezscheme csv7), ($system), (scheme csv7), a test library, a near-family name, an (rnrs ...) name R6RS lacks
  expected: (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 2165 characters]
  actual:   (0 "check-seam: the seam holds (9 libraries in 9 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL19. (rnrs io ports) is not on the allowlist

**Guards:** `legal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(rnrs hashtables) (rnrs io ports) (rnrs io simple)
+(rnrs hashtables) (rnrs io simple)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl.sls: (curl) imports (rnrs io ports), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (http- [cut 59 characters]
FAIL rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)
  expected: ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs enums) (rnrs exceptions) (rnrs files) (rnrs hashtables) (rnrs io ports) (rnrs i [cut 228 characters]
  actual:   ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs enums) (rnrs exceptions) (rnrs files) (rnrs hashtables) (rnrs io simple) (rnrs  [cut 212 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL20. (rnrs) itself is not on the allowlist

**Guards:** `legal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-  '((rnrs) (rnrs base) (rnrs arithmetic bitwise)
+  '((rnrs base) (rnrs arithmetic bitwise)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl.sls: (curl) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (http-client .. [cut 1331 characters]
FAIL rule-a: rule (a): a (curl ...) library importing an (http-client ...) library
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (http-client y), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (http-clie [cut 207 characters]
FAIL rule-b: rule (b): an (http-client ...) library importing a (curl ...) library that is not public
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-b/http-client/z.sls: (http-client z) imports (curl private thing), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))\ncheck-seam: FAILED (proble [cut 10 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/rule-b/http-client/z.sls: (http-client z) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...)  [cut 264 characters]
FAIL second-library: every library form in a file is checked, the second included
  expected: (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two.sls: (curl two-a) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...)  [cut 494 characters]
FAIL neither-family: rule (d): a library in neither family
  expected: (1 "" "check-seam: tests/fixtures/seam/neither-family/util.sls: (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/neither-family/util.sls: (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client\ncheck-seam: tests/fixtures/seam/neither-family/ut [cut 231 characters]
FAIL chez-whole: (chezscheme) imported whole
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-whole/curl/w.sls: (curl w) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/chez-whole/curl/w.sls: (curl w) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (http- [cut 241 characters]
FAIL scheme-alias: (scheme), the alias, imported whole
  expected: (1 "" "check-seam: tests/fixtures/seam/scheme-alias/curl/s.sls: (curl s) imports (scheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/scheme-alias/curl/s.sls: (curl s) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (htt [cut 241 characters]
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (h [cut 4348 characters]
FAIL name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body
  expected: (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and  [cut 513 characters]
FAIL name-top-level-value: a name outside allowed-chez-names: top-level-value, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...)  [cut 529 characters]
FAIL name-primitive: a name outside allowed-chez-names: $primitive, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (h [cut 506 characters]
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (ht [cut 396 characters]
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports (rnrs), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and  [cut 2164 characters]
FAIL names-not-symbols: an only over (chezscheme) with a name that is no identifier
[69 more lines]
```

#### AL21. Any library whose name starts with rnrs is allowed

**Guards:** `unlisted-libraries`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-      ((member imported rnrs-libraries)
-       '())
+      ((eq? (car imported) 'rnrs)
+       '())
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL unlisted-libraries: a library not on the import allowlist: a third-party one, (chezscheme csv7), ($system), (scheme csv7), a test library, a near-family name, an (rnrs ...) name R6RS lacks
  expected: (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 2165 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 1907 characters]
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL22. Any library whose name starts with chezscheme or scheme is allowed through the chez rules

**Guards:** `unlisted-libraries`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-      ((member imported chez-names)
-       (chez-complaints path name spec))
+      ((memq (car imported) '(chezscheme scheme))
+       (chez-complaints path name spec))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL unlisted-libraries: a library not on the import allowlist: a third-party one, (chezscheme csv7), ($system), (scheme csv7), a test library, a near-family name, an (rnrs ...) name R6RS lacks
  expected: (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 2165 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 2029 characters]
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL23. The version reference is not dropped from a library name

**Guards:** `legal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-             (and (pair? found) (reverse found))))))
+             (and (pair? found) (null? rest) (reverse found))))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/legal/curl/private/thing.sls: (curl private thing) has an import it cannot read: (rnrs (6))\ncheck-seam: FAILED (problems: 1)\n")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL24. Rule (a) is gone

**Guards:** `rule-a`, `second-library`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-      ((family? 'http-client imported)
-       (if (family? 'curl name)
+      ((family? 'http-client imported)
+       (if #f
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL rule-a: rule (a): a (curl ...) library importing an (http-client ...) library
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (http-client y), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
FAIL second-library: every library form in a file is checked, the second included
  expected: (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 1 files checked)\n" "")
FAIL lock-regular: a .# regular file is no lock file: it is read and checked
  expected: (1 "" "check-seam: tests/fixtures/seam/lock-regular/curl/.#g.sls: (curl \\x2E;\\x23;g) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
FAIL lock-directory: a .# directory is no lock file: it is walked
  expected: (1 "" "check-seam: tests/fixtures/seam/lock-directory/curl/.#dir/bad.sls: (curl \\x2E;\\x23;dir bad) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems:  [cut 6 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  4
suite-exit-status: exit 1 (pass 37, fail 4, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL25. Rule (b) is gone

**Guards:** `rule-b`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(if (and (family? 'http-client name) (not (member imported public-curl)))
+(if #f
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL rule-b: rule (b): an (http-client ...) library importing a (curl ...) library that is not public
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-b/http-client/z.sls: (http-client z) imports (curl private thing), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))\ncheck-seam: FAILED (proble [cut 10 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL26. Public-curl also lists (curl private thing)

**Guards:** `rule-b`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(define public-curl '((curl)))
+(define public-curl '((curl) (curl private thing)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL rule-b: rule (b): an (http-client ...) library importing a (curl ...) library that is not public
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-b/http-client/z.sls: (http-client z) imports (curl private thing), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))\ncheck-seam: FAILED (proble [cut 10 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL27. Rule (d) is gone

**Guards:** `neither-family`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(if (memq (car name) families)
-         '()
+(if #t
+         '()
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL neither-family: rule (d): a library in neither family
  expected: (1 "" "check-seam: tests/fixtures/seam/neither-family/util.sls: (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL28. A datum that is no library form is no complaint

**Guards:** `not-a-library`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(list (string-append path ": datum " (number->string n)
-                                             " is " (abbreviated (car rest))
-                                             ", not a library form")))
+'())
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL not-a-library: a datum that is no library form, the first or a later one
  expected: (1 "" "check-seam: tests/fixtures/seam/not-a-library/curl/d1.sls: datum 1 is (define x 1), not a library form\ncheck-seam: tests/fixtures/seam/not-a-library/curl/d2.sls: datum 2 is (define y 2), not a library form\ncheck-seam: F [cut 23 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 2 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL29. A file with no datum is no complaint

**Guards:** `no-datum`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(list (string-append path ": it holds no datum, so it holds no library form"))
+'()
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL no-datum: a file that holds no datum
  expected: (1 "" "check-seam: tests/fixtures/seam/no-datum/curl.sls: it holds no datum, so it holds no library form\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (0 libraries in 1 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL30. An #!eof literal is no complaint

**Guards:** `eof-literal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-((port-eof? port) (list 'data (reverse found)))
+(#t (list 'data (reverse found)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL eof-literal: a file with an #!eof literal, which would end the reading early
  expected: (1 "" "check-seam: tests/fixtures/seam/eof-literal/curl/eof.sls: it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL31. An unreadable file is read as empty

**Guards:** `unreadable`, `eof-literal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(guard (e (#t (list 'unreadable (describe e))))
-    (call-with-port (open-file-input-port path
+(guard (e (#t (list 'data '())))
+    (call-with-port (open-file-input-port path
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL dangling-link: a dangling symbolic link not named .# is no lock file: it is named, for it cannot be read
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-link/curl/dangling.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-link/curl/dangling.sls: no such file or directory\nche [cut 33 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/dangling-link/curl/dangling.sls: it holds no datum, so it holds no library form\ncheck-seam: FAILED (problems: 1)\n")
FAIL dangling-dot-link: a dangling symbolic link named with a dot but not .# is no lock file
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: no such file or dire [cut 43 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: it holds no datum, so it holds no library form\ncheck-seam: FAILED (problems: 1)\n")
FAIL dangling-hash-link: a dangling symbolic link with .# inside its name, not at its start, is no lock file
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: no such file or directory\nc [cut 35 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: it holds no datum, so it holds no library form\ncheck-seam: FAILED (problems: 1)\n")
FAIL unreadable: a file that cannot be read as data
  expected: (1 "" "check-seam: tests/fixtures/seam/unreadable/curl/broken.sls: it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 48 of #<input port tests/fixtures/seam/unreadable/curl/bro [cut 83 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unreadable/curl/broken.sls: it holds no datum, so it holds no library form\ncheck-seam: FAILED (problems: 1)\n")
FAIL eof-literal: a file with an #!eof literal, which would end the reading early
  expected: (1 "" "check-seam: tests/fixtures/seam/eof-literal/curl/eof.sls: it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/eof-literal/curl/eof.sls: it holds no datum, so it holds no library form\ncheck-seam: FAILED (problems: 1)\n")
# of unexpected failures  5
suite-exit-status: exit 1 (pass 36, fail 5, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL32. Only the first datum of a file is checked

**Guards:** `second-library`, `not-a-library`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-      (let loop ((rest data) (n 1))
-        (if (null? rest)
+      (let loop ((rest (list (car data))) (n 1))
+        (if (null? rest)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL second-library: every library form in a file is checked, the second included
  expected: (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 1 files checked)\n" "")
FAIL not-a-library: a datum that is no library form, the first or a later one
  expected: (1 "" "check-seam: tests/fixtures/seam/not-a-library/curl/d1.sls: datum 1 is (define x 1), not a library form\ncheck-seam: tests/fixtures/seam/not-a-library/curl/d2.sls: datum 2 is (define y 2), not a library form\ncheck-seam: F [cut 23 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/not-a-library/curl/d1.sls: datum 1 is (define x 1), not a library form\ncheck-seam: FAILED (problems: 1)\n")
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL33. The depth limit is gone: the cyclic import never ends, and make test names the suite HUNG

**Guards:** `make test`'s HUNG line.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-((or (not (list? spec)) (null? spec) (> depth max-depth)) #f)
+((or (not (list? spec)) (null? spec)) #f)
```
**Result:** killed, exit 2; the lines that name it:
```
suite exit 124
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: HUNG tests/test-check-seam.sps (no exit within 30s)
test: ran 10, passed 9, failed 0, hung 1
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL34. A malformed import is no complaint

**Guards:** `cannot-read-import`, `names-not-symbols`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(define (cannot-read path name spec)
-  (string-append path ": " (written name)
-                 " has an import it cannot read: " (abbreviated spec)))
+(define (cannot-read path name spec) "")
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL names-not-symbols: an only over (chezscheme) with a name that is no identifier
  expected: (1 "" "check-seam: tests/fixtures/seam/names-not-symbols/curl/n.sls: (curl n) has an import it cannot read: (only (chezscheme) 42)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: \ncheck-seam: FAILED (problems: 1)\n")
FAIL cannot-read-import: an import it cannot read: a number, an empty list, a bare only, and a cyclic datum
  expected: (1 "" "check-seam: tests/fixtures/seam/cannot-read-import/curl/m1.sls: (curl m1) has an import it cannot read: 42\ncheck-seam: tests/fixtures/seam/cannot-read-import/curl/m2.sls: (curl m2) has an import it cannot read: ()\ncheck [cut 264 characters]
  actual:   (1 "" "check-seam: \ncheck-seam: \ncheck-seam: \ncheck-seam: \ncheck-seam: FAILED (problems: 4)\n")
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL35. .ss is not an unread ending

**Guards:** `unread-ss`, `unread-extensions`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(remp (lambda (ext) (string=? ext ".sls"))
+(remp (lambda (ext) (member ext '(".sls" ".ss")))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL unread-ss: a .ss file, which Chez loads as a library and the program does not read
  expected: (1 "" "check-seam: tests/fixtures/seam/unread-ss/curl/hidden.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
FAIL unread-extensions: every unread ending, each named for its longest: .ss .scm .sch .chezscheme.sls .so .chezscheme.so
  expected: (1 "" "check-seam: tests/fixtures/seam/unread-extensions/curl/a.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/\ncheck-seam: tests/fixtures/seam/unread- [cut 957 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unread-extensions/curl/b.scm: Chez could load a library from a file ending in .scm, and this check does not read one; rename it or keep it out of src/\ncheck-seam: tests/fixtures/seam/unrea [cut 775 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL36. The compiled .so endings are not unread endings

**Guards:** `unread-so`, `unread-extensions`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(remp (lambda (ext) (string=? ext ".sls"))
+(remp (lambda (ext) (member ext '(".sls" ".so" ".chezscheme.so")))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL unread-so: a lone .so, with no source beside it, whatever it holds
  expected: (1 "" "check-seam: tests/fixtures/seam/unread-so/curl/lone.so: Chez could load a library from a file ending in .so, and this check does not read one; rename it or keep it out of src/\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
FAIL unread-extensions: every unread ending, each named for its longest: .ss .scm .sch .chezscheme.sls .so .chezscheme.so
  expected: (1 "" "check-seam: tests/fixtures/seam/unread-extensions/curl/a.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/\ncheck-seam: tests/fixtures/seam/unread- [cut 957 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unread-extensions/curl/a.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/\ncheck-seam: tests/fixtures/seam/unread- [cut 571 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL37. Unread endings are tried shortest first

**Guards:** `unread-extensions`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(lambda (a b) (> (string-length a) (string-length b)))
+(lambda (a b) (< (string-length a) (string-length b)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL unread-extensions: every unread ending, each named for its longest: .ss .scm .sch .chezscheme.sls .so .chezscheme.so
  expected: (1 "" "check-seam: tests/fixtures/seam/unread-extensions/curl/a.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/\ncheck-seam: tests/fixtures/seam/unread- [cut 957 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unread-extensions/curl/a.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/\ncheck-seam: tests/fixtures/seam/unread- [cut 946 characters]
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL38. A symbolic link to a directory is no complaint

**Guards:** `dir-symlink`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(map (lambda (link)
-                      (string-append link ": it is a symbolic link to a directory,"
-                                     " which this check does not follow"))
-                    links)
+'()
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL dir-symlink: a symbolic link to a directory, which the program does not follow
  expected: (1 "" "check-seam: tests/fixtures/seam/dir-symlink/linked: it is a symbolic link to a directory, which this check does not follow\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL39. No libraries is no complaint

**Guards:** "an empty directory holds no library", "a directory that does not exist holds no library".
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(if (null? files)
-                   (list (string-append "no libraries: " root
-                                        " holds no .sls file, so there is no seam to check"))
-                   '())
+'()
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL an empty directory holds no library
  expected: refused
  actual:   (0 "check-seam: the seam holds (0 libraries in 0 files checked)\n" "")
FAIL a directory that does not exist holds no library
  expected: refused
  actual:   (0 "check-seam: the seam holds (0 libraries in 0 files checked)\n" "")
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL40. A directory that does not exist raises

**Guards:** "a directory that does not exist holds no library".
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(found (if (file-directory? root) (walk root) (list '() '() '())))
+(found (walk root))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL a directory that does not exist holds no library
  expected: refused
  actual:   (255 "" "Exception in directory-list: failed for /tmp/tmp.kg4qa9wDqY/no-such-directory: no such file or directory\n")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL41. The argument count is not checked

**Guards:** "no directory named: the usage line, exit 1", "two directories named: the usage line, exit 1".
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(if (not (= (length args) 1))
+(if #f
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL no directory named: the usage line, exit 1
  expected: (1 "" "check-seam: usage: scheme --program tests/check-seam.sps DIR\n")
  actual:   (255 "" "Exception in car: () is not a pair\n")
FAIL two directories named: the usage line, exit 1
  expected: (1 "" "check-seam: usage: scheme --program tests/check-seam.sps DIR\n")
  actual:   (1 "" "check-seam: no libraries: a holds no .sls file, so there is no seam to check\ncheck-seam: FAILED (problems: 1)\n")
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL42. The pass line counts files for libraries

**Guards:** `legal`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(number->string (apply + (map cdr results)))
+(number->string (length files))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   (0 "check-seam: the seam holds (4 libraries in 4 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL43. The failure count is the number of files, not of problems

**Guards:** `names-several`, `names-denylisted`, `unread-extensions`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(number->string (length complaints))
+(number->string (length files))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body
  expected: (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 2)\n")
FAIL name-top-level-value: a name outside allowed-chez-names: top-level-value, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 2)\n")
FAIL name-primitive: a name outside allowed-chez-names: $primitive, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 2)\n")
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1913 characters]
FAIL unread-extensions: every unread ending, each named for its longest: .ss .scm .sch .chezscheme.sls .so .chezscheme.so
  expected: (1 "" "check-seam: tests/fixtures/seam/unread-extensions/curl/a.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/\ncheck-seam: tests/fixtures/seam/unread- [cut 957 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unread-extensions/curl/a.ss: Chez could load a library from a file ending in .ss, and this check does not read one; rename it or keep it out of src/\ncheck-seam: tests/fixtures/seam/unread- [cut 957 characters]
FAIL lock-regular: a .# regular file is no lock file: it is read and checked
  expected: (1 "" "check-seam: tests/fixtures/seam/lock-regular/curl/.#g.sls: (curl \\x2E;\\x23;g) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/lock-regular/curl/.#g.sls: (curl \\x2E;\\x23;g) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 2)\n")
FAIL dangling-link: a dangling symbolic link not named .# is no lock file: it is named, for it cannot be read
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-link/curl/dangling.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-link/curl/dangling.sls: no such file or directory\nche [cut 33 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/dangling-link/curl/dangling.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-link/curl/dangling.sls: no such file or directory\nche [cut 33 characters]
FAIL dangling-dot-link: a dangling symbolic link named with a dot but not .# is no lock file
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: no such file or dire [cut 43 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: no such file or dire [cut 43 characters]
FAIL dangling-hash-link: a dangling symbolic link with .# inside its name, not at its start, is no lock file
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: no such file or directory\nc [cut 35 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: no such file or directory\nc [cut 35 characters]
FAIL unreadable: a file that cannot be read as data
  expected: (1 "" "check-seam: tests/fixtures/seam/unreadable/curl/broken.sls: it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 48 of #<input port tests/fixtures/seam/unreadable/curl/bro [cut 83 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unreadable/curl/broken.sls: it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 48 of #<input port tests/fixtures/seam/unreadable/curl/bro [cut 83 characters]
FAIL an empty directory holds no library
  expected: refused
  actual:   (1 "" "check-seam: no libraries: /tmp/tmp.Hz3kuZf3Yk holds no .sls file, so there is no seam to check\ncheck-seam: FAILED (problems: 0)\n")
FAIL a directory that does not exist holds no library
  expected: refused
  actual:   (1 "" "check-seam: no libraries: /tmp/tmp.CgRS78sEQI/no-such-directory holds no .sls file, so there is no seam to check\ncheck-seam: FAILED (problems: 0)\n")
# of unexpected failures  13
[8 more lines]
```

#### AL44. A failure exits 0

**Guards:** `rule-a`, `unread-ss`, `dir-symlink`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(say (current-error-port)
-                (string-append "FAILED (problems: "
-                               (number->string (length complaints)) ")"))
-           (exit 1))
+(say (current-error-port)
+                (string-append "FAILED (problems: "
+                               (number->string (length complaints)) ")"))
+           (exit 0))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL rule-a: rule (a): a (curl ...) library importing an (http-client ...) library
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (http-client y), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "" "check-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (http-client y), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
FAIL rule-b: rule (b): an (http-client ...) library importing a (curl ...) library that is not public
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-b/http-client/z.sls: (http-client z) imports (curl private thing), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))\ncheck-seam: FAILED (proble [cut 10 characters]
  actual:   (0 "" "check-seam: tests/fixtures/seam/rule-b/http-client/z.sls: (http-client z) imports (curl private thing), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))\ncheck-seam: FAILED (proble [cut 10 characters]
FAIL second-library: every library form in a file is checked, the second included
  expected: (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "" "check-seam: tests/fixtures/seam/second-library/curl/two.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
FAIL neither-family: rule (d): a library in neither family
  expected: (1 "" "check-seam: tests/fixtures/seam/neither-family/util.sls: (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "" "check-seam: tests/fixtures/seam/neither-family/util.sls: (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client\ncheck-seam: FAILED (problems: 1)\n")
FAIL chez-whole: (chezscheme) imported whole
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-whole/curl/w.sls: (curl w) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "" "check-seam: tests/fixtures/seam/chez-whole/curl/w.sls: (curl w) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
FAIL scheme-alias: (scheme), the alias, imported whole
  expected: (1 "" "check-seam: tests/fixtures/seam/scheme-alias/curl/s.sls: (curl s) imports (scheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "" "check-seam: tests/fixtures/seam/scheme-alias/curl/s.sls: (curl s) imports (scheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
FAIL chez-wrapped: (chezscheme) under except, prefix, rename, for, library, a nested only and (scheme)
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
  actual:   (0 "" "check-seam: tests/fixtures/seam/chez-wrapped/curl/w1.sls: (curl w1) imports (except (chezscheme) car), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: tests/fixt [cut 1866 characters]
FAIL name-import-only: a name outside allowed-chez-names: import-only, which opens an import in a body
  expected: (1 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "" "check-seam: tests/fixtures/seam/name-import-only/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
FAIL name-top-level-value: a name outside allowed-chez-names: top-level-value, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "" "check-seam: tests/fixtures/seam/name-top-level-value/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
FAIL name-primitive: a name outside allowed-chez-names: $primitive, which reaches eval
  expected: (1 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "" "check-seam: tests/fixtures/seam/name-primitive/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: FAILED (problems: 1)\n")
FAIL names-several: several names, some listed and some not: each one outside is named, in order
  expected: (1 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
  actual:   (0 "" "check-seam: tests/fixtures/seam/names-several/curl/n.sls: (curl n) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-several/curl/n.sls: [cut 149 characters]
FAIL names-denylisted: the names the old denylist held are outside the allowlist too
  expected: (1 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
  actual:   (0 "" "check-seam: tests/fixtures/seam/names-denylisted/curl/n.sls: (curl n) imports import from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/names-denylisted/cur [cut 1914 characters]
FAIL names-not-symbols: an only over (chezscheme) with a name that is no identifier
  expected: (1 "" "check-seam: tests/fixtures/seam/names-not-symbols/curl/n.sls: (curl n) has an import it cannot read: (only (chezscheme) 42)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "" "check-seam: tests/fixtures/seam/names-not-symbols/curl/n.sls: (curl n) has an import it cannot read: (only (chezscheme) 42)\ncheck-seam: FAILED (problems: 1)\n")
FAIL rnrs-eval: (rnrs eval), plain and wrapped
[62 more lines]
```

#### AL52. Rnrs-libraries also lists (rnrs foo), which R6RS has not

**Guards:** `unlisted-libraries`, "rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)".
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(rnrs unicode)))
+(rnrs unicode) (rnrs foo)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL unlisted-libraries: a library not on the import allowlist: a third-party one, (chezscheme csv7), ($system), (scheme csv7), a test library, a near-family name, an (rnrs ...) name R6RS lacks
  expected: (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 2165 characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/unlisted-libraries/curl/u1.sls: (curl u1) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl .. [cut 1907 characters]
FAIL rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)
  expected: ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs enums) (rnrs exceptions) (rnrs files) (rnrs hashtables) (rnrs io ports) (rnrs i [cut 228 characters]
  actual:   ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs enums) (rnrs exceptions) (rnrs files) (rnrs foo) (rnrs hashtables) (rnrs io por [cut 239 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL53. Rnrs-libraries loses (rnrs enums), which no fixture imports

**Guards:** "rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)".
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(rnrs control) (rnrs enums) (rnrs exceptions)
+(rnrs control) (rnrs exceptions)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)
  expected: ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs enums) (rnrs exceptions) (rnrs files) (rnrs hashtables) (rnrs io ports) (rnrs i [cut 228 characters]
  actual:   ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs exceptions) (rnrs files) (rnrs hashtables) (rnrs io ports) (rnrs io simple) (rn [cut 215 characters]
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL54. Rnrs-libraries also lists (rnrs eval), which its own branch shadows

**Guards:** "rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)".
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(define rnrs-libraries
-  '((rnrs) (rnrs base)
+(define rnrs-libraries
+  '((rnrs) (rnrs eval) (rnrs base)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL rnrs-libraries is the (rnrs ...) libraries this Chez has, but (rnrs eval)
  expected: ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs enums) (rnrs exceptions) (rnrs files) (rnrs hashtables) (rnrs io ports) (rnrs i [cut 228 characters]
  actual:   ((rnrs arithmetic bitwise) (rnrs arithmetic fixnums) (rnrs arithmetic flonums) (rnrs base) (rnrs bytevectors) (rnrs conditions) (rnrs control) (rnrs enums) (rnrs eval) (rnrs exceptions) (rnrs files) (rnrs hashtables) (rnrs io po [cut 240 characters]
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

### Code mutants: the `.#` skip (fix 2)

AL45 to AL51 break the program's rule; SC1 to SC4 break the scan in `tests/test-require-threaded.sps`. AL48 is the
one survivor. It removes the `file-symbolic-link?` test and keeps `(not (file-exists? path))`, and
`directory-list` names only entries that exist, so for any entry a fixture can hold the two programs agree: a
listed name for which `file-exists?` is false is a dangling link. They differ in a directory that can be listed but
not searched, where `file-exists?` is false for a regular file too; there the program reads the `.#` file and
names the failure, and AL48 skips it. Git keeps no mode, so no fixture holds that, and none was built at run time.
The test stays for the case. SR4 and SR5 repeat the rule on the real `src/`.

#### AL45. Every .# name is skipped, as before

**Guards:** `lock-regular`, `lock-directory`, `lock-symlink-live`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(and (prefix? name ".#")
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+(prefix? name ".#"))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL lock-regular: a .# regular file is no lock file: it is read and checked
  expected: (1 "" "check-seam: tests/fixtures/seam/lock-regular/curl/.#g.sls: (curl \\x2E;\\x23;g) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
FAIL lock-directory: a .# directory is no lock file: it is walked
  expected: (1 "" "check-seam: tests/fixtures/seam/lock-directory/curl/.#dir/bad.sls: (curl \\x2E;\\x23;dir bad) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems:  [cut 6 characters]
  actual:   (1 "" "check-seam: no libraries: tests/fixtures/seam/lock-directory holds no .sls file, so there is no seam to check\ncheck-seam: FAILED (problems: 1)\n")
FAIL lock-symlink-live: a .# symbolic link that resolves to a library is no lock file: it is read
  expected: (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  3
suite-exit-status: exit 1 (pass 38, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL46. Every .# symbolic link is skipped, one that resolves too

**Guards:** `lock-symlink-live`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(and (prefix? name ".#")
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+(and (prefix? name ".#")
+       (file-symbolic-link? path)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL lock-symlink-live: a .# symbolic link that resolves to a library is no lock file: it is read
  expected: (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL47. No .# name is skipped

**Guards:** `lock-symlink`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(and (prefix? name ".#")
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+#f)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL lock-symlink: a .# dangling symbolic link, which is Emacs's lock file, is skipped
  expected: (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/lock-symlink/curl/.#legal.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/lock-symlink/curl/.#legal.sls: no such file or directory\ncheck-s [cut 29 characters]
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL48. A .# name is skipped when it names nothing, symbolic link or not (no symlink check)

**Guards:** the `file-symbolic-link?` test of `lock-file?`, which only a directory that lists but cannot be searched tells from `(not (file-exists? path))`; no fixture holds one.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(and (prefix? name ".#")
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+(and (prefix? name ".#")
+       (not (file-exists? path))))
```
**Result:** survived, exit 0. Every suite passed:
```
suite exit 0
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: ran 10, passed 10, failed 0, hung 0
make test exit 0
```

#### AL49. The .# prefix is any name starting with a dot

**Guards:** `dangling-dot-link`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(and (prefix? name ".#")
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+(and (prefix? name ".")
+       (file-symbolic-link? path)
+       (not (file-exists? path))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL dangling-dot-link: a dangling symbolic link named with a dot but not .# is no lock file
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: no such file or dire [cut 43 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL50. .# anywhere in a name makes a lock file

**Guards:** `dangling-hash-link`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(and (prefix? name ".#")
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+(and (let loop ((i 0)) (cond ((> (+ i 2) (string-length name)) #f) ((string=? (substring name i (+ i 2)) ".#") #t) (else (loop (+ i 1)))))
+       (file-symbolic-link? path)
+       (not (file-exists? path))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL dangling-hash-link: a dangling symbolic link with .# inside its name, not at its start, is no lock file
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: no such file or directory\nc [cut 35 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### AL51. Every dangling symbolic link is skipped, whatever its name

**Guards:** `dangling-link`, `dangling-dot-link`, `dangling-hash-link`.
**Mutation:**
In `tests/check-seam.sps`:
```diff
-(and (prefix? name ".#")
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+(and (file-symbolic-link? path)
+       (not (file-exists? path))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL dangling-link: a dangling symbolic link not named .# is no lock file: it is named, for it cannot be read
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-link/curl/dangling.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-link/curl/dangling.sls: no such file or directory\nche [cut 33 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
FAIL dangling-dot-link: a dangling symbolic link named with a dot but not .# is no lock file
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-dot-link/curl/.dangling.sls: no such file or dire [cut 43 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
FAIL dangling-hash-link: a dangling symbolic link with .# inside its name, not at its start, is no lock file
  expected: (1 "" "check-seam: tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: it cannot be read as data: Exception in open-file-input-port: failed for tests/fixtures/seam/dangling-hash-link/curl/a.#b.sls: no such file or directory\nc [cut 35 characters]
  actual:   (0 "check-seam: the seam holds (1 libraries in 1 files checked)\n" "")
# of unexpected failures  3
suite-exit-status: exit 1 (pass 38, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### SC1. The scan skips any dotfile by its name, as before

**Guards:** "the scan reads a name ending in .sls, a dotfile included, and no other", "the scan reads a .# regular file, which Chez loads as a library", "the scan reads a .# link that resolves, and a .# directory".
**Mutation:**
In `tests/test-require-threaded.sps`:
```diff
-    (and (> n 4)
-         (string=? (substring name (- n 4) n) ".sls"))))
+    (and (> n 4)
+         (not (char=? (string-ref name 0) #\.))
+         (string=? (substring name (- n 4) n) ".sls"))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL the scan reads a name ending in .sls, a dotfile included, and no other
  expected: (read read skipped skipped skipped skipped)
  actual:   (read skipped skipped skipped skipped skipped)
FAIL the scan reads a .# regular file, which Chez loads as a library
  expected: ("tests/fixtures/seam/lock-regular/curl/.#g.sls" "tests/fixtures/seam/lock-regular/http-client/target.sls")
  actual:   ("tests/fixtures/seam/lock-regular/http-client/target.sls")
FAIL the scan reads a .# link that resolves, and a .# directory
  expected: ("tests/fixtures/seam/lock-symlink-live/curl/.#real.sls" "tests/fixtures/seam/lock-symlink-live/curl/real.sls" "tests/fixtures/seam/lock-directory/curl/.#dir/bad.sls")
  actual:   ("tests/fixtures/seam/lock-symlink-live/curl/real.sls" "tests/fixtures/seam/lock-directory/curl/.#dir/bad.sls")
# of unexpected failures  3
suite-exit-status: exit 1 (pass 46, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### SC2. The scan skips every .# name

**Guards:** "the scan reads a .# regular file, which Chez loads as a library", "the scan reads a .# link that resolves, and a .# directory".
**Mutation:**
In `tests/test-require-threaded.sps`:
```diff
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+       #t))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL the scan reads a .# regular file, which Chez loads as a library
  expected: ("tests/fixtures/seam/lock-regular/curl/.#g.sls" "tests/fixtures/seam/lock-regular/http-client/target.sls")
  actual:   ("tests/fixtures/seam/lock-regular/http-client/target.sls")
FAIL the scan reads a .# link that resolves, and a .# directory
  expected: ("tests/fixtures/seam/lock-symlink-live/curl/.#real.sls" "tests/fixtures/seam/lock-symlink-live/curl/real.sls" "tests/fixtures/seam/lock-directory/curl/.#dir/bad.sls")
  actual:   ("tests/fixtures/seam/lock-symlink-live/curl/real.sls")
# of unexpected failures  2
suite-exit-status: exit 1 (pass 47, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### SC3. The scan skips a .# link that resolves

**Guards:** "the scan reads a .# link that resolves, and a .# directory".
**Mutation:**
In `tests/test-require-threaded.sps`:
```diff
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+       (file-symbolic-link? path)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL the scan reads a .# link that resolves, and a .# directory
  expected: ("tests/fixtures/seam/lock-symlink-live/curl/.#real.sls" "tests/fixtures/seam/lock-symlink-live/curl/real.sls" "tests/fixtures/seam/lock-directory/curl/.#dir/bad.sls")
  actual:   ("tests/fixtures/seam/lock-symlink-live/curl/real.sls" "tests/fixtures/seam/lock-directory/curl/.#dir/bad.sls")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 48, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### SC4. The scan skips no .# name

**Guards:** "the scan skips a .# dangling symbolic link, an Emacs lock file, and reads what it lies beside".
**Mutation:**
In `tests/test-require-threaded.sps`:
```diff
-(and (> (string-length name) 1)
-       (char=? (string-ref name 0) #\.)
-       (char=? (string-ref name 1) #\#)
-       (file-symbolic-link? path)
-       (not (file-exists? path))))
+#f)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL the scan skips a .# dangling symbolic link, an Emacs lock file, and reads what it lies beside
  expected: ("tests/fixtures/seam/lock-symlink/curl/legal.sls")
  actual:   ("tests/fixtures/seam/lock-symlink/curl/.#legal.sls" "tests/fixtures/seam/lock-symlink/curl/legal.sls")
# of unexpected failures  1
suite-exit-status: exit 1 (pass 48, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### SR4. A regular .# file with a violation beside a source under src/

**Guards:** `check-seam`'s own lines.
**Mutation:**
Written, `src/curl/private/.#evil.sls` (1 lines).
**Result:** killed, exit 2; the lines that name it:
```
suite exit 0
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: src/curl/private/.#evil.sls: (curl private \x2E;\x23;evil) imports (http-client target), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
make: *** [Makefile:235: check-seam] Error 1
make test exit 2
```

#### SR5. Control: an Emacs lock file, a dangling .# symbolic link, beside a source under src/ is skipped

**Guards:** `check-seam`'s own lines.
**Mutation:**
Command only: `ln -s 'user@host.4242:1' 'src/curl/private/.#native.sls' && make check-seam && make test TEST_TIMEOUT=30 2>&1 | tail -3`
**Result:** fail, exit 0; the lines that name it:
```
check-seam: the seam holds (9 libraries in 9 files checked)
```

### The real tree and the reviewer's trees

SR1 to SR3 put into a library under `src/` what the allowlists refuse. RV1 and RV2 are the reviewer's two trees,
`exp/seam/src` and `exp/dot/src`, run through the finished program (the stop condition); `STOP-BEFORE` above is the
same two trees through the program as it was.

#### SR1. A library under src/ imports eval from (chezscheme), which the allowlist does not list

**Guards:** `check-seam`'s own lines, "allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-(only (chezscheme) threaded? scheme-version scheme-version-number))
+(only (chezscheme) threaded? scheme-version scheme-version-number eval))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  expected: (define-ftype display-condition eval file-regular? foreign-alloc foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof format format-condition? ftype-ref getenv load-shared-object machine-type make-ftype-point [cut 50 characters]
  actual:   (define-ftype display-condition file-regular? foreign-alloc foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof format format-condition? ftype-ref getenv load-shared-object machine-type make-ftype-pointer sc [cut 45 characters]
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: src/curl/private/require-threaded.sls: (curl private require-threaded) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: FAILED (problems: 1)
make: *** [Makefile:235: check-seam] Error 1
make test exit 2
```

#### SR2. A library under src/ imports (srfi :1)

**Guards:** `check-seam`'s own lines.
**Mutation:**
In `src/curl/private/constants.sls`:
```diff
-(import (curl private require-threaded)
-          (rnrs))
+(import (curl private require-threaded)
+          (rnrs)
+          (srfi :1))
```
**Result:** killed, exit 2; the lines that name it:
```
suite exit 0
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: src/curl/private/constants.sls: (curl private constants) imports (srfi :1), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (http-client ...) [cut 10 characters]
check-seam: FAILED (problems: 1)
make: *** [Makefile:235: check-seam] Error 1
make test exit 2
```

#### SR3. A library under src/ imports (chezscheme) whole

**Guards:** `check-seam`'s own lines.
**Mutation:**
In `src/curl/private/constants.sls`:
```diff
-(import (curl private require-threaded)
-          (rnrs))
+(import (curl private require-threaded)
+          (rnrs)
+          (chezscheme))
```
**Result:** killed, exit 2; the lines that name it:
```
suite exit 0
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: src/curl/private/constants.sls: (curl private constants) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
check-seam: FAILED (problems: 1)
make: *** [Makefile:235: check-seam] Error 1
make test exit 2
```

#### RV1. The reviewer's seam/src tree: import-only, top-level-value, $primitive, ($system), expand

**Guards:** `check-seam`'s own lines.
**Mutation:**
Copied in, `exp/seam-src`, from the reviewer's `seam/src`.
**Result:** killed, exit 1; the lines that name it:
```
exit 1
check-seam: exp/seam-src/curl/a.sls: (curl a) imports import-only from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: exp/seam-src/curl/b.sls: (curl b) imports top-level-value from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: exp/seam-src/curl/c.sls: (curl c) imports ($system), but a library under src/ may import only the (rnrs ...) libraries except (rnrs eval), (only (chezscheme) name ...), and (curl ...) and (http-client ...) libraries
check-seam: exp/seam-src/curl/d.sls: (curl d) imports $primitive from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: exp/seam-src/curl/e.sls: (curl e) imports expand from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
check-seam: FAILED (problems: 5)
```

#### RV2. The reviewer's dot/src tree: a regular .#g.sls that imports (http-client target)

**Guards:** `check-seam`'s own lines.
**Mutation:**
Copied in, `exp/dot-src`, from the reviewer's `dot/src`.
**Result:** killed, exit 1; the lines that name it:
```
exit 1
check-seam: exp/dot-src/curl/.#g.sls: (curl \x2E;\x23;g) imports (http-client target), but no (curl ...) library may import an (http-client ...) library
check-seam: FAILED (problems: 1)
```

### The fixtures (fix 3)

FX1 is a control and must pass: a suite with no exit line and a library that breaks the seam, both under
`tests/fixtures/`, are read by `check-suites`, `check-seam` and `test-require-threaded` never. FX2 and FX3 break the
correspondence between fixture directories and cases.

#### FX1. Control: a bad suite and a bad library under tests/fixtures/ are read by no check, so make test passes

**Guards:** `check-seam`'s own lines.
**Mutation:**
Written, `tests/fixtures/seam/legal/test-fixture.sps` (2 lines).
Written, `tests/fixtures/test-junk.sps` (2 lines).
Written, `tests/fixtures/junk/curl/bad.sls` (1 lines).
**Result:** passed, as a control must, exit 0; the lines that show it:
```
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: ran 10, passed 10, failed 0, hung 0
```

#### FX2. A fixture directory is deleted: its case, and the check that every directory is a case, fail by name

**Guards:** `rule-a`, "every fixture directory is a case above, and every case has its directory".
**Mutation:**
Removed, `tests/fixtures/seam/rule-a`.
**Result:** killed, exit 2; the lines that name it:
```
FAIL rule-a: rule (a): a (curl ...) library importing an (http-client ...) library
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (http-client y), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: no libraries: tests/fixtures/seam/rule-a holds no .sls file, so there is no seam to check\ncheck-seam: FAILED (problems: 1)\n")
FAIL every fixture directory is a case above, and every case has its directory
  expected: ("cannot-read-import" "chez-whole" "chez-wrapped" "dangling-dot-link" "dangling-hash-link" "dangling-link" "dir-symlink" "eof-literal" "legal" "lock-directory" "lock-regular" "lock-symlink" "lock-symlink-live" "name-import-only" [cut 280 characters]
  actual:   ("cannot-read-import" "chez-whole" "chez-wrapped" "dangling-dot-link" "dangling-hash-link" "dangling-link" "dir-symlink" "eof-literal" "legal" "lock-directory" "lock-regular" "lock-symlink" "lock-symlink-live" "name-import-only" [cut 271 characters]
# of unexpected failures  2
suite-exit-status: exit 1 (pass 39, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### FX3. A fixture directory no case runs

**Guards:** "every fixture directory is a case above, and every case has its directory".
**Mutation:**
Written, `tests/fixtures/seam/stray/curl/stray.sls` (1 lines).
**Result:** killed, exit 2; the lines that name it:
```
FAIL every fixture directory is a case above, and every case has its directory
  expected: ("cannot-read-import" "chez-whole" "chez-wrapped" "dangling-dot-link" "dangling-hash-link" "dangling-link" "dir-symlink" "eof-literal" "legal" "lock-directory" "lock-regular" "lock-symlink" "lock-symlink-live" "name-import-only" [cut 280 characters]
  actual:   ("cannot-read-import" "chez-whole" "chez-wrapped" "dangling-dot-link" "dangling-hash-link" "dangling-link" "dir-symlink" "eof-literal" "legal" "lock-directory" "lock-regular" "lock-symlink" "lock-symlink-live" "name-import-only" [cut 288 characters]
# of unexpected failures  1
suite-exit-status: exit 1 (pass 40, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

### Code mutants: temporary directories (fix 4)

TD1 to TD19 break `tests/curl-testing.sls`; OC1 puts the old body back into `tests/libcurl-oracle.sls`. TD15 and TD19
loop in a Chez child when mutated, so their runs were bounded, and a watcher killed the child that stayed. TD17 removes
the refusal of `/`; its row runs a logging `rm` that removes nothing, so the mutant could not touch a real directory.
TD7 was dropped: an empty answer accepted as a path is refused anyway, one test later, for it is not absolute. A
mutant that removes `remove-temp-directory`'s first `(file-exists? dir)` is equivalent (`rm -rf` of nothing succeeds),
and one that drops the second is TD18. These ran against the tree before the last two rows of
`tests/test-check-seam.sps`, which they do not touch.

#### TD1. The path is cut at the first whitespace, as before

**Guards:** "call-with-temp-directory: TMPDIR holding a space is one path; the directory beside it survives", "call-with-temp-directory: a newline in TMPDIR makes two lines, which it refuses; the directory named by the first survives", "call-with-temp-directory refuses a mktemp that answers two lines, the first a directory, and calls nothing, and removes nothing".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-  (define (single-line text)
-    (let ((n (string-length text)))
-      (and (> n 1)
-           (char=? (string-ref text (- n 1)) #\newline)
-           (let ((line (substring text 0 (- n 1))))
-             (and (not (memv #\newline (string->list line))) line)))))
+  (define (single-line text)
+    (let loop ((i 0))
+      (cond ((= i (string-length text)) #f)
+            ((memv (string-ref text i) '(#\space #\tab #\newline))
+             (and (> i 0) (substring text 0 i)))
+            (else (loop (+ i 1))))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL call-with-temp-directory: TMPDIR holding a space is one path; the directory beside it survives
  expected: (inside kept removed)
  actual:   (elsewhere destroyed left)
FAIL call-with-temp-directory: a newline in TMPDIR makes two lines, which it refuses; the directory named by the first survives
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
FAIL call-with-temp-directory refuses a mktemp that answers two lines, the first a directory, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
# of unexpected failures  3
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 10, passed 8, failed 2, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD2. The path is the first line, whatever follows it

**Guards:** "call-with-temp-directory: a newline in TMPDIR makes two lines, which it refuses; the directory named by the first survives", "call-with-temp-directory refuses a mktemp that answers two lines, the first a directory, and calls nothing, and removes nothing".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-  (define (single-line text)
-    (let ((n (string-length text)))
-      (and (> n 1)
-           (char=? (string-ref text (- n 1)) #\newline)
-           (let ((line (substring text 0 (- n 1))))
-             (and (not (memv #\newline (string->list line))) line)))))
+  (define (single-line text)
+    (let loop ((i 0))
+      (cond ((= i (string-length text)) #f)
+            ((char=? (string-ref text i) #\newline) (and (> i 0) (substring text 0 i)))
+            (else (loop (+ i 1))))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL call-with-temp-directory: a newline in TMPDIR makes two lines, which it refuses; the directory named by the first survives
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
FAIL call-with-temp-directory refuses a mktemp that answers two lines, the first a directory, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
# of unexpected failures  2
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 10, passed 8, failed 2, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD3. A missing final newline is accepted

**Guards:** "call-with-temp-directory refuses a mktemp that answers no newline, and calls nothing, and removes nothing".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-  (define (single-line text)
-    (let ((n (string-length text)))
-      (and (> n 1)
-           (char=? (string-ref text (- n 1)) #\newline)
-           (let ((line (substring text 0 (- n 1))))
-             (and (not (memv #\newline (string->list line))) line)))))
+  (define (single-line text)
+    (let* ((n (string-length text))
+           (line (if (and (> n 0) (char=? (string-ref text (- n 1)) #\newline))
+                     (substring text 0 (- n 1))
+                     text)))
+      (and (> (string-length line) 0)
+           (not (memv #\newline (string->list line)))
+           line)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL call-with-temp-directory refuses a mktemp that answers no newline, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
# of unexpected failures  1
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD4. A relative path is accepted

**Guards:** "call-with-temp-directory refuses a mktemp that answers a relative path to a directory that exists, and calls nothing, and removes nothing".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-(if (and (= (car made) 0) dir (absolute-path? dir) (file-directory? dir))
+(if (and (= (car made) 0) dir (file-directory? dir))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL call-with-temp-directory refuses a mktemp that answers a relative path to a directory that exists, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   ((assertion-violation remove-temp-directory ("tests")) kept called)
# of unexpected failures  1
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD5. A path that is not there is accepted

**Guards:** "call-with-temp-directory refuses a mktemp that answers a path that is not there, and calls nothing, and removes nothing".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-(if (and (= (car made) 0) dir (absolute-path? dir) (file-directory? dir))
+(if (and (= (car made) 0) dir (absolute-path? dir))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL call-with-temp-directory refuses a mktemp that answers a path that is not there, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise kept called)
# of unexpected failures  1
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD6. Mktemp's exit status is not looked at

**Guards:** "call-with-temp-directory refuses a mktemp that answers a directory and exit 1, and calls nothing, and removes nothing".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-(if (and (= (car made) 0) dir (absolute-path? dir) (file-directory? dir))
+(if (and dir (absolute-path? dir) (file-directory? dir))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL call-with-temp-directory refuses a mktemp that answers a directory and exit 1, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   (no-raise destroyed called)
# of unexpected failures  1
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD8. The directory is removed after PROC returns, not when it raises or escapes

**Guards:** "call-with-temp-directory: the directory is removed when PROC raises, and the raise goes on", "call-with-temp-directory: the directory is removed when PROC escapes".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-      (dynamic-wind
-        (lambda () #f)
-        (lambda () (proc dir))
-        (lambda () (remove-temp-directory dir)))))
+      (let ((value (proc dir)))
+        (remove-temp-directory dir)
+        value)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL call-with-temp-directory: the directory is removed when PROC raises, and the raise goes on
  expected: (boom removed)
  actual:   (boom left)
FAIL call-with-temp-directory: the directory is removed when PROC escapes
  expected: (escaped removed)
  actual:   (escaped left)
# of unexpected failures  2
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 10, passed 8, failed 2, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD9. The directory is never removed

**Guards:** "call-with-temp-directory: PROC gets the path of an empty directory, and the directory is gone after", "call-with-temp-directory: its answer is PROC's, and what the directory held is removed too", "call-with-temp-directory: the directory is removed when PROC raises, and the raise goes on", "call-with-temp-directory: the directory is removed when PROC escapes".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-        (lambda () (remove-temp-directory dir)))))
+        (lambda () #f))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL call-with-temp-directory: PROC gets the path of an empty directory, and the directory is gone after
  expected: ((#t #t ()) removed)
  actual:   ((#t #t ()) left)
FAIL call-with-temp-directory: its answer is PROC's, and what the directory held is removed too
  expected: (answer ("g" "sub") removed)
  actual:   (answer ("g" "sub") left)
FAIL call-with-temp-directory: the directory is removed when PROC raises, and the raise goes on
  expected: (boom removed)
  actual:   (boom left)
FAIL call-with-temp-directory: the directory is removed when PROC escapes
  expected: (escaped removed)
  actual:   (escaped left)
FAIL call-with-temp-directory: TMPDIR holding a space is one path; the directory beside it survives
  expected: (inside kept removed)
  actual:   (inside kept left)
# of unexpected failures  5
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 10, passed 8, failed 2, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD10. The directory is removed before PROC runs

**Guards:** "call-with-temp-directory: PROC gets the path of an empty directory, and the directory is gone after", "call-with-temp-directory: its answer is PROC's, and what the directory held is removed too".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-      (dynamic-wind
-        (lambda () #f)
-        (lambda () (proc dir))
-        (lambda () (remove-temp-directory dir)))))
+      (dynamic-wind
+        (lambda () (remove-temp-directory dir))
+        (lambda () (proc dir))
+        (lambda () #f))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL call-with-temp-directory: PROC gets the path of an empty directory, and the directory is gone after
  expected: ((#t #t ()) removed)
  actual:   #f
FAIL call-with-temp-directory: its answer is PROC's, and what the directory held is removed too
  expected: (answer ("g" "sub") removed)
  actual:   #f
FAIL call-with-temp-directory: TMPDIR holding a space is one path; the directory beside it survives
  expected: (inside kept removed)
  actual:   #f
FAIL call-with-temp-directory: a newline in TMPDIR makes two lines, which it refuses; the directory named by the first survives
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   #f
FAIL call-with-temp-directory refuses a mktemp that answers a relative path to a directory that exists, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   #f
FAIL call-with-temp-directory refuses a mktemp that answers a path that is not there, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   #f
FAIL call-with-temp-directory refuses a mktemp that answers an empty line, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   #f
FAIL call-with-temp-directory refuses a mktemp that answers no newline, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   #f
FAIL call-with-temp-directory refuses a mktemp that answers two lines, the first a directory, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   #f
FAIL call-with-temp-directory refuses a mktemp that answers a directory and exit 1, and calls nothing, and removes nothing
  expected: ((other-raise "mktemp -d did not answer one absolute path to a directory") kept never-called)
  actual:   #f
FAIL remove-temp-directory: only an absolute path other than /, and it runs no rm for any other
  expected: ((assertion-violation remove-temp-directory ("relative/dir")) (assertion-violation remove-temp-directory ("/")) (assertion-violation remove-temp-directory ("")) never-run)
  actual:   #f
FAIL remove-temp-directory: a directory still there after rm is a raise
  expected: ((other-raise "could not remove the directory") still-there)
  actual:   #f
FAIL make-process-temp-directory: removed by exit, which keeps its status
  expected: (3 under-tmpdir () removed)
  actual:   #f
FAIL make-process-temp-directory: removed by a raise nothing guards, status 255
[27 more lines]
```

#### TD11. Exit does not remove the process directory

**Guards:** "make-process-temp-directory: removed by exit, which keeps its status", "make-process-temp-directory: a raise a guard catches does not remove it", "make-process-temp-directory: a warning, which goes on, does not remove it".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-      (exit-handler
-       (let ((previous (exit-handler)))
-         (lambda args
-           (remove-quietly dir)
-           (apply previous args))))
+
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL make-process-temp-directory: removed by exit, which keeps its status
  expected: (3 under-tmpdir () removed)
  actual:   (3 under-tmpdir () left)
FAIL make-process-temp-directory: a raise a guard catches does not remove it
  expected: (0 under-tmpdir ("kept") removed)
  actual:   (0 under-tmpdir ("kept") left)
FAIL make-process-temp-directory: a warning, which goes on, does not remove it
  expected: (0 under-tmpdir ("kept") removed)
  actual:   (0 under-tmpdir ("kept") left)
# of unexpected failures  3
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD12. A raise nothing guards does not remove the process directory

**Guards:** "make-process-temp-directory: removed by a raise nothing guards, status 255", "make-process-temp-directory: removed by a raise of a non-condition too".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-      (base-exception-handler
-       (let ((previous (base-exception-handler)))
-         (lambda (condition)
-           (unless (warning? condition)
-             (remove-quietly dir))
-           (previous condition))))
+
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL make-process-temp-directory: removed by a raise nothing guards, status 255
  expected: (255 under-tmpdir () removed)
  actual:   (255 under-tmpdir () left)
FAIL make-process-temp-directory: removed by a raise of a non-condition too
  expected: (255 under-tmpdir () removed)
  actual:   (255 under-tmpdir () left)
# of unexpected failures  2
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD13. A warning removes the process directory

**Guards:** "make-process-temp-directory: a warning, which goes on, does not remove it".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-           (unless (warning? condition)
-             (remove-quietly dir))
+           (remove-quietly dir)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL make-process-temp-directory: a warning, which goes on, does not remove it
  expected: (0 under-tmpdir ("kept") removed)
  actual:   (0 under-tmpdir ("gone") removed)
# of unexpected failures  1
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD14. The exit handler does not go on to the previous one

**Guards:** "make-process-temp-directory: removed by exit, which keeps its status".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-           (remove-quietly dir)
-           (apply previous args))))
+           (remove-quietly dir))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL make-process-temp-directory: removed by exit, which keeps its status
  expected: (3 under-tmpdir () removed)
  actual:   (255 under-tmpdir () removed)
FAIL make-process-temp-directory: a removal that fails in the exit hook neither raises nor changes the status
  expected: (3 under-tmpdir () left)
  actual:   (255 under-tmpdir () left)
FAIL make-process-temp-directory: a raise a guard catches does not remove it
  expected: (0 under-tmpdir ("kept") removed)
  actual:   (255 under-tmpdir ("kept") removed)
FAIL make-process-temp-directory: a warning, which goes on, does not remove it
  expected: (0 under-tmpdir ("kept") removed)
  actual:   (255 under-tmpdir ("kept") removed)
# of unexpected failures  4
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 255)
test: ran 10, passed 8, failed 2, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD15. The exception handler does not go on to the previous one

**Guards:** "make-process-temp-directory: removed by a raise nothing guards, status 255", "make-process-temp-directory: removed by a raise of a non-condition too".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-             (remove-quietly dir))
-           (previous condition))))
+             (remove-quietly dir)))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL make-process-temp-directory: removed by a raise nothing guards, status 255
  expected: (255 under-tmpdir () removed)
  actual:   (137 under-tmpdir () removed)
FAIL make-process-temp-directory: removed by a raise of a non-condition too
  expected: (255 under-tmpdir () removed)
  actual:   (143 under-tmpdir () removed)
FAIL make-process-temp-directory: a removal that fails in the exception hook neither loops nor changes the status
  expected: (255 under-tmpdir () left)
  actual:   (143 under-tmpdir () left)
# of unexpected failures  3
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: HUNG tests/test-curl-testing.sps (no exit within 30s)
test: ran 10, passed 9, failed 0, hung 1
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD16. A path that is not absolute is removed

**Guards:** "remove-temp-directory: only an absolute path other than /, and it runs no rm for any other".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-    (unless (absolute-path? dir)
-      (assertion-violation 'remove-temp-directory "not an absolute path" dir))
+
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL remove-temp-directory: only an absolute path other than /, and it runs no rm for any other
  expected: ((assertion-violation remove-temp-directory ("relative/dir")) (assertion-violation remove-temp-directory ("/")) (assertion-violation remove-temp-directory ("")) never-run)
  actual:   (no-raise (assertion-violation remove-temp-directory ("/")) no-raise never-run)
# of unexpected failures  1
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD17. The root directory is removed (rm is a logging fake in its test)

**Guards:** "remove-temp-directory: only an absolute path other than /, and it runs no rm for any other".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-    (when (string=? dir "/")
-      (assertion-violation 'remove-temp-directory "not the root directory" dir))
+
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL remove-temp-directory: only an absolute path other than /, and it runs no rm for any other
  expected: ((assertion-violation remove-temp-directory ("relative/dir")) (assertion-violation remove-temp-directory ("/")) (assertion-violation remove-temp-directory ("")) never-run)
  actual:   ((assertion-violation remove-temp-directory ("relative/dir")) (other-raise "could not remove the directory") (assertion-violation remove-temp-directory ("")) run)
# of unexpected failures  1
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD18. A directory that is still there after rm is no raise

**Guards:** "remove-temp-directory: a directory still there after rm is a raise".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-      (when (file-exists? dir)
-        (error 'remove-temp-directory "could not remove the directory" dir))))
+      #f))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL remove-temp-directory: a directory still there after rm is a raise
  expected: ((other-raise "could not remove the directory") still-there)
  actual:   (no-raise still-there)
# of unexpected failures  1
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### TD19. A removal that fails in a hook raises from the hook (no remove-quietly)

**Guards:** "make-process-temp-directory: a removal that fails in the exit hook neither raises nor changes the status", "make-process-temp-directory: a removal that fails in the exception hook neither loops nor changes the status".
**Mutation:**
In `tests/curl-testing.sls`:
```diff
-  (define (remove-quietly dir)
-    (guard (e (#t #f)) (remove-temp-directory dir)))
+  (define (remove-quietly dir)
+    (remove-temp-directory dir))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL make-process-temp-directory: a removal that fails in the exit hook neither raises nor changes the status
  expected: (3 under-tmpdir () left)
  actual:   (143 under-tmpdir () left)
FAIL make-process-temp-directory: a removal that fails in the exception hook neither loops nor changes the status
  expected: (255 under-tmpdir () left)
  actual:   (143 under-tmpdir () left)
# of unexpected failures  2
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: HUNG tests/test-curl-testing.sps (no exit within 30s)
test: ran 10, passed 9, failed 0, hung 1
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### OC1. The oracle makes its directory as before: mktemp's first word, a removal a raise skips

**Guards:** "the oracle, with TMPDIR holding a space: the same report, the directory beside it kept, its own removed", "the oracle, with a newline in TMPDIR: no oracle, and the directory named by the first line kept", "the oracle, when a raise comes inside its directory: it answers no-oracle, and has removed the directory".
**Mutation:**
In `tests/libcurl-oracle.sls`:
```diff
-  (define (libcurl-oracle getenv path)
-    (guard (e (#t (list 'no-oracle 'raised (describe e))))
-      (call-with-temp-directory
-       (lambda (dir)
-         (run-oracle getenv (string-append dir "/libcurl-oracle") path)))))
+  (define (libcurl-oracle getenv path)
+    (guard (e (#t (list 'no-oracle 'raised (describe e))))
+      (let ((made (capture-command '("mktemp" "-d"))))
+        (if (not (and (= (car made) 0) (pair? (split-words (cadr made)))))
+            (list 'no-oracle 'mktemp made)
+            (let* ((dir (car (split-words (cadr made))))
+                   (program (string-append dir "/libcurl-oracle"))
+                   (answer (run-oracle getenv program path)))
+              (capture-command (list "rm" "-rf" dir))
+              answer)))))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL the oracle, with TMPDIR holding a space: the same report, the directory beside it kept, its own removed
  expected: (same kept removed)
  actual:   (same destroyed left)
FAIL the oracle, with a newline in TMPDIR: no oracle, and the directory named by the first line kept
  expected: (no-oracle kept)
  actual:   ((version . "8.20.0") destroyed)
FAIL the oracle, when a raise comes inside its directory: it answers no-oracle, and has removed the directory
  expected: (no-oracle raised 1 ())
  actual:   (no-oracle raised 1 ("tmp.IVMIqZmmoo"))
# of unexpected failures  3
suite-exit-status: exit 1 (pass 48, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

### Code mutants: the Chez floor (fix 5)

FL1 and FL2 are the red run for the final rows: the refusal without any pre-release handling. FL3 refuses a
pre-release of a later version too. FL4 and FL8 compare versions wrongly: as text (10.10.0 sorts before 10.4.0), and
leaving out the major version.

#### FL1. The floor never asks whether this Chez is a pre-release

**Guards:** "where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0", "the refusal asks (scheme-version #t), which says whether this Chez is a pre-release".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-(pre (and (equal? have minimum)
-                         (pre-release-suffix (scheme-version #t)))))
+(pre #f))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL the refusal asks (scheme-version #t), which says whether this Chez is a pre-release
  expected: asks
  actual:   never-asks
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.7")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.12")
  actual:   loaded
# of unexpected failures  4
suite-exit-status: exit 1 (pass 45, fail 4, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### FL2. A pre-release at the floor is computed and ignored

**Guards:** "where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-((or (older? have minimum) pre)
+((older? have minimum)
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.7")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.12")
  actual:   loaded
# of unexpected failures  3
suite-exit-status: exit 1 (pass 46, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### FL3. A pre-release of any version is refused, not only of the floor

**Guards:** "where Chez is Chez Scheme Version 10.4.1-pre-release.1, the refusal lets its library load", "where Chez is Chez Scheme Version 10.5.0-pre-release.1, the refusal lets its library load", "where Chez is Chez Scheme Version 11.0.0-pre-release.3, the refusal lets its library load".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-(pre (and (equal? have minimum)
+(pre (and #t
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL where Chez is Chez Scheme Version 10.3.0-pre-release.2, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0-pre-release.2")
FAIL where Chez is Chez Scheme Version 10.4.1-pre-release.1, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.1-pre-release.1")
FAIL where Chez is Chez Scheme Version 10.5.0-pre-release.1, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.5.0-pre-release.1")
FAIL where Chez is Chez Scheme Version 11.0.0-pre-release.3, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 11.0.0-pre-release.3")
# of unexpected failures  4
suite-exit-status: exit 1 (pass 45, fail 4, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### FL4. Versions are compared as text

**Guards:** "where Chez is Chez Scheme Version 10.10.0, the refusal lets its library load".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-      (define (older? have want)
-        (cond ((null? want) #f)
-              ((< (car have) (car want)) #t)
-              ((> (car have) (car want)) #f)
-              (else (older? (cdr have) (cdr want)))))
+      (define (older? have want)
+        (string<? (dotted have) (dotted want)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL where Chez is Chez Scheme Version 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.10.0, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.10.0")
# of unexpected failures  2
suite-exit-status: exit 1 (pass 47, fail 2, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### FL5. The suffix drops its tag

**Guards:** "where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-(substring text i (string-length text))
+(substring text (+ i (string-length tag)) (string-length text))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.01")
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.7")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.07")
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.12")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.012")
# of unexpected failures  3
suite-exit-status: exit 1 (pass 46, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### FL6. Every Chez at the floor is a pre-release

**Guards:** "where Chez is Chez Scheme Version 10.4.0, the refusal lets its library load", "the refusal asks (scheme-version #t), which says whether this Chez is a pre-release".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-(pre-release-suffix (scheme-version #t))
+"-pre-release.0"
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.0 (require-supported-chez)"
FAIL the refusal asks (scheme-version #t), which says whether this Chez is a pre-release
  expected: asks
  actual:   never-asks
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.0")
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.7")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.0")
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.12")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.0")
FAIL where Chez is Chez Scheme Version 10.4.0, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.0")
# of unexpected failures  6
suite-exit-status: exit 1 (pass 43, fail 6, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-conditions.sps (exit 255)
test: FAIL tests/test-discovery.sps (exit 255)
test: FAIL tests/test-library-loading.sps (exit 255)
test: FAIL tests/test-load-state.sps (exit 255)
test: FAIL tests/test-native.sps (exit 255)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: FAIL tests/test-verify.sps (exit 255)
test: ran 10, passed 3, failed 7, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### FL7. (scheme-version) is asked without #t, which leaves out the pre-release

**Guards:** "where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0", "the refusal asks (scheme-version #t), which says whether this Chez is a pre-release".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-(pre-release-suffix (scheme-version #t))
+(pre-release-suffix (scheme-version))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL the refusal asks (scheme-version #t), which says whether this Chez is a pre-release
  expected: asks
  actual:   never-asks
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.7")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.12")
  actual:   loaded
# of unexpected failures  4
suite-exit-status: exit 1 (pass 45, fail 4, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### FL8. The major version is not compared

**Guards:** "where Chez is Chez Scheme Version 9.5.9, the refusal raises its message naming 10.4.0".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-              ((< (car have) (car want)) #t)
+
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL where Chez is Chez Scheme Version 10.3.0, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 9.5.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.3.9, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.9")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.3.0-pre-release.2, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   loaded
# of unexpected failures  4
suite-exit-status: exit 1 (pass 45, fail 4, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

#### FL9. The message leaves out a pre-release

**Guards:** "where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0", "where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0".
**Mutation:**
In `src/curl/private/require-threaded.sls`:
```diff
-" or later, and this one is " (dotted have) (or pre ""))
+" or later, and this one is " (dotted have))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0")
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.7")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0")
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming 10.4.0
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.12")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0")
# of unexpected failures  3
suite-exit-status: exit 1 (pass 46, fail 3, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-require-threaded.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

### Code mutants: the record (fix 6)

#### OP1. The report is no longer opaque

**Guards:** "the report is opaque: record-rtd on a genuine one raises an assertion violation".
**Mutation:**
In `src/curl/private/libcurl-info.sls`:
```diff
-    (sealed #t)
-    (opaque #t)))
+    (sealed #t)))
```
**Result:** killed, exit 2; the lines that name it:
```
FAIL the report is opaque: record-rtd on a genuine one raises an assertion violation
  expected: (assertion-violation record-rtd)
  actual:   (no-raise libcurl-info)
# of unexpected failures  1
suite-exit-status: exit 1 (pass 8, fail 1, xpass 0): a suite needs a pass, and no fail or xpass
suite exit 1
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
test: FAIL tests/test-native.sps (exit 1)
test: ran 10, passed 9, failed 1, hung 0
make: *** [Makefile:191: test] Error 1
make test exit 2
```

### Which mutants failed each `check-seam` case

Every case of `tests/test-check-seam.sps` failed by name under at least one mutant above.

| case | failed under |
| --- | --- |
| `legal` | AL3 AL4 AL10 AL11 AL12 AL13 AL14 AL15 AL19 AL20 AL23 AL42 |
| `rule-a` | FX2 AL20 AL24 AL44 |
| `rule-b` | AL20 AL25 AL26 AL44 |
| `second-library` | AL20 AL24 AL32 AL44 |
| `neither-family` | AL20 AL27 AL44 |
| `chez-whole` | AL9 AL20 AL44 |
| `scheme-alias` | AL8 AL9 AL20 AL44 |
| `chez-wrapped` | AL8 AL9 AL10 AL11 AL12 AL13 AL14 AL15 AL20 AL44 |
| `name-import-only` | AL1 AL4 AL5 AL7 AL14 AL20 AL43 AL44 |
| `name-top-level-value` | AL4 AL5 AL7 AL14 AL20 AL43 AL44 |
| `name-primitive` | AL4 AL5 AL7 AL14 AL20 AL43 AL44 |
| `names-several` | AL2 AL3 AL4 AL5 AL6 AL7 AL14 AL20 AL43 AL44 |
| `names-denylisted` | AL2 AL4 AL5 AL6 AL7 AL14 AL20 AL43 AL44 |
| `names-not-symbols` | AL14 AL20 AL34 AL44 |
| `rnrs-eval` | AL11 AL14 AL16 AL17 AL20 AL44 |
| `unlisted-libraries` | AL14 AL18 AL20 AL21 AL22 AL44 AL52 |
| `unread-ss` | AL20 AL35 AL44 |
| `unread-so` | AL20 AL36 AL44 |
| `unread-extensions` | AL20 AL35 AL36 AL37 AL43 AL44 |
| `dir-symlink` | AL20 AL38 AL44 |
| `lock-symlink` | AL20 AL47 |
| `lock-regular` | AL20 AL24 AL43 AL44 AL45 |
| `lock-directory` | AL20 AL24 AL44 AL45 |
| `lock-symlink-live` | AL20 AL45 AL46 |
| `dangling-link` | AL20 AL31 AL43 AL44 AL51 |
| `dangling-dot-link` | AL20 AL31 AL43 AL44 AL49 AL51 |
| `dangling-hash-link` | AL20 AL31 AL43 AL44 AL50 AL51 |
| `no-datum` | AL29 AL44 |
| `not-a-library` | AL20 AL28 AL32 AL44 |
| `unreadable` | AL20 AL31 AL43 AL44 |
| `eof-literal` | AL30 AL31 AL44 |
| `cannot-read-import` | AL14 AL20 AL34 AL44 |

### Clean rerun

After the last change to the program, the suites, the refusal, the record and the Makefile, in the finished tree,
`scripts/guix-env sh -c 'make test && make check-test-fails && make build'` (exit 0), and `make check-guix` on
the host (exit 0). The check lines, the rows of each suite this part changed, and the tails:
```
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
check-suites: every suite ends with (exit (suite-exit-status runner)) (10 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
=== tests/test-check-seam.sps
# of expected passes      41
test: pass tests/test-check-seam.sps
=== tests/test-conditions.sps
# of expected passes      11
test: pass tests/test-conditions.sps
=== tests/test-curl-testing.sps
# of expected passes      49
test: pass tests/test-curl-testing.sps
=== tests/test-discovery.sps
# of expected passes      41
test: pass tests/test-discovery.sps
=== tests/test-library-loading.sps
# of expected passes      51
test: pass tests/test-library-loading.sps
=== tests/test-load-state.sps
# of expected passes      12
test: pass tests/test-load-state.sps
=== tests/test-manifest.sps
# of expected passes      4
test: pass tests/test-manifest.sps
=== tests/test-native.sps
# of expected passes      9
test: pass tests/test-native.sps
=== tests/test-require-threaded.sps
# of expected passes      49
test: pass tests/test-require-threaded.sps
=== tests/test-verify.sps
# of expected passes      18
test: pass tests/test-verify.sps
test: ran 10, passed 10, failed 0, hung 0
check-test-fails: ok fails: a failing suite is named FAIL, and the suites after it run
check-test-fails: ok no-tests: a suite that runs no test is named FAIL, and the suites after it run
check-test-fails: ok hangs: a suite that never ends is named HUNG, and the suites after it run
check-test-fails: ok exit-line: check-suites names a suite without the shared exit form, and no suite runs
check-test-fails: ok early-exit: check-suites names a suite that exits before its verdict, and no suite runs
check-test-fails: ok nested-exit: check-suites names an exit inside a form before the verdict, and no suite runs
check-test-fails: ok empty: check-suites names a suite with no datum, and no suite runs
check-test-fails: ok seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs
check-test-fails: ok no-suites: make test refuses to pass with no suite to run
check-test-fails: make test failed, as it must, in all 9 cases
chez-curl: libcurl loaded and accepted
  path:     /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/lib/libcurl.so.4 (override)
  version:  8.20.0
  TLS:      GnuTLS/3.8.13
  features: ipv6 ssl libz asynchdns spnego largefile idn tlsauth-srp http2 gssapi kerberos5 unix-sockets psl https-proxy altsvc zstd hsts threadsafe
  host:     x86_64-unknown-linux-gnu
final exit 0
```

`make check-guix`, on the host, after the last change (its own `make test` ran the ten suites again):
```
check-guix: ok isolated-home (/home/kishu holds only the path to /home/kishu/src/chez-curl)
check-guix: ok tool-path[-lc] (scheme: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/scheme)
check-guix: ok tool-path[-lc] (curl: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/curl)
check-guix: ok tool-path[-lc] (node: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/node)
check-guix: ok tool-path[-lc] (openssl: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/openssl)
check-guix: ok tool-path[-lc] (gcc: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/gcc)
check-guix: ok tool-path[-lc] (valgrind: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/valgrind)
check-guix: ok tool-path[-lc] (make: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/make)
check-guix: ok tool-path[-lic] (scheme: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/scheme)
check-guix: ok tool-path[-lic] (curl: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/curl)
check-guix: ok tool-path[-lic] (node: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/node)
check-guix: ok tool-path[-lic] (openssl: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/openssl)
check-guix: ok tool-path[-lic] (gcc: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/gcc)
check-guix: ok tool-path[-lic] (valgrind: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/valgrind)
check-guix: ok tool-path[-lic] (make: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/make)
check-guix: ok chez-variable (/gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/scheme)
check-guix: ok chez-is-elf
check-guix: ok valgrind-instruments-chez
check-guix: ok cc-variable (/gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/gcc)
check-guix: ok curl-headers (8.20.0)
check-guix: ok libcurl-override (/gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/lib/libcurl.so.4 -> /gnu/store/67lpb53npkkjp5mab0arpnrq2i3xxdbg-curl-8.20.0/lib/libcurl.so.4.8.0)
check-guix: ok no-bare-name-load (libcurl.so.4 refused)
check-guix: ok loopback-only (loopback accepted; 192.0.2.1 ENETUNREACH)
check-guix: ok no-git
check-guix: ALL CHECKS PASSED
exit 0
```

### Findings

- **`(scheme-pre-release)` is not used,** though it exists in 10.4.0 and answers `#f`. Importing it makes
  `(curl private require-threaded)` fail with Chez's bare `missing import` on any Chez that lacks the name (shown
  with `scheme-build-number` on 10.4.0), and the library exists to replace that error with a readable one. `(scheme-version #t)` is a name every Chez has, and the
  refusal asks it only when `(scheme-version-number)` answers the floor exactly, where the Chez takes the argument.
  A pre-release below the floor is named without its suffix (`this one is 10.3.0`): the version alone refuses it.
- **Two refinements go past the brief.** The `.#` skip is for a dangling symbolic link only, not for any symbolic link:
  a `.#g.sls` that links to a library resolves, Chez follows it, and the check reads it (`lock-symlink-live`).
  And `mktemp`'s answer is refused when it has more than one line, not cut at its first: a `TMPDIR` holding a newline
  makes the first line a real directory, which a removal would destroy (`TD2`, the newline row).
- **`10.2.0` ran the refusal.** The store's Chez 10.2.0 loaded `(curl private require-threaded)` by hand and was
  refused by name. Part 5 had no Chez below the floor.
- **The seam check found its own change.** Adding `scheme-version` to `src/` made `make check-seam` fail on the real
  tree until the allowlist listed it: the first use of the review gate the allowlist is.
- **AL33 is named HUNG, not FAIL.** With the depth limit gone, the cyclic import `#0=(only #0# x)` never ends, and
  the suite has no clock of its own: `make test` kills it at `TEST_TIMEOUT` and names it `HUNG`. The direct run is
  bounded by `timeout 40`. No by-name `FAIL` is possible short of a timeout inside the suite.
- **AL43 first looked like a survivor.** Its expected rows were wrong, not the suite: `chez-wrapped` and
  `unlisted-libraries` have one problem per file, so counting files gives the same count. The cases that tell the
  two apart are `names-several`, `names-denylisted` and `unread-extensions`.
- **The first `check-seam` run left four survivors out of the 49 written: AL23 refused,** AL43 mis-specified, AL48 and
  AL49 alive. AL49 (any dot-name skipped) had no case: no fixture held a dangling link named with a dot but not `.#`.
  The `dangling-link`, `dangling-dot-link` and `dangling-hash-link` fixtures were added, and AL49 to AL51 die. This is
  the part 5 lesson again (SM58, K2): a skip rule needs a neighbour that must not be skipped.
- **A hook that raises loops.** TD15 (the base handler does not chain) and TD19 (a failing removal raises inside the
  hook) spin forever in the child; the guard in `remove-quietly` and the chaining are what stop it, and rows hold both.
- **Fixture symbols are written by Chez.** `\x2E;\x23;g`, not the shape one types. The test now holds what Chez
  prints at the pin.
- **`check-test-fails.sh` and the shell scripts needed no change.** `tests/check-test-fails.sh`,
  `tests/guix-env-launcher.sh` and `scripts/guix-env-selftest` all run `tmp=$(mktemp -d)` with `"$tmp"` quoted and
  an `EXIT` trap, so a space in `TMPDIR` costs them nothing. The script's two stub libraries pass every new rule.

### Not covered

- **A Chez older than 10.2.0.** None here. Whether a 9.x Chez has `scheme-pre-release` is unmeasured; the refusal does
  not import it, which makes the answer moot.
- **A directory that lists but cannot be searched** (AL48 above).
- **`visit`, `revisit`, `load-compiled-from-port` and `system`** as ways to load code are closed now only because
  `(chezscheme)` names must be listed, and none is. `system` is not on `allowed-chez-names`.
- **Case.** Endings are matched as written. On a case-insensitive file system, macOS's default, `x.SLS` might be found
  by Chez for `(curl x)` and not named. Not run: Linux only.
- **macOS.** The suites were not run there. `mktemp -d` without a template, `chmod +x`, `env VAR=...` and `printf` in
  `/bin/sh` are what the new rows use.
- **Two calls.** `make-process-temp-directory` wraps the exit handler and the base exception handler on each call, so
  two calls stack two wrappers. A suite calls it once. The wrapper is Chez's own parameter, not portable Scheme.
- **Every run was Linux, amd64, in the container,** but for the stored Chez versions, run on the host.
