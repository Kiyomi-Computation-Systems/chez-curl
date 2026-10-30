/* M6's pause probe (2026-10-29; the M6 plan's measurements).

     probe --version
     probe CASE RAW TLS H2 CA

   RAW, TLS and H2 are server.mjs's ports; CA is the run's ca.pem. CASE is
   one of D-first D-every D-hold D-hold-mux D-clock D-chunk D-cancel U-frame
   U-pause U-rewind H-head P-noop, each run on the faces its comment names,
   or D-hold-control, a baseline run.sh runs only when CASES names it.
   Round 2 added W-busy W-lowspeed W-sibling W-unpause-gap W-replay-error
   R-first-read R-answer R-short R-overrun R-lowspeed R-reset-mid R-prereq
   R-refused R-empty U-rewind-fresh H-cl W-h2-gzip W-h2-error, each named
   for the source reading's hypothesis it measures; and R-reset-split, a
   supplement run.sh runs only when CASES names it.

   Every transfer goes through the multi interface, in a loop that mirrors
   chez-curl's engine turn: the message step (a resume, curl_easy_pause
   CONT, when a case's clock says so; a producer's new piece), the setup
   step (curl_multi_add_handle of a transfer whose time has come), the
   cancel step (curl_multi_remove_handle), curl_multi_perform,
   curl_multi_info_read, then curl_multi_poll for at most 1000 ms, less
   when the case's next scripted event is sooner: the engine's message
   would wake its poll then. A finished transfer is removed from its multi
   at once, as the engine does, but in P-noop.

   Every transfer gets the engine's options: PROTOCOLS_STR and
   REDIR_PROTOCOLS_STR "http,https", NOSIGNAL 1, FOLLOWLOCATION 0, PROXY
   "" (a proxy of #f), HTTP_VERSION 2TLS (8.x's default; 7.85.0's is 1.1),
   and on tls and h2 SSL_VERIFYPEER 1, SSL_VERIFYHOST 2, CAINFO at CA and
   CAPATH cleared. A setopt that answers other than CURLE_OK prints a line,
   but CAPATH's clear answering CURLE_NOT_BUILT_IN, which the engine takes.

   libcurl allocates through curl_global_init_mem's counting allocators:
   "live" is the bytes it holds through them at that moment. It does not
   see what the TLS library, nghttp2 or the kernel hold; zlib's state goes
   through libcurl's allocators.

   Output: lines "case NAME FACE key=value ...", NAME holding the variant
   after a colon, each transfer ending "case NAME FACE done code=N ...".
   Times are ms from the transfer's add, or from the case's start where a
   line says so. "server:" lines are server.mjs's log for the transfer's
   tag, fetched by GET /log on the raw face over a plain socket after the
   transfer, so no libcurl call stands between.

   PAUSE_NO_MULTIPLEX=1 in the environment (added for M6 slice 1, the M6
   plan's sections 3.4 and 7) sets CURLMOPT_PIPELINING to 0, CURLPIPE_NOTHING,
   on every multi handle the probe makes, printing a line for each, as the
   engine does on 8.7.0 and 8.7.1; and after D-hold-mux's and W-h2-error's
   transfers it asks the server how many connections the case's tags used,
   printing "conns" lines. Unset, or anything but 1, every case runs as
   before. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <curl/curl.h>

static int P_RAW, P_TLS, P_H2;
static const char *CA;
static int in_pause;             /* 1 while the loop is inside curl_easy_pause */
#ifndef CURL_WRITEFUNC_ERROR
#define CURL_WRITEFUNC_ERROR 0xFFFFFFFF  /* 7.87.0; before it, any wrong count is the same error */
#endif

/* ---------------------------------------------------------------- clocks */
static double abs_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

/* cpu_ms: the process's CPU time. mono_ns: the clock Node's
   process.hrtime.bigint() reads: CLOCK_MONOTONIC on Linux, mach_absolute_time
   (CLOCK_UPTIME_RAW) on macOS. */
static double cpu_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}
static long long mono_ns(void) {
  struct timespec ts;
#ifdef __APPLE__
  clock_gettime(CLOCK_UPTIME_RAW, &ts);
#else
  clock_gettime(CLOCK_MONOTONIC, &ts);
#endif
  return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
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
static int port_of(const char *f) { return !strcmp(f, "raw") ? P_RAW : !strcmp(f, "tls") ? P_TLS : P_H2; }
static const char *FACES[] = { "raw", "tls", "h2" };

/* ---------------------------------------------------------------- transfers */
enum { W_NONE, W_FIRST, W_EVERY, W_AT, W_ERR0, W_WFERR };
enum { R_NONE, R_READY, R_PRODUCER, R_SCHED, R_SHORT, R_OVERRUN };
enum { S_NONE, S_CANT, S_OK };
#define PIECE 16384

typedef struct xfer {
  CURL *h;
  char name[64], face[8], tag[200];
  struct curl_slist *hl;
  double t_add, add_at;
  int added, done, removed, keep_after_done, gave_up;
  CURLcode code;
  double t_end;
  long lport_seen;
  /* write side */
  int wpol;
  double hold;
  int64_t at_bytes;
  int paused, pause_noted, just_resumed, pauses, resumes, cancel_on_pause;
  double paused_at, resume_at;
  int print_calls, print_first, calls, calls_inpause, calls_while_paused, repaused_inside;
  int64_t total, first_bad;
  size_t max_chunk, max_before, first_after, max_after;
  int first_after_pending;
  unsigned char *refused;
  size_t refused_len;
  int rd_equal, rd_longer, rd_shorter, rd_differ;
  int64_t live_cb_pause, live_after_pause, live_before_resume, peak_in_pause;
  int capture;
  char resp[16384];
  size_t resp_len;
  /* read side */
  int rmode, smode, print_reads;
  int64_t up_len, up_off, produced;
  int end_ready, rpaused, reads, reads_inpause, seeks;
  double next_piece;
  /* header and debug logs */
  int hlog, seq, dlog;
  size_t dout_bytes;
  int dout_events;
  /* round 2 */
  int err_done, calls_after_err;
  int64_t bytes_inpause, bytes_after_err;
  int busy, turns_p, polls_p, short_polls_p;
  double cpu_start, cpu_end, wall_start, wall_end;
  int gap_watch, gap_pending;
  double t_cont_ret;
  int hcl, evlog, evseq, prereq_n, prereq_abort_at;
  int sched_n, sched_given;
  double sched_at[64], sched_end_at;
  int64_t sched_bytes[64], sched_avail;
  int64_t short_len;
  int overran, fail_watch, reads_after_fail;
  double fail_t;
  long long first_read_mono;
  double first_read_t;
} xfer;

static double rel(const xfer *x) { return abs_ms() - x->t_add; }

#define SAY(x, ...) do { printf("case %s %s ", (x)->name, (x)->face); printf(__VA_ARGS__); putchar('\n'); } while (0)

static void esc(const char *d, size_t n, char *out, size_t cap) {
  size_t o = 0, i;
  for (i = 0; i < n && o + 5 < cap; i++) {
    unsigned char c = (unsigned char)d[i];
    if (c == '\r') { out[o++] = '\\'; out[o++] = 'r'; }
    else if (c == '\n') { out[o++] = '\\'; out[o++] = 'n'; }
    else if (c == '\\' || c == '"' || c < 0x20 || c > 0x7e) o += (size_t)snprintf(out + o, cap - o, "\\x%02x", c);
    else out[o++] = (char)c;
  }
  if (i < n) o += (size_t)snprintf(out + o, cap - o, "...(%zu bytes)", n);
  out[o] = 0;
}

static size_t on_write(char *d, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t len = sz * nm, i;
  int inp = in_pause, pause = 0;
  const char *rd = "-";
  int pr;
  x->calls++;
  pr = x->print_calls || x->calls <= x->print_first;
  if (inp) x->calls_inpause++;
  if (x->paused) {
    x->calls_while_paused++;
    SAY(x, "call n=%d t=%.1f size=%zu while-paused (the probe has not resumed it) inpause=%d", x->calls, rel(x), len, inp);
  }
  if (x->refused) {
    if (len == x->refused_len && !memcmp(d, x->refused, len)) { rd = "equal"; x->rd_equal++; }
    else if (len > x->refused_len && !memcmp(d, x->refused, x->refused_len)) { rd = "longer,starts-with-refused"; x->rd_longer++; }
    else if (len < x->refused_len && !memcmp(d, x->refused, len)) { rd = "shorter,prefix-of-refused"; x->rd_shorter++; }
    else { rd = "differs"; x->rd_differ++; }
    free(x->refused);
    x->refused = NULL;
  }
  if (x->hlog) { x->seq++; SAY(x, "write seq=%d t=%.1f size=%zu", x->seq, rel(x), len); }
  if (x->capture) {
    size_t k = len < sizeof x->resp - 1 - x->resp_len ? len : sizeof x->resp - 1 - x->resp_len;
    memcpy(x->resp + x->resp_len, d, k);
    x->resp_len += k;
    x->resp[x->resp_len] = 0;
    x->total += (int64_t)len;
    return len;
  }
  if (x->wpol == W_WFERR && !x->err_done) {
    x->err_done = 1;
    SAY(x, "call n=%d t=%.1f size=%zu answer=CURL_WRITEFUNC_ERROR", x->calls, rel(x), len);
    return CURL_WRITEFUNC_ERROR;
  }
  if (x->wpol == W_ERR0 && inp && !x->err_done) {
    x->err_done = 1;
    SAY(x, "call n=%d t=%.1f size=%zu inpause=1 answer=0 (the wrong count, inside the unpause)", x->calls, rel(x), len);
    return 0;
  }
  if (x->wpol == W_ERR0 && x->err_done) { x->calls_after_err++; x->bytes_after_err += (int64_t)len; }
  switch (x->wpol) {
  case W_FIRST: case W_ERR0: pause = x->calls == 1; break;
  case W_EVERY: pause = !x->just_resumed; break;
  case W_AT: pause = !x->pauses && x->total >= x->at_bytes; break;
  default: break;
  }
  x->just_resumed = 0;
  if (pause) {
    x->refused = malloc(len ? len : 1);
    memcpy(x->refused, d, len);
    x->refused_len = len;
    x->paused = 1;
    x->pause_noted = 0;
    x->pauses++;
    x->paused_at = abs_ms();
    x->resume_at = x->paused_at + x->hold;
    x->live_cb_pause = live_now();
    if (pr) SAY(x, "call n=%d t=%.1f size=%zu inpause=%d answer=PAUSE redelivery=%s total=%lld", x->calls, rel(x), len, inp, rd, (long long)x->total);
    return CURL_WRITEFUNC_PAUSE;
  }
  for (i = 0; i < len && x->first_bad < 0; i++)
    if ((unsigned char)d[i] != (unsigned char)((x->total + (int64_t)i) % 251)) x->first_bad = x->total + (int64_t)i;
  x->total += (int64_t)len;
  if (inp) x->bytes_inpause += (int64_t)len;
  if (len > x->max_chunk) x->max_chunk = len;
  if (!x->pauses) { if (len > x->max_before) x->max_before = len; }
  else {
    if (x->first_after_pending) { x->first_after = len; x->first_after_pending = 0; }
    if (len > x->max_after) x->max_after = len;
  }
  if (pr) SAY(x, "call n=%d t=%.1f size=%zu inpause=%d answer=accept redelivery=%s total=%lld", x->calls, rel(x), len, inp, rd, (long long)x->total);
  return len;
}

static size_t on_read(char *buf, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t room = sz * nm, i;
  int64_t avail, piece_left, give;
  int inp = in_pause;
  x->reads++;
  if (inp) x->reads_inpause++;
  if (x->reads == 1) { x->first_read_mono = mono_ns(); x->first_read_t = rel(x); }
  if (x->fail_t > 0) x->reads_after_fail++;
  if (x->rmode == R_SHORT || x->rmode == R_OVERRUN || x->rmode == R_SCHED) {
    int64_t g;
    const char *why = "";
    if (x->rmode == R_SHORT) g = x->short_len - x->up_off;
    else if (x->rmode == R_OVERRUN) g = x->overran ? 0 : 1500;
    else {
      g = x->sched_avail - x->up_off;
      if (g <= 0 && !x->end_ready) {
        x->rpaused = 1;
        x->evseq++;
        SAY(x, "read n=%d ev=%d t=%.1f room=%zu inpause=%d answer=PAUSE (producer empty, offset %lld)", x->reads, x->evseq, rel(x), room, inp, (long long)x->up_off);
        return CURL_READFUNC_PAUSE;
      }
    }
    if (g < 0) g = 0;
    if ((int64_t)room < g) { g = (int64_t)room; why = " (cut to room)"; }
    for (i = 0; i < (size_t)g; i++) buf[i] = (char)((x->up_off + (int64_t)i) % 251);
    x->up_off += g;
    if (x->rmode == R_OVERRUN && g > 0) x->overran = 1;
    x->evseq++;
    SAY(x, "read n=%d ev=%d t=%.1f room=%zu inpause=%d answer=%lld%s offset=%lld", x->reads, x->evseq, rel(x), room, inp, (long long)g, why, (long long)x->up_off);
    return (size_t)g;
  }
  if (x->rmode == R_PRODUCER) {
    avail = x->produced - x->up_off;
    if (avail <= 0) {
      if (x->end_ready) {
        if (x->print_reads) SAY(x, "read n=%d t=%.1f room=%zu inpause=%d answer=0 (the end)", x->reads, rel(x), room, inp);
        return 0;
      }
      x->rpaused = 1;
      if (x->print_reads) SAY(x, "read n=%d t=%.1f room=%zu inpause=%d answer=PAUSE (producer empty, offset %lld)", x->reads, rel(x), room, inp, (long long)x->up_off);
      return CURL_READFUNC_PAUSE;
    }
  } else {
    avail = x->up_len - x->up_off;
  }
  piece_left = PIECE - (x->up_off % PIECE);
  give = avail < piece_left ? avail : piece_left;
  if ((int64_t)room < give) give = (int64_t)room;
  for (i = 0; i < (size_t)give; i++) buf[i] = (char)((x->up_off + (int64_t)i) % 251);
  x->up_off += give;
  if (x->evlog) { x->evseq++; SAY(x, "read n=%d ev=%d t=%.1f room=%zu inpause=%d answer=%lld offset=%lld", x->reads, x->evseq, rel(x), room, inp, (long long)give, (long long)x->up_off); }
  else if (x->print_reads) SAY(x, "read n=%d t=%.1f room=%zu inpause=%d answer=%lld offset=%lld", x->reads, rel(x), room, inp, (long long)give, (long long)x->up_off);
  return (size_t)give;
}

static int on_seek(void *u, curl_off_t off, int origin) {
  xfer *x = u;
  x->seeks++;
  if (x->evlog) {
    x->evseq++;
    SAY(x, "seek n=%d ev=%d t=%.1f offset=%lld origin=%d answer=%s", x->seeks, x->evseq, rel(x), (long long)off, origin,
        x->smode == S_CANT ? "CANTSEEK" : (origin == SEEK_SET && off >= 0 && off <= x->up_len) ? "OK" : "FAIL");
  } else
  SAY(x, "seek n=%d t=%.1f offset=%lld origin=%d answer=%s", x->seeks, rel(x), (long long)off, origin,
      x->smode == S_CANT ? "CANTSEEK" : (origin == SEEK_SET && off >= 0 && off <= x->up_len) ? "OK" : "FAIL");
  if (x->smode == S_CANT) return CURL_SEEKFUNC_CANTSEEK;
  if (origin != SEEK_SET || off < 0 || off > x->up_len) return CURL_SEEKFUNC_FAIL;
  x->up_off = off;
  return CURL_SEEKFUNC_OK;
}

/* on_prereq: CURLOPT_PREREQFUNCTION, counted and logged; ABORT on call
   PREREQ_ABORT_AT when that is set. */
static int on_prereq(void *u, char *pip, char *lip, int pport, int lport) {
  xfer *x = u;
  int ab;
  (void)pip; (void)lip; (void)pport;
  x->prereq_n++;
  x->evseq++;
  ab = x->prereq_abort_at && x->prereq_n == x->prereq_abort_at;
  SAY(x, "prereq n=%d ev=%d t=%.1f local_port=%d answer=%s", x->prereq_n, x->evseq, rel(x), lport, ab ? "ABORT" : "OK");
  return ab ? CURL_PREREQFUNC_ABORT : CURL_PREREQFUNC_OK;
}

static void flush_dout(xfer *x) {
  if (x->dout_events) SAY(x, "debug t=%.1f data_out events=%d bytes=%zu", rel(x), x->dout_events, x->dout_bytes);
  x->dout_events = 0;
  x->dout_bytes = 0;
}

static int on_debug(CURL *h, curl_infotype type, char *d, size_t n, void *u) {
  xfer *x = u;
  char e[600];
  (void)h;
  if (type == CURLINFO_DATA_OUT) { x->dout_events++; x->dout_bytes += n; return 0; }
  if (type != CURLINFO_TEXT && type != CURLINFO_HEADER_OUT && type != CURLINFO_HEADER_IN) return 0;
  flush_dout(x);
  if (type == CURLINFO_HEADER_OUT) {
    size_t k = 0;
    while (k < n && d[k] != '\r') k++;
    esc(d, k, e, sizeof e);
    SAY(x, "debug t=%.1f header_out bytes=%zu first=\"%s\"", rel(x), n, e);
    return 0;
  }
  while (n && (d[n - 1] == '\n' || d[n - 1] == '\r')) n--;
  esc(d, n, e, sizeof e);
  SAY(x, "debug t=%.1f %s \"%s\"", rel(x), type == CURLINFO_TEXT ? "text" : "header_in", e);
  if (x->fail_watch && x->fail_t <= 0 && type == CURLINFO_TEXT &&
      (strstr(e, "ailure") || strstr(e, "died") || strstr(e, "reset") || strstr(e, "abort")))
    x->fail_t = rel(x);
  return 0;
}

static void dump_headers(xfer *x, unsigned int origin, const char *label) {
  struct curl_header *p = NULL;
  char line[4096], e[600];
  size_t o = 0;
  int n = 0;
  line[0] = 0;
  while ((p = curl_easy_nextheader(x->h, origin, -1, p))) {
    char kv[1024];
    n++;
    snprintf(kv, sizeof kv, "%s: %s", p->name, p->value);
    esc(kv, strlen(kv), e, sizeof e);
    o += (size_t)snprintf(line + o, sizeof line - o, "%s%s", n > 1 ? " | " : "", e);
    if (o >= sizeof line) break;
  }
  SAY(x, "head-end %s count=%d [%s]", label, n, line);
}

static size_t on_header(char *d, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t len = sz * nm;
  char e[1200];
  if (x->hcl && len == 2 && d[0] == '\r' && d[1] == '\n') {
    curl_off_t cl = -2;
    long st = 0;
    CURLcode rc = curl_easy_getinfo(x->h, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &cl);
    curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
    SAY(x, "head-end t=%.1f response_code=%ld content_length_download_t=%lld getinfo_rc=%d", rel(x), st, (long long)cl, (int)rc);
  }
  if (!x->hlog) return len;
  x->seq++;
  esc(d, len, e, sizeof e);
  SAY(x, "hdr seq=%d t=%.1f \"%s\"", x->seq, rel(x), e);
  if (len == 2 && d[0] == '\r' && d[1] == '\n') {
    long st = 0;
    curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
    SAY(x, "head-end seq=%d response_code=%ld", x->seq, st);
    dump_headers(x, CURLH_HEADER, "CURLH_HEADER");
    dump_headers(x, CURLH_1XX, "CURLH_1XX");
  }
  return len;
}

#define SETOPT(x, opt, val) do { CURLcode rc_ = curl_easy_setopt((x)->h, opt, val); \
    if (rc_ != CURLE_OK && !(opt == CURLOPT_CAPATH && rc_ == CURLE_NOT_BUILT_IN)) \
      SAY(x, "setopt %s rc=%d", #opt, (int)rc_); } while (0)

/* mk: a transfer NAME on FACE of PATHQ, its tag NAME.FACE, with the
   engine's options. */
static xfer *mk(const char *name, const char *face, const char *pathq) {
  xfer *x = calloc(1, sizeof *x);
  char url[600], *c;
  snprintf(x->name, sizeof x->name, "%s", name);
  snprintf(x->face, sizeof x->face, "%s", face);
  snprintf(x->tag, sizeof x->tag, "%s.%s", name, face);
  for (c = x->tag; *c; c++) if (*c == ':' || *c == '/') *c = '.';
  x->first_bad = -1;
  x->h = curl_easy_init();
  snprintf(url, sizeof url, "%s://127.0.0.1:%d%s%stag=%s", strcmp(face, "raw") ? "https" : "http", port_of(face), pathq,
           strchr(pathq, '?') ? "&" : "?", x->tag);
  SETOPT(x, CURLOPT_URL, url);
  SETOPT(x, CURLOPT_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_NOSIGNAL, 1L);
  SETOPT(x, CURLOPT_FOLLOWLOCATION, 0L);
  SETOPT(x, CURLOPT_PROXY, "");
  SETOPT(x, CURLOPT_HTTP_VERSION, (long)CURL_HTTP_VERSION_2TLS);
  if (strcmp(face, "raw")) {
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

static void upload_opts(xfer *x, int put, int64_t size) {
  x->rmode = x->rmode ? x->rmode : R_READY;
  SETOPT(x, CURLOPT_READFUNCTION, on_read);
  SETOPT(x, CURLOPT_READDATA, x);
  if (put) {
    SETOPT(x, CURLOPT_UPLOAD, 1L);
    SETOPT(x, CURLOPT_INFILESIZE_LARGE, (curl_off_t)size);
  } else {
    SETOPT(x, CURLOPT_POST, 1L);
    SETOPT(x, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)size);
  }
  x->capture = 1;
}

static void resume(xfer *x) {
  CURLcode rc;
  int before = x->calls;
  double t1, held;
  x->live_before_resume = live_now();
  x->peak_in_pause = win_peak;
  x->paused = 0;
  x->just_resumed = 1;
  x->resumes++;
  if (x->pauses == 1) x->first_after_pending = 1;
  if (x->busy) { x->cpu_end = cpu_ms(); x->wall_end = abs_ms(); }
  t1 = abs_ms();
  held = t1 - x->paused_at;
  in_pause = 1;
  rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
  in_pause = 0;
  if (x->gap_watch && x->resumes == 1) { x->t_cont_ret = abs_ms(); x->gap_pending = 1; }
  if (x->print_calls || x->resumes <= x->print_first)
    SAY(x, "resume n=%d t=%.1f held=%.1f rc=%d calls_inside=%d repaused_inside=%d took=%.2f", x->resumes, t1 - x->t_add, held, (int)rc, x->calls - before, x->paused, abs_ms() - t1);
  else if (rc != CURLE_OK) SAY(x, "resume n=%d rc=%d", x->resumes, (int)rc);
  if (x->paused) x->repaused_inside++;
}

static void producer_step(xfer *x, double t) {
  int gained = 0, end = 0;
  while (x->produced < x->up_len && t >= x->next_piece) { x->produced += PIECE; x->next_piece += 100; gained++; }
  if (x->produced >= x->up_len && !x->end_ready && t >= x->next_piece) { x->end_ready = 1; end = 1; }
  if (!gained && !end) return;
  if (x->rpaused) {
    CURLcode rc;
    int rb = x->reads;
    double t1 = abs_ms();
    x->rpaused = 0;
    in_pause = 1;
    rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
    in_pause = 0;
    SAY(x, "cont t=%.1f for=%s produced=%lld rc=%d reads_inside=%d took=%.2f", t1 - x->t_add, end ? "the-end" : "a-piece", (long long)x->produced, (int)rc, x->reads - rb, abs_ms() - t1);
  } else {
    SAY(x, "producer t=%.1f gained %s produced=%lld, the read side not paused: no CONT", t - x->t_add, end ? "the-end" : "a-piece", (long long)x->produced);
  }
}

static void sched_step(xfer *x, double t) {
  int gained = 0, end = 0;
  while (x->sched_given < x->sched_n && t - x->t_add >= x->sched_at[x->sched_given]) {
    x->sched_avail += x->sched_bytes[x->sched_given];
    x->sched_given++;
    gained++;
  }
  if (!x->end_ready && x->sched_end_at > 0 && t - x->t_add >= x->sched_end_at) { x->end_ready = 1; end = 1; }
  if (!gained && !end) return;
  if (x->rpaused) {
    CURLcode rc;
    int rb = x->reads;
    double t1 = abs_ms();
    x->rpaused = 0;
    in_pause = 1;
    rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
    in_pause = 0;
    SAY(x, "cont t=%.1f for=%s available=%lld rc=%d reads_inside=%d", t1 - x->t_add, end ? "the-end" : "a-piece", (long long)x->sched_avail, (int)rc, x->reads - rb);
  } else {
    SAY(x, "producer t=%.1f gained %s available=%lld, the read side not paused: no CONT", t - x->t_add, end ? "the-end" : "a-piece", (long long)x->sched_avail);
  }
}

static double sched_next(const xfer *x) {
  double n = 1e18;
  if (x->sched_given < x->sched_n) n = x->t_add + x->sched_at[x->sched_given];
  if (!x->end_ready && x->sched_end_at > 0 && x->t_add + x->sched_end_at < n) n = x->t_add + x->sched_end_at;
  return n;
}

/* the tick: a case's own line every G_TICK_EVERY ms, from drive */
static void (*g_tick)(void);
static double g_tick_every, g_tick_next;

static void finish(CURLM *m, xfer *x) {
  long st = 0, ver = 0, conns = -1, lport = -1;
  curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
  curl_easy_getinfo(x->h, CURLINFO_HTTP_VERSION, &ver);
  curl_easy_getinfo(x->h, CURLINFO_NUM_CONNECTS, &conns);
  curl_easy_getinfo(x->h, CURLINFO_LOCAL_PORT, &lport);
  x->lport_seen = lport;
  if (x->gap_pending) {
    SAY(x, "unpause-gap done_before_next_poll cont_to_done=%.2f", x->t_end - x->t_cont_ret);
    x->gap_pending = 0;
  }
  if (!x->keep_after_done) { curl_multi_remove_handle(m, x->h); x->removed = 1; }
  if (x->dlog) flush_dout(x);
  if (x->code)
    SAY(x, "done code=%d err=\"%s\" t=%.1f status=%ld ver=%ld conns=%ld lport=%ld", (int)x->code, curl_easy_strerror(x->code), x->t_end - x->t_add, st, ver, conns, lport);
  else
    SAY(x, "done code=0 t=%.1f status=%ld ver=%ld conns=%ld lport=%ld", x->t_end - x->t_add, st, ver, conns, lport);
}

static void add(CURLM *m, xfer *x) {
  CURLMcode mc;
  x->t_add = abs_ms();
  if (x->rmode == R_PRODUCER) x->next_piece = x->t_add + 100;
  mc = curl_multi_add_handle(m, x->h);
  x->added = 1;
  if (mc) SAY(x, "multi_add rc=%d", (int)mc);
}

/* drive: the engine's turn over XS until each is done or removed, or
   BOUND ms pass. */
static void drive(CURLM *m, xfer **xs, int nx, double bound) {
  double start = abs_ms();
  int i, running;
  for (;;) {
    double t = abs_ms(), wait = 1000;
    int open = 0;
    CURLMsg *msg;
    int q;
    for (i = 0; i < nx; i++) {               /* the message step */
      xfer *x = xs[i];
      if (!x->added || x->done || x->removed) continue;
      if (x->rmode == R_PRODUCER) producer_step(x, t);
      if (x->rmode == R_SCHED) sched_step(x, t);
      if (x->busy && x->paused && x->pause_noted) x->turns_p++;
      if (x->paused && !x->cancel_on_pause && t >= x->resume_at) resume(x);
    }
    if (g_tick && g_tick_every > 0 && t >= g_tick_next) { g_tick(); g_tick_next += g_tick_every; }
    for (i = 0; i < nx; i++)                 /* the setup step */
      if (!xs[i]->added && t >= xs[i]->add_at) add(m, xs[i]);
    for (i = 0; i < nx; i++) {               /* the cancel step */
      xfer *x = xs[i];
      if (x->added && !x->done && !x->removed && x->cancel_on_pause && x->paused && t >= x->resume_at) {
        CURLMcode mc;
        int64_t l0 = live_now();
        x->live_before_resume = l0;
        mc = curl_multi_remove_handle(m, x->h);
        x->removed = 1;
        SAY(x, "cancel t=%.1f held=%.1f remove_rc=%d live_before=%lld live_after_remove=%lld", rel(x), abs_ms() - x->paused_at, (int)mc, (long long)l0, (long long)live_now());
      }
    }
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
        if (x->busy && x->pauses == 1) { x->cpu_start = cpu_ms(); x->wall_start = abs_ms(); }
      }
      if (!x->added) { open = 1; if (x->add_at - abs_ms() < wait) wait = x->add_at - abs_ms(); }
      else if (!x->done && !x->removed) {
        open = 1;
        if (x->paused && x->resume_at - abs_ms() < wait) wait = x->resume_at - abs_ms();
        if (x->rmode == R_PRODUCER && x->next_piece - abs_ms() < wait) wait = x->next_piece - abs_ms();
        if (x->rmode == R_SCHED && sched_next(x) - abs_ms() < wait) wait = sched_next(x) - abs_ms();
      }
    }
    if (g_tick && g_tick_every > 0 && g_tick_next - abs_ms() < wait) wait = g_tick_next - abs_ms();
    if (start + bound - abs_ms() < wait) wait = start + bound - abs_ms();
    if (!open) return;
    if (abs_ms() - start > bound) {
      for (i = 0; i < nx; i++) {
        xfer *x = xs[i];
        if (x->added && !x->done && !x->removed) {
          SAY(x, "gave-up after %.0f ms: the probe's own bound; paused=%d", bound, x->paused);
          curl_multi_remove_handle(m, x->h);
          x->removed = 1;
          x->gave_up = 1;
        }
      }
      return;
    }
    if (wait < 0) wait = 0;
    {
      double p0 = abs_ms(), p1;
      int nfds = -1, targ = (int)(wait + 0.999);
      curl_multi_poll(m, NULL, 0, targ, &nfds);
      p1 = abs_ms();
      for (i = 0; i < nx; i++) {
        xfer *x = xs[i];
        if (x->busy && x->paused && x->pause_noted) { x->polls_p++; if (p1 - p0 < 1.0) x->short_polls_p++; }
        if (x->gap_pending) {
          SAY(x, "unpause-gap cont_to_poll_start=%.2f poll_timeout_arg=%d poll_took=%.2f numfds=%d cont_to_poll_return=%.2f waited=%d",
              p0 - x->t_cont_ret, targ, p1 - p0, nfds, p1 - x->t_cont_ret, p1 - p0 >= 1.0);
          x->gap_pending = 0;
        }
      }
    }
  }
}

static void drop(xfer *x) {
  if (x->h) curl_easy_cleanup(x->h);
  x->h = NULL;
  if (x->hl) curl_slist_free_all(x->hl);
  x->hl = NULL;
  free(x->refused);
  free(x);
}

static void summary(xfer *x) {
  char pat[40];
  if (x->first_bad < 0) snprintf(pat, sizeof pat, "ok"); else snprintf(pat, sizeof pat, "bad@%lld", (long long)x->first_bad);
  SAY(x, "summary calls=%d inpause_calls=%d while_paused_calls=%d pauses=%d resumes=%d repaused_inside=%d total=%lld pattern=%s max_chunk=%zu max_before=%zu first_after=%zu max_after=%zu redelivery_equal=%d longer=%d shorter=%d differs=%d",
      x->calls, x->calls_inpause, x->calls_while_paused, x->pauses, x->resumes, x->repaused_inside, (long long)x->total, pat, x->max_chunk, x->max_before, x->first_after, x->max_after,
      x->rd_equal, x->rd_longer, x->rd_shorter, x->rd_differ);
}

/* server_log: GET /log?tag=TAG on the raw face, over a plain socket, each
   body line printed as X's. */
static void server_log_text(xfer *x, char *out, size_t outcap);
static void server_log(xfer *x) { server_log_text(x, NULL, 0); }
static void server_log_text(xfer *x, char *out, size_t outcap) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in sa;
  struct timeval tv = { 6, 0 };
  char req[400], *buf, *body, *line, *nl;
  size_t cap = 1 << 20, n = 0;
  ssize_t k;
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET;
  sa.sin_port = htons((unsigned short)P_RAW);
  sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
  if (connect(fd, (struct sockaddr *)&sa, sizeof sa)) { SAY(x, "server: log fetch failed to connect"); close(fd); return; }
  snprintf(req, sizeof req, "GET /log?tag=%s HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n", x->tag);
  if (write(fd, req, strlen(req)) != (ssize_t)strlen(req)) { SAY(x, "server: log fetch write failed"); close(fd); return; }
  buf = malloc(cap + 1);
  while (n < cap && (k = read(fd, buf + n, cap - n)) > 0) n += (size_t)k;
  close(fd);
  buf[n] = 0;
  body = strstr(buf, "\r\n\r\n");
  if (!body) { SAY(x, "server: log fetch got no head (%zu bytes)", n); free(buf); return; }
  if (out && outcap) snprintf(out, outcap, "%s", body + 4);
  for (line = body + 4; *line; line = nl + 1) {
    nl = strchr(line, '\n');
    if (!nl) { if (*line) SAY(x, "server: %s", line); break; }
    *nl = 0;
    SAY(x, "server: %s", line);
  }
  free(buf);
}

static void sink_line(xfer *x, int with_arrivals) {
  char *p;
  while (x->resp_len && (x->resp[x->resp_len - 1] == '\n')) x->resp[--x->resp_len] = 0;
  if (!with_arrivals && (p = strstr(x->resp, " arr="))) *p = 0;
  SAY(x, "reads=%d reads_inpause=%d seeks=%d answer: %s", x->reads, x->reads_inpause, x->seeks, x->resp_len ? x->resp : "(none)");
}

static int no_multiplex(void) {
  const char *v = getenv("PAUSE_NO_MULTIPLEX");
  return v && !strcmp(v, "1");
}

static CURLM *new_multi(void) {
  CURLM *m = curl_multi_init();
  if(m && no_multiplex()) {
    CURLMcode rc = curl_multi_setopt(m, CURLMOPT_PIPELINING, (long)CURLPIPE_NOTHING);
    printf("multi pipelining=0 (PAUSE_NO_MULTIPLEX=1) rc=%d\n", (int)rc);
  }
  return m;
}

/* server_conns: GET /conns?prefix=PREFIX on the raw face, over a plain
   socket, its answer printed as one line under LABEL: the connections, by
   face and client port, every tag beginning PREFIX used. With
   PAUSE_NO_MULTIPLEX=1 alone. */
static void server_conns(const char *label, const char *prefix) {
  int fd;
  struct sockaddr_in sa;
  struct timeval tv = { 6, 0 };
  char req[400], buf[4096], *body;
  size_t n = 0;
  ssize_t k;
  if(!no_multiplex()) return;
  fd = socket(AF_INET, SOCK_STREAM, 0);
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET;
  sa.sin_port = htons((unsigned short)P_RAW);
  sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
  if(connect(fd, (struct sockaddr *)&sa, sizeof sa)) { printf("case %s conns: fetch failed to connect\n", label); close(fd); return; }
  snprintf(req, sizeof req, "GET /conns?prefix=%s HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n", prefix);
  if(write(fd, req, strlen(req)) != (ssize_t)strlen(req)) { printf("case %s conns: fetch write failed\n", label); close(fd); return; }
  while(n < sizeof buf - 1 && (k = read(fd, buf + n, sizeof buf - 1 - n)) > 0) n += (size_t)k;
  close(fd);
  buf[n] = 0;
  body = strstr(buf, "\r\n\r\n");
  if(!body) { printf("case %s conns: no head (%zu bytes)\n", label, n); return; }
  body += 4;
  if(*body && body[strlen(body) - 1] == '\n') body[strlen(body) - 1] = 0;
  printf("case %s %s\n", label, body);
}

/* ---------------------------------------------------------------- cases */

/* D-first: 1 MiB, Content-Length; pause on the first call, resume 200 ms
   later. Each call printed. raw, tls, h2. */
static void d_first(void) {
  int f;
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    xfer *x = mk("D-first", FACES[f], "/body?n=1048576&mode=length&chunk=65536");
    x->wpol = W_FIRST; x->hold = 200; x->print_calls = 1;
    drive(m, &x, 1, 30000);
    summary(x);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* D-every: pause on every call but the first after a resume, resume each
   1 ms later. Length on raw, tls, h2; chunked and close on raw. Calls are
   counted, not printed one by one; the first 6 are. */
static void d_every_one(const char *name, const char *face, const char *pq) {
  CURLM *m = new_multi();
  xfer *x = mk(name, face, pq);
  x->wpol = W_EVERY; x->hold = 1; x->print_first = 6;
  drive(m, &x, 1, 30000);
  summary(x);
  drop(x);
  curl_multi_cleanup(m);
}
static void d_every(void) {
  int f;
  for (f = 0; f < 3; f++) d_every_one("D-every:length", FACES[f], "/body?n=1048576&mode=length&chunk=65536");
  d_every_one("D-every:chunked", "raw", "/body?n=1048576&mode=chunked&chunk=65536");
  d_every_one("D-every:close", "raw", "/body?n=1048576&mode=close&chunk=65536");
}

/* D-hold: 8 MiB, written 4 KiB a write; paused at the first call for 2 s.
   libcurl's live bytes around the pause, and the server's backpressure. */
static void d_hold(void) {
  int f;
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    int64_t base;
    xfer *x = mk("D-hold", FACES[f], "/body?n=8388608&mode=length&chunk=4096");
    x->wpol = W_FIRST; x->hold = 2000; x->print_calls = 0;
    base = live_now();
    drive(m, &x, 1, 30000);
    summary(x);
    SAY(x, "live base=%lld in_callback_at_pause=%lld after_pausing_perform=%lld before_resume=%lld peak_during_pause=%lld",
        (long long)base, (long long)x->live_cb_pause, (long long)x->live_after_pause, (long long)x->live_before_resume, (long long)x->peak_in_pause);
    server_log(x);
    curl_easy_cleanup(x->h);
    x->h = NULL;
    SAY(x, "live after_easy_cleanup=%lld", (long long)live_now());
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* D-hold-control, not in run.sh's default list: D-hold's 8 MiB, 4 KiB a
   write, never paused, so D-hold's live bytes after the easy cleanup have
   a baseline. Added after the kept runs, on 8.5.0's h2 lanes holding
   3.3 MB to 5.2 MB there; run by CASES=D-hold-control. */
static void d_hold_control(void) {
  int f;
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    int64_t base, done_live;
    xfer *x = mk("D-hold-control", FACES[f], "/body?n=8388608&mode=length&chunk=4096");
    base = live_now();
    win_peak = base;
    drive(m, &x, 1, 30000);
    done_live = live_now();
    summary(x);
    curl_easy_cleanup(x->h);
    x->h = NULL;
    SAY(x, "live base=%lld peak_during_transfer=%lld after_done=%lld after_easy_cleanup=%lld", (long long)base, (long long)win_peak,
        (long long)done_live, (long long)live_now());
    drop(x);
    curl_multi_cleanup(m);
    printf("case D-hold-control %s live after_multi_cleanup=%lld\n", FACES[f], (long long)live_now());
  }
}

/* D-hold-mux: two transfers on h2 at once on one multi: A, 8 MiB, paused
   at its first call for 2 s; B, 1 MiB, never paused. With PIPEWAIT 1 on
   both, and with it left alone. Times from the case's start. */
static void d_hold_mux(void) {
  int pw;
  for (pw = 1; pw >= 0; pw--) {
    CURLM *m = new_multi();
    xfer *xs[2];
    double t0;
    char na[64], nb[64];
    snprintf(na, sizeof na, "D-hold-mux:pipewait%d:A", pw);
    snprintf(nb, sizeof nb, "D-hold-mux:pipewait%d:B", pw);
    xs[0] = mk(na, "h2", "/body?n=8388608&mode=length&chunk=4096");
    xs[1] = mk(nb, "h2", "/body?n=1048576&mode=length&chunk=4096");
    xs[0]->wpol = W_FIRST; xs[0]->hold = 2000;
    if (pw) { SETOPT(xs[0], CURLOPT_PIPEWAIT, 1L); SETOPT(xs[1], CURLOPT_PIPEWAIT, 1L); }
    t0 = abs_ms();
    xs[0]->add_at = t0;
    xs[1]->add_at = t0;
    drive(m, xs, 2, 30000);
    summary(xs[0]);
    summary(xs[1]);
    SAY(xs[0], "mux case_t A_paused_at=%.1f A_resumed_at=%.1f A_end=%.1f B_end=%.1f B_done_while_A_paused=%d A_lport=%ld B_lport=%ld",
        xs[0]->paused_at - t0, xs[0]->paused_at + xs[0]->hold - t0, xs[0]->t_end - t0, xs[1]->t_end - t0,
        xs[1]->done && xs[1]->t_end < xs[0]->paused_at + xs[0]->hold && xs[1]->t_end > xs[0]->paused_at, xs[0]->lport_seen, xs[1]->lport_seen);
    SAY(xs[0], "live in_callback_at_pause=%lld after_pausing_perform=%lld before_resume=%lld peak_during_pause=%lld",
        (long long)xs[0]->live_cb_pause, (long long)xs[0]->live_after_pause, (long long)xs[0]->live_before_resume, (long long)xs[0]->peak_in_pause);
    server_log(xs[0]);
    server_log(xs[1]);
    {
      char label[64], prefix[64];
      snprintf(label, sizeof label, "D-hold-mux:pipewait%d", pw);
      snprintf(prefix, sizeof prefix, "D-hold-mux.pipewait%d.", pw);
      server_conns(label, prefix);
    }
    drop(xs[0]);
    drop(xs[1]);
    curl_multi_cleanup(m);
  }
}

/* D-clock: 1 MiB, paused at the first call and held 3 s, with TIMEOUT_MS
   1000; then with LOW_SPEED_LIMIT 1 and LOW_SPEED_TIME 1 and no timeout. */
static void d_clock(void) {
  int f, v;
  for (f = 0; f < 3; f++) {
    for (v = 0; v < 2; v++) {
      CURLM *m = new_multi();
      xfer *x = mk(v ? "D-clock:lowspeed" : "D-clock:timeout", FACES[f], "/body?n=1048576&mode=length&chunk=16384");
      x->wpol = W_FIRST; x->hold = 3000; x->print_calls = 0;
      if (v) { SETOPT(x, CURLOPT_LOW_SPEED_LIMIT, 1L); SETOPT(x, CURLOPT_LOW_SPEED_TIME, 1L); }
      else SETOPT(x, CURLOPT_TIMEOUT_MS, 1000L);
      drive(m, &x, 1, 15000);
      SAY(x, "clock paused_at=%.1f resumed=%d resume_due=%.1f end=%.1f", x->paused_at - x->t_add, x->resumes, x->paused_at + x->hold - x->t_add, x->t_end - x->t_add);
      summary(x);
      server_log(x);
      drop(x);
      curl_multi_cleanup(m);
    }
  }
}

/* D-chunk: 2 MiB, 64 KiB a write; accept to 256 KiB, pause at the next
   call for 500 ms. BUFFERSIZE default, 1024, 524288. Then ACCEPT_ENCODING
   "" against gzip=1, 8 MiB decoded, paused at the first call for 1 s. */
static void d_chunk(void) {
  int f, b;
  long sizes[3] = { 0, 1024, 524288 };
  for (f = 0; f < 3; f++) {
    for (b = 0; b < 3; b++) {
      CURLM *m = new_multi();
      char nm[64];
      xfer *x;
      snprintf(nm, sizeof nm, "D-chunk:buffersize-%s", b ? (b == 1 ? "1024" : "524288") : "default");
      x = mk(nm, FACES[f], "/body?n=2097152&mode=length&chunk=65536");
      x->wpol = W_AT; x->at_bytes = 262144; x->hold = 500;
      if (sizes[b]) SETOPT(x, CURLOPT_BUFFERSIZE, sizes[b]);
      drive(m, &x, 1, 30000);
      summary(x);
      drop(x);
      curl_multi_cleanup(m);
    }
  }
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    int64_t base;
    xfer *x = mk("D-chunk:gzip", FACES[f], "/body?n=8388608&mode=length&chunk=16384&gzip=1");
    x->wpol = W_FIRST; x->hold = 1000;
    SETOPT(x, CURLOPT_ACCEPT_ENCODING, "");
    base = live_now();
    drive(m, &x, 1, 30000);
    summary(x);
    SAY(x, "live base=%lld in_callback_at_pause=%lld after_pausing_perform=%lld before_resume=%lld peak_during_pause=%lld",
        (long long)base, (long long)x->live_cb_pause, (long long)x->live_after_pause, (long long)x->live_before_resume, (long long)x->peak_in_pause);
    server_log(x);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* D-cancel: 1 MiB, paused at the first call; 200 ms on, removed while
   paused, then cleaned up. Then a second transfer, 1 KiB, on the same
   multi to the same face. */
static void d_cancel(void) {
  int f;
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    int64_t base = live_now(), l1, l2;
    long lp1 = -1;
    xfer *x = mk("D-cancel:first", FACES[f], "/body?n=1048576&mode=length&chunk=16384");
    xfer *y;
    x->wpol = W_FIRST; x->hold = 200; x->cancel_on_pause = 1;
    drive(m, &x, 1, 30000);
    curl_easy_getinfo(x->h, CURLINFO_LOCAL_PORT, &lp1);
    summary(x);
    l1 = live_now();
    curl_easy_cleanup(x->h);
    x->h = NULL;
    l2 = live_now();
    SAY(x, "live multi_base=%lld after_remove=%lld after_easy_cleanup=%lld lport=%ld", (long long)base, (long long)l1, (long long)l2, lp1);
    y = mk("D-cancel:second", FACES[f], "/body?n=1024&mode=length&chunk=1024");
    drive(m, &y, 1, 30000);
    summary(y);
    SAY(y, "reuse first_lport=%ld second_lport=%ld same_port=%d", lp1, y->lport_seen, lp1 == y->lport_seen);
    server_log(x);
    server_log(y);
    drop(y);
    SAY(x, "live after_second_cleanup=%lld", (long long)live_now());
    curl_multi_cleanup(m);
    SAY(x, "live after_multi_cleanup=%lld (what libcurl's global state holds)", (long long)live_now());
    drop(x);
  }
}

/* U-frame: 256 KiB by read callback in 16 KiB pieces; POST by
   POSTFIELDSIZE_LARGE N or -1, PUT by UPLOAD and INFILESIZE_LARGE N or -1,
   each also with CUSTOMREQUEST PATCH, each with and without an empty
   Expect: header. raw, tls, h2. */
static void u_frame(void) {
  int f, put, sized, patch, noexp;
  for (f = 0; f < 3; f++)
    for (put = 0; put < 2; put++)
      for (sized = 1; sized >= 0; sized--)
        for (patch = 0; patch < 2; patch++)
          for (noexp = 0; noexp < 2; noexp++) {
            CURLM *m = new_multi();
            char nm[64];
            xfer *x;
            snprintf(nm, sizeof nm, "U-frame:%s-%s%s-%s", put ? "upload" : "post", sized ? "N" : "unknown", patch ? "-patch" : "",
                     noexp ? "expect-off" : "expect-default");
            x = mk(nm, FACES[f], "/sink?want=262144");
            x->up_len = 262144;
            upload_opts(x, put, sized ? 262144 : -1);
            if (patch) SETOPT(x, CURLOPT_CUSTOMREQUEST, "PATCH");
            if (noexp) { x->hl = curl_slist_append(NULL, "Expect:"); SETOPT(x, CURLOPT_HTTPHEADER, x->hl); }
            drive(m, &x, 1, 30000);
            sink_line(x, 0);
            drop(x);
            curl_multi_cleanup(m);
          }
}

/* U-pause: 256 KiB by read callback, POST, which answers
   CURL_READFUNC_PAUSE while its producer is empty. The producer gains a
   16 KiB piece every 100 ms, from 100 ms; then, 100 ms after the last
   piece, the end. The loop calls CONT whenever it gains one and the read
   side is paused. Sized and unsized (chunked on HTTP/1.1). raw, tls, h2. */
static void u_pause(void) {
  int f, sized;
  for (f = 0; f < 3; f++)
    for (sized = 1; sized >= 0; sized--) {
      CURLM *m = new_multi();
      xfer *x = mk(sized ? "U-pause:length" : "U-pause:chunked", FACES[f], "/sink?want=262144");
      x->up_len = 262144;
      x->rmode = R_PRODUCER;
      x->print_reads = 1;
      upload_opts(x, 0, sized ? 262144 : -1);
      x->hl = curl_slist_append(NULL, "Expect:");
      SETOPT(x, CURLOPT_HTTPHEADER, x->hl);
      drive(m, &x, 1, 30000);
      sink_line(x, 0);
      server_log(x);
      drop(x);
      curl_multi_cleanup(m);
    }
}

/* U-rewind, raw: GET /close-after, then GAP ms on, on the same multi, a
   POST of 256 KiB by read callback to /sink, Expect: off, so head and body
   go at once. then=fin: the server closed the first connection 50 ms after
   its answer. then=kill: it kept it, reads the next request on it whole,
   then closes it with no answer, so every piece is read, and sent, before
   the failure, which the client meets reading the answer. a: no SEEKFUNCTION, fin; b: no SEEKFUNCTION, kill; c:
   SEEKFUNCTION answering CANTSEEK, fin and kill; d: SEEKFUNCTION
   restarting the producer, fin and kill. GAP 200 and 1500. */
/* ropts: what round 2's runs of the U-rewind shape add to the POST. */
typedef struct { int fresh, prereq, abort_at, evlog, fail_watch; int64_t post_len; } ropts;

/* u_rewind_gen: GET /close-after?then=THENQ, then GAP ms on, on the same
   multi, the streamed POST of 256 KiB to /sink; names PREFIX:LABEL:get and
   :post, both under the tag PREFIX.LABEL. Round 1's U-rewind is PREFIX
   U-rewind and O NULL. */
static void u_rewind_gen(const char *prefix, const char *label, const char *thenq, int smode, int gap, const ropts *o) {
  CURLM *m = new_multi();
  xfer *xs[2];
  char n1[120], n2[120], tag[160];
  double t0;
  int64_t plen = (o && o->post_len) ? o->post_len : 262144;
  snprintf(n1, sizeof n1, "%s:%s:get", prefix, label);
  snprintf(n2, sizeof n2, "%s:%s:post", prefix, label);
  xs[0] = mk(n1, "raw", "/close-after");
  xs[1] = mk(n2, "raw", "/sink?want=262144");
  /* both under one tag, so the server's count covers both */
  snprintf(tag, sizeof tag, "%s.%s", prefix, label);
  snprintf(xs[0]->tag, sizeof xs[0]->tag, "%s", tag);
  snprintf(xs[1]->tag, sizeof xs[1]->tag, "%s", tag);
  {
    char url[300];
    snprintf(url, sizeof url, "http://127.0.0.1:%d/close-after?then=%s&tag=%s", P_RAW, thenq, xs[0]->tag);
    SETOPT(xs[0], CURLOPT_URL, url);
    snprintf(url, sizeof url, "http://127.0.0.1:%d/sink?want=%lld&tag=%s", P_RAW, (long long)plen, xs[1]->tag);
    SETOPT(xs[1], CURLOPT_URL, url);
  }
  xs[1]->up_len = plen;
  upload_opts(xs[1], 0, plen);
  xs[1]->hl = curl_slist_append(NULL, "Expect:");
  SETOPT(xs[1], CURLOPT_HTTPHEADER, xs[1]->hl);
  xs[1]->smode = smode;
  if (smode != S_NONE) { SETOPT(xs[1], CURLOPT_SEEKFUNCTION, on_seek); SETOPT(xs[1], CURLOPT_SEEKDATA, xs[1]); }
  if (o && o->fresh) SETOPT(xs[1], CURLOPT_FRESH_CONNECT, 1L);
  if (o && o->prereq) {
    SETOPT(xs[1], CURLOPT_PREREQFUNCTION, on_prereq);
    SETOPT(xs[1], CURLOPT_PREREQDATA, xs[1]);
    xs[1]->prereq_abort_at = o->abort_at;
  }
  if (o && o->evlog) xs[1]->evlog = 1;
  if (o && o->fail_watch) xs[1]->fail_watch = 1;
  xs[1]->print_reads = plen <= 262144;
  xs[1]->dlog = 1;
  SETOPT(xs[1], CURLOPT_VERBOSE, 1L);
  SETOPT(xs[1], CURLOPT_DEBUGFUNCTION, on_debug);
  SETOPT(xs[1], CURLOPT_DEBUGDATA, xs[1]);
  t0 = abs_ms();
  xs[0]->add_at = t0;
  drive(m, xs, 1, 10000);
  xs[1]->add_at = abs_ms() + gap;
  drive(m, xs, 2, 20000);
  SAY(xs[1], "rewind case_t get_end=%.1f post_add=%.1f post_end=%.1f get_lport=%ld post_lport=%ld", xs[0]->t_end - t0, xs[1]->t_add - t0,
      xs[1]->t_end - t0, xs[0]->lport_seen, xs[1]->lport_seen);
  if (o)
    SAY(xs[1], "r2 prereq_calls=%d seeks=%d reads=%d fail_t=%.1f reads_after_fail=%d new_connection=%d", xs[1]->prereq_n, xs[1]->seeks, xs[1]->reads,
        xs[1]->fail_t, xs[1]->reads_after_fail, xs[0]->lport_seen != xs[1]->lport_seen);
  sink_line(xs[1], 0);
  server_log(xs[1]);
  drop(xs[0]);
  drop(xs[1]);
  curl_multi_cleanup(m);
}
static void u_rewind_one(const char *letter, const char *then, int smode, int gap) {
  char label[80];
  snprintf(label, sizeof label, "%s-%s-gap%d", letter, then, gap);
  u_rewind_gen("U-rewind", label, then, smode, gap, NULL);
}
static void u_rewind(void) {
  int g, gaps[2] = { 200, 1500 };
  for (g = 0; g < 2; g++) {
    u_rewind_one("a", "fin", S_NONE, gaps[g]);
    u_rewind_one("b", "kill", S_NONE, gaps[g]);
    u_rewind_one("c", "fin", S_CANT, gaps[g]);
    u_rewind_one("c", "kill", S_CANT, gaps[g]);
    u_rewind_one("d", "fin", S_OK, gaps[g]);
    u_rewind_one("d", "kill", S_OK, gaps[g]);
  }
}

/* H-head: every header call, escaped, and every write call, in one
   sequence; at a line that is exactly CRLF, RESPONSE_CODE and
   curl_easy_nextheader's CURLH_HEADER and CURLH_1XX for request -1.
   /body with delay=300; /early kind 100 and 103; /empty. raw, tls, h2. */
static void h_head(void) {
  const char *paths[4] = { "/body?n=4096&mode=length&chunk=4096&delay=300", "/early?kind=100", "/early?kind=103", "/empty" };
  const char *names[4] = { "H-head:body-delay300", "H-head:early100", "H-head:early103", "H-head:empty204" };
  int f, p;
  for (f = 0; f < 3; f++)
    for (p = 0; p < 4; p++) {
      CURLM *m = new_multi();
      xfer *x = mk(names[p], FACES[f], paths[p]);
      x->hlog = 1;
      if (p) x->capture = 1;
      drive(m, &x, 1, 15000);
      if (p == 0) summary(x);
      else SAY(x, "body bytes=%lld", (long long)x->total);
      drop(x);
      curl_multi_cleanup(m);
    }
}

/* P-noop: what curl_easy_pause(CONT) answers on a transfer not paused: a
   fresh handle never added; one running, twice; one just resumed from a
   real pause, a second CONT; one done but not yet removed; one removed.
   1 MiB written 16 KiB each 10 ms, so it runs about 650 ms. */
static void p_noop(void) {
  int f;
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    xfer *x = mk("P-noop", FACES[f], "/body?n=1048576&mode=length&chunk=16384&gap=10");
    CURL *fresh = curl_easy_init();
    CURLcode rc;
    int running, stage = 0, q, c0;
    double start;
    CURLMsg *msg;
    in_pause = 1;
    rc = curl_easy_pause(fresh, CURLPAUSE_CONT);
    in_pause = 0;
    SAY(x, "cont on=fresh-never-added rc=%d", (int)rc);
    curl_easy_cleanup(fresh);
    x->wpol = W_AT; x->at_bytes = 262144; x->hold = 100;
    x->keep_after_done = 1;
    add(m, x);
    start = abs_ms();
    while (!x->done && abs_ms() - start < 15000) {
      if (stage == 0 && x->calls >= 1 && !x->paused) {
        c0 = x->calls;
        in_pause = 1;
        rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
        in_pause = 0;
        SAY(x, "cont on=running-not-paused n=1 t=%.1f rc=%d calls_inside=%d", rel(x), (int)rc, x->calls - c0);
        c0 = x->calls;
        in_pause = 1;
        rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
        in_pause = 0;
        SAY(x, "cont on=running-not-paused n=2 t=%.1f rc=%d calls_inside=%d", rel(x), (int)rc, x->calls - c0);
        stage = 1;
      }
      if (stage == 1 && x->paused && abs_ms() >= x->resume_at) {
        c0 = x->calls;
        x->paused = 0;
        x->just_resumed = 1;
        x->resumes++;
        in_pause = 1;
        rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
        in_pause = 0;
        SAY(x, "cont on=paused (the real resume) t=%.1f rc=%d calls_inside=%d", rel(x), (int)rc, x->calls - c0);
        c0 = x->calls;
        in_pause = 1;
        rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
        in_pause = 0;
        SAY(x, "cont on=just-resumed (a second CONT) t=%.1f rc=%d calls_inside=%d", rel(x), (int)rc, x->calls - c0);
        stage = 2;
      }
      curl_multi_perform(m, &running);
      while ((msg = curl_multi_info_read(m, &q)))
        if (msg->msg == CURLMSG_DONE && msg->easy_handle == x->h) { x->done = 1; x->code = msg->data.result; x->t_end = abs_ms(); }
      if (!x->done) curl_multi_poll(m, NULL, 0, x->paused ? 10 : 1000, NULL);
    }
    if (x->done) {
      finish(m, x);
      c0 = x->calls;
      in_pause = 1;
      rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
      in_pause = 0;
      SAY(x, "cont on=done-not-removed rc=%d calls_inside=%d", (int)rc, x->calls - c0);
    } else SAY(x, "gave-up after 15000 ms");
    curl_multi_remove_handle(m, x->h);
    in_pause = 1;
    rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
    in_pause = 0;
    SAY(x, "cont on=removed rc=%d", (int)rc);
    summary(x);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* ---------------------------------------------------------------- round 2 */
/* Round 2 (2026-10-29): the coordinator's second list, each case named
   for the source reading's hypothesis it measures. */

static void sleep_ms(int ms) {
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (long)(ms % 1000) * 1000000L;
  nanosleep(&ts, NULL);
}

static void expect_off(xfer *x) {
  x->hl = curl_slist_append(x->hl, "Expect:");
  SETOPT(x, CURLOPT_HTTPHEADER, x->hl);
}

static void verbose(xfer *x) {
  x->dlog = 1;
  SETOPT(x, CURLOPT_VERBOSE, 1L);
  SETOPT(x, CURLOPT_DEBUGFUNCTION, on_debug);
  SETOPT(x, CURLOPT_DEBUGDATA, x);
}

static void prereq(xfer *x) {
  SETOPT(x, CURLOPT_PREREQFUNCTION, on_prereq);
  SETOPT(x, CURLOPT_PREREQDATA, x);
}

/* W-busy (W3, W4): 64 MiB as fast as the server can, paused at the first
   write and held 3 s, so bytes wait in the kernel. Over the hold, from the
   pausing perform to the resume: engine turns, curl_multi_poll returns,
   polls that returned in under 1 ms, and the process's CPU time. raw, tls,
   h2. */
static void w_busy(void) {
  int f;
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    xfer *x = mk("W-busy", FACES[f], "/body?n=67108864&mode=length&chunk=65536");
    double hold;
    x->wpol = W_FIRST; x->hold = 3000; x->busy = 1;
    drive(m, &x, 1, 60000);
    hold = x->wall_end - x->wall_start;
    SAY(x, "busy hold_ms=%.1f turns=%d polls=%d polls_under_1ms=%d cpu_ms=%.1f polls_per_s=%.1f", hold, x->turns_p, x->polls_p, x->short_polls_p,
        x->cpu_end - x->cpu_start, hold > 0 ? x->polls_p * 1000.0 / hold : 0.0);
    SAY(x, "unpause calls_inside=%d bytes_inside=%lld", x->calls_inpause, (long long)x->bytes_inpause);
    summary(x);
    server_log(x);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* W-lowspeed (W12): LOW_SPEED_LIMIT 1000, LOW_SPEED_TIME 1. paused-1000:
   1 MiB, paused at the first write for 3 s. control-stall: no pause; the
   server writes 1 KiB, waits 3 s, writes 1 KiB. raw, tls, h2. */
static void w_lowspeed(void) {
  int f, v;
  for (f = 0; f < 3; f++)
    for (v = 0; v < 2; v++) {
      CURLM *m = new_multi();
      xfer *x = v ? mk("W-lowspeed:control-stall", FACES[f], "/body?n=2048&mode=length&chunk=1024&gap=3000")
                  : mk("W-lowspeed:paused-1000", FACES[f], "/body?n=1048576&mode=length&chunk=16384");
      if (!v) { x->wpol = W_FIRST; x->hold = 3000; }
      SETOPT(x, CURLOPT_LOW_SPEED_LIMIT, 1000L);
      SETOPT(x, CURLOPT_LOW_SPEED_TIME, 1L);
      drive(m, &x, 1, 15000);
      SAY(x, "lowspeed end=%.1f total=%lld pauses=%d resumes=%d", x->t_end - x->t_add, (long long)x->total, x->pauses, x->resumes);
      server_log(x);
      drop(x);
      curl_multi_cleanup(m);
    }
}

/* W-sibling (W6): h2, PIPEWAIT, one connection. A: 80 MiB as fast as the
   server can, paused at its first write for 5 s. B: 800 KiB, 16 KiB each
   100 ms. A tick every 500 ms from the start: libcurl's live bytes, B's
   bytes. */
static xfer *g_ta, *g_tb;
static double g_t0;
static void sib_tick(void) {
  printf("case W-sibling h2 tick t=%.1f live=%lld A_paused=%d A_total=%lld B_total=%lld B_done=%d\n", abs_ms() - g_t0, (long long)live_now(),
         g_ta->paused, (long long)g_ta->total, (long long)g_tb->total, g_tb->done);
}
static void w_sibling(void) {
  CURLM *m = new_multi();
  xfer *xs[2];
  xs[0] = mk("W-sibling:A", "h2", "/body?n=83886080&mode=length&chunk=65536");
  xs[1] = mk("W-sibling:B", "h2", "/body?n=819200&mode=length&chunk=16384&gap=100");
  xs[0]->wpol = W_FIRST; xs[0]->hold = 5000;
  SETOPT(xs[0], CURLOPT_PIPEWAIT, 1L);
  SETOPT(xs[1], CURLOPT_PIPEWAIT, 1L);
  g_t0 = abs_ms();
  xs[0]->add_at = g_t0;
  xs[1]->add_at = g_t0;
  g_ta = xs[0]; g_tb = xs[1];
  g_tick = sib_tick; g_tick_every = 500; g_tick_next = g_t0 + 500;
  drive(m, xs, 2, 90000);
  g_tick = NULL; g_tick_every = 0;
  summary(xs[0]);
  summary(xs[1]);
  SAY(xs[0], "sibling case_t A_paused_at=%.1f A_resumed_at=%.1f A_end=%.1f B_end=%.1f A_code=%d B_code=%d A_lport=%ld B_lport=%ld A_inside_calls=%d A_inside_bytes=%lld",
      xs[0]->paused_at - g_t0, xs[0]->paused_at + xs[0]->hold - g_t0, xs[0]->t_end - g_t0, xs[1]->t_end - g_t0, (int)xs[0]->code, (int)xs[1]->code,
      xs[0]->lport_seen, xs[1]->lport_seen, xs[0]->calls_inpause, (long long)xs[0]->bytes_inpause);
  SAY(xs[0], "live in_callback_at_pause=%lld after_pausing_perform=%lld before_resume=%lld peak_during_pause=%lld",
      (long long)xs[0]->live_cb_pause, (long long)xs[0]->live_after_pause, (long long)xs[0]->live_before_resume, (long long)xs[0]->peak_in_pause);
  server_log(xs[0]);
  server_log(xs[1]);
  drop(xs[0]);
  drop(xs[1]);
  curl_multi_cleanup(m);
}

/* W-unpause-gap (W9): paused at the first write for 500 ms; from CONT's
   return to the next curl_multi_poll's return, and whether that poll
   waited (took 1 ms or more). big: 64 MiB, bytes waiting in the kernel;
   small: 1 KiB, the whole body in libcurl's hands. raw, tls, h2. */
static void w_unpause_gap(void) {
  const char *pq[2] = { "/body?n=67108864&mode=length&chunk=65536", "/body?n=1024&mode=length&chunk=1024" };
  const char *nm[2] = { "W-unpause-gap:big", "W-unpause-gap:small" };
  int v, f;
  for (v = 0; v < 2; v++)
    for (f = 0; f < 3; f++) {
      CURLM *m = new_multi();
      xfer *x = mk(nm[v], FACES[f], pq[v]);
      x->wpol = W_FIRST; x->hold = 500; x->gap_watch = 1; x->print_first = 1;
      drive(m, &x, 1, 60000);
      summary(x);
      drop(x);
      curl_multi_cleanup(m);
    }
}

/* W-replay-error (W15): 1 MiB, paused at the first write for 200 ms; the
   first call inside the unpause answers 0, the wrong count; any later
   call is taken. raw, tls, h2. */
static void w_replay_error(void) {
  int f;
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    xfer *x = mk("W-replay-error", FACES[f], "/body?n=1048576&mode=length&chunk=65536");
    x->wpol = W_ERR0; x->hold = 200; x->print_first = 3;
    drive(m, &x, 1, 30000);
    SAY(x, "replay-error calls_after_err=%d bytes_after_err=%lld total=%lld", x->calls_after_err, (long long)x->bytes_after_err, (long long)x->total);
    summary(x);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* R-first-read (R5): POST, CL 1000, Expect off. The first read's time on
   the clock Node's hrtime reads, against the server's at the head's
   arrival (one clock on Linux), and the debug events in order. raw, tls,
   h2. */
static void r_first_read(void) {
  int f;
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    xfer *x = mk("R-first-read", FACES[f], "/sink?want=1000&mono=1");
    char txt[16384], *p;
    x->up_len = 1000;
    upload_opts(x, 0, 1000);
    expect_off(x);
    x->evlog = 1;
    verbose(x);
    drive(m, &x, 1, 15000);
    sink_line(x, 1);
    txt[0] = 0;
    server_log_text(x, txt, sizeof txt);
    p = strstr(txt, " mono=");
    if (p) SAY(x, "first-read t=%.1f read_mono_minus_server_head_mono_ms=%.3f (one clock on Linux; on macOS the probe reads CLOCK_UPTIME_RAW)", x->first_read_t,
               (double)(x->first_read_mono - atoll(p + 6)) / 1e6);
    else SAY(x, "first-read t=%.1f server head mono: none (reads=%d)", x->first_read_t, x->reads);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* R-answer (R10, R23): POST, CL 1000000, Expect off; the read callback
   pauses and its producer never resumes. The server answers as the head
   arrives: 413 then FIN; 413 keep-alive; 200 then FIN; h2 413 and 200.
   Whether CURLMSG_DONE comes within 3 s without an unpause. */
static void r_answer(void) {
  const char *fc[5] = { "raw", "raw", "raw", "h2", "h2" };
  const char *nm[5] = { "R-answer:413-close", "R-answer:413-keepalive", "R-answer:200-close", "R-answer:413", "R-answer:200" };
  const char *pq[5] = { "/answer?status=413&close=1", "/answer?status=413", "/answer?status=200&close=1", "/answer?status=413", "/answer?status=200" };
  int i;
  for (i = 0; i < 5; i++) {
    CURLM *m = new_multi();
    xfer *x = mk(nm[i], fc[i], pq[i]);
    long st = 0;
    x->rmode = R_SCHED;
    x->up_len = 1000000;
    upload_opts(x, 0, 1000000);
    expect_off(x);
    verbose(x);
    drive(m, &x, 1, 3000);
    curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
    SAY(x, "answer done_within_3s=%d code=%d t=%.1f response_code_seen=%ld reads=%d", x->done, x->done ? (int)x->code : -1,
        x->done ? x->t_end - x->t_add : -1.0, st, x->reads);
    curl_easy_cleanup(x->h);
    x->h = NULL;
    curl_multi_cleanup(m);
    sleep_ms(100);
    server_log(x);
    drop(x);
  }
}

/* R-short (R12): POST, CL 1000; the read callback gives 500 bytes, then 0.
   TIMEOUT_MS 3000. raw, h2. */
static void r_short(void) {
  const char *fc[2] = { "raw", "h2" };
  int i;
  for (i = 0; i < 2; i++) {
    CURLM *m = new_multi();
    xfer *x = mk("R-short", fc[i], "/sink?want=1000");
    x->rmode = R_SHORT;
    x->short_len = 500;
    x->up_len = 1000;
    upload_opts(x, 0, 1000);
    expect_off(x);
    SETOPT(x, CURLOPT_TIMEOUT_MS, 3000L);
    verbose(x);
    drive(m, &x, 1, 10000);
    sink_line(x, 1);
    curl_easy_cleanup(x->h);
    x->h = NULL;
    curl_multi_cleanup(m);
    sleep_ms(100);
    server_log(x);
    drop(x);
  }
}

/* R-overrun (R14): POST, CL 1000; the read callback fills 1500 bytes when
   offered that many, the room when offered less, then 0. raw, h2. */
static void r_overrun(void) {
  const char *fc[2] = { "raw", "h2" };
  int i;
  for (i = 0; i < 2; i++) {
    CURLM *m = new_multi();
    xfer *x = mk("R-overrun", fc[i], "/sink?want=1000");
    x->rmode = R_OVERRUN;
    x->up_len = 1000;
    upload_opts(x, 0, 1000);
    expect_off(x);
    SETOPT(x, CURLOPT_TIMEOUT_MS, 3000L);
    verbose(x);
    drive(m, &x, 1, 10000);
    sink_line(x, 1);
    curl_easy_cleanup(x->h);
    x->h = NULL;
    curl_multi_cleanup(m);
    sleep_ms(100);
    server_log(x);
    drop(x);
  }
}

/* R-lowspeed (R15): POST, CL 32768, Expect off; LOW_SPEED_LIMIT 1,
   LOW_SPEED_TIME 2. The producer has 16 KiB at once, then nothing for
   5 s, then the other 16 KiB. raw. */
static void r_lowspeed(void) {
  CURLM *m = new_multi();
  xfer *x = mk("R-lowspeed", "raw", "/sink?want=32768");
  x->rmode = R_SCHED;
  x->sched_n = 2;
  x->sched_at[0] = 0; x->sched_bytes[0] = 16384;
  x->sched_at[1] = 5000; x->sched_bytes[1] = 16384;
  x->up_len = 32768;
  upload_opts(x, 0, 32768);
  expect_off(x);
  SETOPT(x, CURLOPT_LOW_SPEED_LIMIT, 1L);
  SETOPT(x, CURLOPT_LOW_SPEED_TIME, 2L);
  drive(m, &x, 1, 15000);
  sink_line(x, 1);
  curl_easy_cleanup(x->h);
  x->h = NULL;
  curl_multi_cleanup(m);
  sleep_ms(100);
  server_log(x);
  drop(x);
}

/* R-reset-mid (R17): GET /close-after?then=reset, the connection pooled
   and healthy; 100 ms on, the streamed POST of 256 KiB on it, Expect off;
   the server reads its head and at least 32 KiB of body, then resets.
   noseek: no SEEKFUNCTION; seekok: one that restarts the producer. With a
   PREREQFUNCTION; reads after libcurl first reports a failure. */
static void r_reset_mid(void) {
  ropts o;
  memset(&o, 0, sizeof o);
  o.prereq = 1; o.evlog = 1; o.fail_watch = 1;
  u_rewind_gen("R-reset-mid", "noseek", "reset&at=32768", S_NONE, 100, &o);
  u_rewind_gen("R-reset-mid", "seekok", "reset&at=32768", S_OK, 100, &o);
}

/* R-reset-split, not in run.sh's default list: R17 with its race taken
   out. Added after round 2's kept runs, where R-reset-mid's reset met
   libcurl sending on some runs (55) and reading on others (65 or a retry).
   send-side: the POST is 8 MiB, so the reset at 32 KiB comes while
   libcurl still sends. recv-side: 256 KiB, reset once the server has read
   it whole, so libcurl has sent everything and meets it reading. noseek
   and seekok each. Run by CASES=R-reset-split. */
static void r_reset_split(void) {
  ropts o;
  memset(&o, 0, sizeof o);
  o.prereq = 1; o.evlog = 0; o.fail_watch = 1;
  o.post_len = 8388608;
  u_rewind_gen("R-reset-split", "send-side-noseek", "reset&at=32768", S_NONE, 100, &o);
  u_rewind_gen("R-reset-split", "send-side-seekok", "reset&at=32768", S_OK, 100, &o);
  o.post_len = 262144;
  u_rewind_gen("R-reset-split", "recv-side-noseek", "reset&at=262144", S_NONE, 100, &o);
  u_rewind_gen("R-reset-split", "recv-side-seekok", "reset&at=262144", S_OK, 100, &o);
}

/* R-prereq (R18): PREREQFUNCTION calls, in order with seeks and reads, in
   U-rewind's kill variants b, c, d at gap 200 (R17's are in R-reset-mid);
   then d with a PREREQFUNCTION that answers ABORT on its second call; then
   R8: POST of size -1 to /expect417, which answers 417 to its Expect,
   keep-alive, and with close=1. */
static void r_prereq(void) {
  ropts o;
  CURLM *m;
  xfer *x;
  int k;
  memset(&o, 0, sizeof o);
  o.prereq = 1; o.evlog = 1;
  u_rewind_gen("R-prereq", "kill-b-gap200", "kill", S_NONE, 200, &o);
  u_rewind_gen("R-prereq", "kill-c-gap200", "kill", S_CANT, 200, &o);
  u_rewind_gen("R-prereq", "kill-d-gap200", "kill", S_OK, 200, &o);
  o.abort_at = 2;
  u_rewind_gen("R-prereq", "kill-d-abort2", "kill", S_OK, 200, &o);
  for (k = 0; k < 2; k++) {
    m = new_multi();
    x = mk(k ? "R-prereq:expect417-close" : "R-prereq:expect417", "raw", k ? "/expect417?want=65536&close=1" : "/expect417?want=65536");
    x->up_len = 65536;
    upload_opts(x, 0, -1);
    x->smode = S_OK;
    SETOPT(x, CURLOPT_SEEKFUNCTION, on_seek);
    SETOPT(x, CURLOPT_SEEKDATA, x);
    prereq(x);
    x->evlog = 1;
    verbose(x);
    drive(m, &x, 1, 15000);
    SAY(x, "r2 prereq_calls=%d seeks=%d reads=%d", x->prereq_n, x->seeks, x->reads);
    sink_line(x, 0);
    server_log(x);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* R-refused (R19): h2, streamed POST of 256 KiB, Expect off; the server
   resets the tag's first stream with REFUSED_STREAM after 32 KiB of DATA
   and answers later ones. noseek, and seekok. */
static void r_refused(void) {
  int k;
  for (k = 0; k < 2; k++) {
    CURLM *m = new_multi();
    xfer *x = mk(k ? "R-refused:seekok" : "R-refused:noseek", "h2", "/refuse?want=262144");
    x->up_len = 262144;
    upload_opts(x, 0, 262144);
    expect_off(x);
    if (k) { x->smode = S_OK; SETOPT(x, CURLOPT_SEEKFUNCTION, on_seek); SETOPT(x, CURLOPT_SEEKDATA, x); }
    prereq(x);
    verbose(x);
    drive(m, &x, 1, 20000);
    SAY(x, "r2 prereq_calls=%d seeks=%d reads=%d", x->prereq_n, x->seeks, x->reads);
    sink_line(x, 0);
    server_log(x);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* R-empty (R22): POST of size 0 and PUT of size 0, by read callback: its
   calls, and the framing the server saw. raw, h2. */
static void r_empty(void) {
  const char *fc[2] = { "raw", "h2" };
  int i, put;
  for (i = 0; i < 2; i++)
    for (put = 0; put < 2; put++) {
      CURLM *m = new_multi();
      xfer *x = mk(put ? "R-empty:put0" : "R-empty:post0", fc[i], "/sink?want=0");
      x->up_len = 0;
      upload_opts(x, put, 0);
      x->evlog = 1;
      drive(m, &x, 1, 10000);
      sink_line(x, 0);
      drop(x);
      curl_multi_cleanup(m);
    }
}

/* U-rewind-fresh: U-rewind's fin and kill variants, gaps 200 and 1500,
   with FRESH_CONNECT 1 on the streamed POST. */
static void u_rewind_fresh(void) {
  ropts o;
  int g, gaps[2] = { 200, 1500 };
  char label[80];
  memset(&o, 0, sizeof o);
  o.fresh = 1;
  for (g = 0; g < 2; g++) {
    snprintf(label, sizeof label, "a-fin-gap%d", gaps[g]); u_rewind_gen("U-rewind-fresh", label, "fin", S_NONE, gaps[g], &o);
    snprintf(label, sizeof label, "b-kill-gap%d", gaps[g]); u_rewind_gen("U-rewind-fresh", label, "kill", S_NONE, gaps[g], &o);
    snprintf(label, sizeof label, "c-fin-gap%d", gaps[g]); u_rewind_gen("U-rewind-fresh", label, "fin", S_CANT, gaps[g], &o);
    snprintf(label, sizeof label, "c-kill-gap%d", gaps[g]); u_rewind_gen("U-rewind-fresh", label, "kill", S_CANT, gaps[g], &o);
    snprintf(label, sizeof label, "d-fin-gap%d", gaps[g]); u_rewind_gen("U-rewind-fresh", label, "fin", S_OK, gaps[g], &o);
    snprintf(label, sizeof label, "d-kill-gap%d", gaps[g]); u_rewind_gen("U-rewind-fresh", label, "kill", S_OK, gaps[g], &o);
  }
}

/* H-cl (H5): Content-Length: 1234; CONTENT_LENGTH_DOWNLOAD_T read inside
   the header callback for each head's empty line. raw, tls, h2. */
static void h_cl(void) {
  int f;
  for (f = 0; f < 3; f++) {
    CURLM *m = new_multi();
    xfer *x = mk("H-cl", FACES[f], "/body?n=1234&mode=length&chunk=1234");
    x->hcl = 1;
    drive(m, &x, 1, 10000);
    summary(x);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* W-h2-gzip (W17): ACCEPT_ENCODING "" against 1 MiB gzip-encoded, no
   pause. h2, and raw beside it. */
static void w_h2_gzip(void) {
  const char *fc[2] = { "h2", "raw" };
  int i;
  for (i = 0; i < 2; i++) {
    CURLM *m = new_multi();
    xfer *x = mk("W-h2-gzip", fc[i], "/body?n=1048576&mode=length&chunk=16384&gzip=1");
    SETOPT(x, CURLOPT_ACCEPT_ENCODING, "");
    drive(m, &x, 1, 10000);
    summary(x);
    drop(x);
    curl_multi_cleanup(m);
  }
}

/* W-h2-error (W18): two h2 streams, PIPEWAIT, one connection. A, 8 MiB:
   its first write answers CURL_WRITEFUNC_ERROR. B, 1 MiB, 16 KiB each
   20 ms. B's result. */
static void w_h2_error(void) {
  CURLM *m = new_multi();
  xfer *xs[2];
  double t0;
  xs[0] = mk("W-h2-error:A", "h2", "/body?n=8388608&mode=length&chunk=65536");
  xs[1] = mk("W-h2-error:B", "h2", "/body?n=1048576&mode=length&chunk=16384&gap=20");
  xs[0]->wpol = W_WFERR;
  SETOPT(xs[0], CURLOPT_PIPEWAIT, 1L);
  SETOPT(xs[1], CURLOPT_PIPEWAIT, 1L);
  t0 = abs_ms();
  xs[0]->add_at = t0;
  xs[1]->add_at = t0;
  drive(m, xs, 2, 30000);
  summary(xs[0]);
  summary(xs[1]);
  SAY(xs[1], "h2-error case_t A_end=%.1f B_end=%.1f A_code=%d B_code=%d A_lport=%ld B_lport=%ld B_total=%lld", xs[0]->t_end - t0, xs[1]->t_end - t0,
      (int)xs[0]->code, (int)xs[1]->code, xs[0]->lport_seen, xs[1]->lport_seen, (long long)xs[1]->total);
  server_log(xs[0]);
  server_log(xs[1]);
  server_conns("W-h2-error", "W-h2-error.");
  drop(xs[0]);
  drop(xs[1]);
  curl_multi_cleanup(m);
}

int main(int argc, char **argv) {
  CURLcode g;
  setvbuf(stdout, NULL, _IOLBF, 0);
  g = curl_global_init_mem(CURL_GLOBAL_ALL, c_malloc, c_free, c_realloc, c_strdup, c_calloc);
  if (g) { printf("curl_global_init_mem rc=%d\n", (int)g); return 1; }
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
    printf("version headers=%s runtime=%s ssl=%s libz=%s nghttp2=%s http2=%d libz_feature=%d live_after_init=%lld\n", LIBCURL_VERSION, v->version,
           v->ssl_version ? v->ssl_version : "-", v->libz_version ? v->libz_version : "-",
           v->nghttp2_version ? v->nghttp2_version : "-", !!(v->features & CURL_VERSION_HTTP2), !!(v->features & CURL_VERSION_LIBZ),
           (long long)live_now());
    curl_global_cleanup();
    return 0;
  }
  if (argc != 6) { fprintf(stderr, "usage: probe CASE RAW TLS H2 CA | probe --version\n"); return 2; }
  P_RAW = atoi(argv[2]);
  P_TLS = atoi(argv[3]);
  P_H2 = atoi(argv[4]);
  CA = argv[5];
  if (!strcmp(argv[1], "D-first")) d_first();
  else if (!strcmp(argv[1], "D-every")) d_every();
  else if (!strcmp(argv[1], "D-hold")) d_hold();
  else if (!strcmp(argv[1], "D-hold-mux")) d_hold_mux();
  else if (!strcmp(argv[1], "D-hold-control")) d_hold_control();
  else if (!strcmp(argv[1], "D-clock")) d_clock();
  else if (!strcmp(argv[1], "D-chunk")) d_chunk();
  else if (!strcmp(argv[1], "D-cancel")) d_cancel();
  else if (!strcmp(argv[1], "U-frame")) u_frame();
  else if (!strcmp(argv[1], "U-pause")) u_pause();
  else if (!strcmp(argv[1], "U-rewind")) u_rewind();
  else if (!strcmp(argv[1], "H-head")) h_head();
  else if (!strcmp(argv[1], "P-noop")) p_noop();
  else if (!strcmp(argv[1], "W-busy")) w_busy();
  else if (!strcmp(argv[1], "W-lowspeed")) w_lowspeed();
  else if (!strcmp(argv[1], "W-sibling")) w_sibling();
  else if (!strcmp(argv[1], "W-unpause-gap")) w_unpause_gap();
  else if (!strcmp(argv[1], "W-replay-error")) w_replay_error();
  else if (!strcmp(argv[1], "R-first-read")) r_first_read();
  else if (!strcmp(argv[1], "R-answer")) r_answer();
  else if (!strcmp(argv[1], "R-short")) r_short();
  else if (!strcmp(argv[1], "R-overrun")) r_overrun();
  else if (!strcmp(argv[1], "R-lowspeed")) r_lowspeed();
  else if (!strcmp(argv[1], "R-reset-mid")) r_reset_mid();
  else if (!strcmp(argv[1], "R-reset-split")) r_reset_split();
  else if (!strcmp(argv[1], "R-prereq")) r_prereq();
  else if (!strcmp(argv[1], "R-refused")) r_refused();
  else if (!strcmp(argv[1], "R-empty")) r_empty();
  else if (!strcmp(argv[1], "U-rewind-fresh")) u_rewind_fresh();
  else if (!strcmp(argv[1], "H-cl")) h_cl();
  else if (!strcmp(argv[1], "W-h2-gzip")) w_h2_gzip();
  else if (!strcmp(argv[1], "W-h2-error")) w_h2_error();
  else { fprintf(stderr, "probe: no case %s\n", argv[1]); return 2; }
  printf("case %s all done live_before_global_cleanup=%lld\n", argv[1], (long long)live_now());
  curl_global_cleanup();
  printf("case %s live_after_global_cleanup=%lld\n", argv[1], (long long)live_now());
  return 0;
}
