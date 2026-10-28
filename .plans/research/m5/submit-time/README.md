# A submit's time inside the drive's critical section (M5 slice 1's review, 2026-10-27)

`probe.sps` submits a `post` with a body of 1, 64 and 256 MB inside `critical-section`, as the
drive does, and prints how long the submit took: `prepare-transfer` copies the body there.
`results/guix-8.20.0.log`, three runs in the container, from the repository's root:

    scripts/guix-env sh -c 'for i in 1 2 3; do $CHEZ --libdirs src -q --program .plans/research/m5/submit-time/probe.sps; done'

 0.2 ms for 1 MB, 48.3 to 51.2 ms for
64 MB, and 207.5 to 226.9 ms for 256 MB. For that long Ctrl-C waits, and so does every other
thread's collection.
