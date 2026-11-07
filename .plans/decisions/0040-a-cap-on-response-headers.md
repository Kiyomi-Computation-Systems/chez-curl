# ADR-0040: A cap on response headers: 1,000 lines and 100 KiB a transfer

- **Status:** Accepted; amended 2026-11-06, after the M8 plan's review: decision 4's list made whole
  ([amendment](#amendment-2026-11-06-decision-4s-list-made-whole)); amended 2026-11-06, slice 2's
  measurement through the engine, and two options decided
  ([amendment](#amendment-2026-11-06-measured-through-the-engine-and-two-options-decided))
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
is 8.5.0's, 307,200 a response, and it counts no headers. The cap's refusal of an HTTP/2 head
ends the transfer 56 there, not 23, which decision 2's recorded reason already covers; it does not
lose a refused HTTP/2 trailer, as 8.5.0 does. A line of 102,400 bytes is 100 over HTTP/1.1 and 56
over HTTP/2, 16 if HPACK cannot code it; a 5,000-byte trailer line is 100; nghttp2's limit is 56.
One walk of 5,000 headers took 107 to 146 ms of CPU. No decision moved.

## Amendment, 2026-11-06: measured through the engine, and two options decided

M8 slice 2 measured a prototype of decisions 1 and 2 through the engine on the five Linux lanes,
two runs each, every cell alike in both ([research/m8/slice2/](../research/m8/slice2/README.md));
I reran its Guix lane, 147 cells matching line for line.

- **Decisions 1 and 2 hold on every lane,** buffered and streamed, over HTTP/1.1 and HTTP/2: 1,000
  lines taken, the 1,001st refused; 102,400 bytes taken, 102,401 refused; and 1xx heads, trailers,
  a Digest round, a 417's resend and a `CONNECT` answer all count across the transfer.
- **The recorded reason wins even over 0:** on both 8.5.0 builds, a refused HTTP/2 trailer ends
  the transfer 0 (the trap), and it now fails `header-limit`, its code 0. No test asserts the
  cap's code; `test-headers`' table holds it by version: 23, 0 for 8.5.0's HTTP/2 trailers, and 56
  for an HTTP/2 head on 8.7.1, its trailers 23.
- **Decision 4's list, corrected:** nghttp2's limit on an HTTP/2 head comes before the cap only on
  7.85.0 and 8.5.0, 56, which hand no line of such a head. On 8.20.0 and 8.23.0 its lines arrive
  first and the cap refuses, 23; the earlier "56, or 16 on 8.20.0" was libcurl's answer with no cap.
- **The cost:** a buffered transfer's callable costs 0.4 to 1.3 µs of CPU a line natively on
  7.85.0, and 18.5 to 21.5 µs under the memory gate's Valgrind, 21 to 25 ms more for a response of
  1,000 headers.
- **5. `SUPPRESS_CONNECT_HEADERS` is owned,** refused by the hatch as `owned-option`. Decided by
  the maintainer, 2026-11-06, the recommended option. Set, it hides a `CONNECT` answer from the
  callable on every lane, so the cap never counts it, and libcurl's own caps alone hold it: a
  60,000-line answer passed 200 on 7.85.0, failed 56 at 8.5.0's 307,200 bytes, and 100 at 5,000
  lines on 8.20.0 and 8.23.0. chez-curl shows no `CONNECT` answer either way.
- **6. `HTTP_TRANSFER_DECODING` stays the hatch's.** Decided by the maintainer, 2026-11-06, the
  recommended option. Set to 0, it puts trailers in the body, where `body-limit` bounds them and
  nothing is stored as a header; the docs say so. The hatch's `HTTP200ALIASES`, `HTTP09_ALLOWED`
  and `FAILONERROR` change what the callable sees no further than an alias's status line, counted
  as a header line.
- **The origin's HTTP/2 faces raise Node's send limit alone,** `maxSendHeaderBlockLength`: the
  caps stand-in's other two limits are a receiver's, and put a setting in the SETTINGS frame that
  84 tests hold byte for byte. With Node's default, Node 24 drops a trailer block it cannot send and
  ends the stream cleanly, a 200 with no trailers, and Node 20 resets it (the trap).
- **As built:** `header-line-cap` and `header-byte-cap` in `(curl private transfer)`, each written
  out in `tests/test-headers.sps`. A Linux libcurl never calls the header callable again after it
  refuses, so the refusal of every later call is held by a private seam, a request's mark `(mark
  N)`, which records a planted reason at the head's line N and still answers it.
  `/raw/head417` holds its 417 by a key, not a connection: under the memory gate a resend reached
  a new connection (ADR-0014's gate; [the reproduction](../research/m8/slice2/build/trap-417/)).
- **After the slice's review:** a status line is a line at a head's start reading `HTTP/`, a
  digit, then `.` and a digit or not, then a space. A status line the pattern missed would be
  counted one line over, never under. Mid-head, libcurl takes `HTTP/1.1 x: v`, `HTTP/1: v` and the
  like as headers on all five Linux lanes, and the cap counts them; a trailer section's first line
  that matches the pattern, `HTTP/1.1 x: v` or `HTTP/1 : v`, libcurl takes as a trailer, so that
  section counts one line under, once ([fix/odd](../research/m8/slice2/build/fix/)). `request-like`
  is exported from `(curl private transfer)`, a test seam, for `test-transfer`'s refusals of a
  malformed mark or head fault.
