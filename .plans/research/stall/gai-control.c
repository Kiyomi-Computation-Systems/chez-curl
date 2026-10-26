/* M3 slice 3: the Mac probe's positive control (ADR-0019, amended
 * 2026-10-25). run.sh compiles it and runs it under the stand-in: an
 * ordinary program's own getaddrinfo call on NAME, timed. Under the
 * stand-in it takes STALL_MS and answers EAI_NONAME. If it does and
 * lookup.sps's libcurl lookups do not stall, interposition works but does
 * not reach Apple's libcurl, or that libcurl does not resolve through
 * getaddrinfo. A call from Chez proves nothing: Chez finds an entry through
 * libcurl's own dependencies, which on Linux skip LD_PRELOAD.
 *
 *   gai-control NAME */
#include <netdb.h>
#include <stdio.h>
#include <time.h>

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: gai-control NAME\n");
    return 2;
  }
  struct timespec t0, t1;
  struct addrinfo *res = NULL;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  int code = getaddrinfo(argv[1], NULL, NULL, &res);
  clock_gettime(CLOCK_MONOTONIC, &t1);
  if (res) freeaddrinfo(res);
  long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000);
  printf("gai-control: getaddrinfo(\"%s\") answered %d after %ld ms\n", argv[1], code, ms);
  return 0;
}
