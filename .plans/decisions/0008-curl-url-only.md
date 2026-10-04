# ADR-0008: URLs are parsed, checked and resolved by libcurl's own URL API

- **Status:** Accepted
- **Date:** 2026-10-04
- **Scope:** chez-curl v1
- **Settles:** D2 (brief §10)
- **Related:** brief §3 · [ADR-0003](0003-libcurl-floor-7-85.md), which pins each transfer to
  http and https · uriparse (Kiyomi-Computation-Systems/uriparse), a separate project

## Context

The brief's worry is two URL grammars in one process: chez-curl accepting a URL that curl
rejects, or the two disagreeing about the host. It recommended libcurl's URL API, with
uriparse available as an opt-in strict RFC 3986 validator.

Measured with `curl_url_set` and `curl_url_get` on libcurl 8.20.0 (this host), with no
flags:

- **It resolves relative references.** Against the base `http://example.com/a/b/c?q=1`:

  | Reference | Result |
  |---|---|
  | `../d?x=2` | `http://example.com/a/d?x=2` |
  | `//other.example/x` | `http://other.example/x` |
  | `/root` | `http://example.com/root` |
  | `?only=query` | `http://example.com/a/b/c?only=query` |
  | `#frag` | `http://example.com/a/b/c?q=1#frag` |
  | `https://elsewhere/` | `https://elsewhere/` |

  It also removes dot segments: `/./a/../b` becomes `/b`.
- **It refuses:**
  - a space in the path or host (`CURLUE_MALFORMED_INPUT`);
  - port 99999 (`CURLUE_BAD_PORT_NUMBER`);
  - a missing scheme (`CURLUE_BAD_SCHEME`);
  - an unknown scheme such as `foo://` (`CURLUE_UNSUPPORTED_SCHEME`).
- **It accepts two things RFC 3986 rejects.** The invalid percent-encoding in
  `http://example.com/a%zz` passes unchanged. `http:/example.com/x` is rewritten to
  `http://example.com/x`.
- **It keeps what it was given in two places.** The host's case and an explicit default port
  survive: `HTTP://Example.COM:80/…` comes back as `http://Example.COM:80/…`. It also parses
  `file:///etc/passwd`, because the scheme is one this libcurl supports.
- **A transfer can take the parsed handle itself.** `CURLOPT_CURLU` (7.63.0) gives the
  transfer the parsed handle. curl's documentation says "libcurl uses this handle and its
  contents read-only and does not change its contents".

uriparse is at v0.6.2 (2026-10-01): a strict RFC 3986 parser in portable R6RS. An audit
found it recognises exactly RFC 3986's grammar, with "zero deviations", and it passes all 42
resolution examples in RFC 3986 §5.4.

## Decision

1. **`curl_url` parses every URL a caller hands chez-curl.** A refusal raises a condition
   that carries the input, the `CURLUcode`'s name and `curl_url_strerror`'s message.
2. **The scheme must be `http` or `https`.** chez-curl checks it on the parsed handle before
   anything is submitted, and refuses anything else by name. ADR-0003's transfer-time pin
   remains as the second line.
3. **The transfer takes the parsed handle through `CURLOPT_CURLU`,** never a string that
   Scheme rebuilt. libcurl reads it without changing it, so the request goes to exactly the
   URL that was checked. A `CURLU` handle is used by one thread at a time. If the caller's
   thread parses it, ownership passes to the engine with the request, and the caller never
   touches it again. Which thread parses is M3's to settle.
4. **Relative references are resolved with `curl_url_set` against the current URL's
   handle.** That applies the same RFC 3986 §5 resolution libcurl uses. This covers any
   redirect `Location` the high level follows itself.
5. **chez-curl does not depend on uriparse.** A caller who wants a strict RFC 3986 verdict
   runs uriparse on the string before handing it over. The documentation says so, and lists
   curl's leniencies measured above.

### Rejected

- **An opt-in strict library on top of uriparse.** It would add a dependency, and its verdict
  would not change what is fetched. Callers can call uriparse directly.
- **uriparse on the request path.** That puts two grammars in every request, which is the
  divergence the brief warned about, and makes every user depend on uriparse.

## Consequences

- **What is checked is what is fetched.** That holds by construction: one parser and one
  parsed object.
- **chez-curl inherits curl's verdicts, leniencies included.** The suite pins the verdicts
  chez-curl relies on: RFC 3986 §5.4's resolution examples, the refusals above, and the scheme
  check. It runs them on every lane, the floor lane included (ADR-0003). It also asserts the
  documented leniencies, so a libcurl that changes them flags the documentation as stale.
- **Every string `curl_url_get` returns is freed with `curl_free`.** That is a rule of the
  binding, and the memory gate checks it.
- **Origins cannot be compared as strings,** because host case and explicit default ports
  survive parsing. Redirect policy (M5) compares the scheme, the lowercased host and the
  effective port, using `CURLU_DEFAULT_PORT` when reading the port.
- **uriparse and chez-curl stay independent,** sharing no code.
