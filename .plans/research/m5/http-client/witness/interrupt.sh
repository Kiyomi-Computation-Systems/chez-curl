t=$(command -v timeout || command -v gtimeout) || { echo 'http-client escape: no timeout' >&2; exit 125; }
out=$(mktemp "${TMPDIR:-/tmp}/http-client-escape.XXXXXX") || exit 125
"$t" -s KILL 60 "$@" >"$out" 2>&1 </dev/null &
waiter=$!
n=0
until grep -q '^(ready ' "$out" || [ "$n" -ge 400 ]; do sleep 0.05; n=$((n + 1)); done
pid=$(sed -n 's/^(ready \([0-9]*\))$/\1/p' "$out")
if [ -z "$pid" ]; then kill "$waiter"; wait "$waiter"; cat "$out" >&2; rm -f "$out"; echo 'http-client escape: the child never said it was ready' >&2; exit 126; fi
sleep 0.5
kill -INT "$pid"
wait "$waiter"
status=$?
grep -v '^(ready ' "$out"
rm -f "$out"
exit $status
