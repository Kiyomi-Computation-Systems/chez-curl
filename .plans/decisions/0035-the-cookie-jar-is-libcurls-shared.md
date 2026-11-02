# ADR-0035: The cookie jar is libcurl's, shared

- **Status:** Accepted; amended 2026-11-02, after the M7 plan's review: decision 4's round trip
  on 7.85.0, and the lines a load takes; and decision 6, the maintainer's, the recommended option
- **Date:** 2026-11-02
- **Scope:** chez-curl v1, cookies, in `(curl)` and `(http-client)`, from M7
- **Settles:** how a session's cookie jar is built. The maintainer chose on 2026-11-02, the
  recommended option, from the M7 plan's probe ([research](../research/m7/cookies/)). ADR-0033
  had settled one in-memory jar per session, read out and loaded as data, with no file paths.
- **Related:**
  - [ADR-0033](0033-m7s-scope.md): M7's scope;
  - [ADR-0012](0012-engine-thread-owns-every-handle.md): the engine's thread owns every handle a
    transfer uses, share handles among them;
  - [ADR-0009](0009-typed-escape-hatch.md): `COOKIEFILE` and `COOKIEJAR` are owned, for their
    `"-"` modes.

## Context

Each transfer's easy handle is fresh, and freed when it ends, so libcurl's cookie engine keeps
nothing between transfers unless a `curl_share` holds the cookies. A C probe that steps a multi
handle as the engine does ran on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's
8.20.0 and 8.23.0, two runs each, with no case differing between runs:

- **A share with `CURL_LOCK_DATA_COOKIE`, attached to each handle with `COOKIEFILE ""`, carries
  cookies across fresh handles** on all five: to the same host, and by domain to another. Without
  the share nothing carried; with it but without `COOKIEFILE ""` nothing was stored, and a handle
  without it sends none of the jar's cookies.
- **Transfers live at once on one multi handle, one thread, with no lock callbacks,** each saw
  the others' cookies, and every one ended 0.
- **`curl_share_cleanup` answers `CURLSHE_IN_USE`** while any handle holds the share, finished or
  live, and 0 once each is detached or cleaned up.
- **Import and export:** a jar read out by `CURLINFO_COOKIELIST` and loaded line by line through
  `COOKIELIST` into a fresh share gave the same 13 lines, in order, `#HttpOnly_` and session
  cookies among them, on every lane. A `Set-Cookie:` line with no `Domain`, loaded that way, never
  shows in an export. A line loaded before `SHARE` is set is lost when the share is attached. No
  case read stdin, wrote stdout or stderr, or left a file.
- **What varies by version or build:** `Domain=localhost` by the PSL bit; the default path;
  8.20.0's and 8.23.0's 400-day expiry cap; `Max-Age=-1`, sent as a session cookie on 7.85.0
  alone; a deleted cookie still listed on 7.85.0 and 8.5.0.

Apple's 8.7.1 has not run this probe.

## Decision

1. **A jar is one `curl_share` sharing `CURL_LOCK_DATA_COOKIE`,** made, used and freed on the
   engine's thread, and counted as every native object is (ADR-0012). It needs no lock callbacks:
   one thread alone touches it.
2. **A transfer that uses a jar sets `SHARE` first, then `COOKIEFILE ""`,** which turns the cookie
   engine on and names no file. `COOKIEFILE` and `COOKIEJAR` are never set to a file or to `"-"`.
3. **A jar is freed only once no transfer holds it,** since libcurl refuses the cleanup before
   then.
4. **Cookies go in as Netscape lines through `COOKIELIST`, and come out through
   `CURLINFO_COOKIELIST`,** so what is read out loads back the same, but on 7.85.0 for a cookie
   whose name or value holds a tab: 7.85.0 stores it, and lists it as eight fields, which a load
   refuses. A load takes only lines libcurl keeps alike on every version: seven fields, none
   holding a control byte, none empty but the value. Before 8.23.0 libcurl stores a control byte
   from a loaded line raw, 8.23.0 drops the line and answers 0, and 7.85.0 merges an empty field
   ([review](../research/m7/review/)).
5. **The cookie rules are libcurl's.** Where they vary by version or build, M7's tests pin each
   version's answer, and the documentation says so.
6. **A request that carries a jar refuses a caller's `Cookie` or `Host` header,** so one source
   holds its cookies: libcurl sends a caller's `Cookie` as a second header beside the jar's, and
   drops `COOKIE` beside it; and a caller's `Host` sets the host the jar matches cookies against,
   sending and storing (read in curl's source).

## Rejected

- **A jar in Scheme, in `(http-client)`:** alike on every libcurl, but chez-curl would own every
  rule of RFC 6265, without a public suffix list.

## Consequences

- `curl_share_init`, `curl_share_setopt` (variadic, so `make check-variadic` runs on the Mac) and
  `curl_share_cleanup` are bound, with `curl_slist` read for `CURLINFO_COOKIELIST`.
- The cookie options a jar sets become owned, with their twins; which options those are is the
  M7 plan's.
