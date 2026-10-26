/* The M4 plan's proxy measurement: what one transfer does with the proxy
   variables in its environment, and whether CURLOPT_PROXY "" or
   CURLOPT_NOPROXY "*" turns them off.

     proxy-env version
     proxy-env URL [proxy-empty | noproxy-star]

   The first prints the loaded libcurl's version. The second runs one GET of
   URL and prints one line: the CURLcode, the response code, and the body's
   first bytes. proxies.mjs's proxy answers 299 "proxy" to any request and
   403 to a CONNECT, and its origin answers 200 "origin", so the line says
   where the request went; the proxy's own log is the evidence that it got
   one. A setopt that fails prints "setopt CODE" and exits 1. */
#include <stdio.h>
#include <string.h>
#include <curl/curl.h>

static char body[64];
static size_t used;

static size_t sink(char *data, size_t size, size_t count, void *user) {
  size_t len = size * count;
  size_t room = sizeof body - 1 - used;
  size_t take = len < room ? len : room;
  (void)user;
  memcpy(body + used, data, take);
  used += take;
  body[used] = 0;
  return len;
}

int main(int argc, char **argv) {
  CURL *h;
  CURLcode rc;
  long status = 0;
  if (argc < 2 || argc > 3) {
    fprintf(stderr, "usage: proxy-env version | URL [proxy-empty|noproxy-star]\n");
    return 2;
  }
  if (curl_global_init(CURL_GLOBAL_ALL) != CURLE_OK) return 2;
  if (!strcmp(argv[1], "version")) {
    printf("%s\n", curl_version_info(CURLVERSION_NOW)->version);
    return 0;
  }
  h = curl_easy_init();
  if (!h) return 2;
  curl_easy_setopt(h, CURLOPT_URL, argv[1]);
  curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink);
  curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, 5000L);
  if (argc == 3) {
    if (!strcmp(argv[2], "proxy-empty")) rc = curl_easy_setopt(h, CURLOPT_PROXY, "");
    else if (!strcmp(argv[2], "noproxy-star")) rc = curl_easy_setopt(h, CURLOPT_NOPROXY, "*");
    else { fprintf(stderr, "proxy-env: no flag %s\n", argv[2]); return 2; }
    if (rc != CURLE_OK) { printf("setopt %d\n", (int)rc); return 1; }
  }
  rc = curl_easy_perform(h);
  curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
  printf("code %d status %ld body \"%s\"\n", (int)rc, status, body);
  curl_easy_cleanup(h);
  curl_global_cleanup();
  return 0;
}
