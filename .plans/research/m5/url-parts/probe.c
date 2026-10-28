/* M5 slice 1's URL-parts probe (2026-10-27): what curl_url gives back for
   the two calls slice 1 adds to (curl), curl-url-append-query and
   curl-url-part (the M5 plan, section 4.1).

     probe
     probe --version

   Two tables, no transfer:

   - append: each base URL set on a fresh handle, then each query part
     appended by curl_url_set(CURLUPART_QUERY, part, CURLU_APPENDQUERY), no
     CURLU_URLENCODE; prints the set's code, then the URL and the query read
     back with flags 0.
   - set: each base URL set on a fresh handle, then its query part set by
     curl_url_set(CURLUPART_QUERY, part, 0), no flags: does a plain set
     change a part as an append does?
   - parts: each URL set on a fresh handle with flags 0, then every part
     read back with flags 0, the port also with CURLU_DEFAULT_PORT (port).
     Each answer is the string, or ucN, the CURLUcode that refused it.

   A byte outside 0x21 to 0x7e, and a backslash, prints as \xHH, so a raw
   byte above 0x7F shows as itself, not as UTF-8 or Latin-1. --version
   prints curl_version(). */
#include <stdio.h>
#include <string.h>
#include <curl/curl.h>

static void show(const char *s) {
  for (; *s; s++) {
    unsigned char c = (unsigned char)*s;
    if (c < 0x21 || c > 0x7e || c == '\\') printf("\\x%02x", c); else putchar(c);
  }
}

static void get(CURLU *u, const char *tag, CURLUPart part, unsigned int flags) {
  char *out = NULL;
  CURLUcode uc = curl_url_get(u, part, &out, flags);
  printf(" %s=", tag);
  if (uc) printf("uc%d", (int)uc); else show(out);
  curl_free(out);
}

static void append(const char *base, const char *part) {
  CURLU *u = curl_url();
  CURLUcode uc = curl_url_set(u, CURLUPART_URL, base, 0);
  printf("append base="); show(base); printf(" part=\""); show(part); printf("\"");
  if (uc) { printf(" base-uc%d\n", (int)uc); curl_url_cleanup(u); return; }
  uc = curl_url_set(u, CURLUPART_QUERY, part, CURLU_APPENDQUERY);
  printf(" set=uc%d", (int)uc);
  get(u, "url", CURLUPART_URL, 0);
  get(u, "query", CURLUPART_QUERY, 0);
  putchar('\n');
  curl_url_cleanup(u);
}

static void set(const char *base, const char *part) {
  CURLU *u = curl_url();
  CURLUcode uc = curl_url_set(u, CURLUPART_URL, base, 0);
  printf("set base="); show(base); printf(" part=\""); show(part); printf("\"");
  if (uc) { printf(" base-uc%d\n", (int)uc); curl_url_cleanup(u); return; }
  uc = curl_url_set(u, CURLUPART_QUERY, part, 0);
  printf(" set=uc%d", (int)uc);
  get(u, "url", CURLUPART_URL, 0);
  get(u, "query", CURLUPART_QUERY, 0);
  putchar('\n');
  curl_url_cleanup(u);
}

static void parts(const char *url) {
  CURLU *u = curl_url();
  CURLUcode uc = curl_url_set(u, CURLUPART_URL, url, 0);
  printf("parts in="); show(url);
  if (uc) { printf(" set-uc%d\n", (int)uc); curl_url_cleanup(u); return; }
  get(u, "url", CURLUPART_URL, 0);
  get(u, "scheme", CURLUPART_SCHEME, 0);
  get(u, "user", CURLUPART_USER, 0);
  get(u, "password", CURLUPART_PASSWORD, 0);
  get(u, "host", CURLUPART_HOST, 0);
  get(u, "port", CURLUPART_PORT, CURLU_DEFAULT_PORT);
  get(u, "port0", CURLUPART_PORT, 0);
  get(u, "path", CURLUPART_PATH, 0);
  get(u, "query", CURLUPART_QUERY, 0);
  get(u, "fragment", CURLUPART_FRAGMENT, 0);
  putchar('\n');
  curl_url_cleanup(u);
}

static const char *bases[] = {
  "http://h.example/p",
  "http://h.example/p?a=1",
  "http://h.example/p?",
  "http://h.example/p?a=1&",
  "http://h.example/p#frag",
  "http://h.example/p?a=1#frag",
  "http://h.example/p?#frag",
  "http://h.example",
};

/* What chez-curl's form encoding makes, and its edges: %XX, +, & and =
   (the plan, section 4.1), a bare name, an empty part, and two it never
   makes, a space and raw UTF-8. */
static const char *appended[] = {
  "b=2",
  "n=a%20b+c&m=%3D%26%2B",
  "x",
  "",
  "e=%C3%A9",
  "s=a b",
  "u=\xc3\xa9",
};

static const char *urls[] = {
  /* The parts, ASCII. */
  "http://h.example/p",
  "https://u:pw@H.Example:8443/p/q?a=1&b=2#frag",
  "HTTP://h.example/p",
  "http://h.example",
  "http://h.example:80/p",
  "https://h.example/",
  "http://h.example:080/",
  "http://h.example:0/",
  "http://h.example:65535/",
  "http://[::1]:8080/p",
  "http://u@h.example/",
  "http://:pw@h.example/",
  "http://u:@h.example/",
  "http://h.example/p?",
  "http://h.example/p#",
  "http://h.example/p?#",
  /* %XX in upper and in lower case, in the path, the query and the
     fragment of a whole URL: does a parse change its case? */
  "http://h.example/p%3D%3d?x=%3D&y=%3d#f%3D%3d",
  /* A raw Latin-1 byte, 0xE9, in each part. */
  "http://us\xe9r:pw@h.example/",
  "http://u:p\xe9ss@h.example/",
  "http://caf\xe9.example/",
  "http://h.example/p\xe9",
  "http://h.example/p?q=\xe9",
  "http://h.example/p#f\xe9",
  /* Raw UTF-8, U+00E9, in each part: what a Scheme string sends. */
  "http://us\xc3\xa9r:pw@h.example/",
  "http://u:p\xc3\xa9ss@h.example/",
  "http://caf\xc3\xa9.example/",
  "http://h.example/p\xc3\xa9",
  "http://h.example/p?q=\xc3\xa9",
  "http://h.example/p#f\xc3\xa9",
  /* %E9 in each part: does curl decode it? */
  "http://us%E9r:pw@h.example/",
  "http://u:p%E9ss@h.example/",
  "http://caf%E9.example/",
  "http://h.example/p%E9",
  "http://h.example/p?q=%E9",
  "http://h.example/p#f%E9",
  /* More in a host: lower case, UTF-8 encoded, a lone lead byte, ASCII,
     NUL, a slash, a dot. */
  "http://caf%e9.example/",
  "http://caf%C3%A9.example/",
  "http://caf%C3.example/",
  "http://%41.example/",
  "http://a%00b.example/",
  "http://a%2Fb.example/",
  "http://a%2Eb.example/",
  /* Raw bytes that are not UTF-8 in a host: a lone lead, 0xFF. */
  "http://caf\xc3.example/",
  "http://caf\xff.example/",
};

int main(int argc, char **argv) {
  size_t i, j;
  if (argc == 2 && strcmp(argv[1], "--version") == 0) {
    printf("%s\n", curl_version());
    return 0;
  }
  printf("%s\n", curl_version());
  for (i = 0; i < sizeof bases / sizeof *bases; i++)
    for (j = 0; j < sizeof appended / sizeof *appended; j++)
      append(bases[i], appended[j]);
  set("http://h.example/p", "n=%3D%26&m=%3d");
  set("http://h.example/p?a=1#frag", "n=%3D%26&m=%3d");
  for (i = 0; i < sizeof urls / sizeof *urls; i++)
    parts(urls[i]);
  printf("-- %zu appends, 2 sets, %zu urls\n",
         (sizeof bases / sizeof *bases) * (sizeof appended / sizeof *appended),
         sizeof urls / sizeof *urls);
  return 0;
}
