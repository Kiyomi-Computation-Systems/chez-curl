# ADR-0020: A CI lane on the current libcurl, built from source

- **Status:** Accepted; amended 2026-10-26: the lane moves to 8.23.0
- **Date:** 2026-10-26
- **Scope:** CI (`.github/workflows/ci.yml`), `scripts/ci/build-curl.sh`, and the version
  tables a libcurl needs rows in
- **Settles:** which libcurl the lane builds; the maintainer chose on 2026-10-26
- **Related:** [ADR-0003](0003-libcurl-floor-7-85.md), the floor ·
  [ADR-0016](0016-floors-have-one-source.md), the floors' one source ·
  [ADR-0017](0017-drift-guard.md), the drift guard ·
  [ADR-0019](0019-a-stalled-lookup-does-not-stall-the-engine.md), amended 2026-10-25, whose
  review found that no CI lane loads 8.20.0 or later

## Context

CI's lanes load Ubuntu's 8.5.0, with OpenSSL and with GnuTLS, and the floor's 7.85.0, built
from source. Only the Guix container runs 8.20.0, so `CURLMOPT_QUICK_EXIT`, its constant's
check, and every version table's 8.20.0 row run nowhere in CI (ADR-0019, amended 2026-10-25,
after the slice's review). The maintainer asked for a lane that builds a current curl, as the
floor lane builds 7.85.0.

Measured on 2026-10-26, in Docker `ubuntu:24.04` with `packaging/debian-prereqs.txt`
installed, under the floor's Chez:

- **curl's newest release is 8.23.0, of 2026-10-14** (`https://curl.se/info`). The container
  runs 8.20.0. Both release tarballs' detached signatures verify against Daniel Stenberg's
  key, `27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2`, the key `build-curl.sh` already names:
  8.20.0's `.tar.xz` has sha256 `63fe2dc1…b896`, 8.23.0's `8dadd7d2…e6c5`.
- **curl 8 needs a configure line of its own.** 8.20.0's `./configure` has no `librtmp`,
  `wolfssh`, `hyper` or `msh3` options, which the floor's line names, and under
  `--enable-option-checking=fatal` each stops it. It has two new options that look for a
  library: `libuv`, and Apple's IDN. 8.23.0 drops `smb` and `tls-srp` too, which the line
  does not name.
- **With that line, vanilla 8.20.0 with OpenSSL passed every suite but `test-drift`,** which
  printed the row it needs: 22 of 23. Its other version tables already hold 8.20.0 rows,
  from the container, and its answers agreed with them; `test-transfer-tls` takes it as a
  libcurl that reads neither `SSL_CERT_FILE` nor `SSL_CERT_DIR`, as Guix's patch does.
- **8.23.0 failed four suites, and `test-engine` hung past its 300 s bound.**
  - `test-drift`, `test-url`, `test-transfer` and `test-variadic` have no 8.23.0 row.
  - Five of `test-transfer`'s varying scenarios answer otherwise: a 100 KB and a 1 MB header
    and 100,000 headers are refused with 100, a bad status code is a 200, and conflicting
    `Content-Length` headers are refused with 8.
  - One answer every recorded libcurl shared changed: the error buffer's text for a NUL in a
    header.
  - Two transfers in `test-engine` failed with `CURLE_SEND_ERROR`, "Failed sending data to
    the peer", on caller threads that do not catch it, and the suite hung waiting for them.

## Decision

1. **The lane builds 8.20.0,** vanilla, with OpenSSL: the version the container runs, so the
   current libcurl's every row is one the container already measures, and a build without
   Guix's patches checks them beside the patched one. 8.23.0 is a slice of its own, below.
2. **`build-curl.sh --current` builds it.** The script pins `current_version`, beside the
   floor, with its sha256, and builds it with its own configure line, read against its own
   `./configure --help`. With `--current` it reads no floors file, and no argument or
   environment variable gives the version: the flag chooses between the two pinned builds and
   changes neither. Without it, the floor's build is as it was. The current version is no
   floor, so it is not in `packaging/floors.sexp`, and ADR-0016 does not govern it.
3. **The `current` job runs `make build` and `make test`** against the install, with
   `CHEZ_CURL_LIBCURL` and `C_INCLUDE_PATH` naming it, under the runner's own Node. It fails
   unless `make build` loaded the version the install's own `curl-config` reports, so the
   workflow names no version. Its cache is keyed by `build-curl.sh`, which holds the version,
   and by the package list and the runner image.
4. **`tests/known-libcurls.sexp` gains the build's row,** as `test-drift` printed it.
5. **`test-check-floors` holds `--current`:** it reaches the download of the pinned version
   whatever the floors file holds, or with none; the environment cannot move it; and it takes
   the same usage and prefix rules.

### Rejected

- **8.23.0 now.** It needs rows in five tables, a shared answer moved to version rows, and
  the hang understood before the lane could pass.
- **Both now,** for the same reason, and one more job.
- **The current version in `packaging/floors.sexp`,** or a file of its own with a reader
  script. It is no floor, `check-floors` holds that file to three keys, and the build script,
  which also pins its sum, is one place a change shows.

## Consequences

- **CI shows `CURLMOPT_QUICK_EXIT`,** its constant's check, and the stall checks' 8.20.0
  rows, once CI runs at all: its jobs still stop at the billing limit.
- **Raising the current version is a reviewed change:** a verified sum, a configure line read
  again, and the rows `make test` prints for every version table.
- **Owed, a slice of its own: 8.23.0.** Its rows, the shared answer that moves, and the hang:
  two caller threads in `test-engine` that let a transfer's raise escape, so the suite waits
  for good rather than failing by name. That last is a defect in the suite whatever the
  libcurl, and a check that hangs names no test.
- **The workflow check does not read the current version.** `check-floors` keeps the floors'
  versions out of the workflows; the current lane states none, and nothing passes one to
  `--current`, which takes no value.

## Amendment, 2026-10-26: the lane moves to 8.23.0

The slice this record owed. Measured on 2026-10-26 in Docker `ubuntu:24.04`, under the
floor's Chez, against the vanilla 8.20.0 and 8.23.0 builds of the measurement above:

- **`test-engine`'s hang was the suite's own.** "Two caller threads awaiting together" awaited
  the shared transfer with no `guard`, and waited for both threads on a `condition-wait` with
  no bound: a raise killed both threads, and the wait never ended. Now each thread's raise is
  its answer, and the wait polls under a 45 s bound. On 8.23.0 the check fails by name, each
  thread answering `(on-thread (transfer-error perform-failed 55 #f))`; on 8.20.0 the suite
  passed, 54 checks, and with the checks below, 56.
- **Why 55: 8.23.0 reuses, without checking it, a connection that went back to its pool
  under 1 s before, however old.** `Curl_cpool_conn_seems_healthy` (`lib/conncache.c`) checks
  an idle connection only when its last check is 1000 ms old or more, and `Curl_cpool_return`
  sets that last check each time a connection goes back to the pool; 8.20.0's
  `Curl_conn_seems_dead` (`lib/url.c`) checked every idle connection before reuse. The raw
  face closes after each script and sends no `Connection: close`, so libcurl pools each drip's
  connection, dead. On 8.23.0 the next raw transfer reuses one, sends, sees "Connection died",
  retries on the next, and after five retries gives up: "Connection died, tried 5 times before
  giving up", `CURLE_SEND_ERROR`. A probe that replays the suite's steps with `VERBOSE`
  ([`research/reuse/reuse.sps`](../research/reuse/reuse.sps), its logs in
  `research/reuse/results/`), 2 runs of 2 each: after 5 such connections the next drip
  answered; after 6 or 8 it failed with 55; after 8 and a 1.1 s pause it answered. 8.20.0
  answered every time, and reported each dead connection.
- **The rows.** 8.23.0 answers as 8.20.0 does in `test-transfer`'s five varying scenarios,
  `test-variadic`'s `minus-one-rows` (10), and `test-engine`'s stall row. `test-url` differs in
  two: a space in a path is refused with 25 (`CURLUE_BAD_PATH`), and one in a host with 21
  (`CURLUE_BAD_HOSTNAME`), where 8.20.0 refused both with 3.
- **The shared answer that moved:** the error buffer's text for a NUL in a header is
  "NUL byte in header" (`lib/http.c`), where every libcurl recorded before wrote
  "Nul byte in header".
- **8.23.0's `./configure`** adds `apple-fast-udp`, `gssapi-apple`, `httpsig` and
  `proxy-http3`, each an experimental feature off by default, and `--with-test-h2o`, a test
  server's path; none looks for a library, so the current line builds 8.23.0 unchanged. It
  drops `smb` and `tls-srp`, which the line does not name; its features word is 8.20.0's less
  `CURL_VERSION_TLSAUTH_SRP`.

### Decided by the maintainer, 2026-10-26

1. **The `current` lane builds 8.23.0, in place of 8.20.0.** `build-curl.sh` pins 8.23.0 and
   its sum. The container runs Guix's 8.20.0 on every `make test`, so 8.20.0's rows still run.
2. **The two-thread check runs on an engine of its own,** so no earlier check's pool reaches
   it, and **`test-engine` pins the pool's behaviour by version:** on an engine of its own,
   eight drips live together, then one more at once. A row per version holds its answer, and
   a libcurl with no row prints the one it needs.

### Rejected

- **Both versions,** a matrix: one more job, for a vanilla 8.20.0 the container's patched one
  already covers.
- **Keeping 8.20.0,** with 8.23.0's rows alone: no lane would load the newest release.
- **Recording the reuse alone,** with no check: nothing would notice when libcurl changes it.
- **The raw drip announcing its close:** it changes the instrument's bytes, which
  `test-origin` holds, and hides the behaviour from every check.

### Consequences

- **A server that closes a connection without saying so meets this on 8.23.0.** When six
  such connections went back to an engine's pool within the last second, its next transfer
  to that server fails with 55. M4's error taxonomy decides what a caller sees; M8's
  documentation states it.
- **`test-transfer`'s verdict rows gain a second kind of case:** the error buffer's text for a
  GET, so a text that varies by version is a row's answer, as a verdict is.

### After the slice's review

A read-only review on Opus found six things, each fixed before the slice was offered. Its
probe and logs are kept beside mine, as `research/reuse/probe-reuse.sps` and
`research/reuse/results/review-*.log`; I reran its old-connection case with logs of my own,
`results/old-conns-*.log`.

- **The rule was stated wrong.** I wrote that 8.23.0 skips the check for a connection "under
  1 s old". `Curl_cpool_return` resets the last check each time a connection goes back to the
  pool, so the window runs from its return, however old the connection: connections 1.8 s old,
  returned at once, gave 55, 3 runs of 3; a 0.9 s pause gave 55 too. The records now say so.
- **The pin needed the eight drips to overlap, and nothing held that.** Submits spread over
  70 ms let 4-byte drips at 10 ms share connections, and the ninth answered, 5 runs of 5. The
  drips now pause 50 ms between bytes, about 200 ms each, which gave 55 at the same spread, 5
  of 5; and the check asserts that all eight were live together, by the engine's live count. A
  mutant that submits them one after another fails it on 8.20.0 as on 8.23.0.
- **The row held 55 alone.** The reuse check now carries the error buffer, so 8.23.0's row is
  `(transfer-error perform-failed 55 "Connection died, tried 5 times before giving up")`.
- **`test-curl-testing`'s capture threads could hang it,** the class this slice fixed in
  `test-engine`: a raise outside a capture's `guard` killed a thread, and the wait had no bound.
  Each thread's whole body is guarded now, and the wait polls under 120 s; a planted raise and
  a planted hang each fail the check by name.
- **The `error-text` answer's length was not held:** a mutant taking `(error-text "t" "u")`
  passed. The shape test now rejects it and `(error-text)`.
- **Stale records:** ADR-0016's line on the current version, the M3 plan's Mac rows, "the
  newest release" where it would go stale, a check count, and the 8.23.0 transfer row's
  `where`, now true: with that row removed, `test-transfer` printed it, six answers, equal.
