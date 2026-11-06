# Two questions carried past M7: call-state's guard, and 8.5.0's paused HTTP/2 send

Measured 2026-11-05 on a snapshot of `29f4b5d` (`main`), never the working tree: copies in
`build/carried-guard/`, made by [`probe/make_copies.py`](probe/make_copies.py). Guix runs went
through `scripts/guix-env` under `taskset -c 10-17` ([`probe/run-in.sh`](probe/run-in.sh)); the
Docker lanes ran in `--rm ubuntu:24.04 --cpuset-cpus 10-17`
([`probe/lanes.sh`](probe/lanes.sh), as `build/m7s4b/lanes.sh` runs them). Every number below
is from a log in [`results/`](results/). The engine sweeps' logs are gzipped:
`zcat results/engine-fine-*.log.gz`.

**The seam.** Every copy carries `(curl private gate)` ([`probe/gate.sls`](probe/gate.sls)),
called at `call-state`'s `enter` (the first form of its checks) and `exit` (after
`curl-request-check`), and at a URL parse's `parse` and `parse-end` (the first and last forms
of `call-with-flagged-url`'s body, inside its critical winds). Unarmed it does nothing: the
seamed copy `today` passes the ten high-level suites
([`results/suites-today.log`](results/suites-today.log), 647 passes, 0 failures).

## Question 1: call-state's guard

### Today, measured

`call-state` (`src/http-client.sls:553-576`) wraps its checks in
`(guard (e ((condition? e) (raise (condition e (make-http-exchange ...))))) ...)`. Every entry
reaches it: `http-request`, `call-with-response-port`, a group's `go` and `http-parallel`.

**Ctrl-C** ([`probe/sigint-child.sps`](probe/sigint-child.sps), run by
[`probe/sigint-probe.sps`](probe/sigint-probe.sps); [`results/sigint-today.log`](results/sigint-today.log)).
The seam blocks the call at `enter` or `parse` on a mutex another thread holds until the parent
has sent SIGINT (test-group's `child-hold` pattern: `collect-rendezvous` first, the hold until
the sent file exists, `quiet` checked). The handler runs as the gate's section ends, inside
`call-state`. Four actions: `raise-cond`, a planted `&curl-engine-error`; `cont-cond`,
`raise-continuable` of a `&warning`, which the caller's `with-exception-handler` returns from
(test-http-client's M5 timer test's handler); `raise-false`, `(raise #f)`; `cont-sym`,
`raise-continuable` of `'tick`, returned from. All four entries answered alike, 32 of 32
children, every one `quiet`, holding `(0 0 0)` and its counts zero:

| place | handler | caller receives today |
|---|---|---|
| enter | raise-cond | the plant compounded with `&http-exchange` |
| enter | cont-cond | a `&non-continuable` violation: the guard re-raised the compounded warning with `raise`, and the caller's handler returned from it |
| enter | raise-false | `#f`, as raised |
| enter | cont-sym | the call resumes, 200: the guard declines a non-condition and re-raises it continuably |
| parse | raise-cond | compounded |
| parse | cont-cond | `&non-continuable` |
| parse | raise-false | **`call-with-parsed-url`'s re-entry refusal, compounded** |
| parse | cont-sym | **the re-entry refusal, compounded; the caller's handler never ran** |

The last two are new, and so are not documented: R6RS `guard` re-raises an object no clause
takes "in the dynamic environment of the original call to raise", so it unwinds out of the
parse (its after thunk frees the handle), finds no clause, and rewinds into it, where the
critical before thunk refuses re-entry (`src/curl/private/url.sls:187-188`). Reproduced in pure
Chez, no libcurl ([`probe/guard-rewind.sps`](probe/guard-rewind.sps),
[`results/guard-rewind.log`](results/guard-rewind.log)): a symbol or `#f` declined by a
`condition?` clause comes out as the before thunk's raise, the before thunk run twice.

**A timer** ([`probe/timer-probe.sps`](probe/timer-probe.sps),
[`results/timer-today.log`](results/timer-today.log)): the seam sets `(set-timer 1)` at the
place; the timer handler does the same four things. 32 of 32 rows match the SIGINT table cell
for cell.

**An engine's expiry** ([`probe/engine-sweep.sps`](probe/engine-sweep.sps),
`results/engine-fine-today.log.gz`, summarized by
[`probe/summarize-engine.py`](probe/summarize-engine.py)): each call inside a Chez engine,
fuel swept from 1 to 1400 **a tick at a time**, the seam's marks read at the expiry, then the
engine resumed. `call-state` runs from fuel 25 to 676 for `http-request` (30 to 708 for the
port, 59 to 710 for `go`, 70 to 1109 for `http-parallel`, whose checks parse twice). Of the
fuels whose expiry landed inside `call-state`:

| entry | inside | resumed: re-entry refusal, compounded | resumed otherwise |
|---|---|---|---|
| http-request | 652 | 162 (158 inside the parse's body, 4 at its winds' edges) | 490 answered 200 |
| call-with-response-port | 679 | 162 | 517 answered 200 |
| go | 652 | 162 | 490 raised `closed`, as documented |
| http-parallel | 1040 | 395 | 645 answered `(200)` |

The coarse sweep by 100 to 30,000 ([`results/engine-coarse-today.log`](results/engine-coarse-today.log))
shows the documented rest: an expiry in the await cancels, the port's reads then raise that
cancel and the closed port's error.

The brief's three cases hold as stated, at every entry. One citation is off by a few lines:
the refusal itself is at `url.sls:187-188`, in `call-with-flagged-url`, which
`call-with-parsed-url` (`:168-175`) calls.

### The options, prototyped

All in [`probe/make_copies.py`](probe/make_copies.py). Each ran the same probes and the ten
high-level suites (test-http-client, test-group, test-stream-call, test-retry, test-redirect,
test-auth, test-proxy, test-cookies, test-printed, test-version).

**(a) One critical section.** `call-state`'s checks inside `critical-section`, the guard inside
it with a `#t` clause that answers `(refused X)` as data, `X` compounded when a condition, and
the raise made once the section has ended:

```scheme
(made (critical-section
       (guard (e (#t (list 'refused (if (condition? e)
                                        (condition e (make-http-exchange method given '() 0))
                                        e))))
         (check-session who session)
         (let-values (((request redirects allow-downgrade retry producer)
                       (call-request-of who mode session method given plist)))
           (when check? (curl-request-check request))
           (list 'made (cons (make-exchange ...) producer))))))
(if (eq? (car made) 'refused) (raise (cadr made)) (cadr made))
```

- **What a caller sees** ([`results/sigint-a.log`](results/sigint-a.log),
  [`results/timer-a.log`](results/timer-a.log)): every Ctrl-C and timer row, at every entry and
  both places, the handler running after the checks (its marks read `enter ... exit`): the
  planted condition itself, never compounded; `#f` as raised; both continuable raises resume the
  call, which answers 200, the caller's handler having returned once. 32 of 32 children, 32 of 32
  timer rows.
- **Engine** (`results/engine-fine-a.log.gz`): **0** of 5,600 fuels expired inside
  `call-state`, and no resumed call raised the re-entry refusal; the trail goes from no mark
  straight to `enter ... exit` (fuel 19 to 20 for `http-request`), so the sweep crossed it a
  tick at a time. An expiry in the section lands after it: resumed, the call answers 200, or
  `go` raises `closed`, as documented.
- **Refusals** ([`results/refusal-a.log`](results/refusal-a.log),
  [`probe/refusal-probe.sps`](probe/refusal-probe.sps)): an unknown key, a body that is no body,
  an ftp URL, a header name with a space, prior knowledge on https, at each entry: compounded as
  today, row for row ([`results/refusal-today.log`](results/refusal-today.log)), and the
  caller's handler runs with interrupts on in every row.
- **M5's and M7's tests:** 647 passes, 0 failures ([`results/suites-a.log`](results/suites-a.log)).
- **What it holds** ([`probe/cost.sps`](probe/cost.sps), [`results/cost-a.log`](results/cost-a.log)
  beside [`results/cost-today.log`](results/cost-today.log)): the checks' time, then the longest
  stall of a thread asking for collections back to back, and how long a SIGINT sent at `enter`
  waited:

| case | checks today | stall today | Ctrl-C today | checks (a) | stall (a) | Ctrl-C (a) |
|---|---|---|---|---|---|---|
| get, no body | 0.01-0.09 ms | 0 | 0.03 ms | 0.01-0.11 ms | 0 | 0.04 ms |
| post, 1 MiB bytevector | 0.15-0.23 | 0 | 0.02 | 0.12-0.23 | 0 | 0.15 |
| post, 64 MiB bytevector | 45-49 | 38 | 40 | 28-30 | 29 | 33 |
| post, 256 MiB bytevector | 167-203 | 149 | 150 | 107-110 | 121 | 123 |
| post, 64 Mi-char string | 142-164 | 79 | 128 | 156-158 | 159 | 156 |
| form, one 1 Mi-char value | 49-50 | 7 | 0.02 | 34-41 | 34 | 35 |
| form, one 16 Mi-char value | 1305-1364 | 216 | 0.02 | 687-786 | **833** | **780** |
| form, 100,000 pairs | 48-52 | 7 | 0.02 | 36-41 | 34 | 37 |
| 1,000 headers | 0.33-0.42 | 0.34 | 0.02 | 0.33-0.40 | 0 | 0.34 |
| 100,000 headers | 67-75 | 10 | 0.02 | 45-47 | 48 | 47 |
| a 7.9 MB URL | 274-313 | 54 | 3.8 | 260-266 | **266** | **269** |
| params, 100,000 pairs | 82-84 | 10 | 0.03 | 66-68 | 67 | 69 |
| http-parallel, 1,000 gets | 16-19 | 0.11 | 0.02 | 15-16 | 0.45 | 0.03 |
| http-parallel, 32 posts of 4 MiB | 64-66 | 12 | 0.55 | 80-85 | 15 | 0.56 |

  Today already holds collections and Ctrl-C through a large body's copy: `bytevector-copy`,
  `string-copy` and `string->utf8` are primitives that make no event check while they run, so
  a 256 MiB copy held them 149 ms with no section at all. (a) adds holds only where the checks
  run Scheme loops: the form's encoding, the URL's checks, headers and params, each at
  sizes no ordinary call reaches; an ordinary call holds under 0.5 ms. `http-parallel` makes
  one section per spec, so its hold is one spec's. The drive's submit already holds the same
  way, inside its section: 207 to 227 ms for a 256 MB body (drive.sls's header). Peak memory
  ([`probe/peak.sps`](probe/peak.sps), [`results/peak-a.log`](results/peak-a.log) beside
  [`results/peak-today.log`](results/peak-today.log)): no higher for a large body or form
  (the 16 Mi-char form peaked 1,074 MB against today's 1,417 MB), about 40 MB higher at 100,000
  headers or params, whose garbage waits for the section's end.
- **Inside the section, nothing waits, and no caller code runs.** By reading: the keys,
  bodies, forms, params and headers are read by `length`, `car`, `cdr`, `string-copy` and
  `bytevector-copy`; a producer is stored, never called; `shown-value` is pure; no `getenv`, no
  file and no network (the CA environment is the load's record). Three mutexes are taken, all
  through `locked`, each inside a critical section of its own already, held briefly and never
  across a wait: the counters' (`count-up!` for each CURLU and C string), native's
  `owners-lock` and memory's lock (each C string's block), for each URL parse. The guards
  inside (`string-pairs`'s around `length`, `decoded`'s in each URL part's read,
  `check-proxy-url`'s in `http-parallel`'s check) then read the code's own raises alone, which
  today they do not.

**(b) Narrower: no guard spanning the checks.** `call-request-of` takes a `compound`
procedure; each high-level refusal (`refuse`, `key-settings`, the policy's checks,
`call-body`, `call-pairs`, the stream-buffer assertion, `check-session`) is raised compounded
where it is made; each `(curl)` call of the checks (both `make-curl-request`s, the URL's read,
`curl-request-check`) runs in `answered`, a section of its own whose guard answers its raise as
data, raised compounded after; `string-pairs`'s guard gets a section of its own.

- **What a caller sees:** the same as (a), row for row
  ([`results/sigint-b.log`](results/sigint-b.log), [`results/timer-b.log`](results/timer-b.log)),
  but the handler runs where it lands: at `enter` at once, inside a parse as that parse's
  section ends.
- **Engine** (`results/engine-fine-b.log.gz`): 114 fuels expired inside `call-state`, between
  its sections; every resumed call answered 200, or `go` `closed`; none raised the re-entry
  refusal.
- **Refusals** ([`results/refusal-b.log`](results/refusal-b.log)): as today, interrupts on.
  **Tests:** 647 passes, 0 failures ([`results/suites-b.log`](results/suites-b.log)).
- **What it holds** ([`results/cost-b.log`](results/cost-b.log)): today's holds, but for
  `(curl)`'s calls: a 7.9 MB URL 233 ms (its parse in a section), 100,000 headers 23 ms, 100,000
  params 44 ms; the 16 Mi-char form 211 ms, as today, and Ctrl-C at once there.
- **What it costs in code:** about fifteen definitions of `call.sls` change signature, and every
  refusal a later slice adds to the checks must carry `compound`, or be `answered`: a forgotten
  one raises without its `&http-exchange`, and only a test of that refusal would see it.

**(c) Leave it, documented.** Today's documentation covers the compounded condition and the
engine's re-entry refusal, but not the two rows found here: a continuable condition the
caller's handler returns from becomes `&non-continuable`, and a non-condition raised inside a
URL's parse becomes the re-entry refusal, compounded. (c) needs those two documented.

**Rejected:** parameterizing the caller's `keyboard-interrupt-handler` and
`timer-interrupt-handler` around the checks, to tag a handler's raise for the guard: it rewrites
the caller's handlers during a call, a guard still rewinds into the parse on a decline, and an
engine's expiry is no raise, so the re-entry refusal stays.

### Mutants of (a)

Each a copy (`a-guard-outside`, `a-raise-inside`, `a-section-late`, `a-no-compound`), each run
through the four probes and test-http-client, test-group and test-stream-call
([`results/run-probes-mutants.out`](results/run-probes-mutants.out)):

| mutant | SIGINT matrix | timer matrix | engine sweep | refusal probe | existing suites |
|---|---|---|---|---|---|
| guard outside the section | **fails**: compounded, and both continuable rows `&non-continuable` | passes | passes, 0 inside | passes | pass, 220 of 220 |
| the refusal raised inside the section | passes | passes | passes | **fails**: the caller's handler runs with interrupts off, for the keys', the body's, a header's and `http-parallel`'s check refusals | pass |
| the section entered after `call-request-of` | **fails**, as today | **fails** | **fails**: 2,635 fuels inside, 648 re-entry refusals | passes | pass |
| no compounding | passes | passes | passes | **fails**: not compounded | **fail**: 13 tests, 6 + 3 + 4 |

Logs: `results/{sigint,timer,refusal}-a-*.log`, `results/engine-fine-a-*.log.gz`,
`results/suites-a-*.log` with each suite's log under `results/suites/`. **Only the SIGINT test
sees the guard outside the section**: a timer that runs out inside a section fires at a later
event check, outside the guard (traps.md, "A Chez timer cannot plant an escape where a keyboard
interrupt lands"), and an engine's expiry likewise. And no existing test sees the first three
mutants.

### Recommendation: (a)

It closes all three cases at all four entries with the house pattern the drive's submit and the
group's sections already use, a dozen lines in one definition; refusals and every M5 and M7
test are as they were. Its cost is the checks' length held: under 0.5 ms for an ordinary call,
no worse than today for a large body, whose copy already holds; up to 0.27 s for a 7.9 MB URL
and 0.8 s for a 16 Mi-char form value, sizes the docs can name. (b) holds less at those sizes
but spreads a rule across `call.sls` that a later refusal can break silently. If the form's
hold matters, a cheaper `form-encode` (it builds a list of every UTF-8 byte; 1.4 GB peak today
for a 16 Mi-char value) shrinks it under either option.

**What the builder changes:**

1. `src/http-client.sls`, `call-state` as above; import `(only (chezscheme) critical-section)`.
2. A test seam, as drive.sls's produce gate is one: a gate run at the checks' start and end
   inside the section, from a private library, not exported by `(http-client)`.
3. Tests, each watched failing under the mutant named:
   - test-http-client, test-stream-call and test-group: a SIGINT child per entry
     (`http-request`, `call-with-response-port`, `go`, `http-parallel`), blocked at the gate's
     start on a mutex held until the SIGINT is sent, `child-hold`'s pattern: a handler's planted
     `&curl-error` leaves as raised, that very object, not compounded, nothing submitted, counts
     zero, `quiet`; and a continuable `&warning` the caller's handler returns from resumes the
     call, which answers 200. Fails today, `a-guard-outside` and `a-section-late`.
   - An engine sweep a tick at a time across the checks at each entry: no expiry lands between
     the gate's start and end marks, and no resumed call raises `call-with-parsed-url`'s refusal;
     its evidence, an expiry before the start mark and the next fuel's after the end. Fails
     today and `a-section-late`.
   - A refused call's caller handler runs with interrupts on (a take of no time from a fresh
     mailbox, as the drive's `interrupts-on?` asks). Fails `a-raise-inside`.
   - The existing compounding tests hold `a-no-compound`.
4. Comments: `http-client.sls`'s header (lines 79 to 88, "One that lands earlier, while the
   call's keys and URL are checked, is compounded"), its export comments for `go` (360 to 362),
   the group's engine expiry (380 to 383) and `http-parallel` (432 to 440), `call-state`'s own
   (553 to 564), and drive.sls's header (205 to 209): the checks run in one critical section; a
   handler's raise there comes as it ends, as raised, a continuable one resuming the call; an
   expiry lands after them; Ctrl-C and other threads' collections wait the checks out, with the
   table's sizes.
5. Records: the M5 plan's §10 item and the ledger's carried list (progress.md, "call-state's
   guard compounds ..."), closed; global-constraints, the checks' section beside the submit's;
   traps.md and AGENTS.md, the guard trap below; CHANGELOG.

## Question 2: 8.5.0's paused HTTP/2 send, for a caller

### The paths

- **The low level**, a request with `body 'stream`: `curl-token-head-wait`, `curl-token-head`,
  `curl-token-next-piece`, the body port's reads and `curl-token-await`, each before the first
  put, between puts, or before the end. Measured: all but `curl-token-await`, whose wait is the
  transfer's.
- **The high level** never waits for a head without feeding: before the final head
  `wait-head!` alternates a 10 ms head wait with `feed!`, which calls the producer as soon as
  libcurl asks and has room, and puts its piece; inside PROC's reads the port feeds the producer
  whenever no piece is ready (`src/http-client/private/drive.sls`, `feed!` and `wait-head!`). So
  a send stays paused at most one poll plus the producer's own time. The one caller-visible
  wait is a producer slow to give its next piece; and a PROC that never reads, already
  documented.

### Measured

Servers that answer before they read the body: `answer`, the raw face's
`/raw/answer?status=200&close=0` and HTTP/2's `/answer?status=200`, ending their side; and
`mirror`, `/raw/mirror` and HTTP/2's `/mirror`, the head at once and the body echoed. Faces:
raw (HTTP/1.1), raw-tls, h2c (prior knowledge) and h2 (TLS). A post, body stream, chunked,
`stream-buffer` 65536, `timeout-ms` 8000.

**Low level** ([`probe/paused-send.sps`](probe/paused-send.sps), 144 runs a libcurl; seven
paths for `answer`, five for `mirror`, 3 reps): [`results/paused-guix.log`](results/paused-guix.log)
(8.20.0), [`results/lane-floor-low.log`](results/lane-floor-low.log) (7.85.0),
[`results/lane-openssl-low.log`](results/lane-openssl-low.log) and
[`results/lane-gnutls-low.log`](results/lane-gnutls-low.log) (8.5.0),
[`results/lane-current-low.log`](results/lane-current-low.log) (8.23.0). **The head came every
time, 0 to 14 ms after the submit, over HTTP/1.1 and HTTP/2, on all five, 720 of 720**, before
any put, after libcurl's ask, and after one put. Outcomes, as test-upload's answer rows hold
them: 200 everywhere but 8.20.0's HTTP/2 `answer`, 55 (test-upload: "8.20.0's HTTP/2 200 then
ends 200 or 55").

**This contradicts the brief's premise that a caller meets it as a rule.** The stall is a
race. The answer held until a release from a second engine
([`probe/paused-held.sps`](probe/paused-held.sps)), on h2c and h2, released at once after the
submit (`release-first`) or after libcurl's ask and 0, 50 or 250 ms:

| libcurl, run | runs | head-wait ended at its 3 s bound, no head |
|---|---|---|
| 7.85.0, 8.20.0, 8.23.0, native | 80 each | 0 ([`results/lane-floor-held.log`](results/lane-floor-held.log), [`results/held-guix.log`](results/held-guix.log), [`results/lane-current-held.log`](results/lane-current-held.log)) |
| 8.5.0 OpenSSL and GnuTLS, native | 160 + 4,000 | **5**, all `release-first` on h2c: 5 of 520 of that path, 0 of 3,640 others ([`results/lane-openssl-held.log`](results/lane-openssl-held.log), [`results/lane-gnutls-held.log`](results/lane-gnutls-held.log), [`results/lane-openssl-held-native-250.log`](results/lane-openssl-held-native-250.log), [`results/lane-gnutls-held-native-250.log`](results/lane-gnutls-held-native-250.log)) |
| 8.5.0 OpenSSL and GnuTLS, native, the head waited for 12 s, nothing ever put | 600 | **4**, the wait ending as the transfer's 8 s timeout did, 28, no head ever ([`results/lane-openssl-held-long.log`](results/lane-openssl-held-long.log), [`results/lane-gnutls-held-long.log`](results/lane-gnutls-held-long.log)) |
| 8.5.0 OpenSSL and GnuTLS, under Valgrind | 160 + 640 | **6**: `release-first`, `ask-then-0` and `ask-then-250`, h2c and h2 ([`results/lane-openssl-held-valgrind.log`](results/lane-openssl-held-valgrind.log), [`results/lane-openssl-held-valgrind-40.log`](results/lane-openssl-held-valgrind-40.log), [`results/lane-gnutls-held-valgrind-40.log`](results/lane-gnutls-held-valgrind-40.log)) |

In every stall libcurl had asked for the body and nothing was put; the body's end then brought
the head 1 to 35 ms later, and the transfer ended 200. Left alone, with nothing put, the stall
lasted to the transfer's timeout, 8,006 to 8,010 ms, which ended the wait: it ends at its bound
or at the timeout, never at the answer. 15 stalls in all, 9 native of 4,760 runs with the
answer held, 6 under Valgrind of 800; none in the 144 8.5.0 HTTP/2 runs whose server answered as
the head arrived.

**High level** ([`probe/paused-send-high.sps`](probe/paused-send-high.sps), 96 runs a
libcurl: `call-with-response-port` and `http-post`, producers slow-first (1.5 s, then the
end), paced (three pieces 0.5 s apart) and fast): [`results/high-guix.log`](results/high-guix.log),
`results/lane-{floor,openssl,gnutls,current}-high.log`. PROC was called 1 to 11 ms into the
call in every run, before the producer's first piece returned; on 8.5.0 the `answer` server's
early 200 ended the call at once over HTTP/2, the producer never called (README's "An early
success can cut the body"). No stall met; one would hold PROC for one producer call, by the
drive's reading above, unmeasured.

**Apple's 8.7.1, by its source** (`build/m4s3/src/curl-8.7.1`): `drain_stream` still sets OUT
beside IN (`lib/http2.c:212-229`), but `select_bits_paused` (`lib/transfer.c:382-398`) answers
FALSE when IN is set and the receive is not paused, so `Curl_readwrite` (`:414`) reads: the
head arrives while the send is paused. 8.8.0's is the same (`:380`). 7.85.0's `lib/transfer.c` has no such early return, and
8.20.0's and 8.23.0's no `select_bits_paused`; all three read the head in every run above. The Mac can run
`probe/paused-held.sps` to confirm.

### README draft

For README.org's "Sending a body as it is produced" list, after the bullet "*Over HTTP/2, a
transfer that streams both ways sends only while you read.*":

```org
- *On Ubuntu's libcurl 8.5.0, over HTTP/2, a paused upload can hide the answer.* Rarely, once
  libcurl has asked for the body and you have put nothing, the response waits for your next
  put or end: a head wait answers =#f= at its bound, and a read waits for the timeout. Put or
  end the body first, or bound the wait and then put.
```

The high level's docs need no line: its drive feeds the producer whenever libcurl asks, so the
stall can last no longer than the producer takes to give its next piece, a wait every libcurl
already shows a slow producer.

## Traps found

- **A `guard` that takes no clause re-enters the raise's dynamic extent to re-raise it.** R6RS
  re-raises a declined object "in the dynamic environment of the original call to raise": every
  before thunk between runs again. Inside `call-with-flagged-url`'s critical wind, whose before
  thunk refuses re-entry once the handle is freed, a Ctrl-C handler's `(raise #f)` or
  `(raise-continuable 'tick)` came out of `call-state`'s `condition?` guard as the re-entry
  refusal, compounded, the caller's handler never run ([`results/sigint-today.log`](results/sigint-today.log),
  [`results/timer-today.log`](results/timer-today.log)); in pure Chez, a declined symbol came
  out as a before thunk's raise, that thunk run twice ([`results/guard-rewind.log`](results/guard-rewind.log)).
  For AGENTS.md: "A `guard` whose clauses decline a raise rewinds into the raise to re-raise it,
  running every before thunk between again: inside a wind that refuses re-entry, the declined
  object becomes that refusal. A guard that must pass a raise on unchanged takes it `#t` and
  answers it as data."
- **8.5.0's paused HTTP/2 send is a race, not a rule** (amends the newest trap): 9 of 4,760
  native runs with the answer held, each released as the request went out, racing libcurl's
  first ask; 6 of 800 under Valgrind, after the ask too; none of 144 with the answer as the head
  arrived. Stalled with nothing put, the wait ended only at the transfer's timeout, 28. A test
  that needs the head first still ends the body, or puts, first; a check that the stall is
  gone needs hundreds of runs, not a handful.
- **A large copy holds collections and Ctrl-C with no critical section:** `bytevector-copy`,
  `string-copy` and `string->utf8` make no event check while they run, so today's 256 MiB body
  copy in a call's checks held another thread's collection 149 ms and a SIGINT 150 ms
  ([`results/cost-today.log`](results/cost-today.log)). A hold's cost is measured by a thread
  that asks for collections back to back, counting the gaps its wake-ups wait, not only its
  rendezvous: a thread that wakes from `sleep` while a collection is due waits before it can ask.

## Files

- `probe/`: the seam, the copy maker, every probe and runner named above.
- `results/`: every log cited; `suites/VARIANT/` each suite's whole log.

## The build: option (a), as the maintainer chose it (2026-11-05)

Built in `build/carried-guard/build/`, a fresh copy of the snapshot; the patch,
`build/carried-guard/build.patch`, is `diff -ruN` of `src/` and `tests/` against it, and applies
with `patch -p1` from the repository's root (dry-run against the working tree: clean). Logs in
[`build/`](build/).

- **Code:** `call-state` as prototyped (`src/http-client.sls`), its comments, the header's and
  the export comments'; the seam `drive-checks-gate-set!` in `(http-client private drive)`,
  beside the produce gate, called with `start` and `end` inside the section, inert unless
  armed; drive.sls's header.
- **Tests:** a new suite, `tests/test-call-checks.sps`, 22 tests; and test-group's two engine
  sweeps no longer admit `call-with-parsed-url`'s re-entry refusal. test-http-client.sps is
  untouched.
- **Each watched failing** ([`build/run-build-mutants.out`](build/run-build-mutants.out),
  `build/mutant-*.log`, each suite's log under `build/mutants/`), the build's copies made by
  [`probe/build_mutants.py`](probe/build_mutants.py):

| mutant | test-call-checks | test-group | others |
|---|---|---|---|
| today's guard, no section | 20 of 22 fail: the 8 SIGINT, 4 timer and 8 sweep tests | the 2 sweeps fail: the re-entry refusal at 38 of http-parallel's fuels and 8 of go's | |
| guard outside the section | the 8 SIGINT tests fail: compounded, `&non-continuable` | pass | |
| refusal raised inside the section | the refusal test fails: interrupts off in all 9 rows | pass | |
| section after `call-request-of` | 20 of 22 fail | the 2 sweeps fail | |
| no compounding | the refusal test fails | 3 fail | test-http-client 6, test-stream-call 4 |

- **Checks:**
  - `make test` in the Guix container, `taskset -c 10-17`: 41 of 41
    ([`build/make-test-guix.log`](build/make-test-guix.log)); `check-seam`, 21 libraries, and
    `check-suites`, 41 suites, again on the final source
    ([`build/check-seam-suites-2.log`](build/check-seam-suites-2.log)).
  - The four Docker lanes, `--cpuset-cpus 10-17`, test-http-client, test-stream-call,
    test-group and test-call-checks: 4 of 4 on each ([`build/lanes.out`](build/lanes.out),
    `build/lane-*-lanes.log`).
  - The memory gate on Ubuntu's 8.5.0 (OpenSSL), the same four suites, five rounds, each in a
    container of its own pinned to two CPUs (10,11 twice, 12,13, 14,15, 16,17): 5 of 5
    rounds, 20 of 20 suite runs passed, each Valgrind log 0 errors and 0 bytes definitely lost
    ([`build/memory-A.out`](build/memory-A.out) to `memory-D.out`,
    `build/lane-openssl-memory-*.log`, each round's logs under `build/memory-openssl-memory-*/`).
- **The holds, on the build** ([`probe/cost-build.sps`](probe/cost-build.sps),
  [`build/cost-build.log`](build/cost-build.log)): as the prototype's (`results/cost-a.log`),
  within run-to-run spread; the comment in `src/http-client.sls` gives both runs' ranges.

## The fix round, after the branch's review (2026-11-06)

The review ([`../review/README.md`](../review/README.md)) found the class call-state's section
closed still open at a redirect's step (M1) and in a direct caller's `curl-submit` (m1), and a
URL's hold unbounded (M2). Done in the working tree itself, the maintainer's options. Logs in
[`fix/`](fix/); the pre-fix tree's copy is `build/carried-guard/fix-base/`, the fixed tree's
`build/carried-guard/fix/`.

### The audit: every guard in `src/` that can reach a critical wind

The critical winds whose before thunk refuses re-entry once its handle or string is freed:
`get-part` (`url.sls:168`, refusing at `:170`), `call-with-flagged-url` (`url.sls:201`, `:203`),
which `call-with-parsed-url` and `proxy-url-reading` use, and `call-with-c-bytes`
(`native.sls:430`, `:432`), under every C string. Other critical winds do work in their before
thunks without refusing: `curl-url-get`'s slot (`native.sls:990`, inside the parse winds), the
getinfo slots (`:1027`, `:1042`, `:1056`, `:1255`, the engine's thread alone), the drive's
(`drive.sls`, before thunks `#f`), `produce!`'s (it sets the producing flag) and `locked`'s
`with-mutex`, every one entered inside a critical section. A guard whose clause takes `#t`
declines nothing, so rewinds into nothing; those are listed once.

| site (fixed tree) | its body reaches | entries | interrupts there | a declined raise, or an expiry | verdict |
|---|---|---|---|---|---|
| `exchange.sls:784`, follow's target guard, `curl-url-error?` | `redirect-url` (`:661`): `curl-url-resolve`, `curl-url-part`, `curl-url-with-fragment`, each through `call-with-flagged-url`, `get-part`, `call-with-c-bytes` | `http-request` and the verbs (drive-exchange's step), `call-with-response-port` and a producer's `http-request` (drive-stream's steps and `exchange-steps-past?`) | **on**, before the fix; a group's step (`step!` in `turn!`) off | rewinds into a refusing wind: the review's 679 timer, 1,498 engine of 8,000 | **fixed**: every single-call step in a section (`section-step`, `drive.sls:369`) |
| `exchange.sls:794`, follow's parts guard | `curl-url-part` of the target, three times | the same | the same | the same | **fixed**, the same section |
| `exchange.sls:800-811`, follow's bare `curl-url-part`s of the requested URL | `call-with-flagged-url` | the same | the same | no guard of `src/` declines here, but an expiry leaves the parse behind, and any declining guard above, a caller's, rewinds | **fixed**, the same section |
| `transfer.sls:3842`, `check-proxy-url`'s guard (was `curl-url-error?` at `:3795`) | `proxy-url-reading`'s `call-with-flagged-url` | a direct caller's `curl-submit` and `curl-request-check`; the high level's submits and checks run in sections already | **on** for a direct caller | the review's m1: 375 of 3,000 timer, 579 engine | **fixed**: a short section, its guard `#t` (`in-section`, `transfer.sls:3736`) |
| `transfer.sls:3703`, `request-checks`' URL parse, no guard | `call-with-parsed-url` | the same | **on** for a direct caller | an expiry leaves it behind (m1's 204 engine re-entries from `call-with-parsed-url`); a caller's declining guard rewinds | **fixed**: the same short section |
| `url.sls:133`, `decoded`'s `i/o-decoding-error?` | `bytevector->string` alone, inside `get-part`'s body | every URL part read | as its caller's | no wind between it and a raise: a declined raise rewinds into nothing here, and goes on to the guards above, the sites above | no change |
| `call.sls:147`, `string-pairs`' `assertion-violation?` | `length` alone | call-state (in its section), and `make-http-session`'s `session-defaults` (interrupts on) | on in `make-http-session` | no wind; but a handler's `&assertion` raised inside `length` is read as "not a list", and dropped | no change: no wind; noted below |
| `call.sls:416`, `list-within`'s `assertion-violation?` | `length` alone | `make-http-retry` | on | as `string-pairs`', read as not-a-status-list or not-a-method-list | no change; noted below |
| `drive.sls:287`, `interrupts-on?`'s `take-refusal?` | `curl-mailbox-take` of 0 ms: its only winds are `locked`'s, inside a section | every drive's start, a group's entries | on | no wind is entered with interrupts on, so a declined raise rewinds into nothing | no change |
| `drive.sls:404`, `:1014`, `:1255`, the submits' `curl-error?` | `curl-submit`'s checks and enqueue | each submit | **off**: inside the submit's section | only the submit's own non-`&curl-error` raises; none is raised inside a parse wind, by reading | no change |
| `#t` guards: `http-client.sls:618` (call-state), `drive.sls:371` (`in-step-section`), `:1355` (`guarded!`), `call.sls:525`, `url.sls:229`, `transfer.sls:2398`, `:2655`, `:3011`, `:3094`, `:3468`, `:3502`, `:3543`, `:3738` (`in-section`), `:4259`, `native.sls:209`, `:220`, `:556`, `:653`, `load-state.sls:66`, and every guard of `engine.sls` | | | | decline nothing | no change |

Beyond `src/`'s own guards: the public URL functions (`curl-url-part`, `curl-url-resolve` and the
rest) enter the refusing winds with their caller's interrupts. Their contract says so ("re-entering
a finished call through a continuation raises", `url.sls`'s header): an engine's expiry there,
or a declining guard of the caller's around a handler's raise there, meets that refusal. That is
the caller's, and documented; recorded here, not changed.

### Item 2: the step's hold, at the largest inputs each libcurl takes

[`probe/step-hold.sps`](probe/step-hold.sps), against a stand-in
([`probe/step-server.mjs`](probe/step-server.mjs)) that answers a 302 with a Location of N
bytes and H more headers to a target of any length: bisects the largest of each the libcurl takes,
then times `exchange-step` (and `exchange-steps-past?`), 3 times, on the pre-fix code, where the
fix's section wraps exactly that call.

| libcurl | largest Location | most headers | longest URL sent | step at all three together |
|---|---|---|---|---|
| 7.85.0 ([`results/lane-floor-step-hold.log`](results/lane-floor-step-hold.log)) | 102,387 bytes | 100,003, uncapped (each such transfer took 49 s) | 1,048,544 chars | 168 to 180 ms |
| 8.5.0 OpenSSL ([`results/lane-openssl-step-hold-trace.log`](results/lane-openssl-step-hold-trace.log)) | 102,387 | 22,733 | 131,041; a longer request stalled to its 120 s timeout, 28 | Location alone 14 to 17 ms; URL alone 11 to 12 ms; the Location with the headers refused, 56 |
| 8.5.0 GnuTLS ([`results/lane-gnutls-step-hold-trace.log`](results/lane-gnutls-step-hold-trace.log)) | 102,387 | 22,733 | 131,041, the same stall past it | Location alone 14 to 17 ms; URL alone 11 to 12 ms; the Location with the headers refused, 56 |
| 8.20.0 ([`fix/step-hold-max-guix.log`](fix/step-hold-max-guix.log)) | 102,387 | 5,000 | 1,048,544 | 124 to 139 ms |
| 8.23.0 ([`results/lane-current-step-hold.log`](results/lane-current-step-hold.log)) | 102,387 | 5,000 | 1,048,544 | 157 to 181 ms |

Headers alone cost a step under 0.5 ms on every lane, 100,003 of them on 7.85.0 included. **No
reachable step holds past 1 s**: the most is 181 ms, so the fix went ahead. (8.5.0's stall of a
request past about 131 KB is libcurl's or the stand-in's; it ended at its timeout, and is not this
question's.)

### The fixes

1. **The steps** (`drive.sls`): `section-step`, `sectioned-step` and `section-steps-past?` run
   `exchange-step` and `exchange-steps-past?` in `in-step-section` (`:369`), a critical section
   whose guard takes every raise `#t` as data, raised once it has ended: drive-exchange's one step,
   and drive-stream's seven and its `exchange-steps-past?`. A group's step was in `turn!`'s section already. A test seam, the step
   gate (`drive-step-gate-set!`), marks start and end inside the section, a group's step too.
2. **The submit** (`transfer.sls`): `in-section` (`:3736`) runs `check-proxy-url`'s reading,
   its guard now `#t` (a `&curl-url-error` read as `#f` inside it), and `request-checks`' URL parse,
   each in a short section; the parse gate (`transfer-parse-gate-set!`, exported by
   `(curl private transfer)` alone) marks each section's start.
3. **The cap** (M2): `url.sls`'s `checked-input` refuses a string of more than 8,000,000 chars at
   once, `refuse-code` with libcurl's own `malformed-input`, before any copy; call-state calls
   `curl-url-part` on such a URL right after `check-session`, inside its section, so it is refused
   first. Measured first on the five lanes, pre-fix ([`fix/url-cap-guix.log`](fix/url-cap-guix.log),
   `results/lane-*-url-cap.log`): 8,000,001 chars gave `&curl-url-error` `malformed-input`, code 3,
   "Malformed input to a URL function", who `chez-curl`, irritants `(url)`, the input the URL, with
   `(get URL () 0)` as its `&http-exchange`, alike on all five and at every entry, in 170 to 180 ms;
   8,000,000 gave libcurl's `out-of-memory`, code 7, after the parse, 186 to 291 ms. The fix gives
   the same 8,000,001 refusal in 0.01 to 0.04 ms ([`fix/hold-rates.log`](fix/hold-rates.log)), and
   leaves 8,000,000 to libcurl. A URL past the cap that holds U+0000 is now refused as
   `malformed-input`, where before it was `embedded-nul`.
4. **The holds documented** (`http-client.sls`'s header), each as a rate from
   [`fix/hold-rates.log`](fix/hold-rates.log), every hold the largest of the checks' time, the
   collector's stall and a SIGINT's wait:

| input | sizes | hold | rate |
|---|---|---|---|
| bytevector body | 64, 256 MiB | 28 to 33, 106 to 119 ms | 0.4 to 0.5 ms a MiB |
| string body | 16, 64 Mi chars | 35 to 38, 137 to 170 ms | 2 to 2.7 ms a Mi chars |
| form value | 4, 16, 32 Mi chars | 126 to 127, 645 to 735, 1,325 to 1,492 ms | 31 to 47 ms a Mi chars (52 in the build's run) |
| headers | 25,000, 100,000 | 10 to 11, 45 to 46 ms | 0.4 to 0.5 ms a thousand |
| params | 25,000, 100,000 pairs | 15 to 16, 67 to 72 ms | 0.6 to 0.7 ms a thousand |
| URL | 1, 4, 7.9 M chars | 28 to 30, 115 to 118, 226 to 230 ms | 29 ms a million chars, to the cap |
| URL past the cap | 8,000,001, 64 M chars | 0.01 to 0.04 ms | refused at once |

   The header now says each grows with its input with no bound but the input's, and that once a
   collection falls due during a hold every thread stops at its next event check, the engine's
   thread and its transfers among them.

### The tests, each watched failing

The suite `tests/test-call-checks.sps` grows from 22 to 49 tests, 49 of 49 on the fixed tree
([`fix/call-checks-fix-4.log`](fix/call-checks-fix-4.log), after its last change). Each mutant is a copy of the fixed
tree with one change ([`probe/fix_mutants.py`](probe/fix_mutants.py), run by
[`probe/run-fix-mutants.sh`](probe/run-fix-mutants.sh); each `fix/mutant-NAME.log`, each suite's
log under `fix/mutants/`):

| test | what it proves | fails under |
|---|---|---|
| 4 SIGINT children at the first step's start, the planted `&curl-error` raised (request, port, go, parallel) | the raise comes as the step's section ends, after its end mark; one transfer | step-pre and step-section-late (the handler ran before the step's end) |
| 4 SIGINT children at the first step's start, a continuable `&warning` | the call resumes, follows the redirect, answers 200 | step-pre, step-section-late, **step-guard-outside** (`&non-continuable`) |
| 4 timers at the first step's start | the timer fires after the step | step-pre, step-section-late |
| 3 engine sweeps across the first step, a tick at a time (request, port, go) | no expiry inside a step, no re-entry refusal; evidence the sweep crossed it | step-pre (380 and 421 fuels inside, 66 and 76 re-entries), step-section-late |
| 3 timer sweeps, 1 to 300 ticks past the step's start, a continuable `'tick` | every call resumes and answers 200 | step-pre (47 and 48 re-entries), step-section-late, step-guard-outside (port, 3 `&non-continuable`) |
| a raise inside the step, through the gate | it leaves with interrupts on in the caller's handler | **step-raise-inside** |
| go's and parallel's step rows | a group's step, in `turn!`'s section before the fix | pass under every step mutant, as they should; fail under group-step-outside, 8 rows (below) |
| an engine sweep across a direct `curl-submit` through a proxy URL | no re-entry refusal | submit-pre (593 re-entries), submit-section-late |
| a timer sweep, 1 to 3,000 ticks, across that submit | no re-entry refusal | submit-pre (389) |
| 2 SIGINT children at the proxy URL's parse | a raise leaves as raised; a continuable one resumes and the submit answers its token | submit-pre, submit-section-late, **submit-guard-outside** |
| a direct `curl-submit` of an ftp URL | its refusal reaches the caller's handler with interrupts on | **submit-raise-inside** |
| an 8,000,001-char URL at each entry | refused at the checks' start, as libcurl refuses it, every field | noseam (marks) |
| the cap comes first, 8,000,000 left to the order | over the cap before the keys, at the cap after them | cap-pre, cap-late, cap-off-by-one |
| refused under a tenth of an 8,000,000-char URL's time | no copy or parse first | cap-pre, cap-off-by-one, cap-copying |
| the checks sweeps' evidence (m4) | the crossing fuel's marks are `(start end)` | **noseam** (the review's mut-noseam), with every SIGINT and timer test |
| test-origin-tls's stopped request (m3) | the STOP returned under 2,000 ms after the connect | stop-late (2,300 ms), h2c and h2 |
| test-transfer's two flip tests, a refusal now sleeping 1 ms | never the CR sent, both answers seen | flip-no-cr, `value-fault` taking CR as a value's: both fail, the CR sent ([`fix/mutant-flip-no-cr.log`](fix/mutant-flip-no-cr.log)) |

**The flip tests, under the memory gate.** test-transfer's user agent and header value flip tests,
which a thread flips between `c` and CR across 300 transfers and which need both a refusal and a
whole send seen, saw only refusals in 5 of 22 runs of the gate on the fixed tree before the yield:
rounds F and H of the first ten (`fix/lane-openssl-memory-F-1.log`, `-H-1.log`) and 3 of 12 in
a comparison run beside 12 of the pre-fix copy, all 12 of which passed (`fix/flip-fix*.out`,
`fix/flip-base*.out`, each run's log `fix/lane-openssl-flip-*.log`). The fix moved the submit's URL
parse into a section of its own. The reading, not measured further: a refusal comes before
anything waits, so under Valgrind, which runs one thread at a time, the loop can run on through
one of the flipper's CR states, its 1,000,000 flips between pauses of no time. Each test now
sleeps 1 ms after a refusal, so the flipper moves on: 16 of 16 runs of the gate passed
(`fix/flip-yield*.out`), 225 of 225 natively
([`fix/test-transfer-yield.log`](fix/test-transfer-yield.log)), and both tests still fail under
flip-no-cr.

### The minors

- **m2:** test-origin-tls's comment cites the kept logs: h2 lost the frame 10 of 10 in the races'
  forced loop (`../races/results/loop/stop0-main.log`), h2c 0 of 10, and mutant o0 failed the test
  in each of its three kept runs.
- **m3:** `stopped-probe` answers when `kill -STOP` returned, after the connect by the probe's
  clock; the test asserts it under 2,000 ms, the probe's send.
- **m4:** the sweeps' evidence requires `(start end)` at the crossing fuel.
- **m6:** go's export comment: a raise that leaves starts no call; a continuable one returned from
  resumes go, which then starts it.
- **m7:** test-group's recheck test, "in or just after its checks", name and comment.
- **m8:** `h2EndNext`'s comment names the writes chained on drains a half-close can still cut.

### The review's probes, rerun on the fixed tree

[`fix/review-probes-fixed.log`](fix/review-probes-fixed.log), the review's own probes unchanged:

| probe | before (the review's logs) | fixed |
|---|---|---|
| `redirect-step.sps engine 1 8000 1` | 1,498 re-entry refusals | 0: 6,481 answered, 1,519 the await's documented cancel |
| `redirect-step.sps timer 1 8000 1` | 679 | 0: 8,000 answered |
| `submit-proxy.sps engine 1 3000 1` | 579 | 0: 3,000 submitted |
| `submit-proxy.sps timer 1 3000 1` | 375 | 0: 3,000 submitted |
| `long-url-hold.sps`, Ctrl-C at the checks' start, 8 to 64 M chars | 114 to 891 ms | 0.04 ms, each refused `malformed-input` |

The call's copy of its URL, `string-copy` before the checks' section, still holds Ctrl-C as any
primitive copy does, as before the branch: the call's whole time to the refusal grew from 23 ms
at 8 M chars to 162 ms at 64 M. Skipping that copy for a URL past the cap would leave the
refusal's input the caller's own string.

### The checks

Every final check ran on the working tree as handed back, or on `build/carried-guard/fix/`, its
rsync'd copy (`diff -r` clean against `src/` and `tests/` at each run's start).

- **`make test` in the Guix container**, from the working tree itself, CPUs 10 to 13: 41 of 41,
  `check-seam` 21 libraries in 21 files, `check-suites` 41
  ([`fix/make-test-guix-final.log`](fix/make-test-guix-final.log)); after test-call-checks'
  last change, that suite 49 of 49 ([`fix/call-checks-fix-4.log`](fix/call-checks-fix-4.log)),
  and then `make test` whole again from the working tree, CPUs 0 to 7: 41 of 41, `check-seam` 21,
  `check-suites` 41 ([`fix/make-test-guix-final-2.log`](fix/make-test-guix-final-2.log)). Earlier runs: the first failed test-transfer's order test
  ([`fix/make-test-guix.log`](fix/make-test-guix.log)): it counted the submit's CURLU live where
  its refusal was raised, inside the parse; the refusal now comes once the parse's section has
  ended, the CURLU freed. Its expected value and name now say so, and it fails under submit-pre
  ([`fix/mutant-submit-pre-transfer.log`](fix/mutant-submit-pre-transfer.log)).
- **The four Docker lanes, `make test` whole** ([`fix/lanes-final.out`](fix/lanes-final.out),
  `fix/lane-*-final-lanes.log`): floor 7.85.0, GnuTLS 8.5.0 and 8.23.0 41 of 41; OpenSSL 8.5.0
  40 of 41, test-call-checks' parallel step raise row starting 2 transfers where it expected 1.
  That row was the test's error, not the fix's: see "A group's next hop" below. After the
  change, OpenSSL's lane again, `make test` whole: 41 of 41
  ([`fix/lanes-final-2.out`](fix/lanes-final-2.out), `fix/lane-openssl-final-lanes-2.log`).
- **The memory gate on Ubuntu's 8.5.0** (OpenSSL), test-call-checks, test-group, test-origin-tls,
  test-transfer and test-redirect: five containers at once, each pinned to two CPUs of its own
  (0-1 to 8-9), five rounds each, 25 rounds, **every one passing**
  (`fix/memory-final-N.out`, each round's log `fix/lane-openssl-final-N-R.log`, Valgrind's
  under `fix/memory-openssl-final-N-R/`). test-call-checks' last change only widens two rows
  (1 is one of one-or-two), so every pass there passes it; it ran again under the gate alone,
  four containers, two rounds each: 8 of 8 passing (`fix/memory-final-cc-N.out`,
  `fix/lane-openssl-final-cc-N-R.log`).
- **Earlier gate rounds, kept as found.** Ten single rounds on the fixed tree before the last
  test changes (`fix/memory-A.out` to `-J.out`): C and E failed the evidence of a step engine
  sweep, go's in C and request's in E, `(#t #t #f)` (`fix/lane-openssl-memory-C-1.log`, `-E-1.log`);
  every step sweep's window has since been widened to 200 fuels past the crossing, its coarse
  rows counted; F and H failed test-transfer's flip tests (above); and E failed
  test-origin-tls's TLS stop test, its "idle after a whole keep-alive response" probes on the
  https and https-expired faces missing at the stop, 74 and 73 of 76
  (`fix/lane-openssl-memory-E-1.log`). That test and the origin are unchanged by this round; the
  origin's https faces set no `keepAliveTimeout`, so Node's default 5 s ends an idle keep-alive
  connection, and the test is built to fail when an idle timer ends a probe before the stop. The
  reading, not measured further: under that load the probes' set-up passed 5 s. It did not recur
  in the 25 final rounds.

### A group's next hop, started before the cancel

test-call-checks' SIGINT raise row at a redirect's step asserted 1 transfer started at every
entry. A group, go's and parallel's, submits the next hop inside `step-token!`'s section, before
the handler runs, and the raise's cancel then meets that queued token: the engine's thread can
start it first. With the child's Ctrl-C handler made to sleep 100 ms before its raise (the
handler-sleep variant, built into a tally copy), go and parallel started 2 transfers in 10 of 10
runs each, request and port 1 in 10 of 10
([`fix/step-raise-tally-handler-sleep.log`](fix/step-raise-tally-handler-sleep.log)). Without the
sleep, every run started 1: 40 of each entry in the Guix container
([`fix/step-raise-tally-4cpu.log`](fix/step-raise-tally-4cpu.log)), and on the OpenSSL lane 40
each of request, port and go and 60 of parallel (`fix/step-raise-tally-docker-*.out`; the first
lane run, 40 of each, reached its 300 s bound before parallel's, so parallel's ran alone,
`fix/step-raise-tally-docker.out`, `-2.out`). The tally copy's change to the suite is
[`fix/step-raise-tally.patch`](fix/step-raise-tally.patch), its count set per run. So a
group's row now reads 1 or 2 as `one-or-two`; a single call's, which submits after its step's
section has ended, stays 1. The changed suite passes 49 of 49 with the handler-sleep variant
([`fix/mutant-handler-sleep.log`](fix/mutant-handler-sleep.log)), and a mutant that steps a group's
done token outside a critical section, group-step-outside, fails 8 group rows, both raise rows
among them, marks `(start)` ([`fix/mutant-group-step-outside.log`](fix/mutant-group-step-outside.log)).
This was not the fix's doing: a group's step ran in `turn!`'s section before this round; the row
is new.
