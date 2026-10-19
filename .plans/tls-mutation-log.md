# TLS and HTTP/2 mutation log (M1 slice 2)

- **Date:** 2026-10-18, branch `m1/tls-and-h2`, on top of `79c6df1`.
- **Plan:** [M1 plan](2026-10-18-m1-plan.md) §8. **Records:** ADR-0005, amended a second time
  on 2026-10-18.
- **Scratch:** everything named here lives under `build/verify/m1s2/`:
  - `measure/`: the measurement scripts and their outputs;
  - `samples/`: raw `openssl` outputs;
  - `libressl-3.3.6-node20/`: LibreSSL, built in the Node 20.10.0 image.

## Part 1: measured before the design was settled

### 1.1 Where

| Implementation | Where | Node |
|---|---|---|
| OpenSSL 3.5.7 | the Guix container | 24.18.0 |
| OpenSSL 3.0.13 | Docker `ubuntu:24.04`, noble's `openssl` package | 18.19.1, noble's `nodejs` |
| OpenSSL 3.0.11 | Docker `node:20.10.0-bookworm` | 20.10.0 |
| LibreSSL 3.3.6 | built from `libressl-3.3.6.tar.gz` (sha256 `3f28849365e1190db2baf9014ff9686012c25b1ca6df8b3a085f789e24fe4b9a`, matching OpenBSD's `SHA256` file) in `node:20.10.0-bookworm` | 20.10.0 |
| LibreSSL 3.3.6 | Docker `alpine:3.14`, the `libressl` package, whose binary is `libressl` | 14.21.3 |

The Mac's `/usr/bin/openssl` is LibreSSL 3.3.6, by its release, and has not run.

### 1.2 The material

`tests/make-test-pki.sh`, checked by `measure/pki-check.sh`. Each of the five gave:
- exit 0, an empty stdout and stderr, in under 2 s;
- exactly the ten files;
- serials 01, 02, 03 from the run CA and 01 from the second;
- the SAN lines in §1.3;
- `openssl verify -CAfile ca.pem` giving OK, error 10, OK and error 20;
- the good key matching its certificate.

Each refusal gave the same answer everywhere:

| Call | Exit | First line on stderr |
|---|---|---|
| no argument | 2 | `make-test-pki: it takes 1 argument, and was given 0` |
| a missing DIR | 2 | `make-test-pki: DIR is not a directory` |
| a non-empty DIR | 2 | `make-test-pki: DIR is not empty` |
| `OPENSSL=false` | 1 | `make-test-pki: failed: false ecparam …` |
| `OPENSSL=/no/such/openssl` | 1 | `make-test-pki: failed: /no/such/openssl ecparam …` |

The first draft's config said `prompt = no`, with `CN = placeholder` under its
distinguished-name section. On LibreSSL every leaf came out `CN=placeholder`, while
OpenSSL used `-subj`, and every leaf still verified (`traps.md`). The script's config has
no subject.

### 1.3 `openssl` as the checker

Node served each leaf (`measure/tls-faces.mjs`), and `measure/checker.sh` ran:

```
openssl s_client -connect 127.0.0.1:PORT -servername localhost -CAfile ca.pem -showcerts -alpn h2,http/1.1 </dev/null
```

All five gave exactly this. Each status was 0, and each served leaf was its file.

| Leaf | Verify errors (stderr) | `Verify return code` (stdout) | ALPN | SAN line of `x509 -text` |
|---|---|---|---|---|
| good | none | 0 | `h2` | `DNS:localhost, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1` |
| expired | 10 | 10 | `h2` | the same |
| wrong-host | none | 0 | `h2` | `DNS:wrong-host.invalid` |
| untrusted | 20, 21 | 21 | `h2` | the same as good |

- **The ALPN** here is the measuring server's, which offered `h2`.
- **The second CA:** `untrusted.pem` verifies against `other-ca.pem` everywhere, and
  `good.pem` does not.
- **The same commands differ:**
  - **`-verify_return_error`:** the untrusted leaf's code is 20 everywhere. OpenSSL exits 1
    on each failure, and LibreSSL exits 0.
  - **LibreSSL indents `Verify return code`** by four spaces.
  - **OpenSSL 3.5.7 writes `Connecting to 127.0.0.1`** on stderr.
  - **The verify errors go to stderr**, and the return code to stdout, in both.
  - **`-subject` prints `CN=good` in OpenSSL 3.5.7, `CN = good` in 3.0, and ` /CN=good`
    in LibreSSL.**
- **LibreSSL 3.3.6 has no `-verify_hostname` or `-verify_ip`,** for `verify` or `s_client`,
  and no `x509 -checkhost`, `-checkip` or `-ext`. Each prints its usage. Its fingerprint
  label is `SHA256 Fingerprint=`, where OpenSSL's is `sha256 Fingerprint=`.
- **On OpenSSL**, `-verify_hostname localhost` gives code 62 for wrong-host, and
  `-verify_ip 127.0.0.1` gives 64. No check uses either.

### 1.4 Node (`measure/node-tls.mjs`, `measure/h2-run2.sh`)

Node 20.10.0 and 24.18.0 gave the same answers, apart from the version line and the
ports:

| Question | Answer |
|---|---|
| `https.createServer` default ALPN, offered `h2,http/1.1` | `http/1.1`. Offered only `h2`, `s_client` wrote "No ALPN negotiated", read here as none. Fix round 3 showed it was a refusal, alert 120 (Part 4) |
| `resetAndDestroy()` on a TLS server socket | throws `ERR_INVALID_HANDLE_TYPE`, and nothing reaches the client |
| `net` socket wrapped in `tls.TLSSocket`, the `net` socket reset | client: `"hello"`, then `ECONNRESET` |
| client `tls.connect({socket})`, its `net` socket reset | server: `end` |
| `http2` `stream` event's 4th argument | `rawHeaders`, in wire order |
| `createSecureServer`, no `allowHTTP1`, offered none or `http/1.1` | "No ALPN negotiated", and an `unknownProtocol` event. This was measured with a listener attached, so it says nothing of Node's own handling. With none, Node writes an `HTTP/1.0 403` text (Part 3) |
| the same, offered `h2,http/1.1` | `h2` |

**h2c bytes** for `GET /status/200`, answered with `:status` and `content-length` and
`sendDate: false`:

| Client sends | Server writes | End |
|---|---|---|
| preface, an empty SETTINGS frame, HEADERS | an empty SETTINGS frame, a SETTINGS ACK, HEADERS `88 0f 0d 02 31 31`, DATA `status 200\n` with END_STREAM | idle, until the probe's bound |
| the same, then GOAWAY | the same frames, with the server's own GOAWAY between HEADERS and DATA, and another after DATA | eof |
| the same, half-closed | the same four frames | eof, within 2 ms |

- **Default SETTINGS:** both send an empty SETTINGS frame. With explicit settings, both
  sent the same six.
- **The date:** with `sendDate` on, each response carries a `date`; with it off, none.
- **The suite asserts the half-closed round trip.**

## Part 2: the build

One Opus builder built §8 in the main checkout, then one fix round settled the ticket rule
(§2.2). Scratch: `build/verify/m1s2/` (`mutation-table.md` in full, `node20/`, `final/`,
`measure2/`, `measure3/`).

### 2.1 What the builder measured

- **HTTP/2 over TLS, on `h2` with ALPN `h2` and `--half-close`,** gave byte for byte what
  `h2c` writes, alike on Node 20.10.0 and 24.18.0. The HEADERS blocks are in plan §8.2.
- **`--half-close` over TLS keeps reading** on both versions. After `end()`, a `raw-tls`
  drip still delivered its bytes at 100, 200 and 300 ms (`measure2/halfclose-tls-node{24,20}.txt`).
  The `https` and `h2` servers close at a client's end if they have not answered yet,
  which is Node's HTTP policy. The origin answers at once, so its answers arrive whole.
- **`h2` with a client offering only `http/1.1`:** Node 24 refuses the handshake with
  `ERR_SSL_TLSV1_ALERT_NO_APPLICATION_PROTOCOL`. Node 20 closes before the handshake ends,
  which the probe reports as `(refused "EOF" MS)`. With no ALPN offered, both connect,
  then see eof at once.
- **Bad clients,** alike on both versions:
  - plaintext sent to a TLS face: connected, nothing back, eof;
  - a partial ClientHello then a reset: `reset-sent`;
  - a stream reset with PROTOCOL_ERROR: SETTINGS, the ACK, then eof. Without a stream
    error listener, the origin dies of `ERR_HTTP2_STREAM_ERROR`;
  - HTTP/1.1 sent to `h2c` or `h2`: SETTINGS, then GOAWAY with last stream 0 and
    INTERNAL_ERROR.
- **At stop,** each HTTP/2 session sends two GOAWAY frames, then eof.
- **On `h2`, `s_client` copies the server's binary frames to stdout.** They land at the
  start of the `---` line it writes before a ticket's block, so the ticket line stays
  whole (`measure3/ticket-bytes-openssl-3.5.7.txt`).

### 2.2 The ticket rule

The first build held stdout to exactly one `Verify return code` line, as §8.4 then said.
The first `make test-memory` failed `raw-tls`'s row with three such lines. The cause is
OpenSSL 3 reading TLS 1.3 session tickets before stdin ends (`traps.md`):

| Run | Code lines |
|---|---|
| `measure3/tickets.sh`, stdin ending 300 ms late, OpenSSL 3.5.7 and 3.0.11 | 3, every time |
| the same, LibreSSL 3.3.6 | 1 |
| 200 runs at `</dev/null`, mutation jobs running | 3 lines in 3 runs |
| 200 runs under 24 busy loops | 3 lines in 73 runs |
| 80 runs per checker, the machine idle | always 1 |
| `-no_ticket` | no change: Node still sends two |

`measure/ticket-codes.sh` then showed every ticket's code equal to the handshake's, on
every face (0, 10, 0 and 21). The rule became the one in plan §8.4.

Fix round 1 also refuses a ticket line before the handshake's code line, which the brief
had not named. Its late-stdin check in `test-origin-tls` requires 2 tickets on OpenSSL
and 0 on LibreSSL, so it cannot pass with no tickets read. Afterwards `test-origin-tls`
passed 20 of 20 runs under 24 busy loops (`final/suite-under-load.txt`).

### 2.3 Traps it reproduced

These are in `traps.md`, and the lead reproduced the first two:
- dash writes `Killed` to the killed command's own redirected stderr;
- Chez's `map` calls its procedure in no fixed order;
- OpenSSL's ticket lines.

### 2.4 Mutations

107 mutations ran, and 100 were caught by a named failing test, or a suite that died with
its last line shown. The table lists each, and the first test that failed; `(+N)` counts
the others. Rows named `r1-` ran on fix round 1's tree.

| Case | Where | Mutation | Caught | First failing test |
|---|---|---|---|---|
| `allow-http1` | container | h2 allows HTTP/1.1 | yes | h2: a client offering no ALPN is connected, and then its socket is destroyed, an eof within 1000 ms (+1) |
| `alpn-https-default` | container | the https faces' ALPN left to Node's default | NO | none |
| `alpn-https-h2` | container | the https faces' ALPN is h2, http/1.1 | yes | https: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the good leaf served, a… (+4) |
| `alpn-raw-tls-h2` | container | raw-tls's ALPN is h2, http/1.1 | yes | raw-tls: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the good leaf served,… |
| `alpn-raw-tls-none` | container | raw-tls has no ALPN | yes | raw-tls: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the good leaf served,… |
| `announce-order` | container | raw-tls announced after h2 | yes | the scenarios' origin starts with the PKI, serves them all, and stops (+3) |
| `baseline` | container | no mutation: every suite must pass here | baseline passes | none |
| `bounded-killed-message` | container | bounded's kill as slice 1 wrote it: timeout exec'd with the command's redirections, so dash's Killed reaches the caller's stderr | see node20 | none |
| `bounded-lingers` | container | bounded leaves a subshell sleeping, holding the caller's pipes | yes | bounded leaves nothing running: an origin whose call ran a bounded command stops cleanly (+3) |
| `bounded-unbounded` | container | bounded runs its command with no timeout | yes | bounded: a command still running after 10 s is killed with SIGKILL, exit 137, within 12000 ms |
| `faces-ignore-pki` | container | the announcement is held to the plaintext faces, PKI or not | yes | origin-pki: with a PKI, the origin serves every TLS face too, each on loopback (+4) |
| `h2-204-body` | container | HTTP/2 204 and 304 get a body | yes | h2c GET /status/204, no content-length and no body: the whole frames, then eof (+3) |
| `h2-205-no-length` | container | HTTP/2 205 sends no content-length | yes | h2c GET /status/205, content-length 0 and no body: the whole frames, then eof (+1) |
| `h2-404-body` | container | HTTP/2 404's body changed | yes | h2c GET /nowhere, 404: the whole frames, then eof (+3) |
| `h2-chunked-served` | container | HTTP/2 serves /chunked | yes | h2c GET /chunked, an HTTP/1.1 route, 404: the whole frames, then eof (+1) |
| `h2-content-length-name` | container | HTTP/2 bodies carry x-length, not content-length | yes | h2c GET /status/200: the whole frames, then eof (+13) |
| `h2-echo-no-body` | container | HTTP/2 echo leaves out the request's body | yes | h2c POST /echo?x=1 with a header and a body: each pair, pseudo-headers included, in order, then the body: t… (+1) |
| `h2-echo-no-pseudo` | container | HTTP/2 echo leaves out the pseudo-headers | yes | h2c POST /echo?x=1 with a header and a body: each pair, pseudo-headers included, in order, then the body: t… (+1) |
| `h2-header-order` | container | HTTP/2 content-length before the route's headers | yes | h2c GET /redirect/302?to=%2Fstatus%2F200, location decoded: the whole frames, then eof (+1) |
| `h2-redirect-location` | container | HTTP/2 location gains a slash | yes | h2c GET /redirect/302?to=%2Fstatus%2F200, location decoded: the whole frames, then eof (+1) |
| `h2-senddate-body` | container | HTTP/2 answers with a body carry a date | yes | h2c GET /status/200: the whole frames, then eof (+15) |
| `h2-senddate-headers` | container | HTTP/2 answers with no body carry a date | yes | h2c GET /status/204, no content-length and no body: the whole frames, then eof (+5) |
| `h2-session-error-unhandled` | container | HTTP/2 sessions have no error listener, nor the servers a sessionError one | NO | none |
| `h2-status-body` | container | HTTP/2 /status/CODE's body changed | yes | h2c GET /status/200: the whole frames, then eof (+7) |
| `h2-stream-error-unhandled` | container | HTTP/2 streams have no error listener | yes | a bad HTTP/2 client on h2c: a stream it resets with PROTOCOL_ERROR gets no answer, and the next request is … (+4) |
| `h2c-dropped` | container | no h2c face | yes | the scenarios' origin starts, serves them all, and stops (+7) |
| `https-senddate` | container | the HTTP/1.1 faces, https among them, send Date | yes | https over TLS: GET /status/200 gets http's bytes, then eof (+9) |
| `leaf-h2` | container | h2 serves the untrusted leaf | yes | h2: s_client, trusting the run CA, sees verify errors (), code 0, ALPN h2, the good leaf served, and its SAN |
| `leaf-https` | container | https serves the expired leaf | yes | https: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the good leaf served, a… (+1) |
| `leaf-https-expired` | container | https-expired serves the good leaf | yes | https-expired: s_client, trusting the run CA, sees verify errors (10), code 10, ALPN http/1.1, the expired … |
| `leaf-https-untrusted` | container | https-untrusted serves the good leaf | yes | https-untrusted: s_client, trusting the run CA, sees verify errors (20 21), code 21, ALPN http/1.1, the unt… (+1) |
| `leaf-https-wrong-host` | container | https-wrong-host serves the good leaf | yes | https-wrong-host: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the wrong-ho… |
| `leaf-raw-tls` | container | raw-tls serves the wrong-host leaf | yes | raw-tls: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the good leaf served,… |
| `make-pki-files` | container | make-test-pki ignores the files | yes | make-test-pki, with a stand-in script that leaves out a file: a raise (+2) |
| `make-pki-kept` | container | make-test-pki leaves the directory it refuses | yes | make-test-pki, with a stand-in script that exits 1: a raise, with all it saw, and the directory removed (+5) |
| `make-pki-status` | container | make-test-pki ignores the exit status | yes | make-test-pki, with a stand-in script that exits 1: a raise, with all it saw, and the directory removed (+1) |
| `make-pki-stderr` | container | make-test-pki ignores stderr | yes | make-test-pki, with a stand-in script that writes to stderr: a raise (+1) |
| `make-pki-stdout` | container | make-test-pki ignores stdout | yes | make-test-pki, with a stand-in script that writes to stdout: a raise (+1) |
| `openssl-empty` | container | openssl-program takes an empty OPENSSL | yes | openssl-program: OPENSSL from the environment, else openssl, an empty one included (+3) |
| `openssl-env-ignored` | container | openssl-program ignores OPENSSL | yes | openssl-program: OPENSSL from the environment, else openssl, an empty one included (+9) |
| `parse-alpn-empty` | container | an empty ALPN protocol taken | yes | parse-s-client refuses an ALPN protocol line with no protocol |
| `parse-alpn-none` | container | no ALPN line is not refused by name | yes | parse-s-client refuses no ALPN line |
| `parse-alpn-twice` | container | two ALPN lines taken | yes | parse-s-client refuses an ALPN protocol line and a No ALPN negotiated line (+1) |
| `parse-code-no-brackets` | container | the code line's bracketed text not required | yes | parse-s-client refuses a Verify return code line whose text is not in brackets |
| `parse-code-none` | container | no Verify return code line is not refused by name | yes | parse-s-client refuses no Verify return code line |
| `parse-code-twice` | container | two Verify return code lines taken | yes | parse-s-client refuses two Verify return code lines, as a session ticket's block would add |
| `parse-code-unindented` | container | the Verify return code line read unindented only | yes | parse-s-client: LibreSSL 3.3.6, the same, its code line indented (+2) |
| `parse-error-malformed` | container | a malformed verify error line read as 0 | yes | parse-s-client refuses a verify error line with no number (+1) |
| `parse-error-number` | container | a verify error's number read a digit late | yes | parse-s-client: OpenSSL 3.5.7, an untrusted leaf, ALPN h2, two certificates: the errors from stderr in orde… (+5) |
| `parse-errors-indented` | container | indented verify error lines read too | yes | parse-s-client: a verify error line on stdout is not one of stderr's, nor an indented one on stderr |
| `parse-errors-stdout` | container | verify errors read from stdout | yes | parse-s-client: OpenSSL 3.5.7, an untrusted leaf, ALPN h2, two certificates: the errors from stderr in orde… (+7) |
| `parse-leaf-any-block` | container | the leaf is the first PEM block of any kind | yes | parse-s-client: a key block before the first certificate is not it (+2) |
| `parse-leaf-empty` | container | an empty certificate taken | yes | parse-s-client refuses an empty certificate (+1) |
| `parse-leaf-none` | container | no certificate read as an empty leaf | yes | parse-s-client refuses no certificate (+1) |
| `parse-leaf-open` | container | a certificate not closed taken | yes | parse-s-client refuses a first certificate that is not closed (+1) |
| `parse-no-alpn` | container | No ALPN negotiated not read as #f | yes | parse-s-client: OpenSSL 3.5.7, a good leaf, no ALPN: no errors, code 0, no protocol (+2) |
| `pki-exit-1` | container | a wrong argument or PKI file exits 1 | yes | an unreadable PKI file exits 2, naming the file, with nothing on stdout (+1) |
| `pki-file-unnamed` | container | an unreadable PKI file is not named | yes | an unreadable PKI file exits 2, naming the file, with nothing on stdout |
| `pki-not-passed` | container | call-with-origin hands the origin no --pki | yes | origin-pki: with a PKI, the origin serves every TLS face too, each on loopback (+3) |
| `pki-sh-file-missing` | container | no wrong-host leaf | yes | make-test-pki makes this run's PKI (+54) |
| `pki-sh-good-other-ca` | container | the good leaf signed by the second CA | yes | https: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the good leaf served, a… (+3) |
| `pki-sh-log-hidden` | container | a failing openssl's output not shown | yes | the material: a failing openssl command exits 1, with what openssl wrote on stderr |
| `pki-sh-nonempty` | container | the script takes a directory that is not empty | yes | the material: each refusal exits 2, naming its problem, and writes nothing to stdout |
| `pki-sh-not-expired` | container | the expired leaf valid now | yes | https-expired: s_client, trusting the run CA, sees verify errors (10), code 10, ALPN http/1.1, the expired … |
| `pki-sh-san` | container | the good leaves' SAN leaves out ::1 | yes | https: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the good leaf served, a… (+5) |
| `pki-sh-stderr` | container | the script writes to stderr on success | yes | make-test-pki makes this run's PKI (+54) |
| `pki-sh-untrusted-run-ca` | container | the untrusted leaf signed by the run CA | yes | https-untrusted: s_client, trusting the run CA, sees verify errors (20 21), code 21, ALPN http/1.1, the unt… (+1) |
| `pki-sh-usage-exit-1` | container | the script's refusals exit 1 | yes | the material: each refusal exits 2, naming its problem, and writes nothing to stdout |
| `pki-sh-wrong-host-san` | container | the wrong-host leaf names localhost too | yes | https-wrong-host: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the wrong-ho… |
| `probe-alpn-alone` | container | the probe takes --alpn without --tls | yes | the probe refuses each misuse of --tls and --alpn with exit 2, its problem and its usage on stderr |
| `probe-connected-at-tcp` | container | the probe says connected at TCP connect, before the handshake | yes | h2: a client offering only http/1.1 is refused within 1000 ms, as one of the two ways measured |
| `probe-drops-alpn` | container | the probe drops --alpn | yes | h2 GET /status/200: the whole frames, then eof (+13) |
| `probe-ip-sni` | container | the probe takes an IP address as SERVERNAME | yes | the probe refuses each misuse of --tls and --alpn with exit 2, its problem and its usage on stderr |
| `probe-no-sni` | container | the probe's --tls sends no SNI | yes | the probe's --tls sends SERVERNAME as SNI, and --alpn offers its protocols |
| `probe-reset-tls` | container | the probe takes --reset with --tls | yes | the probe refuses each misuse of --tls and --alpn with exit 2, its problem and its usage on stderr |
| `probe-tls-no-half-close` | container | the probe never half-closes over TLS | yes | h2 GET /status/200: the whole frames, then eof (+11) |
| `probe-tls-not-half-open` | container | the probe's TLS socket is not half-open | NO | none |
| `probe-verifies` | container | the probe judges certificates | yes | https over TLS: GET /status/200 gets http's bytes, then eof (+39) |
| `r1-agreement-skipped` | container | a ticket's code is not held to the handshake's | yes | parse-s-client refuses a ticket's code that is not the handshake's: 21, then 0 (+1) |
| `r1-code-without-ticket` | container | a later code line with no ticket line of its own is not refused | yes | parse-s-client refuses a second Verify return code line with no ticket line before it (+1) |
| `r1-last-code` | container | the answer is the last code line, not the first | NO | none |
| `r1-last-code-unchecked` | container | the answer is the last code line, and a ticket's code is not held to the handshake's | yes | parse-s-client refuses a ticket's code that is not the handshake's: 21, then 0 (+1) |
| `r1-no-code` | container | no Verify return code line is not refused | yes | parse-s-client refuses no Verify return code line |
| `r1-strict-rule` | container | the slice's first rule: any later code line refused, ticket line or not | yes | https-untrusted, stdin ending 300 ms late so that OpenSSL reads the session tickets: exit 0, the Peer the n… (+6) |
| `r1-ticket-before-handshake` | container | a ticket line before the handshake's code is not refused, only passed over | yes | parse-s-client refuses a ticket line before the handshake's Verify return code line |
| `r1-ticket-without-code` | container | a ticket line with no code line after it is not refused | yes | parse-s-client refuses a ticket line with no Verify return code line after it |
| `r1-two-tickets` | container | two ticket lines before one code line are not refused | yes | parse-s-client refuses two ticket lines before one Verify return code line |
| `raw-tls-error-unhandled` | container | raw-tls's TLS socket has no error listener | NO | none |
| `raw-tls-reset-ends` | container | raw-tls's reset turned into an end | yes | raw-tls /raw/reset-mid-body: the whole bytes, then reset |
| `reset-under-tls` | container | wire-probe-reset runs under wire-probe-tls | yes | wire-probe-reset refuses to run under wire-probe-tls, before running a probe |
| `s-client-alpn-always` | container | s-client offers h2 when given no ALPN | yes | s-client against the origin's https and h2 faces: the good leaf, as good.pem holds it, by ALPN http/1.1 and… (+2) |
| `s-client-no-servername` | container | s-client gives no -servername | yes | s-client runs $OPENSSL s_client -connect ADDRESS:PORT -servername localhost -CAfile CA -showcerts, then -al… |
| `s-client-no-showcerts` | container | s-client gives no -showcerts | yes | s-client runs $OPENSSL s_client -connect ADDRESS:PORT -servername localhost -CAfile CA -showcerts, then -al… |
| `s-client-status` | container | s-client ignores the exit status | yes | s-client raises, with its status, stdout and stderr, when openssl does not exit 0 |
| `san-heading-unindented` | container | certificate-san finds the heading unindented only | yes | certificate-san: the good leaf names localhost, 127.0.0.1 and ::1, and the wrong-host leaf wrong-host.inval… (+5) |
| `san-last-line` | container | certificate-san takes a heading on the last line | yes | certificate-san refuses text whose last line is the SAN heading |
| `san-missing` | container | certificate-san answers empty with no heading | yes | certificate-san refuses text with no SAN heading |
| `san-status` | container | certificate-san ignores the exit status | yes | certificate-san refuses a status other than 0 |
| `san-twice` | container | certificate-san takes the heading twice | yes | certificate-san refuses text with the SAN heading twice |
| `san-untrimmed` | container | certificate-san's line not trimmed | yes | certificate-san: the good leaf names localhost, 127.0.0.1 and ::1, and the wrong-host leaf wrong-host.inval… (+3) |
| `stop-https-untracked` | container | the https faces' sockets are not tracked, so stop() destroys none | yes | stopping destroys open connections on every new face: each probe still connected when PROC returns sees eof… |
| `stop-sessions-kept` | container | stop() destroys no HTTP/2 session, only sockets | NO | none |
| `stop-skips-tls-h2` | container | stop() destroys only the http and raw faces' sockets, and no session | yes | stopping destroys open connections on every new face: each probe still connected when PROC returns sees eof… |
| `tls-client-error-unhandled` | container | the https faces have no tlsClientError listener | NO | none |
| `tls-options-first-protocol` | container | wire-probe-tls offers its first protocol alone | yes | wire-probe-tls: each probe speaks TLS with its SNI, offering its protocols, joined, or none; #f speaks none |
| `tls-options-ignored` | container | wire-probe-tls is ignored | yes | wire-probe-tls: each probe speaks TLS with its SNI, offering its protocols, joined, or none; #f speaks none |
| `tls-param-comma` | container | wire-probe-tls takes a protocol with a comma | yes | wire-probe-tls refuses what is not #f, nor a list of SERVERNAME and then protocols, each a string with no c… |
| `unknown-protocol-waits` | container | h2's unknownProtocol destroy removed | yes | h2: a client offering no ALPN is connected, and then its socket is destroyed, an eof within 1000 ms |
| `baseline` | node20 (dash) | no mutation: every suite must pass here (test-curl-testing alone, under Node 20.10.0 and dash) | baseline passes | none |
| `bounded-killed-message` | node20 (dash) | bounded's kill as slice 1 wrote it: timeout exec'd with the command's redirections, so dash's Killed reaches the caller's stderr | yes | bounded: a command still running after 10 s is killed with SIGKILL, exit 137, within 12000 ms |

**The 7 not caught, as the builder argues them:**
- `alpn-https-default`: Node's default ALPN for `https` is already `http/1.1` (§1.4).
- `h2-session-error-unhandled` and `tls-client-error-unhandled`: Node's default handling
  ends the session or socket anyway.
- `stop-sessions-kept`: equivalent because the origin destroys every socket, which ends its
  session. It is not Node's doing: Node 20 ends no idle session at `close()`, as the second
  review measured (Part 4).
- `probe-tls-not-half-open`: no measured difference.
- `raw-tls-error-unhandled`: the builder found no client that made that socket emit
  `error`. **The review disproved that** (Part 3). The socket does emit `error`, from a
  reset after the handshake, from renegotiation, and on Node 20 from an unsupported
  protocol or no shared cipher. With the listener removed, there was still no crash and no
  stderr on either Node. So the mutant is equivalent by measurement, not because no error
  arises. The listener stays.
- `r1-last-code`: the same answer as the first code, by the agreement rule. With the
  agreement check skipped too, it is caught (`r1-last-code-unchecked`).

### 2.5 Final checks

The builder's, rerun by the lead on the same tree, in the container:

| Check | Result |
|---|---|
| `make test` | `test: ran 18, passed 18, failed 0, hung 0` |
| `make check-test-fails` | `check-test-fails: make test failed, as it must, in all 10 cases` |
| `make check-suites` | 18 checked |
| `make check-seam` | 10 libraries in 10 files |
| `make test-memory` on `test-origin-tls`, `test-curl-testing`, `test-origin` | `ran 3, passed 3`, with 0 errors and 0 definitely lost |

| Suite | Plain | Under Valgrind |
|---|---|---|
| `test-origin-tls` | 6.9 s | 17 s |
| `test-curl-testing` | 23.3 s | 41 s |
| `test-origin` | 12.1 s | 25 s |

**Node 20.10.0, in Docker `node:20.10.0-bookworm`** (`node20/node20-run.sh`):

| Checker | `test-origin` | `test-origin-tls` | `test-curl-testing` |
|---|---|---|---|
| OpenSSL 3.0.11 | 109 pass | 71 pass | 233 pass |
| LibreSSL 3.3.6 | 109 pass | 71 pass | 233 pass |

`test-origin` ran on the first build's tree, and the others on fix round 1's.

## Part 3: the review, and fix round 2

### 3.1 The adversarial review (Opus, read-only)

It found no blocker. The instrument's code was right, but these checks passed against a
wrong instrument. Each mutant was planted on a copy, and stayed green in all three suites
(`build/verify/m1s2/review/`, `mk.py`, `run.sh`, `expA`–`expG`):

| Finding | Mutant | What it showed | Reproduced by the lead |
|---|---|---|---|
| The stop tests took any eof as the stop's | `https-tcp-untracked`, `h2-tcp-untracked`, `https-idle-close-untracked` | A client stalled mid-ClientHello made `server.close()` wait: the mutant exited 14112 ms after its stdin ended, against 57 ms (`expD`) | yes: 14112 and 57 ms |
| "Within 1000 ms" was not asserted | `h2-handshake-3s` | Before the handshake, only `--deadline` holds the probe: `(refused "EOF" 5035)` with IDLE-MS 1000 (`expB`) | by the code |
| No timing rule over TLS | `raw-tls-nagle` | Two drip bytes 0 ms apart (`expC`) | by the evidence |
| ALPN only through the last protocol | `probe-alpn-last-only`, `probe-alpn-reversed` | Every multi-protocol row overlapped only in its last entry | by the rows |
| A relative DIR left `work/`, CA keys included | none: the script itself | exit 0, 11 entries, under dash and bash, on OpenSSL and LibreSSL | yes |
| Records said Node waits 10 s without `unknownProtocol` | none | With no listener, Node writes `HTTP/1.0 403 Forbidden … Missing ALPN Protocol…` and closes (`expA`) | yes |
| The log said `raw-tls`'s socket never errors | `listeners-log` | It does, from a reset, renegotiation, and on Node 20 an unsupported protocol or cipher | by the evidence |
| "Each failing leaf differs in one way", but each had its own CN | none | `-subj "/CN=$name"` | by the script |

**Its notes:**
- the served chain was never asserted (`https-extra-chain`);
- a cert and key mismatch was untested (`pki-pair-unchecked`);
- the script header's facts were unchecked (`pki-sh-3650-days`);
- every check sent SNI;
- on Node 20, an HTTP/2 connection error leaves the connection open;
- the late-stdin ticket check is robust. It passed 60 of 60 at `--cpus` 1, 0.5 and 0.25,
  and failed only at 0.25 with 4 busy loops, loudly, never as a false pass.

**Its design note:** M2 must assert, on each backend, that the good face is accepted, as the
control (plan §8.8).

### 3.2 The lead's fixes

- **`tests/make-test-pki.sh`:**
  - It makes DIR absolute before it `cd`s. A relative DIR now ends with exactly ten
    files, and a failing `openssl` leaves nothing, under bash, dash and LibreSSL.
  - Every leaf's subject is `CN=chez-curl test leaf`.
- **The records:** the unknownProtocol claim in the plan, ADR-0005 and Part 1; the
  raw-tls entry in Part 2; and the one-fault wording.
- **The two-day test** accepts 172800 or 172801 s. `openssl` reads the clock once per date,
  as the builder warned. Watched failing on a copy with `-days 3650`, by name.

### 3.3 Fix round 2 (the builder, resumed)

Each class, as the builder closed it:
- **The stop rule:** every probe silent 300 ms after it opens, then its end within 2000 ms
  of the stop. That covers 9 plaintext waiting states and 27 TLS ones, on every face.
- **Time claims:** a new `probe-ended`. The `h2` and bad-client bounds are asserted from the
  probe's own times. The added `r2-h2-connection-held-3s` holds every `h2` connection 3 s.
- **`raw-tls`'s drip gap,** measured (`measure4/gaps-8x20.txt`):
  - with Nagle, the first gap was 0–2 ms in every run;
  - without it, at least 19 ms, under 24 busy loops too;
  - the rule is half the drip's gap.
- **ALPN:** stand-ins report the offered list through `ALPNCallback`, which both Node versions
  have. Rows overlap only first, and only last.
- **The PKI's facts:**
  - new `certificate-text`, `certificate-values` and `certificate-time`, the last from
    days_from_civil and tested against `date -u`;
  - the facts are identical, trimmed, on 3.5.7, 3.0.11 and LibreSSL 3.3.6
    (`measure3/x509-facts-*.txt`);
  - a cert and key that don't match exit 2, naming both files and
    `ERR_OSSL_X509_KEY_VALUES_MISMATCH`.
- **The chain:** `peer-chain`, and every face serves its leaf alone.
- **No SNI:** `s-client` takes SERVERNAME or `#f`. Without `-servername`, all three checkers
  send no SNI to an IP address (`measure3/sni-*.txt`).
- **H, an HTTP/2 connection error on Node 20, stopped on evidence.**
  - After the origin's GOAWAY, for DATA on stream 0, Node 20.10.0 emits nothing.
    Node 24.18.0 emits `sessionError` and closes (`measure3/h2-conn-error-*`).
  - The lead reproduced both. It is a recorded limit (plan §8.8).
- **Its harness had a bug,** `A; B` reporting only B. Six chained cases were rerun
  (`traps.md`).

**The `r2-` mutations:** 26 run, all caught by name. The table now has 133 run and 126
caught. Its 7 survivors are Part 2's, judged equivalent by the review.

| Case | Mutation | Caught | First failing test |
|---|---|---|---|
| `r2-chain-first-only` | peer-chain holds the first certificate alone | yes | parse-s-client: peer-chain is every certificate block, in order, and peer-leaf the first: OpenSSL 3.5.7, two (+2) |
| `r2-h2-connection-held-3s` | h2 holds each TCP connection 3 s before its handshake starts | yes | h2: a client offering no ALPN is connected, then destroyed with no byte written: eof, within 1000 ms of the… (+2) |
| `r2-h2-handshake-3s` | h2 holds every TLS handshake 3 s, by its SNI callback | yes | h2: a client offering no ALPN is connected, then destroyed with no byte written: eof, within 1000 ms of the… |
| `r2-h2-tcp-untracked` | the HTTP/2 faces' TCP sockets untracked | yes | stopping destroys every connection to a TLS face, in every waiting state: each, still waiting 300 ms on, wi… |
| `r2-http-untracked` | the http face's sockets untracked | yes | stopping destroys every connection to a plaintext face, in every waiting state: each, still waiting 300 ms … |
| `r2-https-extra-chain` | the https face serves its leaf with the second CA after it | yes | https: s_client, trusting the run CA, sees verify errors (), code 0, ALPN http/1.1, the good leaf served, a… (+1) |
| `r2-https-idle-close-tracked` | https tracked, but it closes a connection that sends nothing for 100 ms, so only the rule before the stop can tell | yes | https-untrusted, stdin ending 300 ms late so that OpenSSL reads the session tickets: exit 0, the Peer the n… (+1) |
| `r2-https-idle-close-untracked` | https untracked, but it closes a connection that sends nothing for 100 ms | yes | stopping destroys every connection to a TLS face, in every waiting state: each, still waiting 300 ms on, wi… |
| `r2-https-no-sni-expired` | the https face serves the expired leaf to a client that sends no SNI | yes | no SNI: https and h2, reached at their IP address with no -servername, so with no SNI, serve the Peer they … |
| `r2-https-tcp-untracked` | the https faces track the TLS socket only, not the TCP one under it | yes | stopping destroys every connection to a TLS face, in every waiting state: each, still waiting 300 ms on, wi… |
| `r2-pki-pair-unchecked` | a certificate and key that do not match are not refused, but crash the origin | yes | a certificate and a key that do not match: the origin exits 2, naming both files, with nothing on stdout |
| `r2-pki-sh-3650-days` | the PKI script's good leaf lasts ten years | yes | the material: every CA and every leaf but expired is valid for exactly two days, its Not After 172800 s aft… |
| `r2-pki-sh-expired-dates` | the expired leaf's Not After a day later, still expired | yes | the material: expired is valid only from Jan  1 00:00:00 2000 GMT to Jan  2 00:00:00 2000 GMT, as x509 -tex… |
| `r2-pki-sh-p384` | the PKI script's keys are P-384 | yes | the material: a failing openssl command exits 1, with what openssl wrote on stderr (+2) |
| `r2-pki-sh-relative` | the PKI script without making DIR absolute | yes | the material: a relative DIR: exit 0, nothing said, and exactly the ten files in it, no work/ left (+1) |
| `r2-pki-sh-sha384` | the PKI script signs with SHA-384 | yes | the material: every CA and leaf has an EC P-256 key, and both its signature algorithms, its own and its iss… |
| `r2-probe-alpn-last-only` | the probe offers only LIST's last protocol | yes | the probe's --tls sends SERVERNAME as SNI, and --alpn offers its protocols, every one, in order: the only o… |
| `r2-probe-alpn-reversed` | the probe offers LIST's protocols in reverse | yes | the probe's --tls sends SERVERNAME as SNI, and --alpn offers its protocols, every one, in order: the only o… |
| `r2-probe-ended-zero` | probe-ended is always 0 | yes | parse-wire-probe: the probe's lines, as the bytes joined, the end, each arrival, when it connected and when… (+2) |
| `r2-raw-tls-nagle` | raw-tls's TCP socket keeps Nagle's algorithm | yes | raw-tls /raw/drip?bytes=8&gap=20: the whole bytes, then eof, each body byte read at least 10 ms after the o… |
| `r2-raw-untracked` | the raw faces' TCP sockets untracked | yes | stopping destroys every connection to a plaintext face, in every waiting state: each, still waiting 300 ms … |
| `r2-s-client-sni-always` | s-client sends -servername localhost when given none | yes | s-client runs $OPENSSL s_client -connect ADDRESS:PORT, -servername SERVERNAME when given, -CAfile CA -showc… |
| `r2-text-untrimmed` | certificate-text does not trim its lines | yes | certificate-text: x509 -in FILE -noout -text's lines, trimmed at both ends, from OpenSSL 3.5.7's indentation (+2) |
| `r2-time-a-day-late` | certificate-time counts a day too many | yes | certificate-time: x509 -text's dates as seconds since 1970-01-01 UTC, its padded day, a leap day and the ce… |
| `r2-unknown-protocol-unhandled` | h2 has no unknownProtocol listener, so Node writes the client a 403 | yes | h2: a client offering no ALPN is connected, then destroyed with no byte written: eof, within 1000 ms of the… |
| `r2-values-prefix-trimmed` | certificate-values matches a label within a line, not only at its start | yes | certificate-values: what follows the label, trimmed, on every line that starts with it, in order, its spaci… |

### 3.4 Checks after fix round 2

These are the builder's, and the lead reran each in the container.

| Check | Result |
|---|---|
| `make test` | `test: ran 18, passed 18, failed 0, hung 0` |
| `make check-test-fails` | `make test failed, as it must, in all 10 cases` |
| `make check-suites`, `make check-seam` | 18 suites; 10 libraries in 10 files |
| `make test-memory` on the three origin suites | `ran 3, passed 3`, with 0 errors and 0 definitely lost |
| `test-origin-tls` under 24 busy loops (builder) | 20 of 20 |

| Suite | Tests | Plain | Under Valgrind |
|---|---|---|---|
| `test-origin-tls` | 79 | 9.3 s | 21 s |
| `test-curl-testing` | 262 | 23.5 s | 41 s |
| `test-origin` | 109 | 12.8 s | 27 s |

**Node 20.10.0, in Docker:** all three suites pass with OpenSSL 3.0.11, and with LibreSSL
3.3.6 (`node20/node20-{openssl,libressl}-r2.log`).

## Part 4: the second review, and fix round 3

### 4.1 The second review (Opus, read-only, scoped to fix rounds 1 and 2)

It found no blocker, and six should-fix items. In four of them, a fix had closed the
reported instance and left its class open. Each mutant was planted on a copy, and stayed
green (`build/verify/m1s2/review2/`, `mk2.py`, `run2.sh`):

| Finding | Mutants that passed | The class |
|---|---|---|
| Node's own `close()` ends idle HTTP/2 sessions on Node 24, not on Node 20, so the stop rule's verdict depended on the version | `h2c-tracks-nothing`: green on Node 24, fails on Node 20 | an end the stop did not cause |
| The 300 ms silence ended long before the stop, and ends were accepted for 2000 ms after it, so an idle timer passed | `https-untracked-handshake-1200`, `-2500`, `http-untracked-idle-2000` | the same |
| No SNI was compared on `https` and `h2` only | `no-sni-wrong-host-untrusted`, `no-sni-raw-tls-expired` | no SNI, closed for one face |
| The faces' own ALPN sets were judged through the protocol chosen | `alpn-https-also-h2`, `alpn-raw-tls-also-h2` | ALPN, on the server's side |
| The PKI's subject claim was unchecked | `pki-wrong-host-cn-localhost`, `pki-leaves-cn-ip` | a header claim with no check |
| Records stale against round 2 | none | these predated Part 3, which it had not seen |

**The lead reproduced the mechanism** with `review2/measure/close-untracked.mjs`, on both
versions, with nothing tracked:

| Face | Node 24.18.0 at `close()` | Node 20.10.0 |
|---|---|---|
| `h2c` | ends "connected", "partial preface" and "preface done" within 3 ms; "a stream open, its body pending" stays open | ends none |
| `http` | ends "idle after a keep-alive response" within 1 ms; the other states stay open | the same |
| `https` | ends none, the keep-alive state included | the same |

**Its notes:**
- the probe's `--alpn` was never offered three protocols, nor a duplicate
  (`probe-alpn-drop-middle`, `probe-alpn-dedup`);
- `raw-tls`'s drip asserted only the gaps between body bytes
  (`raw-tls-drip-first-byte-with-head`);
- one test name misdescribed the two `Signature Algorithm` lines;
- `certificate-time`'s 400-year rule was untested;
- two of the log's and `traps.md`'s citations were wrong, both since corrected.

**Found sound:**
- the 172801 edit, reproduced with an LD_PRELOAD `time()` that ticks once per call, on all
  three checkers;
- `certificate-time`'s padding, leap years and centuries;
- every "within N ms" in the suites, asserted;
- the gap rule, with 0 failures in 100 runs at 36 and at 72 busy loops, and a smallest gap
  of 15 ms against a threshold of 10;
- the ticket test, 2 tickets in 60 of 60 runs at 54 busy loops.

### 4.2 Fix round 3 (the builder, resumed)

**The stop rule, by mechanism** (plan §8.6):
- the waiting states include those Node's `close()` never ends;
- each probe must hold its state right up to PROC's return;
- the call must return within B = 500 ms of PROC, on Chez's monotonic clock;
- two sets of probes are opened 700 ms apart. That is 36 TLS states a set, 72 probes, and
  12 plaintext states a set, 24 probes.

**B, measured** (`measure5/stop-spread-*`): 35–43 ms idle, 70–150 ms under 24 busy loops,
and 49–76 ms with Chez under Valgrind.

**What `close()` ends,** re-measured on both versions, with the handler answering
(`measure5/close-untracked.mjs`):
- `https`'s `close()` *does* end an idle keep-alive connection. That corrects the second
  review: its handler never answered, so its connection was never idle after a response.
- The plan's table has the rest.

**The idle-close sweep** (`sweep-matrix.md`, `sweep.py`): each of the 9 faces untracked, and
closed L ms after each accept.
- L was 100, 400, 800, 1200, 1600, 2000, 2500, 3000 and 5000 ms, or no close at all.
- **All 90 cases failed on Node 24.18.0, and all 90 on Node 20.10.0,** each by the stop
  test:
  - at 100 and 400 ms, a probe ended before the stop;
  - from 1200 ms on, the call took about L;
  - with no close, the origin was killed.
- The lead reran `https-2500` and `h2c-nothing`, and both failed by the stop test's name.

**The other classes:**
- **No SNI:** the comparison runs on all six TLS faces.
- **ALPN sets:** each face is offered `h2`, `http/1.1` and an unknown protocol, each alone.
  The brief expected `#f` for an unaccepted one, which was wrong. Every face refuses it with
  alert 120: `s_client` exits 1, writes `No ALPN negotiated`, and prints no certificate.
  That holds on both Node versions and all three checkers (`measure5/alpn-sets-*.txt`). It
  also corrects Part 1's reading.
- **Names:** `certificate-names` folds ` = ` to `=` in `Subject:` and `Issuer:` lines only.
  `CN = x` is OpenSSL 3.0.11's spelling; 3.5.7 and LibreSSL write `CN=x`.
- **The probe's `--alpn`:** a three-protocol row whose only overlap is the middle one. A
  duplicate is now a usage error, exit 2.
- **`raw-tls`'s drip** also asserts slice 1's bound from connect.
- **`certificate-time`:** Feb 29 2000 and Mar 1 2000 are tested against `date -u`, and
  Feb 29 2100 is refused.

**The `r3-` mutations:** 18 run, 17 caught by name. The table now has 151 run and 143 caught.
- The one not caught, `r3-probe-alpn-dedup`, is equivalent. Duplicates are refused as a
  usage error before the probe builds its offer, so de-duplicating changes nothing.
- The second review's other 12 mutants all fail, by name.

| Case | Mutation | Caught | First failing test |
|---|---|---|---|
| `r3-alpn-https-also-h2` | the https faces accept h2 too, after http/1.1 | yes | https: its ALPN set pinned, offered each of h2, http/1.1 and an unknown protocol alone (+3) |
| `r3-alpn-raw-tls-also-h2` | raw-tls accepts h2 too, after http/1.1 | yes | raw-tls: its ALPN set pinned, offered each of h2, http/1.1 and an unknown protocol alone |
| `r3-h2c-tracks-nothing` | h2c tracks neither its sockets nor its sessions | yes | stopping destroys every connection to a plaintext face, in every waiting state: two sets of probes, the sec… |
| `r3-http-untracked-idle-2000` | http untracked, with an idle socket timeout of 2000 ms | yes | stopping destroys every connection to a plaintext face, in every waiting state: two sets of probes, the sec… |
| `r3-https-untracked-handshake-1200` | the https faces' TCP sockets untracked, and a TLS handshake timeout of 1200 ms | yes | stopping destroys every connection to a TLS face, in every waiting state: two sets of probes, the second op… |
| `r3-https-untracked-handshake-2500` | the same, its handshake timeout 2500 ms | yes | stopping destroys every connection to a TLS face, in every waiting state: two sets of probes, the second op… |
| `r3-names-unfolded` | certificate-names folds nothing | yes | certificate-names: a Subject or Issuer line's names, each " = " written "=": OpenSSL 3.0's CN = x as 3.5's … |
| `r3-no-sni-raw-tls-expired` | raw-tls serves the expired leaf to a client that sends no SNI | yes | no SNI: every TLS face, reached at its IP address with no -servername, so with no SNI, serves the Peer it s… |
| `r3-no-sni-wrong-host-untrusted` | https-wrong-host serves the untrusted leaf to a client that sends no SNI | yes | no SNI: every TLS face, reached at its IP address with no -servername, so with no SNI, serves the Peer it s… |
| `r3-pki-leaves-cn-ip` | every leaf's subject is CN=127.0.0.1 | yes | the material: every leaf's Subject is CN=chez-curl test leaf, each CA's Subject and Issuer its own CN, and … |
| `r3-pki-wrong-host-cn-localhost` | the wrong-host leaf's subject is CN=localhost | yes | the material: every leaf's Subject is CN=chez-curl test leaf, each CA's Subject and Issuer its own CN, and … |
| `r3-probe-alpn-dedup` | the probe offers each protocol once, duplicates dropped | NO | none |
| `r3-probe-alpn-drop-middle` | the probe drops every protocol of LIST but its first and its last | yes | the probe's --tls sends SERVERNAME as SNI, and --alpn offers its protocols, every one, in order: the only o… |
| `r3-probe-alpn-duplicates-taken` | the probe takes a protocol named twice | yes | the probe refuses each misuse of --tls and --alpn with exit 2, its problem and its usage on stderr |
| `r3-raw-tls-drip-first-byte-with-head` | raw-tls skips a script's first wait, so a drip's first body byte goes with its head | yes | raw-tls /raw/drip?bytes=8&gap=20: the whole bytes, then eof, each body byte read at least 10 ms after the o… |
| `r3-stop-destroys-late` | stop() destroys every socket and session 1000 ms late, more than B | yes | stopping destroys every connection to a TLS face, in every waiting state: two sets of probes, the second op… (+1) |
| `r3-time-no-400-year-rule` | certificate-time's leap years lack the 400-year rule | yes | certificate-time: x509 -text's dates as seconds since 1970-01-01 UTC, its padded day, a leap day and the ce… |
| `r3-tls-param-duplicates-taken` | wire-probe-tls takes a protocol named twice | yes | wire-probe-tls refuses what is not #f, nor a list of SERVERNAME and then protocols, each a string with no c… |

### 4.3 Checks after fix round 3

The builder's, and the lead reran each:

| Check | Result |
|---|---|
| `make test` | `test: ran 18, passed 18, failed 0, hung 0` |
| `make check-test-fails` | `make test failed, as it must, in all 10 cases` |
| `make check-suites`, `make check-seam` | 18 suites; 10 libraries in 10 files |
| `make test-memory` on the three origin suites | `ran 3, passed 3`, with 0 errors and 0 definitely lost |
| `test-origin-tls`, `test-origin` under 24 busy loops (builder) | 20 of 20 each |

| Run | `test-origin` | `test-origin-tls` | `test-curl-testing` |
|---|---|---|---|
| Container, Node 24.18.0, OpenSSL 3.5.7 | 109 | 86 | 265 |
| Docker, Node 20.10.0, OpenSSL 3.0.11 (lead's rerun) | 109, 11 s | 86, 9 s | 265, 22 s |
| Docker, Node 20.10.0, LibreSSL 3.3.6 (lead's rerun) | 109, 10 s | 86, 9 s | 265, 22 s |

| Suite | Plain | Under Valgrind |
|---|---|---|
| `test-origin-tls` | 8.9 s | 22 s |
| `test-curl-testing` | 23.3 s | 42 s |
| `test-origin` | 12.8 s | 27 s |

## Part 5: the third review, and fix round 4

### 5.1 The third review (Opus, read-only, scoped to fix round 3)

It found no blocker: the origin is right, and the baseline copy passed 86, 109 and 265. It
found two should-fix holes in the stop check, from the two classes round 3 had closed
(`build/verify/m1s2/review3/`, `mk3.py`, `run3.sh`):

| Finding | Mutant | Evidence |
|---|---|---|
| A waiting state `close()` never ends was missing: a raw or raw-tls script still playing, between a drip's writes | `raw-playing-spared`: stop() spares a playing socket | Green in all three suites on Node 24. `drip-at-stop.sh`: the origin exits 9805 ms after its stdin ends, against 10 ms |
| The two-set argument rules out per-connection timers only, not one schedule that ends every connection at once | `https-watchdog`: a reap every 1300 ms from listen; `https-shed`: every connection ended 300 ms after a face has more than 6 | Green 3 of 3 on Node 24, and on Node 20 |

**Its notes:**
- **The ALPN refusal was read loosely:** a face with no TLS gives the same `refused` row.
  Every real refusal writes `alert number 120` on stderr, on all three checkers.
- **The stop test cannot tell a destroy from an exit:** `exit-at-once` passes, and is
  equivalent at the TCP level. The test name and plan claimed more.
- **B = 500 ms is safe, with a margin of at least 1.5× even on 1 CPU.**
  - 2 CPUs: 129–148 ms idle, 163–177 ms under Valgrind, 150–169 ms with 2 busy loops.
  - 1 CPU: 315–324 ms under Valgrind, 301–313 ms with 2 busy loops.
  - It reproduced 36–44 ms idle on the container's CPUs. No idle file had been saved for
    the 35–43 ms cited.
- **Sparing only the HTTP/2 states that Node 24's `close()` ends** is caught on Node 20
  alone, which means CI's floor lane and the Docker run. Every face also has states
  `close()` never ends, so sparing a whole face fails everywhere.

**Found sound:**
- `call-with-origin`'s return bounds every connection. It waits for the runner shell's
  stdout, which ends after `wait`, so after Node exits.
- Every probe's end line is required.
- The silence read, and Δ > B against per-connection and server-wide inactivity timers.
- No-SNI, `certificate-names`, `certificate-time`, and the probe's duplicate refusal.

### 5.2 Fix round 4 (the builder, resumed)

- **A script still playing.**
  - **A new script,** `/raw/pause-mid-body?ms=N` for N from 1 to 60000: a head with
    `Content-Length: 11`, then `hello`, a wait of N ms, ` world`, and a FIN. It is
    additive: the drip's range and its edge tests stay as they were.
  - **`test-origin` checks its bytes** at ms=50, its edges at 1 and 60000, and its
    refusals at 0, 60001 and none.
  - **The stop tables gain** "a script playing, between two of its writes", and the same
    with the client half-closed, for raw and raw-tls, at ms=60000.
- **A shared schedule.** Each stop check runs twice on fresh origins, the second with both
  sets held 700 ms longer before the stop.
- **The ALPN refusal** requires `alert number 120` on stderr. It was measured on every real
  refusal with all three checkers, and never on `http` or `h2c`
  (`measure6/alpn-alert-lines-node{24,20}.txt`). The mutant was a callback that throws,
  which drops the connection with no alert.
- **Names:**
  - "the destroy's" became "the stop's", and "every waiting state" became "each waiting
    state its table names";
  - the comment names three states no check holds.
- **B idle, saved:** 34–46 ms over 10 runs (`measure5/stop-spread-idle.txt`).

**The `r4-` mutations:** 8 run, 7 caught. The table now has 159 run and 150 caught. The one
not caught, `r4-exit-at-once`, is equivalent at the TCP level, as the third review found,
and is recorded as a limit (plan §8.8).

| Case | Mutation | Caught | First failing test |
|---|---|---|---|
| `r4-alpn-refused-without-alert` | the https faces refuse an ALPN mismatch by dropping the connection, with no alert | yes | https: its ALPN set pinned, offered each of h2, http/1.1 and an unknown protocol alone (+3) |
| `r4-exit-at-once` | stop() exits at once, destroying nothing: the kernel closes every socket at the exit | NO | none |
| `r4-http-shed` | http untracked; once more than 6 are open, it ends them all 300 ms later | yes | stopping ends every connection to a plaintext face, in each waiting state its table names: the same on a fr… |
| `r4-http-watchdog` | http untracked; every 1300 ms from the listen, a reap of every http connection once one is older than 600 ms | yes | stopping ends every connection to a plaintext face, in each waiting state its table names: the same on a fr… |
| `r4-https-shed` | https untracked; once more than 6 are open on one face, it ends them all 300 ms later | yes | stopping ends every connection to a TLS face, in each waiting state its table names: two sets of probes, th… (+1) |
| `r4-https-watchdog` | https untracked; every 1300 ms from the listen, a reap of every https connection once one is older than 600 ms | yes | stopping ends every connection to a TLS face, in each waiting state its table names: the same on a fresh or… |
| `r4-raw-half-closed-spared` | stop() spares a raw or raw-tls socket whose client has half-closed | yes | stopping ends every connection to a TLS face, in each waiting state its table names: two sets of probes, th… (+4) |
| `r4-raw-playing-spared` | stop() spares a raw or raw-tls socket whose script is playing | yes | stopping ends every connection to a TLS face, in each waiting state its table names: two sets of probes, th… (+4) |

**The sweep, re-run on round 4's tree** (`sweep-matrix-r4.md`): 24 cases.
- They were raw and raw-tls at every L and with no close, https at 1200, 2500 and no close,
  and https-wrong-host at 1200.
- Each fails both stop runs on Node 24.18.0 and on Node 20.10.0.

**The lead's own checks:** `raw-playing-spared`, `https-shed` and `https-watchdog`
(`R3_D=1300 R3_H=600`) were built by the third review's `mk3.py` from round 4's tree
(`mine4/`). Each failed by a stop test's name:
- `raw-playing-spared`: all four stop runs, and the scenarios' stop;
- `https-shed` and `https-watchdog`: the held TLS run.

### 5.3 The final checks

The builder's, and the lead reran each on the final tree:

| Check | Result |
|---|---|
| `make test` | `test: ran 18, passed 18, failed 0, hung 0` |
| `make check-test-fails` | `make test failed, as it must, in all 10 cases` |
| `make check-suites`, `make check-seam` | 18 suites; 10 libraries in 10 files |
| `make test-memory` on the three origin suites | `ran 3, passed 3`, with 0 errors and 0 definitely lost |
| `test-origin-tls`, `test-origin` under 24 busy loops (builder) | 20 of 20 each |

| Run | `test-origin` | `test-origin-tls` | `test-curl-testing` |
|---|---|---|---|
| Container, Node 24.18.0, OpenSSL 3.5.7 | 116 | 87 | 265 |
| Docker, Node 20.10.0, OpenSSL 3.0.11 (lead) | 116, 13 s | 87, 10 s | 265, 23 s |
| Docker, Node 20.10.0, LibreSSL 3.3.6 (lead) | 116, 13 s | 87, 10 s | 265, 23 s |

| Suite | Plain | Under Valgrind |
|---|---|---|
| `test-origin-tls` | 11.0 s | 26 s |
| `test-curl-testing` | 23.5 s | 42 s |
| `test-origin` | 15.1 s | 31 s |
