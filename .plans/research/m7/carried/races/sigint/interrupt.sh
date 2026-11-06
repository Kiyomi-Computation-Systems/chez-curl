t=$(command -v timeout || command -v gtimeout) || { echo 'child-loop: no timeout' >&2; exit 125; }
out=$(mktemp "${TMPDIR:-/tmp}/child-loop.XXXXXX") || exit 125
CHILD_SENT="$out.sent" MAILBOX_CHILD_SENT="$out.sent" HTTP_CLIENT_CHILD_SENT="$out.sent" "$t" -s KILL 60 "$@" >"$out" 2>&1 </dev/null &
waiter=$!
n=0
until grep -q '^(ready ' "$out" || [ "$n" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done
pid=$(sed -n 's/^(ready \([0-9]*\))$/\1/p' "$out")
if [ -z "$pid" ]; then kill "$waiter"; wait "$waiter"; cat "$out" >&2; rm -f "$out"; echo 'child-loop: the child never said it was ready' >&2; exit 126; fi
sleep "${CHILD_SIGINT_AFTER:-0.5}"
kill -INT "$pid"
: >"$out.sent"
wait "$waiter"
status=$?
grep -v '^(ready ' "$out"
rm -f "$out" "$out.sent"
exit $status
