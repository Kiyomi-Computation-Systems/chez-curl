# What varies by libcurl: every per-version table the suites hold (M8 slice 4)

Read-only, on 2026-11-08, at `main` `fb62a0b` (branch `feat/m8-docs`, whose tree differs from
`fb62a0b` in `.plans/` alone). No suite was run. Read: `AGENTS.md`; the M8 plan §3.8 and §9;
`tests/known-libcurls.sexp`; every `tests/*.sps`, `*.sls` and `*.sexp` that holds a version, a
version_num, a TLS backend or a PSL key (the inventory, `logs/by-version-inventory.txt`); the
version statements in `src/` comments and in README.org (named, not judged); for the default types,
`research/m8/mime-wire/` (README §Question 6, `results/docker.log`, `guix-8.20.0.log`,
`mac-8.7.1.log`) and `lib/mime.c` of five curl source trees under `build/`
(`logs/by-version-mime-types.txt`, `logs/by-version-mime-wire-defaults.txt`).

**Columns.** 7.85.0 (floor, OpenSSL, from source); 8.5.0 (Ubuntu 24.04, OpenSSL and GnuTLS);
8.7.1 (Apple's, SecureTransport/LibreSSL); 8.20.0 (Guix's, GnuTLS); 8.23.0 (from source, OpenSSL).

- **8.5.0 is one column:** every table keys on the version alone and its notes say both Ubuntu
  builds answered alike (e.g. `test-headers.sps:252-261`, `test-multipart.sps:1755-1762`,
  `known-transfer-verdicts.sexp:43`), except where a row splits it by backend (`O`, `G`).
- **8.20.0 is Guix's build, measured.** 8.20.0-openssl (from source, CI's current lane for one day)
  has no column: a table keyed on version alone claims the 8.20.0 row for it, but it was measured
  only once, by ADR-0020's run of 2026-10-26, which passed every suite then present
  (`decisions/0020-a-ci-lane-on-the-current-libcurl.md:34-37`); every table added since (M5 to
  M8) was never run on it, and the three tables keyed by backend or PSL have **no row** for it and
  fail by name there (table list, marked †).
- **Citations** give one line per column, in column order, `file:A/B/C/D/E`, A for 7.85.0 through
  E for 8.23.0; one number stands for every column it names, and `same lines` repeats the row above's.

**Answer legend.** `N X` is a `&curl-transfer-error`, reason `perform-failed` unless named, code N,
its class X by `curl-code-classes` (`src/curl/private/conditions.sls:816-829`): SR
`&curl-send-receive-error` (52, 55, 56), P `&curl-protocol-error` (1, 8, 16, 92), TL
`&curl-too-large` (100), T `&curl-timeout` (28), C `&curl-connect-error` (7), TLS `&curl-tls-error`
(35, 58, 60, 83), base: no class (0, 23, 26, 27, 4). `hl N` is reason `header-limit`, class TL,
code N. A cell holding several answers is a race: every answer listed, `/` between.

## 1. The tables

`8.7.1` says whether the table has a row for Apple's 8.7.1. "rule" is a pure function of a
version (or backend) the suite writes out on synthetic inputs, not a measured row.

| # | table | suite:lines | measures | cases | keys | 8.7.1 |
|---|---|---|---|---|---|---|
| 1 | `known-libcurls.sexp` | `test-drift.sps` | the loaded libcurl is a recorded one: version, version-num, features, ssl-version, host | 5 fields | 7 libraries | yes |
| 2 | `known-transfer-verdicts.sexp` | `test-transfer.sps:540-559`, `:2696-2839` | GETs of broken raw-face heads | 5 | version | yes |
| 3 | `known-url-verdicts.sexp` | `test-url.sps:182-186`, `:225-470` | `curl_url` normalize and resolve | 10 | version | yes |
| 4 | `known-url-part-verdicts.sexp` | `test-url-parts.sps:331`, `:458-589` | `curl-url-append-query`, `curl-url-part` | 6 | version | yes |
| 5 | `known-url-location-verdicts.sexp` | `test-url-location.sps:364`, `:488-620` | `curl-url-resolve` of Location bytes, `curl-url-with-fragment` | 24 | version | yes |
| 6 | `rows` | `test-headers.sps:226-327` | the cap's own code; libcurl's refusals before a line reaches the callable | 12 | version | yes |
| 7 | `rows` | `test-multipart.sps:1536-1852` | request size; a file changed after the engine's check; resends | 16 | version | yes |
| 8 | `empty-userinfo` | `test-proxy.sps:518-543` | `@`, `:@`, `:p@`, `u:@` in a proxy URL at the check | 4 | version | yes |
| 9 | `tls-in-tls-checks` † | `test-proxy.sps:903-956` | `proxy-tls-in-tls` by version and backend | 5 | version/backend | SecureTransport only |
| 10 | `tls-in-tls-stalls`, `tls-in-tls-stall?` | `test-proxy.sps:456-467` | the library's rule table, written out | 10 inputs | rule | rule says no |
| 11 | `unshared-tunnel-settings`, `stops-multiplexing?` | `test-proxy.sps:398-428` | the < 8.19.0 rules, by version_num | 7 versions | rule | yes |
| 12 | `empty-userinfo-wire` | `test-proxy.sps:1322-1335`, `:1728-1734` | the same userinfo through the proxy, its log | 2 | version | yes |
| 13 | `refused-rows` | `test-proxy.sps:1337-1357`, `:1814-1829` | a refused CONNECT's code, class, status, size | 7 | version | yes |
| 14 | `unshared-rows` | `test-proxy.sps:1373-1431`, `:1837-1844` | two tunnels in turn through one proxy | 2 | version | yes |
| 15 | `tunnel-plans` | `test-proxy.sps:1433-1443`, `:1853-1866` | a submit's plan: tunnel settings, multiplexing stop | 5 | version | yes |
| 16 | `switch-rows` | `test-proxy.sps:1510-1523`, `:1868-1871` | multiplexing stopped by a proxy URL with userinfo | 4 | version | yes |
| 17 | `join-rows` | `test-proxy.sps:1525-1570`, `:1873-1876` | an environment proxy's transfer beside a live authenticated tunnel | 1 | version | yes |
| 18 | `closing-retries` | `test-proxy.sps:1635-1647`, `:2016-2023` | a proxy that closes a CONNECT, under a retry policy | 2 | version | yes |
| 19 | `refused-readout-rows` | `test-cookies.sps:918-932`, `:1362-1376` | read-out lines a load refuses | 11 | version | yes |
| 20 | `expired-rows` | `test-cookies.sps:935-943`, `:1378-1387` | a loaded line already expired | 1 | version | yes |
| 21 | `open-head-rows` | `test-cookies.sps:946-960`, `:1389-1434` | a 4,003-byte cookie beside a long head | 6 | version | yes |
| 22 | `domain-localhost-rows` † | `test-cookies.sps:963-971`, `:1436-1442` | `Domain=localhost`, by PSL | 3 | version/psl | no-psl |
| 23 | `matrix-rows` | `test-cookies.sps:974-987`, `:1444-1462` | default path, `Path=rel`, 400 days, `Max-Age=-1`, delete | 5 | version | yes |
| 24 | `digest-algorithms` | `test-auth.sps:973-994`, `:1329-1340` | each Digest algorithm and qop | 8 | version | yes |
| 25 | `utf8-digest-user` | `test-auth.sps:1004-1018`, `:1343-1354` | a UTF-8 Digest user name | 1 | version | yes |
| 26 | `empty-userinfo` | `test-auth.sps:1033-1063`, `:1356-1378` | a URL's empty userinfo beside credentials | 5 | version | yes |
| 27 | `mib-credentials` | `test-auth.sps:1065-1076`, `:1381-1395` | 1 MiB Basic password and Bearer token | 2 | version | yes |
| 28 | `stall-verdicts` | `test-engine.sps:392-420`, `:1037-1078` | a stalled name lookup, under a preloaded stand-in | 1 or 3 entries x 9 | version | **no** (Linux only) |
| 29 | `reuse-verdicts` | `test-engine.sps:422-438`, `:653-687` | a drip after 8 connections the server closed unannounced | 1 | version | yes |
| 30 | `rows` (h2 3xx) | `test-stream-call.sps:1597-1646` | a final HTTP/2 303 before the body is sent whole | 2 | version | yes |
| 31 | `rows` (raw, held) | `test-stream-call.sps:1644-1709` | an answer written at accept, on the held engine | 2 | version | yes |
| 32 | `spin-rows` | `test-stream.sps:1411-1429` | CPU through a pause, pacing off | 1 | version | yes |
| 33 | `unmultiplexed-versions`, `multiplexing-off?` | `test-stream.sps:528-541`, `:1621-1642`; `test-version.sps:584-589`, `:699-709` | no multiplexing on 8.7.0 and 8.7.1 | rule, 11 inputs | version | yes |
| 34 | `held-rows` | `test-upload.sps:785-841` | the head's body-asked bit, the answer first | 4 | version | yes |
| 35 | `attempt-rows` | `test-upload.sps:1147-1167` | prerequest calls when the seek refuses a rewind | 1 | version | yes |
| 36 | `answer-rows` | `test-upload.sps:1254-1340` | an answer while a streamed body is sent | 6 x 2 framings | version | yes |
| 37 | `location-rows` | `test-redirect.sps:215-250`, `:1142-1176` | bad Locations, two Locations, live | 3 | version | yes |
| 38 | `prior-knowledge-to-h1` | `test-version.sps:431-462`, `:673-689` | prior knowledge to an HTTP/1.1 server | 1 | version | yes |
| 39 | `together-by-prior-knowledge` | `test-version.sps:464-474`, `:691-697` | connections two batched h2c requests use | 1 | version | yes |
| 40 | `minus-one-rows` | `test-variadic.sps:194-206`, `:620-666` | `MAX_TOTAL_CONNECTIONS` -1 on a multi | 1 | version | yes |
| 41 | `blob-rows` † | `test-unsupported.sps:897-927` | three blobs through the hatch | 3 | version/backend | SecureTransport only |
| 42 | `guix-pin-verdicts`, `ca-overridden?`, `overriding-variables`, `pin-refuses?`, `keychain-fallback?` | `test-transfer-tls.sps:993-1129`, children `:1296-1410` | Guix's CA override; the Mac's keychain | rules + 9 + 2 children | version, file, backend | rule; keychain children |
| 43 | `request-size-broken`, `reported-request-size` | `test-request.sps:875-935`; uses: `test-proxy.sps:112-118`, `test-retry.sps:1174-1181`, `test-stream-call.sps:1149-1160`, `test-stream.sps:899` | request size unknown on 8.7.0 and 8.7.1 | rule | version | yes |
| 44 | `gated-rows` | `test-constants.sps:267-280`, `:1893-1899` | constants newer than the floor | 3 | release | n/a |
| 45 | floor and decoys | `test-verify.sps:137-175`; `test-library-loading.sps:388-423`, `:530-575` | below-floor, no-ssl, missing-api, multipart-unsupported | decoys | version_num, build | n/a |

**Keys.** Unless named here, a table's rows are 7.85.0, 8.5.0, 8.7.1, 8.20.0 and 8.23.0. #1: the
seven libraries. #9: `7.85.0/OpenSSL`, `8.5.0/OpenSSL`, `8.5.0/GnuTLS`, `8.20.0/GnuTLS`,
`8.23.0/OpenSSL`, `8.7.1/SecureTransport` (`test-proxy.sps:914-923`). #10: 7.85.0 on any backend, and
8.5.0 with GnuTLS, the stalling ones (`transfer.sls:2644-2646`). #11: version_nums of 7.85.0, 8.5.0,
8.7.1, 8.18.0, 8.19.0, 8.20.0, 8.23.0 (`test-proxy.sps:405`). #22: `7.85.0/no-psl`, `8.5.0/psl`,
`8.7.1/no-psl`, `8.20.0/psl`, `8.23.0/no-psl`. #28: 7.85.0, 8.5.0, 8.20.0, 8.23.0. #33, #43: 8.7.0
and 8.7.1. #41: #9's pairs. #42: Guix's 8.20.0 alone, a Guix libcurl with no row taken to override.
#44: the releases that added `CURLMOPT_QUICK_EXIT` (8.20.0), `CURLE_TOO_LARGE` (8.6.0),
`CURLE_ECH_REQUIRED` (8.8.0).

† no row for 8.20.0-openssl (`8.20.0/OpenSSL`, `("8.20.0" . "OpenSSL")`, `8.20.0/no-psl`; its
features word has no PSL bit: `known-libcurls.sexp:59`, bit 20 clear). Nor for 8.7.1 with LibreSSL
in use, which a Mac program gets unless `CURL_SSL_BACKEND` is set: `make test` sets
`secure-transport` (`AGENTS.md:383-386`).

## 2. Caller-facing cells, by the docs' topics

Nothing per-version was found for sessions, verbs, params (the query's refusal code is under URLs),
groups, or tokens beyond what streams hold. 104 caller-facing rows: 86 differ by libcurl; 18 hold
cells a per-version table keeps alike on every lane ("all alike"), or turn on a build, not a
version.

### 2.1 Forms and multipart (high and low level)

The file cells change the file once the origin holds the request's head, after the engine's check
(a test-only hold times it; a caller meets it by changing a file mid-transfer).

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| request size of a failed multipart post (`curl-transfer-error-request-size`) | the head alone | the head alone | `#f` | head and body | head and body | `test-multipart.sps:1765/1782/1803/1820/1837` |
| file grown 2,000 bytes, HTTP/1.1 | surplus sent past `Content-Length`; the server's answer, here 400 | as 7.85.0 | 200, body unterminated (closing delimiter never sent) | as 8.7.1 | as 8.7.1 | `:1766/1783/1804/1821/1838` |
| file grown, HTTP/2 | 92 P | 92 P (server on Node 20, 24) / 56 SR (Node 22): the server's answer | 200, unterminated | as 8.7.1 | as 8.7.1 | `:1771/1792/1809/1826/1843` |
| file shrunk to 1,000, HTTP/1.1, `timeout-ms` 3,000 | stalls to the bound: 28 T | as 7.85.0 | 26 base, at once | as 8.7.1 | as 8.7.1 | `:1767/1784/1805/1822/1839` |
| file shrunk, HTTP/1.1, no `timeout-ms` | stalls for ever | as 7.85.0 | 26 base | as 8.7.1 | as 8.7.1 | `:1768/1785/1806/1823/1840` |
| file shrunk, HTTP/2 | 92 P, at once | as 7.85.0 | 26 base | as 8.7.1 | as 8.7.1 | `:1772/1793/1810/1827/1844` |
| file removed, HTTP/1.1 and HTTP/2 | 26 base (all alike) | | | | | `:1769,1773/1786,1794/1807,1811/1824,1828/1841,1845` |
| path swapped for a FIFO, HTTP/1.1 and HTTP/2 | 200 whole, held until the writer comes (all alike) | | | | | `:1770,1774/1787,1795/1808,1812/1825,1829/1842,1846` |
| resend on a dead kept connection, data and file part | 200 whole, 2 requests (all alike) | | | | | `:1775-1776/1796-1797/1813-1814/1830-1831/1847-1848` |
| resend of an HTTP/2 stream refused at HEADERS | 200 whole, 2 (all alike) | | | | | `:1777/1798/1815/1832/1849` |
| a 4 MiB file part, the connection reset as its head arrives | 200 whole, 2 / 55 SR, 1 (a race, every lane; 8.7.1 gave 55 in both Mac runs, plan §9) | | | | | `:1780/1801/1818/1835/1852` |

Default types: §4.

### 2.2 Redirects and retries (high level)

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| a 302 to `javascript:alert(1)` | followed as a relative path, `/raw/javascript:alert(1)` | `bad-location`, `&curl-url-error` 5 unsupported-scheme | as 8.5.0 | as 8.5.0 | as 8.5.0 | `test-redirect.sps:238/236,240/236,241/237,242/237,243` |
| a 302 to `http://[::1/x` | `bad-location`, url-error 4 bad-port-number | `bad-location`, url-error 22 bad-ipv6 | as 8.5.0 | as 8.5.0 | as 8.5.0 | same lines |
| two `Location` headers | the first followed | as 7.85.0 | as 7.85.0 | 8 P, with `&http-exchange` | as 8.20.0 | same lines; test `:1153-1165` |
| a post to a refused port, retry policy | 3 transfers | 3 | **1** (size unknown, read as sent) | 3 | 3 | `test-retry.sps:1174-1181,1447-1462` |
| a producer's post to a refused port, retried | 3 | 3 | 1 | 3 | 3 | `test-stream-call.sps:1149-1160` |
| a retry that runs out of time having sent nothing | the first 28, 2 transfers, no `&http-timeout` | as 7.85.0 | `&http-timeout` 3500 too | as 7.85.0 | as 7.85.0 | `test-retry.sps:1612-1629` |
| a proxy closes a CONNECT, post outside the policy's methods | tried once (size = the CONNECT's bytes) | 3 times | once (size unknown) | 3 | 3 | `test-proxy.sps:1643/1644/1647/1644/1644` |
| the same, a get in the methods | 3 (all alike) | | | | | same lines |

### 2.3 Auth (high level; the low level's `credentials`)

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| Digest MD5, MD5-sess, SHA-256, SHA-256-sess (qop auth, none) | 200 (all alike) | | | | | `test-auth.sps:990/991/992/993/994` |
| Digest SHA-512-256, qop auth and none | 401 (sends SHA-256's response) | 401 | 200 | 200 | 200 | same lines |
| Digest user `üser` | 200, sent raw | 200 | 200 | 200 | 401: percent-encoded, raw bytes hashed | `test-auth.sps:1017/1017/1017/1017/1018` |
| URL `http://@h/` or `http://:@h/` beside credentials | taken, the field's credentials sent, 200 | refused at submit, `credentials-beside-userinfo` | as 8.5.0 | as 8.5.0 | as 8.5.0 | `test-auth.sps:1054-1055/1056-1057/1058-1059/1060-1061/1062-1063` |
| URL `:p@`, `u@`, `u:@` beside credentials | refused, `credentials-beside-userinfo` (all alike) | | | | | same lines |
| 1 MiB Basic password, 1 MiB Bearer token | 27 base, nothing sent | 27 base | 100 TL | 100 TL | 100 TL | `test-auth.sps:1075/1075/1075/1075/1076` |

### 2.4 Proxies (high level `proxy`; the low level's `proxy`)

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| proxy URL `http://@p` or `http://:@p` | taken; no `Proxy-Authorization`, 200 | refused at submit, `credentials-empty`, value `(proxy user)`; nothing sent | as 8.5.0 | as 8.5.0 | as 8.5.0 | `test-proxy.sps:531-532/533/536/534/535`; wire `:1331-1333/1334/1335/1334/1334` |
| `https://` URL through an `https://` proxy URL, http-version #f, http/1.1, http/2 | refused, ok, refused (`proxy-tls-in-tls`) | O: ok x3; G: refused x3 | SecureTransport: ok x3 (200) | GnuTLS: ok x3 | ok x3 | `test-proxy.sps:914/915-916/923/917/918` |
| `http://` URL through an `https://` proxy; `https://` through `http://` | ok (all alike) | | | | | same lines |
| the refusal's irritants | `proxy`, the version, the backend in use, never the URL (all) | | | | | `test-proxy.sps:950-956` |
| CONNECT refused 403, 407, 502, 503, wrong password, none | 56 SR, size = the CONNECT's bytes | 56 SR, size 0 | 56 SR, size `#f` | 7 C, size 0 | 7 C, size 0 | `test-proxy.sps:1353/1354/1357/1355/1356` |
| ... its status, `curl-transfer-error-connect-code` | the proxy's status (all alike) | | | | | same lines |
| a proxy that closes a CONNECT | 56 SR, no status; size as the row above (all) | | | | | same lines |
| two `https://` requests in turn through one proxy URL | each its own CONNECT; with userinfo the first closes as it ends | as 7.85.0 | as 7.85.0 | the second rides the first's tunnel | as 8.20.0 | `test-proxy.sps:1430/1430/1431/1430/1430` |
| a transfer through a proxy URL with userinfo, two HTTP/2 streams live | the engine stops multiplexing for good; a third request opens its own connection | as 7.85.0 | never multiplexes: each stream its own connection | nothing switches; the third rides theirs | as 8.20.0 | `test-proxy.sps:1517/1518/1523/1519/1520` |
| `https_proxy` set, an environment transfer beside a live authenticated tunnel | its own CONNECT, 407: 56 SR; engine switched | as 7.85.0 | 56 SR; multiplexing off throughout | its own CONNECT, 407: 7 C; no switch | as 8.20.0 | `test-proxy.sps:1564/1565/1570/1566/1567` |

### 2.5 Cookies and jars (high level `cookies`; low level jars)

"Faulted" means the read-out line is one `curl-cookie-jar-load!` refuses, `cookie-line`, by the
rule named (`transfer.sls:2734-2780`).

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| server's `Path=`, `Path=TRUE`, `Path=FALSE`, `Path=rel` | listed as given, faulted `path`; sent | as 7.85.0 | as 7.85.0 | listed with `/`, loads; sent | as 8.20.0 | `test-cookies.sps:931/932/930/928/929` |
| a tab in a server cookie's name or value | listed as eight fields, faulted `fields`; sent with the tab | dropped | dropped | dropped | dropped | same lines |
| `__secure-a`, `__SECURE-b`, `__host-c` with a path, `__HOST-d` with a domain, none Secure | listed, faulted `prefix`; sent | dropped at the Set-Cookie | dropped | as 7.85.0 | as 7.85.0 | same lines |
| a tab in a server's `Path` | eight fields, faulted `fields`; not sent | dropped | dropped | dropped | dropped | same lines |
| a loaded line already expired, then a line added | listed until the next is added | as 7.85.0 | as 7.85.0 | dropped at once | as 8.20.0 | `test-cookies.sps:942/943/941/939/940` |
| a server's 4,003-byte cookie, then a request line past 4,200 bytes, or a 4,300-byte User-Agent | `Cookie:` with no line end: the head never ends, 28 T | 200 | 200 | 200 | 200 | `test-cookies.sps:959/960/958/956/957` |
| `Domain=localhost` set at `a.localhost` | kept (`.localhost`), not sent to `a.localhost` (no PSL) | PSL: dropped | no PSL: as 7.85.0 | PSL: dropped | no PSL: as 7.85.0 | `test-cookies.sps:970/971/969/967/968` |
| `Domain=localhost` set at `localhost` | `.localhost`, domain; sent | host-only `localhost`; sent | as 7.85.0 | as 7.85.0 | as 7.85.0 | same lines |
| `__Host-dom; Secure; Path=/; Domain=localhost` at `localhost` | dropped | kept host-only, Secure; sent | dropped | dropped | dropped | same lines |
| default path, set at `/cookies/a/b/page` | `/cookies/a/b/` | as 7.85.0 | as 7.85.0 | `/cookies/a/b` | as 8.20.0 | `test-cookies.sps:986/987/985/983/984` |
| `Path=rel`, `Path=` there | kept as given, faulted `path`; both sent | as 7.85.0 | as 7.85.0 | `/` and the default; `pr` alone sent | as 8.20.0 | same lines |
| `Max-Age` of 1,000 days | kept past 400 days | as 7.85.0 | as 7.85.0 | capped at 400 days | as 8.20.0 | same lines |
| `Max-Age=-1` | kept as a session cookie, sent | listed with expiry 1, not sent | as 8.5.0 | dropped | dropped | same lines |
| a cookie deleted by `Max-Age=0` | listed, expiry 1, until the next request | as 7.85.0 | as 7.85.0 | gone at once | as 8.20.0 | same lines |

### 2.6 The HTTP version (high level and `http-version`)

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| `http/2-prior-knowledge` to an HTTP/1.1 server, natively | 52 SR | 56 SR | 16 P / 56 SR | 16 P | 16 P | `test-version.sps:457/459/460/461/462`; `:431-455` |
| two h2c requests by prior knowledge, one batch | 1 connection | 2 | 2 | 2 | 2 | `test-version.sps:474` |
| a request submitted once a live first's head is in, h2 and h2c | reuses its connection | reuses | opens its own | reuses | reuses | `test-version.sps:589,703-709` |
| two transfers at once to one h2 origin | share a connection | share | each its own | share | share | `test-stream.sps:530-536,1638-1641` |

### 2.7 Streams, high level (`call-with-response-port`, a producer)

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| a final HTTP/2 303 once 65,536 bytes of a 4 MiB body came, `redirects #f`, producer or whole body | the 303 and its body | as 7.85.0 | as 7.85.0 | never ends: 28, `&http-timeout`, at the bound | as 8.20.0 | `test-stream-call.sps:1605/1606/1607/1608/1609` |

### 2.8 Engines (low level)

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| a request right after 8 pooled connections the server closed without saying so | 200 | 200 | 200 | 200 | 55 SR, "Connection died, tried 5 times before giving up" | `test-engine.sps:434/435/436/437/438` |
| a name lookup that stalls, the engine as made: cancel, a transfer beside, a 500 ms timeout, stop | each waits for the lookup (the stop after a cancel or timeout is prompt) | prompt | not measured (no `LD_PRELOAD`) | prompt | prompt | `test-engine.sps:411/412/1040-1042/415/418` |

### 2.9 Requests: the request size (`curl-transfer-error-request-size`)

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| any transfer that ran | its bytes, 0 if none | as 7.85.0 | `#f`, unknown (8.7.0 too) | as 7.85.0 | as 7.85.0 | `test-request.sps:880,933-935`; `test-proxy.sps:118` |
| multipart, refused CONNECT | §2.1, §2.4 | | | | | |

### 2.10 Streams, low level: an answer while a streamed body is sent

`own`: ends within 1 s with nothing put; `waits`: ends only after the producer's next put. Sized
and chunked alike (`test-upload.sps:1291-1340`).

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| HTTP/1.1 413 with close | waits, 413 | own, 413 | own, 413 | own, 413 | own, 413 | `test-upload.sps:1281/1283/1285/1287/1289` |
| HTTP/1.1 413 kept alive | waits, 413 | waits natively (own under Valgrind), 413 | waits, 413 | own, 413 | own, 413 | same lines |
| HTTP/1.1 200 with close | waits, 200 | own, 200 | own, 200 | own, 200 | own, 200 | same lines |
| HTTP/1.1 200 kept alive | waits, 200 (all alike) | | | | | `:1282/1284/1286/1288/1290` |
| HTTP/2 413 | waits, 413 | waits natively (own under Valgrind), 413 | waits, 413 | own, 413 | own, 413 | same lines |
| HTTP/2 200 | waits, then 28 T | own, 200 | waits, 200 / 55 SR | waits, 200 / 55 SR | waits, 200 | same lines |

### 2.11 Errors: codes and classes

The cap's refusals are read by reason and class; the code is libcurl's answer (`conditions.sls:636-642`).

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| the cap's own refusal, HTTP/1.1 (1,001 lines) | hl 23 | hl 23 | hl 23 | hl 23 | hl 23 | `test-headers.sps:264/277/290/303/316` |
| the cap's own refusal, an HTTP/2 head | hl 23 | hl 23 | hl 56 | hl 23 | hl 23 | `:265/278/291/304/317` |
| the cap's own refusal, HTTP/2 trailers | hl 23 | hl 0 (libcurl loses it) | hl 23 | hl 23 | hl 23 | `:266/279/292/305/318` |
| one header line of 102,400 bytes, HTTP/1.1 | 27 base | 27 base | 100 TL | 100 TL | 100 TL | `:267/280/293/306/319`; `known-transfer-verdicts.sexp:35/46/57/68/78` |
| the same, 1 MiB (raw face) | 27 base | 27 base | 100 TL | 100 TL | 100 TL | `known-transfer-verdicts.sexp:36/47/58/69/79` |
| that line over HTTP/2, Huffman-coded | 27 base | 27 base | 56 SR | 16 P | 56 SR | `test-headers.sps:268/281/294/307/320` |
| that line over HTTP/2, not Huffman-codable | 52 SR | 56 SR | 16 P | 16 P | 16 P | `:269/282/295/308/321` |
| an HTTP/2 head of 131,072 bytes | 56 SR (7.85.0's 128 KiB) | hl 23 | hl 56 | hl 23 | hl 23 | `:270/283/296/309/322` |
| an HTTP/2 head of 307,199 bytes (nghttp2's limit) | 56 SR | 56 SR | hl 56 | hl 23 | hl 23 | `:271/284/297/310/323` |
| HTTP/2 trailers past nghttp2's limit | 56 SR | 56 SR | 56 SR | 16 P | 56 SR | `:272/285/298/311/324` |
| a trailer line of 5,000 bytes, HTTP/1.1 | 56 SR | 56 SR | 100 TL | 100 TL | 100 TL | `:273/286/299/312/325` |
| a trailer line of 5,000 bytes, HTTP/2 | 200; trailers listed among the headers (3) | 200 (2) | 200 (2) | 200 (2) | 200 (2) | `:274/287/300/313/326` |
| 6,000 HTTP/2 trailers | hl 23 | hl 0 | hl 23 | hl 23 | 56 SR (its 5,000) | `:275/288/301/314/327` |
| status line `HTTP/1.1 2000 OK` | 1 P | 1 P | 1 P | 200, body kept | 200 | `known-transfer-verdicts.sexp:37/48/59/70/80` |
| two different `Content-Length`s | 200, both headers | 200 | 200 | 8 P | 8 P | `:38-39/49-50/60-61/71/81` |
| a NUL in a header: the error buffer | `Nul byte in header` | as 7.85.0 | as 7.85.0 | as 7.85.0 | `NUL byte in header` | `:40/51/62/72/82` |
| 1 MiB credentials, refused CONNECT, prior knowledge to HTTP/1.1, two Locations | §2.3, §2.4, §2.6, §2.2 | | | | | |

### 2.12 TLS and the environment, finding libcurl

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| a `ca-file` (or `proxy-ca-file`), verify on, `SSL_CERT_FILE` or `SSL_CERT_DIR` set as libcurl loaded | ignored: the CA file is the anchor | ignored | ignored | Guix's (by file or patch literal, any version): refused at check and submit, `environment-override`, naming each variable | ignored | `test-transfer-tls.sps:1001,1084-1129,1296-1377`; `test-proxy.sps:2045-2056` |
| a `ca-file`, verify on, on macOS | (Linux) | (Linux) | LibreSSL in use (`CURL_SSL_BACKEND` unset or `openssl`): refused, `keychain-fallback`, irritant the backend; `secure-transport`: runs | (Linux) | (Linux) | `test-transfer-tls.sps:1044-1055,1383-1410` |
| a libcurl older than 7.85.0; one without SSL | refused at load, `&curl-library-unavailable` `below-floor`; `no-ssl` (any version) | | | | | `test-verify.sps:139-172`; decoys `test-library-loading.sps:390-403` |
| a libcurl built without mime | multipart refused at submit, `multipart-unsupported` (the load's probe); every other request kept | | | | | decoys `test-library-loading.sps:556-575`; `research/m8/slice3/README.md:137-139` |
| a libcurl without the header API | refused at load, `missing-api` `curl_easy_header` | | | | | decoy `test-library-loading.sps:420-423` |
| TLS inside TLS, by backend | §2.4 | | | | | |

### 2.13 URLs (`curl-url-part`, `curl-url-resolve`, `curl-url-with-fragment`, `curl-url-append-query`)

A refusal is `&curl-url-error`, code and reason the CURLUcode's (`constants.sls:179-208`): 3
malformed-input, 4 bad-port-number, 5 unsupported-scheme, 20 bad-fragment, 21 bad-hostname, 22
bad-ipv6, 25 bad-path, 26 bad-query, 28 bad-slashes. The high level's redirects resolve a lone `#`
themselves, alike everywhere (`exchange.sls:648-660`); these cells are a direct call's.

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| resolve `#frag` against `http://example.com/a/b/c?q=1` | `http://example.com/a/b/#frag`: last segment and query dropped | as 7.85.0 | as 7.85.0 | `.../a/b/c?q=1#frag` | as 8.20.0 | `known-url-verdicts.sexp:29/44/89/59/74` |
| resolve `#s` against `http://a/b/c/d;p?q` | `http://a/b/c/#s` | as 7.85.0 | as 7.85.0 | `http://a/b/c/d;p?q#s` | as 8.20.0 | `:32/47/93/62/78` |
| resolve bytes `#only` (base with or without a fragment) | `.../a/b/c/#only` | as 7.85.0 | as 7.85.0 | `.../rel-frag?q=1#only` | as 8.20.0 | `known-url-location-verdicts.sexp:30,34/59,63/146,150/88,92/117,121` |
| resolve `""` against `http://a/b/c/d;p?q` | `http://a/b/c/` | refused 3 | refused 3 | the base, `http://a/b/c/d;p?q` | as 8.20.0 | `known-url-verdicts.sexp:33/48/94/63/79`; bytes `known-url-location-verdicts.sexp:32/61/148/90/119` |
| resolve `g:h` | `http://a/b/c/g:h` | refused 5 | refused 5 | refused 5 | refused 5 | `known-url-verdicts.sexp:34/49/92/64/77` |
| resolve `http:g` | `http://a/b/c/http:g` | refused 28 | refused 28 | refused 28 | refused 28 | `:35/50/95/65/80` |
| resolve bytes `javascript:alert(1)` | `.../a/b/c/javascript:alert(1)` | refused 5 | refused 5 | refused 5 | refused 5 | `known-url-location-verdicts.sexp:31/60/147/89/118` |
| resolve bytes `http://[::1/x` | refused 4 | refused 22 | refused 22 | refused 22 | refused 22 | `:33/62/149/91/120` |
| resolve `é`, `?q=λ`, `?q=😀`; a Latin-1 path as a string | lower-case hex, `%c3%a9` | lower | lower | upper, `%C3%A9` | upper | `known-url-verdicts.sexp:36-38/51-53/96-98/66-68/81-83`; `known-url-location-verdicts.sexp:35/64/151/93/122` |
| parse `http://example.com/a b` | refused 25 | refused 3 | refused 3 | refused 3 | refused 25 | `known-url-verdicts.sexp:30/45/90/60/75` |
| parse `http://exa mple.com/` | refused 21 | refused 3 | refused 3 | refused 3 | refused 21 | `:31/46/91/61/76` |
| `curl-url-with-fragment` a string with a space, tab, CR, 0x01 or 0x7F | refused 20 | refused 3 | refused 3 | refused 3 | refused 20 | `known-url-location-verdicts.sexp:36-53/65-82/152-169/94-111/123-140` |
| `curl-url-append-query` of `s=a b` | refused 26 | refused 3 | refused 3 | refused 3 | refused 26 | `known-url-part-verdicts.sexp:31-32/42-43/75-76/53-54/64-65` |
| `curl-url-part` user of `http://:pw@h/` | `#f` | `""` | `""` | `""` | `""` | `:33/44/77/55/66` |
| `curl-url-part` of `http://u:@h/`: url, password | `http://u@h.example/`, `#f` | `http://u:@h.example/`, `""` | as 8.5.0 | as 8.5.0 | as 8.5.0 | `:34/45/78/56/67` |
| `curl-url-part` query of `http://h/p?` and `p?#` | `""` | `""` | `""` | `#f` | `#f` | `:35-36/46-47/79-80/57-58/68-69` |

### 2.14 The hatch (`curl-request-with-options`)

| behaviour | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 | cite |
|---|---|---|---|---|---|---|
| `ISSUERCERT_BLOB` at the run CA | 200 | O, G: 200 | SecureTransport: 200 | GnuTLS: `setopt-failed` 4 base, option `ISSUERCERT_BLOB` | 200 | `test-unsupported.sps:909/910-911/915/912-913/914` |
| `ISSUERCERT_BLOB` at another CA | 83 TLS | O: 83 TLS; G: 200 (ignored) | 200 (ignored) | `setopt-failed` 4 | 83 TLS | same lines |
| `SSLCERT_BLOB` at bytes that are no certificate | 58 TLS | O: 58 TLS; G: 200 (ignored) | 58 TLS | 200 (ignored) | 58 TLS | same lines |
| an owned option the libcurl does not know (`HAPROXY_CLIENT_IP`, `QUICK_EXIT` on 7.85.0) | `unknown-option`, where others answer `owned-option`; by the loaded libcurl's table, no version row | | | | | `test-unsupported.sps:350-352,450-451`; `transfer.sls:2259-2261,2350-2353` |

## 3. Cells only the suites meet

| cell | why no caller meets it as such | cite |
|---|---|---|
| table 1, the drift guard | `make test` fails on an unrecorded libcurl; a program is never refused for one | `known-libcurls.sexp:1-12` |
| tables 10, 11, 42's rules, 43's `reported-request-size` on 8.6.0 and 8.8.0 | pure functions on synthetic versions, paths and backends; their effects are the live rows above | `test-proxy.sps:398-467`; `test-transfer-tls.sps:1044-1121`; `test-request.sps:931-935` |
| table 15, `tunnel-plans` | a private plan (`prepare-transfer`); its effect is tables 14 and 16 | `test-proxy.sps:1853-1866` |
| table 28's `transfer` and `multi` entries | engines made without a `QUICK_EXIT` setting, a private seam; the live entry is §2.8. The stall itself comes from a preloaded stand-in getaddrinfo | `test-engine.sps:412-420`; ADR-0019 |
| table 31, raw held | the held engine (prerequest held 200 ms), a seam; at a caller's engine the order races (`test-upload.sps:842-850`) | `test-stream-call.sps:1653-1657` |
| table 32, `spin-rows` | the paced poll turned off by a seam; with it on, every lane is under 500 ms (`test-stream.sps:1405-1410`) | `test-stream.sps:1416-1417` |
| table 34, `held-rows` | the prerequest hold, a seam | `test-upload.sps:826-827` |
| table 35, `attempt-rows` | an engine that leaves the owned `FRESH_CONNECT` off, a seam; no request reaches it | `test-upload.sps:1151`; `engine.sls:671-676` |
| table 40, `minus-one-rows` | `curl-multi-setopt-long` is private; no export sets a multi option | `test-variadic.sps:201-206`; `(curl unsupported)` exports `curl-request-with-options` alone |
| table 7, `resend-307-*` | libcurl's own follow is a private seam (`curl-request-following`); the high level follows with a fresh transfer | `test-multipart.sps:1630,1660,1778-1779` |
| table 7, `after-grown-h2` 8.5.0 `92 / 56` and `after-grown-h1`'s 400 | the server's answer to the overrun: the test origin's, by Node's version | `test-multipart.sps:1788-1792`; `AGENTS.md:638-640` |
| table 36, 8.5.0's `own` for a kept 413 and an HTTP/2 413 | seen only under the memory gate's Valgrind and CI's memory job | `test-upload.sps:1258-1266` |
| table 38's 55, and 7.85.0's 16 | under Valgrind alone; natively each row's first answer | `test-version.sps:438-443` |
| `test-stream.sps:885-903`, pause-failed | a planted `curl_easy_pause` answer, 43 | `test-stream.sps:885-886` |
| tables 44, 45 | build-time headers; decoy libraries stand in for builds no lane runs | `test-constants.sps:267-280`; `test-library-loading.sps:388-575` |

## 4. The default types

libcurl picks a part's `Content-Type` when the part names none (`Curl_mime_contenttype`, called by
`Curl_mime_prepare_headers`). The table, the rule and the default are the same in all five trees,
the ten rows hashing alike (`logs/by-version-mime-types.txt`, last five lines):

| extension | type | 7.85.0 `lib/mime.c` | 8.5.0 | 8.7.1 (upstream) | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|---|
| `.gif` | `image/gif` | 1725 | 1717 | 1715 | 1652 | 1694 |
| `.jpg` | `image/jpeg` | 1726 | 1718 | 1716 | 1653 | 1695 |
| `.jpeg` | `image/jpeg` | 1727 | 1719 | 1717 | 1654 | 1696 |
| `.png` | `image/png` | 1728 | 1720 | 1718 | 1655 | 1697 |
| `.svg` | `image/svg+xml` | 1729 | 1721 | 1719 | 1656 | 1698 |
| `.txt` | `text/plain` | 1730 | 1722 | 1720 | 1657 | 1699 |
| `.htm` | `text/html` | 1731 | 1723 | 1721 | 1658 | 1700 |
| `.html` | `text/html` | 1732 | 1724 | 1722 | 1659 | 1701 |
| `.pdf` | `application/pdf` | 1733 | 1725 | 1723 | 1660 | 1702 |
| `.xml` | `application/xml` | 1734 | 1726 | 1724 | 1661 | 1703 |

Trees: `build/verify/current/curl-7.85.0`, `build/m7s4r/src/curl-8.5.0`,
`build/m4s3/src/curl-8.7.1` (upstream's, not Apple's), `build/verify/current/curl-8.20.0`,
`build/verify/current/curl-8.23.0`.

- **The match:** the name's end against each row, ASCII case ignored (`strcasecompare`, from 8.20.0
  `curl_strequal`): 7.85.0 `mime.c:1745`, 8.5.0 `:1737`, 8.7.1 `:1735`, 8.20.0 `:1672`, 8.23.0
  `:1714`. So it is the last extension that counts, `.TXT` matches, `a.tar.gz` matches none, and a
  name that is `.txt` alone matches. Measured: `b.TXT` gives `text/plain` (`test-multipart.sps:1106,1118`).
- **A file part:** its filename's extension, else its path's, else `application/octet-stream`
  (`FILE_CONTENTTYPE_DEFAULT`, `mime.h:39` on 7.85.0, 8.5.0, 8.7.1, `:38` on 8.20.0, 8.23.0):
  7.85.0 `mime.c:1801-1805`, 8.5.0 `:1794-1798`, 8.7.1 `:1792-1796`, 8.20.0 `:1729-1733`, 8.23.0
  `:1833-1837`. Every file part has a filename: libcurl sets its path's base name as `curl_mime_filedata` runs (7.85.0 `mime.c:1437-1446`), and chez-curl sets one only when given (`native.sls:1415-1419`; it checks the default by the filename rules, `transfer.sls:1380-1384`),
  so the octet-stream default always applies; a `filename` of an unknown extension takes the path's
  type (`renamed.bin` of a `.txt` file: `text/plain`, `test-multipart.sps:1108,1120-1121`).
- **A data part:** its filename's extension alone; no filename, or an unknown extension, gets **no**
  `Content-Type`: 7.85.0 `mime.c:1808`, 8.5.0 `:1801`, 8.7.1 `:1799`, 8.20.0 `:1736`, 8.23.0 `:1840`.
- **A `text/plain` found so is dropped from a part with no filename** (7.85.0 `:1818-1821`, 8.5.0
  `:1811-1814`, 8.7.1 `:1809-1812`, 8.20.0 `:1746-1749`, 8.23.0 `:1850-1853`); no chez-curl part
  reaches it (a data part with no filename finds no type; a file part always has one).
- **A `type` given always wins** (`customct`, 7.85.0 `:1788-1793`).
- **Measured alike on every lane:** mime-wire question 6, "every cell holds on all five lanes, in
  both runs" (`research/m8/mime-wire/README.md:340-377`); per lane, `t.bin` and `t` give
  `application/octet-stream`, `d.txt` `text/plain`, `d.bin` none: `results/docker.log:12055,12078,12101,12124`
  (7.85.0), `:25347,25369,25391,25413` (8.5.0-O), `:37235,37257,37279,37301` (8.5.0-G),
  `:48912,48934,48956,48978` (8.23.0), `guix-8.20.0.log:10266,10288,10310,10332`. **Apple's 8.7.1**
  answers the same in the Mac's log: `t.txt` `text/plain` `mac-8.7.1.log:10396`, `t.html`
  `text/html` `:10418`, `t.bin` and `t` octet-stream `:10440,10462`, `d.txt` `:10484`, `d.html`
  `:10527`, `d.bin` and `d` none `:10506,10549`, filedata then filename `other.bin` keeps the path's
  `text/plain` `:10700`; again in run 2, `:22292-22445`. The whole ten-row table, `.json`, `.csv` and
  no extension, data and file, is a shared test (`test-multipart.sps:1127-1149`) that passed on the
  Mac: `research/m8/slice3/mac/mac-8.7.1-multipart-3.log:9`, 73 passes, no failure.
- **They do not differ by version.**

## 5. Per-version behaviour no table pins

C: a caller can meet it. M: chez-curl masks it, every libcurl answering alike to the caller. S:
the suites alone (Valgrind, Node).

| | behaviour | stated at |
|---|---|---|
| C | An environment proxy variable whose userinfo decodes to a control byte: the transfer goes direct on 7.85.0 and 8.5.0, and fails 3 from 8.20.0; no suite sets one (the proxy URL case is refused alike, `test-proxy.sps:707-720`) | README.org:35-39; `AGENTS.md:151-153` |
| C | 8.5.0 hands a response header's empty value over as a lone CR, in `curl-response-headers` too; held only as the redirect rule's data | `exchange.sls:91,606-607`; `test-url-location.sps:13`; rule `test-redirect.sps:431` |
| C | Timings on a reused connection: 8.20.0 reports name-lookup, connect and tls-handshake 0; 7.85.0 a connect of 10 to 37 µs; "No test reads a timing" | `curl.sls:281-285`; `transfer.sls:1920-1924`; `test-version.sps:44` |
| C | A request URL past 131,041 chars on 8.5.0 stalled to its timeout; 7.85.0, 8.20.0 and 8.23.0 sent about 1,048,500 | `drive.sls:340-346` |
| C | Many headers cost n² CPU before 8.23.0 (`curl_easy_nextheader`); 5,000 headers took 107 to 146 ms on 8.7.1; the cap's 1,000 lines bounds it | `AGENTS.md:538-542`; plan §9 |
| C | 8.5.0 over HTTP/2 can read nothing from a transfer paused for sending until the body resumes, 9 of 4,760 runs | `AGENTS.md:579-583`; README.org:454-458 |
| C | 7.85.0: an early HTTP/2 200 while a *whole* body is owed never ends (the streamed case is table 36's 28) | README.org:560-561 |
| C | A low-level transfer's HTTP/2 3xx before its body is sent whole never ends on 8.20.0 and 8.23.0; table 30 pins the high level only | `AGENTS.md:529-533`; `http-client.sls:283-290` |
| C | A stalled lookup holds a group's join, or a cancel's end, on 7.85.0 to 7.86.x up to glibc's resolver timeout; table 28 pins the engine, no group row | `http-client.sls:431-434`; `drive.sls:203-204` |
| C | `curl-url-part` host of `[FE80::1%25ETH0]` keeps its case on 7.85.0 and 8.5.0 alone; an empty zone, `%25` inside one and `%30` vary on 8.23.0: left out of the tables | `test-url-parts.sps:730-736` |
| C | `curl-url-resolve` of a *string* holding 0x01 or 0x7F: 7.85.0 and 8.5.0 refuse it (bytes are encoded first, alike) | `test-url-location.sps:649-653`; `test-redirect.sps:1124-1128` |
| C | `curl-url-resolve` of a lone `#` with `%XX`: 8.20.0 and 8.23.0 give lower-case hex | `AGENTS.md:464-466` |
| C | A libcurl built without mime: 7.85.0 answers `curl_formadd` 7 and makes a mime that sends an empty body; 8.23.0 answers 7 and NULL; held by decoys alone | `AGENTS.md:611-614`; `native.sls:1500-1502`; `research/m8/slice3/README.md:137-139` |
| C | `https-proxy-unsupported` on a build without `CURL_VERSION_HTTPS_PROXY`; Apple's 8.7.1 reads the bit clear before its init. Every lane has it after the init, so only the pure rule holds the refusal | `AGENTS.md:440-445`; `native.sls:720-727`; `test-proxy.sps:434-455` |
| M | Apple's LibreSSL falls back to the keychain when a CA file fails: refused instead (`keychain-fallback`); "No test can show the fallback" | `AGENTS.md:383-386` |
| M | Ubuntu's libcurl trusts its default CAPATH beside CAINFO: the transfer clears CAPATH, held as data | `AGENTS.md:379-382` |
| M | GnuTLS reads a `pkcs11:` CA path as a PKCS#11 URL (77 for a bad one): refused on every backend | `AGENTS.md:431-432`; `transfer.sls:604-607` |
| M | Proxy URL with no port: 7.85.0 to 8.20.0 try 1080, 8.23.0 80; `socks5://` parses on 8.23.0 alone: chez-curl sets the port and judges the scheme | `url.sls:299-309`; README.org:186-187 |
| M | Proxy URL `@`/`:@` sent `:` on 8.5.0 and 8.20.0, nothing on 8.23.0; a decoded control byte went direct on 7.85.0 and 8.5.0, failed 3 later: refused at submit | `transfer.sls:4494-4504` |
| M | Prior knowledge over `https://`: 8.20.0 and 8.23.0 offer ALPN h2 alone (35 from an HTTP/1.1 origin): refused, `prior-knowledge-over-https` | `transfer.sls:4612-4616` |
| M | Credentials both `""`: 8.23.0 sends no header: refused, `credentials-empty` | `conditions.sls:433-436` |
| M | `Expect: 100-continue`: 7.85.0 and 8.5.0 match it anywhere in the value, 8.20.0 and 8.23.0 as a list element: the stream rule matches the floor's way | `AGENTS.md:506-510`; `transfer.sls:1700-1705` |
| M | `curl_url_set` of a part moves `%XX` case (lower to 8.20.0, upper on 8.23.0): a query part goes out as written | `AGENTS.md:460-463`; `curl.sls:247-251` |
| M | A lone `#` Location drops the last segment and query on 7.85.0, 8.5.0, 8.7.1: the high level sets the fragment itself | `exchange.sls:652-656` |
| M | Loaded cookie lines: a control byte stored raw before 8.23.0, the line dropped on 8.23.0; 7.85.0's `strtok_r` merges empty fields; a relative path kept or made `/`; a prefix matched in any case on 7.85.0, 8.20.0, 8.7.1, in its own case on 8.23.0: the load refuses each | `transfer.sls:2734-2777`; `AGENTS.md:564-567` |
| M | A loaded cookie past the 8,190-byte `Cookie` line left the head open on every libcurl: the load caps a line at 4,096 | `transfer.sls:2698-2705`; `AGENTS.md:552-556` |
| M | A share holding HSTS carried an entry to the next transfer on 8.5.0 and later: the share holds cookies alone | `transfer.sls:2690-2696` |
| M | 7.85.0's `MAXREDIRS` default is unbounded (about 90,000 requests in 5 s against a 417 loop): pinned at 30 | `transfer.sls:2318-2331` |
| M | `RESUME_FROM` beside a body reads stdin on 7.85.0; `UPLOAD` or `POST` after `MIMEPOST` reads stdin (a PUT on 7.85.0): owned | `AGENTS.md:452-453,617-618`; `transfer.sls:2210-2213` |
| M | A file part's path refused 26 by `curl_mime_filedata` is still sent, as an empty field from 8.20.0: any answer but 0 fails `part-file` | `AGENTS.md:605-610` |
| M | With `CURLMIMEOPT_FORMESCAPE`, CR and LF go out raw on 7.85.0 to 8.20.0 and on 8.7.1: `MIME_OPTIONS` is owned and never set | plan §9 |
| M | 7.85.0 and 8.5.0 lose a write refusal inside `curl_easy_pause`'s replay and end 0; 8.7.1 hands a refused chunk again: the recorded reason wins, alike (`test-stream.sps:904-906`) | `AGENTS.md:493-496,515-517` |
| M | Ubuntu's 8.5.0 spins `curl_multi_poll` while paused; 7.85.0 during a paused HTTP/2 upload once DATA went: the poll is paced (table 32's control is a seam) | `AGENTS.md:495-496,521-522`; `engine.sls:1833-1840` |
| M | 8.7.1: a write error on one HTTP/2 stream fails its sibling; a paused stream fills the 64 MiB cap; a failed rewind resends from the middle: no multiplexing on 8.7.x, `FRESH_CONNECT` for a stream | `AGENTS.md:497-501` |
| M | Guix's 8.20.0 reads back a `curl_multi_wakeup` inside the perform, its poll then waiting up to 1 s: the engine looks at its queue first | `AGENTS.md:502-505`; `engine.sls:443-449` |
| M | 7.85.0 reads `FORBID_REUSE` only as a transfer ends, and let an environment proxy's transfer ride another user's tunnel: table 17 pins the fix | `AGENTS.md:543-547`; `transfer.sls:199-207` |
| S | Under the memory gate, 8.20.0 sometimes reads a 417 as cutting an upload short and resends on a new connection | `AGENTS.md:623-625` |
