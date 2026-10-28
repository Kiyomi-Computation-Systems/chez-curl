# Progress ledger

Where chez-curl stands. Read it with [global-constraints.md](global-constraints.md)
before starting slice work. When a slice merges, update **Now** and add a
close-out under **Close-outs**, newest first.

## Now

- **Milestone:** M5, the high level (brief §8), per the [M5 plan](2026-10-27-m5-plan.md),
  merged as PR #29 (`a66ef78`). Four slices: the session and the verbs; redirects; retries; the
  request group and `http-parallel`.
  - **Slice 1, the session and the verbs:** merged as PR #30 (`d0dd8e9`); its close-out is
    below.
  - **Slice 2, redirects,** is in progress on `feat/m5-slice-2`.
    - **Measured first** ([`research/m5/location/`](research/m5/location/)), on the five Linux
      libcurls: each of 64 `Location` cases, made by the C probe and through an engine with
      chez-curl's own header reading, agrees byte for byte, its resolution among it; setting a
      fragment part stores its bytes unchecked, a space and 0x01 raw, and moves its hex case
      by version, where the URL written and parsed whole answers alike; and `localhost`
      reaches the origin on all five (ADR-0008, amended 2026-10-28).
    - **Decided by the maintainer, 2026-10-28,** each the recommended option: a fragment is set
      by writing the URL and parsing it whole, a header's bytes encoded first
      ([ADR-0029](decisions/0029-fragment-written-then-parsed-whole.md), new); and, after the
      review below, a `Location`'s bytes are encoded the same way before they are resolved
      (ADR-0029, amended).
    - **Built:** `(curl)` gained `curl-url-resolve`, a string or a header's bytes, and
      `curl-url-with-fragment`, held by `test-url-location`, 222 tests, and its own rows file;
      and `curl-url-part` reads `zoneid`. `(http-client)` follows redirects by the plan's §3.4:
      the `redirects` and `allow-downgrade` keys, `&http-redirect-error`, the rules in the
      exchange's core, the history, and the shell following each redirect with the time left.
      `tests/origin.mjs` gained `/raw/location`, a `Location` written from its query's bytes,
      held by `test-origin`; `test-redirect`, 68 tests, holds the rules, live and by tables.
      README.org says what follows a redirect.
    - **Mutants:** 9 of mine on the URL functions, 9 on the redirect rules and 6 on the review's
      fixes, and the builder's 67, each failing a named test.
    - **Reviewed** (Opus, read-only): no blocker, two majors and nine minors. The majors: an
      absolute `Location` with a Latin-1 byte was refused as `not-utf-8` where a relative one
      was followed, which the maintainer settled by encoding a `Location`'s bytes; and the
      records still called a bytevector reference the UTF-8 rule's second exception, which
      the encoding makes none. Among the minors, each fixed and tested: two zones of one IPv6
      address read as one host, so credentials crossed them; `Expect` survived onto a request
      with no body; three rules no test failed without; and three records' claims, one a
      count, one backed by no kept log.
    - **Checks,** on the final tree: in the container, `make test` 30 of 30 and check-seam (21
      libraries); in Docker, the floor (7.85.0), main (8.5.0), gnutls and current (8.23.0)
      lanes 30 of 30 each, and the memory lane 30 of 30, with `check-memory-gate` 33 of 33.
      That full run failed `test-url-location` on 7.85.0 and 8.5.0 and under Valgrind, every
      other suite passing: its test that a string and bytes resolve alike held 0x01 and 0x7F,
      which a string sends raw and those versions refuse. I had run the suite after the
      encoding change in the container alone. The test now holds printable ASCII, and the suite
      passed on all five lanes and under Valgrind.
    - **Owed by the Mac:** the probes, `CHEZ=chez NODE="$(asdf which node)" sh
      .plans/research/m5/location/run.sh mac`, and `encoded.sh mac` and `zoneid.sh mac` with
      `CHEZ=chez`; and `test-url-location`'s 8.7.1 row, which `make test` prints there (the
      plan, §8).
  - **Measured first** ([`research/m5/redirect-url/`](research/m5/redirect-url/)), through a C
    probe that made each transfer as the engine does, `FOLLOWLOCATION` off, on five libcurls:
    Guix's 8.20.0 in the container, and in Docker 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with
    GnuTLS, and 8.23.0, 62 cases each. `CURLINFO_REDIRECT_URL` moves with the version: 7.85.0
    and 8.5.0 give it for a 3xx alone, 8.20.0 and 8.23.0 for any status with a `Location`;
    8.23.0 drops credentials from it; and every version hands back unparsed what `curl_url_set`
    refuses. Where it is a parsed URL, it is `curl_url_set`'s resolution of the first
    `Location`. So M5 resolves that header's bytes itself (ADR-0008 and ADR-0023, amended
    2026-10-27).
  - **Decided by the maintainer, 2026-10-27,** each the recommended option: the verbs carry the
    `http-` prefix; every call takes an explicit session; a body is bytes, a string or a form,
    with `params` for the query, and no JSON
    ([ADR-0025](decisions/0025-the-high-levels-surface.md), new); retries are off unless a
    session or a call asks ([ADR-0026](decisions/0026-retries-off-unless-asked.md), new); and,
    after the review below, a redirect from `https` to `http` is refused unless the caller
    allows it ([ADR-0027](decisions/0027-no-downgrade-unless-allowed.md), new).
  - **An adversarial review of the plan** (Opus, read-only), before it merged: one blocker,
    twelve majors and sixteen minors, each answered in the plan and its records. The blocker: a
    group that recovered a lost notice by reading `curl-token-done?` could step a token twice,
    and send a `post` twice; each token is now stepped once, from a set. Among the majors:
    libcurl itself resends any method on a dead reused connection, so "off" means chez-curl adds
    no attempt; on 8.7.x every transfer carries `#f`, so a `post` is never retried there; Chez's
    `random` draws one sequence in every process; a Latin-1 host comes back raw from
    `curl_url_get`, and is now refused, not decoded; `Host` and `Proxy-Authorization` are
    dropped across origins; and the downgrade, put to the maintainer. I checked its citations
    in the code and in curl's source, and reran its probes, which are kept in
    [`research/m5/review/`](research/m5/review/).
- **M4, the public records and the asynchronous API:** **done on 2026-10-27.** Its four slices
  are merged (PRs #25 to #28), per the [M4 plan](2026-10-26-m4-plan.md), and the Mac has run
  slice 4 (the M4 plan, §9), on `main` at `a66ef78`: `make test` passed 25 of 26 and printed
  test-unsupported's 8.7.1 blob row, added on `feat/m5-slice-1`; the hatch's sets, with Apple's
  LibreSSL and with SecureTransport; and 8.7.1's options table, 8.5.0's and
  `SERVER_RESPONSE_TIMEOUT_MS` (ADR-0009 and ADR-0018, amended 2026-10-27). Their close-outs
  are below.
  - **Carried into M5** (the M5 plan, §10): why a timeout's 28 came 1,014 ms late once
    (ADR-0019, amended 2026-10-25); the stall checks on macOS; the Mac's Node not exiting when
    its FIFO stdin closes; a curl bug report on 8.23.0's dead-connection reuse; accepting
    Apple's `OPENSSL_X509_TEA_DISABLE=1` in place of the keychain refusal, once when LibreSSL
    reads it is measured (ADR-0024, amended 2026-10-27); and CI has still never run.
- **M3, the engine:** **done on 2026-10-26.** Its three slices are merged (PRs #19, #20 and
  #21), PR #22 moved CI's `current` lane to curl 8.23.0, and the Mac has run both
  (M3 plan, §7). Their close-outs are below.
- **M2, one blocking request, plaintext and TLS:** its three slices are merged (PRs #13, #16
  and #17). Slice 3's close-out is below.
  - **M2 is done:** its last owed item, the Mac's first `test-transfer-tls` on
    SecureTransport, passed all 55 checks on 2026-10-26 (ADR-0018, amended). Its answer to
    clearing `CAPATH`, `CURLE_OK` or `CURLE_NOT_BUILT_IN`, the transfer takes either, so the
    run does not say which.

  M1 (brief §7) is built: PRs #10 and #11. M0 (brief §8) is built.
- **The Mac's run, 2026-10-23,** on the maintainer's M1:
  - the setup: macOS 26.7.1, Homebrew's Chez as `tarm64osx`, Apple's libcurl 8.7.1, and
    Node 20.10.0 through asdf;
  - `make check-variadic`: all 19 steps ok, and every arm64 step failed on its planted
    binding, by name (ADR-0001, amended);
  - `make test` on `main` at `ed217dc`: 18 of 20. `test-drift` and `test-url` lacked rows for
    8.7.1, which are now added;
  - so these have now run on macOS: the prototype check on Apple's SDK headers,
    `test-variadic`, `test-check-nothreads`, Node 20.10.0, and the drip's own-arrival check;
  - it needed `NODE="$(asdf which node)"`, because asdf 0.15's shim writes to stderr on every
    call (`traps.md`).
  - **Then `make test` on `mac/arm64-gate`** (PR #15, on top of #14): 20 of 20. So the two
    rows pass there, and so do #14's probe read and stop/continue checks under macOS's
    kqueue.
  - **The TLS checks there ran OpenSSL 3.6.3,** the first `openssl` on its `PATH`, not
    `/usr/bin/openssl`'s LibreSSL 3.3.6.
  - **With `OPENSSL=/usr/bin/openssl`, 17 checks failed:** LibreSSL's `s_client` polls
    stdin, and macOS's poll does not support `/dev/null`, so it exited 1, `poll error`.
    `s-client` now hands it an empty pipe (ADR-0005, amended). It passed on Linux with
    OpenSSL 3.5.7 and 3.0.13 and LibreSSL 3.3.6. Then on the Mac, with its LibreSSL,
    `test-verify`, `test-origin-tls` and `test-curl-testing` passed: 21, 88 and 276 checks.
- **Done:** slices 1 to 6 of the [harness plan](2026-10-04-harness-plan.md) (§6):
  - slice 1, the container and the Makefile skeleton;
  - slice 2, the test harness
    ([ADR-0015](decisions/0015-test-harness-and-scheme-dependencies.md));
  - slice 3, loading (ADR-0001, ADR-0002, ADR-0003, ADR-0007, all amended), with its
    [mutation log](loading-mutation-log.md);
  - slice 4, constants and layouts (ADR-0001, ADR-0007 and ADR-0013 amended, ADR-0016
    new), with its [mutation log](constants-mutation-log.md);
  - slice 5, the memory gate and CI (ADR-0014 amended), with its
    [mutation log](memory-ci-mutation-log.md);
  - slice 6, which closes M0: the variadic bindings, the binding-macro routes closed,
    `make dev` and `make clean` (ADR-0001, ADR-0007, ADR-0008 and ADR-0013 amended), with
    its [mutation log](variadic-mutation-log.md).
- **macOS runs:** on 2026-10-16, the first, with 13 suites, after a fix: a bare `mktemp -d`
  ignored `TMPDIR` there (`traps.md`). On 2026-10-23, the run above. Both were on Apple
  arm64. Linux on arm64 and macOS on amd64 have not run.
- **The flaky `reset-mid-body` row was the probe, not the origin** (ADR-0005, amended
  2026-10-23). libuv before 1.52, which Node 20.10.0 bundles, reports a reset as an end when
  it arrives with the last data. The probe now reads its socket's fd once on each
  end, and both origin suites stop the probe across a last write and a reset. Without the
  fix, that check failed on Node 20.10.0 in 2 runs of 2.
- **CI has never run.** Every job of PRs #8 to #15 was "not started because recent account payments
  have failed or your spending limit needs to be increased". GitHub parsed the workflow and
  listed all six jobs, so the file is valid. What only CI can show is still unshown: Chez
  built from its tarball on the runner, a real `--nothreads` Chez, the suites under Ubuntu's
  Valgrind 3.22, the floor lane at 7.85.0, and the jobs' times.
- **Decided for M2,** by the maintainer:
  - curl's URL verdicts vary by version, so the URL suite holds shared answers and a row
    per libcurl version (ADR-0008, amended 2026-10-19);
  - one checked wrapper owns every copy between a bytevector and foreign memory;
  - the counters become the leak gate, since Valgrind cannot see Chez's heap (ADR-0001,
    ADR-0014, amended).
- **Settled before slice 5:** the leak in the container. Loading libcurl there loses one
  block in Guix's glibc, and Ubuntu 24.04 loses nothing (`traps.md`). ADR-0014 now allows
  one suppression for it, passed in the container only.
- **No record is Proposed.** ADR-0013, the last, was accepted from spike E1 (M3 slice 1).
- **Settled for M3:** a first reference to `(curl)` from a second thread, made while the load
  runs, raises `cyclic dependency`. An engine loads first (ADR-0002, amended 2026-10-24).

## Close-outs

### 2026-10-28 — M5 slice 1: the session and the verbs (PR #30, `d0dd8e9`)

- **Measured first** ([`research/m5/url-parts/`](research/m5/url-parts/)), through C, on
  7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0: setting a query
  part changes its hex case, to lower on 7.85.0, 8.5.0 and 8.20.0 and to upper on 8.23.0,
  where a whole URL keeps it; libcurl decodes a host's `%XX`, so a UTF-8 string can come back as
  other bytes; and an empty user, password or query reads as `""` or absent by version
  (ADR-0008, amended 2026-10-27).
- **Decided by the maintainer, 2026-10-27,** each the recommended option: `params` are appended
  by writing the URL and parsing it whole
  ([ADR-0028](decisions/0028-params-written-then-parsed-whole.md), new); and a second escape as
  a session's close starts, which can leave its engine running, is documented, not prevented
  (ADR-0025, amended).
- **Built:** `(curl)` gained `curl-url-part` and `curl-url-append-query`, and every URL function
  refuses an answer that is not UTF-8, a submit's scheme check among them, held by
  `test-url-parts`, 159 tests, and its own rows file. `(http-client)` has sessions, the six
  verbs and `http-request`, the keys and their merge, the form encoding, `params`, the response,
  the conditions and the call's bound, with the exchange's functional core and the shell for
  one call, held by `test-http-client`, 72 tests. 35 mutants, the builder's, and 11 of mine each
  fail `test-http-client`; deleting either of `appended-url`'s two branches no libcurl reaches
  fails `test-url-parts`.
- **Reviewed twice** (Opus, read-only). The first review found no blocker and two majors: a
  bound over 300 s misread libcurl's own connect default as its own, and a second escape in the
  drive's after thunk skipped the cancel. The scoped review of those fixes found two more:
  compounding every condition broke a handler's resumable raise, and the connect fill lifted
  libcurl's 300 s cap. Each is fixed and tested, and their minors too.
- **Checks,** on the final tree: in the container, `make test` 28 of 28 and check-seam (21
  libraries); in Docker, the floor (7.85.0), main (8.5.0), gnutls and current (8.23.0) lanes 28
  of 28 each, and the memory lane 28 of 28 twice, with `check-memory-gate` 33 of 33. The memory
  lane found two test traps under Valgrind, each measured and fixed in the suite: a collection
  inside `test-engine`'s 50 ms window ([research](research/m5/valgrind-collect/)), and a sleep
  of no time that starved the flip tests' second thread
  ([research](research/m5/valgrind-yield/)).
- **The Mac ran it, 2026-10-28,** on `fa51098`: `make test` passed 27 of 28, every suite but
  `test-url-parts`, which printed its 8.7.1 row, 8.5.0's, added before the merge; and the
  URL-parts probe answered all 103 lines as 8.5.0 did. It also ran M4's owed checks on `main`,
  which closed M4 (Now, above).
- **Three subagents:**

  | Agent | Model | Tokens | Time |
  |---|---|---|---|
  | builder, the build and two fix rounds | Opus | 663k | 67 + 37 + 47 min |
  | adversarial review | Opus | 398k | 27 min |
  | scoped review of the fixes | Opus | 359k | 30 min |
- **Learned:**
  - measuring first changed the design twice: `CURLU_APPENDQUERY`'s hex case became ADR-0028,
    and a host's decoded `%XX` brought the `not-utf-8` rule into slice 1, for strings too;
  - a fix brief is design: "compound every condition" and "the time left as the connect
    timeout" were mine, written from the finding rather than from what else each would reach,
    and the scoped review found each broke something;
  - counts went into the records before they were counted, again: 59 of 62 for 56, 16 lines for
    11, and 157 tests for 159, each caught on a reread;
  - a failure seen only on the branch is the branch's until a run on `main` says otherwise: both
    memory-lane flakes were this slice's allocation and timing, found by counting what happened
    inside the test.

### 2026-10-27 — M4 slice 4: the hatch (PR #28, `d8e1225`)

- **Measured first** ([`research/m4/slice4/`](research/m4/slice4/)), through a C probe on
  the multi interface with chez-curl's pins, on five libcurls: Guix's 8.20.0 in the
  container, and in Docker 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, and
  8.23.0. A blob with `CURL_BLOB_COPY` and a string list freed after the easy handle left
  Valgrind clean on all five, each control caught. An Opus review classed the 200 options
  the hatch's types reach from curl's docs and source; the probe measured what the source
  could not settle (the plan, §7.1; ADR-0009, amended 2026-10-27).
- **Decided by the maintainer, 2026-10-27:** 18 more options are owned, by id: ten twins,
  `TRANSFERTEXT`, the URL's credentials and `HSTS`, the two socket options, `PROXYHEADER`
  and `HEADEROPT`; and eight kept from the hatch, which read stdin, write stdout, send
  nothing, skip the proxy field or reach later requests. `VERBOSE` and `NOPROGRESS` stay;
  only libcurl's own `"-"` modes are refused; one reason, `owned-option`, covers all.
- **Built:** `(curl unsupported)` exports `curl-request-with-options`; a request keeps
  checked copies of its options, and the engine sets them last; blobs through a counted
  `struct curl_blob` native fills, string lists counted and freed after the easy handle;
  check-seam's rule (j) and `ftype-set!` for native alone; `test-unsupported`; the test
  seam retired, each check that used it accounted for (ADR-0009, amended 2026-10-27).
- **The slice's review** (Opus, read-only) found no blocker and one major, proved in a
  copy: rule (j) closes the route through `(curl unsupported)` alone, since the procedure
  is `(curl private transfer)`'s export too, and a re-export from `(curl)` under another
  name passed check-seam and test-unsupported. test-unsupported now holds `(curl)`'s
  exports by what each is bound to, and the records say what rule (j) does. Its minors:
  the option cache's copy of a name could not be seen through the hatch, which copies
  first, and is now tested through `option-named`; and test-unsupported has no 8.7.1 blob
  row, so the Mac's `make test` fails it, printing the row, until that row is added (the
  plan, §8).
- **Checks:** on the final tree, in the container, `make test` 26 of 26, and the two
  suites the review's fixes changed under the memory gate; before those fixes, `make
  test-memory` 26 of 26. In Docker, on the final tree and before the fixes, the main
  (8.5.0), gnutls, floor (7.85.0) and current (8.23.0) lanes 26 of 26 each, and the memory
  lane 26 of 26 with `check-memory-gate` 33 of 33. The [mutation log](hatch-mutation-log.md): 39 mutants over three sweeps, 38
  failing a named check, three of them only after a fix, one the slice's own sweep found
  and two the review's, and one equivalent.
- **Two subagents:**

  | Agent | Model | Tokens | Time |
  |---|---|---|---|
  | twin review of the 200 options | Opus | 468k | 38 min |
  | adversarial review | Opus | 230k | 16 min |
- **Merged before the Mac ran it,** at the maintainer's call: the Mac's runs are owed (Now,
  above), and test-unsupported fails there until its 8.7.1 blob row is added.
- **Learned:**
  - a rule that closes one route reads as closing them all: rule (j) kept `(curl)` from
    importing the hatch, and the records said `(curl)` could not export it, until the review
    re-exported the procedure from `(curl private transfer)` under another name;
  - a check of an order held by one element cannot see the order: test-check-nothreads
    sorted per directory and passed until a second public library arrived (`traps.md`);
  - a source reading is a hypothesis: the twin review's reading of `RESUME_FROM` in 8.20.0's
    source was wrong, and the probe measured 43 there;
  - counts went into the records from memory again, "six libcurls" for five, and README
    overclaimed what `VERBOSE` writes and what `/dev/stdin` reads, each caught on a reread.

### 2026-10-27 — M4 slice 3: the environment (PR #27, `9c8fdb0`)

- **Measured first** ([`research/m4/slice3/`](research/m4/slice3/)), through a C probe
  with chez-curl's TLS settings, on seven lanes: Guix's 8.20.0 in the container, and in
  Docker 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, 8.23.0, and Guix's 8.20.0
  and 8.6.0 loaded from the store beside Ubuntu's libc. Guix's patch reads the variables
  at `curl_global_init` alone, an empty one as unset; Guix's 8.6.0 lets a CA file win;
  GnuTLS takes `pkcs11:` in all sixteen ASCII cases, a file of that name there or not; an
  `https://` proxy is verified against the system store whatever the request says; and a
  Guix libcurl loaded outside Guix still overrides, so its own mapped file decides, not
  libc's world (the plan, §6.1; ADR-0024, amended).
- **Decided by the maintainer, 2026-10-26:** Guix's 8.6.0 stays taken to override, since
  no lane runs it; and, after the review, a libcurl is Guix's when its file is under
  `/gnu/store/` or holds the patch's literal `SSL_CERT_FILE`, which both Guix builds hold
  and six stock builds do not (ADR-0024, amended).
- **Built:** the native layer records the libcurl's mapped file, whether it holds the
  patch's literal, and the two variables, at the load; a submit refuses a CA file,
  verification on, on a Guix libcurl with either set, naming each, by a pure rule held on
  every lane; `pkcs11:` refused in any ASCII case, at the request and at submit; the
  `proxy` key, `environment` or `#f`, `PROXY` owned with four twins; the origin routes an
  absolute-form target, so its http face stands in for a proxy; README.org names what a
  transfer reads.
- **The slice's review** (Opus, read-only) found no blocker and two majors, each proved
  in a copy of the tree. A native that read the variables again at each submit passed
  every lane but the Guix container: the pin's child printed native's record before
  changing the environment, and now prints it after. And a copy of Guix's 8.20.0 loaded
  from outside the store replaced the CA file unrefused: the key above. Its fourteen
  minors were answered, the records' overclaims among them: "every ASCII case" rested on
  six of sixteen, now all measured, and two probes' findings had been run together.
- **Checks:** on the final tree, in the container, `make test` and `make test-memory` 25
  of 25; in Docker, the main (8.5.0), gnutls, floor (7.85.0) and current (8.23.0) lanes 25
  of 25 each, and the memory lane 25 of 25 with `check-memory-gate` 33 of 33, after each
  round of fixes. The [mutation log](environment-mutation-log.md): 54 mutants over five
  sweeps, 53 failing a named check, the reviews' gaps among them, and one equivalent.
- **Two subagents:**

  | Agent | Model | Tokens | Time |
  |---|---|---|---|
  | adversarial review | Opus | 289k | 21 min |
  | review of the Mac's follow-up | Opus | 285k | 21 min |
- **The Mac ran the PR, 2026-10-27:** the plan's proxy probe answered as on Linux; the
  environment's sets showed Apple's 8.7.1 ignoring `SSL_CERT_FILE` and reading every
  `pkcs11:` path as a file. Two findings followed, each measured and then decided by the
  maintainer:
  - Apple's 8.7.1 puts LibreSSL in use at its init, not SecureTransport, as ADR-0018 had
    read before the init; its keychain fallback undid a CA file for `https://example.com/`,
    through chez-curl too, where SecureTransport kept it. A submit now refuses a CA file
    there, and make runs the suites with `CURL_SSL_BACKEND=secure-transport` on macOS
    (ADR-0024 and ADR-0018, amended 2026-10-27);
  - `make test` failed slice 1's request-size check, its first Mac run: upstream 8.7.0 and
    8.7.1 count 0 for every transfer, 8.6.0 and 8.8.0 do not. A transfer that ran on them
    now carries `#f` (ADR-0022, amended 2026-10-27).
- **A second review** (Opus, read-only) of that work found one blocker: test-request's
  connect-timeout row still expected 0 where 8.7.1 now answers `#f`, which the Mac would
  have failed; test-engine's stalled rows had the same, on Linux alone. Its majors: curl
  names SecureTransport `secure-transport`, and `securetransport` reached it only by the
  fallback an unknown name takes; and three mutants passed every Linux lane, a backend read
  before the init, one never read, and `finish-transfer` reading libcurl's count past
  `ran-request-size`. A MultiSSL decoy, a check of the backend on every lane, and a
  source check now fail each. Its minors were answered: the keychain rule now keys on
  Apple's own libcurl, and refuses where the backend cannot be read; `backend-in-use`
  strips parenthesised groups, so a version with spaces stays whole; the records cite
  curl's own release notes for 8.8.0's fix.
- **The Mac's third run, 2026-10-27:** `make test` 25 of 25, its TLS suites on
  SecureTransport for the first time. `secure-transport` reached SecureTransport by name,
  and `securetransport` and a name no backend has by curl's fallback. With
  `OPENSSL_X509_TEA_DISABLE=1`, LibreSSL kept the CA file the only anchor: Apple's keychain
  fallback is what undid it. **Decided by the maintainer:** that variable is carried past
  slice 3, its timing measured first; the refusal stays, erring toward refusing (ADR-0024,
  amended 2026-10-27).
- **The Mac's Node did not exit when its FIFO stdin closed,** in every slice 3 run, four
  times; the runners' watchdogs ended it 5 s on. Its cause is still unmeasured.
- **Learned:**
  - facts went into code and records from memory again: `securetransport` for curl's
    `secure-transport`, "eleven" 8.6.0 builds for ten, and the host's 7.81.0 libcurls called
    Ubuntu's 8.5.0, each caught later by a review or a reread;
  - a fix to one failing check of a value whose meaning changed left its siblings: the
    request size's other 0 expectations stood until the second review found them;
  - slice 1's version-sensitive check never ran on the Mac until this slice, so the 8.7.x
    request size surfaced two slices late, and changed slice 1's public answer;
  - mutation sweeps found kills resting on one lane, the Guix container's and the Mac's, and
    shaped the design: a pure rule every lane runs, and a thin reading the suite holds as
    source.

### 2026-10-26 — M4 slice 2: the asynchronous API (PR #26, `b88f778`)

- **Measured first** ([`research/m4/slice2/`](research/m4/slice2/)), on a prototype of the
  take and the append, in the container (8.20.0) and in Docker `ubuntu:24.04` (8.5.0,
  Valgrind 3.22): where a SIGINT to the process lands, 160 of 160 on the main thread, no
  thread blocking any signal; a take's delay from completion, 0 to 9.6 ms, Valgrind or not;
  and an interrupt handler that escapes as a take's critical section ends, which loses the
  notice and keeps the outcome (the plan, §5.1; ADR-0021, amended).
- **Decided by the maintainer, 2026-10-26:** the engine's thread leaves its signal mask
  alone. The Mac ran the SIGINT probe on the PR: 40 of 40 on the main thread, so the decision
  stands (ADR-0012, amended).
- **Built:** `(curl)` exports the engine, `curl-submit` with an optional mailbox and
  callback, the token with `curl-token-wait`, and the mailbox's take and delivery, with
  `&curl-engine-error`; a wait's last sleep stops at its bound; `test-mailbox`, 25 checks,
  the escape planted in a child as the measurement planted it, through a private seam that
  holds the mailbox's mutex.
- **The slice's review** (Opus, read-only) found no blocker. Its major: every wait in the
  suite was timed only where it ran out, and a wait that slept out its whole bound after one
  empty read passed all 24 checks, which it ran in a copy. A take, a delivery and a token's
  wait now each return once a 300 ms transfer ends. Its eight minors were answered.
- **Checks:** in the container, `make test` 25 of 25 and `test-mailbox` under Valgrind;
  before the review's fixes, `make test-memory` 25 of 25. In Docker, the main, gnutls, floor
  and current lanes 25 of 25 each, and the memory lane 25 of 25 with `check-memory-gate` 33 of
  33, before and after the fixes. The [mutation log](mailbox-mutation-log.md): 25 mutants, 24
  failing a named check, and a wait's read after its bound, with a cancel's append, left
  unchecked, each for its reason.
- **One subagent:**

  | Agent | Model | Tokens | Time |
  |---|---|---|---|
  | adversarial review | Opus | 287k | 17 min |
- **The Mac's runner hung** after its 40 of 40, waiting with no bound for the origin, whose
  FIFO stdin had closed. The wait now has one; why the origin did not exit is unmeasured.
- **Learned:**
  - a belief went into a record before its measurement, as in slice 1: a draft of ADR-0012
    said Chez's threads block no signal, from belief, until the masks were read from
    `/proc`, before the merge;
  - a probe and a check were built from arithmetic: the delay probe paused in multiples of
    the period it measured, and the clamp check rested on a computed read time, so it passed
    either way. The numbers and the sweep caught both, after the fact (`traps.md`);
  - the mutants shared the author's blind spots: none timed a wait that receives its token,
    and the review's one oversleep mutant passed every check;
  - three listed traps were broken again: a top-level raise that killed the suite, a mutex
    held outside a critical section in the escape child, and an unbounded wait in the Mac's
    runner.

### 2026-10-26 — M4 slice 1: the public request, its body and the classes (PR #25, `7629a91`)

- **Measured first** ([`research/m4/slice1/`](research/m4/slice1/)), on 7.85.0, Ubuntu's
  8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0: what each method's body
  sends, byte for byte; what takes libcurl's own `Content-Type` and `Expect` away; that the
  connect timeout ends a TLS handshake the server never answers; the codes the scenarios
  reach; the timings; and the options tables (the plan, §4.1).
- **Decided by the maintainer, 2026-10-26:** a failed transfer carries its request size,
  `CURLINFO_REQUEST_SIZE`, not its timings, which on a failure move with the version
  (ADR-0022, amended).
- **Built:** `make-curl-request` and `curl-request-with` from a property list, and the
  response with its timings, exported from `(curl)` with every condition a caller can meet
  and the six classes (ADR-0022, ADR-0023, amended); bodies for `post`, `put`, `patch` and
  `delete`, an empty one a block of one byte, never NULL; `Content-Type:` and `Expect:`
  beside a body; the connect timeout; `FOLLOWLOCATION` owned, with a private `follow` field
  for the redirect tests; the owned options and their twins, read from the options tables,
  `PORT`, `REQUEST_TARGET` and the 23 proxy TLS options among them (ADR-0009, amended);
  every classed code a constant, 100 and 101 gated.
- **The slice's review** (Opus, read-only) predicted, from libcurl's source, the one
  failure the `current` lane then showed: the request size sums every attempt, and 8.23.0
  resends a head after a dead reused connection, 150 for 75. Each request-size check now
  runs on an engine of its own (ADR-0022, amended). It also found `CRLF` and `HEADER`
  unowned, now owned, and ten minors, each answered in the code or the records.
- **Checks:** in the container, `make test` and `make test-memory` 24 of 24; in Docker, the
  main (8.5.0), gnutls, floor (7.85.0) and current (8.23.0) lanes 24 of 24 each, and the
  memory lane 24 of 24 with `check-memory-gate` 33 of 33, after the connect timeout's
  bound was widened for Valgrind, which took 990 ms there; the
  [mutation log](request-mutation-log.md), 38 mutants, each failing a named check.
- **Two subagents, both Opus:**

  | Agent | Tokens | Time |
  |---|---|---|
  | the transfer and engine suites moved to the request, in a tree copy | 339k | 20 min |
  | adversarial review | 396k | 23 min |
- **Learned:**
  - a measurement holds under the conditions it ran in: the request size came from a fresh
    handle per transfer, and the suites pool connections, so a value asserted from it failed
    on 8.23.0 (`traps.md`);
  - a timing bound from the review was taken without asking what the memory lane measures,
    and failed there at 990 ms;
  - the mutation runner reported `done` after 5 of 27, its list eaten by `guix-env`'s stdin
    (`traps.md`);
  - three of the records' statements, the empty body's reason, "copied twice" and the
    refusals' order, came from the intent, not the code; the review caught each.

### 2026-10-26 — the M4 plan, revised after its review (PR #24, `73a536c`)

- **An adversarial review of the plan,** Opus, read-only: 420k tokens, 103 tool calls, about 30
  minutes. One blocker, thirteen majors, ten minors, each answered in the plan and its records,
  amended "after the plan's review":
  - **the blocker:** a take that escapes loses a notice, never an outcome (ADR-0021, amended);
  - **redirects:** through a 301, 302 or 303 libcurl resends a custom method without its body;
    `FOLLOWLOCATION` is owned and left off (ADR-0023, amended);
  - **the classes** described in curl's words, 18 with 52, 55 and 56, the redirects class
    dropped (ADR-0022, amended);
  - **Guix's override** keyed by the store path (ADR-0024, amended).
- **Decided by the maintainer:** a proxy's TLS stays libcurl's verified default until M7, and
  every proxy TLS option is owned (ADR-0024 and ADR-0009, amended).
- **Checked:** I read its cited lines and reran its redirect probe in the container, which
  matched its log line for line; the probe is kept in
  [`research/m4/redirect/`](research/m4/redirect/).
- **Checks:** docs only. `test-collect-safe`, 120 of 120.
- **Learned:** the plan merged before its review, so two PRs carried one plan; a claim that a
  condition was raised nowhere came from a search cut short by `head`.

### 2026-10-26 — the M4 plan, and the four records it rests on (PR #23, `d9bbb56`)

- **The [M4 plan](2026-10-26-m4-plan.md):** M4 makes the low level public, in four slices: the
  request, its body and the classes; the asynchronous API; the environment; the hatch.
- **Decided by the maintainer,** each the recommended option:
  - completions reach callers through a mailbox the caller drains
    ([ADR-0021](decisions/0021-completions-through-a-mailbox.md), new; ADR-0012 amended);
  - libcurl's codes are classed as condition types, the class following the code
    ([ADR-0022](decisions/0022-codes-classed-as-condition-types.md), new);
  - the public request is made from a property list, after chez-cmark-gfm's options, and
    carries a whole body ([ADR-0023](decisions/0023-the-public-request.md), new);
  - the environment: proxy variables honoured, with a field to turn them off; a CA-file request
    refused where Guix's override would replace it; `SSLKEYLOGFILE` and `OPENSSL_CONF`
    documented; a `pkcs11:` CA path refused
    ([ADR-0024](decisions/0024-what-a-transfer-reads-from-its-environment.md), new; ADR-0018
    amended).
- **Measured first:** the proxy variables on five Linux libcurls, all alike
  ([research](research/m4/proxy/)); a refused CONNECT, 56 on 7.85.0 and 8.5.0 and 7 from
  8.20.0; and the codes the floor's and 8.23.0's headers name.
- **Also:** PR #22's close-out; M4's rules in global-constraints; the brief's status line.
- **Checks:** docs only. `test-collect-safe`, which quotes the records, 120 of 120, with
  `check-suites`, `check-seam` and `check-floors`.
- **No subagents.** The plan's review came after the merge, at the maintainer's request, and
  its revisions are on the next branch.

### 2026-10-26 — the `current` lane moves to curl 8.23.0, and M3 is done (PR #22, `907d524`)

- **The `current` lane builds curl 8.23.0,** the newest release, as ADR-0020 owed (amended
  2026-10-26). `build-curl.sh --current` pins it and its sum, its configure line read again
  against 8.23.0's `./configure --help`, and `test-check-floors` holds the version. The
  container keeps 8.20.0's rows running.
- **`test-engine`'s hang there was the suite's.** "Two caller threads awaiting together" let a
  raise kill both threads, and waited for them with no bound. Each thread's raise is now its
  answer, and the wait polls under a bound: on 8.23.0 the check failed by name, 55 on both
  threads, instead of hanging. `test-curl-testing`'s capture threads had the same class, which
  the review found: they now guard their whole bodies, and its wait is bounded.
- **Why 55: 8.23.0 reuses, without checking it, a connection that went back to its pool under
  1 s before, however old** (`lib/conncache.c`). The raw face closes each drip's connection
  unannounced. With six such connections back in the pool, the next transfer retries on each
  dead one and gives up, "Connection died, tried 5 times before giving up". Measured with a
  probe, 2 runs of 2: five pass, six and eight fail, and a 1.1 s pause passes; 8.20.0 always
  passes.
- **Decided by the maintainer** (ADR-0020, amended 2026-10-26):
  - 8.23.0 replaces 8.20.0 in the lane;
  - checks that run drips together each get an engine of their own, and `test-engine` pins the
    reuse by version, `reuse-verdicts`: on 8.23.0, 55 and its error buffer's text; an answer
    on 7.85.0, 8.5.0, 8.7.1 and 8.20.0. The check asserts the eight drips were live together.
- **The rows:** `test-drift`, `test-url` (two verdicts moved: 25 and 21, where 8.20.0 gave 3),
  `test-transfer`, `test-variadic`, and `test-engine`'s stall and reuse rows. The NUL-in-header
  text 8.23.0 capitalised is a version row's answer now: `known-transfer-verdicts.sexp` gains a
  second kind of case, `error-text`.
- **Checks,** on the final tree unless said:
  - in the container: `make test` 23/23 (2,393 checks), `test-memory` 23/23, `check-variadic`
    29/29, `check-test-fails` 11/11, `check-suites`, `check-seam`, `check-floors`,
    `check-help`, `check-dev` and `check-clean`; `check-memory-gate` 39/39 before the review's
    fixes, which touched none of its inputs;
  - in Docker: the `current` job's step, 23/23 on 8.23.0 as the real script built it; main
    23/23 with `check-variadic` 29/29; memory, `check-memory-gate` 33/33 and `test-memory`
    23/23. Gnutls and the floor passed 23/23 before the review's fixes, and `test-engine` after
    them, with vanilla 8.20.0 and Ubuntu's 8.5.0;
  - the measurements and the review's probe are kept in [`research/reuse/`](research/reuse/).
- **The [mutation log](curl-8.23-mutation-log.md):** 20 mutants, then 11 after the review. Two
  pass, by design, each recorded with why: the two-thread check's own engine, which guards
  against a later check, and the control for the overlap assertion.
- **One subagent:** the read-only adversarial review, Opus, 297k tokens, 24 minutes. It found
  the 1 s rule stated wrong, a pin that needed its drips to overlap with nothing holding that,
  55 pinned without its text, the hang's class in `test-curl-testing`, an answer shape not held
  whole, and stale records. Each is fixed (ADR-0020, amended, "After the slice's review").
- **The Mac's run, 2026-10-26,** on the maintainer's M1, on the slice's branch (Homebrew's Chez
  10.4.1, Apple's libcurl 8.7.1):
  - `make test`: 21 of 23, the two failures the rows it printed, then added: `("8.7.1" 0)` for
    `minus-one-rows` and `("8.7.1" (response 200 "abcd"))` for `reuse-verdicts`.
    `test-transfer-tls` passed all 55 checks on SecureTransport, its first run there (ADR-0018,
    amended 2026-10-26), so M2 is done too; and `test-transfer` its 8.7.1 row with the
    `error-text` case;
  - the stall probe: the stand-in reaches Apple's resolver through `DYLD_INSERT_LIBRARIES`,
    8.7.1 stalls as 8.5.0 does, and `QUICK_EXIT` ends it (ADR-0019, amended 2026-10-26, which
    leaves running the checks on macOS to the maintainer); 8.7.1 answers no long multi option
    by its value, and `MAX_TOTAL_CONNECTIONS` 1 serialises two drips there (ADR-0001, amended
    2026-10-26);
  - `make check-variadic` at `27c12ca`: all 29 steps ok on `tarm64osx`, so its multi mutant
    failed `test-variadic` by name through `curl-multi-setopt-long` (ADR-0001, amended
    2026-10-26).
- **So M3 is done** (M3 plan, §7): slice 3 is merged, and the Mac has run both.
- **Carried:** whether the engine's thread blocks SIGINT; the 1,014 ms timeout; the stall checks
  on macOS; a curl bug report on 8.23.0's reuse, offered; CI has still never run.

### 2026-10-26 — M3 slice 3: stalled lookups, and a CI lane on curl 8.20.0 (PR #21, `874b3ae`)

- **A stalled name lookup no longer stalls the engine** where libcurl knows the options
  (ADR-0019, amended four times):
  - **transfer:** `QUICK_EXIT` at 1 with the pins, computed as data by `pinned-settings`,
    counted once libcurl takes it, and owned (ADR-0009, amended);
  - **engine:** `CURLMOPT_QUICK_EXIT` at 1 on each multi handle; `CURLM_UNKNOWN_OPTION`
    taken, any other answer refuses the engine. Private switches leave either out, or plant
    the answer, for the controls;
  - **native and constants:** `curl_multi_setopt` for a long, through `bind-variadic`; the
    newer constant checked behind a version gate with a presence probe.
- **The stall checks,** in `test-engine` on Linux: a stand-in `getaddrinfo`, compiled and
  preloaded, and a child judged against its log, with a row of verdicts per libcurl and a
  control per setting. The floor keeps its stall, the recorded limit.
- **The variadic checks:** libcurl 7.85.0 and 8.5.0 answer no long multi option by its value,
  so `test-variadic` watches `curl_multi_setopt` by behaviour, two drips serialised at
  `MAX_TOTAL_CONNECTIONS` 1, judged by their gap; `check-variadic` gained its sixth mutant,
  29 steps (ADR-0001, amended).
- **Decided by the maintainer:** the stall checks on Linux alone, with a probe for the Mac;
  the behavioural check for `curl_multi_setopt`; and a CI lane on vanilla 8.20.0, built by
  `build-curl.sh --current` (ADR-0020, new), with 8.23.0 left to a slice of its own.
- **Checks:** in the container, `make test` 23/23, `test-memory` 23/23, `check-variadic`
  29/29, `check-memory-gate` 39/39 and the other checks; in Docker, the main, gnutls, floor
  and memory lanes, each 23/23, and the `current` job's step, 23/23 on the real script's
  build.
- **The [mutation log](stall-mutation-log.md):** my sweep of 24 mutants, three of which passed
  until their gaps were closed, the review's seven, the constants agent's 18 and the variadic
  agent's 13, with five of `check-variadic`'s own; and four for the lane.
- **Three subagents, all Opus:**

  | Agent | Tokens | Time |
  |---|---|---|
  | constants version gate, in a tree copy | 219k | 14 min |
  | variadic checks, in a tree copy | 281k | 25 min |
  | adversarial review | 365k | 32 min |

  The review found the engine's refusal path held by nothing, two stops never judged, a
  bound that failed under Valgrind, 8.20.0's leftover resolver threads, and no CI lane on
  8.20.0, which led to the lane.
- **Carried:** the Mac's run; whether the engine's thread blocks SIGINT; the 1,014 ms
  timeout, unexplained; curl 8.23.0, with `test-engine`'s hang there; CI has never run.

### 2026-10-25 — M3 slice 2: the engine (PR #20, `bc53947`)

- **`(curl private engine)`:** one Chez thread per engine, which owns a multi handle and a slot
  block, and runs the transfers other threads submit. Submit, cancel and stop are messages,
  queued under the engine's mutex, then `curl_multi_wakeup`. The loop has six steps. A raise
  inside it fails the engine, which completes every token. Faults can be planted, as data, at
  eight steps.
- **native** records each handle's thread, and every exported procedure that takes one checks
  it, raising `&curl-wrong-thread`. The multi interface is bound, the four calls that can block
  through `bind-blocking`. `curl_easy_perform` is gone, and with it the `curl_easy_cleanup`
  wait spike E1 found.
- **transfer:** a submit takes a checked plan on the caller's thread, and the engine's thread
  starts, finishes and frees the transfer. The callable logs each chunk, and a request's fault
  is data. `test-transfer` and `test-transfer-tls` run every scenario through an engine;
  `transfer-escapes` retired.
- **Decided by the maintainer, twice, on the waits:** first, waits whose mutex a critical
  `dynamic-wind` held. The slice's review hung that design with four caller threads within
  1 s. Then polling waits, which hold no mutex while they sleep (ADR-0013, amended 2026-10-25,
  twice).
- **Found, and recorded:**
  - a wait inside a critical section stalls every other thread's collection;
  - a program runs the load before its first line, so the plan's load check could not fail,
    and was dropped (ADR-0002, amended);
  - a slot block made per call raced the counts, so the engine holds one (ADR-0014, amended);
  - a wait with interrupts off deadlocks, so the engine refuses one.
- **Measured first** (plan, §5.1): the thread check costs 43 ns; under the gate's Valgrind a
  polling engine leaves other threads their turn; on the four Linux libcurls,
  `curl_multi_info_read` reads no message for a removed handle.
- **Checks:** in the container, `make test` 23/23 (2,333 checks), `test-memory` 23/23,
  `check-test-fails`, `check-variadic`, `check-memory-gate`, `check-dev` and `check-clean`; in
  Docker, the main, gnutls, floor (7.85.0, Node 20.10.0) and memory lanes; `test-engine` 5
  runs of 5.
- **The [mutation log](engine-mutation-log.md):** two sweeps, the second of 35 mutants, each
  failing a named check, and the conversion agent's 23.
- **Three subagents, all Opus:**
  - the conversion of the transfer suites, 491k tokens, 43 minutes. It found the slot race;
  - the adversarial review, 316k, 35 minutes. It found the deadlock;
  - a scoped review of polling waits, 274k, 23 minutes. It found numbers no check held, and
    the deadlock a wait with interrupts off makes.
- **Carried into slice 3:** stalled lookups and the two `QUICK_EXIT` options; whether the
  engine's thread blocks SIGINT; the Mac's run; CI has never run.

### 2026-10-25 — M3 slice 1: spike E1, and a harness safe for threads (PR #19, `8c9c427`)

- **[Spike E1](research/e1/findings.md)** reran the plan's measurements from programs
  committed under `research/e1/`, twice on each of the four Linux libcurls, and on Guix's
  8.20.0 from the store for the stalled lookups. A read-only Opus review sent three sets back
  for two more runs, with cases the first runs missed. The plan's findings held, but it had
  worded three too broadly: the collection stall, Ctrl-C on another thread, and the load race.
- **[ADR-0013](decisions/0013-collect-safe-blocking-calls.md) is accepted.**
  `curl_multi_perform`, `curl_multi_remove_handle` and `curl_multi_cleanup` can block.
  `curl_multi_init`, `curl_multi_add_handle`, `curl_multi_wakeup`, `curl_multi_info_read`,
  and `curl_easy_cleanup` of a handle removed from our multi handle, stay plain. One callable
  may serve a `__collect_safe` call and a plain one.
- **New in E1:**
  - a plain wait holds a collection until the waiting thread's next event check, every 1,000
    ticks, about every 500 polls: a lone collection waited 51 to 466 polls, by when it was
    asked, and collections close together nearly all of it, 459;
  - a plain write callable inside a `__collect_safe` perform crashed Chez in 8 invocations of
    8, so the delivery runs can tell a pairing that fails;
  - a SIGINT sent to a thread other than the main one is dropped, and ends that thread's
    `sleep` or `curl_multi_poll` early, but not its `condition-wait`;
  - the engine's own load race raised "involving invocation" 80 times of 80;
  - on 8.20.0, `curl_easy_cleanup` after `curl_easy_perform` waited 9 s during a stalled
    lookup. The maintainer chose on 2026-10-25 to leave it for slice 2's deletion.
- **`capture-command` is safe for threads.** Each capture writes into a directory of its own,
  which Chez's `mkdir` makes, mode 700, refusing a taken name, and its counter is under a
  mutex. Seven mutants each fail a named row. The old counter's race never showed, so the
  concurrency row's red runs come from mutants alone.
- **Checks:** in the container, `make test` 22/22 (2,221 checks), `check-suites`, `check-seam`
  (14 libraries), `check-help`, `check-test-fails` 11/11 and `test-memory` 22/22; E1's lanes
  in Docker.
- **One subagent:** the read-only adversarial review, Opus, 249k tokens, about 17 minutes. Its
  finds, all fixed: six crashes reported as eight, three findings worded too broadly, a
  stale attribution of the load race, and the M2 gap above, which it found and I measured.
- **Carried into slice 2:** the collection test asks for collections back to back; a Ctrl-C
  child captures nothing while `system` waits; the multi rows' `bind-blocking`; whether the
  engine thread blocks SIGINT; and deleting M2's path closes the `curl_easy_cleanup` gap.

### 2026-10-24 — the M3 plan, and a stalled lookup that must not stall the engine (PR #18, `bf9cae1`)

- **The [M3 plan](2026-10-24-m3-plan.md):** the engine, in three slices: spike E1 and a
  harness safe for threads, then the engine, then stalled lookups. M3 adds nothing public,
  and M2's blocking path retires.
- **Measured before planning** (plan, §2), from scratch programs:
  - a plain wait stalls other threads' collections hundreds of times its length, through
    Chez's event counter;
  - wakeups are race-free for a queue;
  - a `__collect_safe` callable is safe from a plain call;
  - only the main thread gets Ctrl-C;
  - two threads' first references to the library race;
  - a stalled name lookup blocks teardown, and a timeout, for 9 to 10 s.
- **Decided by the maintainer:**
  - `QUICK_EXIT` where libcurl knows it ([ADR-0019](decisions/0019-a-stalled-lookup-does-not-stall-the-engine.md),
    new). `CURLMOPT_QUICK_EXIT` on the multi handle was measured after the question, and
    follows its answer;
  - the caller checks the URL, and the engine parses it again (ADR-0008, amended);
  - an engine loads libcurl before its thread starts (ADR-0002, amended);
  - stop cancels what is in flight, then joins (ADR-0012, amended).
- **ADR-0009 and ADR-0013 amended:** `QUICK_EXIT` is owned, and `curl_multi_perform` can block.
- **No subagents.**

### 2026-10-24 — M2 slice 3: the blocking request over TLS (PR #17, `c14419f`)

- **The request gains two TLS fields** ([ADR-0018](decisions/0018-ca-file-is-the-only-anchor.md)):
  a CA file, or `#f` for the system store, and whether to verify.
  - **A CA file is the only trust anchor.** It sets `CAINFO` and clears `CAPATH`, and a
    `CURLE_NOT_BUILT_IN` answer to the clear is accepted.
  - **Every transfer sets `SSL_VERIFYPEER` and `SSL_VERIFYHOST`:** 1 and 2, or both 0.
  - **The settings are data.** `tls-settings` computes them, `set-tls-options!` applies
    exactly that list, and `test-transfer-tls` holds them whole. No lane's system store
    trusts the run CA, so no transfer could show `CAPATH` left set.
  - **A CA file's path holding U+0000 is refused** as `&curl-request-error`, `embedded-nul`,
    when the request is made and again on perform's copy.
- **Measured first, on four Linux libcurls** (M2 plan, §6.1):
  - **Ubuntu's 8.5.0 trusts its default `CAPATH` beside `CAINFO`,** with either backend.
    With the run CA in a throwaway container's store, a CA file naming the other CA passed;
  - **Guix's 8.20.0 writes `SSL_CERT_FILE` and `SSL_CERT_DIR` over `CAINFO` and `CAPATH`**
    when a transfer starts. The review found that Guix's 8.6.0 lets the request win.
- **Decided by the maintainer:**
  - the CA file is exclusive;
  - `CAINFO_BLOB` and `SSL_OPTIONS` are its twins (ADR-0009, amended);
  - Guix's override is pinned by a test, by world and version, and its policy is M4's;
  - the memory gate's Guix count is our suppression's own blocks, read from Valgrind's
    `used_suppression` line (ADR-0014, amended). An HTTPS handshake on GnuTLS uses
    Valgrind's own `dtv-addr-tail`.
- **`test-transfer-tls`, 53 checks,** and its child, `transfer-tls-env`. They cover:
  - the faces, `h2`, verification off, the system-store control, other-CA, missing and
    directory paths;
  - a CR/LF path and a UTF-8 path;
  - the refusals, a change after the request was made, and a 300-transfer race;
  - the settings held whole, and the Guix pin.
- **CI gains a `gnutls` job,** loading Ubuntu's `libcurl-gnutls.so.4`. `known-libcurls.sexp`
  gains its row, and `debian-prereqs.txt` gains `libcurl3t64-gnutls`.
- **Checks:**
  - in the container: `make test` 22/22, 2212 checks, `check-test-fails` 11/11,
    `check-suites`, `check-seam` (14 libraries), `check-memory-gate` 39 cases and
    `test-memory` 22/22;
  - in Docker: the floor, `gnutls`, main and memory lanes, each with `test-transfer-tls` at
    53.
- **Built with subagents,** three runs, about 776k tokens, all Opus:

  | Agent | Tokens | Time |
  |---|---|---|
  | builder | 392k | 34 min |
  | fix round | about 46k | 11 min |
  | adversarial review | 338k | 24 min |

  - **The review's main find was my brief's.** It held `set-tls-options!` whole, but not
    `set-option!` beneath it. So a mutant that skipped the `CAPATH` clear passed `make test`.
    In Docker, with the run CA in Ubuntu's store, that mutant trusted the other CA's file.
    The fix holds `set-option!` whole, and both of the review's passing mutants now fail.
  - **The review also measured** `SSLKEYLOGFILE`, `OPENSSL_CONF` and GnuTLS's `pkcs11:` CA
    files, which ADR-0018 hands to M4.
- **Evidence:** the builder's 39 mutants each failed a named test, in scratch under
  `build/verify/m2s3/`. Unlike earlier slices, no mutation log was committed.
- **Carried forward:**
  - the Mac's run on SecureTransport, owed before M2 is done;
  - a CI step that installs the run CA, to show the `CAPATH` clear by behaviour, offered
    and not yet decided;
  - CI has still never run.

### 2026-10-24 — M2 slice 2: the blocking plaintext transfer (PR #16, `6600dfb`)

- **`(curl private transfer)`: one blocking request, on the calling thread.**
  - `curl_easy_perform` is bound through `bind-blocking`, `__collect_safe`. The one write
    callable, `write-body`, is locked, and keyed by an integer through `WRITEDATA`.
  - The request holds a URL, a method (`get` or `head`), headers, a user agent, a timeout,
    a body limit and a test hook. It is checked when made, and again at perform, on a
    private snapshot, which is what is sent.
  - The response holds the status, the HTTP version, the effective URL, every header of the
    last request, and the body.
  - Options are named, typed by the loaded library, and each `CURLOT` type is held to its
    setopt binding. The pins are set first, from one table.
- **Decided by the maintainer:**
  - header strings are Latin-1, both ways (ADR-0001);
  - the test seam, `perform-transfer-with`, is held to ADR-0009's rules, narrowed: long,
    values and `off_t` options alone, by id, twins refused (ADR-0009);
  - an escape from perform is allowed and counted. A critical section around perform was
    measured and reversed: it deferred collections and Ctrl-C (ADR-0013).
- **Seven request refusals,** each a `&curl-request-error`: `not-a-token`, `embedded-nul`,
  `line-break`, `not-latin-1`, `surrounding-whitespace`, `duplicates-field` and
  `framing-header`.
- **`test-transfer`** asserts each plaintext scenario whole. It has shared answers, and rows
  for 7.85.0, 8.5.0, 8.7.1 and 8.20.0 for the five that vary. `transfer-escapes`, a child,
  runs the asynchronous escapes under a bound.
- **The Mac, 2026-10-24:** `make test` passed with its 8.7.1 row, and `make check-variadic`
  passed all 25 steps on `tarm64osx`. On each mutant, `test-transfer` failed:

  | Mutant | `test-transfer` on arm64 |
  |---|---|
  | the template's annotation removed | 104 tests, by name |
  | setopt `long` | timed out at 180 s, exit 124 |
  | setopt pointer | 104 tests, by name |
  | setopt `off_t` | 6 tests, by name |
  | getinfo | 50 tests, by name |

  So each setopt binding is observed in a real transfer on Apple arm64 (ADR-0001).
- **Checks:**
  - in the container: `make test` 21/21, `check-test-fails` 11/11, `check-suites`,
    `check-seam` (14 libraries), `test-memory` 21/21 and `check-variadic`, 25 steps;
  - in Docker: the floor lane (7.85.0, Node 20.10.0) and the main lane (8.5.0, OpenSSL),
    and `test-transfer` on 8.5.0 with GnuTLS.
- **Built with subagents,** eight runs in all, about 3.28M tokens, all Opus:

  | Agent | Tokens | Time |
  |---|---|---|
  | builder | 639k | 49 min |
  | fix round 1, by SendMessage | 869k | 86 min |
  | fix round 2 | 210k | about 2 h 16 min |
  | fix round 3 | 327k | 21 min |
  | socket and child-bound fix | 378k | 32 min |
  | adversarial review | 311k | 20 min |
  | scoped review of round 1 | 273k | 21 min |
  | scoped review of round 2 | 273k | 43 min |

  Each review found a sibling of what the last fix closed: the hook's escape, then the
  engine's; the pins removed, then rewritten; User-Agent duplicated, then Host. The floor
  lane caught what the container could not: 7.85.0 leaks about three sockets per abandoned
  handle, and 8.20.0 one.
- **Evidence:** the [transfer mutation log](transfer-mutation-log.md), 99 mutations, each
  caught by a named test, across the build and three fix rounds.
- **Carried forward:**
  - the `long` mutant fails on arm64 only as a hang, which names no test. Running the stall
    tests in a bounded child would make it a named failure;
  - the proxy policy is M4's;
  - CI has still never run.

### 2026-10-23 — M2 slice 1: the counters, checked copies and libcurl's URL API (PR #13, `ed217dc`)

- **The counters are the leak gate.**
  - `(curl private counters)` counts each kind of native object, per process, behind a
    mutex, with no reset.
  - `suite-exit-status` fails a suite whose counts are not all zero.
  - Each child that reaches native prints its counts, and its suite asserts them zero.
  - `check-test-fails` plants a leak.
- **`(curl private memory)` alone calls `foreign-alloc` and `foreign-free`.** Each block is
  counted, and freeing a dead one raises before `foreign-free`.
- **The checked copies.** `memcpy` is bound both ways and not exported, and bounds are
  asserted first. Chez's `u8*` takes no offset, so a copy at an offset bounces through a
  fresh bytevector.
- **C strings.** Strings reach libcurl as counted, NUL-terminated UTF-8 copies, and a NUL
  inside one is refused.
- **`(curl private url)`.**
  - It provides normalize, resolve, a parsed handle for one call, and the http/https check.
    Each refusal raises `&curl-url-error`.
  - `test-url` holds 70 cases: 60 shared answers, and rows for 7.85.0, 8.5.0 and 8.20.0 for
    the 10 that vary (ADR-0008).
  - The scheme check is held against every protocol the libcurl lists.
- **The checks carried from M0:**
  - each binding is held to a prototype row in the header's own spelling, by
    `_Static_assert(_Generic(...))` with no link, its tables written out in the suite;
  - `curlot-types` is complete;
  - a whole layout's size is checked.
- **Checks:**
  - in the container: `make test` 20/20, `check-test-fails` 11/11, `check-suites`,
    `check-seam` (13 libraries), and `test-memory` 20/20;
  - Docker stand-ins for CI's main, floor (7.85.0, Node 20.10.0), memory and nothreads
    lanes passed.
- **Built with subagents,** three in all, about 1.33M tokens:

  | Agent | Model | Tokens | Time |
  |---|---|---|---|
  | builder, then 2 fix rounds by SendMessage | Opus | 740k | about 14 h of it stalled on a wait loop (`traps.md`) |
  | review | Opus | 272k | 18 min |
  | scoped review of fix round 1 | Opus | 318k | 22 min |

  The builder's 58 mutants were all caught. Then the two reviews found 16 more that passed,
  all of one class: a rule tested on one example, where a narrower rule gives the same answer.
  So briefs now name the class up front:
  - a scan, tested at every position;
  - an encoding, tested on bytes where encodings differ;
  - an allowlist, tested against its whole complement;
  - a table-driven check, with its tables written out.
- **Evidence:** the [foundations mutation log](foundations-mutation-log.md): 109 mutations
  caught. I reran the reviews' 16 with their own harnesses, and each is caught.
- **Carried forward:**
  - the Mac's run: its URL row, and the prototype check on Apple's SDK headers;
  - slices 2 and 3;
  - CI has still never run.

### 2026-10-22 — the M2 plan, and curl's URL verdicts by version (PR #12, `afd7951`)

- **The [M2 plan](2026-10-19-m2-plan.md):** one blocking request, plaintext and TLS, in
  three slices.
  - Slice 1 binds no setopt or getinfo option, so it can go before the Apple arm64 run.
  - Slices 2 and 3 follow that run.
  - M2 adds nothing public.
- **Measured before planning:**
  - a `__collect_safe` `curl_easy_perform` with a write callable delivered every byte while
    another thread forced 145,512 collections;
  - without `lock-object` that probe crashed in 6 runs of 6, and with it passed in 6 of 6;
  - Chez's `string` type cuts at an embedded NUL without a word;
  - the TLS faces gave the same verdicts on GnuTLS under 8.20.0 and on OpenSSL under 7.88.1.
- **ADR-0008 amended:** curl's URL verdicts vary by version. 51 of 58 cases agree across
  7.85.0, 7.88.1, 8.5.0 and 8.20.0. The maintainer chose shared answers plus a row per
  libcurl version for the rest.
- **No subagents.**

### 2026-10-19 — M1 slice 2: TLS and HTTP/2 for the test origin (PR #11, `bd215d8`)

- **Per-run TLS material, `tests/make-test-pki.sh DIR`.** It makes ten files: two CAs, and
  four leaves, `good`, `expired`, `wrong-host` and `untrusted`. Each failing leaf has one
  fault the good one lacks. The same commands ran unchanged on OpenSSL 3.5.7, 3.0.13 and
  3.0.11, and on LibreSSL 3.3.6. Nothing is checked in (ADR-0005).
- **The TLS faces.** `h2c` is always on. `--pki DIR` adds:
  - `https`, `https-expired`, `https-wrong-host` and `https-untrusted`, each offering only
    `http/1.1` by ALPN;
  - `raw-tls`, the raw scripts over TLS;
  - `h2`, HTTP/2 by ALPN only.
- **The probe gains `--tls SERVERNAME` and `--alpn LIST`.**
- **`openssl` checks each face, portably,** as the maintainer chose. LibreSSL 3.3.6, the
  Mac's `openssl`, cannot check a hostname. So the checks are three facts (ADR-0005,
  amended):
  - `s_client`'s verify errors and code against the run CA;
  - the leaf it serves, against its file;
  - that leaf's SAN line.

  The code is the first `Verify return code` line, and each TLS 1.3 ticket's later line
  must agree with it.
- **`test-origin-tls`, 87 tests;** `test-origin` grew to 116 and `test-curl-testing` to 265.
- **The stop check holds that nothing but the stop explains an end.** It covers the states
  Node's `close()` never ends, and requires silence right up to the stop and an end within
  500 ms after it. It opens two sets of probes 700 ms apart, and stops twice. A 90-case
  sweep of idle-close mutants failed it on Node 24.18.0 and 20.10.0 alike.
- **Node 20.10.0 passed in Docker,** with OpenSSL 3.0.11 and with LibreSSL 3.3.6 as the
  checker.
- **Limits, measured:**
  - Node 20.10.0 leaves an HTTP/2 connection open after a protocol error the origin sent;
  - the stop check cannot tell a destroy from an exit.
- **Built with subagents,** four in all, about 1.81M tokens:

  | Agent | Model | Tokens | Time |
  |---|---|---|---|
  | builder, then 4 fix rounds by SendMessage | Opus | 874k | about 4 h |
  | review | Opus | 348k | 30 min |
  | scoped review of rounds 1 and 2 | Opus | 317k | 28 min |
  | scoped review of round 3 | Opus | 272k | 38 min |

  The stop check took three reviews, and the cause was my plan. It never said what proves an
  end was the stop's, so each brief fixed the instances found. The check held once briefed
  by mechanism and checked by the sweep.
- **Evidence:** the [TLS mutation log](tls-mutation-log.md): 159 mutations, 150 caught, and
  the 9 left judged equivalent.
- **Carried forward:**
  - for M2 (M1 plan, §8.8): the good face accepted on each TLS backend, as the control, and
    a face offering both `h2` and `http/1.1`;
  - the Mac's run;
  - CI has still never run.

### 2026-10-18 — M1 slice 1: the test origin, the byte probe and the drift guard (PR #10, `79c6df1`)

- **The plaintext origin, `tests/origin.mjs`,** on Node's standard library only.
  - Two faces listen on `127.0.0.1`, port 0.
  - `http` serves `/status`, `/redirect`, `/chunked`, `/echo` and 404, with no `Date` and
    headers in a fixed order.
  - `raw` plays about 30 scripted byte streams: framings, drips, oversized heads and
    protocol errors.
  - It announces one flat JSON line and exits 0 when its stdin closes. A bad client ends
    only its own connection.
- **The byte probe, `tests/wire-probe.mjs`.** It has no HTTP code: it sends the bytes it is
  given and prints every byte it receives, with timings, as Scheme data. `--reset` resets
  through `resetAndDestroy()`, since `destroy()` sends a FIN (measured).
- **The helpers in `(curl-testing)`.** `call-with-origin` holds every origin to a clean stop:
  stdout ended, nothing on stderr, and exit status 0. An `sh` runner records the status,
  since Chez has no `wait`. The announcement reader, `read-within` and the probes are each
  strict.
- **`test-origin`, 110 tests.** Each scenario's whole bytes, in the suite's own copy, and the
  lifecycle:
  - loopback only, and OS-chosen ports;
  - a clean stop, with open connections destroyed;
  - a stated bound on outliving a killed suite, measured at 19.3 s after a SIGKILL
    mid-probe;
  - bad clients, drip timing, every range's edges, and the 64 KiB head limit.
- **The drift guard (ADR-0017).** `test-drift` passes only when the loaded libcurl's five
  fields equal one row of `tests/known-libcurls.sexp`. The rows are Guix's 8.20.0,
  Ubuntu 24.04's 8.5.0, and the 7.85.0 floor. The floor build now names every optional
  library and checks what it installed.
- **Node in CI.** The floor lane installs Node 20 through a pinned `setup-node`.
  `check-floors` holds every `node-version:` to a step's output, and fails closed on YAML
  it cannot read. Node 20.10.0 passed in Docker.
- **Measured first:**
  - Chez has no sockets;
  - Node 20.10.0 and 24.18.0 write the same bytes;
  - `openssl`'s portability, for slice 2.
- **Built with subagents,** four in all, about 1.58M tokens:

  | Agent | Model | Tokens | Time |
  |---|---|---|---|
  | drift builder, in a worktree | Sonnet | 270k | 20 min |
  | origin builder, 4 rounds by SendMessage | Opus | 714k | about 2.5 h |
  | review | Opus | 306k | 31 min |
  | scoped review | Opus | 287k | 25 min |

  The review's blocker was in my plan. `call-with-origin` took stdout's end as a clean
  stop, so an origin that crashed after answering passed. Slice 5's rule, "passes only on
  positive evidence", had not been applied to a process. The `sh` runner's exit status
  closed it.
- **Evidence:** the [mutation log](instrument-mutation-log.md).
- **Carried forward:**
  - slice 2, TLS and HTTP/2;
  - the Mac's run: its drift row, Node 20.10.0, the drip's own-arrival check, and how
    macOS orders data then a reset;
  - CI has still never run.

### 2026-10-17 — M0 slice 6: the variadic bindings, `make dev` and `make clean` (PR #9, `83b6835`)

- **Binds the variadic entry points once per value type.** `curl_easy_setopt` gets a `long`,
  a pointer and a `curl_off_t` binding, and `curl_easy_getinfo` a pointer one, each through
  `bind-variadic`, whose template carries `(__varargs_after 2)`. `curl-easy-option` reads an
  option's id and type from the loaded library.
- **`test-variadic` round-trips values through libcurl without a transfer:**
  - a pointer through `CURLOPT_PRIVATE`;
  - a `long` through `RTSP_CLIENT_CSEQ`;
  - -1 and other signs through `MAXFILESIZE` (`long`) and `MAXFILESIZE_LARGE` (`curl_off_t`).

  Each round trip gets its own sentinel, and every return code is asserted.
- **`make check-variadic`** plants five unannotated bindings. On every platform
  `test-collect-safe` must refuse each, by name. On Apple arm64, the only ABI where a
  missing annotation fails, `test-variadic` must fail too.
- **Closed the binding-macro routes.** The review found that a macro could change what the
  convention reader reads, a hole dating from slice 4. Now:
  - every macro `src/` defines is a row of `known-macros`;
  - plain macros may not take their input apart or be handed a head;
  - `check-seam` rules (h) and (i) hold each library to its path under `src/`.
- **`make dev` and `make clean`,** with `check-dev` and `check-clean`, which run in a fresh
  copy of the tree. That closes M0's Makefile.
- **Measured at the floor first,** in C, on 7.85.0, 8.5.0 and 8.20.0. 8.20.0 clamps
  `RTSP_CLIENT_CSEQ` and refuses a negative one, keeping the old value. That is why each
  round trip has its own sentinel.
- **Built with subagents,** four in all, about 1.77M tokens:
  - the builder on Opus, in a worktree;
  - an adversarial review on Opus;
  - an Opus fixer resumed for five rounds;
  - a scoped review of the fixes on Opus, which found one more route.

  I forecast one builder and one review. The reader's hole took five rounds, because each
  closed the shapes the last probe used. The design that held named the mechanism, and
  could have been the first brief.
- **Evidence:** the [mutation log](variadic-mutation-log.md). Every check has a red run, and
  every mutation fails its check by name. One known limit is recorded: a phantom binding
  from a quoted operand (PH1).
- **Carried forward:**
  - **The Apple arm64 run gates M2** (the maintainer's decision, 2026-10-17). M2 binds no
    setopt or getinfo option until `make test` and `make check-variadic` pass on the M1.
  - For M2:
    - a check of binding types against libcurl's prototypes;
    - `curlot-types` completeness;
    - `curl-easyoption`'s size;
    - `test-variadic`'s need for RTSP;
    - callables only as a define's whole right-hand side;
    - no nested-pattern helper macros;
    - a `__collect_safe` binder for `curl_easy_perform`.
  - Nothing checks that `src/` comes first in `LIBDIRS`.
  - CI has still never run.

### 2026-10-17 — M0 slice 5: the memory gate and CI (PR #8, `eda03a2`)

- **Valgrind is the memory gate** (ADR-0014). `make test-memory` runs every suite under
  exactly the gate's command, and a suite passes only on evidence from Valgrind's own log:
  its command, the Chez it read, and no errors. It refuses every `VALGRIND_*` variable and
  both `.valgrindrc` files, and holds each suite's options and suppressions to the gate's.
- **One suppression, in the container only.** Loading libcurl there loses one block in Guix's
  glibc. Ubuntu 24.04 loses nothing, so CI passes no suppression.
- **`make check-memory-gate` must see it fail:** a planted overrun, a planted leak, each
  hidden source of options, a forged log, and a run with no evidence.
- **CI's workflow:** the `main`, `floor`, `floor-disabled-api` (two lanes), `nothreads` and
  `memory` jobs. The gate runs on every pull request, push to `main` and tag, and actions are
  pinned to full SHAs. CI states no floor: its build scripts read `packaging/floors.sexp`
  (ADR-0016, amended), and `check-floors` holds every workflow file to that.
- **`make check-nothreads`** requires every public library to refuse, by name, a Chez built
  without threads. It fails on a threaded Chez by design, so CI runs it on a `--nothreads`
  build.
- **Valgrind cannot see Chez's heap.** An overrun into a bytevector passes, and so does a
  dropped block whose address an ftype pointer held. So `test-collect-safe` now holds every
  binding's types to an allowlist, and refuses a heap crossing without a reviewed mark. For
  M2, the maintainer decided on one checked wrapper for bytevector copies, and the counters
  as the leak gate.
- **Built with subagents,** nine in all, about 3.2M tokens, the most yet.
  - Each of three reviews found a class the last fix had left open: a deny list that
    `VALGRIND_LIB` walked round, passes taken from empty output, a pattern variable spelt
    like an allowed type, and a floor redefined in a job's `env:`.
  - The lesson: brief a check as "passes only on evidence", never as "refuses X".
- **Evidence:** the [mutation log](memory-ci-mutation-log.md), in eight parts. Every check
  has a red run, and every mutation fails its check by name.
- **Carried forward:**
  - CI's first run, once billing allows. Expect it to need fixes.
  - For M2: the checked bytevector wrapper, the counters as the leak gate, and `lock-object`
    for every callable C holds (ADR-0013).
  - Valgrind follows no child process, so the Chez processes `test-library-loading` spawns
    run unchecked.

### 2026-10-16 — M0 slice 4: constants and layouts, the convention suite and the floors (PR #7, `ba42f70`)

- **Checks constants and struct layouts against libcurl's own headers.** `test-constants`
  generates one C program from `constants.sls`'s exports and `layouts.sls`'s
  `define-ftype`s. It checks each constant's value, and each field's offset, size and kind.
  A C name follows from its Scheme name. The headers must be no newer than the library
  `(curl)` loads.
- **The structs live in `(curl private layouts)`,** held to struct `define-ftype` forms
  alone.
- **Checks every binding's conventions.** `test-collect-safe` holds every
  `foreign-procedure` and `foreign-callable` to a table, each row quoting the record
  sentence behind it. `curl_easy_perform` and `curl_multi_poll` already have
  `__collect_safe` rows (ADR-0013).
- **The floors have one source,** `packaging/floors.sexp` (ADR-0016). `make check-floors`
  holds the README to it, and the suites hold the code to it by behaviour.
- **`check-seam` rules (f) and (g)** keep `define-ftype` in layouts and stop any library
  re-exporting a Chez name. A function ftype would bind C that no other check sees.
- **The first macOS run,** on the maintainer's M1, passes all 13 suites. Two fixes got it
  there. A bare `mktemp -d` ignored `TMPDIR` on macOS, and Homebrew installs Chez as
  `chez`.
- **Built with subagents,** eight in all, about 2.1M tokens: the builders on Opus, Opus and
  Sonnet, two reviews on Opus, and two fix rounds.
  - The first review found that function ftypes could bind C unseen, and that nothing tied
    the headers to the library. Fields of the wrong kind passed, a test asserted message
    text, and a constant's C name was free text.
  - The review of the fixes walked round the `define-ftype` rule three ways: re-export, a
    macro argument, and an exported macro. That was a flaw in the fix brief, which named too
    narrow a class.
- **Evidence:** the [mutation log](constants-mutation-log.md), in six parts. Every check has
  a red run, and every mutation fails its check by name.
- **Carried forward:**
  - CI's floor lane must point both `C_INCLUDE_PATH` and `CHEZ_CURL_LIBCURL` at curl
    7.85.0, and CI's workflow joins what `check-floors` holds.
  - Known limits: the kind check can't tell a pointer from an aggregate of the same size,
    a name built at expansion is out of the convention suite's reach, and rule (g) sees
    bindings only.
  - Linux on arm64 and macOS on amd64 have not run.

### 2026-10-16 — M0 slice 3: loading libcurl, `(curl)` and the seam check (PR #6, `bfc3aa6`)

- **Loads libcurl as ADR-0002 says.** Discovery is a pure function of the environment: the
  override, or one candidate list per world. `native.sls` then loads once, reads
  `curl_version_info` first, checks the floor and SSL, calls `curl_global_init` once,
  binds every entry point after `foreign-entry?` finds it, and runs the two API probes.
- **Refusals stick.** Each is one of six reason symbols and carries the library's report
  once its version is read. `(curl private load-state)` records the first failure and raises
  it again at every later reference, so libcurl is never loaded twice.
- **`(curl)` reports what it loaded:** the path, its source, the version, the features and
  the TLS backend. `make build` is the preflight that prints it.
- **Refuses an unusable Chez by name:** one older than 10.4.0, a 10.4.0 pre-release, or one
  without threads, at expansion.
- **`check-seam` guards ADR-0007's boundary with allowlists,** and `make test` runs it.
  Every `src/` library is in one of the two families, and file endings Chez would load but
  the check can't read are refused by name.
- **Tests without the real thing:** decoy libcurls compiled at test time, a C oracle that
  reads the same library through `dlopen`, and an in-process suite for `native.sls`.
- **Built with subagents,** eight in all, about 2.8M tokens: the pure core and the native
  layer on Opus, `check-seam` on Sonnet in its own worktree, two reviews on Opus and three
  fix rounds.
  - The first review found a flaw in the brief itself: its import-order rule contradicted
    ADR-0007. It also found refusals that didn't stick, and tests that would fail on CI.
  - The second review found fixes that blocked only the reviewer's examples, a cleanup that
    could remove the wrong directory, and rules tested only in scratch.
- **Evidence:** the [mutation log](loading-mutation-log.md), in six parts. Every check has a
  red run, and every mutation fails its check by name.
- **Carried forward:**
  - Loading GnuTLS's libcurl leaks a block in p11-kit, which fails ADR-0014's gate. Decide
    before slice 5.
  - At M3, a first reference to `(curl)` from a second thread, while the load runs, raises
    `cyclic dependency`.
  - CI must run `make build`, which `make test` doesn't. The disabled-API lane should run the
    preflight and expect `missing-api`, rather than the full suite.
  - Nothing has run on macOS or arm64 yet.

### 2026-10-04 — M0 slice 2: the test harness (PR #5, `9bacc6d`)

- **Pinned SRFI-64.** `vendor/chez-srfi` is a submodule at `7879b52`, recorded in
  `Akku.lock`. `make deps` links it and never fetches. `make check-pins` holds the lock, the
  gitlink and the checkout equal, on the host.
- **Built the test loop.** `make test` runs every suite under GNU `timeout` (or `gtimeout`),
  names each as pass, FAIL or HUNG, and fails if any failed or hung, or if none exists.
- **Turned the suite rules into checks.**
  - `check-suites` requires the shared exit form last, and allows only `(exit 1)` before it.
  - `check-test-fails` plants eight bad cases, and `make test` must fail on each, by name.
- **Shared helpers** live in `tests/curl-testing.sls`. The exit verdict is 0 or 1, never a
  count, because exit statuses wrap at 256.
- **Took git out of the container again.** In a git worktree, the container's git could read
  nothing, so `make test` and `make check-guix` failed there. A `no-git` self-test assertion
  keeps it out (ADR-0006 amended).
- **Built with subagents.** Sonnet did the pins, Opus the harness core and an adversarial
  review, and Sonnet the review's fixes. The review found the worktree failure, a flaw in
  the brief itself.
- **Evidence:** the [mutation log](test-harness-mutation-log.md). Each check has a red run,
  and each mutation fails its check by name. The rewritten `check-suites` got fresh mutants
  after the fixes.
- **Carried forward:**
  - `capture-command` shares one counter across threads and writes predictable `/tmp`
    names. Fix it before the first threaded suite (M3).
  - `check-suites` refuses a suite that starts with a `#!` line.
  - The Node origin's helpers wait for the slice that adds `tests/origin.mjs`.

### 2026-10-04 — M0 slice 1: the pinned container and the Makefile skeleton (PR #4, `e8a2f63`)

- **Built ADR-0006's container, with Valgrind.** `scripts/guix-env` runs the pinned
  toolchain with no network. `make check-guix` tests the launcher on the host (60 checks),
  then checks the container from inside. A cached start takes about 1.5 s.
- **Checked the help.** `check-help` holds `make help`'s own listing equal to `.PHONY`,
  both ways.
- **Measured, and amended ADR-0006:**
  - the pinned toolchain has no `cc`, so the container exports `CC`;
  - `--emulate-fhs` does not let Guix's Chez load a library by bare name;
  - `LD_LIBRARY_PATH` does, so the self-test asserts that such a load fails.
- **Evidence:** the [mutation log](guix-env-mutation-log.md) records 50 mutations, each
  failing its check by name. The red run caught a launcher test that passed for the wrong
  reason.
- **Carried forward:** `GOAL`'s `MAKECMDGOALS` branch stays unexercised until a target
  reaches `require-tools` through a prerequisite, which is slice 2's `test`.

### 2026-10-04 — living brief, harness plan, memory and test records (PR #3, `ea56eb4`)

- **The brief is a living document,** accepted for M0. It cites the records and defers to
  them where they disagree.
- **Recorded how M0 checks itself:**
  - ADR-0014: Valgrind on Linux is the memory gate, and it must be seen to fail.
  - ADR-0015: SRFI-64 comes from a vendored chez-srfi pinned in `Akku.lock`, and the suite
    rules are checks.
- **Planned the harness.** The harness plan covers what M0 copies from chez-cmark-gfm and
  chez-libuv, seven improvements on them, CI's lanes, and five slices.
- **Corrected two records:**
  - ADR-0006 gained Valgrind. It had been lost by copying cl-commonmark-gfm's container
    rather than chez-cmark-gfm's.
  - ADR-0013's E5 figures are chez-http-server's, measured on macOS only.
- **Renamed** `CHANGELOG.org` to `CHANGELOG.md`.
- **Carried forward:** close-outs written after a merge still land one PR late, as this
  one does.

### 2026-10-04 — ledger, constraints and the engine records (PR #2, `9077e28`)

- **Moved the ledger to `.plans/`.** AGENTS.md names this file as the ledger and
  `global-constraints.md` as the hard rules every task brief must follow. `/.superpowers/`
  is git-ignored plugin scratch.
- **Recorded the brief's engine rules.** ADR-0012 (accepted): one engine thread owns every
  transfer handle. ADR-0013 (proposed until spike E1): blocking calls are `__collect_safe`,
  and so is every callback they can invoke.
- **Carried forward:** close-outs written after a merge land one PR late, as this one did.

### 2026-10-04 — open decisions settled (PR #1, `407a8c5`)

- **Settled:** D1 to D11, as ADR-0001 to ADR-0011. That is the brief's D1 to D5, plus
  D6 to D11 raised while checking the brief against this host.
- **What changed the brief:**
  - Chez 10's `(__varargs_after n)` removed the C shim (ADR-0001).
  - Guix Chez cannot load the host's libcurl, so discovery reads which world it runs in
    (ADR-0002).
  - The floor moved to 7.85.0 for `CURLOPT_PROTOCOLS_STR` (ADR-0003).
  - A container without `--network` keeps tests on loopback (ADR-0006).
- **Carried forward:** the probes run while deciding are M0's first tests in waiting:
  - varargs setopt;
  - the census of the options API;
  - world detection via `/proc/self/maps`;
  - `curl_url`'s verdicts;
  - the header-API probe;
  - the loopback-only container.

  They lived in session scratch and need writing as real tests.
