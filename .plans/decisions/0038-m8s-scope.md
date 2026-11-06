# ADR-0038: M8's scope

- **Status:** Accepted
- **Date:** 2026-11-06
- **Scope:** chez-curl v1, M8: multipart/form-data, docs and the v0.1.0 release (the brief, §8),
  and the cap on response headers carried into M8's plan
- **Settles:** what M8 builds in each area, and what v0.1.0 claims. The maintainer chose on
  2026-11-06, the recommended option each time, from three read-only surveys: of the client's
  code and records, of the test instrument, and of the docs and release
  ([research/m8/surveys/](../research/m8/surveys/)).
- **Related:**
  - [ADR-0004](0004-windows-not-supported.md): the platforms v1 aims at;
  - [ADR-0007](0007-one-repo-checked-seam.md): the high level reaches native code only through
    `(curl)`;
  - [ADR-0012](0012-engine-thread-owns-every-handle.md): the engine owns every libcurl handle;
  - [ADR-0014](0014-valgrind-memory-gate.md), amended 2026-11-06: the memory job, split in two;
  - [ADR-0015](0015-test-harness-and-scheme-dependencies.md) and
    [ADR-0001](0001-bind-libcurl-directly.md): Akku left undecided;
  - [ADR-0025](0025-the-high-levels-surface.md), decision 3: the high level's body kinds;
  - [ADR-0032](0032-a-streamed-body-is-sent-at-most-once.md): a streamed body is sent at most
    once;
  - [ADR-0033](0033-m7s-scope.md): file I/O stays the caller's, for cookies.

## Context

On `main` at `fbc6fce`:

- **Multipart:** nothing builds one. `MIMEPOST` and `HTTPPOST` are owned options, and `MIMEPOST`
  is refused by its type besides. `MIME_OPTIONS` and `EXPECT_100_TIMEOUT_MS` are the hatch's.
  Every transfer that sends a body blanks `Content-Type:` and `Expect:` unless the caller names
  them (`transfer.sls:4039-4046`). The surveys read:
  - the floor, 7.85.0, declares the whole `curl_mime` API, and so do 8.5.0, 8.7.1, 8.20.0 and
    8.23.0;
  - a libcurl configured `--disable-mime` defines every `curl_mime_*` symbol, so a missing entry
    point cannot show it, and no `CURL_VERSION_` bit names mime. On 8.23.0 they are stubs. On
    7.85.0 they work whenever SMTP or IMAP is built, as the floor's build has them
    (`lib/mime.c:34`), and HTTP alone stops using them. Measured after this record was first
    written ([research/m8/mime-files/](../research/m8/mime-files/)), each multipart `POST` then
    goes out with no body and is answered 200;
  - on 7.85.0 and 7.86, a mime belongs to the easy handle it was made with; from 7.87.0 it need
    not (`curl_mime_init(3)`);
  - before 8.17.0, a mime read callback that paused was never called again (curl `40f7cd2b`,
    #18848; the M6 source reading, [line 637](../research/m6/source-reading.md)): 7.85.0 and
    8.5.0, and 8.7.1 is not known;
  - libcurl picks a random boundary for each mime: 16 hex characters on 7.85.0, 22 on 8.20.0 and
    8.23.0 (`lib/mime.h`);
  - `curl_mime_filedata` answers 26 at once for a file it cannot `stat` or read, and opens the file
    when the transfer first reads it. A path that is not a regular file, a FIFO or `/dev/stdin`,
    gets no size and no seek (7.85.0 `lib/mime.c:1407-1450`, `715-726`). A failed open during the
    transfer answers 26, after the head and the earlier parts have gone (measured after this record
    was first written: [research/m8/mime-files/](../research/m8/mime-files/), C-removed).
- **Response headers:** the engine's thread walks a response's headers with
  `curl_easy_nextheader`, which walks every header on each call, so n headers cost n²; for a
  streamed response the walk runs twice. 7.85.0 caps one header line at 100 KiB and caps neither
  a response's total size nor its count. Its 50,000-header walk took 7.3 to 7.7 s of CPU
  ([progress.md](../progress.md), PR #39's close-out), stalling every transfer of its engine.
  8.5.0 and later cap a response's headers at 300 KiB, and 8.20.0 and 8.23.0 at 5,000 as well
  (`MAX_HTTP_RESP_HEADER_SIZE`, `MAX_HTTP_RESP_HEADER_COUNT`, read in source).
- **Docs:** README.org is 588 lines, with its Status and Quick start sections empty, no install
  steps, and nothing that runs its nine examples. `docs/` and `CHANGELOG.md` are empty. The three
  public libraries export 194 names. By the docs survey, each of the 174 that are not condition
  types carries a type signature, and the records make 45 promises that a thing is documented,
  13 of which README.org does not keep.
- **The siblings** (chez-cmark-gfm, chez-libuv, chez-httparse, chez-websocket,
  chez-http-server): each has a README.org of 131 to 189 lines and Markdown pages in `docs/`,
  with a hand-written `reference.md` that a check holds to the real exports. Four run their
  examples in a test, and all five deploy a site on a `v*` tag.
- **The release:** the repository is private. `Akku.manifest` names 0.0.0, no tag exists, and a
  `git archive` of a tag would carry `.plans/`: 2,528 of 3,018 tracked files.
- **The platforms:** the suites have run on Linux amd64, in CI on five libcurls and in the Guix
  container, and on macOS arm64 against Apple's 8.7.1, by hand. Never on Linux arm64 or on macOS
  amd64.

## Decision

1. **Multipart: parts in memory, and files by path.** A part is bytes or a string, or a file
   given by its path, which libcurl reads on the engine's thread (`curl_mime_filedata`). Each part
   has a name, and may have a filename and a type. A multipart body is a request's body value at the low level, which the high level's
   verbs carry. Not in M8: streamed parts, nested parts, encoders, and a part's own headers.
2. **Response headers: a cap of chez-curl's own, fixed.** Every transfer caps its response's
   headers by count and by bytes, below every libcurl's own caps, so every lane refuses alike, by
   a named reason. A probe sets the values. No key sets the cap in M8.
3. **Docs: the siblings' shape, without a site.** A thin README.org; Markdown pages in `docs/`;
   a hand-written `docs/reference.md` that a check holds to every export; and examples that a
   test runs. GitHub renders the pages; no site ships in M8.
4. **v0.1.0: a tag, in the private repository.** A CHANGELOG.md entry, `Akku.manifest` at 0.1.0
   and held to the changelog by a check, and the `v0.1.0` tag on the tested squash. Making the
   repository public, publishing to Akku, and what a release archive leaves out are later
   decisions, each of its own.
5. **v0.1.0 claims the platforms that ran:** Linux amd64 and macOS arm64. The docs name Linux
   arm64 and macOS amd64 as untested. ADR-0004's aim stands.
6. **The memory job is split in two,** each gating every pull request (ADR-0014, amended
   2026-11-06).

## Rejected

- **Parts in memory alone:** a large file would cost its size in memory before the transfer.
- **Streamed parts:** they need callables of their own, and on 7.85.0 and 8.5.0 a part that
  paused is never asked again, so the engine would need a workaround or a refusal there.
- **A cap with a key:** nothing measured asks for one. One can follow, as `body-limit` came.
- **No cap, documented:** a server could still stall a 7.85.0 engine for seconds per response.
- **A docs site:** it would copy chez-http-server's `site/` and make chez-cmark-gfm a
  development dependency, amending ADR-0015.
- **README.org alone:** every sibling's shape is a thin README beside `docs/` pages.
- **Public and on Akku at v0.1.0, or public alone:** each publishes, which cannot be taken back;
  no record has decided it.
- **Claiming all four platforms:** two have never run the suites.
- **A Linux arm64 CI lane:** it costs runner minutes, and whether the private repository can have
  arm64 runners is not checked.

## Consequences

- **M8 measures first.** A probe of `curl_mime` and one of the header caps run on the five Linux
  libcurls, and on the Mac against 8.7.1, before the plan decides each rule.
- **A mime handle becomes a counted native kind,** made and freed on the engine's thread with its
  transfer.
- **The rules for a part's bytes and the options it makes its twins are the plan's,** each from
  the probe, as M7's twins were.
- **The docs keep the records' promises:** the plan lists the 45, and closes each one README.org
  does not keep today.
