#!/usr/bin/env bash
# Runs packaging/portable_tools_smoke.sh with the portable tools
# (tools/build_portable.sh) inside clean containers of several Linux
# distributions, to check the same static binaries work on each. Each
# container gets only what d6 expects of any host: CA certificates, plus curl
# and bash for facet and the new project's test.sh.
#
#   tools/test_portable_distros.sh [TOOLS_DIR]   default: build/portable/d6-linux-$(uname -m)
#
# PORTABLE_DISTROS overrides the image list (space separated).
# PORTABLE_SMOKE_OFFLINE=1 skips the checks that need the network.
#
# Stock Ubuntu, Debian and Alpine images lack some of those, so each runs as a
# seeded image with them already installed (tools/ci_images/portable_smoke/):
# ghcr.io/diamond-language/d6-portable-smoke:<distro>-<recipe hash>-ARCH,
# pulled, or built when missing (tools/ci_image.sh; CI_IMAGE_PUSH=true pushes
# it). So a run installs nothing from the distributions' mirrors.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/ci_image.sh
recipe=tools/ci_images/portable_smoke

# A build context whose Containerfile seeds $base.
prepare_smoke() {
    cp "$recipe/setup.sh" "$1/"
    printf '%s\n' "FROM $base" \
        "LABEL org.opencontainers.image.source=https://github.com/diamond-language/d6" \
        "COPY setup.sh /setup/" "RUN sh /setup/setup.sh && rm -rf /setup" > "$1/Containerfile"
}

tools="$(cd "${1:-build/portable/d6-linux-$(uname -m)}" && pwd)"
engine="$(command -v podman || command -v docker || true)"
if [[ -z "$engine" ]]; then
    echo "test_portable_distros: needs podman or docker" >&2
    exit 1
fi
images="${PORTABLE_DISTROS:-docker.io/library/ubuntu:26.04 \
docker.io/library/debian:12 docker.io/library/fedora:44 docker.io/library/archlinux:latest \
docker.io/library/alpine:3.23 docker.io/opensuse/leap:15.6}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

failed=0
for image in $images; do
    # Arch Linux publishes x86-64 images only.
    if [[ "$image" == *archlinux* && "$(uname -m)" != x86_64 ]]; then
        echo "skip $image (no $(uname -m) image)"
        continue
    fi
    # Debian-family and Alpine images ship without CA certificates or curl,
    # and Alpine without bash; the others already carry all three.
    run_image="$image"
    case "$image" in
        *ubuntu*|*debian*|*alpine*)
            base="$image"
            distro="$(basename "$image" | tr ':' '-')"
            key="$distro-$(printf '%s\n' "$base" | cat - "$recipe/setup.sh" | sha256sum | cut -c1-16)"
            if ! ci_image d6-portable-smoke "$key" prepare_smoke; then
                echo "FAIL $image (no seeded image)"
                failed=1
                continue
            fi
            run_image="$CI_IMAGE" ;;
    esac
    if "$engine" run --rm -v "$tools":/opt/d6:ro,Z \
        -v "$PWD/packaging/portable_smoke.d6":/smoke.d6:ro,Z \
        -v "$PWD/packaging/portable_tools_smoke.sh":/smoke.sh:ro,Z \
        -e PORTABLE_SMOKE_OFFLINE="${PORTABLE_SMOKE_OFFLINE:-}" \
        "$run_image" sh -c "PATH=/opt/d6:\$PATH sh /smoke.sh" > "$log" 2>&1; then
        echo "pass $image"
    else
        echo "FAIL $image"
        sed 's/^/    /' "$log" | tail -8
        failed=1
    fi
done
exit "$failed"
