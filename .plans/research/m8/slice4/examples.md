# The examples, proposed; and what a child costs

Read-only, 2026-11-08, `feat/m8-docs` off `main` at `fb62a0b`. Ten examples proposed, none
written. Every output below was measured once, on the Guix lane (8.20.0, GnuTLS), by a prototype
that runs each scenario in one process against `(curl-testing)`'s origin
(`child/proto-outputs.sps`, `logs/proto-outputs-guix.txt`); the other lanes are the slice's suite
to run.

## How the suite would run one

- **The URL is the first command-line argument:** the origin's `http` face as
  `http://127.0.0.1:PORT`, no trailing `/`, which the example appends paths to. Every proposed
  example uses the plaintext `http` face alone, so no TLS backend, CA file or ALPN enters its
  output, and every request is HTTP/1.1 (`http-version #f` over `http://`, `transfer.sls:996-999`).
- **The working directory is the repository root,** so a file part names
  `examples/data/hello.txt`, resolved against `current-directory` as the request is made
  (`transfer.sls:1450-1451`).
- **The counts, by a wrapper, not by the example** (README.md, question 1). AGENTS.md's counters
  rule needs a child that reaches native to print its counts; today's children import `(curl
  private counters)` themselves (`tests/proxy-env.sps:34-35`, `transfer-tls-env.sps:50`,
  `refusal-probe.sps:69`). An example that did would teach a caller a private library, and the
  plan's §3.5 has the example print them. Measured instead: `child/example-runner.sps` loads the
  example as a top-level program in its own process, by Chez's `load-program`, with
  `(command-line)` as the example's, then writes `(counts ALIST)` on stderr. It worked on all five
  runs, the counts zero (`logs/child-cost-native.txt`). The suite then holds: exit 0; stdout equal
  to `examples/expected/NAME.out` byte for byte; stderr exactly the counts line, every count 0. An
  example must not call `exit`, or the wrapper never prints its counts.
- **How today's suites run a child:** `capture-command` (`tests/curl-testing.sls:140-193`), argv
  `$CHEZ --libdirs LIBDIRS --program FILE ARG ...` through `/bin/sh`, stdin `/dev/null`, stdout and
  stderr into files of a fresh directory, the exit status as `system` reports it
  (`tests/test-proxy.sps:1652-1667`, `tests/test-mailbox.sps:240-246`). The child reads its output
  back as data (`read-all`, `test-proxy.sps:2105-2112`) and the suite asserts its counts line
  (`test-mailbox.sps:612-621`, `(list 'counts zero-counts)`).

## What a child costs

| Run | Each child, ms | Log |
|---|---|---|
| `child-probe.sps`, one `http-get`, plain `--program`, 5 runs, natively | 472, 473, 477, 478, 486 | `logs/child-cost-native.txt` |
| the same through `example-runner.sps`, 5 runs, natively | 475, 476, 479, 483, 533 | the same |
| the same 10, the parent under the gate's Valgrind flags (`-v --command-line-only=yes --log-file --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite --suppressions=tests/guix-glibc-locpath.supp`, `Makefile:579-580`) | 479 to 572 | `logs/child-cost-valgrind.txt`, `.valgrind` |
| `tests/test-mailbox.sps`, which spawns 2 children (`test-mailbox.sps:612-621`), whole, natively / under those flags | 6,389 / 22,875 total | `logs/test-mailbox-times.txt`, `test-mailbox-gate.valgrind` |

Each run's own wall time, read by the parent around `capture-command` (`child/child-cost.sps`),
`taskset -c 6-17`, in the Guix container. A child is nearly all Chez's start and the expansion of
`src/` from source: one GET is a few ms of it.

**Valgrind does not follow the children.** The gate passes no `--trace-children=yes`
(`Makefile:579-580`), whose default is no. Measured: under those flags the parent reads Valgrind's
preload in its own `/proc/self/maps`, `(parent-valgrind #t)`, and each of the ten children reads
none, `(valgrind #f)` (`logs/child-cost-valgrind.txt`); the Valgrind log holds one `Command:` line,
the parent's, 0 errors, 0 bytes definitely lost (`child-cost-valgrind.valgrind`); and so does
test-mailbox's (`test-mailbox-gate.valgrind`: one `Command:`, 0 errors). So under the memory gate
an example runs natively: its memory is held by its counts alone, and its cost is the native
0.5 s. Ten examples cost about 5 s of children per run, on either gate. `test-examples` must still
be in a memory shard: `check-memory-gate` holds the two lists to every `tests/test-*.sps`
(the M8 plan §3.2).

## The ten examples

Each is a whole program, `(import (rnrs) (http-client))` or `(curl)`, one origin URL in. Routes
from `tests/origin.mjs`: `/status/CODE` (:40), `/redirect/CODE?to=` (:41), `/echo` (:44,
`:1523-1531`: the request line, each raw header, a blank line, the body), `/pattern/N[?delay=MS]`
(:45), `/sink?key=` (:56, its line :443-460), `/seen?key=` (:58), `/parts?key=[&fail=F]` (:79,
:365-390), `/cookies?key=&set=` (:81, :503-530). Keys are distinct across examples: one origin
serves the suite, and `/sink`'s `seen=` and `/seen` count by key.

| # | File | Level, topics | Routes | Prints (measured on Guix) |
|---|---|---|---|---|
| 1 | `quick-start.sps` | high: sessions, verbs; README.org's taste | `GET /status/200` | `200`, `status 200` |
| 2 | `form-and-params.sps` | high: params, forms | `GET /echo` with `params (("q" . "chez scheme") ("page" . "2"))`; `POST /echo` with `form (("name" . "Ada Lovelace") ("lang" . "Scheme"))` | `GET /echo?q=chez+scheme&page=2 HTTP/1.1`; `POST /echo HTTP/1.1`, `Content-Type: application/x-www-form-urlencoded`, `name=Ada+Lovelace&lang=Scheme`: the echo's request line, its `Content-Type` line, its last line, never its `Host` (a port) |
| 3 | `multipart.sps` | high: multipart, the default types; low level as a fragment | `POST /parts?key=mp-1`, parts: a string, a bytevector with `filename "notes.txt"`, `(file "examples/data/hello.txt")`, a bytevector with `type "application/x-thing"` | `count=4`, then each `part I headers=... len=L sha256=H pattern=P data=D` line whole: `Content-Disposition: form-data; name="doc"; filename="hello.txt"|Content-Type: text/plain`, etc. Never the report's first line: its `ct=` holds the boundary, and its `bytes=` the boundary's length, 16 hex chars on 7.85.0 and 22 on 8.20.0 (ADR-0038:44) |
| 4 | `session-retries.sps` | high: sessions, redirects and retries | `GET /redirect/302?to=/status/200`; `GET /parts?key=retry-1&fail=2` with `retry (make-http-retry 'attempts 3 'backoff-ms 10 'jitter #f 'statuses '(503))`; `GET /seen?key=retry-1` | `200 (302)`: the status, the history's; `200` and the empty report line `parts http method=GET cl=- te=- expect=- ct=- bytes=0 sha256=e3b0... boundary=- preamble=- closed=0 epilogue=- count=0`; `seen 3` |
| 5 | `stream-download.sps` | high: streams (`call-with-response-port`, `get-bytevector-some`) | `GET /pattern/1000000` | `200`; `1000000 bytes, pattern ok`: a count and a check of byte i = i mod 251, never a piece's size |
| 6 | `stream-upload.sps` | low: streams (`body 'stream`, puts, end, await) | `PUT /sink?key=up-1`, `body-length 300000`, puts of 64 KiB of the pattern | `200`; `method=PUT cl=300000 te=- bytes=300000 pattern=ok`: four fields of the sink line, never `arrivals=` or `gap=`, which are timing (`logs/proto-outputs-guix.txt`: `arrivals=5 gap=2.4@130981`) |
| 7 | `group.sps` | high: groups | `http-parallel` of `/status/200`, `/201`, `/404`, `limit 2`; `call-with-request-group` with two `go`s, `/status/202`, `/203` | `(200 201 404)`; `(202 203)` |
| 8 | `cookie-jar.sps` | low: jars (engine, jar, submit, read-out, load, close) | `GET /cookies?key=jar-1&set=flavour%3Doat`; `GET /echo` with the jar | `200`; `"127.0.0.1\tFALSE\t/\tFALSE\t0\tflavour\toat"`; `Cookie: flavour=oat`; after a load, both lines sorted. The lines are sorted, as the docs say their order moves |
| 9 | `errors.sps` | errors, both levels | `GET /status/404`; `GET /pattern/10?delay=2000` with `timeout-ms 200`; `GET /pattern/100000` with `body-limit 1000`; `curl-request-check` of an `https://example.invalid/` request with `http/2-prior-knowledge`, sent nowhere | `404` (a status is data); `(timeout 200 #t)`, `http-timeout-timeout-ms` and `curl-timeout?`; `(too-large perform-failed)`; `(http-version prior-knowledge-over-https)` |
| 10 | `engine-and-tokens.sps` | low: engines, requests, tokens, the mailbox | three `GET /status/20x` submitted with one mailbox; `curl-request-with` for the second URL | the statuses taken from the mailbox, **sorted**, since the order they finish in moves; then `curl-engine-stop`. Not measured |

**What none prints:** a port, a URL with its host, a date, a boundary, a `Content-Length` of a
multipart body, a piece's size, a timing, a version or a TLS backend.

## What the measurement turned up for the pages

- **A `body-limit` below a declared `Content-Length` is libcurl's 63, not `body-limit`:** the
  1,000-byte limit against a 100,000-byte `Content-Length` raised `&curl-too-large` with reason
  `perform-failed` (`logs/proto-outputs-guix.txt`, errors): `MAXFILESIZE_LARGE` refuses before a
  chunk reaches the callable. The class is alike; the reason is not. The errors example prints the
  class and the reason as measured; on the other lanes it is the suite's to see. `conditions.sls:636`
  says only "the callable refused a chunk past the body limit".
- **A redirect's history and a retry's:** the redirect's 302 joins the history, the two 503s do not,
  and `/seen` shows three requests: the page on retries can say so from this example.
- **The default type of `.txt` is `text/plain`** on this lane, for a data part with a filename and
  for a file part (`part 1`, `part 2`); `by-version.md` says whether every lane agrees.

## Risks to measure on every lane before the expected files are fixed

- The cookie line on 7.85.0 and 8.5.0 (the default path, `/` here either way, and PSL), and on
  Apple's 8.7.1.
- `seen 3`: libcurl resends a request on a reused connection that died before any response byte
  (`http-client.sls:14-18`), which would count 4. The http face keeps connections alive
  (`origin.mjs:528-530`); a run under load may show it.
- The 63 above, on 7.85.0 and 8.7.1.
- The timeout's 200 ms against a 2,000 ms delay: a margin of 1.8 s, which a loaded runner keeps.
