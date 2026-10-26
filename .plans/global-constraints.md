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
- **Node:** 20 or later, for the test origin and the probe only. CI's `floor` lane runs the
  suites at the floor, Node 20 (ADR-0005, amended).
- **The floors have one source, `packaging/floors.sexp`.** `make check-floors`, which
  `make test` runs, holds the list lines of README.org's `** Requirements` to it. CI states no
  floor: its build scripts read the file through `scripts/ci/floor.sh`, and no workflow line
  may write a floor's version or name a floor key. `test-verify` and
  `test-require-threaded` hold the code to it by behaviour. Every `node-version:` takes a
  step's output, matched in any case. A workflow line `check-floors` cannot read as text
  fails: a `\` after a `"`, an explicit key, an alias or anchor as a key, a character
  beyond ASCII, or a tab. To change a floor, edit the file,
  the README, `libcurl-floor` or `minimum`, and the literal rows that name the old floor
  (ADR-0016).

## Native code

- **No C is compiled for the library: no shim** (ADR-0001).
- **Variadic entry points are bound once per value type,** with `(__varargs_after 2)`.
  The ones chez-curl binds are `curl_easy_setopt`, `curl_easy_getinfo`, `curl_multi_setopt`
  and `curl_share_setopt`. libcurl has others, `curl_formadd` and the `curl_mprintf`
  family, which chez-curl does not bind.
  - Each of the four is bound through `bind-variadic`, whose template carries the
    convention, and `test-collect-safe` requires both of every binding of them.
  - x86-64 runs a binding without the convention correctly, so only Apple arm64 can show
    one failing. `make check-variadic` must be run on an Apple arm64 Mac whenever a
    variadic binding changes (ADR-0001, amended).
  - **It passed there on 2026-10-23,** on the maintainer's M1 (ADR-0001, amended). So M2
    may bind setopt and getinfo options.
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
    `bind-required`, `bind-variadic` and `bind-blocking`). A wrapper's conventions are its template's own,
    never a use's, and its pattern takes no operand apart.
  - A wrapper's name may stand only at the head of a use in code, or as the name its one
    `define-syntax` defines. Anywhere else it is stray: as an argument, in data, in a
    macro, bound as a name, or in an export or import. So no library exports a wrapper.
  - A row may name the one wrapper its entry must be bound through, `(bound-by NAME)`.
    The four variadic rows name `bind-variadic`, and the four multi calls that can block,
    `curl_multi_poll`, `curl_multi_perform`, `curl_multi_remove_handle` and
    `curl_multi_cleanup`, name `bind-blocking`, whose template carries `__collect_safe`
    (ADR-0013, amended 2026-10-25).
  - A callable is the whole right-hand side of `(define name ...)`. The one callable,
    `write-body`, is locked with `lock-object` where it is defined, and never unlocked.
- **Every macro `src/` defines is a row of `known-macros`,** in
  `tests/foreign-conventions.sls`: a binder (a known wrapper) or a plain macro, defined at
  a library body's top level in the file its row names. Any other `define-syntax`, and every `let-syntax` and `letrec-syntax`, fails.
  A new macro is a reviewed change to that table. A macro can take apart a form it is
  handed, or be handed a head, and bind what it rebuilds, while the reader reads the form
  as written.
  - `define-syntax`, `let-syntax` and `letrec-syntax` stand only at the head of a form
    written in code. As an operand, in data or in a template, each is stray.
  - No pattern variable heads a form in a listed macro's template, except a binder's
    parameter list, which is types.
  - A plain macro holds no `foreign-procedure`, `foreign-callable` or wrapper name, and
    none of `syntax-case`, `with-syntax`, `syntax->datum` or `datum->syntax`. Its
    `syntax-rules` patterns are flat, `(_ id ...)`.
  - A procedural plain macro is `(lambda (ID) BODY ...)`. ID stands only as the last
    argument of a `syntax-violation` call in tail position, and `syntax-violation` only at
    the head of such calls. Its library imports only whole `(rnrs ...)` libraries, never
    `(rnrs eval)`, and `(only (chezscheme) ...)`.
  - The reader treats quote, quasiquote, vector and box literals, and a `case` clause's
    datum list, as data.
  - Its limit: a phantom. A plain macro that quotes an operand makes the reader count a
    binding Chez never makes. Alone it hides nothing.

  (ADR-0013, amended)
- **Bulk copies use libc's `memcpy`,** bound directly as a plain call, never
  `__collect_safe`. One checked wrapper owns every copy between a bytevector and foreign
  memory, and asserts the bound in Scheme first: Valgrind cannot see an overrun into a
  bytevector. It is native's `copy-foreign->bytevector!` and `copy-bytevector->foreign!`, and
  the two `memcpy` bindings behind it are not exported (ADR-0001, amended).
- **Every string chez-curl hands libcurl is a counted, NUL-terminated UTF-8 copy in foreign
  memory,** made by `call-with-c-string`, which refuses a string holding U+0000. Chez's own
  `string` type would cut it at the NUL without a word. Strings libcurl hands back are read
  as bytes, through `strlen` and the checked copy (ADR-0001, amended).
- **Header strings are Latin-1, both ways:** one char per byte. A response header's name and
  value become strings that way. A request header's name and value, and the user agent, reach
  libcurl as counted Latin-1 copies, and a char above U+00FF is refused, as U+0000 is. That
  is the UTF-8 rule's one exception (ADR-0001, amended 2026-10-23).
- **Every check of a caller's string or list runs on a private copy, and the copy is what is
  used.** Scheme strings and pairs are mutable, so a check, then a use, of the caller's own
  checks something else. That covers the transfer's snapshot of its request, the C-string
  helpers, URL checking and option names (ADR-0001, amended).
- **A request header is refused, before anything native, as `&curl-request-error`:**
  - a name that is no RFC 9110 token, `not-a-token`;
  - a value or user agent whose first offending char is U+0000, CR or LF, or above U+00FF:
    `embedded-nul`, `line-break` or `not-latin-1`;
  - then one that starts or ends with SP, HTAB, VT or FF, `surrounding-whitespace`, since
    libcurl drops a blank value, and libcurl's own header of that name with it;
  - a second Host, or a User-Agent beside the user-agent field, `duplicates-field`. libcurl
    keeps one Host, and sends it first;
  - `Content-Length` or `Transfer-Encoding`, `framing-header`: M2 sends no body, and libcurl
    owns the framing. M4 revisits it with bodies.

  (M2 plan, §5.3)
- **Every entry point `src/` binds has a prototype row in `tests/test-constants.sps`,** written
  in the header's own spelling and checked against it. The suite holds each binding's Chez types
  to its row through `c-type-map`, which it writes out, with the enum names and the variadic
  lists. A new binding needs a row (ADR-0001, amended). A callable has one too: `write-body`
  is held to `curl_write_callback`'s typedef.
- **`test-collect-safe` reads every binding's types as an allowlist,** and refuses a
  crossing, a type that hands C a pointer into Chez's heap, unless its row is marked.
  - A bytevector's data (`u8*`, `u16*`, `u32*`) needs `(bytevector-crossing CITATION)`:
    `memcpy`'s row, the checked copies', only.
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
- **An engine loads libcurl before its thread starts.** `make-curl-engine` references the load
  on the caller's thread, then forks, so no engine thread makes a first reference. Chez locks
  no library's invocation, and two threads' first references together raise `cyclic
  dependency` (ADR-0002, amended 2026-10-24). A top-level program has run the load before its
  first line anyway, so only `eval` reaches that race, and no check in a program can show it
  (ADR-0002, amended 2026-10-25).
- **The load runs at most once per process.** `(curl private load-state)` records its first
  failure, and every later reference raises that failure again. Every load step runs
  inside `load-step`, so only serious conditions are raised (ADR-0002, amended).
- **Binding order.** `curl_version_info` is bound and checked first. Only libc's `memcpy`,
  both ways, and `strlen` come between it and the floor check, to read its strings. Every other
  entry point is then bound eagerly, in the same library body. Nothing binds lazily (ADR-0001,
  ADR-0002, both amended).
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
  ADR-0008). The pins, with `NOSIGNAL`, are `pinned-options`, the first thing the transfer sets
  on its handle; their names appear in `transfer.sls` only as data, and `test-transfer` holds
  both. A redirect test cannot: libcurl checks a followed URL against both pins, so either
  hides the other's removal.
- **Relative references** resolve with `curl_url_set` against the current URL's handle
  (ADR-0008).
- **Every `CURLU` lives and dies on one thread.** Submit checks a request's URL on the
  caller's thread, on its snapshot, and frees that handle before it returns, so a refused URL
  raises there. The engine parses the same snapshot again on its own thread (ADR-0008,
  amended 2026-10-24).
- **Origins are compared by** scheme, lowercased host and effective port, never as strings
  (ADR-0008).
- **No dependency on uriparse** (ADR-0008).
- **curl's URL verdicts vary by version,** so the URL suite holds a shared answer for each
  case every recorded libcurl agrees on, and a row per libcurl version for the cases that
  vary. A libcurl with no row fails, printing its row. Answers are asserted whole, as a URL
  or a `CURLUcode`, never a message (ADR-0008, amended).

## TLS

- **TLS is whatever the loaded libcurl provides** (brief §2 item 5). The suites must pass on
  two backends at least: GnuTLS and OpenSSL on Linux, and SecureTransport on the Mac
  (ADR-0003, brief §9 risk 3).
- **A request's CA file is its only trust anchor.** The field sets `CAINFO` to it and clears
  `CAPATH`, since Ubuntu's libcurl trusts its default `/etc/ssl/certs` beside `CAINFO`. A
  `CURLE_NOT_BUILT_IN` answer to `CAPATH` is accepted: that backend has no CA directory. `#f`
  is libcurl's system store, as built, and sets neither (ADR-0018).
- **Every transfer sets verification:** `SSL_VERIFYPEER` and `SSL_VERIFYHOST` at 1 and 2, or
  both 0 when the request turns verification off (ADR-0018).
- **The TLS settings are data,** computed from the request and applied exactly, and
  `test-transfer-tls` holds them whole (ADR-0018).
- **Guix's libcurl 8.20.0 writes `SSL_CERT_FILE` and `SSL_CERT_DIR` over `CAINFO` and
  `CAPATH`** when a transfer starts, after every setopt. Guix's 8.6.0, an older patch, lets the
  request's settings win. `test-transfer-tls` fails first when either is set, and a child test
  pins the override by world and version, from a table in the suite: a Guix libcurl of an
  unrecorded version fails it. The policy, with `SSLKEYLOGFILE`, `OPENSSL_CONF` and GnuTLS's
  `pkcs11:` CA files, is M4's (ADR-0018).

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
  `REDIR_PROTOCOLS`, `NOSIGNAL`, and every option a request field sets, among them `CAINFO`,
  `CAPATH`, `SSL_VERIFYPEER` and `SSL_VERIFYHOST` (ADR-0009), and `QUICK_EXIT`, which every
  engine transfer sets from M3 slice 3 (ADR-0009, amended 2026-10-24 and 2026-10-25). Each
  owned setting's **twin** is
  refused too, an option with an id of its own that sets the same thing: `MAXFILESIZE`,
  `TIMEOUT`, `HTTPGET`, `POST`, `UPLOAD`, `PUT`, `CAINFO_BLOB` and `SSL_OPTIONS` today, and
  with them the transfer's callable and data, `WRITEFUNCTION`, `WRITEDATA` and `ERRORBUFFER`
  (ADR-0009, amended 2026-10-23 and 2026-10-24).
- **The test seam, `curl-engine-submit-with`, is held to these rules, narrowed:** long,
  enumerated-value and `off_t` options alone, so no address can pass, checked at submit on
  the caller's thread. It stays private (ADR-0009, amended 2026-10-23 and 2026-10-25).
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
    `define-ftype` by `(curl private layouts)`, `foreign-alloc` and `foreign-free` by
    `(curl private memory)`, `foreign-procedure` and `load-shared-object` by
    `(curl private native)`, `foreign-callable`, `foreign-callable-entry-point` and
    `lock-object` by `(curl private transfer)`, and `fork-thread` by
    `(curl private engine)`, each alone (ADR-0007, amended). No library imports
    `mutex-acquire`, `mutex-release`, `make-condition`, `condition-wait` or
    `condition-broadcast` (ADR-0013, amended 2026-10-25).
  - No file under `src/` may be one Chez loads as a library that the check doesn't read.
  - Every `(curl ...)` or `(http-client ...)` library a `src/` library imports is defined
    under `src/` (rule (h)). `tests/` is on the suites' library path too.
  - Each file under `src/` holds exactly one library, at the path its name gives (rule
    (i)). Chez finds a library by its path, so one defined elsewhere could lose to a copy
    in `tests/`. Both rules rely on `src/` coming first in `LIBDIRS`, which nothing checks.
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
- **The test origin is `tests/origin.mjs`.** It uses Node's standard library only, and
  each face listens on `127.0.0.1`. The plaintext faces, `http`, `raw` and `h2c`, are
  always there. `--pki DIR` adds the TLS faces, `h2` among them, which serves HTTP/2 by
  ALPN only (M1 plan, §8).
  - It announces one flat JSON line on stdout: `node`, `pid`, then each face as
    `ADDRESS:PORT`, read back from the listening socket. Nothing else goes to stdout.
  - It exits 0 when its stdin closes, and a misbehaving client ends only its own
    connection.
  - `call-with-origin` holds it to a clean stop: stdout ended, nothing on stderr, and exit
    status 0. Every wait on a pipe in the helpers is bounded by a monotonic clock.
  - Its stdin closes once every process holding it has gone, so a suite killed mid-probe
    leaves it serving until that probe's own deadline.
  - Exact bytes come from its raw `node:net` face (ADR-0005, amended).
- **The instrument is checked by a byte probe,** `tests/wire-probe.mjs`, which has no HTTP
  code, and by `openssl`.
  - Each TLS face is checked by three portable facts: `s_client`'s verify errors and code
    against the run CA, the leaf it serves compared with its file, and that leaf's SAN
    line.
  - The code is the first `Verify return code` line. Each later one, from a TLS 1.3
    session ticket, must sit under its own ticket header and agree with it.
  - No check reads a hostname code, which LibreSSL 3.3.6 cannot give. Nor an exit status
    under `-verify_return_error`, which LibreSSL gives as 0 on a failed verify. Nor the
    `-subject` line. Names come from `x509 -text`'s `Subject:` and `Issuer:` lines, with
    ` = ` folded to `=` (ADR-0005, amended).
  - The suites hold their own copy of each scenario's expected bytes, never read from the
    origin, and assert whole outputs.
  - No check of the instrument uses libcurl or the `curl` command line (ADR-0005, amended).
- **TLS test material is generated per run** with the `openssl` command line, by
  `tests/make-test-pki.sh`, running `OPENSSL` or else `openssl`. None is checked in, not
  even in a test's fixtures (ADR-0005).
- **The drift guard:** `test-drift` passes only when the loaded libcurl's `version`,
  `version-num`, `features`, `ssl-version` and `host` equal exactly one row of
  `tests/known-libcurls.sexp`.
  - A libcurl with no row fails wherever it runs, printing its row. A new row is a reviewed
    change.
  - The floor lane's curl names every optional library explicitly, so its feature word
    does not depend on the build machine (ADR-0017).
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
  environment, that entry must have suppressed exactly one block in a suite that read
  `libp11-kit`, and none in one that did not, counted from Valgrind's `used_suppression`
  line for it. Valgrind's own `default.supp` is trusted, in Guix as on CI.
  `--undef-value-errors=no` is added only with a recorded run that needed it (ADR-0014,
  amended 2026-10-24).
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
- **Counters:** every native object is counted, always on, per process, and an engine's
  transfers in its table of live transfers too, which a stop empties and checks empty before
  the engine's thread ends (ADR-0014, amended 2026-10-25). A multi handle is counted as
  `multi`. `(curl private counters)` holds them, with no reset, and `(curl private memory)` alone
  makes and frees foreign blocks. Suites assert that the counts move and return to zero.
  `suite-exit-status` fails a suite whose counts are not all zero at its end, and every child a
  suite spawns that reaches native prints its counts, which the suite asserts zero. They are
  the leak gate for foreign memory a Chez object has held. Valgrind treats such a block as
  reachable, even once the object is dropped (ADR-0014, amended).
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
  records and never touch a transfer handle. M2's blocking path, which owned its handle on
  the calling thread, is gone (the M3 plan, §5.4; ADR-0012).
- **Messages cross threads, handle calls don't.** Submit, cancel, resume and stop are
  queued under the engine's mutex, then `curl_multi_wakeup` wakes the poll. That wakeup is
  the only libcurl call a caller's thread makes on an engine's handle (ADR-0012). A cancel
  of a token still queued is no message: the caller's thread completes it, under the
  engine's mutex, and nothing native is made for it (the M3 plan, §3.5).
- **One central check enforces it.** An operation on an engine-owned handle from any other
  thread raises `&curl-wrong-thread`, carrying who, expected and actual. The check compares
  `get-thread-id` (ADR-0012). It is native's: every easy, multi and `CURLU` handle and every
  string list is recorded with the thread that made it, in the critical section that counts
  it, and every exported procedure that takes one checks it first. `curl_multi_wakeup`
  alone may be called from any thread, on a live multi handle.
- **Caller code never runs on the engine thread.**
  - Callbacks only copy between libcurl's buffers and bounded buffers, then signal.
  - A full buffer pauses its transfer, and the consumer resumes it by message.
  - Completions are delivered on a caller's thread.
  - A test asserts thread identity inside a body consumer.
  - A request holds no procedure: a fault the callable must survive is planted as data, and
    the callable logs each chunk's length and thread as data on the token (the M3 plan,
    §3.6).

  (ADR-0012)
- **Concurrency costs no threads.** Many requests share one engine, and the high level
  never starts a thread per request (ADR-0012).
- **Every native object is made, or freed, in one critical section with its record:** its
  count, its table entry, and the variable its free reads. An escape between the two, by an
  engine's expiry or an interrupt handler, leaked it for good. Every mutex is held through
  `locked`, `critical-section` around `with-mutex`, which takes its mutex before its own
  `dynamic-wind` (ADR-0013, amended 2026-10-23). No hold waits: a thread waiting inside a
  critical section stays active, and holds every other thread's collections, and a thread
  that holds a mutex with interrupts on can join a collection while another, blocked on that
  mutex with interrupts off, stays active, which deadlocks. So a wait polls: each read of
  what it waits for is a short hold through `locked`, and between reads it sleeps, from
  50 µs doubling to 10 ms, holding nothing, and refuses to start with interrupts off, when
  its sleep would keep its thread active. No condition variable is used (ADR-0013, amended
  2026-10-25, after the slice's review).
- **M2's escape rules ended with its path.** `curl_easy_perform` is bound no more, and the
  engine's thread runs no caller code, sets no timer and gets no Ctrl-C, so nothing escapes
  inside its perform but through `collect-request-handler`, which is process-wide: a
  caller's handler that escapes could run there (ADR-0013, amended 2026-10-25).
- **Calls that can block are `__collect_safe`** (ADR-0013, accepted 2026-10-24 from spike E1):
  - they are `curl_multi_poll`, `curl_multi_perform`, `curl_multi_remove_handle` and
    `curl_multi_cleanup`. The last three each waited 9 to 10 s while a name lookup stalled.
    They are bound through `bind-blocking` (ADR-0019);
  - so is every callback a `__collect_safe` call can invoke. The write callback fires inside
    `curl_multi_perform` alone;
  - one callable may serve a `__collect_safe` call and a plain one;
  - `curl_multi_init`, `curl_multi_add_handle`, `curl_multi_wakeup`, `curl_multi_info_read`,
    and `curl_easy_cleanup` of a handle removed from the engine's multi handle, stay plain,
    as does every call that cannot block. After `curl_easy_perform`, `curl_easy_cleanup`
    waited 9 s on 8.20.0; slice 2 deleted that path;
  - a call that can block, or can invoke a callback, never receives a Scheme string or
    bytevector. Pass it foreign memory instead.
- **The engine's loop never waits in a plain call.** A plain wait stalls every other thread's
  collection up to about 500 times its length: Chez checks a pending collection only when a
  thread's 1000-tick event counter runs out (ADR-0013, amended 2026-10-24).
- **A stalled name lookup does not stall the engine** (ADR-0019). M3 slice 3 builds these;
  slice 2's engine sets neither option yet:
  - every engine transfer sets `QUICK_EXIT` to 1 when the loaded libcurl knows it, looked up
    by name, with the pins;
  - every engine's multi handle sets `CURLMOPT_QUICK_EXIT` to 1 when it is made, through
    `curl_multi_setopt`. `CURLM_UNKNOWN_OPTION` is accepted;
  - the floor, 7.85.0 to 7.86.x, keeps the stall, up to glibc's resolver timeout.
- **Stopping an engine cancels what is in flight** (ADR-0012, amended 2026-10-24). Each queued
  and live transfer completes as `stopped`. The engine frees every handle and cleans up the
  multi handle, and the caller's stop returns once its thread has signalled its end. A later
  submit raises, and a later stop returns at once. A drain is the caller's: await, then stop.
