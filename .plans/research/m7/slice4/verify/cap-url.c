/* verify/cap-url.c: one cookie of name+value 4,003 bytes (a size a
   server's Set-Cookie can store: libcurl keeps name+value up to 4,096),
   loaded through CURLOPT_COOKIELIST, then one GET whose path is P bytes,
   to cap-server.mjs, on a bare easy handle. Usage: cap-url PORT P... */
#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  curl_global_init(CURL_GLOBAL_DEFAULT);
  printf("%s\n", curl_version());
  char line[4200];
  int k = sprintf(line, "127.0.0.1\tFALSE\t/\tFALSE\t0\tnm\t");
  memset(line + k, 'v', 4000);
  line[k + 4000] = 0;
  for (int i = 2; i < argc; i++) {
    long p = atol(argv[i]);
    char *url = malloc(p + 64);
    int u = sprintf(url, "http://127.0.0.1:%s/", argv[1]);
    memset(url + u, 'p', p);
    url[u + p] = 0;
    CURL *h = curl_easy_init();
    curl_easy_setopt(h, CURLOPT_URL, url);
    curl_easy_setopt(h, CURLOPT_COOKIEFILE, "");
    CURLcode set = curl_easy_setopt(h, CURLOPT_COOKIELIST, line);
    curl_easy_setopt(h, CURLOPT_TIMEOUT, 3L);
    CURLcode rc = curl_easy_perform(h);
    printf("path=%ld cookielist=%d perform=%d (%s)\n", p, (int)set, (int)rc, curl_easy_strerror(rc));
    fflush(stdout);
    curl_easy_cleanup(h);
    free(url);
  }
  return 0;
}
