/* Does curl_url_get hand back bytes that are not UTF-8? A Latin-1 byte in
   each part of a reference, resolved against a base, read back whole and by
   part. Prints \xHH for a byte outside 0x21..0x7e. */
#include <stdio.h>
#include <string.h>
#include <curl/curl.h>
static void show(const char *s) {
  for (; *s; s++) { unsigned char c = (unsigned char)*s;
    if (c < 0x21 || c > 0x7e || c == '\\') printf("\\x%02x", c); else putchar(c); }
}
static void one(const char *ref) {
  CURLU *u = curl_url(); char *out = NULL; CURLUcode uc;
  uc = curl_url_set(u, CURLUPART_URL, "http://base.example/a/b", 0);
  if (!uc) uc = curl_url_set(u, CURLUPART_URL, ref, 0);
  printf("ref="); show(ref);
  if (uc) { printf(" uc%d\n", (int)uc); curl_url_cleanup(u); return; }
  curl_url_get(u, CURLUPART_URL, &out, 0); printf(" url="); show(out); curl_free(out);
  const CURLUPart parts[] = {CURLUPART_USER, CURLUPART_PASSWORD, CURLUPART_HOST, CURLUPART_PATH, CURLUPART_QUERY, CURLUPART_FRAGMENT};
  const char *names[] = {"user","password","host","path","query","fragment"};
  for (int i = 0; i < 6; i++) { out = NULL; uc = curl_url_get(u, parts[i], &out, 0);
    printf(" %s=", names[i]); if (uc) printf("uc%d", (int)uc); else show(out); curl_free(out); }
  putchar('\n'); curl_url_cleanup(u);
}
int main(void) {
  printf("%s\n", curl_version());
  one("http://caf\xe9.invalid/x");
  one("http://caf\xe8.invalid/x");
  one("http://us\xe9r:p\xe9ss@h.invalid/x");
  one("/p\xe9?q=\xe9#f\xe9");
  one("#only");
  one("http://H.EXAMPLE:80/x");
  return 0;
}
