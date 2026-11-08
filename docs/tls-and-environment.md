# TLS and the environment

What chez-curl and libcurl read from your process, which libcurl gets loaded,
and how a server's certificate is checked.

## Finding libcurl

chez-curl loads libcurl itself, once per process, the first time your program
reaches a name that needs it. A program that imports `(curl)` or
`(http-client)` and uses one does this before its first line runs, so a
`guard` in the program cannot catch a refusal. The condition types, their
predicates and accessors, the reason lists and `libcurl-info`'s accessors load
nothing.

It takes the first of these that exists:

| Where | Candidates, in order |
|---|---|
| `CHEZ_CURL_LIBCURL` set | that path alone, as given: it must be absolute |
| Linux, under Guix | `$GUIX_ENVIRONMENT/lib/libcurl.so.4`, `$GUIX_PROFILE/lib/libcurl.so.4`, `$HOME/.guix-home/profile/lib/libcurl.so.4`, `$HOME/.guix-profile/lib/libcurl.so.4`, `/run/current-system/profile/lib/libcurl.so.4` |
| Linux, elsewhere | `/usr/local/lib/libcurl.so.4`, `/usr/lib/TRIPLE/libcurl.so.4`, `/usr/lib64/libcurl.so.4`, `/usr/lib/libcurl.so.4`, `/usr/lib/TRIPLE/libcurl-gnutls.so.4` |
| macOS | `/usr/lib/libcurl.4.dylib`, Apple's |

TRIPLE is `x86_64-linux-gnu` on amd64 and `aarch64-linux-gnu` on arm64. A
process is under Guix when its C library comes from `/gnu/store/`; then no
system directory is tried, and elsewhere no Guix profile is. Homebrew's and
MacPorts' libcurls are reached through `CHEZ_CURL_LIBCURL` alone:

```sh
CHEZ_CURL_LIBCURL=/opt/homebrew/opt/curl/lib/libcurl.4.dylib scheme --libdirs src --program app.sps
```

The variable is read once, at the load: a change after it does nothing.

**A refusal** raises `&curl-library-unavailable`, at the load and again at
every later reference. Its reason says why:

| Reason | What happened | What to do |
|---|---|---|
| `invalid-override` | `CHEZ_CURL_LIBCURL` is set, but not to an absolute path, the empty string among it | give an absolute path, or unset it |
| `not-found` | no candidate exists; `curl-library-unavailable-candidates` lists every path tried | install libcurl, or set `CHEZ_CURL_LIBCURL` |
| `load-failed` | the loader refused the file; `-detail` holds its message | check the path and the architecture |
| `below-floor` | the libcurl is older than [README.org's Requirements](../README.org) say | point `CHEZ_CURL_LIBCURL` at a newer one |
| `no-ssl` | the libcurl was built without TLS | use one built with TLS |
| `missing-api` | the libcurl was built without an API chez-curl needs; `-detail` names it | use a fuller build |

Ubuntu 22.04, Debian 11 and RHEL 9 ship a libcurl older than the floor: on
them, build or install a newer one and set `CHEZ_CURL_LIBCURL` to it.

A libcurl built without its multipart support still loads: a request with a
multipart body is refused when you submit it, `multipart-unsupported`, and
every other request works.

`(loaded-libcurl)` tells what was loaded: its path, where the path came from,
its version and its TLS library, as libcurl reports them before it starts.

```scheme fragment
(libcurl-info-version (loaded-libcurl))      ; "8.20.0", say
(libcurl-info-source (loaded-libcurl))       ; override, guix-profile, system, ...
(libcurl-info-ssl-version (loaded-libcurl))  ; "GnuTLS/3.8.13", say
```

On Apple's libcurl, which carries two TLS libraries, `libcurl-info-ssl-version`
names the first of them, whatever is in use: LibreSSL is, unless
`CURL_SSL_BACKEND` names the other (below).

## Checking a server's certificate

A request checks the server's certificate and name by default.

- **`ca-file`** names the only CA file to trust. With it `#f`, the default,
  libcurl's own store is used, as it was built. No CA directory is read beside
  a CA file.
- **`verify #f`** turns the check off. Use it only to debug.
- **A `ca-file` that begins `pkcs11:`**, in any case, is refused,
  `pkcs11-url`: GnuTLS reads such a path as a PKCS#11 token, not a file. Name
  the file as `./pkcs11:...`.
- **An `https://` proxy's TLS is its own:** `proxy-ca-file` and
  `proxy-verify`. See [Auth and proxies](auth-and-proxies.md).

Two platforms can put another anchor beside your CA file, so there chez-curl
refuses a request with a `ca-file` and `verify` on when you submit it:

- **Guix's libcurl, `SSL_CERT_FILE` and `SSL_CERT_DIR`.** Guix's libcurl reads
  both as it loads, and its 8.20.0 puts `SSL_CERT_FILE` in place of your
  `ca-file`, and adds `SSL_CERT_DIR`'s certificates. So on any Guix libcurl,
  when either was set and not empty as the program started, such a request is
  refused, `environment-override`, naming each one set. Unset them before
  starting the program, or leave out `ca-file` to trust the store they name.
  Outside Guix, no libcurl measured let them touch a `ca-file`.
- **macOS, Apple's LibreSSL.** Apple's libcurl has two TLS libraries and uses
  LibreSSL unless `CURL_SSL_BACKEND` names the other. LibreSSL checks the
  keychain when a CA file fails, so a server the keychain trusts passes
  whatever your file says. Such a request is refused there,
  `keychain-fallback`, naming the TLS library. Start the program with
  `CURL_SSL_BACKEND=secure-transport`, which keeps your `ca-file` the only
  anchor. chez-curl reads no other setting for it.

```sh
CURL_SSL_BACKEND=secure-transport scheme --libdirs src --program app.sps
```

## What a transfer reads from the environment

chez-curl never changes your environment. It reads `CHEZ_CURL_LIBCURL`,
Guix's profile variables and `HOME` to find libcurl, and `SSL_CERT_FILE` and
`SSL_CERT_DIR`, all at the load. libcurl and its TLS library read these:

| Variable | Read by | What it does |
|---|---|---|
| `http_proxy`, `https_proxy`, `HTTPS_PROXY`, `all_proxy`, `ALL_PROXY` | libcurl, each transfer with `proxy environment`, the default | the transfer goes through the proxy named ([Auth and proxies](auth-and-proxies.md)) |
| `no_proxy`, `NO_PROXY` | the same | hosts that go direct |
| `HTTP_PROXY` | nobody | ignored |
| `SSLKEYLOGFILE` | the TLS library | writes every transfer's secrets to the file it names: anyone with the file can read the traffic. Use it only to debug |
| `OPENSSL_CONF` | OpenSSL | a configuration file, which can weaken what OpenSSL checks |
| `CURL_SSL_BACKEND` | Apple's libcurl, at the load | picks its TLS library (above) |
| `SSL_CERT_FILE`, `SSL_CERT_DIR` | Guix's libcurl, at the load | replace or add to your `ca-file` (above) |

A transfer reads no `.netrc` and no cookie file: those options are chez-curl's
own, and never set. A request with `proxy #f` or a proxy URL reads none of the
proxy variables.
