# Test harness mutation log

Evidence that the checks M0 slice 2 added fail through the property each claims to guard
([harness plan](2026-10-04-harness-plan.md) §6, [ADR-0015](decisions/0015-test-harness-and-scheme-dependencies.md)).
Every mutation was applied to a fresh copy of the working tree, made with `.git` (the pin checks
read git state) and without `build/`, in the session scratchpad. The working tree was never edited.
A driver applied each mutation, recorded what it changed, flagged any that changed nothing, and
compared every case's exit status and whole output with the expected text, never a substring.
The last section, Review fixes, supersedes some of what comes before it. Where an earlier entry no
longer applies, a line of its own says so, and the entry was not rerun.

## Pins and dependencies

The checks here are make targets, so their tests are cases the driver runs against them. The
`check-pins` cases ran on the host (dash, GNU userland, git 2.54.0). The `deps` and self-test cases
ran in the container (bash, Guix's userland, the same git: it held git then and holds none now,
see Review fixes), and `B2` and `B4` also on the host. A
case checks the exit status and the
whole output. `deps`'s probe script prints facts and its own status says nothing, so for it only
the output counts. Cases are named `B` (baselines), `K` (`check-pins`), `D` (`deps`) and `SG`
(the container's self-test). Code mutants are `CM` (`check-pins`) and `DM` (`deps`).

The red runs used a copy of the tree with the Makefile, `manifest.scm` and `.gitignore` as they
were at `e8a2f63` and the self-test already edited. A few cases (K10, K11, D7, and the
untracked-files line of B2 and B3) were written after the recipes, once the first cases passed.
Their red run is that same run, and each has a mutant that fails it (CM6, CM11, DM8, DM9).

There are two kinds of mutation:

- A **state** mutation breaks what a check guards: `Akku.lock`, the submodule's checkout, the
  recorded gitlink. The check is correct, so it must fail by name, and **Result** quotes its own
  output.
- A **code** mutation breaks the check itself. The driver then runs the whole suite of cases
  against the mutant, and **Result** names the cases that failed and quotes their `FAIL` lines.
  A mutant that fails no case has survived. None did.

### `make check-pins`

**Red run, before the recipe existed:** `make check-pins` printed
`make: *** No rule to make target 'check-pins'.  Stop.` and exited 2. The cases, run then, gave
`B1` `0 passed, 2 failed` and each of `K1a` to `K11` `1 passed, 1 failed`. Those thirteen passes
were all exit-status checks, which a missing target satisfies by exiting non-zero. CM8 fails the
status checks of K1a, K1b, K2 to K6 and K10, and CM1 those of K7 and K8. K9a, K9b and K11's status
checks have no mutant of their own (see Not covered); their whole-output checks do (CM9, CM11).

**Baseline:** `B1` `2 passed, 0 failed`, on `e8a2f63` plus this slice: exit 0, and

```
check-pins: chez-srfi 7879b52: Akku.lock, the recorded commit and the checkout agree
```

Every drift ends with one hint line, `check-pins: Bump the submodule and Akku.lock together
(ADR-0015). To restore the recorded checkout, run 'git submodule update --init vendor/chez-srfi'
on the host.` The state entries below quote the lines above it.

**Fresh clone:** the tree was committed in a scratch repository and cloned, which is the state CI
and a new checkout start from. Before `git submodule update --init vendor/chez-srfi`:

```
deps: vendor/chez-srfi/%3a64.sls not found, so the submodule is empty or missing. Run 'git submodule update --init vendor/chez-srfi' on the host: make deps never fetches, and the container has no network.
check-pins: vendor/chez-srfi is not checked out. Run 'git submodule update --init vendor/chez-srfi' on the host.
```

Both exited 2. After it, `B3` and `B5`'s probes in the container gave the outputs shown under
`make deps` below, `make check-pins` printed the agree line, and `git status` listed nothing.

#### K1a. The lock names another commit

**Guards:** `Akku.lock` and the submodule name one commit (ADR-0015 §2).
**Mutation:** `Akku.lock` names `f09bad7`, the pinned commit's first parent.
**Result:** exit 2. The gitlink and the checkout both disagree with the lock, and both lines name
both commits:

```
check-pins: PIN DRIFT: Akku.lock names f09bad7, but the superproject records 7879b527f267f067416552fb989135ad1b4ea436 for vendor/chez-srfi.
check-pins: PIN DRIFT: Akku.lock names f09bad7, but vendor/chez-srfi is checked out at 7879b527f267f067416552fb989135ad1b4ea436.
```

#### K1b. The lock is one digit off

**Guards:** the comparison is exact to the last digit of the lock's commit.
**Mutation:** `Akku.lock` names `7879b53`, where the pin is `7879b52`.
**Result:** exit 2: `check-pins: PIN DRIFT: Akku.lock names 7879b53, but the superproject records
7879b527f267f067416552fb989135ad1b4ea436 for vendor/chez-srfi.` and the same for the checkout.
CM10 and CM12 show this case is not redundant.

#### K2. The checkout moved

**Guards:** the submodule's checkout is the pinned commit, which `make deps` links and the suites
import.
**Mutation:** `git -C vendor/chez-srfi checkout f09bad7…`. The index still records `7879b52`.
**Result:** exit 2:

```
check-pins: PIN DRIFT: Akku.lock names 7879b52, but vendor/chez-srfi is checked out at f09bad7800275ac18f9486d72ae10ab0d7c1cdce.
```

#### K3. The recorded gitlink changed

**Guards:** the gitlink the superproject records is the pinned commit, which a clone checks out.
**Mutation:** `git update-index --cacheinfo 160000,f09bad7…,vendor/chez-srfi`. The checkout stays
at `7879b52`.
**Result:** exit 2:

```
check-pins: PIN DRIFT: Akku.lock names 7879b52, but the superproject records f09bad7800275ac18f9486d72ae10ab0d7c1cdce for vendor/chez-srfi.
```

#### K4. The submodule bumped, the lock not

**Guards:** a bump takes two edits, and one alone fails (ADR-0015, Consequences).
**Mutation:** `git -C vendor/chez-srfi checkout f09bad7…`, then `git add vendor/chez-srfi`.
**Result:** exit 2, both lines, naming `f09bad78…` and `7879b52`:

```
check-pins: PIN DRIFT: Akku.lock names 7879b52, but the superproject records f09bad7800275ac18f9486d72ae10ab0d7c1cdce for vendor/chez-srfi.
check-pins: PIN DRIFT: Akku.lock names 7879b52, but vendor/chez-srfi is checked out at f09bad7800275ac18f9486d72ae10ab0d7c1cdce.
```

#### K5. The submodule is not checked out

**Guards:** a missing checkout is a failure, not a pass. `git -C` on an empty submodule directory
reads the superproject's own HEAD (CM5 shows it).
**Mutation:** `git submodule deinit -f vendor/chez-srfi`: an empty directory, the gitlink kept.
**Result:** exit 2:

```
check-pins: vendor/chez-srfi is not checked out. Run 'git submodule update --init vendor/chez-srfi' on the host.
```

#### K6. The path is not recorded

**Guards:** a missing record is a failure.
**Mutation:** `git rm --cached vendor/chez-srfi`.
**Result:** exit 2:

```
check-pins: could not read the commit the superproject records for vendor/chez-srfi (is it a git submodule, and is this a git checkout?)
```

#### K7. The lock names no readable pin

**Guards:** an empty lock commit would match every commit as a prefix, so it must fail.
**Mutation:** `_repack` deleted from the `chez-srfi` URL in `Akku.lock`.
**Result:** exit 2: `check-pins: could not read a chez-srfi commit from Akku.lock`.

#### K8. The lock names a one-digit commit

**Guards:** a prefix shorter than seven digits is not read as a pin.
**Mutation:** `Akku.lock` names `7`, a prefix of the real commit.
**Result:** exit 2: `check-pins: could not read a chez-srfi commit from Akku.lock`.

#### K9a. No git, on a Guix host

**Guards:** `scripts/require-tools` stops `check-pins` before it runs, and names the goal.
**Mutation:** `PATH` holds one directory, with a stub `guix` and no git.
**Result:** exit 2:

```
make check-pins: git not found.
On this Guix host, run it in the project's container: scripts/guix-env make check-pins
```

#### K9b. No git, no guix

**Mutation:** `PATH` holds an empty directory.
**Result:** exit 2:

```
make check-pins: git not found.
Install the missing tools, then run make check-pins again.
```

#### K10. The checkout is broken

**Guards:** a checkout git cannot read is a failure, not a comparison against nothing.
**Mutation:** `vendor/chez-srfi/.git` contains `gitdir: /nonexistent`.
**Result:** exit 2: `check-pins: could not read the commit checked out in vendor/chez-srfi`.

**Superseded by the review fixes:** the guard asks git for a toplevel first, and a `gitdir:` file
that names no repository gives none, so this state now reads `check-pins: vendor/chez-srfi is not
checked out. Run 'git submodule update --init vendor/chez-srfi' on the host.` K10b, under Review
fixes, reaches the message above.

#### K11. The goal is what the user typed

**Guards:** `GOAL`'s `MAKECMDGOALS` branch, which slice 1 left unexercised: a hint names the
command the user ran, not an inner prerequisite.
**Mutation:** a scratch makefile with one rule, `wrapper: check-pins`, run as
`make -f Makefile -f wrapper.mk wrapper` with no git.
**Result:** exit 2:

```
make wrapper: git not found.
On this Guix host, run it in the project's container: scripts/guix-env make wrapper
```

#### CM1. The empty-lock guard deleted

**Guards:** K7 and K8.
**Mutation:** the `if [ -z "$$lock" ]` block replaced by `true; \`.
**Result:** killed by K7 and K8. With no lock commit, `"$$lock"*` is `*`, which matches every
commit: exit 0 and `check-pins: chez-srfi : Akku.lock, the recorded commit and the checkout agree`.
`FAIL K7 unreadable lock: exit status 0, wanted nz`, `FAIL K7 unreadable lock: output`,
`FAIL K8 lock names 7: exit status 0, wanted nz`, `FAIL K8 lock names 7: output`.

#### CM2. No minimum length for the lock's commit

**Guards:** K8.
**Mutation:** `\{7,40\}` in the `sed` pattern changed to `*`.
**Result:** killed by K8 alone, which exits 0 and prints
`check-pins: chez-srfi 7: Akku.lock, the recorded commit and the checkout agree`.
`FAIL K8 lock names 7: exit status 0, wanted nz`, `FAIL K8 lock names 7: output`. K7 did not
fail: the guard that CM1 deletes still catches an empty commit.

#### CM3. The recorded commit no longer compared

**Guards:** K1a, K1b, K3 and K4.
**Mutation:** the `case "$$rec"` block replaced by `true; \`.
**Result:** killed by K1a, K1b, K3 and K4. K3 exits 0 and prints the agree line. The other three
print only the checkout's PIN DRIFT line. `FAIL K3 gitlink moved: exit status 0, wanted nz`,
`FAIL K3 gitlink moved: output`, and `FAIL … : output` for K1a, K1b and K4.

#### CM4. The checked-out commit no longer compared

**Guards:** K1a, K1b, K2 and K4.
**Mutation:** the `case "$$out"` block replaced by `true; \`.
**Result:** killed by K1a, K1b, K2 and K4. K2 exits 0 and prints the agree line.
`FAIL K2 checkout moved: exit status 0, wanted nz`, `FAIL K2 checkout moved: output`, and
`FAIL … : output` for K1a, K1b and K4.

#### CM5. The not-checked-out guard deleted

**Guards:** K5.
**Mutation:** the `[ ! -e vendor/chez-srfi/.git ]` branch removed, leaving the `git -C … rev-parse
HEAD` read.
**Result:** killed by K5, and for the wrong reason, so the status check passed and only the output
check failed. In the empty directory `git -C` read the superproject's HEAD:

```
check-pins: PIN DRIFT: Akku.lock names 7879b52, but vendor/chez-srfi is checked out at e8a2f63cb89468221e8796045bfc3e0ced9c2022.
```

`FAIL K5 empty checkout: output`.

**Superseded by the review fixes:** the guard is now a comparison of git's toplevel with the
directory, not a test for `.git`. R-d is its mutation, and K5 was rerun on it.

#### CM6. The unreadable-checkout guard deleted

**Guards:** K10.
**Mutation:** the `elif ! out=$$(git -C … rev-parse HEAD …) || [ -z "$$out" ]` branch replaced by
a bare read.
**Result:** killed by K10, again with the right exit status and the wrong output:
`check-pins: PIN DRIFT: Akku.lock names 7879b52, but vendor/chez-srfi is checked out at .`
`FAIL K10 broken checkout: output`.

**Superseded by the review fixes:** K10 now stops at the toplevel guard and never reaches this
branch. K10b does, and CM6 was rerun against it (Review fixes).

#### CM7. The unreadable-record guard deleted

**Guards:** K6.
**Mutation:** the `if [ -z "$$rec" ]` branch replaced by `if false`.
**Result:** killed by K6: `check-pins: PIN DRIFT: Akku.lock names 7879b52, but the superproject
records  for vendor/chez-srfi.` with an empty commit. `FAIL K6 no gitlink: output`.

#### CM8. `check-pins` always exits 0

**Guards:** the exit status of K1a, K1b, K2 to K6 and K10.
**Mutation:** `exit $$fail` changed to `exit 0`.
**Result:** killed by eight cases. Each printed its right lines and exited 0:
`FAIL K1a lock names f09bad7: exit status 0, wanted nz`, and the same for `K1b`, `K2`, `K3`, `K4`,
`K5`, `K6` and `K10`. K7 and K8 did not fail: they exit before that line.

#### CM9. The `require-tools` line deleted

**Guards:** K9a, K9b and K11.
**Mutation:** `@scripts/require-tools "$(GOAL)" git` deleted.
**Result:** killed by K9a, K9b and K11. The recipe ran on without git and blamed the wrong thing:

```
/bin/sh: 1: sed: not found
/bin/sh: 1: head: not found
/bin/sh: 2: git: not found
/bin/sh: 2: awk: not found
check-pins: could not read a chez-srfi commit from Akku.lock
```

`FAIL K9a no git, guix on PATH: output`, `FAIL K9b no git, no guix: output`,
`FAIL K11 the hint names what the user typed: output`.

#### CM10. The lock compared on six digits, against the recorded commit

**Guards:** K1b.
**Mutation:** the `case "$$rec"` pattern `"$$lock"*` changed to `"$$(printf '%.6s' "$$lock")"*`.
**Result:** killed by K1b alone, which printed only the checkout's line and not the record's:
`FAIL K1b lock names 7879b53: output`.

#### CM11. `require-tools` given `$@`

**Guards:** K11.
**Mutation:** `"$(GOAL)"` changed to `"$@"` in the `require-tools` line.
**Result:** killed by K11 alone: the hint named `check-pins`, the inner target, not `wrapper`.
`FAIL K11 the hint names what the user typed: output`. K9a and K9b cannot tell the two apart,
since there `$@` and the goal are both `check-pins`.

#### CM12. The lock compared on six digits, against the checkout

**Guards:** K1b.
**Mutation:** the `case "$$out"` pattern changed the same way as CM10.
**Result:** killed by K1b alone, which printed only the record's line:
`FAIL K1b lock names 7879b53: output`.

#### CM13. The gitlink read from the wrong index stage

**Guards:** B1: a healthy tree passes, and the record is read from stage 0.
**Mutation:** `$$3 == 0` changed to `$$3 == 1` in the `awk` filter.
**Result:** killed by B1, K1a, K1b, K2, K3, K4, K5 and K10. On the healthy tree:

```
check-pins: could not read the commit the superproject records for vendor/chez-srfi (is it a git submodule, and is this a git checkout?)
```

and exit 2. `FAIL B1 healthy tree: check-pins: exit status 2, wanted 0`,
`FAIL B1 healthy tree: check-pins: output`, and `FAIL … : output` for the seven K cases.

### `make deps`

**Red run, before the recipe existed:** `make deps` printed
`make: *** No rule to make target 'deps'.  Stop.` and exited 2. The cases, run then, gave
`B2` to `B6`, `D2`, `D3` and `D7` each `0 passed, 1 failed`. The probe printed `deps exit: 2`
and, for the links, `links: 266 checked, 266 bad`. The status of a probe is not checked, so nothing
passed by absence.

**Baseline:** `B2` (host) and `B3` (container), each `1 passed, 0 failed`, on `e8a2f63` plus this
slice:

```
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
deps exit: 0
links: 266 checked, 0 bad
untracked files under build/: 0
srfi-64: chez exit 0
srfi-64: # of expected passes 1
```

On the host there is no Chez, and the last two lines are replaced by `srfi-64: not run (no CHEZ)`.
`266 checked` counts every top-level entry of the submodule, plus its decoded twin when the name
holds `%3a`. Each link must be exactly the absolute path of its entry. In the container,
`(import (srfi :64))` and a passing `test-equal` ran under Chez with
`CHEZSCHEMELIBDIRS=build/scheme-libs`.

`B4` (host) and `B5` (container) ran `make deps` twice, each `1 passed, 0 failed`: the second run
printed the same line, exited 0, and left `build/` and `vendor/chez-srfi` listings unchanged.
`B6` put a `git` that logs its calls and fails first on `PATH`: `git calls: 0`, `1 passed, 0 failed`.

#### D2. The submodule is empty

**Guards:** `deps` fails on an empty submodule, names the host command and links nothing
(ADR-0015 §3).
**Mutation:** `find vendor/chez-srfi -mindepth 1 -delete`, a fresh clone's state.
**Result:** exit 2, in the container:

```
deps: vendor/chez-srfi/%3a64.sls not found, so the submodule is empty or missing. Run 'git submodule update --init vendor/chez-srfi' on the host: make deps never fetches, and the container has no network.
deps exit: 2
links created: none
```

#### D3. The submodule is missing

**Mutation:** `rm -rf vendor/chez-srfi`.
**Result:** the same three lines.

#### D7. A link fails

**Guards:** a failed link fails `deps`.
**Mutation:** `chmod a-w build/scheme-libs/srfi` between two runs, so every `ln` fails.
**Result:** `second deps exit: 2` and `success lines: 0`.

#### DM1. The empty-or-missing guard deleted

**Guards:** D2 and D3.
**Mutation:** the `if [ ! -f vendor/chez-srfi/%3a64.sls ]` block replaced by `@:`.
**Result:** killed by D2 and D3. The glob `vendor/chez-srfi/*` matched nothing and stayed
literal, so `ln` made a dangling link named `*` and `deps` reported success:

```
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
deps exit: 0
links created: 1
```

`FAIL D2 empty submodule: refuses, names the host command, links nothing: output`, and the same
for `D3`.

#### DM2. `ln -sf`, without `-n`

**Guards:** a rerun changes nothing, and leaves the submodule's tree alone.
**Mutation:** `ln -sfn` changed to `ln -sf`.
**Result:** killed by B4 and B5. On the second run `ln` followed the existing link to a directory
and planted links inside the submodule's own tree:

```
vendor/chez-srfi: CHANGED
> %3a0/%3a0 l …/vendor/chez-srfi/%3a0
> %3a1/%3a1 l …/vendor/chez-srfi/%3a1
```

`FAIL B4 second run changes nothing: output`, `FAIL B5 second run changes nothing: output`.

#### DM3. `ln -sn`, without `-f`

**Guards:** a rerun is a no-op.
**Mutation:** `ln -sfn` changed to `ln -sn`.
**Result:** killed by B4 and B5. The second run died on the first link, and exited 2:
`ln: failed to create symbolic link '…/build/scheme-libs/srfi/%3a0': File exists`.
`FAIL B4 second run changes nothing: output`, `FAIL B5 second run changes nothing: output`.

#### DM4. The decoded names not linked

**Guards:** `(srfi :64)` is importable. Chez resolves it only from the decoded spelling.
**Mutation:** the `[ "$$d" = "$$b" ] || ln -sfn …` line replaced by `:;`.
**Result:** killed by B2 to B5. In the container: `links: 266 checked, 129 bad`,
`srfi-64: chez exit 255`, `srfi-64: Exception: library (srfi :64) not found`.
`FAIL B3 deps links everything, (srfi :64) imports and passes: output`, and B2, B4 and B5.

#### DM5. The siblings' fetch restored

**Guards:** `deps` never fetches (ADR-0015 §3).
**Mutation:** `@git submodule update --init vendor/chez-srfi` as the recipe's first line, silenced
so that no echo gives it away.
**Result:** killed by B6, D2 and D3 and by nothing else. B6's stub logged the call: `deps exit: 2`,
`git calls: 1`. In D2 and D3 git restored the submodule from the local clone, and `deps` succeeded
where it must refuse:

```
Submodule path 'vendor/chez-srfi': checked out '7879b527f267f067416552fb989135ad1b4ea436'
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
deps exit: 0
links created: 266
```

`FAIL B6 no git call: output`, `FAIL D2 empty submodule: refuses, names the host command, links
nothing: output`, and the same for `D3`. With no local copy to restore from, the same line would
clone from the network.

#### DM6. Only the `%3a64` entries linked

**Guards:** every entry of the submodule is linked, since `(srfi :64)` needs other libraries.
**Mutation:** `for f in $$src/*` changed to `for f in $$src/%3a64*`.
**Result:** killed by B2 to B5: `links: 266 checked, 262 bad`, and in the container
`srfi-64: Exception: library (srfi :0 cond-expand) not found`.
`FAIL B3 deps links everything, (srfi :64) imports and passes: output`, and B2, B4 and B5.

#### DM7. Relative link targets

**Guards:** each link is the absolute path of its entry.
**Mutation:** `src=$(abspath $(SRFI_SRC))` changed to `src=$(SRFI_SRC)`.
**Result:** killed by B2 to B5: every link dangles, `links: 266 checked, 266 bad`, and
`srfi-64: Exception: library (srfi :64) not found`.
`FAIL B3 deps links everything, (srfi :64) imports and passes: output`, and B2, B4 and B5.

#### DM8. `set -e` removed

**Guards:** D7.
**Mutation:** `@set -e; \` removed from the link loop.
**Result:** killed by D7 alone. Every `ln` failed, the loop's last iteration did not, and `deps`
reported success: `second deps exit: 0`, `success lines: 1`.
`FAIL D7 a failed link fails deps: output`.

#### DM9. `/build/` left out of `.gitignore`

**Guards:** the generated tree stays out of the repository.
**Mutation:** the `/build/` line deleted from `.gitignore`.
**Result:** killed by B2 and B3: `untracked files under build/: 266`, then
`untracked: ?? build/scheme-libs/srfi/%3a0` and two more.
`FAIL B3 deps links everything, (srfi :64) imports and passes: output`, and B2.

### `make check-help`, with the new targets

**Red run:** before the targets existed, neither mutation had anything to change, and the driver
flagged both `MUTATION DID NOT APPLY`.

**Baseline:** `make check-help` exit 0, silent, with `deps` and `check-pins` in `.PHONY` and `make
help` listing both.

#### H1. A target without a description

**Guards:** `check-help` reads the new targets too.
**Mutation:** `## ` removed from `deps`'s line.
**Result:** exit 2:
`check-help: make help does not list .PHONY target 'deps'; give it a '## ' description on its target line`.

#### H2. A described target outside `.PHONY`

**Mutation:** `check-pins` removed from `.PHONY`.
**Result:** exit 2: `check-help: make help lists 'check-pins', which is not in .PHONY`.

### Container (`make check-guix-inside`)

**Superseded in part by the review fixes:** the container has no git. SG1 to SG5 no longer apply,
and the baseline's git `tool-path` lines and its `check-pins` line are gone. The red run and SG0
are history. The self-test's current run is under Review fixes.

**Red run:** the self-test was edited first, then run in the pinned container before the manifest
or the Makefile changed. It exited 2, with 23 `ok` lines and these:

```
check-guix: FAILED tool-path[-lc]: git resolves to 'nothing' (via 'nothing'), expected /gnu/store/…-profile/bin/git
check-guix: FAILED tool-path[-lic]: git resolves to 'nothing' (via 'nothing'), expected /gnu/store/…-profile/bin/git
make[1]: *** No rule to make target 'check-pins'.  Stop.
check-guix: FAILED check-pins
```

The driver's `SG0` to `SG3`, run against that tree, gave `0 passed, 2 failed`,
`1 passed, 2 failed`, `1 passed, 1 failed` and `1 passed, 1 failed`.

**Baseline:** `SG0` `2 passed, 0 failed`. `make check-guix` on the host ends in the launcher's
`60 passed, 0 failed`, then in the container `check-guix: ALL CHECKS PASSED`, with these among its
lines:

```
check-guix: ok tool-path[-lc] (git: /gnu/store/…-profile/bin/git)
check-guix: ok tool-path[-lic] (git: /gnu/store/…-profile/bin/git)
check-pins: chez-srfi 7879b52: Akku.lock, the recorded commit and the checkout agree
```

#### SG1. The manifest lacks git

**Guards:** git is in the pinned container, and `check-pins` runs there.
**Mutation:** the `"git"` line deleted from `manifest.scm`.
**Result:** exit 2:

```
check-guix: FAILED tool-path[-lc]: git resolves to 'nothing' (via 'nothing'), expected /gnu/store/…-profile/bin/git
check-guix: FAILED tool-path[-lic]: git resolves to 'nothing' (via 'nothing'), expected /gnu/store/…-profile/bin/git
make check-pins: git not found.
Install the missing tools, then run make check-pins again.
check-guix: FAILED check-pins
```

#### SG2. A stand-in git comes first on `PATH`

**Guards:** a login shell runs the pinned git, not another one. It resolves paths, as for the other
tools (ADR-0006 §6).
**Mutation:** a stub `git`, which prints nothing and exits 0, ahead of the profile on `PATH`.
**Result:** exit 2:

```
check-guix: FAILED tool-path[-lc]: git resolves to '<copy>/.mut/bin/git' (via '<copy>/.mut/bin/git'), expected <git>/bin/git
check-guix: FAILED tool-path[-lic]: git resolves to '<copy>/.mut/bin/git' (via '<copy>/.mut/bin/git'), expected <git>/bin/git
check-pins: could not read the commit the superproject records for vendor/chez-srfi (is it a git submodule, and is this a git checkout?)
check-pins: could not read the commit checked out in vendor/chez-srfi
check-guix: FAILED check-pins
```

`<copy>` is the mutated copy's directory, and `<git>` is the pinned git's store item.

#### SG3. The lock drifts, seen from inside

**Guards:** the self-test runs `check-pins` in the container, and fails when it fails.
**Mutation:** `Akku.lock` names `f09bad7`.
**Result:** exit 2, after the two `ok tool-path` lines for git:

```
check-pins: PIN DRIFT: Akku.lock names f09bad7, but the superproject records 7879b527f267f067416552fb989135ad1b4ea436 for vendor/chez-srfi.
check-pins: PIN DRIFT: Akku.lock names f09bad7, but vendor/chez-srfi is checked out at 7879b527f267f067416552fb989135ad1b4ea436.
check-pins: Bump the submodule and Akku.lock together (ADR-0015). To restore the recorded checkout, run 'git submodule update --init vendor/chez-srfi' on the host.
check-guix: FAILED check-pins
```

#### SG4. The self-test's `check-pins` block deleted

**Guards:** Assertion 8's `check-pins` block is what catches SG3.
**Mutation:** the `if ! make --no-print-directory check-pins; then bad "check-pins"; fi` block
deleted from `scripts/guix-env-selftest`, then SG3's drift.
**Result:** killed by SG3. The self-test passed: exit 0, `check-guix: ALL CHECKS PASSED`.
`FAIL SG3 self-test: exit status 0, wanted nz`, `FAIL SG3 self-test: output`.

#### SG5. `git` dropped from the tool list

**Guards:** the tool loop's `git` entry is what catches SG2's stub.
**Mutation:** `git` removed from the `for tool in …` list, then SG2's stub.
**Result:** killed by SG2: the two `FAILED tool-path` lines were gone. Only `check-pins`'s own
failure remained, so a stand-in git would have passed the path check.
`FAIL SG2 self-test: output`.

### Last run

After the last change to the Makefile, the self-test, the manifest, `.gitignore` and the driver,
the whole set ran again on the working tree. Every baseline and every state entry passed, and all
24 code mutants (CM1 to CM13, DM1 to DM9, SG4 and SG5) were killed: 45 mutations in all. That was
before the review fixes: SG4 and SG5 no longer apply, R-d replaces CM5, and CM6 was rerun against
K10b.

### Findings

- **`guix shell -m` serves a stale profile.** It caches a manifest's profile by path, and keeps
  serving it while the file is no newer than the cache entry. The driver copies the tree with
  `tar`, which keeps modification times, so a copy made at a path an earlier run had used got that
  run's profile. That run had no git, and one baseline case failed with `git: command not found`
  inside a container whose manifest listed git. The driver now touches `manifest.scm` in each copy.
  Any swap of `manifest.scm` for an older file, by `cp -p` or `tar`, does the same.
- **`make install` needs `gzip`,** to compress the man page. The container has none, so the Chez
  build in the next section stopped there. Debian's base system has it.
- **An empty submodule directory is not an error to git.** `git -C vendor/chez-srfi rev-parse HEAD`
  answers with the superproject's HEAD (CM5), and so does an empty `.git` directory (R-d, under
  Review fixes). `check-pins` asks git for the submodule's toplevel and compares it with the
  directory.

### Debian prerequisites

`packaging/debian-prereqs.txt` has no check, and nothing has installed from it. Three things were
checked, and the file's header says which:

- **The three names exist in Ubuntu noble:** `build-essential` 12.10ubuntu1, `valgrind`
  1:3.22.0-0ubuntu3 and `libcurl4-openssl-dev` 8.5.0-2ubuntu10.15 (packages.ubuntu.com, read on
  2026-10-04). `libcurl4-openssl-dev` depends on `libcurl4t64` and ships
  `/usr/include/x86_64-linux-gnu/curl/curl.h`. noble's `chezscheme` is 9.5.8.
- **Chez 10.4.0 builds from its release tarball with only a C toolchain and make.** In the
  project's container, whose compiler finds no `curses.h`, `ncurses.h`, `X11/Xlib.h`,
  `uuid/uuid.h` or `zlib.h`, `./configure --disable-x11 --disable-curses` and a plain `make` ran to
  the end. The result printed `10.4.0` for `--version`, and answered `#t` to `(threaded?)` and `ta6le`
  to `(machine-type)`. Chez's `BUILDING` lists the same prerequisites, and its `configure` links
  `-lm -ldl -lrt` and `-lpthread` on Linux.
- **`make install` stopped at `gzip: command not found`.** `gzip` is `Essential: yes` on jammy
  (this host's apt metadata) and on noble.

### Not covered

- **`K9a`, `K9b` and `K11`'s exit-status checks.** With no git on `PATH`, every way `check-pins`
  can fail exits non-zero, so no mutant fails them. Their whole-output checks are what CM9 and
  CM11 fail.
- **`SG0`,** the self-test's healthy run. No code mutant fails it. Its red run, made before the
  manifest and the Makefile changed, is the only time it was seen failing.
- **The `build/: unchanged` half of the rerun check.** DM2 and DM3 fail the rerun through the
  submodule's listing and the exit status. No mutant I could write makes the second run change
  `build/` itself.
- **Stale links.** A re-pin that drops a file from chez-srfi leaves its old link in
  `build/scheme-libs/srfi`, dangling. `make deps` adds and replaces, as both siblings' do.
- **A dirty submodule.** `check-pins` compares commits. Uncommitted edits inside
  `vendor/chez-srfi` would be linked and tested, and nothing notices.
- **The manifest.** *Checked since the review fixes:* `tests/test-manifest.sps` holds
  `Akku.manifest` to no `depends` clause, no `scripts` clause and a `depends/dev` of exactly
  chez-srfi, and holds `Akku.lock`'s chez-srfi url to the manifest's version (R-f to R-h). Neither
  file is checked to parse as Akku reads it.
- **An unmerged index.** `check-pins` reads stage 0 only, so a conflicted gitlink would report as
  unreadable. No case makes one.
- **Other platforms.** The cases ran on one host (dash and GNU tools) and in the container. Not on
  macOS, where `sed`, `ln` and `awk` are BSD's (`\{7,40\}` and `ln -sfn` are the spots most likely
  to differ), and not on ubuntu-24.04, which is slice 5's first run.
- **The Debian file.** The Chez build was never taken through `make install` here, and valgrind
  and libcurl4-openssl-dev were never installed from apt.
- **`GOAL` through `test`.** K11 covers `check-pins` reached through a scratch target. The real
  case is `test`, which did not exist yet. M2 covers it, through `check-suites` since the review
  fixes.

## The suites and their checks

The checks here are `make test`, `make check-suites`, `make check-test-fails`, the launcher's `M2`
case and the self-test's new block, with the suite for `(curl-testing)`. A second driver ran them,
built like the first: a fresh copy of the working tree for each case, made with `.git` and without
`build/`, its `manifest.scm` touched, a refusal when a mutation changed nothing, and an exact
comparison of the exit status and the whole output, make's own `***` line aside. Cases ran in the
container, except `L0`, which runs the launcher's tests on the host.

Cases are named `CS` (`check-suites`), `TL` (the test loop and `check-test-fails`), `X`
(`check-test-fails` over a broken loop), `L0` (the launcher) and `SG` (the self-test). Code mutants
are `LM` (`(curl-testing)`), `LS` (its suite), `CM` (`check-suites`), `TM` (the loop), `FM`
(`check-test-fails`), `LA` (the hint) and `SG7`. As in the pins section, a **state** entry breaks what a check guards,
and the check must fail by name; a **code** entry breaks the check, and some case must fail.

The red runs used the tree with every test here written and none of the code: the Makefile as
the pins section left it, and `tests/curl-testing.sls` a stub whose six exports raised
`not written yet`.

The shared exit form is `(exit (suite-exit-status runner))`. `runner` is the suite's own binding
for the runner it makes current, and `suite-exit-status`, from `(curl-testing)`, answers 0 only
for a runner that saw a pass and no failure or unexpected pass.

### `(curl-testing)` and its suite

**Red run, against the stub:** `tests/test-curl-testing.sps` printed a FAIL line for each of its
26 tests and exited 255:

```
FAIL a pass beside an expected failure and a skip: exit 0, and nothing said
  expected: (0 "")
  actual:   #f
…
# of unexpected failures  26
Exception in suite-exit-status: not written yet
```

Seventeen actual values were `#f`, SRFI-64's rendering of the stub's raise. The nine refusal tests
got `(other-raise "not written yet")` instead of the condition they expect. No expected value is
`#f`, so none passed.

**Baseline:** `TL0` `2 passed, 0 failed`. `make test` exited 0 and printed:

```
check-pins: chez-srfi 7879b52: Akku.lock, the recorded commit and the checkout agree
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
=== tests/test-curl-testing.sps
%%%% Starting test curl-testing
# of expected passes      26
test: pass tests/test-curl-testing.sps
test: ran 1, passed 1, failed 0, hung 0
```

Since the review fixes `make test` does not run `check-pins`, so its first line is gone, and
`tests/test-manifest.sps` runs after this suite: `ran 2, passed 2`.

Every `LM` mutant ran against `TL0`, and every one was killed by it, on both its exit status and
its output. The suite prints a failing test's expected and actual values, so **Result** gives the
FAIL line and the actual value. Each mutant also turned the suite's line into
`test: FAIL tests/test-curl-testing.sps (exit 1)`, except LM27, which stopped `make test` at
`check-suites`.

#### LM1. Failures ignored

**Guards:** a failing test fails its suite.
**Mutation:** `(= fail 0)` dropped from `suite-exit-status`'s test.
**Result:** `FAIL two failures beside a pass: exit 1, not a count, since exit statuses wrap at 256`,
actual `(0 "")`. On its first run this mutant left `make test` green: exit 0 and
`test: pass tests/test-curl-testing.sps`, since the suite's own last line went through the mutant.
Only TL0's comparison of the whole output caught it. The suite now exits 1 on any failure before
its shared exit form (TL6, LS1).

#### LM2. Unexpected passes ignored

**Guards:** an unexpected pass fails its suite.
**Mutation:** `(= xpass 0)` dropped.
**Result:** `FAIL an unexpected pass beside a pass: exit 1`, actual `(0 "")`.

#### LM3. A suite with no pass passes

**Guards:** a suite that ran no test, or only expected failures and skips, fails (ADR-0015).
**Mutation:** `(> pass 0)` dropped.
**Result:** `FAIL an expected failure and a skip, but no pass: exit 1` and
`FAIL no test at all: exit 1`, each with actual `(0 "")`.

#### LM4. A count, not 1

**Guards:** the status is 0 or 1. Chez wraps exit statuses: `(exit 256)` exits 0.
**Mutation:** the failing answer `1` replaced by `(+ fail xpass (if (= pass 0) 1 0))`.
**Result:** `FAIL two failures beside a pass: exit 1, not a count, …`, actual
`(2 "suite-exit-status: exit 1 (pass 1, fail 2, xpass 0): a suite needs a pass, and no fail or xpass\n")`.
With one failure the count is 1, which is why the base has two.

#### LM5. No reason given

**Guards:** a failing verdict says why. SRFI-64's summary says nothing for a suite with no test.
**Mutation:** the `put-string` of the reason line deleted.
**Result:** the four failing-verdict tests, each with actual `(1 "")`.

#### LM6. Anything taken for a runner

**Guards:** `suite-exit-status` refuses a non-runner, under its own name.
**Mutation:** the `test-runner?` check deleted.
**Result:** `FAIL suite-exit-status refuses what is not a runner`, actual
`(assertion-violation test-runner-xpass-count ("not a runner" #<record type test-runner>))`. The
`let`'s last binding ran first: compiled code goes right to left (AGENTS.md).

#### LM7. Nothing quoted

**Guards:** each argument reaches the command as one word, unchanged.
**Mutation:** `(map shell-quote argv)` replaced by `argv`.
**Result:** `FAIL capture-command: the exit status, stdout and stderr, kept apart`, actual
`(3 "" "")`, and `FAIL capture-command: each argument arrives as one word, unchanged`, actual `#f`.

#### LM8. The streams merged

**Guards:** stdout and stderr are kept apart.
**Mutation:** the answer's stdout replaced by stdout then stderr, and its stderr by `""`.
**Result:** `FAIL capture-command: the exit status, stdout and stderr, kept apart`, actual
`(3 "out\nerr\n" "")`.

#### LM9. A non-zero exit raises

**Guards:** a non-zero exit is an answer a test can compare. chez-cmark-gfm's helper raises.
**Mutation:** `(unless (zero? status) (error …))` before the capture files are read.
**Result:** `FAIL capture-command: the exit status, stdout and stderr, kept apart`, actual `#f`.

#### LM10. A NUL let through

**Guards:** a NUL is refused. `system` takes a C string, which ends at the NUL.
**Mutation:** the NUL check deleted.
**Result:** `FAIL capture-command: a NUL would cut the command short, so it is refused`, actual
`(other-raise "the shell did not create a capture file")`. The shell got the command only up to
the NUL, so the redirections after it never ran.

#### LM11. A non-string argument taken

**Mutation:** the `string?` check deleted.
**Result:** `FAIL capture-command: every argument is a string`, actual
`(assertion-violation string->list (5))`.

#### LM12. An empty command taken

**Mutation:** the non-empty-list check deleted.
**Result:** `FAIL capture-command: a command has at least its name`, actual
`(assertion-violation cdr (()))`: `cdr` ran before `car`, right to left again.

#### LM13. A step before the first question

**Guards:** a predicate that already holds costs no step.
**Mutation:** the first clause became `((and (> taken 0) (done?)) 'satisfied)`.
**Result:** `FAIL run-until: a predicate that already holds costs no step`, actual `(satisfied 1)`.

#### LM14. The cap asked before the predicate

**Guards:** a predicate that first holds after the last step allowed is satisfied.
**Mutation:** the cap's clause moved ahead of the predicate's.
**Result:** `FAIL run-until: a predicate that first holds after the last step allowed is
satisfied`, actual `(iterations-exhausted 4)`.

#### LM15. One step past the cap

**Mutation:** `(>= taken max-steps)` became `(> taken max-steps)`.
**Result:** `FAIL run-until: one step short, it answers iterations-exhausted, with no step past the
cap`, actual `(satisfied 5)`.

#### LM16. Booleans for answers

**Guards:** an answer cannot be taken for the `#f` SRFI-64 makes of a raise.
**Mutation:** `'satisfied` and `'iterations-exhausted` became `#t` and `#f`.
**Result:** the four stepping tests, actuals `(#t 0)`, `(#t 3)`, `(#t 4)` and `(#f 4)`.

#### LM17 to LM19. Any cap, predicate or step

**Mutation:** each check deleted in turn.
**Result:** `FAIL run-until: the cap is a positive exact integer`, actual `no-raise`. Then
`FAIL run-until: the predicate is a procedure` and `FAIL run-until: the step is a procedure`, each
actual `(other-raise "attempt to apply non-procedure ~s")`.

#### LM20. The low byte

**Guards:** the bytes are bits 16 to 23, as the comment documents.
**Mutation:** `(mod (div next 65536) 256)` became `(mod next 256)`.
**Result:** `FAIL seeded-bytes: seed 1, as the documented generator computes it`, actual
`#vu8(166 231 148 61 50 131 0 57)`, and seed 2's test, actual `#vu8(19 80 73 78 111 124 5 90)`.

#### LM21. The seed ignored

**Mutation:** the generator started from 0.
**Result:** both seeds' tests, each actual `#vu8(0 220 4 101 170 31 173 29)`.

#### LM22 and LM23. Any length, any seed

**Mutation:** each check deleted in turn.
**Result:** `FAIL seeded-bytes: the length is a natural number`, actual
`(assertion-violation make-bytevector (-1))`, and `FAIL seeded-bytes: the seed is a natural
number`, actual `(assertion-violation bytevector-u8-set! (169.0))`.

#### LM24. Displayed, not written

**Mutation:** `(write obj p)` became `(display obj p)`.
**Result:** `FAIL describe: anything else is written, so a string keeps its quotes`, actual
`"(1 two three)"`.

#### LM25. Not total

**Guards:** a guard clause that calls `describe` cannot raise in turn.
**Mutation:** the `guard` replaced by `begin`.
**Result:** `FAIL describe: an object whose printing raises gets a fixed text, not a raise`, actual
`#f`.

#### LM26. A condition written

**Mutation:** `display-condition` dropped, so every object is written.
**Result:** `FAIL describe: a condition, as display-condition shows it`, actual
`"#<compound condition>"`.

#### LM27. Another binding in the shared form

**Guards:** `check-suites` holds the suites to the form `(curl-testing)` defines.
**Mutation:** `suite-exit-form` names `the-runner`.
**Result:** `make test` stopped at `check-suites`, exit 2:
`check-suites: tests/test-curl-testing.sps: its last datum is (exit (suite-exit-status runner)), not (exit (suite-exit-status the-runner))`.

#### TL6. The verdict broken, seen by make test

**Guards:** the suite that tests `suite-exit-status` does not trust it for its own exit: a
verdict that ignores failures would pass that suite, and `make test` with it.
**Mutation:** LM1's change, as a state.
**Result:** exit 2, through the suite's pre-check, which exits 1 before the shared form:

```
FAIL two failures beside a pass: exit 1, not a count, since exit statuses wrap at 256
  expected: (1 "suite-exit-status: exit 1 (pass 1, fail 2, xpass 0): a suite needs a pass, and no fail or xpass\n")
  actual:   (0 "")
# of expected passes      25
# of unexpected failures  1
test: FAIL tests/test-curl-testing.sps (exit 1)
test: ran 1, passed 0, failed 1, hung 0
```

Its red run is LM1's first run, before the pre-check existed, quoted under LM1.

#### LS1. The pre-check deleted

**Mutation:** `(when (positive? (test-runner-fail-count runner)) (exit 1))` deleted, run as TL6.
**Result:** killed by TL6: `make test` exited 0 with `test: pass tests/test-curl-testing.sps`.
`FAIL TL6 make test: exit status 0, wanted nz`.

**Not covered:**

- **stdin from `/dev/null`.** Under make a suite's stdin is already empty or closed, so no test can
  tell `</dev/null` from an inherited stdin. A mutant that dropped it would survive.
- **The capture files.** Removing them before and after each call, and the raise when the shell did
  not create one, are reached only by LM10's accident.
- **A `TMPDIR` with a space or a quote.** The paths are quoted, but no test sets `TMPDIR`.
- **A command killed by a signal.** `system` answers minus the signal number (`-15`, measured by
  hand), and no test asserts it.
- **Output that is not UTF-8,** which is decoded with replacement characters.

### `make check-suites`

**Red run, before the program and the target existed:** `make check-suites` printed
`make: *** No rule to make target 'check-suites'.  Stop.` and exited 2. The cases, run then, gave
`CS0` `0 passed, 2 failed`, and `CS1` to `CS6` `1 passed, 1 failed` each. Those passes were
exit-status checks, which a missing target satisfies by exiting non-zero. CM4 fails all six.

**Baseline:** `CS0` `2 passed, 0 failed`, exit 0:

```
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
```

Each state entry plants `tests/test-0-plant.sps` in the copy, a suite with one passing test. Each
exited 2, printing the `deps:` line and then the lines quoted.

#### CS1. The siblings' exit line

**Guards:** the last datum is exactly the shared form. The siblings' line passes a suite that ran
no test.
**Mutation:** the plant ends with `(exit (if (zero? (test-runner-fail-count runner)) 0 1))`.
**Result:**

```
check-suites: tests/test-0-plant.sps: its last datum is (exit (if (zero? (test-runner-fail-count runner)) 0 1)), not (exit (suite-exit-status runner))
```

#### CS2. A datum after the exit line

**Guards:** nothing follows the exit line, where it would never run.
**Mutation:** `(display "never runs\n")` after the shared form.
**Result:** `check-suites: tests/test-0-plant.sps: its last datum is (display "never runs\n"), not (exit (suite-exit-status runner))`.
Since the review fixes a second line follows, because the shared form is no longer the last datum:
`check-suites: tests/test-0-plant.sps: (exit (suite-exit-status runner)) before the last datum would
end the suite before its verdict; only (exit 1) may exit early`.

#### CS3. The exit line in a comment

**Guards:** the form must be a datum. A grep finds it in a comment.
**Mutation:** the last line is `;; (exit (suite-exit-status runner))`, after `(test-end "plant")`.
**Result:** `check-suites: tests/test-0-plant.sps: its last datum is (test-end "plant"), not (exit (suite-exit-status runner))`.

#### CS4. An empty suite

**Result:** `check-suites: tests/test-0-plant.sps: it holds no datum, so it cannot end with (exit (suite-exit-status runner))`.

#### CS5. A suite the reader cannot read

**Guards:** an unreadable suite is named, not a crash.
**Mutation:** the plant's `(import (rnrs)` is never closed.
**Result:**

```
check-suites: tests/test-0-plant.sps: it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 56 of #<input port tests/test-0-plant.sps>; the character position might differ
```

#### CS6. Two bad suites

**Guards:** every bad suite is named, in order, and one the reader cannot read does not hide the
next.
**Mutation:** CS5's plant, and `tests/test-1-plant.sps` ending with the siblings' line.
**Result:** CS5's line, then
`check-suites: tests/test-1-plant.sps: its last datum is (exit (if (zero? (test-runner-fail-count runner)) 0 1)), not (exit (suite-exit-status runner))`.

CM1 to CM9 ran against the program as it was before the review fixes rewrote its read loop and its
complaint assembly. CS1 to CS6 were rerun on the rewrite (Review fixes). The mutants were not.

#### CM1. Only the head compared

**Mutation:** a last datum accepted when it is a list that starts with `exit`.
**Result:** killed by CS1 and CS6. CS1 exited 0 with
`check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)`, and CS6 named
only its unreadable suite. `FAIL CS1 the siblings' exit line: exit status 0, wanted nz`,
`FAIL CS1 the siblings' exit line: output`, `FAIL CS6 two bad suites: output`.

#### CM2. A text search, as a grep would do

**Mutation:** a suite accepted when its text holds the form's text.
**Result:** killed by CS2 and CS3, which both exited 0 with `(2 checked)`.
`FAIL CS2 code after the exit form: exit status 0, wanted nz`,
`FAIL CS3 exit line in a comment: exit status 0, wanted nz`, and their output lines.

#### CM3. The first datum kept

**Mutation:** the read loop kept the first datum it read.
**Result:** killed by all seven. CS0 flagged the real suite:
`check-suites: tests/test-curl-testing.sps: its last datum is (import (rnrs) (srfi :64) (only (chezscheme) parameterize record-writer) (prefix (only (chezscheme) current-error-port) chez:) (curl-testing)), not (exit (suite-exit-status runner))`.
`FAIL CS0 every suite ends with the form: exit status 2, wanted 0`.

#### CM4. Always exits 0

**Mutation:** `(exit (if (null? complaints) 0 1))` became `(exit 0)`.
**Result:** killed by CS1 to CS6. Each printed its own line and exited 0:
`FAIL CS1 the siblings' exit line: exit status 0, wanted nz`, and the same for the other five.

#### CM5. Stops at the first bad suite

**Result:** killed by CS6 alone, which named only `tests/test-0-plant.sps`.
`FAIL CS6 two bad suites: output`.

#### CM6. A reader error not caught

**Mutation:** the `guard` around the read replaced by `begin`.
**Result:** killed by CS5 and CS6: Chez's own message, with no suite named after it.
`Exception in read: unexpected end-of-file reading list before file-position 56 of #<input port tests/test-0-plant.sps>; the character position might differ`.
`FAIL CS5 unreadable suite: output`, `FAIL CS6 two bad suites: output`.

#### CM7. An empty suite passes

**Result:** killed by CS4: exit 0 and `(2 checked)`.
`FAIL CS4 empty suite: exit status 0, wanted nz`.

#### CM8. No `require-tools` line

**Guards:** a missing Chez is named, with the goal and the hint.
**Mutation:** `@scripts/require-tools "$(GOAL)" $(CHEZ)` deleted from `check-suites`.
**Result:** killed by TL4 (under `make test`), which printed
`make: /nonexistent/scheme: No such file or directory`. `FAIL TL4 no Chez: output`.

#### CM9. No suite handed to the program

**Mutation:** `$(SUITES)` dropped from the recipe.
**Result:** killed by all seven, each exiting 0 with `(0 checked)`.
`FAIL CS0 every suite ends with the form: output`,
`FAIL CS1 the siblings' exit line: exit status 0, wanted nz`, and so on.

**Not covered:**

- **A suite that rebinds `exit`, `suite-exit-status` or `runner`** before its last line. The check
  compares data, not meaning.
- **A suite whose `runner` is not the runner it made current.** Its form is right, and it fails
  only when it runs, as a runner that saw no pass.
- **Chez's wording.** CS5 quotes the reader's message whole, so a Chez that rewords it fails CS5
  and nothing else.

### `make test`

**Red run, before the target existed:** `make test` printed
`make: *** No rule to make target 'test'.  Stop.` and exited 2. `TL0` and `TL1` gave
`0 passed, 2 failed`; `TL2` to `TL5`, `1 passed, 1 failed` each, the pass again an exit-status
check that absence satisfies.

**Baseline:** `TL0`, under `(curl-testing)`. `TL1`, `make check-test-fails`, is under its own
heading.

Since the review fixes, `make test` has no `check-pins` among its prerequisites and runs each suite as
`$(TIMEOUT) --foreground $(TEST_TIMEOUT) …`. So the `check-pins:` line in TL2's output is gone, and the
three lines before TL3's message are two; TM5, X5 and FM3 name `timeout $(TEST_TIMEOUT)`, spelled as
above now; TM10 no longer applies. None was rerun.

#### TL2. `check-help` fails

**Guards:** `make test` runs `check-help` first (ADR-0015).
**Mutation:** `check-pins` left out of `.PHONY`.
**Result:** exit 2:

```
check-pins: chez-srfi 7879b52: Akku.lock, the recorded commit and the checkout agree
deps: vendor/chez-srfi linked into build/scheme-libs/srfi
check-help: make help lists 'check-pins', which is not in .PHONY
```

The first mutation tried here deleted the `## ` on `deps`'s line, as the pins section's H1 did.
That turned the description's `;` into a recipe, and `make test` died at `deps`, so it was
replaced.

#### TL3. No `timeout`

**Guards:** `timeout` is required (ADR-0015).
**Mutation:** in the container, `PATH` holds links to every profile tool but `timeout`.
**Result:** exit 2, after the prerequisites' three lines:

```
make test: timeout not found.
Install the missing tools, then run make test again.
```

#### TL4. No Chez, for `check-suites`

**Mutation:** `make check-suites CHEZ=/nonexistent/scheme`.
**Result:** exit 2, after the `deps:` line: `make check-suites: /nonexistent/scheme not found.` and
`Install the missing tools, then run make check-suites again.`

#### TM1. Stops at the first failure

**Guards:** a failing suite does not hide the suites after it.
**Mutation:** `break` after the FAIL line.
**Result:** killed by TL1. `check-test-fails` failed its fails and no-tests cases:

```
check-test-fails: FAILED fails: a failing suite is named FAIL, and the suites after it run: make test's check-suites and test lines differ
  …
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
  got:    test: FAIL tests/test-0-plant.sps (exit 1)
  got:    test: ran 1, passed 0, failed 1, hung 0
```

`FAIL TL1 check-test-fails: exit status 2, wanted 0`, `FAIL TL1 check-test-fails: output`.

#### TM2. Always exits 0

**Mutation:** the recipe's last line, `[ $$failed -eq 0 ] && [ $$hung -eq 0 ]`, became `true`.
**Result:** killed by TL1:
`check-test-fails: FAILED fails: a failing suite is named FAIL, and the suites after it run: make test exited 0`,
and the same for the no-tests and hangs cases.

#### TM3. A hung suite not counted

**Mutation:** `&& [ $$hung -eq 0 ]` dropped.
**Result:** killed by TL1, through the hangs case alone:
`check-test-fails: FAILED hangs: a suite that never ends is named HUNG, and the suites after it run: make test exited 0`.

#### TM4. Exit 124 named FAIL

**Mutation:** `elif [ $$rc -eq 124 ]` became `elif false`.
**Result:** killed by TL1, the hangs case:
`got:    test: FAIL tests/test-0-plant.sps (exit 124)` and
`got:    test: ran 2, passed 1, failed 1, hung 0`. The first version of this mutation deleted the
branch's two lines and left a blank line inside the recipe. The shell then died of
`syntax error: unexpected end of file`, which is not the property, so it was rewritten.

#### TM5. No per-suite timeout

**Mutation:** `timeout $(TEST_TIMEOUT)` dropped from the suite's command.
**Result:** killed by TL1, after 70 s:

```
check-test-fails: FAILED hangs: a suite that never ends is named HUNG, and the suites after it run: make test did not finish within 70s, so no per-suite timeout is stopping its suites
```

#### TM6. No suite, and a pass

**Mutation:** the `[ -z "$(SUITES)" ]` block deleted.
**Result:** killed by TL1:
`check-test-fails: FAILED no-suites: make test refuses to pass with no suite to run: make test exited 0`,
with `got:    test: ran 0, passed 0, failed 0, hung 0`.

#### TM7. `check-suites` not a prerequisite

**Mutation:** `check-suites` dropped from `test`'s prerequisites.
**Result:** killed by TL1. The exit-line plant ran and passed:
`check-test-fails: FAILED exit-line: check-suites names a suite without the shared exit form, and no suite runs: make test exited 0`.
Every other case failed too, for want of its `check-suites:` line.

#### TM8. `check-help` not a prerequisite

**Result:** killed by TL2: `make test` exited 0 and ran the suite.
`FAIL TL2 make test stops at check-help: exit status 0, wanted nz`.

#### TM9. `timeout` not required

**Result:** killed by TL3, which ran the suite anyway: `test: FAIL tests/test-curl-testing.sps (exit 127)`.

**Not covered:**

- **TM11 survived: `deps` dropped from `test`'s prerequisites.** `check-suites` depends on `deps`,
  so `deps` still runs, after `check-help` instead of before it. Only TL2's line order would show
  it.
- **TM12 survived: `$(sort)` dropped from `SUITES`.** GNU make 4.3's `$(wildcard)` already sorts:
  files made in the order m, z, a, q and b came back sorted. The `$(sort)` is for make 3.82 to 4.2.
- **A suite that ignores SIGTERM.** `timeout` sends TERM, and Chez dies on it. There is no `-k`.
- **A suite that exits 124 by itself** would be named HUNG.

### `make check-test-fails`

**Rewritten by the review fixes.** Its copy leaves out `.git` and `build/` and holds no real suite:
the plant, and a passing `tests/test-1-after.sps` that follows it. It has seven cases, two of them
new (`early-exit`, `nested-exit`), and takes `make` and `timeout` from the Makefile. The entries below
ran against the earlier script, so the lines they quote name a real suite and `5 cases`. TL5 and FM4
no longer apply, and two **Not covered** items are replaced. X2, X4, X5 and FM1 to FM3 mutate the
status check, the comparison and the timeout, which the rewrite kept; they were not rerun.

**Red run, before `make test` existed:** `tests/check-test-fails.sh`, run directly, failed each of
its four cases then and exited 1. The first:

```
check-test-fails: FAILED fails: a failing suite is named FAIL, and the suites after it run: make test's outcome lines differ
  wanted: test: FAIL tests/test-0-plant.sps (exit 1)
  wanted: test: pass tests/test-curl-testing.sps
  wanted: test: 2 suites: 1 passed, 1 failed, 0 hung
  got:    
```

Its exit-status checks passed, since `make test` exited 2 with no rule; FM1 shows they matter. The
exit-line case, the `check-suites:` lines in each comparison and one short `TEST_TIMEOUT` for
every case came after this run. That run is their red run, and each has a mutant that fails it:
TM7 for the exit-line case and the `check-suites:` lines, TM5 and FM3 for the timeouts.

**Baseline:** `TL1` `2 passed, 0 failed`, in about 10 s:

```
check-test-fails: ok fails: a failing suite is named FAIL, and the suites after it run
check-test-fails: ok no-tests: a suite that runs no test is named FAIL, and the suites after it run
check-test-fails: ok hangs: a suite that never ends is named HUNG, and the suites after it run
check-test-fails: ok exit-line: check-suites names a suite without the shared exit form, and no suite runs
check-test-fails: ok no-suites: make test refuses to pass with no suite to run
check-test-fails: make test failed, as it must, in all 5 cases
```

The `X` entries break the loop, so `check-test-fails` must fail. They compare its
`check-test-fails:` lines only. The `make test` output it prints after them is quoted under the TM
entries.

#### X2. The loop always exits 0

**Mutation:** TM2's.
**Result:** exit 2. The fails, no-tests and hangs cases each failed with `make test exited 0`; the
exit-line and no-suites cases passed, since `make test` stops before the loop's last line there.

#### X4. Exit 124 named FAIL

**Mutation:** TM4's.
**Result:** exit 2, the hangs case alone:
`check-test-fails: FAILED hangs: a suite that never ends is named HUNG, and the suites after it run: make test's check-suites and test lines differ`.

#### X5. No per-suite timeout

**Mutation:** TM5's.
**Result:** exit 2, after 70 s, the hangs case alone, on both counts:
`… make test did not finish within 70s, so no per-suite timeout is stopping its suites` and
`… make test's check-suites and test lines differ`.

#### TL5. No real suite to run after the plant

**Guards:** with no real suite, every case would pass with the plant alone, and show nothing about
the suites after it.
**Mutation:** `tests/test-curl-testing.sps` deleted.
**Result:** exit 1:
`check-test-fails: no tests/test-*.sps in the tree, so nothing shows make test running the suites after a failure`.

**No longer applies:** the copy holds no real suite, so the script has no such guard.

#### FM1. The exit status not checked

**Mutation:** the `make test exited 0` branch deleted, run as X2.
**Result:** killed by X2. Over a loop that always exits 0, `check-test-fails` passed all five
cases. `FAIL X2 check-test-fails: exit status 0, wanted nz`.

#### FM2. The lines not compared

**Mutation:** the comparison's `if` made `if false`, run as X4.
**Result:** killed by X4: all five cases passed while the loop named the hang FAIL.
`FAIL X4 check-test-fails: exit status 0, wanted nz`.

#### FM3. No timeout around `make test`

**Mutation:** `timeout "$make_timeout"` dropped, run as X5.
**Result:** killed by X5, which the driver stopped at its cap: the plant sleeps for an hour.
`FAIL X5 check-test-fails: the case did not finish within 150s`.

#### FM4. No guard for an empty tree

**Mutation:** the `[ "$n_real" -eq 0 ]` block deleted, run as TL5.
**Result:** killed by TL5: every case passed with the plant alone, and `check-test-fails` exited 0.
`FAIL TL5 no real suite: exit status 0, wanted nz`. Before the script counted its suites in the
loop, this mutant failed for another reason: `printf '%s\n'` with no argument still prints one
line, so an empty list counted as one suite, and the counts were wrong.

**No longer applies,** as TL5.

**Not covered:**

- **The plants' own passing tests.** No mutant removes one. Without it the fails plant would also
  fail for having no pass, and LM1 would go unseen here, though the helper suite still sees it.
- **What `cp -a` copies.** The copy takes untracked and ignored files too, everything but `.git`
  and `build/`.
- **A slow real suite.** *No longer applies:* the copy holds no real suite.

### `GOAL` through `make test`

**Superseded by the review fixes.** `make test` no longer stops at `check-pins`, which is not a
prerequisite of it now, so M2 was reworked to stop at `check-suites` (M2 and R-c, under Review
fixes). LA1 and TM10 no longer apply.

**Guards:** `GOAL`'s `$(MAKECMDGOALS)` branch, which K11 reached only through a scratch target.
With a stub `guix` alone on `PATH`, `make test` stops at its first prerequisite, `check-pins`, and
the hint names `test`. This is the real case the pins section's last **Not covered** item waited
for.

**Red run, before `make test` existed:** `L0` `0 passed, 2 failed`. The launcher printed
`FAIL M2 make test without git: the prerequisite's hint names test` and `61 passed, 1 failed`. Its
`fails` check passed: a missing target exits non-zero too.

**Baseline:** `L0` `2 passed, 0 failed`: `ok   M2 make test without git: fails`,
`ok   M2 make test without git: the prerequisite's hint names test` and `62 passed, 0 failed`.
`make test` printed:

```
make test: git not found.
On this Guix host, run it in the project's container: scripts/guix-env make test
```

#### LA1. `$@`, not `$(GOAL)`

**Mutation:** `check-pins`'s `require-tools` line given `"$@"`.
**Result:** killed by L0: `FAIL M2 make test without git: the prerequisite's hint names test`, and
`61 passed, 1 failed`. `make test` printed `make check-pins: git not found.` and
`On this Guix host, run it in the project's container: scripts/guix-env make check-pins`.

#### TM10. `check-pins` not first

**Mutation:** `check-pins` dropped from `test`'s prerequisites.
**Result:** killed by L0, with the same FAIL line. `deps` ran first:
`make: mkdir: No such file or directory`.

**No longer applies:** `check-pins` is not a prerequisite of `test` since the review fixes.

### Container: `make test` in the self-test

**Red run, before `make test` existed:** `SG0` `0 passed, 2 failed`: `check-guix: FAILED test`,
exit 2.

**Baseline:** `SG0` `2 passed, 0 failed`. Among the self-test's lines:

```
test: pass tests/test-curl-testing.sps
test: ran 1, passed 1, failed 0, hung 0
check-guix: ALL CHECKS PASSED
```

#### SG6. A failing suite, seen from inside

**Guards:** the self-test runs `make test`, and fails when it fails.
**Mutation:** a plant with one passing and one failing test.
**Result:** exit 2:

```
test: FAIL tests/test-0-plant.sps (exit 1)
test: pass tests/test-curl-testing.sps
test: ran 2, passed 1, failed 1, hung 0
check-guix: FAILED test
```

#### SG7. The self-test's `make test` block deleted

**Mutation:** the `if ! make --no-print-directory test; then bad "test"; fi` block deleted, run as
SG6.
**Result:** killed by SG6: the self-test passed, exit 0, `check-guix: ALL CHECKS PASSED`.
`FAIL SG6 self-test: exit status 0, wanted nz`, `FAIL SG6 self-test: output`.

### Last run, for this section

After the last change to the Makefile, the scripts, the suites and the driver, every case and
mutant here ran again on the working tree. All 20 baseline and state entries passed. Of 55 code
mutants, 53 were killed. TM11 and TM12 survived, as **Not covered** under `make test` explains. That
was before the review fixes.

### Findings

- **Chez wraps exit statuses at 256.** `(exit 256)` exits 0, so an exit form that answered a count
  would pass a suite with 256 failures. Chez's `(exit #t)` exits 1, so a boolean is no answer
  either. The shared form answers 0 or 1.
- **`system` stops at a NUL.** The command runs up to it, silently, and what follows, here the
  redirections, is lost (LM10).
- **`parameterize` needs Chez's own `current-error-port`.** `(rnrs)`'s takes no argument, and
  rebinding it raises `incorrect number of arguments`. Rebinding Chez's changes what `(rnrs)`'s
  returns.
- **Right to left, in `let` too.** LM6 and LM12 show compiled code evaluating a `let`'s inits and a
  call's arguments last first, the trap AGENTS.md names.
- **A suite cannot be the only judge of its own verdict.** The suite that tests
  `suite-exit-status` exits through it, so a verdict that ignored failures passed that suite and
  `make test` (LM1's first run). `check-test-fails` catches it too, since its fails plant then
  passes. A review rerun found that, against the earlier `check-test-fails`, LM1 failed its fails,
  no-tests and hangs cases with the pre-check, and only its fails case without it: with the
  pre-check the real suite exits 1, so its pass line is missing from every case. The suite now
  exits 1 on a failure first (TL6). Since the review fixes the copy holds no real suite, so by
  construction only the fails case can see LM1. That was not rerun.
- **GNU make 4.3 sorts `$(wildcard)`,** so `$(sort)` around it shows nothing here (TM12).
- **A blank line ends a make recipe's continued line,** and the rest of the shell script runs as
  separate commands. A deletion mutant must keep the continuation (TM4's first version).

## Review fixes

A review found that in a git worktree `.git` is a file that points outside the one directory the
container shares, so git inside the container reads nothing: `fatal: not a git repository: (null)`.
`make test` ran `check-pins`, so `make test` and `make check-guix` failed in every worktree. The
decision ([ADR-0006](decisions/0006-pinned-guix-container.md)'s amendment): the container has no git
again, `check-pins` runs on the host and in CI, and `test` no longer depends on it. What changed:

- `manifest.scm` drops git. The self-test drops git from its tool-path list and its `check-pins`
  block from Assertion 8.
- `test` depends on `deps check-help check-suites`, and runs each suite as `$(TIMEOUT) --foreground
  $(TEST_TIMEOUT) …`. `TIMEOUT` is `timeout`, else `gtimeout` (Homebrew's coreutils, on macOS), else
  the bare name, which `require-tools` then reports missing. Without `--foreground`, timeout puts the
  suite in its own process group, and Ctrl-C at a host terminal waits out the whole timeout.
- `check-test-fails` runs no git (see its rewrite, above).
- `check-suites` has a second rule: before a suite's last datum, every list whose car is `exit` is
  exactly `(exit 1)`, nested forms included.
- `check-pins` takes the submodule to be checked out only if git's toplevel for it is that
  directory. An empty `.git` directory passed the old test, `.git` exists, and git then answered for
  the superproject.
- `deps` quotes its paths. A checkout path with a space failed it with `Error 127`.
- `tests/test-manifest.sps` is new. It reads `Akku.manifest` and `Akku.lock` as data.
- The launcher's `M2` runs `make test CHEZ=no-such-chez` in a copy of the tree, and `T9a` to `T9c`
  are new.

The driver, `fix-mutate.sh`, is built like the others: a fresh copy of the working tree for each
mutation, made in the session scratchpad without `build/`, its `manifest.scm` touched, a refusal when
a mutation changed nothing, and the whole output of every run kept. The copies have no `.git`, since
nothing here reads git state, except those of R-d, K5, K10, K10b and CM6. Container runs are
`scripts/guix-env sh -c 'make test'` or `'make check-test-fails'` in the copy. The rest ran on the
host (dash, GNU Make 4.3, git 2.54.0).

Beyond the review's list: R-a2 and the `nested-exit` case, R-b2, R-e2, and the reruns K5, K10, K10b,
CM6 and CS1 to CS6. Each says why.

### Red runs

**`tests/test-manifest.sps`, before its assertions were written.** The skeleton (the imports, the
runner, an empty `test-begin` and `test-end`, the shared exit form), in the container:

```
%%%% Starting test manifest
suite-exit-status: exit 1 (pass 0, fail 0, xpass 0): a suite needs a pass, and no fail or xpass
exit=1
```

**M2 and T9, before the Makefile changed.** A copy of the tree with the earlier Makefile, which has
`check-pins` among `test`'s prerequisites and no `TIMEOUT`, and the new launcher test:

```
FAIL M2 make test without Chez: the prerequisite's hint names test
FAIL T9a timeout and gtimeout: timeout, by its path
FAIL T9b only gtimeout: gtimeout, by its path
FAIL T9c neither: the bare name timeout
63 passed, 4 failed
```

M2's other three checks passed, since absence satisfies them: `make test` stopped at `check-pins`,
which fails in a copy with no `.git`, so the exit status was non-zero, no suite ran, and stderr
lacked the `make test: no-such-chez not found.` line. That Makefile is also the mutant for
`check-pins` back among `test`'s prerequisites. T9 printed an empty line, `TIMEOUT` being undefined.

The first T9 red run failed for the wrong reason. With the recipe first specified,
`@echo $(TIMEOUT)`, make found no shell character in the line and ran `echo` itself, and `PATH` held
only the stubs:

```
make: echo: No such file or directory
make: *** [<builtin>: print-timeout] Error 127
```

The recipe is `@echo "$(TIMEOUT)"`: the quote sends the line through the shell, whose `echo` is
built in. The red run above is the second.

**The `early-exit` case, before `check-suites` had the rule.** `make check-test-fails` in the
container. The other four cases passed. The plant has a failing test, and `make test` passes it: its
`(exit 0)` ends the run before the verdict.

```
check-test-fails: FAILED early-exit: check-suites names a suite that exits before its verdict, and no suite runs: make test exited 0
check-test-fails: FAILED early-exit: check-suites names a suite that exits before its verdict, and no suite runs: make test's check-suites and test lines differ
  wanted: check-suites: tests/test-0-plant.sps: (exit 0) before the last datum would end the suite before its verdict; only (exit 1) may exit early
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
  got:    test: pass tests/test-0-plant.sps
  got:    test: pass tests/test-1-after.sps
  got:    test: ran 2, passed 2, failed 0, hung 0
```

`nested-exit` was written after the rule. Its red run is R-a's, and R-a2 is the mutant that only it
fails.

### Baseline

After the fixes, on the working tree: `make check-help` exit 0, silent. `make check-pins`, on the
host, exit 0:

```
check-pins: chez-srfi 7879b52: Akku.lock, the recorded commit and the checkout agree
```

The launcher's tests, on the host: `67 passed, 0 failed`, M2 and T9a to T9c among them. In the
container, `scripts/guix-env sh -c 'make test && make check-test-fails'` exit 0:

```
check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
test: pass tests/test-curl-testing.sps
test: pass tests/test-manifest.sps
test: ran 2, passed 2, failed 0, hung 0
check-test-fails: ok fails: a failing suite is named FAIL, and the suites after it run
check-test-fails: ok no-tests: a suite that runs no test is named FAIL, and the suites after it run
check-test-fails: ok hangs: a suite that never ends is named HUNG, and the suites after it run
check-test-fails: ok exit-line: check-suites names a suite without the shared exit form, and no suite runs
check-test-fails: ok early-exit: check-suites names a suite that exits before its verdict, and no suite runs
check-test-fails: ok nested-exit: check-suites names an exit inside a form before the verdict, and no suite runs
check-test-fails: ok no-suites: make test refuses to pass with no suite to run
check-test-fails: make test failed, as it must, in all 7 cases
```

`make check-guix`, on the host, exit 0: the launcher's `67 passed, 0 failed`, then in the container
23 `ok` lines, none for git and none for `check-pins`, `test: ran 2, passed 2, failed 0, hung 0`
and `check-guix: ALL CHECKS PASSED`. The container runs of R-a to R-i were made in copies with no
`.git`, which is what a worktree looks like from inside the container, and their unmutated cases and
suites passed.

### The early-exit rule

#### R-a. The early-exit rule deleted

**Guards:** `check-suites` rejects an exit form before a suite's last datum, `(exit 1)` apart.
**Mutation:** in `tests/check-suites.sps`, the `map` that turns the early exits into complaints
replaced by `'()`.
**Result:** killed by `early-exit` and `nested-exit`, both of which let the plant through: `make
test` exited 0 and ran both suites. The other four cases passed. For each of the two:

```
check-test-fails: FAILED early-exit: check-suites names a suite that exits before its verdict, and no suite runs: make test exited 0
check-test-fails: FAILED early-exit: check-suites names a suite that exits before its verdict, and no suite runs: make test's check-suites and test lines differ
  wanted: check-suites: tests/test-0-plant.sps: (exit 0) before the last datum would end the suite before its verdict; only (exit 1) may exit early
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (2 checked)
  got:    test: pass tests/test-0-plant.sps
  got:    test: pass tests/test-1-after.sps
  got:    test: ran 2, passed 2, failed 0, hung 0
```

The second case's lines read `FAILED nested-exit: check-suites names an exit inside a form before
the verdict, and no suite runs: …`, with the same `wanted:` and `got:` lines.

#### R-a2. The walk does not recurse (an addition)

**Guards:** the nested half of the rule. The `early-exit` plant exits at top level, so without
`nested-exit` nothing would see a form inside another.
**Mutation:** `early-exits` tests the datum itself, and no longer walks the elements of a list.
**Result:** killed by `nested-exit` alone. `early-exit` passed. The two `FAILED nested-exit` lines
and the same five `wanted:` and `got:` lines as R-a.

### The `TIMEOUT` fallback and `M2`

#### R-b. The gtimeout fallback dropped

**Guards:** `gtimeout` is used where there is no `timeout`, as on macOS with Homebrew's coreutils.
**Mutation:** `$(shell command -v gtimeout 2>/dev/null),` deleted from `TIMEOUT`.
**Result:** killed by T9b alone: `FAIL T9b only gtimeout: gtimeout, by its path` and `66 passed, 1
failed`.

#### R-b2. timeout and gtimeout swapped (an addition)

**Guards:** `timeout` wins when both exist. T9a's stub directory holds both names for this: with
`timeout` alone, T9a could not tell the order, and this mutant would have survived.
**Mutation:** the two `command -v` calls swapped.
**Result:** killed by T9a alone: `FAIL T9a timeout and gtimeout: timeout, by its path` and `66
passed, 1 failed`.

#### R-c. `$@` for `$(GOAL)` in `check-suites`

**Guards:** M2: `GOAL`'s `$(MAKECMDGOALS)` branch, reached through a prerequisite, with `deps` and
`check-help` passing first.
**Mutation:** `scripts/require-tools "$(GOAL)" $(CHEZ)` became `"$@"` in `check-suites`.
**Result:** killed by M2's hint check alone: `FAIL M2 make test without Chez: the prerequisite's hint
names test` and `66 passed, 1 failed`. The mutant printed:

```
make check-suites: no-such-chez not found.
On this Guix host, run it in the project's container: scripts/guix-env make check-suites
```

Unmutated, `make test CHEZ=no-such-chez` prints `make test: no-such-chez not found.`, and M2 compares
that line alone, since the hint after it depends on whether the host has guix.

### `check-pins` and `deps`

#### R-d. The toplevel comparison reverted

**Guards:** a submodule directory with an empty `.git` directory in it is "not checked out". git
does not take an empty `.git` directory for a repository, so it asks the superproject.
**Mutation:** the state is `rm vendor/chez-srfi/.git && mkdir vendor/chez-srfi/.git`, in a copy with
`.git`. The mutant replaces `[ -z "$$top" ] || [ "$$top" != "$$want" ]` with `[ ! -e
$(SRFI_SRC)/.git ]`, the old test.
**Result:** with the comparison, exit 2:

```
check-pins: vendor/chez-srfi is not checked out. Run 'git submodule update --init vendor/chez-srfi' on the host.
```

With the old test, exit 2 and the wrong diagnosis, naming the superproject's HEAD, which the copy's
`git rev-parse HEAD` confirms:

```
check-pins: PIN DRIFT: Akku.lock names 7879b52, but vendor/chez-srfi is checked out at e8a2f63cb89468221e8796045bfc3e0ced9c2022.
```

#### K5, K10, K10b and CM6, rerun (additions)

The guard is code the review changed, so the entries that reach it were rerun, on copies with `.git`.
All exited 2.

- **K5,** `git submodule deinit -f vendor/chez-srfi`: the same message as the fix in R-d, `check-pins:
  vendor/chez-srfi is not checked out. …`.
- **K10,** a `gitdir: /nonexistent` file: no longer `could not read the commit checked out`, but
  `check-pins: vendor/chez-srfi is not checked out. …`. git finds no repository there, so it prints
  no toplevel. The old K10 and CM6 entries say so.
- **K10b,** `rm vendor/chez-srfi/.git && git init -q vendor/chez-srfi`, an empty repository: a
  toplevel, and no commit. It reaches the branch K10 used to:
  `check-pins: could not read the commit checked out in vendor/chez-srfi`.
- **CM6,** that branch replaced by a bare read, against K10b: killed, with
  `check-pins: PIN DRIFT: Akku.lock names 7879b52, but vendor/chez-srfi is checked out at HEAD.`
  `git rev-parse HEAD` in a repository with no commit prints `HEAD` and exits 128, so the status
  check in the real branch is what catches it.

#### R-e. `deps` unquoted, in a path with a space

**Guards:** a checkout path may hold a space. The copies were made in `…/fix/sp ace/`.
**Mutation:** `src="$(abspath $(SRFI_SRC))"; dst="$(abspath $(SRFI_LIBS))/srfi"` and `for f in
"$$src"/*` reverted to the unquoted spelling.
**Result:** the mutant failed, and the fix passed. The probe counts the links in
`build/scheme-libs/srfi` and those that dangle.

```
fix:      deps: vendor/chez-srfi linked into build/scheme-libs/srfi
          deps exit=0     links: 266     dangling: 0
mutant:   /bin/sh: 2: ace/R-e/vendor/chez-srfi: not found
          make: *** [Makefile:101: deps] Error 127
          deps exit=2     links: 0       dangling: 0
```

#### R-e2. Only the two assignments quoted (an addition)

**Guards:** the loop's glob. The review asked for the two assignments to be quoted. That is not
enough: `for f in $$src/*` splits on the space as well.
**Mutation:** the assignments quoted, the glob `$$src/*` not.
**Result:** `deps` passed, and linked garbage: `deps: vendor/chez-srfi linked into
build/scheme-libs/srfi`, `deps exit=0`, `links: 2`, `dangling: 2`. The loop's glob is quoted too,
and R-e's mutant reverts it with the rest.

### `tests/test-manifest.sps`

Each mutation changes `Akku.manifest` or `Akku.lock` in a copy, and runs `make test` in the
container. Every one exited 2 with `test: pass tests/test-curl-testing.sps`, then the named test's
FAIL, `test: FAIL tests/test-manifest.sps (exit 1)` and `test: ran 2, passed 1, failed 1, hung 0`.
The suite's other three tests passed each time.

#### R-f. A scripts clause added

**Guards:** the package has no `scripts` clause.
**Mutation:** `(scripts (build "make"))` before `depends/dev` in `Akku.manifest`.
**Result:**

```
FAIL Akku.manifest has no scripts clause
  expected: ()
  actual:   ((scripts (build "make")))
```

#### R-g. A depends clause added

**Guards:** the package has no `depends` clause, which a consumer would install.
**Mutation:** `(depends ("chez-srfi" "^0.0.0-akku.181.7879b52"))` before `depends/dev`.
**Result:**

```
FAIL Akku.manifest has no depends clause
  expected: ()
  actual:   ((depends ("chez-srfi" "^0.0.0-akku.181.7879b52")))
```

#### R-h. The lock's version changed

**Guards:** `Akku.lock`'s chez-srfi url holds the version `Akku.manifest` asks for.
**Mutation:** `7879b52` became `7879b53` in the lock's url.
**Result:**

```
FAIL Akku.lock's chez-srfi url holds the version Akku.manifest asks for
  expected: (#t)
  actual:   (#f)
```

### `check-test-fails`

#### R-i. The after-suite not planted

**Guards:** the after-suite's pass line is what shows `make test` going on after a failure.
**Mutation:** `cp "$plant_dir/after" "$copy/$after"` deleted from `tests/check-test-fails.sh`.
**Result:** killed by the three cases that print the after-suite's lines, by name. Each got `(1
checked)`, the plant's line and `ran 1`, where it wanted `(2 checked)`, the after-suite's pass line
and `ran 2`:

```
check-test-fails: FAILED fails: a failing suite is named FAIL, and the suites after it run: make test's check-suites and test lines differ
  got:    check-suites: every suite ends with (exit (suite-exit-status runner)) (1 checked)
  got:    test: FAIL tests/test-0-plant.sps (exit 1)
  got:    test: ran 1, passed 0, failed 1, hung 0
check-test-fails: FAILED no-tests: a suite that runs no test is named FAIL, and the suites after it run: make test's check-suites and test lines differ
check-test-fails: FAILED hangs: a suite that never ends is named HUNG, and the suites after it run: make test's check-suites and test lines differ
  got:    test: HUNG tests/test-0-plant.sps (no exit within 5s)
  got:    test: ran 1, passed 0, failed 0, hung 1
```

The other four cases, `exit-line`, `early-exit`, `nested-exit` and `no-suites`, passed. They stop at
`check-suites`, or run no suite, so no line of theirs depends on the after-suite, and none could
fail by its absence.

### `check-suites`, rerun on the rewrite

The read loop and the complaint assembly were rewritten for the new rule. CS1 to CS6 were rerun in
the container, each plant at `tests/test-0-plant.sps` beside the two real suites (CS0 `(3
checked)`). CS1, CS3, CS4 and CS6's second line are the old lines. CS5's file position, 36, is the
plant's own. CS2 has the second line described under it. The CM mutants were not rerun.

```
CS0  check-suites: every suite ends with (exit (suite-exit-status runner)) (3 checked)
CS1  check-suites: tests/test-0-plant.sps: its last datum is (exit (if (zero? (test-runner-fail-count runner)) 0 1)), not (exit (suite-exit-status runner))
CS2  check-suites: tests/test-0-plant.sps: its last datum is (display "never runs\n"), not (exit (suite-exit-status runner))
     check-suites: tests/test-0-plant.sps: (exit (suite-exit-status runner)) before the last datum would end the suite before its verdict; only (exit 1) may exit early
CS3  check-suites: tests/test-0-plant.sps: its last datum is (test-end "plant"), not (exit (suite-exit-status runner))
CS4  check-suites: tests/test-0-plant.sps: it holds no datum, so it cannot end with (exit (suite-exit-status runner))
CS5  check-suites: tests/test-0-plant.sps: it cannot be read as data: Exception in read: unexpected end-of-file reading list before file-position 36 of #<input port tests/test-0-plant.sps>; the character position might differ
CS6  (CS5's line), then
     check-suites: tests/test-1-plant.sps: its last datum is (exit (if (zero? (test-runner-fail-count runner)) 0 1)), not (exit (suite-exit-status runner))
```

A probe of the walker on a scratch suite, by hand: `'(quit exit)`, `(only (chezscheme) exit)` and
`(when #f (exit 1))` raised nothing, and a nested `(exit 2)`, a bare `(exit)` and a quoted `'(exit 0)`
were each named.

### Findings

- **make runs a line itself when it has no shell character in it.** `@echo $(TIMEOUT)`, under a
  `PATH` of stubs, looked for an `echo` program and died with Error 127. T9's recipe quotes the value.
- **Quoting `deps`' assignments is not enough** (R-e2): the loop's glob splits on the space too.
- **git does not take an empty `.git` directory for a repository, and goes on up** (R-d). A
  `gitdir:` file that names nothing is an error with no toplevel instead (K10). Both now read as
  "not checked out".
- **`git rev-parse HEAD` in a repository with no commit prints `HEAD` and exits 128** (CM6).
- **The shared exit form is itself an early exit** when something follows it: CS2 now names it as
  well as the trailing datum.

### Last run

After the last change to the code (a comment in `check-suites.sps`), the four runs this closes on
passed: `make check-help` on the host; `scripts/guix-env sh -c 'make test && make check-test-fails'`;
`make check-guix` on the host; `make check-pins` on the host. Their lines are under Baseline. Of the
review's mutations R-a to R-i, and the additions R-a2, R-b2, R-e2, K5, K10, K10b and CM6, every one
that mutates code was killed by the case named for it; the state runs (R-d's fix, R-e's fix, K5,
K10, K10b) gave the lines above.

### Not covered

- **`--foreground` has no automated case.** Its effect is on process groups, under a host
  terminal's Ctrl-C, and no case has a terminal. A mutant that dropped it would survive every
  check. It was checked once by hand instead; see "After the fixes" below.
- **`early-exits` and tails or quoted data.** It visits the elements of a list, never its tails, so
  `'(quit exit)` and `(only (chezscheme) exit)` pass (the probe above). No plant pins that, and a
  mutant that walked tails would survive. A quoted `'(exit 0)` is named, by design, as the header of
  `tests/check-suites.sps` says.
- **`CM1` to `CM9` of `check-suites`** ran before the rewrite, and were not rerun on it. The
  rewritten program has mutants of its own, N1 to N5, below.
- **M2's second hint line,** which depends on whether the host has guix. M2 compares the first.
- **`$(or)` and `--eval` on GNU Make 3.81 (macOS).** T9 ran on GNU Make 4.3 only.
- **That the container has no git** is now asserted. See `no-git`, below.
- **A circular datum in a suite** would hang `early-exits`. `read` makes one only from a datum
  label, which no suite uses.

## After the fixes

These runs were made after the review fixes landed, against the rewritten `check-suites.sps`, a
new `check-test-fails` case and a new self-test assertion. Each mutation ran in a fresh copy of the
tree, made without `.git` and `build/`.

### `check-suites`, rewritten

The crafted suites live inside the copy, because the container shares only that directory. A
first attempt placed them outside it, and every one read as `no such file or directory`. That
attempt is discarded.

**Baseline**, three crafted suites:
- an empty file;
- `(display "unbalanced"`;
- a suite with `(display "after")` after the shared form.

Exit 1, with four complaints:
- `…/test-empty.sps: it holds no datum, so it cannot end with (exit (suite-exit-status runner))`;
- `…/test-unreadable.sps: it cannot be read as data: Exception in read: unexpected end-of-file …`;
- `…/test-trailing.sps: its last datum is (display "after"), not (exit (suite-exit-status runner))`;
- `…/test-trailing.sps: (exit (suite-exit-status runner)) before the last datum would end the
  suite before its verdict; only (exit 1) may exit early`.

#### N1. The last-datum comparison disabled

**Mutation:** `(if (equal? last suite-exit-form) …)` changed to `(if #t …)`.
**Result:** `check-test-fails: FAILED exit-line: …`. `early-exit` and `nested-exit` still passed:
the early-exit rule names those plants on its own.

#### N2. An unreadable suite accepted

**Mutation:** the unreadable branch answers `'()`.
**Result:** the run against the crafted suites lost exactly the `cannot be read as data` line. An
unreadable suite cannot pass silently anyway: Chez fails it when `make test` runs it.

#### N3. An empty suite accepted

**Mutation:** the empty branch answers `'()`.
**Red run:** `make check-test-fails` passed all 7 of its cases (`exit 0`). Nothing in the
repository noticed.
**Fix:** a new case, `empty`. It plants an empty `tests/test-0-plant.sps`, and `check-suites` must
name it before any suite runs.
**Result with the new case:** `FAILED empty: … make test's check-suites and test lines differ`,
with `got: … (2 checked)`, `got: test: FAIL tests/test-0-plant.sps (exit 255)`. So without the
rule, Chez fails an empty program with exit 255, and gives no reason. The case guards
`check-suites`' plain diagnosis; it is not a silent pass. **Baseline:**
`check-test-fails: make test failed, as it must, in all 8 cases`.

#### N5. `check-suites` always exits 0

**Mutation:** the last line changed to `(exit 0)`.
**Result:** `FAILED exit-line`, `FAILED early-exit` and `FAILED nested-exit`: their complaints were
printed, but the suites ran anyway.

### `no-git`, a new self-test assertion

**Guards:** the container has no git (ADR-0006's amendment). With git, every worktree breaks.
**Baseline:** `check-guix: ok no-git`, then `ALL CHECKS PASSED`.
**Mutation G1:** `"git"` put back in `manifest.scm`. The manifest was `touch`ed, per the traps
entry on `guix shell -m`'s cache.
**Result:** `check-guix: FAILED no-git: git is at /gnu/store/…-profile/bin/git; anything that needs
git runs on the host`.

### `--foreground`, checked by hand

A Python script, `pty.fork()`, ran `make test TEST_TIMEOUT=60` on the host, in a pseudo-terminal,
with one planted suite that loops forever. It sent `^C` once the suite had started:

- **With `--foreground`:** make exited 0.0 s after `^C` (status -2), printing
  `make: *** [Makefile:177: test] Interrupt`.
- **Without it:** make was still running 30 s after `^C`, and the script killed it. This is the
  review's finding, reproduced.

Afterwards, no `scheme` or `timeout` process was left. There is no automated case (see Not
covered above).

### Worktrees, the review's first finding, closed

A scratch clone was set up with the slice committed and the chez-srfi gitlink recorded. A worktree
was added from it, with the submodule initialised there, so its `.git` is a file naming
`…/repo/.git/worktrees/wt/modules/vendor/chez-srfi`. In that worktree:

- `make check-pins` on the host: `check-pins: chez-srfi 7879b52: Akku.lock, the recorded commit
  and the checkout agree`.
- `make check-guix`: `67 passed, 0 failed`, `check-guix: ok no-git`,
  `test: ran 2, passed 2, failed 0, hung 0`, `check-guix: ALL CHECKS PASSED`.
- `make check-test-fails`, both in the container and on the host:
  `make test failed, as it must, in all 8 cases`.

The review had reported `make check-guix` failing with `FAILED check-pins` and `FAILED test`
there, and `check-test-fails` failing every case on the host. A first attempt at this setup ran
`git add -A` after recording the gitlink, which staged the submodule's deletion. Every check then
failed for that reason, so that run is discarded.

### Review findings left open

- **`check-suites` refuses a suite that starts with a `#!` script line.** It fails closed, with
  `it cannot be read as data`, and suites run through make never need one.
- **`capture-command` shares one counter across threads, and writes to predictable `/tmp` names.**
  That is safe while every suite is single-threaded. It must be fixed before the first threaded
  suite uses it, which is expected with M3's engine.
- **A red suite makes `make check-guix` red.** The self-test runs `make test`. Its line, `FAILED
  test`, names the cause, so a broken container and a failing suite stay distinguishable.
