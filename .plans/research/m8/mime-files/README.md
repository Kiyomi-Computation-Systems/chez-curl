# M8 research, probe 2: file parts, resends, lifetime, and a libcurl without mime

Measured 2026-11-06 for the M8 plan ([ADR-0038](../../../decisions/0038-m8s-scope.md): "M8 measures
first"), on `docs/m8-plan` at `fbc6fce`. It covers how libcurl reads a file part
(`curl_mime_filedata`), what it does when a mime body must go again inside one transfer, how a mime
handle lives and dies beside its easy handle, and what a libcurl configured `--disable-mime` answers.
It reports what libcurl does; it tests no chez-curl code. Probe 1 (`../`, another directory) measures
what a mime body puts on the wire, its headers and byte rules: this one names a part's bytes, its
filename and its framing only where a case's answer needs them.

Logs, every one kept: `results/docker-1.log` and `results/docker-2.log` (lanes F, O, G and C),
`results/guix-8.20.0-1.log` and `-2.log` (lane X), `results/nomime-1.log` and `-2.log` (the two builds
without mime), `results/races-docker.log.gz` and `results/races-guix.log.gz` (the racing cells, 20 runs
more on every lane), `results/nomime-build-7.85.0.log` and `-8.23.0.log` (the builds' whole output).
Below, "D1" is `docker-1.log`, "X1" `guix-8.20.0-1.log`, "N1" `nomime-1.log`, and so on. Every cell of
the tables at the end is computed from those logs by `summarize.mjs`; the findings cite the tables and,
where a line says more, the log.

## In short

1. **When a file part's file is read** (table 1). `curl_mime_filedata` only looks at the path: `stat`,
   and on 7.85.0 and 8.5.0 also `access(R_OK)`. Nothing touches the file at `MIMEPOST` or at
   `curl_multi_add_handle`. libcurl opens it with `fopen` inside `curl_multi_perform`, when the body
   first reaches the part, on the thread that calls perform (the probe's only thread). It reads it
   with `fread` over as many performs as the body takes (a 4 MiB part: 65 reads over 64 or 65
   performs) and closes it in the perform where the part ends, before the next part opens. Every new
   transfer of the same mime opens it again (R-when-again), and so does every resend (X-drop-file:
   `fopen` twice, no `fseek`). A resend that comes while the file is still open seeks it to 0 instead
   (X-drophead-big, X-refuse-head-big: one `fopen`, then `fseek(0)`, or `fseeko(0)` on 8.20.0 and
   8.23.0). A part that never reaches its end keeps its file open until `curl_mime_free`: C-grown
   closes at `mime_free` on 8.20.0 and 8.23.0.
2. **Missing at `curl_mime_filedata`: 26 at once, on every lane** (table 2, C-missing). What the part
   becomes then splits:
   - 7.85.0 and 8.5.0 keep it a file part of unknown size. The transfer goes chunked and fails 26 if
     the file is still missing, or sends the file if it has appeared since (C-missing-made: 200,
     the 1000 bytes made after the call).
   - 8.20.0 and 8.23.0 keep nothing: the part goes as an empty field with no filename, and the
     transfer answers 0/200 (D1, `[current-8.23.0] case C-missing` part lines: `name="upload"`,
     `len=0`).
3. **Unreadable (mode 000):** before the call, 26 on 7.85.0 and 8.5.0 (their `access` check) and 0
   on 8.20.0 and 8.23.0. After the call, or removed after it: 0 at the call on every lane. Either
   way the transfer fails 26 when it reaches the part, after the head and the parts before it went
   out: the server read the head and 243 or 255 bytes of the body, then the connection ended
   (C-removed, C-unreadable-*). The probe ran as uid 1000, never root (each lane's `node ... uid=`
   line).
4. **The size is the one `stat` saw at the call** (table 2).
   - **Grown** (1000 bytes at the call, 3000 at the transfer), every lane: the declared length
     holds, but libcurl reads past the old size into the new bytes, and they take the place of the
     part's end and the closing delimiter. The server read a whole body with no closing delimiter,
     the part's bytes the grown file's (`unterminated seed8(1054)`, 1048 on 7.85.0). The transfer
     answers 0/200: nothing tells the caller.
   - **Shrunk** (3000, then 1000): 7.85.0 and 8.5.0 send what there is and wait for the timeout
     (28 at the probe's 5 s); 8.20.0 and 8.23.0 fail at once, 26, "client mime read EOF fail, only
     1309/3309 of needed bytes read" (X1).
   - **Replaced** by a rename, same size: the new file's bytes go, 0/200.
5. **Paths that are not regular files** (table 3). Each answers 0 at the call, and its part has no
   size, so the body goes chunked:
   - **FIFO:** sent whole when a writer comes. libcurl's `fopen` blocks inside `curl_multi_perform`
     until one opens: one perform took 1.5 s in N-fifo-late, in each of 22 runs on every lane (1.7 s
     once, on O), and `TIMEOUT_MS` 500 could not end it; 28 came only after. A FIFO no one writes would hold the thread for ever (not
     run).
   - **Directory:** `fread` fails `EISDIR`, libcurl takes it for the end: an empty part, 0/200.
   - **`/dev/null`:** an empty part, 0/200.
   - **`/dev/stdin`**, stdin a pipe of 1200 bytes: libcurl reads the process's stdin to its end
     (`stdin-left=0`) and sends it, 0/200.
   - **`/proc/self/status`:** a regular file whose `st_size` is 0, so a part of length 0 with a
     Content-Length, and libcurl never opens it: an empty part, 0/200.
   - **A relative path** is kept as given and opened against the working directory at the
     transfer, not at the call. After a `chdir` to b, b's `rel.txt` went at a's size, unterminated as
     in C-grown, 0/200; after one to a directory without it, 26.
6. **Resends inside one transfer: libcurl rewinds and sends the whole body again, byte for byte,
   for data and regular-file parts, on every lane** (table 4). One mime keeps its boundary, so the
   FNV-1a of each whole body matched across attempts.
   - A **dead reused connection** (X-drop: read whole, closed unanswered; X-drophead: closed as the
     head came): two requests, the second on a new connection, whole.
   - **Digest:** the first request is libcurl's probe, Content-Length 0 with no body and no
     Content-Type; the body goes once, with the credentials. A stale nonce (X-stale) sends it twice,
     both whole and identical.
   - **HTTP/2 `REFUSED_STREAM`**, at the stream's end or its head: sent again whole, on a new
     connection.
   - **307 and 308 with `FOLLOWLOCATION` 1** (case 5): sent again whole to the hop.
   - **A caller's `Expect: 100-continue` answered 417 at the head:** the body goes once, after the
     417, on the same connection. Answered 417 after the body (EXPECT_100_TIMEOUT_MS 200): no resend;
     the transfer answers 0 with status 417.
   - **A FIFO cannot be rewound.** Every resend that needs bytes already read fails, 65 "Cannot
     rewind mime/post data" (56 on 7.85.0 over HTTP/2, X-refuse-*-pipe), and libcurl never opens the
     FIFO a second time. It survives only where nothing had been read: the 417 at the head and the
     Digest probe.
7. **A pooled connection the server closed while idle** (X-idle, 400 ms after the GET; 20 more runs
   each, all alike): 7.85.0, 8.5.0 and 8.20.0 see it dead and open another, one request. 8.23.0
   reuses it, the request dies ("Connection died, retrying a fresh connect"), and libcurl sends it
   again on a new connection: two heads, the file opened twice; a FIFO part fails 65 with no request
   reaching the server. At 1500 ms (X-idle1500) 8.23.0 checks it too: one request. This is ADR-0020's
   dead-connection trap, met by a mime.
8. **One racing cell: a reset while libcurl is inside a 4 MiB part** (X-drophead-big). It either
   resends (seek to 0, 200) or fails 55 "Send failure: Connection reset by peer", with no resend.
   Over the 2 main runs and 20 races: F 22 resends of 22; O 22 of 22; G 19 resends, 3 failures; X
   15 and 7; C 19 and 3 (C's two main runs both failed). No lane is shown never to fail: F and O
   only did not, 22 times.
9. **Lifetime, under Valgrind with the memory gate's options, on every lane** (table 6): 0 errors and
   no definite loss for every order: `curl_easy_cleanup` then `curl_mime_free`; free then cleanup;
   free while the done handle is still in its multi; `MIMEPOST` NULL, then free; a mime never
   attached, freed before or after its handle; and a free mid-transfer. So `curl_easy_cleanup` does
   not read a mime freed before it (L-free-then-cleanup, all five lanes). Natively, libcurl held 0
   bytes after every order. Two orders change the wire, though:
   - **freed after `MIMEPOST`, before the transfer:** a POST with Content-Length 0, no body and no
     Content-Type, answered 0/200;
   - **freed mid-transfer:** 7.85.0 and both 8.5.0 builds stop sending and wait for the timeout, 28;
     8.20.0 and 8.23.0 fail at once, 26 (the same under Valgrind).
10. **A mime made with one easy handle, attached to another** (table 7): 7.85.0 refuses it, 43,
    whether the first handle is alive or cleaned up, and the transfer then goes as a GET. 8.5.0 and
    later take it. `curl_mime_init(NULL)` is taken everywhere. A mime still attached to A is refused
    on B everywhere, 43. A mime sent on A, A cleaned up, then attached to B: 7.85.0 refuses it; both
    8.5.0 builds send the head with Content-Length 3258 and no body, and wait for the timeout, 28;
    8.20.0 and 8.23.0 send it whole. The same handle sending the same mime again works on every lane
    (R-when-again).
11. **Without mime** (table 8; N1, N2):
    - **8.23.0 `--disable-mime`** compiles stubs: `curl_mime_init` answers NULL, every setter 4
      (`CURLE_NOT_BUILT_IN`), `MIMEPOST` and `HTTPPOST` 48 (`CURLE_UNKNOWN_OPTION`), with NULL or
      with init's NULL alike, and `curl_formadd` 7 (`CURL_FORMADD_DISABLED`). The transfer then goes
      as a GET.
    - **7.85.0 `--disable-mime`, built as the floor lane is** (SMTP and IMAP on), **keeps the whole
      mime API working**: `curl_mime_init` gives a mime, every setter and `MIMEPOST` answer 0, and the
      transfer is a POST with Content-Length 0, no body and no Content-Type, answered 0/200. Only
      `curl_formadd` tells: 7. In source, 7.85.0 compiles `mime.c` when HTTP and mime are both on
      or when SMTP or IMAP is on (`lib/mime.c:34`), and leaves out only HTTP's use of it
      (`lib/http.c:2317`, `:2481`); 8.5.0 and later need mime on (`lib/mime.c:34`). ADR-0038's
      Context, "a libcurl configured `--disable-mime` keeps every `curl_mime_*` symbol as a stub",
      holds for 8.23.0 and not for 7.85.0 as the floor is built.
    - Both builds define every `curl_mime_` and `curl_form` symbol (`nm -D`), both find `MIMEPOST`
      and `MIME_OPTIONS` by `curl_easy_option_by_name`, and each one's features word is its mime
      build's: 0x5129c29d and 0x5129028d (D-calls' `version` line). No bit names mime.

## Surprises

- The part a failed `curl_mime_filedata` leaves behind is sent: an empty field on 8.20.0 and 8.23.0,
  or, on 7.85.0 and 8.5.0, a file that appears later (finding 2).
- A file that grows between the call and its read corrupts the body and the transfer answers 200
  (finding 4); a relative path read after a `chdir` does the same with another file.
- A FIFO blocks the engine's thread in `fopen`, past any timeout (finding 5).
- `/dev/stdin` reads the process's own stdin; a directory, `/dev/null` and a `/proc` file send
  empty parts, all with 200.
- 8.23.0's reuse of a dead pooled connection makes libcurl resend a mime, and fail one with a FIFO
  part before any byte reaches the server (finding 7).
- A freed mime makes a POST with no body and a 200 (finding 9), and 7.85.0 without mime does the same
  for every mime while answering 0 to every call (finding 11).
- On 8.5.0 a mime re-attached to a second handle after its first transfer stalls to the timeout
  (finding 10). The source of that was not read.

## What the M8 plan must decide from these

These are the questions the measurements put; the probe recommends nothing.

- **`curl_mime_filedata`'s answer.** It is 26 for a missing path everywhere, and for an unreadable one
  on 7.85.0 and 8.5.0 alone; whatever follows a 26 still sends something (finding 2). Whether a
  non-zero answer refuses the transfer, and by what reason.
- **Which paths a file part takes, and when they are checked.** libcurl opens the path at the
  transfer, relative to the working directory then, and opens a FIFO, a device, a directory or
  `/dev/stdin` without complaint (findings 1, 5). Whether chez-curl requires an absolute path, or
  resolves one at submit; whether it requires a regular file, checked where (at submit, on the
  engine's thread before the call), knowing that the file can change between that check and libcurl's
  `fopen`; and what a part may do to the engine's thread (a FIFO's `fopen` blocks it).
- **A file that changes during the transfer.** The size is fixed at the call, a growth corrupts the
  body silently, a shrink fails 26 or stalls to the timeout by version (finding 4). Whether the docs
  say so alone, or something checks.
- **Resends.** libcurl resends a whole mime inside one transfer after a dead reused connection, an
  auth round, a REFUSED_STREAM, a 417 at the head and its own follow (finding 6), which ADR-0032's
  "at most once" rule for streamed bodies does not cover: what the plan promises about a multipart
  body sent twice, and how a test counts attempts (the X- rows count them at the server).
- **The mime's lifetime as a counted native kind.** Freed only once its transfer has ended: every
  order after that is clean, before it is not (finding 9). Which order the engine uses (the two
  orders after the end are both clean under Valgrind), and that the high level's retries and
  redirect hops build a fresh mime for each transfer: a mime made with another handle is refused on
  7.85.0, and a used one stalls on 8.5.0 (finding 10).
- **A libcurl without mime.** No feature bit, no missing symbol and no option lookup shows it. On
  8.23.0 `curl_mime_init` answers NULL; on 7.85.0 nothing answers wrong but `curl_formadd`, 7, and
  the transfer silently drops the body (finding 11). 8.5.0 and later can also be built with the form
  API alone disabled (`--disable-form-api`, in 8.5.0's, 8.7.1's, 8.20.0's and 8.23.0's
  `configure.ac`, not in 7.85.0's), where `curl_formadd` would answer 7 and mime would work: not built
  here. How the load or the first multipart submit tells, and refuses.
- **The hatch.** `FOLLOWLOCATION` set by a caller makes libcurl resend the body on 307 and 308
  (case 5), and `EXPECT_100_TIMEOUT_MS` with a caller's `Expect` decides whether a 417 is resent.

## What was not measured, and why

- **The Mac** (Apple's 8.7.1): `mac.sh` is written and `sh -n` clean, not run; the maintainer runs it.
  On the Mac no `fs` lines print (the file watch interposes glibc's calls, Linux alone), N-proc skips,
  and no Valgrind runs.
- **A FIFO with no writer at all:** it would hold the probe's thread in `fopen` until its alarm; N-fifo-late
  shows the block, 1.5 s, on every lane.
- **The form API disabled alone, and 8.5.0, 8.7.1 or 8.20.0 without mime:** one build per brief, two
  were made (7.85.0 and 8.23.0), because 7.85.0's source showed its `--disable-mime` keeps the API.
- **Linux arm64 and macOS amd64:** no runner here.
- **HTTP/2 over TLS:** the REFUSED_STREAM cases run on h2c (prior knowledge); libcurl's resend path is
  the same over TLS, but that was not run.
- **Where libcurl's stall on 8.5.0's re-attached mime comes from** (finding 10): measured, its source
  not read.
- **Why a reset inside a big part sometimes fails 55 rather than resending** (finding 8): counted, not
  explained.

## What was run

`probe.c` drives libcurl's multi interface in M7's probes' loop, which mirrors chez-curl's engine turn:
`curl_multi_add_handle`, `curl_multi_perform`, `curl_multi_info_read` (a done transfer removed at once,
but where a case keeps it), then `curl_multi_poll` for at most 1000 ms; waits between transfers are
engine turns too. Each transfer gets the engine's options (`src/curl/private/transfer.sls`,
`set-transfer-options!`): `PROTOCOLS_STR` and `REDIR_PROTOCOLS_STR` "http,https", `NOSIGNAL` 1,
`MAXREDIRS` 30, `QUICK_EXIT` 1 (by number), `ERRORBUFFER`, `PROXY` "", `FOLLOWLOCATION` 0, and
`HTTPHEADER` "Expect:", the engine's blank, unless a case names its own Expect. It does not blank
`Content-Type`, which would take away the multipart type and its boundary (probe 1's question). It sets
`TIMEOUT_MS` 10000 (5000 in the C- cases, 500 in N-fifo-late) as its own bound. Its header comment
lists the rest. Each case is one process; the run's `results/` lines name it `case NAME`.

On Linux the probe interposes `fopen`, `fopen64`, `open`, `open64`, `openat`, `openat64`,
`__open_2`, `__open64_2`, `stat`, `stat64`, `access`, `fread`, `fseek`, `fseeko`, `fseeko64` and
`fclose`, and prints an `fs` line for each call made while it is inside a libcurl call, naming the
call (`filedata`, `mimepost`, `add`, `perform`, `remove`, `easy_cleanup`, `mime_free`), the
`curl_multi_perform` it was in (`pf`), and the thread. Under Valgrind (`VALGRIND` set) the L-, M- and
R-when cases run again with the memory gate's options (ADR-0014, the Makefile's `test-memory`),
`timeout` outside Valgrind, libcurl on plain `malloc`. Two switches came after the main runs, for the
racing cells alone: `docker.sh`'s `REPEAT` and `run.sh`'s `VG_CASES=none`; unset, the scripts do what
they did for the main runs.

`server.mjs`, Node's standard library alone, has a raw HTTP/1.1 face parsed by hand (keep-alive,
framing by Content-Length or chunked, the routes the cases need), an h2c face (`node:http2`, prior
knowledge) and a control face. It logs each request's head bytes, each body's length and FNV-1a 32,
and each multipart part: its headers, its length, its hash, and its "seed" when its bytes are the
probe's blob of that seed (byte i is 'a' + (i + seed) mod 26), so a part that is another file's bytes,
or a file's first bytes, is named. A part the body ends inside is "unterminated". Its header comment
lists the routes.

The lanes, each run twice (and the racing cells 20 times more):

| Lane | libcurl (as the logs' `version` lines name it) | TLS | Node | Valgrind | Where |
|---|---|---|---|---|---|
| F | `build/e1/ci/curl-floor`, 7.85.0, its own headers | OpenSSL 3.0.13 | 20.10.0 | 3.22.0 | Docker |
| O | Ubuntu's `libcurl.so.4`, 8.5.0 (`8.5.0-2ubuntu10.16`) | OpenSSL 3.0.13 | 24.18.0 | 3.22.0 | Docker |
| G | Ubuntu's `libcurl-gnutls.so.4`, 8.5.0 (`8.5.0-2ubuntu10.16`), `libcurl4-openssl-dev`'s headers | GnuTLS 3.8.3 | 24.18.0 | 3.22.0 | Docker |
| X | the Guix profile's 8.20.0 | GnuTLS 3.8.13 | 24.18.0 | 3.27.0, the gate's suppression | `scripts/guix-env` |
| C | `build/verify/c823/lane1/curl-current`, 8.23.0, its own headers | OpenSSL 3.0.13 | 24.18.0 | 3.22.0 | Docker |
| no-mime 7.85.0 | `build/m8/mime-files/nomime-7.85.0` (below) | OpenSSL 3.0.13 | 24.18.0 | — | Docker |
| no-mime 8.23.0 | `build/m8/mime-files/nomime-8.23.0` (below) | OpenSSL 3.0.13 | 24.18.0 | — | Docker |

Docker is `ubuntu:24.04` (`sha256:68ee2200…`), `--network none` after one fetch of the packages into
`build/m8/mime-files/apt`, `--cpuset-cpus 6-11`, `--rm`; the Guix lane runs under `taskset -c 6-11`.
Every lane runs as uid 1000. The Ubuntu packages are M7's versions (`docker-1.log`'s `package`
lines).

The builds without mime are `scripts/ci/build-curl.sh`, unchanged, with one extra `./configure` flag,
`--disable-mime`, for 7.85.0 and for `--current` (8.23.0), in Docker with `--network none`. The script
fetches its tarball with `curl`; `nomime.sh` puts a stand-in `curl` first on `PATH` that copies the
tarball of that name from `build/verify/current`, and the script checks it against the sha256 it pins,
as it checks a download (`results/nomime-build-*.log`, first line and the build's `exit 0`).
`./configure` printed "whether to support the MIME API... no" for both, and 8.23.0's "whether to
support the form API... no" too (`nomime-build-7.85.0.log:569`, `nomime-build-8.23.0.log:515`, `:517`).

### The cases

| Case | What it does |
|---|---|
| R-when | a data part and two file parts (3000 and 2000 bytes); every step's file calls; then the same easy handle and mime sent again |
| R-big | a 4 MiB file part: its reads across performs |
| C-missing | `curl_mime_filedata` on a path that does not exist; then the transfer |
| C-missing-made | the same, and a 1000-byte file made at the path before the transfer |
| C-removed | 1000 bytes at the call, unlinked before the transfer |
| C-unreadable-first, -later | mode 000 before the call, or after it |
| C-grown, C-shrunk | 1000 bytes at the call, 3000 at the transfer; 3000, then 1000 |
| C-replaced | another 1000-byte file renamed over it before the transfer |
| N-fifo | a FIFO, its writer (a child) writing 5000 bytes at once |
| N-fifo-late | the same, the writer opening it 1500 ms in; `TIMEOUT_MS` 500 |
| N-dir, N-devnull | a directory; `/dev/null` |
| N-stdin | `/dev/stdin`, stdin a pipe holding 1200 bytes, written and closed; what is left of it after |
| N-proc | `/proc/self/status`, a regular file of `st_size` 0 |
| N-relative | `rel.txt`, relative, in directory a: sent there, after a `chdir` to b, and after one to a directory without it |
| X-417-K | Expect: 100-continue named; 417 as the head arrives, once, the connection kept |
| X-late417-K | the same, 417 after the whole body (`EXPECT_100_TIMEOUT_MS` 200) |
| X-idle-K, X-idle1500-file | a GET; the server closes that connection 100 ms after; the mime POST 400 (or 1500) ms later |
| X-drop-K, X-drophead-K | a GET; the POST on its connection, read whole, or only its head, then closed unanswered |
| X-digest-K, X-stale-K | `HTTPAUTH` Digest, `USERNAME`, `PASSWORD`; X-stale answers the first valid response 401 stale=true |
| X-refuse-end-K, X-refuse-head-K | h2c; the first stream reset REFUSED_STREAM once its body ended, or as its headers arrived |
| F-307-K, F-308-K | `FOLLOWLOCATION` 1; 307 or 308 to /sink after the whole body |
| L-cleanup-then-free, L-free-then-cleanup, L-free-in-multi, L-null-then-free | after one transfer of a data and a file part: the orders their names say |
| L-free-before-transfer | the mime freed after `MIMEPOST`, before the transfer |
| L-never-attached | a mime never attached, freed before its easy handle's cleanup, and a second after it |
| L-free-midflight | an 8 MiB file part to a server that pauses reading 1500 ms; freed 300 ms in |
| M-other-easy, M-other-gone, M-null-easy | made with A (alive, or cleaned up), or with NULL; attached to B, sent |
| M-twice | attached to A, then to B |
| M-after-cleanup | attached to A, sent, A cleaned up, then attached to B and sent |
| D-calls | the mime and form calls, their answers, the features word, and two transfers: init's mime, and `MIMEPOST` NULL alone |

K is the mime's kind: `data` ("field" and a 3000-byte data part), `file` (a 3000-byte file), `pipe` (a
FIFO whose writer writes 3000 bytes once, then answers a second open, if one comes, with other bytes),
and `big` (a 4 MiB file) for X-drophead and X-refuse-head.

### Rerun

From the repository's root; each takes a few minutes or less.

```sh
# lane X, in the container, pinned from the host
taskset -c 6-11 scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL VALGRIND=valgrind sh .plans/research/m8/mime-files/run.sh guix-8.20.0' < /dev/null > .plans/research/m8/mime-files/results/guix-8.20.0-N.log 2>&1
# lanes F, O, G and C, in Docker (fetches the apt cache once, then --network none)
sh .plans/research/m8/mime-files/docker.sh > .plans/research/m8/mime-files/results/docker-N.log 2>&1
# the builds without mime, and D-calls and R-when on them (after docker.sh's fetch)
sh .plans/research/m8/mime-files/nomime.sh > .plans/research/m8/mime-files/results/nomime-N.log 2>&1
# the racing cells, 20 runs on each lane
CASES="X-drophead-big X-refuse-head-big X-drophead-data X-drophead-file X-drophead-pipe X-idle-data X-idle-file X-idle-pipe X-idle1500-file N-fifo-late" \
  VG_CASES=none REPEAT=20 sh .plans/research/m8/mime-files/docker.sh > .plans/research/m8/mime-files/results/races-docker.log 2>&1
taskset -c 6-11 scripts/guix-env sh -c 'c="X-drophead-big X-refuse-head-big X-drophead-data X-drophead-file X-drophead-pipe X-idle-data X-idle-file X-idle-pipe X-idle1500-file N-fifo-late"; k=1; while [ $k -le 20 ]; do CASES="$c" CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m8/mime-files/run.sh guix-8.20.0-run$k; k=$((k+1)); done' < /dev/null > .plans/research/m8/mime-files/results/races-guix.log 2>&1
gzip -9 .plans/research/m8/mime-files/results/races-docker.log .plans/research/m8/mime-files/results/races-guix.log
# the Mac, by the maintainer
NODE="$(asdf which node)" sh .plans/research/m8/mime-files/mac.sh
# the tables, from the logs (add results/mac-8.7.1.log once it exists)
scripts/guix-env sh -c 'node .plans/research/m8/mime-files/summarize.mjs .plans/research/m8/mime-files/results/docker-1.log .plans/research/m8/mime-files/results/docker-2.log .plans/research/m8/mime-files/results/guix-8.20.0-1.log .plans/research/m8/mime-files/results/guix-8.20.0-2.log .plans/research/m8/mime-files/results/nomime-1.log .plans/research/m8/mime-files/results/nomime-2.log' < /dev/null
scripts/guix-env sh -c 'node .plans/research/m8/mime-files/summarize.mjs --count .plans/research/m8/mime-files/results/races-docker.log.gz .plans/research/m8/mime-files/results/races-guix.log.gz' < /dev/null
```

`results/shakedown/` holds the first full run on each lane (gzip'd), made before the server named a
part's seed and before the `big` cases existed; no table reads it.

## The tables

Generated by `summarize.mjs` from the two runs of each lane and of each build without mime. A cell
whose two runs differ prints both, "run 1 ‖ run 2", and is listed under its table.

### 1. When and where libcurl reads a file part

Each cell: the step of each file call on the part's file, from the probe's `fs` lines (Linux alone): `stat` at `curl_mime_filedata`, the first `fopen` and the `curl_multi_perform` it ran in (#pf), each `fclose`; `tid` main is the thread that called libcurl. R-when: two file parts (when1, when2), then the same easy handle and mime sent again (the second fopen pair). R-big: a 4 MiB part, its `fread` count and the performs they spread over. X-drop-file: the opens of one transfer that libcurl resent. C-grown: where the grown file's `fclose` ran.

| Case | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 | no-mime 7.85.0 | no-mime 8.23.0 |
|---|---|---|---|---|---|---|---|
| R-when | when1: stat@filedata access@filedata; fopen@perform#1 fopen@perform#5; fclose@perform#1 fclose@perform#5; when2: fopen#2 fclose#2 fopen#6 fclose#6; tid=main | when1: stat@filedata access@filedata; fopen@perform#2 fopen@perform#5; fclose@perform#2 fclose@perform#5; when2: fopen#3 fclose#3 fopen#6 fclose#6; tid=main | when1: stat@filedata access@filedata; fopen@perform#2 fopen@perform#5; fclose@perform#2 fclose@perform#5; when2: fopen#3 fclose#3 fopen#6 fclose#6; tid=main | when1: stat@filedata; fopen@perform#2 fopen@perform#4; fclose@perform#2 fclose@perform#4; when2: fopen#2 fclose#2 fopen#4 fclose#4; tid=main | when1: stat@filedata; fopen@perform#2 fopen@perform#4; fclose@perform#2 fclose@perform#4; when2: fopen#2 fclose#2 fopen#4 fclose#4; tid=main | when1: stat@filedata access@filedata; no fopen; no fclose; when2: no fopen; tid=main | when1: no stat; no fopen; no fclose; when2: no fopen; tid=- |
| R-big | fopen@perform; 65 freads over 65 performs; fclose@perform; 0/200 | fopen@perform; 65 freads over 65 performs; fclose@perform; 0/200 | fopen@perform; 65 freads over 65 performs; fclose@perform; 0/200 | fopen@perform; 65 freads over 64 performs; fclose@perform; 0/200 | fopen@perform; 65 freads over 64 performs; fclose@perform; 0/200 | — | — |
| X-drop-file | fopen 2x (#5 #6); no fseek; 2 attempts | fopen 2x (#5 #7); no fseek; 2 attempts | fopen 2x (#5 #7); no fseek; 2 attempts | fopen 2x (#5 #7); no fseek; 2 attempts | fopen 2x (#5 #7); no fseek; 2 attempts | — | — |
| C-grown | fclose@perform | fclose@perform | fclose@perform | fclose@mime_free | fclose@mime_free | — | — |

Runs: F 7.85.0 docker-1.log[floor-7.85.0], docker-2.log[floor-7.85.0]; O 8.5.0 docker-1.log[ubuntu-openssl-8.5.0], docker-2.log[ubuntu-openssl-8.5.0]; G 8.5.0 docker-1.log[ubuntu-gnutls-8.5.0], docker-2.log[ubuntu-gnutls-8.5.0]; X 8.20.0 guix-8.20.0-1.log[guix-8.20.0], guix-8.20.0-2.log[guix-8.20.0]; C 8.23.0 docker-1.log[current-8.23.0], docker-2.log[current-8.23.0]; no-mime 7.85.0 nomime-1.log[nomime-7.85.0], nomime-2.log[nomime-7.85.0]; no-mime 8.23.0 nomime-1.log[nomime-8.23.0], nomime-2.log[nomime-8.23.0].

### 2. A file that changes between `curl_mime_filedata` and the transfer

Each cell: `curl_mime_filedata`'s answer; the transfer's code/status; what the server read (Content-Length or chunked, and the bytes it got: "(partial)" when the connection ended first); the file part as received, named by the probe's `expect` line its FNV-1a matches (`other` when none does; "unterminated" when the body ended without the part's closing delimiter). C-missing: no file. C-missing-made: none at `filedata`, 1000 bytes made after. C-removed: unlinked after. C-unreadable-first: mode 000 before; -later: after. C-grown: 1000 bytes at `filedata`, 3000 at the transfer; C-shrunk: 3000, then 1000; C-replaced: another 1000-byte file renamed over it. The probe runs as the host's uid, never root (run.sh prints it).

| Case | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 |
|---|---|---|---|---|---|
| C-missing | rc 26; 26; chunked got 243(partial); part: none | rc 26; 26; chunked got 255(partial); part: none | rc 26; 26; chunked got 255(partial); part: none | rc 26; 0/200; CL 260 got 260; part: empty(0) | rc 26; 0/200; CL 260 got 260; part: empty(0) |
| C-missing-made | rc 26; 0/200; chunked got 1291; part: upload-made(1000) | rc 26; 0/200; chunked got 1309; part: upload-made(1000) | rc 26; 0/200; chunked got 1309; part: upload-made(1000) | rc 26; 0/200; CL 260 got 260; part: empty(0) | rc 26; 0/200; CL 260 got 260; part: empty(0) |
| C-removed | rc 0; 26; CL 1291 got 243(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none |
| C-unreadable-first | rc 26; 26; chunked got 243(partial); part: none | rc 26; 26; chunked got 255(partial); part: none | rc 26; 26; chunked got 255(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none |
| C-unreadable-later | rc 0; 26; CL 1291 got 243(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none | rc 0; 26; CL 1309 got 255(partial); part: none |
| C-grown | rc 0; 0/200; CL 1291 got 1291; part: unterminated seed8(1048) | rc 0; 0/200; CL 1309 got 1309; part: unterminated seed8(1054) | rc 0; 0/200; CL 1309 got 1309; part: unterminated seed8(1054) | rc 0; 0/200; CL 1309 got 1309; part: unterminated seed8(1054) | rc 0; 0/200; CL 1309 got 1309; part: unterminated seed8(1054) |
| C-shrunk | rc 0; 28; CL 3291 got 1291(partial); part: none | rc 0; 28; CL 3309 got 1309(partial); part: none | rc 0; 28; CL 3309 got 1309(partial); part: none | rc 0; 26; CL 3309 got 1309(partial); part: none | rc 0; 26; CL 3309 got 1309(partial); part: none |
| C-replaced | rc 0; 0/200; CL 1291 got 1291; part: upload-replaced(1000) | rc 0; 0/200; CL 1309 got 1309; part: upload-replaced(1000) | rc 0; 0/200; CL 1309 got 1309; part: upload-replaced(1000) | rc 0; 0/200; CL 1309 got 1309; part: upload-replaced(1000) | rc 0; 0/200; CL 1309 got 1309; part: upload-replaced(1000) |

Runs: F 7.85.0 docker-1.log[floor-7.85.0], docker-2.log[floor-7.85.0]; O 8.5.0 docker-1.log[ubuntu-openssl-8.5.0], docker-2.log[ubuntu-openssl-8.5.0]; G 8.5.0 docker-1.log[ubuntu-gnutls-8.5.0], docker-2.log[ubuntu-gnutls-8.5.0]; X 8.20.0 guix-8.20.0-1.log[guix-8.20.0], guix-8.20.0-2.log[guix-8.20.0]; C 8.23.0 docker-1.log[current-8.23.0], docker-2.log[current-8.23.0].

### 3. Paths that are not regular files

Each cell: `curl_mime_filedata`'s answer; code/status; the framing the server read and the bytes it got; the file part as received (by `expect` name; `other` when no `expect` matches; `none` when the body held no second part). N-fifo-late: the longest `curl_multi_perform` and the transfer's end, in ms (the writer opens the FIFO 1500 ms in; TIMEOUT_MS 500). N-stdin: `stdin-left`, the bytes of the pipe left after the transfer. N-relative-*: `rel.txt`, relative, given in directory a (1000 bytes, `upload-a`); the transfer then runs there (stay), after a chdir to b (1500 bytes, `upload-b`), or after one to a directory with none.

| Case | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 |
|---|---|---|---|---|---|
| N-fifo | rc 0; 0/200; chunked got 5299; part: upload(5000) [filename fifo, application/octet-stream] | rc 0; 0/200; chunked got 5317; part: upload(5000) [filename fifo, application/octet-stream] | rc 0; 0/200; chunked got 5317; part: upload(5000) [filename fifo, application/octet-stream] | rc 0; 0/200; chunked got 5317; part: upload(5000) [filename fifo, application/octet-stream] | rc 0; 0/200; chunked got 5317; part: upload(5000) [filename fifo, application/octet-stream] |
| N-fifo-late | rc 0; 28; chunked got 5299(partial); part: none; longest perform 1.5 s, end at 1.5 s | rc 0; 28; chunked got 5317(partial); part: none; longest perform 1.5 s, end at 1.5 s | rc 0; 28; chunked got 5317(partial); part: none; longest perform 1.5 s, end at 1.5 s | rc 0; 28; chunked got 5317(partial); part: none; longest perform 1.5 s, end at 1.5 s | rc 0; 28; chunked got 5317(partial); part: none; longest perform 1.5 s, end at 1.5 s |
| N-dir | rc 0; 0/200; chunked got 299; part: empty(0) [filename adir, application/octet-stream] | rc 0; 0/200; chunked got 317; part: empty(0) [filename adir, application/octet-stream] | rc 0; 0/200; chunked got 317; part: empty(0) [filename adir, application/octet-stream] | rc 0; 0/200; chunked got 317; part: empty(0) [filename adir, application/octet-stream] | rc 0; 0/200; chunked got 317; part: empty(0) [filename adir, application/octet-stream] |
| N-devnull | rc 0; 0/200; chunked got 299; part: empty(0) [filename null, application/octet-stream] | rc 0; 0/200; chunked got 317; part: empty(0) [filename null, application/octet-stream] | rc 0; 0/200; chunked got 317; part: empty(0) [filename null, application/octet-stream] | rc 0; 0/200; chunked got 317; part: empty(0) [filename null, application/octet-stream] | rc 0; 0/200; chunked got 317; part: empty(0) [filename null, application/octet-stream] |
| N-stdin | rc 0; 0/200; chunked got 1500; part: upload(1200) [filename stdin, application/octet-stream]; stdin-left=0 | rc 0; 0/200; chunked got 1518; part: upload(1200) [filename stdin, application/octet-stream]; stdin-left=0 | rc 0; 0/200; chunked got 1518; part: upload(1200) [filename stdin, application/octet-stream]; stdin-left=0 | rc 0; 0/200; chunked got 1518; part: upload(1200) [filename stdin, application/octet-stream]; stdin-left=0 | rc 0; 0/200; chunked got 1518; part: upload(1200) [filename stdin, application/octet-stream]; stdin-left=0 |
| N-proc | rc 0; 0/200; CL 301 got 301; part: empty(0) [filename status, application/octet-stream] | rc 0; 0/200; CL 319 got 319; part: empty(0) [filename status, application/octet-stream] | rc 0; 0/200; CL 319 got 319; part: empty(0) [filename status, application/octet-stream] | rc 0; 0/200; CL 319 got 319; part: empty(0) [filename status, application/octet-stream] | rc 0; 0/200; CL 319 got 319; part: empty(0) [filename status, application/octet-stream] |
| N-relative-stay | rc 0; 0/200; CL 1288 got 1288; part: upload-a(1000) [filename rel.txt, text/plain] | rc 0; 0/200; CL 1306 got 1306; part: upload-a(1000) [filename rel.txt, text/plain] | rc 0; 0/200; CL 1306 got 1306; part: upload-a(1000) [filename rel.txt, text/plain] | rc 0; 0/200; CL 1306 got 1306; part: upload-a(1000) [filename rel.txt, text/plain] | rc 0; 0/200; CL 1306 got 1306; part: upload-a(1000) [filename rel.txt, text/plain] |
| N-relative-to-b | rc 0; 0/200; CL 1288 got 1288; part: unterminated seed21(1048) [filename rel.txt, text/plain] | rc 0; 0/200; CL 1306 got 1306; part: unterminated seed21(1054) [filename rel.txt, text/plain] | rc 0; 0/200; CL 1306 got 1306; part: unterminated seed21(1054) [filename rel.txt, text/plain] | rc 0; 0/200; CL 1306 got 1306; part: unterminated seed21(1054) [filename rel.txt, text/plain] | rc 0; 0/200; CL 1306 got 1306; part: unterminated seed21(1054) [filename rel.txt, text/plain] |
| N-relative-to-none | rc 0; 26; CL 1288 got 240(partial); part: none | rc 0; 26; CL 1306 got 252(partial); part: none | rc 0; 26; CL 1306 got 252(partial); part: none | rc 0; 26; CL 1306 got 252(partial); part: none | rc 0; 26; CL 1306 got 252(partial); part: none |

Runs: F 7.85.0 docker-1.log[floor-7.85.0], docker-2.log[floor-7.85.0]; O 8.5.0 docker-1.log[ubuntu-openssl-8.5.0], docker-2.log[ubuntu-openssl-8.5.0]; G 8.5.0 docker-1.log[ubuntu-gnutls-8.5.0], docker-2.log[ubuntu-gnutls-8.5.0]; X 8.20.0 guix-8.20.0-1.log[guix-8.20.0], guix-8.20.0-2.log[guix-8.20.0]; C 8.23.0 docker-1.log[current-8.23.0], docker-2.log[current-8.23.0].

### 4 and 5. Resends inside one transfer, and libcurl's own follow

Each cell: code/status (with libcurl's error buffer when the code is not 0); the requests the server logged for the transfer's tag (and, for F-, its hop's), on how many connections, each as the body bytes it read and how it ended when not 200 (417, 401, 307, 308, drop@body or drop@head: closed unanswered, RST@head or RST@end: RST_STREAM REFUSED_STREAM, none: no answer before the connection went); whether the bodies of more than one non-empty request were byte-identical (FNV-1a of the whole body: one mime keeps its boundary); then the client's own count: the request heads libcurl sent (CURLINFO_HEADER_OUT) and the body bytes it sent after each (CURLINFO_DATA_OUT); for file, big and pipe parts, how many times libcurl opened the file and each `fseek` it made on it; for pipe, each file part the server received, by name (`upload` is the FIFO's first content, seed 3; a second open's content is seed 25, 103 mod 26). X-417: Expect: 100-continue named, 417 at the head, once. X-late417: the same, but 417 after the whole body (EXPECT_100_TIMEOUT_MS 200). X-idle: a GET, the server closes that connection 100 ms after it, the POST 400 ms later (X-idle1500: 1500 ms). X-drop: a GET, then the POST on that connection, read whole and closed unanswered; X-drophead: closed as its head arrived. X-digest: Digest; X-stale: the first valid response answered 401 stale=true. X-refuse-*: h2c, the first stream refused at its headers or at its end. F-307, F-308: FOLLOWLOCATION 1, the code after the whole body. The big kind is a 4 MiB file part, so that the resend comes while libcurl is inside it. The pipe kind is a FIFO whose writer writes once, then answers any second open with another content.

| Case | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 |
|---|---|---|---|---|---|
| X-417-data | 0/200; server: 2 req on 1 conn: -→417, 3240; client: 2 heads, data_out 0,3240 | 0/200; server: 2 req on 1 conn: -→417, 3258; client: 2 heads, data_out 0,3258 | 0/200; server: 2 req on 1 conn: -→417, 3258; client: 2 heads, data_out 0,3258 | 0/200; server: 2 req on 1 conn: -→417, 3258; client: 2 heads, data_out 0,3258 | 0/200; server: 2 req on 1 conn: -→417, 3258; client: 2 heads, data_out 0,3258 |
| X-417-file | 0/200; server: 2 req on 1 conn: -→417, 3287; client: 2 heads, data_out 0,3287; fopen 1x | 0/200; server: 2 req on 1 conn: -→417, 3305; client: 2 heads, data_out 0,3305; fopen 1x | 0/200; server: 2 req on 1 conn: -→417, 3305; client: 2 heads, data_out 0,3305; fopen 1x | 0/200; server: 2 req on 1 conn: -→417, 3305; client: 2 heads, data_out 0,3305; fopen 1x | 0/200; server: 2 req on 1 conn: -→417, 3305; client: 2 heads, data_out 0,3305; fopen 1x |
| X-417-pipe | 0/200; server: 2 req on 1 conn: -→417, 3299; client: 2 heads, data_out 0,3311; fopen 1x; file parts received upload(3000) | 0/200; server: 2 req on 1 conn: -→417, 3317; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) | 0/200; server: 2 req on 1 conn: -→417, 3317; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) | 0/200; server: 2 req on 1 conn: -→417, 3317; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) | 0/200; server: 2 req on 1 conn: -→417, 3317; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) |
| X-late417-data | 0/417; server: 1 req on 1 conn: 3240→417; client: 1 heads, data_out 3240 | 0/417; server: 1 req on 1 conn: 3258→417; client: 1 heads, data_out 3258 | 0/417; server: 1 req on 1 conn: 3258→417; client: 1 heads, data_out 3258 | 0/417; server: 1 req on 1 conn: 3258→417; client: 1 heads, data_out 3258 | 0/417; server: 1 req on 1 conn: 3258→417; client: 1 heads, data_out 3258 |
| X-late417-file | 0/417; server: 1 req on 1 conn: 3287→417; client: 1 heads, data_out 3287; fopen 1x | 0/417; server: 1 req on 1 conn: 3305→417; client: 1 heads, data_out 3305; fopen 1x | 0/417; server: 1 req on 1 conn: 3305→417; client: 1 heads, data_out 3305; fopen 1x | 0/417; server: 1 req on 1 conn: 3305→417; client: 1 heads, data_out 3305; fopen 1x | 0/417; server: 1 req on 1 conn: 3305→417; client: 1 heads, data_out 3305; fopen 1x |
| X-late417-pipe | 0/417; server: 1 req on 1 conn: 3299→417; client: 1 heads, data_out 3311; fopen 1x; file parts received upload(3000) | 0/417; server: 1 req on 1 conn: 3317→417; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 0/417; server: 1 req on 1 conn: 3317→417; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 0/417; server: 1 req on 1 conn: 3317→417; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 0/417; server: 1 req on 1 conn: 3317→417; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) |
| X-idle-data | 0/200; server: 1 req on 1 conn: 3240; client: 1 heads, data_out 3240 | 0/200; server: 1 req on 1 conn: 3258; client: 1 heads, data_out 3258 | 0/200; server: 1 req on 1 conn: 3258; client: 1 heads, data_out 3258 | 0/200; server: 1 req on 1 conn: 3258; client: 1 heads, data_out 3258 | 0/200; server: 1 req on 1 conn: 3258; client: 2 heads, data_out 3258,3258 |
| X-idle-file | 0/200; server: 1 req on 1 conn: 3287; client: 1 heads, data_out 3287; fopen 1x | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x | 0/200; server: 1 req on 1 conn: 3305; client: 2 heads, data_out 3305,3305; fopen 2x |
| X-idle-pipe | 0/200; server: 1 req on 1 conn: 3299; client: 1 heads, data_out 3311; fopen 1x; file parts received upload(3000) | 0/200; server: 1 req on 1 conn: 3317; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 0/200; server: 1 req on 1 conn: 3317; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 0/200; server: 1 req on 1 conn: 3317; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65 "Cannot rewind mime/post data"; server: 0 req on 0 conn: -; client: 1 heads, data_out 3324; fopen 1x; file parts received none |
| X-idle1500-file | 0/200; server: 1 req on 1 conn: 3287; client: 1 heads, data_out 3287; fopen 1x | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x |
| X-drop-data | 0/200; server: 2 req on 2 conn: 3240→drop@body, 3240; bodies identical; client: 2 heads, data_out 3240,3240 | 0/200; server: 2 req on 2 conn: 3258→drop@body, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: 3258→drop@body, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: 3258→drop@body, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: 3258→drop@body, 3258; bodies identical; client: 2 heads, data_out 3258,3258 |
| X-drop-file | 0/200; server: 2 req on 2 conn: 3287→drop@body, 3287; bodies identical; client: 2 heads, data_out 3287,3287; fopen 2x | 0/200; server: 2 req on 2 conn: 3305→drop@body, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: 3305→drop@body, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: 3305→drop@body, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: 3305→drop@body, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x |
| X-drop-pipe | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3299→drop@body; client: 1 heads, data_out 3311; fopen 1x; file parts received upload(3000) | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→drop@body; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→drop@body; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→drop@body; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→drop@body; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) |
| X-drophead-data | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3240; client: 2 heads, data_out 3240,3240 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3258; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3258; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3258; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3258; client: 2 heads, data_out 3258,3258 |
| X-drophead-file | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3287; client: 2 heads, data_out 3287,3287; fopen 2x | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x |
| X-drophead-pipe | 56 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3311; fopen 1x; file parts received none | 65 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3329; fopen 1x; file parts received none | 65 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3329; fopen 1x; file parts received none | 65 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3329; fopen 1x; file parts received none | 65 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3329; fopen 1x; file parts received none |
| X-drophead-big | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194591; client: 2 heads, data_out 4194591 on the last; fopen 1x, fseek(0) | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseek(0) | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseek(0) ‖ 55 "Send failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out part of the body; fopen 1x | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseeko(0) ‖ 55 "Send failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out part of the body; fopen 1x | 55 "Send failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out part of the body; fopen 1x |
| X-digest-data | 0/200; server: 2 req on 1 conn: 0→401, 3240; client: 2 heads, data_out 0,3240 | 0/200; server: 2 req on 1 conn: 0→401, 3258; client: 2 heads, data_out 0,3258 | 0/200; server: 2 req on 1 conn: 0→401, 3258; client: 2 heads, data_out 0,3258 | 0/200; server: 2 req on 1 conn: 0→401, 3258; client: 2 heads, data_out 0,3258 | 0/200; server: 2 req on 1 conn: 0→401, 3258; client: 2 heads, data_out 0,3258 |
| X-digest-file | 0/200; server: 2 req on 1 conn: 0→401, 3287; client: 2 heads, data_out 0,3287; fopen 1x | 0/200; server: 2 req on 1 conn: 0→401, 3305; client: 2 heads, data_out 0,3305; fopen 1x | 0/200; server: 2 req on 1 conn: 0→401, 3305; client: 2 heads, data_out 0,3305; fopen 1x | 0/200; server: 2 req on 1 conn: 0→401, 3305; client: 2 heads, data_out 0,3305; fopen 1x | 0/200; server: 2 req on 1 conn: 0→401, 3305; client: 2 heads, data_out 0,3305; fopen 1x |
| X-digest-pipe | 0/200; server: 2 req on 1 conn: 0→401, 3299; client: 2 heads, data_out 0,3311; fopen 1x; file parts received upload(3000) | 0/200; server: 2 req on 1 conn: 0→401, 3317; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) | 0/200; server: 2 req on 1 conn: 0→401, 3317; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) | 0/200; server: 2 req on 1 conn: 0→401, 3317; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) | 0/200; server: 2 req on 1 conn: 0→401, 3317; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) |
| X-stale-data | 0/200; server: 3 req on 1 conn: 0→401, 3240→401, 3240; bodies identical; client: 3 heads, data_out 0,3240,3240 | 0/200; server: 3 req on 1 conn: 0→401, 3258→401, 3258; bodies identical; client: 3 heads, data_out 0,3258,3258 | 0/200; server: 3 req on 1 conn: 0→401, 3258→401, 3258; bodies identical; client: 3 heads, data_out 0,3258,3258 | 0/200; server: 3 req on 1 conn: 0→401, 3258→401, 3258; bodies identical; client: 3 heads, data_out 0,3258,3258 | 0/200; server: 3 req on 1 conn: 0→401, 3258→401, 3258; bodies identical; client: 3 heads, data_out 0,3258,3258 |
| X-stale-file | 0/200; server: 3 req on 1 conn: 0→401, 3287→401, 3287; bodies identical; client: 3 heads, data_out 0,3287,3287; fopen 2x | 0/200; server: 3 req on 1 conn: 0→401, 3305→401, 3305; bodies identical; client: 3 heads, data_out 0,3305,3305; fopen 2x | 0/200; server: 3 req on 1 conn: 0→401, 3305→401, 3305; bodies identical; client: 3 heads, data_out 0,3305,3305; fopen 2x | 0/200; server: 3 req on 1 conn: 0→401, 3305→401, 3305; bodies identical; client: 3 heads, data_out 0,3305,3305; fopen 2x | 0/200; server: 3 req on 1 conn: 0→401, 3305→401, 3305; bodies identical; client: 3 heads, data_out 0,3305,3305; fopen 2x |
| X-stale-pipe | 65/401 "Cannot rewind mime/post data"; server: 2 req on 1 conn: 0→401, 3299→401; client: 2 heads, data_out 0,3311; fopen 1x; file parts received upload(3000) | 65/401 "Cannot rewind mime/post data"; server: 2 req on 1 conn: 0→401, 3317→401; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) | 65/401 "Cannot rewind mime/post data"; server: 2 req on 1 conn: 0→401, 3317→401; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) | 65/401 "Cannot rewind mime/post data"; server: 2 req on 1 conn: 0→401, 3317→401; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) | 65/401 "Cannot rewind mime/post data"; server: 2 req on 1 conn: 0→401, 3317→401; client: 2 heads, data_out 0,3329; fopen 1x; file parts received upload(3000) |
| X-refuse-end-data | 0/200; server: 2 req on 2 conn: 3240→RST@end, 3240; bodies identical; client: 2 heads, data_out 3240,3240 | 0/200; server: 2 req on 2 conn: 3258→RST@end, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: 3258→RST@end, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: 3258→RST@end, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: 3258→RST@end, 3258; bodies identical; client: 2 heads, data_out 3258,3258 |
| X-refuse-end-file | 0/200; server: 2 req on 2 conn: 3287→RST@end, 3287; bodies identical; client: 2 heads, data_out 3287,3287; fopen 2x | 0/200; server: 2 req on 2 conn: 3305→RST@end, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: 3305→RST@end, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: 3305→RST@end, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: 3305→RST@end, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x |
| X-refuse-end-pipe | 56 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3299→RST@end; client: 1 heads, data_out 3299; fopen 1x; file parts received upload(3000) | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→RST@end; client: 1 heads, data_out 3317; fopen 1x; file parts received upload(3000) | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→RST@end; client: 1 heads, data_out 3317; fopen 1x; file parts received upload(3000) | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→RST@end; client: 1 heads, data_out 3317; fopen 1x; file parts received upload(3000) | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→RST@end; client: 1 heads, data_out 3317; fopen 1x; file parts received upload(3000) |
| X-refuse-head-data | 0/200; server: 2 req on 2 conn: -→RST@head, 3240; client: 2 heads, data_out 3240,3240 | 0/200; server: 2 req on 2 conn: -→RST@head, 3258; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: -→RST@head, 3258; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: -→RST@head, 3258; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 2 conn: -→RST@head, 3258; client: 2 heads, data_out 3258,3258 |
| X-refuse-head-file | 0/200; server: 2 req on 2 conn: -→RST@head, 3287; client: 2 heads, data_out 3287,3287; fopen 2x | 0/200; server: 2 req on 2 conn: -→RST@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: -→RST@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: -→RST@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 2 conn: -→RST@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x |
| X-refuse-head-pipe | 56 "Cannot rewind mime/post data"; server: 1 req on 1 conn: -→RST@head; client: 1 heads, data_out 3299; fopen 1x; file parts received none | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: -→RST@head; client: 1 heads, data_out 3317; fopen 1x; file parts received none | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: -→RST@head; client: 1 heads, data_out 3317; fopen 1x; file parts received none | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: -→RST@head; client: 1 heads, data_out 3317; fopen 1x; file parts received none | 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: -→RST@head; client: 1 heads, data_out 3317; fopen 1x; file parts received none |
| X-refuse-head-big | 0/200; server: 2 req on 2 conn: -→RST@head, 4194591; client: 2 heads, data_out 4194591 on the last; fopen 1x, fseek(0) | 0/200; server: 2 req on 2 conn: -→RST@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseek(0) | 0/200; server: 2 req on 2 conn: -→RST@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseek(0) | 0/200; server: 2 req on 2 conn: -→RST@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseeko(0) | 0/200; server: 2 req on 2 conn: -→RST@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseeko(0) |
| F-307-data | 0/200; server: 2 req on 1 conn: 3240→307, 3240; bodies identical; client: 2 heads, data_out 3240,3240 | 0/200; server: 2 req on 1 conn: 3258→307, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 1 conn: 3258→307, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 1 conn: 3258→307, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 1 conn: 3258→307, 3258; bodies identical; client: 2 heads, data_out 3258,3258 |
| F-307-file | 0/200; server: 2 req on 1 conn: 3287→307, 3287; bodies identical; client: 2 heads, data_out 3287,3287; fopen 2x | 0/200; server: 2 req on 1 conn: 3305→307, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 1 conn: 3305→307, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 1 conn: 3305→307, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 1 conn: 3305→307, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x |
| F-307-pipe | 65/307 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3299→307; client: 1 heads, data_out 3311; fopen 1x; file parts received upload(3000) | 65/307 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→307; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65/307 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→307; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65/307 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→307; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65/307 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→307; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) |
| F-308-data | 0/200; server: 2 req on 1 conn: 3240→308, 3240; bodies identical; client: 2 heads, data_out 3240,3240 | 0/200; server: 2 req on 1 conn: 3258→308, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 1 conn: 3258→308, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 1 conn: 3258→308, 3258; bodies identical; client: 2 heads, data_out 3258,3258 | 0/200; server: 2 req on 1 conn: 3258→308, 3258; bodies identical; client: 2 heads, data_out 3258,3258 |
| F-308-file | 0/200; server: 2 req on 1 conn: 3287→308, 3287; bodies identical; client: 2 heads, data_out 3287,3287; fopen 2x | 0/200; server: 2 req on 1 conn: 3305→308, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 1 conn: 3305→308, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 1 conn: 3305→308, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x | 0/200; server: 2 req on 1 conn: 3305→308, 3305; bodies identical; client: 2 heads, data_out 3305,3305; fopen 2x |
| F-308-pipe | 65/308 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3299→308; client: 1 heads, data_out 3311; fopen 1x; file parts received upload(3000) | 65/308 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→308; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65/308 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→308; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65/308 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→308; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) | 65/308 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 3317→308; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) |

Runs: F 7.85.0 docker-1.log[floor-7.85.0], docker-2.log[floor-7.85.0]; O 8.5.0 docker-1.log[ubuntu-openssl-8.5.0], docker-2.log[ubuntu-openssl-8.5.0]; G 8.5.0 docker-1.log[ubuntu-gnutls-8.5.0], docker-2.log[ubuntu-gnutls-8.5.0]; X 8.20.0 guix-8.20.0-1.log[guix-8.20.0], guix-8.20.0-2.log[guix-8.20.0]; C 8.23.0 docker-1.log[current-8.23.0], docker-2.log[current-8.23.0].

Cells whose runs differ:
- X-drophead-big on G 8.5.0: docker-1.log[ubuntu-gnutls-8.5.0]: 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseek(0); docker-2.log[ubuntu-gnutls-8.5.0]: 55 "Send failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out part of the body; fopen 1x
- X-drophead-big on X 8.20.0: guix-8.20.0-1.log[guix-8.20.0]: 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseeko(0); guix-8.20.0-2.log[guix-8.20.0]: 55 "Send failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out part of the body; fopen 1x

### 6. Lifetime: native outcome, and Valgrind

Each cell: the transfer's code/status and the bytes the server got; libcurl's live bytes after the last cleanup, by the counting allocator (natively; 0 is none leaked); then under Valgrind with the gate's options (ADR-0014): the probe's exit, ERROR SUMMARY's count, definitely lost (Valgrind prints no leak summary when every block was freed), and each transfer's code there, NAME:code/status. L-cleanup-then-free: `curl_easy_cleanup`, then `curl_mime_free`; L-free-then-cleanup: the reverse; L-free-in-multi: `curl_mime_free` while the done easy handle is still in its multi, then remove, then clean up; L-free-before-transfer: freed after MIMEPOST, before the transfer; L-null-then-free: MIMEPOST NULL, then free, then clean up; L-never-attached: a mime never attached, freed before and (second) after its easy handle's cleanup; L-free-midflight: freed 300 ms into an 8 MiB file part's send. M- rows are case 7's, under Valgrind too.

| Case | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 | no-mime 7.85.0 | no-mime 8.23.0 |
|---|---|---|---|---|---|---|---|
| L-cleanup-then-free | 0/200, server got POST 6382; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-cleanup-then-free:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-cleanup-then-free:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-cleanup-then-free:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg L-cleanup-then-free:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-cleanup-then-free:0/200 | — | — |
| L-free-then-cleanup | 0/200, server got POST 6382; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-then-cleanup:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-then-cleanup:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-then-cleanup:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg L-free-then-cleanup:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-then-cleanup:0/200 | — | — |
| L-free-in-multi | 0/200, server got POST 6382; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-in-multi:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-in-multi:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-in-multi:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg L-free-in-multi:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-in-multi:0/200 | — | — |
| L-free-before-transfer | 0/200, server got POST 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-before-transfer:0/200 | 0/200, server got POST 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-before-transfer:0/200 | 0/200, server got POST 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-before-transfer:0/200 | 0/200, server got POST 0; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg L-free-before-transfer:0/200 | 0/200, server got POST 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-before-transfer:0/200 | — | — |
| L-null-then-free | 0/200, server got POST 6382; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-null-then-free:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-null-then-free:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-null-then-free:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg L-null-then-free:0/200 | 0/200, server got POST 6406; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-null-then-free:0/200 | — | — |
| L-never-attached | no transfer; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg - | no transfer; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg - | no transfer; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg - | no transfer; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg - | no transfer; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg - | — | — |
| L-free-midflight | 28, server got POST part of the body, then the connection ended; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-midflight:28 | 28, server got POST part of the body, then the connection ended; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-midflight:28 | 28, server got POST part of the body, then the connection ended; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-midflight:28 | 26, server got POST part of the body, then the connection ended; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg L-free-midflight:26 | 26, server got POST part of the body, then the connection ended; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg L-free-midflight:26 | — | — |
| R-when | 0/200, server got POST 5432,POST 5432; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg R-when:0/200 R-when-again:0/200 | 0/200, server got POST 5456,POST 5456; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg R-when:0/200 R-when-again:0/200 | 0/200, server got POST 5456,POST 5456; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg R-when:0/200 R-when-again:0/200 | 0/200, server got POST 5456,POST 5456; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg R-when:0/200 R-when-again:0/200 | 0/200, server got POST 5456,POST 5456; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg R-when:0/200 R-when-again:0/200 | 0/200, server got POST 0,POST 0; live 0; no Valgrind run | 0/200, server got GET 0,GET 0; live 0; no Valgrind run |
| M-other-easy | 0/200, server got GET 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-other-easy:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-other-easy:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-other-easy:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg M-other-easy:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-other-easy:0/200 | — | — |
| M-other-gone | 0/200, server got GET 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-other-gone:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-other-gone:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-other-gone:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg M-other-gone:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-other-gone:0/200 | — | — |
| M-null-easy | 0/200, server got POST 3240; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-null-easy:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-null-easy:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-null-easy:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg M-null-easy:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-null-easy:0/200 | — | — |
| M-twice | 0/200, server got GET 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-twice:0/200 | 0/200, server got GET 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-twice:0/200 | 0/200, server got GET 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-twice:0/200 | 0/200, server got GET 0; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg M-twice:0/200 | 0/200, server got GET 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-twice:0/200 | — | — |
| M-after-cleanup | 0/200, server got GET 0; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-after-cleanup.A:0/200 M-after-cleanup:0/200 | 28, server got POST 0(partial); live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-after-cleanup.A:0/200 M-after-cleanup:28 | 28, server got POST 0(partial); live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-after-cleanup.A:0/200 M-after-cleanup:28 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 B in 0 blocks; codes under vg M-after-cleanup.A:0/200 M-after-cleanup:0/200 | 0/200, server got POST 3258; live 0; vg exit 0, errors 0, definitely lost 0 (all heap blocks freed); codes under vg M-after-cleanup.A:0/200 M-after-cleanup:0/200 | — | — |

Runs: F 7.85.0 docker-1.log[floor-7.85.0], docker-2.log[floor-7.85.0]; O 8.5.0 docker-1.log[ubuntu-openssl-8.5.0], docker-2.log[ubuntu-openssl-8.5.0]; G 8.5.0 docker-1.log[ubuntu-gnutls-8.5.0], docker-2.log[ubuntu-gnutls-8.5.0]; X 8.20.0 guix-8.20.0-1.log[guix-8.20.0], guix-8.20.0-2.log[guix-8.20.0]; C 8.23.0 docker-1.log[current-8.23.0], docker-2.log[current-8.23.0]; no-mime 7.85.0 nomime-1.log[nomime-7.85.0], nomime-2.log[nomime-7.85.0]; no-mime 8.23.0 nomime-1.log[nomime-8.23.0], nomime-2.log[nomime-8.23.0].

### 7. A mime made with one easy handle, attached to another

Each cell: the MIMEPOST answers (on A, then on B, as the case makes them), the transfer on B's code, and the method and body bytes the server got for B. M-other-easy: made with A, attached to B, A alive. M-other-gone: A cleaned up before the attach. M-null-easy: `curl_mime_init(NULL)`. M-twice: attached to A, then to B while still on A. M-after-cleanup: attached to A, sent, A cleaned up, then attached to B.

| Case | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 |
|---|---|---|---|---|---|
| M-other-easy | MIMEPOST B:43; 0/200; server: GET 0 | MIMEPOST B:0; 0/200; server: POST 3258 | MIMEPOST B:0; 0/200; server: POST 3258 | MIMEPOST B:0; 0/200; server: POST 3258 | MIMEPOST B:0; 0/200; server: POST 3258 |
| M-other-gone | MIMEPOST B:43; 0/200; server: GET 0 | MIMEPOST B:0; 0/200; server: POST 3258 | MIMEPOST B:0; 0/200; server: POST 3258 | MIMEPOST B:0; 0/200; server: POST 3258 | MIMEPOST B:0; 0/200; server: POST 3258 |
| M-null-easy | MIMEPOST B:0; 0/200; server: POST 3240 | MIMEPOST B:0; 0/200; server: POST 3258 | MIMEPOST B:0; 0/200; server: POST 3258 | MIMEPOST B:0; 0/200; server: POST 3258 | MIMEPOST B:0; 0/200; server: POST 3258 |
| M-twice | MIMEPOST A:0 B:43; 0/200; server: GET 0 | MIMEPOST A:0 B:43; 0/200; server: GET 0 | MIMEPOST A:0 B:43; 0/200; server: GET 0 | MIMEPOST A:0 B:43; 0/200; server: GET 0 | MIMEPOST A:0 B:43; 0/200; server: GET 0 |
| M-after-cleanup | MIMEPOST A:0 B:43; 0/200; server: GET 0 | MIMEPOST A:0 B:0; 28; server: POST 0(partial) | MIMEPOST A:0 B:0; 28; server: POST 0(partial) | MIMEPOST A:0 B:0; 0/200; server: POST 3258 | MIMEPOST A:0 B:0; 0/200; server: POST 3258 |

Runs: F 7.85.0 docker-1.log[floor-7.85.0], docker-2.log[floor-7.85.0]; O 8.5.0 docker-1.log[ubuntu-openssl-8.5.0], docker-2.log[ubuntu-openssl-8.5.0]; G 8.5.0 docker-1.log[ubuntu-gnutls-8.5.0], docker-2.log[ubuntu-gnutls-8.5.0]; X 8.20.0 guix-8.20.0-1.log[guix-8.20.0], guix-8.20.0-2.log[guix-8.20.0]; C 8.23.0 docker-1.log[current-8.23.0], docker-2.log[current-8.23.0].

### 8. A libcurl configured without mime, and the same calls on each lane

Each cell: the answers of D-calls' lines, in order: `curl_mime_init(easy)`, `curl_mime_addpart`, `curl_mime_name`, `curl_mime_data`, `curl_mime_filedata`, MIMEPOST with NULL and with init's answer, `curl_formadd`, HTTPPOST, then two transfers: the mime init gave, with a data and a file part (D-send-init), and MIMEPOST NULL alone (D-send-mimepost-null): code, the server's method, Content-Type and body bytes.

| Case | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 | no-mime 7.85.0 | no-mime 8.23.0 |
|---|---|---|---|---|---|---|---|
| D-calls | init a mime; addpart a part; name 0; data 0; filedata 0; MIMEPOST NULL 0, init's 0; formadd 0; HTTPPOST 0; init: 0/200 POST CL 386 got 386 ct multipart/form-data; boundary=…; mimepost-null: 0/200 POST CL 0 got 0 ct none; features 0x5129c29d | init a mime; addpart a part; name 0; data 0; filedata 0; MIMEPOST NULL 0, init's 0; formadd 0; HTTPPOST 0; init: 0/200 POST CL 404 got 404 ct multipart/form-data; boundary=…; mimepost-null: 0/200 POST CL 0 got 0 ct none; features 0x55bf479d | init a mime; addpart a part; name 0; data 0; filedata 0; MIMEPOST NULL 0, init's 0; formadd 0; HTTPPOST 0; init: 0/200 POST CL 404 got 404 ct multipart/form-data; boundary=…; mimepost-null: 0/200 POST CL 0 got 0 ct none; features 0x55bf479d | init a mime; addpart a part; name 0; data 0; filedata 0; MIMEPOST NULL 0, init's 0; formadd 0; HTTPPOST 0; init: 0/200 POST CL 404 got 404 ct multipart/form-data; boundary=…; mimepost-null: 0/200 POST CL 0 got 0 ct none; features 0x553f478d | init a mime; addpart a part; name 0; data 0; filedata 0; MIMEPOST NULL 0, init's 0; formadd 0; HTTPPOST 0; init: 0/200 POST CL 404 got 404 ct multipart/form-data; boundary=…; mimepost-null: 0/200 POST CL 0 got 0 ct none; features 0x5129028d | init a mime; addpart a part; name 0; data 0; filedata 0; MIMEPOST NULL 0, init's 0; formadd 7; HTTPPOST 0; init: 0/200 POST CL 0 got 0 ct none; mimepost-null: 0/200 POST CL 0 got 0 ct none; features 0x5129c29d | init NULL; addpart NULL; name 4; data 4; filedata 4; MIMEPOST NULL 48, init's 48; formadd 7; HTTPPOST 48; init: 0/200 GET CL - got 0 ct none; mimepost-null: 0/200 GET CL - got 0 ct none; features 0x5129028d |

Runs: F 7.85.0 docker-1.log[floor-7.85.0], docker-2.log[floor-7.85.0]; O 8.5.0 docker-1.log[ubuntu-openssl-8.5.0], docker-2.log[ubuntu-openssl-8.5.0]; G 8.5.0 docker-1.log[ubuntu-gnutls-8.5.0], docker-2.log[ubuntu-gnutls-8.5.0]; X 8.20.0 guix-8.20.0-1.log[guix-8.20.0], guix-8.20.0-2.log[guix-8.20.0]; C 8.23.0 docker-1.log[current-8.23.0], docker-2.log[current-8.23.0]; no-mime 7.85.0 nomime-1.log[nomime-7.85.0], nomime-2.log[nomime-7.85.0]; no-mime 8.23.0 nomime-1.log[nomime-8.23.0], nomime-2.log[nomime-8.23.0].

### Probe processes that did not exit 0

None.

## The racing cells, 20 runs more on every lane

Generated by `summarize.mjs --count` from `results/races-docker.log.gz` and `results/races-guix.log.gz`: each cell is every value its 20 runs gave, "VALUE ×N".

### Races: 3. Paths that are not regular files

Each cell: `curl_mime_filedata`'s answer; code/status; the framing the server read and the bytes it got; the file part as received (by `expect` name; `other` when no `expect` matches; `none` when the body held no second part). N-fifo-late: the longest `curl_multi_perform` and the transfer's end, in ms (the writer opens the FIFO 1500 ms in; TIMEOUT_MS 500). N-stdin: `stdin-left`, the bytes of the pipe left after the transfer. N-relative-*: `rel.txt`, relative, given in directory a (1000 bytes, `upload-a`); the transfer then runs there (stay), after a chdir to b (1500 bytes, `upload-b`), or after one to a directory with none.

| Case | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 |
|---|---|---|---|---|---|
| N-fifo-late | rc 0; 28; chunked got 5299(partial); part: none; longest perform 1.5 s, end at 1.5 s ×20 | rc 0; 28; chunked got 5317(partial); part: none; longest perform 1.5 s, end at 1.5 s ×19 ‖ rc 0; 28; chunked got 5317(partial); part: none; longest perform 1.7 s, end at 1.7 s ×1 | rc 0; 28; chunked got 5317(partial); part: none; longest perform 1.5 s, end at 1.5 s ×20 | rc 0; 28; chunked got 5317(partial); part: none; longest perform 1.5 s, end at 1.5 s ×20 | rc 0; 28; chunked got 5317(partial); part: none; longest perform 1.5 s, end at 1.5 s ×20 |

Runs: F 7.85.0 20 runs (races-docker.log.gz); O 8.5.0 20 runs (races-docker.log.gz); G 8.5.0 20 runs (races-docker.log.gz); X 8.20.0 20 runs (races-guix.log.gz); C 8.23.0 20 runs (races-docker.log.gz).

### Races: 4 and 5. Resends inside one transfer, and libcurl's own follow

Each cell: code/status (with libcurl's error buffer when the code is not 0); the requests the server logged for the transfer's tag (and, for F-, its hop's), on how many connections, each as the body bytes it read and how it ended when not 200 (417, 401, 307, 308, drop@body or drop@head: closed unanswered, RST@head or RST@end: RST_STREAM REFUSED_STREAM, none: no answer before the connection went); whether the bodies of more than one non-empty request were byte-identical (FNV-1a of the whole body: one mime keeps its boundary); then the client's own count: the request heads libcurl sent (CURLINFO_HEADER_OUT) and the body bytes it sent after each (CURLINFO_DATA_OUT); for file, big and pipe parts, how many times libcurl opened the file and each `fseek` it made on it; for pipe, each file part the server received, by name (`upload` is the FIFO's first content, seed 3; a second open's content is seed 25, 103 mod 26). X-417: Expect: 100-continue named, 417 at the head, once. X-late417: the same, but 417 after the whole body (EXPECT_100_TIMEOUT_MS 200). X-idle: a GET, the server closes that connection 100 ms after it, the POST 400 ms later (X-idle1500: 1500 ms). X-drop: a GET, then the POST on that connection, read whole and closed unanswered; X-drophead: closed as its head arrived. X-digest: Digest; X-stale: the first valid response answered 401 stale=true. X-refuse-*: h2c, the first stream refused at its headers or at its end. F-307, F-308: FOLLOWLOCATION 1, the code after the whole body. The big kind is a 4 MiB file part, so that the resend comes while libcurl is inside it. The pipe kind is a FIFO whose writer writes once, then answers any second open with another content.

| Case | F 7.85.0 | O 8.5.0 | G 8.5.0 | X 8.20.0 | C 8.23.0 |
|---|---|---|---|---|---|
| X-idle-data | 0/200; server: 1 req on 1 conn: 3240; client: 1 heads, data_out 3240 ×20 | 0/200; server: 1 req on 1 conn: 3258; client: 1 heads, data_out 3258 ×20 | 0/200; server: 1 req on 1 conn: 3258; client: 1 heads, data_out 3258 ×20 | 0/200; server: 1 req on 1 conn: 3258; client: 1 heads, data_out 3258 ×20 | 0/200; server: 1 req on 1 conn: 3258; client: 2 heads, data_out 3258,3258 ×20 |
| X-idle-file | 0/200; server: 1 req on 1 conn: 3287; client: 1 heads, data_out 3287; fopen 1x ×20 | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x ×20 | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x ×20 | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x ×20 | 0/200; server: 1 req on 1 conn: 3305; client: 2 heads, data_out 3305,3305; fopen 2x ×20 |
| X-idle-pipe | 0/200; server: 1 req on 1 conn: 3299; client: 1 heads, data_out 3311; fopen 1x; file parts received upload(3000) ×20 | 0/200; server: 1 req on 1 conn: 3317; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) ×20 | 0/200; server: 1 req on 1 conn: 3317; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) ×20 | 0/200; server: 1 req on 1 conn: 3317; client: 1 heads, data_out 3329; fopen 1x; file parts received upload(3000) ×20 | 65 "Cannot rewind mime/post data"; server: 0 req on 0 conn: -; client: 1 heads, data_out 3324; fopen 1x; file parts received none ×20 |
| X-idle1500-file | 0/200; server: 1 req on 1 conn: 3287; client: 1 heads, data_out 3287; fopen 1x ×20 | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x ×20 | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x ×20 | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x ×20 | 0/200; server: 1 req on 1 conn: 3305; client: 1 heads, data_out 3305; fopen 1x ×20 |
| X-drophead-data | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3240; client: 2 heads, data_out 3240,3240 ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3258; client: 2 heads, data_out 3258,3258 ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3258; client: 2 heads, data_out 3258,3258 ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3258; client: 2 heads, data_out 3258,3258 ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3258; client: 2 heads, data_out 3258,3258 ×20 |
| X-drophead-file | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3287; client: 2 heads, data_out 3287,3287; fopen 2x ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 3305; client: 2 heads, data_out 3305,3305; fopen 2x ×20 |
| X-drophead-pipe | 56 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3311; fopen 1x; file parts received none ×20 | 65 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3329; fopen 1x; file parts received none ×20 | 65 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3329; fopen 1x; file parts received none ×19 ‖ 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3324; fopen 1x; file parts received none ×1 | 65 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3329; fopen 1x; file parts received none ×20 | 65 "Recv failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3329; fopen 1x; file parts received none ×19 ‖ 65 "Cannot rewind mime/post data"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out 3329; fopen 1x; file parts received none ×1 |
| X-drophead-big | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194591; client: 2 heads, data_out 4194591 on the last; fopen 1x, fseek(0) ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseek(0) ×20 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseek(0) ×18 ‖ 55 "Send failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out part of the body; fopen 1x ×2 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseeko(0) ×14 ‖ 55 "Send failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out part of the body; fopen 1x ×6 | 0/200; server: 2 req on 2 conn: 0(dropped at head)→drop@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseeko(0) ×19 ‖ 55 "Send failure: Connection reset by peer"; server: 1 req on 1 conn: 0(dropped at head)→drop@head; client: 1 heads, data_out part of the body; fopen 1x ×1 |
| X-refuse-head-big | 0/200; server: 2 req on 2 conn: -→RST@head, 4194591; client: 2 heads, data_out 4194591 on the last; fopen 1x, fseek(0) ×20 | 0/200; server: 2 req on 2 conn: -→RST@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseek(0) ×20 | 0/200; server: 2 req on 2 conn: -→RST@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseek(0) ×20 | 0/200; server: 2 req on 2 conn: -→RST@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseeko(0) ×20 | 0/200; server: 2 req on 2 conn: -→RST@head, 4194609; client: 2 heads, data_out 4194609 on the last; fopen 1x, fseeko(0) ×20 |

Runs: F 7.85.0 20 runs (races-docker.log.gz); O 8.5.0 20 runs (races-docker.log.gz); G 8.5.0 20 runs (races-docker.log.gz); X 8.20.0 20 runs (races-guix.log.gz); C 8.23.0 20 runs (races-docker.log.gz).

### Probe processes that did not exit 0

None.
