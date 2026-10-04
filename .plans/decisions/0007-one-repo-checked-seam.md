# ADR-0007: One repository, two libraries, and a seam a check enforces

- **Status:** Accepted
- **Date:** 2026-10-04
- **Scope:** chez-curl v1 layout
- **Settles:** D1 (brief §10)
- **Related:** brief §1 and §6 (the two layers) · [ADR-0001](0001-bind-libcurl-directly.md)
  (nothing compiled) · D3, the escape hatch, which this seam fences off

## Context

The brief draws two layers:

- **`(curl ...)`:** bindings, the engine, request records and completions. It holds no
  policy.
- **`(http-client ...)`:** sessions, the verbs, redirect and retry policy, auth, cookies and
  the thread sugar.

The house style is one repository per thesis, which argues for two repositories. The brief
recommended one repository, two libraries and a hard seam, splitting only if the low level
acquired a consumer of its own.

Since the brief, ADR-0001 has removed every compiled artefact, so both layers are pure
Scheme. A later split is a file move, not a build system's worth of work.

A seam stated only in prose breaks at the first convenient import. The house rule is to
prefer a check to a comment.

## Decision

1. **One repository holds both library families.** chez-curl holds `(curl ...)` and
   `(http-client ...)`, named in [ADR-0010](0010-names-curl-and-http-client.md).
2. **The import graph is the seam, and `make check-seam` enforces it.** The check reads the
   `import` form of every library under `src/` with Chez's reader, without evaluating
   anything. It fails, naming the file and the import, when:
   - a `(curl ...)` library imports anything under `(http-client ...)`;
   - an `(http-client ...)` library imports a `(curl ...)` library that is not on the
     check's list of public libraries. At first that list is just `(curl)`. That keeps
     `(curl private ...)` and `(curl unsupported)`, the escape hatch (ADR-0009), out of the
     high level's reach.

   Tests are exempt: a suite may import private libraries to test them.
3. **`make test` runs `check-seam`,** so CI does too. Like every check here, it counts only
   after it has been watched failing. Put a forbidden import in a scratch copy, and the
   check names it.
4. **The split has one trigger: the low level gets a consumer that does not want the high
   level.** `(curl ...)` then moves to its own repository, and the check's rules become
   that repository's boundary. Until then the two libraries share one version and one
   changelog.

### Rejected

- **Two repositories now.** Every change across the seam during v1, while the seam is
  still moving, would need coordinated releases of both.
- **One library with no seam.** Policy would leak into the binding, and a later split would
  be a rewrite rather than a file move.

## Consequences

- **A change across the seam lands in one pull request and one release.**
- **The low level's first consumer lives next door.** The check holds that consumer to the
  public surface, which is exactly what a second consumer would get.
- **Growing the public `(curl ...)` surface is deliberate.** Adding a library to the check's
  list is a reviewed change, not a side effect of an import.
