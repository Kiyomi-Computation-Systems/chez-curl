# Memory gate and CI mutation log (M0 slice 5)

Evidence for the checks M0 slice 5 added, one part per agent, then three rounds of review fixes:

1. [The memory gate](#the-memory-gate): `make test-memory`, `make check-memory-gate`, the
   planted defects and the container's one suppression (ADR-0014).
2. [CI](#ci): `.github/workflows/ci.yml`, `make check-nothreads`, and `check-floors` holding
   the workflow (ADR-0001, ADR-0003, ADR-0016).
3. [Review fixes](#review-fixes): an allowlist of what Valgrind reads, and evidence that it ran.
4. [Review fixes: CI](#review-fixes-ci): the gate on every run, two disabled-API lanes, every
   workflow file under check-floors, and actions pinned to SHAs.
5. [Second review fixes](#second-review-fixes): Valgrind's options block and its own log, and
   the crossing rule in test-collect-safe.
6. [The lead's addition: scheme-object](#the-leads-addition-scheme-object).
7. [Third review fixes](#third-review-fixes): every type held to an allowlist, pattern variables
   tracked, string marks, and the evidence check's `ok` line.
8. [Third review fixes: CI](#third-review-fixes-ci): CI reads the floors from the file, and the
   pin check catches every spelling.

Each part's driver kept every run's whole output in the session scratchpad. This log cuts a
diff to its first 15 lines and an output to its first 19, and says how many lines were cut.

## The memory gate

Evidence that the memory gate fails through each property it claims to guard
([ADR-0014](decisions/0014-valgrind-memory-gate.md), as amended 2026-10-16). The part is:

- `Makefile`: `VALGRIND`, `MEMORY_TIMEOUT` (3600 s a suite), `MEMORY_SUITES` (every suite),
  `MEMORY_LOGS` and `MEMORY_SUPPRESSION_FILE`, and two targets:
  - `make test-memory` runs each suite as `timeout 3600 valgrind --error-exitcode=9
    --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite
    [--suppressions=tests/guix-glibc-locpath.supp] $CHEZ --libdirs … --program SUITE`, the
    suppression only when `GUIX_ENVIRONMENT` is set. It logs each to `build/memory/<suite>.log`,
    names each pass, FAIL (saying when the exit is Valgrind's 9) or HUNG, prints a FAIL's
    first error, definite loss, suppressed total and error summary, goes on after a failure,
    and fails on any failure, hang, or no suite. Two rules go beyond the brief, each from a
    measurement below: it refuses to run while `VALGRIND_OPTS`, `$HOME/.valgrindrc` or
    `./.valgrindrc` is present, and in a Guix environment it fails a suite that exits 0 with
    more than one block suppressed;
  - `make check-memory-gate` runs `tests/check-memory-gate.sh`.
- `tests/memory-plant-overrun.sps` and `tests/memory-plant-leak.sps`, the planted defects: one
  byte written past a 23-byte foreign block, and a 777-byte foreign block nothing holds.
- `tests/memory-load-curl.sps`, which loads libcurl through `(curl)` and says which.
- `tests/guix-glibc-locpath.supp`, the one suppression: `guix-glibc-locpath`, a definite leak
  under `realloc`, `argz_add_sep`, `compute_locale_search_path` and `newlocale`.
- `tests/check-memory-gate.sh`, 16 cases, each named `ok` or `FAILED`: (a) each plant run
  plainly; (b) test-memory on each plant, and on a program that exits 1, each followed by a
  clean one; (c) the suppression file's whole entry; (d), in a Guix environment only, the
  suppression used on one block, needed, not hiding the planted leak, and not hiding a second
  block; (e) the whole command handed to a stand-in for Valgrind, with `GUIX_ENVIRONMENT`
  unset and set; (f) a hang; (g) no suite; (h) `VALGRIND_OPTS` and `$HOME/.valgrindrc`.

A driver in the session scratchpad ran every mutation. It froze a snapshot of the working
tree, without `.git`, `build/` or `.claude/`, and gave each mutation a fresh copy of it. It
applied the mutation by exact-text replacement, aborting unless the target occurred exactly
once, and refused a mutation whose diff was empty unless its command differed. It touched the
copy's `manifest.scm` (`traps.md`, the stale `guix shell -m` profile) and ran the command
through the copy's own `scripts/guix-env`, so the container saw only that copy. Three ran at
a time. A mutation counts as killed only when the command exits non-zero and every expected
line appears in its output: whole, or, for a Valgrind line whose process number varies, as a
substring. The expected lines are the `FAILED` lines of the cases that must fail, and the
problem line that says why. The working tree was never edited.

**Result** quotes at most 12 lines: the expected lines first, then the other `FAILED` lines,
then the problem lines and any `test-memory:` or `direct:` lines, in output order, and says
how many more were cut. Each diff keeps one line of context, and `...` sets its hunks apart.
A diff line longer than 200 characters, and an output line longer than 240, is cut, and says
how much was cut.

### Measurements

All in the container: Valgrind 3.27.0, Chez 10.4.0, libcurl 8.20.0 (GnuTLS), glibc 2.41,
amd64.

**The leak's stack.** `tests/test-native.sps` under ADR-0014's flags and
`--gen-suppressions=all` exited 9. It printed no other error, and no undefined-value report,
so item 1's stop condition did not fire:

```
==824== 171 bytes in 1 blocks are definitely lost in loss record 29 of 39
==824==    at 0x484D3CD: realloc (in /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.27.0/libexec/valgrind/vgpreload_memcheck-amd64-linux.so)
==824==    by 0x4AEDE63: argz_add_sep (in /gnu/store/m31vlvwm79m89fk3xk0z4h7snk61y510-glibc-2.41/lib/libc.so.6)
==824==    by 0x4A8298B: compute_locale_search_path (in /gnu/store/m31vlvwm79m89fk3xk0z4h7snk61y510-glibc-2.41/lib/libc.so.6)
==824==    by 0x4A81FD0: newlocale (in /gnu/store/m31vlvwm79m89fk3xk0z4h7snk61y510-glibc-2.41/lib/libc.so.6)
==824==    by 0x88AE8AA: ??? (in /gnu/store/w9gl8k4gn13vnsjhr0qcasm8iiqh2yd8-p11-kit-0.26.2/lib/libp11-kit.so.0.4.8)
==824==    by 0x4004FCD: call_init (in /gnu/store/m31vlvwm79m89fk3xk0z4h7snk61y510-glibc-2.41/lib/ld-linux-x86-64.so.2)
[6 more frames: _dl_init, _dl_catch_exception, dl_open_worker, _dl_catch_exception, _dl_open, dlopen_doit]
==824==    definitely lost: 171 bytes in 1 blocks
==824== ERROR SUMMARY: 1 errors from 1 contexts (suppressed: 0 from 0)
```

The entry keeps the four glibc frames from `realloc` down to `newlocale`. It names no
p11-kit frame: its only form is an object path holding a store hash, which moves with every
pin. With the entry, `-v` reported it used, and Valgrind accepted the file's `#` comments:

```
--4-- used_suppression:      1 guix-glibc-locpath build/try.supp:3 suppressed: 171 bytes in 1 blocks
```

**Every suite, with the entry.** Each ran under ADR-0014's flags and the entry, one at a
time, in 1 min 38 s in all. Every suite exited 0, with 0 bytes definitely lost and 0 errors.
Only the two suites that load libcurl in their own process had anything suppressed:

| Suite | Time | Suppressed |
|---|---|---|
| `test-check-floors` | 8 s | 0 |
| `test-check-seam` | 9 s | 0 |
| `test-collect-safe` | 7 s | 0 |
| `test-conditions` | 6 s | 0 |
| `test-constants` | 7 s | 171 bytes in 1 block |
| `test-curl-testing` | 9 s | 0 |
| `test-discovery` | 7 s | 0 |
| `test-library-loading` | 12 s | 0 |
| `test-load-state` | 6 s | 0 |
| `test-manifest` | 6 s | 0 |
| `test-native` | 6 s | 171 bytes in 1 block |
| `test-require-threaded` | 7 s | 0 |
| `test-verify` | 7 s | 0 |

`make test-memory` later ran the same 13 suites through the recipe in 97 s, all passing.
`make check-memory-gate` takes 41 s.

**The plants.** Each, run plainly, exits 0 and prints its line. Under ADR-0014's flags each
exits 9, with Valgrind's marker:

```
==8== Invalid write of size 1
==8==  Address 0x4c5ac17 is 0 bytes after a block of size 23 alloc'd
==11== 777 bytes in 1 blocks are definitely lost in loss record 2 of 2
```

`tests/memory-load-curl.sps` passes with the entry ("suppressed: 171 bytes in 1 blocks"),
and without it exits 9 on the same block, under `compute_locale_search_path`.

**Options from outside the command line.** With the command exactly as ADR-0014 gives it,
either `VALGRIND_OPTS` or `$HOME/.valgrindrc` naming a suppression of `fun:*` then `...`
hid the planted leak: exit 0, "suppressed: 777 bytes in 1 blocks". Valgrind also reads
`./.valgrindrc` (MG20b below). So test-memory refuses to run while any of the three is
present.

**One entry, many blocks.** The entry matches every block lost under `newlocale`, not just
p11-kit's. A program that loads libcurl, then calls `newlocale` five times for locales glibc
must search for, exited 0 with "suppressed: 1,026 bytes in 6 blocks". A `newlocale` for "C"
loses nothing: glibc answers its static C locale. So in a Guix environment, test-memory fails
a suite that exits 0 with more than one block suppressed, and case d's `more` program loses
exactly two.

**Ctrl-C.** The brief's command has no `--foreground`, so timeout puts itself in a process
group of its own. A SIGINT sent to make's process group, as a terminal's Ctrl-C sends it, 8 s
into a hanging program with `MEMORY_TIMEOUT=40`, did not reach Valgrind. Three seconds later
timeout and Valgrind were still running; make printed the HUNG line at the 40 s cap and only
then exited 130. The same SIGINT to `timeout --foreground 40 valgrind … $CHEZ` ended Valgrind
at once (Chez exited 255). The recipe keeps the brief's command; the slice's records should
choose.

### Red runs

**Before the targets existed:** `tests/check-memory-gate.sh` and the three programs written,
with no `test-memory` or `check-memory-gate` target and no `tests/guix-glibc-locpath.supp`.
The script, run directly in the container, exited 1. Both `a` cases passed, since the plants
already existed (MG17 and MG17b watch them fail); every other case of the 14 it then held
failed by name:

```
check-memory-gate: FAILED b memory-plant-overrun: test-memory names tests/memory-plant-overrun.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
check-memory-gate: FAILED c suppression: tests/guix-glibc-locpath.supp holds exactly one entry, guix-glibc-locpath, a definite leak under compute_locale_search_path
check-memory-gate: FAILED d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block
check-memory-gate: FAILED d needed: without the suppression, the same run fails on the one block lost under compute_locale_search_path
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez
check-memory-gate: FAILED f hangs: a program that never ends is named HUNG
check-memory-gate: FAILED g none: test-memory refuses to pass with no suite
check-memory-gate: FAILED h options: test-memory refuses to run with VALGRIND_OPTS set
check-memory-gate: FAILED h options: test-memory refuses to run with a $HOME/.valgrindrc
```

Each `FAILED` line came with its problems and make's output, for example:

```
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-overrun.sps (exit 9, Valgrind's: an error or a definite leak)
    wanted: test-memory: pass build/check-memory-gate/after.sps
    wanted: test-memory: ran 2, passed 1, failed 1, hung 0
    got:    
  its log: build/memory/memory-plant-overrun.log does not exist
  | make: *** No rule to make target 'test-memory'.  Stop.
```

Two cases came after the targets: `b fails` and `d more`. Each was green when first run, so
MG12 and MG19 are their red runs.

### Mutations

26 cases ran. 24 were killed, each with every expected line present. The other two, MG4b
and MG20b, are controls and passed, as they must: each shows that one rule alone kills the
case before it. MG11, MG20 and MG22 change no gate code. They plant the defect the gate
exists for: a real suite's leak, a `.valgrindrc`, and a wrapper for Chez.

| ID | Change | Killed by |
|---|---|---|
| MG1 | test-memory stops at the first failure | b overrun, b leak, b fails: the suite after the plant never ran |
| MG2 | timeout between Valgrind and Chez | b overrun, b leak (each plant passes), every d, both e (`parent: sh`) |
| MG3 | overrun plant writes inside its block | b overrun: the plant passes, no "Invalid write" |
| MG3b | leak plant frees its block | b leak, d leak: the plant passes, no loss record |
| MG4 | leak plant fails Valgrind for another reason | b leak, d leak: no 777-byte loss record, though the FAIL line matched |
| MG4b | MG4, with the marker checks removed | control: green, so the marker checks alone kill MG4 |
| MG5 | a second suppression entry | c: "holds 2 entries, not one" |
| MG6 | the entry's frame replaced by `...` | c: "has no fun:compute_locale_search_path frame" |
| MG7 | suppression passed outside Guix | e unset (`--suppressions=` in its command), d needed (the run passed) |
| MG8 | suppression never passed | d used, d leak, d more, e set; test-memory FAILs test-constants and test-native |
| MG9 | empty-MEMORY_SUITES check removed | g: "ran 0", exit 0 |
| MG10 | `--errors-for-leak-kinds=definite` dropped | e unset, e set |
| MG11 | a real suite that leaks 555 bytes | test-memory names `tests/test-zz-leak.sps` FAIL with its loss record |
| MG12 | the FAIL excerpt read from no log | b overrun, b leak, b fails: no Valgrind lines in test-memory's output |
| MG13 | VALGRIND_OPTS refusal removed | h VALGRIND_OPTS: the leak plant passed under `fun:*` |
| MG14 | `.valgrindrc` refusal removed | h `$HOME/.valgrindrc`: the leak plant passed |
| MG15 | per-suite timeout dropped | f (the case's own cap fired), both e (`parent: sh`) |
| MG16 | exit-124 branch removed | f: "FAIL … (exit 124)" |
| MG17 | overrun plant exits 1 plainly | a overrun: "it exited 1 without Valgrind" |
| MG17b | leak plant prints a second line | a leak: its output is not the one line |
| MG18 | memory-load-curl never loads libcurl | d used (not used), d needed (passed; "ask whether it is still needed") |
| MG19 | one-block cap removed | d more: passed with 2 blocks suppressed |
| MG20 | `./.valgrindrc` in the tree root | test-memory refuses it |
| MG20b | MG20, with the refusal removed | control: the `.valgrindrc` hid the planted leak, which passed |
| MG21 | `match-leak-kinds: definite,possible` | c: the entry differs |
| MG22 | CHEZ a wrapper script that execs Chez | b overrun, b leak (each plant passes), b fails, every d |

### MG1. test-memory stops at the first failure

**Guards:** test-memory runs every suite, and goes on after a failure.

**Mutation:** In `Makefile`:

```diff
 	    fi; \
-	    failed=$$((failed + 1)); \
+	    failed=$$((failed + 1)); break; \
 	    echo "  log: $$log"; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-overrun: test-memory names tests/memory-plant-overrun.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-overrun.sps (exit 9, Valgrind's: an error or a definite leak)
    wanted: test-memory: pass build/check-memory-gate/after.sps
    wanted: test-memory: ran 2, passed 1, failed 1, hung 0
    got:    test-memory: FAIL tests/memory-plant-overrun.sps (exit 9, Valgrind's: an error or a definite leak)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
  test-memory's own output: no "Invalid write of size 1" in build/check-memory-gate/out
  test-memory's own output: no "0 bytes after a block of size 23 alloc'd" in build/check-memory-gate/out
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
check-memory-gate: FAILED b fails: test-memory names a program that exits 1 FAIL, with its exit and last lines, and runs the suite after it
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
```
(19 more such lines cut.)

### MG2. timeout put between Valgrind and Chez

**Guards:** timeout wraps Valgrind, never sits between it and Chez.

**Mutation:** In `Makefile`:

```diff
 	  echo "=== $$t"; \
-	  $(TIMEOUT) $(MEMORY_TIMEOUT) $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSI [cut: 69 more characters]
+	  $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSION_FILE)) $(TIMEOUT) $(MEMORY [cut: 69 more characters]
 	  rc=$$?; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-overrun: test-memory names tests/memory-plant-overrun.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
  make test-memory exited 0
  make test-memory's lines differ:
    got:    test-memory: pass tests/memory-plant-overrun.sps
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
check-memory-gate: FAILED d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block
check-memory-gate: FAILED d needed: without the suppression, the same run fails on the one block lost under compute_locale_search_path
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez
    got:    parent: sh
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez
```
(96 more such lines cut.)

### MG3. the overrun plant prints its line but writes inside its block

**Guards:** a plant that plants nothing cannot pass check-memory-gate.

**Mutation:** In `tests/memory-plant-overrun.sps`:

```diff
 (let ((block (foreign-alloc size)))
-  (foreign-set! 'unsigned-8 block size 1)
+  (foreign-set! 'unsigned-8 block (- size 1) 1)
   (foreign-free block))
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-overrun: test-memory names tests/memory-plant-overrun.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-overrun.sps (exit 9, Valgrind's: an error or a definite leak)
    wanted: test-memory: pass build/check-memory-gate/after.sps
    wanted: test-memory: ran 2, passed 1, failed 1, hung 0
    got:    test-memory: pass tests/memory-plant-overrun.sps
    got:    test-memory: pass build/check-memory-gate/after.sps
    got:    test-memory: ran 2, passed 2, failed 0, hung 0
  its log: no "Invalid write of size 1" in build/memory/memory-plant-overrun.log
  test-memory's own output: no "Invalid write of size 1" in build/check-memory-gate/out
  its log: no "0 bytes after a block of size 23 alloc'd" in build/memory/memory-plant-overrun.log
```
(3 more such lines cut.)

### MG3b. the leak plant prints its line but frees its block

**Guards:** a plant that plants nothing cannot pass check-memory-gate.

**Mutation:** In `tests/memory-plant-leak.sps`:

```diff
 (import (rnrs)
-        (only (chezscheme) foreign-alloc))
+        (only (chezscheme) foreign-alloc foreign-free))
 
-(foreign-alloc 777)
+(foreign-free (foreign-alloc 777))
 
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 9, Valgrind's: an error or a definite leak)
    wanted: test-memory: pass build/check-memory-gate/after.sps
    wanted: test-memory: ran 2, passed 1, failed 1, hung 0
    got:    test-memory: pass tests/memory-plant-leak.sps
    got:    test-memory: pass build/check-memory-gate/after.sps
    got:    test-memory: ran 2, passed 2, failed 0, hung 0
  its log: no "777 bytes in 1 blocks are definitely lost in loss record" in build/memory/memory-plant-leak.log
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
  the planted leak: no "777 bytes in 1 blocks are definitely lost in loss record" in build/memory/memory-plant-leak.log
```
(9 more such lines cut.)

### MG4. the leak plant fails Valgrind for another reason: it overruns its block, and frees it

**Guards:** test-memory must fail on the planted defect itself, with its marker, not on any error.

**Mutation:** In `tests/memory-plant-leak.sps`:

```diff
 (import (rnrs)
-        (only (chezscheme) foreign-alloc))
+        (only (chezscheme) foreign-alloc foreign-set! foreign-free))
 
-(foreign-alloc 777)
+(let ((block (foreign-alloc 777))) (foreign-set! 'unsigned-8 block 777 1) (foreign-free block))
 
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
  its log: no "777 bytes in 1 blocks are definitely lost in loss record" in build/memory/memory-plant-leak.log
  test-memory's own output: no "777 bytes in 1 blocks are definitely lost in loss record" in build/check-memory-gate/out
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
  the planted leak: no "777 bytes in 1 blocks are definitely lost in loss record" in build/memory/memory-plant-leak.log
```

### MG4b. MG4's plant, and check-memory-gate's marker checks removed (the control)

**Guards:** the marker checks alone kill MG4.

**Mutation:** In `tests/check-memory-gate.sh`:

```diff
   while IFS= read -r m; do
-    want_in "$log" "$m" "its log"
-    want_in "$out" "$m" "test-memory's own output"
+    :
   done <<EOF
...
   want_in "$log" "Reading suppressions file: $supp" "the suppression read"
-  want_in "$log" "777 bytes in 1 blocks are definitely lost in loss record" "the planted leak"
   verdict "d leak: the leak plant fails with the suppression read"
```

**Mutation:** In `tests/memory-plant-leak.sps`:

```diff
 (import (rnrs)
-        (only (chezscheme) foreign-alloc))
+        (only (chezscheme) foreign-alloc foreign-set! foreign-free))
 
-(foreign-alloc 777)
+(let ((block (foreign-alloc 777))) (foreign-set! 'unsigned-8 block 777 1) (foreign-free block))
 
```

**Result:** as expected, exit 0:

```
check-memory-gate: ok b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
check-memory-gate: ok d leak: the leak plant fails with the suppression read
check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 16 cases
```

### MG5. a second suppression entry

**Guards:** the file holds exactly one entry.

**Mutation:** In `tests/guix-glibc-locpath.supp`:

```diff
 }
+{
+   guix-glibc-locpath-malloc
+   Memcheck:Leak
+   match-leak-kinds: definite
+   fun:malloc
+   fun:argz_add_sep
+   fun:compute_locale_search_path
+   fun:newlocale
+}
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED c suppression: tests/guix-glibc-locpath.supp holds exactly one entry, guix-glibc-locpath, a definite leak under compute_locale_search_path
  tests/guix-glibc-locpath.supp holds 2 entries, not one
  tests/guix-glibc-locpath.supp's entry is not exactly the one ADR-0014 allows:
    wanted: {
    wanted: guix-glibc-locpath
    wanted: Memcheck:Leak
    wanted: match-leak-kinds: definite
    wanted: fun:realloc
    wanted: fun:argz_add_sep
    wanted: fun:compute_locale_search_path
    wanted: fun:newlocale
    wanted: }
```
(18 more such lines cut.)

### MG6. the suppression broadened: its compute_locale_search_path frame replaced by ...

**Guards:** the entry keeps its compute_locale_search_path frame, and no broader match.

**Mutation:** In `tests/guix-glibc-locpath.supp`:

```diff
    fun:argz_add_sep
-   fun:compute_locale_search_path
+   ...
    fun:newlocale
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED c suppression: tests/guix-glibc-locpath.supp holds exactly one entry, guix-glibc-locpath, a definite leak under compute_locale_search_path
  tests/guix-glibc-locpath.supp has no fun:compute_locale_search_path frame
  tests/guix-glibc-locpath.supp's entry is not exactly the one ADR-0014 allows:
    wanted: {
    wanted: guix-glibc-locpath
    wanted: Memcheck:Leak
    wanted: match-leak-kinds: definite
    wanted: fun:realloc
    wanted: fun:argz_add_sep
    wanted: fun:compute_locale_search_path
    wanted: fun:newlocale
    got:    ...
```
(9 more such lines cut.)

### MG7. the suppression passed outside Guix: the GUIX_ENVIRONMENT condition dropped

**Guards:** no suppression with GUIX_ENVIRONMENT unset, as in CI.

**Mutation:** In `Makefile`:

```diff
 	  echo "=== $$t"; \
-	  $(TIMEOUT) $(MEMORY_TIMEOUT) $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSI [cut: 69 more characters]
+	  $(TIMEOUT) $(MEMORY_TIMEOUT) $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite --suppressions=$(MEMORY_SUPPRESSION_FILE) $(CHEZ) --libdir [cut: 43 more characters]
 	  rc=$$?; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d needed: without the suppression, the same run fails on the one block lost under compute_locale_search_path
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-load-curl.sps (exit 9, Valgrind's: an error or a definite leak)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass tests/memory-load-curl.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
  the run did not lose exactly one block: ==4248==    definitely lost: 0 bytes in 0 blocks
  no lost block was allocated under compute_locale_search_path, so the leak the suppression covers is gone, or moved: ask whether it is still needed
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez
  the stand-in for Valgrind was handed another command:
    got:    --suppressions=tests/guix-glibc-locpath.supp
```
(20 more such lines cut.)

### MG8. the suppression never passed

**Guards:** the container passes the suppression, and it is used.

**Mutation:** In `Makefile`:

```diff
 	  echo "=== $$t"; \
-	  $(TIMEOUT) $(MEMORY_TIMEOUT) $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSI [cut: 69 more characters]
+	  $(TIMEOUT) $(MEMORY_TIMEOUT) $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(CHEZ) --libdirs $(LIBDIRS) --program $$t >"$$log" 2>&1;  [cut: 1 more characters]
 	  rc=$$?; \
```

**Command** in the container: `make check-memory-gate`, then `make test-memory MEMORY_SUITES="tests/test-constants.sps tests/test-native.sps"`; the exit status is check-memory-gate's.

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block
  make test-memory exited 2, not 0
  make test-memory's lines differ:
    wanted: test-memory: pass tests/memory-load-curl.sps
    wanted: test-memory: ran 1, passed 1, failed 0, hung 0
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez
test-memory: FAIL tests/test-constants.sps (exit 9, Valgrind's: an error or a definite leak)
test-memory: FAIL tests/test-native.sps (exit 9, Valgrind's: an error or a definite leak)
test-memory: ran 2, passed 0, failed 2, hung 0
direct: test-memory exit 2
```
(69 more such lines cut.)

### MG9. test-memory's empty-MEMORY_SUITES check removed

**Guards:** test-memory fails when no suite ran.

**Mutation:** In `Makefile`:

```diff
 	@scripts/require-tools "$(GOAL)" $(firstword $(VALGRIND)) $(TIMEOUT) $(CHEZ)
-	@if [ -z "$(strip $(MEMORY_SUITES))" ]; then \
-	  echo "test-memory: no suites: MEMORY_SUITES is empty" >&2; \
-	  exit 1; \
-	fi; \
-	if [ -n "$${VALGRIND_OPTS:-}" ]; then \
+	@if [ -n "$${VALGRIND_OPTS:-}" ]; then \
 	  echo "test-memory: VALGRIND_OPTS is set ($$VALGRIND_OPTS): Valgrind would add it to the gate's options; unset it (ADR-0014)" >&2; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED g none: test-memory refuses to pass with no suite
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: no suites: MEMORY_SUITES is empty
    got:    test-memory: ran 0, passed 0, failed 0, hung 0
```

### MG10. --errors-for-leak-kinds=definite dropped

**Guards:** the command is ADR-0014's, whole.

**Mutation:** In `Makefile`:

```diff
 	  echo "=== $$t"; \
-	  $(TIMEOUT) $(MEMORY_TIMEOUT) $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSI [cut: 69 more characters]
+	  $(TIMEOUT) $(MEMORY_TIMEOUT) $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSION_FILE)) $(CHEZ) --libdirs $(LIB [cut: 36 more characters]
 	  rc=$$?; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez
  the stand-in for Valgrind was handed another command:
    wanted: parent: timeout
    wanted: --error-exitcode=9
    wanted: --leak-check=full
    wanted: --show-leak-kinds=definite
    wanted: --errors-for-leak-kinds=definite
    wanted: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/scheme
    wanted: --libdirs
    wanted: src:tests:build/scheme-libs
    wanted: --program
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez
```
(32 more such lines cut.)

### MG11. a suite with a real definite leak, beside test-native, run by plain make test-memory

**Guards:** test-memory fails any suite with a definite leak, from the default MEMORY_SUITES.

**Removed:** `tests/test-check-floors.sps`, `tests/test-check-seam.sps`, `tests/test-collect-safe.sps`, `tests/test-conditions.sps`, `tests/test-constants.sps`, `tests/test-curl-testing.sps`, `tests/test-discovery.sps`, `tests/test-library-loading.sps`, `tests/test-load-state.sps`, `tests/test-manifest.sps`, `tests/test-require-threaded.sps`, `tests/test-verify.sps`.

**Mutation:** In `tests/test-zz-leak.sps`:

```diff
+#!r6rs
+;;; Written for mutation MG11: a suite with a passing test and a real
+;;; definite leak, a 555-byte foreign block whose address it drops.
+(import (rnrs) (srfi :64) (only (chezscheme) foreign-alloc) (curl-testing))
+(define runner (test-runner-simple))
+(test-runner-current runner)
+(test-begin "zz-leak")
+(foreign-alloc 555)
+(test-assert "passes, so only the leak can fail this suite" #t)
+(test-end "zz-leak")
+(exit (suite-exit-status runner))
```

**Command** in the container: `make test-memory`, with its default MEMORY_SUITES.

**Result:** killed, exit 2:

```
test-memory: pass tests/test-native.sps
test-memory: FAIL tests/test-zz-leak.sps (exit 9, Valgrind's: an error or a definite leak)
  log: build/memory/test-zz-leak.log
  ==864== 555 bytes in 1 blocks are definitely lost in loss record 2 of 2
  ==864==    at 0x4845772: malloc (in /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.27.0/libexec/valgrind/vgpreload_memcheck-amd64-linux.so)
  ==864==    by 0x4AC678: s_malloc (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==864==    by 0x721CC59: ???
  ==864==    by 0x4C5AA8F: ???
  ==864==    by 0x416B51: S_call_help (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==864==    by 0x41850F: boot_call (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
  ==864==    by 0x4187F0: run_script (in /gnu/store/nrlh72nrgyna5mm3p2n62mmld6al0lwv-chez-scheme-10.4.0/lib/csv10.4.0/ta6le/scheme)
test-memory: ran 2, passed 1, failed 1, hung 0
```
(4 more such lines cut.)

### MG12. test-memory's FAIL excerpt read from no log

**Guards:** a FAIL prints Valgrind's verdict lines, so a CI log says why.

**Mutation:** In `Makefile`:

```diff
 	            if (summary != "") print "  " summary; \
-	            else print "  (the log holds no Valgrind ERROR SUMMARY)" }' "$$log"; \
+	            else print "  (the log holds no Valgrind ERROR SUMMARY)" }' /dev/null; \
 	    if [ $$rc -ne 9 ]; then \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-overrun: test-memory names tests/memory-plant-overrun.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
  test-memory's own output: no "Invalid write of size 1" in build/check-memory-gate/out
  test-memory's own output: no "0 bytes after a block of size 23 alloc'd" in build/check-memory-gate/out
  test-memory's own output: no "ERROR SUMMARY: 1 errors from 1 contexts" in build/check-memory-gate/out
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
  test-memory's own output: no "777 bytes in 1 blocks are definitely lost in loss record" in build/check-memory-gate/out
  test-memory's own output: no "ERROR SUMMARY: 1 errors from 1 contexts" in build/check-memory-gate/out
check-memory-gate: FAILED b fails: test-memory names a program that exits 1 FAIL, with its exit and last lines, and runs the suite after it
  test-memory's own output, Valgrind's verdict: no "ERROR SUMMARY: 0 errors from 0 contexts" in build/check-memory-gate/out
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
  test-memory's own output, the suppressed total: no " bytes in 2 blocks" in build/check-memory-gate/out
```

### MG13. test-memory's VALGRIND_OPTS refusal removed

**Guards:** no options reach Valgrind but its command line: VALGRIND_OPTS.

**Mutation:** In `Makefile`:

```diff
 	fi; \
-	if [ -n "$${VALGRIND_OPTS:-}" ]; then \
-	  echo "test-memory: VALGRIND_OPTS is set ($$VALGRIND_OPTS): Valgrind would add it to the gate's options; unset it (ADR-0014)" >&2; \
-	  exit 1; \
-	fi; \
 	for rc in $${HOME:+"$$HOME/.valgrindrc"} ./.valgrindrc; do \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED h options: test-memory refuses to run with VALGRIND_OPTS set
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: VALGRIND_OPTS is set (--suppressions=build/check-memory-gate/everything.supp): Valgrind would add it to the gate's options; unset it (ADR-0014)
    got:    test-memory: pass tests/memory-plant-leak.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
  the leak plant ran
```

### MG14. test-memory's .valgrindrc refusal removed

**Guards:** no options reach Valgrind but its command line: $HOME/.valgrindrc.

**Mutation:** In `Makefile`:

```diff
 	fi; \
-	for rc in $${HOME:+"$$HOME/.valgrindrc"} ./.valgrindrc; do \
-	  if [ -e "$$rc" ]; then \
-	    echo "test-memory: $$rc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)" >&2; \
-	    exit 1; \
-	  fi; \
-	done; \
 	mkdir -p $(MEMORY_LOGS); \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED h options: test-memory refuses to run with a $HOME/.valgrindrc
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: …/slice5/M/runs/MG14/build/check-memory-gate/home/.valgrindrc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)
    got:    test-memory: pass tests/memory-plant-leak.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
  the leak plant ran
```

### MG15. the per-suite timeout dropped

**Guards:** every suite runs under timeout, which names a hang.

**Mutation:** In `Makefile`:

```diff
 	  echo "=== $$t"; \
-	  $(TIMEOUT) $(MEMORY_TIMEOUT) $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSI [cut: 69 more characters]
+	  $(VALGRIND) --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSION_FILE)) $(CHEZ) --libdirs $ [cut: 40 more characters]
 	  rc=$$?; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez
  the stand-in for Valgrind was handed another command:
    wanted: parent: timeout
    wanted: --error-exitcode=9
    wanted: --leak-check=full
    wanted: --show-leak-kinds=definite
    wanted: --errors-for-leak-kinds=definite
    wanted: /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/scheme
    got:    parent: sh
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez
check-memory-gate: FAILED f hangs: a program that never ends is named HUNG
  make test-memory did not finish within its cap, so no per-suite timeout stopped it
```
(40 more such lines cut.)

### MG16. a hang reported as FAIL: the exit-124 branch removed

**Guards:** a hang is named HUNG.

**Mutation:** In `Makefile`:

```diff
 	    echo "test-memory: pass $$t"; passed=$$((passed + 1)); \
-	  elif [ $$rc -eq 124 ]; then \
-	    echo "test-memory: HUNG $$t (no exit within $(MEMORY_TIMEOUT)s)"; hung=$$((hung + 1)); \
 	  else \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED f hangs: a program that never ends is named HUNG
  make test-memory's lines differ:
    wanted: test-memory: HUNG build/check-memory-gate/hangs.sps (no exit within 15s)
    wanted: test-memory: ran 1, passed 0, failed 0, hung 1
    got:    test-memory: FAIL build/check-memory-gate/hangs.sps (exit 124)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
```

### MG17. the overrun plant exits 1 when run plainly

**Guards:** a plant exits 0 without Valgrind.

**Mutation:** In `tests/memory-plant-overrun.sps`:

```diff
 (newline)
-(exit 0)
+(exit 1)
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED a plain: tests/memory-plant-overrun.sps exits 0 without Valgrind, and prints only its line
  it exited 1 without Valgrind
```

### MG17b. the leak plant prints a second line

**Guards:** a plant prints only its line.

**Mutation:** In `tests/memory-plant-leak.sps`:

```diff
 (newline)
+(display "and more")
+(newline)
 (exit 0)
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED a plain: tests/memory-plant-leak.sps exits 0 without Valgrind, and prints only its line
  its output, without Valgrind, is not the one line "memory-plant-leak: planted a 777-byte foreign block that nothing frees or holds":
    | memory-plant-leak: planted a 777-byte foreign block that nothing frees or holds
    | and more
```

### MG18. memory-load-curl prints its line without loading libcurl, as if Guix had fixed the leak

**Guards:** the suppression is used, and needed: a stale entry fails.

**Mutation:** In `tests/memory-load-curl.sps`:

```diff
 
-(let ((info (loaded-libcurl)))
-  (display "memory-load-curl: loaded libcurl ")
-  (display (libcurl-info-version info))
-  (display " from ")
-  (display (libcurl-info-path info))
-  (newline))
+(display "memory-load-curl: loaded libcurl ")
+(newline)
 (exit 0)
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block
  -v does not report guix-glibc-locpath used, once, on one block, in build/memory/memory-load-curl.log:
  
check-memory-gate: FAILED d needed: without the suppression, the same run fails on the one block lost under compute_locale_search_path
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-load-curl.sps (exit 9, Valgrind's: an error or a definite leak)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass tests/memory-load-curl.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
  the run did not lose exactly one block: ==4254==    definitely lost: 0 bytes in 0 blocks
  no lost block was allocated under compute_locale_search_path, so the leak the suppression covers is gone, or moved: ask whether it is still needed
```

### MG19. test-memory's one-block cap removed

**Guards:** the entry hides one block, no more.

**Mutation:** In `Makefile`:

```diff
 	  fi; \
-	  if [ $$rc -eq 0 ] && [ "$${blocks:-0}" -le 1 ]; then \
+	  if [ $$rc -eq 0 ]; then \
 	    echo "test-memory: pass $$t"; passed=$$((passed + 1)); \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/more.sps (exit 0, but Valgrind suppressed 2 blocks, and guix-glibc-locpath covers one)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass build/check-memory-gate/more.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
  test-memory's own output, the program's last lines: no "more: newlocale answered 0" in build/check-memory-gate/out
  test-memory's own output, the suppressed total: no " bytes in 2 blocks" in build/check-memory-gate/out
```

### MG20. a .valgrindrc in the tree root naming a suppression that matches every leak

**Guards:** test-memory refuses ./.valgrindrc, which hid the planted leak in a probe.

**Command** in the container: write `.valgrindrc` in the copy's root, naming `build/everything.supp`, a suppression matching every definite leak (`fun:*` then `...`), then `make test-memory MEMORY_SUITES=tests/memory-plant-leak.sps`.

**Result:** killed, exit 2:

```
test-memory: ./.valgrindrc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)
```

### MG20b. MG20's .valgrindrc, and test-memory's .valgrindrc refusal removed (the control)

**Guards:** the refusal alone stops it: the .valgrindrc hides the planted leak.

**Mutation:** In `Makefile`:

```diff
 	fi; \
-	for rc in $${HOME:+"$$HOME/.valgrindrc"} ./.valgrindrc; do \
-	  if [ -e "$$rc" ]; then \
-	    echo "test-memory: $$rc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)" >&2; \
-	    exit 1; \
-	  fi; \
-	done; \
 	mkdir -p $(MEMORY_LOGS); \
```

**Command** in the container: write `.valgrindrc` in the copy's root, naming `build/everything.supp`, a suppression matching every definite leak (`fun:*` then `...`), then `make test-memory MEMORY_SUITES=tests/memory-plant-leak.sps`.

**Result:** as expected, exit 0:

```
test-memory: pass tests/memory-plant-leak.sps
test-memory: ran 1, passed 1, failed 0, hung 0
```

### MG21. the suppression matches possibly-lost blocks too: match-leak-kinds: definite,possible

**Guards:** the entry is exactly the one ADR-0014 allows: no broader leak kind.

**Mutation:** In `tests/guix-glibc-locpath.supp`:

```diff
    Memcheck:Leak
-   match-leak-kinds: definite
+   match-leak-kinds: definite,possible
    fun:realloc
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED c suppression: tests/guix-glibc-locpath.supp holds exactly one entry, guix-glibc-locpath, a definite leak under compute_locale_search_path
  tests/guix-glibc-locpath.supp's entry is not exactly the one ADR-0014 allows:
    wanted: {
    wanted: guix-glibc-locpath
    wanted: Memcheck:Leak
    wanted: match-leak-kinds: definite
    wanted: fun:realloc
    wanted: fun:argz_add_sep
    wanted: fun:compute_locale_search_path
    wanted: fun:newlocale
    wanted: }
    got:    match-leak-kinds: definite,possible
```
(8 more such lines cut.)

### MG22. CHEZ pointed at a wrapper script that execs the real binary

**Guards:** Valgrind checks Chez itself: a wrapper hides it (AGENTS.md).

**Command** in the container: write `build/chez-wrapper`, a shell script that execs `$REAL_CHEZ`, then `REAL_CHEZ=$CHEZ make check-memory-gate CHEZ=build/chez-wrapper`.

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-overrun: test-memory names tests/memory-plant-overrun.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-overrun.sps (exit 9, Valgrind's: an error or a definite leak)
    got:    test-memory: pass tests/memory-plant-overrun.sps
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
    got:    test-memory: pass tests/memory-plant-leak.sps
check-memory-gate: FAILED b fails: test-memory names a program that exits 1 FAIL, with its exit and last lines, and runs the suite after it
check-memory-gate: FAILED d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block
check-memory-gate: FAILED d needed: without the suppression, the same run fails on the one block lost under compute_locale_search_path
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
```
(48 more such lines cut.)

### Clean rerun

After every mutation, on the working tree itself, which `diff -r` showed byte-identical to the
snapshot. `make check-help` passed on the host. In the container, `make test-memory`,
`make check-memory-gate`, the same with `GUIX_ENVIRONMENT` unset, `make test` and
`make check-test-fails` each exited 0. Their verdict lines:

```
test-memory: ran 13, passed 13, failed 0, hung 0
check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 16 cases
check-memory-gate: skipped d: GUIX_ENVIRONMENT is unset, so test-memory passes no suppression here, and there is none to hold
check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 12 cases
test: ran 13, passed 13, failed 0, hung 0
check-test-fails: make test failed, as it must, in all 10 cases
```

No Valgrind or hanging Chez process was left running afterwards.

## CI

Evidence for the checks M0 slice 5's CI part added ([harness plan](2026-10-04-harness-plan.md)
§3 item 6 and §4; [ADR-0001](decisions/0001-bind-libcurl-directly.md),
[ADR-0003](decisions/0003-libcurl-floor-7-85.md), [ADR-0014](decisions/0014-valgrind-memory-gate.md),
[ADR-0016](decisions/0016-floors-have-one-source.md)). The part is:

- `.github/workflows/ci.yml`, new: the main, floor, floor-disabled-apis and nothreads jobs, the memory
  decision and the memory gate, all on `ubuntu-24.04`;
- `scripts/ci/build-chez.sh` and `scripts/ci/build-curl.sh`, new: a release tarball, checked against a
  pinned sha256, built and installed into a prefix;
- `tests/check-nothreads.sps` and `make check-nothreads`, new: every public library under `src/` must
  be refused, by name, on the Chez that runs it. `tests/test-check-nothreads.sps` and
  `tests/fixtures/nothreads/` hold each rule;
- the workflow rules of `(floors)` (`workflow-problems`, and `check-floors` taking the workflow's text),
  the third argument of `tests/check-floors.sps` and `make check-floors`, the new rows of
  `tests/test-check-floors.sps`, and a `ci.yml` in each `tests/fixtures/floors/` case;
- `packaging/debian-prereqs.txt`, which gained the packages the build scripts need.

Only the third and fourth items are mutated here: the workflow runs only on GitHub, and the build
scripts build Chez and curl. The workflow is held by `make check-floors` (its two env lines, and no other
line that writes a floor, which CF1 to CF6 mutate) and by actionlint, and the scripts by shellcheck; the
CI part's report records those runs, and what only CI's first run can show.

A driver in the session scratchpad ran every mutation. It froze a snapshot of the working tree, without
`.git` or `build/`, and gave each mutation a fresh copy of it. It applied the mutation by exact-text
replacement, aborting unless the target occurred exactly once, and refused a mutation whose diff was
empty. It touched the copy's `manifest.scm` (`traps.md`, the stale `guix shell -m` profile) and ran the
command through the copy's own `scripts/guix-env`, so the container saw only that copy. The working tree
was never edited. A mutation counts as killed only when the command exits non-zero and every expected
line appears whole in its output: the case's `FAIL <test name>` lines, with their expected and actual
values, and `test: FAIL <suite> (exit 1)`, or, for CF1 to CF6, the `check-floors:` lines `make test`
prints before it runs any suite, or `check-help`'s own line for H1 and H2.

The command is `make test`, except where a mutation of `(floors)` or `tests/check-floors.sps` could
make `check-floors`, which `make test` runs first, stop it before any suite. Those run `make test` and
then `tests/test-check-floors.sps` directly, and print `direct: test-check-floors exit N`. The exit
status judged is always `make test`'s (or `make check-help`'s).

**Result** quotes at most 12 output lines per run: the first line each expectation matches (a `FAIL` with
its expected and actual lines), then other `FAIL` lines with theirs, then `check-`, `test: FAIL`, `direct:`
and `make:` lines in output order. It says how many wanted lines were cut. A diff keeps one line of context,
and `...` sets its hunks apart. A diff line longer than 200 characters, and an output line longer than 240, is
cut, and says how much was cut.

Cases are named `NT` (`check-nothreads`), `FX` (that suite's own guards), `FL` (the workflow rules in
`(floors)`), `PF` (the program `check-floors.sps`), `CF` (the real workflow, under `make check-floors`)
and `H` (`make help` and `check-help`).

### Red runs

**R1, the suite before the program.** `tests/test-check-nothreads.sps` and the fixture trees were
written first. There was no `tests/check-nothreads.sps`. Chez answered every spawn with `no such
file or directory` (exit 255), 14 tests failed and the 3 that guard the suite itself passed:

```
FAIL refusing: every public library imports the refusal, which refuses; a private library that would load is not imported
  expected: (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl unsupported) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
  actual:   (255 "" "Exception in load-program: failed for tests/check-nothreads.sps: no such file or directory\n")
FAIL src/: on a threaded Chez nothing is refused, so the program names every public library it could import
  expected: (1 "" "check-nothreads: (curl) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (255 "" "Exception in load-program: failed for tests/check-nothreads.sps: no such file or directory\n")
# of expected passes      3
# of unexpected failures  14
suite-exit-status: exit 1 (pass 3, fail 14, xpass 0): a suite needs a pass, and no fail or xpass
```

**R2, the program on the real tree.** With the program written, `make check-nothreads` on this
threaded Chez, where every import loads, failed and named `(curl)`. That is its red run on the real
`src/` and the reason `make test` does not run it. `make` exited 2:

```
check-nothreads: (curl) loaded, but a non-threaded Chez must refuse it
check-nothreads: FAILED (problems: 1)
make: *** [Makefile:270: check-nothreads] Error 1
exit 2
```

**R3, the floors suite against a stub.** The workflow rows, the program rows and the `ci.yml`
fixtures were written, and `(floors)` stubbed: `workflow-problems` answering the empty list,
`check-floors` taking six arguments, and `tests/check-floors.sps` as it was, taking two. 39 tests
failed and 169 passed. The existing program cases are among the failures: they pass three arguments
to a program that takes two. A first draft of the run died at top level, `2 is not a string`, with
no test named: the helper that builds a line number was given a number. It was corrected before this
run:

```
FAIL workflow: the Chez line twice
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 2 times, but must appear once"))
  actual:   (returned ())
FAIL workflow-literal: the workflow writes the libcurl floor in a step, where only its env line may
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-literal/ci.yml: line 13 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" may write; refer to ${{ env.CURL_FLOOR_VERSION }}\ncheck-f [cut: 31 more characters]
  actual:   (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README\n")
# of expected passes      169
# of unexpected failures  39
suite-exit-status: exit 1 (pass 169, fail 39, xpass 0): a suite needs a pass, and no fail or xpass
```

### Baseline

Everything written. The snapshot every mutation copied is byte-identical to the working tree at the clean rerun. `make test` exited 0, with 17 tests passing in `test-check-nothreads` and 211 in `test-check-floors`:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows/ci.yml hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
# of expected passes      211
test: pass tests/test-check-floors.sps
# of expected passes      17
test: pass tests/test-check-nothreads.sps
test: ran 14, passed 14, failed 0, hung 0
make test exit 0
```
(24 more lines cut: the other suites' counts and `test: pass` lines.)

### Mutations

42 mutations ran, and all 42 were killed, each with every expected line present. The two suites the part added or extended failed only under the cases that name them: `test-check-floors` under FL1, FL2, FL3, FL4, FL5, FL6, FL7, FL8, FL9, PF1, PF2, PF3, PF3b, PF4; `test-check-nothreads` under NT1, NT1b, NT2, NT3, NT3a, NT3b, NT3c, NT4, NT5, NT6, NT7, NT8, NT9, NT10, NT11, NT11b, FX1, FX2. `make test` stopped at `check-floors`, before any suite, under CF1, CF2, CF3a, CF3b, CF4, CF5, CF6, which mutate the real workflow.

### NT1. the program skips the first public library

**Guards:** every public library is imported, none left out.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
         (library-directories (list root))
-        (let* ((verdicts (map (lambda (name) (cons name (import-verdict name))) names))
+        (let* ((verdicts (map (lambda (name) (cons name (import-verdict name))) (if (pair? names) (cdr names) names)))
                (problems
```

**Result:** killed, exit 2:

```
FAIL refusing: every public library imports the refusal, which refuses; a private library that would load is not imported
  expected: (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl unsupported) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
  actual:   (0 "check-nothreads: (curl unsupported) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
FAIL mixed: one public library does not import the refusal: it loads, and is named, and the others are still refused
  expected: (1 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (1 "check-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
FAIL src/: on a threaded Chez nothing is refused, so the program names every public library it could import
  expected: (1 "" "check-nothreads: (curl) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```
(18 more such lines cut.)

### NT1b. the program skips the last public library

**Guards:** every public library is imported, none left out.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
         (library-directories (list root))
-        (let* ((verdicts (map (lambda (name) (cons name (import-verdict name))) names))
+        (let* ((verdicts (map (lambda (name) (cons name (import-verdict name))) (if (pair? names) (reverse (cdr (reverse names))) names)))
                (problems
```

**Result:** killed, exit 2:

```
FAIL refusing: every public library imports the refusal, which refuses; a private library that would load is not imported
  expected: (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl unsupported) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
  actual:   (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl unsupported) is refused by name\n" "")
FAIL mixed: one public library does not import the refusal: it loads, and is named, and the others are still refused
  expected: (1 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (1 "check-nothreads: (curl) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
FAIL src/: on a threaded Chez nothing is refused, so the program names every public library it could import
  expected: (1 "" "check-nothreads: (curl) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```
(18 more such lines cut.)

### NT2. the program passes when it finds no public library

**Guards:** a check that finds nothing fails, so an empty or wrong directory is no pass.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
                              reads))
-                 (if (null? names)
-                     (list (string-append "no public library under " root
-                                          ", so there is nothing to refuse"))
-                     '())
+                 '()
                  (apply append
```

**Result:** killed, exit 2:

```
FAIL private-only: private libraries alone: the program imports none, so it has nothing to refuse
  expected: (1 "" "check-nothreads: no public library under tests/fixtures/nothreads/private-only, so there is nothing to refuse\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "" "")
FAIL empty: a tree with no library source in it
  expected: (1 "" "check-nothreads: no public library under tests/fixtures/nothreads/empty, so there is nothing to refuse\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "" "")
FAIL a directory that does not exist holds no public library
  expected: (1 "" "check-nothreads: no public library under tests/fixtures/nothreads/no-such-tree, so there is nothing to refuse\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### NT3. the program takes any raise for the refusal

**Guards:** only the refusal, by name, counts as a refusal.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
 (define (refusal? e)
-  (and (syntax-violation? e)
-       (who-condition? e)
-       (eq? (condition-who e) refusal-who)
-       (message-condition? e)
-       (starts-with? refusal-marker (condition-message e))))
+  #t)
 
```

**Result:** killed, exit 2:

```
FAIL raises-other: the refusal raises, but a plain error, not the refusal
  expected: (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in fixture: boom\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
FAIL wrong-message: a syntax violation from chez-curl whose message is not the threads refusal's
  expected: (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0 (refuse) at line 13, char 3 of tests/fixtures/nothreads/wrong-me [cut: 82 more characters]
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
FAIL wrong-who: the threads refusal's message in a syntax violation from someone else
  expected: (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in someone-else: chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one (refuse) at line 13, char 3 of tests/fixtures/nothreads [cut: 87 more characters]
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
FAIL not-syntax: the threads refusal's who and message in an assertion violation, not a syntax violation
  expected: (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in chez-curl: chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
```
(2 more such lines cut.)

### NT3a. the program does not require a syntax violation

**Guards:** the refusal is a syntax violation, raised at expansion.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
 (define (refusal? e)
-  (and (syntax-violation? e)
-       (who-condition? e)
+  (and (who-condition? e)
        (eq? (condition-who e) refusal-who)
```

**Result:** killed, exit 2:

```
FAIL not-syntax: the threads refusal's who and message in an assertion violation, not a syntax violation
  expected: (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in chez-curl: chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### NT3b. the program does not require who chez-curl

**Guards:** the refusal comes from chez-curl.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
        (who-condition? e)
-       (eq? (condition-who e) refusal-who)
        (message-condition? e)
```

**Result:** killed, exit 2:

```
FAIL wrong-who: the threads refusal's message in a syntax violation from someone else
  expected: (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in someone-else: chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one (refuse) at line 13, char 3 of tests/fixtures/nothreads [cut: 87 more characters]
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### NT3c. the program does not require the marker

**Guards:** the refusal is the threads refusal: its message starts with the marker.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
        (message-condition? e)
-       (starts-with? refusal-marker (condition-message e))))
+       #t))
 
```

**Result:** killed, exit 2:

```
FAIL wrong-message: a syntax violation from chez-curl whose message is not the threads refusal's
  expected: (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in chez-curl: chez-curl needs Chez Scheme 10.4.0 or later, and this one is 10.3.0 (refuse) at line 13, char 3 of tests/fixtures/nothreads/wrong-me [cut: 82 more characters]
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### NT4. the program lets a library that loaded pass

**Guards:** a library that loads on a Chez without threads fails the check.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
                                    ((eq? what 'refused) '())
-                                   ((eq? what 'loaded)
-                                    (list (string-append name " loaded, but a non-threaded"
-                                                         " Chez must refuse it")))
+                                   ((eq? what 'loaded) '())
                                    (else
```

**Result:** killed, exit 2:

```
FAIL mixed: one public library does not import the refusal: it loads, and is named, and the others are still refused
  expected: (1 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
FAIL src/: on a threaded Chez nothing is refused, so the program names every public library it could import
  expected: (1 "" "check-nothreads: (curl) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### NT5. the program imports private libraries too

**Guards:** only public libraries are imported.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
 (define (public? name)
-  (not (memq 'private name)))
+  #t)
 
```

**Result:** killed, exit 2:

```
FAIL refusing: every public library imports the refusal, which refuses; a private library that would load is not imported
  expected: (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl unsupported) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
  actual:   (1 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl private require-threaded) is refused by name\ncheck-nothreads: (curl unsupported) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "c [cut: 127 more characters]
FAIL mixed: one public library does not import the refusal: it loads, and is named, and the others are still refused
  expected: (1 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (1 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl private require-threaded) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl private helper) loaded, but a non- [cut: 155 more characters]
FAIL private-only: private libraries alone: the program imports none, so it has nothing to refuse
  expected: (1 "" "check-nothreads: no public library under tests/fixtures/nothreads/private-only, so there is nothing to refuse\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (1 "check-nothreads: (curl private require-threaded) is refused by name\n" "check-nothreads: (curl private helper) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```
(21 more such lines cut.)

### NT6. the program scans the top directory only

**Guards:** libraries are found at any depth.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
             ((file-directory? path #f)
-             (let ((below (walk path)))
-               (loop (cdr names)
-                     (append (car below) files)
-                     (append (cadr below) links))))
+             (loop (cdr names) files links))
             ((file-directory? path)
```

**Result:** killed, exit 2:

```
FAIL refusing: every public library imports the refusal, which refuses; a private library that would load is not imported
  expected: (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl unsupported) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
  actual:   (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
FAIL mixed: one public library does not import the refusal: it loads, and is named, and the others are still refused
  expected: (1 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
FAIL unreadable: a source that cannot be read as data is named, and the libraries beside it are still checked
  expected: (1 "check-nothreads: (curl) is refused by name\n" "check-nothreads: tests/fixtures/nothreads/unreadable/curl/broken.sls: it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 48 o [cut: 147 more characters]
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### NT7. the program does not put the directory on the library path

**Guards:** one argument says both where to look and where Chez finds the libraries.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
                                 reads))))
-        (library-directories (list root))
         (let* ((verdicts (map (lambda (name) (cons name (import-verdict name))) names))
```

**Result:** killed, exit 2:

```
FAIL refusing: every public library imports the refusal, which refuses; a private library that would load is not imported
  expected: (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl unsupported) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
  actual:   (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in environment: library (curl) not found\ncheck-nothreads: (curl unsupported) raised something other than the refusal: Exception in environment: l [cut: 209 more characters]
FAIL mixed: one public library does not import the refusal: it loads, and is named, and the others are still refused
  expected: (1 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in environment: library (curl) not found\ncheck-nothreads: (curl unsupported) raised something other than the refusal: Exception in environment: l [cut: 209 more characters]
FAIL raises-other: the refusal raises, but a plain error, not the refusal
  expected: (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in fixture: boom\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (1 "" "check-nothreads: (curl) raised something other than the refusal: Exception in environment: library (curl) not found\ncheck-nothreads: FAILED (problems: 1)\n")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```
(18 more such lines cut.)

### NT8. the program exits 0 after naming its problems

**Guards:** a failure exits 1.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
                   (string-append "FAILED (problems: " (number->string (length problems)) ")"))
-             (exit 1)))))))
+             (exit 0)))))))
 
```

**Result:** killed, exit 2:

```
FAIL mixed: one public library does not import the refusal: it loads, and is named, and the others are still refused
  expected: (1 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "check-nothreads: (curl unsupported) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
FAIL private-only: private libraries alone: the program imports none, so it has nothing to refuse
  expected: (1 "" "check-nothreads: no public library under tests/fixtures/nothreads/private-only, so there is nothing to refuse\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "" "check-nothreads: no public library under tests/fixtures/nothreads/private-only, so there is nothing to refuse\ncheck-nothreads: FAILED (problems: 1)\n")
FAIL src/: on a threaded Chez nothing is refused, so the program names every public library it could import
  expected: (1 "" "check-nothreads: (curl) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "" "check-nothreads: (curl) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```
(24 more such lines cut.)

### NT9. the program ignores a source it cannot read

**Guards:** a file that cannot be read as data is named, not skipped.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
                         (map (lambda (read)
-                               (if (eq? (cadr read) 'unreadable)
-                                   (list (string-append (car read) ": it cannot be read as data: "
-                                                        (caddr read)))
-                                   '()))
+                               '())
                              reads))
```

**Result:** killed, exit 2:

```
FAIL unreadable: a source that cannot be read as data is named, and the libraries beside it are still checked
  expected: (1 "check-nothreads: (curl) is refused by name\n" "check-nothreads: tests/fixtures/nothreads/unreadable/curl/broken.sls: it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 48 o [cut: 147 more characters]
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### NT10. the program ignores a symbolic link to a directory

**Guards:** a link it does not follow is named, not skipped.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
                 (append
-                 (map (lambda (link)
-                        (string-append link ": it is a symbolic link to a directory,"
-                                       " which this check does not follow"))
-                      links)
+                 '()
                  (apply append
```

**Result:** killed, exit 2:

```
FAIL dir-symlink: a symbolic link to a directory is named, not followed
  expected: (1 "check-nothreads: (curl) is refused by name\n" "check-nothreads: tests/fixtures/nothreads/dir-symlink/linked: it is a symbolic link to a directory, which this check does not follow\ncheck-nothreads: FAILED (problems: 1)\n")
  actual:   (0 "check-nothreads: (curl) is refused by name\n" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### NT11. the program takes more than one argument

**Guards:** one argument, the directory, and a usage line for any other count.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
 (define (main args)
-  (if (not (= (length args) 1))
+  (if (< (length args) 1)
       (begin
```

**Result:** killed, exit 2:

```
FAIL two arguments: the usage line, exit 1
  expected: (1 "" "check-nothreads: usage: scheme --program tests/check-nothreads.sps DIR\n")
  actual:   (0 "check-nothreads: (curl) is refused by name\ncheck-nothreads: (curl unsupported) is refused by name\ncheck-nothreads: (http-client) is refused by name\n" "")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### NT11b. the program takes no argument at all

**Guards:** one argument, the directory, and a usage line for any other count.

**Mutation:** In `tests/check-nothreads.sps`:

```diff
 (define (main args)
-  (if (not (= (length args) 1))
+  (if (> (length args) 1)
       (begin
```

**Result:** killed, exit 2:

```
FAIL no arguments: the usage line, exit 1
  expected: (1 "" "check-nothreads: usage: scheme --program tests/check-nothreads.sps DIR\n")
  actual:   (255 "" "Exception in car: () is not a pair\n")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### FX1. a fixture directory no case runs

**Guards:** every fixture directory is a case, so a fixture nothing runs guards nothing.

**Mutation:** In `tests/fixtures/nothreads/stray/notes.txt`:

```diff
+A fixture directory with no case.
```

**Result:** killed, exit 2:

```
FAIL every fixture directory is a case above, and every case has its directory
  expected: ("dir-symlink" "empty" "mixed" "not-syntax" "private-only" "raises-other" "refusing" "unreadable" "wrong-message" "wrong-who")
  actual:   ("dir-symlink" "empty" "mixed" "not-syntax" "private-only" "raises-other" "refusing" "stray" "unreadable" "wrong-message" "wrong-who")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### FX2. the suite scans a directory with no library, not src/, for the public libraries it expects

**Guards:** a scan of the wrong directory finds no (curl), and the row that names it fails.

**Mutation:** In `tests/test-check-nothreads.sps`:

```diff
   (guard (e (#t '()))
-    (let loop ((names (map library-name (sls-files "src"))) (found '()))
+    (let loop ((names (map library-name (sls-files "tests/fixtures/nothreads/empty"))) (found '()))
       (cond ((null? names) (reverse found))
```

**Result:** killed, exit 2:

```
FAIL src/ holds the public library (curl)
  expected: found
  actual:   not-found
FAIL src/: on a threaded Chez nothing is refused, so the program names every public library it could import
  expected: (1 "" "check-nothreads: FAILED (problems: 0)\n")
  actual:   (1 "" "check-nothreads: (curl) loaded, but a non-threaded Chez must refuse it\ncheck-nothreads: FAILED (problems: 1)\n")
test: FAIL tests/test-check-nothreads.sps (exit 1)
make: *** [Makefile:193: test] Error 1
```

### FX3. CHEZ unset when the suite runs

**Guards:** without CHEZ nothing can run: that fails by name and never skips.

**Mutation:** none to a file. `CHEZ` is unset.

**Command** in the container: `tests/test-check-nothreads.sps` run directly, under `env -u CHEZ`.

**Result:** killed, exit 1:

```
FAIL CHEZ names the Chez to spawn
  expected: set
  actual:   unset
direct: test-check-nothreads exit 1
```

### FL1. workflow-problems takes the floors from constants, the real floors, not from the file

**Guards:** the env lines are those of the floors file, whatever it gives.

**Mutation:** In `tests/floors.sls`:

```diff
            (rows (map (lambda (row)
-                        (let ((version (floor-text floors (car row))))
+                        (let ((version (if (eq? (car row) (quote chez)) "10.4.0" "7.85.0")))
                           (list (cadr row) version (env-line (caddr row) version) (caddr row))))
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL README: the three lines the floors give, in order
  expected: (returned ())
  actual:   (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.4.0\\\"\" appears 0 times, but must appear once" "W.yml: the line \"  CURL_FLOOR_VERSION: \\\"7.85.0\\\"\" appears 0 times, but must appear once"))
FAIL workflow: the two env lines once each, and the versions as references
  expected: (returned ())
  actual:   (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.4.0\\\"\" appears 0 times, but must appear once" "W.yml: the line \"  CURL_FLOOR_VERSION: \\\"7.85.0\\\"\" appears 0 times, but must appear once"))
FAIL README and workflow: the lines come from the floors file: other floors, other lines
  expected: (returned ("R.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.9.1 or later, built with threads\", but f.sexp gives \"- Chez Scheme 10.0.0 or later, built with threads\"" "R.org: list line 2 under \"** Requiremen [cut: 459 more characters]
  actual:   (returned ("R.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.9.1 or later, built with threads\", but f.sexp gives \"- Chez Scheme 10.0.0 or later, built with threads\"" "R.org: list line 2 under \"** Requiremen [cut: 459 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(465 more such lines cut.)

### FL2. an env line may appear more than once

**Guards:** each env line appears exactly once.

**Mutation:** In `tests/floors.sls`:

```diff
                      (let ((times (occurrences (caddr row) lines)))
-                       (if (= times 1)
+                       (if (>= times 1)
                            '()
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL workflow: the Chez line twice
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 2 times, but must appear once"))
  actual:   (returned ())
FAIL workflow: the libcurl line three times, and the Chez line twice
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 2 times, but must appear once" "W.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 3 times, but must appear once"))
  actual:   (returned ())
FAIL workflow-duplicated: the workflow's libcurl line twice
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-duplicated/ci.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 2 times, but must appear once\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (0 "check-floors: tests/fixtures/floors/workflow-duplicated/README.org and tests/fixtures/floors/workflow-duplicated/ci.yml hold the floors in tests/fixtures/floors/workflow-duplicated/floors.sexp (chez 10.9.1, libcurl 8.1.2, no [cut: 15 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(15 more such lines cut.)

### FL3. a floor written in a comment is not a literal elsewhere

**Guards:** no other line may write a floor, a comment included.

**Mutation:** In `tests/floors.sls`:

```diff
            ((null? rest) '())
-           ((member (car rest) env-lines) (loop (cdr rest) (+ n 1)))
+           ((or (member (car rest) env-lines) (contains? (car rest) "#")) (loop (cdr rest) (+ n 1)))
            (else
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL workflow: an env line with a comment after it is another line, and writes the floor
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{  [cut: 22 more characters]
  actual:   (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once"))
FAIL workflow: the Chez floor in a comment
  expected: (returned ("W.yml: line 16 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{ env.CHEZ_VERSION }}"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
FAIL workflow: an env line with a comment after it is another line, and writes the floor
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{  [cut: 22 more characters]
  actual:   (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once"))
direct: test-check-floors exit 1
```
(3 more such lines cut.)

### FL4. only the Chez floor is searched for elsewhere in the workflow

**Guards:** neither floor is written anywhere but its env line.

**Mutation:** In `tests/floors.sls`:

```diff
                                '()))
-                         rows))
+                         (list (car rows))))
              (loop (cdr rest) (+ n 1)))))))))
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL workflow: the libcurl floor in a run step
  expected: (returned ("W.yml: line 16 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" may write; refer to ${{ env.CURL_FLOOR_VERSION }}"))
  actual:   (returned ())
FAIL workflow: the libcurl floor in a cache key
  expected: (returned ("W.yml: line 16 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" may write; refer to ${{ env.CURL_FLOOR_VERSION }}"))
  actual:   (returned ())
FAIL workflow: both floors on one line: both are named, the Chez floor first
  expected: (returned ("W.yml: line 16 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{ env.CHEZ_VERSION }}" "W.yml: line 16 contains the libcurl floor 8.1.2, which only the line [cut: 93 more characters]
  actual:   (returned ("W.yml: line 16 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{ env.CHEZ_VERSION }}"))
FAIL workflow-literal: the workflow writes the libcurl floor in a step, where only its env line may
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-literal/ci.yml: line 13 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" may write; refer to ${{ env.CURL_FLOOR_VERSION }}\ncheck-f [cut: 31 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflow-literal/README.org and tests/fixtures/floors/workflow-literal/ci.yml hold the floors in tests/fixtures/floors/workflow-literal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\ [cut: 6 more characters]
```
(21 more such lines cut.)

### FL5. an env line counts when it is a part of a line

**Guards:** the env line is the whole line, from its first character to its last.

**Mutation:** In `tests/floors.sls`:

```diff
               (map (lambda (row)
-                     (let ((times (occurrences (caddr row) lines)))
+                     (let ((times (length (filter (lambda (l) (contains? l (caddr row))) lines))))
                        (if (= times 1)
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL workflow: an env line with a comment after it is another line, and writes the floor
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{  [cut: 22 more characters]
  actual:   (returned ("W.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{ env.CHEZ_VERSION }}"))
FAIL workflow: an env line with a space at its end is another line, and writes the floor
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{  [cut: 22 more characters]
  actual:   (returned ("W.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{ env.CHEZ_VERSION }}"))
FAIL workflow: an env line indented four spaces is another line, and writes the floor
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{  [cut: 22 more characters]
  actual:   (returned ("W.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" may write; refer to ${{ env.CHEZ_VERSION }}"))
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(9 more such lines cut.)

### FL6. check-floors does not compare the workflow

**Guards:** the workflow is held to the floors file.

**Mutation:** In `tests/floors.sls`:

```diff
             (append (if rtext (readme-problems rpath rtext fpath floors) '())
-                    (if wtext (workflow-problems wpath wtext floors) '())))
+                    '()))
           problems))))
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL workflow: no workflow text: both lines are missing
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but must appear once"))
  actual:   (returned ())
FAIL workflow: the Chez line says another version
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once"))
  actual:   (returned ())
FAIL workflow-altered: the workflow's Chez line says another version
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-altered/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (0 "check-floors: tests/fixtures/floors/workflow-altered/README.org and tests/fixtures/floors/workflow-altered/ci.yml hold the floors in tests/fixtures/floors/workflow-altered/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\ [cut: 6 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(147 more such lines cut.)

### FL7. check-floors compares the README and the workflow even when the floors file has problems

**Guards:** a bad floors file is reported alone: the others cannot be held to it.

**Mutation:** In `tests/floors.sls`:

```diff
     (let ((problems (floors-problems fpath ftext)))
-      (if (null? problems)
+      (if #t
           (let ((floors (car (cadr (read-data ftext)))))
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL a bad floors file is reported alone: neither the README nor the workflow is read against it
  expected: (returned ("f.sexp: the key node is missing"))
  actual:   (returned ("R.org: it has no \"** Requirements\" section" "W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but m [cut: 18 more characters]
FAIL floors-invalid: a floors file with a missing key and a bad version: both named, and the README and workflow not read
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [cut: 53 more characters]
  actual:   (255 "" "Exception in floor-text: no such floor with irritant node\n")
FAIL a bad floors file, no README and no workflow: the floors problems, then the README, then the workflow
  expected: (1 "" "check-floors: tests/fixtures/floors/floors-invalid/floors.sexp: the key node is missing\ncheck-floors: tests/fixtures/floors/floors-invalid/floors.sexp: chez: the version \"10.9\" is not three dot-separated naturals, majo [cut: 453 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/floors-invalid/none.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/floors-invalid/none.org: no such file or directory\ncheck-floors: tests/f [cut: 217 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(9 more such lines cut.)

### FL8. check-floors compares a workflow it could not read as an empty text

**Guards:** a file the caller could not read is not compared; the caller names it.

**Mutation:** In `tests/floors.sls`:

```diff
             (append (if rtext (readme-problems rpath rtext fpath floors) '())
-                    (if wtext (workflow-problems wpath wtext floors) '())))
+                    (workflow-problems wpath (or wtext "") floors)))
           problems))))
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL an unreadable workflow, #f, is not compared, and the README still is
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ("R.org: it has no \"** Requirements\" section" "W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but m [cut: 18 more characters]
FAIL two unreadable files compare nothing
  expected: (returned ())
  actual:   (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but must appear once"))
FAIL no-workflow: a floors file and a README, and no workflow beside them
  expected: (1 "" "check-floors: tests/fixtures/floors/no-workflow/ci.yml: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-workflow/ci.yml: no such file or directory\ncheck-floors: FAILED (problems: [cut: 7 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/no-workflow/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once\ncheck-floors: tests/fixtures/floors/no-workflow/ci.yml: the line \"  CURL_FLOOR_VE [cut: 290 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(15 more such lines cut.)

### FL9. check-floors compares a README it could not read as an empty text

**Guards:** a file the caller could not read is not compared; the caller names it.

**Mutation:** In `tests/floors.sls`:

```diff
           (let ((floors (car (cadr (read-data ftext)))))
-            (append (if rtext (readme-problems rpath rtext fpath floors) '())
+            (append (readme-problems rpath (or rtext "") fpath floors)
                     (if wtext (workflow-problems wpath wtext floors) '())))
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL an unreadable README, #f, is not compared, and the workflow still is
  expected: (returned ("W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but must appear once"))
  actual:   (returned ("R.org: it has no \"** Requirements\" section" "W.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but m [cut: 18 more characters]
FAIL two unreadable files compare nothing
  expected: (returned ())
  actual:   (returned ("R.org: it has no \"** Requirements\" section"))
FAIL no-readme: a floors file and no README beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-readme/README.org: no such file or directory\ncheck-floors: FAILED (probl [cut: 11 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/no-readme/README.org: it has no \"** Requirements\" section\ncheck-floors: tests/fixtures/floors/no-readme/README.org: it cannot be read: Exception in open-file-input-port: failed for t [cut: 108 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(9 more such lines cut.)

### PF1. the program does not name a workflow it cannot read

**Guards:** a missing workflow fails.

**Mutation:** In `tests/check-floors.sps`:

```diff
             (if (eq? (car r) 'text) '() (list (cadr r)))
-            (if (eq? (car w) 'text) '() (list (cadr w))))))
+            '())))
 
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL no-workflow: a floors file and a README, and no workflow beside them
  expected: (1 "" "check-floors: tests/fixtures/floors/no-workflow/ci.yml: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-workflow/ci.yml: no such file or directory\ncheck-floors: FAILED (problems: [cut: 7 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/no-workflow/README.org and tests/fixtures/floors/no-workflow/ci.yml hold the floors in tests/fixtures/floors/no-workflow/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
FAIL no file exists: all three named, the floors first, then the README, then the workflow
  expected: (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: tests/fixtures/floors/l [cut: 365 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: tests/fixtures/floors/l [cut: 183 more characters]
FAIL a README with a problem and no workflow: both named, the README first
  expected: (1 "" "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\ncheck-floors: tests/fixtures/floors/legal/none.yml: it cannot be read: Exception in open-file-input-port: failed for tests/ [cut: 97 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/no-section/README.org: it has no \"** Requirements\" section\ncheck-floors: FAILED (problems: 1)\n")
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(15 more such lines cut.)

### PF2. the program never compares the workflow

**Guards:** the program holds the workflow it is given to the floors file.

**Mutation:** In `tests/check-floors.sps`:

```diff
     (append (if (eq? (car f) 'text)
-                (check-floors fpath (cadr f) rpath (text-or-false r) wpath (text-or-false w))
+                (check-floors fpath (cadr f) rpath (text-or-false r) wpath #f)
                 (list (cadr f)))
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL workflow-altered: the workflow's Chez line says another version
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-altered/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (0 "check-floors: tests/fixtures/floors/workflow-altered/README.org and tests/fixtures/floors/workflow-altered/ci.yml hold the floors in tests/fixtures/floors/workflow-altered/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\ [cut: 6 more characters]
FAIL workflow-literal: the workflow writes the libcurl floor in a step, where only its env line may
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-literal/ci.yml: line 13 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" may write; refer to ${{ env.CURL_FLOOR_VERSION }}\ncheck-f [cut: 31 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflow-literal/README.org and tests/fixtures/floors/workflow-literal/ci.yml hold the floors in tests/fixtures/floors/workflow-literal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\ [cut: 6 more characters]
FAIL workflow-duplicated: the workflow's libcurl line twice
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-duplicated/ci.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 2 times, but must appear once\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (0 "check-floors: tests/fixtures/floors/workflow-duplicated/README.org and tests/fixtures/floors/workflow-duplicated/ci.yml hold the floors in tests/fixtures/floors/workflow-duplicated/floors.sexp (chez 10.9.1, libcurl 8.1.2, no [cut: 15 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(9 more such lines cut.)

### PF3. the program takes two or more arguments

**Guards:** FLOORS README WORKFLOW, and a usage line for any other count.

**Mutation:** In `tests/check-floors.sps`:

```diff
 (define (main args)
-  (if (not (= (length args) 3))
+  (if (< (length args) 2)
       (begin
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL two arguments: the usage line, exit 1
  expected: (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOW\n")
  actual:   (255 "" "Exception in caddr: incorrect list structure (\"tests/fixtures/floors/legal/floors.sexp\" \"tests/fixtures/floors/legal/README.org\")\n")
FAIL four arguments: the usage line, exit 1
  expected: (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOW\n")
  actual:   (0 "check-floors: tests/fixtures/floors/legal/README.org and tests/fixtures/floors/legal/ci.yml hold the floors in tests/fixtures/floors/legal/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\n" "")
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
FAIL two arguments: the usage line, exit 1
  expected: (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOW\n")
  actual:   (255 "" "Exception in caddr: incorrect list structure (\"tests/fixtures/floors/legal/floors.sexp\" \"tests/fixtures/floors/legal/README.org\")\n")
direct: test-check-floors exit 1
```
(3 more such lines cut.)

### PF3b. the program takes three or more arguments

**Guards:** FLOORS README WORKFLOW, and a usage line for any other count.

**Mutation:** In `tests/check-floors.sps`:

```diff
 (define (main args)
-  (if (not (= (length args) 3))
+  (if (> (length args) 3)
       (begin
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL no arguments: the usage line, exit 1
  expected: (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOW\n")
  actual:   (255 "" "Exception in car: () is not a pair\n")
FAIL one argument: the usage line, exit 1
  expected: (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOW\n")
  actual:   (255 "" "Exception in cadr: incorrect list structure (\"tests/fixtures/floors/legal/floors.sexp\")\n")
FAIL two arguments: the usage line, exit 1
  expected: (1 "" "check-floors: usage: scheme --libdirs tests --program tests/check-floors.sps FLOORS README WORKFLOW\n")
  actual:   (255 "" "Exception in caddr: incorrect list structure (\"tests/fixtures/floors/legal/floors.sexp\" \"tests/fixtures/floors/legal/README.org\")\n")
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
direct: test-check-floors exit 1
```
(9 more such lines cut.)

### PF4. the program does not name a floors file it cannot read

**Guards:** a missing floors file fails.

**Mutation:** In `tests/check-floors.sps`:

```diff
                 (check-floors fpath (cadr f) rpath (text-or-false r) wpath (text-or-false w))
-                (list (cadr f)))
+                '())
             (if (eq? (car r) 'text) '() (list (cadr r)))
```

**Command** in the container: `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, exit 2:

```
FAIL no-floors: a README and no floors file beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\ncheck-floors: FAILED (pro [cut: 13 more characters]
  actual:   (255 "" "Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\n")
FAIL no file exists: all three named, the floors first, then the README, then the workflow
  expected: (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: tests/fixtures/floors/l [cut: 365 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/legal/none.org: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.org: no such file or directory\ncheck-floors: tests/fixtures/floors/leg [cut: 181 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:193: test] Error 1
FAIL no-floors: a README and no floors file beside it
  expected: (1 "" "check-floors: tests/fixtures/floors/no-floors/floors.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\ncheck-floors: FAILED (pro [cut: 13 more characters]
  actual:   (255 "" "Exception in open-file-input-port: failed for tests/fixtures/floors/no-floors/floors.sexp: no such file or directory\n")
direct: test-check-floors exit 1
```
(3 more such lines cut.)

### CF1. the workflow's CHEZ_VERSION line says 10.3.0

**Guards:** the Chez env line is the floor of packaging/floors.sexp.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
 env:
-  CHEZ_VERSION: "10.4.0"
+  CHEZ_VERSION: "10.3.0"
   CURL_FLOOR_VERSION: "7.85.0"
```

**Result:** killed, exit 2:

```
check-floors: .github/workflows/ci.yml: the line "  CHEZ_VERSION: \"10.4.0\"" appears 0 times, but must appear once
check-floors: FAILED (problems: 1)
make: *** [Makefile:255: check-floors] Error 1
```

### CF2. the workflow's CURL_FLOOR_VERSION line is missing

**Guards:** the libcurl env line is there.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
   CHEZ_VERSION: "10.4.0"
-  CURL_FLOOR_VERSION: "7.85.0"
 
```

**Result:** killed, exit 2:

```
check-floors: .github/workflows/ci.yml: the line "  CURL_FLOOR_VERSION: \"7.85.0\"" appears 0 times, but must appear once
check-floors: FAILED (problems: 1)
make: *** [Makefile:255: check-floors] Error 1
```

### CF3a. a literal 7.85.0 in a comment at the end of the workflow

**Guards:** no other line writes a floor, a comment included.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
         run: make test-memory
+# the libcurl floor is 7.85.0
```

**Result:** killed, exit 2:

```
check-floors: .github/workflows/ci.yml: line 444 contains the libcurl floor 7.85.0, which only the line "  CURL_FLOOR_VERSION: \"7.85.0\"" may write; refer to ${{ env.CURL_FLOOR_VERSION }}
check-floors: FAILED (problems: 1)
make: *** [Makefile:255: check-floors] Error 1
```

### CF3b. a literal 10.4.0 in the build step of the nothreads job

**Guards:** every use of a floor refers to the env line.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
         if: steps.chez.outputs.cache-hit != 'true'
-        run: scripts/ci/build-chez.sh "$CHEZ_VERSION" "$RUNNER_TEMP/chez-nothreads" --nothreads
+        run: scripts/ci/build-chez.sh 10.4.0 "$RUNNER_TEMP/chez-nothreads" --nothreads
 
```

**Result:** killed, exit 2:

```
check-floors: .github/workflows/ci.yml: line 342 contains the Chez floor 10.4.0, which only the line "  CHEZ_VERSION: \"10.4.0\"" may write; refer to ${{ env.CHEZ_VERSION }}
check-floors: FAILED (problems: 1)
make: *** [Makefile:255: check-floors] Error 1
```

### CF4. the workflow's CHEZ_VERSION line twice

**Guards:** each env line appears once.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
   CHEZ_VERSION: "10.4.0"
+  CHEZ_VERSION: "10.4.0"
   CURL_FLOOR_VERSION: "7.85.0"
```

**Result:** killed, exit 2:

```
check-floors: .github/workflows/ci.yml: the line "  CHEZ_VERSION: \"10.4.0\"" appears 2 times, but must appear once
check-floors: FAILED (problems: 1)
make: *** [Makefile:255: check-floors] Error 1
```

### CF5. no workflow file

**Guards:** a missing workflow fails.

**Mutation:** delete `.github/workflows/ci.yml`, all 443 lines of it. (The driver's diff shows them all; this log does not.)

**Result:** killed, exit 2:

```
check-floors: .github/workflows/ci.yml: it cannot be read: Exception in open-file-input-port: failed for .github/workflows/ci.yml: no such file or directory
check-floors: FAILED (problems: 1)
make: *** [Makefile:255: check-floors] Error 1
```

### CF6. the workflow's CHEZ_VERSION line with a comment after it

**Guards:** the env line is exact: nothing follows its closing quote.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
 env:
-  CHEZ_VERSION: "10.4.0"
+  CHEZ_VERSION: "10.4.0" # the floor
   CURL_FLOOR_VERSION: "7.85.0"
```

**Result:** killed, exit 2:

```
check-floors: .github/workflows/ci.yml: the line "  CHEZ_VERSION: \"10.4.0\"" appears 0 times, but must appear once
check-floors: .github/workflows/ci.yml: line 53 contains the Chez floor 10.4.0, which only the line "  CHEZ_VERSION: \"10.4.0\"" may write; refer to ${{ env.CHEZ_VERSION }}
check-floors: FAILED (problems: 2)
make: *** [Makefile:255: check-floors] Error 1
```

### H1. check-nothreads lacks its help text

**Guards:** make help lists every .PHONY target (check-help).

**Mutation:** In `Makefile`:

```diff
 # Chez's own bindings, so it needs no deps.
-check-nothreads: ## Fail unless every public library refuses to import, by name, on this Chez; CI runs it on a --nothreads Chez
+check-nothreads:
 	@scripts/require-tools "$(GOAL)" $(CHEZ)
```

**Result:** killed, exit 2:

```
check-help: make help does not list .PHONY target 'check-nothreads'; give it a '## ' description on its target line
make: *** [Makefile:58: check-help] Error 1
```

### H2. check-nothreads is left out of .PHONY

**Guards:** every listed target is in .PHONY (check-help).

**Mutation:** In `Makefile`:

```diff
 # a backslash.
-.PHONY: help check-help check-guix check-guix-inside deps check-pins build test check-suites check-seam check-floors check-nothreads check-test-fails
+.PHONY: help check-help check-guix check-guix-inside deps check-pins build test check-suites check-seam check-floors check-test-fails
 
```

**Result:** killed, exit 2:

```
check-help: make help lists 'check-nothreads', which is not in .PHONY
make: *** [Makefile:58: check-help] Error 1
```

### Coverage

Every test that failed in a red run (14 in `test-check-nothreads`, 39 in `test-check-floors`) was failed by name by at
least one mutation. The three that passed in `test-check-nothreads`' red run guard the suite itself: `CHEZ names the
Chez to spawn` (FX3), `every fixture directory is a case above, and every case has its directory` (FX1) and
`src/ holds the public library (curl)` (FX2). Four rows of `test-check-floors` that the first mutations left unfailed
were each given a case: the usage rows `no arguments` and `one argument` (PF3b), `floors-invalid` (FL7) and `no-floors`
(PF4), because the program's `problems` and `check-floors` were rewritten for a third file. The rows added after the red
run, which take a text that is `#f` for a file the program could not read, are failed by FL8 and FL9.

Notes on single mutations:

- **NT6** is not killed by the real `src/`: its only public library, `(curl)`, is `src/curl.sls`, at the top level, and
  every other library under `src/curl/` is private. It is killed by the fixture trees, where a public library lies in a
  subdirectory (`curl/unsupported.sls`). A first draft of the case expected the `src/` row to fail too, was marked
  SURVIVED by the driver, and was corrected after reading the run: the run had failed `refusing`, `mixed` and `unreadable`.
- **NT3a, NT3b and NT3c** each drop one conjunct of the refusal, and each is killed by exactly one fixture: a syntax
  violation, from `chez-curl`, whose message starts with the marker.
- **CF3a and CF3b** take the line number they expect from the snapshot's file, so a comment appended to the workflow, or
  a step edited, is named by its line.

### Not covered

- **The workflow, beyond its two env lines.** `make check-floors` holds nothing but those lines and the absence of the
  floors elsewhere (CF1 to CF6). No mutation covers the jobs, the cache keys, the `if:` conditions or the step scripts:
  they run only on GitHub. They are held by actionlint, which passes the workflow and fails an unknown job key and an
  unquoted variable in a `run:` script when those are planted, and, for three step scripts, by running each in the
  container (the memory decision for every ref and request; the floor lane's build-and-test step against a libcurl
  7.85.0 built there; the disabled-APIs step against the same libcurl built with the two APIs off). See the report.
- **A literal that is not a floor.** The workflow rule searches for the floors' text. A workflow that builds Chez with a
  literal version other than the floor passes it, so long as the env lines are right and no other line writes the
  floor. It does not require the env entries to be used.
- **The Node floor.** No step of the workflow uses Node yet; the rule holds only the Chez and libcurl floors.
- **`scripts/ci/*.sh` pins a sha256 per version, and names the floors.** `make check-floors` does not read them: a
  floor changed in `packaging/floors.sexp` and the workflow without a sum added fails in CI, at the download, not here.
- **The builds.** The scripts are not mutated. shellcheck passes them; a tampered pin stops each before it unpacks
  anything; an unpinned version, a missing prefix and a relative prefix are refused; `build-curl.sh` built both curl
  variants in `ubuntu:24.04`. `build-chez.sh` was not run past its checks: no Chez is built anywhere but CI.
- **A real `--nothreads` Chez.** `check-nothreads` is red on this threaded Chez by design. The green run on a Chez that
  refuses is shown on a copy of `src/` in which `(threaded?)` is replaced by `#f`; only CI's lane shows a real one.
- **Output order.** `check-nothreads` sorts the files it reads by path, so its lines come in a fixed order. A mutation
  that unsorts them is not killed reliably: `directory-list`'s order is the filesystem's, and may already be sorted.
- **`tests/check-test-fails.sh`** plants a README that disagrees with the floors file, and no workflow that does.

### Clean rerun

After every mutation, on the working tree itself, whose files are byte-identical to the snapshot every case copied
(`diff -r`, without `.git` and `build/`). `make test`, `make check-test-fails` and `make check-help` each exited 0:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows/ci.yml hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
# of expected passes      211
test: pass tests/test-check-floors.sps
# of expected passes      17
test: pass tests/test-check-nothreads.sps
test: ran 14, passed 14, failed 0, hung 0
make test exit 0
check-test-fails exit 0
check-help exit 0
check-test-fails: make test failed, as it must, in all 10 cases
```
(34 more lines cut: the other suites' counts and `test: pass` lines, and check-test-fails' case lines.)

## Review fixes

The review of the memory gate found two holes and a wording question
([ADR-0014](decisions/0014-valgrind-memory-gate.md), as amended 2026-10-16). Each fix closes a
class, not the reviewer's example:

1. **Valgrind's inputs were refused by a deny list.** `VALGRIND_LIB` pointed at a copy of
   Valgrind's library directory, whose `default.supp` gained a catch-all entry, turned the
   planted leak into a pass. The `./.valgrindrc` refusal had no standing case.
2. **A pass needed no evidence that Valgrind ran.** With a wrapper script as `CHEZ`, every
   plant passed.
3. **The one-block cap's wording.**

The part changes two files:

- `Makefile`, the `test-memory` recipe and its comment, and `check-memory-gate`'s comment:
  - every suite runs as `timeout --foreground 3600 valgrind -v --command-line-only=yes
    --error-exitcode=9 --leak-check=full --show-leak-kinds=definite
    --errors-for-leak-kinds=definite [--suppressions=tests/guix-glibc-locpath.supp] $CHEZ
    --libdirs … --program SUITE`;
  - it refuses to run while any `VALGRIND_` variable is set, naming each, or while
    `$HOME/.valgrindrc` or `./.valgrindrc` exists, naming each. Valgrind reads three
    variables: `VALGRIND_OPTS`, `VALGRIND_LIB` and `VALGRIND_LAUNCHER`. The refusal takes
    the whole `VALGRIND_` prefix;
  - before the suites, it asks Valgrind for its own `default.supp`, in a run on `true` with
    `VALGRIND_LIB` unset;
  - a suite that exits 0 passes only when its log shows evidence, read from the lines of
    Valgrind's own process. Otherwise the FAIL line names each thing missing or wrong:
    - the `Command:` line is `$CHEZ --libdirs $LIBDIRS --program SUITE`;
    - the first `Reading syms from` line names the file `CHEZ` resolves to (`readlink -f`);
    - Valgrind reports `ERROR SUMMARY: 0 errors from 0 contexts`;
    - the `Reading suppressions file:` lines are exactly Valgrind's own `default.supp` and,
      when `GUIX_ENVIRONMENT` is set, `tests/guix-glibc-locpath.supp`;
    - in a Guix environment, exactly one block was suppressed when the process read
      `libp11-kit`, and none when it did not. This replaces the cap of one.
  - the FAIL excerpt now finds an error by its header line followed by an `at 0x` frame:
    `-v` adds lines that the old rule took for errors.
- `tests/check-memory-gate.sh`, from 16 cases to 27 in the container (22 outside Guix):
  - e now holds both commands Valgrind is handed, the question and the suite's, and requires
    a FAIL from a stand-in Valgrind that runs nothing;
  - d's checks no longer add their own `-v`, and `d used` names the exact `default.supp`;
  - new: `d alone`; five `h` cases; two `i` cases; four `j` cases (listed in the script's
    header).

The driver is `slice5/fix/mutate.py` in the session scratchpad, adapted from the first
part's. It froze two trees, without `.git`, `build/` or `.claude/`:

- `snap/`, the fixed working tree;
- `snap-before/`, the same with the Makefile as it was before the fixes, for the red runs.

Each case got a fresh copy, a touched `manifest.scm`, and its command through the copy's own
`scripts/guix-env`. Each edit was an exact-text replacement that had to match exactly once.
Three ran at a time. A case counts as killed only when its command exits non-zero and every
expected line is present: whole, as a substring (`~` first), or as a prefix (`~` last). The
working tree was never edited.

**Result** quotes at most 12 lines, chosen as in the first part, and says how many more were
cut. Diff lines are cut at 200 characters, output lines at 240.

### Measurements

The container has Valgrind 3.27.0, Chez 10.4.0, glibc 2.41 and GNU awk, on amd64. Ubuntu
24.04 ran in Docker, with Valgrind 3.22.0 from apt and mawk as `awk`, as CI has them. No Chez
was built there.

**What Valgrind reads.**

- Both versions' tools name `VALGRIND_OPTS`, `VALGRIND_LIB` and `VALGRIND_LAUNCHER`, and
  `~/.valgrindrc` and `./.valgrindrc`. They also name `DEBUGINFOD_URLS`, `DEBUGINFOD_PROGRESS`
  and `DEBUGINFOD_VERBOSE`.
- Ubuntu's `/usr/bin/valgrind` is a shell script. It sets `LD_LIBRARY_PATH` and execs
  `valgrind.bin`, which names `VALGRIND_LAUNCHER` and `VALGRIND_LIB`.
- Valgrind 3.27 also reads `./.valgrindrc` only when `HOME` is set.

**`--command-line-only=yes` blocks the three option sources and leaves `VALGRIND_LIB` alone.**
`all.supp` holds a `fun:*` then `...` entry. Each run is `valgrind -v [--command-line-only=yes]
true`, and its `Reading suppressions file:` lines are shown. The Valgrind 3.22 runs, from
`slice5/fix/probe-ubuntu-322.txt`:

```
VALGRIND_OPTS=--suppressions=all.supp         without: /work/p/all.supp, then /usr/libexec/valgrind/default.supp
                                              with:    /usr/libexec/valgrind/default.supp
HOME/.valgrindrc naming all.supp              without: /work/p/all.supp, then default.supp; with: default.supp
./.valgrindrc naming all.supp                 without: /work/p/all.supp, then default.supp; with: default.supp
VALGRIND_LIB=vglib (default.supp + all.supp)  with:    --181-- Valgrind library directory: /work/p/vglib
                                                       --181-- Reading suppressions file: /work/p/vglib/default.supp
the same under env -u VALGRIND_LIB            with:    --183-- Reading suppressions file: /usr/libexec/valgrind/default.supp
```

- Valgrind 3.27 in the container gives the same five results, with its store paths.
- `--suppressions=x` is read before `default.supp` in both versions.
- 3.27 accepts `--command-line-only=bogus` without a word. Only case e's whole command
  holds the literal.
- With `-v`, the `Valgrind options:` list also shows options that came from
  `VALGRIND_OPTS`.

**`VALGRIND_LIB` cannot be left to the allowlist.**

- It chooses the tool binary and the preloads, as well as `default.supp`. A tool binary
  taken from there can print any log at all.
- So it is refused. Behind the refusal, the allowlist names the impostor `default.supp`
  (MF16), because test-memory asks for Valgrind's own with `VALGRIND_LIB` unset (MF16b is
  the control).
- On Valgrind 3.22, the bare gate command with `VALGRIND_LIB` at such a copy, and
  `--command-line-only=yes`, exited 0, with `suppressed: 777 bytes in 1 blocks` from a C
  program that leaks 777 bytes.

**`VALGRIND_LAUNCHER` does nothing that a run shows.** With it set to the stand-in's path, the
old gate still failed the leak plant with exit 9. The launcher sets the variable itself. It is
refused only as defence.

**What a wrapper `CHEZ` and an exec leave in the log.** Each run was the leak plant, under the
gate's flags with `-v`, in the container:

```
CHEZ a script that execs Chez:    exit 0; Command: names the script; first "Reading syms from" is …-bash-5.2.37/bin/bash; no ERROR SUMMARY
CHEZ a script that runs Chez:     exit 0; Command: names the script; first "Reading syms from" is …-bash-5.2.37/bin/bash; ERROR SUMMARY: 0 errors from 0 contexts
a program that execv's /bin/sh:   exit 0; Command: and first "Reading syms from" are Chez's; no ERROR SUMMARY
```

- So no single line proves that Valgrind ran Chez: test-memory reads all three.
- On Ubuntu, a `#!/bin/sh` script's first `Reading syms from` is `/usr/bin/dash`, which is
  `readlink -f /bin/sh`.
- Chez resolves `execv` only after `(load-shared-object "libc.so.6")`.

**What `-v` adds to a log.** The `Valgrind options:` list. Each object read
(`Reading syms from`), each `REDIR`, each suppressions file and each suppression used. Two
blocks in `==PID==` form: `embedded gdbserver: …` and `TO CONTROL THIS PROCESS USING vgdb …`.
The lines `Searching for pointers to N not-freed blocks` and `Checked N bytes`. And, at exit,
the error list and a second `ERROR SUMMARY`.

- The old excerpt took any unindented `==PID==` line for the start of an error, so with `-v`
  it would have quoted the gdbserver block.
- The new excerpt starts an error at an unindented line followed by an `   at 0x` frame.
  With it, the excerpt for each plant again starts at its marker, "Invalid write of size 1"
  or "777 bytes in 1 blocks are definitely lost", and case b holds that in test-memory's
  output.

**The cap (finding 3).** `-v` makes the tighter rule cheap: two awk lines, read from the
`Reading syms from` lines, and one case. Every suite under the fixed gate, in the container:

| Suite | `libp11-kit` read | `libcurl` read | Blocks suppressed |
|---|---|---|---|
| `test-constants`, `test-native` | yes | yes | 1 each |
| the other 12 | no | no | 0 |

- So the rule is keyed on `libp11-kit`, whose constructor loses the block, rather than on
  libcurl. In this container the two agree.
- Its lower bound fires only when a run that loads `libp11-kit` loses no block under
  `newlocale`. That happens only once Guix stops losing it, and no plant can produce it
  (MF19 survives). `d used` holds the same property for `memory-load-curl`.

**`LD_PRELOAD`, which is not a `VALGRIND_` variable.**

- `LD_PRELOAD` named a bump allocator over `mmap` that defines `malloc`, `free`, `calloc`,
  `realloc`, `memalign`, `aligned_alloc` and `posix_memalign`.
- With it, `make test-memory` still failed the leak plant, exit 9, "777 bytes in 1 blocks
  are definitely lost". Valgrind read the library and still intercepted Chez's `malloc`.
- So this attempt found no hole there.

**Cost.**

- `make test-memory`, all 14 suites: 105 s, up from 97 s. Its logs total 192 KB.
- `make check-memory-gate`: 76 s in the container (27 cases), and 57 s with
  `GUIX_ENVIRONMENT` unset (22 cases).

### Valgrind 3.22 and mawk: the fixed recipe in Docker

- The fixed tree ran on Ubuntu 24.04 in Docker, with apt's `valgrind` 3.22.0, `make` 4.3,
  `gcc` 13.3 and mawk. It had no Chez.
- `CHEZ` was a stand-in that ignores its arguments: `/usr/bin/true`, or a C program that
  loses 777 bytes, writes past a 23-byte block, or execs `/bin/true`.
- Each run was `make test-memory MEMORY_SUITES=tests/memory-plant-leak.sps CHEZ=…`. All
  output is in `slice5/fix/docker-gate322.txt`.

```
question: env -u VALGRIND_LIB valgrind -v --command-line-only=yes true → /usr/libexec/valgrind/default.supp
CHEZ=/usr/bin/true            exit 0  test-memory: pass tests/memory-plant-leak.sps
CHEZ=leaky                    exit 2  test-memory: FAIL tests/memory-plant-leak.sps (exit 9, Valgrind's: an error or a definite leak)
                                        ==1850== 777 bytes in 1 blocks are definitely lost in loss record 1 of 1
PLANT=overrun                 exit 2  FAIL … (exit 9 …), excerpt "Invalid write of size 1", "… 0 bytes after a block of size 23 alloc'd"
PLANT=exec                    exit 2  test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind reported no "ERROR SUMMARY: 0 errors from 0 contexts")
VALGRIND_OPTS, $HOME/.valgrindrc, ./.valgrindrc, VALGRIND_LIB, VALGRIND_LAUNCHER: exit 2, each refused by its own line
VALGRIND=… --suppressions=/work/vglib/default.supp:  test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [/work/vglib/default.supp, /usr/libexec/valgrind/default.supp], and the gate allows exactly [cut: 38 more characters]
CHEZ=#!/bin/sh script         exit 2  test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind ran /usr/bin/dash, not /work/wrap, the file CHEZ names)
```

- `CHEZ=true` failed: `command -v true` answers with the shell builtin, so `readlink -f`
  named `./true`. No Chez has a builtin's name. The demo used `/usr/bin/true`.

### Red runs

**The reviewer's bypass, reproduced (R2).** On the old Makefile, `VALGRIND_LIB` at the copy
made `make test-memory` pass the leak plant: `suppressed: 777 bytes in 1 blocks`, exit 0.
It was reproduced first in the working tree, before any edit:
`slice5/fix/red-vglib-bypass.txt`.

**The new cases (R0).** The final script ran against the old Makefile, exit 2:

- 15 cases failed by name, and 12 passed;
- every new case failed but `h ./.valgrindrc`, whose refusal the old recipe already had.
  R1 is that case's red run;
- `d used`, `d leak` and `d more` failed too. The first two no longer add their own `-v`,
  which the recipe now passes. The third's FAIL wording changed.

R0's quote, in the Mutations section below, shows 11 of its 15 `FAILED` lines and the `ok`
line for `h ./.valgrindrc`. The other four are `d used`, `d leak`, `d more` and
`j evidence: a Valgrind that runs another program than the suite fails the suite`.

**`./.valgrindrc` (R1).** The old Makefile with its `./.valgrindrc` arm removed is the edit
the reviewer made, which left check-memory-gate green then. Now the case fails:

```
check-memory-gate: FAILED h options: test-memory refuses to run with a ./.valgrindrc, in a copy of the tree
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: ./.valgrindrc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)
    got:    test-memory: pass tests/memory-plant-leak.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
  the leak plant ran
```

**`d alone`** was written after the first fixes, before the libp11-kit rule. Against that
Makefile, cap one, it failed by name, and `d more` failed on its new wording
(`slice5/fix/red-alone.txt`):

```
check-memory-gate: FAILED d alone: one block lost under newlocale in a run that loads no libcurl, and so no p11-kit, fails the suite
  make test-memory exited 0
    wanted: test-memory: FAIL build/check-memory-gate/alone.sps (exit 0, but Valgrind suppressed 1 blocks, and guix-glibc-locpath covers none in a run that loads no libp11-kit)
    got:    test-memory: pass build/check-memory-gate/alone.sps
```

### Mutations

25 cases ran, each in a fresh copy:

- three red runs on the old Makefile: R0 and R1 are killed, and R2 passes, as the
  reviewer's bypass did;
- 22 runs on the fixed tree. 20 were killed, each with every expected line present. MF16b
  is a control and passed, as it must. MF19 survived; it is the one mutation that no plant
  can reach.

MF14 and MF15 change no gate code. They run the fixed gate against the defect itself: a
wrapper `CHEZ`, and the reviewer's bypass.

| ID | Change | Killed by |
|---|---|---|
| R0 | the new cases, old Makefile | 15 cases `FAILED` by name; `h ./.valgrindrc` ok (its refusal existed) |
| R1 | old Makefile, `./.valgrindrc` arm removed | `h ./.valgrindrc`: the leak plant passed in the copy |
| R2 | reviewer's `VALGRIND_LIB` bypass, old Makefile | as expected: pass, `suppressed: 777 bytes in 1 blocks` |
| MF1 | `VALGRIND_OPTS` refusal dropped | `h VALGRIND_OPTS`: the plant ran (and failed, exit 9: `--command-line-only=yes`) |
| MF2 | `VALGRIND_LIB` refusal dropped | `h VALGRIND_LIB`: the plant ran; the allowlist named the impostor `default.supp` |
| MF3 | refusal of other `VALGRIND_` variables dropped | `h VALGRIND_LAUNCHER`: the plant ran |
| MF4 | `$HOME/.valgrindrc` refusal dropped | `h $HOME/.valgrindrc`: the plant ran |
| MF5 | `./.valgrindrc` refusal dropped | `h ./.valgrindrc`: the plant ran |
| MF6 | `--command-line-only=yes` dropped | both e (argv), `h` late: the allowlist named `everything.supp` |
| MF7 | allowlist dropped | both i: the plant passed |
| MF8 | allowlist widened to a glob (`*/default.supp`) | both i |
| MF9 | evidence requirement dropped | both e (the stand-in passed), all four j |
| MF10 | `ERROR SUMMARY` check dropped | `j execs` passed; `j exec` lost a problem |
| MF11 | check of the program Valgrind ran dropped | `j child` passed; `j exec` lost a problem |
| MF12 | `Command:` check dropped | `j swap` passed |
| MF13 | `-v` dropped | b, d, e: no `Reading syms from` line, so even `after.sps` fails |
| MF14 | `CHEZ` a wrapper script that execs Chez | b overrun, b leak, b fails, every d: "Valgrind ran …bash" |
| MF15 | reviewer's bypass, fixed Makefile | refused: `VALGRIND_LIB is set (…)` |
| MF16 | MF15 with the `VALGRIND_LIB` refusal dropped, CI arm | the allowlist named `…/build/vglib/default.supp` |
| MF16b | MF16, and the question's `env -u VALGRIND_LIB` dropped | control: the plant passed, so `env -u` is what kills MF16 |
| MF17 | rule for runs without `libp11-kit` dropped | `d alone` passed |
| MF18 | rule for runs with `libp11-kit` loosened to at least one | `d more` passed |
| MF19 | rule for runs with `libp11-kit` loosened to at most one | survived: no plant reaches it |

### R0. the new cases against the Makefile as it was before the fixes

**Guards:** each new case fails against the code it was written to change.

**Tree:** the working tree with the Makefile as it was before the fixes.

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d alone: one block lost under newlocale in a run that loads no libcurl, and so no p11-kit, fails the suite
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez, and a Valgrind that runs nothing fails
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez, and a Valgrind that runs nothing fails
check-memory-gate: ok h options: test-memory refuses to run with a ./.valgrindrc, in a copy of the tree
check-memory-gate: FAILED h options: test-memory refuses to run with VALGRIND_LIB set, at a copy of Valgrind's directory whose default.supp hides every leak
check-memory-gate: FAILED h options: test-memory refuses to run with any other VALGRIND_ variable set, VALGRIND_LAUNCHER
check-memory-gate: FAILED h options: a $HOME/.valgrindrc that a suite writes mid-run hides nothing from the next: --command-line-only=yes
check-memory-gate: FAILED i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name
check-memory-gate: FAILED i suppressions: a file named default.supp in place of Valgrind's own fails the leak plant it hides, by name
check-memory-gate: FAILED j evidence: a CHEZ that is a script exec'ing Chez fails the leak plant, which Valgrind never saw
check-memory-gate: FAILED j evidence: a CHEZ that is a script running Chez as a child fails the leak plant, which Valgrind never saw
check-memory-gate: FAILED j evidence: a program that execs away from Valgrind, which then reports nothing, fails
```
(147 more such lines cut.)

### R1. the ./.valgrindrc case against the old Makefile, its ./.valgrindrc arm removed

**Guards:** the ./.valgrindrc refusal now has a standing case: removing it no longer leaves check-memory-gate green.

**Tree:** the working tree with the Makefile as it was before the fixes.

**Mutation:** In `Makefile`:

```diff
 	fi; \
-	for rc in $${HOME:+"$$HOME/.valgrindrc"} ./.valgrindrc; do \
+	for rc in $${HOME:+"$$HOME/.valgrindrc"}; do \
 	  if [ -e "$$rc" ]; then \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
check-memory-gate: FAILED d alone: one block lost under newlocale in a run that loads no libcurl, and so no p11-kit, fails the suite
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez, and a Valgrind that runs nothing fails
    got:    test-memory: pass tests/memory-plant-leak.sps
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez, and a Valgrind that runs nothing fails
check-memory-gate: FAILED h options: test-memory refuses to run with a ./.valgrindrc, in a copy of the tree
check-memory-gate: FAILED h options: test-memory refuses to run with VALGRIND_LIB set, at a copy of Valgrind's directory whose default.supp hides every leak
check-memory-gate: FAILED h options: test-memory refuses to run with any other VALGRIND_ variable set, VALGRIND_LAUNCHER
check-memory-gate: FAILED h options: a $HOME/.valgrindrc that a suite writes mid-run hides nothing from the next: --command-line-only=yes
check-memory-gate: FAILED i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name
```
(153 more such lines cut.)

### R2. the reviewer's VALGRIND_LIB bypass, through make test-memory on the old Makefile

**Guards:** the bypass is real before the fix.

**Tree:** the working tree with the Makefile as it was before the fixes.

**Command** in the container: the reviewer's probe, rebuilt in the copy: `build/vglib` links every file in Valgrind's library directory but `default.supp`, which gains a suppression matching every definite leak (`fun:*` then `...`); then `VALGRIND_LIB=$PWD/build/vglib make test-memory MEMORY_SUITES=tests/memory-plant-leak.sps`, and the log's suppressed line.

**Result:** as expected, exit 0:

```
test-memory: pass tests/memory-plant-leak.sps
test-memory: ran 1, passed 1, failed 0, hung 0
direct: ==974==         suppressed: 777 bytes in 1 blocks
direct: ==974== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 1 from 1)
```

### MF1. the VALGRIND_OPTS refusal dropped

**Guards:** test-memory refuses VALGRIND_OPTS.

**Mutation:** In `Makefile`:

```diff
 	  case $$v in \
-	    VALGRIND_OPTS) why="Valgrind would add it to the gate's options" ;; \
+	    VALGRIND_OPTS) continue ;; \
 	    VALGRIND_LIB) why="Valgrind would take its tool, its preloads and its default.supp from there" ;; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED h options: test-memory refuses to run with VALGRIND_OPTS set
  make test-memory's lines differ:
    wanted: test-memory: VALGRIND_OPTS is set (--suppressions=build/check-memory-gate/everything.supp): Valgrind would add it to the gate's options; unset it (ADR-0014)
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 9, Valgrind's: an error or a definite leak)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
  the leak plant ran
```

### MF2. the VALGRIND_LIB refusal dropped

**Guards:** test-memory refuses VALGRIND_LIB; and, behind it, the allowlist names the impostor default.supp.

**Mutation:** In `Makefile`:

```diff
 	    VALGRIND_OPTS) why="Valgrind would add it to the gate's options" ;; \
-	    VALGRIND_LIB) why="Valgrind would take its tool, its preloads and its default.supp from there" ;; \
+	    VALGRIND_LIB) continue ;; \
 	    *) why="Valgrind reads its VALGRIND_ variables, and no command line shows them" ;; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED h options: test-memory refuses to run with VALGRIND_LIB set, at a copy of Valgrind's directory whose default.supp hides every leak
  make test-memory's lines differ:
    wanted: test-memory: VALGRIND_LIB is set (…/slice5/fix/runs/MF2/build/check-memory-gate/vglib): Valgrind would take its tool, its preloads and its default.supp from there; unset it (ADR-0014)
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [tests/guix-glibc-locpath.supp, …/slice5/fix/runs/MF2/build/check-memory-gate/vglib/default.supp], and the gate allows exactly [test [cut: 218 more characters]
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
  the leak plant ran
  | test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [tests/guix-glibc-locpath.supp, …/slice5/fix/runs/MF2/build/check-memory-gate/vglib/default.supp], and the gate allows exactly [tests/guix-g [cut: 210 more characters]
```

### MF3. the refusal of any other VALGRIND_ variable dropped

**Guards:** test-memory refuses every VALGRIND_ variable, not only the two it names.

**Mutation:** In `Makefile`:

```diff
 	    VALGRIND_LIB) why="Valgrind would take its tool, its preloads and its default.supp from there" ;; \
-	    *) why="Valgrind reads its VALGRIND_ variables, and no command line shows them" ;; \
+	    *) continue ;; \
 	  esac; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED h options: test-memory refuses to run with any other VALGRIND_ variable set, VALGRIND_LAUNCHER
  make test-memory's lines differ:
    wanted: test-memory: VALGRIND_LAUNCHER is set (…/slice5/fix/runs/MF3/build/check-memory-gate/valgrind-stub): Valgrind reads its VALGRIND_ variables, and no command line shows them; unset it (ADR-0014)
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 9, Valgrind's: an error or a definite leak)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
  the leak plant ran
```

### MF4. the $HOME/.valgrindrc refusal dropped

**Guards:** test-memory refuses $HOME/.valgrindrc.

**Mutation:** In `Makefile`:

```diff
 	done; \
-	for rc in $${HOME:+"$$HOME/.valgrindrc"} ./.valgrindrc; do \
+	for rc in ./.valgrindrc; do \
 	  if [ -e "$$rc" ]; then \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED h options: test-memory refuses to run with a $HOME/.valgrindrc
  make test-memory's lines differ:
    wanted: test-memory: …/slice5/fix/runs/MF4/build/check-memory-gate/home/.valgrindrc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 9, Valgrind's: an error or a definite leak)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
  the leak plant ran
```

### MF5. the ./.valgrindrc refusal dropped

**Guards:** test-memory refuses ./.valgrindrc.

**Mutation:** In `Makefile`:

```diff
 	done; \
-	for rc in $${HOME:+"$$HOME/.valgrindrc"} ./.valgrindrc; do \
+	for rc in $${HOME:+"$$HOME/.valgrindrc"}; do \
 	  if [ -e "$$rc" ]; then \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED h options: test-memory refuses to run with a ./.valgrindrc, in a copy of the tree
  make test-memory's lines differ:
    wanted: test-memory: ./.valgrindrc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 9, Valgrind's: an error or a definite leak)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
  the leak plant ran
```

### MF6. --command-line-only=yes dropped from the suite's command

**Guards:** no .valgrindrc reaches Valgrind, even one written after the refusals ran.

**Mutation:** In `Makefile`:

```diff
 	  echo "=== $$t"; \
-	  $(TIMEOUT) --foreground $(MEMORY_TIMEOUT) $(VALGRIND) -v --command-line-only=yes --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRO [cut: 109 more characters]
+	  $(TIMEOUT) --foreground $(MEMORY_TIMEOUT) $(VALGRIND) -v --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$( [cut: 85 more characters]
 	  rc=$$?; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez, and a Valgrind that runs nothing fails
  the stand-in for Valgrind was handed other commands:
    wanted: -v
    wanted: --command-line-only=yes
    wanted: true
    wanted: --
    wanted: parent: timeout
    wanted: -v
    wanted: --command-line-only=yes
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez, and a Valgrind that runs nothing fails
check-memory-gate: FAILED h options: a $HOME/.valgrindrc that a suite writes mid-run hides nothing from the next: --command-line-only=yes
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files […/slice5/fix/runs/MF6/build/check-memory-gate/everything.supp, tests/guix-glibc-locpath.supp, /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh [cut: 306 more characters]
```
(70 more such lines cut.)

### MF7. the allowlist dropped: any suppressions file passes

**Guards:** a suppressions file the gate does not pass fails the suite.

**Mutation:** In `Makefile`:

```diff
 	            why[++n] = "Valgrind reported no \"ERROR SUMMARY: 0 errors from 0 contexts\""; \
-	          if (read != allowed) why[++n] = "Valgrind read the suppressions files [" read "], and the gate allows exactly [" allowed "]"; \
 	          if (guix != "" && p11 && blocks + 0 != 1) \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [build/check-memory-gate/vglib/default.supp, tests/guix-glibc-locpath.supp, /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.2 [cut: 287 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind suppressed 1 blocks, and guix-glibc-locpath covers none in a run that loads no libp11-kit)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
check-memory-gate: FAILED i suppressions: a file named default.supp in place of Valgrind's own fails the leak plant it hides, by name
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [build/check-memory-gate/vglib/default.supp, tests/guix-glibc-locpath.supp], and the gate allows exactly [tests/guix-glibc-locpath.s [cut: 196 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind suppressed 1 blocks, and guix-glibc-locpath covers none in a run that loads no libp11-kit)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
```

### MF8. the allowlist widened to a glob: its own file, or any file named default.supp

**Guards:** Valgrind's own default.supp is matched by its whole path, not its name.

**Mutation:** In `Makefile`:

```diff
 	            why[++n] = "Valgrind reported no \"ERROR SUMMARY: 0 errors from 0 contexts\""; \
-	          if (read != allowed) why[++n] = "Valgrind read the suppressions files [" read "], and the gate allows exactly [" allowed "]"; \
+	          for (k = split(read, rs, ", "); k > 0; k--) if (rs[k] != "$(MEMORY_SUPPRESSION_FILE)" && rs[k] !~ /\/default\.supp$$/) bad = 1; \
+	          if (bad) why[++n] = "Valgrind read the suppressions files [" read "], and the gate allows exactly [" allowed "]"; \
 	          if (guix != "" && p11 && blocks + 0 != 1) \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [build/check-memory-gate/vglib/default.supp, tests/guix-glibc-locpath.supp, /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.2 [cut: 287 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind suppressed 1 blocks, and guix-glibc-locpath covers none in a run that loads no libp11-kit)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
check-memory-gate: FAILED i suppressions: a file named default.supp in place of Valgrind's own fails the leak plant it hides, by name
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [build/check-memory-gate/vglib/default.supp, tests/guix-glibc-locpath.supp], and the gate allows exactly [tests/guix-glibc-locpath.s [cut: 196 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind suppressed 1 blocks, and guix-glibc-locpath covers none in a run that loads no libp11-kit)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
```

### MF9. the evidence requirement dropped: no Command, program or summary check

**Guards:** a pass needs the log to show that Valgrind ran Chez on the suite and reported 0 errors.

**Mutation:** In `Makefile`:

```diff
 	          blocks = $$0; sub(/ blocks$$/, "", blocks); sub(/.* in /, "", blocks); gsub(/,/, "", blocks) } \
-	        END { if (pid == "") { print "the log has no Valgrind \"Command:\" line"; exit } \
-	          if (got != cmd) why[++n] = "Valgrind\047s Command: line is \"" got "\", not \"" cmd "\""; \
-	          if (ran == "") why[++n] = "the log has no \"Reading syms from\" line, so it does not show what Valgrind ran"; \
-	          else if (ran != chez) why[++n] = "Valgrind ran " ran ", not " chez ", the file CHEZ names"; \
-	          if (summary !~ /^ERROR SUMMARY: 0 errors from 0 contexts( |$$)/) \
-	            why[++n] = "Valgrind reported no \"ERROR SUMMARY: 0 errors from 0 contexts\""; \
+	        END { if (pid == "") exit; \
 	          if (read != allowed) why[++n] = "Valgrind read the suppressions files [" read "], and the gate allows exactly [" allowed "]"; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez, and a Valgrind that runs nothing fails
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but the log has no Valgrind "Command:" line)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass tests/memory-plant-leak.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez, and a Valgrind that runs nothing fails
check-memory-gate: FAILED j evidence: a CHEZ that is a script exec'ing Chez fails the leak plant, which Valgrind never saw
check-memory-gate: FAILED j evidence: a CHEZ that is a script running Chez as a child fails the leak plant, which Valgrind never saw
check-memory-gate: FAILED j evidence: a program that execs away from Valgrind, which then reports nothing, fails
check-memory-gate: FAILED j evidence: a Valgrind that runs another program than the suite fails the suite
```
(30 more such lines cut.)

### MF10. the ERROR SUMMARY check dropped

**Guards:** a pass needs Valgrind to have reported 0 errors from 0 contexts.

**Mutation:** In `Makefile`:

```diff
 	          else if (ran != chez) why[++n] = "Valgrind ran " ran ", not " chez ", the file CHEZ names"; \
-	          if (summary !~ /^ERROR SUMMARY: 0 errors from 0 contexts( |$$)/) \
-	            why[++n] = "Valgrind reported no \"ERROR SUMMARY: 0 errors from 0 contexts\""; \
 	          if (read != allowed) why[++n] = "Valgrind read the suppressions files [" read "], and the gate allows exactly [" allowed "]"; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED j evidence: a CHEZ that is a script exec'ing Chez fails the leak plant, which Valgrind never saw
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind ran /gnu/store/vhkg4avy9zf0kj70dcsmfpymnllkjq1y-bash-5.2.37/bin/bash, not …/slice5/fix/runs/MF10/build/check-memory-gate/chez-exec, the file CHEZ names; Valgrin [cut: 56 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind ran /gnu/store/vhkg4avy9zf0kj70dcsmfpymnllkjq1y-bash-5.2.37/bin/bash, not …/slice5/fix/runs/MF10/build/check-memory-gate/chez-exec, the file CHEZ names)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
check-memory-gate: FAILED j evidence: a program that execs away from Valgrind, which then reports nothing, fails
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/execs.sps (exit 0, but Valgrind reported no "ERROR SUMMARY: 0 errors from 0 contexts")
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass build/check-memory-gate/execs.sps
```
(1 more such lines cut.)

### MF11. the check of the program Valgrind ran dropped

**Guards:** a pass needs Valgrind to have run the file CHEZ names, not a shell.

**Mutation:** In `Makefile`:

```diff
 	          if (got != cmd) why[++n] = "Valgrind\047s Command: line is \"" got "\", not \"" cmd "\""; \
-	          if (ran == "") why[++n] = "the log has no \"Reading syms from\" line, so it does not show what Valgrind ran"; \
-	          else if (ran != chez) why[++n] = "Valgrind ran " ran ", not " chez ", the file CHEZ names"; \
 	          if (summary !~ /^ERROR SUMMARY: 0 errors from 0 contexts( |$$)/) \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED j evidence: a CHEZ that is a script exec'ing Chez fails the leak plant, which Valgrind never saw
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind ran /gnu/store/vhkg4avy9zf0kj70dcsmfpymnllkjq1y-bash-5.2.37/bin/bash, not …/slice5/fix/runs/MF11/build/check-memory-gate/chez-exec, the file CHEZ names; Valgrin [cut: 56 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind reported no "ERROR SUMMARY: 0 errors from 0 contexts")
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
check-memory-gate: FAILED j evidence: a CHEZ that is a script running Chez as a child fails the leak plant, which Valgrind never saw
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind ran /gnu/store/vhkg4avy9zf0kj70dcsmfpymnllkjq1y-bash-5.2.37/bin/bash, not …/slice5/fix/runs/MF11/build/check-memory-gate/chez-child, the file CHEZ names)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass tests/memory-plant-leak.sps
```
(1 more such lines cut.)

### MF12. the Command: line check dropped

**Guards:** a pass needs Valgrind to have run this suite.

**Mutation:** In `Makefile`:

```diff
 	        END { if (pid == "") { print "the log has no Valgrind \"Command:\" line"; exit } \
-	          if (got != cmd) why[++n] = "Valgrind\047s Command: line is \"" got "\", not \"" cmd "\""; \
 	          if (ran == "") why[++n] = "the log has no \"Reading syms from\" line, so it does not show what Valgrind ran"; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED j evidence: a Valgrind that runs another program than the suite fails the suite
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind's Command: line is "/gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/bin/scheme --libdirs src:tests:build/scheme-libs --program build/check-memory-gate/after [cut: 152 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass tests/memory-plant-leak.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
```

### MF13. -v dropped from the suite's command

**Guards:** the evidence and the allowlist read lines only -v prints.

**Mutation:** In `Makefile`:

```diff
 	  echo "=== $$t"; \
-	  $(TIMEOUT) --foreground $(MEMORY_TIMEOUT) $(VALGRIND) -v --command-line-only=yes --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRO [cut: 109 more characters]
+	  $(TIMEOUT) --foreground $(MEMORY_TIMEOUT) $(VALGRIND) --command-line-only=yes --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONME [cut: 106 more characters]
 	  rc=$$?; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-overrun: test-memory names tests/memory-plant-overrun.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
    got:    test-memory: FAIL build/check-memory-gate/after.sps (exit 0, but the log has no "Reading syms from" line, so it does not show what Valgrind ran; Valgrind read the suppressions files [], and the gate allows exactly [tests/guix-gl [cut: 109 more characters]
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
check-memory-gate: FAILED b fails: test-memory names a program that exits 1 FAIL, with its exit and last lines, and runs the suite after it
check-memory-gate: FAILED d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
check-memory-gate: FAILED d alone: one block lost under newlocale in a run that loads no libcurl, and so no p11-kit, fails the suite
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez, and a Valgrind that runs nothing fails
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and tests/guix-glibc-locpath.supp, then Chez, and a Valgrind that runs nothing fails
check-memory-gate: FAILED h options: a $HOME/.valgrindrc that a suite writes mid-run hides nothing from the next: --command-line-only=yes
check-memory-gate: FAILED i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name
```
(153 more such lines cut.)

### MF14. CHEZ pointed at a wrapper script that execs the real binary (MG22, again)

**Guards:** Valgrind checks Chez itself: a wrapper hides it (AGENTS.md).

**Command** in the container: write `build/chez-wrapper`, a shell script that execs `$REAL_CHEZ`, then `REAL_CHEZ=$CHEZ make check-memory-gate CHEZ=build/chez-wrapper`.

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-overrun: test-memory names tests/memory-plant-overrun.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
    got:    test-memory: FAIL tests/memory-plant-overrun.sps (exit 0, but Valgrind ran /gnu/store/vhkg4avy9zf0kj70dcsmfpymnllkjq1y-bash-5.2.37/bin/bash, not …/slice5/fix/runs/MF14/build/chez-wrapper, the file CHEZ names; Valgrind reported n [cut: 44 more characters]
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
check-memory-gate: FAILED b fails: test-memory names a program that exits 1 FAIL, with its exit and last lines, and runs the suite after it
check-memory-gate: FAILED d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block
check-memory-gate: FAILED d needed: without the suppression, the same run fails on the one block lost under compute_locale_search_path
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
check-memory-gate: FAILED d alone: one block lost under newlocale in a run that loads no libcurl, and so no p11-kit, fails the suite
check-memory-gate: FAILED h options: test-memory refuses to run with a ./.valgrindrc, in a copy of the tree
check-memory-gate: FAILED h options: a $HOME/.valgrindrc that a suite writes mid-run hides nothing from the next: --command-line-only=yes
check-memory-gate: FAILED i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name
```
(97 more such lines cut.)

### MF15. the reviewer's VALGRIND_LIB bypass, through make test-memory on the fixed Makefile

**Guards:** the bypass is refused.

**Command** in the container: the reviewer's probe, rebuilt in the copy: `build/vglib` links every file in Valgrind's library directory but `default.supp`, which gains a suppression matching every definite leak (`fun:*` then `...`); then `VALGRIND_LIB=$PWD/build/vglib make test-memory MEMORY_SUITES=tests/memory-plant-leak.sps`, and the log's suppressed line.

**Result:** killed, exit 2:

```
test-memory: VALGRIND_LIB is set (…/slice5/fix/runs/MF15/build/vglib): Valgrind would take its tool, its preloads and its default.supp from there; unset it (ADR-0014)
```

### MF16. the reviewer's bypass, with the VALGRIND_LIB refusal dropped

**Guards:** behind the refusal, the allowlist names the impostor default.supp.

**Mutation:** In `Makefile`:

```diff
 	    VALGRIND_OPTS) why="Valgrind would add it to the gate's options" ;; \
-	    VALGRIND_LIB) why="Valgrind would take its tool, its preloads and its default.supp from there" ;; \
+	    VALGRIND_LIB) continue ;; \
 	    *) why="Valgrind reads its VALGRIND_ variables, and no command line shows them" ;; \
```

**Command** in the container: as MF15, with `GUIX_ENVIRONMENT` unset for make, as in CI, where no suppression is passed and no block count is held.

**Result:** killed, exit 2:

```
test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files […/slice5/fix/runs/MF16/build/vglib/default.supp], and the gate allows exactly [/gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.27.0/libe [cut: 27 more characters]
  log: build/memory/memory-plant-leak.log
  ==985==    definitely lost: 0 bytes in 0 blocks
  ==985==         suppressed: 777 bytes in 1 blocks
  ==985== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 1 from 1)
test-memory: ran 1, passed 0, failed 1, hung 0
direct: ==985==         suppressed: 777 bytes in 1 blocks
direct: ==985== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 1 from 1)
direct: --985-- used_suppression:      1 everything …/slice5/fix/runs/MF16/build/vglib/default.supp:1603 suppressed: 777 bytes in 1 blocks
direct: ==985== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 1 from 1)
```

### MF16b. MF16, with the env -u VALGRIND_LIB of test-memory's question also dropped (the control)

**Guards:** the allowlist names the impostor in MF16 because the question of Valgrind's own default.supp ignores VALGRIND_LIB.

**Mutation:** In `Makefile`:

```diff
 	    VALGRIND_OPTS) why="Valgrind would add it to the gate's options" ;; \
-	    VALGRIND_LIB) why="Valgrind would take its tool, its preloads and its default.supp from there" ;; \
+	    VALGRIND_LIB) continue ;; \
 	    *) why="Valgrind reads its VALGRIND_ variables, and no command line shows them" ;; \
...
 	[ $$refused -eq 0 ] || exit 1; \
-	vgdefault=$$(env -u VALGRIND_LIB $(firstword $(VALGRIND)) -v --command-line-only=yes true 2>&1 | sed -n 's/^--[0-9]*-- Reading suppressions file: //p'); \
+	vgdefault=$$($(firstword $(VALGRIND)) -v --command-line-only=yes true 2>&1 | sed -n 's/^--[0-9]*-- Reading suppressions file: //p'); \
 	case $$vgdefault in \
```

**Command** in the container: as MF15, with `GUIX_ENVIRONMENT` unset for make, as in CI, where no suppression is passed and no block count is held.

**Result:** as expected, exit 0:

```
test-memory: pass tests/memory-plant-leak.sps
test-memory: ran 1, passed 1, failed 0, hung 0
direct: ==985==         suppressed: 777 bytes in 1 blocks
direct: ==985== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 1 from 1)
direct: --985-- used_suppression:      1 everything …/slice5/fix/runs/MF16b/build/vglib/default.supp:1603 suppressed: 777 bytes in 1 blocks
direct: ==985== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 1 from 1)
```

### MF17. the rule for runs without libp11-kit dropped

**Guards:** in a Guix environment, a run that loads no libp11-kit may have nothing suppressed.

**Mutation:** In `Makefile`:

```diff
 	            why[++n] = "Valgrind suppressed " (blocks + 0) " blocks, and guix-glibc-locpath covers exactly one, lost when libp11-kit loads"; \
-	          if (guix != "" && !p11 && blocks + 0 != 0) \
-	            why[++n] = "Valgrind suppressed " (blocks + 0) " blocks, and guix-glibc-locpath covers none in a run that loads no libp11-kit"; \
 	          for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "; " : ""), why[i]; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d alone: one block lost under newlocale in a run that loads no libcurl, and so no p11-kit, fails the suite
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/alone.sps (exit 0, but Valgrind suppressed 1 blocks, and guix-glibc-locpath covers none in a run that loads no libp11-kit)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass build/check-memory-gate/alone.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
  test-memory's own output, the program's last lines: no "alone: newlocale answered 0" in build/check-memory-gate/out
check-memory-gate: FAILED i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [build/check-memory-gate/vglib/default.supp, tests/guix-glibc-locpath.supp, /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.2 [cut: 287 more characters]
check-memory-gate: FAILED i suppressions: a file named default.supp in place of Valgrind's own fails the leak plant it hides, by name
```
(8 more such lines cut.)

### MF18. the rule for runs with libp11-kit loosened to at least one block

**Guards:** in a Guix environment, a run that loads libp11-kit may have one block suppressed, no more.

**Mutation:** In `Makefile`:

```diff
 	          if (read != allowed) why[++n] = "Valgrind read the suppressions files [" read "], and the gate allows exactly [" allowed "]"; \
-	          if (guix != "" && p11 && blocks + 0 != 1) \
+	          if (guix != "" && p11 && blocks + 0 < 1) \
 	            why[++n] = "Valgrind suppressed " (blocks + 0) " blocks, and guix-glibc-locpath covers exactly one, lost when libp11-kit loads"; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/more.sps (exit 0, but Valgrind suppressed 2 blocks, and guix-glibc-locpath covers exactly one, lost when libp11-kit loads)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass build/check-memory-gate/more.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
  test-memory's own output, the program's last lines: no "more: newlocale answered 0" in build/check-memory-gate/out
  test-memory's own output, the suppressed total: no " bytes in 2 blocks" in build/check-memory-gate/out
```

### MF19. the rule for runs with libp11-kit loosened to at most one block

**Guards:** in a Guix environment, a run that loads libp11-kit must have its one block suppressed: no plant can make it lose none.

**Mutation:** In `Makefile`:

```diff
 	          if (read != allowed) why[++n] = "Valgrind read the suppressions files [" read "], and the gate allows exactly [" allowed "]"; \
-	          if (guix != "" && p11 && blocks + 0 != 1) \
+	          if (guix != "" && p11 && blocks + 0 > 1) \
 	            why[++n] = "Valgrind suppressed " (blocks + 0) " blocks, and guix-glibc-locpath covers exactly one, lost when libp11-kit loads"; \
```

**Result:** survived, exit 0, as expected:

```
check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 27 cases
```

No plant can kill it. The lower bound fires only in a Guix run that reads `libp11-kit` and
suppresses no block, and every such run loses the block. The records should choose: keep the
lower bound as a check no case can fail, held in practice by `d used`, or drop it to "at most
one".

### Clean rerun

Every command in item 2 ran on the final working tree, in the container, one after another
(`slice5/fix/final-item2.txt`; each whole output is beside it as `final-*.txt`):

```
make test-memory: exit 0 in 105s; test-memory: ran 14, passed 14, failed 0, hung 0
make check-memory-gate: exit 0 in 76s; check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 27 cases
env -u GUIX_ENVIRONMENT make check-memory-gate: exit 0 in 57s; check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 22 cases
make test: exit 0 in 12s; test: ran 14, passed 14, failed 0, hung 0
make check-help: exit 0 in 0s;
```

With `GUIX_ENVIRONMENT` unset, the run said `check-memory-gate: skipped d: GUIX_ENVIRONMENT is
unset, so test-memory passes no suppression here, and there is none to hold`.

The mutations ran on a frozen copy of this tree, and the working tree did not change after it
was frozen. An earlier pass of the same driver had four expected lines wrong (MF2, MF6, MF16,
MF16b). Each named the wrong layer: the allowlist, or the libp11-kit rule in Guix, caught the
mutant before the line the driver waited for. Each was fixed and every case rerun. That pass is
kept in `slice5/fix/first-pass/`.

## Review fixes: CI

Evidence for the fixes to the review findings on M0 slice 5's CI part ([harness plan](2026-10-04-harness-plan.md)
§4; [ADR-0003](decisions/0003-libcurl-floor-7-85.md), [ADR-0014](decisions/0014-valgrind-memory-gate.md),
[ADR-0016](decisions/0016-floors-have-one-source.md)). The part is:

- `.github/workflows/ci.yml`: the memory job runs on every event the workflow triggers on, and the
  `memory-decision` job, its notice and the `memory` dispatch input are gone; a run that is not a pull
  request's has a concurrency group of its own, its run id, so no push to main or tag waits behind another
  run or is cancelled; `floor-disabled-apis` is replaced by `floor-disabled-api`, a matrix of two lanes, one
  libcurl with only its options API disabled and one with only its header API disabled, each with its own
  cached curl; every job that may build Chez from cold has a 60-minute timeout; every `uses:` is pinned to
  a full commit SHA with its tag in a comment, and the main job's first step checks it;
- `scripts/ci/expect-missing-api.sh`, new: the lanes' step. `make build` must exit non-zero and print
  preflight's refusal block, six whole lines in order, with the lane's entry point on its detail line;
- `scripts/ci/check-action-pins.sh`, new: every `uses:` line under a directory names a full commit SHA and
  its tag in a comment;
- `(floors)`'s `workflows-problems`, which replaces `workflow-problems`, and `check-floors`, which takes the
  workflow directory and every file under it; `tests/check-floors.sps`, which reads that directory whole;
  the Makefile's `check-floors` recipe, which passes `.github/workflows`; the new and changed rows of
  `tests/test-check-floors.sps`; each fixture's `ci.yml` moved to `workflows/ci.yml`, and four new fixtures;
- comments in `scripts/ci/build-curl.sh` and `packaging/debian-prereqs.txt` that named the old lane.

The pins were resolved on the host with `git ls-remote`: `actions/checkout` `v7.0.1` (and `v7`) is
`3d3c42e5aac5ba805825da76410c181273ba90b1`, `actions/cache` `v6.1.0` (and `v6`) is
`55cc8345863c7cc4c66a329aec7e433d2d1c52a9`. Neither tag is annotated: `ls-remote` lists no `^{}` line. A
shallow fetch of each SHA shows a commit (2026-07-17, "prep v7.0.1 release"; 2026-06-23), and the cache
commit holds `restore/action.yml` and `save/action.yml`, with the inputs and outputs the workflow uses.

A driver in the session scratchpad ran every mutation, as the CI part's did. It froze a snapshot of the
tree, without `build/`, and gave each mutation a fresh copy. It applied each by exact-text replacement,
aborting unless the target occurred exactly once, and refused a mutation whose diff was empty. It touched
the copy's `manifest.scm` and ran container commands through the copy's own `scripts/guix-env`, so the
container saw only that copy; the pin check and actionlint ran in the copy on the host. A mutation counts as
killed only when the command exits non-zero and every expected line appears whole in its output: the case's
`FAIL <test name>` lines and `test: FAIL tests/test-check-floors.sps (exit 1)` and `direct: test-check-floors
exit 1`, or the `check-floors:`, `check-action-pins:` or `CELL` lines. For actionlint, each expected message
must appear within a line, the rest of its line being the tool's own.

**Result** quotes at most 12 output lines per run: the first line each expectation matches (a `FAIL` with its
expected and actual lines), then other `FAIL` lines with theirs, then `check-`, `test: FAIL`, `direct:`,
`make:` and exit lines in output order. It says how many wanted lines were cut. A diff keeps one line of
context, and `...` sets its hunks apart. A diff line longer than 200 characters, and an output line longer
than 240, is cut, and says how much was cut. `<fixci>` is `scratchpad/slice5/fixci`, `<run>` a mutation's
copy and `<lanes>` the copy the lanes ran in. The driver's first full pass captured each command's stdout and
stderr apart, which put the exit lines out of order; every run quoted here is from the last full pass, with the
two merged, of the final snapshot, taken after one comment in `tests/check-floors.sps` was rewrapped. Every
pass killed every mutation.

Cases are named `WF` (the real workflow directory and the Makefile, under `make test`'s `check-floors`),
`FL` (the rules in `(floors)`), `PF` (the program `check-floors.sps`), `LN` (the lanes' refusal check),
`PN` (the pin check) and `AL` (actionlint).

### Red runs

**R1, the floors suite before the code.** The new and changed rows of `tests/test-check-floors.sps` and
the fixtures, each case's workflows now in a `workflows/` directory, were written first, and the suite was
run directly against the unchanged `(floors)` and `tests/check-floors.sps`. 109 tests failed and 122 passed:
`check-floors` took a text where the rows now hand it a list of files, and the program read the directory
it was given as a file:

```
FAIL workflows: the env lines moved to a second workflow: missing from ci.yml, and literals there
  expected: (returned ("W/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W/ci.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but must appear once" "W/release.yml: line 2 c [cut: 250 more characters]
  actual:   (raised "Exception in string->list: ((\"W/ci.yml\" \"name: CI\\n\\non:\\n  pull_request:\\n\\njobs:\\n  main:\\n    runs-on: ubuntu-24.04\\n    steps:\\n      - run: make build\\n\") (\"W/release.yml\" \"env:\\n  CHEZ_VERSION: \ [cut: 76 more characters]
FAIL workflows-second-literal: a second workflow beside ci.yml writes the Chez floor in a step
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-second-literal/workflows/release.yml: line 11 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of tests/fixtures/floors/workflows-second- [cut: 74 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/workflows-second-literal/workflows: it cannot be read: Exception in get-string-all: failed on #<binary input port tests/fixtures/floors/workflows-second-literal/workflows>: is a directo [cut: 42 more characters]
FAIL an empty workflow directory: named, once, and nothing else
  expected: (returned same)
  actual:   (returned (got (1 "" "check-floors: /tmp/curl-testing.DhlI9t: it cannot be read: Exception in get-string-all: failed on #<binary input port /tmp/curl-testing.DhlI9t>: is a directory\ncheck-floors: FAILED (problems: 1)\n") want ( [cut: 160 more characters]
# of expected passes      122
# of unexpected failures  109
suite-exit-status: exit 1 (pass 122, fail 109, xpass 0): a suite needs a pass, and no fail or xpass
direct: test-check-floors exit 1
```

**R2, the pin check on the workflow as it was.** `scripts/ci/check-action-pins.sh` was run on
`.github/workflows` before any pin was changed. It named all 19 `uses:` lines and exited 1 (16 of them
cut here):

```
check-action-pins: .github/workflows/ci.yml:70:      - uses: actions/checkout@v7
check-action-pins: .github/workflows/ci.yml:94:        uses: actions/cache/restore@v6
check-action-pins: .github/workflows/ci.yml:105:        uses: actions/cache/save@v6
check-action-pins: 19 of 19 uses: lines name no full commit SHA with its tag in a comment, as uses: OWNER/REPO@<40 hex digits> # vTAG
exit 1
```

Then on an empty directory, a missing one, a directory whose one file has no `uses:` line, and with no
argument, one run each:

```
check-action-pins: ../pinprobe/empty holds no file
exit 1
check-action-pins: ../pinprobe/none is not a directory
exit 1
check-action-pins: no file under ../pinprobe/nouses has a uses: line, so nothing was checked
exit 1
usage: check-action-pins.sh DIR
exit 2
```

**R3, the refusal check's first runs** are the lanes' runs below: it fails each lane's check on the other
lane's library, and on the Guix profile's libcurl, which `make build` accepts.

### The disabled-API lanes, run locally

Two curls 7.85.0, each with one API disabled, were built in the Guix container, out of tree from the
release tarball (sha256 `88b54a6d…be6`, checked on the host, where it was unpacked: the container has no
network and no `tar`), with `--prefix=… --with-openssl --disable-static` and the one flag. Their configure
summaries:

```
built no-options (--disable-get-easy-options): libcurl 7.85.0, OpenSSL v3+
  Headers API:      enabled (--disable-headers-api)
built no-headers (--disable-headers-api): libcurl 7.85.0, OpenSSL v3+
  Headers API:      no      (--enable-headers-api)
exit 0
```

The same two were built in Docker `ubuntu:24.04` through `scripts/ci/build-curl.sh` itself, as the lanes
call it, after installing `packaging/debian-prereqs.txt`. A C program against each build's own header and
library shows each lacks exactly its one API (`curl_easy_header` answers 3, `CURLHE_NOHEADERS`, where the
header API is built in, and 7, `CURLHE_NOT_BUILT_IN`, where it is not):

```
=== Ubuntu 24.04.5 LTS
=== build-curl.sh 7.85.0 /out/curl-no-options --disable-get-easy-options
build-curl.sh: curl 7.85.0 built into /out/curl-no-options (OpenSSL v3+)
libcurl 7.85.0, OpenSSL/3.0.13: curl_easy_option_by_name("URL") NULL; curl_easy_header 3
=== build-curl.sh 7.85.0 /out/curl-no-headers --disable-headers-api
build-curl.sh: curl 7.85.0 built into /out/curl-no-headers (OpenSSL v3+)
libcurl 7.85.0, OpenSSL/3.0.13: curl_easy_option_by_name("URL") non-NULL; curl_easy_header 7
exit 0
```

`make build`, through the container with the Guix Chez 10.4.0 and `CHEZ_CURL_LIBCURL` naming each library,
refused both as `missing-api`, by different probes. The whole block preflight prints, for the options
library (the header library's differs in its path, `detail: curl_easy_header` and its remedy):

```
chez-curl: libcurl refused
(reason . missing-api)
  path:       <lanes>/build/curl/no-options/lib/libcurl.so.4
  source:     override
  detail:     curl_easy_option_by_name
  version:    7.85.0
  TLS:        OpenSSL/3.5.7
  features:   ssl ntlm asynchdns largefile tlsauth-srp ntlm-wb unix-sockets https-proxy altsvc hsts threadsafe
  candidates: none
  remedy:     libcurl was built without its options API (--disable-get-easy-options); name another with CHEZ_CURL_LIBCURL
make: *** [Makefile:198: build] Error 1
make build exit 2
```

`build/lanes-matrix.sh` runs `scripts/ci/expect-missing-api.sh`, as each lane's step runs it, in five
cells: each lane's check on its own library, which must pass; on the other lane's library, which must fail;
and the options lane's check on the profile's libcurl, which `make build` accepts, which must fail. Every
cell came out as it must. The failing cells show the diff from the required block to the printed one:
the detail line, and nothing else:

```
CELL ok options lane on the no-options library: exit 0, pass (must pass)
    expect-missing-api: make build exited 2, refusing <lanes>/build/curl/no-options/lib/libcurl.so.4 at 7.85.0 as missing-api, naming curl_easy_option_by_name
CELL ok options lane on the no-headers library: exit 1, fail (must fail)
    @@ -2,5 +2,5 @@
    -  detail:     curl_easy_option_by_name
    +  detail:     curl_easy_header
    ::error::expect-missing-api: make build exited 2, but did not refuse <lanes>/build/curl/no-headers/lib/libcurl.so.4 at 7.85.0 as missing-api, naming curl_easy_option_by_name: the diff above runs from what must be printed to what was
CELL ok header lane on the no-headers library: exit 0, pass (must pass)
    expect-missing-api: make build exited 2, refusing <lanes>/build/curl/no-headers/lib/libcurl.so.4 at 7.85.0 as missing-api, naming curl_easy_header
CELL ok header lane on the no-options library: exit 1, fail (must fail)
    @@ -2,5 +2,5 @@
    -  detail:     curl_easy_header
    +  detail:     curl_easy_option_by_name
    ::error::expect-missing-api: make build exited 2, but did not refuse <lanes>/build/curl/no-options/lib/libcurl.so.4 at 7.85.0 as missing-api, naming curl_easy_header: the diff above runs from what must be printed to what was
CELL ok options lane on the profile's libcurl, which make build accepts: exit 1, fail (must fail)
    ::error::expect-missing-api: make build accepted /gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/lib/libcurl.so.4, which it must refuse as missing-api, naming curl_easy_option_by_name
lanes-matrix: every cell as it must be
exit 0
```

### Baseline

Everything written. `make test` exited 0, `check-floors` naming the files it read:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: ran 14, passed 14, failed 0, hung 0
make test exit 0
```

### Mutations

27 mutations ran, and all 27 were killed, each with every expected line present. `test-check-floors` was the only suite to fail, under each FL and PF case. `make test` stopped at `check-floors`, before any suite, under WF1 to WF5.

### WF1. the env lines moved from ci.yml to another workflow file

**Guards:** the two env lines are in ci.yml, and no other workflow file writes a floor, an env line included.

**Mutation:** In `.github/workflows/ci.yml`, `.github/workflows/floors.yml`:

```diff
 env:
-  CHEZ_VERSION: "10.4.0"
-  CURL_FLOOR_VERSION: "7.85.0"
 
...
+name: Floors
+on: workflow_dispatch
+env:
+  CHEZ_VERSION: "10.4.0"
+  CURL_FLOOR_VERSION: "7.85.0"
+jobs: {}
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: .github/workflows/ci.yml: the line "  CHEZ_VERSION: \"10.4.0\"" appears 0 times, but must appear once
check-floors: .github/workflows/ci.yml: the line "  CURL_FLOOR_VERSION: \"7.85.0\"" appears 0 times, but must appear once
check-floors: .github/workflows/floors.yml: line 4 contains the Chez floor 10.4.0, which only the line "  CHEZ_VERSION: \"10.4.0\"" of .github/workflows/ci.yml may write
check-floors: .github/workflows/floors.yml: line 5 contains the libcurl floor 7.85.0, which only the line "  CURL_FLOOR_VERSION: \"7.85.0\"" of .github/workflows/ci.yml may write
check-floors: FAILED (problems: 4)
make: *** [Makefile:273: check-floors] Error 1
make test exit 2
```

### WF2. a floor literal in a second workflow file

**Guards:** no line of any workflow file but ci.yml's env lines writes a floor.

**Mutation:** In `.github/workflows/release.yml`:

```diff
+name: Release
+on:
+  push:
+    tags: ["v*"]
+jobs:
+  release:
+    runs-on: ubuntu-24.04
+    steps:
+      - run: scripts/ci/build-curl.sh 7.85.0 /opt/curl
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: .github/workflows/release.yml: line 9 contains the libcurl floor 7.85.0, which only the line "  CURL_FLOOR_VERSION: \"7.85.0\"" of .github/workflows/ci.yml may write
check-floors: FAILED (problems: 1)
make: *** [Makefile:273: check-floors] Error 1
make test exit 2
```

### WF3. the workflow directory emptied

**Guards:** a workflow directory that holds no file fails.

**Mutation:** delete `.github/workflows/ci.yml`, all 435 lines of it, the one file there.

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: .github/workflows: it holds no file, but must hold ci.yml, whose env lines write the floors
check-floors: FAILED (problems: 1)
make: *** [Makefile:273: check-floors] Error 1
make test exit 2
```

### WF4. ci.yml renamed ci.yaml

**Guards:** the env lines are in ci.yml itself; elsewhere they are literals.

**Mutation:** rename `.github/workflows/ci.yml` to `.github/workflows/ci.yaml`, unchanged.

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: .github/workflows: it holds no ci.yml, whose env lines write the floors
check-floors: .github/workflows/ci.yaml: line 64 contains the Chez floor 10.4.0, which only the line "  CHEZ_VERSION: \"10.4.0\"" of .github/workflows/ci.yml may write
check-floors: .github/workflows/ci.yaml: line 65 contains the libcurl floor 7.85.0, which only the line "  CURL_FLOOR_VERSION: \"7.85.0\"" of .github/workflows/ci.yml may write
check-floors: FAILED (problems: 3)
make: *** [Makefile:273: check-floors] Error 1
make test exit 2
```

### WF5. the Makefile hands check-floors ci.yml again, not the directory

**Guards:** make check-floors reads the workflow directory.

**Mutation:** In `Makefile`:

```diff
 	@scripts/require-tools "$(GOAL)" $(CHEZ)
-	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp README.org .github/workflows
+	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp README.org .github/workflows/ci.yml
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: .github/workflows/ci.yml: it cannot be read: Exception in directory-list: failed for .github/workflows/ci.yml: not a directory
check-floors: FAILED (problems: 1)
make: *** [Makefile:273: check-floors] Error 1
make test exit 2
```

### FL1. only ci.yml is searched for floor literals

**Guards:** every file under the directory is searched.

**Mutation:** In `tests/floors.sls`:

```diff
                   (map (lambda (entry)
-                         (if (cadr entry)
+                         (if (and (cadr entry) (string=? (car entry) env-path))
                              (literal-problems (car entry) (split (cadr entry) #\newline) rows
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflows: a second workflow that writes the Chez floor in a step: named, by its own path and line
  expected: (returned ("W/release.yml: line 7 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write"))
  actual:   (returned ())
FAIL workflows: a second workflow that writes the libcurl floor in a comment
  expected: (returned ("W/release.yml: line 8 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" of W/ci.yml may write"))
  actual:   (returned ())
FAIL workflows-second-literal: a second workflow beside ci.yml writes the Chez floor in a step
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-second-literal/workflows/release.yml: line 11 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of tests/fixtures/floors/workflows-second- [cut: 74 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-second-literal/README.org and tests/fixtures/floors/workflows-second-literal/workflows (ci.yml, release.yml) hold the floors in tests/fixtures/floors/workflows-second-literal/flo [cut: 55 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
direct: test-check-floors exit 1
```
(55 more such lines cut.)

### FL2. env lines are exempt in every workflow file, not only in ci.yml

**Guards:** an env line in another file is a literal.

**Mutation:** In `tests/floors.sls`:

```diff
           ((null? rest) '())
-          ((and (not env-path) (member (car rest) env-lines)) (loop (cdr rest) (+ n 1)))
+          ((member (car rest) env-lines) (loop (cdr rest) (+ n 1)))
           (else
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflows: the env lines moved to a second workflow: missing from ci.yml, and literals there
  expected: (returned ("W/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W/ci.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but must appear once" "W/release.yml: line 2 c [cut: 250 more characters]
  actual:   (returned ("W/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W/ci.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but must appear once"))
FAIL workflows: the env lines copied into a second workflow: ci.yml holds them, and the copies are literals
  expected: (returned ("W/release.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/release.yml: line 3 contains the libcurl floor 8.1.2, which only the line \"  CUR [cut: 57 more characters]
  actual:   (returned ())
FAIL workflows: a ci.yml in a subdirectory is not the workflow: there is no ci.yml, and its env lines are literals
  expected: (returned ("W: it holds no ci.yml, whose env lines write the floors" "W/sub/ci.yml: line 7 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/sub/ci.yml: line 8 conta [cut: 113 more characters]
  actual:   (returned ("W: it holds no ci.yml, whose env lines write the floors"))
test: FAIL tests/test-check-floors.sps (exit 1)
direct: test-check-floors exit 1
```
(13 more such lines cut.)

### FL3. the files are taken in the order given, not by path

**Guards:** problems come file by file in path order.

**Mutation:** In `tests/floors.sls`:

```diff
                       workflow-floors))
-           (sorted (list-sort (lambda (a b) (string<? (car a) (car b))) workflows))
+           (sorted workflows)
            (env-entry (assoc env-path sorted)))
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL workflows: every file is held, in path order, whatever order they come in
  expected: (returned ("W/a.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/a.yml: line 2 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERS [cut: 336 more characters]
  actual:   (returned ("W/z.yml: line 1 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/ci.yml: line 16 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VE [cut: 336 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:210: test] Error 1
FAIL workflows: every file is held, in path order, whatever order they come in
  expected: (returned ("W/a.yml: line 2 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/a.yml: line 2 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERS [cut: 336 more characters]
  actual:   (returned ("W/z.yml: line 1 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/ci.yml: line 16 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VE [cut: 336 more characters]
direct: test-check-floors exit 1
```
(1 more such line cut.)

### FL4. a directory with no file is not named alone

**Guards:** an empty workflow directory fails, named once.

**Mutation:** In `tests/floors.sls`:

```diff
            (env-entry (assoc env-path sorted)))
-      (if (null? workflows)
+      (if #f
           (list (string-append wdir ": it holds no file, but must hold " env-workflow
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflows: no file at all: the directory is named, once
  expected: (returned ("W: it holds no file, but must hold ci.yml, whose env lines write the floors"))
  actual:   (returned ("W: it holds no ci.yml, whose env lines write the floors"))
FAIL an empty workflow directory: named, once, and nothing else
  expected: (returned same)
  actual:   (returned (got (1 "" "check-floors: /tmp/curl-testing.6Y44Pw: it holds no ci.yml, whose env lines write the floors\ncheck-floors: FAILED (problems: 1)\n") want (1 "" "check-floors: /tmp/curl-testing.6Y44Pw: it holds no file, but [cut: 93 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL workflows: no file at all: the directory is named, once
  expected: (returned ("W: it holds no file, but must hold ci.yml, whose env lines write the floors"))
  actual:   (returned ("W: it holds no ci.yml, whose env lines write the floors"))
direct: test-check-floors exit 1
```
(7 more such lines cut.)

### FL5. a directory without ci.yml is not named

**Guards:** ci.yml must be there.

**Mutation:** In `tests/floors.sls`:

```diff
           (append
-           (if env-entry
+           (if #t
                '()
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflows: a ci.yml in a subdirectory is not the workflow: there is no ci.yml, and its env lines are literals
  expected: (returned ("W: it holds no ci.yml, whose env lines write the floors" "W/sub/ci.yml: line 7 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/sub/ci.yml: line 8 conta [cut: 113 more characters]
  actual:   (returned ("W/sub/ci.yml: line 7 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/sub/ci.yml: line 8 contains the libcurl floor 8.1.2, which only the line \"  CURL_ [cut: 55 more characters]
FAIL workflows: no ci.yml, and a second workflow that writes no floor
  expected: (returned ("W: it holds no ci.yml, whose env lines write the floors"))
  actual:   (returned ())
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL workflows: a ci.yml in a subdirectory is not the workflow: there is no ci.yml, and its env lines are literals
  expected: (returned ("W: it holds no ci.yml, whose env lines write the floors" "W/sub/ci.yml: line 7 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/sub/ci.yml: line 8 conta [cut: 113 more characters]
  actual:   (returned ("W/sub/ci.yml: line 7 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/sub/ci.yml: line 8 contains the libcurl floor 8.1.2, which only the line \"  CURL_ [cut: 55 more characters]
direct: test-check-floors exit 1
```
(7 more such lines cut.)

### FL6. an unreadable ci.yml is compared as an empty text

**Guards:** a file the caller could not read is not compared; the caller names it.

**Mutation:** In `tests/floors.sls`:

```diff
                                     ", whose env lines write the floors")))
-           (if (and env-entry (cadr env-entry))
-               (env-line-problems env-path (split (cadr env-entry) #\newline) rows)
+           (if env-entry
+               (env-line-problems env-path (split (or (cadr env-entry) "") #\newline) rows)
                '())
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflows: an unreadable ci.yml, #f, is not compared, and is no missing ci.yml; the others still are
  expected: (returned ("W/release.yml: line 7 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write"))
  actual:   (returned ("W/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W/ci.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but must appear once" "W/release.yml: line 7 c [cut: 110 more characters]
FAIL an unreadable ci.yml, #f, is not compared, and the README still is
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ("R.org: it has no \"** Requirements\" section" "W/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W/ci.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, [cut: 24 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
FAIL workflows: an unreadable ci.yml, #f, is not compared, and is no missing ci.yml; the others still are
  expected: (returned ("W/release.yml: line 7 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write"))
  actual:   (returned ("W/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W/ci.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but must appear once" "W/release.yml: line 7 c [cut: 110 more characters]
direct: test-check-floors exit 1
```
(7 more such lines cut.)

### FL7. a workflow directory that could not be read is compared as an empty one

**Guards:** a directory the caller could not list is not compared; the caller names it.

**Mutation:** In `tests/floors.sls`:

```diff
             (append (if rtext (readme-problems rpath rtext fpath floors) '())
-                    (if workflows (workflows-problems wdir workflows floors) '())))
+                    (workflows-problems wdir (or workflows '()) floors)))
           problems))))
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL a workflow directory that could not be read, #f, is not compared, and the README still is
  expected: (returned ("R.org: it has no \"** Requirements\" section"))
  actual:   (returned ("R.org: it has no \"** Requirements\" section" "W: it holds no file, but must hold ci.yml, whose env lines write the floors"))
FAIL an unreadable README and an unreadable workflow directory compare nothing
  expected: (returned ())
  actual:   (returned ("W: it holds no file, but must hold ci.yml, whose env lines write the floors"))
FAIL no-workflow: a floors file and a README, and no workflow directory beside them
  expected: (1 "" "check-floors: tests/fixtures/floors/no-workflow/workflows: it cannot be read: Exception in directory-list: failed for tests/fixtures/floors/no-workflow/workflows: no such file or directory\ncheck-floors: FAILED (problems: [cut: 7 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/no-workflow/workflows: it holds no file, but must hold ci.yml, whose env lines write the floors\ncheck-floors: tests/fixtures/floors/no-workflow/workflows: it cannot be read: Exception  [cut: 140 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
direct: test-check-floors exit 1
```
(25 more such lines cut.)

### FL8. every line of a workflow file but ci.yml is taken for a literal

**Guards:** a second workflow that writes no floor passes.

**Mutation:** In `tests/floors.sls`:

```diff
                    (map (lambda (row)
-                          (if (contains? (car rest) (cadr row))
+                          (if (or env-path (contains? (car rest) (cadr row)))
                               (list (string-append
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflows: a second workflow that writes no floor: nothing to report
  expected: (returned ())
  actual:   (returned ("W/release.yml: line 1 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/release.yml: line 1 contains the libcurl floor 8.1.2, which only the line \"  CUR [cut: 1968 more characters]
FAIL workflows: the Node floor, and versions that are no floor, may be written in a second workflow
  expected: (returned ())
  actual:   (returned ("W/release.yml: line 1 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write" "W/release.yml: line 1 contains the libcurl floor 8.1.2, which only the line \"  CUR [cut: 2241 more characters]
FAIL workflows-second-clean: a second workflow beside ci.yml that writes no floor: both read, and both named
  expected: (0 "check-floors: tests/fixtures/floors/workflows-second-clean/README.org and tests/fixtures/floors/workflows-second-clean/workflows (ci.yml, release.yml) hold the floors in tests/fixtures/floors/workflows-second-clean/floors.se [cut: 49 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/workflows-second-clean/workflows/release.yml: line 1 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of tests/fixtures/floors/workflows-second-cle [cut: 5443 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
direct: test-check-floors exit 1
```
(79 more such lines cut.)

### FL9. a workflow file the caller could not read is compared all the same

**Guards:** a file whose text is #f is not compared.

**Mutation:** In `tests/floors.sls`:

```diff
                   (map (lambda (entry)
-                         (if (cadr entry)
+                         (if #t
                              (literal-problems (car entry) (split (cadr entry) #\newline) rows
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflows: an unreadable ci.yml, #f, is not compared, and is no missing ci.yml; the others still are
  expected: (returned ("W/release.yml: line 7 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of W/ci.yml may write"))
  actual:   (raised "Exception in string->list: #f is not a string")
FAIL workflows: an unreadable second workflow, #f, is not compared
  expected: (returned ())
  actual:   (raised "Exception in string->list: #f is not a string")
FAIL workflows-dir-link: a symbolic link to a directory among the workflows is not followed: it is a file that cannot be read
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-dir-link/workflows/linked: it cannot be read: Exception in get-string-all: failed on #<binary input port tests/fixtures/floors/workflows-dir-link/workflows/linked>: is a direc [cut: 44 more characters]
  actual:   (255 "" "Exception in string->list: #f is not a string\n")
test: FAIL tests/test-check-floors.sps (exit 1)
direct: test-check-floors exit 1
```
(19 more such lines cut.)

### PF1. the program does not walk into subdirectories

**Guards:** every file under the directory is read, in subdirectories too.

**Mutation:** In `tests/check-floors.sps`:

```diff
                 (let ((path (string-append dir "/" name)))
-                  (if (file-directory? path #f) (walk path) (list path))))
+                  (if (file-directory? path #f) '() (list path))))
               (directory-list dir))))
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL workflows-nested: a file in a subdirectory of the workflows names the libcurl floor in a comment
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-nested/workflows/sub/notes.yml: line 2 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" of tests/fixtures/floors/workflows-nested/ [cut: 66 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-nested/README.org and tests/fixtures/floors/workflows-nested/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflows-nested/floors.sexp (chez 10.9.1, libcurl 8.1.2, [cut: 18 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:210: test] Error 1
FAIL workflows-nested: a file in a subdirectory of the workflows names the libcurl floor in a comment
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-nested/workflows/sub/notes.yml: line 2 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" of tests/fixtures/floors/workflows-nested/ [cut: 66 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-nested/README.org and tests/fixtures/floors/workflows-nested/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflows-nested/floors.sexp (chez 10.9.1, libcurl 8.1.2, [cut: 18 more characters]
direct: test-check-floors exit 1
```
(1 more such line cut.)

### PF2. the program follows a symbolic link to a directory

**Guards:** a link to a directory is not followed: it is read as a file, which fails.

**Mutation:** In `tests/check-floors.sps`:

```diff
                 (let ((path (string-append dir "/" name)))
-                  (if (file-directory? path #f) (walk path) (list path))))
+                  (if (file-directory? path) (walk path) (list path))))
               (directory-list dir))))
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL workflows-dir-link: a symbolic link to a directory among the workflows is not followed: it is a file that cannot be read
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-dir-link/workflows/linked: it cannot be read: Exception in get-string-all: failed on #<binary input port tests/fixtures/floors/workflows-dir-link/workflows/linked>: is a direc [cut: 44 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/workflows-dir-link/workflows/linked/ci.yml: line 6 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of tests/fixtures/floors/workflows-dir-link/wor [cut: 316 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:210: test] Error 1
FAIL workflows-dir-link: a symbolic link to a directory among the workflows is not followed: it is a file that cannot be read
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-dir-link/workflows/linked: it cannot be read: Exception in get-string-all: failed on #<binary input port tests/fixtures/floors/workflows-dir-link/workflows/linked>: is a direc [cut: 44 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/workflows-dir-link/workflows/linked/ci.yml: line 6 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of tests/fixtures/floors/workflows-dir-link/wor [cut: 316 more characters]
direct: test-check-floors exit 1
```
(1 more such line cut.)

### PF3. the program hands the check only ci.yml

**Guards:** the program reads every file under the directory, not just ci.yml.

**Mutation:** In `tests/check-floors.sps`:

```diff
           (map (lambda (path) (list path (read-text path)))
-               (list-sort string<? (walk wdir))))))
+               (filter (lambda (p) (string=? p (string-append wdir "/ci.yml"))) (walk wdir))))))
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflows-second-literal: a second workflow beside ci.yml writes the Chez floor in a step
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-second-literal/workflows/release.yml: line 11 contains the Chez floor 10.9.1, which only the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" of tests/fixtures/floors/workflows-second- [cut: 74 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-second-literal/README.org and tests/fixtures/floors/workflows-second-literal/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflows-second-literal/floors.sexp (che [cut: 42 more characters]
FAIL workflows-second-clean: a second workflow beside ci.yml that writes no floor: both read, and both named
  expected: (0 "check-floors: tests/fixtures/floors/workflows-second-clean/README.org and tests/fixtures/floors/workflows-second-clean/workflows (ci.yml, release.yml) hold the floors in tests/fixtures/floors/workflows-second-clean/floors.se [cut: 49 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-second-clean/README.org and tests/fixtures/floors/workflows-second-clean/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflows-second-clean/floors.sexp (chez 10.9 [cut: 36 more characters]
FAIL workflows-nested: a file in a subdirectory of the workflows names the libcurl floor in a comment
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-nested/workflows/sub/notes.yml: line 2 contains the libcurl floor 8.1.2, which only the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" of tests/fixtures/floors/workflows-nested/ [cut: 66 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-nested/README.org and tests/fixtures/floors/workflows-nested/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflows-nested/floors.sexp (chez 10.9.1, libcurl 8.1.2, [cut: 18 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
direct: test-check-floors exit 1
```
(19 more such lines cut.)

### PF4. a directory that cannot be listed is taken for an empty one

**Guards:** a missing workflow directory, or a file in its place, is named as unreadable.

**Mutation:** In `tests/check-floors.sps`:

```diff
 (define (read-workflows wdir)
-  (guard (e (#t (list 'unreadable (string-append wdir ": it cannot be read: " (describe e)))))
+  (guard (e (#t (list 'files '())))
     (list 'files
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL no-workflow: a floors file and a README, and no workflow directory beside them
  expected: (1 "" "check-floors: tests/fixtures/floors/no-workflow/workflows: it cannot be read: Exception in directory-list: failed for tests/fixtures/floors/no-workflow/workflows: no such file or directory\ncheck-floors: FAILED (problems: [cut: 7 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/no-workflow/workflows: it holds no file, but must hold ci.yml, whose env lines write the floors\ncheck-floors: FAILED (problems: 1)\n")
FAIL no file exists: all three named, the floors first, then the README, then the workflow directory
  expected: (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: tests/fixtures/floors/l [cut: 351 more characters]
  actual:   (1 "" "check-floors: tests/fixtures/floors/legal/none.sexp: it cannot be read: Exception in open-file-input-port: failed for tests/fixtures/floors/legal/none.sexp: no such file or directory\ncheck-floors: tests/fixtures/floors/l [cut: 183 more characters]
FAIL the workflows argument names ci.yml itself, a file: it cannot be read as a directory
  expected: (1 "" "check-floors: tests/fixtures/floors/legal/workflows/ci.yml: it cannot be read: Exception in directory-list: failed for tests/fixtures/floors/legal/workflows/ci.yml: not a directory\ncheck-floors: FAILED (problems: 1)\n")
  actual:   (1 "" "check-floors: tests/fixtures/floors/legal/workflows/ci.yml: it holds no file, but must hold ci.yml, whose env lines write the floors\ncheck-floors: FAILED (problems: 1)\n")
test: FAIL tests/test-check-floors.sps (exit 1)
direct: test-check-floors exit 1
```
(25 more such lines cut.)

### PF5. a file under the directory that cannot be read is not named

**Guards:** an unreadable workflow file fails, by name.

**Mutation:** In `tests/check-floors.sps`:

```diff
                        (map (lambda (file)
-                              (if (eq? (car (cadr file)) 'text) '() (list (cadr (cadr file)))))
+                              '())
                             files))
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL workflows-dir-link: a symbolic link to a directory among the workflows is not followed: it is a file that cannot be read
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-dir-link/workflows/linked: it cannot be read: Exception in get-string-all: failed on #<binary input port tests/fixtures/floors/workflows-dir-link/workflows/linked>: is a direc [cut: 44 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-dir-link/README.org and tests/fixtures/floors/workflows-dir-link/workflows (ci.yml, linked) hold the floors in tests/fixtures/floors/workflows-dir-link/floors.sexp (chez 10.9.1,  [cut: 32 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:210: test] Error 1
FAIL workflows-dir-link: a symbolic link to a directory among the workflows is not followed: it is a file that cannot be read
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-dir-link/workflows/linked: it cannot be read: Exception in get-string-all: failed on #<binary input port tests/fixtures/floors/workflows-dir-link/workflows/linked>: is a direc [cut: 44 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-dir-link/README.org and tests/fixtures/floors/workflows-dir-link/workflows (ci.yml, linked) hold the floors in tests/fixtures/floors/workflows-dir-link/floors.sexp (chez 10.9.1,  [cut: 32 more characters]
direct: test-check-floors exit 1
```
(1 more such line cut.)

### PF6. the pass line names ci.yml, not the files read

**Guards:** a pass names every file it read under the directory.

**Mutation:** In `tests/check-floors.sps`:

```diff
            (say (current-output-port)
-                (string-append rpath " and " wdir " (" (joined (read-names wdir w)) ")"
+                (string-append rpath " and " wdir " (" "ci.yml" ")"
                                " hold the floors in " fpath " (" (summary (cadr f)) ")"))
```

**Command:** `make test`, then `tests/test-check-floors.sps` run directly.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL workflows-second-clean: a second workflow beside ci.yml that writes no floor: both read, and both named
  expected: (0 "check-floors: tests/fixtures/floors/workflows-second-clean/README.org and tests/fixtures/floors/workflows-second-clean/workflows (ci.yml, release.yml) hold the floors in tests/fixtures/floors/workflows-second-clean/floors.se [cut: 49 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-second-clean/README.org and tests/fixtures/floors/workflows-second-clean/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflows-second-clean/floors.sexp (chez 10.9 [cut: 36 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make: *** [Makefile:210: test] Error 1
FAIL workflows-second-clean: a second workflow beside ci.yml that writes no floor: both read, and both named
  expected: (0 "check-floors: tests/fixtures/floors/workflows-second-clean/README.org and tests/fixtures/floors/workflows-second-clean/workflows (ci.yml, release.yml) hold the floors in tests/fixtures/floors/workflows-second-clean/floors.se [cut: 49 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-second-clean/README.org and tests/fixtures/floors/workflows-second-clean/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflows-second-clean/floors.sexp (chez 10.9 [cut: 36 more characters]
direct: test-check-floors exit 1
```
(1 more such line cut.)

### LN1a. the detail line dropped from the block the lanes require, and nothing else

**Guards:** the block is compared whole and in order: a line missing from it shifts the rest.

**Mutation:** In `scripts/ci/expect-missing-api.sh`:

```diff
   '  source:     override' \
-  "  detail:     $entry" \
   "  version:    $CURL_FLOOR_VERSION" >"$work/expected"
```

**Command:** `build/lanes-matrix.sh` (the five cells, below), with the two disabled curls copied into the copy.

**Result:** killed, lanes-matrix exit 1:

```
CELL WRONG options lane on the no-options library: exit 1, fail (must pass)
CELL WRONG header lane on the no-headers library: exit 1, fail (must pass)
lanes-matrix: a cell is WRONG
lanes-matrix exit 1
```

### LN1b. the lanes' detail line no longer compared: dropped from what is required and from what is found

**Guards:** each disabled lane requires its own entry point, so it tells the two libraries apart.

**Mutation:** In `scripts/ci/expect-missing-api.sh`:

```diff
   '  source:     override' \
-  "  detail:     $entry" \
   "  version:    $CURL_FLOOR_VERSION" >"$work/expected"
...
 lines=$(grep -c '' "$work/expected")
-sed -n "${start},$((start + lines - 1))p" "$work/build.log" >"$work/found"
+sed -n "${start},$((start + lines))p" "$work/build.log" | grep -v '^  detail:' >"$work/found"
 if ! diff -u "$work/expected" "$work/found" >"$work/diff"; then
```

**Command:** `build/lanes-matrix.sh` (the five cells, below), with the two disabled curls copied into the copy.

**Result:** killed, lanes-matrix exit 1:

```
CELL WRONG options lane on the no-headers library: exit 0, pass (must fail)
CELL WRONG header lane on the no-options library: exit 0, pass (must fail)
lanes-matrix: a cell is WRONG
lanes-matrix exit 1
```

### PN1. the nothreads job's checkout back on its tag, @v7

**Guards:** every uses: line names a full commit SHA.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
     steps:
-      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
+      - uses: actions/checkout@v7
```

**Command:** `scripts/ci/check-action-pins.sh .github/workflows`, on the host.

**Result:** killed, check-action-pins exit 1:

```
check-action-pins: .github/workflows/ci.yml:333:      - uses: actions/checkout@v7
check-action-pins: 1 of 19 uses: lines name no full commit SHA with its tag in a comment, as uses: OWNER/REPO@<40 hex digits> # vTAG
check-action-pins exit 1
```

### PN2. the memory job's cache save at a 7-digit SHA

**Guards:** the SHA is the full 40 hex digits.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
         if: steps.chez.outputs.cache-hit != 'true'
-        uses: actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
+        uses: actions/cache/save@55cc834 # v6.1.0
         with:
```

**Command:** `scripts/ci/check-action-pins.sh .github/workflows`, on the host.

**Result:** killed, check-action-pins exit 1:

```
check-action-pins: .github/workflows/ci.yml:418:        uses: actions/cache/save@55cc834 # v6.1.0
check-action-pins: 1 of 19 uses: lines name no full commit SHA with its tag in a comment, as uses: OWNER/REPO@<40 hex digits> # vTAG
check-action-pins exit 1
```

### PN3. a lane's curl restore without its tag comment

**Guards:** each pin carries its tag in a comment.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
         id: curl
-        uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
+        uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9
         with:
```

**Command:** `scripts/ci/check-action-pins.sh .github/workflows`, on the host.

**Result:** killed, check-action-pins exit 1:

```
check-action-pins: .github/workflows/ci.yml:296:        uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9
check-action-pins: 1 of 19 uses: lines name no full commit SHA with its tag in a comment, as uses: OWNER/REPO@<40 hex digits> # vTAG
check-action-pins exit 1
```

### AL1. a lane reads a matrix property that does not exist

**Guards:** actionlint fails a planted error in the workflow.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
           CHEZ_CURL_LIBCURL: ${{ runner.temp }}/curl-floor-no-${{ matrix.api }}-api/lib/libcurl.so.4
-          ENTRY: ${{ matrix.entry }}
+          ENTRY: ${{ matrix.entrypoint }}
         run: scripts/ci/expect-missing-api.sh "$ENTRY"
```

**Command:** actionlint (Docker, `rhysd/actionlint`, 1.7.12) on `.github/workflows/ci.yml`, on the host.

**Result:** killed, actionlint exit 1:

```
.github/workflows/ci.yml:325:22: property "entrypoint" is not defined in object type {api: string; entry: string; flag: string} [expression]
actionlint exit 1
```

### AL2. the concurrency group reads github.runid, which does not exist

**Guards:** actionlint fails a planted error in the workflow.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
 concurrency:
-  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}
+  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.runid }}
   cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

**Command:** actionlint (Docker, `rhysd/actionlint`, 1.7.12) on `.github/workflows/ci.yml`, on the host.

**Result:** killed, actionlint exit 1:

```
.github/workflows/ci.yml:60:90: property "runid" is not defined in object type {action: string; action_path: string; action_ref: string; action_repository: string; action_status: string; actor: string; actor_id: string; api_url: string; art [cut: 730 more characters]
actionlint exit 1
```

### Coverage

Every rule added has a mutation that fails it by name. Of the 109 tests R1 failed, 24 are failed by a
mutation here: every row of a rule this fix added. FL8 and FL9 were added after a first pass left three of
them unfailed: the two pure rows in which a second workflow writes no floor, and the row in which a second
workflow could not be read. The other 85 failed R1 only because the signature of `check-floors`, the
fixture layout or the usage line changed under them; the rules they hold are the CI part's, and its
mutations (CF, FL, PF) still apply to them.

Notes on single mutations:

- **LN1a and LN1b.** The first draft of the lanes' mutation, LN1a, dropped only the required detail line.
  The block is compared whole and in order, so the rest of it shifted up a line and every refusal failed,
  on its own library too: a kill, but not the one wanted. LN1b leaves the detail line uncompared on both
  sides, and then each lane's check passes on the other lane's library: without that line, the lanes cannot
  tell the two libraries apart.
- **WF4** shows that the env lines must be in `ci.yml` itself: under any other name they are literals.
- **PF2** is killed only by the `workflows-dir-link` fixture, whose link points at `legal/workflows`;
  followed, the link's `ci.yml` is read as a second file, and its env lines are literals.

### Not covered

- **The workflow's structure.** Nothing local checks that the memory job has no `if:` or `needs:`, that a
  job's timeout is 60 minutes, or what the concurrency group evaluates to: those run only on GitHub.
  actionlint passes the workflow and fails a planted undefined matrix property and an undefined `github`
  property in the group (AL1, AL2). What GitHub does with the group is from its documentation
  (docs.github.com, "Control the concurrency of workflows and jobs", read 2026-10-17): "By default, any
  existing `pending` job or workflow in the same concurrency group will be canceled and the new queued job
  or workflow will take its place."
- **The tag in a pin's comment.** `check-action-pins.sh` reads text only: it does not ask GitHub which
  commit the tag names. The SHAs were resolved by hand, above.
- **A real lane run.** The lanes ran on the Guix Chez, not on a Chez built from the tarball by
  `build-chez.sh`, against curls built in the container, not on the runner. The Docker builds ran
  `build-curl.sh` before its header comment was rewrapped for the two lanes; the code is unchanged. The
  TLS, features and remedy lines of the refusal are not compared: the first two name the runner's
  packages, and the third restates the detail.
- **The pin check in `make`.** It is not a Makefile target: this fix could touch only the
  `check-floors` recipe. CI runs it, and it runs by hand with `sh`.

### Clean rerun

After every mutation, on the tree itself, whose files are byte-identical to the snapshot every case copied
(`diff -r`, without `build/`). `make test`, `make check-test-fails` and `make check-help` each exited 0 in the
container; actionlint, shellcheck (Docker, `koalaman/shellcheck:stable`, on the four `scripts/ci/` scripts and
`scripts/guix-env`, `scripts/guix-env-enter`) and the pin check exited 0 on the host:

```
tree and snapshot identical (diff -r, without build/)
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: ran 14, passed 14, failed 0, hung 0
make test exit 0
check-test-fails: make test failed, as it must, in all 10 cases
check-test-fails exit 0
check-help exit 0
actionlint exit 0
shellcheck exit 0
check-action-pins: all 19 uses: lines under .github/workflows name a full commit SHA, with its tag in a comment
```
(1 more line cut: check-action-pins exit 0)

## Second review fixes

The second review left two findings on the memory gate, and the maintainer settled a third
([ADR-0014](decisions/0014-valgrind-memory-gate.md) and
[ADR-0013](decisions/0013-collect-safe-blocking-calls.md), as amended 2026-10-16). Each fix
closes a class:

1. **What Valgrind checked was not held to ADR-0014's command.** Anything that added, dropped
   or changed an option got past the gate, so long as Valgrind exited 0 with a clean summary.
   The routes were `VALGRIND`, a stand-in for Valgrind, `CHEZ`, and, in Guix,
   `MEMORY_SUPPRESSION_FILE` on make's command line.
2. **The evidence was read from a log the suite also writes.** Valgrind's guest shares its pid,
   so a suite can print lines in Valgrind's own `==PID==` form. Two suites with one name also
   shared one log.
3. **The bytevector crossing (the maintainer's decision).** Valgrind cannot see Chez's heap, so
   one checked wrapper (M2) will own every copy between bytevectors and foreign memory. The
   convention suite now allows no other binding that hands C a bytevector's data.

The part changes these files:

- `Makefile`, the memory-gate section only:
  - `MEMORY_SUPPRESSION_FILE` is `override`, so no make command line, nor `make -e`, can name
    another file. test-memory allows the file it names, so one variable fed both the command
    and its allowlist.
  - Each suite's options are one list, `set --` in the recipe: `-v --command-line-only=yes
    --log-file=build/memory/SUITE.valgrind --error-exitcode=9 --leak-check=full
    --show-leak-kinds=definite --errors-for-leak-kinds=definite`, then
    `--suppressions=tests/guix-glibc-locpath.supp` in a Guix environment. Valgrind is handed
    that list, and its `Valgrind options:` block must equal it, element by element and in
    order. Otherwise the FAIL line names both lists.
  - Valgrind writes to `build/memory/SUITE.valgrind`, and the suite's stdout and stderr go to
    `build/memory/SUITE.log`. Every piece of evidence is read from the Valgrind log alone:
    `Command:`, options, `Reading syms from`, `ERROR SUMMARY`, suppressions files and the
    suppressed count. A FAIL prints both paths, Valgrind's excerpt, and, unless the exit was 9,
    the suite's last 10 lines. Both logs are removed before each run. A run that exits 0 with no
    Valgrind log FAILs with `Valgrind wrote no log, PATH`.
  - test-memory refuses two suites with one name before running any, naming both and the two
    logs they would share.
  - The comments name the libp11-kit rule's lower bound as one that fails closed, and that no
    plant can fail.
- `tests/check-memory-gate.sh`: from 27 cases to 36 in the container, and from 22 to 30
  outside Guix:
  - new: `d override` (Guix only), `k undef`, `k added`, `k dropped`, `k changed`, `k order`,
    `l forged`, `l stale` and `l names`;
  - `e` requires `--log-file=build/memory/memory-plant-leak.valgrind` in the suite's command;
  - `i` names the options it adds, before the suppressions files;
  - `b`, `d` and `h` read Valgrind's markers from the `.valgrind` log.
- `tests/foreign-conventions.sls`: the crossing rule. A Binding gains a fifth element, its
  crossings: the `u8*`, `u16*` or `u32*` parameters of a foreign procedure, direct or through a
  known wrapper, and a callable's result of those types. A binding with crossings fails, named
  `(bytevector-crossing KEY TYPES FILE)`, unless its row is marked.
  - A row may take a fourth element, `(bytevector-crossing CITATION)`. Its citation is checked as
    the row's own is, under `crossing-` names, and a marked row may not be `__collect_safe`.
  - Types the reader cannot read fail closed. Those are a parameter list or a callable result
    that is not a symbol, `(* name)` or `(& name)`, and a wrapper use's parameter list that is
    not one. A wrapper's template parameter list must be literal types or `(arg ...)` at a fixed
    place in its pattern.
  - The table has no marked row.
- `tests/test-collect-safe.sps`: every expected binding carries its crossings, and there are
  four new fixture cases. There are eight new seeded tables and a live test that no row is
  marked yet.
- `tests/fixtures/conventions/`: new `crossing-unmarked`, `crossing-wrapper`, `crossing-marked`
  and `types-unreadable`. `wrapper-unreadable` gains two wrappers. `legal`'s `memcpy` now takes
  `(uptr uptr size_t)`. `blocking-plain`'s `memcpy` keeps its `u8*`, now also named as a
  crossing.

The driver is `slice5/fix2/mutate.py` in the session scratchpad, adapted from the last part's.
It froze four trees, without `.git`, `build/` or `.claude/`:

- `snap/`, the fixed working tree;
- `snap-before/`, the tree before these fixes;
- `snap-red-gate/`, `snap-before/` with the new `tests/check-memory-gate.sh`;
- `snap-red-conv/`, `snap-before/` with the new suite and fixtures.

Each case got a fresh copy, a touched `manifest.scm`, and its command through the copy's own
`scripts/guix-env`. Each edit was an exact-text replacement that had to match exactly once.
Three ran at a time. A case counts as killed only when its command exits non-zero and every
expected line is present: whole, as a substring (`~` first), or as a prefix (`~` last). The
working tree was never edited.
### Measurements

The container has Valgrind 3.27.0, Chez 10.4.0 and GNU awk, on amd64. Ubuntu 24.04 ran in Docker
(`chez-curl-vg322:gcc`), with apt's Valgrind 3.22.0, GNU Make 4.3, gcc and mawk, and no Chez.

**The `Valgrind options:` block.** With `-v`, both versions print it in the same shape, one
option per line, indented four spaces, ended by `Contents of /proc/version:`. Valgrind 3.22,
from `slice5/fix2/probe-opts-322.txt`:

```
--14-- Valgrind options:
--14--    -v
--14--    --command-line-only=yes
--14--    --log-file=/work/vg.log
--14--    --error-exitcode=9
--14--    --leak-check=full
--14--    --show-leak-kinds=definite
--14--    --errors-for-leak-kinds=definite
--14-- Contents of /proc/version:
```

- 3.27 prints the same lines, in `slice5/fix2/probe-opts-327.txt`.
- Options from `VALGRIND_OPTS` are listed first, before the command line's.
- Ubuntu's `/usr/bin/valgrind` is a shell script that sets `LD_LIBRARY_PATH` and adds no
  option: the fixed gate's block on 3.22 is exactly the list it was handed.

**What weakens the gate, and from where.**

- A later option overrides an earlier one. On 3.22, the leak exits 9 with
  `--errors-for-leak-kinds=none --errors-for-leak-kinds=definite`, and 0 the other way round.
  So `VALGRIND`, whose options come first, cannot weaken a flag the gate sets. It can add one
  the gate leaves alone.
- `--undef-value-errors=no` is one. A program that branches on four bytes of `foreign-alloc`
  memory nothing initialised fails, exit 9, with `Conditional jump or move depends on
  uninitialised value(s)`. With the option it exits 0 with `ERROR SUMMARY: 0 errors from 0
  contexts`. On the old gate it passed (R0, `k added`).
- Dropping `--leak-check=full` leaves the default, `summary`. Both versions then report
  `definitely lost: 777 bytes in 1 blocks` and `ERROR SUMMARY: 0 errors from 0 contexts`, and
  exit 0. A stand-in for Valgrind that drops it passed the leak plant on the old gate (R0,
  `k dropped`), as did one that changes `--errors-for-leak-kinds=definite` to `none`
  (`k changed`).
- In Guix, `make test-memory MEMORY_SUITES=tests/memory-plant-overrun.sps
  MEMORY_SUPPRESSION_FILE=<a file matching every one-byte invalid access>` passed the overrun
  plant, with `ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 1 from 1)`
  (`slice5/fix2/red-supp-override.txt`). The libp11-kit rule counts only blocks, so it missed a
  suppressed error.

**What a suite can forge.** Under Valgrind, `getpid` answers Valgrind's pid. A program can print
`==PID== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)` on stderr, then exec
`/bin/sh`, and Valgrind never reports. On the old gate that passed (R0, `l forged`). With
`--log-file`, Valgrind's file holds none of the suite's output. Its standard streams stay empty,
except for Valgrind's own errors before the file opens: on 3.22, `--bogus-option=1` wrote
`valgrind: Unknown option` to stderr, exit 1, and no log file.

**Chez's bytevector types**, measured on the pinned Chez 10.4.0 (`slice5/fix2/chez-types.txt`):

- `u8*`, `u16*` and `u32*` are accepted as foreign-procedure parameters; `u64*` and
  `bytevector` are refused as types.
- A callable whose result is `u8*` hands C the bytevector's data: C read back its first byte.
- A callable whose parameter is `u8*` receives a fresh bytevector, copied from C's bytes up to
  the NUL. A procedure's `u8*` result is a copy the same way. Neither hands C a bytevector.
- So the rule reads foreign-procedure parameters and callable results.

**Cost.**

- `make test-memory`, all 14 suites: 108 s, up from 105 s. Its logs, now 28 files, total 236 KB.
- `make check-memory-gate`: 104 s in the container (36 cases), and 80 s with `GUIX_ENVIRONMENT`
  unset (30 cases).

### Valgrind 3.22 and mawk: the fixed recipe in Docker

The fixed tree ran with a stand-in for Chez, a C program that ignores its arguments. With `PLANT`
unset it exits 0. Otherwise it loses 777 bytes, branches on uninitialised memory, or prints a
forged summary with its pid and execs `/bin/true`. Each run was `make test-memory
MEMORY_SUITES=tests/memory-plant-leak.sps CHEZ=/work/fake`. All output is in
`slice5/fix2/docker-gate322.txt`:

```
PLANT unset                       exit 0  test-memory: pass; the options block is the gate's seven, in order; the suite's log is empty
PLANT=leak                        exit 2  FAIL (exit 9, Valgrind's …), "777 bytes in 1 blocks are definitely lost"
PLANT=undef                       exit 2  FAIL (exit 9, Valgrind's …), "Conditional jump or move depends on uninitialised value(s)"
PLANT=undef, VALGRIND="valgrind --undef-value-errors=no"
                                  exit 2  FAIL (exit 0, but Valgrind's options are [--undef-value-errors=no -v …], not the gate's [-v …])
PLANT=leak, a Valgrind that drops --leak-check=full
                                  exit 2  FAIL (exit 0, but Valgrind's options are [-v … --error-exitcode=9 --show-leak-kinds=definite …], …)
PLANT=forge                       exit 2  FAIL (exit 0, but Valgrind reported no "ERROR SUMMARY: 0 errors from 0 contexts")
                                          the suite's log holds the forged line; Valgrind's holds no ERROR SUMMARY
two suites named memory-plant-leak exit 2  test-memory: tests/memory-plant-leak.sps and build/twin/memory-plant-leak.sps share the name …; rename one (ADR-0014)
GUIX_ENVIRONMENT=/x, MEMORY_SUPPRESSION_FILE=/work/all.supp, PLANT=leak
                                  exit 2  FAIL (exit 9, …); Valgrind read tests/guix-glibc-locpath.supp and default.supp only
```
### Red runs

**The new check-memory-gate cases (R0).** The final script ran against the old Makefile, and
exited 2:

- every new case failed by name: `d override`, `k undef`, `k added`, `k dropped`, `k changed`,
  `k order`, `l forged`, `l stale` and `l names`;
- five showed the hole as a pass on the old gate (`got: test-memory: pass`): the overrun under
  a command-line suppression file, the undefined-value plant under `--undef-value-errors=no`,
  the leak plant under each of the two option edits, and the forger;
- `k undef` failed only because the old gate writes no `.valgrind` log: the plant itself failed,
  exit 9, as wanted;
- ten older cases failed too, because they now read the `.valgrind` log, expect
  `--log-file`, or name the options `i` adds: both `b` plants, `d used`, `d needed`, `d leak`,
  both `e` arms, `h` late, and both `i` arms. The other 17 passed.

**The weakening option on every suite (R1).** On the old Makefile, `make test-memory
VALGRIND="valgrind --undef-value-errors=no"` passed all 14 suites, exit 0. No suite has an
undefined-value report today, so the run was simply weaker than ADR-0014's and said pass.

**The new conventions cases (R2).** The new suite and fixtures ran against the old reader, and
failed by name, 19 tests in all:

- the four crossing fixtures;
- seven of the eight new seeded tables;
- `wrapper-unreadable`, whose two new wrappers the old reader read without complaint;
- seven older cases, whose bindings now carry their crossings.

Two new tests passed, as controls. A five-element row was already `row-shape`, and the table has
no marked row.
### Mutations

21 cases ran, each in a fresh copy:

- three red runs: R0 and R2 are killed, and R1 passes, as the hole did;
- 18 runs on the fixed tree, all killed, each with every expected line present.

R1 and MO8 change no code. They run the gate on every suite with an option `VALGRIND` adds.

| ID | Change | Killed by |
|---|---|---|
| R0 | the new check-memory-gate cases, old Makefile | all nine new cases `FAILED` by name; five holes passed there |
| R1 | `--undef-value-errors=no` through `VALGRIND`, every suite, old Makefile | as expected: 14 passed |
| R2 | the new suite and fixtures, old reader | 19 tests `FAIL` by name |
| MO1 | options check dropped | `k added`, `k dropped`, `k changed`, `k order`: each plant passed; both `i` arms |
| MO2 | options check widened: the gate's options present, others allowed | `k added`, `k order`, both `i` arms |
| MO3 | options check widened: the same options, in any order | `k order`: the clean program passed |
| MO4 | `--log-file` dropped: the evidence read from the suite's own log | `l forged`: the forger passed; both `e` arms; 21 cases in all |
| MO5 | the run before's Valgrind log not removed | `l stale`: the stale log passed |
| MO6 | the refusal of two suites with one name dropped | `l names`: both ran |
| MO7 | `override` dropped from `MEMORY_SUPPRESSION_FILE` | `d override`: the overrun passed |
| MO8 | `--undef-value-errors=no` through `VALGRIND`, every suite, fixed Makefile | 14 `FAIL` lines naming the options |
| MC1 | the crossing rule dropped | `crossing-unmarked`, `crossing-wrapper`, `crossing-marked`, `blocking-plain` |
| MC2 | a `u8*` binding added to `native.sls` through `bind-required` | `src/ holds to the table`: `(bytevector-crossing "memcpy" (u8*) "src/curl/private/native.sls")` |
| MC3 | the same, a direct `foreign-procedure` | the same |
| MC4 | the mark accepted without a citation (head only) | `crossing-marked`; seeded "a crossing mark that quotes nothing" (it raised) |
| MC5 | the mark's citation unchecked by `table-problems` | three seeded tables: no record, phrase missing, no phrase |
| MC6 | types the reader cannot read accepted when a list | `types-unreadable` |
| MC7 | a callable's result not read | `crossing-unmarked` |
| MC8 | a marked row allowed `__collect_safe` | seeded "a crossing marked on a `__collect_safe` row" |
| MC9 | a wrapper use's parameter list not read | `crossing-wrapper`, `crossing-marked` |

The first pass of the driver ran on a tree whose `l stale` used the stand-in that names a fake
`default.supp`. MO5 was killed by name there, but only because the allowlist rejected that fake
path: the stale log *was* read. `l stale` now uses a stand-in that names Valgrind's own
`default.supp`. Then R0 and MO1 to MO7 ran again on the refrozen tree, and MO5's stale log now
passes on the mutant. The first pass is kept in `slice5/fix2/first-pass/`.
### R0. the new check-memory-gate cases against the Makefile as it was before these fixes

**Guards:** each new case fails against the code it was written to change, and the holes are real.

**Tree:** the tree before these fixes, with the new tests/check-memory-gate.sh.

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d override: MEMORY_SUPPRESSION_FILE on make's command line, naming a file that hides the overrun plant, is ignored, so the plant fails
    got:    test-memory: pass tests/memory-plant-overrun.sps
check-memory-gate: FAILED k added: --undef-value-errors=no, added through VALGRIND, hides that plant, and fails it by name
    got:    test-memory: pass build/check-memory-gate/undef.sps
check-memory-gate: FAILED k dropped: a Valgrind that drops --leak-check=full hides the leak plant, and fails it by name
    got:    test-memory: pass tests/memory-plant-leak.sps
check-memory-gate: FAILED k changed: a Valgrind that turns --errors-for-leak-kinds=definite to none hides the leak plant, and fails it by name
check-memory-gate: FAILED k order: a Valgrind that moves --leak-check=full to the end of its options fails a clean program, by name
check-memory-gate: FAILED l forged: a suite that prints a clean ERROR SUMMARY with Valgrind's pid, then execs away, fails: the evidence is Valgrind's own log
    got:    test-memory: pass build/check-memory-gate/forge.sps
check-memory-gate: FAILED l stale: a Valgrind log an earlier run left is never read: a Valgrind that writes none fails
check-memory-gate: FAILED l names: two suites with one name, in two directories, are refused, so one suite's logs are never another's
```
(166 more such lines cut.)

### R1. a weakening option through VALGRIND, on every suite, through the Makefile as it was before

**Guards:** the hole is real on the real suites.

**Tree:** the tree as it was before these fixes.

**Command** in the container: `make test-memory VALGRIND="valgrind --undef-value-errors=no"`: every suite, with an option VALGRIND adds that turns undefined-value checking off.

**Result:** as expected, exit 0:

```
test-memory: pass tests/test-check-floors.sps
test-memory: pass tests/test-check-nothreads.sps
test-memory: pass tests/test-check-seam.sps
test-memory: pass tests/test-collect-safe.sps
test-memory: pass tests/test-conditions.sps
test-memory: pass tests/test-constants.sps
test-memory: pass tests/test-curl-testing.sps
test-memory: pass tests/test-discovery.sps
test-memory: pass tests/test-library-loading.sps
test-memory: pass tests/test-load-state.sps
test-memory: pass tests/test-manifest.sps
test-memory: ran 14, passed 14, failed 0, hung 0
```
(3 more such lines cut.)

### R2. the new conventions suite and fixtures against the reader as it was before these fixes

**Guards:** each new case fails against the code it was written to change.

**Tree:** the tree before these fixes, with the new tests/test-collect-safe.sps and tests/fixtures/conventions/.

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a row marked as the bytevector crossing, its mark quoting a record
FAIL table-problems, seeded: a crossing mark that quotes nothing
FAIL table-problems, seeded: a fourth element that is no crossing mark
FAIL table-problems, seeded: a crossing mark citing no record
FAIL table-problems, seeded: a crossing mark quoting a phrase the record does not hold
FAIL table-problems, seeded: a crossing mark whose citation has no phrase
FAIL table-problems, seeded: a crossing marked on a __collect_safe row: ADR-0013's decision 4
FAIL crossing-unmarked: bindings that hand C a bytevector's data, none marked: u8*, u16* and u32* parameters, and a callable's u8* result; a procedure's u8* result and a callable's u8* parameter hand C none
FAIL crossing-wrapper: crossings through known wrappers: a use's parameter list, and a template's own; a use's u8* result hands C none
FAIL crossing-marked: a row marked as the reviewed crossing clears its bindings, direct and wrapped; a mark that quotes nothing clears none
FAIL types-unreadable: types the reader cannot read: a string, a list that is no (* name), a callable's result, and a wrapper use's parameter list that is a variable, improper, or missing
test: FAIL tests/test-collect-safe.sps (exit 1)
```
(46 more such lines cut.)

### MO1. the options check dropped

**Guards:** a pass needs Valgrind's options to be exactly the gate's.

**Mutation:** In `Makefile`:

```diff
 	          if (got != cmd) why[++n] = "Valgrind\047s Command: line is \"" got "\", not \"" cmd "\""; \
-	          nwant = split(ENVIRON["options"], want, "\n"); same = (nopts == nwant); \
-	          for (i = 1; i <= nwant; i++) if (opts[i] != want[i]) same = 0; \
-	          if (!same) { g = ""; for (i = 1; i <= nopts; i++) g = g (i > 1 ? " " : "") opts[i]; \
-	            w = ""; for (i = 1; i <= nwant; i++) w = w (i > 1 ? " " : "") want[i]; \
-	            why[++n] = "Valgrind\047s options are [" g "], not the gate\047s [" w "]" } \
 	          if (ran == "") why[++n] = "the log has no \"Reading syms from\" line, so it does not show what Valgrind ran"; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind's options are [--suppressions=build/check-memory-gate/vglib/default.supp -v --command-line-only=yes --log-file=build/memory/memory-plant-leak.valgrind --error-e [cut: 829 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [build/check-memory-gate/vglib/default.supp, tests/guix-glibc-locpath.supp, /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.2 [cut: 287 more characters]
check-memory-gate: FAILED i suppressions: a file named default.supp in place of Valgrind's own fails the leak plant it hides, by name
check-memory-gate: FAILED k added: --undef-value-errors=no, added through VALGRIND, hides that plant, and fails it by name
    got:    test-memory: pass build/check-memory-gate/undef.sps
check-memory-gate: FAILED k dropped: a Valgrind that drops --leak-check=full hides the leak plant, and fails it by name
check-memory-gate: FAILED k changed: a Valgrind that turns --errors-for-leak-kinds=definite to none hides the leak plant, and fails it by name
check-memory-gate: FAILED k order: a Valgrind that moves --leak-check=full to the end of its options fails a clean program, by name
    got:    test-memory: pass build/check-memory-gate/after.sps
```
(28 more such lines cut.)

### MO2. the options check widened: every option the gate passes is listed, and others may be

**Guards:** an option added to the gate's fails the suite.

**Mutation:** In `Makefile`:

```diff
 	          if (got != cmd) why[++n] = "Valgrind\047s Command: line is \"" got "\", not \"" cmd "\""; \
-	          nwant = split(ENVIRON["options"], want, "\n"); same = (nopts == nwant); \
-	          for (i = 1; i <= nwant; i++) if (opts[i] != want[i]) same = 0; \
+	          nwant = split(ENVIRON["options"], want, "\n"); same = 1; \
+	          for (i = 1; i <= nwant; i++) { hit = 0; for (j = 1; j <= nopts; j++) if (opts[j] == want[i]) hit = 1; if (!hit) same = 0 } \
 	          if (!same) { g = ""; for (i = 1; i <= nopts; i++) g = g (i > 1 ? " " : "") opts[i]; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind's options are [--suppressions=build/check-memory-gate/vglib/default.supp -v --command-line-only=yes --log-file=build/memory/memory-plant-leak.valgrind --error-e [cut: 829 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind read the suppressions files [build/check-memory-gate/vglib/default.supp, tests/guix-glibc-locpath.supp, /gnu/store/gsixr2n0a6aacsiy6lky6d1fjh7svqyd-valgrind-3.2 [cut: 287 more characters]
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
check-memory-gate: FAILED i suppressions: a file named default.supp in place of Valgrind's own fails the leak plant it hides, by name
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-leak.sps (exit 0, but Valgrind's options are [--default-suppressions=no --suppressions=build/check-memory-gate/vglib/default.supp -v --command-line-only=yes --log-file=build/memory/memory-pla [cut: 764 more characters]
check-memory-gate: FAILED k added: --undef-value-errors=no, added through VALGRIND, hides that plant, and fails it by name
    got:    test-memory: pass build/check-memory-gate/undef.sps
check-memory-gate: FAILED k order: a Valgrind that moves --leak-check=full to the end of its options fails a clean program, by name
```
(14 more such lines cut.)

### MO3. the options check widened: the same options, in any order

**Guards:** Valgrind's options are the gate's in order.

**Mutation:** In `Makefile`:

```diff
 	          if (got != cmd) why[++n] = "Valgrind\047s Command: line is \"" got "\", not \"" cmd "\""; \
-	          nwant = split(ENVIRON["options"], want, "\n"); same = (nopts == nwant); \
-	          for (i = 1; i <= nwant; i++) if (opts[i] != want[i]) same = 0; \
+	          nwant = split(ENVIRON["options"], want, "\n"); same = 1; \
+	          for (i = 1; i <= nwant; i++) { hit = 0; for (j = 1; j <= nopts; j++) if (opts[j] == want[i]) hit = 1; if (!hit) same = 0 } \
+	          for (j = 1; j <= nopts; j++) { hit = 0; for (i = 1; i <= nwant; i++) if (opts[j] == want[i]) hit = 1; if (!hit) same = 0 } \
 	          if (!same) { g = ""; for (i = 1; i <= nopts; i++) g = g (i > 1 ? " " : "") opts[i]; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED k order: a Valgrind that moves --leak-check=full to the end of its options fails a clean program, by name
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/after.sps (exit 0, but Valgrind's options are [-v --command-line-only=yes --log-file=build/memory/after.valgrind --error-exitcode=9 --show-leak-kinds=definite --errors-for-leak-kinds=def [cut: 296 more characters]
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass build/check-memory-gate/after.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
```

### MO4. --log-file dropped: Valgrind writes into the suite's own log, and the evidence is read from it

**Guards:** the evidence is read from Valgrind's own log, which nothing the suite prints reaches.

**Mutation:** In `Makefile`:

```diff
 	  log=$(MEMORY_LOGS)/$$name.log; \
-	  vlog=$(MEMORY_LOGS)/$$name.valgrind; \
+	  vlog=$$log; \
 	  rm -f "$$log" "$$vlog"; \
 	  echo "=== $$t"; \
-	  set -- -v --command-line-only=yes "--log-file=$$vlog" --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEM [cut: 25 more characters]
+	  set -- -v --command-line-only=yes --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSION_FILE [cut: 5 more characters]
 	  $(TIMEOUT) --foreground $(MEMORY_TIMEOUT) $(VALGRIND) "$$@" $(CHEZ) --libdirs $(LIBDIRS) --program $$t >"$$log" 2>&1; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED b memory-plant-overrun: test-memory names tests/memory-plant-overrun.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
check-memory-gate: FAILED b memory-plant-leak: test-memory names tests/memory-plant-leak.sps FAIL, with Valgrind's report in its log and its output, and runs the suite after it
check-memory-gate: FAILED b fails: test-memory names a program that exits 1 FAIL, with its exit and last lines, and runs the suite after it
check-memory-gate: FAILED d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block
check-memory-gate: FAILED d needed: without the suppression, the same run fails on the one block lost under compute_locale_search_path
check-memory-gate: FAILED d leak: the leak plant fails with the suppression read
check-memory-gate: FAILED d more: a second block lost under newlocale, which the entry matches, fails the suite
check-memory-gate: FAILED d alone: one block lost under newlocale in a run that loads no libcurl, and so no p11-kit, fails the suite
check-memory-gate: FAILED d override: MEMORY_SUPPRESSION_FILE on make's command line, naming a file that hides the overrun plant, is ignored, so the plant fails
check-memory-gate: FAILED e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez, and a Valgrind that runs nothing fails
check-memory-gate: FAILED l forged: a suite that prints a clean ERROR SUMMARY with Valgrind's pid, then execs away, fails: the evidence is Valgrind's own log
    got:    test-memory: pass build/check-memory-gate/forge.sps
```
(154 more such lines cut.)

### MO5. the Valgrind log of the run before not removed

**Guards:** a Valgrind log an earlier run left is never read.

**Mutation:** In `Makefile`:

```diff
 	  vlog=$(MEMORY_LOGS)/$$name.valgrind; \
-	  rm -f "$$log" "$$vlog"; \
+	  rm -f "$$log"; \
 	  echo "=== $$t"; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED l stale: a Valgrind log an earlier run left is never read: a Valgrind that writes none fails
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/after.sps (exit 0, but Valgrind wrote no log, build/memory/after.valgrind)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass build/check-memory-gate/after.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
```

### MO6. the refusal of two suites with one name dropped

**Guards:** one suite's logs are never another's.

**Mutation:** In `Makefile`:

```diff
 	    if [ "$$(basename "$$u" .sps)" = "$$name" ]; then \
-	      echo "test-memory: $$u and $$t share the name $$name, so they would share $(MEMORY_LOGS)/$$name.log and $(MEMORY_LOGS)/$$name.valgrind; rename one (ADR-0014)" >&2; \
-	      refused=1; \
+	      : ; \
 	    fi; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED l names: two suites with one name, in two directories, are refused, so one suite's logs are never another's
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: build/check-memory-gate/after.sps and build/check-memory-gate/twin/after.sps share the name after, so they would share build/memory/after.log and build/memory/after.valgrind; rename one (ADR-0014)
    got:    test-memory: pass build/check-memory-gate/after.sps
    got:    test-memory: pass build/check-memory-gate/twin/after.sps
    got:    test-memory: ran 2, passed 2, failed 0, hung 0
  a suite ran
```

### MO7. override dropped from MEMORY_SUPPRESSION_FILE

**Guards:** make's command line cannot change the suppression the gate passes and allows.

**Mutation:** In `Makefile`:

```diff
 # one-byte invalid write passed the overrun plant).
-override MEMORY_SUPPRESSION_FILE := tests/guix-glibc-locpath.supp
+MEMORY_SUPPRESSION_FILE := tests/guix-glibc-locpath.supp
 
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED d override: MEMORY_SUPPRESSION_FILE on make's command line, naming a file that hides the overrun plant, is ignored, so the plant fails
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL tests/memory-plant-overrun.sps (exit 9, Valgrind's: an error or a definite leak)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass tests/memory-plant-overrun.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
  the planted overrun: no "Invalid write of size 1" in build/memory/memory-plant-overrun.valgrind
  the gate's own suppression read: no "Reading suppressions file: tests/guix-glibc-locpath.supp" in build/memory/memory-plant-overrun.valgrind
  Valgrind read build/check-memory-gate/anywrite.supp:
    | --7856--    --suppressions=build/check-memory-gate/anywrite.supp
    | --7856-- Reading suppressions file: build/check-memory-gate/anywrite.supp
```
(1 more such lines cut.)

### MO8. a weakening option through VALGRIND, on every suite, through the fixed Makefile

**Guards:** the options check holds on the real suites.

**Command** in the container: `make test-memory VALGRIND="valgrind --undef-value-errors=no"`: every suite, with an option VALGRIND adds that turns undefined-value checking off.

**Result:** killed, exit 2:

```
test-memory: FAIL tests/test-check-floors.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-check-floors.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds= [cut: 326 more characters]
test-memory: FAIL tests/test-check-nothreads.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-check-nothreads.valgrind --error-exitcode=9 --leak-check=full --show-leak- [cut: 335 more characters]
test-memory: FAIL tests/test-check-seam.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-check-seam.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=defi [cut: 320 more characters]
test-memory: FAIL tests/test-collect-safe.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-collect-safe.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds= [cut: 326 more characters]
test-memory: FAIL tests/test-conditions.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-conditions.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=defi [cut: 320 more characters]
test-memory: FAIL tests/test-constants.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-constants.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=defini [cut: 317 more characters]
test-memory: FAIL tests/test-curl-testing.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-curl-testing.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds= [cut: 326 more characters]
test-memory: FAIL tests/test-discovery.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-discovery.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=defini [cut: 317 more characters]
test-memory: FAIL tests/test-library-loading.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-library-loading.valgrind --error-exitcode=9 --leak-check=full --show-leak- [cut: 335 more characters]
test-memory: FAIL tests/test-load-state.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-load-state.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=defi [cut: 320 more characters]
test-memory: FAIL tests/test-native.sps (exit 0, but Valgrind's options are [--undef-value-errors=no -v --command-line-only=yes --log-file=build/memory/test-native.valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --e [cut: 308 more characters]
test-memory: ran 14, passed 0, failed 14, hung 0
```
(73 more such lines cut.)

### MC1. the crossing rule dropped

**Guards:** a binding that hands C a bytevector's data needs a marked row.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                        (else (list (list 'mismatch key (cadr row) conventions file))))
-                 (if (and (pair? passed) (not (and row (crossing-marked? row))))
+                 (if #f
                      (list (list 'bytevector-crossing key passed file))
```

**Result:** killed, exit 2:

```
FAIL blocking-plain: ADR-0013's rows: curl_easy_perform and curl_multi_poll bound plain, curl_multi_perform and memcpy bound __collect_safe, and memcpy's u8* unmarked
  expected: (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required ()) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure ()) ("curl_multi_perform [cut: 711 more characters]
  actual:   (returned ((("curl_easy_perform" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" bind-required ()) ("curl_multi_poll" () "tests/fixtures/conventions/blocking-plain/curl/p.sls" foreign-procedure ()) ("curl_multi_perform [cut: 619 more characters]
FAIL crossing-unmarked: bindings that hand C a bytevector's data, none marked: u8*, u16* and u32* parameters, and a callable's u8* result; a procedure's u8* result and a callable's u8* parameter hand C none
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/crossing-unmarked/curl/c.sls" foreign-procedure (u8*)) ("fixture_wide" () "tests/fixtures/conventions/crossing-unmarked/curl/c.sls" foreign-procedure (u16* u32*)) ("fixture_re [cut: 576 more characters]
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/crossing-unmarked/curl/c.sls" foreign-procedure (u8*)) ("fixture_wide" () "tests/fixtures/conventions/crossing-unmarked/curl/c.sls" foreign-procedure (u16* u32*)) ("fixture_re [cut: 280 more characters]
FAIL crossing-wrapper: crossings through known wrappers: a use's parameter list, and a template's own; a use's u8* result hands C none
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required (u8*)) ("fixture_result" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required ()) ("fixture_bytes" () "tests/fi [cut: 265 more characters]
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required (u8*)) ("fixture_result" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required ()) ("fixture_bytes" () "tests/fi [cut: 71 more characters]
FAIL crossing-marked: a row marked as the reviewed crossing clears its bindings, direct and wrapped; a mark that quotes nothing clears none
  expected: (returned ((("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" foreign-procedure (u8*)) ("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" bind-required (u8*)) ("fixture_cr [cut: 215 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```
(1 more such lines cut.)

### MC2. a u8* binding added to src/ through bind-required

**Guards:** the live scan of src/ reads a wrapper use's parameter list.

**Mutation:** In `src/curl/private/native.sls`:

```diff
   (define curl-easy-cleanup (load-step (bind-required "curl_easy_cleanup" (uptr) void info)))
+  (define memcpy-in (load-step (bind-required "memcpy" (u8* uptr size_t) uptr info)))
 
```

**Result:** killed, exit 2:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((bytevector-crossing "memcpy" (u8*) "src/curl/private/native.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MC3. a u8* binding added to src/ directly

**Guards:** the live scan of src/ reads a direct binding's parameter list.

**Mutation:** In `src/curl/private/native.sls`:

```diff
   (define curl-easy-cleanup (load-step (bind-required "curl_easy_cleanup" (uptr) void info)))
+  (define memcpy-in (foreign-procedure "memcpy" (u8* uptr size_t) uptr))
 
```

**Result:** killed, exit 2:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((bytevector-crossing "memcpy" (u8*) "src/curl/private/native.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MC4. the mark accepted without a citation: a fourth element headed bytevector-crossing marks the row

**Guards:** a mark must quote a record, for table-violations and table-problems alike.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
          (let ((mark (cadddr row)))
-           (and (list? mark)
-                (= (length mark) 2)
-                (eq? (car mark) 'bytevector-crossing)
-                (string? (cadr mark))))))
+           (and (pair? mark)
+                (eq? (car mark) 'bytevector-crossing)))))
 
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a crossing mark that quotes nothing
  expected: (returned ((crossing-mark-shape "x" (bytevector-crossing))))
  actual:   (raised "Exception in cadr: incorrect list structure (bytevector-crossing)")
FAIL crossing-marked: a row marked as the reviewed crossing clears its bindings, direct and wrapped; a mark that quotes nothing clears none
  expected: (returned ((("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" foreign-procedure (u8*)) ("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" bind-required (u8*)) ("fixture_cr [cut: 215 more characters]
  actual:   (returned ((("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" foreign-procedure (u8*)) ("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" bind-required (u8*)) ("fixture_cr [cut: 105 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MC5. the mark's citation unchecked by table-problems

**Guards:** a mark's citation names a record and a phrase it holds.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
       (else
-       (append (citation-problems (car row) (cadr (cadddr row)) root mark-citation)
+       (append '()
                (if (member '__collect_safe (cadr row))
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a crossing mark citing no record
  expected: (returned ((crossing-citation-not-a-record "x" ".plans/decisions/9999-no-such-record.md")))
  actual:   (returned ())
FAIL table-problems, seeded: a crossing mark quoting a phrase the record does not hold
  expected: (returned ((crossing-citation-phrase-missing "x" ".plans/decisions/0013-collect-safe-blocking-calls.md" "Bytevectors cross anywhere.")))
  actual:   (returned ())
FAIL table-problems, seeded: a crossing mark whose citation has no phrase
  expected: (returned ((crossing-citation-shape "x" ".plans/decisions/0013-collect-safe-blocking-calls.md")))
  actual:   (returned ())
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MC6. types the reader cannot read accepted, so long as they are a list

**Guards:** a parameter list the reader cannot read fails closed.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
   (define (readable-types? types)
-    (and (list? types) (for-all readable-type? types)))
+    (list? types))
 
```

**Result:** killed, exit 2:

```
FAIL types-unreadable: types the reader cannot read: a string, a list that is no (* name), a callable's result, and a wrapper use's parameter list that is a variable, improper, or missing
  expected: (returned ((("fixture_result" () "tests/fixtures/conventions/types-unreadable/curl/t.sls" foreign-procedure ())) ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (u [cut: 684 more characters]
  actual:   (returned ((("fixture_wide" () "tests/fixtures/conventions/types-unreadable/curl/t.sls" foreign-procedure ()) ("fixture_wide" () "tests/fixtures/conventions/types-unreadable/curl/t.sls" foreign-procedure ()) ("fixture_result" () [cut: 619 more characters]
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal, parameters mixed, and literal but no typ [cut: 2 more characters]
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [cut: 2143 more characters]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [cut: 1950 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MC7. a callable's result not read

**Guards:** a callable that returns u8* hands C a bytevector's data.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                    (emit! (list 'binding name (car parts) path 'foreign-callable
-                                (crossings (list (cadddr parts))))))))
+                                '())))))
           (walk-elements callable 1 #f)))
```

**Result:** killed, exit 2:

```
FAIL crossing-unmarked: bindings that hand C a bytevector's data, none marked: u8*, u16* and u32* parameters, and a callable's u8* result; a procedure's u8* result and a callable's u8* parameter hand C none
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/crossing-unmarked/curl/c.sls" foreign-procedure (u8*)) ("fixture_wide" () "tests/fixtures/conventions/crossing-unmarked/curl/c.sls" foreign-procedure (u16* u32*)) ("fixture_re [cut: 576 more characters]
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/crossing-unmarked/curl/c.sls" foreign-procedure (u8*)) ("fixture_wide" () "tests/fixtures/conventions/crossing-unmarked/curl/c.sls" foreign-procedure (u16* u32*)) ("fixture_re [cut: 478 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MC8. a marked row allowed __collect_safe

**Guards:** ADR-0013's decision 4: no bytevector to a call that can block.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
        (append (citation-problems (car row) (cadr (cadddr row)) root mark-citation)
-               (if (member '__collect_safe (cadr row))
+               (if #f
                    (list (list 'crossing-collect-safe (car row)))
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a crossing marked on a __collect_safe row: ADR-0013's decision 4
  expected: (returned ((crossing-collect-safe "x")))
  actual:   (returned ())
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MC9. a wrapper use's parameter list not read

**Guards:** a use of a known wrapper carries its own parameter list's crossings.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                                  (cons (list (list-ref form index) conventions file name
-                                             (crossings (use-types form reading)))
+                                             '())
                                        bindings)
```

**Result:** killed, exit 2:

```
FAIL crossing-wrapper: crossings through known wrappers: a use's parameter list, and a template's own; a use's u8* result hands C none
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required (u8*)) ("fixture_result" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required ()) ("fixture_bytes" () "tests/fi [cut: 265 more characters]
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required ()) ("fixture_result" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required ()) ("fixture_bytes" () "tests/fixtu [cut: 65 more characters]
FAIL crossing-marked: a row marked as the reviewed crossing clears its bindings, direct and wrapped; a mark that quotes nothing clears none
  expected: (returned ((("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" foreign-procedure (u8*)) ("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" bind-required (u8*)) ("fixture_cr [cut: 215 more characters]
  actual:   (returned ((("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" foreign-procedure (u8*)) ("fixture_crossing" () "tests/fixtures/conventions/crossing-marked/curl/m.sls" bind-required ()) ("fixture_cross [cut: 212 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### Clean rerun

Every command in item 2 ran on the final working tree, in the container, one after another
(`slice5/fix2/final-item2.txt`; each whole output is beside it as `final-*.txt`):

```
make test-memory: exit 0 in 106s; test-memory: ran 14, passed 14, failed 0, hung 0
make check-memory-gate: exit 0 in 103s; check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 36 cases
env -u GUIX_ENVIRONMENT make check-memory-gate: exit 0 in 80s; check-memory-gate: the memory gate failed, as it must, and its suppression held, in all 30 cases
make test: exit 0 in 13s; test: ran 14, passed 14, failed 0, hung 0
make check-help: exit 0 in 1s;
```

With `GUIX_ENVIRONMENT` unset, the run said `check-memory-gate: skipped d: GUIX_ENVIRONMENT is
unset, so test-memory passes no suppression here, and there is none to hold`.

The mutations ran on frozen copies of this tree. Its Makefile, `tests/check-memory-gate.sh`,
`tests/foreign-conventions.sls`, `tests/test-collect-safe.sps` and
`tests/fixtures/conventions/` are byte for byte the copies' (`cmp`, `diff -r`).
### Not covered

- **The programs `VALGRIND` and `TIMEOUT` name are trusted.** A stand-in for Valgrind can write
  any log, and so can a tool binary chosen through `TIMEOUT='env VALGRIND_LIB=…'`. No check of a
  log tells a forged Valgrind from a real one.
- **A suite that writes into its own Valgrind log by path** (`build/memory/SUITE.valgrind`) could
  still forge lines there. Only its standard streams are kept out.
- **The crossing rule reads `u8*`, `u16*` and `u32*` only.** A `scheme-object` parameter hands C
  a Scheme object, a bytevector among them. A `string`, `utf-8`, `utf-16*` or `utf-32*` parameter
  hands C a pointer into a temporary copy on Chez's heap. Valgrind sees neither. `src/` binds
  `string` parameters today (`curl_easy_option_by_name`, `curl_easy_header`).
- **`k undef` is measured on amd64, in the container only.** Docker has no Chez, so CI's Chez
  first meets the undefined-value plant in CI. If it reports nothing there, the case fails, by
  name.

## The lead's addition: scheme-object

After the second review's fixes, the crossing rule in `(foreign-conventions)` counted `u8*`,
`u16*` and `u32*`. A `scheme-object` parameter, or a callable's `scheme-object` result, also
hands C a pointer into Chez's heap, so it joined `crossing-types`. `string` and `utf-8` stay
out: Chez hands C a fresh NUL-terminated copy for each call, which libcurl only reads
(ADR-0013, amended).

The case came first. `tests/fixtures/conventions/crossing-object/` binds `fixture_object`
with a `scheme-object` parameter, and makes `on-object` with a `scheme-object` result;
`tests/test-collect-safe.sps` holds the whole violation list for it.

### Red run

The case, against the reader without `scheme-object`:

```
FAIL crossing-object: bindings that hand C a Scheme object itself, none marked: a procedure's scheme-object parameter and a callable's scheme-object result
  expected: (returned ((("fixture_object" () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-procedure (scheme-object)) (on-object () "tests/fixtures/conventions/crossing-object/curl/o [cut]
  actual:   (returned ((("fixture_object" () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-procedure ()) (on-object () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign [cut]
# of expected passes      51
# of unexpected failures  1
```

### Clean rerun

With `scheme-object` in `crossing-types`:

```
# of expected passes      52
```

## Third review fixes

The third review left two findings. The first was settled by the maintainer as
[ADR-0013](decisions/0013-collect-safe-blocking-calls.md)'s amendment "what a binding may hand C
from Chez's heap". Each fix closes a class:

1. **The convention suite read types through a deny list.** It flagged `u8*`, `u16*`, `u32*`
   and `scheme-object`, and took any other symbol as safe. So a macro that is no known wrapper
   could take a type from its use. The reviewer's `(bind-memcpy u8*)` bound `memcpy` with a
   `u8*` parameter and passed. String types, which Chez copies into its own heap, passed
   unseen.
2. **test-memory's evidence check passed when awk failed.** The check's output was its verdict,
   and empty meant pass. Its exit status was never read, so an awk that exits 2 printing
   nothing passed the wrapper-CHEZ leak plant.

The part changes these files:

- `tests/foreign-conventions.sls`:
  - **Types are an allowlist.** Every parameter and result type of every binding must be one
    of these, else the binding is `types-unreadable`:
    - an immediate or address type on `immediate-types`, or `void` as a result;
    - `(* NAME)` or `(& NAME)`, where NAME is a `(define-ftype NAME TYPE)` in the tree's
      `(curl private layouts)`, read as data from `ROOT/curl/private/layouts.sls`;
    - a crossing type.

    This covers direct procedures, callables (now their parameters too) and a known wrapper's
    uses (now their result too). A wrapper whose result is neither a type nor a pattern
    variable at a fixed place is unreadable, with the new reason `unplaced-result`.
  - **Pattern variables are tracked.** Inside a `syntax-rules`, `syntax-case`, `with-syntax` or
    `identifier-syntax` form, every symbol of its clauses' patterns, `_` and `...` aside, is a
    pattern variable. A type in a binding, or written by a wrapper's use, that is one of these
    is `types-unreadable`. A convention that is one is the new violation
    `(conventions-from-pattern FILE FORM)`. This goes beyond the brief: an allowlist alone
    passed a pattern variable spelt `uptr` (measured below).
  - **Three crossing kinds, each its own violation:**
    - `(bytevector-crossing KEY TYPES FILE)`: `u8*`, `u16*` or `u32*`, unless the row is marked
      `(bytevector-crossing CITATION)`;
    - `(string-crossing KEY TYPES FILE)`: `string`, `utf-8`, `utf-16le`, `utf-16be`,
      `utf-32le`, `utf-32be` or `wstring`, unless the row is marked
      `(string-not-kept CITATION)`;
    - `(scheme-object KEY TYPES FILE)`: `scheme-object` anywhere, as a parameter or result of
      either, marked or not.

    The first two count as crossings as a procedure's parameters or a callable's result. A
    procedure's `u8*` or string result, and a callable's `u8*` or string parameter, are copies.
  - A row has one mark at most, of either kind. Both kinds' citations are checked as the row's
    own is, and a marked row of either kind is never `__collect_safe`.
  - `curl_easy_option_by_name` and `curl_easy_header` are marked `(string-not-kept ...)`,
    quoting ADR-0013: "`curl_easy_option_by_name` and `curl_easy_header` read their name
    argument during the call, and keep no pointer to it."
  - A callable's `types-unreadable` names its whole `define`, so the binding.
- `tests/test-collect-safe.sps`:
  - six new fixture cases: `types-macro-argument` (the reviewer's tree), `types-pattern-variable`,
    `types-layouts`, `types-allowed`, `string-unmarked` and `string-marked`;
  - `crossing-object`, `crossing-wrapper`, `types-unreadable` and `wrapper-unreadable` extended;
  - four new seeded tables for the `string-not-kept` mark;
  - the live test "no row is marked" replaced by two. The table marks exactly the two rows,
    each with the citation written out in the suite. The live scan's crossings are exactly
    `(string)` for each of those two entries.
- `tests/fixtures/conventions/`: the six new trees; `crossing-object`, `crossing-wrapper`,
  `types-unreadable` and `wrapper-unreadable` extended.
- `Makefile`, the memory-gate section only:
  - test-memory's awk prints `ok`, alone, when it finds nothing wrong.
  - A suite that exits 0 passes only when awk exits 0 and prints exactly `ok`. Otherwise it
    FAILs: `the evidence check (awk) exited N`, `the evidence check (awk) printed no "ok"
    line`, or the problems awk printed.
- `tests/check-memory-gate.sh`: case `m awk`, three arms, each with a stand-in for awk first on
  `PATH`, which logs its calls. A clean program must FAIL, naming the evidence check, under an
  awk that fails printing nothing, one that prints `ok` then exits 2, and one that exits 0
  printing nothing. Each arm checks that the stand-in got the suite's command, so that it was
  the evidence check. The case count goes from 36 to 39 in the container, and from 30 to 33
  outside Guix.

The driver is `slice5/fix3/mutate.py` in the session scratchpad, adapted from fix2's. It froze
six trees, without `.git`, `build/` or `.claude/`:

- `snap/`, the fixed working tree;
- `snap-before/`, the tree before these fixes;
- `snap-red-conv/`, `snap-before/` with the new suite and fixtures;
- `snap-red-gate/`, `snap-before/` with the new `tests/check-memory-gate.sh`;
- `snap-red-cz/` and `snap-cz/`, `snap-before/` and `snap/` with the reviewer's probe trees
  `cz` and `cx`, and `cw`, under `probe/`, and `probe-run.sps`, which runs `check-conventions`
  on each.

Each case got a fresh copy, a touched `manifest.scm`, and its command through the copy's own
`scripts/guix-env`. Each edit was an exact-text replacement that had to match exactly once.
Three ran at a time. A case counts as killed only when its command exits non-zero and every
expected line is present: whole, as a substring (`~` first), or as a prefix (`~` last). The
working tree was never edited.
### Measurements

All in the container: Chez 10.4.0, Valgrind 3.27.0, GNU awk, amd64. The mawk run used fix2's
Docker image (`chez-curl-vg322:gcc`: Ubuntu 24.04, Valgrind 3.22.0, GNU Make 4.3, mawk).

**The allowlist's source.** `immediate-types` is the list of parameter and result types in
CSUG 10.4.0 §4.2, read from the Guix store's `chez-scheme-10.4.0-doc`
(`csug/foreign.html`). It keeps those that convert a value:

```
integer-8 unsigned-8 integer-16 unsigned-16 integer-32 unsigned-32 integer-64 unsigned-64
double-float single-float double float short unsigned-short int unsigned unsigned-int
long unsigned-long long-long unsigned-long-long ptrdiff_t size_t ssize_t iptr uptr void*
fixnum boolean stdbool char wchar_t wchar
```

`void` is allowed as a result only. The pinned Chez's behaviour was then probed
(`slice5/fix3/probe/types.txt`). Each type was `eval`ed as a foreign-procedure parameter and
result, and as a foreign-callable parameter and result, against libc's `strlen`:

- every listed type is accepted in all four places;
- `void` is refused as a parameter, procedure or callable ("invalid foreign-procedure argument
  type specifier"), and accepted as a result;
- `u64*`, `bytevector` and `uint32_t` are refused everywhere;
- Chez also accepts, everywhere, types the list leaves out, which the reader therefore finds
  unreadable:
  - `integer-24`, `unsigned-24`, `integer-40`, `integer-48`, `integer-56` and `unsigned-56`,
    which CSUG documents as neither parameter nor result types;
  - `ptr`, CSUG's alias for `scheme-object`;
  - `utf-16` and `utf-32`, string types CSUG lists that ADR-0013's string kind does not;
  - `ftype-pointer`, which can carry a pointer to a Scheme object;
  - `ftype-scheme-object-pointer`, which hands C an address in Chez's heap.

**A pattern variable spelt as an allowed type** (`slice5/fix3/probe-pattern-named-uptr.txt`).
On the reader with the allowlist but no pattern tracking, this tree passed, read as `memcpy`
taking `(uptr uptr size_t)`:

```
(define-syntax bind-memcpy
  (syntax-rules ()
    ((_ uptr) (foreign-procedure "memcpy" (uptr uptr size_t) uptr))))
(define copy-in (bind-memcpy u8*))
```

Loaded and called, Chez bound every `uptr` as `u8*`. `(copy-in b a 4)` copied one bytevector
into another: `#vu8(7 7 7 7)`. That is why the reader tracks pattern variables.

**mawk** (`slice5/fix3/docker-mawk.txt`). The fixed recipe ran with a stand-in for Chez, `make
test-memory MEMORY_SUITES=tests/memory-plant-leak.sps CHEZ=/work/fake`:

```
clean                           exit 0  test-memory: pass tests/memory-plant-leak.sps
PLANT=leak                      exit 2  FAIL (exit 9, Valgrind's: an error or a definite leak)
PLANT=forge                     exit 2  FAIL (exit 0, but Valgrind reported no "ERROR SUMMARY: 0 errors from 0 contexts")
an awk that fails               exit 2  FAIL (exit 0, but the evidence check (awk) exited 2)
an awk that prints nothing      exit 2  FAIL (exit 0, but the evidence check (awk) printed no "ok" line)
```

**Cost.**

- `make test`: 14 s.
- `make test-memory`, all 14 suites: 109 s.
- `make check-memory-gate`: 112 s in the container (39 cases), and 88 s with `GUIX_ENVIRONMENT`
  unset (33 cases).

### Red runs

**The probe trees on the old reader (R0).** `check-conventions` passed all three with no
violation. These are the reviewer's `cz` (a `u8*` handed in as a macro argument) and `cx` (a
`string` parameter, and a callable's `utf-8` result), and this part's `cw` (a pattern variable
spelt `uptr`). On the fixed reader (R1), `cz` and `cw` are `types-unreadable`, and `cx`'s two
crossings are `string-crossing`.

**The new conventions cases (R2).** The new suite and fixtures ran against the old reader and
failed by name, 14 tests in all:

- the six new fixture trees but `types-allowed`;
- the four extended ones: `crossing-object`, `crossing-wrapper`, `types-unreadable` and
  `wrapper-unreadable`;
- three of the four new seeded tables;
- both new live tests.

Two new tests passed, as controls. `types-allowed` passes because the old reader took any symbol.
"A string-not-kept mark that quotes nothing" passes because the old reader refused every mark
that was not `bytevector-crossing`.

**The new check-memory-gate case (R3).** It ran against the old Makefile, and all three `m awk`
arms failed by name. Under the awk that fails and the one that prints nothing, the clean program
got `test-memory: pass`: that is the hole. Under the awk that prints `ok`, then exits 2, the old
gate took `ok` as a problem: `FAIL ... (exit 0, but ok)`. The other 36 cases passed.
### Mutations

26 cases ran, each in a fresh copy:

- four red runs. R2 and R3 are killed. R0 passes, as the holes did, and R1 shows each hole named;
- 22 runs on the fixed tree, all killed, each with every expected line present. Eight are the
  brief's (MT1 to MT6, MA1, MA2). The other 14 are one each for a new rule that nothing else
  fails (MN1 to MN13, with MN4b).

| ID | Change | Killed by |
|---|---|---|
| R0 | the probe trees `cz`, `cx`, `cw`, old reader | as expected: all three pass, no violation |
| R1 | the same trees, fixed reader | as expected: `cz` and `cw` `types-unreadable`, `cx` two `string-crossing` |
| R2 | the new suite and fixtures, old reader | 14 tests `FAIL` by name |
| R3 | the new `m awk` case, old Makefile | all three arms `FAILED`; two clean runs passed there |
| MT1 | the allowlist widened to any symbol | `types-unreadable` (`uint32_t`, `void` as a parameter, `ptr`, `utf-16`) |
| MT2 | the string kind read as a value | `string-unmarked`, `string-marked`, the live crossings test |
| MT3 | the `string-not-kept` mark accepted without a citation | `string-marked`; seeded "a string-not-kept mark that quotes nothing" |
| MT4 | `curl_easy_option_by_name`'s marked row made `__collect_safe` | the table's own test: `(crossing-collect-safe "curl_easy_option_by_name")`; `src/ holds to the table` |
| MT5 | `scheme-object` accepted under a mark | `crossing-object` |
| MT6 | the layouts check dropped: `(* NAME)` for any symbol | `types-layouts` |
| MA1 | awk's `ok` line not required | `m awk` silent: the clean program passed |
| MA2 | awk's exit status ignored | `m awk` ok-fails: the clean program passed; `m awk` fails, by its reason |
| MN1 | a callable's parameters not read | `crossing-object`, `types-unreadable` |
| MN2 | a procedure's result not read | `crossing-object`, `types-unreadable`, `types-layouts` |
| MN3 | a wrapper use's result not read | `crossing-wrapper`, `types-unreadable` |
| MN4 | `result-reading`'s last branch read as a type | `wrapper-unreadable` (`w-pointer-result`) |
| MN4b | the `unplaced-result` check dropped | `wrapper-unreadable` |
| MN5 | `void` accepted as a parameter | `types-unreadable` |
| MN6 | a mark clears every kind | `string-marked` |
| MN7 | pattern variables not tracked | `types-pattern-variable` |
| MN8 | a wrapper use's types not checked for pattern variables | `types-pattern-variable` |
| MN9 | `with-syntax` not tracked | `types-pattern-variable` |
| MN10 | `identifier-syntax` not tracked | `types-pattern-variable` |
| MN11 | a direct binding's conventions not checked for pattern variables | `types-pattern-variable` |
| MN12 | any definition in layouts admitted as an ftype | `types-layouts` (`not-an-ftype`) |
| MN13 | `curl_easy_header`'s mark dropped | `src/ holds to the table`: `(string-crossing "curl_easy_header" (string) "src/curl/private/native.sls")`; the marks test |

Two rules hold the reviewer's tree, each on its own. Under MT1 (no allowlist),
`types-macro-argument` still fails, because `buffer` is a pattern variable. Under MN7 (no
tracking), it still fails, because `buffer` is on no allowlist.

The first pass got two cases wrong; it is kept in `slice5/fix3/run-all.txt`:

- **MT1 "survived".** Its expected lines named `types-macro-argument`, which pattern tracking
  holds whatever the allowlist does. The mutant was killed by `types-unreadable` on that pass,
  and the expectation was corrected.
- **MN4 survived, rightly.** It edited `result-reading`'s `else` branch, and no fixture reached
  that branch. `w-nested-result`'s variable is caught by the branch before. So
  `w-pointer-result`, whose result is `(* r)`, was added. MN4b mutates the `unplaced-result`
  check itself. The trees were refrozen, and every case but R3, MA1 and MA2 ran again: the
  Makefile and `tests/check-memory-gate.sh` are the same in both freezes.

### R0. the reviewer's probe trees through the reader as it was before these fixes

**Guards:** the holes are real: a type from a macro argument, string parameters and a callable's string result, and a pattern variable spelt uptr, all pass.

**Tree:** the tree before these fixes, with the reviewer's probe trees probe/cz and probe/cx, and probe/cw.

**Command** in the container: each probe tree through `check-conventions`, with the real table and rows for the probe's `curl_easy_setopt` and `on-name`: `probe-run.sps`.

**Result:** as expected, exit 0:

```
probe/cz: ((("memcpy" () "probe/cz/curl/z.sls" foreign-procedure ())) ())
probe/cx: ((("curl_easy_setopt" ((__varargs_after 2)) "probe/cx/curl/k.sls" foreign-procedure ()) (on-name () "probe/cx/curl/k.sls" foreign-callable ())) ())
probe/cw: ((("memcpy" () "probe/cw/curl/w.sls" foreign-procedure ())) ())
```

### R1. the reviewer's probe trees through the fixed reader

**Guards:** each hole now fails by name.

**Tree:** the fixed tree, with the reviewer's probe trees probe/cz and probe/cx, and probe/cw.

**Command** in the container: each probe tree through `check-conventions`, with the real table and rows for the probe's `curl_easy_setopt` and `on-name`: `probe-run.sps`.

**Result:** as expected, exit 0:

```
probe/cz: (() ((types-unreadable "probe/cz/curl/z.sls" "(foreign-procedure \"memcpy\" (buffer uptr size_t) uptr)")))
probe/cx: ((("curl_easy_setopt" ((__varargs_after 2)) "probe/cx/curl/k.sls" foreign-procedure (string)) (on-name () "probe/cx/curl/k.sls" foreign-callable (utf-8))) ((string-crossing "curl_easy_setopt" (string) "probe/cx/curl/k.sls") (strin [cut: 51 more characters]
probe/cw: (() ((types-unreadable "probe/cw/curl/w.sls" "(foreign-procedure \"memcpy\" (uptr uptr size_t) uptr)")))
```

### R2. the new conventions suite and fixtures against the reader as it was before these fixes

**Guards:** each new case fails against the code it was written to change.

**Tree:** the tree before these fixes, with the new tests/test-collect-safe.sps and tests/fixtures/conventions/.

**Result:** killed, exit 2:

```
FAIL crossing-object: scheme-object, never allowed: a procedure's parameter and result, a callable's result and parameter, and a parameter under each kind of mark
FAIL crossing-wrapper: crossings through known wrappers: a use's parameter list, a template's own, and a use's result; a use's u8* result hands C none, and its scheme-object result is never allowed
FAIL types-unreadable: types the reader cannot read: a string, a list that is no (* name), a callable's result, a wrapper use's parameter list that is a variable, improper, or missing; and types on no allowlist: a name that is no Chez type, [cut: 103 more characters]
FAIL types-macro-argument: the third review's tree: a type that is a pattern variable, in a macro that is no known wrapper, whose use supplies u8*
FAIL types-pattern-variable: pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, syntax-case through a wrapper's use, with-syntax, identifier-syntax, a callable's result, and a convention; a  [cut: 48 more characters]
FAIL types-layouts: (* NAME) and (& NAME), read when NAME is an ftype the tree's (curl private layouts) defines, as parameters, a result and a callable's; an ftype defined elsewhere, a variable of layouts, and none, unreadable
FAIL string-unmarked: bindings that hand C a string from Chez's heap, none marked: a string parameter, one of each other string type, one through the known wrapper, and a callable's utf-8 result; a procedure's utf-8 result and a callable's  [cut: 28 more characters]
FAIL string-marked: a row marked string-not-kept clears its strings, direct, wrapped and a callable's result; a mark that quotes nothing clears none, and each mark clears its own kind alone
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal, parameters mixed, literal but no types,  [cut: 51 more characters]
FAIL the table marks exactly curl_easy_option_by_name and curl_easy_header, each string-not-kept, citing what their callees keep
FAIL the scan of src/ finds two crossings, a string each: curl_easy_option_by_name's name and curl_easy_header's
test: FAIL tests/test-collect-safe.sps (exit 1)
```
(31 more such lines cut.)

### R3. the new check-memory-gate case against the Makefile as it was before these fixes

**Guards:** each arm fails against the code it was written to change, and the hole is real.

**Tree:** the tree before these fixes, with the new tests/check-memory-gate.sh.

**Result:** killed, exit 2:

```
check-memory-gate: FAILED m awk: an awk that fails, printing nothing, fails a clean program, naming the evidence check
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/after.sps (exit 0, but the evidence check (awk) exited 2)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass build/check-memory-gate/after.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
check-memory-gate: FAILED m awk: an awk that prints ok, then exits 2, fails a clean program, naming the evidence check
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/after.sps (exit 0, but the evidence check (awk) exited 2)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
check-memory-gate: FAILED m awk: an awk that exits 0, printing nothing, fails a clean program, naming the evidence check
```
(8 more such lines cut.)

### MT1. the allowlist widened to any symbol

**Guards:** a type on no allowlist, a pattern variable among them, is unreadable.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
            'value)
+          ((symbol? type) 'value)
           (else #f)))
```

**Result:** killed, exit 2:

```
FAIL types-unreadable: types the reader cannot read: a string, a list that is no (* name), a callable's result, a wrapper use's parameter list that is a variable, improper, or missing; and types on no allowlist: a name that is no Chez type, [cut: 103 more characters]
  expected: (returned (() ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (uptr \"u8*\") int)") (types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(fo [cut: 1541 more characters]
  actual:   (returned ((("fixture_wide" () "tests/fixtures/conventions/types-unreadable/curl/t.sls" foreign-procedure ()) ("fixture_wide" () "tests/fixtures/conventions/types-unreadable/curl/t.sls" foreign-procedure ()) ("fixture_wide" () " [cut: 1360 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MT2. the string kind read as a value

**Guards:** a string handed to C is a crossing.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
           ((memq type bytevector-types) 'bytevector)
-          ((memq type string-types) 'string)
+          ((memq type string-types) 'value)
           ((memq type object-types) 'object)
```

**Result:** killed, exit 2:

```
FAIL string-unmarked: bindings that hand C a string from Chez's heap, none marked: a string parameter, one of each other string type, one through the known wrapper, and a callable's utf-8 result; a procedure's utf-8 result and a callable's  [cut: 28 more characters]
  expected: (returned ((("fixture_string" () "tests/fixtures/conventions/string-unmarked/curl/s.sls" foreign-procedure (string)) ("fixture_strings" () "tests/fixtures/conventions/string-unmarked/curl/s.sls" foreign-procedure (utf-8 utf-16le [cut: 867 more characters]
  actual:   (returned ((("fixture_string" () "tests/fixtures/conventions/string-unmarked/curl/s.sls" foreign-procedure ()) ("fixture_strings" () "tests/fixtures/conventions/string-unmarked/curl/s.sls" foreign-procedure ()) ("fixture_string" [cut: 368 more characters]
FAIL string-marked: a row marked string-not-kept clears its strings, direct, wrapped and a callable's result; a mark that quotes nothing clears none, and each mark clears its own kind alone
  expected: (returned ((("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" foreign-procedure (string)) ("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" bind-required (strin [cut: 751 more characters]
  actual:   (returned ((("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" foreign-procedure ()) ("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" bind-required ()) (on-kept [cut: 509 more characters]
FAIL the scan of src/ finds two crossings, a string each: curl_easy_option_by_name's name and curl_easy_header's
  expected: (("curl_easy_option_by_name" (string)) ("curl_easy_header" (string)))
  actual:   ()
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MT3. the string-not-kept mark accepted without a citation

**Guards:** a string-not-kept mark must quote a record, for table-violations and table-problems alike.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
          (let ((mark (cadddr row)))
-           (and (list? mark)
-                (= (length mark) 2)
-                (memq (car mark) mark-kinds)
-                (string? (cadr mark))
-                mark))))
+           (or (and (pair? mark) (eq? (car mark) 'string-not-kept) mark)
+               (and (list? mark)
+                    (= (length mark) 2)
+                    (memq (car mark) mark-kinds)
+                    (string? (cadr mark))
+                    mark)))))
 
```

**Result:** killed, exit 2:

```
FAIL table-problems, seeded: a string-not-kept mark that quotes nothing
  expected: (returned ((crossing-mark-shape "x" (string-not-kept))))
  actual:   (raised "Exception in cadr: incorrect list structure (string-not-kept)")
FAIL string-marked: a row marked string-not-kept clears its strings, direct, wrapped and a callable's result; a mark that quotes nothing clears none, and each mark clears its own kind alone
  expected: (returned ((("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" foreign-procedure (string)) ("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" bind-required (strin [cut: 751 more characters]
  actual:   (returned ((("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" foreign-procedure (string)) ("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" bind-required (strin [cut: 645 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MT4. a marked string row made __collect_safe: curl_easy_option_by_name's

**Guards:** ADR-0013's decision 4: no string to a call that can block.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
           (list "curl_global_init" '() cannot-block)
-          (list "curl_easy_option_by_name" '() cannot-block (list 'string-not-kept name-not-kept))
+          (list "curl_easy_option_by_name" '(__collect_safe) cannot-block (list 'string-not-kept name-not-kept))
           (list "curl_easy_init" '() cannot-block)
```

**Result:** killed, exit 2:

```
FAIL the table's citations each name a decision record that exists, and quote it
  expected: (returned ())
  actual:   (returned ((crossing-collect-safe "curl_easy_option_by_name")))
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((mismatch "curl_easy_option_by_name" (__collect_safe) () "src/curl/private/native.sls"))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MT5. scheme-object accepted under a mark

**Guards:** scheme-object is never allowed, marked or not.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                                  (and row (marked? row 'string-not-kept)) key file)
-                 (kind-violation 'scheme-object object-types passed #f key file))))
+                 (kind-violation 'scheme-object object-types passed (and row (row-mark row) #t) key file))))
      '() bindings))
```

**Result:** killed, exit 2:

```
FAIL crossing-object: scheme-object, never allowed: a procedure's parameter and result, a callable's result and parameter, and a parameter under each kind of mark
  expected: (returned ((("fixture_object" () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-procedure (scheme-object)) (on-object () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-callable (scheme-object))  [cut: 1106 more characters]
  actual:   (returned ((("fixture_object" () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-procedure (scheme-object)) (on-object () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-callable (scheme-object))  [cut: 880 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MT6. the layouts check dropped: (* NAME) read for any symbol NAME

**Guards:** (* NAME) and (& NAME) name an ftype layouts defines.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                 (memq (car type) '(* &))
-                (memq (cadr type) ftypes))
+                (symbol? (cadr type)))
            'value)
```

**Result:** killed, exit 2:

```
FAIL types-layouts: (* NAME) and (& NAME), read when NAME is an ftype the tree's (curl private layouts) defines, as parameters, a result and a callable's; an ftype defined elsewhere, a variable of layouts, and none, unreadable
  expected: (returned ((("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) ("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) (on-pointed () "tests/ [cut: 486 more characters]
  actual:   (returned ((("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) ("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) (on-pointed () "tests/ [cut: 364 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MA1. awk's ok line not required

**Guards:** an awk that exits 0 but prints no "ok" fails the suite.

**Mutation:** In `Makefile`:

```diff
 	      why="the evidence check (awk) exited $$checked"; \
-	    elif [ -z "$$evidence" ]; then \
-	      why='the evidence check (awk) printed no "ok" line'; \
 	    elif [ "$$evidence" != ok ]; then \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED m awk: an awk that exits 0, printing nothing, fails a clean program, naming the evidence check
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/after.sps (exit 0, but the evidence check (awk) printed no "ok" line)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass build/check-memory-gate/after.sps
    got:    test-memory: ran 1, passed 1, failed 0, hung 0
```

### MA2. awk's exit status ignored

**Guards:** an awk that exits non-zero fails the suite, whatever it printed.

**Mutation:** In `Makefile`:

```diff
 	    checked=$$?; \
-	    if [ $$checked -ne 0 ]; then \
-	      why="the evidence check (awk) exited $$checked"; \
-	    elif [ -z "$$evidence" ]; then \
+	    if [ -z "$$evidence" ]; then \
 	      why='the evidence check (awk) printed no "ok" line'; \
```

**Result:** killed, exit 2:

```
check-memory-gate: FAILED m awk: an awk that fails, printing nothing, fails a clean program, naming the evidence check
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/after.sps (exit 0, but the evidence check (awk) exited 2)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: FAIL build/check-memory-gate/after.sps (exit 0, but the evidence check (awk) printed no "ok" line)
    got:    test-memory: ran 1, passed 0, failed 1, hung 0
check-memory-gate: FAILED m awk: an awk that prints ok, then exits 2, fails a clean program, naming the evidence check
  make test-memory exited 0
  make test-memory's lines differ:
    wanted: test-memory: FAIL build/check-memory-gate/after.sps (exit 0, but the evidence check (awk) exited 2)
    wanted: test-memory: ran 1, passed 0, failed 1, hung 0
    got:    test-memory: pass build/check-memory-gate/after.sps
```
(1 more such lines cut.)

### MN1. a callable's parameters not read

**Guards:** every type of a callable is held to the allowlist, and scheme-object is a crossing as its parameter.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                   (else
-                   (let ((crossings (signature-crossings (caddr parts) (cadddr parts) ftypes #t)))
+                   (let ((crossings (signature-crossings '() (cadddr parts) ftypes #t)))
                      (if (eq? crossings 'unreadable)
```

**Result:** killed, exit 2:

```
FAIL crossing-object: scheme-object, never allowed: a procedure's parameter and result, a callable's result and parameter, and a parameter under each kind of mark
  expected: (returned ((("fixture_object" () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-procedure (scheme-object)) (on-object () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-callable (scheme-object))  [cut: 1106 more characters]
  actual:   (returned ((("fixture_object" () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-procedure (scheme-object)) (on-object () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-callable (scheme-object))  [cut: 995 more characters]
FAIL types-unreadable: types the reader cannot read: a string, a list that is no (* name), a callable's result, a wrapper use's parameter list that is a variable, improper, or missing; and types on no allowlist: a name that is no Chez type, [cut: 103 more characters]
  expected: (returned (() ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (uptr \"u8*\") int)") (types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(fo [cut: 1541 more characters]
  actual:   (returned (((on-unknown () "tests/fixtures/conventions/types-unreadable/curl/t.sls" foreign-callable ())) ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (uptr \"u [cut: 1563 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN2. a foreign procedure's result not read

**Guards:** a procedure's result is held to the allowlist, and scheme-object is a crossing as its result.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                 (else
-                 (let ((crossings (signature-crossings (caddr parts) (cadddr parts) ftypes #f)))
+                 (let ((crossings (signature-crossings (caddr parts) 'void ftypes #f)))
                    (if (eq? crossings 'unreadable)
```

**Result:** killed, exit 2:

```
FAIL crossing-object: scheme-object, never allowed: a procedure's parameter and result, a callable's result and parameter, and a parameter under each kind of mark
  expected: (returned ((("fixture_object" () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-procedure (scheme-object)) (on-object () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-callable (scheme-object))  [cut: 1106 more characters]
  actual:   (returned ((("fixture_object" () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-procedure (scheme-object)) (on-object () "tests/fixtures/conventions/crossing-object/curl/o.sls" foreign-callable (scheme-object))  [cut: 981 more characters]
FAIL types-unreadable: types the reader cannot read: a string, a list that is no (* name), a callable's result, a wrapper use's parameter list that is a variable, improper, or missing; and types on no allowlist: a name that is no Chez type, [cut: 103 more characters]
  expected: (returned (() ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (uptr \"u8*\") int)") (types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(fo [cut: 1541 more characters]
  actual:   (returned ((("fixture_result" () "tests/fixtures/conventions/types-unreadable/curl/t.sls" foreign-procedure ())) ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (u [cut: 1507 more characters]
FAIL types-layouts: (* NAME) and (& NAME), read when NAME is an ftype the tree's (curl private layouts) defines, as parameters, a result and a callable's; an ftype defined elsewhere, a variable of layouts, and none, unreadable
  expected: (returned ((("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) ("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) (on-pointed () "tests/ [cut: 486 more characters]
  actual:   (returned ((("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) ("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) (on-pointed () "tests/ [cut: 443 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN3. a known wrapper use's result not read

**Guards:** a wrapper use's result is held to the allowlist.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                (not (exists (lambda (s) (memq s bound)) (symbols-in written))))
-          (signature-crossings types (use-result form result) ftypes #f)
+          (signature-crossings types 'void ftypes #f)
           'unreadable)))
```

**Result:** killed, exit 2:

```
FAIL crossing-wrapper: crossings through known wrappers: a use's parameter list, a template's own, and a use's result; a use's u8* result hands C none, and its scheme-object result is never allowed
  expected: (returned ((("memcpy" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required (u8*)) ("fixture_result" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required ()) ("fixture_bytes" () "tests/fi [cut: 494 more characters]
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required (u8*)) ("fixture_result" () "tests/fixtures/conventions/crossing-wrapper/curl/w.sls" bind-required ()) ("fixture_bytes" () "tests/fi [cut: 368 more characters]
FAIL types-unreadable: types the reader cannot read: a string, a list that is no (* name), a callable's result, a wrapper use's parameter list that is a variable, improper, or missing; and types on no allowlist: a name that is no Chez type, [cut: 103 more characters]
  expected: (returned (() ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (uptr \"u8*\") int)") (types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(fo [cut: 1541 more characters]
  actual:   (returned ((("fixture_result" () "tests/fixtures/conventions/types-unreadable/curl/t.sls" bind-required ())) ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (uptr  [cut: 1487 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN4. result-reading's last branch read as a type: a result that holds a pattern variable, and is not one, read anyway

**Guards:** a known wrapper's result must be readable at its definition.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
              (and index (list 'at index))))
-          (else #f)))
+          (else (list 'type 'void))))
 
```

**Result:** killed, exit 2:

```
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal, parameters mixed, literal but no types,  [cut: 51 more characters]
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [cut: 2508 more characters]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [cut: 2325 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN4b. the unplaced-result check dropped: a wrapper with no result reading read anyway

**Guards:** a known wrapper's result must be readable at its definition.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                             (cond ((not reading) (list 'unreadable unplaced-parameters fp))
-                                  ((not result) (list 'unreadable unplaced-result fp))
+                                  (#f (list 'unreadable unplaced-result fp))
                                   (else (list 'ok fp index (car parts) reading result)))))))))))))))
```

**Result:** killed, exit 2:

```
FAIL wrapper-unreadable: known wrappers the reader cannot read: syntax-case, two clauses, no binding, two, a nested entry, an ellipsis first, a string entry, a short form, an entry that is a literal, parameters mixed, literal but no types,  [cut: 51 more characters]
  expected: (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [cut: 2508 more characters]
  actual:   (returned (() ((wrapper-unreadable "tests/fixtures/conventions/wrapper-unreadable/curl/w.sls" w-syntax-case "it is not (syntax-rules (literal ...) (pattern template)), with one clause") (entry-not-string "tests/fixtures/conventi [cut: 2143 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN5. void accepted as a parameter

**Guards:** void is a result type alone.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
     (cond ((memq type immediate-types) 'value)
-          ((and result? (eq? type 'void)) 'value)
+          ((eq? type 'void) 'value)
           ((memq type bytevector-types) 'bytevector)
```

**Result:** killed, exit 2:

```
FAIL types-unreadable: types the reader cannot read: a string, a list that is no (* name), a callable's result, a wrapper use's parameter list that is a variable, improper, or missing; and types on no allowlist: a name that is no Chez type, [cut: 103 more characters]
  expected: (returned (() ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (uptr \"u8*\") int)") (types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(fo [cut: 1541 more characters]
  actual:   (returned ((("fixture_wide" () "tests/fixtures/conventions/types-unreadable/curl/t.sls" foreign-procedure ())) ((types-unreadable "tests/fixtures/conventions/types-unreadable/curl/t.sls" "(foreign-procedure \"fixture_wide\" (upt [cut: 1512 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN6. a mark clears every kind of crossing

**Guards:** each mark clears its own kind alone.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
     (let ((mark (row-mark row)))
-      (and mark (eq? (car mark) kind))))
+      (and mark #t)))
 
```

**Result:** killed, exit 2:

```
FAIL string-marked: a row marked string-not-kept clears its strings, direct, wrapped and a callable's result; a mark that quotes nothing clears none, and each mark clears its own kind alone
  expected: (returned ((("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" foreign-procedure (string)) ("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" bind-required (strin [cut: 751 more characters]
  actual:   (returned ((("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" foreign-procedure (string)) ("fixture_string_not_kept" () "tests/fixtures/conventions/string-marked/curl/m.sls" bind-required (strin [cut: 537 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN7. pattern variables not tracked

**Guards:** a pattern variable spelt as a type is unreadable.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
              (let ((outer bound))
-               (set! bound (append (macro-variables form) bound))
+               (set! bound bound)
                (walk-elements form 0 #f)
```

**Result:** killed, exit 2:

```
FAIL types-pattern-variable: pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, syntax-case through a wrapper's use, with-syntax, identifier-syntax, a callable's result, and a convention; a  [cut: 48 more characters]
  expected: (returned ((("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ())) ((types-unreadable "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" "(foreign-pr [cut: 760 more characters]
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ()) ("memcpy" () "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" bind-required ()) ("memcpy" () "tests/fixt [cut: 590 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN8. pattern variables not checked in a known wrapper's use

**Guards:** a wrapper use's types that are pattern variables are unreadable.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
       (if (and (list? types)
-               (not (exists (lambda (s) (memq s bound)) (symbols-in written))))
+               #t)
           (signature-crossings types (use-result form result) ftypes #f)
```

**Result:** killed, exit 2:

```
FAIL types-pattern-variable: pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, syntax-case through a wrapper's use, with-syntax, identifier-syntax, a callable's result, and a convention; a  [cut: 48 more characters]
  expected: (returned ((("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ())) ((types-unreadable "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" "(foreign-pr [cut: 760 more characters]
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" bind-required ()) ("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ()))  [cut: 704 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN9. with-syntax not tracked

**Guards:** with-syntax binds pattern variables.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
   ;; The forms whose clauses bind pattern variables in their templates.
-  (define macro-forms '(syntax-rules syntax-case with-syntax identifier-syntax))
+  (define macro-forms '(syntax-rules syntax-case identifier-syntax))
 
```

**Result:** killed, exit 2:

```
FAIL types-pattern-variable: pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, syntax-case through a wrapper's use, with-syntax, identifier-syntax, a callable's result, and a convention; a  [cut: 48 more characters]
  expected: (returned ((("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ())) ((types-unreadable "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" "(foreign-pr [cut: 760 more characters]
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ()) ("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ( [cut: 720 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN10. identifier-syntax not tracked

**Guards:** identifier-syntax's set! clause binds a pattern variable.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
   ;; The forms whose clauses bind pattern variables in their templates.
-  (define macro-forms '(syntax-rules syntax-case with-syntax identifier-syntax))
+  (define macro-forms '(syntax-rules syntax-case with-syntax))
 
```

**Result:** killed, exit 2:

```
FAIL types-pattern-variable: pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, syntax-case through a wrapper's use, with-syntax, identifier-syntax, a callable's result, and a convention; a  [cut: 48 more characters]
  expected: (returned ((("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ())) ((types-unreadable "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" "(foreign-pr [cut: 760 more characters]
  actual:   (returned ((("memcpy" () "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ()) ("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ( [cut: 732 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN11. a direct binding's conventions not checked for pattern variables

**Guards:** a convention that is a pattern variable fails.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                  (violation! 'entry-not-string path (abbreviated form)))
-                ((from-pattern? (car parts))
-                 (violation! 'conventions-from-pattern path (abbreviated form)))
                 ((from-pattern? (cddr parts))
```

**Result:** killed, exit 2:

```
FAIL types-pattern-variable: pattern variables spelt as types or a convention, in macros that are no known wrapper: syntax-rules, syntax-case through a wrapper's use, with-syntax, identifier-syntax, a callable's result, and a convention; a  [cut: 48 more characters]
  expected: (returned ((("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ())) ((types-unreadable "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" "(foreign-pr [cut: 760 more characters]
  actual:   (returned ((("curl_easy_perform" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p.sls" foreign-procedure ()) ("curl_multi_poll" (__collect_safe) "tests/fixtures/conventions/types-pattern-variable/curl/p [cut: 723 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN12. any definition in layouts admitted as an ftype

**Guards:** only a (define-ftype NAME TYPE) defines an ftype.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
                                              (= (length form) 3)
-                                             (eq? (car form) 'define-ftype)
+                                             (memq (car form) '(define define-ftype))
                                              (symbol? (cadr form))))
```

**Result:** killed, exit 2:

```
FAIL types-layouts: (* NAME) and (& NAME), read when NAME is an ftype the tree's (curl private layouts) defines, as parameters, a result and a callable's; an ftype defined elsewhere, a variable of layouts, and none, unreadable
  expected: (returned ((("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) ("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) (on-pointed () "tests/ [cut: 486 more characters]
  actual:   (returned ((("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) ("fixture_layout" () "tests/fixtures/conventions/types-layouts/curl/u.sls" foreign-procedure ()) (on-pointed () "tests/ [cut: 446 more characters]
test: FAIL tests/test-collect-safe.sps (exit 1)
```

### MN13. curl_easy_header's string-not-kept mark dropped from the table

**Guards:** the live scan of src/ holds each string crossing to its mark.

**Mutation:** In `tests/foreign-conventions.sls`:

```diff
           (list "curl_easy_init" '() cannot-block)
-          (list "curl_easy_header" '() cannot-block (list 'string-not-kept name-not-kept))
+          (list "curl_easy_header" '() cannot-block)
           (list "curl_easy_cleanup" '() cleanup-open)
```

**Result:** killed, exit 2:

```
FAIL src/ holds to the table: no violation
  expected: ()
  actual:   ((string-crossing "curl_easy_header" (string) "src/curl/private/native.sls"))
FAIL the table marks exactly curl_easy_option_by_name and curl_easy_header, each string-not-kept, citing what their callees keep
  expected: (("curl_easy_option_by_name" (string-not-kept ".plans/decisions/0013-collect-safe-blocking-calls.md: `curl_easy_option_by_name` and `curl_easy_header` read their name argument during the call, and keep no pointer to it.")) ("cur [cut: 209 more characters]
  actual:   (("curl_easy_option_by_name" (string-not-kept ".plans/decisions/0013-collect-safe-blocking-calls.md: `curl_easy_option_by_name` and `curl_easy_header` read their name argument during the call, and keep no pointer to it.")))
test: FAIL tests/test-collect-safe.sps (exit 1)
```

## Third review fixes: CI

Evidence for the fixes to two findings of the third review of M0 slice 5's CI part ([harness
plan](2026-10-04-harness-plan.md) §4; [ADR-0003](decisions/0003-libcurl-floor-7-85.md),
[ADR-0016](decisions/0016-floors-have-one-source.md)).

**Finding 1, a workflow could redefine a floor.** `check-floors` looked only for the floors' version text,
so a job- or step-level `env: CURL_FLOOR_VERSION: "8.1.3"`, or a matrix value, passed, and the floor lane
then built, and checked against, a libcurl that was not the floor. The class is closed by stating no floor in
CI at all:

- `scripts/ci/floor.sh NAME`, new: prints the `chez`, `libcurl` or `node` floor from `packaging/floors.sexp`
  at the repository root (two directories above the script), and fails closed unless that file is one list of
  `(key "version")` entries holding exactly one entry for NAME with a well-formed version. It reads no
  argument but the name and no environment variable;
- `scripts/ci/build-chez.sh PREFIX [--nothreads]` and `scripts/ci/build-curl.sh PREFIX
  [EXTRA-CONFIGURE-FLAGS...]` take no version: each calls `floor.sh`. Their pinned sha256 tables stay, and a
  floor with no pinned sum still fails. `scripts/ci/expect-missing-api.sh` reads the version it requires from
  `floor.sh`, not from `CURL_FLOOR_VERSION`;
- `.github/workflows/ci.yml`: the top-level `env` block with `CHEZ_VERSION` and `CURL_FLOOR_VERSION` is gone;
  every cache key that held a version hashes `packaging/floors.sexp` and the build script instead; no step
  passes a version; the floor lane's check that `make build` loaded the floor gets it from `floor.sh`;
- `tests/floors.sls`, and the comments of `tests/check-floors.sps`: the rule for the workflow directory is now that no line of
  any file there contains either floor's version text or names the keys `CHEZ_VERSION` or
  `CURL_FLOOR_VERSION`. The rule that `ci.yml` holds two env lines exactly once is gone. A missing or empty
  directory, a directory with no `ci.yml`, and a file or directory that cannot be read still fail. The export
  `env-workflow` is now `ci-workflow`, and `workflows-problems` takes the floors file's path first, for its
  messages;
- `tests/test-check-floors.sps`, and the fixtures under `tests/fixtures/floors/`: rows for the new rule, and
  a layer of rows that run the real `scripts/ci/*.sh` in a fresh tree with a floors file of the row's own.

**Finding 2, the pin check missed other spellings.** `check-action-pins.sh` gathered only lines that start
`uses:` or `- uses:`, so `- {uses: actions/checkout@v4, ...}`, `- "uses": ...` and `- uses : ...` passed.
It now gathers every non-comment line that holds a `uses` key in any spelling (bare or quoted, white space
before the colon, after white space, a brace, a bracket or a comma) and requires each to be exactly
`uses: OWNER/REPO[/path]@<40 hex digits> # vTAG`, after any indent and an optional `- `. A flow mapping, a
quoted key, a quoted value, a space before the colon and a value on the next line fail whether or not the
commit is pinned. Its rows are in `tests/test-check-floors.sps` too, run on workflow directories the suite
writes.

A driver in the session scratchpad ran every mutation, as the earlier parts' did. It froze a snapshot of the
tree, without `build/`, and gave each mutation a fresh copy. It applied each by exact-text replacement,
aborting unless the target occurred exactly once (or the named occurrence), and refused a mutation whose diff
was empty. It touched the copy's `manifest.scm` and ran container commands through the copy's own
`scripts/guix-env`, so the container saw only that copy; the pin check and actionlint ran in the copy on the
host. A mutation counts as killed only when the command exits non-zero and every expected line appears whole
in its output: the case's `FAIL <test name>` lines and `test: FAIL tests/test-check-floors.sps (exit 1)`,
or the `check-floors:` or `check-action-pins:` lines. Nothing built Chez or curl: where a build script
reached its download, a curl that only names its URL stood in.

**Result** quotes at most 12 output lines per run: the first line each expectation matches (a `FAIL` with its
expected and actual lines), then other `FAIL` lines with theirs, then `check-`, `test: FAIL`, `make test
exit` and exit lines in output order. It says how many wanted lines were cut. A diff keeps one line of
context, and `...` sets its hunks apart. A diff line longer than 200 characters, and an output line longer
than 240, is cut, and says how much was cut. `<fixci2>` is `scratchpad/slice5/fixci2`, `<run>` a mutation's
copy and `<base>` the tree as it was before this fix.

Cases are named `FW` (the real workflow directory under `make test`'s `check-floors`), `PN` (the pin check on
the real workflow), `KY` and `VT` (the rules in `(floors)`), `FS` (`floor.sh`), `BS` (the build scripts), `EM`
(`expect-missing-api.sh`) and `PC` (the rules inside `check-action-pins.sh`).

### Red runs

**R1, finding 1 on the check as it was.** In a copy of the tree as it was, one job's env gets
`CURL_FLOOR_VERSION: "8.1.3"`, and then, in another copy, one job gets a matrix value `curl: ["8.1.3"]`. Both
are valid workflows (actionlint exits 0 on the second; the first is FW1's, below), and `make check-floors`
passes both:

```
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
make check-floors exit 0
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
make check-floors exit 0
actionlint exit 0
```

**R2, finding 2 on the check as it was.** Three one-file directories, each with one canonical pinned step and
one more: `- {uses: actions/checkout@v4, with: {submodules: true}}`, `- "uses": actions/checkout@v4` and
`- uses : actions/checkout@v4`. The old script, then the new one:

```
== flow (old script)
check-action-pins: all 1 uses: lines under flow name a full commit SHA, with its tag in a comment
exit 0
== quoted (old script)
check-action-pins: all 1 uses: lines under quoted name a full commit SHA, with its tag in a comment
exit 0
== spaced (old script)
check-action-pins: all 1 uses: lines under spaced name a full commit SHA, with its tag in a comment
exit 0
```

```
== flow (new script)
check-action-pins: flow/ci.yml:5:      - {uses: actions/checkout@v4, with: {submodules: true}}
check-action-pins: 1 of 2 lines with a uses key are not "uses: OWNER/REPO@<40 hex digits> # vTAG", after an optional "- "
exit 1
== quoted (new script)
check-action-pins: quoted/ci.yml:5:      - "uses": actions/checkout@v4
check-action-pins: 1 of 2 lines with a uses key are not "uses: OWNER/REPO@<40 hex digits> # vTAG", after an optional "- "
exit 1
== spaced (new script)
check-action-pins: spaced/ci.yml:5:      - uses : actions/checkout@v4
check-action-pins: 1 of 2 lines with a uses key are not "uses: OWNER/REPO@<40 hex digits> # vTAG", after an optional "- "
exit 1
```

**R3, the floors suite before the code.** The new and changed rows of `tests/test-check-floors.sps` and the
fixtures were written first, and the suite was run directly against the unchanged `(floors)`,
`tests/check-floors.sps`, `ci.yml` and `scripts/ci/` (no `floor.sh`). 171 tests failed and 137 passed. The
rows that fail only because the old code wants the env lines are most of them; the rows for the new rules
are the 48 `scripts:` and 26 `pins:` rows, the 21 `workflow:` rows and the fixtures, and three of them:

```
FAIL workflow: a job's env redefining the libcurl floor, to another version
  expected: (returned ("W/ci.yml: line 8 names CURL_FLOOR_VERSION, which no workflow line may name: the build scripts read the floors from f.sexp"))
  actual:   (returned ("W/ci.yml: the line \"  CHEZ_VERSION: \\\"10.9.1\\\"\" appears 0 times, but must appear once" "W/ci.yml: the line \"  CURL_FLOOR_VERSION: \\\"8.1.2\\\"\" appears 0 times, but must appear once"))
FAIL scripts: floor.sh: the libcurl floor
  expected: (returned (0 "8.1.2\n" ""))
  actual:   (returned (127 "" "sh: /tmp/curl-testing.ik4Q07/scripts/ci/floor.sh: No such file or directory\n"))
FAIL pins: a double-quoted key
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 uses: lines under /tmp/curl-testing.YYugnT name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.YYugnT/ci.yml:5:      - \"uses\": a [cut: 151 more characters]
# of expected passes      137
# of unexpected failures  171
suite-exit-status: exit 1 (pass 137, fail 171, xpass 0): a suite needs a pass, and no fail or xpass
```

R3 fails the pin rows on the old script's message as well as on its behaviour; the behaviour is shown by R2,
and by PC1 and PN1 to PN3 below.

### The build scripts, run as far as the floor

`build-chez.sh` and `build-curl.sh` run in a scratch copy of the tree, through its `scripts/guix-env`, with a
curl that only names its URL first on `PATH`: nothing is downloaded and nothing is built. With the checked-in
floors file they read 10.4.0 and 7.85.0 from it. A libcurl floor written `7.85`, a Chez floor written twice
and a missing libcurl entry each stop the script before its download. A floor with no pinned sum stops it,
and the old keys set to the pinned versions do not help. The old calls, a version first, are refused:

```
=== the checked-in floors file
((chez "10.4.0")
 (libcurl "7.85.0")
 (node "20"))
--- sh scripts/ci/build-chez.sh /opt/chez
fake curl asked for: https://github.com/cisco/ChezScheme/releases/download/v10.4.0/csv10.4.0.tar.gz
exit 7
--- sh scripts/ci/build-curl.sh /opt/curl --disable-headers-api
fake curl asked for: https://curl.se/download/curl-7.85.0.tar.xz
exit 7
```

```
=== libcurl written 7.85, not three numbers
--- sh scripts/ci/build-curl.sh /opt/curl
floor.sh: packaging/floors.sexp: the libcurl version "7.85" is not three dot-separated naturals, major.minor.patch
build-curl.sh: no libcurl floor to build
exit 1
=== chez written twice
--- sh scripts/ci/build-chez.sh /opt/chez
floor.sh: packaging/floors.sexp: it holds more than one chez entry
build-chez.sh: no Chez floor to build
exit 1
=== no libcurl entry
--- sh scripts/ci/build-curl.sh /opt/curl
floor.sh: packaging/floors.sexp: it holds no libcurl entry
build-curl.sh: no libcurl floor to build
exit 1
```

```
=== a floor with no pinned sum, with the old env keys set to the pinned versions
--- sh scripts/ci/build-chez.sh /opt/chez
build-chez.sh: no sha256 is pinned for Chez 9.9.9: fetch its release tarball, check it, and add the sum to tarball_sha256 in this script
exit 1
--- sh scripts/ci/build-curl.sh /opt/curl
build-curl.sh: no sha256 is pinned for curl 9.9.9: fetch its release tarball, check it, and add the sum to tarball_sha256 in this script
exit 1
```

```
=== the old calls, a version first
--- sh scripts/ci/build-chez.sh 10.4.0 /opt/chez
usage: build-chez.sh PREFIX [--nothreads]
exit 2
--- sh scripts/ci/build-curl.sh 7.85.0 /opt/curl
build-curl.sh: PREFIX must be an absolute path, not '7.85.0'
exit 2
```

### Baseline

Everything written, on a copy of the final snapshot. `make test` exited 0, `check-floors` naming the files it read:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
test: ran 14, passed 14, failed 0, hung 0
make test exit 0
check-test-fails exit 0
check-help exit 0
```

### Mutations

31 mutations ran, and all 31 were killed, each with every expected line present. `test-check-floors` was the only suite to fail, under every mutation of a script or of `(floors)`. The pin check on the real workflow (PN) was the command under PN1 to PN4, and `make test` stopped at `check-floors`, before any suite, under FW1 to FW3 and FW5.

### FW1. a job-level env redefines the libcurl floor, to another version

**Guards:** no workflow line names the key CURL_FLOOR_VERSION, whatever version it gives.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
       CURL_EXTRA_FLAGS: ""
+      CURL_FLOOR_VERSION: "8.1.3"
     steps:
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: .github/workflows/ci.yml: line 147 names CURL_FLOOR_VERSION, which no workflow line may name: the build scripts read the floors from packaging/floors.sexp
check-floors: FAILED (problems: 1)
make test exit 2
```

actionlint on the mutated workflow: `actionlint exit 0`, so it is a valid workflow, and only check-floors refuses it.

### FW2. a CHEZ_VERSION key in a second workflow file

**Guards:** no line of any workflow file names the key CHEZ_VERSION.

**Mutation:** In `.github/workflows/release.yml`:

```diff
+name: Release
+on:
+  push:
+    tags: ["v*"]
+env:
+  CHEZ_VERSION: "9.5.8"
+jobs:
+  release:
+    runs-on: ubuntu-24.04
+    steps:
+      - run: make build
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: .github/workflows/release.yml: line 6 names CHEZ_VERSION, which no workflow line may name: the build scripts read the floors from packaging/floors.sexp
check-floors: FAILED (problems: 1)
make test exit 2
```

### FW3. a floor literal in a second workflow file

**Guards:** no line of any workflow file contains a floor's version text.

**Mutation:** In `.github/workflows/release.yml`:

```diff
+name: Release
+on:
+  push:
+    tags: ["v*"]
+jobs:
+  release:
+    runs-on: ubuntu-24.04
+    steps:
+      - run: scripts/ci/build-curl.sh 7.85.0 /opt/curl
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: .github/workflows/release.yml: line 9 contains the libcurl floor 7.85.0, which no workflow line may write: the build scripts read it from packaging/floors.sexp
check-floors: FAILED (problems: 1)
make test exit 2
```

### FW4. floor.sh made to print a fixed version, 10.4.0, whatever floor it is asked for

**Guards:** floor.sh prints the floor the file holds for the name asked.

**Mutation:** In `scripts/ci/floor.sh`:

```diff
 fi
-printf '%s\n' "$version"
+printf '%s\n' "10.4.0"
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
FAIL scripts: floor.sh: the Chez floor
  expected: (returned (0 "10.9.1\n" ""))
  actual:   (returned (0 "10.4.0\n" ""))
FAIL scripts: floor.sh: the libcurl floor
  expected: (returned (0 "8.1.2\n" ""))
  actual:   (returned (0 "10.4.0\n" ""))
FAIL scripts: floor.sh: the Node floor
  expected: (returned (0 "22.3\n" ""))
  actual:   (returned (0 "10.4.0\n" ""))
FAIL scripts: expect-missing-api.sh: the version it requires is the libcurl floor of the file
  expected: (returned (0 "chez-curl: libcurl refused\n(reason . missing-api)\n  path:       /lib/libcurl.so.4\n  source:     override\n  detail:     curl_easy_header\n  version:    8.1.2\n  TLS:        fake\nexpect-missing-api: make build e [cut: 92 more characters]
  actual:   (returned (1 "chez-curl: libcurl refused\n(reason . missing-api)\n  path:       /lib/libcurl.so.4\n  source:     override\n  detail:     curl_easy_header\n  version:    8.1.2\n  TLS:        fake\n--- /tmp/expect-missing-api.S7NH [cut: 486 more characters]
```
(41 more such lines cut.)

### FW5. the floor lane's check names the libcurl floor as a literal, not from floor.sh

**Guards:** no workflow line contains the floor; the lane gets it from floor.sh.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
           set -o pipefail
-          floor=$(scripts/ci/floor.sh libcurl)
+          floor=7.85.0
           make build | tee "$RUNNER_TEMP/build.log"
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: .github/workflows/ci.yml: line 226 contains the libcurl floor 7.85.0, which no workflow line may write: the build scripts read it from packaging/floors.sexp
check-floors: FAILED (problems: 1)
make test exit 2
```

### PN1. a checkout step as a flow mapping, its commit and tag in place

**Guards:** every line with a uses key is the canonical form, a flow mapping too.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
     steps:
-      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
-        with:
-          submodules: recursive
+      - {uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1, with: {submodules: recursive}} # v7.0.1
```

**Command:** `scripts/ci/check-action-pins.sh .github/workflows` on the host, then the same script as it was (`<base>`) on the same directory; actionlint on `.github/workflows/ci.yml`, on the host.

**Result:** killed, check-action-pins exit 1:

```
check-action-pins: .github/workflows/ci.yml:81:      - {uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1, with: {submodules: recursive}} # v7.0.1
check-action-pins: 1 of 19 lines with a uses key are not "uses: OWNER/REPO@<40 hex digits> # vTAG", after an optional "- "
check-action-pins exit 1
check-action-pins: all 18 uses: lines under .github/workflows name a full commit SHA, with its tag in a comment
old check-action-pins exit 0
```

actionlint on the mutated workflow: `actionlint exit 0`, so it is a valid workflow, and only the pin check refuses it.

### PN2. a checkout step with a double-quoted key, its commit and tag in place

**Guards:** every line with a uses key is the canonical form, a quoted key too.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
     steps:
-      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
+      - "uses": actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
         with:
```

**Command:** `scripts/ci/check-action-pins.sh .github/workflows` on the host, then the same script as it was (`<base>`) on the same directory; actionlint on `.github/workflows/ci.yml`, on the host.

**Result:** killed, check-action-pins exit 1:

```
check-action-pins: .github/workflows/ci.yml:81:      - "uses": actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
check-action-pins: 1 of 19 lines with a uses key are not "uses: OWNER/REPO@<40 hex digits> # vTAG", after an optional "- "
check-action-pins exit 1
check-action-pins: all 18 uses: lines under .github/workflows name a full commit SHA, with its tag in a comment
old check-action-pins exit 0
```

actionlint on the mutated workflow: `actionlint exit 0`, so it is a valid workflow, and only the pin check refuses it.

### PN3. a checkout step with a space before the colon, its commit and tag in place

**Guards:** every line with a uses key is the canonical form, a spaced key too.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
     steps:
-      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
+      - uses : actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
         with:
```

**Command:** `scripts/ci/check-action-pins.sh .github/workflows` on the host, then the same script as it was (`<base>`) on the same directory; actionlint on `.github/workflows/ci.yml`, on the host.

**Result:** killed, check-action-pins exit 1:

```
check-action-pins: .github/workflows/ci.yml:81:      - uses : actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
check-action-pins: 1 of 19 lines with a uses key are not "uses: OWNER/REPO@<40 hex digits> # vTAG", after an optional "- "
check-action-pins exit 1
check-action-pins: all 18 uses: lines under .github/workflows name a full commit SHA, with its tag in a comment
old check-action-pins exit 0
```

actionlint on the mutated workflow: `actionlint exit 0`, so it is a valid workflow, and only the pin check refuses it.

### PN4. a checkout step back on its tag, @v7

**Guards:** every action is pinned to a full commit.

**Mutation:** In `.github/workflows/ci.yml`:

```diff
     steps:
-      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
+      - uses: actions/checkout@v7
         with:
```

**Command:** `scripts/ci/check-action-pins.sh .github/workflows`, on the host.

**Result:** killed, check-action-pins exit 1:

```
check-action-pins: .github/workflows/ci.yml:81:      - uses: actions/checkout@v7
check-action-pins: 1 of 19 lines with a uses key are not "uses: OWNER/REPO@<40 hex digits> # vTAG", after an optional "- "
check-action-pins exit 1
```

### KY1. check-floors: no key is refused (the key list emptied)

**Guards:** a line that names CHEZ_VERSION or CURL_FLOOR_VERSION fails.

**Mutation:** In `tests/floors.sls`:

```diff
   ;; held the floors in before the build scripts read them from the file.
-  (define workflow-keys '("CHEZ_VERSION" "CURL_FLOOR_VERSION"))
+  (define workflow-keys '())
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
FAIL workflow: a job's env redefining the libcurl floor, to another version
  expected: (returned ("W/ci.yml: line 8 names CURL_FLOOR_VERSION, which no workflow line may name: the build scripts read the floors from f.sexp"))
  actual:   (returned ())
FAIL workflow: a job's env redefining the Chez floor, to another version
  expected: (returned ("W/ci.yml: line 8 names CHEZ_VERSION, which no workflow line may name: the build scripts read the floors from f.sexp"))
  actual:   (returned ())
FAIL workflow-key: a job's env in ci.yml redefines the libcurl floor, to a version that is not the floor
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-key/workflows/ci.yml: line 9 names CURL_FLOOR_VERSION, which no workflow line may name: the build scripts read the floors from tests/fixtures/floors/workflow-key/floors.sexp\nc [cut: 37 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflow-key/README.org and tests/fixtures/floors/workflow-key/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflow-key/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\ [cut: 6 more characters]
FAIL workflows-second-key: a second workflow beside ci.yml has an env naming the Chez key
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-second-key/workflows/release.yml: line 7 names CHEZ_VERSION, which no workflow line may name: the build scripts read the floors from tests/fixtures/floors/workflows-second-key [cut: 52 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-second-key/README.org and tests/fixtures/floors/workflows-second-key/workflows (ci.yml, release.yml) hold the floors in tests/fixtures/floors/workflows-second-key/floors.sexp (ch [cut: 43 more characters]
```
(47 more such lines cut.)

### KY2. check-floors: the libcurl key is not refused

**Guards:** each key is refused on its own.

**Mutation:** In `tests/floors.sls`:

```diff
   ;; held the floors in before the build scripts read them from the file.
-  (define workflow-keys '("CHEZ_VERSION" "CURL_FLOOR_VERSION"))
+  (define workflow-keys '("CHEZ_VERSION"))
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflow: a job's env redefining the libcurl floor, to another version
  expected: (returned ("W/ci.yml: line 8 names CURL_FLOOR_VERSION, which no workflow line may name: the build scripts read the floors from f.sexp"))
  actual:   (returned ())
FAIL workflow: a job's env redefining a floor, to the floor itself: the floor's text and the key
  expected: (returned ("W/ci.yml: line 8 contains the libcurl floor 8.1.2, which no workflow line may write: the build scripts read it from f.sexp" "W/ci.yml: line 8 names CURL_FLOOR_VERSION, which no workflow line may name: the build scrip [cut: 33 more characters]
  actual:   (returned ("W/ci.yml: line 8 contains the libcurl floor 8.1.2, which no workflow line may write: the build scripts read it from f.sexp"))
FAIL workflow-key: a job's env in ci.yml redefines the libcurl floor, to a version that is not the floor
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-key/workflows/ci.yml: line 9 names CURL_FLOOR_VERSION, which no workflow line may name: the build scripts read the floors from tests/fixtures/floors/workflow-key/floors.sexp\nc [cut: 37 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflow-key/README.org and tests/fixtures/floors/workflow-key/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflow-key/floors.sexp (chez 10.9.1, libcurl 8.1.2, node 22.3)\ [cut: 6 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```
(20 more such lines cut.)

### VT1. check-floors: no floor's version text is refused

**Guards:** a line that contains a floor's version fails.

**Mutation:** In `tests/floors.sls`:

```diff
                   (map (lambda (floor)
-                         (if (contains? (car rest) (cadr floor))
+                         (if #f
                              (list (string-append
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL workflow: the Chez floor in a run step
  expected: (returned ("W/ci.yml: line 12 contains the Chez floor 10.9.1, which no workflow line may write: the build scripts read it from f.sexp"))
  actual:   (returned ())
FAIL workflow-literal: ci.yml passes the libcurl floor to a build script
  expected: (1 "" "check-floors: tests/fixtures/floors/workflow-literal/workflows/ci.yml: line 10 contains the libcurl floor 8.1.2, which no workflow line may write: the build scripts read it from tests/fixtures/floors/workflow-literal/floo [cut: 47 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflow-literal/README.org and tests/fixtures/floors/workflow-literal/workflows (ci.yml) hold the floors in tests/fixtures/floors/workflow-literal/floors.sexp (chez 10.9.1, libcurl 8.1.2, [cut: 18 more characters]
FAIL workflows-second-literal: a second workflow beside ci.yml writes the Chez floor in a step
  expected: (1 "" "check-floors: tests/fixtures/floors/workflows-second-literal/workflows/release.yml: line 11 contains the Chez floor 10.9.1, which no workflow line may write: the build scripts read it from tests/fixtures/floors/workflows- [cut: 66 more characters]
  actual:   (0 "check-floors: tests/fixtures/floors/workflows-second-literal/README.org and tests/fixtures/floors/workflows-second-literal/workflows (ci.yml, release.yml) hold the floors in tests/fixtures/floors/workflows-second-literal/flo [cut: 55 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```
(68 more such lines cut.)

### FS1. floor.sh: ; comments not dropped

**Guards:** an entry named in a comment is no entry.

**Mutation:** In `scripts/ci/floor.sh`:

```diff
 # space, so one entry is one piece of text wherever it was broken.
-text=$(sed 's/;.*$//' "$file") || fail "it cannot be read"
+text=$(cat "$file") || fail "it cannot be read"
 case $text in
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL scripts: floor.sh: a comment above, an entry's own line and after the datum holds an entry of the same name: it is no entry
  expected: (returned (0 "8.1.2\n" ""))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: it is not one list of (key \"version\") entries\n"))
FAIL scripts: build-curl.sh: the checked-in libcurl floor has a pinned sum: it reaches the download of its tarball
  expected: (returned (7 "" "https://curl.se/download/curl-7.85.0.tar.xz\n"))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: it is not one list of (key \"version\") entries\nbuild-curl.sh: no libcurl floor to build\n"))
FAIL scripts: build-chez.sh: the checked-in Chez floor has a pinned sum: it reaches the download of its tarball
  expected: (returned (7 "" "https://github.com/cisco/ChezScheme/releases/download/v10.4.0/csv10.4.0.tar.gz\n"))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: it is not one list of (key \"version\") entries\nbuild-chez.sh: no Chez floor to build\n"))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```
(5 more such lines cut.)

### FS2. floor.sh: a # outside a comment allowed

**Guards:** a datum comment or a block comment is refused, not misread.

**Mutation:** In `scripts/ci/floor.sh`:

```diff
 case $text in
-  *'#'*) fail "it holds a # outside a ; comment, which this script does not read" ;;
+  *'#'*) ;;
 esac
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL scripts: floor.sh: a datum comment, which the Scheme reader skips and this script does not read
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: it holds a # outside a ; comment, which this script does not read\n"))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: it is not one list of (key \"version\") entries\n"))
FAIL scripts: floor.sh: a block comment
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: it holds a # outside a ; comment, which this script does not read\n"))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: it is not one list of (key \"version\") entries\n"))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### FS3. floor.sh: the shape of the whole file not required

**Guards:** the file must be one list of (key "version") entries.

**Mutation:** In `scripts/ci/floor.sh`:

```diff
 # One list of entries, each a lower-case key and a string, and nothing else.
-if ! printf '%s\n' "$text" | grep -q -E '^ *\( *(\( *[a-z]+ +"[^"]*" *\) *)+\) *$'; then
+if false; then
   fail "it is not one list of (key \"version\") entries"
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL scripts: floor.sh: an empty file
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: it is not one list of (key \"version\") entries\n"))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: it holds no chez entry\n"))
FAIL scripts: floor.sh: a version that is a symbol, not a string
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: it is not one list of (key \"version\") entries\n"))
  actual:   (returned (0 "8.1.2\n" ""))
FAIL scripts: floor.sh: a second datum
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: it is not one list of (key \"version\") entries\n"))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: it holds more than one chez entry\n"))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```
(14 more such lines cut.)

### FS4. floor.sh: a name written twice takes the first

**Guards:** exactly one entry for the name.

**Mutation:** In `scripts/ci/floor.sh`:

```diff
 [ -n "$entries" ] || fail "it holds no $name entry"
-case $entries in
-  *'
-'*) fail "it holds more than one $name entry" ;;
-esac
+entries=$(printf '%s\n' "$entries" | head -n 1)
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL scripts: floor.sh: the key twice
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: it holds more than one chez entry\n"))
  actual:   (returned (0 "10.9.1\n" ""))
FAIL scripts: build-chez.sh: a Chez floor written twice fails closed, before any download
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: it holds more than one chez entry\nbuild-chez.sh: no Chez floor to build\n"))
  actual:   (returned (7 "" "https://github.com/cisco/ChezScheme/releases/download/v10.4.0/csv10.4.0.tar.gz\n"))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### FS5. floor.sh: the version's shape not required

**Guards:** a version must be dot-separated naturals, three for chez and libcurl.

**Mutation:** In `scripts/ci/floor.sh`:

```diff
 esac
-if ! printf '%s\n' "$version" | grep -q -E "$form"; then
+if false; then
   fail "the $name version \"$version\" is not $what"
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
FAIL scripts: floor.sh: the other floors are well-formed, and the one asked for is not
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: the libcurl version \"8.1\" is not three dot-separated naturals, major.minor.patch\n"))
  actual:   (returned (0 "8.1\n" ""))
FAIL scripts: floor.sh: a version with a leading zero
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: the libcurl version \"08.1.2\" is not three dot-separated naturals, major.minor.patch\n"))
  actual:   (returned (0 "08.1.2\n" ""))
FAIL scripts: floor.sh: a version with four numbers
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: the chez version \"10.9.1.1\" is not three dot-separated naturals, major.minor.patch\n"))
  actual:   (returned (0 "10.9.1.1\n" ""))
FAIL scripts: build-curl.sh: a malformed libcurl floor fails closed, before any download
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: the libcurl version \"7.85\" is not three dot-separated naturals, major.minor.patch\nbuild-curl.sh: no libcurl floor to build\n"))
  actual:   (returned (1 "" "build-curl.sh: no sha256 is pinned for curl 7.85: fetch its release tarball, check it, and add the sum to tarball_sha256 in this script\n"))
```
(14 more such lines cut.)

### FS6. floor.sh: a name with no entry not refused

**Guards:** an entry for the name must be there.

**Mutation:** In `scripts/ci/floor.sh`:

```diff
 entries=$(printf '%s\n' "$text" | grep -o -E "\\( *$name +\"[^\"]*\" *\\)" || true)
-[ -n "$entries" ] || fail "it holds no $name entry"
 case $entries in
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL scripts: floor.sh: the key is missing
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: it holds no libcurl entry\n"))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: the libcurl version \"\" is not three dot-separated naturals, major.minor.patch\n"))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### BS1. build-curl.sh: the version written into the script, not read

**Guards:** the libcurl version is the floor the file holds.

**Mutation:** In `scripts/ci/build-curl.sh`:

```diff
 here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
-version=$(sh "$here/floor.sh" libcurl) || {
+version=7.85.0; true || {
   echo "build-curl.sh: no libcurl floor to build" >&2
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL scripts: build-curl.sh: a libcurl floor with no pinned sum fails, naming it
  expected: (returned (1 "" "build-curl.sh: no sha256 is pinned for curl 9.9.9: fetch its release tarball, check it, and add the sum to tarball_sha256 in this script\n"))
  actual:   (returned (7 "" "https://curl.se/download/curl-7.85.0.tar.xz\n"))
FAIL scripts: build-curl.sh: the env cannot select a version with a sum: the file's floor has none, and fails
  expected: (returned (1 "" "build-curl.sh: no sha256 is pinned for curl 9.9.9: fetch its release tarball, check it, and add the sum to tarball_sha256 in this script\n"))
  actual:   (returned (7 "" "https://curl.se/download/curl-7.85.0.tar.xz\n"))
FAIL scripts: build-curl.sh: a malformed libcurl floor fails closed, before any download
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: the libcurl version \"7.85\" is not three dot-separated naturals, major.minor.patch\nbuild-curl.sh: no libcurl floor to build\n"))
  actual:   (returned (7 "" "https://curl.se/download/curl-7.85.0.tar.xz\n"))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```
(5 more such lines cut.)

### BS2. build-chez.sh: the version taken from CHEZ_VERSION when set

**Guards:** nothing in the environment changes the Chez version.

**Mutation:** In `scripts/ci/build-chez.sh`:

```diff
 here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
-version=$(sh "$here/floor.sh" chez) || {
+version=${CHEZ_VERSION:-$(sh "$here/floor.sh" chez)} || {
   echo "build-chez.sh: no Chez floor to build" >&2
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL scripts: build-chez.sh: the env cannot select a version with a sum: the file's floor has none, and fails
  expected: (returned (1 "" "build-chez.sh: no sha256 is pinned for Chez 9.9.9: fetch its release tarball, check it, and add the sum to tarball_sha256 in this script\n"))
  actual:   (returned (7 "" "https://github.com/cisco/ChezScheme/releases/download/v10.4.0/csv10.4.0.tar.gz\n"))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### BS3. build-curl.sh: a floor.sh failure ignored

**Guards:** a malformed or missing floor stops the build before any download.

**Mutation:** In `scripts/ci/build-curl.sh`:

```diff
 here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
-version=$(sh "$here/floor.sh" libcurl) || {
-  echo "build-curl.sh: no libcurl floor to build" >&2
-  exit 1
-}
+version=$(sh "$here/floor.sh" libcurl) || true
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL scripts: build-curl.sh: a malformed libcurl floor fails closed, before any download
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: the libcurl version \"7.85\" is not three dot-separated naturals, major.minor.patch\nbuild-curl.sh: no libcurl floor to build\n"))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: the libcurl version \"7.85\" is not three dot-separated naturals, major.minor.patch\nbuild-curl.sh: no sha256 is pinned for curl : fetch its release tarball, check it, and add th [cut: 43 more characters]
FAIL scripts: build-curl.sh: no floors file fails closed, before any download
  expected: (returned (1 "" "floor.sh: packaging/floors.sexp: it cannot be read\nbuild-curl.sh: no libcurl floor to build\n"))
  actual:   (returned (1 "" "floor.sh: packaging/floors.sexp: it cannot be read\nbuild-curl.sh: no sha256 is pinned for curl : fetch its release tarball, check it, and add the sum to tarball_sha256 in this script\n"))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### BS4. build-chez.sh: a version accepted before the prefix

**Guards:** the build scripts take no version argument.

**Mutation:** In `scripts/ci/build-chez.sh`:

```diff
 
-[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
+[ "$#" -ge 1 ] && [ "$#" -le 3 ] || usage
+prefix=$1
+case $prefix in [0-9]*) shift ;; esac
 prefix=$1
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL scripts: build-chez.sh: a version and a prefix, as the old calls gave, is the usage
  expected: (returned (2 "" "usage: build-chez.sh PREFIX [--nothreads]\n"))
  actual:   (returned (7 "" "https://github.com/cisco/ChezScheme/releases/download/v10.4.0/csv10.4.0.tar.gz\n"))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### EM1. expect-missing-api.sh: the version taken from CURL_FLOOR_VERSION when set

**Guards:** nothing in the environment changes the version required.

**Mutation:** In `scripts/ci/expect-missing-api.sh`:

```diff
 here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
-floor=$(sh "$here/floor.sh" libcurl) || fail "no libcurl floor to require"
+floor=${CURL_FLOOR_VERSION:-$(sh "$here/floor.sh" libcurl)} || fail "no libcurl floor to require"
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL scripts: expect-missing-api.sh: the env cannot name the version: CURL_FLOOR_VERSION is not read
  expected: (returned (1 "::error::expect-missing-api: make build exited 2, but did not refuse /lib/libcurl.so.4 at 8.1.2 as missing-api, naming curl_easy_header: the diff above runs from what must be printed to what was" ""))
  actual:   (returned (0 "expect-missing-api: make build exited 2, refusing /lib/libcurl.so.4 at 7.85.0 as missing-api, naming curl_easy_header" ""))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### EM2. expect-missing-api.sh: the version written into the script

**Guards:** the version required is the libcurl floor of the file.

**Mutation:** In `scripts/ci/expect-missing-api.sh`:

```diff
 here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
-floor=$(sh "$here/floor.sh" libcurl) || fail "no libcurl floor to require"
+floor=7.85.0
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL scripts: expect-missing-api.sh: the version it requires is the libcurl floor of the file
  expected: (returned (0 "chez-curl: libcurl refused\n(reason . missing-api)\n  path:       /lib/libcurl.so.4\n  source:     override\n  detail:     curl_easy_header\n  version:    8.1.2\n  TLS:        fake\nexpect-missing-api: make build e [cut: 92 more characters]
  actual:   (returned (1 "chez-curl: libcurl refused\n(reason . missing-api)\n  path:       /lib/libcurl.so.4\n  source:     override\n  detail:     curl_easy_header\n  version:    8.1.2\n  TLS:        fake\n--- /tmp/expect-missing-api.KUPO [cut: 486 more characters]
FAIL scripts: expect-missing-api.sh: a refusal at another version than the file's libcurl floor fails
  expected: (returned (1 "::error::expect-missing-api: make build exited 2, but did not refuse /lib/libcurl.so.4 at 8.1.2 as missing-api, naming curl_easy_header: the diff above runs from what must be printed to what was" ""))
  actual:   (returned (0 "expect-missing-api: make build exited 2, refusing /lib/libcurl.so.4 at 7.85.0 as missing-api, naming curl_easy_header" ""))
FAIL scripts: expect-missing-api.sh: the env cannot name the version: CURL_FLOOR_VERSION is not read
  expected: (returned (1 "::error::expect-missing-api: make build exited 2, but did not refuse /lib/libcurl.so.4 at 8.1.2 as missing-api, naming curl_easy_header: the diff above runs from what must be printed to what was" ""))
  actual:   (returned (0 "expect-missing-api: make build exited 2, refusing /lib/libcurl.so.4 at 7.85.0 as missing-api, naming curl_easy_header" ""))
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```
(2 more such lines cut.)

### PC1. check-action-pins.sh: the old gathering, a uses: line only

**Guards:** a line with a uses key in any spelling is gathered.

**Mutation:** In `scripts/ci/check-action-pins.sh`:

```diff
 quote="[\"']?"
-uses_key="(^|[][{,[:space:]])${quote}uses${quote}[[:space:]]*:"
+uses_key='^[[:space:]]*(-[[:space:]]+)?uses:'
 # A line that is only a comment.
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
FAIL pins: a flow mapping, though its commit is pinned
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.UQfStS name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.UQfStS/ci.yml:5:      - { [cut: 232 more characters]
FAIL pins: a flow mapping on a tag
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.V5dHgA name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.V5dHgA/ci.yml:5:      - { [cut: 185 more characters]
FAIL pins: a double-quoted key
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.vdojw2 name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.vdojw2/ci.yml:5:      - \ [cut: 161 more characters]
FAIL pins: a space before the colon
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.LTaOjD name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.LTaOjD/ci.yml:5:      - u [cut: 158 more characters]
```
(26 more such lines cut.)

### PC2. check-action-pins.sh: a quoted key not gathered

**Guards:** a quoted key is gathered.

**Mutation:** In `scripts/ci/check-action-pins.sh`:

```diff
 # comma.
-quote="[\"']?"
+quote=""
 uses_key="(^|[][{,[:space:]])${quote}uses${quote}[[:space:]]*:"
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL pins: a double-quoted key
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.BFx9Re name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.BFx9Re/ci.yml:5:      - \ [cut: 161 more characters]
FAIL pins: a double-quoted key, though its commit is pinned
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.sSJyUx name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.sSJyUx/ci.yml:5:      - \ [cut: 208 more characters]
FAIL pins: a single-quoted key
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.tNGiKc name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.tNGiKc/ci.yml:5:      - ' [cut: 159 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```
(2 more such lines cut.)

### PC3. check-action-pins.sh: white space before the colon not gathered

**Guards:** a key with white space before its colon is gathered.

**Mutation:** In `scripts/ci/check-action-pins.sh`:

```diff
 quote="[\"']?"
-uses_key="(^|[][{,[:space:]])${quote}uses${quote}[[:space:]]*:"
+uses_key="(^|[][{,[:space:]])${quote}uses${quote}:"
 # A line that is only a comment.
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL pins: a space before the colon
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.t0JyDA name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.t0JyDA/ci.yml:5:      - u [cut: 158 more characters]
FAIL pins: a space before the colon, though its commit is pinned
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.Kuyrgx name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.Kuyrgx/ci.yml:5:      - u [cut: 205 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### PC4. check-action-pins.sh: a key after a brace, bracket or comma not gathered

**Guards:** a key inside a flow mapping or sequence is gathered.

**Mutation:** In `scripts/ci/check-action-pins.sh`:

```diff
 quote="[\"']?"
-uses_key="(^|[][{,[:space:]])${quote}uses${quote}[[:space:]]*:"
+uses_key="(^|[[:space:]])${quote}uses${quote}[[:space:]]*:"
 # A line that is only a comment.
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
FAIL pins: a flow mapping, though its commit is pinned
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.tHNJKE name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.tHNJKE/ci.yml:5:      - { [cut: 232 more characters]
FAIL pins: a flow sequence of mappings
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.X49JAZ name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.X49JAZ/ci.yml:5:    steps [cut: 164 more characters]
FAIL pins: a later key of a flow mapping, after a comma
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 1 lines with a uses key under /tmp/curl-testing.lAtrCZ name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.lAtrCZ/ci.yml:5:      - { [cut: 167 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```
(5 more such lines cut.)

### PC5. check-action-pins.sh: a comment line is a uses line

**Guards:** a line that is only a comment is skipped.

**Mutation:** In `scripts/ci/check-action-pins.sh`:

```diff
   [ "$rc" -le 1 ] || fail "$file cannot be read"
-  keep -v "$comment" <"$work/hits" >"$work/lines"
+  cat "$work/hits" >"$work/lines"
   count=$((count + $(grep -c '' "$work/lines" || true)))
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL pins: a comment, a value and a word that only end in uses are no uses key
  expected: (returned same)
  actual:   (returned (got (1 "" "check-action-pins: /tmp/curl-testing.h1XniG/ci.yml:5:      # uses: actions/checkout@v4\ncheck-action-pins: 1 of 2 lines with a uses key are not \"uses: OWNER/REPO@<40 hex digits> # vTAG\", after an optional [cut: 157 more characters]
FAIL pins: a uses key only in a comment: nothing was checked
  expected: (returned same)
  actual:   (returned (got (1 "" "check-action-pins: /tmp/curl-testing.54uaaZ/ci.yml:1:# uses: actions/checkout@v4\ncheck-action-pins: 1 of 1 lines with a uses key are not \"uses: OWNER/REPO@<40 hex digits> # vTAG\", after an optional \"- \ [cut: 132 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### PC6. check-action-pins.sh: the canonical form not anchored at its end

**Guards:** the line holds nothing after the tag comment.

**Mutation:** In `scripts/ci/check-action-pins.sh`:

```diff
 # The one form allowed, after the line number grep -n puts first.
-canonical='^[0-9]+:[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]+v[0-9]+(\.[0-9]+)*[[:space:]]*$'
+canonical='^[0-9]+:[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]+v[0-9]+(\.[0-9]+)*[[:space:]]*'
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL pins: more after the tag
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 2 lines with a uses key under /tmp/curl-testing.Sh0MVq name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.Sh0MVq/ci.yml:5:      - u [cut: 213 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### PC7. check-action-pins.sh: the canonical form not anchored at its start

**Guards:** the key opens the line, after its indent and an optional dash.

**Mutation:** In `scripts/ci/check-action-pins.sh`:

```diff
 # The one form allowed, after the line number grep -n puts first.
-canonical='^[0-9]+:[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]+v[0-9]+(\.[0-9]+)*[[:space:]]*$'
+canonical='^[0-9]+:.*uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]+v[0-9]+(\.[0-9]+)*[[:space:]]*$'
```

**Command:** `make test`.

**Result:** killed, make test exit 2:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
FAIL pins: a uses key after other text on the line, in a trailing comment: it fails closed
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 2 lines with a uses key under /tmp/curl-testing.S7CrLU name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.S7CrLU/ci.yml:5:      - n [cut: 221 more characters]
FAIL pins: a key in a nested sequence
  expected: (returned same)
  actual:   (returned (got (0 "check-action-pins: all 2 lines with a uses key under /tmp/curl-testing.lCVAqs name a full commit SHA, with its tag in a comment\n" "") want (1 "" "check-action-pins: /tmp/curl-testing.lCVAqs/ci.yml:5:      - - [cut: 206 more characters]
test: FAIL tests/test-check-floors.sps (exit 1)
make test exit 2
```

### Not killed, by design: a matrix value of another version

Nothing in `check-floors` can see `curl: ["8.1.3"]`: it is no floor's version text, and it names no key. No
rule was invented for it. It reaches nothing: the build scripts take no version, and read the floor from the
file. On the final tree, with that matrix value in the floor job, `make check-floors` exits 0 and actionlint
exits 0:

```
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
make check-floors exit 0
actionlint exit 0
```

What closes it is the build scripts, not `check-floors`. The rows `build-curl.sh: the env cannot select a
version with a sum: the file's floor has none, and fails` and its Chez twin set `CHEZ_VERSION`,
`CURL_FLOOR_VERSION` and `version` to the pinned versions, and the script still names the file's floor, which
has no sum: BS1 fails the first, BS2 the second. The old call, a version first, is refused: BS4. `floor.sh`
has a row of the same kind (the keys set, the file's floor printed); no mutation of it was run.

### Coverage

Every rule added has a mutation that fails it by name, and the 171 tests R3 failed are now all passing
(308 pass). The kills by rule:

- the workflow rule in `(floors)`: KY1, KY2 (each key), VT1 (the version text), and on the real workflow
  FW1, FW2, FW3, FW5;
- `floor.sh`: FS1 (comments), FS2 (`#`), FS3 (the shape of the file), FS4 (a name twice), FS5 (the shape of the
  version), FS6 (a name missing), FW4 (the version printed);
- the build scripts and `expect-missing-api.sh`: BS1 to BS4, EM1, EM2;
- the pin check: PC1 to PC7 in the script, PN1 to PN4 on the workflow.

The first full pass reported PC7 as survived: it expected rows that the loosened start of the canonical form
does not fail, and the one row that did fail was the nested-sequence one. A row for a `uses` key after other
text on its line was added, and the mutation now names both.

### Not covered

- **Two ways to write `uses` that text cannot see.** A quoted key with an escape (`"\u0075ses": x`), and a
  complex key (`? uses`) with its value on another line, hold no line with the key spelled out. A YAML parser
  would see them; this check reads text. actionlint does not object to them either.
- **A string that holds `uses:`.** `run: echo "uses: x"` counts as a uses line and fails. That is the price of
  failing closed on text.
- **The version a step passes.** A step that passes a bare version to a build script, `build-curl.sh 8.1.3
  "$PREFIX"`, is no floor's text, and `check-floors` does not see it. At run time the script takes it for the
  prefix, which is not absolute, and refuses it, exit 2 (the old-call rows). No static check does.
- **A real build.** `build-chez.sh` and `build-curl.sh` were not run to completion, by the brief: the rows and
  the runs above stop at the download. The floors' pinned sums are checked only in that the checked-in floors
  reach the download (rows `the checked-in ... floor has a pinned sum`).
- **BSD tools.** The scripts and rows run `sh` (bash in the container; dash in Docker `ubuntu:24.04`, where a
  hand-run battery of cases, `dash-battery.sh` in `<fixci2>`, gave the answers the rows expect). `grep -o`, `grep -a`, `tr -s '[:space:]'` and `[][{,[:space:]]`
  are used as GNU and BSD grep both document them; macOS was not run.
- **The pin check in `make`.** It is not a Makefile target, and this fix could not touch the Makefile. CI runs
  it, and the suite runs it on directories it writes.

### Clean rerun

After every mutation, on the tree itself, whose files are byte-identical to the snapshot every case copied
(`diff -r`, without `build/`). `make test`, `make check-test-fails` and `make check-help` each exited 0 in the
container; actionlint, shellcheck (Docker, `koalaman/shellcheck:stable`, on the five `scripts/ci/` scripts) and
the pin check exited 0 on the host:

```
tree and snapshot identical (diff -r, without build/)
check-help exit 0
check-suites: every suite ends with (exit (suite-exit-status runner)) (14 checked)
check-seam: the seam holds (10 libraries in 10 files checked)
check-floors: README.org and .github/workflows (ci.yml) hold the floors in packaging/floors.sexp (chez 10.4.0, libcurl 7.85.0, node 20)
# of expected passes      308
test: ran 14, passed 14, failed 0, hung 0
make test exit 0
check-test-fails: make test failed, as it must, in all 10 cases
check-test-fails exit 0
actionlint exit 0
shellcheck exit 0
```
