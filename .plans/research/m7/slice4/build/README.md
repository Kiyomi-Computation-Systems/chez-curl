# M7 slice 4's build: the logs it cites

Kept by the slice's builder (2026-11-04), from runs made in `build/m7s4b/`, the scratch
directory, where the scripts here ran; each is a copy. Nothing here is a measurement the records
rest on but the by-version rows and the leak probe: the rest is the build's evidence that its
checks passed, and that each was seen to fail.

## The checks

- `results/make-test-guix-8.20.0-1.log`, `-2.log`: `make test` in the container, twice, 40 of
  40 each.
- `results/lanes-final.out`, `results/lanes-final-{floor,openssl,gnutls,current}.log`: `make
  test`, every suite, on the four Docker lanes (floor 7.85.0, Ubuntu's 8.5.0 with OpenSSL and
  with GnuTLS, 8.23.0), by `lanes.sh` and `lanes-in-docker.sh`, slice 3's, on a snapshot of the
  tree (`snap.sh`) whose `src/`, `tests/` and `README.org` match the handed-back tree: 40 of 40
  on each.
- `results/memory-openssl-8.5.0.out`, `.log`: `make test-memory` of test-cookies and the 29 suites
  the slice changed, 30 in all, on Ubuntu's 8.5.0 with OpenSSL.
- `results/check-variadic-guix-8.20.0.log`: `make check-variadic` in the container, 33 steps,
  each `ok`. The share use's static step: test-collect-safe fails on a plain
  `curl_share_setopt`, naming `curl-share-setopt-int` alone. Its arm64 step runs only on the Mac.
- `results/leak-guix-8.20.0.log`, `results/leak-{floor,openssl,gnutls,current}.log`:
  `cookie-leak.sps` on the five lanes. 54 exits a lane, each `secret printed: no`: every
  `cookie-line` refusal, one per rule; every wrong kind; a line where a jar belongs, to each jar
  procedure and to the session's; the `cookie-jar` key; `cookie-beside-jar` as made and at
  submit; another engine's jar; a closed one; a refused connect and a timeout holding the jar;
  the jar, the request, the token, the response, a streamed head, the session, its response and
  its redirect error; a stopped engine's jar. Two controls a lane say `yes`: the jar's read-out
  holds the loaded secret, and the search finds it in the line itself.

## The by-version rows (ADR-0017)

`rows.py` prints each `test-cookies: TAG on KEY measured VALUE` line a run printed, per table and
key, and whether the runs agree. Each row comes from two runs a lane, and no cell split:

- `refused-readout`, `expired-load` and `domain-localhost`: `results/rows-guix-8.20.0-c3.log`,
  `-c4.log`, and `results/rows-lane-*-m1.log`, `-m2.log`; `results/rows-first-three.txt` is
  `rows.py`'s table of them.
- `open-head` and `set-cookie-matrix`: `results/rows-guix-8.20.0-c5.log`, `-c6.log`, and
  `results/rows-lane-*-m3.log`, `-m4.log`.

Before its rows were in, each table's test failed by name, its expected value `(a-row-for
VERSION)` and its actual `(no-row-for VERSION measured ...)`: the five in `-c3.log`, the last two
in `-c5.log` and `-c6.log`. The checks above ran every table again, on every lane, and passed.

## The mutants

`mutants.py` holds each mutant as a row: the file, the text it replaces and its replacement, the
suites it runs, and the tests that must fail by name. `mutants.py make` copies the tree under
`build/m7s4b/mut/NAME`, the decisions included and `build/scheme-libs` linked, and `mut-run.sh`
runs each in the container, two at a time.

- `results/mutants-final.txt`: 86 mutants and a control, each with its suites' exit status and
  every test that failed. Every mutant failed each test it names; the control, a copy with no
  change, passes all 13 suites the mutants run.
- `results/mutants-first.txt`: the first round, on the tests before the round's changes. Its
  control failed three suites that need the decisions or a child's `build/scheme-libs`, which
  the copy then lacked. It found these, each since fixed:
  - `set-cookie-foldcase`, `string-foldcase` for the A to Z fold of `Set-Cookie:`, survived: an
    equivalent mutant. No Latin-1 char but A to Z folds onto `set-cookie:`'s letters, and a
    char above U+00FF is `not-latin-1` first, so the two folds refuse the same lines. The test's
    name now says so; the mutant is out of the list.
  - `share-uncounted`: the test named "its share and handle counted" read the engine's jar
    count. It now reads the share and easy counts.
  - `close-ignores-holders`, a close freeing at once: the close-while-held test passed it, since
    `curl_share_cleanup` refuses a share in use. It now counts the jar's own handle, kept while
    the jar is closing.
  - `jar-after-submits` left the queue-order test passing: a load's place in its turn does not
    show in the transfer, which reads the cookies as it builds its request. The order of jar
    messages and submits shows only against a close: the controlled crossing test now has both
    orders in one hold, and fails `jar-after-submits`, `jar-before-submits` and
    `jar-after-perform`. The queue test's name claims what it shows; `share-unset` fails it.
- The suite's test that `cookie-line-bytes` "checks and loads its copies" was removed: its
  answer is fresh bytevectors whatever the code copies, and no mutant could fail it. A copy
  that is checked and then used shows only in a race; the load's copy taken as it is called is
  held by the queued-load test, which `load-late-copy` fails.

## A trap: node:http hands a server no byte of a head left open (`open-head-node.mjs`)

A client that ends its connection mid-head, as 7.85.0's long-URL hang does, reaches an
`http.Server` only as `clientError` `HPE_INVALID_EOF_STATE`, its `bytesParsed` 0 and its
`rawPacket` undefined: the bytes are gone. The origin's http face keeps a `'data'` listener of
its own on each connection (`headTracker`), which sees them, and Node goes on feeding its parser
from the same events. `results/open-head-node-24.log`: Node 24.18.0 in the container, the head's
46 bytes seen with the listener, none without; test-origin's open-head test passed on Node
20.10.0 on the four Docker lanes.

## A trap: `display-condition` prints every field of a condition with no message (`display-condition.sps`)

Chez's `display-condition` prints a condition that holds a `&message` as its who, message and
irritants alone; one with none, as "condition components", each with every field it holds, a
`&curl-request-error`'s value among them. `results/display-condition-guix.log`, Chez 10.4.0: a
field holding a secret printed without a message, and not with one. Every condition the jar
raises holds a message, and test-cookies' printed test reads `display-condition` of each.

## The fix round, after the review

The review's findings (`../review/README.md`) and ADR-0035's decisions 10 to 13, built on the
same tree. Logs under `results/fix-*`.

### The rows measured again

`refused-readout` gains a server's `__secure-a` and `__SECURE-b`, a `__host-c` with
`Path=/cookies` and a `__HOST-d` with `Domain=a.localhost`, none `Secure`, and a tab in a
server's `Path`; `open-head` gains a 4,300-byte `User-Agent` beside a short URL, in a fresh jar.
Two runs a lane, none split: `results/fix-rows-guix-8.20.0-f1.log`, `-f2.log`,
`results/fix-rows-lane-*-r1.log`, `-r2.log`; `results/fix-rows.txt` is `rows.py`'s table.

- The prefixed cookies are listed, each `prefix` by the rule, on 7.85.0, 8.20.0 and 8.23.0, and
  sent; both 8.5.0 builds drop them at the `Set-Cookie`. The tab in `Path` is eight fields on
  7.85.0 (`fields`), and dropped elsewhere. As the review's `probe-roundtrip.sps` and
  `probe-load.sps` found.
- The user agent's head: 28 and the head left open on 7.85.0, 200 elsewhere, as the long URL's.
  The other three tables measured as before.

### The mutants

`mutants.py`, 18 rows added: each new rule's, and the review's four survivors
(`fail-batch-unanswered`, `control-enumerated`, `expiry-char-numeric`, `release-twice`).
`results/fix-mutants-final.txt`: 104 mutants and the control; every mutant failed each test it
names. The review's four fail the tests added for them: the batch's answer (`(not-answered
10000)`, bounded, never a hang), every control char, the expiry's and the TRUE and FALSE fields'
complements (`expiry-char-numeric` raises, `(raised ...)` against `expiry`), and the hold let go
once (`-1` against `0`). `prefix-foldcase` was not made: as for `Set-Cookie:`, no Latin-1 char
but A to Z folds onto a prefix's letters.

### Two traps

- **A jar's state as its failed engine's token becomes done** (`failed-jar-state.sps`): the
  failure completes each token before it frees the jars, so a read then can see `live`.
  `results/failed-jar-state-guix-6x.log`: six probes at once, 100 runs each, 17 of 600 reads
  `live` as the token was done, every read `closed` once `curl-engine-stop` returned. The first
  run of the hold-let-go-once test read the state before the stop and failed so under one
  mutant's load; the test reads it after the stop.
- **`char-numeric?` takes Latin-1's other numerics** (`char-numeric.sps`): U+00B2, U+00B3,
  U+00B9 and U+00BC to U+00BE, each of which `string->number` reads as `#f`.
  `results/char-numeric-guix.log`.

### The checks

- `results/fix-make-test-guix-8.20.0-1.log`, `-2.log`: `make test` in the container, twice, 40
  of 40 each.
- `results/fix-lanes.out`, `results/fix-lanes-{floor,openssl,gnutls,current}.log`: `make test`,
  every suite, on the four Docker lanes, on a snapshot matching the handed-back `src/`, `tests/`
  and `README.org`: 40 of 40 on each.
- `results/fix-memory-openssl-8.5.0.{out,log}`: `make test-memory` of test-cookies on Ubuntu's
  8.5.0 with OpenSSL, 1 of 1.
- `results/fix-leak-guix-8.20.0.log`, `results/fix-leak-{floor,openssl,gnutls,current}.log`:
  `cookie-leak.sps`, a line refused by each new rule added (a `;` in a value and in a name, an
  `=` in a name, a `__Secure-` not secure, a `__host-` with a path), each refused by its own
  rule: 59 exits a lane, each `secret printed: no`, both controls `yes`.
