/* Redirect probe: METHOD, with BODY by POSTFIELDSIZE_LARGE then
   COPYPOSTFIELDS (or none for "nobody", or an empty body for "empty", passed
   as NULL when the last argument is "null"), and CUSTOMREQUEST METHOD unless
   METHOD is POST, to http://127.0.0.1:PORT/rCODE with FOLLOWLOCATION 1.
   Prints the CURLcode and what /echo saw on the last request. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <curl/curl.h>
static char out[512];
static size_t used;
static size_t sink(char *d, size_t s, size_t n, void *u) {
  size_t len = s * n, room = sizeof out - 1 - used, take = len < room ? len : room;
  (void)u;
  memcpy(out + used, d, take);
  used += take;
  out[used] = 0;
  return len;
}
int main(int argc, char **argv) {
  char url[128];
  CURL *h;
  CURLcode rc;
  long status = 0;
  int null_ptr = argc == 6 && !strcmp(argv[5], "null");
  if (argc < 5 || argc > 6) {
    fprintf(stderr, "usage: probe PORT METHOD CODE BODY|nobody|empty [null]\n");
    return 2;
  }
  snprintf(url, sizeof url, "http://127.0.0.1:%s/r%s", argv[1], argv[3]);
  curl_global_init(CURL_GLOBAL_ALL);
  h = curl_easy_init();
  curl_easy_setopt(h, CURLOPT_URL, url);
  curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink);
  curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, 5000L);
  if (strcmp(argv[4], "nobody")) {
    const char *body = strcmp(argv[4], "empty") ? argv[4] : "";
    curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)strlen(body));
    curl_easy_setopt(h, CURLOPT_COPYPOSTFIELDS, null_ptr ? NULL : body);
  }
  if (strcmp(argv[2], "POST")) curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, argv[2]);
  rc = curl_easy_perform(h);
  curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
  printf("%s via %s, body %s%s -> code %d, status %ld, last request: %s\n", argv[2], argv[3],
         argv[4], null_ptr ? " (NULL)" : "", (int)rc, status, out);
  curl_easy_cleanup(h);
  curl_global_cleanup();
  return 0;
}
