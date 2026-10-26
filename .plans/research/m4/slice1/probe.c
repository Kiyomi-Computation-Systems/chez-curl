/* M4 slice 1's measurement probe (the M4 plan, section 4.1). One transfer per
   run, through curl_easy_perform, printing one line.

     probe version
     probe body PORT PATH METHOD SIZE|none [HEADER ...]
     probe time URL CONNECT-MS TIMEOUT-MS CAINFO|-

   body: METHOD to http://127.0.0.1:PORT/PATH. A SIZE sets the body as the
   request will: POSTFIELDSIZE_LARGE with SIZE, then COPYPOSTFIELDS with SIZE
   bytes, byte i being (i * 31 + 7) & 255, or NULL for SIZE 0. none sets no
   body option. A METHOD but POST is CUSTOMREQUEST. Each HEADER goes into
   HTTPHEADER as given. It prints the code, the status, the FNV-1a of the
   bytes it sent, and what capture.mjs answered.

   time: a GET of URL, with CONNECTTIMEOUT_MS and TIMEOUT_MS when not 0, and
   CAINFO, with CAPATH cleared, when not -. It prints the code, the status,
   its own wall time in ms, the six *_TIME_T infos, each a curl_off_t of
   microseconds, then REQUEST_SIZE and HEADER_SIZE, each a long, each
   marked when its getinfo refused. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <curl/curl.h>

static char out[65536];
static size_t used;

static size_t sink(char *data, size_t size, size_t n, void *unused) {
  size_t len = size * n, room = sizeof out - 1 - used, take = len < room ? len : room;
  (void)unused;
  memcpy(out + used, data, take);
  used += take;
  out[used] = 0;
  return len;
}

static unsigned long fnv1a(const unsigned char *p, size_t n) {
  unsigned long h = 2166136261UL;
  size_t i;
  for (i = 0; i < n; i++) h = ((h ^ p[i]) * 16777619UL) & 0xffffffffUL;
  return h;
}

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static int body(int argc, char **argv) {
  char url[256];
  CURL *h;
  CURLcode rc;
  long status = 0;
  struct curl_slist *list = NULL;
  unsigned char *bytes = NULL;
  size_t size = 0;
  int has_body = strcmp(argv[5], "none") != 0;
  int i;
  snprintf(url, sizeof url, "http://127.0.0.1:%s/%s", argv[2], argv[3]);
  h = curl_easy_init();
  curl_easy_setopt(h, CURLOPT_URL, url);
  curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink);
  curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, 20000L);
  if (has_body) {
    size_t k;
    size = (size_t)strtoul(argv[5], NULL, 10);
    bytes = malloc(size ? size : 1);
    for (k = 0; k < size; k++) bytes[k] = (unsigned char)((k * 31 + 7) & 255);
    curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)size);
    curl_easy_setopt(h, CURLOPT_COPYPOSTFIELDS, size ? (char *)bytes : NULL);
  }
  if (strcmp(argv[4], "POST")) curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, argv[4]);
  for (i = 6; i < argc; i++) list = curl_slist_append(list, argv[i]);
  if (list) curl_easy_setopt(h, CURLOPT_HTTPHEADER, list);
  rc = curl_easy_perform(h);
  curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
  printf("code %d status %ld sent %s fnv %08lx -> %s\n", (int)rc, status,
         has_body ? argv[5] : "none", has_body ? fnv1a(bytes, size) : 0UL, out);
  curl_easy_cleanup(h);
  curl_slist_free_all(list);
  free(bytes);
  return 0;
}

static int timed(char **argv) {
  static const struct { const char *name; CURLINFO info; } infos[] = {
    { "namelookup", CURLINFO_NAMELOOKUP_TIME_T },
    { "connect", CURLINFO_CONNECT_TIME_T },
    { "appconnect", CURLINFO_APPCONNECT_TIME_T },
    { "pretransfer", CURLINFO_PRETRANSFER_TIME_T },
    { "starttransfer", CURLINFO_STARTTRANSFER_TIME_T },
    { "total", CURLINFO_TOTAL_TIME_T },
  };
  CURL *h = curl_easy_init();
  CURLcode rc;
  long status = 0, connect_ms = atol(argv[3]), timeout_ms = atol(argv[4]);
  double start;
  size_t k;
  curl_easy_setopt(h, CURLOPT_URL, argv[2]);
  curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink);
  if (connect_ms) curl_easy_setopt(h, CURLOPT_CONNECTTIMEOUT_MS, connect_ms);
  if (timeout_ms) curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, timeout_ms);
  if (strcmp(argv[5], "-")) {
    curl_easy_setopt(h, CURLOPT_CAINFO, argv[5]);
    curl_easy_setopt(h, CURLOPT_CAPATH, NULL);
  }
  start = now_ms();
  rc = curl_easy_perform(h);
  printf("code %d", (int)rc);
  curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
  printf(" status %ld wall %.0f ms", status, now_ms() - start);
  for (k = 0; k < sizeof infos / sizeof infos[0]; k++) {
    curl_off_t v = -1;
    CURLcode got = curl_easy_getinfo(h, infos[k].info, &v);
    printf(" %s %" CURL_FORMAT_CURL_OFF_T "%s", infos[k].name, v, got ? "(refused)" : "");
  }
  {
    long request = -1, header = -1;
    CURLcode r1 = curl_easy_getinfo(h, CURLINFO_REQUEST_SIZE, &request);
    CURLcode r2 = curl_easy_getinfo(h, CURLINFO_HEADER_SIZE, &header);
    printf(" request-size %ld%s header-size %ld%s", request, r1 ? "(refused)" : "", header, r2 ? "(refused)" : "");
  }
  printf("\n");
  curl_easy_cleanup(h);
  return 0;
}

int main(int argc, char **argv) {
  int status = 2;
  curl_global_init(CURL_GLOBAL_ALL);
  if (argc == 2 && !strcmp(argv[1], "version")) {
    printf("%s\n", curl_version_info(CURLVERSION_NOW)->version);
    status = 0;
  } else if (argc >= 6 && !strcmp(argv[1], "body")) {
    status = body(argc, argv);
  } else if (argc == 6 && !strcmp(argv[1], "time")) {
    status = timed(argv);
  } else {
    fprintf(stderr, "usage: probe version | body PORT PATH METHOD SIZE|none [HEADER ...]"
                    " | time URL CONNECT-MS TIMEOUT-MS CAINFO|-\n");
  }
  curl_global_cleanup();
  return status;
}
