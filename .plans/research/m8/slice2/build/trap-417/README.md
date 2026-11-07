# The 417 trap: what the wire shows

**Question.** Under the memory gate, `test-headers`' 417 case sometimes counted a second 417 and
failed `header-limit`. Why? It ran on lane X, Guix's libcurl 8.20.0, in `scripts/guix-env`, on
CPUs 12 to 17, 2026-11-07.

**Setup.** The runs used a copy of the tree, `build/m8s2/trap417.UVSUmD`, made by tar as
before. `make-copy.py` returned `/raw/head417` to its per-connection hold, the route as it was
before the build keyed it ([`origin.patch`](origin.patch)). It also logs every event the route
sees to `logs/RUN.origin.log`:

- the connection, as the client's port;
- the origin's monotonic time;
- each request line, its Expect and Content-Length;
- the body bytes already arrived when the 417 was written, `queued`;
- whether anything came after the 417.

`trap417.sps` makes `test-headers`' request: a POST of 10 digits with `Expect: 100-continue`, to
a 417 of 500 lines and a 200 of 500. That is 1,000 header lines in all, so the request is taken
when libcurl resends on the 417's connection, and refused `header-limit` when it counts a
second 417. Each request ran on an engine of its own, five to a process (two in the `verbose` runs and the first native trial, `n0`), in three variants:

- `fixed`: `EXPECT_100_TIMEOUT_MS` raised to 60,000 through the hatch, as `test-headers` does;
- `plain`: libcurl's own 1,000 ms;
- `verbose`: `fixed` with `VERBOSE` 1.

`run.sh` ran each process under the gate's Valgrind, with its options and its Guix
suppression, or natively.

## Counts

| | runs | requests | refused `header-limit` | taken |
|---|---|---|---|---|
| under the gate, `g1` to `g8` (`fixed` and `plain`, four each) | 8 | 40 | 8, request 0 of every run | 32 |
| under the gate, `v1`, `v2` (`verbose`) | 2 | 4 | 2, request 0 of each | 2 |
| natively, `n1` to `n8` (four each), and `n0`, `vn1` | 10 | 44 | 0 | 44 |

Every Valgrind log reads `ERROR SUMMARY: 0 errors from 0 contexts` (`logs/*.valgrind`).

## The failing runs

The first request of every process under Valgrind failed this way (`g*.origin.log`, the first
lines):

1. Connection A took the whole request head. The route wrote the 417 at once, with `queued=0`:
   no body byte had arrived.
2. Nothing more came on A. The client closed it 56 to 73 ms after the 417, still at `queued=0`
   (`ended-after-417`).
3. libcurl then sent the same request on a new connection B. The route answered 417 again. The
   resend on B got its 100 Continue and its 200.

That makes six connections for five requests in each run. The callable counted two 417s of 500
lines each, then refused the 200's first line.

libcurl's own account, in `v1.out` and `v2.out`:

- the failing request: `Got HTTP failure 417 while sending data`, `abort upload`, `shutting
  down connection #0`, then a new connection;
- every other request, and every native one: `Got HTTP failure 417 while waiting for a 100`,
  `Connection #0 ... left intact`, and the resend reuses it.

## The passing runs

Every later request in a gate run, and every native request, used one connection: the 417 with
`queued=0`, the resend's head as the next bytes, then 100 Continue and the 200. The native logs
show five connections for five requests every time.

## Was the body already being sent?

No byte of it reached the origin before the 417, nor after, on the abandoned connection. The
Expect timeout does not explain the failure either. `fixed` waits 60 s for the 100, and it
failed exactly as `plain` did: request 0 of every run, four of four each.

What libcurl reports instead is its own state when it read the 417. On a process's first
transfer under Valgrind, it still counted itself as sending the request, `while sending data`,
not yet waiting for the 100, though the origin had the whole head. It took the 417 as cutting
an upload short, and shut the connection down. On every later transfer, and every native one,
it had reached its wait for the 100, and it kept the connection.

**Conclusion.** A server that holds its 417 by connection therefore answers that resend 417
again, and the cap counts both. `/raw/head417` now holds its 417 by key, which a resend on any
connection shares.
