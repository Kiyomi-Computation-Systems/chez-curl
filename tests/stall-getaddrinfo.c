/* tests/stall-getaddrinfo.c: a stand-in getaddrinfo that stalls the names
 * ending in one suffix (ADR-0019, amended 2026-10-25; M3 plan, section 6).
 *
 * tests/test-engine.sps compiles it at test time as a shared object, and
 * loads it with LD_PRELOAD into a child Chez, tests/engine-stall.sps, so a
 * name lookup stalls as it does when a DNS server never answers. The
 * container has no resolver to stall: its lookups fail at once. On every
 * Linux libcurl recorded, this stalled libcurl's resolver thread as a
 * silent DNS server did in spike E1, scaled to the stall.
 *
 * The environment, read once, as the object loads:
 *   STALL_SUFFIX  a lookup of a name ending in it stalls; unset, none does
 *   STALL_MS      for this long, in ms, then answers EAI_NONAME
 *   STALL_LOG     a file each stalled lookup appends a line to: "stalling
 *                 NAME" as it starts, and "answered NAME" as it answers;
 *                 and the object itself, "loaded PID", as it loads, so a
 *                 probe can tell a stand-in never loaded from one loaded
 *                 that stalled nothing
 *
 * Every other lookup goes to the real getaddrinfo. On Linux this file
 * defines getaddrinfo itself, which LD_PRELOAD puts first, and finds the
 * real one by dlsym(RTLD_NEXT, ...). On macOS it interposes, through an
 * __interpose section that DYLD_INSERT_LIBRARIES loads, and calls the real
 * one by name: dyld does not interpose the interposing image's own calls.
 * Whether that reaches the resolver Apple's libcurl uses is the Mac's probe
 * to show; test-engine runs the stall checks on Linux alone. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

static const char *stall_suffix;
static long stall_ms;
static const char *stall_log;

static void note(const char *what, const char *node);

__attribute__((constructor)) static void read_environment(void) {
  const char *ms = getenv("STALL_MS");
  stall_suffix = getenv("STALL_SUFFIX");
  stall_ms = ms ? strtol(ms, NULL, 10) : 0;
  stall_log = getenv("STALL_LOG");
  char pid[32];
  snprintf(pid, sizeof pid, "%ld", (long)getpid());
  note("loaded", pid);
}

/* stalled: whether a lookup of NODE stalls. */
static int stalled(const char *node) {
  if (!node || !stall_suffix || !*stall_suffix) return 0;
  size_t n = strlen(node), s = strlen(stall_suffix);
  return n >= s && strcmp(node + n - s, stall_suffix) == 0;
}

/* note: appends "WHAT NODE" and a newline to STALL_LOG, in one write. */
static void note(const char *what, const char *node) {
  if (!stall_log) return;
  char line[512];
  int n = snprintf(line, sizeof line, "%s %s\n", what, node);
  if (n <= 0 || (size_t)n >= sizeof line) return;
  int fd = open(stall_log, O_WRONLY | O_APPEND | O_CREAT, 0600);
  if (fd < 0) return;
  ssize_t written = write(fd, line, (size_t)n);
  (void)written;
  close(fd);
}

/* stall: NODE's lookup, stalled for STALL_MS, then refused. */
static int stall(const char *node) {
  note("stalling", node);
  struct timespec left = {stall_ms / 1000, (stall_ms % 1000) * 1000000L};
  while (nanosleep(&left, &left) == -1 && errno == EINTR) {
  }
  note("answered", node);
  return EAI_NONAME;
}

#ifdef __APPLE__

static int stall_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints,
                             struct addrinfo **res) {
  if (stalled(node)) return stall(node);
  return getaddrinfo(node, service, hints, res);
}

__attribute__((used, section("__DATA,__interpose"))) static const struct {
  const void *replacement;
  const void *replacee;
} interpose_getaddrinfo = {(const void *)stall_getaddrinfo, (const void *)getaddrinfo};

#else

typedef int (*getaddrinfo_fn)(const char *, const char *, const struct addrinfo *,
                              struct addrinfo **);

int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints,
                struct addrinfo **res) {
  if (stalled(node)) return stall(node);
  getaddrinfo_fn real = (getaddrinfo_fn)dlsym(RTLD_NEXT, "getaddrinfo");
  if (!real) return EAI_SYSTEM;
  return real(node, service, hints, res);
}

#endif
