#!/bin/sh
# Runs once while the test-musl image is built (Containerfile here).
set -eu
apk add --no-cache gcc musl-dev make git diffutils findutils \
    ripgrep bc netcat-openbsd openssl openssl-dev sqlite-dev \
    libpq-dev mariadb-connector-c-dev zlib-dev libucontext \
    libucontext-dev tzdata bash coreutils procps sed gawk >/dev/null
