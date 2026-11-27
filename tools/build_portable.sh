#!/usr/bin/env bash
# Builds a portable d6: fully static (musl) executables of d6, facet, d6-lsp
# and d6-dap, per CPU architecture, that run on any Linux distribution with no
# dependency on the machine's libc, OpenSSL, SQLite, libpq, MariaDB client or zlib. It builds inside an Alpine
# container from the tracked files of this working tree (uncommitted edits
# included), so the host's build/ is left alone.
#
# The container is the builder image (tools/portable/Containerfile), tagged
# ghcr.io/diamond-language/d6-portable-builder:<recipe hash>-ARCH. The script
# pulls it, or builds it when no image has that tag yet, which is the only
# time it downloads packages and source releases. PORTABLE_BUILDER_PUSH=true
# pushes a freshly built image (CI does), and PORTABLE_BUILDER names another
# image to build in.
#
#   tools/build_portable.sh [OUTPUT_DIR]     default: build/portable
#
# Needs podman or docker. Writes OUTPUT_DIR/d6-linux-ARCH/ (ARCH from uname -m)
# holding d6, facet, d6-lsp and d6-dap, and the same as
# OUTPUT_DIR/d6-VERSION-linux-ARCH.tar.gz, the file a release attaches.
# Static glibc is not an option: its name-service lookups load shared
# libraries at run time (see docs/deployment.md).
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:-build/portable}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
arch="$(uname -m)"
engine="$(command -v podman || command -v docker || true)"
if [[ -z "$engine" ]]; then
    echo "build_portable: needs podman or docker" >&2
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Builds the builder image: downloads the two pinned source releases (with
# retries; setup.sh checks their checksums) and runs the Containerfile.
build_builder() {
    local context="$work/image" setup=tools/portable/setup.sh
    mkdir "$context"
    cp tools/portable/Containerfile "$setup" "$context/"
    local xcrypt_version xcrypt_sha256 mariadb_version
    xcrypt_version="$(sed -n "s/^xcrypt_version=//p" "$setup")"
    xcrypt_sha256="$(sed -n "s/^xcrypt_sha256=//p" "$setup")"
    mariadb_version="$(sed -n "s/^mariadb_version=//p" "$setup")"
    # GitHub release downloads need retries and an API fallback (tools/fetch_release_asset.sh).
    sh tools/fetch_release_asset.sh besser82/libxcrypt "v$xcrypt_version" \
        "libxcrypt-$xcrypt_version.tar.xz" "$context/xcrypt.tar.xz" "$xcrypt_sha256"
    curl -fsSL --retry 6 --retry-all-errors --retry-delay 10 -o "$context/mariadb.tar.gz" \
        "https://archive.mariadb.org/connector-c-$mariadb_version/mariadb-connector-c-$mariadb_version-src.tar.gz"
    "$engine" build -q -t "$builder" -f "$context/Containerfile" "$context" >/dev/null
    if [[ "${PORTABLE_BUILDER_PUSH:-}" == true ]]; then
        local attempt
        for attempt in 1 2 3; do
            if "$engine" push -q "$builder"; then return 0; fi
            sleep 10
        done
        echo "build_portable: could not push $builder; building anyway" >&2
    fi
}

builder="${PORTABLE_BUILDER:-}"
if [[ -z "$builder" ]]; then
    recipe="$(cat tools/portable/Containerfile tools/portable/setup.sh | sha256sum | cut -c1-16)"
    builder="ghcr.io/diamond-language/d6-portable-builder:$recipe-$arch"
    if ! "$engine" image inspect "$builder" >/dev/null 2>&1 &&
        ! "$engine" pull -q "$builder" >/dev/null 2>&1; then
        echo "build_portable: no $builder yet; building it"
        build_builder
    fi
fi

git ls-files -z | tar --null -T - -cf "$work/source.tar"
cp tools/build_portable_inside.sh "$work/inside.sh"
"$engine" run --rm -v "$work":/in:Z -v "$out":/out:Z -e ARCH="$arch" \
    -e JOBS="${JOBS:-10}" "$builder" sh /in/inside.sh
echo "build_portable: wrote $out/d6-linux-$arch/ and its tarball"
