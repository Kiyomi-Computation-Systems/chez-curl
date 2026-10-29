/* M5 slice 2's localhost probe (2026-10-28; the M5 plan, section 5.1):
   whether a host name other than 127.0.0.1 reaches the test origin, which
   listens on 127.0.0.1 alone, for a redirect's change of host that a live
   test can make.

     localhost URL...

   One GET of each URL, with the options the engine sets that bear on a
   connect: the protocol pins, NOSIGNAL, PROXY "", a 5 s bound. Prints the
   CURLcode, the status, CURLINFO_PRIMARY_IP and the connect time in
   microseconds. */
#include <stdio.h>
#include <curl/curl.h>

static size_t sink(char *d, size_t s, size_t n, void *u) {
  (void)d; (void)u;
  return s * n;
}

int main(int argc, char **argv) {
  int i;
  curl_global_init(CURL_GLOBAL_ALL);
  for (i = 1; i < argc; i++) {
    CURL *h = curl_easy_init();
    CURLcode rc;
    long status = 0;
    char *ip = NULL;
    curl_off_t connect = -1;
    curl_easy_setopt(h, CURLOPT_URL, argv[i]);
    curl_easy_setopt(h, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(h, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(h, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(h, CURLOPT_PROXY, "");
    curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, 5000L);
    curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink);
    rc = curl_easy_perform(h);
    curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_getinfo(h, CURLINFO_PRIMARY_IP, &ip);
    curl_easy_getinfo(h, CURLINFO_CONNECT_TIME_T, &connect);
    printf("%s rc=%d status=%ld ip=%s connect-us=%ld\n", argv[i], (int)rc, status,
           ip && *ip ? ip : "none", (long)connect);
    curl_easy_cleanup(h);
  }
  curl_global_cleanup();
  return 0;
}
