#!/usr/bin/env bash
# Publish a verified stable website artifact using the existing site operator SSH access.
set -euo pipefail

if [[ $# -lt 2 || ! $1 =~ ^(verify|deploy)$ || ( $1 == verify && $# != 2 ) || ( $1 == deploy && $# != 3 ) ]]; then
    echo "usage: $0 verify SITE_ARTIFACT | deploy SITE_ARTIFACT MARKETING_CHECKOUT" >&2
    exit 64
fi

mode=$1
artifact=$(realpath "$2")
(
    cd "$artifact"
    sha256sum docs.tar.gz diamond.wasm diamond-wasm.js RELEASE RUNTIME_REVISION DOCS_REVISION |
        cmp - SHA256SUMS
)
version=$(cat "$artifact/RELEASE")
runtime_revision=$(cat "$artifact/RUNTIME_REVISION")
docs_revision=$(cat "$artifact/DOCS_REVISION")
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! $runtime_revision =~ ^[0-9a-f]{40}$ || ! $docs_revision =~ ^[0-9a-f]{40}$ ]]; then
    echo "invalid site artifact revision metadata" >&2
    exit 1
fi

test "$(gh -R diamond-language/d6 release view --json tagName --jq .tagName)" = "v$version"

base=https://rolld6.codes
release_url="https://github.com/diamond-language/d6/releases/download/v$version"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

verify_homepage() {
    local home=$1 suffix
    grep -Fq " v$version · open source" "$home" || return
    for suffix in fc{44,45}.{x86_64,aarch64}; do
        grep -Fq "href=\"$release_url/d6-lang-$version-1.$suffix.rpm\"" "$home" || return
    done
    for suffix in amd64 arm64; do
        grep -Fq "href=\"$release_url/d6-lang_${version}-1_$suffix.deb\"" "$home" || return
    done
    test "$(grep -c 'https://github.com/diamond-language/d6/releases/download/.*d6-lang' "$home")" -eq 6
}

fetch() {
    curl -fsSL --retry 2 --max-time 30 "$base/$1" -o "$2"
}

verify_live() {
    local asset
    for asset in RELEASE RUNTIME_REVISION DOCS_REVISION; do
        fetch "$asset" "$tmp/$asset" && cmp "$artifact/$asset" "$tmp/$asset" || return
    done
    fetch '' "$tmp/index.html" && verify_homepage "$tmp/index.html" || return
    fetch docs/guide/getting-started.html "$tmp/guide.html" &&
        grep -Fq "d6-lang_${version}-1_amd64.deb" "$tmp/guide.html" || return
    fetch js/diamond-wasm.js "$tmp/diamond-wasm.js" &&
        cmp "$artifact/diamond-wasm.js" "$tmp/diamond-wasm.js" || return
    curl -fsS --retry 2 --max-time 30 -D "$tmp/wasm-headers" "$base/wasm/diamond.wasm" -o "$tmp/diamond.wasm" &&
        grep -Eiq '^content-type: application/wasm' "$tmp/wasm-headers" &&
        grep -Eiq '^cache-control: no-cache' "$tmp/wasm-headers" &&
        cmp "$artifact/diamond.wasm" "$tmp/diamond.wasm" || return
    grep -oE "https://github.com/diamond-language/d6/releases/download/[^\"]+" "$tmp/index.html" |
        grep -E '/d6-lang[-_]' |
        xargs -r -P 3 -I URL curl -fsSLI --retry 2 --max-time 30 -o /dev/null -w '%{http_code} %{url}\n' URL
}

if [[ $mode == verify ]]; then
    verify_live
    exit
fi

marketing=$(realpath "$3")
# Use the merged marketing commit so the exact loader and module passed its REPL tests.
test -z "$(git -C "$marketing" status --porcelain)"
test "$(git -C "$marketing" rev-parse HEAD)" = "$(git -C "$marketing" rev-parse origin/main)"
test "$(git -C "$(dirname "$0")/.." rev-parse "refs/tags/v$version^{commit}")" = "$runtime_revision"
test "$docs_revision" = "$runtime_revision"
verify_homepage "$marketing/index.html"
cmp "$artifact/diamond.wasm" "$marketing/wasm/diamond.wasm"
cmp "$artifact/diamond-wasm.js" "$marketing/js/diamond-wasm.js"
node --test "$marketing/tests/repl.test.mjs"

site="$tmp/site"
mkdir -p "$site/docs"
rsync -rc --exclude .git --exclude .github --exclude deploy --exclude tests --exclude tools --exclude /docs "$marketing/" "$site/"
tar -xzf "$artifact/docs.tar.gz" --no-same-owner -C "$site/docs"
install -m 644 "$artifact"/{RELEASE,RUNTIME_REVISION,DOCS_REVISION} "$site/"
git -C "$marketing" rev-parse HEAD > "$site/REVISION"

host=root@rolld6.codes
live=/var/www/rolld6.codes
remote=(ssh -4 -o BatchMode=yes "$host")
lock=/var/www/.d6-site-release.lock
"${remote[@]}" mkdir "$lock"
trap '"${remote[@]}" rmdir "$lock"; rm -rf "$tmp"' EXIT
stage=$("${remote[@]}" mktemp -d /var/www/.d6-site-"$version".XXXXXXXX)
[[ $stage == /var/www/.d6-site-"$version".???????? ]]
"${remote[@]}" cp -a "$live/." "$stage/"
"${remote[@]}" chmod 755 "$stage"
rsync -4 -rcni --exclude /docs "$site/" "$host:$live/"
rsync -4 -rcni --delete "$site/docs/" "$host:$live/docs/"
rsync -4 -rc --chown=root:root --chmod=D755,F644 --exclude /docs "$site/" "$host:$stage/"
rsync -4 -rc --delete --chown=root:root --chmod=D755,F644 "$site/docs/" "$host:$stage/docs/"
backup=$("${remote[@]}" mktemp -d /root/d6-"$version"-rollback.XXXXXXXX)
# An atomic directory exchange preserves the old site and avoids a gap in service.
"${remote[@]}" mv --exchange --no-copy -T "$stage" "$live"
if ! verify_live; then
    "${remote[@]}" mv --exchange --no-copy -T "$stage" "$live"
    echo "Site verification failed. Restored the previous site." >&2
    exit 1
fi
"${remote[@]}" mv -T "$stage" "$backup/original-site"
printf 'Published d6 %s. Previous site retained at %s/original-site\n' "$version" "$backup"
