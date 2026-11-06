/* M8's mime-files probe (2026-11-06; probe 2 of the M8 plan's measurements:
   how libcurl reads a file part, what it does when a mime body must go
   again inside one transfer, how a mime handle lives and dies beside its
   easy handle, and what a libcurl configured without mime answers).

     probe --version
     probe CASE CTL RAW H2C DIR

   CTL, RAW and H2C are server.mjs's ports; DIR is a scratch directory of the
   run's own, which the probe writes its files into. CASE is one of the names
   in the table at the end of this file; run.sh runs them all, one process
   each, so a crash ends one case alone.

   Every transfer goes through a multi handle, in M7's probes' loop, which
   mirrors chez-curl's engine turn: curl_multi_add_handle of a transfer whose
   time has come, curl_multi_perform, curl_multi_info_read (a done transfer
   is removed at once, but where a case keeps it), then curl_multi_poll for
   at most 1000 ms. Waits between transfers are engine turns too: perform,
   then poll, with no transfer.

   Every transfer gets the engine's options (src/curl/private/transfer.sls,
   set-transfer-options!): PROTOCOLS_STR and REDIR_PROTOCOLS_STR
   "http,https", NOSIGNAL 1, MAXREDIRS 30, QUICK_EXIT 1 (option 322 by number:
   the floor's headers predate it; its CURLE_UNKNOWN_OPTION is taken),
   ERRORBUFFER, the URL, WRITEFUNCTION and WRITEDATA, PROXY "", FOLLOWLOCATION
   0, and HTTPHEADER "Expect:", the engine's blank for every body, unless a
   case names its own Expect. Not the engine's "Content-Type:" blank: it would
   take away the multipart type and its boundary (probe 1's area). Then, as
   the probe's own bound, TIMEOUT_MS 10000 (5000 in the C- cases; a case may
   say less), and VERBOSE with a debug callback: libcurl's text, each request
   head sent and each response head received are printed, and the body bytes
   sent (CURLINFO_DATA_OUT) are summed per request head, so "attempts=K
   data_out=A,B,.." is the client's own count. HTTP/2 cases set HTTP_VERSION
   2_PRIOR_KNOWLEDGE against the h2c face.

   A mime's parts: "field", data "value-1"; then by kind:
     data  "blob", 3000 bytes of data;
     file  "upload", a 3000-byte regular file, DIR/up.txt;
     big   "upload", a 4 MiB regular file, DIR/up.txt: a resend that comes
           while libcurl is inside the part;
     pipe  "upload", a FIFO, DIR/fifo, whose writer, a child, opens it for
           writing up to 3 times and writes the same 3000 bytes each time:
           so a second open of it by libcurl would show, and not hang.
   Content: byte i of a seed-S blob is 'a' + (i + S) mod 26. "expect" lines
   name each part's length and FNV-1a 32 hash; server.mjs logs the same of
   each part it received.

   On Linux the probe interposes fopen, fopen64, open, open64, openat,
   openat64, __open_2, __open64_2, stat, stat64, access, fread, fseek,
   fseeko, fseeko64 and fclose, and prints a line "fs FN step=STEP pf=K
   tid=main|N ..." for each call made while the probe is inside a libcurl
   call: STEP names the call (filedata, mimepost, add, perform, remove,
   easy_cleanup, mime_free, ...), pf the curl_multi_perform it was in, tid the
   thread. fread, fseek and fclose are printed for the files libcurl opened
   through fopen alone. glibc's own internal calls do not go through them.

   libcurl allocates through curl_global_init_mem's counting allocators,
   unless PROBE_PLAIN=1 (Valgrind's runs: the counting header would make
   every block's pointer an interior one, which Valgrind calls possibly lost):
   "live" is the bytes libcurl holds through them at that moment.

   PROBE_ALARM=S bounds the whole case at S seconds (default 60): the
   handler prints "alarm" and exits 3.

   Output: lines "case NAME ...". Bytes outside 0x20..0x7e, and \ and ", print
   as \xHH; CR as \r, LF as \n. "server:" lines are server.mjs's events since
   the case's step began, fetched on the control port over a plain socket,
   after the step's transfers. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <curl/curl.h>
#ifdef __linux__
#include <dlfcn.h>
#include <sys/syscall.h>
#endif

#ifndef CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE
#define CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE 5
#endif

static int P_CTL, P_RAW, P_H2C;
static const char *DIR_ = ".";
static const char *CASE = "-";
static const char *STEP = "-";
static int fs_watch;
static int perform_n;
static long main_tid;

/* ---------------------------------------------------------------- output */
static void esc(const unsigned char *d, size_t n, char *out, size_t cap) {
  size_t o = 0, i;
  for (i = 0; i < n && o + 8 < cap; i++) {
    unsigned char c = d[i];
    if (c == '\r') { out[o++] = '\\'; out[o++] = 'r'; }
    else if (c == '\n') { out[o++] = '\\'; out[o++] = 'n'; }
    else if (c == '\\' || c == '"' || c < 0x20 || c > 0x7e) o += (size_t)snprintf(out + o, cap - o, "\\x%02x", c);
    else out[o++] = (char)c;
  }
  if (i < n) o += (size_t)snprintf(out + o, cap - o, "...(%zu bytes)", n);
  out[o] = 0;
}
#define SAY(...) do { printf("case %s ", CASE); printf(__VA_ARGS__); putchar('\n'); fflush(stdout); } while (0)

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

static uint32_t fnv(const unsigned char *b, size_t n) {
  uint32_t h = 0x811c9dc5u;
  size_t i;
  for (i = 0; i < n; i++) { h ^= b[i]; h *= 0x01000193u; }
  return h;
}

/* ---------------------------------------------------------------- the file watch */
#ifdef __linux__
static long tid_now(void) { return (long)syscall(SYS_gettid); }
typedef struct { FILE *f; char path[600]; } fent;
static fent ftab[64];
static const char *fpath(FILE *f) {
  int i;
  for (i = 0; i < 64; i++) if (ftab[i].f && ftab[i].f == f) return ftab[i].path;
  return NULL;
}
static void fs_note(const char *fn, const char *p, const char *fmt, ...) {
  char e[1400], rest[256] = "";
  long t;
  va_list ap;
  if (!fs_watch) return;
  t = tid_now();
  esc((const unsigned char *)(p ? p : "(null)"), p ? strlen(p) : 6, e, sizeof e);
  if (fmt) { va_start(ap, fmt); vsnprintf(rest, sizeof rest, fmt, ap); va_end(ap); }
  if (t == main_tid) printf("case %s fs %s step=%s pf=%d tid=main path=\"%s\" %s\n", CASE, fn, STEP, perform_n, e, rest);
  else printf("case %s fs %s step=%s pf=%d tid=%ld path=\"%s\" %s\n", CASE, fn, STEP, perform_n, t, e, rest);
  fflush(stdout);
}
#define NEXT(fn) static __typeof__(&fn) r_; if (!r_) r_ = (__typeof__(&fn))dlsym(RTLD_NEXT, #fn)
static FILE *track_open(const char *fn, const char *p, FILE *f, int err) {
  int i;
  if (f && fs_watch)
    for (i = 0; i < 64; i++) if (!ftab[i].f) { ftab[i].f = f; snprintf(ftab[i].path, sizeof ftab[i].path, "%s", p); break; }
  fs_note(fn, p, "ret=%s fd=%d errno=%d", f ? "FILE" : "NULL", f ? fileno(f) : -1, f ? 0 : err);
  return f;
}
FILE *fopen(const char *p, const char *m) {
  FILE *f;
  NEXT(fopen);
  f = r_(p, m);
  return track_open("fopen", p, f, errno);
}
FILE *fopen64(const char *p, const char *m) {
  FILE *f;
  NEXT(fopen64);
  f = r_(p, m);
  return track_open("fopen64", p, f, errno);
}
#ifdef O_TMPFILE
#define NEEDS_MODE(f) (((f) & O_CREAT) != 0 || ((f) & O_TMPFILE) == O_TMPFILE)
#else
#define NEEDS_MODE(f) (((f) & O_CREAT) != 0)
#endif
#define OPEN_LIKE(NAME)                                                        \
  int NAME(const char *p, int f, ...) {                                        \
    mode_t md = 0;                                                             \
    int fd, e;                                                                 \
    NEXT(NAME);                              \
    if (NEEDS_MODE(f)) { va_list ap; va_start(ap, f); md = (mode_t)va_arg(ap, int); va_end(ap); } \
    fd = r_(p, f, md);                                                         \
    e = errno;                                                                 \
    fs_note(#NAME, p, "flags=0x%x ret=%d errno=%d", f, fd, fd < 0 ? e : 0);    \
    errno = e;                                                                 \
    return fd;                                                                 \
  }
OPEN_LIKE(open)
OPEN_LIKE(open64)
#define OPENAT_LIKE(NAME)                                                      \
  int NAME(int d, const char *p, int f, ...) {                                 \
    mode_t md = 0;                                                             \
    int fd, e;                                                                 \
    NEXT(NAME);                         \
    if (NEEDS_MODE(f)) { va_list ap; va_start(ap, f); md = (mode_t)va_arg(ap, int); va_end(ap); } \
    fd = r_(d, p, f, md);                                                      \
    e = errno;                                                                 \
    fs_note(#NAME, p, "flags=0x%x ret=%d errno=%d", f, fd, fd < 0 ? e : 0);    \
    errno = e;                                                                 \
    return fd;                                                                 \
  }
OPENAT_LIKE(openat)
OPENAT_LIKE(openat64)
int __open_2(const char *p, int f) {
  int fd, e;
  NEXT(__open_2);
  fd = r_(p, f);
  e = errno;
  fs_note("__open_2", p, "ret=%d errno=%d", fd, fd < 0 ? e : 0);
  errno = e;
  return fd;
}
int __open64_2(const char *p, int f) {
  int fd, e;
  NEXT(__open64_2);
  fd = r_(p, f);
  e = errno;
  fs_note("__open64_2", p, "ret=%d errno=%d", fd, fd < 0 ? e : 0);
  errno = e;
  return fd;
}
int stat(const char *p, struct stat *b) {
  int rc, e;
  NEXT(stat);
  rc = r_(p, b);
  e = errno;
  fs_note("stat", p, "ret=%d errno=%d size=%lld mode=0%o", rc, rc ? e : 0, rc ? -1LL : (long long)b->st_size, rc ? 0 : (unsigned)b->st_mode);
  errno = e;
  return rc;
}
int stat64(const char *p, struct stat64 *b) {
  int rc, e;
  NEXT(stat64);
  rc = r_(p, b);
  e = errno;
  fs_note("stat64", p, "ret=%d errno=%d size=%lld mode=0%o", rc, rc ? e : 0, rc ? -1LL : (long long)b->st_size, rc ? 0 : (unsigned)b->st_mode);
  errno = e;
  return rc;
}
int access(const char *p, int m) {
  int rc, e;
  NEXT(access);
  rc = r_(p, m);
  e = errno;
  fs_note("access", p, "mode=%d ret=%d errno=%d", m, rc, rc ? e : 0);
  errno = e;
  return rc;
}
size_t fread(void *buf, size_t sz, size_t n, FILE *f) {
  size_t got;
  const char *p;
  NEXT(fread);
  got = r_(buf, sz, n, f);
  p = fpath(f);
  if (p) fs_note("fread", p, "asked=%zu got=%zu eof=%d error=%d errno=%d", sz * n, got * sz, feof(f), ferror(f), ferror(f) ? errno : 0);
  return got;
}
int fseek(FILE *f, long off, int wh) {
  int rc;
  const char *p;
  NEXT(fseek);
  rc = r_(f, off, wh);
  p = fpath(f);
  if (p) fs_note("fseek", p, "offset=%ld whence=%d ret=%d", off, wh, rc);
  return rc;
}
int fseeko(FILE *f, off_t off, int wh) {
  int rc;
  const char *p;
  NEXT(fseeko);
  rc = r_(f, off, wh);
  p = fpath(f);
  if (p) fs_note("fseeko", p, "offset=%lld whence=%d ret=%d", (long long)off, wh, rc);
  return rc;
}
int fseeko64(FILE *f, off64_t off, int wh) {
  int rc;
  const char *p;
  NEXT(fseeko64);
  rc = r_(f, off, wh);
  p = fpath(f);
  if (p) fs_note("fseeko64", p, "offset=%lld whence=%d ret=%d", (long long)off, wh, rc);
  return rc;
}
int fclose(FILE *f) {
  int i, rc;
  char path[600] = "";
  NEXT(fclose);
  for (i = 0; i < 64; i++) if (f && ftab[i].f == f) { snprintf(path, sizeof path, "%s", ftab[i].path); ftab[i].f = NULL; break; }
  rc = r_(f);
  if (path[0]) {
    int w = fs_watch;
    fs_watch = 1;   /* a tracked file's close is printed wherever it comes from */
    fs_note("fclose", path, "ret=%d", rc);
    fs_watch = w;
  }
  return rc;
}
#else
static long tid_now(void) { return 0; }
#endif

/* IN_CALL: STEP named, the watch on, around one libcurl call. */
#define IN_CALL(step, expr) do { const char *s_ = STEP; STEP = (step); fs_watch = 1; expr; fs_watch = 0; STEP = s_; } while (0)

/* ---------------------------------------------------------------- memory */
#define HDR 16
static int64_t live;
static void track(int64_t d) { __atomic_add_fetch(&live, d, __ATOMIC_SEQ_CST); }
static int64_t live_now(void) { return __atomic_load_n(&live, __ATOMIC_SEQ_CST); }
static void *c_malloc(size_t n) {
  unsigned char *p = malloc(n + HDR);
  if (!p) return NULL;
  memcpy(p, &n, sizeof n);
  track((int64_t)n);
  return p + HDR;
}
static void c_free(void *q) {
  unsigned char *p;
  size_t n;
  if (!q) return;
  p = (unsigned char *)q - HDR;
  memcpy(&n, p, sizeof n);
  track(-(int64_t)n);
  free(p);
}
static void *c_realloc(void *q, size_t n) {
  unsigned char *p, *r;
  size_t o;
  if (!q) return c_malloc(n);
  p = (unsigned char *)q - HDR;
  memcpy(&o, p, sizeof o);
  r = realloc(p, n + HDR);
  if (!r) return NULL;
  memcpy(r, &n, sizeof n);
  track((int64_t)n - (int64_t)o);
  return r + HDR;
}
static char *c_strdup(const char *s) {
  size_t n = strlen(s) + 1;
  char *p = c_malloc(n);
  if (p) memcpy(p, s, n);
  return p;
}
static void *c_calloc(size_t a, size_t b) {
  void *p;
  if (b && a > SIZE_MAX / b) return NULL;
  p = c_malloc(a * b);
  if (p) memset(p, 0, a * b);
  return p;
}
static int plain(void) { const char *v = getenv("PROBE_PLAIN"); return v && !strcmp(v, "1"); }
#define LIVE(label) do { if (!plain()) SAY("live %s=%lld", label, (long long)live_now()); } while (0)

/* ---------------------------------------------------------------- files */
static unsigned char *blob(size_t n, int seed) {
  unsigned char *b = malloc(n ? n : 1);
  size_t i;
  for (i = 0; i < n; i++) b[i] = (unsigned char)('a' + (int)((i + (size_t)seed) % 26));
  return b;
}
static void expect_line(const char *part, const unsigned char *b, size_t n) {
  SAY("expect part=%s len=%zu fnv=%08x", part, n, fnv(b, n));
}
/* put_file: PATH, N bytes of seed SEED, made or truncated; the probe's own
   I/O, outside the watch. */
static void put_file(const char *path, size_t n, int seed) {
  unsigned char *b = blob(n, seed);
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  size_t o = 0;
  if (fd < 0) { SAY("put_file %s failed errno=%d", path, errno); free(b); return; }
  while (o < n) { ssize_t k = write(fd, b + o, n - o); if (k <= 0) break; o += (size_t)k; }
  close(fd);
  free(b);
}
static char *in_dir(const char *name) {
  static char bufs[8][700];
  static int k;
  char *b = bufs[k++ % 8];
  snprintf(b, sizeof bufs[0], "%s/%s", DIR_, name);
  return b;
}

/* The FIFO's writer: a child that, after DELAY ms, opens PATH for writing
   (blocking until a reader opens it), writes N bytes of seed SEED and closes
   it. Then, up to TIMES - 1 more times: it waits 1000 ms, so that the reader
   has seen the end and closed, then polls every 20 ms, for up to 30 s, for a
   reader, by an O_NONBLOCK open (ENXIO while there is none), and on one
   writes N bytes of seed SEED + 100, another content, and closes. So a
   second open by libcurl neither hangs nor passes for the first. */
static pid_t fifo_writer(const char *path, size_t n, int seed, int times, int delay) {
  pid_t pid;
  fflush(stdout);
  pid = fork();
  if (pid == 0) {
    unsigned char *b = blob(n, seed), *b2 = blob(n, seed + 100);
    int t, fd;
    size_t o = 0;
    fs_watch = 0;
    if (delay > 0) usleep((useconds_t)delay * 1000);
    fd = open(path, O_WRONLY);
    if (fd < 0) _exit(4);
    while (o < n) { ssize_t k = write(fd, b + o, n - o); if (k <= 0) break; o += (size_t)k; }
    close(fd);
    for (t = 1; t < times; t++) {
      int tries;
      usleep(1000 * 1000);
      for (tries = 0, fd = -1; tries < 1500 && fd < 0; tries++) {
        fd = open(path, O_WRONLY | O_NONBLOCK);
        if (fd < 0) usleep(20 * 1000);
      }
      if (fd < 0) _exit(0);
      fcntl(fd, F_SETFL, 0);
      for (o = 0; o < n;) { ssize_t k = write(fd, b2 + o, n - o); if (k <= 0) break; o += (size_t)k; }
      close(fd);
    }
    _exit(0);
  }
  return pid;
}
static void reap(pid_t pid, const char *what) {
  int st = 0;
  if (pid <= 0) return;
  kill(pid, SIGTERM);
  waitpid(pid, &st, 0);
  SAY("%s writer ended %s=%d (a second open's content, seed+100, is fnv of its own)", what, WIFEXITED(st) ? "exit" : "signal", WIFEXITED(st) ? WEXITSTATUS(st) : WTERMSIG(st));
}

/* ---------------------------------------------------------------- control */
static long ctl(const char *path, char *out, size_t cap) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in sa;
  struct timeval tv = { 8, 0 };
  char req[400], *buf, *body;
  size_t bcap = 4 << 20, n = 0;
  ssize_t k;
  long len;
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET;
  sa.sin_port = htons((unsigned short)P_CTL);
  sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
  if (connect(fd, (struct sockaddr *)&sa, sizeof sa)) { close(fd); return -1; }
  snprintf(req, sizeof req, "GET %s HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n", path);
  if (write(fd, req, strlen(req)) != (ssize_t)strlen(req)) { close(fd); return -1; }
  buf = malloc(bcap + 1);
  while (n < bcap && (k = read(fd, buf + n, bcap - n)) > 0) n += (size_t)k;
  close(fd);
  buf[n] = 0;
  body = strstr(buf, "\r\n\r\n");
  if (!body) { free(buf); return -1; }
  body += 4;
  len = (long)strlen(body);
  snprintf(out, cap, "%s", body);
  free(buf);
  return len;
}
static long ctl_seq(void) {
  char b[64];
  if (ctl("/seq", b, sizeof b) < 0) { SAY("ctl: /seq failed"); return -1; }
  return atol(b);
}
static char g_events[4 << 20];
static void events(const char *label, long after) {
  char p[64], *line, *nl;
  int n = 0;
  snprintf(p, sizeof p, "/events?after=%ld", after);
  if (ctl(p, g_events, sizeof g_events) < 0) { SAY("%s server: the events fetch failed", label); return; }
  for (line = g_events; *line; line = nl + 1) {
    n++;
    nl = strchr(line, '\n');
    if (!nl) { SAY("%s server: %s", label, line); break; }
    *nl = 0;
    SAY("%s server: %s", label, line);
    *nl = '\n';
  }
  SAY("%s server-events after=%ld n=%d", label, after, n);
}

/* ---------------------------------------------------------------- transfers */
typedef struct xfer {
  CURL *h;
  char name[96];
  int added, done, removed, keep, gave_up;
  CURLcode code;
  long status, conns;
  double t_add, t_end;
  int header_outs;
  long data_out[32];
  char err[CURL_ERROR_SIZE];
  struct curl_slist *hl;
  char resp[256];
  size_t resp_len;
} xfer;

static size_t on_write(char *d, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t n = sz * nm, k = n;
  if (x->resp_len + k > sizeof x->resp - 1) k = sizeof x->resp - 1 - x->resp_len;
  memcpy(x->resp + x->resp_len, d, k);
  x->resp_len += k;
  return n;
}
static int on_debug(CURL *h, curl_infotype type, char *d, size_t n, void *u) {
  xfer *x = u;
  char e[3000];
  (void)h;
  if (type == CURLINFO_DATA_OUT) {
    int i = x->header_outs > 0 ? x->header_outs - 1 : 0;
    if (i < 32) x->data_out[i] += (long)n;
    return 0;
  }
  if (type == CURLINFO_HEADER_OUT) {
    x->header_outs++;
    esc((const unsigned char *)d, n, e, sizeof e);
    SAY("%s dbg header_out n=%d t=%.1f \"%s\"", x->name, x->header_outs, now_ms() - x->t_add, e);
    return 0;
  }
  if (type != CURLINFO_TEXT && type != CURLINFO_HEADER_IN) return 0;
  while (n && (d[n - 1] == '\n' || d[n - 1] == '\r')) n--;
  esc((const unsigned char *)d, n, e, sizeof e);
  SAY("%s dbg %s t=%.1f \"%s\"", x->name, type == CURLINFO_TEXT ? "text" : "header_in", now_ms() - x->t_add, e);
  return 0;
}

#define SETOPT(x, opt, val) do { CURLcode rc_ = curl_easy_setopt((x)->h, opt, val); \
    if (rc_ != CURLE_OK) SAY("%s setopt %s rc=%d", (x)->name, #opt, (int)rc_); } while (0)

static long g_timeout = 10000;

/* mk: a transfer NAME to PATHQ on the raw face (h2c when H2), with the
   engine's options and HTTPHEADER EXPECT ("Expect:" unless a case names
   one; NULL for no header list). */
static xfer *mk(const char *name, const char *pathq, int h2, const char *expect) {
  xfer *x = calloc(1, sizeof *x);
  char url[700];
  CURLcode qe;
  snprintf(x->name, sizeof x->name, "%s", name);
  x->h = curl_easy_init();
  snprintf(url, sizeof url, "http://127.0.0.1:%d%s%stag=%s", h2 ? P_H2C : P_RAW, pathq, strchr(pathq, '?') ? "&" : "?", name);
  SETOPT(x, CURLOPT_URL, url);
  SETOPT(x, CURLOPT_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_NOSIGNAL, 1L);
  SETOPT(x, CURLOPT_MAXREDIRS, 30L);
  qe = curl_easy_setopt(x->h, (CURLoption)322, 1L);
  if (qe != CURLE_OK && qe != CURLE_UNKNOWN_OPTION) SAY("%s setopt QUICK_EXIT rc=%d", name, (int)qe);
  SETOPT(x, CURLOPT_ERRORBUFFER, x->err);
  SETOPT(x, CURLOPT_FOLLOWLOCATION, 0L);
  SETOPT(x, CURLOPT_PROXY, "");
  SETOPT(x, CURLOPT_TIMEOUT_MS, g_timeout);
  SETOPT(x, CURLOPT_WRITEFUNCTION, on_write);
  SETOPT(x, CURLOPT_WRITEDATA, x);
  SETOPT(x, CURLOPT_VERBOSE, 1L);
  SETOPT(x, CURLOPT_DEBUGFUNCTION, on_debug);
  SETOPT(x, CURLOPT_DEBUGDATA, x);
  SETOPT(x, CURLOPT_PRIVATE, x);
  if (h2) SETOPT(x, CURLOPT_HTTP_VERSION, (long)CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE);
  if (expect) {
    x->hl = curl_slist_append(NULL, expect);
    SETOPT(x, CURLOPT_HTTPHEADER, x->hl);
  }
  return x;
}

static void finish(CURLM *m, xfer *x) {
  char d[200], r[600];
  size_t o = 0;
  int i;
  curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &x->status);
  curl_easy_getinfo(x->h, CURLINFO_NUM_CONNECTS, &x->conns);
  if (!x->keep) {
    IN_CALL("remove", curl_multi_remove_handle(m, x->h));
    x->removed = 1;
  }
  d[0] = 0;
  for (i = 0; i < x->header_outs && i < 32; i++) o += (size_t)snprintf(d + o, sizeof d - o, "%s%ld", i ? "," : "", x->data_out[i]);
  esc((const unsigned char *)x->resp, x->resp_len, r, sizeof r);
  SAY("%s done code=%d (%s) errbuf=\"%s\" status=%ld num_connects=%ld attempts=%d data_out=%s t_end=%.1f resp=\"%s\"", x->name, (int)x->code,
      curl_easy_strerror(x->code), x->err, x->status, x->conns, x->header_outs, d[0] ? d : "-", x->t_end - x->t_add, r);
}

static void add(CURLM *m, xfer *x) {
  CURLMcode mc;
  x->t_add = now_ms();
  IN_CALL("add", mc = curl_multi_add_handle(m, x->h));
  x->added = 1;
  if (mc) SAY("%s multi_add rc=%d", x->name, (int)mc);
}

/* drive: the engine's turn over X until it is done, or BOUND ms pass. HOOK,
   when not NULL, runs once at AT ms after the start. Prints the longest
   curl_multi_perform. */
static void drive(CURLM *m, xfer *x, double bound, void (*hook)(xfer *), double at) {
  double start = now_ms(), pmax = 0;
  int running, q, hooked = 0, pmax_n = 0;
  CURLMsg *msg;
  if (!x->added) add(m, x);
  for (;;) {
    double t0, d;
    if (hook && !hooked && now_ms() - start >= at) { hooked = 1; hook(x); }
    perform_n++;
    t0 = now_ms();
    IN_CALL("perform", curl_multi_perform(m, &running));
    d = now_ms() - t0;
    if (d > pmax) { pmax = d; pmax_n = perform_n; }
    while ((msg = curl_multi_info_read(m, &q))) {
      if (msg->msg != CURLMSG_DONE || msg->easy_handle != x->h || x->done) continue;
      x->done = 1;
      x->code = msg->data.result;
      x->t_end = now_ms();
      finish(m, x);
    }
    if (x->done) break;
    if (now_ms() - start > bound) {
      SAY("%s gave-up after %.0f ms: the probe's own bound", x->name, bound);
      IN_CALL("remove", curl_multi_remove_handle(m, x->h));
      x->removed = 1;
      x->gave_up = 1;
      break;
    }
    {
      double wait = 1000;
      if (hook && !hooked && start + at - now_ms() < wait) wait = start + at - now_ms();
      if (start + bound - now_ms() < wait) wait = start + bound - now_ms();
      if (wait < 0) wait = 0;
      IN_CALL("poll", curl_multi_poll(m, NULL, 0, (int)(wait + 0.999), NULL));
    }
  }
  SAY("%s perform_max=%.1f ms at pf=%d", x->name, pmax, pmax_n);
}

/* idle: engine turns with no transfer, for MS ms. */
static void idle(CURLM *m, double ms) {
  double end = now_ms() + ms;
  int running;
  for (;;) {
    double left = end - now_ms();
    perform_n++;
    IN_CALL("idle-perform", curl_multi_perform(m, &running));
    if (left <= 0) break;
    IN_CALL("idle-poll", curl_multi_poll(m, NULL, 0, (int)(left > 1000 ? 1000 : left + 0.999), NULL));
  }
}

static void drop(xfer *x) {
  if (!x) return;
  if (x->h) IN_CALL("easy_cleanup", curl_easy_cleanup(x->h));
  if (x->hl) curl_slist_free_all(x->hl);
  free(x);
}

/* ---------------------------------------------------------------- mimes */
static curl_mimepart *part_data(curl_mime *mm, const char *name, const unsigned char *d, size_t n) {
  curl_mimepart *p;
  CURLcode rc;
  IN_CALL("addpart", p = curl_mime_addpart(mm));
  if (!p) { SAY("mime fn=curl_mime_addpart part=%s answered NULL", name); return NULL; }
  IN_CALL("name", rc = curl_mime_name(p, name));
  if (rc) SAY("mime fn=curl_mime_name part=%s rc=%d", name, (int)rc);
  IN_CALL("data", rc = curl_mime_data(p, (const char *)d, n));
  SAY("mime fn=curl_mime_data part=%s len=%zu rc=%d", name, n, (int)rc);
  return p;
}
static CURLcode g_file_rc;
static curl_mimepart *part_file(curl_mime *mm, const char *name, const char *path) {
  curl_mimepart *p;
  CURLcode rc;
  char e[800];
  IN_CALL("addpart", p = curl_mime_addpart(mm));
  if (!p) { SAY("mime fn=curl_mime_addpart part=%s answered NULL", name); return NULL; }
  IN_CALL("name", rc = curl_mime_name(p, name));
  if (rc) SAY("mime fn=curl_mime_name part=%s rc=%d", name, (int)rc);
  IN_CALL("filedata", rc = curl_mime_filedata(p, path));
  g_file_rc = rc;
  esc((const unsigned char *)path, strlen(path), e, sizeof e);
  SAY("mime fn=curl_mime_filedata part=%s path=\"%s\" rc=%d (%s)", name, e, (int)rc, curl_easy_strerror(rc));
  return p;
}
static void attach(xfer *x, curl_mime *mm) {
  CURLcode rc;
  IN_CALL("mimepost", rc = curl_easy_setopt(x->h, CURLOPT_MIMEPOST, mm));
  SAY("%s setopt MIMEPOST rc=%d (%s)", x->name, (int)rc, curl_easy_strerror(rc));
}
static void mime_free(curl_mime *mm) { IN_CALL("mime_free", curl_mime_free(mm)); }

/* kind_mime: "field" = "value-1", and the kind's second part. PIPE_PID gets
   the FIFO writer's pid, for a pipe. */
static curl_mime *kind_mime(CURL *easy, const char *kind, pid_t *pipe_pid) {
  curl_mime *mm;
  unsigned char *b;
  IN_CALL("mime_init", mm = curl_mime_init(easy));
  part_data(mm, "field", (const unsigned char *)"value-1", 7);
  expect_line("field", (const unsigned char *)"value-1", 7);
  if (!strcmp(kind, "data")) {
    b = blob(3000, 1);
    part_data(mm, "blob", b, 3000);
    expect_line("blob", b, 3000);
    free(b);
  } else if (!strcmp(kind, "file")) {
    put_file(in_dir("up.txt"), 3000, 2);
    b = blob(3000, 2);
    expect_line("upload", b, 3000);
    free(b);
    part_file(mm, "upload", in_dir("up.txt"));
  } else if (!strcmp(kind, "big")) {
    put_file(in_dir("up.txt"), 4 << 20, 12);
    b = blob(4 << 20, 12);
    expect_line("upload", b, 4 << 20);
    free(b);
    part_file(mm, "upload", in_dir("up.txt"));
  } else {
    unlink(in_dir("fifo"));
    if (mkfifo(in_dir("fifo"), 0644)) SAY("mkfifo failed errno=%d", errno);
    b = blob(3000, 3);
    expect_line("upload", b, 3000);
    free(b);
    *pipe_pid = fifo_writer(in_dir("fifo"), 3000, 3, 3, 0);
    part_file(mm, "upload", in_dir("fifo"));
  }
  return mm;
}

/* ---------------------------------------------------------------- case 1 */
/* R-when: a data part and two file parts; each step's file calls; then the
   same easy handle, the same mime, performed again. */
static void r_when(void) {
  CURLM *m = curl_multi_init();
  xfer *x = mk("R-when", "/sink", 0, "Expect:");
  curl_mime *mm;
  unsigned char *b;
  long s0 = ctl_seq();
  put_file(in_dir("when1.txt"), 3000, 4);
  put_file(in_dir("when2.txt"), 2000, 5);
  IN_CALL("mime_init", mm = curl_mime_init(x->h));
  part_data(mm, "field", (const unsigned char *)"value-1", 7);
  part_file(mm, "first", in_dir("when1.txt"));
  part_file(mm, "second", in_dir("when2.txt"));
  b = blob(3000, 4); expect_line("first", b, 3000); free(b);
  b = blob(2000, 5); expect_line("second", b, 2000); free(b);
  attach(x, mm);
  drive(m, x, 15000, NULL, 0);
  events("R-when:1", s0);
  /* again: the same handle and mime, as a second transfer */
  s0 = ctl_seq();
  x->added = x->done = x->removed = 0;
  x->header_outs = 0;
  memset(x->data_out, 0, sizeof x->data_out);
  x->resp_len = 0;
  snprintf(x->name, sizeof x->name, "R-when-again");
  drive(m, x, 15000, NULL, 0);
  events("R-when:2", s0);
  drop(x);
  mime_free(mm);
  curl_multi_cleanup(m);
}

/* R-big: a 4 MiB file part: fopen at its first read, freads across
   performs, its fclose. */
static void r_big(void) {
  curl_mime *mm;
  unsigned char *b;
  CURLM *m = curl_multi_init();
  xfer *x = mk("R-big", "/sink", 0, "Expect:");
  long s0 = ctl_seq();
  put_file(in_dir("big.bin"), 4 << 20, 6);
  IN_CALL("mime_init", mm = curl_mime_init(x->h));
  part_data(mm, "field", (const unsigned char *)"value-1", 7);
  part_file(mm, "big", in_dir("big.bin"));
  b = blob(4 << 20, 6); expect_line("big", b, 4 << 20); free(b);
  attach(x, mm);
  drive(m, x, 15000, NULL, 0);
  events("R-big", s0);
  drop(x);
  mime_free(mm);
  curl_multi_cleanup(m);
}

/* ---------------------------------------------------------------- case 2 */
/* change: a file part at PATH (made by PRE, at its size), MID run between
   curl_mime_filedata and the transfer. */
typedef void (*mutator)(const char *path);
static void c_case(const char *name, int make, size_t n0, int seed0, mutator pre, mutator mid) {
  CURL *e0;
  curl_mime *mm;
  xfer *x;
  CURLM *m;
  const char *path = in_dir("change.txt");
  unlink(path);
  if (make) put_file(path, n0, seed0);
  if (pre) pre(path);
  SAY("euid=%d access_R_OK_by_probe=%d", (int)geteuid(), access(path, R_OK));
  x = mk(name, "/sink", 0, "Expect:");
  e0 = x->h;
  IN_CALL("mime_init", mm = curl_mime_init(e0));
  part_data(mm, "field", (const unsigned char *)"value-1", 7);
  part_file(mm, "upload", path);
  if (mid) mid(path);
  SAY("after-mutation access_R_OK_by_probe=%d", access(path, R_OK));
  attach(x, mm);
  m = curl_multi_init();
  {
    long s0 = ctl_seq();
    drive(m, x, g_timeout + 5000, NULL, 0);
    events(name, s0);
  }
  drop(x);
  mime_free(mm);
  curl_multi_cleanup(m);
  chmod(path, 0644);
  unlink(path);
}
static void m_make1000(const char *p) { unsigned char *b = blob(1000, 7); put_file(p, 1000, 7); expect_line("upload-made", b, 1000); free(b); }
static void m_unlink(const char *p) { SAY("unlink rc=%d", unlink(p)); }
static void m_chmod0(const char *p) { SAY("chmod 000 rc=%d", chmod(p, 0)); }
static void m_grow(const char *p) {
  unsigned char *b = blob(3000, 8);
  put_file(p, 3000, 8);
  expect_line("upload-grown-whole", b, 3000);
  expect_line("upload-grown-first-1000", b, 1000);
  free(b);
}
static void m_shrink(const char *p) { unsigned char *b = blob(1000, 9); put_file(p, 1000, 9); expect_line("upload-shrunk", b, 1000); free(b); }
static void m_replace(const char *p) {
  char tmp[800];
  unsigned char *b = blob(1000, 10);
  snprintf(tmp, sizeof tmp, "%s.new", p);
  put_file(tmp, 1000, 10);
  SAY("rename rc=%d", rename(tmp, p));
  expect_line("upload-replaced", b, 1000);
  free(b);
}
static void c_missing(void) { c_case("C-missing", 0, 0, 0, NULL, NULL); }
static void c_missing_made(void) { c_case("C-missing-made", 0, 0, 0, NULL, m_make1000); }
static void c_removed(void) { unsigned char *b = blob(1000, 11); expect_line("upload-at-filedata", b, 1000); free(b); c_case("C-removed", 1, 1000, 11, NULL, m_unlink); }
static void c_unreadable_first(void) { c_case("C-unreadable-first", 1, 1000, 12, m_chmod0, NULL); }
static void c_unreadable_later(void) { unsigned char *b = blob(1000, 13); expect_line("upload-at-filedata", b, 1000); free(b); c_case("C-unreadable-later", 1, 1000, 13, NULL, m_chmod0); }
static void c_grown(void) { c_case("C-grown", 1, 1000, 14, NULL, m_grow); }
static void c_shrunk(void) { c_case("C-shrunk", 1, 3000, 15, NULL, m_shrink); }
static void c_replaced(void) { c_case("C-replaced", 1, 1000, 16, NULL, m_replace); }

/* ---------------------------------------------------------------- case 3 */
static void n_path(const char *name, const char *path, long timeout) {
  curl_mime *mm;
  CURLM *m;
  xfer *x;
  long s0;
  long saved = g_timeout;
  if (timeout) g_timeout = timeout;
  x = mk(name, "/sink", 0, "Expect:");
  IN_CALL("mime_init", mm = curl_mime_init(x->h));
  part_data(mm, "field", (const unsigned char *)"value-1", 7);
  part_file(mm, "upload", path);
  attach(x, mm);
  m = curl_multi_init();
  s0 = ctl_seq();
  drive(m, x, 20000, NULL, 0);
  events(name, s0);
  drop(x);
  mime_free(mm);
  curl_multi_cleanup(m);
  g_timeout = saved;
}
static void n_fifo(void) {
  unsigned char *b = blob(5000, 17);
  pid_t w;
  unlink(in_dir("fifo"));
  mkfifo(in_dir("fifo"), 0644);
  expect_line("upload", b, 5000);
  free(b);
  w = fifo_writer(in_dir("fifo"), 5000, 17, 3, 0);
  n_path("N-fifo", in_dir("fifo"), 0);
  reap(w, "fifo");
}
static void n_fifo_late(void) {
  unsigned char *b = blob(5000, 18);
  pid_t w;
  unlink(in_dir("fifo"));
  mkfifo(in_dir("fifo"), 0644);
  expect_line("upload", b, 5000);
  free(b);
  w = fifo_writer(in_dir("fifo"), 5000, 18, 3, 1500);
  SAY("writer opens after 1500 ms; TIMEOUT_MS 500");
  n_path("N-fifo-late", in_dir("fifo"), 500);
  reap(w, "fifo");
}
static void n_dir(void) { mkdir(in_dir("adir"), 0755); n_path("N-dir", in_dir("adir"), 0); }
static void n_devnull(void) { n_path("N-devnull", "/dev/null", 0); }
static void n_stdin(void) {
  int fds[2];
  unsigned char *b = blob(1200, 19);
  size_t o = 0;
  char left[4096];
  ssize_t k;
  long total = 0;
  if (pipe(fds)) { SAY("pipe failed"); free(b); return; }
  while (o < 1200) { k = write(fds[1], b + o, 1200 - o); if (k <= 0) break; o += (size_t)k; }
  close(fds[1]);
  dup2(fds[0], 0);
  close(fds[0]);
  SAY("stdin is a pipe holding %zu bytes, written and closed", o);
  expect_line("upload", b, 1200);
  free(b);
  n_path("N-stdin", "/dev/stdin", 0);
  while ((k = read(0, left, sizeof left)) > 0) total += k;
  SAY("stdin-left=%ld", total);
}
static void n_proc(void) {
  struct stat sb;
  if (stat("/proc/self/status", &sb)) { SAY("skip: no /proc/self/status"); return; }
  SAY("probe stat /proc/self/status size=%lld regular=%d", (long long)sb.st_size, S_ISREG(sb.st_mode));
  n_path("N-proc", "/proc/self/status", 0);
}
static void n_relative(void) {
  char cwd[1000];
  unsigned char *b;
  curl_mime *mm;
  CURLM *m;
  xfer *x;
  long s0;
  int sub;
  if (!getcwd(cwd, sizeof cwd)) cwd[0] = 0;
  mkdir(in_dir("a"), 0755);
  mkdir(in_dir("b"), 0755);
  put_file(in_dir("a/rel.txt"), 1000, 20);
  put_file(in_dir("b/rel.txt"), 1500, 21);
  b = blob(1000, 20); expect_line("upload-a", b, 1000); free(b);
  b = blob(1500, 21); expect_line("upload-b", b, 1500); free(b);
  /* sub 0: no chdir; 1: chdir a -> b; 2: chdir a -> DIR, which has none */
  for (sub = 0; sub < 3; sub++) {
    char name[64];
    snprintf(name, sizeof name, "N-relative-%s", sub == 0 ? "stay" : sub == 1 ? "to-b" : "to-none");
    SAY("chdir a rc=%d", chdir(in_dir("a")));
    x = mk(name, "/sink", 0, "Expect:");
    IN_CALL("mime_init", mm = curl_mime_init(x->h));
    part_data(mm, "field", (const unsigned char *)"value-1", 7);
    part_file(mm, "upload", "rel.txt");
    if (sub == 1) SAY("chdir b rc=%d", chdir(in_dir("b")));
    if (sub == 2) SAY("chdir DIR rc=%d", chdir(DIR_));
    attach(x, mm);
    m = curl_multi_init();
    s0 = ctl_seq();
    drive(m, x, 20000, NULL, 0);
    events(name, s0);
    drop(x);
    mime_free(mm);
    curl_multi_cleanup(m);
  }
  if (cwd[0] && chdir(cwd)) SAY("chdir back failed");
}

/* ---------------------------------------------------------------- cases 4 and 5 */
static const char *g_kind;
static void x_run(const char *base, const char *pathq, int h2, const char *expect, void (*extra)(xfer *), const char *before, double wait) {
  char name[96];
  CURLM *m = curl_multi_init();
  xfer *x, *pre = NULL;
  curl_mime *mm;
  pid_t w = 0;
  long s0 = ctl_seq();
  snprintf(name, sizeof name, "%s-%s", base, g_kind);
  if (before) {
    char pn[112];
    snprintf(pn, sizeof pn, "%s.pre", name);
    pre = mk(pn, before, 0, NULL);
    drive(m, pre, 15000, NULL, 0);
    idle(m, wait);
  }
  x = mk(name, pathq, h2, expect);
  mm = kind_mime(x->h, g_kind, &w);
  if (extra) extra(x);
  attach(x, mm);
  drive(m, x, g_timeout + 5000, NULL, 0);
  events(name, s0);
  drop(x);
  drop(pre);
  mime_free(mm);
  curl_multi_cleanup(m);
  if (w) reap(w, "pipe");
}
static void e100(xfer *x) { SETOPT(x, CURLOPT_EXPECT_100_TIMEOUT_MS, 200L); }
static void digest(xfer *x) {
  SETOPT(x, CURLOPT_HTTPAUTH, (long)CURLAUTH_DIGEST);
  SETOPT(x, CURLOPT_USERNAME, "user");
  SETOPT(x, CURLOPT_PASSWORD, "pass");
}
static void follow(xfer *x) { SETOPT(x, CURLOPT_FOLLOWLOCATION, 1L); }
static void x_417(void) { x_run("X-417", "/sink?expect=417", 0, "Expect: 100-continue", NULL, NULL, 0); }
static void x_late417(void) { x_run("X-late417", "/sink?expect=late417", 0, "Expect: 100-continue", e100, NULL, 0); }
static void x_idle(void) { x_run("X-idle", "/sink", 0, "Expect:", NULL, "/hello?idleclose=100", 400); }
static void x_idle1500(void) { x_run("X-idle1500", "/sink", 0, "Expect:", NULL, "/hello?idleclose=100", 1500); }
static void x_drop(void) { x_run("X-drop", "/sink?drop=1&at=body", 0, "Expect:", NULL, "/hello", 0); }
static void x_drophead(void) { x_run("X-drophead", "/sink?drop=1&at=head", 0, "Expect:", NULL, "/hello", 0); }
static void x_digest(void) { x_run("X-digest", "/digest", 0, "Expect:", digest, NULL, 0); }
static void x_stale(void) { x_run("X-stale", "/digest?stale=1", 0, "Expect:", digest, NULL, 0); }
static void x_refuse_end(void) { x_run("X-refuse-end", "/refuse?n=1&at=end", 1, "Expect:", NULL, NULL, 0); }
static void x_refuse_head(void) { x_run("X-refuse-head", "/refuse?n=1&at=head", 1, "Expect:", NULL, NULL, 0); }
static void f_307(void) { x_run("F-307", "/redir?code=307", 0, "Expect:", follow, NULL, 0); }
static void f_308(void) { x_run("F-308", "/redir?code=308", 0, "Expect:", follow, NULL, 0); }

/* ---------------------------------------------------------------- case 6 */
/* lifetime: a mime of data and a file part, sent to /sink, then the case's
   order. */
static curl_mime *life_mime(CURL *e) {
  curl_mime *mm;
  unsigned char *b = blob(3000, 1);
  put_file(in_dir("life.txt"), 3000, 22);
  IN_CALL("mime_init", mm = curl_mime_init(e));
  part_data(mm, "field", (const unsigned char *)"value-1", 7);
  part_data(mm, "blob", b, 3000);
  part_file(mm, "upload", in_dir("life.txt"));
  free(b);
  return mm;
}
static void l_order(const char *name, int order) {
  CURLM *m = curl_multi_init();
  xfer *x = mk(name, "/sink", 0, "Expect:");
  curl_mime *mm;
  long s0 = ctl_seq();
  CURLcode rc;
  LIVE("start");
  mm = life_mime(x->h);
  attach(x, mm);
  if (order == 4) { mime_free(mm); SAY("mime freed before the transfer"); LIVE("after_mime_free"); }
  x->keep = (order == 3);
  drive(m, x, 15000, NULL, 0);
  events(name, s0);
  LIVE("after_transfer");
  switch (order) {
  case 1: /* cleanup, then free */
    IN_CALL("easy_cleanup", curl_easy_cleanup(x->h)); x->h = NULL;
    LIVE("after_easy_cleanup");
    mime_free(mm);
    LIVE("after_mime_free");
    break;
  case 2: /* free, then cleanup */
    mime_free(mm);
    LIVE("after_mime_free");
    IN_CALL("easy_cleanup", curl_easy_cleanup(x->h)); x->h = NULL;
    LIVE("after_easy_cleanup");
    break;
  case 3: /* free while still in the multi, then remove, then cleanup */
    mime_free(mm);
    LIVE("after_mime_free_in_multi");
    IN_CALL("remove", curl_multi_remove_handle(m, x->h));
    LIVE("after_remove");
    IN_CALL("easy_cleanup", curl_easy_cleanup(x->h)); x->h = NULL;
    LIVE("after_easy_cleanup");
    break;
  case 4: /* freed before the transfer */
    IN_CALL("easy_cleanup", curl_easy_cleanup(x->h)); x->h = NULL;
    LIVE("after_easy_cleanup");
    break;
  case 5: /* MIMEPOST NULL, then free, then cleanup */
    IN_CALL("mimepost-null", rc = curl_easy_setopt(x->h, CURLOPT_MIMEPOST, (curl_mime *)NULL));
    SAY("setopt MIMEPOST NULL rc=%d", (int)rc);
    mime_free(mm);
    LIVE("after_mime_free");
    IN_CALL("easy_cleanup", curl_easy_cleanup(x->h)); x->h = NULL;
    LIVE("after_easy_cleanup");
    break;
  }
  drop(x);
  curl_multi_cleanup(m);
  LIVE("after_multi_cleanup");
}
static void l_cleanup_then_free(void) { l_order("L-cleanup-then-free", 1); }
static void l_free_then_cleanup(void) { l_order("L-free-then-cleanup", 2); }
static void l_free_in_multi(void) { l_order("L-free-in-multi", 3); }
static void l_free_before(void) { l_order("L-free-before-transfer", 4); }
static void l_null_then_free(void) { l_order("L-null-then-free", 5); }
static void l_never(void) {
  CURL *e;
  curl_mime *mm;
  LIVE("start");
  e = curl_easy_init();
  mm = life_mime(e);
  LIVE("after_mime_built");
  mime_free(mm);
  LIVE("after_mime_free");
  IN_CALL("easy_cleanup", curl_easy_cleanup(e));
  LIVE("after_easy_cleanup");
  e = curl_easy_init();
  mm = life_mime(e);
  SAY("second: easy cleaned up first");
  IN_CALL("easy_cleanup", curl_easy_cleanup(e));
  LIVE("after_easy_cleanup");
  mime_free(mm);
  LIVE("after_mime_free");
}
/* L-free-midflight: a mime with an 8 MiB file part, to /slow (the server
   pauses its socket 1500 ms), freed 300 ms into the transfer. Unsafe by
   design: Valgrind shows what libcurl reads after. */
static curl_mime *g_mid;
static void mid_hook(xfer *x) {
  SAY("%s hook: curl_mime_free at t=%.1f, data_out so far=%ld", x->name, now_ms() - x->t_add, x->data_out[0]);
  mime_free(g_mid);
  g_mid = NULL;
}
static void l_midflight(void) {
  CURLM *m = curl_multi_init();
  xfer *x = mk("L-free-midflight", "/slow?ms=1500", 0, "Expect:");
  long s0 = ctl_seq();
  put_file(in_dir("mid.bin"), 8 << 20, 23);
  IN_CALL("mime_init", g_mid = curl_mime_init(x->h));
  part_data(g_mid, "field", (const unsigned char *)"value-1", 7);
  part_file(g_mid, "big", in_dir("mid.bin"));
  attach(x, g_mid);
  drive(m, x, 15000, mid_hook, 300);
  events("L-free-midflight", s0);
  drop(x);
  curl_multi_cleanup(m);
  LIVE("after_multi_cleanup");
}

/* ---------------------------------------------------------------- case 7 */
static void m_case(const char *name, int variant) {
  CURL *a = curl_easy_init();
  xfer *xb = mk(name, "/sink", 0, "Expect:");
  CURLM *m = curl_multi_init();
  curl_mime *mm;
  CURLcode rc;
  long s0;
  unsigned char *b = blob(3000, 24);
  LIVE("start");
  IN_CALL("mime_init", mm = curl_mime_init(variant == 3 ? NULL : a));
  SAY("curl_mime_init(%s) -> %s", variant == 3 ? "NULL" : "A", mm ? "a mime" : "NULL");
  if (!mm) { curl_easy_cleanup(a); drop(xb); curl_multi_cleanup(m); free(b); return; }
  part_data(mm, "field", (const unsigned char *)"value-1", 7);
  part_data(mm, "blob", b, 3000);
  expect_line("blob", b, 3000);
  free(b);
  if (variant == 2) { IN_CALL("easy_cleanup-A", curl_easy_cleanup(a)); a = NULL; SAY("A cleaned up before the mime is attached to B"); }
  if (variant == 4 || variant == 5) {
    IN_CALL("mimepost-A", rc = curl_easy_setopt(a, CURLOPT_MIMEPOST, mm));
    SAY("setopt MIMEPOST on A rc=%d (%s)", (int)rc, curl_easy_strerror(rc));
  }
  if (variant == 5) {
    CURLM *ma = curl_multi_init();
    xfer xa;
    memset(&xa, 0, sizeof xa);
    xa.h = a;
    snprintf(xa.name, sizeof xa.name, "%s.A", name);
    {
      char url[300];
      snprintf(url, sizeof url, "http://127.0.0.1:%d/sink?tag=%s.A", P_RAW, name);
      curl_easy_setopt(a, CURLOPT_URL, url);
      curl_easy_setopt(a, CURLOPT_PROXY, "");
      curl_easy_setopt(a, CURLOPT_WRITEFUNCTION, on_write);
      curl_easy_setopt(a, CURLOPT_WRITEDATA, &xa);
      curl_easy_setopt(a, CURLOPT_DEBUGFUNCTION, on_debug);
      curl_easy_setopt(a, CURLOPT_DEBUGDATA, &xa);
      curl_easy_setopt(a, CURLOPT_VERBOSE, 1L);
      xa.hl = curl_slist_append(NULL, "Expect:");
      curl_easy_setopt(a, CURLOPT_HTTPHEADER, xa.hl);
    }
    s0 = ctl_seq();
    drive(ma, &xa, 15000, NULL, 0);
    events(xa.name, s0);
    IN_CALL("easy_cleanup-A", curl_easy_cleanup(a)); a = NULL;
    curl_slist_free_all(xa.hl);
    curl_multi_cleanup(ma);
    SAY("A performed and cleaned up; now the mime goes to B");
  }
  IN_CALL("mimepost-B", rc = curl_easy_setopt(xb->h, CURLOPT_MIMEPOST, mm));
  SAY("setopt MIMEPOST on B rc=%d (%s)", (int)rc, curl_easy_strerror(rc));
  s0 = ctl_seq();
  drive(m, xb, 15000, NULL, 0);
  events(name, s0);
  drop(xb);
  if (a) IN_CALL("easy_cleanup-A", curl_easy_cleanup(a));
  mime_free(mm);
  curl_multi_cleanup(m);
  LIVE("after_all");
}
static void m_other_easy(void) { m_case("M-other-easy", 1); }
static void m_other_gone(void) { m_case("M-other-gone", 2); }
static void m_null_easy(void) { m_case("M-null-easy", 3); }
static void m_twice(void) { m_case("M-twice", 4); }
static void m_after_cleanup(void) { m_case("M-after-cleanup", 5); }

/* ---------------------------------------------------------------- case 8 */
static void features_line(void) {
  curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
  SAY("version runtime=%s age=%d features=0x%x ssl=%s", v->version, (int)v->age, (unsigned)v->features, v->ssl_version ? v->ssl_version : "-");
#ifdef CURLVERSION_ELEVENTH
  if (v->age >= CURLVERSION_ELEVENTH && v->feature_names) {
    char b[2000];
    size_t o = 0;
    const char *const *p;
    for (p = v->feature_names; *p; p++) o += (size_t)snprintf(b + o, sizeof b - o, "%s%s", o ? "," : "", *p);
    SAY("version feature_names=%s", o ? b : "-");
  }
#endif
}
static void d_calls(void) {
  CURL *e = curl_easy_init();
  curl_mime *mm;
  curl_mimepart *p;
  CURLcode rc;
  const struct curl_easyoption *o;
  struct curl_httppost *post = NULL, *last = NULL;
  int fr;
  features_line();
  put_file(in_dir("d.txt"), 100, 25);
  IN_CALL("mime_init", mm = curl_mime_init(e));
  SAY("curl_mime_init(easy) -> %s", mm ? "a mime" : "NULL");
  IN_CALL("addpart", p = curl_mime_addpart(mm));
  SAY("curl_mime_addpart -> %s", p ? "a part" : "NULL");
  rc = curl_mime_name(p, "field"); SAY("curl_mime_name rc=%d (%s)", (int)rc, curl_easy_strerror(rc));
  rc = curl_mime_data(p, "value-1", 7); SAY("curl_mime_data rc=%d (%s)", (int)rc, curl_easy_strerror(rc));
  rc = curl_mime_type(p, "text/plain"); SAY("curl_mime_type rc=%d (%s)", (int)rc, curl_easy_strerror(rc));
  rc = curl_mime_filename(p, "f.txt"); SAY("curl_mime_filename rc=%d (%s)", (int)rc, curl_easy_strerror(rc));
  {
    curl_mimepart *p2 = mm ? curl_mime_addpart(mm) : NULL;
    rc = curl_mime_filedata(p2, in_dir("d.txt")); SAY("curl_mime_filedata(%s) rc=%d (%s)", p2 ? "part" : "NULL", (int)rc, curl_easy_strerror(rc));
    if (p2) curl_mime_name(p2, "upload");
  }
  rc = curl_mime_name(NULL, "x"); SAY("curl_mime_name(NULL) rc=%d (%s)", (int)rc, curl_easy_strerror(rc));
  rc = curl_easy_setopt(e, CURLOPT_MIMEPOST, (curl_mime *)NULL); SAY("setopt MIMEPOST NULL rc=%d (%s)", (int)rc, curl_easy_strerror(rc));
  rc = curl_easy_setopt(e, CURLOPT_MIMEPOST, mm); SAY("setopt MIMEPOST init's answer (%s) rc=%d (%s)", mm ? "a mime" : "NULL", (int)rc, curl_easy_strerror(rc));
  o = curl_easy_option_by_name("MIMEPOST");
  SAY("curl_easy_option_by_name MIMEPOST -> %s id=%d type=%d", o ? "found" : "NULL", o ? (int)o->id : -1, o ? (int)o->type : -1);
  o = curl_easy_option_by_name("MIME_OPTIONS");
  SAY("curl_easy_option_by_name MIME_OPTIONS -> %s", o ? "found" : "NULL");
#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif
  fr = (int)curl_formadd(&post, &last, CURLFORM_COPYNAME, "a", CURLFORM_COPYCONTENTS, "b", CURLFORM_END);
  SAY("curl_formadd rc=%d post=%s", fr, post ? "set" : "NULL");
  {
    CURL *e2 = curl_easy_init();
    rc = curl_easy_setopt(e2, CURLOPT_HTTPPOST, post); SAY("setopt HTTPPOST rc=%d (%s)", (int)rc, curl_easy_strerror(rc));
    curl_easy_cleanup(e2);
  }
  if (post) curl_formfree(post);
#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif
  curl_easy_cleanup(e);
  curl_mime_free(mm);
  /* the transfers: the mime init gave (or NULL), and MIMEPOST NULL alone */
  {
    xfer *x = mk("D-send-init", "/sink", 0, "Expect:");
    curl_mime *m2;
    CURLM *m = curl_multi_init();
    long s0;
    IN_CALL("mime_init", m2 = curl_mime_init(x->h));
    if (m2) {
      curl_mimepart *q = curl_mime_addpart(m2);
      curl_mime_name(q, "field");
      curl_mime_data(q, "value-1", 7);
      q = curl_mime_addpart(m2);
      curl_mime_name(q, "upload");
      curl_mime_filedata(q, in_dir("d.txt"));
    }
    attach(x, m2);
    s0 = ctl_seq();
    drive(m, x, 15000, NULL, 0);
    events("D-send-init", s0);
    drop(x);
    if (m2) curl_mime_free(m2);
    curl_multi_cleanup(m);
  }
  {
    xfer *x = mk("D-send-mimepost-null", "/sink", 0, "Expect:");
    CURLM *m = curl_multi_init();
    long s0;
    attach(x, NULL);
    s0 = ctl_seq();
    drive(m, x, 15000, NULL, 0);
    events("D-send-mimepost-null", s0);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* ---------------------------------------------------------------- main */
static const struct { const char *name; void (*fn)(void); const char *kind; } CASES[] = {
  { "R-when", r_when, NULL }, { "R-big", r_big, NULL },
  { "C-missing", c_missing, NULL }, { "C-missing-made", c_missing_made, NULL }, { "C-removed", c_removed, NULL },
  { "C-unreadable-first", c_unreadable_first, NULL }, { "C-unreadable-later", c_unreadable_later, NULL },
  { "C-grown", c_grown, NULL }, { "C-shrunk", c_shrunk, NULL }, { "C-replaced", c_replaced, NULL },
  { "N-fifo", n_fifo, NULL }, { "N-fifo-late", n_fifo_late, NULL }, { "N-dir", n_dir, NULL }, { "N-devnull", n_devnull, NULL },
  { "N-stdin", n_stdin, NULL }, { "N-proc", n_proc, NULL }, { "N-relative", n_relative, NULL },
  { "X-417-data", x_417, "data" }, { "X-417-file", x_417, "file" }, { "X-417-pipe", x_417, "pipe" },
  { "X-late417-data", x_late417, "data" }, { "X-late417-file", x_late417, "file" }, { "X-late417-pipe", x_late417, "pipe" },
  { "X-idle-data", x_idle, "data" }, { "X-idle-file", x_idle, "file" }, { "X-idle-pipe", x_idle, "pipe" },
  { "X-idle1500-file", x_idle1500, "file" },
  { "X-drop-data", x_drop, "data" }, { "X-drop-file", x_drop, "file" }, { "X-drop-pipe", x_drop, "pipe" },
  { "X-drophead-data", x_drophead, "data" }, { "X-drophead-file", x_drophead, "file" }, { "X-drophead-pipe", x_drophead, "pipe" },
  { "X-drophead-big", x_drophead, "big" },
  { "X-digest-data", x_digest, "data" }, { "X-digest-file", x_digest, "file" }, { "X-digest-pipe", x_digest, "pipe" },
  { "X-stale-data", x_stale, "data" }, { "X-stale-file", x_stale, "file" }, { "X-stale-pipe", x_stale, "pipe" },
  { "X-refuse-end-data", x_refuse_end, "data" }, { "X-refuse-end-file", x_refuse_end, "file" }, { "X-refuse-end-pipe", x_refuse_end, "pipe" },
  { "X-refuse-head-data", x_refuse_head, "data" }, { "X-refuse-head-file", x_refuse_head, "file" }, { "X-refuse-head-pipe", x_refuse_head, "pipe" },
  { "X-refuse-head-big", x_refuse_head, "big" },
  { "F-307-data", f_307, "data" }, { "F-307-file", f_307, "file" }, { "F-307-pipe", f_307, "pipe" },
  { "F-308-data", f_308, "data" }, { "F-308-file", f_308, "file" }, { "F-308-pipe", f_308, "pipe" },
  { "L-cleanup-then-free", l_cleanup_then_free, NULL }, { "L-free-then-cleanup", l_free_then_cleanup, NULL },
  { "L-free-in-multi", l_free_in_multi, NULL }, { "L-free-before-transfer", l_free_before, NULL },
  { "L-null-then-free", l_null_then_free, NULL }, { "L-never-attached", l_never, NULL }, { "L-free-midflight", l_midflight, NULL },
  { "M-other-easy", m_other_easy, NULL }, { "M-other-gone", m_other_gone, NULL }, { "M-null-easy", m_null_easy, NULL },
  { "M-twice", m_twice, NULL }, { "M-after-cleanup", m_after_cleanup, NULL },
  { "D-calls", d_calls, NULL },
};

static void on_alarm(int s) {
  static const char msg[] = "alarm: the probe's own bound ran out\n";
  (void)s;
  if (write(1, msg, sizeof msg - 1) < 0) { /* nothing */ }
  _exit(3);
}

int main(int argc, char **argv) {
  CURLcode g;
  size_t i;
  const char *al = getenv("PROBE_ALARM");
  setvbuf(stdout, NULL, _IOLBF, 0);
  main_tid = tid_now();
  if (plain()) g = curl_global_init(CURL_GLOBAL_ALL);
  else g = curl_global_init_mem(CURL_GLOBAL_ALL, c_malloc, c_free, c_realloc, c_strdup, c_calloc);
  if (g) { printf("curl_global_init rc=%d\n", (int)g); return 1; }
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
    printf("version headers=%s runtime=%s ssl=%s features=0x%x age=%d\n", LIBCURL_VERSION, v->version, v->ssl_version ? v->ssl_version : "-",
           (unsigned)v->features, (int)v->age);
    curl_global_cleanup();
    return 0;
  }
  if (argc == 2 && !strcmp(argv[1], "--list")) {
    for (i = 0; i < sizeof CASES / sizeof CASES[0]; i++) printf("%s\n", CASES[i].name);
    return 0;
  }
  if (argc != 6) { fprintf(stderr, "usage: probe CASE CTL RAW H2C DIR | probe --version\n"); return 2; }
  P_CTL = atoi(argv[2]);
  P_RAW = atoi(argv[3]);
  P_H2C = atoi(argv[4]);
  DIR_ = argv[5];
  signal(SIGALRM, on_alarm);
  signal(SIGPIPE, SIG_IGN);
  alarm(al ? (unsigned)atoi(al) : 60);
  for (i = 0; i < sizeof CASES / sizeof CASES[0]; i++) {
    if (strcmp(argv[1], CASES[i].name)) continue;
    CASE = CASES[i].name;
    g_kind = CASES[i].kind;
    if (CASE[0] == 'C' && CASE[1] == '-') g_timeout = 5000;
    SAY("start plain=%d live=%lld", plain(), (long long)live_now());
    CASES[i].fn();
    SAY("all done live_before_global_cleanup=%lld", (long long)live_now());
    curl_global_cleanup();
    SAY("live_after_global_cleanup=%lld", (long long)live_now());
    return 0;
  }
  fprintf(stderr, "probe: no case %s\n", argv[1]);
  return 2;
}
