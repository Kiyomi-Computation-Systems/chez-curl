# Hatch mutation log (M4 slice 4)

Each mutant was applied to a copy of `src/`, `tests/` and `packaging/` under
`build/m4s4/mut/NAME`, one at a time, by `build/m4s4/mut.py`, a scratch script, which refuses
a substitution that does not match exactly once. The suites its row names then ran from that
copy in the container (Chez 10.4.0, Guix's libcurl 8.20.0 with GnuTLS 3.8.13), four at a time.
A mutant passes only if each suite exits 0.

## Sweep 1: the mechanism

The first sweep printed one line per suite for its 22 mutants: 21 failed, each by the checks
named below, and one passed.

| Mutant | Change | Failed |
|---|---|---|
| `blob-flags-nocopy` | native fills `flags` with 0, `CURL_BLOB_NOCOPY` | `call-with-curl-blob` read back |
| `blob-len-short` | `len` one short | the same |
| `string-not-copied` | a string option's value kept as the caller's | the copies; the copy sent; the string race |
| `string-not-checked` | a string option's value not checked | U+0000, CR and LF at every position; the string race |
| `list-not-checked` | a list's strings not checked | U+0000, CR and LF in each string of a list; the list race |
| `list-not-copied` | a list's strings kept as the caller's | the copies; the list race |
| `blob-not-copied` | a blob kept as the caller's bytevector | the copies |
| `name-not-copied` | the name kept as the caller's string | the copies |
| `owned-off` | no owned check | each owned option written out; the aliases; names before values |
| `owned-by-name` | the owned check by name, not id | the aliases: `FILE`, `RTSPHEADER`, `url`, `Url`, `cainfo` |
| `repeat-by-name` | the repeat check by name, not id | the repeats: by case and by alias |
| `repeat-call-only` | the repeat check against this call's options alone, the request's dropped | the repeats: across two attaches, and after `curl-request-with` |
| `type-object` | an object option taken | the types refused; names before values |
| `nul-name-unchecked` | no check of a name for U+0000 | a name holding U+0000 |
| `nul-as-line-break` | U+0000 in a value refused as `line-break` | U+0000, CR and LF in a string, and in a list |
| `string-latin-1` | a string option sent as Latin-1 | a string's UTF-8 bytes |
| `with-drops-options` | `curl-request-with` drops the options | the repeats; the copy sent through `curl-request-with` |
| `prepare-drops-options` | the plan takes no hatch setting | a string's bytes; the copy sent; the string list; the blob row; both races |
| `lists-not-freed` | the hatch's string lists never freed | both races' counts; the counts after the scenarios and after the stop |
| `curl-exports-hatch` | `(curl)` exports `curl-request-with-options` | the surface |
| `rule-j-off` | check-seam's rule (j) never fires | test-check-seam's `rule-j` tree |
| `ftype-set-unlisted` | check-seam's `ftype-set!` entry removed, so any library may import it | **passed** |

`ftype-set-unlisted` passed because test-check-seam held each entry of
`library-only-chez-names` to the libraries that import its name, and an entry removed is held
to nothing. test-check-seam now writes the list's names out; the mutant then failed it, by
name.

## Sweep 2: the owned list as decided, and the mechanism's other edges

After the maintainer's decisions (ADR-0009, amended 2026-10-27), 14 mutants: 13 failed, each by
the checks named below, and one is equivalent on every platform chez-curl runs.

| Mutant | Change | Failed |
|---|---|---|
| `owned-resolve-dropped` | `RESOLVE` dropped from `owned-option-names` | test-transfer's list written out; test-unsupported's own list, refused at attach |
| `owned-transfertext-dropped` | `TRANSFERTEXT` dropped | the same two |
| `reason-repeated-dropped` | `repeated-option` dropped from the request error's reasons | the reasons written out, and the constructor, in test-conditions; the repeats and names before values, in test-unsupported |
| `field-renamed` | the hatch's refusals name the field `hatch` | every refusal of a name or a string |
| `lf-allowed` | LF taken in a value | U+0000, CR and LF in a string, and in a list |
| `blob-raw-bytes` | a blob set as its bytes' address, no `struct curl_blob` | the blob row: on 8.20.0, `SSLCERT_BLOB` refused where it is taken |
| `slist-null` | a string list set as NULL | the string list reaching libcurl; the list race |
| `lists-unrecorded` | a list built but not recorded, so set as NULL and never freed | the string list; both races; the counts |
| `settings-unreversed` | the settings kept in reverse attach order | each type's setting read back; the copies |
| `settings-applied-reversed` | the engine applies them in reverse | `set-transfer-options!` form by form, in test-transfer |
| `hatch-before-tls` | the hatch's settings applied before the TLS settings | `set-transfer-options!` form by form, in test-transfer and test-transfer-tls |
| `lists-freed-first` | the hatch's lists freed before the easy handle | `free-transfer!`'s order, in test-transfer |
| `long-as-off-t` | a long's value checked as an `off_t` | **passed: equivalent.** A C long is 64 bits on every platform chez-curl supports, as `off_t` is |

## Sweep 3: the slice's review

The adversarial review (Opus, read-only) ran its own mutants in copies of the tree. Two
passed every check, and each is fixed, then watched failing here:

| Mutant | Change | Before the fix | After it |
|---|---|---|---|
| `curl-renames-hatch` | `(curl)` re-exports the hatch's procedure from `(curl private transfer)` as `request-with-options` | **passed** check-seam and test-unsupported: rule (j) closes the route through `(curl unsupported)` alone, and the surface check matched the name | test-unsupported's surface check, which holds `(curl)`'s exports by what each is bound to |
| `curl-exports-hatch` | the same, under its own name | test-unsupported's surface check, by name | the same, by binding |
| `cache-nocopy` | `option-found` keeps the caller's string as the cache's key | **passed** test-transfer: the hatch copies a name before the lookup | the option cache's copy, now looked up through `option-named` in a caller's string |

The review's other mutants, a hatch that keeps the caller's name or value uncopied, failed
test-unsupported.
