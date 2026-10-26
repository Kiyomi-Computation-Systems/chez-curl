# ADR-0018: A request's CA file is its only trust anchor

- **Status:** Accepted; amended 2026-10-26: SecureTransport's first run; amended 2026-10-26:
  the environment's policy is decided (the M4 plan)
- **Date:** 2026-10-24
- **Scope:** M2's private request (M2 plan, §6), and M4's public one, which inherits its
  fields
- **Settles:** what a CA file means, what turning verification off sets, and what chez-curl
  does about Guix's environment patch. The maintainer chose on 2026-10-24.
- **Related:** brief §2 item 5 and §9 risk 3 ·
  [ADR-0002](0002-runtime-libcurl-discovery.md), whose worlds the pin test reads ·
  [ADR-0003](0003-libcurl-floor-7-85.md), any TLS backend ·
  [ADR-0009](0009-typed-escape-hatch.md), amended 2026-10-24 with this record's twins ·
  [the M2 plan](../2026-10-19-m2-plan.md), §6.1

## Context

M2's request gains two TLS fields: a CA file, or `#f` for the system store, and whether to
verify. Brief §9 risk 3 warned that backends differ "the moment someone passes a custom CA".
Measured on 2026-10-24 through C, under `build/verify/m2s3/measure/` (not kept), on
7.85.0 (the floor's build, OpenSSL 3.0.13), Ubuntu 24.04's 8.5.0 with OpenSSL and with GnuTLS,
and the container's 8.20.0 with GnuTLS (M2 plan, §6.1):

- **The plan's verdicts agree on all four,** wherever a system CA store exists.
  - The good face with the run CA: 200, HTTP/1.1. The `h2` face: 200, HTTP/2.
  - Expired, wrong-host and untrusted with the run CA: 60, `CURLE_PEER_FAILED_VERIFICATION`.
  - All four faces with verification off: 200.
  - The good face with the system store: 60.
- **A CA file is not exclusive on Ubuntu's libcurl.** With the run CA installed in a
  throwaway container's system store, a request whose CA file named the other CA passed on
  Ubuntu's 8.5.0, with OpenSSL and with GnuTLS.
  - Both are built with a default `CAPATH`, `/etc/ssl/certs`, and setting `CAINFO` does not
    clear it. The floor's build has no default `CAPATH`, and refused, 60.
  - Setting `CAPATH` to NULL made the CA file exclusive on all three.
- **Beside `CAINFO`, with `CAPATH` cleared, two more options widen trust:**
  - `CAINFO_BLOB` added its CA on both OpenSSL builds, and on 8.20.0, which has no default
    `CAPATH`. Ubuntu's GnuTLS 8.5.0 answers it `CURLE_NOT_BUILT_IN` (4).
  - `SSL_OPTIONS` with `CURLSSLOPT_NATIVE_CA` added the system store on Ubuntu's GnuTLS 8.5.0.
    On the OpenSSL builds it changed nothing.
- **Guix's libcurl reads `SSL_CERT_FILE` and `SSL_CERT_DIR`.** Guix's
  `curl-use-ssl-cert-env.patch` reads both at `curl_global_init`. Its 8.20.0 version then
  writes them over `CAINFO` and `CAPATH` in `Curl_ssl_easy_config_complete`, which runs when
  a transfer starts, so after every setopt. Measured on 8.20.0:
  - `SSL_CERT_FILE` at the other CA refused the good face, whose request named the run CA:
    the variable replaced the CA file;
  - `SSL_CERT_DIR` at a directory holding the run CA passed a request naming the other CA:
    the variable added a CA directory.

  Ubuntu's 8.5.0, with both backends, and the floor ignore both. `CURL_CA_BUNDLE` is read
  only by the curl command line, and no libcurl read it. A Guix profile with `nss-certs`
  exports all three, and the maintainer's host does. The container passes none of them.

  **Guix's 8.6.0 behaves the other way.** Its older patch sets the two variables as an easy
  handle's defaults, when the handle is made, so the request's own setopts win. The
  adversarial review measured it, loading Guix's `curl-8.6.0` from the store with its
  closure, and the lead reran it:

  | Case | Guix 8.6.0 | Guix 8.20.0 |
  |---|---|---|
  | `SSL_CERT_FILE` at the other CA, CA file the run CA | 200 | 60 |
  | `SSL_CERT_FILE` at the run CA, CA file the other CA | 60 | 200 |
  | `SSL_CERT_DIR` at the run CA's directory, CA file the other CA | 60 | 200 |

  So the override depends on the patch's version, not on Guix alone.
- **Other answers, the same on all four:**
  - a CA file that does not exist, or a directory, answers 77,
    `CURLE_SSL_CACERT_BADFILE`, never a fallback to the system store;
  - a CA file whose path holds `é` and `λ` works;
  - turning off `SSL_VERIFYPEER` alone still checks the host, and `SSL_VERIFYHOST` alone
    still checks the chain;
  - with no CA store installed, the OpenSSL builds answer 77 for the system store, since
    their default `CAINFO` names a missing file. GnuTLS answers 60.
- **Three more things a transfer reads, measured by the review** on all four libcurls unless
  named:
  - `SSLKEYLOGFILE` makes libcurl write each transfer's TLS secrets to the file it names:
    five lines for one GET, its handshake and traffic secrets among them.
  - `OPENSSL_CONF` can weaken what an OpenSSL build verifies. A config setting
    `CipherString = DEFAULT:@SECLEVEL=0` let a leaf with a 1024-bit RSA key, signed by the
    request's own CA file, pass on Ubuntu's 8.5.0 with OpenSSL and on the floor, where it
    answered 60 without the variable. Trust anchors were not changed by it. Ubuntu's
    GnuTLS 8.5.0 accepted that leaf with no variable at all.
  - On GnuTLS, a CA file that starts `pkcs11:` is read as a PKCS#11 URL, not a path: it
    answered 60, not the 77 of a missing file, on 8.20.0 and Ubuntu's 8.5.0. No widening was
    shown: with the run CA in Ubuntu's store and `p11-kit-modules` installed, it still
    answered 60. The OpenSSL builds answered 77.
- **Apple's libcurl is MultiSSL.** Apple's LibreSSL checks the keychain when a CA file fails
  to verify (curl issue 12604, 2024), and Apple called that intended. But the Mac's drift
  row reads `SecureTransport (LibreSSL/3.3.6)`, so a library process selects SecureTransport.
  curl's SecureTransport code makes a CA file the only anchors, and has no CA directory, so it
  should answer `CAPATH` with `CURLE_NOT_BUILT_IN`. Neither has been measured on the Mac yet.

## Decision

1. **A CA file is the request's only trust anchor.** The CA file field sets `CAINFO` to the
   file and clears `CAPATH`.
   - A backend with no CA directory answers `CAPATH` with `CURLE_NOT_BUILT_IN`. That answer
     is accepted, since there is no directory to clear. Any other code but `CURLE_OK` is
     `setopt-failed`.
   - The path reaches libcurl as given, as a counted UTF-8 copy. A path holding U+0000 is
     refused before anything native, as `&curl-request-error`, `embedded-nul`. A missing
     file is libcurl's to refuse: 77. On GnuTLS, a path starting `pkcs11:` is a PKCS#11 URL,
     and is M4's to document or refuse.
2. **`#f` is libcurl's system store, as that library was built.** Neither option is set.
3. **Every transfer sets verification.** `SSL_VERIFYPEER` and `SSL_VERIFYHOST` are 1 and 2
   unless the request turns verification off, and then both are 0. A CA file beside
   verification off is allowed: libcurl reads no CA then.
4. **The CA file's twins are refused by the test seam:** `CAINFO_BLOB` and `SSL_OPTIONS`.
   Each changes which anchors are trusted. `SSL_OPTIONS`' other bits are closed with it, and
   M4 can wrap any that are wanted as fields. `CAPATH` is a field's own option (ADR-0009,
   amended 2026-10-24).
5. **Guix's environment override is pinned, and its policy is M4's.**
   - `test-transfer-tls` fails first when `SSL_CERT_FILE` or `SSL_CERT_DIR` is set,
     naming it, as `test-transfer` does for the proxy variables.
   - A child test pins the override by ADR-0002's world and the loaded libcurl's version,
     from a table written out in the suite. On Guix's 8.20.0, `SSL_CERT_FILE` replaces the CA
     file and `SSL_CERT_DIR` adds a directory. Outside Guix both are ignored. A Guix libcurl
     of any other version fails the pin, naming its version, until its verdicts are
     measured and added. That replaces keying on the world alone, which the review showed
     wrong for Guix's 8.6.0.
   - Each variable is tried both ways, so "ignored" is told from "added": `SSL_CERT_FILE` at
     the other CA with the run CA as the CA file, and at the run CA with the other CA as the
     CA file.
   - M4, which makes the CA field public, decides what chez-curl does about it, with the
     table above.

### Rejected

- **Additive, libcurl's default.** What a CA file meant would depend on how the library was
  built: exclusive on the floor's build and Guix's, and beside the whole system store on
  Ubuntu's.
- **`CAINFO_BLOB` in place of `CAINFO`.** Ubuntu's GnuTLS 8.5.0, CI's GnuTLS lane, does not
  build it in.
- **Refusing the CA file now on a Guix libcurl with either variable set.** That needs the
  environment read beside `curl_global_init`, and the world handed to the transfer. It is
  M4's to choose, with the public field.
- **Unsetting the variables in the process.** That changes the caller's environment, and
  `setenv` is not safe beside other threads.

## Consequences

- **On a Guix machine whose profile exports either variable, the CA field does not hold
  until M4 decides.** The suites run in the container, which passes neither, and
  `test-transfer-tls` fails first anywhere else that sets them.
- **Clearing `CAPATH` has no behavioural test in any lane.** No lane's system store trusts
  the run CA, so a transfer that left `CAPATH` set would pass every case. The settings are
  computed as data by the transfer and held whole by `test-transfer-tls`, as the pins are,
  and so is `set-option!`, which sends the clear as NULL and judges its answer. Until it was,
  the review's mutant that skipped the clear passed `make test`, and in Docker, with the run
  CA in Ubuntu's store, it trusted the other CA's file: 200 where the tree answers 60. The
  Docker measurement above is the behavioural evidence.
- **The system-store control needs a system store:** `ca-certificates`
  (`packaging/debian-prereqs.txt` lists it), Guix's GnuTLS store, or the keychain. Without
  one, the OpenSSL builds answer 77, and the suite names the missing store.
- **M4 owns what a transfer reads from the environment:** the proxy variables, Guix's
  `SSL_CERT_FILE` and `SSL_CERT_DIR` with the table above, `SSLKEYLOGFILE`, `OPENSSL_CONF`,
  and the `pkcs11:` prefix on GnuTLS. `test-transfer-tls` fails first on the proxy
  variables, `SSL_CERT_FILE` and `SSL_CERT_DIR`. The rest are recorded here, not checked: an
  `OPENSSL_CONF` that narrows the ciphers can change a verdict too, as the review's control
  showed, 35.
- **The Mac measures SecureTransport.** `test-transfer-tls` there shows its verdicts, its
  answer to `CAPATH`, and whether it reads `SSL_CERT_FILE`. The Mac was out of reach when
  slice 3 was ready, and the maintainer chose to merge first: that run is owed before M2 is
  done, and a refusal there is a finding for its own branch (M2 plan, §6 and §7).

## Amendment, 2026-10-26: SecureTransport's first run

The Mac's `make test`, on PR #22's branch, ran `test-transfer-tls` against Apple's libcurl 8.7.1
for the first time: all 55 checks passed. So on SecureTransport each face answers as the shared
verdicts say, and the transfer reads neither `SSL_CERT_FILE` nor `SSL_CERT_DIR`, as the suite's
pin requires of every libcurl but Guix's 8.20.0. Whether SecureTransport answers the `CAPATH`
clear with `CURLE_OK` or `CURLE_NOT_BUILT_IN`, the run does not say: the transfer takes either.

## Amendment, 2026-10-26: the environment's policy is decided (the M4 plan)

The policy this record handed to M4 is [ADR-0024](0024-what-a-transfer-reads-from-its-environment.md),
chosen by the maintainer on 2026-10-26:
- where Guix's override would replace a request's CA file, the request is refused at submit,
  naming the variable. The variables are read when libcurl loads, beside `curl_global_init`, and
  a table moves into `src/`: Guix's 8.20.0 overrides, and every other Guix libcurl is taken to,
  8.6.0 among them, whose row above came from a measurement that was not kept. As amended after
  the plan's review, it is keyed by the loaded library's path under `/gnu/store`, an empty
  variable counts as unset, and only a request with verification on is refused (ADR-0024,
  amended 2026-10-26);
- `SSLKEYLOGFILE` and `OPENSSL_CONF` are documented, not refused;
- a CA file's path that begins `pkcs11:`, in any ASCII case, is refused when the request is made,
  on every backend;
- the proxy variables are honoured, by libcurl's rules, and a request field turns them off.

Decision 5's "its policy is M4's" and Consequences' "does not hold until M4 decides" end when M4
builds it.
