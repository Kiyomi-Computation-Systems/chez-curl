# M6 slice 3's measurements: my checks (2026-10-31)

I reran the agent's counts from its logs (`../README.md`'s greps), and probed the one finding
its server could not settle: its `/answer-at` sends `Location` exactly when the status is a 3xx,
so "an HTTP/2 3xx never ends" could have been "a response with `Location` never ends". Each
program ran on main's own `src/` (`801c4673…`, printed on each log's first line) through copies
of the agent's runners whose only change is the program's directory (`run.sh.diff`,
`docker.sh.diff`), from `build/m6s3v/`, where they ran.

| File | What it is |
|---|---|
| `probe.sps` | a streamed `post` over `h2` and `raw`, 303, 307, 413 and 200, `Location` and none, sized and chunked, fed throughout; it stops 5 s after the head |
| `whole.sps` | the same with a whole 4 MiB body, as `http-request` sends one, bound 8 s |
| `verbose.sps` | `whole.sps` over `h2`, 303 and 413, with libcurl's `VERBOSE` through the hatch |
| `keepsend.sps` | `whole.sps` over `h2`, 303, 307 and 413, with `KEEP_SENDING_ON_ERROR` at 1 |
| `early-3xx-server.mjs`, `early-3xx-cli.sh` | the bug report's reproduction: curl's own command-line tool against a 30-line Node server, h2c |
| `curl-bug-report.md` | the draft report, for the maintainer to file |
| `results/` | the logs |

## What they showed

- **The status, not `Location`:** over `h2` on 8.20.0, a 303 and a 307 never ended, with
  `Location` and without, sized and chunked, 16 of 16, each cancelled 5 s after its head; a 413
  ended within 0.138 ms of its head, `Location` or not; over `raw` every case ended.
  `grep 'probe face=h2' results/probe-guix.log | grep -o 'status=[0-9]* location=[a-z]*\|ended-own=[a-z]*' | paste - - | sort | uniq -c`
- **8.23.0 the same, 7.85.0 and 8.5.0 not:**
  `grep 'probe face=h2' results/probe-docker.log | grep -o '^\[[^]]*\]\|status=[0-9]* \|ended-own=[a-z]*' | paste - - - | sort | uniq -c`
  (7.85.0's `h2` 200 never ended: slice 2's row.)
- **A whole body too:** 8.20.0's and 8.23.0's `h2` 303 and 307 ended 28 at the 8 s bound, each
  of 6; their 413 ended 413.
  `grep -h 'whole face=h2' results/whole-*.log | grep -o '^\[[^]]*\]\|status=[0-9]* \|outcome=[^ ]*' | paste - - - | sort | uniq -c`
- **libcurl's own account:** for both statuses, "HTTP error before end of send, stop sending",
  then "abort upload"; for the 303, "Operation timed out after 4006 milliseconds with 10 out of
  10 bytes received". `grep -E 'stop sending|abort upload|timed out' results/verbose-guix.log`
- **curl's own tool:** 8.20.0's and 8.23.0's exit 28 for 303 and 307 with "10 out of 10 bytes
  received", and 0 for 413; 7.85.0's exit 0 for every 3xx, and 28 for 200.
  `grep -h '^status=\|^curl ' results/early-3xx-cli-*.log`
- **`KEEP_SENDING_ON_ERROR`:** 8.20.0's `h2` 303 and 307 ended 303 and 307 within 45.241 ms,
  4 of 4. `grep 'whole face' results/keepsend-guix.log`
