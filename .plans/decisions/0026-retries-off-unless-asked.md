# ADR-0026: Retries are off unless a session or a call asks for them

- **Status:** Accepted; amended 2026-10-28: libcurl resends a stream HTTP/2 refused (M5 slice 3); amended 2026-10-28: a retry that runs out of time answers what it retried; amended 2026-10-28: only when the retry sent nothing, and statuses from 400 to 599
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

## Amendment, 2026-10-28: libcurl resends a stream HTTP/2 refused (M5 slice 3)

The plan's review read in libcurl's source that it resends a request on a reused connection that
died before any response byte, a `post` among them. M5 slice 3 measured a second resend of its
own ([research](../research/m5/retry/)): a server that answers each HTTP/2 stream with
`RST_STREAM`, `REFUSED_STREAM`, which says the request was not processed, counted every
request six times, on 7.85.0, 8.5.0, 8.20.0 and 8.23.0, a `post`'s as a `get`'s, before libcurl
failed it with 56; the request size sums the six. So "off adds no attempt" holds of chez-curl
alone, as decided, and a policy's attempts multiply libcurl's: a `get` retried 3 times can reach
such a server 18 times. M8's documentation says so (the M5 plan, §10, amended).

## Amendment, 2026-10-28: a retry that runs out of time answers what it retried

M5 slice 3's review found that a retry was taken whenever its wait ended before the call's
bound, however little time that left: a 503 with `Retry-After: 4` at 1 s into a 5 s bound
waited 4 s, and the retry then had about 0 ms, so the call raised `&http-timeout`, and the 503
was lost, since a retried response joins no history. The review showed it on the core, by
tables.

**Decided by the maintainer, 2026-10-28, the recommended option: when the call's bound passes
during a retry's wait or its next transfer, the call ends as it would with no policy.** That
is, when the submission finds no time left for the retried request, or the retried transfer
fails with the bound's 28, the call answers the retried response, or raises the retried
failure, compounded with `&http-exchange` as every failure of a call is, without
`&http-timeout`. The step keeps its last retried outcome; a redirect, which starts a step, clears
it. A retried transfer that ends any other way goes through the rules as before.

- **So a policy can make a call slower; it means not to make it worse** (but see the next
  amendment). No floor of time left is set: a floor would be a number to guess, and a retry
  with little time left that succeeds is still taken.
- **Rejected:** raising `&http-timeout` with the retried outcome in a field of its own, which
  keeps the timeout but makes the caller dig for the answer; and a floor of time left after the
  wait, a guess.
- **A `Retry-After` of 0, or a date in the past, waits 0,** as the server asked; `attempts`
  bounds how many follow.

## Amendment, 2026-10-28: only when the retry sent nothing, and statuses from 400 to 599

The slice's scoped review of the amendment above found two holes in it, the first shown on the
core and live; its probes are kept and were rerun on 8.20.0 before the fix
([`research/m5/retry-review/`](../research/m5/retry-review/),
`results/before-round-2-guix-8.20.0.log`):

- **A retry that sent its request, then met the bound, raised the failure it retried, which
  could say nothing was sent.** A `post` refused at its connect, request size 0, is retried for
  any method; the retry sent the `post` to a listener that began 500 ms in and never answered,
  then met the 3000 ms bound, and the call raised the refused connect, code 7, size 0, though the
  listener had logged the whole `post`. ADR-0022 makes size 0 the public
  sign that nothing was sent, so a caller trusting it would send the `post` again.
- **A retried 3xx that ran out was answered unfollowed,** an answer the call gives nowhere
  else, since `make-http-retry` took any status from 200 to 599.

**Decided by the maintainer, 2026-10-28, each the recommended option:**

- **A retry that runs out answers what it retried only when the retry sent nothing:** the
  submission found no time left for it, or its transfer failed with the bound's 28 at a request
  size of 0. When that 28 carries a size above 0, or `#f`, unknown, the call raises it with
  `&http-timeout`, as it would with no policy for that transfer, true about the send.
- **`make-http-retry` takes statuses from 400 to 599 alone,** and refuses any other, so no
  retried response is a redirect.

So the amendment above's "never worse" holds of the last transfer: what the call reports about
it is true. It is no promise that a policy's call ends as one with no policy would. A retried
503 whose retry meets a 302 near the deadline, and cannot follow it, raises `&http-timeout`
where no policy would have answered the 503. And a raised failure's request size speaks for its
own transfer alone: a `get` whose first transfer sent its request and failed with 52, then
whose retry was refused at its connect, size 0, and whose next retry found no time left, raises
the refused connect, size 0, with two transfers counted, where no policy would have raised the
52 (the slice's third review, by tables, kept and rerun:
[`research/m5/retry-review/results/tables-guix-8.20.0.log`](../research/m5/retry-review/results/tables-guix-8.20.0.log)).
A method outside the policy's `methods` is never
retried after a send, so a default policy's `post` is not exposed; a caller reads
`&http-exchange`'s transfer count above 1 as "an earlier transfer may have sent the request".
