# chez-curl
#
# On a Guix host, run targets through the container (ADR-0006):
#   scripts/guix-env make <target>

# The Chez binary. In the container, scripts/guix-env-enter exports the
# profile's real `scheme` binary. Exported, so that a suite which spawns
# Chez (tests/test-library-loading.sps) spawns this one.
CHEZ ?= scheme
export CHEZ

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

# One physical line: check-help reads it with awk, and fails if it ends in
# a backslash.
.PHONY: help check-help check-guix check-guix-inside deps check-pins build test check-suites check-seam check-test-fails

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

# Runs every suite, in order, each under timeout, and goes on after a
# failure. One line names each suite's outcome: pass, FAIL with its exit
# status, or HUNG when timeout killed it (exit 124). It fails if any suite
# failed or hung, or if none matched. --foreground keeps a suite in make's
# process group, so Ctrl-C at a terminal reaches it at once, and does not
# wait out the timeout. `make check-test-fails` proves the loop fails. The
# checks come first: check-help, check-suites and check-seam each stop it.
test: deps check-help check-suites check-seam ## Run every tests/test-*.sps under timeout; fail if one fails or hangs, or none exists
	@scripts/require-tools "$(GOAL)" $(TIMEOUT) $(CHEZ)
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
# and (http-client ...) libraries. Any other import fails, (scheme) and
# (chezscheme csv7) included, as does a library in neither family, a file Chez
# could load as a library but this check does not read (.ss, .scm, .sch, .so,
# ...), no library under src/, and a file it cannot read as data. It skips a
# .# dangling symbolic link, Emacs's lock file, and reads any other .# name.
# tests/test-check-seam.sps runs it on a fixture tree for each rule. It needs
# no deps: it imports only (rnrs) and a few of Chez's own bindings.
check-seam: ## Fail unless the imports keep (curl ...) and (http-client ...) apart, with (curl) the only way across
	@scripts/require-tools "$(GOAL)" $(CHEZ)
	@$(CHEZ) --program tests/check-seam.sps src

# Plants bad suites, and a bad import across the seam, one at a time, in a copy
# of the tree, and requires make test to fail on each by name.
# tests/check-test-fails.sh lists the plants. The copy has no .git, so nothing
# in it runs git.
check-test-fails: ## Plant bad suites, none at all and a bad import, in a copy; make test must fail on each, by name
	@scripts/require-tools "$(GOAL)" $(TIMEOUT) $(CHEZ)
	@MAKE='$(MAKE)' TIMEOUT='$(TIMEOUT)' CHEZ='$(CHEZ)' sh tests/check-test-fails.sh
