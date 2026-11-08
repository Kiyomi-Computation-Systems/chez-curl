# M8 slice 3, measured before it is built: a multipart body through the engine

Measured 2026-11-07, the M8 plan's §6 "First, measure", for the multipart body ADR-0039 (amended)
decided: a request's `body` of `(multipart PART ...)`, its parts strings, bytevectors or files by
path, its mime made on the engine's thread with its transfer. A prototype of §3.1 and §3.4 ran
through the engine on the five Linux lanes, two runs each, and on the two builds without mime. This
reports what it answered, `make test` on the prototype, and where today's code does not hold what
§3.1 and §3.4 rely on. It recommends only where the brief asks: in the maintainer's questions.
Every number is from a kept log under `results/`, by its path; the tables are `tables.py`'s output
over those logs, in [`results/tables.md`](results/tables.md), condensed here.

## In short

- **The prototype** ([`proto.patch`](proto.patch), 862 lines; it applies to `main` at bd54721 and
  gives the prototype's tree back, checked): the ten bindings, `curl_formadd` variadic and
  `curl_mime_filedata` blocking; the load's probe in one critical section; the body kind, its
  copies, its paths resolved at construction and stat'd there and at submit; the engine's file
  check outside every section; the mime made after `curl_easy_init`, each part through one
  procedure of native's, `MIMEPOST` last, `Content-Type:` out of the blanks, freed after
  `curl_easy_cleanup`, counted as `mime`; and the origin's parts route. The byte rules
  (`part-bytes`, `part-empty`) and `multipart-content-type` are left out, so the probe could send
  what they refuse.
- **The load's probe answers as the plan says, through the engine:** `curl_formadd` 0 and a mime
  on all five lanes; 7 and a mime on 7.85.0 without mime; 7 and NULL on 8.23.0 without mime; the
  counts all zero after the load; on both builds without mime a multipart body is refused at
  submit and by `curl-request-check`, `multipart-unsupported`, and a GET and a bytevector POST
  are served ([the load](#the-loads-probe)).
- **Every part kind arrives byte for byte, on all five lanes, over HTTP/1.1, h2c and h2,** for
  every method that takes a body, a body of 1,048,577 bytes and a 2 MiB file among them, with no
  `Expect` (the blank holds) and libcurl's `multipart/form-data` type. `get` and `head` refuse it.
  `CURLINFO_REQUEST_SIZE` is the head alone on 7.85.0 and 8.5.0 and the head and the body on
  8.20.0 and 8.23.0, as the mime probe found ([kinds](#each-part-kind-every-method-three-faces)).
- **A file grown after the check is not "a malformed body answered 200" on 7.85.0 and 8.5.0:**
  they send the new bytes **past `Content-Length`**, so on HTTP/1.1 the server reads them as the
  start of the next request on the connection (Node answered 400; the mime probe's own stand-in,
  which answers at `Content-Length`, logged the 2,000 bytes as garbage after its 200, which its
  tables did not show); over HTTP/2 Node reset the stream, 92. 8.20.0 and 8.23.0 stop at the
  length, an unterminated body answered 200. A shrunk file stalls over HTTP/1.1 on 7.85.0 and
  8.5.0 as the plan says, but fails 92 at once over HTTP/2 there ([after](#after-the-check)).
- **A FIFO swapped in after the check blocks the engine's thread until a writer comes:** a GET
  submitted to the same engine 200 ms after the release took 1,806.6 to 1,814.0 ms, its writer
  2 s on, on every lane and face, both runs; then the body went whole, 200. A `timeout-ms` of
  500 ended it only after the writer came, 28 at 2,003.7 to 2,013.7 ms, and a
  `curl-engine-stop` made 200 ms after the release returned at 2,010.4 to 2,011.3 ms
  ([after](#after-the-check)).
- **The engine's file check refuses every kind, at once, and blocks on none:** missing, a
  directory, a FIFO, `/dev/null` and an unreadable file, each itself and through a symlink, each
  `part-file` with a request size of 0, in 6 to 26 µs ([check](#the-file-check)). Inside a
  critical section the caller's `stat` took 0.5 to 4.4 µs at the median and 125.8 µs at the most,
  and a whole `make-curl-request` of one file part 1.0 to 5.0 µs and 198.7 µs, over every kind of
  path, lane and run ([stat](#the-callers-stat-inside-a-critical-section)).
- **What §3.1 relies on does not hold in one place:** `curl-request-body` answering the request's
  own copy uncopied lets a caller's `set-car!` make a resolved path relative again; the submit,
  which stats without resolving, then sent the file the current directory names, on all five
  lanes ([item 4](#item-4-todays-code-against-31-and-34)).
- **The resends are whole on every lane:** a dead reused connection, a stale Digest nonce,
  HTTP/2's `REFUSED_STREAM`, a 307 and a 308 followed, a 417 to a caller's `Expect`, and a second
  transfer of one request and a hop's request made from its body, each with its own mime. A reset
  inside a 4 MiB part resent whole or failed 55 by a race on every lane, 26 runs each: 7.85.0
  failed 12, 8.5.0 6 and 5, 8.20.0 9, 8.23.0 8 ([resends](#resends)).
- **The header cap beside `MIMEPOST`** takes 1,000 lines and refuses the 1,001st, `header-limit`
  23, buffered and streamed, on every lane, the stream publishing no head ([cap](#the-header-cap-beside-mimepost)).
- **Under the memory gate's Valgrind,** on 7.85.0, 8.5.0 with OpenSSL and 8.20.0: each part kind,
  a failed file check, a cancel and a timeout mid-body, 0 errors, nothing definitely lost, and
  every count zero at the end ([memory](#under-the-memory-gate)).
- **`make test` on the prototype:** the same 31 of 42 suites fail on every lane, and the same 11
  pass. 24 fail on the ninth counted kind alone, which §1 expects; the plan's other expected
  changes are there (the conventions and prototype rows, the constants, the reasons, the owned and
  field lists, the decoy); and four things it does not name: `current-directory` past the seam,
  the decoy refused for all ten entry points, and two tests that read the code's shape
  ([item 3](#item-3-make-test-on-the-prototype)).
- **Two traps, each reproduced twice** ([traps](#traps-for-trapsmd)).

## What was run

### Item 1: the prototype

`proto.patch` is the prototype's tree against a copy of `main` (bd54721) made by `tar
--exclude=./build --exclude=./.git --exclude=./.plans/research`, in `build/m8s3/work.YS2PJl/`
(`mktemp -d`): `main`, `proto`, and `probe`, the prototype with the seam.

| file | what the prototype adds |
|---|---|
| `src/curl/private/native.sls` | step 6: `curl_mime_init`, `_free`, `_addpart`, `_name`, `_data`, `_filename`, `_type` and `curl_formfree`, plain, `curl_mime_filedata` through `bind-blocking`, and `curl_formadd` through `bind-variadic`, `(uptr uptr int uptr int uptr int)`, last; each string through `call-with-c-string`, the data through `call-with-foreign-bytes`. `curl-mime-init` (counted as `mime`, owned, in its critical section), `curl-mime-free`, and `curl-mime-add-part!`, which adds a whole part, name, data or file, then filename, then type (after the data: `curl_mime_filedata` sets a filename of its own), checking the mime's owner, so no part's address leaves native; it answers #f or the step that refused and its code. Step 7, after `check-apis`: the probe, one critical section, raw bindings, `curl_formadd` with `COPYNAME`, `COPYCONTENTS` and `END`, `curl_formfree`, then `curl_mime_init(NULL)` and `curl_mime_free`; `loaded-mime-probe` and `loaded-mime?` |
| `src/curl/private/constants.sls` | `curlform-copyname` 1, `curlform-copycontents` 4, `curlform-end` 17, `curl-formadd-ok` 0, `curl-formadd-disabled` 7 |
| `src/curl/private/counters.sls` | the ninth kind, `mime` |
| `src/curl/private/conditions.sls` | the request reasons `part-bytes`, `part-empty`, `multipart-empty`, `multipart-content-type`, `part-file`, `multipart-unsupported`; the transfer reasons `part-file`, `mime-failed` |
| `src/curl/private/transfer.sls` | `multipart?`; `multipart-copy`, run by `checked-request` (resolving, against `current-directory`) and by `request-checks` (not resolving), which returns the copy as a ninth value: fresh names, filenames, types and paths, the data kept, uncopied; `checked-part-path` (`part-file` for an empty path, U+0000, or no regular file by `file-regular?`); `multipart-for-plan`, the submit's copy of the data; `multipart-unsupported` in `request-checks`; `check-plan-files!`, the engine's check; `sends-body?`, `sent-header-lines` (no `Content-Type:` blank), `method-settings` (`MIMEPOST` last, as the symbol `mime`, which `set-transfer-options!` sets to the live mime); `request-field-options`' body gains `MIMEPOST`, the twins lose it and gain `MIME_OPTIONS`; `start-transfer!` makes the mime after `curl_easy_init`, failing `part-file` for a file's data and `mime-failed` for the rest; `free-transfer!` frees it after `curl_easy_cleanup`; `abandon-transfer-easy!` forgets it with the easy handle |
| `src/curl/private/engine.sls` | `set-up!` calls `check-plan-files!` before `start-transfer!`, inside the guard that completes the token, outside every critical section |
| `tests/origin.mjs` | the parts route, `ANY /parts?key=K[&hold=1][&lines=N]`, on http, the https faces, h2c and h2: it counts for K as its head arrives (`/seen?key=K`), answers a 100 for an `Expect: 100-continue`, with `hold=1` only once `/raw/release` names K, reads the body, and answers its report: the request's `Content-Length`, `Transfer-Encoding`, `Expect`, `Content-Type`, the body's bytes and hash, then each part's header lines, length, hash, a pattern check and its bytes when 256 or fewer; `lines=N` answers N header lines in all. The http and https faces gain a `checkContinue` listener, Node's own behaviour but for a held parts request |

### The probe's seam

[`seam.py`](seam.py) (its diff [`seam.patch`](seam.patch)) adds to the probe's tree alone, which
`make test` never ran: a gate the engine's file check calls first, on the engine's thread, so a
probe can make a path another kind between the submit's stat and the engine's check; each finished
transfer's `CURLINFO_REQUEST_SIZE` by URL, from `finish-transfer`; and each file check's time.

### The probe, its servers and the lanes

[`engine-probe.sps`](engine-probe.sps) runs each cell on an engine of its own through `(curl)`, and
`(curl unsupported)` for `EXPECT_100_TIMEOUT_MS`. Its groups: `load`, `kinds`, `defaults`,
`bytes`, `ctype`, `check`, `after`, `stat`, `cap`, `resend`, `hole`, `memory`, and, named alone,
`race` and `fifo`. [`run-probe.sh`](run-probe.sh) makes the run's PKI, starts the tree's origin
(`tests/origin.mjs --pki`) and the mime-files stand-in ([`server.mjs`](../mime-files/server.mjs),
copied as `m8s3/server-files.mjs`) for the resends, and runs the probe, natively or under the
memory gate's Valgrind. [`lanes.sh`](lanes.sh) and [`lanes-in-docker.sh`](lanes-in-docker.sh) run
it, or `make test`, in Docker, as slice 2's did; the Guix lane runs in `scripts/guix-env`.

| lane | libcurl | Node, probe | Node, `make test` | where |
|---|---|---|---|---|
| F | `build/e1/ci/curl-floor` 7.85.0, OpenSSL 3.0.13 | 20.10.0 | 20.10.0 | Docker `ubuntu:24.04`, `--network none`, spike E1's threaded Chez 10.4.0, CPUs 6-11 |
| O | Ubuntu's `libcurl.so.4` 8.5.0-2ubuntu10.16 | 24.18.0 (the store's) | 20.10.0 | the same |
| G | Ubuntu's `libcurl-gnutls.so.4` 8.5.0-2ubuntu10.16 | 24.18.0 | 20.10.0 | the same |
| X | the profile's 8.20.0, GnuTLS 3.8.13 | 24.18.0 | 24.18.0 | `scripts/guix-env`, `taskset -c 12-17` |
| C | `build/verify/c823/lane1/curl-current` 8.23.0 | 24.18.0 | 20.10.0 | Docker |
| N785, N823 | `build/m8/mime-files/nomime-7.85.0`, `nomime-8.23.0` | 24.18.0 | — | Docker, CPUs 12-17, the `load` group alone, no stand-in |

Every container ran `--network none` (`network interfaces: lo` in each Docker log), from slice 2's
apt cache, `build/m8s2/apt`, and every probe as uid 1000, never root (each log's `tree` line).

**Logs** (`results/`): `probe-docker-{1,2}.log` (F, O, G and C), `probe-guix-8.20.0-{1,2}.log`,
`probe-nomime-{1,2}.log`; `races-*.log` (the `race` and `fifo` groups, twice each);
`memory-*.log` and `*.vg` (Valgrind); `test-proto-*.log` (`make test`); `trap-fd-{1,2}.log`.
Runs 1 and 2 ran the probe as `results/engine-probe-runs12.sps` holds it; the `race` and `fifo`
groups, which run only when named, came after.

**Checks:** every probe process ended `program exit=0`, every count was zero at each run's end on
every lane (`tables.md`, "Counts at each run's end"), and no server wrote on stderr.

## Item 2: through the engine

### The load's probe

| lane | `curl_formadd`, `curl_mime_init` | mime | counts after the load | a multipart POST | GET, bytevector POST | `curl-request-check` of multipart |
|---|---|---|---|---|---|---|
| F, O, G, X, C | 0, a mime | #t | all 0 | 200, one part, parsed | 200, 200 | passes |
| 7.85.0 without mime | 7, a mime | #f | all 0 | refused at submit, `multipart-unsupported`, field `body` | 200, 200 | refused, `multipart-unsupported` |
| 8.23.0 without mime | 7, NULL | #f | all 0 | refused at submit, `multipart-unsupported` | 200, 200 | refused, `multipart-unsupported` |

`probe-docker-1.log:16-17`, `probe-guix-8.20.0-1.log:5-6`, `probe-nomime-1.log:15-16` and `:30-31`;
alike in run 2. The counts are read before any engine is made.

### Each part kind, every method, three faces

A string `"Holiday"`, a bytevector `104 105 0 255 13 10`, and a 1,000-byte file, each with no
option, a filename, a type and both; the plan's example body (a string, a file with a type, a
bytevector with a filename) by `post`, `put`, `patch` and `delete`; bodies of 1,048,575 and
1,048,577 bytes, a 2 MiB file and two files; over h1, h2c by prior knowledge and h2 over TLS.

- **Every part arrived as asked, on all five lanes, both runs:** each part's header lines equal
  the asked name, filename and type, or with libcurl's default type alone added, and its data
  byte for byte (by the origin's escaped bytes, or its pattern check past 256 bytes). `get` and
  `head` are refused as the request is made, `body-not-allowed`.
- **The origin saw `Content-Type: multipart/form-data; boundary=B`, a `Content-Length`, and no
  `Expect`, at every size, on every face:** the `Expect:` blank holds past 1 MiB (`tables.md`,
  "What the origin saw").
- **A file part's filename is its path's last component,** as libcurl does it, when none is
  given.
- **`CURLINFO_REQUEST_SIZE`**, against the body the origin read:

  | cell, h1 | F 7.85.0 | O, G 8.5.0 | X 8.20.0, C 8.23.0 |
  |---|---|---|---|
  | one string part, body 143 or 155 | 174 | 180 | 335 |
  | 1,048,577 bytes of data, body 1,048,715 or 1,048,727 | 179 | 185 | 1,048,912 |

  The head alone on 7.85.0 and 8.5.0, the head and the body on 8.20.0 and 8.23.0, over HTTP/2
  too (183 and 1,048,910); `tables.md` holds every cell. §3.8's row holds.

### Default types

One part over h1, `post`, all five lanes alike in both runs:

| asked | `Content-Type` that came |
|---|---|
| a file `t.txt` or `t.TXT`; data with filename `t.txt` | `text/plain` |
| `t.htm`, `t.html` | `text/html` |
| `t.gif`, `t.jpg`, `t.jpeg`, `t.png`, `t.svg` | `image/gif`, `image/jpeg`, `image/jpeg`, `image/png`, `image/svg+xml` |
| `t.pdf`, `t.xml` | `application/pdf`, `application/xml` |
| a file `t.json`, `t.csv`, `t.bin`, `t` | `application/octet-stream` |
| data with filename `t.json`, `t.csv`, `t.bin` or `t`; data with no filename | none |
| file `t.txt`, filename `o.bin` | `text/plain`: the path's, the filename's extension unknown |
| file `t.bin`, filename `o.txt` | `text/plain`: the filename's |
| an empty data part; an empty file `empty.txt` | none; `text/plain` |
| two parts of one name | both sent |

So libcurl knows `txt htm html gif jpg jpeg png svg pdf xml`, in any case: the docs' list.

### Hostile and edge bytes

Each value in a name, a filename, a type and a data value of part 1, a part `z` after it, over
h1, `MIME_OPTIONS` never set; the same on all five lanes, both runs (`tables.md`, every byte):

| value | name and filename | type | value |
|---|---|---|---|
| U+0000 | `call-with-c-string` raises `&curl-embedded-nul` on the engine's thread: the token's outcome, no transfer error | the same | sent, a NUL byte |
| U+0001 to U+0008, U+000B, U+000C, U+000E to U+001F, U+007F, tab | raw | raw | raw |
| LF, CR | `%0A`, `%0D` | raw: a lone CR or LF in the line | raw |
| CR LF `X-Injected: 1` | `a%0D%0AX-Injected: 1` | **a header line of its own**, `X-Injected: 1` | raw |
| `"` | `%22`, the same as `%22` given | raw | raw |
| `%`, `\`, `;`, space, `!`, `#`, `~` | raw | raw | raw |
| U+0080, `é`, `λ`, `€` | their UTF-8 bytes | the same | the same |
| a leading U+FEFF | `EF BB BF`, kept | kept | kept |
| empty | `name=""`, `filename=""` | `Content-Type: ` | an empty part |
| 26 dashes and 16 hex digits, a 7.85.0 boundary's shape; the same between CR LF and `--` | raw, or `%0D%0A` around it | split into lines | raw: the part count stays 2, libcurl's boundary being random |

Which of these the byte rules of §3.4 refuse is decided: every control char, U+0000 to U+001F and
U+007F, in a name, filename or type, `"` in a name or filename, and an empty name, filename or
type. What the wire shows here is mime-wire's question 5 again, alike through the engine, with one
thing more: a leading U+FEFF goes out (`string->utf8` keeps it).

### A caller's Content-Type

Two data parts, h1 and h2, all five lanes, both runs:

| the caller's header | what went out | the parts by the first `boundary=` | dispositions |
|---|---|---|---|
| none: the blank left out | `multipart/form-data; boundary=B` | 2 | `form-data` |
| `multipart/form-data` | the same | 2 | `form-data` |
| `multipart/form-data; boundary=caller-0123456789` | `...; boundary=caller-0123456789; boundary=B` | **0**: the caller's boundary is not the body's | — |
| `multipart/mixed`, `text/plain` | `multipart/mixed; boundary=B`, `text/plain; boundary=B` | 2 | **`attachment`** |
| `""`, sent as `Content-Type;` | `; boundary=B` | 2 | **`attachment`** |

So leaving the blank out is what makes the body a form, and a caller's type breaks it as
mime-wire's question 3 found; `multipart-content-type`'s refusal is what the build adds.

### The file check

| path | at construction, the caller's stat | at the engine's check (the seam's gate, after the submit's stat) |
|---|---|---|
| missing, a directory, a FIFO, `/dev/null`, each itself and through a symlink | refused, `part-file`, field `body`, value `(part 0 path)` | `part-file`, a transfer error with no code and a request size of 0 |
| an unreadable file (mode 000), itself or through a symlink | **made**: stat says regular; the engine refuses it, `part-file`, size 0 | `part-file`, size 0 |
| a regular file, itself or through a symlink | made, 200, sent whole | 200, sent whole |

All five lanes, both runs. The engine's check took 6 to 26 µs a file part (`tables.md`, "The
engine's check"; its first row also holds the five `made` cells' checks before it); a FIFO there is
refused by its stat, before any open, so nothing blocks. (`/dev/null` cannot be swapped in as the
path itself without root: a symlink stands in.)

### After the check

The file, 3,000 bytes when the engine checked it and `curl_mime_filedata` stat'd it, then changed
while the origin held the head: the request carried `Expect: 100-continue`, `EXPECT_100_TIMEOUT_MS`
60000 by the hatch, and the parts route held its 100 until the change was made, so libcurl had not
opened the file and no cell races. Parts `before`, the file, `after` (or the file last, for
`grown-last`). Both runs alike:

| change | F 7.85.0, O and G 8.5.0, h1 | the same, h2 | X 8.20.0, C 8.23.0, h1 and h2 |
|---|---|---|---|
| none | 200, whole | 200, whole | 200, whole |
| grown by 2,000 bytes | **400**: the bytes past `Content-Length` began a second request | **92**, `PROTOCOL_ERROR`: more DATA than `content-length` | 200, the body unterminated: the declared length holds, the file's new bytes in place of the part after it and the closing delimiter |
| grown, the file last | the same, 400 | 92 | 200, unterminated: the file part 3,054 bytes long, to the body's end |
| shrunk to 1,000, `timeout-ms` 3000 | **28 at 3,004 ms**, a stall | **92 at once** | 26 at once, "client mime read EOF fail, only 1430/3430" |
| shrunk, no `timeout-ms` | **stalled**: still running at 6,000 ms, then cancelled | **92 at once** | 26 at once |
| removed | 26, "read function returned funny value", size: the head alone | 26 | 26, "read error getting mime data", size 477: the head and the part before |
| replaced by a FIFO, a writer 2 s on writing 3,000 bytes | 200, whole, ending 2,007.7 to 2,015.0 ms after the release | the same | the same |

`probe-docker-1.log:1249-1274` (F), `:2799-2824` (O), `:4343-4368` (G), `:5905-5942` (C),
`probe-guix-8.20.0-1.log:1238-1275`, and the same cells of each run 2.

- **The grown file on 7.85.0 and 8.5.0 is past what §3.8 says.** libcurl reads the grown file to
  its new end and sends every byte, the declared length notwithstanding: the mime probe's kept log
  shows it too, `data_out=3291` for a declared 1,291 on 7.85.0 and 3,309 for 1,309 on both 8.5.0
  builds, and its raw stand-in logging `garbage bytes=2000` after its 200
  (`mime-files/results/docker-1.log` and `-2.log`, case C-grown), where 8.23.0 sent 1,309. Its
  table read only the body the stand-in framed. Over HTTP/1.1 the surplus begins the next request
  on that connection, whatever the file holds.
- **The FIFO holds the whole engine:** a GET submitted to the same engine 200 ms after the release
  took 1,806.6 to 1,814.0 ms on every lane, face and run, ending as the writer came. The `fifo`
  group, two runs on every lane (`races-*-{1,2}.log`; `tables.md`, "The FIFO's timeout and
  stop"): the same swap with `timeout-ms` 500 ended 28, "Operation timed out after 2023
  milliseconds" (2030 once on 7.85.0), 2,003.7 to 2,013.7 ms after the release: the timeout
  could not fire while `curl_multi_perform` sat in the open. And with no timeout, a
  `curl-engine-stop` from another thread 200 ms after the release returned 2,010.4 to 2,011.3 ms
  after it, the token `stopped`: the stop waited for the writer too. So the docs must say that a
  path that is a FIFO when libcurl opens it holds the engine's thread, every transfer on that
  engine, its `timeout-ms`, its stop and a session's close, until a writer opens the FIFO, and for
  ever if none does; that the engine's check refuses a FIFO, so only a swap after the check can do
  it; and that a caller who cannot trust its file system reads the file itself and sends a data
  part.

### The caller's stat, inside a critical section

`make-curl-request` of one file part, and `file-regular?` alone, each 200 times inside
`critical-section`, µs, median (max), run 1:

| path | F 7.85.0 | O 8.5.0 | X 8.20.0 | C 8.23.0 |
|---|---|---|---|---|
| a regular file | make 5.0 (25.7), stat 4.4 (24.5) | 2.2 (12.8), 1.4 (7.0) | 3.4 (23.6), 2.1 (11.2) | 4.1 (18.1), 2.7 (11.7) |
| missing | 2.1 (13.5), 0.8 (1.6) | 1.0 (8.3), 0.6 (0.9) | 2.4 (13.2), 1.1 (2.3) | 1.4 (10.2), 0.8 (5.3) |
| a directory | 2.5 (7.2), 1.5 (5.8) | 1.3 (124.8), 0.9 (2.3) | 1.7 (180.3), 0.7 (1.7) | 1.3 (127.7), 0.9 (2.1) |
| a FIFO | 2.4 (7.4), 1.2 (5.9) | 1.3 (5.3), 0.9 (5.1) | 1.9 (7.5), 0.8 (3.9) | 1.3 (2.6), 0.9 (7.0) |
| `/dev/null` | 1.9 (143.3), 1.0 (4.3) | 1.0 (1.5), 0.6 (3.3) | 1.5 (2.9), 0.5 (2.8) | 1.0 (1.5), 0.6 (3.0) |
| unreadable | 2.2 (8.1), 1.5 (3.6) | 1.3 (4.6), 0.9 (1.8) | 1.7 (34.4), 0.8 (2.2) | 1.3 (5.3), 0.9 (1.8) |

G and each kind through a symlink are in `tables.md`. A FIFO's stat blocks nothing. These are
local files; a stat of a hung network mount would hold the section for as long as it hangs, and
the high level stats each file part three times for a call's first transfer, each inside one of
its critical sections, and more with a bound, `http-parallel` or a hop (item 4).

### The header cap beside `MIMEPOST`

Two parts, 70,005 bytes of data, the parts route answering 1,000 or 1,001 header lines in all, h1
and h2: 1,000 is a 200 on every lane, buffered and streamed, the stream's head published with 1,000
headers; 1,001 is `header-limit` 23, of `&curl-too-large`, on every lane, buffered and streamed,
the stream publishing no head and its port raising it. Its request size is the head alone on
7.85.0 and 8.5.0 (189, 195) and the head and the whole body on 8.20.0 and 8.23.0 (70,444): the
body had gone before the answer's head came. Slice 2's callable and the mime sit together.

### Resends

Against the mime-files stand-in, a data part of 3,000 bytes or a file of 3,000, beside a field:

| cell | every lane, both runs |
|---|---|
| a dead reused connection, dropped once the body was read, or as the head came | two requests, each body whole (3,235 or 3,253 bytes, by version), each closed, the parts alike |
| a stale Digest nonce | the bare probe (0 bytes), then two bodies whole and alike, 401, 401, 200 |
| HTTP/2 `REFUSED_STREAM`, at the stream's end or its head | the body again, whole and alike |
| a 307 and a 308, libcurl's own follow (the private `follow` field) | the body to the hop, whole and alike |
| a caller's `Expect: 100-continue` answered 417 at the head | one body, after the 417, whole |
| a reset as the head arrives, inside a 4 MiB file part | a race: resent whole, 200, or 55 "Send failure: Connection reset by peer", no resend (below) |
| the same request submitted twice, then a hop's request made from its `curl-request-body` | three transfers, three bodies whole and alike, each its own mime |

So the high level's model, a retry resubmitting the request and a hop's request carrying its body,
gives each transfer a fresh mime that sends the same parts.

**The reset inside a 4 MiB part,** every run (`tables.md`, "The reset inside a 4 MiB part"): each
lane's three cells in runs 1 and 2 and the `race` group's twenty (`races-*-{1,2}.log`):

| lane | resent, 200 | failed 55 |
|---|---|---|
| F 7.85.0 | 14 | 12 |
| O 8.5.0 | 20 | 6 |
| G 8.5.0 | 21 | 5 |
| X 8.20.0 | 17 | 9 |
| C 8.23.0 | 18 | 8 |

Every resend was whole; no lane is free of the failure, 7.85.0 and the OpenSSL 8.5.0 among them,
which the mime probe saw resend in 22 of 22. When it resends on 8.20.0 and 8.23.0, the request
size sums the cut first attempt and the whole second, 4.4 to 6.0 MB for a 4.2 MB body.

### Under the memory gate

The `load` and `memory` groups under the memory gate's Valgrind (its options exactly, the Guix
suppression in the container), the cancel and the timeout given 4 s against a sink that holds its
reading 20 s (`M8S3_SLOW`):

| lane | cells | Valgrind | counts at the end | log |
|---|---|---|---|---|
| F 7.85.0 | a string, a bytevector, a file and a mixed body over h2, each 200 and whole; an unreadable file, `part-file`; a cancel mid-body; a timeout mid-body, 28 | `ERROR SUMMARY: 0 errors from 0 contexts`, definitely lost 0 | all 0 | `memory-docker.log`, `memory-floor.vg` |
| O 8.5.0 | the same, alike | 0 errors, 0 lost | all 0 | `memory-docker.log`, `memory-openssl.vg` |
| X 8.20.0 | the same; its timeout's request size 2,162,688, mid-body | 0 errors (`suppressed: 1 from 1`, the Guix entry), 0 lost | all 0 | `memory-guix-8.20.0.log`, `.vg` |

### Cells the runs split

`tables.md`, "Cells the two runs split": 9 of 1,998 cells, every one the reset inside the 4 MiB
part, which resent (200) or failed 55 by the run, or resent both times with a request size that
sums the first attempt's cut bytes, 4,391,433 or 4,719,113 (X), 4,653,577 or 4,522,505 (C). That
cell got twenty runs more on every lane (above). Nothing else split.

## Item 3: `make test` on the prototype

The whole `make test` on the `proto` tree, once on each lane: `make check-seam` alone first, since
`make test` needs it and it refuses the prototype, then `make -o check-seam test`, so every suite
ran (`lanes-in-docker.sh`; the Guix lane the same in `scripts/guix-env`).
[`maketest.py`](maketest.py) classes each failing test: by the kind alone when its actual value is
its expected one with `(mime . 0)` added to each counts list ([`results/maketest.md`](results/maketest.md)).

| lane | `check-seam` | suites | passed | failed | log |
|---|---|---|---|---|---|
| F 7.85.0 | refused: `current-directory` | 42 | 11 | 31 | `results/test-proto-floor.log` (597 s) |
| O 8.5.0 | refused | 42 | 11 | 31 | `results/test-proto-openssl.log` (593 s) |
| G 8.5.0 | refused | 42 | 11 | 31 | `results/test-proto-gnutls.log` (583 s) |
| X 8.20.0 | refused | 42 | 11 | 31 | `results/test-proto-guix-8.20.0.log` |
| C 8.23.0 | refused | 42 | 11 | 31 | `results/test-proto-current.log` (579 s) |

The same suites on every lane, and the same 42 failing tests that are not the kind's alone. Passed: `test-check-floors`, `-check-nothreads`, `-discovery`,
`-drift`, `-load-state`, `-manifest`, `-origin`, `-origin-tls`, `-require-threaded`, `-variadic`
and `-verify`. No suite hung. What answered differently:

- **The ninth counted kind, alone (§1 expects it):** `test-auth` (4 tests), `-call-checks` (19,
  each a child's printed counts), `-cookies` (2), `-curl-testing` (1), `-engine` (33 to 35, by
  lane), `-group` (13), `-headers` (1), `-http-client` (11), `-mailbox` (4), `-native` (2),
  `-printed` (1), `-proxy` (9), `-redirect` (2), `-request` (13), `-retry` (3), `-stream-call` (3),
  `-stream` (14), `-unsupported` (28), `-upload` (6), `-url-location` (195), `-url-parts` (135),
  `-url` (117 to 127, by lane) and `-version` (3); `-memory-safety`'s 58, and its written-out
  `native-kinds`. And the kind's tests of the seven suites below.
- **The plan's other expected changes:** `test-collect-safe`, `no-row` for each of the ten
  bindings; `test-constants`, the five constants and the ten prototype rows; `test-conditions`, the
  written-out request and transfer reasons, which now end in the multipart ones; `test-transfer`,
  `owned-option-names` and `request-field-options` written out, `MIMEPOST` the body field's and
  `MIME_OPTIONS` a twin; `test-library-loading`, 17 decoy cases (below).
- **Not in the plan:**
  - `check-seam` and `test-check-seam`'s "allowed-chez-names is exactly the names ... src/
    import": `current-directory` (question 3).
  - `test-library-loading`: the decoy has none of the ten entry points, so the control, each
    switch's case, the preflight and **every `DECOY_LACKS_*` case** are refused `missing-api`
    naming `curl_mime_init`: `lacks-curl_easy_setopt` names it, not its own entry point, since the
    mime bindings come before the setopts. The decoy needs all ten, and the accepted case's call
    log the probe's four calls.
  - `test-transfer-tls`' "the checks hand the plan their snapshot" reads `request-checks`' `values`
    form as text, which the prototype's ninth value changed; and `test-transfer`'s "every option
    set-transfer-options! sets is an owned option" counts the `(car setting)` sites in the
    `method-settings` loop, three, which the prototype's `mime` placeholder made four. Both hold
    the code's shape.
- **What did not answer differently, and might have:** `test-unsupported`'s written-out owned list
  still holds `MIMEPOST`, refused as a field's now, and lacks `MIME_OPTIONS`, which nothing
  refuses in a test until the build adds it; `test-native`'s wrong-thread table is a written list
  no check holds to native's exports, so the prototype's three new procedures that take a handle,
  absent from it, failed nothing; `test-variadic` passed, no row reaching `curl_formadd`;
  `test-request`'s written-out `sent-header-lines` and `method-settings` answers for today's
  bodies held; `test-headers`' cap tests passed beside the mime; and `test-origin` and
  `test-origin-tls` passed with the parts route and the `checkContinue` listener.

## Item 4: today's code against §3.1 and §3.4

- **`curl-request-body` answers the record's own list, uncopied** (`transfer.sls:1083`, a checked
  accessor of the field). For a bytevector body that is the caller's object; for a multipart body
  it is the request's copy, whose paths §3.1 resolves. The probe's `hole` cell, on all five lanes,
  both runs: made in directory a, `(eq? (curl-request-body r) (curl-request-body r))` is #t, a
  `set-car!` on it made the path `rel.txt` again, and a submit in directory b sent b's
  `rel.txt`, 80 bytes of `B`, 200; `curl-request-with` in b resolved it against b. The submit
  "checks it by stat again, without resolving" (§3.1), so a relative path reaching it is opened
  against whatever the current directory is at the transfer.
- **Where a call starts** (`http-client.sls:618`, `call-state`): its checks' critical section runs
  `call-request-of` (`call.sls:633`), which makes the request twice, `checked` (`:667`) and the
  final one (`:685`), each a `make-curl-request` that resolves and stats; another thread's
  `chdir` can fall between the two (the section stops no thread). The call then holds the final
  request's absolute paths, so its retries (`exchange.sls:1046`, the same request) and hops
  (`next-request`, `:748`, `'body (curl-request-body last)` unless `body-dropped?` drops it) send
  the files it named, the hole above aside. §3.1's "the call resolves each relative path once,
  when it starts" holds by the low level's construction alone; the high level needs no
  resolving of its own.
- **The stats a call makes of each file part, and the sections they run in:** two at the call's
  start, in `call-state`'s section, and a third there for `http-parallel` (`curl-request-check`);
  then, for each transfer, one in `exchange-submission`'s `curl-request-with` when the call is
  bounded (`exchange.sls:526`: outside a section in `drive-exchange` and `drive-stream`, inside the
  group's, `submit!` at `drive.sls:1248` being called in `admit-one!`'s section, `:1378`), and one
  at its submit, inside the drive's section (`drive.sls:405`, `:1015`); and one for each redirect
  hop's `next-request`, inside the step's section. So an unbounded call's first transfer stats
  each file part three times, each inside a critical section; a low-level `curl-submit` stats it
  once, in none (its URL's parse alone runs in `in-section`). Each is µs locally (above).
- **"A part's data is copied at submit alone ... so a request built inside the high level's
  critical sections costs no copy"** holds for the construction, but every high-level submit
  runs inside a critical section (`drive.sls:405`, `:1015`, and a group's `submit!`, called in
  `admit-one!`'s section, `:1378`, and in its turn's), so the copy still runs in
  one, as a whole body's does today: the trap's 208 ms per 256 MiB with Ctrl-C held. And the
  high level's `body` is copied at the call's start, `call-body` (`call.sls:565`), so its retries
  send the bytes the call began with; a multipart body's data, copied at each submit, is what the
  caller's objects hold at that submit, a retry after a mutation sending other bytes.
- **The body through a retry, a hop and a group:** a retry submits the same request; a hop's
  request is made from the last one's body, kept for a 307 and a 308 and dropped by a 301 or 302
  of a `post` and by a 303; a group's `go` makes its request by `call-state`, as a call does, and
  submits it inside its sections. `spent?` and `drive-stream`'s checks read `(eq? body 'stream)`, so
  a multipart body is never taken for a producer's, and `hop!`'s `(if (curl-request-body request)`
  takes it as a body that is sent (`drive.sls:1050`). Nothing of the high level reads a body's
  shape beyond these.
- **An abandoned easy handle keeps its mime** (§3.4) needs a change the plan does not name:
  `abandon-transfer-easy!` sets the easy field to #f (`transfer.sls:4461`), and `free-transfer!`
  frees what the record holds after, so it would free the mime of a handle still in the multi
  handle. The prototype clears the mime field there too, leaving it counted. Today's
  `free-transfer!` frees an abandoned handle's header list, error buffer and CURLU likewise.
- **The engine's set-up runs outside every critical section** (`engine.sls:2050`, called from the
  turn's loop with no section), so the file check there is outside them, as ADR-0039 asks; the
  check's open of a regular file is the review's measured 0 to 1 ms.

## What the maintainer must answer

1. **What `curl-request-body` answers for a multipart body.** The plan has it answer the request's
   list uncopied, as a bytevector body's; but that list is the request's own copy, its paths
   resolved, and the probe's `hole` cell changed it from outside and sent another directory's
   file (item 4).
   - (a) Answer a fresh copy, fresh pairs and fresh metadata strings, the data objects as given,
     as `curl-request-credentials` and `curl-request-proxy` answer theirs.
   - (b) Keep the plan's uncopied answer, and have the submit refuse a path that is not
     absolute, `part-file`: only a change from outside can put one there.
   - (c) Both.

   **Recommended: (c).** (a) keeps the record's copy its own, as every copied field is; (b) is
   one char's test at submit, and holds against a change through the path string as well.
2. **A file grown after the check, on 7.85.0 and 8.5.0.** ADR-0039 leaves a changed file to the
   caller and the docs; the evidence adds that those versions send the new bytes past
   `Content-Length`, which an HTTP/1.1 server reads as the next request on the connection (the
   file's own bytes, after the body), and an HTTP/2 server refuses (92).
   - (a) Keep the decision: the docs say, by version, what libcurl then sends, this among it.
   - (b) Send a file part through `curl_mime_data_cb`, a read callable giving at most the size
     stat'd from a port the engine opens at its check: one open, so the FIFO window, the shrunk
     stall and the overrun close together, on every version; the option the amendment rejected,
     since it brings back callables.

   **Recommended: (a)**, as ADR-0039 weighed the FIFO window, which is worse, with (b) recorded
   as the one change that closes all three.
3. **`current-directory` past the seam.** `check-seam` refuses it, and the build needs it
   (`(current-directory)` is how a path is resolved). It can set the directory too.
   - (a) Add it to `allowed-chez-names`, and to `library-only-chez-names` for `(curl private
     transfer)` alone.
   - (b) Add it to `allowed-chez-names` alone.

   **Recommended: (a).**
4. **When the high level copies a part's data.** Item 4: a call's `body` is copied as the call
   starts, so its retries send the bytes it began with; a multipart part's data, copied at each
   submit (§3.1, §11.8), is what the caller's objects hold at that submit.
   - (a) The high level copies each part's data once as the call starts, in `call-state`'s
     section, as `call-body` copies a body today; the low level keeps "at submit alone".
   - (b) Leave it at submit, and document that a retry or a hop sends what the objects hold then.

   **Recommended: (a)**, the high level's own precedent.

## What the build will need that the plan does not say

- **§3.8's rows, from these tables:** grown, by version, as above (past `Content-Length` on 7.85.0
  and 8.5.0, an unterminated 200 on 8.20.0 and 8.23.0); shrunk, a stall over HTTP/1.1 on 7.85.0
  and 8.5.0 but 92 at once over HTTP/2 there; removed, 26 everywhere, the message and the request
  size by version; the FIFO, every transfer of the engine held until a writer comes, `timeout-ms`
  ending nothing before it, and `curl-engine-stop` waiting for it (both measured, above); Apple's
  8.7.1 row is the Mac's to take. ADR-0039's Context and the mime probe's README line on the grown
  file ("the declared length holds") want the same correction.
- **`current-directory`** in check-seam's lists and `test-check-seam`'s copy of them (question 3).
- **The decoy needs all ten new entry points,** not `curl_formadd` and `curl_mime_init` alone:
  each is required, and a decoy without them is `missing-api`, naming `curl_mime_init`. Because
  the mime bindings come before the setopts, that refusal came first in every `DECOY_LACKS_*` case
  of `test-library-loading`: `lacks-curl_easy_setopt` named `curl_mime_init`, not its own. Where
  each new binding sits in step 6 decides which a library lacking several is refused for. The
  accepted decoy's call log gains the probe's four calls after `curl_easy_cleanup`.
- **The counted kind's lists are 27 files and 49 lines now,** not §1's 26 and 48: slice 2's
  `test-headers.sps` added one (`grep -E '\(share \. 0\)|\(share \. 1\)|multi share\)'`).
- **Two tests read the code's shape and change with the prototype's:** `test-transfer-tls`' "the
  checks hand the plan their snapshot" holds `request-checks`' `values` form as text, which the
  multipart copy's ninth value changes; `test-transfer`'s "every option set-transfer-options! sets
  is an owned option" counts three `(car setting)` sites in the `method-settings` loop, which the
  live mime's placeholder makes four. The build's shape of those two forms updates both.
- **`MIMEPOST`'s value is the live mime,** which `method-settings`' data cannot hold: a
  placeholder that `set-transfer-options!` replaces, the prototype's symbol `mime`; `test-request`
  writes out `method-settings`' answers, so it holds the placeholder.
- **`request-checks` answers the multipart copy,** so a submit stats once and uses the copy it
  checked; `curl-request-check` drops it. The prototype added it as a ninth value.
- **`abandon-transfer-easy!` must leave the mime counted and unfreed** (item 4).
- **The engine's `part-file` carries no code and no text of its own:** `(failed part-file #f none
  "" size=0)`, its message `failure`'s fallback, "the transfer failed". `failure`'s message case
  wants `part-file` and `mime-failed`.
- **A U+0000 that reaches the engine** in a name, filename or type raises `&curl-embedded-nul`
  from `call-with-c-string` as the token's outcome, not a transfer error, and that condition
  holds the string whole. The byte rules refuse U+0000 first; the secrets test can hold the
  backstop too.
- **The build's tests need two holds the probe used:** the parts route's `hold=1` with a caller's
  `Expect: 100-continue` and `EXPECT_100_TIMEOUT_MS` by the hatch, which keeps libcurl from opening
  the file until the change is made; and, to reach the engine's check with a path the caller's stat
  passed, a gate like the seam's, or an unreadable file, which reaches it with none.
- **The origin's http and https faces take a `checkContinue` listener,** which replaces Node's own
  100 for every request on them; it writes the 100 and calls the request listener, Node's
  behaviour, and `test-origin` and `test-origin-tls` passed with it (item 3).
- **The strings' crossing:** the prototype hands `curl_mime_name`, `_filename`, `_type` and
  `_filedata` a `call-with-c-string` copy as `uptr`, so no row needs `string-not-kept`, and the
  global rule that every string handed libcurl is such a copy holds; §3.9's "strings libcurl
  copies (`string-not-kept`)" is the other way, and the build chooses one.
- **`curl_formadd` is bound last,** after `curl_share_setopt`, `(uptr uptr int uptr int uptr
  int)`: `test-variadic` passed on the prototype, no row reaching it yet (§3.9's new row).
- **Two lists nothing holds:** `test-native`'s wrong-thread table is written out by hand, and no
  test holds it to native's exports, so §3.4's "each new procedure joins it" is kept by review
  alone unless the build adds that check; and `test-unsupported`'s owned list needs
  `MIME_OPTIONS` added by hand, nothing failing without it.
- **A leading U+FEFF in a name, filename or type goes out as `EF BB BF`,** and the byte rules
  pass it; a docs line, if any.

## Traps, for traps.md

1. **A stand-in that answers at `Content-Length` hides the bytes sent past it.** 7.85.0 and both
   8.5.0 builds read a file part grown after `curl_mime_filedata` to its new end, and send it all:
   the mime probe's raw stand-in read the declared 1,291 or 1,309 bytes, answered 200, and logged
   the 2,000 more as garbage, and its tables, built from the body it framed, showed a whole 200.
   Node's parser read the same bytes as a second request and answered 400; over HTTP/2 it reset
   the stream, 92. Reproduced in both runs on F, O and G, each face (`probe-docker-{1,2}.log`,
   `after grown`), and in both of the mime probe's runs (`mime-files/results/docker-{1,2}.log`,
   case C-grown, `data_out=3291` and `garbage bytes=2000`). A check of what was sent reads what
   follows the body too.
2. **A server started after `exec 3> FIFO` holds fd 3 open:** with two servers each reading a FIFO
   the script holds, the second inherits the first's write end, so closing it never ends the
   first's stdin; `run-probe.sh`'s origin exited 143, its watchdog's kill, after every early run.
   Close the others in each child (`3>&-`). Reproduced twice by `trap-fd.sh`
   (`results/trap-fd-{1,2}.log`): A still runs 1 s after fd 3 closed, and ends with it in the
   control.

## How to rerun

From the repository's root, on the host; `W` is a `mktemp -d` directory under `build/m8s3/`:

```sh
W=$(mktemp -d build/m8s3/work.XXXXXX); R=.plans/research/m8/slice3
for t in main proto; do mkdir $W/$t; tar cf - --exclude=./build --exclude=./.git --exclude=./.plans/research . | (cd $W/$t && tar xf -); done
P=$PWD/$R; (cd $W/proto && patch -p1 < $P/proto.patch)
mkdir $W/probe; (cd $W/proto && tar cf - .) | (cd $W/probe && tar xf -); python3 $R/seam.py $W/probe
mkdir $W/probe/m8s3; cp $R/engine-probe.sps $R/run-probe.sh $W/probe/m8s3/; cp .plans/research/m8/mime-files/server.mjs $W/probe/m8s3/server-files.mjs
# item 2, twice each: lane X, lanes F, O, G and C, and the builds without mime
(cd $W/probe && taskset -c 12-17 scripts/guix-env sh m8s3/run-probe.sh guix-8.20.0 < /dev/null) > $R/results/probe-guix-8.20.0-1.log 2>&1
CPUS=6-11 sh $R/lanes.sh $W probe probe floor openssl gnutls current > $R/results/probe-docker-1.log 2>&1
CPUS=12-17 sh $R/lanes.sh $W probe probe nomime785 nomime823 -- load > $R/results/probe-nomime-1.log 2>&1
# the racing cell and the FIFO's timeout and stop, named alone, twice each
(cd $W/probe && taskset -c 12-17 scripts/guix-env sh m8s3/run-probe.sh guix-8.20.0 race fifo < /dev/null) > $R/results/races-guix-8.20.0-1.log 2>&1
CPUS=12-17 sh $R/lanes.sh $W probe probe floor openssl gnutls current -- race fifo > $R/results/races-docker-1.log 2>&1
# under the memory gate's Valgrind: lane X, then F and O
(cd $W/probe && taskset -c 12-17 scripts/guix-env sh -c 'VALGRIND=/tmp/m8s3-vg-guix.vg sh m8s3/run-probe.sh guix-8.20.0 load memory; cp /tmp/m8s3-vg-guix.vg m8s3/memory-guix-8.20.0.vg' < /dev/null) > $R/results/memory-guix-8.20.0.log 2>&1
CPUS=12-17 VALGRIND=memory sh $R/lanes.sh $W probe probe floor openssl -- load memory > $R/results/memory-docker.log 2>&1
# item 3: make test on the prototype (check-seam alone first, then make -o check-seam test)
mkdir $W/proto-guix-test; (cd $W/proto && tar cf - --exclude=./build .) | (cd $W/proto-guix-test && tar xf -)
(cd $W/proto-guix-test && { taskset -c 12-17 scripts/guix-env sh -c 'make deps check-seam; echo check-seam-exit=$?' < /dev/null; taskset -c 12-17 scripts/guix-env make -o check-seam test < /dev/null; }) > $R/results/test-proto-guix-8.20.0.log 2>&1
CPUS=6-11 TAG=proto sh $R/lanes.sh $W test proto floor openssl gnutls current > $R/results/test-proto-docker.log 2>&1
# the tables, and make test's failures classed
python3 $R/tables.py $R/results > $R/results/tables.md
python3 $R/maketest.py $R/results/test-proto-*.log > $R/results/maketest.md
sh $R/trap-fd.sh
```

A probe run takes 10 to 30 s a lane natively; a lane's `make test` 10 to 30 minutes.

## Files

| file | what it is |
|---|---|
| `proto.patch` | the prototype against `main` (bd54721) |
| `seam.py`, `seam.patch` | the probe's seam, and its diff against the prototype |
| `engine-probe.sps` | item 2 through the engine, every group |
| `run-probe.sh` | one lane: the PKI, the origin and the stand-in, the probe, natively or under the gate's Valgrind |
| `lanes.sh`, `lanes-in-docker.sh` | lanes F, O, G, C and the two builds without mime in Docker: `probe` and `test` |
| `tables.py`, `maketest.py` | the tables from the probe's logs; `make test`'s failures classed |
| `trap-fd.sh` | the second trap, reproduced |
| `results/probe-*.log` | item 2, runs 1 and 2; `results/engine-probe-runs12.sps`, the probe as they ran it |
| `results/races-*.log` | the `race` and `fifo` groups, twice each |
| `results/memory-*.log`, `results/*.vg` | under the memory gate's Valgrind, and Valgrind's own logs |
| `results/test-proto-*.log`, `results/maketest.md` | item 3 |
| `results/tables.md` | every table, every cell, and the runs compared |
| `results/trap-fd-{1,2}.log` | the second trap |
