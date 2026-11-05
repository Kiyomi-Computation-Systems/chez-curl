/* M7 slice 4's file watch (2026-11-03), after ../cookies/probe.c's: an
   LD_PRELOAD interposer, Linux alone. Every fopen, fopen64, open, open64,
   openat, openat64, __open_2 and __open64_2 call is passed on, and logged,
   one line each, to the file FSWATCH_LOG names, opened at load with
   O_APPEND:
     CALL "PATH"
   the path's bytes outside 0x20..0x7e, and \ and ", written \xHH. Each line
   is one write(2). Built in the Guix container:
     $CC -shared -fPIC -o build/m7s4/fswatch.so fswatch.c -ldl */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static int log_fd = -1;

__attribute__((constructor)) static void fswatch_init(void) {
  const char *p = getenv("FSWATCH_LOG");
  if (p && *p) log_fd = (int)syscall(SYS_openat, AT_FDCWD, p, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
}

static void note(const char *call, const char *path) {
  char line[1200];
  size_t n = 0;
  if (log_fd < 0) return;
  n += (size_t)snprintf(line, sizeof line, "%s \"", call);
  if (!path) {
    n = (size_t)snprintf(line, sizeof line, "%s (null)\n", call);
  } else {
    for (const unsigned char *s = (const unsigned char *)path; *s && n + 6 < sizeof line; s++) {
      if (*s >= 0x20 && *s <= 0x7e && *s != '\\' && *s != '"') line[n++] = (char)*s;
      else n += (size_t)snprintf(line + n, sizeof line - n, "\\x%02x", *s);
    }
    line[n++] = '"';
    line[n++] = '\n';
  }
  if (write(log_fd, line, n) < 0) { /* nothing to do */ }
}

FILE *fopen(const char *p, const char *m) {
  static FILE *(*r)(const char *, const char *);
  if (!r) r = (FILE * (*)(const char *, const char *)) dlsym(RTLD_NEXT, "fopen");
  note("fopen", p);
  return r(p, m);
}

FILE *fopen64(const char *p, const char *m) {
  static FILE *(*r)(const char *, const char *);
  if (!r) r = (FILE * (*)(const char *, const char *)) dlsym(RTLD_NEXT, "fopen64");
  note("fopen64", p);
  return r(p, m);
}

#define OPEN_LIKE(NAME)                                                     \
  int NAME(const char *p, int flags, ...) {                                \
    static int (*r)(const char *, int, ...);                               \
    mode_t mode = 0;                                                       \
    if (!r) r = (int (*)(const char *, int, ...))dlsym(RTLD_NEXT, #NAME); \
    if (flags & (O_CREAT | O_TMPFILE)) {                                   \
      va_list ap;                                                          \
      va_start(ap, flags);                                                 \
      mode = (mode_t)va_arg(ap, int);                                      \
      va_end(ap);                                                          \
    }                                                                      \
    note(#NAME, p);                                                        \
    return r(p, flags, mode);                                              \
  }
OPEN_LIKE(open)
OPEN_LIKE(open64)

#define OPENAT_LIKE(NAME)                                                        \
  int NAME(int dir, const char *p, int flags, ...) {                            \
    static int (*r)(int, const char *, int, ...);                               \
    mode_t mode = 0;                                                            \
    if (!r) r = (int (*)(int, const char *, int, ...))dlsym(RTLD_NEXT, #NAME); \
    if (flags & (O_CREAT | O_TMPFILE)) {                                        \
      va_list ap;                                                               \
      va_start(ap, flags);                                                      \
      mode = (mode_t)va_arg(ap, int);                                           \
      va_end(ap);                                                               \
    }                                                                           \
    note(#NAME, p);                                                             \
    return r(dir, p, flags, mode);                                              \
  }
OPENAT_LIKE(openat)
OPENAT_LIKE(openat64)

int __open_2(const char *p, int flags) {
  static int (*r)(const char *, int);
  if (!r) r = (int (*)(const char *, int))dlsym(RTLD_NEXT, "__open_2");
  note("__open_2", p);
  return r(p, flags);
}

int __open64_2(const char *p, int flags) {
  static int (*r)(const char *, int);
  if (!r) r = (int (*)(const char *, int))dlsym(RTLD_NEXT, "__open64_2");
  note("__open64_2", p);
  return r(p, flags);
}
