# M7 slice 4's measurement, checked (2026-11-03)

I checked the measurement's hand-back before building on it, on the files as the agent left them:
`src/` at main (`649e7a86…`), the prototype `f70df92d…`, `jar.sps` `1b030702…`, `standin.mjs`
`8a6aeaf5…`, each recorded on its log's lines 5 to 12. `make-prototype.sh` remade the prototype
on the host, its diff equal to `prototype.diff` (`4cf15b93…`).

- **The Guix lane, rerun whole** ([`results/rerun-guix-8.20.0.log`](results/rerun-guix-8.20.0.log)),
  exiting 0. `tables.mjs`, given the kept run 1 and my rerun as its two runs (`--dir`,
  `--lanes=guix-8.20.0`), lists two cases that differ, the two that race by design, 1(a)'s
  completion order and 1(d)'s crossing counts
  ([`results/compare-guix-kept-rerun-splits.md`](results/compare-guix-kept-rerun-splits.md));
  its tables differ in those and in item 8's two `crumbs` cells, by the stand-in's connection
  numbers alone, which the racing cases move
  ([`results/compare-guix-kept-rerun.md`](results/compare-guix-kept-rerun.md)).
- **A planted change:** a copy of my rerun with one cookie changed, `Cookie: k=1` to `k=2` in
  item 2's `carry-SHARE-2`. `tables.mjs` listed that case under the splits, and marked its
  table 2 cell ([`results/compare-guix-planted-splits.md`](results/compare-guix-planted-splits.md),
  [`results/compare-guix-planted-table2.md`](results/compare-guix-planted-table2.md)).
- **The rule the probe applies** (`jar.sps`, `rule`) is §3.5's as written: seven tab-separated
  fields; no byte 0x00 to 0x1F or 0x7F; no field empty but the value; the path not `TRUE` or
  `FALSE`.
- **The hang a loaded cookie makes, reproduced without Chez:** [`cap.c`](cap.c) loads one cookie
  through `COOKIELIST` on a bare easy handle, no share, and sends one `GET` to
  [`cap-server.mjs`](cap-server.mjs), which logs each connection's bytes. On all five lanes, past
  the cap, the head ends `Cookie: \r\n` with no blank line, and the server waits for the rest:
  from a value of 8,180 bytes on 8.5.0, 8.20.0 and 8.23.0, and from 8,150 on 7.85.0, where 8,100
  went whole ([`results/cap-c-guix-8.20.0.log`](results/cap-c-guix-8.20.0.log),
  [`results/cap-c-docker.log`](results/cap-c-docker.log)). curl's own tool cannot show it: it
  reads a cookie file through a 5,000-byte line buffer, and exits 100 past it
  ([`results/cap-cli-guix-8.20.0.log`](results/cap-cli-guix-8.20.0.log)).
- **Why, read in source:** when the first cookie to send passes `MAX_COOKIE_HEADER_LEN`, 8,190,
  libcurl has written `Cookie: `, breaks with none counted, and writes the line's CRLF only when
  one was, so the head's own last CRLF ends the `Cookie:` line (8.20.0 `lib/http.c:2557-2600`;
  8.23.0 `:2631`; 7.85.0 `:2755`; Apple's 8.7.1 the same, `build/m4s3/src`). A server cannot
  store such a cookie: libcurl drops a `Set-Cookie` whose name and value pass `MAX_NAME`, 4,096
  bytes (7.85.0 `lib/cookie.c:561-562`; 8.20.0 `:490-492`; 8.23.0 `:434`), but a `COOKIELIST`
  line has no such cap: a 5,000-byte name, and a value of 5,000 or 8,100, loaded and were sent
  on every lane (`results/docker-1.log`, `r 4 name-5000`, `value-5000`, `value-8100`).
- **On 7.85.0 a server's cookie is enough:** 7.85.0 counts the head built before the `Cookie`
  line against the cap. [`cap-url.c`](cap-url.c), a 4,003-byte cookie and a path of P bytes:
  7.85.0's head was left open from a path of 4,200 bytes; 8.5.0 and 8.23.0 sent each whole
  ([`results/cap-url-docker.log`](results/cap-url-docker.log)).
- **A curl bug report, drafted** for the maintainer to file, not sent:
  [`curl-bug-report.md`](curl-bug-report.md).
- **An expiry already past:** loaded alone, 7.85.0 and 8.5.0 list it, 8.20.0 and 8.23.0 drop it
  at once (`r 4 expiry-1`, `n=1` and `n=0`). 7.85.0 purges expired cookies as the next cookie is
  added, as a transfer gathers the cookies it sends, and as a file is written, never as the jar
  is read out (`lib/cookie.c:1033`, `:1427`, `:1665`). The plan's C probe loaded it among
  fourteen lines, so later adds purged it, and it read as dropped on every lane.
- Rerun in the Guix container from the repository's root:
  `scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice4/verify/cap.sh guix-8.20.0' < /dev/null`;
  the Docker lanes, by [`cap-docker.sh`](cap-docker.sh), whose header gives its two commands.

## The build, checked (2026-11-04)

On the builder's hand-back, before the review:

- **`make test` in the container,** 40 of 40
  ([`results/build-make-test-guix-8.20.0.log`](results/build-make-test-guix-8.20.0.log)).
- **The records are mine alone:** `git diff` of `.plans/` and `AGENTS.md` holds only the edits I
  made before the build.
- **The load rule as built** (`src/curl/private/transfer.sls`, `cookie-line-fault`) is decision
  7's, rule for rule, and a refusal names the line's index (`cookie-line-bytes`).
- **The builder's leak probe, rerun:** 54 exits, none printing either secret, its control finding
  the secret in the line, the counts at zero
  ([`results/leak-rerun-guix-8.20.0.log`](results/leak-rerun-guix-8.20.0.log)).
- **Four mutants of my own,** made by [`build-mutants.py`](build-mutants.py) on a copy of the tree
  (`build/m7s4-check/tree`, every file but `build/`, `.git` and `.plans`), none among the
  builder's 86, each failing test-cookies, the copy itself passing
  ([`results/build-mutants-summary.txt`](results/build-mutants-summary.txt), and a
  `build-mutant-NAME.log` each):
  - `jar-handle-unattached`, the jar's own handle never given the share: seven tests, from the
    Latin-1 read-out to the session's;
  - `expiry-limit-strict`, 9223372036854775807 itself refused: the expiry's test;
  - `size-refuses-limit`, a name and value of 4,096 refused: the size test;
  - `leading-dot-reads-prefix`, the dot rule read from the field with `#HttpOnly_` on: four
    tests, the dot rule's among them.

## The review, and the fix round, checked (2026-11-04)

- **The review's prefix finding,** rerun from its `probe-roundtrip.sps` on Guix's 8.20.0
  ([`results/review-roundtrip-guix-8.20.0.log`](results/review-roundtrip-guix-8.20.0.log)): five
  lines read out, one kept as they were loaded back, `same #f`; read in source, 8.20.0 matches a
  `Set-Cookie` name's prefix in its own case (`lib/cookie.c:499`) and a loaded one's in any
  (`:742`), 8.23.0 its own case both ways (`:441`, `:751`).
- **Its probes on 7.85.0, rerun** from its copy of the tree, whose `src/` matched the working
  tree's ([`results/review-probe-load-floor-rerun.log`](results/review-probe-load-floor-rerun.log),
  [`results/review-probe-engine-floor-rerun.log`](results/review-probe-engine-floor-rerun.log)):
  `pair-sent`, `a=b=c; n=x; admin=1`; a tab in a server's `Path` read out as eight fields; a
  4,300-byte `User-Agent`, and Basic credentials with a 3,300-byte password, each 28 with the head
  left open, the control 200; a jar message in a failing turn's batch answered.
- **`CONNECT_TO`,** read in source: 8.20.0 `lib/http.c:3553-3560` stores a `Set-Cookie` under
  `conn->host.name`, the URL's host, or a caller's `Host`.
- **Two traps the builder reported, reproduced:** `node:http` reports a head left open as
  `HPE_INVALID_EOF_STATE` with no bytes, on Node 24.18.0 and 20.10.0, and a `'data'` listener sees
  46 bytes ([`results/trap-open-head-node-guix.log`](results/trap-open-head-node-guix.log),
  [`results/trap-open-head-node-20.log`](results/trap-open-head-node-20.log)); `display-condition`
  prints every field of a condition with no `&message`
  ([`results/trap-display-condition-guix.log`](results/trap-display-condition-guix.log)).
- **After the fix round:** `make test` in the container, 40 of 40
  ([`results/fix-make-test-guix-8.20.0.log`](results/fix-make-test-guix-8.20.0.log)). Six mutants
  by [`build-mutants.py`](build-mutants.py) on a fresh copy, each failing test-cookies, the copy
  passing ([`results/fix-mutants-summary.txt`](results/fix-mutants-summary.txt)): two of mine,
  `host-path-prefix` (a `__Host-` path that only starts with `/`) and `secure-prefix-reads-tail`
  (the `__Secure-` rule reading the tail-match field), and the review's four survivors,
  `fail-batch-unanswered`, `control-enumerated`, `expiry-char-numeric` and `release-twice`.
- **The fix round's two traps, reproduced:** six `failed-jar-state.sps` at once, 26 of 600 reads
  `live` as the failure's token became done, all 600 `closed` after the stop
  ([`results/trap-failed-jar-state-guix-6x.log`](results/trap-failed-jar-state-guix-6x.log));
  `char-numeric?` takes U+00B2, U+00B3, U+00B9 and U+00BC to U+00BE
  ([`results/trap-char-numeric-guix.log`](results/trap-char-numeric-guix.log)).

## The Mac's run (2026-11-04)

At `47481b2`, `make test` 38 of 40 ([`../results/mac-8.7.1-make-test.log`](../results/mac-8.7.1-make-test.log)):
test-cookies failed its five by-version tests for want of 8.7.1's rows, which test-cookies alone
printed again character for character; `make check-variadic` passed all 33 steps, the share's
mutant failing 14 of test-variadic's share rows by name
([`../results/mac-8.7.1-check-variadic.log`](../results/mac-8.7.1-check-variadic.log)). The five
rows are added.

And slice 1's test-version failed: prior knowledge to the `http` face, HTTP/1.1, gave 56 on 8.7.1,
whose row holds 16, the code every earlier Mac run gave. This slice gave that face a `'data'`
listener, for the open-head log, and Node unconsumes an HTTP server's socket handle once one is
added (`_http_server.js`), so the face now reads through JS events. Not shown to be the cause: on
Guix's 8.20.0, curl's own tool with prior knowledge, 200 times against each origin, gave 16 and 55
both ways, 186 and 14 against main's, 197 and 3 against the slice's, and 56 against neither
([`results/pk-h1-guix-8.20.0.log`](results/pk-h1-guix-8.20.0.log), by [`pk-h1.sh`](pk-h1.sh)).
The Mac runs the same comparison.

On the Mac, at `d176ed7` ([`../results/mac-8.7.1-pk-h1-and-test-version.log`](../results/mac-8.7.1-pk-h1-and-test-version.log)):
curl's own tool, Apple's 8.7.1, 200 times each, gave 16 194 times and 56 6 against main's origin,
and 16 193 times and 56 7 against the slice's; test-version gave 56 twice more. So 8.7.1 gives 56
against the origin as it was before this slice, and the listener moved nothing curl's tool can
see; why the engine's runs went from 16 in every run through slice 3 to 56 in three of three is
not known. 8.7.1's row holds both, as AGENTS.md's race rule has it.

With the rows in, at `e04917a`, test-cookies passed 70 of 70 on the Mac and test-version 27 of 27,
measuring 56 once more ([`../results/mac-8.7.1-test-cookies-version.log`](../results/mac-8.7.1-test-cookies-version.log)).

## CI on PR #45, at `dde5146` (2026-11-05)

Six jobs of eight passed ([`results/ci-gnutls-dde5146.log`](results/ci-gnutls-dde5146.log),
[`results/ci-memory-dde5146.log`](results/ci-memory-dde5146.log)):

- **gnutls:** test-auth, the job's first suite, failed one test: its origin wrote no announcement
  within 5,000 ms, and the bound's kill left status 137, stdout and stderr empty. The origin
  starts in about 60 ms on main's tree and on the slice's, five starts each with the run's PKI
  ([`results/origin-start-guix.log`](results/origin-start-guix.log), by
  [`origin-start.sh`](origin-start.sh)): the runner, not the origin, by every reading here.
- **memory:** test-group, under Valgrind on Ubuntu's 8.5.0 with OpenSSL, failed M5's test of a
  Ctrl-C handler raising its own `&curl-error` while `go`'s submit blocks on the engine's mutex:
  what left the group was compounded, `(raise #f #t after-release ...)` where `(raise #t #f
  after-release ...)` is held. The handler ran after the release, and the raise came out
  compounded, which fits only a signal handled once go's submit section had ended, in the group's
  await. My reading, not measured: Valgrind hands a guest a signal at its own scheduling points, so a
  thread blocked in a mutex wait may see it late. The slice's submit path is one `locked` section
  as before, its new checks only for a request with a jar. test-group passed natively and under
  the gate on that lane in Docker, three runs on the slice's tree and three on main's, interleaved
  ([`results/group-memory-runs.out`](results/group-memory-runs.out)).

**Decided by the maintainer, 2026-11-05, the recommended option:** rerun the two failed jobs.

The rerun ([`results/ci-memory-dde5146-attempt2.log`](results/ci-memory-dde5146-attempt2.log)): gnutls
passed; memory failed elsewhere, test-group passing. M6 slice 2's test-upload read the HTTP/2
body-asked cell `#f` where `#t` is held: its server answers before reading the body, the race the
raw face's cell was loosened for after CI's first runs (`tests/test-upload.sps:708-721`). What the
HTTP/2 cell could hold both ways is not measured: libcurl may still ask for the body over HTTP/2
after the answer. **Decided by the maintainer, 2026-11-05, the recommended option:** rerun the
memory job once more; measure both races under the gate and fix them on the next branch, in a PR
of their own.

The third attempt ([`results/ci-memory-dde5146-attempt3.log`](results/ci-memory-dde5146-attempt3.log))
failed both, test-group and test-upload: each failed two attempts of three on this PR, and neither
had failed on a CI run before it. Locally, in Docker pinned to two CPUs, the memory gate on
Ubuntu's 8.5.0 with OpenSSL, three rounds of both suites a tree
([`results/memory-race.out`](results/memory-race.out), by [`memory-race.sh`](memory-race.sh)):
test-upload's HTTP/2 cell failed once on this slice's tree, never on main's; test-group passed
every run. main's own push run after slice 3, at `a075629`, which I did not watch, had failed the
floor job in test-origin-tls, an HTTP/2 frame sequence after a refused stream
([`results/ci-main-floor-a075629.log`](results/ci-main-floor-a075629.log)), a race of its own.
**Decided by the maintainer, 2026-11-05, the recommended option:** fix both tests on this PR,
measured first; test-origin-tls's race goes to the follow-up.

## The two races, measured and fixed (2026-11-05)

An Opus agent measured both under the gate on both trees and fixed both tests
([`../races/README.md`](../races/README.md)); I checked its hand-back:

- **test-group's cause,** reproduced by a collection planted 1 KiB past the child's ready line:
  CI's own answer, `(raise #f #t after-release (0 0 0))`, the handler in `call-request-of`
  ([`../races/results/trip-1k-raise-ci-guix.log`](../races/results/trip-1k-raise-ci-guix.log)),
  and main's tree failing as readily ([`../races/results/trip-tables.txt`](../races/results/trip-tables.txt)).
  My hypothesis, a SIGINT handed to the holder thread, was wrong: Chez drops one there.
- **test-upload's,** read in 8.5.0's source as the agent had it: `drain_stream` sets OUT beside IN
  while the upload is open (`lib/http2.c:211-218`), and `Curl_readwrite` returns early on a
  paused direction (`lib/transfer.c:1051`), so a held answer to a paused body hung.
- **test-origin-tls's `/refuse` failures** under the gate on two pinned CPUs, 6 of 10 on the fixed
  tree, are older than the fix and the slice: in the same container, on the same CPUs, the
  unfixed tree failed 2 of 3 and main's 1 of 3, at `/refuse?at=0` and `at=3`
  ([`results/control-tls-unfixed-cpus36.out`](results/control-tls-unfixed-cpus36.out),
  [`results/control-tls-main-cpus01.out`](results/control-tls-main-cpus01.out)). It is the race
  main's floor job hit; CI's memory job passed it on all three attempts. Carried, as decided.
- **Carried for the follow-up, from the agent's report:** `call-state`'s guard compounds a
  caller's Ctrl-C handler raise that lands in go's request building, on main too; test-http-client,
  test-engine and test-mailbox hold a section across a SIGINT without `collect-rendezvous`; and a
  caller who streams a body over HTTP/2 on 8.5.0 and waits for the head before putting can wait
  for the transfer's timeout.
- **My checks of the fix:** `make test` 40 of 40 in the container
  ([`results/races-make-test-guix-8.20.0.log`](results/races-make-test-guix-8.20.0.log)); test-group
  and test-upload under the gate, two CPUs, two rounds of two
  ([`results/races-gate-fixed-cpus01.out`](results/races-gate-fixed-cpus01.out)).
