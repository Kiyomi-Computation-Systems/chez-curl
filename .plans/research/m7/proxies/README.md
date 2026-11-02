# M7 research: proxies given by URL, `http://` and `https://`

Measured 2026-11-02 for the M7 plan, area proxies ([ADR-0033](../../../decisions/0033-m7s-scope.md),
decision 2; [ADR-0024](../../../decisions/0024-what-a-transfer-reads-from-its-environment.md) promised
a proxy by URL and its own TLS fields to M7). It reports what libcurl does with `CURLOPT_PROXY` and
the options around it, on five Linux libcurls, two runs each. It recommends nothing. The Mac has not
run it: `mac.sh` is written for the maintainer.

## In short

- **`CURLOPT_PROXY` does not turn the environment's `no_proxy` off.** With `PROXY` naming a proxy,
  `no_proxy` or `NO_PROXY` naming the origin's host, or `*`, sent the transfer direct. `NOPROXY ""`
  made it go through the proxy again; `NOPROXY` set to `NULL` did not. `http_proxy`, `https_proxy`
  and `all_proxy` naming another proxy lost to `PROXY`. All five lanes alike (item 1).
- **Proxy URL forms:** no scheme is `http://`; `HTTP://` works; a path is ignored; `foo://` and
  `ftp://` fail 7, "Unsupported proxy scheme", before any connect. No port means 1080 on 7.85.0,
  8.5.0 and 8.20.0, and 80 on 8.23.0.
- **With `PROXYAUTH` unset libcurl sends Basic credentials before any challenge,** to every proxy,
  one that never asked and one that offers only Digest among them, over absolute form and over
  CONNECT. `DIGEST` and `ANY` send nothing first, then answer the 407: one round more. `ANY` chose
  Digest over Basic. Wrong credentials are not retried: the 407 is final.
- **Where credentials come from:** the proxy URL's userinfo is percent-decoded and wins over
  `PROXYUSERNAME`/`PROXYPASSWORD` (set before `PROXY` or after) and `PROXYUSERPWD`. `PROXYUSERPWD` is
  percent-decoded on all five lanes. `PROXYUSERNAME`/`PROXYPASSWORD` are percent-decoded on 7.85.0
  and both 8.5.0 builds, and sent as given on 8.20.0 and 8.23.0.
- **A UTF-8 Digest username:** 7.85.0, 8.5.0 and 8.20.0 send its bytes raw, `username="élève"`.
  8.23.0 sends `username="%C3%A9l%C3%A8ve"` and hashes the raw bytes, so a proxy that compares the
  name as sent refuses it.
- **A caller's headers and CONNECT:** with `HEADEROPT` at its default, a caller's
  `Proxy-Authorization` and custom headers in `HTTPHEADER` go to the proxy over absolute form, and
  over CONNECT go to the origin alone, inside the tunnel: the caller's proxy credentials reached the
  origin, and the CONNECT carried none. Byte for byte alike on all five lanes (item 3).
- **An `https://` proxy's TLS is separate from the origin's,** on every lane: the origin's `CAINFO`
  and verify switches never reached the proxy, and the proxy's never reached the origin.
  `PROXY_SSL_VERIFYPEER` and `PROXY_SSL_VERIFYHOST` act independently. `PROXY_CAINFO` and
  `PROXY_CAPATH` both `NULL` trust nothing (60).
- **Ubuntu's default `PROXY_CAPATH` trusts the system store beside `PROXY_CAINFO`:** with the run CA
  added to the store, a `PROXY_CAINFO` naming another CA passed on both 8.5.0 builds and on 8.23.0
  (default path `/etc/ssl/certs`), and failed on 7.85.0, which has no default path. Cleared, it
  failed on all four.
- **Guix's 8.20.0 writes `SSL_CERT_FILE` over a set `PROXY_CAINFO`, and `SSL_CERT_DIR` over a
  cleared `PROXY_CAPATH`.** The other four ignore both.
- **Ubuntu's 8.5.0 with GnuTLS never reads an `https://` origin's answer through an `https://`
  proxy:** the tunnel delivered it, and the transfer timed out, 28, 18 cases of 18 in each run.
- **A refused CONNECT** (403, 407, 502) is 56 on 7.85.0 and both 8.5.0 builds and 7 on 8.20.0 and
  8.23.0, with `HTTP_CONNECTCODE` the status; over absolute form the proxy's status is the
  response, code 0. `PROXY_ERROR` read 0 in every case. `USED_PROXY` (8.20.0, 8.23.0) read 1 for
  every transfer that tried a proxy, failures included, and 0 for a direct one and for an unknown
  proxy scheme. 7.85.0 counts a CONNECT in
  `REQUEST_SIZE`, 89 bytes for a refused one; 8.5.0 and later do not (item 5).
- **Nothing split.** The two runs agree on every case, on every lane (`results/splits.txt`).

## What was run

`probe.c` makes one transfer through the multi interface, stepped as chez-curl's engine steps it:
`curl_multi_perform`, `curl_multi_info_read`, then `curl_multi_poll` for at most 100 ms, until done
or 20 s. It gets the engine's options: `PROTOCOLS_STR` and `REDIR_PROTOCOLS_STR` `"http,https"`,
`NOSIGNAL` 1, `FOLLOWLOCATION` 0, `SSL_VERIFYPEER` 1, `SSL_VERIFYHOST` 2, and `TIMEOUT_MS` 10000. It
sets no proxy option, CA or header unless the case's steps do, in the order the case gives. For an
`https://` origin the cases give `CAINFO` the run CA and `CAPATH` `NULL`, chez-curl's `ca-file`,
unless they say otherwise. It prints every environment variable it ran with, each step, libcurl's
debug text and every header byte it sent, then a `done` line: the code, the error buffer,
`RESPONSE_CODE`, `HTTP_CONNECTCODE`, `PROXY_ERROR`, `USED_PROXY` (8.7.0 headers and later),
`REQUEST_SIZE`, `NUM_CONNECTS`, `PROXYAUTH_AVAIL`, `PROXY_SSL_VERIFYRESULT`, `SSL_VERIFYRESULT` and
the body. Then the server's log of the case.

`server.mjs`, Node's standard library alone, parses HTTP/1.1 itself on `node:net` on every face, so a
407 round on one kept-alive connection works, CONNECT included. It logs each connection, TLS
handshake and client alert, the whole head of every request as it arrived, each
`Proxy-Authorization` decoded and judged, what it answered, and each tunnel's byte counts, under the
case. Its faces, all on 127.0.0.1:

| face | what it is |
|---|---|
| `o-raw`, `o-tls` | origins, plaintext and TLS (the good leaf, ALPN http/1.1): 200 `origin FACE METHOD TARGET` |
| `p-open`, `p-other` | open proxies. Absolute form is answered by the proxy itself, 200 `proxy FACE METHOD TARGET`: nothing is forwarded. CONNECT to an origin face gets 200 and a counted tunnel |
| `p-basic`, `p-digest`, `p-both` | as `p-open` once a valid Basic, Digest (MD5, `qop=auth`), or either arrives; else 407 with `Proxy-Authenticate` (Basic, then Digest, for `p-both`), a 20-byte body, keep-alive |
| `p-403`, `p-502` | that status to every request, keep-alive |
| `p-close`, `p-partial` | read the head, then close, nothing written; or write `HTTP/1.1 200` and close |
| `tp-good`, `tp-expired`, `tp-wrong`, `tp-untrusted` | `p-open` over TLS, each serving one leaf of the run's PKI |
| `refused` | a port bound and closed before the run |

The proxies take three users, as bytes: `alice`/`s3cret`, `al@ice`/`p:ss%w`, and UTF-8
`élève`/`päss`. `tests/make-test-pki.sh` makes the PKI per run; `run.sh` adds `cadir/` and
`otherdir/`, each a CA with its hash link. A plaintext face that gets bytes no request line starts
with (a TLS ClientHello) answers 400 and closes, as an HTTP server does.

`run.sh` runs 253 cases on one lane, each under `env -i`, so a case's environment is the `env:` steps
it names and nothing else; the probe sets those before `curl_global_init`. Every `env` line in the
logs names only `http_proxy`, `https_proxy`, `all_proxy`, `no_proxy`, `NO_PROXY`, `SSL_CERT_FILE` or
`SSL_CERT_DIR`, in the cases that set them; the other 2,414 case runs printed `env (none)`.
`docker.sh` fetches the apt packages once, in a container that does nothing else, then runs every
case in a container with `--network none`: its log's line 2 lists one interface, `lo`. Its
`sysstore` pass adds each run's CA to the container's system store with `update-ca-certificates`,
checks `openssl verify` passes the good leaf by the store's bundle and its directory, and reruns the
cases that read a default CA.

A first pass of every lane, with libcurl's `Trying` lines left out of the probe's output, was
discarded: it could not show which port a proxy URL with no port reached. Every log under `results/`
is from the files as they stand.

Rerun, from the repository's root:

```sh
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/proxies/run.sh guix-8.20.0' < /dev/null
sh .plans/research/m7/proxies/docker.sh build/verify/c823/lane1/curl-current          # main
sh .plans/research/m7/proxies/docker.sh build/verify/c823/lane1/curl-current sysstore
NODE="$(asdf which node)" sh .plans/research/m7/proxies/mac.sh                        # the Mac
```

`summarize.mjs` reads the logs: `lanes` groups the lanes by each case's cell, `headers` prints named
headers of every request a face logged, `splits` compares two runs, `cite` prints each `done` line's
place. `digest-check.mjs` recomputes each Digest response a proxy logged.

## Lanes

All x86_64. The two runs ran at once, side by side on one host, each under the other's load.

| lane | where | libcurl | TLS | default CA file, path | Node | log lines |
|---|---|---|---|---|---|---|
| `guix-8.20.0` | the Guix container | `/gnu/store/67lpb53n…-curl-8.20.0/lib/libcurl.so.4.8.0`, 8.20.0 | GnuTLS 3.8.13 | none, none | 24.18.0 | `guix-8.20.0.log:2-4` |
| `floor-7.85.0` | Docker `ubuntu:24.04` | `build/e1/ci/curl-floor`, 7.85.0 | OpenSSL 3.0.13 | `/etc/ssl/certs/ca-certificates.crt`, none | 20.10.0 | `docker.log:10-12` |
| `ubuntu-openssl-8.5.0` | Docker | `/usr/lib/x86_64-linux-gnu/libcurl.so.4.8.0`, `libcurl4t64` 8.5.0-2ubuntu10.16 | OpenSSL 3.0.13 | the bundle, `/etc/ssl/certs` | 24.18.0 | `docker.log:6`, `7709-7711` |
| `ubuntu-gnutls-8.5.0` | Docker | `libcurl-gnutls.so.4.8.0`, `libcurl3t64-gnutls` 8.5.0-2ubuntu10.16 | GnuTLS 3.8.3 | none, `/etc/ssl/certs` | 24.18.0 | `docker.log:5`, `15478-15480` |
| `current-8.23.0` | Docker | `build/verify/c823/lane1/curl-current`, 8.23.0 | OpenSSL 3.0.13 | the bundle, `/etc/ssl/certs` | 24.18.0 | `docker.log:22744-22746` |

Docker's image is `sha256:68ee2200…` (`docker.log:1`); its packages are at `docker.log:3-9`. Each
lane compiled the probe against its own headers. Every lane reports `HTTPS-proxy`.

## Reading the tables

The logs are `results/guix-8.20.0.log`, `results/docker.log` (four lanes), and
`results/docker-sysstore.log`; the second runs add `-2`. A case's evidence on a lane is its lines in
that lane's log, `[LANE] case NAME …`: `env`, `step`, `debug`, `done`, and `server:`.
`grep -n 'case NAME done' results/*.log` finds its `done` line on each lane, and `summarize.mjs
lanes` reproduces each table cell. Where lanes differ, the row names them: **G** `guix-8.20.0`,
**F** `floor-7.85.0`, **UO** `ubuntu-openssl-8.5.0`, **UG** `ubuntu-gnutls-8.5.0`, **C**
`current-8.23.0`. Where it names none, all five agree. Case names begin `I1-` to `I5-`, the item;
then `h`/`a` for an `http://` origin by absolute form, `s`/`c` for an `https://` origin by CONNECT,
`t` for an `http://` origin by CONNECT (`HTTPPROXYTUNNEL` 1).

## 1. A proxy by URL, and the environment

`p-open` is the proxy `CURLOPT_PROXY` names; `p-other` is the one the variables name. "Through"
means that proxy logged the request (for `https://`, a CONNECT and a tunnel, and the origin logged
the `GET` inside it); "direct" means only the origin logged it.

| case (`I1-h-…`, `I1-s-…`) | `PROXY` | `NOPROXY` | environment | went |
|---|---|---|---|---|
| `none` | unset | unset | none | direct |
| `opt` | `p-open` | unset | none | through `p-open` |
| `opt-no_proxy-host` | `p-open` | unset | `no_proxy=127.0.0.1` | direct |
| `opt-NO_PROXY-host` | `p-open` | unset | `NO_PROXY=127.0.0.1` | direct |
| `opt-no_proxy-star` | `p-open` | unset | `no_proxy=*` | direct |
| `opt-no_proxy-other` | `p-open` | unset | `no_proxy=example.invalid` | through `p-open` |
| `opt-noproxy-empty` | `p-open` | `""` | none | through `p-open` |
| `opt-noproxy-empty-no_proxy-host` | `p-open` | `""` | `no_proxy=127.0.0.1` | through `p-open` |
| `opt-noproxy-empty-NO_PROXY-host` | `p-open` | `""` | `NO_PROXY=127.0.0.1` | through `p-open` |
| `opt-noproxy-empty-no_proxy-star` | `p-open` | `""` | `no_proxy=*` | through `p-open` |
| `opt-noproxy-null-no_proxy-host` | `p-open` | `NULL`, set | `no_proxy=127.0.0.1` | direct |
| `opt-noproxy-host` | `p-open` | `127.0.0.1` | none | direct |
| `opt-env-proxy` | `p-open` | unset | `http_proxy`, `https_proxy` = `p-other` | through `p-open` |
| `opt-env-all_proxy` | `p-open` | unset | `all_proxy` = `p-other` | through `p-open` |
| `opt-env-proxy-no_proxy-host` | `p-open` | unset | both = `p-other`, `no_proxy=127.0.0.1` | direct |
| `env-proxy` | unset | unset | both = `p-other` | through `p-other` |
| `env-proxy-noproxy-empty-no_proxy-host` | unset | `""` | both = `p-other`, `no_proxy=127.0.0.1` | through `p-other` |
| `optempty-env-proxy` | `""` | unset | both = `p-other` | direct |

Every row answered 200, for both origins, on all five lanes, both runs; an `https://` origin through
a proxy read `HTTP_CONNECTCODE` 200. `USED_PROXY` on 8.20.0 and 8.23.0 was 1 on each "through" row and 0
on each "direct" one. libcurl's own text names the variable it read, as `Uses proxy env variable
no_proxy == '127.0.0.1'`.

The proxy URL's forms (`I1-h-form-…`, `I1-s-form-…`):

| form | `PROXY` | `http://` origin | `https://` origin |
|---|---|---|---|
| `noscheme` | `127.0.0.1:P` | through `p-open`, 200 | through, 200 |
| `HTTP` | `HTTP://127.0.0.1:P` | through, 200 | through, 200 |
| `path` | `http://127.0.0.1:P/a/path?q=1` | through, 200; the request's target is the origin's URL | through, 200 |
| `https` | `https://` `tp-good`, `PROXY_CAINFO` the run CA, `PROXY_CAPATH` `NULL` | through, 200 | through, 200; **UG** 28 (item 4) |
| `https-plainport` | `https://` naming plaintext `p-open` | 35; the proxy got a ClientHello (`first=0x16`) and answered 400 | 35 |
| `http-tlsport` | `http://` naming `tp-good` | 52, `Empty reply from server`; the proxy logged `ERR_SSL_HTTP_REQUEST` | 56, `Proxy CONNECT aborted` |
| `noscheme-tlsport` | `127.0.0.1:` `tp-good`'s port | 52 | 56 |
| `foo` | `foo://127.0.0.1:P` | 7, `Unsupported proxy scheme for 'foo://127.0.0.1:P'`, no connect | 7 |
| `ftp` | `ftp://127.0.0.1:P` | 7, the same text | 7 |
| `noport` | `http://127.0.0.1` | 7. libcurl's text: `Trying 127.0.0.1:1080...` on **G F UO UG** (`guix-8.20.0.log:474`, `docker.log:464`, `8143`, `15907`), `Trying 127.0.0.1:80...` on **C** (`docker.log:23220`) | 7, the same ports |

`foo://` and `ftp://` read `NUM_CONNECTS` 0 and `USED_PROXY` 0 (8.20.0, 8.23.0); a `noport` transfer read
`USED_PROXY` 1. On 8.20.0 the error buffer of a failed connect through a proxy names the *origin's*
port, `Failed to connect to 127.0.0.1 port <o-raw> via 127.0.0.1` (`guix-8.20.0.log:478`); 7.85.0 and
8.5.0 name the proxy's port, and 8.23.0 the proxy's address and port, `127.0.0.1:P over proxy
127.0.0.1` (`I5-*-refused`).

## 2. Proxy credentials

### `PROXYAUTH`, and how many requests

The proxy URL's userinfo is `alice:s3cret`. Each cell is the requests the proxy logged, in order, and
the result. "Basic" is `Proxy-Authorization: Basic YWxpY2U6czNjcmV0`. Over absolute form
(`I2-a-PROXY-AUTH`):

| proxy offers | `PROXYAUTH` unset | `BASIC` | `DIGEST` | `ANY` |
|---|---|---|---|---|
| nothing, `p-open` | Basic; 200 | Basic; 200 | nothing; 200 | nothing; 200 |
| Basic, `p-basic` | Basic; 200 | Basic; 200 | nothing; 407 | nothing, then Basic; 200 |
| Digest, `p-digest` | Basic; 407 | Basic; 407 | nothing, then Digest; 200 | nothing, then Digest; 200 |
| both, `p-both` | Basic; 200 | Basic; 200 | nothing, then Digest; 200 | nothing, then Digest; 200 |

Over CONNECT (`I2-c-…`) the CONNECT requests carry the same, in the same order; each 200 then tunnels to
the origin, whose `GET` carried no `Proxy-Authorization`. Each 407 is final: code 7 on **G C**, 56 on
**F UO UG**, `HTTP_CONNECTCODE` 407, the origin never reached. Every round of every case used one
connection (`NUM_CONNECTS` 1, one connection id at the proxy). `PROXYAUTH_AVAIL` read 0x1 after a
Basic challenge, 0x2 after a Digest one, 0x3 after both, and 0 with no 407. All five lanes alike but
for the CONNECT code.

The Digest header, all five lanes: `Digest username="alice", realm="m7", nonce="…",
uri="/x?case=…", cnonce="…", nc=00000001, qop=auth, response="…", algorithm=MD5`. Over absolute form
its `uri` is the request's path, not the absolute target the request line carries; over CONNECT it
is `127.0.0.1:PORT`. The cnonce is 44 characters on **F UO UG** and 16 on **G C**, so a Digest round
counts 28 bytes more in `REQUEST_SIZE` there.

### Where the credentials come from

At `p-basic`, `PROXYAUTH` unset (`I2-a-src-…`, `I2-c-src-…`). The middle column is what the proxy
decoded from the Basic header. The result is over absolute form; over CONNECT a 200 tunnelled, and a
407 failed 7 (**G C**) or 56 (**F UO UG**).

| case | credentials given | the proxy decoded | result |
|---|---|---|---|
| `basic-unset` | URL `alice:s3cret@` | `alice:s3cret` | 200 |
| `url-pct` | URL `al%40ice:p%3Ass%25w@` | `al@ice:p:ss%w` | 200 |
| `url-utf8pct` | URL `%C3%A9l%C3%A8ve:p%C3%A4ss@` | UTF-8 `élève:päss` | 200 |
| `url-utf8raw` | URL with those bytes raw | UTF-8 `élève:päss` | 200 |
| `url-useronly` | URL `alice@` | `alice:` | 407 |
| `url-emptypass` | URL `alice:@` | `alice:` | 407 |
| `noscheme` | `alice:s3cret@127.0.0.1:P` | `alice:s3cret` | 200 |
| `opt-plain` | `PROXYUSERNAME` `alice`, `PROXYPASSWORD` `s3cret` | `alice:s3cret` | 200 |
| `opt-raw` | `al@ice`, `p:ss%w` | `al@ice:p:ss%w` | 200 |
| `opt-pct` | `al%40ice`, `p%3Ass%25w` | **F UO UG**: `al@ice:p:ss%w`, 200. **G C**: `al%40ice:p%3Ass%25w`, 407 | split by version |
| `opt-utf8` | UTF-8 `élève`, `päss` | UTF-8 `élève:päss` | 200 |
| `user-only-opt` | `PROXYUSERNAME` `alice` alone | `alice:` | 407 |
| `userpwd-plain` | `PROXYUSERPWD` `alice:s3cret` | `alice:s3cret` | 200 |
| `userpwd-raw` | `al@ice:p:ss%w`, split at the first colon | `al@ice:p:ss%w` | 200 |
| `userpwd-pct` | `al%40ice:p%3Ass%25w` | `al@ice:p:ss%w`, on all five | 200 |
| `url-wrong-opt-right` | URL `alice:wrong@`, then the options `alice`, `s3cret` | `alice:wrong` | 407 |
| `opt-right-url-wrong` | the options first, then that URL | `alice:wrong` | 407 |
| `url-right-opt-wrong` | URL `alice:s3cret@`, options `alice`, `wrong` | `alice:s3cret` | 200 |
| `url-wrong-userpwd-right` | URL `alice:wrong@`, `PROXYUSERPWD` `alice:s3cret` | `alice:wrong` | 407 |
| `url-right-userpwd-wrong` | the reverse | `alice:s3cret` | 200 |

So the URL's userinfo wins over both options. The order did not matter where it was tried:
`PROXYUSERNAME` and `PROXYPASSWORD` set after `PROXY` and before it. Over CONNECT, none of the 292
origin requests of item 2's cases, both runs, carried a `Proxy-Authorization`. `opt-pct`'s rows:
`docker.log:2089` (F), `9767` (UO), `17416` (UG), `guix-8.20.0.log:1985` (G), `docker.log:24786` (C).

### Digest usernames

At `p-digest`, `PROXYAUTH` `DIGEST` (`I2-a-dsrc-…`, `I2-c-dsrc-…`): two requests each, the second's
`username=` below.

| case | given | **G F UO UG** sent | **C** sent | result |
|---|---|---|---|---|
| `dsrc-url-pct` | URL `al%40ice:p%3Ass%25w@` | `username="al@ice"` | the same | 200 |
| `dsrc-userpwd-raw` | `PROXYUSERPWD` `al@ice:p:ss%w` | `username="al@ice"` | the same | 200 |
| `dsrc-url-utf8pct` | URL `%C3%A9l%C3%A8ve:p%C3%A4ss@` | the UTF-8 bytes raw | `username="%C3%A9l%C3%A8ve"` | 200; **C** 407 (CONNECT: 7) |
| `dsrc-opt-utf8` | `PROXYUSERNAME` UTF-8 `élève` | the UTF-8 bytes raw | `username="%C3%A9l%C3%A8ve"` | 200; **C** 407 (CONNECT: 7) |

`results/digest-check.txt` recomputes each logged Digest response from the header's own fields: on
8.23.0 the four UTF-8 headers per run reproduce only from the percent-decoded name, so it hashed the
raw bytes and wrote them encoded. The other 76 per run reproduce from the bytes as sent, and the 30
per run with a wrong password from neither. `dsrc-opt-utf8`: `docker.log:25119` (C),
`guix-8.20.0.log:2314` (G).

### Wrong credentials

| case | given | requests | absolute form | CONNECT |
|---|---|---|---|---|
| `wrong-basic` | `alice:wrong`, `p-basic` | Basic once | 0, status 407 | 7 **G C**, 56 **F UO UG**; connectcode 407 |
| `wrong-user-basic` | `mallory:s3cret`, `p-basic` | Basic once | 0, 407 | the same |
| `wrong-digest` | `alice:wrong`, `DIGEST`, `p-digest` | nothing, then Digest | 0, 407 | the same |
| `wrong-any-both` | `alice:wrong`, `ANY`, `p-both` | nothing, then Digest | 0, 407 | the same |
| `wrong-any-digest` | `alice:wrong`, `ANY`, `p-digest` | nothing, then Digest | 0, 407 | the same |

## 3. A caller's headers and the proxy

The caller's `HTTPHEADER` is `Proxy-Authorization: Basic YWxpY2U6czNjcmV0` (alice's, which `p-basic`
takes) and `X-Caller: m7`. Where libcurl's own credentials are given, they are `PROXYUSERPWD`
`al@ice:p:ss%w`, `Basic YWxAaWNlOnA6c3Mldw==`, which `p-basic` takes too. `HEADEROPT` is unset, but
in `unified`.

| case | the proxy got | the origin got | result |
|---|---|---|---|
| `I3-a-open-hdrs` | both headers, in the one request | not reached | 200 |
| `I3-a-basic-hdrs` | both; the caller's header passed `p-basic` | not reached | 200 |
| `I3-a-basic-hdrs-creds` | `Proxy-Authorization` twice: libcurl's, then the caller's, and `X-Caller` | not reached | 200 |
| `I3-c-open-hdrs` | a CONNECT with neither | both headers | 200 |
| `I3-c-basic-hdrs` | a CONNECT with neither: 407 | not reached | 7 **G C**, 56 **F UO UG**; connectcode 407 |
| `I3-c-basic-hdrs-creds` | a CONNECT with libcurl's `Proxy-Authorization` alone | the caller's `Proxy-Authorization` and `X-Caller` | 200 |
| `I3-t-…` (`HTTPPROXYTUNNEL` 1, `http://` origin) | as `I3-c-…`, row for row | as `I3-c-…`, in plaintext | as `I3-c-…` |
| `I3-a-open-unified` | both headers | not reached | 200 |
| `I3-c-open-unified`, `I3-t-open-unified` | both, on the CONNECT | both again | 200 |
| `I3-a-open-proxyheader` (`PROXYHEADER` `X-Proxy-Only: 1`, `HTTPHEADER` `X-Caller`) | both | not reached | 200 |
| `I3-c-open-proxyheader`, `I3-t-…` | `X-Proxy-Only` alone, on the CONNECT | `X-Caller` alone | 200 |

The whole heads are the same on all five lanes: `summarize.mjs headers
proxy-authorization,x-caller,x-proxy-only '^I3-' results/guix-8.20.0.log results/docker.log` gives one
value per case across them. A CONNECT's
head is `CONNECT 127.0.0.1:PORT HTTP/1.1`, `Host: 127.0.0.1:PORT`, `Proxy-Connection: Keep-Alive`, and
`Proxy-Authorization` when libcurl has credentials. An absolute-form request is the direct request with
the absolute URL as its target and `Proxy-Connection: Keep-Alive` added (`I1-h-none` against
`I1-h-opt`). `I3-c-open-hdrs`: `guix-8.20.0.log:4449`, `docker.log:4730` (F), `27257` (C).

## 4. An `https://` proxy's TLS

### Verification switches and the four leaves

`PROXY_CAINFO` the run CA, `PROXY_CAPATH` `NULL`. `v11` is `PROXY_SSL_VERIFYPEER` 1 and
`PROXY_SSL_VERIFYHOST` 2, `v01` peer 0 and host 2, `v10` peer 1 and host 0, `v00` both off
(`I4-a-LEAF-vXY`, `I4-c-LEAF-vXY`). 0 means the proxy logged the request and the transfer answered
200.

| leaf | `v11` | `v01` | `v10` | `v00` |
|---|---|---|---|---|
| good | 0 | 0 | 0 | 0 |
| expired | 60 | 0 | 60 | 0 |
| wrong-host | 60 | 60 | 0 | 0 |
| untrusted | 60 | 0 | 60 | 0 |

All five lanes, for both origins; but over CONNECT every 0 is 28 on **UG** (below). On a 60 the
proxy logged a TLS connection and no request. What it saw of the refusal, and libcurl's
`PROXY_SSL_VERIFYRESULT` (`I4-a-*-v11`):

| leaf | **F UO** | **C** | **G UG** |
|---|---|---|---|
| expired | the client's alert, `certificate expired` (45); 10 | a finished handshake, then a close; 10 | a finished handshake, then a close; 1026 |
| wrong-host | a finished handshake; 1 | a finished handshake; 1 | a finished handshake; 0 |
| untrusted | the client's alert, `unknown ca` (48); 20 | a finished handshake; 20 | a finished handshake; 66 |

The error buffers name the fault on each backend: OpenSSL's `certificate has expired`, `unable to get
local issuer certificate`, `no alternative certificate subject name matches target host name`
(8.23.0: `target IPv4 address`); GnuTLS's `certificate subject name (chez-curl test leaf) does not
match target host name`, and `certificate has expired` and `certificate signer not trusted` on
8.20.0 where 8.5.0 gives both one text, `server certificate verification failed`.

### `PROXY_CAINFO` and `PROXY_CAPATH`

At `tp-good`: `ca` the run CA, `other` the PKI's second CA (which signed only the untrusted leaf),
`null` set to `NULL`, `default` never set;
`cadir` the run CA's hashed directory (`I4-a-ca-X-capath-Y`, `I4-c-ca-X-capath-Y`). The system store
does not trust the run CA:

| `PROXY_CAINFO` | `PROXY_CAPATH` `NULL` | default | `cadir` |
|---|---|---|---|
| `ca` | 0 | 0 | 0 |
| `other` | 60 | 60 | 0 |
| `null` | 60 | 60 | 0 |
| `default` | 60 | 60 | 0 |

All five lanes, both origins; over CONNECT **UG**'s 0s are 28.

With the run CA in the system store (`docker.sh … sysstore`; `docker-sysstore.log:14-16`, `947-949`,
`2059-2061` and `2967-2969` show `update-ca-certificates` exit 0 and `openssl verify` OK by the bundle
and by the directory, on each lane):

| `PROXY_CAINFO` | `PROXY_CAPATH` `NULL` | default | `cadir` |
|---|---|---|---|
| `ca` | 0 | 0 | 0 |
| `other` | 60 | 60 **F**; 0 **UO UG C** | 0 |
| `null` | 60 | 60 **F**; 0 **UO UG C** | 0 |
| `default` | 0 **F UO C**; 60 **UG** | 0 | 0 |

So a default `PROXY_CAPATH` trusts the system store beside a `PROXY_CAINFO` on both 8.5.0 builds and
on 8.23.0, whose default path is `/etc/ssl/certs`, and not on 7.85.0, which has none. Clearing it
stops that on all four. A default `PROXY_CAINFO` is the bundle on **F UO C**, and none on **UG**.
`null` with `NULL` failed on all four with the run CA in the store: no fallback to the TLS library's
own default store.

The origin, direct (`I4-o-…`), the same way: `CAINFO` `other` with `CAPATH` default passed on **UO
UG C** and failed on **F**; with `CAPATH` `NULL` it failed on all four. Without the run CA in the store
every `I4-o-` case failed 60. `I4-a-ca-other-capath-default`: `docker-sysstore.log:132` (F), `1081`
(UO), `2177` (UG), `3109` (C); without the store, `docker.log:5615`, `13329`, `20767`, `28185`,
`guix-8.20.0.log:5307`.

### The origin's TLS and the proxy's are separate

| case | settings | result |
|---|---|---|
| `I4-c-sep-both-set` | origin `CAINFO` and `PROXY_CAINFO` the run CA | 0; **UG** 28 |
| `I4-c-sep-origin-ca-only` | origin `CAINFO` the run CA, no proxy CA | 60 at the proxy; no request |
| `I4-a-sep-origin-ca-only` | the same, `http://` origin | 60 at the proxy |
| `I4-c-sep-origin-noverify` | origin `SSL_VERIFYPEER` and `VERIFYHOST` 0, no proxy CA | 60 at the proxy |
| `I4-c-sep-proxy-ca-only` | `PROXY_CAINFO` the run CA, origin `CAINFO` the other CA | CONNECT 200, then the origin fails: 60, **UO** 35 |
| `I4-c-sep-proxy-noverify` | proxy verification off, `tp-untrusted`, origin `CAINFO` the other CA | CONNECT 200, then 60, **UO** 35 |

**UO**'s 35 is `OpenSSL SSL_connect: SSL_ERROR_SYSCALL`, `SSL_VERIFYRESULT` 1, where **F C** read 20
and **G UG** 66 (`docker.log:14902`); the origin logged the client's `unknown ca` alert on **F** and
**UO** (`docker.log:7135`, `14909`). With the proxy's verification off, `PROXY_SSL_VERIFYRESULT` still
read the untrusted leaf's failure, 20, on **F UO C**, and 0 on **G UG**.

### Guix's `SSL_CERT_FILE` and `SSL_CERT_DIR`

An `http://` origin, so only the proxy's TLS is read (`I4-a-env-…`):

| case | variable | `PROXY_CAINFO`, `PROXY_CAPATH` | **G** | **F UO UG C** |
|---|---|---|---|---|
| `certfile-other-proxyca-ca` | `SSL_CERT_FILE` the other CA | the run CA, `NULL` | 60 | 0 |
| `certfile-ca-proxyca-other` | `SSL_CERT_FILE` the run CA | the other CA, `NULL` | 0 | 60 |
| `certfile-ca-proxyca-default` | `SSL_CERT_FILE` the run CA | unset | 0 | 60 |
| `certfile-ca-proxyca-null` | `SSL_CERT_FILE` the run CA | `NULL`, `NULL` | 0 | 60 |
| `certdir-cadir-proxyca-other` | `SSL_CERT_DIR` `cadir` | the other CA, `NULL` | 0 | 60 |
| `certdir-cadir-proxyca-null` | `SSL_CERT_DIR` `cadir` | `NULL`, `NULL` | 0 | 60 |

`certfile-other-proxyca-ca`: `guix-8.20.0.log:6708`; `certfile-ca-proxyca-other`: `6734`; the other
lanes at `docker.log:7206`, `7224` (F) and on.

### Ubuntu's 8.5.0 with GnuTLS: TLS inside TLS stalls

On **UG**, every `https://` origin through an `https://` proxy whose two handshakes passed ended 28,
`Operation timed out after 10000 milliseconds with 0 bytes received`: 18 cases of 18 in each main run,
and 9 of 9 in each sysstore run; no other lane timed out in any case. The proxy logged the CONNECT, the origin logged the `GET` and its 200, and the
tunnel carried 1,520 and 1,518 bytes down in the two runs (`docker.log:16747`, `docker-2.log:16749`),
yet libcurl read none, though the probe called `curl_multi_perform` at least every 100 ms
(`I1-s-form-https`: `docker.log:16735`). An `http://` origin through the same proxy, and an
`https://` one through a plaintext proxy, passed.

## 5. Proxy failures

| case | absolute form (`I5-a-`) | CONNECT (`I5-c-`, `I5-t-`) |
|---|---|---|
| `refused` | 7; `REQUEST_SIZE` 0, `NUM_CONNECTS` 0 | 7; the same |
| `noresolve`, `nonesuch.invalid` | 5, `Could not resolve proxy: nonesuch.invalid`; 0, 0 | 5; the same |
| `403` | 0, status 403, the proxy's body; `REQUEST_SIZE` 121 | 7 **G C**, 56 **F UO UG**; connectcode 403; `REQUEST_SIZE` 0, **F** 89 |
| `407`, no credentials | 0, status 407; 121; `PROXYAUTH_AVAIL` 0x1 | 7 or 56; connectcode 407; 0, **F** 89 |
| `502` | 0, status 502; 121 | 7 or 56; connectcode 502; 0, **F** 89 |
| `close`, nothing written | 52, `Empty reply from server`; 123 | 56, `Proxy CONNECT aborted`; 0, **F** 89 |
| `partial`, `HTTP/1.1 200` then a close | 52; 125 | 56; 0, **F** 89 |
| `https-refused`, an `https://` proxy | | 7; 0 |

`PROXY_ERROR` read 0 in all of them, on every lane. `USED_PROXY` read 1 in all of them on 8.20.0 and
8.23.0. A refused CONNECT's text is `Received HTTP code 403 from proxy after CONNECT` on **F**, and
`CONNECT tunnel failed, response 403` on the others. `I5-c-403`: `guix-8.20.0.log:7055`,
`docker.log:7483` (F), `15252` (UO), `22518` (UG), `30111` (C).

`REQUEST_SIZE` across the items: 7.85.0 counts each CONNECT's bytes, 89 for a bare one, so a CONNECT
the proxy refused reads 89 there and 0 on the others; through a tunnel 7.85.0 reads the CONNECT plus
the origin's request (`I1-s-opt` 158 against 69). Over absolute form every lane counts the request
the proxy got, each 407 round included (`I2-a-basic-any` 299).

## What varies by version or backend

- A refused CONNECT: 56 on 7.85.0 and both 8.5.0 builds, 7 on 8.20.0 and 8.23.0 (items 2, 3, 5).
- `PROXYUSERNAME`/`PROXYPASSWORD` percent-decoded on 7.85.0 and 8.5.0, not on 8.20.0 and 8.23.0.
- A UTF-8 Digest username percent-encoded on 8.23.0 alone.
- The Digest cnonce's length, and so `REQUEST_SIZE`, before and after 8.20.0.
- `REQUEST_SIZE` counts a CONNECT on 7.85.0 alone.
- A proxy URL with no port: 1080 on 7.85.0, 8.5.0 and 8.20.0, 80 on 8.23.0.
- Default `PROXY_CAPATH` `/etc/ssl/certs` on both 8.5.0 builds and 8.23.0, none on 7.85.0 and
  8.20.0; default `PROXY_CAINFO` the bundle on the OpenSSL builds, none on the GnuTLS ones.
- Guix's 8.20.0 takes the proxy's CA from `SSL_CERT_FILE` and `SSL_CERT_DIR`.
- Ubuntu's GnuTLS 8.5.0 stalls on TLS inside TLS; Ubuntu's OpenSSL 8.5.0 reports an origin's failed
  verification inside an `https://` proxy as 35.
- The texts: the refused connect's error buffer, the TLS verification texts, and `PROXY_SSL_VERIFYRESULT`'s
  numbering (OpenSSL's X.509 codes, GnuTLS's status bits), which GnuTLS leaves 0 with verification
  off.

## What split

Nothing. `results/splits.txt` compares each pass's two runs case by case, each line normalized
(ports to face names, connection ids, nonces, paths) and less what moves by design: TLS byte counts,
which an ECDSA signature's length changes by a byte or two; a ClientHello's random bytes; pointers in
libcurl's text; the leaf's dates; a timeout's own millisecond count; and how Node saw a client hang up
after refusing a leaf (`ECONNRESET`, `EPIPE`, or nothing). Each pass reads `0 case(s) differ`; 38
cases' lines came in another order.

## What was not measured

- **The Mac.** `mac.sh` runs every case on Apple's 8.7.1 with its default backend (LibreSSL, whose
  keychain fallback can undo a CA file) and with `CURL_SSL_BACKEND=secure-transport`; it skips
  `I5-*-noresolve`, whose lookup would leave loopback there. Not run: `results/mac-8.7.1-*.log` will
  hold it.
- **The cause of UG's stall,** in libcurl's source; and whether UO's 35 holds for an origin's failed
  verification through a plaintext proxy. No case has one.
- **Bodies through a proxy.** Every case is a `GET` with no body, so a 407 round's rewind of a
  request body is unmeasured.
- **A 407 with `Connection: close`,** and a proxy that drops the connection between rounds: the
  stand-ins keep every connection alive.
- **Connection reuse across transfers through a proxy:** each probe makes one transfer.
- **HTTP/2 to the origin through a proxy:** the origin offers http/1.1 alone.
- **A proxy named by host name,** and IPv6: every proxy is `127.0.0.1` but the one that does not
  resolve.
- SOCKS, NTLM, Negotiate and HTTPS2 proxies, by the brief.

## Files

| file | what it is |
|---|---|
| `probe.c`, `server.mjs`, `run.sh` | the probe, the stand-ins, one lane's cases |
| `docker.sh` | the four Docker lanes, `main` or `sysstore` |
| `mac.sh` | the Mac's two passes |
| `summarize.mjs`, `digest-check.mjs` | readers of the logs |
| `results/guix-8.20.0.log`, `-2.log` | the container, two runs |
| `results/docker.log`, `-2.log` | 7.85.0, 8.5.0 with OpenSSL and with GnuTLS, 8.23.0, two runs |
| `results/docker-sysstore.log`, `-2.log` | the same four with the run CA in the system store, the cases that read a default CA |
| `results/splits.txt` | `summarize.mjs splits` for each pass's two runs |
| `results/digest-check.txt` | `digest-check.mjs` over both runs of the main passes |
