# Which `Expect` values make libcurl wait for a 100 (M6 slice 1's fix round, 2026-10-30)

The slice's review found that a caller's `Expect: 100-continue` makes libcurl resend a request
inside one transfer on a 417 (`../../slice1-review/`). The builder of the fix probed which values
make libcurl wait, so the refusal covers each one. I filed the probe here and ran the 8.20.0 lane.

| File | What it is |
|---|---|
| `waits.sps` | a `post` with a whole body and each `Expect` value, against `waits-server.mjs`; prints `(VALUE ANSWER)` |
| `waits-server.mjs` | answers `waited` when the body came after a 100 it sent, `sent` when the body came with the head |
| `docker-waits.sh` | host: 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, and 8.23.0, in `ubuntu:24.04` |
| `auto-expect.sps` | that the request's own `Expect:` still keeps libcurl's from a streamed `put`, `patch`, a small `post` and a 1.5 MiB `post` |
| `results/docker-waits.log` | the builder's run of `docker-waits.sh` |
| `results/docker-waits-rerun.log` | mine, the same, every line identical |
| `results/guix-8.20.0-waits.log` | mine, in the container |
| `results/guix-8.20.0-auto-expect.log` | `auto-expect.sps` against `../../slice1-review/expect417-server.mjs`, which answers 417 to any request that carries `Expect`: each streamed request made one request, `expect=no`, head 200 |

Run the container's lane from the repository's root:

```
scripts/guix-env sh -c 'node .plans/research/m6/slice1-fix/expect/waits-server.mjs > $TMPDIR/p 2> $TMPDIR/s & pid=$!; sleep 1; $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m6/slice1-fix/expect/waits.sps $(cat $TMPDIR/p); kill $pid' < /dev/null
```

**What they show:**
- **7.85.0 and both 8.5.0 builds** wait on `100-continue` anywhere in the value, in any ASCII
  case: `x100-continue`, `y100-continuez`, `a 100-continue` and `100-continue;q=1` all waited.
- **8.20.0 and 8.23.0** wait only when it is an element of a comma list: `100-continue`,
  `100-Continue` and `a,100-continue` waited; the rest were sent at once.
- **So the refusal matches `100-continue` anywhere in any `Expect` header's value,** ASCII case
  folded, the floor's rule, which covers the newer one.
