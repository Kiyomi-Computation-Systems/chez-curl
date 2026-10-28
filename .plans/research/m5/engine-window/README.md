# The engine's take-to-setup window (M5 slice 1, 2026-10-27)

M5 slice 1's builder found that a witness of "the engine holds nothing", the private
`curl-engine-queued-count` plus `curl-engine-live-count`, read 0 for a submit still under way:
the turn empties the queue in one hold of the engine's mutex (`take-queue!`), and enters the
transfer in its live table in a later one (`set-up!`, after `start-transfer!`). Between the two
the token is in neither.

`probe.sps` submits 300 requests, one at a time, to `hold.mjs`, a server that accepts and never
answers, so each stays live until its 100 ms bound. For each it samples the two counts and
`curl-token-done?` as fast as it can until the token is live or done, and counts the samples
that saw neither table hold it and the token not done. `results/guix-8.20.0.log`: 299 of 300
submits showed such a sample, 70,781 samples in all. Run in the container:

    scripts/guix-env sh -c 'mkfifo in; node .plans/research/m5/engine-window/hold.mjs < in > port & exec 3> in; until [ -s port ]; do sleep 0.1; done; $CHEZ --libdirs src:tests -q --program .plans/research/m5/engine-window/probe.sps $(cat port); exec 3>&-; wait; rm -f in port'

A check that the engine holds a token reads the token, never those counts.
