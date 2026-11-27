#!/bin/sh
# Runs once while the builder image is built (tools/ci_images/portable_builder/Containerfile).
# build_portable.sh downloads the two source releases and checks them
# against the checksums here before the image build starts.
set -eu
jobs="$(nproc)"

apk add --no-cache bash make gcc musl-dev linux-headers git \
    openssl-dev openssl-libs-static sqlite-dev sqlite-static zlib-dev zlib-static \
    libpq-dev libucontext-dev libgcc file tar perl xz cmake >/dev/null

# musl's crypt() has no bcrypt and Alpine packages no libxcrypt, so build
# libxcrypt's static library from a pinned, checksummed release (its
# configure needs Perl; nothing of it reaches the binary but libcrypt.a).
xcrypt_version=4.5.2
xcrypt_sha256=71513a31c01a428bccd5367a32fd95f115d6dac50fb5b60c779d5c7942aec071
echo "$xcrypt_sha256  /setup/xcrypt.tar.xz" | sha256sum -c - >/dev/null
mkdir /tmp/xcrypt
tar -xJf /setup/xcrypt.tar.xz -C /tmp/xcrypt --strip-components=1
(cd /tmp/xcrypt && ./configure --quiet --prefix=/opt/xcrypt --disable-shared --enable-static \
    --disable-obsolete-api && make -j"$jobs" >/dev/null && make install >/dev/null)

# Alpine ships MariaDB Connector/C only as a shared library, so build its
# static one from a pinned, checksummed release. The authentication plugins
# a server may ask for are linked in (a static binary cannot dlopen them):
# MySQL 8's caching_sha2_password and sha256_password, MariaDB's ed25519,
# parsec and dialog; Kerberos (GSSAPI) and remote_io stay out.
mariadb_version=3.4.11
mariadb_sha256=521c0712e9291fa96558df9e2ff431376a3a79329f13751896b694cae12765b4
echo "$mariadb_sha256  /setup/mariadb.tar.gz" | sha256sum -c - >/dev/null
mkdir /tmp/mariadb
tar -xzf /setup/mariadb.tar.gz -C /tmp/mariadb --strip-components=1
cmake -S /tmp/mariadb -B /tmp/mariadb/build -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/mariadb -DWITH_UNIT_TESTS=OFF -DWITH_CURL=OFF \
    -DWITH_SSL=OPENSSL -DWITH_EXTERNAL_ZLIB=ON \
    -DCLIENT_PLUGIN_CACHING_SHA2_PASSWORD=STATIC -DCLIENT_PLUGIN_SHA256_PASSWORD=STATIC \
    -DCLIENT_PLUGIN_CLIENT_ED25519=STATIC -DCLIENT_PLUGIN_PARSEC=STATIC \
    -DCLIENT_PLUGIN_DIALOG=STATIC -DCLIENT_PLUGIN_MYSQL_CLEAR_PASSWORD=STATIC \
    -DCLIENT_PLUGIN_AUTH_GSSAPI_CLIENT=OFF -DCLIENT_PLUGIN_REMOTE_IO=OFF \
    -DCLIENT_PLUGIN_ZSTD=OFF >/dev/null
cmake --build /tmp/mariadb/build -j"$jobs" >/dev/null
cmake --install /tmp/mariadb/build >/dev/null

rm -rf /tmp/xcrypt /tmp/mariadb
