# M7 slice 3's review: the probes and mutants it cites

Kept by the slice's read-only adversarial review (2026-11-03). Every probe ran on a copy of the
working tree, `build/m7s3-review/tree/` (rsync of the tree but `build/`, `.git` and
`.plans/research`), never on the tree itself. Rerun each from the repository's root, on the host,
after making the copy:

    rsync -a --delete --exclude /build --exclude /.git --exclude /.plans/research ./ build/m7s3-review/tree/
    cp .plans/research/m7/slice3/review/*.sps build/m7s3-review/tree/
    cp .plans/research/m7/slice3/review/probe-docker.sh build/m7s3-review/

A probe in the Guix container (8.20.0):

    scripts/guix-env sh -c '(cd build/m7s3-review/tree && $CHEZ --libdirs src:tests:'"$PWD"'/build/scheme-libs --program PROBE.sps)' < /dev/null

A probe on the four Docker lanes (floor 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS,
8.23.0), one `--rm --network none` ubuntu:24.04 from the research's apt cache; `LANES=floor` for
one:

    sh build/m7s3-review/probe-docker.sh PROBE.sps

`probe-docker.sh` is the slice's build's, run from the review's copy.

## The probes

- `keys-leak.sps`: a proxy URL holding a password, and slice 2's credentials list, handed where a
  key belongs, at both levels. `results/keys-leak-guix-8.20.0.log`: the unknown-key refusal names
  the misplaced value, and prints the password, in all nine cases; the controls print nothing.
- `env-join.sps`: below 8.19.0, does a transfer through `proxy environment` ride a live HTTP/2
  tunnel that a named proxy's transfer opened with alice's userinfo? A CONNECT to localhost needs
  alice's Basic at the origin's proxy. `results/env-join-docker.log` (four lanes),
  `results/env-join-floor-2.log` (the floor again), `results/env-join-guix-8.20.0.log`: on 7.85.0,
  twice, the environment's transfer, with no credentials, got 200 on alice's HTTP/2 connection as
  a second stream, no CONNECT of its own on the proxy's log; alone, it was refused 407. Both 8.5.0
  builds, 8.20.0 and 8.23.0 sent a CONNECT of their own, refused 407. A named proxy's transfer
  with no userinfo, the control, opened its own on every lane.
- `connect-to.sps`: the hatch's `CONNECT_TO` beside a named proxy. `results/connect-to-guix-8.20.0.log`:
  it moves the `CONNECT`'s target, the proxy seeing the h2 face's port in place of the https
  face's.

## The mutants

`mutants.diff` holds both, as diffs of the review's copies; `run-suites.sh COPY SUITE...` runs
suites on a copy in the container (`results/mutants-guix-8.20.0.txt`).

- `mut-next-verify`: `next-request` no longer carries `proxy-verify` to a redirect's hop.
  test-proxy, test-redirect and test-http-client all pass (`results/mutant-next-verify.txt`): no
  test follows a redirect through an `https://` proxy with `proxy-verify #f`.
- `mut-no-lane`: test-proxy's `lane` set to one no table has a row for. Only the pure
  `proxy-tls-in-tls, by version and backend` test fails; the engine's TLS-inside-TLS test passes,
  both its sides `(no-row LANE)` (`results/mutant-no-lane-test-proxy.txt`: 87 passes, 1 failure).

## Read in source, not run

libcurl writes a proxy URL whole, its userinfo with it, into the error buffer chez-curl hands on
as `curl-transfer-error-error-buffer` when the build has no HTTPS-proxy support: 7.85.0
`lib/url.c:2496`, 8.20.0 `lib/url.c:1994`, 8.23.0 `lib/peer.c:654` (the sources under
`build/verify/current/`). In 7.85.0 only OpenSSL, GnuTLS and NSS set `SSLSUPP_HTTPS_PROXY`; every
lane, and Apple's 8.7.1 (`sectransp.c:3454`), has it, so no lane can show it.
