/* The M5 plan's redirect-URL probe (2026-10-27).

     probe URL METHOD
     probe --version

   One transfer of URL, METHOD GET or HEAD (NOBODY), with the options
   chez-curl's engine sets: the URL through CURLOPT_CURLU, the protocol pins
   and NOSIGNAL, FOLLOWLOCATION left off. It runs through curl_easy_perform,
   not the engine's multi interface. --version prints curl_version().
   Prints one line: the CURLcode, the status, CURLINFO_REDIRECT_URL,
   CURLINFO_EFFECTIVE_URL, the first Location header by curl_easy_header and
   how many there were, then that header resolved against URL by
   curl_url_set on URL's handle, as chez-curl's url-resolve does it, with
   flags 0 (r0) and with CURLU_URLENCODE (renc). A byte outside
   0x21 to 0x7e, and a backslash, prints as \xHH; a string over 120 bytes
   prints its first 40, then its length. */
#include <stdio.h>
#include <string.h>
#include <curl/curl.h>

static size_t sink(char *d, size_t s, size_t n, void *u) {
  (void)d; (void)u;
  return s * n;
}

static void show(const char *tag, const char *s) {
  size_t len, i, cut;
  printf(" %s=", tag);
  if (!s) { printf("NULL"); return; }
  len = strlen(s);
  cut = len > 120 ? 40 : len;
  for (i = 0; i < cut; i++) {
    unsigned char c = (unsigned char)s[i];
    if (c < 0x21 || c > 0x7e || c == '\\') printf("\\x%02x", c); else putchar(c);
  }
  if (cut < len) printf("...(len %zu)", len);
}

static void resolve(const char *tag, const char *base, const char *ref, unsigned int flags) {
  CURLU *u = curl_url();
  char *out = NULL;
  CURLUcode uc = curl_url_set(u, CURLUPART_URL, base, 0);
  if (!uc) uc = curl_url_set(u, CURLUPART_URL, ref, flags);
  if (!uc) uc = curl_url_get(u, CURLUPART_URL, &out, 0);
  if (uc) printf(" %s=uc%d", tag, (int)uc); else show(tag, out);
  curl_free(out);
  curl_url_cleanup(u);
}

int main(int argc, char **argv) {
  CURL *h;
  CURLU *url;
  CURLcode rc;
  long status = 0;
  char *redirect = NULL, *effective = NULL;
  struct curl_header *hd = NULL;
  CURLHcode hc;
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    puts(curl_version());
    return 0;
  }
  if (argc != 3) {
    fprintf(stderr, "usage: probe URL GET|HEAD\n");
    return 2;
  }
  curl_global_init(CURL_GLOBAL_ALL);
  h = curl_easy_init();
  url = curl_url();
  if (curl_url_set(url, CURLUPART_URL, argv[1], 0)) { fprintf(stderr, "bad URL\n"); return 2; }
  curl_easy_setopt(h, CURLOPT_PROTOCOLS_STR, "http,https");
  curl_easy_setopt(h, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
  curl_easy_setopt(h, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(h, CURLOPT_CURLU, url);
  curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink);
  curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, 5000L);
  curl_easy_setopt(h, CURLOPT_PROXY, "");
  if (!strcmp(argv[2], "HEAD")) curl_easy_setopt(h, CURLOPT_NOBODY, 1L);
  rc = curl_easy_perform(h);
  curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
  curl_easy_getinfo(h, CURLINFO_REDIRECT_URL, &redirect);
  curl_easy_getinfo(h, CURLINFO_EFFECTIVE_URL, &effective);
  printf("%s rc=%d status=%ld", argv[2], (int)rc, status);
  show("redirect", redirect);
  show("effective", effective);
  hc = curl_easy_header(h, "Location", 0, CURLH_HEADER, -1, &hd);
  if (hc) {
    printf(" location=hc%d", (int)hc);
  } else {
    show("location", hd->value);
    printf(" amount=%zu", hd->amount);
    resolve("r0", argv[1], hd->value, 0);
    resolve("renc", argv[1], hd->value, CURLU_URLENCODE);
  }
  putchar('\n');
  curl_easy_cleanup(h);
  curl_url_cleanup(url);
  curl_global_cleanup();
  return 0;
}
