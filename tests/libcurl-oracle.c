/* tests/libcurl-oracle.c: what a libcurl says about itself, read in C, for
 * the suites that check what chez-curl reports (tests/libcurl-oracle.sls).
 * chez-curl itself compiles no C (ADR-0001).
 *
 *   libcurl-oracle PATH
 *   libcurl-oracle PATH protocols
 *
 * It dlopens PATH, exactly as given, finds curl_version_info with dlsym,
 * calls it with CURLVERSION_TENTH, the age (curl private native) asks for,
 * and prints five fields of what it answers as Scheme data, one per line:
 *
 *   (version . "8.20.0")
 *   (version-num . 529408)
 *   (features . 1430210445)
 *   (ssl-version . "GnuTLS/3.8.13")
 *   (host . "x86_64-unknown-linux-gnu")
 *
 * With protocols, it prints one datum instead, the list of protocol names
 * curl_version_info_data's protocols holds, in order, as strings:
 *
 *   ("dict" "file" "ftp" ...)
 *
 * A NULL string is #f. The struct is libcurl's own, from its headers, so
 * the fields are read at the offsets C gives them, not the ones the
 * native layer's ftype gives them. It exits 0, or 1 with a message on
 * stderr when PATH will not load, lacks curl_version_info, or answers
 * NULL. Missing headers fail the compile, and the suite with it: never a
 * skip (ADR-0001).
 */
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <curl/curl.h>

typedef curl_version_info_data *(*version_info_fn)(CURLversion);

/* put_string: (KEY . "VALUE"), with " and \ escaped, or (KEY . #f). */
static void put_string(const char *key, const char *value)
{
  const char *p;
  if (!value) {
    printf("(%s . #f)\n", key);
    return;
  }
  printf("(%s . \"", key);
  for (p = value; *p; p++) {
    if (*p == '"' || *p == '\\')
      putchar('\\');
    putchar(*p);
  }
  printf("\")\n");
}

int main(int argc, char **argv)
{
  void *library;
  version_info_fn version_info;
  curl_version_info_data *data;

  if (argc != 2 && !(argc == 3 && strcmp(argv[2], "protocols") == 0)) {
    fprintf(stderr, "usage: libcurl-oracle PATH [protocols]\n");
    return 1;
  }
  library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    fprintf(stderr, "libcurl-oracle: %s\n", dlerror());
    return 1;
  }
  *(void **)(&version_info) = dlsym(library, "curl_version_info");
  if (!version_info) {
    fprintf(stderr, "libcurl-oracle: %s has no curl_version_info\n", argv[1]);
    return 1;
  }
  data = version_info(CURLVERSION_TENTH);
  if (!data) {
    fprintf(stderr, "libcurl-oracle: curl_version_info returned NULL\n");
    return 1;
  }
  if (argc == 3) {
    const char *const *p;
    printf("(");
    for (p = data->protocols; p && *p; p++) {
      const char *c;
      printf("%s\"", p == data->protocols ? "" : " ");
      for (c = *p; *c; c++) {
        if (*c == '"' || *c == '\\')
          putchar('\\');
        putchar(*c);
      }
      printf("\"");
    }
    printf(")\n");
    return 0;
  }
  put_string("version", data->version);
  printf("(version-num . %u)\n", data->version_num);
  printf("(features . %u)\n", (unsigned int)data->features);
  put_string("ssl-version", data->ssl_version);
  put_string("host", data->host);
  return 0;
}
