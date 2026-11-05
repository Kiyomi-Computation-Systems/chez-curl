/* verify/cap.c: one cookie loaded through CURLOPT_COOKIELIST, its value N
   bytes, then one GET to cap-server.mjs, on a bare easy handle: no Chez, no
   share, no engine. Prints the code. Usage: cap PORT N... */
#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  curl_global_init(CURL_GLOBAL_DEFAULT);
  printf("%s\n", curl_version());
  for (int i = 2; i < argc; i++) {
    long n = atol(argv[i]);
    char *line = malloc(n + 64);
    int k = sprintf(line, "127.0.0.1\tFALSE\t/\tFALSE\t0\tnm\t");
    memset(line + k, 'v', n);
    line[k + n] = 0;
    char url[128];
    snprintf(url, sizeof url, "http://127.0.0.1:%s/?n=%ld", argv[1], n);
    CURL *h = curl_easy_init();
    curl_easy_setopt(h, CURLOPT_URL, url);
    curl_easy_setopt(h, CURLOPT_COOKIEFILE, "");
    CURLcode set = curl_easy_setopt(h, CURLOPT_COOKIELIST, line);
    curl_easy_setopt(h, CURLOPT_TIMEOUT, 3L);
    CURLcode rc = curl_easy_perform(h);
    printf("value=%ld cookielist=%d perform=%d (%s)\n", n, (int)set, (int)rc, curl_easy_strerror(rc));
    fflush(stdout);
    curl_easy_cleanup(h);
    free(line);
  }
  return 0;
}
