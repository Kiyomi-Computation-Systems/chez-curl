A documentation release: the libraries are 0.1.1's, unchanged. The docs are a
site now, at <https://kiyomi-computation-systems.github.io/chez-curl/>.

### Added

- **A docs site.** `docs/` is rendered into a site, served on GitHub Pages from
  each release's tag, its links to the repository's files pinned to that tag.
  `make site` builds it into `build/site/`, and `make check-site` checks its
  nav, links and anchors. Building it needs chez-cmark-gfm, which
  `make site-deps` fetches, and the system cmark-gfm library: a program using
  chez-curl needs neither.
- **GitHub Releases.** Each tag has one, from `v0.1.0` on, its notes the tag's
  entry here.

### Changed

- **Release archives** leave out `.plans/` and `AGENTS.md`.
- **README.org** links the site.
