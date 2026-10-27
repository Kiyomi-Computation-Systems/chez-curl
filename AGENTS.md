# AGENTS.md

## Project guidelines

### Architecture & portability

* Use the functional core / imperative shell pattern
* Follow the 12 Factor Apps philosophy
* Project is built for Chez Scheme
* Project should be portable across macos (darwin) and linux; windows is not
  supported (`.plans/decisions/0004-windows-not-supported.md`)
* Project should be portable across amd64 and arm64
* **DO NOT** setup macos CI runners: linux only!
* Exported functions should have a comment with a Typed Racket style type signature
* A Chez Scheme library binding the libcurl C library through the FFI;
  handle C *safely*. Portable across darwin, linux, on amd64 and arm64.

### Dependencies

* libcurl

### Guix development container

* **On a Guix host, run every build and test through `scripts/guix-env`**,
  e.g. `scripts/guix-env make test`. Batch commands with
  `scripts/guix-env sh -c 'make a && make b'`: each call takes a second or
  more to start.
* Edit, commit and push on the host. The container has no git identity,
  agents or tokens, and no network but loopback (ADR-0006).
* Verify it with `make check-guix`, run on the host.
* The container exports `CHEZ` (the real `scheme` binary), `CC` (gcc; the
  toolchain has no `cc`) and `CHEZ_CURL_LIBCURL` (the profile's
  `libcurl.so.4`, ADR-0002). It sets no `LD_LIBRARY_PATH`.
* Anything that needs the network or git runs on the host: fetches, pushes,
  downloads, `make check-pins`, and `git submodule update --init`, which a
  fresh clone needs once before `make deps`. The container has no git.

### Layout, process & libraries

* Plans live in `/.plans`, decision records in `/.plans/decisions`
* The ledger is `/.plans/progress.md`: where the project stands, the next
  slice, and a close-out for each merged slice. `/.plans/global-constraints.md`
  holds the decision records' hard rules and binds every task brief. Read both
  before starting slice work. `/.superpowers/` is git-ignored plugin scratch,
  not the ledger.
* Add entries to `CHANGELOG.md` for each release
* `/docs` is for user facing documentation only.
* Documentation should be very concise, focused, to the point, ELI5 style.
* `Makefile` should have a `help` command which lists all of its commands
* Libraries are R6RS `.sls`; libraries and programs contain their own code —
  no shared include bodies. R6RS forbids assigning an exported variable —
  reach mutable state through procedures.

### Testing & mutation discipline

* Use TDD / test-driven development
* A test that passes whether the code is right or wrong is worse than no test.
* A test is not finished when it passes. It is finished when you have watched
  it fail.
* Prefer a check to a comment.
* **Do not** write tests that rely on reading code comments
* `make check-nothreads` fails on a threaded Chez by design, so `make test`
  doesn't run it. CI runs it on a `--nothreads` Chez.
* `suite-exit-status` reads `(curl private counters)`, so a program that
  imports `(curl-testing)` needs `src` on its library path.
* `make test` runs every suite under GNU `timeout`. On macOS, run
  `brew install coreutils`, and make finds its `gtimeout`. Homebrew installs
  Chez as `chez`, which make also finds.
* A version manager's shim may write to stderr on every call, which fails
  every check that wants a quiet origin. asdf 0.15's does: run
  `make test NODE="$(asdf which node)"`.
* `make test` runs the test origin under Node (`NODE`, default `node`), and
  `test-drift` fails on any libcurl with no row in `tests/known-libcurls.sexp`.
  It prints the row: review it, and add it (ADR-0017).
* `make test` makes TLS material per run and checks the TLS faces with
  `openssl` (`OPENSSL`, default `openssl`). The Mac's `/usr/bin/openssl` is
  LibreSSL 3.3.6, which cannot check a hostname, so no check reads a hostname
  code (ADR-0005, amended). An `openssl` earlier on `PATH` takes its place:
  the maintainer's Mac found OpenSSL 3.6.3. To check with LibreSSL there, pass
  `OPENSSL=/usr/bin/openssl`.
* `make check-variadic` can watch a variadic binding fail only on Apple arm64.
  Run it on the Mac whenever a variadic binding changes. It needs `NODE` too:
  `test-variadic`'s drips run on the test origin. Elsewhere it checks
  only the static half: `test-collect-safe` must refuse each planted binding.

## Traps the family has already hit

Each shipped a green test or a working-looking build that was wrong, in
chez-cmark-gfm, chez-libuv or here. The incident behind each is in
`.plans/traps.md`; read it before working in that area.

**Tests**

* `guard` returns the body's value when nothing raises, and `0` is truthy.
  Assert *what was raised* against an expected value, with a distinct sentinel
  for the no-raise case.
* SRFI-64 turns an exception in the *actual* expression into `#f`. Never
  expect `#f` from something that can raise.
* SRFI-64 does not catch an exception in the *expected* expression, nor in a
  suite's top-level definitions: the suite dies and no test is named. Compute
  anything that can raise under a `guard`.
* Every `tests/test-*.sps` must end with `(exit (suite-exit-status runner))`:
  SRFI-64 sets no exit status. Anything after that line never runs, and
  `make check-suites` checks it is there.
* An exit status is taken modulo 256, so `(exit 256)` exits 0. Exit with 0 or
  1, never a count.
* A suite cannot vouch for the verdict it exits through. A suite that tests
  `suite-exit-status` must also exit 1 on its own failures, before the
  shared form.
* Chez evaluates arguments right to left in compiled library code, left to
  right when interpreted, and `map` calls its procedure in no fixed order. A
  `let`'s inits are arguments too. No assertion may depend on either order;
  use `for-each` for effects, and `let*` when one init must follow another.
* A setter that refuses a value keeps the one it had. Give each round trip
  its own sentinel, and assert every return code.
* An assertion passes whenever *another* rule can produce its expected value.
  Assert whole outputs, not substrings, and build a test's base from
  non-default values. Test a scan at every position, an encoding on bytes
  where encodings differ, and an allowlist against its whole complement.
* SRFI-64 keeps one result per runner. Never run a test inside another test's
  actual expression: the outer verdict is reported under the inner test's name.
* A thread a suite forks dies on a raise it does not catch, and a waiter with
  no bound then hangs the suite, naming no test. Make whatever a thread raises
  its answer, and bound every wait for one.
* Claude Code's Write tool drops trailing whitespace. Build a fixture whose
  point is a trailing space in code, and check its bytes.

**Chez and the FFI**

* `foreign-procedure` resolves its entry point when evaluated, so every
  binding must follow the library's load. Mistakes fail at *import*.
* A library body runs only when one of its bindings is *referenced*. A test of
  load-time behaviour must call into the library. A top-level program runs every
  body it references before its first line, so no thread of a program makes a
  first reference: only `eval` reaches a race on one.
* A `guard` in a program cannot catch a raise from an imported library's body.
  A probe must `eval` its call inside the guard.
* Chez runs a library body that raised a serious condition again at every
  later reference, and wedges one that raised anything else. A load must
  remember its first failure and raise only serious conditions, so libcurl is
  never loaded twice.
* A value that must outlive a failed load, such as the `libcurl-info` record,
  lives outside `native.sls`: any reference into native after a refusal raises
  again.
* A layout check by offset passes a field that is too narrow when padding keeps
  the next offset, and one by offset and size passes a `double` for a pointer.
  `test-constants` checks each field's offset, size and kind.
* On x86-64, a variadic binding without `(__varargs_after 2)` works, and an
  `int` for a 64-bit variadic argument passes -1 as 4294967295. Apple arm64
  passes variadic arguments on the stack, so by its ABI the first hands
  libcurl garbage there; that is not yet measured. `test-collect-safe` requires the
  annotation, and `test-variadic` passes -1 through each 64-bit binding:
  `MAXFILESIZE` for the `long` one, `MAXFILESIZE_LARGE` for `curl_off_t`.
* A reader that tracks a binding macro by its name at a form's head misses it
  reached any other way: unquoted, aliased, or passed to another macro. And a
  macro can take apart a form it is handed, or be handed a head, and bind
  what it rebuilds. So a wrapper's name is held to a use's head, every macro
  `src/` defines is a row of `known-macros`, and the reader's header lists
  what each kind may hold (traps.md).
* A flat macro pattern still lets a use hand the macro its head:
  `((_ head operand ...) (head operand ...))` took `define-syntax` and defined
  a macro no check saw. No pattern variable may head a form in a listed
  macro's template.
* Chez finds a library by its path, and `tests/` is on the suites' library
  path. So `check-seam` requires every family import to be defined under
  `src/`, each file to hold one library, at its name's path.
* A function ftype binds C without `foreign-procedure`: `make-ftype-pointer`
  takes an entry point's name, or a procedure. A rule on who may import a
  keyword loses to a re-export, or to a macro that takes the keyword as an
  argument. So layouts alone imports `define-ftype`, no library re-exports a
  Chez name, and layouts is held to struct forms alone.

**Checks and environment**

* Node's `socket.destroy()` closes with a FIN, not a reset. `resetAndDestroy()`
  sends the RST, but throws on a TLS socket: reset the `net` socket it wraps. A
  client's reset that way still arrives as a FIN. A test of a reset checks what
  the peer saw.
* libuv before 1.52, which Node 20.10.0 bundles, reports a reset that arrives
  with the last data as an end. The probe reads the socket's fd once on each
  end. A test of that path stops the probe across the last write and the reset,
  so that the two arrive together.
* LibreSSL, the Mac's `openssl`, exits 0 from `s_client -verify_return_error` on
  a failed verify, and its `req` prefers a `prompt = no` config's subject to
  `-subj`. Read verify codes, never that exit status, and give the config no
  subject.
* macOS's poll(2) does not support devices. LibreSSL's `s_client` polls stdin,
  so with stdin at `/dev/null` it exits 1, `poll error`, once connected. Give
  it an empty pipe, as `s-client` does.
* curl's `./configure` turns on every optional library it finds, and only warns
  about an option it doesn't know. A reproducible curl build names every
  library, passes `--enable-option-checking=fatal`, and checks what the install
  lists. A newer curl drops options an older one's line names, and the fatal
  check stops at each: curl 8 has no `librtmp`, `wolfssh`, `hyper` or `msh3`.
  Each pinned version gets a line read against its own `./configure --help`.
* A shell's `wait` may print `Killed` on stderr for a child killed by a signal:
  dash, `bash -c` and macOS's `/bin/sh` do, dash onto the stderr the killed
  command's own redirections set. Only bash run as `sh`, the container's,
  prints nothing, so a check run only there won't see it.
* OpenSSL 3's `s_client` prints one more `Verify return code` line per TLS 1.3
  session ticket it reads before stdin ends, so how many it prints depends on
  timing. A rule of one line per output fails only under load.
* Over TLS each record arrives as its own chunk, even when TCP joined them, so
  "each byte arrives alone" says nothing there. Judge timing between arrivals.
* TLS picks ALPN by the server's preference, so the chosen protocol hides a
  client that reorders its list. A server reports the offered list instead.
* An end seen after a stop proves the stop only if nothing but the stop can
  explain it: not an idle timer, nor Node's own `close()`, which ends some
  states on Node 24 and none on Node 20. Cover the states `close()` never ends,
  require silence right up to the stop and an end within a tight bound after
  it, open two sets of probes further apart than that bound, and stop twice,
  held apart by more than it.
* A child of `open-process-ports` stays a zombie until Chez's next collection, so
  `kill -0` succeeds on a dead pid. Never judge liveness by the pid alone.
* `nm` cannot show a curl API that was configured out: curl compiles a stub in
  its place. Only a call shows the difference.
* Deleting a subsystem disarms the checks built around it, and they stay
  green. On any deletion, ask of every surviving check "what would make this
  fail now?"; "nothing" is a defect.
* Point `CHEZ` at the real binary: a symlink breaks boot-file lookup, and a
  wrapper script hides Chez from Valgrind. `make check-guix` checks it.
* Put `timeout` outside Valgrind, never between it and Chez: Valgrind checks
  only the command it is handed.
* Valgrind also reads `VALGRIND_OPTS` and a `.valgrindrc` in `$HOME` or the
  working directory, which no command line shows. A suppression passed that way
  hid the planted leak. `--command-line-only=yes` stops those, but not
  `VALGRIND_LIB`, which moves `default.supp`. So `make test-memory` refuses every
  `VALGRIND_*` variable, and holds each suite's options and suppressions lists
  to the gate's exactly.
* A suite under Valgrind shares its PID, so it can print lines that look like
  Valgrind's own. Read Valgrind's evidence only from its `--log-file`.
* A check whose empty output means pass, passes when the checker itself fails.
  Require a positive `ok` line, and the checker's exit status.
* A check held by a table of its own passes when the table is loosened along
  with the code it checks. Write the table out in the check's suite.
* The counters gate counts per process. A child a suite spawns that reaches
  native must print its counts, and the suite must assert them zero.
* `pgrep -f PATTERN` matches the shell running it when PATTERN is in that
  shell's own command line, so `until ! pgrep -f PATTERN` never ends. Wait on
  a PID or a done-file instead.
* An allowlist of type names still passes a macro's pattern variable spelt as
  one of them. `test-collect-safe` counts every pattern symbol as no type.
* Valgrind cannot see into Chez's heap: an overrun into a bytevector, and a
  leaked block whose address an ftype pointer held, both pass. Bytevector copies
  go through one checked wrapper, and the counters are the leak gate.
* `guix shell --pure` does not stop a login shell from rebuilding `PATH`.
  `scripts/guix-env` uses `--container`, and `make check-guix` checks where a
  login shell finds each tool.
* `guix shell -m` reuses its cached profile while the manifest is no newer
  than the cache, so a copy that keeps old file times (`tar`, `cp -p`) runs
  the old toolchain. `touch` a manifest that a mutation changes.
* In an empty submodule directory, `git -C` answers for the superproject.
  Compare `git -C <dir> rev-parse --show-toplevel` with the directory itself
  before trusting anything else it says.
* Scheme strings and pairs are mutable, so a check on a caller's string or
  list, then a use of it, checks something else. Check a private copy, and
  use that copy.
* A continuation out of a foreign callable abandons its C caller: libcurl
  then leaks its connection while the counts read zero. Caller code inside a
  callable runs in a `dynamic-wind` that turns any exit but a return into a
  raise. An engine's expiry or an interrupt handler escapes at any safe point:
  each native object is made or freed in one critical section with its count
  and its record. A critical section around perform defers collections and
  Ctrl-C until the transfer ends, so M2 allowed its escapes and counted them.
  M2's path is gone, and the engine's thread runs no caller code, but for a
  process-wide `collect-request-handler`, which could escape there.
* An after thunk that raises during an engine's expiry kills the engine: `no
  engine active`. A refusal there holds against a caller's continuation only.
* A loop that waits in a plain foreign call stalls every other thread's
  collection up to about 500 times the wait: Chez checks pending events only
  when its 1000-tick counter runs out. Wait in `__collect_safe` calls. A check
  of it asks for collections back to back: a lone one can wait far less.
* Chez gives Ctrl-C to the main thread alone, and a thread in `condition-wait`
  answers it only when the wait ends. A wait inside `critical-section` keeps its
  thread active, so every other thread's collection waits for it, and a thread
  holding a mutex with interrupts on can join a collection while another blocked
  on it with interrupts off stays active: a deadlock. So hold no mutex while
  waiting: poll under `locked`, and `sleep` between reads, which deactivates the
  thread, with interrupts on alone, and runs a pending Ctrl-C as it wakes. A
  wait inside a critical section sleeps with its thread active, and deadlocks:
  the engine refuses one.
  A SIGINT the kernel hands another thread is dropped, and ends that thread's
  `sleep` or `curl_multi_poll` early. glibc's `system` ignores SIGINT
  process-wide while its command runs.
* A sweep's evidence that it reached a place needs a control run that cannot
  reach it, or a narrower reach passes too.
* `with-mutex` takes its mutex before its own `dynamic-wind`, so an escape
  between them leaves the mutex held. Hold a mutex through `critical-section`
  around `with-mutex`, and never wait while holding one.
* Valgrind runs one thread at a time, so a thread that never sleeps starves
  the rest. Pace a collecting or racing thread.
* One protocol pin hides the other's removal in a redirect test: libcurl
  checks a followed URL against both. Hold each pin by reading the options.
* An ambient `http_proxy` and the like divert every transfer, so
  `test-transfer` fails first, naming the variable, when one is set.
* A stalled name lookup blocks libcurl's teardown, and a timeout inside
  `curl_multi_perform`, for about 10 s: it waits for its resolver thread. On
  8.20.0, so does `curl_multi_cleanup`. `QUICK_EXIT` and `CURLMOPT_QUICK_EXIT`
  leave the thread behind, and every engine sets both where libcurl knows them.
  The container cannot stall a lookup itself: `tests/stall-getaddrinfo.c`,
  preloaded, stalls one on Linux, and `test-engine` runs it. macOS has no
  `LD_PRELOAD`, so the checks run on Linux alone (ADR-0019).
* curl 8.23.0 reuses, without checking it, a connection that went back to its
  pool under 1 s before, however old. The raw face closes after each script
  without saying so, so six drips live together leave six dead connections,
  and the next transfer retries on each, then gives up with 55. A check that
  runs drips together makes an engine of its own; `test-engine` pins each
  libcurl's answer by version (ADR-0020).
* libcurl 7.85.0, 8.5.0 and Apple's 8.7.1 take every value of every long multi
  option, so `curl_multi_setopt`'s answer cannot show a value arriving. `test-variadic`
  watches it by behaviour: two drips, serialised at `MAX_TOTAL_CONNECTIONS` 1.
* A probe that polls once more before it reads its clock reports late, by up to
  that poll's timeout. Stop the clock where the condition is first seen.
* In the Guix container, `C_INCLUDE_PATH` set to another curl's headers alone
  drops glibc's and the kernel's, and every compile fails. Prepend them:
  `C_INCLUDE_PATH=DIR:$C_INCLUDE_PATH`.
* Guix's libcurl 8.20.0 writes `SSL_CERT_FILE` and `SSL_CERT_DIR` over a
  transfer's `CAINFO` and `CAPATH` when it starts, after every setopt; its
  8.6.0 did not. The container passes neither; `test-transfer-tls` fails
  first when either is set, and pins the refusal a submit makes on a Guix
  libcurl with either set (ADR-0024).
* Ubuntu's libcurl trusts its default `CAPATH` beside `CAINFO`, so a CA file
  alone also trusts the system store. No lane's store trusts the run CA, so
  no behavioural test can see it: the transfer clears `CAPATH`, and its TLS
  settings are held as data.
* Apple's LibreSSL checks the keychain when a CA file fails; a library
  process on the Mac selects SecureTransport, and no test can show the
  fallback.
* libcurl's cleanup reads nothing a transfer handed it, so freeing the
  `CURLU`, the header list or the error buffer before `curl_easy_cleanup`
  passes every behavioural check, Valgrind's too. A check reads the
  transfer's nesting instead.
* In a git worktree, `.git` points outside the working directory, so a
  container that shares only the working directory sees no repository. Keep
  git on the host.
* Reading a library's import form does not show all it can import: `for`,
  a body `import`, `eval`, `import-only`, `$primitive`, and files Chez loads
  that the check doesn't read (`.ss`, a lone `.so`, `.#g.sls`). Deny lists
  lose; `check-seam` admits only what its allowlists name.
* An uncaught raise skips Chez's `exit-handler`. Cleanup at a program's top
  level must also hook `base-exception-handler`.
* Take a temporary directory's name from `mktemp`'s one line, never its first
  word. A path cut at a space once had the wrong directory removed.
* `make test`'s `timeout --foreground` does not kill a suite's children.
  After a HUNG suite, look for orphans.
* Guix's `gcc` warns on stderr at every link. Judge a compile by its exit
  status.
* In the container, loading libcurl leaks one block: p11-kit's constructor
  calls `newlocale`, and Guix's `GUIX_LOCPATH` patch to glibc loses it. Ubuntu
  loses nothing. ADR-0014 allows one suppression for it, in the container only.
* A bare `mktemp -d` ignores `TMPDIR` on macOS. Give `mktemp` a template
  under `$TMPDIR`.
* A constants check says nothing about a library whose headers it did not
  compile against. `test-constants` requires the headers to be no newer than
  the library it loads, so a floor lane points both `C_INCLUDE_PATH` and
  `CHEZ_CURL_LIBCURL` at the floor.
* A failed transfer's timings move with the version: 8.20.0 reports a total
  of 0 for a refused connect, and 8.23.0 fills pretransfer though nothing was
  sent. Whether a request was sent is whether `CURLINFO_REQUEST_SIZE` is 0,
  alike on five libcurls, never a timing. The size sums every attempt, a
  resend on 8.23.0's dead reused connections and the body included, so a
  check of its value runs on an engine of its own (ADR-0022, amended).
* A command that reads stdin, `scripts/guix-env` among them, inside a
  `while read` loop eats the rest of the loop's list. Give it `< /dev/null`,
  and count the results against the list.
* A waiter's polling sleeps keep the phase of its start, so a probe whose
  events fall on multiples of its period meets it at one phase, and measures
  one delay. Spread a probe's events over every phase.
* A Chez timer that runs out inside a critical section fires at a later
  event check, never as the section ends; a pending keyboard interrupt runs
  as it ends. To plant an escape there, block the code inside its section on
  a mutex another thread holds, and send SIGINT meanwhile.
* GnuTLS answers 77 for a malformed PKCS#11 URL, as for a missing file. A
  probe tells "read as a file" only by a file that is there and trusted: 200.
* ADR-0002's world is libc's. A Guix libcurl loaded outside Guix still
  writes `SSL_CERT_FILE` over a CA file, and so does a copy of it out of the
  store. Key on the library's own file, the maps line holding one of its
  entry points, and on the patch's string in that file.
* `char-downcase` makes U+212A KELVIN SIGN `k`, and `char-foldcase`,
  `string-ci=?` and `char-ci=?` make U+017F LONG S `s`. Where the other side
  compares bytes, fold A to Z alone, and test both chars.
* A MultiSSL libcurl's `curl_version_info` names its first backend as the
  one in use until `curl_global_init` picks one: Apple's 8.7.1 then uses
  LibreSSL, not SecureTransport. Read the backend after the init, and name
  it as curl does: `secure-transport`.
* libcurl 8.7.0 and 8.7.1 answer `CURLINFO_REQUEST_SIZE` 0 for every
  transfer. A count measured on some versions says nothing of one between.

## Closing ritual

We run this when we're done and ready to merge the PR.

**Important**: ALWAYS ask before running this.

1. Squash merge the PR.
2. Catch up local `main`.
3. Clean up branches. Delete the merged branch locally and on the remote.
4. Reflect.
