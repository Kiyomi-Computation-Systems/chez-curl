# Environment mutation log (M4 slice 3)

Each mutant was applied to a copy of the tree, one at a time, by `build/m4s3/mut.sh`, a scratch
script, and the suites its row names ran there through `make test SUITES=...` in the container
(Chez 10.4.0, Guix's libcurl 8.20.0, so a Guix libcurl: the pin's refusals fire). A mutant
passes only if the summary reads `failed 0, hung 0`. Each substitution was first checked to
apply. The first sweep printed one line for each of its 28 mutants, and `done`: all 28 failed,
each by the checks named below.

| Mutant | Change | Failed |
|---|---|---|
| `pkcs11-case-sensitive` | the prefix compared without folding | the sixteen ASCII cases; the change after the request was made; `pkcs11-prefix?` alone |
| `pkcs11-unicode-fold` | folded by `char-foldcase` | the near misses, U+212A and U+017F among them; `pkcs11-prefix?` alone |
| `pkcs11-char-downcase` | folded by `char-downcase` | the same: U+212A |
| `pkcs11-no-colon` | the prefix `pkcs11`, without its colon | the near misses: `pkcs11`; `pkcs11-prefix?` alone |
| `pkcs11-dropped` | no prefix check | the sixteen cases; the change after the request was made; `ca-file-copy` held whole |
| `pkcs11-before-nul` | the prefix checked before U+0000 | U+0000 checked first; `ca-file-copy` held whole |
| `env-check-dropped` | `prepare-transfer`'s environment check replaced by a form that keeps `ca-file`'s count | the pin's five refusals |
| `env-check-dropped-whole` | the same, keeping the call's arguments | the same |
| `env-verify-ignored` | verification off refused too | `overriding-variables` alone; the pin with verification off |
| `env-no-ca-file-refused` | a request with no CA file refused | `overriding-variables` alone; the pin with no CA file |
| `env-path-only` | the path as loaded decides, not the mapped file | `ca-overridden?` and `overriding-variables` alone |
| `env-file-only` | the mapped file alone, no path where none was read | the same |
| `env-row-only` | a version with no row not taken to override | the same |
| `env-table-emptied` | `guix-ca-overrides` empty | the table held to the suite's copy |
| `env-store-no-slash` | the prefix `/gnu/store`, so `/gnu/storex/` is Guix's | `ca-overridden?` alone |
| `env-first-name-only` | only the first variable set named | `overriding-variables` alone; the pin with both set |
| `env-read-at-submit` | native's record read from the environment at each submit | the pin: a variable set after the load, and one emptied after it |
| `env-empty-is-set` | an empty variable recorded as set | the pin: `SSL_CERT_FILE` empty |
| `native-file-is-path` | the file recorded as the path as loaded | `loaded-libcurl-file` against the suite's own reading of the maps; the pin's file line |
| `maps-end-inclusive` | a range's end taken as its own | `mapped-file` past a range's end |
| `maps-start-exclusive` | a range's start not its own | `mapped-file` at a range's first byte |
| `proxy-none-ignored` | `#f` sets nothing | the proxy child: `http_proxy` and `all_proxy` with `#f` |
| `proxy-noproxy-star` | `#f` sets `NOPROXY` `"*"`, which also goes direct | `set-transfer-options!` form by form |
| `proxy-default-off` | the default `#f` | the defaults, in test-request |
| `proxy-unchecked` | any value taken | the proxy key's types |
| `proxy-with-dropped` | `curl-request-with` resets the proxy | each key sets its own field; `curl-request-with` keeps it |
| `proxy-twin-dropped` | `NOPROXY` unowned | `owned-option-names` written out; the proxy's twins refused by the seam |
| `origin-absolute-unrouted` | the origin routes an absolute-form target as before, to 404 | test-origin's absolute-form rows; the proxy child's cases through the proxy |

## The second sweep

The first sweep showed two kills that rested on one lane. `env-check-dropped` and
`env-check-dropped-whole` failed only the pin, whose refusals fire on a Guix libcurl alone,
so on CI's FHS lanes they would pass. And `proxy-default-off` failed only test-request's
read of the default: the proxy child always passed the key, so no transfer ran on the
default. test-transfer-tls now holds `prepare-transfer`'s call of `check-ca-environment`
whole, test-transfer's order check names it, and the child leaves the key out for its
default cases. The three ran again:

| Mutant | Failed |
|---|---|
| `env-check-dropped` | `prepare-transfer` hands the plan its snapshot, the call held whole; the pin's five refusals |
| `env-check-dropped-whole` | the same |
| `proxy-default-off` | the defaults; the proxy child with no key, through `http_proxy` and `all_proxy` |

## After the slice's review: the third sweep

The review proved two gaps in copies of the tree. `env-read-at-submit` passed off the store:
the pin's child printed native's record before changing the environment, so outside Guix
nothing read the record again. And a copy of Guix's 8.20.0 out of the store replaced the CA
file unrefused. The child now prints the record after its change; the maintainer added the
patch's literal to the key (ADR-0024, amended: the key); native's accessors copy every string
and pair they answer, and a check holds it. The list, its rows rewritten for the new
signatures, ran whole again on the fixed tree, with nine new mutants: 37 lines and `done`,
36 failing, as named.

| Mutant | Change | Failed |
|---|---|---|
| `env-patch-ignored` | the patch's literal not read by `ca-overridden?` | `ca-overridden?` and `overriding-variables` alone; the pin's copy out of the store |
| `env-patch-only` | the literal alone, the store's path not read | the same rules alone |
| `native-patch-false` | native records no literal, ever | `loaded-libcurl-patched?` against the suite's own search; the pin's copy |
| `native-vars-no-copy` | `loaded-ca-variables` answers native's own pairs | fresh objects; and every later CA-file transfer in the suite, refused once the check's change reached native's record |
| `native-file-no-copy` | `loaded-libcurl-file` answers native's own string | fresh objects |
| `bytes-end-missed` | a pattern at the very end not found | `bytes-hold?` |
| `bytes-skip-overlap` | the search jumps past a partial match | `bytes-hold?`: the pattern after a partial one |
| `bytes-first-only` | a match on the first byte alone | `bytes-hold?` |
| `env-read-at-submit`, again | as above | fresh objects; the pin: set after the load, and emptied after it |

Each of the first sweep's 28, with its row rewritten where the code moved, failed again, by
the checks named above or more. On an FHS lane, Docker `ubuntu:24.04` with its libcurl 8.5.0,
`env-read-at-submit` alone ran `test-transfer-tls`: 73 passed and 3 failed, the two after-load
rows and fresh objects. Before the fix, the review saw it fail nothing more than the tree did,
on a copy of the container's libcurl out of the store.

## Unchecked, by design

- **`native-patch-path-only`, which survived:** native reads the literal from the path as
  loaded, not the mapped file. On every lane the path resolves to the mapped file, so the two
  read the same bytes; they differ only for a path changed in the instant between the load
  and the read.

- **The override itself, seen through the library.** On a Guix libcurl a submit refuses
  before libcurl could write a variable over the CA file, so no suite sees the write. The
  measurement is its evidence (ADR-0024, amended 2026-10-26).
- **The refusal by behaviour on CI.** CI's lanes load FHS libcurls, where the pin shows the
  variables ignored. Its rule, `overriding-variables`, is pure and held on every lane, and the
  shell that hands it native's records is held whole.
- **The path standing in for an unread file.** Linux always had `/proc/self/maps` here, and
  macOS has no Guix. `ca-overridden?`'s rows hold the rule alone (`env-file-only`).
