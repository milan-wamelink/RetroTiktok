/* Prints rt_xbogus(query, ua, ts) so it can be compared with a reference implementation. */
#include "rt_xbogus.h"
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: %s query ua ts\n", argv[0]); return 2; }
    char out[29];
    rt_xbogus(argv[1], argv[2], strtoul(argv[3], NULL, 10), out);
    puts(out);
    return 0;
}
