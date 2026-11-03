#!/bin/sh
# Run inside scripts/guix-env from the repository's root:
#   scripts/guix-env sh build/m7s2-review/leak2.sh < /dev/null
rm -f build/m7s2-review/hold.port
node -e 'const s=require("net").createServer(()=>{}).listen(0,"127.0.0.1",()=>{console.log(s.address().port)});setTimeout(()=>process.exit(0),20000)' > build/m7s2-review/hold.port &
until [ -s build/m7s2-review/hold.port ]; do :; done
HOLD_PORT=$(cat build/m7s2-review/hold.port) $CHEZ --libdirs src:tests --program build/m7s2-review/leak2.sps
kill %1 2>/dev/null
