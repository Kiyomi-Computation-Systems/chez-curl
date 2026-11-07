# M8 slice 2, measured before it is built: the header cap through the engine

Measured 2026-11-06, the M8 plan's §5 "First, measure", for the cap ADR-0040 decided: every
transfer's response headers capped at 1,000 header lines and 102,400 bytes over the whole
transfer, refused by the header callable as `header-limit`, of `&curl-too-large`. A prototype of
the plan's §3.3 ran through the engine on the five Linux lanes, two runs each. This reports what
it answered, the origin's HTTP/2 faces with Node's limits raised, and `make test` on the
prototype. It recommends only on `SUPPRESS_CONNECT_HEADERS`, as the brief asks. Every number is
from a kept log under `results/`, by its path; the tables are `tables.py`'s output over those
logs, pasted.

## In short

- **The prototype** ([`proto.patch`](proto.patch), 131 lines, made by `make-proto.py`): the header
  callable on every transfer; its counts span the transfer; past 1,000 header lines or 102,400
  bytes it records `header-limit` and answers 0; once any reason is recorded it answers 0 to every
  later call; `header-limit` is raised as `&curl-too-large`; and the origin's two HTTP/2 faces with
  `maxSendHeaderBlockLength` raised. The probe's tree adds a seam, [`seam.patch`](seam.patch), a log
  of what the callable was handed; `make test` never ran it.
- **The edges hold alike on all five lanes, buffered and streamed, over HTTP/1.1 and HTTP/2:**
  1,000 header lines taken, the 1,001st refused; 102,400 bytes taken, 102,401 refused, the counts
  over HTTP/1.1 equal to the bytes the stand-in wrote (`results/probe-docker-{1,2}.log`,
  `results/probe-guix-8.20.0-{1,2}.log`).
  A refused stream publishes no head when the refusal falls in the final head, and its port raises
  `header-limit`.
- **Every kind of head counts toward the cap across the transfer, on all five lanes,** as decision
  1 says: a 100 and a 103 head, HTTP/1.1 chunked trailers and HTTP/2 trailers, a Digest 401 round,
  a 417, its `100 Continue` and its resend, and a `CONNECT` answer over HTTP/1.1 and HTTP/2: 1,000
  lines in all taken and 1,001 refused, each head alone under the cap; bytes the same.
- **8.5.0's lost HTTP/2 trailer refusal now fails the transfer `header-limit`,** on both builds, in
  both runs, buffered and streamed, but with **code 0**: libcurl still ends the transfer 0, and the
  recorded reason wins. Every other refusal of the cap's on these lanes is 23.
- **libcurl's early refusals** (the plan's §3.8) answer as the caps probe found, with one
  correction: through the cap, nghttp2's limit on a head is reached on 7.85.0 and 8.5.0 alone (56);
  on 8.20.0 and 8.23.0 the lines arrive first and the cap refuses, 23.
- **`SUPPRESS_CONNECT_HEADERS`, which the hatch takes today, takes a `CONNECT` answer out of the
  cap on every lane,** and nothing in chez-curl's surface shows that answer, set or not.
  With it, 8.20.0 and 8.23.0 still count the hidden lines toward their 5,000 (100), 8.5.0 its bytes
  toward its 307,200 (56), and 7.85.0 took a hidden answer of 960,039 bytes. **Recommendation:
  make it a twin of the header callable's**, refused as `owned-option`. Of the other options that
  change what the callable sees, the hatch takes `HTTP_TRANSFER_DECODING`, `HTTP200ALIASES`,
  `HTTP09_ALLOWED` and `FAILONERROR` today; it refuses the rest as owned, or as a callback's type.
- **The cost of the buffered transfer's new callable, 1,000 lines on 7.85.0:** natively 0.51 to
  0.64 µs a call by libcurl's own total, 0.40 to 1.25 µs by process CPU; under the memory gate's
  Valgrind 21.4 to 24.4 µs a call by libcurl's total, 18.5 to 21.5 by process CPU, about 21 to 25
  ms more for a 1,000-line response; and a cost per transfer besides, about 0.05 ms natively and
  0.5 ms under Valgrind.
- **The origin's HTTP/2 faces need one of the caps stand-in's three limits, the send limit,**
  `maxSendHeaderBlockLength`. With all three, as the stand-in has them, `test-origin` (2 tests) and
  `test-origin-tls` (82) fail on all five lanes: `SETTINGS_MAX_HEADER_LIST_SIZE` puts a setting in
  the SETTINGS frame each face sends first, and those tests hold its bytes. With the send limit
  alone every HTTP/2 suite passes on all five lanes, and every cell of the probe answers as with all
  three. Node's default, 64 KiB, cannot send the cap's large heads at all.
- **`make test` on the prototype** fails exactly the two cases the plan names, in `test-transfer`,
  and one test the plan's §3.7 implies but does not count: `test-conditions`' written-out
  reasons, which now end in `header-limit`. Lanes and detail [below](#item-4-make-test-on-the-prototype).
- **One trap, reproduced:** with Node's default send limit, Node 24.18.0's HTTP/2 server drops a
  trailer block it cannot send and closes the stream with code 0, so libcurl reads a whole 200 with
  no trailers; Node 20.10.0 resets the stream instead. A test of large HTTP/2 trailers that does not
  assert they arrived passes without the raise on Node 24.

## What was run

### The prototype, and the probe's seam

`make-proto.py` edits a copy of the tree made by `tar --exclude=./build --exclude=./.git
--exclude=./.plans/research` from this branch (main 9fdb9f3; `src`, `tests` and the Makefile
unchanged from it). The trees lived in `build/m8s2/work.zJZXLW/` (`mktemp -d`):

| tree | what | made by |
|---|---|---|
| `main` | the copy, unchanged | tar |
| `proto` | the prototype: the cap, and the send limit on both HTTP/2 faces | `make-proto.py proto` ([`proto.patch`](proto.patch)) |
| `probe` | the prototype and the seam, for `engine-probe.sps` alone | `make-proto.py probe --seam` ([`seam.patch`](seam.patch), against `proto`) |
| `origin` | `main` with the caps stand-in's three HTTP/2 limits, nothing else | `make-proto.py origin --origin-only --caps-limits` |
| `origin-send` | `main` with the send limit alone | `make-proto.py origin-send --origin-only` |

The cap, in `transfer.sls`: the sink gains three fields, the transfer's header lines, its bytes,
and whether the next line starts a head. `count-header-line!` adds every byte handed, and counts a
line as a header line unless it is a head's empty line (`"\r\n"` or `"\n"`) or, at a head's start,
a status line, one starting `HTTP/`; `read-head` answers 0 once any reason is recorded, then
records `header-limit` and answers 0 when a count passes 1,000 or 102,400, then does what it did.
`set-transfer-options!` sets `HEADERFUNCTION` and `HEADERDATA` on every transfer. In
`conditions.sls`, `header-limit` joins the reasons, and `check-class` and
`make-classed-transfer-error` give it `&curl-too-large` as they give `body-limit`. The constants
are `header-line-cap` and `header-byte-cap`. Nothing else moved: `stream-buffer` still owns the two
options in the field table, and no comment but the new ones was rewritten.

The seam (`--seam`) logs, per transfer as `finish-transfer` reads it, the callable's calls, its two
counts, each head as `status:lines:bytes` (`T` a section no status line opened, a trailer section),
and the calls it refused because a reason was recorded already; `take-header-tallies!` reads it.

### The probe, its stand-in and the lanes

`engine-probe.sps` runs each cell as a GET (a POST for the 417) on an engine of its own, made for
the cell and stopped after it, through `(curl)`, `(curl unsupported)` for the hatch, and the
seam: buffered, and streamed (`stream-buffer` 65536), its body read through the token's port. The
stand-in is the caps probe's [`server.mjs`](../caps/server.mjs), unchanged, its spec queries
as its header says; `server-limits.mjs` is a copy whose h2 face takes its limits from
`H2_LIMITS`. `run-probe.sh` makes the run's PKI, starts the stand-in and runs a program;
`lanes.sh` and `lanes-in-docker.sh` run it, or `make test`, in Docker.

| lane | libcurl | Node for the probe | Node for `make test` | how |
|---|---|---|---|---|
| F, floor | `build/e1/ci/curl-floor`, 7.85.0, OpenSSL 3.0.13 | 20.10.0 | 20.10.0 | Docker `ubuntu:24.04`, `--network none`, spike E1's threaded Chez 10.4.0 |
| O, openssl | Ubuntu's `libcurl.so.4`, 8.5.0-2ubuntu10.16 | 24.18.0 (the Guix store's) | 20.10.0 | the same |
| G, gnutls | Ubuntu's `libcurl-gnutls.so.4`, 8.5.0-2ubuntu10.16 | 24.18.0 | 20.10.0 | the same |
| X, Guix | the profile's 8.20.0, GnuTLS 3.8.13 | 24.18.0 | 24.18.0 | `scripts/guix-env`, `taskset -c 12-17` |
| C, current | `build/verify/c823/lane1/curl-current`, 8.23.0 | 24.18.0 | 20.10.0 | Docker |

Node for the probe is as the caps probe ran each lane; for `make test`, as M7 slice 4's
`lanes-in-docker.sh` did. The packages, `packaging/debian-prereqs.txt`'s, were fetched once into
`build/m8s2/apt` by a container that did nothing else; every other container ran `--network none`
(`network interfaces: lo` in each Docker log) on CPUs 6 to 11 or 12 to 17. The probe ran twice
on each lane; `tables.py` compares the runs:

*Cells the runs split (outcome, tally or stream; times set aside)*

None: 965 cells and hatch lines in run 1, 965 in run 2, every one alike.

## Item 2: through the engine

*Edges, run 1: the outcome (a status and its headers, or a code and reason); what the callable counted, lines/bytes [status:lines:bytes per head]; for a stream, what it published*

| cell | face | opts | way | answer |
|---|---|---|---|---|
| n1000 | h1 | - | buffered | all five: 200 (1000 headers); 1000/16022 [200:1000:16022] |
| n1000 | h1 | - | streamed | all five: 200 (1000 headers); 1000/16022 [200:1000:16022]; head 200/1000, port eof |
| n1001 | h1 | - | buffered | all five: 23 header-limit; 1001/16036 [200:1001:16036] |
| n1001 | h1 | - | streamed | all five: 23 header-limit; 1001/16036 [200:1001:16036]; no head, port 23 header-limit |
| total102400 | h1 | - | buffered | all five: 200 (401 headers); 401/102400 [200:401:102400] |
| total102400 | h1 | - | streamed | all five: 200 (401 headers); 401/102400 [200:401:102400]; head 200/401, port eof |
| total102401 | h1 | - | buffered | all five: 23 header-limit; 401/102401 [200:401:102401] |
| total102401 | h1 | - | streamed | all five: 23 header-limit; 401/102401 [200:401:102401]; no head, port 23 header-limit |
| line102362 | h1 | - | buffered | all five: 200 (2 headers); 2/102400 [200:2:102400] |
| line102362 | h1 | - | streamed | all five: 200 (2 headers); 2/102400 [200:2:102400]; head 200/2, port eof |
| line102363 | h1 | - | buffered | all five: 23 header-limit; 2/102401 [200:2:102401] |
| line102363 | h1 | - | streamed | all five: 23 header-limit; 2/102401 [200:2:102401]; no head, port 23 header-limit |
| n1000 | h2 | - | buffered | all five: 200 (1000 headers); 1000/16018 [200:1000:16018] |
| n1000 | h2 | - | streamed | all five: 200 (1000 headers); 1000/16018 [200:1000:16018]; head 200/1000, port eof |
| n1001 | h2 | - | buffered | all five: 23 header-limit; 1001/16032 [200:1001:16032] |
| n1001 | h2 | - | streamed | all five: 23 header-limit; 1001/16032 [200:1001:16032]; no head, port 23 header-limit |
| total102400 | h2 | - | buffered | all five: 200 (401 headers); 401/102400 [200:401:102400] |
| total102400 | h2 | - | streamed | all five: 200 (401 headers); 401/102400 [200:401:102400]; head 200/401, port eof |
| total102401 | h2 | - | buffered | all five: 23 header-limit; 401/102401 [200:401:102401] |
| total102401 | h2 | - | streamed | all five: 23 header-limit; 401/102401 [200:401:102401]; no head, port 23 header-limit |
| line102366 | h2 | - | buffered | all five: 200 (2 headers); 2/102400 [200:2:102400] |
| line102366 | h2 | - | streamed | all five: 200 (2 headers); 2/102400 [200:2:102400]; head 200/2, port eof |
| line102367 | h2 | - | buffered | all five: 23 header-limit; 2/102401 [200:2:102401] |
| line102367 | h2 | - | streamed | all five: 23 header-limit; 2/102401 [200:2:102401]; no head, port 23 header-limit |

- Over HTTP/1.1 the status line is the stand-in's 17 bytes; over HTTP/2, libcurl's rendering,
  `HTTP/2 200 \r\n`, 13. The longest single line the cap takes is 102,362 bytes after
  `content-length: 0` over HTTP/1.1 and 102,366 over HTTP/2.
- `total102401` is refused at the head's own empty line, the call that takes the bytes from
  102,399 to 102,401 (`passed 2 returned 0` in the error buffer), so a stream publishes no head.
- The error buffer holds `Failed writing header` on 7.85.0 and 8.5.0 and `Failure writing output
  to destination, passed N returned 0` on 8.20.0 and 8.23.0; the code is 23 on every lane.

*What counts toward the cap across a transfer, run 1*

| cell | face | opts | way | answer |
|---|---|---|---|---|
| pre103-500+500 | h1 | - | buffered | all five: 200 (500 headers); 1000/16050 [103:500:8028,200:500:8022] |
| pre103-500+500 | h1 | - | streamed | all five: 200 (500 headers); 1000/16050 [103:500:8028,200:500:8022]; head 200/500, port eof |
| pre103-500+501 | h1 | - | buffered | all five: 23 header-limit; 1001/16064 [103:500:8028,200:501:8036] |
| pre103-500+501 | h1 | - | streamed | all five: 23 header-limit; 1001/16064 [103:500:8028,200:501:8036]; no head, port 23 header-limit |
| pre100-500+501 | h1 | - | buffered | all five: 23 header-limit; 1001/16061 [100:500:8025,200:501:8036] |
| pre100-500+501 | h1 | - | streamed | all five: 23 header-limit; 1001/16061 [100:500:8025,200:501:8036]; no head, port 23 header-limit |
| pre103-250x256+250x256 | h1 | - | buffered | all five: 23 header-limit; 401/102464 [103:250:64028,200:151:38436] |
| pre103-250x256+250x256 | h1 | - | streamed | all five: 23 header-limit; 401/102464 [103:250:64028,200:151:38436]; no head, port 23 header-limit |
| tr-2+998 | h1 | - | buffered | all five: 200 (2 headers); 1000/16031 [200:2:63,T:998:15968] |
| tr-2+998 | h1 | - | streamed | all five: 200 (2 headers); 1000/16031 [200:2:63,T:998:15968]; head 200/2, port eof |
| tr-2+999 | h1 | - | buffered | all five: 23 header-limit; 1001/16047 [200:2:63,T:999:15984] |
| tr-2+999 | h1 | - | streamed | all five: 23 header-limit; 1001/16047 [200:2:63,T:999:15984]; head 200/2, port 23 header-limit |
| tr-2+400x256 | h1 | - | buffered | all five: 23 header-limit; 402/102463 [200:2:63,T:400:102400] |
| tr-2+400x256 | h1 | - | streamed | all five: 23 header-limit; 402/102463 [200:2:63,T:400:102400]; head 200/2, port 23 header-limit |
| auth-499+500 | h1 | - | buffered | all five: 200 (500 headers); 1000/16130 [401:500:8108,200:500:8022] |
| auth-499+501 | h1 | - | buffered | all five: 23 header-limit; 1001/16144 [401:500:8108,200:501:8036] |
| auth-250x256+250x256 | h1 | - | buffered | all five: 23 header-limit; 403/102576 [401:251:63884,200:152:38692] |
| pre103-500+500 | h2 | - | buffered | all five: 200 (500 headers); 1000/16033 [103:500:8015,200:500:8018] |
| pre103-500+500 | h2 | - | streamed | all five: 200 (500 headers); 1000/16033 [103:500:8015,200:500:8018]; head 200/500, port eof |
| pre103-500+501 | h2 | - | buffered | all five: 23 header-limit; 1001/16047 [103:500:8015,200:501:8032] |
| pre103-500+501 | h2 | - | streamed | all five: 23 header-limit; 1001/16047 [103:500:8015,200:501:8032]; no head, port 23 header-limit |
| pre100-500+501 | h2 | - | buffered | all five: 23 header-limit; 1001/16047 [100:500:8015,200:501:8032] |
| pre100-500+501 | h2 | - | streamed | all five: 23 header-limit; 1001/16047 [100:500:8015,200:501:8032]; no head, port 23 header-limit |
| pre103-250x256+250x256 | h2 | - | buffered | all five: 23 header-limit; 401/102447 [103:250:64015,200:151:38432] |
| pre103-250x256+250x256 | h2 | - | streamed | all five: 23 header-limit; 401/102447 [103:250:64015,200:151:38432]; no head, port 23 header-limit |
| tr-2+998 | h2 | - | buffered | **7.85.0**: 200 (1000 headers); 1000/16015 [200:2:47,T:998:15968]; **8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.20.0, 8.23.0**: 200 (2 headers); 1000/16015 [200:2:47,T:998:15968] |
| tr-2+998 | h2 | - | streamed | **7.85.0**: 200 (1000 headers); 1000/16015 [200:2:47,T:998:15968]; head 200/2, port eof; **8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.20.0, 8.23.0**: 200 (2 headers); 1000/16015 [200:2:47,T:998:15968]; head 200/2, port eof |
| tr-2+999 | h2 | - | buffered | **7.85.0, 8.20.0, 8.23.0**: 23 header-limit; 1001/16031 [200:2:47,T:999:15984]; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 0 header-limit; 1001/16031 [200:2:47,T:999:15984] |
| tr-2+999 | h2 | - | streamed | **7.85.0, 8.20.0, 8.23.0**: 23 header-limit; 1001/16031 [200:2:47,T:999:15984]; head 200/2, port 23 header-limit; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 0 header-limit; 1001/16031 [200:2:47,T:999:15984]; head 200/2, port 0 header-limit |
| tr-2+400x256 | h2 | - | buffered | **7.85.0, 8.20.0, 8.23.0**: 23 header-limit; 402/102447 [200:2:47,T:400:102400]; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 0 header-limit; 402/102447 [200:2:47,T:400:102400] |
| tr-2+400x256 | h2 | - | streamed | **7.85.0, 8.20.0, 8.23.0**: 23 header-limit; 402/102447 [200:2:47,T:400:102400]; head 200/2, port 23 header-limit; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 0 header-limit; 402/102447 [200:2:47,T:400:102400]; head 200/2, port 0 header-limit |
| auth-499+500 | h2 | - | buffered | all five: 200 (500 headers); 1000/16112 [401:500:8094,200:500:8018] |
| auth-499+501 | h2 | - | buffered | all five: 23 header-limit; 1001/16126 [401:500:8094,200:501:8032] |
| auth-250x256+250x256 | h2 | - | buffered | all five: 23 header-limit; 403/102558 [401:251:63870,200:152:38688] |
| expect-500+500 | h1 | - | buffered | all five: 200 (500 headers); 1000/16085 [417:500:8038,100:0:25,200:500:8022] |
| expect-500+501 | h1 | - | buffered | all five: 23 header-limit; 1001/16099 [417:500:8038,100:0:25,200:501:8036] |
| expect-250x256+250x256 | h1 | - | buffered | all five: 23 header-limit; 402/102515 [417:250:63798,100:0:25,200:152:38692] |
| connect-500+500 | h1tls+proxy | - | buffered | all five: 200 (500 headers); 1000/16061 [200:500:8039,200:500:8022] |
| connect-500+500 | h1tls+proxy | - | streamed | all five: 200 (500 headers); 1000/16061 [200:500:8039,200:500:8022]; head 200/500, port eof |
| connect-500+501 | h1tls+proxy | - | buffered | all five: 23 header-limit; 1001/16075 [200:500:8039,200:501:8036] |
| connect-500+501 | h1tls+proxy | - | streamed | all five: 23 header-limit; 1001/16075 [200:500:8039,200:501:8036]; no head, port 23 header-limit |
| connect-250x256+250x256 | h1tls+proxy | - | buffered | all five: 23 header-limit; 401/102475 [200:250:64039,200:151:38436] |
| connect-250x256+250x256 | h1tls+proxy | - | streamed | all five: 23 header-limit; 401/102475 [200:250:64039,200:151:38436]; no head, port 23 header-limit |
| connect-500+500 | h2+proxy | - | buffered | all five: 200 (500 headers); 1000/16057 [200:500:8039,200:500:8018] |
| connect-500+500 | h2+proxy | - | streamed | all five: 200 (500 headers); 1000/16057 [200:500:8039,200:500:8018]; head 200/500, port eof |
| connect-500+501 | h2+proxy | - | buffered | all five: 23 header-limit; 1001/16071 [200:500:8039,200:501:8032] |
| connect-500+501 | h2+proxy | - | streamed | all five: 23 header-limit; 1001/16071 [200:500:8039,200:501:8032]; no head, port 23 header-limit |
| connect-250x256+250x256 | h2+proxy | - | buffered | all five: 23 header-limit; 401/102471 [200:250:64039,200:151:38432] |
| connect-250x256+250x256 | h2+proxy | - | streamed | all five: 23 header-limit; 401/102471 [200:250:64039,200:151:38432]; no head, port 23 header-limit |

- Each kind takes 1,000 lines in all and refuses the 1,001st on every lane, each head alone under
  the cap; and the bytes: each head under 102,400, the two past it, refused. A 103 or 100 head's
  status line and empty line are left out of the count, as a final head's are.
- **8.5.0 over HTTP/2, a refused trailer:** `tr-2+999` and `tr-2+400x256` end `header-limit` with
  code 0 on both 8.5.0 builds, buffered and streamed, and the stream's port raises `header-limit`
  0 after publishing the head; the error buffer holds `Failed writing header`. 7.85.0, 8.20.0 and
  8.23.0 end the same cells 23. So the recorded reason makes the lost refusal a failure, as the
  plan meant; its code is libcurl's, 0.
- **7.85.0 lists HTTP/2 trailers among a response's headers:** `tr-2+998` over h2 answers 1,000
  headers on 7.85.0 and 2 elsewhere; its stream's head, published at the head's end, holds 2.
- No lane called the callable again after it refused a line, or after any reason was recorded: no
  tally has a `refused after` count.

*libcurl's refusals before a line reaches the callable, and their controls, run 1*

| cell | face | opts | way | answer |
|---|---|---|---|---|
| line102399 | h1 | - | buffered | all five: 23 header-limit; 2/102435 [200:2:102435] |
| line102399 | h1 | - | streamed | all five: 23 header-limit; 2/102435 [200:2:102435]; no head, port 23 header-limit |
| line102400 | h1 | - | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 27; 1/36 [200:1:36]; **8.20.0, 8.23.0**: 100; 1/36 [200:1:36] |
| line102400 | h1 | - | streamed | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 27; 1/36 [200:1:36]; no head, port 27; **8.20.0, 8.23.0**: 100; 1/36 [200:1:36]; no head, port 100 |
| line102400 | h1tls | - | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 27; 1/36 [200:1:36]; **8.20.0, 8.23.0**: 100; 1/36 [200:1:36] |
| line102400 | h1tls | - | streamed | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 27; 1/36 [200:1:36]; no head, port 27; **8.20.0, 8.23.0**: 100; 1/36 [200:1:36]; no head, port 100 |
| line102400 | h2 | - | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 27; 1/32 [200:1:32]; **8.20.0**: 16; 1/32 [200:1:32]; **8.23.0**: 56; 1/32 [200:1:32] |
| line102400 | h2 | - | streamed | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 27; 1/32 [200:1:32]; no head, port 27; **8.20.0**: 16; 1/32 [200:1:32]; no head, port 16; **8.23.0**: 56; 1/32 [200:1:32]; no head, port 56 |
| line102400-X | h2 | - | buffered | **7.85.0**: 52; 0/0 []; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 1/32 [200:1:32]; **8.20.0, 8.23.0**: 16; 1/32 [200:1:32] |
| line102400-X | h2 | - | streamed | **7.85.0**: 52; 0/0 []; no head, port 52; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 1/32 [200:1:32]; no head, port 56; **8.20.0, 8.23.0**: 16; 1/32 [200:1:32]; no head, port 16 |
| total131071 | h2 | - | buffered | all five: 23 header-limit; 401/102432 [200:401:102432] |
| total131071 | h2 | - | streamed | all five: 23 header-limit; 401/102432 [200:401:102432]; no head, port 23 header-limit |
| total131072 | h2 | - | buffered | **7.85.0**: 56; 0/0 []; **8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.20.0, 8.23.0**: 23 header-limit; 401/102432 [200:401:102432] |
| total131072 | h2 | - | streamed | **7.85.0**: 56; 0/0 []; no head, port 56; **8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.20.0, 8.23.0**: 23 header-limit; 401/102432 [200:401:102432]; no head, port 23 header-limit |
| total307199 | h2 | - | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 0/0 []; **8.20.0, 8.23.0**: 23 header-limit; 401/102432 [200:401:102432] |
| total307199 | h2 | - | streamed | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 0/0 []; no head, port 56; **8.20.0, 8.23.0**: 23 header-limit; 401/102432 [200:401:102432]; no head, port 23 header-limit |
| tr-2+1600x256 | h2 | - | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.23.0**: 56; 2/47 [200:2:47]; **8.20.0**: 16; 2/47 [200:2:47] |
| tr-2+1600x256 | h2 | - | streamed | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.23.0**: 56; 2/47 [200:2:47]; head 200/2, port 56; **8.20.0**: 16; 2/47 [200:2:47]; head 200/2, port 16 |
| tr-line4000 | h1 | - | buffered | all five: 200 (2 headers); 3/4063 [200:2:63,T:1:4000] |
| tr-line4000 | h1 | - | streamed | all five: 200 (2 headers); 3/4063 [200:2:63,T:1:4000]; head 200/2, port eof |
| tr-line5000 | h1 | - | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 2/63 [200:2:63]; **8.20.0, 8.23.0**: 100; 2/63 [200:2:63] |
| tr-line5000 | h1 | - | streamed | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 2/63 [200:2:63]; head 200/2, port 56; **8.20.0, 8.23.0**: 100; 2/63 [200:2:63]; head 200/2, port 100 |
| tr-line5000 | h2 | - | buffered | **7.85.0**: 200 (3 headers); 3/5047 [200:2:47,T:1:5000]; **8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.20.0, 8.23.0**: 200 (2 headers); 3/5047 [200:2:47,T:1:5000] |
| tr-line5000 | h2 | - | streamed | **7.85.0**: 200 (3 headers); 3/5047 [200:2:47,T:1:5000]; head 200/2, port eof; **8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.20.0, 8.23.0**: 200 (2 headers); 3/5047 [200:2:47,T:1:5000]; head 200/2, port eof |
| tr-2+6000 | h1 | - | buffered | all five: 23 header-limit; 1001/16047 [200:2:63,T:999:15984] |
| tr-2+6000 | h1 | - | streamed | all five: 23 header-limit; 1001/16047 [200:2:63,T:999:15984]; head 200/2, port 23 header-limit |
| tr-2+6000 | h2 | - | buffered | **7.85.0, 8.20.0**: 23 header-limit; 1001/16031 [200:2:47,T:999:15984]; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 0 header-limit; 1001/16031 [200:2:47,T:999:15984]; **8.23.0**: 56; 2/47 [200:2:47] |
| tr-2+6000 | h2 | - | streamed | **7.85.0, 8.20.0**: 23 header-limit; 1001/16031 [200:2:47,T:999:15984]; head 200/2, port 23 header-limit; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 0 header-limit; 1001/16031 [200:2:47,T:999:15984]; head 200/2, port 0 header-limit; **8.23.0**: 56; 2/47 [200:2:47]; head 200/2, port 56 |
| tr-2+3 | h1 | - | buffered | all five: 200 (2 headers); 5/111 [200:2:63,T:3:48] |
| tr-2+3 | h1 | - | streamed | all five: 200 (2 headers); 5/111 [200:2:63,T:3:48]; head 200/2, port eof |
| tr-2+3 | h2 | - | buffered | **7.85.0**: 200 (5 headers); 5/95 [200:2:47,T:3:48]; **8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.20.0, 8.23.0**: 200 (2 headers); 5/95 [200:2:47,T:3:48] |
| tr-2+3 | h2 | - | streamed | **7.85.0**: 200 (5 headers); 5/95 [200:2:47,T:3:48]; head 200/2, port eof; **8.5.0 OpenSSL, 8.5.0 GnuTLS, 8.20.0, 8.23.0**: 200 (2 headers); 5/95 [200:2:47,T:3:48]; head 200/2, port eof |

The rows `test-headers`' per-version table will hold, from these, two runs each, every one alike:

| what | 7.85.0 | 8.5.0 (both) | 8.20.0 | 8.23.0 |
|---|---|---|---|---|
| a line of 102,400 bytes, HTTP/1.1 (and over TLS) | 27 | 27 | 100 | 100 |
| a line of 102,400 bytes, HTTP/2, HPACK codes it (`a`) | 27 | 27 | 16 | 56 |
| a line of 102,400 bytes, HTTP/2, HPACK cannot (`X`) | 52, nothing handed | 56 | 16 | 16 |
| an HTTP/2 head of 131,072 bytes | 56, nothing handed | 23 `header-limit` | 23 `header-limit` | 23 `header-limit` |
| an HTTP/2 head past nghttp2's limit (307,199 bytes of 256-byte lines) | 56, nothing handed | 56, nothing handed | 23 `header-limit` | 23 `header-limit` |
| HTTP/2 trailers past nghttp2's limit (1,600 of 256 bytes) | 56 | 56 | 16 | 56 |
| a trailer line of 5,000 bytes, HTTP/1.1 | 56 | 56 | 100 | 100 |
| 6,000 HTTP/2 trailers | 23 `header-limit` | 0 `header-limit` | 23 `header-limit` | 56, none handed |
| 3 HTTP/2 trailers: the response's headers | 5 | 2 | 2 | 2 |
| the cap's own refusal | 23 | 23; 0 for an HTTP/2 trailer | 23 | 23 |

The controls beside them: one line of 102,399 bytes, which libcurl takes, is the cap's (23); a
4,000-byte trailer line over HTTP/1.1 and a 5,000-byte one over HTTP/2 are taken by every lane.
Every code here is the caps probe's cap mode's for the same cell ([caps/README.md](../caps/README.md),
case 4): the engine answers as libcurl alone did. The plan's §3.8 lists nghttp2's limit on a head
as "56, or 16 on 8.20.0", which is libcurl's answer with no cap (case 2); with the cap, 8.20.0 and
8.23.0 hand the head's lines first and refuse it as `header-limit`, 23.

### `SUPPRESS_CONNECT_HEADERS`

*SUPPRESS_CONNECT_HEADERS through the proxy, run 1*

| cell | face | opts | way | answer |
|---|---|---|---|---|
| connect-600+600 | h1tls+proxy | - | buffered | all five: 23 header-limit; 1001/16075 [200:600:9639,200:401:6436] |
| connect-600+600 | h1tls+proxy | - | streamed | all five: 23 header-limit; 1001/16075 [200:600:9639,200:401:6436]; no head, port 23 header-limit |
| connect-4500+600 | h1tls+proxy | - | buffered | all five: 23 header-limit; 1001/16053 [200:1001:16053] |
| connect-4500+600 | h1tls+proxy | - | streamed | all five: 23 header-limit; 1001/16053 [200:1001:16053]; no head, port 23 header-limit |
| connect-900x256+350x256 | h1tls+proxy | - | buffered | all five: 23 header-limit; 400/102437 [200:400:102437] |
| connect-900x256+350x256 | h1tls+proxy | - | streamed | all five: 23 header-limit; 400/102437 [200:400:102437]; no head, port 23 header-limit |
| connect-600+600 | h1tls+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | all five: 200 (600 headers); 600/9622 [200:600:9622] |
| connect-600+600 | h1tls+proxy | SUPPRESS_CONNECT_HEADERS=1 | streamed | all five: 200 (600 headers); 600/9622 [200:600:9622]; head 200/600, port eof |
| connect-4500+600 | h1tls+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 200 (600 headers); 600/9622 [200:600:9622]; **8.20.0, 8.23.0**: 100; 500/8020 [200:500:8020] |
| connect-4500+600 | h1tls+proxy | SUPPRESS_CONNECT_HEADERS=1 | streamed | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 200 (600 headers); 600/9622 [200:600:9622]; head 200/600, port eof; **8.20.0, 8.23.0**: 100; 500/8020 [200:500:8020]; no head, port 100 |
| connect-900x256+350x256 | h1tls+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | **7.85.0, 8.20.0, 8.23.0**: 200 (350 headers); 350/89382 [200:350:89382]; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 301/76836 [200:301:76836] |
| connect-900x256+350x256 | h1tls+proxy | SUPPRESS_CONNECT_HEADERS=1 | streamed | **7.85.0, 8.20.0, 8.23.0**: 200 (350 headers); 350/89382 [200:350:89382]; head 200/350, port eof; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 301/76836 [200:301:76836]; no head, port 56 |
| connect-600+600 | h2+proxy | - | buffered | all five: 23 header-limit; 1001/16071 [200:600:9639,200:401:6432] |
| connect-600+600 | h2+proxy | - | streamed | all five: 23 header-limit; 1001/16071 [200:600:9639,200:401:6432]; no head, port 23 header-limit |
| connect-4500+600 | h2+proxy | - | buffered | all five: 23 header-limit; 1001/16053 [200:1001:16053] |
| connect-4500+600 | h2+proxy | - | streamed | all five: 23 header-limit; 1001/16053 [200:1001:16053]; no head, port 23 header-limit |
| connect-900x256+350x256 | h2+proxy | - | buffered | all five: 23 header-limit; 400/102437 [200:400:102437] |
| connect-900x256+350x256 | h2+proxy | - | streamed | all five: 23 header-limit; 400/102437 [200:400:102437]; no head, port 23 header-limit |
| connect-600+600 | h2+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | all five: 200 (600 headers); 600/9618 [200:600:9618] |
| connect-600+600 | h2+proxy | SUPPRESS_CONNECT_HEADERS=1 | streamed | all five: 200 (600 headers); 600/9618 [200:600:9618]; head 200/600, port eof |
| connect-4500+600 | h2+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 200 (600 headers); 600/9618 [200:600:9618]; **8.20.0, 8.23.0**: 100; 499/8000 [200:499:8000] |
| connect-4500+600 | h2+proxy | SUPPRESS_CONNECT_HEADERS=1 | streamed | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 200 (600 headers); 600/9618 [200:600:9618]; head 200/600, port eof; **8.20.0, 8.23.0**: 100; 499/8000 [200:499:8000]; no head, port 100 |
| connect-900x256+350x256 | h2+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | **7.85.0, 8.20.0, 8.23.0**: 200 (350 headers); 350/89378 [200:350:89378]; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 301/76832 [200:301:76832] |
| connect-900x256+350x256 | h2+proxy | SUPPRESS_CONNECT_HEADERS=1 | streamed | **7.85.0, 8.20.0, 8.23.0**: 200 (350 headers); 350/89378 [200:350:89378]; head 200/350, port eof; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 301/76832 [200:301:76832]; no head, port 56 |
| connect-15000+2 | h1tls+proxy | - | buffered | all five: 23 header-limit; 1001/16053 [200:1001:16053] |
| connect-2+2 | h1tls+proxy | - | buffered | all five: 200 (2 headers); 4/125 [200:2:71,200:2:54] |
| connect-15000+2 | h1tls+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 200 (2 headers); 2/54 [200:2:54]; **8.20.0, 8.23.0**: 100; 0/0 [] |
| connect-2+2 | h1tls+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | all five: 200 (2 headers); 2/54 [200:2:54] |
| connect-60000+2 | h1tls+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | **7.85.0**: 200 (2 headers); 2/54 [200:2:54]; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 0/0 []; **8.20.0, 8.23.0**: 100; 0/0 [] |
| connect-15000+2 | h2+proxy | - | buffered | all five: 23 header-limit; 1001/16053 [200:1001:16053] |
| connect-2+2 | h2+proxy | - | buffered | all five: 200 (2 headers); 4/121 [200:2:71,200:2:50] |
| connect-15000+2 | h2+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | **7.85.0, 8.5.0 OpenSSL, 8.5.0 GnuTLS**: 200 (2 headers); 2/50 [200:2:50]; **8.20.0, 8.23.0**: 100; 0/0 [] |
| connect-2+2 | h2+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | all five: 200 (2 headers); 2/50 [200:2:50] |
| connect-60000+2 | h2+proxy | SUPPRESS_CONNECT_HEADERS=1 | buffered | **7.85.0**: 200 (2 headers); 2/50 [200:2:50]; **8.5.0 OpenSSL, 8.5.0 GnuTLS**: 56; 0/0 []; **8.20.0, 8.23.0**: 100; 0/0 [] |

- **Without it**, the callable is handed the `CONNECT` answer, and the cap counts it with the
  tunnelled response's, on every lane (`connect-600+600`: 600 + 401).
- **With it**, the callable never sees the answer, on every lane: `connect-600+600` is taken with
  600 lines counted. What bounds a hidden answer is then libcurl's, by version:
  - 8.20.0 and 8.23.0 still count its lines toward their 5,000: `connect-4500+600` ends 100, `Too
    many response headers, 5000 is max`, after 500 of the response's lines (499 over HTTP/2), and
    `connect-15000+2` and `connect-60000+2` with nothing handed;
  - 8.5.0 still counts its bytes toward its 307,200: `connect-900x256+350x256` ends 56 after 301
    of the response's lines, and `connect-60000+2` 56, `Too large response headers: 307205 > 307200`;
  - 7.85.0 counts neither: it took `connect-60000+2`, a hidden answer of 60,000 lines and 960,039
    bytes, in 354 ms, and answered the response's 2 headers.
- **Neither way does chez-curl's surface show the answer:** a response's headers are the walk's of
  the last request (`connect-2+2`: 2 headers either way), and a stream's head skips a `CONNECT`
  head (status 0). So the option changes nothing a caller reads but the cap.

**Recommendation: make `SUPPRESS_CONNECT_HEADERS` a twin of the header callable's,** refused by
the hatch as `owned-option`, as `HEADER` is. Set, it takes the `CONNECT` answer out of the cap on
every lane, so the same proxy answer is `header-limit` without it, 100 or 56 with it on 8.5.0 and
later, and taken whole on 7.85.0; and it gives a caller nothing chez-curl shows. The other way is
to keep it the hatch's and document that it takes the `CONNECT` answer out of the cap: the
hatch's options are unsupported, but this one undoes a promise ADR-0040 makes for every transfer.

### The other options that change what the callable sees

Read from 8.23.0's `docs/libcurl/opts/` (`build/verify/current/curl-8.23.0`): its 426 pages, every
`CURLOPT_*` description naming the header callback, a response header, a trailer, a status line,
a `CONNECT` response, 1xx, `100-continue`, a response without headers or transfer decoding (17
options), and those that make a second request inside a transfer (the auth, proxy-auth and
follow options). Each was handed to `curl-request-with-options` on all five lanes:

*The hatch: each option that can change what the header callable sees, as curl-request-with-options answers it*

| option | value | answer |
|---|---|---|
| `SUPPRESS_CONNECT_HEADERS` | `1` | all five: accepted |
| `HTTP_TRANSFER_DECODING` | `0` | all five: accepted |
| `HTTP200ALIASES` | `("ICY 200 OK")` | all five: accepted |
| `HTTP09_ALLOWED` | `1` | all five: accepted |
| `PROXYAUTH` | `1` | all five: (refused owned-option) |
| `FAILONERROR` | `1` | all five: accepted |
| `KEEP_SENDING_ON_ERROR` | `1` | all five: accepted |
| `EXPECT_100_TIMEOUT_MS` | `1000` | all five: accepted |
| `HEADER` | `1` | all five: (refused owned-option) |
| `HEADERFUNCTION` | `0` | all five: (refused owned-option) |
| `HEADERDATA` | `0` | all five: (refused owned-option) |
| `WRITEHEADER` | `0` | all five: (refused owned-option) |
| `HTTPPROXYTUNNEL` | `1` | all five: (refused owned-option) |
| `CONNECT_ONLY` | `1` | all five: (refused owned-option) |
| `NOBODY` | `1` | all five: (refused owned-option) |
| `FOLLOWLOCATION` | `1` | all five: (refused owned-option) |
| `HTTPAUTH` | `1` | all five: (refused owned-option) |
| `HTTP_VERSION` | `2` | all five: (refused owned-option) |
| `PROXYTYPE` | `1` | all five: (refused owned-option) |
| `UNRESTRICTED_AUTH` | `1` | all five: accepted |
| `POSTREDIR` | `1` | all five: accepted |
| `TIMECONDITION` | `1` | all five: accepted |
| `TIMEVALUE` | `1` | all five: accepted |
| `HTTP_CONTENT_DECODING` | `0` | all five: accepted |
| `ACCEPT_ENCODING` | `"gzip"` | all five: accepted |
| `TRANSFER_ENCODING` | `1` | all five: accepted |
| `IGNORE_CONTENT_LENGTH` | `1` | all five: accepted |
| `CONNECT_TO` | `("::127.0.0.1:1")` | all five: accepted |
| `RANGE` | `"0-1"` | all five: accepted |
| `MAXREDIRS` | `1` | all five: (refused owned-option) |
| `PROXY` | `"http://127.0.0.1:1"` | all five: (refused owned-option) |
| `HTTPHEADER` | `("X-A: b")` | all five: (refused owned-option) |
| `PROXYHEADER` | `("X-A: b")` | all five: (refused owned-option) |
| `HEADEROPT` | `1` | all five: (refused owned-option) |
| `CUSTOMREQUEST` | `"GET"` | all five: (refused owned-option) |
| `REQUEST_TARGET` | `"/"` | all five: (refused owned-option) |
| `HTTPGET` | `1` | all five: (refused owned-option) |
| `CRLF` | `1` | all five: (refused owned-option) |
| `DEBUGFUNCTION` | `0` | all five: (refused unsupported-type) |
| `VERBOSE` | `1` | all five: accepted |
| `HTTPPOST` | `0` | all five: (refused owned-option) |
| `POSTFIELDS` | `"x"` | all five: (refused owned-option) |
| `POST` | `1` | all five: (refused owned-option) |
| `UPLOAD` | `1` | all five: (refused owned-option) |
| `TRAILERFUNCTION` | `0` | all five: (refused unsupported-type) |
| `TRAILERDATA` | `0` | all five: (refused unsupported-type) |

Of those the hatch takes, what each changes for the callable:

- **`SUPPRESS_CONNECT_HEADERS`**: hides a `CONNECT` answer, above.
- **`HTTP_TRANSFER_DECODING` 0**: libcurl hands a chunked body raw, its trailers in it, so the
  callable never sees a trailer, on every lane; they are body bytes, which `body-limit` bounds, and
  none is stored as a header ([the table below](#http_transfer_decoding)).
- **`HTTP200ALIASES`**: a listed status line, such as `ICY 200 OK`, starts a head; it does not
  start `HTTP/`, so the cap counts it as one header line more a head. Read, not measured: the stand-in
  sends no such line.
- **`HTTP09_ALLOWED`**: an HTTP/0.9 response has no head, so the callable is handed nothing. Read.
- **`FAILONERROR`**: libcurl ends the transfer at a status of 400 or more, so the callable is handed
  that head's lines at most. Read.

The rest the hatch takes (`KEEP_SENDING_ON_ERROR`, `EXPECT_100_TIMEOUT_MS`, `UNRESTRICTED_AUTH`,
`POSTREDIR`, `TIMECONDITION`, `TIMEVALUE`, `HTTP_CONTENT_DECODING`, `ACCEPT_ENCODING`,
`TRANSFER_ENCODING`, `IGNORE_CONTENT_LENGTH`, `CONNECT_TO`, `RANGE`) change the request, the
body or where it goes, not what the callable is handed; `UNRESTRICTED_AUTH` and `POSTREDIR` act
only with `FOLLOWLOCATION`, which is owned and off; `VERBOSE` writes to stderr, beside the
callable. `PROXYAUTH`, the one that could add a 407 round, is owned already, and so are `HEADER`,
`HEADERFUNCTION`, `HEADERDATA`, `WRITEHEADER`, `HTTPPROXYTUNNEL`, `CONNECT_ONLY`, `NOBODY`,
`FOLLOWLOCATION`, `HTTPAUTH`, `HTTP_VERSION`, `PROXYTYPE` and the body's `HTTPPOST`, `POSTFIELDS`,
`POST` and `UPLOAD`; `DEBUGFUNCTION`, `TRAILERFUNCTION` and `TRAILERDATA` are refused as
`unsupported-type`, a callback's or a pointer's.

### `HTTP_TRANSFER_DECODING`

*HTTP_TRANSFER_DECODING through the hatch, run 1*

| cell | face | opts | way | answer |
|---|---|---|---|---|
| tr-2+999 | h1 | - | buffered | all five: 23 header-limit; 1001/16047 [200:2:63,T:999:15984] |
| tr-2+999 | h1 | - | streamed | all five: 23 header-limit; 1001/16047 [200:2:63,T:999:15984]; head 200/2, port 23 header-limit |
| tr-2+400x256 | h1 | - | buffered | all five: 23 header-limit; 402/102463 [200:2:63,T:400:102400] |
| tr-2+400x256 | h1 | - | streamed | all five: 23 header-limit; 402/102463 [200:2:63,T:400:102400]; head 200/2, port 23 header-limit |
| tr-2+999 | h1 | HTTP_TRANSFER_DECODING=0 | buffered | all five: 200 (2 headers); 2/63 [200:2:63] |
| tr-2+999 | h1 | HTTP_TRANSFER_DECODING=0 | streamed | all five: 200 (2 headers); 2/63 [200:2:63]; head 200/2, body 15989, port eof |
| tr-2+400x256 | h1 | HTTP_TRANSFER_DECODING=0 | buffered | all five: 200 (2 headers); 2/63 [200:2:63] |
| tr-2+400x256 | h1 | HTTP_TRANSFER_DECODING=0 | streamed | all five: 200 (2 headers); 2/63 [200:2:63]; head 200/2, body 102405, port eof |

### The cost of the buffered transfer's callable

`cost.sps` through `(curl)` alone, on lane F (7.85.0), main's tree against the prototype's, run
alternately, main then the prototype, twice: 101 rounds natively (`results/cost-{main,proto}-floor-{1,2}.log`),
15 under the memory gate's Valgrind, the options `make test-memory` passes, no suppression, the
stand-in native (`results/cost-vg-{main,proto}-floor-{1,2}.log`, Valgrind's own logs
`results/cost-vg-{main,proto}-{1,2}-floor.vg`, each `ERROR SUMMARY: 0 errors from 0 contexts`).
Every thread collects, by `collect-rendezvous`, before each request, outside the measured window.
Process CPU is from the submit to the wait's return: the engine's thread's work, this thread's
polls and any collection. libcurl's total holds the callable's calls, made inside
`curl_multi_perform`, and not the walk after it.

*The cost, lane F (7.85.0): process CPU and libcurl's total per request, min / median / max (samples), each log*

| log | tree | Valgrind | kind | headers | process CPU ms | libcurl total ms | samples |
|---|---|---|---|---|---|---|---|
| `cost-main-floor-1.log` | main | no | base | 2 | 0.12 / 0.25 / 0.54 | 0.10 / 0.31 / 1.01 | 101 |
| `cost-main-floor-1.log` | main | no | final | 1000 | 5.78 / 5.90 / 8.47 | 0.34 / 0.77 / 1.42 | 101 |
| `cost-main-floor-1.log` | main | no | pre | 500 | 3.10 / 3.23 / 5.56 | 0.38 / 0.86 / 1.31 | 101 |
| `cost-main-floor-2.log` | main | no | base | 2 | 0.12 / 0.22 / 0.66 | 0.08 / 0.28 / 0.53 | 101 |
| `cost-main-floor-2.log` | main | no | final | 1000 | 3.99 / 5.87 / 7.68 | 0.36 / 0.74 / 1.55 | 101 |
| `cost-main-floor-2.log` | main | no | pre | 500 | 2.67 / 3.25 / 5.55 | 0.34 / 0.73 / 1.43 | 101 |
| `cost-proto-floor-1.log` | proto | no | base | 2 | 0.18 / 0.28 / 0.67 | 0.12 / 0.36 / 0.74 | 101 |
| `cost-proto-floor-1.log` | proto | no | final | 1000 | 4.44 / 7.15 / 9.07 | 0.87 / 1.32 / 2.46 | 101 |
| `cost-proto-floor-1.log` | proto | no | pre | 500 | 2.93 / 4.12 / 5.97 | 0.93 / 1.38 / 2.67 | 101 |
| `cost-proto-floor-2.log` | proto | no | base | 2 | 0.17 / 0.27 / 0.56 | 0.20 / 0.35 / 0.60 | 101 |
| `cost-proto-floor-2.log` | proto | no | final | 1000 | 4.27 / 6.33 / 9.30 | 0.78 / 1.32 / 3.45 | 101 |
| `cost-proto-floor-2.log` | proto | no | pre | 500 | 3.46 / 3.66 / 6.49 | 0.86 / 1.36 / 2.86 | 101 |
| `cost-vg-main-floor-1.log` | main | yes | base | 2 | 2.21 / 4.16 / 78.31 | 0.80 / 1.34 / 3.78 | 15 |
| `cost-vg-main-floor-1.log` | main | yes | final | 1000 | 96.96 / 99.74 / 113.50 | 5.35 / 5.93 / 8.68 | 15 |
| `cost-vg-main-floor-1.log` | main | yes | pre | 500 | 51.22 / 55.05 / 57.93 | 4.65 / 5.99 / 8.80 | 15 |
| `cost-vg-main-floor-2.log` | main | yes | base | 2 | 2.85 / 4.40 / 78.39 | 1.20 / 1.44 / 3.77 | 15 |
| `cost-vg-main-floor-2.log` | main | yes | final | 1000 | 98.78 / 102.22 / 128.64 | 5.25 / 6.08 / 8.59 | 15 |
| `cost-vg-main-floor-2.log` | main | yes | pre | 500 | 52.06 / 58.15 / 68.79 | 3.65 / 7.50 / 9.26 | 15 |
| `cost-vg-proto-floor-1.log` | proto | yes | base | 2 | 3.00 / 4.91 / 22.87 | 1.06 / 1.93 / 2.75 | 15 |
| `cost-vg-proto-floor-1.log` | proto | yes | final | 1000 | 113.99 / 118.24 / 120.11 | 25.97 / 27.38 / 30.95 | 15 |
| `cost-vg-proto-floor-1.log` | proto | yes | pre | 500 | 72.83 / 74.35 / 147.42 | 26.40 / 28.06 / 34.95 | 15 |
| `cost-vg-proto-floor-2.log` | proto | yes | base | 2 | 2.90 / 4.80 / 22.76 | 1.20 / 1.96 / 2.62 | 15 |
| `cost-vg-proto-floor-2.log` | proto | yes | final | 1000 | 117.20 / 122.67 / 125.61 | 25.37 / 29.64 / 33.71 | 15 |
| `cost-vg-proto-floor-2.log` | proto | yes | pre | 500 | 76.33 / 79.74 / 154.23 | 27.74 / 32.01 / 38.09 | 15 |

*The prototype less main, by the medians above, run by run, and per call of the callable*

| Valgrind | run | kind | calls | process CPU ms | per call, us | libcurl total ms | per call, us |
|---|---|---|---|---|---|---|---|
| no | 1 | base | 4 | +0.03 | +7.00 | +0.05 | +13.00 |
| no | 1 | final | 1002 | +1.25 | +1.25 | +0.55 | +0.55 |
| no | 1 | pre | 1004 | +0.90 | +0.89 | +0.51 | +0.51 |
| no | 2 | base | 4 | +0.04 | +10.25 | +0.07 | +16.25 |
| no | 2 | final | 1002 | +0.45 | +0.45 | +0.59 | +0.58 |
| no | 2 | pre | 1004 | +0.41 | +0.40 | +0.64 | +0.64 |
| yes | 1 | base | 4 | +0.75 | +188.00 | +0.59 | +148.75 |
| yes | 1 | final | 1002 | +18.50 | +18.46 | +21.46 | +21.41 |
| yes | 1 | pre | 1004 | +19.31 | +19.23 | +22.07 | +21.98 |
| yes | 2 | base | 4 | +0.40 | +100.50 | +0.53 | +131.50 |
| yes | 2 | final | 1002 | +20.45 | +20.41 | +23.56 | +23.51 |
| yes | 2 | pre | 1004 | +21.59 | +21.50 | +24.50 | +24.41 |

- **Per call, natively:** +0.51 to +0.64 µs by libcurl's total in all four comparisons of 1,002 and
  1,004 calls; +0.40 to +1.25 µs by process CPU, whose medians move about 1 ms between runs of the
  same tree. The plan's "about 0.5 µs a line" holds on 7.85.0.
- **Per call, under the gate's Valgrind:** +21.4 to +24.4 µs by libcurl's total, +18.5 to +21.5 by
  process CPU: a 1,000-line response costs about 21 to 25 ms more under the gate, beside the 100 to
  102 ms of process CPU main's tree spends on it there.
- **Per transfer:** `base`, 4 calls, costs +0.05 and +0.07 ms by libcurl's total natively and +0.53
  and +0.59 under Valgrind, far more than 4 of the per-line calls; so the callable has a cost per
  transfer besides its cost per line. The first design of this measure, 21 rounds with no
  `collect-rendezvous`, was too noisy to read and was replaced; its logs are not in `results/`, and
  no number here is from it.

## Item 3: the origin's HTTP/2 faces with Node's limits raised

Every suite that uses an HTTP/2 face (`test-auth`, `test-cookies`, `test-curl-testing`,
`test-origin`, `test-origin-tls`, `test-proxy`, `test-stream-call`, `test-stream`,
`test-transfer-tls`, `test-upload`, `test-version`; `test-request` names `h2` only as a version
value), on the five lanes, on `main` with no route added:

| the h2 faces' limits | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 |
|---|---|---|---|---|---|
| the caps stand-in's three | 9 of 11 | 9 of 11 | 9 of 11 | 9 of 11 | 9 of 11 |
| `maxSendHeaderBlockLength` alone | 11 of 11 | 11 of 11 | 11 of 11 | 11 of 11 | 11 of 11 |

(`results/h2-origin-docker.log`, `results/test-h2-origin-{floor,openssl,gnutls,current}.log`,
`results/h2-origin-guix-8.20.0.log`; `results/h2-origin-send-docker.log`,
`results/test-h2-origin-send-{floor,openssl,gnutls,current}.log`,
`results/h2-origin-send-guix-8.20.0.log`.)

- **With the three, `test-origin` fails 2 tests and `test-origin-tls` 82, on every lane,** and
  each failure's actual is the same change: the SETTINGS frame each HTTP/2 face sends first was
  empty, `000000040000000000`, and is now `000006040000000000000604000000`, one setting, id 6,
  `SETTINGS_MAX_HEADER_LIST_SIZE`, at 64 MiB. `test-origin`'s plaintext waiting states and
  `test-origin-tls`'s frame checks hold those bytes whole. It is a receive limit the face
  advertises, not a send limit; the frame holds that one setting, so `maxHeaderListPairs` adds
  none.
- **With the send limit alone every suite passes,** and every cell of the probe answers as with all
  three (`limits.py`'s output, `results/limits-compare.txt`, over
  `results/limits-{send,send+pairs,send+pairs+settings}-guix-8.20.0.log`).
- **With Node's defaults, the cap's large HTTP/2 heads cannot be tested:** a head over Node's
  64 KiB send limit is never sent (libcurl 92, `HTTP/2 stream 1 was closed cleanly, but before
  getting all response header fields`), and a trailer block over it is dropped (31 of the probe's
  cells differ, `results/limits-none-guix-8.20.0-1.log`; 21 of the 81 in its second run,
  `-2.log`, the same cells). 1,001 lines of 16 bytes are sent under the default.

## Item 4: `make test` on the prototype

The whole `make test` on the `proto` tree (the cap, and the send limit on the HTTP/2 faces), once
on each lane, and the two failing suites again on lane X:

| lane | suites | failed | log |
|---|---|---|---|
| F 7.85.0 | 41 | `test-conditions`, `test-transfer` | `results/test-proto-floor.log` |
| O 8.5.0 OpenSSL | 41 | `test-conditions`, `test-transfer` | `results/test-proto-openssl.log` |
| G 8.5.0 GnuTLS | 41 | `test-conditions`, `test-transfer` | `results/test-proto-gnutls.log` |
| X 8.20.0 | 41 | `test-conditions`, `test-transfer` | `results/test-proto-guix-8.20.0.log`; again, `-again.log` |
| C 8.23.0 | 41 | `test-conditions`, `test-transfer` | `results/test-proto-current.log` |

(`results/test-proto-docker.log` holds the Docker lanes' summary lines.) Every other suite passed
on every lane, every HTTP/2 suite among them. The tests that answered differently:

- **`test-transfer`, shared: `GET raw /raw/big-header?bytes=102380`**, on all five: it was a 200
  with its one `X-Big` header, and is now `(refused header-limit 23)`. The plan's second case: its
  status line, 17 bytes, and its line of 102,389 bytes take the count to 102,406.
- **`test-transfer`, varying: `GET raw /raw/many-headers?count=50000`**, on all five: each row's
  answer, a 200 of 50,000 headers on 7.85.0, 56 on 8.5.0, 100 on 8.20.0 and 8.23.0, is now
  `(refused header-limit 23)`, the 1,001st line refused. The plan's first case.
- **`test-transfer`, class, by the row: the same case**, on every lane but 7.85.0, whose row
  answers a response and so has no class test: the row's code's class (send-receive for 8.5.0's 56,
  too-large for 100) against the raised `header-limit 23`, of `&curl-too-large`. The same cause.
- **`test-conditions`: "the transfer-error reasons are exactly perform-failed, ...,
  body-not-replayable, in order"**, on all five: the list now ends in `header-limit`. The plan's
  §3.7 expects the written-out lists to grow; it is not among §3.3's two cases, so it is named here.

Nothing else answered differently: the other 39 suites passed on every lane with a header callable
on every transfer. `make test` ran no suite under Valgrind; the cost under the gate is item 2's.

## What the maintainer must answer

1. **`SUPPRESS_CONNECT_HEADERS`: a twin, or the hatch's?** Recommended: a twin, refused as
   `owned-option` (above). The other: keep it, and document that it takes a `CONNECT` answer out
   of the cap.
2. **`HTTP_TRANSFER_DECODING` 0** moves trailers out of the callable's sight into the body, where
   `body-limit` bounds them and no header is stored. The brief asks no recommendation; the evidence
   leaves it the hatch's unless the maintainer wants the cap to hold over trailers whatever the
   hatch sets. Either way the docs can say it.
3. **The origin's limit:** the plan's §3.3 says to raise Node's send limits "as the caps stand-in
   did". The stand-in raised three, and two are not send limits; the third changes bytes two
   suites hold. Raise `maxSendHeaderBlockLength` alone, or all three and rewrite those tests'
   SETTINGS bytes? The evidence favours the first: it alone is needed, and it changes nothing.

## What the build will need that the plan does not say

- **The cap's code can be 0:** on 8.5.0 over HTTP/2, a refused trailer ends the transfer 0, and
  the failure is `header-limit` with code 0. `test-headers`' table holds it per version, as it holds
  8.7.1's 56; no test may assert 23 there.
- **The longest head the cap takes depends on libcurl's rendering:** the status line counts as
  libcurl hands it, 13 bytes over HTTP/2 for `HTTP/2 200 \r\n`; and the refused call can be the
  head's own empty line, which leaves a stream with no head published. The docs' and the tests'
  edges come from that.
- **`test-conditions`' written-out reasons** take `header-limit` (the plan's §3.7 says the lists
  grow; it is not among the two cases §3.3 names).
- **`test-transfer`'s class table and its rule for reasons** (`table-class`) need `header-limit`
  beside `body-limit`, too-large whatever its code: today the rule gives every reason but
  `body-limit` and `perform-failed` the class `none`.
- **The varying 50,000-header case** answers `header-limit` 23 on every lane once the cap is in, so
  it is no longer a varying case: the rows file's rule, "each case has different answers in two
  rows at least", fails once its rows are updated, and the case moves to the shared answers or to
  `test-headers`, with the row files' five rows losing it.
- **The origin's raise is `maxSendHeaderBlockLength` alone** (item 3), and a test of HTTP/2
  trailers past 64 KiB must assert they arrived (the trap below).
- **The streamed path refuses with no head published** when the cap fires in the final head, and
  after publishing it when the cap fires in the trailers; the port raises `header-limit` either
  way, and `curl-token-head` answers `#f` in the first.
- **No Linux lane called the header callable after a refusal,** so "refuses every later call" is
  unreachable through libcurl on Linux, and a test of it there needs a planted path; the Mac may
  differ, as Apple's 8.7.1 did for the write callable (`stream-chunk!`'s comment).
- **Under the gate, a cap test of 1,000 lines costs about 25 ms more on 7.85.0** for the callable,
  beside the walk; the plan's consequence had only the native figure.
- **The comments that say the header callable is a streamed response's alone** (`transfer.sls`'s
  header, `read-head`'s, `set-transfer-options!`'s and the field table's) need rewriting; the
  prototype left them.

## The trap, for traps.md

**Node's HTTP/2 server drops a trailer block it cannot send, on Node 24.18.0.** With Node's default
`maxSendHeaderBlockLength`, 64 KiB, `sendTrailers` of a larger block fails with a frame error (type 1,
code 6, in the stand-in's events); Node 24.18.0 then closes the stream with code 0, and libcurl
ends the transfer 0 with a 200 and no trailers (8.20.0, `results/limits-none-guix-8.20.0-1.log`
and `-2.log`; 8.23.0, `results/limits-none-docker.log`; 7.85.0 under Node 24,
`results/limits-none-docker-floor-node24.log`). Node 20.10.0 resets the stream, `FRAME_SIZE_ERROR`:
7.85.0 ends 16 (`results/limits-none-docker.log`), 8.23.0 92
(`results/limits-none-docker-current-node20.log`). So the answer moves with Node, not libcurl, and
on Node 24 a test of large trailers passes as if the server sent none. Raise the send limit, and
assert the trailers' arrival, not a 200.

## How to rerun

From the repository's root, on the host; `W` is a `mktemp -d` directory under `build/m8s2/`:

```sh
W=$(mktemp -d build/m8s2/work.XXXXXX); R=.plans/research/m8/slice2
for t in main proto probe origin origin-send; do mkdir $W/$t; tar cf - --exclude=./build --exclude=./.git --exclude=./.plans/research . | (cd $W/$t && tar xf -); done
python3 $R/make-proto.py $W/proto; python3 $R/make-proto.py $W/probe --seam
python3 $R/make-proto.py $W/origin --origin-only --caps-limits; python3 $R/make-proto.py $W/origin-send --origin-only
for t in main proto probe; do mkdir -p $W/$t/m8s2; cp .plans/research/m8/caps/server.mjs $R/server-limits.mjs $R/engine-probe.sps $R/cost.sps $R/run-probe.sh $W/$t/m8s2/; done
# item 2, twice each: lane X, then lanes F, O, G and C
(cd $W/probe && taskset -c 12-17 scripts/guix-env sh m8s2/run-probe.sh guix-8.20.0 m8s2/engine-probe.sps < /dev/null) > $R/results/probe-guix-8.20.0-1.log 2>&1
CPUS=12-17 sh $R/lanes.sh $W probe probe floor openssl gnutls current > $R/results/probe-docker-1.log 2>&1
# the cost, lane F: native (101 rounds) and under the gate (15), main then the prototype, twice
CPUS=6-11 sh $R/lanes.sh $W cost main floor -- 101 > $R/results/cost-main-floor-1.log 2>&1
CPUS=6-11 VALGRIND=cost-vg-main-1 sh $R/lanes.sh $W cost main floor -- 15 > $R/results/cost-vg-main-floor-1.log 2>&1
# the stand-in's h2 limits, lane X: H2_LIMITS none, send, send,pairs or send,pairs,settings
(cd $W/probe && taskset -c 12-17 scripts/guix-env sh -c 'SERVER=m8s2/server-limits.mjs H2_LIMITS=send sh m8s2/run-probe.sh guix-8.20.0 m8s2/engine-probe.sps edge toward early suppress' < /dev/null) > $R/results/limits-send-guix-8.20.0.log 2>&1
# item 3: the HTTP/2 suites, the caps stand-in's limits (origin) and the send limit alone (origin-send)
S='tests/test-auth.sps tests/test-cookies.sps tests/test-curl-testing.sps tests/test-origin.sps tests/test-origin-tls.sps tests/test-proxy.sps tests/test-stream-call.sps tests/test-stream.sps tests/test-transfer-tls.sps tests/test-upload.sps tests/test-version.sps'
(cd $W/origin-send && taskset -c 12-17 scripts/guix-env make test SUITES="$S" < /dev/null) > $R/results/h2-origin-send-guix-8.20.0.log 2>&1
CPUS=6-11 SUITES="$S" TAG=h2-origin-send sh $R/lanes.sh $W test origin-send floor openssl gnutls current > $R/results/h2-origin-send-docker.log 2>&1
# item 4: make test on the prototype
(cd $W/proto && taskset -c 12-17 scripts/guix-env make test < /dev/null) > $R/results/test-proto-guix-8.20.0.log 2>&1
CPUS=6-11 TAG=proto sh $R/lanes.sh $W test proto floor openssl gnutls current > $R/results/test-proto-docker.log 2>&1
# the tables
python3 $R/tables.py $R/results > tables.md; python3 $R/limits.py $R/results > $R/results/limits-compare.txt
```

`lanes.sh` writes each lane's `make test` log to `$W/logs/test-TAG-LANE.log`, and Valgrind's log to
`$W/logs/`; they were copied into `results/`. A probe run takes about 5 s a lane, a lane's
`make test` about 470 s, its HTTP/2 suites about 270 s.

## Files

| file | what it is |
|---|---|
| `make-proto.py` | the prototype's edits, the seam's and the origin's |
| `proto.patch`, `seam.patch` | the prototype against `main`; the seam against the prototype |
| `engine-probe.sps` | item 2 through the engine: groups `edge`, `toward`, `early`, `suppress`, `options`, `hatch` |
| `cost.sps` | the cost, through `(curl)` alone |
| `server-limits.mjs` | the caps stand-in with its h2 limits from `H2_LIMITS` |
| `run-probe.sh` | one lane: the PKI, the stand-in, a program, natively or under the gate's Valgrind |
| `lanes.sh`, `lanes-in-docker.sh` | lanes F, O, G and C in Docker: `probe`, `cost` and `test` |
| `tables.py`, `limits.py` | the tables above, and the limits' comparison, from `results/` |
| `readme-src.md`, `maketest.md`, `assemble.py` | this README's text; `assemble.py` puts `tables.py`'s tables in it: `python3 assemble.py results > README.md` |
| `results/probe-docker-{1,2}.log`, `results/probe-guix-8.20.0-{1,2}.log` | item 2, every group, every lane |
| `results/cost-*.log`, `results/cost-vg-*.vg` | the cost, and Valgrind's logs |
| `results/limits-*.log`, `results/limits-compare.txt` | the stand-in's h2 limits, and the trap |
| `results/h2-origin*.log`, `results/test-h2-origin*.log` | item 3 |
| `results/test-proto-*.log` | item 4 |

## Checked by the session (2026-11-06)

- Lane X's probe, rerun: its 147 cells matched `results/probe-guix-8.20.0-1.log` line for line,
  times and ports set aside; `make test` on the prototype failed the same two suites.
- The Node trap, both halves rerun: Node 24.18.0 on Guix's 8.20.0, and Node 20.10.0 on 8.23.0 in
  Docker. The 417 trap: two runs under the gate and one native in its copy
  (`build/trap-417/logs-mine/`), one failing as the trap says.
- On the final tree: the CI main chain in the container, 42 suites; `check-memory-gate`, 45 cases;
  `make test-memory` of every added or changed suite; and four mutants of the session's own,
  each killed by `test-headers`: the count per response, a later call taken, the head's start
  dropped from the status-line rule, and that rule back to an `HTTP/` prefix.
- The Mac's `make test` at `dd6888c`, 2026-11-07: 42 of 42, `test-headers` 43 tests, its 8.7.1
  row matching in every cell ([log](mac/mac-8.7.1-make-test.log)).
