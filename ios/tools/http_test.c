/* Desktop test for src/rt_http.c: tools/http_test.sh builds it against the same mbedTLS as the app. */
#include "rt_http.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

static int to_file(void *ctx, const unsigned char *d, size_t n) { return fwrite(d, 1, n, (FILE *)ctx) == n ? 0 : 1; }

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: %s roots.pem url out [header-block]\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 2; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *pem = malloc((size_t)n); fread(pem, 1, (size_t)n, f); fclose(f);
    printf("roots: %d\n", rt_http_set_roots(pem, (size_t)n));
    FILE *out = fopen(argv[3], "wb");
    rt_http_result r;
    struct timeval a, b; gettimeofday(&a, NULL);
    int rc = rt_http_get(argv[2], argc > 4 ? argv[4] : NULL, 20000, 5, to_file, out, NULL, &r);
    gettimeofday(&b, NULL);
    fclose(out);
    printf("rc=%d status=%d bytes=%lld clen=%lld redirects=%d type=%s\ntls=%s\nerror=%s\ntime=%.2fs\n", rc, r.status, r.body_bytes,
           r.content_length, r.redirects, r.content_type, r.tls_info, r.error,
           (b.tv_sec - a.tv_sec) + (b.tv_usec - a.tv_usec) / 1e6);
    return rc == 0 ? 0 : 1;
}
