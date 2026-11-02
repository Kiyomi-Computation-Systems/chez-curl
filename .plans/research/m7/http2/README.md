# M7 research: HTTP/2 and the HTTP version

Measured 2026-11-02 for the M7 plan, area HTTP/2 ([ADR-0033](../../../decisions/0033-m7s-scope.md),
decision 4). It covers what libcurl does with `CURLOPT_HTTP_VERSION`, how transfers share
connections with and without `PIPEWAIT`, and ADR-0030 decision 5's paused-stream bytes, re-run
beside `PIPEWAIT`. It reports what libcurl does. It recommends nothing.

## In short

- **Unset and `NONE` behave as `2TLS` on all five lanes.** They offer `h2,http/1.1` over https and
  send no `Upgrade` over http (item 1).
- **`2_0` over `http://` sends `Upgrade: h2c`**, with `HTTP2-Settings` and
  `Connection: Upgrade, HTTP2-Settings`, on all five lanes.
- **`2_PRIOR_KNOWLEDGE` over https changed after 8.5.0, by 8.20.0:** 7.85.0 and both 8.5.0 builds offer
  `h2,http/1.1`, so an http/1.1-only origin still answers, over 1.1. 8.20.0 and 8.23.0 offer `h2`
  alone, and that origin's handshake fails 35.
- **`3` and `3ONLY`:** no lane builds HTTP/3. `setopt` refuses `3ONLY` with 1 everywhere, and `3`
  everywhere but 7.85.0. 7.85.0 takes `3`, then fails 35 over https and 3 over http.
- **Sharing:** with `PIPEWAIT` 0, transfers added in one step open a connection each (2 → 2, 4 → 4). With
  `PIPEWAIT` 1 they share one, at no measurable cost to the waiters. A transfer added after the first's
  head, or after its end, reuses the connection, `PIPEWAIT` or not. The same holds on all five lanes.
- **`PIPEWAIT` 1 against an http/1.1-only origin splits by version.** On 7.85.0 and both 8.5.0 builds the
  second transfer opens its own connection once the first's handshake shows no multiplexing (first
  byte at 4 to 7 ms). On 8.20.0 and 8.23.0 it waits for the first transfer to end, then reuses its
  connection: first byte at 508 to 510 ms, behind a body of about 500 ms. A third waiter opens a new
  connection as the first ends.
- **ADR-0030's bytes reproduce, and `PIPEWAIT` does not change them.** A paused stream beside an active
  one on one connection holds 66,888,480 bytes on 7.85.0, 10,639,945 on 8.5.0 (OpenSSL), 21,079,053 on
  8.20.0 and 33,527,276 on 8.23.0, `PIPEWAIT` 1 or 0. What `PIPEWAIT` changes is whether the two
  share a connection. Started together with `PIPEWAIT` 0, they don't, and the paused stream holds
  169 to 509 KB.

## What was run

`probe.c` drives libcurl's multi interface in M6's pause probe's loop, which mirrors chez-curl's
engine turn: resume, add, `curl_multi_perform`, `curl_multi_info_read`, then `curl_multi_poll`. Each
transfer gets the engine's options. `server.mjs` is a stand-in in Node's standard library alone. Its
faces:

| face | scheme | what it serves |
|---|---|---|
| `tlsh2` | https | `ALPNCallback` logs the client's list in the client's order; chooses `h2` if offered, else `http/1.1`, else refuses |
| `tlsh1` | https | as `tlsh2`, but chooses `http/1.1` if offered, else refuses: an origin offering http/1.1 alone |
| `h1` | http | HTTP/1.1 parsed by hand; logs every request header; ignores `Upgrade`; answers a connection preface 400 and closes |
| `h2c` | http | logs each connection's first bytes, then hands the socket to `node:http2`'s plaintext server (prior knowledge) |
| `ctl` | http | control, never logged: the server's events, fetched after each case over a plain socket |

`ALPNCallback` exists in Node 20.10.0: the floor lane ran on it, and its lines log the offered lists
(`D1:786`, `D1:839`). Times are client-side, in ms from each transfer's add. A first byte's clock
stops inside the write callback that first sees it.

Run, from the repository's root, twice each:

```sh
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/http2/run.sh guix-8.20.0' < /dev/null
sh .plans/research/m7/http2/docker.sh      # the four ubuntu:24.04 lanes
```

| lane | where | libcurl file → version | TLS, nghttp2 | headers | Node |
|---|---|---|---|---|---|
| F `floor-7.85.0` | Docker `ubuntu:24.04` (`sha256:68ee2200…`) | `build/e1/ci/curl-floor/lib/libcurl.so.4` → 7.85.0 | OpenSSL 3.0.13, 1.59.0 | its own `include/` | 20.10.0 (`build/verify/m3s2/node20`) |
| O `ubuntu-openssl-8.5.0` | same image | `/usr/lib/x86_64-linux-gnu/libcurl.so.4` (libcurl4t64 8.5.0-2ubuntu10.16) | OpenSSL 3.0.13, 1.59.0 | libcurl4-openssl-dev 8.5.0 | 24.18.0 (Guix store, read-only) |
| G `ubuntu-gnutls-8.5.0` | same image | `/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4` (libcurl3t64-gnutls 8.5.0-2ubuntu10.16) | GnuTLS 3.8.3, 1.59.0 | as O | 24.18.0 |
| X `guix-8.20.0` | Guix container (`scripts/guix-env`) | profile `libcurl.so.4` → `/gnu/store/67lpb53n…-curl-8.20.0/lib/libcurl.so.4.8.0` | GnuTLS 3.8.13, 1.69.0 | the profile's `include/` | 24.18.0 |
| C `current-8.23.0` | Docker `ubuntu:24.04` | `build/verify/c823/lane1/curl-current/lib/libcurl.so.4` → 8.23.0 | OpenSSL 3.0.13, 1.59.0 | its own `include/` | 24.18.0 |

Every lane ran on Linux x86_64, as each log's second line, `uname -sm`, reads. Every lane's
`--version` line reads `http2=1 http3=0`, and its headers match its runtime: `X1:1-3`, `D1:8-10`
(F), `D1:2700-2702` (O), `D1:4577-4579` (G), `D1:6191-6193` (C), and `D1:1-7` for the image and
packages.

**Logs** (in `results/`), and the citation keys used below:

| key | file | runs |
|---|---|---|
| `X1`, `X2` | `guix-8.20.0.log`, `guix-8.20.0-2.log` | lane X; both files have the same line numbers |
| `D1`, `D2` | `docker.log`, `docker-2.log` | lanes F, O, G and C, in that order |
| `N1`, `N2` | `guix-8.20.0-nomux.log`, `-nomux-2.log` | lane X with `PROBE_NO_MULTIPLEX=1` (supplement) |
| `P` | `instrument-before-fixes.log` | lane X once, before two server fixes (below) |

**Checks:** all 72 probe runs, six cases in each of twelve lane-runs, end `exit=0`. No log holds
a `gave-up`, a failed setopt, a failed event fetch, a request still open, or anything on the
server's stderr. Each case prints the server's events since it began, closing with
`server-events after=N n=K`, so "the server saw nothing" is a line (`D1:898`).

**Two server faults, found and fixed before the kept runs.** One Guix run made before the fixes is
kept as `results/instrument-before-fixes.log` (`P`). It ran an earlier probe: S-h1-wait had two
transfers, and there were no event counts.

- **The 80 MiB pattern.** It was built on first use, while W-sibling's first variant waited for its
  heads. There A paused at 114.2 ms (`P:798`); the same variant run later paused at 1.4 ms
  (`P:852`). M6's W-sibling, the same server code, paused there at 104.2 to 120.7 ms on every lane
  (`../../m6/pause/results/round2/`). The server now builds the pattern before it prints its ports.
  In the kept runs that variant paused at 2.0 to 8.2 ms.
- **Nagle.** Over HTTP/1.1 a head was written alone, then the body. The first body byte arrived
  40.6 ms after the head (`P:706`, `A_head=4.8 A_first=45.4`). Sockets that serve HTTP/1.1 now set
  `TCP_NODELAY`, and in the kept runs the gap is 0.0 to 1.7 ms over 70 transfers (the `h1wait` lines). The HTTP/2
  path keeps Node's default, as M6's server did.

## Item 1: `CURLOPT_HTTP_VERSION`

One transfer of `/hello` per setting and face, each on a fresh multi handle. A cell reads: the list
the server saw offered → what it chose; then `CURLINFO_HTTP_VERSION`; then the result code. A
cell holds for all five lanes and both runs unless it names lanes. No cell split between runs.

| setting | `tlsh2` (https, h2) | `tlsh1` (https, http/1.1 only) | `h1` (http) | `h2c` (http, prior knowledge) |
|---|---|---|---|---|
| unset | `h2,http/1.1` → h2; 2; 0 | `h2,http/1.1` → http/1.1; 1.1; 0 | 1.1; 0; no Upgrade | sent HTTP/1.1; 1 |
| `NONE` | `h2,http/1.1` → h2; 2; 0 | `h2,http/1.1` → http/1.1; 1.1; 0 | 1.1; 0; no Upgrade | sent HTTP/1.1; 1 |
| `1_1` | `http/1.1` → http/1.1; 1.1; 0 | `http/1.1` → http/1.1; 1.1; 0 | 1.1; 0; no Upgrade | sent HTTP/1.1; 1 |
| `2_0` | `h2,http/1.1` → h2; 2; 0 | `h2,http/1.1` → http/1.1; 1.1; 0 | 1.1; 0; **`Upgrade: h2c` sent** | sent HTTP/1.1 with `Upgrade: h2c`; 1 |
| `2TLS` | `h2,http/1.1` → h2; 2; 0 | `h2,http/1.1` → http/1.1; 1.1; 0 | 1.1; 0; no Upgrade | sent HTTP/1.1; 1 |
| `2_PRIOR_KNOWLEDGE` | F O G: `h2,http/1.1` → h2; 2; 0. X C: **`h2`** → h2; 2; 0 | F O G: `h2,http/1.1` → http/1.1; 1.1; 0. X C: **`h2` → refused; 35** | sent the preface; F 52, O G 56, X C 16 | sent the preface; 2; 0 |
| `3` (30) | F: setopt 0, then 35. O G X C: setopt 1 | F: setopt 0, then 35. O G X C: setopt 1 | F: setopt 0, then 3. O G X C: setopt 1 | F: setopt 0, then 3. O G X C: setopt 1 |
| `3ONLY` (31) | setopt 1 | setopt 1 | setopt 1 | setopt 1 |

Notes on the cells:

- **Upgrade.** "No Upgrade" is the `h1` face's own header log, `upgrade=none`, and the client's
  head held none either. Under `2_0` the server logged `Upgrade: h2c`, `HTTP2-Settings` and
  `Connection: Upgrade, HTTP2-Settings` (`X1:394`, `D1:562`, `D1:3132`, `D1:4937`, `D1:6648`).
  F, O and G send `Connection` first; X and C send it last. The `h1` face ignores the upgrade and
  answers over 1.1. No face accepts one.
- **`HTTP2-Settings`.** Decoded, every lane's payload holds `MAX_CONCURRENT_STREAMS` 100 and
  `ENABLE_PUSH` 0. `INITIAL_WINDOW_SIZE` differs: 33,554,432 on F
  (`AAMAAABkAAQCAAAAAAIAAAAA`), 10,485,760 on O and G (`AAMAAABkAAQAoAAAAAIAAAAA`), and 65,536 on X
  and C (`AAMAAABkAAQAAQAAAAIAAAAA`). Item 3's stalls on F and on O and G are those windows plus
  65,536, one server write. The TLS connections' own SETTINGS frames were not logged, so this
  is arithmetic on the upgrade's payload.
- **The `h2c` face, any setting but prior knowledge.** Its first bytes were `GET /hello… HTTP/1.1`.
  `node:http2` failed the session (`Received bad client magic byte string`), and libcurl ended 1,
  `Unsupported protocol`, after `Received HTTP/0.9 when not allowed` (`X1:98`, `X1:106`;
  `D1:148`, `D1:155` for F; likewise O, G and C).
- **`2_PRIOR_KNOWLEDGE` over https.**
  - X and C offered `h2` alone (`X1:552`, `D1:6830`); F, O and G offered `h2,http/1.1` (`D1:786`,
    `D1:3303`, `D1:5081`).
  - Against `tlsh1`, X and C were refused at ALPN, `ERR_SSL_NO_APPLICATION_PROTOCOL` at the server,
    35 at the client (`X1:567-568`, `D1:6846-6847`). F, O and G fell back to HTTP/1.1, status 200
    (`D1:839-840`, `D1:3344`, `D1:5113`).
- **`2_PRIOR_KNOWLEDGE` over http to `h1`.** The face saw the preface, answered 400 and closed
  (`X1:588`, `D1:859`, `D1:3362`, `D1:5131`, `D1:6867`). libcurl ended 16 on X and C, `Error in the
  HTTP2 framing layer`; 52 on F, `Server returned nothing`; 56 on O and G, `Failure when receiving
  data from the peer`.
- **`3` on 7.85.0.** `setopt` answered 0, though the build has no HTTP/3. Over https, libcurl printed
  `OpenSSL SSL_connect: Connection refused` and ended 35. The server saw no event at all,
  `server-events … n=0` (`D1:895`, `D1:898`), so no TCP connection reached it. Over http it printed
  `HTTP/3 requested for non-HTTPS URL` and ended 3 (`D1:913`). Elsewhere `setopt` answered 1,
  `Unsupported protocol`, and no transfer ran. 7.85.0's headers do not define `3ONLY`, so the probe
  passed 31.

**Where:** each lane-run's 32 `version setting=` lines lie in X1/X2:45-622;
F D1/D2:79-926; O D1:2751-3394, D2:2739-3382; G D1:4619-5163, D2:4607-5151; C D1:6243-6901,
D2:6231-6889.

## Item 2: connection sharing

All of item 2 ran against `tlsh2` or `tlsh1` with `HTTP_VERSION` `2TLS`. Bodies were 11 KiB, sent in
1 KiB writes 50 ms apart, about 500 ms each. "Connections" counts the server's `accept` events and
the distinct `CURLINFO_LOCAL_PORT` values, which agreed in every case. `NUM_CONNECTS` agreed too.

### Added in one step, to `tlsh2` (h2)

| transfers, `PIPEWAIT` | F | O | G | X | C |
|---|---|---|---|---|---|
| 2, `PIPEWAIT` 1 | 1 | 1 | 1 | 1 | 1 |
| 2, `PIPEWAIT` 0 | 2 | 2 | 2 | 2 | 2 |
| 4, `PIPEWAIT` 1 | 1 | 1 | 1 | 1 | 1 |
| 4, `PIPEWAIT` 0 | 4 | 4 | 4 | 4 | 4 |

The same in both runs. At `PIPEWAIT` 1 every waiter's first byte came 1.9 to 7.0 ms after its add,
and 0.0 to 1.2 ms after the first transfer's, on every lane (the `S-together` `done` lines).
libcurl's text names the wait.

- 8.20.0 and 8.23.0: `Found pending candidate for reuse and CURLOPT_PIPEWAIT is set`,
  `Waiting on connection to negotiate possible multiplexing.`, then `Multiplexed connection found`
  (`X1:629-659`, `D1:6908-6944`).
- 7.85.0 and 8.5.0: `Server doesn't support multiplex yet, wait`, then
  `Multiplexed connection found` (`D1:940-980`, `D1:3401-3435`, `D1:5170-5198`).

**Where** (client line, then server line; run 1 / run 2):

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| 2, `PIPEWAIT` 1 | D1:1023-1024 / D2:1029-1030 | D1:3459-3460 / D2:3447-3448 | D1:5219-5220 / D2:5207-5208 | X:679-680 | D1:6966-6967 / D2:6954-6955 |
| 2, `PIPEWAIT` 0 | D1:1179-1180 / D2:1184-1185 | D1:3553-3554 / D2:3541-3542 | D1:5297-5298 / D2:5285-5286 | X:758-759 | D1:7061-7062 / D2:7049-7050 |
| 4, `PIPEWAIT` 1 | D1:1332-1333 / D2:1334-1335 | D1:3666-3667 / D2:3654-3655 | D1:5401-5402 / D2:5389-5390 | X:861-862 | D1:7172-7173 / D2:7160-7161 |
| 4, `PIPEWAIT` 0 | D1:1640-1641 / D2:1640-1641 | D1:3848-3849 / D2:3836-3837 | D1:5553-5554 / D2:5541-5542 | X:1015-1016 | D1:7358-7359 / D2:7346-7347 |

### Added later, to `tlsh2`

B was added in the engine turn after A's head arrived, or after A ended and was removed. On every
lane, in both runs, at `PIPEWAIT` 1 and 0, B ran on A's connection: the same local port,
`NUM_CONNECTS` 0, one accept at the server, over HTTP/2. B's first byte came 0.2 to 0.5 ms after
its add after A's head, and 0.4 to 1.1 ms after A's end (the 40 `reuse` lines).

**Where** (`reuse` lines; run 1 / run 2): after the head at `PIPEWAIT` 1: F D1:1769 / D2:1759, O D1:3935 / D2:3923,
G D1:5631 / D2:5619, X:1095, C D1:7446 / D2:7434. At `PIPEWAIT` 0: F D1:1871 / D2:1859, O D1:4003 / D2:3991,
G D1:5690 / D2:5678, X:1156, C D1:7515 / D2:7503. After the end at `PIPEWAIT` 1: F D1:1986 / D2:1974,
O D1:4075 / D2:4063, G D1:5753 / D2:5741, X:1221, C D1:7588 / D2:7576. At `PIPEWAIT` 0: F D1:2097 / D2:2085,
O D1:4143 / D2:4131, G D1:5812 / D2:5800, X:1282, C D1:7657 / D2:7645.

### `PIPEWAIT` 1 against `tlsh1`, which offers http/1.1 alone

A and B were added in one step. Times are ms from each one's add, run 1 / run 2.

| lane | A ends | B's head | B's first byte | B's connection | server accepts |
|---|---|---|---|---|---|
| F 7.85.0 | 507.8 / 508.4 | 5.3 / 6.9 | 5.3 / 7.0 | its own | 2 / 2 |
| O 8.5.0 | 508.4 / 508.5 | 4.4 / 7.0 | 4.4 / 7.1 | its own | 2 / 2 |
| G 8.5.0 | 508.5 / 507.5 | 5.4 / 6.0 | 5.5 / 6.1 | its own | 2 / 2 |
| X 8.20.0 | 507.7 / 508.8 | 507.9 / 509.2 | 508.0 / 509.5 | A's, after A ended | 1 / 1 |
| C 8.23.0 | 508.0 / 508.7 | 508.3 / 509.3 | 508.4 / 509.6 | A's, after A ended | 1 / 1 |

At `PIPEWAIT` 0, B opened its own connection at once on every lane. Its first byte came 2.6 to
7.2 ms after its add.

libcurl's own words:

- **F, O and G:** `Server doesn't support multiplex yet, wait`, then, once A's handshake chose
  http/1.1, `Can not multiplex, even if we wanted to` and `Transfer was pending, now try another`
  (`D1:2122-2154`, `D1:4161-4191`, `D1:5830-5854`).
- **X and C:** `Waiting on connection to negotiate possible multiplexing.`, then at 507.7 and
  508.0 ms `Reusing existing https: connection` (`X1:1301`, `X1:1327`, `D1:7676`, `D1:7710`).

**Three transfers, `PIPEWAIT` 1.** On F, O and G each opened its own connection, every first byte by
6.0 ms: 3 accepts. On X and C, B took A's connection as A ended, and C opened a second connection
then: X's C at 512.4 / 508.7 ms, C's C at 513.0 / 509.0 ms, 2 accepts.

**Where** (`h1wait` lines, run 1 / run 2): 2 at `PIPEWAIT` 1: F D1:2234 / D2:2222, O D1:4232 / D2:4220,
G D1:5885 / D2:5873, X:1336, C D1:7719 / D2:7707. 2 at `PIPEWAIT` 0: F D1:2365 / D2:2353, O D1:4315 / D2:4303,
G D1:5952 / D2:5940, X:1401, C D1:7800 / D2:7788. 3 at `PIPEWAIT` 1: F D1:2564 / D2:2552, O D1:4441 / D2:4429,
G D1:6055 / D2:6043, X:1483, C D1:7893 / D2:7881. Each server summary is two lines below.

## Item 3: a paused stream beside an active one

M6's W-sibling, unchanged in substance, against `tlsh2`:

- **A:** 80 MiB written as fast as the server can, paused at its first write and held 5 s.
- **B:** 800 KiB, 16 KiB every 100 ms.
- **Live bytes:** libcurl's allocations through `curl_global_init_mem`'s counting allocators,
  just before A's resume.
- **Stall:** the server's write of A that waited about 5 s, as bytes written:ms.

There are four variants:

- **together:** B is added with A. At `PIPEWAIT` 1 this is M6's case.
- **late:** B is added in the turn after A's head arrived.

In every variant both transfers ended 0, with every byte in order.

| lane | ADR-0030 | `PIPEWAIT` 1, together | `PIPEWAIT` 1, late | `PIPEWAIT` 0, late | `PIPEWAIT` 0, together |
|---|---|---|---|---|---|
| F 7.85.0 | 66.9 MB; 33,619,968 | 66,888,480; 33,619,968 | 66,888,456; 33,619,968 | 66,888,456; 33,619,968 | **2 connections:** 178,400; 2,686,976 / 2,621,440 |
| O 8.5.0 | 10.6 MB; 10,551,296 | 10,639,945; 10,551,296 | 10,639,921; 10,551,296 | 10,639,921; 10,551,296 | **2 connections:** 246,550; 2,686,976 |
| G 8.5.0 | (as O) | 10,639,666; 10,551,296 | 10,639,642; 10,551,296 | 10,639,642; 10,551,296 | **2 connections:** 509,008 / 311,920; 4,784,128 / 4,653,056 |
| X 8.20.0 | 21.1 MB; 20,971,520 | 21,079,053; 20,971,520 | 21,079,029; 20,971,520 | 21,079,029; 20,971,520 | **2 connections:** 180,268; 2,686,976 |
| C 8.23.0 | 33.5 MB; 20,971,520 | 33,527,276 / 33,527,278; 20,971,520 | 33,527,195; 20,971,520 | 33,527,196 / 33,527,197; 20,971,520 | **2 connections:** 169,388; 2,686,976 |

Each cell gives live bytes, then the stall's bytes written. Where two values stand, they are run
1 / run 2; a single value held in both runs. Every stall in the three shared-connection columns
waited 4,960 to 5,020 ms.

- **The numbers reproduce ADR-0030's, to the stall's byte.** The first measured column is M6's
  case. Its live bytes match ADR-0030's rounded figures, and its stalls match its counts exactly.
  M6's round-2 logs read 66,888,468, 10,639,936, 10,639,654, 21,079,044 and 33,527,259, within 19
  bytes of these (`../../m6/pause/results/round2/docker.log`, `guix-8.20.0.log`).
- **`PIPEWAIT` does not change them.** With B added late, `PIPEWAIT` 1 and 0 gave the same bytes
  to within 2, on every lane. In both, B ran on A's connection (`same_conn=1`).
- **What `PIPEWAIT` 0 changes is the sharing.** Added together, A and B open two connections, so A
  is alone on its own. It then holds 169 to 509 KB, and the server's writes stall after 2.6 to
  2.7 MB, or 4.7 to 4.8 MB on G, which first waited 39 ms at about 3 MB.
- **No transfer failed at libcurl's 64 MiB cap for a paused transfer:** every code was 0. The cap
  counts what libcurl buffers for that transfer. The live bytes count all its allocations, and on
  7.85.0 they read 66,888,480, 220,384 under 67,108,864.

**Where** (the `live`, then the server's `body` line for A; run 1 / run 2):

| variant | F | O | G | X | C |
|---|---|---|---|---|---|
| `PIPEWAIT` 1, together | D1:2601,2610 / D2:2589,2598 | D1:4478,4487 / D2:4466,4475 | D1:6092,6101 / D2:6080,6089 | X:1517,1526 | D1:7927,7936 / D2:7915,7924 |
| `PIPEWAIT` 0, together | D1:2627,2640 / D2:2615,2628 | D1:4504,4517 / D2:4492,4505 | D1:6118,6131 / D2:6106,6119 | X:1543,1556 | D1:7953,7966 / D2:7941,7954 |
| `PIPEWAIT` 1, late | D1:2657,2666 / D2:2645,2654 | D1:4534,4543 / D2:4522,4531 | D1:6148,6157 / D2:6136,6145 | X:1573,1582 | D1:7983,7992 / D2:7971,7980 |
| `PIPEWAIT` 0, late | D1:2683,2692 / D2:2671,2680 | D1:4560,4569 / D2:4548,4557 | D1:6174,6183 / D2:6162,6171 | X:1599,1608 | D1:8009,8018 / D2:7997,8006 |

The `sibling case_t` line, one above each `live` line, carries `same_conn`, both codes and
both patterns.

## Supplement: `CURLMOPT_PIPELINING` 0, on 8.20.0

The engine sets `CURLMOPT_PIPELINING` 0 on 8.7.x (ADR-0030, amended), and mac.sh runs the
Mac's probe with it. For a Linux row beside the Mac's, lane X ran with `PROBE_NO_MULTIPLEX=1`
twice (`N1`, `N2`, the same line numbers in each). Each multi handle's setopt answered 0, 47
lines in each.

- **Every transfer opened its own connection,** at `PIPEWAIT` 1 or 0: 2 and 4 together, B after
  A's head, and every h1-only waiter (`N1:727`, `N1:959`, `N1:1221`, `N1:1507`, `N1:1669`).
  B's first byte came by 6.2 ms there.
- **Only after A's end did B reuse the connection** (`N1:1376`, `N1:1438`).
- **In W-sibling, A was always alone:** 179,232 to 180,268 live bytes, both codes 0
  (`N1:1706-1800`, `N2:1706-1800`).

## What split

- **Between runs:** item 3's separate-connection column, on G (509,008 / 311,920 bytes; stall at
  4,784,128 / 4,653,056) and on F's stall (2,686,976 / 2,621,440). C's shared-connection bytes
  moved by 1 to 2. Item 2's times move by a few ms, and the table gives both runs. No item 1 cell
  and no connection count split.
- **Between lanes**, every split is by version, and both runs agree on each:
  - `2_PRIOR_KNOWLEDGE`'s offer over https: 7.85.0 and 8.5.0 against 8.20.0 and 8.23.0.
  - its result code against an HTTP/1.1 origin: 52, 56, 16.
  - `3` on 7.85.0.
  - `PIPEWAIT` 1's wait at an http/1.1-only origin: 7.85.0 and 8.5.0 against 8.20.0 and 8.23.0.
  - item 3's bytes, as in ADR-0030.

## Not measured, and why

- **Apple's 8.7.1.** `mac.sh` runs the probe on the Mac:

  ```sh
  sh .plans/research/m7/http2/mac.sh
  ```

  It takes about 3 minutes. It writes `results/mac-8.7.1.log`, four runs: two as libcurl comes, and
  two with `PROBE_NO_MULTIPLEX=1`, the engine's setting there. It prints the log's path. It needs
  `cc`, `openssl` and Node: `NODE`, else `asdf which node`, else `node`. No Mac was available
  here.
- **Where the 7.85.0 / 8.5.0 to 8.20.0 / 8.23.0 changes happened.** No lane runs a libcurl between
  8.5.0 and 8.20.0 (8.7.1 is the Mac's).
- **HTTP/3.** No lane builds it (`http3=0`). Only `setopt`'s answers, and 7.85.0's attempt, were
  measured.
- **An h2c upgrade a server accepts (101).** No face accepts one. Item 1 records only whether
  `Upgrade: h2c` is sent.
- **Why each byte count is what it is.** The numbers are measured. Beyond item 1's arithmetic on
  `HTTP2-Settings`, the flow-control windows behind them were not read from libcurl's or nghttp2's
  source. Nothing here explains 8.20.0's and 8.23.0's stall at 20,971,520, given a 65,536 initial
  window.
- **chez-curl's engine itself.** The probe mirrors its loop in C. No measurement here went through
  `(curl)`.
- **More than 4 streams on a connection, and arm64.** Concurrent-stream limits were not approached.
  Every lane ran on x86_64.

## Files

- `probe.c`: the probe; its header lists the cases.
- `server.mjs`: the stand-in; its header lists the faces, routes and event lines.
- `run.sh`: builds the probe against one libcurl, makes the run's PKI with `tests/make-test-pki.sh`,
  starts the server and runs the cases.
- `docker.sh`: the four Docker lanes.
- `mac.sh`: the Mac.
- `results/`: the kept logs above. Lanes F, O, G, X and C ran twice each. `P` is an instrument
  check, not a measurement of libcurl.
