#include "rt_http.h"

#include "mbedtls/net_sockets.h"
#include "mbedtls/ssl.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/error.h"
#if defined(MBEDTLS_USE_PSA_CRYPTO) || defined(MBEDTLS_SSL_PROTO_TLS1_3)
#include "psa/crypto.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <pthread.h>
#include <sys/socket.h>

#define RT_HEADER_MAX 32768
#define RT_BUF_SIZE 16384

static mbedtls_x509_crt g_roots;
static int g_roots_ready;
static pthread_mutex_t g_roots_lock = PTHREAD_MUTEX_INITIALIZER;

int rt_http_set_roots(const char *pem, size_t len)
{
    pthread_mutex_lock(&g_roots_lock);
    if (g_roots_ready) mbedtls_x509_crt_free(&g_roots);
    mbedtls_x509_crt_init(&g_roots);
    /* mbedtls wants the terminating NUL included in the length of PEM input */
    char *copy = malloc(len + 1);
    int ret = -1;
    if (copy) {
        memcpy(copy, pem, len);
        copy[len] = 0;
        ret = mbedtls_x509_crt_parse(&g_roots, (const unsigned char *)copy, len + 1);
        free(copy);
    }
    int count = 0;
    for (mbedtls_x509_crt *c = &g_roots; c && c->raw.len; c = c->next) count++;
    g_roots_ready = count > 0;
    pthread_mutex_unlock(&g_roots_lock);
    return ret < 0 ? ret : count;
}

typedef struct {
    int tls;
    mbedtls_net_context net;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
    int timeout_ms;
    volatile int *cancel;
    unsigned char buf[RT_BUF_SIZE];
    size_t pos, len;
    int eof;
} rt_conn;

typedef struct {
    char scheme[8];
    char host[256];
    char port[8];
    char path[2048];
} rt_url;

static void set_err(rt_http_result *r, const char *what, int code)
{
    char tmp[160] = "";
    if (code) mbedtls_strerror(code, tmp, sizeof(tmp));
    snprintf(r->error, sizeof(r->error), "%s%s%s", what, code ? ": " : "", tmp);
}

static int parse_url(const char *url, rt_url *u)
{
    memset(u, 0, sizeof(*u));
    const char *p = strstr(url, "://");
    if (!p || p - url >= (long)sizeof(u->scheme)) return -1;
    memcpy(u->scheme, url, (size_t)(p - url));
    p += 3;
    const char *end = p + strcspn(p, "/?#");
    const char *colon = memchr(p, ':', (size_t)(end - p));
    const char *hostEnd = colon ? colon : end;
    if (hostEnd - p <= 0 || hostEnd - p >= (long)sizeof(u->host)) return -1;
    memcpy(u->host, p, (size_t)(hostEnd - p));
    if (colon && end - colon - 1 > 0 && end - colon - 1 < (long)sizeof(u->port))
        memcpy(u->port, colon + 1, (size_t)(end - colon - 1));
    else
        strcpy(u->port, strcasecmp(u->scheme, "https") == 0 ? "443" : "80");
    const char *frag = strchr(end, '#');
    size_t plen = frag ? (size_t)(frag - end) : strlen(end);
    if (plen == 0) { strcpy(u->path, "/"); return 0; }
    if (plen >= sizeof(u->path)) return -1;
    if (*end != '/') { u->path[0] = '/'; memcpy(u->path + 1, end, plen < sizeof(u->path) - 1 ? plen : sizeof(u->path) - 2); }
    else memcpy(u->path, end, plen);
    return 0;
}

static void conn_close(rt_conn *c)
{
    if (c->tls) {
        mbedtls_ssl_free(&c->ssl);
        mbedtls_ssl_config_free(&c->conf);
        mbedtls_ctr_drbg_free(&c->drbg);
        mbedtls_entropy_free(&c->entropy);
    }
    mbedtls_net_free(&c->net);
}

static int conn_open(rt_conn *c, const rt_url *u, rt_http_result *r)
{
    int ret;
    mbedtls_net_init(&c->net);
    c->tls = strcasecmp(u->scheme, "https") == 0;
    if ((ret = mbedtls_net_connect(&c->net, u->host, u->port, MBEDTLS_NET_PROTO_TCP)) != 0) {
        set_err(r, "connect failed", ret);
        mbedtls_net_free(&c->net);
        c->tls = 0;
        return -1;
    }
#ifdef SO_NOSIGPIPE
    int one = 1;
    setsockopt(c->net.fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    if (!c->tls) return 0;

    if (!g_roots_ready) { set_err(r, "no root certificates loaded", 0); c->tls = 0; mbedtls_net_free(&c->net); return -1; }
    mbedtls_ssl_init(&c->ssl);
    mbedtls_ssl_config_init(&c->conf);
    mbedtls_entropy_init(&c->entropy);
    mbedtls_ctr_drbg_init(&c->drbg);
    static const char pers[] = "retrotok";
    if ((ret = mbedtls_ctr_drbg_seed(&c->drbg, mbedtls_entropy_func, &c->entropy, (const unsigned char *)pers, sizeof(pers) - 1)) != 0) {
        set_err(r, "rng seed failed", ret); return -1;
    }
    if ((ret = mbedtls_ssl_config_defaults(&c->conf, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT)) != 0) {
        set_err(r, "tls config failed", ret); return -1;
    }
    mbedtls_ssl_conf_authmode(&c->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&c->conf, &g_roots, NULL);
    mbedtls_ssl_conf_rng(&c->conf, mbedtls_ctr_drbg_random, &c->drbg);
    mbedtls_ssl_conf_read_timeout(&c->conf, (uint32_t)c->timeout_ms);
    if ((ret = mbedtls_ssl_setup(&c->ssl, &c->conf)) != 0) { set_err(r, "tls setup failed", ret); return -1; }
    if ((ret = mbedtls_ssl_set_hostname(&c->ssl, u->host)) != 0) { set_err(r, "tls hostname failed", ret); return -1; }
    mbedtls_ssl_set_bio(&c->ssl, &c->net, mbedtls_net_send, NULL, mbedtls_net_recv_timeout);
    while ((ret = mbedtls_ssl_handshake(&c->ssl)) != 0) {
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        uint32_t flags = mbedtls_ssl_get_verify_result(&c->ssl);
        if (ret == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED && flags) {
            char info[200];
            mbedtls_x509_crt_verify_info(info, sizeof(info), "", flags);
            for (char *q = info; *q; q++) if (*q == '\n') *q = ' ';
            snprintf(r->error, sizeof(r->error), "certificate rejected for %s: %s", u->host, info);
        } else {
            set_err(r, "TLS handshake failed", ret);
        }
        return -1;
    }
    snprintf(r->tls_info, sizeof(r->tls_info), "%s %s", mbedtls_ssl_get_version(&c->ssl), mbedtls_ssl_get_ciphersuite(&c->ssl));
    return 0;
}

static int conn_write_all(rt_conn *c, const unsigned char *data, size_t len, rt_http_result *r)
{
    while (len) {
        int n = c->tls ? mbedtls_ssl_write(&c->ssl, data, len) : mbedtls_net_send(&c->net, data, len);
        if (n == MBEDTLS_ERR_SSL_WANT_READ || n == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (n <= 0) { set_err(r, "send failed", n); return -1; }
        data += n;
        len -= (size_t)n;
    }
    return 0;
}

/* Refill the buffer. Returns bytes read, 0 at EOF, < 0 on error. */
static int conn_fill(rt_conn *c, rt_http_result *r)
{
    if (c->eof) return 0;
    if (c->cancel && *c->cancel) { set_err(r, "cancelled", 0); return -1; }
    c->pos = 0;
    c->len = 0;
    for (;;) {
        int n = c->tls ? mbedtls_ssl_read(&c->ssl, c->buf, sizeof(c->buf))
                       : mbedtls_net_recv_timeout(&c->net, c->buf, sizeof(c->buf), (uint32_t)c->timeout_ms);
        if (n == MBEDTLS_ERR_SSL_WANT_READ || n == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
#ifdef MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET
        if (n == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET) continue;
#endif
        if (n == 0 || n == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY || n == MBEDTLS_ERR_NET_CONN_RESET) { c->eof = 1; return 0; }
        if (n == MBEDTLS_ERR_SSL_TIMEOUT) { set_err(r, "timed out", 0); return -1; }
        if (n < 0) { set_err(r, "receive failed", n); return -1; }
        c->len = (size_t)n;
        return n;
    }
}

/* Read one CRLF-terminated line (without CRLF). Returns length or < 0. */
static int conn_line(rt_conn *c, char *out, size_t cap, rt_http_result *r)
{
    size_t n = 0;
    for (;;) {
        if (c->pos >= c->len) {
            int f = conn_fill(c, r);
            if (f < 0) return -1;
            if (f == 0) { set_err(r, "connection closed early", 0); return -1; }
        }
        char ch = (char)c->buf[c->pos++];
        if (ch == '\n') {
            if (n && out[n - 1] == '\r') n--;
            out[n] = 0;
            return (int)n;
        }
        /* Overlong lines (e.g. TikTok's ~7 KB content-security-policy) are truncated, not fatal. */
        if (n + 1 < cap) out[n++] = ch;
    }
}

/* Pass `want` bytes (or everything until EOF when want < 0) to the sink. */
static int conn_body(rt_conn *c, long long want, rt_http_sink sink, void *ctx, rt_http_result *r)
{
    while (want != 0) {
        if (c->pos >= c->len) {
            int f = conn_fill(c, r);
            if (f < 0) return -1;
            if (f == 0) {
                if (want < 0) return 0;
                set_err(r, "connection closed before the body was complete", 0);
                return -1;
            }
        }
        size_t avail = c->len - c->pos;
        size_t take = (want > 0 && (long long)avail > want) ? (size_t)want : avail;
        if (sink && sink(ctx, c->buf + c->pos, take) != 0) { set_err(r, "cancelled", 0); return -1; }
        r->body_bytes += (long long)take;
        c->pos += take;
        if (want > 0) want -= (long long)take;
    }
    return 0;
}

static void resolve_location(const rt_url *base, const char *loc, char *out, size_t cap)
{
    if (strstr(loc, "://")) snprintf(out, cap, "%s", loc);
    else if (loc[0] == '/' && loc[1] == '/') snprintf(out, cap, "%s:%s", base->scheme, loc);
    else if (loc[0] == '/') snprintf(out, cap, "%s://%s:%s%s", base->scheme, base->host, base->port, loc);
    else {
        char dir[2048];
        snprintf(dir, sizeof(dir), "%s", base->path);
        char *q = strchr(dir, '?');
        if (q) *q = 0;
        char *slash = strrchr(dir, '/');
        if (slash) slash[1] = 0;
        snprintf(out, cap, "%s://%s:%s%s%s", base->scheme, base->host, base->port, dir, loc);
    }
}

int rt_http_get(const char *url, const char *extra_headers, int timeout_ms, int max_redirects,
                rt_http_sink sink, void *sink_ctx, volatile int *cancel, rt_http_result *r)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
#if defined(MBEDTLS_USE_PSA_CRYPTO) || defined(MBEDTLS_SSL_PROTO_TLS1_3)
    pthread_once(&once, (void (*)(void))psa_crypto_init);
#else
    (void)once;
#endif
    memset(r, 0, sizeof(*r));
    r->content_length = -1;
    char current[2048];
    snprintf(current, sizeof(current), "%s", url);

    for (int hop = 0;; hop++) {
        rt_url u;
        snprintf(r->final_url, sizeof(r->final_url), "%s", current);
        if (parse_url(current, &u) != 0) { snprintf(r->error, sizeof(r->error), "bad URL"); return -1; }

        rt_conn *c = calloc(1, sizeof(rt_conn));
        if (!c) { snprintf(r->error, sizeof(r->error), "out of memory"); return -1; }
        c->timeout_ms = timeout_ms > 0 ? timeout_ms : 20000;
        c->cancel = cancel;
        if (conn_open(c, &u, r) != 0) { conn_close(c); free(c); return -1; }

        char host_hdr[300];
        int default_port = (c->tls && !strcmp(u.port, "443")) || (!c->tls && !strcmp(u.port, "80"));
        if (default_port) snprintf(host_hdr, sizeof(host_hdr), "%s", u.host);
        else snprintf(host_hdr, sizeof(host_hdr), "%s:%s", u.host, u.port);
        size_t reqcap = strlen(u.path) + strlen(host_hdr) + (extra_headers ? strlen(extra_headers) : 0) + 256;
        char *req = malloc(reqcap);
        const char *extra = extra_headers ? extra_headers : "";
        size_t elen = strlen(extra);
        const char *extra_end = (elen && (elen < 2 || strcmp(extra + elen - 2, "\r\n") != 0)) ? "\r\n" : "";
        snprintf(req, reqcap, "GET %s HTTP/1.1\r\nHost: %s\r\nAccept-Encoding: identity\r\nConnection: close\r\n%s%s\r\n",
                 u.path, host_hdr, extra, extra_end);
        int ok = conn_write_all(c, (const unsigned char *)req, strlen(req), r) == 0;
        free(req);

        char line[4096];
        char location[2048] = "";
        int chunked = 0;
        long long clen = -1;
        if (ok) {
            /* status line, skipping interim 1xx responses */
            for (;;) {
                if (conn_line(c, line, sizeof(line), r) < 0) { ok = 0; break; }
                if (strncmp(line, "HTTP/", 5) != 0) { snprintf(r->error, sizeof(r->error), "not an HTTP response"); ok = 0; break; }
                const char *sp = strchr(line, ' ');
                r->status = sp ? atoi(sp + 1) : 0;
                size_t total = 0;
                int hok = 1;
                for (;;) {
                    int n = conn_line(c, line, sizeof(line), r);
                    if (n < 0) { hok = 0; break; }
                    if (n == 0) break;
                    total += (size_t)n;
                    if (total > RT_HEADER_MAX) { snprintf(r->error, sizeof(r->error), "headers too large"); hok = 0; break; }
                    char *colon = strchr(line, ':');
                    if (!colon) continue;
                    *colon = 0;
                    char *val = colon + 1;
                    while (*val == ' ' || *val == '\t') val++;
                    if (!strcasecmp(line, "Content-Length")) clen = atoll(val);
                    else if (!strcasecmp(line, "Transfer-Encoding") && strstr(val, "chunked")) chunked = 1;
                    else if (!strcasecmp(line, "Location")) snprintf(location, sizeof(location), "%s", val);
                    else if (!strcasecmp(line, "Content-Type")) snprintf(r->content_type, sizeof(r->content_type), "%s", val);
                }
                if (!hok) { ok = 0; break; }
                if (r->status >= 100 && r->status < 200) { chunked = 0; clen = -1; location[0] = 0; continue; }
                break;
            }
        }
        if (!ok) { conn_close(c); free(c); return -1; }

        int redirect = (r->status == 301 || r->status == 302 || r->status == 303 || r->status == 307 || r->status == 308) && location[0];
        if (redirect && hop < max_redirects) {
            conn_close(c);
            free(c);
            char next[2048];
            resolve_location(&u, location, next, sizeof(next));
            snprintf(current, sizeof(current), "%s", next);
            r->redirects++;
            r->content_type[0] = 0;
            continue;
        }

        r->content_length = chunked ? -1 : clen;
        int rc = 0;
        if (chunked) {
            for (;;) {
                if (conn_line(c, line, sizeof(line), r) < 0) { rc = -1; break; }
                long long size = strtoll(line, NULL, 16);
                if (size <= 0) break;
                if (conn_body(c, size, sink, sink_ctx, r) < 0) { rc = -1; break; }
                if (conn_line(c, line, sizeof(line), r) < 0) { rc = -1; break; }
            }
        } else if (clen >= 0) {
            rc = conn_body(c, clen, sink, sink_ctx, r);
        } else if (r->status != 204 && r->status != 304) {
            rc = conn_body(c, -1, sink, sink_ctx, r);
        }
        if (c->tls) mbedtls_ssl_close_notify(&c->ssl);
        conn_close(c);
        free(c);
        return rc;
    }
}
