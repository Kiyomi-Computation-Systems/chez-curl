# Variadic bindings mutation log (M0 slice 6)

Evidence for the checks M0 slice 6 added: libcurl's variadic `curl_easy_setopt` and
`curl_easy_getinfo` bound directly with `(__varargs_after 2)`
([ADR-0001](decisions/0001-bind-libcurl-directly.md), decision 1). The part is:

- `src/curl/private/native.sls`: `bind-variadic`, the second known wrapper, whose template
  carries the convention. It binds `curl-easy-setopt-long` `(uptr int long)`,
  `curl-easy-setopt-pointer` `(uptr int uptr)`, `curl-easy-setopt-off-t` `(uptr int
  integer-64)` and `curl-easy-getinfo` `(uptr int uptr)` at the end of step 6, after
  `curl_easy_cleanup`. `curl-easy-option` reads an option's id and CURLOT type code through the
  `curl-easyoption` ftype. All five are exported, with `curl-easy-init` and `curl-easy-cleanup`.
- `src/curl/private/constants.sls`: `curle-bad-function-argument`, `curlinfo-private`,
  `curlinfo-rtsp-client-cseq` and `curlot-types`, all nine `CURLOT_*` codes.
- `src/curl/private/layouts.sls`: `curl-easyoption`, `struct curl_easyoption`'s four fields.
- `tests/test-constants.sps`: a row for each constant, `(curlot-types . (each "CURLOT_"))`,
  and the layout row `(curl-easyoption . "struct curl_easyoption")`. No new field kind: `uptr`,
  `int` and `unsigned-int` were mapped already.
- `tests/foreign-conventions.sls`: `bind-variadic` in `known-wrappers`, and rows requiring
  exactly `((__varargs_after 2))` of `curl_easy_setopt`, `curl_easy_getinfo`,
  `curl_multi_setopt` and `curl_share_setopt`. Each row cites ADR-0001's decision 1: "Variadic
  entry points are bound once per value type, with `(__varargs_after 2)`."
- `tests/test-collect-safe.sps`: two fixture cases, `variadic` and `variadic-unannotated`; the
  live scan finding the four bindings through `bind-variadic`; and the table's four variadic
  rows written out by hand.
- `tests/test-variadic.sps`, a new suite: type codes, the pointer and long round trips through
  getinfo, and the four `off_t` sign answers.
- `tests/decoy-libcurl.c` and `tests/test-library-loading.sps`: the decoy defines both entry
  points, and two new `lacks-` cases.
- `make check-variadic` (`tests/check-variadic.sh`), and the CI main job's `make` line.

A driver in the session scratchpad ran every mutation. It froze a snapshot of the worktree,
without `.git`, `build/`, `.claude/` or the submodule's `.git`, and gave each mutation a fresh
copy. It applied each edit by exact-text replacement, aborting unless the target occurred
exactly once and the edit changed something. It touched the copy's `manifest.scm` (`traps.md`,
the stale `guix shell -m` profile), and ran the command through the copy's own
`scripts/guix-env`, so the container saw only that copy. Three ran at a time. A mutation counts
as killed only when the command exits non-zero and every expected line appears in its output,
whole. Some cases also name a line that must be absent. The working tree was never edited.

**Result** quotes the lines of the output that name a verdict, in output order: `test:` lines,
the `FAIL` lines, the runner's `expected:` and `actual:` lines, and `check-variadic:` and
`test-memory:` lines. It quotes at most 20 besides the expected ones, which are always shown,
and says how many more were cut. A line longer than 240 characters is cut, and says how much
was cut. Each diff keeps one line of context.

## Measurements

All in the container: Chez 10.4.0 ta6le, libcurl 8.20.0 (GnuTLS), Valgrind 3.27.0, amd64.

**The brief's facts, confirmed.** A Chez probe with the four bindings, each with
`(__varargs_after 2)`, sequenced with `let*`:

```
("PRIVATE" 10103 3)
("RTSP_CLIENT_CSEQ" 193 0)
("MAXFILESIZE_LARGE" 30117 2)
("SSLVERSION" 32 1)
(ptr 0 0 "123456789ABCDEF")
(ptr 0 0 "FEDCBA9876543210")
(long 1234567 0 0 1234567)
(long 2147483647 0 0 2147483647)
(long 2147483648 0 0 2147483647)
(long 7654321 0 0 7654321)
(long -5 43 0 7654321)
(off 0 0)
(off -1 43)
(off -4611686018427387904 43)
(off 4611686018427387904 0)
```

Each `ptr` and `long` line is the value set, setopt's code, getinfo's code, and the value read
back. 2^31 reads back as 2^31-1, and -5 is refused with 43, leaving 7654321 in place. The 7.85
and 8.5 headers' `options.h` was compared with 8.20's: `curl_easytype` and `struct
curl_easyoption` are the same in both, comments and spacing aside.

**`int` for `curl_off_t`.** With the off_t binding's value typed `int` (VA7), Chez refuses
±2^62 in its own range check, before any call. It passes -1 zero-extended, so libcurl reads
4294967295, and answers `CURLE_OK` where -1 is refused.

**What test-memory sees of what the suite frees** (VA8, VA8b). Both fail the gate, with exit 9.

- **The slot.** `foreign-free` was dropped. The slot is a `foreign-alloc` block whose address
  the suite holds as a Scheme integer in a top-level variable, and passes to getinfo as a
  `uptr`. Valgrind reports "8 bytes in 1 blocks are definitely lost", under `s_malloc`.
- **The handle.** `curl_easy_cleanup` was dropped: "4,880 bytes in 1 blocks are definitely
  lost", under `curl_easy_init`.

traps.md's blind spot is a block whose address an ftype pointer held. A plain address held as
an integer is not one.

**Two surprises.** Each was caught by a check, not by reading.

- **The mutant appears twice.** `check-variadic`'s first run failed its own mutant step: the
  mutant template text appeared twice after the mutation. `bind-required`'s template already
  reads `(foreign-procedure entry (arg ...) result)`. The step now requires that count to rise
  by exactly one.
- **The poison read back.** In VA4, getinfo refused the wrong CURLINFO code with 48,
  `CURLE_UNKNOWN_OPTION`, and wrote nothing. The slot read back the poison,
  6510615555426900570 (`#x5A5A5A5A5A5A5A5A`), not the earlier sentinel.

## Red runs

**Before any code.** The tests were written first: the rows in `test-constants`, the fixture
cases and live-scan tests in `test-collect-safe`, the two `lacks-` cases, and `test-variadic`.
`make test` then exited 2:

```
FAIL variadic: ADR-0001's variadic rows: (__varargs_after 2) through the variadic wrapper and directly holds; through the plain wrapper, with no convention, (__varargs_after 1) and __varargs alone each mismatch
FAIL variadic-unannotated: make check-variadic's mutant: the variadic wrapper's template without (__varargs_after 2), so each of its uses mismatches
FAIL the scan of src/ finds curl_easy_setopt bound three times, once per value type, and curl_easy_getinfo once, each through bind-variadic with (__varargs_after 2)
FAIL the table requires exactly (__varargs_after 2) of the four variadic entries ADR-0001 names, citing its decision 1, and of no other entry
test: FAIL tests/test-collect-safe.sps (exit 1)
FAIL constant-rows' row curle-bad-function-argument is an export of constants.sls
FAIL constant-rows' row curlinfo-private is an export of constants.sls
FAIL constant-rows' row curlinfo-rtsp-client-cseq is an export of constants.sls
FAIL constant-rows' row curlot-types is an export of constants.sls
FAIL layout-rows' row curl-easyoption is a define-ftype in layouts.sls
FAIL constants.sls: curlot-types is a non-empty list of (name . value), each name a symbol
FAIL every row of constant-rows and layout-rows is checked
FAIL curle-bad-function-argument is CURLE_BAD_FUNCTION_ARGUMENT
FAIL curlinfo-private is CURLINFO_PRIVATE
FAIL curlinfo-rtsp-client-cseq is CURLINFO_RTSP_CLIENT_CSEQ
test: FAIL tests/test-constants.sps (exit 1)
FAIL decoy lacks-curl_easy_setopt: a library without curl_easy_setopt is missing-api, naming it
FAIL decoy lacks-curl_easy_getinfo: a library without curl_easy_getinfo is missing-api, naming it
test: FAIL tests/test-library-loading.sps (exit 1)
Exception: attempt to reference unbound identifier curlot-types at line 93, char 29 of tests/test-variadic.sps
test: FAIL tests/test-variadic.sps (exit 255)
test: ran 15, passed 11, failed 4, hung 0
```

`test-variadic`'s red run here names no test: native exported nothing yet. VA4 to VA7 are its
red runs by name. `check-variadic`'s are CV1 to CV5, below, with VA1 for its static step.

**On Apple arm64: pending.** No machine here is Apple arm64. The maintainer's M1 must run
`make check-variadic`, whose arm64 step requires `test-variadic` to fail on the mutant there,
and `make test`, which must pass. Until then, nothing here shows that the convention is what
makes the values arrive on that ABI, nor that `test-variadic` would see them fail to.

## Mutations

24 cases ran: 23 mutations, and `CLEAN`, the unchanged snapshot, which must pass. 20 mutations
were killed, each with every expected line present. VA8 and VA8b are measurements, with no
expected line, and test-memory failed both. VA5b survived, and is recorded as a limit.

| ID | Change | Killed by |
|---|---|---|
| VA1 | `(__varargs_after 2)` removed from `bind-variadic`'s template | test-collect-safe: four mismatches; test-variadic passes on x86-64; arm64 pending |
| VA2 | `curl-easy-setopt-long` bound through `bind-required` | test-collect-safe: one mismatch, and the binder named |
| VA3 | `curl_easy_getinfo`'s row removed | test-collect-safe: `no-row`, the table test, the fixture cases |
| VA3b | `curl_multi_setopt`'s row removed (bound nowhere in src/) | test-collect-safe: the table test, the `variadic` fixture case |
| VA4 | `curlinfo-private` off by one | test-constants by name; test-variadic: getinfo 48, the poison read |
| VA4b | `curlinfo-rtsp-client-cseq` off by one | test-constants by name; test-variadic: read 0 |
| VA5 | `curl-easyoption`'s `id` and `type` swapped | test-constants: both offsets; test-variadic: every type and code |
| VA5b | `curl-easyoption`'s last field, `flags`, dropped | **survived**: no check compares the struct's size |
| VA6 | the long sentinels made one value | test-variadic: the sentinels' own test |
| VA6a | a planted fault: every long after the first sent negated, so refused | test-variadic: `(setopt 43 getinfo 0 read 1234567)` |
| VA6b | VA6a with one sentinel reused | test-variadic: the sentinels' test, and the round trip by its code |
| VA6c | VA6b with the setopt and getinfo codes not asserted | test-variadic: only the sentinels' test; the round trip passes |
| VA6d | VA6a, distinct sentinels, codes not asserted | test-variadic: the round trip, by the stale value read |
| VA7 | `int` for `integer-64` in the off_t binding | test-variadic: -1, -(2^62) and 2^62 |
| VA8 | `(foreign-free slot)` dropped from the suite | measured: test-memory FAILs it, 8 bytes definitely lost |
| VA8b | `(curl-easy-cleanup easy)` dropped from the suite | measured: test-memory FAILs it, 4,880 bytes definitely lost |
| VA10 | the decoy's `#undef curl_easy_setopt` and `curl_easy_getinfo` removed | test-library-loading: no decoy compiles |
| VA11 | the decoy's `curl_easy_setopt` removed | test-library-loading: every loading decoy refused, naming it |
| CV1 | check-variadic's template text made one the tree lacks | check-variadic: mutant, "0 times, not once" |
| CV2 | check-variadic treats ta6le as Apple arm64 | check-variadic: arm64, "passed on the mutant" |
| CV3 | `bind-variadic` left out of `known-wrappers` | check-variadic: control |
| CV4 | check-variadic's sed made to match nothing | check-variadic: mutant, "changed 0 lines" |
| CV5 | check-variadic's expected violations lose getinfo's | check-variadic: static |
| CLEAN | the unchanged snapshot | control: `make test` and `make check-variadic` pass |

VA6 to VA6d show what the distinct sentinels are for. 8.20 refuses a bad long and keeps the
value it had, so a refused second value reads back as the first sentinel (VA6a). With the codes
asserted, the code check catches that whatever the sentinels (VA6b). With the codes not
asserted, distinct sentinels still catch it, by the value read (VA6d). A reused sentinel
catches nothing: its round trip passes on a refused value, and only the suite's test of its own
sentinels fails (VA6c).

### VA1. the annotation removed from bind-variadic's template

**Guards:** every variadic binding carries `(__varargs_after 2)`, on every platform; this is `make check-variadic`'s mutant, applied to the tree. On x86-64 `test-variadic` passes, as ADR-0001 predicts. On Apple arm64: pending, for the maintainer's M1.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -163,3 +163,3 @@
          (required-entry entry library)
-         (foreign-procedure (__varargs_after 2) entry (arg ...) result)))))
+         (foreign-procedure entry (arg ...) result)))))
 
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL the scan of src/ finds curl_easy_setopt bound three times, once per value type, and curl_easy_getinfo once, each through bind-variadic with (__varargs_after 2)
  expected: (("curl_easy_setopt" ((((__varargs_after 2)) bind-variadic) (((__varargs_after 2)) bind-variadic) (((__varargs_after 2)) bind-variadic))) ("curl_easy_getinfo" ((((__varargs_after 2)) bind-variadic))))
  actual:   (("curl_easy_setopt" ((() bind-variadic) (() bind-variadic) (() bind-variadic))) ("curl_easy_getinfo" ((() bind-variadic))))
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((mismatch "curl_easy_setopt" ((__varargs_after 2)) () "src/curl/private/native.sls") (mismatch "curl_easy_setopt" ((__varargs_after 2)) () "src/curl/private/native.sls") (mismatch "curl_easy_setopt" ((__varargs_after 2)) () "sr [cut: 114 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: pass tests/test-variadic.sps
test: ran 15, passed 14, failed 1, hung 0
```

### VA2. curl-easy-setopt-long bound through bind-required

**Guards:** a variadic entry bound through the plain wrapper is named, with the wrapper that bound it.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -272,3 +272,3 @@
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (bind-required "curl_easy_setopt" (uptr int long) int info)))
 
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL the scan of src/ finds curl_easy_setopt bound three times, once per value type, and curl_easy_getinfo once, each through bind-variadic with (__varargs_after 2)
  expected: (("curl_easy_setopt" ((((__varargs_after 2)) bind-variadic) (((__varargs_after 2)) bind-variadic) (((__varargs_after 2)) bind-variadic))) ("curl_easy_getinfo" ((((__varargs_after 2)) bind-variadic))))
  actual:   (("curl_easy_setopt" ((() bind-required) (((__varargs_after 2)) bind-variadic) (((__varargs_after 2)) bind-variadic))) ("curl_easy_getinfo" ((((__varargs_after 2)) bind-variadic))))
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((mismatch "curl_easy_setopt" ((__varargs_after 2)) () "src/curl/private/native.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: pass tests/test-variadic.sps
test: ran 15, passed 14, failed 1, hung 0
```

### VA3. curl_easy_getinfo's row removed

**Guards:** every variadic entry has its row, and the table holds all four.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -183,3 +183,2 @@
           (list "curl_easy_setopt" '((__varargs_after 2)) variadic-after-2)
-          (list "curl_easy_getinfo" '((__varargs_after 2)) variadic-after-2)
           (list "curl_multi_setopt" '((__varargs_after 2)) variadic-after-2)
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL variadic: ADR-0001's variadic rows: (__varargs_after 2) through the variadic wrapper and directly holds; through the plain wrapper, with no convention, (__varargs_after 1) and __varargs alone each mismatch
  expected: (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_getinfo" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ( [cut: 971 more characters]
  actual:   (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_getinfo" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ( [cut: 1049 more characters]
FAIL variadic-unannotated: make check-variadic's mutant: the variadic wrapper's template without (__varargs_after 2), so each of its uses mismatches
  expected: (returned ((("curl_easy_setopt" () "tests/fixtures/conventions/variadic-unannotated/curl/w.sls" bind-variadic ()) ("curl_easy_setopt" () "tests/fixtures/conventions/variadic-unannotated/curl/w.sls" bind-variadic ()) ("curl_easy_ [cut: 662 more characters]
  actual:   (returned ((("curl_easy_setopt" () "tests/fixtures/conventions/variadic-unannotated/curl/w.sls" bind-variadic ()) ("curl_easy_setopt" () "tests/fixtures/conventions/variadic-unannotated/curl/w.sls" bind-variadic ()) ("curl_easy_ [cut: 635 more characters]
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((no-row "curl_easy_getinfo" "src/curl/private/native.sls"))
FAIL the table requires exactly (__varargs_after 2) of the four variadic entries ADR-0001 names, citing its decision 1, and of no other entry
  expected: (("curl_easy_setopt" ((__varargs_after 2)) ".plans/decisions/0001-bind-libcurl-directly.md: Variadic entry points are bound once per value type, with `(__varargs_after 2)`.") ("curl_easy_getinfo" ((__varargs_after 2)) ".plans/de [cut: 472 more characters]
  actual:   (("curl_easy_setopt" ((__varargs_after 2)) ".plans/decisions/0001-bind-libcurl-directly.md: Variadic entry points are bound once per value type, with `(__varargs_after 2)`.") ("curl_multi_setopt" ((__varargs_after 2)) ".plans/de [cut: 297 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

### VA3b. curl_multi_setopt's row removed

**Guards:** the rows for entries M3 will bind hold even while nothing binds them.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -184,3 +184,2 @@
           (list "curl_easy_getinfo" '((__varargs_after 2)) variadic-after-2)
-          (list "curl_multi_setopt" '((__varargs_after 2)) variadic-after-2)
           (list "curl_share_setopt" '((__varargs_after 2)) variadic-after-2)
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL variadic: ADR-0001's variadic rows: (__varargs_after 2) through the variadic wrapper and directly holds; through the plain wrapper, with no convention, (__varargs_after 1) and __varargs alone each mismatch
  expected: (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_getinfo" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ( [cut: 971 more characters]
  actual:   (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_getinfo" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ( [cut: 1003 more characters]
FAIL the table requires exactly (__varargs_after 2) of the four variadic entries ADR-0001 names, citing its decision 1, and of no other entry
  expected: (("curl_easy_setopt" ((__varargs_after 2)) ".plans/decisions/0001-bind-libcurl-directly.md: Variadic entry points are bound once per value type, with `(__varargs_after 2)`.") ("curl_easy_getinfo" ((__varargs_after 2)) ".plans/de [cut: 472 more characters]
  actual:   (("curl_easy_setopt" ((__varargs_after 2)) ".plans/decisions/0001-bind-libcurl-directly.md: Variadic entry points are bound once per value type, with `(__varargs_after 2)`.") ("curl_easy_getinfo" ((__varargs_after 2)) ".plans/de [cut: 297 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

### VA4. a wrong CURLINFO constant: curlinfo-private off by one

**Guards:** each constant against the headers, and getinfo's readback of the pointer.

**Mutation:** In `src/curl/private/constants.sls`:

```diff
@@ -94,3 +94,3 @@
   ;; curl_easy_getinfo writes the pointer CURLOPT_PRIVATE set, as given.
-  (define curlinfo-private 1048597)
+  (define curlinfo-private 1048598)
 
```

**Result:** killed, exit 2, 17 s, through `make test`:

```
FAIL curlinfo-private is CURLINFO_PRIVATE
  expected: 1048597
  actual:   1048598
test: FAIL tests/test-constants.sps (exit 1)
FAIL PRIVATE set to #x123456789ABCDEF through curl-easy-setopt-pointer reads back exactly through curl-easy-getinfo
  expected: (setopt 0 getinfo 0 read 81985529216486895)
  actual:   (setopt 0 getinfo 48 read 6510615555426900570)
FAIL PRIVATE set to #xFEDCBA9876543210 through curl-easy-setopt-pointer reads back exactly through curl-easy-getinfo
  expected: (setopt 0 getinfo 0 read 18364758544493064720)
  actual:   (setopt 0 getinfo 48 read 6510615555426900570)
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 13, failed 2, hung 0
```

### VA4b. a wrong CURLINFO constant: curlinfo-rtsp-client-cseq off by one

**Guards:** each constant against the headers, and getinfo's readback of the long.

**Mutation:** In `src/curl/private/constants.sls`:

```diff
@@ -100,3 +100,3 @@
   ;; CURLOPT_RTSP_CLIENT_CSEQ set.
-  (define curlinfo-rtsp-client-cseq 2097189)
+  (define curlinfo-rtsp-client-cseq 2097190)
 
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL curlinfo-rtsp-client-cseq is CURLINFO_RTSP_CLIENT_CSEQ
  expected: 2097189
  actual:   2097190
test: FAIL tests/test-constants.sps (exit 1)
FAIL RTSP_CLIENT_CSEQ set to 1234567 through curl-easy-setopt-long reads back exactly through curl-easy-getinfo
  expected: (setopt 0 getinfo 0 read 1234567)
  actual:   (setopt 0 getinfo 0 read 0)
FAIL RTSP_CLIENT_CSEQ set to 2000000011 through curl-easy-setopt-long reads back exactly through curl-easy-getinfo
  expected: (setopt 0 getinfo 0 read 2000000011)
  actual:   (setopt 0 getinfo 0 read 0)
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 13, failed 2, hung 0
```

### VA5. a wrong curl-easyoption field offset: id and type swapped

**Guards:** each field's offset, size and kind, and the type codes curl-easy-option reads.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
@@ -68,4 +68,4 @@
       (name uptr)
+      (type unsigned-int)
       (id int)
-      (type unsigned-int)
       (flags unsigned-int))))
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL struct curl_easyoption.type has the header's offset, size and kind
  expected: (offset 12 size 4 kind integer)
  actual:   (offset 8 size 4 kind integer)
FAIL struct curl_easyoption.id has the header's offset, size and kind
  expected: (offset 8 size 4 kind integer)
  actual:   (offset 12 size 4 kind integer)
test: FAIL tests/test-constants.sps (exit 1)
FAIL PRIVATE is known to the loaded libcurl as CURLOT_OBJECT, the pointer curl-easy-setopt-pointer passes
  expected: (type 3)
  actual:   (type 10103)
FAIL RTSP_CLIENT_CSEQ is known to the loaded libcurl as CURLOT_LONG, the long curl-easy-setopt-long passes
  expected: (type 0)
  actual:   (type 193)
FAIL MAXFILESIZE_LARGE is known to the loaded libcurl as CURLOT_OFF_T, the curl_off_t curl-easy-setopt-off-t passes
  expected: (type 2)
  actual:   (type 30117)
FAIL PRIVATE set to #x123456789ABCDEF through curl-easy-setopt-pointer reads back exactly through curl-easy-getinfo
  expected: (setopt 0 getinfo 0 read 81985529216486895)
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 13, failed 2, hung 0
```
(22 more such lines cut.)

### VA5b. curl-easyoption's last field dropped (a limit)

**Guards:** nothing: `test-constants` checks each field written, not the struct's size, as for `curl-version-info-data`. native never steps from one option to the next, so the size is not used. Recorded so the records can decide.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
@@ -69,3 +69,2 @@
       (id int)
-      (type unsigned-int)
-      (flags unsigned-int))))
+      (type unsigned-int))))
```

**Result:** as expected, exit 0, 18 s, through `make test`:

```
test: ran 15, passed 15, failed 0, hung 0
```

### VA6. a reused long sentinel

**Guards:** the suite's own rule that its long sentinels differ.

**Mutation:** In `tests/test-variadic.sps`:

```diff
@@ -78,3 +78,3 @@
 ;; Longs: in [1, 2^31-1], which libcurl 8.20 neither clamps nor refuses.
-(define long-sentinels '(1234567 2000000011))
+(define long-sentinels '(1234567 1234567))
 (define long-poison -1)
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL the long sentinels are two, distinct, each in [1, 2^31-1], and none is the poison
  expected: (two distinct in-range not-poison)
  actual:   (two same in-range not-poison)
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

### VA6a. a planted fault: the second long refused

**Guards:** a value that does not arrive is named, though setopt was called. The fault negates every long after the first, which 8.20 refuses with 43, keeping the old value: the shape a garbage vararg takes.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -272,3 +272,7 @@
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (let ((raw (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+          (calls 0))
+      (lambda (handle option value)
+        (set! calls (+ calls 1))
+        (raw handle option (if (> calls 1) (- value) value)))))
 
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL RTSP_CLIENT_CSEQ set to 2000000011 through curl-easy-setopt-long reads back exactly through curl-easy-getinfo
  expected: (setopt 0 getinfo 0 read 2000000011)
  actual:   (setopt 43 getinfo 0 read 1234567)
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

### VA6b. VA6a, with a reused sentinel

**Guards:** the setopt code check, which catches a refused value whatever the sentinels.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -272,3 +272,7 @@
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (let ((raw (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+          (calls 0))
+      (lambda (handle option value)
+        (set! calls (+ calls 1))
+        (raw handle option (if (> calls 1) (- value) value)))))
 
```

**Mutation:** In `tests/test-variadic.sps`:

```diff
@@ -78,3 +78,3 @@
 ;; Longs: in [1, 2^31-1], which libcurl 8.20 neither clamps nor refuses.
-(define long-sentinels '(1234567 2000000011))
+(define long-sentinels '(1234567 1234567))
 (define long-poison -1)
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL the long sentinels are two, distinct, each in [1, 2^31-1], and none is the poison
  expected: (two distinct in-range not-poison)
  actual:   (two same in-range not-poison)
FAIL RTSP_CLIENT_CSEQ set to 1234567 through curl-easy-setopt-long reads back exactly through curl-easy-getinfo
  expected: (setopt 0 getinfo 0 read 1234567)
  actual:   (setopt 43 getinfo 0 read 1234567)
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

### VA6c. VA6b, with the codes not asserted (the round trip must pass, to show it)

**Guards:** nothing in the round trip: with one sentinel used twice, a refused value reads back as the earlier one and passes. Only the suite's test of its own sentinels fails, and the round trip's FAIL line must be absent.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -272,3 +272,7 @@
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (let ((raw (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+          (calls 0))
+      (lambda (handle option value)
+        (set! calls (+ calls 1))
+        (raw handle option (if (> calls 1) (- value) value)))))
 
```

**Mutation:** In `tests/test-variadic.sps`:

```diff
@@ -78,3 +78,3 @@
 ;; Longs: in [1, 2^31-1], which libcurl 8.20 neither clamps nor refuses.
-(define long-sentinels '(1234567 2000000011))
+(define long-sentinels '(1234567 1234567))
 (define long-poison -1)
```

**Mutation:** In `tests/test-variadic.sps`:

```diff
@@ -137,3 +137,3 @@
          (back (foreign-ref 'long slot 0)))
-    (list 'setopt set 'getinfo got 'read back)))
+    (list 'read back)))
 
```

**Mutation:** In `tests/test-variadic.sps`:

```diff
@@ -199,3 +199,3 @@
                               " through curl-easy-setopt-long reads back exactly through curl-easy-getinfo")
-     (list 'setopt curle-ok 'getinfo curle-ok 'read value)
+     (list 'read value)
      (long-trip value)))
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL the long sentinels are two, distinct, each in [1, 2^31-1], and none is the poison
  expected: (two distinct in-range not-poison)
  actual:   (two same in-range not-poison)
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

### VA6d. VA6a, with distinct sentinels and the codes not asserted

**Guards:** the distinct sentinels alone: the stale value read back is the first sentinel, not the second. The sentinels' own test must not fail.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -272,3 +272,7 @@
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (let ((raw (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+          (calls 0))
+      (lambda (handle option value)
+        (set! calls (+ calls 1))
+        (raw handle option (if (> calls 1) (- value) value)))))
 
```

**Mutation:** In `tests/test-variadic.sps`:

```diff
@@ -137,3 +137,3 @@
          (back (foreign-ref 'long slot 0)))
-    (list 'setopt set 'getinfo got 'read back)))
+    (list 'read back)))
 
```

**Mutation:** In `tests/test-variadic.sps`:

```diff
@@ -199,3 +199,3 @@
                               " through curl-easy-setopt-long reads back exactly through curl-easy-getinfo")
-     (list 'setopt curle-ok 'getinfo curle-ok 'read value)
+     (list 'read value)
      (long-trip value)))
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL RTSP_CLIENT_CSEQ set to 2000000011 through curl-easy-setopt-long reads back exactly through curl-easy-getinfo
  expected: (read 2000000011)
  actual:   (read 1234567)
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

### VA7. int in place of integer-64 for the off_t binding

**Guards:** the high half and the sign of a curl_off_t arrive.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -278,3 +278,3 @@
   (define curl-easy-setopt-off-t
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int integer-64) int info)))
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int int) int info)))
 
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL MAXFILESIZE_LARGE set to -1 through curl-easy-setopt-off-t answers CURLE_BAD_FUNCTION_ARGUMENT
  expected: 43
  actual:   0
FAIL MAXFILESIZE_LARGE set to -4611686018427387904 through curl-easy-setopt-off-t answers CURLE_BAD_FUNCTION_ARGUMENT
  expected: 43
  actual:   #f
FAIL MAXFILESIZE_LARGE set to 4611686018427387904 through curl-easy-setopt-off-t answers CURLE_OK
  expected: 0
  actual:   #f
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

### VA8. a foreign-free dropped from the suite (a measurement)

**Guards:** whether test-memory sees a `foreign-alloc` block whose address the suite held as an integer. It does.

**Mutation:** In `tests/test-variadic.sps`:

```diff
@@ -218,3 +218,2 @@
 (curl-easy-cleanup easy)
-(foreign-free slot)
 
```

**Result:** as expected, exit 2, 9 s, through `make test-memory MEMORY_SUITES=tests/test-variadic.sps`:

```
test-memory: FAIL tests/test-variadic.sps (exit 9, Valgrind's: an error or a definite leak)
  ==841== 8 bytes in 1 blocks are definitely lost in loss record 1 of 40
  ==841==    at 0x4845772: malloc (in /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.27.0/libexec/valgrind/vgpreload_memcheck-amd64-linux.so)
  ==841==    by 0x4AC678: s_malloc (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==841==    by 0x721CC59: ???
  ==841==    by 0x4C5AA8F: ???
  ==841==    by 0x416B51: S_call_help (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==841==    by 0x41850F: boot_call (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==841==    by 0x4187F0: run_script (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==841==    by 0x40A09B: main (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==841==    definitely lost: 8 bytes in 1 blocks
  ==841==         suppressed: 171 bytes in 1 blocks
  ==841== ERROR SUMMARY: 1 errors from 1 contexts (suppressed: 1 from 1)
test-memory: ran 1, passed 0, failed 1, hung 0
```

### VA8b. curl_easy_cleanup dropped from the suite (a measurement)

**Guards:** whether test-memory sees an easy handle left open. It does.

**Mutation:** In `tests/test-variadic.sps`:

```diff
@@ -217,3 +217,2 @@
 
-(curl-easy-cleanup easy)
 (foreign-free slot)
```

**Result:** as expected, exit 2, 10 s, through `make test-memory MEMORY_SUITES=tests/test-variadic.sps`:

```
test-memory: FAIL tests/test-variadic.sps (exit 9, Valgrind's: an error or a definite leak)
  ==841== 4,880 bytes in 1 blocks are definitely lost in loss record 36 of 40
  ==841==    at 0x484D1C1: calloc (in /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.27.0/libexec/valgrind/vgpreload_memcheck-amd64-linux.so)
  ==841==    by 0x51423CB: ??? (in /gnu/store/67lpb53npkkjp5mab0arpnrq2i3xxdbg-curl-8.20.0/lib/libcurl.so.4.8.0)
  ==841==    by 0x50F08B0: curl_easy_init (in /gnu/store/67lpb53npkkjp5mab0arpnrq2i3xxdbg-curl-8.20.0/lib/libcurl.so.4.8.0)
  ==841==    by 0x6F881C2: ???
  ==841==    by 0x4C5AA8F: ???
  ==841==    by 0x416B51: S_call_help (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==841==    by 0x41850F: boot_call (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==841==    by 0x4187F0: run_script (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==841==    by 0x40A09B: main (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==841==    definitely lost: 4,880 bytes in 1 blocks
  ==841==         suppressed: 171 bytes in 1 blocks
  ==841== ERROR SUMMARY: 1 errors from 1 contexts (suppressed: 1 from 1)
test-memory: ran 1, passed 0, failed 1, hung 0
```

### VA10. the decoy's #undef lines removed

**Guards:** the decoy defines the functions, not curl.h's type-checking macros of the same names; with gcc each definition expands the macro, and no decoy compiles.

**Mutation:** In `tests/decoy-libcurl.c`:

```diff
@@ -50,4 +50,2 @@
    the same #undef. */
-#undef curl_easy_setopt
-#undef curl_easy_getinfo
 
```

**Result:** killed, exit 2, 17 s, through `make test`:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "/tmp/curl-testing.0ykKgh/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "cur [cut: 167 more characters]
  actual:   (1 1 ((reason . load-failed) (path . "/tmp/curl-testing.0ykKgh/accepted.so") (source . override) (detail . "(while loading /tmp/curl-testing.0ykKgh/accepted.so) /tmp/curl-testing.0ykKgh/accepted.so: cannot open shared object fil [cut: 81 more characters]
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "/tmp/curl-testing.0ykKgh/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_in [cut: 155 more characters]
  actual:   (1 1 ((reason . load-failed) (path . "/tmp/curl-testing.0ykKgh/ssl-null.so") (source . override) (detail . "(while loading /tmp/curl-testing.0ykKgh/ssl-null.so) /tmp/curl-testing.0ykKgh/ssl-null.so: cannot open shared object fil [cut: 81 more characters]
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "/tmp/curl-testing.0ykKgh/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version [cut: 158 more characters]
  actual:   (1 1 ((reason . load-failed) (path . "/tmp/curl-testing.0ykKgh/host-null.so") (source . override) (detail . "(while loading /tmp/curl-testing.0ykKgh/host-null.so) /tmp/curl-testing.0ykKgh/host-null.so: cannot open shared object  [cut: 84 more characters]
FAIL decoy version-null: a NULL version is load-failed, and nothing runs after curl_version_info
  expected: (0 1 ((reason . load-failed) (path . "/tmp/curl-testing.0ykKgh/version-null.so") (source . override) (detail . "curl_version_info returned no version") (candidates) (library . #f) (again same same) (calls . "curl_version_info(9) [cut: 7 more characters]
  actual:   (1 1 ((reason . load-failed) (path . "/tmp/curl-testing.0ykKgh/version-null.so") (source . override) (detail . "(while loading /tmp/curl-testing.0ykKgh/version-null.so) /tmp/curl-testing.0ykKgh/version-null.so: cannot open share [cut: 93 more characters]
FAIL decoy below-floor: 7.84.0 is below-floor, and nothing runs after curl_version_info
  expected: (0 1 ((reason . below-floor) (path . "/tmp/curl-testing.0ykKgh/below-floor.so") (source . override) (detail . "7.84.0") (candidates) (library "/tmp/curl-testing.0ykKgh/below-floor.so" override "7.84.0" 480256 1073807373 "DecoyTL [cut: 76 more characters]
  actual:   (1 1 ((reason . load-failed) (path . "/tmp/curl-testing.0ykKgh/below-floor.so") (source . override) (detail . "(while loading /tmp/curl-testing.0ykKgh/below-floor.so) /tmp/curl-testing.0ykKgh/below-floor.so: cannot open shared o [cut: 90 more characters]
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "/tmp/curl-testing.0ykKgh/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "/tmp/curl-testing.0ykKgh/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (ag [cut: 52 more characters]
  actual:   (1 1 ((reason . load-failed) (path . "/tmp/curl-testing.0ykKgh/no-ssl.so") (source . override) (detail . "(while loading /tmp/curl-testing.0ykKgh/no-ssl.so) /tmp/curl-testing.0ykKgh/no-ssl.so: cannot open shared object file: No  [cut: 75 more characters]
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```
(48 more such lines cut.)

### VA11. the decoy's curl_easy_setopt removed

**Guards:** every decoy meant to load needs the new entry points: without one it is refused as missing-api, naming it.

**Mutation:** In `tests/decoy-libcurl.c`:

```diff
@@ -212,9 +212,2 @@
    either is in a log the suite expects, and one there would fail it. */
-#ifndef DECOY_LACKS_curl_easy_setopt
-CURLcode curl_easy_setopt(CURL *easy, CURLoption option, ...)
-{
-  called("curl_easy_setopt(%s,%d)", HANDLE_NAME(easy), (int)option);
-  return CURLE_OK;
-}
-#endif
 
```

**Result:** killed, exit 2, 16 s, through `make test`:

```
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  expected: (0 0 ((loaded . "/tmp/curl-testing.vCpQw4/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "cur [cut: 167 more characters]
  actual:   (0 1 ((reason . missing-api) (path . "/tmp/curl-testing.vCpQw4/accepted.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.vCpQw4/accepted.so" override "7.85.0" 480512 1073807373 "Dec [cut: 100 more characters]
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
  expected: (0 0 ((loaded . "/tmp/curl-testing.vCpQw4/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (again same same) (calls . "curl_version_in [cut: 155 more characters]
  actual:   (0 1 ((reason . missing-api) (path . "/tmp/curl-testing.vCpQw4/ssl-null.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.vCpQw4/ssl-null.so" override "7.85.0" 480512 1073807373 #f " [cut: 88 more characters]
FAIL decoy host-null: a NULL host is reported as #f
  expected: (0 0 ((loaded . "/tmp/curl-testing.vCpQw4/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (again same same) (calls . "curl_version [cut: 158 more characters]
  actual:   (0 1 ((reason . missing-api) (path . "/tmp/curl-testing.vCpQw4/host-null.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.vCpQw4/host-null.so" override "7.85.0" 480512 1073807373 "D [cut: 92 more characters]
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  expected: (0 1 ((reason . missing-api) (path . "/tmp/curl-testing.vCpQw4/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.vCpQw4/options-off.so" override "7.85.0" 480512 1 [cut: 237 more characters]
  actual:   (0 1 ((reason . missing-api) (path . "/tmp/curl-testing.vCpQw4/options-off.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.vCpQw4/options-off.so" override "7.85.0" 480512 107380737 [cut: 106 more characters]
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  expected: (0 1 ((reason . missing-api) (path . "/tmp/curl-testing.vCpQw4/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "/tmp/curl-testing.vCpQw4/headers-off.so" override "7.85.0" 480512 107380737 [cut: 229 more characters]
  actual:   (0 1 ((reason . missing-api) (path . "/tmp/curl-testing.vCpQw4/headers-off.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.vCpQw4/headers-off.so" override "7.85.0" 480512 107380737 [cut: 106 more characters]
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
  expected: (0 1 ((reason . load-failed) (path . "/tmp/curl-testing.vCpQw4/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library "/tmp/curl-testing.vCpQw4/easy-init-null.so" override "7.85.0 [cut: 171 more characters]
  actual:   (0 1 ((reason . missing-api) (path . "/tmp/curl-testing.vCpQw4/easy-init-null.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.vCpQw4/easy-init-null.so" override "7.85.0" 480512 107 [cut: 112 more characters]
test: FAIL tests/test-library-loading.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```
(12 more such lines cut.)

### CV1. check-variadic: a template the tree does not hold

**Guards:** the mutation finds bind-variadic's template exactly once.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -134,3 +134,3 @@
 native=$copy/src/curl/private/native.sls
-template='(foreign-procedure (__varargs_after 2) entry (arg ...) result)'
+template='(foreign-procedure (__varargs_after 2) entry (args ...) result)'
 mutated='(foreign-procedure entry (arg ...) result)'
```

**Result:** killed, exit 2, 3 s, through `make check-variadic`:

```
check-variadic: ok copy: src/, tests/ and .plans/decisions/ copied to /tmp/check-variadic.1Z09QA/tree
check-variadic: ok machine: Chez's machine type is ta6le
check-variadic: ok control: tests/test-collect-safe.sps passes on the unchanged copy
check-variadic: ok control: tests/test-variadic.sps passes on the unchanged copy
check-variadic: FAILED mutant: the copy's native.sls holds bind-variadic's template, (foreign-procedure (__varargs_after 2) entry (args ...) result), 0 times, not once
check-variadic: stopped after 4 ok, 1 FAILED
```

### CV2. check-variadic: ta6le treated as Apple arm64

**Guards:** the arm64 step fails when test-variadic passes on the mutant. On ta6le it does pass, so this is the step's red run.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -113,3 +113,3 @@
 case $machine in
-  arm64osx | tarm64osx) apple_arm64=1 ;;
+  arm64osx | tarm64osx | ta6le) apple_arm64=1 ;;
   *) apple_arm64=0 ;;
```

**Result:** killed, exit 2, 3 s, through `make check-variadic`:

```
check-variadic: ok copy: src/, tests/ and .plans/decisions/ copied to /tmp/check-variadic.1h4fp4/tree
check-variadic: ok machine: Chez's machine type is ta6le
check-variadic: ok control: tests/test-collect-safe.sps passes on the unchanged copy
check-variadic: ok control: tests/test-variadic.sps passes on the unchanged copy
check-variadic: ok mutant: bind-variadic's template is now (foreign-procedure entry (arg ...) result), as bind-required's is, and no other line changed
check-variadic: ok static: tests/test-collect-safe.sps fails on the mutant (exit 1), naming curl_easy_setopt three times and curl_easy_getinfo once as mismatches
check-variadic: FAILED arm64: on ta6le, tests/test-variadic.sps passed on the mutant: without (__varargs_after 2) its values must not arrive on Apple arm64
```

### CV3. bind-variadic left out of known-wrappers

**Guards:** the unchanged copy must pass both suites before the mutant counts.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -195,3 +195,3 @@
   ;; them. The suite holds it equal to the wrappers src/ defines.
-  (define known-wrappers '(bind-required bind-variadic))
+  (define known-wrappers '(bind-required))
 
```

**Result:** killed, exit 2, 3 s, through `make check-variadic`:

```
check-variadic: ok copy: src/, tests/ and .plans/decisions/ copied to /tmp/check-variadic.YbXeFg/tree
check-variadic: ok machine: Chez's machine type is ta6le
check-variadic: FAILED control: tests/test-collect-safe.sps exited 1 on the unchanged copy, so nothing below would say anything about the mutation
check-variadic: stopped after 2 ok, 1 FAILED
```

### CV4. check-variadic: a sed that matches nothing

**Guards:** a mutation that changes nothing is refused.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -140,3 +140,3 @@
 [ "$found" = 1 ] || stop "mutant: the copy's native.sls holds bind-variadic's template, $template, $found times, not once"
-sed 's/(foreign-procedure (__varargs_after 2) entry (arg \.\.\.) result)/(foreign-procedure entry (arg ...) result)/' \
+sed 's/(foreign-procedure (__varargs_after 3) entry (arg \.\.\.) result)/(foreign-procedure entry (arg ...) result)/' \
   "$native" >"$tmp/native.sls" || stop "mutant: sed failed on the copy's native.sls"
```

**Result:** killed, exit 2, 3 s, through `make check-variadic`:

```
check-variadic: ok copy: src/, tests/ and .plans/decisions/ copied to /tmp/check-variadic.0GsK6h/tree
check-variadic: ok machine: Chez's machine type is ta6le
check-variadic: ok control: tests/test-collect-safe.sps passes on the unchanged copy
check-variadic: ok control: tests/test-variadic.sps passes on the unchanged copy
check-variadic: FAILED mutant: the mutation changed 0 lines, left the template 1 times and took the plain template from 1 to 1 lines; it must change one line, leave none and add one
check-variadic: stopped after 4 ok, 1 FAILED
```

### CV5. check-variadic: an expected violation list without getinfo

**Guards:** the static step compares the whole list of violations, not a substring.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -156,3 +156,3 @@
 FAIL src/ holds to the table: no violation"
-want_actual="  actual:   ($mismatch $mismatch $mismatch (mismatch \"curl_easy_getinfo\" ((__varargs_after 2)) () \"src/curl/private/native.sls\"))"
+want_actual="  actual:   ($mismatch $mismatch $mismatch)"
 run "$collect"
```

**Result:** killed, exit 2, 3 s, through `make check-variadic`:

```
check-variadic: ok copy: src/, tests/ and .plans/decisions/ copied to /tmp/check-variadic.IPVGr5/tree
check-variadic: ok machine: Chez's machine type is ta6le
check-variadic: ok control: tests/test-collect-safe.sps passes on the unchanged copy
check-variadic: ok control: tests/test-variadic.sps passes on the unchanged copy
check-variadic: ok mutant: bind-variadic's template is now (foreign-procedure entry (arg ...) result), as bind-required's is, and no other line changed
check-variadic: FAILED static: tests/test-collect-safe.sps must fail on the mutant, naming curl_easy_setopt and curl_easy_getinfo as mismatches
check-variadic: ok other: on ta6le, tests/test-variadic.sps passes on the mutant (exit 0), as expected: this ABI passes variadic arguments as it passes named ones, so only Apple arm64 (arm64osx, tarm64osx) can show the mutation
```

### CLEAN. the unchanged snapshot

**Guards:** the controls: both suites pass, and check-variadic's seven steps are ok.

**Result:** as expected, exit 0, 18 s, through `make test && make check-variadic`:

```
test: ran 15, passed 15, failed 0, hung 0
check-variadic: ok copy: src/, tests/ and .plans/decisions/ copied to /tmp/check-variadic.KBznpq/tree
check-variadic: ok machine: Chez's machine type is ta6le
check-variadic: ok control: tests/test-collect-safe.sps passes on the unchanged copy
check-variadic: ok control: tests/test-variadic.sps passes on the unchanged copy
check-variadic: ok mutant: bind-variadic's template is now (foreign-procedure entry (arg ...) result), as bind-required's is, and no other line changed
check-variadic: ok static: tests/test-collect-safe.sps fails on the mutant (exit 1), naming curl_easy_setopt three times and curl_easy_getinfo once as mismatches
check-variadic: ok other: on ta6le, tests/test-variadic.sps passes on the mutant (exit 0), as expected: this ABI passes variadic arguments as it passes named ones, so only Apple arm64 (arm64osx, tarm64osx) can show the mutation
check-variadic: all 7 steps ok, on ta6le
```

## Clean rerun

VA1 to CV5 and `CLEAN` ran on one snapshot. A comment in `layouts.sls`, on what the suite checks
of `curl-easyoption`, was reworded after it, so VA11 ran on a fresh snapshot, and so did the
runs below. After every mutation, on the worktree itself, which `diff -r --no-dereference`
showed identical to that snapshot (without `build/`, `.git` and `.claude/`), in the container:
`make test`, `make check-variadic`, `make check-test-fails`, `make check-memory-gate` and
`make test-memory` each exited 0. Their verdict lines:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (15 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: ran 15, passed 15, failed 0, hung 0
check-variadic: all 7 steps ok, on ta6le
check-test-fails: make test failed, as it must, in all 10 cases
check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 39 cases
test-memory: ran 15, passed 15, failed 0, hung 0
```

On the host: `scripts/ci/check-action-pins.sh .github/workflows` passed ("all 19 lines with a
uses key under .github/workflows name a full commit SHA, with its tag in a comment").
actionlint (Docker, `rhysd/actionlint:latest`, v1.7.12) and shellcheck
(`koalaman/shellcheck:stable`, `-s sh`, on `tests/check-variadic.sh`) each printed nothing and
exited 0. No Chez or Valgrind process, and no `check-variadic.*` directory, was left behind.

## Fix round

The slice's review found four holes, each reproduced. This round closes them.

- **The reader missed a known wrapper reached any way but by name at a form's head**
  (`tests/foreign-conventions.sls`). A wrapper's name is now an occurrence, as
  `foreign-procedure` is, allowed in two places only: the head of a use in code, and the name
  its one `define-syntax` defines. Code is outside data and outside every macro: a
  transformer, its templates, patterns and literals, and the syntax objects it builds
  (`template-forms`). A head in a macro can still be reached as data, so it is stray too
  (A4 below). Import and export forms, and what `define`, `define-values`, `lambda`,
  `case-lambda`, the let forms, `fluid-let`, `do` and `guard` bind, are read as data. A
  wrapper's use is never inside a macro now, so the pattern-variable check on a use's types
  could no longer fire, and is gone.
- **The `long` binding was never sign-tested** (`tests/test-variadic.sps`). `MAXFILESIZE`, a
  `long`, looked up by name, its type asserted `CURLOT_LONG`, set through
  `curl-easy-setopt-long` to 0 and 2^40 (`CURLE_OK`) and to -1 and -(2^40)
  (`CURLE_BAD_FUNCTION_ARGUMENT`), and a test of those cases' own design. 21 tests.
- **"Each variadic entry is bound through `bind-variadic`" was not enforced.** A row may end
  with `(bound-by BINDER)`, the one way its entry may be bound. The four variadic rows name
  `bind-variadic`. A binding made otherwise is `(wrong-binder KEY EXPECTED ACTUAL FILE)`; a
  last element tagged `bound-by` that is not `(bound-by SYMBOL)` is
  `(binder-shape KEY BINDER)`, from `table-problems`.
- **`check-variadic`'s Apple arm64 step accepted any non-zero exit.** Four mutants now bind one
  use each through `bind-required`, each from the unchanged `native.sls`. 19 steps.

`tests/test-collect-safe.sps` has nine new fixture cases (`wrapper-unquoted`, `wrapper-aliased`,
`wrapper-passed`, `wrapper-argument`, `wrapper-data`, `wrapper-template`, `wrapper-binding`,
`wrapper-import-export`, `wrong-binder`) and four seeded tables. `legal` no longer exports its
wrapper, and uses it in its own file, once in a let's initial value. `types-pattern-variable`'s
use in a syntax-case template is now stray. `variadic`'s direct binding with the convention is now
the wrong binder. 80 tests.

The driver was slice 6's, pointed at the main checkout. Two snapshots: the tree as the review
left it, for the reproductions, and the final tree, for every mutation below, which
`diff -r --no-dereference` showed identical to the working tree (without `.git`, `build/` and
`.claude/`). The working tree was never mutated.

### Measurements

All in the container, as above.

- **BusyBox.** Its `diff` prints unified output by default, and its `sh` runs its own applets
  ahead of `PATH`. So the slice's `diff | grep -c '^[<>]'` counted 0 changed lines there.
  POSIX and BSD `diff` print the normal format, so this was no BSD fault, but `check-variadic`
  now counts changed lines with `awk`. Then, under BusyBox's `sh`, with its `awk`, `sed`,
  `grep`, `diff`, `cp`, `mkdir`, `mktemp`, `rm`, `dirname` and `cat` first on `PATH`, in a
  copy: `check-variadic: all 19 steps ok, on ta6le`. `shellcheck -s sh`
  (`koalaman/shellcheck:stable`) printed nothing and exited 0.
- **getinfo's slot fits an `int` here.** With getinfo's third parameter typed `int`,
  `test-variadic` passed (CVF6): `foreign-alloc`'s 8-byte slot lies below 2^31 in this
  process, so Chez's range check never fires. CVF8 binds getinfo to `curl_easy_setopt`
  instead, to show that step's named path.
- **A crash, planted.** A binding to libc's `abort` exits 134 under `timeout`: signal 6, which
  the steps report as "dying by signal 6".

### Red runs

**Before any reader code.** The fixtures, the cases, the seeded tables and the table test were
written first. `make test` then exited 2. `legal`, rewritten, and the seeded "a binder before a
mark" passed: each gives the same answer under either reader. `wrapper-template` and
`wrapper-import-export` gained items after the reader was written, each to make one part of it
load-bearing; WM1, WM4, WM5 and WM6 below are those items' red runs.

```
FAIL table-problems, seeded: a row naming its binder, and one marked that names its binder
FAIL table-problems, seeded: binders that name no one symbol: a string, two, none, and a number
FAIL table-problems, seeded: a binder on a row whose mark quotes nothing: the mark is named, the binder read
FAIL wrapper-unquoted: the review's A1: bind-required under an unquote, in a quasiquote, which is data
FAIL wrapper-aliased: the review's A2: bind-required in identifier-syntax's template, so bind-plain is another name for it
FAIL wrapper-passed: the review's A3: bind-required an argument of a macro that puts it at a head, binding curl_easy_setopt plain and curl_easy_perform with an unmarked u8*
FAIL wrapper-argument: a known wrapper's name as an argument: the other wrapper, under a call, and an improper tail
FAIL wrapper-data: a known wrapper's name in data: a quoted symbol, a quoted use, a use under an unquote, a vector literal, a box literal
FAIL wrapper-template: a known wrapper's name in a macro, a head with a literal entry too: syntax-rules templates, one handing the use to a pattern variable, a syntax-case taking its template apart, with-syntax, quasisyntax, identifier-syntax's set! clause, a literal and a pattern, and a known wrapper defined through t
FAIL wrapper-binding: a known wrapper's name bound as a variable: define, a define's formals, lambda's, a rest list, case-lambda's, let, let*, letrec, a named let, let-values, do and guard; none is read as a use
FAIL wrapper-import-export: a known wrapper's name exported, by name and renamed, and imported by only, rename, except, prefix, for, (only (chezscheme) ...) and a body import
FAIL variadic: ADR-0001's variadic rows: (__varargs_after 2) through the variadic wrapper holds; directly, with it, is the wrong binder; through the plain wrapper, with no convention, (__varargs_after 1) and __varargs alone each mismatch, and is the wrong binder
FAIL wrong-binder: rows that name their binder: a variadic entry through another wrapper that carries its convention, and directly with it; an entry whose row names foreign-procedure, bound so and through a wrapper; a callable whose row names foreign-procedure; a marked row's binder, the mark clearing its string either
FAIL types-pattern-variable: pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, with-syntax, identifier-syntax, a callable's result, and a convention; a wrapper's use in a syntax-case template is stray; a macro whose pattern binds no type stays readable
FAIL the table requires exactly (__varargs_after 2) of the four variadic entries ADR-0001 names, citing its decision 1, each bound through bind-variadic, and of no other entry, nor names a binder for any other
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

**The review's routes, on the tree as the review left it** (`runs-before`, each a control
expected to pass, to show the hole):

| ID | Change | Result before the fix |
|---|---|---|
| A1 | `bind-required` under an unquote, in a quasiquote; an unused `bind-variadic` keeps the count | `make test`: ran 15, passed 15 |
| A2 | `(define-syntax bind-plain (identifier-syntax bind-required))` binding `curl-easy-setopt-long` | `make test`: ran 15, passed 15 |
| A3 | `(apply-binder bind-required "curl_easy_setopt" ...)` | `make test`: ran 15, passed 15 |
| A3P | A3, and a plain `curl_easy_perform` with an unmarked `u8*` | `test-collect-safe`: ran 1, passed 1 |
| A4 | a syntax-case transformer that takes its own `#'(bind-required "memcpy" ...)` apart and binds `curl_easy_setopt` | `make test`: ran 15, passed 15 |
| A5 | `(swap-entry (bind-required "memcpy" ...))`, a macro that rebuilds the use it is handed with `curl_easy_setopt` | `make test`: ran 15, passed 15 |
| D | `(foreign-procedure (__varargs_after 2) "curl_multi_setopt" (uptr int long) int)` in native | `test-collect-safe`: ran 1, passed 1 |
| L | `curl-easy-setopt-long` typed `(uptr int int)` | `make test`: ran 15, passed 15 |

A3P and D ran `test-collect-safe` alone: the decoy libcurl has neither `curl_easy_perform` nor
`curl_multi_setopt`, so `test-library-loading` fails on them for another reason. In A4 and A5,
`test-variadic` passing shows that Chez bound `curl_easy_setopt`: a `memcpy` called as setopt
would not read the value back. A4 is not in the review: thinking about templates found it.

### Mutations

27 cases ran on the final snapshot: 26 mutations, and `CLEAN`, the unchanged snapshot, which must
pass. 24 mutations were killed, each with every expected line present. A5 and FPA4 survived, and
are recorded as limits.

| ID | Change | Killed by |
|---|---|---|
| A1 | the review's A1 | test-collect-safe: `stray`, the quasiquoted use |
| A2 | the review's A2 | test-collect-safe: `stray`, `(identifier-syntax bind-required)` |
| A3 | the review's A3 | test-collect-safe: `stray`, the argument |
| A3P | A3 and the plain `u8*` perform | test-collect-safe: two `stray`s |
| A4 | a syntax-case taking its template apart | test-collect-safe: `stray`, the use in the template |
| A5 | a macro rebuilding the use it is handed | **survived**: a limit, now in the reader's header |
| FPA4 | A4 with a `foreign-procedure` form in the template, no wrapper | **survived**: a limit since slice 4, now in the reader's header |
| D | the direct `curl_multi_setopt` | test-collect-safe: `wrong-binder` |
| BR1 | `curl_multi_setopt`'s row without its binder | test-collect-safe: the table test, the `variadic` case |
| BR2 | `table-violations` never names a wrong binder | test-collect-safe: the `variadic` and `wrong-binder` cases |
| L | `curl-easy-setopt-long` typed `(uptr int int)` | test-variadic: -1, 2^40 and -(2^40), by name; 0 passes |
| WM1 | a wrapper's definition walked outside the macro context | test-collect-safe: `wrapper-template` |
| WM2 | `(only (chezscheme) ...)` accounting for a wrapper's name | test-collect-safe: `wrapper-import-export` |
| WM3 | binding forms read whole as code | test-collect-safe: `wrapper-binding` |
| WM4 | `template-forms` cut to `macro-forms` | test-collect-safe: `wrapper-template` |
| WM5 | `import` and `export` not data | test-collect-safe: `wrapper-import-export`, the body import |
| WM6 | a library's import specs walked as code | test-collect-safe: `wrapper-import-export` |
| CVF1 | long's expected scan placed where pointer stands | check-variadic: long static |
| CVF2 | the expected violations without `wrong-binder` | check-variadic: the four uses' static steps |
| CVF3 | ta6le treated as Apple arm64 | check-variadic: all five arm64 steps, `test-variadic` passing |
| CVF4 | a use's text the tree lacks | check-variadic: off-t mutant, "0 times, not once" |
| CVF5 | CVF3, each use bound to libc's `abort` | check-variadic: each setopt arm64 step, by the crash; getinfo's accepts it, and says so |
| CVF6 | CVF3, each use's last type `int` | check-variadic: the template's and getinfo's arm64 steps; each setopt's passes, by name |
| CVF7 | CVF6, long's binding named `curl-easy-setopt-pointer` | check-variadic: long arm64, "0 of them through" |
| CVF8 | CVF3, each use bound to `curl_easy_setopt` | check-variadic: the template's and each setopt's arm64 step; getinfo's passes, by name |
| CVF9 | the mutation also inserts a line | check-variadic: template mutant, "changed 335 lines" |
| CLEAN | the unchanged snapshot | control: `make test` and `make check-variadic` pass |

CVF3 is every arm64 step's red run, and CVF5 to CVF8 show what each accepts. On a setopt use
alone, the step needs exit 1 and a failing test through that binding: CVF6 passes it with 3, 2
and 3 such tests; CVF5's crash fails it, and so does CVF7's naming of another binding. On
getinfo alone, a crash passes (CVF5), and so does a named failure (CVF8).

#### A1. the review's A1: bind-required under an unquote

**Guards:** a known wrapper's name in data is stray, the use under an unquote included.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,7 @@
   ;; or a curl_off_t: the CURLcode.
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (car `(,(bind-required "curl_easy_setopt" (uptr int long) int info)))))
 
```

**Result, before the fix:** as expected, exit 0, 18 s, through `make test`:

```
test: ran 15, passed 15, failed 0, hung 0
```

**Result, after:** killed, exit 2, 18 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((stray "src/curl/private/native.sls" "(bind-required \"curl_easy_setopt\" (uptr int long) int info)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

#### A2. the review's A2: an alias by identifier-syntax

**Guards:** a known wrapper's name in a macro's template is stray.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,9 @@
   ;; or a curl_off_t: the CURLcode.
+  (define-syntax bind-plain (identifier-syntax bind-required))
+
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (bind-plain "curl_easy_setopt" (uptr int long) int info)))
 
```

**Result, before the fix:** as expected, exit 0, 18 s, through `make test`:

```
test: ran 15, passed 15, failed 0, hung 0
```

**Result, after:** killed, exit 2, 18 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((stray "src/curl/private/native.sls" "(identifier-syntax bind-required)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

#### A3. the review's A3: the wrapper an argument of a macro

**Guards:** a known wrapper's name as an argument of any form is stray.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,11 @@
   ;; or a curl_off_t: the CURLcode.
+  (define-syntax apply-binder
+    (syntax-rules ()
+      ((_ binder . args) (binder . args))))
+
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (apply-binder bind-required "curl_easy_setopt" (uptr int long) int info)))
 
```

**Result, before the fix:** as expected, exit 0, 17 s, through `make test`:

```
test: ran 15, passed 15, failed 0, hung 0
```

**Result, after:** killed, exit 2, 18 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((stray "src/curl/private/native.sls" "(apply-binder bind-required \"curl_easy_setopt\" (uptr int long) int info)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

#### A3P. A3, and a plain curl_easy_perform with an unmarked u8*

**Guards:** the same, for a binding whose row and crossing would each have failed it, had the reader seen it.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,11 @@
   ;; or a curl_off_t: the CURLcode.
+  (define-syntax apply-binder
+    (syntax-rules ()
+      ((_ binder . args) (binder . args))))
+
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (apply-binder bind-required "curl_easy_setopt" (uptr int long) int info)))
 
```

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -287,2 +287,5 @@
 
+  (define curl-easy-perform-plain
+    (load-step (apply-binder bind-required "curl_easy_perform" (u8*) int info)))
+
   ;; CURLcode curl_easy_getinfo(CURL *handle, CURLINFO info, ...), variadic
```

**Result, before the fix:** as expected, exit 0, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
test: ran 1, passed 1, failed 0, hung 0
```

**Result, after:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((stray "src/curl/private/native.sls" "(apply-binder bind-required \"curl_easy_setopt\" (uptr int long) int info)") (stray "src/curl/private/native.sls" "(apply-binder bind-required \"curl_easy_perform\" (u8*) int info)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### A4. a syntax-case taking its own template apart

**Guards:** a head with a literal entry in a template is stray: the transformer holds it as data.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,12 @@
   ;; or a curl_off_t: the CURLcode.
+  (define-syntax rebind
+    (lambda (x)
+      (syntax-case #'(bind-required "memcpy" (uptr int long) int info) ()
+        ((w e . rest) #'(w "curl_easy_setopt" . rest)))))
+
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (rebind)))
 
```

**Result, before the fix:** as expected, exit 0, 18 s, through `make test`:

```
test: ran 15, passed 15, failed 0, hung 0
```

**Result, after:** killed, exit 2, 18 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((stray "src/curl/private/native.sls" "(bind-required \"memcpy\" (uptr int long) int info)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

#### A5. a macro rebuilding the use it is handed (a limit)

**Guards:** nothing: the reader reads the use as written, `memcpy` through `bind-required`, and cannot see `swap-entry` rebuild it. Recorded in the reader's header.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,11 @@
   ;; or a curl_off_t: the CURLcode.
+  (define-syntax swap-entry
+    (syntax-rules ()
+      ((_ (w e . rest)) (w "curl_easy_setopt" . rest))))
+
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (swap-entry (bind-required "memcpy" (uptr int long) int info))))
 
```

**Result, before the fix:** as expected, exit 0, 18 s, through `make test`:

```
test: ran 15, passed 15, failed 0, hung 0
```

**Result, after:** as expected, exit 0, 18 s, through `make test`:

```
test: ran 15, passed 15, failed 0, hung 0
```

#### FPA4. A4 with a foreign-procedure form, no wrapper (a limit)

**Guards:** nothing: the reader reads a `foreign-procedure` form in a template as a direct binding, as it has since slice 4. Recorded in the reader's header.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,12 @@
   ;; or a curl_off_t: the CURLcode.
+  (define-syntax rebind
+    (lambda (x)
+      (syntax-case #'(foreign-procedure "memcpy" (uptr int long) int) ()
+        ((fp e . rest) #'(fp "curl_easy_setopt" . rest)))))
+
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (rebind)))
 
```

**Result:** as expected, exit 0, 18 s, through `make test`:

```
test: ran 15, passed 15, failed 0, hung 0
```

#### D. a direct binding of a variadic entry, with the convention

**Guards:** every binding of a variadic entry is made through `bind-variadic`.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -288,2 +288,5 @@
 
+  (define curl-multi-setopt-long
+    (load-step (foreign-procedure (__varargs_after 2) "curl_multi_setopt" (uptr int long) int)))
+
   ;; --- 7. the two API probes, then check-apis --------------------------------------------
```

**Result, before the fix:** as expected, exit 0, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
test: ran 1, passed 1, failed 0, hung 0
```

**Result, after:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((wrong-binder "curl_multi_setopt" bind-variadic foreign-procedure "src/curl/private/native.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### BR1. curl_multi_setopt's row without its binder

**Guards:** the table names `bind-variadic` for all four variadic rows, one bound nowhere in src/ yet.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -221,3 +221,3 @@
           (list "curl_easy_getinfo" '((__varargs_after 2)) variadic-after-2 '(bound-by bind-variadic))
-          (list "curl_multi_setopt" '((__varargs_after 2)) variadic-after-2 '(bound-by bind-variadic))
+          (list "curl_multi_setopt" '((__varargs_after 2)) variadic-after-2)
           (list "curl_share_setopt" '((__varargs_after 2)) variadic-after-2 '(bound-by bind-variadic))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL variadic: ADR-0001's variadic rows: (__varargs_after 2) through the variadic wrapper holds; directly, with it, is the wrong binder; through the plain wrapper, with no convention, (__varargs_after 1) and __varargs alone each mismatch, and is the wrong binder
  expected: (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_getinfo" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_setopt" () "tests/fixtures/conventions/variadic/curl/v.sls" bind- [cut: 1466 more characters]
  actual:   (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_getinfo" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_setopt" () "tests/fixtures/conventions/variadic/curl/v.sls" bind- [cut: 1234 more characters]
FAIL the table requires exactly (__varargs_after 2) of the four variadic entries ADR-0001 names, citing its decision 1, each bound through bind-variadic, and of no other entry, nor names a binder for any other
  expected: (("curl_easy_setopt" ((__varargs_after 2)) ".plans/decisions/0001-bind-libcurl-directly.md: Variadic entry points are bound once per value type, with `(__varargs_after 2)`." (bound-by bind-variadic)) ("curl_easy_getinfo" ((__varargs_after 2)) ".plans/decisions/0001-bind-libcurl-directly.md: Variadic entry p [cut: 492 more characters]
  actual:   (("curl_easy_setopt" ((__varargs_after 2)) ".plans/decisions/0001-bind-libcurl-directly.md: Variadic entry points are bound once per value type, with `(__varargs_after 2)`." (bound-by bind-variadic)) ("curl_easy_getinfo" ((__varargs_after 2)) ".plans/decisions/0001-bind-libcurl-directly.md: Variadic entry p [cut: 467 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### BR2. table-violations never names a wrong binder

**Guards:** the binder rule itself, on the fixtures.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1133,3 +1133,3 @@
                        (else (list (list 'mismatch key (cadr row) conventions file))))
-                 (if (and binder (not (eq? binder via)))
+                 (if #f
                      (list (list 'wrong-binder key binder via file))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL variadic: ADR-0001's variadic rows: (__varargs_after 2) through the variadic wrapper holds; directly, with it, is the wrong binder; through the plain wrapper, with no convention, (__varargs_after 1) and __varargs alone each mismatch, and is the wrong binder
  expected: (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_getinfo" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_setopt" () "tests/fixtures/conventions/variadic/curl/v.sls" bind- [cut: 1466 more characters]
  actual:   (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_getinfo" ((__varargs_after 2)) "tests/fixtures/conventions/variadic/curl/v.sls" bind-variadic ()) ("curl_easy_setopt" () "tests/fixtures/conventions/variadic/curl/v.sls" bind- [cut: 891 more characters]
FAIL wrong-binder: rows that name their binder: a variadic entry through another wrapper that carries its convention, and directly with it; an entry whose row names foreign-procedure, bound so and through a wrapper; a callable whose row names foreign-procedure; a marked row's binder, the mark clearing its string either [cut: 4 more characters]
  expected: (returned ((("curl_share_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/wrong-binder/curl/w.sls" bind-varargs ()) ("curl_share_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/wrong-binder/curl/w.sls" foreign-procedure ()) ("fixture_direct" () "tests/fixtures/conventions/wrong-binder/cur [cut: 1015 more characters]
  actual:   (returned ((("curl_share_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/wrong-binder/curl/w.sls" bind-varargs ()) ("curl_share_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/wrong-binder/curl/w.sls" foreign-procedure ()) ("fixture_direct" () "tests/fixtures/conventions/wrong-binder/cur [cut: 428 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### L. int in place of long for curl-easy-setopt-long

**Guards:** the sign and the high half of a long arrive. 0 must pass: its FAIL line must be absent.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -272,3 +272,3 @@
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int int) int info)))
 
```

**Result, before the fix:** as expected, exit 0, 16 s, through `make test`:

```
test: ran 15, passed 15, failed 0, hung 0
```

**Result, after:** killed, exit 2, 19 s, through `make test`:

```
FAIL MAXFILESIZE set to -1 through curl-easy-setopt-long answers CURLE_BAD_FUNCTION_ARGUMENT
  expected: 43
  actual:   0
FAIL MAXFILESIZE set to 1099511627776 through curl-easy-setopt-long answers CURLE_OK
  expected: 0
  actual:   #f
FAIL MAXFILESIZE set to -1099511627776 through curl-easy-setopt-long answers CURLE_BAD_FUNCTION_ARGUMENT
  expected: 43
  actual:   #f
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

#### WM1. a wrapper's definition walked outside the macro context

**Guards:** a known wrapper's name in its own definition's transformer is stray, though no template form holds it.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -907,3 +907,3 @@
           ;; The name is the one place a wrapper's name stands for itself.
-          (within-macro (lambda () (walk-elements form 2 #f)))))
+          (walk-elements form 2 #f)))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL wrapper-template: a known wrapper's name in a macro, a head with a literal entry too: syntax-rules templates, one handing the use to a pattern variable, a syntax-case taking its template apart, with-syntax, quasisyntax and syntax in procedures, transformers by define-syntax and let-syntax, identifier-syntax's set! [cut: 124 more characters]
  expected: (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 1458 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 1345 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### WM2. (only (chezscheme) ...) accounting for a wrapper's name

**Guards:** that import accounts for `foreign-procedure` and `foreign-callable` alone.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -917,3 +917,3 @@
                     (if (chez-only? spec)
-                        (for-each (lambda (id) (unless (occurrence? id) (walk id spec #t)))
+                        (for-each (lambda (id) (unless (name? id) (walk id spec #t)))
                                   (cddr spec))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL wrapper-import-export: a known wrapper's name exported, by name and renamed, and imported by only, rename, except, prefix, for, (only (chezscheme) ...) and a body import
  expected: (returned (() ((stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(export bind-required (rename (bind-variadic bind-v)))") (stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(bind-variadic bind-v)") (stray "tests/fixtures/conventions/wrapper-import-export/curl/i.sls" "( [cut: 747 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(export bind-required (rename (bind-variadic bind-v)))") (stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(bind-variadic bind-v)") (stray "tests/fixtures/conventions/wrapper-import-export/curl/i.sls" "( [cut: 616 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### WM3. binding forms read whole as code

**Guards:** a name a binding form binds is data: `(let ((bind-required ...)) ...)` is no use.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -796,3 +796,2 @@
                (set! bound outer)))
-            ((binding-form! form))
             (else (walk-elements form 0 #f)))))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL wrapper-binding: a known wrapper's name bound as a variable: define, a define's formals, lambda's, a rest list, case-lambda's, let, let*, letrec, a named let, let-values, do and guard; none is read as a use
  expected: (returned (() ((stray "tests/fixtures/conventions/wrapper-binding/curl/b.sls" "(define bind-required 0)") (stray "tests/fixtures/conventions/wrapper-binding/curl/b.sls" "(bind-variadic . args)") (stray "tests/fixtures/conventions/wrapper-binding/curl/b.sls" "(formal bind-required)") (stray "tests/fixtures/c [cut: 955 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/wrapper-binding/curl/b.sls" "(define bind-required 0)") (wrapper-undefined "tests/fixtures/conventions/wrapper-binding/curl/b.sls" bind-variadic "(bind-variadic . args)") (stray "tests/fixtures/conventions/wrapper-binding/curl/b.sls" "(formal bind-required)" [cut: 1189 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### WM4. template-forms cut to macro-forms

**Guards:** define-syntax, let-syntax, syntax and quasisyntax each hold a macro's parts.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -586,3 +586,3 @@
   (define template-forms
-    (append '(define-syntax let-syntax letrec-syntax syntax quasisyntax) macro-forms))
+    macro-forms)
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL wrapper-template: a known wrapper's name in a macro, a head with a literal entry too: syntax-rules templates, one handing the use to a pattern variable, a syntax-case taking its template apart, with-syntax, quasisyntax and syntax in procedures, transformers by define-syntax and let-syntax, identifier-syntax's set! [cut: 124 more characters]
  expected: (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 1458 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 972 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### WM5. import and export not data

**Guards:** a body import is data: its rename's `(bind-required c)` is no use.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -591,3 +591,3 @@
   ;; and import and export, whose parts name bindings and bind none.
-  (define data-forms '(quote quasiquote import export))
+  (define data-forms '(quote quasiquote))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL wrapper-import-export: a known wrapper's name exported, by name and renamed, and imported by only, rename, except, prefix, for, (only (chezscheme) ...) and a body import
  expected: (returned (() ((stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(export bind-required (rename (bind-variadic bind-v)))") (stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(bind-variadic bind-v)") (stray "tests/fixtures/conventions/wrapper-import-export/curl/i.sls" "( [cut: 747 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(export bind-required (rename (bind-variadic bind-v)))") (stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(bind-variadic bind-v)") (stray "tests/fixtures/conventions/wrapper-import-export/curl/i.sls" "( [cut: 780 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### WM6. a library's import specs walked as code

**Guards:** a library's import clause is data: its rename's `(bind-required b)` is no use.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -919,3 +919,3 @@
                                   (cddr spec))
-                        (walk spec (cadddr form) #t)))
+                        (walk spec (cadddr form) #f)))
                   (cdr (cadddr form)))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL wrapper-import-export: a known wrapper's name exported, by name and renamed, and imported by only, rename, except, prefix, for, (only (chezscheme) ...) and a body import
  expected: (returned (() ((stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(export bind-required (rename (bind-variadic bind-v)))") (stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(bind-variadic bind-v)") (stray "tests/fixtures/conventions/wrapper-import-export/curl/i.sls" "( [cut: 747 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(export bind-required (rename (bind-variadic bind-v)))") (stray "tests/fixtures/conventions/wrapper-import-export/curl/e.sls" "(bind-variadic bind-v)") (stray "tests/fixtures/conventions/wrapper-import-export/curl/i.sls" "( [cut: 780 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### CVF1. check-variadic: long's expected scan where pointer stands

**Guards:** the static step identifies which binding the scan found bound plain.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -340,3 +340,3 @@
 use long curl_easy_setopt '(uptr int long)' curl-easy-setopt-long \
-  "(($setopt ($plain $annotated $annotated)) ($getinfo ($annotated)))"
+  "(($setopt ($annotated $plain $annotated)) ($getinfo ($annotated)))"
 use pointer curl_easy_setopt '(uptr int uptr)' curl-easy-setopt-pointer \
```

**Result:** killed, exit 2, 5 s, through `make check-variadic`:

```
check-variadic: FAILED long static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-setopt-long alone: a mismatch and a wrong-binder for curl_easy_setopt
check-variadic: ok pointer static: tests/test-collect-safe.sps fails on the mutant (exit 1), naming curl-easy-setopt-pointer alone: a mismatch and a wrong-binder for curl_easy_setopt
```

#### CVF2. check-variadic: the expected violations without wrong-binder

**Guards:** the static step compares the whole list of violations.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -326,3 +326,3 @@
   static "$label" "  actual:   $via" \
-    "  actual:   ((mismatch \"$key\" ((__varargs_after 2)) () $file) (wrong-binder \"$key\" bind-variadic bind-required $file))" \
+    "  actual:   ((mismatch \"$key\" ((__varargs_after 2)) () $file))" \
     "$binding alone: a mismatch and a wrong-binder for $key"
```

**Result:** killed, exit 2, 5 s, through `make check-variadic`:

```
check-variadic: FAILED long static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-setopt-long alone: a mismatch and a wrong-binder for curl_easy_setopt
check-variadic: FAILED pointer static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-setopt-pointer alone: a mismatch and a wrong-binder for curl_easy_setopt
check-variadic: FAILED off-t static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-setopt-off-t alone: a mismatch and a wrong-binder for curl_easy_setopt
check-variadic: FAILED getinfo static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-getinfo alone: a mismatch and a wrong-binder for curl_easy_getinfo
```

#### CVF3. check-variadic: ta6le treated as Apple arm64

**Guards:** each arm64 step fails when test-variadic passes on its mutant. On ta6le it does pass, so this is every arm64 step's red run.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -152,3 +152,3 @@
 case $machine in
-  arm64osx | tarm64osx) apple_arm64=1 ;;
+  arm64osx | tarm64osx | ta6le) apple_arm64=1 ;;
   *) apple_arm64=0 ;;
```

**Result:** killed, exit 2, 5 s, through `make check-variadic`:

```
check-variadic: FAILED template arm64: on ta6le, tests/test-variadic.sps must fail on the mutant, by a named test or by dying; it exited 0, naming no test
check-variadic: FAILED long arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-long; it exited 0, naming no test, 0 of them through curl-easy-setopt-long
check-variadic: FAILED pointer arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-pointer; it exited 0, naming no test, 0 of them through curl-easy-setopt-pointer
check-variadic: FAILED off-t arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-off-t; it exited 0, naming no test, 0 of them through curl-easy-setopt-off-t
check-variadic: FAILED getinfo arm64: on ta6le, tests/test-variadic.sps must fail on the mutant, by a named test or by dying; it exited 0, naming no test
```

#### CVF4. check-variadic: a use's text the tree lacks

**Guards:** each use mutant finds its text exactly once.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -343,3 +343,3 @@
   "(($setopt ($annotated $plain $annotated)) ($getinfo ($annotated)))"
-use off-t curl_easy_setopt '(uptr int integer-64)' curl-easy-setopt-off-t \
+use off-t curl_easy_setopt '(uptr int int64)' curl-easy-setopt-off-t \
   "(($setopt ($annotated $annotated $plain)) ($getinfo ($annotated)))"
```

**Result:** killed, exit 2, 4 s, through `make check-variadic`:

```
check-variadic: FAILED off-t mutant: the unchanged native.sls holds (bind-variadic "curl_easy_setopt" (uptr int int64) int info) 0 times, not once
check-variadic: stopped after 13 ok, 1 FAILED
```

#### CVF5. check-variadic: each use bound to abort, on ta6le treated as Apple arm64

**Guards:** a setopt step fails on a crash; getinfo's accepts one, and says so. The static steps fail too: the mutants bind `abort`.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -152,3 +152,3 @@
 case $machine in
-  arm64osx | tarm64osx) apple_arm64=1 ;;
+  arm64osx | tarm64osx | ta6le) apple_arm64=1 ;;
   *) apple_arm64=0 ;;
```

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -324,3 +324,3 @@
   label=$1 key=$2 types=$3 binding=$4 via=$5
-  mutate "$label" "(bind-variadic \"$key\" $types int info)" "(bind-required \"$key\" $types int info)"
+  mutate "$label" "(bind-variadic \"$key\" $types int info)" "(bind-required \"abort\" $types int info)"
   static "$label" "  actual:   $via" \
```

**Result:** killed, exit 2, 6 s, through `make check-variadic`:

```
check-variadic: FAILED template arm64: on ta6le, tests/test-variadic.sps must fail on the mutant, by a named test or by dying; it exited 0, naming no test
check-variadic: FAILED long static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-setopt-long alone: a mismatch and a wrong-binder for curl_easy_setopt
check-variadic: FAILED long arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-long; it exited 134, dying by signal 6, naming no test, 0 of them through curl-easy-setopt-long
check-variadic: FAILED pointer static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-setopt-pointer alone: a mismatch and a wrong-binder for curl_easy_setopt
check-variadic: FAILED pointer arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-pointer; it exited 134, dying by signal 6, naming no test, 0 of them through curl-easy-setopt-pointer
check-variadic: FAILED off-t static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-setopt-off-t alone: a mismatch and a wrong-binder for curl_easy_setopt
check-variadic: FAILED off-t arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-off-t; it exited 134, dying by signal 6, naming no test, 0 of them through curl-easy-setopt-off-t
check-variadic: FAILED getinfo static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-getinfo alone: a mismatch and a wrong-binder for curl_easy_getinfo
check-variadic: ok getinfo arm64: on ta6le, tests/test-variadic.sps fails on the mutant (exit 134), dying by signal 6, naming no test
```

#### CVF6. check-variadic: each use's last type int, on ta6le treated as Apple arm64

**Guards:** a setopt step passes on named failures through its binding. getinfo's int slot passes here (Measurements).

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -152,3 +152,3 @@
 case $machine in
-  arm64osx | tarm64osx) apple_arm64=1 ;;
+  arm64osx | tarm64osx | ta6le) apple_arm64=1 ;;
   *) apple_arm64=0 ;;
```

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -324,3 +324,3 @@
   label=$1 key=$2 types=$3 binding=$4 via=$5
-  mutate "$label" "(bind-variadic \"$key\" $types int info)" "(bind-required \"$key\" $types int info)"
+  mutate "$label" "(bind-variadic \"$key\" $types int info)" "(bind-required \"$key\" $(printf '%s' "$types" | sed 's/ [a-z0-9-]*)$/ int)/') int info)"
   static "$label" "  actual:   $via" \
```

**Result:** killed, exit 2, 5 s, through `make check-variadic`:

```
check-variadic: FAILED template arm64: on ta6le, tests/test-variadic.sps must fail on the mutant, by a named test or by dying; it exited 0, naming no test
check-variadic: ok long arm64: on ta6le, tests/test-variadic.sps fails on the mutant by name (exit 1), naming 3 failing tests, 3 of them through curl-easy-setopt-long
check-variadic: ok pointer arm64: on ta6le, tests/test-variadic.sps fails on the mutant by name (exit 1), naming 2 failing tests, 2 of them through curl-easy-setopt-pointer
check-variadic: ok off-t arm64: on ta6le, tests/test-variadic.sps fails on the mutant by name (exit 1), naming 3 failing tests, 3 of them through curl-easy-setopt-off-t
check-variadic: FAILED getinfo arm64: on ta6le, tests/test-variadic.sps must fail on the mutant, by a named test or by dying; it exited 0, naming no test
```

#### CVF7. check-variadic: CVF6, with long's binding named curl-easy-setopt-pointer

**Guards:** a setopt step needs a failing test through its own binding, not just any.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -152,3 +152,3 @@
 case $machine in
-  arm64osx | tarm64osx) apple_arm64=1 ;;
+  arm64osx | tarm64osx | ta6le) apple_arm64=1 ;;
   *) apple_arm64=0 ;;
```

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -324,3 +324,3 @@
   label=$1 key=$2 types=$3 binding=$4 via=$5
-  mutate "$label" "(bind-variadic \"$key\" $types int info)" "(bind-required \"$key\" $types int info)"
+  mutate "$label" "(bind-variadic \"$key\" $types int info)" "(bind-required \"$key\" $(printf '%s' "$types" | sed 's/ [a-z0-9-]*)$/ int)/') int info)"
   static "$label" "  actual:   $via" \
```

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -339,3 +339,3 @@
 
-use long curl_easy_setopt '(uptr int long)' curl-easy-setopt-long \
+use long curl_easy_setopt '(uptr int long)' curl-easy-setopt-pointer \
   "(($setopt ($plain $annotated $annotated)) ($getinfo ($annotated)))"
```

**Result:** killed, exit 2, 5 s, through `make check-variadic`:

```
check-variadic: FAILED template arm64: on ta6le, tests/test-variadic.sps must fail on the mutant, by a named test or by dying; it exited 0, naming no test
check-variadic: FAILED long arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-pointer; it exited 1, naming 3 failing tests, 0 of them through curl-easy-setopt-pointer
check-variadic: FAILED getinfo arm64: on ta6le, tests/test-variadic.sps must fail on the mutant, by a named test or by dying; it exited 0, naming no test
```

#### CVF8. check-variadic: each use bound to curl_easy_setopt, on ta6le treated as Apple arm64

**Guards:** getinfo's step accepts a named failure.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -152,3 +152,3 @@
 case $machine in
-  arm64osx | tarm64osx) apple_arm64=1 ;;
+  arm64osx | tarm64osx | ta6le) apple_arm64=1 ;;
   *) apple_arm64=0 ;;
```

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -324,3 +324,3 @@
   label=$1 key=$2 types=$3 binding=$4 via=$5
-  mutate "$label" "(bind-variadic \"$key\" $types int info)" "(bind-required \"$key\" $types int info)"
+  mutate "$label" "(bind-variadic \"$key\" $types int info)" "(bind-required \"curl_easy_setopt\" $types int info)"
   static "$label" "  actual:   $via" \
```

**Result:** killed, exit 2, 5 s, through `make check-variadic`:

```
check-variadic: FAILED template arm64: on ta6le, tests/test-variadic.sps must fail on the mutant, by a named test or by dying; it exited 0, naming no test
check-variadic: FAILED long arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-long; it exited 0, naming no test, 0 of them through curl-easy-setopt-long
check-variadic: FAILED pointer arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-pointer; it exited 0, naming no test, 0 of them through curl-easy-setopt-pointer
check-variadic: FAILED off-t arm64: on ta6le, tests/test-variadic.sps must fail on the mutant by name, exiting 1, with a failing test through curl-easy-setopt-off-t; it exited 0, naming no test, 0 of them through curl-easy-setopt-off-t
check-variadic: FAILED getinfo static: tests/test-collect-safe.sps must fail on the mutant, naming curl-easy-getinfo alone: a mismatch and a wrong-binder for curl_easy_getinfo
check-variadic: ok getinfo arm64: on ta6le, tests/test-variadic.sps fails on the mutant (exit 1), naming 4 failing tests
```

#### CVF9. check-variadic: the mutation also inserts a line

**Guards:** each mutant changes one line and no other.

**Mutation:** In `tests/check-variadic.sh`:

```diff
@@ -184,2 +184,3 @@
     print
+    if (FNR == 1) print ""
   }' "$original" >"$tmp/native.sls" || stop "$label mutant: awk failed on the unchanged native.sls"
```

**Result:** killed, exit 2, 3 s, through `make check-variadic`:

```
check-variadic: FAILED template mutant: the mutation changed 335 lines, left (foreign-procedure (__varargs_after 2) entry (arg ...) result) 0 times and took (foreign-procedure entry (arg ...) result) from 1 to 2 lines; it must change one line, leave none and add one
check-variadic: stopped after 4 ok, 1 FAILED
```

#### CLEAN. the unchanged snapshot

**Guards:** the controls: `make test` passes, and check-variadic's 19 steps are ok.

**Result:** as expected, exit 0, 20 s, through `make test && make check-variadic`:

```
test: ran 15, passed 15, failed 0, hung 0
check-variadic: all 19 steps ok, on ta6le
```

### Clean rerun

After every mutation, two comments were reworded: `test-collect-safe`'s header, on what
`check-variadic` asks of it, and `check-variadic`'s own, on its mutant step. Then, on the working
tree, in the container:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (15 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: ran 15, passed 15, failed 0, hung 0
check-variadic: all 19 steps ok, on ta6le
test-memory: ran 2, passed 2, failed 0, hung 0
check-test-fails: make test failed, as it must, in all 10 cases
```

`make test-memory` ran with `MEMORY_SUITES="tests/test-variadic.sps tests/test-collect-safe.sps"`.
No Chez or Valgrind process was left behind.

**On Apple arm64: pending.** The maintainer's M1 must run `make check-variadic`. Its five arm64
steps are the only evidence that the convention makes the values arrive on that ABI, and that
`test-variadic` sees them fail to: by name, through each setopt binding alone.

### The macro table

A5 and FPA4 survived the fix round above: a macro took apart a form it was handed, or its own
template, and bound what it rebuilt, while the reader read the form as written. They are closed
now, by a table of the macros a tree may define, and this part supersedes the two limits recorded
above.

- **`known-macros`** (`tests/foreign-conventions.sls`) names src/'s four macros, `(NAME KIND
  FILE)`: `bind-required` and `bind-variadic`, `binder`, in `curl/private/native.sls`;
  `load-step` and `require-supported-chez`, `plain`, each in its own library. `known-wrappers`
  is now its binders. Each scan takes a table, and each fixture case has its own.
- **Placement.** A `define-syntax` at a library body's top level must name a row and stand in
  its file: `(macro-unlisted FILE NAME)`, `(macro-elsewhere FILE NAME LISTED)`. Any other
  `define-syntax` is `(macro-nested FILE FORM)`; a `let-syntax` or `letrec-syntax`,
  `(macro-local FILE FORM)`.
- **Plain.** A plain macro's definition holds no `foreign-procedure`, `foreign-callable` or known
  wrapper's name, `(plain-macro-binds FILE NAME SYMBOL)`; none of `syntax-case`, `with-syntax`,
  `syntax->datum` and `datum->syntax`, `(plain-macro-takes-apart FILE NAME SYMBOL)`; and no
  pattern but `(_ id ...)` in a `syntax-rules` clause, or `(set! id id)` in identifier-syntax's
  set! clause, `(plain-macro-pattern FILE NAME PATTERN)`. Both of today's plain macros pass as
  written: src/ is unchanged.
- **Binder.** Beyond the decided design, and found reading `read-wrapper`: a binder's pattern
  may take no operand apart either. Every element but its parameter list is neither a list nor a
  vector, else the wrapper is unreadable. A pattern `(_ entry (arg ...) result (w e . rest))`
  could otherwise rebuild a use it is handed, as A5 does.
- **any**, a third kind, is for fixture trees only. `legal`'s `bind-poll` holds a
  `foreign-procedure` form, so it is neither plain nor a binder. The old fixtures' macros test
  other rules. An `any` row is held to its place and file, and to neither kind's rules. The
  suite holds `known-macros` to its four rows, written out by hand, so src/'s table can name no
  `any`.

`test-collect-safe` has ten new cases, one per rule: `macro-swap-entry` (A5), `macro-rebind`
(FPA4), `macro-unlisted`, `macro-nested`, `macro-local`, `macro-elsewhere`, `plain-binds`,
`plain-takes-apart`, `plain-pattern` and `binder-takes-apart`. `legal` gained two plain macros,
shaped like src/'s, and a use handed whole to one. `wrapper-template`'s `let-syntax` is now a
local macro, and `wrapper-defined-again`'s second definition stands elsewhere than its row. Two
live tests hold `known-macros` to its four rows, written out by hand, and equal both ways to
what the scan of src/ finds. 92 tests.

#### Measurements

- **A transformer cannot return raw symbols.** A plain lambda transformer returning
  `(list (string->symbol "foreign-procedure") "abs" '(int) 'int)` failed at expansion:
  `Exception: encountered raw symbol foreign-procedure in output of macro (raw)`. So a name built
  with `string->symbol` reaches code only through `datum->syntax`, which a plain macro may not
  hold.
- **A6, a limit, measured.** A plain lambda transformer, `(lambda (x) (rebuild x))`, holding none
  of the names above, called `rebuild` from another library. That procedure took the use apart
  with `syntax->datum` and rebuilt it with `datum->syntax`, swapping the entry. Handed
  `(foreign-procedure "labs" (int) int)`, which the reader would read as `labs`, Chez bound the
  rebuilt entry: `Exception in foreign-procedure: no entry for "abs"`. The rules read macro
  definitions, not procedures. None of the four names stands anywhere in src/ today, so
  forbidding them in every src/ library would close A6 at no cost there.

#### Red run

The rules were written before their cases, so the red run is the reader with every macro rule
off, in a copy (R0): `placement!` naming nothing, `top-macro!` only recording the definition, and
`pattern-takes-apart?` answering `#f`. Every new case failed, and so did the two whose answers
the rules change. `legal` passed.

```
FAIL wrapper-template: a known wrapper's name in a macro, a head with a literal entry too: syntax-rules templates, one handing the use to a pattern variable, a syntax-case taking its template apart, with-syntax, quasisyntax and syntax in procedures, transformers by define-syntax and let-syntax, identifier-syntax's set! [cut: 124 more characters]
FAIL macro-swap-entry: A5: a macro on no row takes apart a use it is handed, which the reader reads as memcpy, and rebuilds it with curl_easy_setopt
FAIL macro-rebind: FPA4: a syntax-case on no row takes apart its own template, a foreign-procedure form the reader reads as memcpy, and binds curl_easy_setopt
FAIL macro-unlisted: a macro at a library body's top level that names no row, though it holds nothing a plain macro may not; one beside it that does
FAIL macro-nested: define-syntax anywhere but a library body's top level: in a procedure's body, in a begin, and in a listed macro's template
FAIL macro-local: local macros, by let-syntax and letrec-syntax
FAIL macro-elsewhere: a listed macro defined in a file other than its row's
FAIL plain-binds: plain macros that would build a binding: a foreign-procedure form, a foreign-callable, a known wrapper's use
FAIL plain-takes-apart: plain macros that can take their operands apart: syntax-case, with-syntax, syntax->datum and datum->syntax
FAIL plain-pattern: plain macros whose patterns take an operand apart: nested, improper, a vector, not headed by _, and identifier-syntax's set! clause; two with identifiers only, an ellipsis among them, pass
FAIL binder-takes-apart: a binder whose pattern takes its library operand apart, so its template could rebuild a use it is handed: unreadable, and none of its uses read
FAIL wrapper-defined-again: the known wrapper defined in two files: the second stands where its row does not say, and no use is read against either
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### Mutations

44 cases ran on the final snapshot, which `diff -rq --no-dereference` showed identical to the
working tree: the fix round's 26 mutations and `CLEAN`, again, and 17 new ones. All 43 mutations
were killed, each with every expected line present, and `CLEAN` passed.

The fix round's 26, rerun. A5 and FPA4 are killed now, each by `macro-unlisted`. A2, A3, A3P and
A4 each also define a macro on no row, so their violations now open with `macro-unlisted`, before
the `stray` above. Every other case's expected lines are unchanged.

| ID | Result |
|---|---|
| A1 | killed, exit 2 |
| A2 | killed, exit 2 |
| A3 | killed, exit 2 |
| A3P | killed, exit 2 |
| A4 | killed, exit 2 |
| A5 | killed, exit 2 |
| FPA4 | killed, exit 2 |
| D | killed, exit 2 |
| BR1 | killed, exit 2 |
| BR2 | killed, exit 2 |
| L | killed, exit 2 |
| WM1 | killed, exit 2 |
| WM2 | killed, exit 2 |
| WM3 | killed, exit 2 |
| WM4 | killed, exit 2 |
| WM5 | killed, exit 2 |
| WM6 | killed, exit 2 |
| CVF1 | killed, exit 2 |
| CVF2 | killed, exit 2 |
| CVF3 | killed, exit 2 |
| CVF4 | killed, exit 2 |
| CVF5 | killed, exit 2 |
| CVF6 | killed, exit 2 |
| CVF7 | killed, exit 2 |
| CVF8 | killed, exit 2 |
| CVF9 | killed, exit 2 |
| CLEAN | as expected, exit 0 |

The new ones:

| ID | Change | Killed by |
|---|---|---|
| R0 | every macro rule off | test-collect-safe: the ten new cases, `wrapper-template` and `wrapper-defined-again` (the red run) |
| MR1 | `macro-nested` never named | test-collect-safe: `macro-nested` |
| MR2 | `macro-local` never named | test-collect-safe: `macro-local`, `wrapper-template` |
| MR3 | `macro-unlisted` never named | test-collect-safe: `macro-swap-entry`, `macro-rebind`, `macro-unlisted` |
| MR4 | a row's file never compared | test-collect-safe: `macro-elsewhere`, `wrapper-defined-again` |
| MR5 | a plain macro may hold a binding name | test-collect-safe: `plain-binds` |
| MR6 | a plain macro may hold a take-apart name | test-collect-safe: `plain-takes-apart` |
| MR7 | a plain macro's patterns never read | test-collect-safe: `plain-pattern` |
| MR8 | a flat pattern need not start with `_` | test-collect-safe: `plain-pattern`, `named` |
| MR9 | identifier-syntax's set! clause never read | test-collect-safe: `plain-pattern`, `setter` |
| MR10 | a binder's pattern may take an operand apart | test-collect-safe: `binder-takes-apart` |
| MR11 | an `any` row held as plain | test-collect-safe: `legal`, and every case whose `any` macro holds a binding |
| MR12 | `load-step`'s row made `any` | test-collect-safe: the hand-written table test |
| MR13 | `require-supported-chez`'s row removed | test-collect-safe: `macro-unlisted` in src/, both table tests |
| SP1 | `load-step` given a clause taking a use apart | test-collect-safe: `plain-macro-pattern` in `load-state.sls` |
| SP2 | `require-supported-chez` given a `syntax-case` | test-collect-safe: `plain-macro-takes-apart` in `require-threaded.sls` |
| SB1 | `bind-required`'s library operand taken apart | test-collect-safe: `wrapper-unreadable`, its pattern taking an operand apart |


##### A5. A5, now killed

**Guards:** a macro on no row is named, whatever it does with what it is handed.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,11 @@
   ;; or a curl_off_t: the CURLcode.
+  (define-syntax swap-entry
+    (syntax-rules ()
+      ((_ (w e . rest)) (w "curl_easy_setopt" . rest))))
+
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (swap-entry (bind-required "memcpy" (uptr int long) int info))))
 
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((macro-unlisted "src/curl/private/native.sls" swap-entry))
FAIL the scan of src/ finds every macro known-macros names, each defined once at a library body's top level in its row's file, and no other
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

##### FPA4. FPA4, now killed

**Guards:** the same, for a syntax-case that takes its own template apart.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,12 @@
   ;; or a curl_off_t: the CURLcode.
+  (define-syntax rebind
+    (lambda (x)
+      (syntax-case #'(foreign-procedure "memcpy" (uptr int long) int) ()
+        ((fp e . rest) #'(fp "curl_easy_setopt" . rest)))))
+
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (rebind)))
 
```

**Result:** killed, exit 2, 18 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((macro-unlisted "src/curl/private/native.sls" rebind))
FAIL the scan of src/ finds every macro known-macros names, each defined once at a library body's top level in its row's file, and no other
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

##### R0. every macro rule off (the red run)

**Guards:** each new rule's case, and the two cases whose answers the rules change.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -946,8 +946,3 @@
       ;; named; so is every let-syntax and letrec-syntax.
-      (define (placement! form)
-        (case (car form)
-          ((define-syntax)
-           (unless (eq? form top-form) (violation! 'macro-nested path (abbreviated form))))
-          ((let-syntax letrec-syntax) (violation! 'macro-local path (abbreviated form)))
-          (else #f)))
+      (define (placement! form) #f)
 
```

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -955,9 +955,3 @@
           (emit! (list 'macro name rel))
-          (cond
-            ((not row) (violation! 'macro-unlisted path name))
-            (else
-             (unless (string=? (caddr row) rel)
-               (violation! 'macro-elsewhere path name (string-append root "/" (caddr row))))
-             (unless (memq (cadr row) '(binder any))
-               (plain! form name))))))
+          #t))
 
```

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -624,3 +624,3 @@
             ((and (eq? (car reading) 'at) (= i (cadr reading))) (loop (cdr rest) (+ i 1)))
-            ((or (pair? (car rest)) (vector? (car rest))) #t)
+            ((or (pair? (car rest)) (vector? (car rest))) #f)
             (else (loop (cdr rest) (+ i 1))))))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL wrapper-template: a known wrapper's name in a macro, a head with a literal entry too: syntax-rules templates, one handing the use to a pattern variable, a syntax-case taking its template apart, with-syntax, quasisyntax and syntax in procedures, transformers by define-syntax and let-syntax, identifier-syntax's set! [cut: 124 more characters]
  expected: (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 1616 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 1458 more characters]
FAIL macro-swap-entry: A5: a macro on no row takes apart a use it is handed, which the reader reads as memcpy, and rebuilds it with curl_easy_setopt
  expected: (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" bind-variadic ()) ("memcpy" () "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" bind-required ())) ((macro-unlisted "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" swap-entry))))
  actual:   (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" bind-variadic ()) ("memcpy" () "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" bind-required ())) ()))
FAIL macro-rebind: FPA4: a syntax-case on no row takes apart its own template, a foreign-procedure form the reader reads as memcpy, and binds curl_easy_setopt
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/macro-rebind/curl/n.sls" foreign-procedure ()) ("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/macro-rebind/curl/n.sls" bind-variadic ())) ((macro-unlisted "tests/fixtures/conventions/macro-rebind/curl/n.sls" rebind))))
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/macro-rebind/curl/n.sls" foreign-procedure ()) ("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/macro-rebind/curl/n.sls" bind-variadic ())) ()))
FAIL macro-unlisted: a macro at a library body's top level that names no row, though it holds nothing a plain macro may not; one beside it that does
  expected: (returned (() ((macro-unlisted "tests/fixtures/conventions/macro-unlisted/curl/u.sls" step))))
  actual:   (returned (() ()))
FAIL macro-nested: define-syntax anywhere but a library body's top level: in a procedure's body, in a begin, and in a listed macro's template
  expected: (returned (() ((macro-nested "tests/fixtures/conventions/macro-nested/curl/n.sls" "(define-syntax inner (syntax-rules () ((_) 0)))") (macro-nested "tests/fixtures/conventions/macro-nested/curl/n.sls" "(define-syntax in-begin (syntax-rules () ((_) 0)))") (macro-nested "tests/fixtures/conventions/macro-nested [cut: 65 more characters]
  actual:   (returned (() ()))
FAIL macro-local: local macros, by let-syntax and letrec-syntax
  expected: (returned (() ((macro-local "tests/fixtures/conventions/macro-local/curl/l.sls" "(let-syntax ((m (syntax-rules () ((_) 0)))) (m))") (macro-local "tests/fixtures/conventions/macro-local/curl/l.sls" "(letrec-syntax ((m (syntax-rules () ((_) 0)))) (m))"))))
  actual:   (returned (() ()))
FAIL macro-elsewhere: a listed macro defined in a file other than its row's
  expected: (returned (() ((macro-elsewhere "tests/fixtures/conventions/macro-elsewhere/curl/b.sls" step "tests/fixtures/conventions/macro-elsewhere/curl/a.sls"))))
  actual:   (returned (() ()))
FAIL plain-binds: plain macros that would build a binding: a foreign-procedure form, a foreign-callable, a known wrapper's use
  expected: (returned ((("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/plain-binds/curl/p.sls" foreign-procedure ())) ((plain-macro-binds "tests/fixtures/conventions/plain-binds/curl/p.sls" bind-poll foreign-procedure) (plain-macro-binds "tests/fixtures/conventions/plain-binds/curl/p.sls" on-callable f [cut: 346 more characters]
  actual:   (returned ((("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/plain-binds/curl/p.sls" foreign-procedure ())) ((callable-not-defined "tests/fixtures/conventions/plain-binds/curl/p.sls" "(foreign-callable (lambda (n) n) (int) int)") (stray "tests/fixtures/conventions/plain-binds/curl/p.sls" "(bi [cut: 47 more characters]
FAIL plain-takes-apart: plain macros that can take their operands apart: syntax-case, with-syntax, syntax->datum and datum->syntax
  expected: (returned (() ((plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-case syntax-case) (plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-with with-syntax) (plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by [cut: 131 more characters]
  actual:   (returned (() ()))
FAIL plain-pattern: plain macros whose patterns take an operand apart: nested, improper, a vector, not headed by _, and identifier-syntax's set! clause; two with identifiers only, an ellipsis among them, pass
  expected: (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail "(_ a . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" vec "(_ #(a b))") (pla [cut: 193 more characters]
  actual:   (returned (() ()))
FAIL binder-takes-apart: a binder whose pattern takes its library operand apart, so its template could rebuild a use it is handed: unreadable, and none of its uses read
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/binder-takes-apart/curl/b.sls" bind-required "its pattern takes an operand apart: an element other than its parameter list is a list or a vector"))))
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/binder-takes-apart/curl/b.sls" bind-required ())) ()))
FAIL wrapper-defined-again: the known wrapper defined in two files: the second stands where its row does not say, and no use is read against either
  expected: (returned (() ((macro-elsewhere "tests/fixtures/conventions/wrapper-defined-again/curl/b.sls" bind-required "tests/fixtures/conventions/wrapper-defined-again/curl/a.sls") (wrapper-defined-again "tests/fixtures/conventions/wrapper-defined-again/curl/b.sls" bind-required))))
  actual:   (returned (() ((wrapper-defined-again "tests/fixtures/conventions/wrapper-defined-again/curl/b.sls" bind-required))))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR1. macro-nested never named

**Guards:** a define-syntax below a library body's top level is named.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -949,3 +949,3 @@
           ((define-syntax)
-           (unless (eq? form top-form) (violation! 'macro-nested path (abbreviated form))))
+           #f)
           ((let-syntax letrec-syntax) (violation! 'macro-local path (abbreviated form)))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL macro-nested: define-syntax anywhere but a library body's top level: in a procedure's body, in a begin, and in a listed macro's template
  expected: (returned (() ((macro-nested "tests/fixtures/conventions/macro-nested/curl/n.sls" "(define-syntax inner (syntax-rules () ((_) 0)))") (macro-nested "tests/fixtures/conventions/macro-nested/curl/n.sls" "(define-syntax in-begin (syntax-rules () ((_) 0)))") (macro-nested "tests/fixtures/conventions/macro-nested [cut: 65 more characters]
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR2. macro-local never named

**Guards:** let-syntax and letrec-syntax are named.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -950,3 +950,3 @@
            (unless (eq? form top-form) (violation! 'macro-nested path (abbreviated form))))
-          ((let-syntax letrec-syntax) (violation! 'macro-local path (abbreviated form)))
+          ((let-syntax letrec-syntax) #f)
           (else #f)))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL wrapper-template: a known wrapper's name in a macro, a head with a literal entry too: syntax-rules templates, one handing the use to a pattern variable, a syntax-case taking its template apart, with-syntax, quasisyntax and syntax in procedures, transformers by define-syntax and let-syntax, identifier-syntax's set! [cut: 124 more characters]
  expected: (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 1616 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 1458 more characters]
FAIL macro-local: local macros, by let-syntax and letrec-syntax
  expected: (returned (() ((macro-local "tests/fixtures/conventions/macro-local/curl/l.sls" "(let-syntax ((m (syntax-rules () ((_) 0)))) (m))") (macro-local "tests/fixtures/conventions/macro-local/curl/l.sls" "(letrec-syntax ((m (syntax-rules () ((_) 0)))) (m))"))))
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR3. macro-unlisted never named

**Guards:** a top-level define-syntax must name a row: A5 and FPA4 among them.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -961,3 +961,3 @@
           (cond
-            ((not row) (violation! 'macro-unlisted path name))
+            ((not row) #f)
             (else
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL macro-swap-entry: A5: a macro on no row takes apart a use it is handed, which the reader reads as memcpy, and rebuilds it with curl_easy_setopt
  expected: (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" bind-variadic ()) ("memcpy" () "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" bind-required ())) ((macro-unlisted "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" swap-entry))))
  actual:   (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" bind-variadic ()) ("memcpy" () "tests/fixtures/conventions/macro-swap-entry/curl/n.sls" bind-required ())) ()))
FAIL macro-rebind: FPA4: a syntax-case on no row takes apart its own template, a foreign-procedure form the reader reads as memcpy, and binds curl_easy_setopt
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/macro-rebind/curl/n.sls" foreign-procedure ()) ("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/macro-rebind/curl/n.sls" bind-variadic ())) ((macro-unlisted "tests/fixtures/conventions/macro-rebind/curl/n.sls" rebind))))
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/macro-rebind/curl/n.sls" foreign-procedure ()) ("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/macro-rebind/curl/n.sls" bind-variadic ())) ()))
FAIL macro-unlisted: a macro at a library body's top level that names no row, though it holds nothing a plain macro may not; one beside it that does
  expected: (returned (() ((macro-unlisted "tests/fixtures/conventions/macro-unlisted/curl/u.sls" step))))
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR4. a row's file never compared

**Guards:** a listed macro stands in its row's file.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -963,3 +963,3 @@
             (else
-             (unless (string=? (caddr row) rel)
+             (unless #t
                (violation! 'macro-elsewhere path name (string-append root "/" (caddr row))))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL macro-elsewhere: a listed macro defined in a file other than its row's
  expected: (returned (() ((macro-elsewhere "tests/fixtures/conventions/macro-elsewhere/curl/b.sls" step "tests/fixtures/conventions/macro-elsewhere/curl/a.sls"))))
  actual:   (returned (() ()))
FAIL wrapper-defined-again: the known wrapper defined in two files: the second stands where its row does not say, and no use is read against either
  expected: (returned (() ((macro-elsewhere "tests/fixtures/conventions/wrapper-defined-again/curl/b.sls" bind-required "tests/fixtures/conventions/wrapper-defined-again/curl/a.sls") (wrapper-defined-again "tests/fixtures/conventions/wrapper-defined-again/curl/b.sls" bind-required))))
  actual:   (returned (() ((wrapper-defined-again "tests/fixtures/conventions/wrapper-defined-again/curl/b.sls" bind-required))))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR5. a plain macro may hold a binding name

**Guards:** a plain macro builds no binding.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -974,3 +974,3 @@
         (let ((symbols (distinct (symbols-in form))))
-          (for-each (lambda (s) (when (name? s) (violation! 'plain-macro-binds path name s)))
+          (for-each (lambda (s) (when #f (violation! 'plain-macro-binds path name s)))
                     symbols)
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-binds: plain macros that would build a binding: a foreign-procedure form, a foreign-callable, a known wrapper's use
  expected: (returned ((("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/plain-binds/curl/p.sls" foreign-procedure ())) ((plain-macro-binds "tests/fixtures/conventions/plain-binds/curl/p.sls" bind-poll foreign-procedure) (plain-macro-binds "tests/fixtures/conventions/plain-binds/curl/p.sls" on-callable f [cut: 346 more characters]
  actual:   (returned ((("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/plain-binds/curl/p.sls" foreign-procedure ())) ((callable-not-defined "tests/fixtures/conventions/plain-binds/curl/p.sls" "(foreign-callable (lambda (n) n) (int) int)") (stray "tests/fixtures/conventions/plain-binds/curl/p.sls" "(bi [cut: 47 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR6. a plain macro may hold a take-apart name

**Guards:** a plain macro uses none of syntax-case, with-syntax, syntax->datum and datum->syntax.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -977,3 +977,3 @@
           (for-each (lambda (s)
-                      (when (memq s take-apart-names) (violation! 'plain-macro-takes-apart path name s)))
+                      (when #f (violation! 'plain-macro-takes-apart path name s)))
                     symbols)
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-takes-apart: plain macros that can take their operands apart: syntax-case, with-syntax, syntax->datum and datum->syntax
  expected: (returned (() ((plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-case syntax-case) (plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-with with-syntax) (plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by [cut: 131 more characters]
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR7. a plain macro's patterns never read

**Guards:** a plain macro's patterns are identifiers only.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -980,3 +980,3 @@
           (for-each (lambda (pattern) (violation! 'plain-macro-pattern path name (abbreviated pattern)))
-                    (unflat-patterns form))))
+                    '())))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-pattern: plain macros whose patterns take an operand apart: nested, improper, a vector, not headed by _, and identifier-syntax's set! clause; two with identifiers only, an ellipsis among them, pass
  expected: (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail "(_ a . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" vec "(_ #(a b))") (pla [cut: 193 more characters]
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR8. a flat pattern need not start with _

**Guards:** a syntax-rules pattern is (_ id ...): `named`'s `(named a)` must still be named.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -826,3 +826,3 @@
          (if (eq? head 'syntax-rules)
-             (and (pair? pattern) (eq? (car pattern) '_) (for-all symbol? (cdr pattern)))
+             (and (pair? pattern) (for-all symbol? (cdr pattern)))
              (and (= (length pattern) 3)
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-pattern: plain macros whose patterns take an operand apart: nested, improper, a vector, not headed by _, and identifier-syntax's set! clause; two with identifiers only, an ellipsis among them, pass
  expected: (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail "(_ a . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" vec "(_ #(a b))") (pla [cut: 193 more characters]
  actual:   (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail "(_ a . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" vec "(_ #(a b))") (pla [cut: 99 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR9. identifier-syntax's set! clause never read

**Guards:** identifier-syntax's set! clause is (set! id id): `setter` must still be named.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -847,3 +847,3 @@
                                  (clause-patterns form))))
-               '() (forms-headed '(syntax-rules identifier-syntax) x)))
+               '() (forms-headed '(syntax-rules) x)))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-pattern: plain macros whose patterns take an operand apart: nested, improper, a vector, not headed by _, and identifier-syntax's set! clause; two with identifiers only, an ellipsis among them, pass
  expected: (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail "(_ a . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" vec "(_ #(a b))") (pla [cut: 193 more characters]
  actual:   (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail "(_ a . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" vec "(_ #(a b))") (pla [cut: 92 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR10. a binder's pattern may take an operand apart

**Guards:** a binder takes no operand apart beyond its parameter list.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -624,3 +624,3 @@
             ((and (eq? (car reading) 'at) (= i (cadr reading))) (loop (cdr rest) (+ i 1)))
-            ((or (pair? (car rest)) (vector? (car rest))) #t)
+            ((or (pair? (car rest)) (vector? (car rest))) #f)
             (else (loop (cdr rest) (+ i 1))))))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL binder-takes-apart: a binder whose pattern takes its library operand apart, so its template could rebuild a use it is handed: unreadable, and none of its uses read
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/binder-takes-apart/curl/b.sls" bind-required "its pattern takes an operand apart: an element other than its parameter list is a list or a vector"))))
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/binder-takes-apart/curl/b.sls" bind-required ())) ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR11. an any row held as plain

**Guards:** an `any` row is held to neither kind's rules, as fixtures need.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -965,3 +965,3 @@
                (violation! 'macro-elsewhere path name (string-append root "/" (caddr row))))
-             (unless (memq (cadr row) '(binder any))
+             (unless (memq (cadr row) '(binder))
                (plain! form name))))))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL legal: every accounted place: the import, the known wrapper's one definition and its uses in code, a let's initial value and a plain macro's operand among them, two plain macros, direct bindings in two files, two conventions as a set, a template that is no wrapper in a fixture's macro, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required ()) ("curl_global_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required ()) ("curl_easy_cleanup" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required ()) ("curl_easy_perform" (__collect_safe [cut: 659 more characters]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required ()) ("curl_global_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required ()) ("curl_easy_cleanup" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required ()) ("curl_easy_perform" (__collect_safe [cut: 752 more characters]
FAIL stray: references that are no form's head: a define, a let binding, an improper tail, an identifier-syntax
FAIL entry-not-string: an entry that is no string literal outside a known wrapper: a variable, an expression, a pattern variable
FAIL wrapper-aliased: the review's A2: bind-required in identifier-syntax's template, so bind-plain is another name for it
FAIL wrapper-passed: the review's A3: bind-required an argument of a macro that puts it at a head, binding curl_easy_setopt plain and curl_easy_perform with an unmarked u8*
FAIL wrapper-argument: a known wrapper's name as an argument: the other wrapper, under a call, and an improper tail
FAIL wrapper-template: a known wrapper's name in a macro, a head with a literal entry too: syntax-rules templates, one handing the use to a pattern variable, a syntax-case taking its template apart, with-syntax, quasisyntax and syntax in procedures, transformers by define-syntax and let-syntax, identifier-syntax's set! [cut: 124 more characters]
FAIL types-macro-argument: the third review's tree: a type that is a pattern variable, in a macro that is no known wrapper, whose use supplies u8*
FAIL types-pattern-variable: pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, with-syntax, identifier-syntax, a callable's result, and a convention; a wrapper's use in a syntax-case template is stray; a macro whose pattern binds no type stays readable
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR12. load-step's row made any

**Guards:** src/'s table is the four rows written out by hand: none may slip to any.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -284,3 +284,3 @@
       (bind-variadic binder "curl/private/native.sls")
-      (load-step plain "curl/private/load-state.sls")
+      (load-step any "curl/private/load-state.sls")
       (require-supported-chez plain "curl/private/require-threaded.sls")))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL known-macros is src/'s four macros: two binders in native.sls, and load-step and require-supported-chez, plain, each in its own library
  expected: ((bind-required binder "curl/private/native.sls") (bind-variadic binder "curl/private/native.sls") (load-step plain "curl/private/load-state.sls") (require-supported-chez plain "curl/private/require-threaded.sls"))
  actual:   ((bind-required binder "curl/private/native.sls") (bind-variadic binder "curl/private/native.sls") (load-step any "curl/private/load-state.sls") (require-supported-chez plain "curl/private/require-threaded.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MR13. require-supported-chez's row removed

**Guards:** the table equals what src/ defines, both ways.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -284,4 +284,3 @@
       (bind-variadic binder "curl/private/native.sls")
-      (load-step plain "curl/private/load-state.sls")
-      (require-supported-chez plain "curl/private/require-threaded.sls")))
+      (load-step plain "curl/private/load-state.sls")))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((macro-unlisted "src/curl/private/require-threaded.sls" require-supported-chez))
FAIL known-macros is src/'s four macros: two binders in native.sls, and load-step and require-supported-chez, plain, each in its own library
  expected: ((bind-required binder "curl/private/native.sls") (bind-variadic binder "curl/private/native.sls") (load-step plain "curl/private/load-state.sls") (require-supported-chez plain "curl/private/require-threaded.sls"))
  actual:   ((bind-required binder "curl/private/native.sls") (bind-variadic binder "curl/private/native.sls") (load-step plain "curl/private/load-state.sls"))
FAIL the scan of src/ finds every macro known-macros names, each defined once at a library body's top level in its row's file, and no other
  expected: (returned ((bind-required "curl/private/native.sls") (bind-variadic "curl/private/native.sls") (load-step "curl/private/load-state.sls")))
  actual:   (returned ((bind-required "curl/private/native.sls") (bind-variadic "curl/private/native.sls") (load-step "curl/private/load-state.sls") (require-supported-chez "curl/private/require-threaded.sls")))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### SP1. load-step taught to take a use apart

**Guards:** a listed plain macro in src/ is held to a flat pattern. `make test`: only test-collect-safe fails.

**Mutation:** In `src/curl/private/load-state.sls`:

```diff
@@ -64,2 +64,3 @@
     (syntax-rules ()
+      ((_ (w "memcpy" . rest)) (w "curl_easy_setopt" . rest))
       ((_ expr)
```

**Result:** killed, exit 2, 17 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((plain-macro-pattern "src/curl/private/load-state.sls" load-step "(_ (w \"memcpy\" . rest))"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

##### SP2. require-supported-chez given a syntax-case

**Guards:** a listed plain transformer in src/ takes nothing apart. `make test`: only test-collect-safe fails.

**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
@@ -89,3 +89,3 @@
              x))
-           (else #'(define supported-chez-checked #t)))))))
+           (else (syntax-case x () ((_) #'(define supported-chez-checked #t)))))))))
 
```

**Result:** killed, exit 2, 17 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((plain-macro-takes-apart "src/curl/private/require-threaded.sls" require-supported-chez syntax-case))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

##### SB1. bind-required's library operand taken apart

**Guards:** src/'s binder is held to the binder rule. Run on test-collect-safe alone: native no longer expands.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -143,5 +143,5 @@
     (syntax-rules ()
-      ((_ entry (arg ...) result library)
+      ((_ entry (arg ...) result (w e . rest))
        (begin
-         (required-entry entry library)
+         (required-entry entry e)
          (foreign-procedure entry (arg ...) result)))))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL the scan of src/ finds the six entries loading binds, each bound once, plain
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((wrapper-unreadable "src/curl/private/native.sls" bind-required "its pattern takes an operand apart: an element other than its parameter list is a list or a vector"))
FAIL the scan of src/ finds two crossings, a string each: curl_easy_option_by_name's name and curl_easy_header's
FAIL known-wrappers is exactly the wrappers src/ defines
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### Clean rerun

On the working tree, in the container, after the last edit:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (15 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: ran 15, passed 15, failed 0, hung 0
check-variadic: all 19 steps ok, on ta6le
test-memory: ran 2, passed 2, failed 0, hung 0
check-test-fails: make test failed, as it must, in all 10 cases
```

`make test-memory` ran with `MEMORY_SUITES="tests/test-variadic.sps tests/test-collect-safe.sps"`.
No Chez or Valgrind process was left behind. Apple arm64 is still pending, as above.

#### A plain transformer's input

A6 survived the macro table: `require-supported-chez`'s kind of macro, a plain transformer
written as a procedure, could hand its input to a procedure another library exports, which took
it apart and rebuilt it. It is closed now by an allowlist of where that input may go, and probing
what was left found four more routes, closed by two rules each as small.

- **Decided.** A procedural plain transformer is exactly `(lambda (ID) BODY ...)`, else
  `(plain-macro-transformer FILE NAME FORM)`. In BODY, ID stands only as the last argument of a
  `syntax-violation` call, else `(plain-macro-input FILE NAME FORM)`: passed on, bound to another
  name, quoted, or shadowed.
- **Tail position** (closes A9 and A11). `syntax-violation` stands in BODY only at the head of a
  call in tail position, through if's branches, cond's and case's clauses, and the last form of
  when, unless, begin, and, or and the let forms, else `(plain-macro-raise FILE NAME FORM)`. The
  condition the call raises holds the input: a handler the transformer set up, by `guard` or
  `with-exception-handler`, could take it back with `syntax-violation-form` (A9). And a
  binding of the name, by let or an internal define, makes the call a procedure of the
  transformer's own (A11).
- **Imports** (closes A10 and A12, and A6 a second way). The library a procedural plain macro
  stands in imports only whole `(rnrs ...)` libraries but `(rnrs eval)`, and
  `(only (chezscheme) name ...)`, with `(rnrs)` or `(rnrs syntax-case)` among them, else
  `(plain-macro-import FILE NAME)`. Then Chez refuses any other `syntax-violation` in it (A10:
  another library's, with `(except (rnrs) syntax-violation)`). And no procedure of another
  library is in reach, to take the input apart (A6) or to build a binding from strings with
  `datum->syntax` while the input goes nowhere (A12).

`require-supported-chez` passes all three as written: its `x` stands only as the last argument of
its two `syntax-violation` calls, both tail calls of a `cond`, and `require-threaded.sls` imports
`(rnrs)` and `(only (chezscheme) ...)`. src/ is unchanged.

`test-collect-safe` has ten new cases: the six decided, `plain-input-elsewhere` (A6),
`plain-input-bound` (with a message, a quote and quoted data besides), `plain-input-local`,
`plain-transformer-rest`, `plain-transformer-case-lambda` and `plain-input-shadowed`; and
`plain-raise-guarded` (A9), `plain-raise-shadowed` (A11), `plain-raise-imported` (A10) and
`plain-built-elsewhere` (A12). `plain-takes-apart`'s transformers now also name the input they
hand to `syntax-case` and `syntax->datum`. 102 tests.

##### Measurements

Each probe ran in the container. Its macro was handed `(foreign-procedure "labs" (int) int)`,
which the reader reads as `labs`, and its procedure swapped in "abs". A route works when Chez
answers `Exception in foreign-procedure: no entry for "abs"`: it bound the entry the procedure
chose.

| Route | The transformer | Chez | The reader with rule 2 alone |
|---|---|---|---|
| A9 | `(guard (c (#t (rebuild (syntax-violation-form c)))) (syntax-violation 'm "never" x))` | no entry for "abs" | admitted |
| A10 | `(syntax-violation 'm "never" x)`, its library importing `(except (rnrs) syntax-violation)` and another library's | no entry for "abs" | admitted |
| A11 | `(let ((syntax-violation (lambda (who message form) (rebuild form)))) (syntax-violation 'm "never" x))` | no entry for "abs" | admitted |
| A12 | `(built)`, from another library, which builds `(foreign-procedure "abs" (int) int)` from strings with `datum->syntax` | no entry for "abs" | admitted |
| A13 | `` #`(#,(string->symbol "foreign-procedure") "abs" (int) int) `` | refused: `encountered raw symbol foreign-procedure in output of macro` | (needs no rule) |

With the rules, the reader names A9 and A11 by `plain-macro-raise` and A10 by `plain-macro-import`;
A12's fixture is named by `plain-macro-import`. And with `(rnrs)` imported whole, Chez refused a
second `syntax-violation`, from another library and from a body definition alike: `Exception:
multiple definitions for syntax-violation in body`. Renaming the other library's,
`(rename (h) (syntax-violation sv))`, loaded, and leaves `(rnrs)`'s in place.

##### Red run

The rules were written before their cases, so the red run is the reader without them, in a copy
(R1): `plain!` reading no procedural transformer. Every new case failed, and so did
`plain-takes-apart`, whose answer they change. `legal` passed, and so did src/.

```
FAIL plain-takes-apart: plain macros that can take their operands apart: syntax-case, with-syntax, syntax->datum and datum->syntax, two of them handed the input too
FAIL plain-input-elsewhere: A6: a plain transformer hands its input to a procedure another library exports, which takes it apart and rebuilds it; the reader reads memcpy
FAIL plain-input-bound: plain transformers whose input goes elsewhere than as syntax-violation's last argument: bound to another name, by let, define and set!; the message; quoted; in quoted data
FAIL plain-input-local: plain transformers that hand their input to a procedure of the same library: the library's own, and the transformer's
FAIL plain-transformer-rest: plain transformers whose parameters are not one identifier: a rest list, an identifier and a rest, two identifiers
FAIL plain-transformer-case-lambda: plain transformers that are procedures but no lambda of one identifier: a case-lambda, and make-variable-transformer's
FAIL plain-input-shadowed: plain transformers that shadow their input, so syntax-violation is handed something else: by let, an inner lambda, whose call is then no tail call, an internal define
FAIL plain-raise-guarded: A9: plain transformers whose input goes only to syntax-violation, with a handler around the call that takes it back from the condition: by guard, and by with-exception-handler
FAIL plain-raise-shadowed: A11: plain transformers that rebind syntax-violation, by let and by an internal define
FAIL plain-raise-imported: A10: a plain transformer in a library that takes syntax-violation from another, with (rnrs)'s excepted
FAIL plain-built-elsewhere: A12: a plain transformer whose input goes nowhere, and whose output a procedure another library exports builds from strings
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### Mutations

57 cases ran on the final snapshot, which `diff -rq --no-dereference` showed identical to the
working tree: the macro table's 44 again, and 13 new ones. All 56 mutations were killed, each
with every expected line present, and `CLEAN` passed.

The 44, rerun. SP2's added `syntax-case` is handed `x`, so its violations now end with a
`plain-macro-input` too. Every other case's expected lines are unchanged.

| ID | Result |
|---|---|
| A1 | killed, exit 2 |
| A2 | killed, exit 2 |
| A3 | killed, exit 2 |
| A3P | killed, exit 2 |
| A4 | killed, exit 2 |
| A5 | killed, exit 2 |
| FPA4 | killed, exit 2 |
| D | killed, exit 2 |
| BR1 | killed, exit 2 |
| BR2 | killed, exit 2 |
| L | killed, exit 2 |
| WM1 | killed, exit 2 |
| WM2 | killed, exit 2 |
| WM3 | killed, exit 2 |
| WM4 | killed, exit 2 |
| WM5 | killed, exit 2 |
| WM6 | killed, exit 2 |
| CVF1 | killed, exit 2 |
| CVF2 | killed, exit 2 |
| CVF3 | killed, exit 2 |
| CVF4 | killed, exit 2 |
| CVF5 | killed, exit 2 |
| CVF6 | killed, exit 2 |
| CVF7 | killed, exit 2 |
| CVF8 | killed, exit 2 |
| CVF9 | killed, exit 2 |
| CLEAN | as expected, exit 0 |
| R0 | killed, exit 2 |
| MR1 | killed, exit 2 |
| MR2 | killed, exit 2 |
| MR3 | killed, exit 2 |
| MR4 | killed, exit 2 |
| MR5 | killed, exit 2 |
| MR6 | killed, exit 2 |
| MR7 | killed, exit 2 |
| MR8 | killed, exit 2 |
| MR9 | killed, exit 2 |
| MR10 | killed, exit 2 |
| MR11 | killed, exit 2 |
| MR12 | killed, exit 2 |
| MR13 | killed, exit 2 |
| SP1 | killed, exit 2 |
| SP2 | killed, exit 2 |
| SB1 | killed, exit 2 |

The new ones:

| ID | Change | Killed by |
|---|---|---|
| R1 | no procedural transformer read | test-collect-safe: the ten new cases and `plain-takes-apart` (the red run) |
| MI1 | the input's places never read | test-collect-safe: `plain-input-elsewhere`, `-bound`, `-local`, `-shadowed`, `plain-takes-apart` |
| MI2 | a transformer's shape never named | test-collect-safe: `plain-transformer-rest`, `plain-transformer-case-lambda` |
| MI3 | the input allowed as any argument of `syntax-violation` | test-collect-safe: `plain-input-bound`, its `by-message` |
| MI4 | quoted data read as code | test-collect-safe: `plain-input-bound`, its `by-data` |
| MI5 | `syntax-violation`'s places never read | test-collect-safe: `plain-input-bound`, `plain-input-shadowed`, `plain-raise-guarded`, `plain-raise-shadowed` |
| MI6 | `guard`'s body taken for a tail position | test-collect-safe: `plain-raise-guarded` |
| MI7 | the library's imports never read | test-collect-safe: `plain-input-elsewhere`, `plain-raise-guarded`, `plain-raise-imported`, `plain-built-elsewhere` |
| MI8 | any import counted as `(rnrs ...)` | test-collect-safe: `plain-built-elsewhere` |
| MI9 | `cond`'s clauses no tail position | test-collect-safe: src/, `require-supported-chez`'s two calls |
| SA6 | `require-supported-chez` hands `x` to a procedure | test-collect-safe: `plain-macro-input` in `require-threaded.sls` |
| SA9 | `require-supported-chez` guards a raise of its input | test-collect-safe: `plain-macro-raise` in `require-threaded.sls`; `make test`: nothing else fails |
| SA10 | `require-threaded.sls` imports `(except (rnrs) exit)` | test-collect-safe: `plain-macro-import`; `make test`: nothing else fails |


###### R1. no procedural transformer read (the red run)

**Guards:** each new case, and the one whose answer the rules change.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1144,3 +1144,3 @@
                     (unflat-patterns form))
-          (unless (pattern-transformer? rhs)
+          (unless #t
             (let ((id (lambda-transformer-input rhs)))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-takes-apart: plain macros that can take their operands apart: syntax-case, with-syntax, syntax->datum and datum->syntax, two of them handed the input too
  expected: (returned (() ((plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-case syntax-case) (plain-macro-input "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-case "(syntax-case x () ((_ e) (syntax e)))") (plain-macro-takes-apart "tests/fixtures/conventions/plain-take [cut: 496 more characters]
  actual:   (returned (() ((plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-case syntax-case) (plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-with with-syntax) (plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by [cut: 131 more characters]
FAIL plain-input-elsewhere: A6: a plain transformer hands its input to a procedure another library exports, which takes it apart and rebuilds it; the reader reads memcpy
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" foreign-procedure ())) ((plain-macro-import "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" m) (plain-macro-input "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" m "(rebuild x)"))))
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" foreign-procedure ())) ()))
FAIL plain-input-bound: plain transformers whose input goes elsewhere than as syntax-violation's last argument: bound to another name, by let, define and set!; the message; quoted; in quoted data
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-let "(form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-define "(define form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-set "(set!  [cut: 503 more characters]
  actual:   (returned (() ()))
FAIL plain-input-local: plain transformers that hand their input to a procedure of the same library: the library's own, and the transformer's
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-local/curl/l.sls" by-library "(keep x)") (plain-macro-input "tests/fixtures/conventions/plain-input-local/curl/l.sls" by-body "(hold x)"))))
  actual:   (returned (() ()))
FAIL plain-transformer-rest: plain transformers whose parameters are not one identifier: a rest list, an identifier and a rest, two identifiers
  expected: (returned (() ((plain-macro-transformer "tests/fixtures/conventions/plain-transformer-rest/curl/r.sls" all-rest "(lambda args (syntax-violation (quote all-rest) \"refused\" (car args)))") (plain-macro-transformer "tests/fixtures/conventions/plain-transformer-rest/curl/r.sls" some-rest "(lambda (x . more) (s [cut: 209 more characters]
  actual:   (returned (() ()))
FAIL plain-transformer-case-lambda: plain transformers that are procedures but no lambda of one identifier: a case-lambda, and make-variable-transformer's
  expected: (returned (() ((plain-macro-transformer "tests/fixtures/conventions/plain-transformer-case-lambda/curl/c.sls" by-cases "(case-lambda ((x) (syntax-violation (quote by-cases) \"refused\" x)))") (plain-macro-transformer "tests/fixtures/conventions/plain-transformer-case-lambda/curl/c.sls" by-variable "(make-va [cut: 90 more characters]
  actual:   (returned (() ()))
FAIL plain-input-shadowed: plain transformers that shadow their input, so syntax-violation is handed something else: by let, an inner lambda, whose call is then no tail call, an internal define
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-let "(x 0)") (plain-macro-input "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-lambda "(x)") (plain-macro-raise "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-lambda "(syntax-v [cut: 152 more characters]
  actual:   (returned (() ()))
FAIL plain-raise-guarded: A9: plain transformers whose input goes only to syntax-violation, with a handler around the call that takes it back from the condition: by guard, and by with-exception-handler
  expected: (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard) (plain-macro-raise "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard "(syntax-violation (quote by-guard) \"never\" x)") (plain-macro-import "tests/fixtures/conventions/plain-raise-guar [cut: 173 more characters]
  actual:   (returned (() ()))
FAIL plain-raise-shadowed: A11: plain transformers that rebind syntax-violation, by let and by an internal define
  expected: (returned (() ((plain-macro-raise "tests/fixtures/conventions/plain-raise-shadowed/curl/s.sls" by-let "(syntax-violation (lambda (who message form) form))") (plain-macro-raise "tests/fixtures/conventions/plain-raise-shadowed/curl/s.sls" by-define "(syntax-violation who message form)"))))
  actual:   (returned (() ()))
FAIL plain-raise-imported: A10: a plain transformer in a library that takes syntax-violation from another, with (rnrs)'s excepted
  expected: (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-raise-imported/curl/i.sls" m))))
  actual:   (returned (() ()))
FAIL plain-built-elsewhere: A12: a plain transformer whose input goes nowhere, and whose output a procedure another library exports builds from strings
  expected: (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-built-elsewhere/curl/m.sls" m))))
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI1. the input's places never read

**Guards:** the input goes nowhere but to syntax-violation.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1154,3 +1154,3 @@
                               (fold-left (lambda (found form)
-                                           (append found (if (eq? form id) (list rhs) (input-leaks id form))))
+                                           (append found '()))
                                          '() body))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-takes-apart: plain macros that can take their operands apart: syntax-case, with-syntax, syntax->datum and datum->syntax, two of them handed the input too
  expected: (returned (() ((plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-case syntax-case) (plain-macro-input "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-case "(syntax-case x () ((_ e) (syntax e)))") (plain-macro-takes-apart "tests/fixtures/conventions/plain-take [cut: 496 more characters]
  actual:   (returned (() ((plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-case syntax-case) (plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by-with with-syntax) (plain-macro-takes-apart "tests/fixtures/conventions/plain-takes-apart/curl/t.sls" by [cut: 131 more characters]
FAIL plain-input-elsewhere: A6: a plain transformer hands its input to a procedure another library exports, which takes it apart and rebuilds it; the reader reads memcpy
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" foreign-procedure ())) ((plain-macro-import "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" m) (plain-macro-input "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" m "(rebuild x)"))))
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" foreign-procedure ())) ((plain-macro-import "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" m))))
FAIL plain-input-bound: plain transformers whose input goes elsewhere than as syntax-violation's last argument: bound to another name, by let, define and set!; the message; quoted; in quoted data
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-let "(form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-define "(define form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-set "(set!  [cut: 503 more characters]
  actual:   (returned (() ((plain-macro-raise "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-data "(syntax-violation by-data \"refused\" x)"))))
FAIL plain-input-local: plain transformers that hand their input to a procedure of the same library: the library's own, and the transformer's
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-local/curl/l.sls" by-library "(keep x)") (plain-macro-input "tests/fixtures/conventions/plain-input-local/curl/l.sls" by-body "(hold x)"))))
  actual:   (returned (() ()))
FAIL plain-input-shadowed: plain transformers that shadow their input, so syntax-violation is handed something else: by let, an inner lambda, whose call is then no tail call, an internal define
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-let "(x 0)") (plain-macro-input "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-lambda "(x)") (plain-macro-raise "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-lambda "(syntax-v [cut: 152 more characters]
  actual:   (returned (() ((plain-macro-raise "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-lambda "(syntax-violation (quote by-lambda) \"refused\" x)"))))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI2. a transformer's shape never named

**Guards:** a procedural plain transformer is exactly (lambda (ID) BODY ...).

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1147,3 +1147,3 @@
               (if (not id)
-                  (violation! 'plain-macro-transformer path name (abbreviated rhs))
+                  #f
                   (let* ((body (cddr rhs))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-transformer-rest: plain transformers whose parameters are not one identifier: a rest list, an identifier and a rest, two identifiers
  expected: (returned (() ((plain-macro-transformer "tests/fixtures/conventions/plain-transformer-rest/curl/r.sls" all-rest "(lambda args (syntax-violation (quote all-rest) \"refused\" (car args)))") (plain-macro-transformer "tests/fixtures/conventions/plain-transformer-rest/curl/r.sls" some-rest "(lambda (x . more) (s [cut: 209 more characters]
  actual:   (returned (() ()))
FAIL plain-transformer-case-lambda: plain transformers that are procedures but no lambda of one identifier: a case-lambda, and make-variable-transformer's
  expected: (returned (() ((plain-macro-transformer "tests/fixtures/conventions/plain-transformer-case-lambda/curl/c.sls" by-cases "(case-lambda ((x) (syntax-violation (quote by-cases) \"refused\" x)))") (plain-macro-transformer "tests/fixtures/conventions/plain-transformer-case-lambda/curl/c.sls" by-variable "(make-va [cut: 90 more characters]
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI3. the input allowed as any argument of syntax-violation

**Guards:** the input is syntax-violation's last argument, never its message.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -913,3 +913,3 @@
                                   (cond ((not (eq? (car rest) id)) (walk (car rest) data?))
-                                        ((and reported? (null? (cdr rest)) (not (eq? rest x))) '())
+                                        ((and reported? (not (eq? rest x))) '())
                                         (else (list x))))))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-input-bound: plain transformers whose input goes elsewhere than as syntax-violation's last argument: bound to another name, by let, define and set!; the message; quoted; in quoted data
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-let "(form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-define "(define form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-set "(set!  [cut: 503 more characters]
  actual:   (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-let "(form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-define "(define form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-set "(set!  [cut: 369 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI4. quoted data read as code

**Guards:** a quoted syntax-violation form is data: its input there is named.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -906,3 +906,3 @@
         ((pair? x)
-         (let* ((data? (or data? (and (memq (car x) '(quote quasiquote syntax quasisyntax)) #t)))
+         (let* ((data? data?)
                 (reported? (and (not data?) (eq? (car x) 'syntax-violation) (list? x))))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-input-bound: plain transformers whose input goes elsewhere than as syntax-violation's last argument: bound to another name, by let, define and set!; the message; quoted; in quoted data
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-let "(form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-define "(define form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-set "(set!  [cut: 503 more characters]
  actual:   (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-let "(form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-define "(define form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-set "(set!  [cut: 374 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI5. syntax-violation's places never read

**Guards:** syntax-violation stands only at the head of a tail call.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1157,3 +1157,3 @@
                     (for-each (lambda (place) (violation! 'plain-macro-raise path name (abbreviated place)))
-                              (raise-places body tails))))))))
+                              '())))))))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-input-bound: plain transformers whose input goes elsewhere than as syntax-violation's last argument: bound to another name, by let, define and set!; the message; quoted; in quoted data
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-let "(form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-define "(define form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-set "(set!  [cut: 503 more characters]
  actual:   (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-let "(form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-define "(define form x)") (plain-macro-input "tests/fixtures/conventions/plain-input-bound/curl/b.sls" by-set "(set!  [cut: 374 more characters]
FAIL plain-input-shadowed: plain transformers that shadow their input, so syntax-violation is handed something else: by let, an inner lambda, whose call is then no tail call, an internal define
  expected: (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-let "(x 0)") (plain-macro-input "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-lambda "(x)") (plain-macro-raise "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-lambda "(syntax-v [cut: 152 more characters]
  actual:   (returned (() ((plain-macro-input "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-let "(x 0)") (plain-macro-input "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-lambda "(x)") (plain-macro-input "tests/fixtures/conventions/plain-input-shadowed/curl/s.sls" by-define "(define x [cut: 8 more characters]
FAIL plain-raise-guarded: A9: plain transformers whose input goes only to syntax-violation, with a handler around the call that takes it back from the condition: by guard, and by with-exception-handler
  expected: (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard) (plain-macro-raise "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard "(syntax-violation (quote by-guard) \"never\" x)") (plain-macro-import "tests/fixtures/conventions/plain-raise-guar [cut: 173 more characters]
  actual:   (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard) (plain-macro-import "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-handler))))
FAIL plain-raise-shadowed: A11: plain transformers that rebind syntax-violation, by let and by an internal define
  expected: (returned (() ((plain-macro-raise "tests/fixtures/conventions/plain-raise-shadowed/curl/s.sls" by-let "(syntax-violation (lambda (who message form) form))") (plain-macro-raise "tests/fixtures/conventions/plain-raise-shadowed/curl/s.sls" by-define "(syntax-violation who message form)"))))
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI6. guard's body taken for a tail position

**Guards:** a raise under a handler the transformer set up is no tail call: A9.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -953,3 +953,3 @@
             ((when unless) (if (>= n 3) (last-of (cddr form)) '()))
-            ((begin and or) (last-of (cdr form)))
+            ((begin and or guard) (last-of (cdr form)))
             ((let) (cond ((and (>= n 4) (symbol? (cadr form))) (last-of (cdddr form)))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-raise-guarded: A9: plain transformers whose input goes only to syntax-violation, with a handler around the call that takes it back from the condition: by guard, and by with-exception-handler
  expected: (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard) (plain-macro-raise "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard "(syntax-violation (quote by-guard) \"never\" x)") (plain-macro-import "tests/fixtures/conventions/plain-raise-guar [cut: 173 more characters]
  actual:   (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard) (plain-macro-import "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-handler) (plain-macro-raise "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-handler "(syntax-violation (q [cut: 34 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI7. the library's imports never read

**Guards:** a procedural plain macro's library reaches no other library: A6, A10, A12.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1151,3 +1151,3 @@
                     (unless (plain-imports? imports)
-                      (violation! 'plain-macro-import path name))
+                      #f)
                     (for-each (lambda (place) (violation! 'plain-macro-input path name (abbreviated place)))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-input-elsewhere: A6: a plain transformer hands its input to a procedure another library exports, which takes it apart and rebuilds it; the reader reads memcpy
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" foreign-procedure ())) ((plain-macro-import "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" m) (plain-macro-input "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" m "(rebuild x)"))))
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" foreign-procedure ())) ((plain-macro-input "tests/fixtures/conventions/plain-input-elsewhere/curl/m.sls" m "(rebuild x)"))))
FAIL plain-raise-guarded: A9: plain transformers whose input goes only to syntax-violation, with a handler around the call that takes it back from the condition: by guard, and by with-exception-handler
  expected: (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard) (plain-macro-raise "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard "(syntax-violation (quote by-guard) \"never\" x)") (plain-macro-import "tests/fixtures/conventions/plain-raise-guar [cut: 173 more characters]
  actual:   (returned (() ((plain-macro-raise "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-guard "(syntax-violation (quote by-guard) \"never\" x)") (plain-macro-raise "tests/fixtures/conventions/plain-raise-guarded/curl/g.sls" by-handler "(syntax-violation (quote by-handler) \"never\" x)"))))
FAIL plain-raise-imported: A10: a plain transformer in a library that takes syntax-violation from another, with (rnrs)'s excepted
  expected: (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-raise-imported/curl/i.sls" m))))
  actual:   (returned (() ()))
FAIL plain-built-elsewhere: A12: a plain transformer whose input goes nowhere, and whose output a procedure another library exports builds from strings
  expected: (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-built-elsewhere/curl/m.sls" m))))
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI8. any import counted as (rnrs ...)

**Guards:** only whole (rnrs ...) libraries and (only (chezscheme) ...) are admitted: A12.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1003,3 +1003,3 @@
                              (not (equal? spec '(rnrs eval))))
-                        (chez-only? spec)))
+                        #t))
                   imports)
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-input-elsewhere: A6: a plain transformer hands its input to a procedure another library exports, which takes it apart and rebuilds it; the reader reads memcpy
FAIL plain-raise-guarded: A9: plain transformers whose input goes only to syntax-violation, with a handler around the call that takes it back from the condition: by guard, and by with-exception-handler
FAIL plain-built-elsewhere: A12: a plain transformer whose input goes nowhere, and whose output a procedure another library exports builds from strings
  expected: (returned (() ((plain-macro-import "tests/fixtures/conventions/plain-built-elsewhere/curl/m.sls" m))))
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI9. cond's clauses no tail position

**Guards:** src/'s require-supported-chez raises from cond's clauses, and passes only while those count.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -950,3 +950,3 @@
                           (if (>= n 4) (tail-raises (cadddr form)) '())))
-            ((cond) (clauses-of (cdr form)))
+            ((cond) '())
             ((case) (if (>= n 2) (clauses-of (cddr form)) '()))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((plain-macro-raise "src/curl/private/require-threaded.sls" require-supported-chez "(syntax-violation (quote chez-curl) \"chez-curl needs a threaded Chez Scheme, and (threaded?) is #...") (plain-macro-raise "src/curl/private/require-threaded.sls" require-supported-chez "(syntax-violation (quote chez-curl) ( [cut: 68 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### SA6. require-supported-chez hands x to a procedure

**Guards:** src/'s procedural plain macro is held to rule 2.

**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
@@ -89,3 +89,3 @@
              x))
-           (else #'(define supported-chez-checked #t)))))))
+           (else (rebuild x)))))))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((plain-macro-input "src/curl/private/require-threaded.sls" require-supported-chez "(rebuild x)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### SA9. require-supported-chez guards a raise of its input

**Guards:** src/'s procedural plain macro is held to the tail rule. The guard catches its own raise, so the macro still works: only test-collect-safe can fail.

**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
@@ -89,3 +89,3 @@
              x))
-           (else #'(define supported-chez-checked #t)))))))
+           (else (guard (c (#t #'(define supported-chez-checked #t))) (syntax-violation 'chez-curl "never" x))))))))
 
```

**Result:** killed, exit 2, 17 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((plain-macro-raise "src/curl/private/require-threaded.sls" require-supported-chez "(syntax-violation (quote chez-curl) \"never\" x)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

###### SA10. require-threaded.sls imports (except (rnrs) exit)

**Guards:** src/'s procedural plain macro's library is held to the import rule; the library still loads.

**Mutation:** In `src/curl/private/require-threaded.sls`:

```diff
@@ -35,3 +35,3 @@
   (export)
-  (import (rnrs)
+  (import (except (rnrs) exit)
           (only (chezscheme) threaded? scheme-version scheme-version-number))
```

**Result:** killed, exit 2, 17 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((plain-macro-import "src/curl/private/require-threaded.sls" require-supported-chez))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

##### Clean rerun

On the working tree, in the container, after the last edit:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (15 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: ran 15, passed 15, failed 0, hung 0
check-variadic: all 19 steps ok, on ta6le
test-memory: ran 2, passed 2, failed 0, hung 0
check-test-fails: make test failed, as it must, in all 10 cases
```

`make test-memory` ran with `MEMORY_SUITES="tests/test-variadic.sps tests/test-collect-safe.sps"`.
No Chez or Valgrind process was left behind. Apple arm64 is still pending, as above.

### The review of the three rounds

A scoped review of the three rounds above found a route the rules admitted, and two smaller gaps.
Each is closed, each closure watched failing first.

- **The route.** `load-step` gained a flat second clause, `((_ head operand ...) (head operand
  ...))`, holding no banned name. Handed `define-syntax`, it defined `bind-quietly`, whose
  syntax-case built a `foreign-procedure` form from strings, and `curl-easy-setopt-long` was
  bound through it. Closed two ways:
  - `define-syntax`, `let-syntax` and `letrec-syntax` are occurrences (`macro-keywords`). Each
    stands only at the head of a form written in code; as an operand, in data or at a head in a
    template it is `stray`;
  - in a binder's or plain macro's templates, no pattern variable heads a form, else
    `(macro-pattern-head FILE NAME FORM)`. That is the mechanism: a use could hand in any keyword
    there, `import` and the rest. A `foreign-procedure` form's parameter list is types, never a
    form, so a binder's `(arg ...)` there is allowed. With that one exception, src/'s four
    macros pass as written: `bind-required` and `bind-variadic` hold `(arg ...)` only there.
- **A case clause's datum list is data.** The reader had read
  `(case x ((foreign-procedure "curl_easy_init" () uptr) 'data) (else 'other))` as a binding of
  `curl_easy_init`, which Chez never made: a phantom that could hold a live count.
- **check-seam's rule (h).** Every `(curl ...)` or `(http-client ...)` library a library under
  src/ imports must be defined there; else Chez loads it from elsewhere on its path, and the
  suites' path holds `tests/`. Rule (h) names an import no other rule refuses: one refused by
  rule (a) or (b) fails the seam already, and check-test-fails' seam plant, which this round may
  not edit, holds check-seam's whole output for such an import. Nine seam fixtures imported
  family libraries their trees did not define. Each now defines them, in a file of its own or,
  in `lock-directory`, whose files test-require-threaded lists, as a second form of `bad.sls`.
  Rule-a's tree does not, so that case also shows the one complaint.

`test-collect-safe` has four new cases, `review-route`, `keyword-places`, `pattern-head` and
`case-data`, and four changed answers: `macro-nested`'s template definition is stray too, and
`plain-pattern`, `binder-takes-apart` and `wrapper-template` name pattern-variable heads. 106
tests. `test-check-seam` has `import-undefined`, and `legal`'s and `ftype-listed`'s counts grew
with their new files. 51 tests.

#### The review's findings, reproduced on the unfixed tree

The tree as the macro rounds left it, in a copy (`runs-review-pre`), each run a control expected to
show the hole.

| ID | Change | Result |
|---|---|---|
| PRE-REV1 | the review's route | `make test`: test-collect-safe passes; test-variadic dies, exit 255 |
| PRE-REV2 | the `case` probe in native | test-collect-safe: `curl_easy_init` counted twice, the phantom among them |
| PRE-REV3 | `tests/curl/private/extra.sls` binding an absent entry, imported and referenced by native | check-seam holds (10 libraries); test-collect-safe passes; test-native and test-variadic die: `no entry for "chez_curl_review_absent"` |

PRE-REV3 needs native to reference the library, not only import it: Chez runs a library body only
when a binding of it is referenced (AGENTS.md), and the first run, with the import alone, passed
test-native.

#### Red runs

The cases were written before the code. Against the reader as it stood, `make test
SUITES=tests/test-collect-safe.sps` failed the four new cases, and nothing else. The reader had
admitted the review's route with no violation, and read the `case` probe as a binding:

```
FAIL review-route: the review's route: load-step's flat second clause puts its first operand at a head, and is handed define-syntax, defining a macro that builds a foreign-procedure form from strings
FAIL keyword-places: define-syntax, let-syntax and letrec-syntax anywhere but the head of a form written in code: an operand, data, a template
FAIL pattern-head: listed macros whose templates put a pattern variable at a form's head: two binders, a syntax-rules plain macro, a spliced one and identifier-syntax's; a binder's foreign-procedure parameter list is types, not a form; any is held to none
FAIL case-data: a case clause's datum list is data, so a foreign-procedure form or a wrapper's use there is stray; a clause's body is code
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

And against check-seam as it stood, the new seam case:

```
FAIL import-undefined: a (curl ...) import, through prefix, and an (http-client ...) import that no library in the tree defines; ones it defines pass
  actual:   (0 "check-seam: the seam holds (4 libraries in 4 files checked)\n" "")
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### Mutations

71 cases ran on the final snapshot, which `diff -rq --no-dereference` showed identical to the
working tree: the 57 of the input round, the review's three findings, nine kills of this round's
rules, and two measurements of routes still open. All 68 mutations were killed, each with every
expected line present; `CLEAN` passed, and both measurements showed what they measure.

The 57, rerun. SP1's added clause, `((_ (w "memcpy" . rest)) (w "curl_easy_setopt" . rest))`, now
also names its head, and R0's and MR5's targets moved with the code. Every other case's expected
lines are unchanged.

| ID | Result |
|---|---|
| A1 | killed, exit 2 |
| A2 | killed, exit 2 |
| A3 | killed, exit 2 |
| A3P | killed, exit 2 |
| A4 | killed, exit 2 |
| A5 | killed, exit 2 |
| FPA4 | killed, exit 2 |
| D | killed, exit 2 |
| BR1 | killed, exit 2 |
| BR2 | killed, exit 2 |
| L | killed, exit 2 |
| WM1 | killed, exit 2 |
| WM2 | killed, exit 2 |
| WM3 | killed, exit 2 |
| WM4 | killed, exit 2 |
| WM5 | killed, exit 2 |
| WM6 | killed, exit 2 |
| CVF1 | killed, exit 2 |
| CVF2 | killed, exit 2 |
| CVF3 | killed, exit 2 |
| CVF4 | killed, exit 2 |
| CVF5 | killed, exit 2 |
| CVF6 | killed, exit 2 |
| CVF7 | killed, exit 2 |
| CVF8 | killed, exit 2 |
| CVF9 | killed, exit 2 |
| CLEAN | as expected, exit 0 |
| R0 | killed, exit 2 |
| MR1 | killed, exit 2 |
| MR2 | killed, exit 2 |
| MR3 | killed, exit 2 |
| MR4 | killed, exit 2 |
| MR5 | killed, exit 2 |
| MR6 | killed, exit 2 |
| MR7 | killed, exit 2 |
| MR8 | killed, exit 2 |
| MR9 | killed, exit 2 |
| MR10 | killed, exit 2 |
| MR11 | killed, exit 2 |
| MR12 | killed, exit 2 |
| MR13 | killed, exit 2 |
| SP1 | killed, exit 2 |
| SP2 | killed, exit 2 |
| SB1 | killed, exit 2 |
| R1 | killed, exit 2 |
| MI1 | killed, exit 2 |
| MI2 | killed, exit 2 |
| MI3 | killed, exit 2 |
| MI4 | killed, exit 2 |
| MI5 | killed, exit 2 |
| MI6 | killed, exit 2 |
| MI7 | killed, exit 2 |
| MI8 | killed, exit 2 |
| MI9 | killed, exit 2 |
| SA6 | killed, exit 2 |
| SA9 | killed, exit 2 |
| SA10 | killed, exit 2 |

The new ones:

| ID | Change | Killed by |
|---|---|---|
| REV1 | the review's route | test-collect-safe: `macro-pattern-head` in `load-state.sls`, `stray` in `native.sls` |
| REV2 | the `case` probe in native | test-collect-safe: `stray`; the six entries counted once each |
| REV3 | `tests/curl/private/extra.sls`, imported by native | check-seam, by rule (h): `make test` stops there |
| MK1 | the macro keywords no occurrences | test-collect-safe: `keyword-places`, `review-route` |
| MK2 | a keyword at a template's head allowed | test-collect-safe: `keyword-places`, `macro-nested` |
| MK3 | templates' heads never read | test-collect-safe: `review-route`, `pattern-head`, `plain-pattern`, `binder-takes-apart`, `wrapper-template` |
| MK4 | a `foreign-procedure` form's parameter list read as a form | test-collect-safe: src/'s two binders, by their `(arg ...)`; `pattern-head` |
| MK5 | identifier-syntax's templates never read | test-collect-safe: `pattern-head`, `plain-pattern` |
| MK6 | a case clause's datum list read as code | test-collect-safe: `case-data` |
| MK7 | rule (h) never names an import | test-check-seam: `import-undefined` |
| MK8 | no library counted as defined | check-seam on src/: `(curl)`'s import of `(curl private require-threaded)` |
| MK9 | rule (h) naming an import rule (a) refuses | test-check-seam: `rule-a` |


##### REV1. the review's route

**Guards:** a keyword handed to a macro, and a pattern variable at a template's head, are each named.

**Mutation:** In `src/curl/private/load-state.sls`:

```diff
@@ -68,2 +68,3 @@
                        (raise c))))
-         expr)))))
+         expr))
+      ((_ head operand ...) (head operand ...)))))
```

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -271,4 +271,16 @@
   ;; or a curl_off_t: the CURLcode.
+  (load-step define-syntax bind-quietly
+    (lambda (x)
+      (syntax-case x ()
+        ((k entry types result)
+         (datum->syntax #'k
+                        (list (string->symbol (string-append "foreign-" "procedure"))
+                              (syntax->datum #'entry) (syntax->datum #'types)
+                              (syntax->datum #'result)))))))
+
+  (define curl-easy-setopt-long-unused
+    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+
   (define curl-easy-setopt-long
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int info)))
+    (load-step (bind-quietly "chez_curl_review_absent" (uptr int long) int)))
 
```

**Result:** killed, exit 2, 19 s, through `make test`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((macro-pattern-head "src/curl/private/load-state.sls" load-step "(head operand ...)") (stray "src/curl/private/native.sls" "(load-step define-syntax bind-quietly (lambda (x) (syntax-case x () ((k entry types result) (datu..."))
test: FAIL tests/test-collect-safe.sps (exit 1)
FAIL the headers the C program compiled against are no newer than the libcurl chez-curl loads
test: FAIL tests/test-constants.sps (exit 1)
FAIL decoy accepted: the control loads, calling curl_global_init exactly once, after the version
FAIL decoy ssl-null: a NULL ssl_version is reported as #f
FAIL decoy host-null: a NULL host is reported as #f
FAIL decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
FAIL decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
FAIL a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
FAIL decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
FAIL decoy lacks-curl_easy_getinfo: a library without curl_easy_getinfo is missing-api, naming it
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
test: FAIL tests/test-native.sps (exit 255)
test: FAIL tests/test-variadic.sps (exit 255)
test: ran 15, passed 10, failed 5, hung 0
```

##### REV2. the case probe

**Guards:** a case clause's datum list is data: no phantom binding, and its foreign-procedure is stray.

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -288,2 +288,8 @@
 
+  (define case-probe
+    (lambda (x)
+      (case x
+        ((foreign-procedure "curl_easy_init" () uptr) 'data)
+        (else 'other))))
+
   ;; --- 7. the two API probes, then check-apis --------------------------------------------
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((stray "src/curl/private/native.sls" "(foreign-procedure \"curl_easy_init\" () uptr)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### REV3. a family library from tests/

**Guards:** every family library a src/ library imports is defined under src/.

**Mutation:** In `tests/curl/private/extra.sls`:

```diff
+#!r6rs
+;; On the suites' library path, tests/, where check-seam reads nothing.
+(library (curl private extra)
+  (export extra)
+  (import (rnrs) (only (chezscheme) foreign-procedure))
+  (define extra (foreign-procedure "chez_curl_review_absent" () int)))
```

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -53,2 +53,3 @@
   (import (curl private require-threaded)
+          (curl private extra)
           (rnrs)
```

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -289,2 +289,4 @@
 
+  (define review-extra extra)
+
   ;; --- 7. the two API probes, then check-apis --------------------------------------------
```

**Result:** killed, exit 2, 3 s, through `make test`:

```
check-seam: src/curl/private/native.sls: (curl private native) imports (curl private extra), but no library under src/ defines it, so Chez would load it from elsewhere on its library path, which this check does not read
```

##### MK1. the macro keywords no occurrences

**Guards:** define-syntax, let-syntax and letrec-syntax are held to the head of a written form.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1129,3 +1129,3 @@
       ;; one of macro-keywords.
-      (define (name? x) (or (binding-name? x) (and (memq x macro-keywords) #t)))
+      (define (name? x) (binding-name? x))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL review-route: the review's route: load-step's flat second clause puts its first operand at a head, and is handed define-syntax, defining a macro that builds a foreign-procedure form from strings
  expected: (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/review-route/curl/n.sls" bind-variadic ())) ((macro-pattern-head "tests/fixtures/conventions/review-route/curl/n.sls" load-step "(head operand ...)") (stray "tests/fixtures/conventions/review-route/curl/n.sls" "(load-step defi [cut: 90 more characters]
  actual:   (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/review-route/curl/n.sls" bind-variadic ())) ((macro-pattern-head "tests/fixtures/conventions/review-route/curl/n.sls" load-step "(head operand ...)"))))
FAIL keyword-places: define-syntax, let-syntax and letrec-syntax anywhere but the head of a form written in code: an operand, data, a template
  expected: (returned (() ((stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(step define-syntax)") (stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(let-syntax ((m 0)) m)") (stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(list letrec-syntax)") (stray "tests/fixtures/convention [cut: 200 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(define-syntax name (syntax-rules () ((_) 0)))") (macro-nested "tests/fixtures/conventions/keyword-places/curl/k.sls" "(define-syntax name (syntax-rules () ((_) 0)))"))))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MK2. a keyword at a template's head allowed

**Guards:** a template's define-syntax is stray.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1171,3 +1171,3 @@
         (let ((head (car form)))
-          (when (and (not quoted?) in-macro? (memq head macro-keywords))
+          (when #f
             (violation! 'stray path (abbreviated form)))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL macro-nested: define-syntax anywhere but a library body's top level: in a procedure's body, in a begin, and in a listed macro's template
  expected: (returned (() ((macro-nested "tests/fixtures/conventions/macro-nested/curl/n.sls" "(define-syntax inner (syntax-rules () ((_) 0)))") (macro-nested "tests/fixtures/conventions/macro-nested/curl/n.sls" "(define-syntax in-begin (syntax-rules () ((_) 0)))") (stray "tests/fixtures/conventions/macro-nested/curl/n [cut: 175 more characters]
  actual:   (returned (() ((macro-nested "tests/fixtures/conventions/macro-nested/curl/n.sls" "(define-syntax inner (syntax-rules () ((_) 0)))") (macro-nested "tests/fixtures/conventions/macro-nested/curl/n.sls" "(define-syntax in-begin (syntax-rules () ((_) 0)))") (macro-nested "tests/fixtures/conventions/macro-nested [cut: 65 more characters]
FAIL keyword-places: define-syntax, let-syntax and letrec-syntax anywhere but the head of a form written in code: an operand, data, a template
  expected: (returned (() ((stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(step define-syntax)") (stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(let-syntax ((m 0)) m)") (stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(list letrec-syntax)") (stray "tests/fixtures/convention [cut: 200 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(step define-syntax)") (stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(let-syntax ((m 0)) m)") (stray "tests/fixtures/conventions/keyword-places/curl/k.sls" "(list letrec-syntax)") (macro-nested "tests/fixtures/con [cut: 88 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MK3. templates' heads never read

**Guards:** no pattern variable heads a form in a listed macro's template.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1227,3 +1227,3 @@
                (for-each (lambda (place) (violation! 'macro-pattern-head path name (abbreviated place)))
-                         (template-heads form)))))))
+                         '()))))))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL wrapper-template: a known wrapper's name in a macro, a head with a literal entry too: syntax-rules templates, one handing the use to a pattern variable, a syntax-case taking its template apart, with-syntax, quasisyntax and syntax in procedures, transformers by define-syntax and let-syntax, identifier-syntax's set! [cut: 124 more characters]
  expected: (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 1720 more characters]
  actual:   (returned (() ((stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-required \"curl_easy_init\" () uptr #f)") (stray "tests/fixtures/conventions/wrapper-template/curl/t.sls" "(bind-variadic \"curl_easy_setopt\" (uptr int long) int #f)") (stray "tests/fixtures/conventions/wrapper-template/c [cut: 1616 more characters]
FAIL plain-pattern: plain macros whose patterns take an operand apart: nested, improper, a vector, not headed by _, and identifier-syntax's set! clause; two with identifiers only, an ellipsis among them, pass
  expected: (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (macro-pattern-head "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(w \"curl_easy_setopt\" . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail [cut: 397 more characters]
  actual:   (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail "(_ a . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" vec "(_ #(a b))") (pla [cut: 193 more characters]
FAIL review-route: the review's route: load-step's flat second clause puts its first operand at a head, and is handed define-syntax, defining a macro that builds a foreign-procedure form from strings
  expected: (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/review-route/curl/n.sls" bind-variadic ())) ((macro-pattern-head "tests/fixtures/conventions/review-route/curl/n.sls" load-step "(head operand ...)") (stray "tests/fixtures/conventions/review-route/curl/n.sls" "(load-step defi [cut: 90 more characters]
  actual:   (returned ((("curl_easy_setopt" ((__varargs_after 2)) "tests/fixtures/conventions/review-route/curl/n.sls" bind-variadic ())) ((stray "tests/fixtures/conventions/review-route/curl/n.sls" "(load-step define-syntax bind-quietly (lambda (x) (syntax-case x () ((k entry types result) (datu..."))))
FAIL pattern-head: listed macros whose templates put a pattern variable at a form's head: two binders, a syntax-rules plain macro, a spliced one and identifier-syntax's; a binder's foreign-procedure parameter list is types, not a form; any is held to none
  expected: (returned (() ((macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-required "(library entry)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-listed "(arg ...)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" apply-head "(k a [cut: 185 more characters]
  actual:   (returned (() ()))
FAIL binder-takes-apart: a binder whose pattern takes its library operand apart, so its template could rebuild a use it is handed: unreadable, and none of its uses read
  expected: (returned (() ((macro-pattern-head "tests/fixtures/conventions/binder-takes-apart/curl/b.sls" bind-required "(w \"curl_easy_setopt\" . rest)") (wrapper-unreadable "tests/fixtures/conventions/binder-takes-apart/curl/b.sls" bind-required "its pattern takes an operand apart: an element other than its parameter [cut: 32 more characters]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/binder-takes-apart/curl/b.sls" bind-required "its pattern takes an operand apart: an element other than its parameter list is a list or a vector"))))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MK4. a foreign-procedure form's parameter list read as a form

**Guards:** the one exception is what lets src/'s binders pass: their (arg ...).

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1055,3 +1055,3 @@
                        (loop (cdr rest)
-                             (append found (if (and types (eq? (car rest) types))
+                             (append found (if #f
                                                '()
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL legal: every accounted place: the import, the known wrapper's one definition and its uses in code, a let's initial value and a plain macro's operand among them, two plain macros, direct bindings in two files, two conventions as a set, a template that is no wrapper in a fixture's macro, callables, and look-alikes
FAIL wrapper-unquoted: the review's A1: bind-required under an unquote, in a quasiquote, which is data
FAIL wrapper-aliased: the review's A2: bind-required in identifier-syntax's template, so bind-plain is another name for it
FAIL wrapper-passed: the review's A3: bind-required an argument of a macro that puts it at a head, binding curl_easy_setopt plain and curl_easy_perform with an unmarked u8*
FAIL wrapper-import-export: a known wrapper's name exported, by name and renamed, and imported by only, rename, except, prefix, for, (only (chezscheme) ...) and a body import
FAIL macro-swap-entry: A5: a macro on no row takes apart a use it is handed, which the reader reads as memcpy, and rebuilds it with curl_easy_setopt
FAIL macro-rebind: FPA4: a syntax-case on no row takes apart its own template, a foreign-procedure form the reader reads as memcpy, and binds curl_easy_setopt
FAIL review-route: the review's route: load-step's flat second clause puts its first operand at a head, and is handed define-syntax, defining a macro that builds a foreign-procedure form from strings
FAIL pattern-head: listed macros whose templates put a pattern variable at a form's head: two binders, a syntax-rules plain macro, a spliced one and identifier-syntax's; a binder's foreign-procedure parameter list is types, not a form; any is held to none
  expected: (returned (() ((macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-required "(library entry)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-listed "(arg ...)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" apply-head "(k a [cut: 185 more characters]
  actual:   (returned (() ((macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-required "(library entry)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-required "(arg ...)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-listed "( [cut: 383 more characters]
FAIL binder-takes-apart: a binder whose pattern takes its library operand apart, so its template could rebuild a use it is handed: unreadable, and none of its uses read
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe, and memcpy's u8* unmarked
FAIL variadic: ADR-0001's variadic rows: (__varargs_after 2) through the variadic wrapper holds; directly, with it, is the wrong binder; through the plain wrapper, with no convention, (__varargs_after 1) and __varargs alone each mismatch, and is the wrong binder
FAIL wrong-binder: rows that name their binder: a variadic entry through another wrapper that carries its convention, and directly with it; an entry whose row names foreign-procedure, bound so and through a wrapper; a callable whose row names foreign-procedure; a marked row's binder, the mark clearing its string either [cut: 4 more characters]
FAIL variadic-unannotated: make check-variadic's mutant: the variadic wrapper's template without (__varargs_after 2), so each of its uses mismatches
FAIL crossing-wrapper: crossings through known wrappers: a use's parameter list, a template's own, and a use's result; a use's u8* result hands C none, and its scheme-object result is never allowed
FAIL crossing-marked: a row marked as the reviewed crossing clears its bindings, direct and wrapped; a mark that quotes nothing clears none
FAIL types-unreadable: types the reader cannot read: a string, a list that is no (* name), a callable's result, a wrapper use's parameter list that is a variable, improper, or missing; and types on no allowlist: a name that is no Chez type, void as a parameter, ptr, utf-16, a procedure's result, a callable's parameter, [cut: 23 more characters]
FAIL types-pattern-variable: pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, with-syntax, identifier-syntax, a callable's result, and a convention; a wrapper's use in a syntax-case template is stray; a macro whose pattern binds no type stays readable
FAIL string-unmarked: bindings that hand C a string from Chez's heap, none marked: a string parameter, one of each other string type, one through the known wrapper, and a callable's utf-8 result; a procedure's utf-8 result and a callable's string parameter hand C none
FAIL string-marked: a row marked string-not-kept clears its strings, direct, wrapped and a callable's result; a mark that quotes nothing clears none, and each mark clears its own kind alone
FAIL wrapper-safe: __collect_safe in the known wrapper's template: every use gets it
FAIL wrapper-pattern-conventions: the known wrapper's conventions come from a pattern variable
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal, parameters mixed, literal but no types, a nested result, and a result that holds a variable
FAIL wrapper-entry-not-string: uses of the known wrapper whose entry is no string literal: a variable, an expression, none at all
FAIL wrapper-defined-again: the known wrapper defined in two files: the second stands where its row does not say, and no use is read against either
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((macro-pattern-head "src/curl/private/native.sls" bind-required "(arg ...)") (macro-pattern-head "src/curl/private/native.sls" bind-variadic "(arg ...)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MK5. identifier-syntax's templates never read

**Guards:** identifier-syntax's set! clause's template is held too.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1095,3 +1095,3 @@
                            '() (elements (cdr syntax)))))
-      '() (forms-headed '(identifier-syntax) form))))
+      '() '())))
 
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL plain-pattern: plain macros whose patterns take an operand apart: nested, improper, a vector, not headed by _, and identifier-syntax's set! clause; two with identifiers only, an ellipsis among them, pass
  expected: (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (macro-pattern-head "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(w \"curl_easy_setopt\" . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail [cut: 397 more characters]
  actual:   (returned (() ((plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(_ (w e . rest))") (macro-pattern-head "tests/fixtures/conventions/plain-pattern/curl/p.sls" swap "(w \"curl_easy_setopt\" . rest)") (plain-macro-pattern "tests/fixtures/conventions/plain-pattern/curl/p.sls" tail [cut: 307 more characters]
FAIL pattern-head: listed macros whose templates put a pattern variable at a form's head: two binders, a syntax-rules plain macro, a spliced one and identifier-syntax's; a binder's foreign-procedure parameter list is types, not a form; any is held to none
  expected: (returned (() ((macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-required "(library entry)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-listed "(arg ...)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" apply-head "(k a [cut: 185 more characters]
  actual:   (returned (() ((macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-required "(library entry)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" bind-listed "(arg ...)") (macro-pattern-head "tests/fixtures/conventions/pattern-head/curl/h.sls" apply-head "(k a [cut: 98 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MK6. a case clause's datum list read as code

**Guards:** a case clause's datums are data.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
@@ -1269,3 +1269,3 @@
                           (else
-                           (unless (eq? (car clause) 'else) (walk (car clause) clause #t))
+                           (unless (eq? (car clause) 'else) (walk (car clause) clause #f))
                            (walk-elements clause 1 #f))))
```

**Result:** killed, exit 2, 3 s, through `make test SUITES=tests/test-collect-safe.sps`:

```
FAIL case-data: a case clause's datum list is data, so a foreign-procedure form or a wrapper's use there is stray; a clause's body is code
  expected: (returned ((("curl_global_init" () "tests/fixtures/conventions/case-data/curl/c.sls" foreign-procedure ())) ((stray "tests/fixtures/conventions/case-data/curl/c.sls" "(foreign-procedure \"curl_easy_init\" () uptr)") (stray "tests/fixtures/conventions/case-data/curl/c.sls" "(bind-required \"curl_easy_init\"  [cut: 16 more characters]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/case-data/curl/c.sls" foreign-procedure ()) ("curl_global_init" () "tests/fixtures/conventions/case-data/curl/c.sls" foreign-procedure ())) ((wrapper-undefined "tests/fixtures/conventions/case-data/curl/c.sls" bind-required "(bind-required \"curl_ [cut: 28 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MK7. rule (h) never names an import

**Guards:** check-seam names a family import defined nowhere under the directory.

**Mutation:** In `tests/check-seam.sps`:

```diff
@@ -369,3 +369,3 @@
 (define (undefined-complaints path name imported defined)
-  (if (member imported defined)
+  (if #t
       '()
```

**Result:** killed, exit 2, 6 s, through `make test SUITES=tests/test-check-seam.sps`:

```
FAIL import-undefined: a (curl ...) import, through prefix, and an (http-client ...) import that no library in the tree defines; ones it defines pass
  expected: (1 "" "check-seam: tests/fixtures/seam/import-undefined/curl/x.sls: (curl x) imports (curl private extra), but no library under src/ defines it, so Chez would load it from elsewhere on its library path, which this check does not read\ncheck-seam: tests/fixtures/seam/import-undefined/http-client/z.sls: (http [cut: 200 more characters]
  actual:   (0 "check-seam: the seam holds (4 libraries in 4 files checked)\n" "")
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### MK8. no library counted as defined

**Guards:** rule (h) reads the libraries the directory defines; src/ holds only because they are counted.

**Mutation:** In `tests/check-seam.sps`:

```diff
@@ -543,3 +543,3 @@
              (unread (list-sort string<? (caddr found)))
-             (defined (defined-libraries files))
+             (defined '())
              (results (map (lambda (path) (check-file path defined)) files))
```

**Result:** killed, exit 2, 2 s, through `make check-seam`:

```
check-seam: src/curl.sls: (curl) imports (curl private require-threaded), but no library under src/ defines it, so Chez would load it from elsewhere on its library path, which this check does not read
```

##### MK9. rule (h) naming an import rule (a) refuses

**Guards:** one complaint for an import another rule refuses.

**Mutation:** In `tests/check-seam.sps`:

```diff
@@ -404,6 +404,7 @@
        (if (family? 'curl name)
-           (list (string-append path ": " (written name) " imports "
-                                (written imported)
-                                ", but no (curl ...) library may import"
-                                " an (http-client ...) library"))
+           (append (list (string-append path ": " (written name) " imports "
+                                        (written imported)
+                                        ", but no (curl ...) library may import"
+                                        " an (http-client ...) library"))
+                   (undefined-complaints path name imported defined))
            (undefined-complaints path name imported defined)))
```

**Result:** killed, exit 2, 6 s, through `make test SUITES=tests/test-check-seam.sps`:

```
FAIL rule-a: rule (a): a (curl ...) library importing an (http-client ...) library, which the tree does not define: rule (h) does not name an import another rule refuses
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (http-client y), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (1 "" "check-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (http-client y), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (http-client y), but no library under src/ defines it, so Chez would load it from [cut: 100 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

#### What the rules still admit, measured

Two routes, each reported, neither ruled against, as the review asked. Each run passed
test-collect-safe, and showed Chez doing what the reader did not see.

- **PH1, a phantom.** With `load-step`'s clause `((_ tag expr) (quote expr))`, native's
  `curl-easy-setopt-pointer` became `(load-step #f (bind-variadic ...))`. The reader still
  counted three setopt bindings, but Chez made two: test-variadic failed its PRIVATE round trips
  by name. A phantom hides no binding by itself; it could keep a count while another route
  did.
- **A14, a name off its path.** `(curl private extra)` defined as a second form of
  `src/curl/private/conditions.sls`, and `tests/curl/private/extra.sls` binding an absent entry,
  with native importing it first: check-seam held (11 libraries in 10 files), test-collect-safe
  passed, and test-variadic died, `no entry for "chez_curl_review_absent"`. test-native passed:
  it loads `conditions.sls`, and with it src/'s `extra`, first. A rule holding each family
  library to its name's path would close it.

##### PH1. a plain template quoting its operand (a limit)

**Guards:** nothing: a plain macro's clause ((_ tag expr) (quote expr)) holds no banned name and no head from its pattern, and the reader reads the operand as written, a binding. Chez never makes it.

**Mutation:** In `src/curl/private/load-state.sls`:

```diff
@@ -68,2 +68,3 @@
                        (raise c))))
-         expr)))))
+         expr))
+      ((_ tag expr) (quote expr)))))
```

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -275,3 +275,3 @@
   (define curl-easy-setopt-pointer
-    (load-step (bind-variadic "curl_easy_setopt" (uptr int uptr) int info)))
+    (load-step #f (bind-variadic "curl_easy_setopt" (uptr int uptr) int info)))
 
```

**Result:** as expected, exit 2, 18 s, through `make test`:

```
test: pass tests/test-collect-safe.sps
FAIL PRIVATE set to #x123456789ABCDEF through curl-easy-setopt-pointer reads back exactly through curl-easy-getinfo
FAIL PRIVATE set to #xFEDCBA9876543210 through curl-easy-setopt-pointer reads back exactly through curl-easy-getinfo
test: FAIL tests/test-variadic.sps (exit 1)
test: ran 15, passed 14, failed 1, hung 0
```

##### A14. a family library defined in another src/ file (a limit)

**Guards:** nothing: rule (h) reads (curl private extra) defined as a second form of conditions.sls, while Chez, looking for it at its name's path, loads tests/curl/private/extra.sls when native asks for it first.

**Mutation:** In `src/curl/private/conditions.sls`:

```diff
@@ -119 +119,8 @@
     (actual curl-wrong-thread-actual)))
+
+;; A second library in this file: check-seam reads it, so (curl private
+;; extra) is defined under src/. Chez looks for it at its name's path.
+(library (curl private extra)
+  (export extra)
+  (import (curl private require-threaded) (rnrs))
+  (define extra 0))
```

**Mutation:** In `tests/curl/private/extra.sls`:

```diff
+#!r6rs
+;; On the suites' library path, tests/, where check-seam reads nothing.
+(library (curl private extra)
+  (export extra)
+  (import (rnrs) (only (chezscheme) foreign-procedure))
+  (define extra (foreign-procedure "chez_curl_review_absent" () int)))
```

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -53,2 +53,3 @@
   (import (curl private require-threaded)
+          (curl private extra)
           (rnrs)
```

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -289,2 +289,4 @@
 
+  (define review-extra extra)
+
   ;; --- 7. the two API probes, then check-apis --------------------------------------------
```

**Result:** as expected, exit 2, 18 s, through `make test`:

```
check-seam: the seam holds (11 libraries in 10 files checked)
test: pass tests/test-collect-safe.sps
test: FAIL tests/test-variadic.sps (exit 255)
test: ran 15, passed 14, failed 1, hung 0
```

#### Clean rerun

On the working tree, in the container, after the last edit:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (15 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: ran 15, passed 15, failed 0, hung 0
check-variadic: all 19 steps ok, on ta6le
test-memory: ran 2, passed 2, failed 0, hung 0
check-test-fails: make test failed, as it must, in all 10 cases
```

`make test-memory` ran with `MEMORY_SUITES="tests/test-variadic.sps tests/test-collect-safe.sps"`.
No Chez or Valgrind process was left behind. Apple arm64 is still pending, as above.

#### Rule (i): a library at its name's path

A14, measured above as a limit, is closed by check-seam's rule (i): each file under src/ holds
exactly one library, at the path its name gives, as Chez maps it with `--libdirs src` and the
`.sls` ending of `(library-extensions)`, the one ending check-seam lets stand under src/.
`(curl private extra)` belongs in `src/curl/private/extra.sls`, `(curl)` in `src/curl.sls`. A
definition anywhere else now fails the seam, so it cannot satisfy rule (h) while `tests/`
supplies the library Chez loads. With src/ first on the suites' library path, the library Chez
loads for a name is the one the checks read. src/'s ten libraries pass as written, each alone at
its path.

PH1 stays a limit, named in the reader's header: a phantom alone hides nothing, and no route that
hides a binding is known open.

The fixtures rule (i) touched, each keeping its one intended fault:

| Fixture | Change |
|---|---|
| `legal` | `curl/two.sls`, two libraries, split into `curl/two-a.sls` and `curl/two-b.sls`; 7 libraries in 7 files |
| `second-library` | `curl/two.sls` renamed `curl/two-a.sls`. Its point is two libraries in a file, so it now also names the file and `(curl two-b)` off its path: 3 complaints. Its `http-client/target.sls`, added in the review round, is gone: rule (h) names no import rule (a) refuses |
| `ftype-elsewhere` | `(curl private layouts extra)` moved from `curl/private/layouts-extra.sls` to its path, `curl/private/layouts/extra.sls` |
| `lock-directory` | `bad.sls`'s second form, added in the review round, removed: the file is as committed |
| `lock-symlink-live` | files unchanged, since test-require-threaded lists them. The `.#real.sls` link is read, and now named: it holds `(curl real)`, whose path is `curl/real.sls`. A refusal, no longer a pass |
| `off-path` (new) | A14's shape, a second library in a file that an import elsewhere finds defined, and a library alone in a file named for another |

`check-test-fails`' seam plant writes `src/curl/planted.sls` and `src/http-client.sls`, both at
their paths: its step stays ok, and its output is unchanged. 52 seam tests.

##### Red runs

A14 on the tree as the review round left it (`runs-a14-pre`, a control expected to show the
hole): check-seam held, test-collect-safe passed, and test-variadic died.


###### PRE-A14. A14, before rule (i)

**Guards:** nothing yet: the hole, shown.

**Mutation:** In `src/curl/private/conditions.sls`:

```diff
@@ -119 +119,8 @@
     (actual curl-wrong-thread-actual)))
+
+;; A second library in this file: check-seam reads it, so (curl private
+;; extra) is defined under src/. Chez looks for it at its name's path.
+(library (curl private extra)
+  (export extra)
+  (import (curl private require-threaded) (rnrs))
+  (define extra 0))
```

**Mutation:** In `tests/curl/private/extra.sls`:

```diff
+#!r6rs
+;; On the suites' library path, tests/, where check-seam reads nothing.
+(library (curl private extra)
+  (export extra)
+  (import (rnrs) (only (chezscheme) foreign-procedure))
+  (define extra (foreign-procedure "chez_curl_review_absent" () int)))
```

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -53,2 +53,3 @@
   (import (curl private require-threaded)
+          (curl private extra)
           (rnrs)
```

**Mutation:** In `src/curl/private/native.sls`:

```diff
@@ -289,2 +289,4 @@
 
+  (define review-extra extra)
+
   ;; --- 7. the two API probes, then check-apis --------------------------------------------
```

**Result:** as expected, exit 2, 17 s, through `make test`:

```
check-seam: the seam holds (11 libraries in 10 files checked)
test: pass tests/test-collect-safe.sps
test: FAIL tests/test-variadic.sps (exit 255)
test: ran 15, passed 14, failed 1, hung 0
```

And the new seam case, against check-seam as it stood:

```
FAIL off-path: rule (i): a second library in a file, which an import elsewhere finds defined, and a library alone in a file named for another
  actual:   (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

##### Mutations

74 cases ran on the final snapshot, which `diff -rq --no-dereference` showed identical to the
working tree: the review round's 71, A14 now a kill, and three mutations of rule (i). All 72
mutations were killed, each with every expected line present; `CLEAN` passed, and PH1 still
showed its phantom.

| ID | Change | Killed by |
|---|---|---|
| A14 | `(curl private extra)` a second form of `conditions.sls`, and `tests/curl/private/extra.sls` imported by native | check-seam, by rule (i): the file, and the library off its path |
| MI10 | rule (i) off | test-check-seam: `off-path`, `second-library`, `lock-symlink-live` |
| MI11 | a file's library count never read | test-check-seam: `off-path`, `second-library` |
| MI12 | a library's path never compared | test-check-seam: `off-path`, `second-library`, `lock-symlink-live` |


###### A14. A14, after rule (i)

**Guards:** every library under src/ stands alone at its name's path.

(The mutation is PRE-A14's.)

**Result:** killed, exit 2, 3 s, through `make test`:

```
check-seam: src/curl/private/conditions.sls: it holds 2 libraries, but Chez loads one library from a file, so each file under src/ holds exactly one
check-seam: src/curl/private/conditions.sls: (curl private extra) is defined here, but Chez loads it from src/curl/private/extra.sls, its name's path
```

###### MI10. rule (i) off

**Guards:** rule (i) itself.

**Mutation:** In `tests/check-seam.sps`:

```diff
@@ -560,3 +560,3 @@
         (cons (append (data-complaints path (cadr found) defined)
-                      (placement-complaints path (filter library-form? (cadr found)) root))
+                      '())
               (length (filter library-form? (cadr found))))
```

**Result:** killed, exit 2, 6 s, through `make test SUITES=tests/test-check-seam.sps`:

```
FAIL second-library: every library form in a file is checked, the second included; rule (i) names the file, and the second library, off its name's path
  expected: (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two-a.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: tests/fixtures/seam/second-library/curl/two-a.sls: it holds 2 libraries, but Chez loads one library from a file, so  [cut: 260 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two-a.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
FAIL off-path: rule (i): a second library in a file, which an import elsewhere finds defined, and a library alone in a file named for another
  expected: (1 "" "check-seam: tests/fixtures/seam/off-path/curl/a.sls: it holds 2 libraries, but Chez loads one library from a file, so each file under src/ holds exactly one\ncheck-seam: tests/fixtures/seam/off-path/curl/a.sls: (curl extra) is defined here, but Chez loads it from tests/fixtures/seam/off-path/curl/ext [cut: 221 more characters]
  actual:   (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
FAIL lock-symlink-live: a .# symbolic link that resolves to a library is no lock file: it is read, and named by rule (i), since the library it holds is not at its own name's path
  expected: (1 "" "check-seam: tests/fixtures/seam/lock-symlink-live/curl/.#real.sls: (curl real) is defined here, but Chez loads it from tests/fixtures/seam/lock-symlink-live/curl/real.sls, its name's path\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI11. a file's library count never read

**Guards:** a file holds one library.

**Mutation:** In `tests/check-seam.sps`:

```diff
@@ -538,3 +538,3 @@
   (append
-   (if (> (length libraries) 1)
+   (if #f
        (list (string-append path ": it holds " (number->string (length libraries))
```

**Result:** killed, exit 2, 6 s, through `make test SUITES=tests/test-check-seam.sps`:

```
FAIL second-library: every library form in a file is checked, the second included; rule (i) names the file, and the second library, off its name's path
  expected: (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two-a.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: tests/fixtures/seam/second-library/curl/two-a.sls: it holds 2 libraries, but Chez loads one library from a file, so  [cut: 260 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two-a.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: tests/fixtures/seam/second-library/curl/two-a.sls: (curl two-b) is defined here, but Chez loads it from tests/fixtur [cut: 92 more characters]
FAIL off-path: rule (i): a second library in a file, which an import elsewhere finds defined, and a library alone in a file named for another
  expected: (1 "" "check-seam: tests/fixtures/seam/off-path/curl/a.sls: it holds 2 libraries, but Chez loads one library from a file, so each file under src/ holds exactly one\ncheck-seam: tests/fixtures/seam/off-path/curl/a.sls: (curl extra) is defined here, but Chez loads it from tests/fixtures/seam/off-path/curl/ext [cut: 221 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/off-path/curl/a.sls: (curl extra) is defined here, but Chez loads it from tests/fixtures/seam/off-path/curl/extra.sls, its name's path\ncheck-seam: tests/fixtures/seam/off-path/curl/b.sls: (curl c) is defined here, but Chez loads it from tests/fixtures/seam/off-path/cu [cut: 63 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

###### MI12. a library's path never compared

**Guards:** a library stands at its name's path.

**Mutation:** In `tests/check-seam.sps`:

```diff
@@ -547,3 +547,3 @@
                         (want (library-path root name)))
-                   (if (string=? path want)
+                   (if #t
                        '()
```

**Result:** killed, exit 2, 5 s, through `make test SUITES=tests/test-check-seam.sps`:

```
FAIL second-library: every library form in a file is checked, the second included; rule (i) names the file, and the second library, off its name's path
  expected: (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two-a.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: tests/fixtures/seam/second-library/curl/two-a.sls: it holds 2 libraries, but Chez loads one library from a file, so  [cut: 260 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two-a.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: tests/fixtures/seam/second-library/curl/two-a.sls: it holds 2 libraries, but Chez loads one library from a file, so  [cut: 76 more characters]
FAIL off-path: rule (i): a second library in a file, which an import elsewhere finds defined, and a library alone in a file named for another
  expected: (1 "" "check-seam: tests/fixtures/seam/off-path/curl/a.sls: it holds 2 libraries, but Chez loads one library from a file, so each file under src/ holds exactly one\ncheck-seam: tests/fixtures/seam/off-path/curl/a.sls: (curl extra) is defined here, but Chez loads it from tests/fixtures/seam/off-path/curl/ext [cut: 221 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/off-path/curl/a.sls: it holds 2 libraries, but Chez loads one library from a file, so each file under src/ holds exactly one\ncheck-seam: FAILED (problems: 1)\n")
FAIL lock-symlink-live: a .# symbolic link that resolves to a library is no lock file: it is read, and named by rule (i), since the library it holds is not at its own name's path
  expected: (1 "" "check-seam: tests/fixtures/seam/lock-symlink-live/curl/.#real.sls: (curl real) is defined here, but Chez loads it from tests/fixtures/seam/lock-symlink-live/curl/real.sls, its name's path\ncheck-seam: FAILED (problems: 1)\n")
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

The review round's other 70, rerun: each as before.

| ID | Result |
|---|---|
| A1 | killed, exit 2 |
| A2 | killed, exit 2 |
| A3 | killed, exit 2 |
| A3P | killed, exit 2 |
| A4 | killed, exit 2 |
| A5 | killed, exit 2 |
| FPA4 | killed, exit 2 |
| D | killed, exit 2 |
| BR1 | killed, exit 2 |
| BR2 | killed, exit 2 |
| L | killed, exit 2 |
| WM1 | killed, exit 2 |
| WM2 | killed, exit 2 |
| WM3 | killed, exit 2 |
| WM4 | killed, exit 2 |
| WM5 | killed, exit 2 |
| WM6 | killed, exit 2 |
| CVF1 | killed, exit 2 |
| CVF2 | killed, exit 2 |
| CVF3 | killed, exit 2 |
| CVF4 | killed, exit 2 |
| CVF5 | killed, exit 2 |
| CVF6 | killed, exit 2 |
| CVF7 | killed, exit 2 |
| CVF8 | killed, exit 2 |
| CVF9 | killed, exit 2 |
| CLEAN | as expected, exit 0 |
| R0 | killed, exit 2 |
| MR1 | killed, exit 2 |
| MR2 | killed, exit 2 |
| MR3 | killed, exit 2 |
| MR4 | killed, exit 2 |
| MR5 | killed, exit 2 |
| MR6 | killed, exit 2 |
| MR7 | killed, exit 2 |
| MR8 | killed, exit 2 |
| MR9 | killed, exit 2 |
| MR10 | killed, exit 2 |
| MR11 | killed, exit 2 |
| MR12 | killed, exit 2 |
| MR13 | killed, exit 2 |
| SP1 | killed, exit 2 |
| SP2 | killed, exit 2 |
| SB1 | killed, exit 2 |
| R1 | killed, exit 2 |
| MI1 | killed, exit 2 |
| MI2 | killed, exit 2 |
| MI3 | killed, exit 2 |
| MI4 | killed, exit 2 |
| MI5 | killed, exit 2 |
| MI6 | killed, exit 2 |
| MI7 | killed, exit 2 |
| MI8 | killed, exit 2 |
| MI9 | killed, exit 2 |
| SA6 | killed, exit 2 |
| SA9 | killed, exit 2 |
| SA10 | killed, exit 2 |
| REV1 | killed, exit 2 |
| REV2 | killed, exit 2 |
| REV3 | killed, exit 2 |
| MK1 | killed, exit 2 |
| MK2 | killed, exit 2 |
| MK3 | killed, exit 2 |
| MK4 | killed, exit 2 |
| MK5 | killed, exit 2 |
| MK6 | killed, exit 2 |
| MK7 | killed, exit 2 |
| MK8 | killed, exit 2 |
| MK9 | killed, exit 2 |
| PH1 | as expected, exit 2 |

##### Clean rerun

On the working tree, in the container, after the last edit:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (15 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: ran 15, passed 15, failed 0, hung 0
check-variadic: all 19 steps ok, on ta6le
test-memory: ran 2, passed 2, failed 0, hung 0
check-test-fails: ok seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs
check-test-fails: make test failed, as it must, in all 10 cases
```

`make test-memory` ran with `MEMORY_SUITES="tests/test-variadic.sps tests/test-collect-safe.sps"`.
No Chez or Valgrind process was left behind. Apple arm64 is still pending, as above.

## `make dev` and `make clean`

The brief's M0 names both targets (§8). `dev` runs `deps` and `build`, then starts Chez's REPL
with `LIBDIRS`, the suites' library path. `clean` is `rm -rf build`, written out, with no
variable. Each has a check:

- `make check-dev` (`tests/check-dev.sh`) runs `make dev` through make, with forms piped in,
  in a fresh copy of the tree with no `build/`, so `make dev` must run `make deps` itself.
  - The **repl** case requires build's report, then the banner, then two lines,
    `check-dev: ok version VERSION` and `check-dev: ok path PATH (SOURCE)`, each exactly
    once and in that order. The forms print them only once `(curl)`, `(curl-testing)` and
    `(srfi :64)` have all imported. VERSION, PATH and SOURCE, read through `(curl)`, must
    equal what build named.
  - The **refused** case sets `CHEZ_CURL_LIBCURL` to a path naming no file. It requires make
    dev to fail with build's refusal, and no banner or line to appear.
  - A REPL that fails an import goes on and exits 0 at the end of its input, so the lines
    are the evidence.
- `make check-clean` (`tests/check-clean.sh`) works in a copy of the tree. It runs make deps,
  then plants a memory log, a nested directory, a hidden file, and three links out of
  `build/`: to a directory and a file outside the copy, and to the copy's `vendor/`. It
  lists every path outside `build/`, with checksums and link targets. Then:
  - make clean must exit 0 and leave no `build/`;
  - the listing must be unchanged;
  - a second make clean must pass;
  - make deps must work after it.

CI's main job runs both. `make test` runs neither: `check-dev` loads libcurl, and `make test`
does not depend on `build`.

### Red runs

The review found that the first `check-dev`, which ran in the tree itself, where `build/`
already existed, passed `dev: build`, without `deps`. On a fresh clone that `make dev` fails
with `library (srfi :64) not found`. The check now runs in a fresh copy and compares the path
too, and every case below was rerun against it.

Each mutation was planted in a plain copy of the tree, by exact-text replacement of one
Makefile recipe or one line of `tests/check-dev.sh`, and run through the copy's own
`scripts/guix-env`. Each exited 2, with these lines:

| Case | Mutation | Check's lines |
|---|---|---|
| D1 | `dev: deps`, without `build` | `check-dev: repl: build's report appears 0 times, not once` · `check-dev: refused: make dev passed with CHEZ_CURL_LIBCURL naming no file` |
| D2 | the REPL's `--libdirs src` alone | `check-dev: repl: the line "check-dev: ok version VERSION" appears 0 times, not once` |
| D3 | the recipe runs `true`, not the REPL | `check-dev: repl: the REPL's banner appears 0 times, not once` |
| D4 | the piped forms print `7.0.0`, not `(curl)`'s version | `check-dev: repl: the REPL loaded libcurl 7.0.0, but build named 8.20.0` |
| D5 | the REPL first, then `make build` | `check-dev: repl: build's report, the banner and the lines are out of order` · `check-dev: refused: a REPL started after build refused libcurl` |
| D6 | `dev: build`, without `deps` (the review's) | `check-dev: repl: the line "check-dev: ok version VERSION" appears 0 times, not once` |
| D7 | the piped forms print `/elsewhere/libcurl.so.4`, not `(curl)`'s path | `check-dev: repl: the REPL loaded /elsewhere/libcurl.so.4 (override), but build named /gnu/store/…-profile/lib/libcurl.so.4 (override)` |
| C1 | `rm -rf build/*` | `check-clean: make clean left build/ in place` |
| C2 | `rm -rf build vendor/chez-srfi/README.md` | `check-clean: make clean changed the tree outside build/` |
| C3 | `rm -rf build/to-outside-dir/* build`, following a link | `check-clean: make clean followed a link out of build/` |
| C4 | `rm -r build`, which fails with no `build/` | `check-clean: make clean failed with no build/` |

**Clean:** on the unchanged tree, both pass: `check-dev: ok: in a fresh copy, make dev runs
deps and build, then a REPL with the suites' library path and build's libcurl; a refused
libcurl stops it`, and `check-clean: ok: make clean removes build/, follows no link out of
it, changes nothing else, passes again, and make deps works after it`.

## Measurements at the floor

The suites have never run against 7.85.0: CI has not run. So the facts `test-variadic` rests
on were measured in C, against three libraries:
- 7.85.0, the floor, built by `scripts/ci/build-curl.sh` in a fresh `ubuntu:24.04` container,
  with OpenSSL 3.0.13;
- Ubuntu 24.04's own 8.5.0, in the same container;
- Guix's 8.20.0, in the development container.

The program looked each option up with `curl_easy_option_by_name` and called
`curl_easy_setopt` and `curl_easy_getinfo` on one fresh handle.

| | 7.85.0 | 8.5.0 | 8.20.0 |
|---|---|---|---|
| `PRIVATE` id, type | 10103, 3 | 10103, 3 | 10103, 3 |
| `RTSP_CLIENT_CSEQ` id, type | 193, 0 | 193, 0 | 193, 0 |
| `MAXFILESIZE_LARGE` id, type | 30117, 2 | 30117, 2 | 30117, 2 |
| `MAXFILESIZE` id, type | 114, 0 | 114, 0 | not run |
| `PRIVATE` 0x0123456789abcdef, read back | exact | exact | exact |
| `RTSP_CLIENT_CSEQ` 123456789, read back | exact | exact | exact |
| `RTSP_CLIENT_CSEQ` 4886718345 (above 2^32) | exact | exact | 2147483647 |
| `RTSP_CLIENT_CSEQ` -5: setopt's code, then read back | 0, -5 | 0, -5 | 43, the old value |
| `MAXFILESIZE_LARGE` 0, -1, -(2^62), 2^62 | 0 43 43 0 | 0 43 43 0 | 0 43 43 0 |
| `MAXFILESIZE` 0, -1, 2^40, -(2^40) | 0 43 0 43 | 0 43 0 43 | not run |
| protocols include `rtsp` | yes | yes | yes |

The review measured `MAXFILESIZE` on 8.20.0 and 8.6.0, through the suite. Apple's 8.7.1 is
shown only by the maintainer's run.
