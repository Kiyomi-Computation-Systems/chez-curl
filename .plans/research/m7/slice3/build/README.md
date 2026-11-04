# M7 slice 3's build: the logs it cites

Kept by the slice's builder (2026-11-03), from runs made in `build/m7s3b/`, the scratch
directory, where the scripts here ran; each is a copy. Nothing here is a measurement the
records rest on but `urlprobe` and the leak probe: the rest is the build's evidence that its
checks passed, and that each was seen to fail.

## What curl_url does with a proxy URL (`urlprobe.sps`)

`urlprobe.sps` parses each of 51 proxy URLs with `curl_url_set`, with no flags and with
`CURLU_NON_SUPPORT_SCHEME` (8), and prints each part `curl_url_get` gives back, and the URL
with its port set. Run on the five Linux lanes: `results/urlprobe-guix-8.20.0.log` (the
container), `results/urlprobe-docker.log` (floor 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with
GnuTLS, 8.23.0, by `probe-docker.sh`), and `results/urlprobe-table.txt` (`cmp.py`'s table of
the two, every case, `all` where the five agree).

- **The flag:** with no flags, `socks5://`, `socks4a://` and `socks5h://` parse on 8.23.0
  alone (5 elsewhere), and `foo://` nowhere; with `CURLU_NON_SUPPORT_SCHEME` every one of them,
  and `ftp://`, parses on all five, so chez-curl's own judgement of the scheme answers
  `proxy-scheme` alike. No scheme (`127.0.0.1:3128`, `localhost`) and an empty URL stay refused
  with the flag, by codes that vary (27, 28, 3), each `proxy-url`.
- **A `%` not followed by two hex digits** (`%zz`, `%`, `%4`, `%z`) in the user or the password
  parses on all five, and comes back as written: chez-curl refuses it as `proxy-url`.
- **A raw control byte, space or 0x7F** in the userinfo is refused by the parse on all five, by
  codes that vary (29 or 24 on 7.85.0 and 8.23.0, 3 elsewhere): `proxy-url`.
- **Empty userinfo:** 7.85.0 reports no user and no password for `@` and `:@`, and no password
  for `u:@`, and gives the URL back without them; 8.5.0 and later report `""`.
- **An empty query (`/?`)** reads `""` on 7.85.0 and 8.5.0 and none on 8.20.0 and 8.23.0; an
  empty fragment none everywhere; the URL given back drops both everywhere. chez-curl counts
  each as none.

## The checks

- `results/make-test-guix-8.20.0-1.log`, `-2.log`: `make test` in the container, twice, 38 of
  38 each.
- `results/lanes-final.out`: the changed suites, 15, on the four Docker lanes, test-proxy run
  twice in each (16 runs), 16 of 16 on each, with every by-version row test-proxy measured;
  `lanes.sh` and `lanes-in-docker.sh`, slice 2's, on a snapshot of the tree (`snap.sh`) that
  matches the handed-back `src/` and `tests/`. `results/lanes-final-{floor,gnutls,current}.log`
  are those lanes' whole logs; the OpenSSL lane's was written over by the memory run's, which
  took the same tag, so its lines are in `lanes-final.out` alone. `results/lanes-first-openssl.log`
  is an earlier full run there.
- `results/memory-openssl-8.5.0-final.log` and `.out`: `make test-memory` of test-proxy and
  every changed suite on Ubuntu's 8.5.0 with OpenSSL, 15 of 15.
- `results/leak-guix-8.20.0.log`, `results/leak-docker.log`: `leak.sps`, after slice 2's
  review's, on the five lanes: every exit a request with a proxy password can take, 59 lines,
  each `secret printed: no` (236 on the four Docker lanes). It once found one: a misused
  `call-with-http-session` printed the URL it was handed as its last argument's irritant.

## A trap: the `CONNECT` socket stays half-open (`halfopen.mjs`)

`http.Server` makes its sockets `allowHalfOpen`, and the one it hands a `connect` event keeps
that: after a client's FIN it stays open until destroyed. The origin's proxy answers a refused
`CONNECT` keeping the connection, so without `client.on('end', () => client.destroy())` in
`proxyRefuse` its open count never fell to 0 once libcurl closed. `results/halfopen-node-24.log`:
Node 24.18.0 in the container, one connection open a second after the client's end without the
handler, none with it.

## The mutants

`mutants.py` holds each mutant as a row: a file, the text it replaces, and the suites it must
fail; `mutate.py` makes its copy of the tree, `run-mutant.sh` runs suites on it in the
container, `run-container-mutants.sh` and `run-docker-mutants.sh` drive them.

- `results/mutants-container-guix-8.20.0.txt`: 35 mutants and a control, 42 runs (some ran on
  two suites), each with its suites' exit status
  and the first tests that failed. Every one failed. test-origin's two SIGKILL tests fail in
  every copy whatever it holds, `control`, the last entry, a copy with no change, among them:
  `run-mutant.sh` runs a suite by `$CHEZ` in a copy that has no `build/`, and their child names
  `build/scheme-libs` by a relative path, so it prints no line. They pass in the tree. Each
  mutant counted on test-origin fails a test besides those two.
- `results/mutants-docker.txt`: 7 mutants a Linux container cannot show, each on the lane that
  can: the TLS-inside-TLS rows (GnuTLS 8.5.0, 7.85.0, the backend's key on OpenSSL 8.5.0), the
  check at submit, and `FRESH_CONNECT`'s and `FORBID_REUSE`'s effects below 8.19.0 (7.85.0).
  Each lane's log is `results/mutant-LANE-NAME.log`.

## The fix round, after the review

The review's findings (`../review/README.md`) and ADR-0037's decision 11, built on the same
tree. Scripts here, logs under `results/fix-*`.

### Decision 11: the switch against a live transfer (`switch-live.sps`)

On one engine: A1 and A2 stream `/connection?delay=2500` on the h2 face, sharing a connection;
then S, an `https://` URL through the http face's proxy with alice's userinfo; then B,
`/connection` on the h2 face, direct, while A1 and A2 are live. Each body names its HTTP/2
session. The control leaves out S. Two of each per lane: `results/fix-switch-live-docker.log`
(7.85.0, both 8.5.0s, 8.23.0) and `results/fix-switch-live-guix-8.20.0.log`.

- 7.85.0 and both 8.5.0s: the engine reads `default` before S and `switched` after it. A1 and
  A2 end 200 on their connection, their bodies whole, unbroken. B, made while they were live,
  opens a connection of its own. Without S, B rides theirs.
- 8.20.0 and 8.23.0: no switch, and B rides theirs with S or without.

test-proxy's `switch-live` and `environment-join` tables hold the same, through the engine and,
for the review's `env-join` case, in a child with `https_proxy` set (`tests/proxy-env-join.sps`).
Under `never-switch` on 7.85.0 the child's transfer through `proxy environment` gets 200 on
alice's tunnel, with no `CONNECT` of its own (`results/fix-mutant-floor-never-switch.log`): the
review's blocker, in the suite.

### The environment proxy's userinfo (`env-userinfo.sps`)

`tests/proxy-env.sps` in a child, one variable set, `proxy environment`, the transfer to the https
face (or the http face, by `http_proxy`). Two runs on each of five lanes, alike:
`results/fix-env-userinfo-docker-{1,2}.log`, `results/fix-env-userinfo-guix-8.20.0-{1,2}.log`.

- A user or password that decodes to 0x00 to 0x1F (`%00`, `%01`, `%1F`), in `https_proxy`,
  `http_proxy` or `all_proxy`: 7.85.0 and both 8.5.0s go direct, 200, nothing on the proxy's log,
  as a named proxy's did; 8.20.0 and 8.23.0 fail 3.
- `%7F` goes through the proxy, its byte in the Basic credentials, on all five.
- A raw 0x01 in the variable fails 5 on all five.

### The audit (`audit.py`)

`results/fix-audit-sites-before.txt` and `-after.txt`: every raise site in `src/` that can carry a
value, before and after the round. Each that held a caller's misplaced value now names it by
`shown-value` or `shown-key`, `(kind K)`; the hand-back lists what was left, and why.

### The checks

- `results/fix-lanes.out`, `results/fix-lanes-{floor,openssl,gnutls,current}.log`: the changed
  suites, test-group and test-engine with them, on the four Docker lanes, test-proxy twice: 18 of
  18 on each.
- `results/fix-memory-openssl-8.5.0.{log,out}`: the memory gate.
- `results/fix-make-test-guix-8.20.0-{1,2}.log`: `make test` in the container, twice.
- `results/fix-leak-*.log`: `leak.sps`, the misplaced values added, 77 lines a lane, each `no`;
  `results/fix-keys-leak-*.log`: the review's `keys-leak.sps`, 12 lines a lane, each `no`.

### The mutants

`mutants-fix.py`, as `mutants.py`. `results/fix-mutants-container-guix-8.20.0.txt`: 22 mutants,
each failing, and a control copy that passes test-proxy, test-transfer, test-conditions,
test-http-client and test-constants. `results/fix-mutants-docker.txt` and
`results/fix-mutant-floor-*.log`: `never-switch`, `switch-resumes` and `switch-every` on 7.85.0,
each failing.

## The second fix round: accessors and refused URLs

The maintainer's decision (ADR-0036 and ADR-0008, amended 2026-11-03): every public accessor
names a wrong argument by its kind, and a refused URL's message and irritants name its field.

- `exports-leak.sps`: every procedure export of `(curl)`, `(curl unsupported)` and
  `(http-client)`, called with a URL holding a password as every argument at each arity from 1
  to 3. `results/fix2-exports-leak-before-guix-8.20.0.log`: 78 printed the password, each a raw
  record or condition accessor. `-after`: none.
- `wrap-accessors.py`: the edit that renamed each to `unchecked-NAME` and defined `NAME` by
  `checked-accessor`; `libcurl-info.sls` was done by hand, with its own copy of the rule, since
  `(curl private conditions)` imports it.
- `exports-table.sps`: `results/fix2-exports-table-guix-8.20.0.txt`, the rows
  `tests/test-printed.sps` writes out, one per export, 186.
- `results/fix2-mutants-container-guix-8.20.0.txt`: `mutants-fix2.py`'s 8 mutants, each failing
  test-printed, and a control copy that passes it.
- `results/fix2-make-test-guix-8.20.0-{1,2}.log`: 39 of 39, twice, test-printed the new suite.
- `results/fix2-lanes.out`, `results/fix2-lanes-*.log`: 24 suites, test-proxy twice, on the four
  Docker lanes, every one passing; `results/fix2-memory-openssl-8.5.0.{log,out}`: 23 of 23.
- Leak probes, every line `no`: `results/fix2-leak-*.log` (`leak.sps`, 97 lines a lane, the
  accessors and the URL refusals added), `results/fix2-keys-leak-docker.log` (the review's
  `keys-leak.sps`), `results/fix2-accessor-leak-docker.log` and
  `results/fix2-keys-accessor-leak-guix-8.20.0.log` (the verify's `accessor-leak.sps`).
