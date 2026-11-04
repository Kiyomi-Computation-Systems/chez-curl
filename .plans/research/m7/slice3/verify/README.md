# M7 slice 3's measurement, checked (2026-11-03)

I checked the measurement's hand-back before building on it, on the files as the agent left them:
`src/` at main (`0080fbff…`), the prototype `b2a1f0e9…`, `proxy.sps` `eb28bfda…`, `standin.mjs`
`7f99adb4…`, each recorded on its log's lines 4 to 6.

- **The Guix lane, rerun whole** ([`results/rerun-guix-8.20.0.log`](results/rerun-guix-8.20.0.log)),
  every part exiting 0. `tables.mjs` read it beside the kept run 1, lane X alone: every cell
  agrees ([`results/compare-guix-kept-rerun.md`](results/compare-guix-kept-rerun.md), "What
  split": nothing).
- **A planted change:** a copy of the rerun with one cell's code changed, 3 to 7, `userinfo19`.
  `tables.mjs` marked that cell alone, and listed it under "What split"
  ([`results/compare-guix-planted.md`](results/compare-guix-planted.md)).
- **7.85.0 and Ubuntu's 8.5.0 with OpenSSL, rerun in Docker,** the parts `userinfo`, `pooled`,
  `refused` and `stall` ([`results/rerun-docker-floor-openssl.log`](results/rerun-docker-floor-openssl.log)),
  beside the kept run 1 ([`results/compare-docker-kept-rerun.md`](results/compare-docker-kept-rerun.md)):
  every cell agrees but 7.85.0's HTTP/2 origin through an `https://` proxy, which stalled 3 of 10
  in both, the cell differing only in the order its counts are listed. So the decoded control
  byte that goes direct (`userinfo19`, lines 259-264 and 3936-3941: `via=direct`, the proxy
  logging nothing), the pooled tunnel 7.85.0 hands another user, the retry's split by version, and
  7.85.0's intermittent stall all came again.
- **Read in source:** 7.85.0's `parse_proxy` jumps to `error` with `result` still `CURLE_OK` when
  the userinfo's decode fails (`lib/url.c:2441`, `2512-2517`); 7.85.0 reads `FORBID_REUSE` only
  as a transfer ends (`lib/multi.c:703`) and `FRESH_CONNECT` as one starts (`lib/url.c:3995`);
  Apple's 8.7.1 matches an HTTP proxy connection by type, port and host alone
  (`lib/url.c:701-710`), comparing the user and password for NTLM only (`lib/url.c:1238-1250`).
  The sources are curl's release tarballs in `build/verify/current/` and `build/m4s3/src/`.
- **Why Ubuntu's 8.5.0 differs from 7.85.0 on the pooled tunnel:** it is
  [CVE-2026-3784](https://curl.se/docs/CVE-2026-3784.html), "wrong proxy connection reuse with
  credentials", curl 7.7 to 8.18.0, fixed in 8.19.0; Ubuntu's noble package carries the fix from
  `8.5.0-2ubuntu10.8` ([UBUNTU-CVE-2026-3784](https://osv.dev/vulnerability/UBUNTU-CVE-2026-3784)),
  and the lanes ran `10.16` ([`../results/docker-1.log`](../results/docker-1.log), lines 4-5).

## The build, checked (2026-11-03)

On the builder's hand-back, before the review:

- **`make test` in the container,** 38 of 38 ([`results/build-make-test-guix-8.20.0.log`](results/build-make-test-guix-8.20.0.log)).
- **Four mutants of my own,** made by [`build-mutants.py`](build-mutants.py) on a copy of the tree
  (`build/m7s3-check/tree`, every file but `build/`, `.git` and `.plans`), each failing tests, the
  copy itself passing test-proxy and test-retry
  ([`results/build-mutants-control.log`](results/build-mutants-control.log)):
  - `noproxy-gone`, `proxy-settings` without `NOPROXY ""`: the written-out settings, and all four
    children whose `no_proxy`, `NO_PROXY` or `*` then sent the transfer direct;
  - `password-unscanned`, the decoded rule reading the user alone: the byte rule by position, the
    UTF-8 rule, and the leak test;
  - `connect-code-ignored`, the retry reading no `CONNECT` status: test-proxy's retry through a
    503 and a 407, and three of test-retry's `exchange-step` tests;
  - `scheme-refusal-holds-url`, `proxy-scheme` naming the URL as its value: the scheme and order
    tests, and the leak test, "no refusal holds the proxy's password".
- **test-proxy on 7.85.0 and on Ubuntu's 8.5.0 with GnuTLS,** by the builder's `lanes.sh` on a
  fresh snapshot, each passing, their by-version rows printed
  ([`results/build-lanes-floor-gnutls.out`](results/build-lanes-floor-gnutls.out)).
- **The half-open socket the builder reported:** its `halfopen.mjs` left a connection open 1 s
  after the client's FIN without an `'end'` handler, and none with it, on Node 24.18.0 in the
  container and on Node 20.10.0 ([`results/halfopen-node-20.log`](results/halfopen-node-20.log)).

## The review, and the first fix round, checked (2026-11-03)

- **The review's blocker,** rerun from its `env-join.sps` on 7.85.0
  ([`results/review-env-join-floor-7.85.0.log`](results/review-env-join-floor-7.85.0.log)): the
  environment's transfer got 200 on alice's HTTP/2 connection, one `CONNECT` on the proxy's log;
  both controls refused 407.
- **A fix, measured before it was put to the maintainer:** [`env-join-fix.sps`](env-join-fix.sps),
  the case again beside one on an engine that does not multiplex. On 7.85.0, two runs, the
  environment's transfer sent its own `CONNECT`, refused 407
  ([`results/env-join-fix-floor-7.85.0-1.log`](results/env-join-fix-floor-7.85.0-1.log), `-2`).
- **The review's major,** rerun from its `keys-leak.sps`
  ([`results/review-keys-leak-guix-8.20.0.log`](results/review-keys-leak-guix-8.20.0.log)): all
  nine cases printed the password.
- **The fix round:** `make test` 38 of 38
  ([`results/fix-make-test-guix-8.20.0.log`](results/fix-make-test-guix-8.20.0.log)); test-proxy
  on 7.85.0 from a snapshot, passing
  ([`results/fix-floor-test-proxy.out`](results/fix-floor-test-proxy.out)), and failing two tests,
  the switch on a live connection and the environment's join, under a mutant of mine whose engine
  records `switched` without telling libcurl
  ([`results/fix-floor-mutant-switch-untold.out`](results/fix-floor-mutant-switch-untold.out)).
- **Two older leaks the fix round's audit left,** reproduced by
  [`accessor-leak.sps`](accessor-leak.sps) on Guix's 8.20.0
  ([`results/accessor-leak-guix-8.20.0.log`](results/accessor-leak-guix-8.20.0.log)): a raw
  accessor handed a string, and a URL refused at submit, each printed the password.
- **The environment proxy's userinfo,** the builder's `env-userinfo.sps` from a snapshot by
  [`probe-docker-snap.sh`](probe-docker-snap.sh), on 7.85.0 and Ubuntu's 8.5.0 with OpenSSL
  ([`results/env-userinfo-floor-openssl.log`](results/env-userinfo-floor-openssl.log)): a user or
  password decoding to 0x00, 0x01 or 0x1F went direct, 200, nothing on the proxy's log; `%7F`
  and the controls went through it; a raw 0x01 failed 5.

## The second fix round, checked (2026-11-03)

- **`make test`,** 39 of 39, test-printed among them
  ([`results/fix2-make-test-guix-8.20.0.log`](results/fix2-make-test-guix-8.20.0.log)).
- **My leak probe again,** `accessor-leak.sps`: each of its four cases now prints no password,
  an accessor naming `(kind string)` and a URL refusal naming `url`
  ([`results/accessor-leak-after-guix-8.20.0.log`](results/accessor-leak-after-guix-8.20.0.log)).
- **Two mutants of mine,** by [`fix2-mutants.py`](fix2-mutants.py), each putting one public
  accessor back to its raw Chez accessor, neither among the builder's: `http-response-history`
  and `curl-transfer-error-connect-code`. Each failed test-printed's row test and its "no export
  prints the password" test; the copy itself passed
  ([`results/fix2-mutant-control.log`](results/fix2-mutant-control.log),
  `fix2-mutant-raw-history.log`, `fix2-mutant-raw-connect-code.log`).
- **After the records were brought to what was built,** `make test` again, 39 of 39
  ([`results/records-make-test-guix-8.20.0.log`](results/records-make-test-guix-8.20.0.log)).

## The Mac's first run, and its fix (2026-11-03)

The Mac's `make test` at `5a98ffe` failed test-proxy, 29 of 96: every `https://` proxy refused,
`https-proxy-unsupported` ([`../results/mac-8.7.1-make-test.log`](../results/mac-8.7.1-make-test.log)).
The check read the features word the load had read before `curl_global_init`; Apple's MultiSSL
8.7.1 computes the word from the backend in use, its selector until the init, which supports
nothing (8.7.1 `lib/version.c:424-428`, `lib/vtls/vtls.c:1306-1308`, read in source). I made the
fix myself: the call after the init that reads the backend reads the word too,
`loaded-features`, and the decoy libcurl's MultiSSL build sets the bit at its init.

- `make test` in the container, 39 of 39
  ([`results/macfix-make-test-guix-8.20.0.log`](results/macfix-make-test-guix-8.20.0.log)).
- A mutant, `loaded-features` answering the word read before the init: the decoy's MultiSSL test
  fails on Linux, where test-proxy cannot see it
  ([`results/macfix-mutant-pre-init-features.log`](results/macfix-mutant-pre-init-features.log)).
- test-proxy, test-library-loading, test-load-state and test-native on the four Docker lanes,
  and under the memory gate on Ubuntu's 8.5.0 with OpenSSL, each passing
  ([`results/macfix-lanes.out`](results/macfix-lanes.out)).
- Eight 8.7.1 rows from the run's two passes, each through an `http://` proxy, which the bug did
  not touch: `empty-userinfo`, `empty-userinfo-wire`, `refused-connect` (its size `unknown`, #f, as
  8.7.x reports every request size), `unshared-tunnels`, `tunnel-plans`, `switch-live`,
  `environment-join` and `closing-retries`.
- **The Mac's second run,** at `043ef4e` ([`../results/mac-8.7.1-make-test-2.log`](../results/mac-8.7.1-make-test-2.log)):
  test-proxy failed 7 of 96, five waiting on `tls-in-tls-checks`' 8.7.1 row and two that wrote a
  TLS failure's request size as 0, which 8.7.x reports as #f. With the row and the size written by
  version, test-proxy passed in the container and on the four Docker lanes
  ([`results/mac2-test-proxy-guix-8.20.0.log`](results/mac2-test-proxy-guix-8.20.0.log),
  [`results/mac2-lanes.out`](results/mac2-lanes.out)).
