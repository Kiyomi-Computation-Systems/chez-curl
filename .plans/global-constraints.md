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
  ADR-0001 names four: chez-curl binds `curl_easy_setopt`, `curl_easy_getinfo` and
  `curl_multi_setopt`, and `curl_share_setopt` has a row of the conventions table but no
  binding yet. libcurl has others, `curl_formadd` and the `curl_mprintf` family, which
  chez-curl does not bind.
  - Each is bound through `bind-variadic`, whose template carries the convention, and
    `test-collect-safe` requires both of every binding of them.
  - x86-64 runs a binding without the convention correctly, so only Apple arm64 can show
    one failing. `make check-variadic` must be run on an Apple arm64 Mac whenever a
    variadic binding changes (ADR-0001, amended).
  - **It passed there on 2026-10-23,** on the maintainer's M1 (ADR-0001, amended). So M2
    may bind setopt and getinfo options.
  - **`curl_multi_setopt` is bound once, for a `long`** (M3 slice 3). No long multi option
    answers by its value on 7.85.0 or 8.5.0, so `test-variadic` watches the value arrive by
    behaviour: `MAX_TOTAL_CONNECTIONS` at 1 serialises two transfers, and at 2 they run
    together (ADR-0001, amended 2026-10-25). The Mac's `check-variadic` must show it fail
    there before M3 is done.
- **`CURLOPT_*` ids and types come from the loaded library,** through
  `curl_easy_option_by_name`. They are never written in Scheme (ADR-0001).
- **Every other constant is a Scheme definition** in `(curl private constants)`. A C program
  compiled at test time checks each one against libcurl's headers. Missing headers fail
  that test; they never skip it. A new export needs a row in `tests/test-constants.sps`,
  or that suite fails. Its C name is the export's name, upcased, with `-` as `_`, unless
  `c-name-aliases` names another, which is a reviewed change. A constant written anywhere
  else is checked by nothing (ADR-0001, amended).
  - **A constant newer than the floor carries its gate,** written out in the suite: the
    release that added it, as text and as `LIBCURL_VERSION_NUM`. The C program reads it
    under `#if`, so headers at or above the gate check it and older ones name it unchecked.
    A compile probe, with a control that must compile and one that must not, requires the
    headers to declare it exactly when they are at or above the gate. The first is
    `CURLMOPT_QUICK_EXIT`, since 8.20.0 (M3 slice 3).
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
    (ADR-0013, amended 2026-10-25), and so does `curl_easy_pause`, from M6 (ADR-0013, amended
    2026-10-30).
  - A callable is the whole right-hand side of `(define name ...)`. Each callable, `write-body`
    and, from M6, the header callable `read-head` and the read, seek and prerequest callables
    `read-body`, `seek-body` and `prereq-body` (ADR-0013, amended 2026-10-31), is locked with
    `lock-object` where it is defined, and never unlocked.
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
  is the UTF-8 rule's one exception (ADR-0001, amended 2026-10-23). A header's bytes handed to
  a URL function, a `Location`'s, are no second one: `curl-url-resolve` and
  `curl-url-with-fragment` encode them into ASCII first (ADR-0029, amended 2026-10-28).
- **Every check of a caller's string or list runs on a private copy, and the copy is what is
  used.** Scheme strings and pairs are mutable, so a check, then a use, of the caller's own
  checks something else. That covers the transfer's snapshot of its request, its body
  among it from M4 slice 1, the C-string helpers, URL checking and option names (ADR-0001,
  amended; ADR-0023).
- **A request header is refused, before anything native, as `&curl-request-error`:**
  - a name that is no RFC 9110 token, `not-a-token`;
  - a value or user agent whose first offending char is U+0000, CR or LF, or above U+00FF:
    `embedded-nul`, `line-break` or `not-latin-1`;
  - then one that starts or ends with SP, HTAB, VT or FF, `surrounding-whitespace`, since
    libcurl drops a blank value, and libcurl's own header of that name with it;
  - a second Host, or a User-Agent beside the user-agent field, `duplicates-field`. libcurl
    keeps one Host, and sends it first;
  - `Content-Length` or `Transfer-Encoding`, `framing-header`: libcurl owns the framing, from
    the body it is handed, M4's bodies too (ADR-0023).

  (M2 plan, §5.3)
- **Every entry point `src/` binds has a prototype row in `tests/test-constants.sps`,** written
  in the header's own spelling and checked against it. The suite holds each binding's Chez types
  to its row through `c-type-map`, which it writes out, with the enum names and the variadic
  lists. A new binding needs a row (ADR-0001, amended). A callable has one too: `write-body`
  and `read-head` are each held to `curl_write_callback`'s typedef.
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
- **Every string `curl_url_get` gives back is read as strict UTF-8, or refused** as
  `&curl-url-error`, `not-utf-8`, naming the string the caller gave: libcurl decodes a host's
  `%XX`, so a UTF-8 URL can come back as other bytes. Never `utf8->string`, which reads them
  as U+FFFD. The decode keeps a leading U+FEFF, which Chez's decoders drop (ADR-0008,
  amended 2026-10-27, slice 1). One exception: a response's `CURLINFO_EFFECTIVE_URL` is still
  read with `utf8->string`. While `FOLLOWLOCATION` stays owned and off it is the URL the strict
  check passed, and a refusal there would raise on the engine's thread.
- **curl's URL verdicts vary by version,** so the URL suite holds a shared answer for each
  case every recorded libcurl agrees on, and a row per libcurl version for the cases that
  vary. A libcurl with no row fails, printing its row. Answers are asserted whole, as a URL
  or a `CURLUcode`, never a message (ADR-0008, amended). `test-url-parts` holds `curl-url-part`'s
  and `curl-url-append-query`'s the same way, in a rows file of its own, and `test-url-location`
  `curl-url-resolve`'s and `curl-url-with-fragment`'s, in another.

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
  pins the refusal below, given each variable before the load, or set or emptied after it, by
  the file the libcurl is mapped from, read in the suite apart from native's reading: a Guix
  libcurl of a version neither table has a row for fails it (ADR-0018; ADR-0024, amended
  2026-10-26).
- **What a transfer reads from its environment** (ADR-0024, from M4 slice 3):
  - it honours the proxy variables, by libcurl's own rules, and a request's `proxy` field at
    `#f` turns them off, by `CURLOPT_PROXY` `""`. A proxy given by URL is M7's;
  - a proxy's TLS stays libcurl's verified default, against its system store, until M7: every
    `PROXY_SSL_*` and `PROXY_CA*` option is owned (ADR-0024, amended 2026-10-26);
  - native reads `SSL_CERT_FILE` and `SSL_CERT_DIR` immediately before `curl_global_init`, where
    Guix's patch reads them, and records them, an empty value as unset. It records the file the
    libcurl is mapped from too: the `/proc/self/maps` line holding `curl_version_info`'s entry
    point, symlinks resolved, never libc's world, and whether that file holds Guix's patch's
    literal, `SSL_CERT_FILE`. Where `guix-ca-overrides` says the loaded libcurl overrides a
    CA file (Guix's 8.20.0, and every other libcurl whose file is under `/gnu/store/`, or,
    with no file read, whose path is, or whose file holds the literal: ADR-0024, amended
    2026-10-26, the key), a request with a CA file and
    verification on is refused at submit, as `&curl-request-error` `environment-override`,
    whose irritants name each variable recorded as set. The rule is pure,
    `overriding-variables`, held on every lane; only a Guix libcurl shows it by behaviour;
  - on macOS with Apple's LibreSSL the TLS backend in use, as `curl_version_info` names it
    after the init, a request with a CA file and verification on is refused at submit, as
    `keychain-fallback`: its keychain fallback would undo the CA file.
    `CURL_SSL_BACKEND=secure-transport` is the operator's way to a CA file there, and make
    sets it for the suites on macOS (ADR-0024, amended 2026-10-27);
  - a CA file's path beginning `pkcs11:`, in any ASCII case and no other fold, is refused as
    `pkcs11-url` when the request is made and again at submit, on every backend: GnuTLS took
    all sixteen ASCII cases;
  - `SSLKEYLOGFILE`, `OPENSSL_CONF` and `CURL_SSL_BACKEND` are documented in README.org, not
    refused.

## The public request and its failures

- **A request is made from a property list:** `(make-curl-request URL KEY VALUE ...)`, and
  `curl-request-with` makes a new one with keys replaced. An unknown key, a repeated key, and a
  key with no value are refused by name. The defaults set no policy: libcurl's own stand
  (ADR-0023, from M4 slice 1).
- **A request may carry a whole body,** a bytevector, with a method beyond GET and HEAD from the
  M4 plan's fixed set. The submit's copy takes it, and libcurl copies that. `Content-Length` and
  `Transfer-Encoding` stay refused: libcurl owns the framing. Streaming is M6's (ADR-0023).
  `put`, `patch` and `delete` are `CUSTOMREQUEST`, owned. Nothing follows a redirect:
  `FOLLOWLOCATION` is owned and left off, since through a 301, 302 or 303 libcurl resends a
  custom method without its body (ADR-0023, amended 2026-10-26); a private `follow` field sets
  it for tests alone.
- **A body's headers are the request's alone:** a request that sends a body also sends
  `Content-Type:` and `Expect:`, which take libcurl's own form type and `Expect` away, unless
  it names a header of that name, which replaces libcurl's. An empty body is a block of one
  byte, never NULL, as a defence: NULL tells libcurl to read the body through its read callback,
  whose default reads stdin, though with a size of 0 it reads none (ADR-0023, amended 2026-10-26, as built in M4 slice 1).
- **A failed transfer raises its code's class,** a condition type under
  `&curl-transfer-error` with every base field, or the base type for a code no class names. The
  class follows the code, for `perform-failed` alone, never the scenario: one failure's code
  moves with the version. `body-limit` is too-large, and every other reason the base type. A
  class is described in curl's words for its codes, never by a cause. Every classed code is a
  constant in `(curl private constants)`, 100 and 101 behind their gates, and every code from 0
  to 101 has a row in one table, written out in the suite. Tests assert the type, the reason and
  the code, and a text only where a version row pins it (ADR-0022, amended 2026-10-26, from M4
  slice 1).
- **A failed transfer's condition carries its request size,** `CURLINFO_REQUEST_SIZE`, the
  bytes of request libcurl sent over every attempt, the body's among them, 0 when it sent none:
  whether it is 0 is what M5's retry policy reads to tell whether a request was sent. A check
  of its value runs on an engine of its own, since curl 8.23.0 resends a head after a dead
  reused connection, and counts both. It carries no timings, which on a failure move with the version;
  the response carries them (ADR-0022, amended 2026-10-26, from M4 slice 1). On libcurl 8.7.0
  and 8.7.1, whose count reads 0 for every transfer, a transfer that ran carries `#f`, unknown,
  and one refused while it was set up still 0 (ADR-0022, amended 2026-10-27).
- **A submit's caller-side checks have one owner,** `request-checks`, which `curl-submit`
  (through `prepare-transfer`) and `curl-request-check` share: what is no request, the URL's
  copy, the headers' and the user agent's snapshot, the CA file's copy and its refusal against
  the environment the libcurl loaded with, then the URL's parse and scheme. `curl-request-check`
  raises what a submit would, its who `curl-request-check` where a submit's is `curl-submit`,
  and copies no body and queues nothing; a submit copies the body after every check (ADR-0023,
  amended 2026-10-28).

## The escape hatch

- **It lives in `(curl unsupported)` only,** which exports `curl-request-with-options`. It
  attaches named options to a request record, never to a handle, and the engine applies them
  after the binding's own and the pins. `(curl)` does not export it, by any name, which
  `test-unsupported` holds; and no `(curl ...)` library imports `(curl unsupported)`
  (check-seam's rule (j)). The procedure is `(curl private transfer)`'s export too, beside the
  request's constructor it needs (ADR-0009, amended 2026-10-27).
- **Each option is checked when attached,** against the loaded libcurl's own table:
  - the name must be known to that libcurl;
  - the type must be long, enumerated values, `off_t`, string, blob or string list;
  - the value must match the type;
  - no string may contain NUL, CR or LF;
  - the option must not be one chez-curl owns or wraps. That is compared by id, so an alias
    cannot pass;
  - the request must not carry it already, by any of its names.

  Each value is copied first, and the copy is checked and kept: the caller's objects are never
  read again. A name or a string refused is a `&curl-request-error`, field `options`, reason
  `embedded-nul`, `unknown-option`, `owned-option`, `unsupported-type`, `repeated-option` or
  `line-break`; a value of the wrong shape or range is an assertion violation (ADR-0009,
  amended 2026-10-27).
- **Owned options:** `URL`, `CURLU`, `PROTOCOLS_STR`, `REDIR_PROTOCOLS_STR`, `PROTOCOLS`,
  `REDIR_PROTOCOLS`, `NOSIGNAL`, and every option a request field sets, among them `CAINFO`,
  `CAPATH`, `SSL_VERIFYPEER` and `SSL_VERIFYHOST` (ADR-0009), and `QUICK_EXIT`, which every
  engine transfer sets from M3 slice 3 (ADR-0009, amended 2026-10-24 and 2026-10-25). Each
  owned setting's **twin** is
  refused too, an option with an id of its own that sets the same thing: `MAXFILESIZE`,
  `TIMEOUT`, `HTTPGET`, `POST`, `UPLOAD`, `PUT`, `CAINFO_BLOB` and `SSL_OPTIONS` today, and
  with them the transfer's callable and data, `WRITEFUNCTION`, `WRITEDATA` and `ERRORBUFFER`
  (ADR-0009, amended 2026-10-23 and 2026-10-24), and from M6 slice 1 the `stream-buffer`
  field's header callable and its data, `HEADERFUNCTION` and `HEADERDATA` (ADR-0009, amended
  2026-10-30), and from M6 slice 2 the `body` field's read, seek and prerequest callables and
  their data, `READFUNCTION`, `READDATA` (`INFILE` its alias), `SEEKFUNCTION`, `SEEKDATA`,
  `PREREQFUNCTION` and `PREREQDATA`, with `FRESH_CONNECT`, on every request; `POST`, `UPLOAD`
  and `INFILESIZE_LARGE` are now fields' options, not twins (ADR-0009, amended 2026-10-31).
  M4 adds, each in its slice: the body's options, `CUSTOMREQUEST`, `CONNECTTIMEOUT_MS`, `PROXY`,
  `FOLLOWLOCATION`, and every `PROXY_SSL_*` and `PROXY_CA*` option, with their twins, among the
  string, list and blob options too (ADR-0009, amended 2026-10-26). Slice 1 built its own, and
  read the options tables of five libcurls for the twins: `CONNECTTIMEOUT`, `POSTFIELDS`,
  `POSTFIELDSIZE`, `HTTPPOST`, `MIMEPOST`, `INFILESIZE`, `INFILESIZE_LARGE`, the URL's `PORT`
  and `REQUEST_TARGET`, `CRLF` and `HEADER`, and all 23 `PROXY_` TLS options (ADR-0009,
  amended 2026-10-26, as built). Slice 3 added `PROXY`, the proxy field's, and its twins
  `NOPROXY`, `PRE_PROXY`, `PROXYPORT` and `PROXYTYPE` (ADR-0024, amended 2026-10-26). Slice 4
  added, from a review of all 200 options the hatch's types reach, each measured, decided by
  the maintainer: the twins `TRANSFERTEXT`, `USERPWD`, `USERNAME`, `PASSWORD`, `NETRC`, `HSTS`,
  `UNIX_SOCKET_PATH`, `ABSTRACT_UNIX_SOCKET`, `PROXYHEADER` and `HEADEROPT`; and, kept from the
  hatch though no twin, `RESUME_FROM`, `RESUME_FROM_LARGE`, `COOKIEFILE`, `COOKIEJAR`,
  `CONNECT_ONLY`, `DOH_URL`, `RESOLVE` and `SSLENGINE_DEFAULT`, all refused as `owned-option`
  (ADR-0009, amended 2026-10-27).
- **The test seam, `curl-engine-submit-with`, is retired into the hatch** (ADR-0009, amended
  2026-10-27). No submit takes options of its own.
- **Lifetimes.** Blobs are passed with `CURL_BLOB_COPY`, through a counted `struct curl_blob`
  native fills and frees as setopt returns. String lists are built by the binding on the
  engine's thread, counted as `slist`, and freed after the easy handle (ADR-0009, amended
  2026-10-27).

## Layout and names

- **One repository, `chez-curl`, with five libraries:** `(curl)`, `(curl private ...)`,
  `(curl unsupported)`, `(http-client)` and `(http-client private ...)` (ADR-0007,
  ADR-0010).
- **`make check-seam` guards the boundary, and `make test` runs it.** Tests are exempt
  (ADR-0007, amended).
  - No `(curl ...)` library imports `(http-client ...)`. An `(http-client ...)` library
    imports only `(curl)` from the low level. No `(curl ...)` library imports
    `(curl unsupported)` (rule (j); ADR-0009, amended 2026-10-27).
  - Every library under `src/` is in one of the two families.
  - A library imports only from allowlists: `(rnrs ...)` except `(rnrs eval)`, `(only
    (chezscheme) name ...)` with names from `allowed-chez-names`, and the two families.
    Adding to a list is a reviewed change.
  - A name in `library-only-chez-names` is imported only by the libraries listed with it:
    `define-ftype` by `(curl private layouts)`, `foreign-alloc` and `foreign-free` by
    `(curl private memory)`, `foreign-procedure`, `load-shared-object` and `ftype-set!`,
    which fills each `struct curl_blob`, by `(curl private native)`, `foreign-callable`,
    `foreign-callable-entry-point` and `lock-object` by `(curl private transfer)`, and
    `fork-thread` by `(curl private engine)`, each alone (ADR-0007, amended). test-check-seam
    writes the list's names out. No library imports
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
  - `current` runs the same against the current libcurl, vanilla 8.23.0 with OpenSSL, the
    newest release when it was pinned on 2026-10-26, built by `scripts/ci/build-curl.sh --current`, which pins that
    version itself: it is no floor. The job names no version, and fails unless `make build`
    loaded the one its build's `curl-config` reports (ADR-0020, amended 2026-10-26).
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
  the only libcurl call a caller's thread makes on an engine's handle (ADR-0012). Between its
  read and its poll the engine looks at its queue under its mutex, and skips the poll when a
  message is queued: Guix's 8.20.0 reads back, inside `curl_multi_perform`, a wakeup made
  before it, and the poll then waits up to 1000 ms (ADR-0012, amended 2026-10-30). A cancel
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
- **Completions reach callers through a mailbox the caller drains** (ADR-0021, from M4 slice
  2). A submit may name a mailbox and a callback. The completing thread appends the finished
  token to its mailbox, as data, under the mailbox's mutex, taken after the engine's, once, on
  its change to done, and never applies the callback. A caller's thread takes the next token,
  under a bound, by polling, and runs its callback. A take that escapes loses the notice, never
  the outcome, which stays on the token: a caller whose interrupt handlers can escape keeps its
  tokens (ADR-0021, amended 2026-10-26). A test asserts, inside a callback, that the thread is
  the delivering one, never the engine's.
- **The engine's thread leaves its signal mask alone** (ADR-0012, amended 2026-10-26, decided
  by the maintainer). On Linux every SIGINT sent to the process reached the main thread,
  though no thread blocked any signal, libcurl's resolver threads among them: the kernel
  offers it to the main thread first. On the Mac, 40 of 40 reached the main thread too, in a
  take and busy (2026-10-26).
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
  - so is every callback a `__collect_safe` call can invoke. The write and header callables fire
    inside `curl_multi_perform`, and inside `curl_easy_pause`'s replay, from M6;
  - `curl_easy_pause` blocks on nothing, but its replay runs the callables and libcurl's
    decoders, up to 21.6 ms for a gzip body: bound plain, it held another thread's collection
    until it returned. It is bound `__collect_safe` through `bind-blocking` (ADR-0013, amended
    2026-10-30);
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
- **A stalled name lookup does not stall the engine** (ADR-0019, amended 2026-10-25), from
  M3 slice 3:
  - every engine transfer sets `QUICK_EXIT` to 1 when the loaded libcurl knows it, looked up
    by name, with the pins;
  - every engine's multi handle sets `CURLMOPT_QUICK_EXIT` to 1 when it is made, through
    `curl_multi_setopt`. `CURLM_UNKNOWN_OPTION` is accepted, and any other answer refuses the
    engine;
  - the floor, 7.85.0 to 7.86.x, keeps the stall, up to glibc's resolver timeout;
  - `test-engine` shows each on Linux, under a stand-in `getaddrinfo` it compiles and
    preloads, with a control per setting where libcurl knows it: on 8.5.0 an engine
    without each transfer's `QUICK_EXIT` stalls, and on 8.20.0 one without
    `CURLMOPT_QUICK_EXIT`. On 8.20.0 a transfer's `QUICK_EXIT` changes no stall, so a count of
    the transfers that set it holds it there. CI's `current` lane loads a vanilla 8.23.0,
    built from source, so `CURLMOPT_QUICK_EXIT` runs there as well as in the Guix container
    (ADR-0020, amended 2026-10-26). A libcurl with no
    row of its verdicts fails by name. The checks do not run on macOS, which has no
    `LD_PRELOAD`; the Mac runs a probe instead.
- **Stopping an engine cancels what is in flight** (ADR-0012, amended 2026-10-24). Each queued
  and live transfer completes as `stopped`. The engine frees every handle and cleans up the
  multi handle, and the caller's stop returns once its thread has signalled its end. A later
  submit raises, and a later stop returns at once. A drain is the caller's: await, then stop.

## The high level

- **`(http-client)` reaches the low level through `(curl)` alone,** and holds no native object of
  its own (ADR-0007).
- **The verbs carry the `http-` prefix:** `http-get`, `http-head`, `http-post`, `http-put`,
  `http-patch`, `http-delete`, and `http-request`, which takes the method; each takes the
  session first (ADR-0025).
- **Every call takes an explicit session.** There is no default session, and the high level
  starts no thread a caller did not ask for. A session owns one engine, and
  `call-with-http-session` stops it when its procedure returns or escapes (ADR-0025).
- **A call's body is a bytevector, a string sent as UTF-8, or a form.** The form encoding is
  chez-curl's, `application/x-www-form-urlencoded`. No JSON (ADR-0025).
- **`params` reach the URL by `curl-url-append-query`:** the URL written from what
  `curl_url_get` gave back, a separator and the encoded part, then parsed whole by `curl_url`,
  which keeps the part's hex case on every libcurl, where setting a part does not; and its query
  read back, or `query-not-kept` (ADR-0028). Never `CURLU_APPENDQUERY`, and never a URL that
  `curl_url` has not parsed whole.
- **A redirect's fragment is set by `curl-url-with-fragment`:** the URL written from what
  `curl_url_get` gave back, `#` and the fragment, then parsed whole; a header's bytes encoded
  first, each byte at or below 0x20, 0x7F and each above as upper-case `%XX`, every other byte
  kept (ADR-0029). Never `curl_url_set` of the fragment part, which stores its bytes unchecked.
- **A call's drive winds with Chez's critical `dynamic-wind`,** `(dynamic-wind #t ...)`, so a
  second escape that lands in its after thunk cannot skip the cancel; the submit and the record
  of its token share one `critical-section`, with the guard that reads the submit's refusal
  inside it, so a Ctrl-C handler's raise as the section ends is never read as one (slice 3's
  fix round); and a call with interrupts off is refused before
  it submits, by `(curl)`'s own refusal of a wait there. A session's close waits, so it cannot
  wind critically: a second escape as it starts can leave the engine running, documented, not
  prevented (ADR-0025, amended 2026-10-27).
- **A bounded call gives each transfer the time left as its `timeout-ms`, and as its
  `connect-timeout-ms` when the caller gave none, capped at 300,000 ms:** libcurl's connect
  takes that default when none is set, so with more than 300 s left its 28 is not the bound's,
  and the cap keeps a bounded connect no longer than an unbounded one (the M5 plan, §3.5).
- **Retries are off unless the session or the call names a policy** (ADR-0026). Off means
  chez-curl adds no attempt: libcurl itself resends on a dead reused connection, and on an
  HTTP/2 stream refused, five times, a `post` among them (ADR-0026, amended 2026-10-28).
- **A retry that runs out reports its last transfer truly:** when the bound passes during a
  retry's wait or its next transfer and the retry sent nothing, the call answers the last
  response it retried, or raises the last failure; a retry that sent its request and met the
  bound raises its 28 with `&http-timeout`. A raised failure's request size speaks for its own
  transfer alone: with more than one transfer counted, an earlier one may have sent the
  request. A policy retries statuses from 400 to 599 alone (ADR-0026, amended 2026-10-28).
- **Only a transfer's own failure is its outcome:** the drive waits with `curl-token-wait`, with
  no guard around the wait, and reads a done token's outcome as data, by `curl-token-outcome`
  (ADR-0021, amended 2026-10-28). A raise the caller's interrupt handler makes during the wait
  leaves as raised, continuably, and the live token is cancelled on any escape.
- **A redirect from `https` to `http` is refused** as `&http-redirect-error`,
  `insecure-redirect`, unless the session or the call sets `allow-downgrade` (ADR-0027).
- **A redirect is followed from the first `Location` header's bytes,** encoded by ADR-0029's
  rule, then resolved by `curl_url_set` against the URL the transfer requested, never from
  `CURLINFO_REDIRECT_URL`, whose statuses and credentials move with the version.
  `FOLLOWLOCATION` stays owned and off (ADR-0008 and ADR-0023, amended 2026-10-27; ADR-0029,
  amended 2026-10-28). A URL function's answer that is not UTF-8 is refused, never decoded
  (ADR-0008, amended 2026-10-27).
- **An origin is the scheme, the host A to Z folded, its zone ID and the port,** each by
  `curl-url-part`: libcurl gives an IPv6 host without its zone, so a rule that compares hosts
  alone sends a call's credentials to another zone (ADR-0008, amended 2026-10-28).
- **A request group costs no thread, and is its thread's** (the M5 plan, §3.7): its calls
  share one mailbox, and whichever call the thread awaits drives them all. `go`, `http-await`,
  `http-pending-done?` and `http-pending-cancel` from another thread raise `&http-group-error`,
  `wrong-thread`, and `go` once the group's procedure has returned or escaped, `closed`.
- **Each token is stepped once:** a turn looks at every live token before it takes; a token is
  stepped only from the group's live set, taken out first, and any other notice is dropped; no
  guard surrounds a wait or a take, so a notice an escape loses, which ADR-0021 allows, is
  found by the next look (the M5 plan, §3.7).
- **Every change to a group's record is one critical section,** which waits for nothing but a
  mutex's brief hold: a step with what it submits, a due submit, a queued call's expiry, each
  admission, each entry, a cancel. A guard inside each call's section ends that call with
  whatever its own step or submit raises, so no raise strands a call where the join would wait
  for good; no interrupt handler runs there, so it reads only the code's own raises.
- **A group's join is two winds:** an inner critical one, whose after thunk closes the group,
  cancels every live token and ends every unended call, and an outer plain one, whose after
  thunk waits for every token to end. A second escape during that wait abandons it: documented,
  not prevented. An escape closes the group for good, a Chez engine's expiry among them: a
  resumed `go` that had not entered its call raises `closed`, once its entry's section has
  ended, and one resumed after its entry answers its pending, whose await raises `cancelled`;
  a resumed `http-parallel` enters no more. A refusal found inside a section is answered as
  data, and raised once the section ends, so a handler runs with interrupts on.
- **A slot is held from a call's first submit until it ends,** through its redirects, retries and
  waits; a call past the limit queues, first in, first out, on its own clock, and its deadline
  fails it without a slot.
- **`http-parallel` checks every spec before it submits any,** its keys and its first request by
  `curl-request-check`, so only an engine's stop or failure can refuse one mid-batch (ADR-0023,
  amended 2026-10-28). It answers responses only when every call is done; otherwise it raises
  the first failure, else the cancel of the first call in SPECS' order that is not done.
- **A caller's cancel exempts a call from the join's raise,** whatever the turns saw of it; the
  call keeps its answer, which its await still gives.

## Streams

- **A streamed body is a request's key, and the token's operations** (ADR-0030, from M6): the
  response's by `stream-buffer`, the request's by `body` `stream` with `body-length`. One
  `curl-submit` answers one kind of token. A request stays data: each submit makes its own
  stream.
- **One transfer, one request:** a request that streams its response refuses, as
  `&curl-request-error`, `stream-with-rounds`, every way libcurl makes a second request inside
  one transfer: the private `follow` field, the hatch's `HTTPAUTH` and `PROXYAUTH`, and a caller
  `Expect` header whose value holds `100-continue` anywhere, folded A to Z alone, whose 417
  libcurl answers with a resend. Each is refused by every path that puts the two together, and
  the header again at submit (the M6 plan, §3.2).
- **A streamed transfer's failure may be `pause-failed`,** `curl_easy_pause` having answered
  other than 0, a reason of no class (ADR-0012, amended 2026-10-29).
- **The callables only copy and signal** (ADR-0012, decision 4): the write callable fills a
  bounded buffer, and answers `CURL_WRITEFUNC_PAUSE` when it is full; the read callable gives
  what is buffered, never past `body-length`, and answers `CURL_READFUNC_PAUSE` when there is
  none; the header callable publishes the first final head; the seek and prerequest callables
  refuse a resend once a byte was handed. Each is `__collect_safe`, locked, in
  `(curl private transfer)` alone, under a guard that records what is raised. A reason a callable
  records wins over libcurl's code.
- **Resume is the engine's fourth message,** naming its token, never a handle, carried out
  after the cancels and before the perform for a token still live, by `curl_easy_pause` with the
  transfer's whole pause state, holding no mutex and outside any critical section. Any answer but
  0 fails the transfer,
  `pause-failed`: 7.85.0 and 8.5.0 lose a refusal made inside the replay, and end 0 (ADR-0012,
  amended 2026-10-29). The pause bits and the resume's flag live under the stream's mutex; the
  lock order is the engine's mutex, then a stream's (the M6 plan, §3.4).
- **The engine paces a poll that spins:** a poll under 1 ms, while a transfer is paused, in a
  turn that took no message and moved no byte, is followed by a sleep of 1 ms. Ubuntu's 8.5.0
  spins otherwise (ADR-0012, amended 2026-10-29).
- **Every stream wait is a bounded poll that answers as data,** and none raises the transfer's
  failure, which the token's outcome holds; the port alone raises it (ADR-0030, decision 4).
- **A take leaves what it took in place inside its hold, and removes it after,** the last thing
  before it returns, by writing fields the engine never writes, so a keyboard interrupt that
  escapes as the hold ends loses nothing; and **every look decides the resume,** not the take
  alone, since the write callable can pause in between. A put commits inside its hold, and
  `curl-token-body-count` tells what was committed (the M6 plan, §3.5; `traps.md`).
- **A port belongs to the thread that made it:** a read that reaches `read!`, or a close, from
  another raises `&curl-wrong-thread`; bytes Chez has already buffered are served to any thread,
  which no hook can see, and another thread's `get-bytevector-n`, `-n!` or `-all` that takes
  them, then raises at `read!`, loses them. Its close cancels its token, and its ends stick:
  0 at a response's end, the failure raised at a failure's, every time after. A raise from a
  read loses bytes inside `get-bytevector-n`, `-n!` and `-all`, never inside
  `get-bytevector-some`, `-some!` or `get-u8` (the M6 plan, §3.5).
- **A streamed body is sent at most once** (ADR-0032, amended 2026-10-29): `FRESH_CONNECT`,
  owned; a seek callable that refuses the rewind, and a prerequest callable that refuses a
  later attempt, once the read callable has handed libcurl a byte, each recording
  `body-not-replayable`. The high level calls a producer only once libcurl asks for the body,
  never retries such a call once its producer was called or libcurl had asked by a head, and
  raises `&http-redirect-error`, `body-not-replayable`, for every redirect whose next request
  keeps the body, as `body-dropped?` decides (ADR-0032, amended).
- **chez-curl counts a streamed body:** short of `body-length`, or past it, is
  `body-length-mismatch`, alike on every libcurl, where libcurl alone stalls, answers 26, or
  sends the surplus (ADR-0031). A put past the length raises `&curl-request-error`
  `body-length-mismatch`, and its transfer fails with `body-length-mismatch` unless another
  reason came first: the outcome reads the refusal too, since libcurl calls the read callable no
  more once it has read the length whole, and closes the request stream in that hold, so a put
  after answers `done` (ADR-0030, amended 2026-10-31). A put after `curl-token-end-body!` on a
  live token is an assertion violation.
- **A put answers `done` only once its token is done,** so its outcome is there to read.
- **The head tells whether libcurl had asked for the body by then,** `curl-head-body-asked?`,
  read in the hold that publishes the final head; the high level's at-most-once rule reads it
  (ADR-0030, amended 2026-10-31; ADR-0032, decision 3). It tells whether libcurl had asked,
  never a guess from the request: an answer that comes before the first ask reads `#f` on
  7.85.0 and 8.5.0, `#t` on 8.20.0 and 8.23.0, which ask with the head.
- **A call's `timeout-ms` bounds the whole call, a consumer's reading included** (ADR-0031).
- **Below the token the bound is libcurl's, and documented:** a paused HTTP/2 stream beside an
  active one keeps receiving, up to its flow-control window on the Linux libcurls (ADR-0030,
  decision 5).
- **On 8.7.0 and 8.7.1 the engine does not multiplex:** it sets `CURLMOPT_PIPELINING` to 0 on
  its multi handle, since on Apple's 8.7.1 a paused HTTP/2 stream beside an active one filled
  libcurl's 64 MiB cap and failed the connection, and a write callback's error on one stream
  failed its sibling (ADR-0030, amended 2026-10-29).
