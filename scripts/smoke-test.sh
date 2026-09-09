#!/usr/bin/env bash
#
# Smoke test one built RNP runtime image: confirm the crypto backend it
# reports, then generate a key and sign and verify a file with it.
#
#   scripts/smoke-test.sh IMAGE EXPECTED_BACKEND [EXPECTED_BACKEND_VERSION]
#
# EXPECTED_BACKEND is the name RNP prints, so OpenSSL or Botan. The version
# is optional and only checked when given.

set -euo pipefail

image=${1:?usage: smoke-test.sh IMAGE EXPECTED_BACKEND [EXPECTED_BACKEND_VERSION]}
expected_backend=${2:?missing expected backend}
expected_version=${3:-}

passphrase='smoke test passphrase'
volume="rnp-smoke-$$"
workdir=$(mktemp -d)

cleanup() {
    rm -rf "$workdir"
    docker volume rm -f "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The image runs as an unprivileged user whose uid need not match the caller's,
# so the bind mount has to be writable by anyone.
chmod 777 "$workdir"

echo "== version =="
version_output=$(docker run --rm "$image" --version 2>&1)
echo "$version_output"

backend=$(awk -F': ' '/^Backend:/        {print $2; exit}' <<<"$version_output")
version=$(awk -F': ' '/^Backend version:/ {print $2; exit}' <<<"$version_output")

if [ "$backend" != "$expected_backend" ]; then
    echo "FAIL: expected backend '$expected_backend', got '$backend'" >&2
    exit 1
fi

if [ -n "$expected_version" ] && [ "$version" != "$expected_version" ]; then
    echo "FAIL: expected backend version '$expected_version', got '$version'" >&2
    exit 1
fi

docker volume create "$volume" >/dev/null
echo "the quick brown fox" > "$workdir/message.txt"

echo "== generate key =="
docker run --rm -v "$volume:/home/rnp/.rnp" --entrypoint rnpkeys "$image" \
    --generate-key --userid "Smoke Test <smoke@example.com>" --password "$passphrase"

echo "== clearsign =="
docker run --rm -v "$volume:/home/rnp/.rnp" -v "$workdir:/data" -w /data "$image" \
    --clearsign message.txt --password "$passphrase"

if [ ! -s "$workdir/message.txt.asc" ]; then
    echo "FAIL: clearsign produced no output on the bind mount" >&2
    exit 1
fi

echo "== verify =="
verify_output=$(docker run --rm -v "$volume:/home/rnp/.rnp" -v "$workdir:/data" -w /data \
    "$image" --verify message.txt.asc 2>&1)
echo "$verify_output"

if ! grep -q 'Signature(s) verified successfully' <<<"$verify_output"; then
    echo "FAIL: signature did not verify" >&2
    exit 1
fi

echo "== verify rejects a tampered file =="
sed 's/quick brown fox/quick brown cat/' "$workdir/message.txt.asc" > "$workdir/tampered.asc"

if docker run --rm -v "$volume:/home/rnp/.rnp" -v "$workdir:/data" -w /data \
        "$image" --verify tampered.asc >/dev/null 2>&1; then
    echo "FAIL: a tampered signature was accepted" >&2
    exit 1
fi

echo "PASS: $image, backend $backend $version"
