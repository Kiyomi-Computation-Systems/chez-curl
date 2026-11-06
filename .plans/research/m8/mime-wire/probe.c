/* M8's mime wire probe (2026-11-06; the M8 plan's measurements, area
   multipart: what a curl_mime body set by MIMEPOST puts on the wire, beside
   the headers and options a chez-curl transfer sets today).

     probe --version
     probe CASE CTL H1 TLSH1 TLSH2 H2C CA FILES

   CTL, H1, TLSH1, TLSH2 and H2C are server.mjs's ports; CA is the run's
   ca.pem; FILES the directory run.sh fills with the file parts' files. CASE
   is one of (the brief's case numbers in brackets):

     H   [1, 2, 8] the head: one data part, two, and a file part of a
         regular file, with no HTTPHEADER and with today's blanks
         ("Content-Type:" and "Expect:"), on each face.
     T   [3] a caller's Content-Type beside MIMEPOST, with "Expect:" beside
         it as a transfer adds today: multipart/form-data; the same with a
         boundary of its own, then that boundary again with a part's data
         holding a part delimited by it ("smuggle"); multipart/mixed;
         text/plain; and "Content-Type;", the form chez-curl gives a header
         with an empty value. Each face.
     E   [4, 8] Expect: bodies of 1,023, 1,025, 1,048,575 and 1,048,577
         bytes in all (one data part, its size set from a calibration
         transfer), with no HTTPHEADER, with "Expect:", and with a caller's
         "Expect: 100-continue"; against cont=1 (the server answers 100) and
         cont=0 (it never does); EXPECT_100_TIMEOUT_MS unset, 300 and 0; each
         face. Then one transfer at EXPECT_100_TIMEOUT_MS 65836, 300 ms past
         65535, on h1 at cont=0; and setopt's answers alone for
         EXPECT_100_TIMEOUT_MS -1, 65535, 65536 and 70000, no transfer.
     M   [5] part metadata bytes: each of a part's name, filename and type set
         alone to each value of MVALS, with MIME_OPTIONS unset and at
         CURLMIMEOPT_FORMESCAPE; a second part "z" after it. h1.
     D   [6] defaults: types by default and by extension, a data part with a
         filename, no name, one name twice, curl_mime_filedata's filename and
         its withdrawal, an empty mime, a part with no data. h1.
     W   [7] methods and twins: MIMEPOST beside CUSTOMREQUEST, NOBODY,
         UPLOAD, POSTFIELDS, COPYPOSTFIELDS, the engine's whole-body pair,
         POSTFIELDSIZE(_LARGE), HTTPPOST, READFUNCTION and INFILESIZE, POST,
         HTTPGET and MIMEPOST NULL, each order where order could matter. h1.
     S   [9] size: 1, 2 and 8 data parts of 100 bytes, and a file part
         beside a data part: CURLINFO_REQUEST_SIZE and SIZE_UPLOAD_T against
         the bytes the server read. Each face.

   Faces: h1 (http, HTTP/1.1), tlsh1 (https; the server offers http/1.1
   alone), tlsh2 (https; the server chooses h2 by ALPN) and h2c (http,
   HTTP_VERSION 2_PRIOR_KNOWLEDGE, as chez-curl sets it for prior knowledge).

   Every transfer runs on a fresh multi handle, so no connection is reused,
   in the engine's turn: curl_multi_perform, curl_multi_info_read, then
   curl_multi_poll for at most 1000 ms; it is removed from its multi once
   done. Each gets the options a chez-curl transfer sets today
   (src/curl/private/transfer.sls, set-transfer-options!): the pins,
   PROTOCOLS_STR and REDIR_PROTOCOLS_STR "http,https", NOSIGNAL 1, MAXREDIRS
   30, and QUICK_EXIT 1 where curl_easy_option_by_name knows it; ERRORBUFFER;
   CURLU, the URL parsed by curl_url_set; WRITEFUNCTION; PROXY ""; on https
   SSL_VERIFYPEER 1, SSL_VERIFYHOST 2, CAINFO at CA and CAPATH cleared; each
   multi handle gets CURLMOPT_QUICK_EXIT 1 where it answers 0, and on 8.7.0
   and 8.7.1 CURLMOPT_PIPELINING 0, as the engine sets them. Then the
   case's body and headers. VERBOSE 1 and a debug callback watch every
   transfer: they change nothing sent.

   stdin is a file holding PROBE-STDIN-MARKER (run.sh); it is rewound before
   each transfer, so a body read from stdin by libcurl's default read
   callback carries the marker, which the server flags (stdin=1). The read
   callback some W cases set gives READFUNCTION-BODY\n (readfn=1).

   Output: per transfer, "case NAME FACE setup ...", libcurl's text and the
   heads it sent and read ("text", "header_out", "header_in"; the text
   leaves out the connection and TLS lines every transfer prints alike,
   NOISE's, counted as text_dropped), a "done" line
   with the result code and the CURLINFO values, then the server's lines for
   the transfer's tag ("server: ..."), fetched on the control port over a
   plain socket once the transfer is done. Times are ms from the transfer's
   add. wait_ms is the debug callback's time from the first head sent to the
   first body byte sent. Escaping: printable ASCII as is, but \ as \\ and "
   as \"; CR as \r, LF as \n; every other byte as \xNN, lower case. */
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

static int P_CTL, P_H1, P_TLSH1, P_TLSH2, P_H2C;
static const char *CA, *FILES;

static double abs_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

static void esc(const char *d, size_t n, char *out, size_t cap) {
  size_t o = 0, i;
  for (i = 0; i < n && o + 8 < cap; i++) {
    unsigned char c = (unsigned char)d[i];
    if (c == '\r') { out[o++] = '\\'; out[o++] = 'r'; }
    else if (c == '\n') { out[o++] = '\\'; out[o++] = 'n'; }
    else if (c == '\\') { out[o++] = '\\'; out[o++] = '\\'; }
    else if (c == '"') { out[o++] = '\\'; out[o++] = '"'; }
    else if (c < 0x20 || c > 0x7e) o += (size_t)snprintf(out + o, cap - o, "\\x%02x", c);
    else out[o++] = (char)c;
  }
  if (i < n) o += (size_t)snprintf(out + o, cap - o, "...(%zu bytes)", n);
  out[o] = 0;
}

/* ---------------------------------------------------------------- transfers */
typedef struct xfer {
  CURL *h;
  CURLU *u;
  curl_mime *mime;
  struct curl_slist *hdrs;
  struct curl_httppost *post, *postlast;
  char name[200], face[8], tag[240], errbuf[CURL_ERROR_SIZE + 1];
  double t_add, t_end, t_hout, t_dout, t_100;
  int hout_n, got_100, done, gave_up, rd_calls, text_dropped;
  long long dout_bytes;
  CURLcode code;
} xfer;

#define SAY(x, ...) do { printf("case %s %s ", (x)->name, (x)->face); printf(__VA_ARGS__); putchar('\n'); } while (0)

static int port_of(const char *f) {
  return !strcmp(f, "h1") ? P_H1 : !strcmp(f, "tlsh1") ? P_TLSH1 : !strcmp(f, "tlsh2") ? P_TLSH2 : P_H2C;
}
static int is_tls(const char *f) { return !strcmp(f, "tlsh1") || !strcmp(f, "tlsh2"); }

static size_t on_write(char *d, size_t sz, size_t nm, void *u) { (void)d; (void)u; return sz * nm; }

/* noise: whether libcurl's text line D is one of the connection and TLS
   lines every transfer prints alike, which the log leaves out, counting
   them (text_dropped): each begins with one of NOISE. Every other line is
   printed. */
static const char *NOISE[] = {
  "  ", "Trying", "Connected to", "Established connection", "using HTTP", "Connection #", "Closing connection",
  "SSL", "GnuTLS", "TLSv", "TLS ", "ALPN", "CAfile", "CApath", "Server certificate", "successfully set certificate",
  "Certificate level", "subject:", "issuer:", "start date", "expire date", "[HTTP/2] [1] [", "[HTTP/2] [1] OPENED",
  "Using Stream ID", "Copying HTTP/2 data", "Host 127.0.0.1:", "IPv4", "IPv6", "Hostname 127.0.0.1", "Connecting to",
  "Server auth using", "x509", "Handshake", "Using HTTP2", "Connection state changed", "multiplexing", "h2 [", "h2h3 [",
  "[HTTP/2] [1] ["
};
static int noise(const char *d, size_t n) {
  size_t i;
  for (i = 0; i < sizeof NOISE / sizeof NOISE[0]; i++) {
    size_t k = strlen(NOISE[i]);
    if (n >= k && !memcmp(d, NOISE[i], k)) return 1;
  }
  return 0;
}

static int on_debug(CURL *h, curl_infotype type, char *d, size_t n, void *u) {
  xfer *x = u;
  char e[16384];
  double t = abs_ms() - x->t_add;
  (void)h;
  switch (type) {
  case CURLINFO_HEADER_OUT:
    if (!x->hout_n++) x->t_hout = t;
    esc(d, n, e, sizeof e);
    SAY(x, "header_out t=%.1f \"%s\"", t, e);
    break;
  case CURLINFO_DATA_OUT:
    if (x->dout_bytes == 0 && x->t_dout < 0) x->t_dout = t;
    x->dout_bytes += (long long)n;
    break;
  case CURLINFO_HEADER_IN:
    if (n >= 12 && !strncmp(d, "HTTP/", 5) && strstr(d, " 100") && x->t_100 < 0) { x->t_100 = t; x->got_100 = 1; }
    while (n && (d[n - 1] == '\n' || d[n - 1] == '\r')) n--;
    esc(d, n, e, sizeof e);
    SAY(x, "header_in t=%.1f \"%s\"", t, e);
    break;
  case CURLINFO_TEXT:
    if (noise(d, n)) { x->text_dropped++; break; }
    while (n && (d[n - 1] == '\n' || d[n - 1] == '\r')) n--;
    esc(d, n, e, sizeof e);
    SAY(x, "text t=%.1f \"%s\"", t, e);
    break;
  default:
    break;
  }
  return 0;
}

static const char RD_BODY[] = "READFUNCTION-BODY\n";
static size_t on_read(char *buf, size_t sz, size_t nm, void *u) {
  xfer *x = u;
  size_t n = sizeof RD_BODY - 1;
  x->rd_calls++;
  if (x->rd_calls > 1 || sz * nm < n) return 0;
  memcpy(buf, RD_BODY, n);
  return n;
}

#define SETOPT(x, opt, val) do { CURLcode rc_ = curl_easy_setopt((x)->h, opt, val); \
    if (rc_ != CURLE_OK && !(opt == CURLOPT_CAPATH && rc_ == CURLE_NOT_BUILT_IN)) \
      SAY(x, "setopt %s rc=%d (%s)", #opt, (int)rc_, curl_easy_strerror(rc_)); } while (0)

/* mk: a transfer NAME on FACE, its tag NAME.FACE, to /echo?tag=TAG&cont=CONT,
   with today's options (the header comment). */
static xfer *mk(const char *name, const char *face, int cont) {
  xfer *x = calloc(1, sizeof *x);
  const struct curl_easyoption *qe;
  char url[600], *c;
  CURLUcode uc;
  snprintf(x->name, sizeof x->name, "%s", name);
  snprintf(x->face, sizeof x->face, "%s", face);
  snprintf(x->tag, sizeof x->tag, "%s.%s", name, face);
  for (c = x->tag; *c; c++)
    if (!((*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') || (*c >= '0' && *c <= '9') || *c == '-' || *c == '_')) *c = '.';
  x->t_hout = x->t_dout = x->t_100 = -1;
  x->h = curl_easy_init();
  SETOPT(x, CURLOPT_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
  SETOPT(x, CURLOPT_NOSIGNAL, 1L);
  SETOPT(x, CURLOPT_MAXREDIRS, 30L);
  qe = curl_easy_option_by_name("QUICK_EXIT");
  if (qe) {
    CURLcode rc = curl_easy_setopt(x->h, qe->id, 1L);
    if (rc) SAY(x, "setopt QUICK_EXIT rc=%d", (int)rc);
  }
  SETOPT(x, CURLOPT_ERRORBUFFER, x->errbuf);
  snprintf(url, sizeof url, "%s://127.0.0.1:%d/echo?tag=%s&cont=%d", is_tls(face) ? "https" : "http", port_of(face), x->tag, cont);
  x->u = curl_url();
  uc = curl_url_set(x->u, CURLUPART_URL, url, 0);
  if (uc) SAY(x, "curl_url_set rc=%d", (int)uc);
  SETOPT(x, CURLOPT_CURLU, x->u);
  SETOPT(x, CURLOPT_WRITEFUNCTION, on_write);
  SETOPT(x, CURLOPT_WRITEDATA, x);
  SETOPT(x, CURLOPT_PROXY, "");
  if (!strcmp(face, "h2c")) SETOPT(x, CURLOPT_HTTP_VERSION, (long)CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE);
  if (is_tls(face)) {
    SETOPT(x, CURLOPT_SSL_VERIFYPEER, 1L);
    SETOPT(x, CURLOPT_SSL_VERIFYHOST, 2L);
    SETOPT(x, CURLOPT_CAINFO, CA);
    SETOPT(x, CURLOPT_CAPATH, (char *)NULL);
  }
  SETOPT(x, CURLOPT_VERBOSE, 1L);
  SETOPT(x, CURLOPT_DEBUGFUNCTION, on_debug);
  SETOPT(x, CURLOPT_DEBUGDATA, x);
  return x;
}

static void hdr(xfer *x, const char *line) { x->hdrs = curl_slist_append(x->hdrs, line); }
static void set_headers(xfer *x) { if (x->hdrs) SETOPT(x, CURLOPT_HTTPHEADER, x->hdrs); }
static void set_mime(xfer *x) { SETOPT(x, CURLOPT_MIMEPOST, x->mime); }

/* mime calls, each answer other than 0 printed */
#define MC(x, call) do { CURLcode rc_ = (call); if (rc_) SAY(x, "mime %s rc=%d (%s)", #call, (int)rc_, curl_easy_strerror(rc_)); } while (0)
static curl_mime *mime_of(xfer *x) { if (!x->mime) x->mime = curl_mime_init(x->h); return x->mime; }
static curl_mimepart *part_data(xfer *x, const char *name, const char *data, size_t n) {
  curl_mimepart *p = curl_mime_addpart(mime_of(x));
  if (name) MC(x, curl_mime_name(p, name));
  MC(x, curl_mime_data(p, data, n));
  return p;
}
static curl_mimepart *part_file(xfer *x, const char *name, const char *file) {
  char path[1024];
  curl_mimepart *p = curl_mime_addpart(mime_of(x));
  snprintf(path, sizeof path, "%s/%s", FILES, file);
  if (name) MC(x, curl_mime_name(p, name));
  MC(x, curl_mime_filedata(p, path));
  return p;
}

static long g_multi_qe_rc = -2;

static void finish_print(xfer *x, double total) {
  long status = -1, ver = -1, reqsize = -1, hdrsize = -1;
  curl_off_t up = -1, clup = -1;
  char *method = NULL, eb[600];
  curl_easy_getinfo(x->h, CURLINFO_RESPONSE_CODE, &status);
  curl_easy_getinfo(x->h, CURLINFO_HTTP_VERSION, &ver);
  curl_easy_getinfo(x->h, CURLINFO_EFFECTIVE_METHOD, &method);
  curl_easy_getinfo(x->h, CURLINFO_REQUEST_SIZE, &reqsize);
  curl_easy_getinfo(x->h, CURLINFO_HEADER_SIZE, &hdrsize);
  curl_easy_getinfo(x->h, CURLINFO_SIZE_UPLOAD_T, &up);
  curl_easy_getinfo(x->h, CURLINFO_CONTENT_LENGTH_UPLOAD_T, &clup);
  esc(x->errbuf, strlen(x->errbuf), eb, sizeof eb);
  SAY(x, "done code=%d err=\"%s\" errbuf=\"%s\" status=%ld ver=%ld(%s) method=%s request_size=%ld header_size=%ld size_upload=%lld content_length_upload=%lld t_total=%.1f header_outs=%d t_header_out=%.1f t_100=%.1f t_first_data_out=%.1f wait_ms=%.1f data_out_bytes=%lld read_calls=%d gave_up=%d text_dropped=%d",
      (int)x->code, curl_easy_strerror(x->code), eb, status, ver,
      ver == CURL_HTTP_VERSION_1_0 ? "1.0" : ver == CURL_HTTP_VERSION_1_1 ? "1.1" : ver == CURL_HTTP_VERSION_2_0 ? "2" : ver == 0 ? "none" : "?",
      method ? method : "-", reqsize, hdrsize, (long long)up, (long long)clup, total, x->hout_n, x->t_hout,
      x->t_100, x->t_dout, (x->t_dout >= 0 && x->t_hout >= 0) ? x->t_dout - x->t_hout : -1.0, x->dout_bytes, x->rd_calls, x->gave_up, x->text_dropped);
}

/* ---------------------------------------------------------------- control */
static long ctl(const char *path, char *out, size_t cap) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in sa;
  struct timeval tv = { 10, 0 };
  char req[600], *buf, *body;
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

static char g_log[4 << 20];
static void server_lines(xfer *x) {
  char p[400], *line, *nl;
  snprintf(p, sizeof p, "/log?tag=%s", x->tag);
  if (ctl(p, g_log, sizeof g_log) < 0) { SAY(x, "server: the log fetch failed"); return; }
  for (line = g_log; *line; line = nl + 1) {
    nl = strchr(line, '\n');
    if (!nl) { SAY(x, "server: %s", line); break; }
    *nl = 0;
    SAY(x, "server: %s", line);
  }
}

/* run: X's transfer on a fresh multi handle, then its lines; frees X. */
static void run(xfer *x, const char *setup) {
  CURLM *m = curl_multi_init();
  double start, bound = 20000;
  int running;
  if (g_multi_qe_rc == -2) {
    g_multi_qe_rc = (long)curl_multi_setopt(m, (CURLMoption)21, 1L);  /* CURLMOPT_QUICK_EXIT, 8.20.0 */
    printf("multi CURLMOPT_QUICK_EXIT(21) rc=%ld (set on every multi handle when 0)\n", g_multi_qe_rc);
  } else if (g_multi_qe_rc == 0) curl_multi_setopt(m, (CURLMoption)21, 1L);
  {
    /* the engine sets CURLMOPT_PIPELINING 0 on 8.7.0 and 8.7.1 (ADR-0030,
       amended): so does the probe */
    unsigned vn = curl_version_info(CURLVERSION_NOW)->version_num;
    if (vn == 0x080700 || vn == 0x080701) {
      CURLMcode pc = curl_multi_setopt(m, CURLMOPT_PIPELINING, (long)CURLPIPE_NOTHING);
      static int said;
      if (!said++) printf("multi CURLMOPT_PIPELINING 0 on 8.7.x, as the engine sets it, rc=%d\n", (int)pc);
    }
  }
  SAY(x, "setup %s", setup);
  rewind(stdin);
  x->t_add = start = abs_ms();
  {
    CURLMcode mc = curl_multi_add_handle(m, x->h);
    if (mc) SAY(x, "multi_add rc=%d", (int)mc);
  }
  for (;;) {
    CURLMsg *msg;
    int q;
    curl_multi_perform(m, &running);
    while ((msg = curl_multi_info_read(m, &q)))
      if (msg->msg == CURLMSG_DONE && msg->easy_handle == x->h && !x->done) { x->done = 1; x->code = msg->data.result; x->t_end = abs_ms(); }
    if (x->done) break;
    if (abs_ms() - start > bound) { x->gave_up = 1; x->t_end = abs_ms(); SAY(x, "gave-up after %.0f ms: the probe's own bound", bound); break; }
    curl_multi_poll(m, NULL, 0, 1000, NULL);
  }
  finish_print(x, x->t_end - x->t_add);
  curl_multi_remove_handle(m, x->h);
  server_lines(x);
  curl_easy_cleanup(x->h);
  if (x->mime) curl_mime_free(x->mime);
  if (x->post) curl_formfree(x->post);
  curl_slist_free_all(x->hdrs);
  curl_url_cleanup(x->u);
  curl_multi_cleanup(m);
  free(x);
}

static const char *FACES[] = { "h1", "tlsh1", "tlsh2", "h2c" };

/* ---------------------------------------------------------------- H */
static void body_named(xfer *x, const char *body) {
  if (!strcmp(body, "one-data")) part_data(x, "a", "alpha", 5);
  else if (!strcmp(body, "two-data")) { part_data(x, "a", "alpha", 5); part_data(x, "b", "bravo-bravo", 11); }
  else if (!strcmp(body, "file")) part_file(x, "f", "f.txt");
}
static void c_h(void) {
  const char *bodies[] = { "one-data", "two-data", "file" };
  int b, s, f;
  for (b = 0; b < 3; b++)
    for (s = 0; s < 2; s++)
      for (f = 0; f < 4; f++) {
        char nm[160], su[200];
        xfer *x;
        snprintf(nm, sizeof nm, "H:%s:%s", bodies[b], s ? "blanks" : "none");
        x = mk(nm, FACES[f], 1);
        body_named(x, bodies[b]);
        if (s) { hdr(x, "Content-Type:"); hdr(x, "Expect:"); }
        set_headers(x);
        set_mime(x);
        snprintf(su, sizeof su, "body=%s httpheader=%s", bodies[b], s ? "[\"Content-Type:\" \"Expect:\"]" : "none");
        run(x, su);
      }
}

/* ---------------------------------------------------------------- T */
static void c_t(void) {
  static const struct { const char *label, *line; int smuggle; } CT[] = {
    { "form-data", "Content-Type: multipart/form-data", 0 },
    { "form-data-own-boundary", "Content-Type: multipart/form-data; boundary=caller-boundary-0123456789", 0 },
    { "form-data-own-boundary-smuggle", "Content-Type: multipart/form-data; boundary=caller-boundary-0123456789", 1 },
    { "mixed", "Content-Type: multipart/mixed", 0 },
    { "text-plain", "Content-Type: text/plain", 0 },
    { "semicolon-empty", "Content-Type;", 0 },
  };
  size_t i;
  int f;
  for (i = 0; i < sizeof CT / sizeof CT[0]; i++)
    for (f = 0; f < 4; f++) {
      char nm[160], su[300], e[200];
      xfer *x;
      snprintf(nm, sizeof nm, "T:%s", CT[i].label);
      x = mk(nm, FACES[f], 1);
      if (CT[i].smuggle) {
        /* a part's data that holds the caller's own boundary: a reader that
           takes the first boundary= and skips a preamble finds the part
           "smuggled" in it */
        static const char SM[] = "\r\n--caller-boundary-0123456789\r\nContent-Disposition: form-data; name=\"smuggled\"\r\n\r\nS\r\n--caller-boundary-0123456789--\r\n";
        part_data(x, "a", SM, sizeof SM - 1);
        part_data(x, "b", "bravo-bravo", 11);
      } else body_named(x, "two-data");
      hdr(x, CT[i].line);
      hdr(x, "Expect:");
      set_headers(x);
      set_mime(x);
      esc(CT[i].line, strlen(CT[i].line), e, sizeof e);
      snprintf(su, sizeof su, "body=%s httpheader=[\"%s\" \"Expect:\"]", CT[i].smuggle ? "a=(data holding --caller-boundary-0123456789 and a part smuggled) b=bravo-bravo" : "two-data", e);
      run(x, su);
    }
}

/* ---------------------------------------------------------------- E */
static char *g_big;
static long long g_overhead = -1;
static void c_e(void) {
  static const long sizes[] = { 1023, 1025, 1048575, 1048577 };
  static const char *hsets[] = { "none", "blank-expect", "caller-expect" };
  static const long tmos[] = { -1, 300, 0 };
  static const long probe_tmos[] = { -1, 65535, 65536, 70000 };
  size_t si, hi, ti, pi;
  int cont, f;
  long i;
  g_big = malloc(1048577);
  for (i = 0; i < 1048577; i++) g_big[i] = (char)(i % 251);
  {
    /* calibration: a one-part body of 0 data bytes; its whole size is the
       overhead every size below subtracts. */
    curl_off_t clup = -1;
    xfer *x = mk("E:calibrate", "h1", 1);
    part_data(x, "f", g_big, 0);
    set_mime(x);
    SAY(x, "setup body=one-data-part-f-of-0-bytes httpheader=none");
    {
      CURLM *m = curl_multi_init();
      int running;
      double start;
      rewind(stdin);
      x->t_add = start = abs_ms();
      curl_multi_add_handle(m, x->h);
      for (;;) {
        CURLMsg *msg;
        int q;
        curl_multi_perform(m, &running);
        while ((msg = curl_multi_info_read(m, &q)))
          if (msg->msg == CURLMSG_DONE && msg->easy_handle == x->h) { x->done = 1; x->code = msg->data.result; x->t_end = abs_ms(); }
        if (x->done || abs_ms() - start > 20000) break;
        curl_multi_poll(m, NULL, 0, 1000, NULL);
      }
      finish_print(x, x->t_end - x->t_add);
      curl_easy_getinfo(x->h, CURLINFO_CONTENT_LENGTH_UPLOAD_T, &clup);
      curl_multi_remove_handle(m, x->h);
      server_lines(x);
      curl_multi_cleanup(m);
    }
    g_overhead = (long long)clup;
    SAY(x, "calibration overhead=%lld (CONTENT_LENGTH_UPLOAD_T of the 0-byte part)", g_overhead);
    curl_easy_cleanup(x->h);
    curl_mime_free(x->mime);
    curl_url_cleanup(x->u);
    free(x);
    if (g_overhead <= 0) { printf("case E calibration failed: overhead=%lld\n", g_overhead); return; }
  }
  for (si = 0; si < 4; si++)
    for (hi = 0; hi < 3; hi++)
      for (cont = 1; cont >= 0; cont--)
        for (ti = 0; ti < 3; ti++)
          for (f = 0; f < 4; f++) {
            char nm[160], su[300], tm[16];
            xfer *x;
            long data = sizes[si] - (long)g_overhead;
            if (tmos[ti] < 0) snprintf(tm, sizeof tm, "unset"); else snprintf(tm, sizeof tm, "%ld", tmos[ti]);
            snprintf(nm, sizeof nm, "E:%ld:%s:cont%d:tmo-%s", sizes[si], hsets[hi], cont, tm);
            x = mk(nm, FACES[f], cont);
            part_data(x, "f", g_big, (size_t)data);
            if (hi == 1) hdr(x, "Expect:");
            if (hi == 2) hdr(x, "Expect: 100-continue");
            set_headers(x);
            if (tmos[ti] >= 0) SETOPT(x, CURLOPT_EXPECT_100_TIMEOUT_MS, tmos[ti]);
            set_mime(x);
            snprintf(su, sizeof su, "body=one-data-part-f total=%ld data=%ld httpheader=%s cont=%d expect_100_timeout_ms=%s", sizes[si], data,
                     hi == 0 ? "none" : hi == 1 ? "[\"Expect:\"]" : "[\"Expect: 100-continue\"]", cont, tm);
            run(x, su);
          }
  {
    /* EXPECT_100_TIMEOUT_MS 65836: 300 ms past 65535. A wait of about 300 ms
       is a truncation to 16 bits; the server's own 4 s body bound firing
       first is a wait of 4 s or more, a clamp or the value as given. */
    char su[300];
    xfer *x = mk("E:1048577:none:cont0:tmo-65836", "h1", 0);
    part_data(x, "f", g_big, (size_t)(1048577 - (long)g_overhead));
    SETOPT(x, CURLOPT_EXPECT_100_TIMEOUT_MS, 65836L);
    set_mime(x);
    snprintf(su, sizeof su, "body=one-data-part-f total=1048577 httpheader=none cont=0 expect_100_timeout_ms=65836");
    run(x, su);
  }
  for (pi = 0; pi < 4; pi++) {
    CURL *h = curl_easy_init();
    CURLcode rc = curl_easy_setopt(h, CURLOPT_EXPECT_100_TIMEOUT_MS, probe_tmos[pi]);
    printf("case E:setopt-only - EXPECT_100_TIMEOUT_MS=%ld rc=%d (%s)\n", probe_tmos[pi], (int)rc, curl_easy_strerror(rc));
    curl_easy_cleanup(h);
  }
  free(g_big);
}

/* ---------------------------------------------------------------- M */
static const struct { const char *label; const char *v; } MVALS[] = {
  { "dquote", "a\"b" },
  { "backslash", "a\\b" },
  { "cr", "a\rb" },
  { "lf", "a\nb" },
  { "crlf", "a\r\nb" },
  { "tab", "a\tb" },
  { "x01", "a\x01" "b" },
  { "x1f", "a\x1f" "b" },
  { "x7f", "a\x7f" "b" },
  { "semicolon", "a;b" },
  { "equals", "a=b" },
  { "percent", "a%b" },
  { "space", "a b" },
  { "e-acute-utf8", "a\xc3\xa9" "b" },
  { "raw-e9", "a\xe9" "b" },
  { "empty", "" },
  { "pct22", "a%22b" },
  { "inject-header", "a\r\nX-Injected: 1" },
  { "inject-body", "a\r\n\r\nINJECTED-DATA" },
  { "inject-param", "a\"; filename=\"evil.sh" },
};
static void c_m(void) {
  static const char *fields[] = { "name", "filename", "type" };
  size_t v, fi;
  int opt;
  for (opt = 0; opt < 2; opt++)
    for (fi = 0; fi < 3; fi++)
      for (v = 0; v < sizeof MVALS / sizeof MVALS[0]; v++) {
        char nm[160], su[400], e[200];
        xfer *x;
        curl_mimepart *p;
        snprintf(nm, sizeof nm, "M:%s:%s:%s", opt ? "formescape" : "unset", fields[fi], MVALS[v].label);
        x = mk(nm, "h1", 1);
        p = curl_mime_addpart(mime_of(x));
        if (fi == 0) MC(x, curl_mime_name(p, MVALS[v].v));
        else MC(x, curl_mime_name(p, "n"));
        if (fi == 1) MC(x, curl_mime_filename(p, MVALS[v].v));
        if (fi == 2) MC(x, curl_mime_type(p, MVALS[v].v));
        MC(x, curl_mime_data(p, "v", 1));
        part_data(x, "z", "zz", 2);
        if (opt) SETOPT(x, CURLOPT_MIME_OPTIONS, (long)CURLMIMEOPT_FORMESCAPE);
        set_mime(x);
        esc(MVALS[v].v, strlen(MVALS[v].v), e, sizeof e);
        snprintf(su, sizeof su, "part1 %s=\"%s\" (others: name n, data v) part2 name=z data=zz mime_options=%s", fields[fi], e, opt ? "FORMESCAPE" : "unset");
        run(x, su);
      }
}

/* ---------------------------------------------------------------- D */
static void c_d(void) {
  xfer *x;
  curl_mimepart *p;
  char path[1024];
  static const char *exts[] = { "t.txt", "t.html", "t.bin", "t" };
  size_t i;

  x = mk("D:data-no-type", "h1", 1);
  part_data(x, "a", "alpha", 5);
  set_mime(x);
  run(x, "part a, data alpha, no type, no filename");

  for (i = 0; i < 4; i++) {
    char nm[160], su[200];
    snprintf(nm, sizeof nm, "D:file-no-type:%s", exts[i]);
    x = mk(nm, "h1", 1);
    part_file(x, "f", exts[i]);
    set_mime(x);
    snprintf(su, sizeof su, "part f, curl_mime_filedata FILES/%s, no type, no filename call", exts[i]);
    run(x, su);
  }

  {
    static const char *fns[] = { "d.txt", "d.bin", "d.html", "d" };
    for (i = 0; i < 4; i++) {
      char nm[160], su[200];
      snprintf(nm, sizeof nm, "D:data-with-filename:%s", fns[i]);
      x = mk(nm, "h1", 1);
      p = part_data(x, "a", "alpha", 5);
      MC(x, curl_mime_filename(p, fns[i]));
      set_mime(x);
      snprintf(su, sizeof su, "part a, data alpha, filename %s, no type", fns[i]);
      run(x, su);
    }
  }

  x = mk("D:no-name", "h1", 1);
  part_data(x, NULL, "anon", 4);
  set_mime(x);
  run(x, "one part, no curl_mime_name, data anon");

  x = mk("D:no-name-with-filename", "h1", 1);
  p = part_data(x, NULL, "anon", 4);
  MC(x, curl_mime_filename(p, "x.txt"));
  set_mime(x);
  run(x, "one part, no curl_mime_name, filename x.txt, data anon");

  x = mk("D:one-name-twice", "h1", 1);
  part_data(x, "dup", "one", 3);
  part_data(x, "dup", "two", 3);
  set_mime(x);
  run(x, "parts dup=one, dup=two");

  snprintf(path, sizeof path, "%s/a/b/c.txt", FILES);
  x = mk("D:filedata-filename", "h1", 1);
  p = curl_mime_addpart(mime_of(x));
  MC(x, curl_mime_name(p, "f"));
  MC(x, curl_mime_filedata(p, path));
  set_mime(x);
  run(x, "part f, curl_mime_filedata FILES/a/b/c.txt");

  x = mk("D:filedata-filename-withdrawn", "h1", 1);
  p = curl_mime_addpart(mime_of(x));
  MC(x, curl_mime_name(p, "f"));
  MC(x, curl_mime_filedata(p, path));
  MC(x, curl_mime_filename(p, NULL));
  set_mime(x);
  run(x, "part f, curl_mime_filedata FILES/a/b/c.txt, then curl_mime_filename NULL");

  x = mk("D:filedata-filename-withdrawn-bin", "h1", 1);
  p = curl_mime_addpart(mime_of(x));
  MC(x, curl_mime_name(p, "f"));
  {
    char pb[1024];
    snprintf(pb, sizeof pb, "%s/t.bin", FILES);
    MC(x, curl_mime_filedata(p, pb));
  }
  MC(x, curl_mime_filename(p, NULL));
  set_mime(x);
  run(x, "part f, curl_mime_filedata FILES/t.bin, then curl_mime_filename NULL");

  x = mk("D:filedata-then-filename", "h1", 1);
  p = curl_mime_addpart(mime_of(x));
  MC(x, curl_mime_name(p, "f"));
  MC(x, curl_mime_filedata(p, path));
  MC(x, curl_mime_filename(p, "other.bin"));
  set_mime(x);
  run(x, "part f, curl_mime_filedata FILES/a/b/c.txt, then curl_mime_filename other.bin");

  x = mk("D:filename-then-filedata", "h1", 1);
  p = curl_mime_addpart(mime_of(x));
  MC(x, curl_mime_name(p, "f"));
  MC(x, curl_mime_filename(p, "first.bin"));
  MC(x, curl_mime_filedata(p, path));
  set_mime(x);
  run(x, "part f, curl_mime_filename first.bin, then curl_mime_filedata FILES/a/b/c.txt");

  x = mk("D:file-with-type", "h1", 1);
  p = part_file(x, "f", "t.txt");
  MC(x, curl_mime_type(p, "application/x-chez"));
  set_mime(x);
  run(x, "part f, curl_mime_filedata FILES/t.txt, type application/x-chez");

  x = mk("D:data-type-text-plain", "h1", 1);
  p = part_data(x, "a", "alpha", 5);
  MC(x, curl_mime_type(p, "text/plain"));
  set_mime(x);
  run(x, "part a, data alpha, type text/plain given");

  x = mk("D:empty-mime", "h1", 1);
  mime_of(x);
  set_mime(x);
  run(x, "a mime with no parts");

  x = mk("D:part-no-data", "h1", 1);
  p = curl_mime_addpart(mime_of(x));
  MC(x, curl_mime_name(p, "nodata"));
  set_mime(x);
  run(x, "one part, name nodata, no data call");

  x = mk("D:data-empty", "h1", 1);
  part_data(x, "e", "", 0);
  set_mime(x);
  run(x, "one part, name e, data of 0 bytes");

  x = mk("D:data-zero-terminated", "h1", 1);
  p = curl_mime_addpart(mime_of(x));
  MC(x, curl_mime_name(p, "zt"));
  MC(x, curl_mime_data(p, "abc\0def", CURL_ZERO_TERMINATED));
  set_mime(x);
  run(x, "one part, name zt, data \"abc\\x00def\" by CURL_ZERO_TERMINATED");

  x = mk("D:data-with-nul", "h1", 1);
  part_data(x, "nul", "abc\0def", 7);
  set_mime(x);
  run(x, "one part, name nul, data \"abc\\x00def\", 7 bytes");
}

/* ---------------------------------------------------------------- W */
static void one(xfer *x) { part_data(x, "a", "alpha", 5); }
static void readfn(xfer *x) { SETOPT(x, CURLOPT_READFUNCTION, on_read); SETOPT(x, CURLOPT_READDATA, x); SETOPT(x, CURLOPT_INFILESIZE, 18L); }
static void httppost(xfer *x) {
  CURLFORMcode fc = curl_formadd(&x->post, &x->postlast, CURLFORM_COPYNAME, "hp", CURLFORM_COPYCONTENTS, "HTTPPOST-BODY", CURLFORM_END);
  if (fc) SAY(x, "curl_formadd rc=%d", (int)fc);
  SETOPT(x, CURLOPT_HTTPPOST, x->post);
}
static void c_w(void) {
  xfer *x;
  static const char *crs[] = { "PUT", "PATCH", "DELETE" };
  size_t i;
  for (i = 0; i < 3; i++) {
    char nm[160], su[200];
    snprintf(nm, sizeof nm, "W:customrequest-%s", crs[i]);
    x = mk(nm, "h1", 1); one(x);
    SETOPT(x, CURLOPT_CUSTOMREQUEST, crs[i]); set_mime(x);
    snprintf(su, sizeof su, "CUSTOMREQUEST %s, then MIMEPOST (part a=alpha)", crs[i]);
    run(x, su);
  }
  x = mk("W:nobody-then-mimepost", "h1", 1); one(x); SETOPT(x, CURLOPT_NOBODY, 1L); set_mime(x); run(x, "NOBODY 1, then MIMEPOST");
  x = mk("W:mimepost-then-nobody", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_NOBODY, 1L); run(x, "MIMEPOST, then NOBODY 1");
  x = mk("W:upload-then-mimepost", "h1", 1); one(x); SETOPT(x, CURLOPT_UPLOAD, 1L); set_mime(x); run(x, "UPLOAD 1, then MIMEPOST");
  x = mk("W:mimepost-then-upload", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_UPLOAD, 1L); run(x, "MIMEPOST, then UPLOAD 1 (no read callback: libcurl's default reads stdin)");
  x = mk("W:mimepost-then-upload-readfn", "h1", 1); one(x); set_mime(x); readfn(x); SETOPT(x, CURLOPT_UPLOAD, 1L); run(x, "MIMEPOST, then READFUNCTION, INFILESIZE 18, UPLOAD 1");
  x = mk("W:mimepost-then-readfn", "h1", 1); one(x); set_mime(x); readfn(x); run(x, "MIMEPOST, then READFUNCTION and INFILESIZE 18");
  x = mk("W:readfn-then-mimepost", "h1", 1); one(x); readfn(x); set_mime(x); run(x, "READFUNCTION and INFILESIZE 18, then MIMEPOST");
  x = mk("W:postfields-then-mimepost", "h1", 1); one(x); SETOPT(x, CURLOPT_POSTFIELDS, "POSTFIELDS-BODY"); set_mime(x); run(x, "POSTFIELDS POSTFIELDS-BODY, then MIMEPOST");
  x = mk("W:mimepost-then-postfields", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_POSTFIELDS, "POSTFIELDS-BODY"); run(x, "MIMEPOST, then POSTFIELDS POSTFIELDS-BODY");
  x = mk("W:copypostfields-then-mimepost", "h1", 1); one(x); SETOPT(x, CURLOPT_COPYPOSTFIELDS, "COPYPOSTFIELDS-BODY"); set_mime(x); run(x, "COPYPOSTFIELDS COPYPOSTFIELDS-BODY, then MIMEPOST");
  x = mk("W:mimepost-then-copypostfields", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_COPYPOSTFIELDS, "COPYPOSTFIELDS-BODY"); run(x, "MIMEPOST, then COPYPOSTFIELDS COPYPOSTFIELDS-BODY");
  x = mk("W:whole-body-then-mimepost", "h1", 1); one(x);
  SETOPT(x, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)18); SETOPT(x, CURLOPT_COPYPOSTFIELDS, "ENGINE-WHOLE-BODY!"); set_mime(x);
  run(x, "POSTFIELDSIZE_LARGE 18 and COPYPOSTFIELDS ENGINE-WHOLE-BODY! (a whole body as a transfer sets it today), then MIMEPOST");
  x = mk("W:mimepost-then-whole-body", "h1", 1); one(x); set_mime(x);
  SETOPT(x, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)18); SETOPT(x, CURLOPT_COPYPOSTFIELDS, "ENGINE-WHOLE-BODY!");
  run(x, "MIMEPOST, then POSTFIELDSIZE_LARGE 18 and COPYPOSTFIELDS ENGINE-WHOLE-BODY!");
  x = mk("W:postfieldsize-then-mimepost", "h1", 1); one(x); SETOPT(x, CURLOPT_POSTFIELDSIZE, 5L); set_mime(x); run(x, "POSTFIELDSIZE 5, then MIMEPOST");
  x = mk("W:mimepost-then-postfieldsize", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_POSTFIELDSIZE, 5L); run(x, "MIMEPOST, then POSTFIELDSIZE 5");
  x = mk("W:mimepost-then-postfieldsize-large", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)5); run(x, "MIMEPOST, then POSTFIELDSIZE_LARGE 5");
  x = mk("W:mimepost-then-postfieldsize-minus1", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)-1); run(x, "MIMEPOST, then POSTFIELDSIZE_LARGE -1");
  x = mk("W:httppost-then-mimepost", "h1", 1); one(x); httppost(x); set_mime(x); run(x, "HTTPPOST hp=HTTPPOST-BODY, then MIMEPOST");
  x = mk("W:mimepost-then-httppost", "h1", 1); one(x); set_mime(x); httppost(x); run(x, "MIMEPOST, then HTTPPOST hp=HTTPPOST-BODY");
  x = mk("W:post1-then-mimepost", "h1", 1); one(x); SETOPT(x, CURLOPT_POST, 1L); set_mime(x); run(x, "POST 1, then MIMEPOST");
  x = mk("W:mimepost-then-post1", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_POST, 1L); run(x, "MIMEPOST, then POST 1 (no read callback: libcurl's default reads stdin)");
  x = mk("W:mimepost-then-post0", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_POST, 0L); run(x, "MIMEPOST, then POST 0");
  x = mk("W:mimepost-then-httpget", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_HTTPGET, 1L); run(x, "MIMEPOST, then HTTPGET 1");
  x = mk("W:httpget-then-mimepost", "h1", 1); one(x); SETOPT(x, CURLOPT_HTTPGET, 1L); set_mime(x); run(x, "HTTPGET 1, then MIMEPOST");
  x = mk("W:mimepost-then-mimepost-null", "h1", 1); one(x); set_mime(x); SETOPT(x, CURLOPT_MIMEPOST, (curl_mime *)NULL); run(x, "MIMEPOST, then MIMEPOST NULL");
  x = mk("W:customrequest-GET", "h1", 1); one(x); SETOPT(x, CURLOPT_CUSTOMREQUEST, "GET"); set_mime(x); run(x, "CUSTOMREQUEST GET, then MIMEPOST");
}

/* ---------------------------------------------------------------- S */
static void c_s(void) {
  static const int ns[] = { 1, 2, 8 };
  char data[100];
  size_t i;
  int f, k;
  for (k = 0; k < 100; k++) data[k] = (char)('a' + k % 26);
  for (i = 0; i < 4; i++)
    for (f = 0; f < 4; f++) {
      char nm[160], su[200];
      xfer *x;
      if (i < 3) {
        snprintf(nm, sizeof nm, "S:parts-%d", ns[i]);
        x = mk(nm, FACES[f], 1);
        for (k = 0; k < ns[i]; k++) { char pn[16]; snprintf(pn, sizeof pn, "p%d", k + 1); part_data(x, pn, data, 100); }
        snprintf(su, sizeof su, "%d data parts p1.. of 100 bytes each", ns[i]);
      } else {
        snprintf(nm, sizeof nm, "S:file-and-data");
        x = mk(nm, FACES[f], 1);
        part_file(x, "f", "f.txt");
        part_data(x, "p1", data, 100);
        snprintf(su, sizeof su, "a file part f (FILES/f.txt) and a data part p1 of 100 bytes");
      }
      set_mime(x);
      run(x, su);
    }
}

int main(int argc, char **argv) {
  CURLcode g;
  setvbuf(stdout, NULL, _IOLBF, 0);
  g = curl_global_init(CURL_GLOBAL_ALL);
  if (g) { printf("curl_global_init rc=%d\n", (int)g); return 1; }
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
    printf("version headers=%s runtime=%s ssl=%s nghttp2=%s http2=%d features=0x%x\n", LIBCURL_VERSION, v->version, v->ssl_version ? v->ssl_version : "-",
           v->nghttp2_version ? v->nghttp2_version : "-", !!(v->features & CURL_VERSION_HTTP2), (unsigned)v->features);
    curl_global_cleanup();
    return 0;
  }
  if (argc != 9) { fprintf(stderr, "usage: probe CASE CTL H1 TLSH1 TLSH2 H2C CA FILES | probe --version\n"); return 2; }
  P_CTL = atoi(argv[2]);
  P_H1 = atoi(argv[3]);
  P_TLSH1 = atoi(argv[4]);
  P_TLSH2 = atoi(argv[5]);
  P_H2C = atoi(argv[6]);
  CA = argv[7];
  FILES = argv[8];
  if (!strcmp(argv[1], "H")) c_h();
  else if (!strcmp(argv[1], "T")) c_t();
  else if (!strcmp(argv[1], "E")) c_e();
  else if (!strcmp(argv[1], "M")) c_m();
  else if (!strcmp(argv[1], "D")) c_d();
  else if (!strcmp(argv[1], "W")) c_w();
  else if (!strcmp(argv[1], "S")) c_s();
  else { fprintf(stderr, "probe: no case %s\n", argv[1]); return 2; }
  printf("case %s all done\n", argv[1]);
  curl_global_cleanup();
  return 0;
}
