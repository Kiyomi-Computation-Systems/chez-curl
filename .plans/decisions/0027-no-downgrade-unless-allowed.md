# ADR-0027: A redirect from `https` to `http` is refused unless the caller allows it

- **Status:** Accepted
- **Date:** 2026-10-27
- **Scope:** chez-curl v1, `(http-client)`'s redirect policy, from M5
- **Settles:** whether the high level follows a redirect that leaves TLS. The M5 plan's review
  raised it; the maintainer chose on 2026-10-27, the recommended option.
- **Related:**
  - [ADR-0008](0008-curl-url-only.md), amended 2026-10-27: M5 resolves a redirect's `Location`
    itself, and compares origins by scheme, host and port;
  - [ADR-0018](0018-ca-file-is-the-only-anchor.md): a request trusts only what its caller names;
  - [ADR-0025](0025-the-high-levels-surface.md), the high level's surface.

## Context

The M5 plan's draft followed a redirect from `https` to `http` as one more change of origin,
dropping the caller's credential headers there. An adversarial review of the plan (Opus,
read-only) pointed out what that still sends in cleartext: a 307 or 308 keeps the method and
the body, a `post`'s among them, and every header the call named but those the origin rule
drops. curl's `-L`, Python's `requests` and Go follow such a redirect. chez-curl's TLS records
lean the other way: a request trusts only the CA its caller names (ADR-0018).

## Decision

1. **A redirect from an `https` URL to an `http` one raises** `&http-redirect-error`, reason
   `insecure-redirect`, carrying the response that named it, unless the call allows it.
2. **A session key, and a call key, `allow-downgrade`,** a boolean, `#f` by default, allows it.
   An allowed downgrade is then followed as any change of origin is.

### Rejected

- **Following it, as curl and the browsers do.** A body and the call's other headers would go
  out in cleartext, to a URL the server named, with no sign to the caller.

## Consequences

- **A caller meets the refusal by name,** and opts in where the downgrade is expected.
- **`http` to `https` is followed,** an upgrade, as a change of origin.
