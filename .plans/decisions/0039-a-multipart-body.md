# ADR-0039: A multipart body: libcurl's form type, strict part bytes, regular files

- **Status:** Accepted; amended 2026-11-06, after the M8 plan's review: decision 3 revised, the
  FIFO window recorded, decision 4 made exact
  ([amendment](#amendment-2026-11-06-after-the-m8-plans-review)); amended 2026-11-07, after slice
  3's measurement: a grown file corrected by version, the request's body handed out as a copy, a
  relative path refused at submit; and after its review, a file whose size is not its content
  ([amendment](#amendment-2026-11-07-after-slice-3s-measurement))
- **Date:** 2026-11-06
- **Scope:** chez-curl v1, M8: a multipart body's parts in memory and its files by path
  ([ADR-0038](0038-m8s-scope.md), decision 1)
- **Settles:** the request's `Content-Type` beside a multipart body; the bytes a part's name,
  filename and type may hold, and `MIME_OPTIONS`; how a file part's path is taken; and how a
  libcurl without mime is told. The maintainer chose on 2026-11-06, the recommended option each
  time, from two probes on the five Linux libcurls, two runs each:
  [research/m8/mime-wire/](../research/m8/mime-wire/) (what a mime body sends) and
  [research/m8/mime-files/](../research/m8/mime-files/) (file parts, resends, lifetime, and
  libcurls built without mime).
- **Related:**
  - [ADR-0009](0009-typed-escape-hatch.md): the options chez-curl owns;
  - [ADR-0012](0012-engine-thread-owns-every-handle.md): the engine owns every handle;
  - [ADR-0003](0003-libcurl-floor-7-85.md): what the load probes;
  - [ADR-0032](0032-a-streamed-body-is-sent-at-most-once.md): a streamed body is sent at most
    once;
  - [ADR-0033](0033-m7s-scope.md): `COOKIEFILE "-"` reads stdin, and is refused.

## Context

Measured on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0. Each
holds on all five unless a version is named.

- **The request's type** (mime-wire, questions 1 to 3). libcurl sends `POST` with
  `Content-Type: multipart/form-data; boundary=B` and a `Content-Length`. Every chez-curl
  transfer that sends a body hands `HTTPHEADER` a blank `Content-Type:` unless the caller names
  one (`transfer.sls`, `sent-header-lines`). Beside `MIMEPOST` that blank sends
  `Content-Type: ; boundary=B`, and every part's `Content-Disposition` becomes `attachment`
  (`results/docker.log:359`, `:363`). A caller's type gets `; boundary=B` appended: a caller's own
  boundary makes two `boundary=` parameters, and `multipart/mixed` or `text/plain` turns the parts
  to `attachment`.
- **`Expect`** (question 4). libcurl adds `Expect: 100-continue` to a body over 1 MiB, over
  HTTP/1.1 alone, and waits about 1 s for a server that never answers; today's blank `Expect:`
  removes it.
- **A part's bytes** (question 5). By default a name or filename has `"`, CR and LF
  percent-encoded and every other byte sent raw, `%` among them, so `a%22b` and `a"b` arrive
  identical. A part's type goes raw under every option: CR LF in it writes a header into the part.
  With `MIME_OPTIONS` at `CURLMIMEOPT_FORMESCAPE`, CR and LF in a name or filename go raw and split
  its header on 7.85.0, 8.5.0 and 8.20.0, and 8.23.0 refuses the transfer with 43
  (`results/docker.log:47671`).
- **The body options** (question 7). The last body option set wins. `UPLOAD` 1 or `POST` 1 set
  after `MIMEPOST` reads stdin through libcurl's default read callback.
- **A file part** (mime-files, tables 1 to 3). `curl_mime_filedata` only `stat`s the path, and
  `access`es it on 7.85.0 and 8.5.0; libcurl opens the file inside `curl_multi_perform`, on the
  engine's thread, when the body reaches the part, and again for each resend. Its size is fixed at
  `curl_mime_filedata`:
  - a file grown since sends the old length of new bytes over the closing delimiter, a malformed
    body answered 200; one shrunk stalls to its timeout on 7.85.0 and 8.5.0, and fails 26 on
    8.20.0 and 8.23.0;
  - a missing path answers 26 at once, and the transfer still sends what is left: on 8.20.0 and
    8.23.0 an empty field, answered 200;
  - a FIFO's open blocks `curl_multi_perform` until a writer comes, past `TIMEOUT_MS`: 1.5 s in
    each of 22 runs, a `TIMEOUT_MS` of 500 set;
  - `/dev/stdin` reads the process's stdin to its end; a directory, `/dev/null` and
    `/proc/self/status` each send an empty part, answered 200;
  - a relative path opens against the working directory at the transfer, so a `chdir` between
    sent another file's bytes at the first one's size, answered 200.
- **Resends** (table 4). libcurl resent data and regular-file parts whole, byte for byte, after a
  dead reused connection, a stale Digest nonce, a `REFUSED_STREAM`, and a 307 or 308 it followed;
  a FIFO part failed 65.
- **A libcurl without mime** (table 8). Every `curl_mime_*` symbol stays, `curl_easy_option_by_name`
  still finds `MIMEPOST`, and the features word is unchanged. 8.23.0 built `--disable-mime`
  answers NULL from `curl_mime_init`. 7.85.0 built so, with SMTP and IMAP as the floor's build has
  them, answers 0 to every mime call and sends each multipart `POST` with no body, answered 200.
  `curl_formadd` answered 7, `CURL_FORMADD_DISABLED`, on both, and 0 on all five full lanes.

## Decision

1. **libcurl writes the request's type.** A multipart transfer leaves `Content-Type:` out of its
   blanks, so libcurl sends `multipart/form-data` with its boundary. A caller's `Content-Type`
   header beside a multipart body is refused, by a named reason. The `Expect:` blank stays.
2. **A part's name, filename and type are strict.** Each is a string, sent as UTF-8, and refuses
   every control character, U+0000 to U+001F and U+007F. A name and a filename refuse `"`. Every
   part has a name, and a name is never empty. `MIME_OPTIONS` becomes owned and is never set, so
   libcurl escapes nothing, and a part's bytes go out as given, alike on every lane.
3. **A file part is a regular file, its path resolved at submit.** Submit, on the caller's thread,
   resolves a relative path against the current directory, and refuses a path that is not a
   regular file it can open. The engine checks that the path is still a regular file just before
   `curl_mime_filedata`, and any answer but 0 fails the transfer before it starts. A file changed
   after submit is the caller's: the docs say what libcurl then sends.
4. **The load probes for mime.** It calls `curl_formadd` once, a new variadic binding that
   `make check-variadic` holds on the Mac, and `curl_mime_init` once, and frees what each made.
   If either says no, a multipart body is refused at submit, by a named reason, and every other
   request works.

## Rejected

- **A caller's `multipart/*` type, its boundary libcurl's:** `multipart/mixed` sends `attachment`
  parts, and the scope is forms.
- **Passing a caller's type through:** a double boundary, or a body no form reader parses.
- **Refusing CR, LF and NUL alone, `MIME_OPTIONS` the hatch's:** `a%22b` and `a"b` stay one on the
  wire, and the hatch's escaping splits by version.
- **The strict bytes, `MIME_OPTIONS` the hatch's:** the same split, reached by the hatch.
- **Absolute paths alone:** a relative path resolved at submit is what its caller meant, and
  never meets a later `chdir`.
- **Any path, documented:** a FIFO path could hold the engine's thread for ever.
- **Refusing only on a NULL `curl_mime_init`:** a 7.85.0 built without mime would send every
  multipart body empty, answered 200.
- **A check after sending:** the empty `POST` has reached the server by then.

## Consequences

- **The twins.** The probe's table names each option that changes a multipart body: `MIMEPOST`,
  `MIME_OPTIONS`, `HTTPPOST`, `POSTFIELDS`, `COPYPOSTFIELDS`, `UPLOAD`, `POST`, `NOBODY`,
  `HTTPGET`, `CUSTOMREQUEST` and `READFUNCTION`. All but `MIME_OPTIONS` are owned on `main` at
  `fbc6fce` (`transfer.sls`, `owned-option-names` and `request-field-options`); it becomes owned.
- **A multipart body is not a stream.** libcurl resends one whole inside a transfer, so ADR-0032's
  rule does not bind it. The plan says what the high level's redirects and retries do with one,
  and each transfer makes its own mime.
- **A path swapped after submit, to a FIFO or `/dev/stdin`, still reaches libcurl.** The engine's
  check narrows that window and cannot close it; the docs say so.
- **No lane builds a libcurl without mime.** The plan says how the probe at load is watched
  failing: a planted seam, a build in Docker, or a CI job like `floor-disabled-api`.

## Amendment, 2026-11-06: after the M8 plan's review

An adversarial review of the M8 plan (Opus, read-only) found decision 3 unsafe as written, and
measured why, in three probes I reran on the Guix lane ([research/m8/review/](../research/m8/review/)):

- **Every high-level submit runs inside a critical section** (`drive.sls:403`, `:1013`, `:1378`,
  `:1492`, `:1515`), and an open that blocks there stalls every thread: a FIFO's open held another
  thread 1,956 to 1,960 ms inside a section, and 1 ms outside one (`critical-open/`).
- **The working directory is the process's:** a `current-directory` set on one thread is every
  thread's (`cwd/`). So a path resolved again at each submit meets a later `chdir`, and a retry or a
  redirect hop sends another file, at the first one's size, answered 200 (mime-files, N-relative).
- **`curl_formadd` with `CURLFORM_END` alone answers 5 on every full libcurl,** 7 on both builds
  without mime, and 4 for an unknown option; with `CURLFORM_COPYNAME` and `CURLFORM_COPYCONTENTS` it
  answers 0 on every full libcurl (`formtell/`, two runs on each lane and build).

**Decided by the maintainer, the recommended option each time:**

1. **Decision 3 is revised: a file part's path is resolved once, and the engine opens it.** The
   path is resolved against the current directory and checked by `stat` alone, a regular file,
   when the request is made; submit checks it by `stat` again; nothing is opened on the caller's
   side. On the engine's thread, outside any critical section, just before `curl_mime_filedata`,
   the engine checks the path by `stat`, then opens the file and closes it, so a file that is
   gone, not regular or unreadable fails the transfer alike on every lane, before anything is
   sent. Any answer but 0 from `curl_mime_filedata` still fails it.
2. **The FIFO window is recorded, not closed.** A path swapped to a FIFO after the engine's check
   blocks the engine's thread in an open for ever: every transfer on that engine stalls, and
   `curl-engine-stop` and a session's close never return. It takes someone who can change the
   caller's files between two checks a moment apart. The docs say so, and that a caller who cannot
   trust its file system reads the file and sends a data part. Rejected: holding the file open
   from the request on and feeding it through `curl_mime_data_cb`, which brings back the callables
   ADR-0038 left out with streamed parts.

**Decision 4 made exact** (the plan's, from `formtell/`): the load calls `curl_formadd` with
`CURLFORM_COPYNAME`, `CURLFORM_COPYCONTENTS` and `CURLFORM_END`, and frees its post. 0 means the
libcurl has mime; 7 means it has not; any other answer is a failure the load records by name, and
multipart is then refused too. A binding that broke the call would answer other than 0, so it
refuses multipart where a "7 means no" rule would read it as yes. A libcurl built
`--disable-form-api` alone, possible from 8.5.0, is read as having no mime, the safe direction (read
in source, not built). ADR-0001's "chez-curl binds neither" `curl_formadd` nor the `curl_mprintf`
family is amended as slice 3 builds.

**And from the review's reading of the probes:**

- a file shrunk after its part is made stalls the transfer on 7.85.0 and 8.5.0 until its
  `timeout-ms`, and for ever with none, which is the default: the probe's 28 was its own 5 s bound
  (mime-files README, C-shrunk);
- a file removed after the engine's check fails the transfer 26 once the head and the earlier parts
  have reached the server, in a request cut short (C-removed).

**Apple's 8.7.1, on the Mac, 2026-11-06** (each probe's `results/mac-8.7.1.log`): it answers as
8.5.0 and later do. `curl_formadd` answers 0 and `curl_mime_init` a mime, so the load reads mime
there; a FIFO's open blocked `curl_multi_perform` 1.5 s; with `CURLMIMEOPT_FORMESCAPE`, CR and LF in
a name go out raw, as on 7.85.0 to 8.20.0; `CURLINFO_REQUEST_SIZE` reads 0, the earlier trap's. No
decision moved.

## Amendment, 2026-11-07: after slice 3's measurement

M8 slice 3 measured a prototype of this record through the engine, on the five Linux libcurls and
the two builds without mime, two runs each ([research/m8/slice3/](../research/m8/slice3/)). I
reran its Guix lane: every cell matched but the reset inside a large part, the race the plan
names.

**The Context's grown file was wrong on two versions.** 7.85.0 and both 8.5.0 builds read a file
grown after `curl_mime_filedata` to its new end and send every byte, past `Content-Length`: over
HTTP/1.1 the server reads the surplus, the file's own bytes, as the next request on the connection
(Node answered 400), and over HTTP/2 it resets the stream (92). The mime probe's own log shows it
too: its stand-in answered at `Content-Length` and logged the 2,000 bytes after as garbage
(`mime-files/results/docker-1.log`, case C-grown), which its tables did not show. 8.20.0, 8.23.0
and Apple's 8.7.1 stop at the declared length: an unterminated body, answered 200. And:

- a file shrunk after the check stalls over HTTP/1.1 on 7.85.0 and 8.5.0 until `timeout-ms`, and
  for ever with none, but fails 92 at once over HTTP/2 there; 26 at once on 8.20.0 and 8.23.0;
- a file removed fails 26 on every lane;
- a FIFO swapped in after the check holds the engine's thread until a writer comes: a transfer
  submitted to that engine 200 ms later took 1.8 s, a `timeout-ms` of 500 ended only after the
  writer came, and `curl-engine-stop` waited for it too (`results/races-*.log`).

**And `curl-request-body` handed out the request's own copy.** The plan had it answer a multipart
body uncopied, as a bytevector body is. But that list is the request's copy, its paths resolved: a
caller's `set-car!` on it made a path relative again, and a submit in another directory sent that
directory's file, answered 200, on all five lanes (the probe's `hole` cell).

**Decided by the maintainer, 2026-11-07, the recommended option each time:**

1. **`curl-request-body` answers a copy of a multipart body:** fresh pairs and fresh name,
   filename, type and path strings, the data as given, as `curl-request-credentials` and
   `curl-request-proxy` answer theirs. **And submit refuses a file part whose path is not
   absolute,** `part-file`.
2. **A file changed after the engine's check stays the caller's** (decision 3, and the FIFO
   window above). The docs say, by version, what libcurl then sends, the overrun among it, and
   that a caller who cannot trust its files sends a data part. Rejected again: a file part through
   `curl_mime_data_cb`, from a file the engine opens at its check, reading at most the size it
   saw. It is the one change that closes the FIFO window, the shrunk stall and the overrun
   together, on every version, and brings back the callables ADR-0038 left out.

**The plan's own, decided with them** (the M8 plan, §3.1, §3.9 and §11):

- `current-directory` is admitted by `check-seam`, to `(curl private transfer)` alone: a path is
  resolved there.
- The high level copies each part's data once, as the call starts, as `call-body` copies a body;
  a retry or a hop then sends the bytes the call began with. The low level copies it at submit.
- The strings handed `curl_mime_name`, `_filename`, `_type` and `_filedata` are counted foreign
  copies, `uptr`, never `string-not-kept` rows: no new string crossing (ADR-0013, amended
  2026-10-23). The plan's §3.9 line on them was wrong.

**After slice 3's review, 2026-11-07** (an Opus review, read-only; its probes and my reruns in
[research/m8/slice3/review/](../research/m8/slice3/review/)):

- **A file whose size is not its content passes the regular-file rule.** procfs and sysfs files
  are regular by `stat`. `/proc/self/status`, size 0, sent an empty part, answered 200, on 8.20.0
  and 7.85.0. A sysfs file of size 4096 holding 23 bytes is sent as a file shrunk after the check
  is: 26 at once on 8.20.0, and on 7.85.0 a stall until `timeout-ms`, 28 at 5,011 ms, for ever
  with none (`review-wire-rerun.log`, `review-wire-floor.log`). **Decided by the maintainer, the
  recommended option:** the rule stays as `stat` sees it, and the docs say that such a file sends
  what a shrunk one sends, by version, and that a caller reads it and sends a data part. Rejected:
  refusing procfs and sysfs by `statfs`'s filesystem type, a new libc binding with a layout per
  platform, on Linux alone, each other pseudo filesystem named in turn.
- **A `stat` on the engine's thread.** The plan's review measured an open of a FIFO outside a
  critical section: Chez deactivates the thread for it, and other threads ran 69,846 to 73,479
  collections across it ([review](../research/m8/review/), `critical-open/`). A `stat` that blocks,
  on a hung network mount, was not measured: none can be made here.
- **As fixed after the review:** `file-regular?` runs with no guard on either side, since it never
  raises for a string, so a caller's interrupt or timer handler's raise inside it leaves as it
  was raised: the guard had turned it into `part-file` in 6 of 20,000 timer runs
  (`review/review-timer-rerun.log`). The engine's open takes the I/O conditions alone. A private
  seam, `transfer-mime-gate-set!`, removes a file between the engine's check and
  `curl_mime_filedata`, so a test meets libcurl's own 26.
