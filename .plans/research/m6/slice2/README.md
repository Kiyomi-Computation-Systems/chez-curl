# M6 slice 2: the measurements of the plan's §5.1 (2026-10-30)

Measured before the slice builds anything, on a prototype of the plan's §3.3, and the send half of
§3.4 and §3.5. The prototype is not the slice's build, and nothing here ships. `main` was at
f0c69d3, slice 1 merged. Every log under `results/` came from `proto.patch` at sha256
`75a493ac5e344424…` (`75a493ac5e344424962cc747c47b63303cea01cbd1592306d57b28249758a87a`), which
`run.sh` prints on each log's first line:
`grep -h 'prototype build' results/*.log | sort -u`.

## Files

| File | What it is |
|---|---|
| `proto.patch` | the prototype: `diff -ruN` of main's `src/` (as `orig/src`) against the prototype (as `work/src`) |
| `build.sh` | host: `build/m6s2/src` from `src/` and `proto.patch`, by GNU patch, with sums `run.sh` checks |
| `run.sh` | one lane: starts `server.mjs` with a fresh PKI, runs `PROGRAM.sps` on the prototype, optionally under the gate's Valgrind |
| `docker.sh` | the four Docker lanes, and Valgrind on Ubuntu's 8.5.0, in `ubuntu:24.04` (slice 1's, its paths changed) |
| `all.sh` | host: every step below, one after another, so no two timed runs share the machine |
| `server.mjs` | the probe server: a copy of `../pause/server.mjs` with a node:http face and the routes marked "slice 2" in its header (not `tests/origin.mjs`) |
| `check.sps` | the prototype's check: each method's framing, sized and chunked, whole by SHA-256, every face |
| `answer.sps` | item 1: an answer while the body is still being sent |
| `rewind.sps` | item 2: the seek and prerequest callables, libcurl's own resend |
| `hazards.sps` | items 3a and 3b: a connection lost under a paused upload; HTTP/2 with one direction paused |
| `cpu.sps` | item 3c: the CPU during a slow upload and a paused one, pacing on and off |
| `offers.sps` | item 4: the read callable's offers |
| `escape.sps` | item 5: the put's escape, the review's SIGINT recipe |
| `throughput.sps` | item 6: 64 MiB through `curl-token-put-piece!` |
| `unpaced.sps` | main's own `src/`, not the prototype: the seamed engines' failure at their first resume |
| `results/` | the logs: `PROGRAM-guix-8.20.0.log`, `PROGRAM-docker.log` (7.85.0, both 8.5.0s, 8.23.0, in that order), and for `cpu` and `throughput`, `PROGRAM-docker-valgrind.log` and `PROGRAM-guix-8.20.0-valgrind.log`; `answer-bound15s/`, item 1's first run, superseded (item 1) |

The server's faces: `http` is node:http (`/sink`, `/log` and `/conns` alone); `raw` is
plaintext HTTP/1.1 on node:net, its own parser, keep-alive; `https` is the same parser over TLS
(the pause server's `tls` face, renamed); `h2` is node:http2. tests/origin.mjs's `raw` face is a
scripted one; here `raw` is the parser that sees each request's bytes. Every request carries a
tag, and each program fetches the server's log for its tag after the case, from `GET /log` on
the raw face, through an engine of its own.

## Rerunning

On the host, from the repository's root:

```
sh .plans/research/m6/slice2/all.sh               # build, check, answer, rewind, hazards,
                                                   # cpu, offers, escape, throughput, unpaced
sh .plans/research/m6/slice2/all.sh rewind cpu     # or some steps
```

`build.sh` must run first, on the host, since the Guix container has no `patch`. It makes
`build/m6s2/src` afresh, and `run.sh` refuses a copy whose sums differ. To regenerate the patch
from an edited copy: put main's `src/` at `build/m6s2/orig/src` and the edited copy at
`build/m6s2/work/src`, then
`(cd build/m6s2 && diff -ruN orig/src work/src) > .plans/research/m6/slice2/proto.patch`.
Each program takes the number of runs last: 2 in `all.sh`, 3 for `escape`. `LIBDIRS` sets the
program's library path, `build/m6s2/src` by default; the `unpaced` step runs on `src`, main's.
The logs were made in this order: check, then answer's first run (now `answer-bound15s/`),
rewind, hazards, cpu, offers, escape, throughput, then answer again and unpaced.

## The prototype

What it adds, beside main:

- a streamed body, set by a private `curl-request-with-body-stream REQUEST LENGTH`, `LENGTH` a
  natural or `#f`, standing in for `body` `stream` and `body-length`;
- `post` by `POST`, `put` by `UPLOAD`, `patch` and `delete` by `POST` and `CUSTOMREQUEST`, with
  `READFUNCTION`, `READDATA`, `POSTFIELDSIZE_LARGE` or `INFILESIZE_LARGE` at the length or -1,
  `SEEKFUNCTION`, `SEEKDATA`, `PREREQFUNCTION`, `PREREQDATA` and `FRESH_CONNECT` at 1, and
  `Content-Type:` and `Expect:` beside them, a streamed `delete`'s too;
- the request stream, its buffer of 65,536 bytes, the send bit and the resume flag;
- the read, seek and prerequest callables, each `__collect_safe`, locked where defined, and
  under a guard that records what is raised as `callback-raised` and answers what refuses:
  `CURL_READFUNC_ABORT`, `CURL_SEEKFUNC_CANTSEEK`, `CURL_PREREQFUNC_ABORT`;
- `curl-token-room-wait`, `curl-token-put-piece!` (committing inside its hold, with its resume
  decision), `curl-token-end-body!` and `curl-token-body-count`;
- `body-length-mismatch` and `body-not-replayable` among `&curl-transfer-error`'s reasons, and
  `body-length-mismatch` among `&curl-request-error`'s;
- the resume step clearing both bits and the flag in one hold; the paced poll's "paused" taking
  either bit; the read callable bumping the moved-byte counter;
- the six constants, unchecked (`CURL_READFUNC_PAUSE`, `_ABORT`, `CURL_SEEKFUNC_OK`,
  `_CANTSEEK`, `CURL_PREREQFUNC_OK`, `_ABORT`), read from the 7.85.0 and 8.23.0 headers;
- counters: the engine's turns, polls, polls under 1 ms, and of those the ones in a turn that
  took a message, else moved bytes, else with nothing paused, else with a transfer paused (the
  ones the pacing follows with a sleep); the request stream's reads, pauses, resumes, seeks,
  prerequest calls, puts, puts that found the buffer full, the most it held, the first ask's time
  and the token's completion time;
- an event log on the request stream, 300,000 events at most: each read call (its time, the room
  offered, the bytes buffered, its answer, and whether it ran inside `curl_easy_pause`), each seek
  call, each prerequest call (with the local port and the send bit as it found it), each resume
  step's call of `curl_easy_pause`, and the end;
- switches, process-wide: `FRESH_CONNECT` off (`set-upload-fresh-connect!`), the prerequest
  callable's clearing of the send bit off (`set-prereq-clears-send!`), and the control's put
  that commits after its hold (`set-put-commits-after-hold!`); the seam
  `call-with-upload-held`, as slice 1's `call-with-stream-held`.

The choices §3 did not make:

1. The streamed body is kept in a weak `eq` table keyed by the request, as slice 1's prototype
   kept `stream-buffer`, so the request record is main's. `curl-request-with-body-stream` comes
   last, after the hatch and the other private constructors, each of which makes a new request.
2. The request stream is made at submit, with the plan. A request that streams both ways gives
   it the response stream's mutex, and it uses that stream's resume flag: the plan's one flag.
   The send bit is the request stream's own field.
3. The read callable copies inside its one hold, across pieces, by the checked copy (a bounce
   bytevector when the offset into a piece is not 0). Once any reason is recorded it answers
   `CURL_READFUNC_ABORT` at every later call, as the write callable refuses after one. With the
   length given whole it answers 0 even before `end-body!`. A room of 0 would pause; none came
   among the calls items 2, 3 and 4 logged, whose least room was 576.
4. The put copies its piece first, refuses an empty one as an assertion violation, and checks the
   length before the room, so a put past the length is refused even while the buffer is full.
   "Full" is 65,536 bytes or more buffered. It waits as every wait, 50 µs doubling to 10 ms, and
   reads whether the token is done in the first hold of each try.
5. `room-wait` answers `#t` once the read callable has been called and fewer than 65,536 bytes
   are buffered.
6. `end-body!` on a token done does nothing, and a second one nothing; it queues a resume when
   the send bit is set and no flag is.
7. The seek callable answers OK for an offset of 0 from `SEEK_SET` with no byte handed, else
   records `body-not-replayable` and answers `CURL_SEEKFUNC_CANTSEEK`. The prerequest callable
   counts its calls; it answers OK at the first, and at a later one while no byte was handed,
   else records `body-not-replayable` and answers `CURL_PREREQFUNC_ABORT`; it clears the send bit
   at every call, the first too.
8. The resume step marks a process-wide flag around `curl_easy_pause`, so a callable's event can
   say it ran inside the call.
9. **Main's `resume!` reads its seam with `(assq 'pause-answer (engine-seams engine))`.** On
   `make-curl-engine-unpaced`'s seams, `(unpaced)`, and `make-curl-engine-unmultiplexed`'s,
   `(unmultiplexed)`, `assq` raises "improperly formed alist", so either engine fails at its
   first resume step. test-stream only cancels on them, so main's suites never met it; this
   slice's first CPU run met it at once. The prototype finds the seam by a pair-safe search. It
   is main's defect, not the prototype's choice, and `unpaced.sps` shows it on main's own `src/`
   (the results' last section).

## Results

The figures are the extremes the logs show. A grep that finds each one is given, and each range
was drawn from every matching line. A lane is named as its logs name it: `floor-7.85.0`,
`ubuntu-openssl-8.5.0`, `ubuntu-gnutls-8.5.0`, `guix-8.20.0`, `current-8.23.0`. Times are ms
from the submit, by the engine's clock where the line says `done-ms`.

### The check: framing, every method, every face

320 transfers, 64 a lane: `post`, `put`, `patch` and `delete` of 262,144 bytes, sized and
chunked, over `http`, `raw`, `https` and `h2`. Each ended 200, and the body arrived whole by
SHA-256 (`want_sha=ok`). Sized sent `Content-Length: 262144` everywhere. Chunked sent
`Transfer-Encoding: chunked` over HTTP/1.1, and neither header over HTTP/2. No transfer sent
`Expect` or `Content-Type` (`expect=- ct=-`), a streamed `delete` included.
`grep -c 'want_sha=ok' results/check-*.log`;
`grep -h 'server: sink' results/check-*.log | grep -o 'method=[A-Z]* cl=[^ ]* te=[^ ]* expect=[^ ]* ct=[^ ]*' | sort | uniq -c`

### Item 1: an answer while the body is still being sent

480 transfers: 6 answers, 4 producers, sized and chunked, two runs on each of the five lanes.
The server answers as the request's head arrives. A paused producer puts nothing for 3 s, then
puts the rest (`paused-rest`, and `paused-head`, which streams the response too), or ends the
body at once (`paused-end`). A giving producer puts 16 KiB every 10 ms. `timeout-ms` is 8,000.
The two framings answered alike in every cell but those the table names.
`grep -h 'answer run' results/answer-*.log | grep -v server:`

"Ends on its own" means without a resume, within 3 s. "At the first resume" means at the
paused producer's first put, or its end, at 3 s. Times are `done-ms`.

| the answer | 7.85.0 | 8.5.0, OpenSSL and GnuTLS alike | 8.20.0 | 8.23.0 |
|---|---|---|---|---|
| 413, then FIN (raw) | at the first resume, 413, 3,000.6–3,001.9; giving 413 at 1.3–10.7 | **on its own**, 413, 1.3–3.7; giving 1.5–1.6 | **on its own**, 1.4–5.4; giving 1.4–1.9 | **on its own**, 1.5–5.3; giving 1.5–1.7 |
| 413, keep-alive (raw) | at the first resume, 3,000.6–3,001.5; giving 10.8–11.1 | **at the first resume**, 3,000.7–3,001.7; giving 1.5–2.4 | **on its own**, 1.4–2.0; giving 1.4 | **on its own**, 1.4–1.6; giving 1.4–1.9 |
| 200, then FIN (raw) | at the first resume, 200, 3,000.8–3,001.9; giving 0.8–11.3 | **on its own**, 1.3–2.5; giving 1.5–2.1 | **on its own**, 1.4–2.2; giving 1.4–1.5 | **on its own**, 1.4–1.6; giving 1.5–1.7 |
| 200, keep-alive (raw) | never on its own, on any lane: the rest put, 200 at 3,015.1–3,032.7, the body whole; an end with nothing sent, sized: **`body-length-mismatch`, 42**, at 3,000.6–3,001.4; chunked: 200 at 3,000.6–3,001.6; giving: 200 at 620.1–639.0, whole | (the same) | (the same) | (the same) |
| 413 (h2) | at the first resume, 3,004.0–3,007.7; giving 3.8–15.2 | **at the first resume**, 3,003.1–3,008.3; giving 3.9–8.0 | **on its own**, 4.4–8.6; giving 4.5–4.9 | **on its own**, 3.2–9.2; giving 3.2–4.0 |
| 200 (h2), the server's stream ended with it | **never**: after the resume the send stops at 81,920–131,071 bytes handed, every put times out, and **28 at the bound**, 7,999.2–7,999.6, giving too; an end with nothing sent: sized `body-length-mismatch`, 42, at 3,004.0, chunked 200 at 3,004.1–3,004.2 | **on its own, 200, 3.4–6.5, with no byte of the body sent**, giving too | not on its own; the rest put: 200 in 6 of 8, **55 in 2 of 8**, at 3,008.9–3,016.7, the body whole; **giving: 55 in 4 of 4**, 627.6–637.0, the body whole; an end with nothing: sized `body-length-mismatch`, 42, at 3,007.2–3,007.3, **chunked 55**, 2 of 2 | not on its own; the rest put: 200 at 3,011.5–3,018.3; giving: 200 at 627.5–641.4; an end with nothing: sized `body-length-mismatch`, 42, at 3,004.0–3,004.1, chunked 200 at 3,007.5–3,007.6 |

- **The status always arrived first:** the streamed response's head was published 0.331 to
  7.671 ms in, on every lane in every case, whether or not the transfer then ended.
  `grep -h 'mode=paused-head' results/answer-*.log | grep -v server: | grep -o 'head-ms=[^ ]* head-status=[^ ]*'`
- **Every failure but 28 and 55 was the read callable's own:** an end short of the length,
  `body-length-mismatch`, 42, alike on every lane (§3.3). The 55s are `perform-failed`, libcurl's
  send failure on 8.20.0 after the server ended its stream. The 28s are the bound.
- **Once the token was done, every later put answered `done`, and `room-wait` too,** 480 of 480;
  `end-body!` did nothing. While the token was live, a put waiting on a buffer libcurl no longer
  read answered `#f` at its bound: the 12 7.85.0 HTTP/2 200 cases.
  `grep -h 'answer run' results/answer-*.log | grep -v server: | grep -o 'after-done-put=[^ ]* after-done-room-wait=[^ ]*' | sort | uniq -c`
- In 24 cases `room-wait` answered `done` rather than `#t`. 8.5.0's HTTP/2 200 had ended before
  its first ask was seen (19), and on 8.20.0 and 8.23.0 an HTTP/2 413 had ended within the
  wait's first polls (5).
  `grep -h 'answer run' results/answer-*.log | grep -v 'server:\|asked=#t'`
- This agrees with the C probe's `R-answer` (§2.1) wherever both ran a case. The keep-alive 200
  is new: it ends on its own on no lane. HTTP/2's 200 differs on all four version families.

The first run of this program, kept in `results/answer-bound15s/`, had a bound of 15,000 ms
but waited only 5 s after its producer. So its 7.85.0 HTTP/2 200 cases ended the program's
waits `not-done`, the transfer still live, with every other cell as here. It is superseded,
and no figure above comes from it.

### Item 2: the seek and prerequest callables, and libcurl's own resend

260 transfers: 26 cases a run, two runs on each of the five lanes.
`grep -h 'rewind run' results/rewind-*.log | grep -v 'events:\|server:\| get '`

**Every resend libcurl wanted after a byte was handed ended `body-not-replayable`,** 70 of 70,
never `perform-failed` with 65, 56 or 42. They were a pooled connection the server cut after
reading the post whole (`kill`), one it reset mid-body (`reset`, at 32,768 and 262,144 bytes,
and at 32,768 of 8 MiB), and an HTTP/2 stream refused after 32 KiB of DATA. The code beside the
reason was libcurl's own:

- 65, the seek callable's `CANTSEEK`, on every lane;
- 56 on 7.85.0 for the resets and the refused stream, where the seek refused just the same;
- 42 on both 8.5.0 builds in 4 of the 8 refused-stream runs.

In those four 8.5.0 runs the resend came **with no seek at all**: `seeks=0 attempts=2`, and the
second prerequest call refused it, `P2:abort ... handed65536`. Each time one read had handed
65,536 bytes at once, and `request-size=139` or `140`. That is the window §3.3 read in 7.85.0's
source: bytes handed but not yet sent, then a resend with no rewind. Here it was measured on
8.5.0.
`grep -h 'reason=body-not-replayable' results/rewind-*.log | grep -v 'events:\|server:' | grep -c .`;
`grep -h 'code=42' results/rewind-docker.log | grep -v events`;
`grep -h 'P2:abort' results/rewind-docker.log`

The server saw one request for each of these: `count raw:/close-after=1 raw:/sink=1`, or
`count h2:/refuse=1`.
`grep -h 'server: count' results/rewind-*.log | sort | uniq -c`

**A resend before any byte was handed went on, and ended 0,** with `attempts=2` and two requests
at the server (`raw:/sink=2`, `h2:/refuse=2`). The cases were a pooled connection cut at the
post's head by FIN (`cuthead`) and by RST (`resethead`), and an HTTP/2 stream refused at its
headers (`refuse-at0`), the producer putting nothing for 500 ms. 7.85.0 and 8.5.0 resent with
no seek (`seeks=0`). 8.20.0 and 8.23.0 first sought to 0 from `SEEK_SET`, which the seek
callable answered OK (`S0/0:ok`).

**The exception is 7.85.0's `cuthead`, 2 of 2:** it did not see the FIN while the read was
paused. Once the producer put, the send failed: `perform-failed`, 55, `attempts=1`, 65,536 bytes
handed. That is no resend, so no refusal is due; it ends as a send failure. It belongs with
item 3a's 7.85.0 rows.
`grep -h 'case=pooled-cuthead-gap200-late fresh=off' results/rewind-*.log | grep -v 'events:\|server:\| get '`

**With `FRESH_CONNECT` on, the dead pooled connection was never met:** 100 of 100 pooled
transfers (10 cases, 2 runs, 5 lanes) ended 200 with `attempts=1 seeks=0` and one `/sink`
request each. Off, 8.23.0 alone met a connection closed cleanly 200 ms before: `fin-gap200` and
`fin-gap200-late`, two runs each, 4 of 4, `attempts=2 seeks=1`, each ending 0 with one `/sink`
request, its first attempt never reaching the server. At 1,500 ms no lane met one.
`grep -h 'case=pooled.*fresh=on status=200.*attempts=1 seeks=0' results/rewind-*.log | grep -c .`;
`grep -h 'case=pooled.*fresh=on server: count raw:/close-after=1 raw:/sink=1' results/rewind-*.log | grep -c .`

**libcurl's own resend starts its attempt unpaused, on all five** (§3.4 read it, not measured).
In each of the 52 resends before any byte was handed, the read was paused when the attempt
failed. The second prerequest call found the send bit set and nothing handed
(`P2:ok:...:send1:handed0`, 52 of 52), and a read came
0.009 to 1.165 ms after it, with no resume between (`resend-read-unpaused=yes`). That read found
nothing buffered and paused again.

The control is HTTP/2's `/sink` with the same late producer and no refusal. On all five, 10 of
10, it made one read, a pause, then no read until the resume about 500 ms later
(`R65536/0:pause@1.587 Z0:send1@502.25`).

With the prerequest callable's clearing of the send bit switched off, the late refusal ended 0
on all five, 10 of 10. On these five libcurls the clear is harmless but measurably unneeded,
since a read follows at once and re-pauses.
`grep -c 'resend-read-unpaused=yes' results/rewind-*.log`;
`grep -h 'case=h2-control-sink-late.*events:' results/rewind-*.log`;
`grep -h 'case=h2-refuse-at0-late fresh=on clears-send=off' results/rewind-*.log | grep -v 'events:\|server:'`

The P2-to-read delays, from the event logs:
`grep -h events: results/rewind-*.log | grep -o 'P2:[^ ]* R[^ ]*'`

### Item 3a: a connection lost under a paused upload (#11769)

Each case puts 65,536 bytes of 1,000,000, so the read pauses. The server drops the connection
200 ms after those bytes arrive, by FIN or by RST, and `timeout-ms` is 4,000.
`grep -h 'case=lost' results/hazards-*.log | grep -v 'events:\|server:'`

| lane | raw (HTTP/1.1), RST | raw, FIN | https, RST or FIN | h2, RST or FIN |
|---|---|---|---|---|
| floor-7.85.0 | 56 at 204.3–208.7 | **28 at the bound, 4,004.7–4,005.3**, 4 of 4 | 56 at 206.4–218.5 | **split**: 28 at 4,004.7–4,005.2 in run 1, every case; 56 at 210.4–211.6 in run 2 |
| ubuntu-openssl-8.5.0 | 56 at 203.6–206.1 | 52 at 202.6–205.3 | 56 or 52 at 205.2–211.5 | 56 at 206.5–210.2, but **28 at 3,999.7** once (FIN, sized, run 1) |
| ubuntu-gnutls-8.5.0 | 56 at 204.0–205.7 | 52 at 203.8–204.4 | 56 at 206.3–211.0 | 56 at 206.5–210.8, but **28 at 3,999.8** once (RST, sized, run 1) |
| guix-8.20.0 | 56 at 203.8–208.2 | 52 at 202.9–205.4 | 56 at 209.0–216.3 | 56 at 206.8–211.2 |
| current-8.23.0 | 56 at 202.9–207.3 | 52 at 204.4–205.8 | 56 at 209.4–211.0 | 56 at 208.2–211.4 |

Each lane's last pause came 1.449 to 13.782 ms into its transfers. Every failure was
`perform-failed`, the code libcurl answered. So on 7.85.0 a FIN under a paused
plaintext upload is never noticed (#11769), and an HTTP/2 connection lost while paused splits
by run on 7.85.0 and 8.5.0. **The bound answers each,** `timeout-ms`, as 28; nothing else ended
them.
`grep -h 'case=lost' results/hazards-*.log | grep 'code=28'`

### Item 3b: HTTP/2 with one direction paused (cdd905a9)

Each case is `/duplex` on the h2 face: the server answers 200 with 4 MiB as the headers arrive,
while it reads a sized body of 1,000,000 bytes, and `timeout-ms` is 20,000. The server logs its
flow-control windows at 1 s (`duplex-state`).
`grep -h 'case=\(send-paused\|recv-paused\|recv-paused-small\|recv-flowing\) face=h2 asked' results/hazards-*.log`;
`grep -h 'duplex-state\|the stream closed\|body_end=\|still open\|body h2 n=' results/hazards-*.log`

**The send paused while the response arrives** (`send-paused`): 64 KiB put, then nothing for
3 s.

- **8.20.0 and 8.23.0:** the response arrived whole while paused, its last piece at 17.3–35.4
  ms. Once the producer went on at 3 s, the body went whole, and the transfer ended 200 at
  3,011.3–3,023.0.
- **8.5.0 with OpenSSL: the receive stalled while the send was paused,** 2 of 2. The server
  had written all 4,194,304 bytes by 1 s, but the consumer held 540,672 and 2,572,288 at 3 s.
  The rest came after the resume, the last piece at 3,016.1 and 3,024.2. The transfer then
  ended 200 at 3,010.4–3,010.8, with 65,536 to 131,072 of the body handed. That is
  cdd905a9's stall; the resume carried it on.
- **8.5.0 with GnuTLS:** the response arrived whole by 25.3 and 33.7 ms. The transfer ended 200
  **at 12.6 and 23.9 ms, before the body was sent**: 0 and 65,536 bytes handed. No stall.
- **7.85.0:** the response arrived whole by 26.4 and 26.9 ms. After the resume the upload
  stopped again, the server holding 131,070 bytes when the stream closed, and **never ended: 28
  at the bound, 19,999.4 and 19,999.6**, "with 4194304 out of 4194304 bytes received".

**The receive paused while the send goes on** (`recv-paused`): stream-buffer 64 KiB, the
consumer taking nothing for 3 s, the producer putting the whole body at once. **On no lane did
the send go on.**

- **8.20.0 and 8.23.0:** libcurl had taken 131,072 to 180,224 bytes by 2.9 s, but the server had
  received 65,535, HTTP/2's initial window, before 2.9 s, in 8 of 8 runs of this case and its
  control. The puts took 3,057.6 to 3,102.6 ms.
  The transfer ended 200 at 3,058.1–3,102.9.
- **8.5.0:** 0 bytes handed at 2.9 s in 4 of 4 runs (in the control, 0 in 2 and 65,536 in 2).
  Once the consumer read, the transfer ended 200 at 3,095.0–3,101.3 with 131,072 to 196,608
  bytes handed: the body cut again.
- **7.85.0:** 81,920 to 131,071 bytes handed by 2.9 s, and 28 at the bound, 19,999.3 and
  19,999.3.

**The control, `recv-paused-small`,** has a response of 128 KiB, so the server's writes end at
once, in 0.7 to 1.4 ms on 8.20.0 and 8.23.0 (`total=`). At 1 s the server had consumed 65,535
bytes (0 on 8.5.0 in 2 runs of 4), its stream window stood
at 65,535 again (it had granted more), and nothing waited in its outbound queue
(`stream.localWindowSize=65535 ... session.outboundQueueSize=0`). Still the client sent nothing
more until the consumer read, on every lane. So the stall is on the client's side, not the
server's nor TCP's. That libcurl stops reading the connection while its one stream's receive is
paused, and so never sees the WINDOW_UPDATE, fits the evidence but is **not shown**.

**The other control, `recv-flowing`,** pauses nothing and takes the response as it comes.
8.20.0 and 8.23.0 sent the whole body by 9.5 to 11.3 ms and ended 200 at 14.7–18.4. 8.5.0 ended
200 at 7.96–17.6 **with 0 to 802,816 bytes handed**, once the response had ended. 7.85.0 ended
200 at 16.5 once, and in the other run reached 28 at 19,999.6 with 360,446 handed: the response
ended first, and the upload never went on.

**On 8.5.0 the server's request stream stayed open** in all 16 of its duplex cases. The log
fetch, 3 s after the client's 200, read `1 request(s) of this tag still open after 3 s`: the
client had ended the transfer, and neither ended nor reset its stream. #17611, which the source
reading lists 8.5.0 as carrying, is a fit; the RST itself is not shown.
`grep -h '8.5.0\] hazard.*still open' results/hazards-docker.log | grep -c .` (16)

So:

- **8.5.0's cdd905a9 stall is real with OpenSSL.** The stalled side resumes when the other does,
  so a producer that goes on carries it, and the bound ends one that does not.
- **A paused receive stops the send on every lane,** at the peer's window, or, on 8.5.0, before
  its first byte. A full-duplex producer then makes no progress until its consumer reads. Only
  the consumer's reading answers it, or the bound.
- **Over HTTP/2, the server's end of its response ends the transfer early on 8.5.0,** 200 with
  the body cut, and **stalls it to the bound on 7.85.0.**

### Item 3c: the CPU during a slow upload and a paused one (#16084)

`slow` is 300 puts of 4,096 bytes, 10 ms apart, about 3 s. `paused` is 3 s with the read
paused and nothing put. Each window is about 3 s; CPU is Chez's `time-process` clock, every
thread's.
`grep -h 'cpu run' results/cpu-*.log | grep -v server:`

| lane | h2 paused, pacing off | h2 paused, pacing on | h2 slow, off | h2 slow, on | raw (HTTP/1.1), every case |
|---|---|---|---|---|---|
| floor-7.85.0 | **2,998.344–2,998.81 ms, 2,382,235–2,391,236 polls** | 0.379–42.444 ms, 3–2,816 polls, 0–2,816 paced | **2,658.18–2,671.14 ms, 2,063,197–2,074,230 polls** | 67.132–72.905 ms, 2,518–2,537 paced | 0.49–42.763 ms, 3–602 polls |
| ubuntu-openssl-8.5.0 | 0.342–0.527, 2 polls | 0.306–0.379, 2 polls | 48.338–53.783 | 49.037–50.217, 37–38 paced | 0.368–45.878 |
| ubuntu-gnutls-8.5.0 | 0.299–0.519, 2 polls | 0.283–0.449, 2 polls | 43.698–45.681 | 41.989–43.107, 37 paced | 0.282–42.652 |
| guix-8.20.0 | 0.492–0.512, 2 polls | 0.341–0.434, 2 polls | 54.819–57.757 | 50.007–72.602, 74–79 paced | 0.438–49.306 |
| current-8.23.0 | 0.531–0.583, 2 polls | 0.482–0.593, 2 polls | 59.224–61.727 | 51.538–52.611, 74 paced | 0.34–43.195 |
| 8.5.0 OpenSSL, Valgrind | 1.727–1.831 | 1.779–1.802 | 640.858–695.679 | 618.016–629.052 | 1.711–546.292 |
| guix-8.20.0, Valgrind | 2.296–2.644 | 2.764–3.121 | 613.648–629.328 | 628.522–694.827 | 1.669–557.355 |

- **The upload spin is 7.85.0's, over HTTP/2, not 8.5.0's** (#16084 was read as 8.5.0's and
  8.7.1's). 8.5.0 made 336–337 fast polls in a slow upload's 3 s, 299 of them in turns that took
  a resume, on either face, and 2 polls in a paused upload's.
- **On 7.85.0 the spin is a paused send's:** every fast poll of it came in a turn that took no
  message, moved no byte, with the transfer paused (`fast-paced-eligible` 2,382,231–2,391,233 of
  2,382,233–2,391,236 fast polls). So **the paced poll's conditions hold, and it answers the
  spin:** 42.444 ms at most with it on.
- **No fast poll came in a turn whose callables moved bytes,** `fast-moved=0` in every case on
  every lane, but one Valgrind run's 1; and none with nothing paused, `fast-unpaused=0`
  everywhere. In the slow upload the fast polls were the 299–300 turns that took a resume, and
  the rest met the pacing's conditions.
- **The spin is split on 7.85.0's paused upload:** 3 runs of 4 spun. Both runs with pacing off
  did, and one of the two with it on, which paced it, 2,816 sleeps. The slow upload spun in 4 of
  4.
- **Under Valgrind no lane spun:** 2 polls in a paused upload's 3 s.

`grep -h 'floor-7.85.0\] cpu run=[12] face=h2' results/cpu-docker.log`

### Item 4: the read callable's offers

1 MiB, sized and chunked, over `http`, `raw`, `https` and `h2`. The producer put 16 KiB or
64 KiB pieces as fast as the buffer took them (`fast16k`, `fast64k`), or 1 KiB every 2 ms
(`slow`). All 240 transfers ended 200, whole by SHA-256. "Room" is the size libcurl offered.
`grep -h 'offers run' results/offers-*.log | grep -v 'calls:\|server:'`;
`grep -h 'offers run' results/offers-*.log | grep 'calls:'` (every call, in order)

| lane | first call | later calls, sized | chunked over HTTP/1.1 | HTTP/2 | the last calls of a sized body |
|---|---|---|---|---|---|
| floor-7.85.0 | 65,536 (65,524 chunked over HTTP/1.1) | 65,536 | 65,524 | 65,465–65,536 | 65,536, to the last byte |
| both 8.5.0s | 65,536 (65,524 chunked over HTTP/1.1) | 65,536 | 65,524 | 65,536 | 65,536, to the last byte |
| guix-8.20.0 and current-8.23.0 | with the request's head: 65,399–65,404 sized and 65,382–65,387 chunked over HTTP/1.1, 65,404–65,407 and 65,427–65,430 over HTTP/2 | 65,536 | 65,524 | 65,536 | **what the length still owes**: 19,456, 18,432, down to 1,024 |

- **The head shares the first call's buffer on 8.20.0 and 8.23.0,** as the source reading said
  of 8.7.1 and later: the first room is 65,536 less the head.
- **On 7.85.0 and 8.5.0 the room ignores the length;** 8.20.0 and 8.23.0 cap it. So the read
  callable's own cap at what `body-length` owes is what keeps 7.85.0 and 8.5.0 from sending a
  surplus (§2.1, §3.3).
- **A call gave at most 65,536 bytes,** or 65,524 over chunked HTTP/1.1: the chunk's framing
  takes 12.
- With the slow producer each piece cost about two calls, a pause and then the piece: 2,046 to
  2,051 calls for 1,024 pieces. The program's first call is always a pause, since its producer
  waits for `room-wait`, which needs libcurl's first ask.

`grep -h 'offers run=1 face=http framing=sized pace=slow calls:' results/offers-*.log`;
`grep -h 'offers run' results/offers-*.log | grep -v 'calls:\|server:' | grep -c status=200` (240);
`grep -h 'offers run.*server: sink' results/offers-*.log | grep -c want_sha=ok` (240)

### Item 5: the put's escape

Three runs of each case on each of the five lanes, a chunked post of 15 bytes, the first put of
piece 1 blocked on the request stream's mutex while SIGINT arrives.
`grep -h 'escape run' results/escape-*.log`

| put | handler | runs | first put | body-count after it | at the end | server |
|---|---|---|---|---|---|---|
| committed in its hold | escapes | 15 of 15 | `escaped` | 5 | 15 | 15 bytes, in order, `want_sha=ok` |
| committed in its hold | returns | 15 of 15 | `#t` | 5 | 15 | 15 bytes, `want_sha=ok` |
| control, committed after | escapes | 15 of 15 | `escaped` | **0** | **10** | **10 bytes, `pattern=bad@0`**: piece 1 lost |
| control, committed after | returns | 15 of 15 | `#t` | 5 | 15 | 15 bytes, `want_sha=ok` |

A handler that escapes as the put's section ends leaves the piece committed, and
`curl-token-body-count` says so: a caller that caught the escape can tell the piece was taken
(§3.5). The control's escape skipped its two plain writes. The next put linked over the
uncommitted piece, which was lost without a word.

The timer sweep across the put a tick at a time, as C10 did for the take, was not run. It is
not in the work list, and the committed put has nothing after its section but the return.

### Item 6: upload throughput

64 MiB in 64 KiB pieces, sized and chunked, two runs a lane; `done-ms` is from the submit to
the token's completion. All 84 transfers ended 200, and the server read 67,108,864 bytes in
order, `want_sha=ok`.
`grep -h 'throughput run' results/throughput-*.log | grep -v server:`;
`grep -h 'server: sink' results/throughput-*.log | grep -c 'bytes=67108864.*want_sha=ok'`

| lane | http | https | h2 |
|---|---|---|---|
| floor-7.85.0 | 1,882.43–1,991.78 | 1,847.4–1,898.49 | 383.739–459.634 |
| ubuntu-openssl-8.5.0 | 1,877.86–1,998.56 | 1,798.37–1,903.89 | 354.092–387.288 |
| ubuntu-gnutls-8.5.0 | 1,886.23–1,995.21 | 1,702.79–1,902.58 | 320.54–390.602 |
| guix-8.20.0 | 1,880.16–1,971.97 | 1,875.94–1,890.9 | 326.612–648.049 |
| current-8.23.0 | 1,864.27–1,990.45 | 1,843.61–1,903.49 | 703.015–874.225 |
| 8.5.0 OpenSSL, Valgrind | 713.593–1,593.81 | 5,110.13–6,085.95 | 6,351.89–6,501.68 |
| guix-8.20.0, Valgrind | 867.492–2,130.12 | 4,462.21–4,922.15 | 5,337.89–5,575.03 |

- **Natively the worst was 1,998.56 ms, and under Valgrind 6,501.68 ms.** Valgrind found 0
  errors, 0 bytes definitely lost, on both lanes, in `cpu` and `throughput`.
  `grep -h 'valgrind:' results/*valgrind*.log`
- **Over HTTP/1.1, every lane ran at about the same rate,** 33.6 to 39.4 MB/s natively (64 MiB in
  1,702.79 to 1,998.56 ms), with a pause of the read
  for nearly every piece: 899 to 1,024 pauses for 1,024 pieces, and 4,551 to 5,090 puts that
  found the buffer full. HTTP/2 paused 22 to 503 times and ran 2 to 6 times faster. Under
  Valgrind plain HTTP/1.1 ran faster than natively, 713.593–2,130.12 ms, with 1 to 593 pauses.
  That the HTTP/1.1 rate is the put's polled wait and the resume's turn, one pause and resume
  per piece, fits these counts, but is **not shown**.
- The buffer held at most 77,788 bytes: a put commits while fewer than 65,536 are buffered, so
  at most 65,535 plus the piece (§3.3).

### A defect in main: the seamed engines fail at their first resume

`unpaced.sps`, run on main's own `src/` (`LIBDIRS=src`), not the prototype. On all five lanes,
20 of 20 engines made by `make-curl-engine-unpaced` or `make-curl-engine-unmultiplexed`
failed at their first resume, `&curl-engine-error`, `failed`, raising
`("improperly formed alist ~s" ((unpaced)))`, or `((unmultiplexed))`. The control,
`make-curl-engine`, streamed 1 MiB through 13 to 19 resumes, 10 of 10. `resume!` reads its seams
with `(assq 'pause-answer (engine-seams engine))`, and both seam lists hold a bare symbol.
test-stream never resumes on either engine, so its suites pass. A slice 2 test that pauses an
upload on the unpaced engine, the CPU control, will meet it.
`grep -h 'unpaced run' results/unpaced-*.log`

## What it means for the plan

**§3.3, confirmed:**
- the options, the framing and the headers, on all five (the check);
- the read callable's cap at what `body-length` owes, which 7.85.0 and 8.5.0 need, since they
  offer 65,536 to the last byte (item 4);
- at most once: `FRESH_CONNECT` kept every dead pooled connection away, 100 of 100. Every resend
  after a byte was handed ended `body-not-replayable`, 70 of 70, by the seek, or by the
  prerequest callable where libcurl skipped the seek (item 2);
- `body-length-mismatch` at an end short of the length, 42 beside it, alike on all five
  (item 1).

**§3.3, added:**
- **The prerequest callable is needed on 8.5.0 too,** not only on 7.85.0 by its source: 8.5.0
  resent a refused HTTP/2 stream with no seek in 4 of 8 runs (item 2).
- **7.85.0 resends with no seek when nothing was sent, and so does 8.5.0;** 8.20.0 and 8.23.0
  seek to 0 first. Each went on, and ended 0.

**§3.4, confirmed:**
- **libcurl's own resend starts its attempt unpaused,** on all five: the read was called
  0.009–1.165 ms after the second prerequest call, before any resume, in 52 of 52 resends. So
  the prerequest callable's clearing of the send bit is safe; switched off, it changed nothing
  measurable on these five (item 2).
- **The paced poll's "paused", with the send bit,** catches the one upload spin found, 7.85.0's
  over HTTP/2. Every fast poll of it met the conditions, and no poll in a turn that moved bytes
  was fast (item 3c).

**§3.4, found:** main's seam lookup in `resume!` (above).

**§3.5, confirmed:** the committed put. An escape at its section's end leaves the piece
committed and counted, 15 of 15, and the control loses it, 15 of 15 (item 5).

**§3.7 and §2.2, new rows:**

| What | 7.85.0 | 8.5.0 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|
| an answer while the body is sent | ends only at a resume, and never over HTTP/2 after a 200 | ends on its own after a close and after HTTP/2's 200, the body unsent | ends on its own, but not after a keep-alive 200 nor HTTP/2's 200; HTTP/2's 200 then ends 200 or 55 | as 8.20.0, HTTP/2's 200 then ending 200 |
| a connection lost under a paused upload (#11769) | a plaintext FIN never seen, 28 at the bound; HTTP/2 split | HTTP/2: 28 at the bound once in 8 on each build | ends at once | ends at once |
| HTTP/2, the send paused | the response arrives; the upload then never ends, 28 | with OpenSSL **the receive stalls** until the resume (cdd905a9), with GnuTLS not; both end at the response's end, the body cut | the response arrives; the transfer ends after the body | the same |
| HTTP/2, the receive paused | the send stops at the window; then 28 | the send does not start, 0 handed at 2.9 s in 4 of 4; the transfer ends at the response's end, the body cut | the send stops at the window until the consumer reads | the same |
| the poll during an HTTP/2 upload, paused | **spins**, 100% of a core, 3 runs of 4 | 2 polls in 3 s | 2 | 2 |
| the read's offer, a sized body | 65,536 to the end | 65,536 to the end | what the length owes; the first shares the head | the same |

**For slice 3 (§3.6), not this slice's to decide:**
- A full-duplex producer over HTTP/2 stalls while its consumer does not read, on every lane, at
  the peer's window (item 3b). Feeding the producer in the port's read is what lets it go on.
- 8.5.0 ends a call 200 when the response ends before the body is sent, the body cut, and leaves
  its stream open at the server (items 1, 3b). A caller that needs the server to have the whole
  body cannot tell from the outcome.

## Bounds for test-upload

- **Throughput:** 64 MiB through `curl-token-put-piece!`, 1,998.56 ms at worst natively and
  6,501.68 ms under the memory gate's Valgrind. So 10 s natively and 60 s under Valgrind, slice
  1's bounds, hold 5 and 9 times over.
- **The CPU of a paused upload:** over HTTP/2, 3 s with the read paused cost at most 42.444 ms
  with pacing on natively, and 3.858 ms under Valgrind. With pacing off, 7.85.0 spun,
  2,998.81 ms in 3 s; every other lane stayed at 0.583 ms or less, and both Valgrind lanes at
  2.644 ms or less. So:
  - a bound of 500 ms over a 2 s paused upload over HTTP/2 holds on every lane;
  - the pacing-off control fails it on 7.85.0 alone. It needs a version row, as test-stream's
    `spin-rows`: `7.85.0` spins, the rest are quiet;
  - under Valgrind the control cannot fail, since no Valgrind lane spins, and the floor has no
    Valgrind lane;
  - 7.85.0's spin came in 3 runs of 4, but in 2 of 2 with pacing off, the control's runs.
- **An early answer:** the cases that end on their own did so by 9.2 ms. Those that wait for a
  resume ended 0.6 to 8.3 ms after it (3,000.6 to 3,008.3 ms from a submit whose producer acted
  at 3 s). So "ends within 1 s, no resume" and "not done after 1 s" separate them by over 100
  times.
- **A connection lost under a paused upload:** where it ended on its own, it did so 202.6 to
  218.5 ms from the submit, the drop coming 200 ms after the bytes. On 7.85.0's plaintext FIN only
  the bound ends it, so a test of it there sets a short `timeout-ms` and expects 28.
- **libcurl's resend:** its first read came 1.165 ms at most after the second prerequest call.

## Not measured, and why

- **The Mac's 8.7.1:** not planned here. Its run would fill an 8.7.1 column. Its dropped rewind
  (§2.4) is the prerequest callable's case, and it does not multiplex (ADR-0030, amended).
- **A put past `body-length`, and a length of 0,** which §5.2 tests: the prototype has the
  first, but no program here exercised it; §2.1's probe measured the second.
- **A timer swept across the put a tick at a time,** as C10 did for the take: not in the work
  list, and the committed put has nothing after its section but its return.
- **Why libcurl's send stops while an HTTP/2 receive is paused,** past the server's own state
  (item 3b): a trace of the client's socket reads would show it.
- **Why HTTP/1.1 upload throughput is 33.6 to 39.4 MB/s on every lane, and faster under
  Valgrind** (item 6).
