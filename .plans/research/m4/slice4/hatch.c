/* M4 slice 4's measurement probe (the M4 plan, section 7.1): one transfer
   through the multi interface, as the engine makes one, with options set by
   name, as the hatch will set them.

     hatch version
     hatch URL STEP ...

   Every transfer first gets chez-curl's pins, PROTOCOLS_STR and
   REDIR_PROTOCOLS_STR at "http,https" and NOSIGNAL at 1, and a write
   callback that keeps the body. Then each STEP, in order:

     long:NAME=V        a long option, by curl_easy_option_by_name's id
     off:NAME=V         an off_t one
     str:NAME=V         a string one, from a malloc'd copy freed once setopt
                        returns, as the binding's counted block is
     list:NAME=A|B|...  a string list, each element appended, freed after
                        curl_easy_cleanup, as the binding frees its lists
     list-early:NAME=A|B|...
                        a control: the list freed, its strings first
                        overwritten, as soon as setopt returns
     list-leak:NAME=A|B|...
                        a control: the list never freed
     blob:NAME=FILE     FILE's bytes in a malloc'd block, passed with
                        CURL_BLOB_COPY, then overwritten and freed as soon as
                        setopt returns, as the binding will
     blob-nocopy:NAME=FILE
                        the control: CURL_BLOB_NOCOPY, overwritten and freed
                        as soon as setopt returns
     body:N             POSTFIELDSIZE_LARGE at N, then COPYPOSTFIELDS at N
                        bytes, byte i (i * 31 + 7) & 255, never NULL
     text:T             POSTFIELDSIZE_LARGE at T's length, then
                        COPYPOSTFIELDS at T, as given
     method:M           CUSTOMREQUEST at M
     ca:FILE            CAINFO at FILE, CAPATH cleared, as the CA file field

   A step whose name the library does not know prints so, and the transfer
   still runs. It prints one line per step, "set NAME CODE" with setopt's
   answer, then: the transfer's code, its status, how many messages
   curl_multi_info_read gave and how many were for its own handle, the
   first 300 bytes of the body, escaped, how far its stdin's offset moved,
   which a read of stdin moves, when stdin is a file, and its effective
   URL. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <curl/curl.h>

static char out[65536];
static size_t used;

static size_t sink(char *data, size_t size, size_t n, void *unused) {
  size_t len = size * n, room = sizeof out - 1 - used, take = len < room ? len : room;
  (void)unused;
  memcpy(out + used, data, take);
  used += take;
  out[used] = 0;
  return len;
}

static struct curl_slist *kept[16];
static int nkept;

/* option: NAME's id, or -1 when the library does not know it. */
static int option(const char *name) {
  const struct curl_easyoption *o = curl_easy_option_by_name(name);
  return o ? (int)o->id : -1;
}

static void print_escaped(const char *s, size_t n) {
  size_t i;
  putchar('"');
  for (i = 0; i < n; i++) {
    unsigned char c = (unsigned char)s[i];
    if (c == '"' || c == '\\') printf("\\%c", c);
    else if (c >= 32 && c < 127) putchar(c);
    else printf("\\x%02x", c);
  }
  putchar('"');
}

/* read_file: FILE's bytes, malloc'd, and their count in *n. */
static char *read_file(const char *file, size_t *n) {
  FILE *f = fopen(file, "rb");
  char *bytes;
  long size;
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  size = ftell(f);
  fseek(f, 0, SEEK_SET);
  bytes = malloc(size > 0 ? (size_t)size : 1);
  *n = fread(bytes, 1, (size_t)size, f);
  fclose(f);
  return bytes;
}

static struct curl_slist *build_list(char *spec) {
  struct curl_slist *list = NULL;
  char *part = strtok(spec, "|");
  while (part) {
    list = curl_slist_append(list, part);
    part = strtok(NULL, "|");
  }
  return list;
}

static void step(CURL *h, char *arg) {
  char *colon = strchr(arg, ':'), *kind = arg, *name, *value, *eq;
  CURLcode rc = CURLE_OK;
  int id;
  if (!colon) { printf("bad step %s\n", arg); exit(2); }
  *colon = 0;
  name = colon + 1;
  if (strcmp(kind, "body") == 0) {
    long n = atol(name), i;
    unsigned char *bytes = malloc(n > 0 ? (size_t)n : 1);
    for (i = 0; i < n; i++) bytes[i] = (unsigned char)((i * 31 + 7) & 255);
    printf("set POSTFIELDSIZE_LARGE %d\n", (int)curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)n));
    printf("set COPYPOSTFIELDS %d\n", (int)curl_easy_setopt(h, CURLOPT_COPYPOSTFIELDS, bytes));
    free(bytes);
    return;
  }
  if (strcmp(kind, "text") == 0) {
    printf("set POSTFIELDSIZE_LARGE %d\n", (int)curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)strlen(name)));
    printf("set COPYPOSTFIELDS %d\n", (int)curl_easy_setopt(h, CURLOPT_COPYPOSTFIELDS, name));
    return;
  }
  if (strcmp(kind, "method") == 0) {
    printf("set CUSTOMREQUEST %d\n", (int)curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, name));
    return;
  }
  if (strcmp(kind, "ca") == 0) {
    printf("set CAINFO %d\n", (int)curl_easy_setopt(h, CURLOPT_CAINFO, name));
    printf("set CAPATH %d\n", (int)curl_easy_setopt(h, CURLOPT_CAPATH, (char *)NULL));
    return;
  }
  eq = strchr(name, '=');
  if (!eq) { printf("bad step %s:%s\n", kind, name); exit(2); }
  *eq = 0;
  value = eq + 1;
  id = option(name);
  if (id < 0) { printf("set %s unknown\n", name); return; }
  if (strcmp(kind, "long") == 0) {
    rc = curl_easy_setopt(h, (CURLoption)id, atol(value));
  } else if (strcmp(kind, "off") == 0) {
    rc = curl_easy_setopt(h, (CURLoption)id, (curl_off_t)strtoll(value, NULL, 10));
  } else if (strcmp(kind, "str") == 0) {
    char *copy = strdup(value);
    rc = curl_easy_setopt(h, (CURLoption)id, copy);
    memset(copy, 'X', strlen(copy));
    free(copy);
  } else if (strcmp(kind, "list") == 0 || strcmp(kind, "list-early") == 0
             || strcmp(kind, "list-leak") == 0) {
    struct curl_slist *list = build_list(value), *e;
    rc = curl_easy_setopt(h, (CURLoption)id, list);
    if (strcmp(kind, "list") == 0) {
      kept[nkept++] = list;
    } else if (strcmp(kind, "list-early") == 0) {
      for (e = list; e; e = e->next) memset(e->data, 'X', strlen(e->data));
      curl_slist_free_all(list);
    }
  } else if (strcmp(kind, "blob") == 0 || strcmp(kind, "blob-nocopy") == 0) {
    struct curl_blob blob;
    size_t n = 0;
    char *bytes = read_file(value, &n);
    if (!bytes) { printf("no file %s\n", value); exit(2); }
    blob.data = bytes;
    blob.len = n;
    blob.flags = strcmp(kind, "blob") == 0 ? CURL_BLOB_COPY : CURL_BLOB_NOCOPY;
    rc = curl_easy_setopt(h, (CURLoption)id, &blob);
    memset(bytes, 0xA5, n);
    free(bytes);
  } else {
    printf("bad step kind %s\n", kind);
    exit(2);
  }
  printf("set %s %d\n", name, (int)rc);
}

int main(int argc, char **argv) {
  CURLM *m;
  CURL *h;
  CURLMsg *msg;
  int running = 1, i, left, msgs = 0, ours = 0;
  CURLcode code = (CURLcode)-1;
  long status = 0;
  if (curl_global_init(CURL_GLOBAL_ALL) != CURLE_OK) { puts("no init"); return 1; }
  if (argc == 2 && strcmp(argv[1], "version") == 0) {
    curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
    printf("%s %s\n", v->version, v->ssl_version ? v->ssl_version : "-");
    return 0;
  }
  if (argc < 2) { puts("usage: hatch version | hatch URL STEP ..."); return 2; }
  m = curl_multi_init();
  h = curl_easy_init();
  curl_easy_setopt(h, CURLOPT_URL, argv[1]);
  curl_easy_setopt(h, (CURLoption)option("PROTOCOLS_STR"), "http,https");
  curl_easy_setopt(h, (CURLoption)option("REDIR_PROTOCOLS_STR"), "http,https");
  curl_easy_setopt(h, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, 10000L);
  curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, sink);
  for (i = 2; i < argc; i++) step(h, argv[i]);
  curl_multi_add_handle(m, h);
  while (running) {
    if (curl_multi_perform(m, &running) != CURLM_OK) break;
    if (running) curl_multi_poll(m, NULL, 0, 1000, NULL);
  }
  while ((msg = curl_multi_info_read(m, &left)) != NULL) {
    msgs++;
    if (msg->easy_handle == h) {
      ours++;
      if (msg->msg == CURLMSG_DONE) code = msg->data.result;
    }
  }
  curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
  printf("code %d status %ld msgs %d ours %d body ", (int)code, status, msgs, ours);
  print_escaped(out, used < 300 ? used : 300);
  {
    char *effective = NULL;
    curl_easy_getinfo(h, CURLINFO_EFFECTIVE_URL, &effective);
    printf(" stdin-offset %ld url %s\n", (long)lseek(0, 0, SEEK_CUR), effective ? effective : "-");
  }
  curl_multi_remove_handle(m, h);
  curl_easy_cleanup(h);
  for (i = 0; i < nkept; i++) curl_slist_free_all(kept[i]);
  curl_multi_cleanup(m);
  curl_global_cleanup();
  return 0;
}
