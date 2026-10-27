# ADR-0026: Retries are off unless a session or a call asks for them

- **Status:** Accepted
- **Date:** 2026-10-27
- **Scope:** chez-curl v1, `(http-client)`'s retry policy, from M5
- **Settles:** whether the high level retries a failed request by default. The maintainer chose
  on 2026-10-27, the recommended option.
- **Related:**
  - brief §6.2: retry with backoff is the high level's policy;
  - [ADR-0022](0022-codes-classed-as-condition-types.md): a failure's class, and its request
    size, which says whether a request was sent;
  - [ADR-0025](0025-the-high-levels-surface.md), the high level's surface.

## Context

The brief puts retry with backoff in the high level. ADR-0022 gave M5 what a policy reads:

- **the class** follows libcurl's code, and names what libcurl answered, never the cause: 56
  is a bad chunk size as well as a lost connection;
- **the request size** is 0 exactly when nothing was sent, so a retry then cannot repeat a
  request the server saw. On libcurl 8.7.0 and 8.7.1, the Mac's among them, a transfer that ran
  carries `#f`: whether it sent anything is unknown.

So a policy can tell a request never sent from one that was, and retry the second only for a
method RFC 9110 calls idempotent. Two defaults were offered: retries off unless asked, which is
how Python's `requests` and the curl tool behave; and safe retries on by default, up to 2, only
where the rules above allow.

## Decision

1. **A failure raises at once, and a status is answered,** unless the session or the call names
   a retry policy.
2. **A session takes a default policy, and a call may name its own,** or `#f` for none.

### Rejected

- **Safe retries on by default.** A failure would show only after the retries' backoff, and a
  test of a failure would need to switch them off. A caller who never asked for retries would
  find chez-curl's attempts added to libcurl's own resends, below.

## Consequences

- **What a policy retries is the M5 plan's design** (§3.5): which classes, which methods, which
  statuses, how `Retry-After` is read, and the backoff. A slice's measurements and review may
  revise it; this record fixes only that it is off unless asked.
- **A test of a failure needs no switch,** and a test of a retry names its policy.
- **Off means chez-curl adds no attempt; libcurl may still resend.** libcurl resends a request
  of any method, a `POST` and its body among them, on a fresh connection when a reused one died
  before any response byte, up to 5 times (`Curl_retry_request`, 7.85.0's `lib/transfer.c` and
  8.23.0's, read by the M5 plan's review, not measured). The request size sums those sends. M5
  offers no mode that never reuses a connection; the M5 plan carries it.
