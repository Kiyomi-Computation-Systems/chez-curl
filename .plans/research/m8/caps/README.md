# M8 research: libcurl's response-header caps, and what a cap of chez-curl's own costs

Measured 2026-11-06 for the M8 plan, [ADR-0038](../../../decisions/0038-m8s-scope.md) decision 2:
every transfer caps its response's headers by count and by bytes, below every libcurl's own caps,
so every lane refuses alike, by a named reason. This reports where each libcurl's caps are, what it
answers at them, and what a cap below them in a `HEADERFUNCTION` answers and costs. It recommends
nothing. Every number below is from a kept log under `results/`, by its path; the tables are
`tables.mjs`'s output over those logs, pasted.

## In short

- **The count cap is 8.20.0's and 8.23.0's alone, and it counts the whole transfer.** Over HTTP/1.1
  they take 5,000 header lines and refuse the 5,001st with 100, `Too many response headers, 5000
  is max`, before handing it to the callback. Over HTTP/2 they take 4,999: libcurl stores each
  head's `:status` as a `CURLH_PSEUDO` header (8.20.0 `lib/http2.c:1526`), which takes a slot. The
  5,000 spans every head of the transfer: a 1xx head's lines, trailers, a `CONNECT` answer's, and
  both responses of a Digest 401 round, a followed redirect and a 417's resend. 7.85.0 and 8.5.0
  count nothing ([case 1](#case-1-count), [case 3](#case-3-what-counts-toward-a-cap)).
- **The byte cap is 8.5.0's and later: 307,200 bytes a request, every byte handed counted.** A head
  of 307,200 bytes, its status line, every CR LF and its empty line in, is taken; 307,201 is refused
  56, `Too large response headers: 307201 > 307200`, the line that crossed handed to the callback
  first. 1xx heads count with the final head, and so does a `CONNECT` answer on 8.5.0 but not on
  8.20.0 and 8.23.0; a 401 round's, a redirect's and a 417's second response start again at 0.
  Trailers count on 8.23.0 alone. 7.85.0 takes 1 MiB over HTTP/1.1 ([case 2](#case-2-bytes)).
- **One line of 102,400 bytes, CR LF in, is refused on every lane, before the callback sees it;
  102,399 is taken.** The code moves: 27 on 7.85.0 and 8.5.0, 100 on 8.20.0 and 8.23.0 over
  HTTP/1.1; over HTTP/2, 27 on 7.85.0 and 8.5.0, 16 on 8.20.0 and 56 on 8.23.0. No `HEADERFUNCTION` cap can name this refusal: the line
  never reaches it.
- **Over HTTP/2, caps below libcurl's own refuse first.** nghttp2 refuses a long header block, `-905
  Too many CONTINUATION frames following a HEADER frame`, in Docker's 1.59.0-1ubuntu0.4 and Guix's
  1.69.0 alike: heads of distinct 256-byte lines stopped at 168,480 decoded bytes, on every lane but
  7.85.0, whose own 128 KiB comes first (131,071 bytes taken, 131,072 refused 56). The codes: 56 on
  7.85.0, 8.5.0 and 8.23.0, 16 on 8.20.0. HPACK lets a server pass nghttp2's: 307,199 bytes of one
  repeated pair took 3,174 to 3,198 bytes on the wire, its TLS handshake among them, and met
  libcurl's own 300 KiB cap on 8.5.0 and later; 7.85.0's 128 KiB, of decoded bytes, still refused it.
- **7.85.0 and 8.5.0 hand nothing of an HTTP/2 head that they or nghttp2 refuse** (`@0` in the
  tables); 8.20.0 and 8.23.0 hand every line decoded before the refusal.
- **A cap in the `HEADERFUNCTION` at 1,000 header lines and 102,400 bytes refused first in every
  case of 1 to 3 but these:** the single line of 102,400 bytes or more; a trailer line of 5,000
  bytes on HTTP/1.1 (4,000 taken; libcurl's chunked parser, 56 or 100); every HTTP/2 head 7.85.0, 8.5.0 or
  nghttp2 refuses before handing a line (above); HTTP/2 trailers that nghttp2 refuses, or, on
  8.23.0, more than 5,000 of them (56, `Error receiving HTTP2 header: 27(Out of memory)`). Its
  refusal ends the transfer 23 on every lane, **but on both 8.5.0 builds over HTTP/2 a refused
  trailer line is lost: the transfer ends 0**, `Failed writing header` in the error buffer
  ([case 4](#case-4-a-cap-below-libcurls-in-a-headerfunction)).
- **The walk is n² on 7.85.0, 8.5.0 and 8.20.0, linear on 8.23.0.** One whole `curl_easy_nextheader`
  walk of 5,000 headers took 140 to 158 ms of CPU on 7.85.0, 159 to 205 on 8.5.0, 454 to 536 on
  8.20.0 and 0.39 to 0.54 on 8.23.0, whose `nextheader_cache_build` (8.23.0 `lib/headers.c`) caches
  each header's count. At 1,000: 6.0 to 9.7 ms on 7.85.0 and 8.5.0, 19 to 25 on 8.20.0, 0.07 to
  0.15 on 8.23.0. 7.85.0 walked 50,000 in 12.2 to 12.5 s; 8.5.0 walked the 19,199 it stored before
  its byte cap refused a head of 16-byte lines in 2.26 to 2.45 s. Under Valgrind, 8.20.0's 5,000 took
  7.3 to 8.6 s ([case 5](#case-5-the-walks-cost)).
- **Case 6, lane X, through today's `(curl)`:** the streamed path's callable costs about 0.3 to 0.5 µs
  a line. A buffered response of 5,000 headers took 458 to 484 ms of CPU, nearly all of it the walk,
  and a streamed one 914 to 956 ms, two walks, the first inside `curl_multi_perform`
  ([case 6](#case-6-a-scheme-callable-per-header-line)).

## What was run

`probe.c` drives libcurl's multi interface in chez-curl's engine turn (`curl_multi_perform`,
`curl_multi_info_read`, `curl_multi_poll` for at most 1000 ms), one transfer on a fresh multi handle
per cell, with the engine's options in `transfer.sls`'s order: the pins (`PROTOCOLS_STR` and
`REDIR_PROTOCOLS_STR` `http,https`, `NOSIGNAL` 1, `MAXREDIRS` 30, `QUICK_EXIT` 1 where known),
`ERRORBUFFER`, the URL, `WRITEFUNCTION`, `PROXY` `""` or the proxy, `SSL_VERIFYPEER` 1,
`SSL_VERIFYHOST` 2, `CAINFO` and `CAPATH` cleared; `CURLMOPT_QUICK_EXIT` 1 where known, and
`CURLMOPT_PIPELINING` 0 on 8.7.x. `HTTP_VERSION` is libcurl's own (2TLS). Its header comment lists
everything. `server.mjs` is a stand-in on Node's standard library alone:

| face | scheme | what it serves |
|---|---|---|
| `h1` | http | HTTP/1.1 written by hand: every byte of a head is the stand-in's |
| `h1tls` | https | the same, behind TLS, ALPN `http/1.1` alone |
| `h2` | https | `node:http2`, ALPN `h2` alone, its send limits raised, no `date`; nghttp2 encodes the block (HPACK, Huffman where shorter, a repeated pair indexed) |
| `proxy` | http | answers `CONNECT` 200 with the head `/arm` named, then tunnels |
| `ctl` | http | control: `/arm`, and the events fetched after each cell |

A head's spec is a query: `n` lines of `line` bytes each (CR LF included; names `x-000001` on, the
value `v` repeated), or lines until the head holds `total` bytes, status line and empty line in;
`same=1`, every line the same pair; `big=B`, one more line of B bytes, its value `a` repeated (5
bits each in HPACK's Huffman code), or `bigch=X` (8 bits, so sent raw); `pre=103:N:L,...`, 1xx heads
first; `tn`/`tl`, trailers. `/auth`, `/expect` and `/redir` give a flow's two responses their own
specs. The h1 faces put `content-length: 0` (or `transfer-encoding: chunked`) first, among the `n`.
Over HTTP/2 libcurl renders the status line `HTTP/2 200 \r\n`, 13 bytes; over HTTP/1.1 it is the
stand-in's `HTTP/1.1 200 OK\r\n`, 17. Every head taken whole in the logs holds exactly its spec's
bytes.

Every cell runs three ways (`PROBE_MODES`):

- **obs**: a `HEADERFUNCTION` that counts every line it is handed and answers its length, as
  chez-curl's streamed path sets one; the walk after the end, whatever the code.
- **none**: no `HEADERFUNCTION`, as chez-curl's buffered path; the walk after a code of 0.
- **cap**: case 4's callback, refusing (answering 0) the line that takes the header lines past
  1,000 or the bytes past 102,400; the walk after a code of 0.

The callback calls a line starting `HTTP/` at a head's start a status line, `\r\n` an empty line, and
the rest header lines; header lines after an empty line that no status line opens are a trailer
section, `T`. Its bytes count every line, status and empty lines too.

### The lanes, two runs each

| lane | libcurl | TLS, nghttp2 | Node | runs |
|---|---|---|---|---|
| F | `build/e1/ci/curl-floor`, 7.85.0, its own headers | OpenSSL 3.0.13, 1.59.0 | 20.10.0 | `results/docker-1.log`, `docker-2.log`, `[floor-7.85.0]` |
| O | Ubuntu 24.04's `libcurl.so.4`, 8.5.0-2ubuntu10.16 | OpenSSL 3.0.13, 1.59.0-1ubuntu0.4 | 24.18.0 | the same, `[ubuntu-openssl-8.5.0]` |
| G | Ubuntu's `libcurl-gnutls.so.4`, 8.5.0-2ubuntu10.16, against `libcurl4-openssl-dev`'s headers | GnuTLS 3.8.3, 1.59.0-1ubuntu0.4 | 24.18.0 | the same, `[ubuntu-gnutls-8.5.0]` |
| X | the Guix profile's 8.20.0 (`$CHEZ_CURL_LIBCURL`) | GnuTLS 3.8.13, 1.69.0 | 24.18.0 | `results/guix-8.20.0-1.log`, `-2.log` |
| C | `build/verify/c823/lane1/curl-current`, 8.23.0 | OpenSSL 3.0.13, 1.59.0-1ubuntu0.4 | 24.18.0 | `results/docker-1.log`, `docker-2.log`, `[current-8.23.0]` |
| M | Apple's 8.7.1 | SecureTransport | the Mac's | `mac.sh` writes `results/mac-8.7.1-{1,2}.log`; not run here |

Docker ran `ubuntu:24.04` (`sha256:68ee2200…`) with `--network none` (loopback alone, printed) and
`--cpuset-cpus 12-17`, from packages fetched once into `build/m8/caps/apt`; lane X ran in the Guix
container under `taskset -c 12-17`. Every lane's run printed its `Cpus_allowed_list` as `12-17`.

## Case 1: count

Responses of N header lines of 16 bytes (`content-length: 0` among them), names distinct; over h2
again with every line the same pair (`-same`), which HPACK indexes. The verdict is the obs mode's;
`@` is the header lines handed when libcurl stopped. The none mode's code is the same in every cell
of cases 1 to 3, on every lane (below the case 3 table).

*Case 1, count: the code (obs), and @ the header lines handed when it stopped*

| cell | face | F floor-7.85.0 | O ubuntu-openssl-8.5.0 | G ubuntu-gnutls-8.5.0 | X guix-8.20.0 | C current-8.23.0 |
|---|---|---|---|---|---|---|
| n1000 | h1 | 0 | 0 | 0 | 0 | 0 |
| n4999 | h1 | 0 | 0 | 0 | 0 | 0 |
| n5000 | h1 | 0 | 0 | 0 | 0 | 0 |
| n5001 | h1 | 0 | 0 | 0 | 100 @5000 | 100 @5000 |
| n10000 | h1 | 0 | 0 | 0 | 100 @5000 | 100 @5000 |
| n50000 | h1 | 0 | 56 @19199 | 56 @19199 | 100 @5000 | 100 @5000 |
| n1000 | h1tls | 0 | 0 | 0 | 0 | 0 |
| n4999 | h1tls | 0 | 0 | 0 | 0 | 0 |
| n5000 | h1tls | 0 | 0 | 0 | 0 | 0 |
| n5001 | h1tls | 0 | 0 | 0 | 100 @5000 | 100 @5000 |
| n10000 | h1tls | 0 | 0 | 0 | 100 @5000 | 100 @5000 |
| n50000 | h1tls | 0 | 56 @19199 | 56 @19199 | 100 @5000 | 100 @5000 |
| n1000 | h2 | 0 | 0 | 0 | 0 | 0 |
| n4999 | h2 | 0 | 0 | 0 | 0 | 0 |
| n5000 | h2 | 0 | 0 | 0 | 100 @4999 | 100 @4999 |
| n5001 | h2 | 0 | 0 | 0 | 100 @4999 | 100 @4999 |
| n10000 | h2 | 56 @0 | 0 | 0 | 100 @4999 | 100 @4999 |
| n50000 | h2 | 56 @0 | 56 @0 | 56 @0 | 100 @4999 | 100 @4999 |
| n4999-same | h2 | 0 | 0 | 0 | 0 | 0 |
| n5000-same | h2 | 0 | 0 | 0 | 100 @4999 | 100 @4999 |
| n5001-same | h2 | 0 | 0 | 0 | 100 @4999 | 100 @4999 |
| n10000-same | h2 | 56 @0 | 0 | 0 | 100 @4999 | 100 @4999 |
| n50000-same | h2 | 56 @0 | 56 @19200 | 56 @19200 | 100 @4999 | 100 @4999 |

- **8.20.0 and 8.23.0:** 5,000 taken over HTTP/1.1, the 5,001st refused 100 before it is handed;
  4,999 over HTTP/2, the `:status` pseudo-header holding the 5,000th slot.
- **8.5.0:** no count; over HTTP/1.1 50,000 stops at its byte cap, 56 after 19,199 lines (307,204
  bytes); over HTTP/2 50,000 distinct lines stop at nghttp2's `CONTINUATION` limit, none handed,
  and the same pair at the byte cap, after 19,200 lines.
- **7.85.0:** takes 50,000 over HTTP/1.1; over HTTP/2 10,000 lines (160,018 bytes) pass its
  128 KiB, refused 56 with none handed.
- **Memory:** libcurl held 3,083 KiB through its allocators at the end of 7.85.0's 50,000; 315 KiB
  at 5,000 (7.85.0), 314 (8.5.0), 347 (8.20.0), 423 (8.23.0) (`live_kb`, the obs lines).

*Case 1, times: the transfer (ms, add to done, no HEADERFUNCTION), each run; then the walk's CPU (ms) after a code of 0*

| cell | face | F floor-7.85.0 | O ubuntu-openssl-8.5.0 | G ubuntu-gnutls-8.5.0 | X guix-8.20.0 | C current-8.23.0 |
|---|---|---|---|---|---|---|
| n1000 | h1 | 3.3, 4.3; walk 6.1, 7.3 | 2.4, 2.4; walk 7.3, 7.5 | 2.9, 2.3; walk 8.8, 6.9 | 2.3, 2.7; walk 21.0, 26.6 | 2.2, 2.2; walk 0.1, 0.1 |
| n4999 | h1 | 3.9, 4.5; walk 142.0, 155.5 | 2.9, 3.0; walk 173.5, 174.9 | 3.3, 2.6; walk 164.5, 160.2 | 2.7, 3.2; walk 449.7, 483.5 | 3.5, 3.6; walk 0.6, 0.5 |
| n5000 | h1 | 1.7, 1.9; walk 140.7, 151.0 | 1.7, 2.0; walk 172.7, 173.4 | 1.8, 1.8; walk 160.6, 160.5 | 1.5, 1.7; walk 472.6, 474.8 | 2.2, 2.3; walk 0.4, 0.4 |
| n5001 | h1 | 2.5, 2.1; walk 141.2, 161.1 | 1.7, 1.6; walk 180.9, 171.9 | 1.6, 1.5; walk 160.3, 160.2 | 1.4, 1.5 | 2.1, 2.0 |
| n10000 | h1 | 3.9, 4.6; walk 552.7, 591.1 | 5.0, 3.1; walk 697.4, 738.8 | 3.0, 3.7; walk 640.7, 665.2 | 4.8, 2.4 | 2.9, 2.7 |
| n50000 | h1 | 43.4, 42.5; walk 12277.9, 12395.7 | 18.2, 18.5 | 19.0, 18.4 | 19.1, 18.0 | 19.5, 19.5 |
| n1000 | h1tls | 4.5, 6.3; walk 6.3, 7.2 | 4.5, 4.7; walk 7.2, 7.4 | 6.1, 6.3; walk 7.0, 7.0 | 6.0, 4.1; walk 20.4, 20.7 | 4.4, 6.0; walk 0.1, 0.1 |
| n4999 | h1tls | 3.1, 3.1; walk 116.4, 115.6 | 3.1, 3.2; walk 172.4, 172.6 | 3.1, 2.9; walk 161.2, 162.2 | 4.5, 3.4; walk 449.6, 457.0 | 3.3, 2.9; walk 0.6, 0.5 |
| n5000 | h1tls | 4.1, 4.2; walk 141.1, 141.0 | 3.0, 3.1; walk 177.0, 176.8 | 3.1, 2.9; walk 167.7, 160.8 | 3.8, 3.3; walk 479.7, 455.8 | 3.2, 2.8; walk 0.6, 0.5 |
| n5001 | h1tls | 3.2, 3.3; walk 141.6, 141.3 | 3.8, 5.2; walk 177.5, 177.3 | 3.7, 4.3; walk 160.7, 161.0 | 3.5, 3.4 | 2.9, 3.3 |
| n10000 | h1tls | 5.1, 5.3; walk 561.5, 554.6 | 5.8, 5.7; walk 684.8, 684.6 | 7.1, 5.6; walk 645.1, 636.5 | 5.5, 5.3 | 3.9, 5.1 |
| n50000 | h1tls | 20.8, 23.8; walk 12228.9, 12513.4 | 15.2, 14.8 | 14.9, 14.7 | 13.4, 13.0 | 22.3, 12.9 |
| n1000 | h2 | 7.0, 7.1; walk 5.2, 5.3 | 7.8, 7.5; walk 7.1, 7.5 | 7.0, 9.1; walk 7.0, 6.9 | 7.3, 7.3; walk 20.4, 20.8 | 7.9, 7.8; walk 0.1, 0.1 |
| n4999 | h2 | 9.4, 9.6; walk 119.2, 118.9 | 8.7, 8.6; walk 173.3, 171.7 | 8.5, 9.0; walk 160.4, 164.8 | 10.5, 9.9; walk 461.0, 466.9 | 9.7, 10.4; walk 0.5, 0.5 |
| n5000 | h2 | 10.2, 8.3; walk 123.4, 118.0 | 8.0, 8.2; walk 172.1, 171.8 | 7.9, 7.7; walk 160.5, 159.9 | 8.3, 8.2 | 8.6, 7.8 |
| n5001 | h2 | 7.9, 9.0; walk 117.6, 117.7 | 8.1, 7.7; walk 187.3, 173.0 | 8.5, 7.6; walk 164.5, 160.5 | 7.8, 8.3 | 7.6, 7.9 |
| n10000 | h2 | 13.7, 14.3 | 15.6, 15.5; walk 705.4, 685.8 | 19.4, 16.7; walk 675.2, 636.3 | 15.4, 17.0 | 14.8, 15.0 |
| n50000 | h2 | 94.4, 88.1 | 70.6, 71.7 | 71.7, 92.0 | 69.9, 71.0 | 88.7, 87.5 |
| n4999-same | h2 | 5.4, 5.5; walk 166.2, 150.3 | 10.1, 10.6; walk 160.6, 162.9 | 4.8, 5.6; walk 161.4, 165.6 | 4.9, 5.0; walk 473.6, 472.2 | 7.6, 5.6; walk 0.5, 0.5 |
| n5000-same | h2 | 4.3, 4.7; walk 149.5, 150.1 | 3.9, 3.8; walk 160.5, 161.4 | 3.4, 4.5; walk 160.3, 163.2 | 3.8, 3.7 | 4.9, 4.1 |
| n5001-same | h2 | 3.8, 3.8; walk 155.3, 149.5 | 3.9, 4.7; walk 161.3, 168.2 | 4.3, 4.3; walk 159.8, 161.1 | 4.4, 4.6 | 4.4, 4.1 |
| n10000-same | h2 | 4.5, 5.3 | 6.3, 6.4; walk 668.0, 675.2 | 7.0, 5.3; walk 644.9, 663.8 | 5.7, 5.7 | 4.6, 4.6 |
| n50000-same | h2 | 21.4, 15.4 | 29.2, 26.0 | 24.0, 20.7 | 18.8, 19.8 | 17.2, 16.3 |

A transfer of 50,000 lines took 12.9 to 94.4 ms on every lane, refused or not; the walk after it is what
costs (case 5).

## Case 2: bytes

Heads of 307,199, 307,200, 307,201 and 1,048,576 bytes in all, in lines of 256 bytes; one line of
102,398 to 102,401 bytes after `content-length: 0`; over h2, the same pair, the raw `X` line, and
heads at 7.85.0's 128 KiB. `@` is the bytes handed when libcurl stopped.

*Case 2, bytes: the code (obs), and @ the bytes handed, status and empty lines in, when it stopped; libcurl's own figure where it differs*

| cell | face | F floor-7.85.0 | O ubuntu-openssl-8.5.0 | G ubuntu-gnutls-8.5.0 | X guix-8.20.0 | C current-8.23.0 |
|---|---|---|---|---|---|---|
| total307199 | h1 | 0 | 0 | 0 | 0 | 0 |
| total307200 | h1 | 0 | 0 | 0 | 0 | 0 |
| total307201 | h1 | 0 | 56 @307201 | 56 @307201 | 56 @307201 | 56 @307201 |
| total1048576 | h1 | 0 | 56 @307236 | 56 @307236 | 56 @307236 | 56 @307236 |
| line102398 | h1 | 0 | 0 | 0 | 0 | 0 |
| line102399 | h1 | 0 | 0 | 0 | 0 | 0 |
| line102400 | h1 | 27 @36 | 27 @36 | 27 @36 | 100 @36 | 100 @36 |
| line102401 | h1 | 27 @36 | 27 @36 | 27 @36 | 100 @36 | 100 @36 |
| total307199 | h1tls | 0 | 0 | 0 | 0 | 0 |
| total307200 | h1tls | 0 | 0 | 0 | 0 | 0 |
| total307201 | h1tls | 0 | 56 @307201 | 56 @307201 | 56 @307201 | 56 @307201 |
| total1048576 | h1tls | 0 | 56 @307236 | 56 @307236 | 56 @307236 | 56 @307236 |
| line102398 | h1tls | 0 | 0 | 0 | 0 | 0 |
| line102399 | h1tls | 0 | 0 | 0 | 0 | 0 |
| line102400 | h1tls | 27 @36 | 27 @36 | 27 @36 | 100 @36 | 100 @36 |
| line102401 | h1tls | 27 @36 | 27 @36 | 27 @36 | 100 @36 | 100 @36 |
| total307199 | h2 | 56 @0 | 56 @0 | 56 @0 | 16 @168480 | 56 @168480 |
| total307200 | h2 | 56 @0 | 56 @0 | 56 @0 | 16 @168480 | 56 @168480 |
| total307201 | h2 | 56 @0 | 56 @0 | 56 @0 | 16 @168480 | 56 @168480 |
| total1048576 | h2 | 56 @0 | 56 @0 | 56 @0 | 16 @168480 | 56 @168480 |
| line102398 | h2 | 0 | 0 | 0 | 0 | 0 |
| line102399 | h2 | 0 | 0 | 0 | 0 | 0 |
| line102400 | h2 | 27 @32 | 27 @32 | 27 @32 | 16 @32 | 56 @32 |
| line102401 | h2 | 27 @32 | 27 @32 | 27 @32 | 16 @32 | 56 @32 |
| total307199-same | h2 | 56 @0 | 0 | 0 | 0 | 0 |
| total307200-same | h2 | 56 @0 | 0 | 0 | 0 | 0 |
| total307201-same | h2 | 56 @0 | 56 @307201 | 56 @307201 | 56 @307201 | 56 @307201 |
| total1048576-same | h2 | 56 @0 | 56 @307232 | 56 @307232 | 56 @307232 | 56 @307232 |
| line102400-X | h2 | 52 @0 | 56 @32 | 56 @32 | 16 @32 | 16 @32 |
| total131071 | h2 | 0 | 0 | 0 | 0 | 0 |
| total131072 | h2 | 56 @0 | 0 | 0 | 0 | 0 |
| total131073 | h2 | 56 @0 | 0 | 0 | 0 | 0 |

- **What libcurl's byte cap counts:** every byte it hands the callback. At 307,201 its own figure,
  in `Too large response headers: N > 307200`, equals the callback's count on every lane that caps,
  over HTTP/1.1 and HTTP/2: the status line, every line's CR LF and the empty line are all in. It
  refuses once the count passes 307,200, after handing the line that passed it.
- **The line cap:** 102,399 bytes, CR LF in, taken; 102,400 refused before it is handed (`@36` and
  `@32` are the status and `content-length` lines alone). 7.85.0 and 8.5.0 answer 27 with an empty
  error buffer, 8.20.0 and 8.23.0 100 over HTTP/1.1; over HTTP/2 8.20.0 answers 16 and 8.23.0 56,
  both `Error receiving HTTP2 header: 100(A value or data field grew larger than allowed)`.
- **The raw `X` line over HTTP/2** fails in nghttp2's HPACK decoder (`COMPRESSION_ERROR`, a client
  GOAWAY of code 9 in the server's events): 52 `Empty reply from server` on 7.85.0, 56 with an empty
  buffer on 8.5.0, 16 on 8.20.0 and 8.23.0. The `a` line, about 64,000 bytes Huffman-coded (65,684
  and 65,687 wire bytes in all), passes nghttp2 and meets libcurl's own line cap.
- **nghttp2's `CONTINUATION` limit:** distinct 256-byte lines stopped at 168,480 decoded bytes on
  8.20.0 and 8.23.0, which hand lines as they come; the stand-in wrote 270,851 bytes on the wire for
  the 307,199-byte head, TLS in, and 270,852 in run 2 (`h2-wire` events, `results/guix-8.20.0-{1,2}.log`).
  The same pair's 307,199 bytes took 3,198 and 3,174 wire bytes, the TLS handshake among them, and
  met libcurl's own cap.

## Case 3: what counts toward a cap

Each head the callback was handed, as `status:header-lines:bytes`; `T` a trailer section. The
`/expect` flow's second response is preceded by a `100 Continue` the stand-in sends (`100:0:25`).

*Case 3, what counts: the code (obs) and each head handed, as status:header-lines:bytes (T a trailer section)*

| cell | face | F floor-7.85.0 | O ubuntu-openssl-8.5.0 | G ubuntu-gnutls-8.5.0 | X guix-8.20.0 | C current-8.23.0 |
|---|---|---|---|---|---|---|
| pre103-6000+2 | h1 | 0 [103:6000:96028,200:2:54] | 0 [103:6000:96028,200:2:54] | 0 [103:6000:96028,200:2:54] | 100 [103:5000:80026] | 100 [103:5000:80026] |
| pre103-3000+3000 | h1 | 0 [103:3000:48028,200:3000:48022] | 0 [103:3000:48028,200:3000:48022] | 0 [103:3000:48028,200:3000:48022] | 100 [103:3000:48028,200:2000:32020] | 100 [103:3000:48028,200:2000:32020] |
| pre100-3000+3000 | h1 | 0 [100:3000:48025,200:3000:48022] | 0 [100:3000:48025,200:3000:48022] | 0 [100:3000:48025,200:3000:48022] | 100 [100:3000:48025,200:2000:32020] | 100 [100:3000:48025,200:2000:32020] |
| pre103-2500x2+1000 | h1 | 0 [103:2500:40028,103:2500:40028,200:1000:16022] | 0 [103:2500:40028,103:2500:40028,200:1000:16022] | 0 [103:2500:40028,103:2500:40028,200:1000:16022] | 100 [103:2500:40028,103:2500:40028,200:0:17] | 100 [103:2500:40028,103:2500:40028,200:0:17] |
| pre103-400K+2 | h1 | 0 [103:1600:409628,200:2:54] | 56 [103:1200:307226] | 56 [103:1200:307226] | 56 [103:1200:307226] | 56 [103:1200:307226] |
| pre103-200K+200K | h1 | 0 [103:800:204828,200:800:204582] | 56 [103:800:204828,200:401:102436] | 56 [103:800:204828,200:401:102436] | 56 [103:800:204828,200:401:102436] | 56 [103:800:204828,200:401:102436] |
| tr-2+6000 | h1 | 0 [200:2:63,T:6000:96000] | 0 [200:2:63,T:6000:96000] | 0 [200:2:63,T:6000:96000] | 100 [200:2:63,T:4998:79968] | 100 [200:2:63,T:4998:79968] |
| tr-3000+3000 | h1 | 0 [200:3000:48031,T:3000:48000] | 0 [200:3000:48031,T:3000:48000] | 0 [200:3000:48031,T:3000:48000] | 100 [200:3000:48031,T:2000:32000] | 100 [200:3000:48031,T:2000:32000] |
| tr-2+400K | h1 | 0 [200:2:63,T:1600:409600] | 0 [200:2:63,T:1600:409600] | 0 [200:2:63,T:1600:409600] | 0 [200:2:63,T:1600:409600] | 56 [200:2:63,T:1200:307200] |
| tr-200K+200K | h1 | 0 [200:800:204591,T:800:204800] | 0 [200:800:204591,T:800:204800] | 0 [200:800:204591,T:800:204800] | 0 [200:800:204591,T:800:204800] | 56 [200:800:204591,T:401:102656] |
| tr-line4000 | h1 | 0 [200:2:63,T:1:4000] | 0 [200:2:63,T:1:4000] | 0 [200:2:63,T:1:4000] | 0 [200:2:63,T:1:4000] | 0 [200:2:63,T:1:4000] |
| tr-line5000 | h1 | 56 [200:2:63] | 56 [200:2:63] | 56 [200:2:63] | 100 [200:2:63] | 100 [200:2:63] |
| pre103-6000+2 | h2 | 0 [103:6000:96015,200:2:50] | 0 [103:6000:96015,200:2:50] | 0 [103:6000:96015,200:2:50] | 100 [103:4999:79997] | 100 [103:4999:79997] |
| pre103-3000+3000 | h2 | 0 [103:3000:48015,200:3000:48018] | 0 [103:3000:48015,200:3000:48018] | 0 [103:3000:48015,200:3000:48018] | 100 [103:3000:48015,200:1998:31984] | 100 [103:3000:48015,200:1998:31984] |
| pre100-3000+3000 | h2 | 0 [100:3000:48015,200:3000:48018] | 0 [100:3000:48015,200:3000:48018] | 0 [100:3000:48015,200:3000:48018] | 100 [100:3000:48015,200:1998:31984] | 100 [100:3000:48015,200:1998:31984] |
| pre103-2500x2+1000 | h2 | 0 [103:2500:40015,103:2500:40015,200:1000:16018] | 0 [103:2500:40015,103:2500:40015,200:1000:16018] | 0 [103:2500:40015,103:2500:40015,200:1000:16018] | 16 [103:2500:40015,103:2498:39981] | 56 [103:2500:40015,103:2498:39981] |
| pre103-400K+2 | h2 | 56 [] | 56 [] | 56 [] | 16 [103:658:168461] | 56 [103:658:168461] |
| pre103-200K+200K | h2 | 56 [] | 56 [] | 56 [] | 16 [103:658:168461] | 56 [103:658:168461] |
| tr-2+6000 | h2 | 0 [200:2:47,T:6000:96000] | 0 [200:2:47,T:6000:96000] | 0 [200:2:47,T:6000:96000] | 100 [200:2:47,T:4997:79952] | 56 [200:2:47] |
| tr-3000+3000 | h2 | 0 [200:3000:48015,T:3000:48000] | 0 [200:3000:48015,T:3000:48000] | 0 [200:3000:48015,T:3000:48000] | 100 [200:3000:48015,T:1999:31984] | 100 [200:3000:48015,T:1999:31984] |
| tr-2+400K | h2 | 56 [200:2:47] | 56 [200:2:47] | 56 [200:2:47] | 16 [200:2:47] | 56 [200:2:47] |
| tr-200K+200K | h2 | 56 [] | 56 [] | 56 [] | 16 [200:658:168461] | 56 [200:658:168461] |
| tr-line4000 | h2 | 0 [200:2:47,T:1:4000] | 0 [200:2:47,T:1:4000] | 0 [200:2:47,T:1:4000] | 0 [200:2:47,T:1:4000] | 0 [200:2:47,T:1:4000] |
| tr-line5000 | h2 | 0 [200:2:47,T:1:5000] | 0 [200:2:47,T:1:5000] | 0 [200:2:47,T:1:5000] | 0 [200:2:47,T:1:5000] | 0 [200:2:47,T:1:5000] |
| auth-2+2 | h1 | 0 [401:3:156,200:2:54] | 0 [401:3:156,200:2:54] | 0 [401:3:156,200:2:54] | 0 [401:3:156,200:2:54] | 0 [401:3:156,200:2:54] |
| auth-6000+2 | h1 | 0 [401:6001:96124,200:2:54] | 0 [401:6001:96124,200:2:54] | 0 [401:6001:96124,200:2:54] | 100 [401:5000:80106] | 100 [401:5000:80106] |
| auth-3000+3000 | h1 | 0 [401:3001:48124,200:3000:48022] | 0 [401:3001:48124,200:3000:48022] | 0 [401:3001:48124,200:3000:48022] | 100 [401:3001:48124,200:1999:32004] | 100 [401:3001:48124,200:1999:32004] |
| auth-200K+200K | h1 | 0 [401:801:204684,200:800:204582] | 0 [401:801:204684,200:800:204582] | 0 [401:801:204684,200:800:204582] | 0 [401:801:204684,200:800:204582] | 0 [401:801:204684,200:800:204582] |
| redir-2+2 | h1 | 0 [302:3:106,200:2:54] | 0 [302:3:106,200:2:54] | 0 [302:3:106,200:2:54] | 0 [302:3:106,200:2:54] | 0 [302:3:106,200:2:54] |
| redir-3000+3000 | h1 | 0 [302:3001:48083,200:3000:48022] | 0 [302:3001:48083,200:3000:48022] | 0 [302:3001:48083,200:3000:48022] | 100 [302:3001:48083,200:1999:32004] | 100 [302:3001:48083,200:1999:32004] |
| redir-200K+200K | h1 | 0 [302:801:204651,200:800:204582] | 0 [302:801:204651,200:800:204582] | 0 [302:801:204651,200:800:204582] | 0 [302:801:204651,200:800:204582] | 0 [302:801:204651,200:800:204582] |
| auth-2+2 | h2 | 0 [401:3:142,200:2:50] | 0 [401:3:142,200:2:50] | 0 [401:3:142,200:2:50] | 0 [401:3:142,200:2:50] | 0 [401:3:142,200:2:50] |
| auth-6000+2 | h2 | 0 [401:6001:96110,200:2:50] | 0 [401:6001:96110,200:2:50] | 0 [401:6001:96110,200:2:50] | 100 [401:4999:80076] | 100 [401:4999:80076] |
| auth-3000+3000 | h2 | 0 [401:3001:48110,200:3000:48018] | 0 [401:3001:48110,200:3000:48018] | 0 [401:3001:48110,200:3000:48018] | 100 [401:3001:48110,200:1997:31968] | 100 [401:3001:48110,200:1997:31968] |
| auth-200K+200K | h2 | 56 [] | 56 [] | 56 [] | 16 [401:659:168316] | 56 [401:659:168316] |
| redir-2+2 | h2 | 0 [302:3:100,200:2:50] | 0 [302:3:100,200:2:50] | 0 [302:3:100,200:2:50] | 0 [302:3:100,200:2:50] | 0 [302:3:100,200:2:50] |
| redir-3000+3000 | h2 | 0 [302:3001:48077,200:3000:48018] | 0 [302:3001:48077,200:3000:48018] | 0 [302:3001:48077,200:3000:48018] | 100 [302:3001:48077,200:1997:31968] | 100 [302:3001:48077,200:1997:31968] |
| redir-200K+200K | h2 | 56 [] | 56 [] | 56 [] | 16 [302:660:168547] | 56 [302:660:168547] |
| expect-2+2 | h1 | 0 [417:2:70,100:0:25,200:2:54] | 0 [417:2:70,100:0:25,200:2:54] | 0 [417:2:70,100:0:25,200:2:54] | 0 [417:2:70,100:0:25,200:2:54] | 0 [417:2:70,100:0:25,200:2:54] |
| expect-6000+2 | h1 | 0 [417:6000:96038,100:0:25,200:2:54] | 0 [417:6000:96038,100:0:25,200:2:54] | 0 [417:6000:96038,100:0:25,200:2:54] | 100 [417:5000:80036] | 100 [417:5000:80036] |
| expect-3000+3000 | h1 | 0 [417:3000:48038,100:0:25,200:3000:48022] | 0 [417:3000:48038,100:0:25,200:3000:48022] | 0 [417:3000:48038,100:0:25,200:3000:48022] | 100 [417:3000:48038,100:0:25,200:2000:32020] | 100 [417:3000:48038,100:0:25,200:2000:32020] |
| expect-200K+200K | h1 | 0 [417:800:204598,100:0:25,200:800:204582] | 0 [417:800:204598,100:0:25,200:800:204582] | 0 [417:800:204598,100:0:25,200:800:204582] | 0 [417:800:204598,100:0:25,200:800:204582] | 0 [417:800:204598,100:0:25,200:800:204582] |
| connect-2+2 | h1tls+proxy | 0 [200:2:71,200:2:54] | 0 [200:2:71,200:2:54] | 0 [200:2:71,200:2:54] | 0 [200:2:71,200:2:54] | 0 [200:2:71,200:2:54] |
| connect-6000+2 | h1tls+proxy | 0 [200:6000:96039,200:2:54] | 0 [200:6000:96039,200:2:54] | 0 [200:6000:96039,200:2:54] | 100 [200:5000:80037] | 100 [200:5000:80037] |
| connect-3000+3000 | h1tls+proxy | 0 [200:3000:48039,200:3000:48022] | 0 [200:3000:48039,200:3000:48022] | 0 [200:3000:48039,200:3000:48022] | 100 [200:3000:48039,200:2000:32020] | 100 [200:3000:48039,200:2000:32020] |
| connect-400K+2 | h1tls+proxy | 0 [200:1600:409639,200:2:54] | 56 [200:1200:307237] | 56 [200:1200:307237] | 56 [200:1200:307237] | 56 [200:1200:307237] |
| connect-200K+200K | h1tls+proxy | 0 [200:800:204839,200:800:204582] | 56 [200:800:204839,200:401:102436] | 56 [200:800:204839,200:401:102436] | 0 [200:800:204839,200:800:204582] | 0 [200:800:204839,200:800:204582] |
| connect-2+2 | h2+proxy | 0 [200:2:71,200:2:50] | 0 [200:2:71,200:2:50] | 0 [200:2:71,200:2:50] | 0 [200:2:71,200:2:50] | 0 [200:2:71,200:2:50] |
| connect-6000+2 | h2+proxy | 0 [200:6000:96039,200:2:50] | 0 [200:6000:96039,200:2:50] | 0 [200:6000:96039,200:2:50] | 100 [200:5000:80037] | 100 [200:5000:80037] |
| connect-3000+3000 | h2+proxy | 0 [200:3000:48039,200:3000:48018] | 0 [200:3000:48039,200:3000:48018] | 0 [200:3000:48039,200:3000:48018] | 100 [200:3000:48039,200:1999:32000] | 100 [200:3000:48039,200:1999:32000] |
| connect-400K+2 | h2+proxy | 0 [200:1600:409639,200:2:50] | 56 [200:1200:307237] | 56 [200:1200:307237] | 56 [200:1200:307237] | 56 [200:1200:307237] |
| connect-200K+200K | h2+proxy | 56 [200:800:204839] | 56 [200:800:204839] | 56 [200:800:204839] | 16 [200:800:204839,200:659:168480] | 56 [200:800:204839,200:659:168480] |

No HEADERFUNCTION (none) against the counting one (obs): every cell's none-mode code equalled its
obs-mode code, in cases 1 to 3, on every lane, in both runs (`tables.mjs`'s check lists no cell).

| What | the count, 8.20.0 and 8.23.0 | the bytes, 8.5.0, 8.20.0 and 8.23.0 |
|---|---|---|
| a 1xx head (100, 103) | counted with the final head: `pre103-3000+3000` stops after 3,000 + 2,000 lines | counted with the final head: `pre103-200K+200K` refused at 307,264 bytes |
| HTTP/1.1 trailers | counted: `tr-3000+3000`, 3,000 + 2,000 | 8.23.0 alone: `tr-2+400K` refused at 307,263; 8.5.0 and 8.20.0 take 409,663 |
| HTTP/2 trailers | counted (`tr-3000+3000`, 3,000 + 1,999); 8.23.0 fails more than 5,000 trailers 56 before any is handed (`tr-2+6000`) | nghttp2 refuses `tr-2+400K` first |
| a Digest 401 round | counted across both responses: `auth-3000+3000` stops after 3,001 + 1,999 | each request starts at 0: `auth-200K+200K`, 409,266 bytes, taken |
| a followed redirect | across both (`redir-3000+3000`) | each request from 0 (`redir-200K+200K` taken) |
| a 417 and its resend | across both (`expect-3000+3000`) | each request from 0 (`expect-200K+200K` taken) |
| a `CONNECT` answer | counted with the tunnelled response's (`connect-3000+3000`) | 8.5.0: with the tunnelled response's, refused at 307,275; 8.20.0 and 8.23.0: from 0, 409,421 taken |

7.85.0 counts none of these: it took every HTTP/1.1 cell whole, 409,693 bytes of `CONNECT` answer
and response among them. Two more things the walk sees:

- **7.85.0 stores HTTP/2 trailers as `CURLH_HEADER`:** `tr-2+6000` over h2 walked 6,002 headers
  for `CURLH_HEADER`, request -1, where 8.5.0 walked 2 (and 6,002 with every origin). On 7.85.0 a
  walk of a response's headers over HTTP/2 returns its trailers too.
- **`CURLINFO_HEADER_SIZE`** sums every head of the transfer, 1xx, `CONNECT` and a 401 round's
  first response among them, equal to the callback's bytes, but leaves trailers out on every lane
  but 8.23.0:

*CURLINFO_HEADER_SIZE against the callback's bytes, cells ended 0 where they differ (= the same)*

| case | cell | face | F floor-7.85.0 | O ubuntu-openssl-8.5.0 | G ubuntu-gnutls-8.5.0 | X guix-8.20.0 | C current-8.23.0 |
|---|---|---|---|---|---|---|---|
| toward | tr-2+6000 | h1 | 63 vs 96063 | 63 vs 96063 | 63 vs 96063 | n/a | n/a |
| toward | tr-3000+3000 | h1 | 48031 vs 96031 | 48031 vs 96031 | 48031 vs 96031 | n/a | n/a |
| toward | tr-2+400K | h1 | 63 vs 409663 | 63 vs 409663 | 63 vs 409663 | 63 vs 409663 | n/a |
| toward | tr-200K+200K | h1 | 204591 vs 409391 | 204591 vs 409391 | 204591 vs 409391 | 204591 vs 409391 | n/a |
| toward | tr-line4000 | h1 | 63 vs 4063 | 63 vs 4063 | 63 vs 4063 | 63 vs 4063 | = |
| toward | tr-2+6000 | h2 | 47 vs 96047 | 47 vs 96047 | 47 vs 96047 | n/a | n/a |
| toward | tr-3000+3000 | h2 | 48015 vs 96015 | 48015 vs 96015 | 48015 vs 96015 | n/a | n/a |
| toward | tr-line4000 | h2 | 47 vs 4047 | 47 vs 4047 | 47 vs 4047 | 47 vs 4047 | = |
| toward | tr-line5000 | h2 | 47 vs 5047 | 47 vs 5047 | 47 vs 5047 | 47 vs 5047 | = |

## Case 4: a cap below libcurl's, in a `HEADERFUNCTION`

The cap mode's callback over every cell of cases 1 to 3: it refuses the line that takes the header
lines past 1,000 (`lines@1001`) or the bytes, status and empty lines in, past 102,400 (`bytes@N`,
the count with the refused line). "libcurl first" is a cell where libcurl (or nghttp2) ended the
transfer before the cap fired, with its code.

*Case 4, the cap (1,000 header lines, 102,400 bytes) in a HEADERFUNCTION, over case 1: the code, and what refused*

| cell | face | F floor-7.85.0 | O ubuntu-openssl-8.5.0 | G ubuntu-gnutls-8.5.0 | X guix-8.20.0 | C current-8.23.0 |
|---|---|---|---|---|---|---|
| n1000 | h1 | 0, none | 0, none | 0, none | 0, none | 0, none |
| n4999 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n5000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n5001 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n10000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n50000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n1000 | h1tls | 0, none | 0, none | 0, none | 0, none | 0, none |
| n4999 | h1tls | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n5000 | h1tls | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n5001 | h1tls | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n10000 | h1tls | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n50000 | h1tls | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n1000 | h2 | 0, none | 0, none | 0, none | 0, none | 0, none |
| n4999 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n5000 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n5001 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n10000 | h2 | 56, libcurl first | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n50000 | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 lines@1001 | 23 lines@1001 |
| n4999-same | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n5000-same | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n5001-same | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n10000-same | h2 | 56, libcurl first | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| n50000-same | h2 | 56, libcurl first | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |

*Case 4, the cap (1,000 header lines, 102,400 bytes) in a HEADERFUNCTION, over case 2: the code, and what refused*

| cell | face | F floor-7.85.0 | O ubuntu-openssl-8.5.0 | G ubuntu-gnutls-8.5.0 | X guix-8.20.0 | C current-8.23.0 |
|---|---|---|---|---|---|---|
| total307199 | h1 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 |
| total307200 | h1 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 |
| total307201 | h1 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 |
| total1048576 | h1 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 |
| line102398 | h1 | 23 bytes@102434 | 23 bytes@102434 | 23 bytes@102434 | 23 bytes@102434 | 23 bytes@102434 |
| line102399 | h1 | 23 bytes@102435 | 23 bytes@102435 | 23 bytes@102435 | 23 bytes@102435 | 23 bytes@102435 |
| line102400 | h1 | 27, libcurl first | 27, libcurl first | 27, libcurl first | 100, libcurl first | 100, libcurl first |
| line102401 | h1 | 27, libcurl first | 27, libcurl first | 27, libcurl first | 100, libcurl first | 100, libcurl first |
| total307199 | h1tls | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 |
| total307200 | h1tls | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 |
| total307201 | h1tls | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 |
| total1048576 | h1tls | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 | 23 bytes@102436 |
| line102398 | h1tls | 23 bytes@102434 | 23 bytes@102434 | 23 bytes@102434 | 23 bytes@102434 | 23 bytes@102434 |
| line102399 | h1tls | 23 bytes@102435 | 23 bytes@102435 | 23 bytes@102435 | 23 bytes@102435 | 23 bytes@102435 |
| line102400 | h1tls | 27, libcurl first | 27, libcurl first | 27, libcurl first | 100, libcurl first | 100, libcurl first |
| line102401 | h1tls | 27, libcurl first | 27, libcurl first | 27, libcurl first | 100, libcurl first | 100, libcurl first |
| total307199 | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 |
| total307200 | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 |
| total307201 | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 |
| total1048576 | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 |
| line102398 | h2 | 23 bytes@102430 | 23 bytes@102430 | 23 bytes@102430 | 23 bytes@102430 | 23 bytes@102430 |
| line102399 | h2 | 23 bytes@102431 | 23 bytes@102431 | 23 bytes@102431 | 23 bytes@102431 | 23 bytes@102431 |
| line102400 | h2 | 27, libcurl first | 27, libcurl first | 27, libcurl first | 16, libcurl first | 56, libcurl first |
| line102401 | h2 | 27, libcurl first | 27, libcurl first | 27, libcurl first | 16, libcurl first | 56, libcurl first |
| total307199-same | h2 | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 |
| total307200-same | h2 | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 |
| total307201-same | h2 | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 |
| total1048576-same | h2 | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 |
| line102400-X | h2 | 52, libcurl first | 56, libcurl first | 56, libcurl first | 16, libcurl first | 16, libcurl first |
| total131071 | h2 | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 |
| total131072 | h2 | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 |
| total131073 | h2 | 56, libcurl first | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 | 23 bytes@102432 |

*Case 4, the cap (1,000 header lines, 102,400 bytes) in a HEADERFUNCTION, over case 3: the code, and what refused*

| cell | face | F floor-7.85.0 | O ubuntu-openssl-8.5.0 | G ubuntu-gnutls-8.5.0 | X guix-8.20.0 | C current-8.23.0 |
|---|---|---|---|---|---|---|
| pre103-6000+2 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| pre103-3000+3000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| pre100-3000+3000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| pre103-2500x2+1000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| pre103-400K+2 | h1 | 23 bytes@102426 | 23 bytes@102426 | 23 bytes@102426 | 23 bytes@102426 | 23 bytes@102426 |
| pre103-200K+200K | h1 | 23 bytes@102426 | 23 bytes@102426 | 23 bytes@102426 | 23 bytes@102426 | 23 bytes@102426 |
| tr-2+6000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| tr-3000+3000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| tr-2+400K | h1 | 23 bytes@102463 | 23 bytes@102463 | 23 bytes@102463 | 23 bytes@102463 | 23 bytes@102463 |
| tr-200K+200K | h1 | 23 bytes@102445 | 23 bytes@102445 | 23 bytes@102445 | 23 bytes@102445 | 23 bytes@102445 |
| tr-line4000 | h1 | 0, none | 0, none | 0, none | 0, none | 0, none |
| tr-line5000 | h1 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 100, libcurl first | 100, libcurl first |
| pre103-6000+2 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| pre103-3000+3000 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| pre100-3000+3000 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| pre103-2500x2+1000 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| pre103-400K+2 | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 bytes@102413 | 23 bytes@102413 |
| pre103-200K+200K | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 bytes@102413 | 23 bytes@102413 |
| tr-2+6000 | h2 | 23 lines@1001 | 0 lines@1001 | 0 lines@1001 | 23 lines@1001 | 56, libcurl first |
| tr-3000+3000 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| tr-2+400K | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 16, libcurl first | 56, libcurl first |
| tr-200K+200K | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 bytes@102413 | 23 bytes@102413 |
| tr-line4000 | h2 | 0, none | 0, none | 0, none | 0, none | 0, none |
| tr-line5000 | h2 | 0, none | 0, none | 0, none | 0, none | 0, none |
| auth-2+2 | h1 | 0, none | 0, none | 0, none | 0, none | 0, none |
| auth-6000+2 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| auth-3000+3000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| auth-200K+200K | h1 | 23 bytes@102538 | 23 bytes@102538 | 23 bytes@102538 | 23 bytes@102538 | 23 bytes@102538 |
| redir-2+2 | h1 | 0, none | 0, none | 0, none | 0, none | 0, none |
| redir-3000+3000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| redir-200K+200K | h1 | 23 bytes@102505 | 23 bytes@102505 | 23 bytes@102505 | 23 bytes@102505 | 23 bytes@102505 |
| auth-2+2 | h2 | 0, none | 0, none | 0, none | 0, none | 0, none |
| auth-6000+2 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| auth-3000+3000 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| auth-200K+200K | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 bytes@102524 | 23 bytes@102524 |
| redir-2+2 | h2 | 0, none | 0, none | 0, none | 0, none | 0, none |
| redir-3000+3000 | h2 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| redir-200K+200K | h2 | 56, libcurl first | 56, libcurl first | 56, libcurl first | 23 bytes@102499 | 23 bytes@102499 |
| expect-2+2 | h1 | 0, none | 0, none | 0, none | 0, none | 0, none |
| expect-6000+2 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| expect-3000+3000 | h1 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| expect-200K+200K | h1 | 23 bytes@102452 | 23 bytes@102452 | 23 bytes@102452 | 23 bytes@102452 | 23 bytes@102452 |
| connect-2+2 | h1tls+proxy | 0, none | 0, none | 0, none | 0, none | 0, none |
| connect-6000+2 | h1tls+proxy | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| connect-3000+3000 | h1tls+proxy | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| connect-400K+2 | h1tls+proxy | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 |
| connect-200K+200K | h1tls+proxy | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 |
| connect-2+2 | h2+proxy | 0, none | 0, none | 0, none | 0, none | 0, none |
| connect-6000+2 | h2+proxy | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| connect-3000+3000 | h2+proxy | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 | 23 lines@1001 |
| connect-400K+2 | h2+proxy | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 |
| connect-200K+200K | h2+proxy | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 | 23 bytes@102437 |

- **The refusal's code is 23 on every lane:** `Failed writing header` on 7.85.0 and 8.5.0, `Failure
  writing output to destination, passed N returned 0` on 8.20.0 and 8.23.0, at once: the transfer
  ends with the refused line.
- **But not on 8.5.0 over HTTP/2 for a trailer:** `tr-2+6000`, the 1,001st header line a trailer,
  ended 0 on both 8.5.0 builds in all four runs (`docker-1.log`, `docker-2.log`,
  `docker-toward-cap-3.log`, `-4.log`), the error buffer holding `Failed writing header`. 7.85.0 and
  8.20.0 ended it 23; 8.23.0 refused it first itself (56). A refused HTTP/2 head line ended 23 on
  8.5.0 (`count` over h2).
- **Where libcurl comes first, the cap cannot:** a single line of 102,400 bytes or more (never
  handed); a trailer line of 5,000 bytes on HTTP/1.1, 4,000 taken (`Out of memory in chunked-encoding`, 56 on
  7.85.0 and 8.5.0, 100 on 8.20.0 and 8.23.0); an HTTP/2 head of more than 128 KiB on 7.85.0; an HTTP/2
  head nghttp2 refuses, on 7.85.0 and 8.5.0, which hand none of it; HTTP/2 trailers past nghttp2's
  limit, none of them handed first, on every lane; more than 5,000 HTTP/2 trailers on 8.23.0.
- **`CURLINFO_HEADER_SIZE` after the refusal** leaves the refused line out: 16,020 against the
  callback's 16,036 (`count n4999 h1`, cap mode).

## Case 5: the walk's cost

One whole walk, `curl_easy_nextheader` for `CURLH_HEADER` and request -1 until it answers NULL, as
`response-headers` walks, timed by the thread's CPU, after a transfer of N 16-byte lines over h1;
names distinct or all the same; 7 rounds a run, the order turned each round, so each figure is 14
samples over two runs. A second walk at once took the same on every lane but 8.23.0, whose cache
made it 0.001 to 0.072 ms (`walk2_cpu_ms`).

The walk's cost moves with the names as well as their number: a call compares the name it returns,
case folded, against every stored header's. These `x-000001` names share their first six bytes, and
7.85.0 walked 50,000 of them in 12.2 to 12.5 s (case 1's times); the records' 7.3 to 7.7 s for 50,000
on 7.85.0 walked the origin's `X-H-1: v` lines through chez-curl ([ci-first-run](../../ci-first-run/)).
`traps.md` and the surveys name 8.23.0 among the n² walks; this 8.23.0 build is not one.

*Case 5, the walk: one whole curl_easy_nextheader walk's CPU, ms, min / median / max over both runs' rounds (samples; code:stored)*

| N | names | F floor-7.85.0 | O ubuntu-openssl-8.5.0 | G ubuntu-gnutls-8.5.0 | X guix-8.20.0 | C current-8.23.0 |
|---|---|---|---|---|---|---|
| 100 | distinct | 0.06 / 0.06 / 0.07 (14; 0:100) | 0.07 / 0.07 / 0.09 (14; 0:100) | 0.07 / 0.08 / 0.10 (14; 0:100) | 0.23 / 0.23 / 0.29 (14; 0:100) | 0.01 / 0.01 / 0.03 (14; 0:100) |
| 100 | same | 0.06 / 0.06 / 0.07 (14; 0:100) | 0.07 / 0.07 / 0.09 (14; 0:100) | 0.07 / 0.07 / 0.09 (14; 0:100) | 0.18 / 0.19 / 0.25 (14; 0:100) | 0.01 / 0.01 / 0.01 (14; 0:100) |
| 1000 | distinct | 6.41 / 6.43 / 8.29 (14; 0:1000) | 7.14 / 7.53 / 9.39 (14; 0:1000) | 6.85 / 6.94 / 9.65 (14; 0:1000) | 20 / 21 / 25 (14; 0:1000) | 0.07 / 0.08 / 0.15 (14; 0:1000) |
| 1000 | same | 6.01 / 6.06 / 7.74 (14; 0:1000) | 6.43 / 6.52 / 7.78 (14; 0:1000) | 6.42 / 6.55 / 8.36 (14; 0:1000) | 19 / 19 / 24 (14; 0:1000) | 0.07 / 0.07 / 0.11 (14; 0:1000) |
| 2000 | distinct | 24 / 24 / 26 (14; 0:2000) | 28 / 28 / 36 (14; 0:2000) | 26 / 27 / 35 (14; 0:2000) | 75 / 77 / 82 (14; 0:2000) | 0.15 / 0.17 / 0.28 (14; 0:2000) |
| 2000 | same | 24 / 24 / 29 (14; 0:2000) | 25 / 28 / 33 (14; 0:2000) | 25 / 26 / 33 (14; 0:2000) | 75 / 76 / 76 (14; 0:2000) | 0.14 / 0.15 / 0.16 (14; 0:2000) |
| 5000 | distinct | 140 / 141 / 157 (14; 0:5000) | 172 / 173 / 205 (14; 0:5000) | 160 / 165 / 188 (14; 0:5000) | 454 / 465 / 495 (14; 0:5000) | 0.41 / 0.45 / 0.54 (14; 0:5000) |
| 5000 | same | 148 / 148 / 158 (14; 0:5000) | 159 / 164 / 201 (14; 0:5000) | 160 / 162 / 196 (14; 0:5000) | 471 / 478 / 536 (14; 0:5000) | 0.39 / 0.42 / 0.52 (14; 0:5000) |

Under Valgrind with the memory gate's options (`-v --command-line-only=yes --error-exitcode=9
--leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite`, the Guix
suppression), lane X, 3 rounds a run, the probe under Valgrind and the stand-in native. Each run
ended `ERROR SUMMARY: 0 errors`, the Guix suppression used once
(`results/valgrind-guix-8.20.0-{1,2}.vg`).

*Case 5 under Valgrind, lane X, valgrind run 1 (.plans/research/m8/caps/results/valgrind-guix-8.20.0-1.log): the walk's CPU, ms, each round*

| N | names | walk CPU ms | samples |
|---|---|---|---|
| 1000 | distinct | 324, 338, 347 | 3 |
| 1000 | same | 334, 338, 359 | 3 |
| 5000 | distinct | 7272, 7390, 7400 | 3 |
| 5000 | same | 8453, 8509, 8603 | 3 |

*Case 5 under Valgrind, lane X, valgrind run 2 (.plans/research/m8/caps/results/valgrind-guix-8.20.0-2.log): the walk's CPU, ms, each round*

| N | names | walk CPU ms | samples |
|---|---|---|---|
| 1000 | distinct | 326, 334, 339 | 3 |
| 1000 | same | 335, 338, 347 | 3 |
| 5000 | distinct | 7335, 7346, 7349 | 3 |
| 5000 | same | 8414, 8429, 8518 | 3 |

## Case 6: a Scheme callable per header line

`stream-cost.sps`, through today's `(curl)` on this tree, unchanged, on lane X: one engine, GETs of
`/head` on the h1 face, direct, a 60 s timeout, buffered (no `stream-buffer`) and streamed
(`stream-buffer` 65536). `final` is a 200 of N lines; `pre` a 103 of N - 2 lines, then a 200 of 2,
so the streamed path's callable takes N + 4 lines while each walk returns 2 headers, scanning the N
stored. 7 rounds a run, the order turned. Process CPU is the engine's thread's work (this thread
sleeps in `curl-token-wait`'s polls); wall is to the wait's return, whose polls sleep up to 10 ms;
libcurl's total ends before `finish-transfer`'s walk.

*Case 6, lane X, run 1 (.plans/research/m8/caps/results/stream-cost-guix-8.20.0-1.log): min / median / max*

| way | head | N | status:headers[:head] | process CPU ms | wall ms | libcurl total ms | samples |
|---|---|---|---|---|---|---|---|
| buffered | base | 2 | 200:2 | 0.3 / 0.3 / 0.5 | 0.6 / 0.6 / 1.1 | 0.2 / 0.3 / 0.4 | 7 |
| streamed | base | 2 | 200:2:2 | 0.2 / 0.2 / 0.4 | 0.5 / 0.6 / 1.0 | 0.2 / 0.3 / 0.4 | 7 |
| buffered | final | 1000 | 200:1000 | 20.8 / 21.4 / 21.9 | 23.3 / 23.3 / 23.3 | 0.5 / 0.6 / 1.2 | 7 |
| streamed | final | 1000 | 200:1000:1000 | 42.2 / 42.7 / 42.9 | 43.4 / 43.5 / 53.5 | 21.9 / 22.3 / 22.8 | 7 |
| buffered | pre | 1000 | 200:2 | 0.5 / 0.6 / 1.1 | 1.9 / 2.0 / 3.6 | 0.9 / 1.0 / 1.9 | 7 |
| streamed | pre | 1000 | 200:2:2 | 0.8 / 0.9 / 2.3 | 1.9 / 1.9 / 3.7 | 1.0 / 1.5 / 2.8 | 7 |
| buffered | final | 5000 | 200:5000 | 458.1 / 467.3 / 470.6 | 466.0 / 476.1 / 477.4 | 2.5 / 3.4 / 4.0 | 7 |
| streamed | final | 5000 | 200:5000:5000 | 922.0 / 935.2 / 956.3 | 929.0 / 939.4 / 959.4 | 466.8 / 473.6 / 478.8 | 7 |
| buffered | pre | 5000 | 200:2 | 1.2 / 1.5 / 3.6 | 3.6 / 6.9 / 13.5 | 2.8 / 3.4 / 5.8 | 7 |
| streamed | pre | 5000 | 200:2:2 | 3.2 / 4.1 / 4.3 | 6.8 / 6.8 / 7.5 | 4.2 / 4.7 / 5.8 | 7 |

*Case 6, lane X, run 2 (.plans/research/m8/caps/results/stream-cost-guix-8.20.0-2.log): min / median / max*

| way | head | N | status:headers[:head] | process CPU ms | wall ms | libcurl total ms | samples |
|---|---|---|---|---|---|---|---|
| buffered | base | 2 | 200:2 | 0.2 / 0.3 / 0.5 | 0.6 / 0.6 / 1.1 | 0.2 / 0.3 / 0.3 | 7 |
| streamed | base | 2 | 200:2:2 | 0.2 / 0.2 / 0.4 | 0.5 / 0.6 / 1.0 | 0.2 / 0.3 / 0.3 | 7 |
| buffered | final | 1000 | 200:1000 | 20.8 / 21.8 / 26.8 | 23.3 / 23.3 / 33.5 | 0.4 / 0.5 / 1.1 | 7 |
| streamed | final | 1000 | 200:1000:1000 | 42.6 / 42.8 / 43.1 | 43.4 / 53.5 / 53.6 | 21.9 / 22.4 / 22.9 | 7 |
| buffered | pre | 1000 | 200:2 | 0.5 / 0.6 / 0.6 | 1.9 / 2.0 / 3.7 | 0.8 / 1.1 / 1.9 | 7 |
| streamed | pre | 1000 | 200:2:2 | 0.8 / 1.0 / 2.0 | 1.8 / 2.9 / 3.6 | 1.0 / 1.5 / 2.1 | 7 |
| buffered | final | 5000 | 200:5000 | 463.2 / 467.9 / 484.4 | 466.2 / 476.4 / 488.4 | 2.0 / 2.4 / 4.2 | 7 |
| streamed | final | 5000 | 200:5000:5000 | 913.8 / 931.6 / 943.0 | 919.3 / 939.5 / 951.2 | 455.7 / 469.3 / 477.0 | 7 |
| buffered | pre | 5000 | 200:2 | 1.1 / 1.4 / 1.5 | 3.6 / 3.7 / 7.0 | 1.9 / 2.4 / 5.7 | 7 |
| streamed | pre | 5000 | 200:2:2 | 3.2 / 3.9 / 5.0 | 6.8 / 6.8 / 7.0 | 4.2 / 4.5 / 5.4 | 7 |

From the medians, run 1 then run 2:

- **The callable, per line:** streamed `pre` less buffered `pre` is 2.6 and 2.5 ms of process CPU
  for the 5,004 lines at N = 5,000, about 0.5 µs a line; 0.3 and 0.4 ms for the 1,004 at N = 1,000.
- **The walk through `(curl)`:** buffered `final` less buffered `pre` is 20.8 and 21.2 ms at 1,000,
  465.8 and 466.5 ms at 5,000: within 1 ms of case 5's bare walk on this lane (medians 21 and 465),
  so the Latin-1 copies of names and values add little beside libcurl's n².
- **The streamed path's second walk:** streamed `final` less buffered `final` is 21.3 and 21.0 ms at
  1,000, 467.9 and 463.7 ms at 5,000: one more walk, of which the callable's 5,002 calls are about
  2.5 ms. libcurl's own total for a streamed `final` of 5,000, 455.7 to 478.8 ms against 2.0 to 4.2
  buffered, holds the first walk: `head-line!` runs it inside `curl_multi_perform`, so it stalls the
  engine's turn.
- A callable on every line cost about 0.5% of one walk at 5,000 on 8.20.0 (2.5 of 465 ms), and
  about 2% at 1,000 (0.35 of 21 ms).

## What the plan must decide

From the measurements; the choices are the plan's.

1. **The count, and what it counts.** libcurl's 5,000 (8.20.0 and 8.23.0) spans the whole transfer,
   every 1xx head, trailer, `CONNECT` answer and resend's response in, and takes one slot more per
   HTTP/2 head. A count of every header line handed, kept across the transfer, at 1,000 fired before
   libcurl's 5,000 in every cell of cases 1 and 3 on 8.20.0 and 8.23.0. A count per response would
   not: a 401 round, a redirect, a 417, a 1xx head or a `CONNECT` answer of 3,000 lines, each with a
   final head of 3,000, was refused 100 by libcurl. Whether a head of no lines counts is open
   (below).
2. **The bytes, and what they count.** libcurl counts every byte handed, status line, CR LF and empty
   line in, per request, 1xx heads with the final one, and resets at a resend's response; 8.5.0
   alone keeps a `CONNECT` answer's bytes, and 8.23.0 alone counts trailers. A byte count kept across
   the transfer, every line in, at 102,400 fired before libcurl wherever libcurl handed the lines.
3. **The single long line.** One line of 102,400 bytes is refused by libcurl on every lane before any
   callback sees it, with 27, 100, 16 or 56 by version and protocol, and an empty error buffer for
   27 and for HTTP/1.1's 100. A `HEADERFUNCTION` cap cannot name it; the plan decides whether these
   codes map to the cap's reason, how it tells them from other 27s, 56s and 16s, or whether the line
   limit is documented as libcurl's.
4. **HTTP/2's lower limits.** nghttp2 refuses a header block past its `CONTINUATION` limit (168,480
   decoded bytes of distinct 256-byte lines here), and 7.85.0 a head past 128 KiB; 7.85.0 and 8.5.0
   hand none of such a head first, so no callback cap fires there at any value. "Every lane refuses
   alike" cannot hold for those heads; the plan names what they answer (56 on 7.85.0, 8.5.0 and
   8.23.0, 16 on 8.20.0, nghttp2's `-905` or 7.85.0's `-902` in the error buffer).
5. **8.5.0 loses a refused HTTP/2 trailer.** Both 8.5.0 builds ended `tr-2+6000` over HTTP/2 0 after
   the callback refused its 1,001st line, a trailer, in all four runs (`docker-1.log`, `docker-2.log`,
   `docker-toward-cap-3.log`, `docker-toward-cap-4.log`). `finish-transfer` reads a recorded reason
   before the code (`transfer.sls:4461-4470`), so a cap that records its reason fails such a transfer;
   one that relies on libcurl's code does not. Whether trailers are capped at all is the plan's:
   `response-headers` walks `CURLH_HEADER`, which leaves them out on every lane but 7.85.0 over
   HTTP/2.
6. **The buffered path sets no `HEADERFUNCTION` today** (`set-transfer-options!`, `transfer.sls:4175`).
   A cap in a callback sets one on every transfer: about 0.5 µs a line on lane X (case 6).
7. **The walk's cost at the cap.** With a count of C, a buffered response walks once and a streamed
   one twice, at about (C/5,000)² of case 5's 5,000 figure on 7.85.0, 8.5.0 and 8.20.0, linear on
   8.23.0: at 1,000, 6 to 10 ms on 7.85.0 and 8.5.0 and 19 to 25 ms on 8.20.0 a walk; at libcurl's
   own 5,000, 140 to 205 ms and 454 to 536 ms; about 16 to 18 times that under Valgrind on 8.20.0.
8. **7.85.0's HTTP/2 trailers are headers:** a walk for `CURLH_HEADER` returns them, so a count of
   the walk and a count of the callback's head lines differ there.

## What was not measured, and why

- **Apple's 8.7.1:** `mac.sh` is written and `sh -n` clean; the maintainer runs it on the Mac. Its
  results go to `results/mac-8.7.1-{1,2}.log`, which `tables.mjs` reads as lane M when present.
- **Heads with no lines, in number.** An HTTP/2 head's `:status` takes a slot of 8.20.0's 5,000
  whether or not the head has lines, and an HTTP/1.1 1xx head's status line counts toward the
  307,200 bytes; a server sending thousands of empty 103 heads was not run (the stand-in's `pre`
  list rides in the URL).
- **Where nghttp2's `CONTINUATION` limit falls in bytes.** It counts frames, so its cut moves with
  HPACK's encoding of the lines; only distinct 256-byte `v` lines were run to it, and 50,000 16-byte
  lines (refused on 8.5.0; 652,759 bytes on the wire in lane X's run 1) and 10,000 (taken on 8.5.0;
  131,766).
- **An HTTPS proxy, or a `CONNECT` over HTTP/2:** the proxy face is plaintext HTTP/1.1 alone.
- **Valgrind on any lane but X, and case 6 on any lane but X:** the brief asks lane X alone.
- **Linux arm64 and macOS amd64:** no host here.
- The runs shared the host with two other probes on CPUs 0 to 11; this one's ran on 12 to 17 alone.
  Times are CPU where the tables say so, and spread over rounds; none is a CI runner's.

## Every run agreed

Every verdict of cases 1 to 4, code and where it stopped, was the same in runs 1 and 2 on all five
lanes (`tables.mjs`'s "Cells the runs split" is empty), and the none mode's code equalled the obs
mode's in every cell. Two more runs of case 3 in cap mode on the Docker lanes
(`results/docker-toward-cap-3.log`, `-4.log`) gave the same verdicts, but one byte in
`redir-200K+200K` over h2 on 8.23.0 (`bytes@102498` for 102,499): the redirect's `location` carries
the cell's tag, whose sequence number has a digit fewer in those runs.

## How to rerun

From the repository's root, on the host; each run's lines are prefixed by its lane:

```sh
# lane X, the Guix container (twice: -1 and -2)
taskset -c 12-17 scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m8/caps/run.sh guix-8.20.0-1' < /dev/null > .plans/research/m8/caps/results/guix-8.20.0-1.log 2>&1
# lanes F, O, G and C: Docker ubuntu:24.04, --network none, --cpuset-cpus 12-17 (twice: docker-1, -2)
sh .plans/research/m8/caps/docker.sh > .plans/research/m8/caps/results/docker-1.log 2>&1
# case 5 under the memory gate's Valgrind, lane X (twice)
taskset -c 12-17 scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL PROBE_VALGRIND=.plans/research/m8/caps/results/valgrind-guix-8.20.0-1.vg sh .plans/research/m8/caps/run.sh valgrind-guix-8.20.0-1' < /dev/null > .plans/research/m8/caps/results/valgrind-guix-8.20.0-1.log 2>&1
# case 6, Chez through today's (curl), lane X (twice)
taskset -c 12-17 scripts/guix-env sh .plans/research/m8/caps/stream-cost.sh guix-8.20.0-1 < /dev/null > .plans/research/m8/caps/results/stream-cost-guix-8.20.0-1.log 2>&1
# case 3 in cap mode alone, on the Docker lanes
CASES=toward PROBE_MODES=cap sh .plans/research/m8/caps/docker.sh > .plans/research/m8/caps/results/docker-toward-cap-3.log 2>&1
# the tables, from the kept logs
scripts/guix-env node .plans/research/m8/caps/tables.mjs < /dev/null > build/m8/caps/tables.md
# the Mac, Apple's 8.7.1
sh .plans/research/m8/caps/mac.sh
```

`CASES` (`count bytes toward walk`) and `PROBE_MODES` (`obs none cap`) narrow a run; `WALK_NS` and
`WALK_ROUNDS` set case 5's sizes and rounds. A lane X run takes about 90 s, a Docker run about 3.5
min, a Valgrind run about 100 s.

## Files

| file | what it is |
|---|---|
| `probe.c` | the probe: cases `count`, `bytes`, `toward` and `walk`, each cell in modes `obs`, `none` and `cap` |
| `server.mjs` | the stand-in: faces `h1`, `h1tls`, `h2`, `proxy`, `ctl` |
| `run.sh` | one lane: the compile, the run's PKI, the stand-in, the cases; `PROBE_VALGRIND` for case 5 under the gate |
| `docker.sh` | lanes F, O, G and C in one `ubuntu:24.04` container |
| `mac.sh` | Apple's 8.7.1, twice |
| `stream-cost.sps`, `stream-cost.sh` | case 6, Chez through `(curl)`, lane X |
| `tables.mjs` | the tables above, from `results/` |
| `results/guix-8.20.0-{1,2}.log` | lane X, every case |
| `results/docker-{1,2}.log` | lanes F, O, G, C, every case |
| `results/docker-toward-cap-{3,4}.log` | case 3 in cap mode, lanes F, O, G, C |
| `results/valgrind-guix-8.20.0-{1,2}.log`, `.vg` | case 5 under Valgrind, the probe's lines and Valgrind's own log |
| `results/stream-cost-guix-8.20.0-{1,2}.log` | case 6 |

