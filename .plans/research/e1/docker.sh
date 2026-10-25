#!/bin/sh
# Spike E1's Docker lanes. Run on the host, from the repository's root, after
# `make deps`:
#
#   sh .plans/research/e1/docker.sh [SET...]
#
# SET is one of run.sh's sets; with none, every set it runs in Docker.
# It starts ubuntu:24.04 with the repository at /src and at its own path,
# and the Guix store read-only, and runs in-docker.sh there. That builds, or reuses from
# build/e1/ci, the floors' Chez and libcurl through scripts/ci, as CI does,
# then stalls every name lookup and runs run.sh on each lane:
#   floor           libcurl at its floor, built from source with OpenSSL
#   ubuntu-openssl  Ubuntu's libcurl4t64
#   ubuntu-gnutls   Ubuntu's libcurl3t64-gnutls
#   guix-store      the container's libcurl and Chez, from the store, for
#                   the lookups the container cannot stall
# The first three run under the floor's Chez; the test origin runs on the
# container's Node, from the store. Prints the image's id first.
set -eu
[ -f .plans/research/e1/in-docker.sh ] || { echo "docker.sh: run it from the repository's root" >&2; exit 2; }
docker image inspect ubuntu:24.04 --format 'image ubuntu:24.04 {{.Id}}'
guix=$(scripts/guix-env sh -c 'printf "%s\n%s\n%s\n" "$CHEZ" "$CHEZ_CURL_LIBCURL" "$(command -v node)"')
guix_chez=$(printf '%s\n' "$guix" | sed -n 1p)
guix_libcurl=$(printf '%s\n' "$guix" | sed -n 2p)
guix_node=$(printf '%s\n' "$guix" | sed -n 3p)
for p in "$guix_chez" "$guix_libcurl" "$guix_node"; do
  case $p in /gnu/store/*) ;; *) echo "docker.sh: not in the store: '$p'" >&2; exit 1 ;; esac
done
# The repository is mounted twice: at /src, where the floors' builds live,
# and at its own path, which make deps's links into vendor/ name.
root=$PWD
exec docker run --rm -v "$root:/src" -v "$root:$root" -v /gnu/store:/gnu/store:ro \
  -e GUIX_CHEZ="$guix_chez" -e GUIX_LIBCURL="$guix_libcurl" -e GUIX_NODE="$guix_node" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  ubuntu:24.04 sh /src/.plans/research/e1/in-docker.sh "$@"
