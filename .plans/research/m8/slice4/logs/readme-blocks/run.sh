#!/bin/sh
# Runs the README's nine blocks, inside the container: first as written, a
# fragment (1-4) under (import (curl)) as a script, a block with its own
# import (5-9) both as an R6RS program and as a script (the REPL's
# environment, Chez's names bound); then 4 and 6-9 against a loopback http
# stand-in, example.com's https URL replaced, block 4's saved-lines bound to
# its read-out, and block 9's big.bin made.
D=.plans/research/m8/slice4/logs/readme-blocks
LIBS=src:build/scheme-libs
make deps >/dev/null 2>&1 || { echo "make deps failed"; exit 1; }
echo "## bound check"
"$CHEZ" --libdirs $LIBS --program $D/bound.sps 2>&1
for n in 1 2 3 4; do
  { echo '(import (curl))'; cat $D/block-$n.ss; echo '(display "ok block '$n' ran to its end") (newline)'; } > $D/frag-$n.ss
  echo "## block $n as a script, (import (curl)) prepended"
  timeout 60 "$CHEZ" -q --libdirs $LIBS --script $D/frag-$n.ss 2>&1; echo "exit $?"
done
for n in 5 6 7 8 9; do
  echo "## block $n as an R6RS program, as written"
  timeout 60 "$CHEZ" --libdirs $LIBS --program $D/block-$n.ss 2>&1; echo "exit $?"
  { cat $D/block-$n.ss; echo '(display "ok block '$n' ran to its end") (newline)'; } > $D/script-$n.ss
  echo "## block $n as a script, as written"
  timeout 60 "$CHEZ" -q --libdirs $LIBS --script $D/script-$n.ss 2>&1; echo "exit $?"
done
# Loopback runs.
node $D/server.mjs > $D/port.txt &
SERVER=$!
i=0; while [ ! -s $D/port.txt ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
PORT=$(head -n 1 $D/port.txt)
echo "## loopback stand-in on port $PORT"
head -c 300000 /dev/zero > /tmp/big.bin
for n in 4 6 7 8 9; do
  sed "s|https://example.com|http://127.0.0.1:$PORT|g; s|\"big.bin\"|\"/tmp/big.bin\"|; s|saved-lines|(curl-cookie-jar-cookies jar)|" $D/block-$n.ss > $D/loop-$n.ss
  case $n in 4) pre='(import (curl))';; *) pre='';; esac
  { echo "$pre"; cat $D/loop-$n.ss; } > $D/loop-$n.tmp && mv $D/loop-$n.tmp $D/loop-$n.ss
  # Print each top-level value: run through the REPL, not --script.
  echo "## block $n against the loopback stand-in, through the REPL, each value printed"
  timeout 60 "$CHEZ" -q --libdirs $LIBS < $D/loop-$n.ss 2>&1; echo "exit $?"
done
kill $SERVER
echo "ok run.sh done"
