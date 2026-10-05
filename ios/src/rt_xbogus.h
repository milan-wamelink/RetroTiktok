/* TikTok web "X-Bogus" request signature, computed on the device (no server). Some www.tiktok.com endpoints
 * (hashtag pages) answer with an empty body without it. Pure C so tools/ can test it on Linux. */
#ifndef RT_XBOGUS_H
#define RT_XBOGUS_H
#include <stddef.h>

/* query: the exact query string being sent (without '?'), ua: the exact User-Agent header, ts: unix seconds.
 * Writes a NUL-terminated 28-character signature to out (size >= 29). */
void rt_xbogus(const char *query, const char *ua, unsigned long ts, char out[29]);

#endif
