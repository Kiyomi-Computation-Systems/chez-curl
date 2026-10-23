/* tests/decoy-libcurl.c: a stand-in libcurl, for
 * tests/test-library-loading.sps only. chez-curl itself compiles no C
 * (ADR-0001).
 *
 * The suite compiles this file at test time, once per case, as a shared
 * object (-shared -fPIC) under the -D switches below, and points
 * CHEZ_CURL_LIBCURL at it. Each case answers one load-time check wrongly,
 * so the suite watches each refusal fire by name. With no switch it is the
 * control: at the floor, with SSL, and both APIs present, so it loads, and a
 * refusal of any other case is that case's doing.
 *
 * It includes libcurl's own headers, so every prototype it defines and
 * every struct it fills has the real library's types and layout. Missing
 * headers fail the compile, and the suite with it: never a skip (ADR-0001).
 *
 * Every curl_* function here appends one entry to a call log, its name and
 * its arguments, and decoy_calls() returns the log, entries separated by a
 * space. The suite asserts the whole log: ADR-0001's load order, the
 * arguments each call got, and that nothing runs after a refusal.
 *
 * Switches:
 *
 *   DECOY_BELOW_FLOOR          version 7.84.0, 0x075400: one minor below
 *   DECOY_NO_SSL               features without CURL_VERSION_SSL
 *   DECOY_SSL_VERSION_NULL     ssl_version is NULL
 *   DECOY_VERSION_NULL         version is NULL
 *   DECOY_HOST_NULL            host is NULL
 *   DECOY_HOST_UTF8            host is "décoy-λ€", in UTF-8: two- and
 *                              three-byte sequences, which only a UTF-8
 *                              reading reports as written
 *   DECOY_PROTOCOLS            protocols is {"https", "dict", "http",
 *                              NULL}; every other build leaves it NULL
 *   DECOY_VERSION_INFO_NULL    curl_version_info returns NULL
 *   DECOY_INIT_FAILS           curl_global_init returns CURLE_FAILED_INIT
 *   DECOY_OPTIONS_OFF          curl_easy_option_by_name returns NULL, as
 *                              with --disable-get-easy-options
 *   DECOY_HEADERS_OFF          curl_easy_header returns CURLHE_NOT_BUILT_IN,
 *                              as with --disable-headers-api
 *   DECOY_EASY_INIT_NULL       curl_easy_init returns NULL
 *   DECOY_NOT_CURL             no curl_* function at all: not a libcurl
 *   DECOY_LACKS_<function>     that one curl_* function left out
 *   DECOY_MARKER               also defines decoy_marker, which no other
 *                              build has: whether a process ever loaded
 *                              this build is foreign-entry?'s answer for it
 */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
/* curl_url_get's declaration differs by version (below), so the headers
   declare it under another name, and this file defines it with none. */
#define curl_url_get decoy_header_curl_url_get
#include <curl/curl.h>
#include <curl/header.h>
#undef curl_url_get

/* With gcc, curl/curl.h makes curl_easy_setopt and curl_easy_getinfo
   type-checking macros, as its typecheck-gcc.h does for a caller. This
   file defines the functions themselves, as libcurl's own sources do after
   the same #undef. */
#undef curl_easy_setopt
#undef curl_easy_getinfo

static char calls[2048];

/* called: appends one entry, printf-style, to the call log. */
static void called(const char *format, ...)
{
  size_t used = strlen(calls);
  va_list args;
  if (used > 0 && used + 1 < sizeof calls) {
    calls[used++] = ' ';
    calls[used] = '\0';
  }
  va_start(args, format);
  vsnprintf(calls + used, sizeof calls - used, format, args);
  va_end(args);
}

/* decoy_calls: the call log. Not a curl name, so the real libcurl lacks it. */
const char *decoy_calls(void)
{
  return calls;
}

#ifdef DECOY_MARKER
/* decoy_marker: present only in a build with DECOY_MARKER. */
int decoy_marker(void)
{
  return 1;
}
#endif

#ifndef DECOY_NOT_CURL

#ifdef DECOY_BELOW_FLOOR
#define DECOY_VERSION "7.84.0"
#define DECOY_VERSION_NUM 0x075400
#elif defined(DECOY_VERSION_NULL)
#define DECOY_VERSION NULL
#define DECOY_VERSION_NUM 0x075500
#else
#define DECOY_VERSION "7.85.0"
#define DECOY_VERSION_NUM 0x075500
#endif

#ifdef DECOY_HOST_NULL
#define DECOY_HOST NULL
#elif defined(DECOY_HOST_UTF8)
#define DECOY_HOST "d\xc3\xa9" "coy-\xce\xbb" "\xe2\x82\xac"
#else
#define DECOY_HOST "decoy-host"
#endif

#ifdef DECOY_NO_SSL
#define DECOY_FEATURES (CURL_VERSION_IPV6 | CURL_VERSION_LIBZ)
#else
#define DECOY_FEATURES (CURL_VERSION_IPV6 | CURL_VERSION_SSL | CURL_VERSION_LIBZ | \
                        CURL_VERSION_HTTP2 | CURL_VERSION_THREADSAFE)
#endif

#ifdef DECOY_SSL_VERSION_NULL
#define DECOY_SSL_VERSION NULL
#else
#define DECOY_SSL_VERSION "DecoyTLS/1.0"
#endif

/* The one easy handle: curl_easy_init answers its address, and the calls
   that take a handle log whether they got it. */
static int easy_handle;
#define HANDLE_NAME(easy) ((easy) == (CURL *)&easy_handle ? "handle" : "other")

#ifndef DECOY_LACKS_curl_version_info
#ifdef DECOY_PROTOCOLS
static const char *const decoy_protocols[] = {"https", "dict", "http", NULL};
#define DECOY_PROTOCOL_LIST decoy_protocols
#else
#define DECOY_PROTOCOL_LIST NULL
#endif

static curl_version_info_data info = {
  .age = CURLVERSION_TENTH,
  .version = DECOY_VERSION,
  .version_num = DECOY_VERSION_NUM,
  .host = DECOY_HOST,
  .features = DECOY_FEATURES,
  .ssl_version = DECOY_SSL_VERSION,
  .protocols = DECOY_PROTOCOL_LIST,
};

curl_version_info_data *curl_version_info(CURLversion stamp)
{
  called("curl_version_info(%d)", (int)stamp);
#ifdef DECOY_VERSION_INFO_NULL
  return NULL;
#else
  return &info;
#endif
}
#endif

#ifndef DECOY_LACKS_curl_global_init
CURLcode curl_global_init(long flags)
{
  called("curl_global_init(%ld)", flags);
#ifdef DECOY_INIT_FAILS
  return CURLE_FAILED_INIT;
#else
  return CURLE_OK;
#endif
}
#endif

#ifndef DECOY_LACKS_curl_easy_option_by_name
static const struct curl_easyoption url_option = {
  .name = "URL",
  .id = CURLOPT_URL,
  .type = CURLOT_STRING,
  .flags = 0,
};

/* Knows one option, URL, as the real table does: any other name is NULL. */
const struct curl_easyoption *curl_easy_option_by_name(const char *name)
{
  called("curl_easy_option_by_name(%s)", name ? name : "NULL");
#ifdef DECOY_OPTIONS_OFF
  return NULL;
#else
  return (name && strcmp(name, "URL") == 0) ? &url_option : NULL;
#endif
}
#endif

#ifndef DECOY_LACKS_curl_easy_init
CURL *curl_easy_init(void)
{
  called("curl_easy_init()");
#ifdef DECOY_EASY_INIT_NULL
  return NULL;
#else
  return (CURL *)&easy_handle;
#endif
}
#endif

#ifndef DECOY_LACKS_curl_easy_header
/* A fresh handle has no headers: CURLHE_NOHEADERS, as libcurl 8.20.0
   answers (ADR-0003). */
CURLHcode curl_easy_header(CURL *easy, const char *name, size_t nameindex,
                           unsigned int origin, int request,
                           struct curl_header **hout)
{
  called("curl_easy_header(%s,%s,%zu,%u,%d,%s)", HANDLE_NAME(easy),
         name ? name : "NULL", nameindex, origin, request,
         hout ? "hout" : "NULL");
#ifdef DECOY_HEADERS_OFF
  return CURLHE_NOT_BUILT_IN;
#else
  return CURLHE_NOHEADERS;
#endif
}
#endif

#ifndef DECOY_LACKS_curl_easy_cleanup
void curl_easy_cleanup(CURL *easy)
{
  called("curl_easy_cleanup(%s)", HANDLE_NAME(easy));
}
#endif

/* The variadic pair the load binds and never calls: so no entry for
   either is in a log the suite expects, and one there would fail it. */
#ifndef DECOY_LACKS_curl_easy_setopt
CURLcode curl_easy_setopt(CURL *easy, CURLoption option, ...)
{
  called("curl_easy_setopt(%s,%d)", HANDLE_NAME(easy), (int)option);
  return CURLE_OK;
}
#endif

#ifndef DECOY_LACKS_curl_easy_getinfo
CURLcode curl_easy_getinfo(CURL *easy, CURLINFO info, ...)
{
  called("curl_easy_getinfo(%s,%d)", HANDLE_NAME(easy), (int)info);
  return CURLE_OK;
}
#endif

/* The URL API (ADR-0008), which the load binds and never calls, as with
   the variadic pair above. Each answers as a library with no memory
   would. */
#ifndef DECOY_LACKS_curl_url
CURLU *curl_url(void)
{
  called("curl_url()");
  return NULL;
}
#endif

#ifndef DECOY_LACKS_curl_url_cleanup
void curl_url_cleanup(CURLU *handle)
{
  called("curl_url_cleanup(%s)", handle ? "handle" : "NULL");
}
#endif

#ifndef DECOY_LACKS_curl_url_set
CURLUcode curl_url_set(CURLU *handle, CURLUPart what, const char *part,
                       unsigned int flags)
{
  called("curl_url_set(%s,%d,%s,%u)", handle ? "handle" : "NULL", (int)what,
         part ? "part" : "NULL", flags);
  return CURLUE_OUT_OF_MEMORY;
}
#endif

#ifndef DECOY_LACKS_curl_url_get
/* The header's own declaration was renamed away above: its handle is
   CURLU * at the floor, 7.85.0, and const CURLU * in 8.x, and a definition
   that disagrees with it does not compile. Defined with no declaration in
   scope, either way, it compiles against whichever headers the lane
   names. */
CURLUcode curl_url_get(CURLU *handle, CURLUPart what, char **part,
                       unsigned int flags)
{
  called("curl_url_get(%s,%d,%s,%u)", handle ? "handle" : "NULL", (int)what,
         part ? "part" : "NULL", flags);
  return CURLUE_OUT_OF_MEMORY;
}
#endif

#ifndef DECOY_LACKS_curl_url_strerror
const char *curl_url_strerror(CURLUcode error)
{
  called("curl_url_strerror(%d)", (int)error);
  return "decoy";
}
#endif

#ifndef DECOY_LACKS_curl_free
void curl_free(void *p)
{
  called("curl_free(%s)", p ? "p" : "NULL");
}
#endif

#endif /* DECOY_NOT_CURL */
