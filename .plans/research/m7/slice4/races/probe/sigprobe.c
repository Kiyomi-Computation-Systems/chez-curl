/* sigprobe.c: a measurement probe for M7 slice 4's race work, not a test.
 * Loaded into a test-group child by load-shared-object, probe_install
 * wraps the SIGINT handler Chez installed: each SIGINT the process takes
 * is recorded, up to 16, with the thread that took it (gettid), the time
 * (CLOCK_REALTIME, ns), the interrupted context's rax (-4, EINTR, when the
 * thread was in a blocking system call) and the system call the main
 * thread was in at that moment when another thread took it (from
 * /proc/self/task/MAIN/syscall: its number, -1 when running, -2 unread);
 * then Chez's handler runs, as before. */
#define _GNU_SOURCE
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <ucontext.h>
#include <sys/syscall.h>

#define N 16
static struct sigaction old;
static volatile int count;
static volatile long tids[N];
static volatile long long nss[N];
static volatile long raxs[N];
static volatile long mainsys[N];
static long main_tid;

static long long now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static long read_syscall(long tid) {
  char path[64], buf[64];
  int i = 0, fd, n;
  long v = 0, sign = 1;
  /* path by hand: snprintf is not async-signal-safe */
  const char *a = "/proc/self/task/";
  char digits[24];
  int d = 0;
  long t = tid;
  while (*a) path[i++] = *a++;
  do { digits[d++] = (char)('0' + t % 10); t /= 10; } while (t > 0);
  while (d > 0) path[i++] = digits[--d];
  a = "/syscall";
  while (*a) path[i++] = *a++;
  path[i] = 0;
  fd = open(path, O_RDONLY);
  if (fd < 0) return -2;
  n = (int)read(fd, buf, sizeof buf - 1);
  close(fd);
  if (n <= 0) return -2;
  buf[n] = 0;
  if (buf[0] == 'r') return -1; /* running */
  i = 0;
  if (buf[0] == '-') { sign = -1; i = 1; }
  for (; buf[i] >= '0' && buf[i] <= '9'; i++) v = v * 10 + (buf[i] - '0');
  return sign * v;
}

static void wrapper(int sig, siginfo_t *si, void *ctx) {
  int k = count;
  long tid = syscall(SYS_gettid);
  if (k < N) {
    tids[k] = tid;
    nss[k] = now_ns();
#if defined(__x86_64__)
    raxs[k] = (long)((ucontext_t *)ctx)->uc_mcontext.gregs[REG_RAX];
#else
    raxs[k] = 0;
#endif
    mainsys[k] = (tid == main_tid) ? -3 : read_syscall(main_tid);
  }
  count = k + 1;
  if (old.sa_flags & SA_SIGINFO) {
    if (old.sa_sigaction) old.sa_sigaction(sig, si, ctx);
  } else if (old.sa_handler != SIG_IGN && old.sa_handler != SIG_DFL) {
    old.sa_handler(sig);
  }
}

int probe_install(void) {
  struct sigaction act;
  main_tid = syscall(SYS_gettid);
  if (sigaction(SIGINT, NULL, &old) != 0) return -1;
  memset(&act, 0, sizeof act);
  act.sa_sigaction = wrapper;
  act.sa_flags = old.sa_flags | SA_SIGINFO;
  act.sa_mask = old.sa_mask;
  if (sigaction(SIGINT, &act, NULL) != 0) return -1;
  return (old.sa_flags & SA_SIGINFO) ? 1 : 0;
}

long probe_gettid(void) { return syscall(SYS_gettid); }
long long probe_now(void) { return now_ns(); }
int probe_count(void) { return count; }
long probe_tid(int i) { return (i >= 0 && i < N) ? tids[i] : 0; }
long long probe_ns(int i) { return (i >= 0 && i < N) ? nss[i] : 0; }
long probe_rax(int i) { return (i >= 0 && i < N) ? raxs[i] : 0; }
long probe_mainsys(int i) { return (i >= 0 && i < N) ? mainsys[i] : 0; }
long probe_syscall_of(long tid) { return read_syscall(tid); }
/* whether SIGINT is blocked in the calling thread */
int probe_blocked(void) {
  sigset_t s;
  if (pthread_sigmask(SIG_BLOCK, NULL, &s) != 0) return -1;
  return sigismember(&s, SIGINT);
}
