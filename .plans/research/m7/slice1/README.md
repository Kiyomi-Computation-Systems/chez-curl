# M7 slice 1 research: the HTTP version, through the engine

Measured 2026-11-02 for M7 slice 1 ([plan](../../../2026-11-02-m7-plan.md), section 4.1;
[ADR-0034](../../../decisions/0034-the-http-version-and-connection-sharing.md)). Every transfer
went through chez-curl's engine, on main's `src/`, or on a copy of it for a named proxy. Each
`HTTP_VERSION` went through the hatch, `curl-request-with-options`. Five Linux libcurls ran it,
two runs each. It reports what libcurl does through the engine. It recommends nothing.

## In short

- **Item 1 matches ADR-0034's C probe, cell for cell, on all five lanes.**
  - Unset, `NONE` and `2TLS` act alike. `1_1` offers `http/1.1` alone. `2_0` sends
    `Upgrade: h2c` over `http://`.
  - Prior knowledge to the origin's HTTP/1.1 `http` face sends a request, then fails: 52 on
    7.85.0, 56 on both 8.5.0s, 16 on 8.20.0 and 8.23.0.
  - Over `https://`, to the `https` face, which offers `http/1.1` alone:
    - 7.85.0 and 8.5.0 offer `h2` and `http/1.1` and read 1.1.
    - 8.20.0 and 8.23.0 offer `h2` alone, as libcurl's own lines say, and fail 35 with nothing
      sent.
  - A cell the probe lacked: `1_1` to the `h2` face, which offers `h2` alone, fails 35
    everywhere.
- **Prior knowledge through a proxy that does not tunnel is ignored on all five.**
  - This holds for the environment's proxy and for a named one.
  - The request goes as HTTP/1.1 in absolute form, and reads 200 over 1.1. It does so even to the
    HTTP/1.1 face, which fails when reached directly.
  - libcurl says `Ignoring HTTP/2 prior knowledge due to proxy`.
  - With `HTTPPROXYTUNNEL` 1, which today's hatch takes, prior knowledge speaks HTTP/2 inside a
    `CONNECT` tunnel, on all five.
- **`SSL_ENABLE_ALPN` 0 turns HTTP/2 into HTTP/1.1** at a server that offers both, for unset and
  `2TLS`, on all five. Against the `h2`-only face it fails 56.
- **`ALTSVC` moves a later transfer to another port or host, and to the alternative's version.**
  - The cache file comes from an earlier transfer or is pre-written.
  - 7.85.0 fails 1 on every move to an `h2` alternative. Its own trace reads `Using HTTP2`, then
    it sends the request as text. A source reading is below.
  - 7.85.0 and 8.5.0 move at `1_1` too, then fail 35 at the `h2`-only alternative.
  - 8.20.0 and 8.23.0 keep `1_1` and pass over `h2` alternatives. They still take an `h1`
    alternative, so the host moves at `1_1` on every lane.
  - Some things hold on all five:
    - `ALTSVC_CTRL` alone moves nothing across transfers. **Inside one transfer it does:** the
      slice's review showed a 417's resend moving to the alternative with it alone
      ([review/](review/)), so it is owned.
    - `http://` never moves.
    - A dead alternative fails 7, with no fallback.
    - The file is written when the transfer's handle is cleaned up, before its token is done.
- **`HTTP09_ALLOWED` turns the h2c face's failure into a response:** status 0, version `#f`, its
  body the server's HTTP/2 frames. `HTTP200ALIASES` reads an `ICY 200 OK` line as 200 over
  HTTP/1.0. `CONNECT_TO` moves the host, as the owned `PORT` and `RESOLVE` do. Each holds on all
  five.
- **Sharing, to `h2`, unset and `2TLS`, matches ADR-0034's probe on all five.** Two submitted in
  one batch open two connections. A second request after the first's head reuses its
  connection, and so does one after its end.
- **To `h2c` by prior knowledge, two submitted together share one connection on 7.85.0**, in
  every rep of both runs: `Multiplexed connection found`. 8.5.0, 8.20.0 and 8.23.0 open two.
- **On 7.85.0, a connection reused after the first's end reports a connect timing of 10 to
  37 µs, not 0** (18 of 18 such cases). After the head it is 0, as on every other lane.
- **No cell split between the kept runs.** A pair of runs made before the last change to the
  program read 52 once, in a cell where every kept run reads 56 ("What split", below).

## What was run

- `version.sps`, one Chez program in five parts, each its own process:
  - `versions`: item 1;
  - `envproxy` and `named`: item 2;
  - `twins`: item 3;
  - `sharing`: item 4.

  Every request carries `ca-file` and `timeout-ms` 10,000. Each wait is bounded at 15,000 ms,
  and a transfer still running then is cancelled and logged `hung`; none was. Items 1 to 3 run
  each transfer on an engine of its own. The one exception is Alt-Svc's (i), whose A and B share
  an engine. Item 4 makes a fresh engine for each rep of each case. The program's header lists
  every case.
- `run.sh LANE [PART...]` runs one lane:
  - It makes the run's PKI with `tests/make-test-pki.sh`.
  - It starts `tests/origin.mjs --pki`, unchanged, and `standin.mjs`.
  - It runs each part under GNU `timeout`: `named` on the prototype, `envproxy` with the proxy
    variables set, every other part on main's `src/` with none.
  - It first prints sha256 hashes of `src/`, the prototype, the program, the stand-in and the
    origin.
- **The origin's faces:**
  - `http`: HTTP/1.1. It is also the plain proxy, routing an absolute-form target by its path,
    and the `CONNECT` proxy to the origin's own faces, whose `/connects` counts tunnels.
  - `https`: TLS, ALPN `http/1.1` alone.
  - `h2c`: HTTP/2 by prior knowledge, plaintext.
  - `h2`: TLS, ALPN `h2` alone.

  `/echo` shows the request as each face read it. `/connection[?delay=MS]` answers its head at
  once and `connection K` MS ms on, K the connection's number on that face.
- **`standin.mjs` (Node's standard library) adds what the origin has no face for:**
  - `alt1`: TLS, `http/1.1` alone, answering `Alt-Svc: h2=":ALT2"`. A path that begins `/slow`
    gets its body 500 ms after its head.
  - `alt1h`: the same over plaintext.
  - `alt2`: TLS, `h2` alone.
  - `both`: TLS, `h2` and `http/1.1`, answering with the version and ALPN it saw.
  - `icy`: answers `ICY 200 OK`.
  - `ctl`: counts each face's TCP connections, handshakes and requests.
  - `closed`: a port nothing holds.

  Each body names the face and its connection number.
- **`make-prototype.sh`** copies `src/` to `build/m7s1/src` and changes one definition:
  `owned-option-names` leaves out `PROXY` and `NOPROXY`. `prototype.diff` is the change, two
  lines. `HTTPPROXYTUNNEL` needed no change, since today's hatch takes it. On main's `src/` the
  hatch refuses `PROXY`, `owned-option`, on all five (the `p2a` table's first row).
- **`tables.mjs`** builds the tables below from the logs alone. A cell where the runs disagree
  reads `**run 1 / run 2**`. It flagged a 52 / 56 cell in the earlier pair of runs, so the check
  can fire.

**The lanes.** All five ran on Linux x86_64, as each log's `uname` line reads.

| | lane | where | libcurl | TLS | Node | Chez |
|---|---|---|---|---|---|---|
| F | `floor-7.85.0` | Docker `ubuntu:24.04` (`sha256:68ee2200…`) | `build/e1/ci/curl-floor/lib/libcurl.so.4`, 7.85.0 | OpenSSL 3.0.13 | 20.10.0 (`build/verify/m3s2/node20`) | `build/e1/ci/chez-threads`, 10.4.0, threaded |
| O | `ubuntu-openssl-8.5.0` | same image | `/usr/lib/x86_64-linux-gnu/libcurl.so.4` (libcurl4t64 8.5.0-2ubuntu10.16) | OpenSSL 3.0.13 | 20.10.0 | as F |
| G | `ubuntu-gnutls-8.5.0` | same image | `libcurl-gnutls.so.4` (libcurl3t64-gnutls 8.5.0-2ubuntu10.16) | GnuTLS 3.8.3 | 20.10.0 | as F |
| X | `guix-8.20.0` | Guix container (`scripts/guix-env`) | the profile's `libcurl.so.4`, 8.20.0 | GnuTLS 3.8.13 | 24.18.0 | the profile's |
| C | `current-8.23.0` | Docker `ubuntu:24.04` | `build/verify/c823/lane1/curl-current/lib/libcurl.so.4`, 8.23.0 | OpenSSL 3.0.13 | 20.10.0 | as F |

**To rerun,** from the repository's root:

```sh
sh .plans/research/m7/slice1/make-prototype.sh      # on the host, first: makes build/m7s1/src
# lane X, the Guix container's 8.20.0:
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice1/run.sh guix-8.20.0' < /dev/null
# lanes F, O, G and C, one --rm ubuntu:24.04 container, on the host:
sh .plans/research/m7/slice1/docker.sh all
# both, twice each, into results/ (about 3.5 minutes):
sh .plans/research/m7/slice1/all.sh
# the tables below, from results/:
scripts/guix-env sh -c 'node .plans/research/m7/slice1/tables.mjs' < /dev/null
```

`run.sh LANE PART...` and `docker.sh LANES PART...` run only the parts named.

**The logs** (in `results/`), and their citation keys:

| key | file | what |
|---|---|---|
| `X1`, `X2` | `guix-8.20.0.log`, `guix-8.20.0-2.log` | lane X, runs 1 and 2, with the same line numbers |
| `D1`, `D2` | `docker.log`, `docker-2.log` | lanes F, O, G and C in that order, runs 1 and 2, with the same line numbers |
| `S` | `supplement-twins-docker.log`, `supplement-twins-guix-8.20.0.log` | the `twins` part twice more on each lane ("What split") |

**Checks:**

- All 50 kept part-runs exited 0, and every native count read zero at each part's end (50
  `native` lines).
- No line reads `hung`, a raised condition, or a server's stderr.
- Every log hashes `src/` to `56b78abf…` (`git diff main -- src` is empty), the prototype to
  `4c02e7f8…`, and `version.sps` to `f39cbd8a…`.
- Each lane's part ranges, the same in both runs of a log:
  - X: X1:7, 79, 112, 142, 306;
  - F: D1:12, 99, 131, 160, 286;
  - O: D1:436, 525, 556, 584, 720;
  - G: D1:866, 957, 988, 1016, 1153;
  - C: D1:1303, 1372, 1405, 1435, 1595.

  The numbers are the `versions`, `envproxy`, `named`, `twins` and `sharing` start lines, in
  order.

## The tables

Run 1 and run 2 agree on every cell below. They are `tables.mjs`'s output, unedited.

### Item 1: each HTTP_VERSION over each face (`v1` lines)

A cell: who answered (`h1-face`, `h2-face`: the origin's /echo over HTTP/1.1, over HTTP/2), status and version read; or the code and its class, and whether a request was sent (`CURLINFO_REQUEST_SIZE` above 0); `Upgrade: h2c sent` when the echo shows it.

| version | face | F | O | G | X | C |
|---|---|---|---|---|---|---|
| unset | http | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| unset | https | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| unset | h2c | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent |
| unset | h2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| NONE | http | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| NONE | https | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| NONE | h2c | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent |
| NONE | h2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| 1_1 | http | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| 1_1 | https | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| 1_1 | h2c | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent |
| 1_1 | h2 | 35 tls, none sent | 35 tls, none sent | 35 tls, none sent | 35 tls, none sent | 35 tls, none sent |
| 2_0 | http | h1-face 200 1.1, Upgrade: h2c sent | h1-face 200 1.1, Upgrade: h2c sent | h1-face 200 1.1, Upgrade: h2c sent | h1-face 200 1.1, Upgrade: h2c sent | h1-face 200 1.1, Upgrade: h2c sent |
| 2_0 | https | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| 2_0 | h2c | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent |
| 2_0 | h2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| 2TLS | http | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| 2TLS | https | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| 2TLS | h2c | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent | 1 protocol, sent |
| 2TLS | h2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| 2_PRIOR_KNOWLEDGE | http | 52 send-receive, sent | 56 send-receive, sent | 56 send-receive, sent | 16 protocol, sent | 16 protocol, sent |
| 2_PRIOR_KNOWLEDGE | https | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | 35 tls, none sent | 35 tls, none sent |
| 2_PRIOR_KNOWLEDGE | h2c | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| 2_PRIOR_KNOWLEDGE | h2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |

### Item 2 (a): the environment's proxy (`p2a` lines)

`http_proxy` and `https_proxy` name the origin's http face. A cell: the outcome; `absolute form` when the http face's /echo shows `GET http://...`; `CONNECT` when its tunnel count rose. `h2-face` is the origin's HTTP/2 /echo, reached through the tunnel.

| case | face | version | F | O | G | X | C |
|---|---|---|---|---|---|---|---|
| the hatch's PROXY, on main's src/ | - | - | refused owned-option | refused owned-option | refused owned-option | refused owned-option | refused owned-option |
| direct-pk-proxy-#f | h2c | 2_PRIOR_KNOWLEDGE | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| plain-unset | h2c | unset | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form |
| plain-pk | h2c | 2_PRIOR_KNOWLEDGE | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form |
| plain-pk-verbose | h2c | 2_PRIOR_KNOWLEDGE | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form |
| plain-pk-to-http | http | 2_PRIOR_KNOWLEDGE | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form |
| tunnel-unset | h2c | unset | 1 protocol, CONNECT | 1 protocol, CONNECT | 1 protocol, CONNECT | 1 protocol, CONNECT | 1 protocol, CONNECT |
| tunnel-pk | h2c | 2_PRIOR_KNOWLEDGE | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT |
| https-unset | h2 | unset | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT |
| https-2tls | h2 | 2TLS | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT |
| https-pk | h2 | 2_PRIOR_KNOWLEDGE | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT |

### Item 2 (b): a named proxy, on the prototype (`p2b` lines)

The hatch's `PROXY` at the http face and `NOPROXY ""`; no proxy variable set. Cells as in (a).

| case | face | version | F | O | G | X | C |
|---|---|---|---|---|---|---|---|
| plain-unset | h2c | unset | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form |
| plain-pk | h2c | 2_PRIOR_KNOWLEDGE | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form |
| plain-pk-verbose | h2c | 2_PRIOR_KNOWLEDGE | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form |
| plain-pk-to-http | http | 2_PRIOR_KNOWLEDGE | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form | 200 1.1, absolute form |
| tunnel-unset | h2c | unset | 1 protocol, CONNECT | 1 protocol, CONNECT | 1 protocol, CONNECT | 1 protocol, CONNECT | 1 protocol, CONNECT |
| tunnel-pk | h2c | 2_PRIOR_KNOWLEDGE | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT |
| https-unset | h2 | unset | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT |
| https-2tls | h2 | 2TLS | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT |
| https-pk | h2 | 2_PRIOR_KNOWLEDGE | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT | h2-face 200 2, CONNECT |

### Item 3: `SSL_ENABLE_ALPN` (`alpn` lines)

A cell: the outcome; for the stand-in's `both` face, the ALPN it chose (`none`: no ALPN).

| face | version | SSL_ENABLE_ALPN | F | O | G | X | C |
|---|---|---|---|---|---|---|---|
| https | unset | default | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| https | unset | off | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| https | 2TLS | default | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| https | 2TLS | off | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| https | 1_1 | default | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| https | 1_1 | off | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 | h1-face 200 1.1 |
| h2 | unset | default | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| h2 | unset | off | 56 send-receive | 56 send-receive | 56 send-receive | 56 send-receive | 56 send-receive |
| h2 | 2TLS | default | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| h2 | 2TLS | off | 56 send-receive | 56 send-receive | 56 send-receive | 56 send-receive | 56 send-receive |
| h2 | 1_1 | default | 35 tls | 35 tls | 35 tls | 35 tls | 35 tls |
| h2 | 1_1 | off | 56 send-receive | 56 send-receive | 56 send-receive | 56 send-receive | 56 send-receive |
| both | unset | default | both 200 2, ALPN h2 | both 200 2, ALPN h2 | both 200 2, ALPN h2 | both 200 2, ALPN h2 | both 200 2, ALPN h2 |
| both | unset | off | both 200 1.1, ALPN none | both 200 1.1, ALPN none | both 200 1.1, ALPN none | both 200 1.1, ALPN none | both 200 1.1, ALPN none |
| both | 2TLS | default | both 200 2, ALPN h2 | both 200 2, ALPN h2 | both 200 2, ALPN h2 | both 200 2, ALPN h2 | both 200 2, ALPN h2 |
| both | 2TLS | off | both 200 1.1, ALPN none | both 200 1.1, ALPN none | both 200 1.1, ALPN none | both 200 1.1, ALPN none | both 200 1.1, ALPN none |
| both | 1_1 | default | both 200 1.1, ALPN http/1.1 | both 200 1.1, ALPN http/1.1 | both 200 1.1, ALPN http/1.1 | both 200 1.1, ALPN http/1.1 | both 200 1.1, ALPN http/1.1 |
| both | 1_1 | off | both 200 1.1, ALPN none | both 200 1.1, ALPN none | both 200 1.1, ALPN none | both 200 1.1, ALPN none | both 200 1.1, ALPN none |

### Item 3 (i) and (iii): `ALTSVC` and `ALTSVC_CTRL`, two transfers on one engine, then one on a fresh engine (`altsvc-i` lines)

A cell: the face that answered, and the version. A is streamed from alt1's `/slow` (head, then the body 500 ms on); the file row reads the alt-svc file at A's head and at its end.

| case | step | F | O | G | X | C |
|---|---|---|---|---|---|---|
| h1h2-unset | A | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| h1h2-unset | file at A's head, end | absent, entry | absent, entry | absent, entry | absent, entry | absent, entry |
| h1h2-unset | B-same-engine | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| h1h2-unset | C-fresh-engine | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| h1h2-2tls | A | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| h1h2-2tls | file at A's head, end | absent, entry | absent, entry | absent, entry | absent, entry | absent, entry |
| h1h2-2tls | B-same-engine | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| h1h2-2tls | C-fresh-engine | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| h1h2-1_1 | A | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| h1h2-1_1 | file at A's head, end | absent, entry | absent, entry | absent, entry | absent, entry | absent, entry |
| h1h2-1_1 | B-same-engine | 35 tls | 35 tls | 35 tls | alt1 200 1.1 | alt1 200 1.1 |
| h1h2-1_1 | C-fresh-engine | 35 tls | 35 tls | 35 tls | alt1 200 1.1 | alt1 200 1.1 |
| h1only-unset | A | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| h1only-unset | file at A's head, end | absent, entry | absent, entry | absent, entry | absent, entry | absent, entry |
| h1only-unset | B-same-engine | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| h1only-unset | C-fresh-engine | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| file-ctrl-default | A | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| file-ctrl-default | file at A's head, end | absent, entry | absent, entry | absent, entry | absent, entry | absent, entry |
| file-ctrl-default | B-same-engine | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| file-ctrl-default | C-fresh-engine | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| plain-http-unset | A | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 |
| plain-http-unset | file at A's head, end | absent, no entries | absent, no entries | absent, no entries | absent, no entries | absent, no entries |
| plain-http-unset | B-same-engine | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 |
| plain-http-unset | C-fresh-engine | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 |
| ctrl-alone-unset | A | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| ctrl-alone-unset | file at A's head, end | absent, absent | absent, absent | absent, absent | absent, absent | absent, absent |
| ctrl-alone-unset | B-same-engine | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| ctrl-alone-unset | C-fresh-engine | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| ctrl-alone-2tls | A | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| ctrl-alone-2tls | file at A's head, end | absent, absent | absent, absent | absent, absent | absent, absent | absent, absent |
| ctrl-alone-2tls | B-same-engine | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |
| ctrl-alone-2tls | C-fresh-engine | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 | alt1 200 1.1 |

### Item 3 (ii): a pre-written alt-svc file, one transfer on a fresh engine (`altsvc-ii` lines)

A cell: the face that answered (`h2-face`, `h1-face`: the origin's h2 face, its https face) and the version, or the code; `file rewritten` when the file no longer holds the entry alone.

| entry | version | F | O | G | X | C |
|---|---|---|---|---|---|---|
| port | unset | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| port | 2TLS | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| port | 1_1 | 35 tls | 35 tls | 35 tls | alt1 200 1.1, file rewritten | alt1 200 1.1, file rewritten |
| port-ctrl-ro | unset | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| port-ctrl-ro | 2TLS | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| port-ctrl-ro | 1_1 | 35 tls | 35 tls | 35 tls | alt1 200 1.1 | alt1 200 1.1 |
| host | unset | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| host | 2TLS | 1 protocol | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| host | 1_1 | 35 tls | 35 tls | 35 tls | alt1 200 1.1, file rewritten | alt1 200 1.1, file rewritten |
| h1-to-both | unset | both 200 2 | both 200 2 | both 200 2 | both 200 2 | both 200 2 |
| h1-to-both | 2TLS | both 200 2 | both 200 2 | both 200 2 | both 200 2 | both 200 2 |
| h1-to-both | 1_1 | both 200 1.1 | both 200 1.1 | both 200 1.1 | both 200 1.1 | both 200 1.1 |
| h2src | unset | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| h2src | 2TLS | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| h2src | 1_1 | 35 tls | 35 tls | 35 tls | alt1 200 1.1, file rewritten | alt1 200 1.1, file rewritten |
| dead | unset | 7 connect | 7 connect | 7 connect | 7 connect | 7 connect |
| dead | 2TLS | 7 connect | 7 connect | 7 connect | 7 connect | 7 connect |
| dead | 1_1 | 7 connect | 7 connect | 7 connect | alt1 200 1.1, file rewritten | alt1 200 1.1, file rewritten |
| origin-h2 | unset | 1 protocol | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| origin-h2 | 2TLS | 1 protocol | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 | h2-face 200 2 |
| origin-h2 | 1_1 | 35 tls | 35 tls | 35 tls | h1-face 200 1.1 | h1-face 200 1.1 |
| plain-http | unset | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 |
| plain-http | 2TLS | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 |
| plain-http | 1_1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 | alt1h 200 1.1 |

### Item 3: `HTTP09_ALLOWED`, `HTTP200ALIASES`, `CONNECT_TO` (`h09`, `alias`, `connect-to` lines)

A cell: the face that answered, status and version, or the code.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| h09 control (unset) | 1 protocol | 1 protocol | 1 protocol | 1 protocol | 1 protocol |
| h09 allowed (unset) | 0 none | 0 none | 0 none | 0 none | 0 none |
| h09 allowed-1_1 (1_1) | 0 none | 0 none | 0 none | 0 none | 0 none |
| alias control | 1 protocol | 1 protocol | 1 protocol | 1 protocol | 1 protocol |
| alias alias (http/1.0) | 200 1.0 | 200 1.0 | 200 1.0 | 200 1.0 | 200 1.0 |
| alias http09 (#f) | 0 none | 0 none | 0 none | 0 none | 0 none |
| CONNECT_TO alt2 (unset) | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 | alt2 200 2 |
| CONNECT_TO alt2 (1_1) | 35 tls | 35 tls | 35 tls | 35 tls | 35 tls |

### Item 4: connection sharing (`share` lines)

A cell: for each rep, the connections the two requests used, by the origin's `/connection` K, then the versions read. `!first-ended`: the first had ended before the second did (none should). Each rep and each case ran on a fresh engine.

| setup | case | reps | F | O | G | X | C |
|---|---|---|---|---|---|---|---|
| h2/unset | a-together | reps 1, 2, 3 | 2, 2, 2 (2) | 2, 2, 2 (2) | 2, 2, 2 (2) | 2, 2, 2 (2) | 2, 2, 2 (2) |
| h2/unset | b-after-head | reps 1, 2, 3 | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) |
| h2/unset | c-after-end | reps 1, 2, 3 | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) |
| h2/2TLS | a-together | reps 1, 2, 3 | 2, 2, 2 (2) | 2, 2, 2 (2) | 2, 2, 2 (2) | 2, 2, 2 (2) | 2, 2, 2 (2) |
| h2/2TLS | b-after-head | reps 1, 2, 3 | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) |
| h2/2TLS | c-after-end | reps 1, 2, 3 | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) |
| h2c/2_PRIOR_KNOWLEDGE | a-together | reps 1, 2, 3 | 1, 1, 1 (2) | 2, 2, 2 (2) | 2, 2, 2 (2) | 2, 2, 2 (2) | 2, 2, 2 (2) |
| h2c/2_PRIOR_KNOWLEDGE | b-after-head | reps 1, 2, 3 | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) |
| h2c/2_PRIOR_KNOWLEDGE | c-after-end | reps 1, 2, 3 | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) | 1, 1, 1 (2) |
| h2/unset | a-together | verbose rep | 2 (2) | 2 (2) | 2 (2) | 2 (2) | 2 (2) |
| h2c/2_PRIOR_KNOWLEDGE | a-together | verbose rep | 1 (2) | 2 (2) | 2 (2) | 2 (2) | 2 (2) |

## Notes on the cells

**Item 1.**

- **The ALPN offer, in libcurl's own words.** The `v1v` lines are prior knowledge over `https`,
  with `VERBOSE`.
  - F offers `h2`, then `http/1.1` (D1:46-47).
  - O and G offer `h2,http/1.1` (D1:471, D1:904).
  - X and C offer `h2` alone (X1:45, D1:1338).
  - F, O and G then read `server accepted http/1.1`. X and C fail 35 with nothing sent:
    `No supported application protocol could be negotiated` (X1:73), `reason(1120)` (D1:1366).
- **Prior knowledge to the `http` face.** Node's `http` parser answers the preface, and every
  lane sent a request of 56 bytes.
  - F: `Empty reply from server` (D1:92).
  - O and G: 56, `Remote peer returned unexpected data while we expected SETTINGS frame`
    (D1:518, D1:950).
  - X and C: 16, with the same text (X1:72, D1:1365).
  - The class differs too: 52 and 56 are `curl-send-receive-error`, and 16 is
    `curl-protocol-error`.
- **`2_0` over `http://`** sent `Upgrade: h2c`, `HTTP2-Settings` and
  `Connection: Upgrade, HTTP2-Settings` on every lane. The face ignored them and answered over
  1.1 (D1:84, D1:510, D1:942, D1:1357, X1:64).
- **Every setting but prior knowledge, to `h2c`,** sent HTTP/1.1 and failed 1:
  `Received HTTP/0.9 when not allowed`. The request was 58 bytes, or 151 with `2_0`'s upgrade
  headers.

**Item 2.**

- **libcurl's words on every lane, in both runs.** `p2a`'s `plain-pk-verbose` printed
  `Uses proxy env variable http_proxy == 'http://…'`, then
  `Ignoring HTTP/2 prior knowledge due to proxy`. `p2b`'s printed the second line alone: F
  D1:109 and 138, O D1:535 and 563, G D1:967 and 995, C D1:1382 and 1412, X X1:89 and 119.
- **In 7.85.0's source** (`http.c:3060-3066`) the notice sits on the branch for
  `conn->bits.httpproxy && !conn->bits.tunnel_proxy`. A tunnel does not take it, and
  `tunnel-pk` reads HTTP/2 from the h2c face through `CONNECT`: F D1:124 and 153, O D1:549 and
  577, G D1:981 and 1009, C D1:1398 and 1428, X X1:105 and 135.
- **Prior knowledge to the HTTP/1.1 face through a proxy** (`plain-pk-to-http`) reads 200 over
  1.1 on every lane. Direct, the same request fails 52, 56 or 16 (D1:122, D1:547, D1:979,
  D1:1396, X1:103).
- **libcurl proxies `127.0.0.1` when `http_proxy` is set.** With `no_proxy` unset, no lane
  skipped the loopback host.

**Item 3.**

- **`SSL_ENABLE_ALPN` 0 against `both`.** Unset and `2TLS` read 1.1 and the face saw no ALPN
  (D1:177, 601, 1033, 1452; X1:159). With ALPN on, they read 2 with ALPN `h2`. Against `h2`, the
  face destroys a socket that did not choose `h2`, and every lane fails 56. Its error text
  varies by backend and by run: `Connection reset by peer`, `unexpected eof while reading`,
  GnuTLS `-110`.
- **(i), the file.** Absent at A's head, written by A's end, on every lane. libcurl writes it
  in `Curl_close`, which `curl_easy_cleanup` calls (8.23.0 `url.c:197` and `:258`, 7.85.0
  `url.c:370` and `:435`). The engine frees the handle before it completes the token
  (`take-out!` in `engine.sls`), so the file is written on the engine's thread, before await
  returns.
  - **B, on the same engine as A,** took the alternative though A's connection to `alt1` was
    pooled.
  - **At `1_1` on 8.20.0 and 8.23.0,** B reused A's connection and read 1.1.
  - **A plain `http://` origin's `Alt-Svc`** left the file holding no entries.
- **(ii), the pre-written file.**
  - `host`: the entry names `localhost` for the destination. The transfer reached `alt2`, and
    `:authority` kept the origin's `127.0.0.1:PORT`.
  - `h1-to-both`: an `h1` alternative on `both` gets HTTP/2 at unset and `2TLS`, and 1.1 at
    `1_1`, on all five (D1:223, 647, 1079, 1498; X1:205). The host moves whatever the version.
  - `dead`: a closed alternative fails 7, `Failed to connect to 127.0.0.1 port …`, with no
    fallback to the origin (D1:227, 651, 1083, 1502; X1:209). At `1_1` on X and C the entry
    does not apply, and the origin answers.
  - `origin-h2`: an entry on the origin's `https` face moved the transfer to its `h2` face.
  - `file rewritten`: on X and C, a transfer that passed the entry over learned alt1's own
    `Alt-Svc` header, and the file was saved with it. `ALTSVC_CTRL`'s read-only bit,
    `port-ctrl-ro`, kept the file as written.
- **7.85.0 and an `h2` alternative.** D1:236-262 is its whole trace. It reads
  `Alt-svc connecting from [h1]… to [h2]…`, `ALPN: server accepted h2`,
  `Using HTTP2, server supports multiplexing`, then `> GET /v HTTP/2` as text, 80 bytes, with
  no stream opened. The server's `GOAWAY` came back as `Received HTTP/0.9 when not allowed`.
  - Read in 7.85.0's source: the alt-svc hit sets `conn->httpversion = 20` before the connect
    (`url.c:3390-3410`).
  - `http.c:3045` switches to HTTP/2 only `if(conn->httpversion < 20)`. So
    `Curl_http2_switched` is never called, and the connection speaks HTTP/1 framing.
- **7.85.0 and 8.5.0 at `1_1`.** Each moves to the `h2` alternative and offers `http/1.1`
  alone, which the alternative refuses, 35 (F D1:264-270, O D1:698-706, G D1:1131-1138). On X and
  C at `1_1`, the trace shows no `Alt-svc connecting`, and then `Added alt-svc: … over h2` from
  alt1's header (D1:1550-1576).
- **`HTTP09_ALLOWED`.** The response's body is the h2c face's SETTINGS and GOAWAY frames, 26
  bytes. Its status reads 0 and its version `#f` (D1:276, X1:296).
- **`HTTP200ALIASES`.** It reads `ICY 200 OK` as 200 over HTTP/1.0 (D1:279, X1:299). Bare, the
  line fails 1. With `HTTP09_ALLOWED`, the whole head comes back as the body, status 0.
- **`CONNECT_TO`** `::127.0.0.1:ALT2` moved alt1's URL to alt2 on every lane (D1:281, X1:301).
  At `1_1`, alt2 refused the offer, 35.

**Item 4.**

- **(b) is valid in every rep.** Every `b-after-head` line reads
  `first-done-at-second-end=#f`: the first was still open, its body due 700 to 1,100 ms on.
- **The second was submitted as the first's head-wait returned.** That head came 1.1 to 3.8 ms
  after the first's submit on `h2c`, and 3.5 to 7.1 ms after it on `h2`. The second ended 0.5 to
  3.6 ms after the head, across every lane and run.
- **On 7.85.0, `h2c` together** (D1:388-404): `Using HTTP2, server supports multiplexing` for the
  first, then for the second `Found bundle for host … [can multiplex]`,
  `Multiplexed connection found` and `Re-using existing connection #0`. The plaintext connect
  and the prior-knowledge switch finished inside the turn that set both up.
  - 8.20.0 and 8.23.0 say `Connection #0 is not open enough, cannot reuse` and open a second.
  - 8.5.0 says `Server doesn't support multiplex (yet)` and opens a second.
  - Over TLS every lane opens two: the handshake takes more than one turn.

## Against ADR-0034's C probe and the plan

| claim | through the engine |
|---|---|
| ADR-0034: unset and `NONE` act as `2TLS`; `1_1` offers `http/1.1` alone; `2_0` sends `Upgrade: h2c` | confirmed, all five |
| ADR-0034, plan §3.7: prior knowledge to an HTTP/1.1 server over `http://` is 52, 56, 16 | confirmed against `tests/origin.mjs`'s `http` face, a Node parser where the probe's face was hand-written. The class differs with the code: send-receive for 52 and 56, protocol for 16. |
| ADR-0034: prior knowledge over `https://` offers `h2` alone on 8.20.0 and 8.23.0, and fails 35 against an `http/1.1` origin | confirmed, by libcurl's ALPN lines and the 35 |
| ADR-0034: prior knowledge to an h2c server gets HTTP/2, where every other setting fails 1 | confirmed |
| ADR-0034: transfers added in one step to an HTTP/2 origin open one connection each | confirmed for `h2` (TLS) on all five; **not for `h2c` by prior knowledge on 7.85.0, where they share one** |
| ADR-0034: a transfer added after another's head, or after its end, reuses its connection | confirmed on all five, `h2` and `h2c` |
| plan §3.2: libcurl ignores prior knowledge through a proxy that does not tunnel | confirmed on all five, named and environment; **with `HTTPPROXYTUNNEL` 1, which is not owned, prior knowledge holds inside the tunnel** |
| plan §3.2: beside `proxy environment`, measure what a variable's proxy does | it turns prior knowledge over `http://` into HTTP/1.1 in absolute form, reading 200 over 1.1, even to an HTTP/1.1 origin; over `https://` the variable's proxy tunnels, and `2TLS` reads 2 |
| plan §3.2: `SSL_ENABLE_ALPN` can turn `http/2` into HTTP/1.1 | confirmed on all five, against a server offering both |
| plan §3.2: `ALTSVC` and `ALTSVC_CTRL` can move a transfer to another version or host | `ALTSVC` confirmed on all five; **`ALTSVC_CTRL` alone moves nothing**, since each transfer is a fresh handle |
| plan §4.2: a later request reuses an HTTP/2 connection; requests submitted in one batch open their own | the first holds; the second holds over TLS, and **fails on 7.85.0 by prior knowledge** |
| `(curl)`'s timings doc: connect is 0 on a connection reused (8.20.0) | holds after the head on all five, and after the end on all but 7.85.0, where it reads 10 to 37 µs |

## The twins: what each changes

The question for each option: does it change the version, or the host, that the
`http-version` field's setting gets?

| option | owned today | changes | evidence |
|---|---|---|---|
| `SSL_ENABLE_ALPN` | no | **the version.** At 0, unset and `2TLS` read 1.1 at a server offering both, on all five, and fail 56 at an `h2`-only one | `alpn` rows |
| `ALTSVC` | no | **the host and the version**, through its file, on all five. On 7.85.0 and 8.5.0 it moves at `1_1` too, to an `h2` alternative; on 7.85.0 a move to `h2` fails 1; on 8.20.0 and 8.23.0 `1_1` passes over `h2` alternatives and takes `h1` ones. `https://` alone | `altsvc-i`, `altsvc-ii` |
| `ALTSVC_CTRL` | no | **nothing alone**, 6 transfers in 6 per lane-run. Beside `ALTSVC` it picks which alternatives apply (`h1only`: none moved), and its read-only bit keeps the file unwritten | `ctrl-alone-*`, `h1only-unset`, `port-ctrl-ro` |
| `HTTPPROXYTUNNEL` | no | **whether prior knowledge holds through a proxy**: HTTP/2 inside the tunnel, where without it the proxy gets HTTP/1.1 | `tunnel-pk`, `plain-pk` |
| `CONNECT_TO` | no | **the host**, on all five, as `PORT` and `RESOLVE` do, which are owned. The version stays the field's | `connect-to` |
| `HTTP09_ALLOWED` | no | **what a response reads, not what is set.** The h2c face's failure 1 becomes status 0 and version `#f`, at unset and `1_1` | `h09` |
| `HTTP200ALIASES` | no | **what a response reads**: a non-HTTP status line reads 200 over HTTP/1.0. No face of the origin sends one | `alias` |

**The rest of 8.23.0's options.** They were read from its man pages,
`build/verify/current/curl-8.23.0/docs/libcurl/opts/`, its 313 `CURLOPT_` pages.
Each one that touches the version, the connection or the host:

- **Not measured, with the reason:**
  - `SSL_ENABLE_NPN`: "Deprecated. Setting this option has no function" since 7.86.0, and Node's
    TLS has no NPN.
  - `PIPEWAIT`: ADR-0034 measured it; it changes sharing, not the version.
  - `HSTS_CTRL`: its cache is the handle's (8.23.0 `setopt.c:1222-1236`) unless a share holds it,
    and only `HSTS`, owned, loads one; each engine transfer is a fresh handle.
  - `STREAM_WEIGHT`: a priority. `STREAM_DEPENDS` and `STREAM_DEPENDS_E` take a handle, which the
    hatch refuses by type.
  - `UPKEEP_INTERVAL_MS`: HTTP/2 pings.
  - `HAPPY_EYEBALLS_TIMEOUT_MS`: no lane builds HTTP/3.
  - `FORBID_REUSE`, `MAXAGE_CONN`, `MAXLIFETIME_CONN`, `MAXCONNECTS`: they change item 4's reuse,
    not the version.
  - `SSLVERSION`, `SSL_CIPHER_LIST`, `TLS13_CIPHERS`, `ECH`: TLS settings.
  - `HAPROXYPROTOCOL`, `HAPROXY_CLIENT_IP`: a PROXY header.
  - `DEFAULT_PROTOCOL`: chez-curl's `CURLU` always has a scheme.
  - `IPRESOLVE`, `DNS_*`: name lookup.
- **Owned already:** `PORT`, `RESOLVE`, `DOH_URL`, `PROXYTYPE`, `HSTS`, `UNIX_SOCKET_PATH`,
  `PROXY`, `NOPROXY`.

## What split

- **Between the kept runs: nothing.** `tables.mjs` marks no cell.
- **The supplement.** The `twins` part ran twice more on every lane (`S`), so its cells have
  four runs each. `tables.mjs` built the same four twins tables from `S`'s two runs as from the
  kept pair, line for line.
  - `supplement-twins-docker.log` begins with one pass of the four Docker lanes. A second
    request, `all,all`, ran no lane, and its `docker.sh: no lane all` line is kept. The file
    then holds a second pass of `all`.
- **One cell not kept.** A pair of runs made before the `VERBOSE` cases were added was
  overwritten when the program changed. In it, O's `h2 | unset | off`, `SSL_ENABLE_ALPN` 0
  against the `h2` face, read 52 in one run and 56 in the other.
  - Every run kept since, the kept pair and the supplement's two, reads 56 for it, on every
    lane.
  - Hold that cell to what all read: a `curl-send-receive-error`, 52 or 56.
  - The server destroys the socket as the handshake ends, so whether libcurl sees a reset or an
    end varies. The error texts above vary that way within a lane.
- **Between lanes, every split follows the version:**
  - prior knowledge's code to the HTTP/1.1 face: 52, 56, 16;
  - its offer over `https://`: F, O and G against X and C;
  - `ALTSVC`: F fails every `h2` move, F, O and G move at `1_1`, X and C keep `1_1`;
  - `h2c` together: F shares;
  - the connect timing on reuse after the end: F alone above 0.

  The two 8.5.0 builds agree on every cell.

## Not measured, and why

- **Apple's 8.7.1.** No Mac was available, and `run.sh` was not tried on one. The engine does
  not multiplex on 8.7.x (ADR-0030, amended), so item 4 there should read one connection per
  request.
- **The rest of the 7.85.0 Alt-Svc bug.** Whether it also breaks an `h1` to `h2` move on a
  reused connection, or with a cache shared across handles, was not tried. Nor was the version
  that fixed it: no lane runs a libcurl between 8.5.0 and 8.20.0. 8.5.0 moves correctly.
- **An h2c upgrade a server accepts.** No face accepts `Upgrade: h2c`.
- **`ALTSVC` with an `h3` alternative.** No lane builds HTTP/3.
- **The high level.** `(http-client)` was not used. Every transfer was a low-level request on an
  engine.

## Files

- `version.sps`: the program; its header lists each part and case. The header's list of line
  names predates three kinds: `v1v`, `altsvc-v`, and the `verbose-begin` and `verbose-end`
  pairs. (iii)'s cases print `altsvc-i` lines, not `altsvc-iii`. It was left as run, so its hash
  stays the logs' `f39cbd8a…`.
- `standin.mjs`: the Alt-Svc, `both`, `icy` and `ctl` faces; its header lists them.
- `run.sh`: one lane, every part or those named.
- `docker.sh`: the four Docker lanes.
- `all.sh`: the prototype, then both runs of every lane, into `results/`.
- `make-prototype.sh`, `prototype.diff`: the named-proxy prototype in `build/m7s1/src`.
- `tables.mjs`: the tables above, from `results/`.
- `results/`: the kept logs (`X1`, `X2`, `D1`, `D2`) and the supplement (`S`).
