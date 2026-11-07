# M8 slice 2, the review's fixes: the logs

The fixes for the slice's Opus review, one major and the minors, made in the repository's tree on
`feat/m8-header-cap`, 2026-11-07. The tree's sums are in `snapshot-sums.txt`; the Docker lanes ran a
copy of it, `build/m8s2/work.zJZXLW/snap-fix`.

The changes:

- `status-line?` reads `HTTP/`, a digit, then a `.` and a digit or not, then a space. It used to
  read the `HTTP/` prefix alone. `count-header-line!` still asks it only at a head's start.
- `tests/origin.mjs`'s raw head routes take three new parameters, all refused on HTTP/2 with 404:
  - `hname=1` names every generated line `HTTP/1.1 x-NNNNNN`;
  - `tname=1` names the first trailer `HTTP/x`;
  - `v10=1` writes every head's status line as `HTTP/1.0`.
- `test-headers` gains three pairs, buffered and streamed:
  - 1,000 `hname` lines taken, 1,001 refused;
  - the `tname` trailers: 998 taken and 999 refused by lines; 300 of 256 bytes taken and 400 refused
    by bytes;
  - 1,000 `v10` lines taken, 1,001 refused.
- `test-transfer` adds two tests:
  - each header seam constructor's refusals, by who and by message;
  - `request-like`'s refusal of `(mark 0)`, `(mark -1)`, `(mark 1.5)` and `(head 0)`.
- `request-like` is exported from `(curl private transfer)` for that second test.
- `test-origin`'s `total=` rows expect `total` itself.

## Why `hname` is `HTTP/1.1 x-NNNNNN` and not `HTTP/N`

With the strict pattern in place, a header named `HTTP/1` or `HTTP/1.1`, its colon straight after
the name, is no status line anywhere. So such a name cannot tell a dropped `start` from a kept one.
A name that holds the pattern's space, `HTTP/1.1 x-000001`, does tell them apart: libcurl takes it
as a header on every lane (`odd/`, case h).

## The odd-header probe: `odd/`

The probe sends each odd head through `(curl)`, buffered.

- **Lanes:** Guix's 8.20.0 (`logs/odd-guix.log`), and in Docker 7.85.0, Ubuntu's 8.5.0 with OpenSSL
  and with GnuTLS, and 8.23.0 (`logs/odd-docker.log`).
- **Mid-head lines libcurl takes as headers, on all five:** `HTTP/1 : v`, `HTTP/1.1 x: v`,
  `HTTP/1: v`, `HTTP/1 200: v` and `HTTP/1.1 x-000001: vvvv`.
- **A bare `HTTP/1.1 200 OK` mid-head** is refused with 8.
- **A bare `HTTP/1.1 200 OK` as a trailer** is refused with 43, or with 8 on 8.23.0.
- **First trailers libcurl takes, 200:** `HTTP/x: v`, `HTTP/x-000001: vvvv`, `HTTP/1.1 x: v`,
  `HTTP/1 : v` and `HTTP/1.1: v`.
- **An HTTP/1.0 head** is taken.

Cases k and l show the hole that is left: a trailer section's first line that matches the strict
pattern is exempt, so the count comes out one line under, once for each trailer section.

## Logs

| log | what |
|---|---|
| `dev-four.log` | lane X: `test-headers`, `test-origin`, `test-origin-tls` and `test-transfer`, first run of the new tests |
| `test-guix.log` | lane X: `make test`, every suite |
| `test-docker.log`, `test-fix-{floor,openssl,gnutls,current}.log` | lanes F, O, G and C: `make deps test`, every suite |
| `memory-guix.log`, `memory/` | lane X: `make test-memory` of `test-headers`, `test-origin` and `test-origin-tls`, with Valgrind's logs |
| `ci-chain-guix.log` | lane X: `make check-help check-suites check-seam check-floors build test check-test-fails check-dev check-clean` |
| `mutants.py`, `mutants-make-2.txt`, `mutants-run-{1,2}.log`, `mutants-check-{1,2}.txt`, `mutants/` | the mutants, run in lane X by `../mut-run.sh` and checked by name |

`mutants-run-1.log` and `mutants-check-1.txt` are the first run. There, `test-origin` failed its two
SIGKILL tests in every copy, the control's too, because the copies had no `build/scheme-libs` for the
child Chez. Since then, `mutants.py make` links it into each copy. Run 2 reran the control and the two
`route-short` mutants; every other mutant's verdict is from run 1.
