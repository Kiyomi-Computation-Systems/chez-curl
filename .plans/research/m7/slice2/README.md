# M7 slice 2 research: auth, through the engine

Measured 2026-11-02 for M7 slice 2 ([plan](../../../2026-11-02-m7-plan.md), section 5.1;
[ADR-0036](../../../decisions/0036-credentials-and-one-auth-scheme.md)). Every transfer went through
chez-curl's engine: credentials by the hatch, `curl-request-with-options`, on a prototype copy of
`src/`; the hatch's refusals and today's origin rule on main's `src/`. Five Linux libcurls ran it,
two runs each, then items 1, 2 and 6 once more under the memory gate's Valgrind. It reports what
libcurl does through the engine. It recommends nothing.

## In short

- **Item 1, each scheme.** Basic and Bearer send their credentials on the first request and never
  a second, on every face, `get` and `post`; a wrong password or token ends with the server's 401
  and code 0. Digest sends a bare request, then one more with the body, `Content-Length: 0` on the
  probe. MD5, MD5-sess, SHA-256 and SHA-256-sess verify on all five; SHA-512-256 on 8.20.0 and
  8.23.0 alone; `-sess` with no `qop` sends no second request. Two answers the C probe had no case
  for:
  - Digest against a route that answers without a challenge sends a `post` twice: the bare probe
    is answered 200, then the body is sent again and answered 200, on all five (`schemes20`).
  - Digest against a Basic challenge sends one bare request and ends 401, the body never sent.
- **Item 2, streams.** Basic and Bearer beside a streamed body, sized or chunked, and beside a
  streamed response: one request each, the 256 KiB body whole at the stand-in, over `http` and
  `h2`, on all five. A wrong password answered at the head, or mid-body, ends 401, code 0, the
  producer's last put answering `done`, within 10 ms on every lane; libcurl had sent part of the
  body. Digest beside each, on the prototype:
  - a streamed body is sent once, after a bare probe, but on 7.85.0 over `h2` to a server that
    waits for the probe's end the transfer fails 28 at its 10 s timeout (`streams51`, F);
  - a streamed response publishes the 401's head, while the transfer ends 200 with the 200's body
    read through the same stream, on all five (`streams49`).
- **Item 3, empty values.** 8.23.0 sends nothing for `USERNAME ""` with `PASSWORD ""`, under Basic
  and Digest, nor for `XOAUTH2_BEARER ""`, and ends 401 after one bare request; the other four send
  Basic `:`, a Digest `username=""` the stand-in verifies, and `Bearer ` (`empty1`). A user with an
  empty password, and the reverse, go out on all five. Over `h2` no lane's empty token reached the
  stand-in.
- **Item 4, hostile bytes.** The hatch's strings are UTF-8, by `call-with-c-string`, and refuse
  U+0000, CR and LF, so the prototype adds a byte seam (below); NUL is refused by both,
  `embedded-nul`.
  - **A header of its own:** CR LF in a Bearer token writes `X-Injected: 1` on all five, over
    HTTP/1.1 and over `h2` (`bytes85`); in a Digest user name on 7.85.0 to 8.20.0, while 8.23.0
    percent-encodes it (`bytes34`). Basic's base64 carries every byte, CR LF too.
  - **8.23.0 percent-encodes a Digest user name's bytes below 0x20, 0x7F and above 0x7F,** a UTF-8
    name by `USERNAME` among them (`bytes87`), and hashes the raw bytes, so the stand-in refuses
    it; the other four send the bytes raw in `username="..."`, verified. No lane sends
    `username*=`.
  - **Over `h2`:** a bare LF in a Bearer token fails 43 on 8.5.0 and later, before anything is
    sent (`bytes180`), and in a Digest user name on 8.5.0 to 8.20.0, which 8.23.0 percent-encodes;
    a CR cuts the value there; 7.85.0 fails 27 on a CR. 0x01, 0x1F and 0x7F reach nghttp2
    (libcurl's own trace, `bytestrace10`), and the stand-in's HTTP/2 stack drops the field.
  - **Lengths:** 8 KiB passes everywhere; 64 KiB over HTTP/1.1 alone, failing 55 over `h2` (56 on
    7.85.0) with nothing sent; a 1 MiB password or token fails 27 (7.85.0, 8.5.0) or 100 (8.20.0,
    8.23.0) with nothing sent, but Digest's 1 MiB password passes, since only its hash is sent;
    8,000,000 bytes fails 27 everywhere; 8,000,001 is refused at the setopt, 43.
- **Item 5, rounds inside one transfer.** Digest's second request rides the probe's connection on
  every face, `get` and `post`. A caller's `Expect: 100-continue` against a server that answers 417
  to every request carrying it loops: 31 requests then 47 on 8.5.0 and later, `MAXREDIRS`' default
  30; on 7.85.0, whose default is -1, 90,712 and 90,104 requests until the 5 s timeout, 28
  (`rounds1`). Answered 417 once, the caller's header goes out again on the resend, which passes.
  Under Digest, a 417 to the probe ends the transfer 417. A `stale=true` challenge gets a third
  request, and a second one a fourth, on all five; Basic and Bearer never resend. The private
  follow keeps credentials within one origin and drops them on another port, another host
  (`localhost` against `127.0.0.1`, either way) and another scheme on the same port, unless
  `UNRESTRICTED_AUTH` is 1; then 7.85.0 sends Digest to the other origin at once, where 8.5.0 and
  later start a new round (`rounds80`). 7.85.0 resolves `localhost` to 127.0.0.1; the rest reach
  `::1` first.
- **Item 6, pooled connections.** A second Digest transfer on the first's pooled connection
  starts bare; one with other credentials carries its own, and one with none carries none, on
  every face, all five. Over `h2`, two Digest transfers submitted in one batch: the second's
  authenticated request moves to the first's connection on 7.85.0 to 8.20.0, and stays on its own
  on 8.23.0 (`pooled48`).
- **Item 7, the twins.** `LOGIN_OPTIONS`, `SASL_AUTHZID`, `SASL_IR` and `SERVICE_NAME` change
  nothing sent. `NETRC_FILE` alone turns no netrc on, on all five, as the source reads. Options that
  change what credentials send, or how a wrong password ends:
  - `AWS_SIGV4` set after `HTTPAUTH` replaces each scheme with an `AWS4-HMAC-SHA256` signature;
    set before it, `HTTPAUTH` wins;
  - `MAXREDIRS` 0 stops Digest after the probe, 47; 1 stops a `stale` round's third request, 47
    (`twins50`, `twins52`): each auth round is a follow libcurl counts;
  - `FAILONERROR` 1 makes a wrong password's 401 code 22 (`twins7`);
  - `AUTOREFERER` 1 adds a `Referer` to Digest's second request (`twins53`);
  - `KEEP_SENDING_ON_ERROR` 1 sends a streamed body whole after a 401 at its head over HTTP/1.1,
    and on 7.85.0 over `h2` fails 28 (`twins67`, `twins69`);
  - `DISALLOW_USERNAME_IN_URL` 1 does nothing to a first request, since the URL arrives as a
    `CURLU` and is not parsed again; on 7.85.0 it refuses Digest's second request beside URL
    userinfo, 67 (`twins30`).
- **Item 8, the high level's hops.** Built as `next-request` builds them, each hop a fresh transfer
  on one engine carrying the same hatch credentials, every hop sends them: another port, another
  host, `https` on the same port. Each Digest hop starts its own round. A same-origin hop reuses
  the first leg's pooled connection. A `Location` holding `u2:p2@` beside the options sends the
  options' `user:pass` on all five (`hops16`). Today's origin rule makes `http://h/` and
  `http://h:80/` one origin, as it does `https://h/` and `https://h:443/`: `curl-url-part` gives
  the default port.
- **`MAXREDIRS` 30, set by the hatch** (an addition, `maxredirs.sps`): 7.85.0 then stops rounds1's
  `Expect` loop at 31 requests with 47, as 8.5.0 and later do at their default, under Basic and
  Bearer (Digest's probe ends 417 at once at either value). A Digest route answering `stale=true`
  for ever runs 7.85.0 at its default to its 5 s timeout, 42,826 and 42,689 requests, 28, and every
  other lane, and 7.85.0 at 30, to 31 requests and 47. A Digest round that is challenged once ends
  200 in two requests at 30 on all five.
- **The Valgrind pass:** 474 of 474 transfers of items 1, 2 and 6 gave the same code, status and
  statuses as both native runs on Ubuntu's 8.5.0 with OpenSSL; 0 errors, 0 bytes definitely lost.
- **Nothing split between the kept runs but how much of a body cut short the stand-in read,** in
  three cells ("What split").

## What was run

- **`auth.sps`, one Chez program in twelve parts, run as thirteen processes.** Its header lists them:
  `refusals` (on main's `src/` as `refusals-main`, and on the prototype), `schemes` (item 1),
  `wire` (the wire check), `streams` (2), `empty` (3), `bytes` and `bytestrace` (4), `rounds` (5),
  `pooled` (6), `twins` (7), `hops` and `origin` (8, `origin` on main's `src/`). Every request
  carries `ca-file` and `timeout-ms` 10,000 unless named; every wait is bounded at 15,000 ms, and a
  transfer still running then is cancelled and logged `hung` (none was). Each case runs on an
  engine of its own, but item 6's and item 8's, whose transfers share one. Each transfer prints a
  `t` line, then the stand-in's log for its tag, `s TAG ...`.
- **Credentials go in as the field would set them,** by the hatch: `HTTPAUTH` at the scheme's bit
  (`BASIC` 1, `DIGEST` 2, `BEARER` 64), then `USERNAME` and `PASSWORD`, or `XOAUTH2_BEARER`.
- **The hatch's string encoding is UTF-8.** `set-hatch-option!` sets a string through
  `set-string-option!`, which calls `call-with-c-string` (`src/curl/private/native.sls:467-490`): a
  copy, `string->utf8`, a NUL appended, a string holding U+0000 refused as `&curl-embedded-nul`.
  Before that, `hatch-value` refuses U+0000, CR and LF in a string (`text-fault`,
  `src/curl/private/transfer.sls:1495-1506`). So a string cannot carry a lone byte above 0x7F, CR
  or LF, and item 4 needs each.
- **`make-prototype.sh`** copies `src/` to `build/m7s2/src` and changes three things in
  `(curl private transfer)`, nothing else; `prototype.diff` is the change, 5 lines removed and 13
  added, and the script fails unless it is exactly that:
  1. `owned-option-names` leaves out `USERNAME` and `PASSWORD`. `HTTPAUTH`, `XOAUTH2_BEARER`,
     `AWS_SIGV4` and every twin measured are the hatch's on main already (the refusals table).
  2. `rounds-option-names` is `("PROXYAUTH")`, so a streamed response beside `HTTPAUTH` passes.
  3. **A byte seam:** a string option's value may be a bytevector, sent as those bytes and a NUL by
     `call-with-foreign-bytes`; one holding a 0 byte is refused, `embedded-nul`. A string keeps
     today's rules.
- **`standin.mjs`** (Node's standard library), adapted from [`../auth/server.mjs`](../auth/server.mjs),
  whose Digest arithmetic, self-test and parsers it keeps unchanged:
  - faces, each on 127.0.0.1 and `::1` at one port: `http`, HTTP/1.1 from bytes, which takes TLS
    on the same port when a connection's first byte is 0x16, so a hop can change the scheme
    alone; `httpb`, another port; `https`, TLS with ALPN `http/1.1` alone; `h2`, ALPN `h2` alone,
    header lists to 16 MiB; and `ctl`, for the logs;
  - route `/auth` and below it: a chosen challenge (`ch=`), an account as hex bytes (`uh=`, `ph=`,
    `th=`) or a length (`plen=`, `tlen=`), Digest by algorithm and `qop`, `stale=N`, a 302 to the
    URL `go=` names, `expect=417` and `417once`, `early=1`, `after=N`, `size=`, `slow=`;
  - a log per request, under its tag: its face, connection number on that face, peer address,
    request line, every header name, the raw head escaped, each `Authorization` whole, the body's
    length and SHA-256, the verdict and the answer; a tag's first 40 requests in full, then a count.
- **Checks on the instrument, each watched failing:**
  - the self-test, `selftest ok 13`, first on every lane-run (RFC 2617's and RFC 7616's vectors and
    four planted failures); `selftest-control.sh` puts `nc` before the nonce in a copy, and all
    three vectors fail, exit 1 (`results/selftest-control-guix-8.20.0.log`);
  - the wire check, `wire.mjs`: libcurl's own trace of each `Authorization` it sent (the `wire`
    part, `VERBOSE`) against the stand-in's log, whole; 160 of 160 the same over the kept logs
    (`results/wire-check.log`); `wire-control.sh` runs the part against a copy that logs each
    value one byte short: 16 `DIFFERS`, exit 1, then 16 the same against the stand-in as it is
    (`results/wire-control-guix-8.20.0.log`);
  - the Valgrind comparison, against lane F's native runs instead of lane O's: 4 of 474 differ,
    the 7.85.0 `h2` Digest stream rows (`results/valgrind-control.log`).
- **`tables.mjs`** builds every table below from the kept logs alone, and marks a cell the two runs
  disagree on `**run 1 / run 2**`; a face, or a Digest variant, whose cells agree on every lane in
  both runs shares a row. The tables are its output, unedited.

**The lanes,** each from its log's `uname`, `libcurl version=`, `package` and `node` lines. All ran
on Linux x86_64.

| | lane | where | libcurl | TLS | Node |
|---|---|---|---|---|---|
| F | `floor-7.85.0` | Docker `ubuntu:24.04` (24.04.5 LTS, `sha256:68ee2200…`) | `build/e1/ci/curl-floor/lib/libcurl.so.4.8.0`, 7.85.0 | OpenSSL 3.0.13 | 20.10.0 |
| O | `ubuntu-openssl-8.5.0` | same image | `/usr/lib/x86_64-linux-gnu/libcurl.so.4.8.0` (libcurl4t64 8.5.0-2ubuntu10.16) | OpenSSL 3.0.13 | 20.10.0 |
| G | `ubuntu-gnutls-8.5.0` | same image | `…/libcurl-gnutls.so.4.8.0` (libcurl3t64-gnutls 8.5.0-2ubuntu10.16) | GnuTLS 3.8.3 | 20.10.0 |
| X | `guix-8.20.0` | the Guix container (`scripts/guix-env`) | `/gnu/store/67lpb53n…-curl-8.20.0/lib/libcurl.so.4.8.0`, 8.20.0 | GnuTLS 3.8.13 | 24.18.0 |
| C | `current-8.23.0` | Docker `ubuntu:24.04` | `build/verify/c823/lane1/curl-current/lib/libcurl.so.4.8.0`, 8.23.0 | OpenSSL 3.0.13 | 20.10.0 |

Chez is 10.4.0, threaded: the profile's in the container, `build/e1/ci/chez-threads` in Docker.
The Valgrind pass ran lane O in the same image, Valgrind 3.22.0 (1:3.22.0-0ubuntu3), with the
memory gate's options exactly and no suppression, GNU `timeout` outside it.

**To rerun,** from the repository's root, on the host:

```sh
sh .plans/research/m7/slice2/all.sh 1 2 valgrind    # the prototype, both runs, then Valgrind (about 13 minutes)
# one lane, or some parts:
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice2/run.sh guix-8.20.0 [PART...]' < /dev/null
sh .plans/research/m7/slice2/docker.sh LANES [PART...]        # LANES: all, or a comma list
VALGRIND=1 sh .plans/research/m7/slice2/docker.sh ubuntu-openssl-8.5.0 schemes streams pooled
# the tables, the Valgrind comparison and its control, the wire check:
scripts/guix-env sh -c 'node .plans/research/m7/slice2/tables.mjs' < /dev/null
scripts/guix-env sh -c 'node .plans/research/m7/slice2/tables.mjs --valgrind [--against=floor-7.85.0]' < /dev/null
scripts/guix-env sh -c 'node .plans/research/m7/slice2/wire.mjs .plans/research/m7/slice2/results/*-[12].log' < /dev/null
# the controls:
scripts/guix-env sh .plans/research/m7/slice2/selftest-control.sh < /dev/null
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice2/wire-control.sh' < /dev/null
# the MAXREDIRS addition, both runs, every lane (about a minute; keeps an existing prototype):
sh .plans/research/m7/slice2/all.sh maxredirs-1 maxredirs-2
```

**The logs** (in `results/`): `guix-8.20.0-1.log` and `docker-1.log` are run 1 (Docker's lanes in
the order F, O, G, C), `-2` run 2; `valgrind-ubuntu-openssl-8.5.0.log` the Valgrind pass. Every
one records the same hashes: `src/` `6c773dd3…` (`git diff main -- src` is empty), the prototype
`64d6ca37…`, `auth.sps` `103d5a1e…`, `standin.mjs` `51655a8f…`. A tag names one transfer, and is
the same on every lane and in both runs: `schemes20` is item 1's twentieth case everywhere.

### Checks, each lane-run

| lane | run | exits | self-test | counts | transfers | hung | tags still open 3 s on | error lines |
|---|---|---|---|---|---|---|---|---|
| F | 1 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| O | 1 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| G | 1 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| X | 1 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| C | 1 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| F | 2 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| O | 2 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| G | 2 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| X | 2 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| C | 2 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |

## The hatch, on main and on the prototype

On main's `src/` the hatch refuses `USERNAME` and `PASSWORD`, `owned-option`, and `HTTPAUTH` beside
a `stream-buffer`, `stream-with-rounds`, on all five; `HTTPAUTH` beside a streamed body passes, as
the plan's §3.3 says. A bytevector for a string option is an assertion violation on main; the
prototype's seam takes it, CR and LF too, and refuses a 0 byte.

### The hatch, on main's `src/` and on the prototype (`r` lines)

A cell: `attached`, or the refusal's reason, or `condition` for an assertion violation (the option takes a string).

| case | tree | F | O | G | X | C |
|---|---|---|---|---|---|---|
| USERNAME | main | refused owned-option | refused owned-option | refused owned-option | refused owned-option | refused owned-option |
| PASSWORD | main | refused owned-option | refused owned-option | refused owned-option | refused owned-option | refused owned-option |
| HTTPAUTH | main | attached | attached | attached | attached | attached |
| HTTPAUTH-beside-stream-buffer | main | refused stream-with-rounds | refused stream-with-rounds | refused stream-with-rounds | refused stream-with-rounds | refused stream-with-rounds |
| HTTPAUTH-beside-body-stream | main | attached | attached | attached | attached | attached |
| PROXYAUTH-beside-stream-buffer | main | refused stream-with-rounds | refused stream-with-rounds | refused stream-with-rounds | refused stream-with-rounds | refused stream-with-rounds |
| XOAUTH2_BEARER | main | attached | attached | attached | attached | attached |
| AWS_SIGV4 | main | attached | attached | attached | attached | attached |
| XOAUTH2_BEARER-CR | main | refused line-break | refused line-break | refused line-break | refused line-break | refused line-break |
| XOAUTH2_BEARER-LF | main | refused line-break | refused line-break | refused line-break | refused line-break | refused line-break |
| XOAUTH2_BEARER-NUL | main | refused embedded-nul | refused embedded-nul | refused embedded-nul | refused embedded-nul | refused embedded-nul |
| XOAUTH2_BEARER-bytes | main | condition: takes a string | condition: takes a string | condition: takes a string | condition: takes a string | condition: takes a string |
| XOAUTH2_BEARER-bytes-NUL | main | condition: takes a string | condition: takes a string | condition: takes a string | condition: takes a string | condition: takes a string |
| USERNAME-bytes | main | refused owned-option | refused owned-option | refused owned-option | refused owned-option | refused owned-option |
| LOGIN_OPTIONS | main | attached | attached | attached | attached | attached |
| DISALLOW_USERNAME_IN_URL | main | attached | attached | attached | attached | attached |
| UNRESTRICTED_AUTH | main | attached | attached | attached | attached | attached |
| NETRC_FILE | main | attached | attached | attached | attached | attached |
| NETRC | main | refused owned-option | refused owned-option | refused owned-option | refused owned-option | refused owned-option |
| SASL_AUTHZID | main | attached | attached | attached | attached | attached |
| SASL_IR | main | attached | attached | attached | attached | attached |
| SERVICE_NAME | main | attached | attached | attached | attached | attached |
| KEEP_SENDING_ON_ERROR | main | attached | attached | attached | attached | attached |
| FAILONERROR | main | attached | attached | attached | attached | attached |
| USERPWD | main | refused owned-option | refused owned-option | refused owned-option | refused owned-option | refused owned-option |
| PROXYAUTH | main | attached | attached | attached | attached | attached |
| USERNAME | prototype | attached | attached | attached | attached | attached |
| PASSWORD | prototype | attached | attached | attached | attached | attached |
| HTTPAUTH | prototype | attached | attached | attached | attached | attached |
| HTTPAUTH-beside-stream-buffer | prototype | attached | attached | attached | attached | attached |
| HTTPAUTH-beside-body-stream | prototype | attached | attached | attached | attached | attached |
| PROXYAUTH-beside-stream-buffer | prototype | refused stream-with-rounds | refused stream-with-rounds | refused stream-with-rounds | refused stream-with-rounds | refused stream-with-rounds |
| XOAUTH2_BEARER | prototype | attached | attached | attached | attached | attached |
| AWS_SIGV4 | prototype | attached | attached | attached | attached | attached |
| XOAUTH2_BEARER-CR | prototype | refused line-break | refused line-break | refused line-break | refused line-break | refused line-break |
| XOAUTH2_BEARER-LF | prototype | refused line-break | refused line-break | refused line-break | refused line-break | refused line-break |
| XOAUTH2_BEARER-NUL | prototype | refused embedded-nul | refused embedded-nul | refused embedded-nul | refused embedded-nul | refused embedded-nul |
| XOAUTH2_BEARER-bytes | prototype | attached | attached | attached | attached | attached |
| XOAUTH2_BEARER-bytes-NUL | prototype | refused embedded-nul | refused embedded-nul | refused embedded-nul | refused embedded-nul | refused embedded-nul |
| USERNAME-bytes | prototype | attached | attached | attached | attached | attached |
| LOGIN_OPTIONS | prototype | attached | attached | attached | attached | attached |
| DISALLOW_USERNAME_IN_URL | prototype | attached | attached | attached | attached | attached |
| UNRESTRICTED_AUTH | prototype | attached | attached | attached | attached | attached |
| NETRC_FILE | prototype | attached | attached | attached | attached | attached |
| NETRC | prototype | refused owned-option | refused owned-option | refused owned-option | refused owned-option | refused owned-option |
| SASL_AUTHZID | prototype | attached | attached | attached | attached | attached |
| SASL_IR | prototype | attached | attached | attached | attached | attached |
| SERVICE_NAME | prototype | attached | attached | attached | attached | attached |
| KEEP_SENDING_ON_ERROR | prototype | attached | attached | attached | attached | attached |
| FAILONERROR | prototype | attached | attached | attached | attached | attached |
| USERPWD | prototype | refused owned-option | refused owned-option | refused owned-option | refused owned-option | refused owned-option |
| PROXYAUTH | prototype | attached | attached | attached | attached | attached |

## Item 1: each scheme through the engine

Cases: `right`, the account's credentials; `wrong`, the password `wrong` or the token `wrong`;
`other`, a challenge of another scheme (Digest for Basic, Basic for Digest and Bearer); `none`, a 401
with no challenge; `open`, 200 always. `post` carries a 1 KiB body in memory.

### Item 1: each scheme, each case (`i1` lines)

A cell: each request at the stand-in, in order: its `Authorization` scheme (– none), the stand-in's verdict (✓ valid, ✗ refused), its status, `{N}` the body bytes it read; then ⇒ the final status, or the code. Every case ran on a fresh engine.

| scheme | case | method | face | F | O | G | X | C |
|---|---|---|---|---|---|---|---|---|
| basic | right | get | http, https, h2 | Basic✓/200 ⇒ 200 | Basic✓/200 ⇒ 200 | Basic✓/200 ⇒ 200 | Basic✓/200 ⇒ 200 | Basic✓/200 ⇒ 200 |
| basic | right | post | http, https, h2 | Basic✓/200{1024} ⇒ 200 | Basic✓/200{1024} ⇒ 200 | Basic✓/200{1024} ⇒ 200 | Basic✓/200{1024} ⇒ 200 | Basic✓/200{1024} ⇒ 200 |
| basic | wrong | get | http, https, h2 | Basic✗/401 ⇒ 401 | Basic✗/401 ⇒ 401 | Basic✗/401 ⇒ 401 | Basic✗/401 ⇒ 401 | Basic✗/401 ⇒ 401 |
| basic | wrong | post | http, https, h2 | Basic✗/401{1024} ⇒ 401 | Basic✗/401{1024} ⇒ 401 | Basic✗/401{1024} ⇒ 401 | Basic✗/401{1024} ⇒ 401 | Basic✗/401{1024} ⇒ 401 |
| basic | other | get | http, https, h2 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 |
| basic | other | post | http, https, h2 | Basic✓/401{1024} ⇒ 401 | Basic✓/401{1024} ⇒ 401 | Basic✓/401{1024} ⇒ 401 | Basic✓/401{1024} ⇒ 401 | Basic✓/401{1024} ⇒ 401 |
| basic | none | get | http, https, h2 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 |
| basic | none | post | http, https, h2 | Basic✓/401{1024} ⇒ 401 | Basic✓/401{1024} ⇒ 401 | Basic✓/401{1024} ⇒ 401 | Basic✓/401{1024} ⇒ 401 | Basic✓/401{1024} ⇒ 401 |
| basic | open | get | http, https, h2 | Basic✓/200 ⇒ 200 | Basic✓/200 ⇒ 200 | Basic✓/200 ⇒ 200 | Basic✓/200 ⇒ 200 | Basic✓/200 ⇒ 200 |
| basic | open | post | http, https, h2 | Basic✓/200{1024} ⇒ 200 | Basic✓/200{1024} ⇒ 200 | Basic✓/200{1024} ⇒ 200 | Basic✓/200{1024} ⇒ 200 | Basic✓/200{1024} ⇒ 200 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth | right | get | http, https, h2 | –/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/200 ⇒ 200 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth | right | post | http, https, h2 | –/401 → Digest✓/200{1024} ⇒ 200 | –/401 → Digest✓/200{1024} ⇒ 200 | –/401 → Digest✓/200{1024} ⇒ 200 | –/401 → Digest✓/200{1024} ⇒ 200 | –/401 → Digest✓/200{1024} ⇒ 200 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-512-256-auth, digest-SHA-512-256-none | wrong | get | http, https, h2 | –/401 → Digest✗/401 ⇒ 401 | –/401 → Digest✗/401 ⇒ 401 | –/401 → Digest✗/401 ⇒ 401 | –/401 → Digest✗/401 ⇒ 401 | –/401 → Digest✗/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-512-256-auth, digest-SHA-512-256-none | wrong | post | http, https, h2 | –/401 → Digest✗/401{1024} ⇒ 401 | –/401 → Digest✗/401{1024} ⇒ 401 | –/401 → Digest✗/401{1024} ⇒ 401 | –/401 → Digest✗/401{1024} ⇒ 401 | –/401 → Digest✗/401{1024} ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | other | get | http, https, h2 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | other | post | http, https, h2 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | none | get | http, https, h2 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | none | post | http, https, h2 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | open | get | http, https, h2 | –/200 ⇒ 200 | –/200 ⇒ 200 | –/200 ⇒ 200 | –/200 ⇒ 200 | –/200 ⇒ 200 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | open | post | http, https, h2 | –/200 → –/200{1024} ⇒ 200 | –/200 → –/200{1024} ⇒ 200 | –/200 → –/200{1024} ⇒ 200 | –/200 → –/200{1024} ⇒ 200 | –/200 → –/200{1024} ⇒ 200 |
| digest-MD5-sess-none, digest-SHA-256-sess-none | right | get | http, https, h2 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 |
| digest-MD5-sess-none, digest-SHA-256-sess-none | right | post | http, https, h2 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 |
| digest-MD5-sess-none, digest-SHA-256-sess-none | wrong | get | http, https, h2 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 |
| digest-MD5-sess-none, digest-SHA-256-sess-none | wrong | post | http, https, h2 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 | –/401 ⇒ 401 |
| digest-SHA-512-256-auth, digest-SHA-512-256-none | right | get | http, https, h2 | –/401 → Digest✗/401 ⇒ 401 | –/401 → Digest✗/401 ⇒ 401 | –/401 → Digest✗/401 ⇒ 401 | –/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/200 ⇒ 200 |
| digest-SHA-512-256-auth, digest-SHA-512-256-none | right | post | http, https, h2 | –/401 → Digest✗/401{1024} ⇒ 401 | –/401 → Digest✗/401{1024} ⇒ 401 | –/401 → Digest✗/401{1024} ⇒ 401 | –/401 → Digest✓/200{1024} ⇒ 200 | –/401 → Digest✓/200{1024} ⇒ 200 |
| bearer | right | get | http, https, h2 | Bearer✓/200 ⇒ 200 | Bearer✓/200 ⇒ 200 | Bearer✓/200 ⇒ 200 | Bearer✓/200 ⇒ 200 | Bearer✓/200 ⇒ 200 |
| bearer | right | post | http, https, h2 | Bearer✓/200{1024} ⇒ 200 | Bearer✓/200{1024} ⇒ 200 | Bearer✓/200{1024} ⇒ 200 | Bearer✓/200{1024} ⇒ 200 | Bearer✓/200{1024} ⇒ 200 |
| bearer | wrong | get | http, https, h2 | Bearer✗/401 ⇒ 401 | Bearer✗/401 ⇒ 401 | Bearer✗/401 ⇒ 401 | Bearer✗/401 ⇒ 401 | Bearer✗/401 ⇒ 401 |
| bearer | wrong | post | http, https, h2 | Bearer✗/401{1024} ⇒ 401 | Bearer✗/401{1024} ⇒ 401 | Bearer✗/401{1024} ⇒ 401 | Bearer✗/401{1024} ⇒ 401 | Bearer✗/401{1024} ⇒ 401 |
| bearer | other | get | http, https, h2 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 |
| bearer | other | post | http, https, h2 | Bearer✓/401{1024} ⇒ 401 | Bearer✓/401{1024} ⇒ 401 | Bearer✓/401{1024} ⇒ 401 | Bearer✓/401{1024} ⇒ 401 | Bearer✓/401{1024} ⇒ 401 |
| bearer | none | get | http, https, h2 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 |
| bearer | none | post | http, https, h2 | Bearer✓/401{1024} ⇒ 401 | Bearer✓/401{1024} ⇒ 401 | Bearer✓/401{1024} ⇒ 401 | Bearer✓/401{1024} ⇒ 401 | Bearer✓/401{1024} ⇒ 401 |
| bearer | open | get | http, https, h2 | Bearer✓/200 ⇒ 200 | Bearer✓/200 ⇒ 200 | Bearer✓/200 ⇒ 200 | Bearer✓/200 ⇒ 200 | Bearer✓/200 ⇒ 200 |
| bearer | open | post | http, https, h2 | Bearer✓/200{1024} ⇒ 200 | Bearer✓/200{1024} ⇒ 200 | Bearer✓/200{1024} ⇒ 200 | Bearer✓/200{1024} ⇒ 200 | Bearer✓/200{1024} ⇒ 200 |

### Item 1: the `Authorization` sent, whole (`i1`, right credentials, get)

A cell: the value of the last request's `Authorization`, as the stand-in received it; for Digest, the nonce, cnonce, response and uri replaced by N, CN, R and U (each verified by the stand-in, `ok` in item 1's table).

| scheme | face | F | O | G | X | C |
|---|---|---|---|---|---|---|
| basic | http, https, h2 | `Basic dXNlcjpwYXNz` | `Basic dXNlcjpwYXNz` | `Basic dXNlcjpwYXNz` | `Basic dXNlcjpwYXNz` | `Basic dXNlcjpwYXNz` |
| digest-MD5-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5` |
| digest-MD5-none | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=MD5` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=MD5` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=MD5` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=MD5` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=MD5` |
| digest-MD5-sess-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5-sess` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5-sess` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5-sess` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5-sess` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5-sess` |
| digest-MD5-sess-none | http, https, h2 | `none` | `none` | `none` | `none` | `none` |
| digest-SHA-256-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256` |
| digest-SHA-256-none | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-256` |
| digest-SHA-256-sess-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256-sess` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256-sess` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256-sess` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256-sess` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256-sess` |
| digest-SHA-256-sess-none | http, https, h2 | `none` | `none` | `none` | `none` | `none` |
| digest-SHA-512-256-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-512-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-512-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-512-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-512-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-512-256` |
| digest-SHA-512-256-none | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-512-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-512-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-512-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-512-256` | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-512-256` |
| bearer | http, https, h2 | `Bearer tok123` | `Bearer tok123` | `Bearer tok123` | `Bearer tok123` | `Bearer tok123` |

- **A ✓ beside a 401** is a request whose credentials match the account, refused because the route
  offers another scheme, or none.
- **Digest's `post`:** the probe goes out with `Content-Length: 0` and no body, on every lane and
  face; the body goes once, with `Authorization`.
- **The open route under Digest:** `get` is one bare request, 200. `post` is two: the probe, answered
  200, then the body on a second request, answered 200 (`schemes20`): libcurl sent the probe
  expecting a 401.
- **SHA-512-256** on 7.85.0 and both 8.5.0s: the stand-in's verdict is `bad(response)`, the response
  SHA-256's under `algorithm=SHA-512-256`, as the auth probe found.
- **The headers whole** agree on all five, but for the nonce, cnonce and response, which are
  random or follow from them, and which the stand-in verified.

## Item 2: streams

Bodies are 256 KiB, put in 16 KiB pieces, each put bounded at 3 s; a streamed response is 256 KiB
read in pieces through a `stream-buffer` of 4096. `when`: `normal`, answered after the body;
`early`, at the head; `mid`, once 64 KiB had arrived. Basic and Bearer run on the prototype as on
main; Digest needs the prototype's `rounds-option-names`.

### Item 2: streams (`i2` lines)

A cell: the outcome; the requests at the stand-in, `{whole}` or `{part}` of the 256 KiB body it read (`closed` when the client closed first); for a streamed body the producer's last put (`end`: every piece taken, then the end; `done`: the transfer had ended; `#f`: its 3 s bound passed), for a streamed response the head the token published and the body bytes read. How much of a body cut short the stand-in read races; the counts are in the next table.

| scheme | case | kind | when | face | F | O | G | X | C |
|---|---|---|---|---|---|---|---|---|---|
| basic | right | sized | normal | http, h2 | 200; Basic✓/200{whole}; last put end | 200; Basic✓/200{whole}; last put end | 200; Basic✓/200{whole}; last put end | 200; Basic✓/200{whole}; last put end | 200; Basic✓/200{whole}; last put end |
| basic | right | chunked | normal | http, h2 | 200; Basic✓/200{whole}; last put end | 200; Basic✓/200{whole}; last put end | 200; Basic✓/200{whole}; last put end | 200; Basic✓/200{whole}; last put end | 200; Basic✓/200{whole}; last put end |
| basic | right | response | normal | http, h2 | 200; Basic✓/200; head 200, read 262144 | 200; Basic✓/200; head 200, read 262144 | 200; Basic✓/200; head 200, read 262144 | 200; Basic✓/200; head 200, read 262144 | 200; Basic✓/200; head 200, read 262144 |
| bearer | right | sized | normal | http, h2 | 200; Bearer✓/200{whole}; last put end | 200; Bearer✓/200{whole}; last put end | 200; Bearer✓/200{whole}; last put end | 200; Bearer✓/200{whole}; last put end | 200; Bearer✓/200{whole}; last put end |
| bearer | right | chunked | normal | http, h2 | 200; Bearer✓/200{whole}; last put end | 200; Bearer✓/200{whole}; last put end | 200; Bearer✓/200{whole}; last put end | 200; Bearer✓/200{whole}; last put end | 200; Bearer✓/200{whole}; last put end |
| bearer | right | response | normal | http, h2 | 200; Bearer✓/200; head 200, read 262144 | 200; Bearer✓/200; head 200, read 262144 | 200; Bearer✓/200; head 200, read 262144 | 200; Bearer✓/200; head 200, read 262144 | 200; Bearer✓/200; head 200, read 262144 |
| basic | wrong | sized | early | http | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done |
| basic | wrong | sized | mid | http | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done |
| basic | wrong | sized | normal | http, h2 | 401; Basic✗/401{whole}; last put end | 401; Basic✗/401{whole}; last put end | 401; Basic✗/401{whole}; last put end | 401; Basic✗/401{whole}; last put end | 401; Basic✗/401{whole}; last put end |
| basic | wrong | chunked | early | http | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done |
| basic | wrong | chunked | mid | http | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done |
| basic | wrong | chunked | normal | http, h2 | 401; Basic✗/401{whole}; last put end | 401; Basic✗/401{whole}; last put end | 401; Basic✗/401{whole}; last put end | 401; Basic✗/401{whole}; last put end | 401; Basic✗/401{whole}; last put end |
| basic | wrong | response | normal | http, h2 | 401; Basic✗/401; head 401, read 11 | 401; Basic✗/401; head 401, read 11 | 401; Basic✗/401; head 401, read 11 | 401; Basic✗/401; head 401, read 11 | 401; Basic✗/401; head 401, read 11 |
| bearer | wrong | sized | early | http | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done |
| bearer | wrong | sized | mid | http | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done |
| bearer | wrong | sized | normal | http, h2 | 401; Bearer✗/401{whole}; last put end | 401; Bearer✗/401{whole}; last put end | 401; Bearer✗/401{whole}; last put end | 401; Bearer✗/401{whole}; last put end | 401; Bearer✗/401{whole}; last put end |
| bearer | wrong | chunked | early | http | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done |
| bearer | wrong | chunked | mid | http | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done |
| bearer | wrong | chunked | normal | http, h2 | 401; Bearer✗/401{whole}; last put end | 401; Bearer✗/401{whole}; last put end | 401; Bearer✗/401{whole}; last put end | 401; Bearer✗/401{whole}; last put end | 401; Bearer✗/401{whole}; last put end |
| bearer | wrong | response | normal | http, h2 | 401; Bearer✗/401; head 401, read 11 | 401; Bearer✗/401; head 401, read 11 | 401; Bearer✗/401; head 401, read 11 | 401; Bearer✗/401; head 401, read 11 | 401; Bearer✗/401; head 401, read 11 |
| basic | wrong | sized | early | h2 | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part}; last put done | 401; Basic✗/401 at head{part}; last put done | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done |
| basic | wrong | sized | mid | h2 | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part}; last put done | 401; Basic✗/401 mid-body{part}; last put done | **401; Basic✗/401 mid-body{part, closed}; last put done / 401; Basic✗/401 mid-body{part, closed}; last put end** | 401; Basic✗/401 mid-body{part, closed}; last put done |
| basic | wrong | chunked | early | h2 | 401; Basic✗/401 at head{part}; last put done | 401; Basic✗/401 at head{part}; last put done | 401; Basic✗/401 at head{part}; last put done | 401; Basic✗/401 at head{part, closed}; last put done | 401; Basic✗/401 at head{part, closed}; last put done |
| basic | wrong | chunked | mid | h2 | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part}; last put done | 401; Basic✗/401 mid-body{part}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done | 401; Basic✗/401 mid-body{part, closed}; last put done |
| bearer | wrong | sized | early | h2 | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part}; last put done | 401; Bearer✗/401 at head{part}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done |
| bearer | wrong | sized | mid | h2 | 401; Bearer✗/401 mid-body{part, closed}; last put done | **401; Bearer✗/401 mid-body{part, closed}; last put done / 401; Bearer✗/401 mid-body{part}; last put done** | 401; Bearer✗/401 mid-body{part}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done |
| bearer | wrong | chunked | early | h2 | 401; Bearer✗/401 at head{part}; last put done | 401; Bearer✗/401 at head{part}; last put done | 401; Bearer✗/401 at head{part}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done | 401; Bearer✗/401 at head{part, closed}; last put done |
| bearer | wrong | chunked | mid | h2 | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part}; last put done | 401; Bearer✗/401 mid-body{part}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done | 401; Bearer✗/401 mid-body{part, closed}; last put done |
| digest | right | sized | normal | http | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end |
| digest | right | sized | early | http | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end |
| digest | wrong | sized | normal | http | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end |
| digest | wrong | sized | early | http | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put end |
| digest | right | chunked | normal | http | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end |
| digest | right | chunked | early | http | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end |
| digest | wrong | chunked | normal | http | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end |
| digest | wrong | chunked | early | http | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done |
| digest | right | response | normal | http, h2 | 200; –/401 → Digest✓/200; head 401, read 262144 | 200; –/401 → Digest✓/200; head 401, read 262144 | 200; –/401 → Digest✓/200; head 401, read 262144 | 200; –/401 → Digest✓/200; head 401, read 262144 | 200; –/401 → Digest✓/200; head 401, read 262144 |
| digest | wrong | response | normal | http, h2 | 401; –/401 → Digest✗/401; head 401, read 11 | 401; –/401 → Digest✗/401; head 401, read 11 | 401; –/401 → Digest✗/401; head 401, read 11 | 401; –/401 → Digest✗/401; head 401, read 11 | 401; –/401 → Digest✗/401; head 401, read 11 |
| digest | right | sized | normal | h2 | fails 28; –/-{part, closed}; last put #f | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end |
| digest | right | sized | early | h2 | 200; –/401 at head{part, closed} → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end |
| digest | wrong | sized | normal | h2 | fails 28; –/-{part, closed}; last put #f | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end |
| digest | wrong | sized | early | h2 | 401; –/401 at head{part, closed} → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part}; last put done | 401; –/401 at head → Digest✗/401 at head{part}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done |
| digest | right | chunked | normal | h2 | fails 28; –/-{part, closed}; last put #f | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end | 200; –/401 → Digest✓/200{whole}; last put end |
| digest | right | chunked | early | h2 | 200; –/401 at head{part, closed} → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end | 200; –/401 at head → Digest✓/200{whole}; last put end |
| digest | wrong | chunked | normal | h2 | fails 28; –/-{part, closed}; last put #f | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end | 401; –/401 → Digest✗/401{whole}; last put end |
| digest | wrong | chunked | early | h2 | 401; –/401 at head{part, closed} → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part}; last put done | 401; –/401 at head → Digest✗/401 at head{part}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done |

### Item 2: times and bytes, run 1; run 2 (not compared)

A cell: ms from the submit to the end; for a streamed body the bytes the puts committed (`curl-token-body-count`); the bytes the stand-in read per request.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| basic | right | sized | normal | http | 10.1 ms, put 262144, got 262144; 7.0 ms, put 262144, got 262144 | 6.8 ms, put 262144, got 262144; 9.9 ms, put 262144, got 262144 | 11.6 ms, put 262144, got 262144; 11.8 ms, put 262144, got 262144 | 9.9 ms, put 262144, got 262144; 9.3 ms, put 262144, got 262144 | 12.5 ms, put 262144, got 262144; 10.4 ms, put 262144, got 262144 |
| basic | right | chunked | normal | http | 6.7 ms, put 262144, got 262144; 7.7 ms, put 262144, got 262144 | 7.7 ms, put 262144, got 262144; 5.8 ms, put 262144, got 262144 | 6.6 ms, put 262144, got 262144; 8.1 ms, put 262144, got 262144 | 17.0 ms, put 262144, got 262144; 9.2 ms, put 262144, got 262144 | 7.3 ms, put 262144, got 262144; 6.8 ms, put 262144, got 262144 |
| basic | right | response | normal | http | 3.9 ms, got 0; 3.8 ms, got 0 | 16.8 ms, got 0; 17.9 ms, got 0 | 18.3 ms, got 0; 18.9 ms, got 0 | 2.9 ms, got 0; 2.9 ms, got 0 | 2.9 ms, got 0; 4.5 ms, got 0 |
| bearer | right | sized | normal | http | 7.6 ms, put 262144, got 262144; 7.6 ms, put 262144, got 262144 | 7.4 ms, put 262144, got 262144; 7.5 ms, put 262144, got 262144 | 8.0 ms, put 262144, got 262144; 7.4 ms, put 262144, got 262144 | 6.5 ms, put 262144, got 262144; 7.4 ms, put 262144, got 262144 | 6.5 ms, put 262144, got 262144; 7.5 ms, put 262144, got 262144 |
| bearer | right | chunked | normal | http | 7.6 ms, put 262144, got 262144; 7.6 ms, put 262144, got 262144 | 7.5 ms, put 262144, got 262144; 7.4 ms, put 262144, got 262144 | 7.6 ms, put 262144, got 262144; 7.6 ms, put 262144, got 262144 | 6.4 ms, put 262144, got 262144; 7.4 ms, put 262144, got 262144 | 8.3 ms, put 262144, got 262144; 6.5 ms, put 262144, got 262144 |
| bearer | right | response | normal | http | 3.8 ms, got 0; 3.8 ms, got 0 | 20.1 ms, got 0; 16.7 ms, got 0 | 17.7 ms, got 0; 17.9 ms, got 0 | 2.9 ms, got 0; 4.5 ms, got 0 | 3.4 ms, got 0; 3.2 ms, got 0 |
| basic | right | sized | normal | h2 | 8.8 ms, put 262144, got 262144; 9.2 ms, put 262144, got 262144 | 10.4 ms, put 262144, got 262144; 8.0 ms, put 262144, got 262144 | 10.3 ms, put 262144, got 262144; 8.6 ms, put 262144, got 262144 | 8.3 ms, put 262144, got 262144; 10.0 ms, put 262144, got 262144 | 12.6 ms, put 262144, got 262144; 9.4 ms, put 262144, got 262144 |
| basic | right | chunked | normal | h2 | 4.6 ms, put 262144, got 262144; 4.4 ms, put 262144, got 262144 | 6.3 ms, put 262144, got 262144; 6.7 ms, put 262144, got 262144 | 7.2 ms, put 262144, got 262144; 6.7 ms, put 262144, got 262144 | 7.5 ms, put 262144, got 262144; 8.3 ms, put 262144, got 262144 | 8.0 ms, put 262144, got 262144; 8.6 ms, put 262144, got 262144 |
| basic | right | response | normal | h2 | 6.5 ms, got 0; 6.5 ms, got 0 | 18.2 ms, got 0; 27.4 ms, got 0 | 24.9 ms, got 0; 28.4 ms, got 0 | 28.5 ms, got 0; 31.4 ms, got 0 | 27.1 ms, got 0; 33.3 ms, got 0 |
| bearer | right | sized | normal | h2 | 7.7 ms, put 262144, got 262144; 7.7 ms, put 262144, got 262144 | 4.6 ms, put 262144, got 262144; 7.2 ms, put 262144, got 262144 | 4.8 ms, put 262144, got 262144; 11.4 ms, put 262144, got 262144 | 13.8 ms, put 262144, got 262144; 8.3 ms, put 262144, got 262144 | 7.7 ms, put 262144, got 262144; 8.8 ms, put 262144, got 262144 |
| bearer | right | chunked | normal | h2 | 4.1 ms, put 262144, got 262144; 11.0 ms, put 262144, got 262144 | 6.3 ms, put 262144, got 262144; 10.0 ms, put 262144, got 262144 | 3.9 ms, put 262144, got 262144; 17.6 ms, put 262144, got 262144 | 8.5 ms, put 262144, got 262144; 10.0 ms, put 262144, got 262144 | 8.5 ms, put 262144, got 262144; 6.0 ms, put 262144, got 262144 |
| bearer | right | response | normal | h2 | 6.5 ms, got 0; 6.5 ms, got 0 | 32.2 ms, got 0; 27.1 ms, got 0 | 26.6 ms, got 0; 25.0 ms, got 0 | 23.5 ms, got 0; 32.6 ms, got 0 | 24.3 ms, got 0; 31.6 ms, got 0 |
| basic | wrong | sized | early | http | 1.3 ms, put 81920, got 16384(closed); 1.7 ms, put 114688, got 49152(closed) | 2.0 ms, put 98304, got 32768(closed); 2.0 ms, put 114688, got 49152(closed) | 1.6 ms, put 114688, got 49152(closed); 1.7 ms, put 81920, got 16384(closed) | 2.1 ms, put 114688, got 49152(closed); 1.5 ms, put 98304, got 32768(closed) | 2.1 ms, put 98304, got 32768(closed); 1.8 ms, put 98304, got 32768(closed) |
| basic | wrong | sized | mid | http | 2.6 ms, put 147456, got 81920(closed); 2.7 ms, put 147456, got 81920(closed) | 2.9 ms, put 131072, got 65536(closed); 1.7 ms, put 131072, got 65536(closed) | 3.0 ms, put 180224, got 114688(closed); 3.0 ms, put 147456, got 81920(closed) | 3.3 ms, put 163840, got 98304(closed); 2.9 ms, put 163840, got 98304(closed) | 3.2 ms, put 163840, got 98304(closed); 2.1 ms, put 147456, got 81920(closed) |
| basic | wrong | sized | normal | http | 6.6 ms, put 262144, got 262144; 6.2 ms, put 262144, got 262144 | 5.1 ms, put 262144, got 262144; 5.0 ms, put 262144, got 262144 | 5.8 ms, put 262144, got 262144; 6.9 ms, put 262144, got 262144 | 6.9 ms, put 262144, got 262144; 5.7 ms, put 262144, got 262144 | 6.4 ms, put 262144, got 262144; 5.0 ms, put 262144, got 262144 |
| basic | wrong | chunked | early | http | 1.5 ms, put 131072, got 65536(closed); 1.6 ms, put 81920, got 16384(closed) | 1.5 ms, put 114688, got 49152(closed); 1.5 ms, put 114688, got 49152(closed) | 1.4 ms, put 98304, got 32768(closed); 1.8 ms, put 81920, got 16384(closed) | 2.0 ms, put 98304, got 32768(closed); 1.4 ms, put 98304, got 32768(closed) | 1.8 ms, put 114688, got 49152(closed); 1.5 ms, put 114688, got 49152(closed) |
| basic | wrong | chunked | mid | http | 2.8 ms, put 147456, got 81920(closed); 2.8 ms, put 147456, got 81920(closed) | 3.1 ms, put 163840, got 98304(closed); 2.6 ms, put 163840, got 98304(closed) | 2.6 ms, put 147456, got 81920(closed); 3.3 ms, put 147456, got 81920(closed) | 3.2 ms, put 163840, got 98304(closed); 2.7 ms, put 163840, got 98304(closed) | 3.0 ms, put 229376, got 163840(closed); 1.6 ms, put 131072, got 65536(closed) |
| basic | wrong | chunked | normal | http | 6.2 ms, put 262144, got 262144; 6.0 ms, put 262144, got 262144 | 6.7 ms, put 262144, got 262144; 6.0 ms, put 262144, got 262144 | 5.8 ms, put 262144, got 262144; 6.8 ms, put 262144, got 262144 | 5.1 ms, put 262144, got 262144; 5.8 ms, put 262144, got 262144 | 4.8 ms, put 262144, got 262144; 5.8 ms, put 262144, got 262144 |
| basic | wrong | response | normal | http | 0.7 ms, got 0; 0.3 ms, got 0 | 0.6 ms, got 0; 0.6 ms, got 0 | 1.0 ms, got 0; 0.6 ms, got 0 | 0.5 ms, got 0; 0.5 ms, got 0 | 0.5 ms, got 0; 0.5 ms, got 0 |
| bearer | wrong | sized | early | http | 1.9 ms, put 81920, got 16384(closed); 1.5 ms, put 81920, got 16384(closed) | 1.8 ms, put 81920, got 16384(closed); 1.9 ms, put 81920, got 16384(closed) | 1.4 ms, put 81920, got 16384(closed); 1.8 ms, put 81920, got 16384(closed) | 1.6 ms, put 147456, got 81920(closed); 1.9 ms, put 180224, got 114688(closed) | 1.5 ms, put 114688, got 49152(closed); 1.7 ms, put 131072, got 65536(closed) |
| bearer | wrong | sized | mid | http | 3.1 ms, put 163840, got 98304(closed); 2.7 ms, put 147456, got 81920(closed) | 3.3 ms, put 147456, got 81920(closed); 3.2 ms, put 147456, got 81920(closed) | 2.7 ms, put 163840, got 98304(closed); 3.3 ms, put 147456, got 81920(closed) | 2.7 ms, put 180224, got 114688(closed); 3.5 ms, put 180224, got 114688(closed) | 2.7 ms, put 180224, got 114688(closed); 4.1 ms, put 245760, got 180224(closed) |
| bearer | wrong | sized | normal | http | 6.3 ms, put 262144, got 262144; 5.9 ms, put 262144, got 262144 | 7.3 ms, put 262144, got 262144; 4.9 ms, put 262144, got 262144 | 5.8 ms, put 262144, got 262144; 6.9 ms, put 262144, got 262144 | 4.7 ms, put 262144, got 262144; 6.0 ms, put 262144, got 262144 | 5.7 ms, put 262144, got 262144; 4.8 ms, put 262144, got 262144 |
| bearer | wrong | chunked | early | http | 1.9 ms, put 81920, got 16384(closed); 1.5 ms, put 81920, got 16384(closed) | 1.9 ms, put 81920, got 16384(closed); 1.9 ms, put 81920, got 16384(closed) | 1.4 ms, put 81920, got 16384(closed); 1.6 ms, put 65536, got 0(closed) | 1.4 ms, put 114688, got 49152(closed); 1.5 ms, put 131072, got 65536(closed) | 2.0 ms, put 98304, got 32768(closed); 1.5 ms, put 114688, got 49152(closed) |
| bearer | wrong | chunked | mid | http | 3.4 ms, put 147456, got 81920(closed); 2.6 ms, put 147456, got 81920(closed) | 3.3 ms, put 147456, got 81920(closed); 3.1 ms, put 163840, got 98304(closed) | 2.9 ms, put 163840, got 98304(closed); 2.7 ms, put 180224, got 114688(closed) | 2.6 ms, put 163840, got 98304(closed); 2.7 ms, put 180224, got 114688(closed) | 2.7 ms, put 180224, got 114688(closed); 1.6 ms, put 147456, got 81920(closed) |
| bearer | wrong | chunked | normal | http | 6.4 ms, put 262144, got 262144; 5.8 ms, put 262144, got 262144 | 6.9 ms, put 262144, got 262144; 4.9 ms, put 262144, got 262144 | 6.0 ms, put 262144, got 262144; 6.1 ms, put 262144, got 262144 | 4.7 ms, put 262144, got 262144; 5.7 ms, put 262144, got 262144 | 4.8 ms, put 262144, got 262144; 4.8 ms, put 262144, got 262144 |
| bearer | wrong | response | normal | http | 6.7 ms, got 0; 0.6 ms, got 0 | 0.6 ms, got 0; 0.6 ms, got 0 | 1.1 ms, got 0; 0.3 ms, got 0 | 0.6 ms, got 0; 1.0 ms, got 0 | 4.3 ms, got 0; 0.5 ms, got 0 |
| basic | wrong | sized | early | h2 | 3.4 ms, put 131072, got 65535(closed); 4.6 ms, put 196608, got 65535(closed) | 8.2 ms, put 131072, got 65536; 8.5 ms, put 131072, got 65536 | 7.9 ms, put 65536, got 65535; 6.4 ms, put 65536, got 65535 | 3.3 ms, put 131072, got 65535(closed); 4.2 ms, put 131072, got 65535(closed) | 3.8 ms, put 65536, got 65535(closed); 3.6 ms, put 196608, got 65535(closed) |
| basic | wrong | sized | mid | h2 | 3.4 ms, put 131072, got 131070(closed); 4.8 ms, put 196608, got 131070(closed) | 4.4 ms, put 180224, got 114688; 2.8 ms, put 163840, got 131070 | 2.8 ms, put 147456, got 131070; 3.2 ms, put 147456, got 131070 | 4.7 ms, put 114688, got 65536(closed); 5.3 ms, put 262144, got 131070(closed) | 3.9 ms, put 212992, got 131070(closed); 4.2 ms, put 147456, got 131070(closed) |
| basic | wrong | sized | normal | h2 | 3.0 ms, put 262144, got 262144; 6.7 ms, put 262144, got 262144 | 7.7 ms, put 262144, got 262144; 3.4 ms, put 262144, got 262144 | 6.2 ms, put 262144, got 262144; 7.5 ms, put 262144, got 262144 | 7.5 ms, put 262144, got 262144; 7.0 ms, put 262144, got 262144 | 5.8 ms, put 262144, got 262144; 5.8 ms, put 262144, got 262144 |
| basic | wrong | chunked | early | h2 | 5.0 ms, put 131072, got 65535; 5.9 ms, put 131072, got 65535 | 3.0 ms, put 114688, got 65536; 1.7 ms, put 131072, got 65536 | 2.4 ms, put 81920, got 65535; 2.8 ms, put 98304, got 65535 | 3.5 ms, put 131072, got 65535(closed); 3.6 ms, put 131072, got 65535(closed) | 3.5 ms, put 163840, got 65535(closed); 3.4 ms, put 131072, got 65535(closed) |
| basic | wrong | chunked | mid | h2 | 2.7 ms, put 163840, got 131070(closed); 4.9 ms, put 196608, got 131070(closed) | 3.6 ms, put 163840, got 131070; 5.6 ms, put 196608, got 131070 | 2.7 ms, put 196608, got 131070; 4.2 ms, put 131072, got 65536 | 3.9 ms, put 163840, got 131070(closed); 4.8 ms, put 196608, got 131070(closed) | 5.1 ms, put 196608, got 131070(closed); 3.8 ms, put 212992, got 131070(closed) |
| basic | wrong | chunked | normal | h2 | 3.4 ms, put 262144, got 262144; 6.7 ms, put 262144, got 262144 | 6.9 ms, put 262144, got 262144; 6.9 ms, put 262144, got 262144 | 5.0 ms, put 262144, got 262144; 7.2 ms, put 262144, got 262144 | 7.1 ms, put 262144, got 262144; 7.2 ms, put 262144, got 262144 | 7.3 ms, put 262144, got 262144; 6.9 ms, put 262144, got 262144 |
| basic | wrong | response | normal | h2 | 1.8 ms, got 0; 1.9 ms, got 0 | 3.6 ms, got 0; 3.5 ms, got 0 | 3.5 ms, got 0; 3.5 ms, got 0 | 3.6 ms, got 0; 3.6 ms, got 0 | 3.5 ms, got 0; 3.5 ms, got 0 |
| bearer | wrong | sized | early | h2 | 2.5 ms, put 131072, got 65535(closed); 2.6 ms, put 131072, got 65535(closed) | 3.1 ms, put 98304, got 65535; 2.1 ms, put 131072, got 65536 | 2.3 ms, put 65536, got 65535; 2.4 ms, put 98304, got 65535 | 3.4 ms, put 147456, got 65535(closed); 3.6 ms, put 131072, got 65535(closed) | 3.3 ms, put 131072, got 65535(closed); 3.3 ms, put 131072, got 65535(closed) |
| bearer | wrong | sized | mid | h2 | 2.6 ms, put 147456, got 131070(closed); 4.1 ms, put 131072, got 131070(closed) | 4.6 ms, put 81920, got 65536(closed); 2.8 ms, put 196608, got 131070 | 3.4 ms, put 131072, got 65536; 3.4 ms, put 147456, got 81920 | 5.0 ms, put 131072, got 65536(closed); 5.0 ms, put 196608, got 131070(closed) | 4.2 ms, put 196608, got 131070(closed); 4.4 ms, put 196608, got 131070(closed) |
| bearer | wrong | sized | normal | h2 | 4.9 ms, put 262144, got 262144; 7.5 ms, put 262144, got 262144 | 7.1 ms, put 262144, got 262144; 6.4 ms, put 262144, got 262144 | 5.1 ms, put 262144, got 262144; 4.8 ms, put 262144, got 262144 | 5.6 ms, put 262144, got 262144; 8.8 ms, put 262144, got 262144 | 5.1 ms, put 262144, got 262144; 6.6 ms, put 262144, got 262144 |
| bearer | wrong | chunked | early | h2 | 1.8 ms, put 147456, got 65535; 1.9 ms, put 114688, got 65535 | 3.7 ms, put 131072, got 65536; 2.5 ms, put 65536, got 65535 | 3.8 ms, put 65536, got 65535; 2.2 ms, put 65536, got 65535 | 3.3 ms, put 131072, got 65535(closed); 3.5 ms, put 131072, got 65535(closed) | 3.3 ms, put 131072, got 65535(closed); 3.4 ms, put 131072, got 65535(closed) |
| bearer | wrong | chunked | mid | h2 | 2.6 ms, put 147456, got 131070(closed); 2.7 ms, put 147456, got 131070(closed) | 3.5 ms, put 131072, got 114688; 4.0 ms, put 131072, got 65536 | 3.5 ms, put 131072, got 65536; 3.4 ms, put 147456, got 81920 | 5.2 ms, put 180224, got 114688(closed); 4.5 ms, put 196608, got 131070(closed) | 4.7 ms, put 196608, got 131070(closed); 3.7 ms, put 163840, got 131070(closed) |
| bearer | wrong | chunked | normal | h2 | 4.4 ms, put 262144, got 262144; 5.9 ms, put 262144, got 262144 | 9.2 ms, put 262144, got 262144; 5.2 ms, put 262144, got 262144 | 3.0 ms, put 262144, got 262144; 5.4 ms, put 262144, got 262144 | 7.4 ms, put 262144, got 262144; 7.3 ms, put 262144, got 262144 | 4.1 ms, put 262144, got 262144; 5.9 ms, put 262144, got 262144 |
| bearer | wrong | response | normal | h2 | 1.8 ms, got 0; 1.8 ms, got 0 | 3.7 ms, got 0; 3.6 ms, got 0 | 1.8 ms, got 0; 3.5 ms, got 0 | 3.5 ms, got 0; 6.7 ms, got 0 | 3.5 ms, got 0; 3.5 ms, got 0 |
| digest | right | sized | normal | http | 4.8 ms, put 262144, got 0+262144; 6.6 ms, put 262144, got 0+262144 | 7.0 ms, put 262144, got 0+262144; 8.4 ms, put 262144, got 0+262144 | 6.5 ms, put 262144, got 0+262144; 10.7 ms, put 262144, got 0+262144 | 7.7 ms, put 262144, got 0+262144; 6.9 ms, put 262144, got 0+262144 | 7.1 ms, put 262144, got 0+262144; 7.4 ms, put 262144, got 0+262144 |
| digest | right | sized | early | http | 5.7 ms, put 262144, got 0+262144; 10.4 ms, put 262144, got 0+262144 | 5.5 ms, put 262144, got 0+262144; 6.8 ms, put 262144, got 0+262144 | 7.0 ms, put 262144, got 0+262144; 7.0 ms, put 262144, got 0+262144 | 6.9 ms, put 262144, got 0+262144; 6.7 ms, put 262144, got 0+262144 | 7.0 ms, put 262144, got 0+262144; 6.8 ms, put 262144, got 0+262144 |
| digest | wrong | sized | normal | http | 5.3 ms, put 262144, got 0+262144; 7.5 ms, put 262144, got 0+262144 | 5.3 ms, put 262144, got 0+262144; 6.9 ms, put 262144, got 0+262144 | 10.1 ms, put 262144, got 0+262144; 7.0 ms, put 262144, got 0+262144 | 6.9 ms, put 262144, got 0+262144; 6.6 ms, put 262144, got 0+262144 | 10.0 ms, put 262144, got 0+262144; 9.8 ms, put 262144, got 0+262144 |
| digest | wrong | sized | early | http | 2.1 ms, put 131072, got 0+65536(closed); 3.6 ms, put 212992, got 0+147456(closed) | 3.7 ms, put 196608, got 0+131072(closed); 3.5 ms, put 212992, got 0+147456(closed) | 3.4 ms, put 196608, got 0+131072(closed); 3.1 ms, put 196608, got 0+131072(closed) | 3.1 ms, put 196608, got 0+131072(closed); 3.3 ms, put 196608, got 0+131072(closed) | 5.0 ms, put 262144, got 0+196608(closed); 4.6 ms, put 262144, got 0+212992(closed) |
| digest | right | chunked | normal | http | 6.9 ms, put 262144, got 0+262144; 6.9 ms, put 262144, got 0+262144 | 6.9 ms, put 262144, got 0+262144; 6.7 ms, put 262144, got 0+262144 | 7.4 ms, put 262144, got 0+262144; 6.7 ms, put 262144, got 0+262144 | 6.5 ms, put 262144, got 0+262144; 6.5 ms, put 262144, got 0+262144 | 7.0 ms, put 262144, got 0+262144; 6.8 ms, put 262144, got 0+262144 |
| digest | right | chunked | early | http | 5.3 ms, put 262144, got 0+262144; 6.9 ms, put 262144, got 0+262144 | 6.9 ms, put 262144, got 0+262144; 6.9 ms, put 262144, got 0+262144 | 5.3 ms, put 262144, got 0+262144; 6.7 ms, put 262144, got 0+262144 | 7.1 ms, put 262144, got 0+262144; 4.9 ms, put 262144, got 0+262144 | 5.5 ms, put 262144, got 0+262144; 6.7 ms, put 262144, got 0+262144 |
| digest | wrong | chunked | normal | http | 7.5 ms, put 262144, got 0+262144; 6.9 ms, put 262144, got 0+262144 | 5.7 ms, put 262144, got 0+262144; 7.0 ms, put 262144, got 0+262144 | 6.8 ms, put 262144, got 0+262144; 6.7 ms, put 262144, got 0+262144 | 6.5 ms, put 262144, got 0+262144; 6.5 ms, put 262144, got 0+262144 | 6.7 ms, put 262144, got 0+262144; 5.6 ms, put 262144, got 0+262144 |
| digest | wrong | chunked | early | http | 3.6 ms, put 212992, got 0+147456(closed); 3.4 ms, put 196608, got 0+131072(closed) | 3.3 ms, put 196608, got 0+131072(closed); 3.0 ms, put 212992, got 0+147456(closed) | 3.5 ms, put 212992, got 0+147456(closed); 3.0 ms, put 196608, got 0+131072(closed) | 3.0 ms, put 212992, got 0+147456(closed); 1.7 ms, put 147456, got 0+81920(closed) | 1.9 ms, put 147456, got 0+81920(closed); 3.3 ms, put 196608, got 0+131072(closed) |
| digest | right | response | normal | http | 5.7 ms, got 0+0; 4.9 ms, got 0+0 | 19.7 ms, got 0+0; 16.6 ms, got 0+0 | 19.2 ms, got 0+0; 19.5 ms, got 0+0 | 4.6 ms, got 0+0; 2.1 ms, got 0+0 | 3.8 ms, got 0+0; 2.5 ms, got 0+0 |
| digest | wrong | response | normal | http | 4.0 ms, got 0+0; 2.4 ms, got 0+0 | 2.4 ms, got 0+0; 2.4 ms, got 0+0 | 2.9 ms, got 0+0; 2.4 ms, got 0+0 | 3.6 ms, got 0+0; 2.3 ms, got 0+0 | 2.3 ms, got 0+0; 2.8 ms, got 0+0 |
| digest | right | sized | normal | h2 | 10005.0 ms, put 65536, got 0(closed); 10009.1 ms, put 65536, got 0(closed) | 10.4 ms, put 262144, got 0+262144; 10.3 ms, put 262144, got 0+262144 | 10.4 ms, put 262144, got 0+262144; 8.4 ms, put 262144, got 0+262144 | 8.8 ms, put 262144, got 0+262144; 9.6 ms, put 262144, got 0+262144 | 10.0 ms, put 262144, got 0+262144; 10.4 ms, put 262144, got 0+262144 |
| digest | right | sized | early | h2 | 17.0 ms, put 262144, got 0(closed)+262144; 15.7 ms, put 262144, got 0(closed)+262144 | 10.3 ms, put 262144, got 0+262144; 6.9 ms, put 262144, got 0+262144 | 12.3 ms, put 262144, got 0+262144; 10.2 ms, put 262144, got 0+262144 | 9.4 ms, put 262144, got 0+262144; 10.1 ms, put 262144, got 0+262144 | 8.6 ms, put 262144, got 0+262144; 10.0 ms, put 262144, got 0+262144 |
| digest | wrong | sized | normal | h2 | 10004.4 ms, put 65536, got 0(closed); 10009.0 ms, put 65536, got 0(closed) | 10.6 ms, put 262144, got 0+262144; 5.7 ms, put 262144, got 0+262144 | 8.8 ms, put 262144, got 0+262144; 6.4 ms, put 262144, got 0+262144 | 9.9 ms, put 262144, got 0+262144; 10.6 ms, put 262144, got 0+262144 | 6.7 ms, put 262144, got 0+262144; 7.8 ms, put 262144, got 0+262144 |
| digest | wrong | sized | early | h2 | 9.5 ms, put 81920, got 0(closed)+65535(closed); 7.7 ms, put 131072, got 0(closed)+65535(closed) | 4.3 ms, put 81920, got 0+65535; 5.2 ms, put 131072, got 0+65535 | 4.5 ms, put 114688, got 0+65535; 4.3 ms, put 131072, got 0+65535 | 5.2 ms, put 131072, got 0+65535(closed); 4.4 ms, put 81920, got 0+65535(closed) | 5.1 ms, put 131072, got 0+65535(closed); 4.6 ms, put 212992, got 0+65535(closed) |
| digest | right | chunked | normal | h2 | 10009.4 ms, put 65536, got 0(closed); 10009.2 ms, put 65536, got 0(closed) | 10.3 ms, put 262144, got 0+262144; 8.4 ms, put 262144, got 0+262144 | 8.3 ms, put 262144, got 0+262144; 8.5 ms, put 262144, got 0+262144 | 8.0 ms, put 262144, got 0+262144; 9.7 ms, put 262144, got 0+262144 | 9.6 ms, put 262144, got 0+262144; 9.6 ms, put 262144, got 0+262144 |
| digest | right | chunked | early | h2 | 9.1 ms, put 262144, got 0(closed)+262144; 13.4 ms, put 262144, got 0(closed)+262144 | 7.7 ms, put 262144, got 0+262144; 14.2 ms, put 262144, got 0+262144 | 8.8 ms, put 262144, got 0+262144; 6.4 ms, put 262144, got 0+262144 | 8.9 ms, put 262144, got 0+262144; 9.0 ms, put 262144, got 0+262144 | 10.0 ms, put 262144, got 0+262144; 9.2 ms, put 262144, got 0+262144 |
| digest | wrong | chunked | normal | h2 | 10006.4 ms, put 65536, got 0(closed); 10011.7 ms, put 65536, got 0(closed) | 10.2 ms, put 262144, got 0+262144; 6.4 ms, put 262144, got 0+262144 | 16.2 ms, put 262144, got 0+262144; 11.0 ms, put 262144, got 0+262144 | 10.3 ms, put 262144, got 0+262144; 9.1 ms, put 262144, got 0+262144 | 6.9 ms, put 262144, got 0+262144; 9.2 ms, put 262144, got 0+262144 |
| digest | wrong | chunked | early | h2 | 9.2 ms, put 131072, got 0(closed)+65535(closed); 5.8 ms, put 131072, got 0(closed)+65535(closed) | 3.7 ms, put 131072, got 0+65535; 3.8 ms, put 65536, got 0+65535 | 5.8 ms, put 131072, got 0+65535; 5.0 ms, put 131072, got 0+65535 | 6.0 ms, put 196608, got 0+65535(closed); 7.4 ms, put 65536, got 0+65535(closed) | 7.6 ms, put 65536, got 0+65535(closed); 4.9 ms, put 212992, got 0+65535(closed) |
| digest | right | response | normal | h2 | 10.8 ms, got 0+0; 10.4 ms, got 0+0 | 23.8 ms, got 0+0; 27.0 ms, got 0+0 | 24.5 ms, got 0+0; 27.4 ms, got 0+0 | 26.7 ms, got 0+0; 24.5 ms, got 0+0 | 23.6 ms, got 0+0; 24.5 ms, got 0+0 |
| digest | wrong | response | normal | h2 | 4.5 ms, got 0+0; 3.6 ms, got 0+0 | 5.3 ms, got 0+0; 5.3 ms, got 0+0 | 4.5 ms, got 0+0; 5.3 ms, got 0+0 | 3.7 ms, got 0+0; 3.6 ms, got 0+0 | 4.6 ms, got 0+0; 5.4 ms, got 0+0 |

- **A wrong password beside a streamed body** ends with the 401 and code 0 on every lane, within
  10 ms of the submit (the times table); the producer's last put answers `done`, and libcurl had
  taken part of the body, as `curl-token-body-count` shows. The C probe's 100 ms on 7.85.0 and
  8.5.0 came from its paused read callback; here the producer puts without pause.
- **Over `h2` the stand-in read 65,535 or 65,536 bytes** of a body answered at its head, the stream's
  window: libcurl had sent no more.
- **Digest beside a streamed body** sends the bare probe, no body, then the body once, 200 or 401,
  on every lane over `http`, and over `h2` on 8.5.0 and later. On 7.85.0 over `h2`, when the stand-in
  waits for the probe's end, the probe is never ended: one request at the stand-in, closed with no
  answer, and the transfer fails 28 at its 10 s timeout, the producer's first put timing out
  (`streams51`, F). Answered at its head, the probe passes there too. This is the C probe's hang,
  through the engine.
- **Digest beside a streamed response** on the prototype: the token's head is the probe's 401,
  while the transfer ends 200 and the 200's 256 KiB body arrives through the same stream, its
  pattern intact (`streams49`, every lane, both faces). Main refuses this pairing as
  `stream-with-rounds`.

## Item 3: empty values

### Item 3: empty values (`i3` lines)

A cell: each request's credentials as the stand-in decoded them; then the requests in order, as in item 1; ⇒ the final status or code.

| scheme | user | pass | token | face | F | O | G | X | C |
|---|---|---|---|---|---|---|---|---|---|
| basic | empty | empty | tok | http, h2 | Basic ":"; Basic✓/200 ⇒ 200 | Basic ":"; Basic✓/200 ⇒ 200 | Basic ":"; Basic✓/200 ⇒ 200 | Basic ":"; Basic✓/200 ⇒ 200 | –; –/401 ⇒ 401 |
| basic | user | empty | tok | http, h2 | Basic "user:"; Basic✓/200 ⇒ 200 | Basic "user:"; Basic✓/200 ⇒ 200 | Basic "user:"; Basic✓/200 ⇒ 200 | Basic "user:"; Basic✓/200 ⇒ 200 | Basic "user:"; Basic✓/200 ⇒ 200 |
| basic | empty | pass | tok | http, h2 | Basic ":pass"; Basic✓/200 ⇒ 200 | Basic ":pass"; Basic✓/200 ⇒ 200 | Basic ":pass"; Basic✓/200 ⇒ 200 | Basic ":pass"; Basic✓/200 ⇒ 200 | Basic ":pass"; Basic✓/200 ⇒ 200 |
| digest | empty | empty | tok | http, h2 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 | –; –/401 ⇒ 401 |
| digest | user | empty | tok | http, h2 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| digest | empty | pass | tok | http, h2 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 |
| bearer | user | pass | empty | http | Bearer ""; Bearer✓/200 ⇒ 200 | Bearer ""; Bearer✓/200 ⇒ 200 | Bearer ""; Bearer✓/200 ⇒ 200 | Bearer ""; Bearer✓/200 ⇒ 200 | –; –/401 ⇒ 401 |
| bearer | user | pass | empty | h2 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 |

- **8.23.0** sends no `Authorization` when both the user and the password are empty, under Basic and
  Digest, and none for an empty token; it ends 401 after one request (`empty1`). The other four
  send Basic `Og==`, a Digest `username=""` whose response verifies, and `Bearer ` with nothing
  after it.
- **Over `h2`,** no lane's empty token reached the stand-in. Over HTTP/1.1 four lanes send
  `Bearer ` with a space after it, and a field value ending in whitespace is invalid in HTTP/2
  (RFC 9113, section 8.2.1), so the stand-in's HTTP/2 stack would drop it; that is an inference,
  not traced. 8.23.0 sent none over either.

## Item 4: hostile and edge bytes

Each case sets the user, the password or the token to `a`, the byte(s), `b`, by the prototype's
seam, under each scheme the field reaches; `x` is the neighbour that passes, `crlf-header` is
`\r\nX-Injected: 1`, and `utf8-string` is the user `üser` as a string, the hatch's own path. The
account the stand-in checks holds the same bytes.

### Item 4: hostile and edge bytes, `a` BYTE `b` (`i4` lines)

A cell: what the stand-in received, escaped as `\xNN` (for Digest the `username` parameter, unquoted, and any `username*`); the verdict, the stand-in's own arithmetic on the bytes set (`valid`, `refused`, or Digest's `bad(...)` list); `+header N` for a header name no request otherwise carries, a header of its own; `bare CR or LF in head`; ⇒ the final status or code; `no request reached the stand-in` when none did, and `nothing sent` when the failure's request size is 0.

| field | scheme | byte | face | F | O | G | X | C |
|---|---|---|---|---|---|---|---|---|
| user | basic | x | http, h2 | Basic "axb:pass"; valid ⇒ 200 | Basic "axb:pass"; valid ⇒ 200 | Basic "axb:pass"; valid ⇒ 200 | Basic "axb:pass"; valid ⇒ 200 | Basic "axb:pass"; valid ⇒ 200 |
| user | basic | 01 | http, h2 | Basic "a\x01b:pass"; valid ⇒ 200 | Basic "a\x01b:pass"; valid ⇒ 200 | Basic "a\x01b:pass"; valid ⇒ 200 | Basic "a\x01b:pass"; valid ⇒ 200 | Basic "a\x01b:pass"; valid ⇒ 200 |
| user | basic | tab | http, h2 | Basic "a\x09b:pass"; valid ⇒ 200 | Basic "a\x09b:pass"; valid ⇒ 200 | Basic "a\x09b:pass"; valid ⇒ 200 | Basic "a\x09b:pass"; valid ⇒ 200 | Basic "a\x09b:pass"; valid ⇒ 200 |
| user | basic | lf | http, h2 | Basic "a\x0ab:pass"; valid ⇒ 200 | Basic "a\x0ab:pass"; valid ⇒ 200 | Basic "a\x0ab:pass"; valid ⇒ 200 | Basic "a\x0ab:pass"; valid ⇒ 200 | Basic "a\x0ab:pass"; valid ⇒ 200 |
| user | basic | cr | http, h2 | Basic "a\x0db:pass"; valid ⇒ 200 | Basic "a\x0db:pass"; valid ⇒ 200 | Basic "a\x0db:pass"; valid ⇒ 200 | Basic "a\x0db:pass"; valid ⇒ 200 | Basic "a\x0db:pass"; valid ⇒ 200 |
| user | basic | 1f | http, h2 | Basic "a\x1fb:pass"; valid ⇒ 200 | Basic "a\x1fb:pass"; valid ⇒ 200 | Basic "a\x1fb:pass"; valid ⇒ 200 | Basic "a\x1fb:pass"; valid ⇒ 200 | Basic "a\x1fb:pass"; valid ⇒ 200 |
| user | basic | sp | http, h2 | Basic "a b:pass"; valid ⇒ 200 | Basic "a b:pass"; valid ⇒ 200 | Basic "a b:pass"; valid ⇒ 200 | Basic "a b:pass"; valid ⇒ 200 | Basic "a b:pass"; valid ⇒ 200 |
| user | basic | dquote | http, h2 | Basic "a"b:pass"; valid ⇒ 200 | Basic "a"b:pass"; valid ⇒ 200 | Basic "a"b:pass"; valid ⇒ 200 | Basic "a"b:pass"; valid ⇒ 200 | Basic "a"b:pass"; valid ⇒ 200 |
| user | basic | comma | http, h2 | Basic "a,b:pass"; valid ⇒ 200 | Basic "a,b:pass"; valid ⇒ 200 | Basic "a,b:pass"; valid ⇒ 200 | Basic "a,b:pass"; valid ⇒ 200 | Basic "a,b:pass"; valid ⇒ 200 |
| user | basic | colon | http, h2 | Basic "a:b:pass" (user "a" by the first colon); valid ⇒ 200 | Basic "a:b:pass" (user "a" by the first colon); valid ⇒ 200 | Basic "a:b:pass" (user "a" by the first colon); valid ⇒ 200 | Basic "a:b:pass" (user "a" by the first colon); valid ⇒ 200 | Basic "a:b:pass" (user "a" by the first colon); valid ⇒ 200 |
| user | basic | backslash | http, h2 | Basic "a\\b:pass"; valid ⇒ 200 | Basic "a\\b:pass"; valid ⇒ 200 | Basic "a\\b:pass"; valid ⇒ 200 | Basic "a\\b:pass"; valid ⇒ 200 | Basic "a\\b:pass"; valid ⇒ 200 |
| user | basic | 7f | http, h2 | Basic "a\x7fb:pass"; valid ⇒ 200 | Basic "a\x7fb:pass"; valid ⇒ 200 | Basic "a\x7fb:pass"; valid ⇒ 200 | Basic "a\x7fb:pass"; valid ⇒ 200 | Basic "a\x7fb:pass"; valid ⇒ 200 |
| user | basic | 80 | http, h2 | Basic "a\x80b:pass"; valid ⇒ 200 | Basic "a\x80b:pass"; valid ⇒ 200 | Basic "a\x80b:pass"; valid ⇒ 200 | Basic "a\x80b:pass"; valid ⇒ 200 | Basic "a\x80b:pass"; valid ⇒ 200 |
| user | basic | ff | http, h2 | Basic "a\xffb:pass"; valid ⇒ 200 | Basic "a\xffb:pass"; valid ⇒ 200 | Basic "a\xffb:pass"; valid ⇒ 200 | Basic "a\xffb:pass"; valid ⇒ 200 | Basic "a\xffb:pass"; valid ⇒ 200 |
| user | basic | latin1-u-umlaut | http, h2 | Basic "a\xfcb:pass"; valid ⇒ 200 | Basic "a\xfcb:pass"; valid ⇒ 200 | Basic "a\xfcb:pass"; valid ⇒ 200 | Basic "a\xfcb:pass"; valid ⇒ 200 | Basic "a\xfcb:pass"; valid ⇒ 200 |
| user | basic | utf8-u-umlaut | http, h2 | Basic "a\xc3\xbcb:pass"; valid ⇒ 200 | Basic "a\xc3\xbcb:pass"; valid ⇒ 200 | Basic "a\xc3\xbcb:pass"; valid ⇒ 200 | Basic "a\xc3\xbcb:pass"; valid ⇒ 200 | Basic "a\xc3\xbcb:pass"; valid ⇒ 200 |
| user | basic | crlf-header | http, h2 | Basic "a\x0d\x0aX-Injected: 1b:pass" (user "a\x0d\x0aX-Injected" by the first colon); valid ⇒ 200 | Basic "a\x0d\x0aX-Injected: 1b:pass" (user "a\x0d\x0aX-Injected" by the first colon); valid ⇒ 200 | Basic "a\x0d\x0aX-Injected: 1b:pass" (user "a\x0d\x0aX-Injected" by the first colon); valid ⇒ 200 | Basic "a\x0d\x0aX-Injected: 1b:pass" (user "a\x0d\x0aX-Injected" by the first colon); valid ⇒ 200 | Basic "a\x0d\x0aX-Injected: 1b:pass" (user "a\x0d\x0aX-Injected" by the first colon); valid ⇒ 200 |
| user | digest | x | http, h2 | – → Digest username="axb"; valid ⇒ 200 | – → Digest username="axb"; valid ⇒ 200 | – → Digest username="axb"; valid ⇒ 200 | – → Digest username="axb"; valid ⇒ 200 | – → Digest username="axb"; valid ⇒ 200 |
| user | digest | 01 | http | – → Digest username="a\x01b"; valid ⇒ 200 | – → Digest username="a\x01b"; valid ⇒ 200 | – → Digest username="a\x01b"; valid ⇒ 200 | – → Digest username="a\x01b"; valid ⇒ 200 | – → Digest username="a%01b"; bad(username) ⇒ 401 |
| user | digest | tab | http, h2 | – → Digest username="a\x09b"; valid ⇒ 200 | – → Digest username="a\x09b"; valid ⇒ 200 | – → Digest username="a\x09b"; valid ⇒ 200 | – → Digest username="a\x09b"; valid ⇒ 200 | – → Digest username="a%09b"; bad(username) ⇒ 401 |
| user | digest | lf | http | – → Digest username="a\x0ab"; valid bare CR or LF in head ⇒ 200 | – → Digest username="a\x0ab"; valid bare CR or LF in head ⇒ 200 | – → Digest username="a\x0ab"; valid bare CR or LF in head ⇒ 200 | – → Digest username="a\x0ab"; valid bare CR or LF in head ⇒ 200 | – → Digest username="a%0Ab"; bad(username) ⇒ 401 |
| user | digest | cr | http | – → Digest username="a\x0db"; valid bare CR or LF in head ⇒ 200 | – → Digest username="a\x0db"; valid bare CR or LF in head ⇒ 200 | – → Digest username="a\x0db"; valid bare CR or LF in head ⇒ 200 | – → Digest username="a\x0db"; valid bare CR or LF in head ⇒ 200 | – → Digest username="a%0Db"; bad(username) ⇒ 401 |
| user | digest | 1f | http | – → Digest username="a\x1fb"; valid ⇒ 200 | – → Digest username="a\x1fb"; valid ⇒ 200 | – → Digest username="a\x1fb"; valid ⇒ 200 | – → Digest username="a\x1fb"; valid ⇒ 200 | – → Digest username="a%1Fb"; bad(username) ⇒ 401 |
| user | digest | sp | http, h2 | – → Digest username="a b"; valid ⇒ 200 | – → Digest username="a b"; valid ⇒ 200 | – → Digest username="a b"; valid ⇒ 200 | – → Digest username="a b"; valid ⇒ 200 | – → Digest username="a b"; valid ⇒ 200 |
| user | digest | dquote | http, h2 | – → Digest username="a"b"; valid ⇒ 200 | – → Digest username="a"b"; valid ⇒ 200 | – → Digest username="a"b"; valid ⇒ 200 | – → Digest username="a"b"; valid ⇒ 200 | – → Digest username="a"b"; valid ⇒ 200 |
| user | digest | comma | http, h2 | – → Digest username="a,b"; valid ⇒ 200 | – → Digest username="a,b"; valid ⇒ 200 | – → Digest username="a,b"; valid ⇒ 200 | – → Digest username="a,b"; valid ⇒ 200 | – → Digest username="a,b"; valid ⇒ 200 |
| user | digest | colon | http, h2 | – → Digest username="a:b"; valid ⇒ 200 | – → Digest username="a:b"; valid ⇒ 200 | – → Digest username="a:b"; valid ⇒ 200 | – → Digest username="a:b"; valid ⇒ 200 | – → Digest username="a:b"; valid ⇒ 200 |
| user | digest | backslash | http, h2 | – → Digest username="a\\b"; valid ⇒ 200 | – → Digest username="a\\b"; valid ⇒ 200 | – → Digest username="a\\b"; valid ⇒ 200 | – → Digest username="a\\b"; valid ⇒ 200 | – → Digest username="a\\b"; valid ⇒ 200 |
| user | digest | 7f | http | – → Digest username="a\x7fb"; valid ⇒ 200 | – → Digest username="a\x7fb"; valid ⇒ 200 | – → Digest username="a\x7fb"; valid ⇒ 200 | – → Digest username="a\x7fb"; valid ⇒ 200 | – → Digest username="a%7Fb"; bad(username) ⇒ 401 |
| user | digest | 80 | http, h2 | – → Digest username="a\x80b"; valid ⇒ 200 | – → Digest username="a\x80b"; valid ⇒ 200 | – → Digest username="a\x80b"; valid ⇒ 200 | – → Digest username="a\x80b"; valid ⇒ 200 | – → Digest username="a%80b"; bad(username) ⇒ 401 |
| user | digest | ff | http, h2 | – → Digest username="a\xffb"; valid ⇒ 200 | – → Digest username="a\xffb"; valid ⇒ 200 | – → Digest username="a\xffb"; valid ⇒ 200 | – → Digest username="a\xffb"; valid ⇒ 200 | – → Digest username="a%FFb"; bad(username) ⇒ 401 |
| user | digest | latin1-u-umlaut | http, h2 | – → Digest username="a\xfcb"; valid ⇒ 200 | – → Digest username="a\xfcb"; valid ⇒ 200 | – → Digest username="a\xfcb"; valid ⇒ 200 | – → Digest username="a\xfcb"; valid ⇒ 200 | – → Digest username="a%FCb"; bad(username) ⇒ 401 |
| user | digest | utf8-u-umlaut | http, h2 | – → Digest username="a\xc3\xbcb"; valid ⇒ 200 | – → Digest username="a\xc3\xbcb"; valid ⇒ 200 | – → Digest username="a\xc3\xbcb"; valid ⇒ 200 | – → Digest username="a\xc3\xbcb"; valid ⇒ 200 | – → Digest username="a%C3%BCb"; bad(username) ⇒ 401 |
| user | digest | crlf-header | http, h2 | – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) +header x-injected ⇒ 401 | – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) +header x-injected ⇒ 401 | – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) +header x-injected ⇒ 401 | – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) +header x-injected ⇒ 401 | – → Digest username="a%0D%0AX-Injected: 1b"; bad(username) ⇒ 401 |
| pass | basic | x | http, h2 | Basic "user:axb"; valid ⇒ 200 | Basic "user:axb"; valid ⇒ 200 | Basic "user:axb"; valid ⇒ 200 | Basic "user:axb"; valid ⇒ 200 | Basic "user:axb"; valid ⇒ 200 |
| pass | basic | 01 | http, h2 | Basic "user:a\x01b"; valid ⇒ 200 | Basic "user:a\x01b"; valid ⇒ 200 | Basic "user:a\x01b"; valid ⇒ 200 | Basic "user:a\x01b"; valid ⇒ 200 | Basic "user:a\x01b"; valid ⇒ 200 |
| pass | basic | tab | http, h2 | Basic "user:a\x09b"; valid ⇒ 200 | Basic "user:a\x09b"; valid ⇒ 200 | Basic "user:a\x09b"; valid ⇒ 200 | Basic "user:a\x09b"; valid ⇒ 200 | Basic "user:a\x09b"; valid ⇒ 200 |
| pass | basic | lf | http, h2 | Basic "user:a\x0ab"; valid ⇒ 200 | Basic "user:a\x0ab"; valid ⇒ 200 | Basic "user:a\x0ab"; valid ⇒ 200 | Basic "user:a\x0ab"; valid ⇒ 200 | Basic "user:a\x0ab"; valid ⇒ 200 |
| pass | basic | cr | http, h2 | Basic "user:a\x0db"; valid ⇒ 200 | Basic "user:a\x0db"; valid ⇒ 200 | Basic "user:a\x0db"; valid ⇒ 200 | Basic "user:a\x0db"; valid ⇒ 200 | Basic "user:a\x0db"; valid ⇒ 200 |
| pass | basic | 1f | http, h2 | Basic "user:a\x1fb"; valid ⇒ 200 | Basic "user:a\x1fb"; valid ⇒ 200 | Basic "user:a\x1fb"; valid ⇒ 200 | Basic "user:a\x1fb"; valid ⇒ 200 | Basic "user:a\x1fb"; valid ⇒ 200 |
| pass | basic | sp | http, h2 | Basic "user:a b"; valid ⇒ 200 | Basic "user:a b"; valid ⇒ 200 | Basic "user:a b"; valid ⇒ 200 | Basic "user:a b"; valid ⇒ 200 | Basic "user:a b"; valid ⇒ 200 |
| pass | basic | dquote | http, h2 | Basic "user:a"b"; valid ⇒ 200 | Basic "user:a"b"; valid ⇒ 200 | Basic "user:a"b"; valid ⇒ 200 | Basic "user:a"b"; valid ⇒ 200 | Basic "user:a"b"; valid ⇒ 200 |
| pass | basic | comma | http, h2 | Basic "user:a,b"; valid ⇒ 200 | Basic "user:a,b"; valid ⇒ 200 | Basic "user:a,b"; valid ⇒ 200 | Basic "user:a,b"; valid ⇒ 200 | Basic "user:a,b"; valid ⇒ 200 |
| pass | basic | colon | http, h2 | Basic "user:a:b" (user "user" by the first colon); valid ⇒ 200 | Basic "user:a:b" (user "user" by the first colon); valid ⇒ 200 | Basic "user:a:b" (user "user" by the first colon); valid ⇒ 200 | Basic "user:a:b" (user "user" by the first colon); valid ⇒ 200 | Basic "user:a:b" (user "user" by the first colon); valid ⇒ 200 |
| pass | basic | backslash | http, h2 | Basic "user:a\\b"; valid ⇒ 200 | Basic "user:a\\b"; valid ⇒ 200 | Basic "user:a\\b"; valid ⇒ 200 | Basic "user:a\\b"; valid ⇒ 200 | Basic "user:a\\b"; valid ⇒ 200 |
| pass | basic | 7f | http, h2 | Basic "user:a\x7fb"; valid ⇒ 200 | Basic "user:a\x7fb"; valid ⇒ 200 | Basic "user:a\x7fb"; valid ⇒ 200 | Basic "user:a\x7fb"; valid ⇒ 200 | Basic "user:a\x7fb"; valid ⇒ 200 |
| pass | basic | 80 | http, h2 | Basic "user:a\x80b"; valid ⇒ 200 | Basic "user:a\x80b"; valid ⇒ 200 | Basic "user:a\x80b"; valid ⇒ 200 | Basic "user:a\x80b"; valid ⇒ 200 | Basic "user:a\x80b"; valid ⇒ 200 |
| pass | basic | ff | http, h2 | Basic "user:a\xffb"; valid ⇒ 200 | Basic "user:a\xffb"; valid ⇒ 200 | Basic "user:a\xffb"; valid ⇒ 200 | Basic "user:a\xffb"; valid ⇒ 200 | Basic "user:a\xffb"; valid ⇒ 200 |
| pass | basic | latin1-u-umlaut | http, h2 | Basic "user:a\xfcb"; valid ⇒ 200 | Basic "user:a\xfcb"; valid ⇒ 200 | Basic "user:a\xfcb"; valid ⇒ 200 | Basic "user:a\xfcb"; valid ⇒ 200 | Basic "user:a\xfcb"; valid ⇒ 200 |
| pass | basic | utf8-u-umlaut | http, h2 | Basic "user:a\xc3\xbcb"; valid ⇒ 200 | Basic "user:a\xc3\xbcb"; valid ⇒ 200 | Basic "user:a\xc3\xbcb"; valid ⇒ 200 | Basic "user:a\xc3\xbcb"; valid ⇒ 200 | Basic "user:a\xc3\xbcb"; valid ⇒ 200 |
| pass | basic | crlf-header | http, h2 | Basic "user:a\x0d\x0aX-Injected: 1b" (user "user" by the first colon); valid ⇒ 200 | Basic "user:a\x0d\x0aX-Injected: 1b" (user "user" by the first colon); valid ⇒ 200 | Basic "user:a\x0d\x0aX-Injected: 1b" (user "user" by the first colon); valid ⇒ 200 | Basic "user:a\x0d\x0aX-Injected: 1b" (user "user" by the first colon); valid ⇒ 200 | Basic "user:a\x0d\x0aX-Injected: 1b" (user "user" by the first colon); valid ⇒ 200 |
| pass | digest | x | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | 01 | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | tab | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | lf | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | cr | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | 1f | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | sp | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | dquote | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | comma | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | colon | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | backslash | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | 7f | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | 80 | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | ff | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | latin1-u-umlaut | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | utf8-u-umlaut | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | crlf-header | http, h2 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 | – → Digest username="user"; valid ⇒ 200 |
| token | bearer | x | http, h2 | Bearer "axb"; valid ⇒ 200 | Bearer "axb"; valid ⇒ 200 | Bearer "axb"; valid ⇒ 200 | Bearer "axb"; valid ⇒ 200 | Bearer "axb"; valid ⇒ 200 |
| token | bearer | 01 | http | Bearer "a\x01b"; valid ⇒ 200 | Bearer "a\x01b"; valid ⇒ 200 | Bearer "a\x01b"; valid ⇒ 200 | Bearer "a\x01b"; valid ⇒ 200 | Bearer "a\x01b"; valid ⇒ 200 |
| token | bearer | tab | http, h2 | Bearer "a\x09b"; valid ⇒ 200 | Bearer "a\x09b"; valid ⇒ 200 | Bearer "a\x09b"; valid ⇒ 200 | Bearer "a\x09b"; valid ⇒ 200 | Bearer "a\x09b"; valid ⇒ 200 |
| token | bearer | lf | http | Bearer "a\x0ab"; valid bare CR or LF in head ⇒ 200 | Bearer "a\x0ab"; valid bare CR or LF in head ⇒ 200 | Bearer "a\x0ab"; valid bare CR or LF in head ⇒ 200 | Bearer "a\x0ab"; valid bare CR or LF in head ⇒ 200 | Bearer "a\x0ab"; valid bare CR or LF in head ⇒ 200 |
| token | bearer | cr | http | Bearer "a\x0db"; valid bare CR or LF in head ⇒ 200 | Bearer "a\x0db"; valid bare CR or LF in head ⇒ 200 | Bearer "a\x0db"; valid bare CR or LF in head ⇒ 200 | Bearer "a\x0db"; valid bare CR or LF in head ⇒ 200 | Bearer "a\x0db"; valid bare CR or LF in head ⇒ 200 |
| token | bearer | 1f | http | Bearer "a\x1fb"; valid ⇒ 200 | Bearer "a\x1fb"; valid ⇒ 200 | Bearer "a\x1fb"; valid ⇒ 200 | Bearer "a\x1fb"; valid ⇒ 200 | Bearer "a\x1fb"; valid ⇒ 200 |
| token | bearer | sp | http, h2 | Bearer "a b"; valid ⇒ 200 | Bearer "a b"; valid ⇒ 200 | Bearer "a b"; valid ⇒ 200 | Bearer "a b"; valid ⇒ 200 | Bearer "a b"; valid ⇒ 200 |
| token | bearer | dquote | http, h2 | Bearer "a"b"; valid ⇒ 200 | Bearer "a"b"; valid ⇒ 200 | Bearer "a"b"; valid ⇒ 200 | Bearer "a"b"; valid ⇒ 200 | Bearer "a"b"; valid ⇒ 200 |
| token | bearer | comma | http, h2 | Bearer "a,b"; valid ⇒ 200 | Bearer "a,b"; valid ⇒ 200 | Bearer "a,b"; valid ⇒ 200 | Bearer "a,b"; valid ⇒ 200 | Bearer "a,b"; valid ⇒ 200 |
| token | bearer | colon | http, h2 | Bearer "a:b"; valid ⇒ 200 | Bearer "a:b"; valid ⇒ 200 | Bearer "a:b"; valid ⇒ 200 | Bearer "a:b"; valid ⇒ 200 | Bearer "a:b"; valid ⇒ 200 |
| token | bearer | backslash | http, h2 | Bearer "a\\b"; valid ⇒ 200 | Bearer "a\\b"; valid ⇒ 200 | Bearer "a\\b"; valid ⇒ 200 | Bearer "a\\b"; valid ⇒ 200 | Bearer "a\\b"; valid ⇒ 200 |
| token | bearer | 7f | http | Bearer "a\x7fb"; valid ⇒ 200 | Bearer "a\x7fb"; valid ⇒ 200 | Bearer "a\x7fb"; valid ⇒ 200 | Bearer "a\x7fb"; valid ⇒ 200 | Bearer "a\x7fb"; valid ⇒ 200 |
| token | bearer | 80 | http, h2 | Bearer "a\x80b"; valid ⇒ 200 | Bearer "a\x80b"; valid ⇒ 200 | Bearer "a\x80b"; valid ⇒ 200 | Bearer "a\x80b"; valid ⇒ 200 | Bearer "a\x80b"; valid ⇒ 200 |
| token | bearer | ff | http, h2 | Bearer "a\xffb"; valid ⇒ 200 | Bearer "a\xffb"; valid ⇒ 200 | Bearer "a\xffb"; valid ⇒ 200 | Bearer "a\xffb"; valid ⇒ 200 | Bearer "a\xffb"; valid ⇒ 200 |
| token | bearer | latin1-u-umlaut | http, h2 | Bearer "a\xfcb"; valid ⇒ 200 | Bearer "a\xfcb"; valid ⇒ 200 | Bearer "a\xfcb"; valid ⇒ 200 | Bearer "a\xfcb"; valid ⇒ 200 | Bearer "a\xfcb"; valid ⇒ 200 |
| token | bearer | utf8-u-umlaut | http, h2 | Bearer "a\xc3\xbcb"; valid ⇒ 200 | Bearer "a\xc3\xbcb"; valid ⇒ 200 | Bearer "a\xc3\xbcb"; valid ⇒ 200 | Bearer "a\xc3\xbcb"; valid ⇒ 200 | Bearer "a\xc3\xbcb"; valid ⇒ 200 |
| token | bearer | crlf-header | http, h2 | Bearer "a"; refused +header x-injected ⇒ 401 | Bearer "a"; refused +header x-injected ⇒ 401 | Bearer "a"; refused +header x-injected ⇒ 401 | Bearer "a"; refused +header x-injected ⇒ 401 | Bearer "a"; refused +header x-injected ⇒ 401 |
| user | basic | utf8-string | http, h2 | Basic "\xc3\xbcser:pass"; valid ⇒ 200 | Basic "\xc3\xbcser:pass"; valid ⇒ 200 | Basic "\xc3\xbcser:pass"; valid ⇒ 200 | Basic "\xc3\xbcser:pass"; valid ⇒ 200 | Basic "\xc3\xbcser:pass"; valid ⇒ 200 |
| user | digest | utf8-string | http, h2 | – → Digest username="\xc3\xbcser"; valid ⇒ 200 | – → Digest username="\xc3\xbcser"; valid ⇒ 200 | – → Digest username="\xc3\xbcser"; valid ⇒ 200 | – → Digest username="\xc3\xbcser"; valid ⇒ 200 | – → Digest username="%C3%BCser"; bad(username) ⇒ 401 |
| user | basic | nul-string | http, h2 | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in |
| user | basic | nul-bytes | http, h2 | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in |
| pass | digest | nul-string | http, h2 | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in |
| pass | digest | nul-bytes | http, h2 | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in |
| token | bearer | nul-string | http, h2 | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in |
| token | bearer | nul-bytes | http, h2 | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in | refused embedded-nul, no request reached the stand-in |
| user | digest | 01 | h2 | – → –; no Authorization arrived ⇒ 401 | – → –; no Authorization arrived ⇒ 401 | – → –; no Authorization arrived ⇒ 401 | – → –; no Authorization arrived ⇒ 401 | – → Digest username="a%01b"; bad(username) ⇒ 401 |
| user | digest | lf | h2 | – → –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ fails 43 | –; no Authorization arrived ⇒ fails 43 | –; no Authorization arrived ⇒ fails 43 | – → Digest username="a%0Ab"; bad(username) ⇒ 401 |
| user | digest | cr | h2 | –; no Authorization arrived ⇒ fails 27 | – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) ⇒ 401 | – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) ⇒ 401 | – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) ⇒ 401 | – → Digest username="a%0Db"; bad(username) ⇒ 401 |
| user | digest | 1f | h2 | – → –; no Authorization arrived ⇒ 401 | – → –; no Authorization arrived ⇒ 401 | – → –; no Authorization arrived ⇒ 401 | – → –; no Authorization arrived ⇒ 401 | – → Digest username="a%1Fb"; bad(username) ⇒ 401 |
| user | digest | 7f | h2 | – → –; no Authorization arrived ⇒ 401 | – → –; no Authorization arrived ⇒ 401 | – → –; no Authorization arrived ⇒ 401 | – → –; no Authorization arrived ⇒ 401 | – → Digest username="a%7Fb"; bad(username) ⇒ 401 |
| token | bearer | 01 | h2 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 |
| token | bearer | lf | h2 | –; no Authorization arrived ⇒ 401 | fails 43, nothing sent, no request reached the stand-in | fails 43, nothing sent, no request reached the stand-in | fails 43, nothing sent, no request reached the stand-in | fails 43, nothing sent, no request reached the stand-in |
| token | bearer | cr | h2 | fails 27, nothing sent, no request reached the stand-in | Bearer "a"; refused ⇒ 401 | Bearer "a"; refused ⇒ 401 | Bearer "a"; refused ⇒ 401 | Bearer "a"; refused ⇒ 401 |
| token | bearer | 1f | h2 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 |
| token | bearer | 7f | h2 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 | –; no Authorization arrived ⇒ 401 |

### Item 4: lengths (`i4len` lines)

A cell: the outcome (a setopt refusal names its code); the stand-in's verdict on the bytes it received, and their length.

| field | scheme | length | face | F | O | G | X | C |
|---|---|---|---|---|---|---|---|---|
| pass | basic | 8192 | http, h2 | 200; valid, header 10938 bytes; Basic✓/200 | 200; valid, header 10938 bytes; Basic✓/200 | 200; valid, header 10938 bytes; Basic✓/200 | 200; valid, header 10938 bytes; Basic✓/200 | 200; valid, header 10938 bytes; Basic✓/200 |
| pass | basic | 65536 | http | 200; valid, header 87394 bytes; Basic✓/200 | 200; valid, header 87394 bytes; Basic✓/200 | 200; valid, header 87394 bytes; Basic✓/200 | 200; valid, header 87394 bytes; Basic✓/200 | 200; valid, header 87394 bytes; Basic✓/200 |
| pass | basic | 1048576 | http, h2 | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 100, nothing sent; nothing sent | fails 100, nothing sent; nothing sent |
| pass | basic | 8000000 | http, h2 | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent |
| pass | basic | 8000001 | http, h2 | setopt 43 PASSWORD; nothing sent | setopt 43 PASSWORD; nothing sent | setopt 43 PASSWORD; nothing sent | setopt 43 PASSWORD; nothing sent | setopt 43 PASSWORD; nothing sent |
| pass | digest | 8192 | http, h2 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 |
| pass | digest | 65536 | http, h2 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 |
| pass | digest | 1048576 | http, h2 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 | 200; valid; –/401 → Digest✓/200 |
| pass | digest | 8000000 | http, h2 | fails 27; no Authorization; –/401 | fails 27; no Authorization; –/401 | fails 27; no Authorization; –/401 | fails 27; no Authorization; –/401 | fails 27; no Authorization; –/401 |
| pass | digest | 8000001 | http, h2 | setopt 43 PASSWORD; nothing sent | setopt 43 PASSWORD; nothing sent | setopt 43 PASSWORD; nothing sent | setopt 43 PASSWORD; nothing sent | setopt 43 PASSWORD; nothing sent |
| token | bearer | 8192 | http, h2 | 200; valid, header 8199 bytes; Bearer✓/200 | 200; valid, header 8199 bytes; Bearer✓/200 | 200; valid, header 8199 bytes; Bearer✓/200 | 200; valid, header 8199 bytes; Bearer✓/200 | 200; valid, header 8199 bytes; Bearer✓/200 |
| token | bearer | 65536 | http | 200; valid, header 65543 bytes; Bearer✓/200 | 200; valid, header 65543 bytes; Bearer✓/200 | 200; valid, header 65543 bytes; Bearer✓/200 | 200; valid, header 65543 bytes; Bearer✓/200 | 200; valid, header 65543 bytes; Bearer✓/200 |
| token | bearer | 1048576 | http, h2 | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 100, nothing sent; nothing sent | fails 100, nothing sent; nothing sent |
| token | bearer | 8000000 | http, h2 | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent | fails 27, nothing sent; nothing sent |
| token | bearer | 8000001 | http, h2 | setopt 43 XOAUTH2_BEARER; nothing sent | setopt 43 XOAUTH2_BEARER; nothing sent | setopt 43 XOAUTH2_BEARER; nothing sent | setopt 43 XOAUTH2_BEARER; nothing sent | setopt 43 XOAUTH2_BEARER; nothing sent |
| pass | basic | 65536 | h2 | fails 56; nothing sent | fails 55; nothing sent | fails 55; nothing sent | fails 55; nothing sent | fails 55; nothing sent |
| token | bearer | 65536 | h2 | fails 56; nothing sent | fails 55; nothing sent | fails 55; nothing sent | fails 55; nothing sent | fails 55; nothing sent |

### Item 4: control bytes over h2, in libcurl's own trace (`i4trace` lines)

The h2 face's HTTP/2 stack drops a field holding a control byte before the stand-in sees it, so these cases ran again with `VERBOSE`. A cell: each `authorization` field libcurl's trace shows it handing HTTP/2 (`[HTTP/2] [N] [...]` from 8.5.0, `h2h3 [...]` on 7.85.0), escaped, the nonce and response cut; then the outcome, and the stand-in's view as in item 4.

| field | scheme | byte | face | F | O | G | X | C |
|---|---|---|---|---|---|---|---|---|
| user | digest | x | h2 | `Digest username="axb", ...`; – → Digest username="axb"; valid ⇒ 200 | `Digest username="axb", ...`; – → Digest username="axb"; valid ⇒ 200 | `Digest username="axb", ...`; – → Digest username="axb"; valid ⇒ 200 | `Digest username="axb", ...`; – → Digest username="axb"; valid ⇒ 200 | `Digest username="axb", ...`; – → Digest username="axb"; valid ⇒ 200 |
| user | digest | 01 | h2 | `Digest username="a\x01b", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a\x01b", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a\x01b", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a\x01b", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a%01b", ...`; – → Digest username="a%01b"; bad(username) ⇒ 401 |
| user | digest | tab | h2 | `Digest username="a\x09b", ...`; – → Digest username="a\x09b"; valid ⇒ 200 | `Digest username="a\x09b", ...`; – → Digest username="a\x09b"; valid ⇒ 200 | `Digest username="a\x09b", ...`; – → Digest username="a\x09b"; valid ⇒ 200 | `Digest username="a\x09b", ...`; – → Digest username="a\x09b"; valid ⇒ 200 | `Digest username="a%09b", ...`; – → Digest username="a%09b"; bad(username) ⇒ 401 |
| user | digest | lf | h2 | `Digest username="a\x0ab", ...`; – → –; no Authorization arrived ⇒ 401 | no authorization field traced; –; no Authorization arrived ⇒ fails 43 | no authorization field traced; –; no Authorization arrived ⇒ fails 43 | no authorization field traced; –; no Authorization arrived ⇒ fails 43 | `Digest username="a%0Ab", ...`; – → Digest username="a%0Ab"; bad(username) ⇒ 401 |
| user | digest | cr | h2 | no authorization field traced; –; no Authorization arrived ⇒ fails 27 | `Digest username="a`; – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) ⇒ 401 | `Digest username="a`; – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) ⇒ 401 | `Digest username="a`; – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) ⇒ 401 | `Digest username="a%0Db", ...`; – → Digest username="a%0Db"; bad(username) ⇒ 401 |
| user | digest | 1f | h2 | `Digest username="a\x1fb", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a\x1fb", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a\x1fb", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a\x1fb", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a%1Fb", ...`; – → Digest username="a%1Fb"; bad(username) ⇒ 401 |
| user | digest | 7f | h2 | `Digest username="a\x7fb", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a\x7fb", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a\x7fb", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a\x7fb", ...`; – → –; no Authorization arrived ⇒ 401 | `Digest username="a%7Fb", ...`; – → Digest username="a%7Fb"; bad(username) ⇒ 401 |
| user | digest | 80 | h2 | `Digest username="a\x80b", ...`; – → Digest username="a\x80b"; valid ⇒ 200 | `Digest username="a\x80b", ...`; – → Digest username="a\x80b"; valid ⇒ 200 | `Digest username="a\x80b", ...`; – → Digest username="a\x80b"; valid ⇒ 200 | `Digest username="a\x80b", ...`; – → Digest username="a\x80b"; valid ⇒ 200 | `Digest username="a%80b", ...`; – → Digest username="a%80b"; bad(username) ⇒ 401 |
| token | bearer | x | h2 | `Bearer axb`; Bearer "axb"; valid ⇒ 200 | `Bearer axb`; Bearer "axb"; valid ⇒ 200 | `Bearer axb`; Bearer "axb"; valid ⇒ 200 | `Bearer axb`; Bearer "axb"; valid ⇒ 200 | `Bearer axb`; Bearer "axb"; valid ⇒ 200 |
| token | bearer | 01 | h2 | `Bearer a\x01b`; –; no Authorization arrived ⇒ 401 | `Bearer a\x01b`; –; no Authorization arrived ⇒ 401 | `Bearer a\x01b`; –; no Authorization arrived ⇒ 401 | `Bearer a\x01b`; –; no Authorization arrived ⇒ 401 | `Bearer a\x01b`; –; no Authorization arrived ⇒ 401 |
| token | bearer | tab | h2 | `Bearer a\x09b`; Bearer "a\x09b"; valid ⇒ 200 | `Bearer a\x09b`; Bearer "a\x09b"; valid ⇒ 200 | `Bearer a\x09b`; Bearer "a\x09b"; valid ⇒ 200 | `Bearer a\x09b`; Bearer "a\x09b"; valid ⇒ 200 | `Bearer a\x09b`; Bearer "a\x09b"; valid ⇒ 200 |
| token | bearer | lf | h2 | `Bearer a\x0ab`; –; no Authorization arrived ⇒ 401 | no authorization field traced; fails 43, nothing sent, no request reached the stand-in | no authorization field traced; fails 43, nothing sent, no request reached the stand-in | no authorization field traced; fails 43, nothing sent, no request reached the stand-in | no authorization field traced; fails 43, nothing sent, no request reached the stand-in |
| token | bearer | cr | h2 | no authorization field traced; fails 27, nothing sent, no request reached the stand-in | `Bearer a`; Bearer "a"; refused ⇒ 401 | `Bearer a`; Bearer "a"; refused ⇒ 401 | `Bearer a`; Bearer "a"; refused ⇒ 401 | `Bearer a`; Bearer "a"; refused ⇒ 401 |
| token | bearer | 1f | h2 | `Bearer a\x1fb`; –; no Authorization arrived ⇒ 401 | `Bearer a\x1fb`; –; no Authorization arrived ⇒ 401 | `Bearer a\x1fb`; –; no Authorization arrived ⇒ 401 | `Bearer a\x1fb`; –; no Authorization arrived ⇒ 401 | `Bearer a\x1fb`; –; no Authorization arrived ⇒ 401 |
| token | bearer | 7f | h2 | `Bearer a\x7fb`; –; no Authorization arrived ⇒ 401 | `Bearer a\x7fb`; –; no Authorization arrived ⇒ 401 | `Bearer a\x7fb`; –; no Authorization arrived ⇒ 401 | `Bearer a\x7fb`; –; no Authorization arrived ⇒ 401 | `Bearer a\x7fb`; –; no Authorization arrived ⇒ 401 |
| token | bearer | 80 | h2 | `Bearer a\x80b`; Bearer "a\x80b"; valid ⇒ 200 | `Bearer a\x80b`; Bearer "a\x80b"; valid ⇒ 200 | `Bearer a\x80b`; Bearer "a\x80b"; valid ⇒ 200 | `Bearer a\x80b`; Bearer "a\x80b"; valid ⇒ 200 | `Bearer a\x80b`; Bearer "a\x80b"; valid ⇒ 200 |

- **NUL:** the hatch refuses U+0000 in a string, `embedded-nul`, on main and on the prototype, and
  the seam refuses a 0 byte the same way; nothing is sent (`bytes88`).
- **Basic** carries every byte, base64-encoded, on every lane and face; a user name holding `:`
  goes out as given, and a server splitting at the first colon reads another user.
- **A bare CR or LF goes out raw over HTTP/1.1, inside its line,** in a Bearer token on all five
  and in a Digest user name on 7.85.0 to 8.20.0 (`bare CR or LF in head`). CR LF ends the line, and
  the rest is a header of its own: `X-Injected: 1` arrives as a header (`+header x-injected`), for
  a Bearer token on all five, and for a Digest user name on 7.85.0 to 8.20.0; 8.23.0
  percent-encodes the user name's bytes.
- **8.23.0's Digest user name.** Each byte below 0x20, 0x7F and above goes out as `%XX` in
  `username="..."`, and the response is computed over the raw bytes, so the stand-in, comparing
  `username` with the account, refuses it (`bad(username)`); the auth probe's UTF-8 finding,
  generalised to every byte outside 0x20 to 0x7E. `"`, `\`, `,`, `:` and SP go out as the other
  lanes send them, `"` and `\` escaped.
- **Over `h2`** (`i4trace`): every lane hands nghttp2 the bytes 0x01, TAB, 0x1F, 0x7F and 0x80 as
  set (8.23.0 its percent-encoded name); the stand-in's HTTP/2 stack drops a field holding 0x01,
  0x1F or 0x7F, so no `Authorization` arrives. A CR cuts the value at the CR on 8.5.0 and later,
  and the rest is gone; a bare LF fails 43 on 8.5.0 and later, a Bearer request before anything is
  sent, a Digest one after its probe. 8.23.0 percent-encodes either byte in a Digest user name,
  and is refused as for every other byte. 7.85.0 passes the LF to nghttp2, and fails 27 on a CR,
  nothing sent.
- **Lengths.** A 64 KiB `Authorization` passes over HTTP/1.1 and fails over `h2`, 55 (56 on
  7.85.0), with nothing sent (`bytes203`). A 1 MiB password or token fails before anything is
  sent, 27 on 7.85.0 and 8.5.0 and 100 on 8.20.0 and 8.23.0 (`bytes96`); under Digest, whose
  password is only hashed, 1 MiB passes and 8,000,000 bytes fails 27 after the probe. 8,000,001
  bytes is refused by the setopt itself, 43, `setopt-failed` naming the option (`bytes98`):
  libcurl's `CURL_MAX_INPUT_LENGTH` is 8,000,000.

## Item 5: requests inside one transfer

### Item 5 (a): Digest's second request and the first's connection (from `i1`, right credentials)

A cell: for each Digest variant with a second request, `same` when it rode the first's connection, else `other`, counted: 8 of the 10 variants per face and method send one (`-sess` without `qop` does not).

| method | face | F | O | G | X | C |
|---|---|---|---|---|---|---|
| get | http, https, h2 | same ×8 | same ×8 | same ×8 | same ×8 | same ×8 |
| post | http, https, h2 | same ×8 | same ×8 | same ×8 | same ×8 | same ×8 |

### Item 5 (b): a caller's `Expect: 100-continue`, a 64 KiB `post` (`i5expect` lines)

Modes: `417`, the stand-in answers 417 to every request carrying it; `417once`, to the first alone; `401`, a head that would fail is answered 401 before any 100. A cell: the requests, as in item 1 (`{none sent}`: the next bytes began a request), ⇒ the final status or code. Every transfer's timeout-ms is 5,000.

| scheme | case | mode | face | F | O | G | X | C |
|---|---|---|---|---|---|---|---|---|
| basic | right | 417 | http, https | 40 × Basic/417 at head{none sent}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 |
| basic | right | 417once | http, https | Basic/417 at head{none sent}·E → Basic✓/200{65536}·E ⇒ 200 | Basic/417 at head{none sent}·E → Basic✓/200{65536}·E ⇒ 200 | Basic/417 at head{none sent}·E → Basic✓/200{65536}·E ⇒ 200 | Basic/417 at head{none sent}·E → Basic✓/200{65536}·E ⇒ 200 | Basic/417 at head{none sent}·E → Basic✓/200{65536}·E ⇒ 200 |
| basic | right | 401 | http, https, h2 | Basic✓/200{65536}·E ⇒ 200 | Basic✓/200{65536}·E ⇒ 200 | Basic✓/200{65536}·E ⇒ 200 | Basic✓/200{65536}·E ⇒ 200 | Basic✓/200{65536}·E ⇒ 200 |
| basic | wrong | 417 | http, https | 40 × Basic/417 at head{none sent}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 |
| basic | wrong | 417once | http, https | Basic/417 at head{none sent}·E → Basic✗/401 at head{0, closed}·E ⇒ 401 | Basic/417 at head{none sent}·E → Basic✗/401 at head{0, closed}·E ⇒ 401 | Basic/417 at head{none sent}·E → Basic✗/401 at head{0, closed}·E ⇒ 401 | Basic/417 at head{none sent}·E → Basic✗/401 at head{0, closed}·E ⇒ 401 | Basic/417 at head{none sent}·E → Basic✗/401 at head{0, closed}·E ⇒ 401 |
| basic | wrong | 401 | http, https | Basic✗/401 at head{0, closed}·E ⇒ 401 | Basic✗/401 at head{0, closed}·E ⇒ 401 | Basic✗/401 at head{0, closed}·E ⇒ 401 | Basic✗/401 at head{0, closed}·E ⇒ 401 | Basic✗/401 at head{0, closed}·E ⇒ 401 |
| bearer | right | 417 | http, https | 40 × Bearer/417 at head{none sent}·E → over 1,000 more, the last Bearer/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 |
| bearer | right | 417once | http, https | Bearer/417 at head{none sent}·E → Bearer✓/200{65536}·E ⇒ 200 | Bearer/417 at head{none sent}·E → Bearer✓/200{65536}·E ⇒ 200 | Bearer/417 at head{none sent}·E → Bearer✓/200{65536}·E ⇒ 200 | Bearer/417 at head{none sent}·E → Bearer✓/200{65536}·E ⇒ 200 | Bearer/417 at head{none sent}·E → Bearer✓/200{65536}·E ⇒ 200 |
| bearer | right | 401 | http, https, h2 | Bearer✓/200{65536}·E ⇒ 200 | Bearer✓/200{65536}·E ⇒ 200 | Bearer✓/200{65536}·E ⇒ 200 | Bearer✓/200{65536}·E ⇒ 200 | Bearer✓/200{65536}·E ⇒ 200 |
| bearer | wrong | 417 | http, https | 40 × Bearer/417 at head{none sent}·E → over 1,000 more, the last Bearer/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 |
| bearer | wrong | 417once | http, https | Bearer/417 at head{none sent}·E → Bearer✗/401 at head{0, closed}·E ⇒ 401 | Bearer/417 at head{none sent}·E → Bearer✗/401 at head{0, closed}·E ⇒ 401 | Bearer/417 at head{none sent}·E → Bearer✗/401 at head{0, closed}·E ⇒ 401 | Bearer/417 at head{none sent}·E → Bearer✗/401 at head{0, closed}·E ⇒ 401 | Bearer/417 at head{none sent}·E → Bearer✗/401 at head{0, closed}·E ⇒ 401 |
| bearer | wrong | 401 | http, https | Bearer✗/401 at head{0, closed}·E ⇒ 401 | Bearer✗/401 at head{0, closed}·E ⇒ 401 | Bearer✗/401 at head{0, closed}·E ⇒ 401 | Bearer✗/401 at head{0, closed}·E ⇒ 401 | Bearer✗/401 at head{0, closed}·E ⇒ 401 |
| digest | right | 417 | http, https | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 |
| digest | right | 417once | http, https | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 |
| digest | right | 401 | http, https, h2 | –/401·E → Digest✓/200{65536}·E ⇒ 200 | –/401·E → Digest✓/200{65536}·E ⇒ 200 | –/401·E → Digest✓/200{65536}·E ⇒ 200 | –/401·E → Digest✓/200{65536}·E ⇒ 200 | –/401·E → Digest✓/200{65536}·E ⇒ 200 |
| digest | wrong | 417 | http, https | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 |
| digest | wrong | 417once | http, https | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 |
| digest | wrong | 401 | http, https | –/401·E → Digest✗/401 at head{0, closed}·E ⇒ 401 | –/401·E → Digest✗/401 at head{0, closed}·E ⇒ 401 | –/401·E → Digest✗/401 at head{0, closed}·E ⇒ 401 | –/401·E → Digest✗/401 at head{0, closed}·E ⇒ 401 | –/401·E → Digest✗/401 at head{0, closed}·E ⇒ 401 |
| basic | right | 417 | h2 | 40 × Basic/417 at head{0, closed}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 30 × Basic/417 at head{0, closed}·E → Basic/417 at head·E ⇒ fails 47 | 30 × Basic/417 at head{0, closed}·E → Basic/417 at head·E ⇒ fails 47 | 31 × Basic/417 at head{0, closed}·E ⇒ fails 47 | 31 × Basic/417 at head{0, closed}·E ⇒ fails 47 |
| basic | right | 417once | h2 | Basic/417 at head{0, closed}·E → Basic✓/200{65536}·E ⇒ 200 | Basic/417 at head{0, closed}·E → Basic✓/200{65536}·E ⇒ 200 | Basic/417 at head{0, closed}·E → Basic✓/200{65536}·E ⇒ 200 | Basic/417 at head{0, closed}·E → Basic✓/200{65536}·E ⇒ 200 | Basic/417 at head{0, closed}·E → Basic✓/200{65536}·E ⇒ 200 |
| basic | wrong | 417 | h2 | 40 × Basic/417 at head{0, closed}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 30 × Basic/417 at head{0, closed}·E → Basic/417 at head·E ⇒ fails 47 | 30 × Basic/417 at head{0, closed}·E → Basic/417 at head·E ⇒ fails 47 | 31 × Basic/417 at head{0, closed}·E ⇒ fails 47 | 31 × Basic/417 at head{0, closed}·E ⇒ fails 47 |
| basic | wrong | 417once | h2 | Basic/417 at head{0, closed}·E → Basic✗/401{65536}·E ⇒ 401 | Basic/417 at head{0, closed}·E → Basic✗/401{65536}·E ⇒ 401 | Basic/417 at head{0, closed}·E → Basic✗/401{65536}·E ⇒ 401 | Basic/417 at head{0, closed}·E → Basic✗/401{65536}·E ⇒ 401 | Basic/417 at head{0, closed}·E → Basic✗/401{65536}·E ⇒ 401 |
| basic | wrong | 401 | h2 | Basic✗/401{65536}·E ⇒ 401 | Basic✗/401{65536}·E ⇒ 401 | Basic✗/401{65536}·E ⇒ 401 | Basic✗/401{65536}·E ⇒ 401 | Basic✗/401{65536}·E ⇒ 401 |
| bearer | right | 417 | h2 | 40 × Bearer/417 at head{0, closed}·E → over 1,000 more, the last Bearer/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 30 × Bearer/417 at head{0, closed}·E → Bearer/417 at head·E ⇒ fails 47 | 30 × Bearer/417 at head{0, closed}·E → Bearer/417 at head·E ⇒ fails 47 | 31 × Bearer/417 at head{0, closed}·E ⇒ fails 47 | 31 × Bearer/417 at head{0, closed}·E ⇒ fails 47 |
| bearer | right | 417once | h2 | Bearer/417 at head{0, closed}·E → Bearer✓/200{65536}·E ⇒ 200 | Bearer/417 at head{0, closed}·E → Bearer✓/200{65536}·E ⇒ 200 | Bearer/417 at head{0, closed}·E → Bearer✓/200{65536}·E ⇒ 200 | Bearer/417 at head{0, closed}·E → Bearer✓/200{65536}·E ⇒ 200 | Bearer/417 at head{0, closed}·E → Bearer✓/200{65536}·E ⇒ 200 |
| bearer | wrong | 417 | h2 | 40 × Bearer/417 at head{0, closed}·E → over 1,000 more, the last Bearer/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 30 × Bearer/417 at head{0, closed}·E → Bearer/417 at head·E ⇒ fails 47 | 30 × Bearer/417 at head{0, closed}·E → Bearer/417 at head·E ⇒ fails 47 | 31 × Bearer/417 at head{0, closed}·E ⇒ fails 47 | 31 × Bearer/417 at head{0, closed}·E ⇒ fails 47 |
| bearer | wrong | 417once | h2 | Bearer/417 at head{0, closed}·E → Bearer✗/401{65536}·E ⇒ 401 | Bearer/417 at head{0, closed}·E → Bearer✗/401{65536}·E ⇒ 401 | Bearer/417 at head{0, closed}·E → Bearer✗/401{65536}·E ⇒ 401 | Bearer/417 at head{0, closed}·E → Bearer✗/401{65536}·E ⇒ 401 | Bearer/417 at head{0, closed}·E → Bearer✗/401{65536}·E ⇒ 401 |
| bearer | wrong | 401 | h2 | Bearer✗/401{65536}·E ⇒ 401 | Bearer✗/401{65536}·E ⇒ 401 | Bearer✗/401{65536}·E ⇒ 401 | Bearer✗/401{65536}·E ⇒ 401 | Bearer✗/401{65536}·E ⇒ 401 |
| digest | right | 417 | h2 | –/417 at head{0, closed}·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 |
| digest | right | 417once | h2 | –/417 at head{0, closed}·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 |
| digest | wrong | 417 | h2 | –/417 at head{0, closed}·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 |
| digest | wrong | 417once | h2 | –/417 at head{0, closed}·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 | –/417 at head·E ⇒ 417 |
| digest | wrong | 401 | h2 | –/401·E → Digest✗/401{65536}·E ⇒ 401 | –/401·E → Digest✗/401{65536}·E ⇒ 401 | –/401·E → Digest✗/401{65536}·E ⇒ 401 | –/401·E → Digest✗/401{65536}·E ⇒ 401 | –/401·E → Digest✗/401{65536}·E ⇒ 401 |

### Item 5 (c): the first valid request (or two) answered 401 again (`i5stale` lines)

Digest's second 401 carries `stale=true` and a new nonce; Basic's and Bearer's carry the route's challenge. A cell as in item 1.

| scheme | stale | face | F | O | G | X | C |
|---|---|---|---|---|---|---|---|
| digest | 1 | http, h2 | –/401 → Digest✓/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/401 → Digest✓/200 ⇒ 200 |
| digest | 2 | http, h2 | –/401 → Digest✓/401 → Digest✓/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/401 → Digest✓/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/401 → Digest✓/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/401 → Digest✓/401 → Digest✓/200 ⇒ 200 | –/401 → Digest✓/401 → Digest✓/401 → Digest✓/200 ⇒ 200 |
| basic | 1 | http, h2 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 | Basic✓/401 ⇒ 401 |
| bearer | 1 | http, h2 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 | Bearer✓/401 ⇒ 401 |

### Item 5 (d): the private follow, a 302 from the first hop (`i5follow` lines)

A cell: each request, with its connection as a letter (A, B ... in order of first use; another letter is another connection), as in item 1, ⇒ the final status. The first hop is `http://127.0.0.1` (`localhost` in `localhost-to-ip`), the h2 face in `h2-same-origin`; `http-to-https-same-port` changes the scheme alone, on one port.

| scheme | target | UNRESTRICTED_AUTH | F | O | G | X | C |
|---|---|---|---|---|---|---|---|
| basic | same-origin | off | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 |
| basic | same-origin | on | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 |
| basic | other-port | off | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | other-port | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | ip-to-localhost | off | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | ip-to-localhost | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | localhost-to-ip | off | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | localhost-to-ip | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | http-to-https-same-port | off | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | http-to-https-same-port | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | http-to-https-face | off | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | http-to-https-face | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | h2-same-origin | off | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 |
| basic | h2-same-origin | on | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 |
| digest | same-origin | off | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 |
| digest | same-origin | on | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 |
| digest | other-port | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | other-port | on | A:–/401 → A:Digest✓/302 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | ip-to-localhost | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | ip-to-localhost | on | A:–/401 → A:Digest✓/302 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | localhost-to-ip | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | localhost-to-ip | on | A:–/401 → A:Digest✓/302 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | http-to-https-same-port | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | http-to-https-same-port | on | A:–/401 → A:Digest✓/302 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | http-to-https-face | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | http-to-https-face | on | A:–/401 → A:Digest✓/302 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | h2-same-origin | off | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 |
| digest | h2-same-origin | on | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 |
| bearer | same-origin | off | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 |
| bearer | same-origin | on | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 |
| bearer | other-port | off | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | other-port | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | ip-to-localhost | off | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | ip-to-localhost | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | localhost-to-ip | off | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | localhost-to-ip | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | http-to-https-same-port | off | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | http-to-https-same-port | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | http-to-https-face | off | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | http-to-https-face | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | h2-same-origin | off | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 |
| bearer | h2-same-origin | on | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 |

### Items 5 and 8: the address each request to `localhost` reached (`i5follow`, `i8` lines)

A cell: each request's peer address at the stand-in, in order; every face listens on 127.0.0.1 and on ::1 at one port.

| item | scheme | target | UNRESTRICTED_AUTH | F | O | G | X | C |
|---|---|---|---|---|---|---|---|---|
| i5follow | basic | ip-to-localhost | off | 127.0.0.1, 127.0.0.1 | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] |
| i5follow | basic | ip-to-localhost | on | 127.0.0.1, 127.0.0.1 | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] |
| i5follow | basic | localhost-to-ip | off | 127.0.0.1, 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 |
| i5follow | basic | localhost-to-ip | on | 127.0.0.1, 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 |
| i5follow | digest | ip-to-localhost | off | 127.0.0.1, 127.0.0.1, 127.0.0.1 | 127.0.0.1, 127.0.0.1, [::1] | 127.0.0.1, 127.0.0.1, [::1] | 127.0.0.1, 127.0.0.1, [::1] | 127.0.0.1, 127.0.0.1, [::1] |
| i5follow | digest | ip-to-localhost | on | 127.0.0.1, 127.0.0.1, 127.0.0.1 | 127.0.0.1, 127.0.0.1, [::1], [::1] | 127.0.0.1, 127.0.0.1, [::1], [::1] | 127.0.0.1, 127.0.0.1, [::1], [::1] | 127.0.0.1, 127.0.0.1, [::1], [::1] |
| i5follow | digest | localhost-to-ip | off | 127.0.0.1, 127.0.0.1, 127.0.0.1 | [::1], [::1], 127.0.0.1 | [::1], [::1], 127.0.0.1 | [::1], [::1], 127.0.0.1 | [::1], [::1], 127.0.0.1 |
| i5follow | digest | localhost-to-ip | on | 127.0.0.1, 127.0.0.1, 127.0.0.1 | [::1], [::1], 127.0.0.1, 127.0.0.1 | [::1], [::1], 127.0.0.1, 127.0.0.1 | [::1], [::1], 127.0.0.1, 127.0.0.1 | [::1], [::1], 127.0.0.1, 127.0.0.1 |
| i5follow | bearer | ip-to-localhost | off | 127.0.0.1, 127.0.0.1 | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] |
| i5follow | bearer | ip-to-localhost | on | 127.0.0.1, 127.0.0.1 | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] |
| i5follow | bearer | localhost-to-ip | off | 127.0.0.1, 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 |
| i5follow | bearer | localhost-to-ip | on | 127.0.0.1, 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 | [::1], 127.0.0.1 |
| i8 | basic | other-host | - | 127.0.0.1, 127.0.0.1 | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] |
| i8 | digest | other-host | - | 127.0.0.1, 127.0.0.1, 127.0.0.1, 127.0.0.1 | 127.0.0.1, 127.0.0.1, [::1], [::1] | 127.0.0.1, 127.0.0.1, [::1], [::1] | 127.0.0.1, 127.0.0.1, [::1], [::1] | 127.0.0.1, 127.0.0.1, [::1], [::1] |
| i8 | bearer | other-host | - | 127.0.0.1, 127.0.0.1 | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] | 127.0.0.1, [::1] |

- **Digest's round** rides the probe's connection, on every face, method and lane (item 1's right
  credentials, 8 variants with a second request each).
- **A caller's `Expect: 100-continue` and a 417.** libcurl resends a request answered 417 inside the
  transfer, and the caller's header goes out again each time: libcurl drops only its own `Expect`.
  Each resend is a follow `MAXREDIRS` counts, so 8.5.0 and later stop after 31 requests, 47; 7.85.0,
  whose `MAXREDIRS` defaults to -1, ran 90,712 and 90,104 requests in its 5 s, then 28 (`rounds1`,
  the stand-in's count). Over `h2` too. With `MAXREDIRS` -1 (item 7), 8.5.0 also loops to its
  timeout, and 8.20.0 and 8.23.0 stop at 5,001 requests with 100, the response-header cap (8.20.0
  `http.h:160`, `MAX_HTTP_RESP_HEADER_COUNT` 5000; `headers.c:253-256`). Answered 417 once
  (`417once`), the resend carries the header and the body, and passes. Under Digest the probe
  carries the caller's `Expect` with no body, the 417 ends the transfer, and no credentials are sent
  (`rounds13`).
- **401 before any 100:** a wrong Basic password or Bearer token is one request, answered at its
  head, the body never sent; Digest's authenticated request, answered so, ends 401 with no body
  sent (`rounds18`); the right credentials get a 100 and send the body once.
- **`stale=true`:** a third request with the new nonce, and a fourth after a second stale answer,
  then 200, on all five (`rounds55`). Basic and Bearer answered 401 again end there (`rounds57`).
- **The private follow** (`curl-request-following`). Without `UNRESTRICTED_AUTH`, credentials reach
  the same origin's hop and no other: another port (`rounds65`), another host either way
  (`rounds67`), `https` on the same port (`rounds71`) or another. With it, each scheme's
  credentials reach the other origin; Digest there on 7.85.0 at once, with the first origin's
  Digest state, which the stand-in, sharing nonces across its faces, accepts; on 8.5.0 and later
  after a bare request and a new challenge (`rounds80`).
- **`localhost`:** 7.85.0 reached 127.0.0.1, the rest `::1`, which the stand-in serves; no refused
  `::1` was met.

## Item 6: pooled connections, on one engine

Each case's two transfers run one after the other on one engine, but `together` (one batch,
`call-with-engine-held`) and `after-head` (the second submitted once the first's head was in, its
body 1.5 s on). `other-credentials` is `alice` then `bob`, each route's account its own.

### Item 6: transfers on one engine (`i6` lines)

A cell: each request of the step, its connection a letter shared by the case's two steps (A, B ... in order of first use), as in item 1, ⇒ its final status. `together`: both submitted in one batch; `after-head`: the second submitted once the first's head was in.

| case | scheme | face | step | F | O | G | X | C |
|---|---|---|---|---|---|---|---|---|
| digest-twice | digest | http, https, h2 | 1 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| digest-twice | digest | http, https, h2 | 2 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| other-credentials | basic | http, https, h2 | 1 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 |
| other-credentials | basic | http, https, h2 | 2 | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200 | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200 | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200 | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200 | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200 |
| then-none | basic | http, https, h2 | 1 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 |
| then-none | basic | http, https, h2 | 2 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 |
| other-credentials | digest | http, https, h2 | 1 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| other-credentials | digest | http, https, h2 | 2 | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| then-none | digest | http, https, h2 | 1 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| then-none | digest | http, https, h2 | 2 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 |
| other-credentials | bearer | http, https, h2 | 1 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 |
| other-credentials | bearer | http, https, h2 | 2 | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200 |
| then-none | bearer | http, https, h2 | 1 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 |
| then-none | bearer | http, https, h2 | 2 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 | –; A:–/200 ⇒ 200 |
| together | basic | h2 | 1 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 |
| together | basic | h2 | 2 | Basic "bob:pw-b"; B:Basic✓/200 ⇒ 200 | Basic "bob:pw-b"; B:Basic✓/200 ⇒ 200 | Basic "bob:pw-b"; B:Basic✓/200 ⇒ 200 | Basic "bob:pw-b"; B:Basic✓/200 ⇒ 200 | Basic "bob:pw-b"; B:Basic✓/200 ⇒ 200 |
| after-head | basic | h2 | 1 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200; head 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200; head 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200; head 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200; head 200 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200; head 200 |
| after-head | basic | h2 | 2 | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200; first done at second's end #f | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200; first done at second's end #f | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200; first done at second's end #f | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200; first done at second's end #f | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200; first done at second's end #f |
| together | digest | h2 | 1 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| together | digest | h2 | 2 | – → Digest username="bob"; B:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="bob"; B:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="bob"; B:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="bob"; B:–/401 → A:Digest✓/200 ⇒ 200 | – → Digest username="bob"; B:–/401 → B:Digest✓/200 ⇒ 200 |
| after-head | digest | h2 | 1 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200; head 401 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200; head 401 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200; head 401 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200; head 401 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200; head 401 |
| after-head | digest | h2 | 2 | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200; first done at second's end #f | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200; first done at second's end #f | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200; first done at second's end #f | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200; first done at second's end #f | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200; first done at second's end #f |
| together | bearer | h2 | 1 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 |
| together | bearer | h2 | 2 | Bearer "tok-b"; B:Bearer✓/200 ⇒ 200 | Bearer "tok-b"; B:Bearer✓/200 ⇒ 200 | Bearer "tok-b"; B:Bearer✓/200 ⇒ 200 | Bearer "tok-b"; B:Bearer✓/200 ⇒ 200 | Bearer "tok-b"; B:Bearer✓/200 ⇒ 200 |
| after-head | bearer | h2 | 1 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200; head 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200; head 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200; head 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200; head 200 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200; head 200 |
| after-head | bearer | h2 | 2 | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200; first done at second's end #f | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200; first done at second's end #f | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200; first done at second's end #f | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200; first done at second's end #f | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200; first done at second's end #f |

- **No Digest state crosses transfers on a pooled connection:** the second starts bare on the
  first's connection, A, and gets a new challenge (`pooled2`).
- **Each request carries its own credentials,** and a transfer with none sends none, on the
  pooled connection, on every face and lane.
- **`together` over `h2`:** two connections. Under Digest, the second transfer's authenticated
  request moved to the first's connection, A, on 7.85.0 to 8.20.0, and stayed on its own, B, on
  8.23.0 (`pooled48`).
- **`after-head` under Digest:** the first transfer's head, published by its `stream-buffer`, is
  the 401 (`pooled49`), as item 2's streamed response; the second reused the connection.

## Item 7: the twins

Through the hatch on the prototype, beside each scheme's credentials, a `get` to the `http` face
unless named.

### Item 7: the twins (`i7` lines)

A cell: the requests' credentials as the stand-in decoded them (an `AWS4-HMAC-SHA256` header named by its scheme), and `+header N (#K)` for a header no request otherwise carries, with the requests that carried it; the requests, as in item 1 (a verdict ✗ on `AWS4` is the stand-in knowing no such scheme); ⇒ the final status or code. Every case is a `get` to the `http` face with the route's challenge for the scheme, but where named: `AWS_SIGV4-*` to an open route, `*-post` a 64 KiB `post`, `early-401-*` a 1 MiB `post` answered 401 at its head, `stream-*` a streamed 256 KiB body answered 401 at its head.

| twin | scheme | face | F | O | G | X | C |
|---|---|---|---|---|---|---|---|
| control | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=* | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=PLAIN | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| DISALLOW_USERNAME_IN_URL=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| AWS_SIGV4-after | basic | http | AWS4-HMAC-SHA256 +header x-amz-date (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 |
| FAILONERROR=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| FAILONERROR=1-wrong | basic | http | Basic "user:wrong"; Basic✗/401 ⇒ fails 22 | Basic "user:wrong"; Basic✗/401 ⇒ fails 22 | Basic "user:wrong"; Basic✗/401 ⇒ fails 22 | Basic "user:wrong"; Basic✗/401 ⇒ fails 22 | Basic "user:wrong"; Basic✗/401 ⇒ fails 22 |
| NETRC_FILE-beside | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| control | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=* | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=PLAIN | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| DISALLOW_USERNAME_IN_URL=1 | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| AWS_SIGV4-after | digest | http | AWS4-HMAC-SHA256 +header x-amz-date (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 |
| FAILONERROR=1 | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| FAILONERROR=1-wrong | digest | http | – → Digest username="user"; –/401 → Digest✗/401 ⇒ fails 22 | – → Digest username="user"; –/401 → Digest✗/401 ⇒ fails 22 | – → Digest username="user"; –/401 → Digest✗/401 ⇒ fails 22 | – → Digest username="user"; –/401 → Digest✗/401 ⇒ fails 22 | – → Digest username="user"; –/401 → Digest✗/401 ⇒ fails 22 |
| NETRC_FILE-beside | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| control | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=* | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=PLAIN | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| DISALLOW_USERNAME_IN_URL=1 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| AWS_SIGV4-after | bearer | http | AWS4-HMAC-SHA256 +header x-amz-date (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 |
| FAILONERROR=1 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| FAILONERROR=1-wrong | bearer | http | Bearer "wrong"; Bearer✗/401 ⇒ fails 22 | Bearer "wrong"; Bearer✗/401 ⇒ fails 22 | Bearer "wrong"; Bearer✗/401 ⇒ fails 22 | Bearer "wrong"; Bearer✗/401 ⇒ fails 22 | Bearer "wrong"; Bearer✗/401 ⇒ fails 22 |
| NETRC_FILE-beside | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| AWS_SIGV4-before | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| AWS_SIGV4-alone | none | http | AWS4-HMAC-SHA256 +header x-amz-date (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 |
| userinfo-control | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| userinfo-DISALLOW_USERNAME_IN_URL=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| userinfo-digest-control | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| userinfo-digest-DISALLOW_USERNAME_IN_URL=1 | digest | http | –; –/401 ⇒ fails 67 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| NETRC_FILE-alone | none | http | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 |
| NETRC_FILE-HTTPAUTH-basic | basic | http | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 |
| NETRC_FILE-HTTPAUTH-digest | digest | http | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 | –; –/401 ⇒ 401 |
| NETRC_FILE-userinfo-user | basic | http | Basic "netuser:"; Basic✗/401 ⇒ 401 | Basic "netuser:"; Basic✗/401 ⇒ 401 | Basic "netuser:"; Basic✗/401 ⇒ 401 | Basic "netuser:"; Basic✗/401 ⇒ 401 | Basic "netuser:"; Basic✗/401 ⇒ 401 |
| control-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| SASL_AUTHZID-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| SASL_IR-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| SERVICE_NAME-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| KEEP_SENDING_ON_ERROR-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| early-401-control | basic | http | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401 | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401 | **Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401 / Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401** | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401 | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401 |
| early-401-KEEP_SENDING_ON_ERROR=1 | basic | http | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401 | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401 | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401 | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401 | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401 |
| early-401-control | digest | http | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 |
| early-401-KEEP_SENDING_ON_ERROR=1 | digest | http | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 |
| MAXREDIRS=0 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| MAXREDIRS=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| MAXREDIRS=1-stale | basic | http | Basic "user:pass"; Basic✓/401 ⇒ 401 | Basic "user:pass"; Basic✓/401 ⇒ 401 | Basic "user:pass"; Basic✓/401 ⇒ 401 | Basic "user:pass"; Basic✓/401 ⇒ 401 | Basic "user:pass"; Basic✓/401 ⇒ 401 |
| AUTOREFERER=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| SERVICE_NAME | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| SASL_AUTHZID | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| MAXREDIRS=0 | digest | http | –; –/401 ⇒ fails 47 | –; –/401 ⇒ fails 47 | –; –/401 ⇒ fails 47 | –; –/401 ⇒ fails 47 | –; –/401 ⇒ fails 47 |
| MAXREDIRS=1 | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| MAXREDIRS=1-stale | digest | http | – → Digest username="user"; –/401 → Digest✓/401 ⇒ fails 47 | – → Digest username="user"; –/401 → Digest✓/401 ⇒ fails 47 | – → Digest username="user"; –/401 → Digest✓/401 ⇒ fails 47 | – → Digest username="user"; –/401 → Digest✓/401 ⇒ fails 47 | – → Digest username="user"; –/401 → Digest✓/401 ⇒ fails 47 |
| AUTOREFERER=1 | digest | http | – → Digest username="user" +header referer (#2); –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user" +header referer (#2); –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user" +header referer (#2); –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user" +header referer (#2); –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user" +header referer (#2); –/401 → Digest✓/200 ⇒ 200 |
| SERVICE_NAME | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| SASL_AUTHZID | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| MAXREDIRS=0 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| MAXREDIRS=1 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| MAXREDIRS=1-stale | bearer | http | Bearer "tok123"; Bearer✓/401 ⇒ 401 | Bearer "tok123"; Bearer✓/401 ⇒ 401 | Bearer "tok123"; Bearer✓/401 ⇒ 401 | Bearer "tok123"; Bearer✓/401 ⇒ 401 | Bearer "tok123"; Bearer✓/401 ⇒ 401 |
| AUTOREFERER=1 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| SERVICE_NAME | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| SASL_AUTHZID | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| MAXREDIRS=0-expect417once | basic | http | Basic dXNlcjpwYXNz; Basic/417 at head{0, closed}·E ⇒ fails 47 | Basic dXNlcjpwYXNz; Basic/417 at head{0, closed}·E ⇒ fails 47 | Basic dXNlcjpwYXNz; Basic/417 at head{0, closed}·E ⇒ fails 47 | Basic dXNlcjpwYXNz; Basic/417 at head{0, closed}·E ⇒ fails 47 | Basic dXNlcjpwYXNz; Basic/417 at head{0, closed}·E ⇒ fails 47 |
| MAXREDIRS=-1-expect417 | basic | http | 40 × Basic dXNlcjpwYXNz → ...; 40 × Basic/417 at head{none sent}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 40 × Basic dXNlcjpwYXNz → ...; 40 × Basic/417 at head{none sent}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 40 × Basic dXNlcjpwYXNz → ...; 40 × Basic/417 at head{none sent}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 28 | 40 × Basic dXNlcjpwYXNz → ...; 40 × Basic/417 at head{none sent}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 100 | 40 × Basic dXNlcjpwYXNz → ...; 40 × Basic/417 at head{none sent}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 100 |
| SERVICE_NAME-alone-HTTPAUTH-basic | basic | http | –; –/200 ⇒ 200 | –; –/200 ⇒ 200 | –; –/200 ⇒ 200 | –; –/200 ⇒ 200 | –; –/200 ⇒ 200 |
| SASL_AUTHZID-alone-HTTPAUTH-basic | basic | http | –; –/200 ⇒ 200 | –; –/200 ⇒ 200 | –; –/200 ⇒ 200 | –; –/200 ⇒ 200 | –; –/200 ⇒ 200 |
| stream-early-401-control | basic | http | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done |
| stream-early-401-KEEP_SENDING_ON_ERROR=1 | basic | http | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401; last put end | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401; last put end | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401; last put end | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401; last put end | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401; last put end |
| stream-early-401-control | basic | h2 | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done |
| stream-early-401-KEEP_SENDING_ON_ERROR=1 | basic | h2 | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ fails 28; last put #f | Basic "user:wrong"; Basic✗/401 at head{part} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done |

- **No change:** `LOGIN_OPTIONS` (`AUTH=*`, `AUTH=PLAIN`), `SASL_AUTHZID`, `SASL_IR`,
  `SERVICE_NAME`, and `DISALLOW_USERNAME_IN_URL` beside credentials by option. `SERVICE_NAME` or
  `SASL_AUTHZID` beside `HTTPAUTH` Basic with no credentials sends nothing, 8.23.0 too, though it
  builds a transfer's credentials from them (`url.c:1376-1386`) (`twins64`).
- **`AWS_SIGV4`** set after `HTTPAUTH` replaces Basic, Digest and Bearer with an
  `AWS4-HMAC-SHA256` header, `x-amz-date` beside it, and `x-amz-content-sha256` too from 8.5.0
  (`twins5`). Set before `HTTPAUTH` Basic, Basic goes out (`twins25`): `AWS_SIGV4`'s setter sets
  `httpauth` to `CURLAUTH_AWS_SIGV4`, so the later setopt wins. Alone beside `USERNAME` and
  `PASSWORD`, it signs.
- **`NETRC_FILE`** naming a file that holds the host, `NETRC` unset: nothing is sent, alone, beside
  `HTTPAUTH`, or beside a URL user, whose password stays empty (`twins31`, `twins34`), on all five.
- **`FAILONERROR` 1:** a wrong password ends 22, not with the 401 (`twins7`).
- **`MAXREDIRS`:** 0 stops Digest after its probe, 47; 1 lets the round through and stops a stale
  answer's third request, 47 (`twins50`, `twins52`); Basic and Bearer are unaffected.
- **`AUTOREFERER` 1** sends `Referer` on Digest's second request, the same URL (`twins53`).
- **`KEEP_SENDING_ON_ERROR` 1:** beside Digest with a whole body, nothing changes. Beside a
  streamed 256 KiB body answered 401 at its head over HTTP/1.1, libcurl sends it whole and the
  producer's last put is the end, where without it the transfer ends under the producer, `done`,
  the body in part, on all five (`twins67`). Beside a 1 MiB whole body so answered, the stand-in
  read it whole on every lane in both runs; without it, in part on F, X and C, whole on O, and
  either on G, a race. Over `h2` the stream is cut as without it, but on 7.85.0 the transfer fails
  28, the producer's put timing out (`twins69`).
- **`DISALLOW_USERNAME_IN_URL` 1 beside URL userinfo** does nothing on a first request on any lane:
  the transfer sets `CURLU`, and libcurl applies the flag only when it parses a URL string
  (`if(!use_set_uh)`, 7.85.0 `url.c:1999-2004`, 8.20.0 `url.c:1560-1565`). On 7.85.0, Digest's
  second request parses it, and fails 67 (`twins30`).

### Every option the HTTP auth path reads

Read in `build/verify/current/curl-7.85.0`, `build/m4s3/src/curl-8.7.1`,
`build/verify/current/curl-8.20.0` and `build/verify/current/curl-8.23.0`, `lib/` unless named:
`http.c`'s output (`output_auth_headers`, `Curl_http_output_auth`), input
(`Curl_http_input_auth`), the auth act and pick (`Curl_http_auth_act`, `pickoneauth`),
`http_should_fail`, `http_digest.c`, `vauth/digest.c`, `vauth/cleartext.c`, `http_aws_sigv4.c`,
and where the user, password, bearer and "auth to other hosts" settings are read (`url.c`,
`transfer.c`, `vauth/vauth.c`, the follow).

| option | what reads it on the auth path | 7.85.0 | 8.7.1 | 8.20.0 | 8.23.0 | owned today |
|---|---|---|---|---|---|---|
| `USERNAME`, `PASSWORD` (and `USERPWD`) | copied for the transfer; Basic's and Digest's user and password; netrc consulted only without `USERNAME` | `transfer.c:1525-1529`, `url.c:3015`, `http_digest.c:108-110` | `transfer.c:704-708`, `url.c:1905`, `1923`, `2729` | `transfer.c:447-453`, `url.c:2485` | `url.c:1376-1386` (`Curl_creds_create`), `http.c:275`, `http_digest.c:147`, `vauth/digest.c:354`, `703` | yes |
| `XOAUTH2_BEARER` | Bearer's token, and whether a 401 needs a round | `http.c:361-369`, `582`, `592`, `761`, `831`; `url.c:3734` | `http.c:340-348`, `511`, `521`, `675`, `752`; `url.c:3449` | `http.c:318-326`, `554`, `564`, `717`, `804`; `url.c:3062` | `url.c:1378`, `http.c:321-330`, `563`, `758` | no |
| `HTTPAUTH` | the schemes wanted | `transfer.c:1448` | `transfer.c:616` | `transfer.c:536` | `transfer.c:503` | no |
| `AWS_SIGV4` | sets `httpauth` to `CURLAUTH_AWS_SIGV4` (`setopt.c`); the signature's provider string | `setopt.c:710-721`, `http_aws_sigv4.c:125`, `http.c:695` | `setopt.c:684-695`, `http_aws_sigv4.c:584`, `http.c:606` | `setopt.c:1956-1966`, `http_aws_sigv4.c:880`, `http.c:656` | `setopt.c:2055-2065`, `http_aws_sigv4.c:814`, `1081-1087`, `http.c:665` | no |
| `UNRESTRICTED_AUTH` | credentials to another host, port or scheme after a follow | `http.c:663-668`, `transfer.c:1667` | `vauth/vauth.c:158`, `transfer.c:848` | `vauth/vauth.c:142`, `http.c:1253` | `vauth/vauth.c:148` | no |
| `NETRC`, `NETRC_FILE` | netrc's credentials, only when `NETRC` is set | `url.c:2999-3033` | `url.c:2724-2746` | `url.c:2480-2507` | `url.c:1275-1323` | `NETRC` yes |
| `LOGIN_OPTIONS` | copied to `conn->options`, which no HTTP code reads | `url.c:3006-3008` | `url.c:2716-2718` | `url.c:2472-2474` | `url.c:1473-1474` | no |
| `DISALLOW_USERNAME_IN_URL` | a flag on parsing a URL string, not a set `CURLU` | `url.c:1999-2004` | `url.c:1809` | `url.c:1560-1565` | `url.c:2109`, `2145` | no |
| `SASL_AUTHZID`, `SERVICE_NAME`, `SASL_IR` | SASL and Negotiate, NTLM, Kerberos (`curl_sasl.c`, `http_negotiate.c`, `http_ntlm.c`); 8.23.0 builds a transfer's credentials from the first two | `url.c:3726` | `url.c:3441` | `url.c:3054` | `url.c:1376-1386` | no |
| `FAILONERROR` | `http_should_fail`; a 401 the auth act gives up on | `http.c:590`, `1113` | `http.c:519`, `1058` | `http.c:486`, `562` | `http.c:495`, `571` | no |
| `KEEP_SENDING_ON_ERROR` | keeps sending a body after an error answer arrives before its end, and not after a 417 | `http.c:4120` | `http.c:3591` | `http.c:4077` | `http.c:4139` | no |
| `MAXREDIRS` (found here) | each auth round and 417 resend sets `newurl`, a follow it counts | `http.c:628`, `641`, `4117`; `transfer.c:1586-1596` | `http.c:554`, `567`, `3588`; `transfer.c:765-775` | `http.c:603`, `617`, `4073`; `http.c:1157-1164` | `http.c:613`, `627`, `4135`; `http.c:1399-1409` | no |
| `AUTOREFERER` (found here) | a `Referer` on each follow, the auth round's included | `transfer.c:1598` | `transfer.c:775` | `http.c:1167` | `http.c:1409` | no |
| `HTTPHEADER` | a caller's `Authorization` replaces Basic and Bearer (`Curl_checkheaders`); SigV4 signs the headers | `http.c:748`, `762` | `http.c:662`, `678` | `http.c:704`, `721` | `http.c:694`, `743`, `759`; `http_aws_sigv4.c:433` | yes |
| `CUSTOMREQUEST`, `REQUEST_TARGET` | Digest's method and `uri` | the request line handed to `Curl_output_digest` (`http.c:731`) | `http.c:642` | `http.c:683` | `http.c:722`, `1160` | yes |
| `PORT`, `FOLLOWLOCATION` | the follow's credential clearing and the follow | `transfer.c:1667-1672` | `transfer.c:848` | `http.c:1245-1260` | `http.c:1258` | yes |
| `PATH_AS_IS` | SigV4's canonical path, and a parsed URL's path | `url.c:2004` | `url.c:1809` | `url.c:1565` | `http_aws_sigv4.c:1175` | no |

`MAXREDIRS` and `AUTOREFERER` are the two this list adds to the brief's; both are measured above.
`PATH_AS_IS`, like `DISALLOW_USERNAME_IN_URL`, reaches no first request through a `CURLU`, and
SigV4 would be owned with `AWS_SIGV4`; it was not measured. `POSTREDIR` changes the method of a
followed `post` alone, which no public request follows; not measured.

## Item 8: what the high level's redirect would send

Each case is one engine, as a session's: step 1 a `get` with the credentials, answered 302; step 2
a fresh request to the `Location`, as `next-request` builds a hop, the same credentials set again
by the hatch, since today's `next-request` carries no hatch option and the high level has no
credentials key.

### Item 8: a redirect's hops built by hand on one engine (`i8` lines)

Step 1 is a `get` to `http://127.0.0.1` answered 302 once the credentials pass; step 2 a fresh transfer on the same engine to the `Location`, with the same credentials by the hatch. A cell: each request of the two steps, its connection a letter (the same letter in step 2 is step 1's pooled connection), as in item 1; ⇒ each step's final status.

| scheme | target | F | O | G | X | C |
|---|---|---|---|---|---|---|
| basic | same-origin-other-path | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 |
| basic | other-port | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 |
| basic | other-host | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 |
| basic | http-to-https-same-port | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 |
| basic | http-to-https-face | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 |
| digest | same-origin-other-path | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 |
| digest | other-port | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 |
| digest | other-host | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 |
| digest | http-to-https-same-port | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 |
| digest | http-to-https-face | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 |
| bearer | same-origin-other-path | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 |
| bearer | other-port | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 |
| bearer | other-host | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 |
| bearer | http-to-https-same-port | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 |
| bearer | http-to-https-face | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 |
| basic | userinfo-location | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 |
| digest | userinfo-location | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 |
| bearer | userinfo-location | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 |

### Item 8: what each hop's credentials decoded to (`i8` lines)

A cell: each request's credentials as the stand-in decoded them, in order, across the two steps.

| scheme | target | F | O | G | X | C |
|---|---|---|---|---|---|---|
| basic | same-origin-other-path | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" |
| basic | other-port | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" |
| basic | other-host | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" |
| basic | http-to-https-same-port | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" |
| basic | http-to-https-face | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" |
| digest | same-origin-other-path | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" |
| digest | other-port | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" |
| digest | other-host | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" |
| digest | http-to-https-same-port | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" |
| digest | http-to-https-face | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" |
| bearer | same-origin-other-path | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" |
| bearer | other-port | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" |
| bearer | other-host | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" |
| bearer | http-to-https-same-port | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" |
| bearer | http-to-https-face | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" |
| basic | userinfo-location | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" | Basic "user:pass" → Basic "user:pass" |
| digest | userinfo-location | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" | – → Digest username="user" → – → Digest username="user" |
| bearer | userinfo-location | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" | Bearer "tok123" → Bearer "tok123" |

### Item 8: today's origin rule, by `exchange-step` (`o` lines)

A 302 from A to the Location B, the request carrying `Authorization`, `Cookie` and `X-Other`. A cell: the headers the next request keeps (dropped ones are another origin's), and the parts `curl-url-part` gave B (scheme, host, port).

| A | Location B | F | O | G | X | C |
|---|---|---|---|---|---|---|
| http://h.example/a | http://h.example:80/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) |
| http://h.example:80/a | http://h.example/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) |
| https://h.example/a | https://h.example:443/b | next ("Authorization" "Cookie" "X-Other"); B ("https" "h.example" 443) | next ("Authorization" "Cookie" "X-Other"); B ("https" "h.example" 443) | next ("Authorization" "Cookie" "X-Other"); B ("https" "h.example" 443) | next ("Authorization" "Cookie" "X-Other"); B ("https" "h.example" 443) | next ("Authorization" "Cookie" "X-Other"); B ("https" "h.example" 443) |
| http://h.example/a | http://H.EXAMPLE/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "H.EXAMPLE" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "H.EXAMPLE" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "H.EXAMPLE" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "H.EXAMPLE" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "H.EXAMPLE" 80) |
| http://h.example/a | http://h.example:8080/b | next ("X-Other"); B ("http" "h.example" 8080) | next ("X-Other"); B ("http" "h.example" 8080) | next ("X-Other"); B ("http" "h.example" 8080) | next ("X-Other"); B ("http" "h.example" 8080) | next ("X-Other"); B ("http" "h.example" 8080) |
| http://h.example/a | https://h.example/b | next ("X-Other"); B ("https" "h.example" 443) | next ("X-Other"); B ("https" "h.example" 443) | next ("X-Other"); B ("https" "h.example" 443) | next ("X-Other"); B ("https" "h.example" 443) | next ("X-Other"); B ("https" "h.example" 443) |
| http://h.example/a | https://h.example:80/b | next ("X-Other"); B ("https" "h.example" 80) | next ("X-Other"); B ("https" "h.example" 80) | next ("X-Other"); B ("https" "h.example" 80) | next ("X-Other"); B ("https" "h.example" 80) | next ("X-Other"); B ("https" "h.example" 80) |
| http://127.0.0.1/a | http://localhost/b | next ("X-Other"); B ("http" "localhost" 80) | next ("X-Other"); B ("http" "localhost" 80) | next ("X-Other"); B ("http" "localhost" 80) | next ("X-Other"); B ("http" "localhost" 80) | next ("X-Other"); B ("http" "localhost" 80) |
| http://h.example/a | /b | next ("Authorization" "Cookie" "X-Other"); B (refused "Exception in chez-curl: Bad scheme with irritant \"/b\"") | next ("Authorization" "Cookie" "X-Other"); B (refused "Exception in chez-curl: Bad scheme with irritant \"/b\"") | next ("Authorization" "Cookie" "X-Other"); B (refused "Exception in chez-curl: Bad scheme with irritant \"/b\"") | next ("Authorization" "Cookie" "X-Other"); B (refused "Exception in chez-curl: Bad scheme with irritant \"/b\"") | next ("Authorization" "Cookie" "X-Other"); B (refused "Exception in chez-curl: Bad scheme with irritant \"/b\"") |
| http://[::1]/a | http://[::1]:80/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "[::1]" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "[::1]" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "[::1]" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "[::1]" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "[::1]" 80) |
| http://u:p@h.example/a | http://h.example/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) |
| http://h.example/a | http://u:p@h.example/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) |

- **Every hop sends the credentials it is given:** another port, another host (`hops3`), `https`
  on the same port or the `https` face; libcurl's own "auth to other hosts" rule never applies,
  since each hop is a first request.
- **Each Digest hop starts a round of its own,** bare then authenticated, a fresh handle with no
  Digest state (`hops7`). A same-origin hop reuses step 1's connection, A; any other origin opens B.
- **A `Location` holding `u2:p2@`** beside `USERNAME` and `PASSWORD`: the options' `user:pass` goes
  out, Basic and Digest, on all five (`hops16`); the URL's userinfo is unused. With both set, the
  auth probe's table has the same answer (its `O3` column).
- **Today's origin rule** (`o` lines, `exchange-step` on a crafted 302): `http://h.example/` and
  `http://h.example:80/` are one origin, so is `https://…:443`, and a host differing in case; the
  request keeps `Authorization` and `Cookie`. Another port, scheme (`https://h.example:80/` too)
  or host (`localhost` from `127.0.0.1`) drops both. A relative `/b` stays in the origin. A
  `Location` holding userinfo on the same origin keeps them, and the next URL holds the userinfo.

## Addition: `MAXREDIRS` beside a loop, a stale Digest and a round

Asked after the first hand-back, and run apart so that `auth.sps` and the hash its logs record
stay as they are: `maxredirs.sps`, one part, `maxredirs`, its helpers `auth.sps`'s, copied, on the
prototype, against the same stand-in (`stale=1000000` for the route that answers stale for ever),
on every lane, two runs, into `results/maxredirs-guix-8.20.0-{1,2}.log` and
`results/maxredirs-docker-{1,2}.log`, whose program hash is `2e61f827…` and whose stand-in,
`src/` and prototype hashes are the main logs'. Its tags are `maxredirs1` to `maxredirs10`: the
five cases at libcurl's default, then the same five at 30, in the table's order.

### MAXREDIRS beside a loop, a stale Digest and a round (`mr` lines, `maxredirs.sps`)

Each case on an engine of its own, `timeout-ms` 5,000, MAXREDIRS unset (libcurl's default: -1 on 7.85.0, 30 from 8.7.1) or set to 30 by the hatch. `expect417`: rounds1's case, a 64 KiB `post` with a caller's `Expect: 100-continue`, the stand-in answering 417 to every request carrying it; `stale-forever`: Digest against a route that answers every valid response 401 `stale=true`, a new nonce each time; `round`: Digest against a route that challenges once. A cell: the requests the stand-in counted (`over 1,000` past it, the exact counts in the next table), the last one's status, ⇒ the final status or code.

| case | scheme | MAXREDIRS | F | O | G | X | C |
|---|---|---|---|---|---|---|---|
| expect417 | basic | unset | over 1,000 requests, the last 417 ⇒ fails 28 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 |
| expect417 | bearer | unset | over 1,000 requests, the last 417 ⇒ fails 28 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 |
| expect417 | digest | unset | 1 request, the last 417 ⇒ 417 | 1 request, the last 417 ⇒ 417 | 1 request, the last 417 ⇒ 417 | 1 request, the last 417 ⇒ 417 | 1 request, the last 417 ⇒ 417 |
| stale-forever | digest | unset | over 1,000 requests, the last 401 ⇒ fails 28 | 31 requests, the last 401 ⇒ fails 47 | 31 requests, the last 401 ⇒ fails 47 | 31 requests, the last 401 ⇒ fails 47 | 31 requests, the last 401 ⇒ fails 47 |
| round | digest | unset | 2 requests, the last 200 ⇒ 200 | 2 requests, the last 200 ⇒ 200 | 2 requests, the last 200 ⇒ 200 | 2 requests, the last 200 ⇒ 200 | 2 requests, the last 200 ⇒ 200 |
| expect417 | basic | 30 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 |
| expect417 | bearer | 30 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 | 31 requests, the last 417 ⇒ fails 47 |
| expect417 | digest | 30 | 1 request, the last 417 ⇒ 417 | 1 request, the last 417 ⇒ 417 | 1 request, the last 417 ⇒ 417 | 1 request, the last 417 ⇒ 417 | 1 request, the last 417 ⇒ 417 |
| stale-forever | digest | 30 | 31 requests, the last 401 ⇒ fails 47 | 31 requests, the last 401 ⇒ fails 47 | 31 requests, the last 401 ⇒ fails 47 | 31 requests, the last 401 ⇒ fails 47 | 31 requests, the last 401 ⇒ fails 47 |
| round | digest | 30 | 2 requests, the last 200 ⇒ 200 | 2 requests, the last 200 ⇒ 200 | 2 requests, the last 200 ⇒ 200 | 2 requests, the last 200 ⇒ 200 | 2 requests, the last 200 ⇒ 200 |

### MAXREDIRS: the requests counted and the time to the end, run 1; run 2 (not compared)

A cell: the stand-in's count of the transfer's requests, and ms from the submit to the end.

| case | scheme | MAXREDIRS | F | O | G | X | C |
|---|---|---|---|---|---|---|---|
| expect417 | basic | unset | 92457 req, 5008.3 ms; 90548 req, 5007.4 ms | 31 req, 13.9 ms; 31 req, 24.0 ms | 31 req, 14.2 ms; 31 req, 13.9 ms | 31 req, 14.3 ms; 31 req, 24.2 ms | 31 req, 24.2 ms; 31 req, 24.1 ms |
| expect417 | bearer | unset | 90505 req, 5008.1 ms; 87941 req, 5007.4 ms | 31 req, 14.7 ms; 31 req, 13.9 ms | 31 req, 7.5 ms; 31 req, 13.8 ms | 31 req, 13.9 ms; 31 req, 13.7 ms | 31 req, 14.1 ms; 31 req, 14.1 ms |
| expect417 | digest | unset | 1 req, 5.8 ms; 1 req, 5.7 ms | 1 req, 1.9 ms; 1 req, 1.5 ms | 1 req, 1.0 ms; 1 req, 1.4 ms | 1 req, 2.3 ms; 1 req, 2.6 ms | 1 req, 1.0 ms; 1 req, 2.7 ms |
| stale-forever | digest | unset | 42826 req, 5001.1 ms; 42689 req, 5003.6 ms | 31 req, 13.6 ms; 31 req, 13.5 ms | 31 req, 23.6 ms; 31 req, 13.5 ms | 31 req, 13.5 ms; 31 req, 13.6 ms | 31 req, 13.5 ms; 31 req, 23.6 ms |
| round | digest | unset | 2 req, 7.2 ms; 2 req, 7.5 ms | 2 req, 2.2 ms; 2 req, 2.1 ms | 2 req, 2.1 ms; 2 req, 2.1 ms | 2 req, 2.1 ms; 2 req, 2.1 ms | 2 req, 1.3 ms; 2 req, 2.2 ms |
| expect417 | basic | 30 | 31 req, 4.5 ms; 31 req, 4.5 ms | 31 req, 7.6 ms; 31 req, 13.7 ms | 31 req, 7.6 ms; 31 req, 14.1 ms | 31 req, 13.7 ms; 31 req, 13.8 ms | 31 req, 14.1 ms; 31 req, 7.5 ms |
| expect417 | bearer | 30 | 31 req, 7.6 ms; 31 req, 7.6 ms | 31 req, 7.6 ms; 31 req, 7.3 ms | 31 req, 7.6 ms; 31 req, 7.6 ms | 31 req, 7.2 ms; 31 req, 7.4 ms | 31 req, 4.1 ms; 31 req, 7.4 ms |
| expect417 | digest | 30 | 1 req, 1.4 ms; 1 req, 1.7 ms | 1 req, 1.9 ms; 1 req, 1.5 ms | 1 req, 1.0 ms; 1 req, 1.5 ms | 1 req, 2.6 ms; 1 req, 3.0 ms | 1 req, 1.5 ms; 1 req, 1.5 ms |
| stale-forever | digest | 30 | 31 req, 7.1 ms; 31 req, 7.2 ms | 31 req, 13.5 ms; 31 req, 7.0 ms | 31 req, 13.4 ms; 31 req, 7.0 ms | 31 req, 13.5 ms; 31 req, 13.9 ms | 31 req, 13.4 ms; 31 req, 13.5 ms |
| round | digest | 30 | 2 req, 1.3 ms; 2 req, 1.3 ms | 2 req, 3.8 ms; 2 req, 3.8 ms | 2 req, 3.8 ms; 2 req, 2.2 ms | 2 req, 3.8 ms; 2 req, 2.2 ms | 2 req, 2.3 ms; 2 req, 2.2 ms |

| lane | run | exits | self-test | native counts | hung | error lines |
|---|---|---|---|---|---|---|
| F | 1 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |
| O | 1 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |
| G | 1 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |
| X | 1 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |
| C | 1 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |
| F | 2 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |
| O | 2 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |
| G | 2 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |
| X | 2 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |
| C | 2 | maxredirs exited 0 | standin selftest ok 13; standin selftest exit=0 | 0 nonzero | 0 | 0 |

- **7.85.0 at `MAXREDIRS` 30 stops at 31 requests with 47,** rounds1's case under Basic
  (`maxredirs6`) and Bearer (`maxredirs7`), as 8.5.0 and later do at their default, 30, and at 30
  set. At its default, -1, it ran 92,457 and 90,548 requests in its 5 s (Basic, `maxredirs1`), then
  28.
- **Under Digest** the probe carries the caller's `Expect` with no body, the 417 ends the
  transfer at once, one request, 417, at either value (`maxredirs3`, `maxredirs8`).
- **A Digest route answering `stale=true` for ever:** at libcurl's default 7.85.0 sends 42,826 and
  42,689 requests until its timeout, 28 (`maxredirs4`); every other lane stops at 31, 47; at 30 set,
  every lane stops at 31, 47 (`maxredirs9`). Each stale answer's resend is a follow `MAXREDIRS`
  counts, as item 7's `MAXREDIRS=1-stale` row showed.
- **A Digest round challenged once** ends 200 in two requests at 30, as at the default, on all five
  (`maxredirs5`, `maxredirs10`).

## The Valgrind pass

Items 1, 2 and 6 on lane O under the memory gate's options (`-v --command-line-only=yes
--log-file=… --error-exitcode=9 --leak-check=full --show-leak-kinds=definite
--errors-for-leak-kinds=definite`), every bound auth.sps waits multiplied by 10. Compared by code,
final status and each request's status alone, since a failure's code can race under Valgrind
(AGENTS.md).


474 transfers (items 1, 2 and 6); 474 give the same code, status and statuses of each request as both native runs. schemes exited 0, streams exited 0, pooled exited 0.

- `valgrind schemes:     definitely lost: 0 bytes in 0 blocks`
- `valgrind schemes:  ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)`
- `valgrind streams:     definitely lost: 0 bytes in 0 blocks`
- `valgrind streams:  ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)`
- `valgrind pooled:     definitely lost: 0 bytes in 0 blocks`
- `valgrind pooled:  ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)`

No transfer differs.


The control, the same comparison against lane F's native runs:

474 transfers (items 1, 2 and 6); 470 give the same code, status and statuses of each request as both native runs. schemes exited 0, streams exited 0, pooled exited 0.

| case | Valgrind | native run 1 | native run 2 |
|---|---|---|---|
| i2 scheme=digest case=right kind=sized when=normal face=h2 | 200, 2 req, 401/200 | fails 28, 1 req, - | fails 28, 1 req, - |
| i2 scheme=digest case=wrong kind=sized when=normal face=h2 | 401, 2 req, 401/401 | fails 28, 1 req, - | fails 28, 1 req, - |
| i2 scheme=digest case=right kind=chunked when=normal face=h2 | 200, 2 req, 401/200 | fails 28, 1 req, - | fails 28, 1 req, - |
| i2 scheme=digest case=wrong kind=chunked when=normal face=h2 | 401, 2 req, 401/401 | fails 28, 1 req, - | fails 28, 1 req, - |


The `possibly lost` lines (336 bytes in one block in `streams` and `pooled`) are no gate's
concern: the gate fails on errors and definite leaks alone.

## Against ADR-0036, the plan's §3.3 and §3.7, and the auth probe

| claim | through the engine |
|---|---|
| ADR-0036: `USERNAME` and `PASSWORD` set both, no userinfo, send the same bytes on all five, empty values among them | **not for both empty:** 8.23.0 sends nothing for `USERNAME ""` with `PASSWORD ""`, Basic and Digest, and none for `XOAUTH2_BEARER ""` (item 3); one empty, the other not, alike on all five |
| ADR-0036: unset, `BASIC` and `BEARER` send credentials at once and never a second; Digest a bare request then one more | confirmed for `BASIC`, `BEARER` and `DIGEST`, every face; and under `DIGEST` a `post` to a server that answers the probe 200 is sent twice (item 1) |
| ADR-0036: MD5, MD5-sess, SHA-256, SHA-256-sess on all five, SHA-512-256 on 8.20.0 and 8.23.0 alone | confirmed, each with `qop=auth`, and without `qop` for the non-`-sess` ones; `-sess` without `qop` sends no Digest |
| ADR-0036: a wrong password ends with a final 401 and code 0 | confirmed, but beside `FAILONERROR` 1, which makes it 22 (item 7) |
| ADR-0036: no Digest state crosses fresh easy handles | confirmed through the engine, on a pooled connection too (item 6); but with `UNRESTRICTED_AUTH` 1, 7.85.0's private follow carries it to another origin inside one transfer (item 5) |
| ADR-0036, decision 3: Digest's second request rides a pooled connection; it hung over HTTP/2 on 7.85.0 | the hang holds through the engine, 28 at the transfer's timeout (item 2); here every round rode its own probe's connection, each case on a fresh engine |
| ADR-0036, decision 4; plan §3.3: CR LF in a Bearer token and a Digest user name write a header of their own; 8.23.0 percent-encodes the Digest name | confirmed, over HTTP/1.1 and over `h2` (item 4) |
| plan §3.3: refuse NUL, CR, LF and each byte the header rule refuses | the hatch refuses NUL, CR and LF today; 0x01 to 0x1F but TAB, and 0x7F, go out raw over HTTP/1.1 on all five, a bare CR or LF inside its line; over `h2` the server's stack drops 0x01, 0x1F and 0x7F, and a bare LF fails 43 |
| plan §3.3: `AWS_SIGV4` after `HTTPAUTH` Basic replaced it | confirmed through the engine, for Digest and Bearer too; before `HTTPAUTH`, `HTTPAUTH` wins |
| plan §3.3: measure `LOGIN_OPTIONS`, `DISALLOW_USERNAME_IN_URL`, `UNRESTRICTED_AUTH` | `LOGIN_OPTIONS` changes nothing; `DISALLOW_USERNAME_IN_URL` changes no first request, and on 7.85.0 refuses Digest's round beside userinfo, 67; `UNRESTRICTED_AUTH` sends credentials across origins in the private follow, which nothing public sets |
| plan §3.3: a streamed body or response takes Basic or Bearer, one request each | confirmed, over `http` and `h2`, on all five |
| plan §3.7: a UTF-8 Digest user name on 8.23.0 | percent-encoded and refused by a server hashing the name it reads, by `USERNAME` as from the URL; and every byte below 0x20 and from 0x7F, not UTF-8 alone |
| auth probe: libcurl's 1 s `Expect` timeout never ran | here neither: the stand-in answers each `Expect` at once |
| auth probe: an early 401 with a paused read callback ends at its next piece on 7.85.0 and 8.5.0 | the engine's producer did not pause, and every lane ended within 10 ms |

## What split

- **Between the kept runs:** three cells, each how much of a body cut short the stand-in read, or
  how its stream ended:
  - item 2, `basic | wrong | sized | mid | h2` on X: the producer's last put `done` in run 1,
    `end` in run 2 (libcurl took the last piece before the 401 arrived);
  - item 2, `bearer | wrong | sized | mid | h2` on O: the stream closed in run 1, ended in run 2;
  - item 7, `early-401-control | basic` on G: the 1 MiB body read in part in run 1, whole in run 2.

  How many bytes the stand-in read of a body cut short races in every such cell; the compared cells
  keep `{whole}` or `{part}`, and the times table shows each count, run by run.
- **Between lanes, every other difference follows the version,** but those same races: whether an
  `h2` stream answered early closed or ended (8.5.0 against the rest), and whether a 1 MiB body was
  read whole. The two 8.5.0 builds agree in every cell but such races.
- **Through the engine against the C probe:** the 100 ms on 7.85.0 and 8.5.0 for an early 401
  beside a paused producer is gone, since nothing paused (item 2).

## Not measured, and why

- **Apple's 8.7.1.** No Mac script was written, by the brief: the Mac runs `make test` on the PR.
  Its auth path is in the source list.
- **What libcurl writes on the wire over `h2`** for a field the stand-in's HTTP/2 stack drops: the
  stand-in cannot see it, so libcurl's own trace stands for it (`i4trace`); no raw HTTP/2 parser
  was written.
- **A server that splits a Basic credential at its first colon:** the stand-in compares the whole
  decoded bytes; the cell names the user such a server would read.
- **`PATH_AS_IS`, `POSTREDIR`:** read in source above, not measured.
- **Proxy auth, NTLM, Negotiate:** slice 3's, or out of M7 (ADR-0033).
- **The 417 loop's count on 7.85.0** is the requests made before its 5 s timeout, which the machine's
  speed sets: 90,712 and 90,104 here; the cells say "over 1,000".

## Files

- `auth.sps`: the program; its header lists each part.
- `maxredirs.sps`: the MAXREDIRS addition's program, run by `run.sh` with `PROGRAM=maxredirs.sps`.
- `standin.mjs`: the stand-in; its header lists every face, route and log line.
- `run.sh`: one lane, every part or those named; `VALGRIND=1` for the gate's Valgrind.
- `docker.sh`: the four Docker lanes, one `--rm ubuntu:24.04`.
- `all.sh`: the prototype, then both runs of every lane, then the Valgrind pass, into `results/`.
- `make-prototype.sh`, `prototype.diff`: the prototype in `build/m7s2/src`.
- `tables.mjs`: every table here, from `results/`; `--valgrind` the Valgrind comparison.
- `wire.mjs`, `wire-control.sh`, `selftest-control.sh`: the wire check, and the controls.
- `results/`: the kept logs, `guix-8.20.0-{1,2}.log`, `docker-{1,2}.log`,
  `valgrind-ubuntu-openssl-8.5.0.log`; `wire-check.log`, `wire-control-guix-8.20.0.log`,
  `selftest-control-guix-8.20.0.log`, `valgrind-control.log`; the addition's
  `maxredirs-guix-8.20.0-{1,2}.log` and `maxredirs-docker-{1,2}.log`.
