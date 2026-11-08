# M8 slice 4, measured before the docs

Read-only measurement, 2026-11-08, on `feat/m8-docs` off `main` at `fb62a0b` (slices 1 to 3
merged), for the docs the plan's §3.5 and §7 fix. Nothing outside this directory was written; no
page and no example exists yet. Re-measures the docs survey (`../surveys/docs.md`, at `fbc6fce`).

## The files

| File | What it holds |
|---|---|
| `inventory.sexp` | every export of `(curl)`, `(curl unsupported)` and `(http-client)`, one list each, readable by `read`: library, kind, topic, signature comment verbatim, the prose under it, its block's intro and section, what it raises with a code citation, comment against code, and the record citations its comment carries. Made by `inventory.py` from the export forms and a hand-written table; read back by `inventory-check.sps` (`logs/inventory-check.txt`) |
| `promises.md` | the survey's 45 promises re-read, and M8's 23 new ones, each with README.org's state and its page |
| `readme-claims.md` | every claim of README.org, 312 rows, against today's code and the suites; the nine blocks; what README.org lacks |
| `by-version.md` | every per-version table in `tests/`, the cells a caller meets by libcurl and topic, the default part types, and what no table pins |
| `examples.md` | ten examples proposed, each one's routes and output, measured on the Guix lane; how a suite runs one; what a child costs, natively and under the gate |
| `environment.md` | each variable the load and a transfer read, and the candidate lists, by platform |
| `stale.md` | every "not yet", "TODO", "on main", "M[0-9] slice" and the like outside `.plans/`, classed |
| `kinds.sps`, `exports.sps`, `load-probe/`, `child/` | the programs behind `logs/` |

## The exports, against the survey's 194

| | Survey (`fbc6fce`) | Today (`fb62a0b`) |
|---|---|---|
| `(curl)` | 134 | 134 |
| `(curl unsupported)` | 1 | 1 |
| `(http-client)` | 59 | 59 |
| total | 194 | 194 (`logs/exports.txt`, `library-exports`) |
| procedures | — | 167 (`logs/kinds.txt`) |
| values, each a list of reason symbols | 7 | 7 |
| condition types (syntax) | 20 | 20 |
| procedures and values with a signature comment | 174 of 174 | 174 of 174; the six transfer classes share one block with no `&name:` line, as before |
| `curl-request-error-reasons` | 39 | 45 (+6: `part-bytes`, `part-empty`, `multipart-empty`, `multipart-content-type`, `part-file`, `multipart-unsupported`) |
| `curl-transfer-error-reasons` | 11 | 14 (+3: `header-limit`, `part-file`, `mime-failed`) |
| `http-request-error-reasons` | 17 | 18 (+1: `multipart-beside-body`) |
| the other four reason lists | 6, 2, 4, 3 | the same |
| lines citing an ADR in `src/curl.sls` / `src/http-client.sls` / `src/curl/unsupported.sls` | 19 / 32 / 2 | 20 / 34 / 2; plans 0 / 8 / 1, research paths 0 / 2 / 0, dates 1 / 10 / 0, slices 1 / 3 / 0 |
| exports whose comment, block or section cites a record | — | 79 of 194 (`inventory.sexp`, `cites`) |
| comment against code | — | 3 disagree, 12 partly, 3 notes, 176 agree as far as read |

**No export was added or removed since `fbc6fce`.** The three export forms changed in comment
lines alone (`git diff -U0 fbc6fce..HEAD -- src/curl.sls src/http-client.sls
src/curl/unsupported.sls`: every changed line is a `;;` line). What changed under the same names:
`make-curl-request`'s and `curl-request-with`'s `body` takes `(multipart PART ...)`;
`curl-request-with` takes a `url` key (it took none at `fbc6fce`); `curl-request-body` answers a
multipart body as a copy; every `(http-client)` call takes `multipart`; the reason lists above;
`&curl-too-large` takes `header-limit`; `curl-transfer-error-request-size` reads differently for
multipart; and every transfer caps its response headers.

**What loads libcurl** (`logs/load-probe.txt`, 14 probes, `CHEZ_CURL_LIBCURL` relative so the
load refuses): the condition types, their predicates and accessors, the reason lists and
`libcurl-info`'s accessors load nothing; every other export loads libcurl at its first reference,
before the program's body, `http-retry?`, `http-response?` and `make-curl-request` among them.

**The disagreements** (`inventory.sexp`, `comment-vs-code`): `curl.sls:543` lists `&curl-too-large`'s
codes as "63, 100, and the body limit", without the header cap; `http-client.sls:526-536` lists 17
of `http-request-error-reasons`' 18, without `body-length-mismatch`; and three public signatures
are wider or narrower than the private ones: `curl-request-method` `Symbol` (private: the six
methods), `curl-response-http-version` and `curl-head-http-version` the four versions (private:
`Symbol`). The twelve partly: chiefly the public comments of `make-curl-request`,
`curl-submit`, `curl-request-check`, `make-curl-engine` and `curl-engine-stop`, which name fewer
refusals than the code makes; and the jar procedures, whose libcurl refusals raise Chez's `&error`,
no chez-curl condition (`engine.sls:1655-1673`, `transfer.sls:2895-2897, 2916-2918`).

## What changed since the survey

- **README.org:** unchanged. Its claims: of 312, 295 held, 1 wrong, 16 partly; 46 held by no test
  (`readme-claims.md`, Counts). The survey's ten: nine carried over, the code unchanged where each
  rests; claim 7 (`MAXREDIRS`, 47) is partly now, since the header cap can end such a loop first
  when its heads are large.
- **The one wrong claim:** README.org:237-238, `SUPPRESS_CONNECT_HEADERS` "stays" the hatch's.
  It is owned since slice 2 (`transfer.sls:2312`), refused `owned-option`
  (`tests/test-unsupported.sps:478`; ADR-0037, amended 2026-11-06).
- **The promises:** 45 rows, kept 24 (was 25), partly 5, partly superseded 1 (row 41, the line
  above), no 13, n/a 1, superseded 1. M8 adds 23 rows, none kept by README.org today.
- **Stale lines:** `packaging/debian-prereqs.txt:4`'s "NOT YET EXERCISED", the plan's own;
  README.org:66's "does not read it yet", which the plan's search terms miss; 41 slice citations in
  `src/` comments; nothing "unreleased", no `FIXME`.

## What varies by libcurl, and the default types (`by-version.md`)

- **45 tables** in `tests/`: 33 of per-version rows, the five `known-*.sexp` files, 7 rule or
  threshold tables. **104 caller-facing rows** in 14 topic tables, 86 of them differing by
  libcurl; **15 cells only the suites meet** (a seam, Valgrind, Node's version, a decoy); **14
  per-version behaviours a caller can meet that no table pins** (§5 there), among them 8.5.0's
  stall past a URL of 131,041 chars and 7.85.0's early HTTP/2 200 that never ends.
- **No 8.7.1 row:** `stall-verdicts` (`test-engine.sps:410-420`, Linux alone: no `LD_PRELOAD` on
  macOS) and `guix-pin-verdicts` (Guix alone); `tls-in-tls-checks` and `blob-rows` hold 8.7.1 with
  SecureTransport alone, the backend `make test` sets.
- **The 8.20.0 OpenSSL build** (`known-libcurls.sexp`'s fifth row) was measured once, before M5,
  by ADR-0020's run; no table since has run on it, and three keyed by backend or PSL hold no row
  for it (question 9).
- **The default types are alike on every libcurl:** ten extensions, `.gif`, `.jpg`, `.jpeg`,
  `.png`, `.svg`, `.txt`, `.htm`, `.html`, `.pdf`, `.xml`, matched at the name's end in any ASCII
  case; a file part then takes its path's, then `application/octet-stream`; a data part with no
  filename or an unknown extension gets no `Content-Type`; a given `type` wins. The table is the
  same in five source trees (`lib/mime.c`; my rehash of the ten rows, whitespace dropped: one
  digest, `3191a088...`, in all five) and was measured on the five Linux lanes and the Mac.
- **8.7.1 often behaves as a named version and goes unnamed:** README.org's seven rows
  (`readme-claims.md`), and `curl.sls:336-341`, which has 8.5.0 alone drop a server's prefixed
  cookie where the table shows 8.7.1 doing so too (`test-cookies.sps:930`).

## The examples (`examples.md`)

Ten, every one on the plaintext `http` face, its URL the first argument, run from the root:
`quick-start`, `form-and-params`, `multipart`, `session-retries`, `stream-download` (high level),
`stream-upload` (low level), `group`, `cookie-jar` (low level), `errors` (both levels),
`engine-and-tokens` (low level). Nine were run once as a prototype on the Guix lane, their output
in `logs/proto-outputs-guix.txt`; none prints a port, a boundary, a timing or a version. A child
costs 0.47 to 0.57 s, natively and under the gate alike, since Valgrind does not follow children.

## Questions a page or a check needs decided

Each with options and a recommendation; the maintainer's to choose.

1. **How does an example's counts line reach the suite?** The plan (§3.5) has the example print
   its native counts, which needs `(curl private counters)` in every example.
   (a) As the plan says. (b) A wrapper, `tests/example-runner.sps`, loads the example by
   `load-program` in its own process and prints the counts on stderr; the example imports public
   libraries alone (prototype `child/example-runner.sps`, 5 runs, counts zero,
   `logs/child-cost-native.txt`). (c) No counts: breaks AGENTS.md's counters rule.
   **Recommend (b),** and amend the plan's §3.5 line; an example then must not call `exit`.
2. **Where do the URL functions and ADR-0008's leniencies go?** `curl-url-part`,
   `curl-url-append-query`, `curl-url-resolve` and `curl-url-with-fragment` fit none of the plan's
   topics, and promises 4 and 5 ask the docs to list curl's leniencies, by version.
   (a) A "URLs" section of the low-level page, the leniencies on "what varies by libcurl".
   (b) A `docs/urls.md` of its own. (c) The reference alone, and promises 4 and 5 marked open.
   **Recommend (a).**
3. **The records that name README.org as the place** (`promises.md` §3: `global-constraints.md:295`,
   ADR-0024:63, :282, :307, :343, ADR-0009:318, :320, ADR-0030:78, ADR-0031:80, :119, ADR-0032:89).
   The plan moves those sections to `docs/`. (a) Amend each line to "the docs". (b) One line in
   ADR-0038's consequences: a record's "README.org says" is kept by the docs' pages, README.org
   linking them. (c) Keep those topics in README.org, past 150 lines. **Recommend (b);**
   `global-constraints.md:295` gets the same words, being a hard rule.
4. **How an example is handed the origin, and from where it runs.** (a) The `http` face's base
   URL as its first argument, run from the repository root, file parts under `examples/data/`.
   (b) An environment variable, e.g. `CHEZ_CURL_EXAMPLE_ORIGIN`. (c) A path computed from the
   example's own file. **Recommend (a):** a caller can run it by hand against any server, and
   `(cadr (command-line))` is the one line it costs.
5. **The two comment disagreements, and the three signatures.** The reference is hand-written,
   but the review "compares the types with the code" (plan §3.5). (a) Fix the five comments in
   `src/` in slice 4, comment lines alone. (b) Leave them; the reference says what the code does.
   **Recommend (a):** `curl.sls:543` and `http-client.sls:526-536` would otherwise disagree with
   the reference the review checks; take the narrower type for each signature.
6. **The jars' `&error`.** A libcurl refusal inside a jar's make, read-out or load raises Chez's
   `&error`, no `&curl-error`. (a) The reference says so, and the code stays. (b) A code change,
   a reason of its own: not this slice. **Recommend (a),** carried as an item for later.
7. **A `body-limit` under a declared length is libcurl's 63, `perform-failed`, not `body-limit`**
   (`examples.md`, measured on Guix: `MAXFILESIZE_LARGE` refuses before a chunk arrives). The class
   is `&curl-too-large` either way. (a) The errors page says both reasons, by when the length is
   known. (b) Map 63 to `body-limit` in code: ADR-0040's rejected option's kind ("Mapping
   libcurl's own codes"). **Recommend (a),** after the slice's suite sees 63 on every lane.
8. **The request size on 8.7.x:** the plan's §3.8 says "0 on 8.7.x"; chez-curl answers `#f` there
   (`transfer.sls:2005-2015`). Not a choice: the page says `#f`. Listed so the page follows the
   code, not the plan's line.
9. **Which libcurls the "what varies" page names.** (a) The six the suites run today: 7.85.0,
   Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Apple's 8.7.1, Guix's 8.20.0, 8.23.0. (b) The
   seven rows of `known-libcurls.sexp`, the 8.20.0 OpenSSL build among them, measured once before
   M5. **Recommend (a),** the page saying "measured on these libcurls", and the release's Known
   limitations the same six.

## The subagents

| Agent | Model | Tokens | Tool uses | Time |
|---|---|---|---|---|
| README.org's claims (`readme-claims.md`) | Opus | 325k, and its four range agents' 1,212k (271k, 354k, 273k, 314k) | 95 | 23.9 min |
| the per-version tables (`by-version.md`) | Opus | 542k | 173 | 26.7 min |

I checked each hand-back: reran readme-claims' two checks, each output identical to its log; read
its wrong row and a held, a partly and two unheld rows at their lines; read four of by-version's
cited rows, the missing 8.7.1 row and the default-types table in all five trees. One correction,
mine, in `by-version.md` §4: libcurl, not chez-curl, gives a file part its path's base name
(`curl_mime_filedata`, 7.85.0 `mime.c:1437-1446`; `native.sls:1415-1419`).

## Corrections, after the build

- **`inventory.sexp`'s five `curl-request-error` rows** (`curl-request-error?`, `-field`,
  `-value`, `-reason`, `-reasons`) say they load libcurl and refuse "not a request". They load
  nothing, as `logs/load-probe.txt` shows for `curl-request-error-reasons`, and refuse anything
  that is not a `&curl-request-error` (`src/curl/private/conditions.sls:606-611`). Found by
  builder B; the reference follows the code.
- **`src/curl.sls` line citations past 342** are one line early: slice 4's comment fix at
  `:336-342` added a line.
