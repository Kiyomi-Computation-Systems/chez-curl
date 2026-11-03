# M7 slice 3 research: a proxy given by URL, through the engine

Measured 2026-11-02 for M7 slice 3 ([plan](../../../2026-11-02-m7-plan.md), section 6.1;
[ADR-0037](../../../decisions/0037-a-proxy-given-by-url.md)). Every transfer went through
chez-curl's engine, on a prototype copy of `src/` whose `proxy` field takes a URL, and whose hatch
reaches `NOPROXY`, the proxy's TLS options and `FRESH_CONNECT`; the hatch's refusals and the URL
parse ran on main's `src/`. Five Linux libcurls ran it, two runs each, then items 3, 4 and 5 once
more under the memory gate's Valgrind. It reports what libcurl does through the engine. It
recommends nothing. The C probe this builds on is [`../proxies/`](../proxies/); where a cell came
again it is not argued again.

Lanes: **F** `floor-7.85.0`, **O** `ubuntu-openssl-8.5.0`, **G** `ubuntu-gnutls-8.5.0`, **X**
`guix-8.20.0`, **C** `current-8.23.0`. Citations are `FILE:LINE` in `results/`, run 1 unless
named; `tables.mjs --cite=ITEM,FIELD=VALUE,...` prints every run's place for a row.

## In short

- **Item 1, a named proxy beside the environment.** As the C probe found, through the engine, on
  all five, both runs: with `PROXY` named and `NOPROXY` unset, `no_proxy` or `NO_PROXY` naming
  127.0.0.1, or `*`, sends the transfer direct, the h2 one too (`docker-1.log:646` F,
  `guix-8.20.0-1.log:636` X); with `NOPROXY ""` it goes through the named proxy
  (`docker-1.log:635`). `http_proxy`, `https_proxy` and `all_proxy` naming `p-other` lose to the
  named proxy, by absolute form, `CONNECT`, and `CONNECT` with ALPN `h2` inside
  (`docker-1.log:937`), while the control `proxy environment` reaches `p-other`
  (`docker-1.log:982`). Each child printed its environment first: one to four variables, the
  case's, beside `CHEZ_CURL_LIBCURL`, on all 10 lane-runs.
- **Item 2 (a), chez-curl's own parse** (`curl-url-part`, on main): a proxy URL with no port gets
  80 or 443; no scheme fails `bad-scheme` (27) and `foo://` `unsupported-scheme` (5) on all five;
  `ftp://` parses on all five; **`socks5://` parses on 8.23.0 alone**, `unsupported-scheme`
  elsewhere. Percent-escapes in userinfo come back encoded, `%3A` as `%3A`; 7.85.0 reports no
  user for `@` and `:@`, no password for `u:@`, and no user for `:p@`, where 8.5.0 and later
  report `""`. A zone ID comes apart from the host, as `curl-url-part` documents.
- **Item 2 (b), the userinfo on the wire.** Every form libcurl takes is percent-decoded, then sent
  by Basic on the first request, absolute form and `CONNECT` alike; `%3A` in the user puts a
  colon there, so the proxy reads user `a`, password `b:p` (`docker-1.log:1384`); `%7F`, `%FF`,
  `%C3%A9` and raw UTF-8 go out as those bytes (`docker-1.log:1649`); `%20` as a space.
  - **A byte below 0x20 after decoding (`%00`, `%01`, `%09`, `%0D%0A`, `%1F`) sends the transfer
    direct, silently, 200, on 7.85.0 and both 8.5.0 builds; the proxy gets nothing**
    (`docker-1.log:1438` F, `7964` O, `14663` G). 8.20.0 and 8.23.0 fail 3, nothing sent
    (`guix-8.20.0-1.log:1432`, `docker-1.log:21375`). 7.85.0's `parse_proxy` jumps to its error
    label with `result` still `CURLE_OK` when the decode fails, so no proxy host is set
    (`lib/url.c:2512-2517`); 8.20.0 sets the code first (`lib/url.c:2010-2019`).
  - `@` and `:@` send no `Proxy-Authorization` on 7.85.0 and 8.23.0, and `Basic Og==` (`:`) on
    both 8.5.0s and 8.20.0 (`docker-1.log:1237`).
- **Item 2 (c), the port read, not inferred** (Docker, listeners on 80, 443 and 1080): `http://`
  with no port, and no scheme with no port, connect to 1080 on F, O and G, and to 80 on C
  (`docker-1.log:1803`, `21677`); `https://` with no port connects to 443 on all four.
- **Item 3, the pooled tunnel.** **7.85.0 reuses an authenticated tunnel for a second request
  with other userinfo, a wrong password, or none:** no new `CONNECT`, the second request rides
  alice's tunnel and answers 200 (`docker-1.log:1934`, `1972`). It does so over `CONNECT` to
  `https://`, over `HTTPPROXYTUNNEL` to `http://`, through an `https://` proxy, and to an `h2`
  origin, where the second goes as stream 3 on the first's connection (`docker-1.log:3377`).
  Both 8.5.0 builds, 8.20.0 and 8.23.0 open a new connection and send the second's own
  credentials: a 407 for wrong or none (`docker-1.log:8513`). By absolute form 7.85.0 reuses the
  connection for another user but sends that user's own `Proxy-Authorization`
  (`docker-1.log:2500`); for wrong or none it opens a new one, on all five. `FRESH_CONNECT` 1 on
  the second, and `FORBID_REUSE` 1 on the first, give a new connection on all five, every mode
  (`docker-1.log:2076`): the reading tells reuse from none. Two submitted in one batch to `h2` by
  `CONNECT` open two tunnels on all five, whatever the userinfo (`docker-1.log:3641`). The
  control, the same userinfo again, reuses in every mode on every lane but two: absolute form
  through an `https://` proxy, where 8.20.0 and 8.23.0 open a new connection even then
  (`guix-8.20.0-1.log:2913`), so the reading there cannot tell; and `CONNECT` through an
  `https://` proxy on G, whose first transfer stalls (below). The engine
  cannot read `NUM_CONNECTS`: no response or condition carries it; the stand-in's connection
  numbers are the reading.
- **Item 4, a refused `CONNECT`.** 403, 407 (none, wrong) and 502 end 56 with `REQUEST_SIZE` 89
  (134 with credentials) on 7.85.0, 56 with 0 on both 8.5.0s, and 7 with 0 on 8.20.0 and 8.23.0
  (`docker-1.log:3942`, `10563`, `guix-8.20.0-1.log:3845`); the status is in the error buffer's
  text alone, never in chez-curl's condition. A proxy that closes after the head, or writes
  `HTTP/1.1 200` and closes, ends 56 everywhere, size 89 on 7.85.0 and 0 elsewhere; a refused
  port 7, size 0. By absolute form the proxy's 403, 407 and 502 are the response, code 0; the
  closes are 52 with the request's size. **The high level's retry differs by version:** with the
  policy, a `post` through a refused `CONNECT` is tried once on 7.85.0 (size above 0, `post` not
  in the methods) and three times on the other four (size 0, any method), the proxy logging each
  (`docker-1.log:4064` F, `10685` O); a `get` is tried three times everywhere. A refused port is
  retried for both methods everywhere; a 52 by absolute form for `get` alone.
- **Item 5, the proxy's TLS.** `curl_easy_setopt` takes `PROXY_CAINFO`, a cleared `PROXY_CAPATH`
  and the verify switches with 0 on all five, GnuTLS too; `HAPROXY_CLIENT_IP` is unknown to
  7.85.0. The good leaf passes with `PROXY_CAINFO` the run CA and `PROXY_CAPATH` cleared; the
  expired, wrong-host and untrusted leaves fail 60 with nothing sent, and pass with both switches
  off. The origin's `ca-file` and `verify` and the proxy's are apart: each side fails while the
  other passes, both ways; an origin refused through the tunnel is 35 on O, 60 elsewhere, with
  size 89 on F (`docker-1.log:4627`). On Guix's 8.20.0, `SSL_CERT_FILE` and `SSL_CERT_DIR` win
  over `PROXY_CAINFO`, cleared `PROXY_CAPATH` or not: the run CA in the variable passes beside a
  `PROXY_CAINFO` of the other CA, and the other CA in it fails the run CA
  (`guix-8.20.0-1.log:4676`, `4706`); the other four ignore both.
  - **The stall:** on G an `https://` origin, and an `h2` one, through an `https://` proxy end 28
    at 10 s, 10 of 10 in each run, the request sent (`REQUEST_SIZE` 64 to 67) and the origin's
    200 tunnelled back (`docker-1.log:18170`); an `http://` origin through it passes. **On F an
    `h2` origin through an `https://` proxy stalls the same way at times: 3 and 2 of 10 in the
    kept runs, then 1, 1 and 0 of 10 in three more, 7 of 50** (`docker-1.log:5083`,
    `supplement-stall-floor-7.85.0-1.log:307`); its HTTP/1.1 case passed 50 of 50. O, X and C
    passed every case.
- **Item 6, the twins.** On main the hatch takes `HTTPPROXYTUNNEL`, `SUPPRESS_CONNECT_HEADERS`,
  `PROXY_SERVICE_NAME`, `SOCKS5_AUTH`, `HAPROXYPROTOCOL`, `HAPROXY_CLIENT_IP` (but on 7.85.0,
  `unknown-option`), and `PROXYAUTH`, `PROXYUSERPWD`, `PROXYUSERNAME` and `PROXYPASSWORD`.
  - `HTTPPROXYTUNNEL` 1 turns an `http://` origin's absolute form into a `CONNECT` with no
    caller header on it; the caller's `X-Caller` and `Proxy-Authorization` then reach the origin
    inside the tunnel, where by absolute form both reached the proxy (`docker-1.log:5392`).
    `HTTPPROXYTUNNEL` 0 changes nothing for an `https://` origin, which tunnels anyway.
  - `SUPPRESS_CONNECT_HEADERS` changes nothing chez-curl reads: the `CONNECT` 200's
    `X-Tunnel` header is in neither the response's headers nor a streamed head, with it or
    without, on all five (`docker-1.log:5491`).
  - `PROXY_SERVICE_NAME` and `SOCKS5_AUTH` change no byte either side got.
  - `HAPROXYPROTOCOL` 1 writes a PROXY v1 line: by absolute form as the proxy connection's first
    bytes; through a `CONNECT` tunnel inside it, first to the origin, which fails a TLS origin's
    handshake, 35, on all five (`docker-1.log:5602`), and which 7.85.0 writes twice
    (`docker-1.log:5614`). `HAPROXY_CLIENT_IP` replaces the source address on both 8.5.0s, and
    the source and destination on 8.20.0 and 8.23.0 (8.20.0's `lib/cf-haproxy.c:90-93`).
- **Item 7, prior knowledge through a named proxy:** confirmed on the prototype, both runs, all
  five: through the plain proxy the request goes as HTTP/1.1 in absolute form, which the proxy
  answers, 200 over 1.1; with `HTTPPROXYTUNNEL` 1 it speaks HTTP/2 to the h2c origin inside the
  tunnel (`docker-1.log:5645`, `5651`).
- **Item 8, the high level.** The prototype's proxy string reaches every hop: a session's `proxy`
  and a call's replacing it (bob's credentials, `#f` direct, `environment` direct with no
  variable set); a redirect from `http://` to another `http://` origin goes by absolute form, to
  `https://` by `CONNECT`, each hop with the proxy URL's `Proxy-Authorization`
  (`docker-1.log:5795`). The `credentials` key's `Authorization` goes to the proxy beside the
  proxy's by absolute form, and inside the tunnel alone by `CONNECT`; Digest's second request
  rides the first's proxy connection; across a redirect to another origin the `Authorization`
  goes, the `Proxy-Authorization` stays (`docker-1.log:5926`). Alike on all five.
- **Item 9, the sent rule.** A proxied transfer that passes sends its request; read from its twin
  at `body-limit` 1, which fails 63 after the send, `REQUEST_SIZE` is the bytes the stand-in got
  from libcurl: the absolute-form request on all five, the origin's request alone through a
  tunnel on 8.5.0 and later, and the `CONNECT` plus it on 7.85.0 (155 against 66;
  `docker-1.log:6103`). Of item 4's failures, each through a `CONNECT` reads 0 but on 7.85.0,
  where it reads the `CONNECT`'s bytes, and so does an origin's TLS failure inside the tunnel
  (89); by absolute form a proxy's close reads the request's bytes (120, 121) on all five.
- **The checks:** 10 lane-runs, 24 processes each, all exit 0; 509 transfers each (499 on X, which
  has no low ports), none hung, no socket open at a log's end, no log fetch failed, native counts
  0 at every process's end. The wire check matched 90 of 90 heads, the Valgrind pass gave 301 of
  301 rows as both native runs, 0 errors, 0 bytes definitely lost.
- **What split between the kept runs:** one cell, F's `h2` stall count (3 and 2 of 10), a race.

## What bears on the open questions

- **`FRESH_CONNECT` beside proxy userinfo:** needed on 7.85.0 alone of the five. There a pooled,
  authenticated tunnel carries a later request with another user's, a wrong, or no userinfo, over
  `CONNECT`, over `HTTPPROXYTUNNEL`, through an `https://` proxy, and as another stream of an `h2`
  connection inside the tunnel; `FRESH_CONNECT` 1 stopped it every time. Absolute form needs it
  less: 7.85.0 reuses the connection for another user, but each request carries its own
  credentials and the proxy judges each; wrong and none open new connections everywhere. Two
  submitted together never shared a tunnel. Both 8.5.0 builds behave as 8.20.0 and 8.23.0, which
  the plan had from source alone. Apple's 8.7.1 is `mac.sh`'s.
- **`HTTPPROXYTUNNEL`, owned or the hatch's:** it changes what the proxy field sends: an
  `http://` origin's request moves from the proxy, in absolute form, to the origin, inside a
  tunnel, with every caller header (a `Proxy-Authorization` among them, which slice 3 refuses
  anyway); it lets prior knowledge speak HTTP/2 through a named proxy (item 7); and with
  `HAPROXYPROTOCOL` it moves the PROXY line from the proxy to the origin.
- **The refused `CONNECT` and the retry (ADR-0022):** the code is 56 on 7.85.0 and both 8.5.0s,
  7 on 8.20.0 and 8.23.0; the size is the `CONNECT`'s on 7.85.0 and 0 elsewhere. So
  `retried-failure?` repeats a refused `CONNECT` (403, 407, 502, a close) for any method on
  8.5.0 and later, a `post` included, and for the policy's methods alone on 7.85.0, `get` but
  not `post`: the same failure retried differently by version. Each retry of a 407 with wrong
  credentials is another failed authentication at the proxy (3 per call here).
- **`proxy-tls-in-tls`' list:** G, for `https://` and `h2` origins, every time; F, for an `h2`
  origin alone, 7 of 50; O, X and C never. An `http://` origin through an `https://` proxy passed
  everywhere. A stalled transfer had sent its request (`REQUEST_SIZE` above 0), so a policy
  retries it for its methods alone.
- **The userinfo byte rule after decoding:** libcurl percent-decodes the URL's userinfo, then
  base64-encodes it, so no byte reaches a header raw. But a decoded byte from 0x00 to 0x1F makes
  7.85.0 and both 8.5.0s drop the proxy and go direct, 200, where 8.20.0 and 8.23.0 fail 3; 0x20,
  0x7F and every byte above go out as they are, a lone 0xFF (no UTF-8) among them; a decoded colon
  in the user ends the user for the proxy; `@` and `:@` send `:` on 8.5.0 and 8.20.0 and nothing
  on 7.85.0 and 8.23.0; and chez-curl's own `curl-url-part` returns the parts still encoded.
- **Each twin:** `HTTPPROXYTUNNEL` and `HAPROXYPROTOCOL` (with `HAPROXY_CLIENT_IP`) change what
  the field sends; `SUPPRESS_CONNECT_HEADERS`, `PROXY_SERVICE_NAME` and `SOCKS5_AUTH` changed no
  byte either side got and nothing chez-curl read, on all five. 8.23.0's `parse_proxy` hands
  `PROXY_SERVICE_NAME` to its credentials (`lib/proxy.c:452-468`), read in source; with no
  userinfo it sent no `Proxy-Authorization` here.
- **The high level's hops:** the proxy URL, and so its `Proxy-Authorization`, reaches every hop,
  another origin's too; `credentials` go within one origin and drop across, as slice 2 built; by
  absolute form a hop's `Authorization` goes to the proxy in the request it forwards.

## Against ADR-0037 and the plan's §3.4

- **§3.4's reasons by chez-curl's own parse:** `curl_url` with no flags refuses a URL with no
  scheme (27) and any scheme it does not know (5), so `foo://` is `proxy-url`, not `proxy-scheme`;
  `ftp://` parses and is `proxy-scheme`; and `socks5://` is `proxy-url` on 7.85.0 to 8.20.0 and
  `proxy-scheme` on 8.23.0, which registers the SOCKS schemes (8.23.0's `lib/protocol.c:364-371`,
  checked at `lib/urlapi.c:1044-1046`). A no-scheme proxy URL, which libcurl reads as `http://`,
  is refused.
- **"held to `credentials-bytes`' rule":** the rule must read the userinfo decoded. Encoded, every
  form is ASCII and passes; decoded, a control byte sends the transfer around the named proxy on
  7.85.0 and 8.5.0, against decision 2's "a named proxy takes every transfer"; and a decoded byte
  above 0x7F need not be UTF-8 (`%FF`), which the rule's "a char above U+007F" does not cover. An
  empty user and password (`@`, `:@`) send differently by version, as slice 2's
  `credentials-empty` cases did.
- **"7.85.0 matches a pooled proxy connection by type, host and port alone, where 8.20.0 and 8.23.0
  compare the user and password too":** measured, and both 8.5.0 builds compare them too.
- **"An `https://` origin through an `https://` proxy is refused on Ubuntu's 8.5.0 with GnuTLS":**
  an `h2` origin stalls there too, and on 7.85.0 at times, which the decision's list does not
  hold.
- **"`REQUEST_SIZE` counts a `CONNECT` on 7.85.0 alone":** confirmed, and it counts one whose
  origin then refused the TLS handshake (89 with nothing at the origin).
- Everything else ADR-0037 and §3.4 state came again through the engine: `NOPROXY ""`, the
  variables losing to a named proxy, Basic on the first request, the caller's headers inside a
  tunnel, the proxy's TLS apart from the origin's, Guix's variables over `PROXY_CAINFO`, the
  refused `CONNECT`'s code, and the ports with none named (1080, and 80 on 8.23.0).

## Source read, to explain a split

- **The control byte that goes direct:** 7.85.0's `parse_proxy` decodes the user with
  `CURLU_URLDECODE` and, on any failure but "no user", jumps to `error` with `result` still
  `CURLE_OK` (`lib/url.c:2512-2517`), so it returns OK before the proxy host is set, and the
  connection has no HTTP proxy (`lib/url.c:2762`). 8.20.0 sets `Curl_uc_to_curlcode(uc)` first
  (`lib/url.c:2010-2019`): 3. 8.5.0's source is not on this host; it behaves as 7.85.0.
- **The pooled tunnel:** 8.20.0's `proxy_info_matches` compares the user and password
  (`lib/url.c:575-588`), called for an HTTP proxy at `lib/url.c:891`; 7.85.0's compares type,
  host and port (`lib/url.c:935-944`, the plan's reading).
- **`HAPROXY_CLIENT_IP`:** 8.20.0 sets the destination address to the client address it was given
  (`lib/cf-haproxy.c:90-93`); 8.5.0 kept the connection's own, by the bytes logged.
- **`socks5://`:** above. Not traced: why 7.85.0 writes the PROXY line twice into a tunnel; F's
  intermittent `h2` stall inside an `https://` proxy; and why 8.20.0 and 8.23.0 do not reuse an
  `https://` proxy connection for absolute form, the TLS settings being the same.

## What was run

- **`proxy.sps`, one Chez program in 16 parts,** each its own process: `refusals` (on main's
  `src/` as `refusals-main`, and on the prototype), `setopts`, `urlparse` (item 2 (a), on main),
  `named` (item 1, once in each of 7 environments), `userinfo` (2 (b)), `ports` (2 (c)), `pooled`
  (3), `refused` (4), `tls`, `tlsenv` (once in each of 3 environments) and `stall` (5), `twins`
  (6), `pk` (7), `hl` (8), `sent` (9) and `wire`. Its header lists them. Every request carries
  `timeout-ms` 10,000, and `ca-file` the run CA for an `https://` URL, unless named; each wait is
  bounded at 15,000 ms, and a transfer still running then is cancelled and logged `hung` (none
  was). Each case runs on an engine of its own, but item 3's two transfers and item 8's session.
  Each case is a stand-in case: `/begin` before, `/end` after its engine has stopped, so the log
  holds every connection whole.
- **Every process runs under `env -i`:** its environment is `CHEZ_CURL_LIBCURL` and the variables
  its environment names, which it prints first, from `/proc/self/environ`. No ambient proxy
  variable reaches any case.
- **`make-prototype.sh`** copies `src/` to `build/m7s3/src` and changes `(curl private transfer)`
  alone, 8 lines removed and 11 added (`prototype.diff`), and fails unless it is exactly that:
  1. the `proxy` field takes a string, and the transfer sets `PROXY` to it verbatim;
  2. `owned-option-names` leaves out `NOPROXY` and `proxy-tls-option-names`;
  3. `owned-option-names` leaves out `FRESH_CONNECT`, a streamed body's, so the hatch can set it
     (item 3 needs it on a transfer that streams nothing);
  4. a string option's hatch value may be `#f`, a clear, set as `NULL`: on main `#f` is an
     assertion violation (the `PROXY_SERVICE_NAME-clear` row), and item 5 needs `PROXY_CAPATH`
     cleared.

  The high level passes the string through unchanged: item 8's calls ran on it.
- **`standin.mjs`** (Node's standard library), from [`../proxies/server.mjs`](../proxies/server.mjs):
  origins `o-raw`, `o-raw2` (HTTP/1.1), `o-tls` (TLS, `http/1.1`), `o-h2` (TLS, `h2` alone),
  `o-h2c` (prior knowledge), with routes for a redirect and Basic or Digest at the origin;
  proxies `p-open`, `p-other`, `p-basic` (alice and bob), `p-403`, `p-502`, `p-close`,
  `p-partial`, over TLS `tp-good`, `tp-expired`, `tp-wrong`, `tp-untrusted`, `tp-basic`, a
  refused port, and in Docker `p80`, `p1080` and `tp443`. A proxy tunnels a `CONNECT` and
  forwards an absolute-form request to `o-raw` or `o-raw2` on an upstream connection of its own,
  so the origin's answer comes back; it logs each connection, each head whole, each
  `Proxy-Authorization` and `Authorization` decoded to hex, each tunnel's and forward's upstream,
  and which proxy connection each origin request rode (`via=`). Its header lists every line.
- **Checks on the instrument, each watched failing:**
  - the self-test, `selftest ok 12 (1 planted vector caught)`, first on every lane-run: the
    decoder against eight vectors whose base64 and hex came from `base64(1)` and `od(1)`, and a
    planted vector a byte short that must fail. `selftest-control.sh` splits at the last colon in a
    copy, and the `a:b:c` vector fails, exit 1; makes the planted vector true in another, and it
    fails as a planted vector that passed, exit 1 (`results/selftest-control.log`);
  - the wire check, `wire.mjs`: each request head in libcurl's own trace (`VERBOSE`) against the
    stand-in's, byte for byte: 90 of 90 the same over the kept logs (`results/wire-check.log`);
    `wire-control.sh` runs the part against a copy that logs each head a byte short: 18
    `DIFFERS`, exit 1, then 9 of 9 the same, exit 0 (`results/wire-control-guix-8.20.0.log`);
  - item 3's reading: the same userinfo again must reuse, and does, and `FORBID_REUSE` 1 must not,
    and does not, on every lane in every mode (the exceptions in "In short");
  - item 1's environment: each child's printed environment, and `no_proxy` sending a named proxy's
    transfer direct with `NOPROXY` unset, so a variable that did not arrive would show;
  - the Valgrind comparison against lane F's native runs instead of lane O's: 67 of 301 rows
    differ (`results/valgrind-control.log`).
- **`tables.mjs`** builds every table below from the kept logs alone, its output unedited; a cell
  the runs disagree on reads `**run 1 / run 2**`, and is listed under "What split".

**The lanes**, from each log's `uname`, `libcurl version=` and `package` lines; all Linux x86_64:

| | lane | where | libcurl | TLS | Node | Chez |
|---|---|---|---|---|---|---|
| F | `floor-7.85.0` | Docker `ubuntu:24.04` (24.04.5 LTS, `sha256:68ee2200…`), `--network none` (`docker-1.log:1-2`) | `build/e1/ci/curl-floor/lib/libcurl.so.4.8.0`, 7.85.0 | OpenSSL 3.0.13 | 20.10.0 | `build/e1/ci/chez-threads`, 10.4.0, threaded |
| O | `ubuntu-openssl-8.5.0` | same container | `/usr/lib/x86_64-linux-gnu/libcurl.so.4.8.0` (libcurl4t64 8.5.0-2ubuntu10.16) | OpenSSL 3.0.13 | 20.10.0 | as F |
| G | `ubuntu-gnutls-8.5.0` | same container | `…/libcurl-gnutls.so.4.8.0` (libcurl3t64-gnutls 8.5.0-2ubuntu10.16) | GnuTLS 3.8.3 | 20.10.0 | as F |
| X | `guix-8.20.0` | the Guix container (`scripts/guix-env`) | `/gnu/store/67lpb53n…-curl-8.20.0/lib/libcurl.so.4.8.0`, 8.20.0 | GnuTLS 3.8.13 | 24.18.0 | the profile's, 10.4.0 |
| C | `current-8.23.0` | same container as F | `build/verify/c823/lane1/curl-current/lib/libcurl.so.4.8.0`, 8.23.0 | OpenSSL 3.0.13 | 20.10.0 | as F |

The Valgrind pass ran lane O in the same image, Valgrind 3.22.0, with the memory gate's options
exactly and no suppression, GNU `timeout` outside it, every bound times 10.

**To rerun,** from the repository's root, on the host:

```sh
sh .plans/research/m7/slice3/all.sh 1 2 valgrind controls   # the prototype, both runs, Valgrind, the controls (about 23 minutes)
# one lane, or some parts:
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice3/run.sh guix-8.20.0 [PART...]' < /dev/null
sh .plans/research/m7/slice3/docker.sh LANES [PART...]          # LANES: all, or a comma list
VALGRIND=1 sh .plans/research/m7/slice3/docker.sh ubuntu-openssl-8.5.0 pooled refused tls stall
# F's h2 stall, three more runs:
for n in 1 2 3; do sh .plans/research/m7/slice3/docker.sh floor-7.85.0 stall < /dev/null > .plans/research/m7/slice3/results/supplement-stall-floor-7.85.0-$n.log 2>&1; done
# the tables, the checks, the Valgrind comparison and its control, the wire check, a row's places:
scripts/guix-env sh -c 'node .plans/research/m7/slice3/tables.mjs' < /dev/null
scripts/guix-env sh -c 'node .plans/research/m7/slice3/tables.mjs --checks' < /dev/null
scripts/guix-env sh -c 'node .plans/research/m7/slice3/tables.mjs --valgrind [--against=floor-7.85.0]' < /dev/null
scripts/guix-env sh -c 'node .plans/research/m7/slice3/wire.mjs .plans/research/m7/slice3/results/*-[12].log' < /dev/null
scripts/guix-env sh -c 'node .plans/research/m7/slice3/tables.mjs --cite=i3,mode=connect-https,second=none' < /dev/null
# the Mac, by the maintainer:
NODE="$(asdf which node)" sh .plans/research/m7/slice3/mac.sh
```

**The logs** (in `results/`): `guix-8.20.0-1.log` and `docker-1.log` are run 1 (Docker's lanes in
the order F, O, G, C), `-2` run 2; `valgrind-ubuntu-openssl-8.5.0.log` the Valgrind pass;
`supplement-stall-floor-7.85.0-{1,2,3}.log` F's stall three more times. Every one records the same
hashes: `src/` `0080fbff…` (`git diff main -- src` is empty), the prototype `b2a1f0e9…`,
`proxy.sps` `eb28bfda…`, `standin.mjs` `7f99adb4…`. A tag names one case, the same on every lane
and in both runs; in a child of an environment it carries the environment's name,
`named.no_proxy-host.2`.

### Checks, each lane-run

From `tables.mjs --checks`:

| lane | run | parts, exits | self-test | transfers | hung | sockets open at /end | log fetch failed | native counts not zero |
|---|---|---|---|---|---|---|---|---|
| F | 1 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 509 | 0 | 0 | 0 | 0 of 24 |
| O | 1 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 509 | 0 | 0 | 0 | 0 of 24 |
| G | 1 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 509 | 0 | 0 | 0 | 0 of 24 |
| X | 1 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 499 | 0 | 0 | 0 | 0 of 24 |
| C | 1 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 509 | 0 | 0 | 0 | 0 of 24 |
| F | 2 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 509 | 0 | 0 | 0 | 0 of 24 |
| O | 2 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 509 | 0 | 0 | 0 | 0 of 24 |
| G | 2 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 509 | 0 | 0 | 0 | 0 of 24 |
| X | 2 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 499 | 0 | 0 | 0 | 0 of 24 |
| C | 2 | 24 processes, all 0 | standin selftest ok 12 (1 planted vector caught); standin selftest exit=0 | 509 | 0 | 0 | 0 | 0 of 24 |

Hashes, every lane-run:

- `src 0080fbff14e23de0e2b49ffd08bf6afedc05c731d7c9e60103a4dabd182fa315`
- `prototype build/m7s3/src b2a1f0e9418d4aad03ee574ee596326007a19e16af819e3d6029fa37e073b93a`
- `program .plans/research/m7/slice3/proxy.sps eb28bfda80ee053f7e3f6b9984dcf31c9567f444178ddbaa36fadcf261eae816 standin .plans/research/m7/slice3/standin.mjs 7f99adb48701b7d0b881d65a991369af7239cf43d1deb2537547b5689cc1196d`

### The Valgrind pass

`tables.mjs --valgrind`: 301 rows of items 3, 4 and 5 (`pooled`, `refused`, `tls`, `stall`) under
the memory gate's Valgrind on lane O, each the same code, request size, status and transfer count
as both native runs; 0 rows differ. Each of the four processes: `ERROR SUMMARY: 0 errors`,
`definitely lost: 0 bytes in 0 blocks` (`valgrind-ubuntu-openssl-8.5.0.log`), with 336 bytes
"possibly lost" in one block each, which the gate does not count. Against lane F's native runs
instead, the control, 67 of 301 differ (`valgrind-control.log`): 7.85.0's tunnel reuse, its
`CONNECT` sizes and its retries, so the comparison can tell lanes apart. No race of item 4's codes
moved under Valgrind on O; F, whose `h2` stall is a race, was not in the pass.

## What split

- **Between the kept runs:** one cell, F's `h2` origin through an `https://` proxy, 3 of 10
  stalled in run 1 and 2 of 10 in run 2; 1, 1 and 0 of 10 in the supplement's three runs.
- **Between lanes,** every difference follows the version: 7.85.0 against the rest for the pooled
  tunnel, the refused `CONNECT`'s size, `@`'s credentials and `HAPROXY_CLIENT_IP` (unknown);
  7.85.0 and 8.5.0 against 8.20.0 and 8.23.0 for a control byte in the userinfo and the refused
  `CONNECT`'s code; 8.23.0 alone for `socks5://`, the port with none named and `@`; G alone for
  the TLS stall; X alone for the CA variables; and the error buffer's text.
- **Through the engine against the C probe:** no cell the probe measured moved.

## Traps hit, and how to reproduce them

- **An ephemeral port outlives its socket in a map keyed by port.** The stand-in's first
  `viaByPort` kept an upstream socket's local port after the socket closed; a later libcurl
  connection to a proxy got the same port, and the proxy's own request was logged as arriving
  through a tunnel: `req p-basic#196 #1 via=p-open#34/tunnel` (`trial-stale-via-docker.log:14842`,
  G, and on F at `4268`, a trial run with the earlier stand-in, `standin.mjs` `d5653321…`, kept for
  this alone). The earlier stand-in is the kept one less its two `viaByPort.delete` lines and the
  `c.kind === 'origin'` test; with them gone, `docker.sh all` gave the lines above. Not rerun
  since the fix. The kept stand-in deletes an entry as its socket closes, and reads `via` for an
  origin face alone, and no kept log has a proxy face's `req` line with a `/tunnel` or `/forward`
  `via` (`grep -c` over `results/*-[12].log`: 0; over the trial log, 20).
- **A port that moves per run splits a cell when it is printed raw.** OpenSSL's error buffer names
  the origin's port (`SSL_ERROR_SYSCALL in connection to 127.0.0.1:33659`), so O's
  `HAPROXYPROTOCOL` cell read as a split between runs until `tables.mjs` passed error buffers
  through its port names. And the reverse: mapping the low ports 80, 443 and 1080 to Docker's
  faces made lane X, which has none, differ from the rest in every URL naming 80 or 443.
- **A 200 does not say the proxy was used.** A proxy URL whose userinfo decodes to a control byte
  answers 200 on 7.85.0 and 8.5.0, direct. A test of the named proxy asserts the proxy's log.
- **The Guix container does not share the host's `/tmp`.** A log path under the session's scratch
  directory, written by a command inside `scripts/guix-env`, failed `No such file or directory`;
  scratch logs went under `build/m7s3/` instead.
- **`VERBOSE` lines end in CR.** Grepping a log holding libcurl's trace printed nothing visible in
  this terminal for matched lines; `cat -v` or `grep -a` shows them.
- **On main the hatch cannot clear a string option, and cannot set `FRESH_CONNECT`:** `#f` is an
  assertion violation, and `FRESH_CONNECT` is the streamed body's. The prototype adds both;
  slice 3's fields set them itself.

## Not measured, and why

- **Apple's 8.7.1.** `mac.sh` runs items 3, 4 and 5's leaves and stall (`pooled refused tls
  stall`), twice with LibreSSL and twice with `CURL_SSL_BACKEND=secure-transport`; not run here.
- **`NUM_CONNECTS`:** no response or condition carries it; the stand-in's connection numbers and
  each request's `via` are the reading.
- **The causes not traced in source** (above), and 8.5.0's source, which is not on this host.
- **A proxy named by host name or IPv6 through the engine:** every proxy is 127.0.0.1; item 2 (a)
  parses `[::1]` and zones only.
- **A body large enough for `Expect: 100-continue`** through a proxy: the `post` bodies are 62
  bytes.
- SOCKS, NTLM, Negotiate, Digest at a proxy beyond the 407, and HTTPS2 proxies, by the brief.

## Files

- `proxy.sps`: the program; its header lists each part.
- `standin.mjs`: the stand-ins; its header lists every face, route and log line.
- `run.sh`: one lane, every part or those named, each under `env -i`; `VALGRIND=1` for the gate's
  Valgrind. After the kept runs it learned to pick `sed`'s line buffering, `-u` (GNU, as the kept
  runs used) or `-l` (macOS), for `mac.sh`; nothing else changed.
- `docker.sh`: the four Docker lanes, in one `--rm --network none ubuntu:24.04`, after one `--rm`
  container that fetches the apt packages into `build/m7s3/apt`.
- `all.sh`: the prototype, then both runs of every lane, the Valgrind pass and the controls, into
  `results/`.
- `mac.sh`: the Mac's runs, for the maintainer.
- `make-prototype.sh`, `prototype.diff`: the prototype in `build/m7s3/src`.
- `tables.mjs`: every table here, from `results/`; `--checks`, `--valgrind`, `--cite`.
- `wire.mjs`, `wire-control.sh`, `selftest-control.sh`: the wire check, and the controls.
- `results/`: the kept logs, `guix-8.20.0-{1,2}.log`, `docker-{1,2}.log`,
  `valgrind-ubuntu-openssl-8.5.0.log`, `supplement-stall-floor-7.85.0-{1,2,3}.log`;
  `wire-check.log`, `wire-control-guix-8.20.0.log`, `selftest-control.log`,
  `valgrind-control.log`; and `trial-stale-via-docker.log`, a trial run with an earlier
  stand-in, kept as the stale-port trap's evidence alone: no table reads it.

## The tables

A cell `=` is the same as the row's first; one in bold is two runs that disagree, run 1 / run 2.

### The hatch and the proxy field, on main and on the prototype (`refusals`)

A cell: `attached` (the hatch took it), `made` (the field took it), the refusal's reason, or `condition` for an assertion violation.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| main PROXY | refused owned-option | = | = | = | = |
| main NOPROXY | refused owned-option | = | = | = | = |
| main PROXY_CAINFO | refused owned-option | = | = | = | = |
| main PROXY_CAPATH | refused owned-option | = | = | = | = |
| main PROXY_CAPATH-clear | refused owned-option | = | = | = | = |
| main PROXY_SSL_VERIFYPEER | refused owned-option | = | = | = | = |
| main PROXY_SSL_VERIFYHOST | refused owned-option | = | = | = | = |
| main HTTPPROXYTUNNEL | attached | = | = | = | = |
| main SUPPRESS_CONNECT_HEADERS | attached | = | = | = | = |
| main PROXY_SERVICE_NAME | attached | = | = | = | = |
| main PROXY_SERVICE_NAME-clear | condition: takes a string | = | = | = | = |
| main SOCKS5_AUTH | attached | = | = | = | = |
| main HAPROXYPROTOCOL | attached | = | = | = | = |
| main HAPROXY_CLIENT_IP | refused unknown-option | attached | attached | attached | attached |
| main PROXYAUTH | attached | = | = | = | = |
| main PROXYUSERPWD | attached | = | = | = | = |
| main PROXYUSERNAME | attached | = | = | = | = |
| main PROXYPASSWORD | attached | = | = | = | = |
| main PROXYHEADER | refused owned-option | = | = | = | = |
| main HEADEROPT | refused owned-option | = | = | = | = |
| main PRE_PROXY | refused owned-option | = | = | = | = |
| main PROXYTYPE | refused owned-option | = | = | = | = |
| main PROXYPORT | refused owned-option | = | = | = | = |
| main FRESH_CONNECT | refused owned-option | = | = | = | = |
| main FORBID_REUSE | attached | = | = | = | = |
| main VERBOSE | attached | = | = | = | = |
| main CAPATH-clear | refused owned-option | = | = | = | = |
| main USERAGENT-clear | refused owned-option | = | = | = | = |
| main field-proxy "http://127.0.0.1:1" | condition: not a proxy value | = | = | = | = |
| main session-proxy "http://127.0.0.1:1" | condition: not a proxy value | = | = | = | = |
| main field-proxy environment | made | = | = | = | = |
| main session-proxy environment | made | = | = | = | = |
| main field-proxy #f | made | = | = | = | = |
| main session-proxy #f | made | = | = | = | = |
| main field-proxy "" | condition: not a proxy value | = | = | = | = |
| main session-proxy "" | condition: not a proxy value | = | = | = | = |
| prototype PROXY | refused owned-option | = | = | = | = |
| prototype NOPROXY | attached | = | = | = | = |
| prototype PROXY_CAINFO | attached | = | = | = | = |
| prototype PROXY_CAPATH | attached | = | = | = | = |
| prototype PROXY_CAPATH-clear | attached | = | = | = | = |
| prototype PROXY_SSL_VERIFYPEER | attached | = | = | = | = |
| prototype PROXY_SSL_VERIFYHOST | attached | = | = | = | = |
| prototype HTTPPROXYTUNNEL | attached | = | = | = | = |
| prototype SUPPRESS_CONNECT_HEADERS | attached | = | = | = | = |
| prototype PROXY_SERVICE_NAME | attached | = | = | = | = |
| prototype PROXY_SERVICE_NAME-clear | attached | = | = | = | = |
| prototype SOCKS5_AUTH | attached | = | = | = | = |
| prototype HAPROXYPROTOCOL | attached | = | = | = | = |
| prototype HAPROXY_CLIENT_IP | refused unknown-option | attached | attached | attached | attached |
| prototype PROXYAUTH | attached | = | = | = | = |
| prototype PROXYUSERPWD | attached | = | = | = | = |
| prototype PROXYUSERNAME | attached | = | = | = | = |
| prototype PROXYPASSWORD | attached | = | = | = | = |
| prototype PROXYHEADER | refused owned-option | = | = | = | = |
| prototype HEADEROPT | refused owned-option | = | = | = | = |
| prototype PRE_PROXY | refused owned-option | = | = | = | = |
| prototype PROXYTYPE | refused owned-option | = | = | = | = |
| prototype PROXYPORT | refused owned-option | = | = | = | = |
| prototype FRESH_CONNECT | attached | = | = | = | = |
| prototype FORBID_REUSE | attached | = | = | = | = |
| prototype VERBOSE | attached | = | = | = | = |
| prototype CAPATH-clear | refused owned-option | = | = | = | = |
| prototype USERAGENT-clear | refused owned-option | = | = | = | = |
| prototype field-proxy "http://127.0.0.1:1" | made | = | = | = | = |
| prototype session-proxy "http://127.0.0.1:1" | made | = | = | = | = |
| prototype field-proxy environment | made | = | = | = | = |
| prototype session-proxy environment | made | = | = | = | = |
| prototype field-proxy #f | made | = | = | = | = |
| prototype session-proxy #f | made | = | = | = | = |
| prototype field-proxy "" | made | = | = | = | = |
| prototype session-proxy "" | made | = | = | = | = |

### Item 5: curl_easy_setopt's answer to each proxy TLS setting, on a scratch handle (`setopts`)

A cell: the CURLcode, 0 OK, 4 CURLE_NOT_BUILT_IN, 48 CURLE_UNKNOWN_OPTION; `unknown` when the libcurl knows no option by the name.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| PROXY_CAINFO the ca.pem | 0 | = | = | = | = |
| PROXY_CAPATH #f | 0 | = | = | = | = |
| PROXY_CAPATH the cadir | 0 | = | = | = | = |
| PROXY_CAINFO #f | 0 | = | = | = | = |
| PROXY_SSL_VERIFYPEER 0 | 0 | = | = | = | = |
| PROXY_SSL_VERIFYPEER 1 | 0 | = | = | = | = |
| PROXY_SSL_VERIFYHOST 0 | 0 | = | = | = | = |
| PROXY_SSL_VERIFYHOST 2 | 0 | = | = | = | = |
| CAINFO the ca.pem | 0 | = | = | = | = |
| CAPATH #f | 0 | = | = | = | = |
| CAPATH the cadir | 0 | = | = | = | = |
| HAPROXY_CLIENT_IP "10.1.2.3" | unknown | 0 | 0 | 0 | 0 |
| NOPROXY "" | 0 | = | = | = | = |

### Item 2 (a): curl-url-part of each proxy URL, on main's src/ (`i2a`)

A cell: scheme, user, password, host, port, path, query and fragment as curl-url-part answers them (`–` absent; zoneid after the host when present), or the refusal. `<p-open>` is that face's port.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| port-http | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| noport-http | `http` u=– pw=– h=127.0.0.1 port=80 path=/ q=– f=– | = | = | = | = |
| noport-https | `https` u=– pw=– h=127.0.0.1 port=443 path=/ q=– f=– | = | = | = | = |
| port80 | `http` u=– pw=– h=127.0.0.1 port=80 path=/ q=– f=– | = | = | = | = |
| port443 | `https` u=– pw=– h=127.0.0.1 port=443 path=/ q=– f=– | = | = | = | = |
| upper-scheme | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| no-scheme | url-error reason=bad-scheme code=27 | = | = | = | = |
| foo | url-error reason=unsupported-scheme code=5 | = | = | = | = |
| ftp | `ftp` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| socks5 | url-error reason=unsupported-scheme code=5 | url-error reason=unsupported-scheme code=5 | url-error reason=unsupported-scheme code=5 | url-error reason=unsupported-scheme code=5 | `socks5` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| path-a | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/a q=– f=– | = | = | = | = |
| path-slash | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| query | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=q=1 f=– | = | = | = | = |
| query-nopath | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=q=1 f=– | = | = | = | = |
| fragment | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=f | = | = | = | = |
| fragment-nopath | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=f | = | = | = | = |
| ipv6 | `http` u=– pw=– h=[::1] port=<p-open> path=/ q=– f=– | = | = | = | = |
| ipv6-zone | `http` u=– pw=– h=[fe80::1]%eth0 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ipv6-zone-lo | `http` u=– pw=– h=[::1]%lo port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-at | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-colon-at | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-u-at | `http` u=u pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-u-colon-at | `http` u=u pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u=u pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u=u pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u=u pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u=u pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-colon-p-at | `http` u=– pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | `http` u= pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-u-p-at | `http` u=u pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-user-3A | `http` u=a%3Ab pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-pass-3A | `http` u=u pw=p%3Aq h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-user-0D0A | `http` u=u%0D%0Ax pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-pass-0D0A | `http` u=u pw=p%0D%0Ax h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-user-00 | `http` u=u%00x pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-pass-00 | `http` u=u pw=p%00x h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-user-01 | `http` u=u%01x pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-user-09 | `http` u=u%09x pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-user-1F | `http` u=u%1Fx pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-user-20 | `http` u=u%20x pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-user-7F | `http` u=u%7Fx pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-pass-7F | `http` u=u pw=p%7Fx h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-utf8-pct | `http` u=%C3%A9l%C3%A8ve pw=p%C3%A4ss h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-user-FF | `http` u=u%FFx pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-pass-FF | `http` u=u pw=p%FFx h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-pct-25 | `http` u=u%25x pw=p%25q h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |
| ui-utf8-raw | `http` u=\xc3\xa9l\xc3\xa8ve pw=p\xc3\xa4ss h=127.0.0.1 port=<p-open> path=/ q=– f=– | = | = | = | = |

The URLs, in order: `port-http` http://127.0.0.1:<p-open>; `noport-http` http://127.0.0.1; `noport-https` https://127.0.0.1; `port80` http://127.0.0.1:80; `port443` https://127.0.0.1:443; `upper-scheme` HTTP://127.0.0.1:<p-open>; `no-scheme` 127.0.0.1:<p-open>; `foo` foo://127.0.0.1:<p-open>; `ftp` ftp://127.0.0.1:<p-open>; `socks5` socks5://127.0.0.1:<p-open>; `path-a` http://127.0.0.1:<p-open>/a; `path-slash` http://127.0.0.1:<p-open>/; `query` http://127.0.0.1:<p-open>/?q=1; `query-nopath` http://127.0.0.1:<p-open>?q=1; `fragment` http://127.0.0.1:<p-open>/#f; `fragment-nopath` http://127.0.0.1:<p-open>#f; `ipv6` http://[::1]:<p-open>; `ipv6-zone` http://[fe80::1%25eth0]:<p-open>; `ipv6-zone-lo` http://[::1%25lo]:<p-open>; `ui-at` http://@127.0.0.1:<p-open>; `ui-colon-at` http://:@127.0.0.1:<p-open>; `ui-u-at` http://u@127.0.0.1:<p-open>; `ui-u-colon-at` http://u:@127.0.0.1:<p-open>; `ui-colon-p-at` http://:p@127.0.0.1:<p-open>; `ui-u-p-at` http://u:p@127.0.0.1:<p-open>; `ui-user-3A` http://a%3Ab:p@127.0.0.1:<p-open>; `ui-pass-3A` http://u:p%3Aq@127.0.0.1:<p-open>; `ui-user-0D0A` http://u%0D%0Ax:p@127.0.0.1:<p-open>; `ui-pass-0D0A` http://u:p%0D%0Ax@127.0.0.1:<p-open>; `ui-user-00` http://u%00x:p@127.0.0.1:<p-open>; `ui-pass-00` http://u:p%00x@127.0.0.1:<p-open>; `ui-user-01` http://u%01x:p@127.0.0.1:<p-open>; `ui-user-09` http://u%09x:p@127.0.0.1:<p-open>; `ui-user-1F` http://u%1Fx:p@127.0.0.1:<p-open>; `ui-user-20` http://u%20x:p@127.0.0.1:<p-open>; `ui-user-7F` http://u%7Fx:p@127.0.0.1:<p-open>; `ui-pass-7F` http://u:p%7Fx@127.0.0.1:<p-open>; `ui-utf8-pct` http://%C3%A9l%C3%A8ve:p%C3%A4ss@127.0.0.1:<p-open>; `ui-user-FF` http://u%FFx:p@127.0.0.1:<p-open>; `ui-pass-FF` http://u:p%FFx@127.0.0.1:<p-open>; `ui-pct-25` http://u%25x:p%25q@127.0.0.1:<p-open>; `ui-utf8-raw` http://\xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss@127.0.0.1:<p-open>.

### Item 1: a named proxy beside the environment (`i1`)

The named proxy is `p-open`; the variables name `p-other`. A cell: where the request went (`p-open`, `p-other`, or `direct`: only the origin logged it), the form (`abs`, `CONNECT`), the response, and for h2 the ALPN the origin chose.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| none absolute-http noproxy=empty | p-open abs; 200 | = | = | = | = |
| none absolute-http noproxy=unset | p-open abs; 200 | = | = | = | = |
| none connect-https noproxy=empty | p-open CONNECT; 200 | = | = | = | = |
| none connect-https noproxy=unset | p-open CONNECT; 200 | = | = | = | = |
| none connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| none connect-h2 noproxy=unset | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| none direct-http noproxy=control | direct; 200 | = | = | = | = |
| none environment-http noproxy=control | direct; 200 | = | = | = | = |
| none environment-https noproxy=control | direct; 200 | = | = | = | = |
| no_proxy-host absolute-http noproxy=empty | p-open abs; 200 | = | = | = | = |
| no_proxy-host absolute-http noproxy=unset | direct; 200 | = | = | = | = |
| no_proxy-host connect-https noproxy=empty | p-open CONNECT; 200 | = | = | = | = |
| no_proxy-host connect-https noproxy=unset | direct; 200 | = | = | = | = |
| no_proxy-host connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| no_proxy-host connect-h2 noproxy=unset | direct; 200 h2 alpn=h2 | = | = | = | = |
| no_proxy-host direct-http noproxy=control | direct; 200 | = | = | = | = |
| no_proxy-host environment-http noproxy=control | direct; 200 | = | = | = | = |
| no_proxy-host environment-https noproxy=control | direct; 200 | = | = | = | = |
| NO_PROXY-host absolute-http noproxy=empty | p-open abs; 200 | = | = | = | = |
| NO_PROXY-host absolute-http noproxy=unset | direct; 200 | = | = | = | = |
| NO_PROXY-host connect-https noproxy=empty | p-open CONNECT; 200 | = | = | = | = |
| NO_PROXY-host connect-https noproxy=unset | direct; 200 | = | = | = | = |
| NO_PROXY-host connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| NO_PROXY-host connect-h2 noproxy=unset | direct; 200 h2 alpn=h2 | = | = | = | = |
| NO_PROXY-host direct-http noproxy=control | direct; 200 | = | = | = | = |
| NO_PROXY-host environment-http noproxy=control | direct; 200 | = | = | = | = |
| NO_PROXY-host environment-https noproxy=control | direct; 200 | = | = | = | = |
| no_proxy-star absolute-http noproxy=empty | p-open abs; 200 | = | = | = | = |
| no_proxy-star absolute-http noproxy=unset | direct; 200 | = | = | = | = |
| no_proxy-star connect-https noproxy=empty | p-open CONNECT; 200 | = | = | = | = |
| no_proxy-star connect-https noproxy=unset | direct; 200 | = | = | = | = |
| no_proxy-star connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| no_proxy-star connect-h2 noproxy=unset | direct; 200 h2 alpn=h2 | = | = | = | = |
| no_proxy-star direct-http noproxy=control | direct; 200 | = | = | = | = |
| no_proxy-star environment-http noproxy=control | direct; 200 | = | = | = | = |
| no_proxy-star environment-https noproxy=control | direct; 200 | = | = | = | = |
| proxy-vars absolute-http noproxy=empty | p-open abs; 200 | = | = | = | = |
| proxy-vars absolute-http noproxy=unset | p-open abs; 200 | = | = | = | = |
| proxy-vars connect-https noproxy=empty | p-open CONNECT; 200 | = | = | = | = |
| proxy-vars connect-https noproxy=unset | p-open CONNECT; 200 | = | = | = | = |
| proxy-vars connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| proxy-vars connect-h2 noproxy=unset | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| proxy-vars direct-http noproxy=control | direct; 200 | = | = | = | = |
| proxy-vars environment-http noproxy=control | p-other abs; 200 | = | = | = | = |
| proxy-vars environment-https noproxy=control | p-other CONNECT; 200 | = | = | = | = |
| all_proxy absolute-http noproxy=empty | p-open abs; 200 | = | = | = | = |
| all_proxy absolute-http noproxy=unset | p-open abs; 200 | = | = | = | = |
| all_proxy connect-https noproxy=empty | p-open CONNECT; 200 | = | = | = | = |
| all_proxy connect-https noproxy=unset | p-open CONNECT; 200 | = | = | = | = |
| all_proxy connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| all_proxy connect-h2 noproxy=unset | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| all_proxy direct-http noproxy=control | direct; 200 | = | = | = | = |
| all_proxy environment-http noproxy=control | p-other abs; 200 | = | = | = | = |
| all_proxy environment-https noproxy=control | p-other CONNECT; 200 | = | = | = | = |
| proxy-vars-no_proxy-host absolute-http noproxy=empty | p-open abs; 200 | = | = | = | = |
| proxy-vars-no_proxy-host absolute-http noproxy=unset | direct; 200 | = | = | = | = |
| proxy-vars-no_proxy-host connect-https noproxy=empty | p-open CONNECT; 200 | = | = | = | = |
| proxy-vars-no_proxy-host connect-https noproxy=unset | direct; 200 | = | = | = | = |
| proxy-vars-no_proxy-host connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 | = | = | = | = |
| proxy-vars-no_proxy-host connect-h2 noproxy=unset | direct; 200 h2 alpn=h2 | = | = | = | = |
| proxy-vars-no_proxy-host direct-http noproxy=control | direct; 200 | = | = | = | = |
| proxy-vars-no_proxy-host environment-http noproxy=control | direct; 200 | = | = | = | = |
| proxy-vars-no_proxy-host environment-https noproxy=control | direct; 200 | = | = | = | = |

Each child's environment, its first line, on every lane-run (the libcurl path and the run's temporary directory left out), and how many lane-runs printed it:

- named `none`: `env 1 CHEZ_CURL_LIBCURL=…` (10)
- named `no_proxy-host`: `env 2 CHEZ_CURL_LIBCURL=… no_proxy=127.0.0.1` (10)
- named `NO_PROXY-host`: `env 2 CHEZ_CURL_LIBCURL=… NO_PROXY=127.0.0.1` (10)
- named `no_proxy-star`: `env 2 CHEZ_CURL_LIBCURL=… no_proxy=*` (10)
- named `proxy-vars`: `env 3 CHEZ_CURL_LIBCURL=… http_proxy=http://127.0.0.1:<p-other> https_proxy=http://127.0.0.1:<p-other>` (10)
- named `all_proxy`: `env 2 CHEZ_CURL_LIBCURL=… all_proxy=http://127.0.0.1:<p-other>` (10)
- named `proxy-vars-no_proxy-host`: `env 4 CHEZ_CURL_LIBCURL=… http_proxy=http://127.0.0.1:<p-other> https_proxy=http://127.0.0.1:<p-other> no_proxy=127.0.0.1` (10)
- tlsenv `certfile-ca`: `env 2 CHEZ_CURL_LIBCURL=… SSL_CERT_FILE=TMP/pki/ca.pem` (10)
- tlsenv `certfile-other`: `env 2 CHEZ_CURL_LIBCURL=… SSL_CERT_FILE=TMP/pki/other-ca.pem` (10)
- tlsenv `certdir-cadir`: `env 2 CHEZ_CURL_LIBCURL=… SSL_CERT_DIR=TMP/pki/cadir` (10)

### Item 2 (b): what goes on the wire for each userinfo form, through `p-open` (`i2b`)

A cell: the outcome, then the `Proxy-Authorization` p-open decoded, user:password with each byte outside `!`..`~` as `\xHH`, or `–` for none sent; `no request` when no face got one; `DIRECT` when the origin got the request straight, and the proxy nothing.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| form=none transport=absolute | 200; – | = | = | = | = |
| form=none transport=connect | 200; – | = | = | = | = |
| form=at transport=absolute | 200; – | 200; : | 200; : | 200; : | 200; – |
| form=at transport=connect | 200; – | 200; : | 200; : | 200; : | 200; – |
| form=colon-at transport=absolute | 200; – | 200; : | 200; : | 200; : | 200; – |
| form=colon-at transport=connect | 200; – | 200; : | 200; : | 200; : | 200; – |
| form=u-at transport=absolute | 200; u: | = | = | = | = |
| form=u-at transport=connect | 200; u: | = | = | = | = |
| form=u-colon-at transport=absolute | 200; u: | = | = | = | = |
| form=u-colon-at transport=connect | 200; u: | = | = | = | = |
| form=colon-p-at transport=absolute | 200; :p | = | = | = | = |
| form=colon-p-at transport=connect | 200; :p | = | = | = | = |
| form=u-p-at transport=absolute | 200; u:p | = | = | = | = |
| form=u-p-at transport=connect | 200; u:p | = | = | = | = |
| form=user-3A transport=absolute | 200; a:b:p | = | = | = | = |
| form=user-3A transport=connect | 200; a:b:p | = | = | = | = |
| form=pass-3A transport=absolute | 200; u:p:q | = | = | = | = |
| form=pass-3A transport=connect | 200; u:p:q | = | = | = | = |
| form=user-0D0A transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-0D0A transport=connect | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=pass-0D0A transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=pass-0D0A transport=connect | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-00 transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-00 transport=connect | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=pass-00 transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=pass-00 transport=connect | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-01 transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-01 transport=connect | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-09 transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-09 transport=connect | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-1F transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-1F transport=connect | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 200; DIRECT: the origin got it, the proxy nothing | 3 – sent=0; no request | 3 – sent=0; no request |
| form=user-20 transport=absolute | 200; u\x20x:p | = | = | = | = |
| form=user-20 transport=connect | 200; u\x20x:p | = | = | = | = |
| form=user-7F transport=absolute | 200; u\x7fx:p | = | = | = | = |
| form=user-7F transport=connect | 200; u\x7fx:p | = | = | = | = |
| form=pass-7F transport=absolute | 200; u:p\x7fx | = | = | = | = |
| form=pass-7F transport=connect | 200; u:p\x7fx | = | = | = | = |
| form=utf8-pct transport=absolute | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss | = | = | = | = |
| form=utf8-pct transport=connect | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss | = | = | = | = |
| form=user-FF transport=absolute | 200; u\xffx:p | = | = | = | = |
| form=user-FF transport=connect | 200; u\xffx:p | = | = | = | = |
| form=pass-FF transport=absolute | 200; u:p\xffx | = | = | = | = |
| form=pass-FF transport=connect | 200; u:p\xffx | = | = | = | = |
| form=pct-25 transport=absolute | 200; u%x:p%q | = | = | = | = |
| form=pct-25 transport=connect | 200; u%x:p%q | = | = | = | = |
| form=utf8-raw transport=absolute | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss | = | = | = | = |
| form=utf8-raw transport=connect | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss | = | = | = | = |
| form=noscheme-u-p transport=absolute | 200; u:p | = | = | = | = |
| form=noscheme-u-p transport=connect | 200; u:p | = | = | = | = |

### Item 2 (c): the port a proxy URL names, and none (Docker, root) (`i2c`)

Listeners: `p80` on 80 and `p1080` on 1080, plaintext open proxies; `tp443` on 443, an open proxy over TLS. A cell: the face that got the connection, and the outcome. Lane X did not run it: its stand-in has no low ports.

| case | F | O | G | C |
|---|---|---|---|---|
| proxy=http-80 transport=absolute | p80; 200 | = | = | = |
| proxy=http-80 transport=connect | p80; 200 | = | = | = |
| proxy=http-none transport=absolute | p1080; 200 | p1080; 200 | p1080; 200 | p80; 200 |
| proxy=http-none transport=connect | p1080; 200 | p1080; 200 | p1080; 200 | p80; 200 |
| proxy=noscheme-none transport=absolute | p1080; 200 | p1080; 200 | p1080; 200 | p80; 200 |
| proxy=noscheme-none transport=connect | p1080; 200 | p1080; 200 | p1080; 200 | p80; 200 |
| proxy=https-443 transport=absolute | tp443; 200 | = | = | = |
| proxy=https-443 transport=connect | tp443; 200 | tp443; 200 | tp443; 28 timeout sent=66 | tp443; 200 |
| proxy=https-none transport=absolute | tp443; 200 | = | = | = |
| proxy=https-none transport=connect | tp443; 200 | tp443; 200 | tp443; 28 timeout sent=67 | tp443; 200 |

### Item 3: the pooled tunnel (`i3`)

Two transfers on one engine through one proxy that takes Basic for alice and bob, the first as alice. `sequential`: the second submitted once the first is done; `batch`: both submitted in one hold of the engine. A cell: `reused` when the second request rode the first's origin connection (for a tunnel: inside the first's tunnel; for absolute form: on the first's proxy connection, whose upstream it is), else `new`; then the second's outcome; then each request the proxy got for the second, with the credentials it carried (`no request`: the proxy got none for it).

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| mode=connect-https order=sequential flags=plain second=same | reused; 200; no request | = | = | = | = |
| mode=connect-https order=sequential flags=plain second=other | reused; 200; no request | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=connect-https order=sequential flags=plain second=wrong | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-https order=sequential flags=plain second=none | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-https order=sequential flags=fresh-second second=same | new; 200; CONNECT PA=alice:s3cret→200 | = | = | = | = |
| mode=connect-https order=sequential flags=fresh-second second=other | new; 200; CONNECT PA=bob:hunter2→200 | = | = | = | = |
| mode=connect-https order=sequential flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-https order=sequential flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-https order=sequential flags=forbid-first second=same | new; 200; CONNECT PA=alice:s3cret→200 | = | = | = | = |
| mode=connect-https order=sequential flags=forbid-first second=other | new; 200; CONNECT PA=bob:hunter2→200 | = | = | = | = |
| mode=connect-https order=sequential flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-https order=sequential flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=tunnel-http order=sequential flags=plain second=same | reused; 200; no request | = | = | = | = |
| mode=tunnel-http order=sequential flags=plain second=other | reused; 200; no request | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=tunnel-http order=sequential flags=plain second=wrong | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=tunnel-http order=sequential flags=plain second=none | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=tunnel-http order=sequential flags=fresh-second second=same | new; 200; CONNECT PA=alice:s3cret→200 | = | = | = | = |
| mode=tunnel-http order=sequential flags=fresh-second second=other | new; 200; CONNECT PA=bob:hunter2→200 | = | = | = | = |
| mode=tunnel-http order=sequential flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=tunnel-http order=sequential flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=tunnel-http order=sequential flags=forbid-first second=same | new; 200; CONNECT PA=alice:s3cret→200 | = | = | = | = |
| mode=tunnel-http order=sequential flags=forbid-first second=other | new; 200; CONNECT PA=bob:hunter2→200 | = | = | = | = |
| mode=tunnel-http order=sequential flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=tunnel-http order=sequential flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=absolute-http order=sequential flags=plain second=same | reused; 200; abs PA=alice:s3cret | = | = | = | = |
| mode=absolute-http order=sequential flags=plain second=other | reused; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 |
| mode=absolute-http order=sequential flags=plain second=wrong | new; 407; abs PA=alice:wrong→407 | = | = | = | = |
| mode=absolute-http order=sequential flags=plain second=none | new; 407; abs PA=–→407 | = | = | = | = |
| mode=absolute-http order=sequential flags=fresh-second second=same | new; 200; abs PA=alice:s3cret | = | = | = | = |
| mode=absolute-http order=sequential flags=fresh-second second=other | new; 200; abs PA=bob:hunter2 | = | = | = | = |
| mode=absolute-http order=sequential flags=fresh-second second=wrong | new; 407; abs PA=alice:wrong→407 | = | = | = | = |
| mode=absolute-http order=sequential flags=fresh-second second=none | new; 407; abs PA=–→407 | = | = | = | = |
| mode=absolute-http order=sequential flags=forbid-first second=same | new; 200; abs PA=alice:s3cret | = | = | = | = |
| mode=absolute-http order=sequential flags=forbid-first second=other | new; 200; abs PA=bob:hunter2 | = | = | = | = |
| mode=absolute-http order=sequential flags=forbid-first second=wrong | new; 407; abs PA=alice:wrong→407 | = | = | = | = |
| mode=absolute-http order=sequential flags=forbid-first second=none | new; 407; abs PA=–→407 | = | = | = | = |
| mode=https-proxy-connect-https order=sequential flags=plain second=same | reused; 200; no request | reused; 200; no request | new; 28 timeout sent=75; CONNECT PA=alice:s3cret→200 [first: 28 timeout sent=75] | reused; 200; no request | reused; 200; no request |
| mode=https-proxy-connect-https order=sequential flags=plain second=other | reused; 200; no request | new; 200; CONNECT PA=bob:hunter2→200 | new; 28 timeout sent=75; CONNECT PA=bob:hunter2→200 [first: 28 timeout sent=75] | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=https-proxy-connect-https order=sequential flags=plain second=wrong | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 [first: 28 timeout sent=75] | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=https-proxy-connect-https order=sequential flags=plain second=none | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 [first: 28 timeout sent=75] | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=same | new; 200; CONNECT PA=alice:s3cret→200 | new; 200; CONNECT PA=alice:s3cret→200 | new; 28 timeout sent=75; CONNECT PA=alice:s3cret→200 [first: 28 timeout sent=75] | new; 200; CONNECT PA=alice:s3cret→200 | new; 200; CONNECT PA=alice:s3cret→200 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=other | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 | new; 28 timeout sent=75; CONNECT PA=bob:hunter2→200 [first: 28 timeout sent=75] | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 [first: 28 timeout sent=75] | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 [first: 28 timeout sent=75] | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=same | new; 200; CONNECT PA=alice:s3cret→200 | new; 200; CONNECT PA=alice:s3cret→200 | new; 28 timeout sent=75; CONNECT PA=alice:s3cret→200 [first: 28 timeout sent=75] | new; 200; CONNECT PA=alice:s3cret→200 | new; 200; CONNECT PA=alice:s3cret→200 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=other | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 | new; 28 timeout sent=75; CONNECT PA=bob:hunter2→200 [first: 28 timeout sent=75] | new; 200; CONNECT PA=bob:hunter2→200 | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 [first: 28 timeout sent=75] | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 [first: 28 timeout sent=75] | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=https-proxy-absolute-http order=sequential flags=plain second=same | reused; 200; abs PA=alice:s3cret | reused; 200; abs PA=alice:s3cret | reused; 200; abs PA=alice:s3cret | new; 200; abs PA=alice:s3cret | new; 200; abs PA=alice:s3cret |
| mode=https-proxy-absolute-http order=sequential flags=plain second=other | reused; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 |
| mode=https-proxy-absolute-http order=sequential flags=plain second=wrong | new; 407; abs PA=alice:wrong→407 | = | = | = | = |
| mode=https-proxy-absolute-http order=sequential flags=plain second=none | new; 407; abs PA=–→407 | = | = | = | = |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=same | new; 200; abs PA=alice:s3cret | = | = | = | = |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=other | new; 200; abs PA=bob:hunter2 | = | = | = | = |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=wrong | new; 407; abs PA=alice:wrong→407 | = | = | = | = |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=none | new; 407; abs PA=–→407 | = | = | = | = |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=same | new; 200; abs PA=alice:s3cret | = | = | = | = |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=other | new; 200; abs PA=bob:hunter2 | = | = | = | = |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=wrong | new; 407; abs PA=alice:wrong→407 | = | = | = | = |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=none | new; 407; abs PA=–→407 | = | = | = | = |
| mode=connect-h2 order=sequential flags=plain second=same | reused stream=3; 200 h2; no request | = | = | = | = |
| mode=connect-h2 order=sequential flags=plain second=other | reused stream=3; 200 h2; no request | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 |
| mode=connect-h2 order=sequential flags=plain second=wrong | reused stream=3; 200 h2; no request | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=sequential flags=plain second=none | reused stream=3; 200 h2; no request | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=sequential flags=fresh-second second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = | = | = | = |
| mode=connect-h2 order=sequential flags=fresh-second second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = | = | = | = |
| mode=connect-h2 order=sequential flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=sequential flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=sequential flags=forbid-first second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = | = | = | = |
| mode=connect-h2 order=sequential flags=forbid-first second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = | = | = | = |
| mode=connect-h2 order=sequential flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=sequential flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=batch flags=plain second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = | = | = | = |
| mode=connect-h2 order=batch flags=plain second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = | = | = | = |
| mode=connect-h2 order=batch flags=plain second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=batch flags=plain second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=batch flags=fresh-second second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = | = | = | = |
| mode=connect-h2 order=batch flags=fresh-second second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = | = | = | = |
| mode=connect-h2 order=batch flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=batch flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=batch flags=forbid-first second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = | = | = | = |
| mode=connect-h2 order=batch flags=forbid-first second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = | = | = | = |
| mode=connect-h2 order=batch flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=batch flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 | new; 7 connect sent=0; CONNECT PA=–→407 |

### Item 4: a refused CONNECT, and the same proxies by absolute form (`i4`)

A cell: the status chez-curl's response carries, or the failure: code, class, request size; then the error buffer.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| proxy=403 transport=absolute | 403 | = | = | = | = |
| proxy=403 transport=connect | 56 send-receive sent=89; "Received HTTP code 403 from proxy after CONNECT" | 56 send-receive sent=0; "CONNECT tunnel failed, response 403" | 56 send-receive sent=0; "CONNECT tunnel failed, response 403" | 7 connect sent=0; "CONNECT tunnel failed, response 403" | 7 connect sent=0; "CONNECT tunnel failed, response 403" |
| proxy=407-none transport=absolute | 407 | = | = | = | = |
| proxy=407-none transport=connect | 56 send-receive sent=89; "Received HTTP code 407 from proxy after CONNECT" | 56 send-receive sent=0; "CONNECT tunnel failed, response 407" | 56 send-receive sent=0; "CONNECT tunnel failed, response 407" | 7 connect sent=0; "CONNECT tunnel failed, response 407" | 7 connect sent=0; "CONNECT tunnel failed, response 407" |
| proxy=407-wrong transport=absolute | 407 | = | = | = | = |
| proxy=407-wrong transport=connect | 56 send-receive sent=134; "Received HTTP code 407 from proxy after CONNECT" | 56 send-receive sent=0; "CONNECT tunnel failed, response 407" | 56 send-receive sent=0; "CONNECT tunnel failed, response 407" | 7 connect sent=0; "CONNECT tunnel failed, response 407" | 7 connect sent=0; "CONNECT tunnel failed, response 407" |
| proxy=502 transport=absolute | 502 | = | = | = | = |
| proxy=502 transport=connect | 56 send-receive sent=89; "Received HTTP code 502 from proxy after CONNECT" | 56 send-receive sent=0; "CONNECT tunnel failed, response 502" | 56 send-receive sent=0; "CONNECT tunnel failed, response 502" | 7 connect sent=0; "CONNECT tunnel failed, response 502" | 7 connect sent=0; "CONNECT tunnel failed, response 502" |
| proxy=close transport=absolute | 52 send-receive sent=120; "Empty reply from server" | = | = | = | = |
| proxy=close transport=connect | 56 send-receive sent=89; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" |
| proxy=partial transport=absolute | 52 send-receive sent=121; "Empty reply from server" | = | = | = | = |
| proxy=partial transport=connect | 56 send-receive sent=89; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" |
| proxy=refused transport=absolute | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Connection refused" | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Couldn't connect to server" | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Couldn't connect to server" | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <o-raw> via 127.0.0.1 after N ms: Could not connect to server" | 7 connect sent=0; "Failed to connect to 127.0.0.1:<refused> over proxy 127.0.0.1 after N ms: Could not connect to server" |
| proxy=refused transport=connect | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Connection refused" | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Couldn't connect to server" | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Couldn't connect to server" | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <o-tls> via 127.0.0.1 after N ms: Could not connect to server" | 7 connect sent=0; "Failed to connect to 127.0.0.1:<o-tls> over proxy 127.0.0.1 after N ms: Could not connect to server" |

### Item 4: the high level's retry through each (`i4high`)

`http-get` and `http-post`, with the policy (attempts 3, the default statuses and methods, backoff 20 ms, jitter off) and with none. A cell: what the call answered or raised (`transfers=` its `&http-exchange`'s count), then the requests the proxy logged.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| proxy=403 transport=absolute method=get retry=policy | 403; proxy got 1 | = | = | = | = |
| proxy=403 transport=absolute method=get retry=none | 403; proxy got 1 | = | = | = | = |
| proxy=403 transport=absolute method=post retry=policy | 403; proxy got 1 | = | = | = | = |
| proxy=403 transport=absolute method=post retry=none | 403; proxy got 1 | = | = | = | = |
| proxy=403 transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=403 transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=403 transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=403 transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=407-none transport=absolute method=get retry=policy | 407; proxy got 1 | = | = | = | = |
| proxy=407-none transport=absolute method=get retry=none | 407; proxy got 1 | = | = | = | = |
| proxy=407-none transport=absolute method=post retry=policy | 407; proxy got 1 | = | = | = | = |
| proxy=407-none transport=absolute method=post retry=none | 407; proxy got 1 | = | = | = | = |
| proxy=407-none transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=407-none transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=407-none transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=407-none transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=407-wrong transport=absolute method=get retry=policy | 407; proxy got 1 | = | = | = | = |
| proxy=407-wrong transport=absolute method=get retry=none | 407; proxy got 1 | = | = | = | = |
| proxy=407-wrong transport=absolute method=post retry=policy | 407; proxy got 1 | = | = | = | = |
| proxy=407-wrong transport=absolute method=post retry=none | 407; proxy got 1 | = | = | = | = |
| proxy=407-wrong transport=connect method=get retry=policy | 56 send-receive sent=134 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=407-wrong transport=connect method=get retry=none | 56 send-receive sent=134 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=407-wrong transport=connect method=post retry=policy | 56 send-receive sent=134 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=407-wrong transport=connect method=post retry=none | 56 send-receive sent=134 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=502 transport=absolute method=get retry=policy | 502; proxy got 1 | = | = | = | = |
| proxy=502 transport=absolute method=get retry=none | 502; proxy got 1 | = | = | = | = |
| proxy=502 transport=absolute method=post retry=policy | 502; proxy got 1 | = | = | = | = |
| proxy=502 transport=absolute method=post retry=none | 502; proxy got 1 | = | = | = | = |
| proxy=502 transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=502 transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=502 transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=502 transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=close transport=absolute method=get retry=policy | 52 send-receive sent=121 transfers=3; proxy got 3 | = | = | = | = |
| proxy=close transport=absolute method=get retry=none | 52 send-receive sent=121 transfers=1; proxy got 1 | = | = | = | = |
| proxy=close transport=absolute method=post retry=policy | 52 send-receive sent=204 transfers=1; proxy got 1 | = | = | = | = |
| proxy=close transport=absolute method=post retry=none | 52 send-receive sent=204 transfers=1; proxy got 1 | = | = | = | = |
| proxy=close transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=close transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=close transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=close transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=partial transport=absolute method=get retry=policy | 52 send-receive sent=121 transfers=3; proxy got 3 | = | = | = | = |
| proxy=partial transport=absolute method=get retry=none | 52 send-receive sent=121 transfers=1; proxy got 1 | = | = | = | = |
| proxy=partial transport=absolute method=post retry=policy | 52 send-receive sent=204 transfers=1; proxy got 1 | = | = | = | = |
| proxy=partial transport=absolute method=post retry=none | 52 send-receive sent=204 transfers=1; proxy got 1 | = | = | = | = |
| proxy=partial transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=partial transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=partial transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=partial transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=refused transport=absolute method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 0 | = | = | = | = |
| proxy=refused transport=absolute method=get retry=none | 7 connect sent=0 transfers=1; proxy got 0 | = | = | = | = |
| proxy=refused transport=absolute method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 0 | = | = | = | = |
| proxy=refused transport=absolute method=post retry=none | 7 connect sent=0 transfers=1; proxy got 0 | = | = | = | = |
| proxy=refused transport=connect method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 0 | = | = | = | = |
| proxy=refused transport=connect method=get retry=none | 7 connect sent=0 transfers=1; proxy got 0 | = | = | = | = |
| proxy=refused transport=connect method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 0 | = | = | = | = |
| proxy=refused transport=connect method=post retry=none | 7 connect sent=0 transfers=1; proxy got 0 | = | = | = | = |

### Item 5: the proxy's leaves, verification on and off (`i5leaves`)

An `https://` proxy with `PROXY_CAINFO` the run CA and `PROXY_CAPATH` cleared; `off` adds `PROXY_SSL_VERIFYPEER` 0 and `PROXY_SSL_VERIFYHOST` 0. A cell: the outcome; for a failure, whether the proxy logged a request.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| leaf=good verify=on transport=absolute | 200 | = | = | = | = |
| leaf=good verify=on transport=connect | 200 | 200 | 28 timeout sent=64; proxy requests 1 | 200 | 200 |
| leaf=good verify=off transport=absolute | 200 | = | = | = | = |
| leaf=good verify=off transport=connect | 200 | 200 | 28 timeout sent=64; proxy requests 1 | 200 | 200 |
| leaf=expired verify=on transport=absolute | 60 tls sent=0; proxy requests 0 | = | = | = | = |
| leaf=expired verify=on transport=connect | 60 tls sent=0; proxy requests 0 | = | = | = | = |
| leaf=expired verify=off transport=absolute | 200 | = | = | = | = |
| leaf=expired verify=off transport=connect | 200 | 200 | 28 timeout sent=64; proxy requests 1 | 200 | 200 |
| leaf=wrong-host verify=on transport=absolute | 60 tls sent=0; proxy requests 0 | = | = | = | = |
| leaf=wrong-host verify=on transport=connect | 60 tls sent=0; proxy requests 0 | = | = | = | = |
| leaf=wrong-host verify=off transport=absolute | 200 | = | = | = | = |
| leaf=wrong-host verify=off transport=connect | 200 | 200 | 28 timeout sent=65; proxy requests 1 | 200 | 200 |
| leaf=untrusted verify=on transport=absolute | 60 tls sent=0; proxy requests 0 | = | = | = | = |
| leaf=untrusted verify=on transport=connect | 60 tls sent=0; proxy requests 0 | = | = | = | = |
| leaf=untrusted verify=off transport=absolute | 200 | = | = | = | = |
| leaf=untrusted verify=off transport=connect | 200 | 200 | 28 timeout sent=65; proxy requests 1 | 200 | 200 |

### Item 5: the origin's TLS settings against the proxy's (`i5sep`)

Through `tp-good` to the `o-tls` origin by CONNECT. `proxy-bad`: `PROXY_CAINFO` the other CA; `origin-bad`: the origin's `ca-file` the other CA; `noverify`: that side's verification off. A cell: the outcome; which side refused it (`at proxy`: no CONNECT logged; `at origin`: the CONNECT passed).

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| sep=both-good | 200 | 200 | 28 timeout sent=65; at origin | 200 | 200 |
| sep=origin-bad | 60 tls sent=89; at origin | 35 tls sent=0; at origin | 60 tls sent=0; at origin | 60 tls sent=0; at origin | 60 tls sent=0; at origin |
| sep=proxy-bad | 60 tls sent=0; at proxy | = | = | = | = |
| sep=origin-noverify-proxy-bad | 60 tls sent=0; at proxy | = | = | = | = |
| sep=proxy-noverify-origin-bad | 60 tls sent=89; at origin | 35 tls sent=0; at origin | 60 tls sent=0; at origin | 60 tls sent=0; at origin | 60 tls sent=0; at origin |
| sep=both-off | 200 | 200 | 28 timeout sent=65; at origin | 200 | 200 |
| sep=origin-verify-off-proxy-good | 200 | 200 | 28 timeout sent=65; at origin | 200 | 200 |

### Item 5: SSL_CERT_FILE and SSL_CERT_DIR beside a PROXY_CAINFO, in a child's environment (`i5env`)

An `http://` origin through `tp-good`. `certfile-ca`: `SSL_CERT_FILE` the run CA; `certfile-other`: the other CA; `certdir-cadir`: `SSL_CERT_DIR` the run CA's hashed directory. `run-ca` and `other-ca`: `PROXY_CAINFO`, with `PROXY_CAPATH` cleared; `other-ca-capath-default`: not cleared.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| certfile-ca proxyca=run-ca | 200 | = | = | = | = |
| certfile-ca proxyca=other-ca | 60 tls sent=0 | 60 tls sent=0 | 60 tls sent=0 | 200 | 60 tls sent=0 |
| certfile-ca proxyca=other-ca-capath-default | 60 tls sent=0 | 60 tls sent=0 | 60 tls sent=0 | 200 | 60 tls sent=0 |
| certfile-other proxyca=run-ca | 200 | 200 | 200 | 60 tls sent=0 | 200 |
| certfile-other proxyca=other-ca | 60 tls sent=0 | = | = | = | = |
| certfile-other proxyca=other-ca-capath-default | 60 tls sent=0 | = | = | = | = |
| certdir-cadir proxyca=run-ca | 200 | = | = | = | = |
| certdir-cadir proxyca=other-ca | 60 tls sent=0 | 60 tls sent=0 | 60 tls sent=0 | 200 | 60 tls sent=0 |
| certdir-cadir proxyca=other-ca-capath-default | 60 tls sent=0 | 60 tls sent=0 | 60 tls sent=0 | 200 | 60 tls sent=0 |

### Item 5: TLS inside TLS, ten times each per run (`i5stall`)

`timeout-ms` 10,000, through `tp-good` (`https-via-http`: through plaintext `p-open`). A cell: each outcome and how many of the ten gave it.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| case=https-via-https | 10× 200 | 10× 200 | 9× 28 timeout sent=66, 1× 28 timeout sent=67 | 10× 200 | 10× 200 |
| case=http-via-https | 10× 200 | = | = | = | = |
| case=h2-via-https | **7× 200 h2, 3× 28 timeout sent=154 / 8× 200 h2, 2× 28 timeout sent=154** | 10× 200 h2 | 10× 28 timeout sent=65 | 10× 200 h2 | 10× 200 h2 |
| case=https-via-http | 10× 200 | = | = | = | = |

### Item 6: the twins, beside a named proxy (`i6`)

Through `p-open`, the caller's headers `X-Caller: m7s3` and `Proxy-Authorization: Basic YWxpY2U6czNjcmV0`. A cell: each request in the order the stand-in logged it, `FACE: FORM` with the header names it carried (not Host, Accept), `PA=` its Proxy-Authorization; a PROXY protocol line and where it arrived; then the response chez-curl read: status, its header names, and for a streamed one the head's.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| twin=base transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=base transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=base transport=connect-stream | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] head 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=HTTPPROXYTUNNEL-1 transport=absolute | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=HTTPPROXYTUNNEL-1 transport=absolute-stream | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] head 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=HTTPPROXYTUNNEL-1 transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=HTTPPROXYTUNNEL-0 transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=HTTPPROXYTUNNEL-0 transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=SUPPRESS_CONNECT_HEADERS transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=SUPPRESS_CONNECT_HEADERS transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=SUPPRESS_CONNECT_HEADERS transport=connect-stream | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] head 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=SUPPRESS_CONNECT_HEADERS-tunnel transport=absolute | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=SUPPRESS_CONNECT_HEADERS-tunnel transport=absolute-stream | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] head 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=PROXY_SERVICE_NAME transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=PROXY_SERVICE_NAME transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=SOCKS5_AUTH transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=SOCKS5_AUTH transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=HAPROXYPROTOCOL transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller]; PROXY line at p-open: PROXY TCP4 127.0.0.1 127.0.0.1 # <p-open> → 200 [X-Origin,Content-Length] | = | = | = | = |
| twin=HAPROXYPROTOCOL transport=connect | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=133 "error:0A000126:SSL routines::unexpected eof while reading" | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to 127.0.0.1:<o-tls> " | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "gnutls_handshake() failed: The TLS connection was non-properly terminated." | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "GnuTLS, handshake failed: The TLS connection was non-properly terminated." | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "TLS connect error: error:0A000126:SSL routines::unexpected eof while reading" |
| twin=HAPROXYPROTOCOL-tunnel transport=absolute | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: PROXY (tunnel) PA=alice:s3cret [GET /x?tag=twins20 HTTP/1.,X-Caller,Proxy-Authorization]; PROXY line at o-raw: PROXY TCP4 127.0.0.1 127.0.0.1 # <p-open>; PROXY line inside the tunnel → 200 [X-Origin,Content-Length] | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization]; PROXY line at o-raw: PROXY TCP4 127.0.0.1 127.0.0.1 # <p-open>; PROXY line inside the tunnel → 200 [X-Origin,Content-Length] | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization]; PROXY line at o-raw: PROXY TCP4 127.0.0.1 127.0.0.1 # <p-open>; PROXY line inside the tunnel → 200 [X-Origin,Content-Length] | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization]; PROXY line at o-raw: PROXY TCP4 127.0.0.1 127.0.0.1 # <p-open>; PROXY line inside the tunnel → 200 [X-Origin,Content-Length] | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization]; PROXY line at o-raw: PROXY TCP4 127.0.0.1 127.0.0.1 # <p-open>; PROXY line inside the tunnel → 200 [X-Origin,Content-Length] |
| twin=HAPROXY_CLIENT_IP transport=absolute |  → refused unknown-option | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller]; PROXY line at p-open: PROXY TCP4 10.1.2.3 127.0.0.1 # <p-open> → 200 [X-Origin,Content-Length] | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller]; PROXY line at p-open: PROXY TCP4 10.1.2.3 127.0.0.1 # <p-open> → 200 [X-Origin,Content-Length] | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller]; PROXY line at p-open: PROXY TCP4 10.1.2.3 10.1.2.3 # <p-open> → 200 [X-Origin,Content-Length] | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller]; PROXY line at p-open: PROXY TCP4 10.1.2.3 10.1.2.3 # <p-open> → 200 [X-Origin,Content-Length] |
| twin=HAPROXY_CLIENT_IP transport=connect |  → refused unknown-option | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to 127.0.0.1:<o-tls> " | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "gnutls_handshake() failed: The TLS connection was non-properly terminated." | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "GnuTLS, handshake failed: The TLS connection was non-properly terminated." | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "TLS connect error: error:0A000126:SSL routines::unexpected eof while reading" |

### Item 7: prior knowledge to the h2c origin through a named proxy (`i7`)

A cell: each request the stand-in logged (`h2 GET`: an HTTP/2 stream), then the response's status and version.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| case=direct | o-h2c: h2 GET → 200 ⇒ 200 h2 | = | = | = | = |
| case=plain-proxy | p-open: GET abs PA=– → 200 ⇒ 200 | = | = | = | = |
| case=tunnel | p-open: CONNECT PA=– → 200 ; o-h2c: h2 GET (tunnel) → 200 ⇒ 200 h2 | = | = | = | = |

### Item 8: the high level's proxy, hop by hop (`i8`)

The session's proxy is `p-basic` as alice; `call-proxy-other` names it as bob; credentials are `ouser`/`opass` at the origin. A cell: each request in the order the stand-in logged it, `FACE: FORM`, `(tunnel)` or `(forwarded)` for an origin reached through the proxy, `PA=` the Proxy-Authorization the proxy decoded, `A=` the Authorization the origin got, `→` its answer; then what the call answered.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| case=session-proxy origin=http to=- scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 200 ⇒ 200 | = | = | = | = |
| case=session-proxy origin=https to=- scheme=- | p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) → 200 ⇒ 200 | = | = | = | = |
| case=call-proxy-other origin=http to=- scheme=- | p-basic: GET abs PA=bob:hunter2 ; o-raw: GET (forwarded) → 200 ⇒ 200 | = | = | = | = |
| case=call-proxy-other origin=https to=- scheme=- | p-basic: CONNECT PA=bob:hunter2 → 200 ; o-tls: GET (tunnel) → 200 ⇒ 200 | = | = | = | = |
| case=call-proxy-none origin=http to=- scheme=- | o-raw: GET → 200 ⇒ 200 | = | = | = | = |
| case=call-proxy-environment origin=http to=- scheme=- | o-raw: GET → 200 ⇒ 200 | = | = | = | = |
| case=call-proxy-on-none-session origin=http to=- scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 200 ⇒ 200 | = | = | = | = |
| case=redirect origin=- to=same-origin scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 302 ; p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 200 ⇒ 200 after 302 | = | = | = | = |
| case=redirect origin=- to=other-http scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 302 ; p-basic: GET abs PA=alice:s3cret ; o-raw2: GET (forwarded) → 200 ⇒ 200 after 302 | = | = | = | = |
| case=redirect origin=- to=other-https scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 302 ; p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) → 200 ⇒ 200 after 302 | = | = | = | = |
| case=credentials origin=http to=- scheme=basic | p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 200 ⇒ 200 | = | = | = | = |
| case=credentials origin=https to=- scheme=basic | p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) A=Basic ouser:opass → 200 ⇒ 200 | = | = | = | = |
| case=credentials origin=http to=- scheme=digest | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 401 ; p-basic: GET abs PA=alice:s3cret A=Digest ; o-raw: GET (forwarded) A=Digest → 200 ⇒ 200 | = | = | = | = |
| case=credentials origin=https to=- scheme=digest | p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) → 401 ; o-tls: GET (tunnel) A=Digest → 200 ⇒ 200 | = | = | = | = |
| case=credentials-redirect origin=- to=same-origin scheme=basic | p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 302 ; p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 200 ⇒ 200 after 302 | = | = | = | = |
| case=credentials-redirect origin=- to=other-http scheme=basic | p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 302 ; p-basic: GET abs PA=alice:s3cret ; o-raw2: GET (forwarded) → 200 ⇒ 200 after 302 | = | = | = | = |
| case=credentials-redirect origin=- to=other-https scheme=basic | p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 302 ; p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) → 200 ⇒ 200 after 302 | = | = | = | = |

### Item 9: REQUEST_SIZE of proxied transfers (`i9`)

`limit=none`: the transfer as it is, its outcome; `limit=1`: the same request with `body-limit` 1, which fails 63 once the response head says its length, after the whole request went: its `sent=` is `REQUEST_SIZE`. Then the bytes the stand-in got from libcurl: each head's length, and the body's, at the proxy and at the origin (through a tunnel; a forwarded request is the proxy's).

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| route=direct-http method=get limit=none | 200; origin 65 | = | = | = | = |
| route=direct-http method=get limit=1 | 63 too-large sent=65; origin 65 | = | = | = | = |
| route=direct-http method=post limit=none | 200; origin 86+62 | = | = | = | = |
| route=direct-http method=post limit=1 | 63 too-large sent=148; origin 86+62 | = | = | = | = |
| route=direct-https method=get limit=none | 200; origin 65 | = | = | = | = |
| route=direct-https method=get limit=1 | 63 too-large sent=65; origin 65 | = | = | = | = |
| route=direct-https method=post limit=none | 200; origin 86+62 | = | = | = | = |
| route=direct-https method=post limit=1 | 63 too-large sent=148; origin 86+62 | = | = | = | = |
| route=absolute-open method=get limit=none | 200; proxy 117 | = | = | = | = |
| route=absolute-open method=get limit=1 | 63 too-large sent=118; proxy 118 | = | = | = | = |
| route=absolute-open method=post limit=none | 200; proxy 139+62 | = | = | = | = |
| route=absolute-open method=post limit=1 | 63 too-large sent=201; proxy 139+62 | = | = | = | = |
| route=connect-open method=get limit=none | 200; proxy 89, origin 66 | = | = | = | = |
| route=connect-open method=get limit=1 | 63 too-large sent=155; proxy 89, origin 66 | 63 too-large sent=66; proxy 89, origin 66 | 63 too-large sent=66; proxy 89, origin 66 | 63 too-large sent=66; proxy 89, origin 66 | 63 too-large sent=66; proxy 89, origin 66 |
| route=connect-open method=post limit=none | 200; proxy 89, origin 87+62 | = | = | = | = |
| route=connect-open method=post limit=1 | 63 too-large sent=238; proxy 89, origin 87+62 | 63 too-large sent=149; proxy 89, origin 87+62 | 63 too-large sent=149; proxy 89, origin 87+62 | 63 too-large sent=149; proxy 89, origin 87+62 | 63 too-large sent=149; proxy 89, origin 87+62 |
| route=absolute-basic method=get limit=none | 200; proxy 163 | = | = | = | = |
| route=absolute-basic method=get limit=1 | 63 too-large sent=163; proxy 163 | = | = | = | = |
| route=absolute-basic method=post limit=none | 200; proxy 184+62 | = | = | = | = |
| route=absolute-basic method=post limit=1 | 63 too-large sent=246; proxy 184+62 | = | = | = | = |
| route=connect-basic method=get limit=none | 200; proxy 134, origin 66 | = | = | = | = |
| route=connect-basic method=get limit=1 | 63 too-large sent=200; proxy 134, origin 66 | 63 too-large sent=66; proxy 134, origin 66 | 63 too-large sent=66; proxy 134, origin 66 | 63 too-large sent=66; proxy 134, origin 66 | 63 too-large sent=66; proxy 134, origin 66 |
| route=connect-basic method=post limit=none | 200; proxy 134, origin 87+62 | = | = | = | = |
| route=connect-basic method=post limit=1 | 63 too-large sent=283; proxy 134, origin 87+62 | 63 too-large sent=149; proxy 134, origin 87+62 | 63 too-large sent=149; proxy 134, origin 87+62 | 63 too-large sent=149; proxy 134, origin 87+62 | 63 too-large sent=149; proxy 134, origin 87+62 |

### The wire check's cases (`wire`)

A cell: the outcome. `wire.mjs` compares each head libcurl's trace shows with the stand-in's.

| case | F | O | G | X | C |
|---|---|---|---|---|---|
| case=absolute-basic | 200 | = | = | = | = |
| case=connect-basic | 200 | = | = | = | = |
| case=tunnel-basic | 200 | = | = | = | = |
| case=absolute-bytes | 200 | = | = | = | = |
| case=connect-utf8 | 200 | = | = | = | = |
| case=absolute-https-proxy | 200 | = | = | = | = |

### What split

- i5stall case=h2-via-https floor-7.85.0: 7× 200 h2, 3× 28 timeout sent=154 / 8× 200 h2, 2× 28 timeout sent=154
