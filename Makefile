# chez-curl
#
# On a Guix host, run targets through the container (ADR-0006):
#   scripts/guix-env make <target>

# The Chez binary. In the container, scripts/guix-env-enter exports the
# profile's real `scheme` binary. Elsewhere it is `scheme` on PATH, or else
# `chez`, the name Homebrew installs it under on macOS. Exported, so that a
# suite which spawns Chez (tests/test-library-loading.sps) spawns this one.
CHEZ ?= $(or $(if $(shell command -v scheme 2>/dev/null),scheme),$(if $(shell command -v chez 2>/dev/null),chez),scheme)
export CHEZ

# Node, for the test origin and the byte probe, tests/origin.mjs and
# tests/wire-probe.mjs (ADR-0005): the node on PATH unless NODE names another.
# Exported, so that (curl-testing) spawns this one, and make test and
# test-memory name it in require-tools.
NODE ?= node
export NODE

# openssl, which makes the test origin's TLS material, tests/make-test-pki.sh,
# and checks its certificates (ADR-0005, amended): the openssl on PATH unless
# OPENSSL names another, such as LibreSSL's. Exported, so that the script and
# (curl-testing) run this one, and make test and test-memory name it in
# require-tools.
OPENSSL ?= openssl
export OPENSSL

# The make target to name in a missing-tool hint (scripts/require-tools):
# what the user typed, $(MAKECMDGOALS), or, when that is empty, the
# recipe's own target, $@. Recursively expanded (=, not :=), so each
# reference picks up whichever recipe is running it.
GOAL = $(strip $(if $(MAKECMDGOALS),$(MAKECMDGOALS),$@))

# chez-srfi, which supplies SRFI-64, is a git submodule pinned in Akku.lock
# (ADR-0015). `make deps` links it into SRFI_LIBS, for Chez's library path
# (LIBDIRS) to name.
SRFI_SRC  := vendor/chez-srfi
SRFI_LIBS := build/scheme-libs

# Chez's library path for the suites: src/ holds chez-curl's own libraries,
# (curl private ...) among them, and tests/ holds (curl-testing).
LIBDIRS := src:tests:$(SRFI_LIBS)

# Every suite, in one order everywhere: make 3.82 to 4.2 leave $(wildcard)
# unsorted.
SUITES := $(sort $(wildcard tests/test-*.sps))

# Seconds a suite may run before timeout kills it and make test names it
# HUNG.
TEST_TIMEOUT ?= 300

# GNU timeout. Homebrew's coreutils installs it as gtimeout on macOS.
TIMEOUT ?= $(or $(shell command -v timeout 2>/dev/null),$(shell command -v gtimeout 2>/dev/null),timeout)

# The memory gate (ADR-0014): Valgrind, and the seconds a suite may run
# under it before timeout kills it and make test-memory names it HUNG.
# Valgrind runs 10 to 50 times slower than Chez alone.
VALGRIND ?= valgrind
MEMORY_TIMEOUT ?= 3600

# The suites make test-memory runs: every suite, unless a run names others.
MEMORY_SUITES ?= $(SUITES)

# Where make test-memory writes each suite's logs: <suite>.log, the suite's
# own output, and <suite>.valgrind, Valgrind's.
MEMORY_LOGS := build/memory

# The gate's one suppression, for the block Guix's glibc loses when libcurl
# loads p11-kit (ADR-0014, amended 2026-10-16). make test-memory hands it to
# Valgrind only in a Guix environment: CI, on Ubuntu, passes none. override:
# test-memory also allows the file it names, so no make command line, nor
# make -e, may name another (measured: one naming a file that matches every
# one-byte invalid write passed the overrun plant).
override MEMORY_SUPPRESSION_FILE := tests/guix-glibc-locpath.supp

# One physical line: check-help reads it with awk, and fails if it ends in
# a backslash.
.PHONY: help check-help check-guix check-guix-inside deps check-pins build dev check-dev test check-suites check-seam check-floors check-nothreads check-test-fails check-variadic test-memory check-memory-gate clean check-clean

.DEFAULT_GOAL := help

# The name column is as wide as the longest target's name.
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / \
	  { n++; name[n] = $$1; text[n] = $$2; if (length($$1) > width) width = length($$1) } \
	  END { format = "  \033[36m%-" width "s\033[0m %s\n"; \
	        for (i = 1; i <= n; i++) printf format, name[i], text[i] }' $(MAKEFILE_LIST)

# Reads what `make help` prints, colour codes stripped, so it checks the
# listing itself. Both directions: every .PHONY target is listed, and every
# listed target is in .PHONY. A listed target left out of .PHONY silently
# stops running once a file of its name exists.
check-help: ## Fail unless `make help` lists exactly the .PHONY targets
	@status=0; \
	if grep -qE '^\.PHONY:.*\\$$' Makefile; then \
	  echo "check-help: the .PHONY line ends in a backslash; keep it on one line" >&2; \
	  status=1; \
	fi; \
	help=$$($(MAKE) --no-print-directory help) || { \
	  echo "check-help: make help failed" >&2; \
	  exit 1; \
	}; \
	esc=$$(printf '\033'); \
	listed=$$(printf '%s\n' "$$help" | sed "s/$$esc\[[0-9;]*m//g" | awk '{ print $$1 }'); \
	phony=$$(awk '/^\.PHONY:/ { $$1 = ""; print }' Makefile); \
	for t in $$phony; do \
	  printf '%s\n' $$listed | grep -qxF "$$t" || { \
	    echo "check-help: make help does not list .PHONY target '$$t'; give it a '## ' description on its target line" >&2; \
	    status=1; \
	  }; \
	done; \
	for t in $$listed; do \
	  printf '%s\n' $$phony | grep -qxF "$$t" || { \
	    echo "check-help: make help lists '$$t', which is not in .PHONY" >&2; \
	    status=1; \
	  }; \
	done; \
	exit $$status

check-guix: ## Test scripts/guix-env on the host, then the toolchain inside the container
	@scripts/require-tools "$(GOAL)" guix
	@sh tests/guix-env-launcher.sh
	@scripts/guix-env make check-guix-inside

check-guix-inside: ## (inside the container) Assert the pinned toolchain, isolation and loopback-only network
	@CHEZ='$(CHEZ)' CC='$(CC)' sh scripts/guix-env-selftest

# Links vendor/chez-srfi into build/scheme-libs/srfi, and never fetches: the
# container has no network (ADR-0006), so an empty submodule is filled on the
# host. chez-srfi ships Akku's percent-encoded filenames (%3a64.sls) and Chez
# resolves (srfi :64) only from the decoded spelling (:64.sls), so every entry
# is linked under both and the submodule's own tree is left alone. It always
# relinks. `ln -sfn` replaces a link in place, and the -n is what stops it
# following an existing link to a directory into the submodule. A rerun
# changes nothing, and `set -e` keeps a failed link from hiding behind the
# loop's last iteration. Every path is quoted, since the checkout's may hold
# a space.
deps: ## Link vendor/chez-srfi into build/scheme-libs; never fetches
	@if [ ! -f $(SRFI_SRC)/%3a64.sls ]; then \
	  echo "deps: $(SRFI_SRC)/%3a64.sls not found, so the submodule is empty or missing. Run 'git submodule update --init $(SRFI_SRC)' on the host: make deps never fetches, and the container has no network." >&2; \
	  exit 1; \
	fi
	@mkdir -p $(SRFI_LIBS)/srfi
	@set -e; \
	src="$(abspath $(SRFI_SRC))"; dst="$(abspath $(SRFI_LIBS))/srfi"; \
	for f in "$$src"/*; do \
	  b=$$(basename "$$f"); \
	  ln -sfn "$$f" "$$dst/$$b"; \
	  d=$$(printf '%s' "$$b" | sed 's/%3a/:/g'); \
	  [ "$$d" = "$$b" ] || ln -sfn "$$f" "$$dst/$$d"; \
	done
	@echo "deps: $(SRFI_SRC) linked into $(SRFI_LIBS)/srfi"

# Three places name the chez-srfi commit, and nothing else keeps them equal:
# Akku.lock (what a consumer installs), the gitlink the superproject records
# (what a clone checks out) and the submodule's checkout (what the tests
# import). The gitlink and the checkout move separately: `git checkout` in the
# submodule moves the checkout, `git add` moves the gitlink, and `git
# submodule update` undoes the first, so each is read. The lock names a short
# commit (Akku's `akku.N.<short>`), so it is compared as a prefix, and a
# prefix shorter than seven digits is not read at all: an empty or one-digit
# one would match every commit. An empty or half-made submodule directory is
# no error to git, which answers there for the superproject, so the checkout
# counts only when git's toplevel for it is that directory itself. Read-only.
# It needs git, which the container does not have: run it on the host and in
# CI. `make test` does not run it.
check-pins: ## Fail unless Akku.lock, the gitlink and the checkout name one chez-srfi commit
	@scripts/require-tools "$(GOAL)" git
	@lock=$$(sed -n 's#.*/chez-srfi_[^"]*-akku\.[0-9]*\.\([a-f0-9]\{7,40\}\)_repack.*#\1#p' Akku.lock | head -n 1); \
	rec=$$(git ls-files -s -- $(SRFI_SRC) | awk '$$1 == "160000" && $$3 == 0 { print $$2 }'); \
	top=$$(git -C $(SRFI_SRC) rev-parse --show-toplevel 2>/dev/null); \
	want=$$(cd $(SRFI_SRC) 2>/dev/null && pwd -P); \
	fail=0; drift=0; \
	if [ -z "$$lock" ]; then \
	  echo "check-pins: could not read a chez-srfi commit from Akku.lock" >&2; \
	  exit 1; \
	fi; \
	if [ -z "$$rec" ]; then \
	  echo "check-pins: could not read the commit the superproject records for $(SRFI_SRC) (is it a git submodule, and is this a git checkout?)" >&2; \
	  fail=1; \
	else \
	  case "$$rec" in \
	    "$$lock"*) ;; \
	    *) echo "check-pins: PIN DRIFT: Akku.lock names $$lock, but the superproject records $$rec for $(SRFI_SRC)." >&2; \
	       fail=1; drift=1 ;; \
	  esac; \
	fi; \
	if [ -z "$$top" ] || [ "$$top" != "$$want" ]; then \
	  echo "check-pins: $(SRFI_SRC) is not checked out. Run 'git submodule update --init $(SRFI_SRC)' on the host." >&2; \
	  fail=1; \
	elif ! out=$$(git -C $(SRFI_SRC) rev-parse HEAD 2>/dev/null) || [ -z "$$out" ]; then \
	  echo "check-pins: could not read the commit checked out in $(SRFI_SRC)" >&2; \
	  fail=1; \
	else \
	  case "$$out" in \
	    "$$lock"*) ;; \
	    *) echo "check-pins: PIN DRIFT: Akku.lock names $$lock, but $(SRFI_SRC) is checked out at $$out." >&2; \
	       fail=1; drift=1 ;; \
	  esac; \
	fi; \
	if [ "$$drift" -eq 1 ]; then \
	  echo "check-pins: Bump the submodule and Akku.lock together (ADR-0015). To restore the recorded checkout, run 'git submodule update --init $(SRFI_SRC)' on the host." >&2; \
	fi; \
	if [ "$$fail" -eq 0 ]; then \
	  echo "check-pins: chez-srfi $$lock: Akku.lock, the recorded commit and the checkout agree"; \
	fi; \
	exit $$fail

# There is nothing to compile (ADR-0001). build loads libcurl as (curl)
# would, through tests/preflight.sps, and names it: its path and source,
# version, TLS backend, features and host. A refused libcurl fails it, with
# the reason, the path, the candidates checked and a remedy, and, when the
# refusal came after the version was read, that library's own report. make
# test does not depend on it.
build: ## Load libcurl as (curl) would and name it; fail with the reason when it is refused
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --libdirs src --program tests/preflight.sps

# A REPL for working on chez-curl by hand. make build's preflight runs first
# and names the libcurl it loaded, and a refused libcurl stops it there, with
# the reason. The REPL's library path is the suites' own, LIBDIRS, so (curl),
# (curl private ...), (curl-testing) and (srfi :64) all import. On a Guix
# host, run it as `scripts/guix-env make dev`.
dev: deps build ## Start a REPL with (curl) and the suites' libraries on its library path, after make build
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --libdirs $(LIBDIRS)

# Runs make dev through make, in a fresh copy of the tree with no build/, with
# forms piped into its REPL. It requires build's report, the banner, and two
# lines those forms print only once (curl), (curl-testing) and (srfi :64) have
# imported, naming the version, path and source build named. With
# CHEZ_CURL_LIBCURL naming no file, make dev must fail with build's refusal
# before any REPL starts (tests/check-dev.sh).
check-dev: ## Fail unless make dev runs build, then a REPL that imports (curl) and the suites' libraries; a refused libcurl must stop it
	@scripts/require-tools "$(GOAL)" $(TIMEOUT) $(CHEZ)
	@MAKE='$(MAKE)' TIMEOUT='$(TIMEOUT)' sh tests/check-dev.sh

# Runs every suite, in order, each under timeout, and goes on after a
# failure. One line names each suite's outcome: pass, FAIL with its exit
# status, or HUNG when timeout killed it (exit 124). It fails if any suite
# failed or hung, or if none matched. --foreground keeps a suite in make's
# process group, so Ctrl-C at a terminal reaches it at once, and does not
# wait out the timeout. `make check-test-fails` proves the loop fails. The
# checks come first: check-help, check-suites, check-seam and check-floors
# each stop it.
test: deps check-help check-suites check-seam check-floors ## Run every tests/test-*.sps under timeout; fail if one fails or hangs, or none exists
	@scripts/require-tools "$(GOAL)" $(TIMEOUT) $(CHEZ) $(NODE) $(OPENSSL)
	@if [ -z "$(SUITES)" ]; then \
	  echo "test: no suites: nothing matches tests/test-*.sps" >&2; \
	  exit 1; \
	fi; \
	passed=0; failed=0; hung=0; \
	for t in $(SUITES); do \
	  echo "=== $$t"; \
	  $(TIMEOUT) --foreground $(TEST_TIMEOUT) $(CHEZ) --libdirs $(LIBDIRS) --program $$t; \
	  rc=$$?; \
	  if [ $$rc -eq 0 ]; then \
	    echo "test: pass $$t"; passed=$$((passed + 1)); \
	  elif [ $$rc -eq 124 ]; then \
	    echo "test: HUNG $$t (no exit within $(TEST_TIMEOUT)s)"; hung=$$((hung + 1)); \
	  else \
	    echo "test: FAIL $$t (exit $$rc)"; failed=$$((failed + 1)); \
	  fi; \
	done; \
	echo "test: ran $$((passed + failed + hung)), passed $$passed, failed $$failed, hung $$hung"; \
	[ $$failed -eq 0 ] && [ $$hung -eq 0 ]

# Reads every suite as data and fails unless each one's last datum is the
# shared exit form, (curl-testing)'s suite-exit-form, and no datum before it
# holds an exit form but (exit 1), naming each suite that breaks either rule
# (tests/check-suites.sps). With no suite it passes: make test fails that case
# itself.
check-suites: deps ## Fail unless every tests/test-*.sps ends with the shared exit form
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/check-suites.sps $(SUITES)

# Reads every src/**/*.sls as data, evaluating nothing, and fails, naming the
# file and the import, when a (curl ...) library imports an (http-client ...)
# library, or an (http-client ...) library imports a (curl ...) library that is
# not public: only (curl) is (ADR-0007, tests/check-seam.sps). A library may
# import only allowlists: the (rnrs ...) libraries but (rnrs eval), (only
# (chezscheme) name ...) with each name in allowed-chez-names, and (curl ...)
# and (http-client ...) libraries. A name in library-only-chez-names may be
# imported only by the libraries listed with it: define-ftype by (curl private
# layouts), foreign-alloc and foreign-free by (curl private memory), and
# foreign-procedure by (curl private native). No library may export a name it
# imports from (chezscheme). Any other import fails, (scheme) and
# (chezscheme csv7) included, as does a library in neither family, a file Chez
# could load as a library but this check does not read (.ss, .scm, .sch, .so,
# ...), no library under src/, and a file it cannot read as data. It skips a
# .# dangling symbolic link, Emacs's lock file, and reads any other .# name.
# tests/test-check-seam.sps runs it on a fixture tree for each rule. It needs
# no deps: it imports only (rnrs) and a few of Chez's own bindings.
check-seam: ## Fail unless the imports keep (curl ...) and (http-client ...) apart, with (curl) the only way across
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --program tests/check-seam.sps src

# packaging/floors.sexp is the one file that writes the Chez, libcurl and Node
# floors. This reads it, README.org and every file under .github/workflows as
# data and fails, naming each problem, when the floors file is not exactly the
# datum (floors) describes, when README.org's "** Requirements" section does
# not hold the three list lines the file calls for, or when any line of a
# workflow file writes either floor's version, names CHEZ_VERSION or
# CURL_FLOOR_VERSION, names node-version, in any case, in any form but
# "node-version: ${{ steps.ID.outputs.NAME }}", or holds a double-quoted key
# with an escape, which YAML reads and this check does not: CI's build scripts
# read the floors from the file through scripts/ci/floor.sh, and so does the
# step that gives setup-node its version (tests/floors.sls,
# tests/check-floors.sps).
# tests/test-check-floors.sps holds each rule on texts and fixtures. The
# Scheme code that enforces a floor is held to the file by tests/test-verify.sps
# and tests/test-require-threaded.sps, which read it. It imports only (rnrs),
# a few of Chez's own bindings and (floors), so it needs no deps.
check-floors: ## Fail unless README.org and the CI workflows state the floors in packaging/floors.sexp
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --libdirs tests --program tests/check-floors.sps packaging/floors.sexp README.org .github/workflows

# Imports every public library under src/ (a library whose name has no private
# part) and requires each import to be refused, by name, as
# (curl private require-threaded) refuses a Chez that is not threaded: a syntax
# violation from chez-curl, whose message starts with the refusal's marker. It
# fails if it finds no public library, and names each one that loaded or raised
# something else (tests/check-nothreads.sps). tests/test-check-nothreads.sps
# holds each rule on a fixture tree. On the threaded Chez that make test runs,
# every import loads, so this FAILS there, naming (curl): that is its red run,
# and why make test does not run it. CI runs it on a Chez built with
# --nothreads (.github/workflows/ci.yml). It imports only (rnrs) and a few of
# Chez's own bindings, so it needs no deps.
check-nothreads: ## Fail unless every public library refuses to import, by name, on this Chez; CI runs it on a --nothreads Chez
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --program tests/check-nothreads.sps src

# Plants bad suites, a leaking one among them, a bad import across the seam
# and a README that disagrees with the floors file, one at a time, in a copy
# of the tree, and requires make test to fail on each by name. tests/check-test-fails.sh lists the
# plants. The copy has no .git, so nothing in it runs git.
check-test-fails: ## Plant bad suites, none at all, a bad import and a stale README, in a copy; make test must fail on each, by name
	@scripts/require-tools "$(GOAL)" $(TIMEOUT) $(CHEZ)
	@MAKE='$(MAKE)' TIMEOUT='$(TIMEOUT)' CHEZ='$(CHEZ)' sh tests/check-test-fails.sh

# Removes (__varargs_after 2) in a copy of src/, tests/ and
# .plans/decisions/, five ways, each from the unchanged
# src/curl/private/native.sls: from bind-variadic's template, then from
# each of its four uses alone, bound through bind-required instead. On
# every platform, tests/test-collect-safe.sps must fail on each, naming
# exactly the mutated bindings. On Apple arm64, Chez's machine type
# arm64osx or tarm64osx, tests/test-variadic.sps must fail too: on a setopt
# use alone by name, exiting 1, with a failing test through that binding;
# on the template, or getinfo alone, by a named test or by dying. Anywhere
# else it runs that suite on each mutant and reports what it did: x86-64
# and Linux arm64 pass variadic arguments as they pass named ones, so only
# Apple arm64 can show a binding without the convention failing
# (ADR-0001). The unchanged copy must pass both first.
# tests/check-variadic.sh holds the steps. The copy has no .git.
check-variadic: deps ## Remove (__varargs_after 2) from bind-variadic's template, then from each use alone, in a copy; test-collect-safe must fail on each, and on Apple arm64 test-variadic too
	@scripts/require-tools "$(GOAL)" $(TIMEOUT) $(CHEZ)
	@TIMEOUT='$(TIMEOUT)' CHEZ='$(CHEZ)' TEST_TIMEOUT='$(TEST_TIMEOUT)' sh tests/check-variadic.sh

# Runs every MEMORY_SUITES suite under Valgrind, in order, each under
# timeout, and goes on after a failure (ADR-0014). timeout wraps Valgrind
# and never sits between it and Chez: Valgrind checks only the command it
# is handed. A suite's own output goes to build/memory/<suite>.log, and
# Valgrind writes its report to build/memory/<suite>.valgrind (--log-file),
# where nothing the suite prints can reach. Two suites with one name would
# share both, so test-memory refuses them. One line names each suite's
# outcome: pass, FAIL with its exit status (9 is Valgrind's: an error, or a
# definite leak), or HUNG when timeout killed it (exit 124).
#
# Valgrind runs with -v, and a suite that exits 0 passes only when its
# Valgrind log, and nothing else, shows what Valgrind checked, else it
# FAILs, naming each thing wrong. One awk program reads the log, and prints
# the things wrong, or "ok" alone when it finds none: a suite passes only
# on that line and awk's exit status 0, so an awk that fails, or prints
# nothing, FAILs it, naming the check. It checks that:
#   - the log exists: each run removes the one before;
#   - Valgrind's "Command:" line is CHEZ, the libraries and the suite, so
#     Valgrind ran this suite;
#   - its "Valgrind options:" list is exactly the options test-memory
#     hands it, in order: -v, --command-line-only=yes, the suite's
#     --log-file, ADR-0014's four flags, and, in a Guix environment, the
#     suppression. So nothing VALGRIND, CHEZ or a stand-in for Valgrind
#     adds, drops or changes (measured: --undef-value-errors=no through
#     VALGRIND hid an undefined-value plant, and a dropped
#     --leak-check=full hid the leak plant) gets past it. make
#     check-memory-gate holds the options themselves to ADR-0014's;
#   - the first program it read is the file CHEZ names, so it ran Chez
#     itself: a CHEZ that is a script runs the shell under Valgrind, and
#     Chez outside it;
#   - it reported "ERROR SUMMARY: 0 errors from 0 contexts": a program that
#     execs away from Valgrind, or a CHEZ script that execs Chez, exits 0
#     with no report at all;
#   - the suppressions files it read are exactly its own default.supp and,
#     in a Guix environment, MEMORY_SUPPRESSION_FILE. Its own default.supp
#     is the one it names in a run on true, with VALGRIND_LIB unset;
#   - in a Guix environment, it suppressed exactly one block if it read
#     libp11-kit, which libcurl loads, and none if not: the entry matches
#     every block lost under newlocale, and each call that searches the
#     locale path loses one (measured: six from one program), so only the
#     count keeps it to the one block p11-kit's constructor loses. Its
#     lower bound fails closed, and no plant can fail it: every run that
#     loads libp11-kit loses the block.
# A FAIL also prints, from Valgrind's log, its first error, the definite
# loss, the suppressed total and its error summary, and, unless the exit
# was Valgrind's, the suite's last lines, so a CI log says why. It fails if
# any suite failed or hung, or if none was named.
#
# Valgrind also takes options and files that its command line does not
# show, and one of them can hide a leak (measured: a suppression in
# VALGRIND_OPTS, in a .valgrindrc, or in the default.supp of a directory
# VALGRIND_LIB names, each hid the planted one). So it refuses to run while
# any VALGRIND_ variable is set (Valgrind reads VALGRIND_OPTS, VALGRIND_LIB
# and VALGRIND_LAUNCHER) or a .valgrindrc exists in $HOME or here, and
# hands Valgrind --command-line-only=yes, so that no .valgrindrc a suite
# writes reaches the next. `make check-memory-gate` proves each rule fails.
test-memory: deps ## Run every MEMORY_SUITES suite under Valgrind; fail on any error or definite leak, a hang, or no suite
	@scripts/require-tools "$(GOAL)" $(firstword $(VALGRIND)) $(TIMEOUT) $(CHEZ) $(NODE) $(OPENSSL)
	@if [ -z "$(strip $(MEMORY_SUITES))" ]; then \
	  echo "test-memory: no suites: MEMORY_SUITES is empty" >&2; \
	  exit 1; \
	fi; \
	refused=0; \
	for v in $$(env | sed -n 's/^\(VALGRIND_[A-Za-z0-9_]*\)=.*/\1/p'); do \
	  case $$v in \
	    VALGRIND_OPTS) why="Valgrind would add it to the gate's options" ;; \
	    VALGRIND_LIB) why="Valgrind would take its tool, its preloads and its default.supp from there" ;; \
	    *) why="Valgrind reads its VALGRIND_ variables, and no command line shows them" ;; \
	  esac; \
	  echo "test-memory: $$v is set ($$(printenv $$v)): $$why; unset it (ADR-0014)" >&2; \
	  refused=1; \
	done; \
	for rc in $${HOME:+"$$HOME/.valgrindrc"} ./.valgrindrc; do \
	  if [ -e "$$rc" ]; then \
	    echo "test-memory: $$rc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)" >&2; \
	    refused=1; \
	  fi; \
	done; \
	seen=; \
	for t in $(MEMORY_SUITES); do \
	  name=$$(basename "$$t" .sps); \
	  for u in $$seen; do \
	    if [ "$$(basename "$$u" .sps)" = "$$name" ]; then \
	      echo "test-memory: $$u and $$t share the name $$name, so they would share $(MEMORY_LOGS)/$$name.log and $(MEMORY_LOGS)/$$name.valgrind; rename one (ADR-0014)" >&2; \
	      refused=1; \
	    fi; \
	  done; \
	  seen="$$seen $$t"; \
	done; \
	[ $$refused -eq 0 ] || exit 1; \
	vgdefault=$$(env -u VALGRIND_LIB $(firstword $(VALGRIND)) -v --command-line-only=yes true 2>&1 | sed -n 's/^--[0-9]*-- Reading suppressions file: //p'); \
	case $$vgdefault in \
	  /*/default.supp) ;; \
	  *) vgdefault=; ;; \
	esac; \
	if [ -z "$$vgdefault" ] || [ "$$(printf '%s\n' "$$vgdefault" | wc -l)" -ne 1 ]; then \
	  echo "test-memory: $(firstword $(VALGRIND)) -v, run on true, named no one default.supp of its own" >&2; \
	  exit 1; \
	fi; \
	allowed=$$vgdefault; \
	if [ -n "$(GUIX_ENVIRONMENT)" ]; then allowed="$(MEMORY_SUPPRESSION_FILE), $$allowed"; fi; \
	chez=$$(readlink -f "$$(command -v $(CHEZ))"); \
	mkdir -p $(MEMORY_LOGS); \
	passed=0; failed=0; hung=0; \
	for t in $(MEMORY_SUITES); do \
	  name=$$(basename "$$t" .sps); \
	  log=$(MEMORY_LOGS)/$$name.log; \
	  vlog=$(MEMORY_LOGS)/$$name.valgrind; \
	  rm -f "$$log" "$$vlog"; \
	  echo "=== $$t"; \
	  set -- -v --command-line-only=yes "--log-file=$$vlog" --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $(if $(GUIX_ENVIRONMENT),--suppressions=$(MEMORY_SUPPRESSION_FILE)); \
	  $(TIMEOUT) --foreground $(MEMORY_TIMEOUT) $(VALGRIND) "$$@" $(CHEZ) --libdirs $(LIBDIRS) --program $$t >"$$log" 2>&1; \
	  rc=$$?; \
	  why=; \
	  if [ $$rc -eq 0 ] && [ ! -f "$$vlog" ]; then \
	    why="Valgrind wrote no log, $$vlog"; \
	  elif [ $$rc -eq 0 ]; then \
	    evidence=$$(options=$$(printf '%s\n' "$$@") awk -v cmd="$(CHEZ) --libdirs $(LIBDIRS) --program $$t" -v chez="$$chez" -v allowed="$$allowed" -v guix="$(GUIX_ENVIRONMENT)" \
	      'pid == "" && /^==[0-9]+== Command: / { pid = $$0; sub(/^==/, "", pid); sub(/==.*/, "", pid); \
	          got = $$0; sub(/^==[0-9]+== Command: /, "", got); syms = "--" pid "-- Reading syms from "; \
	          supps = "--" pid "-- Reading suppressions file: "; mine = "==" pid "== "; \
	          head = "--" pid "-- Valgrind options:"; option = "--" pid "--    "; next } \
	        pid == "" { next } \
	        listing && index($$0, option) == 1 { opts[++nopts] = substr($$0, length(option) + 1); next } \
	        listing { listing = 0; listed = 1 } \
	        !listed && $$0 == head { listing = 1; next } \
	        index($$0, syms) == 1 && ran == "" { ran = substr($$0, length(syms) + 1) } \
	        index($$0, syms) == 1 && $$0 ~ /\/libp11-kit\.so[^\/]*$$/ { p11 = 1 } \
	        index($$0, supps) == 1 { f = substr($$0, length(supps) + 1); read = (read == "" ? f : read ", " f) } \
	        index($$0, mine "ERROR SUMMARY: ") == 1 { summary = substr($$0, length(mine) + 1) } \
	        index($$0, mine) == 1 && $$0 ~ /== +suppressed: [0-9,]+ bytes in [0-9,]+ blocks$$/ { \
	          blocks = $$0; sub(/ blocks$$/, "", blocks); sub(/.* in /, "", blocks); gsub(/,/, "", blocks) } \
	        END { if (pid == "") { print "the log has no Valgrind \"Command:\" line"; exit } \
	          if (got != cmd) why[++n] = "Valgrind\047s Command: line is \"" got "\", not \"" cmd "\""; \
	          nwant = split(ENVIRON["options"], want, "\n"); same = (nopts == nwant); \
	          for (i = 1; i <= nwant; i++) if (opts[i] != want[i]) same = 0; \
	          if (!same) { g = ""; for (i = 1; i <= nopts; i++) g = g (i > 1 ? " " : "") opts[i]; \
	            w = ""; for (i = 1; i <= nwant; i++) w = w (i > 1 ? " " : "") want[i]; \
	            why[++n] = "Valgrind\047s options are [" g "], not the gate\047s [" w "]" } \
	          if (ran == "") why[++n] = "the log has no \"Reading syms from\" line, so it does not show what Valgrind ran"; \
	          else if (ran != chez) why[++n] = "Valgrind ran " ran ", not " chez ", the file CHEZ names"; \
	          if (summary !~ /^ERROR SUMMARY: 0 errors from 0 contexts( |$$)/) \
	            why[++n] = "Valgrind reported no \"ERROR SUMMARY: 0 errors from 0 contexts\""; \
	          if (read != allowed) why[++n] = "Valgrind read the suppressions files [" read "], and the gate allows exactly [" allowed "]"; \
	          if (guix != "" && p11 && blocks + 0 != 1) \
	            why[++n] = "Valgrind suppressed " (blocks + 0) " blocks, and guix-glibc-locpath covers exactly one, lost when libp11-kit loads"; \
	          if (guix != "" && !p11 && blocks + 0 != 0) \
	            why[++n] = "Valgrind suppressed " (blocks + 0) " blocks, and guix-glibc-locpath covers none in a run that loads no libp11-kit"; \
	          for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "; " : ""), why[i]; \
	          if (n) print ""; else print "ok" }' "$$vlog"); \
	    checked=$$?; \
	    if [ $$checked -ne 0 ]; then \
	      why="the evidence check (awk) exited $$checked"; \
	    elif [ -z "$$evidence" ]; then \
	      why='the evidence check (awk) printed no "ok" line'; \
	    elif [ "$$evidence" != ok ]; then \
	      why=$$evidence; \
	    fi; \
	  fi; \
	  if [ $$rc -eq 0 ] && [ -z "$$why" ]; then \
	    echo "test-memory: pass $$t"; passed=$$((passed + 1)); \
	  elif [ $$rc -eq 124 ]; then \
	    echo "test-memory: HUNG $$t (no exit within $(MEMORY_TIMEOUT)s)"; hung=$$((hung + 1)); \
	  else \
	    if [ $$rc -eq 0 ]; then \
	      echo "test-memory: FAIL $$t (exit 0, but $$why)"; \
	    elif [ $$rc -eq 9 ]; then \
	      echo "test-memory: FAIL $$t (exit 9, Valgrind's: an error or a definite leak)"; \
	    else \
	      echo "test-memory: FAIL $$t (exit $$rc)"; \
	    fi; \
	    failed=$$((failed + 1)); \
	    echo "  log: $$log"; \
	    echo "  Valgrind's log: $$vlog"; \
	    if [ ! -f "$$vlog" ]; then echo "  (Valgrind wrote no log)"; else \
	    awk '/^==[0-9]+== Command: / { body = 1; next } \
	      !body || !/^==[0-9]+==/ { next } \
	      { line = $$0; sub(/^==[0-9]+== ?/, "", line) } \
	      line == "" { if (inerr) { inerr = 0; done = 1 }; cand = ""; next } \
	      !done && !inerr && cand != "" && line ~ /^ +at 0x/ { inerr = 1; first[++n] = cand } \
	      inerr && n < 16 { first[++n] = $$0 } \
	      !inerr { cand = (line ~ /^[^ ]/) ? $$0 : "" } \
	      line ~ /^ *definitely lost: / { lost = $$0 } \
	      line ~ /^ *suppressed: / { hidden = $$0 } \
	      line ~ /^ERROR SUMMARY: / { summary = $$0 } \
	      END { for (i = 1; i <= n; i++) print "  " first[i]; \
	            if (lost != "") print "  " lost; \
	            if (hidden != "") print "  " hidden; \
	            if (summary != "") print "  " summary; \
	            else print "  (the log holds no Valgrind ERROR SUMMARY)" }' "$$vlog"; \
	    fi; \
	    if [ $$rc -ne 9 ]; then \
	      tail -n 10 "$$log" | sed 's/^/  | /'; \
	    fi; \
	  fi; \
	done; \
	echo "test-memory: ran $$((passed + failed + hung)), passed $$passed, failed $$failed, hung $$hung"; \
	[ $$failed -eq 0 ] && [ $$hung -eq 0 ]

# Plants a heap overrun and a definite leak (tests/memory-plant-*.sps) and
# requires make test-memory to fail on each, by name, with Valgrind's own
# report. It holds the one suppression to its entry and, in a Guix
# environment, requires a run that loads libcurl to use it on one block and
# fail without it, and a block hidden under it in any other run, or a
# second one, to fail the suite. It requires the commands handed to
# Valgrind to carry the suppression only when GUIX_ENVIRONMENT is set, and
# test-memory to name a hang and refuse no suite. It plants each source of
# options test-memory's command line does not show, each in a copy, and
# requires test-memory to refuse it; a suppressions file the gate does not
# pass, and requires it named; a run with no evidence that Valgrind
# checked Chez on the suite, and requires it to fail; an option added,
# dropped, changed or moved, each hiding a plant where it can, and
# requires it named; a suite that forges Valgrind's lines, and requires
# them unread; and an awk that fails, or prints no "ok", and requires a
# clean program to fail, naming the evidence check.
# tests/check-memory-gate.sh lists the cases. CI runs it before
# test-memory (ADR-0014).
check-memory-gate: ## Plant a heap overrun and a leak; make test-memory must fail on each, by name, and its one suppression must hold
	@scripts/require-tools "$(GOAL)" $(firstword $(VALGRIND)) $(TIMEOUT) $(CHEZ)
	@MAKE='$(MAKE)' TIMEOUT='$(TIMEOUT)' CHEZ='$(CHEZ)' VALGRIND='$(VALGRIND)' LIBDIRS='$(LIBDIRS)' sh tests/check-memory-gate.sh

# Removes build/, and nothing else: make deps' links (the links, never what
# they name, since rm does not follow a link), the memory gate's logs and
# every check's scratch. The path is written out, not a variable, so no make
# command line can point it elsewhere. With no build/, it passes.
clean: ## Remove build/, and nothing else
	rm -rf build

# Runs make clean in a copy of the tree, after make deps and a few planted
# files and links out of build/, and requires build/ gone, every other path
# unchanged, no link followed, a second make clean to pass, and make deps to
# work after it (tests/check-clean.sh).
check-clean: ## Fail unless make clean, in a copy, removes build/, changes nothing else, follows no link, and can run twice
	@MAKE='$(MAKE)' sh tests/check-clean.sh
