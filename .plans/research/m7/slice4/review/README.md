# M7 slice 4's adversarial review: the probes and mutants it cites

Kept by the slice's reviewer (2026-11-04). Everything ran on a copy of the working tree,
`build/m7s4-review/base` (rsync of the tree, `make deps` run in it), never on the tree itself.
The mutants are copies of that copy under `build/m7s4-review/base/mut/NAME`.

## Files

| File | What it is |
|---|---|
| `mutants.py` | Six mutants the build's 86 did not make, each an exact, once-only edit; `make` builds them, `list` prints the jobs. |
| `mut-run.sh` | Runs each job's suite in its mutant copy, in the Guix container, two at a time. |
| `probe-load.sps` | Lines the load rule takes: cookie-prefix names (`__Secure-`, `__Host-`, other cases), a value holding `; ` and a name holding `=`, a server's tab in `Path`, and 7.85.0's open head by a long user agent or Basic credentials. |
| `probe-roundtrip.sps` | A server's prefix-named cookies in a case not the prefix's own, read out, loaded into a fresh jar, read out again. |
| `probe-engine.sps` | Two paths of the lifetime test-cookies does not reach: a jar message in the batch of a failing turn, and a failure after take-out! has let a hold go. |
| `rule-mutants.sps` | What the two surviving rule mutants let through. |
| `probe-lanes.sh`, `probe-lanes-in-docker.sh` | The probes on the four Docker lanes, one `--rm` ubuntu:24.04, the build's lanes' paths. |
| `results/` | Every log cited below. |

## What the logs show

- `results/probe-roundtrip-guix-8.20.0.log`, `results/*-probe-roundtrip.log`,
  `results/probe-lanes-roundtrip.out`: a server's `__secure-a`, `__SECURE-b`, `__host-c` and
  `__HOST-d` are stored and read out on 7.85.0, 8.20.0 and 8.23.0, dropped by 8.5.0's Set-Cookie;
  the read-out loaded into a fresh jar keeps 1 line of 5 on 7.85.0 and 8.20.0, every load
  answering OK (`same #f`), and all 5 on 8.23.0.
- `results/probes-guix-8.20.0.log`, `results/*-probe-load.log`, `results/probe-lanes.out`:
  - `prefix-*`: a loaded line whose prefix's rule it breaks is dropped on every lane in the
    prefix's own case; in another case it is dropped on 7.85.0, both 8.5.0s and 8.20.0 and kept
    on 8.23.0 (`__secure-b`, `__SECURE-c`, `__host-f`, `__HOST-h`);
  - `pair-sent`: `cookie="a=b=c; n=x; admin=1"` on all five;
  - `path-tab-readout`: 7.85.0 reads a server's `Path=/a<TAB>b` out as eight fields; the rest
    drop the cookie;
  - `head-agent`, `head-basic`: 7.85.0 ends 28 with the head left open (`open-head` in the
    origin's log) for a 4,300-byte user agent, and for Basic credentials of a 3,300-byte password,
    beside a server's 4,003-byte cookie and a short URL; the control 200; the rest 200.
- `results/probes-guix-8.20.0.log` (the `mut/` sections) and `results/*-probe-engine.log`: on
  the tree, `batch (answered (raised (engine-error failed)))` and `free (... 0 closed)` on all five
  lanes; on `fail-batch-unanswered`, `batch (not-answered 5000)`; on `release-twice`, holders
  `-1`.
- `results/mutants-results.txt` and `results/mutant-NAME-test-cookies.log`: test-cookies on each
  mutant. `fail-batch-unanswered`, `control-enumerated`, `expiry-char-numeric` and
  `release-twice` pass it, 60 of 60; `jar-no-wakeup` fails the delaying engine's crossing test;
  `no-8.20.0-rows` fails the five by-version tests, each `(a-row-for "8.20.0")` against
  `(no-row-for "8.20.0" measured ...)`.
- `results/rule-mutants-guix.log`: on the tree, U+0002 and U+000B are `control-byte` and U+00B2
  `expiry`; `control-enumerated` takes both controls; `expiry-char-numeric` raises from `<=`.
- `results/test-cookies-base-guix-8.20.0.log`: test-cookies on the copy, 60 of 60.

## Rerun

From the repository's root, on the host:

```sh
rsync -a --delete --exclude /build --exclude /.git ./ build/m7s4-review/base/
(cd build/m7s4-review/base && scripts/guix-env make deps < /dev/null)
mkdir -p build/m7s4-review/base/probes build/m7s4-review/base/logs
cp .plans/research/m7/slice4/review/*.sps build/m7s4-review/base/probes/
cp .plans/research/m7/slice4/review/mut-run.sh build/m7s4-review/base/
python3 .plans/research/m7/slice4/review/mutants.py make
python3 .plans/research/m7/slice4/review/mutants.py list > build/m7s4-review/base/mut/jobs
(cd build/m7s4-review/base && scripts/guix-env sh -c 'sh mut-run.sh < mut/jobs' < /dev/null)
(cd build/m7s4-review/base && scripts/guix-env sh -c '"$CHEZ" --libdirs src:tests:build/scheme-libs --program probes/probe-roundtrip.sps' < /dev/null)
PROBES='probes/probe-load.sps probes/probe-engine.sps probes/probe-roundtrip.sps' \
  sh .plans/research/m7/slice4/review/probe-lanes.sh floor openssl gnutls current
```

A mutant's own probe run copies the probe into `mut/NAME/probes/` and runs it from there with
`--libdirs src:tests:../../build/scheme-libs`.
