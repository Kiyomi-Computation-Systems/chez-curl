# The records' promises to document, on `fb62a0b`

Read-only, 2026-11-08, on `feat/m8-docs` off `main` at `fb62a0b`. Two parts: the docs survey's 45
rows (`surveys/docs.md` §7, read at `fbc6fce`) re-read against today's records, and every record
line added or changed since `fbc6fce` that promises a thing is documented, listed, named or told
to a caller.

"README.org today": **kept**, it says so; **partly**; **no**; **superseded**, a later record
withdrew or changed the promise; **n/a**. "Src" means only a source comment says it. Lines are
today's: the amended records' lines moved (ADR-0003 +1, ADR-0009 +1, ADR-0022 +1, ADR-0025 +1,
ADR-0037 +1, `global-constraints.md` +17 from its line 336 on), mapped by `git diff -U0
fbc6fce..HEAD` hunks and each spot-read.

## What was carried over, and why

- **README.org is unchanged since `fbc6fce`** (`git diff --stat fbc6fce..HEAD -- README.org`:
  empty), so each row's README.org column stands as the survey read it, but row 41.
- **The cited records are unchanged in content:** the brief, the harness, M3 to M7 plans and
  ADR-0002, 0008, 0016, 0018, 0019, 0020, 0024, 0026, 0030 to 0036 have no diff since `fbc6fce`;
  ADR-0003, 0009, 0022, 0025, 0037 and `global-constraints.md` were amended, each by an added
  status line or a new section after the cited lines, which I read: none withdraws a row's
  promise but ADR-0037's (row 41).
- **Row 41 changed:** `SUPPRESS_CONNECT_HEADERS` is owned since M8 slice 2 (ADR-0037, amended
  2026-11-06, :267-274; ADR-0009, amended 2026-11-06, :493-503; `src/curl/private/transfer.sls:2312`,
  `owned-option-names`). README.org:237-238 still says it "stays" the hatch's: wrong today.

## 1. The survey's 45 rows

| # | Record and line (today's) | Promise | README.org today | Topic |
|---|---|---|---|---|
| 1 | brief:56-61 | N concurrent requests need one engine thread, not N caller threads: "the single most important thing to get into the README" | partly: :567-571, a group runs many calls on one thread; nothing on the engine | README.org's taste; the high level: groups; the low level: engines |
| 2 | ADR-0002:246-248; M3 plan :469 | reference `(curl)` once before starting threads that use it (`cyclic dependency`) | no | the low level: engines |
| 3 | ADR-0003:120-122 | the supported-platforms docs say Ubuntu 22.04, Debian 11 and RHEL 9 need a newer libcurl, by `CHEZ_CURL_LIBCURL` | no | TLS and the environment: finding libcurl; README.org status |
| 4 | ADR-0008:72-74 | a caller wanting RFC 3986's strict verdict runs uriparse first; the docs list curl's leniencies | no | URLs (no page in the plan's list; see README.md, question 2) |
| 5 | ADR-0008:89-90, :149, :181 | the leniencies listed by version, from `test-url`'s rows, non-ASCII ones among them | no | what varies by libcurl |
| 6 | ADR-0009:18-20, :94-96 | the hatch documented as unsupported; what it checks; that it can change tested behaviour | kept, :335-348 | the hatch |
| 7 | ADR-0009:318; :319-320 | what `VERBOSE` and `NOPROGRESS` print; a path at `/dev/stdin` is the caller's | kept, :349-352 | the hatch |
| 8 | ADR-0009:483-488; ADR-0036:117-121; M7 plan :203-206 | `FAILONERROR`, `AUTOREFERER`, `KEEP_SENDING_ON_ERROR`, `UNRESTRICTED_AUTH`, `DISALLOW_USERNAME_IN_URL` stay the hatch's, "documented"; `LOGIN_OPTIONS` and the rest changed nothing | no (src: `transfer.sls`, the owned list's comment) | the hatch |
| 9 | ADR-0016:14-17, :28-31, :39, :52, :86; global-constraints :18-21, :25-28 | `** Requirements` holds the three floor lines | kept, :11-15, by `check-floors` | README.org: Requirements |
| 10 | ADR-0016:57; harness plan :77-79 | `docs/` joins `check-floors` when it states requirements | n/a: `docs/` is empty; the plan's quick start states no floor (M8 plan :253-254) | quick start |
| 11 | ADR-0018:101-103 | a `pkcs11:` CA path documented or refused | refused, and kept, :51-53 | TLS and the environment |
| 12 | ADR-0018:185; ADR-0024:62-63; M4 plan :316; global-constraints :293-296 | `SSLKEYLOGFILE`, `OPENSSL_CONF`, then `CURL_SSL_BACKEND`, documented **in README.org** | kept, :54-67 | TLS and the environment (README.md, question 3: the records name README.org) |
| 13 | ADR-0024:118, :281-283, :307 | `CURL_SSL_BACKEND=secure-transport` named, as `secure-transport` | kept, :59-67 | TLS and the environment |
| 14 | ADR-0024:336-343; global-constraints :268-271 | a proxy variable's control-byte userinfo goes direct on 7.85.0 and 8.5.0 | kept, :35-39 | TLS and the environment; what varies by libcurl |
| 15 | ADR-0019:108-111; M3 plan :470 | on 7.85.0 and 7.86.x a cancel or timeout during a stalled lookup holds the engine up to 10 s | partly: :575-578, a group's escape alone | what varies by libcurl; the low level: engines |
| 16 | ADR-0019:220-226; M3 plan :471-472 | on 8.20.0 each stopped engine leaves two resolver threads for about 2 s | no | what varies by libcurl |
| 17 | ADR-0020:149-152; M3 plan :473-474 | on 8.23.0, after six silent closes within a second, the next transfer fails 55 | no | what varies by libcurl |
| 18 | ADR-0022:27-35, :225-227, by the M4 plan :620-621 and M5 plan :753-754 | the classes' version variance: one failure's code and class move by version | no (src: `curl.sls:535-546` lists the codes) | errors; what varies by libcurl |
| 19 | ADR-0025:4, :78-83; global-constraints :711-714 | a second escape as a session's close starts can leave its engine running: documented, not prevented | no (src: `http-client.sls:198-212`) | the high level: sessions |
| 20 | ADR-0025:116, :144-149 | the checks' hold grows with the input, at sizes the documentation names | no (src: `http-client.sls:84-111`) | the high level: bodies |
| 21 | ADR-0026:56-63; M5 plan :754-756 | libcurl's own resends multiply a policy's attempts: a `get` retried 3 times can reach a server 18 times | no (src: `http-client.sls:14-18`) | the high level: redirects and retries |
| 22 | M5 plan :753-757 | the redirect rules and the headers that follow | kept, :460-479 | the high level: redirects and retries |
| 23 | M5 plan :753-757 | the retry rules | no: beside other topics alone (:221-224, :514-518, :543-545) | the high level: redirects and retries |
| 24 | M5 plan :320 | every other header follows a redirect, an `X-Api-Key` among them | kept, :468-470 | the high level: redirects and retries |
| 25 | M5 plan :756-757 (its §2, :74-130) | two `Location` headers: the first followed on 7.85.0, 8.5.0 and 8.7.1, a failure, 8, on 8.20.0 and 8.23.0 | no (src: `http-client.sls:298-301`) | what varies by libcurl |
| 26 | M5 plan :453-457; global-constraints :775-777 | a group's join can wait on a stalled lookup, and a second Ctrl-C abandons it | kept, :575-578 | the high level: groups |
| 27 | M5 plan :760-767 | a group call's compounded timer raise and an expiry's re-entry refusal, "both documented" | superseded: ADR-0025, amended 2026-11-05, removed both | n/a |
| 28 | ADR-0030:70-78; ADR-0034:58-59; M6 plan :236-237; global-constraints :871-872 | a paused HTTP/2 stream beside an active one receives into libcurl's memory, "documented, by version" | partly: :378-381, "tens of megabytes", no per-version figure | the low level: streams; what varies by libcurl |
| 29 | ADR-0031:80; M6 plan :598 | a consumer slower than the bound meets `&http-timeout`, beside the forms | kept, :382-383, :506-508 | the high level: streams |
| 30 | ADR-0031:4, :114-119; M6 plan :929; global-constraints :867-870 | the HTTP/2 3xx that never ends: pass `timeout-ms` | kept, :556-561 | what varies by libcurl; the high level: streams |
| 31 | ADR-0032:89 | a streamed upload costs a connection of its own | kept, :425-431 | the low level: streams |
| 32 | M6 plan :478, :481, :524-527 | a port never closed leaves its transfer paused; prefer `get-bytevector-some`; a PROC that never reads starves its upload | kept, :392-393, :384-386, :509-511, :546-550 | streams, both levels |
| 33 | M6 plan :573-599, :976 | how to stream each way, and §3.7's documented rows | kept, :354-458, :481-563 | streams, both levels |
| 34 | ADR-0034:93-96; M7 plan :157-159 | prior knowledge beside `proxy environment` is ignored | kept, :92-94, :206-208 | the high level: the HTTP version |
| 35 | M7 plan :153-155 | a redirect to `https://` by prior knowledge fails the call | kept, :89-91 | the high level: the HTTP version |
| 36 | M7 plan :163 | the hatch's `PIPEWAIT` stays allowed | kept, :100-101 | the HTTP version; the hatch |
| 37 | M7 plan :358-362 | the codes of prior knowledge against an HTTP/1.1 server, by version | partly: :90-91, "depends on the libcurl and on timing", no codes | what varies by libcurl |
| 38 | ADR-0036:86-87; M7 plan :363-365 | the Digest algorithms each version supports, and 8.23.0's UTF-8 user name | partly: the user name, :127-129; the algorithms, no | the high level: auth; what varies by libcurl |
| 39 | ADR-0036:103; :115 | Digest sends a body twice to a server that never challenges; no length is checked | kept, :123-126, :144-147 | the high level: auth |
| 40 | ADR-0037:91-92; M7 plan :366-370 | the refused `CONNECT`'s code, and which builds stall inside a tunnel | kept, :213-224 | the high level: proxies; what varies by libcurl |
| 41 | ADR-0037:185-187; :253 | `SUPPRESS_CONNECT_HEADERS`, `PROXY_SERVICE_NAME`, `SOCKS5_AUTH` and `CONNECT_TO` stay the hatch's | **partly superseded:** `SUPPRESS_CONNECT_HEADERS` is owned (ADR-0037, amended 2026-11-06, :267-274); README.org:237-238 is wrong for it, right for the other three | the hatch; the high level: proxies |
| 42 | ADR-0035:64-65; M7 plan :371-384 | the cookie rules vary by version, and the docs say so | kept, :262-263, :280-291 | the high level: cookies; what varies by libcurl |
| 43 | ADR-0035:137 | 7.85.0's hang through a long URL | kept, :295-300 | what varies by libcurl |
| 44 | ADR-0035:142; M7 plan :320; global-constraints :897-900 | a load's cost; each jar procedure waits with no bound | kept, :292-294, :307-309 | the low level: jars |
| 45 | ADR-0035:180 | `CONNECT_TO` stays the hatch's, its cookies following the URL's host | kept, :312-314 | the hatch; cookies |

**Count:** kept 24, partly 5, partly superseded 1 (row 41), no 13, n/a 1, superseded 1: 45. The
survey had kept 25; row 41 left it.

## 2. M8's own promises (records added or changed since `fbc6fce`)

Grepped the added lines (`git diff -U0 fbc6fce..HEAD -- .plans/decisions
.plans/global-constraints.md .plans/2026-11-06-m8-plan.md`, 1,292 lines) for `document`, `the
docs`, `README`, `listed`, `named`, `told`, `says`, `say`, and read each hit in place. Left out:
lines about the slice's own work (the plan's §1 table, §2, §7, §14), rejected options (ADR-0038:101,
ADR-0039:104), the survey's numbers (ADR-0038:59-66), and "named" meaning a measurement named a
race (M8 plan :497).

| # | Record and line | Promise | README.org today | Topic |
|---|---|---|---|---|
| M1 | M8 plan :125-128 (§3.1) | **the default types:** "The docs list the extensions libcurl knows": a part's type from the filename's extension, then the path's for a file part, then `application/octet-stream` for a file part; none for a data part with no filename or an unknown extension | no | the high level: forms and multipart; the low level: requests; what varies by libcurl (`by-version.md`, default types) |
| M2 | M8 plan :178-180 (§3.3); ADR-0040:58-60 (decision 4); ADR-0040:105 | **the cap's earlier refusals:** libcurl's refusals before any line reaches the callable keep their codes, held in `test-headers`' table, "listed in the docs", by version | no | what varies by libcurl; errors |
| M3 | M8 plan :316-323 (§3.8, slice 2) | each of slice 2's rows by version: a 102,400-byte line (27/100; over HTTP/2 27, 16 or 56, or 52, 56 and 16 when HPACK cannot code it), 7.85.0's HTTP/2 head of 128 KiB (56), nghttp2's limit on a head and on trailers, a 5,000-byte trailer line (56/100), 5,000 HTTP/2 trailers on 8.23.0 (56), 7.85.0's HTTP/2 trailers among the headers, 8.7.1's rows, and the cap's own code (23, or 56 over HTTP/2 on 8.7.1): "The docs list each, by version, from these tables" (:333) | no | what varies by libcurl |
| M4 | M8 plan :324-333 (§3.8, slice 3) | each of slice 3's rows by version: `CURLINFO_REQUEST_SIZE` for multipart; a file grown, shrunk, removed after the engine's check; a FIFO; the default types; the resends, a reset inside a large part racing 55 | no | what varies by libcurl; the high level: forms and multipart |
| M5 | M8 plan :238-239 (§3.4); ADR-0022:252-255 (amended 2026-11-07) | the request size's documentation says a multipart body's holds the head alone on 7.85.0 and 8.5.0 | no; src keeps it: `conditions.sls:706-708`, `curl.sls:520-522` | errors (`curl-transfer-error-request-size`) |
| M6 | M8 plan :450-451 (§11, 7) | the cap's values are constants: "`header-limit` names the cap, and the docs say its values" (1,000 lines, 102,400 bytes) | no; src keeps it: `conditions.sls:637-643` | errors; the low level: requests |
| M7 | ADR-0039:87-88 (decision 3), revised by :140-146 | a file changed after submit is the caller's: "the docs say what libcurl then sends" | no | the high level: forms and multipart |
| M8 | ADR-0039:118-119 (consequences) | a path swapped after submit, to a FIFO or `/dev/stdin`, still reaches libcurl; the engine's check narrows the window and cannot close it: "the docs say so" | no | the high level: forms and multipart |
| M9 | ADR-0039:147-151 (amended 2026-11-06, decision 2); M8 plan :466-467 (§12, 3) | **the FIFO window:** a path swapped to a FIFO after the engine's check holds the engine's thread for ever: every transfer on it stalls, and `curl-engine-stop` and a session's close never return; "the docs say so, and that a caller who cannot trust its file system reads the file and sends a data part" | no | the high level: forms and multipart; the low level: engines |
| M10 | ADR-0039:211-213 (amended 2026-11-07, decision 2); global-constraints :963-966 | **a file changed after the check, by version:** "the docs say, by version, what libcurl then sends, the overrun among it": grown, sent past `Content-Length` on 7.85.0 and 8.5.0 (400 or 92), an unterminated body answered 200 on 8.20.0, 8.23.0 and 8.7.1; shrunk, a stall over HTTP/1.1 until `timeout-ms` on 7.85.0 and 8.5.0 (for ever with none), 92 over HTTP/2 there, 26 on 8.20.0 and 8.23.0; removed, 26 everywhere (:185-198); and the data-part advice | no | what varies by libcurl; the high level: forms and multipart |
| M11 | ADR-0039:231-237 (after slice 3's review) | **pseudo-files:** a procfs or sysfs file whose size is not its content passes the regular-file rule; "the docs say that such a file sends what a shrunk one sends, by version, and that a caller reads it and sends a data part" (`/proc/self/status` sends an empty part, 200) | no | the high level: forms and multipart; what varies by libcurl |
| M12 | ADR-0039:12-14, :89-92 (decision 4); ADR-0003:159-169 (amended 2026-11-07) | **a libcurl without mime is told,** by a named reason at submit, `multipart-unsupported`, every other request working | no; code keeps it: `transfer.sls:4334-4340` | errors; TLS and the environment: finding libcurl |
| M13 | ADR-0039:77-79 (decision 1) | a caller's `Content-Type` beside a multipart body refused "by a named reason" | no; code keeps it: `multipart-content-type`, `transfer.sls:1469-1473` | errors; forms and multipart |
| M14 | ADR-0040:53-56 (decision 2); ADR-0022:240-248 (amended 2026-11-06) | the cap's refusal is a named reason of `&curl-too-large`, `header-limit`, whatever libcurl's code (0 for 8.5.0's HTTP/2 trailers) | no; code keeps it: `conditions.sls:637-643, 921-923`; `curl.sls:543` omits it (inventory: a disagreement) | errors |
| M15 | ADR-0040:138-140 (amended 2026-11-06, 6) | `HTTP_TRANSFER_DECODING` 0, the hatch's, puts trailers in the body, where `body-limit` bounds them and nothing is stored as a header: "the docs say so" | no | the hatch |
| M16 | ADR-0037:267-274; ADR-0009:493-503 (amended 2026-11-06) | `SUPPRESS_CONNECT_HEADERS` owned, refused `owned-option`; `PROXY_SERVICE_NAME`, `SOCKS5_AUTH` stay the hatch's | no: README.org:237-238 says the opposite for the first | the hatch |
| M17 | ADR-0009:505-511 (amended 2026-11-07) | `MIME_OPTIONS` owned, refused `owned-option`; `MIMEPOST` the body field's; `EXPECT_100_TIMEOUT_MS` stays the hatch's | no (no record line asks it documented; README.org's hatch list would be partial without it) | the hatch |
| M18 | ADR-0038:90-91 (decision 5); M8 plan :243-245 (§3.5) | **the platforms:** v0.1.0 claims Linux amd64 and macOS arm64, macOS arm64 meaning Apple's 8.7.1; "the docs name Linux arm64 and macOS amd64 as untested" | no (`** Status` is empty) | README.org: status |
| M19 | M8 plan :252 (§3.5) | the page "what varies by libcurl": every per-version behaviour a caller meets, the cap's earlier refusals among them | no (no such page) | what varies by libcurl |
| M20 | M8 plan :245-246, :253-254 (§3.5) | README.org says how to install from a clone, with the library path and `CHEZ_CURL_LIBCURL`; the quick start links Requirements and states no floor | no | README.org: install; quick start |
| M21 | M8 plan :270-273 (§3.5); global-constraints :979-981 | the docs leave out slice history, logs, CI notes, ADR numbers, and link nothing in `.plans/` | n/a: a rule of the pages, which `test-docs` holds (:264-266) | every page |
| M22 | M8 plan :277-279 (§3.6) | CHANGELOG's Known limitations: the platforms not run, "the per-version behaviour the docs list" | n/a: slice 5 | the release |
| M23 | ADR-0023, amended 2026-11-07 (`curl-request-with` takes `url`) | no doc promise; a new key of an export's surface, which `reference.md` must list | no | the low level: requests |

**Count:** 23 rows; README.org keeps none of M1 to M20 (M5, M6 and M12 to M14 are kept by a source
comment or the code alone); M21 and M22 are n/a here.

## 3. The records that name README.org as the place

The plan moves most of README.org's sections into `docs/`. These lines promise README.org by
name, so a page that takes their text leaves the record naming the wrong file (README.md,
question 3): `global-constraints.md:295-296` ("documented in README.org"); ADR-0024:62-64, :281-283,
:307, :343; ADR-0009:318, :320 ("the README says"); ADR-0030:78; ADR-0031:80, :119; ADR-0032:89;
ADR-0016:28-31 and `global-constraints.md:18-21`, `check-floors`' own (the Requirements stay in
README.org, by the plan).
