# ADR-0018: A request's CA file is its only trust anchor

- **Status:** Accepted
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
  - `CAINFO_BLOB` added its CA on both OpenSSL builds. Ubuntu's GnuTLS 8.5.0 answers it
    `CURLE_NOT_BUILT_IN` (4).
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
- **Other answers, the same on all four:**
  - a CA file that does not exist, or a directory, answers 77,
    `CURLE_SSL_CACERT_BADFILE`, never a fallback to the system store;
  - a CA file whose path holds `é` and `λ` works;
  - turning off `SSL_VERIFYPEER` alone still checks the host, and `SSL_VERIFYHOST` alone
    still checks the chain;
  - with no CA store installed, the OpenSSL builds answer 77 for the system store, since
    their default `CAINFO` names a missing file. GnuTLS answers 60.
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
     file is libcurl's to refuse: 77.
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
   - A child test pins the override by ADR-0002's world. On a Guix libcurl, `SSL_CERT_FILE`
     replaces the CA file and `SSL_CERT_DIR` adds to it. Elsewhere both are ignored.
   - M4, which makes the CA field public, decides what chez-curl does about it.

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
  computed as data by the transfer and held whole by `test-transfer-tls`, as the pins are.
  The Docker measurement above is the behavioural evidence.
- **The system-store control needs a system store:** `ca-certificates`
  (`packaging/debian-prereqs.txt` lists it), Guix's GnuTLS store, or the keychain. Without
  one, the OpenSSL builds answer 77, and the suite names the missing store.
- **The Mac measures SecureTransport.** `test-transfer-tls` there shows its verdicts, its
  answer to `CAPATH`, and whether it reads `SSL_CERT_FILE`. A refusal there is a finding,
  settled before slice 3 merges (M2 plan, §6).
