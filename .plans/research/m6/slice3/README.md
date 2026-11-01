# M6 slice 3: the measurements of the plan's §6.1 (2026-10-31)

Measured before the slice builds anything, on main's own `src/` at 777fa68 (slices 1 and 2
merged), with no patch. Every log names what it ran on, its first line:
`grep -h '\] src ' results/*.log | sort | uniq -c` gives one hash,
`801c4673…` (`801c46734ba31e8706e6b5f7eddd29bf1603d8a40e24f9890d78bae0630e73fd`), the sha256 of
`src/`'s `.sls` files concatenated in sorted path order, which is main's. Every grep below runs
from this directory.

**In short:**

- **Item 1.** Where a final head can come before libcurl's first ask (7.85.0 and both 8.5.0s,
  over HTTP/1.1, plaintext or TLS), libcurl never asks after a head of 300 or more: 696 of 696,
  252 at the origin's `/raw/arm` and 444 at keep-alive, close and late answers; nor after a 200
  that closes, 48 of 48. **But it does ask after a 200 kept alive**, within 0.2 ms, 72 of 72, and
  waits for the body. On 8.20.0 and 8.23.0
  no final head came before the first ask, in 624 of 624 held cases over every face. The plan's
  rule holds for a hop; the final head must be fed when asked.
- **Item 2.** The drive works on every lane and face, both bodies whole in all 600 runs of a and
  b, and its producer never called for a refused connect. Feeding inside the port's read is
  needed: without it every full-duplex call stalled to the bound, 60 of 60, and every early answer
  on 7.85.0, 40 of 40. No libcurl sent a byte of the body after an early answer. **On 8.20.0 and
  8.23.0 every 3xx over HTTP/2 never ends, even fed** (40 of 40), and a cancel at the head's
  Content-Length ends it. The brief's strict alternation costs a slice per 64 KiB piece (2.1 to
  2.6 MB/s at S=50, 9.6 to 12.7 at S=10, 47 to 96 at S=1); an eager variant with no new low-level
  wait gave 24.1 to 212.6 at S=10. Under Valgrind, unheld, 8.5.0's echo read the bit `#f` in 7 of 18 calls, and the
  brief's rule stalled each of those it drove to the bound.

## The programs and what ran them

- `asked.sps` (sha256 `705f5fe4…`) made `asked-*.log`; `server.mjs` (`f1c9f298…`) served every
  run.
- `drive-v1.sps` (`1fd31a43…`) is the drive's first build, which ran as `drive.sps` and made
  `drive-e`, `drive-eager`, `drive-c`, `drive-idle`, `drive-hops`, `drive-hopcancel`,
  `drive-valgrind` and `drive-valgrind-strict`; Valgrind's `Command:` lines in those name
  `drive.sps`. Its eager variant keeps a side's progress flag while that side is not stepped (see
  the traps); on every path that feeds, that changes nothing.
- `drive.sps` (`ab8e4e61…`), the second build, adds case f, `final-feeds`, and clears the eager
  flag at an empty wait; with the first build's options it runs as the first did. It made
  `drive-f`, `drive-f-final` and `drive-valgrind-final`, whose logs print its hash
  (`grep -h '\] program ' results/*.log | sort | uniq -c`).
- `sha256sum *.sps server.mjs` gives each whole.

## Item 1: does libcurl ask for the body after a final head that came before its first ask?

Every case ran on `make-curl-engine-holding-prereq 200`, whose prerequest callable holds the
engine's thread 200 ms once connected, before the request is sent, so an answer written at accept
(or, over TLS, as the handshake ends) is in the socket before the request leaves. A streamed `post`
or `put` of 1,000 bytes, sized or chunked, `stream-buffer` 1,024; nothing put. Each line says the
head's bit, when libcurl first asked against the head's publication (`first-ask=`, both the
engine's monotonic clock, from the request stream's `asked-at` and the stream's `head-at`), whether
the transfer ended on its own within 1,500 ms, its body, then (`then=`) what feeding it did. Every
one of the 1,560 cases made exactly one hold (`holds=1`) and left no native object
(`asked counts`).

### The brief's matrix: `tests/origin.mjs`'s `/raw/arm`

480 cases, 96 a lane: 200 (the control), 301, 302, 303, 307, 308, 413 and 503, `post` and `put`,
sized and chunked, three runs. The arm answers with Content-Length, `Connection: close` and the
body, then ends its side.

| lane | the head's bit | libcurl's first ask | ended on its own | body |
|---|---|---|---|---|
| floor-7.85.0, ubuntu-openssl-8.5.0, ubuntu-gnutls-8.5.0 | `#f`, 96 of 96 each | **never**, 96 of 96 | yes, 3.635–4.853 ms after the head, with the status | "early S\n" whole |
| guix-8.20.0, current-8.23.0 | `#t`, 96 of 96 each | before the head, 0.083–0.311 ms, with the request's head: one call, `paused`, nothing handed | yes, 3.53–4.811 ms after the head, with the status | whole |

So against an answer that closes, no libcurl asks after the head, at any status, the 200 included,
and every transfer ends on its own: 480 of 480, each outcome its status, `handed=0`.

- `grep -h 'asked part=origin' results/asked-origin-*.log | grep -c 'ended-own=yes .*body-whole=yes'` (480)
- `grep -h 'asked part=origin' results/asked-origin-*.log | grep -o '^\[[^]]*\]\|bit=[^ ]*\|first-ask=[a-z-]*' | paste - - - | sort | uniq -c`
- `grep -h 'asked part=origin' results/asked-origin-*.log | grep -o 'first-ask=before-head:[-0-9.]*' | cut -d: -f2 | sort -n | sed -n '1p;$p'`
- `for l in floor-7.85.0 ubuntu-openssl-8.5.0 ubuntu-gnutls-8.5.0 guix-8.20.0 current-8.23.0; do grep -h "^\[$l\] asked part=origin" results/asked-origin-*.log | grep -o 'end-ms=+[0-9.]*' | cut -d+ -f2 | sort -n | sed -n '1p;$p'; done`

### Beyond the brief: keep-alive and late answers, TLS, HTTP/2 (`server.mjs`)

1,080 cases, 216 a lane, two runs a cell. `raw-keep`, `raw-later`: the plaintext face's arm, the
answer whole and keep-alive (`keep`), or the head alone, its body once the request is read whole
(`later`), every status, both methods, both framings. `https-close`, `https-keep`, `https-later`:
the TLS face's arm, answered as the handshake ends: 200, 303, 307, 413, `post`, both framings.
`h2-headers`: `/answer-at?after=0` on the h2 face, answered as the request's headers arrive, the
stream ended: 200, 303, 307, 413, 503, both methods, both framings. Where the transfer had not
ended by 1,500 ms, the body was put and ended if libcurl had asked (`fed`), and the token cancelled
1,500 ms later if still live (`then-cancelled`); else cancelled (`cancelled`).

**HTTP/1.1, plaintext and TLS:**

| lane | ≥ 300 (301–308, 413, 503) | 200, keep-alive or late |
|---|---|---|
| 7.85.0 and both 8.5.0s | bit `#f`; **never asked**, 444 of 444. keep and close end on their own; later never ends, the server waiting for the body: cancelled | bit `#f`; **libcurl asks after the head, 0.004–0.189 ms after it**, 72 of 72, and the transfer waits for the body; fed, it ends 200 |
| 8.20.0 and 8.23.0 | bit `#t`, asked before the head; keep and close end on their own; later: the put is taken, never handed (`handed=0`), and the transfer never ends: cancelled | bit `#t`; keep and later wait for the body, fed they end 200 |

A 200 that closes (`https-close` 200, 12 of 12 on 7.85.0 and 8.5.0) behaves as the origin's arm: bit
`#f`, never asked, ended on its own.

- `grep -h 'asked part=faces face=\(raw\|https\)-\(keep\|later\|close\) status=\(30[0-9]\|413\|503\)' results/asked-faces-docker.log | grep -v server: | grep '^\[\(floor\|ubuntu\)' | grep -c 'bit=#f .*first-ask=never'` (444)
- `grep -h 'asked part=faces face=\(raw\|https\)-\(keep\|later\) status=200' results/asked-faces-docker.log | grep -v server: | grep '^\[\(floor\|ubuntu\)' | grep -c 'bit=#f .*first-ask=after-head.*ended-own=no.*then=fed:put=#t:ended=#t.*outcome=status=200'` (72)
- `grep -h 'asked part=faces' results/asked-faces-docker.log | grep -v server: | grep -o 'first-ask=after-head:+[0-9.]*' | cut -d+ -f2 | sort -n | sed -n '1p;$p'`
- the whole table: `grep -h 'asked part=faces' results/asked-faces-*.log | grep -v server: | grep -o '^\[[^]]*\]\|face=[^ ]*\| status=[0-9]*\|bit=[^ ]*\|first-ask=[a-z-]*\|ended-own=[a-z]*\|then=[a-z]*' | paste - - - - - - - | sort | uniq -c`

**HTTP/2,** the answer at the request's headers:

| lane | the head | first ask | without a put | fed |
|---|---|---|---|---|
| floor-7.85.0 | bit `#t` | 1.163–4.754 ms before the head (all lanes but OpenSSL's 8.5.0) | no status ends | every status ends with it |
| ubuntu-openssl-8.5.0 | **none published while the send is paused**: head-wait's 5,000 ms passed, 40 of 40 | at 202.29–206.8 ms, after the hold | never ends | ends with the status |
| ubuntu-gnutls-8.5.0 | bit `#t` | before | 200 ends on its own; 303, 307, 413, 503 do not | they end with the status |
| guix-8.20.0 | bit `#t` | before | 413 and 503 end on their own | 200 ends **55**, 8 of 8; **303 and 307 never end**, the put taken and never handed: cancelled |
| current-8.23.0 | bit `#t` | before | 413 and 503 end on their own | 200 ends 200; **303 and 307 never end**: cancelled |

OpenSSL's 8.5.0 is cdd905a9's stall (slice 2's item 3b): the response does not reach the header
callable while the send is paused, so there the drive's feeding during its head wait is what brings
the head.

- `grep -h 'asked part=faces face=h2-headers' results/asked-faces-docker.log | grep -v server: | grep '^\[ubuntu-openssl' | grep -c 'head=#f bit=no-head.*then=fed:put=#t:ended=#t'` (40)
- `grep -h 'asked part=faces face=h2-headers' results/asked-faces-*.log | grep -v server: | grep -v '^\[ubuntu-openssl' | grep -c 'bit=#t .*first-ask=before-head'` (160 of 160)

### On 8.20.0 and 8.23.0, can a final head come before the first ask?

**No way was found.** In all 624 held cases on the two lanes (192 at the origin's arm, 432 at
`server.mjs`'s raw, TLS and HTTP/2 faces), the bit read `#t` and the first ask came before the
head. Both ask with the request's head, as they build it, before a byte
is sent (slice 2), and read no response before that: an answer already waiting in the socket,
plaintext or TLS, is read after the ask. Over HTTP/2 a server cannot answer a stream before the
client's HEADERS open it. What else was weighed, not run: `Expect: 100-continue`, which would make
libcurl send the head and wait before asking, is refused beside a streamed response
(`stream-with-rounds`, slice 1), and `call-with-response-port` streams every response; a 1xx is no
final head; a CONNECT tunnel's head reads code 0 (slice 1); `body-length` 0 is never asked for on
any libcurl (slice 2), so its bit is `#f` on all five with nothing to feed.

`grep -h 'asked part=' results/asked-*.log | grep -v server: | grep '^\[\(guix\|current\)' | grep -c 'bit=#t .*first-ask=before-head'` (624 of 624 in item 1)

### So, for the plan's §3.6

- **The plan's premise holds for a hop:** a head of 300 or more that came before libcurl's first
  ask is never followed by an ask, on 7.85.0 and both 8.5.0s, 696 of 696 (252 at the origin's arm,
  444 at `server.mjs`), keep-alive, close or late, plaintext or TLS. On 8.20.0 and 8.23.0 no head
  comes before the ask.
- **But a final 2xx is not a hop:** on 7.85.0 and 8.5.0 a 200 that came before the first ask, kept
  alive, is followed by an ask within 0.2 ms, and the transfer waits for the body. A drive that
  never calls the producer after a head whose bit is `#f` (the brief's rule) leaves it to the
  bound. The "never fed" rule belongs to a head the call steps past; the head handed to PROC must
  be fed whenever libcurl asks.
- **A hop asked for may never end on its own, even fed:** HTTP/2's 303 and 307 on 8.20.0 and
  8.23.0. The plan's "read whole" then waits for the bound; item 2's c shows it, and a cancel at
  the head's Content-Length ends it.

## Item 2: the drive's interleaving, through the engine

The drive (`drive-v1.sps` for a to e, `drive.sps` for f and the final Valgrind run) is the
brief's, at the low level on the caller's thread (each file's header says each rule). Each call has an engine of its own, `stream-buffer` 65,536, and a producer of 64 KiB pieces
of the pattern. Each response body was checked byte for byte against the pattern (`port=end:N:ok`,
the first bad offset in place of `ok`), and the server's sink line gives the request body's SHA-256
(`want_sha=ok`) and what it sent (`sent_sha=`, `echo_sha=`). The pattern compared by position over
the whole length is exactly the SHA-256 check of `pattern(N)`: two sequences that agree byte for
byte have one hash. `sched=strict` is the brief's alternation, each wait bounded by S;
`sched=eager` is a variant of mine: a side's wait is 0 ms when the other side's last step moved
something, else S (in `drive.sps`, moved since this side's own last empty wait; see the traps).

### a, b and e: sequential, full-duplex, and the slice S

`drive-e` (strict, S of 1, 10 and 50) and `drive-eager` (S of 10 and 50), raw, https and h2, sized
and chunked, two runs: **600 transfers, every one whole both ways**: 600 sink lines `want_sha=ok`,
300 `seq ... written=4194304`, 300 `echo ... written=16777216` with one `echo_sha=` (that of 16 MiB
of the pattern), and every port `end:N:ok` with outcome 200. MB/s is up and down bytes over the
call's wall time; CPU is the process's, every thread's, over the call. Ranges cover the three
faces and both framings:

| case | sched, S | 7.85.0 | 8.5.0, OpenSSL | 8.5.0, GnuTLS | 8.20.0 | 8.23.0 | CPU, ms, all lanes |
|---|---|---|---|---|---|---|---|
| a, 4 MiB each way | strict 1 | 50.6–96.0 | 47.5–59.7 | 49.0–54.8 | 52.5–92.5 | 54.1–90.2 | 24.9–48.4 |
| | strict 10 | 11.0–12.5 | 11.1–11.8 | 11.0–11.6 | 11.3–12.6 | 11.3–12.7 | 25.7–73.1 |
| | strict 50 | 2.50–2.60 | 2.49–2.55 | 2.49–2.54 | 2.51–2.60 | 2.51–2.60 | 35.9–105.1 |
| | eager 10 | 35.8–212.6 | 38.9–68.7 | 38.0–67.4 | 58.0–73.3 | 56.3–78.6 | 22.1–50.6 |
| | eager 50 | 31.3–105.9 | 33.1–50.7 | 32.9–50.6 | 43.8–57.3 | 40.6–60.1 | 22.1–49.2 |
| b, 16 MiB each way | strict 1 | 47.1–71.7 | 53.5–71.0 | 54.9–63.4 | 50.2–74.6 | 50.4–74.8 | 90.0–168.3 |
| | strict 10 | 9.64–11.8 | 9.96–11.9 | 9.76–10.4 | 10.1–11.8 | 9.88–11.8 | 148.7–394.3 |
| | strict 50 | 2.14–2.51 | 2.34–2.47 | 2.41–2.47 | 2.43–2.48 | 2.34–2.52 | 195.4–574.2 |
| | eager 10 | 62.7–110.0 | **24.1**–110.5 | **24.2**–110.9 | 67.6–115.5 | 67.3–105.1 | 65.0–224.8 |
| | eager 50 | 37.7–86.4 | **6.19**–97.7 | **6.56**–98.2 | 44.6–103.0 | 39.5–85.9 | 76.7–317.9 |

- **Strict alternation costs a slice per piece:** each 64 KiB piece waits out one S on the side
  that has nothing, so MB/s falls as 1/S, alike on every lane and face: 2.14 to 2.60 at S=50,
  9.64 to 12.7 at S=10. a's 64 pieces took 3,225.3 to 3,365.3 ms at S=50, b's 256 took 13,312.3
  to 15,677.5.
- **The eager variant recovers most of it at the same S,** with no new wait in the low level:
  at S=10, 35.8 to 212.6 MB/s for a and 24.1 to 115.5 for b. Its slow cells are both 8.5.0s'
  HTTP/2 full-duplex (24.1–30.7 at S=10, 6.19–7.3 at S=50), where cdd905a9's stall holds the
  receive while the send is paused, so a side waits out S anyway.
- **CPU is small at every S:** 574.2 ms at most for b's 32 MiB, 105.1 for a's 8 MiB; eager uses
  less than strict at the same S (b at S=10: 65.0–224.8 against 148.7–394.3).
- **Idle, S sets the polling cost** (`drive-idle`: b's control on raw, sized, its port waiting
  3 s with nothing to read, 2 runs a lane): 44.5–90.7 ms of CPU in 3 s at S=1, 11.7–19.3 at S=10,
  9.1–19.8 at S=50; about 2,850 waits at S=1, 300 at S=10, 61 at S=50.

Greps:
- `grep -h '\] drive case=[ab] ' results/drive-e-*.log results/drive-eager-*.log | grep -v server | grep -c 'port=end:[0-9]*:ok .*outcome=status=200'` (600)
- `grep -h 'drive case=[ab] .*server: sink' results/drive-e-*.log results/drive-eager-*.log | grep -c 'want_sha=ok'` (600)
- `grep -h 'server: echo ' results/drive-e-*.log results/drive-eager-*.log | grep -o 'echo_sha=[0-9a-f]*' | sort | uniq -c`
- per cell: `grep -h '\] drive case=a ' results/drive-e-docker.log | grep -v server | grep 'floor-7.85.0' | grep 'S=10 sched=strict' | grep -o 'MBps=[0-9.]*\|cpu-ms=[0-9.]*' | paste - -`
- idle: `grep -h '\] drive case=b-control' results/drive-idle-*.log | grep -v server | grep -o '^\[[^]]*\]\|S=[0-9]*\|cpu-ms=[0-9.]*\|resp-waits=[0-9/]*' | paste - - - -`

### b's control: the same drive, its port never feeding

60 calls (6 a lane a run, two runs, five lanes), `control-bound` 5,000: **every one stalled to the
bound, 28,** on every lane and face, at 5,002.8 to 5,009.8 ms. The echo's head comes as the
request's head arrives, before the drive has fed more than once: 46 calls put nothing, 14 one
piece, which came back. So a full-duplex server is answered only by feeding inside the port's read.
`grep -h '\] drive case=b-control' results/drive-c-*.log | grep -v server | grep -c 'outcome=failed:perform-failed:28'` (60);
`grep -h '\] drive case=b-control' results/drive-c-*.log | grep -v server | grep -o 'up=[0-9]* down=[0-9]*' | sort | uniq -c`

### c: an early 303 and 413, the producer still giving

`/answer-at` answering once 65,536 of 4 MiB arrived: keep-alive (`raw-keep`, `https-keep`), with a
close (`raw-close`, `https-close`), or over h2; sized and chunked; two runs; strict, S=10,
`bound` 20,000, `control-bound` 5,000. The 303's body is read whole while feeding, then a `get` to
its Location (65,536 bytes, checked); the 413 through the port. The head's bit read `#t` in all
400 calls: libcurl had sent the first 64 KiB.

**The server read no byte after its answer, 392 of 392 logged** (the other 8 were 8.5.0's HTTP/2
413 controls, whose request stream stayed open past the log's 3 s, as slice 2 saw): no libcurl
sends the rest of the body after an early answer, 7.85.0 included. It ends at the next put. On
7.85.0 and both 8.5.0s over HTTP/2, chunked, the stream was ended cleanly after the 64 KiB, so the
server read the cut body as whole (`answer-at h2 body read whole: 65536 bytes`).

| | 7.85.0 | 8.5.0, both | 8.20.0 | 8.23.0 |
|---|---|---|---|---|
| fed (c): the head to the hop's or the call's end | **at the next put**, one producer call and 64 KiB put after the head, never handed: 10.3–12.8 ms, every face | close: on its own, 0.11–1.96 ms; keep-alive and h2: at the next put, 10.3–13.6 ms | on its own, 0.12–1.67 ms; **h2 303: never, 28 at the bound**, though fed | as 8.20.0 |
| the control (c-control), no feeding after the head | **28 at the bound in all 40** | keep-alive and h2: 28 at the bound; close: on its own; GnuTLS's h2 303 ended on its own once in 4 | h2 303 alone: 28 | h2 303 alone: 28 |

Every 303's `get` came back whole (`get=end:65536:ok`), the 28s' too. Natively every call that did
not meet the bound ended within 71.6 ms of its submit.

`drive-hops` widens the HTTP/2 row (fed, `bound` 8,000): **on 8.20.0 and 8.23.0 every 3xx over
HTTP/2, 301, 302, 303, 307 and 308, never ends, 40 of 40, 28 at the bound**, while 413 and 503
end on their own; on 7.85.0 and both 8.5.0s every status ends at the next put, 10.5–14.3 ms. The
put after the head is taken and never handed. **`drive-hopcancel`,** the variant that cancels a
hop once its head's Content-Length has arrived, ends every one, 0.116 to 4.158 ms after the head,
its `get` whole; on 7.85.0 and 8.5.0 it also beats the next put.

- `grep -h '\] drive case=c ' results/drive-c-*.log | grep -v server | grep -o '^\[[^]]*\]\|where=[^ ]*\| status=[0-9]*\| outcome=[^ ]*$' | paste - - - - | sort | uniq -c`
- `grep -h '\] drive case=c-control ' results/drive-c-*.log | grep -v server | grep -o '^\[[^]]*\]\|where=[^ ]*\| status=[0-9]*\| outcome=[^ ]*$' | paste - - - - | sort | uniq -c`
- `grep -h 'drive case=c\(-control\)\? where=.* server:' results/drive-c-*.log | grep -E 'aborted|body read whole' | grep -c ' 0 after the answer\| 0 of them after the answer'` (392)
- `grep -h '\] drive case=c ' results/drive-c-*.log | grep -v server | grep -o '^\[[^]]*\]\|where=[^ ]*\|calls-after-head=[0-9]*\|put-after-head=[0-9]*\|handed=[0-9]*' | paste - - - - - | sort | uniq -c`
- `grep -h '\] drive case=c ' results/drive-hops-*.log | grep -v server | grep -o '^\[[^]]*\]\| status=[0-9]*\| outcome=[^ ]*$' | paste - - - | sort | uniq -c`
- `grep -h '\] drive case=c ' results/drive-hopcancel-*.log | grep -v server | grep -o 'head-to-end-ms=[0-9.]*' | cut -d= -f2 | sort -n | sed -n '1p;$p'`

### d: a refused connect

20 calls: **the producer was never called** (`calls=0`), and each ended 7 at 0.279 to 1.13 ms, the
head-wait answering at the token's end with no head.
`grep -h '\] drive case=d ' results/drive-c-*.log | grep -v server | grep -c 'calls=0 .*outcome=failed:perform-failed:7'` (20)

### f: an early final 200, through the drive (`drive.sps`, the second build)

Item 1's keep-alive 200 row, driven: the raw or https face armed (`keep`) on the held engine, a
1 MiB `post` to `/sink`, strict, S=10, `control-bound` 5,000, two runs, both framings, under each
rule (`drive-f`, the brief's; `drive-f-final`, `final-feeds=1`, where a bit of `#f` stops the
feeding only at a 3xx).

| lane | the bit | the brief's rule | the final head fed when asked |
|---|---|---|---|
| 7.85.0, both 8.5.0s | `#f`, 48 of 48 | **28 at the bound, 24 of 24** (5,000.3–5,008.9 ms), the producer never called after the head (`state=unasked`) | **200, 24 of 24**, the body put after the head, the head to the end 152.7–176.0 ms |
| 8.20.0, 8.23.0 | `#t`, 32 of 32 | 200, 16 of 16 | 200, 16 of 16 |

- `grep -h '\] drive case=f' results/drive-f-docker.log | grep -v server | grep '^\[\(floor\|ubuntu\)' | grep -c 'bit=#f .*state=unasked .*outcome=failed:perform-failed:28'` (24)
- `grep -h '\] drive case=f' results/drive-f-final-docker.log | grep -v server | grep '^\[\(floor\|ubuntu\)' | grep -c 'bit=#f .*outcome=status=200'` (24)
- `grep -h '\] drive case=f' results/drive-f-guix-8.20.0.log results/drive-f-docker.log results/drive-f-final-*.log | grep -v server | grep '^\[\(guix\|current\)' | grep -c 'bit=#t .*outcome=status=200'` (32)

### Under the memory gate's Valgrind

Its options exactly (`run.sh` passes `-v --command-line-only=yes --log-file=… --error-exitcode=9
--leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite`, and in the
container `--suppressions=tests/guix-glibc-locpath.supp`), on `ubuntu-openssl-8.5.0-valgrind` and
`guix-8.20.0-valgrind`, one run, `bound` 180,000, `control-bound` 15,000. Three steps:

- `drive-valgrind` (drive-v1, eager, S=10, a to d), `drive-valgrind-strict` (drive-v1, strict,
  S=10, a and b), and `drive-valgrind-final` (drive.sps, eager, S=10, `final-feeds=1`, a to d and
  f), the one whose durations the suite should take.
- **Every run was clean:** `ERROR SUMMARY: 0 errors from 0 contexts`, `definitely lost: 0 bytes in
  0 blocks`, and in the container its one suppression, 171 bytes in 1 block, once a run.
  `grep -h 'valgrind: .*\(ERROR SUMMARY\|definitely\|used_suppression\)' results/drive-valgrind*.log`

Durations, ms, from the submit, `drive-valgrind-final`, both lanes (`total-ms`):

| case | ubuntu-openssl-8.5.0-valgrind | guix-8.20.0-valgrind |
|---|---|---|
| a, 4 MiB each way | 429.9–1,857.1 | 446.0–1,274.5 |
| b, 16 MiB each way | 1,366.6–5,797.1 | 1,403.3–4,283.5 |
| b-control, the bound | 15,010.9–15,015.9, 28 | 15,010.0–15,015.2, 28 |
| c (fed) | 12.9–135.2 | 15.2–104.7; **h2 303: 180,030–180,032, 28** |
| c-control | 12.8–132.4, every one ended on its own | 12.5–90.8; h2 303: 15,027–15,029, 28 |
| d | 2.6–7.1, 7 | 3.6–11.1, 7 |
| f, 1 MiB | 218.9–328.5 (bit `#f`, fed) | 228.2–325.3 |

Strict at S=10 (`drive-valgrind-strict`): a 1,055.0–2,224.0, b 4,826.8–6,687.1 where it did not
stall. Every a and b that ended 200 was whole: 24 of 24 in `drive-valgrind-final`, sink lines
`want_sha=ok`.
`grep -h '\] drive case' results/drive-valgrind-final-*.log | grep -v server | grep -o '^\[[^]]*\]\|case=[^ ]* \(face\|where\)=[^ ]*\( status=[0-9]*\)\?\|total-ms=[0-9.]*\| outcome=[^ ]*$' | paste - - - -`

What Valgrind changed:

- **The echo's 200 came before libcurl's first ask on 8.5.0, unheld:** the bit read `#f` in 7 of
  18 of its b calls over the three steps (raw chunked once, https six times) and in 4 of 4 https
  b-controls of the two eager steps, where natively it read `#t` in every one. libcurl then asked
  (`asked=#t`). Under the brief's rule each of those b calls stalled to the 180,000 ms bound, 28,
  `state=unasked`, five of them; fed as a final head, both of `drive-valgrind-final`'s ended 200,
  whole, in 3,645.5–3,877.7 ms. This is item 1's 200 keep row, met with no hold.
  `grep -h '\] drive case=b ' results/drive-valgrind*-docker.log | grep -v server | grep -o 'bit=[^ ]*\|state=[^ ]*\| outcome=[^ ]*$' | paste - - - | sort | uniq -c`
- **8.5.0's end after an early answer moved:** the c-controls over keep-alive and HTTP/2, which
  natively waited to the bound in 47 of 48, ended on their own under Valgrind, 24 of 24.
  `grep -h '\] drive case=c-control where=\(raw-keep\|https-keep\|h2\)' results/drive-valgrind-docker.log results/drive-valgrind-final-docker.log | grep -v server | grep -c 'outcome=status='` (24)
- **drive-v1's eager variant spun under Valgrind:** see the traps below. `drive-valgrind`'s
  b-control durations (up to 25,018.5 ms, past the 15,000 bound) are that flaw's, not the
  drive's; `drive-valgrind-final`'s are the ones to read.

## Contradicting, or adding to, the plan and the ADRs

1. **§3.6's "a hop whose body libcurl had not asked for by its head is never fed" is right for a
   hop, and wrong if applied to every head, as the brief's drive does.** On 7.85.0 and both
   8.5.0s, a final 2xx head before the first ask is followed by an ask (item 1, 72 of 72; f, 24 of
   24; Valgrind's b, unheld). The head handed to PROC must be fed whenever libcurl asks. ADR-0032's
   decision 3 is untouched: such a call is not stepped past, so no replay is at stake.
2. **§3.6's "where it asks, the hop is cancelled once its buffered pieces are read" has no signal
   on HTTP/2:** on 8.20.0 and 8.23.0 every 3xx over HTTP/2 never ends, fed or not (40 of 40, and
   item 1's 32 of 32), with its body whole in the stream. Nothing tells the drive the pieces are all
   there but the head's Content-Length; cancelling there ended every hop in 0.116–4.158 ms. A hop
   with no Content-Length (chunked over HTTP/1.1, or HTTP/2 without content-length) has no such
   signal and would wait for the bound.
3. **§3.6's "§2.1 found 7.85.0 does not end such a transfer until the body resumes":** confirmed
   through the engine, and it is the next put that ends it; no libcurl sent a byte of the body
   after an early answer (392 of 392), so "does 7.85.0 send the whole remaining body" is no.
4. **§3.7's "an answer while a streamed body is sent" row** has a new cell: 8.20.0 and 8.23.0
   end a 3xx over HTTP/2 never, even at the next put (slice 2 measured 413 and 200 only).
5. **ADR-0030's amendment of 2026-10-31** says the bit read `#t` unheld natively 100 of 100, and
   `#f` under Valgrind on 8.5.0 for an answer at accept. Here an answer written as the request's
   head arrives (the echo) also read `#f` under Valgrind on 8.5.0, over TLS above all: not a
   contradiction, a wider case.

## Rows proposed for the plan's §3.7

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | chez-curl |
|---|---|---|---|---|---|---|
| a final head before libcurl's first ask (held; unheld under Valgrind) | bit `#f`; at 300 or more never asked after; a 2xx kept alive asked within 0.2 ms | the same; over HTTP/2 with OpenSSL no head at all while the send is paused | not measured | never: the first ask comes with the request's head | the same | a hop with bit `#f` never fed; the final head fed when asked |
| an HTTP/2 3xx while the body is owed | ends at the next put | the same | not measured | never, even fed: 28 at the bound | the same | the hop cancelled at its Content-Length |
| an early answer, the producer still giving | ends at the next put, every face; no byte of the rest sent | a close at once; keep-alive and HTTP/2 at the next put (under Valgrind at once) | not measured | at once, but HTTP/2's 3xx never | the same | fed in every wait |
| an early answer, nobody feeding | 28 at the bound | keep-alive and HTTP/2: 28 natively | not measured | HTTP/2's 3xx: 28 | the same | fed in every wait |
| HTTP/2, an early answer to an unsized body | the stream ended clean after the bytes sent: the server reads a cut body as whole | the same | not measured | the stream reset | the same | documented |
| a full-duplex server, the port not feeding | 28 at the bound | the same | not measured | the same | the same | fed inside the port's read |

## The suite's bounds, and the slice S

- **S: 10 ms, with the eager alternation** (a side's wait 0 ms when the other has moved something
  since this side's last empty wait, else S). It gave 24.1–212.6 MB/s natively, CPU 22.1–224.8 ms
  per call, 11.7–19.3 ms of idle CPU in 3 s. The brief's strict alternation needs S of 1 for
  47–96 MB/s, at 44.5–90.7 ms of idle CPU in 3 s; at S=10 it gives 9.64–12.7 MB/s. A single
  low-level wait for "a piece, room or the end" would take S out of the throughput altogether; the
  eager variant shows the low level can do without one, but for 8.5.0's HTTP/2 full duplex
  (24.1–30.7 MB/s at S=10).
- **Natively,** the longest of each case at that S: a 234.5 ms (4 MiB each way), b 1,393.1 ms
  (16 MiB each way), c 71.6 ms (strict), d 1.13 ms, f 381.8 ms (strict, 1 MiB). A bound of 10 s a
  call covers 16 MiB each way seven times over; slice 1's and 2's 10 s stand.
- **Under Valgrind** (`drive-valgrind-final`): a 1,857.1, b 5,797.1, c 135.2, d 11.1, f 328.5
  ms; a bound of 60 s a call covers b ten times over, as slices 1 and 2 set it.
- **A check that must wait for a bound** (a control's stall, the HTTP/2 3xx on 8.20.0 and
  8.23.0): natively every b- and c-control that met its 5,000 ms bound was done 5,000.3 to
  5,061.0 ms from its submit, a 303's `get` included; under Valgrind, its 15,000 ms bound, 15,010.0
  to 15,029.1 ms, and the 180,000 ms one 180,030.0 to 180,032.1.
  `for f in results/drive-c-*.log; do grep -h '\] drive case=\(b\|c\)-control' $f | grep -v server | grep 'outcome=failed:perform-failed:28' | grep -o 'total-ms=[0-9.]*' | cut -d= -f2; done | sort -n | sed -n '1p;$p'`

## Traps

- **An answer written as the request's head arrives races libcurl's first ask under Valgrind,**
  as slice 2's answer at accept did: 8.5.0's bit read `#f` for the echo in 7 of 18 b calls, over
  TLS above all, and never natively. A test whose drive stops at a bit of `#f` stalls there; one
  that pins the bit for such a server asserts nothing under the gate.
  (`results/drive-valgrind*-docker.log`, case b)
- **A wait bounded by 0 after the other side moved must forget that move:** drive-v1's eager
  variant kept the flag while its port never fed the other side, polled `next-piece` at 0 ms, 3.4
  to 4.0 million times in 20 to 25 s (`resp-waits=`), and under Valgrind, which runs one thread at
  a time, starved the engine's thread: libcurl's 15 s timeout fired late, at 20,881.5 ms, or not
  before the drive's own deadline at 25 s (5 b-controls). Natively it never ran. drive.sps clears
  the flag at an empty wait. (`results/drive-valgrind-guix-8.20.0.log`, `-docker.log`, b-control)
- **8.5.0's end after an early answer depends on timing:** natively keep-alive and HTTP/2 waited
  for the next put (47 of 48), under Valgrind they ended on their own (24 of 24). A by-version cell
  for it asserts what holds both ways.
- **The `grep -o 'outcome=…'` of a line that also holds `hop-outcome=` and `get-outcome=`**
  matched all three, and `status=` matched inside `outcome=status=`, so a `paste` of fields slid;
  the README's greps anchor them (`' status=…'`, `' outcome=[^ ]*$'`).
- **A shell reads its script as it runs:** an edit of `run.sh` during a trial run (not kept in
  `results/`) broke that run at line 91. No kept log ran across an edit.
- **`(collect)` raises while another thread is active** (traps.md): one of 56 programs,
  `ubuntu-gnutls-8.5.0`'s in `drive-f-docker.log`, raised "cannot collect when multiple threads
  are active" at its last line, before its counts, after every case had printed: an engine's
  thread was still ending after its stop. The programs should call `collect-rendezvous` there; the
  other 55 printed their counts.

## What the build needs that the plan does not say

- The bit's rule by head: a hop with bit `#f` is never fed; the final head is fed when asked.
- A hop's end without the transfer's: its head's Content-Length, then a cancel, at least on 8.20.0
  and 8.23.0 over HTTP/2; and a rule for a hop with no length (the bound, or no hop body read).
- The drive's alternation: strict alternation costs S per 64 KiB piece; the eager form, with its
  flag cleared at an empty wait, or a low-level wait for either side.
- Feeding inside the port's read is not optional: full duplex on every lane, and an early answer on
  7.85.0 everywhere and on 8.5.0 kept alive or over HTTP/2.
- For test-stream-call: a hop whose bit is `#f` needs the held engine, which is
  `(curl private engine)`'s, under a session, which `(http-client private call)`'s
  `new-http-session` can make; the origin has no early answer after N body bytes, no keep-alive
  arm, no echo and no sink-then-body (`server.mjs`'s `/answer-at`, `/arm?mode=keep`, `/echo`,
  `/seq`); its `/raw/arm` always closes and sends no Location.
- No defect in main was found: every count of native objects was 0 at the end of the 55 programs
  that printed one (`grep -h 'counts ((block' results/*.log | sed 's/^\[[^]]*\] //; s/ hop-cancels=[0-9]*//' | sort | uniq -c`).


## Files

| File | What it is |
|---|---|
| `server.mjs` | the probe server: a copy of `../slice2/server.mjs` with the routes its header marks "Slice 3" (`/seq`, `/echo`, `/answer-at`, `/arm`) and a `closed` port, not `tests/origin.mjs` |
| `run.sh` | one lane: starts `server.mjs` with a fresh PKI, runs `PROGRAM.sps` on `src:tests:build/scheme-libs` under GNU `timeout`, optionally under the gate's Valgrind |
| `docker.sh` | the four Docker lanes, and Valgrind on Ubuntu's 8.5.0, in `ubuntu:24.04`, Node 20.10.0 on each |
| `all.sh` | host: every step, one after another, so no two timed runs share the machine |
| `asked.sps` | item 1: whether libcurl asks for the body after a final head that came before its first ask; `origin` against `tests/origin.mjs`'s `/raw/arm`, `faces` against `server.mjs` |
| `drive-v1.sps` | item 2's first build: the drive, at the low level, cases a to d, and e's slices |
| `drive.sps` | its second build: case f, `final-feeds`, the eager flag cleared |
| `results/` | the logs: `STEP-guix-8.20.0.log` and `STEP-docker.log` (7.85.0, both 8.5.0s, 8.23.0, in that order), and `drive-valgrind{,-strict,-final}-{docker,guix-8.20.0}.log`, the Docker one Ubuntu's 8.5.0 with OpenSSL |

The lanes, as the logs name them: `floor-7.85.0`, `ubuntu-openssl-8.5.0`, `ubuntu-gnutls-8.5.0`,
`guix-8.20.0`, `current-8.23.0`, and under Valgrind `ubuntu-openssl-8.5.0-valgrind` and
`guix-8.20.0-valgrind`.

## Rerunning

On the host, from the repository's root:

```
sh .plans/research/m6/slice3/all.sh                       # every step, about four hours
sh .plans/research/m6/slice3/all.sh asked-origin drive-c  # or some steps
S=10 SCHED=eager sh .plans/research/m6/slice3/all.sh valgrind   # as the kept logs ran
```

Each step's arguments are in `all.sh`. One lane by hand, in the container:

```
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice3/run.sh guix-8.20.0 drive cases=a slices=10 runs=1' < /dev/null
```

**On the Mac** (Apple's 8.7.1), both programs run as they are, through `run.sh`, which takes
`gtimeout` and `shasum` there; `/proc` is missing, so `drive.sps` prints `proc-stat-ms=0`:

```
NODE="$(asdf which node)" CHEZ=chez CURL_SSL_BACKEND=secure-transport sh .plans/research/m6/slice3/run.sh mac-8.7.1 asked origin 3 > mac-asked.log 2>&1; NODE="$(asdf which node)" CHEZ=chez CURL_SSL_BACKEND=secure-transport sh .plans/research/m6/slice3/run.sh mac-8.7.1 drive cases=a,b,b-control,c,c-control,d,f final-feeds=1 sched=eager slices=10 runs=2 bound=20000 > mac-drive.log 2>&1
```
