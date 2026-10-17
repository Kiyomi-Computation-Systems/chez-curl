# Global constraints

These rules bind every task brief. Each one cites the decision record in
[decisions/](decisions/) it comes from. If a rule here and its record disagree, the record
wins and this file gets fixed. Rules from a record that is still Proposed are marked
provisional. They bind until that record is accepted or amended.

## Platforms and versions

- **Platforms:** Linux and macOS, on amd64 and arm64. No Windows code paths, CI or
  abstractions (ADR-0004).
- **Chez:** 10.4.0 or later, threaded. An older, pre-release or non-threaded Chez is
  refused at import, by name (ADR-0001, amended).
- **libcurl:** 7.85.0 or later, meaning `version_num` ≥ `0x075500` (ADR-0003).
- **Anything newer than the floor is optional, one feature at a time.** Options are
  looked up by name. Functions are bound only if `foreign-entry?` finds them (ADR-0003).
- **Node:** 20 or later, for the test origin only (ADR-0005).
- **The floors have one source, `packaging/floors.sexp`.** `make check-floors`, which
  `make test` runs, holds the list lines of README.org's `** Requirements` to it. CI states no
  floor: its build scripts read the file through `scripts/ci/floor.sh`, and no workflow line
  may write a floor's version or name a floor key. `test-verify` and
  `test-require-threaded` hold the code to it by behaviour. To change a floor, edit the file,
  the README, `libcurl-floor` or `minimum`, and the literal rows that name the old floor
  (ADR-0016).

## Native code

- **No C is compiled for the library: no shim** (ADR-0001).
- **Variadic entry points are bound once per value type,** with `(__varargs_after 2)`.
  These are `curl_easy_setopt`, `curl_easy_getinfo`, `curl_multi_setopt` and
  `curl_share_setopt` (ADR-0001).
- **`CURLOPT_*` ids and types come from the loaded library,** through
  `curl_easy_option_by_name`. They are never written in Scheme (ADR-0001).
- **Every other constant is a Scheme definition** in `(curl private constants)`. A C program
  compiled at test time checks each one against libcurl's headers. Missing headers fail
  that test; they never skip it. A new export needs a row in `tests/test-constants.sps`,
  or that suite fails. Its C name is the export's name, upcased, with `-` as `_`, unless
  `c-name-aliases` names another, which is a reviewed change. A constant written anywhere
  else is checked by nothing (ADR-0001, amended).
- **Structs Scheme reads are `define-ftype`s in `(curl private layouts)`,** each a struct of
  primitive-typed fields. The same program checks every field's offset, size and kind. A
  new struct needs a row in the same suite. The headers it compiles against must be no
  newer than the library chez-curl loads (ADR-0001, amended).
- **`define-ftype` is used only in `(curl private layouts)`,** as struct forms alone. A
  function ftype would bind an entry point, or make a callable, that no other check sees.
  - `check-seam` lets only layouts import it (rule (f)). No library may re-export a name it
    imports from `(chezscheme)` (rule (g)).
  - `test-constants` holds layouts to an exact shape: its imports, struct `define-ftype`
    forms alone, and exports of exactly their names.

  (ADR-0007, ADR-0013, both amended)
- **Every `foreign-procedure` and `foreign-callable` has a row in
  `tests/foreign-conventions.sls`'s table,** and `test-collect-safe` checks its conventions
  against it.
  - An entry is a string literal, given directly or to a known wrapper (today
    `bind-required`).
  - A callable is the whole right-hand side of `(define name ...)`.
  - A new binding macro joins `known-wrappers`.

  (ADR-0013, amended)
- **Bulk copies use libc's `memcpy`,** bound directly as a plain call, never
  `__collect_safe`. One checked wrapper owns every copy between a bytevector and foreign
  memory, and asserts the bound in Scheme first: Valgrind cannot see an overrun into a
  bytevector.
- **`test-collect-safe` reads every binding's types as an allowlist,** and refuses a
  crossing, a type that hands C a pointer into Chez's heap, unless its row is marked.
  - A bytevector's data (`u8*`, `u16*`, `u32*`) needs `(bytevector-crossing CITATION)`:
    M2's checked wrapper only.
  - A string type needs `(string-not-kept CITATION)`, citing that its callee keeps no
    pointer. A string libcurl keeps, like `CURLOPT_POSTFIELDS`, goes through foreign memory.
  - `scheme-object` is never allowed.
  - A marked row is never `__collect_safe` (ADR-0001, ADR-0013, both amended).
- **`curl_global_init` is called exactly once,** from the library body (ADR-0003).
- **Every string `curl_url_get` returns is freed with `curl_free`** (ADR-0008).

## Loading libcurl

- **The override:** `CHEZ_CURL_LIBCURL`, when set, is an absolute path loaded as given.
  There is no search and no fallback. A relative path or bare name is refused as
  `invalid-override` (ADR-0002).
- **Otherwise, one candidate list per world.** The first candidate that exists wins, and
  it is loaded by absolute path. chez-curl never loads a bare soname, and never sets
  `LD_LIBRARY_PATH` or `DYLD_*` (ADR-0002).
  - **Guix world** (libc mapped from `/gnu/store`): `lib/libcurl.so.4` under
    `$GUIX_ENVIRONMENT`, `$GUIX_PROFILE`, `~/.guix-home/profile`, `~/.guix-profile`, then
    `/run/current-system/profile`. Never standard directories.
  - **Other Linux:** `libcurl.so.4` in `/usr/local/lib`, `/usr/lib/<triple>`,
    `/usr/lib64` and `/usr/lib`, then `/usr/lib/<triple>/libcurl-gnutls.so.4`. Never Guix
    profiles. The triple is `x86_64-linux-gnu` for `ta6le` and `aarch64-linux-gnu` for
    `tarm64le`.
  - **macOS:** `/usr/lib/libcurl.4.dylib` only.
- **One load, then verify.** After a failure, chez-curl never tries another candidate
  (ADR-0002).
- **The load runs at most once per process.** `(curl private load-state)` records its first
  failure, and every later reference raises that failure again. Every load step runs
  inside `load-step`, so only serious conditions are raised (ADR-0002, amended).
- **Binding order.** `curl_version_info` is bound and checked first. Every other entry
  point is then bound eagerly, in the same library body. Nothing binds lazily (ADR-0001,
  ADR-0002).
- **Checks at load:**
  - `CURL_VERSION_SSL` is set;
  - `curl_easy_option_by_name("URL")` returns non-NULL;
  - `curl_easy_header` on a fresh handle does not return `CURLHE_NOT_BUILT_IN`.

  (ADR-0002, ADR-0003)
- **The refusal reasons are the contract:** `invalid-override`, `not-found`,
  `load-failed`, `below-floor`, `no-ssl` and `missing-api`. Tests assert the reason
  symbol, never the message text. The preflight's printed output is its own contract, and
  its tests hold it whole (ADR-0002, ADR-0003, both amended).
- **A required entry point the library lacks is `missing-api`,** naming it. Each is checked
  with `foreign-entry?` before it is bound (ADR-0003, amended).
- **Every outcome reports what it loaded:** the path, its source, and the library's
  version, features and TLS backend. A refusal made after the version was read carries
  that report. `not-found` lists every candidate it checked (ADR-0002, amended).

## URLs and protocols

- **`curl_url` parses every URL.** The transfer takes the parsed handle through
  `CURLOPT_CURLU`, never a string Scheme rebuilt (ADR-0008).
- **Only `http` and `https`.** The scheme is checked on the parsed handle before
  submission. Every transfer is also pinned with `CURLOPT_PROTOCOLS_STR` and
  `CURLOPT_REDIR_PROTOCOLS_STR`. The deprecated bitmask options are never used (ADR-0003,
  ADR-0008).
- **Relative references** resolve with `curl_url_set` against the current URL's handle
  (ADR-0008).
- **A `CURLU` handle is used by one thread at a time.** Ownership passes to the engine with
  the request (ADR-0008).
- **Origins are compared by** scheme, lowercased host and effective port, never as strings
  (ADR-0008).
- **No dependency on uriparse** (ADR-0008).

## The escape hatch

- **It lives in `(curl unsupported)` only.** It attaches named options to a request record,
  never to a handle, and the engine applies them after the binding's own (ADR-0009).
- **Each option is checked when attached,** against the loaded libcurl's own table:
  - the name must be known to that libcurl;
  - the type must be long, enumerated values, `off_t`, string, blob or string list;
  - the value must match the type;
  - no string may contain NUL, CR or LF;
  - the option must not be one chez-curl owns or wraps. That is compared by id, so an alias
    cannot pass.

  (ADR-0009)
- **Owned options:** `URL`, `CURLU`, `PROTOCOLS_STR`, `REDIR_PROTOCOLS_STR`, `PROTOCOLS`,
  `REDIR_PROTOCOLS`, `NOSIGNAL`, and every option a request field sets (ADR-0009).
- **Lifetimes.** Blobs are passed with `CURL_BLOB_COPY`. String lists are built by the
  binding and freed only after the transfer completes (ADR-0009).

## Layout and names

- **One repository, `chez-curl`, with five libraries:** `(curl)`, `(curl private ...)`,
  `(curl unsupported)`, `(http-client)` and `(http-client private ...)` (ADR-0007,
  ADR-0010).
- **`make check-seam` guards the boundary, and `make test` runs it.** Tests are exempt
  (ADR-0007, amended).
  - No `(curl ...)` library imports `(http-client ...)`. An `(http-client ...)` library
    imports only `(curl)` from the low level.
  - Every library under `src/` is in one of the two families.
  - A library imports only from allowlists: `(rnrs ...)` except `(rnrs eval)`, `(only
    (chezscheme) name ...)` with names from `allowed-chez-names`, and the two families.
    Adding to a list is a reviewed change.
  - A name in `library-only-chez-names` is imported only by the libraries listed with it:
    `define-ftype` by `(curl private layouts)` alone.
  - No file under `src/` may be one Chez loads as a library that the check doesn't read.
- **Every `src/` library imports the refusal first:** a `(curl ...)` library imports
  `(curl private require-threaded)`, and an `(http-client ...)` library imports `(curl)`
  (ADR-0001, ADR-0007, both amended).
- **No dependency on chez-http-server,** in either direction (ADR-0011).

## Environment and tests

- **On a Guix host, build and test through `scripts/guix-env`.** Edit, commit and push on
  the host (ADR-0006).
- **The container has no network.** Tests reach nothing beyond loopback (ADR-0006).
- **Inside the container:**
  - `CHEZ` is the real `scheme` binary;
  - `CC` is the profile's `gcc`, since the toolchain has no `cc`;
  - `CHEZ_CURL_LIBCURL` is the profile's `libcurl.so.4`;
  - there is no `LD_LIBRARY_PATH` and no `--emulate-fhs`;
  - there is no git, so anything that needs git runs on the host. In a worktree, the
    container's git could read nothing.

  (ADR-0006)
- **The test origin is `tests/origin.mjs`.** It uses Node's standard library only and
  binds loopback only. It announces OS-chosen ports as one JSON line on stdout and exits
  when its stdin closes. Exact bytes come from its raw `node:net` face (ADR-0005).
- **TLS test material is generated per run** with the `openssl` command line. None is
  checked in (ADR-0005).
- **CI is `.github/workflows/ci.yml`, on a pinned `ubuntu-24.04`, Linux only.** It builds Chez
  from the release tarball, with a pinned sha256, and caches it.
  - `main` runs every check, `make build` and the suites.
  - `floor` runs `make build` and `make test` against curl 7.85.0 built from source, with
    `CHEZ_CURL_LIBCURL` and `C_INCLUDE_PATH` both pointed at it.
  - `floor-disabled-api` is two lanes. Each builds that curl without one API, and requires
    `make build` to refuse it as `missing-api`, naming that API's entry point, in the whole
    refusal block.
  - `nothreads` runs `make check-nothreads` on a `--nothreads` Chez.
  - `memory` runs on every run: every pull request, every push to `main`, and every tag.
  - Every `uses:` names a full commit SHA, with its tag in a comment.
    `scripts/ci/check-action-pins.sh` checks it.
  - A run on a pull request cancels that pull request's earlier run. Any other run has a
    concurrency group of its own, so nothing on `main` or a tag is cancelled.

  (ADR-0001, ADR-0003, ADR-0014, ADR-0016, all amended)
- **A check counts only after it has been watched failing** (ADR-0006, ADR-0007,
  AGENTS.md).

## Memory and the test harness

- **Valgrind on Linux is the memory gate.** Each suite runs as
  `timeout N valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $CHEZ --program …`.
  `timeout` wraps Valgrind and never sits between it and Chez (ADR-0014).
- **The gate must be seen to fail.** `make check-memory-gate` runs before `make test-memory`,
  and planted defects must fail with Valgrind's own marker (ADR-0014).
- **One suppression, used only when `GUIX_ENVIRONMENT` is set.** It covers the block Guix's
  glibc loses under `compute_locale_search_path` when libcurl loads p11-kit. CI passes no
  suppression. `make check-memory-gate` holds the file to that one entry. In a Guix
  environment, a suite must have exactly one block suppressed if it read `libp11-kit`, and
  none if it did not. `--undef-value-errors=no` is added only with a recorded run that
  needed it (ADR-0014, amended).
- **Valgrind checks exactly the gate's command.** `make test-memory` refuses every
  `VALGRIND_*` variable and both `.valgrindrc` files, and passes `--command-line-only=yes`.
  Valgrind writes its own `--log-file`, and every piece of evidence is read from it alone.
  - Each suite's `Valgrind options:` block must equal the gate's list exactly, in order.
  - Its suppressions read must be exactly Valgrind's own `default.supp`, plus ours in Guix.
  - A pass needs Valgrind's `Command:` line naming `$CHEZ`, symbols read from that file,
    and `ERROR SUMMARY: 0 errors from 0 contexts`.

  (ADR-0014, amended)
- **When the gate runs:** CI runs it on every pull request, on `main` and on tags. Locally it
  runs in the container (ADR-0014, amended).
- **Counters:** every native object is counted, always on, per engine. Suites assert that the
  counts move and return to zero, and a suite fails if any count is not zero at its end.
  They are the leak gate for foreign memory a Chez object has held. Valgrind treats such a
  block as reachable, even once the object is dropped (ADR-0014, amended).
- **SRFI-64 comes from `vendor/chez-srfi`,** at the commit `Akku.lock` pins.
  - `make check-pins` holds `Akku.lock`, the recorded gitlink and the checkout equal. It
    runs on the host and in CI.
  - `tests/test-manifest.sps` holds `Akku.manifest` to no scripts and no runtime
    dependency.

  (ADR-0015)
- **`make deps` never fetches.** Submodules are fetched on the host (ADR-0015).
- **The suite rules are checked** (ADR-0015):
  - every `tests/test-*.sps` ends with the shared exit form,
    `(exit (suite-exit-status runner))`, and `check-suites` checks it;
  - before that, a suite may exit early only with `(exit 1)`;
  - a suite that ran no tests fails;
  - every suite runs under `timeout`;
  - `make test` runs every suite and fails if any did.
- **Refusal probes print `(reason . symbol)`, and tests assert that symbol** (ADR-0015).

## Engine and threads

- **One engine thread owns every transfer handle:** the multi handle, plus the easy,
  share and mime handles and the string lists each transfer uses. Callers submit request
  records and never touch a transfer handle. Before M3, M2's blocking request owns its
  handle on the calling thread (ADR-0012).
- **Messages cross threads, handle calls don't.** Submit, cancel, resume and stop are
  queued under the engine's mutex, then `curl_multi_wakeup` wakes the poll. That wakeup is
  the only libcurl call a caller's thread makes on an engine's handle (ADR-0012).
- **One central check enforces it.** An operation on an engine-owned handle from any other
  thread raises `&curl-wrong-thread`, carrying who, expected and actual. The check compares
  `get-thread-id` (ADR-0012).
- **Caller code never runs on the engine thread.**
  - Callbacks only copy between libcurl's buffers and bounded buffers, then signal.
  - A full buffer pauses its transfer, and the consumer resumes it by message.
  - Completions are delivered on a caller's thread.
  - A test asserts thread identity inside a body consumer.

  (ADR-0012)
- **Concurrency costs no threads.** Many requests share one engine, and the high level
  never starts a thread per request (ADR-0012).
- **Provisional until spike E1 at M3** (ADR-0013, Proposed):
  - A libcurl call that can block is `__collect_safe`: `curl_multi_poll`,
    `curl_easy_perform`, and whatever else E1 finds blocks. So is every callback it can
    invoke.
  - Calls that cannot block stay plain. That includes `curl_multi_perform` until E1 says
    otherwise.
  - A call that can block, or can invoke a callback, never receives a Scheme string or
    bytevector. Pass it foreign memory instead.
