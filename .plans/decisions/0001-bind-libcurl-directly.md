# ADR-0001: Bind libcurl directly, with no C shim; the floor is Chez 10.4.0, threaded

- **Status:** Accepted; amended 2026-10-16 with what M0 slices 3 to 5 built
  ([slice 3](#amendment-2026-10-16-what-slice-3-built),
  [slice 4](#amendment-2026-10-16-what-slice-4-built),
  [slice 5](#amendment-2026-10-16-the-non-threaded-check-m0-slice-5),
  [bytevector copies](#amendment-2026-10-16-bytevector-copies-go-through-one-checked-wrapper-m0-slice-5));
  amended 2026-10-17 with [what slice 6 built](#amendment-2026-10-17-the-variadic-bindings-m0-slice-6);
  amended 2026-10-23 with [what M2 slice 1 built](#amendment-2026-10-23-the-checked-copies-and-the-carried-checks-m2-slice-1)
- **Date:** 2026-10-04
- **Scope:** chez-curl v1
- **Settles:** D6. That decision was raised on 2026-10-04, after the brief was written.
- **Supersedes:** the brief's §2 item 6, its §4, and its "a C shim of our own" dependency.
- **Related:** [project brief](../2026-09-20-chez-curl-project-brief.md) §2, §4, §9 risk 5 ·
  chez-libuv ADR-0002 (a constants-only shim) and ADR-0005 (constants are never
  transcribed) · chez-cmark-gfm ADR-0015 (it deleted its shim) and ADR-0016 (bind the
  version check first)

## Context

The brief settles on a C shim with three jobs (§4):

1. Typed wrappers for the variadic `curl_easy_setopt` and `curl_easy_getinfo`, "which
   Chez's `foreign-procedure` cannot express".
2. A name-keyed constant table, so that "values are never hard-coded in Scheme".
3. Field offsets for `CURLMsg` and `curl_waitfd`.

**Job 1's premise has been false since Chez 10.0.0.** That release added the `__varargs`
and `(__varargs_after n)` conventions (release notes, "Foreign interface extensions
(10.0.0)"). The user guide at v9.5.8 and v9.6.4 has neither. We measured both on this
repository's development host (Chez 10.4.0 ta6le, libcurl 8.20.0 with GnuTLS):

- **The variadic binding works.** `curl_easy_setopt`, bound as
  `(foreign-procedure (__varargs_after 2) "curl_easy_setopt" (uptr int string) int)`,
  set `CURLOPT_URL`. A `long` twin set `CURLOPT_VERBOSE`. Both returned `CURLE_OK`.
- **The collect-safe call works.** `curl_easy_perform`, declared `__collect_safe`, then
  returned `CURLE_UNSUPPORTED_PROTOCOL` for `nosuchproto://x`, the expected result.

That measurement proves little on its own. On x86-64, integer and pointer varargs travel
in the same registers as named arguments, so a binding with the annotation missing would
pass too. The ABI where it matters is Apple arm64, which passes variadic arguments on the
stack. Chez's own `mats/foreign.ms` exercises both conventions. Upstream CI builds and runs
those tests for `arm64osx` and `tarm64osx` on `macos-26`.

**With job 1 gone, the brief's shim would still wrap libcurl calls.** chez-libuv's
ADR-0002 rules that out for its own shim: it never exports "a function that itself calls
into libuv on the binding's behalf". So the real alternative was chez-libuv's
constants-only shim. What that shim earns in libuv does not arise here:

- **libuv's constants vary by platform, and Scheme must size the libuv structs it
  allocates** (`uv_loop_t`, `uv_tcp_t`, …). libcurl allocates every handle it gives out:
  `curl_easy_init`, `curl_multi_init`, `curl_url`, `curl_mime_init` and
  `curl_slist_append` all return opaque pointers. The enumerations this binding needs
  have no platform conditionals, and libcurl does not renumber them. The soname is still
  `libcurl.so.4` for both the Guix 8.20.0 and the Ubuntu 7.81.0 library on this host.
- **libcurl describes its own options.** `curl_easy_option_by_name` (`options.h`, 7.73.0)
  returns the id and value type of any option the loaded library knows. Measured:

  | Option | Id | Type |
  |---|---|---|
  | `URL` | 10002 | string |
  | `FOLLOWLOCATION` | 52 | long |
  | `WRITEFUNCTION` | 20011 | function |
  | `POSTFIELDSIZE_LARGE` | 30120 | off_t |
  | `CAINFO_BLOB` | 40309 | blob |
  | `NO_SUCH_OPTION` | — | returns NULL |

**The house has already recorded what a shim costs.**

- **chez-libuv's README:** `make build` "compiles the small C shim and generates
  config.sls" for each machine, and "a source-only install cannot work anywhere".
- **chez-cmark-gfm ADR-0015:** it deleted its shim because "something had to compile it".

For libcurl, every install would also need the `-dev` headers package.

## Decision

**chez-curl compiles no C.** `(curl ...)` binds libcurl with `foreign-procedure` and
nothing else.

1. **Variadic entry points are bound once per value type, with `(__varargs_after 2)`.**
   These are `curl_easy_setopt`, `curl_easy_getinfo`, `curl_multi_setopt` and
   `curl_share_setopt`.
2. **`CURLOPT_*` ids and value types come from the loaded library**, by name, through
   `curl_easy_option_by_name`.
   - Setopt refuses a value of the wrong type.
   - A name the loaded library does not know raises a condition that names it.
   - These values are never written in Scheme.
3. **Every other constant is a Scheme definition, checked against the real headers at test
   time.** This covers `CURLE_*`, `CURLINFO_*`, `CURLM_*`, `CURLMSG_*`, the
   `CURL_VERSION_*` bits, `CURL_HTTP_VERSION_*` and the pause and read sentinels. A test
   generates a C program from the Scheme table and compiles it against libcurl's headers.
   It fails naming every constant whose value differs.
4. **The structs Scheme reads are `define-ftype`s, checked by the same program** with
   `sizeof` and `offsetof`. They are `CURLMsg`, `struct curl_header`,
   `struct curl_easyoption` and `curl_version_info_data`.
   - `curl_waitfd` is not bound. `curl_multi_wakeup` (7.68) wakes `curl_multi_poll`
     without an extra descriptor.
   - If M3 finds it does need one, its layout gets the same check.
5. **Bulk byte moves use libc's `memcpy`, bound directly, as a plain call.**
   - **Why plain:** a call that is not `__collect_safe` keeps the thread active, so no
     collection can move a bytevector mid-copy (chez-libuv ADR-0002's amendment).
   - **It resolves:** `(foreign-entry? "memcpy")` is `#f` in a bare Chez and `#t` once
     libcurl is loaded.
   - **It works:** a 16 KiB copy from foreign memory into a bytevector, through a `u8*`
     argument, arrived intact.
6. **The floor is Chez 10.4.0, threaded.**
   - 10.0.0 brings `__varargs_after`.
   - 10.4.0 fixes a bug where "some signals raised in non-Scheme threads could cause a
     segmentation fault in the signal handler". libcurl's threaded resolver runs name
     lookups on non-Scheme threads, and this host's libcurl uses it (no c-ares).
   - 10.4.1 adds only a `logtest` fix for mixed fixnum/bignum arguments and a ppc32 fix.
     chez-libuv's 10.4.1 floor records no reason beyond being the version its spikes ran
     on, so this binding does not inherit it.
   - A non-threaded Chez is refused at import, by name.

### Rejected

- **A constants-only shim (chez-libuv ADR-0002's line).** It keeps ADR-0005 to the letter.
  But every install would need a C compiler, libcurl's `-dev` headers and a `make build`
  in each clone, and Akku would be ruled out. All of that would protect values that do
  not vary by platform, and decision 3 still checks them against the real headers.
- **The brief's shim (typed setopt and getinfo wrappers, plus constants and layouts).**
  - Its reason went away in Chez 10.0.0.
  - It wraps calls, which ADR-0002 excludes.
  - It costs as much as the constants-only shim.
  - Its one remaining advantage is not depending on Chez's varargs on Apple arm64. Upstream
    CI and the M2 test below cover that.

## Consequences

- **Install needs a threaded Chez ≥ 10.4.0 and a libcurl runtime package.** No compiler,
  no headers, no generated per-machine files. That keeps Akku possible; whether to publish
  there is not decided here.
- **CI cannot use apt's Chez.** Ubuntu 24.04 ships 9.5.8. CI builds the floor from the
  release tarball and caches it, as chez-libuv's `ci.yml` does.
- **The brief's "values are never hard-coded in Scheme" now holds for `CURLOPT_*` only.**
  For every other constant the guarantee becomes "drift fails a test", on the platforms
  where that test runs: Linux in CI, and macOS when the maintainer runs it. That is
  accepted because these enumerations have no platform conditionals, and libcurl's ABI
  promise is that they are never renumbered.
- **The C compiler and libcurl's headers become development dependencies.** Guix's curl
  package includes its headers; CI installs a `-dev` package. Without headers, the
  constants test fails rather than skips: an absent oracle is a failure, not an excuse
  (chez-cmark-gfm ADR-0015).
- **Apple arm64 is the only ABI where `__varargs_after` changes how arguments travel, and
  no CI here runs it.** M2's first FFI test therefore sets a string, a `long` and an
  `off_t` option through the variadic bindings and observes each one's effect in a real
  transfer. A broken varargs path then fails by name on the Mac. A green Linux run says
  nothing about this path.
- **Load order is the binding's job, not a linker's.** `foreign-procedure` resolves its
  entry point when evaluated (chez-cmark-gfm `traps.md`). So `curl_version_info` is bound
  and checked against the floor before any newer entry point, such as `curl_easy_header`
  (7.83). A too-old libcurl is then refused by name (brief §9 risk 5), not with
  `no entry for "curl_easy_header"`.
- **M0 has nothing to compile.** `make build` becomes a preflight that names the libcurl it
  loaded, with its version, features and TLS backend, as chez-cmark-gfm's does. How that
  libcurl is found is D7.

## Amendment, 2026-10-16: what slice 3 built

- **`curl_version_info` is called with `CURLVERSION_TENTH`.** That was `CURLVERSION_NOW`
  at the 7.85.0 floor, so a library at the floor fills every field the binding reads.
  `CURLVERSION_NOW` moves with the headers: it is `CURLVERSION_TWELFTH` in 8.20.0.
- **`curl_version_info_data` is a `define-ftype`** through `gsasl_version`, the last field
  that age fills. `features` is read as an unsigned int, since a bit 31 would make a C
  `int` negative. Slice 4's C program checks the offsets.
- **The Chez floor is checked as well as threads.** `(curl private require-threaded)`
  refuses, at expansion and by name, a Chez that is not threaded or is older than 10.4.0.
  A pre-release of 10.4.0 is refused too, since it precedes the release. The refusal
  imports only names an older Chez has: a missing name would fail with Chez's bare
  `missing import`, which the refusal exists to replace. Its suite expands copies of the
  refusal that answer as an older, pre-release or non-threaded Chez. By hand, Guix's
  Chez 10.2.0 was refused by name. A real non-threaded one is measured only by CI's
  non-threaded lane.

## Amendment, 2026-10-16: what slice 4 built

- **`tests/test-constants.sps` checks decisions 3 and 4.** It reads `constants.sls` and
  `layouts.sls` as data, and generates one C program from what it finds.
  - Every export of `(curl private constants)` has a row naming its C expression, and
    every row is an export. A missing side fails, naming it. `curl-version-features` is
    checked entry by entry: `ntlm-wb` is `CURL_VERSION_NTLM_WB`.
  - A row's C name is the export's name, upcased, with `-` as `_`. A list row's prefix is
    the export's name without its last word: `curl-version-features` gives
    `CURL_VERSION_`. A row may name something else only through an entry in
    `c-name-aliases`, which is empty now. An alias that changes nothing, or names no row,
    fails. Adding one is a reviewed change. Otherwise a row could name any constant that
    happens to have the same value.
  - The structs Scheme reads live in `(curl private layouts)`, which never loads libcurl.
    Each `define-ftype` has a row naming its C type, and each row is a `define-ftype`.
  - Each must be a struct of primitive-typed fields, each type one the suite's
    `field-kinds` maps. Any other shape fails by name, so `CURLMsg`'s `data` union, and a
    bit-field such as `curl_hstsentry`'s, will need the check extended when their slices
    add them.
- **Every field is checked by offset, size and kind,** not offsets alone as the slice 3
  amendment said.
  - An `int` written for `ssl_version_num`'s `long` kept every offset, since padding filled
    the gap, and only the size check failed. A `double` written for a pointer passed offset
    and size together, and only the kind check fails it.
  - The C side reports each member's kind with C11's `_Generic`: integer, floating, or
    other. `uptr` and `void*` must be other, `iptr` and the sized types integer, so an
    integer member is written `size_t` or `long`, never `uptr`. Signedness is not compared:
    `features` is `unsigned-int` against C's `int` on purpose.
  - "Other" covers pointers, arrays, structs and unions alike, so an array or aggregate the
    size of a pointer, written as `uptr`, passes.
  - The total size is not compared: `curl-version-info-data` stops at `gsasl_version`.
- **The headers must be no newer than the library chez-curl loads.** The program prints
  `LIBCURL_VERSION_NUM`, and the suite loads `(curl)` in its own process to read the
  library's `version_num`. So a floor lane that compiled against the runner's newer headers
  fails, rather than checking fields its library lacks.
  - The program is compiled with `$CC`, with no `-I` and no `-l`, so the compiler's own
    search path must find `curl/curl.h`. In the container, that is `C_INCLUDE_PATH`.
  - CI's floor lane must point both `C_INCLUDE_PATH` and `CHEZ_CURL_LIBCURL` at its curl
    7.85.0.
  - On macOS, `cc` finds the SDK's headers, and the library is the system's dylib. An SDK
    newer than the running OS fails this rule. Point `CC` at the matching SDK with
    `-isysroot`, or set `C_INCLUDE_PATH`. On the maintainer's Mac (Apple's libcurl
    8.7.1), the SDK's headers were no newer, and the suite passed.
  - The compile is judged by its exit status alone. `_Generic` needs C11, which gcc and
    clang default to.
- **The feature list is checked from Scheme to C,** not against the headers for
  completeness. A bit the headers have and the list lacks goes unchecked here.
  `test-verify` holds the list as it is.

## Amendment, 2026-10-16: the non-threaded check (M0 slice 5)

- **`make check-nothreads` is the non-threaded check.** It finds every public library under
  `src/` (one with no `private` in its name), and fails when it finds none. It imports each
  with `(environment '(rnrs) NAME)`, which expands the library without running its body, so
  libcurl is never loaded. It requires `require-threaded`'s refusal by name: a syntax
  violation from `chez-curl`, carrying its message.
- **It fails on a threaded Chez, by design,** naming `(curl)`, so `make test` does not run
  it. CI's `nothreads` lane runs it on Chez 10.4.0 built with `--nothreads`.
  `tests/test-check-nothreads.sps` holds each rule on fixture trees. On a copy whose refusal
  always fires, the check passed. A real `--nothreads` Chez is first measured by CI.

## Amendment, 2026-10-16: bytevector copies go through one checked wrapper (M0 slice 5)

- **Valgrind cannot see an overrun into a bytevector.** Measured under slice 5's gate: a
  `memcpy` of 24 bytes into a 23-byte bytevector, through a `u8*` argument, passed with 0
  errors. A bytevector lives in Chez's own heap, which Valgrind sees as one live block
  (ADR-0014, amended).
- **So decision 5's copies get their bound from Scheme, decided by the maintainer before M2
  writes the first one.**
  - One checked wrapper owns every copy between a bytevector and foreign memory. Before
    calling `memcpy`, it asserts that `offset + n` is within the bytevector's length.
  - No other binding may hand C a bytevector's data: a `u8*`, `u16*` or `u32*` parameter,
    or a callable's result of those types. `test-collect-safe` refuses any such binding
    unless its table row marks it as the reviewed crossing. String parameters are crossings
    too, since Chez makes their copy in its own heap. They need a mark saying their callee
    keeps no pointer (ADR-0013, amended).
  - The wrapper's bound is mutation-tested when M2 builds it.

## Amendment, 2026-10-17: the variadic bindings (M0 slice 6)

- **Decision 1 is built.** `bind-variadic` is a second known wrapper in
  `(curl private native)`. Its template carries `(__varargs_after 2)`, so no use can drop it:
  `test-collect-safe` refuses a convention taken from a macro's pattern.
  - It binds `curl_easy_setopt` three times, `(uptr int long)`, `(uptr int uptr)` and
    `(uptr int integer-64)`, and `curl_easy_getinfo` once, `(uptr int uptr)`, whose one
    variadic argument is where to write the answer.
  - They are bound last in the load's step 6, so a library that lacks an earlier entry point
    is still refused naming that one.
  - The conventions table requires exactly `(__varargs_after 2)` of all four entries this
    decision names, and each row names `bind-variadic` as the only way to bind its entry. A
    direct binding, even with the convention, fails as `wrong-binder`. `curl_multi_setopt`
    and `curl_share_setopt` hold M3 to it before they are bound.
  - libcurl has other variadic entry points, `curl_formadd` and the `curl_mprintf` family.
    chez-curl binds neither.
  - String options are not bound yet: M2 decides which strings libcurl keeps
    (`CURLOPT_POSTFIELDS` keeps its pointer).
- **Decision 2's lookup exists.** `curl-easy-option` reads an option's id and `CURLOT_*`
  type code from `curl_easy_option_by_name`, through the `curl-easyoption` ftype, and
  `(curl private constants)`'s `curlot-types` names the codes. No option id is written in
  Scheme.
- **Decision 4 gains `struct curl_easyoption`.** Each field is checked, but not the struct's
  size, so a field dropped from the end would pass. Native reads one option at a time, by
  the pointer libcurl hands it, and never steps from one to the next.
- **The Consequences' first FFI test is `test-variadic`, without a transfer.** libcurl
  stores what setopt gives it, and getinfo reads it back, or answers by its code:
  - **a pointer:** `CURLOPT_PRIVATE`, read back through `CURLINFO_PRIVATE`, exactly, for two
    sentinels above 2^32;
  - **a `long`:** `RTSP_CLIENT_CSEQ`, read back through `CURLINFO_RTSP_CLIENT_CSEQ`. It
    needs a libcurl built with RTSP, as Guix's, Ubuntu's and the floor build are. Apple's is
    shown by the maintainer's run.
    8.20.0 clamps a value above 2^31-1 and refuses a negative one with
    `CURLE_BAD_FUNCTION_ARGUMENT`, keeping the value it had. 7.85.0 and 8.5.0 do neither. So
    the sentinels lie in [1, 2^31-1], differ, and each setopt's code is asserted: a refused
    second value would otherwise read back as the first;
  - **a `long`'s sign and width:** `MAXFILESIZE` refuses a negative `long`. 0 and 2^40 are
    taken, and -1 and -(2^40) refused. The round trip alone passed a `long` binding typed
    `int`, since Chez zero-extends an `int` and every sentinel fits in 31 bits;
  - **a `curl_off_t`:** `MAXFILESIZE_LARGE` has no readback, but answers by sign. 0 and
    2^62 are taken, and -1 and -(2^62) refused.

  Each of these was measured in C at 7.85.0 (the floor, built by `scripts/ci/build-curl.sh`),
  Ubuntu's 8.5.0 and Guix's 8.20.0, and through the suite at 8.20.0 (`MAXFILESIZE` was not
  run in C at 8.20.0). The mutation log holds the table.

  A string option, and each option's effect in a real transfer, are still M2's.
- **Measured: x86-64 cannot see the annotation.** With `(__varargs_after 2)` removed, every
  value above arrives, and every answer is the same. By the AAPCS64, Linux arm64 passes
  variadic arguments as it passes named ones too, which is not measured.
- **`make check-variadic` plants five mutants, each in a copy.** The unchanged copy must
  pass first. One mutant removes the annotation from `bind-variadic`'s template. Four bind
  one use each, the three setopts and getinfo, through `bind-required`.
  - On every platform, `test-collect-safe` must fail on each mutant, naming exactly the
    bindings it changed. CI's main job runs it.
  - On Apple arm64, `test-variadic` must fail too. The step decides by Chez's machine type,
    `arm64osx` or `tarm64osx`, since a Chez under Rosetta runs x86-64's ABI.
    - Each setopt mutant must fail by name, with a failing test through that binding.
      Getinfo stays annotated there, so no wild write hides the result.
    - The template and getinfo mutants may fail by name or die, since getinfo may write
      through a garbage pointer.
  - Anywhere else, it reports what `test-variadic` did, and does not fail on it.
- **On Apple arm64: pending.** No machine here is Apple arm64. Until the maintainer's M1 runs
  `make test` and `make check-variadic`, nothing shows that the annotation is what makes the
  values arrive there, nor that `test-variadic` sees them fail to.
- **That run gates M2,** as the maintainer decided on 2026-10-17, when the Mac was out of
  reach and slice 6 merged without it. M1 binds no variadic entry point, so it goes ahead.
  M2 binds no setopt or getinfo option until `make check-variadic` has passed on Apple
  arm64, with each arm64 step failing on its planted binding, and the result is recorded
  here. A failure there is a finding against this decision, settled before M2 starts.
- **Not checked yet, and carried forward:**
  - A binding's parameter types against libcurl's prototypes. With getinfo's destination
    typed `int`, `test-variadic` passed, since the slot `foreign-alloc` gave lies below
    2^31. M2, which binds most of the API, needs a prototype check.
  - That `curlot-types` lists every `curl_easytype`. M2's setopt type check leans on it.
  - `curl-easyoption`'s total size.
  - `test-variadic` needs a libcurl built with RTSP. One built with `--disable-rtsp` fails
    it, though chez-curl itself needs only HTTP and HTTPS.
- **Evidence:** the [mutation log](../variadic-mutation-log.md).

## Amendment, 2026-10-23: the checked copies and the carried checks (M2 slice 1)

- **Decision 5's copies are built** in `(curl private native)`.
  - `memcpy` is bound twice, once each way, and neither binding is exported.
  - The exports are `copy-foreign->bytevector!` and `copy-bytevector->foreign!`. Each asserts
    its bound before calling C: the offset and the count are exact non-negative integers,
    their sum is at most the bytevector's length, and the address is a positive exact
    integer. A count of 0 calls nothing.
  - **Chez's `u8*` hands C a whole bytevector, from its first byte.** A pair, a list, a
    vector or a raw address in its place is refused (measured). chez-curl has no shim to add
    an offset, as chez-libuv's does. So a copy at a non-zero offset goes through a fresh
    bytevector of the count's length, and `bytevector-copy!`.
  - Their row is the only one marked `bytevector-crossing`.
- **Every string chez-curl hands libcurl goes through foreign memory** (M2 plan, §3.3).
  `call-with-c-string` makes a counted, NUL-terminated UTF-8 copy, refuses a string holding
  U+0000 before allocating, and frees the copy under `dynamic-wind`. Re-entering it after the
  free raises. Strings come back as bytes, through `strlen` and the checked copy, and native's
  byte-at-a-time reader is gone.
- **The binding order gains one exception.** libc's `memcpy`, both ways, and `strlen` are bound
  right after `curl_version_info` and its NULL check, before the floor check. Step 3 reads
  `curl_version_info_data`'s strings with them, and the floor's refusals carry those strings.
  They are libc's, present once the library loads. Every refusal still names what it named:
  `test-library-loading`'s decoys passed unchanged, a library with no `curl_*` function is still
  `missing-api` for `curl_version_info`, and `below-floor` and `no-ssl` still name the version.
- **The non-threaded check has run on a real `--nothreads` Chez,** built by
  `scripts/ci/build-chez.sh` in Docker, since CI has not. `make check-nothreads` refused `(curl)`
  by name. `(curl private counters)` imports `make-mutex`, the first thread primitive in `src/`,
  and the refusal still came first.
- **The carried checks are built, in `test-constants`:**
  - **Prototypes.** Every entry point `src/` binds has a row: the header's own declaration,
    with the header's own spellings.
    - The C side compiles `_Static_assert(_Generic(ENTRY, TYPE: 1, default: 0), "ENTRY: ...")`
      per row. It needs no link to libcurl and no warning flag, and a wrong row fails naming its
      entry. A must-fail row is compiled each run, to show the check can fail.
    - A row's spelling is checked against the preprocessed headers, so an enum must be written by
      its name: gcc 16.2, gcc 13.3 and clang 18.1.3 each accept `unsigned int` for these enums,
      so the C side alone cannot tell (measured on 18 cases; `_Generic` on gcc 16.2 only).
    - The Scheme side holds each binding's Chez types to its row through `c-type-map`. The map,
      the enum names, and the variadic rows' lists are written out in the suite. Setopt may pass
      `long`, `integer-64` and `uptr`, and getinfo `uptr` alone. Only `curl_url_get`'s row has
      two declarations: 7.85.0's and Debian 7.88.1's headers take `CURLU *`, and Ubuntu 8.5.0's
      and 8.20.0's take `const CURLU *`. Both must give the same Chez types. `(* F)` fits only
      the pointer type F's layout row names, and `string` only `const char *`.
  - **`curlot-types` is complete:** the `CURLOT_` names in `$CC -E` of `curl/options.h` must be
    exactly its names.
  - **A whole layout's size is checked.** A layout row says whether its ftype is the whole
    struct. `curl-easyoption` is, and its `sizeof` must equal its `ftype-sizeof`;
    `curl-version-info-data` stays a prefix.
- **Still carried:** `test-variadic` needs a libcurl with RTSP.
- **Apple's SDK headers have not been read by the prototype check.** The Mac's run shows it.
- **Evidence:** the [foundations mutation log](../foundations-mutation-log.md).
