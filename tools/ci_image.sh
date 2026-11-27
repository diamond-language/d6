# Prebuilt CI images on ghcr.io, so CI jobs don't install from package
# mirrors on every run. Source this file, then:
#
#   ci_image NAME KEY PREPARE
#
# sets CI_IMAGE to ghcr.io/diamond-language/NAME:KEY-ARCH (ARCH from
# uname -m) and makes sure the image is there: present locally, pulled, or
# else built. PREPARE is a function that fills the empty build context
# directory it is given with a Containerfile and whatever that copies. It
# runs only when the image is built, so only then are packages and sources
# downloaded. KEY should hash everything the image is built from, so a
# changed recipe gets a new image.
#
# CI_IMAGE_PUSH=true pushes an image after building it (CI does this, except
# for pull requests from forks). CI_IMAGE_CHECK_ONLY=true only checks that the
# registry has the image, without pulling it, and builds and pushes it when
# the registry lacks it.

# A short hash of the files given, for a KEY.
ci_image_hash() {
    cat "$@" | sha256sum | cut -c1-16
}

ci_image() {
    local name=$1 key=$2 prepare=$3 engine context attempt
    engine="$(command -v podman || command -v docker || true)"
    if [[ -z "$engine" ]]; then
        echo "ci_image: needs podman or docker" >&2
        return 1
    fi
    CI_IMAGE="ghcr.io/diamond-language/$name:$key-$(uname -m)"
    if [[ "${CI_IMAGE_CHECK_ONLY:-}" == true ]]; then
        if skopeo inspect --raw "docker://$CI_IMAGE" >/dev/null 2>&1; then return 0; fi
    elif "$engine" image inspect "$CI_IMAGE" >/dev/null 2>&1 ||
        "$engine" pull -q "$CI_IMAGE" >/dev/null 2>&1; then
        return 0
    fi
    echo "ci_image: no $CI_IMAGE yet; building it" >&2
    context="$(mktemp -d)"
    if ! "$prepare" "$context" ||
        ! "$engine" build -q -t "$CI_IMAGE" -f "$context/Containerfile" "$context" >/dev/null; then
        rm -rf "$context"
        echo "ci_image: building $CI_IMAGE failed" >&2
        return 1
    fi
    rm -rf "$context"
    if [[ "${CI_IMAGE_PUSH:-}" == true ]]; then
        for attempt in 1 2 3; do
            if "$engine" push -q "$CI_IMAGE"; then return 0; fi
            sleep 10
        done
        echo "ci_image: could not push $CI_IMAGE" >&2
        [[ "${CI_IMAGE_CHECK_ONLY:-}" != true ]] || return 1
    elif [[ "${CI_IMAGE_CHECK_ONLY:-}" == true ]]; then
        echo "ci_image: $CI_IMAGE is built here but can't be pushed (CI_IMAGE_PUSH is not true)" >&2
        return 1
    fi
}
