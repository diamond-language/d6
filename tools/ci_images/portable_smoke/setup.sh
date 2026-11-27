#!/bin/sh
# Adds what the portable smoke test needs to a stock distribution image
# (tools/test_portable_distros.sh): CA certificates and curl, and bash on
# Alpine. Runs once while each seeded image is built.
set -eu
if command -v apk >/dev/null; then
    apk add --no-cache -q ca-certificates curl bash
elif command -v apt-get >/dev/null; then
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl >/dev/null
    rm -rf /var/lib/apt/lists/*
else
    echo "portable_smoke setup: no apk or apt-get here" >&2
    exit 1
fi
