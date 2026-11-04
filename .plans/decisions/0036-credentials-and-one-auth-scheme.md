# ADR-0036: Credentials, and one auth scheme per request

- **Status:** Accepted; amended 2026-11-02, after the M7 plan's review: decision 3's reach, and
  the bytes and headers credentials meet; amended 2026-11-02, measured through the engine, with
  three answers on the bytes and one on resends (M7 slice 2); amended 2026-11-03: no printed
  text carries a caller's misplaced value or a refused URL (M7 slice 3)
- **Date:** 2026-11-02
- **Scope:** chez-curl v1, a server's auth, in `(curl)` and `(http-client)`, from M7
- **Settles:** how a caller gives server credentials, and which schemes a request may pick, a
  streamed one among them. The maintainer chose on 2026-11-02, the recommended option each time,
  from the M7 plan's probe ([research](../research/m7/auth/)). ADR-0033 had settled Basic, Bearer
  and Digest. A proxy's credentials are ADR-0037's.
- **Related:**
  - [ADR-0033](0033-m7s-scope.md): M7's scope;
  - [ADR-0009](0009-typed-escape-hatch.md): `USERNAME`, `PASSWORD` and `USERPWD` are owned as the
    URL's twins;
  - [ADR-0032](0032-a-streamed-body-is-sent-at-most-once.md): a streamed body is sent at most
    once;
  - [ADR-0027](0027-no-downgrade-unless-allowed.md) and the M5 plan: credentials across a
    redirect.

## Context

Today credentials reach libcurl in the URL's userinfo, or in a caller's `Authorization` header.
A C probe that steps a multi handle as the engine does ran on 7.85.0, Ubuntu's 8.5.0 with
OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0, two runs each, against a stand-in that checks
Digest with its own arithmetic. No outcome differed between runs.

- **Where credentials come from:** with no userinfo in the URL, `USERNAME` and `PASSWORD` set
  both send the same Basic bytes on all five, empty values among them. Mixed with the URL's
  userinfo they differ: 7.85.0 in 19 cells of 168 and 8.23.0 in 50, against 8.5.0 and 8.20.0,
  which agree. The URL's userinfo is percent-decoded before it is encoded; an option's bytes go
  out as given.
- **`HTTPAUTH`:** unset, `BASIC` and `BEARER` send credentials on the first request and never try
  a second. Every other value sends a bare first request, then at most one more, in the scheme it
  picks. A Bearer token goes out only when `HTTPAUTH` holds `BEARER`.
- **Digest:** MD5, MD5-sess, SHA-256 and SHA-256-sess work on all five; SHA-512-256 on 8.20.0 and
  8.23.0 alone. `auth-int` on a `POST` hashes an empty body on every lane, so the server refuses
  it. A wrong password ends with a final 401 and code 0. No Digest state crosses fresh easy
  handles. On 8.23.0 a UTF-8 user name is sent percent-encoded but hashed raw, so the server
  refuses it.
- **Bodies across a round:** `ANY` sent a whole body twice, and failed a streamed one with 65.
  `DIGEST` sent a `Content-Length: 0` request first, then the body once, reading a streamed body
  once without a seek; but its second request reused a connection an earlier transfer had pooled
  on 7.85.0, 8.5.0 and 8.20.0, which `FRESH_CONNECT` does not cover, and over HTTP/2 a streamed
  Digest `POST` hung on 7.85.0.
- **An HTTP/2 401 before the body is sent whole ends the transfer** on every lane, within 8 ms,
  or at the producer's next piece while the read is paused, unlike the 3xx that never ends on
  8.20.0 and 8.23.0.

The maintainer's Mac ran it on 2026-11-02, twice, against Apple's 8.7.1, with no split: every
credentials cell as on 8.5.0 and 8.20.0; SHA-512-256 and a UTF-8 Digest user name work; a
streamed body under `ANY` fails 26 there, where the Linux libcurls fail 65.

## Decision

1. **A credentials field carries a user and a password, and sets `USERNAME` and `PASSWORD`
   both.** A request that gives it beside userinfo in its URL is refused when submitted. The URL's
   userinfo alone stays allowed, as today.
2. **A request names one scheme: Basic, Digest or Bearer.** It never names a set, nor libcurl's
   `ANY` or `ANYSAFE`. A Bearer request carries its token, sent by `XOAUTH2_BEARER`.
3. **A streamed request takes Basic or Bearer alone,** each one request. Digest is a round, and
   is refused beside a streamed body or a streamed response, by a rule of its own: today's
   refusal of the hatch's auth rounds fires beside a streamed response alone, so a streamed body
   beside the hatch's `HTTPAUTH` passes today.
4. **Credentials never write a header of their own, nor meet a caller's.** Every credentials
   string refuses NUL, CR, LF and each byte the header rule refuses: libcurl writes a Bearer token
   raw, and escapes only `"` and `\` in a Digest user name, so CR LF in either injected a header
   on the five lanes, 8.23.0 percent-encoding the Digest name. Credentials beside a caller's
   `Authorization` header are refused: libcurl dropped its own Basic and Bearer for the caller's,
   and sent both beside Digest ([review](../research/m7/review/)).

## Rejected

- **The field winning over the URL's userinfo:** a rule chez-curl would apply by stripping the
  userinfo, beside one the caller can see by reading the request.
- **URL userinfo alone:** no way to name Digest or Bearer.
- **Digest beside a stream:** its second request rides a pooled connection, and it hung over
  HTTP/2 on 7.85.0.
- **`ANY`:** it sent a whole body twice.

## Consequences

- `USERNAME`, `PASSWORD`, `HTTPAUTH`, `XOAUTH2_BEARER` and `AWS_SIGV4` become owned, with their
  other twins: `AWS_SIGV4` set after `HTTPAUTH` Basic replaced it with a signature (review).
- What varies by version, the Digest algorithms and 8.23.0's UTF-8 user name, is pinned in a
  per-version table and documented.
- Across a redirect to another origin the high level drops the credentials field as it drops an
  `Authorization` header (the M5 plan). The fields' shapes are the M7 plan's.

## Amendment, 2026-11-02: measured through the engine, the bytes and the resends (M7 slice 2)

M7 slice 2 ran these questions again through chez-curl's engine, credentials set by the hatch on a
prototype, on the five Linux libcurls, two runs each, and three of its eight items once more
under the memory gate's Valgrind on 8.5.0, whose 474 transfers ended as they did natively
([research](../research/m7/slice2/)). What it adds, and corrects:

- **Both parts empty is not alike:** 8.23.0 sends nothing for `USERNAME ""` with `PASSWORD ""`,
  nor for `XOAUTH2_BEARER ""`, and ends 401 after one bare request; the other four send `Basic
  Og==`, a Digest `username=""`, and `Bearer `, and over HTTP/2 no lane's empty token reached the
  server. The Context's "empty values among them" holds for one empty part beside the other.
- **Digest to a server that never challenges sends a `post` twice:** the bare probe, with no body,
  is answered 200, then the request goes again with its body, on all five. Documented.
- **What decision 3 prevents:** a streamed response under Digest published the probe's 401 head
  while the transfer ended 200, on all five; a streamed body under Digest over HTTP/2 failed 28 at
  its timeout on 7.85.0.
- **A wrong password ends with the server's 401 and code 0,** unless the hatch sets
  `FAILONERROR`, which makes it 22.
- **8.23.0 percent-encodes every byte of a Digest user name outside 0x20 to 0x7E,** a UTF-8 name
  among them, and hashes the raw bytes, so a server that checks the hash refuses it; the other
  four send the bytes raw. No lane sends `username*=`. Pinned by version.
- **Lengths:** 8 KiB passes everywhere; 64 KiB over HTTP/1.1 alone, failing 55 over HTTP/2 (56 on
  7.85.0) with nothing sent; 1 MiB fails 27 or 100 by version with nothing sent, but for a Digest
  password, of which only the hash goes; 8,000,001 bytes is refused as the option is set, 43. No
  rule of chez-curl's caps a length; this is documented.
- **The twins measured:** `AWS_SIGV4` set after `HTTPAUTH` replaces every scheme with a signature,
  so it is owned, as the Consequences say. `MAXREDIRS` counts each auth round as a follow: at 0,
  Digest stops after its probe, 47. `FAILONERROR`, `AUTOREFERER`, which adds a `Referer` to
  Digest's second request, `KEEP_SENDING_ON_ERROR`, `UNRESTRICTED_AUTH`, which reaches libcurl's
  own follow alone, and `DISALLOW_USERNAME_IN_URL` stay the hatch's, documented; `LOGIN_OPTIONS`,
  `SASL_AUTHZID`, `SASL_IR`, `SERVICE_NAME`, and `NETRC_FILE` without `NETRC`, changed nothing.
- **A redirect within one origin whose `Location` holds userinfo,** beside credentials: libcurl
  sent the field's credentials on all five. The high level keeps credentials within an origin, so
  the hop is refused as it is submitted, `credentials-beside-userinfo`, and the call fails.

**Decided by the maintainer, 2026-11-02,** each the recommended option:

5. **Credentials strings are UTF-8:** the user, the password and the token, as the hatch's strings
   are, and as RFC 7617 and RFC 7616 name. The plan had read them as Latin-1, by the header rule.
6. **No credentials string holds a control byte,** 0x00 to 0x1F or 0x7F, `credentials-bytes`,
   and a Basic user name holds no `:`. This replaces decision 4's "NUL, CR, LF and each byte the
   header rule refuses": CR LF wrote a header of its own, and the other control bytes went out raw
   over HTTP/1.1, an HTTP/2 server dropping the field, a bare LF failing 43 over HTTP/2 from
   8.5.0. For a Basic password, which base64 carries, the rule is stricter than it needs to be.
7. **Empty credentials are refused,** `credentials-empty`: a Bearer token `""`, and Basic or Digest
   with the user and the password both `""`. One empty part beside the other goes out alike on all
   five, and stays allowed.
8. **Every transfer sets `MAXREDIRS` 30, and the hatch cannot:** libcurl counts each follow inside
   a transfer against it, an auth round, a `stale=true` round and a 417's resend of a caller's
   `Expect: 100-continue` alike, but never its retry of a dead or refused connection (7.85.0
   `transfer.c:1583-1593`, 8.20.0 `http.c:1154-1165`, read in source by the slice's review). Against a server that answers 417, or `stale=true`, for ever,
   7.85.0 at its default, -1, made about 90,000 and 43,000 requests in 5 s, until its timeout,
   and with no `timeout-ms` would never stop; at 30 it stops at 31 requests with 47, as 8.5.0 and
   later do at their default, 30, and a Digest round still ends 200 in two
   ([research](../research/m7/slice2/), its `MAXREDIRS` section). A hatch `MAXREDIRS` of 0 had
   ended Digest after its probe. Nothing public follows a redirect, so the count reaches the follows
   inside a transfer alone.

**As built** (the slice's build and review):

- **What the field refuses beside userinfo,** by what `curl_url` reports, on each of the five
  lanes, the builder's runs and mine alike ([`verify/`](../research/m7/slice2/verify/)): 7.85.0 reports
  neither a user nor a password for `http://@h/` and `http://:@h/`, which pass beside the field
  and send its credentials; 8.5.0 and later report `""` there, and refuse them. `http://:p@h/`,
  `http://u@h/` and `http://u:@h/` are refused on all five.
- **A refusal's value** is `(SCHEME PART)` for the byte and empty rules, `(SCHEME user)` when
  both parts are empty, and `SCHEME` for the rules beside; a wrong shape's irritant is the symbol
  `credentials`, so a secret given in a wrong shape is never handed on. **Nothing prints the
  credentials:** the request, its plan, the live transfer, the engine, the token, the mailbox and
  the high level's exchange are opaque, so a token handed to an assertion as its irritant prints
  its type alone, and `record-rtd` raises on each. The review found the token
  printing its request's password, and another live request's token through the engine's table;
  a URL's userinfo and an `Authorization` header had printed so before the field.
- **A 417's resend needs a connection libcurl keeps:** 7.85.0 and 8.20.0 resend inside the
  transfer only when the connection is not to close (`lib/http.c`, `!conn->bits.close`), so a
  server that answers 417 with `Connection: close` ends the transfer at its 417. Measured with
  curl's tool on 8.20.0: 51 requests, then 47, on a kept connection; one, ending 417, on a closed
  one ([`verify/`](../research/m7/slice2/verify/)). A test of the loop needs a server that keeps
  the connection while the body never comes, which `node:http` cannot: the origin's raw face
  serves it.
- **The Mac's `make test` on 8.7.1,** at the slice's PR: a UTF-8 Digest user name given by the
  field went out raw and verified; every empty-userinfo URL was refused, as from 8.5.0; a 1 MiB
  password or token failed 100 with nothing sent, as on 8.20.0
  ([log](../research/m7/slice2/results/mac-8.7.1-make-test.log), and a second run of test-auth,
  [alike](../research/m7/slice2/results/mac-8.7.1-test-auth-2.log)).

## Amendment, 2026-11-03: no printed text carries a misplaced value or a refused URL (M7 slice 3)

M7 slice 3's review and its fix round found three more ways a secret reached a condition's
printed text, past the records this ADR made opaque. Each reproduced on Guix's 8.20.0
([review](../research/m7/slice3/review/), [verify](../research/m7/slice3/verify/)):

- **A value where a key belongs:** `unknown-key` named it, so a proxy URL, or a credentials list,
  given without its key printed its password, at both levels, nine cases of nine.
- **A raw record accessor handed something else:** Chez's own check names what it refused, so
  `(curl-request-url "http://u:PW@h/")` printed `"http://u:PW@h/" is not of type #<record type
  curl-request>`; the same for every public accessor of the request, the response and the high
  level's response.
- **A URL refused at submit:** `scheme-not-http` and a parse failure carried the whole URL as
  their irritant, `ftp://u:PW@h/` among them.

The fix round names a misplaced value by its kind wherever it could hold a secret, and a
header value's refusal by its header's name. **Decided by the maintainer, 2026-11-03, the
recommended option,** for the other two, on this slice: every public accessor of the request,
the response and the high level's response checks its argument and names a wrong one by its
kind; and a refused URL's message and irritants name its field, never the URL, while
`curl-url-error-input` still gives the string back to code that asks for it (ADR-0008, amended).

**As built** (M7 slice 3's two fix rounds): `shown-value` names a misplaced value by its kind,
keeping symbols, numbers, booleans, chars and lists of those, and `shown-key` keeps a symbol
alone; `checked-accessor` wraps each public record and condition accessor, its message "not a
request", "not a response" or the like, its irritant the wrong argument's kind: 78 exports had
printed a password handed in their place, none after. `libcurl-info`, which the conditions
library imports, holds its own copy of the rule, held alike by the suite.
`tests/test-printed.sps` writes out a row for every export of `(curl)`, `(curl unsupported)` and
`(http-client)`, 186 in all, so a new export fails until it has one, and calls each with a URL
holding a password ([build](../research/m7/slice3/build/), [verify](../research/m7/slice3/verify/)).
