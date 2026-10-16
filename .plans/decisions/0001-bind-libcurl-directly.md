# ADR-0001: Bind libcurl directly, with no C shim; the floor is Chez 10.4.0, threaded

- **Status:** Accepted; amended 2026-10-16 with what M0 slice 3 built
  ([amendment](#amendment-2026-10-16-what-slice-3-built))
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
