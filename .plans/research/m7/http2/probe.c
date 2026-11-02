/* M7's HTTP/2 probe (2026-11-02; the M7 plan's measurements, area HTTP/2
   and the HTTP version).

     probe --version
     probe CASE CTL H1 TLSH2 TLSH1 H2C CA

   CTL, H1, TLSH2, TLSH1 and H2C are server.mjs's ports; CA is the run's
   ca.pem. CASE is one of:

     V-version     item 1: CURLOPT_HTTP_VERSION unset, NONE, 1_1, 2_0, 2TLS,
                   2_PRIOR_KNOWLEDGE, 3 and 3ONLY, each against tlsh2 (https,
                   chooses h2 when offered), tlsh1 (https, http/1.1 alone),
                   h1 (http, HTTP/1.1) and h2c (http, HTTP/2 by prior
                   knowledge), one transfer each on a fresh multi handle.
     S-together    item 2: 2 and 4 transfers to tlsh2 added in one step,
                   PIPEWAIT 1 and 0.
     S-after-head  item 2: B added once A's head arrived, PIPEWAIT 1 and 0.
     S-after-end   item 2: B added once A ended, PIPEWAIT 1 and 0.
     S-h1-wait     item 2: two transfers to tlsh1 added in one step, PIPEWAIT
                   1 and 0, and three at PIPEWAIT 1.
     W-sibling     item 3: M6's W-sibling, A paused beside an active B, with
                   PIPEWAIT 1 and 0, B added with A ("together", M6's case
                   at PIPEWAIT 1) or once A's head arrived ("late").

   Every transfer goes through the multi interface, in M6's pause probe's
   loop, which mirrors chez-curl's engine turn: the message step (a resume,
   curl_easy_pause CONT, when a case's clock says so), the setup step
   (curl_multi_add_handle of a transfer whose time has come), then
   curl_multi_perform, curl_multi_info_read, and curl_multi_poll for at most
   1000 ms, less when the case's next event is sooner. A finished transfer
   is removed from its multi at once, as the engine does.

   Every transfer gets the engine's options: PROTOCOLS_STR and
   REDIR_PROTOCOLS_STR "http,https", NOSIGNAL 1, FOLLOWLOCATION 0, PROXY ""
   and, on https, SSL_VERIFYPEER 1, SSL_VERIFYHOST 2, CAINFO at CA and CAPATH
   cleared. HTTP_VERSION is left unset or set by V-version; the S- and W-
   cases set 2TLS, as M6's probe did. A setopt that answers other than
   CURLE_OK prints a line, but CAPATH's clear answering CURLE_NOT_BUILT_IN.

   libcurl allocates through curl_global_init_mem's counting allocators:
   "live" is the bytes it holds through them at that moment (M6's measure).

   Output: lines "case NAME FACE key=value ...", each transfer ending
   "case NAME FACE done code=N ...". Times are ms from the transfer's add,
   or, where a line says case_t, from the case's start. "server:" lines are
   server.mjs's events since the case began, fetched on the control port
   over a plain socket, after the case's transfers, so no libcurl call
   stands between.

   PROBE_NO_MULTIPLEX=1 in the environment sets CURLMOPT_PIPELINING to 0 on
   every multi handle, as chez-curl's engine does on 8.7.0 and 8.7.1
   (ADR-0030, amended), printing a line for each. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <curl/curl.h>

#ifndef CURL_HTTP_VERSION_3
#define CURL_HTTP_VERSION_3 30      /* 7.66.0 */
#endif
#ifndef CURL_HTTP_VERSION_3ONLY
#define CURL_HTTP_VERSION_3ONLY 31  /* 7.88.0 */
#endif

static int P_CTL, P_H1, P_TLSH2, P_TLSH1, P_H2C;
static const char *CA;
static int in_pause;

/* ---------------------------------------------------------------- clocks */
static double abs_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

/* ---------------------------------------------------------------- memory */
#define HDR 16
static int64_t live, win_peak;
static void track(int64_t d) {
  int64_t v = __atomic_add_fetch(&live, d, __ATOMIC_SEQ_CST);
  if (v > win_peak) win_peak = v;
}
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

/* ---------------------------------------------------------------- faces */
static int port_of(const char *f) {
  return !strcmp(f, "h1") ? P_H1 : !strcmp(f, "tlsh2") ? P_TLSH2 : !strcmp(f, "tlsh1") ? P_TLSH1 : P_H2C;
}
static int is_tls(const char *f) { return !strcmp(f, "tlsh2") || !strcmp(f, "tlsh1"); }

static const char *ver_name(long v) {
  switch (v) {
  case 0: return "none";
  case CURL_HTTP_VERSION_1_0: return "1.0";
  case CURL_HTTP_VERSION_1_1: return "1.1";
  case CURL_HTTP_VERSION_2_0: return "2";
  case CURL_HTTP_VERSION_3: return "3";
  default: return "?";
  }
}

/* ---------------------------------------------------------------- transfers */
typedef struct xfer {
  CURL *h;
  char name[96], face[8], tag[200];
  double t_add, add_at;
  int added, done, removed, gave_up;
  CURLcode code;
  double t_end, t_head, t_first;
  long lport, ver, status, conns;
  int ver_rc;                   /* HTTP_VERSION's setopt answer; -1 unset */
  /* write side */
  int pause_first;
  double hold;
  int paused, pause_noted, pauses, resumes;
  double paused_at, resume_at;
  int calls, calls_inpause;
  int64_t total, first_bad, bytes_inpause;
  int64_t live_cb_pause, live_after_pause, live_before_resume, peak_in_pause;
  /* debug */
  int dlog, upgrade_sent, header_out_n;
  /* chaining: another transfer to add once this one's head arrives, or once
     it ends */
  struct xfer *then_on_head, *then_on_end;
} xfer;

static double g_t0;
static double rel(const xfer *x) { return abs_ms() - x->t_add; }
#define SAY(x, ...) do { printf("case %s %s ", (x)->name, (x)->face); printf(__VA_ARGS__); putchar('\n'); } while (0)

static void esc(const char *d, size_t n, char *out, size_t cap) {
  size_t o = 0, i;
  for (i = 0; i < n && o + 6 < cap; i++) {
    unsigned char c = (unsigned char)d[i];
    if (c == '\r') { out[o++] = '\\'; out[o++] = 'r'; }
    else if (c == '\n') { out[o++] = '\\'; out[o++] = 'n'; }
    else if (c == '\\' || c == '"' || c < 0x20 || c > 0x7e) o += (size_t)snprintf(out + o, cap - o, "\\x%02x", c);
    else out[o++] = (char)c;
  }
  if (i < n) o += (size_t)snprintf(out + o, cap - o, "...(%zu bytes)", n);
  out[o] = 0;
}

/* ci_find: whether NEEDLE occurs in D[0..N), ASCII case folded. */
static int ci_find(const char *d, size_t n, const char *needle) {
  size_t k = strlen(needle), i, j;
  for (i = 0; i + k <= n; i++) {
    for (j = 0; j < k; j++)
      if (tolower((unsigned char)d[i + j]) != tolower((unsigned char)needle[j])) break;
    if (j == k) return 1;
  }
  return 0;
}

static size_t on_write(char *d, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t len = sz * nm, i;
  x->calls++;
  if (in_pause) x->calls_inpause++;
  if (x->t_first < 0) x->t_first = rel(x);   /* the clock stops where the first byte is seen */
  if (x->pause_first && x->calls == 1) {
    x->paused = 1;
    x->pause_noted = 0;
    x->pauses++;
    x->paused_at = abs_ms();
    x->resume_at = x->paused_at + x->hold;
    x->live_cb_pause = live_now();
    return CURL_WRITEFUNC_PAUSE;
  }
  for (i = 0; i < len && x->first_bad < 0; i++)
    if ((unsigned char)d[i] != (unsigned char)((x->total + (int64_t)i) % 251)) x->first_bad = x->total + (int64_t)i;
  x->total += (int64_t)len;
  if (in_pause) x->bytes_inpause += (int64_t)len;
  return len;
}

static size_t on_header(char *d, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t len = sz * nm;
  if (len == 2 && d[0] == '\r' && d[1] == '\n') {
    long st = 0;
    curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
    if (st >= 200 && x->t_head < 0) {
      x->t_head = rel(x);
      if (x->then_on_head && !x->then_on_head->added) x->then_on_head->add_at = abs_ms();
    }
  }
  return len;
}

static int on_debug(CURL *h, curl_infotype type, char *d, size_t n, void *u) {
  xfer *x = u;
  char e[2400];
  (void)h;
  if (type == CURLINFO_HEADER_OUT) {
    x->header_out_n++;
    if (ci_find(d, n, "\nupgrade: h2c")) x->upgrade_sent = 1;
    if (x->dlog) { esc(d, n, e, sizeof e); SAY(x, "debug t=%.1f header_out \"%s\"", rel(x), e); }
    return 0;
  }
  if (!x->dlog) return 0;
  if (type != CURLINFO_TEXT && type != CURLINFO_HEADER_IN) return 0;
  while (n && (d[n - 1] == '\n' || d[n - 1] == '\r')) n--;
  esc(d, n, e, sizeof e);
  SAY(x, "debug t=%.1f %s \"%s\"", rel(x), type == CURLINFO_TEXT ? "text" : "header_in", e);
  return 0;
}

#define SETOPT(x, opt, val) do { CURLcode rc_ = curl_easy_setopt((x)->h, opt, val); \
    if (rc_ != CURLE_OK && !(opt == CURLOPT_CAPATH && rc_ == CURLE_NOT_BUILT_IN)) \
      SAY(x, "setopt %s rc=%d", #opt, (int)rc_); } while (0)

/* mk: a transfer NAME on FACE of PATHQ, its tag NAME, with the engine's
   options, and HTTP_VERSION VER, or none when VER is -1. */
static xfer *mk(const char *name, const char *face, const char *pathq, long ver) {
  xfer *x = calloc(1, sizeof *x);
  char url[600], *c;
  snprintf(x->name, sizeof x->name, "%s", name);
  snprintf(x->face, sizeof x->face, "%s", face);
  snprintf(x->tag, sizeof x->tag, "%s", name);
  for (c = x->tag; *c; c++) if (*c == ':' || *c == '/') *c = '.';
  x->first_bad = -1;
  x->t_first = x->t_head = -1;
  x->lport = x->ver = x->status = x->conns = -1;
  x->ver_rc = -1;
  x->h = curl_easy_init();
  snprintf(url, sizeof url, "%s://127.0.0.1:%d%s%stag=%s", is_tls(face) ? "https" : "http", port_of(face), pathq,
           strchr(pathq, '?') ? "&" : "?", x->tag);
  SETOPT(x, CURLOPT_URL, url);
  SETOPT(x, CURLOPT_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_NOSIGNAL, 1L);
  SETOPT(x, CURLOPT_FOLLOWLOCATION, 0L);
  SETOPT(x, CURLOPT_PROXY, "");
  if (ver >= 0) x->ver_rc = (int)curl_easy_setopt(x->h, CURLOPT_HTTP_VERSION, ver);
  if (is_tls(face)) {
    SETOPT(x, CURLOPT_SSL_VERIFYPEER, 1L);
    SETOPT(x, CURLOPT_SSL_VERIFYHOST, 2L);
    SETOPT(x, CURLOPT_CAINFO, CA);
    SETOPT(x, CURLOPT_CAPATH, (char *)NULL);
  }
  SETOPT(x, CURLOPT_WRITEFUNCTION, on_write);
  SETOPT(x, CURLOPT_WRITEDATA, x);
  SETOPT(x, CURLOPT_HEADERFUNCTION, on_header);
  SETOPT(x, CURLOPT_HEADERDATA, x);
  SETOPT(x, CURLOPT_PRIVATE, x);
  return x;
}

/* verbose: the debug callback, which counts each request head sent and
   whether it held Upgrade: h2c, and prints libcurl's text, the heads sent
   and the heads received. V- and S- cases; W-sibling runs without it, as
   M6's did. */
static int quiet(void) {
  const char *v = getenv("PROBE_QUIET");
  return v && !strcmp(v, "1");
}
static void verbose(xfer *x) {
  if (quiet()) return;
  x->dlog = 1;
  SETOPT(x, CURLOPT_VERBOSE, 1L);
  SETOPT(x, CURLOPT_DEBUGFUNCTION, on_debug);
  SETOPT(x, CURLOPT_DEBUGDATA, x);
}

static void resume(xfer *x) {
  CURLcode rc;
  int before = x->calls;
  double t1;
  x->live_before_resume = live_now();
  x->peak_in_pause = win_peak;
  x->paused = 0;
  x->resumes++;
  t1 = abs_ms();
  in_pause = 1;
  rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
  in_pause = 0;
  SAY(x, "resume n=%d t=%.1f held=%.1f rc=%d calls_inside=%d took=%.2f", x->resumes, t1 - x->t_add, t1 - x->paused_at, (int)rc, x->calls - before, abs_ms() - t1);
}

static void (*g_tick)(void);
static double g_tick_every, g_tick_next;

static void finish(CURLM *m, xfer *x) {
  curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &x->status);
  curl_easy_getinfo(x->h, CURLINFO_HTTP_VERSION, &x->ver);
  curl_easy_getinfo(x->h, CURLINFO_NUM_CONNECTS, &x->conns);
  curl_easy_getinfo(x->h, CURLINFO_LOCAL_PORT, &x->lport);
  curl_multi_remove_handle(m, x->h);
  x->removed = 1;
  SAY(x, "done code=%d err=\"%s\" case_t_add=%.1f t_head=%.1f t_first=%.1f t_end=%.1f status=%ld ver=%ld(%s) num_connects=%ld lport=%ld total=%lld pattern=%s",
      (int)x->code, curl_easy_strerror(x->code), x->t_add - g_t0, x->t_head, x->t_first, x->t_end - x->t_add, x->status, x->ver, ver_name(x->ver),
      x->conns, x->lport, (long long)x->total, x->first_bad < 0 ? "ok" : "bad");
  if (x->then_on_end && !x->then_on_end->added) x->then_on_end->add_at = abs_ms();
}

static void add(CURLM *m, xfer *x) {
  CURLMcode mc;
  x->t_add = abs_ms();
  mc = curl_multi_add_handle(m, x->h);
  x->added = 1;
  if (mc) SAY(x, "multi_add rc=%d", (int)mc);
}

/* drive: the engine's turn over XS until each is done, or BOUND ms pass. A
   transfer whose add_at is 1e18 waits for another's head or end. */
static void drive(CURLM *m, xfer **xs, int nx, double bound) {
  double start = abs_ms();
  int i, running;
  for (;;) {
    double wait = 1000, t = abs_ms();
    int open = 0, q;
    CURLMsg *msg;
    for (i = 0; i < nx; i++) {               /* the message step */
      xfer *x = xs[i];
      if (!x->added || x->done || x->removed) continue;
      if (x->paused && t >= x->resume_at) resume(x);
    }
    if (g_tick && g_tick_every > 0 && t >= g_tick_next) { g_tick(); g_tick_next += g_tick_every; }
    for (i = 0; i < nx; i++)                 /* the setup step */
      if (!xs[i]->added && t >= xs[i]->add_at) add(m, xs[i]);
    curl_multi_perform(m, &running);
    while ((msg = curl_multi_info_read(m, &q))) {
      if (msg->msg != CURLMSG_DONE) continue;
      for (i = 0; i < nx; i++) {
        if (xs[i]->h == msg->easy_handle && !xs[i]->done) {
          xs[i]->done = 1;
          xs[i]->code = msg->data.result;
          xs[i]->t_end = abs_ms();
          finish(m, xs[i]);
        }
      }
    }
    for (i = 0; i < nx; i++) {
      xfer *x = xs[i];
      if (x->paused && !x->pause_noted) {
        x->pause_noted = 1;
        if (x->pauses == 1) { x->live_after_pause = live_now(); win_peak = x->live_after_pause; }
      }
      if (!x->added) { open = 1; if (x->add_at - abs_ms() < wait) wait = x->add_at - abs_ms(); }
      else if (!x->done && !x->removed) {
        open = 1;
        if (x->paused && x->resume_at - abs_ms() < wait) wait = x->resume_at - abs_ms();
      }
    }
    if (!open) return;
    if (g_tick && g_tick_every > 0 && g_tick_next - abs_ms() < wait) wait = g_tick_next - abs_ms();
    if (start + bound - abs_ms() < wait) wait = start + bound - abs_ms();
    if (abs_ms() - start > bound) {
      for (i = 0; i < nx; i++) {
        xfer *x = xs[i];
        if (!x->done && !x->removed) {
          SAY(x, "gave-up after %.0f ms: the probe's own bound; added=%d paused=%d", bound, x->added, x->paused);
          if (x->added) curl_multi_remove_handle(m, x->h);
          x->removed = 1;
          x->gave_up = 1;
        }
      }
      return;
    }
    if (wait < 0) wait = 0;
    curl_multi_poll(m, NULL, 0, (int)(wait + 0.999), NULL);
  }
}

static void drop(xfer *x) {
  if (x->h) curl_easy_cleanup(x->h);
  free(x);
}

/* ---------------------------------------------------------------- control */
/* ctl: GET PATH on the control port over a plain socket; the body into OUT,
   NUL-terminated. Answers its length, or -1. */
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
  if (ctl("/seq", b, sizeof b) < 0) { printf("ctl: /seq failed\n"); return -1; }
  return atol(b);
}

static char g_events[1 << 20];

/* events: fetch the events after AFTER into g_events, and print each line
   as LABEL's "server:" line. */
static void events(const char *label, long after) {
  char p[64], *line, *nl;
  int n = 0;
  snprintf(p, sizeof p, "/events?after=%ld", after);
  if (ctl(p, g_events, sizeof g_events) < 0) { printf("case %s server: the events fetch failed\n", label); g_events[0] = 0; return; }
  for (line = g_events; *line; line = nl + 1) {
    n++;
    nl = strchr(line, '\n');
    if (!nl) { printf("case %s server: %s\n", label, line); break; }
    *nl = 0;
    printf("case %s server: %s\n", label, line);
    *nl = '\n';
  }
  printf("case %s server-events after=%ld n=%d\n", label, after, n);
}

static void server_summary(const char *label, long after, const char *face) {
  char p[96], b[2048];
  snprintf(p, sizeof p, "/summary?after=%ld&face=%s", after, face);
  if (ctl(p, b, sizeof b) < 0) { printf("case %s server-summary: fetch failed\n", label); return; }
  if (*b && b[strlen(b) - 1] == '\n') b[strlen(b) - 1] = 0;
  printf("case %s server-summary face=%s %s\n", label, face, b);
}

/* field: copy the token after KEY= in the first g_events line holding
   KIND (e.g. " alpn face=tlsh2 "), into OUT; "-" when there is none. */
static void field(const char *kind, const char *key, char *out, size_t cap) {
  const char *p = strstr(g_events, kind), *eol, *k;
  char kk[64];
  size_t n;
  snprintf(out, cap, "-");
  if (!p) return;
  eol = strchr(p, '\n');
  if (!eol) eol = p + strlen(p);
  snprintf(kk, sizeof kk, " %s=", key);
  k = strstr(p, kk);
  if (!k || k > eol) return;
  k += strlen(kk);
  n = strcspn(k, " \n");
  if (n >= cap) n = cap - 1;
  memcpy(out, k, n);
  out[n] = 0;
}

static int no_multiplex(void) {
  const char *v = getenv("PROBE_NO_MULTIPLEX");
  return v && !strcmp(v, "1");
}

static CURLM *new_multi(void) {
  CURLM *m = curl_multi_init();
  if (m && no_multiplex()) {
    CURLMcode rc = curl_multi_setopt(m, CURLMOPT_PIPELINING, (long)CURLPIPE_NOTHING);
    printf("multi pipelining=0 (PROBE_NO_MULTIPLEX=1) rc=%d\n", (int)rc);
  }
  return m;
}

/* ---------------------------------------------------------------- item 1 */
static const struct { const char *name; long val; } SETTINGS[] = {
  { "unset", -1 },
  { "NONE", CURL_HTTP_VERSION_NONE },
  { "1_1", CURL_HTTP_VERSION_1_1 },
  { "2_0", CURL_HTTP_VERSION_2_0 },
  { "2TLS", CURL_HTTP_VERSION_2TLS },
  { "2_PRIOR_KNOWLEDGE", CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE },
  { "3", CURL_HTTP_VERSION_3 },
  { "3ONLY", CURL_HTTP_VERSION_3ONLY },
};
static const char *VFACES[] = { "tlsh2", "tlsh1", "h1", "h2c" };

/* V-version: each setting against each face, one transfer of /hello on a
   fresh multi. One line "version ..." per pair, beside the transfer's
   verbose text, its request head, and the server's events. */
static void v_version(void) {
  size_t s;
  int f;
  for (s = 0; s < sizeof SETTINGS / sizeof SETTINGS[0]; s++) {
    for (f = 0; f < 4; f++) {
      CURLM *m = new_multi();
      char nm[96], label[128], offered[256], chose[64], proto[16], upg[64], first[96], tlsalpn[32], tlserr[96];
      long seq0;
      xfer *x;
      snprintf(nm, sizeof nm, "V-version:%s", SETTINGS[s].name);
      x = mk(nm, VFACES[f], "/hello", SETTINGS[s].val);
      snprintf(label, sizeof label, "%s %s", x->name, x->face);
      if (SETTINGS[s].val >= 0 && x->ver_rc != 0) {
        SAY(x, "version setting=%s(%ld) setopt_rc=%d (%s): refused, no transfer run", SETTINGS[s].name, SETTINGS[s].val, x->ver_rc,
            curl_easy_strerror((CURLcode)x->ver_rc));
        drop(x);
        curl_multi_cleanup(m);
        continue;
      }
      verbose(x);
      seq0 = ctl_seq();
      g_t0 = abs_ms();
      x->add_at = g_t0;
      drive(m, &x, 1, 15000);
      events(label, seq0);
      {
        char k1[64], k2[64], k3[64], k4[64], k5[64];
        snprintf(k1, sizeof k1, " alpn face=%s ", x->face);
        snprintf(k2, sizeof k2, " req face=%s ", x->face);
        snprintf(k3, sizeof k3, " first face=%s ", x->face);
        snprintf(k4, sizeof k4, " tls face=%s ", x->face);
        field(k1, "offered", offered, sizeof offered);
        field(k1, "chose", chose, sizeof chose);
        field(k2, "proto", proto, sizeof proto);
        field(k2, "upgrade", upg, sizeof upg);
        field(k3, "bytes", first, sizeof first);
        field(k4, "alpn", tlsalpn, sizeof tlsalpn);
        snprintf(k5, sizeof k5, " tls-error face=%s ", x->face);
        field(k5, "code", tlserr, sizeof tlserr);
        if (strcmp(first, "-")) {
          /* the first bytes' opening, after bytes=N */
          const char *p = strstr(g_events, k3);
          p = p ? strstr(p, " \"") : NULL;
          if (p) { size_t n = strcspn(p + 2, "\\\""); if (n > 16) n = 16; snprintf(first, sizeof first, "%.*s", (int)n, p + 2); }
        }
      }
      SAY(x, "version setting=%s(%ld) setopt_rc=%d code=%d ver=%ld(%s) status=%ld client_upgrade_h2c_sent=%d client_header_outs=%d server_alpn_offered=%s server_alpn_chose=%s server_tls_alpn=%s server_req_proto=%s server_req_upgrade=%s server_first_bytes=%s server_h1_saw_preface=%d server_tls_error=%s",
          SETTINGS[s].name, SETTINGS[s].val, x->ver_rc, (int)x->code, x->ver, ver_name(x->ver), x->status, x->upgrade_sent, x->header_out_n,
          offered, chose, tlsalpn, proto, upg, first, strstr(g_events, " preface face=h1 ") != NULL, tlserr);
      drop(x);
      curl_multi_cleanup(m);
    }
  }
}

/* ---------------------------------------------------------------- item 2 */
/* ~500 ms of body: 11 writes of 1 KiB, 50 ms apart */
#define BODY500 "/body?n=11264&chunk=1024&gap=50"

static void lports_line(const char *label, xfer **xs, int n) {
  char b[512];
  size_t o = 0;
  int i, j, distinct = 0;
  long sum = 0;
  for (i = 0; i < n; i++) {
    int seen = 0;
    for (j = 0; j < i; j++) if (xs[j]->lport == xs[i]->lport) seen = 1;
    if (!seen) distinct++;
    sum += xs[i]->conns;
    o += (size_t)snprintf(b + o, sizeof b - o, "%s%ld", i ? "," : "", xs[i]->lport);
  }
  printf("case %s client lports=%s distinct=%d num_connects_sum=%ld\n", label, b, distinct, sum);
}

/* S-together: N transfers of BODY500 to tlsh2, added in one step. */
static void s_together(void) {
  int ns[2] = { 2, 4 }, a, pw, i;
  for (a = 0; a < 2; a++)
    for (pw = 1; pw >= 0; pw--) {
      CURLM *m = new_multi();
      xfer *xs[4];
      char label[96];
      long seq0 = ctl_seq();
      int n = ns[a];
      snprintf(label, sizeof label, "S-together:n%d:pipewait%d", n, pw);
      for (i = 0; i < n; i++) {
        char nm[96];
        snprintf(nm, sizeof nm, "%s:%c", label, 'A' + i);
        xs[i] = mk(nm, "tlsh2", BODY500, CURL_HTTP_VERSION_2TLS);
        if (xs[i]->ver_rc) SAY(xs[i], "setopt HTTP_VERSION rc=%d", xs[i]->ver_rc);
        SETOPT(xs[i], CURLOPT_PIPEWAIT, (long)pw);
        verbose(xs[i]);
      }
      g_t0 = abs_ms();
      for (i = 0; i < n; i++) xs[i]->add_at = g_t0;
      drive(m, xs, n, 20000);
      lports_line(label, xs, n);
      server_summary(label, seq0, "tlsh2");
      events(label, seq0);
      for (i = 0; i < n; i++) drop(xs[i]);
      curl_multi_cleanup(m);
    }
}

/* S-after-head and S-after-end: A, then B once A's head arrived, or once A
   ended; BODY500 each, to tlsh2. */
static void s_after(int on_end) {
  int pw;
  for (pw = 1; pw >= 0; pw--) {
    CURLM *m = new_multi();
    xfer *xs[2];
    char label[96], na[112], nb[112];
    long seq0 = ctl_seq();
    snprintf(label, sizeof label, "%s:pipewait%d", on_end ? "S-after-end" : "S-after-head", pw);
    snprintf(na, sizeof na, "%s:A", label);
    snprintf(nb, sizeof nb, "%s:B", label);
    xs[0] = mk(na, "tlsh2", BODY500, CURL_HTTP_VERSION_2TLS);
    xs[1] = mk(nb, "tlsh2", BODY500, CURL_HTTP_VERSION_2TLS);
    SETOPT(xs[0], CURLOPT_PIPEWAIT, (long)pw);
    SETOPT(xs[1], CURLOPT_PIPEWAIT, (long)pw);
    verbose(xs[0]);
    verbose(xs[1]);
    if (on_end) xs[0]->then_on_end = xs[1]; else xs[0]->then_on_head = xs[1];
    g_t0 = abs_ms();
    xs[0]->add_at = g_t0;
    xs[1]->add_at = 1e18;
    drive(m, xs, 2, 20000);
    printf("case %s reuse A_head=%.1f A_end=%.1f B_added_at=%.1f B_first=%.1f (case_t) A_lport=%ld B_lport=%ld same_conn=%d B_num_connects=%ld A_ver=%ld B_ver=%ld B_added_while_A_open=%d\n",
           label, xs[0]->t_head, xs[0]->t_end - g_t0, xs[1]->t_add - g_t0, xs[1]->t_add - g_t0 + xs[1]->t_first, xs[0]->lport, xs[1]->lport,
           xs[0]->lport == xs[1]->lport, xs[1]->conns, xs[0]->ver, xs[1]->ver, xs[1]->t_add < xs[0]->t_end);
    lports_line(label, xs, 2);
    server_summary(label, seq0, "tlsh2");
    events(label, seq0);
    drop(xs[0]);
    drop(xs[1]);
    curl_multi_cleanup(m);
  }
}

/* S-h1-wait: N transfers of BODY500 to tlsh1, which offers http/1.1
   alone, added in one step, HTTP_VERSION 2TLS: 2 at PIPEWAIT 1 and 0, and
   3 at PIPEWAIT 1. One "h1wait" line, each transfer's head, first byte and
   end in ms from its add, and its connection. */
static void s_h1_wait(void) {
  int vs[3][2] = { { 2, 1 }, { 2, 0 }, { 3, 1 } }, v, i;
  for (v = 0; v < 3; v++) {
    CURLM *m = new_multi();
    xfer *xs[3];
    char label[96], line[1024];
    size_t o = 0;
    int n = vs[v][0], pw = vs[v][1];
    long seq0 = ctl_seq();
    snprintf(label, sizeof label, "S-h1-wait:n%d:pipewait%d", n, pw);
    for (i = 0; i < n; i++) {
      char nm[112];
      snprintf(nm, sizeof nm, "%s:%c", label, 'A' + i);
      xs[i] = mk(nm, "tlsh1", BODY500, CURL_HTTP_VERSION_2TLS);
      SETOPT(xs[i], CURLOPT_PIPEWAIT, (long)pw);
      verbose(xs[i]);
    }
    g_t0 = abs_ms();
    for (i = 0; i < n; i++) xs[i]->add_at = g_t0;
    drive(m, xs, n, 20000);
    for (i = 0; i < n; i++) {
      xfer *x = xs[i];
      o += (size_t)snprintf(line + o, sizeof line - o, " %c_add=%.1f %c_head=%.1f %c_first=%.1f %c_end=%.1f %c_lport=%ld %c_num_connects=%ld %c_ver=%ld %c_code=%d",
                            'A' + i, x->t_add - g_t0, 'A' + i, x->t_head, 'A' + i, x->t_first, 'A' + i, x->t_end - x->t_add, 'A' + i, x->lport,
                            'A' + i, x->conns, 'A' + i, x->ver, 'A' + i, (int)x->code);
    }
    printf("case %s h1wait n=%d pipewait=%d (ms from each add; add from the case's start)%s B_first_after_A_end=%d B_same_conn_as_A=%d\n", label, n, pw, line,
           xs[1]->t_add + xs[1]->t_first > xs[0]->t_end, xs[0]->lport == xs[1]->lport);
    lports_line(label, xs, n);
    server_summary(label, seq0, "tlsh1");
    events(label, seq0);
    for (i = 0; i < n; i++) drop(xs[i]);
    curl_multi_cleanup(m);
  }
}

/* ---------------------------------------------------------------- item 3 */
/* W-sibling: M6's (round 2, W6). A: 80 MiB as fast as the server can,
   paused at its first write for 5 s. B: 800 KiB, 16 KiB each 100 ms. A tick
   every 500 ms from the start: libcurl's live bytes, B's bytes. Variants:
   PIPEWAIT 1 and 0; B added with A ("together", M6's case at PIPEWAIT 1) or
   once A's head arrived ("late"). */
static xfer *g_ta, *g_tb;
static char g_tick_label[96];
static void sib_tick(void) {
  printf("case %s tick t=%.1f live=%lld A_paused=%d A_total=%lld B_added=%d B_total=%lld B_done=%d\n", g_tick_label, abs_ms() - g_t0, (long long)live_now(),
         g_ta->paused, (long long)g_ta->total, g_tb->added, (long long)g_tb->total, g_tb->done);
}
static void w_sibling(void) {
  int pw, late;
  for (late = 0; late < 2; late++)
    for (pw = 1; pw >= 0; pw--) {
      CURLM *m = new_multi();
      xfer *xs[2];
      char na[112], nb[112];
      long seq0 = ctl_seq();
      snprintf(g_tick_label, sizeof g_tick_label, "W-sibling:pipewait%d:%s", pw, late ? "late" : "together");
      snprintf(na, sizeof na, "%s:A", g_tick_label);
      snprintf(nb, sizeof nb, "%s:B", g_tick_label);
      xs[0] = mk(na, "tlsh2", "/body?n=83886080&chunk=65536", CURL_HTTP_VERSION_2TLS);
      xs[1] = mk(nb, "tlsh2", "/body?n=819200&chunk=16384&gap=100", CURL_HTTP_VERSION_2TLS);
      xs[0]->pause_first = 1;
      xs[0]->hold = 5000;
      SETOPT(xs[0], CURLOPT_PIPEWAIT, (long)pw);
      SETOPT(xs[1], CURLOPT_PIPEWAIT, (long)pw);
      g_t0 = abs_ms();
      xs[0]->add_at = g_t0;
      if (late) { xs[1]->add_at = 1e18; xs[0]->then_on_head = xs[1]; }
      else xs[1]->add_at = g_t0;
      g_ta = xs[0]; g_tb = xs[1];
      g_tick = sib_tick; g_tick_every = 500; g_tick_next = g_t0 + 500;
      drive(m, xs, 2, 90000);
      g_tick = NULL; g_tick_every = 0;
      printf("case %s sibling case_t A_paused_at=%.1f A_resumed_at=%.1f A_end=%.1f B_added_at=%.1f B_end=%.1f A_code=%d B_code=%d A_lport=%ld B_lport=%ld same_conn=%d A_ver=%ld B_ver=%ld A_total=%lld A_pattern=%s B_total=%lld B_pattern=%s A_inside_calls=%d A_inside_bytes=%lld\n",
             g_tick_label, xs[0]->paused_at - g_t0, xs[0]->paused_at + xs[0]->hold - g_t0, xs[0]->t_end - g_t0, xs[1]->t_add - g_t0, xs[1]->t_end - g_t0,
             (int)xs[0]->code, (int)xs[1]->code, xs[0]->lport, xs[1]->lport, xs[0]->lport == xs[1]->lport, xs[0]->ver, xs[1]->ver,
             (long long)xs[0]->total, xs[0]->first_bad < 0 ? "ok" : "bad", (long long)xs[1]->total, xs[1]->first_bad < 0 ? "ok" : "bad",
             xs[0]->calls_inpause, (long long)xs[0]->bytes_inpause);
      printf("case %s live in_callback_at_pause=%lld after_pausing_perform=%lld before_resume=%lld peak_during_pause=%lld\n", g_tick_label,
             (long long)xs[0]->live_cb_pause, (long long)xs[0]->live_after_pause, (long long)xs[0]->live_before_resume, (long long)xs[0]->peak_in_pause);
      server_summary(g_tick_label, seq0, "tlsh2");
      events(g_tick_label, seq0);
      drop(xs[0]);
      drop(xs[1]);
      curl_multi_cleanup(m);
      printf("case %s live after_cleanup=%lld\n", g_tick_label, (long long)live_now());
    }
}

int main(int argc, char **argv) {
  CURLcode g;
  setvbuf(stdout, NULL, _IOLBF, 0);
  g = curl_global_init_mem(CURL_GLOBAL_ALL, c_malloc, c_free, c_realloc, c_strdup, c_calloc);
  if (g) { printf("curl_global_init_mem rc=%d\n", (int)g); return 1; }
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
    printf("version headers=%s runtime=%s ssl=%s nghttp2=%s http2=%d http3=%d quic=%s features=0x%x\n", LIBCURL_VERSION, v->version,
           v->ssl_version ? v->ssl_version : "-", v->nghttp2_version ? v->nghttp2_version : "-", !!(v->features & CURL_VERSION_HTTP2),
#ifdef CURL_VERSION_HTTP3
           !!(v->features & CURL_VERSION_HTTP3),
#else
           -1,
#endif
           (v->age >= CURLVERSION_FIFTH && v->quic_version) ? v->quic_version : "-", (unsigned)v->features);
    curl_global_cleanup();
    return 0;
  }
  if (argc != 8) { fprintf(stderr, "usage: probe CASE CTL H1 TLSH2 TLSH1 H2C CA | probe --version\n"); return 2; }
  P_CTL = atoi(argv[2]);
  P_H1 = atoi(argv[3]);
  P_TLSH2 = atoi(argv[4]);
  P_TLSH1 = atoi(argv[5]);
  P_H2C = atoi(argv[6]);
  CA = argv[7];
  if (!strcmp(argv[1], "V-version")) v_version();
  else if (!strcmp(argv[1], "S-together")) s_together();
  else if (!strcmp(argv[1], "S-after-head")) s_after(0);
  else if (!strcmp(argv[1], "S-after-end")) s_after(1);
  else if (!strcmp(argv[1], "S-h1-wait")) s_h1_wait();
  else if (!strcmp(argv[1], "W-sibling")) w_sibling();
  else { fprintf(stderr, "probe: no case %s\n", argv[1]); return 2; }
  printf("case %s all done live_before_global_cleanup=%lld\n", argv[1], (long long)live_now());
  curl_global_cleanup();
  printf("case %s live_after_global_cleanup=%lld\n", argv[1], (long long)live_now());
  return 0;
}
