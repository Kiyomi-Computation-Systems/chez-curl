# ADR-0025: The high level's surface: explicit sessions, prefixed verbs, bodies, forms and params

- **Status:** Accepted; amended 2026-10-27: params are written into the URL, then parsed whole
  (ADR-0028); amended 2026-10-27: a second escape during a session's close is documented, not
  prevented; amended 2026-11-05: a call's checks run in one critical section, and after
  its review, 2026-11-06: every guard around a critical wind
- **Date:** 2026-10-27
- **Scope:** chez-curl v1, `(http-client)`, from M5
- **Settles:** three questions the M5 plan raised about `(http-client)`'s public surface. The
  maintainer chose each on 2026-10-27, each the recommended option.
- **Related:**
  - brief §6.2 and §6.3, the high level and its thread sugar;
  - [ADR-0007](0007-one-repo-checked-seam.md) and [ADR-0010](0010-names-curl-and-http-client.md):
    `(http-client)` reaches the low level only through `(curl)`;
  - [ADR-0012](0012-engine-thread-owns-every-handle.md): concurrency costs no threads;
  - [ADR-0023](0023-the-public-request.md), the low level's request, which the high level builds.

## Context

M4 made the low level public: a request made from a property list, an engine that runs it, a
token to await, and a mailbox for completions. M5 builds the high level on it (brief §8): sessions,
the verbs, redirect and retry policy, and the thread sugar.

The brief sketches the verbs as `(get s url)` and `(post s url ...)`, after Racket's
`http-easy`, beside `http-parallel` and `call-with-http-session`. Every name `(curl)` exports
carries the `curl-` prefix. The brief names ad-hoc scripting as the first consumer, which a
session made for one call taxes. And it leaves decoding to the caller: chez-curl is not a JSON
library (brief §3).

## Decision

1. **The verbs carry the `http-` prefix:** `http-get`, `http-head`, `http-post`, `http-put`,
   `http-patch` and `http-delete`, and `http-request`, which takes the method. Each takes the
   session first. A caller who wants short names renames them on import.
2. **Every call takes an explicit session.** `(http-client)` has no default session, and starts
   no thread a caller did not ask for. A session owns one engine, and `call-with-http-session`
   stops it when its procedure returns or escapes.
3. **A call's body is a bytevector or a string, or a form; a call may add params to the URL:**
   - `body`: a bytevector, sent as is, or a string, sent as its UTF-8 bytes;
   - `form`: a list of name and value string pairs, sent as
     `application/x-www-form-urlencoded`;
   - `params`: a list of name and value string pairs, added to the URL's query, encoded the
     same way;
   - no JSON: encoding and decoding stay the caller's (brief §3).

### Rejected

- **Bare verbs, `get` and `post`, as the brief sketched.** They read well, and clash with a
  caller's own definitions. `(prefix (http-client) http:)` would give `http:get`, but the
  library's other names would then read `http:http-parallel`.
- **A lazy default session as well.** It would start an engine thread on a first call and never
  stop it, so it would live until the process exits, a path no test covers.
- **Bytes only, as the low level takes them.** Every caller would percent-encode their own
  forms and queries, and get the encoding's edge cases wrong in their own ways.

## Consequences

- **A one-off script writes a session:**
  `(call-with-http-session (lambda (s) (http-get s url)))`.
- **The form encoding is chez-curl's,** in Scheme, after the WHATWG URL Standard's
  `application/x-www-form-urlencoded` serializer, so it is tested on every byte. Params reach
  the URL through libcurl's URL API, never by Scheme splicing a string (ADR-0008).
- **`(curl)` gains URL functions the high level needs:** appending a query, reading a URL's
  parts, resolving a header's bytes, and setting a fragment. The M5 plan, §3.1, names them.

## Amendment, 2026-10-27: params are written into the URL, then parsed whole (ADR-0028)

- **The consequence above, "never by Scheme splicing a string", no longer holds.** M5 slice 1
  measured `CURLU_APPENDQUERY` and found that setting a query part changes its hex case, to lower
  on 7.85.0, 8.5.0 and 8.20.0 and to upper on 8.23.0, where parsing a whole URL keeps it on all
  five.
- **So `curl-url-append-query` writes the URL** from what `curl_url_get` gives back, the
  query's separator and the caller's encoded part, then has `curl_url` parse it whole, and
  checks that the query came back as written (ADR-0028). Every URL is still parsed by
  `curl_url` (ADR-0008), and `params` go out as chez-curl encodes them on every libcurl.

## Amendment, 2026-10-27: a second escape during a session's close is documented, not prevented

- **Found by M5 slice 1's review** (Opus, read-only), and reproduced there: an escape, by a timer
  or an escaping Ctrl-C handler, that lands at the start of `call-with-http-session`'s after
  thunk skips `curl-engine-stop`, and the session's engine, a thread and its multi handle,
  lives on until the process exits. The close waits for the engine's thread, so it cannot run
  with interrupts off, as the drive's cancel now does.
- **Decided by the maintainer, 2026-10-27, the recommended option:** `(http-client)` says so,
  as the M5 plan already says a second Ctrl-C abandons a group's join (§3.7). `(curl)` keeps its
  surface: no non-waiting stop request is added for it.
- **Rejected:** a non-waiting `curl-engine-request-stop` in `(curl)`, which a critical after
  thunk would call first. It would grow the low level's public surface past the URL functions
  the M5 plan names.

## Amendment, 2026-11-05: a call's checks run in one critical section

- **Carried since M5** (the M5 plan, §10): `call-state`, which makes a call's exchange for
  `http-request`, `call-with-response-port`, `go` and `http-parallel`, guards its checks with a
  `guard` that compounds every condition with `&http-exchange`. A raise that is not the call's
  own lands there too. Measured after M7 ([`research/m7/carried/guard/`](../research/m7/carried/guard/)),
  at all four entries, by a seam that blocks inside the checks:
  - a Ctrl-C or timer handler's raised condition left compounded;
  - a continuable `&warning` its handler returned from became `&non-continuable`, so the call
    could not resume;
  - a non-condition raised inside the URL parse, `#f` or a symbol, came back as
    `call-with-parsed-url`'s re-entry refusal: the guard declined it and rewound into the parse's
    critical wind, whose before thunk refuses re-entry;
  - an engine's expiry, its fuel swept a tick at a time, landed inside the checks 3,023 times;
    in 881 of them the resumed call raised that refusal.
- **Decided by the maintainer, 2026-11-05, the recommended option:** the checks run in one
  `critical-section`, the guard inside it taking every raise and answering it as data, raised
  once the section ends: the pattern the drive's submit and the group's sections already follow.
  A handler's raise then comes as the section ends, as raised; a continuable one resumes the
  call; an expiry lands after the checks; a refusal is compounded as before, and a caller's
  handler sees it with interrupts on. Measured on a prototype: all of that at every entry, 0 of
  5,600 fuels inside the checks, and the high level's ten suites, 647 tests, passing.
- **Its cost:** a Ctrl-C and every other thread's collection wait for the checks. An ordinary
  call holds under 0.5 ms; a large body no longer than today, whose copy already holds with no
  section; the longest new holds are at sizes the documentation names: 0.83 s for a 16 Mi-char
  form value, 0.27 s for a 7.9 MB URL.
- **Rejected:**
  - each refusal compounding itself where it is raised, each `(curl)` call in a section of its
    own. It behaves the same and holds less at those sizes, but it changes about fifteen
    signatures in `call.sls`, and a later refusal that forgets to compound loses its
    `&http-exchange` silently;
  - leaving it, documented, which would also have to document the two cases found here.
- **As built.** `call-state` holds its checks in one `critical-section`, its guard inside taking
  every raise `#t`, a condition compounded with `&http-exchange`, and raises after the section;
  a private seam, `drive-checks-gate-set!` in `(http-client private drive)`, runs a test's
  procedure at the checks' start and end, inside the section. `tests/test-call-checks.sps`
  holds it at all four entries: a SIGINT child's planted condition leaves as raised, a
  continuable one resumes the call to 200, a timer likewise, an engine swept a tick at a time
  lands no expiry inside the checks, and a refusal's handler runs with interrupts on. Today's
  `call-state` fails 20 of its 22 tests; test-group's two engine sweeps no longer accept the
  re-entry refusal.
- **After the branch's review, 2026-11-06** (Opus, read-only;
  [`research/m7/carried/review/`](../research/m7/carried/review/)), two findings, each
  reproduced, and the maintainer's answers, each the recommended option:
  - **The same trap outside the checks.** A redirect's step parses URLs with interrupts on,
    inside guards that take `&curl-url-error` alone: an engine swept a tick at a time across a
    302 made 1,498 of 8,000 resumed calls raise `call-with-parsed-url`'s re-entry refusal, and a
    timer's continuable raise, which the caller's handler returned from, became it 679 times;
    `(curl)`'s `curl-submit` does the same in its proxy URL's check. **Decided:** every guard in
    `src/` whose body can enter a critical wind with interrupts on is audited, and each that can
    be reached so runs inside a `critical-section`, its guard taking every raise as data, raised
    once the section ends; the redirect drives' step as a group's `turn!` already does, its hold
    measured first.
  - **The checks' hold grows with the input, unbounded:** a 64 M-char URL, which libcurl then
    refuses, held a Ctrl-C 0.86 s, and a 64 M-char form value 1.6 s. **Decided:** a URL longer
    than libcurl's 8,000,000-byte cap is refused as the checks begin, as libcurl refuses it, so
    a URL's hold stays near a 7.9 MB one's; the other holds are documented as growing with their
    input, and every thread, the engine's among them, stalls once a collection falls due during
    one.
  - **As built after the review.** An audit of every guard in `src/` that can reach a critical
    wind whose before thunk refuses re-entry, `get-part`'s, `call-with-flagged-url`'s and
    `call-with-c-bytes`'s, with interrupts on, found two kinds of site reachable, each now
    inside a section of its own whose guard takes every raise as data: a single call's
    redirect step, `drive-exchange`'s and `drive-stream`'s, through `in-step-section`; and
    `curl-submit`'s two URL parses, its URL's and its proxy URL's, through `in-section`. A
    group's step already ran in `turn!`'s. Measured first, the largest step any libcurl
    accepts held 168 to 181 ms (7.85.0's 100,003 headers, a 102,387-byte `Location` and a
    1,048,544-char URL; 8.20.0 124 to 139 ms; 8.23.0 157 to 181 ms). The review's probes then
    gave no re-entry refusal: 0 of 1,498, 679, 579 and 375. The cap is `checked-input`'s, in
    `(curl private url)`, and `call-state` reads it just after the session's check: a URL of
    more than 8,000,000 chars is refused as libcurl refuses it, `malformed-input`, code 3, in
    0.01 to 0.04 ms where it took 170 to 180 ms; two orders change, such a URL refused before an
    unknown key, and one holding U+0000 read as `malformed-input`, not `embedded-nul`.
    `(http-client)`'s header gives the other holds as rates: a bytevector body 0.4 to 0.5 ms a
    MiB, a string body 2 to 2.7 ms a Mi chars, a form value 31 to 52 ms a Mi chars, headers and
    params 0.4 to 0.7 ms a thousand, a URL about 29 ms a million chars to the cap.
    `tests/test-call-checks.sps` holds all of it, 49 tests. Two older tests changed with it:
    test-transfer's flip tests sleep 1 ms after a refusal, since under Valgrind a loop whose
    refusal waited for nothing ran through the flipper's CR states, 5 runs of 22 once the
    submit's parse had a section and 0 of 12 before; test-unsupported's twin, which then failed
    CI's memory job at `473b1b4`, races so on `main` too, 6 runs of 20, and got the same pause; and a group's step row counts 1 or 2 transfers started, since a
    group submits the next hop inside its step's section, before a pending Ctrl-C runs, and the
    raise's cancel then races the engine starting it.
