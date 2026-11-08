# M8 slice 4: README.org's claims against today's code

Read-only check, 2026-11-08, of chez-curl's README.org on `feat/m8-docs`, `main` and HEAD at
`fb62a0b` (slice 3 merged). README.org is unchanged since the docs survey's `fbc6fce`
(`.plans/research/m8/surveys/docs.md` section 1); slices 2 (the header cap, ADR-0040) and 3
(multipart bodies, ADR-0039) changed `src/` since (`git diff --stat fbc6fce..HEAD -- src`: 11
files, +1,237 -185).

**What was read.** AGENTS.md; the survey's section 1; README.org whole; the slices' diff of
`src/`; then, for each claim, the code it rests on and the suites that would hold it. Four
read-only Opus agents each checked one range of README.org (:23-166, :167-321, :322-459,
:460-584) against one brief; I checked :11-16, the blocks, the gaps and the survey's ten, and
verified the four hand-backs: every test citation in the table is a `test-equal` or
`test-assert` line or a table's row (`logs/readme-citations.log`); every code citation lies
inside its file (same log); and the wrong row, every partly row and a sample of held and
unheld rows were re-read at their lines.

**Paths.** `transfer.sls`, `engine.sls`, `url.sls`, `native.sls`, `conditions.sls`,
`verify.sls`, `discovery.sls` and `require-threaded.sls` are under `src/curl/private/`;
`call.sls`, `exchange.sls` and `drive.sls` under `src/http-client/private/`. A bare `:N` in a
cell is a line of the file named before it in that cell.

**Marks.** *held*: today's code does what the claim says. *wrong*: it does otherwise. *partly*:
true, but missing a case (one the merged slices added, or one that was always there), or true
only in part. *unheld*, added after the code's mark: no test's assertion would fail if the claim
became false. "libcurl's" in Code: chez-curl does not make it so; only a test that measures it
holds it. *held (8.7.1 unnamed)*: true of every version it names, and the suite's table shows
Apple's 8.7.1 doing the same, unnamed by the README.

**Logs** (all under `.plans/research/m8/slice4/logs/`): `readme-blocks/` (the blocks' run:
`run.sh`, `bound.sps`, `server.mjs`, `run.log`); `readme-survey-carry.sh` and `.log` (the
survey's ten against the diff); `readme-citations.sh` and `.log` (the citation checks).

## Claims

One row per claim, in README.org line order. :1-10 and :585-588 (the title, badge, disclosure
and license) make none about what chez-curl does.

| README.org | Claim | Code | Test | Mark |
|---|---|---|---|---|
| :13 | Chez 10.4.0 or later, built with threads: an older or a `--nothreads` Chez is refused (survey 1) | require-threaded.sls:43 (`minimum '(10 4 0)`), :79-89 (`(threaded?)` #f, then older) | tests/test-require-threaded.sps:458 (threaded? #f refused), :491 (below the floor, pre-releases too), :508 (at and above load); the line itself by `make check-floors` (Makefile:392-394; tests/test-check-floors.sps:1345) | held |
| :14 | libcurl 7.85.0 or later, built with TLS: below-floor, then no-ssl (survey 2) | verify.sls:26 (`#x075500`), :35-41 | tests/test-verify.sps:152, :162 (below-floor), :166 (no-ssl), :174 (below-floor wins) | held |
| :15 | Node.js 20 or later, for the tests | packaging/floors.sexp (`(node "20")`); tests/floors.sls:363-372 (the README line) | `make check-floors` holds the line to the floors file; .github/workflows/ci.yml:314-321 (the floor job runs the suites on Node at its floor) | held |
| :25-26 | chez-curl never changes the environment's variables | src reads them with `getenv` alone: `native.sls:696-701`, `discovery.sls:53,252-254`; no `putenv`/`setenv` anywhere in `src/` | `tests/check-seam.sps:164` (allowlist admits `getenv`, not `putenv`); weak: a check program, and a foreign `setenv` binding is caught only by the binding-row rule | held |
| :28-29 | `http_proxy`, `https_proxy`, `HTTPS_PROXY`, `all_proxy`, `ALL_PROXY` route through their proxy | libcurl's: `transfer.sls:2566` (environment sets nothing), `:943-947` | `tests/test-transfer.sps:2644` (http_proxy, all_proxy rows), `tests/test-proxy.sps:1874` (https_proxy); weak: `HTTPS_PROXY`, `ALL_PROXY` never set by any test | held |
| :29-30 | `no_proxy` and `NO_PROXY` list hosts that go direct | libcurl's: `transfer.sls:2566` | `tests/test-proxy.sps:2037` (no_proxy beside environment goes direct); weak: `NO_PROXY` with environment untested | held |
| :30 | `HTTP_PROXY` is ignored | libcurl's; `transfer.sls:945-947` (comment) | none (the hermetic tests, e.g. `tests/test-proxy.sps:347`, only require it unset) | held, unheld |
| :30-31 | `'proxy #f` goes direct whatever the variables say | `transfer.sls:2567` (PROXY "") | `tests/test-transfer.sps:2644` (rows http_proxy/all_proxy with `none`, direct) | held |
| :31-32 | a proxy URL takes the transfer whatever the variables say | `transfer.sls:2568-2569` (PROXY, then NOPROXY "") | `tests/test-proxy.sps:2027` (no_proxy, NO_PROXY, `*`, the three variables at a refused port) | held |
| :32-34 | through a non-tunnelling proxy libcurl ignores prior knowledge, sends HTTP/1.1 | libcurl's for the environment's (`transfer.sls:2566`); a proxy URL is refused first, `transfer.sls:4568-4570`, `:4319` | none for the environment's; `tests/test-proxy.sps:885`, `:1904` hold the proxy URL's refusal | partly, unheld |
| :35-36 | a variable's user and password are libcurl's; chez-curl checks none | `transfer.sls:4304` (check-proxy-url only for a string proxy), `:2566` | none | held, unheld |
| :36-38 | control-byte userinfo: direct on 7.85.0, 8.5.0; 3 from 8.20.0 | libcurl's; measured, `.plans/decisions/0024-what-a-transfer-reads-from-its-environment.md:337-343` | none | held, unheld |
| :38-39 | a proxy URL's control-byte credentials are refused | `transfer.sls:4506` (check-proxy-userinfo, credentials-bytes) | `tests/test-proxy.sps:707`, `:717` | held |
| :40-41 | a variable's `https://` proxy checked against libcurl's store; on Guix SSL_CERT_FILE's | `transfer.sls:2566` (no PROXY_ TLS option set for environment) | none (`tests/test-proxy.sps:1791` holds it for a proxy URL with no proxy-ca-file, not a variable) | held, unheld |
| :42-43 | `ca-file`/`verify` are the server's; a proxy URL's are `proxy-ca-file`/`proxy-verify` | `transfer.sls:2475-2482` (tls-settings), `:2562-2575` (proxy-settings) | `tests/test-proxy.sps:1791` (origin keys change nothing at the proxy), `:1806` (proxy's never reach the origin), `:364` | held |
| :44-45 | Guix's libcurl reads both variables as it loads | libcurl's patch; `native.sls:687-701` records them at the load | `tests/test-transfer-tls.sps:1321` (rows set and emptied after the load); Guix lane alone | held |
| :45-46 | Guix 8.20.0 writes SSL_CERT_FILE over `ca-file`, adds SSL_CERT_DIR | libcurl's; `transfer.sls:610-620` (guix-ca-overrides, its measurement) | none: on Guix a submit refuses before the override can show | held, unheld |
| :46-49 | any Guix libcurl, either set at start, `ca-file` + verify on: refused at submit, naming it | `transfer.sls:632-635` (no row = overrides), `:654-657`, `:689-702`, `:4303` | `tests/test-transfer-tls.sps:1321` (refusal seen on the Guix lane alone), `:1084`, `:1097` | held |
| :49-50 | with no `ca-file`, not refused: the store the variable names | `transfer.sls:655` | `tests/test-transfer-tls.sps:1321` (row "SSL_CERT_FILE at ca.pem and no CA file") | held |
| :51-52 | GnuTLS reads a `pkcs11:` path, any case, as a PKCS#11 token | GnuTLS's; `transfer.sls:556-562` (comment, measured) | none | held, unheld |
| :52-53 | chez-curl refuses such a `ca-file`, `pkcs11-url`, on every backend | `transfer.sls:563-569`, `:604-607` | `tests/test-transfer-tls.sps:468`, `:497` | held |
| :53 | `./pkcs11:...` names the file | `transfer.sls:563-569` (a prefix test alone) | `tests/test-transfer-tls.sps:487` (dot-slash taken), `:1225` (pkcs11:ca.pem by absolute path, 200) | held |
| :54-56 | `SSLKEYLOGFILE` writes every transfer's secrets | the TLS library's; nothing in `src/` reads or sets it | none (measured, ADR-0024 `:42`) | held, unheld |
| :57-58 | `OPENSSL_CONF` at level 0 let a 1024-bit certificate pass | OpenSSL's; nothing in `src/` | none (measured, ADR-0024 `:43`) | held, unheld |
| :59-60 | Apple's libcurl uses LibreSSL unless `CURL_SSL_BACKEND` | libcurl's; `native.sls:713-736` (backend read after the init), `:1545` | `tests/test-transfer-tls.sps:1393` (macOS lane alone), `:1071` | held |
| :60-62 | Apple's LibreSSL checks the keychain when a `ca-file` fails | Apple's; `transfer.sls:659-670` (comment) | none (no test can show it: AGENTS.md trap) | held, unheld |
| :62-63 | there a `ca-file` with verify on is refused at submit | `transfer.sls:671-674`, `:703-706` (keychain-fallback) | `tests/test-transfer-tls.sps:1044` (rule written out), `:1393` (macOS lane alone) | held |
| :63-65 | `CURL_SSL_BACKEND=secure-transport` keeps the `ca-file` the only anchor | `transfer.sls:673` (SecureTransport not refused) | `tests/test-transfer-tls.sps:1393` (row secure-transport), `:1196` run there; weak: macOS lane alone, keychain unshowable | held |
| :65 | `make test` sets it on macOS | `Makefile:34-37` | `tests/test-transfer-tls.sps:1071` | held |
| :65-66 | `OPENSSL_X509_TEA_DISABLE=1` turns the fallback off | Apple's; measured, `.plans/progress.md:1470` | none | held, unheld |
| :66-67 | chez-curl does not read it, and still refuses | `transfer.sls:671-674` (reads no variable); no match in `src/` | none | held, unheld |
| :68-69 | libcurl 8.7.0 and 8.7.1 count no bytes sent | libcurl's; measured, `transfer.sls:1999-2005` | none measures libcurl's 0; the suites hold chez-curl's table | held, unheld |
| :69-70 | there a failure that ran has request size `#f`, not 0 | `transfer.sls:2005-2012`, `:2030-2032`; `conditions.sls:696-711` | `tests/test-request.sps:927` (table, copy at `:880`), `:931` (8.7.0 and 8.7.1 rows `#f`) | held |
| :80-81 | `#f` sets nothing: HTTP/2 over https when offered, else HTTP/1.1 | `transfer.sls:2508` | `tests/test-version.sps:650`, `:300` | held |
| :82-83 | `http/1.1` alone; an HTTP/2-only server refuses it | `transfer.sls:2509` | `tests/test-version.sps:654` (h2 face, 35) | held |
| :84-85 | `http/2`: HTTP/2 by ALPN over https, else HTTP/1.1 | `transfer.sls:2510` (2TLS) | `tests/test-version.sps:662` | held |
| :85-86 | `http/2` over `http://`: HTTP/1.1, no `Upgrade` | `transfer.sls:2499-2500`, `:2510` | `tests/test-version.sps:662` (head with no Upgrade) | held |
| :87-88 | prior knowledge speaks HTTP/2 from the first byte to `http://` | `transfer.sls:2511` | `tests/test-version.sps:666` (h2c face) | held |
| :88-89 | with `https://` refused at submit, `prior-knowledge-over-https` | `transfer.sls:4617-4619`, `:4318` | `tests/test-version.sps:666`, `:380`, `:412` | held |
| :89-90 | a redirect to `https://` fails the call the same way | `exchange.sls:809-815` (next request submitted), `transfer.sls:4617-4619` | `tests/test-version.sps:796` | held |
| :90-91 | an HTTP/1.1 server fails it; code by libcurl and timing | libcurl's | `tests/test-version.sps:677`, rows `:456-462` | held |
| :92-94 | through a non-tunnelling proxy, the environment's among them, prior knowledge ignored | libcurl's for the environment's (`transfer.sls:2566`); a proxy URL refused first, `transfer.sls:4568-4570` | none for the environment's; `tests/test-proxy.sps:885`, `:1904` hold the proxy URL's refusal | partly, unheld |
| :95-97 | requests started together open a connection each; no `PIPEWAIT` | `PIPEWAIT` is set nowhere: in `src/` only in comments, `transfer.sls:141`, `:999`, `:2237` | `tests/test-version.sps:687` (two connections at #f and http/2) | held |
| :97 | a request started later reuses an open connection | libcurl's | `tests/test-version.sps:703`, `:711` | held |
| :97-98 | 7.85.0 shares one by prior knowledge even then | libcurl's | `tests/test-version.sps:693`, row `:473` (7.85.0 1; 8.5.0, 8.7.1, 8.20.0, 8.23.0 2) | held |
| :98-100 | 8.7.0, 8.7.1: no multiplexing, a concurrent request opens its own | `engine.sls:402-416` | `tests/test-version.sps:703`, copy `:589`; the 8.7.x branch runs on the Mac alone | held |
| :100-101 | the hatch's `PIPEWAIT` still works | `transfer.sls:2237-2238`, `:2295-2313` (not owned) | `tests/test-unsupported.sps:380` (taken); weak: its effect is unmeasured | held |
| :102-104 | a reused prior-knowledge HTTP/2 connection serves #f and http/2 over http | libcurl's | `tests/test-version.sps:722` | held |
| :105-107 | hatch refuses `HTTP_VERSION`, `SSL_ENABLE_ALPN`, `ALTSVC`, `ALTSVC_CTRL` | `transfer.sls:2129`, `:2307` | `tests/test-unsupported.sps:380` | held |
| :109 | sessions and calls take `http-version` | `call.sls:65-67`, `:94-95` | `tests/test-version.sps:736` | held |
| :109-110 | a call's replaces its session's | `call.sls:723-724`, `:743` | `tests/test-version.sps:744` | held |
| :110 | a redirect keeps it | `exchange.sls:766-771` (curl-request-with keeps the field) | `tests/test-version.sps:770` | held |
| :114-120 | `credentials` is one scheme's: basic, digest or bearer | `transfer.sls:761`, `:774-791`, `:2528-2542` | `tests/test-auth.sps:417`, `:358` | held |
| :122 | Basic and Bearer go out on the first request | `transfer.sls:2519-2521`, `:2537-2542` (one scheme's bit) | `tests/test-auth.sps:1099`, `:1109` | held |
| :123-124 | Digest: a bare request, then the credentials, inside one transfer | libcurl's; `transfer.sls:2540` | `tests/test-auth.sps:1123` | held |
| :124-126 | a Digest body to a server that never challenges goes twice, first bodiless | libcurl's | `tests/test-auth.sps:1169` | held |
| :127 | each string is sent as UTF-8 | `transfer.sls:2523-2524` (set-string-option!) | `tests/test-auth.sps:1352`; weak: a Digest user alone, no Basic or Bearer string | held |
| :127-129 | 8.23.0 percent-encodes a non-ASCII Digest user, hashes raw: refused | libcurl's | `tests/test-auth.sps:1352`, row `:1018` (8.23.0 401, `%C3%BCser`; the rest 200 raw) | held |
| :130 | a wrong password is the server's 401, no failure | libcurl's; FAILONERROR never set (`transfer.sls:2243-2248`) | `tests/test-auth.sps:1152` | held |
| :131-133 | a control char in any string: `credentials-bytes`, as made | `transfer.sls:801-806`, `:839-848` | `tests/test-auth.sps:513` | held |
| :133-134 | a `:` in a Basic user: `credentials-bytes` | `transfer.sls:845` | `tests/test-auth.sps:542` | held |
| :134-135 | an empty token, or user and password both empty: `credentials-empty` | `transfer.sls:849-851` | `tests/test-auth.sps:548` | held |
| :135-136 | beside an `Authorization` header: `credentials-beside-authorization` | `transfer.sls:852-853` | `tests/test-auth.sps:559`, `:572`, `:620` | held |
| :137-138 | Digest beside a streamed body or response: `digest-with-stream`; Basic, Bearer stream | `transfer.sls:854-855` | `tests/test-auth.sps:585`, `:1204`, `:1239` | held |
| :139-140 | at submit, beside a URL's user or password: `credentials-beside-userinfo` | `transfer.sls:4315-4316`, `:4604-4606` | `tests/test-auth.sps:638` | held |
| :140-141 | an empty `@` counts from 8.5.0, not on 7.85.0 | libcurl's URL API; `transfer.sls:4605` | `tests/test-auth.sps:1377`, rows `:1054` (7.85.0 `@`, `:@` sent), `:1056` (8.5.0 refused; 8.7.1, 8.20.0, 8.23.0 alike) | held |
| :142-143 | a refusal names scheme and part, never the secret | `transfer.sls:808-812`, `:846`, `:850`; `conditions.sls:573-578`, `:592-594` | `tests/test-auth.sps:513`, `:731` | held |
| :144 | no length is checked | `transfer.sls:836-855` (no length rule) | `tests/test-auth.sps:1393` (a 1 MiB password reaches libcurl) | held |
| :144-145 | 8 KiB goes everywhere, 64 KiB over HTTP/1.1 alone | libcurl's; measured, `.plans/decisions/0036-credentials-and-one-auth-scheme.md:112-113` | none | held, unheld |
| :145-147 | 1 MiB fails before sending, 27 or 100 by version | libcurl's | `tests/test-auth.sps:1393`, row `:1075` (7.85.0, 8.5.0 27; 8.7.1, 8.20.0, 8.23.0 100) | held |
| :147 | but a 1 MiB Digest password passes: only its hash goes | libcurl's; ADR-0036 `:113` | none | held, unheld |
| :148-149 | a printed request, token or engine shows its type alone | `transfer.sls:1102-1128` (opaque); `engine.sls:308-336`, `:347-361` | `tests/test-auth.sps:778` | held |
| :150-152 | a misplaced value is named by its kind, `(kind string)` | `conditions.sls:116-145` (shown-value, checked-accessor) | `tests/test-printed.sps:370`, `:389`, `:336` | held |
| :152 | a refused URL is named by its field, `url` | `url.sls:58-63` | `tests/test-printed.sps:571` | held |
| :152-153 | a header value is named by its header's name | `transfer.sls:524-525` | `tests/test-transfer.sps:833` | held |
| :153 | `curl-url-error-input` still holds the URL | `conditions.sls:304-307`, `:328-329` | `tests/test-printed.sps:571` | held |
| :154-155 | hatch refuses `HTTPAUTH`, `USERNAME`, `PASSWORD`, `XOAUTH2_BEARER`, `AWS_SIGV4`, `MAXREDIRS` | `transfer.sls:2129`, `:2297`, `:2308` | `tests/test-unsupported.sps:410` | held |
| :155-158 | 30 follows a transfer; 417 or stale answers for ever end it with 47 | `transfer.sls:2315-2335` (MAXREDIRS 30); the header cap `:3570-3578`, `:3602-3621` counts every round's head | `tests/test-auth.sps:1304`, `:1317`; `tests/test-headers.sps:480` (the cap across a 417 and its resend) | partly |
| :158-159 | libcurl's retry on a dead connection is no such follow | libcurl's; `transfer.sls:2320-2325` (read in source) | none | held, unheld |
| :161 | sessions and calls take `credentials` | `call.sls:65-67`, `:94-95`, `:744` | `tests/test-auth.sps:1428` | held |
| :161-162 | a call's replaces its session's, `#f` too | `call.sls:723-724`, `:744` | `tests/test-auth.sps:1437` | held |
| :162-163 | a redirect keeps them within the origin, drops them for another, as `Authorization` | `exchange.sls:700-702`, `:760-771`, `:801-808` | `tests/test-auth.sps:1464`, `:1478` (port), `:1494` (host); weak: a scheme change untested | held |
| :163-165 | a same-origin hop to a URL with userinfo fails, `credentials-beside-userinfo` | `exchange.sls:809`, `transfer.sls:4604-4606` | `tests/test-auth.sps:1515` | held |
| :169 | `proxy` takes a proxy URL string, kept as a copy | transfer.sls:1239-1240 (type), :1254 (copy), :1192-1196 (fresh copy read) | tests/test-proxy.sps:547 (kept as a copy, fresh each read) | held |
| :178 | `environment`, the default, goes through the proxy a variable names | transfer.sls:1780 (default `'environment`), :2566 (sets nothing, libcurl reads the variables) | tests/test-transfer.sps:2644 (child, http_proxy/all_proxy, default and environment go through); tests/test-proxy.sps:2037 (environment beside http_proxy at a refused port fails 7) | held |
| :178-179 | `#f` goes direct | transfer.sls:2567 (PROXY "") | tests/test-transfer.sps:2644 (child, http_proxy and all_proxy set, `#f` direct); tests/test-proxy.sps:364 (settings written out) | held |
| :180-181 | a proxy URL takes every transfer; no_proxy, NO_PROXY and proxy variables send nothing around it | transfer.sls:2568-2569 (PROXY at the URL, NOPROXY "") | tests/test-proxy.sps:2027 (child: no_proxy, NO_PROXY, `*`, the three variables beside no_proxy; proxy's log) | held |
| :182-183 | userinfo percent-decoded, sent by Basic on the first request | transfer.sls:2568-2569 (PROXY at the URL), :2309 (PROXYAUTH owned, never set: libcurl's default Basic) | tests/test-proxy.sps:1708 (ten userinfo rows, decoded Basic on the proxy's log), :1745 (on the CONNECT) | held |
| :183-184 | an http:// URL's request goes to the proxy whole (absolute form) | libcurl's; transfer.sls:2310 (HTTPPROXYTUNNEL owned, never set) | tests/test-proxy.sps:1708, :1724 | held |
| :184-185 | an https:// URL goes through a CONNECT tunnel, the proxy seeing only the CONNECT | libcurl's | tests/test-proxy.sps:1739, :1751 (HTTP/2 inside the tunnel) | held |
| :186-187 | a proxy URL with no port gets 80 or 443 on every libcurl | url.sls:323-332 (port set when none), transfer.sls:4484 (that URL handed to PROXY) | tests/test-proxy.sps:492 (check-proxy-url's URL written out), :511 (the plan's) | held |
| :187 | on its own libcurl tries 1080, and 8.23.0 80 | libcurl's; url.sls:307-309 records it (comment) | none | held, unheld |
| :188-189 | proxy-ca-file is an https:// proxy's only CA file (PROXY_CAINFO, PROXY_CAPATH cleared) | transfer.sls:2572-2573 | tests/test-proxy.sps:364 (settings), :1773 (run CA as proxy's: good leaf passes), :1791 (another CA fails 60) | held |
| :189 | no proxy-ca-file: libcurl's default store | transfer.sls:2572-2574 (no PROXY_CA* set) | tests/test-proxy.sps:1791 (good leaf fails 60 against the default store) | held |
| :189-190 | proxy-verify, `#t` by default, checks the proxy's certificate and name | transfer.sls:2570-2571 (1 and 2, or 0 and 0), :1257 (type) | tests/test-proxy.sps:573 (default `#t`), :1773 (expired, wrong-host, untrusted fail 60; pass with it off) | held |
| :190-191 | the request's ca-file and verify never reach the proxy, nor the proxy keys the server | transfer.sls:2562-2575 (PROXY_* options alone) apart from tls-settings' (CAINFO, SSL_VERIFY*) | tests/test-proxy.sps:1791 (origin's CA file or verify off change nothing at the proxy), :1806 (proxy's verify never reaches the origin) | held |
| :191-193 | proxy-ca-file refused against the environment as ca-file is: Guix's SSL_CERT_FILE and SSL_CERT_DIR, the Mac's LibreSSL | transfer.sls:4309 (check-ca-environment 'proxy-ca-file), :689-705 (the shared rule) | tests/test-proxy.sps:2045 (child, SSL_CERT_FILE, Guix lanes alone); SSL_CERT_DIR and the keychain for proxy-ca-file: none, the shared rule alone, tests/test-transfer-tls.sps:1097, :1044 | held |
| :194-195 | submit refusals name the field, never the URL | transfer.sls:4385-4390 (refuse-proxy, value `proxy` or `(proxy PART)`) | tests/test-proxy.sps:655 (value `proxy`), :1003 (no refusal prints the password) | held |
| :195-196 | an unparsable URL, or a userinfo `%` not followed by two hex digits: proxy-url | transfer.sls:4462-4466, :4475-4476 | tests/test-proxy.sps:655, :673 | held |
| :196-197 | a scheme but http or https, socks5:// among them: proxy-scheme | transfer.sls:4477-4478 | tests/test-proxy.sps:689 (whole complement listed, both cases) | held |
| :197-198 | a path, a query or a fragment: proxy-url-parts | transfer.sls:4479-4482 (a path but `/`) | tests/test-proxy.sps:695 | held |
| :198-200 | userinfo decoding to a control byte, non-UTF-8, or a `:` in the user: credentials-bytes | transfer.sls:4506-4519 | tests/test-proxy.sps:707, :717, :722, :739, :755 | held |
| :200 | user and password both empty: credentials-empty | transfer.sls:4521-4523 | tests/test-proxy.sps:541 (by version), :765 (one empty part passes) | held |
| :200-202 | proxy-ca-file or proxy-verify `#f` beside any proxy but an https:// URL: proxy-tls-without-https-proxy | transfer.sls:4553-4558 | tests/test-proxy.sps:858, :872 | held |
| :202-203 | http/2-prior-knowledge beside a proxy URL: prior-knowledge-through-proxy | transfer.sls:4568-4570 | tests/test-proxy.sps:885, :1904 (the proxy gets nothing) | held |
| :202-203, :207-208 | libcurl ignores prior knowledge through a proxy, the environment's too | libcurl's; transfer.sls:4563-4567 records it | none: refused beside a URL; no test sends prior knowledge through an environment proxy | held, unheld |
| :203-206 | an https:// proxy on a libcurl without HTTPS-proxy support: https-proxy-unsupported | transfer.sls:4541-4543, :4305-4306 (features read after the init) | tests/test-proxy.sps:439 (rule on feature words), :451 (loaded libcurl passes); weak: no lane lacks the feature | held |
| :205 | such a libcurl writes the whole URL into its error buffer | libcurl's; transfer.sls:4534-4537 (read in source) | none | held, unheld |
| :206-208 | beside `proxy environment` prior knowledge is not refused | transfer.sls:4568-4570 (refuses beside a URL's reading alone) | tests/test-proxy.sps:885 (environment and `#f` pass check and submit) | held |
| :208-209 | 7.85.0 reads an empty `@` or `:@` as no credentials and sends none; later ones refuse them | transfer.sls:4521-4523 (refused only when a part is reported); libcurl's report | tests/test-proxy.sps:541 (rows 7.85.0, 8.5.0, 8.20.0, 8.23.0, 8.7.1), :1733 (wire: none sent on 7.85.0) | held |
| :210-212 | a Proxy-Authorization header, any case, refused as made: proxy-authorization-header | transfer.sls:522-523 | tests/test-proxy.sps:816 (each letter flipped, every position), :830, :842 (again at check and submit) | held |
| :211-212 | inside a tunnel libcurl would send it to the server | libcurl's; transfer.sls:484-487 records it | none | held, unheld |
| :213-215 | https:// through an https:// proxy stalls to its timeout on Ubuntu's 8.5.0/GnuTLS, at times on 7.85.0 over HTTP/2 | libcurl's; transfer.sls:2631-2643 records the measurement | none: the refusal keeps every such lane from it | held, unheld |
| :215-217 | refused at submit, proxy-tls-in-tls: always on 8.5.0/GnuTLS, on 7.85.0 unless http/1.1 | transfer.sls:2644-2646 (table), :2653-2661, :4579-4588 | tests/test-proxy.sps:456 (table), :460 (rule), :946 (rows 7.85.0/OpenSSL, 8.5.0/GnuTLS refuse as stated; others pass), :1878 (through the engine) | held |
| :217-218 | a stalling proxy named by a variable, through `proxy environment`, is not refused | transfer.sls:4580 (needs a proxy URL's reading) | none: no test submits an https:// URL through proxy environment on a lane whose row refuses | held, unheld |
| :219 | a refused CONNECT fails 56 on 7.85.0 and 8.5.0, 7 from 8.20.0 | libcurl's | tests/test-proxy.sps:1827 (refused-rows: 7.85.0, 8.5.0 56; 8.20.0, 8.23.0 7; 8.7.1 56, unnamed) | held (8.7.1 unnamed) |
| :220-221 | curl-transfer-error-connect-code holds the proxy's status on every version | transfer.sls:2019-2025, :5143-5176 | tests/test-proxy.sps:1827 (403, 407, 502, 503 on each row), :1831 (none without a refused CONNECT) | held |
| :221-222 | a retry treats it as a response with that status; the default never retries 403 or 407 | exchange.sls:1092-1097; call.sls:474 (default statuses `(429 503)`) | tests/test-proxy.sps:2005 (503 retried, 407 once); weak: its policy is `(503)`, not the default | held |
| :222-224 | a proxy that closes keeps the plain rule; on 7.85.0 the size counts the CONNECT, so a post is not retried | exchange.sls:1098-1100 (size rule) | tests/test-proxy.sps:1827 (7.85.0 size the CONNECT's), :2021 (closing-retries: 7.85.0 post once; 8.7.1 once too, unnamed) | held (8.7.1 unnamed) |
| :225-227 | before 8.19.0 each https:// request through a proxy URL opens its own connection, and with credentials closes it as it ends | transfer.sls:2583, :2604-2611, :4819-4822 (FRESH_CONNECT, FORBID_REUSE set) | tests/test-proxy.sps:418 (written out), :1842 (unshared-rows: 7.85.0, 8.5.0, 8.7.1 below; 8.20.0, 8.23.0 shared), :1864 (the plan's) | held |
| :227-228 | 7.85.0 let a later request ride another user's tunnel (CVE-2026-3784) | libcurl's; transfer.sls:2597-2600 records it | none: :1842 runs one user's userinfo twice, under the fix | held, unheld |
| :228-229 | Ubuntu's 8.5.0 has the fix but pays for the new connection too | transfer.sls:2607 (by version alone) | tests/test-proxy.sps:1842 (8.5.0 row: own CONNECT each); "has the fix": none | held |
| :230-233 | before 8.19.0 userinfo in a proxy URL stops the engine's multiplexing for good; each later request opens its own connection; none rides that tunnel, environment's included | transfer.sls:2627-2628; engine.sls:2031-2035, :2062 (switched before the handle is added) | tests/test-proxy.sps:426, :1864, :1869 (switch-rows), :1874 (join-rows: environment's own CONNECT refused 407) | partly |
| :234-236 | the hatch refuses PROXY, NOPROXY, PROXYAUTH, PROXYUSERPWD, PROXYUSERNAME, PROXYPASSWORD, HTTPPROXYTUNNEL, HAPROXYPROTOCOL, HAPROXY_CLIENT_IP, FORBID_REUSE | transfer.sls:2127 (proxy field's), :2309-2310 | tests/test-unsupported.sps:450 (HAPROXY_CLIENT_IP unknown-option on 7.85.0), :350 | partly |
| :236 | and every PROXY_ TLS option | transfer.sls:2130-2131 (the four fields'), :2158-2164 (the rest) | tests/test-unsupported.sps:350 (each written out); weak: the list is five libcurls' tables, the loaded one's never walked | held |
| :237 | SUPPRESS_CONNECT_HEADERS stays the hatch's | transfer.sls:2312 (owned since M8 slice 2), :2283-2287 (why), :2264 (the hatch's until slice 2) | tests/test-unsupported.sps:478 (refused, owned-option) | wrong |
| :237-238 | PROXY_SERVICE_NAME and SOCKS5_AUTH stay the hatch's | transfer.sls:2295-2313 (not listed) | tests/test-unsupported.sps:450 (taken, kept as attached) | held |
| :238 | none of those changed what was sent | libcurl's; transfer.sls:2262-2263 records the measurement | none | held, unheld |
| :238-239 | CONNECT_TO stays the hatch's | transfer.sls:2295-2313 (not listed) | tests/test-unsupported.sps:380 (taken, kept) | held |
| :239 | CONNECT_TO moves the host and port the proxy's CONNECT names | libcurl's | none | held, unheld |
| :241-242 | sessions and calls take proxy, proxy-ca-file and proxy-verify | call.sls:66-67 | tests/test-proxy.sps:1910 (a session's reach its call) | held |
| :242 | a call's replaces its session's | call.sls:742, :745-752 | tests/test-proxy.sps:1918 (call's proxy, call's proxy-verify), :1939 (call's proxy-ca-file) | held |
| :242-243 | a call naming its own proxy drops the session's proxy-ca-file and proxy-verify | call.sls:745-752 (`#f` and `#t` when the call names proxy) | tests/test-proxy.sps:1918 | held |
| :243-245 | every redirect hop goes through the same proxy, another server's too, with its credentials | exchange.sls:757-770 (curl-request-with keeps proxy and its TLS keys) | tests/test-proxy.sps:1951 (absolute form, then CONNECT, both with alice's), :1973 (proxy-verify `#f` kept) | held |
| :249-250 | a jar is an engine's; give it to each request whose cookies it keeps | engine.sls:1466-1470 (made on its engine), :842-845; transfer.sls:2674-2678 (only a request with the jar sets SHARE, COOKIEFILE) | tests/test-cookies.sps:714 (another engine's refused), :1049 (a request without it sends and stores none) | held |
| :262-263 | which cookies are kept and sent where are libcurl's rules, varying by version | transfer.sls:2674-2678, :2696 (turns libcurl's engine on, nothing more) | tests/test-cookies.sps:1036 (hosts, three labels deep), :1375-:1460 (by-version tables) | held |
| :264 | a jar holds cookies alone, in memory: no file, no HSTS entry | transfer.sls:2696 (share of cookies alone), :2674-2678 (COOKIEFILE ""), :2305 (COOKIEJAR owned) | tests/test-cookies.sps:285, :289 (no HSTS, no DNS); tests/test-unsupported.sps:502 | held |
| :265-266 | a line is a Netscape line, seven tab fields, `#HttpOnly_` before an HttpOnly domain | engine.sls:1472-1486 (CURLINFO_COOKIELIST's lines); libcurl's format | tests/test-cookies.sps:995 (HttpOnly line read out whole, loads back) | held |
| :266-267 | a Latin-1 string both ways, each byte one char | engine.sls:1486 (bytes->latin-1); transfer.sls:2864 (each char one byte) | tests/test-cookies.sps:581, :1021 (E9 and FF both ways, on the wire) | held |
| :267-268 | their order moves | transfer.sls:2900-2903 (libcurl's hash order, comment) | none | held, unheld |
| :269-270 | a load takes a read-out's form, every line checked before any loads | transfer.sls:2843-2864; engine.sls:1499-1506 (checked on the caller's thread first) | tests/test-cookies.sps:995 (read-out loads back), :1011 (last line refused, none loaded) | held |
| :270 | seven fields, none holding a control char | transfer.sls:2785, :2789-2790 | tests/test-cookies.sps:349 (32 chars, every field's three positions), :359, :385 | held |
| :271-272 | TRUE or FALSE in the 2nd and 4th; a leading dot exactly beside TRUE | transfer.sls:2803-2804, :2806 | tests/test-cookies.sps:429, :435, :456, :462 (whole complements), :466 | held |
| :272-273 | a domain neither empty nor `#`; no Set-Cookie: line | transfer.sls:2786, :2802 | tests/test-cookies.sps:393, :411 (512 cases) | held |
| :273-274 | a path starting `/`; an expiry of digits, at most 9223372036854775807 | transfer.sls:2805, :2807 | tests/test-cookies.sps:474, :479, :485 | held |
| :274-275 | a name; no `;` in name or value, no `=` in the name | transfer.sls:2808-2810 | tests/test-cookies.sps:496, :525 | held |
| :275-276 | name and value 4,096 bytes at most together | transfer.sls:2705, :2811 | tests/test-cookies.sps:501 (each split, both sides of the bound) | held |
| :276-278 | `__Secure-`/`__Host-` in any case only beside TRUE 4th; `__Host-` path `/` and FALSE 2nd | transfer.sls:2812, :2824-2829 | tests/test-cookies.sps:536 (64 cases), :547, :560 | held |
| :278 | no char above U+00FF | transfer.sls:2784 | tests/test-cookies.sps:349 | held |
| :278-279 | refused cookie-line, naming the index, never the text | transfer.sls:2854-2862 (field lines, value index, irritants index and rule) | tests/test-cookies.sps:589, :1465 (no exit prints a value) | held |
| :280-281 | 7.85.0 lists a tab in a name, a value or a server's Path as an eighth field | libcurl's | tests/test-cookies.sps:1375 (refused-readout-rows: 7.85.0 `fields` for all three; the rest drop them) | held |
| :281-283 | 7.85.0 and 8.5.0 list Path=, Path=TRUE, Path=FALSE, Path=rel as given | libcurl's | tests/test-cookies.sps:1375 (7.85.0, 8.5.0 as given; 8.20.0, 8.23.0 `/`; 8.7.1 as given too, unnamed) | held (8.7.1 unnamed) |
| :283-285 | 7.85.0, 8.20.0 and 8.23.0 list an off-case prefix cookie breaking its rule; 8.5.0 drops it | libcurl's | tests/test-cookies.sps:1375 (as stated; 8.7.1 drops too, unnamed) | held (8.7.1 unnamed) |
| :286-287 | Domain=localhost kept without PSL, dropped with it; set from localhost, host-only on 8.5.0 | libcurl's | tests/test-cookies.sps:1441 (domain-localhost-rows: 8.20.0/psl, 8.5.0/psl drop; no-psl lanes keep; 8.5.0 host-only) | held |
| :287-288 | the default path ends in `/` on 7.85.0 and 8.5.0 | libcurl's | tests/test-cookies.sps:1460 (matrix-rows; 8.7.1 too, unnamed) | held (8.7.1 unnamed) |
| :288-289 | 8.20.0 and later cap an expiry at 400 days | libcurl's | tests/test-cookies.sps:1460 | held |
| :289 | Max-Age=-1 keeps a session cookie on 7.85.0 | libcurl's | tests/test-cookies.sps:1460 (7.85.0 expiry 0, sent) | held |
| :290-291 | 7.85.0 and 8.5.0 list a deleted cookie at expiry 1, and a loaded expired one until another is added | libcurl's | tests/test-cookies.sps:1460, :1386 (expired-rows; 8.7.1 too, unnamed) | held (8.7.1 unnamed) |
| :292-294 | a load is about n^2 on the engine's thread, its transfers waiting; 10,000 lines 0.24-0.50 s, 50,000 up to 27 s; a read-out of 50,000 1.7-6.4 s | engine.sls:1616-1631 (on the engine's thread), :1496-1497 (the load's timings, comment); the read-out's timings are recorded nowhere in src or tests | none | held, unheld |
| :295-300 | on 7.85.0 a 4 KB cookie beside a 4,200-byte URL or a 4,300-byte user agent leaves the head unended, 28 | libcurl's | tests/test-cookies.sps:1433 (open-head-rows: 7.85.0 28, head left open; the rest 200); the Authorization case is not measured | held |
| :301-302 | a Cookie or Host header beside a jar, any case, any value, refused as made: cookie-beside-jar | transfer.sls:1657-1661, :1274 | tests/test-cookies.sps:663, :683, :694 (A to Z folded alone), :703 (again at check and submit) | held |
| :302-303 | libcurl would send a second Cookie, or match the jar against your Host | libcurl's; transfer.sls:1650-1655 records it | none | held, unheld |
| :304-305 | a submit refuses another engine's jar (cookie-jar-engine) and a closed one (cookie-jar-closed) | engine.sls:842-845 | tests/test-cookies.sps:714, :1106 | held |
| :305-306 | a close crossing a submit fails its token so | engine.sls:2052-2059 (set-up! checks again) | tests/test-cookies.sps:1147 (controlled), :1184, :1201 | held |
| :307 | a close frees the jar once no transfer holds it | engine.sls:1711-1718, :1724-1736 | tests/test-cookies.sps:1106 | held |
| :307-308 | an engine's stop frees every jar | engine.sls:1747-1749, :2161 | tests/test-cookies.sps:1214 | held |
| :308 | each jar procedure waits for the engine, as a stop does | engine.sls:1450-1454 (reply-of, no bound) | tests/test-cookies.sps:631 (refused inside a critical section, as a waiter), :1082 (a load waits queued); weak | held |
| :309 | a stopped engine's jar raises as a submit would | engine.sls:1426-1443 (post-jar!: stopped, or the failure) | tests/test-cookies.sps:1214, :1232 (failed) | held |
| :310-311 | the hatch refuses SHARE, COOKIE, COOKIEFILE, COOKIEJAR, COOKIELIST, COOKIESESSION | transfer.sls:2132 (SHARE, COOKIEFILE the field's), :2305, :2311 | tests/test-unsupported.sps:502 | held |
| :311-312 | COOKIELIST would clear or fill the jar of every transfer that holds it | libcurl's; transfer.sls:2270-2273 records it | none | held, unheld |
| :312-313 | HSTS_CTRL and CONNECT_TO stay the hatch's | transfer.sls:2295-2313 (not listed) | tests/test-unsupported.sps:502 (HSTS_CTRL), :380 (both) | held |
| :313-314 | a jar's cookies follow the URL's host, not the server CONNECT_TO routes to | libcurl's; transfer.sls:2278-2282 (read in source) | none | held, unheld |
| :316 | a session takes cookies, `#f` by default | call.sls:81, :345-352 | tests/test-cookies.sps:1348 (none sent or kept), :1521 (a boolean; a call's refused) | held |
| :316-318 | `#t` keeps a jar on its engine, carried by every call and every redirect hop | call.sls:527-531, :753; exchange.sls:757-770 | tests/test-cookies.sps:1323, :1339 (hop to another origin sends it) | held |
| :318 | the session's close frees it | src/http-client.sls:684-686 (close stops the engine) | tests/test-cookies.sps:1545 (stopped after close), :1579 (every count zero at the end); weak | held |
| :318-319 | http-session-cookies reads it out, http-session-load-cookies! loads into it | src/http-client.sls:678-682 | tests/test-cookies.sps:1323 | held |
| :319-320 | a Cookie or Host header, the session's or a call's, refused beside it | call.sls:530 (session's through curl-request-with), :753 (the call's request takes the jar) | tests/test-cookies.sps:1533 (session's Cookie and host), :1348 (call's Cookie) | held |
| :324-325 | `(curl unsupported)` attaches a libcurl option to a request by its name | `src/curl/unsupported.sls:27-29` (exports only `curl-request-with-options`); `transfer.sls:3045-3070` | `tests/test-unsupported.sps:236` (exports curl-request-with-options alone); `:546` (each hatch type attached) | held |
| :335-336 | A hatch option can change what chez-curl tests: it is set last, after chez-curl's own options | `transfer.sls:4867-4872` (the hatch loop is the last form of `set-transfer-options!`); `src/curl/unsupported.sls:4-7` | `tests/test-transfer.sps:1682` (set-transfer-options! form by form, the hatch loop last; it reads the source, it does not run anything) | held |
| :337-338 | A value is plain data, matching the option's type: an integer, a string, a list of strings or a bytevector | `transfer.sls:2927` (`hatch-types`); `:2992-3030` (`hatch-value`: long and off_t ranges, string, slist, blob) | `tests/test-unsupported.sps:546` (each type); `:589` (long range); `:595` (off_t range); `:600` (wrong shapes) | held |
| :338-339 | Options that take a pointer or a callback are refused | `transfer.sls:3058-3059` (`unsupported-type` for any type outside `hatch-types`) | `tests/test-unsupported.sps:539` (STDERR, DEBUGDATA, XFERINFOFUNCTION) | held |
| :340 | No string may hold NUL, CR or LF | `transfer.sls:2973-2983` (`text-fault`); `:2996-2999`; `:3054` (a NUL in the name) | `tests/test-unsupported.sps:614` (every position); `:635` (each string of a list); `:285` (a NUL in the name) | held |
| :341 | Options chez-curl sets itself are refused, as `owned-option` | `transfer.sls:2295-2313` (`owned-option-names`, which includes every `request-field-options` row, `:2120-2133`: HEADERFUNCTION and HEADERDATA, now set on every transfer, at `:2128`; MIMEPOST at `:2123`); `:3057` | `tests/test-unsupported.sps:350` (every owned name written out); `:478` (HEADERFUNCTION, HEADERDATA); `:361` (MIMEPOST); `tests/test-transfer.sps:1884` (every option set-transfer-options! sets is owned); `:1433` | held |
| :341-342 | So is any option that does the same job another way (a twin) | `transfer.sls:2298-2312` (the twins in `owned-option-names`) | `tests/test-unsupported.sps:350`; `tests/test-transfer.sps:1383` (owned-option-names written out) | held |
| :341-346 | Every refusal falls in one of three kinds: set by chez-curl, a twin, or one of a few that reach past the request | `transfer.sls:2300` MIME_OPTIONS and `:2312` SUPPRESS_CONNECT_HEADERS, which chez-curl never sets; comments `:2181-2184` and `:2283-2290` say they are owned so they cannot undo chez-curl's multipart encoding and its header cap | `tests/test-unsupported.sps:361` (MIME_OPTIONS); `:478` (SUPPRESS_CONNECT_HEADERS) | partly |
| :342-343 | COOKIEFILE and COOKIEJAR are refused (they read stdin or write stdout) | `transfer.sls:2132` (COOKIEFILE now belongs to the cookie-jar field); `:2305` (COOKIEJAR); reason at `:2210-2214` | `tests/test-unsupported.sps:502` | held |
| :344 | COOKIELIST is refused (it reaches into a cookie jar) | `transfer.sls:2311` | `tests/test-unsupported.sps:502` | held |
| :345 | RESOLVE is refused (it steers later requests) | `transfer.sls:2306`; reason at `:2215-2217` | `tests/test-unsupported.sps:350` | held |
| :345 | DOH_URL is refused (it skips the `proxy` key) | `transfer.sls:2306`; reason at `:2215` | `tests/test-unsupported.sps:350` | held |
| :345-346 | A refusal names the option | `transfer.sls:2938-2953` (`refuse-option`: field `options`, value NAME as given) | `tests/test-unsupported.sps:350` and the other `refused-as` rows (`:197-198` asserts the value is the name) | held |
| :347 | An option is checked when you attach it | `transfer.sls:3045-3070` (chez-curl's checks run at attach); `:2431-2443` (libcurl can still refuse the value when the transfer is set up: `setopt-failed`) | `tests/test-unsupported.sps:350` (the attach raises before anything native exists); `tests/test-transfer.sps:2459` (LOW_SPEED_LIMIT -2 is taken at attach, then the transfer fails `setopt-failed`) | partly |
| :347-348 | The request keeps its own copy, so changing your string later changes nothing | `transfer.sls:2957-2970` (`option-pairs` copies the names); `:2992-3030` (`hatch-value` copies the values) | `tests/test-unsupported.sps:650` (the request keeps copies); `:888` (the engine sends the attached copy) | held |
| :349 | VERBOSE and NOPROGRESS write to your program's stderr | Up to libcurl. Neither option is owned (`transfer.sls:2295-2313`). STDERR is refused as an object (`:2927`, `:3058`). `src` sets no DEBUGFUNCTION, XFERINFOFUNCTION or PROGRESSFUNCTION (grep finds none) | none | held, unheld |
| :349-350 | VERBOSE writes every header it sends, a password among them | Up to libcurl; nothing in `src` | none | held, unheld |
| :351 | A path is opened as given; chez-curl does not check it | `transfer.sls:2992-3030` (a string value is checked only for NUL, CR and LF) | none | held, unheld |
| :351-352 | A path of `/dev/stdin` is your program's stdin | Up to libcurl and the OS; nothing in `src` | none | held, unheld |
| :356-357 | `stream-buffer` is a size in bytes; the token hands over the body in pieces instead of keeping it whole | `transfer.sls:1242-1243` (a positive exact integer); `:3490-3520` (`stream-chunk!`); `:5156` (a streamed response's body is `#f`) | `tests/test-request.sps:373`; `tests/test-stream.sps:608` (4 MiB by next-piece and by the port, the body `#f`); `:685` (the token's bound) | held |
| :367 | (block) The head comes first | `transfer.sls:3634-3653` (`head-line!` publishes the final head at its empty line) | `tests/test-stream.sps:1016` (the head comes before the first piece) | held |
| :372 | (block) `next-piece` answers the eof object at the end | `engine.sls:964-985` | `tests/test-stream.sps:608` | held |
| :375 | (block) The outcome is the response with its body `#f`, or the failure | `transfer.sls:5156`; `engine.sls:559` | `tests/test-stream.sps:608` (response 200 with body `#f`); `:1371` (a failure, 28) | held |
| :378 | A full buffer pauses the transfer; taking pieces resumes it | `transfer.sls:3504-3506` (answers `CURL_WRITEFUNC_PAUSE`); `engine.sls:964-985` (each look decides the resume) | `tests/test-stream.sps:666` (backpressure); `:735` (the resume comes at half the buffer); `:759` (one resume per pause) | held |
| :379 | Over HTTP/1.1 the server then waits too | libcurl stops reading the socket (ADR-0030, decision 5) | `tests/test-stream.sps:666` (the origin's writes stall, and the kernel takes no more bytes across a second) | held |
| :379-381 | Over HTTP/2, a paused stream that shares a busy connection keeps receiving into libcurl's memory, up to its window: tens of MB | Up to libcurl. ADR-0030 decision 5 measured 10.6 to 66.9 MB once, by probe. `engine.sls:408-416` turns multiplexing off on 8.7.x | none | held, unheld |
| :382-383 | The timeout runs while you are not reading; `timeout-ms` ends a paused transfer | `transfer.sls:4839-4841` (TIMEOUT_MS) | `tests/test-stream.sps:1371` (a paused transfer times out with 28) | held |
| :384 | `curl-token-body-port` reads the pieces through a binary input port | `engine.sls:1000-1043` | `tests/test-stream.sps:608` | held |
| :385-386 | Read with `get-bytevector-some` or `get-u8`: when the transfer fails, `-n`, `-n!` and `-all` lose the bytes they had read | `engine.sls:1037` (`read!` raises the outcome); `:988-990` | `tests/test-stream.sps:1256` (each get-bytevector form's loss, pinned) | held |
| :387-388 | The port belongs to its thread; another thread's close raises `&curl-wrong-thread` | `engine.sls:1010-1018` (`own`); `:1042-1043` (close calls `own` first) | `tests/test-stream.sps:1283` | held |
| :388-389 | So does another thread's read that needs more than the port had buffered | `engine.sls:1021-1022` (`read!` calls `own`) | `tests/test-stream.sps:1302`; `:1324` | held |
| :389-390 | Bytes the port already buffered go to whichever thread reads them | Chez's port buffer, which never calls `read!`; `engine.sls:993-996` | `tests/test-stream.sps:1302` | held |
| :390-392 | Another thread's `-n`, `-n!` or `-all` that takes the buffered bytes and then raises loses them | `engine.sls:1021-1022` | `tests/test-stream.sps:1324` | held |
| :392 | Closing the port cancels the transfer | `engine.sls:1042-1043` (close calls `curl-token-cancel`) | `tests/test-stream.sps:1358` | held |
| :392-393 | A port you never close leaves its transfer paused until its timeout or its engine's stop | `engine.sls:997-998` ("No collection, and no exit, closes it"; `src` has no guardian) | `tests/test-stream.sps:1371` (paused until the timeout); `:1552` (a stop while paused). Weak: neither test drops an unclosed port and watches it stay paused | held |
| :394 | One request per transfer | `transfer.sls:1268-1269` (follow), `:1730-1732` (Expect), `:854-855` (Digest). But a streamed response sets no FRESH_CONNECT (`:4819-4820` covers an upload only), and libcurl's retry of a lost request is no follow (`:2346-2352`) | `tests/test-stream.sps:403`; `:454` | partly |
| :394-396 | `stream-buffer` is refused beside an Expect header that holds 100-continue | `transfer.sls:1707-1711` (`expect-continue?`); `:1730-1732` (`stream-with-rounds`), checked again at submit | `tests/test-stream.sps:454`; `:483` (at submit, on copies); `:506` (the rule) | held |
| :395-396 | A 417 makes libcurl send the request twice, and the stream's head would be the first answer's | Up to libcurl; `transfer.sls:1724-1728` (the reason) | `tests/test-headers.sps:480` (a 417 and its resend's 200 inside one transfer); `tests/test-auth.sps:1304`. Weak: a whole body, not a stream | held |
| :396-398 | The hatch's HTTPAUTH and PROXYAUTH are refused whatever the request | `transfer.sls:2129` (HTTPAUTH, the credentials field's); `:2309` (PROXYAUTH) | `tests/test-stream.sps:403`; `:427` (on a whole body too); `tests/test-unsupported.sps:410`; `:450` | held |
| :398-399 | Digest credentials beside a stream are refused, `digest-with-stream` | `transfer.sls:854-855` | `tests/test-auth.sps:585` | held |
| :400-401 | On libcurl 8.7.0 and 8.7.1, each HTTP/2 transfer gets a connection of its own | `engine.sls:408-416` (`multiplexing-off?`); `:1805-1809` (the engine sets CURLMOPT_PIPELINING to 0) | `tests/test-stream.sps:530`; `:534`; `:538`; `:1638` (by behaviour); `tests/test-version.sps:703`. The 8.7.x arm runs on the Mac lane alone | partly |
| :405-406 | With `body 'stream`, the token takes the body from your puts | `transfer.sls:4747-4760` (`method-settings`); `engine.sls:1196-1236` (`put-piece`) | `tests/test-upload.sps:562` | held |
| :406-407 | `body-length` is sent as Content-Length | `transfer.sls:4757-4759` (INFILESIZE_LARGE for put, POSTFIELDSIZE_LARGE for the rest) | `tests/test-upload.sps:562` (Content-Length when sized); `tests/test-request.sps:494` | held |
| :407 | With `body-length #f`, the body is sent chunked | `transfer.sls:4748` (a size of -1) | `tests/test-upload.sps:562` ("Transfer-Encoding: chunked over HTTP/1.1 when not, neither over HTTP/2") | partly |
| :418 | (block) `room-wait` answers `#t` once libcurl asks for the body | `engine.sls:1153-1162`; `transfer.sls:3887-3891` (`upload-room?`: asked, and room left) | `tests/test-upload.sps:876` (`#f` before libcurl asks); `:886` (`#t`) | held |
| :422 | (block) `await` answers the response, or raises the failure | `engine.sls:862` | `tests/test-upload.sps:562`; `:1053` | held |
| :425-428 | A resend libcurl wants after a piece has been handed (a dead connection, a refused HTTP/2 stream) fails `body-not-replayable` | `transfer.sls:4082-4106` (the seek callable); `:4124-4149` (the prerequest callable) | `tests/test-upload.sps:1152` (by version, through the seam); `:1183`; `:1193` (REFUSED_STREAM) | held |
| :428-429 | An upload never reuses a pooled connection: it opens one, and over TLS does a handshake | `transfer.sls:4819-4820` (FRESH_CONNECT) | `tests/test-upload.sps:1143` | held |
| :429-431 | Once the upload ends, a later transfer may reuse its connection, or share it over HTTP/2 while it runs | `transfer.sls:4819-4822` (FRESH_CONNECT; FORBID_REUSE only when a tunnel asks) | none | held, unheld |
| :432 | A put waits while the buffer holds 64 KiB | `transfer.sls:3715` (`upload-buffer-limit` 65536); `:3840-3842` | `tests/test-upload.sps:886`. Weak: its 64 KiB puts hold the buffer between 64 and 128 KiB, and no test writes 65,536 out | held |
| :432-433 | A put given a bound answers `#f` once the bound passes | `engine.sls:1225-1235` | `tests/test-upload.sps:886`; `:857` | held |
| :434 | `done` means the transfer has ended; a put that answers `done` took nothing | `engine.sls:1206-1215` | `tests/test-upload.sps:481`; `:521`; `:911` | held |
| :434-435 | `curl-token-outcome` tells how the transfer ended | `engine.sls:559` | `tests/test-upload.sps:857` (the outcome is readable at once) | held |
| :436-437 | The timeout runs while you are not putting; `timeout-ms` ends a waiting upload | `transfer.sls:4839-4841` (TIMEOUT_MS) | none. No suite times out an upload paused for sending; the 28 in 7.85.0's HTTP/2 row at `tests/test-upload.sps:1281` comes after the rest was put | held, unheld |
| :438-439 | An end short of `body-length`, or a piece past it, fails `body-length-mismatch`; the put past it raises | `transfer.sls:3836-3838`; `:4040`; `engine.sls:1216-1223` | `tests/test-upload.sps:1053`; `:1111` | held |
| :440-441 | An early answer ends the upload; after it, every put answers `done` | Up to libcurl; `engine.sls:1206-1215` | `tests/test-upload.sps:1291` (by version; once done, a put and a room-wait answer `done`) | held |
| :441-442 | Some libcurls end such a transfer only at your next put or end | Up to libcurl | `tests/test-upload.sps:1291`, rows `:1281` (7.85.0: every 413 waits), `:1283` (8.5.0: `either`), `:1285` (8.7.1: the kept and HTTP/2 413s wait), `:1287` and `:1289` (8.20.0, 8.23.0: `own`) | held |
| :443-444 | `curl-token-body-count` counts what your puts committed to the buffer, not what reached the server | `engine.sls:1256-1257` | `tests/test-upload.sps:911` (65,536 counted though libcurl never asked); `:931` | held |
| :445-448 | An early 200 can end the transfer as a success with the body cut: over HTTP/1.1 with a close on 8.5.0, 8.20.0 and 8.23.0; over HTTP/2 on 8.5.0 | Up to libcurl | `tests/test-upload.sps:1291`: `raw-200-close own 200` in rows `:1283` (8.5.0), `:1285` (8.7.1), `:1287` (8.20.0) and `:1289` (8.23.0); `h2-200 own 200` in row `:1283` (8.5.0) alone | held (8.7.1 unnamed) |
| :448-449 | On 7.85.0 the transfer waits for your next put; over HTTP/2 its upload then never ends, and the timeout ends it | Up to libcurl | `tests/test-upload.sps:1291`, row `:1281` (`raw-200-*` waits 200, `h2-200 waits 28`) | held |
| :451-453 | Over HTTP/2, a transfer that streams both ways sends only while you read the response | Up to libcurl. Measured by probe once, `.plans/2026-10-29-m6-plan.md:589`; 8.7.1 not measured | none. `tests/test-upload.sps:1536` reads the response only after the whole body is put | held, unheld |
| :454-458 | On Ubuntu's 8.5.0 over HTTP/2, a paused upload can rarely hide the answer: a head wait times out, and the transfer may wait until its timeout | Up to libcurl. Recorded only in the AGENTS.md trap (9 of 4,760 runs natively) and the comment at `tests/test-upload.sps:719-729` | none | held, unheld |
| :462 | Follows a 301, 302, 303, 307 or 308 that has a Location (a blank Location is answered) | `exchange.sls:591` (statuses), `:830-831` (no or blank Location is done) | `tests/test-redirect.sps:411` (statuses table); `:431` (blank Location answered) | held |
| :463 | Default bound is 20 redirects | `call.sls:105`, `:338-339`; `exchange.sls:835-836` (too-many-redirects) | `tests/test-redirect.sps:1072` (live loop: default 20 follows 20, then too-many) | held |
| :463 | The session or the call sets the bound; the call's wins | `call.sls:325-332` (policy-of), `:675-677` | `tests/test-redirect.sps:1082` (call's 1 over session's 0; call's #f over session's) | held |
| :464 | `#f` follows none and answers the redirect | `exchange.sls:832` | `tests/test-redirect.sps:440` (table); `:1082` (live) | held |
| :466-467 | To another origin (scheme, host, port) the call drops Authorization and Cookie | `exchange.sls:700-702` (credential-header?), `:763`, `:801-808` (across) | `tests/test-redirect.sps:605` (table); `:956`, `:1008` (live, by port, by scheme) | held |
| :467 | ...and drops Proxy-Authorization | no such drop: `exchange.sls:695-702` names Authorization and Cookie only; `transfer.sls:523` refuses the header when the request is made, so none reaches a redirect | `tests/test-redirect.sps:646` (refused, proxy-authorization-header; "its drop ... unreachable"); `:976` (live) | partly |
| :468 | ...and drops the `credentials` key | `exchange.sls:771`, `:805-808` | `tests/test-redirect.sps:631` (table); `:1021` (live) | held |
| :468 | ...and drops Host when the host changes (another zone ID too) | `exchange.sls:764`, `:801-804` | `tests/test-redirect.sps:605`; `:1021` (live) | held |
| :468-469 | A dropped header stays dropped, even back on the first origin | `exchange.sls:809` (next request built from the step's request), `:757-765` | `tests/test-redirect.sps:653` (table); `:988` (live) | held |
| :469-470 | Every other header follows; X-Api-Key reaches the new origin | `exchange.sls:760-765` (filter keeps the rest) | `tests/test-redirect.sps:605` (X-Api-Key in origin-headers, kept on every row); `:956` (live) | held |
| :471 | A `user:pass@` in the URL stays for a relative Location | `exchange.sls:661-668` -> `url.sls:488` (curl-url-resolve: libcurl's resolution) | `tests/test-url-location.sps:620` (shared rows: me:secret kept for `/x/y`, dropped for netpath `//host/np`); direct calls of curl-url-resolve, no hop | partly |
| :471-472 | An absolute Location carries its own userinfo, or none | `exchange.sls:661-668`; `url.sls:488` | `tests/test-url-location.sps:620` (rows "userinfo" carries u:p; "other-host" from me:secret has none) | held |
| :473 | https to http is refused unless `allow-downgrade` is `#t` | `exchange.sls:796-799` (insecure-redirect) | `tests/test-redirect.sps:514` (table); `:1032`, `:1041` (live) | held |
| :474 | A 303 makes a get of every method but head | `exchange.sls:674-678`, `:768` | `tests/test-redirect.sps:571` (every status x method) | held |
| :474-475 | A 301 or 302 makes a post a get | `exchange.sls:676` | `tests/test-redirect.sps:571` | held |
| :475-476 | The body goes, with Content-*, Digest, Last-Modified and Expect | `exchange.sls:691-693` (body-header?), `:762`, `:770` (body #f, body-length #f) | `tests/test-redirect.sps:571`; `tests/test-multipart.sps:1408` (a multipart 303 sends a get with no body) | held |
| :477-479 | Producer's body: once libcurl asked, a 307/308, or a 301/302 of any method but post, raises body-not-replayable | `exchange.sls:436-437` (spent?), `:833-834`; `drive.sls:1035-1036` (head's bit marks called) | `tests/test-stream-call.sps:684` (table); `:949` (live, every status and method) | held |
| :483-484 | `call-with-response-port` hands the procedure the response and a binary port over the body as it arrives | `src/http-client.sls:727-740`; `drive.sls:1064-1075` (final!), `:908-956` (call-port) | `tests/test-stream-call.sps:836` | held |
| :500 | The response has no body: its body and timings are `#f` | `drive.sls:890-891` (head-response), `exchange.sls:582-584`; but `drive.sls:1087-1091` hands a retry run out of time its read body | `tests/test-stream-call.sps:836` (#f); `:760` (retry run out: body read, port in memory) | partly |
| :500-501 | `http-response-text` refuses it | `exchange.sls:285-293` | `tests/test-stream-call.sps:512` (table-built response) | held |
| :502 | The procedure's values are the call's | `drive.sls:1106-1119` | `tests/test-stream-call.sps:836` ("the call answers its two values") | held |
| :502-503 | When it returns or escapes, the port is closed and the transfer cancelled | `drive.sls:1108-1116` (critical wind's after thunk), `:955-956` (close cancels) | `tests/test-stream-call.sps:978` (return); `:992` (escape by raise) | held |
| :503-505 | A Chez engine's expiry is an escape: cancelled; resumed reads raise that cancel, then Chez's closed-port error | `drive.sls:1108-1116`, `:947-953` | none (`tests/test-http-client.sps:1549` covers http-get only) | held, unheld |
| :506-508 | `timeout-ms` bounds the whole call, reading included; a slower reader meets `&http-timeout` | `exchange.sls:524-529` (time left is each transfer's timeout-ms), `:561-569` (exchange-raised); `drive.sls:951` | `tests/test-stream-call.sps:1104` | held |
| :508 | `timeout-ms #f` leaves the call unbounded | `exchange.sls:515-516`; `src/curl.sls:102` (default #f) | `tests/test-http-client.sps:669` (core: no bound submits as is) | held |
| :509 | The port is read on the call's thread | `drive.sls:916-920`, `:926-927` (own) | `tests/test-stream-call.sps:1065` (read), `:1079` (close) | held |
| :510-511 | When the transfer fails, the read raises its failure, every time after | `drive.sls:935`, `:947-953` | `tests/test-stream-call.sps:1104` ("every time after") | held |
| :511 | get-bytevector-n, -n! or -all then loses the bytes it had read | Chez's custom port, `drive.sls:955` | `tests/test-stream.sps:1256` (the low level's port, not the call's) | held |
| :512 | `stream-buffer` is 64 KiB unless given | `call.sls:110`, `:700-701` | none | held, unheld |
| :512-513 | A full buffer pauses the transfer | `transfer.sls:3504-3506` (CURL_WRITEFUNC_PAUSE) | `tests/test-stream.sps:666` (backpressure, low level) | held |
| :514-515 | A streamed call (this one, or a producer's) decides redirects and retries at each head | `src/http-client.sls:717-719`; `drive.sls:1029-1048` | `tests/test-stream-call.sps:652` (predicate table); `:867` (redirect), `:890` (retry) | held |
| :516 | A hop's body is read into the history | `drive.sls:1054-1063` | `tests/test-stream-call.sps:867` | held |
| :516-517 | A hop whose request sends a body is cancelled at its head; its history entry's body and timings `#f` | `drive.sls:1050-1053`, `:882-884` | `tests/test-stream-call.sps:879` (whole body 307); `:1400` (producer's 303) | held |
| :517-518 | If a retry's wait then leaves no time, the call meets `&http-timeout` | `exchange.sls:491-495`, `:519` | `tests/test-stream-call.sps:760`, `:793` | held |
| :522-523 | A body may be a producer: a no-argument procedure answering bytes or the eof object | `call.sls:569-574`, `:696` | `tests/test-stream-call.sps:1122` | held |
| :523-524 | `body-length` sends its length; left out, the body is chunked | `call.sls:699`, `:707`; `transfer.sls:4751-4758` (length or -1) | `tests/test-upload.sps:562` (framing headers, low level); `tests/test-stream-call.sps:1122` (sized and chunked, bodies only) | held |
| :537 | The producer runs on the caller's thread | `drive.sls:714-730` (produce!, on the drive's thread) | `tests/test-stream-call.sps:1122`, `:1582` | held |
| :537-538 | It is called only once libcurl asks for the body | `drive.sls:546-550` (room-wait first) | `tests/test-stream-call.sps:1139` | held |
| :538 | Never called after it answered the eof object | `drive.sls:612-616`, `:551` (ending phase) | `tests/test-stream-call.sps:1122` (none after its end) | held |
| :538-539 | It answers a bytevector of a byte or more, or eof; anything else is an assertion violation | `drive.sls:617`, `:634-641` | `tests/test-stream-call.sps:1306` (empty bytevector too); `:1277` | held |
| :540-542 | A body short of `body-length` fails from the transfer, body-length-mismatch | `transfer.sls:4031`, `:4040` | `tests/test-stream-call.sps:1167` | held |
| :540-542 | A piece past it is `&http-request-error` body-length-mismatch, before any of it is sent | `drive.sls:619-628` | `tests/test-stream-call.sps:1167` (nothing of that piece put) | held |
| :543-544 | Once libcurl asked, no retry takes the call, whatever the policy | `exchange.sls:436-437`, `:1059-1062` | `tests/test-stream-call.sps:716` (table); `:1518` (live 503) | held |
| :544-545 | A refused connect, before any ask, is still retried | `exchange.sls:1100-1102` (size 0 any method; else methods only); `transfer.sls:2005-2012` (size #f on 8.7.0, 8.7.1) | `tests/test-stream-call.sps:1152` (3 transfers; 1 on 8.7.0 and 8.7.1) | partly |
| :546-547 | Through `call-with-response-port`, the port feeds the producer while you read | `drive.sls:954` (feed! inside read!), `:536-552` | `tests/test-stream-call.sps:1365` (full duplex, raw, raw-tls, h2) | held |
| :547 | A server that answers as the body arrives gets the rest | `drive.sls:954` | `tests/test-stream-call.sps:1365` (echo whole) | held |
| :548-549 | It feeds only when no bytes are waiting, so a faster server holds the upload back | `drive.sls:933` (bytes at hand first), `:939-954` (feeds only when next-piece finds none) | none | held, unheld |
| :549-550 | A procedure that never reads nor returns starves the upload | `drive.sls:954` (fed inside the read alone, once the final head is handed on) | none | held, unheld |
| :551-552 | A producer's raise inside the read sticks: every later read raises it, the call too once the procedure returns | `drive.sls:714-738` (sticky), `:930-931`, `:1117-1119` | `tests/test-stream-call.sps:1256` | held |
| :552-553 | A producer that reads its own port is refused | `drive.sls:928-929` | `tests/test-stream-call.sps:1327` | held |
| :554-555 | `go` and `http-parallel` refuse a producer, stream-in-group | `call.sls:687-689` | `tests/test-stream-call.sps:517` (go), `:540` (http-parallel) | held |
| :556-558 | On 8.20.0 and 8.23.0, an HTTP/2 3xx the call does not follow, arriving before the body is sent whole, ends only at the bound | libcurl's; nothing but the transfer's timeout-ms ends it, `exchange.sls:524-529` | `tests/test-stream-call.sps:1619`, rows `:1605-1609`: 7.85.0, 8.5.0, 8.7.1 end with the 303; 8.20.0, 8.23.0 give 28 and `&http-timeout`, producer and whole body alike | held |
| :559 | A whole bytevector's redirect waits the same way through `http-request` | `drive.sls:403-407` (drive-exchange awaits the transfer's end before stepping) | `tests/test-stream-call.sps:1619` (the whole-body cell, redirects #f: weak, it measures the final 3xx's transfer, not a followed hop) | held |
| :559-560 | A producer's redirect is cut at its head | `drive.sls:1050-1053` | `tests/test-stream-call.sps:1400` (h2 row, on every libcurl) | held |
| :560-561 | On 7.85.0, an early 200 while the body is still owed never ends either | libcurl's | `tests/test-upload.sps:1291`, row `:1281` (7.85.0 h2-200 "waits 28"; low-level streamed body; a whole bytevector body unmeasured) | held |
| :562-563 | An early answer (a 413) ends the call before the body is sent | `drive.sls:1064-1075` (the final head handed on) | `tests/test-stream-call.sps:1382` (413 handed, call ends early: raw kept and closed, raw-tls, h2) | held |
| :563 | ...and the rest of the body is never sent | `drive.sls:522-529`, `:1069-1070` (the final head is fed whenever libcurl asks) | none (`:1382` asserts no cut) | partly, unheld |
| :567 | `call-with-request-group` runs many calls on the caller's one thread | `drive.sls:1580-1616`, `:1490-1515` (turn!) | `tests/test-group.sps:2483` (20 held at once) | held |
| :568-569 | `go` starts a call and answers its pending at once | `drive.sls:1582-1602` | `tests/test-group.sps:1401` (three held at once without awaiting) | held |
| :569 | `http-await` gives its response | `drive.sls:1736-1756` | `tests/test-group.sps:1401`; `:2346` | held |
| :569-570 | `limit` caps calls in flight; the rest wait their turn | `drive.sls:1386-1397` (admit-one!) | `tests/test-group.sps:2488` (at most 2 held); `:2183` (FIFO) | held |
| :570 | Each waiting call is on its own clock | `drive.sls:1592` (deadline from go), `:1361-1367` (expire!), `:1504-1510` | `tests/test-group.sps:2373`; `:2427` | held |
| :570-571 | `http-parallel` runs a list and answers the responses in order | `drive.sls:1677-1682` | `tests/test-group.sps:2495` | held |
| :573 | The group waits for every call before it returns | `drive.sls:1608-1612` (join) | `tests/test-group.sps:1401` | held |
| :573-574 | ...then raises the first failure never awaited | `drive.sls:1613-1615`, `:1532-1534` | `tests/test-group.sps:1424`; `:1465` (ties by submit order) | held |
| :574 | A call you cancelled raises nothing | `drive.sls:1781-1790` (exempt), `:1532-1534` | `tests/test-group.sps:2257`; `:2306` | held |
| :575-576 | If the procedure escapes, the group cancels every call and waits for each transfer to end | `drive.sls:1540-1548` (two winds), `:1438-1445` (cancel-all!), `:1459-1464` (drain-all!) | `tests/test-group.sps:1581` | held |
| :576-577 | On 7.85.0 to 7.86.x a stalled lookup can hold that wait up to glibc's resolver timeout | libcurl's; `engine.sls:16-23` (QUICK_EXIT where libcurl knows it) | `tests/test-engine.sps:1057`, row `:411` (7.85.0: cancel stalled; 8.5.0 on prompt). Weak: low-level cancel, Linux only, a 3 s stand-in stall, no 7.86.x row, no group | held |
| :577-578 | A second Ctrl-C during that wait gives up, leaving those transfers running | `drive.sls:1459-1463` (unguarded wait; an escape abandons it) | none (`tests/test-group.sps:1629` holds the cancel, not the abandonment) | held, unheld |
| :579 | Only the thread that made a group may use it | `drive.sls:1206-1211` | `tests/test-group.sps:1330` | held |
| :580 | `http-parallel` checks every call before it sends any, as a send would | `src/http-client.sls:801-816`, `:653` (curl-request-check) | `tests/test-group.sps:2514`, `:2541`, `:2623` | held |
| :581 | Only a stopped or failed engine can still refuse a call partway | `drive.sls:1255-1260` (a submit's refusal fails its call); `transfer.sls:4302`, `:1441-1458` (submit re-stats file parts, part-file) | `tests/test-group.sps:2688` (stopped); `tests/test-multipart.sps:1508` (a group's hop refused part-file) | partly |
| :582-583 | Inside a Chez engine, an expiry ends the whole group: resumed awaits raise cancelled, a new go raises closed | `drive.sls:1438-1445`, `:1584-1600`, `:1756` | `tests/test-group.sps:1789`, `:1804`, `:1821` | held |

## Notes on the table

**Wrong (1).**

- **:237, `SUPPRESS_CONNECT_HEADERS` "stays its, unsupported".** Since slice 2 the hatch
  refuses it as `owned-option`. It hides a CONNECT answer from the header callable, so the cap
  would never count that answer (transfer.sls:2312, comment :2283-2288 and :2264 "did until M8
  slice 2"; tests/test-unsupported.sps:478). `PROXY_SERVICE_NAME` and `SOCKS5_AUTH` are still
  taken (:450).

**Partly (16).**

- **:32-34 and :92-94** (unheld for the environment's case). Through a proxy that does not
  tunnel, libcurl ignores prior knowledge and sends HTTP/1.1. That holds only for the
  environment's proxy. Beside a proxy URL, a submit refuses the request first,
  `prior-knowledge-through-proxy` (transfer.sls:4568-4570, called at :4319;
  tests/test-proxy.sps:885, :1904). :92-94's "the environment's among them" reads as though a
  named proxy also lets the request through and ignores the setting.
- **:155-158** (survey claim 7; touched by slice 2). It says a server answering 417, or a stale
  challenge, for ever ends the transfer at the 30-follow pin with 47. The header cap counts every
  round's response head over the whole transfer (transfer.sls:248-261, :3602-3621;
  tests/test-headers.sps:480, a 417 and its resend summed). So 31 heads averaging more than about
  32 header lines, or about 3.3 KB, end with `header-limit` (23, `&curl-too-large`) first.
  tests/test-auth.sps:1304 and :1317 hold 47 only for small heads.
- **:230-233.** "From its first such request, each later request opens a connection of its own"
  overstates. Before 8.19.0 the engine stops multiplexing alone (CURLMOPT_PIPELINING 0,
  engine.sls:2031-2035, :2062). A later request still reuses an idle pooled connection:
  tests/test-proxy.sps:1846 shows two http:// requests in turn, alice's userinfo on each, both
  on `conn=1` on every libcurl. The rest is held (:1869, :1874).
- **:234-236.** The list of proxy options the hatch refuses lacks `SUPPRESS_CONNECT_HEADERS`,
  owned since slice 2 (transfer.sls:2312). It also lacks options owned before the README was
  written: `PRE_PROXY`, `PROXYPORT` and `PROXYTYPE` (:2302), and `PROXYHEADER` and `HEADEROPT`
  (:2304).
- **:341-346** (a judgement call). The README sorts every refusal into three kinds: an option
  chez-curl sets, a twin of one, or one of a few that reach past the request. Two newly owned
  options fit none of these as a reader would take them. `MIME_OPTIONS` (slice 3, :2300, never
  set; comment :2181-2184) would change how libcurl escapes a part's name and filename, which
  the byte rules own. `SUPPRESS_CONNECT_HEADERS` (slice 2) would hide answers from the cap. The
  code files both as twins.
- **:347, "It is checked when you attach it."** chez-curl's checks all run then
  (transfer.sls:3045-3070). libcurl still judges the value as the transfer is set up, and a value
  it refuses fails the transfer as `setopt-failed` (:2431-2443).
  tests/test-transfer.sps:2459: `LOW_SPEED_LIMIT` -2 attaches, then fails 43.
- **:394, "One request per transfer."** Every round that brings a head of its own is refused:
  follow, a 417's resend, `HTTPAUTH`, `PROXYAUTH` and Digest. But a streamed response sets no
  `FRESH_CONNECT` (transfer.sls:4819-4820 sets it for an upload alone). So libcurl's resend after
  a dead pooled connection, or after HTTP/2's `REFUSED_STREAM`, is still a second request in the
  transfer, though only one head.
- **:400-401** (the survey's "also held"; code unchanged). The behaviour holds: on 8.7.0 and
  8.7.1 each HTTP/2 transfer gets a connection of its own. But the engine does it, not libcurl,
  by setting CURLMOPT_PIPELINING to 0 (engine.sls:408-416, :1805-1809). "Could fail its
  neighbours" is the reason for that rule, not a hazard a caller meets.
- **:407, `body-length #f` "sends it chunked".** True over HTTP/1.1. Over HTTP/2 the body goes
  with neither `Transfer-Encoding` nor `Content-Length` (tests/test-upload.sps:562).
- **:467, the call "drops Proxy-Authorization" across origins.** No redirect rule drops it.
  `credential-header?` names Authorization and Cookie alone (exchange.sls:695-702), because the
  low level refuses that header as a request is made (transfer.sls:523). So no hop holds one, and
  tests/test-redirect.sps:646 calls the drop unreachable. The outcome holds; the mechanism the
  README names does not.
- **:471, `user:pass@` "stays for a relative Location".** That holds for a path or query
  reference. libcurl drops the userinfo for a network-path reference, `//host/p`, which RFC 3986
  counts as relative (url.sls:488; tests/test-url-location.sps:620, the `me:secret` rows).
- **:500, "The response has no body."** That holds at a final head. But a retry that runs out of
  time, having sent nothing, hands the procedure the retried response with its body read, and a
  port over those bytes in memory (drive.sls:1087-1091; tests/test-stream-call.sps:760).
- **:544-545, "A refused connect, before any ask, is still retried."** Not for a post on 8.7.0
  and 8.7.1. A transfer that ran there has request size `#f`, so only the policy's methods are
  retried (exchange.sls:1100-1102; transfer.sls:2005-2012). tests/test-stream-call.sps:1152 makes
  1 transfer there, 3 elsewhere.
- **:563, "the rest is never sent"** (unheld). The drive feeds the producer whenever libcurl asks
  after the final head (drive.sls:522-529, :1069-1070). The low level's table records libcurls
  that take the rest of the body after an early answer (tests/test-upload.sps:1281-1289): every
  7.85.0 cell, 8.7.1's kept and HTTP/2 413, and a kept 200 everywhere. No test asserts the cut:
  tests/test-stream-call.sps:1382 asserts only that the 413 is handed on.
- **:581, "Only a stopped or failed engine can still refuse one partway."** Since slice 3 each
  submit stats a file part's path again (transfer.sls:4302, :1441-1458). So `part-file` can
  refuse a queued call past `limit`, a retry or a hop, after `http-parallel`'s checks passed
  (tests/test-multipart.sps:1508, a group's 307 hop). A hop could already be refused for
  `prior-knowledge-over-https`, `credentials-beside-userinfo` or `proxy-tls-in-tls`
  (transfer.sls:4316-4320).

**Held (8.7.1 unnamed) (7).** :219 (8.7.1 fails 56 too, tests/test-proxy.sps:1827); :222-224
(8.7.1 tries a post once too, its size unknown, :2021); :281-283 (it lists the paths as given,
tests/test-cookies.sps:1375); :283-285 (it drops the off-case prefix cookies, as 8.5.0 does,
:1375); :287-288 and :290-291 (its default path ends in `/`; it lists the deleted and the expired
cookie, :1460, :1386); :445-448 (`raw-200-close own 200` on 8.7.1 too,
tests/test-upload.sps:1285). Range C's agent marked :445-448 partly. I made it this mark, for one
rule across the table.

**Unheld (46), grouped.** Most are libcurl's, the TLS library's or Apple's behaviour, recorded in
an ADR, a plan or a source comment and measured by no suite.

- Environment: :30 (`HTTP_PROXY` ignored); :35-36 (a variable's userinfo unchecked); :36-38
  (control-byte userinfo direct on 7.85.0 and 8.5.0, 3 from 8.20.0); :40-41 (a variable's
  https:// proxy checked against the store); :45-46 (Guix 8.20.0's override itself); :51-52
  (GnuTLS's `pkcs11:`); :54-56 (`SSLKEYLOGFILE`); :57-58 (`OPENSSL_CONF`); :60-62 (the
  keychain fallback); :65-66 and :66-67 (`OPENSSL_X509_TEA_DISABLE`); :68-69 (8.7.x's raw
  count); and :32-34 and :92-94, partly above.
- Credentials: :144-145 (8 KiB everywhere, 64 KiB over HTTP/1.1 alone); :147 (a 1 MiB Digest
  password passes); :158-159 (a dead connection's retry is no follow).
- Proxy: :187 (libcurl's own 1080, and 8.23.0's 80); :202-203 and :207-208 (prior knowledge
  ignored); :205 (the error buffer); :211-212 (Proxy-Authorization into a tunnel); :213-215 (the
  TLS-in-TLS stall itself); :217-218 (the environment's stall not refused); :227-228 (the CVE
  ride); :238 (two options changed nothing); :239 (`CONNECT_TO` moves the CONNECT).
- Cookies: :267-268 (the order moves); :292-294 (a load's n² and every timing; the read-out's
  1.7 to 6.4 s is recorded nowhere in `src` or `tests`); :302-303 (a second Cookie, the Host
  match); :311-312 (`COOKIELIST`'s reach); :313-314 (cookies follow the URL's host).
- Hatch: :349, :349-350 (`VERBOSE`, `NOPROGRESS`, a password in a header); :351, :351-352 (a
  path unchecked, `/dev/stdin`).
- Streams and uploads: :379-381 (HTTP/2's tens of megabytes); :429-431 (an upload's connection
  reused later); :436-437 (the timeout ends a waiting upload); :451-453 (HTTP/2 sends only while
  you read); :454-458 (8.5.0 hides the answer).
- The high level: :503-505 (an engine's expiry in `call-with-response-port`); :512 (the 64 KiB
  default `stream-buffer`); :548-549, :549-550 (feeding only when no bytes wait, and the
  starved upload); :563 (the cut, partly above); :577-578 (a second Ctrl-C abandons the group's
  wait).

**Held weakly** (marked held). :28-30 (`HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY` never set by
a test); :127 (UTF-8 shown for a Digest user alone); :100-101 (`PIPEWAIT` only shown taken, its
effect unmeasured); :162-163 (a scheme change across origins untested); :44-50 (Guix lanes
alone) and :59-65 (the Mac alone); :191-193 (a proxy CA file against the environment shown for
`SSL_CERT_FILE` alone); :203-206 (no lane lacks HTTPS-proxy support); :221-222 (the retry test's
policy is `(503)`, not the default); :392-393 (no test drops an unclosed port); :395-396 (the
417 resend shown on a whole body); :432 (the 64 KiB threshold held by a 64 to 128 KiB range,
65,536 written out by no test); :511 and :512-513 (the low level's port, not the call's); :559
(the whole-body redirect's wait measured with `redirects #f`); :560-561 (a streamed body's cell,
not a call's); :576-577 (7.85.0 alone, a 3 s stand-in stall, Linux alone, no group).

**Undecided** (from the hand-backs; nothing was run for them).

- :236, "every `PROXY_` TLS option": the owned list holds the names of the five measured
  libcurls (transfer.sls:2158-2164). Whether a newer libcurl has one outside it needs a walk of
  the loaded library's option table, which no test makes.
- :503-505: after an engine's expiry the README has resumed reads raise the cancel, then Chez's
  closed-port error. Reading drive.sls:926-956 and :1108-1116, that order holds when the expiry
  lands inside a read. Landing elsewhere, the after thunk has closed the port, and the first read
  should meet the closed port at once. Settling it needs a sweep.
- :560-561: "while a whole body is still owed" reads as either a bytevector body or the body in
  full; only a streamed body is measured.
- :576-577: "7.85.0 to 7.86.x" and "glibc's resolver timeout" come from ADR-0019; only 7.85.0's
  row exists, with a 3 s stand-in stall.

## The survey's ten (item 4)

`logs/readme-survey-carry.log` holds the comparison: which files slices 2 and 3 changed, each
range's text old against new, and each line's move.

| # | README.org | Survey's code (at `fbc6fce`) | Today's code | Touched by slices 2 and 3? | Today | Test |
|---|---|---|---|---|---|---|
| 1 | :13 | require-threaded.sls:43, :79-89 | the same lines | no: the file is not in the diff | held, carried over | tests/test-require-threaded.sps:458, :491, :508 |
| 2 | :14 | verify.sls:26, :35-41 | the same lines | no: not in the diff | held, carried over | tests/test-verify.sps:152, :162, :166 |
| 3 | :51-53 | transfer.sls:492-500; conditions.sls:387 | transfer.sls:563-569 (`pkcs11-prefix?`), :604-607 (the refusal); conditions.sls:387 | no: old 486-560 = new 550-624, byte for byte; conditions.sls's hunks start at :28, then :503 | held, carried over (:51-52, GnuTLS's reading, unheld) | tests/test-transfer-tls.sps:468, :487, :497 |
| 4 | :64-65 | Makefile:34-37 | Makefile:34-37 | no: the Makefile's hunks start at old :72; 34-37 the same | held, carried over | tests/test-transfer-tls.sps:1071 |
| 5 | :95-101 | no `"PIPEWAIT"` in `src/`; absent from owned (:1781-1798) and pinned (:1818-1820) | comments alone, transfer.sls:141, :999, :2237; absent from `owned-option-names` :2295-2313 and `pinned-options` :2333-2335 | yes: the owned list changed (`MIMEPOST` moved, `MIME_OPTIONS` and `SUPPRESS_CONNECT_HEADERS` added). Checked again: still absent | held | tests/test-version.sps:687; tests/test-unsupported.sps:380 (taken) |
| 6 | :105-107 | transfer.sls:1628, :1793 | transfer.sls:2129, :2307 | yes, the same lists. Checked again: present | held | tests/test-unsupported.sps:380 |
| 7 | :154-159 | transfer.sls:1783; pinned :1818-1820 | transfer.sls:2297; pinned :2333-2335 | the pins no: old 1815-1822 = new 2330-2337. But slice 2's cap now also ends those rounds: checked again | **partly** (:155-158, above); :154-155 held | tests/test-unsupported.sps:410; tests/test-auth.sps:1304, :1317; tests/test-headers.sps:480 |
| 8 | :186-187 | url.sls:324-329 | url.sls:323-332 | no: url.sls is not in the diff; 320-332 the same | held, carried over (:187, libcurl's own ports, unheld) | tests/test-proxy.sps:492, :511 |
| 9 | :264, :274-275 | transfer.sls:2181, :2190 | transfer.sls:2696, :2705 | no: old 2170-2200 = new 2685-2715 | held, carried over | tests/test-cookies.sps:285, :289, :501 |
| 10 | :432, :462-463, :512 | transfer.sls:3124; exchange.sls:591; call.sls:101, :106 | transfer.sls:3715; exchange.sls:591; call.sls:105, :110 | no: old 3110-3130 = new 3701-3721; exchange.sls's hunks are :203 (same length) and :745 (`next-request`); call.sls's values unchanged, moved 4 lines | held, carried over; :512 unheld | tests/test-upload.sps:886 (weak); tests/test-redirect.sps:411, :1072; :512 none |

The survey's three "also held" lines. :98-100 and :400-401 (engine.sls:408, unchanged): held,
but :400-401's wording is partly (above). :66-67 (no `OPENSSL_X509_TEA_DISABLE` in `src/`, still
none): held, unheld. :148-149 (the opaque request, transfer.sls:1102-1128, was :1055): held,
tests/test-auth.sps:778.

## Blocks (item 5)

How they were checked: by reading, then run in the container
(`logs/readme-blocks/run.sh`, output `logs/readme-blocks/run.log`). `bound.sps` evaluates every
name the blocks use in `(rnrs)`, `(curl)`, `(curl unsupported)` and `(http-client)`: each is
bound, `saved-lines` alone unbound. A fragment (1 to 4) ran as a script with `(import (curl))`
before it; a block with its own `import` (5 to 9) ran as an R6RS program as written, and as a
script (the REPL's environment, Chez's names bound). The container has no network, so the
example.com blocks then fail at the transfer; 4 and 6 to 9 ran again against a loopback http
stand-in (`server.mjs`), their `https://example.com` replaced, block 4's `saved-lines` bound
to the jar's read-out, block 9's `big.bin` made (300,000 bytes).

| # | README.org | Kind | Names and keys | As written | Against the stand-in |
|---|---|---|---|---|---|
| 1 | :76-78 | fragment (no `import`) | `make-curl-request`, `http-version 'http/2`: taken | runs | n/a (makes a request only) |
| 2 | :116-120 | fragment | `credentials` `(basic ..)`, `(digest ..)`, `(bearer ..)`: taken | runs | n/a |
| 3 | :171-176 | fragment | `proxy` URLs, `proxy-ca-file`: taken (a proxy URL is parsed and checked at submit) | runs | n/a |
| 4 | :252-260 | fragment, illustrative | every jar name bound; `saved-lines` unbound | the await raises at the network (container); `saved-lines` would raise next | runs: a response, one cookie line read out, load and close return |
| 5 | :327-333 | program | `curl-request-with-options` (from `(curl unsupported)`), `LOW_SPEED_TIME` taken | **as an R6RS program: fails, `quote` unbound** (no `(rnrs)` import); as a script: runs | n/a |
| 6 | :359-376 | program | every name bound; `stream-buffer` taken | **as a program: fails, `define` unbound**; as a script: `curl-head-status` raised `not a head` on `#f`, since the failed transfer published no head and the block does not check `curl-token-head-wait`'s answer | runs: `#t`, `200`, a response |
| 7 | :409-423 | program | every name bound; `method put`, `body stream`, `body-length 11` taken | **as a program: fails, `define` unbound**; as a script: the await raises at the network | runs: `#t #t #t`, a response |
| 8 | :486-498 | program | every name bound; `call-with-response-port`'s `KEY VALUE ... PROC` order matches its signature (`src/http-client.sls:308-311`) | **as a program: fails, `lambda` unbound**; as a script: raises at the network | runs, exit 0 |
| 9 | :526-535 | program, illustrative | every name bound; a producer `body` taken | **as a program: fails, `lambda` unbound**; as a script: `open-file-input-port` raises, no `big.bin` | runs: an `http-response` |

So: all nine use today's names and keys as the API takes them. Blocks 1 to 4 are fragments
(no `import`). Blocks 5 to 9 carry an `import` that names only chez-curl's libraries, so none
runs as an R6RS top-level program, which needs `(rnrs)` for `quote`, `define` and `lambda`;
each runs at the REPL, where Chez's own names are bound. Block 4 needs `saved-lines` and
block 9 a `big.bin`; block 6 raises on any transfer that fails before its head.

## What README.org lacks that slices 2 and 3 added (item 6)

Each is something a caller meets. README.org names none of them: no `multipart`, `mime`,
`header-limit` or header cap anywhere in it (grep).

**Multipart bodies (slice 3, ADR-0039).**

1. **The body form.** `make-curl-request`'s `body` takes `(multipart PART ...)`. Each PART is
   `(NAME SOURCE OPTION ...)`. SOURCE is a string (sent as UTF-8), a bytevector, or
   `(file PATH)`. Each OPTION is `filename STRING` or `type STRING`, at most once. A wrong shape
   is an assertion violation naming the body by its kind. post, put, patch and delete take one;
   get and head refuse one, `body-not-allowed`; `body-length` beside it is
   `body-length-without-stream`. Code: src/curl.sls:84-100; transfer.sls:50-87, :1270-1278,
   :1351. Tests: tests/test-multipart.sps:253 (shapes), :461 (methods), :1098 (each kind on the
   wire), :1154 (every method, three faces).
2. **The defaults.** A file part's filename defaults to its path's last component, and that
   default is held by the filename's rules (transfer.sls:1332; tests/test-multipart.sps:389).
   The types are libcurl's, by the filename's extension: text/plain, text/html, image/gif,
   image/jpeg, image/png, image/svg+xml, application/pdf and application/xml. .json, .csv or no
   extension get none on a data part; a file part gets application/octet-stream; a data part
   with no filename gets no type. No chez-curl code sets a type (tests/test-multipart.sps:1098,
   :1127).
3. **What libcurl writes.** It writes `Content-Type: multipart/form-data` and its boundary. A
   caller's `Content-Type` header beside the body, A to Z folded, is refused as the request is
   made and again at submit, `multipart-content-type`. The transfer keeps its `Expect:` blank, so
   no 100-continue wait past 1 MiB. Code: transfer.sls:83-84, :1469, :4655-4659. Tests:
   tests/test-multipart.sps:437, :450, :1167.
4. **The files.** A relative path is resolved against `current-directory` once, as the request
   is made. Each path must name a regular file by stat (symlinks followed) as the request is
   made, at submit, and on the engine's thread before the transfer is set up, where it is also
   opened and closed. libcurl reads the file as the body goes. A part's data is copied at submit,
   not as the request is made. `curl-request-body` answers a copy. Code: transfer.sls:62-81,
   :1441, :1519 (`check-plan-files!`); engine.sls:2064-2068. Tests: tests/test-multipart.sps:400,
   :413, :1234, :1274, :1296, :830.
5. **New request-error reasons.** `part-bytes` (a control char in a name, filename or type, or
   a `"` in a name or filename, a default filename's included), `part-empty`, `multipart-empty`,
   `multipart-content-type`, `part-file` and `multipart-unsupported`. Each names the part as
   `(part I FIELD)`, never the string. Code: conditions.sls:506-528, the list :542-543, the
   fields :562-591. Tests: tests/test-multipart.sps:290, :294, :357, :389, :400, :437, :1941 (no
   secret printed).
6. **`multipart-unsupported`.** The load probes for mime: `curl_formadd` must answer 0 and
   `curl_mime_init` must make one. A libcurl without it (a 7.85.0 built `--disable-mime` sends
   every multipart body empty) refuses a multipart body at submit, before its other checks,
   naming the probe's answers. No other request is refused. Code: native.sls:1494-1527;
   transfer.sls:4328-4340. Tests: tests/test-library-loading.sps:561-573 (the decoy's switches);
   tests/test-multipart.sps:476 (the loaded libcurl has mime).
7. **New transfer-error reasons.** `part-file` (the engine's check fails, or
   `curl_mime_filedata` answers a code) and `mime-failed`. Each has request size 0, with nothing
   sent. Code: conditions.sls:669-675, :710-711. Tests: tests/test-multipart.sps:1296, :1336,
   :1356.
8. **The request size of a multipart failure, by version.** The head alone on 7.85.0 and 8.5.0;
   the head and the body sent from 8.20.0; unknown on 8.7.1. Code: src/curl.sls:520-522;
   conditions.sls:696-698. Tests: the table at tests/test-multipart.sps:1765 (7.85.0), :1782
   (8.5.0), :1803 (8.7.1), :1820 (8.20.0), :1837 (8.23.0).
9. **`(http-client)`'s `multipart` key.** A call takes `multipart (PART ...)`. A relative path is
   resolved, and each part's data copied, once, as the call starts, so retries and hops send what
   it began with. A session's `Content-Type` header is dropped. It is a whole body: a retry
   resends it, a 307 or 308 keeps it, a 303 drops it, a group takes one. New reason
   `multipart-beside-body` (beside `body` or `form`); `body-not-allowed` now names `multipart`
   with get or head. A file lost mid-call fails at the hop's or retry's submit, `part-file`.
   Code: src/http-client.sls:249-258, :290-291; call.sls:88-95 (the key), :583-597 (the data copied once), :681-686 (the refusals), :716-722 (the session's Content-Type dropped);
   http-client/private/conditions.sls:107, :137, :147. Tests: tests/test-multipart.sps:568,
   :1408, :1438, :1508.
10. **The hatch.** `MIMEPOST` is now the body field's, and `MIME_OPTIONS` is owned and never set.
    Both are refused as `owned-option` (transfer.sls:2123, :2300; tests/test-unsupported.sps:361;
    tests/test-transfer.sps:1383).
11. **`curl-request-with` takes `url`** (slice 3). A redirect's hop is now the last request with
    its URL changed, keeping its hatch options, so a multipart body is kept without its files
    being stat'd again until the submit. Code: src/curl.sls:199-205; transfer.sls:1790;
    exchange.sls:745-771. Tests: tests/test-multipart.sps:657, :672, :779, :809.

**The header cap (slice 2, ADR-0040).**

12. **The cap.** Every transfer refuses the response-header line that takes it past 1,000
    header lines or 102,400 bytes, counted over the whole transfer. Each 1xx head, a trailer
    section, a CONNECT answer, and each auth round's and resend's response are counted. A head's
    status line and empty line count as bytes but not as lines. The cap is fixed: no key sets it.
    Code: transfer.sls:248-261, :3571-3578, :3600-3621. Tests: tests/test-headers.sps:108 (the
    values), :379, :384, :434, :449, :464, :480, :495; tests/test-multipart.sps:1185 (beside a
    mime).
13. **`header-limit`.** A new transfer-error reason, of class `&curl-too-large`, with libcurl's
    code beside it: 23, but 0 on 8.5.0 for an HTTP/2 trailer (whose refusal libcurl loses), and
    56 on 8.7.1 for an HTTP/2 head. A streamed response's port raises it, and its head is never
    published when the cap falls in the head. At the high level, `http-get` raises it, and so
    does `call-with-response-port`, before PROC. Code: conditions.sls:76, :637-643, :680,
    :867-870, :914-921. Tests: tests/test-headers.sps:379, :525, and the table at :262-328
    (7.85.0 :263, 8.5.0 :276, 8.7.1 :289, 8.20.0 :302, 8.23.0 :315); tests/test-conditions.sps:282, :373.
14. **libcurl's own limits come first for some heads, by version, and fail with its code, not
    `header-limit`.** One header line of 102,400 bytes over HTTP/1.1 fails 27 on 7.85.0 and 8.5.0
    and 100 from 8.7.1 (`line-102400-h1`). A 5,000-byte trailer line over HTTP/1.1 fails 56 on
    7.85.0 and 8.5.0 and 100 from 8.7.1 (`trailer-line-5000-h1`). Trailers past nghttp2's limit
    fail 56, or 16 on 8.20.0 (`trailers-past-nghttp2-h2`). An HTTP/2 head past nghttp2's limit
    fails 56 on 7.85.0 and 8.5.0, and is `header-limit` from 8.7.1 (`head-past-nghttp2-h2`).
    8.23.0's 6,000 HTTP/2 trailers fail 56 (`trailers-6000-h2`). So a caller can meet
    `perform-failed` of the too-large, send-receive or protocol class instead of
    `header-limit`. Tests: the same table's rows.
15. **Every transfer sets the header callable** (it was a stream's alone). So the hatch refuses
    `HEADERFUNCTION`, `HEADERDATA` and `SUPPRESS_CONNECT_HEADERS` for every request, and takes
    `HTTP_TRANSFER_DECODING`, `HTTP200ALIASES` and `HTTP09_ALLOWED` (transfer.sls:2110-2113,
    :2283-2292; tests/test-unsupported.sps:478). README :237 is wrong for this reason (above).
16. **The class list in the source comment a reference would draw on is stale.**
    src/curl.sls:543 still says `curl-too-large?` is "63, 100, and the body limit". The header
    cap is missing there, where conditions.sls:76 has it. This is a comment, not a README claim;
    it is listed here because the slice's pages may copy it.

Both slices also bear on claims already in the table: :155-158 (the cap ends a 417 or stale
loop with large heads first), :234-237 and :341-346 (the newly owned options), and :581
(`part-file` partway).

## Counts

Claims: **312 rows**. **held 295** (43 of them unheld; 7 of them held with 8.7.1 unnamed),
**wrong 1**, **partly 16** (3 of them unheld), **unheld 46** in all.

| README.org | Rows | held | of them unheld | wrong | partly | of them unheld |
|---|---|---|---|---|---|---|
| 11-16 | 3 | 3 | 0 | 0 | 0 | 0 |
| 23-166 | 80 | 77 | 15 | 0 | 3 | 2 |
| 167-321 | 94 | 91 | 14 | 1 | 2 | 0 |
| 322-459 | 62 | 57 | 9 | 0 | 5 | 0 |
| 460-584 | 73 | 67 | 5 | 0 | 6 | 1 |
| total | 312 | 295 | 43 | 1 | 16 | 3 |

Blocks: 9. Four are fragments (1 to 4). Five carry an `import` (5 to 9), and none of those runs as
an R6RS program as written, since it does not import `(rnrs)`. Every name is bound but block 4's
`saved-lines`. At the REPL, against the stand-in, every block ran.

Gaps: 16. Eleven are multipart's, five the header cap's.
