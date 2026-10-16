# ADR-0003: The libcurl floor is 7.85.0, and two APIs are probed at load

- **Status:** Accepted; amended 2026-10-16: `missing-api` also names a missing entry point
- **Date:** 2026-10-04
- **Scope:** chez-curl v1
- **Settles:** D10. That decision was raised on 2026-10-04, after the brief was written.
- **Supersedes:** the brief's 7.84 floor (its header line and §9 risk 5).
- **Related:** [ADR-0001](0001-bind-libcurl-directly.md), which relies on the options and
  header APIs · [ADR-0002](0002-runtime-libcurl-discovery.md), which runs these checks after
  its single load · brief §3 (the HTTP and HTTPS scope)

## Context

The brief puts the floor at 7.84. Its reasons: `curl_multi_poll` needs 7.68,
`curl_easy_header` needs 7.83, and `CURL_VERSION_THREADSAFE` needs 7.84. curl's own records
(`docs/libcurl/symbols-in-versions`, and each function page's `Added-in`) give this
design's dependencies as:

| Needed for | Symbol | First version |
|---|---|---|
| the engine's wait | `curl_multi_poll` | 7.66.0 |
| waking the engine on submit | `curl_multi_wakeup` | 7.68.0 |
| `CURLOPT_*` ids and types (ADR-0001) | `curl_easy_option_by_name` | 7.73.0 |
| response headers (brief §3) | `curl_easy_header`, `curl_easy_nextheader` | 7.83.0 |
| — | `CURL_VERSION_THREADSAFE` | 7.84.0 |
| pinning requests and redirects to http and https (brief §3) | `CURLOPT_PROTOCOLS_STR`, `CURLOPT_REDIR_PROTOCOLS_STR` | 7.85.0 |

The brief's "`curl_multi_poll` needs 7.68" conflated the poll (7.66) with the wakeup (7.68).
Two further findings move the floor and change how it is checked.

**7.85.0 is the first version with a non-deprecated way to pin protocols.** The bitmask
options `CURLOPT_PROTOCOLS` and `CURLOPT_REDIR_PROTOCOLS` were deprecated in 7.85.0, when
the `_STR` options arrived. The scope is HTTP and HTTPS only (brief §3). So every transfer
must refuse `file://`, `dict://`, `gopher://` and the rest, both as a request and as a
redirect target. On 7.84 that needs the deprecated options, or a second code path.

**A version check cannot see two build switches.**

- **The header API's history.** In 7.83.0 it was off by default and listed in
  `docs/EXPERIMENTAL.md`; its `configure.ac` says
  `curl_headers_msg="no (--enable-headers-api)"`. 7.84.0 turned it on.
- **The switches.** Every version since 7.85.0 still accepts `--disable-headers-api` and
  `--disable-get-easy-options` (`docs/CURL-DISABLE.md` today). Either one leaves the
  version and the symbols in place but switches off an API ADR-0001 depends on.
- **How each behaves when disabled.** With options disabled, `curl_easy_option_by_name`
  returns NULL for every name (`lib/easygetopt.c` at the `curl-7_85_0` tag). On this host's
  8.20.0, `curl_easy_header` on a fresh easy handle returns `CURLHE_NOHEADERS` (3); a build
  without the API returns `CURLHE_NOT_BUILT_IN` (7).

**Reach is not what decides it.** What supported platforms ship, per Launchpad and Repology
on 2026-10-04 (Apple's from the brief, Guix measured on this host):

| Platform | libcurl |
|---|---|
| Debian 11 | 7.74.0 |
| AlmaLinux 9 (RHEL 9) | 7.76.1 |
| Ubuntu 22.04 | 7.81.0 (package `7.81.0-1ubuntu1.29`) |
| Debian 12 | 7.88.1 |
| Ubuntu 24.04 | 8.5.0 |
| macOS, Apple's | 8.7.1 |
| Alpine 3.17 and later | 8.9.0 or newer |
| CentOS Stream 10 | 8.12.1 |
| Ubuntu 26.04 | 8.18.0 |
| Guix | 8.20.0 |
| Homebrew, Arch | 8.22.0 |

Every platform at or above 7.84 is at least 7.88.1, and every one below 7.84 is well below
it. So 7.84, 7.85 and 7.88.1 admit the same platforms today. The choice rests on API
reasons and testability.

## Decision

1. **The floor is libcurl 7.85.0.** `curl_version_info`'s `version_num` must be at least
   `0x075500`. A lower library is refused as `below-floor` (ADR-0002), naming its path and
   version.
2. **Two APIs are probed at load.** The probes run after the version check and before
   `(curl ...)` hands anything to a caller.
   - `curl_easy_option_by_name("URL")` must return non-NULL.
   - `curl_easy_header` on a fresh easy handle must not return `CURLHE_NOT_BUILT_IN`.

   A failure is refused as `missing-api`, naming the API. This joins ADR-0002's reason
   symbols.
3. **Every transfer is pinned to http and https**, through `CURLOPT_PROTOCOLS_STR` and
   `CURLOPT_REDIR_PROTOCOLS_STR`. The deprecated bitmask options are never used.
4. **Anything newer than the floor is optional, one feature at a time.**
   - **Options** such as `CURLOPT_QUICK_EXIT` (7.87.0) are looked up by name through the
     options API. When the loaded library doesn't know one, only the feature that needs it
     raises a condition, naming the option.
   - **Functions** such as `curl_multi_get_handles` (8.4.0) are bound only if `foreign-entry?`
     finds them, and still eagerly at load (ADR-0002).
   - Nothing newer than the floor is ever required.
5. **`CURL_VERSION_THREADSAFE` is reported, not required.** The bit only says whether
   `curl_global_init` may be called concurrently, and chez-curl calls it once, from its
   library body.

### Rejected

- **7.84.0 (the brief's).** Protocol pinning would need the deprecated bitmask options or a
  second code path, for a version no supported platform ships.
- **7.88.1 (Debian 12's).** CI could then test a stock Debian 12 package instead of building
  curl. But that job would still build Chez, since Debian 12's apt Chez is 9.5.8. And the
  floor would refuse 7.85.0–7.88.0 builds that work.

## Consequences

- **The floor is about APIs, not bugs.** Distributions backport fixes without changing the
  version; Ubuntu 22.04's `7.81.0-1ubuntu1.29` is one example. The version says which entry
  points and options exist, never which bugs are fixed.
- **CI gets a floor lane.** It builds curl 7.85.0 from the release tarball and caches it by
  version, as chez-libuv's CI caches its Chez build. It then runs the suite with
  `CHEZ_CURL_LIBCURL` pointing at that build. Without the lane the floor is a claim; with
  it, any reliance on something newer fails there, by name.
- **The `missing-api` refusals must be seen to fire.** The probe's decision is a pure
  function, unit-tested with synthetic results. The floor lane also builds a 7.85.0 variant
  with `--disable-get-easy-options` and `--disable-headers-api`, so one real refusal is
  watched end to end. No packaged libcurl disables either API, so nothing else would ever
  exercise those paths.
- **Ubuntu 22.04, Debian 11 and RHEL 9 are below the floor.** Their users need a newer
  libcurl, named through `CHEZ_CURL_LIBCURL` (ADR-0002). The supported-platforms
  documentation says so.

## Amendment, 2026-10-16: `missing-api` also names a missing entry point

M0 slice 3 checks each required entry point with `foreign-entry?` before binding it.
A library without one is refused as `missing-api`, with the entry point's C name as its
detail. The other way to fail is Chez's bare `no entry for`, which decision 2 is written
to avoid. A library that is not libcurl at all is refused this way, as missing
`curl_version_info`. The two probes in decision 2 keep their meaning.
