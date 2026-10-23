# Foundations mutation log (M2 slice 1)

- **Date:** 2026-10-22, branch `m2/foundations`, on top of `afd7951`.
- **Plan:** [M2 plan](2026-10-19-m2-plan.md) §3 and §4. **Records:** ADR-0001, ADR-0007,
  ADR-0008, ADR-0013, ADR-0014; the amendments this slice needs are the lead's to write.
- **Scratch:** every path under `build/verify/` named here is scratch, and is not kept. This log
  holds what each file showed. The parts were:
  - `build/verify/m2s1/scratch/`: the measurement programs and their outputs;
  - `build/verify/m2s1/mut/`: the mutation harness, `run.py`, its table generator, `table.py`,
    `results.jsonl`, and each case's logs;
  - `build/verify/m2s1/ci/`: the CI stand-in: Chez, the floor curl and Node, built once, and
    `lane.sh`, which runs a lane on a copy of the tree.

## Part 1: measured

### 1.1 Chez's `u8*` hands C a bytevector's first byte, with no offset

`scratch/u8-offset.sps`, in the container (Chez 10.4.0): `memcpy` bound `(u8* uptr size_t)`,
copying 3 bytes from a foreign block into a 6-byte bytevector of `#xEE`, then given four other
shapes that could name an offset. The first run, `$CHEZ --script build/verify/m2s1/scratch/u8-offset.sps`,
printed (the block's address changes per run):

```
copied 3 bytes into a 6-byte bytevector: #vu8(1 2 3 238 238 238)
u8* given (#vu8(1 2 3 238 238 238) . 2): Exception in memcpy: invalid foreign-procedure argument (#vu8(1 2 3 238 238 238) . 2)
u8* given (#vu8(1 2 3 238 238 238) 2): Exception in memcpy: invalid foreign-procedure argument (#vu8(1 2 3 238 238 238) 2)
u8* given 1006216256: Exception in memcpy: invalid foreign-procedure argument 1006216256
u8* given #(#vu8(1 2 3 238 238 238) 2): Exception in memcpy: invalid foreign-procedure argument #(#vu8(1 2 3 238 238 238) 2)
```

Rerun on 2026-10-23 both ways (`fix1/u8-offset-rerun.txt`). `--script` printed the same lines.
`$CHEZ --program build/verify/m2s1/scratch/u8-offset.sps` printed, after the same first line:

```
u8* given (#vu8(1 2 3 238 238 238) . 2): Exception in $oops: invalid who argument memcpy (message = "invalid foreign-procedure argument ~s", irritants = ((#vu8(1 2 3 238 238 238) . 2)))
u8* given (#vu8(1 2 3 238 238 238) 2): Exception in $oops: invalid who argument memcpy (message = "invalid foreign-procedure argument ~s", irritants = ((#vu8(1 2 3 238 238 238) 2)))
u8* given 694637632: Exception in $oops: invalid who argument memcpy (message = "invalid foreign-procedure argument ~s", irritants = (694637632))
u8* given #(#vu8(1 2 3 238 238 238) 2): Exception in $oops: invalid who argument memcpy (message = "invalid foreign-procedure argument ~s", irritants = (#(#vu8(1 2 3 238 238 238) 2)))
```

Compiled, a foreign procedure's own argument check raises with the entry's name, a string, as
its who, and `$oops` refuses that who. Either way, every shape but the bytevector is refused,
and the bytevector is copied into from its first byte. The checked copies refuse a bad argument
themselves, before any foreign procedure sees it.

chez-curl compiles no C, so no shim adds the offset as chez-libuv's does. So each checked copy
calls `memcpy` on the caller's bytevector itself when OFFSET is 0, and otherwise through a fresh
N-byte bytevector and `bytevector-copy!`. The bound is asserted before either. The lead agreed
(2026-10-22), and asked for the bounce's two mutations, `cpy-bounce-from-0-*` and
`cpy-bounce-n1-*` below.

### 1.2 Binding order: libc's `memcpy` and `strlen` before the floor check

Step 3 reads `curl_version_info_data`'s three strings, and the below-floor and no-ssl refusals
carry them. With `c-string` gone (plan §4.3), they are read with `c-string->bytevector`, so
`memcpy` (both ways) and `strlen` are bound right after `curl_version_info` and its NULL check,
before step 4. The lead chose this (option A, 2026-10-22) over a second, byte-at-a-time reader.
They are bound through `bind-required`, with no report (`#f`), since none exists yet.

`test-library-loading` was rerun with it: 59 passes, up from 53, the six new `lacks-` decoys
for the URL API. Every decoy refusal still carries its reason, detail and report: `below-floor`
and `no-ssl` name the version, and a library with no `curl_*` function is still `missing-api`,
naming `curl_version_info`.

### 1.3 `curl_url_get`'s declaration differs by version

The headers read, each where it was read (corrected in fix round 2, Part 7):

| Header | Where | `curl_url_get`'s handle |
|---|---|---|
| 7.85.0, the floor, `ci/curl-floor/include/curl/urlapi.h`, built by `build-curl.sh` | Docker `ubuntu:24.04` (`fix2/read-headers.txt`) | `CURLU *handle` |
| 8.5.0, Ubuntu's `libcurl4-openssl-dev` 8.5.0-2ubuntu10.16, `/usr/include/x86_64-linux-gnu/curl/urlapi.h` | Docker `ubuntu:24.04` (`fix2/read-headers.txt`) | `const CURLU *handle` |
| 8.20.0, the container's profile, `include/curl/urlapi.h` | the container (`fix2/url-euro-guix.txt`) | `const CURLU *u` |

The first round's draft named 8.6.0's, from a Guix store path on the host, which no lane reads;
the table above replaces it. For every other bound entry, one spelling serves all three: the
spelling check (Part 6), which reads each row's declaration from the headers a run compiles
against, matched on the floor lane (7.85.0), the main lane (8.5.0) and in the container
(8.20.0). C finds the two function types incompatible, so:
- `prototype-rows` lets a row give more than one declaration, and `curl_url_get`'s gives both. The
  C side's `_Generic` lists each; the Scheme side holds a binding to any one.
- `tests/decoy-libcurl.c` defines `curl_url_get` with the header's declaration renamed away, since
  a definition that disagrees with the header in scope does not compile.

### 1.4 Chez's `string` for a `const char *`

The plan's map (§4.5) gives a pointer `uptr`, `void*` or `(* FTYPE)`. `curl_easy_option_by_name`
and `curl_easy_header` bind their name `string`, under their `string-not-kept` marks. So
`c-type-map` also lets a `const char *`, and no other pointer, be `string`.

### 1.5 A `(curl-testing)` child needs `src/` on its library path

`curl-testing` now imports `(curl private counters)`, from `src/`. `test-origin.sps` line 900
spawned `origin-child.sps`, which imports `(curl-testing)`, with `--libdirs tests:build/scheme-libs`.
Measured in the container, the child died with `library (curl private counters) not found`, and
`test-origin` failed two tests by name:

```
FAIL a suite killed with SIGKILL while idle: within 5 s every face of its origin refuses connections
  actual:   (raised "Exception in sigkill: the child Chez printed no line")
FAIL a suite killed with SIGKILL during a probe: ...
  actual:   (raised "Exception in sigkill: the child Chez printed no line")
```

The lead changed that line to `--libdirs src:tests:build/scheme-libs` (test-origin.sps is the
lead's), and both pass. `test-curl-testing.sps`'s two child spawns got the same change. No other
program spawns a `(curl-testing)` child without `src/`.

### 1.6 Smaller facts

- **`thread-join` answers nothing** (`#<void>`) in Chez 10.4.0, so the counters' thread test
  records each thread's outcome in its own vector slot.
- **The counters' mutex is visible.** With each `with-mutex` a `begin`, 8 threads counting up
  20000 times each left 55689 and 68398 of 160000 in two runs, and counting down raised
  "a double free" in some threads.
- **A dropped bound corrupts silently.** `cpy-bound-f2b` wrote 7 bytes into a 6-byte bytevector,
  and the suite ran on to its end. Only the test's own expected refusal named it.
- **The load reads through the copies,** so a mutant that breaks them breaks the load.
  `test-memory-safety` reaches `(curl private native)` through `eval` under a guard, so such a
  mutant fails `(curl private native) loads, reached through eval` and each test that uses a copy,
  by name, rather than killing the suite at import.

## Part 2: what was built, in the container (Chez 10.4.0, libcurl 8.20.0, GnuTLS)

- `make test` runs 20 suites, all passing. At `afd7951` it ran 18 in 66 s.
- `make test-memory` runs all 20 in 4 min 32 s; the four new or changed suites alone took 38 s.
- The counters' thread test, 8 threads of 20000 steps each way, passes under Valgrind too, which
  runs one thread at a time.

## Part 3: mutations

Each case ran in a copy of the tree, `mut/<case>/tree`, made with `cp` of everything but
`.git` and `build/`, then the stated exact replacements, each required to match the stated number
of times. The `baseline` case is the copy unchanged. "Run" is what ran in that copy, in the
container. "First failing test" is the first SRFI-64 FAIL line in the failing runs, its number of
other FAIL lines in brackets; a check line where no suite ran. Names over 110 characters are cut.

The `ctr-*`, `blk-*`, `cpy-*`, `str-*`, `rule-cstr-reentry`, `rule-easy-uncounted` and
`seam-procedure-unlisted` rows are a second run. In the first, `ctr-up-nothing`, `blk-uncounted`,
`cpy-lt-for-le` and `cpy-natural-strict` killed `test-memory-safety` at import (exit 255), each
by breaking the load, which uses what they changed; §1.6's change to that suite names them.
`seam-procedure-unlisted`'s first edit left `check-seam.sps` unreadable, and was corrected.

| Case | Mutation | Caught | First failing test or check line | Truncated | Run |
|---|---|---|---|---|---|
| `baseline` | no mutation: every suite and check must pass here | baseline passes |  |  | `make test` passes; `make check-test-fails` passes |
| `ctr-exit-ignores-counts` | suite-exit-status ignores the counts | yes | a pass, and native objects left: exit 1, one line naming each count not zero, in the counters' order (+2) | no | `make test SUITES="test-curl-testing"` fails; `make check-test-fails` fails |
| `ctr-up-nothing` | count-up! does nothing | yes | (curl private native) loads, reached through eval (+32) | no | `make test SUITES="test-memory-safety"` fails |
| `ctr-down-nothing` | count-down! does nothing | yes | native-counts: every kind, in native-kinds' order, each zero at the start (+13) | no | `make test SUITES="test-memory-safety"` fails |
| `ctr-no-mutex` | the mutex removed: each with-mutex a begin | yes | the mutex: 8 threads count transfer up 20000 times each, then down as often, with no raise, and the count is … | yes | `make test SUITES="test-memory-safety"` fails |
| `ctr-below-zero` | a count-down below zero allowed, and not raised | yes | a count-down below zero, a double free, raises an assertion violation and leaves the count at zero (+9) | no | `make test SUITES="test-memory-safety"` fails |
| `blk-uncounted` | foreign-block uncounted | yes | (curl private native) loads, reached through eval (+36) | no | `make test SUITES="test-memory-safety"` fails |
| `blk-free-no-count` | free-foreign-block! skips its count-down | yes | native-counts: every kind, in native-kinds' order, each zero at the start (+13) | no | `make test SUITES="test-memory-safety"` fails |
| `blk-free-dead` | freeing a dead address calls foreign-free, then raises | yes | free-foreign-block! refuses what is no address at all, and counts nothing (+1) | no | `make test SUITES="test-memory-safety"` fails |
| `cpy-bound-f2b` | the bound dropped, foreign->bytevector only | yes | copy-foreign->bytevector!: offset 0 and N one more than the length is refused before C, and the bytevector is… (+2) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bound-b2f` | the bound dropped, bytevector->foreign only | yes | copy-bytevector->foreign!: offset 0 and N one more than the length is refused before C, and the block is unto… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-lt-for-le` | < for <= in the bound | yes | (curl private native) loads, reached through eval (+26) | no | `make test SUITES="test-memory-safety"` fails |
| `cpy-bound-plus-one` | <= for <: the bound loosened by one, as if offset + n < length + 1 were <= | yes | copy-foreign->bytevector!: offset 0 and N one more than the length is refused before C, and the bytevector is… (+4) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-natural-strict` | > for >= in exact-natural?: offset 0 and N 0 refused | yes | (curl private native) loads, reached through eval (+26) | no | `make test SUITES="test-memory-safety"` fails |
| `cpy-no-offset` | offset left out of the sum | yes | copy-foreign->bytevector!: offset + N one more than the length, past 0, is refused before C, and the bytevect… (+2) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-address-0` | address 0 allowed | yes | copy-foreign->bytevector!: an address that is 0, negative or inexact, or no number; a bytevector that is none… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-raw-exported` | a raw memcpy binding exported | yes | native.sls binds memcpy twice, exports neither binding, plain or renamed, and names them only in the two chec… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bounce-from-0-f2b` | the bounce copies to offset 0, not OFFSET (foreign->bytevector) | yes | copy-foreign->bytevector!, offset past 0: through a bytevector of its own; the bytes on each side of the span… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bounce-from-0-b2f` | the bounce copies from offset 0, not OFFSET (bytevector->foreign) | yes | copy-bytevector->foreign!, offset past 0: through a bytevector of its own; the block's bytes on each side of … (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bounce-n1-f2b` | the bounce copies N+1 (foreign->bytevector) | yes | copy-foreign->bytevector!, offset past 0: through a bytevector of its own; the bytes on each side of the span… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bounce-n1-b2f` | the bounce copies N+1 (bytevector->foreign) | yes | copy-bytevector->foreign!, offset past 0: through a bytevector of its own; the block's bytes on each side of … (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `str-nul-dropped` | call-with-c-string: the NUL refusal dropped | yes | a string holding U+0000 is refused as &curl-embedded-nul, naming it, before anything is allocated or PROC runs | no | `make test SUITES="test-memory-safety"` fails |
| `str-no-terminator` | call-with-c-string: the terminator left out of the copy | yes | call-with-c-string hands C UTF-8 and a NUL: é is 195 169, λ is 206 187, U+1F600 is 240 159 152 128; c-string-… (+1) | yes | `make test SUITES="test-memory-safety"` fails; `make test-memory MEMORY_SUITES=test-memory-safety` fails |
| `str-not-freed` | call-with-c-string: the block not freed | yes | call-with-c-string hands C UTF-8 and a NUL: é is 195 169, λ is 206 187, U+1F600 is 240 159 152 128; c-string-… (+4) | yes | `make test SUITES="test-memory-safety"` fails |
| `url-no-curl-free` | curl_free skipped | yes | shared: resolve "../d?x=2" against "http://example.com/a/b/c?q=1" is "http://example.com/a/d?x=2", and the co… (+66) | yes | `make test SUITES="test-url"` fails; `make test-memory MEMORY_SUITES=test-url` fails |
| `url-no-cleanup` | curl_url_cleanup skipped | yes | shared: resolve "../d?x=2" against "http://example.com/a/b/c?q=1" is "http://example.com/a/d?x=2", and the co… (+66) | yes | `make test SUITES="test-url"` fails; `make test-memory MEMORY_SUITES=test-url` fails |
| `url-no-scheme-check` | the scheme check dropped | yes | file:///etc/passwd parses, and require-http-scheme refuses it as scheme-not-http, with no code, naming the URL | no | `make test SUITES="test-url"` fails |
| `url-nul-dropped` | the NUL refusal dropped in (curl private url) | yes | a NUL in a URL is refused as embedded-nul, with no code, naming the input, before libcurl reads it as http://… (+2) | yes | `make test SUITES="test-url"` fails |
| `url-codes-shifted` | the code->name list shifted by one | yes | libcurl's refusal: the code's name from curlue-codes, the code, the string refused, and curl_url_strerror's m… (+35) | yes | `make test SUITES="test-url test-conditions test-constants"` fails |
| `url-resolve-no-base` | url-resolve ignoring its base | yes | shared: resolve "../d?x=2" against "http://example.com/a/b/c?q=1" is "http://example.com/a/d?x=2", and the co… (+46) | yes | `make test SUITES="test-url"` fails |
| `url-row-changed` | a version row's answer changed: 8.20.0's #frag | yes | libcurl 8.20.0: resolve "#frag" against "http://example.com/a/b/c?q=1" is its row's answer, and the counts ar… | yes | `make test SUITES="test-url"` fails |
| `url-shared-changed` | a shared answer changed: /root | yes | shared: resolve "/root" against "http://example.com/a/b/c?q=1" is "http://example.com/root/", and the counts … | yes | `make test SUITES="test-url"` fails |
| `url-row-missing` | the loaded libcurl's row removed: an unknown libcurl | yes | it holds rows for 7.85.0, 8.5.0 and 8.20.0, the libcurls the lanes run (+8) | no | `make test SUITES="test-url"` fails |
| `url-missing-silent` | a missing row passing silently: the matcher falls back to the first row, and 8.20.0 has none | yes | it holds rows for 7.85.0, 8.5.0 and 8.20.0, the libcurls the lanes run (+9) | no | `make test SUITES="test-url"` fails |
| `load-strerror-direct` | curl_url_strerror bound with no foreign-entry? check | yes | decoy lacks-curl_url_strerror: a library without curl_url_strerror is missing-api, naming it | no | `make test SUITES="test-library-loading"` fails |
| `seam-alloc-native` | foreign-alloc imported by (curl private native) | yes | check-seam: src/curl/private/native.sls: (curl private native) imports foreign-alloc from (chezscheme), but l… | yes | `make check-seam` fails |
| `seam-procedure-memory` | foreign-procedure imported by (curl private memory) | yes | check-seam: src/curl/private/memory.sls: (curl private memory) imports foreign-procedure from (chezscheme), b… | yes | `make check-seam` fails |
| `seam-no-make-mutex` | make-mutex left out of allowed-chez-names | yes | check-seam: src/curl/private/counters.sls: (curl private counters) imports make-mutex from (chezscheme), but … | yes | `make check-seam` fails; `make test SUITES="test-check-seam"` fails |
| `seam-alloc-unlisted` | foreign-alloc's library-only entry removed | yes | memory-native-elsewhere: rule (f): foreign-alloc, foreign-free and foreign-procedure each imported by a libra… | yes | `make test SUITES="test-check-seam"` fails |
| `seam-procedure-unlisted` | foreign-procedure's library-only entry removed | yes | memory-native-elsewhere: rule (f): foreign-alloc, foreign-free and foreign-procedure each imported by a libra… | yes | `make test SUITES="test-check-seam"` fails |
| `pro-enum-as-int` | a wrong prototype row: curl_url_set's CURLUPart written int | yes | the headers declare each entry as one of its row's declarations: the C program's static assertions compile, w… | yes | `make test SUITES="test-constants"` fails |
| `pro-flags-int` | curl_url_set's flags bound int in native | yes | prototype: "curl_url_set" bound through bind-required as (uptr int uptr int) -> int fits a declaration its ro… | yes | `make test SUITES="test-constants"` fails |
| `pro-getinfo-int` | getinfo's destination bound int | yes | prototype: "curl_easy_getinfo" bound through bind-variadic as (uptr int int) -> int fits a declaration its ro… | yes | `make test SUITES="test-constants test-variadic"` fails |
| `pro-no-row` | an entry bound with no prototype row: strlen's row removed | yes | prototype-rows has a row for every entry point src/ binds, and src/ binds every row's entry (+1) | no | `make test SUITES="test-constants"` fails |
| `pro-default-1` | the prototype assertion's default branch passes | yes | the prototype check refuses a row that writes an enum as int: curl_url_set's CURLUPart written int fails to c… | yes | `make test SUITES="test-constants"` fails |
| `pro-enum-unsigned` | c-type-map lets an enum be unsigned-int | yes | the Scheme side's map: an enum is int, never unsigned-int; unsigned int is unsigned-int; a pointer is uptr, v… | yes | `make test SUITES="test-constants"` fails |
| `ot-dropped` | a curlot-types entry dropped: function | yes | curlot-types names exactly the CURLOT_ names in the preprocessed headers, each once | no | `make test SUITES="test-constants"` fails |
| `ot-added` | a curlot-types entry added: extra | yes | the C program compiled against libcurl's headers and ran (+116) | no | `make test SUITES="test-constants"` fails |
| `lay-last-field` | curl-easyoption's last field dropped | yes | curl-easyoption is the whole of struct curl_easyoption: its ftype-sizeof is sizeof(struct curl_easyoption) | no | `make test SUITES="test-constants"` fails |
| `lay-whole-to-prefix` | curl-easyoption's row turned prefix, with its last field dropped | yes | curl-easyoption is laid out whole, and curl-version-info-data as a prefix | no | `make test SUITES="test-constants"` fails |
| `cv-memcpy-unmarked` | memcpy's bytevector-crossing mark removed | yes | blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and me… (+2) | yes | `make test SUITES="test-collect-safe"` fails |
| `rule-url-reentry` | call-with-parsed-url's re-entry guard dropped | yes | call-with-parsed-url: re-entering PROC through a continuation, once the handle is freed, raises, and PROC run… | yes | `make test SUITES="test-url"` fails |
| `rule-cstr-reentry` | call-with-c-string's re-entry guard dropped | yes | call-with-c-string: re-entering PROC through a continuation, once the block is freed, raises, and PROC runs o… | yes | `make test SUITES="test-memory-safety"` fails |
| `rule-get-slot-kept` | curl-url-get's slot not freed | yes | shared: resolve "../d?x=2" against "http://example.com/a/b/c?q=1" is "http://example.com/a/d?x=2", and the co… (+66) | yes | `make test SUITES="test-url"` fails |
| `rule-get-uncounted` | curl-url-get's string not counted | yes | the printed row reads back as a well-formed row for this version, answering exactly the varying cases (+53) | no | `make test SUITES="test-url"` fails |
| `rule-easy-uncounted` | curl_easy_init not counted | yes | (curl private native) loads, reached through eval (+26) | no | `make test SUITES="test-native test-variadic test-memory-safety"` fails |
| `rule-probe-slot-kept` | the header probe's hout not freed | yes | every native count is zero once the load has returned: the header probe freed its handle and its slot | no | `make test SUITES="test-native"` fails |
| `rule-url-uncounted` | curl_url not counted, curl_url_cleanup still counting down | yes | the printed row reads back as a well-formed row for this version, answering exactly the varying cases (+67) | no | `make test SUITES="test-url"` fails |
| `rule-version-strings` | step 3's strings read without their bytes: c-text answers the empty string | yes | the record's version is the C oracle's (+34) | no | `make test SUITES="test-native test-library-loading"` fails |

All 58 mutations were caught; none survived. The brief's `<=` for `<` has no `<` to act on: the
bound is written `(<= (+ offset n) (bytevector-length bytevector))`, so its two nearest forms
ran, `cpy-bound-plus-one` and `cpy-natural-strict`.

### 3.1 Selected output

`ctr-exit-ignores-counts`, `make check-test-fails` (the leaks plant):

```
check-test-fails: FAILED leaks: a suite whose tests pass, but which drops a counted block, is named FAIL through the counters' line, and the suites after it run: make test exited 0
check-test-fails: FAILED leaks: ...: make test's lines differ
  wanted: check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
  wanted: suite-exit-status: exit 1 (native objects left: block 1): every native object a suite makes must be freed by its end
  wanted: test: FAIL tests/test-0-plant.sps (exit 1)
  wanted: test: pass tests/test-1-after.sps
  wanted: test: ran 2, passed 1, failed 1, hung 0
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
```

`cpy-raw-exported`:

```
FAIL native.sls binds memcpy twice, exports neither binding, plain or renamed, and names them only in the two checked copies
  expected: (2 () ())
  actual:   (2 (memcpy->bytevector) ())
```

`pro-enum-as-int` (gcc 16.2.0):

```
FAIL the headers declare each entry as one of its row's declarations: the C program's static assertions compile, with no link
  expected: compiled
  actual:   (compile 1 "" "/tmp/curl-testing.OJ9GEy/prototypes.c:14:1: error: static assertion failed: \"curl_url_set: the headers declare it otherwise than each declaration its row gives\"\n ...")
```

`url-row-missing`: the row printed on the error port, which equals the file's 8.20.0 row but for
its `where`:

```
test-url: no row of tests/known-url-verdicts.sexp is for libcurl 8.20.0.
(libcurl
 (where "TODO: say where this libcurl runs")
 (version "8.20.0")
 (answers
  ((resolve "http://example.com/a/b/c?q=1" "#frag") "http://example.com/a/b/c?q=1#frag")
  ((normalize "http://example.com/a b") (refused 3))
  ((normalize "http://exa mple.com/") (refused 3))
  ((resolve "http://a/b/c/d;p?q" "g:h") (refused 5))
  ((resolve "http://a/b/c/d;p?q" "#s") "http://a/b/c/d;p?q#s")
  ((resolve "http://a/b/c/d;p?q" "") "http://a/b/c/d;p?q")
  ((resolve "http://a/b/c/d;p?q" "http:g") (refused 28))))
```

Under Valgrind: `str-no-terminator` gave `Conditional jump or move depends on uninitialised
value(s)`, and `url-no-curl-free` `definitely lost: 1,973 bytes in 62 blocks`.

### 3.2 Watched failing, as standing tests

- **Each URL entry point absent is `missing-api`, naming it:** the six decoys
  `lacks-curl_url`, `lacks-curl_url_cleanup`, `lacks-curl_url_set`, `lacks-curl_url_get`,
  `lacks-curl_url_strerror` and `lacks-curl_free` in `test-library-loading`. Each builds a
  libcurl without the one function and asserts the whole refusal. `load-strerror-direct` shows
  one failing when its binding skips the check.
- **The prototype check's C side** has a standing control in `test-constants`: `curl_url_set`'s
  `CURLUPart` written `int` must fail to compile, and written `CURLUPart` must compile.

## Part 4: the CI stand-in

`ci/setup.sh`, in Docker `ubuntu:24.04` with `packaging/debian-prereqs.txt` installed: Chez
10.4.0 by `scripts/ci/build-chez.sh`, threaded; curl 7.85.0 by `scripts/ci/build-curl.sh`
(`build-curl.sh: curl 7.85.0 built into ... (OpenSSL v3+)`); Node 20.10.0 from nodejs.org's
`node-v20.10.0-linux-x64.tar.xz`, checked against its `SHASUMS256.txt`:
`3fe4ec5d70c8b4ffc1461dec83ab23fc70124e137c4cbbe1ccc9d6ae6ec04a7d`. Each lane, `ci/lane.sh`,
is a fresh `docker run --rm` of `ubuntu:24.04` with the tree mounted read-only, copied inside
with its `.git`, the prereqs and `git` installed, and runs what `.github/workflows/ci.yml` runs:

| Lane | Ran | libcurl | Outcome |
|---|---|---|---|
| main | `make check-help check-suites check-pins check-seam check-floors build test check-test-fails check-variadic check-dev check-clean` | Ubuntu's 8.5.0, OpenSSL 3.0.13, by discovery | passed: `test: ran 20, passed 20, failed 0, hung 0`; `check-test-fails: make test failed, as it must, in all 11 cases`; `check-variadic: all 19 steps ok, on ta6le`; check-pins, check-dev and check-clean ok; 1 min 47 s |
| floor | `make build`, its version line and Node's checked as the lane does, then `make test`, `CHEZ_CURL_LIBCURL` and `C_INCLUDE_PATH` at the floor | 7.85.0 | passed: `  version:  7.85.0`, Node v20.10.0, `test: ran 20, passed 20, failed 0, hung 0`; 3 min 21 s |
| memory | `make check-memory-gate`, then `make test-memory` | Ubuntu's 8.5.0 | passed: `check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 33 cases`; `test-memory: ran 20, passed 20, failed 0, hung 0`; 6 min 45 s |

Each reported Chez 10.4.0, Node v20.10.0, gcc 13.3.0 and valgrind-3.22.0. At the floor,
`test-url` used the 7.85.0 row, `test-constants` compiled its prototypes against 7.85.0's headers
(`curl_url_get` by its first declaration), and `test-drift` matched its 7.85.0 row. The lanes ran
after the last change to `src/` and `tests/`.

## Part 5: the final checks

On the final tree, in the container, each command's last line:

| Command | Last line |
|---|---|
| `scripts/guix-env make test` | `test: ran 20, passed 20, failed 0, hung 0` |
| `scripts/guix-env make check-test-fails` | `check-test-fails: make test failed, as it must, in all 11 cases` |
| `scripts/guix-env make check-suites` | `check-suites: every suite ends with (exit (suite-exit-status runner)) (20 checked)` |
| `scripts/guix-env make check-seam` | `check-seam: the seam holds (13 libraries in 13 files checked)` |
| `scripts/guix-env make test-memory` | `test-memory: ran 20, passed 20, failed 0, hung 0` |

And in Docker, Part 4's main and floor lanes.

## Part 6: fix round 1 (2026-10-23)

The review, and the lead's own mutants, found five rules that passed with wrong code, all of
one class: **a rule tested only on inputs where a narrower rule gives the same answer.** This
round fixed the class: every rule this slice adds was swept, and each is now tested on inputs
that tell it apart from its nearest narrower variants. Scratch for this round is under
`build/verify/m2s1/fix1/`, and is not kept either.

### 6.1 Measured

**Every protocol the libcurl lists parses as a URL** (`fix1/schemes.c`, run through C with no
flags: `P://example.com/`, and `file:///etc/passwd` for file). Each came back with its scheme as
written:

| libcurl | Protocols listed | Others than http and https | Refused by curl_url_set |
|---|---|---|---|
| 7.85.0, the floor | 20 | 18 | none |
| 8.5.0, OpenSSL and GnuTLS alike | 30 | 28 | none |
| 8.20.0, the container | 21 | 19 | none |

8.20.0 lists `mqtts`, `ws` and `wss`; 8.5.0 also the `ldap`, `rtmp` and `scp`/`sftp` families.
Nothing needed deciding: test-url requires each to parse, then be refused.

**curl hands back the bytes it was given** (`fix1/url-utf8.c`), on 7.85.0, 8.5.0 (both) and
8.20.0, with and without IDN, in all but one shape:

| Case | 7.85.0 and 8.5.0 | 8.20.0 |
|---|---|---|
| normalize `http://example.com/é`, `.../a?q=λ`, `.../a?q=U+1F600`, `http://bücher.example/` | each as given, raw UTF-8 | the same |
| resolve against A: `//bücher.example/x`, `http://example.com/é?q=λ`, `https://elsewhere/U+1F600#λ` | as given, raw | the same |
| resolve `x?q=1` against `http://example.com/é/` | `http://example.com/é/x?q=1`, raw | the same |
| resolve against A: `é`, `?q=λ`, `?q=U+1F600` | percent-encoded, lower case: `%c3%a9` | percent-encoded, upper case: `%C3%A9` |

The non-ASCII host does not vary: it comes back raw on the floor, which has no IDN, as on the
others. So 8 of the 11 are shared answers and 3 are version rows.

**A NUL at the start on the unmutated tree** (`fix1/nul-check.sps`): `url-normalize
"\x0;http://a/"`, `"\x0;"` and `"http://a/\x0;"`, `url-resolve`'s reference `"\x0;b"`, and
`call-with-parsed-url "\x0;http://a/"` each raised `&curl-url-error`, reason `embedded-nul`. The
bare `&curl-embedded-nul` is what `rv-url-nul-first` gives: with (curl private url)'s check
blind to the first character, native's check, behind it, raises its own condition. So no
translation was added, which would make that mutant equivalent; the new tests require
`&curl-url-error` at every position, and kill it.

**The u8* measurement, rerun** (`fix1/u8-offset-rerun.txt`): §1.1 now quotes both runs.

**The nothreads Chez:** `scripts/ci/build-chez.sh ... --nothreads` in Docker printed
`build-chez.sh: Chez 10.4.0 built --nothreads into /src/build/verify/m2s1/ci/chez-nothreads: (10 4 0 no)`.

### 6.2 The class sweep

Each rule this slice adds, the narrower variant that passed or could have, and the inputs that
now tell them apart:

| Rule | Narrower variant | Inputs that tell it apart | Where |
|---|---|---|---|
| The scheme check, an allowlist | refuse `file` alone, or any named few | every protocol the loaded libcurl lists but http and https, each parsed and refused by name (18, 28 or 19); http, https and HTTP accepted | test-url |
| The protocol list native reads | skip its first or last entry, or answer a few | the whole list, in order, against the C oracle's reading of the same file; and http, https and four others present | test-native, test-url |
| NUL in a URL, a scan | miss the first or last character | U+0000 first, in the middle, last, alone, and between é and λ, through url-normalize, url-resolve's base and its reference, and call-with-parsed-url; each must be `&curl-url-error`, `embedded-nul`, no code, the string named; and (fix round 2) no handle or block counted at the raise | test-url |
| NUL in a C string, a scan | the same | U+0000 first, middle, last, alone, between é and λ, after U+1F600, and (fix round 2) after €; each `&curl-embedded-nul`, PROC not run, counts zero at the raise and after | test-memory-safety |
| URLs decoded as UTF-8 | Latin-1, or any byte-per-character reading | 8 shared answers holding é, λ, U+1F600 or ü raw, through normalize and resolve; a test that 8 shared answers hold characters past ASCII | test-url |
| curl_version_info's strings decoded as UTF-8 | Latin-1 | a decoy whose host is `décoy-λ`, as UTF-8 bytes | test-library-loading |
| C strings encoded as UTF-8 | Latin-1 or UTF-16 | é, λ and U+1F600's exact bytes, and the empty string (unchanged) | test-memory-safety |
| The counters, per kind | one kind's index lost, or the double-free check for some kinds | each of the six kinds alone, counted up and back; each alone counted below zero | test-memory-safety |
| The counters' gate | read some kinds only | each of the six kinds alone fails a passing suite, its line whole | test-curl-testing |
| No reset; no back door | an export more | (curl private counters)' and (curl private memory)'s exports, written out | test-memory-safety |
| The live-block table | the last block only | two blocks live at once, freed in the order made; a 1-byte block | test-memory-safety |
| Counts in child processes | a leak left by a refused load, in a process nobody reads | the refusal probe prints its counts after every outcome, and every decoy and refusal case requires them zero | test-library-loading |
| c-type-map, a table | loosened with the binding it holds | the whole map, written out; then, for each C type a row writes, exactly the listed Chez types fit, out of all 50 types the conventions reader reads (and an ftype no layout defines) | test-constants |
| The variadic lists | getinfo taking int too | setopt `(long integer-64 uptr)` and getinfo `(uptr)`, written out, and no other variadic row | test-constants |
| More than one declaration | any row gaining a second | only curl_url_get's, two, written out; and its two let the same Chez types stand at every place | test-constants |
| `(* F)` for a pointer | any ftype for any pointer | the fit table: `(* curl-version-info-data)` only for `curl_version_info_data *`, `(* curl-easyoption)` only for `struct curl_easyoption *`, neither for `CURL *` | test-constants |
| The header's own spelling | `unsigned int` or `int` for an enum, which the C side cannot tell from it | each row's declaration read from the preprocessed headers, names dropped, and compared word for word; every row's entry found there; the reader on fixed text: first statement, after `}` and (fix round 2) directly after `{`, an attribute before and after, restrict, `(void)`, a definition passed over, an unnamed `enum` parameter, nullability qualifiers and `__attribute` | test-constants |
| The enum names | a name dropped, with its map entry | the seven names written out, equal to c-type-map's int entries but int, each a `typedef enum` in the headers, and every row type the headers so define among them; the enum reader on fixed text: a tag, nested braces, first and last, a struct and an untyped enum | test-constants |
| The reader's type universe | a type kind dropped | readable-types, written out | test-collect-safe |
| The slice's conventions rows | loosened with their bindings | strlen's, the six URL entries' and memcpy's rows, written out whole | test-collect-safe |
| scan-signatures | read every type from the use | a template's own parameter list, a use's, and a use's result, on the crossing-wrapper tree | test-collect-safe |
| The curlot scan | miss an identifier at the text's edge | the fixed text's first and last words are CURLOT_ names | test-constants |
| load-shared-object, a seam rule | any library may load | imported by another library, in either family (`curl/x.sls`, and since fix round 2 `http-client/h.sls`), refused; native's passes | test-check-seam |

Rules swept that already held: the copies' bounds and argument types (both directions, both
paths, each edge); memcpy's bindings unexported; `curlue-codes`, written out in test-conditions;
the URL tables' coverage and the matcher on made-up rows; the layout extents; each URL entry's
`missing-api`.

**Spawned processes that reach (curl private native)**, and how each reports its counts:

| Program | Spawned by | Covered by |
|---|---|---|
| `tests/refusal-probe.sps` | test-library-loading, every decoy, refusal and real-library case | prints `(counts . ...)`; every case requires all zero |
| `tests/preflight.sps` | test-library-loading (6 cases), `make build`, `make dev`, `expect-missing-api.sh` | output left whole, as its contract. Each path it reaches is also run through the probe: the accepted decoy, the real libcurl, invalid-override, below-floor, the raising fixture and not-found, and options-off and headers-off, which `expect-missing-api.sh` runs |
| `tests/memory-load-curl.sps` | `check-memory-gate` (a check, not a suite) | the successful load, whose counts test-native asserts in its own process, and the probe in every loaded case |
| `make dev`'s REPL | `check-dev` (a check) | the same load path |
| suites in copies | `check-test-fails`, `check-variadic` | each exits through suite-exit-status, which reads its own counts |

test-memory-safety's dead-address child reaches memory and counters only, never native, and
prints its counts too.

### 6.3 What changed

- `src/curl/private/native.sls`: `loaded-protocols`, read in step 3 from
  `curl_version_info_data`'s `protocols`, private.
- `tests/check-seam.sps`: `load-shared-object` for (curl private native) alone; its two fixtures.
- `tests/test-url.sps` and `tests/known-url-verdicts.sexp`: 11 non-ASCII cases (69 in all, 59
  shared, 10 varying), each listed protocol refused, and NUL at five positions through every
  entry point.
- `tests/test-memory-safety.sps`: NUL at six positions; each kind alone, up and below zero; two
  live blocks; the export lists.
- `tests/test-curl-testing.sps`: each kind alone fails the gate.
- `tests/refusal-probe.sps`, `tests/test-library-loading.sps`: the probe's counts, asserted zero
  in every case; the `host-utf8` decoy (`tests/decoy-libcurl.c`, `DECOY_HOST_UTF8`).
- `tests/libcurl-oracle.c`, `tests/libcurl-oracle.sls`, `tests/test-native.sps`: the oracle's
  `protocols` mode, and loaded-protocols held to it.
- `tests/foreign-conventions.sls`: `readable-types`.
- `tests/test-collect-safe.sps`: readable-types, the slice's rows and scan-signatures through
  wrappers, each pinned.
- `tests/test-constants.sps`: the map, the variadic lists and the declaration counts pinned; the
  fit table against the whole universe; `(* F)` held to its layout; the header spelling check;
  the enum names; the readers on fixed text.

### 6.4 Mutations

Each ran in a copy, as in Part 3, on the final tree: the 58 of Part 3 again, the review's ten
(`rv-`, its nine and `probe-leak-on-refusal`), the lead's six (`ld-`, `scheme-file-only` and
the five it had killed), and this round's 22 (`fx-`). `seam-procedure-unlisted`'s replacement
was respelled for `check-seam.sps`'s new last entry. `rv-long-map-int` replaces `("long" long)`
in c-type-map alone: the pinned copy holds the same text, so the review's one-match edit no
longer applies. The review's harness ran a probe beside some cases; here the suites alone
decide.

| Case | Mutation | Caught | First failing test or check line | Truncated | Run |
|---|---|---|---|---|---|
| `baseline` | no mutation: every suite and check must pass here | baseline passes |  |  | `make test` passes; `make check-test-fails` passes |
| `ctr-exit-ignores-counts` | suite-exit-status ignores the counts | yes | a pass, and native objects left: exit 1, one line naming each count not zero, in the counters' order (+8) | no | `make test SUITES="test-curl-testing"` fails; `make check-test-fails` fails |
| `ctr-up-nothing` | count-up! does nothing | yes | (curl private native) loads, reached through eval (+44) | no | `make test SUITES="test-memory-safety"` fails |
| `ctr-down-nothing` | count-down! does nothing | yes | native-counts: every kind, in native-kinds' order, each zero at the start (+31) | no | `make test SUITES="test-memory-safety"` fails |
| `ctr-no-mutex` | the mutex removed: each with-mutex a begin | yes | the mutex: 8 threads count transfer up 20000 times each, then down as often, with no raise, and the count is … | yes | `make test SUITES="test-memory-safety"` fails |
| `ctr-below-zero` | a count-down below zero allowed, and not raised | yes | a count-down below zero, a double free, raises an assertion violation and leaves the count at zero (+27) | no | `make test SUITES="test-memory-safety"` fails |
| `blk-uncounted` | foreign-block uncounted | yes | (curl private native) loads, reached through eval (+43) | no | `make test SUITES="test-memory-safety"` fails |
| `blk-free-no-count` | free-foreign-block! skips its count-down | yes | native-counts: every kind, in native-kinds' order, each zero at the start (+20) | no | `make test SUITES="test-memory-safety"` fails |
| `blk-free-dead` | freeing a dead address calls foreign-free, then raises | yes | free-foreign-block! refuses what is no address at all, and counts nothing (+1) | no | `make test SUITES="test-memory-safety"` fails |
| `cpy-bound-f2b` | the bound dropped, foreign->bytevector only | yes | copy-foreign->bytevector!: offset 0 and N one more than the length is refused before C, and the bytevector is… (+2) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bound-b2f` | the bound dropped, bytevector->foreign only | yes | copy-bytevector->foreign!: offset 0 and N one more than the length is refused before C, and the block is unto… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-lt-for-le` | < for <= in the bound | yes | (curl private native) loads, reached through eval (+31) | no | `make test SUITES="test-memory-safety"` fails |
| `cpy-bound-plus-one` | <= for <: the bound loosened by one, as if offset + n < length + 1 were <= | yes | copy-foreign->bytevector!: offset 0 and N one more than the length is refused before C, and the bytevector is… (+4) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-natural-strict` | > for >= in exact-natural?: offset 0 and N 0 refused | yes | (curl private native) loads, reached through eval (+31) | no | `make test SUITES="test-memory-safety"` fails |
| `cpy-no-offset` | offset left out of the sum | yes | copy-foreign->bytevector!: offset + N one more than the length, past 0, is refused before C, and the bytevect… (+2) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-address-0` | address 0 allowed | yes | copy-foreign->bytevector!: an address that is 0, negative or inexact, or no number; a bytevector that is none… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-raw-exported` | a raw memcpy binding exported | yes | native.sls binds memcpy twice, exports neither binding, plain or renamed, and names them only in the two chec… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bounce-from-0-f2b` | the bounce copies to offset 0, not OFFSET (foreign->bytevector) | yes | copy-foreign->bytevector!, offset past 0: through a bytevector of its own; the bytes on each side of the span… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bounce-from-0-b2f` | the bounce copies from offset 0, not OFFSET (bytevector->foreign) | yes | copy-bytevector->foreign!, offset past 0: through a bytevector of its own; the block's bytes on each side of … (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bounce-n1-f2b` | the bounce copies N+1 (foreign->bytevector) | yes | copy-foreign->bytevector!, offset past 0: through a bytevector of its own; the bytes on each side of the span… (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `cpy-bounce-n1-b2f` | the bounce copies N+1 (bytevector->foreign) | yes | copy-bytevector->foreign!, offset past 0: through a bytevector of its own; the block's bytes on each side of … (+1) | yes | `make test SUITES="test-memory-safety"` fails |
| `str-nul-dropped` | call-with-c-string: the NUL refusal dropped | yes | call-with-c-string refuses "\x0;abc" as &curl-embedded-nul, naming it, before anything is allocated or PROC r… (+5) | yes | `make test SUITES="test-memory-safety"` fails |
| `str-no-terminator` | call-with-c-string: the terminator left out of the copy | yes | call-with-c-string hands C UTF-8 and a NUL: é is 195 169, λ is 206 187, U+1F600 is 240 159 152 128; c-string-… (+1) | yes | `make test SUITES="test-memory-safety"` fails; `make test-memory MEMORY_SUITES=test-memory-safety` fails |
| `str-not-freed` | call-with-c-string: the block not freed | yes | call-with-c-string hands C UTF-8 and a NUL: é is 195 169, λ is 206 187, U+1F600 is 240 159 152 128; c-string-… (+9) | yes | `make test SUITES="test-memory-safety"` fails |
| `url-no-curl-free` | curl_free skipped | yes | shared: resolve "../d?x=2" against "http://example.com/a/b/c?q=1" is "http://example.com/a/d?x=2", and the co… (+113) | yes | `make test SUITES="test-url"` fails; `make test-memory MEMORY_SUITES=test-url` fails |
| `url-no-cleanup` | curl_url_cleanup skipped | yes | shared: resolve "../d?x=2" against "http://example.com/a/b/c?q=1" is "http://example.com/a/d?x=2", and the co… (+113) | yes | `make test SUITES="test-url"` fails; `make test-memory MEMORY_SUITES=test-url` fails |
| `url-no-scheme-check` | the scheme check dropped | yes | file:///etc/passwd parses, and require-http-scheme refuses it as scheme-not-http, with no code, naming the URL (+19) | no | `make test SUITES="test-url"` fails |
| `url-nul-dropped` | the NUL refusal dropped in (curl private url) | yes | url-normalize refuses "\x0;http://a/" as &curl-url-error, embedded-nul, with no code, naming it, before libcu… (+19) | yes | `make test SUITES="test-url"` fails |
| `url-codes-shifted` | the code->name list shifted by one | yes | libcurl's refusal: the code's name from curlue-codes, the code, the string refused, and curl_url_strerror's m… (+35) | yes | `make test SUITES="test-url test-conditions test-constants"` fails |
| `url-resolve-no-base` | url-resolve ignoring its base | yes | shared: resolve "../d?x=2" against "http://example.com/a/b/c?q=1" is "http://example.com/a/d?x=2", and the co… (+55) | yes | `make test SUITES="test-url"` fails |
| `url-row-changed` | a version row's answer changed: 8.20.0's #frag | yes | libcurl 8.20.0: resolve "#frag" against "http://example.com/a/b/c?q=1" is its row's answer, and the counts ar… | yes | `make test SUITES="test-url"` fails |
| `url-shared-changed` | a shared answer changed: /root | yes | shared: resolve "/root" against "http://example.com/a/b/c?q=1" is "http://example.com/root/", and the counts … | yes | `make test SUITES="test-url"` fails |
| `url-row-missing` | the loaded libcurl's row removed: an unknown libcurl | yes | it holds rows for 7.85.0, 8.5.0 and 8.20.0, the libcurls the lanes run (+11) | no | `make test SUITES="test-url"` fails |
| `url-missing-silent` | a missing row passing silently: the matcher falls back to the first row, and 8.20.0 has none | yes | it holds rows for 7.85.0, 8.5.0 and 8.20.0, the libcurls the lanes run (+12) | no | `make test SUITES="test-url"` fails |
| `load-strerror-direct` | curl_url_strerror bound with no foreign-entry? check | yes | decoy lacks-curl_url_strerror: a library without curl_url_strerror is missing-api, naming it | no | `make test SUITES="test-library-loading"` fails |
| `seam-alloc-native` | foreign-alloc imported by (curl private native) | yes | check-seam: src/curl/private/native.sls: (curl private native) imports foreign-alloc from (chezscheme), but l… | yes | `make check-seam` fails |
| `seam-procedure-memory` | foreign-procedure imported by (curl private memory) | yes | check-seam: src/curl/private/memory.sls: (curl private memory) imports foreign-procedure from (chezscheme), b… | yes | `make check-seam` fails |
| `seam-no-make-mutex` | make-mutex left out of allowed-chez-names | yes | check-seam: src/curl/private/counters.sls: (curl private counters) imports make-mutex from (chezscheme), but … | yes | `make check-seam` fails; `make test SUITES="test-check-seam"` fails |
| `seam-alloc-unlisted` | foreign-alloc's library-only entry removed | yes | memory-native-elsewhere: rule (f): foreign-alloc, foreign-free, foreign-procedure and load-shared-object each… | yes | `make test SUITES="test-check-seam"` fails |
| `seam-procedure-unlisted` | foreign-procedure's library-only entry removed | yes | memory-native-elsewhere: rule (f): foreign-alloc, foreign-free, foreign-procedure and load-shared-object each… | yes | `make test SUITES="test-check-seam"` fails |
| `pro-enum-as-int` | a wrong prototype row: curl_url_set's CURLUPart written int | yes | the headers declare each entry as one of its row's declarations: the C program's static assertions compile, w… (+1) | yes | `make test SUITES="test-constants"` fails |
| `pro-flags-int` | curl_url_set's flags bound int in native | yes | prototype: "curl_url_set" bound through bind-required as (uptr int uptr int) -> int fits a declaration its ro… | yes | `make test SUITES="test-constants"` fails |
| `pro-getinfo-int` | getinfo's destination bound int | yes | prototype: "curl_easy_getinfo" bound through bind-variadic as (uptr int int) -> int fits a declaration its ro… | yes | `make test SUITES="test-constants test-variadic"` fails |
| `pro-no-row` | an entry bound with no prototype row: strlen's row removed | yes | prototype-rows has a row for every entry point src/ binds, and src/ binds every row's entry (+1) | no | `make test SUITES="test-constants"` fails |
| `pro-default-1` | the prototype assertion's default branch passes | yes | the prototype check refuses a row that writes an enum as int: curl_url_set's CURLUPart written int fails to c… | yes | `make test SUITES="test-constants"` fails |
| `pro-enum-unsigned` | c-type-map lets an enum be unsigned-int | yes | c-type-map is exactly, written out here: void, int, unsigned int, long, size_t and curl_off_t each to its one… (+2) | yes | `make test SUITES="test-constants"` fails |
| `ot-dropped` | a curlot-types entry dropped: function | yes | curlot-types names exactly the CURLOT_ names in the preprocessed headers, each once | no | `make test SUITES="test-constants"` fails |
| `ot-added` | a curlot-types entry added: extra | yes | the C program compiled against libcurl's headers and ran (+116) | no | `make test SUITES="test-constants"` fails |
| `lay-last-field` | curl-easyoption's last field dropped | yes | curl-easyoption is the whole of struct curl_easyoption: its ftype-sizeof is sizeof(struct curl_easyoption) | no | `make test SUITES="test-constants"` fails |
| `lay-whole-to-prefix` | curl-easyoption's row turned prefix, with its last field dropped | yes | curl-easyoption is laid out whole, and curl-version-info-data as a prefix | no | `make test SUITES="test-constants"` fails |
| `cv-memcpy-unmarked` | memcpy's bytevector-crossing mark removed | yes | blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and me… (+3) | yes | `make test SUITES="test-collect-safe"` fails |
| `rule-url-reentry` | call-with-parsed-url's re-entry guard dropped | yes | call-with-parsed-url: re-entering PROC through a continuation, once the handle is freed, raises, and PROC run… | yes | `make test SUITES="test-url"` fails |
| `rule-cstr-reentry` | call-with-c-string's re-entry guard dropped | yes | call-with-c-string: re-entering PROC through a continuation, once the block is freed, raises, and PROC runs o… | yes | `make test SUITES="test-memory-safety"` fails |
| `rule-get-slot-kept` | curl-url-get's slot not freed | yes | shared: resolve "../d?x=2" against "http://example.com/a/b/c?q=1" is "http://example.com/a/d?x=2", and the co… (+113) | yes | `make test SUITES="test-url"` fails |
| `rule-get-uncounted` | curl-url-get's string not counted | yes | the printed row reads back as a well-formed row for this version, answering exactly the varying cases (+83) | no | `make test SUITES="test-url"` fails |
| `rule-easy-uncounted` | curl_easy_init not counted | yes | (curl private native) loads, reached through eval (+31) | no | `make test SUITES="test-native test-variadic test-memory-safety"` fails |
| `rule-probe-slot-kept` | the header probe's hout not freed | yes | every native count is zero once the load has returned: the header probe freed its handle and its slot | no | `make test SUITES="test-native"` fails |
| `rule-url-uncounted` | curl_url not counted, curl_url_cleanup still counting down | yes | the printed row reads back as a well-formed row for this version, answering exactly the varying cases (+97) | no | `make test SUITES="test-url"` fails |
| `rule-version-strings` | step 3's strings read without their bytes: c-text answers the empty string | yes | the record's version is the C oracle's (+36) | no | `make test SUITES="test-native test-library-loading"` fails |
| `rv-nul-native-end` | review: native's holds-nul? never looks at the last character | yes | call-with-c-string refuses "abc\x0;" as &curl-embedded-nul, naming it, before anything is allocated or PROC r… (+2) | yes | `make test SUITES="test-memory-safety test-url"` fails |
| `rv-nul-native-start` | review: native's holds-nul? never looks at the first character | yes | call-with-c-string refuses "\x0;abc" as &curl-embedded-nul, naming it, before anything is allocated or PROC r… (+1) | yes | `make test SUITES="test-memory-safety test-url"` fails |
| `rv-url-nul-first` | review: url.sls's holds-nul? never looks at the first character | yes | url-normalize refuses "\x0;http://a/" as &curl-url-error, embedded-nul, with no code, naming it, before libcu… (+7) | yes | `make test SUITES="test-url"` fails |
| `rv-url-latin1` | review: url.sls decodes curl_url_get's bytes as Latin-1 | yes | shared: normalize "http://example.com/é" is "http://example.com/é", and the counts are back at zero (+7) | no | `make test SUITES="test-url"` fails |
| `rv-long-map-int` | review: c-type-map lets long be int, and curl_global_init's flags are bound int (against the new code: c-type-map's entry alone, since the pinned copy holds the same text) | yes | c-type-map is exactly, written out here: void, int, unsigned int, long, size_t and curl_off_t each to its one… (+1) | yes | `make test SUITES="test-constants test-collect-safe test-native"` fails |
| `rv-getinfo-row-int` | review: getinfo's row admits int, and getinfo's destination is bound int | yes | the variadic rows are curl_easy_setopt's and curl_easy_getinfo's alone: setopt passes exactly long, integer-6… | yes | `make test SUITES="test-constants test-collect-safe test-variadic test-native"` fails |
| `rv-second-decl` | review: curl_global_init's row gains a second declaration, (int), and the binding uses it | yes | only curl_url_get's row gives more than one declaration, and it gives two | no | `make test SUITES="test-constants test-collect-safe test-native"` fails |
| `rv-enum-unsigned-row` | review: curl_url_set's row writes CURLUPart as unsigned int, and the binding unsigned-int | yes | prototype: the headers declare curl_url_set in one of its row's spellings, an enum by its own name | no | `make test SUITES="test-constants test-url"` fails |
| `rv-probe-slot-leak-on-refusal` | review: the header probe keeps its slot when the load is about to be refused (CURLHE_NOT_BUILT_IN) | yes | decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header | no | `make test SUITES="test-native test-library-loading test-memory-safety test-url"` fails |
| `rv-probe-leak-on-refusal` | review: the header probe keeps its handle and slot when the load is about to be refused | yes | decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header | no | `make test SUITES="test-native test-library-loading test-memory-safety test-url"` fails |
| `ld-scheme-file-only` | lead: require-http-scheme refuses only file | yes | require-http-scheme refuses dict://example.com/, a protocol this libcurl lists, as scheme-not-http, after it … (+17) | yes | `make test SUITES="test-url"` fails |
| `ld-cstring-short` | lead: c-string->bytevector copies one byte fewer | yes | the loaded libcurl's version has exactly one row in tests/known-url-verdicts.sexp (+92) | no | `make test SUITES="test-url test-memory-safety"` fails |
| `ld-free-wrong-kind` | lead: curl-free counts down url, not curl-string | yes | the printed row reads back as a well-formed row for this version, answering exactly the varying cases (+114) | no | `make test SUITES="test-url"` fails |
| `ld-bound-tight` | lead: the copy bound one byte too tight | yes | (curl private native) loads, reached through eval (+31) | no | `make test SUITES="test-memory-safety"` fails |
| `ld-set-in-before` | lead: call-with-parsed-url parses in the before thunk, so a refusal leaks the handle | yes | shared: resolve "../d?x=2" against "http://example.com/a/b/c?q=1" is "http://example.com/a/d?x=2", and the co… (+113) | yes | `make test SUITES="test-url"` fails |
| `ld-memcpy-n-uint` | lead: memcpy into a bytevector bound with its count unsigned-int | yes | prototype: "memcpy" bound through bind-required as (u8* uptr unsigned-int) -> uptr fits a declaration its row… | yes | `make test SUITES="test-constants test-collect-safe"` fails |
| `fx-ftype-any` | (* F) fits any pointer, with any ftype | yes | the map, in x's row: for CURL * exactly (uptr void*) fit, and every other type a binding can write is refused (+13) | no | `make test SUITES="test-constants"` fails |
| `fx-lso-elsewhere` | load-shared-object imported by (curl private memory) | yes | check-seam: src/curl/private/memory.sls: (curl private memory) imports load-shared-object from (chezscheme), … | yes | `make check-seam` fails |
| `fx-lso-unlisted` | load-shared-object's library-only entry removed | yes | memory-native-elsewhere: rule (f): foreign-alloc, foreign-free, foreign-procedure and load-shared-object each… | yes | `make test SUITES="test-check-seam"` fails |
| `fx-protocols-short` | loaded-protocols answers its first three only | yes | the loaded libcurl lists http and https among its protocols, each once, and at least four others (+1) | no | `make test SUITES="test-url test-native"` fails |
| `fx-protocols-skip-first` | native's protocol reading starts at the second entry | yes | loaded-protocols is the protocol list the C oracle reads, in order, every entry | no | `make test SUITES="test-url test-native"` fails |
| `fx-protocols-skip-last` | native's protocol reading stops one entry early | yes | loaded-protocols is the protocol list the C oracle reads, in order, every entry | no | `make test SUITES="test-url test-native"` fails |
| `fx-protocols-empty` | loaded-protocols answers nothing | yes | the loaded libcurl lists http and https among its protocols, each once, and at least four others | no | `make test SUITES="test-url"` fails |
| `fx-url-nul-last` | url.sls's holds-nul? never looks at the last character | yes | url-normalize refuses "http://a/\x0;" as &curl-url-error, embedded-nul, with no code, naming it, before libcu… (+8) | yes | `make test SUITES="test-url"` fails |
| `fx-ctext-latin1` | native's c-text, which reads curl_version_info's strings, decodes Latin-1 | yes | decoy host-utf8: a host past ASCII is read as UTF-8: décoy-λ | no | `make test SUITES="test-library-loading"` fails |
| `fx-probe-no-counts` | the refusal probe prints no counts | yes | decoy accepted: the control loads, calling curl_global_init exactly once, after the version (+35) | no | `make test SUITES="test-library-loading"` fails |
| `fx-gate-one-kind` | suite-exit-status's gate ignores transfer | yes | a pass, and one transfer left alone: exit 1, the line naming it (+1) | no | `make test SUITES="test-curl-testing"` fails |
| `fx-below-zero-some` | a count-down below zero raises for every kind but curl-string | yes | count-down! of curl-string at zero raises, a double free, and leaves every count at zero | no | `make test SUITES="test-memory-safety"` fails |
| `fx-live-last-only` | memory's live table keeps the last block alone | yes | two blocks live at once are both counted, and each frees, the first made first; a block of 1 byte is one too (+11) | no | `make test SUITES="test-memory-safety"` fails |
| `fx-counters-reset` | (curl private counters) exports a reset | yes | (curl private counters) exports exactly native-kinds, count-up!, count-down! and native-counts: no reset; (cu… | yes | `make test SUITES="test-memory-safety"` fails |
| `fx-enum-name-dropped` | CURLUPart dropped from enum-names, and c-type-map with it | yes | the enum names, written out, are exactly c-type-map's C types that map to int, but int itself (+1) | no | `make test SUITES="test-constants"` fails |
| `fx-universe-no-ref` | readable-types leaves out (& F) | yes | readable-types: CSUG's 33 immediate types, void, the three bytevector types, the seven string types, scheme-o… (+1) | yes | `make test SUITES="test-collect-safe test-constants"` fails |
| `fx-row-loosened` | strlen's conventions row cites the can-block sentence | yes | the table's rows for strlen and the URL API are each plain, citing ADR-0013's cannot-block sentence, with no … | yes | `make test SUITES="test-collect-safe"` fails |
| `fx-signature-result` | scan-signatures records uptr for every wrapper use's result | yes | scan-signatures: the legal tree's bindings, each with how it was bound, its parameter and result types as wri… (+13) | yes | `make test SUITES="test-collect-safe test-constants"` fails |
| `fx-curlot-scan-start` | c-identifiers misses an identifier at the text's first character | yes | c-identifiers: whole identifiers with the prefix, each once, in order, the text's first and last word among t… | yes | `make test SUITES="test-constants"` fails |
| `fx-spelling-skip` | the spelling check finds no declaration, and passes a row it cannot compare | yes | the preprocessed headers declare every entry a prototype row names | no | `make test SUITES="test-constants"` fails |
| `fx-enum-tag` | enums-in reads no enum that has a tag | yes | enums-in: typedef enum, with a tag or without, its braces nested or not, first and last in the text; a typede… | yes | `make test SUITES="test-constants"` fails |
| `fx-enum-nested` | enums-in ends an enum at the first }, nested or not | yes | enums-in: typedef enum, with a tag or without, its braces nested or not, first and last in the text; a typede… | yes | `make test SUITES="test-constants"` fails |

All 96 mutations were caught by name; none survived.

### 6.5 The CI stand-in, after the last edit

| Lane | Ran | Outcome |
|---|---|---|
| main | as Part 4 | passed: `test: ran 20, passed 20, failed 0, hung 0`; `check-test-fails: make test failed, as it must, in all 11 cases`; `check-variadic: all 19 steps ok, on ta6le`; check-pins, check-dev and check-clean ok. test-url ran 144 tests there: 28 other protocols |
| floor | as Part 4 | passed: `  version:  7.85.0`, `test: ran 20, passed 20, failed 0, hung 0`; test-url ran 134 tests: 18 other protocols |
| memory | as Part 4 | passed: `check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 33 cases`; `test-memory: ran 20, passed 20, failed 0, hung 0`; 6 min 12 s |
| nothreads | Chez 10.4.0 built `--nothreads` by `build-chez.sh`, `(threaded?)` `#f`; `make check-nothreads`, as ci.yml's nothreads job runs it | passed: `check-nothreads: (curl) is refused by name` |

At the floor, the spelling check read 7.85.0's declarations, `curl_url_get`'s with `CURLU *`;
test-url refused all 18 other protocols and matched the 7.85.0 row's 10 answers.

### 6.6 The final checks

On the final tree, in the container:

| Command | Last line |
|---|---|
| `scripts/guix-env make test` | `test: ran 20, passed 20, failed 0, hung 0` |
| `scripts/guix-env make check-test-fails` | `check-test-fails: make test failed, as it must, in all 11 cases` |
| `scripts/guix-env make check-suites` | `check-suites: every suite ends with (exit (suite-exit-status runner)) (20 checked)` |
| `scripts/guix-env make check-seam` | `check-seam: the seam holds (13 libraries in 13 files checked)` |
| `scripts/guix-env make test-memory` | `test-memory: ran 20, passed 20, failed 0, hung 0` |

The tree's last edit was at 03:54; the four lanes started after it, at 03:56 and later.

## Part 7: fix round 2 (2026-10-23)

A scoped review of round 1 found six smaller gaps of the same class. Scratch for this round is
under `build/verify/m2s1/fix2/`, and is not kept.

### 7.1 Each fix

1. **NUL is refused before anything is allocated** (plan §3.3), and that is now read at the raise.
   In test-memory-safety and test-url, every NUL position records `(native-counts)` in a
   `with-exception-handler` that re-raises, which runs before any `dynamic-wind` after thunk, and
   requires all zero there as well as after. A refusal moved into the body, once the block or
   handle exists, shows it at the raise.
2. **The protocol list's NULL branch.** After a successful load, `tests/refusal-probe.sps` prints
   `(protocols . LIST)`. Every decoy whose array is NULL requires `()`. The new `DECOY_PROTOCOLS`
   decoy, `{"https", "dict", "http", NULL}`, requires exactly that list, in order. The real
   libraries' cases require the C oracle's list. The list's place in step 3 is no rule: it reads
   data `curl_version_info` already answered, makes no call, and refuses nothing. native's
   comment now says so, and nothing checks it.
3. **An empty `$CC -E`.** `header-tokens-read?` guards both header readers, and a new test, "the
   preprocessed headers hold tokens to read", names the case. The reviewer's stand-ins were
   watched failing it by name: with `fakecc/cc-e-empty` and with `fakecc/cc-e-fails`,
   test-constants exits 1, and its first FAIL line is `curl/options.h, preprocessed with $CC -E,
   names CURLOT_ types`, then `the preprocessed headers hold tokens to read` among others
   (`fix2/cc-e-empty.out`, `fix2/cc-e-fails.out`).
4. **Three-byte UTF-8.**
   - € (U+20AC) is in call-with-c-string's byte test (226 130 172), and `"€\x0;"` is a NUL
     position.
   - The UTF-8 decoy's host is now `décoy-λ€`.
   - test-url gains `normalize "http://example.com/€?q=€#€"`, a shared answer (7.2). That makes
     70 cases, 60 shared and 9 of the shared answers past ASCII.
5. **The header reader's fixed text** gains `{int sixth(enum CURLUPart);}`: a statement directly
   after `{`, and an unnamed `enum` parameter.
6. **Apple's headers.** The reader drops Clang's nullability qualifiers, `_Nonnull`,
   `_Nullable`, `_Null_unspecified`, `__nonnull`, `__nullable` and `__null_unspecified`, and skips
   `__attribute((...))` as it does `__attribute__((...))`. Each is held by fixed text, the
   declarations `seventh` and `eighth`.
7. **Log corrections.**
   - §1.3 names only headers read, and where.
   - §6.2's load-shared-object row now holds: `http-client/h.sls` imports it too, and is named.
   - Its URL NUL row now holds: the reference cases' last is `"é\x0;λ"`.
   - Its "after a brace" holds through `sixth`.

**What the header reader still cannot read**, for the Mac run. Each would fail closed, as a
false failure, never a wrong pass:
- a parameter that is a function pointer or an array: `int (*f)(void)`, `char buf[]`. No bound
  entry has one;
- an annotation `$CC -E` leaves as identifiers: Apple's bounds-safety macros, if they do not
  expand to nothing or to `__attribute__` (`__sized_by(n)`, `__counted_by(n)`,
  `__sized_by_or_null(n)`, `__single`, `__unsafe_indexable`, `__terminated_by(0)`),
  `_Nullable_result`, an unexpanded `API_AVAILABLE(...)`, and `__declspec(...)`;
- a function declared through a typedef of its type (`strlen_t strlen;`), or in K&R form;
- a name declared twice with different spellings, since the first declaration is read.

### 7.2 Measured

**The euro sign** (`fix2/url-euro.c`, through C with no flags): `normalize
"http://example.com/€?q=€#€"` and `resolve "https://elsewhere/€"` against A each came back as
given, raw UTF-8 (`\xe2\x82\xac`), on 7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS and 8.20.0
(`fix2/url-euro-docker.txt`, `fix2/url-euro-guix.txt`). The first is a shared answer.

**curl_url_get's declaration** in each lane's headers: §1.3's table.

### 7.3 Mutations

All 110 cases ran in copies, on the final tree: Part 6's 96 again, the second review's eight, and
this round's five. Of the second review's ten, `protocols-after-init` is no rule (7.1, item 2),
and `baseline` is the copy unchanged. The two fake compilers run test-constants with
`CC=review2/fakecc/cc-e-empty` or `cc-e-fails` and `REAL_CC` the container's gcc.

96 of Part 6's 96 were caught again, none surviving. The new rows:

| Case | Mutation | Caught | First failing test or check line | Truncated | Run |
|---|---|---|---|---|---|
| `rv2-url-nul-after-handle` | review 2: call-with-parsed-url checks for NUL only once its handle exists, inside the dynamic-wind body | yes | url-normalize refuses "\x0;http://a/" as &curl-url-error, embedded-nul, with no code, naming it, with no hand… (+14) | yes | `make test SUITES="test-url test-memory-safety"` fails |
| `rv2-cstr-nul-after-alloc` | review 2: call-with-c-string checks for NUL only once its block is allocated | yes | call-with-c-string refuses "\x0;abc" as &curl-embedded-nul, naming it, with nothing allocated at the raise, a… (+6) | yes | `make test SUITES="test-memory-safety test-url"` fails |
| `rv2-protocols-null-answer` | review 2: loaded-protocols answers (http https) when the protocols array is NULL | yes | decoy accepted: the control loads, calling curl_global_init exactly once, after the version (+4) | no | `make test SUITES="test-native test-url test-library-loading test-memory-safety"` fails |
| `rv2-decl-no-open-brace` | review 2: declaration-in starts a statement after ; or } only, not after { | yes | header-declaration's reading: names dropped, type keywords and struct and enum tags kept, restrict, nullabili… | yes | `make test SUITES="test-constants"` fails |
| `rv2-param-struct-tag` | review 2: parameter-type drops a last identifier even after struct, union or enum | yes | header-declaration's reading: names dropped, type keywords and struct and enum tags kept, restrict, nullabili… | yes | `make test SUITES="test-constants"` fails |
| `rv2-utf8-three-byte` | review 2: call-with-c-string and url.sls mangle every character U+0800 to U+FFFF to ? | yes | call-with-c-string hands C UTF-8 and a NUL: é is 195 169, λ is 206 187, € is 226 130 172, U+1F600 is 240 159 … (+1) | yes | `make test SUITES="test-memory-safety test-url test-library-loading test-native"` fails |
| `rv2-cc-e-empty` | review 2: $CC -E prints nothing and exits 0 (a stand-in compiler) | yes | curl/options.h, preprocessed with $CC -E, names CURLOT_ types (+21) | no | `REAL_CC="$CC" CC=/home/kishu/src/chez-curl/build/verify/m2s1/review2/fakecc/cc-e-empty make test SUITES="test-constants"` fails |
| `rv2-cc-e-fails` | review 2: $CC -E fails (a stand-in compiler) | yes | curl/options.h, preprocessed with $CC -E, names CURLOT_ types (+21) | no | `REAL_CC="$CC" CC=/home/kishu/src/chez-curl/build/verify/m2s1/review2/fakecc/cc-e-fails make test SUITES="test-constants"` fails |
| `fx2-probe-no-protocols` | the refusal probe prints no protocols after a load | yes | decoy accepted: the control loads, calling curl_global_init exactly once, after the version (+7) | no | `make test SUITES="test-library-loading"` fails |
| `fx2-protocols-reversed` | native reads the protocol list in reverse | yes | decoy protocols: a protocol list is read whole, in its order: https, dict, http (+3) | no | `make test SUITES="test-library-loading test-native"` fails |
| `fx2-nullability-kept` | the spelling reader keeps Clang's nullability qualifiers | yes | header-declaration's reading: names dropped, type keywords and struct and enum tags kept, restrict, nullabili… | yes | `make test SUITES="test-constants"` fails |
| `fx2-attribute-short` | the spelling reader skips __attribute__ only, not __attribute | yes | header-declaration's reading: names dropped, type keywords and struct and enum tags kept, restrict, nullabili… | yes | `make test SUITES="test-constants"` fails |
| `fx2-seam-curl-only` | rule (f) holds only (curl ...) libraries to library-only-chez-names | yes | ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by nam… (+1) | yes | `make test SUITES="test-check-seam"` fails |

The reviewer's own harness, `review2/mut2.py`, was run too, on its six code mutants. Each failed
by name with the tests above (`fix2/review2-harness.out`).

### 7.4 The CI stand-in, after the last edit

- **main:** passed. `test: ran 20, passed 20, failed 0, hung 0`;
  `check-test-fails: make test failed, as it must, in all 11 cases`;
  `check-variadic: all 19 steps ok, on ta6le`; check-pins, check-dev and check-clean ok.
- **floor:** its first run, beside the mutation run and the main lane, failed one test in
  test-origin, which this slice does not touch:

  ```
  FAIL raw /raw/reset-mid-body: the whole bytes, then reset
    expected: ("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" reset)
    actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" eof)
  ```

  Rerun with nothing else running, it passed: `  version:  7.85.0`, then `test: ran 20, passed 20,
  failed 0, hung 0`. That is Node 20.10.0's reset read as a FIN under load, once. It is the
  lead's to judge.
- **memory and nothreads:** not rerun. src/ changed this round in native.sls's comment alone.

### 7.5 The final checks

On the final tree, in the container:

| Command | Last line |
|---|---|
| `scripts/guix-env make test` | `test: ran 20, passed 20, failed 0, hung 0` |
| `scripts/guix-env make check-test-fails` | `check-test-fails: make test failed, as it must, in all 11 cases` |
| `scripts/guix-env make check-suites` | `check-suites: every suite ends with (exit (suite-exit-status runner)) (20 checked)` |
| `scripts/guix-env make check-seam` | `check-seam: the seam holds (13 libraries in 13 files checked)` |
| `scripts/guix-env make test-memory` | `test-memory: ran 20, passed 20, failed 0, hung 0` |
