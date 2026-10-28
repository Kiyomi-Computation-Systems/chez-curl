# A sleep of no time under Valgrind (M5 slice 1, 2026-10-27)

`test-url`'s flip test, M2's, has its main thread normalize a URL 1000 times while a second
thread flips one char of it between `a` and U+0000, and requires both answers, the URL whole
and refused as `embedded-nul`. Its main thread yielded with a sleep of no time every tenth call,
so that under Valgrind, which runs one thread at a time, the flipper would run. On this branch
the memory lane failed it in 2 of its 3 full runs, the flipper never seen in the NUL state.

In the container, a copy of the suite that counted the refused answers under the memory gate
(`build/m5s1/flipdiag/`, the suite with a count printed) answered 530, 0 and 270 in three runs,
failing the second (`results/zero-sleep.log`): the zero sleep can hand the main thread the lock
straight back, and the flipper then never runs. The same copy with a 1 ms sleep in its place
answered 490 to 500 in each of 6 runs, all passing; `main`'s suite passed 4 of 4 there
(`results/one-ms-and-main.log`). Both flip tests, `test-url`'s and `test-url-parts`', now sleep
1 ms before every tenth call.
