/* M8's header-caps probe (2026-11-06; the M8 plan's measurements,
   ADR-0038 decision 2: a cap of chez-curl's own on response headers).

     probe --version
     probe CASE CTL H1 H1TLS H2 PROXY CA

   CTL, H1, H1TLS, H2 and PROXY are server.mjs's ports; CA is the run's
   ca.pem. CASE is one of:

     count   case 1: responses of 1,000, 4,999, 5,000, 5,001, 10,000 and
             50,000 header lines of 16 bytes, over h1 (http), h1tls (https,
             http/1.1) and h2 (https, h2); over h2 again with every line the
             same pair, which HPACK indexes.
     bytes   case 2: heads of 307,199, 307,200, 307,201 and 1,048,576 bytes in
             all, in lines of 256 bytes, over the three faces, and over h2
             again with the lines the same pair; one line of 102,398 to
             102,401 bytes, its value a's (5 bits each in HPACK's Huffman
             code), and over h2 one of 102,400 whose value is X's (8 bits,
             so sent as it is); over h2, heads of 131,071 to 131,073 bytes
             (7.85.0's DYN_H2_HEADERS is 128 KiB).
     toward  case 3: many lines in 1xx heads (100 and 103), in trailers, in
             both responses of a Digest 401 round, of a 417 and its resend
             (h1 alone), of a redirect followed, and in a proxy's CONNECT
             answer, the target over h1tls and h2.
     walk    case 5: N = WALK_NS (100 1000 2000 5000) header lines over h1,
             names distinct and all the same, WALK_ROUNDS (7) rounds, the
             order turned each round; each transfer's curl_easy_nextheader
             walk timed twice, wall and the thread's CPU.

   Every cell of count, bytes and toward runs in each mode of PROBE_MODES
   ("obs none cap"):
     obs   a HEADERFUNCTION that counts every line it is handed and answers
           its length, as chez-curl's streamed path sets one; after the end,
           the walk, whatever the code.
     none  no HEADERFUNCTION, as chez-curl's buffered path; the walk after a
           code of 0, as finish-transfer walks.
     cap   case 4: the counting HEADERFUNCTION, refusing, by answering 0,
           the line that takes the header lines past CAP_LINES (1000) or the
           bytes past CAP_BYTES (102400); the walk after a code of 0.
   A line is a status line when it starts "HTTP/" at a head's start (the
   first line, or one after an empty line), an empty line when it is "\r\n"
   or "\n", and else a header line; header lines after a head's empty line
   that no status line opens are a trailer section, "T". The bytes count
   every line handed, status and empty lines too.

   Every transfer goes through the multi interface, one transfer on a fresh
   multi handle per cell, in chez-curl's engine turn: curl_multi_perform,
   curl_multi_info_read, curl_multi_poll for at most 1000 ms; the probe gives
   up after 60 s. The multi handle gets CURLMOPT_QUICK_EXIT 1 where libcurl
   knows it, and CURLMOPT_PIPELINING 0 on 8.7.0 and 8.7.1 (ADR-0030,
   amended). Every transfer gets the engine's options, in transfer.sls's
   order: the pins, PROTOCOLS_STR and REDIR_PROTOCOLS_STR "http,https",
   NOSIGNAL 1, MAXREDIRS 30, QUICK_EXIT 1 where libcurl knows it;
   ERRORBUFFER; the URL (CURLOPT_URL, where chez-curl hands a CURLU);
   WRITEFUNCTION; HEADERFUNCTION as the mode says; for a POST, POSTFIELDSIZE
   and COPYPOSTFIELDS, and HTTPHEADER holding the caller's Expect and
   chez-curl's blank Content-Type; PROXY "" or the proxy's URL; HTTPAUTH
   DIGEST, USERNAME and PASSWORD for the Digest round; on https,
   SSL_VERIFYPEER 1, SSL_VERIFYHOST 2, CAINFO at CA and CAPATH cleared;
   FOLLOWLOCATION 1 for a redirect, as chez-curl's private follow sets it.
   HTTP_VERSION is left unset: libcurl's own, 2TLS. A setopt that answers
   other than CURLE_OK prints a line, but CAPATH's clear answering
   CURLE_NOT_BUILT_IN and QUICK_EXIT's answering CURLE_UNKNOWN_OPTION.

   libcurl allocates through curl_global_init_mem's counting allocators:
   live_kb is what it holds through them as the transfer ends, before the
   easy handle's cleanup.

   Output: one "cell" line per transfer:
     cell CASE LABEL face=F mode=M code=N err="..." status=S ver=V
          t_ms=add-to-done cpu_ms=the process's CPU across it
          calls= hdr_lines= bytes= heads=[LABEL:HEADER_LINES:BYTES,...]
          refused=none|lines@K|bytes@B header_size= stored= walk_ms=
          walk_cpu_ms= [stored_all= stored_r0=] live_kb=
   then "srv" lines: server.mjs's events for the cell, fetched on the
   control port over a plain socket after the transfer. The walk case
   prints one "walk" line per transfer. */
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

/* By number, so one source builds against every lane's headers. */
#define OPT_QUICK_EXIT ((CURLoption)(CURLOPTTYPE_LONG + 322))   /* 7.87.0 */
#define MOPT_QUICK_EXIT ((CURLMoption)(CURLOPTTYPE_LONG + 21))  /* 8.18.0 */

static int P_CTL, P_H1, P_H1TLS, P_H2, P_PROXY;
static const char *CA;
static unsigned VNUM;
static long CAP_LINES = 1000, CAP_BYTES = 102400;
static long g_seq;

/* ---------------------------------------------------------------- clocks */
static double mono_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}
static double cpu_ms(clockid_t c) {
  struct timespec ts;
  clock_gettime(c, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

/* ---------------------------------------------------------------- memory */
#define HDR 16
static int64_t live;
static void track(int64_t d) { __atomic_add_fetch(&live, d, __ATOMIC_SEQ_CST); }
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

/* ---------------------------------------------------------------- output */
static void esc(const char *d, size_t n, char *out, size_t cap) {
  size_t o = 0, i;
  for (i = 0; i < n && o + 6 < cap; i++) {
    unsigned char c = (unsigned char)d[i];
    if (c == '\r') { out[o++] = '\\'; out[o++] = 'r'; }
    else if (c == '\n') { out[o++] = '\\'; out[o++] = 'n'; }
    else if (c == '\\' || c == '"' || c < 0x20 || c > 0x7e) o += (size_t)snprintf(out + o, cap - o, "\\x%02x", c);
    else out[o++] = (char)c;
  }
  out[o] = 0;
}

/* ---------------------------------------------------------------- control */
/* ctl: GET PATH on the control port over a plain socket; the body into OUT,
   NUL-terminated. Answers its length, or -1. */
static long ctl(const char *path, char *out, size_t cap) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in sa;
  struct timeval tv = { 8, 0 };
  char req[4096], *buf, *body;
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
/* srv_lines: the server's events after AFTER, but accept, tls, req, close
   and a client's GOAWAY of code 0, each as a "srv" line. */
static void srv_lines(long after) {
  char p[64], *line, *nl;
  snprintf(p, sizeof p, "/events?after=%ld", after);
  if (ctl(p, g_events, sizeof g_events) < 0) { printf("srv the events fetch failed\n"); return; }
  for (line = g_events; *line; line = nl + 1) {
    nl = strchr(line, '\n');
    if (nl) *nl = 0;
    if (!strstr(line, " accept ") && !strstr(line, " tls ") && !strstr(line, " req ") && !strstr(line, " close ") &&
        !(strstr(line, " goaway ") && strstr(line, " code=0 ")))
      printf("srv %s\n", line);
    if (!nl) break;
    *nl = '\n';
  }
}

/* ---------------------------------------------------------------- transfers */
enum { M_NONE, M_OBS, M_CAP };
static const char *MODE_NAME[] = { "none", "obs", "cap" };
enum { F_DIGEST = 1, F_EXPECT = 2, F_FOLLOW = 4, F_PROXY = 8, F_WALKALL = 16 };

#define MAXHEADS 64
typedef struct head { char label[8]; long lines, bytes; } head;
typedef struct xfer {
  CURL *h;
  int mode;
  char errbuf[CURL_ERROR_SIZE + 1];
  long calls, hdr_lines, bytes;
  int at_start, nheads, refused;
  head heads[MAXHEADS];
  char refused_txt[64];
} xfer;

static size_t on_write(char *d, size_t sz, size_t nm, void *u) { (void)d; (void)u; return sz * nm; }

static size_t on_header(char *d, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t n = sz * nm;
  int blank = (n == 2 && d[0] == '\r' && d[1] == '\n') || (n == 1 && d[0] == '\n');
  head *cur;
  x->calls++;
  if (!blank && (x->at_start || x->nheads == 0)) {
    if (n >= 5 && !memcmp(d, "HTTP/", 5)) {
      const char *sp = memchr(d, ' ', n);
      if (x->nheads < MAXHEADS) x->nheads++;
      cur = &x->heads[x->nheads - 1];
      memset(cur, 0, sizeof *cur);
      if (sp && sp + 4 <= d + n) memcpy(cur->label, sp + 1, 3); else strcpy(cur->label, "?");
      cur->bytes += (long)n;
      x->bytes += (long)n;
      x->at_start = 0;
      goto judge;
    }
    if (x->at_start && x->nheads > 0) {
      if (x->nheads < MAXHEADS) x->nheads++;
      cur = &x->heads[x->nheads - 1];
      memset(cur, 0, sizeof *cur);
      strcpy(cur->label, "T");
    }
  }
  if (x->nheads == 0) { x->nheads = 1; memset(&x->heads[0], 0, sizeof x->heads[0]); strcpy(x->heads[0].label, "-"); }
  cur = &x->heads[x->nheads - 1];
  cur->bytes += (long)n;
  x->bytes += (long)n;
  if (!blank) { cur->lines++; x->hdr_lines++; }
  x->at_start = blank;
judge:
  if (x->mode == M_CAP && !x->refused) {
    if (x->hdr_lines > CAP_LINES) { x->refused = 1; snprintf(x->refused_txt, sizeof x->refused_txt, "lines@%ld", x->hdr_lines); return 0; }
    if (x->bytes > CAP_BYTES) { x->refused = 1; snprintf(x->refused_txt, sizeof x->refused_txt, "bytes@%ld", x->bytes); return 0; }
  }
  return n;
}

#define SETOPT(h, opt, val) do { CURLcode rc_ = curl_easy_setopt((h), opt, val); \
    if (rc_ != CURLE_OK && !(opt == CURLOPT_CAPATH && rc_ == CURLE_NOT_BUILT_IN) && !(opt == OPT_QUICK_EXIT && rc_ == CURLE_UNKNOWN_OPTION)) \
      printf("setopt %s rc=%d\n", #opt, (int)rc_); } while (0)

static int port_of(const char *f) {
  return !strcmp(f, "h1") ? P_H1 : !strcmp(f, "h1tls") ? P_H1TLS : P_H2;
}
static int is_tls(const char *f) { return strcmp(f, "h1") != 0; }

static CURLM *new_multi(void) {
  CURLM *m = curl_multi_init();
  CURLMcode rc = curl_multi_setopt(m, MOPT_QUICK_EXIT, 1L);
  if (rc != CURLM_OK && rc != CURLM_UNKNOWN_OPTION) printf("multi quick_exit rc=%d\n", (int)rc);
  if (VNUM == 0x080700 || VNUM == 0x080701) {
    rc = curl_multi_setopt(m, CURLMOPT_PIPELINING, (long)CURLPIPE_NOTHING);
    if (rc != CURLM_OK) printf("multi pipelining rc=%d\n", (int)rc);
  }
  return m;
}

/* walk: one curl_easy_nextheader walk for ORIGIN and REQUEST; its count,
   and its wall and thread CPU ms in WALL and CPU. */
static long walk(CURL *h, unsigned origin, int request, double *wall, double *cpu) {
  struct curl_header *prev = NULL, *hh;
  long n = 0;
  double t0 = mono_ms(), c0 = cpu_ms(CLOCK_THREAD_CPUTIME_ID);
  while ((hh = curl_easy_nextheader(h, origin, request, prev))) { n++; prev = hh; }
  if (wall) *wall = mono_ms() - t0;
  if (cpu) *cpu = cpu_ms(CLOCK_THREAD_CPUTIME_ID) - c0;
  return n;
}

typedef struct result {
  CURLcode code;
  long status, ver, header_size, stored;
  double t_ms, cpu_ms, walk_ms, walk_cpu_ms;
  int walked;
} result;

/* run: one transfer to FACE's PATHQ in MODE, with FLAGS; TAG goes in the
   query. X is the callback state; WALKS walks after the end as the mode
   says (0: none). The easy handle is left for the caller, in X->h. */
static void run(xfer *x, const char *face, const char *pathq, const char *tag, int mode, unsigned flags, result *r) {
  CURLM *m = new_multi();
  char url[4096];
  struct curl_slist *hl = NULL;
  int running, q, done = 0;
  CURLMsg *msg;
  double t0, c0;
  memset(x, 0, sizeof *x);
  memset(r, 0, sizeof *r);
  x->mode = mode;
  x->at_start = 1;
  r->stored = -1;
  x->h = curl_easy_init();
  snprintf(url, sizeof url, "%s://127.0.0.1:%d%s%stag=%s", is_tls(face) ? "https" : "http", port_of(face), pathq,
           strchr(pathq, '?') ? "&" : "?", tag);
  SETOPT(x->h, CURLOPT_PROTOCOLS_STR, "http,https");
  SETOPT(x->h, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
  SETOPT(x->h, CURLOPT_NOSIGNAL, 1L);
  SETOPT(x->h, CURLOPT_MAXREDIRS, 30L);
  SETOPT(x->h, OPT_QUICK_EXIT, 1L);
  SETOPT(x->h, CURLOPT_ERRORBUFFER, x->errbuf);
  SETOPT(x->h, CURLOPT_URL, url);
  SETOPT(x->h, CURLOPT_WRITEFUNCTION, on_write);
  SETOPT(x->h, CURLOPT_WRITEDATA, x);
  if (mode != M_NONE) {
    SETOPT(x->h, CURLOPT_HEADERFUNCTION, on_header);
    SETOPT(x->h, CURLOPT_HEADERDATA, x);
  }
  if (flags & F_EXPECT) {
    SETOPT(x->h, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)10);
    SETOPT(x->h, CURLOPT_COPYPOSTFIELDS, "0123456789");
    hl = curl_slist_append(hl, "Expect: 100-continue");
    hl = curl_slist_append(hl, "Content-Type:");
    SETOPT(x->h, CURLOPT_HTTPHEADER, hl);
  }
  if (flags & F_PROXY) {
    char p[64];
    snprintf(p, sizeof p, "http://127.0.0.1:%d", P_PROXY);
    SETOPT(x->h, CURLOPT_PROXY, p);
  } else SETOPT(x->h, CURLOPT_PROXY, "");
  if (flags & F_DIGEST) {
    SETOPT(x->h, CURLOPT_HTTPAUTH, (long)CURLAUTH_DIGEST);
    SETOPT(x->h, CURLOPT_USERNAME, "alice");
    SETOPT(x->h, CURLOPT_PASSWORD, "secret");
  }
  if (is_tls(face)) {
    SETOPT(x->h, CURLOPT_SSL_VERIFYPEER, 1L);
    SETOPT(x->h, CURLOPT_SSL_VERIFYHOST, 2L);
    SETOPT(x->h, CURLOPT_CAINFO, CA);
    SETOPT(x->h, CURLOPT_CAPATH, (char *)NULL);
  }
  if (flags & F_FOLLOW) SETOPT(x->h, CURLOPT_FOLLOWLOCATION, 1L);
  t0 = mono_ms();
  c0 = cpu_ms(CLOCK_PROCESS_CPUTIME_ID);
  curl_multi_add_handle(m, x->h);
  while (!done) {
    curl_multi_perform(m, &running);
    while ((msg = curl_multi_info_read(m, &q))) {
      if (msg->msg == CURLMSG_DONE && msg->easy_handle == x->h) { done = 1; r->code = msg->data.result; }
    }
    if (done) break;
    if (mono_ms() - t0 > 60000) { printf("gave-up after 60000 ms: the probe's own bound, tag=%s\n", tag); r->code = (CURLcode)-1; break; }
    curl_multi_poll(m, NULL, 0, 1000, NULL);
  }
  r->t_ms = mono_ms() - t0;
  r->cpu_ms = cpu_ms(CLOCK_PROCESS_CPUTIME_ID) - c0;
  curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &r->status);
  curl_easy_getinfo(x->h, CURLINFO_HTTP_VERSION, &r->ver);
  curl_easy_getinfo(x->h, CURLINFO_HEADER_SIZE, &r->header_size);
  curl_multi_remove_handle(m, x->h);
  curl_multi_cleanup(m);
  if (hl) curl_slist_free_all(hl);
}

static void tag_of(char *out, size_t cap, const char *cs, const char *label, int mode) {
  char *c;
  snprintf(out, cap, "%s.%s.%s.%ld", cs, label, MODE_NAME[mode], ++g_seq);
  for (c = out; *c; c++) if (*c == ':' || *c == '/' || *c == '&' || *c == '=' || *c == '?' || *c == '+' || *c == ' ') *c = '.';
}

static const char *g_modes;

/* cell: one transfer in each mode PROBE_MODES names, each with its line. */
static void cell(const char *cs, const char *label, const char *face, const char *pathq, unsigned flags, const char *arm) {
  int mode;
  for (mode = 0; mode < 3; mode++) {
    xfer x;
    result r;
    char tag[256], e[2 * CURL_ERROR_SIZE], hs[2048], extra[200] = "";
    size_t o = 0;
    int i;
    long seq0;
    if (!strstr(g_modes, MODE_NAME[mode])) continue;
    tag_of(tag, sizeof tag, cs, label, mode);
    if (arm) {
      char p[2048], b[64];
      snprintf(p, sizeof p, "/arm?%s&tag=%s", arm, tag);
      if (ctl(p, b, sizeof b) < 0) printf("ctl: /arm failed\n");
    }
    seq0 = ctl_seq();
    run(&x, face, pathq, tag, mode, flags, &r);
    if (mode == M_OBS || r.code == CURLE_OK) {
      r.stored = walk(x.h, CURLH_HEADER, -1, &r.walk_ms, &r.walk_cpu_ms);
      r.walked = 1;
    }
    if (flags & F_WALKALL) {
      unsigned all = CURLH_HEADER | CURLH_TRAILER | CURLH_CONNECT | CURLH_1XX;
      snprintf(extra, sizeof extra, " stored_all=%ld stored_r0=%ld stored_r1=%ld", walk(x.h, all, -1, NULL, NULL),
               walk(x.h, all, 0, NULL, NULL), walk(x.h, all, 1, NULL, NULL));
    }
    esc(x.errbuf, strlen(x.errbuf), e, sizeof e);
    hs[0] = 0;
    for (i = 0; i < x.nheads && o + 40 < sizeof hs; i++)
      o += (size_t)snprintf(hs + o, sizeof hs - o, "%s%s:%ld:%ld", i ? "," : "", x.heads[i].label, x.heads[i].lines, x.heads[i].bytes);
    printf("cell %s %s face=%s%s mode=%s code=%d err=\"%s\" status=%ld ver=%ld t_ms=%.1f cpu_ms=%.1f calls=%ld hdr_lines=%ld bytes=%ld heads=[%s] refused=%s header_size=%ld stored=%ld walk_ms=%.2f walk_cpu_ms=%.2f%s live_kb=%lld\n",
           cs, label, face, (flags & F_PROXY) ? "+proxy" : "", MODE_NAME[mode], (int)r.code, e, r.status, r.ver, r.t_ms, r.cpu_ms,
           mode == M_NONE ? -1L : x.calls, mode == M_NONE ? -1L : x.hdr_lines, mode == M_NONE ? -1L : x.bytes, hs,
           mode == M_CAP ? (x.refused ? x.refused_txt : "none") : "-", r.header_size, r.stored, r.walk_ms, r.walk_cpu_ms, extra,
           (long long)(__atomic_load_n(&live, __ATOMIC_SEQ_CST) / 1024));
    curl_easy_cleanup(x.h);
    srv_lines(seq0);
  }
}

static const char *FACES[] = { "h1", "h1tls", "h2" };

/* ---------------------------------------------------------------- cases */
static void c_count(void) {
  static const long NS[] = { 1000, 4999, 5000, 5001, 10000, 50000 };
  char label[64], pq[256];
  size_t f, i;
  for (f = 0; f < 3; f++)
    for (i = 0; i < sizeof NS / sizeof NS[0]; i++) {
      snprintf(label, sizeof label, "n%ld", NS[i]);
      snprintf(pq, sizeof pq, "/head?n=%ld&line=16", NS[i]);
      cell("count", label, FACES[f], pq, 0, NULL);
    }
  for (i = 1; i < sizeof NS / sizeof NS[0]; i++) {
    snprintf(label, sizeof label, "n%ld-same", NS[i]);
    snprintf(pq, sizeof pq, "/head?n=%ld&line=16&same=1", NS[i]);
    cell("count", label, "h2", pq, 0, NULL);
  }
}

static void c_bytes(void) {
  static const long TS[] = { 307199, 307200, 307201, 1048576 };
  static const long BS[] = { 102398, 102399, 102400, 102401 };
  char label[64], pq[256];
  size_t f, i;
  for (f = 0; f < 3; f++) {
    int slen = !strcmp(FACES[f], "h2") ? 13 : 17;
    for (i = 0; i < 4; i++) {
      snprintf(label, sizeof label, "total%ld", TS[i]);
      snprintf(pq, sizeof pq, "/head?total=%ld&line=256&slen=%d", TS[i], slen);
      cell("bytes", label, FACES[f], pq, 0, NULL);
    }
    for (i = 0; i < 4; i++) {
      snprintf(label, sizeof label, "line%ld", BS[i]);
      snprintf(pq, sizeof pq, "/head?n=1&big=%ld", BS[i]);
      cell("bytes", label, FACES[f], pq, 0, NULL);
    }
  }
  for (i = 0; i < 4; i++) {
    snprintf(label, sizeof label, "total%ld-same", TS[i]);
    snprintf(pq, sizeof pq, "/head?total=%ld&line=256&slen=13&same=1", TS[i]);
    cell("bytes", label, "h2", pq, 0, NULL);
  }
  cell("bytes", "line102400-X", "h2", "/head?n=1&big=102400&bigch=X", 0, NULL);
  /* 7.85.0 gathers an HTTP/2 head in a dynbuf of DYN_H2_HEADERS, 128 KiB */
  for (i = 0; i < 3; i++) {
    snprintf(label, sizeof label, "total%ld", 131071 + (long)i);
    snprintf(pq, sizeof pq, "/head?total=%ld&line=256&slen=13", 131071 + (long)i);
    cell("bytes", label, "h2", pq, 0, NULL);
  }
}

static void c_toward(void) {
  static const struct { const char *label, *pq; } PRE[] = {
    { "pre103-6000+2", "/head?pre=103:6000:16&n=2" },
    { "pre103-3000+3000", "/head?pre=103:3000:16&n=3000" },
    { "pre100-3000+3000", "/head?pre=100:3000:16&n=3000" },
    { "pre103-2500x2+1000", "/head?pre=103:2500:16,103:2500:16&n=1000" },
    { "pre103-400K+2", "/head?pre=103:1600:256&n=2" },
    { "pre103-200K+200K", "/head?pre=103:800:256&n=800&line=256" },
    { "tr-2+6000", "/head?n=2&tn=6000&tl=16" },
    { "tr-3000+3000", "/head?n=3000&tn=3000&tl=16" },
    { "tr-2+400K", "/head?n=2&tn=1600&tl=256" },
    { "tr-200K+200K", "/head?n=800&line=256&tn=800&tl=256" },
    { "tr-line4000", "/head?n=2&tn=1&tl=4000" },
    { "tr-line5000", "/head?n=2&tn=1&tl=5000" },
  };
  static const struct { const char *label, *pq; } FLOW[] = {
    { "auth-2+2", "/auth?a.n=2&b.n=2" },
    { "auth-6000+2", "/auth?a.n=6000&b.n=2" },
    { "auth-3000+3000", "/auth?a.n=3000&b.n=3000" },
    { "auth-200K+200K", "/auth?a.n=800&a.line=256&b.n=800&b.line=256" },
    { "redir-2+2", "/redir?a.n=2&b.n=2" },
    { "redir-3000+3000", "/redir?a.n=3000&b.n=3000" },
    { "redir-200K+200K", "/redir?a.n=800&a.line=256&b.n=800&b.line=256" },
  };
  static const struct { const char *label, *pq; } EXPECT[] = {
    { "expect-2+2", "/expect?a.n=2&b.n=2" },
    { "expect-6000+2", "/expect?a.n=6000&b.n=2" },
    { "expect-3000+3000", "/expect?a.n=3000&b.n=3000" },
    { "expect-200K+200K", "/expect?a.n=800&a.line=256&b.n=800&b.line=256" },
  };
  static const struct { const char *label, *arm, *pq; } CONNECT[] = {
    { "connect-2+2", "n=2", "/head?n=2" },
    { "connect-6000+2", "n=6000", "/head?n=2" },
    { "connect-3000+3000", "n=3000", "/head?n=3000" },
    { "connect-400K+2", "n=1600&line=256", "/head?n=2" },
    { "connect-200K+200K", "n=800&line=256", "/head?n=800&line=256" },
  };
  static const char *TF[] = { "h1", "h2" };
  static const char *CF[] = { "h1tls", "h2" };
  size_t f, i;
  for (f = 0; f < 2; f++)
    for (i = 0; i < sizeof PRE / sizeof PRE[0]; i++) cell("toward", PRE[i].label, TF[f], PRE[i].pq, F_WALKALL, NULL);
  for (f = 0; f < 2; f++)
    for (i = 0; i < sizeof FLOW / sizeof FLOW[0]; i++)
      cell("toward", FLOW[i].label, TF[f], FLOW[i].pq, F_WALKALL | (FLOW[i].label[0] == 'a' ? F_DIGEST : F_FOLLOW), NULL);
  for (i = 0; i < sizeof EXPECT / sizeof EXPECT[0]; i++) cell("toward", EXPECT[i].label, "h1", EXPECT[i].pq, F_WALKALL | F_EXPECT, NULL);
  for (f = 0; f < 2; f++)
    for (i = 0; i < sizeof CONNECT / sizeof CONNECT[0]; i++)
      cell("toward", CONNECT[i].label, CF[f], CONNECT[i].pq, F_WALKALL | F_PROXY, CONNECT[i].arm);
}

static void c_walk(void) {
  long ns[16];
  int nn = 0, rounds, r, i, k;
  const char *e = getenv("WALK_NS");
  char buf[256], *tok;
  snprintf(buf, sizeof buf, "%s", e && *e ? e : "100 1000 2000 5000");
  for (tok = strtok(buf, " "); tok && nn < 16; tok = strtok(NULL, " ")) ns[nn++] = atol(tok);
  rounds = getenv("WALK_ROUNDS") && *getenv("WALK_ROUNDS") ? atoi(getenv("WALK_ROUNDS")) : 7;
  for (r = 0; r < rounds; r++)
    for (i = 0; i < nn; i++) {
      long n = ns[(i + r) % nn];
      for (k = 0; k < 2; k++) {
        int same = (k + r) % 2;
        xfer x;
        result res;
        char tag[128], pq[128], e2[2 * CURL_ERROR_SIZE];
        double w1, c1, w2, c2;
        long s1, s2;
        snprintf(tag, sizeof tag, "walk.n%ld.%s.r%d.%ld", n, same ? "same" : "distinct", r, ++g_seq);
        snprintf(pq, sizeof pq, "/head?n=%ld&line=16%s", n, same ? "&same=1" : "");
        run(&x, "h1", pq, tag, M_NONE, 0, &res);
        s1 = walk(x.h, CURLH_HEADER, -1, &w1, &c1);
        s2 = walk(x.h, CURLH_HEADER, -1, &w2, &c2);
        esc(x.errbuf, strlen(x.errbuf), e2, sizeof e2);
        printf("walk n=%ld names=%s round=%d code=%d err=\"%s\" status=%ld t_ms=%.1f stored=%ld walk1_ms=%.3f walk1_cpu_ms=%.3f stored2=%ld walk2_ms=%.3f walk2_cpu_ms=%.3f\n",
               n, same ? "same" : "distinct", r, (int)res.code, e2, res.status, res.t_ms, s1, w1, c1, s2, w2, c2);
        curl_easy_cleanup(x.h);
      }
    }
}

int main(int argc, char **argv) {
  CURLcode g;
  curl_version_info_data *v;
  setvbuf(stdout, NULL, _IOLBF, 0);
  g = curl_global_init_mem(CURL_GLOBAL_ALL, c_malloc, c_free, c_realloc, c_strdup, c_calloc);
  if (g) { printf("curl_global_init_mem rc=%d\n", (int)g); return 1; }
  v = curl_version_info(CURLVERSION_NOW);
  VNUM = v->version_num;
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    printf("version headers=%s runtime=%s num=0x%06x ssl=%s nghttp2=%s http2=%d features=0x%x\n", LIBCURL_VERSION, v->version, v->version_num,
           v->ssl_version ? v->ssl_version : "-", v->nghttp2_version ? v->nghttp2_version : "-", !!(v->features & CURL_VERSION_HTTP2),
           (unsigned)v->features);
    curl_global_cleanup();
    return 0;
  }
  if (argc != 8) { fprintf(stderr, "usage: probe CASE CTL H1 H1TLS H2 PROXY CA | probe --version\n"); return 2; }
  P_CTL = atoi(argv[2]);
  P_H1 = atoi(argv[3]);
  P_H1TLS = atoi(argv[4]);
  P_H2 = atoi(argv[5]);
  P_PROXY = atoi(argv[6]);
  CA = argv[7];
  g_modes = getenv("PROBE_MODES") && *getenv("PROBE_MODES") ? getenv("PROBE_MODES") : "obs none cap";
  if (!strcmp(argv[1], "count")) c_count();
  else if (!strcmp(argv[1], "bytes")) c_bytes();
  else if (!strcmp(argv[1], "toward")) c_toward();
  else if (!strcmp(argv[1], "walk")) c_walk();
  else { fprintf(stderr, "probe: no case %s\n", argv[1]); return 2; }
  printf("case %s all done live_before_global_cleanup=%lld\n", argv[1], (long long)__atomic_load_n(&live, __ATOMIC_SEQ_CST));
  curl_global_cleanup();
  printf("case %s live_after_global_cleanup=%lld\n", argv[1], (long long)__atomic_load_n(&live, __ATOMIC_SEQ_CST));
  return 0;
}
