# M8 slice 1: the memory job in two

The plan's §3.2 and §4; ADR-0014, amended 2026-11-06. Measured first, then built, then the check
watched failing.

## Each suite's time under the gate

From the memory job's log of four CI runs, by their timestamps (`times.sh`): a suite's time runs
from its `=== tests/X.sps` line to its `test-memory: pass` line. The four ran the same suites and
sources. The two pull requests' runs checked out GitHub's merge of the head onto `main`:
`daacead`, `da485cd` onto `29f4b5d`, which has `da485cd`'s tree, as `fbc6fce` does; and `db50717`,
`2c54687` onto `2f5ea9f`. These and `74d7aca` differ from `fbc6fce` only in `.plans/` and
`AGENTS.md`'s traps.

| Run | Event | Head | Checked out | Memory job |
|---|---|---|---|---|
| 42255186047 | push to `main` | `fbc6fce` | `fbc6fce` | 128020391358 |
| 42288043630 | push to `main` | `74d7aca` | `74d7aca` | 128133882402 |
| 42249246013 | PR #47's last | `da485cd` | `daacead` | 127999579512 |
| 42281172448 | PR #49's | `2c54687` | `db50717` | 128110200781 |

The logs are in `logs/`, and the table in `times.txt`, its columns in this order:

```sh
sh times.sh logs/memory-128020391358.log logs/memory-128133882402.log \
  logs/memory-127999579512.log logs/memory-128110200781.log >times.txt
sh balance.sh <times.txt >balance.txt
```

In seconds:

| Step | 128020391358 | 128133882402 | 127999579512 | 128110200781 |
|---|---|---|---|---|
| setup, to the planted defects' step | 22.9 | 24.7 | 26.5 | 40.9 |
| the planted defects, `check-memory-gate` | 83.5 | 97.5 | 99.4 | 124.0 |
| the suites, `test-memory` | 1,253.6 | 1,611.2 | 1,734.4 | 1,939.0 |
| first line to the last suite | 1,360.1 | 1,733.5 | 1,860.3 | 2,103.8 |

- **The runner's speed varies 1.55 times** between runs, from 1,252 to 1,937 s of suites, and
  every suite moves with it: a suite's slowest run over its fastest is 1.26, test-curl-testing's,
  to 2.21, test-unsupported's.
- **Two suites move most:** test-transfer, 86.6 to 162.3 s, and test-unsupported, 70.4 to
  155.8 s. They are the largest, beside test-upload's 88.9 to 141.4 s.

## The split

`balance.sh` takes each suite's slowest run, and, slowest first, puts each suite in the shard with
less time so far (`balance.txt`). Each shard's sum of its suites' times, in seconds:

| Shard | Suites | 128020391358 | 128133882402 | 127999579512 | 128110200781 |
|---|---|---|---|---|---|
| 1 | 21 | 645.7 | 809.7 | 872.0 | 977.3 |
| 2 | 20 | 606.4 | 799.7 | 860.9 | 959.8 |

The heavier shard's time is 1.25 to 6.48 per cent above the lighter's in each run. The plan aimed each shard at no
more than 16 minutes on a pull request's runner: PR #47's run gives 14.5 minutes of suites for
the slower shard, and PR #49's, the slowest of the four, 16.3. With setup and the planted
defects, which each shard runs, a shard's job comes to about 16.6 and 19.0 minutes on those two
runners, where the one job took 31.0 and 35.1.

A new suite goes in one of the Makefile's two lists, by its time, in the slice that adds it.

## The check, watched failing

`make check-memory-gate` gains six cases (`tests/check-memory-gate.sh`, n and o). Cases n read
what each run of `test-memory` ran, from its own `=== ` lines, and what it handed Valgrind, a
stand-in for Valgrind running nothing; case o reads `ci.yml`. In the Guix container the whole
check passed its 45 cases (`results/check-memory-gate-guix.log`).

Its first run failed `n refused` on a `MEMORY_SHARD` of `1"`: the shard's text reached a
double-quoted `echo` in the recipe, and the shell refused the whole recipe, a syntax error, before
the refusal ran (`results/check-memory-gate-guix-quote-bug.log`). `MEMORY_RUN` and
`MEMORY_RUN_NAME` now take only a shard of 1 or 2.

`mutate.sh` makes each of 18 mutations in a copy of the tree and runs the whole check there, each
copy in a container of its own (`results/<name>.log`, `results/mutate.out`), the last three from
the review below. Every one failed, and in one case alone, the 44 others passing:

| Mutation | Case failed | Named |
|---|---|---|
| a suite in neither list (`neither`) | n split | `tests/test-native.sps runs in neither shard` |
| a new suite in `tests/`, in no list (`new-suite`) | n split | `tests/test-zzz-new.sps runs in neither shard` |
| a suite in both (`both`) | n split | `tests/test-auth.sps runs 1 times in shard 1 and 1 in shard 2` |
| a list naming no suite (`missing`) | n split | `shard 1 runs tests/test-nope.sps, which is no suite in tests/` |
| `MEMORY_RUN` ignoring the shard (`run-ignores`) | n split | each suite in both |
| the shard refusal removed (`no-refusal`) | n refused | each value's line |
| the refusal beside `MEMORY_SUITES` removed (`no-origin`) | n beside | a suite ran, both arms |
| two jobs on shard 1 (`two-on-one`) | o ci | `2 steps run ... MEMORY_SHARD=1`, `0 ... =2` |
| `memory-2` deleted (`deleted`) | o ci | `0 steps run ... MEMORY_SHARD=2` |
| `MEMORY_SHRAD=2` (`misspelt`) | o ci | the line, and `0 steps run ... =2` |
| `memory-2`'s planted defects gone (`no-gate`) | o ci | `... with no "make check-memory-gate" step before it` |
| `continue-on-error: true` on shard 1's step (`continue`) | o ci | the step and its key |
| `if: false` on `memory-2` (`job-if`) | o ci | `job memory-2 has a job-level if:` |
| `if: false` on `memory-1`'s planted defects (`gate-if`) | o ci | the step and its key |
| shard 2's line as a `run: \|` block (`block`) | o ci | the line, and `0 steps run ... =2` |
| `--leak-check=full` dropped on the shard path alone (`shard-flags`) | n split | each shard's commands, `< --leak-check=full` |
| the refusal of a shard's list set from outside removed (`no-list-origin`) | n lists | a suite ran, both arms |
| the refusal of `MEMORY_RUN` and `MEMORY_RUN_NAME` removed (`no-run-origin`) | n lists | a suite ran, each |

## The review

An Opus agent reviewed the slice, read-only and adversarially, before the commit: no blocker, no
major, three minors and some nits. I reproduced the first before its fix.

- **No planted defect ran through the shard path,** and the evidence check compares Valgrind's
  options with the recipe's own list: `--leak-check=full` dropped on the shard path alone passed
  the whole check, 44 cases, and the leak plant passed through shard 1 while it failed with no
  shard. Case n split now holds every suite's command in each shard to case e's.
- **A shard's list could be set from outside,** on make's command line or under `make -e`, and so
  could `MEMORY_RUN`: each ran one suite. `test-memory` refuses each, case n lists.
- **The ledger gave 14.5 minutes alone,** not PR #49's 16.3, past the plan's aim of 16.
- Nits: a newline in `MEMORY_SHARD` still breaks the recipe's shell, which then runs no suite,
  now said in the Makefile; `ci.yml`'s Node line named the old job; its timing predates the shard
  cases; this README named the pull requests' heads where they checked out merges, gave no
  commands, and mixed the percentage's bases.

## On the pull request

PR #50's run 42300311966 at `20cd0d3`, its two memory jobs' logs in `logs/` (`times.sh` reads
them as it reads the others):

| Job | Suites | Wall time | Setup | Planted defects | Suites |
|---|---|---|---|---|---|
| `memory-1`, 128176068436 | 21 | 18 min 47 s | 21.0 s | 134.6 s | 967.2 s |
| `memory-2`, 128176068651 | 20 | 18 min 34 s | 21.5 s | 135.9 s | 953.9 s |

The two shards' suites came to within 1.4 per cent of each other, 1,918 s together, near PR
#49's 1,937 s, the slowest of the four runs above. `check-memory-gate` took 135 s, 39 cases, the
Guix-only six skipped; before this slice's cases it took 84 to 124 s.

## On `main`

`main`'s push run 42305322110 at `9fdb9f3`, all nine jobs passed, its memory logs in `logs/`:

| Job | Wall time | Setup | Planted defects | Suites |
|---|---|---|---|---|
| `memory-1`, 128193088547 | 13 min 22 s | 20.1 s | 90.2 s | 688.1 s |
| `memory-2`, 128193088459 | 20 min 3 s | 101.5 s | 136.4 s | 962.5 s |

Each job takes a runner of its own. Shard 2's suites took 0.99 to 1.05 times their pull
request's times, suite by suite; shard 1's 0.54 to 0.84, on a faster runner. A shard's wall time
follows its runner as much as its list.
