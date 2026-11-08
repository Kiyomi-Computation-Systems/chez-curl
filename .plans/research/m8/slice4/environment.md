# The environment, and finding libcurl, on `fb62a0b`

Read-only, 2026-11-08, `feat/m8-docs` off `main` at `fb62a0b`. What the load and a transfer read
from the process's environment, by today's code, and the candidate lists the load probes. Every
`getenv` in `src/` is in two places: `discovery.sls` (the choice) and `native.sls` (the CA
variables): `grep -n getenv src/curl/private/*.sls src/http-client/private/*.sls src/*.sls`.

## 1. Read by chez-curl's own code

All at the load, once per process, on the thread that first reaches a binding that loads libcurl
(`logs/load-probe.txt`: every export but the condition types, the reason lists and
`libcurl-info`'s accessors loads it). A value changed after the load is never read again
(`native.sls:132-138`, step 0 raises an earlier failure, and runs nothing twice).

| Variable | When it is read | What it does | Code |
|---|---|---|---|
| `CHEZ_CURL_LIBCURL` | first, on every platform | set to an absolute path: that file is loaded, as given, no candidate tried, never checked for existence first (loading decides); set to anything else, the empty string too: refused, `&curl-library-unavailable`, `invalid-override`; unset: the candidate lists below | `discovery.sls:52-70`, `:287-288` |
| `GUIX_ENVIRONMENT` | Linux, Guix world, override unset | `$GUIX_ENVIRONMENT/lib/libcurl.so.4`, the first Guix candidate; unset or not absolute: none | `discovery.sls:251-262` |
| `GUIX_PROFILE` | the same | `$GUIX_PROFILE/lib/libcurl.so.4`, second | `discovery.sls:253, 257` |
| `HOME` | the same | `$HOME/.guix-home/profile/lib/libcurl.so.4`, then `$HOME/.guix-profile/lib/libcurl.so.4`; unset or not absolute: neither | `discovery.sls:254, 258-261` |
| `SSL_CERT_FILE`, `SSL_CERT_DIR` | step 5, just before `curl_global_init`, on every libcurl; an empty value read as unset | recorded; a submit then refuses a request with a CA file and `verify` on, `environment-override`, naming each one set, when the loaded libcurl is Guix's (its file under `/gnu/store/`, or holding Guix's patch's literal `SSL_CERT_FILE`) and its version has no row saying it does not override (`guix-ca-overrides`, one row: 8.20.0 overrides); the same for `proxy-ca-file` with `proxy-verify` | `native.sls:686-701`; `transfer.sls:610-706`; `native.sls:664-674` |

Besides variables, the load reads: Chez's `machine-type` (a name ending `le` is Linux, `osx`
macOS, any other has no candidate: `discovery.sls:96-101`); `/proc/self/maps` on Linux, for the
world (libc mapped from under `/gnu/store/` is Guix) and for the file `curl_version_info` is mapped
from (`native.sls:222-233`, `:664-667`; `discovery.sls:116-140`); that file's bytes, once, for
Guix's literal (`native.sls:668-674`); and the TLS backend and features word after
`curl_global_init` (`native.sls:712-736`).

## 2. Read by libcurl or its TLS library, as chez-curl's code and records name them

chez-curl reads none of these; it sets options that decide whether libcurl does.

| Variable | Read by | What it does, measured where | chez-curl's part | Citation |
|---|---|---|---|---|
| `http_proxy`, `https_proxy`, `HTTPS_PROXY`, `all_proxy`, `ALL_PROXY` | libcurl, each transfer, when `proxy` is `environment` (the default) | the transfer goes through the proxy named; measured on the five Linux libcurls, each alike; 8.7.1 not run | `proxy` `environment` sets nothing, so libcurl reads them; `#f` sets `PROXY ""`, which reads none; a URL sets `PROXY` and `NOPROXY ""`, so none applies | ADR-0024:24-33 (:28-29); `transfer.sls:943-952, 2562-2581` |
| `HTTP_PROXY` (upper case) | ignored by libcurl | a lone one sent the transfer to the origin | none | ADR-0024:30; `transfer.sls:947` |
| `no_proxy`, `NO_PROXY` | libcurl, with `environment` | naming the origin's host sends it direct; no effect beside a proxy URL | `NOPROXY ""` beside a URL | ADR-0024:31; `transfer.sls:2551-2553` |
| userinfo in a proxy variable | libcurl | one that decodes to 0x00 to 0x1F sends 7.85.0 and 8.5.0 direct, 200; 8.20.0 and 8.23.0 fail 3; never parsed by chez-curl | none: a named proxy URL's userinfo is checked instead | ADR-0024:336-343 |
| `SSL_CERT_FILE`, `SSL_CERT_DIR` | Guix's libcurl patch, at `curl_global_init` | Guix's 8.20.0 writes `SSL_CERT_FILE` over a transfer's `CAINFO` and adds `SSL_CERT_DIR`, after every setopt; its 8.6.0 lets the request win; outside Guix both ignored, the Mac's 8.7.1 too | the refusal above (§1) | ADR-0024:37-41; `transfer.sls:610-620` |
| `SSLKEYLOGFILE` | the TLS library | every libcurl measured wrote each transfer's TLS secrets to the file | documented, not refused | ADR-0024:42, :62-64 |
| `OPENSSL_CONF` | OpenSSL | at security level 0 a 1024-bit leaf passed, on the OpenSSL builds | documented, not refused | ADR-0024:43, :62-64 |
| `CURL_SSL_BACKEND` | a MultiSSL libcurl, at `curl_global_init` | on Apple's 8.7.1, LibreSSL is in use unless it names another; LibreSSL checks the keychain when a CA file fails | a submit refuses a CA file with `verify` on there, `keychain-fallback`, unless the backend in use is not LibreSSL: `CURL_SSL_BACKEND=secure-transport`; `make test` sets it on macOS | `transfer.sls:659-706`; `Makefile:32-36`; ADR-0024:281-283, :307 |
| `OPENSSL_X509_TEA_DISABLE` | Apple's LibreSSL | turns the keychain fallback off; chez-curl does not read it and still refuses | none | README.org:65-67; `grep -rn OPENSSL_X509_TEA_DISABLE src/`: no match |

Not read, by the options chez-curl sets: a `.netrc` (`NETRC` owned and never set:
`transfer.sls:2303`), a cookie file (`COOKIEFILE` set to `""` only with a jar, ADR-0035), a CA
directory beside a CA file (`CAPATH` cleared: `transfer.sls:2466-2482`). libcurl's own build-time
default CA store is read for a request with no `ca-file`, as built.

**For installing from a clone** (the plan's README.org section), Chez's own: `CHEZSCHEMELIBDIRS`,
or `--libdirs`, puts `src` on the library path. The suites use `--libdirs src:build/scheme-libs`
(`Makefile`, `test`); a caller's program needs `src` alone, since no public library imports
chez-srfi (`check-seam`, `tests/check-seam.sps`). Not measured here: an installed tree (ADR-0002:
"An installed tree waits for packaging").

## 3. Finding libcurl: ADR-0002's candidate lists, as the code has them

`choose-libcurl` (`discovery.sls:52-70`) takes the first candidate that exists, asked one at a
time in order, `regular-file?` (symlinks followed: `native.sls:235-239`); none existing is
`not-found`, listing every path checked (`discovery.sls:76-85`). They match ADR-0002:59-83 path
for path and in order.

| Platform | Candidates, in order | Source symbol | Code |
|---|---|---|---|
| any, override set | `$CHEZ_CURL_LIBCURL`, as given | `override` | `discovery.sls:66` |
| Linux, Guix world | `$GUIX_ENVIRONMENT/lib/libcurl.so.4`; `$GUIX_PROFILE/lib/libcurl.so.4`; `$HOME/.guix-home/profile/lib/libcurl.so.4`; `$HOME/.guix-profile/lib/libcurl.so.4`; `/run/current-system/profile/lib/libcurl.so.4`. Never an FHS directory | `guix-environment`, `guix-profile`, `guix-home`, `guix-user-profile`, `guix-system` | `discovery.sls:251-268` |
| Linux, FHS world (`ta6le`: triple `x86_64-linux-gnu`; `tarm64le`: `aarch64-linux-gnu`; any other Linux type: no triple directory) | `/usr/local/lib/libcurl.so.4`; `/usr/lib/<triple>/libcurl.so.4`; `/usr/lib64/libcurl.so.4`; `/usr/lib/libcurl.so.4`; `/usr/lib/<triple>/libcurl-gnutls.so.4`. Never a Guix profile | `system` | `discovery.sls:106-110, 274-283` |
| macOS (`*osx`) | `/usr/lib/libcurl.4.dylib` alone, not asked whether it exists (the dyld shared cache has no file); Homebrew's and MacPorts' only through the override | `macos-system` | `discovery.sls:58-60, 238` |
| any other | none: the override alone works | — | `discovery.sls:65, 245` |

The world is Guix when a line of `/proc/self/maps` names a `libc.so.6` under `/gnu/store/`; FHS
otherwise, and when the maps cannot be read (`discovery.sls:116-125`; `native.sls:225-233`).

**What a refusal tells** (`conditions.sls:149-178`): `curl-library-unavailable-reason`, one of
`invalid-override`, `not-found`, `load-failed`, `below-floor`, `no-ssl`, `missing-api`; `-path` and
`-source`; `-candidates` (every path checked, `not-found`); `-detail` (the override's value, the
loader's message, the version, or the API's C name); `-library`, the `libcurl-info` for a refusal
made after `curl_version_info` was read. Ubuntu 22.04, Debian 11 and RHEL 9 ship libcurls below
7.85.0 and need the override (ADR-0003:120-122): `below-floor`, then `CHEZ_CURL_LIBCURL` at a newer
one.

**Held by:** `tests/test-discovery.sps` (the pure rules, synthetic inputs); `test-load-state`,
`test-library-loading` (the decoy) and `test-verify` (the refusals); `test-drift` (the loaded row).
