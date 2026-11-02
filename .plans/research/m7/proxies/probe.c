/* M7's proxy probe (2026-11-02; the M7 plan's measurements).

     probe --version
     probe CTL PKI CASE URL [STEP]...

   The first prints the loaded libcurl: its version by the headers and at
   run time, its TLS backend after curl_global_init (on a MultiSSL build
   the one in use is the one outside parentheses), its features, and a
   fresh handle's default CA file and CA path (CURLINFO_CAINFO and
   CURLINFO_CAPATH, 7.84.0).

   The second runs one transfer of URL, a GET, and prints what it did, each
   line beginning "case CASE". CTL is server.mjs's control port: the probe
   asks it to begin CASE before the transfer, and for CASE's log after the
   transfer's handles are cleaned up, every connection closed; it prints
   that log as "server:" lines. PKI is the run's tests/make-test-pki.sh
   directory, with cadir/ and otherdir/ (each a CA and its hash link) that
   run.sh adds.

   The transfer goes through the multi interface as chez-curl's engine
   steps it: curl_multi_perform, curl_multi_info_read, then curl_multi_poll
   for at most 100 ms, until the transfer is done, or 20 s pass. It gets the
   engine's options: PROTOCOLS_STR and REDIR_PROTOCOLS_STR "http,https",
   NOSIGNAL 1, FOLLOWLOCATION 0, SSL_VERIFYPEER 1, SSL_VERIFYHOST 2; and
   TIMEOUT_MS 10000. It sets no proxy option, CA or anything else unless a
   STEP does; each STEP is applied in order:

     env:NAME=VALUE        setenv before curl_global_init (run.sh runs the
                           probe under env -i, so these are its environment)
     proxy=V               CURLOPT_PROXY
     noproxy=V             CURLOPT_NOPROXY
     proxy-user=V          CURLOPT_PROXYUSERNAME
     proxy-pass=V          CURLOPT_PROXYPASSWORD
     proxy-userpwd=V       CURLOPT_PROXYUSERPWD
     proxyauth=A           CURLOPT_PROXYAUTH: basic, digest, any
     header=V              appended to CURLOPT_HTTPHEADER
     proxyheader=V         appended to CURLOPT_PROXYHEADER
     headeropt=unified|separate   CURLOPT_HEADEROPT
     tunnel=N              CURLOPT_HTTPPROXYTUNNEL
     proxy-ca=V            CURLOPT_PROXY_CAINFO
     proxy-capath=V        CURLOPT_PROXY_CAPATH
     proxy-verifypeer=N    CURLOPT_PROXY_SSL_VERIFYPEER
     proxy-verifyhost=N    CURLOPT_PROXY_SSL_VERIFYHOST
     ca=V                  CURLOPT_CAINFO
     capath=V              CURLOPT_CAPATH
     verifypeer=N          CURLOPT_SSL_VERIFYPEER
     verifyhost=N          CURLOPT_SSL_VERIFYHOST

   In a value, \xHH is the byte HH; "null" is a NULL pointer, and an empty
   value the empty string; @ca, @other, @cadir and @otherdir are PKI's
   ca.pem, other-ca.pem, cadir and otherdir. A setopt that answers other
   than CURLE_OK prints "setopt NAME rc=N" and the transfer still runs.

   Lines: "env" (the whole environment the transfer ran with), "setopt",
   "debug" (libcurl's CURLOPT_DEBUGFUNCTION text, header_out with every byte,
   header_in; text lines of the leaf's fields and the TLS handshake's trace
   are left out, by the prefixes in on_debug), "done" (the result and every
   getinfo below), "server:".
   Exit 0 once the transfer ran, whatever its result; 2 on a usage error or
   when the control port fails. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <curl/curl.h>

extern char **environ;

static const char *CASE;
static const char *PKI;
static char body[4096];
static size_t body_len;

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

/* esc: D's N bytes, \r \n \\ \" and every byte outside 0x20..0x7e as an
   escape, into OUT. */
static void esc(const char *d, size_t n, char *out, size_t cap) {
  size_t o = 0, i;
  for (i = 0; i < n && o + 8 < cap; i++) {
    unsigned char c = (unsigned char)d[i];
    if (c == '\r') { out[o++] = '\\'; out[o++] = 'r'; }
    else if (c == '\n') { out[o++] = '\\'; out[o++] = 'n'; }
    else if (c == '\\' || c == '"') { out[o++] = '\\'; out[o++] = (char)c; }
    else if (c < 0x20 || c > 0x7e) o += (size_t)snprintf(out + o, cap - o, "\\x%02x", c);
    else out[o++] = (char)c;
  }
  if (i < n) o += (size_t)snprintf(out + o, cap - o, "...(%zu bytes)", n);
  out[o] = 0;
}

#define SAY(...) do { printf("case %s ", CASE); printf(__VA_ARGS__); putchar('\n'); } while (0)

/* ---------------------------------------------------------------- control */
/* ctl: GET PATH from 127.0.0.1:PORT on a plain socket; the body into OUT. */
static int ctl(int port, const char *path, char *out, size_t cap) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in sa;
  struct timeval tv = { 8, 0 };
  char req[512], *buf, *b;
  size_t n = 0, bufcap = 1 << 20;
  ssize_t k;
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET;
  sa.sin_port = htons((unsigned short)port);
  sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
  if (connect(fd, (struct sockaddr *)&sa, sizeof sa)) { close(fd); return -1; }
  snprintf(req, sizeof req, "GET %s HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n", path);
  if (write(fd, req, strlen(req)) != (ssize_t)strlen(req)) { close(fd); return -1; }
  buf = malloc(bufcap + 1);
  while (n < bufcap && (k = read(fd, buf + n, bufcap - n)) > 0) n += (size_t)k;
  close(fd);
  buf[n] = 0;
  b = strstr(buf, "\r\n\r\n");
  if (!b) { free(buf); return -1; }
  snprintf(out, cap, "%s", b + 4);
  free(buf);
  return 0;
}

/* ---------------------------------------------------------------- values */
/* value: a step's value, \xHH unescaped, the @ names resolved; NULL for
   "null". The answer is malloc'd, or NULL. */
static char *value(const char *v) {
  char *o, *p;
  const char *name = NULL;
  if (!strcmp(v, "null")) return NULL;
  if (!strcmp(v, "@ca")) name = "ca.pem";
  else if (!strcmp(v, "@other")) name = "other-ca.pem";
  else if (!strcmp(v, "@cadir")) name = "cadir";
  else if (!strcmp(v, "@otherdir")) name = "otherdir";
  if (name) {
    size_t n = strlen(PKI) + strlen(name) + 2;
    o = malloc(n);
    snprintf(o, n, "%s/%s", PKI, name);
    return o;
  }
  o = malloc(strlen(v) + 1);
  for (p = o; *v; ) {
    unsigned int h;
    if (v[0] == '\\' && v[1] == 'x' && isxdigit((unsigned char)v[2]) && isxdigit((unsigned char)v[3]) && sscanf(v + 2, "%2x", &h) == 1) { *p++ = (char)h; v += 4; }
    else *p++ = *v++;
  }
  *p = 0;
  return o;
}

/* ---------------------------------------------------------------- callbacks */
static size_t on_write(char *d, size_t sz, size_t nm, void *u) {
  size_t len = sz * nm, room = sizeof body - 1 - body_len, k = len < room ? len : room;
  (void)u;
  memcpy(body + body_len, d, k);
  body_len += k;
  body[body_len] = 0;
  return len;
}

static int on_debug(CURL *h, curl_infotype type, char *d, size_t n, void *u) {
  static char e[16384];
  (void)h; (void)u;
  if (type == CURLINFO_HEADER_OUT) {
    esc(d, n, e, sizeof e);
    SAY("debug header_out \"%s\"", e);
  } else if (type == CURLINFO_TEXT || type == CURLINFO_HEADER_IN) {
    /* The leaf's fields and the TLS handshake's trace, which say nothing
       of a proxy; every line naming a CA, a verification or an error
       stays. */
    static const char *const quiet[] = { "TLSv1", "  subject:", "  start date:", "  expire date:", "  issuer:",
      "  certificate public key", "  certificate version", "  common name:", "  SSL certificate expiration date OK",
      "  SSL certificate activation date OK", "  SSL certificate status verification SKIPPED", "GnuTLS priority",
      "  subjectAltName:", "Server certificate:", NULL };
    const char *const *q;
    if (type == CURLINFO_TEXT)
      for (q = quiet; *q; q++) if (n >= strlen(*q) && !strncmp(d, *q, strlen(*q))) return 0;
    while (n && (d[n - 1] == '\n' || d[n - 1] == '\r')) n--;
    esc(d, n, e, sizeof e);
    SAY("debug %s \"%s\"", type == CURLINFO_TEXT ? "text" : "header_in", e);
  }
  return 0;
}

/* ---------------------------------------------------------------- steps */
struct opt { const char *name; CURLoption opt; int kind; };  /* kind 0 string, 1 long */
static const struct opt OPTS[] = {
  { "proxy", CURLOPT_PROXY, 0 },
  { "noproxy", CURLOPT_NOPROXY, 0 },
  { "proxy-user", CURLOPT_PROXYUSERNAME, 0 },
  { "proxy-pass", CURLOPT_PROXYPASSWORD, 0 },
  { "proxy-userpwd", CURLOPT_PROXYUSERPWD, 0 },
  { "proxy-ca", CURLOPT_PROXY_CAINFO, 0 },
  { "proxy-capath", CURLOPT_PROXY_CAPATH, 0 },
  { "ca", CURLOPT_CAINFO, 0 },
  { "capath", CURLOPT_CAPATH, 0 },
  { "tunnel", CURLOPT_HTTPPROXYTUNNEL, 1 },
  { "proxy-verifypeer", CURLOPT_PROXY_SSL_VERIFYPEER, 1 },
  { "proxy-verifyhost", CURLOPT_PROXY_SSL_VERIFYHOST, 1 },
  { "verifypeer", CURLOPT_SSL_VERIFYPEER, 1 },
  { "verifyhost", CURLOPT_SSL_VERIFYHOST, 1 },
  { NULL, CURLOPT_URL, 0 }
};

static void check(const char *name, CURLcode rc) {
  if (rc != CURLE_OK) SAY("setopt %s rc=%d (%s)", name, (int)rc, curl_easy_strerror(rc));
}

int main(int argc, char **argv) {
  CURL *h;
  CURLM *m;
  CURLcode rc, code = CURLE_OK;
  struct curl_slist *headers = NULL, *pheaders = NULL;
  char errbuf[CURL_ERROR_SIZE], url[2048], path[512], *log;
  char **ev;
  int i, ctlport, done = 0, envs = 0;
  double t0;
  setvbuf(stdout, NULL, _IOLBF, 0);
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    curl_version_info_data *v;
    char *cainfo = NULL, *capath = NULL;
    if (curl_global_init(CURL_GLOBAL_ALL)) return 2;
    v = curl_version_info(CURLVERSION_NOW);
    h = curl_easy_init();
    curl_easy_getinfo(h, CURLINFO_CAINFO, &cainfo);
    curl_easy_getinfo(h, CURLINFO_CAPATH, &capath);
    printf("version headers=%s runtime=%s ssl=\"%s\" features=0x%x https_proxy=%d ssl_feature=%d asynchdns=%d default_cainfo=%s default_capath=%s\n",
           LIBCURL_VERSION, v->version, v->ssl_version ? v->ssl_version : "-", (unsigned)v->features,
           !!(v->features & CURL_VERSION_HTTPS_PROXY), !!(v->features & CURL_VERSION_SSL), !!(v->features & CURL_VERSION_ASYNCHDNS),
           cainfo ? cainfo : "(null)", capath ? capath : "(null)");
    curl_easy_cleanup(h);
    curl_global_cleanup();
    return 0;
  }
  if (argc < 5) { fprintf(stderr, "usage: probe CTL PKI CASE URL [STEP]... | probe --version\n"); return 2; }
  ctlport = atoi(argv[1]);
  PKI = argv[2];
  CASE = argv[3];
  for (i = 5; i < argc; i++) {
    if (!strncmp(argv[i], "env:", 4)) {
      char *a = argv[i] + 4, *eq = strchr(a, '='), *val;
      if (!eq) { fprintf(stderr, "probe: no NAME=VALUE in %s\n", argv[i]); return 2; }
      *eq = 0;
      val = value(eq + 1);
      if (setenv(a, val ? val : "", 1)) { perror("setenv"); return 2; }
      free(val);
      *eq = '=';
    }
  }
  for (ev = environ; *ev; ev++) {
    char e[2048];
    esc(*ev, strlen(*ev), e, sizeof e);
    SAY("env \"%s\"", e);
    envs++;
  }
  if (!envs) SAY("env (none)");
  snprintf(path, sizeof path, "/begin?case=%s", CASE);
  log = malloc(1 << 20);
  if (ctl(ctlport, path, log, 1 << 20)) { SAY("control: begin failed"); return 2; }
  if (curl_global_init(CURL_GLOBAL_ALL)) { SAY("curl_global_init failed"); return 2; }
  h = curl_easy_init();
  m = curl_multi_init();
  errbuf[0] = 0;
  snprintf(url, sizeof url, "%s", argv[4]);
  check("URL", curl_easy_setopt(h, CURLOPT_URL, url));
  check("PROTOCOLS_STR", curl_easy_setopt(h, CURLOPT_PROTOCOLS_STR, "http,https"));
  check("REDIR_PROTOCOLS_STR", curl_easy_setopt(h, CURLOPT_REDIR_PROTOCOLS_STR, "http,https"));
  check("NOSIGNAL", curl_easy_setopt(h, CURLOPT_NOSIGNAL, 1L));
  check("FOLLOWLOCATION", curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, 0L));
  check("SSL_VERIFYPEER", curl_easy_setopt(h, CURLOPT_SSL_VERIFYPEER, 1L));
  check("SSL_VERIFYHOST", curl_easy_setopt(h, CURLOPT_SSL_VERIFYHOST, 2L));
  check("TIMEOUT_MS", curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, 10000L));
  check("ERRORBUFFER", curl_easy_setopt(h, CURLOPT_ERRORBUFFER, errbuf));
  check("WRITEFUNCTION", curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, on_write));
  check("DEBUGFUNCTION", curl_easy_setopt(h, CURLOPT_DEBUGFUNCTION, on_debug));
  check("VERBOSE", curl_easy_setopt(h, CURLOPT_VERBOSE, 1L));
  for (i = 5; i < argc; i++) {
    char *a = argv[i], *eq, *val;
    const struct opt *o;
    char shown[1024];
    if (!strncmp(a, "env:", 4)) continue;
    eq = strchr(a, '=');
    if (!eq) { SAY("step %s: no =", a); return 2; }
    *eq = 0;
    val = value(eq + 1);
    if (val) esc(val, strlen(val), shown, sizeof shown); else snprintf(shown, sizeof shown, "(null)");
    if (!val && (!strcmp(a, "headeropt") || !strcmp(a, "proxyauth") || !strcmp(a, "tunnel") || strstr(a, "verify"))) { SAY("step %s: null takes no number", a); return 2; }
    SAY("step %s=\"%s\"", a, shown);
    if (!strcmp(a, "header")) headers = curl_slist_append(headers, val ? val : "");
    else if (!strcmp(a, "proxyheader")) pheaders = curl_slist_append(pheaders, val ? val : "");
    else if (!strcmp(a, "headeropt"))
      check("HEADEROPT", curl_easy_setopt(h, CURLOPT_HEADEROPT, !strcmp(val, "unified") ? CURLHEADER_UNIFIED : CURLHEADER_SEPARATE));
    else if (!strcmp(a, "proxyauth")) {
      unsigned long au = !strcmp(val, "basic") ? CURLAUTH_BASIC : !strcmp(val, "digest") ? CURLAUTH_DIGEST : !strcmp(val, "any") ? CURLAUTH_ANY : 0;
      if (!au) { SAY("step proxyauth: no %s", val); return 2; }
      check("PROXYAUTH", curl_easy_setopt(h, CURLOPT_PROXYAUTH, au));
    } else {
      for (o = OPTS; o->name; o++) if (!strcmp(o->name, a)) break;
      if (!o->name) { SAY("step %s: no such step", a); return 2; }
      if (o->kind == 1) check(o->name, curl_easy_setopt(h, o->opt, atol(val)));
      else check(o->name, curl_easy_setopt(h, o->opt, val));
    }
    *eq = '=';
    free(val);  /* libcurl copies every string option */
  }
  if (headers) check("HTTPHEADER", curl_easy_setopt(h, CURLOPT_HTTPHEADER, headers));
  if (pheaders) check("PROXYHEADER", curl_easy_setopt(h, CURLOPT_PROXYHEADER, pheaders));
  t0 = now_ms();
  curl_multi_add_handle(m, h);
  for (;;) {
    int running, q;
    CURLMsg *msg;
    curl_multi_perform(m, &running);
    while ((msg = curl_multi_info_read(m, &q)))
      if (msg->msg == CURLMSG_DONE && msg->easy_handle == h) { done = 1; code = msg->data.result; }
    if (done) break;
    if (now_ms() - t0 > 20000) { SAY("gave-up after 20 s: the probe's own bound"); break; }
    curl_multi_poll(m, NULL, 0, 100, NULL);
  }
  {
    long status = -1, connectcode = -1, perr = -1, reqsize = -1, hdrsize = -1, conns = -1, pport = -1, pavail = -1, havail = -1, pvr = -1, svr = -1, ver = -1;
    char *pip = NULL, b[sizeof body * 4 + 64], eb[CURL_ERROR_SIZE * 4];
    char used[32];
    curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_getinfo(h, CURLINFO_HTTP_CONNECTCODE, &connectcode);
    rc = curl_easy_getinfo(h, CURLINFO_PROXY_ERROR, &perr);
    if (rc) perr = -1000 - (long)rc;
#if LIBCURL_VERSION_NUM >= 0x080700
    {
      long up = -1;
      rc = curl_easy_getinfo(h, CURLINFO_USED_PROXY, &up);
      if (rc) snprintf(used, sizeof used, "getinfo-rc%d", (int)rc); else snprintf(used, sizeof used, "%ld", up);
    }
#else
    snprintf(used, sizeof used, "n/a(headers)");
#endif
    curl_easy_getinfo(h, CURLINFO_REQUEST_SIZE, &reqsize);
    curl_easy_getinfo(h, CURLINFO_HEADER_SIZE, &hdrsize);
    curl_easy_getinfo(h, CURLINFO_NUM_CONNECTS, &conns);
    curl_easy_getinfo(h, CURLINFO_PRIMARY_IP, &pip);
    curl_easy_getinfo(h, CURLINFO_PRIMARY_PORT, &pport);
    curl_easy_getinfo(h, CURLINFO_PROXYAUTH_AVAIL, &pavail);
    curl_easy_getinfo(h, CURLINFO_HTTPAUTH_AVAIL, &havail);
    curl_easy_getinfo(h, CURLINFO_PROXY_SSL_VERIFYRESULT, &pvr);
    curl_easy_getinfo(h, CURLINFO_SSL_VERIFYRESULT, &svr);
    curl_easy_getinfo(h, CURLINFO_HTTP_VERSION, &ver);
    esc(body, body_len, b, sizeof b);
    esc(errbuf, strlen(errbuf), eb, sizeof eb);
    SAY("done code=%d (%s) errbuf=\"%s\" status=%ld connectcode=%ld proxy_error=%ld used_proxy=%s request_size=%ld header_size=%ld num_connects=%ld primary=%s:%ld proxyauth_avail=0x%lx httpauth_avail=0x%lx proxy_ssl_verifyresult=%ld ssl_verifyresult=%ld http_version=%ld body=\"%s\"",
        (int)code, curl_easy_strerror(code), eb, status, connectcode, perr, used, reqsize, hdrsize, conns, pip ? pip : "-", pport,
        (unsigned long)pavail, (unsigned long)havail, pvr, svr, ver, b);
  }
  curl_multi_remove_handle(m, h);
  curl_easy_cleanup(h);
  curl_multi_cleanup(m);
  curl_slist_free_all(headers);
  curl_slist_free_all(pheaders);
  snprintf(path, sizeof path, "/end?case=%s", CASE);
  if (ctl(ctlport, path, log, 1 << 20)) { SAY("control: end failed"); return 2; }
  {
    char *line = log, *nl;
    for (; *line; line = nl + 1) {
      nl = strchr(line, '\n');
      if (nl) *nl = 0;
      SAY("server: %s", line);
      if (!nl) break;
    }
  }
  free(log);
  curl_global_cleanup();
  return 0;
}
