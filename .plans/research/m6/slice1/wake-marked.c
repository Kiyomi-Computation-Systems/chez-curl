/* M6 slice 1 (2026-10-30), wake.c with a mark written to stderr around
   each libcurl call of the turn (M-pause-*, M-perform-*, M-poll-*, M-wake),
   so strace shows which call reads the wakeup back (wake-marked.sh).

   wake.c: is a curl_multi_wakeup lost when it is made
   while the engine's thread is between taking its messages and polling,
   inside curl_easy_pause or before curl_multi_perform?

     wake URL WHERE

   One transfer of URL, ACCEPT_ENCODING "gzip", on a multi handle, in a loop
   like the engine's turn: a resume step, perform, info read, then
   curl_multi_poll for at most 1000 ms. For a paused WHERE, the write
   callback takes a chunk when it holds none and answers
   CURL_WRITEFUNC_PAUSE otherwise; the loop "consumes" the held chunk at
   once, and resumes with curl_easy_pause(CONT) in the next turn's resume
   step, which replays a chunk inside the call. WHERE says when the engine's
   own thread calls curl_multi_wakeup, once a turn, as a caller's thread
   could at that moment:
     pause        inside the replay of curl_easy_pause, the first write call
                  there;
     after        just after curl_easy_pause returns, before the perform;
     before-poll  after the perform, just before the poll: the control that
                  a wakeup there is kept;
     none         never: the control, whose poll waits for libcurl alone;
     plain        no pause at all, every chunk taken, a wakeup before every
                  perform: is a wakeup before a perform lost without one?
   Every poll that follows a wakeup is timed; a wakeup kept ends it at once,
   one lost leaves it to libcurl, 1000 ms while paused, or until the next
   bytes arrive. Prints, per run, the polls timed, how many lasted 100 ms or
   more, and 5 ms or more, the longest, the resumes, the bytes and the code. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <curl/curl.h>
#include <unistd.h>
#define MARK(t) write(2, t "\n", sizeof(t))

static CURLM *multi;
static int holding, in_pause, woke, plain;
static const char *where;
static long long bytes;

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

static void wake(void) {
  if(!woke) {
    curl_multi_wakeup(multi);
    woke = 1;
  }
}

static size_t on_write(char *p, size_t s, size_t n, void *u) {
  (void)p; (void)u;
  if(in_pause && !strcmp(where, "pause")) wake();
  if(plain) { bytes += (long long)(s * n); return s * n; }
  if(holding) return CURL_WRITEFUNC_PAUSE;
  holding = 1;
  bytes += (long long)(s * n);
  return s * n;
}

int main(int argc, char **argv) {
  CURL *h;
  int running = 1, polls = 0, slow = 0, slow5 = 0, resumes = 0, msgs;
  double longest = 0;
  CURLMsg *m;
  CURLcode code = CURLE_OK;
  if(argc != 3) { fprintf(stderr, "usage: wake URL pause|after|before-poll|none|plain\n"); return 2; }
  where = argv[2];
  plain = !strcmp(where, "plain");
  curl_global_init(CURL_GLOBAL_ALL);
  multi = curl_multi_init();
  h = curl_easy_init();
  curl_easy_setopt(h, CURLOPT_URL, argv[1]);
  curl_easy_setopt(h, CURLOPT_PROXY, "");
  curl_easy_setopt(h, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(h, CURLOPT_ACCEPT_ENCODING, "gzip");
  curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, on_write);
  curl_easy_setopt(h, CURLOPT_TIMEOUT_MS, 60000L);
  curl_multi_add_handle(multi, h);
  while(running) {
    woke = 0;
    if(holding) {
      /* the consumer took the held chunk: the resume step */
      holding = 0;
      resumes++;
      in_pause = 1;
      MARK("M-pause-start");
      curl_easy_pause(h, CURLPAUSE_CONT);
      MARK("M-pause-end");
      in_pause = 0;
      if(!strcmp(where, "after")) { MARK("M-wake"); wake(); }
    }
    if(plain) wake();
    MARK("M-perform-start");
    curl_multi_perform(multi, &running);
    MARK("M-perform-end");
    while((m = curl_multi_info_read(multi, &msgs)))
      if(m->msg == CURLMSG_DONE) code = m->data.result;
    if(!running) break;
    if(!strcmp(where, "before-poll") && holding) wake();
    {
      int made = woke;
      double t0 = now_ms(), d;
      MARK("M-poll-start");
      curl_multi_poll(multi, NULL, 0, 1000, NULL);
      MARK("M-poll-end");
      d = now_ms() - t0;
      if(made) {
        polls++;
        if(d >= 100) slow++;
        if(d >= 5) slow5++;
        if(d > longest) longest = d;
      }
    }
  }
  printf("wake where=%s version=%s timed-polls=%d polls-100ms-or-more=%d polls-5ms-or-more=%d longest-ms=%.1f resumes=%d bytes=%lld code=%d\n",
         where, curl_version_info(CURLVERSION_NOW)->version, polls, slow, slow5, longest, resumes, bytes, (int)code);
  curl_multi_remove_handle(multi, h);
  curl_easy_cleanup(h);
  curl_multi_cleanup(multi);
  curl_global_cleanup();
  return 0;
}
