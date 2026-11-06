# M8 survey A: multipart against today's client, and the header cap

Read-only survey, 2026-11-06, of `docs/m8-plan` at `fbc6fce` (the tree was clean). It states what
the code and the records say today, with `file:line` citations; it designs and recommends nothing.
Paths are relative to the repository root. "Read in source" means read in a curl source tree under
`build/`, never measured. Nothing here was run against libcurl.

Curl trees read locally:

- `build/verify/current/curl-7.85.0` (the floor), `build/m7s4r/src/curl-8.5.0`,
  `build/m4s3/src/curl-8.7.1`, `build/verify/current/curl-8.20.0` and
  `build/verify/current/curl-8.23.0`: upstream sources, each with `include/curl/`, `lib/` and
  `docs/libcurl/`. The 8.5.0 and 8.7.1 trees are upstream's, not Ubuntu's or Apple's builds.
- The Guix profile's headers, `/gnu/store/iczfwsvwwd0srk2h3339vcq7qj8zs54k-profile/include/curl/`,
  8.20.0, read through `scripts/guix-env`. That profile has no mime man pages (`share/man/man3`).

---

## 1. Bodies at the low level

**The body kinds.** A request's `body` is a bytevector, the symbol `stream`, or `#f`
(`src/curl/private/transfer.sls:1138-1139`; documented at `src/curl.sls:84-88`). A body with `get` or
`head` is refused, `body-not-allowed` (`transfer.sls:1177-1178`). `body-length` beside a body that
does not stream is refused, `body-length-without-stream` (`transfer.sls:1179-1180`). The request holds
no procedure: its private fields are data (`transfer.sls:1019-1028`, `1171-1172`).

**Which methods send one.** `sends-body?`: `post`, `put` and `patch` always, empty for `#f`; `delete`
only with a body, whole or streamed (`transfer.sls:4018-4020`).

**A whole body** (`method-settings`, `transfer.sls:4115-4138`):

- `NOBODY` 1 for `head`; `CUSTOMREQUEST` at the upcased name for `put`, `patch` and `delete`
  (`4128-4133`);
- then `POSTFIELDSIZE_LARGE` at the bytevector's length and `COPYPOSTFIELDS` at the bytes, an empty
  bytevector for `#f` (`4134-4137`). The bytes go through `call-with-foreign-bytes`, a counted copy
  freed as setopt returns (`set-transfer-options!`, `transfer.sls:4189-4196`; native
  `call-with-foreign-bytes`, `src/curl/private/native.sls:449-456`). An empty body is a block of one
  byte, never NULL (`transfer.sls:35-40`; global-constraints, "A body's headers are the request's
  alone").
- The submit copies the bytevector after every check (`prepare-transfer`, `transfer.sls:3628-3629`),
  and libcurl copies that copy (ADR-0023, decision 4).

**A streamed body** (`method-settings`, `transfer.sls:4118-4127`):

- `post` sets `POST` 1; `put` `UPLOAD` 1; `patch` and `delete` `POST` 1 and `CUSTOMREQUEST`;
- the length is `body-length`, or -1 for none, chunked: `INFILESIZE_LARGE` for `put`,
  `POSTFIELDSIZE_LARGE` for the rest;
- the read, seek and prerequest callables and their data, the transfer's key
  (`set-transfer-options!`, `transfer.sls:4178-4184`), and `FRESH_CONNECT` 1 unless the engine's
  reusing seam (`4185-4186`).
- Caller puts feed a request stream of at most `upload-buffer-limit`, 65,536 bytes
  (`transfer.sls:3124`; `upload-put!`, `3237-3263`).

**The seek callable and the at-most-once rule** (ADR-0032, decisions 1-2 and its amendment):

- `seek-body` answers `CURL_SEEKFUNC_OK` only for offset 0 from `SEEK_SET` while no byte was handed
  and no reason is recorded; otherwise it records `body-not-replayable` and answers `CANTSEEK`
  (`transfer.sls:3499-3517`).
- `prereq-body` answers OK at the first attempt, or a later one while nothing was handed; otherwise
  `body-not-replayable` and `CURL_PREREQFUNC_ABORT` (`transfer.sls:3540-3560`).
- `FRESH_CONNECT` keeps a streamed body off pooled connections (ADR-0032, decision 1).
- A recorded reason wins over libcurl's code (`reason-of`, `transfer.sls:4441-4445`;
  `finish-transfer`, `4461-4483`).

**What is refused beside a streamed body:**

- Digest credentials, `digest-with-stream` (`check-credentials`, `transfer.sls:790-791`);
- a put past `body-length`, `body-length-mismatch`, at the put and as the outcome (ADR-0030, amended
  2026-10-31; `body-read!`, `transfer.sls:3437`, `3449`);
- at the high level: a producer in a group, `stream-in-group`
  (`src/http-client/private/call.sls:652-654`); a retry once the producer counts as called; a
  redirect that keeps the body, `body-not-replayable` (`exchange.sls:836-837`).
- `stream-with-rounds` belongs to a streamed *response* (`stream-buffer`), beside `follow` or an
  `Expect` holding `100-continue` (`transfer.sls:1181-1182`, `1272-1274`), not to a streamed body.

**Length and `Content-Type`:**

- Length: a whole body's is its bytevector's length; a streamed one's is `body-length` or -1
  (above). `Content-Length` and `Transfer-Encoding` headers are refused, `framing-header`
  (`snapshot`, `transfer.sls:468-470`).
- `Content-Type`: `sent-header-lines` hands `HTTPHEADER` the caller's headers, then, when the
  transfer sends a body, `"Content-Type:"` and `"Expect:"`, each unless the caller names that header,
  case-insensitively (`transfer.sls:4039-4046`, `string-ci=?` at `4041`). A blank `"Name:"` takes
  libcurl's own header away. M4 slice 1 measured this on five libcurls for `POSTFIELDS` bodies:
  libcurl adds `Content-Type: application/x-www-form-urlencoded` to every body and `Expect:
  100-continue` past 1 MiB, and a header the request names replaces libcurl's (ADR-0023, amended
  2026-10-26, "as built").

## 2. Bodies at the high level

**ADR-0025's kinds** (decision 3; `call-body`, `call.sls:565-570`):

- `body`: a bytevector, copied; a string, sent as `string->utf8`; or a producer (ADR-0031, decision 2).
  Anything else is `not-a-body`.
- `form`: a list of `(NAME . VALUE)` strings (`call-pairs`, `call.sls:575-578`), encoded by
  `form-encode` (`call.sls:273-286`): WHATWG `application/x-www-form-urlencoded` on UTF-8 bytes,
  `*-._` and ASCII letters and digits kept, space as `+`, every other byte `%XX` in upper case
  (`kept-byte?`, `put-component`, `call.sls:248-266`).
- `params`: the same pairs and encoding, appended by `curl-url-append-query` (`call.sls:681-684`;
  ADR-0028).
- `body` and `form` together are refused, `body-and-form`; either with `get` or `head`,
  `body-not-allowed` (`call.sls:647-651`). No JSON (ADR-0025).

**`Content-Type`.** A form's request gets `Content-Type: application/x-www-form-urlencoded` unless the
headers name one, A to Z folded (`with-form-type`, `call.sls:240-243`, applied at `678`). A bytes or
string body gets none of its own (`src/http-client.sls:234-236`), so the low level's blank
`"Content-Type:"` goes out (section 1).

**A redirect, by status** (`exchange.sls:86-130`; `body-dropped?`, `674-678`; `next-request`,
`748-774`):

- 301 or 302: a `post` becomes a `get` without its body; `put`, `patch` and `delete` keep method and
  body.
- 303: every method but `head` becomes a `get` without its body.
- 307 and 308: method and body kept.
- With the body go the headers `Content-*`, `Digest`, `Last-Modified` and `Expect`
  (`body-header?`, `exchange.sls:691-693`).
- A producer counted as called, through any redirect that keeps the body, fails as
  `body-not-replayable` (`exchange.sls:829-840`; `spent?`, `436-437`).

**What a retry resends.** The step's request record again, unchanged (`retry`,
`exchange.sls:1046-1051`). A whole body is the record's bytevector, copied again by each submit
(`prepare-transfer`, `transfer.sls:3629`). A step whose producer counts as called is never retried
(`attempts-left?`, `exchange.sls:1062-1065`).

**`next-request`'s keys** (`exchange.sls:757-774`): `url`, `method`, `headers`, `body`,
`body-length`, `stream-buffer`, `user-agent`, `timeout-ms`, `connect-timeout-ms`, `body-limit`,
`ca-file`, `verify`, `proxy`, `http-version`, `credentials` (`#f` across origins), `proxy-ca-file`,
`proxy-verify` and `cookie-jar`. That is every key of `request-keys` (`transfer.sls:657-659`). A key
`next-request` does not pass takes its default on the next hop.

**The merge of a session's and a call's keys** (`call-request-of`, `call.sls:633-713`):

- Session keys: the request keys `headers user-agent timeout-ms connect-timeout-ms body-limit ca-file
  verify proxy http-version credentials proxy-ca-file proxy-verify`, the policy keys `redirects
  allow-downgrade retry`, and `cookies` (`call.sls:63-84`).
- Call keys add `body form params body-length` (`call.sls:91`); `call-with-response-port` adds
  `stream-buffer` (`96`). Body keys are the call's alone.
- Headers (`merge-fields`, `call.sls:220-230`): a call's header replaces every session header of its
  name, A to Z folded; the session's others come first. A call's `User-Agent` header makes the field
  `#f`; a call's `user-agent` field drops the session's `User-Agent` header.
- Every other request key is the call's, else the session's (`pick`, `call.sls:679-680`). A call that
  names its own `proxy` drops the session's `proxy-ca-file` and `proxy-verify` (`701-708`). The
  session's jar is every call's (`709`).
- The merged request is built by `make-curl-request`, so the low level's refusals apply to it
  (`call.sls:626-632`).

## 3. What `(curl)` owns that multipart touches

**The owned list.** `owned-option-names` (`transfer.sls:1781-1798`):

- the always-set and pins, `WRITEFUNCTION`, `WRITEDATA` and `ERRORBUFFER`;
- every field option in `request-field-options` (`transfer.sls:1619-1632`). The body field's are
  `POSTFIELDSIZE_LARGE COPYPOSTFIELDS READFUNCTION READDATA SEEKFUNCTION SEEKDATA PREREQFUNCTION
  PREREQDATA FRESH_CONNECT`, and the method field's `NOBODY CUSTOMREQUEST POST UPLOAD`;
- the twins (`1785-1797`), among them `HTTPGET PUT POSTFIELDS POSTFIELDSIZE HTTPPOST MIMEPOST
  INFILESIZE`, `CRLF`, `TRANSFERTEXT` and `HEADEROPT`.

`tests/test-unsupported.sps:312-336` and `tests/test-transfer.sps:1344-1375` write both lists out.

**The hatch, by value kind** (ADR-0009, decision 3; `curl-request-with-options`,
`transfer.sls:2530-2550`):

- Order: a name holding U+0000 is `embedded-nul`; one unknown to the loaded libcurl `unknown-option`;
  an owned id `owned-option` (`2542`); a type outside `hatch-types`, `long values off-t string slist
  blob` (`2412`), `unsupported-type` (`2543-2544`); `repeated-option` last.
- `object`, `cbptr` and `function` options are refused by type. `MIMEPOST` and `HTTPPOST` are
  `object` options (`[floor] MIMEPOST 10269 object`, `[floor] HTTPPOST 10024 object`,
  `.plans/research/m4/slice1/results/options-docker.log:143`, `105`), and owned. Since ownership is
  checked first, each is refused as `owned-option` (`tests/test-unsupported.sps:347-351`).
- A string value holding NUL, CR or LF is refused (`text-fault`, `transfer.sls:2458-2465`).

**`MIME_OPTIONS`** is no owned name. It is a `long`, id 315, in all six recorded options tables:
7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, 8.23.0 (`options-docker.log:144`, `461`, `780`,
`1104`), Guix's 8.20.0 (`options-guix-8.20.0.log:142`) and Apple's 8.7.1
(`options-mac-8.7.1.log:141`). So the hatch takes it today on every lane. No request sends a mime
body, so what it reaches today is not recorded.

**`EXPECT_100_TIMEOUT_MS`** is no owned name either: a `long`, id 227, in the same six tables
(`options-docker.log:63`, `378`, `697`, `1017`; `options-guix-8.20.0.log:59`;
`options-mac-8.7.1.log:58`). The hatch takes it. M6's source reading says it defaults to 1000 ms, and
that on timeout libcurl sends the body anyway (`.plans/research/m6/source-reading.md:354`).

**A caller's `Expect` header and the 417 rule:**

- Every body-sending transfer sends a blank `"Expect:"` unless the caller names `Expect`
  (`transfer.sls:4045`).
- A caller's `Expect` holding `100-continue`, ASCII-folded, anywhere in its value, is refused beside a
  `stream-buffer` alone, `stream-with-rounds` (`expect-continue?`, `transfer.sls:1249-1253`;
  `check-expect-round`, `1272-1274`). Beside a whole body and a whole response it is taken.
- libcurl answers a 417 with a resend inside the transfer, counted against `MAXREDIRS`, pinned at 30
  (`pinned-options`, `transfer.sls:1800-1820`; ADR-0036, amended).
- The high level drops `Expect` with a dropped body on a redirect (`exchange.sls:691-693`).

**`CUSTOMREQUEST`** is the method field's: `put`, `patch` and `delete` set it, whole or streamed
(`transfer.sls:4122-4132`). M6's source reading: beside `POST` or `UPLOAD` it "replaces only the
method word; framing follows POST or PUT" (`source-reading.md:320`).

**`UPLOAD`** is the method field's, a streamed `put`'s (`transfer.sls:4121`). `INFILESIZE_LARGE` is
`body-length`'s (`1627`). `INFILESIZE` is a twin (`1786`).

**A caller's `Content-Type` beside a body** replaces libcurl's own, and is otherwise blanked
(section 1). Measured for `POSTFIELDS` bodies only (ADR-0023, amended 2026-10-26).

**Twins, by today's rule.** The rule: "an option with an id of its own that sets the same thing"
(ADR-0009, amended 2026-10-23). In practice each twin was found by measurement (ADR-0009, amended
2026-10-27, 2026-11-02 twice). When a field takes over a twin, it moves from the twins to the field's
options: `POST`, `UPLOAD` and `INFILESIZE_LARGE` did (ADR-0009, amended 2026-10-31), `NOPROXY` and
`COOKIEFILE` did (`transfer.sls:1600-1608`). By that rule, if a body field set `MIMEPOST`:

- `MIMEPOST` would leave the twins for `request-field-options`' body entry, and both written-out lists
  would change;
- `HTTPPOST`, `POSTFIELDS` and `POSTFIELDSIZE` already sit among the twins as "another body, size or
  form" (`transfer.sls:1677-1679`);
- `MIME_OPTIONS` changes how libcurl writes a part's field and file names. Its man page says so; it is
  unmeasured here. Whether that is "the same thing" a multipart field sets is the rule's open case,
  as `TRANSFERTEXT`'s was before it was measured;
- `EXPECT_100_TIMEOUT_MS` sets a wait, not a body. No owned setting today is that wait.

## 4. What a `curl_mime` handle would need from today's machinery

**Who owns mime handles.** ADR-0012, decision 1, already names "mime handles" among those the engine
creates, configures, adds, removes and frees on its own thread. global-constraints repeats it
("Engine and threads").

**Where easy handles are made and freed:**

- A transfer's handle is made in `start-transfer!` (`transfer.sls:4317-4321`), called from the
  engine's `set-up!` (`src/curl/private/engine.sls:2061-2065`).
- It is freed in `free-transfer!` (`transfer.sls:4348-4352`), from `take-out!` after
  `curl_multi_remove_handle` (`engine.sls:2083-2094`); on `start-transfer!`'s raise
  (`transfer.sls:4259`); and in `fail-engine!` (`engine.sls:2204-2221`).
- A jar's own handle is made in `make-jar!` (`engine.sls:1670-1674`) and freed in `free-jar!`
  (`1692-1696`). The load's header probe makes and frees one (`native.sls:1307-1318`).

**Counters and kinds.** `native-kinds` is `block easy url slist curl-string transfer multi share`
(`src/curl/private/counters.sls:38`). `tests/test-memory-safety.sps:172-174` and `207`, and
`tests/test-curl-testing.sps:139`, write the list out. A new kind changes all three.

**Native's owner registry.** It records each easy, multi, share, url and slist handle with its kind
and maker thread, in the critical section that counts it (`own!`/`disown!`, `native.sls:244-257`).
Every exported wrapper checks the registry first (`check-owner`, `277-285`): another thread's handle
raises `&curl-wrong-thread`, and a dead or wrong-kind address is an assertion violation
(`live-handle`, `263-270`).

**The critical sections.** Each counted wrapper makes, or frees, its object, its count and its
registry entry in one section: `curl-easy-init` and `curl-easy-cleanup` (`native.sls:893-910`), the
slist (`1084-1103`), the share (`1215-1242`) and the URL (`955-971`). `start-transfer!` adds a section
per object, each holding the make and the live record's field:

- key and sink (`transfer.sls:4260-4274`);
- the CURLU (`4275`);
- the error buffer (`4277`);
- each header-list append (`4286-4292`) and each hatch-list append (`4305-4314`);
- the easy handle (`4317-4321`).

`free-transfer!` mirrors them (`4348-4383`). ADR-0013's window rule: an object made or freed in one
section with its record (global-constraints, "Every native object is made, or freed, in one critical
section with its record").

**Today's lifetimes and free order.** Made in this order: key and sink, CURLU (the plan's URL parsed
again on the engine's thread), error buffer, header list, hatch string lists, easy handle, then
`set-transfer-options!` (`transfer.sls:55-64`, `4257-4326`). Freed the other way round, after the
handle leaves the multi handle: easy, hatch lists, header list, error buffer, CURLU, key
(`transfer.sls:66-75`, `4336-4383`).

- The CURLU, the header list (libcurl does not copy string lists: ADR-0009, Context) and the error
  buffer each outlive the easy handle.
- The error buffer is read by `failure` before any free (`transfer.sls:1465-1476`, `4461-4483`).
- A jar's share outlives every handle that holds it: `curl_share_cleanup` answers `CURLSHE_IN_USE`
  while one does, so a jar's own handle goes first and a closing jar is freed by its last holder
  (`free-jar!`, `engine.sls:1690-1706`; `release!`, `1726-1736`).
- A handle whose removal failed is abandoned, never freed, and stays counted
  (`abandon-transfer-easy!`, `transfer.sls:4333-4334`; `engine.sls:2211-2216`). Whatever it holds is
  kept with it: the jar hold is, at `2217`.

**The nesting check.** The trap "libcurl's cleanup reads nothing a transfer handed it"
(`.plans/traps.md:380-385`) is held by `tests/test-transfer.sps:1689-1724`. It reads `start-transfer!`
and `free-transfer!` as data, collects the live record's setters in `live-setters`
(`1689-1691`), and asserts the making order and the freeing order whole. A new object in the live
record needs a setter there and a place in both expected lists.

**What the mime pages say about the handle** (documentation, not measured):

- 7.85.0's `curl_mime_init.3`: it "creates a handle to a new empty mime structure intended to be used
  with *easy_handle*", attached by `CURLOPT_MIMEPOST`.
- 8.23.0's `curl_mime_init.md`: "*easy_handle* is used for part separator randomization and error
  reporting. Since 7.87.0, it does not need to be the final target handle." So from 7.85.0 to 7.86.x
  the documented rule ties a mime to its transfer's own handle.
- `curl_mime_free.3` (7.85.0): it "must be called when the data has been used, which typically means
  after `curl_easy_perform(3)`"; subpart structures "must not be explicitly freed as they are by the
  top structure freeing"; NULL is a no-op.
- The `curl_mime_init.3` example frees `curl_easy_cleanup(easy)` before `curl_mime_free(mime)`, as
  does 8.23.0's `docs/examples/postit2.c:96-99`.

## 5. The bindings

**How native binds.** Every entry point is bound eagerly, in order, in the library body
(`native.sls:5-35`), through one of three binders:

- `bind-required`, plain (`298-303`);
- `bind-variadic`, `(__varargs_after 2)` (`315-320`);
- `bind-blocking`, `__collect_safe` (`329-334`).

Each first asks `foreign-entry?` and refuses an absent entry as `missing-api` (`required-entry`,
`287-294`). `curl_easy_setopt` is bound once per value type: `long`, a pointer as `uptr`, and
`integer-64` (`856-863`). The transfer picks the binding by the option's CURLOT type, `object`
included, through `option-bindings` (`transfer.sls:1559-1561`) and `set-option!` (`1918-1928`).

**The `__collect_safe` rule** (ADR-0013; global-constraints, "Calls that can block"): every call that
can block, and every callback such a call can invoke, is `__collect_safe`. "One callable may serve a
`__collect_safe` call and a plain one." A call that can block, or invoke a callback, never receives a
Scheme string or bytevector.

**What `test-collect-safe` requires** (`tests/foreign-conventions.sls:143-185`, `351-390`):

- a row per entry point or callable in `conventions-table`, with its conventions and a citation
  quoting a decision record;
- a binder where named, `(bound-by ...)`;
- every type on the allowlist: immediates, `(* F)` for a layouts ftype, and crossings only where the
  row is marked. `string` needs `string-not-kept`; `u8*` needs `bytevector-crossing`, memcpy's alone;
  `scheme-object` never.

**What `test-constants` requires** (`tests/test-constants.sps:1-75`):

- a prototype row per bound entry in the header's own spelling (`prototype-rows`, `1115-1155`);
- each binding's Chez types allowed by `c-type-map` (`1183-1201`). A pointer is a type ending in `*`
  or `[]` (`pointer-type?`, `1209-1214`); "A C type in no entry here, and no pointer, fails its row by
  name" (`1180-1182`). The typedef names `curl_read_callback`, `curl_seek_callback` and
  `curl_free_callback`, as parameters of `curl_mime_data_cb`, are neither pointers by that rule nor
  map entries today;
- a callable row per callable, naming its function-pointer typedef (`callable-rows`, `1163-1168`):
  today `curl_write_callback`, `curl_read_callback`, `curl_seek_callback` and
  `curl_prereq_callback`;
- a new constant in `(curl private constants)` with a row in `constant-rows` (`139`); one newer than
  the floor also in `gated-rows` (`271-272`);
- a struct Scheme reads as a `define-ftype` in layouts with a `layout-rows` row (`281`).

**What layouts requires.** Struct `define-ftype` forms alone (`src/curl/private/layouts.sls:1-17`;
global-constraints, "Native code"). `curl_mime` and `curl_mimepart` are incomplete typedefs in
`curl.h` (`typedef struct curl_mime curl_mime;`, 7.85.0 `include/curl/curl.h:2316-2317`), so no field
is read through them. `struct curl_slist` already has a layout (`layouts.sls:127-130`).

**check-seam.** `foreign-procedure` is native's alone; `foreign-callable`,
`foreign-callable-entry-point` and `lock-object` are transfer's alone (`tests/check-seam.sps:26-30`;
global-constraints, "Layout and names").

**The `curl_mime_*` API at the floor.** Quoted from 7.85.0's `include/curl/curl.h`
(`LIBCURL_VERSION "7.85.0"`, `curlver.h:35`):

```c
typedef struct curl_mime      curl_mime;      /* Mime context. */
typedef struct curl_mimepart  curl_mimepart;  /* Mime part context. */
/* CURLMIMEOPT_ defines are for the CURLOPT_MIME_OPTIONS option. */
#define CURLMIMEOPT_FORMESCAPE  (1<<0) /* Use backslash-escaping for forms. */
CURL_EXTERN curl_mime *curl_mime_init(CURL *easy);
CURL_EXTERN void curl_mime_free(curl_mime *mime);
CURL_EXTERN curl_mimepart *curl_mime_addpart(curl_mime *mime);
CURL_EXTERN CURLcode curl_mime_name(curl_mimepart *part, const char *name);
CURL_EXTERN CURLcode curl_mime_filename(curl_mimepart *part,
                                        const char *filename);
CURL_EXTERN CURLcode curl_mime_type(curl_mimepart *part, const char *mimetype);
CURL_EXTERN CURLcode curl_mime_encoder(curl_mimepart *part,
                                       const char *encoding);
CURL_EXTERN CURLcode curl_mime_data(curl_mimepart *part,
                                    const char *data, size_t datasize);
CURL_EXTERN CURLcode curl_mime_filedata(curl_mimepart *part,
                                        const char *filename);
CURL_EXTERN CURLcode curl_mime_data_cb(curl_mimepart *part,
                                       curl_off_t datasize,
                                       curl_read_callback readfunc,
                                       curl_seek_callback seekfunc,
                                       curl_free_callback freefunc,
                                       void *arg);
CURL_EXTERN CURLcode curl_mime_subparts(curl_mimepart *part,
                                        curl_mime *subparts);
CURL_EXTERN CURLcode curl_mime_headers(curl_mimepart *part,
                                       struct curl_slist *headers,
                                       int take_ownership);
```

From the same file (`2308`, `2316-2441`): `#define CURL_ZERO_TERMINATED ((size_t) -1)`;
`CURLOPT(CURLOPT_MIMEPOST, CURLOPTTYPE_OBJECTPOINT, 269)` (`2009`);
`CURLOPT(CURLOPT_MIME_OPTIONS, CURLOPTTYPE_LONG, 315)` (`2139`);
`CURLOPT(CURLOPT_HTTPPOST, CURLOPTTYPE_OBJECTPOINT, 24)` (`1174`); and the callback typedefs:

```c
typedef int (*curl_seek_callback)(void *instream,
                                  curl_off_t offset,
                                  int origin); /* 'whence' */
typedef size_t (*curl_read_callback)(char *buffer,
                                      size_t size,
                                      size_t nitems,
                                      void *instream);
typedef void (*curl_free_callback)(void *ptr);
```

(`359-361`, `377-380`, `445`).

**Later versions.** The same twelve `curl_mime_*` declarations, `CURLMIMEOPT_FORMESCAPE`, `MIMEPOST`
269 and `MIME_OPTIONS` 315 appear in the 8.5.0, 8.7.1, 8.20.0 and 8.23.0 trees and in the Guix
profile's 8.20.0 `curl.h` (lines 2441-2550 there). From 8.20.0 the bit reads
`(1L << 0) /* Use backslash-escaping for forms */`. From 8.5.0, `HTTPPOST` is
`CURLOPTDEPRECATED(... 7.56.0, "Use CURLOPT_MIMEPOST")` and `curl_formadd`/`curl_formfree` carry
`CURL_DEPRECATED(7.56.0, ...)`; 7.85.0's header marks neither. chez-curl binds neither, nor any
variadic but its four (global-constraints, "Native code").

**What the constants table already has.** `curl-readfunc-abort`, `curl-readfunc-pause`,
`curl-seekfunc-ok`, `curl-seekfunc-cantseek` and `seek-set` (`constants.sls:42-43`, `546-552`), and
`curle-bad-function-argument` 43 and `curle-not-built-in` 4 (`122`, `129`). `CURLE_READ_ERROR`, 26,
is no named constant; its class is none (`tests/test-conditions.sps:314`). There is no
`CURL_ZERO_TERMINATED` and no `CURLMIMEOPT_FORMESCAPE`.

**A build without mime.** curl's `./configure` has `--disable-mime` (7.85.0 `configure.ac:3977-3981`;
8.23.0 `:4749-4753`). Read in source, such a build keeps every `curl_mime_*` symbol as a stub: init
and addpart answer NULL, the setters `CURLE_NOT_BUILT_IN` (7.85.0 `lib/mime.c:1927-2010`; 8.23.0
`lib/mime.c:2229` on). So `foreign-entry?` and `missing-api` cannot see it: AGENTS.md, "nm cannot show
a curl API that was configured out". `curl.h`'s `CURL_VERSION_*` bits hold no mime bit (8.23.0
`include/curl/curl.h:3203-3239`). CI's curl builds pass no `--disable-mime`
(`scripts/ci/build-curl.sh:143-172`).

**The man pages.** They are local for 7.85.0 (`docs/libcurl/curl_mime_*.3`,
`opts/CURLOPT_MIMEPOST.3`, `opts/CURLOPT_MIME_OPTIONS.3`, `opts/CURLOPT_EXPECT_100_TIMEOUT_MS.3`) and
for 8.23.0 (`.md`). Quoted where used below.

**Not found:** Apple's 8.7.1 headers and Ubuntu's 8.5.0 `-dev` headers, which are not local; the Guix
profile's man pages; any record that measures a mime call.

## 6. Callbacks

**How today's callables are made** (`transfer.sls:189-206`, `3008-3567`):

- Each is `(define NAME (foreign-callable __collect_safe (lambda ...) (ARGS) RESULT))`: `write-body`
  (`3008-3035`), `read-head` (`3091-3109`), `read-body` (`3465-3477`), `seek-body` (`3499-3517`) and
  `prereq-body` (`3540-3560`).
- Each is locked where it is defined, never unlocked (`3039-3040`, `3112-3113`, `3480-3481`,
  `3520-3521`, `3563-3564`), and its entry point taken by `foreign-callable-entry-point`.
- Each is handed the transfer's key, an integer, as its `*DATA`, so no Scheme object crosses
  (`194-196`). The key indexes a table of sinks under a mutex (`sinks`, `2619-2621`; `sink-of`,
  `2648-2649`).
- Each callable's whole body runs under `(guard (e (#t (record! key 'callback-raised e) ANSWER)))`,
  answering the refusal value for its kind: 0, `CURL_READFUNC_ABORT`, `CANTSEEK` or `PREREQFUNC_ABORT`.
  `record!` never raises and keeps the first reason (`2654-2658`).
- The lock is held by behaviour, under a paced collector (`tests/test-transfer.sps:2520`,
  `tests/test-stream.sps:1096`, `tests/test-upload.sps:1499`).

**The `dynamic-wind` that turned an escape into a raise is gone.** It wrapped M2's caller-code hook
inside `write-body` (ADR-0013, amended 2026-10-23; `.plans/traps.md:387-394`). ADR-0013, amended
2026-10-25: "The engine's write callable runs no procedure a caller supplied, so the hook's
`dynamic-wind`, the performing mark and the escape child ... went with them." Today no callable runs
caller code, and the only escape route left on the engine's thread is a process-wide
`collect-request-handler` (same amendment; `engine.sls:159-166`).

**Refusing every call once a reason is recorded:**

- `stream-chunk!` answers 0 for every call once anything is recorded (`transfer.sls:2973-2975`), for
  Apple's 8.7.1, which hands a refused chunk back after `curl_easy_pause` (AGENTS.md trap);
- `body-read!` answers `ABORT` once recorded (`3436`, `3448`);
- `seek-body` and `prereq-body` refuse once recorded (`3513`, `3556`).

**Caller code never runs on the engine's thread** (ADR-0012, decision 4):

- the callables only copy between libcurl's buffers and bounded buffers;
- a request holds no procedure (`transfer.sls:1016-1028`);
- the high level's producer is called on the caller's thread, which puts its pieces through
  `curl-token-put-piece!` (ADR-0031, decision 2; `src/http-client.sls:249-252`);
- a test asserts the thread inside the body consumer and the delivery (ADR-0012, decision 4).

**What `curl_mime_data_cb`'s callbacks would meet** (7.85.0 `curl_mime_data_cb.3`, documentation):

- `readfunc` "may not be set to NULL"; it "gets called by libcurl as soon as it needs to read data";
  it may answer `CURL_READFUNC_ABORT` or `CURL_READFUNC_PAUSE`.
- `seekfunc` "will be used upon resending data (i.e.: after a redirect); this pointer may be set to
  NULL, in which case a resend is not possible".
- `freefunc` "will be called upon mime structure freeing", so it would fire inside `curl_mime_free`.
  Nothing records whether that call can block, which decides its binder.
- `arg` is shared with any duplicated handle, and `freefunc` is then called twice. chez-curl binds no
  `curl_easy_duphandle` (native's exports, `native.sls:142-160`).

By today's rules such callables would be transfer.sls's, `__collect_safe` wherever a `__collect_safe`
call can fire them, locked, keyed by an integer and not a Scheme object, running no caller code, and
refusing once a reason is recorded. Which libcurl calls run a part's read and seek callbacks, the
perform, `curl_easy_pause`, a setopt or `curl_mime_free`, is not recorded; it would need measuring.

## 7. File paths

**M7 rejected cookie files.** ADR-0033, decision 3: "No file paths: file I/O stays the caller's, and
`COOKIEFILE` and `COOKIEJAR`, whose `"-"` reads stdin and writes stdout, stay refused." Rejected:
"`COOKIEJAR` writes only at cleanup and reports no error, by its man page." ADR-0009, amended
2026-10-27: "Only libcurl's own `"-"` modes are refused ... A path at `/dev/stdin` is the caller's
choice, and the README says so." `ALTSVC`, a file libcurl writes at `curl_easy_cleanup` on the
engine's thread, is owned (ADR-0009, amended 2026-11-02).

**Paths chez-curl hands libcurl today:**

- `ca-file`, which sets `CAINFO`, and `proxy-ca-file`, which sets `PROXY_CAINFO`
  (`transfer.sls:1960-1967`, `2057-2059`). `path-copy` copies the string, refuses U+0000
  (`embedded-nul`) and a `pkcs11:` prefix in any ASCII case (`pkcs11-url`), and nothing else:
  "a path may hold CR or LF" (`530-544`).
- The path goes "as given, relative or absolute" (`867-870`), as a counted UTF-8 copy set on the
  engine's thread (`set-tls-options!`, `1974-1979`, from `set-transfer-options!`, `4230`).
- A missing file "is libcurl's to refuse: 77" (ADR-0018, decision 1).
- chez-curl itself opens two files: `/proc/self/maps` and the loaded libcurl's file, both at load
  (`native.sls:207-215`, `651-656`).

**When and on which thread libcurl opens the CA file:** not found in any record. The setopt runs on the
engine's thread; that the open happens inside the transfer's handshake, also on the engine's thread,
is an inference from where libcurl runs a transfer, not a record. A relative path then resolves
against the process's working directory, which is not recorded either.

**What `curl_mime_filedata` documents** (7.85.0 `curl_mime_filedata.3`):

- "The contents of the file is read during the file transfer in a streaming manner ... It therefore
  requires that the file is kept intact during the entire request."
- "As a side effect, the part's remote file name is set to the base name of the given filename."
- "If the file size cannot be determined before actually reading it (such as for a device or named
  pipe), the whole mime structure containing the part will be transferred as chunks by HTTP."
- Its return: "`CURLE_READ_ERROR` is only an indication that the file is not yet readable: it can be
  safely ignored at this time."

Read in 7.85.0's source, not measured: the call `stat`s and `access`es the path when it is made
(`lib/mime.c:1420`), sets a seek only for a regular file (`1428-1431`), and has no special case for
`"-"` (`1407-1450`). Under ADR-0012 that call would run on the engine's thread.

## 8. Strings and bytes

**Today's rules:**

- **UTF-8 default.** Every string handed to libcurl is a counted, NUL-terminated UTF-8 copy, refusing
  U+0000 (`call-with-c-string`, `native.sls:493-505`; global-constraints, "Native code").
- **Header names** are RFC 9110 tokens, ASCII alone (`tchar?`/`token?`, `transfer.sls:329-339`).
- **Header values and the user agent** are Latin-1, one char per byte (`call-with-latin-1-c-string`,
  `native.sls:519-539`). The first offending char decides: U+0000 `embedded-nul`, CR or LF
  `line-break`, above U+00FF `not-latin-1` (`value-fault`, `transfer.sls:345-353`). Then SP, HTAB, VT
  or FF at either end, `surrounding-whitespace` (`value-problem`, `365-370`).
- **Banned headers.** A second `Host`, or a `User-Agent` beside the field, is `duplicates-field`;
  `Content-Length` and `Transfer-Encoding` are `framing-header`; `Proxy-Authorization` is refused by
  name (`snapshot`, `432-475`). A header value's refusal names its header, never the value
  (`425-429`).
- **URL bytes.** `curl_url` parses every URL. What `curl_url_get` gives back is read as strict UTF-8 or
  refused, `not-utf-8`. A header's bytes handed to a URL function are encoded into ASCII first
  (global-constraints, "URLs and protocols"; ADR-0029).
- **Credentials** are UTF-8 with no control char, U+0000 to U+001F or U+007F, and no colon in a Basic
  user (`control-char?`, `check-credentials`, `transfer.sls:740-791`). A refusal names the scheme and
  the part, never the string.
- **Cookie lines** are Latin-1 both ways, with no control byte but tab, seven fields, and a name and
  value of 4,096 bytes at most (`cookie-line-fault`, `transfer.sls:2266-2298`). A refusal names the
  line's index (`cookie-line-bytes`, `2328-2349`).
- **Hatch strings** hold no NUL, CR or LF (`text-fault`, `2458-2465`).
- **Copy, then check.** Every check of a caller's string or list runs on a private copy, the copy is
  what is used, and lists are walked by a count fixed first (global-constraints, "Native code";
  `snapshot`, `transfer.sls:436-449`; `option-pairs`, `2442-2452`; `string-pairs-within`,
  `call.sls:146-165`). Folding is A to Z alone, never `string-ci=?`
  (`ascii-folded`, `transfer.sls:1235-1236`; AGENTS.md trap on U+212A and U+017F).

**What a part's strings would need under the same rules.** Each is a C string libcurl copies:
`curl_mime_name.3`, `curl_mime_filename.3`, `curl_mime_type.3` and `curl_mime_encoder.3` each say
the storage "may safely be released or reused after" the call. So each would need a counted
NUL-terminated copy refusing U+0000, as every string does. Each also needs a choice of encoding:
UTF-8, the default rule, or Latin-1, the header rule's one exception.

- **Name and filename** end up in a generated part header, per `curl_mime_filename.3`:
  "transmitted to the server in the associated Content-Disposition generated header".
  `CURLOPT_MIME_OPTIONS.3` (7.85.0) documents the escaping: "Percent encoding maps all occurrences of
  double quote, carriage return and line feed to %22, %0D and %0A respectively. Before version
  7.81.0, percent-encoding was never applied." `CURLMIMEOPT_FORMESCAPE` swaps it for backslash
  escaping.
- **Type** is a header value. Its man page gives the default when none is set: a custom header's
  value, `application/form-data` for an HTTP form post, from the filename's extension or
  `application/octet-stream`, `multipart/mixed` for subparts, else `text/plain`.
- **Part headers** go through `curl_mime_headers` as a `struct curl_slist`, which today's header rules
  would reach line by line. Its `take_ownership` hands the list's free to libcurl ("must not be freed
  explicitly"). Today every slist is counted and freed by `curl-slist-free-all`
  (`native.sls:1084-1103`), so a list libcurl frees would never be counted down.
- **Data.** `curl_mime_data` copies its bytes ("The storage may safely be reused after the call"),
  with an explicit size or `CURL_ZERO_TERMINATED`. By today's rule bytes cross through foreign memory,
  as `COPYPOSTFIELDS`' do (`call-with-foreign-bytes`).

**To be measured, not claimed:** what libcurl writes, on each lane, for a name or filename holding
`"`, `\`, CR, LF, other control bytes, bytes above 0x7F and UTF-8, under each `MIME_OPTIONS` value. Also:

- whether a part's type or a part header holding CR or LF reaches the wire;
- what part headers named `Content-Disposition`, `Content-Type`, `Content-Transfer-Encoding`,
  `Content-Length` or `Transfer-Encoding` do beside libcurl's own;
- the filename basename side effect for paths with odd bytes;
- each encoder's output and failures (`curl_mime_encoder.3`: `7bit` gives "a read error" on a high
  byte; `quoted-printable` leaves the size unknown, "causing chunked transfer").

## 9. Secrets and printing

**Opaque records today:**

- request, plan and live transfer (`transfer.sls:1055`, `3595`, `4067`);
- engine, token and mailbox (`engine.sls:336`, `361`, `371`);
- cookie jar, `curl-response` and `curl-head` (`transfer.sls:683`, `1400`, `2713`);
- libcurl-info (`src/curl/private/libcurl-info.sls:53`);
- at the high level: response, exchange, retry, session, stream-call, leg, group and pending
  (`exchange.sls:245`, `368`; `call.sls:397`, `509`; `drive.sls:449`, `477`, `1157`, `1188`).

The rule: "No record that holds a request, a plan, a token or credentials prints its fields"
(global-constraints, "M7"; AGENTS.md trap on `record-rtd`). The private `hatch-setting`, `sink`,
`response-stream` and `upload` records are not opaque (`transfer.sls:2417`, `2610`, `2756`, `3165`);
each is reached only through an opaque one.

**Accessors.** Every public record and condition accessor checks its argument first and names a wrong
one by kind (`checked-accessor`, `src/curl/private/conditions.sls:141-145`; `shown-value`, `124-127`;
`shown-key`, `132-133`).

**`tests/test-printed.sps`.** Every export of `(curl)`, `(curl unsupported)` and `(http-client)` has a
row, written out (`tests/test-printed.sps:5-18`, `120-125`). Each is called with a URL holding a
password, and must print neither it nor a jar's cookie values. A new export fails until it has a row.

**Refusals name a field, not a value:**

- a header value's refusal names its header (`transfer.sls:425-429`);
- credentials name the scheme and part (`744-748`);
- a proxy refusal names `proxy` (`3763-3768`);
- a cookie line names its index (`2339-2347`);
- a key found where a value belongs is named by kind (`request-settings`, `806-814`).

**What a part or a form would meet:**

- a part's value can be a secret, as a form field's password is;
- a filename or part header can carry one too;
- a record that holds parts would print its fields unless opaque;
- each new export needs a printed row;
- a refusal of a part would name it by field or index, never its bytes, as the cookie-line refusal
  does.

Not found: any record that says whether a part's value, name or filename counts as a secret.

## 10. The header cap carried for M8's plan

**Carried by** `.plans/progress.md:72` ("a cap on response headers, for M8's plan") and by the M7
plan's §10 ("a chez-curl cap on response headers, whose walk costs n²",
`.plans/2026-11-02-m7-plan.md:584`).

**How headers are read today.** `response-headers` walks `curl_easy_nextheader` for `CURLH_HEADER` of
request -1, copying each name and value as Latin-1 (`transfer.sls:4410-4420`;
`curl-header-bytes`, `native.sls:1070-1073`). It runs on the engine's thread:

- in `finish-transfer`, for every transfer that ends `CURLE_OK`, streamed or not, before any free
  (`transfer.sls:4479`), called from `read-finished!` (`engine.sls:2114-2128`);
- for a streamed response, also in `head-line!` at the first final head (`transfer.sls:3070`), inside
  `read-head`, a `__collect_safe` callable that fires inside `curl_multi_perform` or
  `curl_easy_pause`. So a streamed response's headers are walked twice.

The high level reads the resulting lists linearly on the caller's thread (`location-of`,
`exchange.sls:831`; `Retry-After`, `1079`).

**Its cost, as recorded.** `.plans/traps.md:1348-1356`, `research/ci-first-run/README.md:39-42`:
`curl_easy_nextheader` counts, from the first header, every one sharing the returned name
(`lib/headers.c` on 7.85.0, 8.20.0 and 8.23.0), so n headers cost n².

- On 7.85.0, 100,000 headers took 30.4 to 31.5 s, all CPU, after the transfer had ended; 50,000 took
  7.3 to 7.7 s (README row `many-headers.sps`).
- 8.5.0 took 20,000 in 1.9 s and refused 30,000 and more with 56; 8.20.0 and 8.23.0 refused 20,000 and
  more with 100.
- During the walk the engine's thread serves no other transfer (it is one thread, `engine.sls:37-63`).

**Any bound today.** None of chez-curl's own on headers. The only response bound is `body-limit`:
`MAXFILESIZE_LARGE` at the limit plus one, and the write callable refuses past it, reason
`body-limit`, class too-large (`transfer.sls:202-206`, `3022-3025`; global-constraints, "`body-limit`
is too-large"). Among the options whose names hold `HEADER` in 8.23.0's table, none caps response
headers (`options-docker.log`, `[current]` rows: `HEADER`, `HEADERDATA`, `HEADERFUNCTION`,
`HEADEROPT`, `HTTPHEADER`, `HTTPSIG_HEADERS`, `PROXYHEADER`, `RTSPHEADER`,
`SUPPRESS_CONNECT_HEADERS`, `WRITEHEADER`). The full table was not reviewed for one.

**libcurl's caps by version.**

As the records state them:

- 7.85.0 caps no response's headers;
- 8.7.1 and 8.20.0 cap them at 300 KiB, and 8.20.0 at 5,000 headers too (`.plans/traps.md:1350-1351`;
  `research/ci-first-run/README.md:41-42`);
- AGENTS.md: "the newer caps: 300 KiB, and 5,000 from 8.20.0";
- `tests/known-transfer-verdicts.sexp`'s 8.7.1 row notes the 300 KiB cap and that "50,000 are about
  690 KB".

The verdicts for `/raw/many-headers?count=50000`: 7.85.0 a 200 with all 50,000; 8.5.0 and 8.7.1
refused 56; 8.20.0 and 8.23.0 refused 100 (`known-transfer-verdicts.sexp`;
`tests/test-transfer.sps:551`). One header past `CURL_MAX_HTTP_HEADER`, 100 KiB in every `curl.h`
read: 27 on 7.85.0 and 8.5.0, 100 on 8.7.1 and later (ADR-0022, Context; same rows).
`tests/known-libcurls.sexp` records no caps.

Read in source here, beyond the records: `lib/http.h`'s `MAX_HTTP_RESP_HEADER_SIZE (300*1024)` is in
the upstream 8.5.0 tree too (`build/m7s4r/src/curl-8.5.0/lib/http.h:190-193`), and both constants are
in 8.23.0's (`lib/http.h:154-162`: 300 KiB and `MAX_HTTP_RESP_HEADER_COUNT 5000`). 7.85.0's `lib/http.h`
has neither. The records name neither 8.5.0's size cap nor 8.23.0's caps; 8.5.0's measured answers
(20,000 taken, 30,000 refused) fit a 300 KiB cap. Ubuntu's 8.5.0 build was not read.

**Where a chez-curl cap could sit, by today's code** (sites, not a design):

- **The header callable.** `read-head` sees every head line as it arrives, before `head-line!` walks
  (`transfer.sls:3091-3107`). Today it is set only for a streamed response
  (`set-transfer-options!`, `4175-4177`). Its answer of 0 fails the transfer, and a recorded reason
  wins over the code. `HEADERFUNCTION` and `HEADERDATA` are owned (`1627`).
- **The walk itself.** `response-headers` (`4413-4420`) could stop at a count or a byte total. It runs
  after libcurl has stored every header, and its cost before any stop is the walk's.
- **A field beside `body-limit`.** Today's precedent for a caller-set response bound: a request key,
  a session key (`call.sls:63-65`), passed by `next-request` (`exchange.sls:766`), with a reason of no
  class or too-large (ADR-0022).
- **Documentation alone**, by libcurl's caps per version (the verdict rows above).

## 11. The high level's surface

**Exports** (`src/http-client.sls:157-573`):

- sessions: `make-http-session`, `http-session?`, `http-session-close`, `call-with-http-session`,
  `http-session-cookies`, `http-session-load-cookies!`;
- the verbs: `http-request`, `http-get`, `http-head`, `http-post`, `http-put`, `http-patch`,
  `http-delete`;
- streaming: `call-with-response-port`;
- retries: `make-http-retry`, `http-retry?`;
- groups: `call-with-request-group`, `http-pending?`, `http-await`, `http-pending-done?`,
  `http-pending-cancel`, `http-parallel`;
- the response: `http-response?`, `-status`, `-http-version`, `-url`, `-headers`, `-body`, `-timings`,
  `-history`, `-header`, `-text`;
- the conditions: `&http-error`, `&http-request-error` and its accessors and reasons,
  `&http-redirect-error` and its, `&http-timeout`, `&http-group-error`, `&http-exchange`.

**The verbs' signatures:**

- `http-request : Session Symbol String Any ... -> Response`;
- `http-get`, `http-head`, `http-post`, `http-put`, `http-patch` and `http-delete :
  Session String Any ... -> Response` (`228-294`, `801-806`);
- `call-with-response-port : Session Symbol String Any ... (Response Binary-Input-Port -> Any ...)
  -> Any ...` (`297-338`);
- `go : Symbol String Any ... -> Pending` (`379-398`), and `http-parallel` takes specs
  `(METHOD URL KEY VALUE ...)` (`449-474`).

Every call's body comes through the keys `body`, `form`, `params` and `body-length` (`call-keys`,
`call.sls:91`). So a multipart body could take any of these shapes, none chosen:

- a new call key beside `form`, with the precedents `body-and-form` and `body-not-allowed`;
- a widened `form` value;
- a new kind of `body` value;
- a low-level request `body` kind that the high level passes through.

**Constraints on a new body kind:**

- ADR-0025, decision 3, names the kinds: "a bytevector or a string, or a form", plus `params`, and
  "no JSON". The brief's §2 item 7 and §8 put `multipart/form-data` through `curl_mime` in v1's M8.
- ADR-0007 and global-constraints, "The high level": `(http-client)` reaches the low level through
  `(curl)` alone and holds no native object. A mime handle is the engine's (ADR-0012, decision 1).
- ADR-0023: the request is a property list, checked when made and again at submit on private copies,
  and it holds no procedure (`transfer.sls:1016-1028`).
- ADR-0032: a streamed body is sent at most once.
- ADR-0031: a producer is a call's `body`, called on the caller's thread.
- A group takes no producer (`stream-in-group`).

**Every place a new kind would touch, by today's code:**

- **The low-level request:**
  - `request-keys` (`transfer.sls:657-659`) for a new key; the body type check (`1138-1139`);
  - `checked-request`, `request-like`, `default-request` and the record (`1029-1055`, `1124-1191`,
    `1276-1311`); the accessors and `(curl)`'s exports and docs (`src/curl.sls:77-217`);
  - `request-checks` and `prepare-transfer`'s body copy (`3625-3718`); the plan (`3585-3595`).
- **Setting the transfer:** `sends-body?` (`4018-4020`), `sent-header-lines`' blank `Content-Type:`
  and `Expect:` (`4039-4046`), `method-settings` (`4115-4138`) and `set-transfer-options!`
  (`4169-4237`).
- **The owned lists:** `request-field-options` and `owned-option-names` (`1619-1632`, `1781-1798`).
- **Making and freeing:** `start-transfer!`, `free-transfer!` and the live record (`4057-4067`,
  `4257-4383`), with the engine's abandon path (`engine.sls:2204-2221`). Credentials' Digest rule if
  the body streams (`790-791`).
- **Native:** new bindings and exports (`native.sls:142-160`, step 6), a new kind in `native-kinds` and
  the owner registry.
- **The high level:**
  - `call-keys`, `call-body`, `call-pairs` and `call-request-of`'s refusals and its `bytes`/`sent`
    computation (`call.sls:91`, `565-578`, `633-713`); `with-form-type` (`240-243`);
  - `http-request-error-reasons` (`src/http-client/private/conditions.sls:134-138`);
  - `next-request`, `body-dropped?`, `body-header?`, `spent?` and `retry`
    (`exchange.sls:436-437`, `674-693`, `748-774`, `1046-1051`);
  - the choice of drive: a producer goes to `drive-stream`, anything else to `drive-exchange`
    (`src/http-client.sls:700-704`).
- **Tests that write the tables out:**
  - `test-request` (`request-keys`, `tests/test-request.sps:241`; `method-settings`, `494-502`);
  - `test-transfer` (`request-field-options`, owned names, nesting: `tests/test-transfer.sps:1344-1375`,
    `1689-1724`);
  - `test-unsupported` (`owned-names`, `312-336`);
  - `test-printed` (export rows);
  - `test-memory-safety` (`native-kinds`, `172-174`, `207`);
  - `test-constants` (prototype, callable and constant rows);
  - `tests/foreign-conventions.sls` (`conventions-table`).

---

## Questions the scope must answer

Each is a choice the maintainer makes, with what bears on it. None is recommended.

1. **Which layer carries multipart: `(curl)`, `(http-client)`, or both?** The high level holds no
   native object and reaches only `(curl)` (ADR-0007), and the engine owns mime handles (ADR-0012,
   decision 1). So a mime is made by the low level on the engine's thread, whatever surface sits on
   top. ADR-0025 decision 3 lists the high level's body kinds, and would be amended.
2. **Which part sources?** In-memory bytes or strings (`curl_mime_data` copies); files by path
   (`curl_mime_filedata`); streamed parts (`curl_mime_data_cb`); nested subparts
   (`curl_mime_subparts`).
   - ADR-0033 decision 3 kept file I/O the caller's for cookies.
   - `ca-file` is a precedent for taking a path.
   - filedata stats at the call and reads during the transfer, on the engine's thread (section 7).
   - A streamed part needs callables that copy and signal, and a producer per part. Today's drive
     feeds one producer per call, and a group takes none.
3. **May a multipart body be sent twice?** Redirects that keep a body (301 and 302 for `put`, `patch`
   and `delete`; 307; 308), retries, and libcurl's own resend all bear on it (sections 2 and 6), as do
   ADR-0032's at-most-once rule and `FRESH_CONNECT` for streamed parts, and `curl_mime_data_cb`'s note
   that a NULL seek makes "a resend ... not possible". Whether a mime of in-memory parts rewinds on
   its own is unmeasured.
4. **Which methods take one?** ADR-0023's fixed set; `CUSTOMREQUEST` beside `POST` "replaces only the
   method word" (M6 source reading); `body-not-allowed` for `get` and `head`; the 301/302 and 303 rules
   that turn a `post` into a `get`.
5. **The request's `Content-Type` and `Expect`.**
   - Today every body-sending transfer blanks both unless the caller names them (section 1). A
     multipart body depends on libcurl's boundary-bearing `Content-Type`.
   - What a blank or a caller's `Content-Type` does beside `MIMEPOST` is unmeasured: refused, replaced
     or passed?
   - Whether libcurl adds `Expect: 100-continue` to a mime post, and when, is unmeasured.
   - `EXPECT_100_TIMEOUT_MS` is the hatch's today.
6. **Part metadata.**
   - Encoding: UTF-8 or Latin-1.
   - Which bytes are refused in names, filenames and types.
   - Whether per-part headers are offered at all, and which part header names are refused, by
     `framing-header`'s precedent.
   - Whether `curl_mime_encoder` is offered.
   - Whether the default part type and the filename basename side effect are documented or
     controlled.
7. **The owned options.** `MIMEPOST` would move from twin to field, by precedent. Is `MIME_OPTIONS` a
   twin, a field, or the hatch's? It is unowned today and changes how names are escaped. Is
   `EXPECT_100_TIMEOUT_MS` owned? `HTTPPOST` stays a twin unless chosen otherwise. Each twin has been
   decided from a measurement.
8. **Ownership and counts.**
   - Today every slist is counted and freed by chez-curl, which collides with
     `curl_mime_headers(take_ownership)` and with `curl_mime_subparts`' handover.
   - The mime is a new native kind; are parts recorded too?
   - The floor's man page ties a mime to its target easy handle (7.85.0 to 7.86.x), so it would be
     made after `curl_easy_init` in `start-transfer!`.
   - Docs free it after `curl_easy_cleanup`, the precedent order.
   - An abandoned easy handle would keep its mime, as it keeps its jar hold.
9. **A libcurl built without mime.** Its stubs pass `foreign-entry?`, so `missing-api` cannot see one,
   and no feature bit names mime. Choices: refuse at load by a probe call, as the header API is probed
   (`native.sls:1307-1322`); refuse at submit; or fail the transfer with libcurl's NULL or 4. No lane
   builds one.
10. **Secrets.** Is a part's value, name or filename treated as a secret in printing and refusals?
    Records that hold parts would be opaque, with checked accessors; new exports get printed rows;
    refusals name a part by field or index (section 9).
11. **The header cap.**
    - Whether to cap at all, or document libcurl's per-version caps.
    - Count, bytes or both, and the default.
    - Whether a request or session key sets it, as `body-limit` does.
    - Where: the header callable on every transfer, or the walk.
    - Its refusal's reason and class (`body-limit`'s too-large precedent).
    - Whether 1xx heads, a proxy's `CONNECT` head and trailers count.
    - Bears on it: the n² walk runs on the engine's thread, twice for a streamed response; 7.85.0 caps
      nothing; 8.5.0 and later cap 300 KiB by source, and 8.20.0 and 8.23.0 5,000; the records' cap
      list omits 8.5.0 and 8.23.0.
12. **What M8 measures first.** Probes on the five Linux libcurls and the Mac, as M4 to M7 did:
    - the `Content-Type` and `Expect` interplay with `MIMEPOST`;
    - name, filename and type escaping under each `MIME_OPTIONS` value;
    - part-header conflicts;
    - which calls fire a part's callbacks, and whether `curl_mime_free` can block;
    - how each part kind sizes and frames a body: chunked versus `Content-Length`, over HTTP/1.1 and
      HTTP/2;
    - resend and rewind behaviour on a 307 and on a dead pooled connection;
    - the mime handle's lifetime against `curl_easy_cleanup`, under the memory gate.
