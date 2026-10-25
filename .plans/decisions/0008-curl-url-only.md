# ADR-0008: URLs are parsed, checked and resolved by libcurl's own URL API

- **Status:** Accepted; amended 2026-10-17: the measured verdicts become M2's tests; amended
  2026-10-19: the verdicts vary by version, so the suite holds shared answers and version
  rows; amended 2026-10-23 with what M2 slice 1 built, and with what M2 slice 2 changed; amended
  2026-10-24: the caller checks, the engine parses (M3)
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

## Amendment, 2026-10-17: the measured verdicts become M2's tests

- **The verdicts measured above are M2's first URL tests,** run against the loaded libcurl:
  the six resolutions, the dot segments, the four refusals, the two RFC 3986 deviations and
  what parsing keeps.
- **Why M2, not M0:** the harness plan put them in M0's slices 3 and 4, and neither
  slice wrote them. Testing them needs `curl_url`, `curl_url_set`, `curl_url_get`,
  `curl_url_cleanup` and `curl_free`, which M0 has no use for. M2 binds them for the transfer
  (decision 1), and its suite starts from this table.
- **Floor:** the table was measured on 8.20.0. M2's suite runs at the floor too, in CI's
  floor lane, so a verdict that differs at 7.85.0 fails there, naming the verdict.

## Amendment, 2026-10-19: the verdicts vary by version, so the suite holds shared answers and version rows

- **Measured** (2026-10-19), through `curl_url_set` and `curl_url_get` with no flags: this
  record's 16 cases, and RFC 3986 §5.4's 42 examples against the base `http://a/b/c/d;p?q`.
  The libcurls:
  - 7.85.0, the floor, built by `scripts/ci/build-curl.sh` in Docker `ubuntu:24.04`;
  - 7.88.1, Debian 12's, in Docker `node:20.10.0-bookworm`;
  - 8.5.0, Ubuntu 24.04's OpenSSL and GnuTLS builds, which agreed on every case;
  - 8.20.0, the container's.
- **51 of the 58 cases agree on every version. This record's table holds on 8.20.0 alone.**
  The 7 that vary:

  | Case | 7.85.0 | 7.88.1 | 8.5.0 | 8.20.0 |
  |---|---|---|---|---|
  | `#s` (RFC) | `http://a/b/c/#s` | the same | the same | `http://a/b/c/d;p?q#s` |
  | the empty reference (RFC) | `http://a/b/c/` | the same | refused, 3 | `http://a/b/c/d;p?q` |
  | `g:h` (RFC) | `http://a/b/c/g:h` | refused, 5 | refused, 5 | refused, 5 |
  | `http:g` (RFC) | `http://a/b/c/http:g` | refused, 28 | refused, 28 | refused, 28 |
  | `#frag` (this record) | `http://example.com/a/b/#frag` | the same | the same | `http://example.com/a/b/c?q=1#frag` |
  | a space in the path | refused, 25 | refused, 25 | refused, 3 | refused, 3 |
  | a space in the host | refused, 21 | refused, 21 | refused, 3 | refused, 3 |

  - Only 8.20.0 resolves a fragment-only reference, and the empty one, as RFC 3986 does.
    Which release changed them was not measured.
  - Every version writes `//g` as `http://g/`, not RFC 3986's `http://g`.
  - 7.85.0's `curl_url_strerror` text for code 5 differs from the others'.
- **So the suite holds shared answers and version rows,** as the maintainer chose
  (2026-10-19).
  - A case on which every recorded libcurl agrees has one answer, for every lane.
  - The 7 above have one row per libcurl version, in a reviewed file. A libcurl with no row
    fails, printing the row it would need, as the drift guard does (ADR-0017).
  - Each answer is asserted whole: the URL `curl_url_get` gives back, or the refusal's
    `CURLUcode`. No message is compared.
  - A libcurl that answers a shared case differently fails. Moving that case into the rows
    is a reviewed change.
  - Rows are recorded for the libcurls a lane runs: 7.85.0, 8.5.0 and 8.20.0. The Mac's
    8.7.1 prints its row on its first run. 7.88.1 has no lane, so it gets no row.
- **This replaces the 2026-10-17 amendment's "a verdict that differs at 7.85.0 fails
  there".** It would fail on 3 of this record's cases.
- **The documentation lists curl's leniencies by version,** from these rows.
- **Rejected:**
  - **Any measured answer passes.** No rows to add, but a libcurl that moved between known
    answers would pass unseen.
  - **Agreed cases only,** with the 7 in the documentation alone. A change in them would
    never be seen.

## Amendment, 2026-10-23: what M2 slice 1 built

- **`(curl private url)`** holds decisions 1, 2 and 4: `url-normalize`, `url-resolve`,
  `call-with-parsed-url` and `require-http-scheme`. Every `CURLU` handle is made and freed in one
  call, every `curl_url_get` string is freed with `curl_free`, and both are counted (ADR-0014,
  amended 2026-10-23).
- **A refusal raises `&curl-url-error`,** with the string refused, a reason, a code and a
  message. The reason is the code's name, from `curlue-codes`, the floor's 30 codes. A later code
  has reason `#f`, with its number. chez-curl's own reasons are `scheme-not-http` and
  `embedded-nul`, with no code. The condition is private until M4.
- **A NUL is refused before libcurl reads the string,** wherever it sits. Chez's `string` type
  cuts at an embedded NUL without a word, so `"http://a/\x0;b"` would reach libcurl as
  `http://a/`.
- **The scheme check is held against the whole complement:** every protocol the loaded libcurl
  lists, but http and https, must parse and then be refused. That is 18 others on 7.85.0, 28 on
  8.5.0 and 19 on 8.20.0, and each parsed.
- **The suite has 70 cases:** this record's 16, RFC 3986 §5.4's 42, and 12 non-ASCII ones, added
  because only ASCII had been tested. They cover characters of two, three and four UTF-8 bytes.
  60 are shared answers and 10 are version rows.
- **Measured for the non-ASCII cases,** on 7.85.0, 8.5.0 (OpenSSL and GnuTLS alike) and 8.20.0:
  - curl hands back the UTF-8 it was given, raw, in an absolute URL and in a host, with or
    without IDN;
  - it percent-encodes a relative reference's non-ASCII bytes, in lower case before 8.20.0
    (`%c3%a9`) and in upper case on 8.20.0 (`%C3%A9`).
- **The floor lane's stand-in passed with the 7.85.0 row,** in Docker, since CI has not run.
- **The documentation's list of curl's leniencies gains these,** by version.

## Amendment, 2026-10-23: one copy is checked and parsed (M2 slice 2)

- **`call-with-parsed-url` checks a private copy of its string, and hands libcurl that copy.**
  It used to check the caller's string, then encode it again. A thread that changed it in
  between could put U+0000 past the check, and libcurl would read the URL short. The same
  holds for `url-resolve`'s reference (global-constraints, "Every check of a caller's string").
- **The transfer takes the parsed handle through `CURLOPT_CURLU`,** and pins every transfer
  with `PROTOCOLS_STR` and `REDIR_PROTOCOLS_STR`, as decision 3 asks. Both pins are held by a
  test that reads the transfer's options as data. A redirect test cannot: libcurl checks a
  followed URL against both, so either one alone hides the other's removal.
- **The version-rows rule gains a check.** Each case in the rows must answer differently in
  at least two of them. Otherwise it belongs among the shared answers, and a rows file could
  hide a shared case. `test-url` and `test-transfer` both hold it.


## Amendment, 2026-10-24: the caller checks, the engine parses (the M3 plan)

Decision 3 left M3 to settle which thread parses a request's URL. The maintainer chose on
2026-10-24.

- **Submit checks the URL on the caller's thread.** It runs `call-with-parsed-url` and the
  scheme check on the request's snapshot, the private copy the transfer sends, and frees that
  handle before submit returns. A refused URL raises there, before anything is queued.
- **The engine parses the same snapshot again,** on its own thread, and the transfer takes
  that handle through `CURLOPT_CURLU`. It frees it once the transfer is taken apart.
- **So every `CURLU` lives and dies on one thread,** and no native handle crosses between
  threads. Both parses read the same immutable copy with the same libcurl. The cost is a
  second parse per request.
- **Rejected:** handing the caller's `CURLU` to the engine, which saves the parse but moves a
  native handle across threads, and leaves a submit that fails after the parse to free it.
  Also rejected: parsing on the engine alone, which turns a bad URL from a raise at submit
  into a failed completion.
