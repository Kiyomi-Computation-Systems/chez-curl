# ADR-0009: A typed escape hatch for unwrapped options, in the low level only

- **Status:** Accepted; amended 2026-10-23, a private test seam held to its rules (M2 slice 2); amended 2026-10-24, the TLS fields' options and twins (M2 slice 3); amended 2026-10-24, `QUICK_EXIT` is owned (M3); amended 2026-10-25, the test seam is a submit (M3 slice 2); amended 2026-10-25, `QUICK_EXIT` is owned, as built (M3 slice 3); amended 2026-10-26, M4's owned options (the M4 plan); amended 2026-10-26, M4 slice 1's owned options, as built
- **Date:** 2026-10-04
- **Scope:** chez-curl v1, `(curl ...)` only
- **Settles:** D3 (brief §10)
- **Related:**
  - brief §2 item 2 (callers never touch a handle), §3 and §9 risk 2 (caller code on the
    engine thread);
  - [ADR-0001](0001-bind-libcurl-directly.md) (the options API);
  - [ADR-0003](0003-libcurl-floor-7-85.md) (the protocol pin);
  - [ADR-0007](0007-one-repo-checked-seam.md) (the seam check);
  - [ADR-0008](0008-curl-url-only.md) (the parsed URL handle).

## Context

The brief recommended a raw `setopt` for options chez-curl does not wrap. It would live in
`(curl ...)` only, be documented as unsupported, and never be reachable from the high
level.

libcurl 8.20.0 describes 308 options, not counting 15 alias names, through the options
API ADR-0001 binds:

| Value type | Count |
|---|---|
| long | 115 |
| enumerated values | 18 |
| `off_t` | 7 |
| string | 92 |
| blob | 8 |
| `curl_slist` | 10 |
| object | 11 |
| callback pointer | 21 |
| function | 26 |

curl's documentation sets out what it does with the values it is given:

- **Strings are copied.** A string's storage "may be discarded or reused after
  `curl_easy_setopt` returns". The one exception is `CURLOPT_POSTFIELDS`, which the options
  API types as an object, not a string. Strings are limited to 8 MB.
- **Blobs set with `CURL_BLOB_COPY` are copied.**
- **String lists are not copied.** They must outlive the transfer.
- **Contents are not checked.** libcurl "does little to no verification of the contents of
  provided strings". A CR or LF can inject a header, and a NUL silently truncates.

The object, callback-pointer and function types hand raw pointers and callbacks across.
That threatens memory safety, and a callback would run caller code on the engine thread.

Two of the safe types still need guarding:

- **Two string options hold ADR-0003's pin.** `PROTOCOLS_STR` and `REDIR_PROTOCOLS_STR` are
  ordinary strings, and the deprecated `PROTOCOLS` and `REDIR_PROTOCOLS` are ordinary
  longs.
- **Callers never touch a handle** (brief §2 item 2). So a hatch cannot be "setopt on a
  handle".

## Decision

1. **The hatch is its own library, `(curl unsupported)`** (ADR-0010). It is not on
   ADR-0007's list of public libraries, so `make check-seam` fails if any
   `(http-client ...)` library imports it.
2. **It attaches options to a request record, not to a handle.** Each option is a name and a
   value. The engine applies them when it builds the transfer, after every option the
   binding sets itself.
3. **Each option is checked when it is attached, on the caller's thread,** against the loaded
   libcurl's own table (`curl_easy_option_by_name`):
   - **The name must be known to this libcurl.** An unknown name is refused, and the
     condition names it.
   - **The type must be one the binding can pass safely:** long, enumerated values,
     `off_t`, string, blob or string list. Object, callback-pointer and function options
     are refused.
   - **The value must match the type:**

     | Type | Value |
     |---|---|
     | long, enumerated values | an exact integer within C `long` |
     | `off_t` | a 64-bit signed integer |
     | string | a string |
     | blob | a bytevector |
     | string list | a list of strings |

   - **No string, and no element of a list, may contain NUL, CR or LF.**
   - **The option must not be one chez-curl owns or wraps.** The deny-list is compared by
     option id, so an alias name cannot slip past it. It holds:
     - `URL` and `CURLU` (ADR-0008);
     - `PROTOCOLS_STR`, `REDIR_PROTOCOLS_STR`, `PROTOCOLS` and `REDIR_PROTOCOLS`
       (ADR-0003);
     - `NOSIGNAL`;
     - every option a request field already sets, so each setting has one way in.
4. **The binding handles each value's lifetime.** libcurl copies strings during setopt, and
   blobs because they are passed with `CURL_BLOB_COPY`. The binding builds string lists
   itself and frees them only after the transfer completes.
5. **The hatch is unsupported surface.** It carries no compatibility promise. The
   documentation says what it checks, and that an option set through it can change behaviour
   chez-curl does not test.

### Rejected

- **No hatch in v1.** Callers would wait a release for any unwrapped option.
- **The brief's raw setopt.** It allows any type, including pointers and callbacks, and can
  break memory safety, the engine-thread rule and ADR-0003's protocol pin.

## Consequences

- **On 8.20.0 the hatch can reach 250 of 308 options, before the deny-list.** Those are the
  long, enumerated-value, `off_t`, string, blob and string-list ones. An option newer than
  the floor works only on a libcurl that knows it; elsewhere it is refused at attach time,
  by name (ADR-0003 decision 4).
- **Wrapping an option closes its hatch path automatically.** The "already wraps" part of the
  deny-list is derived from the request record's field table, and a test asserts that every
  field's option is on it.
- **Every refusal rule gets a test that watches it fire.** That includes an alias of a denied
  option, and a string carrying CR, LF or NUL.
- **The CR, LF and NUL refusal also blocks strings that legitimately contain them.** That is
  accepted for an HTTP-only hatch: a wrapped option is the way to set one.

## Amendment, 2026-10-23: a private test seam is held to these rules (M2 slice 2)

- **What was built.** M2 slice 2's builder added `perform-transfer-with` to
  `(curl private transfer)`. It sets options after the request's own, for tests no request
  field can reach:
  - an unknown option's refusal;
  - a setopt libcurl refuses;
  - a followed redirect, which shows that the headers come from the last request.
- **As built, it was the raw setopt this record rejects.** It took any option and any
  integer. The review showed what that allowed:
  - it set `PROTOCOLS` and `REDIR_PROTOCOLS` to -1, followed a redirect to
    `file:///etc/passwd`, and read the file;
  - it passed `WRITEFUNCTION` as 0, which ended in `invalid memory reference`.
- **Decided, by the maintainer: the seam is held to this record's rules, narrowed.**
  - It takes only long, enumerated-value and `off_t` options, with each value checked
    against its type. M2 needs no string, blob or string list option, so no address can pass.
  - Its deny-list is compared by id. It holds decision 3's options. It also holds the
    callable and its data, `WRITEFUNCTION` and `WRITEDATA`, plus `ERRORBUFFER`, and every
    option a request field sets.
  - **It also refuses each owned setting's twin:** an option with an id of its own that sets
    the same thing. `MAXFILESIZE` would undo the body limit's `MAXFILESIZE_LARGE`, `TIMEOUT`
    would undo `TIMEOUT_MS`, and `HTTPGET`, `POST`, `UPLOAD` and `PUT` would change the
    method that `NOBODY` sets. Decision 3 compares ids, and a twin has its own id, so
    decision 3 alone would pass it. **M4's public hatch must refuse twins too.**
  - The seam stays private, in `(curl private transfer)`. The public hatch,
    `(curl unsupported)`, is still M4's.

## Amendment, 2026-10-24: the TLS fields' options and twins (M2 slice 3)

- **The request's two TLS fields set four options** ([ADR-0018](0018-ca-file-is-the-only-anchor.md)).
  The CA file sets `CAINFO` and clears `CAPATH`. Verification sets `SSL_VERIFYPEER` and
  `SSL_VERIFYHOST` on every transfer. All four are field options, so the deny-list holds them
  through the field table, and a field may now name more than one option.
- **The CA file's twins are `CAINFO_BLOB` and `SSL_OPTIONS`,** decided by the maintainer.
  Measured beside a CA file with `CAPATH` cleared:
  - `CAINFO_BLOB` added its CA, on 7.85.0 and Ubuntu's 8.5.0 with OpenSSL;
  - `SSL_OPTIONS` with `CURLSSLOPT_NATIVE_CA` added the system store, on Ubuntu's 8.5.0 with
    GnuTLS.

  The seam's type rule already refuses `CAINFO_BLOB`. `SSL_OPTIONS` is an enumerated-value
  option, so before this amendment the seam took it. Its other bits are closed with it. M4
  can wrap any that are wanted as fields.
- **Verification has no twin among the options the hatch's types allow.** `PROXY_SSL_VERIFYPEER`,
  `PROXY_SSL_VERIFYHOST`, `DOH_SSL_VERIFYPEER` and `DOH_SSL_VERIFYHOST` verify other
  connections: a proxy's, whose policy is M4's, and a DNS-over-HTTPS server's. Each still
  reaches the seam. `SSL_CTX_FUNCTION` could replace OpenSSL's verification, and is a
  function, which no hatch takes.


## Amendment, 2026-10-24: `QUICK_EXIT` is owned (the M3 plan)

- **Every engine transfer sets `QUICK_EXIT` to 1 where the loaded libcurl knows it**
  ([ADR-0019](0019-a-stalled-lookup-does-not-stall-the-engine.md)). Turned off, a stalled
  name lookup holds the engine for up to 10 s on Ubuntu's 8.5.0. So it is an owned option,
  set with the pins, and the test seam refuses it, by id, like the rest of decision 3's list.
- **The multi handle's `CURLMOPT_QUICK_EXIT` is out of every hatch's reach.** The hatch
  attaches options to a request, never to a handle, and a multi option is no easy option.

## Amendment, 2026-10-25: the test seam is a submit (M3 slice 2)

- **`perform-transfer-with` went with M2's blocking path** (the M3 plan, §5.4). The seam is now
  `curl-engine-submit-with`, in `(curl private engine)`: a submit whose options
  `prepare-transfer` checks on the caller's thread, by the 2026-10-23 rules, before anything
  is queued, so each refusal raises at submit. The engine's thread sets them last, after the
  request's own, as `perform-transfer-with` did.
- **`QUICK_EXIT` is not yet among the owned options.** Slice 3 sets it on every engine
  transfer, and adds it to the list the seam refuses, by id.

## Amendment, 2026-10-25: `QUICK_EXIT` is owned, as built (M3 slice 3)

- **`QUICK_EXIT` is in `owned-option-names`,** after `NOSIGNAL`, among the options every
  transfer sets. Where the loaded libcurl knows it, the seam refuses it by id, as
  `owned-option`. The floor does not know it, so there it is `unknown-option`, as any name
  the library lacks. `test-transfer` writes out both answers.
- **No request turns it off.** A private constructor,
  `make-curl-engine-without-quick-exit`, makes an engine that leaves it out, or leaves out its
  multi handle's `CURLMOPT_QUICK_EXIT`, so `test-engine` can show the stall each prevents
  (ADR-0019, amended 2026-10-25). It is a test seam, as `make-faulty-curl-engine` is: no
  request, option or hatch reaches it.

## Amendment, 2026-10-26: M4's owned options (the M4 plan)

The M4 plan, revised after its review, adds to the owned options and twins, each built in its
slice:
- the body's options, `CUSTOMREQUEST`, `CONNECTTIMEOUT_MS` and `PROXY`, as request fields
  ([ADR-0023](0023-the-public-request.md), [ADR-0024](0024-what-a-transfer-reads-from-its-environment.md));
- `FOLLOWLOCATION`, left off: through a 301, 302 or 303, libcurl resends a custom method without
  its body (ADR-0023, amended 2026-10-26);
- every `PROXY_SSL_*` and `PROXY_CA*` option. The 2026-10-24 amendment left a proxy's
  verification to M4, and the maintainer chose libcurl's verified default until M7 (ADR-0024,
  amended 2026-10-26).

The hatch copies each value as it is attached, and applies the copy. `test-unsupported` writes
every owned option and twin out. The test seam, `curl-engine-submit-with`, retires into the
hatch in slice 4, which amends this record and global-constraints when it goes.

## Amendment, 2026-10-26: M4 slice 1's owned options, as built

`owned-option-names` in `(curl private transfer)` gained, as the M4 plan's amendment above
named, each refused by the test seam by id:
- **the new fields' options:** `method`'s `CUSTOMREQUEST`, beside its `NOBODY`; `body`'s
  `POSTFIELDSIZE_LARGE` and `COPYPOSTFIELDS`; `connect-timeout-ms`'s `CONNECTTIMEOUT_MS`; and
  the private `follow` field's `FOLLOWLOCATION`, which the two seam tests that set it now set
  through that field;
- **their twins:** `CONNECTTIMEOUT`; `POSTFIELDS`, `POSTFIELDSIZE`, `HTTPPOST` and `MIMEPOST`,
  another body, size or form; `INFILESIZE` and `INFILESIZE_LARGE`, an upload's size; beside
  `HTTPGET`, `POST`, `PUT` and `UPLOAD`, owned since M2;
- **the URL's twins, found in the options tables** (the M4 plan, §4.1): `PORT`, which replaces
  the URL's port, a long the seam took until now, and `REQUEST_TARGET`, its target on the
  request line;
- **every option that sets a proxy's TLS,** 23 in the tables of 7.85.0 to 8.23.0: the
  `PROXY_SSL_*` and `PROXY_CA*` options the amendment above names, and the rest of the `PROXY_`
  TLS settings, its version, ciphers, CRL, issuer, pinned key, client certificate and key, and
  TLS-SRP, any of which could loosen it or replace its trust, as ADR-0024 decided it must not be
  until M7.
- **two more, found by the slice's review,** longs the seam took: `CRLF`, which libcurl documents
  as converting each LF in what it sends to CRLF, a rewrite of the request's own body; and
  `HEADER`, which hands the response's head to the write callback with its body, where the body
  limit counts it.

Not yet owned, for slice 4's twin review of the string, list and blob options the hatch takes,
and of these the review named, unmeasured: `HTTP_TRANSFER_DECODING`, `HTTP_CONTENT_DECODING` and
`IGNORE_CONTENT_LENGTH`, which change the body and its limit; `CONNECT_ONLY`, which sends no
request; `TIMECONDITION`, `TIMEVALUE`, `TIMEVALUE_LARGE`, `RESUME_FROM`, `RESUME_FROM_LARGE` and
`TRANSFER_ENCODING`, which add headers the request never named; and the rest:
`CONNECT_TO`, `RESOLVE`, `UNIX_SOCKET_PATH` and `ABSTRACT_UNIX_SOCKET`, which send a connection
elsewhere; `HEADEROPT` and `PROXYHEADER`, slice 3's; and `COOKIEFILE` at `"-"`, which reads
stdin. `PROXY`, `NOPROXY` and `PRE_PROXY` come with slice 3's field.
