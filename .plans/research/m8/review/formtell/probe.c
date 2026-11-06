/* The M8 plan's review, 2026-11-06: what each of the form API's calls answers
 * on a libcurl with mime and on one built --disable-mime, so the load's mime
 * probe can be judged (the plan, section 3.4; ADR-0039, decision 4).
 *
 * It prints, in order, one line each:
 *   version     curl_version_info's version and TLS backend
 *   formget-cb  curl_formget(NULL, NULL, cb): a NULL form, non-variadic;
 *               then how many times cb was called, and with how many bytes
 *   formadd-end curl_formadd(&post, &last, CURLFORM_END): the "cheapest call"
 *               the plan's slice 3 measures
 *   formadd-nc  curl_formadd(&post, &last, CURLFORM_COPYNAME, "n",
 *               CURLFORM_COPYCONTENTS, "c", CURLFORM_END): the plan's call
 *   formadd-bad curl_formadd(&post, &last, 9999, CURLFORM_END): an option
 *               number libcurl does not know, what a garbage first variadic
 *               argument would read as
 *   mime-null   curl_mime_init(NULL): a mime, or NULL
 * Every form it makes is freed with curl_formfree, every mime with
 * curl_mime_free. No transfer runs. It needs no server.
 */
#define CURL_DISABLE_DEPRECATION 1
#include <stdio.h>
#include <curl/curl.h>

static int calls = 0;
static size_t bytes = 0;

static size_t counting(void *arg, const char *buf, size_t len)
{
  (void)arg; (void)buf;
  calls++;
  bytes += len;
  return len;
}

int main(void)
{
  struct curl_httppost *post = NULL, *last = NULL;
  curl_version_info_data *v;
  curl_mime *mime;
  int rc;

  if(curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
    printf("global-init failed\n");
    return 1;
  }
  v = curl_version_info(CURLVERSION_NOW);
  printf("version %s ssl=%s\n", v->version, v->ssl_version ? v->ssl_version : "-");

  rc = curl_formget(NULL, NULL, counting);
  printf("formget-cb rc=%d calls=%d bytes=%zu\n", rc, calls, bytes);

  rc = (int)curl_formadd(&post, &last, CURLFORM_END);
  printf("formadd-end rc=%d post=%s\n", rc, post ? "made" : "NULL");
  curl_formfree(post);
  post = last = NULL;

  rc = (int)curl_formadd(&post, &last, CURLFORM_COPYNAME, "n", CURLFORM_COPYCONTENTS, "c",
                         CURLFORM_END);
  printf("formadd-nc rc=%d post=%s\n", rc, post ? "made" : "NULL");
  if(post) {
    calls = 0; bytes = 0;
    rc = curl_formget(post, NULL, counting);
    printf("formget-form rc=%d calls=%d bytes=%zu\n", rc, calls, bytes);
  }
  curl_formfree(post);
  post = last = NULL;

  rc = (int)curl_formadd(&post, &last, (CURLformoption)9999, CURLFORM_END);
  printf("formadd-bad rc=%d post=%s\n", rc, post ? "made" : "NULL");
  curl_formfree(post);
  post = last = NULL;

  mime = curl_mime_init(NULL);
  printf("mime-null %s\n", mime ? "a mime" : "NULL");
  curl_mime_free(mime);

  curl_global_cleanup();
  printf("exit 0\n");
  return 0;
}
