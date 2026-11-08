#!/bin/sh
# `make check-memory-gate`: proves that `make test-memory` fails on planted
# memory defects, and holds its one suppression honest (ADR-0014, amended
# 2026-10-16). One case per property:
#
#   a  plain        each plant, run without Valgrind, exits 0 and prints
#                   only its line, so a red gate can only mean Valgrind
#                   saw the defect
#   b  overrun      test-memory names the overrun plant FAIL, with exit 9,
#                   Valgrind's "Invalid write" in its log and in its own
#                   output, and goes on to the suite after it
#   b  leak         the same for the leak plant, with its loss record
#   b  fails        a program that Valgrind finds clean but that exits 1
#                   is named FAIL with its exit, its FAIL line with its
#                   expected and actual values, 18 lines before its end,
#                   and its last lines, a FAIL among them, each line once,
#                   and no line between them
#   c  suppression  tests/guix-glibc-locpath.supp holds exactly its one
#                   entry: one name, one kind, these four frames, nothing
#                   else
#   d  used         (Guix only) a run that loads libcurl through (curl)
#                   passes, and -v reports guix-glibc-locpath used on one
#                   block, and no suppression file but it and Valgrind's own
#                   default.supp, at the path Valgrind names for it
#   d  needed       (Guix only) the same run with GUIX_ENVIRONMENT unset
#                   fails, on one block lost under
#                   compute_locale_search_path: an entry Guix has made
#                   stale fails here
#   d  leak         (Guix only) the leak plant fails with the suppression
#                   read
#   d  more         (Guix only) a program that loads libcurl and calls
#                   newlocale once more loses a second block the entry
#                   matches, and test-memory names it FAIL: the entry may
#                   hide one block, no more
#   d  alone        (Guix only) a program that loads no libcurl, and so no
#                   p11-kit, and calls newlocale once loses one block the
#                   entry matches, and test-memory names it FAIL: the entry
#                   hides a block only in a run that loads libp11-kit
#   d  override     (Guix only) MEMORY_SUPPRESSION_FILE on make's command
#                   line, naming a file that hides the overrun plant, is
#                   ignored, so the plant fails
#
#                   No case fails the rule's lower bound, that a run which
#                   loads libp11-kit has its one block suppressed: every
#                   such run loses the block, and no plant can stop it.
#                   d used holds the same property for memory-load-curl.
#   e  command      the commands test-memory hands Valgrind, whole, read by
#                   a stand-in for Valgrind: first the run that asks it for
#                   its default.supp, then the suite's, with -v,
#                   --command-line-only=yes and the suite's own --log-file,
#                   no suppression with GUIX_ENVIRONMENT unset, as in CI,
#                   the one file with it set, and timeout its parent. The
#                   stand-in runs nothing, so the suite FAILs: it wrote no
#                   Valgrind log
#   f  hangs        a program that never ends is named HUNG
#   g  none         test-memory refuses to pass with no suite
#   h  options      test-memory refuses to run while any source of options
#                   its command line does not show is present, each in a
#                   case of its own, planted in a copy: VALGRIND_OPTS,
#                   $HOME/.valgrindrc, ./.valgrindrc (in a copy of the
#                   tree), VALGRIND_LIB (at a copy of Valgrind's library
#                   directory whose default.supp hides every leak), and any
#                   other VALGRIND_ variable. And a suite that writes
#                   $HOME/.valgrindrc mid-run cannot hand the next suite a
#                   suppression: --command-line-only=yes
#   i  suppressions a suppressions file the gate does not pass, named
#                   default.supp and hiding every leak, fails the leak
#                   plant by name, though Valgrind exits 0: beside
#                   Valgrind's own default.supp, and in its place
#   j  evidence     a pass needs the log to show that Valgrind ran Chez
#                   itself, on the suite, and reported 0 errors from 0
#                   contexts: a CHEZ that is a script, exec'ing Chez or
#                   running it as a child, fails the leak plant; a program
#                   that execs away from Valgrind fails; a Valgrind that
#                   runs another program than the suite fails
#   k  options      a pass needs Valgrind's "Valgrind options:" list to be
#                   exactly the gate's, in order. A program that branches
#                   on memory nothing initialised fails, exit 9 (undef);
#                   --undef-value-errors=no, added through VALGRIND, hides
#                   it, and fails it by name (added). Stand-ins for
#                   Valgrind that drop --leak-check=full, or change
#                   --errors-for-leak-kinds=definite to none, each hide the
#                   leak plant, and fail it by name (dropped, changed); one
#                   that moves a flag fails a clean program (order)
#   l  logs         Valgrind writes to a log of its own, and every piece of
#                   evidence is read from it: a suite that prints a clean
#                   ERROR SUMMARY with Valgrind's pid, then execs away,
#                   fails (forged); a Valgrind log an earlier run left is
#                   never read: a Valgrind that writes none fails (stale);
#                   two suites with one name, whose logs would be one, are
#                   refused (names)
#   m  awk          the evidence check is one awk program, and a pass needs
#                   its exit status 0 and its one line "ok". Stand-ins for
#                   awk, first on PATH, each fail a clean program, naming
#                   the check: one that fails, printing nothing, as a broken
#                   program or a missing feature would (fails); one that
#                   prints "ok", then exits 2 (ok-fails); and one that exits
#                   0, printing nothing (silent)
#   n  shards       CI runs the gate in two shards (ADR-0014, amended
#                   2026-11-06), and what each runs is read from
#                   test-memory's own run, a stand-in for Valgrind running
#                   nothing: with no MEMORY_SHARD it runs every suite in
#                   tests/, in order (all); MEMORY_SHARD=1 and 2 each run a
#                   list of their own, and the two run every suite in tests/
#                   once between them, and nothing else, each suite's
#                   command to Valgrind e's (split). It refuses a
#                   MEMORY_SHARD but 1 or 2 (refused), one beside a
#                   MEMORY_SUITES on its command line or in the environment
#                   (beside), and a shard's list, MEMORY_RUN or
#                   MEMORY_RUN_NAME set from outside (lists), running no
#                   suite
#   o  ci           .github/workflows/ci.yml runs make test-memory in two
#                   jobs, one per shard, each line exactly "run: make
#                   test-memory MEMORY_SHARD=1" or "=2", each job running
#                   "run: make check-memory-gate" in an earlier step, and
#                   neither job nor step carries an if: or a
#                   continue-on-error:
#
# Outside a Guix environment (GUIX_ENVIRONMENT unset, as in CI), d is
# skipped and says so: no suppression is passed there. e holds both arms
# everywhere.
#
# A case compares the lines starting "test-memory: " as a whole: each
# suite's outcome and the count. The suite after a plant is
# build/check-memory-gate/after.sps, an empty program, which loses nothing.
# Every run writes build/memory/<suite>.log, the suite's own output, and
# build/memory/<suite>.valgrind, Valgrind's, and the whole directory is
# removed before each run but l stale's second, so no log is left from an
# earlier one. Scratch files live in build/check-memory-gate/, by relative
# path: make splits MEMORY_SUITES on spaces, and the checkout's path may
# hold one.
#
# `make check-memory-gate` passes MAKE, TIMEOUT, CHEZ, VALGRIND and
# LIBDIRS, the ones it uses. Run directly, the script takes make, timeout,
# scheme and valgrind from PATH.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root" || exit 2

# The inner make starts afresh: nothing of an outer make's flags or
# command-line variables reaches it, nor a shard or a list of suites from
# the environment, which test-memory reads.
unset MAKEFLAGS MFLAGS MAKELEVEL MEMORY_SHARD MEMORY_SUITES

MAKE=${MAKE:-make}
TIMEOUT=${TIMEOUT:-timeout}
CHEZ=${CHEZ:-scheme}
VALGRIND=${VALGRIND:-valgrind}
LIBDIRS=${LIBDIRS:-src:tests:build/scheme-libs}

# Each run's per-suite cap, in seconds: a plant ends in a few. The hang
# case's is shorter, so its plant is killed soon.
suite_timeout=300
hang_timeout=15

supp=tests/guix-glibc-locpath.supp
overrun=tests/memory-plant-overrun.sps
leak=tests/memory-plant-leak.sps
loader=tests/memory-load-curl.sps
scratch=build/check-memory-gate
after=$scratch/after.sps
fails=$scratch/fails.sps
more=$scratch/more.sps
alone=$scratch/alone.sps
hangs=$scratch/hangs.sps
latrc=$scratch/late-rc.sps
execs=$scratch/execs.sps
undef=$scratch/undef.sps
forge=$scratch/forge.sps
twin=$scratch/twin/after.sps
stub=$scratch/valgrind-stub
mute=$scratch/valgrind-mute
swap=$scratch/valgrind-swap
everything=$scratch/everything.supp
anywrite=$scratch/anywrite.supp
vglib=$scratch/vglib
tree=$scratch/tree
logs=build/memory
out=$scratch/out

rm -rf "$scratch"
mkdir -p "$scratch" || { echo "check-memory-gate: could not make $scratch" >&2; exit 2; }

# Valgrind's own default.supp, as Valgrind names it in a run that nothing
# outside its command line steers. Cases d, h and i need it.
vgbin=${VALGRIND%% *}
vgdefault=$(env -u VALGRIND_LIB "$vgbin" -v --command-line-only=yes true 2>&1 |
  sed -n 's/^--[0-9]*-- Reading suppressions file: //p')
case $vgdefault in
  /*/default.supp) ;;
  *) echo "check-memory-gate: $vgbin -v, run on true, named no default.supp of its own: \"$vgdefault\"" >&2
     exit 2 ;;
esac
vglibdir=${vgdefault%/default.supp}

# The real file sh names, as Valgrind reports what it ran.
sh_real=$(readlink -f "$(command -v sh)")

# A suppression that matches every definite leak, the plant's among them.
cat >"$everything" <<'EOF'
{
   everything
   Memcheck:Leak
   match-leak-kinds: definite
   fun:*
   ...
}
EOF

# A suppression that matches every one-byte invalid access, the overrun
# plant's among them.
cat >"$anywrite" <<'EOF'
{
   anywrite
   Memcheck:Addr1
   fun:*
   ...
}
EOF

# A copy of Valgrind's library directory, every file linked but
# default.supp, which gains the suppression above: VALGRIND_LIB pointed
# here hid the leak plant from the gate before it refused VALGRIND_LIB.
mkdir -p "$vglib"
for f in "$vglibdir"/*; do ln -s "$f" "$vglib/"; done
rm -f "$vglib/default.supp"
cat "$vgdefault" "$everything" >"$vglib/default.supp"

cat >"$after" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: an empty program, which loses
;;; nothing, run after a plant to show that test-memory goes on.
(import (rnrs))
(display "after: ran")
(newline)
EOF

cat >"$fails" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: a program that fails on its own.
(import (rnrs))
(display "FAIL a planted check\n  expected: (planted 1)\n  actual:   (planted 2)\n")
(let loop ((i 1))
  (when (<= i 12)
    (display "fails: line ") (display i) (newline)
    (loop (+ i 1))))
(display "FAIL a late check\n  expected: (late 1)\n  actual:   (late 2)\n")
(display "fails: exits 1, with no memory defect")
(newline)
(exit 1)
EOF

cat >"$more" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: loads libcurl, which loses the
;;; one block the suppression covers, then calls glibc's newlocale for a
;;; locale it must search for, which loses another under the same frames.
;;; 8127 is glibc's LC_ALL_MASK; xx_YY is no locale, so newlocale answers 0.
(import (rnrs) (only (chezscheme) foreign-procedure) (curl))
(define newlocale (foreign-procedure "newlocale" (int string uptr) uptr))
(loaded-libcurl)
(display "more: newlocale answered ")
(display (newlocale 8127 "xx_YY" 0))
(newline)
EOF

cat >"$alone" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: loads no libcurl, and so no
;;; p11-kit, then calls glibc's newlocale for a locale it must search for,
;;; which loses one block under the frames the suppression names. 8127 is
;;; glibc's LC_ALL_MASK; xx_YY is no locale, so newlocale answers 0.
(import (rnrs) (only (chezscheme) load-shared-object foreign-procedure))
(load-shared-object "libc.so.6")
(define newlocale (foreign-procedure "newlocale" (int string uptr) uptr))
(display "alone: newlocale answered ")
(display (newlocale 8127 "xx_YY" 0))
(newline)
EOF

cat >"$hangs" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: a program that never ends.
(import (rnrs) (only (chezscheme) sleep make-time))
(sleep (make-time 'time-duration 0 3600))
EOF

cat >"$latrc" <<EOF
#!r6rs
;;; Written by tests/check-memory-gate.sh: writes \$HOME/.valgrindrc, naming
;;; a suppression that matches every definite leak, for the suite after it.
(import (rnrs) (only (chezscheme) getenv))
(call-with-output-file (string-append (getenv "HOME") "/.valgrindrc")
  (lambda (port)
    (display "--suppressions=$root/$everything" port)
    (newline port)))
(display "late-rc: wrote \$HOME/.valgrindrc")
(newline)
EOF

cat >"$execs" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: replaces itself with /bin/sh,
;;; which exits 0. Valgrind follows no exec, so it never reports on the run.
(import (rnrs)
        (only (chezscheme) load-shared-object foreign-procedure foreign-alloc
              foreign-set! foreign-sizeof))
(load-shared-object "libc.so.6")
(define execv (foreign-procedure "execv" (string uptr) int))
(define (c-string s)
  (let* ((b (string->utf8 s)) (n (bytevector-length b)) (p (foreign-alloc (+ n 1))))
    (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref b i)))
    (foreign-set! 'unsigned-8 p n 0)
    p))
(define args '("sh" "-c" "exit 0"))
(define width (foreign-sizeof 'uptr))
(define argv (foreign-alloc (* width (+ (length args) 1))))
(let loop ((i 0) (args args))
  (if (null? args)
      (foreign-set! 'uptr argv (* width i) 0)
      (begin
        (foreign-set! 'uptr argv (* width i) (c-string (car args)))
        (loop (+ i 1) (cdr args)))))
(display "execs: replacing itself with /bin/sh, which exits 0")
(newline)
(flush-output-port (current-output-port))
(execv "/bin/sh" argv)
(display "execs: execv failed")
(newline)
(exit 1)
EOF

cat >"$undef" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: branches on four bytes of foreign
;;; memory that nothing initialised, which Valgrind reports as a
;;; "Conditional jump or move depends on uninitialised value(s)".
(import (rnrs) (only (chezscheme) foreign-alloc foreign-ref foreign-free))
(define p (foreign-alloc 8))
(display (if (= (foreign-ref 'unsigned-32 p 0) 12345) "undef: branched one way" "undef: branched"))
(newline)
(foreign-free p)
EOF

# The forger prints one line as Valgrind would, with Valgrind's pid, which
# is its own, then replaces itself with /bin/sh, so Valgrind never reports.
cat >"$forge" <<'EOF'
#!r6rs
;;; Written by tests/check-memory-gate.sh: prints, on stderr and with its
;;; own pid, which is Valgrind's, the ERROR SUMMARY of a clean run, then
;;; replaces itself with /bin/sh, which exits 0, so that Valgrind itself
;;; reports nothing.
(import (rnrs)
        (only (chezscheme) load-shared-object foreign-procedure foreign-alloc
              foreign-set! foreign-sizeof))
(load-shared-object "libc.so.6")
(define getpid (foreign-procedure "getpid" () int))
(define execv (foreign-procedure "execv" (string uptr) int))
(define (c-string s)
  (let* ((b (string->utf8 s)) (n (bytevector-length b)) (p (foreign-alloc (+ n 1))))
    (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref b i)))
    (foreign-set! 'unsigned-8 p n 0)
    p))
(define args '("sh" "-c" "exit 0"))
(define width (foreign-sizeof 'uptr))
(define argv (foreign-alloc (* width (+ (length args) 1))))
(let loop ((i 0) (args args))
  (if (null? args)
      (foreign-set! 'uptr argv (* width i) 0)
      (begin
        (foreign-set! 'uptr argv (* width i) (c-string (car args)))
        (loop (+ i 1) (cdr args)))))
(let ((err (current-error-port)) (pid (number->string (getpid))))
  (put-string err (string-append "==" pid "== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)\n"))
  (flush-output-port err))
(execv "/bin/sh" argv)
(display "forge: execv failed")
(newline)
(exit 1)
EOF

mkdir -p "${twin%/*}"
cp "$after" "$twin"

# A stand-in for Valgrind: it appends the name of the process that started
# it, then each argument, one per line, then a line "--", to
# <itself>.argv. It names a default.supp, as Valgrind -v does, so that
# test-memory's question of its default.supp has an answer, and exits 0
# having run nothing.
cat >"$stub" <<'EOF'
#!/bin/sh
{
  printf 'parent: %s\n' "$(cat "/proc/$PPID/comm" 2>/dev/null || echo unknown)"
  for arg in "$@"; do printf '%s\n' "$arg"; done
  printf '%s\n' --
} >>"$0.argv"
echo "--1-- Reading suppressions file: /check-memory-gate/valgrind-stub/default.supp" >&2
exit 0
EOF
chmod +x "$stub"

# Another that runs nothing, but names Valgrind's own default.supp, so that
# a log left from a real run would pass every check but its existence.
cat >"$mute" <<EOF
#!/bin/sh
echo "--1-- Reading suppressions file: $vgdefault" >&2
exit 0
EOF
chmod +x "$mute"

# A Valgrind that runs another program than the suite it is handed: the
# empty one, after.sps. It hands Valgrind every other argument as it came.
cat >"$swap" <<EOF
#!/bin/sh
n=\$#
i=0
for arg in "\$@"; do
  i=\$((i + 1))
  case \$i:\$arg in
    \$n:*.sps) set -- "\$@" "$after" ;;
    *)         set -- "\$@" "\$arg" ;;
  esac
done
shift "\$n"
exec "$vgbin" "\$@"
EOF
chmod +x "$swap"

# Three Valgrinds that edit the options they are handed, up to the first
# argument that is no option, and hand the rest on as it came: one drops
# --leak-check=full, one changes --errors-for-leak-kinds=definite to none,
# and one moves --leak-check=full to the end of the options.
for how in drop change order; do
  cat >"$scratch/valgrind-$how" <<EOF
#!/bin/sh
n=\$#
moved=
options=yes
for arg in "\$@"; do
  if [ -n "\$options" ]; then
    case \$arg in
      -*) ;;
      *) options=
         [ -z "\$moved" ] || set -- "\$@" "\$moved" ;;
    esac
  fi
  if [ -n "\$options" ]; then
    case $how:\$arg in
      drop:--leak-check=full) continue ;;
      change:--errors-for-leak-kinds=definite) arg=--errors-for-leak-kinds=none ;;
      order:--leak-check=full) moved=\$arg; continue ;;
    esac
  fi
  set -- "\$@" "\$arg"
done
shift "\$n"
exec "$vgbin" "\$@"
EOF
  chmod +x "$scratch/valgrind-$how"
done

# Two scripts for CHEZ: one execs the real Chez, the other runs it as a
# child. Valgrind runs the shell, not Chez, and follows no exec or child.
for how in exec child; do
  case $how in
    exec) run='exec' ;;
    *)    run='' ;;
  esac
  printf '#!%s\n%s "%s" "$@"\n' "$sh_real" "$run" "$CHEZ" >"$scratch/chez-$how"
  chmod +x "$scratch/chez-$how"
done

pass=0
fail=0
ok()   { pass=$((pass + 1)); printf 'check-memory-gate: ok %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'check-memory-gate: FAILED %s\n' "$1" >&2; }
skip() { printf 'check-memory-gate: skipped %s\n' "$1"; }

# gate MAKE-ARG...: runs make test-memory with MEMORY_TIMEOUT=$per_suite and
# the arguments, output to $out, under a cap of its own: room for two
# suites to run out their time, and two minutes more. A make that runs
# longer has lost its per-suite timeout. Answers make's status.
per_suite=$suite_timeout
gate() {
  rm -rf "$logs"
  gate_keep "$@"
}

# gate_keep MAKE-ARG...: gate, with the logs of the run before left in place.
gate_keep() {
  "$TIMEOUT" $((2 * per_suite + 120)) "$MAKE" --no-print-directory test-memory \
    MEMORY_TIMEOUT="$per_suite" "$@" >"$out" 2>&1
}

# gate_in DIR MAKE-ARG...: gate, run as make -C DIR, in a copy of the tree.
gate_in() {
  dir=$1
  shift
  rm -rf "$dir/$logs"
  "$TIMEOUT" $((2 * per_suite + 120)) "$MAKE" --no-print-directory -C "$dir" test-memory \
    MEMORY_TIMEOUT="$per_suite" "$@" >"$out" 2>&1
}

# Problems found in the current case, one per line, and the case's verdict.
problems=
problem() { problems="$problems$1
"; }

# verdict NAME [plain]: ok when the case found no problem, else FAILED with
# each, and then, unless the case ran no make, the whole output of its last
# run.
verdict() {
  if [ -z "$problems" ]; then
    ok "$1"
  else
    bad "$1"
    printf '%s' "$problems" | sed 's/^/  /' >&2
    [ "${2:-}" = plain ] || [ ! -f "$out" ] || sed 's/^/  | /' "$out" >&2
  fi
  problems=
}

# want_status WANT STATUS: WANT is 0 or nonzero. A status of 124 is the
# case's own cap: make test-memory never finished.
want_status() {
  if [ "$2" -eq 124 ]; then
    problem "make test-memory did not finish within its cap, so no per-suite timeout stopped it"
  elif [ "$1" = 0 ] && [ "$2" -ne 0 ]; then
    problem "make test-memory exited $2, not 0"
  elif [ "$1" = nonzero ] && [ "$2" -eq 0 ]; then
    problem "make test-memory exited 0"
  fi
}

# want_lines WANTED: the run's "test-memory: " lines must be exactly WANTED.
want_lines() {
  got=$(grep '^test-memory: ' "$out")
  if [ "$got" != "$1" ]; then
    problem "make test-memory's lines differ:
$(printf '%s\n' "$1" | sed 's/^/  wanted: /')
$(printf '%s\n' "$got" | sed 's/^/  got:    /')"
  fi
}

# want_in FILE TEXT WHAT: FILE must hold a line containing TEXT.
want_in() {
  if [ ! -f "$1" ]; then
    problem "$3: $1 does not exist"
  elif ! grep -qF -- "$2" "$1"; then
    problem "$3: no \"$2\" in $1"
  fi
}

failed_line() { printf 'test-memory: FAIL %s (exit 9, Valgrind'"'"'s: an error or a definite leak)\n' "$1"; }

# zero_line SUITE PROBLEM...: the line naming SUITE FAIL though Valgrind
# exited 0, with each problem test-memory found in its log, in its order.
zero_line() {
  suite=$1
  shift
  why=$1
  shift
  for extra in "$@"; do why="$why; $extra"; done
  printf 'test-memory: FAIL %s (exit 0, but %s)\n' "$suite" "$why"
}

# A suite's two logs: its own output, and Valgrind's.
log_of()  { printf '%s/%s.log' "$logs" "$(basename "$1" .sps)"; }
vlog_of() { printf '%s/%s.valgrind' "$logs" "$(basename "$1" .sps)"; }

# gate_options SUITE: the options test-memory hands Valgrind for SUITE, in
# order, one space between each, as other_options lists them. They are
# ADR-0014's, written out here and not read from the Makefile.
gate_options() {
  printf '%s' "-v --command-line-only=yes --log-file=$(vlog_of "$1") --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite"
  [ -z "${GUIX_ENVIRONMENT:-}" ] || printf ' %s' "--suppressions=$supp"
}

# The problems zero_line names, worded as test-memory words them.
no_log() { printf 'Valgrind wrote no log, %s' "$(vlog_of "$1")"; }
no_zero='Valgrind reported no "ERROR SUMMARY: 0 errors from 0 contexts"'
ran_other() { printf 'Valgrind ran %s, not %s, the file CHEZ names' "$1" "$2"; }
other_command() { printf 'Valgrind'"'"'s Command: line is "%s", not "%s"' "$1" "$2"; }
other_options() { printf 'Valgrind'"'"'s options are [%s], not the gate'"'"'s [%s]' "$1" "$2"; }
other_files() { printf 'Valgrind read the suppressions files [%s], and the gate allows exactly [%s]' "$1" "$2"; }
no_p11() { printf 'guix-glibc-locpath suppressed %s blocks, and covers none in a run that loads no libp11-kit' "$1"; }

# The suppressions files test-memory allows, as other_files lists them.
if [ -n "${GUIX_ENVIRONMENT:-}" ]; then
  allowed="$supp, $vgdefault"
else
  allowed=$vgdefault
fi
count_line()  { printf 'test-memory: ran %d, passed %d, failed %d, hung %d\n' "$1" "$2" "$3" "$4"; }

# ---- a: each plant, run plainly ----
for p in "$overrun" "$leak"; do
  case "$p" in
    "$overrun") line="memory-plant-overrun: planted a one-byte write just past a 23-byte foreign block" ;;
    *)          line="memory-plant-leak: planted a 777-byte foreign block that nothing frees or holds" ;;
  esac
  plain=$("$CHEZ" --libdirs "$LIBDIRS" --program "$p" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || problem "it exited $rc without Valgrind"
  [ "$plain" = "$line" ] || problem "its output, without Valgrind, is not the one line \"$line\":
$(printf '%s\n' "$plain" | sed 's/^/  | /')"
  verdict "a plain: $p exits 0 without Valgrind, and prints only its line" plain
done

# ---- b: test-memory fails on each plant, by name, with Valgrind's marker ----
for p in "$overrun" "$leak"; do
  gate MEMORY_SUITES="$p $after"
  status=$?
  want_status nonzero "$status"
  want_lines "$(failed_line "$p")
test-memory: pass $after
$(count_line 2 1 1 0)"
  vlog=$(vlog_of "$p")
  case "$p" in
    "$overrun") markers="Invalid write of size 1
0 bytes after a block of size 23 alloc'd" ;;
    *)          markers="777 bytes in 1 blocks are definitely lost in loss record" ;;
  esac
  markers="$markers
ERROR SUMMARY: 1 errors from 1 contexts"
  while IFS= read -r m; do
    want_in "$vlog" "$m" "its Valgrind log"
    want_in "$out" "$m" "test-memory's own output"
  done <<EOF
$markers
EOF
  verdict "b $(basename "$p" .sps): test-memory names $p FAIL, with Valgrind's report in its log and its output, and runs the suite after it"
done

gate MEMORY_SUITES="$fails $after"
status=$?
want_status nonzero "$status"
want_lines "test-memory: FAIL $fails (exit 1)
test-memory: pass $after
$(count_line 2 1 1 0)"
want_in "$out" "  | fails: exits 1, with no memory defect" "test-memory's own output, the program's last lines"
want_in "$out" "  | FAIL a planted check" "test-memory's own output, the suite's FAIL line, 18 lines before its end"
want_in "$out" "  |   expected: (planted 1)" "test-memory's own output, the FAIL's expected value"
want_in "$out" "  |   actual:   (planted 2)" "test-memory's own output, the FAIL's actual value"
for f in "  | FAIL a planted check" "  | FAIL a late check"; do
  n=$(grep -cxF -- "$f" "$out")
  [ "$n" = 1 ] || problem "test-memory's own output shows \"$f\" $n times, not once"
done
if grep -qxF -- "  | fails: line 1" "$out"; then
  problem "test-memory's own output shows \"fails: line 1\", a line neither after a FAIL nor in the suite's last 10"
fi
want_in "$out" "ERROR SUMMARY: 0 errors from 0 contexts" "test-memory's own output, Valgrind's verdict"
verdict "b fails: test-memory names a program that exits 1 FAIL, with its exit, its FAIL lines and its last lines, and runs the suite after it"

# ---- c: the suppression file holds exactly its one entry ----
# Valgrind skips blank lines and lines starting with #; every other line,
# stripped, is part of an entry.
entry='{
guix-glibc-locpath
Memcheck:Leak
match-leak-kinds: definite
fun:realloc
fun:argz_add_sep
fun:compute_locale_search_path
fun:newlocale
}'
if [ ! -f "$supp" ]; then
  problem "$supp does not exist"
else
  body=$(grep -v '^#' "$supp" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')
  entries=$(printf '%s\n' "$body" | grep -c '^{$')
  [ "$entries" -eq 1 ] || problem "$supp holds $entries entries, not one"
  printf '%s\n' "$body" | grep -qxF 'fun:compute_locale_search_path' ||
    problem "$supp has no fun:compute_locale_search_path frame"
  [ "$body" = "$entry" ] || problem "$supp's entry is not exactly the one ADR-0014 allows:
$(printf '%s\n' "$entry" | sed 's/^/  wanted: /')
$(printf '%s\n' "$body" | sed 's/^/  got:    /')"
fi
verdict "c suppression: $supp holds exactly one entry, guix-glibc-locpath, a definite leak under compute_locale_search_path" plain

# ---- d: in a Guix environment, the suppression is used, needed, and narrow ----
if [ -z "${GUIX_ENVIRONMENT:-}" ]; then
  skip "d: GUIX_ENVIRONMENT is unset, so test-memory passes no suppression here, and there is none to hold"
else
  gate MEMORY_SUITES="$loader"
  status=$?
  want_status 0 "$status"
  want_lines "test-memory: pass $loader
$(count_line 1 1 0 0)"
  log=$(log_of "$loader")
  vlog=$(vlog_of "$loader")
  want_in "$log" "memory-load-curl: loaded libcurl " "the program's line, so libcurl was loaded"
  if [ -f "$vlog" ]; then
    used=$(grep -cE "^--[0-9]+-- used_suppression: +1 guix-glibc-locpath $supp:[0-9]+ suppressed: [0-9,]+ bytes in 1 blocks$" "$vlog")
    [ "$used" -eq 1 ] || problem "-v does not report guix-glibc-locpath used, once, on one block, in $vlog:
$(grep 'used_suppression' "$vlog" | sed 's/^/  | /')"
    files=$(sed -n 's/^--[0-9]*-- Reading suppressions file: //p' "$vlog")
    [ "$files" = "$supp
$vgdefault" ] || problem "Valgrind read other suppression files than $supp and its own $vgdefault:
$(printf '%s\n' "$files" | sed 's/^/  | /')"
  else
    problem "$vlog does not exist"
  fi
  verdict "d used: a run that loads libcurl through (curl) passes, and Valgrind reports guix-glibc-locpath used on one block"

  ( unset GUIX_ENVIRONMENT; gate MEMORY_SUITES="$loader" )
  status=$?
  want_status nonzero "$status"
  want_lines "$(failed_line "$loader")
$(count_line 1 0 1 0)"
  want_in "$log" "memory-load-curl: loaded libcurl " "the program's line, so libcurl was loaded"
  want_in "$vlog" "definitely lost: " "a definite loss"
  if [ -f "$vlog" ]; then
    grep -qE '^==[0-9]+== +definitely lost: [0-9,]+ bytes in 1 blocks$' "$vlog" ||
      problem "the run did not lose exactly one block: $(grep 'definitely lost:' "$vlog")"
    grep -qE '^==[0-9]+== +by 0x[0-9A-F]+: compute_locale_search_path ' "$vlog" ||
      problem "no lost block was allocated under compute_locale_search_path, so the leak the suppression covers is gone, or moved: ask whether it is still needed"
  fi
  verdict "d needed: without the suppression, the same run fails on the one block lost under compute_locale_search_path"

  gate MEMORY_SUITES="$leak"
  status=$?
  want_status nonzero "$status"
  want_lines "$(failed_line "$leak")
$(count_line 1 0 1 0)"
  vlog=$(vlog_of "$leak")
  want_in "$vlog" "Reading suppressions file: $supp" "the suppression read"
  want_in "$vlog" "777 bytes in 1 blocks are definitely lost in loss record" "the planted leak"
  verdict "d leak: the leak plant fails with the suppression read"

  gate MEMORY_SUITES="$more"
  status=$?
  want_status nonzero "$status"
  want_lines "test-memory: FAIL $more (exit 0, but guix-glibc-locpath suppressed 2 blocks, and covers exactly one, lost when libp11-kit loads)
$(count_line 1 0 1 0)"
  want_in "$out" "more: newlocale answered 0" "test-memory's own output, the program's last lines"
  want_in "$out" " suppressed: " "test-memory's own output, the suppressed total"
  # The entry's own count, from Valgrind's used_suppression line: the total
  # holds default.supp's too, and the load's mime probe, whose
  # curl_mime_init draws a boundary, grew it by dtv-addr-tail's one block
  # (M8 slice 3's build, research/m8/slice3/build/).
  entry_used=$(grep 'used_suppression: .* guix-glibc-locpath ' "$(vlog_of "$more")" 2>/dev/null)
  case $entry_used in
    *" bytes in 2 blocks") ;;
    *) problem "Valgrind's log, the entry's own count: its used_suppression line is \"$entry_used\", not 2 blocks" ;;
  esac
  verdict "d more: a second block lost under newlocale, which the entry matches, fails the suite"

  gate MEMORY_SUITES="$alone"
  status=$?
  want_status nonzero "$status"
  want_lines "$(zero_line "$alone" "$(no_p11 1)")
$(count_line 1 0 1 0)"
  want_in "$out" "alone: newlocale answered 0" "test-memory's own output, the program's last lines"
  verdict "d alone: one block lost under newlocale in a run that loads no libcurl, and so no p11-kit, fails the suite"

  # The file the gate passes, and allows, is its own, whatever make is told.
  gate MEMORY_SUITES="$overrun" MEMORY_SUPPRESSION_FILE="$anywrite"
  status=$?
  want_status nonzero "$status"
  want_lines "$(failed_line "$overrun")
$(count_line 1 0 1 0)"
  vlog=$(vlog_of "$overrun")
  want_in "$vlog" "Invalid write of size 1" "the planted overrun"
  want_in "$vlog" "Reading suppressions file: $supp" "the gate's own suppression read"
  if [ -f "$vlog" ] && grep -qF "$anywrite" "$vlog"; then
    problem "Valgrind read $anywrite:
$(grep -F "$anywrite" "$vlog" | sed 's/^/  | /')"
  fi
  verdict "d override: MEMORY_SUPPRESSION_FILE on make's command line, naming a file that hides the overrun plant, is ignored, so the plant fails"
fi

# ---- e: the commands Valgrind is handed ----
# expected_argv SUPPRESSION: what the stand-in must write, the suppression
# argument, if any, in its place. First comes the run that asks Valgrind
# for its default.supp, whose parent this does not hold, then the suite's.
expected_argv() {
  printf '%s\n' -v --command-line-only=yes true --
  suite_argv "$leak" "$1"
}
# suite_argv SUITE SUPPRESSION: what the stand-in must write for SUITE's
# run, timeout its parent; case n holds each shard's runs to it too.
suite_argv() {
  printf 'parent: %s\n' "$(basename -- "$TIMEOUT")"
  printf '%s\n' -v --command-line-only=yes "--log-file=$(vlog_of "$1")" --error-exitcode=9 \
    --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite
  [ -z "$2" ] || printf '%s\n' "$2"
  printf '%s\n' "$CHEZ" --libdirs "$LIBDIRS" --program "$1" --
}
for arm in outside inside; do
  rm -f "$stub.argv"
  if [ "$arm" = outside ]; then
    ( unset GUIX_ENVIRONMENT; gate MEMORY_SUITES="$leak" VALGRIND="$stub" )
    status=$?
    wanted=$(expected_argv "")
  else
    ( GUIX_ENVIRONMENT=${GUIX_ENVIRONMENT:-/gnu/store/check-memory-gate-profile}
      export GUIX_ENVIRONMENT
      gate MEMORY_SUITES="$leak" VALGRIND="$stub" )
    status=$?
    wanted=$(expected_argv "--suppressions=$supp")
  fi
  got=$(sed '1{/^parent: /d;}' "$stub.argv" 2>/dev/null)
  [ "$got" = "$wanted" ] || problem "the stand-in for Valgrind was handed other commands:
$(printf '%s\n' "$wanted" | sed 's/^/  wanted: /')
$(printf '%s\n' "$got" | sed 's/^/  got:    /')"
  want_status nonzero "$status"
  want_lines "$(zero_line "$leak" "$(no_log "$leak")")
$(count_line 1 0 1 0)"
  case "$arm" in
    outside) verdict "e command, GUIX_ENVIRONMENT unset: timeout runs Valgrind with ADR-0014's flags, no suppression, then Chez, and a Valgrind that runs nothing fails" ;;
    *)       verdict "e command, GUIX_ENVIRONMENT set: timeout runs Valgrind with ADR-0014's flags and $supp, then Chez, and a Valgrind that runs nothing fails" ;;
  esac
done

# ---- f: a program that never ends ----
per_suite=$hang_timeout
gate MEMORY_SUITES="$hangs"
status=$?
per_suite=$suite_timeout
want_status nonzero "$status"
want_lines "test-memory: HUNG $hangs (no exit within ${hang_timeout}s)
$(count_line 1 0 0 1)"
verdict "f hangs: a program that never ends is named HUNG"

# ---- g: no suite ----
gate MEMORY_SUITES=
status=$?
want_status nonzero "$status"
want_lines "test-memory: no suites: MEMORY_SUITES is empty"
verdict "g none: test-memory refuses to pass with no suite"

# ---- h: options from outside the command line ----
# Each source is planted in a copy, never in the tree, $HOME or Valgrind's
# own directory, and each must stop test-memory before any suite runs.
leaklog=$(basename "$leak" .sps).log

( VALGRIND_OPTS="--suppressions=$everything"
  export VALGRIND_OPTS
  gate MEMORY_SUITES="$leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: VALGRIND_OPTS is set (--suppressions=$everything): Valgrind would add it to the gate's options; unset it (ADR-0014)"
[ ! -e "$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with VALGRIND_OPTS set"

home=$root/$scratch/home
mkdir -p "$home"
printf '%s\n' "--suppressions=$root/$everything" >"$home/.valgrindrc"
( HOME=$home; export HOME; gate MEMORY_SUITES="$leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: $home/.valgrindrc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)"
[ ! -e "$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with a \$HOME/.valgrindrc"

# A copy of the tree: the Makefile copied, the rest linked, so make runs
# there, and Valgrind would read the copy's ./.valgrindrc.
mkdir -p "$tree/build"
cp Makefile "$tree/Makefile"
for f in "$root"/*; do
  case ${f##*/} in
    build|Makefile) ;;
    *) ln -s "$f" "$tree/" ;;
  esac
done
printf '%s\n' "--suppressions=$root/$everything" >"$tree/.valgrindrc"
gate_in "$tree" MEMORY_SUITES="$leak"
status=$?
want_status nonzero "$status"
want_lines "test-memory: ./.valgrindrc exists: Valgrind would add its options to the gate's; remove it (ADR-0014)"
[ ! -e "$tree/$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with a ./.valgrindrc, in a copy of the tree"

( VALGRIND_LIB=$root/$vglib; export VALGRIND_LIB; gate MEMORY_SUITES="$leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: VALGRIND_LIB is set ($root/$vglib): Valgrind would take its tool, its preloads and its default.supp from there; unset it (ADR-0014)"
[ ! -e "$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with VALGRIND_LIB set, at a copy of Valgrind's directory whose default.supp hides every leak"

( VALGRIND_LAUNCHER=$root/$stub; export VALGRIND_LAUNCHER; gate MEMORY_SUITES="$leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: VALGRIND_LAUNCHER is set ($root/$stub): Valgrind reads its VALGRIND_ variables, and no command line shows them; unset it (ADR-0014)"
[ ! -e "$logs/$leaklog" ] || problem "the leak plant ran"
verdict "h options: test-memory refuses to run with any other VALGRIND_ variable set, VALGRIND_LAUNCHER"

# A $HOME with no .valgrindrc when test-memory starts: the first suite
# writes one, naming the suppression that hides every leak.
late=$root/$scratch/home-late
mkdir -p "$late"
( HOME=$late; export HOME; gate MEMORY_SUITES="$latrc $leak" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: pass $latrc
$(failed_line "$leak")
$(count_line 2 1 1 0)"
[ -f "$late/.valgrindrc" ] || problem "$latrc wrote no $late/.valgrindrc, so this case shows nothing"
want_in "$(vlog_of "$leak")" "777 bytes in 1 blocks are definitely lost in loss record" "the planted leak"
verdict "h options: a \$HOME/.valgrindrc that a suite writes mid-run hides nothing from the next: --command-line-only=yes"

# ---- i: suppressions files the gate does not pass ----
# Each is named default.supp, as Valgrind's own is, and hides every leak:
# first beside Valgrind's own, then in its place. The options that pass it
# come through VALGRIND, so the options rule names them first. The block it
# hides is its own entry's, not guix-glibc-locpath's, so in a Guix
# environment the count rule does not name it: the files rule does.
for arm in beside instead; do
  case $arm in
    beside)  extra="--suppressions=$vglib/default.supp"
             gate MEMORY_SUITES="$leak" VALGRIND="$VALGRIND $extra"
             status=$?
             read_files="$vglib/default.supp, $allowed" ;;
    *)       extra="--default-suppressions=no --suppressions=$vglib/default.supp"
             gate MEMORY_SUITES="$leak" VALGRIND="$VALGRIND $extra"
             status=$?
             read_files=$vglib/default.supp
             [ -z "${GUIX_ENVIRONMENT:-}" ] || read_files="$read_files, $supp" ;;
  esac
  want_status nonzero "$status"
  options=$(other_options "$extra $(gate_options "$leak")" "$(gate_options "$leak")")
  wanted=$(zero_line "$leak" "$options" "$(other_files "$read_files" "$allowed")")
  want_lines "$wanted
$(count_line 1 0 1 0)"
  case $arm in
    beside) verdict "i suppressions: a suppressions file the gate does not pass, named default.supp, beside Valgrind's own, fails the leak plant it hides, by name" ;;
    *)      verdict "i suppressions: a file named default.supp in place of Valgrind's own fails the leak plant it hides, by name" ;;
  esac
done

# ---- j: a pass needs evidence that Valgrind ran Chez on the suite ----
for how in exec child; do
  wrapper=$scratch/chez-$how
  wrapper_real=$(readlink -f "$wrapper")
  gate MEMORY_SUITES="$leak" CHEZ="$wrapper"
  status=$?
  want_status nonzero "$status"
  case $how in
    exec) wanted=$(zero_line "$leak" "$(ran_other "$sh_real" "$wrapper_real")" "$no_zero") ;;
    *)    wanted=$(zero_line "$leak" "$(ran_other "$sh_real" "$wrapper_real")") ;;
  esac
  want_lines "$wanted
$(count_line 1 0 1 0)"
  want_in "$logs/$leaklog" "memory-plant-leak: planted a 777-byte foreign block" "the plant's line, so Chez ran"
  case $how in
    exec) verdict "j evidence: a CHEZ that is a script exec'ing Chez fails the leak plant, which Valgrind never saw" ;;
    *)    verdict "j evidence: a CHEZ that is a script running Chez as a child fails the leak plant, which Valgrind never saw" ;;
  esac
done

gate MEMORY_SUITES="$execs"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$execs" "$no_zero")
$(count_line 1 0 1 0)"
want_in "$logs/$(basename "$execs" .sps).log" "execs: replacing itself with /bin/sh, which exits 0" "the program's line, so it ran"
verdict "j evidence: a program that execs away from Valgrind, which then reports nothing, fails"

gate MEMORY_SUITES="$leak" VALGRIND="$swap"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$leak" "$(other_command "$CHEZ --libdirs $LIBDIRS --program $after" "$CHEZ --libdirs $LIBDIRS --program $leak")")
$(count_line 1 0 1 0)"
verdict "j evidence: a Valgrind that runs another program than the suite fails the suite"

# ---- k: Valgrind's options are exactly the gate's ----
gate MEMORY_SUITES="$undef"
status=$?
want_status nonzero "$status"
want_lines "$(failed_line "$undef")
$(count_line 1 0 1 0)"
want_in "$(vlog_of "$undef")" "Conditional jump or move depends on uninitialised value(s)" "its Valgrind log"
want_in "$out" "Conditional jump or move depends on uninitialised value(s)" "test-memory's own output"
verdict "k undef: a program that branches on memory nothing initialised fails, exit 9, with Valgrind's report: the plant the next case hides"

gate MEMORY_SUITES="$undef" VALGRIND="$VALGRIND --undef-value-errors=no"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$undef" "$(other_options "--undef-value-errors=no $(gate_options "$undef")" "$(gate_options "$undef")")")
$(count_line 1 0 1 0)"
want_in "$(vlog_of "$undef")" "ERROR SUMMARY: 0 errors from 0 contexts" "its Valgrind log, so the option hid the plant"
verdict "k added: --undef-value-errors=no, added through VALGRIND, hides that plant, and fails it by name"

for how in drop change order; do
  case $how in
    drop)   suite=$leak
            got=$(gate_options "$leak" | sed 's/ --leak-check=full / /') ;;
    change) suite=$leak
            got=$(gate_options "$leak" | sed 's/ --errors-for-leak-kinds=definite/ --errors-for-leak-kinds=none/') ;;
    *)      suite=$after
            got="$(gate_options "$after" | sed 's/ --leak-check=full / /') --leak-check=full" ;;
  esac
  gate MEMORY_SUITES="$suite" VALGRIND="$scratch/valgrind-$how"
  status=$?
  want_status nonzero "$status"
  want_lines "$(zero_line "$suite" "$(other_options "$got" "$(gate_options "$suite")")")
$(count_line 1 0 1 0)"
  case $how in
    order) verdict "k order: a Valgrind that moves --leak-check=full to the end of its options fails a clean program, by name" ;;
    *)     want_in "$(vlog_of "$leak")" "ERROR SUMMARY: 0 errors from 0 contexts" "its Valgrind log, so the edit hid the plant"
           case $how in
             drop) verdict "k dropped: a Valgrind that drops --leak-check=full hides the leak plant, and fails it by name" ;;
             *)    verdict "k changed: a Valgrind that turns --errors-for-leak-kinds=definite to none hides the leak plant, and fails it by name" ;;
           esac ;;
  esac
done

# ---- l: the evidence comes from Valgrind's own log ----
gate MEMORY_SUITES="$forge"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$forge" "$no_zero")
$(count_line 1 0 1 0)"
want_in "$(log_of "$forge")" "== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)" "the suite's output, its forged line"
if [ -f "$(vlog_of "$forge")" ] && grep -q 'ERROR SUMMARY' "$(vlog_of "$forge")"; then
  problem "$(vlog_of "$forge") holds an ERROR SUMMARY, so Valgrind reported, and the case shows nothing"
fi
verdict "l forged: a suite that prints a clean ERROR SUMMARY with Valgrind's pid, then execs away, fails: the evidence is Valgrind's own log"

gate MEMORY_SUITES="$after"
status=$?
want_status 0 "$status"
[ -f "$(vlog_of "$after")" ] || problem "the first run left no $(vlog_of "$after"), so this case shows nothing"
gate_keep MEMORY_SUITES="$after" VALGRIND="$mute"
status=$?
want_status nonzero "$status"
want_lines "$(zero_line "$after" "$(no_log "$after")")
$(count_line 1 0 1 0)"
verdict "l stale: a Valgrind log an earlier run left is never read: a Valgrind that writes none fails"

gate MEMORY_SUITES="$after $twin"
status=$?
want_status nonzero "$status"
want_lines "test-memory: $after and $twin share the name after, so they would share $logs/after.log and $logs/after.valgrind; rename one (ADR-0014)"
[ ! -e "$(log_of "$after")" ] || problem "a suite ran"
verdict "l names: two suites with one name, in two directories, are refused, so one suite's logs are never another's"

# ---- m: the evidence check's own verdict ----
# Each stand-in for awk logs its arguments, one call per line, to
# <itself>.calls. Only the evidence check hands awk the suite's command.
for how in fails ok-fails silent; do
  dir=$scratch/awk-$how
  mkdir -p "$dir"
  case $how in
    fails)    body='echo "awk: syntax error (planted)" >&2; exit 2'
              why='the evidence check (awk) exited 2' ;;
    ok-fails) body='echo ok; exit 2'
              why='the evidence check (awk) exited 2' ;;
    *)        body='exit 0'
              why='the evidence check (awk) printed no "ok" line' ;;
  esac
  {
    printf '#!%s\n' "$sh_real"
    printf '%s\n' 'printf "%s\n" "$*" >>"$0.calls"' "$body"
  } >"$dir/awk"
  chmod +x "$dir/awk"
  ( PATH=$root/$dir:$PATH; export PATH; gate MEMORY_SUITES="$after" )
  status=$?
  want_status nonzero "$status"
  want_lines "$(zero_line "$after" "$why")
$(count_line 1 0 1 0)"
  want_in "$dir/awk.calls" "cmd=$CHEZ --libdirs $LIBDIRS --program $after" "the stand-in's calls, so it was the evidence check"
  case $how in
    fails)    verdict "m awk: an awk that fails, printing nothing, fails a clean program, naming the evidence check" ;;
    ok-fails) verdict "m awk: an awk that prints ok, then exits 2, fails a clean program, naming the evidence check" ;;
    *)        verdict "m awk: an awk that exits 0, printing nothing, fails a clean program, naming the evidence check" ;;
  esac
done

# ---- n: the two shards ----
# What a run of test-memory ran, from its "=== " lines, in order. The
# stand-in for Valgrind runs nothing, so each suite FAILs at once.
ran() { sed -n 's/^=== //p' "$out"; }
# want_count N: the run's count line names N suites run, every one failed.
want_count() {
  got=$(grep '^test-memory: ran ' "$out")
  [ "$got" = "$(count_line "$1" 0 "$1" 0)" ] ||
    problem "make test-memory's count line is \"$got\", not \"$(count_line "$1" 0 "$1" 0)\""
}
suites=$(printf '%s\n' tests/test-*.sps | LC_ALL=C sort)

gate VALGRIND="$stub"
status=$?
want_status nonzero "$status"
[ "$(ran)" = "$suites" ] || problem "with no MEMORY_SHARD, test-memory ran other suites than every one in tests/, in order:
$(printf '%s\n' "$suites" | sed 's/^/  wanted: /')
$(ran | sed 's/^/  ran:    /')"
want_count "$(printf '%s\n' "$suites" | grep -c '')"
verdict "n all: with no MEMORY_SHARD, test-memory runs every suite in tests/, in order"

# Each shard's runs are handed to Valgrind as case e's run is: no plant
# runs through a shard, so the commands are held instead, every suite's.
for shard in 1 2; do
  rm -f "$stub.argv"
  gate MEMORY_SHARD=$shard VALGRIND="$stub"
  status=$?
  want_status nonzero "$status"
  ran >"$scratch/shard-$shard"
  n=$(grep -c '' "$scratch/shard-$shard")
  if [ "$n" -eq 0 ]; then
    problem "MEMORY_SHARD=$shard ran no suite:
$(sed 's/^/  | /' "$out")"
  else
    want_count "$n"
  fi
  {
    printf '%s\n' -v --command-line-only=yes true --
    while IFS= read -r t; do
      suite_argv "$t" "${GUIX_ENVIRONMENT:+--suppressions=$supp}"
    done <"$scratch/shard-$shard"
  } >"$scratch/argv-wanted-$shard"
  sed '1{/^parent: /d;}' "$stub.argv" >"$scratch/argv-got-$shard" 2>/dev/null
  cmp -s "$scratch/argv-wanted-$shard" "$scratch/argv-got-$shard" ||
    problem "MEMORY_SHARD=$shard handed the stand-in for Valgrind other commands than case e's, suite by suite (wanted <, got >):
$(diff "$scratch/argv-wanted-$shard" "$scratch/argv-got-$shard" | head -n 20 | sed 's/^/  /')"
done
for t in $suites; do
  in1=$(grep -cxF -- "$t" "$scratch/shard-1")
  in2=$(grep -cxF -- "$t" "$scratch/shard-2")
  case $in1:$in2 in
    1:0 | 0:1) ;;
    0:0) problem "$t runs in neither shard" ;;
    *)   problem "$t runs $in1 times in shard 1 and $in2 in shard 2" ;;
  esac
done
for shard in 1 2; do
  while IFS= read -r t; do
    printf '%s\n' "$suites" | grep -qxF -- "$t" ||
      problem "shard $shard runs $t, which is no suite in tests/"
  done <"$scratch/shard-$shard"
done
verdict "n split: MEMORY_SHARD=1 and 2 each run a list of their own, and the two run every suite in tests/ once between them, and nothing else, each handed to Valgrind as case e's is" plain

for value in 0 3 '1 2' "1'" '1"' one; do
  gate MEMORY_SHARD="$value" VALGRIND="$stub"
  status=$?
  want_status nonzero "$status"
  want_lines "test-memory: MEMORY_SHARD is \"$value\": it takes 1 or 2, or none to run MEMORY_SUITES (ADR-0014)"
  [ -z "$(ran)" ] || problem "MEMORY_SHARD=$value ran a suite"
done
verdict "n refused: test-memory refuses a MEMORY_SHARD of 0, 3, \"1 2\", 1', 1\" or one, running no suite"

gate MEMORY_SHARD=1 MEMORY_SUITES="$after" VALGRIND="$stub"
status=$?
want_status nonzero "$status"
want_lines "test-memory: MEMORY_SUITES is set on make's command line beside MEMORY_SHARD=1, which names its own suites: give one (ADR-0014)"
[ -z "$(ran)" ] || problem "beside a command line's MEMORY_SUITES, a suite ran"
( MEMORY_SUITES=$after; export MEMORY_SUITES; gate MEMORY_SHARD=2 VALGRIND="$stub" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: MEMORY_SUITES is set in the environment beside MEMORY_SHARD=2, which names its own suites: give one (ADR-0014)"
[ -z "$(ran)" ] || problem "beside the environment's MEMORY_SUITES, a suite ran"
verdict "n beside: test-memory refuses a MEMORY_SHARD beside a MEMORY_SUITES on its command line or in the environment, running no suite"

# The Makefile's own variables, set from outside: a shard's list, and what
# test-memory runs. make -e lets the environment's override the Makefile's.
gate MEMORY_SHARD=1 MEMORY_SUITES_1="$after" VALGRIND="$stub"
status=$?
want_status nonzero "$status"
want_lines "test-memory: MEMORY_SUITES_1 is set on make's command line: the shard's list is the Makefile's; to run other suites give MEMORY_SUITES and no MEMORY_SHARD (ADR-0014)"
[ -z "$(ran)" ] || problem "with a command line's MEMORY_SUITES_1, a suite ran"
( MEMORY_SUITES_2=$after; export MEMORY_SUITES_2; gate -e MEMORY_SHARD=2 VALGRIND="$stub" )
status=$?
want_status nonzero "$status"
want_lines "test-memory: MEMORY_SUITES_2 is set in the environment: the shard's list is the Makefile's; to run other suites give MEMORY_SUITES and no MEMORY_SHARD (ADR-0014)"
[ -z "$(ran)" ] || problem "with the environment's MEMORY_SUITES_2 under make -e, a suite ran"
for v in MEMORY_RUN MEMORY_RUN_NAME; do
  gate "$v=$after" VALGRIND="$stub"
  status=$?
  want_status nonzero "$status"
  want_lines "test-memory: $v is set on make's command line: it is the Makefile's own; give MEMORY_SUITES or MEMORY_SHARD (ADR-0014)"
  [ -z "$(ran)" ] || problem "with a command line's $v, a suite ran"
done
verdict "n lists: test-memory refuses a shard's list set on its command line or, under make -e, in the environment, and MEMORY_RUN or MEMORY_RUN_NAME set on its command line, running no suite"

# ---- o: ci.yml runs each shard in a job of its own ----
# One awk program reads the workflow: its jobs, each job's steps, and each
# step's run line, comments and blank lines left out. It prints each
# problem, or "ok" alone.
ci=.github/workflows/ci.yml
evidence=$(awk '
  { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line) }
  line == "" || line ~ /^#/ { next }
  /^jobs:$/ { injobs = 1; next }
  /^[^ ]/ { injobs = 0; next }
  !injobs { next }
  /^  [^ ]/ { job = line; sub(/:.*/, "", job); next }
  /^    [^ ]/ { key = line; sub(/:.*/, "", key)
    if (key == "if" || key == "continue-on-error") jobflag[job] = jobflag[job] " " key ":" }
  /^      - / { step++; stepjob[step] = job; sub(/^- +/, "", line); onkey = 1 }
  /^        [^ ]/ { onkey = 1 }
  onkey && step { key = line; sub(/:.*/, "", key); value = line; sub(/^[^:]*: */, "", value)
    if (key == "if" || key == "continue-on-error") stepflag[step] = stepflag[step] " " key ":"
    if (key == "run") steprun[step] = value }
  index(line, "test-memory") || index(line, "check-memory-gate") {
    if (!(onkey && step && key == "run" && (value == "make check-memory-gate" || value == "make test-memory MEMORY_SHARD=1" || value == "make test-memory MEMORY_SHARD=2")))
      why[++n] = "line " NR " names the gate other than as one step\047s whole run line, \"run: make check-memory-gate\" or \"run: make test-memory MEMORY_SHARD=1\" or \"=2\": " line }
  { onkey = 0 }
  END {
    for (s = 1; s <= 2; s++) { want = "make test-memory MEMORY_SHARD=" s; found = 0
      for (i = 1; i <= step; i++) if (steprun[i] == want) { found++; at[s] = i }
      if (found != 1) { why[++n] = found " steps run \"" want "\", not one"; continue }
      j = stepjob[at[s]]; gated = 0
      for (i = 1; i < at[s]; i++) if (stepjob[i] == j && steprun[i] == "make check-memory-gate") { gated = i }
      if (!gated) why[++n] = "job " j " runs \"" want "\" with no \"make check-memory-gate\" step before it"
      else if (stepflag[gated] != "") why[++n] = "job " j "\047s \"make check-memory-gate\" step has" stepflag[gated]
      if (stepflag[at[s]] != "") why[++n] = "job " j "\047s \"" want "\" step has" stepflag[at[s]]
      if (jobflag[j] != "") why[++n] = "job " j " has a job-level" jobflag[j] }
    if (at[1] && at[2] && stepjob[at[1]] == stepjob[at[2]])
      why[++n] = "job " stepjob[at[1]] " runs both shards, not one each"
    for (i = 1; i <= n; i++) print why[i]
    if (!n) print "ok" }' "$ci")
checked=$?
if [ "$checked" -ne 0 ]; then
  problem "the check of $ci (awk) exited $checked"
elif [ -z "$evidence" ]; then
  problem "the check of $ci (awk) printed nothing"
elif [ "$evidence" != ok ]; then
  problem "$evidence"
fi
verdict "o ci: $ci runs make test-memory MEMORY_SHARD=1 and =2 in a job each, after make check-memory-gate, with no if: or continue-on-error:" plain

if [ "$fail" -eq 0 ]; then
  printf 'check-memory-gate: the memory gate failed, as it must, its suppression held, and its two shards run every suite once, in all %d cases\n' "$pass"
fi
[ "$fail" -eq 0 ]
