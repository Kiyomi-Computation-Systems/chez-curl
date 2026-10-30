# M6 slice 1: the measurements of the plan's §4.1 (2026-10-30)

Measured before the slice builds anything, on a prototype of the plan's §3.2, §3.4 and §3.5. The
prototype is not the slice's build, and nothing here ships. `main` was at 46c1f3c. Every log
under `results/` came from `proto.patch` at sha256 `715a9e73fcaaf4ae…`, which `run.sh` prints on
each log's first line. The one exception is `results/stall/replay-guix-8.20.0-stalled.log`, from
an earlier patch (`a4067e79…`) that lacked the queued-poll counters.

## Files

| File | What it is |
|---|---|
| `proto.patch` | the prototype: `diff -ruN` of main's `src/` (as `orig/src`) against the prototype (as `work/src`) |
| `build.sh` | host: `build/m6s1/src` from `src/` and `proto.patch`, by GNU patch, with sums `run.sh` checks |
| `run.sh` | one lane: starts `server.mjs` with a fresh PKI, runs `PROGRAM.sps` on the prototype, optionally under the gate's Valgrind |
| `docker.sh` | the four Docker lanes, and Valgrind on Ubuntu's 8.5.0, in `ubuntu:24.04`; `wake` runs `wake.sh` instead |
| `all.sh` | host: every step below, one after another, so no two timed runs share the machine |
| `server.mjs` | the probe server: `http`, `raw`, `https`, `h2` and a CONNECT `proxy` face (not `tests/origin.mjs`) |
| `check.sps` | item 1: 4 MiB streamed whole and in order, every face, by `next-piece` and by the port |
| `paced.sps` | item 2: the paced poll, CPU and turns over a 3 s pause, submit, cancel and resume delays |
| `replay.sps` | item 3: `curl_easy_pause`'s longest replay, gzip under `ACCEPT_ENCODING`, and collections meanwhile |
| `head.sps` | item 4: the head read in the header callable against `finish-transfer`'s, every face, 1xx, CONNECT, 204, `head`, refused |
| `escape.sps` | item 5: the review's SIGINT recipe against the lent take, and the control |
| `throughput.sps` | item 6: 64 MiB through the write callable and a `next-piece` consumer |
| `wake.c`, `wake.sh`, `wake-strace.sh` | the lost wakeup on Guix's 8.20.0, in C with no Chez, and its `strace` |
| `wake-marked.c`, `wake-marked.sh` | host: `wake.c` with marks around each libcurl call, traced, to place the wakeup's read in `curl_multi_perform` |
| `results/` | the logs; `results/stall/` the lost wakeup's first evidence |

Item 7 also changed three files in `../pause/`: `probe.c` (the `PAUSE_NO_MULTIPLEX=1` switch and
its `conns` lines), `server.mjs` (the `/conns` route) and `docker.sh` (it passes the switch
in). With the switch unset nothing changes. `results/pause-unset-guix-8.20.0.log` reran every
case with the same outcomes as `../pause/results/round2/guix-8.20.0.log` (212 `done code=`
lines, 30 `exit=0`), but for `R-reset-mid`'s two `post` cases. Those split by timing on main's
own files too: `results/pause-reset-mid-guix-8.20.0.log`.

## Rerunning

On the host, from the repository's root:

```
sh .plans/research/m6/slice1/all.sh            # build, check, paced, replay, head, escape,
                                                # throughput, wake, nomux, regress
sh .plans/research/m6/slice1/all.sh paced head  # or some steps
```

`all.sh` shows each step's command lines. `build.sh` must run first, on the host, because the
Guix container has no `patch`. It makes `build/m6s1/src` afresh, and `run.sh` refuses a copy
whose sums differ. To regenerate the patch from an edited copy: put main's `src/` at
`build/m6s1/orig/src` and the edited copy at `build/m6s1/work/src`, then run
`(cd build/m6s1 && diff -ruN orig/src work/src) > .plans/research/m6/slice1/proto.patch`.

The Mac's run, for item 7:

```
PAUSE_NO_MULTIPLEX=1 CASES="D-hold-mux W-h2-error" NODE="$(asdf which node)" sh .plans/research/m6/pause/run.sh mac
```

## The prototype

What it adds, beside the plan's §3:

- `stream-buffer`, set by a private `curl-request-with-stream-buffer`;
- a stream per submit, made in the plan;
- the buffered write callable;
- the header callable and the head;
- the pause bits and the resume flag;
- the resume message and step;
- the paced poll;
- the lent take `curl-token-next-piece`, and a minimal port;
- `call-with-stream-held`;
- `curl_easy_pause`, bound plain (`bind-required`), plus a `__collect_safe` twin, for item 3's
  contrast alone;
- counters: turns, polls, polls under 1 ms, paced sleeps, resumes passed over, and polls that
  began with a message queued;
- an event log of each submit, cancel and resume, with the queueing, take and action times;
- switches: pacing off, the twin binding, and the control's take, which removes inside its
  hold.

The choices §3 did not make:

1. `stream-buffer` is kept in a weak `eq` table keyed by the request. The hatch's options go on
   first, because `curl-request-with-options` makes a new request.
2. The stream is made at submit, in the plan, so a take on a queued token looks at a real
   stream. The engine hands the stream its mutex, for the head, at set-up.
3. The write callable checks the body limit first, then the buffer. It copies the chunk inside
   the stream hold, so the copy and the append share one hold. A stream keeps no per-chunk log,
   only counts. The test for taking a chunk is strict: buffered + n < stream-buffer, or
   buffered = 0, as the second review's model.
4. A look counts the buffer the way the taker will see it after its removal: appended − taken −
   this piece. It queues a resume at or below `(div stream-buffer 2)`. A look that finds no
   piece counts appended − taken.
5. A look takes three holds, one after another inside one critical section: the engine's (is
   the token done?), the stream's (pick the piece, decide), then the engine's again to queue,
   only while the token is live and the engine running.
6. The removal is a leaf procedure of plain field writes, called last. The port's read sets its
   piece-at-hand and offset just before the removal.
7. The paced sleep comes straight after the fast poll, so the next turn takes whatever arrived
   during the sleep.
   - "Paused" means any live stream with either bit set, each read in its own hold after the
     table's.
   - "Moved a byte" is a process-wide counter, under `sinks-lock`, that the write callable bumps
     for each chunk it takes, whole bodies' chunks too. It is compared from the turn's start,
     before the take, to just after the poll.
8. A `curl_easy_pause` answer other than 0 records `pause-failed`, unless a reason is already
   recorded. The resume step then takes the transfer out, `finish-transfer` reads it, and the
   token completes.
9. The head lives on the stream, published under the engine's mutex, and `curl-token-head`
   reads it there. `curl-token-head-wait` answers once there is a head or the token is done.
   The callable reads `RESPONSE_CODE` and `HTTP_VERSION` by `curl_easy_getinfo` inside itself.
   `HEADERFUNCTION` is set on a streamed response alone.
10. The port has no thread rule. Its close cancels the token; at the end it answers 0, or raises
    the outcome.

## Results

The figures are the extremes the logs show. A grep that finds each one is given; the ranges
were drawn from every matching line.

### Item 1: the prototype streams whole and in order

Every lane, every face (`http`, `raw`, `https`, `h2`), both readers: `pattern=ok whole=#t`,
`status=200`, `body=#f`, pauses = resumes. That includes Valgrind on 8.5.0: 0 errors, 0 bytes
definitely lost.
`grep 'check face' results/check-*.log`

### Item 2: the paced poll

The quiet window: 3 s with the stream paused and the consumer taking nothing.
`grep window-ms results/paced-*.log`

| lane | pacing | CPU (ms) in the 3 s | polls | paced sleeps |
|---|---|---|---|---|
| ubuntu-openssl-8.5.0, http and h2 | off | 2999.126–3000.16 | 3,045,568–3,240,573 | 0 |
| ubuntu-openssl-8.5.0, http and h2 | on | 26.66–39.214 | 2,794–2,831 | 2,794–2,832 |
| ubuntu-gnutls-8.5.0, http and h2 | off | 2998.696–3000.273 | 3,019,801–3,165,048 | 0 |
| ubuntu-gnutls-8.5.0, http and h2 | on | 23.521–35.486 | 2,821–2,835 | 2,821–2,835 |
| floor-7.85.0 | either | 0.284–0.429 | 3 | 0 |
| guix-8.20.0 | either | 0.227–0.469 | 2 | 0 |
| current-8.23.0 | either | 0.25–0.355 | 2 | 0 |
| 8.5.0 OpenSSL, Valgrind, http | off | 3039.639–3066.984 | 48,796–50,921 | 0 |
| 8.5.0 OpenSSL, Valgrind, http | on | 365.542–369.516 | 2,506–2,515 | 2,506–2,515 |
| 8.5.0 OpenSSL, Valgrind, h2 | either | 1.072–4.275 | 2–3 | 0 |
| guix-8.20.0, Valgrind | either | 1.177–7.82 | 2–3 | 0–1 |

The delays, ms, from the caller's call to the engine acting on it.
`grep delays results/paced-*.log`

- A **submit** acts when its transfer is added to the multi handle; `submit-taken` is when the
  turn took the message.
- A **cancel** acts when the engine completes the token as cancelled.
- A **resume** runs from the look that queued it, inside the caller's take, to the engine's
  call of `curl_easy_pause`.

| lane | submit | cancel | resume |
|---|---|---|---|
| natively, all five, either pacing | 0.122–1.228 | 0.043–1.251 | 0.006–1.035 |
| 8.5.0, pacing on, http (the paced sleep) | 0.157–1.228 | 0.085–1.133 | 0.094–1.035 |
| 8.5.0 OpenSSL, Valgrind | 1.158–24.381 | 0.363–20.917 | 0.656–7.093 |
| guix-8.20.0, Valgrind | 1.341–6.397 | 0.47–24.545 | 0.117–6.252 |

Each kind has 24 samples per lane, face and pacing setting. Their sleeps of 23 ms plus 125 µs
times the round spread them over the 1 ms period. Every drain was whole and in order, but on
Guix's 8.20.0: 2 to 3 polls of 1005 ms in h2 drains. That is the lost wakeup, below.
`grep 'queued-polls-100ms=[1-9]' results/paced-guix-8.20.0.log`

### Item 3: `curl_easy_pause`'s longest replay

64 MiB of zeros, gzip at level 9, paused 1 s, then drained. Times are ms inside one call, the
plain binding with no collector.
`grep 'mode=alone' results/replay-docker.log`

| lane | 1 B | 64 KiB | 1 MiB | 16 MiB |
|---|---|---|---|---|
| floor-7.85.0 | 6.555–10.761 | 4.661–7.197 | 6.544–8.521 | 0.335–1.053 |
| ubuntu-openssl-8.5.0 | 8.256–9.661 | 6.664–7.653 | 5.231–7.013 | 6.182–7.922 |
| ubuntu-gnutls-8.5.0 | 8.399–9.924 | 6.133–6.223 | 7.741–7.872 | 15.153–21.647 |
| current-8.23.0 | 4.584–9.514 | 5.693–6.63 | 7.962–15.438 | 7.177–16.314 |

- The longest replay was at 16 MiB on 8.5.0 with GnuTLS (21.647 ms) and on 8.23.0 (16.314 ms),
  and at 1 byte on 7.85.0 (10.761 ms) and 8.5.0 with OpenSSL (9.661 ms).
- At 16 MiB one call appended up to 14,204,154 bytes. At 1 byte it appended 16,384, yet still
  took up to 10.761 ms: decoding inside the call costs more than delivering.
- Every body was whole, all zeros; every `curl_easy_pause` answered 0.

Collections, asked for back to back (100 µs apart) by another thread.
`grep collects results/replay-docker.log`

| what | median (ms) | longest (ms) | ended after the call returned (ms) |
|---|---|---|---|
| control: asked and done in the 1 s hold, no call under way | 0.005–0.009 | 0.276–18.452 | — |
| asked during a call, plain binding | 0.087–0.52 | 0.155–10.881 | −0.154–7.024 |
| asked during a call, `__collect_safe` twin | 0.008–0.201 | 0.088–6.119 | −0.085–1.271 |

Under the plain binding, a collection asked during a call waits for the rest of the call: its
median is near half the median call, 0.28–0.5 ms at 1 byte. Under the twin it goes on during
the call. The control's large maxima come at the big buffers, where the heap holds many
megabytes of pieces.

Guix's 8.20.0: **stopped**. Its full run stalled on the lost wakeup: 588 resumes in 300 s, then
28 (`results/stall/replay-guix-8.20.0-stalled.log`). The bounded run, 1 MiB at 1 byte and at
64 KiB, is the evidence: drains of 1,021.197–10,138.767 ms, and 1 to 10 polls of 1005 ms each,
which began with a message queued.
`grep queued-polls-100ms results/replay-guix-8.20.0-bounded.log`

### Item 4: the head

The head read inside the header callable equals, as whole values, the status, version and
headers `finish-transfer` read for the same response: every case on every face of every lane,
`equal=#t`.
`grep 'head case' results/head-*.log`

- **1xx**: the trace is `(100 . t) (103 . t) (200 . t)` on all four faces of all five lanes.
  Over h2, Node's `writeContinue` and `writeEarlyHints` reach libcurl, 7.85.0 to 8.23.0, each as
  a head of its own, its code at its empty line; each is passed over.
- **CONNECT**, an `https` URL through `https_proxy`: `(0 . t) (200 . t)` on all five, both TLS
  backends of 8.5.0 too. The proxy face counted 2 CONNECTs per run.
  `grep connects results/head-*.log`
- **Lead**: for a body written 300 ms after its head, the head comes first by 300.734–303.77 ms.
  Over 1xx, the final head and its 6-byte body arrive together, a lead of 0.003–0.014 ms.
- **204 and `head`**: the head is published and no piece arrives.
- **Refused connect**: no head, `head-wait` answers `#t`, code 7.
- Node's `http` and `https` faces hold a head back until the first write: `server.mjs`
  flushes it at once.

### Item 5: the take's escape

`grep 'escape run' results/escape-*.log`

- The lent take, under `next-piece`, `get-bytevector-some` and `get-u8`, with a handler that
  escapes or returns: 90 cases of 90 gave pieces (1 2 3) and received 5 bytes of each. None was
  lost and none given twice. Every escaping case read `first=escaped`.
- The control, which removes inside its hold: in all 45 escaping cases, piece 1 was lost,
  received bytes (0 5 5). In all 45 returning cases nothing was lost.

### Item 6: throughput

64 MiB of i mod 251, written 64 KiB a write; the wall time runs from the submit to the end,
read where the end is first seen. Every run was whole, `pattern=ok`, `eof`, and `status=200`;
pauses equal resumes, none passed over.
`grep 'throughput run' results/throughput-*.log`

| lane | stream-buffer 65,536 (ms) | 1,048,576 (ms) |
|---|---|---|
| floor-7.85.0 | http 1501.527–1629.916, https 1394.35–1467.317, h2 154.554–158.537 | 148.571–164.602 |
| ubuntu-openssl-8.5.0 | http 1213.936–1244.35, https 1162.531–1286.522, h2 994.915–1489.364 | 142.766–202.341 |
| ubuntu-gnutls-8.5.0 | http 1218.454–1277.132, https 1263.87–1292.857, h2 1351.763–1489.364 | 145.329–202.849 |
| guix-8.20.0 | http 150.915–206.859, https 151.633–160.711, h2 1122.79–1180.904 | 145.097–172.125 |
| current-8.23.0 | http 155.438–216.957, https 154.988–162.116, h2 1203.348–1235.223 | 143.485–151.288 |
| 8.5.0 OpenSSL, Valgrind (2 runs) | http 3847.984–4277.994, https 8245.859–9072.647, h2 8823.261–8837.515 | 3922.694–8367.01 |
| guix-8.20.0, Valgrind (2 runs) | http 4143.114–4509.079, https 8438.888–8899.232, h2 9389.13–9479.968 | 4095.947–9319.009 |

At 64 KiB: 940–3,921 pauses natively and 14–1,355 under Valgrind. At 1 MiB: 42–111 natively
and 0–63 under Valgrind. On Guix's 8.20.0, 0 to 160 polls a run began with a message queued,
none of 100 ms or more. Valgrind: 0 errors, 0 bytes definitely lost.

### Item 7: no multiplexing, the Mac's probe

`PAUSE_NO_MULTIPLEX=1` on all five Linux lanes: `curl_multi_setopt(CURLMOPT_PIPELINING, 0)`
answered 0.
`grep -E 'pipelining|conns prefix|done code' results/nomux-*.log`

- In both D-hold-mux variants, A and B each had a connection of their own (`n=2`). B ended 0,
  at 4.7–31.4 ms, while A was paused.
- In W-h2-error, A ended 23 and B ended 0 (1,048,576 bytes), each on its own connection.

## The lost wakeup, on Guix's 8.20.0

On the container's libcurl, Guix's 8.20.0 with GnuTLS, a `curl_multi_wakeup` made after the
engine's turn takes its messages and before its perform is lost: inside `curl_easy_pause` (the
resume step), or between that call and `curl_multi_perform`. The next `curl_multi_poll` then
waits for libcurl's own events, or its 1000 ms bound.

`wake.c` shows it with no Chez, in a loop like the engine's turn (`results/wake-*.log`). On
`guix-8.20.0`:

- `pause`: 14 of 14 timed polls lasted 100 ms or more, the longest 1005.0 ms;
- `after`: 14 of 14 too, the longest 1005.0 ms;
- `plain`, with no pause: 15 of 18 polls waited for the next bytes, up to 50.8 ms;
- the control `before-poll` was kept: 15 of 15 at 0.0 ms.

7.85.0, both 8.5.0 builds, 8.23.0, and an upstream 8.20.0 built with OpenSSL
(`results/wake-docker-vanilla-8.20.0.log`) keep it in every case.

`results/stall/wake-guix-8.20.0-strace.txt` shows each turn's `write(4)`, the wakeup, then
`read(4) = 8`, then a `poll(2)` that times out. **The read is `curl_multi_perform`'s**, not
`curl_multi_poll`'s, as this README first said. `wake-marked.c` writes a mark to stderr around
each call of the turn, and `wake-marked.sh` traces it on the host
(`results/stall/wake-guix-8.20.0-marked-strace.txt`):

- in the `after` case, each `read(4) = 8` falls between `M-perform-start` and
  `M-perform-end`, and the poll then times out;
- in the `before-poll` control, the wakeup written after `M-perform-end` ends the poll at once,
  and `curl_multi_poll` reads it back after its `poll(2)` returns.

So a wakeup made before the perform, inside `curl_easy_pause` among them, is lost; one made
after it is kept. Why Guix's build drains in the perform and upstream's 8.20.0 does not was not
found. The engine's answer, decided on 2026-10-30, is a look at its queue between the perform
and the poll (ADR-0012, amended).

In the prototype it costs about 1 s for every resume whose look lands while the engine is in
its resume step or perform:

- the fast drains of item 3: 1 to 10 slow polls per drain of 25 to 63 resumes
  (`replay-guix-8.20.0-bounded.log`);
- h2 drains in item 2, 2 to 3 per 8 MiB;
- in item 6, polls that began with a message queued were common (0 to 160 a run), but none was
  slow.

Submits and cancels queued during a turn are exposed the same way. The engine has relied on
the wakeup since M3.
