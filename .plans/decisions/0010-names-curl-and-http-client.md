# ADR-0010: The repository stays chez-curl; the libraries are (curl) and (http-client)

- **Status:** Accepted
- **Date:** 2026-10-04
- **Scope:** chez-curl
- **Settles:** D4 (brief §10)
- **Supersedes:** the brief's `(http client ...)` (§1, §6, §10).
- **Related:** [ADR-0007](0007-one-repo-checked-seam.md) (the seam check, which names these
  libraries) · [ADR-0009](0009-typed-escape-hatch.md) (the escape hatch)

## Context

The brief proposed the repository name `chez-curl` and the libraries `(curl ...)` and
`(http client ...)`. Its alternatives were `chez-http-client` and `chez-http-easy`.

Each sibling's root library is one hyphenated segment, named after its project:

| Project | Root library |
|---|---|
| chez-http-server | `(http-server ...)` |
| chez-httparse | `(httparse ...)` |
| chez-libuv | `(libuv ...)` |
| uriparse | `(uri ...)` |
| chez-cmark-gfm | `(cmark gfm ...)` |

On 2026-10-04 no Akku package provided `(curl ...)` or `(http ...)`. The nearest were
http-pixiu (a server), `(retropikzel requests)` and ocelotl. One earlier `(library (curl))`
exists: `iovxw/chez-curl`, a single file pushed once in 2016 and not on Akku.

## Decision

**The repository stays `chez-curl`.** The family names bindings after the library they
bind, as chez-libuv and chez-cmark-gfm do.

The libraries:

| Library | File | Role |
|---|---|---|
| `(curl)` | `src/curl.sls` | the low level's public library: the only entry on ADR-0007's public list |
| `(curl private ...)` | `src/curl/private/*.sls` | the low level's internals |
| `(curl unsupported)` | `src/curl/unsupported.sls` | the escape hatch (ADR-0009) |
| `(http-client)` | `src/http-client.sls` | the high level's public library |
| `(http-client private ...)` | `src/http-client/private/*.sls` | the high level's internals |

ADR-0007's seam check, in these names:

- A `(curl ...)` library may not import any `(http-client ...)` library.
- An `(http-client ...)` library may import `(curl)` and nothing else from the low level.
  `(curl private ...)` and `(curl unsupported)` are out of reach.

### Rejected

- **`(http client ...)`, the brief's.** It would be the one sibling root that is not a
  single segment, and it claims all of `(http ...)`, a namespace the family does not own.
- **Renaming the repository `chez-http-client`.** The low level is a binding, and the family
  names bindings after what they bind. Renaming the existing GitHub repository, README and
  CI badge would be work for no gain.

## Consequences

- **`(curl)` collides with `iovxw/chez-curl` on one shared library path.** That is accepted,
  because that project is a 2016 single file and not on Akku.
- **Every import of the escape hatch says `unsupported`.**
- **`(http-client)` reads as the pair of chez-http-server's `(http-server ...)`.**
- **ADR-0007 and ADR-0009 use these names.**
