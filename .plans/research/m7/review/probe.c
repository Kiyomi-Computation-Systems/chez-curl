/* Review probe: header injection through credentials and loaded cookie
 * lines, a caller's Authorization beside libcurl's credentials, AWS_SIGV4
 * over HTTPAUTH, and curl_url's answers for empty userinfo. One easy handle
 * per case, curl_easy_perform: what libcurl sends, not the engine's loop. */
#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *base;

static void esc(const char *s) {
  for (; *s; s++) {
    unsigned char c = (unsigned char)*s;
    if (c == '\r') printf("\\r");
    else if (c == '\n') printf("\\n");
    else if (c == '\t') printf("\\t");
    else if (c < 0x20 || c > 0x7e) printf("\\x%02x", c);
    else putchar(c);
  }
}

static size_t sink(char *p, size_t s, size_t n, void *u) { (void)p; (void)u; return s * n; }

static CURL *fresh(const char *path) {
  char url[256];
  CURL *h = curl_easy_init();
  snprintf(url, sizeof url, "%s%s", base, path);
  curl_easy_setopt(h, CURLOPT_URL, url);
  curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink);
  curl_easy_setopt(h, CURLOPT_PROXY, "");
  return h;
}

static void run(const char *name, CURL *h) {
  long status = 0;
  CURLcode rc;
  printf("case %s\n", name);
  fflush(stdout);
  rc = curl_easy_perform(h);
  curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
  printf("case %s done code=%d status=%ld\n", name, (int)rc, status);
  fflush(stdout);
}

static void cookie_case(const char *name, const char *line) {
  CURL *h = fresh("/c");
  struct curl_slist *list = NULL, *p;
  CURLcode rc;
  curl_easy_setopt(h, CURLOPT_COOKIEFILE, "");
  rc = curl_easy_setopt(h, CURLOPT_COOKIELIST, line);
  printf("case %s load rc=%d\n", name, (int)rc);
  curl_easy_getinfo(h, CURLINFO_COOKIELIST, &list);
  for (p = list; p; p = p->next) { printf("case %s listed \"", name); esc(p->data); printf("\"\n"); }
  if (!list) printf("case %s listed none\n", name);
  curl_slist_free_all(list);
  run(name, h);
  curl_easy_cleanup(h);
}

static void url_case(const char *u) {
  CURLU *url = curl_url();
  char *user = NULL, *pass = NULL;
  CURLUcode a, b;
  curl_url_set(url, CURLUPART_URL, u, 0);
  a = curl_url_get(url, CURLUPART_USER, &user, 0);
  b = curl_url_get(url, CURLUPART_PASSWORD, &pass, 0);
  printf("url %s user rc=%d %s%s%s password rc=%d %s%s%s\n", u, (int)a,
         user ? "\"" : "", user ? user : "(none)", user ? "\"" : "",
         (int)b, pass ? "\"" : "", pass ? pass : "(none)", pass ? "\"" : "");
  curl_free(user); curl_free(pass);
  curl_url_cleanup(url);
}

int main(int argc, char **argv) {
  CURL *h;
  struct curl_slist *hl;
  if (argc != 2) return 2;
  base = argv[1];
  curl_global_init(CURL_GLOBAL_ALL);
  printf("version %s\n", curl_version());

  /* 1. Loaded Netscape lines whose value holds CR, or 0x01. */
  cookie_case("cookie-cr", "127.0.0.1\tFALSE\t/\tFALSE\t0\tc\tv\rX-Injected: 1");
  cookie_case("cookie-ctl01", "127.0.0.1\tFALSE\t/\tFALSE\t0\tc\tv\x01w");
  /* 1b. An empty name field, seven fields by tab. */
  cookie_case("cookie-empty-name", "127.0.0.1\tFALSE\t/\tFALSE\t0\t\tv");

  /* 2. A Bearer token holding CRLF. */
  h = fresh("/b");
  curl_easy_setopt(h, CURLOPT_HTTPAUTH, (long)CURLAUTH_BEARER);
  curl_easy_setopt(h, CURLOPT_XOAUTH2_BEARER, "tok\r\nX-Injected: 1");
  run("bearer-crlf", h);
  curl_easy_cleanup(h);

  /* 3. A Digest user name holding CRLF. */
  h = fresh("/digest");
  curl_easy_setopt(h, CURLOPT_HTTPAUTH, (long)CURLAUTH_DIGEST);
  curl_easy_setopt(h, CURLOPT_USERNAME, "u\r\nX-Injected: 1");
  curl_easy_setopt(h, CURLOPT_PASSWORD, "p");
  run("digest-user-crlf", h);
  curl_easy_cleanup(h);

  /* 4. A caller's Authorization header beside Basic, Bearer and Digest. */
  h = fresh("/a");
  hl = curl_slist_append(NULL, "Authorization: Caller x");
  curl_easy_setopt(h, CURLOPT_HTTPHEADER, hl);
  curl_easy_setopt(h, CURLOPT_HTTPAUTH, (long)CURLAUTH_BASIC);
  curl_easy_setopt(h, CURLOPT_USERNAME, "u");
  curl_easy_setopt(h, CURLOPT_PASSWORD, "p");
  run("authz-beside-basic", h);
  curl_easy_cleanup(h);
  h = fresh("/a");
  curl_easy_setopt(h, CURLOPT_HTTPHEADER, hl);
  curl_easy_setopt(h, CURLOPT_HTTPAUTH, (long)CURLAUTH_BEARER);
  curl_easy_setopt(h, CURLOPT_XOAUTH2_BEARER, "tok");
  run("authz-beside-bearer", h);
  curl_easy_cleanup(h);
  h = fresh("/digest");
  curl_easy_setopt(h, CURLOPT_HTTPHEADER, hl);
  curl_easy_setopt(h, CURLOPT_HTTPAUTH, (long)CURLAUTH_DIGEST);
  curl_easy_setopt(h, CURLOPT_USERNAME, "u");
  curl_easy_setopt(h, CURLOPT_PASSWORD, "p");
  run("authz-beside-digest", h);
  curl_easy_cleanup(h);
  curl_slist_free_all(hl);

  /* 5. AWS_SIGV4 set after HTTPAUTH BASIC, as the hatch sets its options last. */
  h = fresh("/s");
  curl_easy_setopt(h, CURLOPT_HTTPAUTH, (long)CURLAUTH_BASIC);
  curl_easy_setopt(h, CURLOPT_USERNAME, "u");
  curl_easy_setopt(h, CURLOPT_PASSWORD, "p");
  curl_easy_setopt(h, CURLOPT_AWS_SIGV4, "aws:amz:us-east-1:s3");
  run("awssigv4-after-basic", h);
  curl_easy_cleanup(h);

  /* 6. curl_url's answers for empty userinfo. */
  url_case("http://@h/");
  url_case("http://:@h/");
  url_case("http://u@h/");
  url_case("http://:p@h/");
  url_case("http://h/");
  return 0;
}
