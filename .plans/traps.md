# Traps: the full accounts

`AGENTS.md` carries the one-line rule for each trap; this file keeps the
incident behind it. Most came from chez-curl's sibling repositories,
chez-cmark-gfm and chez-libuv, where each shipped a passing test or a
working-looking build that was wrong. None is obvious from reading the code.
Each account names the repository it happened in. Add an incident under its
trap, newest last, naming the repository.

## Why "prefer a check to a comment"

This is not abstract. The rule about empty tests was already written down
in `AGENTS.md`, and five tests violating it shipped anyway; it only started
holding once it carried an executable standard. A Makefile comment requiring
the `chez-srfi` submodule and `Akku.lock` to name the same commit was
violated *in the same commit that introduced it*, and only became true once
it was `make check-pins`. When a comment is load-bearing, that is the signal
it should not be a comment. (chez-cmark-gfm)

## Tests

* **`0` is truthy in Scheme, and `guard` returns the body's value when nothing
  raises.** So `(test-assert "…" (guard (e ((pred e) #t) (#t #f)) (accessor x)))`
  passes even when `accessor` never raises — freed pointer fields are zeroed, and
  `0` satisfies `test-assert`. Assert on *what was raised*, compared against an
  expected value, with a distinct sentinel for the no-raise case. Three tests
  guarding the liveness mechanism passed against code with that mechanism deleted.
  (chez-cmark-gfm and chez-libuv)
* **SRFI-64 turns any exception in a test's *actual* expression into `#f`**
  (`%test-evaluate-with-catch` in `vendor/chez-srfi/%3a64/testing-impl.scm`,
  which the R6RS branch defines as `(guard (ex (else #F)) …)`). An assertion
  expecting `#f` therefore passes when the code under test raises. Never make
  `#f` the expected value of an assertion that can raise — use a sentinel the
  failure path cannot produce: `'agree (or (compare …) 'agree)`. A whole
  differential leg reported 79/79 green against a `cmark-gfm` that crashed on
  every fixture, because the helper's raise on a non-zero exit was swallowed.
  (chez-cmark-gfm and chez-libuv)
* **Every `tests/test-*.sps` must end with its own `(exit …)`.** SRFI-64 does not set
  a process exit status, so a suite missing that line always reports success and
  `make test` stays green through real failures. Anything appended *after* it is
  dead code — a sabotage test added that way silently never runs.
  (chez-cmark-gfm and chez-libuv)
* **Chez evaluates argument expressions right-to-left in compiled library code**,
  left-to-right when interpreted. Never let an assertion's meaning depend on
  which argument runs first: one named "rejected before anything is allocated"
  was in fact satisfied by the *last* argument's accessor raising.
  (chez-cmark-gfm and chez-libuv)
* **An assertion passes whenever some *other* rule can produce the value it
  expects.** `AGENTS.md` gives the rule; here is what it looked like four times
  in one stage of chez-cmark-gfm, each one green and each one empty. A
  `*COMMENT*`-in-`blockquote` fixture survived narrowing `block-comment-parents`
  to `'(*TOP*)`, because `blockquote` is also in `cr-before-close` and
  contributes the identical newline. An empty-URL assertion could not
  distinguish "empty routes to encoding" from "empty routes to rejection",
  because `percent-encode("")` and the rejection branch both yield `""`. A
  `contains?` probe for `"  indented\n"` still matched after the serializer was
  turned into a pretty-printer, because the injected indent lands immediately in
  front of the content's own two spaces — the substring survived the corruption
  it existed to detect. And a functional-update test cannot tell "carried from
  the argument" from "rebuilt from the default" while its base record holds the
  default for the field the update leaves alone; two of `sxml-options-with`'s
  three fields were unpinned that way. Assert the whole rendering rather than a
  substring, give the fixture a neighbour that cannot produce the same bytes by
  another route, and build the base out of non-default values. (chez-cmark-gfm)

  In chez-curl, the first run of `tests/guix-env-launcher.sh`, made before
  `scripts/guix-env-enter` existed, passed
  `T6 enter on host: points at scripts/guix-env`, a `grep -F "scripts/guix-env"`
  on stderr. The refusal it meant to find never ran. dash's own error,
  `cannot open …/scripts/guix-env-enter`, contains that string. The check now
  compares the whole of stderr. (chez-curl)

* **An exit status is taken modulo 256.** Chez's `(exit 256)` exits 0, and
  `(exit #t)` exits 1 (both measured at the pin). An exit form that reported its
  failure count would pass a suite with exactly 256 failures. `suite-exit-status`
  answers 0 or 1, never a count. (chez-curl)
* **A suite cannot vouch for the verdict it exits through.**
  `tests/test-curl-testing.sps` tests `suite-exit-status` and ends, like every
  suite, by exiting with it. In slice 2's first mutation run, `suite-exit-status`
  rewritten to ignore failures made that suite's own assertions fail, and then
  exit 0 through the broken verdict, so `make test` passed. The suite now exits 1
  on any failure of its own before it reaches the shared form. (chez-curl)

## Chez and the FFI

* **`foreign-procedure` resolves its entry point when the expression is evaluated,
  not when the procedure is first called.** Every binding must be defined after
  `load-shared-object`, which is why the load is written as a definition placed
  ahead of them in `native.sls`. Getting this wrong fails at *import* time, not at
  first use, so the error points nowhere near the mistake.
  (chez-cmark-gfm and chez-libuv)
* **Chez invokes an imported library's body only when a binding is
  *referenced*.** A probe that merely imports `(cmark gfm)` never forces
  `native.sls`'s body to run, so discovery never happens and
  `CHEZ_CMARK_GFM_LIBS` is never even read. A subprocess test written that way
  printed "unexpectedly imported" and exited 0 against libraries that cannot
  possibly load. Any test asserting something about load-time behaviour must
  *call* into the library — `tests/load-failed-probe.sps` calls
  `markdown->html` for exactly this reason. The same property is what makes
  `make check-purity` meaningful and what limits it. (chez-cmark-gfm)
* **Chez's `system` stops silently at a NUL.** The command goes to C as a
  NUL-terminated string, so whatever follows the NUL is dropped. Measured at the
  pin: `echo before`, then a NUL, then `> /tmp/nul-out` printed `before` to
  stdout and wrote no file. Redirections written after the command are the part
  that goes missing. `capture-command` refuses an argument holding a NUL rather
  than quote it. (chez-curl)

## Checks and environment

* **Deleting a subsystem disarms the checks built around it, and they stay
  green.** Release 2.0 removed the C shim and produced seven of these in one
  branch. `make check-purity` poisoned `CHEZ_CMARK_GFM_SHIM`, which the same
  release had replaced with `CHEZ_CMARK_GFM_LIBS` — nothing read the poison, so
  the gate passed unconditionally, including for regressions it existed to
  catch. A CI step asserted `! -e build/lib`, a path only the deleted shim rules
  ever created. `deps-info` branched on `$(HAVE_PKG)`; with the variable gone
  Make expanded it to empty and it reported "vendored" forever — a dangling Make
  variable is not an error. A CI job named for the vendored build passed while
  Homebrew's copy silently satisfied discovery first: green for the wrong
  reason, which is worse than red. And a `no-library` job grepped only for remedy
  text that the preflight's catch-all `else` prints for *any* condition, so it
  could not identify the failure it claimed to test.
  None of these fail, so no gate surfaces them. On any deletion, ask of every
  surviving check "what would make this fail now?" and treat "nothing" as a
  defect — then prove it by breaking the guarded thing and watching it go red.
  A passing CI job is evidence a check *ran*, not that it works.
  (chez-cmark-gfm)
* **An alias for the Chez binary must be neither a symlink nor a wrapper
  script.** A `chez` symlink to Guix's `scheme` aborts with `cannot find
  compatible chez.boot in search path "%x:%x/../lib/csv%v/%m:…"`: Chez
  derives its boot-file name from the invoked name. A wrapper script that
  `exec`s `scheme` fixes that and passes `make test`, but hides Chez from
  Valgrind: Valgrind traces the shell, the shell execs Chez uninstrumented,
  and `make test-memory` reported success over 21 suites without printing a
  single `ERROR SUMMARY`. Point `CHEZ` at the real binary, which is what
  chez-cmark-gfm's `manifest.scm` search path does. `make check-guix` asserts that
  `valgrind $CHEZ` prints an `ERROR SUMMARY`. (chez-cmark-gfm)

  In chez-curl, `scripts/guix-env-enter` exports `CHEZ` as the profile's
  `bin/scheme`. `make check-guix` asserts that it lies under the profile and
  is an ELF binary, and that `valgrind $CHEZ` prints an `ERROR SUMMARY`. Its
  mutation log records each wrapper and symlink failing. (chez-curl)
* **Anything between the memory tool and Chez gets checked instead of
  Chez.** Valgrind checks the command it is handed and does not follow an
  exec. `valgrind … timeout 900 scheme …` therefore checked timeout's two
  allocations while Chez ran natively and exited 0. chez-libuv's #14 wrote that shape,
  and the Linux gate stayed green from 2026-08-30 to 2026-09-27; v0.6.0 and
  v0.7.0 shipped on it. On macOS, `DYLD_INSERT_LIBRARIES` is lost two ways.
  SIP purges it when it launches a protected binary such as `/bin/sh`, and
  the ASan arm's `sh -c` never loaded ASan from v0.1 on. ASan's Darwin
  runtime also strips itself from the variable in whatever process it loads
  into, so under `timeout` it is `timeout` that gets ASan. Put wrappers
  *outside* the tool, and put the preload on the `chez` command itself.
  `make check-memory-gate` holds this: it plants defects and requires the
  real recipe to fail on each, with the tool's own report in the log. Watch
  it go red whenever you touch either `test-memory` recipe. (chez-libuv)
* **`guix shell --pure` does not stop a login shell from rebuilding `PATH`.**
  `--pure` clears the environment once, at entry. A later login shell
  (`bash -l`) re-sources `~/.bash_profile` and `~/.profile`. On the
  maintainer's machine those put `~/.guix-home/profile/bin` ahead of the
  environment, so `scheme` and `git` resolved to the host's copies while
  everything still passed.
  `scripts/guix-env` uses `--container`, whose `HOME` is empty; `make
  check-guix` asserts both that (`isolated-home`) and that a login shell
  runs the pinned binaries, comparing resolved paths. Do not assume you
  know how a tool builds its shell: when Claude Code ran inside the
  container (chez-cmark-gfm's ADR-0018, since withdrawn), its Bash tool put `/bin:/usr/bin`
  ahead of the profile, which a `bash -l` check never showed. `guix shell
  --check` diagnoses clobbering for a `--pure` shell. (chez-cmark-gfm)
* **`guix shell -m` serves its cached profile while the manifest is no newer
  than the cache.** In slice 2, a mutation driver copied the tree with `tar`,
  which keeps file times, and a baseline case flaked: a copy's changed
  `manifest.scm` was older than the cache entry for that path, so the container
  ran the old toolchain. Measured at the pin: once a profile with git was
  cached, a manifest without git, dated 2020, still got git. A manifest
  rewritten within a second of the cache was missed too. `touch` a manifest
  that a mutation changes. (chez-curl)
* **In an empty submodule directory, `git -C` answers for the superproject.**
  `git -C vendor/chez-srfi rev-parse HEAD` in an uninitialised submodule
  returns the superproject's HEAD, so `check-pins` reported pin drift against
  the wrong repository instead of saying the submodule was not checked out. The
  first fix tested for `vendor/chez-srfi/.git`, but the slice 2 review showed an
  empty `.git` directory passes that test and still gets the superproject's
  answer. `check-pins` now compares `git -C vendor/chez-srfi rev-parse
  --show-toplevel` with the directory itself. (chez-curl)
* **In a git worktree, `.git` points outside the working directory.** Its
  `.git` is a file naming a directory inside the main repository's `.git`, and
  the container shares only the working directory. Slice 2 first put git in
  the container so `make test` could run `check-pins`. Its review found that
  `make test` and `make check-guix` then failed in every worktree, with
  `fatal: not a git repository: (null)`, where slice 1 had worked. The container
  has no git again, and `check-pins` runs on the host and in CI. (chez-curl)
