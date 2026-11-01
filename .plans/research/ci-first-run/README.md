# CI's first runs: the evidence for their fixes (2026-11-01)

CI ran for the first time on PR #38, M6 slice 3. Four suites failed across its two complete runs,
each at a test already on `main`. This is what I measured to explain each one. The programs ran
from git-ignored scratch under `build/cifix/`, so their paths name it; they are kept as they ran.
`docker.sh` ran each lane in Docker `ubuntu:24.04`, the runner's image, on a copy of the tree,
with Node 22.23.4, the runner's own, from nodejs.org, checked against its `SHASUMS256.txt`.

| File | What it is |
|---|---|
| `results/ci-run-41338306057-failed.log` | the PR at `b4a5e08`: main's `wire-probe-reset` peer test read a FIN where the probe had reset; the floor's 100,000-header GET never completed within 60,000 ms; current's full-buffer upload never filled |
| `results/ci-run-41340591223-failed.log` | the PR at `9759dd4`: current's full-buffer upload never filled again, `never-full 33554432`; the memory lane failed two of test-upload's tests, which its output did not name, Valgrind finding 0 errors |
| `reset-race.mjs`, `results/reset-race.log` | a server whose loop is blocked as each connection arrives, against `wire-probe.mjs --reset`: blocked 200 ms, Node 22.23.4 (libuv 1.51.0) and 20.10.0 (1.46.0) reported an end in 20 runs of 20, while one read(2) of the fd threw `ECONNRESET`; 24.18.0 (1.52.1) read the reset 20 of 20. Unblocked, 22.23.4 and 20.10.0 each read an end once in 20 |
| `results/ct-*.log` | test-curl-testing with the stand-in fixed: the tree passes on Node 22, 20 and 24; without its fd read it fails on 22 and 20, as CI did; a probe that destroys where it should reset fails it |
| `many-headers.sps`, `results/mh-*.log`, `results/mh2-*.log` | a GET of N headers, timed: on 7.85.0, 20,000 took 1.3 s, 50,000 7.3 to 7.6 s, 100,000 30.4 to 31.5 s, all of it CPU; 8.5.0, OpenSSL and GnuTLS, took 20,000 in 1.9 s and refused 30,000 and more with 56; 8.20.0 and 8.23.0 refused 20,000 and more with 100 |
| `results/tr-*.log` | test-transfer with its case at 50,000, on the five Linux libcurls: each passes, the floor's run 15.8 s, from 39.6 s at 100,000 (`tr-floor-1.log`) |
| `results/gate-before.log`, `results/gate-after.log` | `make check-memory-gate` with its failing stand-in printing a FAIL line 15 lines before its end: before test-memory printed FAIL lines, 38 cases ok and that one FAILED; after, 39 of 39 |
| `results/up-*.log`, `results/vg-upload-1.log` | test-upload with the fill's trace, on four lanes here: each filled at 1,966,080 or 2,097,152 bytes, in 1,084 to 2,052 ms; under the memory gate's Valgrind on 8.5.0, at 2,031,616 bytes in 1,155 ms, 58 of 58 |
| `results/tr-floor-mut49999.log` | the floor's test-transfer with 7.85.0's cell wrong, 49,999 headers: the by-version test fails by name |
| `results/guix-full-1.log` | the container on this tree: check-suites, check-seam and check-floors, then `make test` 35 of 35 |

curl's `lib/headers.c` shows why the headers cost n²: `curl_easy_nextheader` counts, from the first
header, every one that shares the name of the one it returns, on 7.85.0, 8.20.0 and 8.23.0.
`lib/http.h` caps a response's headers at 300 KiB on 8.7.1 and 8.20.0, and at 5,000 on 8.20.0;
7.85.0's has no cap.
