# ADR-0002: Find libcurl at runtime: an override, else one candidate list per world, loaded once by absolute path

- **Status:** Accepted
- **Date:** 2026-10-04
- **Scope:** chez-curl v1. Linux distributions, Guix environments and macOS.
- **Settles:** D7. That decision was raised on 2026-10-04, after the brief was written.
- **Related:** [ADR-0001](0001-bind-libcurl-directly.md), which leaves no build step to
  record where libcurl is · chez-cmark-gfm ADR-0016, the house's earlier runtime discovery ·
  brief §7 (the drift guard) and §9 risks 3 and 5

## Context

ADR-0001 compiles nothing, so libcurl must be found when `(curl ...)` is imported. The
facts below were measured on this repository's development host: Pop!_OS 22.04 with a Guix
home profile, Chez 10.4.0 from Guix, 2026-10-04.

- **A bare soname finds nothing under Guix Chez.** `(load-shared-object "libcurl.so.4")`
  fails with "cannot open shared object file", though the host's `/etc/ld.so.cache` lists
  `/lib/x86_64-linux-gnu/libcurl.so.4`. Guix's loader does not consult the host's
  directories.
- **The host's libcurl cannot load into Guix Chez even by absolute path.** Loading
  `/lib/x86_64-linux-gnu/libcurl.so.4` fails with "libnghttp2.so.14: cannot open shared
  object file". Its dependencies live in the host's world, not Guix's. It is also curl
  7.81.0, below the floor.
- **The Guix libcurl is one symlink away.**
  `~/.guix-home/profile/lib/libcurl.so.4` resolves to
  `/gnu/store/…-curl-8.20.0/lib/libcurl.so.4.8.0`. `GUIX_PROFILE` points at that profile.
  `GUIX_ENVIRONMENT` is set only inside `guix shell`.
- **Chez can tell which world it runs in, in plain Scheme.** `/proc/self/maps` lists libc
  as `/gnu/store/…-glibc-2.41/lib/libc.so.6`. No FFI is needed.
- **Filenames do not carry curl's version.** The `4.8.0` in `libcurl.so.4.8.0` is a
  libtool version; that file is curl 8.20.0. Unlike cmark-gfm (ADR-0016 clause 2), the
  version is only knowable after loading. The soname `libcurl.so.4` ships in the runtime
  package, so matching it needs no `-dev` package.
- **Debian-family systems ship a second build.** It is `libcurl-gnutls.so.4`, from the
  `libcurl3-gnutls` package (installed on this host, beside `libcurl4`).
- **Homebrew's curl is keg-only.** The formula API reports 8.22.0, OpenSSL 3, `keg_only`
  `:provided_by_macos`. It is never linked into `/opt/homebrew/lib`, so chez-cmark-gfm's
  macOS directory list would not see it.
- **Apple ships a public libcurl at `/usr/lib/libcurl.4.dylib`.** Its headers are in the
  SDK. It was 8.7.1 on the maintainer's Mac per the brief. Like every system dylib since
  macOS 11, it lives in the dyld shared cache with no file on disk. chez-cmark-gfm's
  ADR-0016 measured the same property for `/usr/lib/libcmark-gfm.dylib`.
- **Chez binds a name to the most recently loaded object.** Two `-nostdlib` objects both
  exported `curl_probe_id`. A `foreign-procedure` evaluated before the second load called
  the first; one evaluated after it called the second.

## Decision

**1. The override.** If `CHEZ_CURL_LIBCURL` is set, it must be an absolute path, and it is
loaded as given. There is no search and no fallback, whatever happens to it.

- A relative path or bare name is refused (`invalid-override`), because handing it to the
  loader would search.
- Existence is decided by loading, not `stat`, so Apple's dyld-cache library can be named.

**2. Otherwise, one candidate list, chosen by world.** A pure function computes it from
the machine type, the environment variables and an existence predicate. The first
candidate that exists is chosen.

- **Guix world (Linux only).** The world is Guix when `/proc/self/maps` shows libc mapped
  from under `/gnu/store/`. If `/proc` cannot be read, the world is FHS. The candidate is
  `lib/libcurl.so.4` under each of these, in order:
  1. `$GUIX_ENVIRONMENT` (an active `guix shell`)
  2. `$GUIX_PROFILE`
  3. `$HOME/.guix-home/profile`
  4. `$HOME/.guix-profile`
  5. `/run/current-system/profile` (Guix System)

  A variable that is unset or not absolute contributes nothing. Standard Linux
  directories are never candidates here.
- **FHS Linux.** The triple comes from the machine type: `ta6le` → `x86_64-linux-gnu`,
  `tarm64le` → `aarch64-linux-gnu`. An unknown machine type has no triple directory. The
  candidates are `libcurl.so.4` in each of these, in order:
  1. `/usr/local/lib`
  2. `/usr/lib/<triple>`
  3. `/usr/lib64`
  4. `/usr/lib`

  The last candidate is `/usr/lib/<triple>/libcurl-gnutls.so.4`, so a Debian-family
  machine with only the GnuTLS build still works. Guix profiles are never candidates here.
- **macOS.** The only candidate is `/usr/lib/libcurl.4.dylib`, Apple's. Existence is
  decided by loading. Homebrew's or MacPorts' curl is used through the override:
  `CHEZ_CURL_LIBCURL="$(brew --prefix curl)/lib/libcurl.4.dylib"`.
- **Any other platform** has no list, so only the override works.

**3. One load, then verify, never fall through.** The chosen path is loaded once.
ADR-0001's ordering applies: `curl_version_info` is bound and checked first, then every
other entry point is bound eagerly in the same library body. Nothing binds lazily, because
of the most-recently-loaded rule above.

- A failed load is `load-failed`.
- A library below the floor is `below-floor`. The floor is 7.85.0
  ([ADR-0003](0003-libcurl-floor-7-85.md)).
- A library without `CURL_VERSION_SSL` is `no-ssl`.
- None of these tries the next candidate. A failed or unsuitable library is information
  the user needs, and masking it would make behaviour machine-dependent. A library that
  loaded and was rejected also cannot be unloaded. A second load would leave two
  libcurls, with bindings that point at whichever was loaded most recently when each was
  evaluated.

**4. Every outcome names its paths.** The loaded library is reported with its path, its
source (override, a Guix location, a system directory) and the version, features and TLS
backend it reports. `not-found` carries every candidate it checked; chez-cmark-gfm's
ADR-0016 recorded the lack of that as a gap.

### Rejected

- **A bare soname through the platform loader** (`libcurl.so.4`, `libcurl.4.dylib`). It
  would keep Guix and FHS worlds apart for free and need no directory table. But:
  - it finds nothing under Guix (measured), so the Guix list is needed anyway;
  - it cannot say which file loaded without more FFI (`dladdr`);
  - its choice cannot be unit-tested;
  - it lets `LD_LIBRARY_PATH` and `DYLD_*` decide silently.

  The house rule from chez-cmark-gfm is absolute paths, never leafnames.
- **One merged list for both Linux worlds**, in either order. Standard directories first
  makes this host pick a library that cannot load; it is also below the floor. Guix first
  makes a host-built Chez load a Guix library built against a newer glibc than the one in
  its process. Which world the process is in is a fact; it is read, not guessed from order.
- **chez-cmark-gfm's macOS directories** (`/opt/homebrew/lib`, `/usr/local/lib`,
  `/opt/local/lib`). They cannot see a keg-only curl.
- **Homebrew or MacPorts before Apple's.** It gets a newer curl when one is installed,
  but which libcurl loads would then depend on what else is installed on that Mac. Apple's
  is always present, behaves the same across Macs on a given OS, and trusts the keychain.
- **Selecting by version from the filename.** libcurl's filenames carry no curl version.
- **Probing several candidates and keeping the first that verifies.** See decision 3.

## Consequences

- **Nothing reads `LD_LIBRARY_PATH` or `DYLD_*` on chez-curl's behalf.** Anyone pointing at
  a non-standard libcurl uses `CHEZ_CURL_LIBCURL`. That covers Nix, `/opt` prefixes and
  hand builds.
- **Development never depends on the search.** The development container exports
  `CHEZ_CURL_LIBCURL` ([ADR-0006](0006-pinned-guix-container.md)). Two kinds of test cover
  the search instead:
  - **The pure function, with synthetic inputs.** Each rule gets a test that fails by
    name when the rule is relaxed. These include:
    - a Guix world never yields a standard directory, even when one "exists" in the
      synthetic listing;
    - an FHS world never yields a Guix profile;
    - the precedence order holds;
    - the GnuTLS build is chosen only when no `libcurl.so.4` exists;
    - the triple table maps `ta6le` and `tarm64le`;
    - a relative override is refused;
    - `not-found` lists what it checked.
  - **An install check with the override unset.** It proves an installed tree loads
    libcurl by discovery alone.
- **Linux CI runs in the FHS world.** CI builds its Chez from the release tarball
  (ADR-0001), so discovery finds the runner's packaged `libcurl.so.4`. A second lane can
  set the override to `libcurl-gnutls.so.4` to give brief §9 risk 3 its second TLS backend
  without leaving Linux. On the Mac, the override reaches Homebrew's OpenSSL-backed curl
  beside Apple's.
- **Ubuntu 22.04 finds its libcurl and then refuses it.** It ships curl 7.81.0, so the
  result is `below-floor`, naming the path, the version and the override as the remedy.
- **A Guix shell without curl falls through to the user's profiles**, whose curl may come
  from another Guix revision. If that curl needs a newer glibc than the shell's Chez, the
  result is `load-failed` with the loader's message. The remedy is adding `curl` to the
  shell.
- **The drift guard (brief §7) asserts against what this reports**: path, version, feature
  bits and TLS backend. An OS update that swaps Apple's libcurl then fails a test, not a
  user.
- **The reason symbols are the contract.** They are `invalid-override`, `not-found`,
  `load-failed`, `below-floor`, `no-ssl` and `missing-api` (ADR-0003). Tests and CI assert the reason, not the
  remedy text, which a catch-all clause can print for any failure (chez-cmark-gfm
  `traps.md`).
