# ADR-0036: Credentials, and one auth scheme per request

- **Status:** Accepted
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

Apple's 8.7.1 has not run this probe.

## Decision

1. **A credentials field carries a user and a password, and sets `USERNAME` and `PASSWORD`
   both.** A request that gives it beside userinfo in its URL is refused when submitted. The URL's
   userinfo alone stays allowed, as today.
2. **A request names one scheme: Basic, Digest or Bearer.** It never names a set, nor libcurl's
   `ANY` or `ANYSAFE`. A Bearer request carries its token, sent by `XOAUTH2_BEARER`.
3. **A streamed request takes Basic or Bearer alone,** each one request. Digest is a round, and
   is refused beside a stream, as every auth round is today (ADR-0030's one transfer, one
   request).

## Rejected

- **The field winning over the URL's userinfo:** a rule chez-curl would apply by stripping the
  userinfo, beside one the caller can see by reading the request.
- **URL userinfo alone:** no way to name Digest or Bearer.
- **Digest beside a stream:** its second request rides a pooled connection, and it hung over
  HTTP/2 on 7.85.0.
- **`ANY`:** it sent a whole body twice.

## Consequences

- `USERNAME`, `PASSWORD`, `HTTPAUTH` and `XOAUTH2_BEARER` become owned, with their twins;
  `stream-with-rounds` keeps refusing Digest beside a stream.
- What varies by version, the Digest algorithms and 8.23.0's UTF-8 user name, is pinned in a
  per-version table and documented.
- Across a redirect to another origin the high level drops the credentials field as it drops an
  `Authorization` header (the M5 plan). The fields' shapes are the M7 plan's.
