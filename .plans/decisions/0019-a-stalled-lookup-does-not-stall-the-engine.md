# ADR-0019: A stalled name lookup does not stall the engine

- **Status:** Accepted
- **Date:** 2026-10-24
- **Scope:** M3's engine and every transfer it runs (the [M3 plan](../2026-10-24-m3-plan.md))
- **Settles:** what the engine does about libcurl's resolver thread, which blocks teardown
  while a lookup runs. The maintainer chose on 2026-10-24.
- **Related:** [ADR-0003](0003-libcurl-floor-7-85.md), whose rule makes anything newer than the
  floor optional, one feature at a time · [ADR-0009](0009-typed-escape-hatch.md), owned
  options · [ADR-0012](0012-engine-thread-owns-every-handle.md), the engine ·
  [ADR-0013](0013-collect-safe-blocking-calls.md), calls that can block · the M3 plan, §2

## Context

The M3 plan measured this before planning, on 2026-10-24, through Chez probes under
`build/verify/m3/measure/` (not kept; spike E1 commits its own). Each ran in Docker
`ubuntu:24.04`, where `/etc/resolv.conf` named `127.0.0.1`, and `nc -lku 127.0.0.1 53` read
every query and answered none. The libcurls were:
- the floor's 7.85.0 and Ubuntu's 8.5.0, with OpenSSL and with GnuTLS, under the CI stand-in's
  Chez 10.4.0;
- Guix's 8.20.0 under Guix's Chez 10.4.0, from `/gnu/store` mounted read-only.

Each probe ran one easy handle for `http://slow-name.example.com/` in one multi handle, with
`NOSIGNAL` 1. Every case ran twice, and the runs agreed within 25 ms.

- **Taking a resolving transfer apart blocks until the lookup ends.** Driven 300 ms, then
  removed and cleaned up, with `TIMEOUT_MS` at 60 s, in ms:

  | libcurl | `remove_handle` | `easy_cleanup` | `multi_cleanup` |
  |---|---|---|---|
  | 7.85.0 | 9,729–9,733 | 0 | 0 |
  | 8.5.0, OpenSSL | 9,724–9,744 | 0 | 0 |
  | 8.5.0, GnuTLS | 9,741–9,744 | 0 | 0 |
  | 8.5.0, either, with `QUICK_EXIT` 1 | 0 | 0 | 0 |
  | 8.20.0, with or without `QUICK_EXIT` | 0 | 0 | 9,749 |
  | 8.20.0 with `CURLMOPT_QUICK_EXIT` 1 | 0 | 0 | 0 |

  9.7 s is glibc's resolver giving up: two tries of 5 s, less the 300 ms already spent.
  The floor has no `QUICK_EXIT` (7.87.0), and `curl_easy_option_by_name` does not find it.
  8.20.0 joins its resolver threads when the multi handle is cleaned up. Its
  `CURLMOPT_QUICK_EXIT`, option 21 in its `multi.h`, stops that. 8.5.0 answers it
  `CURLM_UNKNOWN_OPTION`, 6.
- **A transfer's own timeout blocks inside `curl_multi_perform`.** With `TIMEOUT_MS` at 1000,
  driven to its end:

  | libcurl | code 28 at | longest single `curl_multi_perform` |
  |---|---|---|
  | 7.85.0 | 10,046–10,051 ms | 9,046–9,051 ms |
  | 8.5.0, either | 10,027–10,051 ms | 9,026–9,051 ms |
  | 8.5.0, either, with `QUICK_EXIT` 1 | 1,001–1,002 ms | 0 ms |
  | 8.20.0, with or without `QUICK_EXIT` | 1,000–1,001 ms | 0 ms |

  8.20.0's `multi_cleanup` then blocked 9,050–9,051 ms.

  On an engine, that one call holds the thread: every other transfer on it stops for 9 s.
  A plain binding would also stall every other thread's collection for longer than that.
  The plan measured it: a collection waits about 500 of the engine's loops (§2).
- **libcurl documents the trade.** `CURLOPT_QUICK_EXIT(3)`, 8.20.0: "1L meaning that when
  recovering from a timeout, libcurl should skip lengthy cleanups that are intended to avoid
  all kinds of leaks (threads etc.), as the caller program is about to call exit() anyway.
  This allows for a swift termination after a DNS timeout for example, by canceling and/or
  forgetting about a resolver thread, at the expense of a possible (though short-lived) leak
  of associated resources." `CURLMOPT_QUICK_EXIT(3)` says the same of a multi handle, "do not
  join threads when cleaning up this multi handle", and was added in 8.20.0.
- **Every recorded libcurl resolves on a thread.** Each row of `tests/known-libcurls.sexp` has
  the `AsynchDNS` bit. A libcurl without it resolves inside `curl_multi_perform` itself. A new
  row is a reviewed change (ADR-0017), so such a libcurl is seen before it is admitted.
- **The container cannot show any of it.** It has no `/etc/resolv.conf` and no network, so
  the same lookup fails at once: code 6, `CURLE_COULDNT_RESOLVE_HOST`, in 1 ms. Binding
  port 53 there, to stand in a server that never answers, is refused, `EACCES`.

## Decision

1. **Every engine transfer sets `QUICK_EXIT` to 1 when the loaded libcurl knows it.** It is
   looked up by name, as every option is, and set with the pins, before the request's own
   settings. Any answer but `CURLE_OK` is `setopt-failed`. On the floor, which lacks it, the
   transfer runs without it.
2. **Every engine's multi handle sets `CURLMOPT_QUICK_EXIT` to 1, on the engine thread, when
   it is made.** It goes through `curl_multi_setopt`, bound once for a long through
   `bind-variadic` (ADR-0001). `CURLM_UNKNOWN_OPTION` is accepted: that libcurl predates it.
   Any other answer but `CURLM_OK` refuses the engine before its thread runs a transfer.
   This applies decision 1 to the multi handle. It was measured after the maintainer chose
   "QUICK_EXIT where known", which it follows.
3. **The calls measured blocking are `__collect_safe`,** through `bind-blocking`:
   `curl_multi_perform`, `curl_multi_remove_handle` and `curl_multi_cleanup`, with
   `curl_multi_poll`. That is ADR-0013's decision 1, which binds whatever can block. It
   overturns ADR-0013's provisional decision 3 for `curl_multi_perform`. Spike E1 reruns the
   measurement and amends ADR-0013 (amended 2026-10-24).
4. **`QUICK_EXIT` is an owned option** (ADR-0009, amended 2026-10-24). The test seam refuses
   it, so no request can turn it off. No hatch reaches a multi option.
5. **A test shows a stalled lookup returning promptly,** on Linux. The container cannot
   stall a lookup, so a stand-in `getaddrinfo`, compiled at test time and loaded with
   `LD_PRELOAD` into a child Chez, stalls one name. The M3 plan, §6, says what it holds.

### Rejected

- **Raising the floor to 7.87.0, so that `QUICK_EXIT` is always there.** Every 7.85.0 row
  would be measured again (drift, URL verdicts, transfer verdicts), and CI's floor curl
  rebuilt. It would not reach 8.20.0's stall, which is the multi handle's.
- **Accepting the stall,** with the calls `__collect_safe` so that collections go on. A
  cancel, a timeout or a stop during a slow lookup would still hold every transfer on the
  engine for up to 10 s.

## Consequences

- **A detached resolver thread outlives its transfer** until its lookup ends, and then frees
  what it holds, as libcurl documents. That is unmeasured under Valgrind. No suite stalls a
  lookup under the memory gate.
- **The floor keeps the stall.** On 7.85.0 and 7.86.x, a cancel or a timeout during a stalled
  lookup holds the engine for up to glibc's resolver timeout, 10 s by default. M8's
  documentation says so.
- **`curl_multi_setopt` is a new variadic binding,** so `make check-variadic` must run on the
  Mac before M3 is done (ADR-0001).
- **`CURLMOPT_QUICK_EXIT` is a constant newer than the floor.** `test-constants` compiles
  against headers no newer than the library, and the floor's headers lack it. So M3 checks
  it only where the headers have it, under `LIBCURL_VERSION_NUM` (M3 plan, §6).
- **Apple's libcurl is unmeasured.** Its 8.7.1 has `QUICK_EXIT` but not the multi option, and
  macOS has no `LD_PRELOAD`. Whether the stand-in reaches Apple's resolver is the Mac run's
  to show.
