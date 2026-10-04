# ADR-0004: Windows is not supported

- **Status:** Accepted
- **Date:** 2026-10-04
- **Scope:** chez-curl, until a later decision record reverses this one
- **Settles:** D9.
- **Supersedes:** the word "windows" in AGENTS.md's portability bullet, for this project.
- **Related:** chez-cmark-gfm ADR-0004 and chez-libuv ADR-0004, which deferred Windows but
  kept their designs open to it · [ADR-0002](0002-runtime-libcurl-discovery.md)

## Context

AGENTS.md asks for portability across macOS, Linux and Windows. Its own closing bullet, and
the brief, name only darwin and Linux. Both sibling projects met the same conflict and
deferred Windows, while keeping their designs ready for it. chez-cmark-gfm put
"library-name and path resolution … behind a single abstraction, so Windows is additive
later". chez-libuv deferred it "design-clean".

## Decision

**Windows is deferred outright.** chez-curl does not support Windows or test it. Nor does
it spend design effort keeping Windows possible: no Windows code paths, no Windows CI, and
no abstraction that exists only so Windows could be added later.

## Consequences

- **The supported platforms are Linux and macOS, on amd64 and arm64.**
- **Windows falls under ADR-0002's "any other platform".** There, only the override works.
  Nothing promises that a libcurl named that way on Windows works, and nothing tests it.
- **Assumptions that only hold off Windows need no flag.** Examples are POSIX paths,
  `/proc/self/maps` (ADR-0002), and libcurl's `curl_socket_t` being an `int`.
- **Reversing this takes its own decision record, and real work,** because nothing has been
  kept ready for Windows.
