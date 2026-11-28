#!/usr/bin/env bash
# Makes sure the test-musl image (tools/ci_images/musl_test/) is on ghcr.io,
# building and pushing it when its recipe changed, and prints its name. In
# CI it also writes `image=<name>` to GITHUB_OUTPUT for the test-musl job.
# The registry check needs skopeo; pushing needs a ghcr.io login and
# CI_IMAGE_PUSH=true (tools/ci_image.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/ci_image.sh

recipe=tools/ci_images/musl_test
prepare_musl_test() { cp "$recipe/Containerfile" "$recipe/setup.sh" "$1/"; }

CI_IMAGE_CHECK_ONLY=true ci_image d6-musl-test "$(ci_image_hash "$recipe/Containerfile" "$recipe/setup.sh")" prepare_musl_test
echo "$CI_IMAGE"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "image=$CI_IMAGE" >> "$GITHUB_OUTPUT"; fi
