#!/bin/sh
# Builds tools/http_test (desktop) from src/rt_http.c and the vendored mbedTLS, for testing the app's network core.
set -e
cd "$(dirname "$0")/.."
./tools/fetch_mbedtls.sh >/dev/null
mkdir -p obj/http_test
for s in vendor/mbedtls/library/*.c vendor/mbedtls_glue.c src/rt_http.c; do
  o=obj/http_test/$(basename "$s" .c).o
  [ "$o" -nt "$s" ] || cc -O2 -w -Ivendor/mbedtls/include -Ivendor/mbedtls/library -Isrc -c "$s" -o "$o"
done
cc -O2 -Isrc tools/http_test.c obj/http_test/*.o -lpthread -o obj/http_test/http_test
echo obj/http_test/http_test
