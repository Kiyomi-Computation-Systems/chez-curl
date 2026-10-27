# The M5 plan review's probes (2026-10-27)

Run by the plan's adversarial review (Opus, read-only) in the Guix container, libcurl 8.20.0,
and rerun by the plan's author there, each alike.

- `rawhost.c`: does `curl_url_get` hand back bytes that are not UTF-8? A Latin-1 byte in each
  part of a reference, resolved against a base, read back whole and by part.
  `results/rawhost-guix-8.20.0.log`: the host and the user info come back raw, `caf\xe9`; the
  path, query and fragment come back as `%E9`; a host's case and an explicit `:80` are kept.

      scripts/guix-env sh -c '$CC -o build/rawhost .plans/research/m5/review/rawhost.c $CHEZ_CURL_LIBCURL && build/rawhost'

- `random-seed.ss`: Chez's `random` draws the same sequence in every process, from a fixed
  `random-seed`; a `make-pseudo-random-generator` draws differently in each.
  `results/random-seed.log`, three processes.

      scripts/guix-env sh -c 'for i in 1 2 3; do $CHEZ -q --script .plans/research/m5/review/random-seed.ss; done'
