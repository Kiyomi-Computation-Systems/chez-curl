# Global constraints

These rules bind every task brief. Each one cites the decision record in
[decisions/](decisions/) it comes from. If a rule here and its record disagree, the record
wins and this file gets fixed. Rules from a record that is still Proposed are marked
provisional. They bind until that record is accepted or amended.

## Platforms and versions

- **Platforms:** Linux and macOS, on amd64 and arm64. No Windows code paths, CI or
  abstractions (ADR-0004).
- **Chez:** 10.4.0 or later, threaded. A non-threaded Chez is refused at import, by name
  (ADR-0001).
- **libcurl:** 7.85.0 or later, meaning `version_num` ≥ `0x075500` (ADR-0003).
- **Anything newer than the floor is optional, one feature at a time.** Options are
  looked up by name. Functions are bound only if `foreign-entry?` finds them (ADR-0003).
- **Node:** 20 or later, for the test origin only (ADR-0005).

## Native code

- **No C is compiled for the library: no shim** (ADR-0001).
- **Variadic entry points are bound once per value type,** with `(__varargs_after 2)`.
  These are `curl_easy_setopt`, `curl_easy_getinfo`, `curl_multi_setopt` and
  `curl_share_setopt` (ADR-0001).
- **`CURLOPT_*` ids and types come from the loaded library,** through
  `curl_easy_option_by_name`. They are never written in Scheme (ADR-0001).
- **Every other constant is a Scheme definition.** A C program compiled at test time
  checks each one against libcurl's headers. Missing headers fail that test; they never
  skip it (ADR-0001).
- **Structs Scheme reads are `define-ftype`s,** checked by the same program with `sizeof`
  and `offsetof` (ADR-0001).
- **Bulk copies use libc's `memcpy`,** bound directly as a plain call, never
  `__collect_safe` (ADR-0001).
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
  symbol, never the message text (ADR-0002, ADR-0003).
- **Every outcome reports what it loaded:** the path, its source, and the library's
  version, features and TLS backend. `not-found` lists every candidate it checked
  (ADR-0002).

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
- **`make check-seam` guards the boundary, and `make test` runs it.** No `(curl ...)`
  library imports `(http-client ...)`. An `(http-client ...)` library imports only `(curl)`
  from the low level. Tests are exempt (ADR-0007).
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
- **CI builds Chez from the release tarball.** It also runs a floor lane against curl
  7.85.0 built from source, plus a 7.85.0 variant with the options and header APIs
  disabled (ADR-0001, ADR-0003).
- **A check counts only after it has been watched failing** (ADR-0006, ADR-0007,
  AGENTS.md).

## Memory and the test harness

- **Valgrind on Linux is the memory gate.** Each suite runs as
  `timeout N valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $CHEZ --program …`.
  `timeout` wraps Valgrind and never sits between it and Chez (ADR-0014).
- **The gate must be seen to fail.** `make check-memory-gate` runs before `make test-memory`,
  and planted defects must fail with Valgrind's own marker (ADR-0014).
- **No suppression files.** `--undef-value-errors=no` is added only with a recorded run that
  needed it (ADR-0014).
- **When the gate runs:** CI runs it on `main`, on tags and on request. Locally it runs in the
  container (ADR-0014).
- **Counters:** every native object is counted, always on, per engine. Suites assert that the
  counts move and return to zero (ADR-0014).
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
