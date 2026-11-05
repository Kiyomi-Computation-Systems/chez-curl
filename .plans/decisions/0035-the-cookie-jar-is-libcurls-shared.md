# ADR-0035: The cookie jar is libcurl's, shared

- **Status:** Accepted; amended 2026-11-02, after the M7 plan's review: decision 4's round trip
  on 7.85.0, and the lines a load takes; and decision 6, the maintainer's, the recommended option;
  amended 2026-11-04, measured through the engine, with decisions 7 to 9, and after the slice's
  review, decisions 10 to 13, the maintainer's, each the recommended option (M7 slice 4)
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

The maintainer's Mac ran it on 2026-11-02, twice, against Apple's 8.7.1, with no split: the
share, live transfers, the 13-line round trip and a caller's cookies as on Linux. Without PSL it
keeps `Domain=localhost`, which there reaches `localhost` itself; its paths are 7.85.0's and
8.5.0's; it caps no expiry; it lists a deleted cookie.

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

## Amendment, 2026-11-04: measured through the engine (M7 slice 4)

M7 slice 4 ran a jar through a prototype of the engine, as the M7 plan's section 3.5 has it, on
the five Linux libcurls, two runs each, and its lifetime once more under the memory gate's
Valgrind on Ubuntu's 8.5.0 with OpenSSL ([research](../research/m7/slice4/)). What it adds, and
corrects:

- **The lifetime holds.** 200 transfers, 20 live at a time, shared one jar; a close while
  transfers held it answered at once, and the share was freed once, as the last let it go,
  `curl_share_cleanup` answering 2 until then; 500 crossings of a close and a submit on two
  threads each ended as a transfer that ran with the jar, a refusal at submit or a refusal in
  `set-up!`, and nothing else; a stop freed a live jar and a closing one. Pooled HTTP/1.1 and
  HTTP/2 connections opened while the jar was held were reused after it was freed. Valgrind found
  no error. A handle left in the multi handle keeps the share, and both stay counted.
- **`SHARE` and `COOKIEFILE ""` may come in either order:** each stored and sent the same on all
  five.
- **A loaded cookie can hang every request to its host.** `COOKIELIST` puts no cap on a loaded
  line's name and value, where a server's `Set-Cookie` is held to 4,096 bytes (`MAX_NAME`). When
  the first cookie a request would send passes the `Cookie` line's cap of 8,190 bytes, libcurl
  has written `Cookie: ` and writes no line end, so the head's own last CRLF ends that line and
  the head never ends: the request waits for its timeout, 28, on all five, and in plain C on a
  bare handle too (8.20.0 `lib/http.c:2557-2600`, read in source; Apple's 8.7.1 the same). On
  7.85.0 the cap counts the head built before the `Cookie` line, so a server's 4 KB cookie and a
  URL path of 4,200 bytes hang it the same way ([verify](../research/m7/slice4/verify/)).
- **The plan's rule let through lines libcurl drops, rewrites or splits by version:** a domain
  starting `#` after `#HttpOnly_`, or a line starting `Set-Cookie:`, dropped everywhere; a
  tail-match or secure field other than `TRUE`, read out `FALSE`; an expiry with a sign, a space,
  an exponent or past 64 bits, dropped or split; a path that is not absolute, kept on 7.85.0 and
  8.5.0 and made `/` on 8.20.0 and 8.23.0. A read-out on 7.85.0 and 8.5.0 gives lines the rule
  refuses, beside 7.85.0's tab: a server's `Path=`, `Path=TRUE` and `Path=FALSE`.
- **Bytes above 0x7F** in a name or value are stored, read out and sent byte for byte, alike on
  all five, from a `Set-Cookie` and from a load.
- **Decision 6 holds by measurement:** a caller's `Host`, in any case and with any port, sends
  that host's cookies and stores the answer's there, over HTTP/1.1 and over HTTP/2 as
  `:authority`; a caller's `Cookie`, empty or in any case, goes out beside the jar's.
- **`COOKIELIST` reaches past its transfer:** set by the hatch on a transfer that holds the jar,
  `ALL` and `SESS` cleared the jar for every transfer, and a line loaded into it. `COOKIESESSION`
  and `HSTS_CTRL` changed nothing in the jar.
- **A share of cookies carries no HSTS entry,** on 8.20.0 and 8.23.0; one that also shares
  `CURL_LOCK_DATA_HSTS` carried it. 7.85.0 refuses that lock value.
- **A load costs about n² on the engine's thread:** 10,000 lines took 0.24 to 0.50 s, 50,000
  9.4 to 27.4 s, nearly all of it libcurl's setopt; reading 50,000 out took 1.7 to 6.4 s.

Decided by the maintainer, 2026-11-04, each the recommended option:

7. **A load takes a line only in the form a read-out writes it** (decision 4, amended): seven
   tab-separated fields, none holding a byte from 0x00 to 0x1F or 0x7F; the domain, after an
   optional `#HttpOnly_`, is not empty and does not start with `#`, and the line does not start
   with `Set-Cookie:` in any case; the domain starts with a dot exactly when the tail-match field
   is `TRUE`; the tail-match and secure fields are `TRUE` or `FALSE`; the path starts with `/`;
   the expiry is decimal digits, at most 9223372036854775807; the name is not empty, and the name
   and value together are at most 4,096 bytes, libcurl's own cap on a server's cookie, which
   closes the hang. Every line of the measurement it takes loaded alike on all five, but one whose
   expiry has passed: 8.20.0 and 8.23.0 drop it at once, 7.85.0 and 8.5.0 list it until the next
   cookie is added. 7.85.0's hang through a long URL is libcurl's: documented, pinned by version,
   and drafted for curl as a report.
8. **A cookie line is a Latin-1 string, both ways,** as a header's strings are (ADR-0001): each
   byte one character, so no byte is lost either way. A line holding a character above U+00FF is
   refused, `cookie-line`.
9. **A load's cost is documented,** and carried beside the open cap on a response's headers: a
   bound on one load would not bound the jar, which servers' `Set-Cookie` headers fill too.

## Amendment, 2026-11-04: after the slice's review (M7 slice 4)

The slice's adversarial review ([review](../research/m7/slice4/review/)) found decision 7's rule
still taking lines libcurl splits on, and lines no read-out holds; I reproduced each
([verify](../research/m7/slice4/verify/)):

- **A cookie prefix in another case:** 7.85.0, 8.20.0 and Apple's 8.7.1 match a loaded name's
  `__Secure-` or `__Host-` in any case, and a `Set-Cookie` name's in its own case alone; 8.23.0
  matches its own case both ways (8.20.0 `lib/cookie.c:499`, `:742`, read in source). So a
  server's `__secure-a` that is not `Secure` is stored and read out, then dropped as it is loaded
  back on 7.85.0 and 8.20.0, every load answering 0; 8.23.0 keeps it; both 8.5.0 builds drop it
  at the `Set-Cookie`. On 8.20.0, five lines read out, one kept.
- **A pair no `Set-Cookie` can make:** a loaded value holding `; `, or a name holding `=`, went
  out as more pairs, `Cookie: a=b=c; n=x; admin=1`, on all five.
- **7.85.0's open head** comes of everything written before the `Cookie` line, not the URL
  alone: a 4,300-byte user agent, or Basic credentials with a 3,300-byte password, beside a
  server's 4 KB cookie, left it open too.
- **A tab in a server's `Path`** reads out as eight fields on 7.85.0, a line the load refuses;
  the other lanes drop the cookie.
- **`CONNECT_TO` beside a jar,** read in source alone: libcurl stores the reached server's
  `Set-Cookie` under the URL's host, and sends it that host's cookies (8.20.0
  `lib/http.c:3553-3560`), as a hosts file's entry would.

Decided by the maintainer, 2026-11-04, each the recommended option:

10. **A load refuses a cookie-prefixed line that breaks its prefix's rule,** `cookie-line`: a name
    starting `__Secure-` or `__Host-`, in any ASCII case, needs the secure field `TRUE`, and
    `__Host-` the path `/` and the tail-match `FALSE` too. A server's such cookies read out on
    7.85.0, 8.20.0 and 8.23.0 are pinned among the read-out lines a load refuses.
11. **Each jar procedure waits with no bound,** as `curl-engine-stop` does: the engine answers
    every jar message, at its turn, at a stop and at its failure, and a bound would fail a load
    that is slow by libcurl's cost.
12. **A load refuses `;` in a name or a value, and `=` in a name,** `cookie-line`: a read-out never
    holds them, since a `Set-Cookie` ends a value at `;` and a name at `=`. An `=` in a value
    stays.
13. **`CONNECT_TO` stays the hatch's,** documented: a routing choice its transfer makes, cookies
    following the URL's host as they would a hosts file's.

### As built (M7 slice 4)

- **The jar** is an opaque record in `(curl private transfer)`, where the request key checks it:
  its engine, its share, the handle the engine keeps for its messages, counted and freed before
  the share, a state (pending until its make is carried out, then live, closing, closed) and a
  holder count. `make-curl-cookie-jar`, `curl-cookie-jar-cookies`, `curl-cookie-jar-load!`,
  `curl-cookie-jar-close!` and `curl-cookie-jar?`, each a message, each waiting with no bound and
  refused inside a critical section (decision 11). A share setopt that answers but 0 fails the
  make, which frees what it made. A failed engine leaves an abandoned handle's jar closing, its
  share counted.
- **The load** copies the lines and checks them on the caller's thread, then posts their bytes.
  `cookie-line`'s rules, in the order they are read: `not-latin-1`, `control-byte`, `set-cookie`,
  `fields`, `domain`, `tail-match`, `leading-dot`, `path`, `secure`, `expiry`, `name`,
  `separator`, `size`, `prefix`; a prefix is matched on the name, A to Z folded alone. A refusal
  names the line by its index. A `COOKIELIST` answer but 0 raises `&error` naming the index and
  the code, the lines before it loaded: libcurl answers 0 to a line it drops, so only a test seam
  or a failed allocation reaches it.
- **The high level:** `cookies` is a session's key, not a call's.
- **Opaque now, since a response's headers can hold a `Set-Cookie`:** `curl-response`,
  `curl-head` and `http-response`.
- **The origin:** `/cookies[/P]` writes the `Set-Cookie` lines its query names, with a chosen
  status and `Location`; `/cookie-log?key=K` reports each request's `Cookie` headers whole; its
  `http` face logs a head left open when its connection closes, by a `'data'` listener of its own,
  since `node:http` reports one with no bytes (traps.md).
- **`test-cookies`,** 70 tests, and its child `jar-abandon.sps`; by version, `refused-readout`,
  `expired-load`, `open-head`, `set-cookie-matrix`, and `domain-localhost`, keyed by version and
  the PSL bit, each from two runs on the five lanes. `test-variadic` watches `curl_share_setopt`
  by behaviour: `SHARE 2` alone of 0 to 9 carries a cookie, 99 and -1 answer 1, and `UNSHARE 2`
  stops the carrying. 104 mutants, each failing a test ([build](../research/m7/slice4/build/)).

