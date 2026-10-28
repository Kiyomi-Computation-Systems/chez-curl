# A collection inside a timed window under Valgrind (M5 slice 1, 2026-10-27)

The memory lane failed `test-engine` on this branch: a failed engine's second stop, which must
return within 50 ms, took 142 to 145 ms, in 2 of 3 runs of the memory lane on `test-engine` and
`test-url` alone (`results/before-fix-3-runs.txt`, `before-fix-run2.log`, `before-fix-run3.log`).
`main` passed `test-engine` there 3 of 3. A copy of the suite that counted Chez's `(collections)`
around the window (`results/diag-run3.log`) failed once in 3 runs, with `(ms 144 collections
1)`: a collection landed in the window, and under Valgrind one takes about 140 ms. The branch
allocates more along the way, so its collections fall elsewhere.

The fix is the suite's: `(collect)` just before each of its two at-once windows opens, so none
is due inside. After it, the branch passed `test-engine` and `test-url` 5 of 5 under Valgrind,
and `main` passed `test-url` 5 of 5 (`results/after-fix-and-main-runs.txt`). `test-url`'s flip
test failed once on this branch, in the memory lane's full run, seeing the URL whole 1000 times
and never refused: 1 of 9 Valgrind runs of it here, 0 of 5 on `main`, too few to tell apart.

The lanes ran `build/m5s1/lanes.sh memsuites` (`make test-memory` alone, on the suites named in
`SUITES`), Docker `ubuntu:24.04`, libcurl 8.5.0, from the repository's root.
