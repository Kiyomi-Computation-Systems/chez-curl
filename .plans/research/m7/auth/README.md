# M7 auth: Basic, Bearer and Digest, measured

2026-11-02, for the M7 plan ([ADR-0033](../../../decisions/0033-m7s-scope.md), decision 1). What
libcurl does with credentials, `HTTPAUTH` and auth rounds, on five Linux libcurls, two runs each.
It reports what libcurl does. It designs nothing and recommends nothing.

## What ran

| file | what |
|---|---|
| `probe.c` | the client: one multi handle per group, a fresh easy handle per transfer, the engine's turn and options (its header comment lists them) |
| `server.mjs` | the stand-in: Node's standard library alone; HTTP/1.1 parsed from bytes (`raw`) and `node:http2` over TLS (`h2`); logs every request's line, `Authorization` bytes, body (bytes, pattern, SHA-256) and its own answer; verifies Digest with its own arithmetic |
| `run.sh` | one lane: compile against the lane's headers, a per-run PKI, the server's self-test, then groups C A B D W S E H |
| `docker.sh` | the four Docker lanes, in `ubuntu:24.04` |
| `mac.sh` | Apple's 8.7.1, for the maintainer (not run here) |
| `tables.mjs`, `readme-tables.mjs` | read the logs: one line per transfer, the cross-log comparison, and every table below |
| `wire-control.sh`, `selftest-control.sh` | the wire check and the Digest self-test, each watched failing |
| `utf8-recompute.mjs` | 8.23.0's UTF-8 Digest header, recomputed apart from the server |
| `results/` | `guix-8.20.0-{1,2}.log`, `docker-{1,2}.log` (four lanes each); `wire-control-guix-8.20.0.log`, `selftest-control-guix-8.20.0.log`, `utf8-recompute.log` |

**Lanes.** Each from its log's header lines (`libcurl`, `version`, `node`; Docker's `package`
lines):

| lane | libcurl file | version, TLS, nghttp2 | Node | where |
|---|---|---|---|---|
| `guix-8.20.0` | `/gnu/store/67lpb53n…-curl-8.20.0/lib/libcurl.so.4.8.0` | 8.20.0, GnuTLS/3.8.13, 1.69.0 | 24.18.0 | the Guix container (`scripts/guix-env`), Linux x86_64 |
| `floor-7.85.0` | `build/e1/ci/curl-floor/lib/libcurl.so.4.8.0` | 7.85.0, OpenSSL/3.0.13, 1.59.0 | 20.10.0 | Docker `ubuntu:24.04` (24.04.5 LTS, image `sha256:68ee2200…`) |
| `ubuntu-openssl-8.5.0` | `/usr/lib/x86_64-linux-gnu/libcurl.so.4.8.0` (libcurl4t64 8.5.0-2ubuntu10.16) | 8.5.0, OpenSSL/3.0.13, 1.59.0 | 24.18.0 | same |
| `ubuntu-gnutls-8.5.0` | `…/libcurl-gnutls.so.4.8.0` (libcurl3t64-gnutls 8.5.0-2ubuntu10.16) | 8.5.0, GnuTLS/3.8.3, 1.59.0 | 24.18.0 | same |
| `current-8.23.0` | `build/verify/c823/lane1/curl-current/lib/libcurl.so.4.8.0` | 8.23.0, OpenSSL/3.0.13, 1.59.0 | 24.18.0 | same |

Every lane compiled against its own headers (`version headers=X runtime=X`). All 40 groups of the
ten lane-runs ended `probe G exit=0`; each lane-run printed 636 `row` lines. No log has a
`server-stderr`, `exited` or `cc:` line.

**Checks on the instrument.**
- `server selftest ok 13` in every lane-run: RFC 2617's MD5 example, RFC 7616's MD5 and SHA-256
  examples, SHA-512/256 of nothing, and four controls that must fail (wrong password, `auth-int`
  ignoring the body, the hash function and `-sess` making no difference). `selftest-control.sh`
  puts `nc` before the nonce in a copy: `selftest FAIL` for all three examples, `exit=1`
  (`results/selftest-control-guix-8.20.0.log`).
- `wire #K same` compares request K's `Authorization` as libcurl logged it (`HEADER_OUT`) with the
  bytes the server received, whole. No log has a `DIFFERS`, `wire requests` or
  `server-has-no-request` line. `wire-control.sh` runs group A against a server that logs each value
  one byte short: `DIFFERS 46, same (none) 56, same with a value 0`, and group A sends 46
  `Authorization` headers.
- Item 3's same-handle control (`D:reuse-same`) shows the probe can see carried Digest state, and
  item 4's 301 control reproduces AGENTS.md's HTTP/2 3xx trap, so the 401 beside it is measured
  by an instrument that can see a hang.

**Reading a log.** Lines are `[LANE] case NAME FACE …`. `out #K` is request head K as libcurl
handed it to the debug callback; `in` a status, `WWW-Authenticate` or `Location` line received;
`text` libcurl's own; `server:` the stand-in's log for the transfer; `done` the transfer's end
(`code`, `t` in ms from its add, `status`, `outs` requests, `reads`, `seeks`, `prereqs`, `handed`
bytes); `row` its summary. `server: rounds` holds one bracket per request: `auth=SCHEME:VERDICT
status=N early|mid|after-body body=BYTES:pattern…`.

The tables come from `node .plans/research/m7/auth/readme-tables.mjs GROUP results/guix-8.20.0-1.log
results/guix-8.20.0-2.log results/docker-1.log results/docker-2.log`, which compares outcomes
across the four logs (ten lane-runs). A cell names lanes only where they differ: `8.20.0`,
`7.85.0`, `8.5.0o` (OpenSSL), `8.5.0g` (GnuTLS), `8.23.0`. A cell that holds for every lane-run
names none.

## 1. Where credentials come from

HTTPAUTH unset (libcurl's default, Basic), against `/auth?ch=open` (200 always). URL userinfo
`U0`–`U11` crossed with options `O0`–`O13`, 168 transfers, each once by `CURLOPT_CURLU` (the
engine's way, `curl_url_set(CURLUPART_URL, url, 0)`) and once by `CURLOPT_URL`. A cell is the Basic
credentials decoded from the `Authorization` libcurl sent (`cred sent=basic decoded="…"`), bytes
escaped as `\xNN`; `none` is no `Authorization`; `fails 3` is `CURLE_URL_MALFORMAT` before any
request.

- **URL userinfo:** U0 none; U1 `alice`; U2 `alice:secret`; U3 `:secret`; U4 `alice:`; U5 `:`;
  U6 empty (`http://@host`); U7 `a%20b%40c:p%3Aq%2Fr%25`; U8 `alice:se:cret`; U9
  `%C3%BCser:p%C3%A4ss%E2%82%AC`; U10 the same bytes raw in the URL; U11 `alice:a%00b`.
- **Options**, set in this order: O0 none; O1 `USERNAME bob`; O2 `PASSWORD hunter2`; O3 both; O4
  `USERPWD carol:pw3`; O5 `USERPWD carol`; O6 `USERPWD :pw3`; O7 `USERPWD carol:pw3` then O3's
  pair; O8 O3's pair then `USERPWD carol:pw3`; O9 `USERNAME ""` and `PASSWORD hunter2`; O10
  `USERNAME bob` and `PASSWORD ""`; O11 `USERNAME \xc3\xbc`, `PASSWORD \xc3\xa4\xe2\x82\xac`; O12
  the same by `USERPWD`; O13 `USERPWD a%40b:c%3Ad`.

<!-- 336 cells over 5 lanes and 4 logs; split between runs: 0; CURLU against CURLOPT_URL: 0 differ; 8.5.0 (both) against 8.20.0: 0 differ -->
| | O0 | O1 | O2 | O3 | O4 | O5 | O6 | O7 | O8 | O9 | O10 | O11 | O12 | O13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| U0 | none | `bob:` | none | `bob:hunter2` | `carol:pw3` | `carol:` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U1 | `alice:` | `bob:` | `alice:hunter2` | `bob:hunter2` | `carol:pw3` | `carol:` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U2 | `alice:secret` | `alice:secret` | `alice:hunter2` | `bob:hunter2` | `carol:pw3` | `alice:secret` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U3 | `:secret` | `:secret` | `:hunter2` | `bob:hunter2` | `carol:pw3` | `:secret` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U4 | `alice:` | `alice:` | `alice:hunter2` | `bob:hunter2` | `carol:pw3` | `alice:` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U5 | `:` | `:` | `:hunter2` | `bob:hunter2` | `carol:pw3` | `:` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U6 | `:` | `bob:` | `:hunter2` | `bob:hunter2` | `carol:pw3` | `carol:` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U7 | `a b@c:p:q/r%` | `a b@c:p:q/r%` | `a b@c:hunter2` | `bob:hunter2` | `carol:pw3` | `a b@c:p:q/r%` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U8 | `alice:se:cret` | `alice:se:cret` | `alice:hunter2` | `bob:hunter2` | `carol:pw3` | `alice:se:cret` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U9 | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `\xc3\xbcser:hunter2` | `bob:hunter2` | `carol:pw3` | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U10 | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `\xc3\xbcser:hunter2` | `bob:hunter2` | `carol:pw3` | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |
| U11 | fails 3 | fails 3 | `alice:hunter2` | `bob:hunter2` | `carol:pw3` | fails 3 | `:pw3` | `bob:hunter2` | `carol:pw3` | `:hunter2` | `bob:` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `\xc3\xbc:\xc3\xa4\xe2\x82\xac` | `a%40b:c%3Ad` |

| cell | 8.5.0, 8.20.0 | 7.85.0 | 8.23.0 |
|---|---|---|---|
| U0 O2 | none | `:hunter2` | `:hunter2` |
| U1 O6 | `:pw3` | same | `alice:pw3` |
| U1 O9 | `:hunter2` | same | `alice:hunter2` |
| U2 O1 | `alice:secret` | `bob:secret` | `bob:` |
| U2 O2 | `alice:hunter2` | same | `alice:secret` |
| U2 O5 | `alice:secret` | `carol:secret` | `carol:` |
| U2 O6 | `:pw3` | same | `alice:secret` |
| U2 O9 | `:hunter2` | same | `alice:secret` |
| U3 O1 | `:secret` | `bob:secret` | `bob:` |
| U3 O2 | `:hunter2` | same | `:secret` |
| U3 O5 | `:secret` | `carol:secret` | `carol:` |
| U3 O6 | `:pw3` | same | `:secret` |
| U3 O9 | `:hunter2` | same | `:secret` |
| U4 O1 | `alice:` | `bob:` | `bob:` |
| U4 O2 | `alice:hunter2` | same | `alice:` |
| U4 O5 | `alice:` | `carol:` | `carol:` |
| U4 O6 | `:pw3` | same | `alice:` |
| U4 O9 | `:hunter2` | same | `alice:` |
| U5 O0 | `:` | none | none |
| U5 O1 | `:` | `bob:` | `bob:` |
| U5 O2 | `:hunter2` | same | none |
| U5 O5 | `:` | `carol:` | `carol:` |
| U5 O6 | `:pw3` | same | none |
| U5 O9 | `:hunter2` | same | none |
| U6 O0 | `:` | none | none |
| U7 O1 | `a b@c:p:q/r%` | `bob:p:q/r%` | `bob:` |
| U7 O2 | `a b@c:hunter2` | same | `a b@c:p:q/r%` |
| U7 O5 | `a b@c:p:q/r%` | `carol:p:q/r%` | `carol:` |
| U7 O6 | `:pw3` | same | `a b@c:p:q/r%` |
| U7 O9 | `:hunter2` | same | `a b@c:p:q/r%` |
| U8 O1 | `alice:se:cret` | `bob:se:cret` | `bob:` |
| U8 O2 | `alice:hunter2` | same | `alice:se:cret` |
| U8 O5 | `alice:se:cret` | `carol:se:cret` | `carol:` |
| U8 O6 | `:pw3` | same | `alice:se:cret` |
| U8 O9 | `:hunter2` | same | `alice:se:cret` |
| U9 O1 | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `bob:p\xc3\xa4ss\xe2\x82\xac` | `bob:` |
| U9 O2 | `\xc3\xbcser:hunter2` | same | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` |
| U9 O5 | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `carol:p\xc3\xa4ss\xe2\x82\xac` | `carol:` |
| U9 O6 | `:pw3` | same | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` |
| U9 O9 | `:hunter2` | same | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` |
| U10 O1 | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `bob:p\xc3\xa4ss\xe2\x82\xac` | `bob:` |
| U10 O2 | `\xc3\xbcser:hunter2` | same | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` |
| U10 O5 | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` | `carol:p\xc3\xa4ss\xe2\x82\xac` | `carol:` |
| U10 O6 | `:pw3` | same | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` |
| U10 O9 | `:hunter2` | same | `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` |
| U11 O1 | fails 3 | same | `bob:` |
| U11 O2 | `alice:hunter2` | same | fails 3 |
| U11 O5 | fails 3 | same | `carol:` |
| U11 O6 | `:pw3` | same | fails 3 |
| U11 O9 | `:hunter2` | same | fails 3 |

Read from the table and its checks line:
- **CURLU and `CURLOPT_URL` give the same bytes in all 336 cells, on every lane.** No cell split
  between runs. Ubuntu's two 8.5.0 builds and Guix's 8.20.0 agree in every cell; 7.85.0 differs in
  19 and 8.23.0 in 50 (the second table).
- **What is base64-encoded is the bytes, as decoded from the URL or as given in the option.**
  U9 (percent-encoded) and U10 (raw in the URL) both went out as `Authorization: Basic
  w7xzZXI6cMOkc3Pigqw=`, `\xc3\xbcser:p\xc3\xa4ss\xe2\x82\xac` (guix-8.20.0-1.log,
  `case C:curlu:U9-utf8pct:O0-none raw out #1`). An option's bytes go out as given, percent signs
  included (O13). The URL's userinfo splits at its first `:` (U8: `alice:se:cret`), and
  `USERPWD` at its `:` (O4).
- **The last setopt wins between `USERPWD` and `USERNAME`/`PASSWORD`** (O7 against O8), on every
  lane.
- **Options against the URL, by lane:**
  - 8.5.0 and 8.20.0: `PASSWORD` alone replaces the URL's password (U2 O2 `alice:hunter2`);
    `USERNAME` alone, or `USERPWD` without a colon, replaces the URL's user only when the URL has no
    `:` (U1 O1 `bob:`, U4 O1 `alice:`); an empty user from `USERNAME ""` or `USERPWD :pw3`
    replaces the URL's whole userinfo (U2 O6 `:pw3`).
  - 7.85.0: `USERNAME` replaces the URL's user and keeps its password (U2 O1 `bob:secret`).
  - 8.23.0: `USERNAME` replaces the user and drops the URL's password (U2 O1 `bob:`); `PASSWORD`
    alone does not replace the URL's password (U2 O2 `alice:secret`); an empty user from an option
    leaves the URL's userinfo in place (U2 O6 `alice:secret`).
- **Empty credentials.** `http://:@host` (U5) and `http://@host` (U6) send `Authorization: Basic
  Og==`, `:`, on 8.5.0 and 8.20.0 (`case C:curlu:U6-emptyinfo:O0-none raw out #1`), and nothing
  on 7.85.0 and 8.23.0. `PASSWORD` with no user anywhere (U0 O2) sends `:hunter2` on 7.85.0 and
  8.23.0, and nothing on 8.5.0 and 8.20.0.
- **A `%00` in the URL's password** (U11) fails the transfer with 3 before any request, unless an
  option takes the password's place: on 8.5.0 and 8.20.0 `PASSWORD`, or a `USERPWD` with a `:`;
  on 8.23.0 a non-empty `USERNAME` or `USERPWD`, which drops the URL's password, while `PASSWORD`
  alone, or an empty user, does not.
- ADR-0009's measured variance (`USERNAME` replaced the user on 7.85.0 and 8.23.0, `PASSWORD` the
  password on 7.85.0 to 8.20.0) holds here at U2.

## 2. `HTTPAUTH` values and rounds

URL userinfo `user:pass`; for the modes holding `BEARER`, `XOAUTH2_BEARER tok123` too. Servers
(`ch=`): `basic`; `digest` (MD5, `qop="auth"`); `both`, a 401 with `WWW-Authenticate: Basic` then
`Digest`; `both-rev`, Digest then Basic; `bearer`; `none`, a 401 with no `WWW-Authenticate`; `open`,
200 without a challenge. The server accepts only a scheme its challenge offered. A cell is each
request's `Authorization` scheme in order (`–` none) and the final status; the code was 0 in every
cell (libcurl answers a 401 with `CURLE_OK`).

| HTTPAUTH | basic | digest | both | both-rev | bearer | none | open |
|---|---|---|---|---|---|---|---|
| unset | Basic ⇒ 200 | Basic ⇒ 401 | Basic ⇒ 200 | Basic ⇒ 200 | Basic ⇒ 401 | Basic ⇒ 401 | Basic ⇒ 200 |
| BASIC | Basic ⇒ 200 | Basic ⇒ 401 | Basic ⇒ 200 | Basic ⇒ 200 | Basic ⇒ 401 | Basic ⇒ 401 | Basic ⇒ 200 |
| DIGEST | – ⇒ 401 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – ⇒ 401 | – ⇒ 401 | – ⇒ 200 |
| BEARER | Bearer ⇒ 401 | Bearer ⇒ 401 | Bearer ⇒ 401 | Bearer ⇒ 401 | Bearer ⇒ 200 | Bearer ⇒ 401 | Bearer ⇒ 200 |
| ANY | – → Basic ⇒ 200 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – ⇒ 401 | – ⇒ 401 | – ⇒ 200 |
| ANYSAFE | – ⇒ 401 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – ⇒ 401 | – ⇒ 401 | – ⇒ 200 |
| DIGEST\|BASIC | – → Basic ⇒ 200 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – ⇒ 401 | – ⇒ 401 | – ⇒ 200 |
| BASIC\|ONLY | – → Basic ⇒ 200 | – ⇒ 401 | – → Basic ⇒ 200 | – → Basic ⇒ 200 | – ⇒ 401 | – ⇒ 401 | – ⇒ 200 |
| DIGEST\|ONLY | – ⇒ 401 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – ⇒ 401 | – ⇒ 401 | – ⇒ 200 |
| BEARER\|ONLY | – ⇒ 401 | – ⇒ 401 | – ⇒ 401 | – ⇒ 401 | – → Bearer ⇒ 200 | – ⇒ 401 | – ⇒ 200 |
| DIGEST\|BASIC\|ONLY | – → Basic ⇒ 200 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – → Digest ⇒ 200 | – ⇒ 401 | – ⇒ 401 | – ⇒ 200 |

- **Every cell holds on every lane-run** (77 of 77).
- One request when libcurl sends credentials at once: `unset`, `BASIC` and `BEARER` are sent on the
  first request, whatever the server offers (`Authorization: Basic dXNlcjpwYXNz`,
  `case A:unset:basic raw out #1`), and a second round never follows.
- Every other mode sends nothing first, then at most one more request, in the scheme it picks from
  the challenge: Digest over Basic, in both header orders.
- `ANYSAFE` and `DIGEST|ONLY` never send Basic; `BASIC|ONLY` never sends Digest; against a 401 with
  no `WWW-Authenticate`, or an offer it may not use, libcurl ends after one request with that 401.
- A wrong Digest password ends after two requests with the 401 (item 3's `D:wrong`); a wrong
  Basic one, sent at once, after one (item 4's `basicwrong` rows). libcurl logs `Authentication
  problem. Ignoring this.` on 7.85.0 and 8.5.0, and `Digest authentication problem, ignoring.` or
  `Basic authentication problem, ignoring.` on 8.20.0 and 8.23.0.

**Bearer.** `XOAUTH2_BEARER tok123` in every row but the last. Servers `open`, `bearer`, `basic`.

| row | open | bearer | basic |
|---|---|---|---|
| unset-nouser | – ⇒ 200 | – ⇒ 401 | – ⇒ 401 |
| unset-user | Basic ⇒ 200 | Basic ⇒ 401 | Basic ⇒ 200 |
| BEARER-nouser | Bearer ⇒ 200 | Bearer ⇒ 200 | Bearer ⇒ 401 |
| BEARER-user | Bearer ⇒ 200 | Bearer ⇒ 200 | Bearer ⇒ 401 |
| ANY-nouser | – ⇒ 200 | – → Bearer ⇒ 200 | **8.20.0,7.85.0,8.5.0o,8.5.0g**: – → – ⇒ 401<br>**8.23.0**: – ⇒ 401 |
| ANY-user | – ⇒ 200 | – → Bearer ⇒ 200 | – → Basic ⇒ 200 |
| BEARER\|BASIC-user | – ⇒ 200 | – → Bearer ⇒ 200 | – → Basic ⇒ 200 |
| BEARER\|ONLY-nouser | – ⇒ 200 | – → Bearer ⇒ 200 | – ⇒ 401 |
| BEARER-notoken-user | – ⇒ 200 | – ⇒ 401 | – ⇒ 401 |

- `Authorization: Bearer tok123` goes out only when `HTTPAUTH` holds `BEARER` (`case
  B:BEARER-nouser:open raw out #1`). With `HTTPAUTH` unset the token is ignored: the URL's Basic
  goes out instead, or nothing without one. `BEARER` alone sends the token on the first request,
  and URL credentials beside it are not sent. With `ANY` or `BEARER|BASIC` it is sent only after a
  `Bearer` challenge. `BEARER` with no token sends nothing.
- **Varies:** `ANY` with a token and no user, against a Basic challenge: 8.23.0 ends after one
  request; the other four send a second request, also without `Authorization`.

## 3. Digest variants

`HTTPAUTH DIGEST`, user `user:pass`, GET unless named. The server verifies every parameter and the
response by its own arithmetic (`server: digest #K ok` or `bad(…)`); a wrong response is retried
against 48 other arithmetics, and `alt=` names the first that matches. Cases: `alg:ALG:QOP` with
`ALG` none (no `algorithm` parameter), MD5, MD5-sess, SHA-256, SHA-256-sess, SHA-512-256,
SHA-512-256-sess, and `QOP` auth, auth-int, none (no `qop`), both (`qop="auth,auth-int"`);
`userhash`; `stale` (the first valid response answered 401 with a new nonce and `stale=true`);
`wrong` (password `wrong`); `authint-post` and `auth-post`, a 1 KiB `POST`; `utf8`, user `üser`
and password `päss` from the URL; `reuse`, two transfers in sequence on one nonce, by fresh easy
handles and, as a control, by one easy handle added twice.

| case | result |
|---|---|
| alg:none:auth | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:none:auth-int | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:none:none | 2 req, #2 ok ⇒ 200 |
| alg:none:both | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:MD5:auth | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:MD5:auth-int | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:MD5:none | 2 req, #2 ok ⇒ 200 |
| alg:MD5:both | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:MD5-sess:auth | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:MD5-sess:auth-int | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:MD5-sess:none | 1 req, no Digest sent ⇒ 401 |
| alg:MD5-sess:both | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:SHA-256:auth | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:SHA-256:auth-int | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:SHA-256:none | 2 req, #2 ok ⇒ 200 |
| alg:SHA-256:both | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:SHA-256-sess:auth | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:SHA-256-sess:auth-int | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:SHA-256-sess:none | 1 req, no Digest sent ⇒ 401 |
| alg:SHA-256-sess:both | 2 req, #2 ok ⇒ 200, nc 00000001 |
| alg:SHA-512-256:auth | **8.20.0,8.23.0**: 2 req, #2 ok ⇒ 200, nc 00000001<br>**7.85.0,8.5.0o,8.5.0g**: 2 req, #2 bad(response) alt=sha256,body,qop,user ⇒ 401, nc 00000001 |
| alg:SHA-512-256:auth-int | **8.20.0,8.23.0**: 2 req, #2 ok ⇒ 200, nc 00000001<br>**7.85.0,8.5.0o,8.5.0g**: 2 req, #2 bad(response) alt=sha256,body,qop,user ⇒ 401, nc 00000001 |
| alg:SHA-512-256:none | **8.20.0,8.23.0**: 2 req, #2 ok ⇒ 200<br>**7.85.0,8.5.0o,8.5.0g**: 2 req, #2 bad(response) alt=sha256,body,qop,user ⇒ 401 |
| alg:SHA-512-256:both | **8.20.0,8.23.0**: 2 req, #2 ok ⇒ 200, nc 00000001<br>**7.85.0,8.5.0o,8.5.0g**: 2 req, #2 bad(response) alt=sha256,body,qop,user ⇒ 401, nc 00000001 |
| alg:SHA-512-256-sess:auth | **8.20.0,8.23.0**: 2 req, #2 ok ⇒ 200, nc 00000001<br>**7.85.0,8.5.0o,8.5.0g**: 2 req, #2 bad(response) alt=sha256-sess,body,qop,user ⇒ 401, nc 00000001 |
| alg:SHA-512-256-sess:auth-int | **8.20.0,8.23.0**: 2 req, #2 ok ⇒ 200, nc 00000001<br>**7.85.0,8.5.0o,8.5.0g**: 2 req, #2 bad(response) alt=sha256-sess,body,qop,user ⇒ 401, nc 00000001 |
| alg:SHA-512-256-sess:none | 1 req, no Digest sent ⇒ 401 |
| alg:SHA-512-256-sess:both | **8.20.0,8.23.0**: 2 req, #2 ok ⇒ 200, nc 00000001<br>**7.85.0,8.5.0o,8.5.0g**: 2 req, #2 bad(response) alt=sha256-sess,body,qop,user ⇒ 401, nc 00000001 |
| userhash:MD5 | 2 req, #2 ok ⇒ 200, nc 00000001 |
| userhash:SHA-256 | 2 req, #2 ok ⇒ 200, nc 00000001 |
| userhash:SHA-512-256 | **8.20.0,8.23.0**: 2 req, #2 ok ⇒ 200, nc 00000001<br>**7.85.0,8.5.0o,8.5.0g**: 2 req, #2 bad(username-hash,response) alt=sha256,body,qop,user ⇒ 401, nc 00000001 |
| stale:MD5 | 3 req, #2 ok, #3 ok ⇒ 200, nc 00000001/00000001 |
| wrong:MD5 | 2 req, #2 bad(response) ⇒ 401, nc 00000001 |
| authint-post:MD5 | 2 req, #2 bad(response) alt=md5,empty-body,qop,user ⇒ 401, nc 00000001 |
| auth-post:MD5 | 2 req, #2 ok ⇒ 200, nc 00000001 |
| stale:SHA-256 | 3 req, #2 ok, #3 ok ⇒ 200, nc 00000001/00000001 |
| wrong:SHA-256 | 2 req, #2 bad(response) ⇒ 401, nc 00000001 |
| authint-post:SHA-256 | 2 req, #2 bad(response) alt=sha256,empty-body,qop,user ⇒ 401, nc 00000001 |
| auth-post:SHA-256 | 2 req, #2 ok ⇒ 200, nc 00000001 |
| utf8:MD5 | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 2 req, #2 ok ⇒ 200, nc 00000001<br>**8.23.0**: 2 req, #2 bad(username) ⇒ 401, nc 00000001 |
| utf8-userhash:SHA-256 | 2 req, #2 ok ⇒ 200, nc 00000001 |
| reuse-fresh:1 | 2 req, #2 ok ⇒ 200, nc 00000001 |
| reuse-fresh:2 | 2 req, #2 ok ⇒ 200, nc 00000001, nonce-from=D.reuse-fresh.1.raw nc-repeat |
| reuse-same:1 | 2 req, #2 ok ⇒ 200, nc 00000001 |
| reuse-same:2 | 1 req, #1 ok ⇒ 200, nc 00000002, nonce-from=D.reuse-same.1.raw |

- **Supported, by the server's verdict:** MD5, MD5-sess, SHA-256, SHA-256-sess with `qop` auth,
  auth-int or none, and `userhash`, on every lane. **SHA-512-256 and SHA-512-256-sess only on
  8.20.0 and 8.23.0.** On 7.85.0 and both 8.5.0 builds the response is SHA-256's
  (`alt=sha256,body,qop,user`), under `algorithm=SHA-512-256`, and the transfer ends 401 after two
  requests.
- **No `qop` with a `-sess` algorithm:** libcurl sends no second request on any lane and ends
  with the 401 (`case D:alg:MD5-sess:none raw text t=0.1 "Digest authentication problem,
  ignoring."` in guix-8.20.0-1.log).
- **`qop="auth,auth-int"`:** libcurl picks `auth` on every lane.
- **`auth-int` on a POST hashes an empty body**, on every lane: `bad(response)
  alt=md5,empty-body,qop,user` (`case D:authint-post:MD5 raw server: digest #2`). On a GET, where
  the body is empty, it verifies.
- **`stale=true`:** a third request with the new nonce, `nc` back to `00000001`, then 200, on
  every lane (`server: stale: a valid response answered 401 stale=true`).
- **A wrong password:** two requests, the 401, code 0.
- **No Digest state crosses easy handles.** The second fresh handle sent its first request bare,
  then answered the same nonce with `nc=00000001` again (`nonce-from=D.reuse-fresh.1.raw
  nc-repeat`). The control, one easy handle added twice, sent `Authorization` on its first request
  with `nc=00000002` (`case D:reuse-same:2 raw out #1`). Every lane.
- **A UTF-8 user name:** the raw bytes in `username="\xc3\xbcser"` on four lanes, verified. 8.23.0
  writes `username="%C3%BCser"`, the URL's percent-encoding, and hashes the decoded bytes: the
  server's verdict is `bad(username)` alone, and `utf8-recompute.mjs`, apart from the server,
  matches libcurl's response with the bytes `c3 bc` and not with `%C3%BCser`, in both runs
  (`results/utf8-recompute.log`). With `userhash` the hash holds the decoded bytes on every lane,
  verified.

## 4. Bodies across a round

Bodies are byte i = i mod 251; the server checks the pattern and counts what it read. A whole body
is `POSTFIELDSIZE_LARGE` then `COPYPOSTFIELDS`; a streamed one `POST`, `POSTFIELDSIZE_LARGE` (the
length, or -1 for chunked), a read callback, `PREREQFUNCTION` and `FRESH_CONNECT`, with a seek
callback per row: `none`, `cant` (always `CANTSEEK`) or `adr32` (OK to offset 0 before any byte was
handed, else `CANTSEEK`). Expect: `default` (libcurl's own), `on` (`Expect: 100-continue` in
`HTTPHEADER`), `off` (`Expect:`). The stand-in reads a body whole before it answers, but refuses an
`Expect: 100-continue` request at its head when the head alone would fail, without `100 Continue`.

Cells: code, final status; then each request at the server as SCHEME/STATUS{BODY}: `–` no
`Authorization`, `✗` credentials refused; `(refused at head)` answered as the head arrived; `{N}`
the body read whole, `{part}` part of it before the client closed, `{0}` none, `{open}` still open
at the server 3 s after the transfer; `@pooled`, on a connection an earlier transfer of the lane had
used (by the client's port at the server).

### Whole body, HTTP/1.1 (group W)

| case | face | result |
|---|---|---|
| DIGEST:digest:64k:expect-default | raw | 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:64k:expect-on | raw | 0, 200; –/401@pooled · Digest/200{65536}@pooled |
| DIGEST:digest:64k:expect-off | raw | 0, 200; –/401@pooled · Digest/200{65536}@pooled |
| ANY:digest:64k:expect-default | raw | 0, 200; –/401{65536}@pooled · Digest/200{65536}@pooled |
| ANY:digest:64k:expect-on | raw | 0, 200; –/401 (refused at head){0}@pooled · Digest/200{65536} |
| ANY:digest:64k:expect-off | raw | 0, 200; –/401{65536}@pooled · Digest/200{65536}@pooled |
| ANY:basic:64k:expect-default | raw | 0, 200; –/401{65536}@pooled · Basic/200{65536}@pooled |
| ANY:basic:64k:expect-on | raw | 0, 200; –/401 (refused at head){0}@pooled · Basic/200{65536} |
| ANY:basic:64k:expect-off | raw | 0, 200; –/401{65536}@pooled · Basic/200{65536}@pooled |
| DIGEST\|BASIC:digest:64k:expect-default | raw | 0, 200; –/401{65536}@pooled · Digest/200{65536}@pooled |
| DIGEST\|BASIC:digest:64k:expect-on | raw | 0, 200; –/401 (refused at head){0}@pooled · Digest/200{65536} |
| DIGEST\|BASIC:digest:64k:expect-off | raw | 0, 200; –/401{65536}@pooled · Digest/200{65536}@pooled |
| BASIC:basic:64k:expect-default | raw | 0, 200; Basic/200{65536}@pooled |
| BASIC:basic:64k:expect-on | raw | 0, 200; Basic/200{65536}@pooled |
| BASIC:basic:64k:expect-off | raw | 0, 200; Basic/200{65536}@pooled |
| DIGEST:digest:2m:expect-default | raw | 0, 200; –/401@pooled · Digest/200{2097152}@pooled |
| ANY:digest:2m:expect-default | raw | 0, 200; –/401 (refused at head){0}@pooled · Digest/200{2097152} |

- **A single Digest bit holds the body back.** `DIGEST` sends a probe with `Content-Length: 0` and
  no body, then the body once with `Authorization` (`out #1 "Content-Length: 0"`), with every
  Expect, on every lane. With `Expect: 100-continue` forced, the probe carries it too.
- **Several bits send the body twice.** `ANY` and `DIGEST|BASIC` send the whole body on the first,
  bare request; after the 401 libcurl sends it again, 65,536 bytes read twice (8.20.0 and 8.23.0
  log `Need to rewind upload for next request`; the older three log no such line).
- **Unless the server refuses at the head.** With `Expect: 100-continue`, forced or libcurl's own
  (it adds it to a request carrying the 2 MiB body, 10 of 10, and to none carrying 64 KiB), the
  401 arrives before any body byte; libcurl closes the connection (`{0}`) and sends the body once,
  on a new one.

### Streamed body, HTTP/1.1 (group S)

| case | face | result |
|---|---|---|
| DIGEST:digest:sized:seek-none:expect-default | raw | 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:sized:seek-none:expect-on | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:sized:seek-none:expect-off | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:sized:seek-cant:expect-default | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:sized:seek-cant:expect-on | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:sized:seek-cant:expect-off | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:sized:seek-adr32:expect-default | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:sized:seek-adr32:expect-on | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:sized:seek-adr32:expect-off | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| ANY:digest:sized:seek-none:expect-default | raw | 65, 401; –/401{65536} |
| ANY:digest:sized:seek-none:expect-on | raw | 0, 200; –/401 (refused at head){0} · Digest/200{65536}@pooled |
| ANY:digest:sized:seek-none:expect-off | raw | 65, 401; –/401{65536} |
| ANY:digest:sized:seek-cant:expect-default | raw | 65, 401; –/401{65536} |
| ANY:digest:sized:seek-cant:expect-on | raw | 0, 200; –/401 (refused at head){0} · Digest/200{65536}@pooled |
| ANY:digest:sized:seek-cant:expect-off | raw | 65, 401; –/401{65536} |
| ANY:digest:sized:seek-adr32:expect-default | raw | 65, 401; –/401{65536} |
| ANY:digest:sized:seek-adr32:expect-on | raw | 0, 200; –/401 (refused at head){0} · Digest/200{65536}@pooled |
| ANY:digest:sized:seek-adr32:expect-off | raw | 65, 401; –/401{65536} |
| ANY:basic:sized:seek-none:expect-default | raw | 65, 401; –/401{65536} |
| ANY:basic:sized:seek-none:expect-on | raw | 0, 200; –/401 (refused at head){0} · Basic/200{65536}@pooled |
| ANY:basic:sized:seek-none:expect-off | raw | 65, 401; –/401{65536} |
| ANY:basic:sized:seek-cant:expect-default | raw | 65, 401; –/401{65536} |
| ANY:basic:sized:seek-cant:expect-on | raw | 0, 200; –/401 (refused at head){0} · Basic/200{65536}@pooled |
| ANY:basic:sized:seek-cant:expect-off | raw | 65, 401; –/401{65536} |
| ANY:basic:sized:seek-adr32:expect-default | raw | 65, 401; –/401{65536} |
| ANY:basic:sized:seek-adr32:expect-on | raw | 0, 200; –/401 (refused at head){0} · Basic/200{65536}@pooled |
| ANY:basic:sized:seek-adr32:expect-off | raw | 65, 401; –/401{65536} |
| BASIC:basic:sized:seek-none:expect-default | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:sized:seek-none:expect-on | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:sized:seek-none:expect-off | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:sized:seek-cant:expect-default | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:sized:seek-cant:expect-on | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:sized:seek-cant:expect-off | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:sized:seek-adr32:expect-default | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:sized:seek-adr32:expect-on | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:sized:seek-adr32:expect-off | raw | 0, 200; Basic/200{65536} |
| DIGEST:digest:chunked:seek-none:expect-default | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:chunked:seek-none:expect-on | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:chunked:seek-none:expect-off | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:chunked:seek-cant:expect-default | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:chunked:seek-cant:expect-on | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:chunked:seek-cant:expect-off | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:chunked:seek-adr32:expect-default | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:chunked:seek-adr32:expect-on | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| DIGEST:digest:chunked:seek-adr32:expect-off | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| ANY:digest:chunked:seek-none:expect-default | raw | 0, 200; –/401 (refused at head){0} · Digest/200{65536}@pooled |
| ANY:digest:chunked:seek-none:expect-on | raw | 0, 200; –/401 (refused at head){0} · Digest/200{65536}@pooled |
| ANY:digest:chunked:seek-none:expect-off | raw | 65, 401; –/401{65536} |
| ANY:digest:chunked:seek-cant:expect-default | raw | 0, 200; –/401 (refused at head){0} · Digest/200{65536}@pooled |
| ANY:digest:chunked:seek-cant:expect-on | raw | 0, 200; –/401 (refused at head){0} · Digest/200{65536}@pooled |
| ANY:digest:chunked:seek-cant:expect-off | raw | 65, 401; –/401{65536} |
| ANY:digest:chunked:seek-adr32:expect-default | raw | 0, 200; –/401 (refused at head){0} · Digest/200{65536}@pooled |
| ANY:digest:chunked:seek-adr32:expect-on | raw | 0, 200; –/401 (refused at head){0} · Digest/200{65536}@pooled |
| ANY:digest:chunked:seek-adr32:expect-off | raw | 65, 401; –/401{65536} |
| ANY:basic:chunked:seek-none:expect-default | raw | 0, 200; –/401 (refused at head){0} · Basic/200{65536}@pooled |
| ANY:basic:chunked:seek-none:expect-on | raw | 0, 200; –/401 (refused at head){0} · Basic/200{65536}@pooled |
| ANY:basic:chunked:seek-none:expect-off | raw | 65, 401; –/401{65536} |
| ANY:basic:chunked:seek-cant:expect-default | raw | **8.20.0,7.85.0,8.23.0**: 0, 200; –/401 (refused at head){0} · Basic/200{65536}@pooled<br>**8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head){0} · Basic/200{65536} |
| ANY:basic:chunked:seek-cant:expect-on | raw | 0, 200; –/401 (refused at head){0} · Basic/200{65536}@pooled |
| ANY:basic:chunked:seek-cant:expect-off | raw | 65, 401; –/401{65536} |
| ANY:basic:chunked:seek-adr32:expect-default | raw | **8.20.0,7.85.0,8.23.0**: 0, 200; –/401 (refused at head){0} · Basic/200{65536}@pooled<br>**8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head){0} · Basic/200{65536} |
| ANY:basic:chunked:seek-adr32:expect-on | raw | 0, 200; –/401 (refused at head){0} · Basic/200{65536}@pooled |
| ANY:basic:chunked:seek-adr32:expect-off | raw | 65, 401; –/401{65536} |
| BASIC:basic:chunked:seek-none:expect-default | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:chunked:seek-none:expect-on | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:chunked:seek-none:expect-off | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:chunked:seek-cant:expect-default | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:chunked:seek-cant:expect-on | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:chunked:seek-cant:expect-off | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:chunked:seek-adr32:expect-default | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:chunked:seek-adr32:expect-on | raw | 0, 200; Basic/200{65536} |
| BASIC:basic:chunked:seek-adr32:expect-off | raw | 0, 200; Basic/200{65536} |

- **`DIGEST` reads the body once, on the second request**, sized or chunked: the probe goes out
  with `Content-Length: 0`, libcurl calls no seek, and every seek mode ends 0 and 200.
- **`ANY` without a head refusal fails with 65**, after the server read the whole body:
  `necessary data rewind was not possible` (no seek; `wasn't` on 7.85.0 and 8.5.0), or `seek
  callback returned error 2` (`cant`, and `adr32`, since 65,536 bytes were handed). The server saw
  one request.
- **`ANY` with a head refusal ends 0 and 200 with every seek mode:** the 401 arrives before any
  body byte, libcurl closes the connection and sends the body once. A chunked body gets libcurl's
  own `Expect: 100-continue`, so its `default` row succeeds where the sized one fails; `Expect:`
  off fails both with 65.
- **`FRESH_CONNECT` holds for a transfer's first request only.** On 7.85.0, 8.5.0 and 8.20.0
  the authenticated request reused a connection an earlier transfer had pooled: on 7.85.0,
  `S:DIGEST:digest:sized:seek-none:expect-on`'s first request went out from local port 50548 and
  its second from 50530, the previous transfer's (`prereq n=2 … local_port=50530`, docker-1.log).
  On 8.23.0 the second request stayed on the transfer's own connection (`Reusing existing http:
  connection`, the same local port). After a head refusal closed the connection, the resend went to
  a pooled one in every such row, on every lane, but two chunked `default` rows on 8.5.0.

### A refusal before the body is sent whole (group E), HTTP/1.1 and HTTP/2

`early=1`: answered as the head arrives. `-mid`: answered once 64 KiB of a 4 MiB body had arrived
(`after=65536`, the shape of M6's early-3xx server), the rest still read. `stream`: 512 KiB from a
producer that gives 16 KiB each 100 ms, its read callback answering `PAUSE` until then. `noauth`:
no credentials, against a Basic challenge; `basicwrong`: `BASIC` with a wrong password;
`redirect`: a 301 control. Over HTTP/1.1 libcurl gives a 4 MiB body its own `Expect:
100-continue`, so the stand-in refuses those `-mid` rows at the head; the `-noexpect` rows add
`Expect:`, and are answered mid-body. libcurl sends no `Expect` over HTTP/2. Bound: 10 s.

| case | face | result |
|---|---|---|
| noauth-stream | raw | 0, 401; –/401 (refused at head){0} |
| basicwrong-stream | raw | 0, 401; Basic✗/401 (refused at head){0} |
| any-stream | raw | **8.20.0,8.23.0**: 65, 401; –/401 (refused at head){0}<br>**7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head){0} · Digest/200{524288} |
| any-stream-cant | raw | **8.20.0,8.23.0**: 65, 401; –/401 (refused at head){0}<br>**7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head){0} · Digest/200{524288}@pooled |
| any-stream-adr32 | raw | **8.20.0,8.23.0**: 0, 200; –/401 (refused at head){0} · Digest/200{524288}<br>**7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head){0} · Digest/200{524288}@pooled |
| digest-stream | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head) · Digest/200{524288}@pooled<br>**8.23.0**: 0, 200; –/401 (refused at head) · Digest/200{524288} |
| redirect-stream | raw | 0, 301; –/301 (refused at head){0} |
| noauth-whole1m | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 401; –/401 (refused at head){1048576}@pooled<br>**8.23.0**: 0, 401; –/401 (refused at head){part}@pooled |
| any-whole1m | raw | **8.20.0,8.5.0o,8.5.0g,8.23.0,7.85.0**: 0, 200; –/401 (refused at head){1048576}@pooled · Digest/200{1048576}@pooled<br>**7.85.0,8.5.0g**: 0, 200; –/401 (refused at head){part}@pooled · Digest/200{1048576}@pooled<br>**8.23.0**: 0, 200; –/401 (refused at head){part}@pooled · Digest/200{1048576} *(split on 8.5.0g, 8.23.0, 7.85.0)* |
| redirect-whole1m | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g,8.23.0**: 0, 301; –/301 (refused at head){part}@pooled<br>**7.85.0**: 0, 301; –/301 (refused at head){1048576}@pooled *(split on 7.85.0)* |
| redirect-whole4m-mid | raw | **8.20.0,8.5.0o,8.5.0g,7.85.0**: 0, 301; –/301 (refused at head){0}@pooled<br>**7.85.0,8.23.0,8.5.0g**: 0, 301; –/301 (refused at head){0} *(split on 8.5.0g, 7.85.0)* |
| noauth-whole4m-mid | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g,8.23.0**: 0, 401; –/401 (refused at head){0}<br>**7.85.0**: 0, 401; –/401 (refused at head){0}@pooled *(split on 7.85.0)* |
| basicwrong-whole4m-mid | raw | 0, 401; Basic✗/401 (refused at head){0} |
| any-whole4m-mid | raw | 0, 200; –/401 (refused at head){0} · Digest/200{4194304} |
| redirect-stream4m-mid | raw | 0, 301; –/301 (refused at head){0} |
| noauth-stream4m-mid | raw | 0, 401; –/401 (refused at head){0} |
| any-stream4m-mid-adr32 | raw | 0, 200; –/401 (refused at head){0} · Digest/200{4194304}@pooled |
| digest-stream4m-mid | raw | **8.20.0,7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{4194304}@pooled<br>**8.23.0**: 0, 200; –/401 · Digest/200{4194304} |
| noauth-stream | h2 | **8.20.0,8.23.0**: 0, 401; –/401 (refused at head){0} (rst_code=5)<br>**7.85.0,8.5.0o,8.5.0g**: 0, 401; –/401 (refused at head){0} (rst_code=1) |
| basicwrong-stream | h2 | **8.20.0,8.23.0**: 0, 401; Basic✗/401 (refused at head){0} (rst_code=5)<br>**7.85.0,8.5.0o,8.5.0g**: 0, 401; Basic✗/401 (refused at head){0} (rst_code=1) |
| any-stream | h2 | **8.20.0,8.23.0**: 65, 401; –/401 (refused at head){0} (rst_code=5)<br>**7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head){0} · Digest/200{524288} (rst_code=1) |
| any-stream-cant | h2 | **8.20.0,8.23.0**: 65, 401; –/401 (refused at head){0} (rst_code=5)<br>**7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head){0} · Digest/200{524288} (rst_code=1) |
| any-stream-adr32 | h2 | **8.20.0,8.23.0**: 0, 200; –/401 (refused at head){0} · Digest/200{524288} (rst_code=5)<br>**7.85.0,8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head){0} · Digest/200{524288} (rst_code=1) |
| digest-stream | h2 | **8.20.0,8.5.0o,8.5.0g**: 0, 200; –/401 (refused at head) · Digest/200{524288}@pooled<br>**7.85.0**: 0, 200; –/401 (refused at head){0} · Digest/200{524288}@pooled (rst_code=5)<br>**8.23.0**: 0, 200; –/401 (refused at head) · Digest/200{524288} |
| redirect-stream | h2 | **8.20.0,8.23.0**: **hung: gave up at 10 s**, 0, 301; –/301 (refused at head){0} (rst_code=5)<br>**7.85.0,8.5.0o,8.5.0g**: 0, 301; –/301 (refused at head){0} (rst_code=1) |
| noauth-whole1m | h2 | **8.20.0,7.85.0,8.23.0**: 0, 401; –/401 (refused at head){part}@pooled (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 401; –/401 (refused at head){open}@pooled |
| any-whole1m | h2 | 0, 200; –/401 (refused at head){part}@pooled · Digest/200{1048576}@pooled (rst_code=5) |
| redirect-whole1m | h2 | **8.20.0,8.23.0**: **hung: gave up at 10 s**, 0, 301; –/301 (refused at head){part}@pooled (rst_code=5)<br>**7.85.0**: 0, 301; –/301 (refused at head){part}@pooled (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 301; –/301 (refused at head){open}@pooled |
| redirect-whole4m-mid | h2 | **8.20.0,8.23.0**: **hung: gave up at 10 s**, 0, 301; –/301{part}@pooled (rst_code=5)<br>**7.85.0**: 0, 301; –/301{part}@pooled (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 301; –/301{open}@pooled<br>**7.85.0**: 0, 301; –/301{part}@pooled (rst_code=1) *(split on 7.85.0)* |
| noauth-whole4m-mid | h2 | **8.20.0,7.85.0,8.23.0**: 0, 401; –/401{part}@pooled (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 401; –/401{open}@pooled |
| basicwrong-whole4m-mid | h2 | **8.20.0,7.85.0,8.23.0**: 0, 401; Basic✗/401{part}@pooled (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 401; Basic✗/401{open}@pooled |
| any-whole4m-mid | h2 | 0, 200; –/401{part}@pooled · Digest/200{4194304}@pooled (rst_code=5) |
| redirect-stream4m-mid | h2 | **8.20.0,8.23.0**: **hung: gave up at 10 s**, 0, 301; –/301{part} (rst_code=5)<br>**7.85.0**: 0, 301; –/301{part} (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 301; –/301{open} |
| noauth-stream4m-mid | h2 | **8.20.0,7.85.0,8.23.0**: 0, 401; –/401{part} (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 401; –/401{open} |
| any-stream4m-mid-adr32 | h2 | **8.20.0,7.85.0,8.23.0**: 65, 401; –/401{part} (rst_code=5)<br>**8.5.0o,8.5.0g**: 65, 401; –/401{open} |
| digest-stream4m-mid | h2 | **8.20.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{4194304}@pooled<br>**7.85.0**: **hung: gave up at 10 s**, 0, 0; –/-{0} (rst_code=5)<br>**8.23.0**: 0, 200; –/401 · Digest/200{4194304} |
| redirect-whole4m-mid-noexpect | raw | 0, 301; –/301{part} |
| noauth-whole4m-mid-noexpect | raw | 0, 401; –/401{part} |
| basicwrong-whole4m-mid-noexpect | raw | 0, 401; Basic✗/401{part} |
| any-whole4m-mid-noexpect | raw | **8.20.0,7.85.0,8.5.0g,8.23.0,8.5.0o**: 0, 200; –/401{part} · Digest/200{4194304}<br>**8.5.0o**: 0, 200; –/401{part} · Digest/200{4194304}@pooled *(split on 8.5.0o)* |
| redirect-stream4m-mid-noexpect | raw | 0, 301; –/301{part} |
| noauth-stream4m-mid-noexpect | raw | 0, 401; –/401{part} |
| any-stream4m-mid-adr32-noexpect | raw | 65, 401; –/401{part} |
| digest-stream4m-mid-noexpect | raw | **8.20.0,7.85.0**: 0, 200; –/401 · Digest/200{4194304}@pooled<br>**8.5.0o,8.5.0g,8.23.0**: 0, 200; –/401 · Digest/200{4194304} |
| redirect-whole4m-mid-noexpect | h2 | **8.20.0,8.23.0**: **hung: gave up at 10 s**, 0, 301; –/301{part}@pooled (rst_code=5)<br>**7.85.0**: 0, 301; –/301{part}@pooled (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 301; –/301{open}@pooled |
| noauth-whole4m-mid-noexpect | h2 | **8.20.0,8.23.0,7.85.0**: 0, 401; –/401{part}@pooled (rst_code=5)<br>**7.85.0**: 0, 401; –/401{part}@pooled (rst_code=1)<br>**8.5.0o,8.5.0g**: 0, 401; –/401{open}@pooled *(split on 7.85.0)* |
| basicwrong-whole4m-mid-noexpect | h2 | **8.20.0,7.85.0,8.23.0**: 0, 401; Basic✗/401{part}@pooled (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 401; Basic✗/401{open}@pooled |
| any-whole4m-mid-noexpect | h2 | 0, 200; –/401{part}@pooled · Digest/200{4194304}@pooled (rst_code=5) |
| redirect-stream4m-mid-noexpect | h2 | **8.20.0,8.23.0**: **hung: gave up at 10 s**, 0, 301; –/301{part} (rst_code=5)<br>**7.85.0**: 0, 301; –/301{part} (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 301; –/301{open} |
| noauth-stream4m-mid-noexpect | h2 | **8.20.0,7.85.0,8.23.0**: 0, 401; –/401{part} (rst_code=5)<br>**8.5.0o,8.5.0g**: 0, 401; –/401{open} |
| any-stream4m-mid-adr32-noexpect | h2 | **8.20.0,7.85.0,8.23.0**: 65, 401; –/401{part} (rst_code=5)<br>**8.5.0o,8.5.0g**: 65, 401; –/401{open} |
| digest-stream4m-mid-noexpect | h2 | **8.20.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{4194304}@pooled<br>**7.85.0**: **hung: gave up at 10 s**, 0, 0; –/-{0} (rst_code=5)<br>**8.23.0**: 0, 200; –/401 · Digest/200{4194304} |

**When the transfer ends** (`done … t=`, ms from the add; both runs):

| case | face | 8.20.0 | 7.85.0 | 8.5.0o | 8.5.0g | 8.23.0 |
|---|---|---|---|---|---|---|
| noauth-stream (401 at head) | raw | 0.3, 0.3 | 101.0, 101.1 | 101.0, 101.1 | 101.0, 101.0 | 0.4, 0.3 |
| noauth-stream (401 at head) | h2 | 5.2, 5.0 | 100.0, 100.0 | 100.1, 100.1 | 100.0, 100.0 | 6.7, 5.5 |
| basicwrong-stream | h2 | 1.4, 1.3 | 100.0, 100.0 | 100.0, 100.0 | 100.0, 100.0 | 4.5, 2.6 |
| noauth-whole4m-mid | h2 | 1.5, 1.7 | 0.7, 0.7 | 2.5, 1.6 | 1.7, 1.1 | 1.1, 1.6 |
| noauth-stream4m-mid | h2 | 3.8, 3.9 | 1.9, 1.8 | 3.9, 4.4 | 4.0, 4.0 | 3.4, 4.1 |
| redirect-stream (301 at head) | h2 | gave up, gave up | 100.1, 100.1 | 100.1, 100.1 | 100.1, 100.1 | gave up, gave up |
| redirect-whole4m-mid (301) | h2 | gave up, gave up | 0.8, 0.8 | 2.2, 1.8 | 1.8, 2.0 | gave up, gave up |

- **An HTTP/2 401 that arrives before the body is sent whole ends the transfer, on every lane, in
  every shape:** at the head or mid-body, a whole or a streamed body, with or without credentials;
  code 0, status 401 (65 where a second round needed a rewind). Across the HTTP/2 401 rows, 8.20.0
  and 8.23.0 ended within 7.0 ms; 7.85.0 and 8.5.0 within 7.7 ms, but at 100.0 to 100.1 ms when
  the read callback was paused: at the producer's next piece.
- **The 301 control hangs on 8.20.0 and 8.23.0** to the 10 s bound in all six HTTP/2 shapes
  (`gave-up after 10000 ms … status=301`), after `HTTP error before end of send, stop sending`; it
  ends on 7.85.0 and 8.5.0. That is AGENTS.md's trap, reproduced beside the 401.
- **HTTP/1.1** ends every 401 and 301 too: within 4.3 ms on 8.20.0 and 8.23.0, within 1.0 ms on
  7.85.0 and 8.5.0, but at 100.9 to 101.3 ms on those two for the paused stream. libcurl closes
  the connection.
- **A round after an early 401 needs no rewind on 7.85.0 and 8.5.0 when no byte was handed.** For
  `ANY` with the paused stream (the read callback had answered `PAUSE` once, `reads=1 handed=0`),
  7.85.0 and 8.5.0 sent the body once on a second request and ended 200; 8.20.0 and 8.23.0 logged
  `Need to rewind upload for next request` and failed with 65 without a seek or with `cant`. With
  `adr32`, whose seek answered OK, every lane ended 200, on both faces.
- **Once bytes were handed, every lane fails with 65** (`any-stream4m-mid-adr32` on HTTP/2, and
  its `-noexpect` twin on HTTP/1.1). Its HTTP/1.1 row with libcurl's own `Expect` (a 4 MiB body)
  succeeds: refused at the head.
- **A whole body is resent:** `ANY` with a whole 1 or 4 MiB body ends 200 on every lane.
- **7.85.0 hangs on an HTTP/2 Digest POST whose body streams** when the server waits for the
  probe's end: the probe goes out with `content-length: 0` and the stream is never ended
  (`server: closed #1 before any answer … at 10004.2ms`; `gave-up … status=0`). It ended 200 when
  the server answered the probe at its head (`E:digest-stream h2`). Group H, below, shows it too.
- **8.5.0 leaves the HTTP/2 stream open:** after an HTTP/2 401 or 301 that arrived before a whole
  or an unpaused streamed body was sent, its transfer ended within 7.7 ms (`left intact`) while
  the server's stream was still open 3 s later (`log: 1 request(s) of this tag still open after
  3 s`). Elsewhere the server saw the stream close: Node's `rstCode` 5, or 1 on 7.85.0's and
  8.5.0's paused-stream rows and in one 7.85.0 run of two mid-body rows.

### HTTP/2, the server reading the body first (group H)

| case | face | result |
|---|---|---|
| any-whole | h2 | 0, 200; –/401{65536} · Digest/200{65536} |
| digest-whole | h2 | 0, 200; –/401@pooled · Digest/200{65536}@pooled |
| basic-whole | h2 | 0, 200; Basic/200{65536}@pooled |
| any-stream | h2 | 65, 401; –/401{65536} |
| any-stream-cant | h2 | 65, 401; –/401{65536} |
| any-stream-adr32 | h2 | 65, 401; –/401{65536} |
| any-stream-chunked | h2 | 65, 401; –/401{65536} |
| digest-stream | h2 | **8.20.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**7.85.0**: **hung: gave up at 10 s**, 0, 0; –/-{0} (rst_code=5)<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| digest-stream-chunked | h2 | **8.20.0,8.5.0o,8.5.0g**: 0, 200; –/401 · Digest/200{65536}@pooled<br>**7.85.0**: **hung: gave up at 10 s**, 0, 0; –/-{0} (rst_code=5)<br>**8.23.0**: 0, 200; –/401 · Digest/200{65536} |
| basic-stream | h2 | 0, 200; Basic/200{65536} |

- `ANY` with a whole body sends it twice and ends 200; with a streamed body it fails with 65 in
  every seek mode, chunked too.
- `DIGEST` with a streamed body ends 200 on four lanes and hangs on 7.85.0, as above.

## What varies by version

| what | 7.85.0 | 8.5.0 (both) | 8.20.0 | 8.23.0 |
|---|---|---|---|---|
| `USERNAME` against a URL with `user:password` | replaces the user | ignored | ignored | replaces it, drops the password |
| `PASSWORD` alone against a URL password | replaces it | replaces it | replaces it | ignored |
| `http://:@` or `http://@` | nothing sent | Basic `:` | Basic `:` | nothing sent |
| `PASSWORD` with no user anywhere | Basic `:password` | nothing | nothing | Basic `:password` |
| Digest SHA-512-256(-sess) | SHA-256's hash sent | SHA-256's hash sent | verified | verified |
| Digest, a UTF-8 user name | raw bytes | raw bytes | raw bytes | percent-encoded name, decoded hash |
| `ANY`, a token, no user, Basic challenge | 2 requests | 2 requests | 2 requests | 1 request |
| `FRESH_CONNECT`'s authenticated request | a pooled connection | a pooled connection | a pooled connection | its own connection |
| a round after an early 401, nothing handed | no rewind | no rewind | rewind: 65 without a seek | rewind: 65 without a seek |
| an early 401 with a paused read callback | ends at its next piece | ends at its next piece | ends at once | ends at once |
| HTTP/2 301 before the body is whole | ends | ends | hangs | hangs |
| HTTP/2 Digest POST, streamed body, a server that waits for the probe's end | hangs | 200 | 200 | 200 |

Ubuntu's 8.5.0 with OpenSSL and with GnuTLS agree in every case but three, each of which split
between runs (`any-whole1m`, `redirect-whole4m-mid` and `any-whole4m-mid-noexpect`, raw).

## What split

No item 1, 2 or 3 case split, nor any outcome: code, status, request count, `Authorization`
sequence, verdict, hang. Seven group E cases split between runs of one lane in what the server saw
of a body the client had stopped sending (read whole or in part), in which connection a request
used, or in Node's `rstCode`, so each is recorded as split: `any-whole1m` raw (7.85.0, 8.5.0g,
8.23.0), `redirect-whole1m` raw (7.85.0), `redirect-whole4m-mid` raw (7.85.0, 8.5.0g) and h2
(7.85.0, `rst_code` 5 against 1), `noauth-whole4m-mid` raw (7.85.0), `any-whole4m-mid-noexpect`
raw (8.5.0o), `noauth-whole4m-mid-noexpect` h2 (7.85.0, `rst_code`). The table rows marked *split*
show both values.

## Not measured

- **Apple's libcurl 8.7.1.** `mac.sh` is written, not run: on the Mac, from the repository's root,
  `sh .plans/research/m7/auth/mac.sh`. It runs `run.sh` twice against `/usr/lib/libcurl.4.dylib`
  (`cc -lcurl`, the SDK's headers), with `NODE="$(asdf which node)"` unless `NODE` is set and
  `CURL_SSL_BACKEND=secure-transport`, and writes `results/mac-8.7.1-1.log` and `-2.log`, printing
  each path, its line and row counts and its `exit=0` count (9 expected). The Mac's git ignores
  `results/` globally: `git add -f`.
- **Proxy auth, NTLM, Negotiate and `NETRC`:** excluded (the brief; ADR-0033).
- **The Digest arithmetic for `-sess` and `auth-int`** has no published example checked here: RFC
  7616's examples cover MD5 and SHA-256 with `qop=auth`, and its SHA-512-256 example carries an
  erratum, so it was not used. That every lane's `-sess` and `auth-int` GET responses verify is
  agreement with libcurl, not an independent proof.
- **What 8.5.0 does with the HTTP/2 stream it leaves open:** the server's log is read 3 s on, and the
  server closes every connection when its stdin ends.
- **libcurl's 1 s Expect timeout** never ran: the stand-in answers every `Expect: 100-continue` at
  once, with `100 Continue` or a refusal.
- **`@pooled`** is read from the client's port at the server, within one lane-run; a port the
  kernel reused would read as pooled. The prereq lines' `local_port` agree where checked.
- **The logs are large:** about 1.8 MB per container run and 8 MB per Docker run (four lanes),
  19 MB in all, most of it libcurl's `VERBOSE` text and the server's header lines.
