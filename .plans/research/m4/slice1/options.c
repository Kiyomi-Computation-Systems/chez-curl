/* M4 slice 1's options table (the M4 plan, section 3.2): every option the
   loaded libcurl's options API names, through curl_easy_option_next, one
   line each: its name, its id, its CURLOT type's name, and "alias" for an
   alias name (CURLOT_FLAG_ALIAS). */
#include <stdio.h>
#include <curl/curl.h>
static const char *types[] = { "long", "values", "off-t", "object", "string",
                               "slist", "cbptr", "blob", "function" };
int main(void) {
  const struct curl_easyoption *o = NULL;
  curl_global_init(CURL_GLOBAL_ALL);
  printf("libcurl %s\n", curl_version_info(CURLVERSION_NOW)->version);
  while ((o = curl_easy_option_next(o)) != NULL)
    printf("%s %d %s%s\n", o->name, (int)o->id,
           o->type < sizeof types / sizeof types[0] ? types[o->type] : "unknown",
           (o->flags & CURLOT_FLAG_ALIAS) ? " alias" : "");
  curl_global_cleanup();
  return 0;
}
