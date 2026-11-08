# Stale lines outside `.plans/`, on `fb62a0b`

Read-only, 2026-11-08. Every tracked file outside `.plans/` searched, nothing changed:

```
git grep -n -I -i -E 'not yet|unreleased|on main|for now|later slice' -- . ':!.plans'   # 29 lines
git grep -n -I -E 'TODO|FIXME|M[0-9] slice' -- . ':!.plans'                              # 138 lines
```

`git grep` does not descend into the `vendor/chez-srfi` submodule. 166 lines, one
(`packaging/debian-prereqs.txt:4`) matching both searches. No line says "unreleased", and no
`FIXME` exists.

## What needs the slice's attention

| Line | Text | Why |
|---|---|---|
| `packaging/debian-prereqs.txt:4` | `# NOT YET EXERCISED. M0 slice 5 adds the workflow, and its first run is the` | stale: CI has run it since PR #38; the plan removes it (§3.5) |
| `README.org:66` | `turns the keychain fallback off too, but chez-curl does not read it yet,` | not matched by the searches ("not ... yet"); found by `git grep -w yet` on the shipped files; a promise of later work in a user page |
| 41 lines in `src/` | `(M7 slice 3's review)`, `(M8 slice 3)` and the like: `src/curl.sls:285`, `src/http-client.sls:697`, 23 in `transfer.sls`, 6 in `engine.sls`, 3 in `conditions.sls`, 2 in `native.sls`, 2 in `http-client/private/conditions.sls`, 1 each in `url.sls`, `constants.sls`, `exchange.sls` | record citations in source comments; `src/curl.sls:285` is in `curl-response-timings`' export comment, which a hand-written reference must not copy (`inventory.sexp`, `cites`) |
| `AGENTS.md:186` | `libcurl garbage there; that is not yet measured.` | a record of the repository's, not a user page; ships if the archive carries AGENTS.md (survey §5, question 9) |

Everything else is not stale: 21 lines of plain English describing a state ("not yet freed",
"not yet done", "not yet entered"); 5 `TODO:` strings that are `test-drift`'s printed row's
placeholder, by design (`tests/test-drift.sps:199`, and the four suites that print a missing row);
2 false positives (`main-thread`, a variable; `for NOW`, a parameter); 2 lines of a check's own
prose ("a library a later slice adds is imported with no edit here",
`tests/check-nothreads.sps:14`, `tests/test-check-nothreads.sps:224`); and 91 slice citations in
`tests/` comments, which are the suites' records.

## Every line

| Line | Text | Class |
|---|---|---|
| AGENTS.md:186 | libcurl garbage there; that is not yet measured. 'test-collect-safe' requires the | AGENTS.md: a record (outside the docs) |
| packaging/debian-prereqs.txt:4 | # NOT YET EXERCISED. M0 slice 5 adds the workflow, and its first run is the | stale: the plan removes it (§3.5) |
| src/curl/private/engine.sls:306 | ;; cookie jars, each made and not yet freed, live or closing; and its | plain English: a state (not yet freed, done, entered) |
| src/curl/private/engine.sls:689 | ;; has closed but which is not yet done (completion-stall!). | plain English: a state (not yet freed, done, entered) |
| src/curl/private/engine.sls:1227 | ;; thread read the outcome, the token not yet done; either | plain English: a state (not yet freed, done, entered) |
| src/curl/private/engine.sls:1571 | ;; and not yet freed, each read in a hold of the engine's mutex: private | plain English: a state (not yet freed, done, entered) |
| src/curl/private/engine.sls:1955 | ;; a token whose outcome is read, its request stream closed, and not yet | plain English: a state (not yet freed, done, entered) |
| src/http-client.sls:425 | ;; that had not yet entered its call raises closed, and one that had | plain English: a state (not yet freed, done, entered) |
| src/http-client.sls:454 | ;;   queued in the engine, not yet taken in by its thread, is completed | plain English: a state (not yet freed, done, entered) |
| src/http-client/private/drive.sls:110 | ;;;     not yet stepped; waiting, a retry's wait, keeping its slot, until a | plain English: a state (not yet freed, done, entered) |
| src/http-client/private/drive.sls:146 | ;;; queued in the engine, not yet taken in by its thread, which completes | plain English: a state (not yet freed, done, entered) |
| src/http-client/private/drive.sls:456 | ;; produce! holds it, not yet taken; the piece taken from it, held until | plain English: a state (not yet freed, done, entered) |
| src/http-client/private/drive.sls:579 | ;; Whether LEG's token has published a head not yet known final: a hop's, | plain English: a state (not yet freed, done, entered) |
| src/http-client/private/drive.sls:1448 | ;; GROUP's draining tokens, those not yet ended alone. | plain English: a state (not yet freed, done, entered) |
| src/http-client/private/drive.sls:1628 | ;; winds, and a resumed run must enter no more, so a call not yet entered | plain English: a state (not yet freed, done, entered) |
| src/http-client/private/drive.sls:1776 | ;; under the engine's mutex; a token still queued in the engine, not yet | plain English: a state (not yet freed, done, entered) |
| tests/check-nothreads.sps:14 | ;;; library a later slice adds is imported with no edit here. It puts the | check's own prose: a library a later slice adds |
| tests/test-call-checks.sps:537 | ;; step, a step-start not yet | plain English: a state (not yet freed, done, entered) |
| tests/test-call-checks.sps:595 | ;; handler ran inside a step, its marks a step-start not yet ended; and | plain English: a state (not yet freed, done, entered) |
| tests/test-check-nothreads.sps:224 | ;; a scan written out in this suite, so that a library a later slice adds is | check's own prose: a library a later slice adds |
| tests/test-cookies.sps:825 | ;; LINE with its expiry as expiry-kind writes it, for NOW, when it has | false positive (NOW, a variable) |
| tests/test-mailbox.sps:528 | (list (awaited t) (eq? delivered t) (eqv? ran-on main-thread)))) | false positive |
| tests/test-mailbox.sps:540 | (list (awaited t) (eq? delivered t) (eqv? ran-on main-thread))))))) | false positive |
| tests/test-memory-safety.sps:852 | ;; object made but not yet recorded where its free finds it, at any of those | plain English: a state (not yet freed, done, entered) |
| tests/test-stream-call.sps:1546 | ;; produce!'s before thunk, the producer not yet entered. | plain English: a state (not yet freed, done, entered) |
| tests/test-stream.sps:856 | (test-equal "the resume step holds nothing across curl_easy_pause, by behaviour: a replay stalled 2,000 ms ... | plain English: a state (not yet freed, done, entered) |
| tests/test-unsupported.sps:781 | ;; in 6 of 20 runs of the memory gate on main's tree and 5 | record citation (main's tree) |
| tests/test-url-location.sps:29 | ;;;     of its own, so a libcurl not yet run fails this suite alone. | plain English: a state (not yet freed, done, entered) |
| tests/test-url.sps:734 | ;; object made but not yet recorded where its free finds it, at any of those | plain English: a state (not yet freed, done, entered) |
| src/curl.sls:285 | ;; reported 0 (M7 slice 1). A streamed response's body is #f: its token | record citation (slice) |
| src/curl/private/conditions.sls:122 | ;; a key or another value belongs was printed whole (M7 slice 3's | record citation (slice) |
| src/curl/private/conditions.sls:483 | ;;                 error buffer (M7 slice 3's review, read in source) | record citation (slice) |
| src/curl/private/conditions.sls:569 | ;;           (M7 slice 3's review); the method, for body-not-allowed; | record citation (slice) |
| src/curl/private/constants.sls:249 | ;; unsupported scheme, 5, and 8.23.0 parses it (M7 slice 3's build). | record citation (slice) |
| src/curl/private/engine.sls:78 | ;;; curl_multi_perform makes its messages (M3 slice 2, measured on four | record citation (slice) |
| src/curl/private/engine.sls:305 | ;; paced sleeps it has seen. Then, from M7 slice 4, under the mutex: its | record citation (slice) |
| src/curl/private/engine.sls:335 | ;; review of M7 slice 2). An engine prints as #<curl-engine>. | record citation (slice) |
| src/curl/private/engine.sls:558 | ;; raise could be taken for the transfer's (M5 slice 3's review). | record citation (slice) |
| src/curl/private/engine.sls:702 | ;; 7.85.0 and 8.5.0, which stop sending once they read it (M6 slice 2's | record citation (slice) |
| src/curl/private/engine.sls:1968 | ;; bare symbol, and those engines failed at their first resume (M6 slice | record citation (slice) |
| src/curl/private/native.sls:53 | ;;; (M8 slice 3), its parts the mime's own. The load's own, the header | record citation (slice) |
| src/curl/private/native.sls:726 | ;; the Mac's run of M7 slice 3). info keeps the word it read; step 3's | record citation (slice) |
| src/curl/private/transfer.sls:686 | ;; as over CAINFO, cleared PROXY_CAPATH or not (M7 slice 3's | record citation (slice) |
| src/curl/private/transfer.sls:1126 | ;; read and changed its private copy (the review of M7 slice 2). A | record citation (slice) |
| src/curl/private/transfer.sls:1705 | ;; as M6 slice 1's Expect probe measured. This holds the wider rule, on | record citation (slice) |
| src/curl/private/transfer.sls:1924 | ;; connection reused once the transfer before had ended (M7 slice 1). | record citation (slice) |
| src/curl/private/transfer.sls:2095 | ;; option (ADR-0039; MIMEPOST was a twin before, M8 slice 3); | record citation (slice) |
| src/curl/private/transfer.sls:2118 | ;; replace part of the URL's credentials on some version (M4 slice 4's | record citation (slice) |
| src/curl/private/transfer.sls:2157 | ;; verification are the fields' from M7 slice 3 (ADR-0037, decision 5). | record citation (slice) |
| src/curl/private/transfer.sls:2183 | ;;     was its twin until the body field took it over (M8 slice 3); | record citation (slice) |
| src/curl/private/transfer.sls:2186 | ;;     target on the request line (the options tables, M4 slice 1); | record citation (slice) |
| src/curl/private/transfer.sls:2197 | ;;     until M7 slice 3 made it the field's own; | record citation (slice) |
| src/curl/private/transfer.sls:2198 | ;;   - found by M4 slice 4's review of every option the hatch's types | record citation (slice) |
| src/curl/private/transfer.sls:2214 | ;;     cookie-jar field's from M7 slice 4; CONNECT_ONLY, | record citation (slice) |
| src/curl/private/transfer.sls:2221 | ;;     (M7 slice 1; ADR-0009, amended 2026-11-02): SSL_ENABLE_ALPN, whose | record citation (slice) |
| src/curl/private/transfer.sls:2239 | ;;     HTTPPROXYTUNNEL did until M7 slice 3; | record citation (slice) |
| src/curl/private/transfer.sls:2241 | ;;     libcurls (M7 slice 2; ADR-0036, amended 2026-11-02): AWS_SIGV4, | record citation (slice) |
| src/curl/private/transfer.sls:2250 | ;;     (M7 slice 3; ADR-0037, amended 2026-11-03): PROXYAUTH, | record citation (slice) |
| src/curl/private/transfer.sls:2264 | ;;     SUPPRESS_CONNECT_HEADERS did until M8 slice 2; | record citation (slice) |
| src/curl/private/transfer.sls:2284 | ;;     libcurls (M8 slice 2; ADR-0040, amended 2026-11-06, decided by the | record citation (slice) |
| src/curl/private/transfer.sls:2600 | ;; the new connection too (M7 slice 3's measurement). FRESH_CONNECT is | record citation (slice) |
| src/curl/private/transfer.sls:2621 | ;; tunnel as a second HTTP/2 stream and got 200 (M7 slice 3's review); | record citation (slice) |
| src/curl/private/transfer.sls:2640 | ;; keeps the server from choosing HTTP/2 (M7 slice 3's measurement). | record citation (slice) |
| src/curl/private/transfer.sls:4405 | ;; libcurl refuses in a userinfo and each sends on as it is (M7 slice 3's | record citation (slice) |
| src/curl/private/transfer.sls:4540 | ;; Mac's run of M7 slice 3). | record citation (slice) |
| src/curl/private/url.sls:302 | ;; unsupported scheme and 8.23.0 parses it (M7 slice 3's build). Answers | record citation (slice) |
| src/http-client.sls:697 | ;; handed on (M7 slice 3). | record citation (slice) |
| src/http-client/private/conditions.sls:68 | ;; a key or another value belongs was printed whole (M7 slice 3's | record citation (slice) |
| src/http-client/private/conditions.sls:164 | ;;           credentials or a body (M7 slice 3's review); #f, for | record citation (slice) |
| src/http-client/private/exchange.sls:367 | ;; of M7 slice 2). | record citation (slice) |
| tests/auth-testing.sls:3 | ;;; from the test origin (M7 slice 2; the M7 plan, section 5.2): MD5 (RFC | record citation (slice) |
| tests/check-memory-gate.sh:742 | # (M8 slice 3's build, research/m8/slice3/build/). | record citation (slice) |
| tests/check-seam.sps:152 | ;; (M4 slice 2), and run no code either. foreign-entry answers an entry | record citation (slice) |
| tests/check-seam.sps:154 | ;; loaded libcurl's file (M4 slice 3): it calls nothing. ftype-sizeof and | record citation (slice) |
| tests/check-seam.sps:158 | ;; draw from a session's jitter generator (M5 slice 3): they run no code | record citation (slice) |
| tests/check-variadic.sh:48 | #                refused, and UNSHARE 2 stopping the carrying (M7 slice 4); | record citation (slice) |
| tests/check-variadic.sh:51 | #              - formadd, the load's mime probe's form (M8 slice 3): it | record citation (slice) |
| tests/decoy-libcurl.c:332 | /* The transfer's entry points (M2 slice 2), which the load binds | record citation (slice) |
| tests/decoy-libcurl.c:368 | /* The engine's multi interface (M3 slice 2), bound and never called during | record citation (slice) |
| tests/foreign-conventions.sls:280 | ;; What spike E1 measured (M3 slice 1; ADR-0013, accepted): the multi | record citation (slice) |
| tests/foreign-conventions.sls:314 | ;; and so are the request stream's, M6 slice 2's: read-body, the read | record citation (slice) |
| tests/foreign-conventions.sls:338 | ;; is made. M2, M3 and M7 slice 4 bound theirs against rows written | record citation (slice) |
| tests/known-transfer-verdicts.sexp:32 | (where "The floor, curl 7.85.0 built by scripts/ci/build-curl.sh on Ubuntu 24.04 with OpenSSL 3.0.13: the l... | record citation (slice) |
| tests/known-transfer-verdicts.sexp:43 | (where "Ubuntu 24.04's libcurl4t64 8.5.0 (OpenSSL 3.0.13), the library CI's main and memory lanes load; its... | record citation (slice) |
| tests/known-transfer-verdicts.sexp:54 | (where "Apple's libcurl 8.7.1, /usr/lib/libcurl.4.dylib with SecureTransport (LibreSSL/3.3.6), on the maint... | record citation (slice) |
| tests/known-transfer-verdicts.sexp:65 | (where "The pinned Guix container (scripts/guix-env, ADR-0006): the profile's curl 8.20.0 with GnuTLS 3.8.1... | record citation (slice) |
| tests/known-transfer-verdicts.sexp:75 | (where "The current libcurl, curl 8.23.0 built by scripts/ci/build-curl.sh --current on Ubuntu 24.04 with O... | record citation (slice) |
| tests/origin.mjs:365 | // The parts route (M8 slice 3; the M8 plan, section 6), on http, the https faces, h2c and | record citation (slice) |
| tests/origin.mjs:389 | // The auth route (M7 slice 2; the M7 plan, section 5.2), on http, the https | record citation (slice) |
| tests/origin.mjs:462 | // The proxy (M7 slice 3; the M7 plan, section 6.2), on http and the https | record citation (slice) |
| tests/origin.mjs:503 | // The cookie route (M7 slice 4; the M7 plan, section 6.4), on http and the | record citation (slice) |
| tests/origin.mjs:943 | // --- the parts route (M8 slice 3) ------------------------------------------- | record citation (slice) |
| tests/origin.mjs:1050 | // The arithmetic, its self-test and its parser are M7 slice 2's stand-in's | record citation (slice) |
| tests/origin.mjs:1864 | // --- the head routes (M8 slice 2; ADR-0040) ------------------------------ | record citation (slice) |
| tests/origin.mjs:2366 | // (M8 slice 2; traps.md). Node's two receive limits stay their defaults: the | record citation (slice) |
| tests/origin.mjs:2639 | // The head routes (M8 slice 2): a head of a chosen size and shape; a | record citation (slice) |
| tests/origin.mjs:3420 | // 417: libcurl may resend on a new connection (M8 slice 2's build: | record citation (slice) |
| tests/test-auth.sps:762 | ;; --- what a printed request, plan, token or engine shows (the review of M7 slice 2) ------- | record citation (slice) |
| tests/test-auth.sps:1045 | ;; Measured by this suite on M7 slice 2's build, two runs on each lane: | record citation (slice) |
| tests/test-auth.sps:1250 | ;; --- a live token's assertion (the review of M7 slice 2) --- | record citation (slice) |
| tests/test-call-checks.sps:197 | ;; test-group's children hold theirs (M7 slice 4's races, | record citation (slice) |
| tests/test-collect-safe.sps:72 | ;;; a wrong binder. curl_share_setopt is bound from M7 slice 4, for an int, | record citation (slice) |
| tests/test-collect-safe.sps:73 | ;;; and curl_formadd from M8 slice 3, for the load's mime probe's form. | record citation (slice) |
| tests/test-collect-safe.sps:1111 | ;; alone (M7 slice 4), and curl_formadd for the load's form of one field, | record citation (slice) |
| tests/test-collect-safe.sps:1112 | ;; two string options and CURLFORM_END (M8 slice 3). make check-variadic | record citation (slice) |
| tests/test-collect-safe.sps:1327 | ;; Spike E1's plain rows (M3 slice 1; ADR-0013, accepted), written out | record citation (slice) |
| tests/test-collect-safe.sps:1350 | ;; The mime API but curl_mime_filedata, and curl_formfree (M8 slice 3): | record citation (slice) |
| tests/test-conditions.sps:511 | ;; --- a caller's value, as a refusal names it (M7 slice 3's review) --- | record citation (slice) |
| tests/test-drift.sps:199 | (define placeholder "TODO: ") | intended: test-drift's printed row's placeholder |
| tests/test-engine.sps:862 | ;; (measured in M5 slice 1, .plans/traps.md), so the window opens | record citation (slice) |
| tests/test-group.sps:442 | ;; hold (M7 slice 4's races, research/m7/slice4/races): | record citation (slice) |
| tests/test-headers.sps:254 | ;; libcurls' measured through the engine by M8 slice 2, two runs each, | record citation (slice) |
| tests/test-headers.sps:475 | ;; connection once (M8 slice 2's build), so the route holds its 417 by | record citation (slice) |
| tests/test-http-client.sps:1608 | ;; --- a caller's value, as a refusal names it (M7 slice 3's review), the high level's own copy --- | record citation (slice) |
| tests/test-library-loading.sps:358 | ;; after (the Mac's run of M7 slice 3): curl/curl.h's 1<<21, #x200000. | record citation (slice) |
| tests/test-mailbox.sps:349 | ;; there (M5 slice 3's review). The refused connect is to port 1. | record citation (slice) |
| tests/test-multipart.sps:1757 | ;; measured through the engine by M8 slice 3's build, two runs each, 8.5.0 | record citation (slice) |
| tests/test-origin-tls.sps:24 | ;;;   by hand beside it. The head routes' blocks (M8 slice 2) are decoded by | record citation (slice) |
| tests/test-origin-tls.sps:910 | ;; --- the parts route (M8 slice 3) -------------------------------------------- | record citation (slice) |
| tests/test-origin-tls.sps:1510 | ;; --- HPACK, decoded (M8 slice 2): the head routes' blocks ------------------- | record citation (slice) |
| tests/test-origin-tls.sps:2118 | ;; The head routes (M8 slice 2; ADR-0040), decoded: each block's fields | record citation (slice) |
| tests/test-origin-tls.sps:2126 | ;; trailers of /head?n=2&tn=6000 so (M8 slice 2's build). Those rows' probe | record citation (slice) |
| tests/test-origin-tls.sps:2371 | ;; --- the auth route over TLS (M7 slice 2; the M7 plan, section 5.2) --------------- | record citation (slice) |
| tests/test-origin-tls.sps:2464 | ;; --- the proxy over TLS (M7 slice 3; the M7 plan, section 6.2) -------------------- | record citation (slice) |
| tests/test-origin.sps:904 | ;; --- the raw face: the head routes (M8 slice 2; ADR-0040): a head of the | record citation (slice) |
| tests/test-origin.sps:1074 | ;; The proxy's arm (M8 slice 2): the next CONNECT it answers 200 carries | record citation (slice) |
| tests/test-origin.sps:1290 | ;; --- the parts route (M8 slice 3) ------------------------------------------------- | record citation (slice) |
| tests/test-origin.sps:2410 | ;; --- the auth route (M7 slice 2; the M7 plan, section 5.2) ------------------------ | record citation (slice) |
| tests/test-origin.sps:2634 | ;; --- the proxy (M7 slice 3; the M7 plan, section 6.2) --------------------------------- | record citation (slice) |
| tests/test-origin.sps:2872 | ;; --- the cookie route (M7 slice 4; the M7 plan, section 6.4) ------------------------- | record citation (slice) |
| tests/test-printed.sps:4 | ;;; M7 slice 3's review and its fix rounds). | record citation (slice) |
| tests/test-proxy.sps:1018 | ;; --- a secret where another value belongs (M7 slice 3's review) --- | record citation (slice) |
| tests/test-retry.sps:728 | ;; 56 with 0 on 8.5.0, and 7 with 0 on 8.20.0 and 8.23.0 (M7 slice 3's | record citation (slice) |
| tests/test-stream.sps:22 | ;;;     owned-option, the credentials field's since M7 slice 2, whose Digest | record citation (slice) |
| tests/test-stream.sps:24 | ;;;     proxy field's since M7 slice 3, whose credentials go by Basic alone; | record citation (slice) |
| tests/test-stream.sps:774 | ;; The seamed engines resume too (M6 slice 2's measurement, unpaced.sps): | record citation (slice) |
| tests/test-transfer-tls.sps:1211 | ;; Linux libcurls (measured in M2 slice 3's review) | record citation (slice) |
| tests/test-transfer.sps:686 | " (where \"TODO: say where this libcurl runs\")\n" | intended: test-drift's printed row's placeholder |
| tests/test-transfer.sps:1383 | (test-equal "owned-option-names, written out: the options the transfer always sets, QUICK_EXIT and MAXREDIR... | record citation (slice) |
| tests/test-transfer.sps:2063 | ;; --- the cap on response headers (ADR-0040; M8 slice 2), the raw face's | record citation (slice) |
| tests/test-unsupported.sps:245 | ;; curl-request-check, (curl)'s export from M5 slice 4's fix round (ADR-0023, | record citation (slice) |
| tests/test-unsupported.sps:299 | ;; slice 2), and http-version's HTTP_VERSION (M7 slice 1), and credentials' | record citation (slice) |
| tests/test-unsupported.sps:300 | ;; HTTPAUTH, USERNAME, PASSWORD and XOAUTH2_BEARER (M7 slice 2), with | record citation (slice) |
| tests/test-unsupported.sps:313 | ;; field's now (ADR-0039, decision 2; M8 slice 3); every proxy TLS option. | record citation (slice) |
| tests/test-unsupported.sps:356 | ;; M8 slice 3 (ADR-0039, decision 2): MIME_OPTIONS at CURLMIMEOPT_FORMESCAPE | record citation (slice) |
| tests/test-unsupported.sps:370 | ;; M7 slice 1 (ADR-0009, amended 2026-11-02): the http-version field's | record citation (slice) |
| tests/test-unsupported.sps:379 | ;; until M7 slice 3 owned it, below. Each is attached, and kept. | record citation (slice) |
| tests/test-unsupported.sps:396 | ;; M7 slice 2 (ADR-0036, amended 2026-11-02): the credentials field's | record citation (slice) |
| tests/test-unsupported.sps:408 | ;; nothing sent. PROXYAUTH was one until M7 slice 3 owned it, below. Each | record citation (slice) |
| tests/test-unsupported.sps:435 | ;; M7 slice 3 (ADR-0037, amended 2026-11-03): the proxy field's PROXY, | record citation (slice) |
| tests/test-unsupported.sps:448 | ;; got. SUPPRESS_CONNECT_HEADERS was among them until M8 slice 2 made it the | record citation (slice) |
| tests/test-unsupported.sps:469 | ;; The header callable's (M8 slice 2; ADR-0040, amended 2026-11-06, decided | record citation (slice) |
| tests/test-unsupported.sps:493 | ;; The cookie jar's (M7 slice 4; ADR-0035, amended 2026-11-04): SHARE and | record citation (slice) |
| tests/test-unsupported.sps:533 | (test-equal "INFILE, READDATA's alias, is refused as owned-option, by id: a streamed body's read callable r... | record citation (slice) |
| tests/test-upload.sps:722 | ;; first in 4 of 20 runs of M7 slice 4's tree and 5 of 20 of main's, and | record citation (slice) |
| tests/test-upload.sps:785 | ;; --- the body-asked bit with the answer first (M6 slice 2, round 4): | record citation (slice) |
| tests/test-upload.sps:1264 | ;; its own, chunked, under CI's memory job at M7 slice 2's cf3a567, the | record citation (slice) |
| tests/test-url-location.sps:6 | ;;; Its cases are M5 slice 2's measurement's (.plans/research/m5/location/), | record citation (slice) |
| tests/test-url-location.sps:475 | " (where \"TODO: say where this libcurl runs\")\n" | intended: test-drift's printed row's placeholder |
| tests/test-url-parts.sps:7 | ;;; Its cases are M5 slice 1's measurement's (.plans/research/m5/url-parts/), | record citation (slice) |
| tests/test-url-parts.sps:445 | " (where \"TODO: say where this libcurl runs\")\n" | intended: test-drift's printed row's placeholder |
| tests/test-url.sps:327 | " (where \"TODO: say where this libcurl runs\")\n" | intended: test-drift's printed row's placeholder |
| tests/test-url.sps:711 | ;; gave 490 to 500 in each of 6 (M5 slice 1, | record citation (slice) |
| tests/test-variadic.sps:7 | ;;; (ADR-0001, decision 1, amended 2026-10-25; M7 slice 4; M8 slice 3). It | record citation (slice) |
| tests/test-variadic.sps:78 | ;;;            the carrying, which UNSHARE of no other value does (M7 slice | record citation (slice) |
| tests/test-variadic.sps:758 | ;; --- the form, through curl-formadd-code (M8 slice 3) ------------------------------------------ | record citation (slice) |
