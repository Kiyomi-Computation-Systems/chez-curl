/* mac/backend.c: the TLS backend a libcurl names, before and after
   curl_global_init, with CURL_SSL_BACKEND as the process has it. A MultiSSL
   libcurl's ssl_version names every backend, those not in use in
   parentheses; before the init it names its first as the one in use
   (ADR-0024). Prints four lines; exit 0, or 1 when the init fails. */
#include <stdio.h>
#include <stdlib.h>
#include <curl/curl.h>

static const char *text(const char *s) { return s ? s : "(null)"; }

int main(void) {
  const char *env = getenv("CURL_SSL_BACKEND");
  curl_version_info_data *before = curl_version_info(CURLVERSION_NOW);
  printf("c: CURL_SSL_BACKEND %s\n", env ? env : "(unset)");
  printf("c: libcurl %s, before the init: %s\n", text(before->version), text(before->ssl_version));
  CURLcode code = curl_global_init(CURL_GLOBAL_DEFAULT);
  curl_version_info_data *after = curl_version_info(CURLVERSION_NOW);
  printf("c: curl_global_init %d\n", (int)code);
  printf("c: after the init: %s\n", text(after->ssl_version));
  curl_global_cleanup();
  return code == CURLE_OK ? 0 : 1;
}
