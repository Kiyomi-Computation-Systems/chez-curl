# ADR-0023: The public request is made from a property list, and carries a whole body

- **Status:** Accepted; amended 2026-10-26: after the plan's review; amended 2026-10-26: as built
  (M4 slice 1); amended 2026-10-27: M5 follows a redirect from its `Location`
- **Date:** 2026-10-26
- **Scope:** chez-curl v1, `(curl)`'s request record, from M4
- **Settles:** the request's public shape, and whether M4's request carries a body; the
  maintainer chose bodies on 2026-10-26, and the shape follows chez-cmark-gfm's convention
- **Related:**
  - [ADR-0001](0001-bind-libcurl-directly.md), amended 2026-10-23: header strings are Latin-1;
  - [ADR-0009](0009-typed-escape-hatch.md): every option a field sets is owned, with its twins;
  - [ADR-0018](0018-ca-file-is-the-only-anchor.md): the TLS fields;
  - [ADR-0024](0024-what-a-transfer-reads-from-its-environment.md): the proxy field;
  - the M2 plan, §5.3, and global-constraints: `framing-header`, "M4 revisits it with bodies".

## Context

The request is private today, `make-transfer-request` in `(curl private transfer)`, with nine
positional fields: the URL, the method (`get` or `head`), headers, a user agent, a timeout, a
body limit, a CA file, verification, and a private fault. It is checked when made, and again at
submit, on a private copy, which is what is sent.

M4 makes it public (brief §8). Fields will grow in M5 to M7: auth, cookies, proxies. A
positional constructor breaks every caller each time.

chez-cmark-gfm, the nearest sibling, makes its options from a property list:
`make-cmark-options`, `default-cmark-options` and `cmark-options-with`, refusing an unknown
key, a repeated key, and a key with no value. chez-libuv's spawn takes an association list,
refusing the same.

No request sends a body yet: a request naming `Content-Length` or `Transfer-Encoding` is
refused, as `framing-header`, because libcurl owns the framing. M5's verbs need a body, and M6
streams bodies both ways.

## Decision

1. **`(make-curl-request URL KEY VALUE ...)`,** with keys from a fixed list. An unknown key, a
   repeated key, and a key with no value are each refused, by name, before anything is checked
   further. A key left out takes its default.
2. **`(curl-request-with REQUEST KEY VALUE ...)`** makes a new request, with the keys given
   replaced and the rest kept, checked as a new one is.
3. **The defaults set no policy** (brief §6.1): `get`, no headers, no body, verification on,
   libcurl's system store, and libcurl's own limits, timeouts included.
4. **M4's request carries a whole body,** a bytevector, with methods beyond GET and HEAD, from
   a fixed set the M4 plan names. The submit's private copy takes the body too, and libcurl is
   handed that copy to copy, so the caller's bytevector may change once submit returns.
   Streaming bodies stay M6's.
5. **libcurl still owns the framing.** `Content-Length` and `Transfer-Encoding` stay refused.
   What libcurl adds to a body on its own, such as a `Content-Type` or `Expect`, the M4 plan's
   first measurement records on each libcurl, before the plan's design for it is built.
6. **The private fault is no key.** The test seam keeps it, through a private constructor.

### Rejected

- **A positional constructor.** Each new field would break every caller.
- **GET and HEAD until M6.** M5's verbs would wait two milestones for a body.

## Consequences

- **The options a body sets are owned,** and their twins refused by the hatch (ADR-0009). The
  M4 plan names them.
- **M5's session merges its defaults into a request with `curl-request-with`.**
- **The request's checks run twice, as now:** when it is made, and on the submit's copy.

## Amendment, 2026-10-26: after the plan's review

An adversarial review of the M4 plan (Opus, read-only) measured bodies and redirects, with a C
probe against a Node server that echoes what it got, on 7.85.0, Ubuntu's 8.5.0 with OpenSSL,
Guix's 8.20.0 and 8.23.0, each alike, and rerun in the container
([research](../research/m4/redirect/)):

- libcurl adds `Content-Type: application/x-www-form-urlencoded` to a body on every method,
  `PUT`, `PATCH` and `DELETE` by `CUSTOMREQUEST` as well as `POST`;
- with `FOLLOWLOCATION`, a 301, 302 or 303 turns a `POST` into a `GET` without its body, and
  resends a `CUSTOMREQUEST` method with no body. 307 and 308 keep both. The option that changes
  it, `CURLFOLLOW_OBEYCODE`, arrived in 8.13.0, above the floor;
- an empty body passed as NULL and as `""` sent the same request, `Content-Length: 0`, and a
  `PUT` with no body sent no `Content-Length`.

So the M4 plan, as its design (§3.2), revised:
- **`FOLLOWLOCATION` is owned, and left off.** Nothing in M4 follows a redirect, and M5 follows
  them itself, from `CURLINFO_REDIRECT_URL`.
- **`CUSTOMREQUEST` is `method`'s own option,** owned, for `put`, `patch` and `delete`, with or
  without a body.
- **With no body, `post`, `put` and `patch` send an empty one,** `Content-Length: 0`, passed to
  libcurl as NULL; a `delete` sends none. A body with `get` or `head` is refused, as
  `&curl-request-error`, reason `body-not-allowed`.
- **Decision 5's measurement is partly in:** the `Content-Type` above is on every method. The
  suppression is measured in slice 1.
- **Decision 6:** "the test seam keeps it" means a private constructor, since the M4 plan
  retires the seam into the hatch in slice 4.

## Amendment, 2026-10-26: as built (M4 slice 1)

Slice 1 measured first ([research](../research/m4/slice1/)), on 7.85.0, Ubuntu's 8.5.0 with
OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0, each alike:

- **Decision 5's measurement.** libcurl adds `Content-Type: application/x-www-form-urlencoded`
  to every body method's body, an empty one too, and `Expect: 100-continue` to one past 1 MiB,
  1,048,577 bytes, then waits about a second for a server that never answers it.
  `Content-Type:` and `Expect:` in `HTTPHEADER` take each away; a header the request names
  replaces libcurl's, in any case.

So, as the M4 plan proposed (§3.2), now built:
- **A request that sends a body also sends `Content-Type:` and `Expect:`,** each unless the
  request names a header of that name. `sent-header-lines` computes the list as data, and
  `test-request` writes its answers out and reads each method's head from the raw face, byte
  for byte.
- **An empty body is a block of one byte, never NULL,** as a defence: with a size of 0 libcurl
  reads nothing either way, but NULL tells it to send the body through its read callback, whose
  default reads stdin; its setopt allocates a byte for a size of
  0 "to mark that postfields is used rather than read function" (`lib/setopt.c`, 7.85.0).
- **The private fault and the private `follow` field** are set by constructors `(curl)` does
  not export, `curl-request-with-fault` and `curl-request-following`, and `curl-request-with`
  keeps both. `follow` sets `FOLLOWLOCATION`, for the tests of a followed redirect and of
  ADR-0003's redirect pin, which set it through the test seam until the seam refused it.
- **The keys' refusals** are `&curl-request-error`s, field `key`, the key as given as their
  value, in this order at each position: `unknown-key`, then `missing-value`, then
  `repeated-key`. Then the URL's type; then the types of `method`, `body`, the timeouts,
  `body-limit`, `ca-file` and `verify`; then `body-not-allowed`, field `body`, the method as its
  value; then the headers and the user agent, their types first; then the CA file's path
  (corrected after the slice's review, which found the headers' types checked after
  `body-not-allowed`).

## Amendment, 2026-10-27: M5 follows a redirect from its `Location` (the M5 plan)

The first amendment above said M5 would follow redirects "from `CURLINFO_REDIRECT_URL`". The M5
plan measured that field on five libcurls first (ADR-0008, amended 2026-10-27): which statuses
carry it, and whether it keeps credentials, move with the version, and it hands back unparsed
what `curl_url_set` refuses. So M5 resolves the first `Location` header's bytes itself, by
ADR-0008's decision 4, against the URL it requested. `FOLLOWLOCATION` stays owned and off, and
the private `follow` field stays the redirect-pin tests' alone.
