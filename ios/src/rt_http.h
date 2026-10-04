/*
 * Minimal blocking HTTP/1.1 client with TLS 1.2 from the bundled mbedTLS. Plain C so the exact same code can be
 * tested on a desktop (tools/http_test.c). Supports http/https, redirects, chunked and Content-Length bodies,
 * streaming the body to a callback. One request per connection (Connection: close).
 */
#ifndef RT_HTTP_H
#define RT_HTTP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Body sink: return 0 to continue, non-zero to abort the transfer. */
typedef int (*rt_http_sink)(void *ctx, const unsigned char *data, size_t len);

typedef struct {
    int status;                   /* final HTTP status, 0 when no response */
    long long content_length;     /* -1 when unknown */
    long long body_bytes;         /* bytes passed to the sink */
    int redirects;
    char content_type[128];
    char final_url[2048];
    char tls_info[160];           /* "TLSv1.2 TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384" for the last https hop */
    char error[256];
} rt_http_result;

/* Parse the PEM bundle of trusted roots. Call once before any https request. Returns number of roots or < 0. */
int rt_http_set_roots(const char *pem, size_t len);

/*
 * GET url. extra_headers: NULL or "Name: value\r\n..." block. cancel: optional flag checked between reads.
 * Returns 0 on a complete response (any status), < 0 on network/TLS errors (see result->error).
 */
int rt_http_get(const char *url, const char *extra_headers, int timeout_ms, int max_redirects,
                rt_http_sink sink, void *sink_ctx, volatile int *cancel, rt_http_result *result);

#ifdef __cplusplus
}
#endif

#endif
