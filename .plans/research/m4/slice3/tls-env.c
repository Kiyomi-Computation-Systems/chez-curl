/* M4 slice 3's measurements (the M4 plan, section 6.1): what one transfer's
   TLS reads from the environment, the CA file's PKCS#11 spellings, and an
   https:// proxy's verification.

     tls-env version
     tls-env URL [STEP]...

   The first runs curl_global_init and prints the loaded libcurl's version,
   its TLS library, and whether it has CURL_VERSION_HTTPS_PROXY. The second
   applies each STEP in turn: an environment step either side of
   curl_global_init, as its prefix says, and the request's settings once
   the easy handle exists. Then one GET of URL, and one line: the CURLcode,
   the response code, the body's first bytes, the error buffer, and the TLS
   library curl_version_info names after the init.

     before:NAME=VALUE   setenv before curl_global_init
     after:NAME=VALUE    setenv after it, before the easy handle
     unset-after:NAME    unsetenv after it, before the easy handle
     ca-file:PATH        CAINFO PATH and CAPATH NULL: chez-curl's ca-file
     no-verify           SSL_VERIFYPEER 0, SSL_VERIFYHOST 0: its verify #f
     proxy-ca:PATH       PROXY_CAINFO PATH
     proxy-no-verify     PROXY_SSL_VERIFYPEER 0, PROXY_SSL_VERIFYHOST 0

   Without no-verify, the transfer sets SSL_VERIFYPEER 1 and SSL_VERIFYHOST
   2, as every chez-curl transfer does (ADR-0018, decision 3). It sets no
   other TLS option, so each proxy option is libcurl's default unless a step
   sets it. CAPATH NULL may answer CURLE_NOT_BUILT_IN, which chez-curl takes;
   any other failing setopt prints "setopt NAME CODE" and exits 1. */
#include <stdio.h>
#include <stdlib.h>
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

/* Prints TEXT between double quotes, each " and \ and control byte as \xHH. */
static void quoted(const char *text) {
  const unsigned char *p = (const unsigned char *)text;
  putchar('"');
  for (; *p; p++) {
    if (*p == '"' || *p == '\\' || *p < 0x20 || *p == 0x7f) printf("\\x%02x", *p);
    else putchar(*p);
  }
  putchar('"');
}

static int prefixed(const char *arg, const char *prefix) {
  return strncmp(arg, prefix, strlen(prefix)) == 0;
}

/* setenv from NAME=VALUE; exits 2 on a malformed step. */
static void put(const char *assignment) {
  const char *eq = strchr(assignment, '=');
  char name[128];
  if (!eq || eq == assignment || (size_t)(eq - assignment) >= sizeof name) {
    fprintf(stderr, "tls-env: no NAME=VALUE in %s\n", assignment);
    exit(2);
  }
  memcpy(name, assignment, eq - assignment);
  name[eq - assignment] = 0;
  if (setenv(name, eq + 1, 1) != 0) { perror("setenv"); exit(2); }
}

static void check(const char *name, CURLcode rc, int not_built_in_ok) {
  if (rc == CURLE_OK || (not_built_in_ok && rc == CURLE_NOT_BUILT_IN)) return;
  printf("setopt %s %d\n", name, (int)rc);
  exit(1);
}

int main(int argc, char **argv) {
  CURL *h;
  CURLcode rc;
  long status = 0;
  int i, verify = 1;
  char error[CURL_ERROR_SIZE];
  const curl_version_info_data *v;
  if (argc < 2) {
    fprintf(stderr, "usage: tls-env version | URL [STEP]...\n");
    return 2;
  }
  for (i = 2; i < argc; i++)
    if (prefixed(argv[i], "before:")) put(argv[i] + strlen("before:"));
  if (curl_global_init(CURL_GLOBAL_ALL) != CURLE_OK) return 2;
  v = curl_version_info(CURLVERSION_NOW);
  if (!strcmp(argv[1], "version")) {
    printf("%s, %s, https-proxy %s\n", v->version, v->ssl_version ? v->ssl_version : "none",
           (v->features & CURL_VERSION_HTTPS_PROXY) ? "yes" : "no");
    return 0;
  }
  for (i = 2; i < argc; i++) {
    if (prefixed(argv[i], "after:")) put(argv[i] + strlen("after:"));
    else if (prefixed(argv[i], "unset-after:")) unsetenv(argv[i] + strlen("unset-after:"));
  }
  h = curl_easy_init();
  if (!h) return 2;
  error[0] = 0;
  check("URL", curl_easy_setopt(h, CURLOPT_URL, argv[1]), 0);
  check("WRITEFUNCTION", curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink), 0);
  check("ERRORBUFFER", curl_easy_setopt(h, CURLOPT_ERRORBUFFER, error), 0);
  check("TIMEOUT_MS", curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, 10000L), 0);
  for (i = 2; i < argc; i++) {
    const char *a = argv[i];
    if (prefixed(a, "before:") || prefixed(a, "after:") || prefixed(a, "unset-after:")) continue;
    if (prefixed(a, "ca-file:")) {
      check("CAINFO", curl_easy_setopt(h, CURLOPT_CAINFO, a + strlen("ca-file:")), 0);
      check("CAPATH", curl_easy_setopt(h, CURLOPT_CAPATH, (char *)NULL), 1);
    } else if (!strcmp(a, "no-verify")) {
      verify = 0;
    } else if (prefixed(a, "proxy-ca:")) {
      check("PROXY_CAINFO", curl_easy_setopt(h, CURLOPT_PROXY_CAINFO, a + strlen("proxy-ca:")), 0);
    } else if (!strcmp(a, "proxy-no-verify")) {
      check("PROXY_SSL_VERIFYPEER", curl_easy_setopt(h, CURLOPT_PROXY_SSL_VERIFYPEER, 0L), 0);
      check("PROXY_SSL_VERIFYHOST", curl_easy_setopt(h, CURLOPT_PROXY_SSL_VERIFYHOST, 0L), 0);
    } else {
      fprintf(stderr, "tls-env: no step %s\n", a);
      return 2;
    }
  }
  check("SSL_VERIFYPEER", curl_easy_setopt(h, CURLOPT_SSL_VERIFYPEER, verify ? 1L : 0L), 0);
  check("SSL_VERIFYHOST", curl_easy_setopt(h, CURLOPT_SSL_VERIFYHOST, verify ? 2L : 0L), 0);
  rc = curl_easy_perform(h);
  curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
  printf("code %d status %ld body ", (int)rc, status);
  quoted(body);
  printf(" error ");
  quoted(error);
  printf(" ssl ");
  quoted(v->ssl_version ? v->ssl_version : "none");
  printf("\n");
  curl_easy_cleanup(h);
  curl_global_cleanup();
  return 0;
}
