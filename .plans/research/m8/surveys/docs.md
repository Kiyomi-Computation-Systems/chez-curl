# M8 survey C: the docs and the v0.1.0 release

Read-only survey, 2026-11-06, of chez-curl on `docs/m8-plan` (at `fbc6fce`, clean), with the
siblings' local clones under `~/src` read for precedent. Nothing was run but `git` read-only
commands, `grep`, `awk` and one counting script of mine (in the session's scratchpad, not the
tree). It recommends nothing. Paths without a prefix are chez-curl's; a sibling's carry
`~/src/<repo>/`.

The rules it reads against, from `AGENTS.md`: a Typed Racket style signature comment on every
exported function (AGENTS.md:14); a `CHANGELOG.md` entry per release (:46); `/docs` for
user-facing documentation only (:47); documentation very concise, focused, ELI5 (:48).

## 1. README.org today

**Shape.** 588 lines, 9 `#+begin_src` blocks. Its headings, with the lines under each:

| Heading | Lines | |
|---|---|---|
| `* Chez Scheme HTTP Client` | 1–10 | CI badge (:3), one-line description (:5), AI disclosure (:7–9) |
| `** Requirements` | 11–16 | three list lines, held exactly by `make check-floors` (tests/floors.sls:51–57, 363–372) |
| `** Status` | 17 | **empty** |
| `** Quick start` | 19 | **empty** |
| `** Configuration` | 21–584 | every topic below sits under this one heading |
| `*** What a transfer reads from the environment` | 23–71 | 48 |
| `*** Choosing the HTTP version` | 72–111 | 39 |
| `*** Giving credentials` | 112–166 | 54 |
| `*** Going through a proxy` | 167–246 | 79 |
| `*** Keeping cookies` | 247–321 | 74 |
| `*** Options chez-curl does not wrap` | 322–353 | 31 |
| `*** Reading a response as it arrives` | 354–402 | 48 (low level) |
| `*** Sending a body as it is produced` | 403–459 | 56 (low level) |
| `*** What follows a redirect` | 460–480 | 20 (high level) |
| `*** Reading a call's response as it arrives` | 481–519 | 38 (high level) |
| `*** Sending a call's body from a producer` | 520–564 | 44 (high level) |
| `*** Running calls at once` | 565–584 | 19 (high level) |
| `** License` | 585–588 | BSD 3-Clause, links `LICENSE` |

**Who it is written for.** A caller writing a program ("your program", "you submit"), who
already knows the API: there is no introduction to sessions, engines, requests or responses,
no install step, and no first example (Status and Quick start are empty headings). The
sections read as a reference for the M4 to M7 surface's edges: environment variables, refusals,
and what each libcurl version does. 35 lines besides the floor's name a specific libcurl
version (:37, 45, 68, 97, 98, 127, 141, 187, 208, 214–216, 219, 223–230, 280–290, 295, 400,
447–448, 454, 556, 560, 576). Of the 194 public exports (§2), README.org names 36, by an
identifier match: none of `http-get`, `make-http-session`, `make-http-retry`,
`curl-token-cancel`, `make-curl-mailbox`, `loaded-libcurl`, or any condition predicate. The
brief names the first consumer as "ad-hoc scripting" (brief:5).

**Ten claims checked against the code. All ten held.**

| # | README.org | The code | Held |
|---|---|---|---|
| 1 | :13 Chez 10.4.0 or later, threaded | `src/curl/private/require-threaded.sls:43` `minimum '(10 4 0)`; :79–89 refuse `(threaded?)` #f, then an older Chez | yes |
| 2 | :14 libcurl 7.85.0 or later, with TLS | `src/curl/private/verify.sls:26` `libcurl-floor #x075500`; :35–41 `below-floor`, then `no-ssl` | yes |
| 3 | :51–53 a `ca-file` beginning `pkcs11:`, any case, refused | `src/curl/private/transfer.sls:492–500` `pkcs11-prefix?`; reason `pkcs11-url`, `conditions.sls:387` | yes |
| 4 | :64–65 `make test` sets `CURL_SSL_BACKEND=secure-transport` on macOS | `Makefile:34–37` | yes |
| 5 | :95–101 chez-curl never sets `PIPEWAIT`; the hatch's still works | no `"PIPEWAIT"` string anywhere in `src/`; absent from `owned-option-names` (`transfer.sls:1781–1798`) and `pinned-options` (:1818–1820) | yes |
| 6 | :105–107 the hatch refuses `HTTP_VERSION`, `SSL_ENABLE_ALPN`, `ALTSVC`, `ALTSVC_CTRL` | `transfer.sls:1628` (`http-version`'s option), :1793 | yes |
| 7 | :154–159 the hatch refuses `MAXREDIRS`; every transfer stops after 30 follows | `transfer.sls:1783`, `pinned-options` `("MAXREDIRS" . 30)` :1818–1820 | yes |
| 8 | :186–187 a proxy URL with no port gets 80 or 443 | `src/curl/private/url.sls:324–329` | yes |
| 9 | :264, :274–275 a jar holds cookies alone; a loaded name and value at most 4,096 bytes | `transfer.sls:2181` `share-settings`, `CURL_LOCK_DATA_COOKIE` alone; :2190 `cookie-line-limit 4096` | yes |
| 10 | :432, :462–463, :512 a put waits at 64 KiB; 301/302/303/307/308 followed, 20 by default; `stream-buffer` 64 KiB by default | `transfer.sls:3124` `upload-buffer-limit 65536`; `src/http-client/private/exchange.sls:591`; `src/http-client/private/call.sls:101`, :106 | yes |

Also held, checked the same way: :98–100 and :400–401, no multiplexing on 8.7.0 and 8.7.1
(`src/curl/private/engine.sls:408`); :66–67, `OPENSSL_X509_TEA_DISABLE` not read (no match in
`src/`); :148–149, a request prints its type alone (`transfer.sls:1029`, `(opaque #t)` :1055).

**Process detail in README.org.** No slice history, ADR number, `.plans/` path or date appears
in it (grep for `ADR`, `slice`, `.plans`, `M[0-9]`: no match). What reads as test or
measurement detail rather than use:

- :15, "Node.js 20 or later, for the tests": a contributor's requirement, but `check-floors`
  requires that exact line (tests/floors.sls:363–372), so it cannot leave the section alone.
- :65, "`make test` sets it on macOS": the suites' setting.
- :292–294, a load's measured times (10,000 lines 0.24 to 0.50 s; 50,000 up to 27 s; a
  read-out 1.7 to 6.4 s).
- :144–147, measured lengths (8 KiB, 64 KiB, 1 MiB) and their codes by version.
- :336, "can change what chez-curl tests".
- :3, the CI badge.
- The per-version bullets are the libcurls the CI lanes and the Mac load (7.85.0, 8.5.0 with
  OpenSSL and GnuTLS, 8.7.1, 8.20.0, 8.23.0): user-facing limits, but measured lane by lane.

**What reads it.** Only `make check-floors` reads README.org (`Makefile:325–327`), and
`check-test-fails` plants a stale README (`Makefile:348`). No check runs its nine examples;
two are illustrative only (`saved-lines` unbound at :258; `"big.bin"` at :531).

## 2. The public exports

Counted from each library's `export` form, and a comment `;; NAME : TYPE` (or
`;; A, B, C :`) anywhere in the file:

| Library | Exports | Procedures and values | With a signature | Missing one | Condition types |
|---|---|---|---|---|---|
| `(curl)`, `src/curl.sls` | 134 | 120 (4 of them reason lists) | 120 | **0** | 14 |
| `(curl unsupported)`, `src/curl/unsupported.sls` | 1 | 1 | 1 | **0** | 0 |
| `(http-client)`, `src/http-client.sls` | 59 | 53 (3 of them reason lists) | 53 | **0** | 6 |
| total | 194 | 174 | 174 | 0 | 20 |

- **Where.** In `(curl)` and `(http-client)` each signature sits inside the `export` form,
  directly above the names it types (`src/curl.sls:22–535`, `src/http-client.sls:159–573`),
  most followed by prose: keys, defaults, refusals, per-version behaviour. `(curl
  unsupported)`'s one sits after its `export` form, in the library body
  (`src/curl/unsupported.sls:32–46`).
- **Condition types** carry no type, which fits: they are not functions. 14 have a one-line
  `;; &name: ...` comment. The six classes, `&curl-timeout`, `&curl-connect-error`,
  `&curl-send-receive-error`, `&curl-tls-error`, `&curl-protocol-error` and `&curl-too-large`
  (`src/curl.sls:523–525`), share one block (:514–522) that types their predicates and lists
  each class's codes.
- **Missing ones:** none.
- **No check holds the rule.** No test or script reads the comment signatures (grep for
  `Typed Racket`, `signature comment` in `tests/`, `scripts/`, `Makefile`: no match; the
  `signature` hits in `tests/test-constants.sps:1349–1357` and `tests/test-collect-safe.sps`
  are about foreign-procedure prototypes). `tests/test-printed.sps:6–12` does hold a written-out
  row for every export, by `library-exports`, so a list of the exports is already held.
- **What the comments cite.** If an API reference were drawn from them, these would come with
  it: `src/curl.sls` cites ADRs 19 times and a date once; `src/http-client.sls` cites ADRs 32
  times, an "M5/M6 plan, section" 8 times, `research/` paths twice and dates 10 times (e.g.
  :105, `.plans/research/m7/carried/guard/`); `src/curl/unsupported.sls` cites ADRs twice and
  a plan once. chez-curl's AGENTS.md has no rule against that; chez-libuv's (AGENTS.md:13–19)
  and chez-http-server's (AGENTS.md:34–38) forbid it in shipped files.

## 3. User docs in the sibling repos

Every sibling has a thin `README.org`, a `docs/` of Markdown pages with a hand-written
`docs/reference.md`, a check that holds the reference to the real exports, a docs site built by
`build-site.sps` and `site/*.sls`, and a `.github/workflows/pages.yml` that deploys it on a `v*`
tag (cmark-gfm pages.yml:8–10; libuv :13–15; httparse :11–13; websocket :13–15; http-server
:15–17).

| Repo | README.org | docs/ | reference.md | Reference held by | Examples checked |
|---|---|---|---|---|---|
| chez-cmark-gfm | 172 lines | 9 pages, 2,816 lines | 1,000 lines, authored | `make check-reference` (Makefile:483; tests/reference-check.sps:1–8): modules and bindings against the export clauses | `make examples` (Makefile:445) diffs `examples/*.sps` against `examples/expected/`; tests/test-example-coverage.sps:1–6 requires every export of `(cmark gfm)` in an example |
| chez-libuv | 189 | 15 pages, 6,759, with `docs/README.md` and `quickstart.md` | 1,262, authored | `make check-reference` (Makefile:426): one entry per public export, in the modules that export it | not found: no `examples/`; tests cite docs pages but run no doc code |
| chez-httparse | 184 | 12 pages, 3,019 | 910, authored | test/common/reference-tests.sps:1–12: exact for its own modules, a subset for the runtime | test/common/example-tests.sps:1–7 runs README.org's example (CMake lanes, test/CMakeLists.txt:1384–1391); some docs claims tested (`te-error-nodes-tests.sps`, `stream-offset-tests.sps`) |
| chez-websocket | 136 | 8 pages, 837, with `docs/README.md` | 297, authored | tests/test-docs.sps:1–40: exports, defaults, reference entries, fenced blocks, Makefile targets, links, numbers | tests/test-examples.sps:1–3 plays each `examples/*.sps` on a fake |
| chez-http-server | 131 | 18 pages, 2,629, with `docs/README.md` and `quickstart.md` | 259, authored, types "as Typed Racket writes them" (:4–6) | tests/test-reference.sps:1–5: every export of `(http-server)` and `(http-server testing)`, and no other | tests/test-examples.sps:1–3 runs each example as a process over loopback |

- **No sibling generates its reference.** cmark-gfm's, libuv's and httparse's checks call it
  "authored" prose whose completeness is checked (cmark-gfm tests/reference-check.sps:2–3;
  httparse test/common/reference-tests.sps:3–4).
- **How each reference is organised.** A modules table, a conventions note (`->` is notation;
  `[x]` optional), then sections by topic with a `### name (kind)` entry each: its call form,
  the library that exports it, what it raises, a link to the guide page (cmark-gfm
  docs/reference.md:1–59; libuv :1–40; websocket :1–28). httparse adds an alphabetical index
  (:12–13). http-server groups several names under one heading (:35, `&http-server-error,
  http-server-error?`).
- **The README's shape.** cmark-gfm's publishing-prep design cut a 643-line README to about
  140, in eight sections: description and AI disclosure; what it is; status; install; a taste;
  documentation links; contributing; license
  (`~/src/chez-cmark-gfm/.plans/2026-08-22-publishing-prep-design.md:9–37`). Code samples
  there cite `examples/*.sps` where one exists, so `make examples` gates them (:70–73).
- **Community files.** CONTRIBUTING.md: cmark-gfm, libuv, websocket, http-server. SECURITY.md:
  the same four. NOTICE: cmark-gfm, libuv, httparse, http-server. chez-curl has none of them.

## 4. Changelogs and releases in the siblings

| Repo | CHANGELOG.md format | Tags (local) | Akku.manifest | Manifest held to the changelog |
|---|---|---|---|---|
| chez-cmark-gfm | "follows Semantic Versioning" (:3–4); `## [X.Y.Z] — date`, sections such as `### Added/Fixed/Security/Notes`; first entry `[0.1.0] — 2026-08-17` (:635) | 5: v0.1.0 `67f4cc4` … v2.0.0 `3c84828` | 2.0.0 (:18) | not found (Makefile:438 is a comment) |
| chez-libuv | semver (:3–4); `## X.Y.Z — date`, unbracketed; `### Added/Changed/Fixed/Known limitations`; first `0.1.0 — 2026-08-18` (:1277) | 15: v0.1.0 `35f290b` … v0.11.0 `afe79a5`, "chore: release 0.11.0 (#145)" | 0.11.0 (:20) | `check-pins` fails on VERSION DRIFT against the top `## X.Y.Z` (Makefile:345–355) |
| chez-httparse | Keep a Changelog 1.1.0 + semver 2.0.0 (:3–5); `## [X.Y.Z] - date` | 10: v0.1.0 `d74a43d` … v0.5.0 `52a62e5`, "the first public release, packaged for Akku" | 0.5.0 (:20) | a CMake lane: the latest release (test/CMakeLists.txt:1438) |
| chez-websocket | Keep a Changelog 1.1.0 + semver (:3–5); first `[0.1.0] - 2026-10-11` (:187), `### Added/Measured` | 7: v0.1.0 `87bc9e6` … v0.5.1 `4b70f22` | 0.5.1 (:9), development only (:4–8) | tests/test-docs.sps reads CHANGELOG.md's numbers |
| chez-http-server | Keep a Changelog 1.1.0 + semver (:3–5); first `[0.1.0] - 2026-10-04` (:672), `### Added/Measured` | 12: v0.1.0 `fa9e745` … v0.10.0 `5c16f64` | 0.10.0 (:22) | `scripts/check-akku-manifest.ss`, through `check-pins`: "the package's version is CHANGELOG.md's latest release" (.plans/decisions/0031-…:79–80) |

- **A release target or script:** none in any sibling. No `release` or `tag` target; libuv's
  and httparse's `prod` build an optimised artifact. Release-adjacent targets: `check-akku`
  (cmark-gfm Makefile:588, libuv :450, httparse, http-server), `check-archive` (libuv :395),
  `check-history` (libuv :385), and `install`/`uninstall`/`check-install` (cmark-gfm alone,
  :593, :609, :527).
- **An exported version of the package itself:** not found in any sibling. cmark-gfm's
  `cmark-gfm-version` (src/cmark/gfm.sls:100–104) and libuv's `uv-version`
  (src/libuv.sls:102–106) report the C library. chez-curl likewise reports libcurl
  (`loaded-libcurl`, `libcurl-info-version`) and has no package version.
- **Records of how they release.**
  - chez-http-server: a release's ledger moves to its own `vX.Y.Z-progress.md` (AGENTS.md:43–45).
    `.superpowers/sdd/v0.9.1-progress.md:94–125` is a whole release, in order: CHANGELOG's
    `[Unreleased]` dated, `Akku.manifest` bumped, the gate run, the squash merge, a signed
    annotated tag on the tested commit (:114), `pages.yml` redeploying (:115), a GitHub Release
    from the entry (:116), then `akku publish` from a fresh clone at the tag (:121–125).
  - chez-websocket: its ledger, `.superpowers/sdd/progress.md:2129` and :2201 (a signed tag
    `v0.1.0`, its body naming `[0.1.0]`).
  - chez-libuv: a public-release docs design (`.plans/2026-08-22-chez-libuv-public-release-docs-design.md`,
    with the version check at :189–193); a pre-release review's mutation log; AGENTS.md:23–30, a
    release ships `git archive` of its tag, `.gitattributes` export-ignoring the repository's
    own records.
  - chez-httparse: AGENTS.md:200–203 ("before a release, search for 'unreleased', 'on main',
    'not yet shipped'") and :234–238 (the `akku publish` traps).
  - chez-cmark-gfm: the publishing-prep design above, and the stage-6 packaging design.
- **chez-curl today:** `CHANGELOG.md` is 0 bytes; it has no tags; `Akku.manifest` names 0.0.0
  (:16). CI already runs every job on a `v*` tag's push (`.github/workflows/ci.yml:19–25`,
  :63–66), and says "macOS is covered by running the suites by hand before tagging" (:6–7).

## 5. Akku

**chez-curl's records.**

- ADR-0001:132–134: an install needs a threaded Chez ≥ 10.4.0 and a libcurl runtime package,
  no compiler, no headers, no generated files; "That keeps Akku possible; whether to publish
  there is not decided here."
- ADR-0015 decision 2 (:38–49): `Akku.manifest` declares chez-srfi as a development dependency
  and runs no scripts; `Akku.lock` pins it; "Publishing chez-curl on Akku is still undecided
  (ADR-0001)" (:40–41). `tests/test-manifest.sps` holds no `depends`, no `scripts`, `depends/dev`
  exactly chez-srfi (:99–110), and the lock to that version. It does not read the package's own
  version.
- ADR-0002:219–220: "An installed tree waits for packaging."
- ADR-0010:26–28 and :61–62: on 2026-10-04 no Akku package provided `(curl ...)`; the one
  earlier `(library (curl))`, iovxw/chez-curl, is not on Akku. Not rechecked (no network).
- `packaging/` holds `floors.sexp` and `debian-prereqs.txt`, neither about Akku.
  `debian-prereqs.txt:4–9` still says "NOT YET EXERCISED … M0 slice 5 adds the workflow", though
  CI has run since PR #38 (progress.md:236–241).
- `Akku.manifest:16–21`: `("chez-curl" "0.0.0")`, synopsis, authors, homepage, `BSD-3-Clause`,
  `depends/dev` chez-srfi. No `.akkuignore`, no `.gitattributes`, no `make check-akku`.

**The siblings' records on the index.**

- chez-cmark-gfm: publishing was out of scope through 2.0 ("a submission process, and it should
  follow a release that has proven itself", .plans/decisions/0017-no-akku-scripts.md:120–126;
  publishing-prep design :230). It is on the index at 2.0.0 (CHANGELOG.md:73–76;
  docs/installing.md:99). How it was submitted: not found in its records.
- chez-http-server ADR-0031: on 2026-10-23 the index listed chez-libuv 0.11.0, chez-httparse
  0.5.0, chez-uri 0.8.0 and byte-machine 0.8.0 (:13–21). Decision 7: "Publishing to the index is
  part of a release, from its tag" (:103–106). Its 0.9.1 was queued, the package page answering
  404, with 0.8.0 and 0.9.0 still queued (v0.9.1-progress.md:125).
- chez-httparse: `akku publish` signs with gpg's default key, there the personal one, so the
  release key must be named and the `.sig` checked; and it refuses a git worktree, so it runs
  from a fresh clone at the tag (.plans/lessons.md:1225–1242; AGENTS.md:234–238). Its
  docs/installing.md:94–95 still says "not on Akku's index yet", where http-server's ADR-0031
  read it on the index.
- chez-websocket: not installed through Akku; its manifest is for development (Akku.manifest:4–8).

**What a v0.1.0 there would need, by those records.** Each is a fact from a record, not a choice
made here:

1. `Akku.manifest`'s version moved from 0.0.0. Three siblings hold it to CHANGELOG.md's latest
   release by a check; chez-curl's `test-manifest.sps` does not.
2. A tag to publish from. Akku's archive serves `git archive` of the tag (libuv AGENTS.md:23–26).
   chez-curl tracks 3,018 files, 2,528 of them under `.plans/` (`git ls-files`), and has no
   `.gitattributes`, so its archive would carry them. A submodule's gitlink ships empty
   (cmark-gfm 0017:72), which is `vendor/chez-srfi` here, a development dependency.
3. What Akku installs: every library outside `tests/`, and `site/`'s unless `.akkuignore` names it
   (http-server ADR-0031, :59–61, measured). chez-curl's `src/` has 21 libraries; its test
   libraries sit in `tests/`.
4. No `scripts` clause: nothing builds (Akku.manifest:11–15).
5. `akku publish` from a fresh clone at the tag, signed with the named release key, the `.sig`
   verified after (httparse lessons.md:1225–1242).
6. The listing can lag the submission by days (http-server, above).

## 6. What a release must state

- **The license.** `LICENSE`: BSD 3-Clause, "Copyright (c) 2026, Kiyomi Computation Systems LLC"
  (:1–3). README.org:585–588 and `Akku.manifest:20` say the same. No NOTICE. Whether any file
  under `src/` transcribes third-party expression, which is what cmark-gfm's NOTICE rests on
  (publishing-prep design :149–166): not surveyed.
- **The floors** (`packaging/floors.sexp`, ADR-0016): Chez 10.4.0, libcurl 7.85.0, Node 20, held
  in README.org by `check-floors` and in the code by `test-verify` and `test-require-threaded`
  (ADR-0016:28–38). The Chez floor also needs a threaded build (require-threaded.sls:79–83). Node
  is for the tests alone (README.org:15).
- **The libcurls the suites are recorded against,** `tests/known-libcurls.sexp`, seven rows (`make test` fails on any other, ADR-0017):

  | Version | TLS | Where | Host |
  |---|---|---|---|
  | 8.20.0 | GnuTLS 3.8.13 | the Guix container (:23–29) | x86_64 Linux |
  | 8.5.0 | OpenSSL 3.0.13 | Ubuntu 24.04, CI's main and memory lanes (:31–37) | x86_64 Linux |
  | 8.5.0 | GnuTLS 3.8.3 | Ubuntu 24.04, CI's gnutls lane (:39–45) | x86_64 Linux |
  | 7.85.0 | OpenSSL 3.0.13 | the floor, built from source (:47–53) | x86_64 Linux |
  | 8.20.0 | OpenSSL 3.0.13 | built from source, the old current lane (:55–61) | x86_64 Linux |
  | 8.23.0 | OpenSSL 3.0.13 | built from source, CI's current lane (:63–69) | x86_64 Linux |
  | 8.7.1 | SecureTransport (LibreSSL 3.3.6) | Apple's, the maintainer's M1 (:71–77) | arm64 macOS (reports x86_64) |

- **Chez.** 10.4.0 in the container and in CI, built from its tarball; 10.4.1, Homebrew's, on the
  Mac (ADR-0012:176; ADR-0001:563); a `--nothreads` 10.4.0 must be refused (CI's `nothreads`
  job).
- **OSes and arches.** ADR-0004:27: "The supported platforms are Linux and macOS, on amd64 and
  arm64"; Windows is not supported (ADR-0004:21–23). Run so far: Linux amd64 and macOS arm64;
  "Linux on arm64 and macOS on amd64 have not run" (progress.md:229–230). CI is Linux only
  (ci.yml:3–7).
- **Finding libcurl** (ADR-0002, decision 2, :59–89): `CHEZ_CURL_LIBCURL`, an absolute path,
  else one candidate list per world: Guix profiles, FHS directories with a GnuTLS fallback, or
  Apple's `/usr/lib/libcurl.4.dylib`; Homebrew's curl only through the override. Ubuntu 22.04,
  Debian 11 and RHEL 9 are below the floor, and need the override (ADR-0003:119–121).
  README.org names neither the variable nor the list.
- **The install steps README.org gives:** none. No install section; Quick start is empty (:19);
  no Akku, clone or `CHEZSCHEMELIBDIRS` line; no `make install`.
- **The limits README.org already tells a caller,** by libcurl:
  - a proxy variable's control-byte userinfo goes direct on 7.85.0 and 8.5.0 (:35–39);
  - Guix's `SSL_CERT_FILE` and `SSL_CERT_DIR` (:44–50); the Mac's `CURL_SSL_BACKEND` (:59–67);
  - 8.7.0 and 8.7.1: request size `#f` (:68–70), no multiplexing (:98–100, :400–401);
  - 8.23.0's Digest user name outside ASCII (:127–129);
  - lengths (:144–147);
  - TLS inside TLS stalls on Ubuntu's 8.5.0 with GnuTLS, and on 7.85.0 (:213–218);
  - a refused `CONNECT`'s code (:219–224);
  - before 8.19.0, no shared tunnel and CVE-2026-3784 (:225–233);
  - cookies by version (:280–291); a load's n² cost (:292–294); 7.85.0's unended head (:295–300);
  - an early success that cuts the body (:445–450);
  - **the 8.5.0 bullet:** over HTTP/2 a paused upload can hide the answer (:454–458);
  - an HTTP/2 3xx that never ends on 8.20.0 and 8.23.0, and 7.85.0's early 200 (:556–561);
  - a stalled lookup during a group's escape on 7.85.0 to 7.86.x (:575–578).
- **Limits the records promise to the docs that README.org does not tell:** §7's rows marked
  "no".
- **Carried items that bear on the limits** (progress.md:69–80): no cap on response headers,
  whose walk costs n² (traps: 100,000 took 30 s of CPU on 7.85.0); 8.5.0's stall past a URL of
  about 131 KB, cause unknown; the public URL functions running with their caller's interrupts;
  the curl bug reports drafted but not filed (progress.md:70–71; the M6 plan :1122–1124).

## 7. Every promise to document

Grepped `.plans/decisions/*.md`, `.plans/2026-*-plan.md` and `.plans/global-constraints.md` for
`document` (any form), `README` and `docs`: 130 lines. Left out: lines citing curl's, Node's or
chez-libuv's own documentation (ADR-0001:70, 0002:192, 0003:17, :41, :44, 0005:228, 0008:50,
0009:36, :232, :273, 0012:21, :25, :228, 0013:49, :76, :407, 0019:58, :107, 0022:111,
0037:120, the M2 plan :85, the M4 plan :89, :564), alternatives a record rejected (0008:153, 0012:223,
:259, 0021:148, 0022:192, 0024:73, :288, 0025:122, 0030:133, :158), 0012:60 ("enforced, not
documented"), 0010:56 (renaming the repository), and the M6 plan :877 (a review's finding, since
fixed). 0030:110 restates decision 5, and the M6 plan :584–594 and the M7 plan :353 sit inside
the sections their rows cite. Added: the brief's README line (brief:56–61), and the `For M8's
documentation` lists (the M3 plan :468–474, the M4 plan :620–621, the M5 plan :753–757, the M6
plan :1118–1119).

"Kept" means README.org says it today. "Src" means only a source comment says it.

| Record | Promise | README.org today |
|---|---|---|
| brief:56–61 | N concurrent requests need one engine thread, not N caller threads: "the single most important thing to get into the README" | partly: :567–571 says a group runs many calls on one thread; nothing on the engine |
| ADR-0002:246–248; M3 plan :469 | reference `(curl)` once before starting threads that use it (`cyclic dependency`) | no |
| ADR-0003:119–121 | the supported-platforms docs say Ubuntu 22.04, Debian 11 and RHEL 9 need a newer libcurl, by `CHEZ_CURL_LIBCURL` | no |
| ADR-0008:72–74 | a caller wanting RFC 3986's strict verdict runs uriparse first; the docs list curl's leniencies | no |
| ADR-0008:89–90, :149, :181 | the leniencies listed by version, from `test-url`'s rows, non-ASCII ones among them | no (no list exists to go stale) |
| ADR-0009:17–19, :93–95 | the hatch is documented as unsupported; what it checks; that it can change tested behaviour | kept, :335–348 |
| ADR-0009:317; :318–319 | what `VERBOSE` and `NOPROGRESS` print; a path at `/dev/stdin` is the caller's | kept, :349–352 |
| ADR-0009:482–487; ADR-0036:117–121; M7 plan :203–206 | `FAILONERROR`, `AUTOREFERER`, `KEEP_SENDING_ON_ERROR`, `UNRESTRICTED_AUTH`, `DISALLOW_USERNAME_IN_URL` stay the hatch's, "documented"; `LOGIN_OPTIONS` and the rest changed nothing | no (src: transfer.sls:1739–1741) |
| ADR-0016:14–17, :28–31, :39, :52, :86; global-constraints :18–21, :25–28 | `** Requirements` holds the three floor lines | kept, :11–15, by `check-floors` |
| ADR-0016:57; harness plan :77–79 | `docs/` joins `check-floors` when it states requirements | n/a: `docs/` holds only `.gitkeep` |
| ADR-0018:101–103 | a `pkcs11:` CA path documented or refused | refused and kept, :51–53 |
| ADR-0018:185; ADR-0024:62–63; M4 plan :316; global-constraints :293–296 | `SSLKEYLOGFILE`, `OPENSSL_CONF`, then `CURL_SSL_BACKEND`, documented in README.org | kept, :54–67 |
| ADR-0024:118, :281–283, :307 | `CURL_SSL_BACKEND=secure-transport` named, as `secure-transport` | kept, :59–67 |
| ADR-0024:336–343; global-constraints :268–271 | a proxy variable's control-byte userinfo goes direct on 7.85.0 and 8.5.0 | kept, :35–39 |
| ADR-0019:108–111; M3 plan :470 | on 7.85.0 and 7.86.x a cancel or timeout during a stalled lookup holds the engine up to 10 s | partly: :575–578, for a group's escape alone |
| ADR-0019:220–226; M3 plan :471–472 | on 8.20.0 each stopped engine leaves two resolver threads for about 2 s | no |
| ADR-0020:149–152; M3 plan :473–474 | on 8.23.0, after six silent closes within a second, the next transfer fails 55 | no |
| ADR-0022:26–34, :224–226, by the M4 plan :620–621 and M5 plan :753–754 | the classes' version variance: one failure's code and class move by version | no (README.org names no class; src: curl.sls:514–525 lists the codes) |
| ADR-0025:4, :77–82; global-constraints :694–697 | a second escape as a session's close starts can leave its engine running: documented, not prevented | no (src: http-client.sls:198–212) |
| ADR-0025:115, :143–148 | the checks' hold grows with the input, at sizes the documentation names | no (src: http-client.sls:84–111) |
| ADR-0026:56–63; M5 plan :754–756 | libcurl's own resends multiply a policy's attempts: a `get` retried 3 times can reach a server 18 times | no; README.org has no retry section (src: http-client.sls:14–18) |
| M5 plan :753–757 | the redirect rules and the headers that follow | kept, :460–479 |
| M5 plan :753–757 | the retry rules | no: retries appear only beside other topics (:221–224, :514–518, :543–545) |
| M5 plan :320 | every other header follows a redirect, an `X-Api-Key` among them | kept, :468–470 |
| M5 plan :756–757 (its §2, :74–130) | what varies by version at a redirect: two `Location` headers, the first followed on 7.85.0, 8.5.0 and 8.7.1, a failure, 8, on 8.20.0 and 8.23.0 | no (src: http-client.sls:287–290) |
| M5 plan :453–457; global-constraints :758–760 | a group's join can wait on a stalled lookup, and a second Ctrl-C abandons it | kept, :575–578 |
| M5 plan :760–767 | a group call's compounded timer raise and an expiry's re-entry refusal, "both documented" | superseded: ADR-0025, amended 2026-11-05, removed both (progress.md:42–49) |
| ADR-0030:70–78; ADR-0034:58–59; M6 plan :236–237; global-constraints :854–855 | a paused HTTP/2 stream beside an active one receives into libcurl's memory, "documented, by version" | partly: :378–381 says "tens of megabytes", no per-version figure (the M6 plan's §3.7 has 66.9, 10.6, 21.1, 33.5 MB and 8.7.1's cap) |
| ADR-0031:80; M6 plan :598 | a consumer slower than the bound meets `&http-timeout`, beside the forms | kept, :382–383, :506–508 |
| ADR-0031:4, :114–119; M6 plan :929; global-constraints :850–853 | the HTTP/2 3xx that never ends: pass `timeout-ms` | kept, :556–561 |
| ADR-0032:89 | a streamed upload costs a connection of its own | kept, :425–431 |
| M6 plan :478, :481, :524–527 | a port never closed leaves its transfer paused; prefer `get-bytevector-some`; a PROC that never reads starves its upload | kept, :392–393, :384–386, :509–511, :546–550 |
| M6 plan :573–599, :976 | how to stream each way, and §3.7's documented rows | kept, :354–458, :481–563 |
| ADR-0034:93–96; M7 plan :157–159 | prior knowledge beside `proxy environment` is ignored | kept, :92–94, :206–208 |
| M7 plan :153–155 | a redirect to `https://` by prior knowledge fails the call | kept, :89–91 |
| M7 plan :163 | the hatch's `PIPEWAIT` stays allowed | kept, :100–101 |
| M7 plan :358–362 | the codes of prior knowledge against an HTTP/1.1 server, by version | partly: :90–91 says its code depends on the libcurl and on timing, no codes |
| ADR-0036:86–87; M7 plan :363–365 | the Digest algorithms each version supports, and 8.23.0's UTF-8 user name | partly: the user name, :127–129; the algorithms, no |
| ADR-0036:103; :115 | Digest sends a body twice to a server that never challenges; no length is checked | kept, :123–126, :144–147 |
| ADR-0037:90–91; M7 plan :366–370 | the refused `CONNECT`'s code, and which builds stall inside a tunnel | kept, :213–224 |
| ADR-0037:184–186; :252 | `SUPPRESS_CONNECT_HEADERS`, `PROXY_SERVICE_NAME`, `SOCKS5_AUTH` and `CONNECT_TO` stay the hatch's | kept, :237–239 |
| ADR-0035:64–65; M7 plan :371–384 | the cookie rules vary by version, and the docs say so | kept, :262–263, :280–291 |
| ADR-0035:137 | 7.85.0's hang through a long URL | kept, :295–300 |
| ADR-0035:142; M7 plan :320; global-constraints :880–883 | a load's cost; each jar procedure waits with no bound | kept, :292–294, :307–309 |
| ADR-0035:180 | `CONNECT_TO` stays the hatch's, its cookies following the URL's host | kept, :312–314 |

Count: 45 rows: kept 25 (the `pkcs11:` row refused as well), partly 5, no 13, n/a 1,
superseded 1. Five records say "M8's documentation" in so many words: ADR-0002:247,
ADR-0019:111 and :226, ADR-0020:152 and ADR-0026:63. The M3 plan's list (:468–474) carries the
first four. Of the five, four are "no" and ADR-0019:111 is "partly".

## Questions the scope must answer

1. **Where do user docs live: README.org alone, or a thin README.org beside `docs/*.md`?**
   Bears on it: AGENTS.md:47–48 (`/docs` user-facing; concise, ELI5); README.org at 588 lines
   with Status and Quick start empty and every topic under Configuration (§1); every sibling's
   README.org of 131 to 189 lines beside 8 to 18 Markdown pages (§3); cmark-gfm's cut of a
   643-line README (§3); `check-floors` holding README.org's `** Requirements` exactly, Node's
   test-only line included (tests/floors.sls:363–372), and ADR-0016:57 adding `docs/` once it
   states requirements.
2. **Is the API reference written by hand, as every sibling's is, or drawn from the export
   blocks' comments?** Bears on it: all 174 procedures and values carry a signature (§2), but
   the comments around them run to hundreds of lines and cite ADRs, plans, research paths and
   dates (§2); no sibling generates its reference; chez-http-server's reference already writes
   Typed Racket types.
3. **What checks hold the docs?** Bears on it: today only `check-floors` reads README.org, and
   no check runs its nine examples (§1); each sibling holds its reference to the real exports,
   and four run their examples (§3); `tests/test-printed.sps` already holds a row per export,
   by `library-exports` (§2); libuv's `check-history` keeps record citations out of shipped
   files.
4. **Does a docs site ship, and from what?** Bears on it: all five siblings render `docs/`
   through chez-cmark-gfm and deploy on a `v*` tag (§3); chez-curl's `test-manifest.sps:99–110`
   holds `depends/dev` to chez-srfi alone (ADR-0015), so a second development dependency
   changes that check; a push that touches `docs/` or README.org runs every CI job
   (ci.yml:63–72).
5. **Which of §7's thirteen "no" rows and five "partly" rows does M8 close, and where?** Bears on
   it: five records say "M8's documentation" in so many words; some live only in source
   comments today (§7); AGENTS.md:48's "very concise, ELI5".
6. **Do measured figures and per-version tables stay in user docs?** Bears on it: README.org's
   35 lines naming a libcurl version, its timings and lengths (§1); the records' promises,
   several "by version" (§7); AGENTS.md:48.
7. **Which install routes does v0.1.0 document and test: a clone with `CHEZSCHEMELIBDIRS`,
   `make install`, Akku?** Bears on it: README.org gives none (§6); no `install` target and no
   installed-tree check (ADR-0002:219–220); cmark-gfm's `install`, `uninstall` and
   `check-install`, and four siblings' `check-akku` (§4).
8. **Is v0.1.0 published to Akku's index, at its tag or later?** Bears on it: ADR-0001:132–134
   and ADR-0015:40–41 leave it undecided; cmark-gfm deferred it until a release had proven
   itself, http-server made it part of every release (§5); the six things a submission needed
   there (§5); the listing's lag.
9. **What does a release archive carry?** Bears on it: 2,528 of 3,018 tracked files are under
   `.plans/`; no `.gitattributes` or `.akkuignore`; libuv's `check-archive` and http-server's
   ADR-0031 decision 5 (§5); AGENTS.md, `.github` and `tests/` ship too unless excluded.
10. **What holds `Akku.manifest`'s version?** Bears on it: 0.0.0 today; three siblings fail a
    check when it differs from CHANGELOG.md's latest release (§4); chez-curl's
    `test-manifest.sps` reads every clause but the version.
11. **What form does CHANGELOG.md take, and what does `[0.1.0]` cover?** Bears on it: the file
    is 0 bytes; three siblings follow Keep a Changelog 1.1.0, two state semver alone; first
    entries summarise with Added and Measured or Known limitations (§4); AGENTS.md:46; M0 to M8
    are all unreleased.
12. **Which matrix does v0.1.0 claim?** Bears on it: ADR-0004:27 names amd64 and arm64 on both
    OSes; only Linux amd64 and macOS arm64 have run (progress.md:229–230); seven libcurl rows,
    three TLS backends (§6); ci.yml:6–7 puts the Mac's run before tagging.
13. **What does `** Status` say?** Bears on it: the heading is empty; 0.x versioning in every
    sibling; `(curl unsupported)` carries no compatibility promise (README.org:335–336;
    ADR-0009:93–95); the items still carried (progress.md:69–80).
14. **What release procedure does M8 record, and where?** Bears on it: none in chez-curl's
    records; http-server's `vX.Y.Z-progress.md` (a signed tag on the tested squash, Pages, a
    GitHub Release, `akku publish` from a fresh clone with the named key); httparse's
    "version surface" search (§4); CI already runs on `v*` tags (ci.yml:19–25); the closing
    ritual's squash merge (AGENTS.md:603–609).
15. **Which community files ship with v0.1.0?** Bears on it: chez-curl has no CONTRIBUTING.md,
    SECURITY.md, NOTICE or issue templates; four siblings have the first two, four a NOTICE
    (§3); NOTICE's grounds in cmark-gfm were transcribed third-party code, which this survey
    did not look for in chez-curl's `src/` (§6).
16. **Does chez-curl export a version of its own?** Bears on it: no sibling does; each reports
    the C library it binds, as `loaded-libcurl` does (§4).
17. **Do the stale lines found here change before the tag?** Bears on it:
    `packaging/debian-prereqs.txt:4–9` ("NOT YET EXERCISED"), and the source comments' record
    citations (§2), if the reference is drawn from them; httparse's rule to search for
    "unreleased", "not yet" and the like before a release (AGENTS.md:200–203).
