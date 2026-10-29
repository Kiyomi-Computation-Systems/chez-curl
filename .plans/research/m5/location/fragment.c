/* M5 slice 2's fragment probe (2026-10-28; the M5 plan, section 5.1).

     fragment
     fragment --version

   What libcurl's URL API makes of a fragment, given as a header's bytes,
   for curl-url-with-fragment (the M5 plan, section 3.4). For each base and
   each fragment F, four answers, each the URL and its fragment part as
   curl_url_get gives them with no flags:

     part0  curl_url_set(CURLUPART_FRAGMENT, F, 0) on the base's handle;
     penc   the same with CURLU_URLENCODE;
     whole  the base, its fragment cut, then "#" F, parsed whole, flags 0;
     ref    "#" F resolved against the base by curl_url_set(CURLUPART_URL),
            as chez-curl's url-resolve does it.

   Then each base's fragment cleared, by a NULL part. A byte outside 0x21
   to 0x7e, and a backslash, prints as \xHH; a refusal prints as ucN. */
#include <stdio.h>
#include <string.h>
#include <curl/curl.h>

static void show(const char *tag, const char *s) {
  size_t i;
  printf(" %s=", tag);
  if (!s) { printf("NULL"); return; }
  for (i = 0; s[i]; i++) {
    unsigned char c = (unsigned char)s[i];
    if (c < 0x21 || c > 0x7e || c == '\\') printf("\\x%02x", c); else putchar(c);
  }
}

/* The URL and its fragment, as curl_url_get gives them; or the code. */
static void answer(const char *tag, CURLU *u, CURLUcode uc) {
  char *url = NULL, *frag = NULL;
  CURLUcode fc;
  if (uc) { printf(" %s=uc%d", tag, (int)uc); return; }
  uc = curl_url_get(u, CURLUPART_URL, &url, 0);
  if (uc) { printf(" %s=get-uc%d", tag, (int)uc); return; }
  show(tag, url);
  fc = curl_url_get(u, CURLUPART_FRAGMENT, &frag, 0);
  if (fc) printf(" %s.frag=uc%d", tag, (int)fc); else show("frag", frag);
  curl_free(url);
  curl_free(frag);
}

static CURLU *parsed(const char *url, CURLUcode *uc) {
  CURLU *u = curl_url();
  *uc = curl_url_set(u, CURLUPART_URL, url, 0);
  return u;
}

static void one(const char *label, const char *base, const char *stem, const char *f) {
  char buf[512];
  CURLUcode uc;
  CURLU *u;
  printf("%s base=%s", label, base);
  show("f", f);
  u = parsed(base, &uc);
  if (!uc) uc = curl_url_set(u, CURLUPART_FRAGMENT, f, 0);
  answer("part0", u, uc);
  curl_url_cleanup(u);
  u = parsed(base, &uc);
  if (!uc) uc = curl_url_set(u, CURLUPART_FRAGMENT, f, CURLU_URLENCODE);
  answer("penc", u, uc);
  curl_url_cleanup(u);
  snprintf(buf, sizeof buf, "%s#%s", stem, f);
  u = parsed(buf, &uc);
  answer("whole", u, uc);
  curl_url_cleanup(u);
  snprintf(buf, sizeof buf, "#%s", f);
  u = parsed(base, &uc);
  if (!uc) uc = curl_url_set(u, CURLUPART_URL, buf, 0);
  answer("ref", u, uc);
  curl_url_cleanup(u);
  putchar('\n');
}

int main(int argc, char **argv) {
  static const char *bases[][2] = {
    {"http://h.example/a/b?q=1", "http://h.example/a/b?q=1"},
    {"http://h.example/a/b?q=1#old", "http://h.example/a/b?q=1"},
    {"http://h.example/a/b#old%e9", "http://h.example/a/b"},
  };
  static const char *frags[][2] = {
    {"plain", "only"},
    {"empty", ""},
    {"space", "a b"},
    {"blank", "   "},
    {"tab", "\t"},
    {"cr", "\r"},
    {"latin1", "caf\xe9"},
    {"utf8", "caf\xc3\xa9"},
    {"bom", "\xef\xbb\xbf" "bom"},
    {"pct-lower", "%e9x"},
    {"pct-upper", "%E9x"},
    {"pct-mixed", "%c3%A9"},
    {"bad-pct", "%zz"},
    {"lone-pct", "%"},
    {"hash", "a#b"},
    {"ctl", "x\x01y"},
    {"del", "x\x7fy"},
    {"delims", "\"<>`{}|^"},
    {"reserved", "a?b/c:d@e!$&'()*+,;="},
    {"backslash", "a\\b"},
  };
  size_t b, f;
  if (argc == 2 && !strcmp(argv[1], "--version")) {
    puts(curl_version());
    return 0;
  }
  curl_global_init(CURL_GLOBAL_ALL);
  for (b = 0; b < sizeof bases / sizeof bases[0]; b++)
    for (f = 0; f < sizeof frags / sizeof frags[0]; f++)
      one(frags[f][0], bases[b][0], bases[b][1], frags[f][1]);
  for (b = 0; b < sizeof bases / sizeof bases[0]; b++) {
    CURLUcode uc;
    CURLU *u = parsed(bases[b][0], &uc);
    printf("clear base=%s", bases[b][0]);
    if (!uc) uc = curl_url_set(u, CURLUPART_FRAGMENT, NULL, 0);
    answer("cleared", u, uc);
    putchar('\n');
    curl_url_cleanup(u);
  }
  printf("-- %zu lines\n", sizeof bases / sizeof bases[0] * (sizeof frags / sizeof frags[0] + 1));
  curl_global_cleanup();
  return 0;
}
