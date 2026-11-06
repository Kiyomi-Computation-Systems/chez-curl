# M8 plan: the adversarial review

Read-only review, 2026-11-06, of `docs/m8-plan`'s uncommitted tree: `.plans/2026-11-06-m8-plan.md`,
ADR-0038 to ADR-0040, ADR-0014's amendment of 2026-11-06, `global-constraints.md` (its M8 section and
the rules a slice keeps), `traps.md`'s and `AGENTS.md`'s new entries, the three surveys and the three
probes' READMEs and logs, against today's `src/`, `tests/`, `Makefile` and `.github/workflows/ci.yml`.
Three probes of this review's own sit beside this file (§ Probes). Nothing outside this directory and
`build/m8/review/` was written.

"Plan:N" is a line of the plan; other paths are the repository's.

## In short

| # | Rank | Finding |
|---|---|---|
| M1 | major | The submit's file check opens the file, and every high-level submit runs inside a critical section: an open that waits stalls every thread's collections (measured: 1.96 s for 1.96 s), against the rule that those sections wait for nothing |
| M2 | major | Re-resolving a relative path at each retry and hop (§11.4) sends another file after a `chdir`, which ADR-0039 rejected an option to avoid |
| M3 | major | A FIFO swapped in after the engine's check blocks the engine's thread in `fopen` for ever: every transfer of the engine, and its stop, hang. ADR-0039 calls this a "narrowed" window and leaves it to the docs |
| M4 | major | The mime and its parts against native's owner registry: the plan is silent, and a part handle cannot pass `check-owner` as the rule requires |
| M5 | major | `curl_formadd`, a seventh variadic binding called at every load: `check-variadic` cannot watch it fail as the plan has it, "the cheapest call" answers 5 not 0, and ADR-0001 and global-constraints still say chez-curl binds no `curl_formadd` |
| M6 | major | The probe's "no" is watched by a seam that skips the probe; the decoy libcurl, the precedent for every load probe, would watch the real call each run, and its whole-log check changes anyway |
| M7 | major | No test holds a multipart part's secret out of printed text |
| M8 | major | The cap's "libcurl refuses first" list omits what the caps probe found: a trailer line over about 4 KiB on HTTP/1.1, HTTP/2 trailers past nghttp2's limit, the codes of a line HPACK cannot compress, and 7.85.0's HTTP/2 trailers among the headers |
| M9 | major | A file shrunk after the engine's check: "28 on 7.85.0 and 8.5.0" is the probe's own 5 s timeout; with chez-curl's default of no timeout the transfer hangs |
| M10 | major | `check-memory-gate` holds the Makefile's two lists, not that CI runs both shards |
| m1 to m20 | minor | below |

No blocker was found.

## Majors

### M1. The submit's file check opens the file inside the high level's critical sections

- **The plan:** "the path must name a regular file that opens for reading, opened and closed then"
  (plan:170-172; ADR-0039, decision 3: "refuses a path that is not a regular file it can open").
- **Where a high-level submit runs:** inside `critical-section`, by design: `drive-exchange`
  (`src/http-client/private/drive.sls:403-406`), `drive-stream` (`:1013-1017`), a group's admission
  (`:1378`, `admit-one!` calling `submit!`, `:1248-1260`), its due submits and its stepped hops
  (`:1492-1503`, `:1515`). The low level's own `curl-submit` runs `prepare-transfer` outside any section
  (`src/curl/private/engine.sls:834`).
- **The rules it breaks:** "No hold waits: a thread waiting inside a critical section stays active, and
  holds every other thread's collections" (`global-constraints.md:612-622`); "Every change to a
  group's record is one critical section, which waits for nothing but a mutex's brief hold: a step
  with what it submits, a due submit" (`:754-758`); "Nothing in the checks may wait" (`:699-704`).
- **Measured** (probe `critical-open/`, two runs of three, Chez 10.4.0 threaded, the Guix container):
  an open of a FIFO whose writer came about 2 s later took 1,952 to 1,960 ms. Inside a
  `critical-section`, a worker thread that allocates stalled for the whole open, its longest gap
  1,952 to 1,960 ms, 1 or 2 collections across the open. Outside one, the same open left the worker's
  longest gap at 1 ms, with 69,846 to 73,479 collections across it: Chez deactivates the thread for the
  open, unless a critical section keeps it active. A regular file's open took 0 to 1 ms either way.
- **The failure:** a regular-file check cannot keep a FIFO out of the open: a swap between the `stat`
  and the `open` blocks it, and so can a regular file on NFS or FUSE. While it waits, every thread of
  the process, the engine's among them, stalls at its next collection, and the caller's Ctrl-C waits for
  the section's end. A FIFO with no writer holds the process for ever.
- **The fix:** never open at submit. Check with `file-regular?` (a `stat`, which a FIFO does not
  block), and leave readability to `curl_mime_filedata`'s answer and the engine's check; or run the
  high level's file checks before it enters the submit's section, the low level's recheck `stat`-only.

### M2. A relative path re-resolved at every submit meets a later `chdir`

- **The plan:** "Each submit resolves a relative path again, against the current directory then"
  (plan:128-131); "so a retry or a hop after a `chdir` opens what the path names then" (plan:362-363).
- **The record it contradicts:** ADR-0039 rejected "Absolute paths alone" because "a relative path
  resolved at submit is what its caller meant, and never meets a later `chdir`"
  (`0039-a-multipart-body.md:97-98`). The plan's own choice makes a call's later transfers meet one.
- **Measured:** `(current-directory)` is the process's: a forked thread's `(current-directory "/tmp")`
  changed the main thread's answer (probe `cwd/`, two runs). A call's retry waits a backoff or a
  `Retry-After`, and a group's procedure runs between its calls' turns, so another thread's `chdir`, or
  the group's own, lands between two transfers of one call. mime-files' N-relative-to-b shows what
  libcurl then sends: the other directory's file at the first one's size, unterminated, answered 200
  (`research/m8/mime-files/README.md:68-70`, table 3).
- **The fix:** resolve once per call: the low level at construction, keeping the absolute path in the
  request (`getcwd` waits for nothing), or the high level in `call-request-of` before its first submit,
  so `next-request` and `retry` carry the path the call named.

### M3. A FIFO swapped in after the engine's check holds the engine's thread for ever

- **The records:** "The engine's check narrows that window and cannot close it; the docs say so"
  (ADR-0039:113-114). The same record rejected "Any path, documented: a FIFO path could hold the
  engine's thread for ever" (`:99`).
- **What the window is:** the check runs in `start-transfer!`, before `curl_mime_filedata`; libcurl
  opens the file inside `curl_multi_perform` when the body reaches the part (mime-files finding 1),
  after the connect, the TLS handshake, any `Expect` wait and every earlier part's bytes. The engine's
  check narrows the submit-to-setup gap, usually milliseconds, and not this one.
- **The failure:** `fopen` of a FIFO blocks `curl_multi_perform` past `TIMEOUT_MS` (1.5 s against 500 ms
  in 22 of 22 runs, mime-files README:58-60). With no writer it never returns: every transfer of that
  engine stalls, and `curl-engine-stop` waits with no deadline (`engine.sls:1392-1396`), so a session's
  close hangs too. Anyone who can rename a file in the directory a caller uploads from can do it.
- **The fix:** a decision for the maintainer: hold the file open from submit and hand libcurl the open
  file (`curl_mime_data_cb` over a read callable on a port the submit opened, its size from the open
  file; a regular file's read never pauses, so ADR-0038's reason for rejecting streamed parts, a pause
  7.85.0 and 8.5.0 never resume, does not reach it); or state the engine-wide consequence in ADR-0039 and
  the docs, not "narrows".

### M4. The mime and its parts against native's owner registry

- **The rule:** "every easy, multi and `CURLU` handle and every string list is recorded with the thread
  that made it ... and every exported procedure that takes one checks it first"
  (`global-constraints.md:581-586`; `native.sls:104-115`, `:230-285`).
- **The plan:** "The mime is a counted kind ... Parts are the mime's, not counted" (plan:183-186). It
  says nothing of the registry, and `curl_mime_name`, `_data`, `_filedata`, `_filename` and `_type` each
  take a part: an address `own!` never recorded, so `live-handle` refuses it as an assertion violation,
  or the wrapper skips the check the rule requires. `test-native.sps:193-296`'s wrong-thread table,
  which M7 slice 4 grew for the share, is in no list of §1 or §3.9.
- **The fix:** decide it: the mime recorded as kind `mime` in its counting section, each part as an
  uncounted `part` entry forgotten with its mime; or one native wrapper that adds a whole part to a
  checked mime, so no part address leaves native. Add each new procedure to `test-native`'s
  wrong-thread table.

### M5. `curl_formadd`: a seventh variadic binding, called at every load

- **`check-variadic` cannot watch it as the plan has it.** `tests/check-variadic.sh` mutates "each of
  the six uses alone" (`:4-6`, `:17-21`), and on Apple arm64 requires `test-variadic` to fail by name and
  `test-transfer` to fail for each use's mutant (`:34-66`), with written exceptions for the multi and
  share uses; `test-collect-safe` counts six (`tests/test-collect-safe.sps:57-67`). No transfer of
  `test-transfer` and no row of `test-variadic` reaches `curl_formadd`. The plan says only that the
  binding "makes `make check-variadic` due on the Mac" (plan:278-279).
- **"The cheapest call that tells" answers 5, not 0.** Probe `formtell/`, two runs on F, O, G, X and C and
  on both no-mime builds: `curl_formadd(&p, &l, CURLFORM_END)` answers 5, `CURL_FORMADD_INCOMPLETE`, on
  every full libcurl, and 7 on both builds without mime; an unknown option number answers 4. So a probe of
  `CURLFORM_END` alone must read "7 means no", and then a garbage option number, what a binding
  without the convention would hand libcurl on Apple arm64 (unmeasured there; 9999 answered 4 here),
  reads as "mime on", unseen. With `COPYNAME` and
  `COPYCONTENTS`, 0 on every full libcurl, "0 means yes" makes the same fault refuse multipart, which the
  Mac's `make test` would see. The plan leaves "says no" undefined (plan:163-169; ADR-0039, decision 4).
- **The records still say otherwise.** ADR-0001: "libcurl has other variadic entry points, `curl_formadd`
  and the `curl_mprintf` family. chez-curl binds neither" (`0001-bind-libcurl-directly.md:269-270`);
  `global-constraints.md:33-37` names four variadics and "`curl_formadd` ... which chez-curl does not
  bind", beside its own new M8 line that the load probes with it. The amendment list (plan:287-290)
  leaves ADR-0001 out.
- **And `--disable-form-api`:** 8.5.0 and later can drop the form API alone, mime kept
  (mime-files README:177-180, read in `configure.ac`; not built): `curl_formadd` then answers 7 by
  8.23.0's `lib/formdata.c:849-855`, and the probe refuses multipart on a libcurl that has it. The 7.85.0 quirk the call exists for ends by 8.5.0, whose `lib/mime.c:34` needs
  mime on (mime-files finding 11), so a probe that calls `curl_formadd` only below that version would
  spare the Mac's 8.7.1 the call and keep multipart on a form-API-less build.
- **The fix:** the two-option call, "0 yes, 7 no, anything else no and named"; a `test-variadic` row
  (0 for a valid form, 4 for an unknown option, and the decoy's logged arguments, M6); `check-variadic.sh`
  and `test-collect-safe` taught a seventh use, with its arm64 step said; ADR-0001 and
  `global-constraints.md:33-37` amended. Consider the version gate above.

### M6. The probe's "no" is watched by a seam that skips the probe

- **The plan:** "a planted seam that makes the probe answer no ... and once, in Docker, the two no-mime
  builds, its log kept. No CI job builds one" (plan:321-323, :364-365).
- **The precedent it passes over:** `tests/decoy-libcurl.c`, which `test-library-loading` compiles per
  case, has `DECOY_OPTIONS_OFF` and `DECOY_HEADERS_OFF` (`:40-43`), one switch per load probe, so the real
  call is made and its answer read in every run. A seam proves the refusal at submit, never the probe's
  reading of `curl_formadd`.
- **The failure it leaves:** a later change that probes `curl_mime_init` alone passes every CI run,
  since 7.85.0 built without mime answers it with a working mime (probe `formtell/`, `nomime-7.85.0`:
  `mime-null a mime`), and such a libcurl sends every form empty, answered 200, the outcome ADR-0039
  rejected an option for (`:100-101`).
- **What changes anyway:** the decoy "appends one entry to a call log ... The suite asserts the whole
  log: ADR-0001's load order, the arguments each call got" (`decoy-libcurl.c:15-19`), so the four new
  load-time calls change `test-library-loading`'s every expected log; neither file is in §1's table
  (plan:38-52).
- **The fix:** a decoy `curl_formadd` (variadic, logging its options) answering 0 by default, and
  switches answering 7 and making `curl_mime_init` answer NULL, each a case of `test-library-loading`
  that asserts the load, the logged arguments and a refused multipart submit. On the Mac the logged
  arguments are the behavioural check M5 needs.

### M7. No test holds a part's secret out of printed text

- **The plan** names a refusal's part "by its index and field, never its value" (plan:189-192), makes a
  wrong shape an assertion violation (plan:101), and grows `test-printed` only with an export
  (plan:285-286).
- **The traps it meets:** "check a secret's absence in printed text, not by walking pairs"
  (`AGENTS.md:150`); "A refusal can print the value a caller put in the wrong place" (`:154`);
  "`display-condition` prints every field of a condition that has no `&message`" (`:560`). An
  assertion violation's irritant prints whole unless named by `shown-value`
  (`conditions.sls:115-127`), and a part's value, name, filename or path can be the password.
- **The fix:** one test that builds a body holding one secret in a value, a name, a filename, a type and
  a path, triggers each refusal (every reason of §3.7, every shape's assertion violation, `part-file` at
  submit and from the engine, `mime-failed`), prints each condition, the request, the token and its
  outcome, and asserts the secret absent from every text.

### M8. The cap's "libcurl refuses first" list omits what the caps probe found

- **The plan's list** (plan:262-266) and ADR-0040, decision 4 (`:55-57`): a line of 102,400 bytes, 7.85.0's
  HTTP/2 head of 128 KiB, nghttp2's limit, 8.23.0's 5,000 HTTP/2 trailers. "The docs list each, by
  version, from these tables" (plan:272).
- **Left out, each in a kept log:**
  - a trailer line of 5,000 bytes over HTTP/1.1 (4,000 taken), refused by libcurl's chunked parser before
    any callable sees it, "Out of memory in chunked-encoding", status 200: 56 on 7.85.0 and 8.5.0, 100 on
    8.20.0 and 8.23.0 (caps README:487-491; `caps/results/docker-1.log:509-513`,
    `guix-8.20.0-1.log:500-504`). It sits far below the cap's 102,400 bytes;
  - HTTP/2 trailers past nghttp2's limit, none handed, on every lane: `tr-2+400K` over h2, 56, 56, 56,
    16, 56 (caps README, case 3 and case 4);
  - the codes of a long line HPACK cannot Huffman-code: `line102400-X` over h2, 52 "Empty reply from
    server" on 7.85.0 (`docker-1.log:394-406`), 56 on 8.5.0, 16 on 8.23.0 (caps README, case 2's
    table), not the "27, 16 or 56"
    plan:263-264 and ADR-0040's Context give;
  - 7.85.0 stores HTTP/2 trailers as `CURLH_HEADER`, so `response-headers` returns them among a
    response's headers there (caps README:329-331): a per-version difference a caller meets.
- **The fix:** a row for each in §3.8, ADR-0040's decision 4 and Context, `test-headers`' table and the
  docs page; §1's trailer routes (plan:48) need a 5,000-byte HTTP/1.1 trailer line and an HTTP/2
  trailer block past nghttp2's limit.

### M9. A shrunk file "fails 28" only because the probe set a timeout

- **The plan:** "shrunk: 28 on 7.85.0 and 8.5.0, 26 on 8.20.0 and 8.23.0" (plan:268-269).
- **The log:** 7.85.0 and 8.5.0 "send what there is and wait for the timeout (28 at the probe's 5 s)"
  (mime-files README:52-53); the probe "sets `TIMEOUT_MS` ... 5000 in the C- cases" (`:211`).
- **The failure:** a request's `timeout-ms` is `#f` by default (`transfer.sls:1307`), and a high-level
  call without a bound passes none, so on the floor and on CI's main and memory libcurl the transfer waits
  for the server, which waits for the rest of a `Content-Length` body: the docs would promise a code where
  the default hangs.
- **The fix:** the row reads "stalls until `timeout-ms`; for ever with none"; the test sets one and
  asserts 28 at it; the docs say so.

### M10. `check-memory-gate` holds the lists, not the jobs

- **The plan:** "`check-memory-gate` holds the split: the two lists are disjoint, and together they are
  `SUITES` exactly" (plan:140-141), watched failing three ways, each a list's (plan:296-297).
- **The failure:** two CI jobs that both run `MEMORY_SHARD=1`, a shard-2 job deleted, or one whose
  `MEMORY_SHARD` is misspelt (`make test-memory` then runs every suite, or none) pass every check, and half
  the suites leave the gate unseen: "Deleting a subsystem disarms the checks built around it"; "A check
  held by a table of its own passes when the table is loosened" (AGENTS.md's checks traps).
- **The fix:** the check also reads `ci.yml`: exactly two memory jobs, each `make test-memory
  MEMORY_SHARD=N`, N 1 and 2; and `test-memory` refuses a `MEMORY_SHARD` other than empty, 1 or 2.

## Minors

- **m1. `curl-request-body` "as it answers a bytevector's" (plan:114) is not today's code.** The record
  keeps the caller's own bytevector (`transfer.sls:1011-1013`) and the accessor answers it, uncopied
  (`:1067-1068`); the submit copies it (`:3628-3629`). The precedent for a copy-checked field is
  `curl-request-credentials` (`:1102-1105`).
- **m2. A second test-transfer case meets the cap.** The shared `big-header?bytes=102380`, "a 200 whole on
  every libcurl" (`tests/test-transfer.sps:518-519`), is a 17-byte status line then one 102,389-byte line
  (`tests/origin.mjs:1997-2001`): 102,406 bytes at that line, past 102,400, so `header-limit` on every lane
  (the caps probe's cap mode refuses `line102398` and `line102399` over h1, `bytes@102434`, `@102435`).
  §3.3 (plan:157-159) names the 50,000-header case alone. The docs should say the longest header line the
  cap takes is about 102,380 bytes, not libcurl's 102,399.
- **m3. The plan's own example is wrong.** `(make-curl-request 'url "https://example.com/upload" ...)`
  (plan:95-98): the URL is positional (`transfer.sls:1309`; `src/curl.sls:78-79`), so the URL string
  lands where a key belongs and is refused, `unknown-key` (`transfer.sls:806-811`), before any URL is read.
  Slice 4's docs would copy it.
- **m4. Shape or refusal.** "at least one PART" is the shape (plan:85) and "A wrong shape is an assertion
  violation" (plan:101), yet `(multipart)` is the named refusal `multipart-empty` (plan:192, :360). Also
  unsaid: a `(file PATH)` of `""` or with U+0000 (`path-copy`'s `embedded-nul`?), a `filename ""` and a
  `type ""`.
- **m5. The default type** (plan:111-113): a file part given a filename of an unknown extension takes the
  path's type, `text/plain` for `c.txt` named `other.bin`, and a data part with such a filename gets none
  (mime-wire README:353, :360).
- **m6. `sends-body?` and `method-settings`.** `sends-body?` sends `delete`'s blanks only for a bytevector
  or a stream (`transfer.sls:4018-4020`), so a multipart `delete` would lose its `Expect:` blank and wait
  libcurl's 1 s past 1 MiB over HTTP/1.1 (mime-wire, question 4); `method-settings` would take
  `bytevector-length` of the list (`:4134-4137`). Neither is named, nor `MIMEPOST`'s move from the twins
  to the body field's options, the precedent when a field takes over a twin (`:1677-1679`'s list; ADR-0009,
  amended 2026-10-31).
- **m7. The engine side's condition type.** §3.7's third row names none (plan:250). A
  `&curl-transfer-error` needs `part-file` and `mime-failed` in `curl-transfer-error-reasons`
  (`conditions.sls:634-635`), with request size 0 by `fail`; the jar's precedent completes a token with a
  `&curl-request-error` from `set-up!` (`engine.sls:2050-2058`). Decide which.
- **m8. The file-change cells hold only after `curl_mime_filedata`.** A change between submit and the
  engine's check is refused (`part-file`, nothing sent) or absorbed (`stat` reads the new size), so
  "grown", "shrunk" and "removed after submit (26, after the head)" (plan:268-270) need the change made once
  the server has the head, a race unless the origin holds the body; the docs should say the head and the
  earlier parts reach the server in a request that never ends (mime-files table 2, C-removed).
- **m9. "The resends, whole on every lane"** (plan:270): a reset inside a 4 MiB part resent or failed 55,
  by a race, on G, X and C (mime-files README:95-99), a cell two runs can split (AGENTS.md's traps).
- **m10. The origin's HTTP/2 faces.** The caps stand-in raised `maxSendHeaderBlockLength`,
  `maxHeaderListPairs` and `maxHeaderListSize` to send its heads (`research/m8/caps/server.mjs:271-275`);
  the origin's h2 faces take Node's defaults (`tests/origin.mjs:1902`, `:1905`), which every h2 suite
  shares. §1's new routes (plan:48) do not say so.
- **m11. `SUPPRESS_CONNECT_HEADERS`** stays the hatch's as "changing no byte ... and nothing chez-curl
  reads" (`transfer.sls:1758-1760`). With the cap it hides a `CONNECT` answer from the callable while 8.20.0
  and 8.23.0 still count it (caps case 3); §5's "reads the options table" (plan:308-309) should name it.
- **m12. The request size's meaning.** `conditions.sls:650-656` says it holds the body's bytes; for a mime
  on 7.85.0 and 8.5.0 it is the head alone (mime-wire, question 9). §3.8 tables it; the condition's
  documentation and ADR-0022 need the same amendment.
- **m13. The split's balance and its numbers.** It reads `main`'s run (plan:142-144, :294-295), 20 min 54 s
  of suites, where PR #47's run took 31 min 4 s (ADR-0014's amendment) and PRs gate the merge: about
  15.5 min a shard before M8's suites. No kept log under `.plans/` holds runs 42255186047 or 42249246013,
  or the 84 s planted step (a grep finds only the plan and ADR-0014); the only CI memory log kept is
  `research/m7/carried/verify/ci/ci-memory-473b1b4.log`.
- **m14. Shard 2's gate is never seen failing.** "The gate proves nothing unless it can fail, so the planted
  defects run first" (`ci.yml:640-646`): shard 2's runner and its Valgrind get no plant (plan:366), to save
  84 s. Also unsaid: `MEMORY_SHARD` against a command line's `MEMORY_SUITES`, and `check-memory-gate.sh`'s
  nested `make test-memory MEMORY_SUITES=...` runs, which unset `MAKEFLAGS` (`:124`) but would inherit a job's
  `MEMORY_SHARD`; and the branch's required status checks, renamed by the split (not read: no network).
- **m15. The docs' rules have no check.** "Every code sample ... is an example's, or is marked as a fragment"
  (plan:212-213), "link nothing in `.plans/`" (plan:217) and the reference's types "as the export's comment
  gives it" (plan:208) are each held by nothing ("Prefer a check to a comment", AGENTS.md). An example run as
  a child that reaches native must print its counts for the suite to assert (`AGENTS.md:280-282`), and needs
  the origin's URL and output free of ports, dates and boundaries: unsaid. A quick start will state the
  floors, so ADR-0016's `check-floors` on `docs/` (plan:290, "if") should be decided now. M8's own
  promises to the docs (ADR-0039:83, :113-114; ADR-0040:57) are outside the survey's 45. "macOS arm64" means
  Apple's libcurl alone.
- **m16. Copies of in-memory data.** "Every string and bytevector the body holds is copied ... at
  construction and again at submit" (plan:103-105); a bytevector body today is copied at submit alone
  (ADR-0023, decision 4). The high level builds two requests (`call.sls:667`, `:685`) inside `call-state`'s
  critical section, whose holds stall every thread as they grow (`global-constraints.md:710-714`), so an
  N-byte part is copied five times or more. Copy the list and its metadata at construction, the data at
  submit.
- **m17. `curl_mime_filedata` on the engine's thread.** It `stat`s, and on 7.85.0 and 8.5.0 `access`es, the
  path in a plain call; "none blocks" (plan:279-281) holds for a local file, not NFS, where a plain call holds
  every thread's collection, and a call that can block takes no Scheme string (`global-constraints.md`,
  "Calls that can block").
- **m18. The cap callable once a reason is recorded.** "a callable refuses every call once a reason is
  recorded" (`AGENTS.md:515-517`); `read-head` today answers every line its length after a record
  (`transfer.sls:3091-3107`), and plan:150-153 does not say the cap's callable refuses.
- **m19. The high level's `multipart` beside `get` or `head`.** `call-request-of` refuses `body` and `form`
  there with field `body` or `form` (`call.sls:649-651`); for `multipart` the low level's refusal would name
  field `body`. Unsaid.
- **m20. Stale records and the load's place.** ADR-0038's Context says "What a failed open during the
  transfer answers is not measured" (`0038-m8s-scope.md:49-50`); mime-files measured it (C-removed, 26 after
  the head). ADR-0003, which ADR-0039 cites for "what the load probes", is not in the amendment list. The
  plan does not place the probe after `curl_global_init` (step 7, as the header probe), where a MultiSSL
  libcurl's `curl_mime_init(NULL)` draws its boundary through the backend in use, nor say whether the probe's
  mime is counted, when the counted wrapper's `check-owner` refuses the NULL easy handle. And the release
  steps run the Mac's `make test` before "the entry dated" and tag the squash (plan:228-231): compare the
  squash's tree with the tested branch's (`git rev-parse HEAD^{tree}`) before tagging.

## Probes

Each beside this file, each run twice, its logs kept in its `results/`.

### `formtell/`: what the form API answers, full and without mime

`probe.c` calls `curl_formget(NULL, NULL, cb)`, `curl_formadd` with `CURLFORM_END` alone, with `COPYNAME`
and `COPYCONTENTS`, and with an unknown option, and `curl_mime_init(NULL)`. On F 7.85.0, O and G 8.5.0, C
8.23.0, X 8.20.0 (`results/docker-{1,2}.log`, `guix-8.20.0-{1,2}.log`; the two Docker runs' lines and the
two Guix runs identical):

| call | F, O, G, X, C | no-mime 7.85.0 | no-mime 8.23.0 |
|---|---|---|---|
| `curl_formget(NULL, NULL, cb)` | 0, `cb` called once with 37 bytes | 7, not called | 7, not called |
| `curl_formadd(CURLFORM_END)` | 5 | 7 | 7 |
| `curl_formadd(COPYNAME, COPYCONTENTS, END)` | 0 | 7 | 7 |
| `curl_formadd(9999, END)` | 4 | 7 | 7 |
| `curl_mime_init(NULL)` | a mime | a mime | NULL |

So `curl_formget` is no callback-free probe: it calls its callback for an empty form. The rest is M5 and
M6's evidence.

```sh
sh .plans/research/m8/review/formtell/docker.sh > .plans/research/m8/review/formtell/results/docker-N.log 2>&1
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL CC=gcc sh .plans/research/m8/review/formtell/run.sh guix-8.20.0' < /dev/null > .plans/research/m8/review/formtell/results/guix-8.20.0-N.log 2>&1
```

`docker.sh` reuses the mime-files probe's apt cache (`build/m8/mime-files/apt`) and its no-mime builds,
fetches nothing, and runs `--network none --cpuset-cpus 0-5 --rm`.

### `critical-open/`: an open's cost to other threads, inside and outside a critical section

`probe.sps` opens a path on the main thread while a worker allocates 64 KiB at a time
(`collect-trip-bytes` 1 MiB), and prints the open's time, the worker's longest gap and the collections
across the open. `run.sh` runs each case in a process of its own, three times; the FIFO's writer opens it
about 2 s into the open (`results/guix-{1,2}.log`):

| case | open | worker's longest gap | collections across the open |
|---|---|---|---|
| `inside`: `(critical-section (open-file-input-port FIFO))` | 1,952 to 1,960 ms | 1,952 to 1,960 ms | 1 or 2 |
| `outside`: the same open, no section | 1,955 to 1,956 ms | 1 ms | 69,846 to 73,479 |
| `regular`: a regular file, inside a section | 0 to 1 ms | 1 ms | 0 or 1 |

```sh
scripts/guix-env sh -c 'CHEZ=$CHEZ sh .plans/research/m8/review/critical-open/run.sh' < /dev/null > .plans/research/m8/review/critical-open/results/guix-N.log 2>&1
```

### `cwd/`: whose `current-directory`

`probe.sps`: a forked thread sets `(current-directory "/tmp")`; the main thread then reads `"/tmp"`
(`results/guix-{1,2}.log`). Chez's current directory is the process's.

```sh
scripts/guix-env sh -c '$CHEZ --program .plans/research/m8/review/cwd/probe.sps' < /dev/null > .plans/research/m8/review/cwd/results/guix-N.log 2>&1
```

## Not checked

- The Mac: none of these probes ran on Apple's 8.7.1, and `curl_mime_init(NULL)` there is unmeasured.
- GitHub: no CI log or branch protection setting was read (no network).
- The 45 promises were not re-derived; the survey's count was taken as given.
