# child-loop.sh LOAD N PROGRAM: child-loop.sps N PROGRAM, beside LOAD busy loops.
load=$1; n=$2; program=$3
pids=
i=0
while [ "$i" -lt "$load" ]; do ( while :; do :; done ) & pids="$pids $!"; i=$((i + 1)); done
$CHEZ --libdirs src:tests:build/scheme-libs --program build/m5s1-builder/kept/witness/child-loop.sps "$n" "$program" < /dev/null
for p in $pids; do kill "$p"; done
