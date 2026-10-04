#!/bin/sh
# Downloads mbedTLS into ios/vendor/mbedtls and installs the iOS 6 config. Run once before `make`.
set -e
VERSION="${MBEDTLS_VERSION:-3.6.7}"
cd "$(dirname "$0")/../vendor"
if [ -f mbedtls/.retrotok-$VERSION ]; then echo "mbedTLS $VERSION already present"; exit 0; fi
rm -rf mbedtls && mkdir mbedtls
curl -sSfL "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$VERSION/mbedtls-$VERSION.tar.bz2" | tar -xj -C mbedtls --strip-components=1
mv mbedtls/include/mbedtls/mbedtls_config.h mbedtls/include/mbedtls/mbedtls_config_default.h
cp mbedtls_config_ios6.h mbedtls/include/mbedtls/mbedtls_config.h
touch mbedtls/.retrotok-$VERSION
echo "mbedTLS $VERSION: $(ls mbedtls/library/*.c | wc -l) sources"
