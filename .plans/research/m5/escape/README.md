# A second escape in an after thunk (M5 slice 1's review, 2026-10-27)

Written by the slice's adversarial review (Opus, read-only), and rerun by the slice's author in
the container on 8.20.0, from the repository's root:

    scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs -q --program .plans/research/m5/escape/double-escape.sps'
    scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs -q --program .plans/research/m5/escape/session-escape.sps'

- `double-escape.sps`: a timer escapes from `http-get`'s await on a 10 s drip, then re-arms for N
  ticks and escapes again, N from 1 to 12, each beside controls of 300 and 1,000 ticks; then
  whether the transfer is live 300 ms on. `results/double-escape-guix-8.20.0.log`, before the
  drive's `dynamic-wind` was made critical: `still-live` at N 5 to 9, `ended` at every other N
  and every control.
- `session-escape.sps`: the same second escape, landing in `call-with-http-session`'s close,
  N from 1 to 40, and the multi handles left 200 ms on.
  `results/session-escape-guix-8.20.0.log`: the count rose by one at each N from 3 to 6, an
  engine left running each time, and held at 4. The maintainer chose to document this, not
  prevent it (ADR-0025, amended 2026-10-27).
