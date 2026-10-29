# ADR-0029: A fragment is set by writing the URL, then parsing it whole

- **Status:** Accepted; amended 2026-10-28: a `Location`'s bytes are encoded by the same rule before they are resolved; measured on the Mac, 2026-10-29
- **Date:** 2026-10-28
- **Scope:** chez-curl v1, `(curl)`'s `curl-url-with-fragment`, and so `(http-client)`'s two
  fragment rules for a redirect, from M5 slice 2; and, by the amendment, `curl-url-resolve`'s
  bytevector reference, a redirect's `Location`
- **Settles:** how `curl-url-with-fragment` sets a fragment. M5 slice 2's measurement raised
  it; the maintainer chose on 2026-10-28, the recommended option.
- **Related:**
  - [ADR-0008](0008-curl-url-only.md): `curl_url` parses every URL a caller hands chez-curl;
  - [ADR-0028](0028-params-written-then-parsed-whole.md): a query appended the same way;
  - the M5 plan, §3.1, §3.4 and §5.1.

## Context

The M5 plan had `curl-url-with-fragment` set the fragment by `curl_url_set`, for §3.4's two
rules: a `Location` that is `#` and a fragment alone keeps the URL and sets its fragment, and a
reference with no fragment takes the URL's own (RFC 9110 §10.2.2). Slice 2 measured it first
([research](../research/m5/location/)), through `fragment.c`, on 7.85.0, Ubuntu's 8.5.0 with
OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0: three URLs, one with no fragment, two with
one, each given twenty fragments, then each cleared, 63 lines, each fragment set four ways. The
two 8.5.0 builds answered alike.

- **The part set with no flags stores the bytes unchecked,** on all five: a space, a tab, a CR,
  0x01 and 0x7F land in the URL raw, and a byte above 0x7F stays raw, so a header's Latin-1
  byte comes back as bytes that are not UTF-8. The hex case moves, as a query's does: `%E9`
  becomes `%e9` on 7.85.0, 8.5.0 and 8.20.0, and `%e9` becomes `%E9` on 8.23.0.
- **The part set with `CURLU_URLENCODE` encodes `%` too,** and every reserved character, so
  `%e9x` becomes `%25e9x`, another fragment; in lower-case hex on 7.85.0 and 8.5.0, upper on
  8.20.0 and 8.23.0.
- **The URL written with the fragment and parsed whole answers alike on all five:** each byte
  kept, the hex case as given, a byte above 0x7F raw, a `#` inside the fragment kept. A space,
  a tab, a CR, 0x01 and 0x7F are refused, with 3, `MALFORMED_INPUT`, on 8.5.0 and 8.20.0, and
  with 20, `BAD_FRAGMENT`, on 7.85.0 and 8.23.0. A `#` with nothing after it gives no fragment.
- **`#F` resolved against the URL varies most:** 7.85.0 and 8.5.0 drop the last segment and
  the query, refuse a tab, a CR, 0x01 and 0x7F, encode a space and a byte above 0x7F in lower
  case, and keep the case of hex given; 8.20.0 and 8.23.0 keep the URL, encode a space, a tab,
  a CR, 0x01, 0x7F and each byte above 0x7F in upper case, and raise hex given in lower case.

## Decision

1. **`curl-url-with-fragment` writes the new URL, then has `curl_url` parse it whole.** From one
   parse of the URL it reads `url` and `fragment` back by `curl_url_get`, takes the fragment,
   with its `#`, off the end of the URL, then adds `#` and the new fragment, and parses that
   string whole, as `url-normalize` does, and answers what `curl_url_get` gives back. `#f`, or
   an empty fragment, adds no `#`: the answer has none.
2. **A bytevector, a header's bytes, is encoded by chez-curl first:** each byte at or below
   0x20, 0x7F, and each byte above 0x7F, as `%` and two upper-case hex digits; every other byte
   kept, `%` and `#` among them. 8.20.0 and 8.23.0's own resolution of `#F` encoded each such
   byte the probe gave it, and kept each other. A 0x00 is refused as `embedded-nul`, as a
   bytevector reference's is (the M5 plan, §3.1).
3. **A string comes as a URL holds it:** chez-curl encodes nothing, sends it as UTF-8, and the
   whole parse refuses what `curl_url` refuses, a space among them. So the URL's own fragment,
   as `curl-url-part` gives it, goes back as it came, raw UTF-8 and its hex case kept.

### Rejected

- **`curl_url_set` of the part, with no flags, as the plan had it.** A redirect's `#a b` would
  put a raw space in `http-response-url`, which `curl-url-part` then refuses; a header's
  Latin-1 byte would be refused as `not-utf-8`; and the hex case would differ by libcurl.
- **`curl_url_set` of the part with `CURLU_URLENCODE`.** It changes a fragment already encoded,
  `%e9` to `%25e9`, and its hex case differs by libcurl.

## Consequences

- **A redirect's fragment, and the URL's own carried to it, read alike on every libcurl,**
  but for a refusal's code. Hex given in lower case stays lower, where 8.20.0 and 8.23.0's own
  resolution of `#F` would raise it.
- **Every URL is still parsed by `curl_url`** (ADR-0008, decision 1): the string chez-curl
  writes holds only what `curl_url_get` gave back and the fragment.
- **The string is written by a pure function, and the bytes encoded by another,** each driven
  by tables in `test-url-location`: the encoder over every byte, against the whole complement
  of the kept set (`traps.md`).
- **`test-url-location` holds the fragments live:** the probe's three URLs, each with its
  twenty fragments as bytes and as the strings their text makes, and `#f`, 120 cases. A
  version row in `known-url-location-verdicts.sexp` holds each string's refusal code, 3 or 20;
  every other answer is shared by the four Linux versions.

## Amendment, 2026-10-28: a `Location`'s bytes are encoded by the same rule before they are resolved

Slice 2's review found that `curl-url-resolve` handed a bytevector reference's bytes to libcurl
as they were, and that libcurl treats a raw byte above 0x7F by where it sits: a relative
reference's comes back encoded, as `%e9` or `%E9` by version, but an absolute URL's comes back
raw, so `/caf\xE9` was followed and `http://h.example/caf\xE9` refused as `not-utf-8`, the
refusal decision 2's encoding removed for a fragment. The review measured it on three libcurls;
slice 2 then measured it on the five Linux libcurls
([`results/encoded-*.log`](../research/m5/location/results/), `encoded.sps`), 45 `Location`
values, each resolved raw and encoded first:

- **Raw,** 16 of the 45 answer differently by version, and 5 are refused as `not-utf-8`: a
  Latin-1 byte in an absolute URL's path, query, fragment and user, and in a host.
- **Encoded first,** 3 answer differently by version, `javascript:` and a bad IPv6 host, which
  libcurl refuses by version either way, and `%e9` given in a relative path, whose hex case
  8.20.0 and 8.23.0 raise; and 1 is refused as `not-utf-8`, the Latin-1 host, since libcurl
  decodes a host's `%XX`. Raw, 0x01 and 0x7F in a relative path were refused on 7.85.0 and
  8.5.0 and encoded on 8.20.0 and 8.23.0; in an absolute URL, 0x01, 0x7F, a tab and a space
  were refused on all five, with 25 on 7.85.0 and 8.23.0 and 3 on 8.5.0 and 8.20.0. Encoded
  first, each is followed on all five.

The maintainer chose to encode, the recommended option:

4. **`curl-url-resolve` encodes a bytevector reference by decision 2's rule before libcurl sees
   it:** each byte at or below 0x20, 0x7F and each above 0x7F as upper-case `%XX`, every other
   kept. Both of `(curl)`'s functions then read a header's bytes one way, and libcurl is handed
   ASCII alone: the UTF-8 rule keeps its one exception, header strings (global-constraints),
   with no second for a bytevector. A refusal still names the bytes read as Latin-1.

### Rejected

- **Resolving the raw bytes, and recording the asymmetry.** A server that writes its own host's
  URL absolute, with a Latin-1 path, would fail every call that follows it, where the same path
  written relative is followed; and 16 of the 45 values measured would answer by version.

### Consequences

- **`test-url-location`** gains the review's eight values, a Latin-1 byte in an absolute URL's
  path, query, user and fragment, behind a network path and a query alone, and a control byte
  and a space in an absolute URL: 170 cases, of which 146 are shared by the four Linux versions,
  where 133 of 162 were before.
- **`test-redirect`** follows 0x01, 0x7F and a Latin-1 path, relative and absolute, alike on
  every libcurl, where its rows pinned 0x01 and 0x7F as refused on 7.85.0 and 8.5.0.
- **The encoder is `encoded-bytes`,** named for both its uses; it was `fragment-encoded`.
- **The Mac, 2026-10-29:** Apple's 8.7.1 ran `encoded.sps` on the built tree, where
  `curl-url-resolve` encodes a bytevector itself, so its raw and encoded columns give one answer,
  as the probe's header says, and the raw column measures nothing there. Encoded first, all 45
  answer as 8.5.0's ([results/encoded-mac-8.7.1.log](../research/m5/location/results/encoded-mac-8.7.1.log)).
  Its fragment probe answers as 8.5.0's, all 54 lines: setting the part stores its bytes
  unchecked, and lowers its hex case ([results/mac-8.7.1.log](../research/m5/location/results/mac-8.7.1.log));
  and `test-url-location`'s 8.7.1 row is 8.5.0's answers.
