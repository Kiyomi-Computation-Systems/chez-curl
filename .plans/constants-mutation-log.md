# Constants and layouts mutation log (M0 slice 4)

Evidence for the checks M0 slice 4 added, one part per agent, the review's fixes last:

1. [Constants and layouts](#constants-and-layouts): `tests/test-constants.sps` and
   `(curl private layouts)` (ADR-0001, decisions 3 and 4).
2. [The collect-safe suite](#the-collect-safe-suite): `tests/test-collect-safe.sps` and
   `(foreign-conventions)` (ADR-0013).
3. [The floors](#the-floors): `packaging/floors.sexp`, `make check-floors` and the suites' floor
   rows (ADR-0016).
4. [Review fixes: test-constants](#review-fixes-test-constants): the headers' version against
   the loaded library, each field's kind, and C names derived from export names.
5. [Review fixes: define-ftype only in layouts](#review-fixes-define-ftype-only-in-layouts):
   `check-seam`'s rule (f) (ADR-0007).
6. [Second review fixes](#second-review-fixes): `check-seam`'s rule (g), `layouts.sls` held to
   an exact shape, the kind map, and derived prefixes.

Each part's driver kept every run's whole output in the session scratchpad. This log cuts a
diff to its first 15 lines and an output to its first 19, and says how many lines were cut.
Every kept line is a diff line, a `FAIL` line with its expected and actual values, or a
check's own verdict line.

## Constants and layouts

Evidence that the check M0 slice 4's first part added fails through each property it claims
to guard ([ADR-0001](decisions/0001-bind-libcurl-directly.md), decisions 3 and 4). The part
is:

- `src/curl/private/layouts.sls`, new: `(curl private layouts)`, which holds
  `curl-version-info-data`, moved out of `native.sls`. It never loads libcurl;
- `src/curl/private/native.sls`, which imports it, and no longer imports `define-ftype`;
- `tests/test-constants.sps`, new. It reads `constants.sls` for its exports and
  `layouts.sls` for its `define-ftype`s, as data, and holds a table row for each. It
  generates one C program from those rows, compiles it with `$CC` and no `-I` flag, runs
  it, and reads its output as data. Each constant's value, each feature bit, and each
  field's offset and size are compared with the headers'.

A driver in the session scratchpad ran every mutation. It froze a snapshot of the working
tree, without `.git`, `build/` or `.claude/`, and gave each mutation a fresh copy of it. It
applied the mutation by exact-text replacement, aborting unless the target occurred exactly
once, and refused a mutation whose diff was empty unless it changed only the environment. It
touched the copy's `manifest.scm` (`traps.md`, the stale `guix shell -m` profile) and ran
`scripts/guix-env make test` from inside the copy, so the container saw only that copy. An
environment case put its assignment before `make test` inside the container. A mutation
counts as killed only when `make test` exits non-zero and every expected line appears whole
in its output: the case's `FAIL <test name>` lines, with their expected and actual values
where the case is about a value, and `test: FAIL tests/test-constants.sps (exit 1)`. For a
failed compile or run, the actual line must also show what went wrong: the undeclared name
(CN6, CV3), the missing `curl/curl.h` (EV1), the raise (EV3), Guix's locale warning (TS5), or
the program's output (TS6, TS7). This log cuts long outputs (see the top). The working tree was never edited.

**Result** quotes only the `FAIL` lines, each with its expected and actual lines, and the
`test: FAIL` lines, from every suite. CV6 never reaches a suite, so it quotes `check-seam`'s
lines and make's. Each diff keeps one line of context, and `...` sets its hunks
apart. A diff line longer than 200 characters, and an output line longer than 240, is cut,
and says how much was cut.

Cases are named `CN` (constant values), `CV` (constant coverage and the read of
`constants.sls`), `LY` (layouts), `EV` (the environment) and `TS` (the suite's own reads,
runs and checks).

### Red runs

**Before `layouts.sls` existed:** `tests/test-constants.sps` written, and `native.sls` still holding
the ftype. `make test` exited 2. The suite ran: every constant and feature bit already matched
the headers, and three tests failed by name, each for want of `layouts.sls`:

```
FAIL layouts.sls is read: a library with a define-ftype, at least one
  expected: read
  actual:   (unreadable "src/curl/private/layouts.sls" "Exception in open-file-input-port: failed for src/curl/private/layouts.sls: no such file or directory")
FAIL layout-rows' row curl-version-info-data is a define-ftype in layouts.sls
  expected: defined
  actual:   not-defined
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
  actual:   (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth)
test: FAIL tests/test-constants.sps (exit 1)
test: ran 11, passed 10, failed 1, hung 0
```

### Baseline

`layouts.sls` written, the ftype moved into it, and `native.sls` importing it. This is the
snapshot every mutation copied; it is byte-identical to the working tree at the clean rerun.
`make test` exited 0, with 85 tests passing in `test-constants`:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (11 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
test: pass tests/test-check-seam.sps
test: pass tests/test-conditions.sps
test: pass tests/test-constants.sps
test: pass tests/test-curl-testing.sps
test: pass tests/test-discovery.sps
test: pass tests/test-library-loading.sps
test: pass tests/test-load-state.sps
test: pass tests/test-manifest.sps
test: pass tests/test-native.sps
test: pass tests/test-require-threaded.sps
test: pass tests/test-verify.sps
test: ran 11, passed 11, failed 0, hung 0
```

### Mutations

34 mutations ran, and all 34 were killed, each with every expected line present.
Two were killed outside this suite, as expected: CV6 by `check-seam`, which reads
`constants.sls` before any suite runs, and CN7 by `test-verify`. This suite checks each feature
entry against its C constant, but not that the list holds every bit the header defines.

Every one of the suite's 85 tests was failed by name by at least one mutant, except six
instances of "constants.sls exports X, and constant-rows has a row for it". That rule fails
under CV1 and CV2. Each of the 62 per-constant and per-field tests fails under every case
where the C program gives no answer, with `(no-answer ...)` as its expected value. That is
why CN6, CV3, EV1 to EV3, TS1 and TS5 to TS7 each list 62 or more FAILs from this suite.

### CN1. `curl-version-ssl` changed to `#x8`

**Guards:** each constant equals its C expression.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
   ;; curl/curl.h: CURL_VERSION_SSL, (1<<2). Required at load (ADR-0002).
-  (define curl-version-ssl #x00000004)
+  (define curl-version-ssl #x8)
 
```
**Result:** killed, exit 2:

```
FAIL curl-version-ssl is CURL_VERSION_SSL
  expected: 4
  actual:   8
test: FAIL tests/test-constants.sps (exit 1)
FAIL decoy no-ssl: no CURL_VERSION_SSL is no-ssl, and nothing runs after curl_version_info
  expected: (0 1 ((reason . no-ssl) (path . "/tmp/tmp.ppndD7gKhI/no-ssl.so") (source . override) (detail . "7.85.0") (candidates) (library "/tmp/tmp.ppndD7gKhI/no-ssl.so" override "7.85.0" 480512 9 "DecoyTLS/1.0" "decoy-host") (again same s [cut: 42 more characters]
  actual:   (0 0 ((loaded . "/tmp/tmp.ppndD7gKhI/no-ssl.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 9) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info(9 [cut: 151 more characters]
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL check-version: every feature but SSL is no-ssl, with the version, path and source
  expected: (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "8.20.0" () the-report)
  actual:   (returned #t)
FAIL check-version: SSL, 1<<2, alone is enough
  expected: (returned #t)
  actual:   (refused no-ssl "/usr/lib/aarch64-linux-gnu/libcurl.so.4" override "8.20.0" () the-report)
test: FAIL tests/test-verify.sps (exit 1)
```

### CN2. the `http2` feature bit wrong, `1<<17`

**Guards:** each feature entry equals its CURL_VERSION_ bit.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
       (ntlm-wb      . #x00008000)     ; CURL_VERSION_NTLM_WB      (1<<15)
-      (http2        . #x00010000)     ; CURL_VERSION_HTTP2        (1<<16)
+      (http2        . #x00020000)     ; CURL_VERSION_HTTP2        (1<<16)
       (gssapi       . #x00020000)     ; CURL_VERSION_GSSAPI       (1<<17)
```
**Result:** killed, exit 2:

```
FAIL curl-version-features: http2 is CURL_VERSION_HTTP2
  expected: 65536
  actual:   131072
test: FAIL tests/test-constants.sps (exit 1)
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  expected: (0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/tmp.WWIgh98xWx/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")
  actual:   (0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/tmp.WWIgh98xWx/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz threadsafe 65536\n  host:     decoy-host\n" "")
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
  expected: (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       /tmp/tmp.WWIgh98xWx/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl  [cut: 156 more characters]
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       /tmp/tmp.WWIgh98xWx/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl  [cut: 156 more characters]
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL feature-names: each bit alone names its own CURL_VERSION_ feature
  expected: ((ipv6) (kerberos4) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (http2) (gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi-ssl)  [cut: 71 more characters]
  actual:   ((ipv6) (kerberos4) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (65536) (http2 gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi [cut: 77 more characters]
FAIL feature-names: every bit set names every feature, in curl.h's order
  expected: (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl th [cut: 9 more characters]
  actual:   (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl th [cut: 15 more characters]
FAIL feature-names: only the bits that are set
  expected: (ipv6 ssl http2 threadsafe)
[2 more lines cut]
```

### CN3. `curlhe-not-built-in` off by one, 8

**Guards:** each constant equals its C expression.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
   ;; curl_easy_header answers in a build without the header API (ADR-0003).
-  (define curlhe-not-built-in 7)
+  (define curlhe-not-built-in 8)
 
```
**Result:** killed, exit 2:

```
FAIL curlhe-not-built-in is CURLHE_NOT_BUILT_IN
  expected: 7
  actual:   8
test: FAIL tests/test-constants.sps (exit 1)
FAIL decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  expected: (0 1 ((reason . missing-api) (path . "/tmp/tmp.GlSTuW5Iwh/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "/tmp/tmp.GlSTuW5Iwh/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTL [cut: 219 more characters]
  actual:   (0 0 ((loaded . "/tmp/tmp.GlSTuW5Iwh/headers-off.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_ [cut: 165 more characters]
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL check-apis: header code 7, CURLHE_NOT_BUILT_IN, is missing-api, naming curl_easy_header
  expected: (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" guix-system "curl_easy_header" () the-report)
  actual:   (returned #t)
FAIL check-apis: every other header code is accepted
  expected: ((returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t))
  actual:   ((returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (returned #t) (refused missing-api "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "curl_easy_header" () the-report) (returned #t))
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (readable readable readable no-raise)
test: FAIL tests/test-verify.sps (exit 1)
```

### CN4. a feature entry written as a bare name, `http2`

**Guards:** an (each PREFIX) row's value is a non-empty list of (name . value), each name a symbol.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
       (ntlm-wb      . #x00008000)     ; CURL_VERSION_NTLM_WB      (1<<15)
-      (http2        . #x00010000)     ; CURL_VERSION_HTTP2        (1<<16)
+      http2     ; CURL_VERSION_HTTP2        (1<<16)
       (gssapi       . #x00020000)     ; CURL_VERSION_GSSAPI       (1<<17)
```
**Result:** killed, exit 2:

```
FAIL constants.sls: curl-version-features is a non-empty list of (name . value), each name a symbol
  expected: entries
  actual:   ((ipv6 . 1) (kerberos4 . 2) (ssl . 4) (libz . 8) (ntlm . 16) (gssnegotiate . 32) (debug . 64) (asynchdns . 128) (spnego . 256) (largefile . 512) (idn . 1024) (sspi . 2048) (conv . 4096) (curldebug . 8192) (tlsauth-srp . 16384) ( [cut: 311 more characters]
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
  actual:   (curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
test: FAIL tests/test-constants.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 255)
test: FAIL tests/test-native.sps (exit 255)
test: FAIL tests/test-verify.sps (exit 255)
```

### CN5. the feature list emptied

**Guards:** an (each PREFIX) row's value is a non-empty list: an empty one checks nothing.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
   (define curl-version-features
-    '((ipv6         . #x00000001)     ; CURL_VERSION_IPV6         (1<<0)
-      (kerberos4    . #x00000002)     ; CURL_VERSION_KERBEROS4    (1<<1)
-      (ssl          . #x00000004)     ; CURL_VERSION_SSL          (1<<2)
-      (libz         . #x00000008)     ; CURL_VERSION_LIBZ         (1<<3)
-      (ntlm         . #x00000010)     ; CURL_VERSION_NTLM         (1<<4)
-      (gssnegotiate . #x00000020)     ; CURL_VERSION_GSSNEGOTIATE (1<<5)
-      (debug        . #x00000040)     ; CURL_VERSION_DEBUG        (1<<6)
-      (asynchdns    . #x00000080)     ; CURL_VERSION_ASYNCHDNS    (1<<7)
-      (spnego       . #x00000100)     ; CURL_VERSION_SPNEGO       (1<<8)
-      (largefile    . #x00000200)     ; CURL_VERSION_LARGEFILE    (1<<9)
-      (idn          . #x00000400)     ; CURL_VERSION_IDN          (1<<10)
-      (sspi         . #x00000800)     ; CURL_VERSION_SSPI         (1<<11)
-      (conv         . #x00001000)     ; CURL_VERSION_CONV         (1<<12)
-      (curldebug    . #x00002000)     ; CURL_VERSION_CURLDEBUG    (1<<13)
[19 more lines cut]
```
**Result:** killed, exit 2:

```
FAIL constants.sls: curl-version-features is a non-empty list of (name . value), each name a symbol
  expected: entries
  actual:   ()
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
  actual:   (curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
test: FAIL tests/test-constants.sps (exit 1)
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  expected: (0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/tmp.XrOf4zi2PM/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")
  actual:   (0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/tmp.XrOf4zi2PM/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: 1 4 8 65536 1073741824\n  host:     decoy-host\n" "")
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
  expected: (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       /tmp/tmp.XrOf4zi2PM/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl  [cut: 156 more characters]
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       /tmp/tmp.XrOf4zi2PM/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   1 4 8 655 [cut: 148 more characters]
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL feature-names: each bit alone names its own CURL_VERSION_ feature
  expected: ((ipv6) (kerberos4) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (http2) (gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi-ssl)  [cut: 71 more characters]
  actual:   ((1) (2) (4) (8) (16) (32) (64) (128) (256) (512) (1024) (2048) (4096) (8192) (16384) (32768) (65536) (131072) (262144) (524288) (1048576) (2097152) (4194304) (8388608) (16777216) (33554432) (67108864) (134217728) (268435456) (5 [cut: 23 more characters]
FAIL feature-names: every bit set names every feature, in curl.h's order
  expected: (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl th [cut: 9 more characters]
[8 more lines cut]
```

### CN6. a feature renamed, `unix-sockets` to `unix-socket`

**Guards:** each feature's C name is made from its Scheme name, and must exist.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
       (kerberos5    . #x00040000)     ; CURL_VERSION_KERBEROS5    (1<<18)
-      (unix-sockets . #x00080000)     ; CURL_VERSION_UNIX_SOCKETS (1<<19)
+      (unix-socket  . #x00080000)     ; CURL_VERSION_UNIX_SOCKETS (1<<19)
       (psl          . #x00100000)     ; CURL_VERSION_PSL          (1<<20)
```
**Result:** killed, exit 2:

```
FAIL the C program compiled against libcurl's headers and ran
  expected: ran
  actual:   (compile 1 "" "/tmp/tmp.N6v2nlUryf/headers.c: In function 'main':\n/tmp/tmp.N6v2nlUryf/headers.c:30:12: error: 'CURL_VERSION_UNIX_SOCKET' undeclared (first use in this function); did you mean 'CURL_VERSION_UNIX_SOCKETS'?\n   30  [cut: 713 more characters]
FAIL the C program answered every question, in order
  expected: ((constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "CURL_VERSION_DEBUG [cut: 2171 more characters]
  actual:   ()
FAIL curl-version-features: ipv6 is CURL_VERSION_IPV6
  expected: (no-answer constant "CURL_VERSION_IPV6")
  actual:   1
FAIL curl-version-features: kerberos4 is CURL_VERSION_KERBEROS4
  expected: (no-answer constant "CURL_VERSION_KERBEROS4")
  actual:   2
FAIL curl-version-features: ssl is CURL_VERSION_SSL
  expected: (no-answer constant "CURL_VERSION_SSL")
  actual:   4
FAIL curl-version-features: libz is CURL_VERSION_LIBZ
  expected: (no-answer constant "CURL_VERSION_LIBZ")
  actual:   8
FAIL curl-version-features: ntlm is CURL_VERSION_NTLM
[181 more lines cut]
```

### CN7. the `http2` entry deleted from the feature list

**Guards:** nothing here: this suite checks each entry against C, not that the list is whole. test-verify holds the whole list.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
       (ntlm-wb      . #x00008000)     ; CURL_VERSION_NTLM_WB      (1<<15)
-      (http2        . #x00010000)     ; CURL_VERSION_HTTP2        (1<<16)
       (gssapi       . #x00020000)     ; CURL_VERSION_GSSAPI       (1<<17)
```
**Result:** killed, exit 2:

```
FAIL preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  expected: (0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/tmp.vpoCgSWasy/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")
  actual:   (0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/tmp.vpoCgSWasy/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz threadsafe 65536\n  host:     decoy-host\n" "")
FAIL preflight, the below-floor decoy: exit 1, naming the version, TLS and features it read
  expected: (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       /tmp/tmp.vpoCgSWasy/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl  [cut: 156 more characters]
  actual:   (1 "" "chez-curl: libcurl refused\n(reason . below-floor)\n  path:       /tmp/tmp.vpoCgSWasy/below-floor.so\n  source:     override\n  detail:     7.84.0\n  version:    7.84.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl  [cut: 156 more characters]
test: FAIL tests/test-library-loading.sps (exit 1)
FAIL feature-names: each bit alone names its own CURL_VERSION_ feature
  expected: ((ipv6) (kerberos4) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (http2) (gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi-ssl)  [cut: 71 more characters]
  actual:   ((ipv6) (kerberos4) (ssl) (libz) (ntlm) (gssnegotiate) (debug) (asynchdns) (spnego) (largefile) (idn) (sspi) (conv) (curldebug) (tlsauth-srp) (ntlm-wb) (65536) (gssapi) (kerberos5) (unix-sockets) (psl) (https-proxy) (multi-ssl)  [cut: 71 more characters]
FAIL feature-names: every bit set names every feature, in curl.h's order
  expected: (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb http2 gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl th [cut: 9 more characters]
  actual:   (ipv6 kerberos4 ssl libz ntlm gssnegotiate debug asynchdns spnego largefile idn sspi conv curldebug tlsauth-srp ntlm-wb gssapi kerberos5 unix-sockets psl https-proxy multi-ssl brotli altsvc http3 zstd unicode hsts gsasl threadsa [cut: 9 more characters]
FAIL feature-names: only the bits that are set
  expected: (ipv6 ssl http2 threadsafe)
  actual:   (ipv6 ssl threadsafe 65536)
test: FAIL tests/test-verify.sps (exit 1)
```

### CV1. a new export in `constants.sls` with no row

**Guards:** every export has a row.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
           curlhe-not-built-in curlh-header curl-global-default curle-ok
-          curlversion-tenth)
+          curlversion-tenth curle-unsupported-protocol)
   (import (curl private require-threaded)
...
   ;; headers: it is CURLVERSION_TWELFTH in 8.20.0.
-  (define curlversion-tenth 9))
+  (define curlversion-tenth 9)
+
+  (define curle-unsupported-protocol 1))
```
**Result:** killed, exit 2:

```
FAIL constants.sls exports curle-unsupported-protocol, and constant-rows has a row for it
  expected: row
  actual:   no-row
test: FAIL tests/test-constants.sps (exit 1)
```

### CV2. the row for `curlh-header` removed from the suite

**Guards:** every export has a row.
**Mutation:** In `tests/test-constants.sps`:

```diff
     (curlhe-not-built-in . "CURLHE_NOT_BUILT_IN")
-    (curlh-header . "CURLH_HEADER")
     (curl-global-default . "CURL_GLOBAL_DEFAULT")
```
**Result:** killed, exit 2:

```
FAIL constants.sls exports curlh-header, and constant-rows has a row for it
  expected: row
  actual:   no-row
test: FAIL tests/test-constants.sps (exit 1)
```

### CV3. a row naming a C constant that does not exist, `CURLE_OKAY`

**Guards:** the program compiles, and a failed compile shows the compiler's output.
**Mutation:** In `tests/test-constants.sps`:

```diff
     (curl-global-default . "CURL_GLOBAL_DEFAULT")
-    (curle-ok . "CURLE_OK")
+    (curle-ok . "CURLE_OKAY")
     (curlversion-tenth . "CURLVERSION_TENTH")))
```
**Result:** killed, exit 2:

```
FAIL the C program compiled against libcurl's headers and ran
  expected: ran
  actual:   (compile 1 "" "/tmp/tmp.jfjuEHXFrT/headers.c: In function 'main':\n/tmp/tmp.jfjuEHXFrT/headers.c:46:12: error: 'CURLE_OKAY' undeclared (first use in this function); did you mean 'CURLE_OK'?\n   46 |   CONSTANT(CURLE_OKAY);\n     [cut: 654 more characters]
FAIL the C program answered every question, in order
  expected: ((constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "CURL_VERSION_DEBUG [cut: 2174 more characters]
  actual:   ()
FAIL curl-version-features: ipv6 is CURL_VERSION_IPV6
  expected: (no-answer constant "CURL_VERSION_IPV6")
  actual:   1
FAIL curl-version-features: kerberos4 is CURL_VERSION_KERBEROS4
  expected: (no-answer constant "CURL_VERSION_KERBEROS4")
  actual:   2
FAIL curl-version-features: ssl is CURL_VERSION_SSL
  expected: (no-answer constant "CURL_VERSION_SSL")
  actual:   4
FAIL curl-version-features: libz is CURL_VERSION_LIBZ
  expected: (no-answer constant "CURL_VERSION_LIBZ")
  actual:   8
FAIL curl-version-features: ntlm is CURL_VERSION_NTLM
[174 more lines cut]
```

### CV4. a row with no export, `curle-again`

**Guards:** every row is an export.
**Mutation:** In `tests/test-constants.sps`:

```diff
     (curle-ok . "CURLE_OK")
-    (curlversion-tenth . "CURLVERSION_TENTH")))
+    (curlversion-tenth . "CURLVERSION_TENTH")
+    (curle-again . "CURLE_AGAIN")))
 
```
**Result:** killed, exit 2:

```
FAIL constant-rows' row curle-again is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL curle-again is CURLE_AGAIN
  expected: 81
  actual:   (no-value "Exception: attempt to reference unbound identifier curle-again")
test: FAIL tests/test-constants.sps (exit 1)
```

### CV5. an export written as a `rename`

**Guards:** the export list is read only when every export is an identifier.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
 (library (curl private constants)
-  (export curl-version-features curl-version-ssl
+  (export curl-version-features (rename (curl-version-ssl curl-version-ssl))
           curlhe-not-built-in curlh-header curl-global-default curle-ok
```
**Result:** killed, exit 2:

```
FAIL constants.sls is read: a library whose exports are identifiers, at least one
  expected: read
  actual:   (exports-not-identifiers ((rename (curl-version-ssl curl-version-ssl))))
FAIL constant-rows' row curl-version-features is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curl-version-ssl is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curlhe-not-built-in is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curlh-header is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curl-global-default is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curle-ok is an export of constants.sls
[6 more lines cut]
```

### CV6. `constants.sls` holds no library form: `export` misspelt

**Guards:** the read finds a library form; here check-seam finds it first.
**Mutation:** In `src/curl/private/constants.sls`:

```diff
 (library (curl private constants)
-  (export curl-version-features curl-version-ssl
+  (exports curl-version-features curl-version-ssl
           curlhe-not-built-in curlh-header curl-global-default curle-ok
```
**Result:** killed, exit 2:

```
check-seam: src/curl/private/constants.sls: datum 1 is (library (curl private constants) (exports curl-version-f..., not a library form
check-seam: FAILED (problems: 1)
make: *** [Makefile:235: check-seam] Error 1
```

### CV7. the suite reads a file with no library form: `constants-source` pointed at a program

**Guards:** the read finds a library form (CV6 cannot reach it: check-seam runs first).
**Mutation:** In `tests/test-constants.sps`:

```diff
 
-(define constants-source "src/curl/private/constants.sls")
+(define constants-source "tests/preflight.sps")
 (define layouts-source "src/curl/private/layouts.sls")
```
**Result:** killed, exit 2:

```
FAIL constants.sls is read: a library whose exports are identifiers, at least one
  expected: read
  actual:   (no-library-form "tests/preflight.sps")
FAIL constant-rows' row curl-version-features is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curl-version-ssl is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curlhe-not-built-in is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curlh-header is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curl-global-default is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curle-ok is an export of constants.sls
[6 more lines cut]
```

### LY1. `ssl-version-num` declared `int`, not `long`

**Guards:** each field's size is C's: the offsets all still match.
**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (ssl-version uptr)
-      (ssl-version-num long)
+      (ssl-version-num int)
       (libz-version uptr)
```
**Result:** killed, exit 2:

```
FAIL curl_version_info_data.ssl_version_num has the header's offset and size
  expected: (offset 48 size 8)
  actual:   (offset 48 size 4)
test: FAIL tests/test-constants.sps (exit 1)
```

### LY2. `host` and `version-num` swapped

**Guards:** each field's offset is C's.
**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (version uptr)
-      (version-num unsigned-int)
       (host uptr)
+      (version-num unsigned-int)
       (features unsigned-int)
```
**Result:** killed, exit 2:

```
FAIL curl_version_info_data.host has the header's offset and size
  expected: (offset 24 size 8)
  actual:   (offset 16 size 8)
FAIL curl_version_info_data.version_num has the header's offset and size
  expected: (offset 16 size 4)
  actual:   (offset 24 size 4)
FAIL curl_version_info_data.features has the header's offset and size
  expected: (offset 32 size 4)
  actual:   (offset 28 size 4)
FAIL curl_version_info_data.ssl_version has the header's offset and size
  expected: (offset 40 size 8)
  actual:   (offset 32 size 8)
FAIL curl_version_info_data.ssl_version_num has the header's offset and size
  expected: (offset 48 size 8)
  actual:   (offset 40 size 8)
FAIL curl_version_info_data.libz_version has the header's offset and size
  expected: (offset 56 size 8)
  actual:   (offset 48 size 8)
FAIL curl_version_info_data.protocols has the header's offset and size
[137 more lines cut]
```

### LY3. a middle field, `ares-num`, deleted

**Guards:** each field's offset is C's.
**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (ares uptr)
-      (ares-num int)
       (libidn uptr)
```
**Result:** killed, exit 2:

```
FAIL curl_version_info_data.libidn has the header's offset and size
  expected: (offset 88 size 8)
  actual:   (offset 80 size 8)
FAIL curl_version_info_data.iconv_ver_num has the header's offset and size
  expected: (offset 96 size 4)
  actual:   (offset 88 size 4)
FAIL curl_version_info_data.libssh_version has the header's offset and size
  expected: (offset 104 size 8)
  actual:   (offset 96 size 8)
FAIL curl_version_info_data.brotli_ver_num has the header's offset and size
  expected: (offset 112 size 4)
  actual:   (offset 104 size 4)
FAIL curl_version_info_data.brotli_version has the header's offset and size
  expected: (offset 120 size 8)
  actual:   (offset 112 size 8)
FAIL curl_version_info_data.nghttp2_ver_num has the header's offset and size
  expected: (offset 128 size 4)
  actual:   (offset 120 size 4)
FAIL curl_version_info_data.nghttp2_version has the header's offset and size
[24 more lines cut]
```

### LY4. a second `define-ftype` with no row

**Guards:** every define-ftype has a row.
**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-ftype curl-waitfd
+    (struct (fd int) (events short) (revents short))))
```
**Result:** killed, exit 2:

```
FAIL layouts.sls defines the ftype curl-waitfd, and layout-rows has a row for it
  expected: row
  actual:   no-row
test: FAIL tests/test-constants.sps (exit 1)
```

### LY5. a field made an array, `(hyper-version (array 1 uptr))`

**Guards:** each define-ftype is a struct of primitive-typed fields: a field that is not.
**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (zstd-version uptr)
-      (hyper-version uptr)
+      (hyper-version (array 1 uptr))
       (gsasl-version uptr))))
```
**Result:** killed, exit 2:

```
FAIL layouts.sls: curl-version-info-data is a struct of primitive-typed fields
  expected: handled
  actual:   (unhandled (hyper-version (array 1 uptr)))
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
  actual:   (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth)
test: FAIL tests/test-constants.sps (exit 1)
```

### LY6. a row with no `define-ftype`, `curl-msg`

**Guards:** every layout row is a define-ftype.
**Mutation:** In `tests/test-constants.sps`:

```diff
 (define layout-rows
-  '((curl-version-info-data . "curl_version_info_data")))
+  '((curl-version-info-data . "curl_version_info_data")
+    (curl-msg . "CURLMsg")))
 
```
**Result:** killed, exit 2:

```
FAIL layout-rows' row curl-msg is a define-ftype in layouts.sls
  expected: defined
  actual:   not-defined
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data curl-msg)
  actual:   (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
test: FAIL tests/test-constants.sps (exit 1)
```

### LY7. an ftype that is not a struct, `curl-socket`, with a row

**Guards:** each define-ftype is a struct: a type that is not.
**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-ftype curl-socket int))
```
**Mutation:** In `tests/test-constants.sps`:

```diff
 (define layout-rows
-  '((curl-version-info-data . "curl_version_info_data")))
+  '((curl-version-info-data . "curl_version_info_data")
+    (curl-socket . "curl_socket_t")))
 
```
**Result:** killed, exit 2:

```
FAIL layouts.sls: curl-socket is a struct of primitive-typed fields
  expected: handled
  actual:   (unhandled int)
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data curl-socket)
  actual:   (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
test: FAIL tests/test-constants.sps (exit 1)
```

### LY8. a `define-ftype` of two clauses

**Guards:** each define-ftype is (define-ftype NAME TYPE): a form that is not.
**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-ftype (curl-a (struct (x int))) (curl-b (struct (y int)))))
```
**Result:** killed, exit 2:

```
FAIL layouts.sls defines the ftype (define-ftype (curl-a (struct (x int))) (curl-b (struct (y int)))), and layout-rows has a row for it
  expected: row
  actual:   no-row
FAIL layouts.sls: (define-ftype (curl-a (struct (x int))) (curl-b (struct (y int)))) is a struct of primitive-typed fields
  expected: handled
  actual:   (unhandled (define-ftype (curl-a (struct (x int))) (curl-b (struct (y int)))))
test: FAIL tests/test-constants.sps (exit 1)
```

### LY9. a field typed by another ftype, `curl-ares-num`

**Guards:** each field's type is one foreign-sizeof knows: an ftype's name is not.
**Mutation:** In `src/curl/private/layouts.sls`:

```diff
   ;; takes a natural number.
+  (define-ftype curl-ares-num int)
+
   (define-ftype curl-version-info-data
...
       (ares uptr)
-      (ares-num int)
+      (ares-num curl-ares-num)
       (libidn uptr)
```
**Result:** killed, exit 2:

```
FAIL layouts.sls defines the ftype curl-ares-num, and layout-rows has a row for it
  expected: row
  actual:   no-row
FAIL layouts.sls: curl-ares-num is a struct of primitive-typed fields
  expected: handled
  actual:   (unhandled int)
FAIL layouts.sls: curl-version-info-data is a struct of primitive-typed fields
  expected: handled
  actual:   (unhandled (ares-num curl-ares-num))
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
  actual:   (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth)
test: FAIL tests/test-constants.sps (exit 1)
```

### LY10. the row for `curl-version-info-data` removed from the suite

**Guards:** every define-ftype has a row: the one layouts.sls holds.
**Mutation:** In `tests/test-constants.sps`:

```diff
 (define layout-rows
-  '((curl-version-info-data . "curl_version_info_data")))
+  '())
 
```
**Result:** killed, exit 2:

```
FAIL layouts.sls defines the ftype curl-version-info-data, and layout-rows has a row for it
  expected: row
  actual:   no-row
test: FAIL tests/test-constants.sps (exit 1)
```

### EV1. headers missing: `C_INCLUDE_PATH` emptied

**Guards:** missing headers fail, never skip.
**Mutation:** no file changed. The container ran `C_INCLUDE_PATH= make test`.
**Result:** killed, exit 2:

```
FAIL the C program compiled against libcurl's headers and ran
  expected: ran
  actual:   (compile 1 "" "/tmp/tmp.CKpmBxR8ZM/headers.c:1:10: fatal error: curl/curl.h: No such file or directory\n    1 | #include <curl/curl.h>\n      |          ^~~~~~~~~~~~~\ncompilation terminated.\n")
FAIL the C program answered every question, in order
  expected: ((constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "CURL_VERSION_DEBUG [cut: 2172 more characters]
  actual:   ()
FAIL curl-version-features: ipv6 is CURL_VERSION_IPV6
  expected: (no-answer constant "CURL_VERSION_IPV6")
  actual:   1
FAIL curl-version-features: kerberos4 is CURL_VERSION_KERBEROS4
  expected: (no-answer constant "CURL_VERSION_KERBEROS4")
  actual:   2
FAIL curl-version-features: ssl is CURL_VERSION_SSL
  expected: (no-answer constant "CURL_VERSION_SSL")
  actual:   4
FAIL curl-version-features: libz is CURL_VERSION_LIBZ
  expected: (no-answer constant "CURL_VERSION_LIBZ")
  actual:   8
FAIL curl-version-features: ntlm is CURL_VERSION_NTLM
[284 more lines cut]
```

### EV2. no compiler: `CC=false`

**Guards:** a failed compile fails.
**Mutation:** no file changed. The container ran `CC=false make test`.
**Result:** killed, exit 2:

```
FAIL the C program compiled against libcurl's headers and ran
  expected: ran
  actual:   (compile 1 "" "")
FAIL the C program answered every question, in order
  expected: ((constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "CURL_VERSION_DEBUG [cut: 2172 more characters]
  actual:   ()
FAIL curl-version-features: ipv6 is CURL_VERSION_IPV6
  expected: (no-answer constant "CURL_VERSION_IPV6")
  actual:   1
FAIL curl-version-features: kerberos4 is CURL_VERSION_KERBEROS4
  expected: (no-answer constant "CURL_VERSION_KERBEROS4")
  actual:   2
FAIL curl-version-features: ssl is CURL_VERSION_SSL
  expected: (no-answer constant "CURL_VERSION_SSL")
  actual:   4
FAIL curl-version-features: libz is CURL_VERSION_LIBZ
  expected: (no-answer constant "CURL_VERSION_LIBZ")
  actual:   8
FAIL curl-version-features: ntlm is CURL_VERSION_NTLM
[284 more lines cut]
```

### EV3. no temporary directory: `TMPDIR=/nonexistent`

**Guards:** a raise while compiling or running fails, with its text.
**Mutation:** no file changed. The container ran `TMPDIR=/nonexistent make test`.
**Result:** killed, exit 2:

```
FAIL legal: a legal tree: wrappers over (rnrs ...), (only (chezscheme) ...), a version reference, two libraries in a file, and files it passes by
  expected: (0 "check-seam: the seam holds (5 libraries in 4 files checked)\n" "")
  actual:   #f
FAIL rule-a: rule (a): a (curl ...) library importing an (http-client ...) library
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-a/curl/x.sls: (curl x) imports (http-client y), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   #f
FAIL rule-b: rule (b): an (http-client ...) library importing a (curl ...) library that is not public
  expected: (1 "" "check-seam: tests/fixtures/seam/rule-b/http-client/z.sls: (http-client z) imports (curl private thing), but an (http-client ...) library may import only the public (curl ...) libraries ((curl))\ncheck-seam: FAILED (proble [cut: 10 more characters]
  actual:   #f
FAIL second-library: every library form in a file is checked, the second included
  expected: (1 "" "check-seam: tests/fixtures/seam/second-library/curl/two.sls: (curl two-b) imports (http-client target), but no (curl ...) library may import an (http-client ...) library\ncheck-seam: FAILED (problems: 1)\n")
  actual:   #f
FAIL neither-family: rule (d): a library in neither family
  expected: (1 "" "check-seam: tests/fixtures/seam/neither-family/util.sls: (util) belongs to neither family: the first identifier of a library's name under src/ must be curl or http-client\ncheck-seam: FAILED (problems: 1)\n")
  actual:   #f
FAIL chez-whole: (chezscheme) imported whole
  expected: (1 "" "check-seam: tests/fixtures/seam/chez-whole/curl/w.sls: (curl w) imports (chezscheme), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)\ncheck-seam: FAILED (problems: 1)\n")
  actual:   #f
FAIL scheme-alias: (scheme), the alias, imported whole
[383 more lines cut]
```

### TS1. the C program prints nothing

**Guards:** the suite never passes on an empty read of the program's output.
**Mutation:** In `tests/test-constants.sps`:

```diff
    "#include <stddef.h>\n"
-   "#include <stdio.h>\n"
+   "#include <stdio.h>\n#define printf(...) 0\n"
    "\n"
```
**Result:** killed, exit 2:

```
FAIL the C program answered every question, in order
  expected: ((constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "CURL_VERSION_DEBUG [cut: 2172 more characters]
  actual:   ()
FAIL curl-version-features: ipv6 is CURL_VERSION_IPV6
  expected: (no-answer constant "CURL_VERSION_IPV6")
  actual:   1
FAIL curl-version-features: kerberos4 is CURL_VERSION_KERBEROS4
  expected: (no-answer constant "CURL_VERSION_KERBEROS4")
  actual:   2
FAIL curl-version-features: ssl is CURL_VERSION_SSL
  expected: (no-answer constant "CURL_VERSION_SSL")
  actual:   4
FAIL curl-version-features: libz is CURL_VERSION_LIBZ
  expected: (no-answer constant "CURL_VERSION_LIBZ")
  actual:   8
FAIL curl-version-features: ntlm is CURL_VERSION_NTLM
  expected: (no-answer constant "CURL_VERSION_NTLM")
  actual:   16
FAIL curl-version-features: gssnegotiate is CURL_VERSION_GSSNEGOTIATE
[171 more lines cut]
```

### TS2. the coverage check given nothing to compare: the export list read as empty

**Guards:** the export list read is live.
**Mutation:** In `tests/test-constants.sps`:

```diff
 ;; exports : (Listof Symbol)
-(define exports
-  (if (eq? (car constants-read) 'read) (cadr constants-read) '()))
+(define exports '())
 
```
**Result:** killed, exit 2:

```
FAIL constants.sls is read: a library whose exports are identifiers, at least one
  expected: read
  actual:   (read (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth))
FAIL constant-rows' row curl-version-features is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curl-version-ssl is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curlhe-not-built-in is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curlh-header is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curl-global-default is an export of constants.sls
  expected: exported
  actual:   not-exported
FAIL constant-rows' row curle-ok is an export of constants.sls
[6 more lines cut]
```

### TS3. the ftype scan finds nothing

**Guards:** the define-ftype scan is live.
**Mutation:** In `tests/test-constants.sps`:

```diff
 ;; ftype-forms : (Listof Pair)
-(define ftype-forms
-  (if (eq? (car layouts-read) 'read) (cadr layouts-read) '()))
+(define ftype-forms '())
 
```
**Result:** killed, exit 2:

```
FAIL layouts.sls is read: a library with a define-ftype, at least one
  expected: read
  actual:   (read ((define-ftype curl-version-info-data (struct (age int) (version uptr) (version-num unsigned-int) (host uptr) (features unsigned-int) (ssl-version uptr) (ssl-version-num long) (libz-version uptr) (protocols uptr) (ares upt [cut: 321 more characters]
FAIL layout-rows' row curl-version-info-data is a define-ftype in layouts.sls
  expected: defined
  actual:   not-defined
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
  actual:   (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth)
test: FAIL tests/test-constants.sps (exit 1)
```

### TS4. the checks emptied

**Guards:** every row of both tables is checked.
**Mutation:** In `tests/test-constants.sps`:

```diff
 
-(define check-list (if (and (pair? checks) (eq? (car checks) 'raised)) '() checks))
+(define check-list '())
 
```
**Result:** killed, exit 2:

```
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data)
  actual:   ()
test: FAIL tests/test-constants.sps (exit 1)
```

### TS5. the compile judged by an empty stderr as well as its status

**Guards:** a compile is judged by its exit status alone (traps.md: Guix gcc warns at every link).
**Mutation:** In `tests/test-constants.sps`:

```diff
                           (append (c-compiler getenv) (list "-o" program source)))))
-           (if (not (= (car compiled) 0))
+           (if (not (and (= (car compiled) 0) (string=? (caddr compiled) "")))
                (cons 'compile compiled)
```
**Result:** killed, exit 2:

```
FAIL the C program compiled against libcurl's headers and ran
  expected: ran
  actual:   (compile 0 "" "guile: warning: failed to install locale\n")
FAIL the C program answered every question, in order
  expected: ((constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "CURL_VERSION_DEBUG [cut: 2172 more characters]
  actual:   ()
FAIL curl-version-features: ipv6 is CURL_VERSION_IPV6
  expected: (no-answer constant "CURL_VERSION_IPV6")
  actual:   1
FAIL curl-version-features: kerberos4 is CURL_VERSION_KERBEROS4
  expected: (no-answer constant "CURL_VERSION_KERBEROS4")
  actual:   2
FAIL curl-version-features: ssl is CURL_VERSION_SSL
  expected: (no-answer constant "CURL_VERSION_SSL")
  actual:   4
FAIL curl-version-features: libz is CURL_VERSION_LIBZ
  expected: (no-answer constant "CURL_VERSION_LIBZ")
  actual:   8
FAIL curl-version-features: ntlm is CURL_VERSION_NTLM
[174 more lines cut]
```

### TS6. the C program exits 3

**Guards:** a failed run fails, with the program's output.
**Mutation:** In `tests/test-constants.sps`:

```diff
    (apply string-append (map c-line questions))
-   "  return 0;\n"
+   "  return 3;\n"
    "}\n"))
```
**Result:** killed, exit 2:

```
FAIL the C program compiled against libcurl's headers and ran
  expected: ran
  actual:   (run 3 "(constant \"CURL_VERSION_IPV6\" 1)\n(constant \"CURL_VERSION_KERBEROS4\" 2)\n(constant \"CURL_VERSION_SSL\" 4)\n(constant \"CURL_VERSION_LIBZ\" 8)\n(constant \"CURL_VERSION_NTLM\" 16)\n(constant \"CURL_VERSION_GSSNEGOTIA [cut: 2755 more characters]
FAIL the C program answered every question, in order
  expected: ((constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "CURL_VERSION_DEBUG [cut: 2172 more characters]
  actual:   ()
FAIL curl-version-features: ipv6 is CURL_VERSION_IPV6
  expected: (no-answer constant "CURL_VERSION_IPV6")
  actual:   1
FAIL curl-version-features: kerberos4 is CURL_VERSION_KERBEROS4
  expected: (no-answer constant "CURL_VERSION_KERBEROS4")
  actual:   2
FAIL curl-version-features: ssl is CURL_VERSION_SSL
  expected: (no-answer constant "CURL_VERSION_SSL")
  actual:   4
FAIL curl-version-features: libz is CURL_VERSION_LIBZ
  expected: (no-answer constant "CURL_VERSION_LIBZ")
  actual:   8
FAIL curl-version-features: ntlm is CURL_VERSION_NTLM
[174 more lines cut]
```

### TS7. the C program prints a datum that is not an answer

**Guards:** output that is not answers fails, with what was printed.
**Mutation:** In `tests/test-constants.sps`:

```diff
    (apply string-append (map c-line questions))
-   "  return 0;\n"
+   "  puts(\"(garbage)\");\n  return 0;\n"
    "}\n"))
```
**Result:** killed, exit 2:

```
FAIL the C program compiled against libcurl's headers and ran
  expected: ran
  actual:   (output "(constant \"CURL_VERSION_IPV6\" 1)\n(constant \"CURL_VERSION_KERBEROS4\" 2)\n(constant \"CURL_VERSION_SSL\" 4)\n(constant \"CURL_VERSION_LIBZ\" 8)\n(constant \"CURL_VERSION_NTLM\" 16)\n(constant \"CURL_VERSION_GSSNEGOTI [cut: 2764 more characters]
FAIL the C program answered every question, in order
  expected: ((constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "CURL_VERSION_DEBUG [cut: 2172 more characters]
  actual:   ()
FAIL curl-version-features: ipv6 is CURL_VERSION_IPV6
  expected: (no-answer constant "CURL_VERSION_IPV6")
  actual:   1
FAIL curl-version-features: kerberos4 is CURL_VERSION_KERBEROS4
  expected: (no-answer constant "CURL_VERSION_KERBEROS4")
  actual:   2
FAIL curl-version-features: ssl is CURL_VERSION_SSL
  expected: (no-answer constant "CURL_VERSION_SSL")
  actual:   4
FAIL curl-version-features: libz is CURL_VERSION_LIBZ
  expected: (no-answer constant "CURL_VERSION_LIBZ")
  actual:   8
FAIL curl-version-features: ntlm is CURL_VERSION_NTLM
[174 more lines cut]
```

### Clean rerun

After every mutation, on the working tree itself. `make test` exited 0:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (11 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
test: pass tests/test-check-seam.sps
test: pass tests/test-conditions.sps
test: pass tests/test-constants.sps
test: pass tests/test-curl-testing.sps
test: pass tests/test-discovery.sps
test: pass tests/test-library-loading.sps
test: pass tests/test-load-state.sps
test: pass tests/test-manifest.sps
test: pass tests/test-native.sps
test: pass tests/test-require-threaded.sps
test: pass tests/test-verify.sps
test: ran 11, passed 11, failed 0, hung 0
```

## The collect-safe suite

Evidence for the check behind [harness plan](2026-10-04-harness-plan.md) §3 item 3
([ADR-0013](decisions/0013-collect-safe-blocking-calls.md),
[ADR-0001](decisions/0001-bind-libcurl-directly.md) decision 5). `tests/test-collect-safe.sps`
reads `src/` as data through `(foreign-conventions)`, `tests/foreign-conventions.sls`. It holds
each `foreign-procedure`'s and `foreign-callable`'s conventions against a table whose rows cite
the records. Every rule has a fixture tree under `tests/fixtures/conventions/`.

A driver in the session scratchpad ran every mutation. It froze one snapshot of part B's
worktree, without `.git` or `build/`, and gave each mutation a fresh copy of it. The sha256 of
the snapshot's files, the submodule aside, is
`b174a00e626f733320f07cd2ce5d485e3d23b7c058d42fa84451a7694f2023be`.
It applied the mutation by exact-text replacement, aborting unless the target occurred exactly
once, and refused a mutation whose diff was empty. It touched the copy's `manifest.scm` (`traps.md`, the stale
`guix shell -m` profile) and ran `scripts/guix-env make test` from inside the copy. A mutation
counts as killed only when `make test` exits non-zero and every expected line appears whole in
its output: the suite's `FAIL <test name>` lines, and
`test: FAIL tests/test-collect-safe.sps (exit 1)`. The working tree was never edited.

**Result** quotes the collect-safe suite's `FAIL` lines with their expected and actual values,
and every suite's `test: FAIL` line. A line longer than 240 characters is cut, and says how
much was cut. When a mutation in `native.sls` broke other suites, their `FAIL` lines are
counted, not copied. In CS1 they all read `string argument not allowed with __collect_safe
procedure`: Chez refuses a `string` parameter in a `__collect_safe` foreign procedure.

Cases are named `CS` (the brief's: bindings in `native.sls`, and a citation), `RD` (the
reader), `TB` (the table), `KW` (`known-wrappers`) and `FX` (the fixture trees).

62 mutations ran, and each was killed by name. Every one of the suite's 38 tests was failed by
name by at least one of them. TB13 and TB14 were added after the first 60, which left two
seeded tests that no mutant failed. RD11's kill is a hang: its suite names the
`shared-structure` case FAIL, then never returns from the `cyclic` case, so it ran with
`TEST_TIMEOUT=60`. No process outlived it.

### Red runs

**Before the library existed:** the suite and its fixtures, and no
`tests/foreign-conventions.sls`. `make test` exited 2. The suite died at import, with no test
run:

```
Exception: library (foreign-conventions) not found
test: FAIL tests/test-collect-safe.sps (exit 255)
```

**Against a stub:** the library with its real export list, each procedure raising
`not written yet`, and `conventions-table` and `known-wrappers` the symbol `not-written-yet`.
`make test` exited 2. 36 of the suite's 37 tests failed by name:

```
FAIL the table's citations each name a decision record that exists, and quote it
  expected: (returned ())
  actual:   (raised "Exception in foreign-conventions: not written yet")
FAIL table-problems, seeded: a citation naming no file
  expected: (returned ((citation-not-a-record "x" ".plans/decisions/9999-no-such-record.md")))
  actual:   (raised "Exception in foreign-conventions: not written yet")
FAIL table-problems, seeded: a citation naming a file outside .plans/decisions/
  expected: (returned ((citation-not-a-record "x" "AGENTS.md")))
  actual:   (raised "Exception in foreign-conventions: not written yet")
FAIL table-problems, seeded: a citation climbing out of .plans/decisions/
  expected: (returned ((citation-not-a-record "x" ".plans/decisions/../progress.md")))
  actual:   (raised "Exception in foreign-conventions: not written yet")
FAIL table-problems, seeded: a phrase the record does not hold
  expected: (returned ((citation-phrase-missing "x" ".plans/decisions/0013-collect-safe-blocking-calls.md" "Calls that can block stay plain.")))
  actual:   (raised "Exception in foreign-conventions: not written yet")
FAIL table-problems, seeded: a citation with no phrase
  expected: (returned ((citation-shape "x" ".plans/decisions/0013-collect-safe-blocking-calls.md")))
  actual:   (raised "Exception in foreign-conventions: not written yet")
FAIL table-problems, seeded: a citation with an empty phrase
[90 more lines cut]
```

The one pass, `every fixture directory is a case above, and every case has its directory`,
holds the suite's own case list against `tests/fixtures/conventions/`, so no library code can
fail it. FX1 and FX2 do.

The first run against the real library failed one test, `unreadable`. Its fixture `eof.sls`
began with `#!r6rs`, and Chez refuses `#!eof` in that mode (as it does `#&` and datum labels,
measured at the pin), so Chez's own read error came before the reader's check. The fixture
lost its `#!r6rs`.

Tests written after these runs are each watched failing below: the `cyclic` case (RD11,
RD11b), the vector and box literals in `quoted` (RD24, RD25), the improper tail in `stray`
(RD26), and `w-literal-entry` in `wrapper-unreadable` (RD18b). Before the first real run, the
`shared-structure` case's expected bindings went from one to none, when the reader came to
skip a datum with shared structure rather than walk it once.

### CS1. __collect_safe added to bind-required's template in native.sls

```diff
-         (foreign-procedure entry (arg ...) result)))))
+         (foreign-procedure __collect_safe entry (arg ...) result)))))
```

**Result:** killed, exit 2:

```
FAIL the scan of src/ finds the six entries loading binds, each bound once, plain
  expected: (("curl_version_info" (())) ("curl_global_init" (())) ("curl_easy_option_by_name" (())) ("curl_easy_init" (())) ("curl_easy_header" (())) ("curl_easy_cleanup" (())))
  actual:   (("curl_version_info" ((__collect_safe))) ("curl_global_init" ((__collect_safe))) ("curl_easy_option_by_name" ((__collect_safe))) ("curl_easy_init" ((__collect_safe))) ("curl_easy_header" ((__collect_safe))) ("curl_easy_cleanup" [21 more]
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((mismatch "curl_version_info" () (__collect_safe) "src/curl/private/native.sls") (mismatch "curl_global_init" () (__collect_safe) "src/curl/private/native.sls") (mismatch "curl_easy_option_by_name" () (__collect_safe) "src/curl [261 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 1)
test: FAIL tests/test-native.sps (exit 255)
```

Other suites failed 41 tests as well; their FAIL lines are left out.

### CS2. a direct (foreign-procedure __collect_safe "curl_easy_init" ...) in native.sls

```diff
-  (define curl-easy-init (load-step (bind-required "curl_easy_init" () uptr info)))
+  (define curl-easy-init (load-step (begin (required-entry "curl_easy_init" info) (foreign-procedure __collect_safe "curl_easy_init" () uptr))))
```

**Result:** killed, exit 2:

```
FAIL the scan of src/ finds the six entries loading binds, each bound once, plain
  expected: (("curl_version_info" (())) ("curl_global_init" (())) ("curl_easy_option_by_name" (())) ("curl_easy_init" (())) ("curl_easy_header" (())) ("curl_easy_cleanup" (())))
  actual:   (("curl_version_info" (())) ("curl_global_init" (())) ("curl_easy_option_by_name" (())) ("curl_easy_init" ((__collect_safe))) ("curl_easy_header" (())) ("curl_easy_cleanup" (())))
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((mismatch "curl_easy_init" () (__collect_safe) "src/curl/private/native.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### CS3. a new plain binding of curl_easy_perform through bind-required

```diff
+  (define curl-easy-perform (load-step (bind-required "curl_easy_perform" (uptr) int info)))
```

**Result:** killed, exit 2:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((mismatch "curl_easy_perform" (__collect_safe) () "src/curl/private/native.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 1)
```

Other suites failed 9 tests as well; their FAIL lines are left out.

### CS4. a binding, curl_easy_reset, with no table row

```diff
+  (define curl-easy-reset (load-step (bind-required "curl_easy_reset" (uptr) void info)))
```

**Result:** killed, exit 2:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((no-row "curl_easy_reset" "src/curl/private/native.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 1)
```

Other suites failed 9 tests as well; their FAIL lines are left out.

### CS5. a foreign-procedure whose entry is a variable, outside a known wrapper

```diff
+  (define easy-init-name "curl_easy_init")
+  (define curl-easy-init-again (load-step (foreign-procedure easy-init-name () uptr)))
```

**Result:** killed, exit 2:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((entry-not-string "src/curl/private/native.sls" "(foreign-procedure easy-init-name () uptr)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### CS6. 'foreign-procedure quoted in native.sls's body

```diff
+  (define quoted-name 'foreign-procedure)
```

**Result:** killed, exit 2:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((stray "src/curl/private/native.sls" "(quote foreign-procedure)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### CS7. a foreign-callable not under a define, in native.sls (imported, and allowed in check-seam, so only this suite can fail)

```diff
-                foreign-procedure foreign-entry? load-shared-object
+                foreign-procedure foreign-callable foreign-entry? load-shared-object
+  (define (make-callable) (foreign-callable (lambda (n) n) (int) int))
-    foreign-free foreign-procedure foreign-ref foreign-sizeof format
+    foreign-free foreign-procedure foreign-callable foreign-ref foreign-sizeof format
```

**Result:** killed, exit 2:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((callable-not-defined "src/curl/private/native.sls" "(foreign-callable (lambda (n) n) (int) int)"))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### CS8. the table's citations name a decision record that does not exist

```diff
-  (define adr-0013 ".plans/decisions/0013-collect-safe-blocking-calls.md")
+  (define adr-0013 ".plans/decisions/0013-collect-safe.md")
```

**Result:** killed, exit 2:

```
FAIL the table's citations each name a decision record that exists, and quote it
  expected: (returned ())
  actual:   (returned ((citation-not-a-record "curl_version_info" ".plans/decisions/0013-collect-safe.md") (citation-not-a-record "curl_global_init" ".plans/decisions/0013-collect-safe.md") (citation-not-a-record "curl_easy_option_by_name"  [541 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD1. the live scan pointed at an empty directory

```diff
-(define source-root "src")
+(define source-root "empty-src")
```
```sh
mkdir empty-src
```

**Result:** killed, exit 2:

```
FAIL the scan of src/ finds the six entries loading binds, each bound once, plain
  expected: (("curl_version_info" (())) ("curl_global_init" (())) ("curl_easy_option_by_name" (())) ("curl_easy_init" (())) ("curl_easy_header" (())) ("curl_easy_cleanup" (())))
  actual:   (("curl_version_info" ()) ("curl_global_init" ()) ("curl_easy_option_by_name" ()) ("curl_easy_init" ()) ("curl_easy_header" ()) ("curl_easy_cleanup" ()))
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((no-sources "empty-src"))
FAIL known-wrappers is exactly the wrappers src/ defines
  expected: (returned (bind-required))
  actual:   (returned ())
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD2. the reader skips define-syntax forms

```diff
+            ((eq? head 'define-syntax) #f)
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("fixture_two_conventions" ((__vara [617 more]
FAIL stray: references that are no form's head: a define, a let binding, an improper tail, an identifier-syntax
  expected: (returned (() ((stray "tests/fixtures/conventions/stray/curl/s.sls" "(define fp foreign-procedure)") (stray "tests/fixtures/conventions/stray/curl/s.sls" "(f foreign-callable)") (stray "tests/fixtures/conventions/stray/curl/s.sl [128 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/stray/curl/s.sls" "(define fp foreign-procedure)") (stray "tests/fixtures/conventions/stray/curl/s.sls" "(f foreign-callable)") (stray "tests/fixtures/conventions/stray/curl/s.sl [34 more]
FAIL entry-not-string: an entry that is no string literal outside a known wrapper: a variable, an expression, a pattern variable
  expected: (returned (() ((entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure entry () uptr)") (entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure (strin [154 more]
  actual:   (returned (() ((entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure entry () uptr)") (entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure (strin [47 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__collect_safe) "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("memcp [547 more]
FAIL wrapper-safe: __collect_safe in the known wrapper's template: every use gets it
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((mism [98 more]
  actual:   (returned (() ((wrapper-undefined "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required "(bind-required \"curl_easy_init\" () uptr #f)") (wrapper-undefined "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-r [65 more]
FAIL wrapper-pattern-conventions: the known wrapper's conventions come from a pattern variable
  expected: (returned (() ((wrapper-conventions-from-pattern "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" bind-required (conv)))))
  actual:   (returned (() ((wrapper-undefined "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" bind-required "(bind-required __collect_safe \"curl_easy_init\" () uptr #f)"))))
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal
[18 more lines cut]
```

### RD3. quote and quasiquote walked as code

```diff
-            ((memq head '(quote quasiquote)) (walk-elements form 0 #t))
+            ((memq head '()) (walk-elements form 0 #t))
```

**Result:** killed, exit 2:

```
FAIL quoted: quoted occurrences: a symbol, a list, a quasiquote with an unquote, a syntax form, a vector literal holding a form, a box literal holding one
  expected: (returned (() ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/quoted/curl/q.sls" "(foreign-procedure \"curl_easy_init\" () uptr)") (stray "tests/fixtures/con [539 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/quoted/curl/q.sls" foreign-procedure) ("curl_global_init" () "tests/fixtures/conventions/quoted/curl/q.sls" foreign-procedure)) ((stray "tests/fixtures/conventions/quo [501 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD3b. quasiquote alone walked as code

```diff
-            ((memq head '(quote quasiquote)) (walk-elements form 0 #t))
+            ((memq head '(quote)) (walk-elements form 0 #t))
```

**Result:** killed, exit 2:

```
FAIL quoted: quoted occurrences: a symbol, a list, a quasiquote with an unquote, a syntax form, a vector literal holding a form, a box literal holding one
  expected: (returned (() ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/quoted/curl/q.sls" "(foreign-procedure \"curl_easy_init\" () uptr)") (stray "tests/fixtures/con [539 more]
  actual:   (returned ((("curl_global_init" () "tests/fixtures/conventions/quoted/curl/q.sls" foreign-procedure)) ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/quoted/ [518 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD4. any only import accounts for the names, not just (only (chezscheme) ...)

```diff
-         (eq? (car spec) 'only)
-         (equal? (cadr spec) '(chezscheme))))
+         (eq? (car spec) 'only)))
```

**Result:** killed, exit 2:

```
FAIL imports: only (only (chezscheme) name ...) accounts for a name: not an export, an except, (scheme), nor an only inside a prefix
  expected: (returned (() ((stray "tests/fixtures/conventions/imports/curl/i.sls" "(export foreign-procedure)") (stray "tests/fixtures/conventions/imports/curl/i.sls" "(except (chezscheme) foreign-callable)") (stray "tests/fixtures/conventi [159 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/imports/curl/i.sls" "(export foreign-procedure)") (stray "tests/fixtures/conventions/imports/curl/i.sls" "(except (chezscheme) foreign-callable)") (stray "tests/fixtures/conventi [67 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD4b. no import accounts for the names

```diff
-                    (if (chez-only? spec)
+                    (if #f
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [1097 more]
FAIL quoted: quoted occurrences: a symbol, a list, a quasiquote with an unquote, a syntax form, a vector literal holding a form, a box literal holding one
  expected: (returned (() ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/quoted/curl/q.sls" "(foreign-procedure \"curl_easy_init\" () uptr)") (stray "tests/fixtures/con [539 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(only (chezscheme) foreign-procedure)") (stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/ [634 more]
FAIL stray: references that are no form's head: a define, a let binding, an improper tail, an identifier-syntax
  expected: (returned (() ((stray "tests/fixtures/conventions/stray/curl/s.sls" "(define fp foreign-procedure)") (stray "tests/fixtures/conventions/stray/curl/s.sls" "(f foreign-callable)") (stray "tests/fixtures/conventions/stray/curl/s.sl [128 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/stray/curl/s.sls" "(only (chezscheme) foreign-procedure foreign-callable)") (stray "tests/fixtures/conventions/stray/curl/s.sls" "(only (chezscheme) foreign-procedure foreign-cal [350 more]
FAIL imports: only (only (chezscheme) name ...) accounts for a name: not an export, an except, (scheme), nor an only inside a prefix
  expected: (returned (() ((stray "tests/fixtures/conventions/imports/curl/i.sls" "(export foreign-procedure)") (stray "tests/fixtures/conventions/imports/curl/i.sls" "(except (chezscheme) foreign-callable)") (stray "tests/fixtures/conventi [159 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/imports/curl/i.sls" "(export foreign-procedure)") (stray "tests/fixtures/conventions/imports/curl/i.sls" "(only (chezscheme) foreign-procedure foreign-callable)") (stray "tests/f [385 more]
FAIL entry-not-string: an entry that is no string literal outside a known wrapper: a variable, an expression, a pattern variable
  expected: (returned (() ((entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure entry () uptr)") (entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure (strin [154 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(only (chezscheme) foreign-procedure)") (entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure entry () uptr [259 more]
FAIL malformed: forms too short, with no type list, improper, and a callable too short
  expected: (returned (() ((malformed "tests/fixtures/conventions/malformed/curl/m.sls" "(foreign-procedure \"curl_easy_init\")") (malformed "tests/fixtures/conventions/malformed/curl/m.sls" "(foreign-procedure \"curl_easy_init\" uptr uptr) [207 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/malformed/curl/m.sls" "(only (chezscheme) foreign-procedure foreign-callable)") (stray "tests/fixtures/conventions/malformed/curl/m.sls" "(only (chezscheme) foreign-procedure for [437 more]
FAIL callable-misplaced: a callable that is not the whole right-hand side of (define name ...)
[36 more lines cut]
```

### RD5. conventions compared as lists, not sets

```diff
-    (and (for-all (lambda (x) (member x b)) a)
-         (for-all (lambda (x) (member x a)) b)
-         #t))
+    (equal? a b))
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [780 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD5b. conventions compared one way: the row's within the binding's

```diff
-         (for-all (lambda (x) (member x a)) b)
```

**Result:** killed, exit 2:

```
FAIL mismatch: a direct binding with a convention its row lacks, and a callable without the one its row requires
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-procedure) (on-write () "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-callable)) ((mismatch "curl_easy_init" () ( [157 more]
  actual:   (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-procedure) (on-write () "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-callable)) ((mismatch on-write (__collect_s [60 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [402 more]
FAIL wrapper-safe: __collect_safe in the known wrapper's template: every use gets it
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((mism [98 more]
  actual:   (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD5c. conventions compared one way: the binding's within the row's

```diff
-    (and (for-all (lambda (x) (member x b)) a)
-         (for-all (lambda (x) (member x a)) b)
+    (and (for-all (lambda (x) (member x a)) b)
```

**Result:** killed, exit 2:

```
FAIL mismatch: a direct binding with a convention its row lacks, and a callable without the one its row requires
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-procedure) (on-write () "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-callable)) ((mismatch "curl_easy_init" () ( [157 more]
  actual:   (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-procedure) (on-write () "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-callable)) ((mismatch "curl_easy_init" () ( [68 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [394 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD6. a wrapper's conventions from a pattern variable accepted

```diff
-                         ((exists (lambda (s) (or (memq s variables) (eq? s '...)))
+                         ((exists (lambda (s) #f)
```

**Result:** killed, exit 2:

```
FAIL wrapper-pattern-conventions: the known wrapper's conventions come from a pattern variable
  expected: (returned (() ((wrapper-conventions-from-pattern "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" bind-required (conv)))))
  actual:   (returned ((("curl_easy_init" (conv) "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" bind-required)) ((mismatch "curl_easy_init" () (conv) "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls")) [2 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD7. a wrapper use's entry accepted whatever it is

```diff
-                                 (string? (list-ref form index)))
+                                 #t)
```

**Result:** killed, exit 2:

```
FAIL wrapper-entry-not-string: uses of the known wrapper whose entry is no string literal: a variable, an expression, none at all
  expected: (returned (() ((wrapper-entry-not-string "tests/fixtures/conventions/wrapper-entry-not-string/curl/u.sls" bind-required "(bind-required name () uptr #f)") (wrapper-entry-not-string "tests/fixtures/conventions/wrapper-entry-not-s [228 more]
  actual:   (returned (((name () "tests/fixtures/conventions/wrapper-entry-not-string/curl/u.sls" bind-required) ((string-append "curl_" "easy_init") () "tests/fixtures/conventions/wrapper-entry-not-string/curl/u.sls" bind-required)) ((wrap [310 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD8. a callable outside a define accepted

```diff
-             (violation! 'callable-not-defined path (abbreviated form))
```

**Result:** killed, exit 2:

```
FAIL callable-misplaced: a callable that is not the whole right-hand side of (define name ...)
  expected: (returned (() ((callable-not-defined "tests/fixtures/conventions/callable-misplaced/curl/c.sls" "(foreign-callable (lambda (a) a) (int) int)") (callable-not-defined "tests/fixtures/conventions/callable-misplaced/curl/c.sls" "(fo [429 more]
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD9. a binding with no row accepted

```diff
-                 (cond ((not row) (list (list 'no-row key file)))
+                 (cond ((not row) '())
```

**Result:** killed, exit 2:

```
FAIL no-row: bindings with no row: an entry, a callable, and a callable named memcpy, a symbol
  expected: (returned ((("curl_easy_reset" () "tests/fixtures/conventions/no-row/curl/n.sls" foreign-procedure) (on-unlisted () "tests/fixtures/conventions/no-row/curl/n.sls" foreign-callable) (memcpy () "tests/fixtures/conventions/no-row/c [238 more]
  actual:   (returned ((("curl_easy_reset" () "tests/fixtures/conventions/no-row/curl/n.sls" foreign-procedure) (on-unlisted () "tests/fixtures/conventions/no-row/curl/n.sls" foreign-callable) (memcpy () "tests/fixtures/conventions/no-row/c [34 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD10. an entry that is no string literal accepted

```diff
-                (else (violation! 'entry-not-string path (abbreviated form))))))
+                (else #f))))
```

**Result:** killed, exit 2:

```
FAIL entry-not-string: an entry that is no string literal outside a known wrapper: a variable, an expression, a pattern variable
  expected: (returned (() ((entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure entry () uptr)") (entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure (strin [154 more]
  actual:   (returned (() ()))
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1759 more]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (wrapper-unreadable "tests/fixtures/conven [1317 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD11. the shared-structure check removed: a shared datum is walked (TEST_TIMEOUT=60)

```diff
-      (cond (shared (violation! 'shared-structure path (abbreviated shared)))
+      (cond (#f (violation! 'shared-structure path (abbreviated shared)))
```

**Result:** killed, exit 2:

```
FAIL shared-structure: a form labelled and referred to again: the datum holding it is named, and not read, binding included
  expected: (returned (() ((shared-structure "tests/fixtures/conventions/shared-structure/curl/g.sls" "(foreign-procedure \"curl_easy_init\" () uptr)"))))
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/shared-structure/curl/g.sls" foreign-procedure) ("curl_easy_init" () "tests/fixtures/conventions/shared-structure/curl/g.sls" foreign-procedure)) ()))
test: HUNG tests/test-collect-safe.sps (no exit within 60s)
```

### RD11b. a shared datum skipped, but not named

```diff
-      (cond (shared (violation! 'shared-structure path (abbreviated shared)))
+      (cond (shared #f)
```

**Result:** killed, exit 2:

```
FAIL shared-structure: a form labelled and referred to again: the datum holding it is named, and not read, binding included
  expected: (returned (() ((shared-structure "tests/fixtures/conventions/shared-structure/curl/g.sls" "(foreign-procedure \"curl_easy_init\" () uptr)"))))
  actual:   (returned (() ()))
FAIL cyclic: a cyclic datum is named, and the walk ends
  expected: (returned (() ((shared-structure "tests/fixtures/conventions/cyclic/curl/h.sls" "#0=(foreign-procedure . #0#)"))))
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD12. a file that cannot be read skipped

```diff
-          (list (list 'violation (list 'unreadable path (cadr data))))
+          '()
```

**Result:** killed, exit 2:

```
FAIL unreadable: a file that cannot be read as data, and one with an #!eof literal hiding a binding
  expected: (returned (() ((unreadable "tests/fixtures/conventions/unreadable/curl/broken.sls" "Exception in read: unexpected end-of-file reading list before file-position 48 of #<input port tests/fixtures/conventions/unreadable/curl/broken [195 more]
  actual:   (returned (() ()))
FAIL lock-file: a .# dangling link, Emacs's lock file, is skipped; a .# regular file is read; another dangling link is named
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/lock-file/curl/a.sls" foreign-procedure)) ((stray "tests/fixtures/conventions/lock-file/curl/.#b.sls" "(quote foreign-callable)") (unreadable "tests/fixtures/conventio [157 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/lock-file/curl/a.sls" foreign-procedure)) ((stray "tests/fixtures/conventions/lock-file/curl/.#b.sls" "(quote foreign-callable)"))))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD13. a directory with no source passes

```diff
-                 (append (if (null? files) (list (list 'no-sources root)) '())
+                 (append '()
```

**Result:** killed, exit 2:

```
FAIL an empty directory holds no source, and says so
  expected: refused
  actual:   (returned (() ()))
FAIL a directory that does not exist holds no source, and says so
  expected: refused
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD14. a wrapper use with no definition accepted

```diff
-                            (cons (list 'wrapper-undefined file name (abbreviated form)) violations)
+                            violations
```

**Result:** killed, exit 2:

```
FAIL wrapper-undefined: a use of the known wrapper that no file defines
  expected: (returned (() ((wrapper-undefined "tests/fixtures/conventions/wrapper-undefined/curl/u.sls" bind-required "(bind-required \"curl_easy_init\" () uptr #f)"))))
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD15. a wrapper defined twice accepted

```diff
-                           (cons (list 'wrapper-defined-again (caddr f) (cadr f)) violations)
+                           violations
```

**Result:** killed, exit 2:

```
FAIL wrapper-defined-again: the known wrapper defined in two files: no use is read against either
  expected: (returned (() ((wrapper-defined-again "tests/fixtures/conventions/wrapper-defined-again/curl/b.sls" bind-required))))
  actual:   (returned (() ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD16. a wrapper with two clauses read by its first

```diff
-         (= (length rules) 3)
+         (>= (length rules) 3)
```

**Result:** killed, exit 2:

```
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1759 more]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1478 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD17. an ellipsis before a wrapper's entry ignored

```diff
-                  (and (not (memq '... (take pattern (min (length pattern) (+ i 2)))))
-                       i))
+                  i)
```

**Result:** killed, exit 2:

```
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1759 more]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1592 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD18. a wrapper template with two foreign-procedure forms read by its first

```diff
-              ((pair? (cdr heads)) (list 'unreadable many-bindings #f))
```

**Result:** killed, exit 2:

```
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1759 more]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1495 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD18b. a wrapper's entry need not be a pattern variable

```diff
-    (and (memq entry variables)
-         (list? pattern)
+    (and (list? pattern)
```

**Result:** killed, exit 2:

```
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1759 more]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1593 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD19. a malformed foreign-procedure form accepted

```diff
-          (cond ((not parts) (violation! 'malformed path (abbreviated form)))
+          (cond ((not parts) #f)
```

**Result:** killed, exit 2:

```
FAIL malformed: forms too short, with no type list, improper, and a callable too short
  expected: (returned (() ((malformed "tests/fixtures/conventions/malformed/curl/m.sls" "(foreign-procedure \"curl_easy_init\")") (malformed "tests/fixtures/conventions/malformed/curl/m.sls" "(foreign-procedure \"curl_easy_init\" uptr uptr) [207 more]
  actual:   (returned (() ((malformed "tests/fixtures/conventions/malformed/curl/m.sls" "(foreign-callable (lambda () 0))"))))
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1759 more]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1664 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD20. a define with an extra part counts as a callable's definition

```diff
-         (= (length form) 3)
```

**Result:** killed, exit 2:

```
FAIL callable-misplaced: a callable that is not the whole right-hand side of (define name ...)
  expected: (returned (() ((callable-not-defined "tests/fixtures/conventions/callable-misplaced/curl/c.sls" "(foreign-callable (lambda (a) a) (int) int)") (callable-not-defined "tests/fixtures/conventions/callable-misplaced/curl/c.sls" "(fo [429 more]
  actual:   (returned (((both () "tests/fixtures/conventions/callable-misplaced/curl/c.sls" foreign-callable)) ((callable-not-defined "tests/fixtures/conventions/callable-misplaced/curl/c.sls" "(foreign-callable (lambda (a) a) (int) int)")  [459 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD21. a symbolic link to a directory skipped without a word

```diff
-               ((file-directory? path)
-                (list (car found) (append (cadr found) (list path))))
+               ((file-directory? path) found)
```

**Result:** killed, exit 2:

```
FAIL dir-symlink: a symbolic link to a directory is named, not followed
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/dir-symlink/curl/ok.sls" foreign-procedure)) ((directory-link "tests/fixtures/conventions/dir-symlink/linked"))))
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/dir-symlink/curl/ok.sls" foreign-procedure)) ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD22. Emacs lock files no longer skipped

```diff
-         (cond ((lock-file? path name) found)
+         (cond (#f found)
```

**Result:** killed, exit 2:

```
FAIL lock-file: a .# dangling link, Emacs's lock file, is skipped; a .# regular file is read; another dangling link is named
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/lock-file/curl/a.sls" foreign-procedure)) ((stray "tests/fixtures/conventions/lock-file/curl/.#b.sls" "(quote foreign-callable)") (unreadable "tests/fixtures/conventio [157 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/lock-file/curl/a.sls" foreign-procedure)) ((stray "tests/fixtures/conventions/lock-file/curl/.#b.sls" "(quote foreign-callable)") (unreadable "tests/fixtures/conventio [347 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD23. only .sls files read

```diff
-  (define source-endings (map car (library-extensions)))
+  (define source-endings '(".sls"))
```

**Result:** killed, exit 2:

```
FAIL extensions: every source ending Chez loads a library from is read: .chezscheme.sls .ss .scm .sch; a .txt is not
  expected: (returned (() ((stray "tests/fixtures/conventions/extensions/curl/w.chezscheme.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/extensions/curl/x.ss" "(quote foreign-procedure)") (stray "tests/fixtures/conven [147 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/extensions/curl/w.chezscheme.sls" "(quote foreign-procedure)"))))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD24. a vector literal's elements walked as code

```diff
-              ((vector? x) (for-each (lambda (e) (walk e x #t)) (vector->list x)))
+              ((vector? x) (for-each (lambda (e) (walk e x #f)) (vector->list x)))
```

**Result:** killed, exit 2:

```
FAIL quoted: quoted occurrences: a symbol, a list, a quasiquote with an unquote, a syntax form, a vector literal holding a form, a box literal holding one
  expected: (returned (() ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/quoted/curl/q.sls" "(foreign-procedure \"curl_easy_init\" () uptr)") (stray "tests/fixtures/con [539 more]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/quoted/curl/q.sls" foreign-procedure)) ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/quoted [616 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD25. a box literal not walked

```diff
-              ((box? x) (walk (unbox x) x #t))
+              (#f (walk (unbox x) x #t))
```

**Result:** killed, exit 2:

```
FAIL quoted: quoted occurrences: a symbol, a list, a quasiquote with an unquote, a syntax form, a vector literal holding a form, a box literal holding one
  expected: (returned (() ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/quoted/curl/q.sls" "(foreign-procedure \"curl_easy_init\" () uptr)") (stray "tests/fixtures/con [539 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/quoted/curl/q.sls" "(foreign-procedure \"curl_easy_init\" () uptr)") (stray "tests/fixtures/con [408 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD26. an improper tail not walked

```diff
-                (else (walk rest form quoted?)))))
+                (else #f))))
```

**Result:** killed, exit 2:

```
FAIL stray: references that are no form's head: a define, a let binding, an improper tail, an identifier-syntax
  expected: (returned (() ((stray "tests/fixtures/conventions/stray/curl/s.sls" "(define fp foreign-procedure)") (stray "tests/fixtures/conventions/stray/curl/s.sls" "(f foreign-callable)") (stray "tests/fixtures/conventions/stray/curl/s.sl [128 more]
  actual:   (returned (() ((stray "tests/fixtures/conventions/stray/curl/s.sls" "(define fp foreign-procedure)") (stray "tests/fixtures/conventions/stray/curl/s.sls" "(f foreign-callable)") (stray "tests/fixtures/conventions/stray/curl/s.sl [46 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD27. a known wrapper's template form not accounted for

```diff
-            ((memq form accounted) (walk-elements form 1 #f))
+            (#f (walk-elements form 1 #f))
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [733 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [723 more]
FAIL wrapper-safe: __collect_safe in the known wrapper's template: every use gets it
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((mism [98 more]
  actual:   (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((entr [230 more]
FAIL wrapper-pattern-conventions: the known wrapper's conventions come from a pattern variable
  expected: (returned (() ((wrapper-conventions-from-pattern "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" bind-required (conv)))))
  actual:   (returned (() ((wrapper-conventions-from-pattern "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" bind-required (conv)) (entry-not-string "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" "(f [50 more]
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [1759 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" foreign-procedure)) ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rul [2194 more]
FAIL wrapper-entry-not-string: uses of the known wrapper whose entry is no string literal: a variable, an expression, none at all
  expected: (returned (() ((wrapper-entry-not-string "tests/fixtures/conventions/wrapper-entry-not-string/curl/u.sls" bind-required "(bind-required name () uptr #f)") (wrapper-entry-not-string "tests/fixtures/conventions/wrapper-entry-not-s [228 more]
  actual:   (returned (() ((entry-not-string "tests/fixtures/conventions/wrapper-entry-not-string/curl/u.sls" "(foreign-procedure entry (arg ...) result)") (wrapper-entry-not-string "tests/fixtures/conventions/wrapper-entry-not-string/curl/ [357 more]
FAIL wrapper-defined-again: the known wrapper defined in two files: no use is read against either
[6 more lines cut]
```

### RD28. a library's body not walked

```diff
-        (for-each (lambda (body) (walk body form #f)) (cddddr form)))
+        #f)
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned (() ()))
FAIL quoted: quoted occurrences: a symbol, a list, a quasiquote with an unquote, a syntax form, a vector literal holding a form, a box literal holding one
  expected: (returned (() ((stray "tests/fixtures/conventions/quoted/curl/q.sls" "(quote foreign-procedure)") (stray "tests/fixtures/conventions/quoted/curl/q.sls" "(foreign-procedure \"curl_easy_init\" () uptr)") (stray "tests/fixtures/con [539 more]
  actual:   (returned (() ()))
FAIL stray: references that are no form's head: a define, a let binding, an improper tail, an identifier-syntax
  expected: (returned (() ((stray "tests/fixtures/conventions/stray/curl/s.sls" "(define fp foreign-procedure)") (stray "tests/fixtures/conventions/stray/curl/s.sls" "(f foreign-callable)") (stray "tests/fixtures/conventions/stray/curl/s.sl [128 more]
  actual:   (returned (() ()))
FAIL entry-not-string: an entry that is no string literal outside a known wrapper: a variable, an expression, a pattern variable
  expected: (returned (() ((entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure entry () uptr)") (entry-not-string "tests/fixtures/conventions/entry-not-string/curl/e.sls" "(foreign-procedure (strin [154 more]
  actual:   (returned (() ()))
FAIL malformed: forms too short, with no type list, improper, and a callable too short
  expected: (returned (() ((malformed "tests/fixtures/conventions/malformed/curl/m.sls" "(foreign-procedure \"curl_easy_init\")") (malformed "tests/fixtures/conventions/malformed/curl/m.sls" "(foreign-procedure \"curl_easy_init\" uptr uptr) [207 more]
  actual:   (returned (() ()))
FAIL callable-misplaced: a callable that is not the whole right-hand side of (define name ...)
  expected: (returned (() ((callable-not-defined "tests/fixtures/conventions/callable-misplaced/curl/c.sls" "(foreign-callable (lambda (a) a) (int) int)") (callable-not-defined "tests/fixtures/conventions/callable-misplaced/curl/c.sls" "(fo [429 more]
  actual:   (returned (() ()))
FAIL mismatch: a direct binding with a convention its row lacks, and a callable without the one its row requires
[42 more lines cut]
```

### RD29. a wrapper use's entry read one place too far

```diff
-                       i))
+                       (+ i 1)))
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("fixture_two_conventions" ((__vara [732 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__collect_safe) "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("memcp [554 more]
FAIL wrapper-safe: __collect_safe in the known wrapper's template: every use gets it
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((mism [98 more]
  actual:   (returned (() ((wrapper-entry-not-string "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required "(bind-required \"curl_easy_init\" () uptr #f)") (wrapper-entry-not-string "tests/fixtures/conventions/wrapper-safe/curl [79 more]
FAIL the scan of src/ finds the six entries loading binds, each bound once, plain
  expected: (("curl_version_info" (())) ("curl_global_init" (())) ("curl_easy_option_by_name" (())) ("curl_easy_init" (())) ("curl_easy_header" (())) ("curl_easy_cleanup" (())))
  actual:   (("curl_version_info" ()) ("curl_global_init" ()) ("curl_easy_option_by_name" ()) ("curl_easy_init" ()) ("curl_easy_header" ()) ("curl_easy_cleanup" ()))
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((wrapper-entry-not-string "src/curl/private/native.sls" bind-required "(bind-required \"curl_version_info\" (int) uptr #f)") (wrapper-entry-not-string "src/curl/private/native.sls" bind-required "(bind-required \"curl_global_in [572 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### RD30. conventions read as none, whatever precedes the entry

```diff
-                (list (take (cdr form) (- n 4)) (list-ref form (- n 3)))))))
+                (list '() (list-ref form (- n 3)))))))
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" () "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/conventions/lega [948 more]
FAIL mismatch: a direct binding with a convention its row lacks, and a callable without the one its row requires
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-procedure) (on-write () "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-callable)) ((mismatch "curl_easy_init" () ( [157 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-procedure) (on-write () "tests/fixtures/conventions/mismatch/curl/x.sls" foreign-callable)) ((mismatch on-write (__collect_safe) () "tests [46 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" () " [374 more]
FAIL wrapper-safe: __collect_safe in the known wrapper's template: every use gets it
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((mism [98 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" () "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((mismatch "curl_easy_perform" (__ [73 more]
FAIL wrapper-pattern-conventions: the known wrapper's conventions come from a pattern variable
  expected: (returned (() ((wrapper-conventions-from-pattern "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" bind-required (conv)))))
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" bind-required)) ()))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB1. curl_easy_perform's row made plain

```diff
-          (list "curl_easy_perform" '(__collect_safe) can-block)
+          (list "curl_easy_perform" '() can-block)
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [720 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [498 more]
FAIL wrapper-safe: __collect_safe in the known wrapper's template: every use gets it
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((mism [98 more]
  actual:   (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((mism [202 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB2. curl_multi_poll's row made plain

```diff
-          (list "curl_multi_poll" '(__collect_safe) can-block)
+          (list "curl_multi_poll" '() can-block)
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [718 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [500 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB3. curl_multi_perform's row made __collect_safe

```diff
-          (list "curl_multi_perform" '() multi-perform-plain)
+          (list "curl_multi_perform" '(__collect_safe) multi-perform-plain)
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [721 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [497 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB4. memcpy's row made __collect_safe

```diff
-          (list "memcpy" '() memcpy-plain)))
+          (list "memcpy" '(__collect_safe) memcpy-plain)))
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [709 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [509 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB5. one of the six current rows, curl_easy_cleanup's, made __collect_safe

```diff
-          (list "curl_easy_cleanup" '() cannot-block)
+          (list "curl_easy_cleanup" '(__collect_safe) cannot-block)
```

**Result:** killed, exit 2:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((mismatch "curl_easy_cleanup" (__collect_safe) () "src/curl/private/native.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB6. a second row for a key accepted

```diff
-              ((member (car row) keys)
-               (loop (cdr rows) keys (append found (list (list 'duplicate-row (car row))))))
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: two rows for one key
  expected: (returned ((duplicate-row "x")))
  actual:   (returned ())
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB7. a citation's phrase not looked for

```diff
-        (and (string? text) (search (squeezed text) (squeezed phrase)) #t))))
+        #t)))
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a phrase the record does not hold
  expected: (returned ((citation-phrase-missing "x" ".plans/decisions/0013-collect-safe-blocking-calls.md" "Calls that can block stay plain.")))
  actual:   (returned ())
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB8. a phrase matched without squeezing whitespace

```diff
-        (and (string? text) (search (squeezed text) (squeezed phrase)) #t))))
+        (and (string? text) (search text phrase) #t))))
```

**Result:** killed, exit 2:

```
FAIL the table's citations each name a decision record that exists, and quote it
  expected: (returned ())
  actual:   (returned ((citation-phrase-missing "curl_easy_perform" ".plans/decisions/0013-collect-safe-blocking-calls.md" "Known now: `curl_multi_poll` and `curl_easy_perform`.") (citation-phrase-missing "curl_multi_poll" ".plans/decisions [299 more]
FAIL table-problems, seeded: a callable's row, keyed by a symbol, and a phrase across a line break
  expected: (returned ())
  actual:   (returned ((citation-phrase-missing "y" ".plans/decisions/0013-collect-safe-blocking-calls.md" "It covers `curl_multi_perform` too, which curl documents as non-blocking, until E1 says otherwise.")))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB9. a citation may climb out of .plans/decisions/

```diff
-           (and (> (string-length name) 0)
-                (not (memv #\/ (string->list name)))))
+           (> (string-length name) 0))
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a citation climbing out of .plans/decisions/
  expected: (returned ((citation-not-a-record "x" ".plans/decisions/../progress.md")))
  actual:   (returned ())
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB10. a citation need not start with .plans/decisions/

```diff
-    (and (prefix? path records)
+    (and #t
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a citation naming a file outside .plans/decisions/
  expected: (returned ((citation-not-a-record "x" "AGENTS.md")))
  actual:   (raised "Exception in substring: 17 and 9 are not valid start/end indices for \"AGENTS.md\"")
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB11. an empty phrase accepted

```diff
-           (< (+ at 2) (string-length citation))
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a citation with an empty phrase
  expected: (returned ((citation-shape "x" ".plans/decisions/0013-collect-safe-blocking-calls.md: ")))
  actual:   (returned ())
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB12. a row whose citation is no string accepted as shaped

```diff
-         (list? (cadr row))
-         (string? (caddr row))))
+         (list? (cadr row))))
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: rows not shaped (key conventions citation)
  expected: (returned ((row-shape ("a" ())) (row-shape (42 () ".plans/decisions/0013-collect-safe-blocking-calls.md: Calls that cannot block stay plain.")) (row-shape ("c" __collect_safe ".plans/decisions/0013-collect-safe-blocking-calls.md [66 more]
  actual:   (raised "Exception in string-length: 13 is not a string")
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB13. a citation's record need not exist

```diff
-                (not (memv #\/ (string->list name)))))
-         (file-regular? (string-append root "/" path))))
+                (not (memv #\/ (string->list name)))))))
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a citation naming no file
  expected: (returned ((citation-not-a-record "x" ".plans/decisions/9999-no-such-record.md")))
  actual:   (returned ((citation-phrase-missing "x" ".plans/decisions/9999-no-such-record.md" "Calls that cannot block stay plain.")))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### TB14. a citation that is not RECORD: PHRASE accepted

```diff
-                                 ((not parts) (list (list 'citation-shape key citation)))
+                                 ((not parts) '())
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a citation with no phrase
  expected: (returned ((citation-shape "x" ".plans/decisions/0013-collect-safe-blocking-calls.md")))
  actual:   (returned ())
FAIL table-problems, seeded: a citation with an empty phrase
  expected: (returned ((citation-shape "x" ".plans/decisions/0013-collect-safe-blocking-calls.md: ")))
  actual:   (returned ())
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### KW1. a known wrapper src/ does not define

```diff
-  (define known-wrappers '(bind-required))
+  (define known-wrappers '(bind-required bind-optional))
```

**Result:** killed, exit 2:

```
FAIL known-wrappers is exactly the wrappers src/ defines
  expected: (returned (bind-required bind-optional))
  actual:   (returned (bind-required))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### KW2. bind-required no known wrapper

```diff
-  (define known-wrappers '(bind-required))
+  (define known-wrappers '())
```

**Result:** killed, exit 2:

```
FAIL legal: every accounted place: the import, the known wrapper and its uses in two files, direct bindings, two conventions as a set, a template that is no wrapper, callables, and look-alikes
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/legal/curl/a.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/co [624 more]
  actual:   (returned ((("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("memcpy" () "tests/fixtures/conventions/legal/curl/a.sls" foreign-procedure) ("fixture_two_conventions" ((__vara [567 more]
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__c [604 more]
  actual:   (returned ((("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("curl_multi_perform" (__collect_safe) "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure) ("memcp [523 more]
FAIL wrapper-safe: __collect_safe in the known wrapper's template: every use gets it
  expected: (returned ((("curl_easy_init" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required) ("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/wrapper-safe/curl/w.sls" bind-required)) ((mism [98 more]
  actual:   (returned (() ((entry-not-string "tests/fixtures/conventions/wrapper-safe/curl/w.sls" "(foreign-procedure __collect_safe entry (arg ...) result)"))))
FAIL wrapper-pattern-conventions: the known wrapper's conventions come from a pattern variable
  expected: (returned (() ((wrapper-conventions-from-pattern "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" bind-required (conv)))))
  actual:   (returned (() ((entry-not-string "tests/fixtures/conventions/wrapper-pattern-conventions/curl/w.sls" "(foreign-procedure conv entry (arg ...) result)"))))
FAIL wrapper-entry-not-string: uses of the known wrapper whose entry is no string literal: a variable, an expression, none at all
  expected: (returned (() ((wrapper-entry-not-string "tests/fixtures/conventions/wrapper-entry-not-string/curl/u.sls" bind-required "(bind-required name () uptr #f)") (wrapper-entry-not-string "tests/fixtures/conventions/wrapper-entry-not-s [228 more]
  actual:   (returned (() ((entry-not-string "tests/fixtures/conventions/wrapper-entry-not-string/curl/u.sls" "(foreign-procedure entry (arg ...) result)"))))
FAIL wrapper-undefined: a use of the known wrapper that no file defines
  expected: (returned (() ((wrapper-undefined "tests/fixtures/conventions/wrapper-undefined/curl/u.sls" bind-required "(bind-required \"curl_easy_init\" () uptr #f)"))))
  actual:   (returned (() ()))
FAIL wrapper-defined-again: the known wrapper defined in two files: no use is read against either
[9 more lines cut]
```

### FX1. a fixture directory no case runs

```sh
mkdir -p tests/fixtures/conventions/orphan/curl
cp tests/fixtures/conventions/legal/curl/a.sls tests/fixtures/conventions/orphan/curl/a.sls
```

**Result:** killed, exit 2:

```
FAIL every fixture directory is a case above, and every case has its directory
  expected: ("blocking-plain" "callable-misplaced" "cyclic" "dir-symlink" "entry-not-string" "extensions" "imports" "legal" "lock-file" "malformed" "mismatch" "no-row" "quoted" "shared-structure" "stray" "unreadable" "wrapper-defined-again" [114 more]
  actual:   ("blocking-plain" "callable-misplaced" "cyclic" "dir-symlink" "entry-not-string" "extensions" "imports" "legal" "lock-file" "malformed" "mismatch" "no-row" "orphan" "quoted" "shared-structure" "stray" "unreadable" "wrapper-defin [123 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### FX2. a case whose fixture directory is gone

```sh
rm -r tests/fixtures/conventions/lock-file
```

**Result:** killed, exit 2:

```
FAIL lock-file: a .# dangling link, Emacs's lock file, is skipped; a .# regular file is read; another dangling link is named
  expected: (returned ((("curl_easy_init" () "tests/fixtures/conventions/lock-file/curl/a.sls" foreign-procedure)) ((stray "tests/fixtures/conventions/lock-file/curl/.#b.sls" "(quote foreign-callable)") (unreadable "tests/fixtures/conventio [157 more]
  actual:   (returned (() ((no-sources "tests/fixtures/conventions/lock-file"))))
FAIL every fixture directory is a case above, and every case has its directory
  expected: ("blocking-plain" "callable-misplaced" "cyclic" "dir-symlink" "entry-not-string" "extensions" "imports" "legal" "lock-file" "malformed" "mismatch" "no-row" "quoted" "shared-structure" "stray" "unreadable" "wrapper-defined-again" [114 more]
  actual:   ("blocking-plain" "callable-misplaced" "cyclic" "dir-symlink" "entry-not-string" "extensions" "imports" "legal" "malformed" "mismatch" "no-row" "quoted" "shared-structure" "stray" "unreadable" "wrapper-defined-again" "wrapper-en [102 more]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### Clean rerun

On the worktree itself, after every mutation, whose files hash to the snapshot's sum.
`make test` exited 0:

```
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
check-suites: every suite ends with (exit (suite-exit-status runner)) (11 checked)
check-seam: the seam holds (9 libraries in 9 files checked)
=== tests/test-check-seam.sps
%%%% Starting test check-seam
# of expected passes      41
test: pass tests/test-check-seam.sps
=== tests/test-collect-safe.sps
%%%% Starting test collect-safe
# of expected passes      38
test: pass tests/test-collect-safe.sps
=== tests/test-conditions.sps
%%%% Starting test conditions
# of expected passes      11
test: pass tests/test-conditions.sps
=== tests/test-curl-testing.sps
%%%% Starting test curl-testing
# of expected passes      49
test: pass tests/test-curl-testing.sps
[30 more lines cut]
```

## The floors

Evidence for the checks that hold every statement of a version floor to `packaging/floors.sexp`
(harness plan §3, item 5):

- `packaging/floors.sexp`, the one file that writes the Chez, libcurl and Node floors;
- `tests/floors.sls`, `(floors)`: the rules for the file and for the README, and a floor by name;
- `tests/check-floors.sps` and `make check-floors`: the program, and its Makefile target;
- `tests/test-check-floors.sps` and `tests/fixtures/floors/`: the suite that holds each rule;
- the floors rows added to `tests/test-verify.sps` and `tests/test-require-threaded.sps`, which
  read the file and hold `libcurl-floor` and the Chez refusal to it by behaviour;
- the `floors` case of `tests/check-test-fails.sh`, and `check-floors` among `make test`'s
  prerequisites.

A driver in the session scratchpad ran every mutation. It copied the working tree, without `.git`
or `build/`, into a fresh directory for each mutation, and touched the copy's `manifest.scm`
(`traps.md`, the stale `guix shell -m` profile). It applied the mutation by exact-text
replacement, aborting unless the text occurred exactly once, and refused a mutation whose diff
was empty. It ran the copy through `scripts/guix-env`, and kept each run's whole output. The
working tree was never edited.

Most runs are three steps in one container: `make check-floors`, then each of
`tests/test-check-floors.sps`, `tests/test-verify.sps` and `tests/test-require-threaded.sps`
directly. `make test` is not used for them: `check-floors` is its prerequisite, so a mutation
that makes it fail would hide the suites. A suite that exits non-zero is printed as
`test: FAIL <suite> (exit N)`, as `make test` prints it, and `status:` lines give the exit status
of each step. MK1 and the mutations that change what check-floors reports about the whole run
use `make check-test-fails` or `make check-help`.

A mutation counts as killed when the run exits non-zero and the line that names its rule is in
the output: a `check-floors:` line, or a suite's `FAIL <test name>` with its expected and actual
values. Exit status alone is not taken for a kill. (The first runs of FL11, P5 and MK8, the three
that run `make check-floors` and `make check-test-fails` in one container, exited 2 because
the driver's own shell syntax was wrong, and never ran `make check-test-fails`; they were
rerun after the driver was fixed, and the review of each result found it.) **Result** quotes only those lines, each cut at 240 characters and
saying how much was cut, and at most 18 lines per run. A longer output says how many lines were
cut. Every whole output is kept.

Cases are named `FL` (a floor stated in the README, the floors file or the Scheme code, as the
brief lists them), `F` (a rule for the floors file, in `(floors)`), `R` (a rule for the README),
`A` (what `(floors)` answers a suite), `P` (the program), `MK` (the Makefile and
`check-test-fails`) and `FX` (the suite's own guards).

### Red runs

**Before any code existed:** `tests/test-check-floors.sps`, its fixtures, the new rows in
`test-verify` and `test-require-threaded`, and the `floors` case of `check-test-fails.sh` were
written. There was no `(floors)` library, no `tests/check-floors.sps`, no
`packaging/floors.sexp`, no README section, and no Makefile target. `make test` exited 2. Three
suites died at import, with no test run:

```
Exception: library (floors) not found
test: FAIL tests/test-check-floors.sps (exit 255)
Exception: library (floors) not found
test: FAIL tests/test-require-threaded.sps (exit 255)
Exception: library (floors) not found
test: FAIL tests/test-verify.sps (exit 255)
test: ran 11, passed 8, failed 3, hung 0
```

**Against a stub:** a `(floors)` library with the real export list, `floors-path` the string
`"stub"`, and every procedure raising `not written yet`. `make test` exited 2:

| Suite | Passed | Failed |
|---|---|---|
| `test-check-floors` | 2 | 174 |
| `test-require-threaded` | 42 | 15 |
| `test-verify` | 18 | 4 |

The two passes in `test-check-floors` are `CHEZ names the Chez to spawn` and `every fixture
directory is a case above, and every case has its directory`: neither calls `(floors)`. FX1 to
FX3 fail them. The four `test-verify` failures:

```
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
  actual:   (assertion-violation <)
FAIL check-version: the refusal's message names the floor of packaging/floors.sexp
  expected: no-floor-text
  actual:   raised-something-else
```

The expected values are symbols, not raises: a floors file the stub cannot read gives the suite a
sentinel to fail on by name, and nothing raises in an expected expression. The fifteen
`test-require-threaded` failures are the seven existing literal rows, now expecting the message
the file gives (`(refused chez-curl floors-file-unreadable)` against the real message), and the
eight rows built from the file (`actual: no-such-version`):

```
FAIL where Chez is Chez Scheme Version 10.3.0, the refusal raises its message naming the floor
  expected: (refused chez-curl floors-file-unreadable)
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
FAIL where Chez is the floor of packaging/floors.sexp, the refusal lets its library load
  expected: loaded
  actual:   no-such-version
FAIL where Chez's major number is one below the floor of packaging/floors.sexp, the refusal raises its message naming the floor
  expected: (refused chez-curl floors-file-unreadable)
  actual:   no-such-version
```

The `test-check-floors` failures are every other test in it, named; the whole run is kept in
`C/red2-test.txt`.

**`make check-test-fails`, before the Makefile target and the README section:** the new case
failed, and the other nine passed:

```
check-test-fails: FAILED floors: could not read the Chez floor from packaging/floors.sexp
check-test-fails: FAILED floors: the plant did not change README.org, so it plants nothing
check-test-fails: FAILED floors: check-floors names a README that states another Chez floor, and no suite runs: make test exited 0
check-test-fails: FAILED floors: check-floors names a README that states another Chez floor, and no suite runs: make test's lines differ
  wanted: check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
  wanted: check-floors: README.org: list line 1 under "** Requirements" is "- Chez Scheme 10.3.0 or later, built with threads", but packaging/floors.sexp gives "- Chez Scheme 0.0.0 or later, built with threads"
  wanted: check-floors: FAILED (problems: 1)
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
  got:    test: pass tests/test-1-after.sps
  got:    test: ran 1, passed 1, failed 0, hung 0
```

**The first green run** failed two tests, both written wrongly: Chez words an assertion
violation's irritant as `no such floor with irritant python`, and the tests expected `no such
floor python`. The tests were corrected; no code changed. One row, the line indented with a tab,
was added after the stub run, for R3f.

### Mutations

99 mutations ran. 99 were killed, each by the line that names its rule. 0 survived.

**README against the floors file**

### FL1. README's Chez line says 10.3.0

```diff
-- Chez Scheme 10.4.0 or later, built with threads
+- Chez Scheme 10.3.0 or later, built with threads
```

**Result:** killed, exit 1:

```
check-floors: README.org: list line 1 under "** Requirements" is "- Chez Scheme 10.3.0 or later, built with threads", but packaging/floors.sexp gives "- Chez Scheme 10.4.0 or later, built with threads"
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
```

### FL2. README's libcurl line deleted

```diff
-- libcurl 7.85.0 or later, built with TLS
```

**Result:** killed, exit 1:

```
check-floors: README.org: "** Requirements" lacks the list line "- libcurl 7.85.0 or later, built with TLS", which packaging/floors.sexp gives
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
```

### FL3. an extra README line

```diff
+- Python 3 or later
```

**Result:** killed, exit 1:

```
check-floors: README.org: "** Requirements" has an extra list line, "- Python 3 or later", which packaging/floors.sexp does not give
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
```

### FL3b. README's Chez and libcurl lines swapped

```diff
-- Chez Scheme 10.4.0 or later, built with threads
+- Chez Scheme 10.4.0 or later, built with threads
```

**Result:** killed, exit 1:

```
check-floors: README.org: list line 1 under "** Requirements" is "- libcurl 7.85.0 or later, built with TLS", but packaging/floors.sexp gives "- Chez Scheme 10.4.0 or later, built with threads"
check-floors: README.org: list line 2 under "** Requirements" is "- Chez Scheme 10.4.0 or later, built with threads", but packaging/floors.sexp gives "- libcurl 7.85.0 or later, built with TLS"
check-floors: FAILED (problems: 2)
status: make check-floors exit=2
```

### FL3c. README's libcurl line with a space at its end

```diff
-- libcurl 7.85.0 or later, built with TLS
+- libcurl 7.85.0 or later, built with TLS 
```

**Result:** killed, exit 1:

```
check-floors: README.org: list line 2 under "** Requirements" is "- libcurl 7.85.0 or later, built with TLS ", but packaging/floors.sexp gives "- libcurl 7.85.0 or later, built with TLS"
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
```

### FL3d. a second Requirements section in README

```diff
+** Requirements
+
+- Chez Scheme 10.4.0 or later, built with threads
+- libcurl 7.85.0 or later, built with TLS
+- Node.js 20 or later, for the tests
+
```

**Result:** killed, exit 1:

```
check-floors: README.org: it has 2 "** Requirements" sections, but must have one
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
```

### FL4. README's Requirements section removed

```diff
-** Requirements
-
-- Chez Scheme 10.4.0 or later, built with threads
-- libcurl 7.85.0 or later, built with TLS
-- Node.js 20 or later, for the tests
-
```

**Result:** killed, exit 1:

```
check-floors: README.org: it has no "** Requirements" section
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
```

### FL4b. README's section renamed Prerequisites

```diff
-** Requirements
+** Prerequisites
```

**Result:** killed, exit 1:

```
check-floors: README.org: it has no "** Requirements" section
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
```

**The floors file against the code**

### FL5. floors.sexp: chez "10.5.0"

```diff
-((chez "10.4.0")
+((chez "10.5.0")
```

**Result:** killed, exit 1:

```
check-floors: README.org: list line 1 under "** Requirements" is "- Chez Scheme 10.4.0 or later, built with threads", but packaging/floors.sexp gives "- Chez Scheme 10.5.0 or later, built with threads"
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL where Chez is Chez Scheme Version 10.3.0, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.5.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
FAIL where Chez is Chez Scheme Version 9.5.9, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.5.0 or later, and this one is 9.5.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
FAIL where Chez is Chez Scheme Version 10.3.9, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.5.0 or later, and this one is 10.3.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.9")
FAIL where Chez is Chez Scheme Version 10.3.0-pre-release.2, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.5.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.5.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
[19 more lines; the whole output is kept]
```

### FL6. floors.sexp: libcurl "7.86.0"

```diff
- (libcurl "7.85.0")
+ (libcurl "7.86.0")
```

**Result:** killed, exit 1:

```
check-floors: README.org: list line 2 under "** Requirements" is "- libcurl 7.85.0 or later, built with TLS", but packaging/floors.sexp gives "- libcurl 7.86.0 or later, built with TLS"
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: 480768
  actual:   480512
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.85.255" () the-report)
  actual:   (returned #t)
FAIL check-version: the refusal's message names the floor of packaging/floors.sexp
  expected: "libcurl 7.85.255 is older than chez-curl's floor, 7.86.0; name a newer one with CHEZ_CURL_LIBCURL"
  actual:   no-raise
test: FAIL tests/test-verify.sps (exit 1)
```

### FL10. floors.sexp: libcurl "7.85", two numbers

```diff
- (libcurl "7.85.0")
+ (libcurl "7.85")
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: libcurl: the version "7.85" is not three dot-separated naturals, major.minor.patch
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: libcurl: the version \"7.85\" is not three dot-separated naturals, major.minor.patch"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: libcurl: the version \"7.85\" is not three dot-separated naturals, major.minor.patch")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL11. the libcurl floor lowered to 7.84.0 in floors.sexp, README and verify.sls together: check-floors and check-test-fails stay green, only the literal rows fail

```diff
- (libcurl "7.85.0")
+ (libcurl "7.84.0")
-- libcurl 7.85.0 or later, built with TLS
+- libcurl 7.84.0 or later, built with TLS
-  (define libcurl-floor #x075500)
+  (define libcurl-floor #x075400)
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.84.0, node 20)
status: make check-floors exit=0
FAIL the floor is 7.85.0, #x075500
  expected: 480512
  actual:   480256
FAIL check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.84.255" () the-report)
  actual:   (returned #t)
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (no-raise readable readable readable)
test: FAIL tests/test-verify.sps (exit 1)
check-test-fails: make test failed, as it must, in all 10 cases
status: make check-test-fails exit=0
```

**The floors file's own rules (FL9)**

### FL9a. floors.sexp: node missing

```diff
- (libcurl "7.85.0")
- (node "20"))
+ (libcurl "7.85.0"))
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: the key node is missing
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: the key node is missing"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: the key node is missing")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9b. floors.sexp: an extra key

```diff
- (node "20"))
+ (node "20")
+ (python "3"))
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: the key python is extra: the keys are chez, libcurl, node
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: the key python is extra: the keys are chez, libcurl, node"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: the key python is extra: the keys are chez, libcurl, node")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9c. floors.sexp: chez "10.4"

```diff
-((chez "10.4.0")
+((chez "10.4")
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: chez: the version "10.4" is not three dot-separated naturals, major.minor.patch
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: chez: the version \"10.4\" is not three dot-separated naturals, major.minor.patch"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: chez: the version \"10.4\" is not three dot-separated naturals, major.minor.patch")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9d. floors.sexp: keys reordered

```diff
-((chez "10.4.0")
- (libcurl "7.85.0")
+((libcurl "7.85.0")
+ (chez "10.4.0")
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: the keys are in the order libcurl, chez, node, but must be chez, libcurl, node
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: the keys are in the order libcurl, chez, node, but must be chez, libcurl, node"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: the keys are in the order libcurl, chez, node, but must be chez, libcurl, node")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9e. floors.sexp: a second datum

```diff
+(more)
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: it holds 2 data, but must hold exactly one
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: it holds 2 data, but must hold exactly one"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: it holds 2 data, but must hold exactly one")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9f. floors.sexp: a closing parenthesis missing

```diff
- (node "20"))
+ (node "20")
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: it cannot be read as data: Exception in read: unexpected end-of-file reading list at char 112 of #<input port string>
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: it cannot be read as data: Exception in read: unexpected end-of-file reading list at char 112 of #<input port string>"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: it cannot be read as data: Exception in read: unexpected end-of-file reading list at char 112 of #<input port string>")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9g. floors.sexp: libcurl "7.x.0"

```diff
- (libcurl "7.85.0")
+ (libcurl "7.x.0")
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: libcurl: the version "7.x.0" is not three dot-separated naturals, major.minor.patch
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: libcurl: the version \"7.x.0\" is not three dot-separated naturals, major.minor.patch"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: libcurl: the version \"7.x.0\" is not three dot-separated naturals, major.minor.patch")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9h. floors.sexp: node's version a number, not a string

```diff
- (node "20"))
+ (node 20))
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: node: the version 20 is not dot-separated naturals
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: node: the version 20 is not dot-separated naturals"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: node: the version 20 is not dot-separated naturals")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9i. floors.sexp: chez "10.04.0", a leading zero

```diff
-((chez "10.4.0")
+((chez "10.04.0")
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: chez: the version "10.04.0" is not three dot-separated naturals, major.minor.patch
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: chez: the version \"10.04.0\" is not three dot-separated naturals, major.minor.patch"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: chez: the version \"10.04.0\" is not three dot-separated naturals, major.minor.patch")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9j. floors.sexp: only a comment

```diff
-;; The version floors chez-curl supports; `make check-floors` and the suites hold everything else to this file.
-((chez "10.4.0")
- (libcurl "7.85.0")
- (node "20"))
+;; nothing here
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: it holds no datum, but must hold exactly one
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (returned ("packaging/floors.sexp: it holds no datum, but must hold exactly one"))
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: it holds no datum, but must hold exactly one")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

### FL9k. floors.sexp: deleted

```diff
Only in <worktree>/packaging: floors.sexp
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for packaging/floors.sexp: no such file or directory
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (raised "Exception in open-file-input-port: failed for packaging/floors.sexp: no such file or directory")
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in open-file-input-port: failed for packaging/floors.sexp: no such file or directory")
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: floors-file-unreadable
  actual:   480512
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (assertion-violation <)
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system no-version-below () the-report)
[51 more lines; the whole output is kept]
```

**The Scheme floors, by behaviour**

### FL7. verify.sls: libcurl-floor is #x075600

```diff
-  (define libcurl-floor #x075500)
+  (define libcurl-floor #x075600)
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL the floor is 7.85.0, #x075500
  expected: 480512
  actual:   480768
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: 480512
  actual:   480768
FAIL check-version: the floor of packaging/floors.sexp is accepted
  expected: (returned #t)
  actual:   (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.85.0" () the-report)
FAIL check-version: the refusal's message names the floor of packaging/floors.sexp
  expected: "libcurl 7.84.255 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL"
  actual:   "libcurl 7.84.255 is older than chez-curl's floor, 7.86.0; name a newer one with CHEZ_CURL_LIBCURL"
FAIL check-version: the floor itself, #x075500, is accepted
  expected: (returned #t)
  actual:   (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.85.0" () the-report)
test: FAIL tests/test-verify.sps (exit 1)
```

### FL7b. verify.sls: check-version accepts one below the floor

```diff
-      ((< version-num libcurl-floor)
+      ((< version-num (- libcurl-floor 1))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL check-version: one below the floor of packaging/floors.sexp is below-floor, with that version
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.84.255" () the-report)
  actual:   (returned #t)
FAIL check-version: the refusal's message names the floor of packaging/floors.sexp
  expected: "libcurl 7.84.255 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL"
  actual:   no-raise
FAIL check-version: one below the floor, #x0754ff, is below-floor, with the version, path and source
  expected: (refused below-floor "/usr/lib/aarch64-linux-gnu/libcurl.so.4" system "7.84.255" () the-report)
  actual:   (returned #t)
FAIL check-version and check-apis: every refusal carries a who and a message, for the default handler
  expected: (readable readable readable readable)
  actual:   (no-raise readable readable readable)
test: FAIL tests/test-verify.sps (exit 1)
```

### FL7c. verify.sls: version->string reads the minor number wrong, so the message names another floor

```diff
-                   (number->string (bitwise-and (bitwise-arithmetic-shift-right num 8) #xff)) "."
+                   (number->string (bitwise-and num #xff)) "."
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL check-version: the refusal's message names the floor of packaging/floors.sexp
  expected: "libcurl 7.84.255 is older than chez-curl's floor, 7.85.0; name a newer one with CHEZ_CURL_LIBCURL"
  actual:   "libcurl 7.84.255 is older than chez-curl's floor, 7.0.0; name a newer one with CHEZ_CURL_LIBCURL"
test: FAIL tests/test-verify.sps (exit 1)
```

### FL8. require-threaded.sls: minimum is '(10 4 1)

```diff
-      (define minimum '(10 4 0))
+      (define minimum '(10 4 1))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
test: FAIL tests/test-verify.sps (exit 255)
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.1 or later, and this one is 10.4.0 (require-supported-chez)"
FAIL where Chez is Chez Scheme Version 10.3.0, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.1 or later, and this one is 10.3.0")
FAIL where Chez is Chez Scheme Version 9.5.9, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.1 or later, and this one is 9.5.9")
FAIL where Chez is Chez Scheme Version 10.3.9, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.1 or later, and this one is 10.3.9")
FAIL where Chez is Chez Scheme Version 10.3.0-pre-release.2, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.1 or later, and this one is 10.3.0")
[31 more lines; the whole output is kept]
```

### FL8b. require-threaded.sls: the message names 10.3.0, not the minimum

```diff
-             (string-append "chez-curl needs Chez Scheme " (dotted minimum)
+             (string-append "chez-curl needs Chez Scheme " "10.3.0"
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL where Chez is Chez Scheme Version 10.3.0, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.3.0 or later, and this one is 10.3.0")
FAIL where Chez is Chez Scheme Version 9.5.9, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 9.5.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.3.0 or later, and this one is 9.5.9")
FAIL where Chez is Chez Scheme Version 10.3.9, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.9")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.3.0 or later, and this one is 10.3.9")
FAIL where Chez is Chez Scheme Version 10.3.0-pre-release.2, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.3.0 or later, and this one is 10.3.0")
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.3.0 or later, and this one is 10.4.0-pre-release.1")
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming the floor
[18 more lines; the whole output is kept]
```

### FL8c. require-threaded.sls: a pre-release of the floor is never refused

```diff
-               (pre (and (equal? have minimum)
-                         (pre-release-suffix (scheme-version #t)))))
+               (pre #f))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL the refusal asks (scheme-version #t), which says whether this Chez is a pre-release
  expected: asks
  actual:   never-asks
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.1, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.7, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.7")
  actual:   loaded
FAIL where Chez is Chez Scheme Version 10.4.0-pre-release.12, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.12")
  actual:   loaded
FAIL where Chez is a pre-release of the floor of packaging/floors.sexp, number 1, the refusal raises its message naming the floor
  expected: (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0-pre-release.1")
  actual:   loaded
FAIL where Chez is a pre-release of the floor of packaging/floors.sexp, number 7, the refusal raises its message naming the floor
[6 more lines; the whole output is kept]
```

### FL8d. require-threaded.sls: a Chez whose major number equals the floor's is always refused

```diff
-              (else (older? (cdr have) (cdr want)))))
+              (else #t)))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
test: FAIL tests/test-verify.sps (exit 255)
FAIL on this threaded Chez, the refusal lets its library load
  expected: loaded
  actual:   "Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0 (require-supported-chez)"
FAIL where Chez is Chez Scheme Version 10.4.0, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.0")
FAIL where Chez is Chez Scheme Version 10.5.1, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.5.1")
FAIL where Chez is Chez Scheme Version 10.10.0, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.10.0")
FAIL where Chez is Chez Scheme Version 10.4.1-pre-release.1, the refusal lets its library load
  expected: loaded
  actual:   (refused chez-curl "chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.4.1")
[13 more lines; the whole output is kept]
```

**`(floors)`: the floors file's rules (F)**

### F1. floors: an empty floors file is no longer a problem

```diff
-                   (list (string-append path ": it holds no datum, but must hold exactly one")))
+                   '())
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: an empty file holds no datum
  expected: (returned ("f.sexp: it holds no datum, but must hold exactly one"))
  actual:   (returned ())
FAIL floors file: a file of comments holds no datum
  expected: (returned ("f.sexp: it holds no datum, but must hold exactly one"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F2. floors: a second datum is no longer a problem

```diff
-                  ((pair? (cdr data))
-                   (list (string-append path ": it holds " (number->string (length data))
-                                        " data, but must hold exactly one")))
+
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: a second datum
  expected: (returned ("f.sexp: it holds 2 data, but must hold exactly one"))
  actual:   (returned ())
FAIL floors file: three data
  expected: (returned ("f.sexp: it holds 3 data, but must hold exactly one"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F3. floors: a reader error reads as no datum

```diff
-    (guard (e (#t (list 'unreadable (describe e))))
+    (guard (e (#t (list 'data '())))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: a datum cut short cannot be read
  expected: (returned ("f.sexp: it cannot be read as data: Exception in read: unexpected end-of-file reading list at char 0 of #<input port string>"))
  actual:   (returned ("f.sexp: it holds no datum, but must hold exactly one"))
FAIL floors file: an #!eof literal would end the reading early
  expected: (returned ("f.sexp: it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file"))
  actual:   (returned ("f.sexp: it holds no datum, but must hold exactly one"))
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F4. floors: an #!eof literal ends the reading quietly

```diff
-                  (else (error 'read "an #!eof literal ends the reading before the end of the file"))))))))
+                  (else (list 'data (reverse found)))))))))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: an #!eof literal would end the reading early
  expected: (returned ("f.sexp: it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file"))
  actual:   (returned ("f.sexp: it holds no datum, but must hold exactly one"))
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F5. floors: a datum that is no list is not named

```diff
-    (if (not (list? datum))
+    (if #f
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: the datum is a number
  expected: (returned ("f.sexp: the datum is 42, not a list of (key \"version\") entries"))
  actual:   (raised "Exception in filter: 42 is not a proper list")
FAIL floors file: the datum is a string
  expected: (returned ("f.sexp: the datum is \"10.9.1\", not a list of (key \"version\") entries"))
  actual:   (raised "Exception in filter: \"10.9.1\" is not a proper list")
FAIL floors file: the datum is a dotted pair
  expected: (returned ("f.sexp: the datum is (chez . \"10.9.1\"), not a list of (key \"version\") entries"))
  actual:   (raised "Exception in filter: (chez . \"10.9.1\") is not a proper list")
FAIL floors file: the datum is a cyclic list, which is named and never walked
  expected: (returned ("f.sexp: the datum is #0=(a . #0#), not a list of (key \"version\") entries"))
  actual:   (raised "Exception in filter: (a a a a a a ...) is not a proper list")
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F6. floors: a malformed entry is not named

```diff
-           (map (lambda (x)
-                  (string-append path ": " (abbreviated x)
-                                 " is not an entry (key \"version\")"))
-                (remp entry? datum))
+           '()
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: an entry with a key and no version
  expected: (returned ("f.sexp: (libcurl) is not an entry (key \"version\")" "f.sexp: the key libcurl is missing"))
  actual:   (returned ("f.sexp: the key libcurl is missing"))
FAIL floors file: an entry with a key and two versions
  expected: (returned ("f.sexp: (chez \"10.9.1\" \"10.9.2\") is not an entry (key \"version\")" "f.sexp: the key chez is missing"))
  actual:   (returned ("f.sexp: the key chez is missing"))
FAIL floors file: an entry whose key is a string
  expected: (returned ("f.sexp: (\"chez\" \"10.9.1\") is not an entry (key \"version\")" "f.sexp: the key chez is missing"))
  actual:   (returned ("f.sexp: the key chez is missing"))
FAIL floors file: an entry that is no list
  expected: (returned ("f.sexp: chez is not an entry (key \"version\")" "f.sexp: the key chez is missing"))
  actual:   (returned ("f.sexp: the key chez is missing"))
FAIL floors file: the keys and versions in one flat list
  expected: (returned ("f.sexp: chez is not an entry (key \"version\")" "f.sexp: \"10.9.1\" is not an entry (key \"version\")" "f.sexp: the key chez is missing" "f.sexp: the key libcurl is missing" "f.sexp: the key node is missing"))
  actual:   (returned ("f.sexp: the key chez is missing" "f.sexp: the key libcurl is missing" "f.sexp: the key node is missing"))
FAIL floors file: several faults at once come in a fixed order: the entries, the keys, the versions
[3 more lines; the whole output is kept]
```

### F7. floors: a missing key is not named

```diff
-       (map (lambda (key)
-              (string-append path ": the key " (symbol->string key) " is missing"))
-            missing)
+       '()
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: an empty list names all three keys missing
  expected: (returned ("f.sexp: the key chez is missing" "f.sexp: the key libcurl is missing" "f.sexp: the key node is missing"))
  actual:   (returned ())
FAIL floors file: an entry with a key and no version
  expected: (returned ("f.sexp: (libcurl) is not an entry (key \"version\")" "f.sexp: the key libcurl is missing"))
  actual:   (returned ("f.sexp: (libcurl) is not an entry (key \"version\")"))
FAIL floors file: an entry with a key and two versions
  expected: (returned ("f.sexp: (chez \"10.9.1\" \"10.9.2\") is not an entry (key \"version\")" "f.sexp: the key chez is missing"))
  actual:   (returned ("f.sexp: (chez \"10.9.1\" \"10.9.2\") is not an entry (key \"version\")"))
FAIL floors file: an entry whose key is a string
  expected: (returned ("f.sexp: (\"chez\" \"10.9.1\") is not an entry (key \"version\")" "f.sexp: the key chez is missing"))
  actual:   (returned ("f.sexp: (\"chez\" \"10.9.1\") is not an entry (key \"version\")"))
FAIL floors file: an entry that is no list
  expected: (returned ("f.sexp: chez is not an entry (key \"version\")" "f.sexp: the key chez is missing"))
  actual:   (returned ("f.sexp: chez is not an entry (key \"version\")"))
FAIL floors file: the keys and versions in one flat list
[36 more lines; the whole output is kept]
```

### F8. floors: an extra key is not named

```diff
-       (map (lambda (key)
-              (string-append path ": the key " (symbol->string key)
-                             " is extra: the keys are "
-                             (joined ", " (map symbol->string required-keys))))
-            extra)
+       '()
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: an extra key
  expected: (returned ("f.sexp: the key python is extra: the keys are chez, libcurl, node"))
  actual:   (returned ())
FAIL floors file: an extra key first
  expected: (returned ("f.sexp: the key python is extra: the keys are chez, libcurl, node"))
  actual:   (returned ())
FAIL floors file: an extra key twice is named once
  expected: (returned ("f.sexp: the key python is extra: the keys are chez, libcurl, node"))
  actual:   (returned ())
FAIL floors file: a key in capitals is another key
  expected: (returned ("f.sexp: the key chez is missing" "f.sexp: the key Chez is extra: the keys are chez, libcurl, node"))
  actual:   (returned ("f.sexp: the key chez is missing"))
FAIL floors file: an extra key and a missing one, and no word about the order
  expected: (returned ("f.sexp: the key libcurl is missing" "f.sexp: the key python is extra: the keys are chez, libcurl, node"))
  actual:   (returned ("f.sexp: the key libcurl is missing"))
FAIL floors file: several faults at once come in a fixed order: the entries, the keys, the versions
[3 more lines; the whole output is kept]
```

### F9. floors: a repeated key is not named

```diff
-       (map (lambda (key)
-              (string-append path ": the key " (symbol->string key) " appears "
-                             (number->string (occurrences key keys)) " times"))
-            repeated)
+       '()
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: a key twice
  expected: (returned ("f.sexp: the key chez appears 2 times"))
  actual:   (returned ())
FAIL floors file: a key three times, and another twice
  expected: (returned ("f.sexp: the key node appears 3 times" "f.sexp: the key libcurl appears 2 times"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F10. floors: the order of the keys is not checked

```diff
-                (not (equal? keys required-keys)))
+                #f)
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: libcurl before chez
  expected: (returned ("f.sexp: the keys are in the order libcurl, chez, node, but must be chez, libcurl, node"))
  actual:   (returned ())
FAIL floors file: node first
  expected: (returned ("f.sexp: the keys are in the order node, chez, libcurl, but must be chez, libcurl, node"))
  actual:   (returned ())
FAIL floors file: node before libcurl
  expected: (returned ("f.sexp: the keys are in the order chez, node, libcurl, but must be chez, libcurl, node"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F11. floors: the count of numbers in a version is not checked

```diff
-            ((and numbers (or (not (cadr shape)) (= (length numbers) (cadr shape)))) '())
+            (numbers '())
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: chez "10.9" is not three dot-separated naturals
  expected: (returned ("f.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: libcurl "10.9" is not three dot-separated naturals
  expected: (returned ("f.sexp: libcurl: the version \"10.9\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: chez "10" is not three dot-separated naturals
  expected: (returned ("f.sexp: chez: the version \"10\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: libcurl "10" is not three dot-separated naturals
  expected: (returned ("f.sexp: libcurl: the version \"10\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: chez "10.9.1.2" is not three dot-separated naturals
  expected: (returned ("f.sexp: chez: the version \"10.9.1.2\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: libcurl "10.9.1.2" is not three dot-separated naturals
[18 more lines; the whole output is kept]
```

### F11b. floors: Chez's version may have any count of numbers

```diff
-    '((chez 3 "three dot-separated naturals, major.minor.patch")
+    '((chez #f "three dot-separated naturals, major.minor.patch")
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: chez "10.9" is not three dot-separated naturals
  expected: (returned ("f.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: chez "10" is not three dot-separated naturals
  expected: (returned ("f.sexp: chez: the version \"10\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: chez "10.9.1.2" is not three dot-separated naturals
  expected: (returned ("f.sexp: chez: the version \"10.9.1.2\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: a version longer than the message shows is cut
  expected: (returned ("f.sexp: chez: the version \"11111111111111111111111111111111111111111111111111111111... is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: several faults at once come in a fixed order: the entries, the keys, the versions
  expected: (returned ("f.sexp: (libcurl) is not an entry (key \"version\")" "f.sexp: the key libcurl is missing" "f.sexp: the key python is extra: the keys are chez, libcurl, node" "f.sexp: chez: the version \"10.9\" is not three dot-separ [+99 chars]
  actual:   (returned ("f.sexp: (libcurl) is not an entry (key \"version\")" "f.sexp: the key libcurl is missing" "f.sexp: the key python is extra: the keys are chez, libcurl, node" "f.sexp: node: the version \"x\" is not dot-separated natu [+7 chars]
FAIL floors-invalid: a floors file with a missing key and a bad version: both named, and the README not read
[9 more lines; the whole output is kept]
```

### F11c. floors: libcurl's version must have two numbers

```diff
-      (libcurl 3 "three dot-separated naturals, major.minor.patch")
+      (libcurl 2 "three dot-separated naturals, major.minor.patch")
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: libcurl: the version "7.85.0" is not three dot-separated naturals, major.minor.patch
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL floors file: the base text is legal
  expected: (returned ())
  actual:   (returned ("f.sexp: libcurl: the version \"8.1.2\" is not three dot-separated naturals, major.minor.patch"))
FAIL floors file: a comment above, between, after and inside the datum is no datum
  expected: (returned ())
  actual:   (returned ("f.sexp: libcurl: the version \"8.1.2\" is not three dot-separated naturals, major.minor.patch"))
FAIL floors file: zero is a natural, and so is a number of several digits
  expected: (returned ())
  actual:   (returned ("f.sexp: libcurl: the version \"10.0.10\" is not three dot-separated naturals, major.minor.patch"))
FAIL floors file: Node may be one number, or several
  expected: (returned ())
  actual:   (returned ("f.sexp: libcurl: the version \"8.1.2\" is not three dot-separated naturals, major.minor.patch"))
FAIL floors file: Node may be one number, or several: three
  expected: (returned ())
  actual:   (returned ("f.sexp: libcurl: the version \"8.1.2\" is not three dot-separated naturals, major.minor.patch"))
[444 more lines; the whole output is kept]
```

### F12. floors: a leading zero is allowed

```diff
-         (or (string=? s "0") (not (char=? (string-ref s 0) #\0)))))
+         #t))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: chez "10.09.1" is not three dot-separated naturals
  expected: (returned ("f.sexp: chez: the version \"10.09.1\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: libcurl "10.09.1" is not three dot-separated naturals
  expected: (returned ("f.sexp: libcurl: the version \"10.09.1\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: chez "00.9.1" is not three dot-separated naturals
  expected: (returned ("f.sexp: chez: the version \"00.9.1\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: libcurl "00.9.1" is not three dot-separated naturals
  expected: (returned ("f.sexp: libcurl: the version \"00.9.1\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: node "022" is not dot-separated naturals
  expected: (returned ("f.sexp: node: the version \"022\" is not dot-separated naturals"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F13. floors: any Unicode digit is a digit

```diff
-         (for-all (lambda (c) (and (char>=? c #\0) (char<=? c #\9))) (string->list s))
+         (for-all char-numeric? (string->list s))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: chez "١0.9.1" is not three dot-separated naturals
  expected: (returned ("f.sexp: chez: the version \"١0.9.1\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: libcurl "١0.9.1" is not three dot-separated naturals
  expected: (returned ("f.sexp: libcurl: the version \"١0.9.1\" is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F14. floors: a version that is no string is not named

```diff
+            ((not (string? version)) '())
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: chez 10 is no string
  expected: (returned ("f.sexp: chez: the version 10 is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: node 10 is no string
  expected: (returned ("f.sexp: node: the version 10 is not dot-separated naturals"))
  actual:   (returned ())
FAIL floors file: chez 10.9 is no string
  expected: (returned ("f.sexp: chez: the version 10.9 is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: node 10.9 is no string
  expected: (returned ("f.sexp: node: the version 10.9 is not dot-separated naturals"))
  actual:   (returned ())
FAIL floors file: chez ten is no string
  expected: (returned ("f.sexp: chez: the version ten is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ())
FAIL floors file: node ten is no string
[21 more lines; the whole output is kept]
```

### F15. floors: Node's version must have three numbers

```diff
-      (node #f "dot-separated naturals")))
+      (node 3 "dot-separated naturals")))
```

**Result:** killed, exit 1:

```
check-floors: packaging/floors.sexp: node: the version "20" is not dot-separated naturals
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL floors file: the base text is legal
  expected: (returned ())
  actual:   (returned ("f.sexp: node: the version \"22.3\" is not dot-separated naturals"))
FAIL floors file: a comment above, between, after and inside the datum is no datum
  expected: (returned ())
  actual:   (returned ("f.sexp: node: the version \"22.3\" is not dot-separated naturals"))
FAIL floors file: zero is a natural, and so is a number of several digits
  expected: (returned ())
  actual:   (returned ("f.sexp: node: the version \"0\" is not dot-separated naturals"))
FAIL floors file: Node may be one number, or several
  expected: (returned ())
  actual:   (returned ("f.sexp: node: the version \"22\" is not dot-separated naturals"))
FAIL floors file: an entry with a key and no version
  expected: (returned ("f.sexp: (libcurl) is not an entry (key \"version\")" "f.sexp: the key libcurl is missing"))
  actual:   (returned ("f.sexp: (libcurl) is not an entry (key \"version\")" "f.sexp: the key libcurl is missing" "f.sexp: node: the version \"22.3\" is not dot-separated naturals"))
[444 more lines; the whole output is kept]
```

### F16. floors: a long datum is not cut in a message

```diff
-      (if (> (string-length text) 60)
-          (string-append (substring text 0 57) "...")
-          text)))
+      text))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: a version longer than the message shows is cut
  expected: (returned ("f.sexp: chez: the version \"11111111111111111111111111111111111111111111111111111111... is not three dot-separated naturals, major.minor.patch"))
  actual:   (returned ("f.sexp: chez: the version \"1111111111111111111111111111111111111111111111111111111111111111111111\" is not three dot-separated naturals, major.minor.patch"))
test: FAIL tests/test-check-floors.sps (exit 1)
```

### F17. floors: write without print-graph, on a cyclic datum

```diff
-      (lambda (p) (parameterize ((print-graph #t)) (write datum p)))))
+      (lambda (p) (write datum p))))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors file: the datum is a cyclic list, which is named and never walked
  expected: (returned ("f.sexp: the datum is #0=(a . #0#), not a list of (key \"version\") entries"))
  actual:   (raised "Warning in write: cycle detected; proceeding with (print-graph #t)")
test: FAIL tests/test-check-floors.sps (exit 1)
```

**`(floors)`: the README's rules (R)**

### R1. floors: a README with no Requirements section is not named

```diff
-        ((null? found)
-         (list (string-append rpath ": it has no " (written section-heading) " section")))
+
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: an empty README
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (raised "Exception in cdr: () is not a pair")
FAIL README: the right lines and no heading
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (raised "Exception in cdr: () is not a pair")
FAIL README: the right lines under another heading
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (raised "Exception in cdr: () is not a pair")
FAIL README: a heading of one star
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (raised "Exception in cdr: () is not a pair")
FAIL README: a heading of three stars
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (raised "Exception in cdr: () is not a pair")
FAIL README: a heading with a tag
[12 more lines; the whole output is kept]
```

### R2. floors: a second Requirements section is not named

```diff
-        ((pair? (cdr found))
-         (list (string-append rpath ": it has " (number->string (length found)) " "
-                              (written section-heading) " sections, but must have one")))
+
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: two sections
  expected: (returned ("R.org: it has 2 \"** Requirements\" sections, but must have one"))
  actual:   (returned ())
FAIL README: three sections
  expected: (returned ("R.org: it has 3 \"** Requirements\" sections, but must have one"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R3a. floors: a "+ " line is no list line

```diff
-          (prefix? "+ " rest)
+
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: a line with a plus for its bullet
  expected: (returned ("R.org: list line 1 under \"** Requirements\" is \"+ Chez Scheme 10.9.1 or later, built with threads\", but f.sexp gives \"- Chez Scheme 10.9.1 or later, built with threads\""))
  actual:   (returned ("R.org: \"** Requirements\" lacks the list line \"- Chez Scheme 10.9.1 or later, built with threads\", which f.sexp gives"))
FAIL README: an extra line with a plus bullet
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"+ Python 3 or later\", which f.sexp does not give"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R3b. floors: a numbered line is no list line

```diff
-          (numbered? rest)
+
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: an extra numbered line
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"1. numbered\", which f.sexp does not give"))
  actual:   (returned ())
FAIL README: an extra numbered line with a parenthesis
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"12) numbered\", which f.sexp does not give"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R3c. floors: an indented "* " line is no list line

```diff
-          (and (> start 0) (prefix? "* " rest)))))
+          #f)))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: an extra line with an indented star
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"  * starred\", which f.sexp does not give"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R3d. floors: an indented line is no list line

```diff
-           (rest (substring line start n)))
+           (rest line))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: a line indented
  expected: (returned ("R.org: list line 3 under \"** Requirements\" is \"  - Node.js 22.3 or later, for the tests\", but f.sexp gives \"- Node.js 22.3 or later, for the tests\""))
  actual:   (returned ("R.org: \"** Requirements\" lacks the list line \"- Node.js 22.3 or later, for the tests\", which f.sexp gives"))
FAIL README: an extra line nested under an item
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"  - nested\", which f.sexp does not give"))
  actual:   (returned ())
FAIL README: an extra line with an indented star
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"  * starred\", which f.sexp does not give"))
  actual:   (returned ())
FAIL README: an extra line indented with a tab
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"\\t- tabbed\", which f.sexp does not give"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R3e. floors: "12) " is no numbered line

```diff
-                       (memv (string-ref line i) '(#\. #\)))
+                       (memv (string-ref line i) '(#\.))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: an extra numbered line with a parenthesis
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"12) numbered\", which f.sexp does not give"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R3f. floors: a tab is no indent

```diff
-                    (if (and (< i n) (memv (string-ref line i) '(#\space #\tab)))
+                    (if (and (< i n) (memv (string-ref line i) '(#\space)))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: an extra line indented with a tab
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"\\t- tabbed\", which f.sexp does not give"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R4. floors: only a heading of two stars ends the section

```diff
-              ((heading? (car rest)) (loop (cdr rest) #f '() closed))
+              ((prefix? "** " (car rest)) (loop (cdr rest) #f '() closed))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: a deeper heading ends the section
  expected: (returned ())
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- an extra item\", which f.sexp does not give"))
FAIL README: a heading of one star ends the section
  expected: (returned ())
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- an extra item\", which f.sexp does not give"))
FAIL legal: floors no real floor equals, a README with their lines among other lists and sections
  expected: (0 "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
  actual:   (1 "" "check-floors: tests/fixtures/floors/legal/README.org: \"** Requirements\" has an extra list line, \"- A list under a deeper heading is not the section's list.\", which tests/fixtures/floors/legal/floors.sexp does not give [+40 chars]
FAIL the legal fixture's files pass the pure procedure
  expected: (returned ())
  actual:   (returned ("r: \"** Requirements\" has an extra list line, \"- A list under a deeper heading is not the section's list.\", which f does not give"))
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R4b. floors: no heading ends the section

```diff
-              ((heading? (car rest)) (loop (cdr rest) #f '() closed))
+
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: lists under other headings are not compared
  expected: (returned ())
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- Node.js 1 or later, for the tests\", which f.sexp does not give"))
FAIL README: a deeper heading ends the section
  expected: (returned ())
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- an extra item\", which f.sexp does not give"))
FAIL README: a heading of one star ends the section
  expected: (returned ())
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- an extra item\", which f.sexp does not give"))
FAIL legal: floors no real floor equals, a README with their lines among other lists and sections
  expected: (0 "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
  actual:   (1 "" "check-floors: tests/fixtures/floors/legal/README.org: \"** Requirements\" has an extra list line, \"- A list under a deeper heading is not the section's list.\", which tests/fixtures/floors/legal/floors.sexp does not give [+240 chars]
FAIL the legal fixture's files pass the pure procedure
  expected: (returned ())
  actual:   (returned ("r: \"** Requirements\" has an extra list line, \"- A list under a deeper heading is not the section's list.\", which f does not give" "r: \"** Requirements\" has an extra list line, \"- Node.js 1 or later, for the te [+31 chars]
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R4c. floors: a line that starts with a star is a heading, a space or not

```diff
-            (else (and (> i 0) (char=? (string-ref line i) #\space))))))
+            (else (> i 0)))))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: prose, blank lines and lines that are no bullets between the items
  expected: (returned ())
  actual:   (returned ("R.org: \"** Requirements\" lacks the list line \"- Node.js 22.3 or later, for the tests\", which f.sexp gives"))
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R4d. floors: a section the file ends in is lost

```diff
-        (cond ((null? rest) (reverse closed))
+        (cond ((null? rest) (reverse found))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: the three lines the floors give, in order
  expected: (returned ())
  actual:   (returned ("R.org: it has no \"** Requirements\" section"))
FAIL README: the section last in the file, with no newline after its last line
  expected: (returned ())
  actual:   (returned ("R.org: it has no \"** Requirements\" section"))
FAIL README: prose, blank lines and lines that are no bullets between the items
  expected: (returned ())
  actual:   (returned ("R.org: it has no \"** Requirements\" section"))
FAIL README: two sections
  expected: (returned ("R.org: it has 2 \"** Requirements\" sections, but must have one"))
  actual:   (returned ())
FAIL README: three sections
  expected: (returned ("R.org: it has 3 \"** Requirements\" sections, but must have one"))
  actual:   (returned ("R.org: it has 2 \"** Requirements\" sections, but must have one"))
FAIL README: the Chez line says an older Chez
[90 more lines; the whole output is kept]
```

### R5. floors: a changed line is reported as one extra and one missing

```diff
-      ((= (length found) (length expected))
+      (#f
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: the Chez line says an older Chez
  expected: (returned ("R.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but f.sexp gives \"- Chez Scheme 10.9.1 or later, built with threads\""))
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- Chez Scheme 10.8.0 or later, built with threads\", which f.sexp does not give" "R.org: \"** Requirements\" lacks the list line \"- Chez Scheme 10.9.1 or later, b [+42 chars]
FAIL README: the libcurl line says SSL, not TLS
  expected: (returned ("R.org: list line 2 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with SSL\", but f.sexp gives \"- libcurl 8.1.2 or later, built with TLS\""))
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- libcurl 8.1.2 or later, built with SSL\", which f.sexp does not give" "R.org: \"** Requirements\" lacks the list line \"- libcurl 8.1.2 or later, built with TLS\ [+24 chars]
FAIL README: the Node line says another Node
  expected: (returned ("R.org: list line 3 under \"** Requirements\" is \"- Node.js 22.4 or later, for the tests\", but f.sexp gives \"- Node.js 22.3 or later, for the tests\""))
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- Node.js 22.4 or later, for the tests\", which f.sexp does not give" "R.org: \"** Requirements\" lacks the list line \"- Node.js 22.3 or later, for the tests\", w [+20 chars]
FAIL README: a line with a space at its end
  expected: (returned ("R.org: list line 2 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with TLS \", but f.sexp gives \"- libcurl 8.1.2 or later, built with TLS\""))
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- libcurl 8.1.2 or later, built with TLS \", which f.sexp does not give" "R.org: \"** Requirements\" lacks the list line \"- libcurl 8.1.2 or later, built with TLS [+25 chars]
FAIL README: a line with two spaces inside it
  expected: (returned ("R.org: list line 2 under \"** Requirements\" is \"- libcurl 8.1.2 or later,  built with TLS\", but f.sexp gives \"- libcurl 8.1.2 or later, built with TLS\""))
  actual:   (returned ("R.org: \"** Requirements\" has an extra list line, \"- libcurl 8.1.2 or later,  built with TLS\", which f.sexp does not give" "R.org: \"** Requirements\" lacks the list line \"- libcurl 8.1.2 or later, built with TLS [+25 chars]
FAIL README: a line indented
[24 more lines; the whole output is kept]
```

### R5b. floors: an extra line is not named

```diff
-        (map (lambda (line)
-               (string-append rpath ": " (written section-heading)
-                              " has an extra list line, " (written line)
-                              ", which " fpath " does not give"))
-             (multiset-minus found expected))
+        '()
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: an extra line at the end
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"- Python 3 or later\", which f.sexp does not give"))
  actual:   (returned ())
FAIL README: an extra line at the start
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"- Python 3 or later\", which f.sexp does not give"))
  actual:   (returned ())
FAIL README: an extra line in the middle
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"- Python 3 or later\", which f.sexp does not give"))
  actual:   (returned ())
FAIL README: an extra line with a plus bullet
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"+ Python 3 or later\", which f.sexp does not give"))
  actual:   (returned ())
FAIL README: an extra line nested under an item
  expected: (returned ("R.org: \"** Requirements\" has an extra list line, \"  - nested\", which f.sexp does not give"))
  actual:   (returned ())
FAIL README: an extra numbered line
[18 more lines; the whole output is kept]
```

### R5c. floors: a missing line is not named

```diff
-        (map (lambda (line)
-               (string-append rpath ": " (written section-heading)
-                              " lacks the list line " (written line)
-                              ", which " fpath " gives"))
-             (multiset-minus expected found))))))
+        '()))))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: the Chez line missing
  expected: (returned ("R.org: \"** Requirements\" lacks the list line \"- Chez Scheme 10.9.1 or later, built with threads\", which f.sexp gives"))
  actual:   (returned ())
FAIL README: the libcurl line missing
  expected: (returned ("R.org: \"** Requirements\" lacks the list line \"- libcurl 8.1.2 or later, built with TLS\", which f.sexp gives"))
  actual:   (returned ())
FAIL README: the Node line missing
  expected: (returned ("R.org: \"** Requirements\" lacks the list line \"- Node.js 22.3 or later, for the tests\", which f.sexp gives"))
  actual:   (returned ())
FAIL README: the heading and nothing under it
  expected: (returned ("R.org: \"** Requirements\" lacks the list line \"- Chez Scheme 10.9.1 or later, built with threads\", which f.sexp gives" "R.org: \"** Requirements\" lacks the list line \"- libcurl 8.1.2 or later, built with TLS\",  [+133 chars]
  actual:   (returned ())
FAIL README: the heading and prose under it
  expected: (returned ("R.org: \"** Requirements\" lacks the list line \"- Chez Scheme 10.9.1 or later, built with threads\", which f.sexp gives" "R.org: \"** Requirements\" lacks the list line \"- libcurl 8.1.2 or later, built with TLS\",  [+133 chars]
  actual:   (returned ())
FAIL README: one line altered and one added
[3 more lines; the whole output is kept]
```

### R6. floors: the order of the README's lines is not checked

```diff
-      ((equal? found expected) '())
+      ((equal? (list-sort string<? found) (list-sort string<? expected)) '())
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: the first two lines swapped
  expected: (returned ("R.org: list line 1 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with TLS\", but f.sexp gives \"- Chez Scheme 10.9.1 or later, built with threads\"" "R.org: list line 2 under \"** Requirements\" is \ [+118 chars]
  actual:   (returned ())
FAIL README: the last two lines swapped
  expected: (returned ("R.org: list line 2 under \"** Requirements\" is \"- Node.js 22.3 or later, for the tests\", but f.sexp gives \"- libcurl 8.1.2 or later, built with TLS\"" "R.org: list line 3 under \"** Requirements\" is \"- libcurl  [+96 chars]
  actual:   (returned ())
FAIL README: the three lines rotated
  expected: (returned ("R.org: list line 1 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with TLS\", but f.sexp gives \"- Chez Scheme 10.9.1 or later, built with threads\"" "R.org: list line 2 under \"** Requirements\" is \ [+118 chars]
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R7. floors: a space at the end of a README line is ignored

```diff
-    (let ((found (sections (split rtext #\newline))))
+    (let ((found (sections (map (lambda (l) (let trim ((n (string-length l))) (if (and (> n 0) (char=? (string-ref l (- n 1)) #\space)) (trim (- n 1)) (substring l 0 n)))) (split rtext #\newline)))))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: a line with a space at its end
  expected: (returned ("R.org: list line 2 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with TLS \", but f.sexp gives \"- libcurl 8.1.2 or later, built with TLS\""))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R8. floors: the Chez line is written from a constant, not the file

```diff
-    (list (string-append "- Chez Scheme " (floor-text floors 'chez)
+    (list (string-append "- Chez Scheme " "10.4.0"
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: the three lines the floors give, in order
  expected: (returned ())
  actual:   (returned ("R.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.9.1 or later, built with threads\", but f.sexp gives \"- Chez Scheme 10.4.0 or later, built with threads\""))
FAIL README: the section last in the file, with no newline after its last line
  expected: (returned ())
  actual:   (returned ("R.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.9.1 or later, built with threads\", but f.sexp gives \"- Chez Scheme 10.4.0 or later, built with threads\""))
FAIL README: prose, blank lines and lines that are no bullets between the items
  expected: (returned ())
  actual:   (returned ("R.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.9.1 or later, built with threads\", but f.sexp gives \"- Chez Scheme 10.4.0 or later, built with threads\""))
FAIL README: lists under other headings are not compared
  expected: (returned ())
  actual:   (returned ("R.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.9.1 or later, built with threads\", but f.sexp gives \"- Chez Scheme 10.4.0 or later, built with threads\""))
FAIL README: a deeper heading ends the section
  expected: (returned ())
  actual:   (returned ("R.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.9.1 or later, built with threads\", but f.sexp gives \"- Chez Scheme 10.4.0 or later, built with threads\""))
FAIL README: a heading of one star ends the section
[105 more lines; the whole output is kept]
```

### R9. floors: the README is never compared

```diff
-          (readme-problems rpath rtext fpath (car (cadr (read-data ftext))))
+          '()
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: an empty README
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ())
FAIL README: the right lines and no heading
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ())
FAIL README: the right lines under another heading
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ())
FAIL README: a heading of one star
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ())
FAIL README: a heading of three stars
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ())
FAIL README: a heading with a tag
[105 more lines; the whole output is kept]
```

### R10. floors: a heading that starts with Requirements opens the section

```diff
-              ((string=? (car rest) section-heading) (loop (cdr rest) #t '() closed))
+              ((prefix? section-heading (car rest)) (loop (cdr rest) #t '() closed))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: a heading with a tag
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R10b. floors: the section heading is matched without regard to case

```diff
-              ((string=? (car rest) section-heading) (loop (cdr rest) #t '() closed))
+              ((string-ci=? (car rest) section-heading) (loop (cdr rest) #t '() closed))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: a heading in lower case
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### R10c. floors: a Requirements heading of any level opens the section

```diff
-              ((string=? (car rest) section-heading) (loop (cdr rest) #t '() closed))
+              ((let ((l (car rest))) (and (>= (string-length l) 13) (string=? (substring l (- (string-length l) 13) (string-length l)) " Requirements"))) (loop (cdr rest) #t '() closed))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL README: a heading of one star
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ())
FAIL README: a heading of three stars
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

**`(floors)`: the answers a suite reads (A)**

### A1. floors: floor-numbers drops the last number

```diff
-          (map string->number (split (cadr entry) #\.))
+          (map string->number (let ((p (split (cadr entry) #\.))) (if (null? (cdr p)) p (reverse (cdr (reverse p))))))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floor-numbers: chez
  expected: (returned (10 9 1))
  actual:   (returned (10 9))
FAIL floor-numbers: libcurl
  expected: (returned (8 1 2))
  actual:   (returned (8 1))
FAIL floor-numbers: node
  expected: (returned (22 3))
  actual:   (returned (22))
FAIL floor-numbers: zeros and several digits stay as they are
  expected: (returned ((0 0 0) (10 0 10) (0)))
  actual:   (returned ((0 0) (10 0) (0)))
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL the floor is the libcurl floor of packaging/floors.sexp, as a version_num
  expected: not-a-version-num
  actual:   480512
[35 more lines; the whole output is kept]
```

### A2. floors: requirement-lines says SSL for TLS

```diff
-                         " or later, built with TLS")
+                         " or later, built with SSL")
```

**Result:** killed, exit 1:

```
check-floors: README.org: list line 2 under "** Requirements" is "- libcurl 7.85.0 or later, built with TLS", but packaging/floors.sexp gives "- libcurl 7.85.0 or later, built with SSL"
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
FAIL README: the three lines the floors give, in order
  expected: (returned ())
  actual:   (returned ("R.org: list line 2 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with TLS\", but f.sexp gives \"- libcurl 8.1.2 or later, built with SSL\""))
FAIL README: the section last in the file, with no newline after its last line
  expected: (returned ())
  actual:   (returned ("R.org: list line 2 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with TLS\", but f.sexp gives \"- libcurl 8.1.2 or later, built with SSL\""))
FAIL README: prose, blank lines and lines that are no bullets between the items
  expected: (returned ())
  actual:   (returned ("R.org: list line 2 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with TLS\", but f.sexp gives \"- libcurl 8.1.2 or later, built with SSL\""))
FAIL README: lists under other headings are not compared
  expected: (returned ())
  actual:   (returned ("R.org: list line 2 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with TLS\", but f.sexp gives \"- libcurl 8.1.2 or later, built with SSL\""))
FAIL README: a deeper heading ends the section
  expected: (returned ())
  actual:   (returned ("R.org: list line 2 under \"** Requirements\" is \"- libcurl 8.1.2 or later, built with TLS\", but f.sexp gives \"- libcurl 8.1.2 or later, built with SSL\""))
[106 more lines; the whole output is kept]
```

### A3. floors: parse-floors answers () for a bad file, and does not raise

```diff
-          (assertion-violation 'parse-floors (joined "; " problems)))))
+          '())))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL parse-floors refuses a file with a problem, naming it
  expected: (raised "Exception in parse-floors: packaging/floors.sexp: the key node is missing")
  actual:   (returned ())
FAIL parse-floors refuses a file with two problems, naming both
  expected: (raised "Exception in parse-floors: packaging/floors.sexp: the key node is missing; packaging/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
```

### A3b. floors: parse-floors joins its problems with a comma

```diff
-          (assertion-violation 'parse-floors (joined "; " problems)))))
+          (assertion-violation 'parse-floors (joined ", " problems)))))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL parse-floors refuses a file with two problems, naming both
  expected: (raised "Exception in parse-floors: packaging/floors.sexp: the key node is missing; packaging/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
  actual:   (raised "Exception in parse-floors: packaging/floors.sexp: the key node is missing, packaging/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
test: FAIL tests/test-check-floors.sps (exit 1)
```

### A4. floors: floor-text answers #f for a name that is no floor

```diff
-          (assertion-violation 'floor-text "no such floor" name))))
+          #f)))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floor-text: a name that is no floor is refused, by name
  expected: (raised "Exception in floor-text: no such floor with irritant python")
  actual:   (returned #f)
test: FAIL tests/test-check-floors.sps (exit 1)
```

### A5. floors: floors-path names a file that is not there

```diff
-  (define floors-path "packaging/floors.sexp")
+  (define floors-path "packaging/floor.sexp")
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL parse-floors refuses a file with a problem, naming it
  expected: (raised "Exception in parse-floors: packaging/floors.sexp: the key node is missing")
  actual:   (raised "Exception in parse-floors: packaging/floor.sexp: the key node is missing")
FAIL parse-floors refuses a file with two problems, naming both
  expected: (raised "Exception in parse-floors: packaging/floors.sexp: the key node is missing; packaging/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
  actual:   (raised "Exception in parse-floors: packaging/floor.sexp: the key node is missing; packaging/floor.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.minor.patch")
FAIL floors-path names the checked-in file
  expected: "packaging/floors.sexp"
  actual:   "packaging/floor.sexp"
FAIL the checked-in floors file is legal
  expected: (returned ())
  actual:   (raised "Exception in open-file-input-port: failed for packaging/floor.sexp: no such file or directory")
FAIL read-floors answers the checked-in file's three floors, in order
  expected: (returned (chez libcurl node))
  actual:   (raised "Exception in open-file-input-port: failed for packaging/floor.sexp: no such file or directory")
test: FAIL tests/test-check-floors.sps (exit 1)
[59 more lines; the whole output is kept]
```

**`tests/check-floors.sps` (P)**

### P1. program: the argument count is not checked

```diff
-  (if (not (= (length args) 2))
+  (if #f
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL no arguments: the usage line, exit 1
  expected: (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README\n")
  actual:   (255 "" "Exception in car: () is not a pair\n")
FAIL one argument: the usage line, exit 1
  expected: (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README\n")
  actual:   (255 "" "Exception in cadr: incorrect list structure (\"tests/fixtures/floors/legal/floors.sexp\")\n")
FAIL three arguments: the usage line, exit 1
  expected: (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README\n")
  actual:   (0 "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
test: FAIL tests/test-check-floors.sps (exit 1)
```

### P2. program: a file it cannot read reads as empty

```diff
-  (guard (e (#t (list 'unreadable
-                      (string-append path ": it cannot be read: " (describe e)))))
+  (guard (e (#t (list 'text "")))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL no-readme: a floors file and no README beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or directory\ncheck-floors: FAILED (probl [+11 chars]
  actual:   (1 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it has no \"** Requirements\" section\ncheck-floors: FAILED (problems: 1)\n")
FAIL no-floors: a README and no floors file beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\ncheck-floors: FAILED (pro [+13 chars]
  actual:   (1 "" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it holds no datum, but must hold exactly one\ncheck-floors: FAILED (problems: 1)\n")
FAIL neither file exists: both named, the floors first
  expected: (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: tests/fixtures/floors/l [+183 chars]
  actual:   (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it holds no datum, but must hold exactly one\ncheck-floors: FAILED (problems: 1)\n")
FAIL a bad floors file and no README: the floors problems, then the README
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+253 chars]
  actual:   (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
test: FAIL tests/test-check-floors.sps (exit 1)
```

### P3. program: the problem count is always 1

```diff
-                (string-append "FAILED (problems: " (number->string (length found)) ")"))
+                (string-append "FAILED (problems: " "1" ")"))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL floors-invalid: a floors file with a missing key and a bad version: both named, and the README not read
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
  actual:   (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
FAIL neither file exists: both named, the floors first
  expected: (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: tests/fixtures/floors/l [+183 chars]
  actual:   (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: tests/fixtures/floors/l [+183 chars]
FAIL a bad floors file and no README: the floors problems, then the README
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
  actual:   (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
test: FAIL tests/test-check-floors.sps (exit 1)
```

### P4. program: the ok line does not name the floors

```diff
-                               (summary (file-text fpath)) ")"))
+                               "x" ")"))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (x)
status: make check-floors exit=0
FAIL legal: floors no real floor equals, a README with their lines among other lists and sections
  expected: (0 "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
  actual:   (0 "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (x)\n" "")
test: FAIL tests/test-check-floors.sps (exit 1)
```

### P5. program: every (exit 1) is (exit 0), so it always exits 0 (MK2)

```diff
-        (exit 1))
+        (exit 0))
-           (exit 1))))))
+           (exit 0))))))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL readme-altered: one README line altered
  expected: (1 "" "check-floors: tests/fixtures/floors/readme-altered/README.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but tests/fixtures/floors/readme-altered/floors.sexp gives \"- [+90 chars]
  actual:   (0 "" "check-floors: tests/fixtures/floors/readme-altered/README.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but tests/fixtures/floors/readme-altered/floors.sexp gives \"- [+90 chars]
FAIL no-section: the right lines under another heading
  expected: (1 "" "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (0 "" "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\ncheck-floors: FAILED (problems: 1)\n")
FAIL floors-invalid: a floors file with a missing key and a bad version: both named, and the README not read
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
  actual:   (0 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
FAIL no-readme: a floors file and no README beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or directory\ncheck-floors: FAILED (probl [+11 chars]
  actual:   (0 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or directory\ncheck-floors: FAILED (probl [+11 chars]
FAIL no-floors: a README and no floors file beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\ncheck-floors: FAILED (pro [+13 chars]
  actual:   (0 "" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\ncheck-floors: FAILED (pro [+13 chars]
FAIL neither file exists: both named, the floors first
[26 more lines; the whole output is kept]
```

### P6. program: the FAILED line goes to stdout

```diff
-           (say (current-error-port)
+           (say (current-output-port)
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL readme-altered: one README line altered
  expected: (1 "" "check-floors: tests/fixtures/floors/readme-altered/README.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but tests/fixtures/floors/readme-altered/floors.sexp gives \"- [+90 chars]
  actual:   (1 "check-floors: FAILED (problems: 1)\n" "check-floors: tests/fixtures/floors/readme-altered/README.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but tests/fixtures/floors/ [+90 chars]
FAIL no-section: the right lines under another heading
  expected: (1 "" "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (1 "check-floors: FAILED (problems: 1)\n" "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\n")
FAIL floors-invalid: a floors file with a missing key and a bad version: both named, and the README not read
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
  actual:   (1 "check-floors: FAILED (problems: 2)\n" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is no [+53 chars]
FAIL no-readme: a floors file and no README beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or directory\ncheck-floors: FAILED (probl [+11 chars]
  actual:   (1 "check-floors: FAILED (problems: 1)\n" "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or di [+11 chars]
FAIL no-floors: a README and no floors file beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\ncheck-floors: FAILED (pro [+13 chars]
  actual:   (1 "check-floors: FAILED (problems: 1)\n" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or  [+13 chars]
FAIL neither file exists: both named, the floors first
[6 more lines; the whole output is kept]
```

### P6b. program: the problems go to stdout

```diff
-           (for-each (lambda (p) (say (current-error-port) p)) found)
+           (for-each (lambda (p) (say (current-output-port) p)) found)
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL readme-altered: one README line altered
  expected: (1 "" "check-floors: tests/fixtures/floors/readme-altered/README.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but tests/fixtures/floors/readme-altered/floors.sexp gives \"- [+90 chars]
  actual:   (1 "check-floors: tests/fixtures/floors/readme-altered/README.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but tests/fixtures/floors/readme-altered/floors.sexp gives \"- Ch [+90 chars]
FAIL no-section: the right lines under another heading
  expected: (1 "" "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (1 "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\n" "check-floors: FAILED (problems: 1)\n")
FAIL floors-invalid: a floors file with a missing key and a bad version: both named, and the README not read
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
  actual:   (1 "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, major.m [+53 chars]
FAIL no-readme: a floors file and no README beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or directory\ncheck-floors: FAILED (probl [+11 chars]
  actual:   (1 "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or directory\n" "check-floors: FAILED (probl [+11 chars]
FAIL no-floors: a README and no floors file beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\ncheck-floors: FAILED (pro [+13 chars]
  actual:   (1 "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\n" "check-floors: FAILED (pro [+13 chars]
FAIL neither file exists: both named, the floors first
[6 more lines; the whole output is kept]
```

### P7. program: an unreadable README is named before the floors file's problems

```diff
-        (append (if (eq? (car f) 'text)
-                    (floors-problems fpath (cadr f))
-                    (list (cadr f)))
-                (if (eq? (car r) 'text)
+        (append (if (eq? (car r) 'text)
-                    (list (cadr r)))))))
+                    (list (cadr r)))
+                (if (eq? (car f) 'text)
+                    (floors-problems fpath (cadr f))
+                    (list (cadr f))))))))
```

**Result:** killed, exit 1:

```
status: make check-floors exit=2
FAIL legal: floors no real floor equals, a README with their lines among other lists and sections
  expected: (0 "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
  actual:   (255 "" "Exception in read: unexpected close parenthesis at line 52, char 41 of tests/check-floors.sps\n")
FAIL readme-altered: one README line altered
  expected: (1 "" "check-floors: tests/fixtures/floors/readme-altered/README.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.8.0 or later, built with threads\", but tests/fixtures/floors/readme-altered/floors.sexp gives \"- [+90 chars]
  actual:   (255 "" "Exception in read: unexpected close parenthesis at line 52, char 41 of tests/check-floors.sps\n")
FAIL no-section: the right lines under another heading
  expected: (1 "" "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (255 "" "Exception in read: unexpected close parenthesis at line 52, char 41 of tests/check-floors.sps\n")
FAIL floors-invalid: a floors file with a missing key and a bad version: both named, and the README not read
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
  actual:   (255 "" "Exception in read: unexpected close parenthesis at line 52, char 41 of tests/check-floors.sps\n")
FAIL no-readme: a floors file and no README beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or directory\ncheck-floors: FAILED (probl [+11 chars]
  actual:   (255 "" "Exception in read: unexpected close parenthesis at line 52, char 41 of tests/check-floors.sps\n")
FAIL no-floors: a README and no floors file beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\ncheck-floors: FAILED (pro [+13 chars]
[17 more lines; the whole output is kept]
```

### P8. program: an unreadable README is not named when the floors file is bad or unreadable

```diff
-                (if (eq? (car r) 'text)
-                    '()
-                    (list (cadr r)))))))
+                '()))))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL no-readme: a floors file and no README beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or directory\ncheck-floors: FAILED (probl [+11 chars]
  actual:   (0 "check-floors: tests/fixtures/floors/no-readme/README.org states the floors in tests/fixtures/floors/no-readme/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
FAIL neither file exists: both named, the floors first
  expected: (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: tests/fixtures/floors/l [+183 chars]
  actual:   (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: FAILED (problems: 1)\n" [+1 chars]
FAIL a bad floors file and no README: the floors problems, then the README
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+253 chars]
  actual:   (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [+53 chars]
test: FAIL tests/test-check-floors.sps (exit 1)
```

### P9. program: the ok line goes to stderr

```diff
-           (say (current-output-port)
+           (say (current-error-port)
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL legal: floors no real floor equals, a README with their lines among other lists and sections
  expected: (0 "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
  actual:   (0 "" "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n")
test: FAIL tests/test-check-floors.sps (exit 1)
```

### P10. program: it exits 1 on a pass

```diff
-           (exit 0))
+           (exit 1))
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=2
FAIL legal: floors no real floor equals, a README with their lines among other lists and sections
  expected: (0 "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
  actual:   (1 "check-floors: tests/fixtures/floors/legal/README.org states the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
test: FAIL tests/test-check-floors.sps (exit 1)
```

**The Makefile and `check-test-fails` (MK)**

### MK1. Makefile: check-floors dropped from test's prerequisites

```diff
-test: deps check-help check-suites check-seam check-floors ## Run every tests/test-*.sps under timeout; fail if one fails or hangs, or none exists
+test: deps check-help check-suites check-seam ## Run every tests/test-*.sps under timeout; fail if one fails or hangs, or none exists
```

**Result:** killed, exit 2:

```
check-test-fails: FAILED floors: check-floors names a README that states another Chez floor, and no suite runs: make test exited 0
check-test-fails: FAILED floors: check-floors names a README that states another Chez floor, and no suite runs: make test's lines differ
  wanted: check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
  wanted: check-floors: README.org: list line 1 under "** Requirements" is "- Chez Scheme 10.3.0 or later, built with threads", but packaging/floors.sexp gives "- Chez Scheme 10.4.0 or later, built with threads"
  wanted: check-floors: FAILED (problems: 1)
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
  got:    test: pass tests/test-1-after.sps
  got:    test: ran 1, passed 1, failed 0, hung 0
```

### MK3. Makefile: check-floors dropped from .PHONY

```diff
-.PHONY: help check-help check-guix check-guix-inside deps check-pins build test check-suites check-seam check-floors check-test-fails
+.PHONY: help check-help check-guix check-guix-inside deps check-pins build test check-suites check-seam check-test-fails
```

**Result:** killed, exit 2:

```
check-help: make help lists 'check-floors', which is not in .PHONY
```

### MK4. Makefile: check-floors loses its help line

```diff
-check-floors: ## Fail unless README.org states the floors in packaging/floors.sexp
+check-floors:
```

**Result:** killed, exit 2:

```
check-help: make help does not list .PHONY target 'check-floors'; give it a '## ' description on its target line
```

### MK5. check-test-fails.sh: the plant's sed no longer matches the README line

```diff
-sed 's/^- Chez Scheme .* or later, built with threads$/- Chez Scheme 10.3.0 or later, built with threads/' \
+sed 's/^- Chez Scheme .* or later, built with thread$/- Chez Scheme 10.3.0 or later, built with threads/' \
```

**Result:** killed, exit 2:

```
check-test-fails: FAILED floors: the plant did not change README.org, so it plants nothing
check-test-fails: FAILED floors: check-floors names a README that states another Chez floor, and no suite runs: make test exited 0
check-test-fails: FAILED floors: check-floors names a README that states another Chez floor, and no suite runs: make test's lines differ
  wanted: check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
  wanted: check-floors: README.org: list line 1 under "** Requirements" is "- Chez Scheme 10.3.0 or later, built with threads", but packaging/floors.sexp gives "- Chez Scheme 10.4.0 or later, built with threads"
  wanted: check-floors: FAILED (problems: 1)
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
  got:    check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
  got:    test: pass tests/test-1-after.sps
  got:    test: ran 1, passed 1, failed 0, hung 0
```

### MK6. check-test-fails.sh: the README is not restored after the floors case

```diff
-cp "$root/README.org" "$copy/README.org"
+
```

**Result:** killed, exit 2:

```
check-test-fails: FAILED no-suites: make test refuses to pass with no suite to run: make test's lines differ
  wanted: check-suites: every suite ends with (exit (suite-exit-status runner)) (0 checked)
  wanted: test: no suites: nothing matches tests/test-*.sps
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (0 checked)
```

### MK7. Makefile: check-floors ignores the program's exit status

```diff
-	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp README.org
+	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp README.org || true
```

**Result:** killed, exit 2:

```
check-test-fails: FAILED floors: check-floors names a README that states another Chez floor, and no suite runs: make test exited 0
check-test-fails: FAILED floors: check-floors names a README that states another Chez floor, and no suite runs: make test's lines differ
  wanted: check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
  wanted: check-floors: README.org: list line 1 under "** Requirements" is "- Chez Scheme 10.3.0 or later, built with threads", but packaging/floors.sexp gives "- Chez Scheme 10.4.0 or later, built with threads"
  wanted: check-floors: FAILED (problems: 1)
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
  got:    check-floors: README.org: list line 1 under "** Requirements" is "- Chez Scheme 10.3.0 or later, built with threads", but packaging/floors.sexp gives "- Chez Scheme 10.4.0 or later, built with threads"
  got:    check-floors: FAILED (problems: 1)
  got:    test: pass tests/test-1-after.sps
  got:    test: ran 1, passed 1, failed 0, hung 0
```

### MK8. Makefile: check-floors reads LICENSE, not README.org

```diff
-	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp README.org
+	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp LICENSE
```

**Result:** killed, exit 1:

```
check-floors: LICENSE: it has no "** Requirements" section
check-floors: FAILED (problems: 1)
status: make check-floors exit=2
check-test-fails: FAILED fails: a failing suite is named FAIL, and the suites after it run: make test's lines differ
  wanted: check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
  wanted: test: FAIL tests/test-0-plant.sps (exit 1)
  wanted: test: pass tests/test-1-after.sps
  wanted: test: ran 2, passed 1, failed 1, hung 0
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
check-test-fails: FAILED no-tests: a suite that runs no test is named FAIL, and the suites after it run: make test's lines differ
  wanted: check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
  wanted: test: FAIL tests/test-0-plant.sps (exit 1)
  wanted: test: pass tests/test-1-after.sps
  wanted: test: ran 2, passed 1, failed 1, hung 0
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
check-test-fails: FAILED hangs: a suite that never ends is named HUNG, and the suites after it run: make test's lines differ
  wanted: check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
  wanted: test: HUNG tests/test-0-plant.sps (no exit within 5s)
[15 more lines; the whole output is kept]
```

### MK9. Makefile: check-floors without --libdirs tests, so (floors) is not found

```diff
-	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp README.org
+	@$(CHEZ) --program tests/check-floors.sps packaging/floors.sexp README.org
```

**Result:** killed, exit 1:

```
status: make check-floors exit=2
```

**The suite's own guards (FX)**

### FX1. a fixture directory, tests/fixtures/floors/stray, that no case runs

```diff
Only in ./tests/fixtures/floors: stray
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL every fixture directory is a case above, and every case has its directory
  expected: ("floors-invalid" "legal" "no-floors" "no-readme" "no-section" "readme-altered")
  actual:   ("floors-invalid" "legal" "no-floors" "no-readme" "no-section" "readme-altered" "stray")
test: FAIL tests/test-check-floors.sps (exit 1)
```

### FX2. a case whose fixture directory, tests/fixtures/floors/no-section, is gone

```diff
Only in <worktree>/tests/fixtures/floors: no-section
```

**Result:** killed, exit 1:

```
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
FAIL no-section: the right lines under another heading
  expected: (1 "" "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (1 "" "check-floors: tests/fixtures/floors/no-section/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-section/floors.sexp: no such file or directory\ncheck-floors: tests/fix [+211 chars]
FAIL every fixture directory is a case above, and every case has its directory
  expected: ("floors-invalid" "legal" "no-floors" "no-readme" "no-section" "readme-altered")
  actual:   ("floors-invalid" "legal" "no-floors" "no-readme" "readme-altered")
test: FAIL tests/test-check-floors.sps (exit 1)
```

### FX3. CHEZ unset: the suite names it and stops

```diff

mutation.sh: the suite is run with CHEZ set to the empty string
```

**Result:** killed, exit 1:

```
FAIL CHEZ names the Chez to spawn
  expected: set
  actual:   unset
status: tests/test-check-floors.sps exit=1
```

### Coverage

Every one of the 177 tests in `tests/test-check-floors.sps` was failed by name by at least one
mutant. Two needed the mutants of their own: `CHEZ names the Chez to spawn`, which only an unset
`CHEZ` fails (FX3), and `every fixture directory is a case above, and every case has its
directory`, which FX1 and FX2 fail. The twelve new rows in the other two suites, four in
`test-verify` and eight in `test-require-threaded`, were each failed by name, and the message
the literal rows expect is now taken from the file.

Notes on single mutations:

- **FL8 and FL11** change a floor the running Chez meets or not. FL8 raises the minimum to
  10.4.1 on a Chez 10.4.0, so `test-verify` dies at import (`exit 255`) as well, with no test
  named; `test-require-threaded` names fifteen. A floor cannot be raised by editing every place
  that holds it on the Chez the suites run, so FL11, the "changed everywhere" case, lowers the
  libcurl floor to 7.84.0 instead: `make check-floors` and `make check-test-fails` stay green
  (nothing but the file, the README and `verify.sls` names the floor), and only the three literal
  rows in `test-verify` that name 7.85.0, or the version just below it, fail.
- **MK9** is killed by `make check-floors`' exit status alone: Chez's own error, `library
  (floors) not found`, is not a line the filter keeps.
- **P5** is the brief's MK2.

### Clean rerun

The tree every mutation above copied, but for the header comment of `tests/floors.sls`, which was
corrected after the mutation runs (no code changed). No mutation, run from the repository:

```
make test               exit 0
  check-suites: every suite ends with (exit (suite-exit-status runner)) (11 checked)
  check-seam: the seam holds (9 libraries in 9 files checked)
  check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
  test: pass tests/test-check-floors.sps          (177 tests)
  test: pass tests/test-check-seam.sps
  test: pass tests/test-conditions.sps
  test: pass tests/test-curl-testing.sps
  test: pass tests/test-discovery.sps
  test: pass tests/test-library-loading.sps
  test: pass tests/test-load-state.sps
  test: pass tests/test-manifest.sps
  test: pass tests/test-native.sps
  test: pass tests/test-require-threaded.sps      (57 tests)
  test: pass tests/test-verify.sps                (22 tests)
  test: ran 11, passed 11, failed 0, hung 0
make check-test-fails   exit 0
  check-test-fails: ok floors: check-floors names a README that states another Chez floor, and no suite runs
  check-test-fails: make test failed, as it must, in all 10 cases
[2 more lines cut]
```

And as a mutation copy ran it, `make check-floors` and `make check-test-fails` in one container:

```
exit=0
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
status: make check-floors exit=0
check-test-fails: make test failed, as it must, in all 10 cases
status: make check-test-fails exit=0
```

## Review fixes: test-constants

Evidence that the fixes to `tests/test-constants.sps` from slice 4's review each fail through
the property they guard ([ADR-0001](decisions/0001-bind-libcurl-directly.md), decisions 3 and
4). Only the suite changed. The review found four holes:

1. **The suite never checked which headers it compiled against.** On CI's floor lane, a
   forgotten `C_INCLUDE_PATH` would check the runner's 8.5.0 headers while the library under
   test is 7.85.0, and pass. The C program now prints `LIBCURL_VERSION_NUM` as its own answer.
   The suite loads the libcurl chez-curl itself loads, in its own process: it `eval`s
   `(libcurl-info-version-number (loaded-libcurl))` in `(environment '(curl))` under a guard. A
   refusal becomes `(refused REASON PATH)`, never a raise. One test requires the headers to be
   no newer than that library. On failure it names both numbers in hex, or what stopped
   either side. Two more tests hold the rule itself on fixed numbers. The real headers and
   library are one version here, so a comparison turned round would pass the real test.
2. **Layouts compared offset and size only,** so `(capath double)` passed for C's `char *`.
   The C program now also prints each member's kind, through C11 `_Generic` on
   `((T *)0)->m`, which it does not evaluate: `integer` for each standard integer type,
   `floating` for `float`, `double` and `long double`, and `other` for anything else. The
   suite's `field-kinds` maps each Chez primitive type to the kinds it may lay out: integer
   types to integer, floating types to floating, `uptr` and `iptr` to integer or other, and
   `void*` to other. Signedness is not compared. A field type `field-kinds` lacks fails the
   shape test by name. A new test requires each type there to be one `foreign-sizeof`
   knows. The per-field test compares `(offset N size N kind K)` whole.
3. **A constant row's C name was free text,** so `(curlh-header . "CURL_VERSION_IPV6")`
   passed, both being 1. Each scalar row's C name must now be its export's name upcased,
   with `-` as `_`, unless `c-name-aliases` names another. That list is empty, and its
   comment says that adding to it is a reviewed change. It holds `(EXPORT . C-NAME)` pairs,
   so an alias pins one C name rather than excusing any. There is one test per row.
4. **"Every row is checked" compared in order,** so a second struct's row had to follow
   `layouts.sls`'s order. Both sides are now sorted.

**This suite now loads libcurl in its own process.** Slice 5's memory gate will see GnuTLS's
p11-kit leak here (AGENTS.md), as it does in `test-native`.

A driver in the session scratchpad ran every case, adapted from the first part's. It froze a
snapshot of the working tree, without `.git`, `build/` or `.claude/`, and gave each case a
fresh copy. It applied each case by exact-text replacement, aborting unless the target
occurred exactly once, and refused a case whose diff was empty unless it ran its own command.
It touched the copy's `manifest.scm` and ran the case's command through the copy's own
`scripts/guix-env`, so the container saw only that copy. The command was `make test`, or, for
HV1, a compile of the accepted decoy followed by `make test` with `CHEZ_CURL_LIBCURL` naming
it. A case marked `old` first put back the suite as it was before these fixes, to reproduce a
finding. A case is killed only when `make test` exits non-zero and every expected line
appears whole in its output: the `FAIL` line, its expected and actual lines where the case is
about a value, and `test: FAIL tests/test-constants.sps (exit 1)`. A case that must pass needs
exit 0 and its expected lines, among them the suite's pass count. The snapshot was taken after
the check-seam fix had landed in the tree. It is byte-identical to the working tree at the
clean rerun. The working tree was never edited for a case.

**Result** quotes at most 12 output lines per run. It shows the expected lines first, each
`FAIL` with its expected and actual lines, then other `FAIL` lines and `test: FAIL` lines,
and says how many more it cut. Output lines longer than 240 characters, and diff lines
longer than 200, are cut, and say so. Paths under the scratchpad are shortened to `…/`.

Cases are named `HV` (the headers' version), `KD` (kinds), `NM` (names) and `OR` (order).
`OLD-` marks a case run on the suite as it was.

### Red runs

**R1, the tests before the C program.** The new tests were written first: the version test and the rule tests, the kind map, kinds in the per-field comparison, the name tests, and the sorted coverage. The C program was still the old one, with no `HEADER_VERSION` and no kinds. `make test` exited 2. The program no longer compiled, since the new header-version question calls a macro it lacked. So the version test failed for want of the headers' answer, as did every per-field and constant test: 65 FAILs, 30 passes. The library was loaded in this process, and named, as `0x081400`:

```
FAIL the C program compiled against libcurl's headers and ran
  expected: ran
  actual:   (compile 1 "" "/tmp/tmp.fGWKUL3QSy/headers.c: In function 'main':\n/tmp/tmp.fGWKUL3QSy/headers.c:11:3: error: implicit declaration of function 'HEADER_VERSION' [-Wimplicit-function-declaration]\n   11 |   HEADER_VERSION();\n     [cut: 24 more characters]
FAIL the headers the C program compiled against are no newer than the libcurl chez-curl loads
  expected: no-newer
  actual:   (headers (no-header-version compile) library "0x081400")
FAIL curl_version_info_data.capath has the header's offset, size and kind
  expected: (no-answer member "curl_version_info_data" "capath")
  actual:   (offset 160 size 8 kind (uptr may-be (integer other)))
test: FAIL tests/test-constants.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
```
(187 more such lines cut.)

The name tests, the field-kinds test, the rule tests and the sorted coverage passed in R1, since the tree is right for each. Each was watched failing in its own case below: NM1 and NM3, KD5, HV2 and HV2b, and KD4. The order fix's red is OLD-OR1.

**G1, the C program written.** `KIND` through `_Generic`, `HEADER_VERSION` printing `LIBCURL_VERSION_NUM`, and `MEMBER` printing the kind. `make test` exited 0, with 95 tests passing in `test-constants`:

```
# of expected passes      95
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
```
(12 more lines cut: the other suites' `test: pass`.)

### The findings, reproduced on the suite as it was

Each finding was reproduced before its fix was trusted. The first three pass the old suite: a library older than its headers, `(capath double)`, and a row naming another constant of the same value. The fourth fails it, because the order is wrong, not because anything is unchecked.

### OLD-HV1. HV1 on the suite as it was

**Guards:** finding 1: the old suite passes with a library older than its headers.

**Base:** the suite as it was before these fixes, `tests/test-constants.sps` replaced by the copy kept before editing.

**Command** in the container: `$CC -shared -fPIC -o "$PWD/hv1-decoy.so" tests/decoy-libcurl.c && CHEZ_CURL_LIBCURL="$PWD/hv1-decoy.so" make test`.

**Result:** as expected, exit 2:

```
# of expected passes      85
test: pass tests/test-constants.sps
FAIL the real libcurl through the override: loaded, with the C oracle's report
  expected: (0 ((loaded . "…/runs/OLD-HV1/hv1-decoy.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same)) "")
  actual:   (0 ((loaded . "…/runs/OLD-HV1/hv1-decoy.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_i [cut: 156 more characters]
test: FAIL tests/test-library-loading.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### OLD-KD1. KD1 on the suite as it was

**Guards:** finding 2: the old suite passes `(capath double)`.

**Base:** the suite as it was before these fixes, `tests/test-constants.sps` replaced by the copy kept before editing.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (cainfo uptr)
-      (capath uptr)
+      (capath double)
       (zstd-ver-num unsigned-int)
```

**Result:** as expected, exit 0:

```
# of expected passes      85
test: pass tests/test-constants.sps
```

### OLD-NM1. NM1 on the suite as it was

**Guards:** finding 3: the old suite passes a row naming another constant of the same value.

**Base:** the suite as it was before these fixes, `tests/test-constants.sps` replaced by the copy kept before editing.

**Mutation:** In `tests/test-constants.sps`:

```diff
     (curlhe-not-built-in . "CURLHE_NOT_BUILT_IN")
-    (curlh-header . "CURLH_HEADER")
+    (curlh-header . "CURL_VERSION_IPV6")
     (curl-global-default . "CURL_GLOBAL_DEFAULT")
```

**Result:** as expected, exit 0:

```
# of expected passes      85
test: pass tests/test-constants.sps
```

### OLD-OR1. OR1 on the suite as it was

**Guards:** finding 4: the old suite fails a second struct whose row is out of layouts.sls's order.

**Base:** the suite as it was before these fixes, `tests/test-constants.sps` replaced by the copy kept before editing.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data curl-easyoption)
   (import (curl private require-threaded)
...
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-ftype curl-easyoption
+    (struct
+      (name uptr)
+      (id int)
+      (type int)
+      (flags unsigned-int))))
```

**Mutation:** In `tests/test-constants.sps`:

```diff
 (define layout-rows
-  '((curl-version-info-data . "curl_version_info_data")))
+  '((curl-easyoption . "struct curl_easyoption")
+    (curl-version-info-data . "curl_version_info_data")))
 
```

**Result:** killed, exit 2:

```
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-easyoption curl-version-info-data)
  actual:   (curl-version-features curl-version-ssl curlhe-not-built-in curlh-header curl-global-default curle-ok curlversion-tenth curl-version-info-data curl-easyoption)
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### Mutations

15 cases ran on the fixed suite. The 13 meant to fail were each killed, with every expected line present. NM2 and OR1 are meant to pass, and both did, with the expected pass count. Some cases change the library or the headers that every suite uses, so other suites failed too: `test-library-loading` under HV1, HV3, HV5; `test-native` under HV3, HV5. Each quote shows this suite's lines first.

### HV1. a library older than the headers: the accepted decoy, 7.85.0, as `CHEZ_CURL_LIBCURL`

**Guards:** the headers are no newer than the libcurl chez-curl loads.

**Command** in the container: `$CC -shared -fPIC -o "$PWD/hv1-decoy.so" tests/decoy-libcurl.c && CHEZ_CURL_LIBCURL="$PWD/hv1-decoy.so" make test`.

**Result:** killed, exit 2:

```
FAIL the headers the C program compiled against are no newer than the libcurl chez-curl loads
  expected: no-newer
  actual:   (headers "0x081400" newer-than library "0x075500")
test: FAIL tests/test-constants.sps (exit 1)
FAIL the real libcurl through the override: loaded, with the C oracle's report
  expected: (0 ((loaded . "…/runs/HV1/hv1-decoy.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same)) "")
  actual:   (0 ((loaded . "…/runs/HV1/hv1-decoy.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (again same same) (calls . "curl_version_info( [cut: 152 more characters]
test: FAIL tests/test-library-loading.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### HV2. the comparison turned round, `>=` for `<=`

**Guards:** the version rule, on fixed numbers (the real headers and library are one version, so the real test passes).

**Mutation:** In `tests/test-constants.sps`:

```diff
 (define (version-verdict headers library)
-  (if (<= headers library)
+  (if (>= headers library)
       'no-newer
```

**Result:** killed, exit 2:

```
FAIL the version rule: headers 0x081400 are newer than a library 0x075500, both named in hex
  expected: (headers "0x081400" newer-than library "0x075500")
  actual:   no-newer
FAIL the version rule: headers older than the library, or the same, are no newer
  expected: (no-newer no-newer)
  actual:   ((headers "0x075500" newer-than library "0x081400") no-newer)
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### HV2b. the comparison made strict, `<` for `<=`

**Guards:** the version rule, on equal numbers; and the real test, at one version.

**Mutation:** In `tests/test-constants.sps`:

```diff
 (define (version-verdict headers library)
-  (if (<= headers library)
+  (if (< headers library)
       'no-newer
```

**Result:** killed, exit 2:

```
FAIL the version rule: headers older than the library, or the same, are no newer
  expected: (no-newer no-newer)
  actual:   (no-newer (headers "0x081400" newer-than library "0x081400"))
FAIL the headers the C program compiled against are no newer than the libcurl chez-curl loads
  expected: no-newer
  actual:   (headers "0x081400" newer-than library "0x081400")
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### HV3. `CHEZ_CURL_LIBCURL` naming a missing file

**Guards:** a refused load fails the version test, naming the reason, never passes it.

**Command** in the container: `CHEZ_CURL_LIBCURL=/nonexistent/libcurl.so.4 make test`.

**Result:** killed, exit 2:

```
FAIL the headers the C program compiled against are no newer than the libcurl chez-curl loads
  expected: no-newer
  actual:   (headers "0x081400" library (refused load-failed "/nonexistent/libcurl.so.4"))
test: FAIL tests/test-constants.sps (exit 1)
FAIL the real libcurl: the probe, in this environment, loads one by absolute path
  expected: loaded
  actual:   (1 ((reason . load-failed) (path . "/nonexistent/libcurl.so.4") (source . override) (detail . "(while loading /nonexistent/libcurl.so.4) /nonexistent/libcurl.so.4: cannot open shared object file: No such file or directory") (can [cut: 46 more characters]
FAIL the C oracle read the real libcurl
  expected: read
  actual:   (no-oracle no-path #f)
test: FAIL tests/test-library-loading.sps (exit 1)
test: FAIL tests/test-native.sps (exit 255)
```
(22 more such lines cut.)

### HV4. the C program's header-version line dropped

**Guards:** the program answers the header-version question; the version test needs its answer.

**Mutation:** In `tests/test-constants.sps`:

```diff
   (case (car question)
-    ((header-version) "  HEADER_VERSION();\n")
+    ((header-version) "")
     ((constant) (string-append "  CONSTANT(" (cadr question) ");\n"))
```

**Result:** killed, exit 2:

```
FAIL the C program answered every question, in order
  expected: ((header-version) (constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "C [cut: 2189 more characters]
  actual:   ((constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "CURL_VERSION_DEBUG [cut: 2172 more characters]
FAIL the headers the C program compiled against are no newer than the libcurl chez-curl loads
  expected: no-newer
  actual:   (headers (no-header-version answers) library "0x081400")
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### HV5. headers missing: `C_INCLUDE_PATH` emptied

**Guards:** a failed compile fails the version test too.

**Command** in the container: `C_INCLUDE_PATH= make test`.

**Result:** killed, exit 2:

```
FAIL the C program compiled against libcurl's headers and ran
  expected: ran
  actual:   (compile 1 "" "/tmp/tmp.rdc1EE5bGp/headers.c:1:10: fatal error: curl/curl.h: No such file or directory\n    1 | #include <curl/curl.h>\n      |          ^~~~~~~~~~~~~\ncompilation terminated.\n")
FAIL the C program answered every question, in order
  expected: ((header-version) (constant "CURL_VERSION_IPV6") (constant "CURL_VERSION_KERBEROS4") (constant "CURL_VERSION_SSL") (constant "CURL_VERSION_LIBZ") (constant "CURL_VERSION_NTLM") (constant "CURL_VERSION_GSSNEGOTIATE") (constant "C [cut: 2189 more characters]
  actual:   ()
FAIL the headers the C program compiled against are no newer than the libcurl chez-curl loads
  expected: no-newer
  actual:   (headers (no-header-version compile) library "0x081400")
test: FAIL tests/test-constants.sps (exit 1)
test: FAIL tests/test-library-loading.sps (exit 1)
test: FAIL tests/test-native.sps (exit 1)
```
(295 more such lines cut.)

### KD1. `(capath double)`, C's `char *`

**Guards:** each field's kind is C's: offset and size both still match.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (cainfo uptr)
-      (capath uptr)
+      (capath double)
       (zstd-ver-num unsigned-int)
```

**Result:** killed, exit 2:

```
FAIL curl_version_info_data.capath has the header's offset, size and kind
  expected: (offset 160 size 8 kind other)
  actual:   (offset 160 size 8 kind (double may-be (floating)))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### KD2. `(age float)`, C's `int`

**Guards:** each field's kind is C's: offset and size both still match.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
     (struct
-      (age int)
+      (age float)
       (version uptr)
```

**Result:** killed, exit 2:

```
FAIL curl_version_info_data.age has the header's offset, size and kind
  expected: (offset 0 size 4 kind integer)
  actual:   (offset 0 size 4 kind (float may-be (floating)))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### KD3. an `(x uptr)` field against a C `double`: a test-only struct `kd3_t` defined in the C program, an ftype and a row for it

**Guards:** uptr may be integer or other, never floating.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data kd3)
   (import (curl private require-threaded)
...
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-ftype kd3 (struct (x uptr))))
```

**Mutation:** In `tests/test-constants.sps`:

```diff
 (define layout-rows
-  '((curl-version-info-data . "curl_version_info_data")))
+  '((curl-version-info-data . "curl_version_info_data")
+    (kd3 . "kd3_t")))
 
...
    "#include <stddef.h>\n"
-   "#include <stdio.h>\n"
+   "#include <stdio.h>\ntypedef struct { double x; } kd3_t;\n"
    "\n"
```

**Result:** killed, exit 2:

```
FAIL kd3_t.x has the header's offset, size and kind
  expected: (offset 0 size 8 kind floating)
  actual:   (offset 0 size 8 kind (uptr may-be (integer other)))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### KD4. a field type field-kinds lacks, `(age boolean)`, int-sized

**Guards:** a field type absent from field-kinds fails the shape test by name (fail closed).

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
     (struct
-      (age int)
+      (age boolean)
       (version uptr)
```

**Result:** killed, exit 2:

```
FAIL layouts.sls: curl-version-info-data is a struct of primitive-typed fields, each type in field-kinds
  expected: handled
  actual:   (no-kind (age boolean))
FAIL every row of constant-rows and layout-rows is checked
  expected: (curl-global-default curl-version-features curl-version-info-data curl-version-ssl curle-ok curlh-header curlhe-not-built-in curlversion-tenth)
  actual:   (curl-global-default curl-version-features curl-version-ssl curle-ok curlh-header curlhe-not-built-in curlversion-tenth)
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### KD5. field-kinds misspells a type, `void-star`

**Guards:** each type field-kinds holds is one foreign-sizeof knows.

**Mutation:** In `tests/test-constants.sps`:

```diff
      (iptr integer other)
-     (void* other))))
+     (void-star other))))
 
```

**Result:** killed, exit 2:

```
FAIL field-kinds: each type is one foreign-sizeof knows, each kind integer, floating or other
  expected: ()
  actual:   ((void-star other))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### NM1. `(curlh-header . "CURL_VERSION_IPV6")`, both 1

**Guards:** a row's C name is its export's name upcased, - as _.

**Mutation:** In `tests/test-constants.sps`:

```diff
     (curlhe-not-built-in . "CURLHE_NOT_BUILT_IN")
-    (curlh-header . "CURLH_HEADER")
+    (curlh-header . "CURL_VERSION_IPV6")
     (curl-global-default . "CURL_GLOBAL_DEFAULT")
```

**Result:** killed, exit 2:

```
FAIL constant-rows' row curlh-header names CURLH_HEADER, its name upcased, - as _
  expected: "CURLH_HEADER"
  actual:   "CURL_VERSION_IPV6"
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### NM2. NM1, excused by a c-name-aliases entry `(curlh-header . "CURL_VERSION_IPV6")`

**Guards:** the exception works: an alias names the C name its row must name. Expected to pass, with 95 tests.

**Mutation:** In `tests/test-constants.sps`:

```diff
     (curlhe-not-built-in . "CURLHE_NOT_BUILT_IN")
-    (curlh-header . "CURLH_HEADER")
+    (curlh-header . "CURL_VERSION_IPV6")
     (curl-global-default . "CURL_GLOBAL_DEFAULT")
...
 ;; text can name any constant whose value happens to match.
-(define c-name-aliases '())
+(define c-name-aliases '((curlh-header . "CURL_VERSION_IPV6")))
 
```

**Result:** as expected, exit 0:

```
# of expected passes      95
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
```

### NM3. an alias `(curlh-header . "CURL_VERSION_IPV6")`, the row still `CURLH_HEADER`

**Guards:** an alias pins the C name; it does not excuse any name.

**Mutation:** In `tests/test-constants.sps`:

```diff
 ;; text can name any constant whose value happens to match.
-(define c-name-aliases '())
+(define c-name-aliases '((curlh-header . "CURL_VERSION_IPV6")))
 
```

**Result:** killed, exit 2:

```
FAIL constant-rows' row curlh-header names CURL_VERSION_IPV6, its entry in c-name-aliases
  expected: "CURL_VERSION_IPV6"
  actual:   "CURLH_HEADER"
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### OR1. a second ftype, `curl-easyoption`, after `curl-version-info-data` in layouts.sls, its row before it in layout-rows

**Guards:** coverage is compared in any order. Expected to pass, with 102 tests: 4 more field tests, and the second ftype's two coverage tests and its shape test.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data curl-easyoption)
   (import (curl private require-threaded)
...
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-ftype curl-easyoption
+    (struct
+      (name uptr)
+      (id int)
+      (type int)
+      (flags unsigned-int))))
```

**Mutation:** In `tests/test-constants.sps`:

```diff
 (define layout-rows
-  '((curl-version-info-data . "curl_version_info_data")))
+  '((curl-easyoption . "struct curl_easyoption")
+    (curl-version-info-data . "curl_version_info_data")))
 
```

**Result:** as expected, exit 0:

```
# of expected passes      102
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
```

### Clean rerun

After every case, on the working tree itself. `make test` exited 0, with 95 tests passing in `test-constants`:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (13 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
# of expected passes      95
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
```
(12 more lines cut: the other suites' `test: pass`.)

## Review fixes: define-ftype only in layouts

Evidence for a review finding on M0 slice 4. In Chez a function ftype binds a C entry point
without `foreign-procedure`: `(define-ftype F (function (int) int))`, then
`(ftype-ref F () (make-ftype-pointer F "abs"))` calls libc's `abs`, and
`(make-ftype-pointer F (lambda ...))` makes a callable. `define-ftype`, `make-ftype-pointer`
and `ftype-ref` were in `allowed-chez-names`, so any library could import them, and the
collect-safe suite knows only `foreign-procedure` and `foreign-callable`. A binding or a
callback could dodge the conventions table and the load's `foreign-entry?` check, with every
check green. In the container, after `(load-shared-object "libc.so.6")`, such an ftype called
`abs` and answered 5 for -5. An anonymous `(function (int) int)` in `make-ftype-pointer` or in
`ftype-ref` raised `invalid syntax`, so `define-ftype` is the only way in.

The fix, in `tests/check-seam.sps`, `tests/test-check-seam.sps` and
`tests/fixtures/seam/ftype-*`:

- `library-only-chez-names`, `'((define-ftype (curl private layouts)))`: each entry is a name
  in `allowed-chez-names` and the libraries that alone may import it. Any other library that
  imports it is named, as rule (f). Together with `test-constants`, which holds every
  `define-ftype` in `layouts.sls` to a struct of primitive-typed fields, no function ftype can
  exist under `src/`.
- Three fixture trees: `ftype-listed` (the listed library imports `define-ftype`: passes),
  `ftype-elsewhere` (four libraries that are not listed, two of them near the listed name, one in
  `(http-client ...)`, beside the listed library, which is not named) and `ftype-with-unlisted`
  (`define-ftype` between two names `allowed-chez-names` does not list).
- Three tests on the list, read from the program as data: it holds `(name library ...)`
  entries; every name in it is in `allowed-chez-names`; each entry's libraries are exactly the
  libraries under `src/` that import its name, so no permission is stale and none is missing.

A driver in the session scratchpad ran every mutation. It froze the tree, without `build/`,
and gave each mutation a fresh copy of it. It applied the mutation by exact-text replacement,
aborting unless the target occurred exactly once, and refused a mutation whose diff was empty.
It touched the copy's `manifest.scm` (`traps.md`, the stale `guix shell -m` profile) and ran
`scripts/guix-env make test` from inside the copy, so the container saw only that copy. A
mutation counts as killed only when the command exits non-zero and every expected line appears
whole in its output. SM1 and SM7 must also stop at `check-seam`: no `=== tests/` line may
appear. Each output was kept verbatim. The tree was never edited.

**Result** quotes the `FAIL` lines with their expected and actual lines, the `check-seam:`
lines other than the pass line, the `test: FAIL` and `test: ran` lines and make's error line,
at most 12 lines a run. The `FAIL` blocks that hold the lines the case expects come first, and
a run that had more says how many lines it cut. A diff line longer than 200 characters and an
output line longer than 240 are cut, and say how much was cut.

Mutations are named `SM` (seam mutation). H0 is the same change as SM1, made in the tree before the fix.

### Red runs

**The hole, before the fix.** The pristine tree this fix merges against, with `native.sls`
importing `define-ftype` and binding `curl_easy_perform` as a function ftype. `make test`
exited 0: `check-seam`, `test-collect-safe` and every other check passed.

**Mutation:** In `src/curl/private/native.sls`:

```diff
           (rnrs)
-          (only (chezscheme) ftype-ref make-ftype-pointer
+          (only (chezscheme) define-ftype ftype-ref make-ftype-pointer
                 foreign-procedure foreign-entry? load-shared-object
...
   ;; this reference and every later one.
-  (define (loaded-libcurl) info))
+  (define (loaded-libcurl) info)
+
+  (define-ftype easy-perform-fn (function (uptr) int))
+  (define (easy-perform easy)
+    ((ftype-ref easy-perform-fn () (make-ftype-pointer easy-perform-fn "curl_easy_perform"))
+     easy)))
```
**Result:** exit 0 (`make test`):

```
check-seam: the seam holds (10 libraries in 10 files checked)
test: ran 13, passed 13, failed 0, hung 0
```

**The suite and the fixtures first.** `tests/test-check-seam.sps` with its three new cases and
three new tests, the three fixture trees, and `tests/check-seam.sps` as it was. `make test`
exited 2. The suite ran, and five tests failed by name. `ftype-listed` passed, as it must: a
tree where the listed library imports the name is legal before the rule too. SM6 fails it.

```
FAIL ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 693 more characters]
  actual:   (0 "check-seam: the seam holds (5 libraries in 5 files checked)\n" "")
FAIL ftype-with-unlisted: rule (f) and rule (c) in one import set: each name outside its list is named, in the order the import set holds them
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 368 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 161 more characters]
FAIL library-only-chez-names is a list of (name library ...) entries
  expected: entries
  actual:   (not-defined)
FAIL every name in library-only-chez-names is in allowed-chez-names
  expected: ()
  actual:   (unreadable "Exception in car: not-defined is not a pair")
FAIL each library-only-chez-names entry lists exactly the libraries under src/ that import its name
  expected: (unreadable "Exception in car: not-defined is not a pair")
  actual:   (malformed "Exception in car: not-defined is not a pair")
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
```

### Baseline

The rule written. This is the snapshot every mutation copied; it is identical, file for file,
to the tree at the clean rerun. `make test` exited 0, with 47 tests passing in
`test-check-seam` (41 before):

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (13 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: pass tests/test-check-floors.sps
test: pass tests/test-check-seam.sps
test: pass tests/test-collect-safe.sps
test: pass tests/test-conditions.sps
test: pass tests/test-constants.sps
test: pass tests/test-curl-testing.sps
test: pass tests/test-discovery.sps
test: pass tests/test-library-loading.sps
test: pass tests/test-load-state.sps
test: pass tests/test-manifest.sps
test: pass tests/test-native.sps
test: pass tests/test-require-threaded.sps
test: pass tests/test-verify.sps
test: ran 13, passed 13, failed 0, hung 0
```

### Mutations

16 mutations ran. 15 were killed, each with every expected line present. SM16 survived, as
expected (see Not covered). SM1 and SM7 were killed by `check-seam` on the real `src/`, before
any suite ran. The other 13 were killed by `tests/test-check-seam.sps`, SM8 run alone.

Every one of the six new tests and cases was failed by name by at least one mutant:

| Test or case | Failed by |
|---|---|
| `ftype-listed` | SM6 |
| `ftype-elsewhere` | SM2, SM3, SM4, SM9, SM10, SM11, SM12, SM13 |
| `ftype-with-unlisted` | SM2, SM3, SM4, SM9, SM13 |
| `library-only-chez-names is a list of (name library ...) entries` | SM13 |
| `every name in library-only-chez-names is in allowed-chez-names` | SM5 |
| `each library-only-chez-names entry lists exactly the libraries under src/ that import its name` | SM4, SM5, SM8, SM13, SM14, SM15 |

### SM1. `native.sls` imports `define-ftype` and binds `curl_easy_perform` as a function ftype

**Guards:** only (curl private layouts) imports define-ftype.
**Mutation:** In `src/curl/private/native.sls`:

```diff
           (rnrs)
-          (only (chezscheme) ftype-ref make-ftype-pointer
+          (only (chezscheme) define-ftype ftype-ref make-ftype-pointer
                 foreign-procedure foreign-entry? load-shared-object
...
   ;; this reference and every later one.
-  (define (loaded-libcurl) info))
+  (define (loaded-libcurl) info)
+
+  (define-ftype easy-perform-fn (function (uptr) int))
+  (define (easy-perform easy)
+    ((ftype-ref easy-perform-fn () (make-ftype-pointer easy-perform-fn "curl_easy_perform"))
+     easy)))
```
**Result:** killed, exit 2:

```
check-seam: src/curl/private/native.sls: (curl private native) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)
check-seam: FAILED (problems: 1)
make: *** [Makefile:236: check-seam] Error 1
```

This is the finding. H0 above makes the same change in the tree before the fix, and `make test` exits 0.

### SM2. `define-ftype` removed from `library-only-chez-names`

**Guards:** the list holds define-ftype, so a library that is not listed cannot import it.
**Mutation:** In `tests/check-seam.sps`:

```diff
 (define library-only-chez-names
-  '((define-ftype (curl private layouts))))
+  '())
 
```
**Result:** killed, exit 2:

```
FAIL ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 693 more characters]
  actual:   (0 "check-seam: the seam holds (5 libraries in 5 files checked)\n" "")
FAIL ftype-with-unlisted: rule (f) and rule (c) in one import set: each name outside its list is named, in the order the import set holds them
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 368 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 161 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

`ftype-elsewhere` got the program's pass line: with no entry, no library is held to a list.

### SM3. rule (f) disabled in `name-complaints`

**Guards:** the program names a library that imports a library-only name and is not listed.
**Mutation:** In `tests/check-seam.sps`:

```diff
                             " tests/check-seam.sps does not list it")))
-      ((and only (not (member name (cdr only))))
+      ((and #f only (not (member name (cdr only))))
        (list (string-append path ": " (written name) " imports "
```
**Result:** killed, exit 2:

```
FAIL ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 693 more characters]
  actual:   (0 "check-seam: the seam holds (5 libraries in 5 files checked)\n" "")
FAIL ftype-with-unlisted: rule (f) and rule (c) in one import set: each name outside its list is named, in the order the import set holds them
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 368 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 161 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

### SM4. a stale library added to the entry, `(curl private native)`

**Guards:** each entry lists exactly the libraries under src/ that import its name: no stale permission.
**Mutation:** In `tests/check-seam.sps`:

```diff
 (define library-only-chez-names
-  '((define-ftype (curl private layouts))))
+  '((define-ftype (curl private layouts) (curl private native))))
 
```
**Result:** killed, exit 2:

```
FAIL ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 693 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts), (curl private nati [cut: 785 more characters]
FAIL ftype-with-unlisted: rule (f) and rule (c) in one import set: each name outside its list is named, in the order the import set holds them
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 368 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 391 more characters]
FAIL each library-only-chez-names entry lists exactly the libraries under src/ that import its name
  expected: ((define-ftype (curl private layouts)))
  actual:   ((define-ftype (curl private layouts) (curl private native)))
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

The entry lists a library that does not import `define-ftype`, a stale permission. `check-seam` on `src/` has nothing to say about it. The complaints end `(curl private layouts), (curl private native)`, so the two cases that print them fail, and so does the exactness test, which is the one that names the stale entry.

### SM5. an entry for `top-level-value`, which `allowed-chez-names` does not list

**Guards:** every name in library-only-chez-names is in allowed-chez-names.
**Mutation:** In `tests/check-seam.sps`:

```diff
 (define library-only-chez-names
-  '((define-ftype (curl private layouts))))
+  '((define-ftype (curl private layouts)) (top-level-value (curl private layouts))))
 
```
**Result:** killed, exit 2:

```
FAIL every name in library-only-chez-names is in allowed-chez-names
  expected: ()
  actual:   (top-level-value)
FAIL each library-only-chez-names entry lists exactly the libraries under src/ that import its name
  expected: ((define-ftype (curl private layouts)) (top-level-value))
  actual:   ((define-ftype (curl private layouts)) (top-level-value (curl private layouts)))
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

Both lines fail: the entry names a name `allowed-chez-names` does not list, and its libraries are not the libraries that import it (none do).

### SM6. the legal fixture renamed, so the listed library no longer imports `define-ftype`

**Guards:** a library that is listed passes: the legal tree is a tree where the listed library imports the name.
**Mutation:** In `tests/fixtures/seam/ftype-listed/curl/private/layouts.sls`:

```diff
 ;;; ftype is what that rule closes elsewhere; here it is only a struct.
-(library (curl private layouts)
+(library (curl private layout)
   (export point)
```
**Result:** killed, exit 2:

```
FAIL ftype-listed: rule (f), passing: define-ftype imported by (curl private layouts), the one library library-only-chez-names lists for it
  expected: (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-listed/curl/private/layouts.sls: (curl private layout) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layo [cut: 42 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

The fixture's library is now `(curl private layout)`, which is not listed, so the program names it, as it must, and the test that expected a pass fails.

### SM7. an entry for `ftype-ref` that lists only `(curl private layouts)`, though `native.sls` imports it

**Guards:** a library that imports a library-only name and is not listed fails check-seam, on the real src/.
**Mutation:** In `tests/check-seam.sps`:

```diff
 (define library-only-chez-names
-  '((define-ftype (curl private layouts))))
+  '((define-ftype (curl private layouts)) (ftype-ref (curl private layouts))))
 
```
**Result:** killed, exit 2:

```
check-seam: src/curl/private/native.sls: (curl private native) imports ftype-ref from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)
check-seam: FAILED (problems: 1)
make: *** [Makefile:236: check-seam] Error 1
```

`ftype-ref` is a name `native.sls` imports. This shows the rule reads the list for any name, not `define-ftype` alone.

### SM8. SM1's change, with check-seam left out of the run: `test-check-seam` alone

**Guards:** each entry lists exactly the libraries under src/ that import its name: no missing permission.
**Mutation:** In `src/curl/private/native.sls`:

```diff
           (rnrs)
-          (only (chezscheme) ftype-ref make-ftype-pointer
+          (only (chezscheme) define-ftype ftype-ref make-ftype-pointer
                 foreign-procedure foreign-entry? load-shared-object
...
   ;; this reference and every later one.
-  (define (loaded-libcurl) info))
+  (define (loaded-libcurl) info)
+
+  (define-ftype easy-perform-fn (function (uptr) int))
+  (define (easy-perform easy)
+    ((ftype-ref easy-perform-fn () (make-ftype-pointer easy-perform-fn "curl_easy_perform"))
+     easy)))
```
**Command:** `make -o check-seam test SUITES=tests/test-check-seam.sps` (`-o check-seam` leaves check-seam out, so the suite runs).
**Result:** killed, exit 2:

```
FAIL each library-only-chez-names entry lists exactly the libraries under src/ that import its name
  expected: ((define-ftype (curl private layouts) (curl private native)))
  actual:   ((define-ftype (curl private layouts)))
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

SM1's change fails `check-seam` on `src/` first (SM1), so `make test` never reaches this suite. Run alone, the suite names the missing permission: `native.sls` imports `define-ftype` and the entry lists only `(curl private layouts)`.

### SM9. a listed library matched by its first identifier, `curl`

**Guards:** the whole library name must match, so a near name is named.
**Mutation:** In `tests/check-seam.sps`:

```diff
                             " tests/check-seam.sps does not list it")))
-      ((and only (not (member name (cdr only))))
+      ((and only (not (member (car name) (map car (cdr only)))))
        (list (string-append path ": " (written name) " imports "
```
**Result:** killed, exit 2:

```
FAIL ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 693 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/http-client/h.sls: (http-client h) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\nchec [cut: 32 more characters]
FAIL ftype-with-unlisted: rule (f) and rule (c) in one import set: each name outside its list is named, in the order the import set holds them
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 368 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 161 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

The actual output names only `(http-client h)`: the three `(curl ...)` libraries start with `curl`, so they passed.

### SM10. a listed library matched by its last identifier

**Guards:** the whole library name must match, so (curl layouts) is named.
**Mutation:** In `tests/check-seam.sps`:

```diff
                             " tests/check-seam.sps does not list it")))
-      ((and only (not (member name (cdr only))))
+      ((and only (not (member (car (reverse name)) (map (lambda (l) (car (reverse l))) (cdr only)))))
        (list (string-append path ": " (written name) " imports "
```
**Result:** killed, exit 2:

```
FAIL ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 693 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 478 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

The actual output lacks `(curl layouts)`, whose last identifier is `layouts`. The other three libraries are named.

### SM11. a listed library matched by prefix, so `(curl private layouts extra)` passes

**Guards:** the whole library name must match, so a name that starts with the listed one is named.
**Mutation:** In `tests/check-seam.sps`:

```diff
                             " tests/check-seam.sps does not list it")))
-      ((and only (not (member name (cdr only))))
+      ((and only (not (exists (lambda (lib) (let prefix ((a lib) (b name)) (or (null? a) (and (pair? b) (equal? (car a) (car b)) (prefix (cdr a) (cdr b)))))) (cdr only))))
        (list (string-append path ": " (written name) " imports "
```
**Result:** killed, exit 2:

```
FAIL ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 693 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 450 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

The actual output lacks `(curl private layouts extra)`, whose name starts with the listed one. The other three libraries are named.

### SM12. rule (f) applied to `(curl ...)` libraries only

**Guards:** the rule holds in both families.
**Mutation:** In `tests/check-seam.sps`:

```diff
                             " tests/check-seam.sps does not list it")))
-      ((and only (not (member name (cdr only))))
+      ((and only (family? 'curl name) (not (member name (cdr only))))
        (list (string-append path ": " (written name) " imports "
```
**Result:** killed, exit 2:

```
FAIL ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 693 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 476 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

The actual output lacks `(http-client h)`. The three `(curl ...)` libraries are named.

### SM13. an entry that lists a library as a bare symbol, `foo`

**Guards:** an entry is a name and the library names that alone may import it.
**Mutation:** In `tests/check-seam.sps`:

```diff
 (define library-only-chez-names
-  '((define-ftype (curl private layouts))))
+  '((define-ftype (curl private layouts) foo)))
 
```
**Result:** killed, exit 2:

```
FAIL ftype-elsewhere: rule (f): define-ftype imported by a library that is not listed, in either family, or by names that only look like the listed one; the listed library beside them is not named
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts)\ncheck-seam: tests/ [cut: 693 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-elsewhere/curl/f.sls: (curl f) imports define-ftype from (chezscheme), but library-only-chez-names in tests/check-seam.sps allows it only in (curl private layouts), foo\ncheck-seam: t [cut: 713 more characters]
FAIL ftype-with-unlisted: rule (f) and rule (c) in one import set: each name outside its list is named, in the order the import set holds them
  expected: (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 368 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/ftype-with-unlisted/curl/m.sls: (curl m) imports eval from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it\ncheck-seam: tests/fixtures/seam/ftype-with-unlisted [cut: 373 more characters]
FAIL library-only-chez-names is a list of (name library ...) entries
  expected: entries
  actual:   ((define-ftype (curl private layouts) foo))
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
[3 more lines cut]
```

The three lines cut are the exactness test's FAIL: `foo` is not a library that imports `define-ftype`. `ftype-elsewhere` and `ftype-with-unlisted` fail too, since the complaint now ends `(curl private layouts), foo`.

### SM14. the suite scans a tree that has no `define-ftype` for the libraries that import a name

**Guards:** the scan of src/ is what the exactness test compares the entries with.
**Mutation:** In `tests/test-check-seam.sps`:

```diff
                              (read-forms path))))
-              (sls-files "src"))))
+              (sls-files "tests/fixtures/seam/legal"))))
 
```
**Result:** killed, exit 2:

```
FAIL allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  expected: (format threaded?)
  actual:   (define-ftype display-condition file-regular? foreign-alloc foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof format format-condition? ftype-ref getenv load-shared-object machine-type make-ftype-pointer sc [cut: 45 more characters]
FAIL each library-only-chez-names entry lists exactly the libraries under src/ that import its name
  expected: ((define-ftype))
  actual:   ((define-ftype (curl private layouts)))
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

The scan read a tree without `define-ftype`, so the libraries that import it came out as none. The older test, that `allowed-chez-names` equals the imported names, fails too.

### SM15. a second library form named `(curl private layouts)` in `native.sls`, with a function ftype

**Guards:** a listed name appears once: a library named like the listed one, elsewhere, is counted.
**Mutation:** In `src/curl/private/native.sls`:

```diff
   (define (loaded-libcurl) info))
+
+(library (curl private layouts)
+  (export easy-perform)
+  (import (rnrs) (only (chezscheme) define-ftype ftype-ref make-ftype-pointer))
+  (define-ftype easy-perform-fn (function (uptr) int))
+  (define (easy-perform easy)
+    ((ftype-ref easy-perform-fn () (make-ftype-pointer easy-perform-fn "curl_easy_perform"))
+     easy)))
```
**Result:** killed, exit 2:

```
FAIL each library-only-chez-names entry lists exactly the libraries under src/ that import its name
  expected: ((define-ftype (curl private layouts) (curl private layouts)))
  actual:   ((define-ftype (curl private layouts)))
test: FAIL tests/test-check-seam.sps (exit 1)
test: ran 13, passed 12, failed 1, hung 0
make: *** [Makefile:192: test] Error 1
```

`check-seam` on `src/` passes it, the name being listed. So do `test-constants`, which reads `layouts.sls` alone, `test-native` and `test-collect-safe`. Only the count of libraries named `(curl private layouts)` notices a second one, and `ftype-listed` and `ftype-elsewhere` cannot.

### SM16. the separator between two listed libraries in the complaint changed, `", "` to `" and "`

**Guards:** a complaint writes the libraries it allows, a comma between each two.
**Mutation:** In `tests/check-seam.sps`:

```diff
                             " tests/check-seam.sps allows it only in "
-                            (joined ", " (map written (cdr only))))))
+                            (joined " and " (map written (cdr only))))))
       (else '()))))
```
**Result:** survived, as expected, exit 0:

```
test: ran 13, passed 13, failed 0, hung 0
```

No entry lists two libraries, so no fixture prints a complaint with two. The separator is
unguarded. A case for it needs the program to take its list from the tree it checks, which
this fix does not do.

### Not covered

- **The separator between two listed libraries in a complaint** (SM16). `library-only-chez-names`
  has one library for its one name.
- **A library that is named like a listed one, elsewhere** is caught only by SM15's count: a
  library name that appears twice among the libraries that import the name. `check-seam` does
  not check that library names are unique, or that a library's name matches its file.

### Clean rerun

After every mutation, on the tree itself, which was still identical to the snapshot. `make
test` exited 0, and so did `make check-test-fails`, which needed no change ("make test failed,
as it must, in all 10 cases"):

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (13 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: pass tests/test-check-floors.sps
test: pass tests/test-check-seam.sps
test: pass tests/test-collect-safe.sps
test: pass tests/test-conditions.sps
test: pass tests/test-constants.sps
test: pass tests/test-curl-testing.sps
test: pass tests/test-discovery.sps
test: pass tests/test-library-loading.sps
test: pass tests/test-load-state.sps
test: pass tests/test-manifest.sps
test: pass tests/test-native.sps
test: pass tests/test-require-threaded.sps
test: pass tests/test-verify.sps
test: ran 13, passed 13, failed 0, hung 0
```

## Second review fixes

Evidence that the fixes from slice 4's second review each fail through the property they
guard ([ADR-0007](decisions/0007-one-repo-checked-seam.md)'s rule (f),
[ADR-0001](decisions/0001-bind-libcurl-directly.md), decision 4). Only `tests/test-constants.sps`,
`tests/check-seam.sps`, `tests/test-check-seam.sps` and three new fixture trees under
`tests/fixtures/seam/` changed. `src/` did not. The review found three holes:

1. **`define-ftype` could reach a function ftype outside a plain struct form in
   `layouts.sls`.** Rule (f) let only `(curl private layouts)` import `define-ftype`, and
   `test-constants` checked only the lists headed by that symbol. The reviewer bound libc's
   `strlen` through a function ftype three ways, with `make test` fully green. In P1, layouts
   exported `define-ftype`. In P2, a macro in layouts applied `define-ftype` passed in as an
   argument, so no list was headed by it. In P3, layouts exported a macro whose template
   expanded to `define-ftype`. Three fixes close the class:
   - **`test-constants` holds `layouts.sls` to an exact shape.** The file is one datum, the
     library `(curl private layouts)`. Its imports are exactly
     `(curl private require-threaded)`, `(rnrs)` and `(only (chezscheme) define-ftype)`, in
     order, so a wrapped, prefixed or renamed import fails. Its body is
     `(define-ftype NAME (struct ...))` forms alone. Its exports are exactly those `NAME`s,
     as plain identifiers, in any order. The symbol `define-ftype`, quoted or not, appears
     only in its `(only (chezscheme) ...)` import and at the head of its body forms. The
     walks are cycle-safe, and the read fails on an `#!eof` literal.
   - **`test-constants` reads rule (f) from `tests/check-seam.sps` as data.** It requires
     `library-only-chez-names` to be defined once, as a quoted list, with one entry for
     `define-ftype`, exactly `(define-ftype (curl private layouts))`. Widening rule (f) to
     another library fails until that library is held to a shape too.
   - **`check-seam` has a new rule (g): no library under `src/` exports a name it imports
     from `(chezscheme)`.** That covers a plain export and the internal name of a
     `(rename (internal external))` spec. A spec that is neither, the only two forms Chez
     10.4.0 accepts (probed: `(import ...)`, `(car)`, `(foo car)`, `42` and a bad `rename`
     each raise "invalid export spec"), is named as an export it cannot read. Rule (c)
     already refuses every wrapper round `(only (chezscheme) ...)`: `prefix`, `rename`,
     `except`, `for` and a nested `only`. So the names inside those `only`s are exactly the
     local names `(chezscheme)` binds, and rule (g) reads them there. A new fixture row pins
     that refusal for a wrapper whose export uses the name it makes.
2. **`uptr` and `iptr` mapped to integer or other,** so a `uptr` written for C's `long`
   passed. Now `uptr` and `void*` map to other, and `iptr` to integer.
3. **An `(each PREFIX)` row's prefix was free text.** `"0|CURL_VERSION_"` made every entry's
   C expression another one with the same value, and passed. The prefix is now derived: the
   export's name less its last hyphen-separated word, upcased, `-` as `_`, then `_`. Only
   `c-name-aliases` can name another. Each alias must name a row, be its row's first entry,
   and change what the row's name derives. Anything else is a stale permission, and fails.

A driver in the session scratchpad ran every case, adapted from the first fix part's. It
froze a snapshot of the working tree, without `.git`, `build/` or `.claude/`, and gave each case
a fresh copy. It applied each case by exact-text replacement, aborting unless the target
occurred exactly once. Two kinds of edit were exceptions: P8's rewording of test-check-seam's
rows, which replaced every occurrence, and the reviewer's own `layouts.sls` and `sneak.sls`,
copied in whole. It refused a case whose diff was empty unless the case ran its own command.
It touched the copy's `manifest.scm` and ran the case's command through the copy's own
`scripts/guix-env`, so the container saw only that copy.

The command was `make test`. `make test` runs check-seam before any suite, so where check-seam
stops it, the command also ran `tests/test-constants.sps` directly, to show what the suite
says. For the reviewer's trees it then ran the reviewer's caller, `call.sps`, which loads libc
and calls `sneak-strlen` on `"hello"`. It prints `(strlen-of-hello 5)` when the route is live.
The exit status judged is always `make test`'s.

Each case ran on one of three bases:
- **red:** the new tests with `check-seam.sps` as it was, which is how the tree stood before
  rule (g) was written;
- **old:** all three files as they were, with the new fixture trees removed, to reproduce a
  finding;
- **new:** the fixed tree.

A case is killed only when `make test` exits non-zero and every expected line appears whole
in its output. A case that must pass needs exit 0 and its expected lines, among them the
suite's pass count. The snapshot is byte-identical to the working tree at the clean rerun.
The working tree was never edited for a case.

**Result** quotes at most 12 output lines per run. It shows each expected line's first
appearance first, each `FAIL` with its expected and actual lines. Then come other `FAIL`
lines, and the `check-seam:`, `test: FAIL`, `direct:` and `make` lines. It says how many
more it cut. Output lines longer than 240 characters, and diff lines longer than 200, are
cut, and say so. Paths under the scratchpad are shortened to `…/`.

Cases are named `P` (the class: a route to a function ftype), `N` and `D` (layouts' name and
how it is read), `X` (rule (g)), `K` (kinds) and `E` (each prefixes and aliases). `RED-` marks a
red run and `OLD-` a finding reproduced on the suites as they were.

### Red runs

**R1, the rows before rule (g).** The three new rows of `tests/test-check-seam.sps` and their fixture trees were written first, and run against `check-seam.sps` as it was. `export-chez` and `export-unreadable` failed, the program passing both trees. `export-wrapped-chez` passed: rule (c) already refuses each wrapper, and the row pins that refusal. A first draft put a cyclic export spec, `#0=`, in a `#!r6rs` file, which Chez's reader refuses in that mode. It moved to a file without the directive, as `cannot-read-import/curl/m4.sls` already is.

```
FAIL export-chez: rule (g): a name imported from (chezscheme) exported, plain or as a rename spec's internal name, in either family, each in export order; a name from (rnrs), a rename of a library's own definition to a (chezscheme) name, an [cut: 62 more characters]
  expected: (1 "" "check-seam: tests/fixtures/seam/export-chez/curl/private/layouts.sls: (curl private layouts) exports define-ftype, but it imports define-ftype from (chezscheme), and no library under src/ may export a name it imports from [cut: 668 more characters]
  actual:   (0 "check-seam: the seam holds (4 libraries in 4 files checked)\n" "")
FAIL export-unreadable: rule (g) fails closed: each export spec that is neither an identifier nor (rename (internal external) ...) is named, in order, a cyclic one included
  expected: (1 "" "check-seam: tests/fixtures/seam/export-unreadable/curl/x.sls: (curl x) has an export it cannot read: 42\ncheck-seam: tests/fixtures/seam/export-unreadable/curl/x.sls: (curl x) has an export it cannot read: \"s\"\ncheck-se [cut: 851 more characters]
  actual:   (0 "check-seam: the seam holds (2 libraries in 2 files checked)\n" "")
# of expected passes      48
# of unexpected failures  2
suite exit 1
```

The new tests in `test-constants` passed on the tree, 102 in all, since the tree is right for each. They were then run on the reviewer's three trees, on the red base, before rule (g) was written. Each failed by name, and each tree still called `strlen`. On that base `test-check-seam` fails as well, on R1's two rows:

### RED-P1. the reviewer's P1 tree: layouts exports `define-ftype`, and `(curl private sneak)` imports layouts and binds `strlen` through a function ftype

**Guards:** the export rule and the stray rule, before check-seam's rule (g) exists.

**Base:** the tree with the new tests, `tests/check-seam.sps` as it was before these fixes.

**Added:** `call.sps`, the reviewer's caller, at the copy's root.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data define-ftype)
   (import (curl private require-threaded)
```

**Mutation:** In `src/curl/private/sneak.sls`:

```diff
+#!r6rs
+(library (curl private sneak)
+  (export sneak-strlen)
+  (import (curl private require-threaded)
+          (rnrs)
+          (curl private layouts)
+          (only (chezscheme) make-ftype-pointer ftype-ref))
+  (define-ftype strlen-t (function (string) size_t))
+  (define (sneak-strlen s)
+    ((ftype-ref strlen-t () (make-ftype-pointer strlen-t "strlen")) s)))
```

**Command** in the container: `make test`, then `tests/test-constants.sps` run directly, then the reviewer's caller, `call.sps`, which loads libc and calls `sneak-strlen` on `"hello"`.

**Result:** killed, exit 2:

```
FAIL export-chez: rule (g): a name imported from (chezscheme) exported, plain or as a rename spec's internal name, in either family, each in export order; a name from (rnrs), a rename of a library's own definition to a (chezscheme) name, an [cut: 62 more characters]
  expected: (1 "" "check-seam: tests/fixtures/seam/export-chez/curl/private/layouts.sls: (curl private layouts) exports define-ftype, but it imports define-ftype from (chezscheme), and no library under src/ may export a name it imports from [cut: 668 more characters]
  actual:   (0 "check-seam: the seam holds (4 libraries in 4 files checked)\n" "")
FAIL layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order
  expected: (curl-version-info-data)
  actual:   (curl-version-info-data define-ftype)
FAIL layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted
  expected: ()
  actual:   ((export curl-version-info-data define-ftype))
test: FAIL tests/test-constants.sps (exit 1)
direct: test-constants exit 1
(strlen-of-hello 5)
```
(12 more such lines cut.)

### RED-P2. the reviewer's P2 tree: a macro in layouts applies `define-ftype` passed as an argument, `(apply-head define-ftype strlen-t (function (string) size_t))`

**Guards:** the body rule, the export rule and the stray rule.

**Base:** the tree with the new tests, `tests/check-seam.sps` as it was before these fixes.

**Added:** `call.sps`, the reviewer's caller, at the copy's root.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data strlen-t)
   (import (curl private require-threaded)
...
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-syntax apply-head (syntax-rules () ((_ k n t) (k n t))))
+  (apply-head define-ftype strlen-t (function (string) size_t)))
```

**Mutation:** In `src/curl/private/sneak.sls`:

```diff
+#!r6rs
+(library (curl private sneak)
+  (export sneak-strlen)
+  (import (curl private require-threaded)
+          (rnrs)
+          (curl private layouts)
+          (only (chezscheme) make-ftype-pointer ftype-ref))
+  (define (sneak-strlen s)
+    ((ftype-ref strlen-t () (make-ftype-pointer strlen-t "strlen")) s)))
```

**Command** in the container: `make test`, then `tests/test-constants.sps` run directly, then the reviewer's caller, `call.sps`, which loads libc and calls `sneak-strlen` on `"hello"`.

**Result:** killed, exit 2:

```
FAIL layouts.sls's body is define-ftype forms alone: no define, define-syntax, begin, macro use or other form
  expected: ()
  actual:   ((define-syntax apply-head (syntax-rules () ((_ k n t) (k n t)))) (apply-head define-ftype strlen-t (function (string) size_t)))
FAIL layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order
  expected: (curl-version-info-data)
  actual:   (curl-version-info-data strlen-t)
FAIL layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted
  expected: ()
  actual:   ((apply-head define-ftype strlen-t (function (string) size_t)))
test: FAIL tests/test-constants.sps (exit 1)
direct: test-constants exit 1
(strlen-of-hello 5)
```
(18 more such lines cut.)

### RED-P3. the reviewer's P3 tree: layouts exports `def-layout`, a macro whose template expands to `define-ftype`; sneak uses it

**Guards:** the body rule, the export rule and the stray rule.

**Base:** the tree with the new tests, `tests/check-seam.sps` as it was before these fixes.

**Added:** `call.sps`, the reviewer's caller, at the copy's root.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data def-layout)
   (import (curl private require-threaded)
...
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-syntax apply-head (syntax-rules () ((_ k n t) (k n t))))
+  (define-syntax def-layout (syntax-rules () ((_ n t) (apply-head define-ftype n t)))))
```

**Mutation:** In `src/curl/private/sneak.sls`:

```diff
+#!r6rs
+(library (curl private sneak)
+  (export sneak-strlen)
+  (import (curl private require-threaded)
+          (rnrs)
+          (curl private layouts)
+          (only (chezscheme) make-ftype-pointer ftype-ref))
+  (def-layout strlen-t (function (string) size_t))
+  (define (sneak-strlen s)
+    ((ftype-ref strlen-t () (make-ftype-pointer strlen-t "strlen")) s)))
```

**Command** in the container: `make test`, then `tests/test-constants.sps` run directly, then the reviewer's caller, `call.sps`, which loads libc and calls `sneak-strlen` on `"hello"`.

**Result:** killed, exit 2:

```
FAIL layouts.sls's body is define-ftype forms alone: no define, define-syntax, begin, macro use or other form
  expected: ()
  actual:   ((define-syntax apply-head (syntax-rules () ((_ k n t) (k n t)))) (define-syntax def-layout (syntax-rules () ((_ n t) (apply-head define-ftype n t)))))
FAIL layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order
  expected: (curl-version-info-data)
  actual:   (curl-version-info-data def-layout)
FAIL layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted
  expected: ()
  actual:   ((define-syntax def-layout (syntax-rules () ((_ n t) (apply-head define-ftype n t)))))
test: FAIL tests/test-constants.sps (exit 1)
direct: test-constants exit 1
(strlen-of-hello 5)
```
(18 more such lines cut.)

**G1, rule (g) written.** `make test` exited 0:

```
check-seam: the seam holds (10 libraries in 10 files checked)
# of expected passes      50
test: pass tests/test-check-seam.sps
# of expected passes      102
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
```
(22 more lines cut: the other suites' counts and `test: pass` lines.)

### The findings, reproduced on the suites as they were

Each finding was reproduced before its fix was trusted. On the old base, `make test` passes the reviewer's three trees, and each of them calls `strlen`. It also passes rule (f) widened to a library no test holds to a shape, a `uptr` for C's `long`, a free-text prefix that is another C expression of the same values, and an alias that changes nothing.

### OLD-P1. P1 on the suites as they were

**Guards:** finding: the old suites pass P1, and strlen is called.

**Base:** the suites as they were before these fixes: `tests/test-constants.sps`, `tests/check-seam.sps` and `tests/test-check-seam.sps` replaced by the copies kept before editing, and the three new fixture trees removed.

**Added:** `call.sps`, the reviewer's caller, at the copy's root.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data define-ftype)
   (import (curl private require-threaded)
```

**Mutation:** In `src/curl/private/sneak.sls`:

```diff
+#!r6rs
+(library (curl private sneak)
+  (export sneak-strlen)
+  (import (curl private require-threaded)
+          (rnrs)
+          (curl private layouts)
+          (only (chezscheme) make-ftype-pointer ftype-ref))
+  (define-ftype strlen-t (function (string) size_t))
+  (define (sneak-strlen s)
+    ((ftype-ref strlen-t () (make-ftype-pointer strlen-t "strlen")) s)))
```

**Command** in the container: `make test`, then `tests/test-constants.sps` run directly, then the reviewer's caller, `call.sps`, which loads libc and calls `sneak-strlen` on `"hello"`.

**Result:** as expected, exit 0:

```
# of expected passes      95
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
direct: test-constants exit 0
(strlen-of-hello 5)
```
(2 more such lines cut.)

### OLD-P2. P2 on the suites as they were

**Guards:** finding: the old suites pass P2, and strlen is called.

**Base:** the suites as they were before these fixes: `tests/test-constants.sps`, `tests/check-seam.sps` and `tests/test-check-seam.sps` replaced by the copies kept before editing, and the three new fixture trees removed.

**Added:** `call.sps`, the reviewer's caller, at the copy's root.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data strlen-t)
   (import (curl private require-threaded)
...
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-syntax apply-head (syntax-rules () ((_ k n t) (k n t))))
+  (apply-head define-ftype strlen-t (function (string) size_t)))
```

**Mutation:** In `src/curl/private/sneak.sls`:

```diff
+#!r6rs
+(library (curl private sneak)
+  (export sneak-strlen)
+  (import (curl private require-threaded)
+          (rnrs)
+          (curl private layouts)
+          (only (chezscheme) make-ftype-pointer ftype-ref))
+  (define (sneak-strlen s)
+    ((ftype-ref strlen-t () (make-ftype-pointer strlen-t "strlen")) s)))
```

**Command** in the container: `make test`, then `tests/test-constants.sps` run directly, then the reviewer's caller, `call.sps`, which loads libc and calls `sneak-strlen` on `"hello"`.

**Result:** as expected, exit 0:

```
# of expected passes      95
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
direct: test-constants exit 0
(strlen-of-hello 5)
```
(2 more such lines cut.)

### OLD-P3. P3 on the suites as they were

**Guards:** finding: the old suites pass P3, and strlen is called.

**Base:** the suites as they were before these fixes: `tests/test-constants.sps`, `tests/check-seam.sps` and `tests/test-check-seam.sps` replaced by the copies kept before editing, and the three new fixture trees removed.

**Added:** `call.sps`, the reviewer's caller, at the copy's root.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data def-layout)
   (import (curl private require-threaded)
...
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-syntax apply-head (syntax-rules () ((_ k n t) (k n t))))
+  (define-syntax def-layout (syntax-rules () ((_ n t) (apply-head define-ftype n t)))))
```

**Mutation:** In `src/curl/private/sneak.sls`:

```diff
+#!r6rs
+(library (curl private sneak)
+  (export sneak-strlen)
+  (import (curl private require-threaded)
+          (rnrs)
+          (curl private layouts)
+          (only (chezscheme) make-ftype-pointer ftype-ref))
+  (def-layout strlen-t (function (string) size_t))
+  (define (sneak-strlen s)
+    ((ftype-ref strlen-t () (make-ftype-pointer strlen-t "strlen")) s)))
```

**Command** in the container: `make test`, then `tests/test-constants.sps` run directly, then the reviewer's caller, `call.sps`, which loads libc and calls `sneak-strlen` on `"hello"`.

**Result:** as expected, exit 0:

```
# of expected passes      95
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
direct: test-constants exit 0
(strlen-of-hello 5)
```
(2 more such lines cut.)

### OLD-P8. P8 on the suites as they were

**Guards:** finding: the old suites pass rule (f) widened to a library no test holds to a shape.

**Base:** the suites as they were before these fixes: `tests/test-constants.sps`, `tests/check-seam.sps` and `tests/test-check-seam.sps` replaced by the copies kept before editing, and the three new fixture trees removed.

**Mutation:** In `src/curl/private/native.sls`:

```diff
           (rnrs)
-          (only (chezscheme) ftype-ref make-ftype-pointer
+          (only (chezscheme) define-ftype ftype-ref make-ftype-pointer
                 foreign-procedure foreign-entry? load-shared-object
```

**Mutation:** In `tests/check-seam.sps`:

```diff
 (define library-only-chez-names
-  '((define-ftype (curl private layouts))))
+  '((define-ftype (curl private layouts) (curl private native))))
 
```

**Mutation:** In `tests/test-check-seam.sps`:

```diff
                   (string-append (at "ftype-elsewhere" "curl/f.sls") ": (curl f) "
-                                 (library-only "define-ftype" "(curl private layouts)"))
+                                 (library-only "define-ftype" "(curl private layouts), (curl private native)"))
                   (string-append (at "ftype-elsewhere" "curl/layouts.sls") ": (curl layouts) "
-                                 (library-only "define-ftype" "(curl private layouts)"))
+                                 (library-only "define-ftype" "(curl private layouts), (curl private native)"))
                   (string-append (at "ftype-elsewhere" "curl/private/layouts-extra.sls")
                                  ": (curl private layouts extra) "
-                                 (library-only "define-ftype" "(curl private layouts)"))
+                                 (library-only "define-ftype" "(curl private layouts), (curl private native)"))
                   (string-append (at "ftype-elsewhere" "http-client/h.sls") ": (http-client h) "
-                                 (library-only "define-ftype" "(curl private layouts)"))))
+                                 (library-only "define-ftype" "(curl private layouts), (curl private native)"))))
    (list "ftype-with-unlisted"
...
[4 more lines cut]
```

**Result:** as expected, exit 0:

```
test: pass tests/test-check-seam.sps
# of expected passes      95
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
```

### OLD-K1. K1 on the suites as they were

**Guards:** finding: the old kind map passes a `uptr` for C's `long`.

**Base:** the suites as they were before these fixes: `tests/test-constants.sps`, `tests/check-seam.sps` and `tests/test-check-seam.sps` replaced by the copies kept before editing, and the three new fixture trees removed.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (ssl-version uptr)
-      (ssl-version-num long)
+      (ssl-version-num uptr)
       (libz-version uptr)
```

**Result:** as expected, exit 0:

```
# of expected passes      95
test: pass tests/test-constants.sps
```

### OLD-E1. E1 on the suites as they were

**Guards:** finding: the old suite passes a free-text prefix that is another C expression of the same values.

**Base:** the suites as they were before these fixes: `tests/test-constants.sps`, `tests/check-seam.sps` and `tests/test-check-seam.sps` replaced by the copies kept before editing, and the three new fixture trees removed.

**Mutation:** In `tests/test-constants.sps`:

```diff
 (define constant-rows
-  '((curl-version-features . (each "CURL_VERSION_"))
+  '((curl-version-features . (each "0|CURL_VERSION_"))
     (curl-version-ssl . "CURL_VERSION_SSL")
```

**Result:** as expected, exit 0:

```
# of expected passes      95
test: pass tests/test-constants.sps
```

### OLD-E2. E2 on the suites as they were

**Guards:** finding: the old suite passes an alias that changes nothing.

**Base:** the suites as they were before these fixes: `tests/test-constants.sps`, `tests/check-seam.sps` and `tests/test-check-seam.sps` replaced by the copies kept before editing, and the three new fixture trees removed.

**Mutation:** In `tests/test-constants.sps`:

```diff
 ;; text can name any constant whose value happens to match.
-(define c-name-aliases '())
+(define c-name-aliases '((curlh-header . "CURLH_HEADER")))
 
```

**Result:** as expected, exit 0:

```
# of expected passes      95
test: pass tests/test-constants.sps
```

### Mutations

22 cases ran on the fixed tree. The 21 meant to fail were each killed, with every expected line present. E1b is meant to pass, and did, with the expected pass count. check-seam stopped `make test` before any suite in P1, P6, D2, X1, X2. Only two cases failed `test-check-seam`: X3, whose suite it is, and N1, whose versioned name the exactness test does not find in rule (f)'s entry. No other suite failed. Suites that failed, by case: `test-check-seam` under N1, X3.

### P1. the reviewer's P1 tree

**Guards:** rule (g) stops make test; the export and stray rules name it too.

**Added:** `call.sps`, the reviewer's caller, at the copy's root.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data define-ftype)
   (import (curl private require-threaded)
```

**Mutation:** In `src/curl/private/sneak.sls`:

```diff
+#!r6rs
+(library (curl private sneak)
+  (export sneak-strlen)
+  (import (curl private require-threaded)
+          (rnrs)
+          (curl private layouts)
+          (only (chezscheme) make-ftype-pointer ftype-ref))
+  (define-ftype strlen-t (function (string) size_t))
+  (define (sneak-strlen s)
+    ((ftype-ref strlen-t () (make-ftype-pointer strlen-t "strlen")) s)))
```

**Command** in the container: `make test`, then `tests/test-constants.sps` run directly.

**Result:** killed, exit 2:

```
check-seam: src/curl/private/layouts.sls: (curl private layouts) exports define-ftype, but it imports define-ftype from (chezscheme), and no library under src/ may export a name it imports from (chezscheme)
check-seam: FAILED (problems: 1)
make: *** [Makefile:238: check-seam] Error 1
FAIL layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order
  expected: (curl-version-info-data)
  actual:   (curl-version-info-data define-ftype)
FAIL layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted
  expected: ()
  actual:   ((export curl-version-info-data define-ftype))
direct: test-constants exit 1
```

### P2. the reviewer's P2 tree

**Guards:** the body, export and stray rules; check-seam passes it.

**Added:** `call.sps`, the reviewer's caller, at the copy's root.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data strlen-t)
   (import (curl private require-threaded)
...
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-syntax apply-head (syntax-rules () ((_ k n t) (k n t))))
+  (apply-head define-ftype strlen-t (function (string) size_t)))
```

**Mutation:** In `src/curl/private/sneak.sls`:

```diff
+#!r6rs
+(library (curl private sneak)
+  (export sneak-strlen)
+  (import (curl private require-threaded)
+          (rnrs)
+          (curl private layouts)
+          (only (chezscheme) make-ftype-pointer ftype-ref))
+  (define (sneak-strlen s)
+    ((ftype-ref strlen-t () (make-ftype-pointer strlen-t "strlen")) s)))
```

**Result:** killed, exit 2:

```
FAIL layouts.sls's body is define-ftype forms alone: no define, define-syntax, begin, macro use or other form
  expected: ()
  actual:   ((define-syntax apply-head (syntax-rules () ((_ k n t) (k n t)))) (apply-head define-ftype strlen-t (function (string) size_t)))
FAIL layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order
  expected: (curl-version-info-data)
  actual:   (curl-version-info-data strlen-t)
FAIL layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted
  expected: ()
  actual:   ((apply-head define-ftype strlen-t (function (string) size_t)))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### P3. the reviewer's P3 tree

**Guards:** the body, export and stray rules; check-seam passes it.

**Added:** `call.sps`, the reviewer's caller, at the copy's root.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data def-layout)
   (import (curl private require-threaded)
...
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define-syntax apply-head (syntax-rules () ((_ k n t) (k n t))))
+  (define-syntax def-layout (syntax-rules () ((_ n t) (apply-head define-ftype n t)))))
```

**Mutation:** In `src/curl/private/sneak.sls`:

```diff
+#!r6rs
+(library (curl private sneak)
+  (export sneak-strlen)
+  (import (curl private require-threaded)
+          (rnrs)
+          (curl private layouts)
+          (only (chezscheme) make-ftype-pointer ftype-ref))
+  (def-layout strlen-t (function (string) size_t))
+  (define (sneak-strlen s)
+    ((ftype-ref strlen-t () (make-ftype-pointer strlen-t "strlen")) s)))
```

**Result:** killed, exit 2:

```
FAIL layouts.sls's body is define-ftype forms alone: no define, define-syntax, begin, macro use or other form
  expected: ()
  actual:   ((define-syntax apply-head (syntax-rules () ((_ k n t) (k n t)))) (define-syntax def-layout (syntax-rules () ((_ n t) (apply-head define-ftype n t)))))
FAIL layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order
  expected: (curl-version-info-data)
  actual:   (curl-version-info-data def-layout)
FAIL layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted
  expected: ()
  actual:   ((define-syntax def-layout (syntax-rules () ((_ n t) (apply-head define-ftype n t)))))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### P4. a `begin` in layouts wrapping a function ftype, not exported

**Guards:** the body rule and the stray rule; the nested form fails its shape and coverage tests.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (begin (define-ftype strlen-t (function (string) size_t))))
```

**Result:** killed, exit 2:

```
FAIL layouts.sls's body is define-ftype forms alone: no define, define-syntax, begin, macro use or other form
  expected: ()
  actual:   ((begin (define-ftype strlen-t (function (string) size_t))))
FAIL layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted
  expected: ()
  actual:   ((begin (define-ftype strlen-t (function (string) size_t))))
FAIL layouts.sls: strlen-t is a struct of primitive-typed fields, each type in field-kinds
  expected: handled
  actual:   (unhandled (function (string) size_t))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```
(3 more such lines cut.)

### P5. `'define-ftype` quoted in layouts' body, where `datum->syntax` could make it a binding

**Guards:** the stray rule, quoted ones counted; the body rule.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (hyper-version uptr)
-      (gsasl-version uptr))))
+      (gsasl-version uptr)))
+
+  (define marker 'define-ftype))
```

**Result:** killed, exit 2:

```
FAIL layouts.sls's body is define-ftype forms alone: no define, define-syntax, begin, macro use or other form
  expected: ()
  actual:   ((define marker (quote define-ftype)))
FAIL layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted
  expected: ()
  actual:   ((define marker (quote define-ftype)))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### P6. layouts imports `(prefix (only (chezscheme) define-ftype) x:)`, its ftype written `x:define-ftype`

**Guards:** rule (c) stops make test; the import, body and stray rules name it too.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
           (rnrs)
-          (only (chezscheme) define-ftype))
+          (prefix (only (chezscheme) define-ftype) x:))
 
...
   ;; takes a natural number.
-  (define-ftype curl-version-info-data
+  (x:define-ftype curl-version-info-data
     (struct
```

**Command** in the container: `make test`, then `tests/test-constants.sps` run directly.

**Result:** killed, exit 2:

```
check-seam: src/curl/private/layouts.sls: (curl private layouts) imports (prefix (only (chezscheme) define-ftype) x:), but (chezscheme), and its alias (scheme), may be imported only as (only (chezscheme) name ...)
make: *** [Makefile:238: check-seam] Error 1
FAIL layouts.sls imports exactly (curl private require-threaded), (rnrs) and (only (chezscheme) define-ftype), in order, none wrapped
  expected: ((curl private require-threaded) (rnrs) (only (chezscheme) define-ftype))
  actual:   ((curl private require-threaded) (rnrs) (prefix (only (chezscheme) define-ftype) x:))
FAIL layouts.sls's body is define-ftype forms alone: no define, define-syntax, begin, macro use or other form
  expected: ()
  actual:   ((x:define-ftype curl-version-info-data (struct (age int) (version uptr) (version-num unsigned-int) (host uptr) (features unsigned-int) (ssl-version uptr) (ssl-version-num long) (libz-version uptr) (protocols uptr) (ares uptr) ( [cut: 316 more characters]
FAIL layouts.sls holds define-ftype only in its (only (chezscheme) ...) import and at its body forms' heads, quoted ones counted
  expected: ()
  actual:   ((prefix (only (chezscheme) define-ftype) x:))
direct: test-constants exit 1
```
(13 more such lines cut.)

### P7. layouts exports `car`, an export that is no ftype

**Guards:** the export rule.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data car)
   (import (curl private require-threaded)
```

**Result:** killed, exit 2:

```
FAIL layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order
  expected: (curl-version-info-data)
  actual:   (car curl-version-info-data)
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### P7b. layouts exports its ftype a second time, through a rename spec

**Guards:** the export rule: plain identifiers only.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 (library (curl private layouts)
-  (export curl-version-info-data)
+  (export curl-version-info-data (rename (curl-version-info-data version-info)))
   (import (curl private require-threaded)
```

**Result:** killed, exit 2:

```
FAIL layouts.sls exports exactly the names its define-ftype forms define, each a plain identifier, in any order
  expected: (curl-version-info-data)
  actual:   (not-identifiers ((rename (curl-version-info-data version-info))))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### P8. rule (f)'s entry widened to `(curl private native)`, native importing `define-ftype`, and test-check-seam's rows for rule (f) given the widened list's words, as a reviewed widening would

**Guards:** rule (f)'s entry, read as data; check-seam and test-check-seam, its exactness tests among them, pass it.

**Mutation:** In `src/curl/private/native.sls`:

```diff
           (rnrs)
-          (only (chezscheme) ftype-ref make-ftype-pointer
+          (only (chezscheme) define-ftype ftype-ref make-ftype-pointer
                 foreign-procedure foreign-entry? load-shared-object
```

**Mutation:** In `tests/check-seam.sps`:

```diff
 (define library-only-chez-names
-  '((define-ftype (curl private layouts))))
+  '((define-ftype (curl private layouts) (curl private native))))
 
```

**Mutation:** In `tests/test-check-seam.sps`:

```diff
                   (string-append (at "ftype-elsewhere" "curl/f.sls") ": (curl f) "
-                                 (library-only "define-ftype" "(curl private layouts)"))
+                                 (library-only "define-ftype" "(curl private layouts), (curl private native)"))
                   (string-append (at "ftype-elsewhere" "curl/layouts.sls") ": (curl layouts) "
-                                 (library-only "define-ftype" "(curl private layouts)"))
+                                 (library-only "define-ftype" "(curl private layouts), (curl private native)"))
                   (string-append (at "ftype-elsewhere" "curl/private/layouts-extra.sls")
                                  ": (curl private layouts extra) "
-                                 (library-only "define-ftype" "(curl private layouts)"))
+                                 (library-only "define-ftype" "(curl private layouts), (curl private native)"))
                   (string-append (at "ftype-elsewhere" "http-client/h.sls") ": (http-client h) "
-                                 (library-only "define-ftype" "(curl private layouts)"))))
+                                 (library-only "define-ftype" "(curl private layouts), (curl private native)"))))
    (list "ftype-with-unlisted"
...
[4 more lines cut]
```

**Result:** killed, exit 2:

```
test: pass tests/test-check-seam.sps
FAIL tests/check-seam.sps's library-only-chez-names lets (curl private layouts) alone import define-ftype
  expected: (define-ftype (curl private layouts))
  actual:   (define-ftype (curl private layouts) (curl private native))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### N1. layouts's library name given a version, `(curl private layouts (1))`, which an import of `(curl private layouts)` still finds

**Guards:** layouts.sls is the library rule (f) names, exactly.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
 ;;; through ftype pointers.
-(library (curl private layouts)
+(library (curl private layouts (1))
   (export curl-version-info-data)
```

**Result:** killed, exit 2:

```
FAIL each library-only-chez-names entry lists exactly the libraries under src/ that import its name
  expected: ((define-ftype (curl private layouts (1))))
  actual:   ((define-ftype (curl private layouts)))
test: FAIL tests/test-check-seam.sps (exit 1)
FAIL layouts.sls is the library (curl private layouts), the one rule (f) names
  expected: (curl private layouts)
  actual:   (curl private layouts (1))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### D1. a second library form in layouts.sls, after the first

**Guards:** layouts.sls is one datum.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (gsasl-version uptr))))
+
+(library (curl private layouts-b) (export) (import (rnrs)))
```

**Result:** killed, exit 2:

```
FAIL layouts.sls is read: one datum, a library with a define-ftype, at least one
  expected: read
  actual:   (data-count 2)
FAIL layouts.sls is the library (curl private layouts), the one rule (f) names
  expected: (curl private layouts)
  actual:   (no-library (data-count 2))
FAIL layouts.sls imports exactly (curl private require-threaded), (rnrs) and (only (chezscheme) define-ftype), in order, none wrapped
  expected: ((curl private require-threaded) (rnrs) (only (chezscheme) define-ftype))
  actual:   (no-library (data-count 2))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```
(15 more such lines cut.)

### D2. an `#!eof` literal after layouts' library form, text after it, and the `#!r6rs` line dropped, since that mode refuses `#!eof`

**Guards:** layouts.sls is read to its end.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
-#!r6rs
 ;;; (curl private layouts): the C structs Scheme reads, each a define-ftype
...
       (gsasl-version uptr))))
+#!eof
+(text the reader never reaches)
```

**Command** in the container: `make test`, then `tests/test-constants.sps` run directly.

**Result:** killed, exit 2:

```
check-seam: src/curl/private/layouts.sls: it cannot be read as data: Exception in read: an #!eof literal ends the reading before the end of the file
make: *** [Makefile:238: check-seam] Error 1
FAIL layouts.sls is read: one datum, a library with a define-ftype, at least one
  expected: read
  actual:   (eof-literal "src/curl/private/layouts.sls")
FAIL layouts.sls is the library (curl private layouts), the one rule (f) names
  expected: (curl private layouts)
  actual:   (no-library (eof-literal "src/curl/private/layouts.sls"))
FAIL layouts.sls imports exactly (curl private require-threaded), (rnrs) and (only (chezscheme) define-ftype), in order, none wrapped
  expected: ((curl private require-threaded) (rnrs) (only (chezscheme) define-ftype))
  actual:   (no-library (eof-literal "src/curl/private/layouts.sls"))
direct: test-constants exit 1
```
(16 more such lines cut.)

### X1. `(curl)` imports `(only (chezscheme) format)` and exports `format`

**Guards:** rule (g), a plain export.

**Mutation:** In `src/curl.sls`:

```diff
    loaded-libcurl
+   format
 
...
           (rnrs)
+          (only (chezscheme) format)
           (curl private conditions)
```

**Result:** killed, exit 2:

```
check-seam: src/curl.sls: (curl) exports format, but it imports format from (chezscheme), and no library under src/ may export a name it imports from (chezscheme)
check-seam: FAILED (problems: 1)
make: *** [Makefile:238: check-seam] Error 1
```

### X2. X1 through a rename export spec, `(rename (format curl-format))`

**Guards:** rule (g), a rename spec's internal name.

**Mutation:** In `src/curl.sls`:

```diff
    loaded-libcurl
+   (rename (format curl-format))
 
...
           (rnrs)
+          (only (chezscheme) format)
           (curl private conditions)
```

**Result:** killed, exit 2:

```
check-seam: src/curl.sls: (curl) exports format as curl-format, but it imports format from (chezscheme), and no library under src/ may export a name it imports from (chezscheme)
check-seam: FAILED (problems: 1)
make: *** [Makefile:238: check-seam] Error 1
```

### X3. check-seam's rule (g) tests a rename spec's external name, not its internal one

**Guards:** test-check-seam's export-chez row tells the two apart.

**Mutation:** In `tests/check-seam.sps`:

```diff
                                (map (lambda (pair)
-                                      (if (memq (car pair) chez)
+                                      (if (memq (cdr pair) chez)
                                           (list (string-append
```

**Result:** killed, exit 2:

```
FAIL export-chez: rule (g): a name imported from (chezscheme) exported, plain or as a rename spec's internal name, in either family, each in export order; a name from (rnrs), a rename of a library's own definition to a (chezscheme) name, an [cut: 62 more characters]
  expected: (1 "" "check-seam: tests/fixtures/seam/export-chez/curl/private/layouts.sls: (curl private layouts) exports define-ftype, but it imports define-ftype from (chezscheme), and no library under src/ may export a name it imports from [cut: 668 more characters]
  actual:   (1 "" "check-seam: tests/fixtures/seam/export-chez/curl/ok.sls: (curl ok) exports my-format as format, but it imports my-format from (chezscheme), and no library under src/ may export a name it imports from (chezscheme)\ncheck-s [cut: 671 more characters]
test: FAIL tests/test-check-seam.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### K1. `(ssl-version-num uptr)`, C's `long`

**Guards:** uptr lays out a pointer alone: offset and size both still match.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (ssl-version uptr)
-      (ssl-version-num long)
+      (ssl-version-num uptr)
       (libz-version uptr)
```

**Result:** killed, exit 2:

```
FAIL curl_version_info_data.ssl_version_num has the header's offset, size and kind
  expected: (offset 48 size 8 kind integer)
  actual:   (offset 48 size 8 kind (uptr may-be (other)))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### K2. `(capath iptr)`, C's `char *`

**Guards:** iptr lays out an integer alone.

**Mutation:** In `src/curl/private/layouts.sls`:

```diff
       (cainfo uptr)
-      (capath uptr)
+      (capath iptr)
       (zstd-ver-num unsigned-int)
```

**Result:** killed, exit 2:

```
FAIL curl_version_info_data.capath has the header's offset, size and kind
  expected: (offset 160 size 8 kind other)
  actual:   (offset 160 size 8 kind (iptr may-be (integer)))
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### E1. an each row with a wrong prefix, `(each "0|CURL_VERSION_")`, whose every C expression has the right value

**Guards:** an each row's prefix is derived from its name.

**Mutation:** In `tests/test-constants.sps`:

```diff
 (define constant-rows
-  '((curl-version-features . (each "CURL_VERSION_"))
+  '((curl-version-features . (each "0|CURL_VERSION_"))
     (curl-version-ssl . "CURL_VERSION_SSL")
```

**Result:** killed, exit 2:

```
FAIL constant-rows' row curl-version-features has the prefix CURL_VERSION_, its name less its last word, upcased, - as _, then _
  expected: "CURL_VERSION_"
  actual:   "0|CURL_VERSION_"
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### E1b. E1, excused by a c-name-aliases entry `(curl-version-features . "0|CURL_VERSION_")`

**Guards:** the exception works: an alias names the prefix its row must name. Expected to pass, with 103 tests.

**Mutation:** In `tests/test-constants.sps`:

```diff
 (define constant-rows
-  '((curl-version-features . (each "CURL_VERSION_"))
+  '((curl-version-features . (each "0|CURL_VERSION_"))
     (curl-version-ssl . "CURL_VERSION_SSL")
...
 ;; expression.
-(define c-name-aliases '())
+(define c-name-aliases '((curl-version-features . "0|CURL_VERSION_")))
 
```

**Result:** as expected, exit 0:

```
# of expected passes      103
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
```

### E2. a stale alias, `(curlh-header . "CURLH_HEADER")`, which changes nothing

**Guards:** every alias changes what its row derives.

**Mutation:** In `tests/test-constants.sps`:

```diff
 ;; expression.
-(define c-name-aliases '())
+(define c-name-aliases '((curlh-header . "CURLH_HEADER")))
 
```

**Result:** killed, exit 2:

```
FAIL c-name-aliases' entry (curlh-header . "CURLH_HEADER") is its row's one alias, and changes what the row's name derives
  expected: changes
  actual:   (derived-already "CURLH_HEADER")
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### E2b. an alias for no row, `(curl-nothing . "CURL_NOTHING")`

**Guards:** every alias names a row.

**Mutation:** In `tests/test-constants.sps`:

```diff
 ;; expression.
-(define c-name-aliases '())
+(define c-name-aliases '((curl-nothing . "CURL_NOTHING")))
 
```

**Result:** killed, exit 2:

```
FAIL c-name-aliases' entry (curl-nothing . "CURL_NOTHING") is its row's one alias, and changes what the row's name derives
  expected: changes
  actual:   no-such-row
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### E2c. two aliases for one row: `(curlh-header . "CURL_VERSION_IPV6")`, which its row names, then `(curlh-header . "CURLH_HEADER")`

**Guards:** an alias shadowed by an earlier one for its row is stale.

**Mutation:** In `tests/test-constants.sps`:

```diff
     (curlhe-not-built-in . "CURLHE_NOT_BUILT_IN")
-    (curlh-header . "CURLH_HEADER")
+    (curlh-header . "CURL_VERSION_IPV6")
     (curl-global-default . "CURL_GLOBAL_DEFAULT")
...
 ;; expression.
-(define c-name-aliases '())
+(define c-name-aliases '((curlh-header . "CURL_VERSION_IPV6") (curlh-header . "CURLH_HEADER")))
 
```

**Result:** killed, exit 2:

```
FAIL c-name-aliases' entry (curlh-header . "CURLH_HEADER") is its row's one alias, and changes what the row's name derives
  expected: changes
  actual:   not-its-rows-first-entry
test: FAIL tests/test-constants.sps (exit 1)
make: *** [Makefile:192: test] Error 1
```

### Clean rerun

After every case, on the working tree itself: `make test`, `make check-test-fails` and `make check-help`, each exiting 0:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (13 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org states the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
# of expected passes      50
test: pass tests/test-check-seam.sps
# of expected passes      102
test: pass tests/test-constants.sps
test: ran 13, passed 13, failed 0, hung 0
check-test-fails: make test failed, as it must, in all 10 cases
check-test-fails exit 0
check-help exit 0
```
(30 more lines cut: the other suites' counts and `test: pass` lines, and check-test-fails' case lines.)
