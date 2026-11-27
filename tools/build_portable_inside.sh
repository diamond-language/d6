#!/bin/sh
# The container half of tools/build_portable.sh: builds the tools in the
# builder image (tools/ci_images/portable_builder/Containerfile), which already holds the
# packages and the static libraries in /opt. Runs as root.
set -eu

mkdir /work
tar -xf /in/source.tar -C /work
cd /work

# The baseline ISA: the binary has to run on any CPU of its architecture.
case "$ARCH" in
    x86_64) march="-march=x86-64" ;;
    *) march="" ;;
esac

# libpq's static archive needs its two helper archives; musl implements no
# ucontext, which libucontext supplies. facet, diamond-lsp and diamond-dap
# compile and link in one step with CFLAGS_DEBUG (as packaging/build.sh does),
# so their static flags ride there. Two runs, as there: `release` drives its
# own sub-make, which races with the tool targets in one parallel make.
static_libs="-L/opt/xcrypt/lib -L/opt/mariadb/lib/mariadb"
set -- CC=gcc \
    CPPFLAGS_EXTRA="-I/opt/xcrypt/include -I/opt/mariadb/include/mariadb" \
    LDFLAGS_EXTRA="-static $static_libs" \
    LDLIBS_EXTRA="-lpgcommon_shlib -lpgport_shlib -lucontext" \
    CFLAGS_DEBUG="-O2 -DNDEBUG $march -static $static_libs"
# A release tarball reports exactly its version, never a git revision (tools/version_suffix.sh).
export D6_VERSION_SUFFIX=
make -j"$JOBS" "$@" CFLAGS_RELEASE="-O3 -DNDEBUG $march" release
make -j"$JOBS" "$@" facet lsp dap

# One directory per architecture with the four tools under their installed
# names, and the same as a release tarball.
version="$(build/diamond --version | cut -d' ' -f2)"
dir="/out/d6-linux-$ARCH"
rm -rf "$dir"
mkdir -p "$dir"
cp build/diamond "$dir/d6"
cp build/facet "$dir/facet"
cp build/diamond-lsp "$dir/d6-lsp"
cp build/diamond-dap "$dir/d6-dap"
strip "$dir"/*
for tool in "$dir"/*; do
    if ! file "$tool" | grep -q "static"; then
        echo "build_portable: $tool is not statically linked" >&2
        exit 1
    fi
done
tar -czf "/out/d6-$version-linux-$ARCH.tar.gz" -C /out --owner=0 --group=0 "d6-linux-$ARCH"
