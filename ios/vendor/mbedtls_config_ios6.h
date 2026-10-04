/*
 * mbedTLS configuration for RetroTok on iOS 6 (armv7).
 *
 * tools/fetch_mbedtls.sh renames the stock include/mbedtls/mbedtls_config.h to mbedtls_config_default.h and
 * installs this file in its place, so we start from the upstream defaults and only trim:
 *   - TLS 1.2 client only (no TLS 1.3, DTLS or server side)
 *   - X.509 parsing only, no self tests
 *   - extra entropy from SecRandomCopyBytes and mbedtls_ms_time() from gettimeofday (clock_gettime is iOS 10+),
 *     both in vendor/mbedtls_glue.c
 */
#ifndef MBEDTLS_CONFIG_IOS6_H
#define MBEDTLS_CONFIG_IOS6_H

#include "mbedtls/mbedtls_config_default.h"

#undef MBEDTLS_SSL_PROTO_TLS1_3
#undef MBEDTLS_SSL_TLS1_3_COMPATIBILITY_MODE
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_ENABLED
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_ENABLED
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_EPHEMERAL_ENABLED
#undef MBEDTLS_SSL_EARLY_DATA

#undef MBEDTLS_SSL_PROTO_DTLS
#undef MBEDTLS_SSL_DTLS_ANTI_REPLAY
#undef MBEDTLS_SSL_DTLS_HELLO_VERIFY
#undef MBEDTLS_SSL_DTLS_SRTP
#undef MBEDTLS_SSL_DTLS_CLIENT_PORT_REUSE
#undef MBEDTLS_SSL_DTLS_CONNECTION_ID
#undef MBEDTLS_SSL_DTLS_CONNECTION_ID_COMPAT

#undef MBEDTLS_SSL_SRV_C
#undef MBEDTLS_SSL_COOKIE_C
#undef MBEDTLS_SSL_TICKET_C
#undef MBEDTLS_SSL_CACHE_C

#undef MBEDTLS_X509_CREATE_C
#undef MBEDTLS_X509_CRT_WRITE_C
#undef MBEDTLS_X509_CSR_WRITE_C
#undef MBEDTLS_X509_CSR_PARSE_C
#undef MBEDTLS_PK_WRITE_C
#undef MBEDTLS_PEM_WRITE_C

#undef MBEDTLS_SELF_TEST
#undef MBEDTLS_VERSION_FEATURES
#undef MBEDTLS_TIMING_C
#undef MBEDTLS_LMS_C
#undef MBEDTLS_LMS_PRIVATE
#undef MBEDTLS_PSA_CRYPTO_STORAGE_C
#undef MBEDTLS_PSA_ITS_FILE_C
#undef MBEDTLS_PSA_CRYPTO_SE_C

#define MBEDTLS_ENTROPY_HARDWARE_ALT
#define MBEDTLS_PLATFORM_MS_TIME_ALT
#define MBEDTLS_THREADING_C
#define MBEDTLS_THREADING_PTHREAD

#endif /* MBEDTLS_CONFIG_IOS6_H */
