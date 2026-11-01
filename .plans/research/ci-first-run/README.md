# CI's first runs: the evidence for their fixes (2026-11-01)

CI ran for the first time on PR #38, M6 slice 3. Five suites failed across its two complete runs
and `main`'s push after it, each at a test already on `main`. This is what I measured to explain each one. The programs ran
from git-ignored scratch under `build/cifix/`, so their paths name it; they are kept as they ran.
`docker.sh` ran each lane in Docker `ubuntu:24.04`, the runner's image, on a copy of the tree,
with Node 22.23.4, the runner's own, from nodejs.org, checked against its `SHASUMS256.txt`.

| File | What it is |
|---|---|
| `results/ci-run-41338306057-failed.log` | the PR at `b4a5e08`: main's `wire-probe-reset` peer test read a FIN where the probe had reset; the floor's 100,000-header GET never completed within 60,000 ms; current's full-buffer upload never filled |
| `results/ci-run-41342516891-failed.log` | `main`'s push at `969e981`: current's full-buffer upload never filled a third time; the memory lane failed test-retry's live run-out-of-time check, one transfer at 1,440 ms, and test-upload's two |
| `results/ci-pr39-fill.log` | PR #39's first run, at `1dcf451`: the runner's kernel, 7.0.0-1017-azure, and TCP buffers; on 8.23.0 the fill stalled at 2,031,616 bytes, then libcurl took one 64 KiB piece more at 1,049, 2,050, 3,051, 4,051 and 5,052 ms, until the sink read at 5 s; on 8.5.0, GnuTLS, it stalled at once |
| `results/up-new-*.log`, `results/vg-upload-new.log`, `results/up-drain700-new-*.log` | the fill that asks only for a quiet through the put's own bound: it stalls at 548 to 593 ms on each lane, and at 781 ms under Valgrind |
| `results/up-holdignored-new-*.log` | the same fill with the sink's hold ignored, slice 2's `hold-ignored`: it fails, `never-full`, on 8.23.0 and 8.5.0 |
| `trickle.sed`, `drain700.sed`, `results/up-trickle*-old-*.log`, `results/up-drain700-old-*.log` | origin mutants that read the held sink a little each second or each 700 ms, to stand in for the runner's kernel: none reproduced it, the old fill retrying once at most. Linux keeps its window shut until about half the receive buffer is free, so a small read does not reopen it |
| `results/vg-retry-cpu*.log`, `results/vg-retry2-cpu*.log`, `results/retry2-*.log` | test-retry under the memory gate's Valgrind in Docker held to 1 and 0.5 CPU: at 0.5 the old check failed, its first 28 at the bound; with 2,000 ms of a 3,500 ms bound it passes at both, and natively on 7.85.0, 8.5.0 and 8.20.0 |
| `results/gate-dup-mutant.log`, `results/gate-after-2.log` | the gate check that each FAIL line is shown once, a FAIL in the suite's last 10 lines among them: test-memory as first changed, printing that one twice, fails it, 38 ok and 1 FAILED; the tree, 39 of 39 |
| `results/ci-run-41340591223-failed.log` | the PR at `9759dd4`: current's full-buffer upload never filled again, `never-full 33554432`; the memory lane failed two of test-upload's tests, which its output did not name, Valgrind finding 0 errors |
| `reset-race.mjs`, `results/reset-race.log` | a server whose loop is blocked as each connection arrives, against `wire-probe.mjs --reset`: blocked 200 ms, Node 22.23.4 (libuv 1.51.0) and 20.10.0 (1.46.0) reported an end in 20 runs of 20, while one read(2) of the fd threw `ECONNRESET`; 24.18.0 (1.52.1) read the reset 20 of 20. Unblocked, 22.23.4 and 20.10.0 each read an end once in 20 |
| `results/ct-*.log` | test-curl-testing with the stand-in fixed: the tree passes on Node 22, 20 and 24; without its fd read it fails on 22 and 20, as CI did; a probe that destroys where it should reset fails it |
| `many-headers.sps`, `results/mh-*.log`, `results/mh2-*.log` | a GET of N headers, timed: on 7.85.0, 20,000 took 1.3 s, 50,000 7.3 to 7.6 s, 100,000 30.4 to 31.5 s, all of it CPU; 8.5.0, OpenSSL and GnuTLS, took 20,000 in 1.9 s and refused 30,000 and more with 56; 8.20.0 and 8.23.0 refused 20,000 and more with 100 |
| `results/tr-*.log` | test-transfer with its case at 50,000, on the five Linux libcurls: each passes, the floor's run 15.8 s, from 39.6 s at 100,000 (`tr-floor-1.log`) |
| `results/gate-before.log`, `results/gate-after.log` | `make check-memory-gate` with its failing stand-in printing a FAIL line 15 lines before its end: before test-memory printed FAIL lines, 38 cases ok and that one FAILED; after, 39 of 39 |
| `results/up-*.log`, `results/vg-upload-1.log` | test-upload with the fill's trace, on four lanes here: each filled at 1,966,080 or 2,097,152 bytes, in 1,084 to 2,052 ms; under the memory gate's Valgrind on 8.5.0, at 2,031,616 bytes in 1,155 ms, 58 of 58 |
| `results/tr-floor-mut49999.log` | the floor's test-transfer with 7.85.0's cell wrong, 49,999 headers: the by-version test fails by name |
| `results/guix-full-1.log`, `results/guix-full-2.log` | the container on the first and the second commit: check-suites, check-seam and check-floors, then `make test` 35 of 35 |

curl's `lib/headers.c` shows why the headers cost n²: `curl_easy_nextheader` counts, from the first
header, every one that shares the name of the one it returns, on 7.85.0, 8.20.0 and 8.23.0.
`lib/http.h` caps a response's headers at 300 KiB on 8.7.1 and 8.20.0, and at 5,000 on 8.20.0;
7.85.0's has no cap.
