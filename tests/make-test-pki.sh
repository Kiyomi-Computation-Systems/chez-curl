#!/bin/sh
# tests/make-test-pki.sh: the test origin's TLS material, made per run with
# the openssl command line, so nothing in the repository can expire (ADR-0005;
# M1 plan, section 8).
#
#   tests/make-test-pki.sh DIR
#
# DIR must be an existing, empty directory, named by an absolute or a relative
# path. On success it holds exactly these ten files, nothing is written to
# stdout or stderr, and the exit status is 0:
#
#   ca.pem                       the run CA, the one a suite trusts
#   other-ca.pem                 a second CA, never trusted
#   good.pem, good.key           for localhost, 127.0.0.1 and ::1, by the run CA
#   expired.pem, expired.key     as good, valid only 2000-01-01 to 2000-01-02
#   wrong-host.pem, wrong-host.key
#                                for wrong-host.invalid only, by the run CA
#   untrusted.pem, untrusted.key as good, but signed by the second CA
#
# Each failing leaf has one fault the good one lacks: its dates, its names, or
# its issuer. Every leaf has the same subject, CN=chez-curl test leaf, which
# names no host, so a verifier that falls back to the CN matches none. The keys
# are EC P-256, the signatures ECDSA with SHA-256. The CAs and every leaf but
# the expired one are valid for two days from now. A self-signed leaf would
# give OpenSSL error 18 and LibreSSL 20, so the untrusted leaf has an issuer
# instead, one that is never trusted.
#
# It runs $OPENSSL, else openssl. The same commands were measured on OpenSSL
# 3.5.7, 3.0.13 and 3.0.11, and on LibreSSL 3.3.6, the Mac's /usr/bin/openssl
# (2026-10-18). LibreSSL's req takes a subject from the config's
# distinguished_name section over -subj when the config says prompt = no, so
# that section is empty here and every subject comes from -subj.
#
# A wrong argument exits 2. A failing openssl command exits 1, with what
# openssl wrote on stderr; DIR may then hold some of the files, and the caller
# removes it.

set -eu

usage() {
  echo "make-test-pki: $1" >&2
  echo "usage: tests/make-test-pki.sh DIR, where DIR is an existing, empty directory" >&2
  exit 2
}

[ $# -eq 1 ] || usage "it takes 1 argument, and was given $#"
dir=$1
[ -d "$dir" ] || usage "$dir is not a directory"
[ -z "$(ls -A "$dir")" ] || usage "$dir is not empty"

openssl=${OPENSSL:-openssl}

# DIR as an absolute path: the script works in work/ below it, and its exit
# trap, which runs there, must still find work/ by name.
dir=$(CDPATH= cd -- "$dir" && pwd)

# The CA keys, the config, the requests and openssl ca's database live in
# work/, which goes on any exit.
work=$dir/work
mkdir "$work"
trap 'rm -rf "$work"' EXIT
cd "$work"

# run: a command, its output kept in log; on failure, the log goes to stderr.
run() {
  if ! "$@" >> log 2>&1; then
    echo "make-test-pki: failed: $*" >&2
    cat log >&2
    exit 1
  fi
}

cat > pki.cnf <<'CONFIG'
[req]
distinguished_name = dn
[dn]

[ca_ext]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash

[good_ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost,IP:127.0.0.1,IP:::1
authorityKeyIdentifier = keyid

[wrong_ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:wrong-host.invalid
authorityKeyIdentifier = keyid

# openssl ca's settings for each CA, picked by -name.
[ca_issuer]
database = ca.index
serial = ca.serial
new_certs_dir = .
default_md = sha256
policy = any
unique_subject = no
copy_extensions = none

[other-ca_issuer]
database = other-ca.index
serial = other-ca.serial
new_certs_dir = .
default_md = sha256
policy = any
unique_subject = no
copy_extensions = none

[any]
commonName = supplied
CONFIG

key() {
  run "$openssl" ecparam -name prime256v1 -genkey -noout -out "$1"
}

# ca NAME CN: a CA's key and self-signed certificate, and the database and
# serial its section of pki.cnf names, so each CA numbers its own leaves.
ca() {
  key "$1.key"
  run "$openssl" req -new -x509 -key "$1.key" -sha256 -days 2 -subj "/CN=$2" \
    -config pki.cnf -extensions ca_ext -out "../$1.pem"
  : > "$1.index"
  echo 01 > "$1.serial"
}

# leaf NAME CA EXTENSIONS VALIDITY...: a key, and a certificate CA signs, with
# the given extensions and validity.
leaf() {
  name=$1 issuer=$2 extensions=$3
  shift 3
  key "../$name.key"
  run "$openssl" req -new -key "../$name.key" -subj "/CN=chez-curl test leaf" -config pki.cnf -out "$name.csr"
  run "$openssl" ca -batch -config pki.cnf -name "${issuer}_issuer" -cert "../$issuer.pem" \
    -keyfile "$issuer.key" -in "$name.csr" "$@" -extfile pki.cnf -extensions "$extensions" \
    -notext -out "../$name.pem"
}

ca ca "chez-curl test CA"
ca other-ca "chez-curl untrusted CA"
leaf good ca good_ext -days 2
leaf expired ca good_ext -startdate 20000101000000Z -enddate 20000102000000Z
leaf wrong-host ca wrong_ext -days 2
leaf untrusted other-ca good_ext -days 2
