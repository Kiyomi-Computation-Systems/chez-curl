# ADR-0007: One repository, two libraries, and a seam a check enforces

- **Status:** Accepted; amended 2026-10-16 with the routes round the seam that slice 3
  closed ([amendment](#amendment-2026-10-16-the-routes-round-the-seam)), and with slice 4's
  one-library names ([amendment](#amendment-2026-10-16-some-names-are-for-one-library-only-m0-slice-4))
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

## Amendment, 2026-10-16: the routes round the seam

M0 slice 3 built `tests/check-seam.sps`. Its review found that decision 2's two rules,
applied to the `import` form alone, could be bypassed ([mutation log](../loading-mutation-log.md),
parts 2, 5 and 6). The check now also fails, naming the file:

- **A library in neither family.** A library's family is its name's first identifier,
  `curl` or `http-client`. Without this rule, `(curl x)` could import `(util)`, which
  imports `(http-client)`.
- **An import that is not on an allowlist.** A library under `src/` may import only:
  - the `(rnrs …)` libraries other than `(rnrs eval)`, listed as `rnrs-libraries`;
  - `(only (chezscheme) name …)`, every name drawn from `allowed-chez-names`;
  - `(curl …)` and `(http-client …)` libraries, under rules (a) and (b).

  `(scheme)`, `(chezscheme csv7)` and third-party libraries all fail. A first fix denied
  named routes such as `import`, `eval` and `compile`. A second review then reached
  `(http-client …)` through `import-only`, `top-level-value` and `$primitive`, which no
  denylist named. So `allowed-chez-names` holds exactly the names `src/` imports, and its
  suite holds it equal to them. Adding a name is a reviewed change, as adding to
  `public-curl` is.
- **A file Chez could load as a library that the check does not read.** That covers every
  ending in `(library-extensions)` other than `.sls`, and compiled `.so` files: a lone
  `.so` loads as the library.
- **Fail-closed cases:** no library under `src/`, a file that cannot be read as data, a
  datum that is not a library form, and a malformed import.

Emacs lock files are skipped: a dangling symbolic link whose name starts with `.#`. Any
other file of that name is read, since a regular `.#g.sls` loads as a library.

The lists are `public-curl`, `allowed-chez-names` and `rnrs-libraries`, in
`tests/check-seam.sps`. `tests/test-check-seam.sps` runs the check on a fixture tree
for every rule and asserts each whole output. `make check-test-fails` plants a bad import,
and `make test` must fail on it.

The `require-threaded` order rule (ADR-0001) bent to fit the seam. A `(curl …)` library
imports `(curl private require-threaded)` first. An `(http-client …)` library imports
`(curl)` first instead, since it may not import a private library, and `(curl)` imports
the refusal first.

Endings are matched case-sensitively, which a case-insensitive macOS file system may not
honour.

## Amendment, 2026-10-16: some names are for one library only (M0 slice 4)

- **Rule (f): a name in `library-only-chez-names` may be imported from `(chezscheme)` only
  by the libraries listed with it.** At first that is `define-ftype`, for
  `(curl private layouts)` alone. Any other library that imports it is named.
- **Why:** a function ftype binds a C entry point, or makes a callable, without
  `foreign-procedure` or `foreign-callable`. Slice 4's review bound `curl_easy_perform`
  this way in `native.sls`, past the conventions table (ADR-0013) and the load's
  `foreign-entry?` check, with every check green. `define-ftype` is the only way to a
  function ftype: an anonymous `(function ...)` in `make-ftype-pointer` or `ftype-ref` is
  invalid syntax, so those two stay open to every library.
- **Rule (f) alone was not enough.** The review of the fix reached `define-ftype` from
  another library three ways, with `make test` green:
  - layouts re-exported it;
  - a macro in layouts took it as an argument, so no form was headed by the name;
  - layouts exported a macro that expands to it.

  Two more checks close those routes.
- **Rule (g): no library exports a name it imports from `(chezscheme)`,** either plainly or
  as the internal name of a `rename` spec. Rule (c) already refuses any wrapper around
  `(only (chezscheme) ...)`, so the local names are the listed ones. An export spec the
  check cannot read fails.
- **`test-constants` holds `(curl private layouts)` to an exact shape:**
  - the file is that one library;
  - its imports are exactly the refusal, `(rnrs)` and `(only (chezscheme) define-ftype)`;
  - its body is `(define-ftype NAME (struct ...))` forms alone, with no macro, `begin` or
    other form;
  - it exports exactly those names;
  - the symbol `define-ftype` appears nowhere else in the file, quoted or not.

  It also reads this check's list as data, and requires the `define-ftype` entry to be
  exactly `(curl private layouts)`. So widening rule (f) to another library fails until
  that library is shape-checked too.
- **Rule (g) sees bindings, not values or macros.** A library could still hand out a Chez
  procedure through `(define dl load-shared-object)`, or a keyword through an exported
  macro. For `define-ftype` that route is shut, since layouts may hold no code. A future
  library-only name needs the same pattern: its libraries held to a shape by a suite that
  reads their rule (f) entry.
- **The lists are exact, like the others.** `tests/test-check-seam.sps` requires each name in
  `library-only-chez-names` to be in `allowed-chez-names`, and each entry's libraries to be
  exactly the libraries under `src/` that import the name. Adding a name or a library is a
  reviewed change.
- **The rule keys on a library's name, not its file.** A second library form named
  `(curl private layouts)`, in another file, would pass `check-seam`. Only the exactness
  test notices it, because it counts the importers.
