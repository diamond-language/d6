#!/usr/bin/env bash
# Build the curated docs with the same runtime shipped in the package release.
set -euo pipefail

if [[ $# != 2 || ! $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: $0 vX.Y.Z RUNTIME_TARBALL" >&2
    exit 64
fi
version=${1#v}
archive=$(realpath "$2")
cd "$(dirname "$0")/.."
source_revision=$(git -c safe.directory="$PWD" rev-parse HEAD)
source_version=$(sed -n 's/.*DIAMOND_VERSION\[\] = "\(.*\)";/\1/p' src/main.c)
if [[ $source_version != "$version" ]]; then
    echo "site release tag $1 does not match src/main.c ($source_version)" >&2
    exit 1
fi
# Fail before compiling if the Getting Started examples still name old packages.
guide=docs/getting-started.md
if [[ $(grep -Ec "Downloads/d6-lang[-_]${version//./\\.}-1[_.]" "$guide") != 4 ||
      $(grep -Ec 'Downloads/d6-lang[-_]' "$guide") != 4 ]] ||
   ! grep -Fq "d6 --version     # d6 $version" "$guide"; then
    echo "update the package examples and d6 --version in $guide for $version" >&2
    exit 1
fi

runtime=$(mktemp -d)
mkdir -p build
site_build=$(mktemp -d build/site-docs.XXXXXXXX)
trap 'rm -rf "$runtime" "$site_build"' EXIT
tar -xzf "$archive" --strip-components=1 -C "$runtime"
test "$("$runtime/bin/d6" --version)" = "d6 $version"

# Build WASM first: the host compiler produces its embedded prelude. The docs
# then use the packaged runtime via a separate make target path.
make -j4 MINIMAL=1 build/compiled_prelude.bin
JOBS=4 make test-wasm
FACET_BIN="$runtime/bin/facet" bash tools/install_local_cuts.sh .
ln -s "$runtime/bin/d6" "$site_build/diamond"
DIAMOND_BIN="$runtime/bin/d6" make -o "$site_build/diamond" BUILD_DIR="$site_build" test-docs test-docsite

output="build/site-release-$version"
mkdir -p "$output"
tar -C "$site_build/docsite" -czf "$output/docs.tar.gz" .
cp build/wasm/diamond.wasm wasm/web/diamond-wasm.js "$output/"
printf '%s\n' "$version" > "$output/RELEASE"
printf '%s\n' "$source_revision" > "$output/RUNTIME_REVISION"
cp "$output/RUNTIME_REVISION" "$output/DOCS_REVISION"
(cd "$output" && sha256sum docs.tar.gz diamond.wasm diamond-wasm.js RELEASE RUNTIME_REVISION DOCS_REVISION > SHA256SUMS)
