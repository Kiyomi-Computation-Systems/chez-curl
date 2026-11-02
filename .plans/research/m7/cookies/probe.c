/* M7's cookie probe (2026-11-02; the M7 plan's measurements).

     probe --version
     probe CASE PORT

   PORT is server.mjs's port, on 127.0.0.1 and ::1. CASE is one of the
   names in the table at the end of this file; run.sh runs them all.

   Every transfer goes through one multi handle per case, in a loop that
   mirrors chez-curl's engine turn: curl_multi_add_handle of a transfer
   whose time has come, curl_multi_perform, curl_multi_info_read (a done
   transfer is removed at once), then curl_multi_poll for at most 1000 ms,
   20 ms when a case watches a clock. Each transfer is a fresh easy handle,
   cleaned up once it has been reported, as the engine frees its own.

   Every transfer gets the engine's options: PROTOCOLS_STR and
   REDIR_PROTOCOLS_STR "http,https", NOSIGNAL 1, FOLLOWLOCATION 0 (but
   R-libcurl-follow), PROXY "", QUICK_EXIT 1 (option 322, by number: the
   floor's headers predate it, and its CURLE_UNKNOWN_OPTION is taken),
   ERRORBUFFER. Then, as the case says, CURLOPT_SHARE (a curl_share with
   CURL_LOCK_DATA_COOKIE alone, no lock callbacks, one thread) and
   COOKIEFILE "", the cookie engine with no file. COOKIEFILE and COOKIEJAR
   are never "-"; COOKIEJAR names a file only in F-flush-control, inside
   the scratch directory FLUSH_DIR.

   Output, to the file PROBE_LOG names (stdout when unset), so that stdout
   and stderr stay for libcurl alone: lines "case NAME ...".
     xfer=L url="..." done code=N status=S primary=IP
     xfer=L got LINE        the server's report of the request, its Cookie
                            headers whole: cookie "Cookie: ..."
     jar@L rc=N n=K         CURLINFO_COOKIELIST read through a handle
     jar@L line "..." exp=session | exp_delta=SECONDS (expiry - now)
     setopt / share / fs lines as they come.
   Bytes outside 0x20..0x7e, and \ and ", print as \xHH; a tab as \t.

   On Linux the probe interposes fopen, fopen64, open, open64, openat,
   openat64, __open_2, __open64_2, rename and unlink, and prints a line
   "fs FN step=STEP path=..." for every call made while a case runs, from
   libcurl or the probe: glibc's own internal opens do not go through them.
   F-flush-control and X-detector show the interposer seeing a file.
   Every case ends by reading fd 0 to its end and printing what was left
   ("stdin-left=N"): run.sh hands each case a pipe holding a known line,
   so a read of stdin by libcurl shows as bytes missing. */
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
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <netdb.h>
#include <curl/curl.h>
#ifdef __linux__
#include <dlfcn.h>
#endif

static int PORT;
static FILE *LOG;
static const char *CASE = "-";
static const char *STEP = "-";
static int fs_watch;

/* ---------------------------------------------------------------- output */
static char *esc_dup(const char *d, size_t n) {
  char *out = malloc(n * 4 + 1);
  size_t o = 0, i;
  if (!out) abort();
  for (i = 0; i < n; i++) {
    unsigned char c = (unsigned char)d[i];
    if (c == '\t') { out[o++] = '\\'; out[o++] = 't'; }
    else if (c == '\\' || c == '"' || c < 0x20 || c > 0x7e) o += (size_t)sprintf(out + o, "\\x%02x", c);
    else out[o++] = (char)c;
  }
  out[o] = 0;
  return out;
}

static void say(const char *fmt, ...) {
  va_list ap;
  fprintf(LOG, "case %s ", CASE);
  va_start(ap, fmt);
  vfprintf(LOG, fmt, ap);
  va_end(ap);
  fputc('\n', LOG);
  fflush(LOG);
}

/* ---------------------------------------------------------------- the file watch */
#ifdef __linux__
static void fs_note(const char *fn, const char *p) {
  char *e;
  if (!fs_watch || !LOG) return;
  e = esc_dup(p ? p : "(null)", p ? strlen(p) : 6);
  fprintf(LOG, "case %s fs %s step=%s path=\"%s\"\n", CASE, fn, STEP, e);
  fflush(LOG);
  free(e);
}
#define NEEDS_MODE(f) (((f) & O_CREAT) != 0 || NEEDS_TMPFILE(f))
#ifdef O_TMPFILE
#define NEEDS_TMPFILE(f) (((f) & O_TMPFILE) == O_TMPFILE)
#else
#define NEEDS_TMPFILE(f) 0
#endif
FILE *fopen(const char *p, const char *m) {
  static FILE *(*r)(const char *, const char *);
  if (!r) r = (FILE *(*)(const char *, const char *))dlsym(RTLD_NEXT, "fopen");
  fs_note("fopen", p);
  return r(p, m);
}
FILE *fopen64(const char *p, const char *m) {
  static FILE *(*r)(const char *, const char *);
  if (!r) r = (FILE *(*)(const char *, const char *))dlsym(RTLD_NEXT, "fopen64");
  fs_note("fopen64", p);
  return r(p, m);
}
#define OPEN_LIKE(NAME)                                                      \
  int NAME(const char *p, int f, ...) {                                      \
    static int (*r)(const char *, int, ...);                                 \
    mode_t md = 0;                                                           \
    if (!r) r = (int (*)(const char *, int, ...))dlsym(RTLD_NEXT, #NAME);    \
    if (NEEDS_MODE(f)) { va_list ap; va_start(ap, f); md = (mode_t)va_arg(ap, int); va_end(ap); } \
    fs_note(#NAME, p);                                                       \
    return r(p, f, md);                                                      \
  }
OPEN_LIKE(open)
OPEN_LIKE(open64)
#define OPENAT_LIKE(NAME)                                                    \
  int NAME(int d, const char *p, int f, ...) {                               \
    static int (*r)(int, const char *, int, ...);                            \
    mode_t md = 0;                                                           \
    if (!r) r = (int (*)(int, const char *, int, ...))dlsym(RTLD_NEXT, #NAME); \
    if (NEEDS_MODE(f)) { va_list ap; va_start(ap, f); md = (mode_t)va_arg(ap, int); va_end(ap); } \
    fs_note(#NAME, p);                                                       \
    return r(d, p, f, md);                                                   \
  }
OPENAT_LIKE(openat)
OPENAT_LIKE(openat64)
int __open_2(const char *p, int f) {
  static int (*r)(const char *, int);
  if (!r) r = (int (*)(const char *, int))dlsym(RTLD_NEXT, "__open_2");
  fs_note("__open_2", p);
  return r(p, f);
}
int __open64_2(const char *p, int f) {
  static int (*r)(const char *, int);
  if (!r) r = (int (*)(const char *, int))dlsym(RTLD_NEXT, "__open64_2");
  fs_note("__open64_2", p);
  return r(p, f);
}
int rename(const char *a, const char *b) {
  static int (*r)(const char *, const char *);
  if (!r) r = (int (*)(const char *, const char *))dlsym(RTLD_NEXT, "rename");
  fs_note("rename-from", a);
  fs_note("rename-to", b);
  return r(a, b);
}
int unlink(const char *p) {
  static int (*r)(const char *);
  if (!r) r = (int (*)(const char *))dlsym(RTLD_NEXT, "unlink");
  fs_note("unlink", p);
  return r(p);
}
#endif

/* ---------------------------------------------------------------- clocks */
static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

/* ---------------------------------------------------------------- transfers */
#define F_SHARE 1
#define F_FILE  2

typedef struct xfer {
  CURL *h;
  char label[64];
  char url[70000];
  char *resp;
  size_t resp_len, resp_cap;
  char err[CURL_ERROR_SIZE];
  struct curl_slist *hl;
  int added, done;
  CURLcode code;
  double add_at;
} xfer;

static size_t on_write(char *d, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t n = sz * nm;
  if (x->resp_len + n + 1 > x->resp_cap) {
    size_t cap = (x->resp_len + n + 1) * 2;
    char *r = realloc(x->resp, cap);
    if (!r) return 0;
    x->resp = r;
    x->resp_cap = cap;
  }
  memcpy(x->resp + x->resp_len, d, n);
  x->resp_len += n;
  x->resp[x->resp_len] = 0;
  return n;
}

#define SETOPT(x, opt, val) do { CURLcode rc_ = curl_easy_setopt((x)->h, opt, val); \
    if (rc_ != CURLE_OK) say("xfer=%s setopt %s rc=%d", (x)->label, #opt, (int)rc_); } while (0)

static void hexcat(char *dst, const char *bytes, size_t n) {
  static const char *hx = "0123456789abcdef";
  size_t o = strlen(dst), i;
  for (i = 0; i < n; i++) {
    unsigned char c = (unsigned char)bytes[i];
    dst[o++] = hx[c >> 4];
    dst[o++] = hx[c & 15];
  }
  dst[o] = 0;
}

/* url: http://HOST:PORT + PATH, then ?k=v pairs from Q. */
static void mkurl(char *out, size_t cap, const char *host, const char *path) {
  snprintf(out, cap, "http://%s:%d%s", host, PORT, path);
}
/* addq: append "&K=HEX(V)" or "?K=HEX(V)" to URL, V of length N. */
static void addq(char *url, const char *k, const char *v, size_t n) {
  strcat(url, strchr(url, '?') ? "&" : "?");
  strcat(url, k);
  strcat(url, "=");
  hexcat(url, v, n);
}
static void addsc(char *url, const char *v) { addq(url, "sc", v, strlen(v)); }
static void addplain(char *url, const char *kv) {
  strcat(url, strchr(url, '?') ? "&" : "?");
  strcat(url, kv);
}

static xfer *mk(const char *label, const char *url, int flags, CURLSH *sh) {
  xfer *x = calloc(1, sizeof *x);
  if (!x) abort();
  snprintf(x->label, sizeof x->label, "%s", label);
  snprintf(x->url, sizeof x->url, "%s", url);
  x->h = curl_easy_init();
  SETOPT(x, CURLOPT_URL, x->url);
  SETOPT(x, CURLOPT_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_NOSIGNAL, 1L);
  SETOPT(x, CURLOPT_FOLLOWLOCATION, 0L);
  SETOPT(x, CURLOPT_PROXY, "");
  {
    CURLcode rc = curl_easy_setopt(x->h, (CURLoption)322, 1L); /* QUICK_EXIT */
    if (rc != CURLE_OK && rc != CURLE_UNKNOWN_OPTION) say("xfer=%s setopt QUICK_EXIT rc=%d", x->label, (int)rc);
  }
  SETOPT(x, CURLOPT_ERRORBUFFER, x->err);
  SETOPT(x, CURLOPT_WRITEFUNCTION, on_write);
  SETOPT(x, CURLOPT_WRITEDATA, x);
  if ((flags & F_SHARE) && sh) SETOPT(x, CURLOPT_SHARE, sh);
  if (flags & F_FILE) SETOPT(x, CURLOPT_COOKIEFILE, "");
  return x;
}

static void drop(xfer *x) {
  if (!x) return;
  if (x->h) curl_easy_cleanup(x->h);
  if (x->hl) curl_slist_free_all(x->hl);
  free(x->resp);
  free(x);
}

/* drive: the engine's turn over XS until each is done, or BOUND ms pass.
   TICK, when given, runs every turn with the ms since the start. */
static void drive(CURLM *m, xfer **xs, int n, double bound, void (*tick)(double)) {
  double t0 = now_ms();
  int i;
  for (;;) {
    double t = now_ms() - t0, wait = 1000;
    int open = 0, running = 0, q;
    CURLMsg *msg;
    for (i = 0; i < n; i++)
      if (!xs[i]->added && t >= xs[i]->add_at) {
        CURLMcode mc = curl_multi_add_handle(m, xs[i]->h);
        xs[i]->added = 1;
        if (mc) say("xfer=%s multi_add rc=%d", xs[i]->label, (int)mc);
      }
    if (tick) tick(t);
    curl_multi_perform(m, &running);
    while ((msg = curl_multi_info_read(m, &q))) {
      if (msg->msg != CURLMSG_DONE) continue;
      for (i = 0; i < n; i++)
        if (xs[i]->h == msg->easy_handle && !xs[i]->done) {
          xs[i]->done = 1;
          xs[i]->code = msg->data.result;
          curl_multi_remove_handle(m, xs[i]->h);
        }
    }
    for (i = 0; i < n; i++) {
      if (!xs[i]->added) { open = 1; if (xs[i]->add_at - t < wait) wait = xs[i]->add_at - t; }
      else if (!xs[i]->done) open = 1;
    }
    if (!open) return;
    if (now_ms() - t0 > bound) {
      for (i = 0; i < n; i++)
        if (xs[i]->added && !xs[i]->done) {
          say("xfer=%s gave-up after %.0f ms, the probe's bound", xs[i]->label, bound);
          curl_multi_remove_handle(m, xs[i]->h);
          xs[i]->done = 1;
          xs[i]->code = (CURLcode)-1;
        }
      return;
    }
    if (tick && wait > 20) wait = 20;
    if (wait < 0) wait = 0;
    curl_multi_poll(m, NULL, 0, (int)wait, NULL);
  }
}

static void report(xfer *x) {
  long st = 0;
  char *ip = NULL, *line, *nl, *body;
  int saw_end = 0;
  curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
  curl_easy_getinfo(x->h, CURLINFO_PRIMARY_IP, &ip);
  {
    char *u = esc_dup(x->url, strlen(x->url));
    if (strlen(u) > 300) strcpy(u + 280, "...(long)");
    if (x->code)
      say("xfer=%s url=\"%s\" done code=%d err=\"%s\" status=%ld primary=%s", x->label, u, (int)x->code, x->err, st, ip ? ip : "-");
    else
      say("xfer=%s url=\"%s\" done code=0 status=%ld primary=%s", x->label, u, st, ip ? ip : "-");
    free(u);
  }
  if (!x->resp) { say("xfer=%s got nothing", x->label); return; }
  body = strdup(x->resp);
  for (line = body; *line; line = nl + 1) {
    nl = strchr(line, '\n');
    if (nl) *nl = 0;
    if (!strcmp(line, "end")) saw_end = 1;
    else say("xfer=%s got %s", x->label, line);
    if (!nl) break;
  }
  if (!saw_end) say("xfer=%s got no end line (%zu bytes)", x->label, x->resp_len);
  free(body);
}

/* one: run X alone on M, report it, and leave it for the caller. */
static void one(CURLM *m, xfer *x) {
  drive(m, &x, 1, 10000, NULL);
  report(x);
}

static long long field_expiry(const char *line) {
  const char *p = line;
  int f;
  if (!strncmp(p, "#HttpOnly_", 10)) p += 10;
  for (f = 0; f < 4; f++) {
    p = strchr(p, '\t');
    if (!p) return -1;
    p++;
  }
  return atoll(p);
}

/* jar: CURLINFO_COOKIELIST through H, every line whole. */
static int jar_lines(CURL *h, const char *label, int print) {
  struct curl_slist *l = NULL, *e;
  CURLcode rc = curl_easy_getinfo(h, CURLINFO_COOKIELIST, &l);
  int n = 0;
  time_t now = time(NULL);
  for (e = l; e; e = e->next) n++;
  say("jar@%s rc=%d n=%d", label, (int)rc, n);
  if (print) {
    for (e = l; e; e = e->next) {
      char *s = esc_dup(e->data, strlen(e->data));
      long long ex = field_expiry(e->data);
      if (ex == 0) say("jar@%s line \"%s\" exp=session", label, s);
      else say("jar@%s line \"%s\" exp_delta=%lld", label, s, ex - (long long)now);
      free(s);
    }
  } else if (l) {
    struct curl_slist *last = l;
    char *s = esc_dup(l->data, strlen(l->data));
    while (last->next) last = last->next;
    say("jar@%s first \"%s\"", label, s);
    free(s);
    s = esc_dup(last->data, strlen(last->data));
    say("jar@%s last \"%s\"", label, s);
    free(s);
  }
  curl_slist_free_all(l);
  return n;
}
static void jar(CURL *h, const char *label) { jar_lines(h, label, 1); }

static CURLSH *new_share(const char *label) {
  CURLSH *s = curl_share_init();
  CURLSHcode rc = curl_share_setopt(s, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);
  say("share %s init rc=%d", label, (int)rc);
  return s;
}
static void end_share(CURLSH *s, const char *label) {
  CURLSHcode rc = curl_share_cleanup(s);
  say("share %s cleanup rc=%d (%s)", label, (int)rc, curl_share_strerror(rc));
}

/* get: a fresh transfer LABEL to HOST PATH with FLAGS on SH, run alone,
   reported, its jar printed when PRINTJAR, then freed. */
static void get(CURLM *m, CURLSH *sh, const char *label, const char *host, const char *path, int flags, int printjar) {
  char u[2000];
  xfer *x;
  mkurl(u, sizeof u, host, path);
  x = mk(label, u, flags, sh);
  one(m, x);
  if (printjar) jar(x->h, label);
  drop(x);
}

/* setter: a fresh transfer to HOST PATH answering each of SCS[0..N) as a
   Set-Cookie, reported, the jar printed through it, then freed. */
static void setter(CURLM *m, CURLSH *sh, const char *label, const char *host, const char *path, const char **scs, int n) {
  char *u = malloc(70000);
  int i;
  xfer *x;
  mkurl(u, 70000, host, path);
  for (i = 0; i < n; i++) addsc(u, scs[i]);
  x = mk(label, u, F_SHARE | F_FILE, sh);
  one(m, x);
  jar(x->h, label);
  drop(x);
  free(u);
}

static void cookielist(xfer *x, const char *line) {
  CURLcode rc = curl_easy_setopt(x->h, CURLOPT_COOKIELIST, line);
  char *s = esc_dup(line, strlen(line));
  say("xfer=%s COOKIELIST \"%s\" rc=%d", x->label, s, (int)rc);
  free(s);
}

static void httpdate(char *out, size_t cap, long long delta) {
  time_t t = time(NULL) + (time_t)delta;
  struct tm g;
  gmtime_r(&t, &g);
  strftime(out, cap, "%a, %d %b %Y %H:%M:%S GMT", &g);
}

#define NELEM(a) ((int)(sizeof(a) / sizeof((a)[0])))

/* ================================================================ item 1 */

/* S-*: T1 to a.localhost sets host1 (host-only) and dom1 (Domain=a.localhost);
   T2 a.localhost, T3 b.a.localhost, T4 localhost. MODE: share 1 or 0;
   file: 0 none, 1 every transfer, 2 T1 alone, 3 every transfer but T1. */
static void s_variant(int share, int file) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = share ? new_share("S") : NULL;
  const char *hosts[4] = { "a.localhost", "a.localhost", "b.a.localhost", "localhost" };
  const char *paths[4] = { "/s1", "/s2", "/s3", "/s4" };
  int i;
  for (i = 0; i < 4; i++) {
    char u[2000], label[16];
    int flags = share ? F_SHARE : 0;
    xfer *x;
    if (file == 1 || (file == 2 && i == 0) || (file == 3 && i > 0)) flags |= F_FILE;
    mkurl(u, sizeof u, hosts[i], paths[i]);
    if (i == 0) { addsc(u, "host1=v1"); addsc(u, "dom1=v1; Domain=a.localhost"); }
    snprintf(label, sizeof label, "T%d", i + 1);
    x = mk(label, u, flags, sh);
    say("xfer=%s share=%d cookiefile=%d", label, share, (flags & F_FILE) != 0);
    one(m, x);
    jar(x->h, label);
    drop(x);
  }
  curl_multi_cleanup(m);
  if (sh) end_share(sh, "S");
}
static void s_share(void) { s_variant(1, 1); }
static void s_noshare(void) { s_variant(0, 1); }
static void s_nofile(void) { s_variant(1, 0); }
static void s_file_first(void) { s_variant(1, 2); }
static void s_file_later(void) { s_variant(1, 3); }

/* S-live: A (answers at once), B (answers at 600 ms) and C (added at 250
   ms, answers 800 ms after its request), live together on one multi
   handle, one share, no lock callbacks. A sets la and same=A, B lb and
   same=B, C lc. At 400 ms the jar is read through B's handle (A done, B
   live); at 1000 ms through C's (B done, C live). D, after all, sends
   what the jar holds. */
static xfer *g_live[3];
static int g_tick1, g_tick2;
static void live_tick(double t) {
  if (!g_tick1 && t >= 400) {
    g_tick1 = 1;
    say("tick t=%.0f A.done=%d B.done=%d C.added=%d C.done=%d", t, g_live[0]->done, g_live[1]->done, g_live[2]->added, g_live[2]->done);
    jar(g_live[1]->h, "B-live");
  }
  if (!g_tick2 && t >= 1000) {
    g_tick2 = 1;
    say("tick t=%.0f A.done=%d B.done=%d C.done=%d", t, g_live[0]->done, g_live[1]->done, g_live[2]->done);
    jar(g_live[2]->h, "C-live");
  }
}
static void s_live(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("S");
  char ua[2000], ub[2000], uc[2000];
  int i;
  mkurl(ua, sizeof ua, "a.localhost", "/la");
  addsc(ua, "la=1"); addsc(ua, "same=A");
  mkurl(ub, sizeof ub, "a.localhost", "/lb?delay=600");
  addsc(ub, "lb=1"); addsc(ub, "same=B");
  mkurl(uc, sizeof uc, "a.localhost", "/lc?delay=800");
  addsc(uc, "lc=1");
  g_live[0] = mk("A", ua, F_SHARE | F_FILE, sh);
  g_live[1] = mk("B", ub, F_SHARE | F_FILE, sh);
  g_live[2] = mk("C", uc, F_SHARE | F_FILE, sh);
  g_live[2]->add_at = 250;
  drive(m, g_live, 3, 10000, live_tick);
  for (i = 0; i < 3; i++) report(g_live[i]);
  jar(g_live[2]->h, "after");
  for (i = 0; i < 3; i++) drop(g_live[i]);
  get(m, sh, "D", "a.localhost", "/ld", F_SHARE | F_FILE, 1);
  curl_multi_cleanup(m);
  end_share(sh, "S");
}

/* S-cleanup: what curl_share_cleanup answers while a handle holds the
   share: live in the multi, done but not cleaned up, detached by
   CURLOPT_SHARE NULL, and after every handle is gone. */
static CURLSH *g_cl_share;
static int g_cl_ticked;
static void cleanup_tick(double t) {
  if (!g_cl_ticked && t >= 200) {
    CURLSHcode rc;
    g_cl_ticked = 1;
    rc = curl_share_cleanup(g_cl_share);
    say("share L cleanup-while-live t=%.0f rc=%d (%s)", t, (int)rc, curl_share_strerror(rc));
  }
}
static void s_cleanup(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("K");
  char u[2000];
  xfer *h1, *h2, *h3;
  CURLSHcode rc;
  CURLcode src;
  mkurl(u, sizeof u, "localhost", "/k1");
  addsc(u, "k=1");
  h1 = mk("h1", u, F_SHARE | F_FILE, sh);
  one(m, h1);
  rc = curl_share_cleanup(sh);
  say("share K cleanup-while-h1-holds rc=%d (%s)", (int)rc, curl_share_strerror(rc));
  jar(h1->h, "h1-after-refused-cleanup");
  mkurl(u, sizeof u, "localhost", "/k2");
  h2 = mk("h2", u, F_SHARE | F_FILE, sh);
  drop(h1);
  rc = curl_share_cleanup(sh);
  say("share K cleanup-while-h2-holds-h1-gone rc=%d (%s)", (int)rc, curl_share_strerror(rc));
  jar(h2->h, "h2-attached");
  src = curl_easy_setopt(h2->h, CURLOPT_SHARE, (CURLSH *)NULL);
  say("xfer=h2 setopt SHARE NULL rc=%d", (int)src);
  jar(h2->h, "h2-detached");
  rc = curl_share_cleanup(sh);
  say("share K cleanup-after-detach rc=%d (%s)", (int)rc, curl_share_strerror(rc));
  one(m, h2);
  jar(h2->h, "h2-detached-after-transfer");
  drop(h2);
  /* L: a live holder */
  g_cl_share = new_share("L");
  mkurl(u, sizeof u, "localhost", "/k3?delay=500");
  addsc(u, "k3=1");
  h3 = mk("h3", u, F_SHARE | F_FILE, g_cl_share);
  drive(m, &h3, 1, 10000, cleanup_tick);
  report(h3);
  jar(h3->h, "h3");
  drop(h3);
  end_share(g_cl_share, "L");
  curl_multi_cleanup(m);
}

/* ================================================================ item 2 */

typedef struct { const char *host, *path; } tgt;

static void probes(CURLM *m, CURLSH *sh, const tgt *t, int n) {
  int i;
  for (i = 0; i < n; i++) {
    char label[160];
    snprintf(label, sizeof label, "to:%s%s", t[i].host, t[i].path);
    get(m, sh, label, t[i].host, t[i].path, F_SHARE | F_FILE, 0);
  }
}

static void matrix(const char *set_host, const char *set_path, const char **scs, int nsc, const tgt *t, int nt) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("M");
  char label[160];
  snprintf(label, sizeof label, "set:%s%s", set_host, set_path);
  setter(m, sh, label, set_host, set_path, scs, nsc);
  probes(m, sh, t, nt);
  curl_multi_cleanup(m);
  end_share(sh, "M");
}

static void m_domain_a(void) {
  const char *sc[] = { "d_none=1", "d_lh=1; Domain=localhost", "d_dotlh=1; Domain=.localhost",
    "d_self=1; Domain=a.localhost", "d_dotself=1; Domain=.a.localhost", "d_child=1; Domain=b.a.localhost",
    "d_sib=1; Domain=b.localhost", "d_unrel=1; Domain=example.com", "d_ip=1; Domain=127.0.0.1",
    "d_empty=1; Domain=", "d_case=1; Domain=A.LOCALHOST" };
  const tgt t[] = { { "a.localhost", "/" }, { "b.a.localhost", "/" }, { "localhost", "/" }, { "b.localhost", "/" }, { "127.0.0.1", "/" } };
  matrix("a.localhost", "/", sc, NELEM(sc), t, NELEM(t));
}
static void m_domain_ba(void) {
  const char *sc[] = { "p_none=1", "p_parent=1; Domain=a.localhost", "p_dotparent=1; Domain=.a.localhost", "p_lh=1; Domain=localhost" };
  const tgt t[] = { { "b.a.localhost", "/" }, { "a.localhost", "/" }, { "c.a.localhost", "/" }, { "localhost", "/" } };
  matrix("b.a.localhost", "/", sc, NELEM(sc), t, NELEM(t));
}
static void m_domain_lh(void) {
  const char *sc[] = { "l_none=1", "l_lh=1; Domain=localhost", "l_dotlh=1; Domain=.localhost", "l_sub=1; Domain=a.localhost" };
  const tgt t[] = { { "localhost", "/" }, { "a.localhost", "/" }, { "b.a.localhost", "/" }, { "127.0.0.1", "/" } };
  matrix("localhost", "/", sc, NELEM(sc), t, NELEM(t));
}
static void m_domain_ip(void) {
  const char *sc[] = { "i_none=1", "i_self=1; Domain=127.0.0.1", "i_other=1; Domain=127.0.0.2", "i_lh=1; Domain=localhost", "i_tail=1; Domain=0.0.1" };
  const tgt t[] = { { "127.0.0.1", "/" }, { "localhost", "/" } };
  matrix("127.0.0.1", "/", sc, NELEM(sc), t, NELEM(t));
}
static void m_path(void) {
  const char *sc[] = { "p_def=1", "p_a=1; Path=/a", "p_aslash=1; Path=/a/", "p_ab=1; Path=/a/b", "p_x=1; Path=/x",
    "p_root=1; Path=/", "p_rel=1; Path=rel", "p_upper=1; Path=/A", "p_empty=1; Path=" };
  const tgt t[] = { { "localhost", "/" }, { "localhost", "/a" }, { "localhost", "/a/" }, { "localhost", "/a/b" }, { "localhost", "/a/b/" },
    { "localhost", "/a/b/c" }, { "localhost", "/ab" }, { "localhost", "/A" }, { "localhost", "/x/y" }, { "localhost", "/a/bc" } };
  matrix("localhost", "/a/b/page", sc, NELEM(sc), t, NELEM(t));
}

/* M-secure: Secure over http:// from localhost, a.localhost and 127.0.0.1,
   each beside a plain one; then a Netscape line with secure TRUE for
   a.localhost loaded by COOKIELIST; then each host asked over http. */
static void m_secure(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("M");
  const char *sl[] = { "sec_lh=1; Secure", "nsec_lh=1" };
  const char *sa[] = { "sec_a=1; Secure", "nsec_a=1" };
  const char *si[] = { "sec_ip=1; Secure", "nsec_ip=1" };
  const tgt t[] = { { "localhost", "/" }, { "a.localhost", "/" }, { "127.0.0.1", "/" } };
  char u[2000];
  xfer *x;
  setter(m, sh, "set:localhost/", "localhost", "/", sl, 2);
  setter(m, sh, "set:a.localhost/", "a.localhost", "/", sa, 2);
  setter(m, sh, "set:127.0.0.1/", "127.0.0.1", "/", si, 2);
  mkurl(u, sizeof u, "a.localhost", "/");
  x = mk("import", u, F_SHARE | F_FILE, sh);
  cookielist(x, "a.localhost\tFALSE\t/\tTRUE\t0\timp_sec_a\t1");
  cookielist(x, "Set-Cookie: imp_sc_sec_a=1; Domain=a.localhost; Secure");
  jar(x->h, "import");
  drop(x);
  probes(m, sh, t, NELEM(t));
  curl_multi_cleanup(m);
  end_share(sh, "M");
}

static void m_expiry(void) {
  char past[64], fut[64], far[64], d401[64], d399[64];
  char b[14][160];
  const char *sc[14];
  const tgt t[] = { { "localhost", "/" } };
  int i = 0;
  httpdate(past, sizeof past, -86400);
  httpdate(fut, sizeof fut, 86400);
  httpdate(far, sizeof far, 1000LL * 86400);
  httpdate(d401, sizeof d401, 401LL * 86400);
  httpdate(d399, sizeof d399, 399LL * 86400);
  snprintf(b[i++], 160, "e_past=1; Expires=%s", past);
  snprintf(b[i++], 160, "e_fut=1; Expires=%s", fut);
  snprintf(b[i++], 160, "e_far=1; Expires=%s", far);
  snprintf(b[i++], 160, "e_401=1; Expires=%s", d401);
  snprintf(b[i++], 160, "e_399=1; Expires=%s", d399);
  snprintf(b[i++], 160, "m_zero=1; Max-Age=0");
  snprintf(b[i++], 160, "m_neg=1; Max-Age=-1");
  snprintf(b[i++], 160, "m_day=1; Max-Age=86400");
  snprintf(b[i++], 160, "m_far=1; Max-Age=86400000");
  snprintf(b[i++], 160, "m_huge=1; Max-Age=99999999999999999999");
  snprintf(b[i++], 160, "mx_ma60_expast=1; Max-Age=60; Expires=%s", past);
  snprintf(b[i++], 160, "mx_exfut_ma0=1; Expires=%s; Max-Age=0", fut);
  snprintf(b[i++], 160, "e_bad=1; Expires=notadate");
  snprintf(b[i++], 160, "e_session=1");
  for (i = 0; i < 14; i++) sc[i] = b[i];
  matrix("localhost", "/", sc, 14, t, NELEM(t));
}

static void m_attrs(void) {
  const char *sc[] = { "h_only=1; HttpOnly", "h_lower=1; httponly", "ss_strict=1; SameSite=Strict", "ss_lax=1; SameSite=Lax",
    "ss_none=1; SameSite=None", "ss_none_sec=1; SameSite=None; Secure", "ss_bogus=1; SameSite=Bogus",
    "__Secure-pre=1; Secure", "__Secure-nosec=1", "__Host-ok=1; Secure; Path=/", "__Host-dom=1; Secure; Path=/; Domain=localhost",
    "__Host-nopath=1; Secure", "unk=1; Foo=bar; Partitioned" };
  const tgt t[] = { { "localhost", "/" } };
  matrix("localhost", "/", sc, NELEM(sc), t, NELEM(t));
}

static void m_overwrite(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("M");
  const char *s1[] = { "dup=1", "dup2=a", "dup2=b", "pd=1; Path=/p", "pd=2", "dd=host", "dd=dom; Domain=a.localhost" };
  const char *s2[] = { "dup=2" };
  const tgt t[] = { { "a.localhost", "/" }, { "a.localhost", "/p" }, { "b.a.localhost", "/" } };
  setter(m, sh, "set1:a.localhost/", "a.localhost", "/", s1, NELEM(s1));
  setter(m, sh, "set2:a.localhost/", "a.localhost", "/", s2, NELEM(s2));
  probes(m, sh, t, NELEM(t));
  curl_multi_cleanup(m);
  end_share(sh, "M");
}

static void m_delete(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("M");
  const char *s1[] = { "del_ma=1; Max-Age=3600", "del_ex=1; Max-Age=3600", "del_path=1; Path=/p", "del_sess=1", "keep=1" };
  const char *s2[] = { "del_ma=; Max-Age=0", "del_ex=x; Expires=Thu, 01 Jan 1970 00:00:00 GMT", "del_path=; Max-Age=0",
    "del_sess=gone; Max-Age=-1" };
  const tgt t[] = { { "localhost", "/" }, { "localhost", "/p" } };
  setter(m, sh, "set1:localhost/", "localhost", "/", s1, NELEM(s1));
  probes(m, sh, t, NELEM(t));
  setter(m, sh, "set2:localhost/", "localhost", "/", s2, NELEM(s2));
  probes(m, sh, t, NELEM(t));
  curl_multi_cleanup(m);
  end_share(sh, "M");
}

static void m_invalid(void) {
  static char lng[4200], fit[4200], line[5200], nm[4200];
  const char *sc[20];
  const tgt t[] = { { "localhost", "/" } };
  int i = 0;
  strcpy(lng, "v_4101=");  memset(lng + 7, 'x', 4094); lng[7 + 4094] = 0;   /* name 6 + value 4094 = 4100 > 4096 */
  strcpy(fit, "v_4090=");  memset(fit + 7, 'x', 4084); fit[7 + 4084] = 0;   /* name 6 + value 4084 = 4090 */
  strcpy(line, "v_line=1; Path=/; Comment="); memset(line + 26, 'c', 5000); line[26 + 5000] = 0;
  memset(nm, 'n', 4096); strcpy(nm + 4096, "=1");                            /* name 4096 */
  sc[i++] = "";
  sc[i++] = "=noname";
  sc[i++] = "noequals";
  sc[i++] = "n v=1";
  sc[i++] = "n\tt=1";
  sc[i++] = "ctl=a\x01" "b";
  sc[i++] = "dl=a\x7f" "b";
  sc[i++] = "tabv=a\tb";
  sc[i++] = "sp=a b";
  sc[i++] = "lead=  padded  ";
  sc[i++] = "quote=\"q v\"";
  sc[i++] = "semi=a;b";
  sc[i++] = "empty=";
  sc[i++] = ";;;";
  sc[i++] = "dom_dots=1; Domain=..localhost";
  sc[i++] = lng;
  sc[i++] = fit;
  sc[i++] = line;
  sc[i++] = nm;
  matrix("localhost", "/", sc, i, t, NELEM(t));
}

/* M-header-forms: Set-Cookie header lines spelt other ways, by h=. */
static void m_header_forms(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("M");
  const char *hs[] = { "set-cookie: hf_lower=1", "SET-COOKIE: hf_upper=1", "Set-Cookie:hf_nospace=1", "Set-Cookie:    hf_spaces=1",
    "Set-Cookie:", "Set-Cookie2: hf_two=1", "Set-Cookie: hf_a=1, hf_b=2" };
  char *u = malloc(70000);
  xfer *x;
  int i;
  mkurl(u, 70000, "localhost", "/");
  for (i = 0; i < NELEM(hs); i++) addq(u, "h", hs[i], strlen(hs[i]));
  x = mk("set:localhost/", u, F_SHARE | F_FILE, sh);
  one(m, x);
  jar(x->h, "set:localhost/");
  drop(x);
  get(m, sh, "to:localhost/", "localhost", "/", F_SHARE | F_FILE, 0);
  free(u);
  curl_multi_cleanup(m);
  end_share(sh, "M");
}

static void m_highbyte(void) {
  const char *sc[] = { "hb_utf8=caf\xc3\xa9", "hb_latin=\xe9", "hb_ff=\xff\xfe", "n\xc3\xa9=1", "hb_mid=a\xe2\x80\x8b" "b" };
  const tgt t[] = { { "localhost", "/" } };
  matrix("localhost", "/", sc, NELEM(sc), t, NELEM(t));
}

/* M-many: per-response, per-request and size caps, and the jar's own count. */
static void many_set(CURLM *m, CURLSH *sh, const char *label, const char *host, const char *path, int n, const char *prefix, int size) {
  char u[2000], kv[200];
  xfer *x;
  mkurl(u, sizeof u, host, path);
  snprintf(kv, sizeof kv, "many=%d&mname=%s&msize=%d", n, prefix, size);
  addplain(u, kv);
  x = mk(label, u, F_SHARE | F_FILE, sh);
  drive(m, &x, 1, 10000, NULL);
  {
    long st = 0;
    curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
    say("xfer=%s many=%d prefix=%s size=%d done code=%d status=%ld", label, n, prefix, size, (int)x->code, st);
  }
  jar_lines(x->h, label, 0);
  drop(x);
}
static void many_get(CURLM *m, CURLSH *sh, const char *label, const char *host, const char *path) {
  char u[2000];
  xfer *x;
  char *line, *nl, *body;
  mkurl(u, sizeof u, host, path);
  x = mk(label, u, F_SHARE | F_FILE, sh);
  drive(m, &x, 1, 10000, NULL);
  say("xfer=%s done code=%d", label, (int)x->code);
  body = x->resp ? strdup(x->resp) : strdup("");
  for (line = body; *line; line = nl + 1) {
    nl = strchr(line, '\n');
    if (nl) *nl = 0;
    if (!strncmp(line, "cookie ", 7) || !strncmp(line, "cookie-headers", 14)) {
      if (!strncmp(line, "cookie \"", 8)) {
        /* the pairs: count them, and the whole line's length, as received */
        int pairs = 1;
        size_t len = strlen(line) - 9, k;  /* less: cookie "  and the closing quote */
        for (k = 0; line[k]; k++) if (line[k] == ';') pairs++;
        say("xfer=%s cookie-line bytes=%zu pairs=%d", label, len, pairs);
        /* the names sent, tallied by their prefix up to the first '_' */
        {
          char pre[64][16], tally[1200] = "";
          int cnt[64], np = 0, j;
          char *q = strstr(line, "Cookie: ");
          q = q ? q + 8 : line;
          while (*q && *q != '"') {
            char nm[16];
            size_t w = 0;
            while (q[w] && q[w] != '_' && q[w] != '=' && w < sizeof nm - 2) { nm[w] = q[w]; w++; }
            nm[w] = '_';
            nm[w + 1] = 0;
            for (j = 0; j < np; j++) if (!strcmp(pre[j], nm)) break;
            if (j == np && np < 64) { snprintf(pre[np], sizeof pre[np], "%s", nm); cnt[np++] = 0; }
            if (j < 64) cnt[j]++;
            q = strstr(q, "; ");
            if (!q) break;
            q += 2;
          }
          for (j = 0; j < np; j++) {
            char one[40];
            snprintf(one, sizeof one, " %s=%d", pre[j], cnt[j]);
            strcat(tally, one);
          }
          say("xfer=%s sent-by-prefix%s", label, tally);
        }
      }
      say("xfer=%s got %s", label, line);
    }
    if (!nl) break;
  }
  free(body);
  drop(x);
}
static void m_many(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("M");
  int r;
  /* one response with 60 Set-Cookie lines, on localhost /one */
  many_set(m, sh, "set60:localhost/one", "localhost", "/one", 60, "ma_", 1);
  many_get(m, sh, "to:localhost/one", "localhost", "/one");
  /* 4 responses of 50 each on a.localhost: 200 in the jar */
  for (r = 0; r < 4; r++) {
    char label[64], prefix[16];
    snprintf(label, sizeof label, "set50#%d:a.localhost/", r);
    snprintf(prefix, sizeof prefix, "mb%d_", r);
    many_set(m, sh, label, "a.localhost", "/", 50, prefix, 1);
  }
  many_get(m, sh, "to:a.localhost/", "a.localhost", "/");
  /* 3 responses of 10 cookies of 1000 bytes on b.localhost: over 8190 */
  for (r = 0; r < 3; r++) {
    char label[64], prefix[16];
    snprintf(label, sizeof label, "set10x1000#%d:b.localhost/", r);
    snprintf(prefix, sizeof prefix, "mc%d_", r);
    many_set(m, sh, label, "b.localhost", "/", 10, prefix, 1000);
  }
  many_get(m, sh, "to:b.localhost/", "b.localhost", "/");
  /* 20 responses of 50 on b.a.localhost: 1000 in the jar */
  for (r = 0; r < 20; r++) {
    char label[64], prefix[16];
    snprintf(label, sizeof label, "set50#%d:b.a.localhost/", r);
    snprintf(prefix, sizeof prefix, "md%d_", r);
    many_set(m, sh, label, "b.a.localhost", "/", 50, prefix, 1);
  }
  many_get(m, sh, "to:b.a.localhost/", "b.a.localhost", "/");
  curl_multi_cleanup(m);
  end_share(sh, "M");
}

/* ================================================================ item 3 */

static void import_and_probe(const char **lines, int n) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("I");
  const tgt t[] = { { "localhost", "/" }, { "localhost", "/p" }, { "a.localhost", "/" }, { "b.a.localhost", "/" }, { "b.localhost", "/" },
    { "127.0.0.1", "/" }, { "127.0.0.1", "/p" }, { "[::1]", "/" } };
  char u[2000];
  xfer *x;
  int i;
  mkurl(u, sizeof u, "localhost", "/");
  x = mk("import", u, F_SHARE | F_FILE, sh);
  for (i = 0; i < n; i++) cookielist(x, lines[i]);
  jar(x->h, "import");
  drop(x);
  probes(m, sh, t, NELEM(t));
  mkurl(u, sizeof u, "localhost", "/");
  x = mk("after", u, F_SHARE | F_FILE, sh);
  jar(x->h, "after");
  drop(x);
  curl_multi_cleanup(m);
  end_share(sh, "I");
}

static void i_netscape(void) {
  char fut[64], b[16][200];
  const char *l[16];
  int i = 0, k;
  snprintf(fut, sizeof fut, "%lld", (long long)time(NULL) + 86400);
  snprintf(b[i++], 200, "localhost\tFALSE\t/\tFALSE\t0\tns_sess\tv1");
  snprintf(b[i++], 200, ".localhost\tTRUE\t/\tFALSE\t%s\tns_dottail\tv2", fut);
  snprintf(b[i++], 200, "#HttpOnly_localhost\tFALSE\t/\tFALSE\t0\tns_httponly\tv3");
  snprintf(b[i++], 200, "localhost\tFALSE\t/p\tTRUE\t%s\tns_secpath\tv4", fut);
  snprintf(b[i++], 200, "a.localhost\tTRUE\t/\tFALSE\t0\tns_tail\tv5");
  snprintf(b[i++], 200, "localhost\tFALSE\t/\tFALSE\t0\tns_novalue");
  snprintf(b[i++], 200, "localhost\tFALSE\t/\tFALSE\t1\tns_expired\tv7");
  snprintf(b[i++], 200, "localhost FALSE / FALSE 0 ns_spaces v8");
  snprintf(b[i++], 200, "127.0.0.1\tFALSE\t/\tFALSE\t0\tns_ip\tv9");
  snprintf(b[i++], 200, "localhost\tTRUE\t/\tFALSE\t0\tns_lhtail\tv10");
  snprintf(b[i++], 200, "# a comment line");
  snprintf(b[i++], 200, "localhost\tFALSE\t/\tFALSE\t0\tns_val_tab\ta\tb");
  snprintf(b[i++], 200, "localhost\tFALSE\t/\tFALSE\t99999999999\tns_far\tv13");
  for (k = 0; k < i; k++) l[k] = b[k];
  import_and_probe(l, i);
}

static void i_setcookie(void) {
  const char *l[] = { "Set-Cookie: sc_nodomain=v1", "Set-Cookie: sc_lh=v2; Domain=localhost", "Set-Cookie: sc_a=v3; Domain=a.localhost; Path=/p; HttpOnly; Max-Age=3600",
    "set-cookie: sc_lowerprefix=v4; Domain=localhost", "Set-Cookie:sc_nospace=v5; Domain=localhost", "Set-Cookie: sc_sec=v6; Domain=localhost; Secure",
    "Set-Cookie: sc_ip=v7; Domain=127.0.0.1", "Set-Cookie: sc_nodomain_path=v8; Path=/p" };
  import_and_probe(l, NELEM(l));
}

/* I-commands: ALL, SESS, FLUSH, RELOAD, on a handle with the share and
   COOKIEFILE "", no COOKIEJAR; and on a bare handle. The fs and stdin
   lines show what each touched. */
static void i_commands(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("I");
  const char *sc[] = { "t_sess=1", "t_pers=1; Max-Age=3600" };
  const char *cmds[] = { "SESS", "FLUSH", "RELOAD", "ALL" };
  char u[2000], lab[64];
  xfer *x, *bare;
  int i;
  setter(m, sh, "set:localhost/", "localhost", "/", sc, 2);
  mkurl(u, sizeof u, "localhost", "/");
  x = mk("cmd", u, F_SHARE | F_FILE, sh);
  cookielist(x, "localhost\tFALSE\t/\tFALSE\t0\timp_sess\t1");
  {
    char line[200];
    snprintf(line, sizeof line, "localhost\tFALSE\t/\tFALSE\t%lld\timp_pers\t1", (long long)time(NULL) + 3600);
    cookielist(x, line);
  }
  jar(x->h, "before");
  for (i = 0; i < 4; i++) {
    STEP = cmds[i];
    cookielist(x, cmds[i]);
    STEP = "-";
    snprintf(lab, sizeof lab, "after-%s", cmds[i]);
    jar(x->h, lab);
  }
  drop(x);
  get(m, sh, "to:localhost/", "localhost", "/", F_SHARE | F_FILE, 1);
  /* RELOAD after a transfer on the handle that ran it, and lower case */
  setter(m, sh, "set2:localhost/", "localhost", "/", sc, 2);
  mkurl(u, sizeof u, "localhost", "/r");
  x = mk("ran", u, F_SHARE | F_FILE, sh);
  one(m, x);
  STEP = "RELOAD-after-transfer";
  cookielist(x, "RELOAD");
  STEP = "-";
  jar(x->h, "after-RELOAD-after-transfer");
  STEP = "sess-lower";
  cookielist(x, "sess");
  STEP = "-";
  jar(x->h, "after-sess-lower");
  STEP = "all-lower";
  cookielist(x, "all");
  STEP = "-";
  jar(x->h, "after-all-lower");
  drop(x);
  /* a bare handle: no share, no COOKIEFILE */
  bare = mk("bare", u, 0, NULL);
  for (i = 0; i < 4; i++) {
    STEP = cmds[i];
    cookielist(bare, cmds[i]);
    STEP = "-";
    snprintf(lab, sizeof lab, "bare-after-%s", cmds[i]);
    jar(bare->h, lab);
  }
  STEP = "BOGUS";
  cookielist(bare, "BOGUS");
  STEP = "-";
  jar(bare->h, "bare-after-BOGUS");
  drop(bare);
  curl_multi_cleanup(m);
  end_share(sh, "I");
}

/* I-roundtrip: a jar filled by Set-Cookie and by COOKIELIST is read out,
   every line loaded into a fresh share, read out again and compared; then
   the same requests on both shares. */
static void i_roundtrip(void) {
  CURLM *m = curl_multi_init();
  CURLSH *s1 = new_share("R1"), *s2 = new_share("R2");
  const char *sc[] = { "rt_host=1", "rt_dom=2; Domain=a.localhost", "rt_path=3; Path=/p", "rt_ho=4; HttpOnly", "rt_pers=5; Max-Age=3600",
    "rt_sp=a b", "rt_hb=caf\xc3\xa9", "rt_empty=", "rt_q=\"x\"", "rt_ho_dom=6; HttpOnly; Domain=a.localhost; Max-Age=7200" };
  const char *imp[] = { "Set-Cookie: rt_nodomain=7", "localhost\tFALSE\t/\tTRUE\t0\trt_ns_sec\t8", ".a.localhost\tTRUE\t/\tFALSE\t0\trt_ns_dot\t9",
    "#HttpOnly_a.localhost\tFALSE\t/\tFALSE\t0\trt_ns_ho\t10" };
  const tgt t[] = { { "a.localhost", "/" }, { "a.localhost", "/p" }, { "b.a.localhost", "/" }, { "localhost", "/" } };
  char u[2000];
  struct curl_slist *l1 = NULL, *l2 = NULL, *e, *f;
  xfer *x;
  int i, n1 = 0, n2 = 0, same = 0, missing = 0;
  CURLcode rc;
  setter(m, s1, "set:a.localhost/", "a.localhost", "/", sc, NELEM(sc));
  mkurl(u, sizeof u, "a.localhost", "/");
  x = mk("import1", u, F_SHARE | F_FILE, s1);
  for (i = 0; i < NELEM(imp); i++) cookielist(x, imp[i]);
  rc = curl_easy_getinfo(x->h, CURLINFO_COOKIELIST, &l1);
  say("roundtrip read1 rc=%d", (int)rc);
  jar(x->h, "R1");
  drop(x);
  x = mk("load2", u, F_SHARE | F_FILE, s2);
  for (e = l1; e; e = e->next) { cookielist(x, e->data); n1++; }
  rc = curl_easy_getinfo(x->h, CURLINFO_COOKIELIST, &l2);
  say("roundtrip read2 rc=%d", (int)rc);
  jar(x->h, "R2");
  drop(x);
  for (f = l2; f; f = f->next) n2++;
  for (e = l1; e; e = e->next) {
    int found = 0;
    for (f = l2; f; f = f->next) if (!strcmp(e->data, f->data)) { found = 1; break; }
    if (found) same++;
    else {
      char *s = esc_dup(e->data, strlen(e->data));
      say("roundtrip R1-line-not-in-R2 \"%s\"", s);
      free(s);
      missing++;
    }
  }
  for (f = l2; f; f = f->next) {
    int found = 0;
    for (e = l1; e; e = e->next) if (!strcmp(e->data, f->data)) { found = 1; break; }
    if (!found) {
      char *s = esc_dup(f->data, strlen(f->data));
      say("roundtrip R2-line-not-in-R1 \"%s\"", s);
      free(s);
    }
  }
  {
    int ordered = 1;
    for (e = l1, f = l2; e && f; e = e->next, f = f->next) if (strcmp(e->data, f->data)) ordered = 0;
    if (e || f) ordered = 0;
    say("roundtrip n1=%d n2=%d identical_lines=%d r1_missing_in_r2=%d same_order=%d", n1, n2, same, missing, ordered);
  }
  curl_slist_free_all(l1);
  curl_slist_free_all(l2);
  for (i = 0; i < NELEM(t); i++) {
    char label[160];
    snprintf(label, sizeof label, "R1-to:%s%s", t[i].host, t[i].path);
    get(m, s1, label, t[i].host, t[i].path, F_SHARE | F_FILE, 0);
    snprintf(label, sizeof label, "R2-to:%s%s", t[i].host, t[i].path);
    get(m, s2, label, t[i].host, t[i].path, F_SHARE | F_FILE, 0);
  }
  curl_multi_cleanup(m);
  end_share(s1, "R1");
  end_share(s2, "R2");
}

/* I-order: COOKIELIST before CURLOPT_SHARE on one handle, and after. */
static void i_order(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("I");
  char u[2000];
  xfer *x;
  CURLcode rc;
  mkurl(u, sizeof u, "localhost", "/");
  x = mk("before-share", u, F_FILE, NULL);
  cookielist(x, "localhost\tFALSE\t/\tFALSE\t0\tbefore_share\t1");
  jar(x->h, "before-share-own");
  rc = curl_easy_setopt(x->h, CURLOPT_SHARE, sh);
  say("xfer=before-share setopt SHARE rc=%d", (int)rc);
  jar(x->h, "before-share-attached");
  cookielist(x, "localhost\tFALSE\t/\tFALSE\t0\tafter_share\t1");
  jar(x->h, "after-share-attached");
  drop(x);
  get(m, sh, "to:localhost/", "localhost", "/", F_SHARE | F_FILE, 1);
  curl_multi_cleanup(m);
  end_share(sh, "I");
}

/* I-noengine: the share attached and COOKIELIST loaded, without COOKIEFILE:
   does the handle send the jar, and store a Set-Cookie? And a bare handle,
   no share, no COOKIEFILE, with COOKIELIST alone. */
static void i_noengine(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("I");
  char u[2000];
  xfer *x;
  mkurl(u, sizeof u, "localhost", "/n1");
  addsc(u, "ne_set=1");
  x = mk("share-nofile", u, F_SHARE, sh);
  cookielist(x, "localhost\tFALSE\t/\tFALSE\t0\tne_imp\t1");
  one(m, x);
  jar(x->h, "share-nofile");
  drop(x);
  get(m, sh, "to:localhost/-with-file", "localhost", "/n2", F_SHARE | F_FILE, 1);
  mkurl(u, sizeof u, "localhost", "/n3");
  addsc(u, "bare_set=1");
  x = mk("bare-cookielist", u, 0, NULL);
  cookielist(x, "localhost\tFALSE\t/\tFALSE\t0\tbare_imp\t1");
  one(m, x);
  jar(x->h, "bare-cookielist");
  drop(x);
  curl_multi_cleanup(m);
  end_share(sh, "I");
}

/* F-flush-control: COOKIEJAR at FLUSH_DIR/jar.txt, the one file case. */
static void print_file(const char *path, const char *label) {
  FILE *f;
  char buf[4096];
  STEP = "probe-reads-jar-file";
  f = fopen(path, "r");
  STEP = "-";
  if (!f) { say("file %s %s absent errno=%d", label, path, errno); return; }
  while (fgets(buf, sizeof buf, f)) {
    char *s;
    size_t n = strlen(buf);
    if (n && buf[n - 1] == '\n') buf[--n] = 0;
    s = esc_dup(buf, n);
    say("file %s line \"%s\"", label, s);
    free(s);
  }
  fclose(f);
}
static void f_flush_control(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("F");
  const char *dir = getenv("FLUSH_DIR");
  char path[1200], u[2000];
  xfer *x;
  if (!dir) { say("no FLUSH_DIR"); return; }
  snprintf(path, sizeof path, "%s/jar.txt", dir);
  mkurl(u, sizeof u, "localhost", "/f");
  addsc(u, "f_set=1");
  x = mk("jar", u, F_SHARE | F_FILE, sh);
  SETOPT(x, CURLOPT_COOKIEJAR, path);
  STEP = "FLUSH-before-transfer";
  cookielist(x, "FLUSH");
  STEP = "-";
  print_file(path, "after-FLUSH-before-transfer");
  STEP = "transfer";
  one(m, x);
  STEP = "FLUSH-after-transfer";
  cookielist(x, "FLUSH");
  STEP = "-";
  print_file(path, "after-FLUSH-after-transfer");
  STEP = "easy-cleanup";
  drop(x);
  STEP = "-";
  print_file(path, "after-easy-cleanup");
  curl_multi_cleanup(m);
  end_share(sh, "F");
}

/* X-detector: the probe itself reads stdin, writes stdout and stderr and
   opens a file, so the run shows each detector seeing it. */
static void x_detector(void) {
  int c;
  FILE *f;
  c = getchar();
  say("detector read stdin first byte=%d", c);
  fputs("probe-stdout\n", stdout);
  fflush(stdout);
  fputs("probe-stderr\n", stderr);
  STEP = "detector-fopen";
  f = fopen("detector-no-such-file", "r");
  STEP = "-";
  if (f) fclose(f);
  say("detector done");
}

/* X-resolve: the system resolver's answer for each name, beside libcurl's
   own (a transfer to each, its primary IP). */
static void x_resolve(void) {
  const char *names[] = { "localhost", "a.localhost", "b.a.localhost", "b.localhost", "c.a.localhost" };
  CURLM *m = curl_multi_init();
  int i;
  for (i = 0; i < NELEM(names); i++) {
    struct addrinfo hints, *res = NULL, *r;
    char fams[200] = "";
    int rc;
    memset(&hints, 0, sizeof hints);
    hints.ai_socktype = SOCK_STREAM;
    rc = getaddrinfo(names[i], NULL, &hints, &res);
    if (rc) say("system-resolver %s fails rc=%d (%s)", names[i], rc, gai_strerror(rc));
    else {
      for (r = res; r; r = r->ai_next) strcat(fams, r->ai_family == AF_INET6 ? " v6" : r->ai_family == AF_INET ? " v4" : " other");
      say("system-resolver %s ok:%s", names[i], fams);
      freeaddrinfo(res);
    }
  }
  for (i = 0; i < NELEM(names); i++) {
    char label[80];
    snprintf(label, sizeof label, "to:%s", names[i]);
    get(m, NULL, label, names[i], "/", 0, 0);
  }
  curl_multi_cleanup(m);
}

/* ================================================================ item 4 */

/* C-*: a jar holding n=jar for localhost and j=jar for a.localhost; the
   caller's own Cookie by HTTPHEADER or CURLOPT_COOKIE, named n: on
   localhost the jar's cookie of the same name, on a.localhost one of a
   different name. */
static void c_one(CURLM *m, CURLSH *sh, const char *label, const char *host, int flags, const char **hdrs, int nh, const char *opt) {
  char u[2000];
  xfer *x;
  int i;
  mkurl(u, sizeof u, host, "/c");
  x = mk(label, u, flags, sh);
  for (i = 0; i < nh; i++) x->hl = curl_slist_append(x->hl, hdrs[i]);
  if (x->hl) SETOPT(x, CURLOPT_HTTPHEADER, x->hl);
  if (opt) SETOPT(x, CURLOPT_COOKIE, opt);
  one(m, x);
  if (flags & F_SHARE) jar(x->h, label);
  drop(x);
}
static void c_caller(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("C");
  const char *s1[] = { "n=jar" };
  const char *s2[] = { "j=jar" };
  const char *h_n[] = { "Cookie: n=caller" };
  const char *h_rm[] = { "Cookie:" };
  const char *h_empty[] = { "Cookie;" };
  const char *h_lower[] = { "cookie: n=caller" };
  const char *h_two[] = { "Cookie: n=caller1", "Cookie: n=caller2" };
  const char *hosts[] = { "localhost", "a.localhost" };
  int k;
  setter(m, sh, "set:localhost/", "localhost", "/", s1, 1);
  setter(m, sh, "set:a.localhost/", "a.localhost", "/", s2, 1);
  for (k = 0; k < 2; k++) {
    const char *h = hosts[k];
    char lab[120];
#define L(s) (snprintf(lab, sizeof lab, "%s@%s", s, h), lab)
    c_one(m, sh, L("jar-only"), h, F_SHARE | F_FILE, NULL, 0, NULL);
    c_one(m, sh, L("httpheader"), h, F_SHARE | F_FILE, h_n, 1, NULL);
    c_one(m, sh, L("opt-cookie"), h, F_SHARE | F_FILE, NULL, 0, "n=opt");
    c_one(m, sh, L("httpheader+opt-cookie"), h, F_SHARE | F_FILE, h_n, 1, "n=opt");
    c_one(m, sh, L("httpheader-remove"), h, F_SHARE | F_FILE, h_rm, 1, NULL);
    c_one(m, sh, L("httpheader-empty"), h, F_SHARE | F_FILE, h_empty, 1, NULL);
    c_one(m, sh, L("httpheader-lower"), h, F_SHARE | F_FILE, h_lower, 1, NULL);
    c_one(m, sh, L("httpheader-two"), h, F_SHARE | F_FILE, h_two, 2, NULL);
    c_one(m, sh, L("opt-cookie-two-pairs"), h, F_SHARE | F_FILE, NULL, 0, "n=opt1; o=opt2");
    c_one(m, sh, L("httpheader-remove+opt-cookie"), h, F_SHARE | F_FILE, h_rm, 1, "n=opt");
    c_one(m, sh, L("nojar-opt-cookie"), h, 0, NULL, 0, "n=opt");
    c_one(m, sh, L("nojar-httpheader"), h, 0, h_n, 1, NULL);
#undef L
  }
  get(m, sh, "after:localhost", "localhost", "/c", F_SHARE | F_FILE, 1);
  curl_multi_cleanup(m);
  end_share(sh, "C");
}

/* ================================================================ item 5 */

/* hop: a transfer to URL (absolute), reported, its jar printed, its
   CURLINFO_REDIRECT_URL copied to NEXT when given. */
static void hop(CURLM *m, CURLSH *sh, const char *label, const char *url, char *next, size_t cap) {
  xfer *x = mk(label, url, F_SHARE | F_FILE, sh);
  char *r = NULL;
  one(m, x);
  curl_easy_getinfo(x->h, CURLINFO_REDIRECT_URL, &r);
  say("xfer=%s redirect_url=%s", label, r ? r : "(none)");
  if (next) snprintf(next, cap, "%s", r ? r : "");
  jar(x->h, label);
  drop(x);
}

/* R-*: T0 a.localhost/pre sets pre (host-only) and pdom (Domain=a.localhost);
   T1 answers a 3xx to TARGET with Set-Cookies SCS; T2 a fresh handle to
   T1's redirect URL; T3 back to a.localhost/land. */
static void r_case(const char *start_host, const char *start_path, const char *status, const char *loc, const char **scs, int nsc) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("R");
  const char *pre[] = { "pre=a", "pdom=1; Domain=a.localhost" };
  char u[4000], next[2000], locb[600];
  int i;
  setter(m, sh, "T0:a.localhost/pre", "a.localhost", "/pre", pre, 2);
  mkurl(u, sizeof u, start_host, start_path);
  addplain(u, status);
  if (strstr(loc, "%d")) snprintf(locb, sizeof locb, loc, PORT); else snprintf(locb, sizeof locb, "%s", loc);
  addq(u, "loc", locb, strlen(locb));
  for (i = 0; i < nsc; i++) addsc(u, scs[i]);
  hop(m, sh, "T1", u, next, sizeof next);
  if (next[0]) hop(m, sh, "T2-follow", next, NULL, 0);
  mkurl(u, sizeof u, "a.localhost", "/land");
  hop(m, sh, "T3:a.localhost/land", u, NULL, 0);
  curl_multi_cleanup(m);
  end_share(sh, "R");
}
static void r_cross(void) {
  const char *sc[] = { "on3xx=1", "on3xx_lh=1; Domain=localhost" };
  r_case("a.localhost", "/start", "st=302", "http://b.localhost:%d/land", sc, 2);
}
static void r_rel(void) {
  const char *sc[] = { "rp=1; Path=/other", "rq=1" };
  r_case("a.localhost", "/dir/start", "st=302", "/other/land", sc, 2);
}
static void r_sub(void) {
  const char *sc[] = { "sub=1; Domain=a.localhost" };
  r_case("a.localhost", "/start", "st=301", "http://b.a.localhost:%d/land", sc, 1);
}
static void r_del(void) {
  const char *sc[] = { "pre=; Max-Age=0" };
  r_case("a.localhost", "/start", "st=303", "/land", sc, 1);
}
static void r_ip(void) {
  const char *sc[] = { "lh_only=1" };
  r_case("localhost", "/start", "st=307", "http://127.0.0.1:%d/land", sc, 1);
}
/* R-libcurl-follow: R-cross's hops followed by libcurl itself
   (FOLLOWLOCATION 1, MAXREDIRS 5), one handle: a comparison row. */
static void r_libcurl_follow(void) {
  CURLM *m = curl_multi_init();
  CURLSH *sh = new_share("R");
  const char *pre[] = { "pre=a", "pdom=1; Domain=a.localhost" };
  char u[4000], locb[600];
  xfer *x;
  setter(m, sh, "T0:a.localhost/pre", "a.localhost", "/pre", pre, 2);
  mkurl(u, sizeof u, "a.localhost", "/start");
  addplain(u, "st=302");
  snprintf(locb, sizeof locb, "http://b.localhost:%d/land", PORT);
  addq(u, "loc", locb, strlen(locb));
  addsc(u, "on3xx=1");
  addsc(u, "on3xx_lh=1; Domain=localhost");
  x = mk("T1-libcurl-follows", u, F_SHARE | F_FILE, sh);
  SETOPT(x, CURLOPT_FOLLOWLOCATION, 1L);
  SETOPT(x, CURLOPT_MAXREDIRS, 5L);
  one(m, x);
  jar(x->h, "T1-libcurl-follows");
  drop(x);
  curl_multi_cleanup(m);
  end_share(sh, "R");
}

/* ================================================================ main */

static void version(void) {
  curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
  printf("version %s num=0x%06x age=%d features=0x%x psl_bit=%d ssl=%s libz=%s host=%s\n", v->version, v->version_num, (int)v->age,
         (unsigned)v->features, (v->features & CURL_VERSION_PSL) ? 1 : 0, v->ssl_version ? v->ssl_version : "-",
         v->libz_version ? v->libz_version : "-", v->host);
  printf("curl_version %s\n", curl_version());
  printf("headers LIBCURL_VERSION %s\n", LIBCURL_VERSION);
#if LIBCURL_VERSION_NUM >= 0x075700
  if (v->age >= CURLVERSION_ELEVENTH && v->feature_names) {
    const char *const *f;
    printf("feature_names");
    for (f = v->feature_names; *f; f++) printf(" %s", *f);
    printf("\n");
  }
#endif
}

static const struct { const char *name; void (*fn)(void); } CASES[] = {
  { "X-detector", x_detector }, { "X-resolve", x_resolve },
  { "S-share", s_share }, { "S-noshare", s_noshare }, { "S-nofile", s_nofile }, { "S-file-first", s_file_first },
  { "S-file-later", s_file_later }, { "S-live", s_live }, { "S-cleanup", s_cleanup },
  { "M-domain-a", m_domain_a }, { "M-domain-ba", m_domain_ba }, { "M-domain-lh", m_domain_lh }, { "M-domain-ip", m_domain_ip },
  { "M-path", m_path }, { "M-secure", m_secure }, { "M-expiry", m_expiry }, { "M-attrs", m_attrs },
  { "M-overwrite", m_overwrite }, { "M-delete", m_delete }, { "M-invalid", m_invalid }, { "M-header-forms", m_header_forms },
  { "M-highbyte", m_highbyte }, { "M-many", m_many },
  { "I-netscape", i_netscape }, { "I-setcookie", i_setcookie }, { "I-commands", i_commands }, { "I-roundtrip", i_roundtrip },
  { "I-order", i_order }, { "I-noengine", i_noengine }, { "F-flush-control", f_flush_control },
  { "C-caller", c_caller },
  { "R-cross", r_cross }, { "R-rel", r_rel }, { "R-sub", r_sub }, { "R-del", r_del }, { "R-ip", r_ip }, { "R-libcurl-follow", r_libcurl_follow },
};

int main(int argc, char **argv) {
  const char *lp = getenv("PROBE_LOG");
  int i;
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    curl_global_init(CURL_GLOBAL_DEFAULT);
    version();
    return 0;
  }
  if (argc == 2 && !strcmp(argv[1], "--list")) {
    for (i = 0; i < NELEM(CASES); i++) printf("%s\n", CASES[i].name);
    return 0;
  }
  if (argc != 3) { fprintf(stderr, "usage: probe --version | --list | CASE PORT\n"); return 2; }
  LOG = lp ? fopen(lp, "a") : stdout;
  if (!LOG) { fprintf(stderr, "probe: cannot open PROBE_LOG\n"); return 2; }
  PORT = atoi(argv[2]);
  curl_global_init(CURL_GLOBAL_DEFAULT);
  for (i = 0; i < NELEM(CASES); i++)
    if (!strcmp(argv[1], CASES[i].name)) {
      char buf[4096];
      ssize_t k;
      size_t left = 0;
      char first[64] = "";
      CASE = CASES[i].name;
      fs_watch = 1;
      CASES[i].fn();
      fs_watch = 0;
      /* what stdin still holds */
      while ((k = read(0, buf, sizeof buf)) > 0) {
        if (!left) { size_t c = (size_t)k < 40 ? (size_t)k : 40; char *s = esc_dup(buf, c); snprintf(first, sizeof first, "%s", s); free(s); }
        left += (size_t)k;
      }
      say("stdin-left=%zu first=\"%s\"", left, first);
      curl_global_cleanup();
      return 0;
    }
  fprintf(stderr, "probe: no case %s\n", argv[1]);
  return 2;
}
