# ADR-0042: A docs site on GitHub Pages, a GitHub Release for each tag, and archives without the records

- **Status:** Accepted
- **Date:** 2026-11-14
- **Scope:** what chez-curl publishes beyond a tag: a docs site, GitHub Releases, and what a
  release archive leaves out. It amends [ADR-0038](0038-m8s-scope.md)'s amendment of
  2026-11-10, decision 4, which made a release the tag alone and left each of these a later
  decision of its own.
- **Settles:** where the docs are served, what renders and checks them, how chez-cmark-gfm
  arrives, when the site first deploys, which tags get a Release and how, and what GitHub's
  source archives carry. Akku stays out. The maintainer chose on 2026-11-14, the recommended
  option each time: Releases for `v0.1.0` and `v0.1.1` now; the first deploy from v0.1.2;
  archives without `.plans/` and `AGENTS.md`; chez-cmark-gfm from the locked archive.
- **Related:**
  - [ADR-0038](0038-m8s-scope.md), amended 2026-11-10: no GitHub Release and no Akku, as "a
    publish cannot be taken back"; a docs site not in M8;
  - [ADR-0015](0015-test-harness-and-scheme-dependencies.md): chez-srfi, a `depends/dev`
    pinned in `Akku.lock`;
  - [ADR-0041](0041-a-json-example-takes-jsonparse.md): a dependency one part of the tree
    uses alone;
  - [ADR-0006](0006-pinned-guix-container.md): the container has no network;
  - circuit: its site (PR #17, 2026-10-30), its anchors by GitHub's rule (PR #32), and its
    v0.3.0 release (PR #47), the newest of the family's.

## Context

Read on 2026-11-14, on `main` at `79c6ced` (`v0.1.1`):

- **chez-curl publishes tags alone:** `v0.1.0` on `ecfdbf1` and `v0.1.1` on `79c6ced`, each
  signed and annotated. `gh release list` answers none, the Pages API answers 404, `ci.yml` is
  the only workflow, and no target renders `docs/`.
- **`docs/` is 16 Markdown pages.** Its index, `docs/README.md`, lists the other 15 in
  reading order under "The pages". They link to repository files by `../`: README.org 3
  times, examples 13 times, two of those to a directory (`../examples`,
  `../examples/expected`). `test-docs` holds their links and anchors, the anchors by
  GitHub's rule.
- **Six siblings serve a site:** chez-http-server, chez-libuv, chez-cmark-gfm,
  chez-websocket, chez-httparse and circuit. Each Pages site builds from a workflow. Read
  for circuit, the server and chez-websocket: their `github-pages` environment takes the
  branch `main` and the tags `v*`, and nothing else.
- **circuit's is the newest:**
  - `build-site.sps` and `site/`, eight libraries and a stylesheet, render `docs/*.md` into
    `build/site/` through chez-cmark-gfm. `site/pages.sls` is the nav's order and labels.
  - `make site-deps` gets chez-cmark-gfm as `Akku.lock` pins it, a `depends/dev`:
    `scripts/fetch-akku-lock` downloads the locked archive on the host and checks its sha256.
  - `make site` renders the site. `make check-site` runs the generator's two suites, then
    `site-check` on the real docs: the nav names exactly `docs/*.md`; no anchor dangles; no
    `.md` link leaks; no `<pre>` is reflowed; every relative link names a page written; and
    every `../` link names a file the checkout has.
  - A `site` job in `ci.yml` builds the site on apt's Chez, 9.5.8, on every PR: 29 s on PR
    #17. `pages.yml` deploys on a `v*` tag or by hand, its actions pinned by SHA, with
    `SITE_REF` the ref, so links to repository files name `blob/<tag>/`. v0.3.0's build took
    30 s and its deploy 10 s.
  - Its anchors are GitHub's since PR #32, from chez-http-server's fix. chez-websocket's
    copy keeps the older rule.
- **circuit's container** gained cmark-gfm, tar and xz. Its `guix-env-enter` exports
  `CHEZ_CMARK_GFM_LIBS`, naming the profile's two libraries by absolute path: chez-cmark-gfm
  otherwise searches `/usr/lib` and the like, which only `--emulate-fhs` gives. chez-curl's
  `scripts/guix-env` passes no `--emulate-fhs` either.
- **circuit's Release for each tag:**
  - its title is the tag message's subject;
  - it is made from the tag with `--verify-tag`, and is no draft or prerelease;
  - its notes are the CHANGELOG entry as the tag holds it, intro to last bullet, and the
    published body is read back and compared byte for byte.
  - The site, deployed by the tag's push, is then checked live: each page answers 200, its
    links name `blob/<tag>/`, and none names `blob/main/`.
  - `.gitattributes` export-ignores `/.plans` and `/AGENTS.md`, checked by listing the tag's
    source tarball.
- **A workflow run by hand takes the workflow file at the ref it runs on,** and `v0.1.0` and
  `v0.1.1` hold no `pages.yml`. That is GitHub's documented rule, not measured here.
- **chez-cmark-gfm's newest tag is v2.0.0.** circuit's `Akku.lock` entry for it gives the
  archive URL and sha256, and was copied whole from chez-websocket's, which `akku lock`
  wrote. `akku` isn't installed here.

## Decision

1. **A docs site renders `docs/` to GitHub Pages,** at
   `https://kiyomi-computation-systems.github.io/chez-curl/`.
   - It copies circuit's `build-site.sps`, `site/` and suites, changing three things: the
     links to repository files name chez-curl's blob; the names; and the nav, which is
     `docs/README.md` as the home page, then "The pages" in order.
   - Every page in `docs/` is rendered. README.org is not: links to it name its blob.
   - README.org names the site.
2. **chez-cmark-gfm arrives as circuit's does:**
   - a `depends/dev` at `^2.0.0` in `Akku.manifest`;
   - its `Akku.lock` entry copied from circuit's;
   - `make site-deps` downloads the locked archive once on the host and checks its sha256,
     through `scripts/fetch-akku-lock` and its offline test.

   Nothing under `src/`, `examples/` or `tests/test-*.sps` imports it, so `make test` needs
   none of it. The system cmark-gfm library is needed for the site alone. AGENTS.md's
   Dependencies names both, as the site's.
3. **The container renders and checks the site:**
   - `manifest.scm` gains cmark-gfm and whatever `fetch-akku-lock`'s check needs;
   - `guix-env-enter` exports `CHEZ_CMARK_GFM_LIBS` by absolute path;
   - `make check-guix` holds both loads, as circuit's does.
4. **The targets are `site-deps`, `site`, `check-site` and `check-site-deps`,** in `make help`.
   The generator and its suites import nothing under `src/`, so they run on apt's Chez,
   below chez-curl's floor. Like `tests/test-*.sps`, the suites are held by a check to an
   exit that counts their failures.
5. **CI:**
   - a `site` job in `ci.yml` builds and checks the site on apt's Chez, on each PR the filter
     runs: a tenth job;
   - `pages.yml`, as circuit's, deploys on a `v*` tag or by hand, its actions pinned by SHA
     and `SITE_REF` the ref.
6. **Pages is on, built from GitHub Actions,** and its `github-pages` environment takes `main`
   and `v*` tags, as the siblings' do. It is set before the first tag that deploys, by the
   maintainer, or by me on their ask.
7. **The site first deploys from v0.1.2, a docs release,** as circuit's first deployed from its
   v0.1.1. The site's PR merges first, then v0.1.2's release PR, and the tag's push deploys.
   The live site is then checked: each page answers 200, every link to a repository file
   names `blob/v0.1.2/`, and none names `blob/main/`.
8. **Every tag gets a GitHub Release, by circuit's recipe:**
   - its title is the tag message's subject;
   - it is made from the tag with `--verify-tag`, and is no draft or prerelease;
   - its notes are the CHANGELOG entry as the tag holds it (`git show vX:CHANGELOG.md`),
     intro to last bullet;
   - the published body is read back from the API and compared byte for byte.

   `v0.1.0`'s and `v0.1.1`'s Releases are made once this record is accepted, oldest first:
   `v0.1.0` with `--latest=false`, then `v0.1.1` with `--latest`. Each later one takes
   `--latest`. Each is made on the maintainer's ask, as a tag is.

   Each is made first as a draft, its stored body checked, then published. The first two,
   made 2026-11-14, showed two things
   ([research/adr-0042/releases/](../research/adr-0042/releases/)):
   - GitHub renders a relative link in a Release body as `blob/<tag>/<path>`, so an entry's
     `docs/` links name the tag's own files and need no rewrite. A draft's links name
     `untagged-…` until it is published.
   - Each newline renders as a line break, as circuit's pages show. The entries are kept as
     wrapped.
9. **Release archives leave out `.plans/` and `AGENTS.md`,** through `.gitattributes`
   `export-ignore` as circuit's does, from v0.1.2 on. Each tag's source tarball is listed to
   check it. `v0.1.0`'s and `v0.1.1`'s archives keep both, since their trees cannot change.
10. **Akku stays out,** a later decision of its own: ADR-0038's reason stands. `.akkuignore`
   waits with it.

## Rejected

- **A first deploy from `main`, by hand:** the site would come before any release that holds
  it, and its links would name `blob/main/`, which moves. `pages.yml` can still run by hand
  later.
- **The site deployed at `v0.1.1`:** a run by hand takes `v0.1.1`'s workflow files, and it has
  no `pages.yml`. A published signed tag is never moved.
- **chez-cmark-gfm as a submodule, as jsonparse is (ADR-0041):** jsonparse is on no archive,
  but chez-cmark-gfm is. Every sibling's site takes the locked archive, and circuit's targets
  and suites expect it.
- **GitHub's own build from a branch:** nothing of chez-curl's would check what it renders,
  and the family serves no site that way.
- **Releases from v0.1.2 on, alone:** the Releases page would leave out two tags that are
  already public.

## Consequences

- **A PR that runs CI runs ten jobs.** The site's took about 30 s on circuit.
- **Two copies of GitHub's anchor rule,** `test-docs`'s and `site/slug.sls`, both kept.
  Measured on 2026-11-14 ([research/adr-0042/anchors/](../research/adr-0042/anchors/)):
  - Each gives GitHub's anchor for every one of the 175 headings in `docs/` at `v0.1.1`.
    The measurement used `test-docs`'s own definitions, read from the file.
  - They differ only on characters `docs/` doesn't use. `test-docs` keeps Unicode's `No`
    and `Nl` numbers, but GitHub drops `①`, an `No`.
  - A heading on which they disagree fails one check or the other, and never passes both.
- **Two links name a directory.** `tests/check-site.sps`'s `file-exists?` passes a
  directory, and the rewrite makes `blob/<ref>/examples`. GitHub answers that with a 301 to
  `tree/<ref>/examples`, and then 200
  ([research/adr-0042/site/](../research/adr-0042/site/)), so the links are kept as written.
- **A release archive is not a test tree.** From a clone, the tests run as before. An
  archive holds no submodule's files, which GitHub's never does, so `make deps` refuses
  one. From v0.1.2 on, an archive also holds no `.plans/`, which `test-collect-safe` reads
  for its citations and `check-variadic` copies. README.org's install steps clone the tag.
- **The release steps gain four:** read the Pages run; check the site live; make the Release
  and read it back; list the tarball.
- **`Akku.lock` gains an entry copied by hand** while `akku` isn't installed. `check-pins`
  reads chez-srfi's line alone.
- **ADR-0038** gains an amendment pointing here.
- **The work is two PRs.** The site's PR: the generator, container, targets, CI, `pages.yml`
  and `.gitattributes`. Then v0.1.2's release PR. Pages is turned on, and the Releases made,
  between them, each on the maintainer's ask.
