# OpenSSL 4's x509 -text, against 3.0

The Mac's `make test` at `08eca49` ([log](../../mac/mac-8.7.1-make-test-openssl41.log))
ran Homebrew's OpenSSL 4.1.0 and failed two checks that held OpenSSL 3's `Public-Key: (256 bit)`.

- `x509-3.txt`, `x509-4.txt`: the lines the suites read from `x509 -text` of each certificate
  `tests/make-test-pki.sh` made, with Debian's OpenSSL 3.0.22 and with 4.0.0 built from source,
  in a throwaway Docker container (`version-3.txt`, `version-4.txt`). Set aside the times and
  `CN =` against `CN=`, and they differ in two things: each `Public-Key:` line, and the Subject Key
  Identifier, which 4.0.0 leaves out on the four leaves.
- `o4-*.summary.txt`: the two suites run in the Guix container with `OPENSSL` at a static
  4.0.0: the committed versions (`old-`) fail the Mac's two checks, and the fixed ones pass,
  288 and 201.
- `p256-key-text-mutants.txt`: three mutants of `p256-key-text`, each failing its test.
