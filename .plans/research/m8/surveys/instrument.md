# M8 survey B: the test instrument for multipart and the header cap

Read-only survey, 2026-11-06, on `docs/m8-plan` at `fbc6fce`. It reports what the instrument can show
today and what multipart (`curl_mime`) and a cap on response headers would need from it. It designs
nothing and recommends nothing.

**Method.** Files were read and grepped; nothing was run: no make target, suite, Node, Docker or
network. Each claim cites `file:line`, or a record and its section. Paths under `build/` are
git-ignored scratch (`.gitignore:7`) on this host only, never kept: where a fact comes from a curl
source copy there, it says so. Their existence was checked with `test -e` alone.

## 1. The origin (`tests/origin.mjs`)

### 1.1 Faces

| Face | Built on | Serves | Where |
|---|---|---|---|
| `http` | `node:http`, no options | the well-formed routes; a plain proxy | `origin.mjs:37-84`, `:1459` |
| `https`, `https-expired`, `https-wrong-host`, `https-untrusted` | `node:https`, ALPN `http/1.1` alone | http's routes and bytes; an `https://` proxy | `:273-277`, `:1642` |
| `raw` | `node:net`, half-open | scripts by `/raw/NAME?QUERY`. It reads a request head up to 64 KiB, then closes after each script | `:85-265`, `:1917`, `:3014` |
| `raw-tls` | `node:net`, each socket wrapped in `tls.TLSSocket` | raw's scripts | `:278-282`, `:3029` |
| `h2c` | `node:http2`, plaintext, prior knowledge, half-open | the HTTP/2 routes | `:266-272`, `:1902` |
| `h2` | `node:http2`, secure, ALPN `h2` alone | the HTTP/2 routes | `:283-290`, `:1905` |

The contract: one JSON announcement line; loopback only; exit 0 at stdin's end; a bad client ends
only its own connection (`:5-34`; `global-constraints.md:450-466`). The imports are Node's
standard library alone: `node:crypto`, `fs`, `http`, `http2`, `https`, `net`, `process` and `tls`
(`:489-496`).

### 1.2 Routes that read a request body, echo it, or log a head or a body

| Route | Faces | Body read | What it shows | Where |
|---|---|---|---|---|
| `ANY /echo` | http, the https faces, h2c, h2 | whole | Over HTTP/1.1: the request line, then each header as Node parsed it (`rawHeaders`, the name's case kept, Latin-1), a blank line, then the body's bytes. Over HTTP/2: each pair, pseudo-headers included, in order, then the body | `:44`, `:291-296`, `:1345-1352`, `:1733-1739` |
| `/raw/echo` | raw, raw-tls | **none** | the request head's exact bytes, to its CRLF CRLF, as the body | `:2052-2056`; `test-origin.sps:545-549` |
| `ANY /sink?key=K[&list=1]` | http, the https faces, h2c, h2 | whole | One summary line: `method`, `cl`, `te`, `expect`, `ct`, `bytes`, `sha256`, `pattern` (bad@I against i mod 251), `arrivals`, `gap`, `seen`, and with `list` each arrival | `:56`, `:389-407`, `:846-872`, `:1440-1447`, `:1837-1854` |
| `/raw/sink?key=K[&hold=MS][&list=1]` | raw, raw-tls | by the head's framing: length, chunked (extensions and trailers dropped), or none | the same summary | `:168-179`, `:2170` |
| `/raw/sunk?key=K` | raw | none | how many body bytes K's latest `/raw/sink` has read | `:180-183`, `:2221` |
| `/raw/mirror` | raw, raw-tls | by framing | each decoded body piece written back, chunked when the request was, `Content-Length` echoed | `:209-218`, `:2242-2252`; `test-origin-tls.sps:1442-1447` |
| `/mirror` | h2c, h2 | streamed | each DATA chunk written back | `:323-327`, `:1789-1810` |
| `/seq`, `/raw/seq` | h2c, h2; raw | whole | the sink line in a `Sink` header, then N bytes of the pattern | `:219-226`, `:328-331`, `:1827-1836` |
| `/refuse?key=K&at=N` | h2c, h2 | counted | as `/sink`, or `RST_STREAM` after N bytes | `:310-315` |
| `/raw/cut`, `/raw/arm` (`keep`, `cut`), `/raw/answer`, `/raw/answer-at` | raw | by framing | an answer, or a close, while the body arrives | `:184-204`, `:227-254` |
| `ANY /auth?...`, `GET /auth-log?key=K` | every face | whole | One log line per request: method, `body=B` (bytes, then `:bad@I`), verdict, status, the first `Authorization` header's bytes escaped | `:335-388` |
| `/raw/auth417?key=K` | raw | by `Content-Length` | the auth log | `:255-265` |
| `ANY /cookies...`, `GET /cookie-log?key=K` | http, the https faces | whole | One log line: `Host`, each `Cookie` header's value, escaped. An open-head line for a head left unterminated | `:449-484`, `:1245-1290` |
| The proxy, `GET /proxy-log?from=N` | http, the https faces | — | `connect` (its `head=N` bytes rebuilt from what Node parsed), `request`, `inner`, `close` | `:408-447` |

On the raw face, only the body scripts keep the bytes that follow the head; "every other script
reads none" (`:233-235`).

### 1.3 How a suite reads what the origin received

- **Through chez-curl's own transfer.** A route's answer is the response body: `/raw/echo` and
  `/echo` in `test-request.sps:633-670` and `test-transfer.sps:1872-1880` and `:2031-2105`. The
  sink line is parsed by `test-upload.sps:385-422` (`parse-sink`, `sink-line`, `whole`).
- **Logs come by a second transfer**, often on a log engine of its own. Each suite writes its own
  reader: `test-auth.sps:908`, `test-proxy.sps:1262-1265`, `test-cookies.sps:760-765`, and
  test-upload's `seen-count` (`test-upload.sps:425-430`).
- **`(curl-testing)` exports no log reader** (`curl-testing.sls:64-75`).
- **The instrument's own checks** run through `tests/wire-probe.mjs`, with no libcurl
  (`test-origin.sps` header; `global-constraints.md:467-480`). Each scenario's expected bytes are
  written in the suite, never read from the origin (`origin.mjs:485-487`).

### 1.4 What a multipart route would need to show, against what exists

- **The raw body bytes:** `/echo` (the whole body after the head), `/raw/mirror` (the body alone),
  and the sink's `bytes` and `sha256`. The sink's `pattern` field tests only the 251-byte pattern.
- **The request's `Content-Type` with its boundary:**
  - `/echo`'s header line, as Node parsed it;
  - `/raw/echo`'s exact head bytes, but no body;
  - the sink's `ct=` field. That field joins repeats with `,` and writes whitespace as `_`
    (`origin.mjs:851-854`), so `; boundary=` arrives as `;_boundary=`.
- **Each part's headers: not found.** No route parses a multipart body. A grep of
  `tests/origin.mjs`, `tests/wire-probe.mjs`, every `.mjs` under `.plans/research/` and `scripts/`
  found no `multipart`, `boundary`, `formData`, `Request`, `Response`, `undici` or `busboy`. The
  parts are visible only inside `/echo`'s body bytes.
- **libcurl's boundary is random per mime.** Read from scratch sources, not measured:
  - on 7.85.0 it is 24 dashes and 16 hex characters from `Curl_rand_hex`
    (`build/verify/current/curl-7.85.0/lib/mime.h:29-30`, `mime.c:1289-1291`);
  - on 8.20.0 and 8.23.0 it is 24 dashes and 22 alphanumerics from `Curl_rand_alnum`
    (`curl-8.20.0/lib/mime.h:28-29`, `mime.c:1213-1215`; `curl-8.23.0/lib/mime.h:28-29`,
    `mime.c:1255-1257`).

  So a multipart body's whole bytes hold a value libcurl picks at each transfer. Copies of 8.5.0
  and 8.7.1's sources exist (`build/m7s4r/src/curl-8.5.0`, `build/m4s3/src/curl-8.7.1`) and were
  not read for this.
- **Node's own multipart parsing: not found in the code or the records.** No code calls
  `Request.formData()` or anything like it (the grep above). No record measures it: a grep of
  `.plans/`, `docs/` and `README.org` found nothing. ADR-0005, decision 1, allows Node's standard
  library alone, with no npm. Its Context already expected multipart in a later milestone
  (`0005-node-test-origin.md`, Context). No record settles whether the global `Request` and
  `Response` count as that library, or whether they parse `multipart/form-data` on each lane's
  Node.
- **The Node versions the lanes run:**

  | Where | Node | Source |
  |---|---|---|
  | The Guix container: `make test`, `make test-memory` locally, probe lane X | 24.18.0 | `manifest.scm:15` (`"node"`, no version) at `channels.scm`'s commit `b532aa7`, unchanged since `e8a2f63` (2026-10-04); ADR-0005 Context table; `known-transfer-verdicts.sexp:68`; `research/m7/http2/README.md:64` |
  | CI's main, gnutls, current and memory jobs | the runner's own, unpinned; 22.23.4 at CI's first run | `ci.yml:12-14`, `:361-362`; `traps.md:911-913`; `research/ci-first-run/README.md:7`, `docker.sh:8`. No kept CI log shows main's `node --version` line (`ci.yml:158`) |
  | CI's floor job | `setup-node` at the floors file's `20`; read as v20.20.2 | `packaging/floors.sexp:5`; `ci.yml:311-353`; `research/m7/slice2/verify/results/ci-floor-30c053a.log:329`; `research/m7/slice4/verify/results/ci-main-floor-a075629.log:317` |
  | CI's floor-disabled-api and nothreads jobs | none: `make build` or `check-nothreads` alone | `ci.yml:451-591` |
  | The Mac | 20.10.0, through asdf 0.15's shim | `progress.md:194-204`; `traps.md:921-926` |
  | M7's Docker probe lanes | F at 20.10.0 (`build/verify/m3s2/node20/node`, nodejs.org's tarball checked against its `SHASUMS256.txt`, `foundations-mutation-log.md:277`); O, G and C at the Guix store's 24.18.0, mounted read-only | `research/m7/http2/README.md:59-65`; `research/m7/http2/docker.sh:24-42` |
  | M7 slice 4's Docker suite lanes | 20.10.0 on all four | `research/m7/slice4/build/lanes-in-docker.sh:16` |

## 2. Test helpers and conventions

### 2.1 The shared libraries

- **`(curl-testing)`** (`curl-testing.sls:1-75`) exports:
  - the exit form and `suite-exit-status`;
  - `capture-command`, `bounded`, the temporary directories, `run-until`, `seeded-bytes` and
    `describe`;
  - `call-with-origin`, `origin-face`, `origin-timeout` and the `wire-probe` family;
  - the PKI and `s-client` helpers.

  Nothing in it reads an origin log or splits a body.
- **`(auth-testing)`** (`auth-testing.sls:12-20`) exports `md5-hex`, `sha256-hex`, `base64-encode`
  and `digest-response`, each computed by the suite and never read from the origin. test-auth,
  test-origin and test-origin-tls import it. test-upload instead writes a table of SHA-256s
  "computed outside the suite, never by the origin" (`test-upload.sps:275-293`).

### 2.2 The suite rules

- A suite's last datum is `(exit (suite-exit-status runner))`, and before it a suite may exit
  only by `(exit 1)` (`curl-testing.sls:96`; `check-suites.sps` header; `Makefile:279-286`).
- `suite-exit-status` answers 0 only with a pass, no fail and no xpass, and every native count at
  zero (`curl-testing.sls:98-140`).
- Every suite runs under `timeout --foreground`. `TEST_TIMEOUT` is 300 s and `MEMORY_TIMEOUT` is
  3600 s, and exit 124 is reported as `HUNG` (`Makefile:59-70`, `:266-274`, `:496`).
  `origin-timeout` is 5000 ms, for the announcement and for the stop (`curl-testing.sls:445-453`).
- `SUITES` is the sorted wildcard `tests/test-*.sps`, and `MEMORY_SUITES` defaults to it
  (`Makefile:55-57`, `:72-73`). A new suite joins `make test` and `make test-memory` by its name
  alone.
- `make check-test-fails` plants bad suites, a leaking one among them (`Makefile:344-350`).
- A refusal probe prints `(reason . symbol)` (ADR-0015, decision 5). Every child that reaches
  native prints its counts, and its suite asserts them zero (`global-constraints.md:545-546`).

### 2.3 The suites that cover bodies, and what each asserts

| Suite | Body | Asserts | Where |
|---|---|---|---|
| test-request | whole bytevector | Each method's head at `/raw/echo`, byte for byte: a `Content-Length`, no `Content-Type`, no `Expect`. Every byte 0 to 255, and 1,048,577 bytes, whole at `/echo`. A caller's own `Content-Type` and `Expect` in its order. The body copied at submit | `test-request.sps:630-700`, `:801-838` |
| test-upload | streamed | Each method's framing, sized and chunked, over http, raw, https and h2: the sink line's `bytes`, `pattern=ok` and `sha256` held to the table. Also pause and resume, at most once, and 64 MiB whole | `test-upload.sps:1-44`, `:275-293`, `:385-422` |
| test-transfer | none, and heads | The head at `/raw/echo` and `/echo`; header bytes 0x01 to 0xFF; the varying header scenarios (§6) | `test-transfer.sps:1872-1880`, `:2031-2105`, `:479-554` |
| test-http-client | string, bytevector, form | Each verb at `/echo`. The form encoding pure, over every char below U+0100 and its complement. `with-form-type`'s `Content-Type` | `test-http-client.sps:14-24`, `:433-439`, `:464-491` |
| test-redirect | the method and body per status | 300 to 308 with each method at `/echo`; a body kept or dropped | `test-redirect.sps:20-24` |
| test-retry | attempts | The retry script's counts at the origin | `test-retry.sps` header |
| test-stream, test-stream-call | response; producer | Every byte in order over every face; a producer's pieces; at most once | each header |
| test-auth | through `/auth` | The log's `body=B` with the pattern check | `origin.mjs:368-372` |

### 2.4 Conventions a new suite meets, by the records

- Expected values are written in the suite, as whole outputs, and none is `#f`. A raise is
  answered as data under a guard (AGENTS.md, Tests traps).
- A check on the raw face runs on its own engine or session, since 8.23.0 reuses dead pooled
  connections (`test-upload.sps:42-44`; ADR-0020, amended).
- Every bound holds under Valgrind (`test-upload.sps:46-48`).
- An answer that varies by version is a row per libcurl version. A libcurl with no row fails and
  prints its row (`test-transfer.sps:2615-2619`; `known-transfer-verdicts.sexp:1-29`).
- Requests are made with `'proxy #f` (`test-upload.sps:299-300`), and ambient proxy variables
  fail test-transfer first (`traps.md:955-959`).
- The counts lists are written out: `zero-counts` and `running-counts` (`test-upload.sps:93-102`).

## 3. M7's probes (`.plans/research/m7/{http2,cookies,auth,proxies}/`)

### 3.1 Their shape

Each probe has these parts:

- `probe.c`, which drives libcurl's multi interface in M6's pause probe's loop, mirroring the
  engine's turn, with the engine's options;
- `server.mjs`, a stand-in on Node's standard library alone;
- `run.sh LANE`, one libcurl;
- `docker.sh`, the four Docker lanes;
- `mac.sh`;
- a `README.md`;
- `results/`.

`research/m7/http2/README.md:46-56` and `probe.c:1-50` describe it. The extras are auth's
`tables.mjs`, `readme-tables.mjs`, `wire-control.sh` and `selftest-control.sh`; cookies'
`compare.sh`; and proxies' `summarize.mjs` and `digest-check.mjs`.

**The lanes** (`research/m7/http2/README.md:59-65`):

| Lane | libcurl | TLS | Runs on |
|---|---|---|---|
| F | `build/e1/ci/curl-floor/lib/libcurl.so.4`, 7.85.0 | OpenSSL 3.0.13 | Docker |
| O | Ubuntu's `libcurl.so.4`, 8.5.0 | OpenSSL | Docker |
| G | Ubuntu's `libcurl-gnutls.so.4`, 8.5.0, against `libcurl4-openssl-dev`'s headers | GnuTLS 3.8.3 | Docker |
| X | the Guix profile's 8.20.0 | GnuTLS 3.8.13 | the Guix container |
| C | `build/verify/c823/lane1/curl-current`, 8.23.0 | OpenSSL | Docker |
| the Mac | Apple's 8.7.1, by `-lcurl` and the SDK's headers | SecureTransport (LibreSSL) | the Mac |

### 3.2 The exact commands, run from the repository's root

```sh
# lane X, in the container
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/<probe>/run.sh guix-8.20.0' < /dev/null
# lanes F, O, G and C, in Docker
sh .plans/research/m7/http2/docker.sh                                     # no argument
sh .plans/research/m7/cookies/docker.sh build/verify/c823/lane1/curl-current
sh .plans/research/m7/auth/docker.sh build/verify/c823/lane1/curl-current > .plans/research/m7/auth/results/docker-N.log
sh .plans/research/m7/proxies/docker.sh build/verify/c823/lane1/curl-current [main|sysstore]
# the Mac
sh .plans/research/m7/http2/mac.sh
NODE="$(asdf which node)" sh .plans/research/m7/cookies/mac.sh
sh .plans/research/m7/auth/mac.sh
NODE="$(asdf which node)" sh .plans/research/m7/proxies/mac.sh
```

### 3.3 `run.sh`'s interface (`research/m7/http2/run.sh`)

- **Variables:**
  - `CURL_LIB` is a `libcurl.so.4`. It is required on Linux and unset on macOS, where the probe
    links `-lcurl` (`:6-16`, `:29-32`).
  - `CURL_INCLUDE` defaults to `CURL_LIB`'s `../include` (`:55-58`).
  - `NODE`, `CC`, `OPENSSL` and `CASES` choose the tools and the cases.
- **The compile:** `probe.c` is compiled against the library file itself, with
  `-Wl,-rpath` (`:59-66`).
- **The PKI:** each run makes a fresh one with `tests/make-test-pki.sh` (`:74-75`).
- **The stand-in:** it reads stdin from a FIFO and exits at its end. A watchdog kills it 5 s after
  that, and says so (`:38-54`, `:76-82`).
- **The environment:** it unsets the proxy variables, `SSL_CERT_FILE` and `SSL_CERT_DIR` (`:33`).
  On Darwin it sets `CURL_SSL_BACKEND=secure-transport` unless that is already set (`:22-25`).
- **Output and scratch:** every line is prefixed `[LANE]`, and the temporary directory comes from
  `mktemp` under `$TMPDIR` (`:36`).

### 3.4 `docker.sh` (`research/m7/http2/docker.sh:15-42`; cookies, auth and proxies alike)

- It mounts the repository read-only at `/src`, and `/gnu/store` read-only.
- It installs `build-essential`, `libcurl4-openssl-dev`, `libcurl3t64-gnutls`, `ca-certificates`
  and `openssl` by apt, which needs the network.
- It takes Node for O, G and C from `scripts/guix-env sh -c 'command -v node'`.
- Lane F runs with `NODE=build/verify/m3s2/node20/node`.
- Proxies' version fetches the packages once into `build/m7/proxies/apt`, then runs every case
  with `--network none` (`proxies/docker.sh:11-17`, `:41-55`).

### 3.5 What they assume

- **Prerequisites under git-ignored `build/`, present on this host today and in no clone:**
  - `build/e1/ci/curl-floor`, made by `scripts/ci/build-curl.sh` in Docker
    (`research/e1/in-docker.sh:38`);
  - `build/e1/ci/chez-threads`, made by `build-chez.sh` (`:34`);
  - `build/verify/c823/lane1/curl-current`, made by `build-curl.sh --current`;
  - `build/verify/m3s2/node20/node`;
  - proxies' apt cache.
- The Docker image `ubuntu:24.04`, digest `sha256:68ee2200…` as run (`http2/README.md:61`), and
  the network for apt.
- The Guix container, for lane X and for the store's Node.
- Two runs per lane (`http2/README.md:52`, `:350`; AGENTS.md's one-run trap).
- **How each probe was checked:** by rerunning its Guix lane (`2026-11-02-m7-plan.md:584-589`).
- **The Docker lanes are not CI's.** Their Node is 20.10.0 or 24.18.0, where CI runs 20.20.2 and
  22.23.4. The runner's pace and its kernel buffers differ too ("CI is a lane of its own",
  `progress.md`, PR #39's close-out).

### 3.6 Precedents and parts an M8 `curl_mime` probe would copy

- **The whole-suite precedent:** `research/m7/slice4/build/lanes.sh` and `lanes-in-docker.sh`.
  They run `make deps test` on a copy of the tree per lane, with `MEMORY_SUITES` and `PROBE`
  optional. Chez comes from `build/e1/ci/chez-threads`, and Node 20.10.0 on all four lanes. Their
  paths name `build/m7s4b`, where they ran.
- **The parts to copy:**
  - `http2/run.sh`: the compile, the per-run PKI, the stand-in's lifecycle and its watchdog;
  - `http2/docker.sh`: the four lanes;
  - `http2/mac.sh`;
  - auth's `server.mjs`, which logs each request's line and body as bytes, pattern and SHA-256
    (`auth/README.md:12`);
  - cookies' `probe.c` file watch, for a probe that must see libcurl open a file. It interposes
    `fopen`, `fopen64`, `open`, `open64` and `openat`, on Linux alone (`cookies/probe.c:36-40`,
    `:110-119`; `cookies/mac.sh:9-11`);
  - proxies' fetch-once, then `--network none`.

## 4. The gates a new native kind, binding or option meets

### 4.1 The counters gate

- **A kind is a symbol in `native-kinds`** (`counters.sls:26-38`). Eight exist today: `block`,
  `easy`, `url`, `slist`, `curl-string`, `transfer`, `multi` and `share`.
- **Each kind is written out again in the suites:**
  - `test-memory-safety.sps:172-174`, which holds the whole list;
  - `:207`, `every-kind`, which checks each kind alone;
  - `:106`, `zero-counts`, and `:317-319`, a child's printed counts;
  - `test-curl-testing.sps:148`, where each kind left over is named, and `:166`.
- **Every written-out counts list names all eight.** 26 files hold 48 such lines today (a grep for
  `(share . 0)`, `(share . 1)` and `multi share)`). M7 slice 4 grew them when `share` came: its merge
  touched 36 files under `tests/` (`git show --stat 088eddd`).
- **`suite-exit-status` needs no change for a new kind:** it reads `native-counts`
  (`curl-testing.sls:108-140`).
- **Each kind is made or freed in one critical section** with its count and its record
  (`global-constraints.md:611-622`). An engine's live-transfer table is emptied and checked at
  its stop (ADR-0014, amended 2026-10-25).
- **Valgrind cannot see a leak that a Chez object's address still holds.** It calls a leaked
  libcurl block whose address a Chez object held still reachable, so the counters are that leak's
  gate (ADR-0014, amended 2026-10-16; `traps.md:792-802`).

### 4.2 The memory gate

- **Every suite runs under Valgrind** with the gate's fixed options (`Makefile:441-496`). The awk
  check holds its `Command:` line, its options block, the first program it read symbols from,
  `ERROR SUMMARY: 0 errors from 0 contexts`, and the suppressions files it read
  (`Makefile:502-536`).
- **Nothing outside the command line may change it:** every `VALGRIND_*` variable and both
  `.valgrindrc` files are refused (`:447-462`).
- **Suppressions:** one entry, Guix only. `--undef-value-errors=no` comes only with a recorded run
  that needed it (`global-constraints.md:521-528`).
- **CI's memory job** loads the runner's 8.5.0 OpenSSL by discovery, after `check-memory-gate`
  (`ci.yml:596-652`). Its timeout is 60 minutes (`:599`).
- **The job's time, at `473b1b4`:** `test-memory` ran 41 suites from 14:47:03 to 15:17:50, about
  31 minutes (`research/m7/carried/verify/ci/ci-memory-473b1b4.log:1`, `:102`). From those
  timestamps, the longest suites were test-transfer at 176 s, test-upload at 141 s and test-origin
  at 119 s.
- **ADR-0014's 2026-10-16 amendment:** "If the memory job comes to take longer than 20 minutes, a
  decision moves it back to `main` and tags."

### 4.3 test-printed

- **Every export of `(curl)`, `(curl unsupported)` and `(http-client)` has a row**, written out:
  its arity and its answer when called with a URL holding a password
  (`test-printed.sps:118-330`). The test that the rows name every export is at `:336-338`.
- **Opacity:** a record that holds a request, a plan, a token or credentials is opaque, and every
  public accessor checks its argument (`global-constraints.md:893-897`, `:917-922`).
- **Other written-out lists of exports:** `test-library-loading.sps:850` and
  `test-http-client.sps:254-256`. Reasons are written out in `test-conditions.sps:241` and `:282`.

### 4.4 test-collect-safe and `(foreign-conventions)`

- **Every `foreign-procedure` and `foreign-callable` needs a row** in `conventions-table`
  (`foreign-conventions.sls:347-386`). The row's citation phrase must appear in the decision
  record it cites (`cite`, `:274-276`).
- **The crossing types:**
  - a string type needs a `string-not-kept` mark, with a citation;
  - a bytevector type is allowed on memcpy's row alone;
  - `scheme-object` is never allowed (`test-collect-safe.sps:10-18`;
    `global-constraints.md:155-162`).
- **A callable** is `(define name (foreign-callable ...))` in `(curl private transfer)` alone,
  locked, and `__collect_safe` when a `__collect_safe` call can invoke it
  (`global-constraints.md:91-94`, `:631-637`).
- **`(bound-by ...)`** binds the variadic and blocking rows to their binders.
  `make check-variadic`'s count of `bind-variadic`'s uses, "six", moves only with a variadic
  binding (`test-collect-safe.sps:61-71`). An option of object type, `MIMEPOST` among them, goes
  through setopt's existing `uptr` binding (`test-constants.sps:1123`).

### 4.5 test-constants

- **A prototype row per entry point**, in the header's own spelling (`test-constants.sps:1104-1154`).
  The test holds the rows to what `src/` binds, both ways (`:2013-2015`).
- **`c-type-map` is written out** (`:1170-1200`, test `:2101-2107`):
  - any type ending in `*` is `uptr` or `void*`;
  - "a C type in no entry here, and no pointer, fails its row by name" (`:1181-1182`).

  `curl_mime_data_cb`'s parameters `curl_read_callback`, `curl_seek_callback` and
  `curl_free_callback` (7.85.0 `curl.h:2416`, a scratch copy) are typedef names. None of them is
  in the map.
- **`callable-rows`** holds five callables, each tied to its typedef (`:1159-1171`).
- **`constant-rows`:** each new constant needs a row. A constant newer than the floor carries its
  gate (`global-constraints.md:52-63`).
- **`enum-names`:** each new enum type needs a row (`:1604-1609`).
- **The headers** must be no newer than the library loaded (`:72-77`).

### 4.6 Loading, and the thread rule

- **Every entry point is bound eagerly at load,** and one the library lacks is `missing-api`, by
  name (`global-constraints.md:193-196`, `:207-208`).
- **For the load checks, each entry point needs** a row in `test-library-loading.sps:451-491` and a
  stub guarded by `DECOY_LACKS_<entry>` in `tests/decoy-libcurl.c`. The share's stubs are at
  `:453-476`.
- **The thread rule:** every handle is recorded with the thread that made it, and every exported
  procedure that takes one checks it (`global-constraints.md:580-585`). `test-native.sps:193-296`
  makes each kind on another thread and asserts `&curl-wrong-thread` for each procedure. M7 slice 4
  added the share there.

### 4.7 check-seam and known-macros

- **check-seam's allowlists:** `allowed-chez-names` (`check-seam.sps:139-170`) and
  `library-only-chez-names` (`:172-205`).
  - Only `(curl private native)` may import `foreign-procedure`, `ftype-set!` or
    `load-shared-object`.
  - Only `(curl private transfer)` may import `foreign-callable`, `foreign-callable-entry-point`
    or `lock-object`.
  - Only `(curl private memory)` may import `foreign-alloc` or `foreign-free`.
- **Each file under `src/` holds one library,** at its name's path
  (`global-constraints.md:425-430`).
- **`known-macros`** has five rows (`foreign-conventions.sls:392-404`). A new macro is a reviewed
  change to it (`global-constraints.md:95-117`).

### 4.8 Owned options

- **The lists are written out** in `test-unsupported.sps:312-345` (its test at `:347-352`),
  `test-transfer.sps:1341-1372` (`owned-option-names`) and `:1374` (`request-field-options`). The
  code's own are in `transfer.sls:1619` and `:1781`.
- **`MIMEPOST` and `HTTPPOST` are owned already,** as twins: "another body, size or form"
  (`transfer.sls:1679-1680`; `global-constraints.md:380-381`).
- **`MIME_OPTIONS`: not found.** A grep of `src/`, `tests/` and `.plans/decisions/` gave nothing.

### 4.9 A libcurl built without mime

- **curl compiles stubs** for an API that is configured out, as the traps record for the options
  and header APIs. In 7.85.0's `mime.c:1927-2028`, read from a scratch copy, `curl_mime_init`
  answers NULL and the rest `CURLE_NOT_BUILT_IN`.
- **`--disable-mime`** exists in `configure.ac:3977` (7.85.0) and `:4749` (8.23.0). 8.23.0 also has
  `--disable-form-api` (`:4787`).
- **No `CURL_VERSION_` bit names mime or forms:** a grep of 8.23.0's `curl.h` found none.
- **Precedents:** `scripts/ci/build-curl.sh` names no mime flag (`:143-177`). The
  `floor-disabled-api` jobs (`ci.yml:447-543`, `scripts/ci/expect-missing-api.sh`) and the load's
  probes by a call (`global-constraints.md:197-201`) handle a disabled API.

## 5. CI (`.github/workflows/ci.yml`)

| Job | libcurl | Node | Runs | Where |
|---|---|---|---|---|
| main | the runner's `libcurl4t64` 8.5.0, OpenSSL, by discovery | the runner's | `check-help check-suites check-pins check-seam check-floors build test check-test-fails check-variadic check-dev check-clean` | `:102-169` |
| gnutls | `libcurl-gnutls.so.4` 8.5.0, through `CHEZ_CURL_LIBCURL` | the runner's | `make build`, which must name GnuTLS, then `make test` | `:176-235` |
| floor | 7.85.0, built, with `CHEZ_CURL_LIBCURL` and `C_INCLUDE_PATH` naming it | `setup-node` at 20, version checked | `make build`, its version checked, then `make test` | `:237-354` |
| current | 8.23.0, built with `--current` | the runner's | `make build` against `curl-config`'s version, then `make test` | `:362-445` |
| floor-disabled-api × 2 | 7.85.0 built with `--disable-get-easy-options`, and with `--disable-headers-api` | — | `expect-missing-api.sh` | `:451-543` |
| nothreads | — | — | `make check-nothreads` on a `--nothreads` Chez | `:545-591` |
| memory | the runner's 8.5.0, OpenSSL | the runner's | `check-memory-gate`, then `test-memory` | `:596-652` |

- **The basics:** each job's timeout is 60 minutes. Chez is built from its tarball and cached, and
  every action is pinned to a commit. CI runs no macOS and no Guix container (`:3-10`).
- **A new suite joins every job by its name.** No line of `ci.yml` lists suites. main also runs
  `check-test-fails` and `check-variadic`, each on a copy of the tree. `check-variadic` runs
  test-collect-safe, test-variadic and test-transfer on its mutants (`Makefile:352-377`).
- **A by-version table needs a row** for each lane's libcurl, or that lane fails, printing its row
  (ADR-0017).
- **The paths filter:** pushes to `main` and pull requests ignore `.plans/*` and
  `.plans/research/**` (`:62-73`). Tags are never filtered, and `.plans/decisions/` runs every job
  (`:21-25`; `progress.md:84-86`). This file runs no job.

## 6. The header cap's instrument

### 6.1 The routes

- **`/raw/big-header?bytes=N`**, N from 1 to 1,048,576: a 200, then one `X-Big` header of N `a`s,
  no body, then the close (`origin.mjs:1996-2001`).
- **`/raw/many-headers?count=N`**, N from 1 to 100,000: `X-H-1: v` to `X-H-N: v`
  (`:2002-2010`).
- Both play on raw and raw-tls, so over HTTP/1.1 alone. test-origin holds them at 1 and 5 bytes,
  at 1 and 3 headers, and at the most each takes (`test-origin.sps:480-500`), and refuses
  out-of-range values (`:732-733`).
- **Elsewhere, not found:**
  - no HTTP/2 route sends large or many headers (`origin.mjs:291-333`);
  - no route varies size and count together, repeats one name, puts many headers into 1xx heads
    (`/early` and `/raw/early` send one 100 and one 103) or into trailers (one, in
    `chunked-extensions-trailers`, `:1957-1960`), or spreads headers across several responses of
    one transfer, but for libcurl's own resends (`/raw/auth417`, `:255-265`; `/auth`'s rounds).
- **Other routes that write a header per query pair:** `/cookies`' `set=` (`:456-459`) and
  `/raw/location`'s `to=` (`:99-111`). The request head bounds their count: 64 KiB on the raw face
  (`:1917`). The `node:http` faces' own limit is not stated in any record or option (`:1459` and
  `:1642` pass none).

### 6.2 test-transfer

- **Shared answers, each a 200 whole on every libcurl:** `big-header` at 1,000 and 102,380 bytes,
  and `many-headers` at 10 and 1,000 (`test-transfer.sps:516-521`). Headers are read through
  `curl_easy_nextheader`, `CURLH_HEADER`, for the last request (`:479-480`).
- **Varying cases:** `big-header` at 102,400 and 1,048,576 bytes, and `many-headers` at 50,000
  (`:540-554`). Their answers, in `known-transfer-verdicts.sexp:31-90`:

  | libcurl | 102,400 bytes | 1,048,576 bytes | 50,000 headers |
  |---|---|---|---|
  | 7.85.0 | 27 | 27 | 200, all 50,000 |
  | 8.5.0, OpenSSL and GnuTLS | 27 | 27 | 56 |
  | 8.7.1 | 100 | 100 | 56 |
  | 8.20.0 | 100 | 100 | 100 |
  | 8.23.0 | 100 | 100 | 100 |

- **The classes:** 27 is of no class, 56 is `send-receive` and 100 is `too-large`
  (`test-transfer.sps:296-308`).
- **The bounds:** each await is bounded at 60,000 ms (`:224-240`), and a request's timeout at
  20,000 ms (`:206`).

### 6.3 The timings recorded

`research/ci-first-run/README.md:32-33` and `traps.md:1348-1356` record these, measured by
`research/ci-first-run/many-headers.sps` through chez-curl:

- 7.85.0 took 20,000 headers in 1.3 s, 50,000 in 7,280 to 7,706 ms (7,296 to 7,702 ms of CPU, five
  runs), and 100,000 in 30.4 to 31.5 s. All of it was CPU, after the transfer had ended.
- 8.5.0, with OpenSSL and with GnuTLS, took 20,000 in 1.9 s, and refused 30,000 and more with 56.
- 8.20.0 and 8.23.0 refused 20,000 and more with 100.
- test-transfer whole on the floor took 15.8 s with its case at 50,000, and 39.6 s at 100,000. At
  100,000 it outlasted the 60 s bound once in three runs on CI's floor lane.
- **8.7.1: not found.** No timing exists. Its row notes that 50,000 headers are about 690 KB, past
  its 300 KiB cap (`known-transfer-verdicts.sexp:56`).
- **Under Valgrind: not found.** The memory lane's 8.5.0 refuses 50,000, so no record times a long
  header walk under the gate.

### 6.4 libcurl's own caps

- **7.85.0:** no cap on a response's headers. `CURL_MAX_HTTP_HEADER` is 100 KiB a header, past
  which it answers 27 (`ci-first-run/README.md:41-42`; `test-transfer.sps:302`; scratch
  `curl-7.85.0/include/curl/curl.h:248-252`).
- **8.5.0:** its scratch `lib/http.h:190-193` defines `MAX_HTTP_RESP_HEADER_SIZE` as 300 × 1024.
  The records name that cap for 8.7.1 and 8.20.0 alone. It answers 56.
- **8.7.1:** 300 KiB, and 56 (the records).
- **8.20.0 and 8.23.0:** 300 KiB, and 5,000 headers (scratch `http.h:155`, `:160` and `:157`,
  `:162`). They answer 100. The count runs across a transfer's requests: 5,001 requests answered
  417 stopped with 100 (`research/m7/slice2/README.md:858-860`).

### 6.5 What a test of a chez-curl cap would need, on every lane (facts)

- **Below every libcurl's cap:** 5,000 headers and 300 KiB in all (8.20.0 and 8.23.0), and 100 KiB
  a header (every version). The instrument varies the count and a single header's size, but not
  both at once.
- **The floor:** with no count cap, every count up to 100,000 reaches chez-curl, at the walk's n²
  cost: 7.3 to 7.7 s of CPU at 50,000.
- **Above a lane's own cap,** libcurl refuses first, by version, as the rows show.
- **Two paths hand headers to chez-curl:** the header callable `read-head` for a stream
  (`global-constraints.md:791-797`), and `curl_easy_nextheader` after the transfer. Which a cap
  reads is the client survey's question.
- **The memory lane's 8.5.0** refuses 30,000 headers and more with 56. The Mac's 8.7.1 answers as
  its row.
- **The time limits:** 300 s per suite, and test-transfer's 60 s await bound.

## 7. The Mac

- **What it runs:** `make test NODE="$(asdf which node)"`, and `make check-variadic` whenever a
  variadic binding changes (AGENTS.md; `global-constraints.md:39-42`). The maintainer runs them
  and pastes or uploads the output.
  - For M7: `make test` on each slice's PR, `check-variadic` on slice 4, and the four probes
    (`2026-11-02-m7-plan.md:535-554`).
  - Its latest run: 41 of 41 at `84e7e22`, 2026-11-06
    (`research/m7/carried/mac/mac-8.7.1-make-test.log:217`; `progress.md:59-60`).
- **Its setup:**
  - an M1 on macOS 26.7.1;
  - Homebrew's Chez, installed as `chez`, `tarm64osx`;
  - Apple's 8.7.1, `/usr/lib/libcurl.4.dylib`, `SecureTransport (LibreSSL/3.3.6)`;
  - Node 20.10.0 through asdf, and OpenSSL 3.6.3 first on `PATH`
    (`known-libcurls.sexp`, Apple's row; `progress.md:194-214`).
- **Its known differences, by the records:**
  - **TLS backend:** the Makefile exports `CURL_SSL_BACKEND=secure-transport` on Darwin
    (`Makefile:28-37`), against LibreSSL's keychain fallback (ADR-0024). As a MultiSSL libcurl,
    its backend and features word are read after the init (`traps.md:1378-1387`).
  - **libcurl's own:**
    - on 8.7.x the engine does not multiplex (`global-constraints.md:857-860`);
    - `CURLINFO_REQUEST_SIZE` reads 0 (`:330-332`);
    - its header answers are 56 and 100 (§6.2);
    - prior knowledge to an HTTP/1.1 server answers 16 or 56 (ADR-0034, amended);
    - `curl_version_info` names an x86_64 host.
  - **macOS:**
    - `system` serialises across threads (`traps.md:1340-1347`);
    - `poll(2)` does not support `/dev/null` (ADR-0005, amended);
    - `mktemp` needs a template under `$TMPDIR` (`traps.md:778-786`);
    - there is no `LD_PRELOAD`, so the stall checks run on Linux alone
      (`global-constraints.md:662-663`).
  - **Its tools:**
    - asdf's shim writes to stderr on every call (`traps.md:921-926`);
    - its Node did not exit when the FIFO on its stdin closed, in M4 slice 2's and slice 3's
      runners, cause unmeasured (`progress.md:1269-1270`, `:1314-1315`);
    - its git ignores `results/` globally, so logs need `git add -f`.
  - `check-variadic` there is the only arm64 evidence for variadic bindings.
- **What a probe there needs, from the `mac.sh` precedents:**
  - a Darwin check and a check that it runs from the repository's root (`http2/mac.sh:19-21`);
  - `NODE` from `asdf which node`, else `PATH` (`:22-27`);
  - `cc` and `-lcurl`, with `CURL_LIB` unset (`http2/run.sh:13-16`, `:60-64`);
  - `CURL_SSL_BACKEND=secure-transport` for a TLS case with a CA file (`run.sh:22-25`), or both
    passes (`proxies/mac.sh:20-31`);
  - temporary files under `$TMPDIR`;
  - the library named by the probe's `--version` line, `otool -L` or `ls -l`, since the dylib
    lives in the dyld shared cache (`http2/mac.sh:36-38`; `auth/mac.sh:31`;
    `cookies/mac.sh:24-25`);
  - logs written into `results/`, then `git add -f`, or into `$TMPDIR` and copied;
  - a watchdog on the stand-in;
  - no Linux-only watchers there (`cookies/mac.sh:9-11`), and a `.invalid` lookup there leaves
    loopback (`proxies/mac.sh:7-9`).
- **mime on 8.7.1: not found.** No record measures Apple's libcurl's mime API. M6's source reading
  lists 8.17.0's "mime: fix unpausing of readers" fix with 8.7.1 as a carrier, marked `?`
  (`research/m6/source-reading.md:637`).

## What the instrument lacks for multipart and the cap

1. **No route parses a `multipart/form-data` body** or reports a part's headers, name, filename,
   type or bytes. The only `Content-Type` report is the sink's `ct=` field, with whitespace written
   as `_`.
2. **No route returns a request's exact head bytes and its body together.** `/raw/echo` gives the
   head's exact bytes and reads no body. `/echo` gives the head as Node parsed it, then the body.
   `/raw/mirror` gives the body alone.
3. **No fixed boundary:**
   - libcurl picks a random one per mime: 16 hex characters on 7.85.0, 22 alphanumerics on 8.20.0
     and 8.23.0, read from scratch sources;
   - so no suite can hold a body's whole bytes written in advance;
   - nothing in `(curl-testing)` or `(auth-testing)` reads a boundary or splits a body.
4. **No code or record covers Node's own multipart parsing** (`formData()` and the like) on any
   lane's Node: 20.10.0, 20.20.2, 22.23.4 or 24.18.0.
5. **No `curl_mime` probe exists.** M7's four are the precedent, and their `build/` prerequisites
   exist on this host alone.
6. **Nothing tests a libcurl without mime:** no lane builds one, and no feature bit shows mime.
7. **The counters have no mime kind,** and every written-out counts list names eight kinds: 26
   files, 48 lines.
8. **`curl_mime_data_cb`'s types are unmapped:** `c-type-map` has no entry for its
   `curl_read_callback`, `curl_seek_callback` or `curl_free_callback`. `callable-rows` holds five
   callables.
9. **No suite watches libcurl read a file.** Only a probe's interposer does, on Linux alone (M7's
   cookies), and nothing does on the Mac.
10. **`MIME_OPTIONS` is in no owned list,** and in no record.
11. **For the cap:**
    - no HTTP/2 route sends many or large headers;
    - no route varies count and size together, repeats one name, or puts headers into 1xx heads,
      trailers, or the responses of one transfer, but for libcurl's own resends;
    - no timing exists of the header walk under Valgrind, or on 8.7.1;
    - 8.5.0's 300 KiB cap is in its scratch source and in no record.
12. **The `node:http` faces' request-head limit** is stated in no record.
13. **The memory job has little room:** it already takes about 31 minutes of its 60, against
    ADR-0014's 20-minute line.

## Questions the scope must answer

1. Does the origin gain a route that parses multipart parts, or does a suite parse what `/echo`
   returns? If the origin parses, is it through Node's global `Request` or `Response`
   `formData()`, or through a parser in `origin.mjs`?
   - Does `formData()` count as ADR-0005's standard library, and does it work on each lane's Node?
     Neither is measured.
   - If it is a parser in `origin.mjs`, is it held by a self-test, as `--selftest` holds the Digest
     arithmetic?
2. How does a suite assert a whole multipart body when libcurl chose its boundary at random? How
   does that sit beside "the suites hold their own copy of each scenario's expected bytes, never
   read from the origin" (`global-constraints.md:478-479`)?
3. Which faces must multipart run over (http, https, raw, h2c, h2), and which framings: sized, and
   chunked for a part of unknown size?
4. Which part sources are in scope?
   - data in memory;
   - a file, read on the engine's thread;
   - a callback, which needs a new callable and new `c-type-map` entries, and which M6's source
     reading ties to 8.17.0's mime-unpause fix, unknown for 8.7.1;
   - subparts, encoders, a part's own headers.

   Each changes which of §4's gates the binding meets.
5. Is a mime handle a ninth counted kind, recorded with its thread as the other handles are?
6. Is `curl_mime` measured first, by a C probe on the five Linux lanes and the Mac, built from M7's
   `run.sh`, `docker.sh` and `mac.sh`? If so, what must it answer: the boundary's form, the
   `Content-Type` and `Expect` libcurl writes, the framing, and a callback part's pause?
7. Is a libcurl with mime configured out refused at load, as the options and header APIs are, with
   a lane of its own? Or refused at submit, or not handled?
8. Is `MIME_OPTIONS` (7.81.0) owned, left to the hatch, or set by a field?
9. For the cap:
   - does it count headers, bytes, or both?
   - per response, or across a transfer's responses: redirects, auth rounds, 1xx heads, and
     streamed heads?
   - is it below every libcurl's cap, so that every lane answers alike, or above some, so that
     by-version rows say where libcurl refuses first?
   - what does it raise: which code, class and reason?
10. Does the cap need new origin routes: many headers over HTTP/2, size and count together, one
    repeated name, 1xx heads, trailers? And does its test run under the memory gate on 8.5.0, whose
    walk under Valgrind is unmeasured?
11. Does M8's growth in suites fit the memory job, which already takes about 31 minutes of its 60,
    past ADR-0014's 20-minute line?
12. Do the Mac's M8 runs include a `curl_mime` probe and `make test` per slice, with
    `check-variadic` only if a variadic binding changes?
