# M8 slice 2, built: the logs

The slice as built on `feat/m8-header-cap`, 2026-11-06 and 07: the cap on response headers in
`src/curl/private/transfer.sls` and `conditions.sls`, `SUPPRESS_CONNECT_HEADERS` owned, the
origin's head routes and send limit, `tests/test-headers.sps`, and the suites that write the
changed lists out. The lanes are the measurement's ([../README.md](../README.md)): F 7.85.0, O and
G Ubuntu's 8.5.0 with OpenSSL and GnuTLS, C 8.23.0, in Docker `ubuntu:24.04` with `--network none`,
CPUs 6 to 11, by `../lanes.sh`; X Guix's 8.20.0, `scripts/guix-env`, CPUs 12 to 17.

The final tree's logs, then the earlier ones they replace.

| log | what |
|---|---|
| `ci-chain-guix-3.log` | lane X, the final tree: `make check-help check-suites check-seam check-floors build test check-test-fails check-dev check-clean` |
| `test-final4-docker.log`, `test-final4-{floor,openssl,gnutls,current}.log` | lanes F, O, G, C, the final tree: `make deps test`, every suite |
| `test-final4-again-*.log` | lanes F, O, G, C: `test-headers` and `test-transfer`, which read a table's rows, a second time |
| `memory-final4-docker.log`, `memory-final4-{openssl,floor}.log` | lanes O and F: `make test-memory` of `test-headers`, `test-origin`, `test-origin-tls` and `test-transfer` |
| `test-memory-guix-final.log`, `memory-test-headers-keyed-{1..4}.log`, `memory/` | lane X: `make test-memory` of every suite added or changed, `test-headers` four times; Valgrind's logs |
| `check-memory-gate-guix.log` | lane X: `make check-memory-gate` |
| `mutants.py`, `mut-run.sh`, `mutants-run-3.log`, `mutants-check-3.txt`, `mutants/` | the mutants, made from the final tree, run in lane X, checked by name |

Earlier, each replaced as the tree moved:

| log | what, and what replaced it |
|---|---|
| `snap1-docker.log` | lanes F, O, G, C, the changed suites' first run: the 8.23.0 row's `trailers-6000-h2` cell was wrong, and fixed |
| `ci-chain-guix.log`, `test-final-docker.log`, `test-final-*.log`, `test-final-again-*.log`, `test-again-guix-8.20.0.log` | every lane, every suite, before the two Valgrind fixes below; all passed |
| `test-memory-guix.log`, `memory-test-headers-1.log`, `memory-test-headers-time-{a,b}.log`, `test-memory-guix-{2,3}.log`, `memory-fixed-*` | lane X under the gate: `test-headers`' 417 case failed in two of six runs, and `test-origin-tls`' h2 trailer block of 6,000 lines once; then the trailer rows' probe read to idle, and the 417 route held its 417 by key |
| `test-fixed-{1,2}-*.log` | lanes F, O, G, C: `test-headers` and `test-origin-tls` after the first fix, twice |
| `ci-chain-guix-2.log` | lane X: run while the 417 fix was being written, so its suites mixed two trees; not a result |
| `mutants-run-{1,2}.log`, `mutants-check-{1,2}.txt` | the mutants on the earlier trees: every one killed both times |
