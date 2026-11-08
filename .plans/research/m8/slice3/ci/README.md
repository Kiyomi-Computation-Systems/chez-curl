# PR #52's first CI run, and the Node it ran

PR #52's first run (42441292684, at `928ac85`) failed three jobs, `main`, `gnutls` and `memory-1`,
each on one cell alone: `test-multipart`'s 8.5.0 row held `after-grown-h2` at 92, and each job
measured 56 (`pr52-failed.log`, `pr52-run-42441292684-jobs.txt`). Those three jobs run the test
origin under the runner's own Node, 22.23.4 there; every local run had used Node 20.10.0, or
24.18.0 for the probe.

Reproduced in Docker on Ubuntu 24.04's 8.5.0, OpenSSL and GnuTLS builds, `make test
SUITES=tests/test-multipart.sps`, with Node 22.23.4 from nodejs.org (its tarball checked against
`SHASUMS256.txt`) and with 20.10.0, by `lanes-node.sh` and `lanes-in-docker-node.sh`, slice 3's
lane scripts with the suite's Node taken from `NODE_FOR_TEST`:

| libcurl | Node 22.23.4 | Node 20.10.0 |
|---|---|---|
| 8.5.0, OpenSSL | 56 in 3 of 3 (`test-node22-{1,2,3}-openssl.log`) | 92 (`test-node20-1-openssl.log`) |
| 8.5.0, GnuTLS | 56 in 3 of 3 (`test-node22-{1,2,3}-gnutls.log`) | 92 (`test-node20-1-gnutls.log`) |
| 7.85.0 | 92 in 2 of 2 (`test-node22-{1,2}-floor.log`) | 92 (the build's runs) |

So the cell is the test origin's answer to libcurl's overrun, by Node's version. The 8.5.0 cell now
holds both answers, and passes under both Nodes on both builds (`test-fixed-*.log`). The summaries
are `node-lanes*.out` and `node-lanes*-summary.txt`.
