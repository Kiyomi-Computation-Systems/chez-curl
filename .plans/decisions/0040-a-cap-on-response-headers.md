# ADR-0040: A cap on response headers: 1,000 lines and 100 KiB a transfer

- **Status:** Accepted; amended 2026-11-06, after the M8 plan's review: decision 4's list made whole
  ([amendment](#amendment-2026-11-06-decision-4s-list-made-whole))
- **Date:** 2026-11-06
- **Scope:** chez-curl v1, M8: every transfer's response headers
  ([ADR-0038](0038-m8s-scope.md), decision 2)
- **Settles:** the cap's values, what it counts, where it is counted, and what it raises. The
  maintainer chose on 2026-11-06, the recommended option, from a probe on the five Linux libcurls,
  two runs each ([research/m8/caps/](../research/m8/caps/)).
- **Related:**
  - [ADR-0012](0012-engine-thread-owns-every-handle.md): the engine's thread walks every
    response's headers;
  - [ADR-0022](0022-codes-classed-as-condition-types.md): `&curl-too-large`, which holds 63, 100
    and the body limit;
  - [ADR-0017](0017-drift-guard.md): what varies by version is held in a row per libcurl.

## Context

- **libcurl's own caps** (case 1 to 3). Each holds on all five unless a version is named.
  - Count: 8.20.0 and 8.23.0 take 5,000 header lines a transfer, 4,999 over HTTP/2, and refuse
    the next with 100 before the header callback sees it. The count spans every head of the
    transfer: 1xx heads, trailers, a `CONNECT` answer, and both responses of a Digest round or a
    417's resend. 7.85.0 and 8.5.0 count nothing.
  - Bytes: 8.5.0 and later take 307,200 bytes a response, every byte handed to the callback in,
    and refuse the next with 56. 7.85.0 took 1 MiB.
  - One line of 102,400 bytes is refused on every lane before the callback sees it, by 27, 100, 16
    or 56, by version and protocol.
  - Over HTTP/2, nghttp2 refuses a long header block, at 168,480 decoded bytes of 256-byte lines;
    7.85.0 refuses a head at 128 KiB. 7.85.0 and 8.5.0 hand the callback no line of a head refused
    so.
- **The walk** (case 5). chez-curl reads a response's headers with `curl_easy_nextheader` on the
  engine's thread, and for a streamed response twice. A walk of 1,000 headers took 6.0 to 9.7 ms
  of CPU on 7.85.0 and 8.5.0, 19 to 25 ms on 8.20.0, and 0.07 to 0.15 ms on 8.23.0, which caches
  its counts; of 5,000, 140 to 536 ms on the first three. 7.85.0 walked 50,000 in 12.2 to 12.5 s.
  Under the memory gate's Valgrind, 8.20.0 walked 1,000 in 324 to 359 ms.
- **A cap in the header callback** (case 4). One that counted the lines and bytes it was handed
  over the whole transfer, and refused past 1,000 lines or 102,400 bytes, fired before libcurl's
  own caps in every case but those above where no line reaches it, and ended the transfer 23. On
  both 8.5.0 builds over HTTP/2, its refusal of a trailer line was lost, and the transfer ended 0.
- **Its cost** (case 6, through today's `(curl)` on 8.20.0). A Scheme callable per header line cost
  0.3 to 0.5 µs a line. Today a buffered transfer sets no header callback (`transfer.sls`, near
  line 4175).

## Decision

1. **Every transfer sets a header callable that counts its response headers over the whole
   transfer:** every head, 1xx heads, trailers, a `CONNECT` answer, and each response of an auth
   round or a resend. It counts header lines, a head's status line and empty line left out, and
   bytes, every byte it is handed.
2. **It refuses past 1,000 header lines or 102,400 bytes.** Its refusal is recorded as the
   transfer's reason before libcurl's answer is read, so the transfer fails with it whatever code
   libcurl gives, 8.5.0's lost refusal among them. It is a named reason of `&curl-too-large`, as
   the body limit's is.
3. **The values are fixed.** No key sets them in M8.
4. **libcurl's refusals that come before any line reaches the callable keep libcurl's codes:** a
   line of 102,400 bytes or more, an HTTP/2 head of 128 KiB or more on 7.85.0, and a head past
   nghttp2's limit. The docs list them by version, from a per-version table.

## Rejected

- **500 lines and 64 KiB:** cheaper walks, about 5 ms on 8.20.0, but more real responses refused,
  those with large cookies or policies among them.
- **2,000 lines and 120 KiB:** the walk costs about 77 ms on 8.20.0, twice that for a stream, and
  was not measured under Valgrind.
- **A cap per response:** libcurl's count spans the transfer, so a cap per response would let
  8.20.0 and 8.23.0 refuse first, with 100, on a transfer of several heads.
- **Mapping libcurl's own codes to the cap's reason:** 27 is libcurl's out-of-memory code, so a
  real failure would read as the cap's.

## Consequences

- **Every lane refuses alike** wherever the callable sees a line, the floor included, whose walk
  the cap now bounds.
- **A buffered transfer gains a callable per header line,** about 0.5 µs a line.
- **A test of the cap under the memory gate costs about a third of a second a walk** at 1,000 lines
  on 8.20.0.
- **`traps.md`'s n² walk** is amended: 8.23.0 caches, and 8.20.0's walk costs about three times
  7.85.0's.

## Amendment, 2026-11-06: decision 4's list made whole

The M8 plan's review found the caps probe's kept logs holding more refusals that come before any
line reaches the callable than decision 4 named, and one code the Context gave wrong. Each from
`results/` of [research/m8/caps/](../research/m8/caps/), its README's tables for cases 2 to 4,
which I checked against the logs:

- **A trailer line of 5,000 bytes over HTTP/1.1,** refused by libcurl's chunked parser, `Out of
  memory in chunked-encoding`: 56 on 7.85.0 and 8.5.0, 100 on 8.20.0 and 8.23.0
  (`docker-1.log:509-513`, `guix-8.20.0-1.log:500-504`); one of 4,000 is taken.
- **HTTP/2 trailers past nghttp2's limit,** none handed: 56 on 7.85.0, 8.5.0 and 8.23.0, 16 on
  8.20.0 (`tr-2+400K`).
- **A line of 102,400 bytes over HTTP/2 that HPACK cannot Huffman-code** (`line102400-X`): 52 on
  7.85.0, 56 on 8.5.0, 16 on 8.20.0 and 8.23.0. The Context's "27, 16 or 56 by version and
  protocol" holds for the line HPACK codes.
- **7.85.0 stores HTTP/2 trailers as headers,** so its walk returns them among a response's
  headers; the other lanes keep them apart.
- **The longest line the cap takes is shorter than libcurl's:** its bytes count the status line,
  every CR LF and the empty line, so a head of one 102,389-byte line, as test-transfer's
  `big-header?bytes=102380` case sends, meets it on every lane, where libcurl takes a line of
  102,399.

Each is a row of `test-headers`' per-version table, and the docs list them by version.

**Apple's 8.7.1, on the Mac, 2026-11-06** (`results/mac-8.7.1-1.log` and `-2.log`): its byte cap
is 8.5.0's, 307,200 a response, and it counts no headers. The cap's refusal ends an HTTP/2 transfer
56 there, not 23, which decision 2's recorded reason already covers; it does not lose a refused
HTTP/2 trailer, as 8.5.0 does. A line of 102,400 bytes is 100 over HTTP/1.1 and 56 over HTTP/2, 16
if HPACK cannot code it; a 5,000-byte trailer line is 100; nghttp2's limit is 56. One walk of 5,000
headers took 107 to 146 ms of CPU. No decision moved.
