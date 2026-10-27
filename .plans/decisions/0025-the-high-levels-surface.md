# ADR-0025: The high level's surface: explicit sessions, prefixed verbs, bodies, forms and params

- **Status:** Accepted
- **Date:** 2026-10-27
- **Scope:** chez-curl v1, `(http-client)`, from M5
- **Settles:** three questions the M5 plan raised about `(http-client)`'s public surface. The
  maintainer chose each on 2026-10-27, each the recommended option.
- **Related:**
  - brief §6.2 and §6.3, the high level and its thread sugar;
  - [ADR-0007](0007-one-repo-checked-seam.md) and [ADR-0010](0010-names-curl-and-http-client.md):
    `(http-client)` reaches the low level only through `(curl)`;
  - [ADR-0012](0012-engine-thread-owns-every-handle.md): concurrency costs no threads;
  - [ADR-0023](0023-the-public-request.md), the low level's request, which the high level builds.

## Context

M4 made the low level public: a request made from a property list, an engine that runs it, a
token to await, and a mailbox for completions. M5 builds the high level on it (brief §8): sessions,
the verbs, redirect and retry policy, and the thread sugar.

The brief sketches the verbs as `(get s url)` and `(post s url ...)`, after Racket's
`http-easy`, beside `http-parallel` and `call-with-http-session`. Every name `(curl)` exports
carries the `curl-` prefix. The brief names ad-hoc scripting as the first consumer, which a
session made for one call taxes. And it leaves decoding to the caller: chez-curl is not a JSON
library (brief §3).

## Decision

1. **The verbs carry the `http-` prefix:** `http-get`, `http-head`, `http-post`, `http-put`,
   `http-patch` and `http-delete`, and `http-request`, which takes the method. Each takes the
   session first. A caller who wants short names renames them on import.
2. **Every call takes an explicit session.** `(http-client)` has no default session, and starts
   no thread a caller did not ask for. A session owns one engine, and `call-with-http-session`
   stops it when its procedure returns or escapes.
3. **A call's body is a bytevector or a string, or a form; a call may add params to the URL:**
   - `body`: a bytevector, sent as is, or a string, sent as its UTF-8 bytes;
   - `form`: a list of name and value string pairs, sent as
     `application/x-www-form-urlencoded`;
   - `params`: a list of name and value string pairs, added to the URL's query, encoded the
     same way;
   - no JSON: encoding and decoding stay the caller's (brief §3).

### Rejected

- **Bare verbs, `get` and `post`, as the brief sketched.** They read well, and clash with a
  caller's own definitions. `(prefix (http-client) http:)` would give `http:get`, but the
  library's other names would then read `http:http-parallel`.
- **A lazy default session as well.** It would start an engine thread on a first call and never
  stop it, so it would live until the process exits, a path no test covers.
- **Bytes only, as the low level takes them.** Every caller would percent-encode their own
  forms and queries, and get the encoding's edge cases wrong in their own ways.

## Consequences

- **A one-off script writes a session:**
  `(call-with-http-session (lambda (s) (http-get s url)))`.
- **The form encoding is chez-curl's,** in Scheme, after the WHATWG URL Standard's
  `application/x-www-form-urlencoded` serializer, so it is tested on every byte. Params reach
  the URL through libcurl's URL API, never by Scheme splicing a string (ADR-0008).
- **`(curl)` gains URL functions the high level needs:** appending a query, reading a URL's
  parts, resolving a header's bytes, and setting a fragment. The M5 plan, §3.1, names them.
