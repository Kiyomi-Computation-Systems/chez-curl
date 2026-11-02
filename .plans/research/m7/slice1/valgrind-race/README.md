# Prior knowledge's code under Valgrind (M7 slice 1's build, 2026-11-02)

The slice's builder (Opus) found test-version failing the memory gate on every lane: prior
knowledge to the origin's HTTP/1.1 `http` face fails with one code natively, and mostly with 55
under Valgrind. `test-pkprobe.sps` is test-version as it then stood, with a probe that submits
each case `PROBE_REPS` times (10 by default) and counts the outcomes. It runs as
`tests/test-pkprobe.sps` in a copy of this branch's tree: natively by `make test
SUITES=tests/test-pkprobe.sps`, under the gate by `make test-memory
MEMORY_SUITES=tests/test-pkprobe.sps`; `probe-in-docker.sh` ran it on the four Docker lanes,
30 reps each, in one `--rm ubuntu:24.04`.

| Lane | Native | Under Valgrind |
|---|---|---|
| 7.85.0 | 52 ×30 | 52 ×11, 55 ×18, 16 ×1 |
| 8.5.0, OpenSSL | 56 ×30 | 55 ×30 |
| 8.5.0, GnuTLS | 56 ×30 | 55 ×29, 56 ×1 |
| 8.20.0, Guix | 16 ×10 | 16 ×21, 55 ×9; my rerun, 16 ×7, 55 ×3 |
| 8.23.0 | 16 ×30 | 16 ×22, 55 ×8 |

The builder's reading, not measured further: the face answers the HTTP/2 preface with a 400 and
resets the connection, and the code is a race between that reset and libcurl's next send, which
Valgrind slows. Every other case the probe counted gave one outcome under both. With one code per
row, test-version failed the gate 5 runs of 5 on 8.20.0 (`results/guix-8.20.0-valgrind.log`) and
2 of 2 on each Docker lane (`results/docker.log`); its rows now hold every code seen.
