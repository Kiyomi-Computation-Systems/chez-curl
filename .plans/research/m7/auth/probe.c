/* M7's auth probe (2026-11-02; the M7 plan's measurements, area auth: Basic,
   Bearer and Digest). Modelled on M6's pause probe (../../m6/pause/probe.c).

     probe --version
     probe GROUP RAW H2 CA

   RAW and H2 are server.mjs's ports; CA is the run's ca.pem. GROUP is one of
     C  where credentials come from (the brief's item 1)
     A  HTTPAUTH values against each challenge (item 2)
     B  Bearer, with and without HTTPAUTH BEARER (item 2)
     D  Digest variants (item 3)
     W  a whole body across a round, HTTP/1.1 (item 4)
     S  a streamed body across a round, HTTP/1.1 (item 4)
     E  a refusal that arrives before the body is sent whole, HTTP/1.1 and
        HTTP/2 (item 4): answered as the head arrives (early=1), or once
        64 KiB of a 4 MiB body have arrived (after=65536, M6's early-3xx
        shape), each beside a 301 control; the mid-body ones again with
        "Expect:" (named -noexpect). Bound 10 s.
     H  a whole and a streamed body across a round, HTTP/2 (item 4)

   Every transfer goes through the multi interface, in a loop that mirrors
   chez-curl's engine turn (one multi handle per group, a fresh easy handle
   per transfer, removed as soon as it is done): the message step (a slow
   producer's new piece unpauses its read side), the setup step
   (curl_multi_add_handle), curl_multi_perform, curl_multi_info_read, then
   curl_multi_poll for at most 1000 ms, less when the producer's next piece
   is sooner.

   Every transfer gets the engine's options: the URL by CURLOPT_CURLU from
   curl_url_set(CURLUPART_URL, url, 0) (group C also runs every row through
   CURLOPT_URL), PROTOCOLS_STR and REDIR_PROTOCOLS_STR "http,https",
   NOSIGNAL 1, FOLLOWLOCATION 0, PROXY "" (a proxy of #f), HTTP_VERSION 2TLS,
   and on h2 SSL_VERIFYPEER 1, SSL_VERIFYHOST 2, CAINFO at CA and CAPATH
   cleared. A whole body is POSTFIELDSIZE_LARGE then COPYPOSTFIELDS, as
   chez-curl sets it; a streamed one POST 1, POSTFIELDSIZE_LARGE at its
   length or -1, READFUNCTION, PREREQFUNCTION and FRESH_CONNECT 1 (ADR-0032),
   and a SEEKFUNCTION per row: none; one that answers CANTSEEK always
   ("cant"); or one that answers OK to offset 0 from SEEK_SET before the
   read callback has handed a byte and CANTSEEK after ("adr32", ADR-0032's
   rule). Body byte i is i mod 251. A setopt that answers other than
   CURLE_OK prints a line, but CAPATH's clear answering CURLE_NOT_BUILT_IN.

   Output: lines "case NAME FACE ...". VERBOSE 1 with a DEBUGFUNCTION:
   "out #K" lines are request head K as libcurl handed it to the debug
   callback (its request line, then its Authorization, Content-Length,
   Expect and Transfer-Encoding lines, whole); "text" lines libcurl's own
   (group C: only those naming auth or a user); "in" lines are response
   status, WWW-Authenticate and Location lines, from the header callback.
   Times are ms from the transfer's add. "server:" lines are server.mjs's
   log for the transfer's tag, fetched by GET /log on the raw face over a
   plain socket after the transfer. "wire #K" compares request K's
   Authorization value as libcurl logged it with the bytes the server
   received, whole. "row" is the transfer's one-line summary. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <curl/curl.h>

static int P_RAW, P_H2;
static const char *CA;
static int G_PID;

static double abs_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

/* esc: server.mjs's rule. Printable ASCII as is, but \ as \\ and " as \";
   every other byte as \xNN, lower case. */
static void esc(const char *d0, size_t n, char *out, size_t cap) {
  const unsigned char *d = (const unsigned char *)d0;
  size_t o = 0, i;
  for (i = 0; i < n && o + 8 < cap; i++) {
    unsigned char c = d[i];
    if (c == '\\') { out[o++] = '\\'; out[o++] = '\\'; }
    else if (c == '"') { out[o++] = '\\'; out[o++] = '"'; }
    else if (c < 0x20 || c > 0x7e) o += (size_t)snprintf(out + o, cap - o, "\\x%02x", c);
    else out[o++] = (char)c;
  }
  if (i < n) o += (size_t)snprintf(out + o, cap - o, "...(%zu bytes)", n);
  out[o] = 0;
}

static size_t b64dec(const char *s, size_t n, unsigned char *out, size_t cap) {
  static const char A[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  unsigned v = 0;
  int bits = 0;
  size_t o = 0, i;
  for (i = 0; i < n && s[i] && s[i] != '='; i++) {
    const char *p = strchr(A, s[i]);
    if (!p) break;
    v = (v << 6) | (unsigned)(p - A);
    bits += 6;
    if (bits >= 8) { bits -= 8; if (o < cap) out[o++] = (unsigned char)((v >> bits) & 0xff); }
  }
  return o;
}

static int hdr_is(const char *p, size_t len, const char *name) {
  size_t nl = strlen(name);
  return len > nl && !strncasecmp(p, name, nl) && p[nl] == ':';
}

static int has_ci(const char *d, size_t n, const char *w) {
  size_t wl = strlen(w), i;
  for (i = 0; i + wl <= n; i++) if (!strncasecmp(d + i, w, wl)) return 1;
  return 0;
}

/* ---------------------------------------------------------------- transfers */
enum { S_NONE, S_CANT, S_ADR32 };
static const char *SNAME[] = { "none", "cant", "adr32" };
#define MAXOUT 16
#define PIECE 16384

typedef struct xfer {
  CURL *h;
  CURLU *u;
  struct curl_slist *hl;
  char name[200], face[8], tag[240];
  int added, done, removed, gave_up;
  CURLcode code;
  long url_rc;
  double t_add, t_end;
  int quiet;
  int outs;
  char out_auth[MAXOUT][900];
  char out_auth_raw[MAXOUT][600];
  size_t out_auth_len[MAXOUT];
  int out_auth_n[MAXOUT];
  /* body */
  int stream, slow, smode;
  int64_t up_len, up_off, produced;
  int rpaused, end_ready;
  double next_piece;
  int reads, seeks, prereqs, after_seek;
  int64_t got;
  char *whole;
} xfer;

static double rel(const xfer *x) { return abs_ms() - x->t_add; }

#define SAY(x, ...) do { printf("case %s %s ", (x)->name, (x)->face); printf(__VA_ARGS__); putchar('\n'); } while (0)

#define SETOPT(x, opt, val) do { CURLcode rc_ = curl_easy_setopt((x)->h, opt, val); \
    if (rc_ != CURLE_OK && !(opt == CURLOPT_CAPATH && rc_ == CURLE_NOT_BUILT_IN)) \
      SAY(x, "setopt %s rc=%d", #opt, (int)rc_); } while (0)

static size_t on_write(char *d, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  (void)d;
  x->got += (int64_t)(sz * nm);
  return sz * nm;
}

static size_t on_header(char *d, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t n = sz * nm, k = n;
  char e[1600];
  while (k && (d[k - 1] == '\n' || d[k - 1] == '\r')) k--;
  if ((k > 5 && !strncmp(d, "HTTP/", 5)) || hdr_is(d, k, "www-authenticate") || hdr_is(d, k, "location")) {
    esc(d, k, e, sizeof e);
    SAY(x, "in t=%.1f \"%s\"", rel(x), e);
  }
  return n;
}

static int on_debug(CURL *h, curl_infotype type, char *d, size_t n, void *u) {
  xfer *x = u;
  char e[2400];
  (void)h;
  if (type == CURLINFO_HEADER_OUT) {
    size_t i = 0;
    int k, line = 0;
    if (n < 4 || d[0] < 'A' || d[0] > 'Z') {
      esc(d, n < 200 ? n : 200, e, sizeof e);
      SAY(x, "out-fragment t=%.1f bytes=%zu \"%s\"", rel(x), n, e);
      return 0;
    }
    k = x->outs++;
    if (k < MAXOUT) { x->out_auth[k][0] = 0; x->out_auth_n[k] = 0; x->out_auth_len[k] = 0; }
    while (i < n) {
      size_t ls = i, len;
      while (i < n && d[i] != '\r' && d[i] != '\n') i++;
      len = i - ls;
      if (i < n && d[i] == '\r') i++;
      if (i < n && d[i] == '\n') i++;
      if (!len) continue;
      if (line == 0) { esc(d + ls, len, e, sizeof e); SAY(x, "out #%d t=%.1f \"%s\"", k + 1, rel(x), e); }
      else if (hdr_is(d + ls, len, "authorization") || hdr_is(d + ls, len, "content-length") ||
               hdr_is(d + ls, len, "expect") || hdr_is(d + ls, len, "transfer-encoding")) {
        esc(d + ls, len, e, sizeof e);
        SAY(x, "out #%d \"%s\"", k + 1, e);
        if (hdr_is(d + ls, len, "authorization") && k < MAXOUT) {
          size_t v = 14;
          while (v < len && (d[ls + v] == ' ' || d[ls + v] == '\t')) v++;
          if (!x->out_auth_n[k]) {
            esc(d + ls + v, len - v, x->out_auth[k], sizeof x->out_auth[k]);
            x->out_auth_len[k] = len - v < sizeof x->out_auth_raw[k] ? len - v : sizeof x->out_auth_raw[k];
            memcpy(x->out_auth_raw[k], d + ls + v, x->out_auth_len[k]);
          }
          x->out_auth_n[k]++;
        }
      }
      line++;
    }
    return 0;
  }
  if (type == CURLINFO_TEXT) {
    while (n && (d[n - 1] == '\n' || d[n - 1] == '\r')) n--;
    if (x->quiet && !has_ci(d, n, "auth") && !has_ci(d, n, "user")) return 0;
    esc(d, n, e, sizeof e);
    SAY(x, "text t=%.1f \"%s\"", rel(x), e);
  }
  return 0;
}

static size_t on_read(char *buf, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t room = sz * nm;
  int64_t avail, give, i;
  x->reads++;
  avail = (x->slow ? x->produced : x->up_len) - x->up_off;
  if (avail <= 0) {
    if (!x->slow || x->end_ready) {
      SAY(x, "read n=%d t=%.1f answer=0 (the end) offset=%lld", x->reads, rel(x), (long long)x->up_off);
      return 0;
    }
    x->rpaused = 1;
    return CURL_READFUNC_PAUSE;
  }
  give = avail < (int64_t)room ? avail : (int64_t)room;
  if (give > PIECE) give = PIECE;
  for (i = 0; i < give; i++) buf[i] = (char)((x->up_off + i) % 251);
  if (x->reads == 1 || x->after_seek)
    SAY(x, "read n=%d t=%.1f room=%zu answer=%lld from=%lld%s", x->reads, rel(x), room, (long long)give, (long long)x->up_off,
        x->after_seek ? " (the first read after a seek)" : "");
  x->after_seek = 0;
  x->up_off += give;
  return (size_t)give;
}

static int on_seek(void *u, curl_off_t off, int origin) {
  xfer *x = u;
  int ans;
  x->seeks++;
  if (x->smode == S_CANT) ans = CURL_SEEKFUNC_CANTSEEK;
  else ans = (x->up_off == 0 && off == 0 && origin == SEEK_SET) ? CURL_SEEKFUNC_OK : CURL_SEEKFUNC_CANTSEEK;
  SAY(x, "seek n=%d t=%.1f offset=%lld origin=%d handed=%lld answer=%s", x->seeks, rel(x), (long long)off, origin,
      (long long)x->up_off, ans == CURL_SEEKFUNC_OK ? "OK" : "CANTSEEK");
  if (ans == CURL_SEEKFUNC_OK) { x->up_off = off; x->after_seek = 1; }
  return ans;
}

static int on_prereq(void *u, char *pip, char *lip, int pport, int lport) {
  xfer *x = u;
  (void)pip; (void)lip; (void)pport;
  x->prereqs++;
  SAY(x, "prereq n=%d t=%.1f local_port=%d handed=%lld", x->prereqs, rel(x), lport, (long long)x->up_off);
  return CURL_PREREQFUNC_OK;
}

static void set_url(xfer *x, const char *userinfo, const char *pq, int use_curlu) {
  char url[1200], *c;
  snprintf(x->tag, sizeof x->tag, "%s.%s", x->name, x->face);
  for (c = x->tag; *c; c++) if (*c == ':' || *c == '/' || *c == '|') *c = '.';
  snprintf(url, sizeof url, "%s://%s%s127.0.0.1:%d%s%stag=%s", strcmp(x->face, "raw") ? "https" : "http",
           userinfo ? userinfo : "", userinfo ? "@" : "", strcmp(x->face, "raw") ? P_H2 : P_RAW, pq,
           strchr(pq, '?') ? "&" : "?", x->tag);
  x->url_rc = 0;
  if (use_curlu) {
    CURLUcode uc;
    CURLU *old = x->u;
    x->u = curl_url();
    uc = curl_url_set(x->u, CURLUPART_URL, url, 0);
    x->url_rc = (long)uc;
    if (uc) {
      char e[1600];
      esc(url, strlen(url), e, sizeof e);
      SAY(x, "url_set rc=%d (%s) url=\"%s\"", (int)uc, curl_url_strerror(uc), e);
    }
    SETOPT(x, CURLOPT_CURLU, x->u);
    if (old) curl_url_cleanup(old);
  } else {
    SETOPT(x, CURLOPT_URL, url);
  }
}

/* mk: a transfer NAME on FACE of PQ, with USERINFO before the host (NULL:
   none), with the engine's options. Its tag is NAME.FACE, ':' '/' '|' made '.'. */
static xfer *mk(const char *name, const char *face, const char *pq, const char *userinfo, int use_curlu) {
  xfer *x = calloc(1, sizeof *x);
  snprintf(x->name, sizeof x->name, "%s", name);
  snprintf(x->face, sizeof x->face, "%s", face);
  x->h = curl_easy_init();
  set_url(x, userinfo, pq, use_curlu);
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
  SETOPT(x, CURLOPT_DEBUGFUNCTION, on_debug);
  SETOPT(x, CURLOPT_DEBUGDATA, x);
  SETOPT(x, CURLOPT_VERBOSE, 1L);
  return x;
}

static long authbits(const char *m) {
  long b = 0;
  char tmp[64], *t, *save = NULL;
  if (!strcmp(m, "unset")) return -1;
  snprintf(tmp, sizeof tmp, "%s", m);
  for (t = strtok_r(tmp, "|", &save); t; t = strtok_r(NULL, "|", &save)) {
    if (!strcmp(t, "BASIC")) b |= (long)CURLAUTH_BASIC;
    else if (!strcmp(t, "DIGEST")) b |= (long)CURLAUTH_DIGEST;
    else if (!strcmp(t, "BEARER")) b |= (long)CURLAUTH_BEARER;
    else if (!strcmp(t, "ANY")) b |= (long)CURLAUTH_ANY;
    else if (!strcmp(t, "ANYSAFE")) b |= (long)CURLAUTH_ANYSAFE;
    else if (!strcmp(t, "ONLY")) b |= (long)CURLAUTH_ONLY;
    else { fprintf(stderr, "probe: no auth bit %s\n", t); exit(2); }
  }
  return b;
}

static void set_auth(xfer *x, const char *m) {
  long b = authbits(m);
  if (b != -1) SETOPT(x, CURLOPT_HTTPAUTH, (unsigned long)b);
}

static char *pattern(int64_t n) {
  char *p = malloc((size_t)n + 1);
  int64_t i;
  for (i = 0; i < n; i++) p[i] = (char)(i % 251);
  return p;
}

static void whole_body(xfer *x, int64_t n) {
  x->whole = pattern(n);
  SETOPT(x, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)n);
  SETOPT(x, CURLOPT_COPYPOSTFIELDS, x->whole);
}

/* stream_body: N bytes from the read callback, or chunked (-1 to libcurl)
   when CHUNKED; SLOW, a producer of 16 KiB each 100 ms from the add. */
static void stream_body(xfer *x, int64_t n, int chunked, int slow, int smode) {
  x->stream = 1;
  x->up_len = n;
  x->slow = slow;
  x->smode = smode;
  SETOPT(x, CURLOPT_POST, 1L);
  SETOPT(x, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)(chunked ? -1 : n));
  SETOPT(x, CURLOPT_READFUNCTION, on_read);
  SETOPT(x, CURLOPT_READDATA, x);
  if (smode != S_NONE) {
    SETOPT(x, CURLOPT_SEEKFUNCTION, on_seek);
    SETOPT(x, CURLOPT_SEEKDATA, x);
  }
  SETOPT(x, CURLOPT_PREREQFUNCTION, on_prereq);
  SETOPT(x, CURLOPT_PREREQDATA, x);
  SETOPT(x, CURLOPT_FRESH_CONNECT, 1L);
}

static void set_expect(xfer *x, const char *e) {
  if (!strcmp(e, "on")) x->hl = curl_slist_append(x->hl, "Expect: 100-continue");
  else if (!strcmp(e, "off")) x->hl = curl_slist_append(x->hl, "Expect:");
  else return;
  SETOPT(x, CURLOPT_HTTPHEADER, x->hl);
}

static void finish(CURLM *m, xfer *x) {
  long st = 0, ver = 0, conns = -1;
  curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
  curl_easy_getinfo(x->h, CURLINFO_HTTP_VERSION, &ver);
  curl_easy_getinfo(x->h, CURLINFO_NUM_CONNECTS, &conns);
  curl_multi_remove_handle(m, x->h);
  x->removed = 1;
  SAY(x, "done code=%d err=\"%s\" t=%.1f status=%ld ver=%ld conns=%ld outs=%d reads=%d seeks=%d prereqs=%d handed=%lld got=%lld",
      (int)x->code, curl_easy_strerror(x->code), x->t_end - x->t_add, st, ver, conns, x->outs, x->reads, x->seeks, x->prereqs,
      (long long)x->up_off, (long long)x->got);
}

static void producer_step(xfer *x, double t) {
  int gained = 0;
  while (x->produced < x->up_len && t >= x->next_piece) { x->produced += PIECE; x->next_piece += 100; gained++; }
  if (x->produced >= x->up_len && !x->end_ready && t >= x->next_piece) { x->end_ready = 1; gained++; }
  if (gained && x->rpaused) {
    CURLcode rc;
    x->rpaused = 0;
    rc = curl_easy_pause(x->h, CURLPAUSE_CONT);
    if (rc) SAY(x, "cont t=%.1f rc=%d", t - x->t_add, (int)rc);
  }
}

/* drive: the engine's turn over XS until each is done, or BOUND ms pass. */
static void drive(CURLM *m, xfer **xs, int nx, double bound) {
  double start = abs_ms();
  int i, running;
  for (;;) {
    double wait = 1000;
    int open = 0, q;
    CURLMsg *msg;
    for (i = 0; i < nx; i++) {
      xfer *x = xs[i];
      if (x->added && !x->done && x->slow) producer_step(x, abs_ms());
    }
    for (i = 0; i < nx; i++) {
      xfer *x = xs[i];
      if (!x->added) {
        CURLMcode mc;
        x->t_add = abs_ms();
        x->next_piece = x->t_add + 100;
        mc = curl_multi_add_handle(m, x->h);
        x->added = 1;
        if (mc) { SAY(x, "multi_add rc=%d", (int)mc); x->done = 1; x->removed = 1; }
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
      if (!x->done) {
        open = 1;
        if (x->slow && x->next_piece - abs_ms() < wait) wait = x->next_piece - abs_ms();
      }
    }
    if (!open) return;
    if (abs_ms() - start > bound) {
      for (i = 0; i < nx; i++) {
        xfer *x = xs[i];
        if (!x->done) {
          long st = 0;
          curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
          SAY(x, "gave-up after %.0f ms, the probe's own bound: status=%ld outs=%d handed=%lld rpaused=%d", bound, st, x->outs,
              (long long)x->up_off, x->rpaused);
          curl_multi_remove_handle(m, x->h);
          x->removed = 1;
          x->done = 1;
          x->gave_up = 1;
        }
      }
      return;
    }
    if (start + bound - abs_ms() < wait) wait = start + bound - abs_ms();
    if (wait < 0) wait = 0;
    {
      int nfds = -1;
      curl_multi_poll(m, NULL, 0, (int)(wait + 0.999), &nfds);
    }
  }
}

static void drop(xfer *x) {
  if (x->h) curl_easy_cleanup(x->h);
  if (x->u) curl_url_cleanup(x->u);
  if (x->hl) curl_slist_free_all(x->hl);
  free(x->whole);
  free(x);
}

/* server_log: GET /log?tag=TAG on the raw face, over a plain socket; each
   body line printed as X's "server:" line; the body copied to OUT. */
static void server_log(xfer *x, char *out, size_t outcap) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in sa;
  struct timeval tv = { 6, 0 };
  char req[600], *buf, *body, *line, *nl;
  size_t cap = 1 << 20, n = 0;
  ssize_t k;
  if (out && outcap) out[0] = 0;
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

/* wire: request K's Authorization, as libcurl logged it and as the server
   received it, compared whole. */
static int server_count(const char *log) {
  const char *p = strstr(log, "\ncount ");
  const char *q;
  int n = 0;
  if (!p) p = !strncmp(log, "count ", 6) ? log - 1 : NULL;
  if (!p) return -1;
  for (q = p + 7; *q && *q != '\n'; q++) {
    if (!strncmp(q, ":/auth=", 7)) n += atoi(q + 7);
  }
  return n;
}

static void wire(xfer *x, const char *log) {
  int k, sn = server_count(log);
  for (k = 1; k <= x->outs && k <= MAXOUT; k++) {
    char key[64], sv[900];
    const char *p, *q;
    int none = 0;
    size_t o = 0;
    snprintf(key, sizeof key, "auth #%d value=\"", k);
    p = strstr(log, key);
    if (!p) {
      snprintf(key, sizeof key, "auth #%d none", k);
      if (strstr(log, key)) none = 1;
      else { SAY(x, "wire #%d server-has-no-request client=%s", k, x->out_auth_n[k - 1] ? x->out_auth[k - 1] : "none"); continue; }
    }
    if (!none) {
      for (q = p + strlen(key); *q && *q != '"' && o + 2 < sizeof sv; q++) {
        if (*q == '\\' && q[1]) { sv[o++] = *q++; }
        sv[o++] = *q;
      }
      sv[o] = 0;
    }
    if (none && !x->out_auth_n[k - 1]) SAY(x, "wire #%d same (none)", k);
    else if (!none && x->out_auth_n[k - 1] && !strcmp(sv, x->out_auth[k - 1])) SAY(x, "wire #%d same", k);
    else SAY(x, "wire #%d DIFFERS client=%s%s%s server=%s%s%s", k, x->out_auth_n[k - 1] ? "\"" : "", x->out_auth_n[k - 1] ? x->out_auth[k - 1] : "none",
             x->out_auth_n[k - 1] ? "\"" : "", none ? "" : "\"", none ? "none" : sv, none ? "" : "\"");
  }
  if (sn != x->outs) SAY(x, "wire requests client=%d server=%d", x->outs, sn);
}

static void row(xfer *x, const char *log) {
  char seq[2000], one[1000];
  size_t o = 0;
  int k;
  long st = 0;
  curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &st);
  seq[0] = 0;
  for (k = 0; k < x->outs && k < MAXOUT; k++) {
    if (x->out_auth_n[k]) {
      char sch[32];
      size_t i = 0;
      while (i < x->out_auth_len[k] && i < sizeof sch - 1 && x->out_auth_raw[k][i] != ' ') { sch[i] = x->out_auth_raw[k][i]; i++; }
      sch[i] = 0;
      snprintf(one, sizeof one, "%s%s", k ? "," : "", sch);
    } else snprintf(one, sizeof one, "%snone", k ? "," : "");
    o += (size_t)snprintf(seq + o, sizeof seq - o, "%s", one);
  }
  SAY(x, "row code=%d status=%ld outs=%d server=%d auth_out=[%s]%s", (int)x->code, st, x->outs, server_count(log), seq,
      x->gave_up ? " gave-up" : "");
}

static char LOG[1 << 20];

static void run1(CURLM *m, xfer *x, double bound) {
  if (x->url_rc) {
    SAY(x, "skipped: curl_url_set refused the URL, rc=%ld", x->url_rc);
    SAY(x, "row url_rc=%ld not-run", x->url_rc);
    return;
  }
  drive(m, &x, 1, bound);
  server_log(x, LOG, sizeof LOG);
  wire(x, LOG);
  row(x, LOG);
}

/* ---------------------------------------------------------------- C */
static const char *UI[][2] = {
  { "U0-none", NULL }, { "U1-user", "alice" }, { "U2-userpass", "alice:secret" }, { "U3-emptyuser", ":secret" },
  { "U4-emptypass", "alice:" }, { "U5-colononly", ":" }, { "U6-emptyinfo", "" }, { "U7-pct", "a%20b%40c:p%3Aq%2Fr%25" },
  { "U8-colon", "alice:se:cret" }, { "U9-utf8pct", "%C3%BCser:p%C3%A4ss%E2%82%AC" },
  { "U10-utf8raw", "\xC3\xBCser:p\xC3\xA4ss\xE2\x82\xAC" }, { "U11-pctnul", "alice:a%00b" },
};
static const char *OPTS[] = { "O0-none", "O1-username", "O2-password", "O3-both", "O4-userpwd", "O5-userpwd-nocolon",
  "O6-userpwd-emptyuser", "O7-userpwd-then-names", "O8-names-then-userpwd", "O9-emptyusername", "O10-emptypassword",
  "O11-utf8-names", "O12-utf8-userpwd", "O13-userpwd-pct" };

static void apply_opt(xfer *x, int i) {
  switch (i) {
  case 1: SETOPT(x, CURLOPT_USERNAME, "bob"); break;
  case 2: SETOPT(x, CURLOPT_PASSWORD, "hunter2"); break;
  case 3: SETOPT(x, CURLOPT_USERNAME, "bob"); SETOPT(x, CURLOPT_PASSWORD, "hunter2"); break;
  case 4: SETOPT(x, CURLOPT_USERPWD, "carol:pw3"); break;
  case 5: SETOPT(x, CURLOPT_USERPWD, "carol"); break;
  case 6: SETOPT(x, CURLOPT_USERPWD, ":pw3"); break;
  case 7: SETOPT(x, CURLOPT_USERPWD, "carol:pw3"); SETOPT(x, CURLOPT_USERNAME, "bob"); SETOPT(x, CURLOPT_PASSWORD, "hunter2"); break;
  case 8: SETOPT(x, CURLOPT_USERNAME, "bob"); SETOPT(x, CURLOPT_PASSWORD, "hunter2"); SETOPT(x, CURLOPT_USERPWD, "carol:pw3"); break;
  case 9: SETOPT(x, CURLOPT_USERNAME, ""); SETOPT(x, CURLOPT_PASSWORD, "hunter2"); break;
  case 10: SETOPT(x, CURLOPT_USERNAME, "bob"); SETOPT(x, CURLOPT_PASSWORD, ""); break;
  case 11: SETOPT(x, CURLOPT_USERNAME, "\xC3\xBC"); SETOPT(x, CURLOPT_PASSWORD, "\xC3\xA4\xE2\x82\xAC"); break;
  case 12: SETOPT(x, CURLOPT_USERPWD, "\xC3\xBC:\xC3\xA4\xE2\x82\xAC"); break;
  case 13: SETOPT(x, CURLOPT_USERPWD, "a%40b:c%3Ad"); break;
  default: break;
  }
}

static void group_c(CURLM *m) {
  int um, ui, oi;
  const char *modes[] = { "curlu", "url" };
  for (um = 0; um < 2; um++)
    for (ui = 0; ui < (int)(sizeof UI / sizeof UI[0]); ui++)
      for (oi = 0; oi < (int)(sizeof OPTS / sizeof OPTS[0]); oi++) {
        char name[200];
        xfer *x;
        snprintf(name, sizeof name, "C:%s:%s:%s", modes[um], UI[ui][0], OPTS[oi]);
        x = mk(name, "raw", "/auth?ch=open", UI[ui][1], um == 0);
        x->quiet = 1;
        apply_opt(x, oi);
        run1(m, x, 5000);
        if (!x->url_rc && x->outs && x->out_auth_n[0]) {
          unsigned char dec[600];
          char e[2000];
          const char *v = x->out_auth_raw[0];
          size_t n = x->out_auth_len[0];
          if (n > 6 && !strncasecmp(v, "Basic ", 6)) {
            size_t dn = b64dec(v + 6, n - 6, dec, sizeof dec);
            esc((char *)dec, dn, e, sizeof e);
            SAY(x, "cred sent=basic decoded=\"%s\"", e);
          } else SAY(x, "cred sent=other");
        } else if (!x->url_rc) SAY(x, "cred sent=none");
        drop(x);
      }
}

/* ---------------------------------------------------------------- A, B */
static void group_a(CURLM *m) {
  static const char *modes[] = { "unset", "BASIC", "DIGEST", "BEARER", "ANY", "ANYSAFE", "DIGEST|BASIC", "BASIC|ONLY",
    "DIGEST|ONLY", "BEARER|ONLY", "DIGEST|BASIC|ONLY" };
  static const char *chs[] = { "basic", "digest", "both", "both-rev", "bearer", "none", "open" };
  int i, j;
  for (i = 0; i < (int)(sizeof modes / sizeof modes[0]); i++)
    for (j = 0; j < (int)(sizeof chs / sizeof chs[0]); j++) {
      char name[200], pq[200];
      xfer *x;
      snprintf(name, sizeof name, "A:%s:%s", modes[i], chs[j]);
      snprintf(pq, sizeof pq, "/auth?ch=%s&alg=MD5&qop=auth", chs[j]);
      x = mk(name, "raw", pq, "user:pass", 1);
      set_auth(x, modes[i]);
      if (strstr(modes[i], "BEARER")) SETOPT(x, CURLOPT_XOAUTH2_BEARER, "tok123");
      run1(m, x, 5000);
      drop(x);
    }
}

static void group_b(CURLM *m) {
  static const struct { const char *id, *mode, *ui; int token; } rows[] = {
    { "unset-nouser", "unset", NULL, 1 }, { "unset-user", "unset", "user:pass", 1 },
    { "BEARER-nouser", "BEARER", NULL, 1 }, { "BEARER-user", "BEARER", "user:pass", 1 },
    { "ANY-nouser", "ANY", NULL, 1 }, { "ANY-user", "ANY", "user:pass", 1 },
    { "BEARER|BASIC-user", "BEARER|BASIC", "user:pass", 1 }, { "BEARER|ONLY-nouser", "BEARER|ONLY", NULL, 1 },
    { "BEARER-notoken-user", "BEARER", "user:pass", 0 },
  };
  static const char *chs[] = { "open", "bearer", "basic" };
  int i, j;
  for (i = 0; i < (int)(sizeof rows / sizeof rows[0]); i++)
    for (j = 0; j < 3; j++) {
      char name[200], pq[200];
      xfer *x;
      snprintf(name, sizeof name, "B:%s:%s", rows[i].id, chs[j]);
      snprintf(pq, sizeof pq, "/auth?ch=%s", chs[j]);
      x = mk(name, "raw", pq, rows[i].ui, 1);
      set_auth(x, rows[i].mode);
      if (rows[i].token) SETOPT(x, CURLOPT_XOAUTH2_BEARER, "tok123");
      run1(m, x, 5000);
      drop(x);
    }
}

/* ---------------------------------------------------------------- D */
static void d_one(CURLM *m, const char *name, const char *pq, const char *ui, const char *mode, int64_t post) {
  xfer *x = mk(name, "raw", pq, ui, 1);
  set_auth(x, mode);
  if (post) whole_body(x, post);
  run1(m, x, 5000);
  drop(x);
}

static void retarget(xfer *x, const char *name, const char *ui, const char *pq) {
  snprintf(x->name, sizeof x->name, "%s", name);
  set_url(x, ui, pq, 1);
  x->added = x->done = x->removed = x->gave_up = 0;
  x->outs = x->reads = x->seeks = x->prereqs = 0;
  x->got = 0;
  x->code = CURLE_OK;
}

static void group_d(CURLM *m) {
  static const char *algs[] = { "none", "MD5", "MD5-sess", "SHA-256", "SHA-256-sess", "SHA-512-256", "SHA-512-256-sess" };
  static const char *qops[] = { "auth", "auth-int", "none", "both" };
  char name[200], pq[400];
  int i, j;
  for (i = 0; i < 7; i++)
    for (j = 0; j < 4; j++) {
      snprintf(name, sizeof name, "D:alg:%s:%s", algs[i], qops[j]);
      snprintf(pq, sizeof pq, "/auth?ch=digest&alg=%s&qop=%s", algs[i], qops[j]);
      d_one(m, name, pq, "user:pass", "DIGEST", 0);
    }
  for (i = 1; i < 7; i += 2) {
    const char *a = i == 1 ? "MD5" : i == 3 ? "SHA-256" : "SHA-512-256";
    snprintf(name, sizeof name, "D:userhash:%s", a);
    snprintf(pq, sizeof pq, "/auth?ch=digest&alg=%s&qop=auth&userhash=1", a);
    d_one(m, name, pq, "user:pass", "DIGEST", 0);
  }
  for (i = 0; i < 2; i++) {
    const char *a = i ? "SHA-256" : "MD5";
    snprintf(name, sizeof name, "D:stale:%s", a);
    snprintf(pq, sizeof pq, "/auth?ch=digest&alg=%s&qop=auth&stale=1", a);
    d_one(m, name, pq, "user:pass", "DIGEST", 0);
    snprintf(name, sizeof name, "D:wrong:%s", a);
    snprintf(pq, sizeof pq, "/auth?ch=digest&alg=%s&qop=auth", a);
    d_one(m, name, pq, "user:wrong", "DIGEST", 0);
    snprintf(name, sizeof name, "D:authint-post:%s", a);
    snprintf(pq, sizeof pq, "/auth?ch=digest&alg=%s&qop=auth-int", a);
    d_one(m, name, pq, "user:pass", "DIGEST", 1024);
    snprintf(name, sizeof name, "D:auth-post:%s", a);
    snprintf(pq, sizeof pq, "/auth?ch=digest&alg=%s&qop=auth", a);
    d_one(m, name, pq, "user:pass", "DIGEST", 1024);
  }
  /* A UTF-8 user and password, from the URL: u=\xc3\xbcser p=p\xc3\xa4ss */
  d_one(m, "D:utf8:MD5", "/auth?ch=digest&alg=MD5&qop=auth&u=%C3%BCser&p=p%C3%A4ss", "%C3%BCser:p%C3%A4ss", "DIGEST", 0);
  d_one(m, "D:utf8-userhash:SHA-256", "/auth?ch=digest&alg=SHA-256&qop=auth&userhash=1&u=%C3%BCser&p=p%C3%A4ss",
        "%C3%BCser:p%C3%A4ss", "DIGEST", 0);
  /* One nonce, two transfers in sequence: fresh easy handles, then the
     same easy handle re-added (the control). */
  for (i = 0; i < 2; i++) {
    char n1[200], n2[200];
    xfer *x;
    snprintf(pq, sizeof pq, "/auth?ch=digest&alg=MD5&qop=auth&fixnonce=fixed%d%s", G_PID, i ? "same" : "fresh");
    snprintf(n1, sizeof n1, "D:reuse-%s:1", i ? "same" : "fresh");
    snprintf(n2, sizeof n2, "D:reuse-%s:2", i ? "same" : "fresh");
    x = mk(n1, "raw", pq, "user:pass", 1);
    set_auth(x, "DIGEST");
    run1(m, x, 5000);
    if (i) {
      retarget(x, n2, "user:pass", pq);
      run1(m, x, 5000);
      drop(x);
    } else {
      drop(x);
      d_one(m, n2, pq, "user:pass", "DIGEST", 0);
    }
  }
}

/* ---------------------------------------------------------------- W, S */
static const char *PAIRS[][2] = { { "DIGEST", "digest" }, { "ANY", "digest" }, { "ANY", "basic" }, { "DIGEST|BASIC", "digest" },
  { "BASIC", "basic" } };
static const char *EXPECTS[] = { "default", "on", "off" };

static void group_w(CURLM *m) {
  int i, j;
  for (i = 0; i < 5; i++)
    for (j = 0; j < 3; j++) {
      char name[200], pq[200];
      xfer *x;
      snprintf(name, sizeof name, "W:%s:%s:64k:expect-%s", PAIRS[i][0], PAIRS[i][1], EXPECTS[j]);
      snprintf(pq, sizeof pq, "/auth?ch=%s", PAIRS[i][1]);
      x = mk(name, "raw", pq, "user:pass", 1);
      set_auth(x, PAIRS[i][0]);
      whole_body(x, 65536);
      set_expect(x, EXPECTS[j]);
      run1(m, x, 5000);
      drop(x);
    }
  for (i = 0; i < 2; i++) {
    char name[200], pq[200];
    xfer *x;
    snprintf(name, sizeof name, "W:%s:%s:2m:expect-default", PAIRS[i][0], PAIRS[i][1]);
    snprintf(pq, sizeof pq, "/auth?ch=%s", PAIRS[i][1]);
    x = mk(name, "raw", pq, "user:pass", 1);
    set_auth(x, PAIRS[i][0]);
    whole_body(x, 2 * 1048576);
    run1(m, x, 5000);
    drop(x);
  }
}

static void group_s(CURLM *m) {
  static const int pairs[] = { 0, 1, 2, 4 };
  int f, i, s, e;
  for (f = 0; f < 2; f++)
    for (i = 0; i < 4; i++)
      for (s = 0; s < 3; s++)
        for (e = 0; e < 3; e++) {
          char name[200], pq[200];
          xfer *x;
          const char *const *p = PAIRS[pairs[i]];
          snprintf(name, sizeof name, "S:%s:%s:%s:seek-%s:expect-%s", p[0], p[1], f ? "chunked" : "sized", SNAME[s], EXPECTS[e]);
          snprintf(pq, sizeof pq, "/auth?ch=%s", p[1]);
          x = mk(name, "raw", pq, "user:pass", 1);
          set_auth(x, p[0]);
          stream_body(x, 65536, f, 0, s);
          set_expect(x, EXPECTS[e]);
          run1(m, x, 5000);
          drop(x);
        }
}

/* ---------------------------------------------------------------- E, H */
/* A body case: AFTER, when not 0, has the server answer once that many body
   bytes have arrived (after=N), in place of early=1's answer at the head. */
typedef struct { const char *id, *mode, *ui, *ch; int body; int64_t n; int smode; int chunked; int64_t after; } bcase;
static int E_NOEXPECT;   /* body_case adds "Expect:" and "-noexpect" to the name */
enum { BD_WHOLE = 1, BD_SLOW, BD_FAST };

static void body_case(CURLM *m, const char *grp, const char *face, const bcase *c, int early) {
  char name[200], pq[200];
  xfer *x;
  snprintf(name, sizeof name, "%s:%s%s", grp, c->id, E_NOEXPECT ? "-noexpect" : "");
  if (c->after) snprintf(pq, sizeof pq, "/auth?ch=%s&after=%lld", c->ch, (long long)c->after);
  else snprintf(pq, sizeof pq, "/auth?ch=%s%s", c->ch, early ? "&early=1" : "");
  x = mk(name, face, pq, c->ui, 1);
  set_auth(x, c->mode);
  if (c->body == BD_WHOLE) whole_body(x, c->n);
  else stream_body(x, c->n, c->chunked, c->body == BD_SLOW, c->smode);
  if (E_NOEXPECT) set_expect(x, "off");
  run1(m, x, 10000);
  drop(x);
}

static void group_e(CURLM *m) {
  static const bcase cs[] = {
    { "noauth-stream", "unset", NULL, "basic", BD_SLOW, 524288, S_NONE, 0 },
    { "basicwrong-stream", "BASIC", "user:wrong", "basic", BD_SLOW, 524288, S_NONE, 0 },
    { "any-stream", "ANY", "user:pass", "digest", BD_SLOW, 524288, S_NONE, 0 },
    { "any-stream-cant", "ANY", "user:pass", "digest", BD_SLOW, 524288, S_CANT, 0 },
    { "any-stream-adr32", "ANY", "user:pass", "digest", BD_SLOW, 524288, S_ADR32, 0 },
    { "digest-stream", "DIGEST", "user:pass", "digest", BD_SLOW, 524288, S_NONE, 0 },
    { "redirect-stream", "unset", NULL, "redirect", BD_SLOW, 524288, S_NONE, 0 },
    { "noauth-whole1m", "unset", NULL, "basic", BD_WHOLE, 1048576, S_NONE, 0 },
    { "any-whole1m", "ANY", "user:pass", "digest", BD_WHOLE, 1048576, S_NONE, 0 },
    { "redirect-whole1m", "unset", NULL, "redirect", BD_WHOLE, 1048576, S_NONE, 0 },
    /* M6's early-3xx shape: 4 MiB, answered once 64 KiB have arrived. */
    { "redirect-whole4m-mid", "unset", NULL, "redirect", BD_WHOLE, 4194304, S_NONE, 0, 65536 },
    { "noauth-whole4m-mid", "unset", NULL, "basic", BD_WHOLE, 4194304, S_NONE, 0, 65536 },
    { "basicwrong-whole4m-mid", "BASIC", "user:wrong", "basic", BD_WHOLE, 4194304, S_NONE, 0, 65536 },
    { "any-whole4m-mid", "ANY", "user:pass", "digest", BD_WHOLE, 4194304, S_NONE, 0, 65536 },
    { "redirect-stream4m-mid", "unset", NULL, "redirect", BD_FAST, 4194304, S_NONE, 0, 65536 },
    { "noauth-stream4m-mid", "unset", NULL, "basic", BD_FAST, 4194304, S_NONE, 0, 65536 },
    { "any-stream4m-mid-adr32", "ANY", "user:pass", "digest", BD_FAST, 4194304, S_ADR32, 0, 65536 },
    { "digest-stream4m-mid", "DIGEST", "user:pass", "digest", BD_FAST, 4194304, S_NONE, 0, 65536 },
  };
  static const char *faces[] = { "raw", "h2" };
  int f, i;
  for (f = 0; f < 2; f++)
    for (i = 0; i < (int)(sizeof cs / sizeof cs[0]); i++) body_case(m, "E", faces[f], &cs[i], 1);
  /* The mid-body cases again with "Expect:": libcurl's own Expect:
     100-continue, for a body over 1 MiB, sends HTTP/1.1's head alone. */
  E_NOEXPECT = 1;
  for (f = 0; f < 2; f++)
    for (i = 0; i < (int)(sizeof cs / sizeof cs[0]); i++) if (cs[i].after) body_case(m, "E", faces[f], &cs[i], 1);
  E_NOEXPECT = 0;
}

static void group_h(CURLM *m) {
  static const bcase cs[] = {
    { "any-whole", "ANY", "user:pass", "digest", BD_WHOLE, 65536, S_NONE, 0 },
    { "digest-whole", "DIGEST", "user:pass", "digest", BD_WHOLE, 65536, S_NONE, 0 },
    { "basic-whole", "BASIC", "user:pass", "basic", BD_WHOLE, 65536, S_NONE, 0 },
    { "any-stream", "ANY", "user:pass", "digest", BD_FAST, 65536, S_NONE, 0 },
    { "any-stream-cant", "ANY", "user:pass", "digest", BD_FAST, 65536, S_CANT, 0 },
    { "any-stream-adr32", "ANY", "user:pass", "digest", BD_FAST, 65536, S_ADR32, 0 },
    { "any-stream-chunked", "ANY", "user:pass", "digest", BD_FAST, 65536, S_NONE, 1 },
    { "digest-stream", "DIGEST", "user:pass", "digest", BD_FAST, 65536, S_NONE, 0 },
    { "digest-stream-chunked", "DIGEST", "user:pass", "digest", BD_FAST, 65536, S_NONE, 1 },
    { "basic-stream", "BASIC", "user:pass", "basic", BD_FAST, 65536, S_NONE, 0 },
  };
  int i;
  for (i = 0; i < (int)(sizeof cs / sizeof cs[0]); i++) body_case(m, "H", "h2", &cs[i], 0);
}

int main(int argc, char **argv) {
  CURLcode g;
  CURLM *m;
  setvbuf(stdout, NULL, _IOLBF, 0);
  g = curl_global_init(CURL_GLOBAL_ALL);
  if (g) { printf("curl_global_init rc=%d\n", (int)g); return 1; }
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
    printf("version headers=%s runtime=%s ssl=%s nghttp2=%s features=%d http2=%d gssapi=%d spnego=%d ntlm=%d\n", LIBCURL_VERSION,
           v->version, v->ssl_version ? v->ssl_version : "-", v->nghttp2_version ? v->nghttp2_version : "-", v->features,
           !!(v->features & CURL_VERSION_HTTP2), !!(v->features & CURL_VERSION_GSSAPI), !!(v->features & CURL_VERSION_SPNEGO),
           !!(v->features & CURL_VERSION_NTLM));
    curl_global_cleanup();
    return 0;
  }
  if (argc != 5) { fprintf(stderr, "usage: probe GROUP RAW H2 CA | probe --version\n"); return 2; }
  P_RAW = atoi(argv[2]);
  P_H2 = atoi(argv[3]);
  CA = argv[4];
  G_PID = (int)getpid();
  m = curl_multi_init();
  if (!strcmp(argv[1], "C")) group_c(m);
  else if (!strcmp(argv[1], "A")) group_a(m);
  else if (!strcmp(argv[1], "B")) group_b(m);
  else if (!strcmp(argv[1], "D")) group_d(m);
  else if (!strcmp(argv[1], "W")) group_w(m);
  else if (!strcmp(argv[1], "S")) group_s(m);
  else if (!strcmp(argv[1], "E")) group_e(m);
  else if (!strcmp(argv[1], "H")) group_h(m);
  else { fprintf(stderr, "probe: no group %s\n", argv[1]); return 2; }
  curl_multi_cleanup(m);
  printf("group %s all done\n", argv[1]);
  curl_global_cleanup();
  return 0;
}
