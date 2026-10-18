# Mutation log: M1 slice 1, the instrument and the drift guard

- **Date:** 2026-10-18, branch `m1/origin-and-drift`, on `83b6835`.
- **Records:** the [M1 plan](2026-10-18-m1-plan.md), [ADR-0005](decisions/0005-node-test-origin.md)
  (amended 2026-10-18), [ADR-0017](decisions/0017-drift-guard.md).
- **Parts:**
  1. the origin, the probe and their helpers, in the builder's three rounds;
  2. the drift guard and the floor build;
  3. what I checked myself, and the reviews.

Paths under `build/verify/` name scratch files, which are not kept. Where the coordinator's
own measurement differs from a builder's, part 3 says so.

---

# Part 1: the origin, the probe and their helpers


- **Date:** 2026-10-18, branch `m1/origin-and-drift`, on top of `83b6835`.
- **Where:** the Guix container (`scripts/guix-env`): Chez 10.4.0 threaded, Node v24.18.0,
  x86_64. Node 20.10.0: Docker `node:20.10.0-bookworm` (Debian 12, x86_64, gcc 12.2.0),
  with Chez 10.4.0 built by `scripts/ci/build-chez.sh`.
- **Scratch:** everything named here lives under `build/verify/m1/`: `measure/` (the
  measurement scripts and their outputs), `mutate.py` and `mutate-run.sh` (the mutation
  driver), `mut/<case>/` (each copy, its command, output and status), `node20-run.sh` and
  `node20-run.log`, `stop-final.log`, `time/`.

## 1.1 Measurements

### 1.1.1 What Node writes on the well-formed face

The origin, driven by the probe (`measure/wire.mjs`, `measure/http-cases.sh`), on Node
24.18.0 (`measure/http-bytes-node24.txt`) and 20.10.0 (`measure/http-bytes-node20.txt`).
With the pids and ports masked, the two files are **identical**: no header-order fix was
needed. `writeHead` takes an explicit header array, `sendDate` is off, and `Connection` is
always set explicitly, from Node's own `res.shouldKeepAlive`, so Node adds neither
`Connection` nor `Keep-Alive` itself. The suite holds these bytes, written by hand.

| Request (as sent) | Bytes Node writes (JSON string) | End |
|---|---|---|
| http "GET /status/200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" | eof |
| http "GET /status/204 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n" | eof |
| http "GET /status/205 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 205 Reset Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" | eof |
| http "GET /status/299 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 299 unknown\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 299\n" | eof |
| http "GET /status/304 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 304 Not Modified\r\nConnection: close\r\n\r\n" | eof |
| http "GET /status/404 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 404 Not Found\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 404\n" | eof |
| http "GET /status/418 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 418 I'm a Teapot\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 418\n" | eof |
| http "GET /status/503 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 503\n" | eof |
| http "GET /status/599 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 599 unknown\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 599\n" | eof |
| http "GET /redirect/300?to=%2Fstatus%2F200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 300 Multiple Choices\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 300\n" | eof |
| http "GET /redirect/301?to=%2Fstatus%2F200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 301 Moved Permanently\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 301\n" | eof |
| http "GET /redirect/302?to=%2Fstatus%2F200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 302 Found\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 302\n" | eof |
| http "GET /redirect/303?to=%2Fstatus%2F200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 303 See Other\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 303\n" | eof |
| http "GET /redirect/304?to=%2Fstatus%2F200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 304 Not Modified\r\nLocation: /status/200\r\nConnection: close\r\n\r\n" | eof |
| http "GET /redirect/305?to=%2Fstatus%2F200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 305 Use Proxy\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 305\n" | eof |
| http "GET /redirect/306?to=%2Fstatus%2F200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 306 unknown\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 306\n" | eof |
| http "GET /redirect/307?to=%2Fstatus%2F200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 307 Temporary Redirect\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 307\n" | eof |
| http "GET /redirect/308?to=%2Fstatus%2F200 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 308 Permanent Redirect\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 308\n" | eof |
| http "GET /chunked HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n6\r\nalpha\n\r\n5\r\nbeta\n\r\n6\r\ngamma\n\r\n0\r\n\r\n" | eof |
| http "POST /echo?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Two: a\r\nx-lower: b\r\nContent-Length: 4\r\nConnection: close\r\n\r\nbody" | "HTTP/1.1 200 OK\r\nContent-Length: 101\r\nConnection: close\r\n\r\nPOST /echo?x=1 HTTP/1.1\nHost: 127.0.0.1\nX-Two: a\nx-lower: b\nContent-Length: 4\nConnection: close\n\nbody" | eof |
| http "GET /nowhere HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n" | eof |
| http "GET /status/200 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" | "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: keep-alive\r\n\r\nstatus 200\n" | timeout |
| http "GET /status/200 HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n" | "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" | eof |
| http "garbage\r\n\r\n" | "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n" | eof |
| http "GET /redirect/302 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n" | eof |
| http "GET /status/600 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" | "HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n" | eof |
| raw "GET /raw/reset-mid-body HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" | "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" | reset |
| raw "GET /raw/stall-after-head HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" | "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n" | timeout |
| raw "GET /raw/drip?bytes=4&gap=25 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" | "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd" | eof |
| raw "GET /raw/nope HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" | "HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" | eof |

The raw face's bytes are the suite's own copy, not measured: the table in section 4 of
the plan, as `tests/test-origin.sps` writes them.

### 1.1.2 A reset mid-request: the probe's --reset (fix round)

`measure/destroy.mjs`: a client sends part of a request head, then closes. On both Node
24.18.0 and 20.10.0:

    destroy(): end (FIN) | resetAndDestroy(): error ECONNRESET

So plan section 5's probe, which ends with `destroy()`, could not be section 7's "reset
mid-request". The first round used a throwaway client the suite wrote. The coordinator
chose this instead:
- `wire-probe.mjs --reset` waits for the write callback, which means its bytes are with the
  kernel. It then calls `resetAndDestroy()` and prints `(reset-sent MS)` in place of an end
  line.
- `(curl-testing)` gains a sibling, `wire-probe-reset : Origin Symbol Bytevector -> Probe`.
  `wire-probe`'s shape is unchanged, and `parse-wire-probe` reads `(reset-sent MS)` as the
  end `reset-sent`.
- The throwaway client is gone.
- `test-curl-testing` holds the reset to a RST with a stand-in that records how the last
  connection ended. After `wire-probe-reset` it reports `ECONNRESET`, and after a plain
  probe's timeout `FIN`. Mutation y-reset-fin turns the first into `FIN`.
- Mutation f, rerun, fails through the new route.

### 1.1.3 Chez's process ports (`measure/ports.sps`, `measure/exec-redirect.sps`)

- `open-process-ports "exec CMD"`: the pid it answers is CMD's, since `exec` keeps the pid.
- `input-port-ready?` on its binary stdout port is `#f` with no data and `#t` at the end,
  so a bounded wait polls it, 10 ms apart, against the monotonic clock. Nothing waits for
  a reap.
- A child of `open-process-ports` holds only fds 0, 1 and 2. A child of `system` (so, of
  `capture-command`) also holds the parent's ends of every open-process-ports pipe (here
  fds 4, 5 and 7). A probe therefore holds the origin's stdin open while it runs. The
  child Chez of the SIGKILL check is spawned with open-process-ports for that reason.
- `exec CMD 2>FILE`: when CMD is not found, the shell's own message goes into FILE.
  call-with-origin sends the origin's stderr to a file, so reading it never blocks.

### 1.1.4 The Node 20.10.0 run (`node20-run.log`, the final run)

    v20.10.0
    image: Debian GNU/Linux 12 (bookworm) x86_64
    build-chez.sh: Chez 10.4.0 built --threads into /opt/chez: (10 4 0 yes)
    pass tests/test-origin.sps (5s)        # of expected passes 100
    pass tests/test-curl-testing.sps (5s)  # of expected passes 137

That is the fix round's rerun, after the probe's `--reset` and `@FILE` and the 64 KiB
checks. The first round's run gave 95 and 130.

The tree was mounted read-only and copied in without `.git`, `build` or `.claude`, with the
`vendor/chez-srfi` checkout. The container fetched only Chez's tarball.

### 1.1.5 Times

| What | Time |
|---|---|
| `tests/test-origin.sps`, container | 6.8 s (100 tests, about 95 probes, each a Node start) |
| `tests/test-curl-testing.sps`, container | 5.8 s, from 1.3 s at HEAD (137 tests, from 54) |
| `tests/test-check-floors.sps`, container | 3.5 s (330 tests) |
| `make test`, all 16 suites, container | about 22 s with the checks before it |
| `make check-test-fails` at HEAD, a copy of HEAD | 12.93 s, 12.95 s |
| `make check-test-fails` with this change, a copy | 13.25 s, 13.22 s |
| `MEMORY_SUITES="tests/test-origin.sps tests/test-curl-testing.sps" make test-memory` | 74 s; 65 s in the fix round |

`check-test-fails` deletes every real suite in its copy, so `test-origin`'s time is never
multiplied there. Its 0.3 s comes from the larger copy and `require-tools` looking up Node
in each of its ten `make test` runs. Both copies were timed back to back in one container
(`time/summary.txt`).

### 1.1.6 Flakiness

`test-origin` passed 10 times in a row, and 4 copies run at once all passed. The tightest
margin is the drip's spread: 76 ms seen against a bound of 75. The origin's `pause` rearms
its timer until `performance.now()` shows the whole gap, since a Node timer can fire early
by the loop's cached time. The probe floors its times, and floor(b) - floor(a) >= S
whenever b - a >= S for a whole S. So the bound holds unless the probe handles the first
byte late.

### 1.1.7 The stop condition (`stop-final.log`)

    check-suites: every suite ends with (exit (suite-exit-status runner)) (16 checked)
    check-seam: the seam holds (10 libraries in 10 files checked)
    check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
    test: ran 16, passed 16, failed 0, hung 0
    check-test-fails: make test failed, as it must, in all 10 cases
    test-memory: ran 2, passed 2, failed 0, hung 0
    check-action-pins: all 20 lines with a uses key under .github/workflows name a full commit SHA, with its tag in a comment
    actionlint: exit 0, no findings

`actions/setup-node` v7.1.0 is commit `949feb2413d6458794dcd2491c4babbbce0c15c1`, from
`git ls-remote`: a lightweight tag, with no `^{}` line.

The fix round's stop condition (`stop-fix-round.log`), with the drift guard's
`test-drift.sps` now in the tree:

    check-suites: every suite ends with (exit (suite-exit-status runner)) (17 checked)
    test: ran 17, passed 17, failed 0, hung 0
    test-memory: ran 2, passed 2, failed 0, hung 0

### 1.1.8 Bytes from a file, and the 64 KiB head limit (fix round)

- **@FILE.** The probe accepts `@FILE` in HEX's place, and reads the whole file as the hex
  digits. `wire-probe` passes bytes in the argument up to `probe-argument-bytes`, which is
  **16384 bytes** (32 KiB of hex, a quarter of Linux's 128 KiB per argument,
  MAX_ARG_STRLEN). Beyond that it writes the hex to `$TMPDIR/curl-testing-PID-N.hex` and
  removes it after. Both paths are tested: an echo of 16384 bytes and one of 16385 come
  back whole, with `TMPDIR` a fresh directory that is empty afterwards. Mutation
  y-never-file shows a 65536-byte head cannot travel in the argument: `system`'s shell
  never runs, and capture-command raises "the shell did not create a capture file".
- **The limit, from both sides** (`test-origin`). Each head is padded to its size, the
  padding counted from the text around it:
  - exactly 65536 bytes, CRLF CRLF included: served, `content-length`'s bytes then eof;
  - 65537 bytes, CRLF CRLF included: the fixed 400;
  - 65536 bytes with no CRLF CRLF, the most the head may hold: the fixed 400;
  - 70000 bytes with no CRLF CRLF: the fixed 400.

  Mutation y-limit-1 (a limit of 64 KiB − 1) fails the first test, and y-limit-gt (`>` for
  `>=`) fails the third.
- **204, 304 and 205:** kept as built, as the coordinator confirmed.

## 1.2 Mutations

Each case is a plain copy of the tree, made by `mutate.py` without `.git`, `build` or
`.claude`, with exactly one edit. The driver refuses an edit whose text it does not find
exactly once. `mutate-run.sh` runs each case's command in the container and then kills any
process whose working directory is in that copy. The baseline copy, unmutated, passes
every command. Cases a to q are the brief's list. The `x-` cases add one for each check
that none of those reaches. The `y-` cases are the fix round's: the probe's `--reset` and
`@FILE`, the helper's file, and the 64 KiB limit. f was rerun through `--reset`. Every row
was rerun against the final code: 61 cases, 8.5 minutes. A "check" here means one test form or one table of rows. A
group of the raw face that (g) samples counts as reached; "tolerated" is no group of (g),
so `x-bare-lf` covers it. c and o are one planting, since the origin cannot tell stdin
ending from its suite dying. The table names, for (o), the SIGKILL check's failure.

| Case | Mutation | Failing test (failures in all) | Output (at most 3 lines) |
|---|---|---|---|
| baseline | no mutation: every command below must pass here | none: every command passes | # of expected passes      100<br># of expected passes      137<br># of expected passes      330 (exit 0, 17 s) |
| a | the raw face bound to 0.0.0.0 | loopback only: every face's announced address is 127.0.0.1 (2) | expected: ("127.0.0.1" "127.0.0.1")<br>actual:   ("127.0.0.1" "0.0.0.0") (exit 1, 13 s) |
| b | the http face on a fixed port, 40123 | OS ports: two origins at once announce four ports, none 0 and all different, and both serve (1) | expected: (returned (distinct (("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof) ("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200…<br>actual:   (raised "Exception in call-with-origin: the origin's stdout ended before its announcement with irritants ((stdout . \"\") (stderr . \"origin: the http face fai… (exit 1, 7 s) |
| c-o | stdin's end ignored (cases c and o: one planting, two checks) | the scenarios' origin starts, serves them all, and stops (5); for (o): it cannot outlive its suite: a child Chez that started it is killed with SIGKILL, and within 5 s every face refuses connections | expected: (returned done)<br>actual:   (raised "Exception in call-with-origin: the origin's stdout did not end within 5000 ms of its stdin closing, so it was killed with irritants ((stdout . \"\") (… (exit 1, 67 s) |
| d | the announcement gives the requested port, 0 | raw /raw/content-length: the whole bytes, then eof (91) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)<br>actual:   ("" (refused "ECONNREFUSED")) (exit 1, 6 s) |
| e | a stray stdout line before the announcement | the scenarios' origin starts, serves them all, and stops (5) | expected: (returned done)<br>actual:   (raised "Exception in call-with-origin: the origin's announcement is malformed: an announcement is one JSON object, from { to } with irritants ((stdout . \"sta… (exit 1, 1 s) |
| f | no 'error' handler on raw sockets | a bad client: a reset mid-request on the raw face ends only its connection, and the next request is served (3) | expected: (("" reset-sent) ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))<br>actual:   (("" reset-sent) ("" (refused "ECONNREFUSED"))) (exit 1, 6 s) |
| g-framing | one byte changed in content-length | raw /raw/content-length: the whole bytes, then eof (5) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhellp\n" eof) (exit 1, 7 s) |
| g-drips | one byte changed in drip's head | raw /raw/drip?bytes=4&gap=25: the whole bytes, then eof, the last body byte at least 75 ms after the first (4) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd" eof spread-enough)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Lenght: 4\r\n\r\nabcd" eof spread-enough) (exit 1, 7 s) |
| g-oversized | one byte changed in big-header | raw /raw/big-header?bytes=5: the whole bytes, then eof (2) | expected: ("HTTP/1.1 200 OK\r\nX-Big: aaaaa\r\n\r\n" eof)<br>actual:   ("HTTP/1.1 200 OK\r\nX-Bog: aaaaa\r\n\r\n" eof) (exit 1, 7 s) |
| g-errors | one byte changed in bad-chunk-size | raw /raw/bad-chunk-size: the whole bytes, then eof (1) | expected: ("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nhello\n\r\n0\r\n\r\n" eof)<br>actual:   ("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzy\r\nhello\n\r\n0\r\n\r\n" eof) (exit 1, 7 s) |
| g-echo | one byte changed in echo's status line | raw /raw/echo: the request head's exact bytes as the body, and nothing sent after the head (1) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 60\r\n\r\nGET /raw/echo HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Spaced:  a b \r\n\r\n" eof)<br>actual:   ("HTTP/1.1 201 OK\r\nContent-Length: 60\r\n\r\nGET /raw/echo HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Spaced:  a b \r\n\r\n" eof) (exit 1, 6 s) |
| h | short-body ends with RST, not FIN | raw /raw/short-body: the whole bytes, then eof (1) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" eof)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" reset) (exit 1, 7 s) |
| i | the drip without its wait | raw /raw/drip?bytes=4&gap=25: the whole bytes, then eof, the last body byte at least 75 ms after the first (3) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd" eof spread-enough)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd" eof (spread 0 ((0 . 2) (38 . 2) (40 . 2) (41 . 2)))) (exit 1, 7 s) |
| j | sendDate left on | http /status/200: the whole bytes Node writes, then eof (34) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" eof)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\nDate: Sun, 18 Oct 2026 09:45:37 GMT\r\n\r\nstatus 200\n" eof) (exit 1, 7 s) |
| k | 307 without its Location | http /redirect/307: the whole bytes Node writes, then eof (1) | expected: ("HTTP/1.1 307 Temporary Redirect\r\nLocation: /status/200\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 307\n" eof)<br>actual:   ("HTTP/1.1 307 Temporary Redirect\r\nContent-Length: 13\r\nConnection: close\r\n\r\nredirect 307\n" eof) (exit 1, 7 s) |
| l | the probe drops its first data chunk | raw /raw/content-length: the whole bytes, then eof (92) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)<br>actual:   ("" eof) (exit 1, 13 s) |
| m | the probe reports a reset as eof | raw /raw/reset-mid-body: the whole bytes, then reset (1) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" reset)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" eof) (exit 1, 7 s) |
| n-duplicate | read-announcement accepts a duplicate key | read-announcement refuses "{\"a\":1,\"a\":2}": a duplicate key (1) | expected: (read-announcement "a duplicate key" ("{\"a\":1,\"a\":2}" 7))<br>actual:   no-raise (exit 1, 6 s) |
| n-trailing | read-announcement accepts trailing text | read-announcement refuses "{} ": text after the object (4) | expected: (read-announcement "text after the object" ("{} " 2))<br>actual:   no-raise (exit 1, 6 s) |
| p | NODE names no file | make exits 2, no suite runs | make test: /no/such/node not found. (exit 2, 1 s) |
| q | a literal node-version in ci.yml | make exits 2, no suite runs | check-floors: .github/workflows/ci.yml: line 229 names node-version, but is not "node-version: ${{ steps.ID.outputs.NAME }}": the Node floor comes from packaging/floors.…<br>check-floors: FAILED (problems: 1) (exit 2, 0 s) |
| x-400-range | drip's bytes range widened to 4097 | raw: the fixed 400 for drip bytes=4097, above its range (1) | expected: ("HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 4097\r\n\r\nabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdef… (exit 1, 12 s) |
| x-ann-empty | read-announcement refuses {} | read-announcement: an empty object, a zero, an empty string and text beyond ASCII (3) | expected: (() (("a" . 0) ("" . "") ("ké" . "λ")))<br>actual:   (raised "Exception in read-announcement: a key is a string with irritants (\"{}\" 1)") (exit 1, 6 s) |
| x-ann-string | read-announcement does not check its argument | read-announcement: its argument is a string (1) | expected: (assertion-violation read-announcement (5))<br>actual:   (assertion-violation string-length (5)) (exit 1, 5 s) |
| x-ann-values | read-announcement keeps each key as its value | read-announcement: the origin's announcement, its entries in order (22) | expected: (("node" . "v24.18.0") ("pid" . 12345) ("http" . "127.0.0.1:40001") ("raw" . "127.0.0.1:40002"))<br>actual:   (("node" . "node") ("pid" . "pid") ("http" . "http") ("raw" . "raw")) (exit 1, 5 s) |
| x-bare-lf | bare-lf with one CRLF | raw /raw/bare-lf: the whole bytes, then eof (1) | expected: ("HTTP/1.1 200 OK\nContent-Length: 6\n\nhello\n" eof)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 6\n\nhello\n" eof) (exit 1, 7 s) |
| x-chez | CHEZ unset | CHEZ names the Chez to spawn (2) | expected: set<br>actual:   unset (exit 1, 6 s) |
| x-cleanup | call-with-origin stops the origin only when PROC returns | call-with-origin: when PROC raises, the raise goes on unchanged, and the origin has exited (2) | expected: (boom ((refused "ECONNREFUSED") (refused "ECONNREFUSED")))<br>actual:   (boom (eof eof)) (exit 1, 6 s) |
| x-deadline | read-until reports its deadline as the port's end | call-with-origin raises when no announcement comes within origin-timeout (2) | expected: (call-with-origin "the origin wrote no announcement within 500 ms" ((stdout . "") (stderr . "")))<br>actual:   (call-with-origin "the origin's stdout ended before its announcement" ((stdout . "") (stderr . ""))) (exit 1, 5 s) |
| x-face-origin | origin-face does not check its origin | origin-face: what is not an origin raises (1) | expected: (assertion-violation origin-face (not-an-origin))<br>actual:   (assertion-violation origin-faces (not-an-origin #<record type origin>)) (exit 1, 6 s) |
| x-face-unknown | origin-face answers #f for an unknown face | origin-face: an unknown face raises, by name (3) | expected: (assertion-violation origin-face (https))<br>actual:   no-raise (exit 1, 6 s) |
| x-floors-canonical | check-floors refuses the one form it should take | workflow: node-version from a step's output: nothing to report (3) | expected: (returned ())<br>actual:   (returned ("W/ci.yml: line 13 names node-version, but is not \"node-version: ${{ steps.ID.outputs.NAME }}\": the Node floor comes from f.sexp, through a step t… (exit 1, 4 s) |
| x-floors-comment | check-floors takes a node-version with a comment after it | workflow: node-version from a step's output, with a comment after it: named (1) | expected: (returned ("W/ci.yml: line 13 names node-version, but is not \"node-version: ${{ steps.ID.outputs.NAME }}\": the Node floor comes from f.sexp, through a step t…<br>actual:   (returned ()) (exit 1, 4 s) |
| x-http-garbage | the http face drops garbage without Node's 400 | http garbage, which Node refuses: the whole bytes Node writes, then eof (1) | expected: ("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n" eof)<br>actual:   ("" eof) (exit 1, 7 s) |
| x-http-reset | the http face dies on a client reset | a bad client: a reset mid-request on the http face ends only its connection, and the next request is served (2) | expected: (("" reset-sent) ("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n" eof))<br>actual:   (("" reset-sent) ("" (refused "ECONNREFUSED"))) (exit 1, 7 s) |
| x-noargs | arguments accepted | it takes no arguments: one exits 2, naming it on stderr, and nothing on stdout (1) | expected: (2 "" "origin: it takes no arguments, and was given [\"--pki\",\"dir\"]\n")<br>actual:   (0 "{\"node\":\"v24.18.0\",\"pid\":69463,\"http\":\"127.0.0.1:38921\",\"raw\":\"127.0.0.1:44503\"}\n" "") (exit 1, 7 s) |
| x-node-version | node announced without its v | the announcement's node is the version the Node that ran it reports (1) | expected: (0 "24.18.0\n" "")<br>actual:   (0 "v24.18.0\n" "") (exit 1, 7 s) |
| x-nokill | an origin that does not exit is not killed | call-with-origin: an origin that ignores stdin's end is killed after origin-timeout, and the raise says so; until then it served (1) | expected: ((call-with-origin "the origin's stdout did not end within 1000 ms of its stdin closing, so it was killed" ((stdout . "") (stderr . ""))) ("deaf\n" eof) ((refu…<br>actual:   ((call-with-origin "the origin's stdout did not end within 1000 ms of its stdin closing, so it was killed" ((stdout . "") (stderr . ""))) ("deaf\n" eof) (eof e… (exit 1, 6 s) |
| x-param | origin-timeout takes anything | origin-script and origin-timeout refuse what they cannot use (1) | expected: ((assertion-violation origin-script ("")) (assertion-violation origin-timeout (0)) (assertion-violation origin-timeout (1.5)))<br>actual:   ((assertion-violation origin-script ("")) no-raise no-raise) (exit 1, 6 s) |
| x-parse-arrivals | parse-wire-probe swaps offset and time | wire-probe: the whole bytes, the end, and arrivals from offset 0 that account for every byte (2) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof 0 counted)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof 2 counted) (exit 1, 6 s) |
| x-parse-error | parse-wire-probe drops an error end's code | parse-wire-probe: each other end: reset, timeout, an error with its code, a reset sent, and a refusal (1) | expected: (reset timeout (error "EPIPE") reset-sent (refused "ECONNREFUSED"))<br>actual:   (reset timeout error reset-sent (refused "ECONNREFUSED")) (exit 1, 6 s) |
| x-parse-offset | parse-wire-probe does not check offsets | parse-wire-probe refuses an offset that skips a byte (2) | expected: (parse-wire-probe "a data line's offset is not the count of bytes before it" ((data 2 1 "62")))<br>actual:   no-raise (exit 1, 6 s) |
| x-parse-string | parse-wire-probe does not check its argument | parse-wire-probe: its argument is a string (1) | expected: (assertion-violation parse-wire-probe (5))<br>actual:   (parse-wire-probe "the probe's output is not Scheme data" (5)) (exit 1, 5 s) |
| x-pid | pid announced as the parent's | the announcement's pid names a live process, and not this Chez, which spawned it (1) | expected: ((0 "" "") another)<br>actual:   ((0 "" "") this-chez) (exit 1, 7 s) |
| x-port-range | a face port of 65536 accepted | call-with-origin raises on a malformed announcement: its raw face is not ADDRESS:PORT (1) | expected: (call-with-origin "the origin's announcement is malformed: its raw face is not ADDRESS:PORT" ((stdout . "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1:1\",\"…<br>actual:   no-raise (exit 1, 6 s) |
| x-probe-idle | wire-probe does not check its idle bound | wire-probe refuses an unknown face, bytes that are not a bytevector, and an idle bound that is not positive (1) | expected: ((assertion-violation origin-face (https)) (assertion-violation wire-probe ("GET")) (assertion-violation wire-probe (0)))<br>actual:   ((assertion-violation origin-face (https)) (assertion-violation wire-probe ("GET")) (wire-probe "the probe did not exit 0" (2 "wire-probe: IDLE-MS is \"0\", no… (exit 1, 5 s) |
| x-probe-refused | the probe reports a refusal as an error end | call-with-origin: once PROC returns, the origin has exited, so every face refuses (5) | expected: (((refused "ECONNREFUSED") (refused "ECONNREFUSED")))<br>actual:   (raised "Exception in parse-wire-probe: the first line is (connected MS) or (refused \"CODE\" MS) with irritant (end error 1 \"ECONNREFUSED\")") (exit 1, 5 s) |
| x-proc | call-with-origin does not check PROC | call-with-origin: PROC is a procedure (1) | expected: (assertion-violation call-with-origin (proc))<br>actual:   (other-condition "Exception: attempt to apply non-procedure proc") (exit 1, 6 s) |
| x-second-line | a second line read with the announcement accepted | call-with-origin raises on an origin that writes a second line with its announcement (1) | expected: (call-with-origin "the origin wrote to stdout after its announcement" ((stdout . "{\"node\":\"v1\",\"pid\":1,\"http\":\"127.0.0.1:1\",\"raw\":\"127.0.0.1:2\"}\…<br>actual:   no-raise (exit 1, 6 s) |
| x-stderr | the raise leaves out the origin's stderr | call-with-origin raises, with stderr, on an origin that dies before announcing (2) | expected: (call-with-origin "the origin's stdout ended before its announcement" ((stdout . "") (stderr . "dying early\n")))<br>actual:   (call-with-origin "the origin's stdout ended before its announcement" ((stdout . "") (stderr . ""))) (exit 1, 5 s) |
| x-trailing | stdout after the announcement unchecked once PROC returns | call-with-origin raises once PROC returns when the origin wrote to stdout after its announcement (1) | expected: (call-with-origin "the origin wrote to stdout after its announcement" ((stdout . "goodbye\n") (stderr . "")))<br>actual:   no-raise (exit 1, 6 s) |
| x-vanish | a write to a client that went is fatal | a bad client: one that vanishes during a drip ends only its connection, and the next request is served (1) | expected: (("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n" timeout) ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))<br>actual:   (("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n" timeout) ("" (refused "ECONNREFUSED"))) (exit 1, 7 s) |
| y-file-hex | the probe drops the last byte of an @FILE | raw: a head of exactly 65536 bytes, CRLF CRLF included, is read and served (4) | expected: (65536 ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))<br>actual:   (65536 ("" timeout)) (exit 1, 18 s) |
| y-hex-kept | the helper leaves its hex file behind | wire-probe: 16384 bytes go in the probe's argument, 16385 through a file, and both arrive whole; the file is removed (1) | expected: ((16384 same eof) (16385 same eof) ())<br>actual:   ((16384 same eof) (16385 same eof) ("curl-testing-98983-1.hex")) (exit 1, 6 s) |
| y-limit-1 | the head limit one byte short, 64 KiB - 1 | raw: a head of exactly 65536 bytes, CRLF CRLF included, is read and served (1) | expected: (65536 ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))<br>actual:   (65536 ("HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof)) (exit 1, 7 s) |
| y-limit-gt | the head limit checked with > for >= | raw: 65536 bytes with no CRLF CRLF, the most the head may hold, get the fixed 400 (1) | expected: ("HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof)<br>actual:   ("" timeout) (exit 1, 9 s) |
| y-never-file | the helper always passes the hex in the argument | raw: a head of exactly 65536 bytes, CRLF CRLF included, is read and served (4) | expected: (65536 ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))<br>actual:   (65536 (raised "Exception in capture-command: the shell did not create a capture file with irritant \"/tmp/curl-testing-104201-50.out\"")) (exit 0, 13 s) |
| y-probe-usage | the probe takes an unreadable @FILE as no bytes | the probe refuses a usage error with exit 2, its problem and its usage on stderr (1) | expected: ((2 "" "wire-probe: it takes 4 arguments after any --reset, and was given 3\nusage: node tests/wire-probe.mjs [--reset] HOST PORT HEX IDLE-MS\n") (2 "" "wire-p…<br>actual:   ((2 "" "wire-probe: it takes 4 arguments after any --reset, and was given 3\nusage: node tests/wire-probe.mjs [--reset] HOST PORT HEX IDLE-MS\n") (2 "" "wire-p… (exit 1, 7 s) |
| y-reset-fin | the probe's --reset ends with destroy(), a FIN | wire-probe-reset: the peer sees a reset, ECONNRESET, where wire-probe's end is a FIN (1) | expected: ((reset-sent ("ECONNRESET\n" eof)) (timeout ("FIN\n" eof)))<br>actual:   ((reset-sent ("FIN\n" eof)) (timeout ("FIN\n" eof))) (exit 1, 13 s) |
| y-reset-sent-kind | parse-wire-probe reads (reset-sent MS) as eof | wire-probe-reset: the probe sends, then resets, so its end is reset-sent, with nothing received (5) | expected: (#vu8() reset-sent ())<br>actual:   (raised "Exception in caddr: incorrect list structure (reset-sent 2)") (exit 1, 6 s) |

## 1.3 Traps hit and reproduced

- **A test inside another test's actual expression takes over its report.** SRFI-64 keeps
  one result record per runner. A `test-equal` run inside another's actual expression
  overwrites that test's name and expected value, so the outer verdict is reported under
  the last inner test's name. The first c-o run reported the scenarios' origin failing as
  "FAIL a bad client: one that vanishes during a drip". Reproduced alone
  (`measure/nested.sps`): an outer test that fails, holding an inner one that passes,
  prints `FAIL inner, which passes`, and the outer name is never printed. The fix runs the
  scenarios in a definition and tests its outcome after.
- **`(curl-testing)`'s exports land in every suite that imports it whole.** Its first
  `probe` broke `test-library-loading`, which defines its own `probe`: "multiple
  definitions for probe in body", exit 255. The exports are now `wire-probe` and
  `parse-wire-probe`.
- **A test of a parameter's filter must use `parameterize`.** Called as `(p 0)`, it sets
  the parameter whenever the filter takes the value. Under x-param, that broke 21 later
  tests.
- **Watching each check fail found two of my own holes.** The two tests that run
  `origin.mjs` straight through `capture-command` would have hung, not failed, on an origin
  that ignores stdin's end. They now run under a 10 s SIGKILL watchdog, and fail with
  status 137. And "the pid names a live process" passed `process.ppid`, the Chez that
  spawned it. It now also requires a pid other than this Chez's.

## 1.4 For the records

- **ADR-0005's amendment and global-constraints:**
  - Node 20.10.0 and 24.18.0 write the same bytes for every well-formed response measured.
  - The probe's `destroy()` reaches the origin as a FIN. A reset mid-request needs
    `resetAndDestroy()`.
  - `setup-node` v7.1.0 is pinned at commit `949feb24…`.
  - The Node 20.10.0 run passed, as in 1.4.
- **A rule check-floors now holds:** `node-version` is written only as
  `node-version: ${{ steps.ID.outputs.NAME }}`. Its limit: it holds the form, not the step
  behind it, so a step that echoes `version=22` passes.
- **The plan:**
  - §7's "reset mid-request" now comes from §5's probe, with `--reset` (1.2).
  - §5's probe also takes `@FILE`, and §4's 64 KiB limit is checked from both sides (1.8).

## 1.5 Open

- **`origin-timeout`, 5 s, bounds both the announcement and the exit.** Nothing under
  Valgrind needed more: Node runs outside it.

## 1.6 Round 3: the review (2026-10-18)

An Opus review found ten gaps; the coordinator reproduced the main ones. Each is closed as
a class. The rows below are this round's, run against the final code from fresh copies
(`mutate3.py`, `mut3/`); the earlier rounds' rows above are kept as recorded.

### 1.6.1 What changed

1. **The origin's end of life, by evidence.**
   - `call-with-origin` now runs Node under a runner shell (`origin-runner`). The shell starts
     Node in the background on its own stdin (fd 3), records Node's pid (`$!`) in a file,
     `wait`s for it, and writes its exit status to a file.
   - The shell holds the stdout pipe until it exits, so stdout's end means the status is
     written. The kill path kills Node by its recorded pid, then the shell if need be.
   - Once PROC returns, every one of these must hold: stdout ended within the bound;
     nothing after the announcement; nothing on stderr; status 0.
   - Every raise carries `(stdout . TEXT) (stderr . TEXT) (status . N)`, 4096 bytes of
     each at most.
   - When PROC raises or escapes, cleanup stops the origin once, never raises, and PROC's
     raise goes on. The temporary directory's removal is guarded too.
   - The announced pid must equal the recorded one: a stand-in announcing pid 1 is
     refused.
2. **Every wait is bounded by the clock.**
   - `read-until` reads the monotonic clock before every read and joins its pieces once.
     It keeps 4096 bytes, so a flood costs no memory. It is exported as `read-within`.
   - The announcement gives up at 4096 bytes without a newline.
   - The SIGKILL test loops on a 5000 ms deadline from the kill, checked before each
     round of probes, so its name's 5 s holds.
   - `read-line-within` and `read-to-end-within` are built on `read-within`.
   - The child Chez exits after 30 s on its own.
   - Same class, closed too: the probe's only bound was IDLE-MS, which every byte rearms.
     It now has `--deadline MS` (default 30000), ending `(end deadline MS)`.
     `wire-probe-deadline` is a parameter, and every helper passes it.
3. **No helper outlives its call.**
   - `bounded` now execs GNU `timeout -s KILL 10` (`gtimeout` on macOS), which waits for
     its command and leaves nothing behind. The subshell's `sleep 10` had been orphaned
     (ppid 1), holding the caller's pipes.
   - A test runs `bounded` with a pipe as its stdout. The pipe must end within 2000 ms.
   - Who spawns what:
     - probes and commands go through `capture-command`, which waits for them;
     - the origin goes through `open-process-ports`, whose children hold no other pipe;
     - the open-at-stop probe and the child Chez go through `open-process-ports`, and are
       killed in a dynamic-wind;
     - stand-ins are stopped or killed by `call-with-origin`.
4. **Stopping destroys open connections.** The new test: a probe still connected on
   `stall-before-head` when PROC returns, spawned through `open-process-ports`. It must
   see eof, and `call-with-origin` must return within 2000 ms.
5. **Half-close.**
   - The raw face is `allowHalfOpen: true`. A script that is playing goes on after the
     client's FIN. Once the script has ended or stalls, the FIN closes the connection.
   - The probe has `--half-close`, and `(curl-testing)` has `wire-probe-half-close`.
   - Tests: a raw drip, raw content-length and http `/status/200`, each served whole, then
     the next request.
   - A stand-in holds the probe to its FIN: it answers "saw FIN" only when one comes.
6. **Drips.** Kept: the coordinator's bounds from the connect time and on half the spread.
   Added:
   - each body byte i arrives at least (i+1)×gap after `probe-connected`;
   - on the 25 ms row only, each body byte is its own arrival.
7. **Edges accepted.**
   - `drip?bytes=4096&gap=5000` with idle 300: the head, then timeout.
   - `big-header?bytes=1`, beside the existing 1048576.
   - `many-headers?count=1`, beside the existing 100000.
8. **Loopback by connection on Linux.** Linux is any `(machine-type)` ending in `le`.
   There, each face must refuse `127.0.0.2:PORT`. Elsewhere `test-skip` applies, and the
   reason is in the name.
9. **check-floors.**
   - `node-version` is matched ignoring case, quoted or not.
   - Fail-closed: any double-quoted key holding a backslash is named, since YAML reads
     escapes that this check does not.
   - Four fixtures, copied from `cf/v*`, and pure rows.
10. **Wording.** `test-origin`'s header cites `.plans/instrument-mutation-log.md`. Both
    `.mjs` files say "Node 20 and later (measured on 20.10.0 and 24.18.0)".

### 1.6.2 Measured this round

- Chez reaps an exited `open-process-ports` child: `kill -0` on its pid then fails. The
  old "zombie" premise does not hold at 10.4.0.
- `dash`'s `$!` for a background simple command is the command's own pid.
- `dash`'s `wait` prints `Killed` to stderr for a job that SIGKILL ended. Debian, in Docker,
  showed it in the origin's stderr evidence; Guix's `sh`, bash, prints nothing. The runner's
  own stderr now goes to `/dev/null`, and Node's has its own redirection, so a NODE that is
  not found still reports: `sh: line 2: /no/such/node: No such file or directory`, status
  127.
- A flood through a pipe cannot keep `input-port-ready?` true against a linear reader.
  Node writing asynchronously, or with `writeSync` retried on EAGAIN (Node's stdout pipe
  is non-blocking), still left the pipe empty now and then. `z-flood-deadline` passed both
  ways.
- A custom port raises "cannot determine ready status". `/dev/zero` is always ready, so
  the deadline's place is checked there, in a child Chez under `timeout`.
- The reviewer's own scripts, against this code: `flood.sps` raised in 1062 ms
  (`flood-after`) and 1066 ms (`flood-before`); `open-at-stop.sps` returned in 581 ms, its
  probe at `(end eof 467)`; `halfclose.sps` got each response whole.
- Times in the container:
  - `test-origin` 8.1 s, 109 tests;
  - `test-curl-testing` 11.0 s, 157 tests;
  - `test-check-floors` 342 tests;
  - `test-memory` for the two suites took 94 s.
- Node 20.10.0 in Docker: 109 and 157 pass.
- The stop condition (`stop-round3.log`): 17 of 17 suites; `check-test-fails` 10 of 10;
  `test-memory` 2 of 2.

### 1.6.3 Mutations, round 3

| Case | Mutation | Failing test (failures in all) | Output (at most 3 lines) |
|---|---|---|---|
| baseline | no mutation: every command below must pass here | none: every command passes | # of expected passes      109<br># of expected passes      157<br># of expected passes      342<br>check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20) (exit 0, 23 s) |
| z-lastcrash | the origin throws 20 ms after the scenarios' last content-length (its 7th) | a half-closing client: http /status/200, sent with a FIN after it, gets the whole response, and the next request is served (2) | expected: (("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: keep-alive\r\n\r\nstatus 200\n" eof) ("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r…<br>actual:   (("" (refused "ECONNREFUSED")) ("" (refused "ECONNREFUSED"))) (exit 1, 8 s) |
| z-exit1 | the origin exits 1, with stderr, at stdin's end once it has had a connection | the scenarios' origin starts, serves them all, and stops (3) | expected: (returned done)<br>actual:   (raised "Exception in call-with-origin: the origin did not end cleanly: it wrote to stderr; it exited 1 with irritants ((stdout . \"\") (stderr . \"origin: die… (exit 1, 8 s) |
| z-nodestroy | stopping leaves open connections open | stopping destroys open connections: a probe still connected on stall-before-head when PROC returns sees eof, and call-with-origin returns within 2000 ms (1) | expected: (returned (connected returned-within-2000-ms eof))<br>actual:   (raised "Exception in call-with-origin: the origin's stdout did not end within 5000 ms of its stdin closing, so it was killed with irritants ((stdout . \"\") (… (exit 1, 18 s) |
| z-drippairs | the drip sends its bytes in pairs, after a double wait | raw /raw/drip?bytes=4&gap=25: the whole bytes, then eof, the last body byte at least 100 ms after connecting and half of 75 ms after the first (1) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd" eof late-enough spread-enough each-late-enough own-arrivals)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd" eof late-enough spread-enough each-late-enough (shared-arrivals ((0 . 2) (38 . 53) (39 . 53) (40 . 103)))) (exit 1, 8 s) |
| z-anybind | the faces bind 0.0.0.0 and announce 127.0.0.1 | loopback by connection, on Linux: each face refuses 127.0.0.2, so it listens on 127.0.0.1 alone (skipped elsewhere, where 127.0.0.2 is no loopback address by default) (1) | expected: ((refused "ECONNREFUSED") (refused "ECONNREFUSED"))<br>actual:   (timeout timeout) (exit 1, 9 s) |
| z-c-o | stdin's end ignored, as in round 1: the SIGKILL check now ends by its 5 s | the scenarios' origin starts, serves them all, and stops (7); the SIGKILL check: it cannot outlive its suite: a child Chez that started it is killed with SIGKILL, and within 5 s every face refuses connections | expected: (returned done)<br>actual:   (raised "Exception in call-with-origin: the origin's stdout did not end within 5000 ms of its stdin closing, so it was killed with irritants ((stdout . \"\") (… (exit 1, 54 s) |
| z-deadline-ignored | the probe takes --deadline and never ends at it | wire-probe-deadline: a peer that keeps sending ends the probe at the deadline, by the clock, with what came by then (1) | expected: (deadline prefix within-1500-ms)<br>actual:   (eof (not-a-prefix 4137) (took 4488)) (exit 1, 15 s) |
| z-first-wait | the drip sends its first byte without its wait | raw /raw/drip?bytes=4&gap=25: the whole bytes, then eof, the last body byte at least 100 ms after connecting and half of 75 ms after the first (4) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd" eof late-enough spread-enough each-late-enough own-arrivals)<br>actual:   ("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd" eof (since-connected 78 1 ((0 . 2) (38 . 2) (39 . 28) (40 . 53) (41 . 79))) spread-enough (early-bytes (0 1… (exit 1, 8 s) |
| z-flood-deadline | read-until reads its deadline only when nothing is ready | read-within: on /dev/zero, a port always ready with no end, it stops at its deadline of 300 ms, by the clock, within 1000 ms, keeping 4096 bytes (1) | expected: (0 "(timeout 4096 within-1000-ms)\n" "")<br>actual:   (137 "" "") (exit 1, 20 s) |
| z-floors-case | check-floors matches node-version in lower case only | workflow: node-version with its key in title case, as GitHub reads it all the same: named (7) | expected: (returned ("W/ci.yml: line 13 names node-version, but is not \"node-version: ${{ steps.ID.outputs.NAME }}\": the Node floor comes from f.sexp, through a step t…<br>actual:   (returned ()) (exit 1, 4 s) |
| z-floors-escape | check-floors reads no double-quoted key with an escape | workflow: a double-quoted key with an escape that spells node-version: named (4) | expected: (returned ("W/ci.yml: line 13 holds a double-quoted key with an escape, which check-floors does not read: write the key as GitHub reads it"))<br>actual:   (returned ()) (exit 1, 4 s) |
| z-half-close-ignored | the probe takes --half-close and never half-closes | wire-probe-half-close: the peer sees a FIN once the bytes are sent, and the probe reads its answer; wire-probe sends none (1) | expected: (("saw FIN\n" eof) ("" timeout))<br>actual:   (("" timeout) ("" timeout)) (exit 1, 14 s) |
| z-halfopen-false | the raw face without allowHalfOpen | a half-closing client: a raw drip, sent with a FIN after it, gets the whole response, and the next request is served (1) | expected: (("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc" eof) ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))<br>actual:   (("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n" eof) ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)) (exit 1, 8 s) |
| z-pid-unchecked | the announced pid is not compared with Node's | call-with-origin raises on a malformed announcement: its pid is not that of the Node process call-with-origin started (1) | expected: (call-with-origin "the origin's announcement is malformed: its pid is not that of the Node process call-with-origin started" ((stdout . "{\"node\":\"v1\",\"pid…<br>actual:   no-raise (exit 1, 11 s) |
| z-raise-replaced | the stop's problem is raised in the cleanup, so in place of PROC's raise | call-with-origin raises, with stderr and exit status, on an origin that dies before announcing (5) | expected: (call-with-origin "the origin's stdout ended before its announcement" ((stdout . "") (stderr . "dying early\n") (status . 3)))<br>actual:   (call-with-origin "the origin did not end cleanly: it wrote to stderr; it exited 3" ((stdout . "") (stderr . "dying early\n") (status . 3))) (exit 1, 11 s) |
| z-range-big-header | big-header's bytes narrowed to 2-1048576 | raw /raw/big-header?bytes=1: the whole bytes, then eof (1) | expected: ("HTTP/1.1 200 OK\r\nX-Big: a\r\n\r\n" eof)<br>actual:   ("HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof) (exit 1, 9 s) |
| z-range-drip-bytes | drip's bytes narrowed to 1-4095 | raw /raw/drip?bytes=4096&gap=5000: the whole bytes, then timeout (1) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 4096\r\n\r\n" timeout)<br>actual:   ("HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof) (exit 1, 8 s) |
| z-range-drip-gap | drip's gap narrowed to 1-4999 | raw /raw/drip?bytes=4096&gap=5000: the whole bytes, then timeout (1) | expected: ("HTTP/1.1 200 OK\r\nContent-Length: 4096\r\n\r\n" timeout)<br>actual:   ("HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof) (exit 1, 8 s) |
| z-range-many-headers | many-headers' count narrowed to 2-100000 | raw /raw/many-headers?count=1: the whole bytes, then eof (1) | expected: ("HTTP/1.1 200 OK\r\nX-H-1: v\r\n\r\n" eof)<br>actual:   ("HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof) (exit 1, 9 s) |
| z-status-ignored | a non-zero exit status passes | call-with-origin, once PROC returns, refuses an origin that exits 1 and writes to stderr (3) | expected: (call-with-origin "the origin did not end cleanly: it wrote to stderr; it exited 1" ((stdout . "") (stderr . "bye\n") (status . 1)))<br>actual:   (call-with-origin "the origin did not end cleanly: it wrote to stderr" ((stdout . "") (stderr . "bye\n") (status . 1))) (exit 1, 12 s) |
| z-stderr-ignored | stderr passes | call-with-origin, once PROC returns, refuses an origin that exits 1 and writes to stderr (3) | expected: (call-with-origin "the origin did not end cleanly: it wrote to stderr; it exited 1" ((stdout . "") (stderr . "bye\n") (status . 1)))<br>actual:   (call-with-origin "the origin did not end cleanly: it exited 1" ((stdout . "") (stderr . "bye\n") (status . 1))) (exit 1, 11 s) |
| z-watchdog-orphan | bounded's first watchdog, a sleep in a subshell | bounded leaves nothing running: run with a pipe as its stdout, the pipe ends within 2000 ms of a command that ends at once (1) | expected: ended<br>actual:   still-open-after-2000-ms (exit 1, 10 s) |

`z-lastcrash` now throws after the 7th content-length play, which is this code's last; the
reviewer's tree had 4. The crash lands just before the http half-close test, so that test
fails too, with the verdict. `z-flood-deadline` hangs no suite: the `/dev/zero` read runs
in a child under `timeout`, and fails with status 137.

## 1.7 Round 4: the scoped review of round 3 (2026-10-18)

### 1.7.1 What changed

1. **An origin outlives a dead suite by what the suite was running.**
   - Children of `system` inherit Chez's pipe ends. So a probe or command running when the
     suite dies holds the origin's stdin until its own bound ends it:
     `wire-probe-deadline` for a probe, `bounded`'s 10 s for a command. The coordinator
     chose to state this, with no FFI and no fd juggling.
   - `origin.mjs`'s contract, `call-with-origin`'s comment and `test-origin`'s header now
     say so.
   - `origin-child.sps` gains a `probe` mode: a probe on `stall-before-head`, idle 20000,
     under `wire-probe-deadline` 2000.
   - The new test kills that child with SIGKILL mid-probe. Every face must refuse within
     2000 ms plus 2000 ms of slack of the kill, by the monotonic clock.
   - The idle test is kept, through the same helper, `sigkill-check`.
2. **check-floors fails closed on whatever it cannot read.** Five rules, each per line of
   every workflow file, replace round 3's escaped-key rule, which they cover:
   - a backslash after a double quote, in a key or value, closed or not;
   - `?` where a key goes, after the indent and any `- `, or after `{`, `[` or `,`;
   - `*` or `&` where a key goes, followed by a letter, digit, `_` or `-`;
   - any character beyond ASCII;
   - a tab.

   **Narrowed:** the alias rule needs a name character after `*` or `&`, because the real
   `ci.yml` holds `*)`, a shell `case` pattern in a `run:` block (line 262). `r4-alias-wide`
   shows the wide rule failing on it. The real `ci.yml` holds none of the other four: its
   only backslashes are in single quotes, with no double quote before them.

   The reviewer's six fixtures, plus a dotless-i one I completed (its directory was
   empty), are in `tests/fixtures/floors/workflow-key-*`, each failing by name. Rows cover
   each rule, and six narrowed cases pass. Round 3's row for a double-quoted value with an
   escape now expects the complaint, since a quoted key may go on over lines.
3. **Nagle.** The raw face sets `socket.setNoDelay(true)`, so a drip's bytes are not
   joined by Nagle's algorithm while one is unacknowledged. No check: the review measured
   no flake on Linux, and macOS is unmeasured.

### 1.7.2 Mutations, round 4

| Case | Mutation | Failing test (failures in all) | Output (at most 3 lines) |
|---|---|---|---|
| baseline | no mutation: every command below must pass here | none: every command passes | # of expected passes      110<br># of expected passes      368<br>check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20) (exit 0, 15 s) |
| r4-deadline-ignored | the probe takes --deadline and never ends at it | a suite killed with SIGKILL during a probe: its origin lives until the probe's wire-probe-deadline, 2000 ms, ends the probe; within 2000 ms of it plus 2000 ms of slack every face refuses connections (1) | expected: (returned ((timeout timeout) refused-within-the-bound))<br>actual:   (returned ((timeout timeout) still-served-after-the-bound)) (exit 1, 13 s) |
| r4-no-backslash-rule | check-floors without the backslash-after-a-double-quote rule | workflow: a double-quoted key with an escape that spells node-version: named (13) | expected: (returned ("W/ci.yml: line 13 holds a backslash after a double quote, which YAML may read as an escape, and check-floors does not"))<br>actual:   (returned ()) (exit 1, 5 s) |
| r4-no-explicit-rule | check-floors without the explicit-key rule | workflow: unread: an explicit key: named (7) | expected: (returned ("W/ci.yml: line 12 writes an explicit key, with ?, whose colon check-floors does not look for"))<br>actual:   (returned ()) (exit 1, 5 s) |
| r4-no-alias-rule | check-floors without the alias-or-anchor rule | workflow: unread: an alias as a key: named (4) | expected: (returned ("W/ci.yml: line 12 puts an alias or an anchor where a key goes, which check-floors does not resolve"))<br>actual:   (returned ()) (exit 1, 4 s) |
| r4-no-ascii-rule | check-floors without the beyond-ASCII rule | workflow: unread: a character beyond ASCII, in a comment: named (4) | expected: (returned ("W/ci.yml: line 12 holds a character beyond ASCII, which GitHub may fold into a key's letters, and check-floors does not"))<br>actual:   (returned ()) (exit 1, 4 s) |
| r4-no-tab-rule | check-floors without the tab rule | workflow: unread: a tab before a colon: named (3) | expected: (returned ("W/ci.yml: line 12 holds a tab, which YAML may read beside a key, and check-floors does not"))<br>actual:   (returned ()) (exit 1, 5 s) |
| r4-alias-wide | the alias rule widened to any * or & where a key goes, unnarrowed | workflow: unread, narrowed: a shell case pattern *) in a run block: nothing to report (3) | expected: (returned ())<br>actual:   (returned ("W/ci.yml: line 12 puts an alias or an anchor where a key goes, which check-floors does not resolve"))<br>check-floors: .github/workflows/ci.yml: line 262 puts an alias or an anchor where a key goes, which check-floors does not resolve (exit 2, 4 s) |

### 1.7.3 The stop condition (`stop-round4.log`)

    check-suites: every suite ends with (exit (suite-exit-status runner)) (17 checked)
    test: ran 17, passed 17, failed 0, hung 0
    check-test-fails: make test failed, as it must, in all 10 cases
    test-memory: ran 2, passed 2, failed 0, hung 0

`test-origin` 110 tests in 10.5 s; `test-check-floors` 368 tests. No Docker rerun: neither
the runner nor the probe changed.

---

# Part 2: the drift guard and the floor build


Worktree: `/home/kishu/src/chez-curl/.claude/worktrees/agent-a45acd9c604059f4e`.
Raw outputs: `build/verify/m1/out/*.txt` (Docker builds), `build/verify/m1/copy/mutant-out/*.txt`
(mutations), `build/verify/m1/out/final-make.txt` (the final make run). Scripts that made them:
`docker-floor.sh`, `docker-e2e.sh`, `make-mutants.py`, `copy/run-mutants.sh`.

## 2.1 The three rows

Every row's five fields were read by `tests/libcurl-oracle.c` (C, compiled at test time, dlopen of
the library), not by chez-curl.

| Row | Where measured | version | version-num | features | ssl-version | host |
|---|---|---|---|---|---|---|
| Guix container | `scripts/guix-env`, `$CHEZ_CURL_LIBCURL` = profile `libcurl.so.4` -> `/gnu/store/67lpb53npkkjp5mab0arpnrq2i3xxdbg-curl-8.20.0/lib/libcurl.so.4.8.0` | 8.20.0 | 529408 | 1430210445 | GnuTLS/3.8.13 | x86_64-unknown-linux-gnu |
| Ubuntu 24.04 | Docker `ubuntu:24.04` (24.04.5 LTS), `/usr/lib/x86_64-linux-gnu/libcurl.so.4` -> `libcurl.so.4.8.0`; `dpkg -l`: `libcurl4t64 8.5.0-2ubuntu10.16`, `libssl3t64 3.0.13-0ubuntu3.16`, (`libcurl4-openssl-dev 8.5.0-2ubuntu10.16`, only for the compile) | 8.5.0 | 525568 | 1438599069 | OpenSSL/3.0.13 | x86_64-pc-linux-gnu |
| 7.85.0 floor | Docker `ubuntu:24.04`, `packaging/debian-prereqs.txt` installed, `scripts/ci/build-curl.sh` (new) into `/opt/curl`; `libssl-dev 3.0.13-0ubuntu3.16`, `zlib1g-dev 1:1.3.dfsg-3.1ubuntu2.2`, `libnghttp2-dev 1.59.0-1ubuntu0.4` | 7.85.0 | 480512 | 1361691293 | OpenSSL/3.0.13 | x86_64-pc-linux-gnu |

The Guix oracle run printed `(version . "8.20.0") (version-num . 529408) (features . 1430210445)
(ssl-version . "GnuTLS/3.8.13") (host . "x86_64-unknown-linux-gnu")`; Chez in the container is 10.4.0.
The Ubuntu run is `out/measure-ubuntu.out`... see `measure-ubuntu.out` in this directory.

The features words, decoded (`CURL_VERSION_*` bits, `curl/curl.h`):

- Guix 1430210445: IPV6 SSL LIBZ ASYNCHDNS SPNEGO LARGEFILE IDN TLSAUTH_SRP HTTP2 GSSAPI KERBEROS5
  UNIX_SOCKETS PSL HTTPS_PROXY ALTSVC ZSTD HSTS THREADSAFE
- Ubuntu 1438599069: the same, plus NTLM and BROTLI
- floor 1361691293: IPV6 SSL LIBZ NTLM ASYNCHDNS LARGEFILE TLSAUTH_SRP NTLM_WB HTTP2 UNIX_SOCKETS
  HTTPS_PROXY ALTSVC HSTS THREADSAFE

## 2.2 The floor build: every optional dependency of 7.85.0's `./configure`

Source: `./configure --help` of the pinned tarball (sha256 `88b54a6d...04be6` verified; saved as
`build/verify/m1/configure-help-7.85.0.txt`), and the
`OPT_*` defaults in its `configure` (a value of `off`, `yes` or `default` is probed; `no` is not).

| Dependency | Flag set | Probed by default in 7.85.0? | Setting |
|---|---|---|---|
| OpenSSL | `--with-openssl` | no (`OPT_OPENSSL=no`); a missing one is a configure error | ON (unchanged) |
| zlib | `--with-zlib` | yes; bare `--with-zlib` is the same as the default (silently absent without headers) | ON, and curl-config must list `libz` |
| nghttp2 | `--with-nghttp2` | yes (`OPT_H2=yes`); bare is the same as the default | ON, and curl-config must list `HTTP2` |
| brotli | `--without-brotli` | yes (`OPT_BROTLI=off`) | OFF |
| zstd | `--without-zstd` | yes (`OPT_ZSTD=off`) | OFF |
| libidn2 | `--without-libidn2` | yes (`OPT_IDN=default`) | OFF |
| libpsl | `--without-libpsl` | yes | OFF |
| libgsasl | `--without-libgsasl` | yes | OFF |
| libssh2, libssh, wolfssh | `--without-libssh2 --without-libssh --without-wolfssh` | yes (`off`) | OFF |
| librtmp | `--without-librtmp` | yes (`OPT_LIBRTMP=off`) | OFF |
| LDAP, LDAPS | `--disable-ldap --disable-ldaps` | yes (looks for `ldap.h`) | OFF |
| GSS-API | `--without-gssapi` | **no** in 7.85.0: `want_gss` is set only by `--with-gssapi*` | OFF (named anyway) |
| c-ares | `--disable-ares` | no (`--enable-ares` is opt-in) | OFF (named anyway) |
| hyper, quiche, msh3 | `--without-hyper --without-quiche --without-msh3` | no (`no`) | OFF (named anyway) |
| ngtcp2 | `--without-ngtcp2` | yes (`OPT_TCP2=yes`, found by pkg-config) | OFF |
| nghttp3 | `--without-nghttp3` | only when ngtcp2 is on | OFF |
| other TLS backends: schannel, secure-transport, amissl, gnutls, mbedtls, wolfssl, bearssl, rustls, nss | none | no (all `no`; only asked for) | not named |
| windows IDN (`--with-winidn`) | none | Windows only | not named |
| RTSP | `--enable-rtsp` (default) | not a probe | stays ON (`test-variadic` needs it) |
| IPv6 | none | **a run-time test**: `socket(AF_INET6, ...)` succeeds, else IPv6 is off | not pinned (see open question) |
| default CA bundle path | none | a file test; changes no feature bit | not pinned |

Also set: `--enable-option-checking=fatal`, because a misspelt `--with…`/`--enable…` is only a
`configure: WARNING: unrecognized options` otherwise (configure line 1705).

Additions to the script beyond the flags (all fail-closed):

1. After install, `curl-config --features` and `--protocols` must list `libz` and `HTTP2`.
2. They must list none of: brotli zstd IDN PSL GSS-API Kerberos SPNEGO GSASL HTTP3 (features) and
   LDAP LDAPS RTMP SCP SFTP (protocols). LDAP, RTMP and SSH change `curl_version_info`'s protocols
   only, not its features word, so the drift guard could not see them.

## 2.3 A/B: the feature word depends on the machine, with the old script; not with the new

Docker `ubuntu:24.04`. **A**: only the prereqs. **B**: the prereqs plus `libbrotli-dev libzstd-dev
libidn2-dev libpsl-dev libssh2-1-dev libldap-dev libkrb5-dev librtmp-dev libgsasl-dev
libc-ares-dev`. Package versions in B (from `dpkg -l`): libbrotli-dev 1.1.0-2build2, libc-ares-dev
1.27.0-1.0ubuntu1, libgsasl-dev 2.2.1-1willsync1ubuntu0.1, libidn2-dev 2.3.7-2build1.1, libkrb5-dev
1.20.1-6ubuntu2.10, libldap-dev 2.6.10+dfsg-0ubuntu0.24.04.1, libpsl-dev 0.21.2-1.1build1,
librtmp-dev 2.4+20151223.gitfa8646d.1-2build7, libssh2-1-dev 1.11.0-4.1ubuntu0.24.04.4,
libzstd-dev 1.5.5+dfsg2-2build1.1 (and zlib1g-dev 1:1.3.dfsg-3.1ubuntu2.2 pulled in by them).

| Run | Script, prereqs | version-num | **features** | ssl-version | host | curl-config features |
|---|---|---|---|---|---|---|
| old-A | HEAD, HEAD | 480512 | **1361625749** | OpenSSL/3.0.13 | x86_64-pc-linux-gnu | AsynchDNS HSTS HTTPS-proxy IPv6 Largefile NTLM NTLM_WB SSL TLS-SRP UnixSockets alt-svc threadsafe |
| old-B | HEAD, HEAD | 480512 | **1975043741** | OpenSSL/3.0.13 | x86_64-pc-linux-gnu | AsynchDNS GSASL HSTS HTTPS-proxy IDN IPv6 Largefile NTLM NTLM_WB PSL SSL TLS-SRP UnixSockets alt-svc brotli libz threadsafe zstd |
| new-A | new, new | 480512 | **1361691293** | OpenSSL/3.0.13 | x86_64-pc-linux-gnu | AsynchDNS HSTS HTTP2 HTTPS-proxy IPv6 Largefile NTLM NTLM_WB SSL TLS-SRP UnixSockets alt-svc libz threadsafe |
| new-B | new, new | 480512 | **1361691293** | OpenSSL/3.0.13 | x86_64-pc-linux-gnu | (identical to new-A) |

- **Red:** old-A and old-B give different `features` words (1361625749 vs 1975043741). B's adds
  GSASL, IDN, PSL, brotli, libz, zstd. Old-B's protocols also gain LDAP, LDAPS and RTMP.
- Old-A had **no zlib and no HTTP/2** (`zlib: no (--with-zlib)`, `HTTP2: no`): `libcurl4-openssl-dev`
  only *suggests* `zlib1g-dev` and `libssl-dev` (`apt-cache depends`, noble), so nothing installed
  the headers. The floor lane had been testing a libcurl without HTTP/2.
- **Green:** new-A and new-B give identical fields. Their `curl-config --protocols` are identical
  too: DICT FILE FTP FTPS GOPHER GOPHERS HTTP HTTPS IMAP IMAPS MQTT POP3 POP3S RTSP SMB SMBS SMTP
  SMTPS TELNET TFTP. `ldd` of new-B's `libcurl.so.4`: libc libcrypto libnghttp2 libssl libz (and the
  loader and vdso) and nothing else.
- Configure's own summary for every run is in `out/{old,new}-{A,B}.txt`.

### 2.3.1 The script's new checks, watched failing (Docker, new script)

| Case | Run | build-curl.sh |
|---|---|---|
| libnghttp2-dev left out of A | `neg-nghttp2` | exit 1: `curl-config does not list HTTP2, which this build needs (is its -dev package installed? ...)`. configure itself said nothing and finished. |
| zlib1g-dev left out of A | `neg-zlib` | exit 1: `curl-config does not list libz, ...` |
| `--disable-ldap --disable-ldaps` cut from the script, in B | `neg-ldap` | exit 1: `curl-config lists LDAP, which this build turns off` (the features word does not show LDAP) |
| `--without-brotlii` (typo) as an extra flag, new script, A | `neg-typo-new` | exit 1: `configure: error: unrecognized options: --without-brotlii` |
| the same, **old** script, A | `neg-typo-old` | exit 0, features word 1361625749, as old-A: the typo did nothing and was only warned about |

## 2.4 The disabled-API builds (new script, image A)

`nm -D` cannot show an API missing. Measured, both with the option flag:

| Build | `curl_easy_option_by_name` | `curl_easy_header` | `curl-config`'s `Headers API` line |
|---|---|---|---|
| `--disable-get-easy-options` | present | present | enabled |
| `--disable-headers-api` | present | present | `no (--enable-headers-api)` |
| none (new-A) | present | present | enabled |

Both entry points are exported in all three, as stubs: with the API configured out, libcurl 7.85.0
still defines the functions (`lib/easygetopt.c` is guarded by `CURL_DISABLE_GETOPTIONS`, and the
stub of `curl_easy_option_by_name` answers NULL; `curl_easy_header` answers `CURLHE_NOT_BUILT_IN`).
That is why `src/curl/private/verify.sls` probes by calling the functions. So the brief's
"`nm -D` shows each lacks its entry point" is false; what refuses a build is the probe.
All three had features 1361691293 (the same word), as the feature word does not show these APIs.

The probe result itself, through the real `make build` and `scripts/ci/expect-missing-api.sh`, is
in section 6 (both variants are refused, each naming its own entry point).

## 2.5 The suite watched failing

All in `build/verify/m1/copy`, a plain copy of the worktree (no `.git`), through its own
`scripts/guix-env`. `copy/run-mutants.sh` restores the pristine suite and rows before each case
and runs the suite alone. Guard = the test named "the loaded libcurl's version, version-num, features,
ssl-version and host equal exactly one row of tests/known-libcurls.sexp". The unmutated suite: 47
passes, exit 0.

| Case | Mutation | Failing test(s) | Output (trimmed) |
|---|---|---|---|
| a-version | Guix row `(version "8.20.0")` -> `"8.20.1"` | guard | `FAIL <guard>` / `expected: (("8.20.0" 529408 ...))` / `actual: ()`; the row was printed on stderr |
| a-version-num | `529408` -> `529409` | guard | same |
| a-features | `1430210445` -> `1430210444` | guard | same |
| a-ssl-version | `"GnuTLS/3.8.13"` -> `"GnuTLS/3.8.14"` | guard | same |
| a-host | `"x86_64-unknown-linux-gnu"` -> `"...gnux"` | guard | same |
| b-matching-row-removed | the Guix row deleted | guard | `actual: ()`; stderr: `test-drift: no row of tests/known-libcurls.sexp matches the libcurl this suite loaded (/gnu/store/...-profile/lib/libcurl.so.4).` then the row, `(libcurl (where "TODO: ...") (version "8.20.0") (version-num 529408) (features 1430210445) (ssl-version "GnuTLS/3.8.13") (host "x86_64-unknown-linux-gnu"))` |
| c-duplicate-row | the Guix row again, `where` changed | no two rows are equal on ...; guard | `expected: ()` / `actual: ((1 2))`; guard `actual:` lists the key twice |
| d-field-missing | Ubuntu row without `version-num` | `row 2 is (libcurl) with exactly where, ...` | `actual: (fields-are (where version features ssl-version host) not (where version version-num features ssl-version host))` |
| d-field-extra | Ubuntu row with `(note "extra")` | `row 2 is ...` | `actual: (fields-are (where version version-num note features ssl-version host) not (...))` |
| d-fields-swapped | Ubuntu row, `version` and `version-num` swapped | `row 2 is ...` | `actual: (fields-are (where version-num version features ssl-version host) not (...))` |
| e-unclosed-paren | last row's `)` removed | `tests/known-libcurls.sexp reads as data`; guard | `actual: (unreadable "Exception in read: unexpected end-of-file reading list before file-position 2646 ...")` |
| e-stray-close-paren | a `)` after the last row | `... reads as data`; guard | `actual: (unreadable "Exception in read: unexpected close parenthesis before file-position 2648 ...")` |
| f-missing-file | file removed | `... reads as data`; guard | `actual: (unreadable "Exception in open-file-input-port: failed for tests/known-libcurls.sexp: no such file or directory")`; row printed |
| g-matcher-version-only | `matching-rows` compares `version` alone | matcher: a report that differs in version-num / features / ssl-version / host alone matches no row (4 tests) | the guard passes here (the real rows equal the report) |
| g2 | (g) and the Guix row's features changed | the same 4, **and the guard** | `expected: (("8.20.0" 529408 1430210445 ...))` / `actual: (("8.20.0" 529408 1430210444 ...))`: the version-only matcher found the row, and `row-key` of it is not the report's key |
| h-where-alone | the Guix row's `where` changed | none: exit 0, 47 passes | `# of expected passes 47` |
| i-wrong-kind | Ubuntu row's `version-num` is the string `"525568"` | `row 2 is ...` | `actual: (bad-value version-num wants natural got "525568")` |
| k1-kinds-not-checked | `kind-ok?` accepts anything | nine `shape: a row whose F is V is refused` | `expected: rejected` / `actual: ok` |
| k2-order-not-checked | `row-problem` no longer compares the names | `shape: a row without ssl-version / host`, `with a seventh field`, `with a field twice`, `with where and host swapped`, `(libcurl) is refused`, `matcher: a row that is not shaped like one is never a match` (7) | |
| k3-duplicates-blind | `duplicate-rows` finds nothing | `duplicates: rows that differ in where alone are one, found by place` | `expected: ((1 3))` / `actual: ()` |
| k4-malformed-row-matches | `row-key` no longer checks shape | `matcher: a row that is not shaped like one is never a match` | |
| k5-printed-row-unclosed | `row-text` leaves off the closing `)` | `the row printed for a report reads back as a row that equals the report` | |
| k6-printed-where-unescaped | `row-text` writes `where` unescaped | the same | |

(a) to (i) are the brief's list plus (i), a rule none of it reaches: the shape check's kind rule. (k)
are the suite's own unit tests, each watched failing under a mutation of the procedure it tests,
because no plant in a file reaches them. Case g2 is why the guard
reads the matched rows back through `row-key` instead of trusting the matcher: with (g) alone the
guard passes (the unit tests catch (g)); with (g) and a row that differs elsewhere, only the
read-back catches it.

## 2.6 End to end in Docker, as the CI lanes run (`out/e2e.txt`)

One throwaway `ubuntu:24.04` (24.04.5) container: `packaging/debian-prereqs.txt` installed as the
workflow installs it (`grep -v` and `apt-get install --no-install-recommends`), Chez 10.4.0 built
by `scripts/ci/build-chez.sh` (`(10 4 0 yes)`), libcurl 7.85.0 built three times by the new
`scripts/ci/build-curl.sh` (plain, `--disable-get-easy-options`, `--disable-headers-api`), then,
as a non-root user, from a copy of the worktree:

| Step | Result |
|---|---|
| `test-drift.sps` against the system libcurl (discovery; `libcurl4t64 8.5.0-2ubuntu10.16`) | exit 0: the Ubuntu row matched what `(loaded-libcurl)` reports |
| `test-drift.sps` with `CHEZ_CURL_LIBCURL` = the floor build | exit 0: the floor row matched |
| `expect-missing-api.sh curl_easy_option_by_name` on the options-disabled build | `(reason . missing-api)`, `detail: curl_easy_option_by_name`, version 7.85.0; verdict `refusing ... as missing-api, naming curl_easy_option_by_name` |
| `expect-missing-api.sh curl_easy_header` on the header-disabled build | `detail: curl_easy_header`; verdict `... naming curl_easy_header` |
| `make build; make test` against the system libcurl (the main lane's suites) | 16 suites passed, 0 failed |
| `make build; make test` against the floor build, with `C_INCLUDE_PATH` (the floor lane) | 16 suites passed, 0 failed; `make build` named `version: 7.85.0`, `features: ipv6 ssl libz ntlm asynchdns largefile tlsauth-srp ntlm-wb http2 unix-sockets https-proxy altsvc hsts threadsafe` |

So the two CI-measured rows are confirmed by the suite itself, not only by the C oracle, on the
same image the runner uses, though not on GitHub's runner image: CI has still never run.

## 2.7 The final make run (`out/final-make.txt`)

`scripts/guix-env sh -c 'make check-suites test && MEMORY_SUITES=tests/test-drift.sps make test-memory'`:
`check-suites` 16 checked; `make test` ran 16, passed 16, failed 0, hung 0 (`test-drift.sps` 47 passes);
`test-memory` ran 1, passed 1.

---

# Part 3: what the coordinator checked, and the reviews

## 3.1 Each hand-back, rerun

- **The drift guard,** in its worktree:
  - `make check-suites test` passed, and `test-memory` passed on `test-drift`.
  - The container's row equals the C oracle's answer there.
  - The Ubuntu row equals a separate Docker `ubuntu:24.04` run of the oracle against
    `libcurl4t64 8.5.0-2ubuntu10.16`.
  - `apt-cache depends libcurl4-openssl-dev` lists `libssl-dev` and `zlib1g-dev` under
    Suggests only.
  - With the container's row removed, the guard fails by name, `actual: ()`, and prints the
    row ready to paste.
- **Every round of the origin,** in the real tree with both halves:
  - `make check-help check-suites check-seam check-floors test check-test-fails` passed:
    17 of 17 suites, and `check-test-fails` 10 of 10.
  - `test-memory` passed on the three new suites.
  - On the host, `check-action-pins.sh` and actionlint passed.
  - `actions/setup-node` v7.1.0 is commit `949feb2413d6458794dcd2491c4babbbce0c15c1`
    (`gh api repos/actions/setup-node/git/ref/tags/v7.1.0`).
- **`y-never-file`'s "exit 0"** is the status of its command's second suite: the case runs
  two suites joined by `;`, and `test-origin`, the first, exited 1.

## 3.2 Changes the coordinator made, each watched failing

- **`--enable-ipv6` in `build-curl.sh`.**
  - In 7.85.0's `configure.ac`, the flag sets `ipv6=yes` without the `AC_RUN_IFELSE`
    socket test.
  - A Docker rebuild with it gave the floor row's five fields unchanged, and passed the new
    `IPv6` check.
- **A row still beginning `TODO: `, the placeholder `test-drift` prints, fails.** Planted
  on the container's row: `FAIL no row's where still begins with the placeholder the suite
  prints`.
- **The drip bounds.**
  - The probe's answer gained `probe-connected`.
  - The drip test bounds the last body byte from the connect time, and half the spread.
  - Three plants, in a copy:

    | Plant | Result |
    |---|---|
    | the drip with no waits | fails both bounds: `(since-connected 1 …)`, `(spread 0 …)` |
    | one wait of N×gap, then every byte together | passes the connect bound, fails the spread |
    | `probe-connected` always 0 | fails `parse-wire-probe`'s test |
- **`read-data` in `test-drift`.** UTF-8 errors now raise, and nothing may follow `#!eof`.
  Each has a test on a written file, and each mutant fails by name:
  - the default transcoder gives `FAIL read-data: a file whose bytes are not UTF-8 does not
    read`;
  - no end check gives `FAIL read-data: a row after an end-of-file mark does not read`.
- **CI.**
  - The curl cache keys hash `packaging/debian-prereqs.txt`.
  - The floor lane checks `"${NODE:-node}" --version` against the floor, exactly or as a
    major. Checked as a `case` on its own: v20 and v20.19.5 pass, v22.1.0 and v200.0.0 are
    refused; a floor of 20.10.0 takes v20.10.0 and refuses v20.10.1.

## 3.3 Traps, reproduced before they were recorded

| Trap | How it was reproduced |
|---|---|
| SRFI-64's one result per runner | a four-line suite printed `FAIL inner, which passes` |
| Node's `destroy()` sends a FIN | a server saw `end`; with `resetAndDestroy()` it saw `ECONNRESET` |
| curl's stubs for a configured-out API | read in 7.85.0's `lib/easygetopt.c` and `lib/headers.c` |
| `configure` only warns about an unknown option | read at `configure` line 1705 |
| optional libraries found by default | `OPT_BROTLI=off`, and only `no` skips the search (`configure.ac`) |
| a shell's `wait` prints `Killed` | dash in Docker, and `bash -c` in the container, both print it; bash as `sh` doesn't |
| a zombie until Chez's next collection | `/proc/PID/status` said `Z (zombie)` one second after exit, and the pid was gone after a `(collect)` |

The builder's round 3 said "Chez reaps an exited child". Its probe ran `(collect)` before
`kill -0`, so the measurement here is the accurate one.

## 3.4 The first review (Opus, read-only)

| Finding | Severity | Reproduced here | Closed by |
|---|---|---|---|
| an origin that dies after its last exchange, or exits 1 at stdin's end, passes | blocker | yes: both reviewer mutants passed 100 of 100 | round 3: the runner, exit status, empty stderr |
| the bounded wait is unbounded while data flows | should-fix | yes: both floods ran 12 s against a 1 s bound | round 3: `read-within`, the probe's `--deadline` |
| destroying open sockets at the stop is untested | should-fix | yes: `mut-nodestroy` passed | round 3: a test with a probe open across the stop |
| `node-version` matched case-sensitively | should-fix | yes: four spellings passed `check-floors` | round 3: any case, quoted or not |
| bunched drip bytes pass | should-fix | yes: `mut-drippairs` passed | round 3: per-byte bounds; own arrivals on the 25 ms row |
| range edges, loopback by connection, the drift reader, the cache key, records | notes | partly | rounds 3 and 3.2 above |

After round 3, the coordinator's own version of each reviewer mutant was planted in a
fresh copy of the final code. Each failed by name, and the unmutated copy passed:

| Mutant | Failing test |
|---|---|
| exit 1 with no stderr | the scenarios' origin, OS ports, pid, stop |
| stderr with exit 0 | the same four |
| no socket destroy | stopping destroys open connections |
| bytes in pairs | the drip's own arrivals |
| bind 0.0.0.0, announce 127.0.0.1 | loopback by connection |

The reviewer's floods raised in 1064 ms and 1065 ms.

## 3.5 The scoped review of the fixes (Opus, read-only)

- **An origin outlives a suite killed mid-probe** (should-fix). `system`'s children inherit
  the origin's pipe ends. Reproduced: served 19.3 s after the SIGKILL, with the stdin pipe
  held by the probe's shell and node. Decided: no FFI and no fd juggling. The contract
  states the bound, the probe's own deadline, and round 4 tests it.
- **`check-floors`' escape rule needed a closing quote and its colon on one line**
  (should-fix). Six YAML spellings passed. Round 4 fails closed on the constructs instead.
- **My edit cut the head off traps.md's `nm` entry** (should-fix). Restored.
- **Notes:**
  - the `Killed` trap's wording about bash, now corrected;
  - Nagle and the 25 ms row: round 4 sets `setNoDelay`;
  - "every wait" was overclaimed, and is now "every wait on a pipe";
  - the floor lane's Node check, now exact or a major, and against `$NODE`;
  - the zombie evidence, settled in 3.3.
- **Classes it found closed:** the end of life, with the runner portable across dash, bash
  5, bash 5 `--posix` and bash 3.2 `--posix`; bounded waits; stopping; half-close; range
  edges; loopback; and the coordinator's own fixes, including a Docker rebuild that gave the
  floor row's features exactly.

## 3.6 Round 4, rerun

- In the real tree, with the coordinator's `ci.yml` change:
  - the checks before `make test`, then `make test` (17 of 17 suites) and
    `check-test-fails` (10 of 10), all passed;
  - `test-memory` passed on the three new suites;
  - `check-action-pins.sh` and actionlint passed.
- Each of the second review's seven YAML fixtures (`review2/cf/v1`–`v7`) now fails
  `check-floors` with status 1. Run directly, `v1-explicit` names two problems on its line
  14: the backslash after a double quote, and the explicit key.
- Each round 4 mutant fails by name; the outputs are in `build/verify/m1/mut4/`.
  `r4-alias-wide` also fails `check-floors` on the real `ci.yml`'s `*)` at line 262. That
  is why the alias rule needs a name character after `*` or `&`.
- A loop of the coordinator's own first reported status 0 for all seven fixtures:
  `$(basename …)` inside its `echo` reset `$?` before it was printed. Rerun with the status
  saved first, all seven failed.
