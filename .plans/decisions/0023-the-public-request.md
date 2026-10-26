# ADR-0023: The public request is made from a property list, and carries a whole body

- **Status:** Accepted
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
