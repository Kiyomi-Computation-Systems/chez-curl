# ADR-0024: What a transfer reads from its environment

- **Status:** Accepted; amended 2026-10-26: a proxy's TLS, and after the plan's review;
  amended 2026-10-26: measured before slice 3; amended 2026-10-26: as built in slice 3;
  amended 2026-10-26: the key, after slice 3's review
- **Date:** 2026-10-26
- **Scope:** chez-curl v1, every transfer, from M4
- **Settles:** the environment policy ADR-0018 handed to M4: the proxy variables, Guix's
  `SSL_CERT_FILE` and `SSL_CERT_DIR`, `SSLKEYLOGFILE`, `OPENSSL_CONF`, and GnuTLS's `pkcs11:`
  CA paths. The maintainer chose each on 2026-10-26.
- **Related:**
  - [ADR-0002](0002-runtime-libcurl-discovery.md), the worlds;
  - [ADR-0009](0009-typed-escape-hatch.md): owned options and their twins;
  - [ADR-0018](0018-ca-file-is-the-only-anchor.md), whose measurements of the TLS variables and
    `pkcs11:` this record rests on;
  - [ADR-0023](0023-the-public-request.md), the public request.

## Context

libcurl, and the TLS library under it, read several variables from the process's environment.
chez-curl cannot unset them: `setenv` is not safe beside other threads, and the environment is
the caller's (ADR-0018, Rejected).

**The proxy variables, measured on 2026-10-26** (`research/m4/proxy/`) on 7.85.0, Ubuntu's
8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0, each alike. A C probe made one
transfer under `env -i` with only the variables a case named; a stand-in proxy answered 299
and logged every request it got.
- A transfer reads `http_proxy`, `https_proxy`, `HTTPS_PROXY`, `all_proxy` and `ALL_PROXY`, and
  goes through the proxy each names: the proxy logged one request per case.
- A lone `HTTP_PROXY` is ignored: the transfer went to the origin.
- `no_proxy` and `NO_PROXY` naming the origin's host send it direct.
- `CURLOPT_PROXY` set to `""` sends it direct with each variable set, and so does
  `CURLOPT_NOPROXY` set to `"*"`. The proxy logged nothing.

The Mac's 8.7.1 has not run the probe.

**The TLS variables and `pkcs11:`,** measured for ADR-0018 on the four Linux libcurls:
- Guix's 8.20.0 writes `SSL_CERT_FILE` over a transfer's `CAINFO`, and adds `SSL_CERT_DIR`, when
  the transfer starts, after every setopt. Guix's 8.6.0 lets the request win. Outside Guix both
  are ignored, and so they were on the Mac's 8.7.1 (ADR-0018, amended 2026-10-26). Guix's patch
  reads both at `curl_global_init` (`traps.md`).
- `SSLKEYLOGFILE` made every libcurl write each transfer's TLS secrets to the file it names.
- `OPENSSL_CONF` at security level 0 let a 1024-bit leaf pass on the OpenSSL builds.
- On GnuTLS, a CA file starting `pkcs11:` is read as a PKCS#11 URL: it answered 60, where a
  missing file answers 77. No widening of trust was shown.

## Decision

1. **A transfer honours the proxy variables, by libcurl's own rules,** as curl itself does. A
   request field turns them off, for that transfer, by setting `CURLOPT_PROXY` to `""`. The
   field's option is owned, and its twins, among them `NOPROXY`, are refused by the hatch
   (ADR-0009). A proxy given by URL stays M7's.
2. **Where Guix's override would replace a request's CA file, the request is refused at submit.**
   - The variables are read when libcurl loads, beside `curl_global_init`, which is when Guix's
     patch reads them, and recorded.
   - A table by ADR-0002's world and the libcurl's version says which libcurls override:
     Guix's 8.20.0 does, its 8.6.0 does not, and outside Guix none does. A Guix libcurl with
     no row is taken to override.
   - On a libcurl that overrides, with either variable recorded as set, a request with a CA
     file is refused at submit as `&curl-request-error`, naming the variable. A request with
     no CA file, which trusts the system store, goes ahead.
3. **`SSLKEYLOGFILE` and `OPENSSL_CONF` are documented, not refused.** They are the operator's
   to set, and the TLS library reads them in every program that links it. README.org names
   both, with what was measured.
4. **A CA file's path that begins `pkcs11:`, in any ASCII case, is refused when the request is
   made,** on every backend, as `&curl-request-error`. So the field always names a file. A file
   really named that way is still reached as `./pkcs11:…`.

### Rejected

- **Ignoring the proxy variables unless a request asks.** The operator's proxy settings would
  not apply by default.
- **Documenting Guix's override, or reporting it in `loaded-libcurl`.** The CA field's promise,
  the only trust anchor, would fail silently on such a profile.
- **Refusing to load with `SSLKEYLOGFILE` set.** Key logging, a common debugging aid, would
  never work with chez-curl.
- **Taking a PKCS#11 URL on GnuTLS.** The field would mean different things on different
  backends.

## Consequences

- **The suites still fail first when a proxy variable is set.** A test sets one for a child,
  against a stand-in proxy, and shows both the default and the field by the proxy's own log.
- **On Guix with `nss-certs` in the profile, a request with a CA file fails at submit,** naming
  the variable, until the caller unsets it before starting the program.
- **The override table moves from `test-transfer-tls` into `src/`,** and the suite holds the
  library's table to its own copy.
- **The Mac runs the proxy probe** with its next run, and its answers join this record.

## Amendment, 2026-10-26: a proxy's TLS, and after the plan's review

An adversarial review of the M4 plan (Opus, read-only) found the proxy's TLS undecided, though
ADR-0009 (amended 2026-10-24) handed it to M4, and corrected four details.

- **Decided by the maintainer, 2026-10-26: a proxy's TLS stays libcurl's verified default,**
  against its system store, until M7. Decision 1 honours `https_proxy` and `all_proxy`, which
  can name an `https://` proxy, and the request's `ca-file` and `verify` do not reach one. So
  every `PROXY_SSL_*` and `PROXY_CA*` option is owned, and the hatch cannot loosen a proxy's
  verification. A proxy's own CA or verification is a request field with M7's explicit
  proxies. Guix's patch writes the proxy's CA and CA directory from the same two variables
  (`curl-use-ssl-cert-env.patch`): the operator's setting, recorded.
  - **Rejected:** the request's `ca-file` and `verify` covering the proxy too, which would make
    a CA file meant for the origin trust the proxy, and `verify #f` turn off the proxy's checks;
    and leaving the options to the hatch, where a caller could turn a proxy's verification off.
- **Context overclaimed the switches.** The probe ran `CURLOPT_PROXY ""` with `http_proxy`,
  `all_proxy` and `https_proxy` set, and `CURLOPT_NOPROXY "*"` with `http_proxy` and
  `https_proxy`. That each holds for the other variables is libcurl's source, `lib/url.c`, not
  the measurement.
- **Decision 2, made exact:**
  - an empty variable counts as unset, as libcurl's `curl_getenv` reads it;
  - the table is keyed by whether the loaded library's resolved path is under `/gnu/store`, and
    by its version, not by libc's world: a Guix libcurl loaded through `CHEZ_CURL_LIBCURL` by a
    Chez outside Guix is still Guix's;
  - Guix's 8.20.0 overrides, and every other Guix libcurl is taken to. 8.6.0's "does not" came
    from a measurement that was not kept, and `test-transfer-tls` records 8.6.0 as unrecorded;
  - a request is refused only with verification on. With it off libcurl reads no CA, and
    ADR-0018's decision 3 allows a CA file beside it.
- **`CURL_SSL_BACKEND` joins decision 3's documented variables.** On Apple's MultiSSL libcurl it
  selects the backend, and its LibreSSL falls back to the keychain when a CA file fails
  (`traps.md`). The Mac measures whether selecting it undoes a request's CA file. If it does,
  what to do is the maintainer's.

## Amendment, 2026-10-26: measured before slice 3

Measured for the M4 plan's section 6.1 ([`research/m4/slice3/`](../research/m4/slice3/)). A C
probe, `tls-env.c`, set each variable by `setenv` before or after `curl_global_init`, or unset
it after, then made one transfer with chez-curl's TLS settings, against a Node origin and an
`https://` proxy, each serving a leaf the run CA signed. Seven lanes: Guix's 8.20.0 in the
container; in Docker `ubuntu:24.04`, 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS,
8.23.0, and Guix's 8.20.0 and 8.6.0 loaded from the store beside Ubuntu's libc.

- **Guix's patch reads the variables at `curl_global_init`, and only then.** On 8.20.0, in the
  container and outside Guix alike:
  - `SSL_CERT_FILE` set before the init replaced the CA file, both ways. Set after it, it
    changed nothing. Set before and unset after, or emptied after (the second run), it still
    replaced the CA file.
  - An empty value counted as unset.
  - A missing file in it answered 77 with verification on, and 200 with it off: with
    verification off, libcurl reads no CA.
  - `SSL_CERT_DIR` added its directory beside the CA file, when set before the init, and not
    when set after.

  Each matches the patch's source: `curl_getenv` in `global_init`, which answers an empty
  value as NULL.
- **Guix's 8.6.0 does not override a CA file.** Each case answered as on the other libcurls,
  but one: with no CA file and `SSL_CERT_FILE` naming the run CA, the transfer passed. That
  fits the older patch's source, in the store beside the 8.19 one, which sets the variables
  as a handle's defaults, for a request's `CAINFO` and cleared `CAPATH` to replace; which
  patch that build carried, the log does not show. The FHS libcurls ignored both variables
  in every case.
- **Decided by the maintainer, 2026-10-26: 8.6.0 stays taken to override.** No lane runs it,
  so a row saying it does not would rest on one build's log, one of the ten 8.6.0 builds in
  the host's store, and nothing would check it. A wrong "does not" row would break the CA file's
  promise silently; a wrong "does" refuses, naming the variable. The table keeps 8.20.0's row
  alone.
  - **Rejected:** a row for 8.6.0, which would let its profiles use a CA file with `nss-certs`
    installed.
- **The loaded library's own file decides whether it is Guix's, not libc's world.**
  `/proc/self/maps` maps `curl_version_info`'s entry point from the library's real file, its
  symlinks resolved. The container's profile link and a link in a temporary directory both
  mapped from `/gnu/store/…-curl-8.20.0/lib/libcurl.so.4.8.0`. Spike E1's Chez, built on
  Ubuntu, loaded Guix's 8.20.0 and 8.6.0 from the store. Its libc came from `/usr/lib`, so
  ADR-0002's world was FHS. The C probe, built and run in that Ubuntu, showed 8.20.0 still
  overriding there.
- **GnuTLS matches `pkcs11:` in any ASCII case.** Each path tried was a file in the working
  directory, a copy of the run CA, so 200 alone meant it was read as a file.
  - On GnuTLS 3.8.3 (Ubuntu's 8.5.0), 3.8.9 (Guix's 8.6.0) and 3.8.13 (Guix's 8.20.0),
    `pkcs11:`, `pkcs11:object=x`, `PKCS11:` and each letter's case alone (`Pkcs11:` to
    `pkcS11:`) answered 60, and `pkcs11:ca.pem`, a URL that does not parse, 77. None was read
    as a file. A second run, after the slice's review, tried all sixteen ASCII cases: each
    answered 60 on all three (`results/guix-8.20.0-2.log`, `results/docker-2.log`).
  - `pkcs11`, `pkcs1:`, `pkcs111:`, ` pkcs11:`, `pkcs11 :`, `tpmkey:`, `system:`, `./pkcs11:`,
    and `p`, U+212A KELVIN SIGN, `cs11:` were read as files: 200. So, in the second run, were
    `xpkcs11:`, `x/pkcs11:`, each of the prefix's seven chars made the next, and `pkc`,
    U+017F LONG S, `11:`.
  - The OpenSSL builds read every path as a file.

  So decision 4's refusal matches GnuTLS's own rule. On OpenSSL it refuses files that are
  really there, which `./` still reaches.
- **An `https://` proxy is verified against the system store, whatever the request says.**
  With `http_proxy`, `https_proxy` or `all_proxy` naming one, on all seven lanes:
  - a CA file naming the run CA, which signed the proxy's leaf, verification off, and both,
    each answered 60, and the proxy logged no request;
  - `PROXY_CAINFO` at the run CA, or the proxy's own verification off, reached it: 299, or a
    logged `CONNECT`;
  - Guix's 8.20.0 and 8.6.0 took the proxy's CA from `SSL_CERT_FILE`: 299 with no CA file;
  - a refused `CONNECT` answered 56 on 7.85.0, 8.5.0 and 8.6.0, and 7 on 8.20.0 and 8.23.0.

## Amendment, 2026-10-26: as built in slice 3

- **The native layer records two things at the load.** The file the libcurl is mapped from:
  the `/proc/self/maps` line holding `curl_version_info`'s entry point, through `foreign-entry`,
  a reviewed addition to check-seam's names, for native alone; `#f` off Linux. And
  `SSL_CERT_FILE` and `SSL_CERT_DIR`, read immediately before `curl_global_init`, an empty value
  as `#f`. Both are private.
- **Decision 2 as built.** `guix-ca-overrides`, in `(curl private transfer)`, has 8.20.0's row
  alone. `ca-overridden?` keys on the mapped file, or, with none read, the path as loaded,
  under `/gnu/store/`, and, after the review, on that file holding the patch's literal (the
  next amendment). A version with no row is taken to override.
  - The refusal holds whatever the URL's scheme: a CA file beside an `http://` URL, which runs
    no TLS, is refused there too.
  - Another `curl_global_init` in the process, earlier than native's, would read the
    variables first, and libcurl's source makes native's a count alone: the record could then
    differ from what libcurl read, unseen. No suite can plant that.
  - A submit checks the CA file, after the test seam's options and before the URL. With a CA
    file, verification on, and either variable recorded, it refuses as `environment-override`,
    whose irritants are the path, then each variable set, in order.
  - The rule is pure, `overriding-variables`, over native's records. `test-transfer-tls` holds
    it on every lane, with synthetic inputs, and holds the shell that hands it native's records
    whole. Only a Guix libcurl shows the refusal by behaviour, so CI's FHS lanes show the
    variables ignored.
- **The pin now pins the refusal.** Its child takes the variables through its command, or sets
  or empties one after the load, and prints native's record after that. On Guix's 8.20.0, in
  the container, each case with a CA file and verification on is refused, naming each
  variable set, and so is one emptied after the load. One set after the load changes nothing,
  nor does an empty one, verification off, or no CA file, which trusts the variable's store.
  After the review, the record is printed after the child's own change to the environment,
  so on every lane a record read again at submit fails the pin; and one more row loads a copy
  of the libcurl's file from a scratch directory, which, on Guix's, the patch's literal alone
  marks as Guix's. The libcurl's override itself is no longer seen
  through the library: the measurement is its evidence, rerun by `research/m4/slice3/run.sh`'s
  `when` set for any new Guix version.
- **Decision 4 as built:** `pkcs11-url`, by `ca-file-copy`, so both when the request is made
  and at submit. Only A to Z fold. `test-transfer-tls` tries all sixteen ASCII cases, alone and
  before more, and seventeen near misses, among them U+212A and U+017F LONG S, which Unicode
  folds make `k` and `s`. A file named `pkcs11:ca.pem`, reached by its absolute path, passes.
- **Decision 1 as built.** The request's `proxy` key is `environment`, the default, or `#f`,
  which sets `PROXY` to `""`. `PROXY` is the field's option. Its twins are `NOPROXY`, whose `"*"`
  turns the variables off as `""` does; `PRE_PROXY`, a SOCKS proxy before it; and `PROXYPORT` and
  `PROXYTYPE`, parts of the proxy `PROXY` names, as `PORT` is of the URL. The test seam refuses
  each; slice 4's hatch reads its own twins from the options tables.
  - `test-transfer` runs a child given `http_proxy` or `all_proxy` at the origin's http face,
    with `no_proxy` and `NO_PROXY` cleared. The origin now routes a target in absolute form by
    its path, so the face stands in for a plain proxy, and `/echo`'s first line is its own
    record of the target it got: absolute through a proxy, a path direct.

## Amendment, 2026-10-26: the key, after slice 3's review

The slice's review (Opus, read-only) loaded a copy of the container's 8.20.0 from outside the
store, through `CHEZ_CURL_LIBCURL`: five of the pin's rows found the CA file replaced, and
nothing refused it. So a Guix libcurl mapped from anywhere but `/gnu/store/` fails open: a
copied file, perhaps a relocatable `guix pack` in its fallback modes, or any Guix libcurl when
`/proc/self/maps` cannot be read. That is the silent failure this record rejected.

- **Measured, 2026-10-26:** the literal `SSL_CERT_FILE`, Guix's patch's own string, stands
  once in Guix's 8.20.0 and 8.6.0, and in none of 7.85.0, 8.23.0, Ubuntu 24.04's 8.5.0 with
  OpenSSL and with GnuTLS, and the host's 7.81.0 with each (`grep -c -a`).
- **Decided by the maintainer, 2026-10-26: a libcurl is Guix's when its mapped file is under
  `/gnu/store/`, or its file holds the patch's literal `SSL_CERT_FILE`.** The native layer
  reads the library's file once, at the load. A future upstream libcurl that names the
  variable would be refused, loudly, naming it, until it has a row.
  - **Rejected:** widening the path rule, to `/gnu/store/` anywhere in the path and unreadable
    maps taken to override, which leaves a plain copy failing open; and recording the gap
    alone.
