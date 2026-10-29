# ADR-0008: URLs are parsed, checked and resolved by libcurl's own URL API

- **Status:** Accepted; amended 2026-10-17: the measured verdicts become M2's tests; amended
  2026-10-19: the verdicts vary by version, so the suite holds shared answers and version
  rows; amended 2026-10-23 with what M2 slice 1 built, and with what M2 slice 2 changed; amended
  2026-10-24: the caller checks, the engine parses (M3); amended 2026-10-27: a redirect's
  `Location`, measured (the M5 plan), and on the Mac; amended 2026-10-27: a URL's parts,
  measured, and every answer UTF-8 or refused (M5 slice 1); amended 2026-10-28: the `Location`
  through chez-curl's own reading, and `localhost`, measured (M5 slice 2), and on the Mac
  (2026-10-29)
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

## Amendment, 2026-10-27: a redirect's `Location`, measured (the M5 plan)

M4 left redirects to M5, and the M4 plan and ADR-0023's amendment said M5 would follow them
"from `CURLINFO_REDIRECT_URL`". The M5 plan measured that first
([research](../research/m5/redirect-url/)): a C probe made one transfer with the options the
engine sets, its URL through `CURLOPT_CURLU`, the pins, and `FOLLOWLOCATION` off, through
`curl_easy_perform`, against a server
that wrote each `Location` byte for byte, on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with
GnuTLS, Guix's 8.20.0 and 8.23.0, 62 cases each. It printed `CURLINFO_REDIRECT_URL` beside the
first `Location` header, resolved by `curl_url_set` on the request URL's handle, as decision 4
does it.

- **Where libcurl's answer is a parsed URL, it is decision 4's resolution,** on all five, but
  for credentials on 8.23.0, below.
- **But libcurl's answer moves with the version where decision 4's does not:**
  - 7.85.0 and 8.5.0 give one only for a 3xx status; 8.20.0 and 8.23.0 for any status that
    carries a `Location`, 200 and 400 among them;
  - 8.23.0 drops credentials from it: the request URL's on a relative reference, and a
    `Location`'s own. The other four keep both, as `curl_url_set` does on all five.
- **libcurl hands back what `curl_url_set` refuses, as it came:** `http://[::1/x` and a port of
  99999 on all five, `foo://bar/x` on all five, and `javascript:alert(1)` from 8.5.0. 7.85.0
  resolves the last as a relative path. Bytes 0x01 and 0x7F come back raw on 7.85.0 and 8.5.0,
  where `curl_url_set` refuses them, and percent-encoded from 8.20.0, as `curl_url_set` encodes
  them there.
- **Variance both share:** a byte above 0x7F in a path is percent-encoded on all five, in
  lower-case hex on 7.85.0 and 8.5.0 and upper-case from 8.20.0, and a UTF-8 host comes back
  raw; and a lone `#only` drops the last segment and the
  query on 7.85.0 and 8.5.0, the `#s` row `test-url` already holds. No version gives a
  reference without a fragment the request's, which RFC 9110 §10.2.2 asks of a user agent.
- **Around the URL:** an empty or blank `Location` gives none, on all five; two `Location`
  headers fail the transfer with 8 on 8.20.0 and 8.23.0, and the first is taken on 7.85.0 and
  8.5.0; a 110,000-byte one fails with 27 on 7.85.0 and 8.5.0, and 100 from 8.20.0, as an
  oversized head does.

So, the M5 plan's design (§3.4), revising the M4 plan's: **the high level follows a redirect
from the first `Location` header's bytes, resolved by decision 4 against the URL it requested,
never from `CURLINFO_REDIRECT_URL`.** The status, the credentials and the refusals are then
chez-curl's rules, one on every libcurl, and the variance left is `curl_url`'s, which `test-url`
already pins by version. A header string is Latin-1, so the resolution takes its bytes as given:
`(curl)` exports one that takes a bytevector reference beside a string (the M5 plan, §3.1).

The plan's review then found, in the container on 8.20.0 ([research](../research/m5/review/)),
that a Latin-1 byte in a host or in the user info comes back raw from `curl_url_get`, whole and
by part, where `utf8->string` reads `caf\xe9` and `caf\xe8` as one string. So each URL
function refuses an answer that is not UTF-8, by a new reason, `not-utf-8`, rather than decode
it (the M5 plan, §3.1).

On the Mac, the maintainer ran the probe against Apple's 8.7.1 on 2026-10-27
([results/mac-8.7.1.log](../research/m5/redirect-url/results/mac-8.7.1.log)). It answered as
8.5.0 did on 56 of the 62 cases: a URL for a 3xx alone, credentials kept, `javascript:` and the
control bytes handed back raw, the last segment and the query dropped for `#only`, a path's
bytes in lower-case hex, and the first of two `Location` headers taken. The other six differ
three ways: an empty or blank `Location` reads as empty, not as 8.5.0's lone CR; a 110,000-byte
one fails with 100, as from 8.20.0, not 27; and `EFFECTIVE_URL` keeps the request's credentials,
as 7.85.0 and 8.20.0 do. Where libcurl's answer is a parsed URL, it is `curl_url_set`'s
resolution there too.

## Amendment, 2026-10-27: a URL's parts, measured, and every answer UTF-8 or refused (M5 slice 1)

M5 slice 1 adds two URL functions to `(curl)`, `curl-url-part` and `curl-url-append-query`,
and measured `curl_url_set` and `curl_url_get` first ([research](../research/m5/url-parts/)),
through C, on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0:
44 URLs read back by part, 56 appends with `CURLU_APPENDQUERY`, and 2 plain sets of a query.

- **libcurl decodes a host's `%XX`,** on all five: `http://caf%E9.example/` comes back as
  `caf`, the byte 0xE9 and `.example`, whole and as the host; `%C3` alone as a lone lead byte;
  `%41` as `A` and `%2E` as `.`. `%00` and `%2F` there are refused, 21. The user info, the
  path, the query and the fragment keep their `%XX`. A raw byte above 0x7F comes back as it
  was given, in every part of a whole URL.
- **So a string, which chez-curl sends as UTF-8, can come back as bytes that are not UTF-8.**
  Every function of `(curl private url)` now reads what `curl_url_get` gives back as strict
  UTF-8, and refuses anything else as `&curl-url-error`, reason `not-utf-8`, no code, naming
  the string it was given, as the M5 plan's review asked (above). That covers `url-normalize`,
  `url-resolve` and the scheme check a submit runs, which now takes the string it names: a
  submit of `http://caf%E9.example/` is refused on the caller's thread. Chez's decoders drop a
  leading U+FEFF, so the decode puts one back (traps.md).
- **Setting a part changes its hex case** (ADR-0028): lower on 7.85.0, 8.5.0 and 8.20.0, upper
  on 8.23.0; a whole URL keeps it on all five. So `curl-url-append-query` writes the URL and
  parses it whole, and reads its query back, or refuses the part as `query-not-kept`.
- **What else varies:** an empty user is absent on 7.85.0 and `""` from 8.5.0; an empty password
  is absent on 7.85.0, which also drops its `:` from the URL; an empty query is `""` on 7.85.0
  and 8.5.0 and absent from 8.20.0, the URL dropping its `?` on all five; and a space in a
  query, parsed whole, is refused with 3 (`MALFORMED_INPUT`) on 8.5.0 and 8.20.0, and 26
  (`BAD_QUERY`) on 7.85.0 and 8.23.0.
- **Alike on all five:** an explicit default port, a host's case and an IPv6 host's brackets
  are kept, `:080` becomes `:80`, a port of 0 is taken, and `CURLU_DEFAULT_PORT` gives 80 and
  443.
- **`tests/test-url-parts.sps` holds them,** in the shape `test-url` holds its verdicts: shared
  answers for 113 cases, and `tests/known-url-part-verdicts.sexp` with a row per version for
  the 6 that vary. It is a file of its own so that a version row for the Mac's 8.7.1, owed
  until it runs, fails only there. On the 36 URLs both ran, its parts answers agree with the C
  probe's `curl_url_get` on each Linux libcurl; the suite's other 5 URLs, `file:`, `ftp:`, two
  that hold U+FEFF and a port of 99999, and the space's codes, are the suite's own answers, as
  each lane printed them ([research](../research/m5/url-parts/results/printed-rows.log)).
- **The Mac, 2026-10-28:** Apple's 8.7.1 answered all 103 of the probe's lines as 8.5.0 did
  ([results/mac-8.7.1.log](../research/m5/url-parts/results/mac-8.7.1.log)), and
  `test-url-parts` printed 8.5.0's row for it, now the file's fifth; its `make test` passed every
  other suite, `test-http-client`'s 72 among them.

## Amendment, 2026-10-28: the `Location` through chez-curl's own reading, measured (M5 slice 2)

The M5 plan's §5.1 asked that the `Location` cases above resolve through chez-curl as the C
probe resolved them, byte for byte. Slice 2 measured it ([research](../research/m5/location/)),
on the same five libcurls: the 62 cases above, and `rel-abs` again from `localhost` and from
`[::ffff:127.0.0.1]`, 64 a lane. Each case ran twice in one run against one server: by the C
probe above, and by `probe.sps`, through an engine, as the high level makes a transfer, its
response's headers read as chez-curl reads them, by `curl_easy_nextheader`, each value a Latin-1
string. The first `Location` header, A to Z folded, was resolved from that string's bytes by
`curl_url_set` against the URL requested, flags 0.

- **All 64 agree, on each of the five:** the status, the first `Location`'s bytes, how many
  there were, and the resolution, byte for byte; and a failed transfer's code, 8 for two
  `Location` headers on 8.20.0 and 8.23.0, and 27 or 100 for 110,000 bytes, as above. The
  comparator, given five planted differences, one in each field it reads, caught each
  ([results/compare-control.log](../research/m5/location/results/compare-control.log)).
- **8.5.0's lone CR comes through chez-curl's reading too:** an empty or blank `Location` reads
  as `\r` there, which `curl_url_set` refuses with 3, and as empty on 7.85.0, 8.20.0 and
  8.23.0. 7.85.0
  resolves an empty one as it resolves `#only`, dropping the last segment and the query; 8.20.0
  and 8.23.0 answer the URL requested. The M5 plan's §3.4 answers either as no redirect.
- **No resolution of the 62 came back as bytes that are not UTF-8,** but every Latin-1 byte
  among them sat in a relative reference, which libcurl encodes: the path's came back as `%e9`
  or `%E9`, and the UTF-8 host raw. The slice's review found that a Latin-1 byte in an absolute
  URL, in its path, query, fragment or user, comes back raw, and was refused as `not-utf-8`. So
  a header's bytes are now encoded before they are resolved
  ([ADR-0029](0029-fragment-written-then-parsed-whole.md), amended 2026-10-28); a Latin-1 host
  is still refused, since libcurl decodes a host's `%XX`.
- **`localhost` reaches a server on 127.0.0.1,** on all five: by `localhost.c`, with the
  options the engine sets that bear on a connect, libcurl connected to 127.0.0.1 each time; and
  through the engine, which answered the server's 302. So does `[::ffff:127.0.0.1]`, at that
  address. A live test changes host by `localhost`.
- **A fragment set by `curl_url_set` is stored unchecked, and its hex case moves by version,**
  so `curl-url-with-fragment` writes the URL and parses it whole, as `curl-url-append-query`
  does ([ADR-0029](0029-fragment-written-then-parsed-whole.md), new).
- **`tests/test-url-location.sps` holds `curl-url-resolve`'s bytes and
  `curl-url-with-fragment`,** as test-url-parts holds slice 1's: 170 cases, 146 shared by
  7.85.0, 8.5.0, 8.20.0 and 8.23.0, and `tests/known-url-location-verdicts.sexp` with a row per
  version for the other 24. Of the 39 resolutions it shares with the probe, the port written as
  40001 and the empty value the one each probe sent, all 39 answer as the probe's did on 8.20.0
  and 8.23.0, which encode a relative reference's bytes as the suite now does; on 7.85.0 and
  8.5.0, all but the four the encoding changes, a byte above 0x7F in upper-case hex where they
  wrote lower, and 0x01 and 0x7F followed where they refused, and on 8.5.0 its lone CR, which
  the high level never resolves
  ([results/suite-vs-probe.log](../research/m5/location/results/suite-vs-probe.log)).
- **libcurl gives an IPv6 host without its zone ID,** on all five: `[fe80::1%25eth0]` and
  `[fe80::1%25eth1]` both read as the host `[fe80::1]`, and the zone as a part of its own,
  `CURLUPART_ZONEID`, kept in its case ([results/zoneid-*.log](../research/m5/location/results/)).
  The slice's review found the origin rule comparing hosts alone, so a call's credentials
  crossed zones. `curl-url-part` now reads `zoneid` too, and another zone is another host. An
  empty zone, `%25` inside one and `%30` read otherwise on 8.23.0.
- **The Mac, 2026-10-29:** the maintainer ran slice 2's probes against Apple's 8.7.1, on
  `feat/m5-slice-4`, which holds slice 2 ([results/mac-8.7.1.log](../research/m5/location/results/mac-8.7.1.log),
  [encoded-mac-8.7.1.log](../research/m5/location/results/encoded-mac-8.7.1.log),
  [zoneid-mac-8.7.1.log](../research/m5/location/results/zoneid-mac-8.7.1.log)):
  - all 64 cases agree there too, the C probe by `-lcurl` against `probe.sps`; the C probe's
    lines answer as 8.5.0's but for the six its redirect-URL run found on 2026-10-27, an empty
    `Location` read as empty, 100 for the 110,000 bytes, and `EFFECTIVE_URL` keeping the
    credentials;
  - `localhost` and `[::ffff:127.0.0.1]` reach a server on 127.0.0.1, as on the five;
  - the fragment probe answers as 8.5.0's, all 54 lines;
  - an IPv6 host comes back without its zone ID, the zone a part of its own, every line as
    7.85.0's and 8.5.0's: `FE80` kept in upper case, an empty zone read as `25`, and `%30`
    kept;
  - `test-url-location` printed 8.5.0's answers for its 24 varying cases, now the rows file's
    8.7.1 row, and every other suite of `make test` passed there.
