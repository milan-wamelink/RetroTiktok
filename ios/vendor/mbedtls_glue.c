/*
 * Platform glue for mbedTLS on iOS 6.
 *  - mbedtls_ms_time(): upstream uses clock_gettime(), which only exists on iOS 10+.
 *  - mbedtls_hardware_poll(): extra entropy from SecRandomCopyBytes() (getrandom() in the Linux test build).
 */
#include "mbedtls/build_info.h"
#include "mbedtls/platform_time.h"
#include "mbedtls/entropy.h"

#include <sys/time.h>
#include <stddef.h>
#if defined(__APPLE__)
#include <Security/SecRandom.h>
#else
#include <sys/random.h>
#endif

#if defined(MBEDTLS_PLATFORM_MS_TIME_ALT)
mbedtls_ms_time_t mbedtls_ms_time(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (mbedtls_ms_time_t)tv.tv_sec * 1000 + (mbedtls_ms_time_t)(tv.tv_usec / 1000);
}
#endif

#if defined(MBEDTLS_ENTROPY_HARDWARE_ALT)
int mbedtls_hardware_poll(void *data, unsigned char *output, size_t len, size_t *olen)
{
    (void)data;
    *olen = 0;
    if (len == 0) return 0;
#if defined(__APPLE__)
    if (SecRandomCopyBytes(kSecRandomDefault, len, output) != 0) return MBEDTLS_ERR_ENTROPY_SOURCE_FAILED;
#else
    if (getrandom(output, len, 0) != (ssize_t)len) return MBEDTLS_ERR_ENTROPY_SOURCE_FAILED;
#endif
    *olen = len;
    return 0;
}
#endif
