#include "rt_xbogus.h"
#include "mbedtls/md5.h"
#include <stdlib.h>
#include <string.h>

static void rc4(const unsigned char *key, size_t klen, const unsigned char *in, size_t n, unsigned char *out)
{
    unsigned char s[256];
    unsigned i, j = 0;
    for (i = 0; i < 256; i++) s[i] = (unsigned char)i;
    for (i = 0; i < 256; i++) {
        j = (j + s[i] + key[i % klen]) & 255;
        unsigned char t = s[i]; s[i] = s[j]; s[j] = t;
    }
    i = j = 0;
    for (size_t k = 0; k < n; k++) {
        i = (i + 1) & 255;
        j = (j + s[i]) & 255;
        unsigned char t = s[i]; s[i] = s[j]; s[j] = t;
        out[k] = in[k] ^ s[(s[i] + s[j]) & 255];
    }
}

static void md5(const unsigned char *in, size_t n, unsigned char out[16]) { mbedtls_md5(in, n, out); }

static void md5x2(const unsigned char *in, size_t n, unsigned char out[16])
{
    unsigned char once[16];
    md5(in, n, once);
    md5(once, 16, out);
}

static size_t base64(const unsigned char *in, size_t n, char *out)
{
    static const char a[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t o = 0;
    for (size_t i = 0; i < n; i += 3) {
        unsigned v = (unsigned)in[i] << 16 | (i + 1 < n ? (unsigned)in[i + 1] << 8 : 0) | (i + 2 < n ? in[i + 2] : 0);
        out[o++] = a[v >> 18 & 63];
        out[o++] = a[v >> 12 & 63];
        out[o++] = i + 1 < n ? a[v >> 6 & 63] : '=';
        out[o++] = i + 2 < n ? a[v & 63] : '=';
    }
    return o;
}

void rt_xbogus(const char *query, const char *ua, unsigned long ts, char out[29])
{
    static const char alphabet[] = "Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe";
    static const unsigned char ua_key[3] = { 0, 1, 14 }, final_key[1] = { 255 };
    const unsigned long canvas = 536919696UL;
    unsigned char p[16], d[16], u[16];

    md5x2((const unsigned char *)query, strlen(query), p);
    md5x2((const unsigned char *)"", 0, d);

    size_t ualen = strlen(ua);
    unsigned char *enc = malloc(ualen + 1);
    char *b64 = malloc((ualen + 2) / 3 * 4 + 1);
    rc4(ua_key, 3, (const unsigned char *)ua, ualen, enc);
    md5((const unsigned char *)b64, base64(enc, ualen, b64), u);
    free(enc);
    free(b64);

    unsigned char a[19] = { 64, 0, 1, 14, p[14], p[15], d[14], d[15], u[14], u[15],
                            (unsigned char)(ts >> 24), (unsigned char)(ts >> 16), (unsigned char)(ts >> 8), (unsigned char)ts,
                            (unsigned char)(canvas >> 24), (unsigned char)(canvas >> 16), (unsigned char)(canvas >> 8),
                            (unsigned char)canvas, 0 };
    for (int i = 0; i < 18; i++) a[18] ^= a[i];

    unsigned char b[21] = { 2, 255 };
    rc4(final_key, 1, a, 19, b + 2);
    for (int i = 0, o = 0; i < 21; i += 3) {
        unsigned v = (unsigned)b[i] << 16 | (unsigned)b[i + 1] << 8 | b[i + 2];
        out[o++] = alphabet[v >> 18 & 63];
        out[o++] = alphabet[v >> 12 & 63];
        out[o++] = alphabet[v >> 6 & 63];
        out[o++] = alphabet[v & 63];
    }
    out[28] = 0;
}
