The whole `make test` on the `proto` tree (the cap, and the send limit on the HTTP/2 faces), once
on each lane, and the two failing suites again on lane X:

| lane | suites | failed | log |
|---|---|---|---|
| F 7.85.0 | 41 | `test-conditions`, `test-transfer` | `results/test-proto-floor.log` |
| O 8.5.0 OpenSSL | 41 | `test-conditions`, `test-transfer` | `results/test-proto-openssl.log` |
| G 8.5.0 GnuTLS | 41 | `test-conditions`, `test-transfer` | `results/test-proto-gnutls.log` |
| X 8.20.0 | 41 | `test-conditions`, `test-transfer` | `results/test-proto-guix-8.20.0.log`; again, `-again.log` |
| C 8.23.0 | 41 | `test-conditions`, `test-transfer` | `results/test-proto-current.log` |

(`results/test-proto-docker.log` holds the Docker lanes' summary lines.) Every other suite passed
on every lane, every HTTP/2 suite among them. The tests that answered differently:

- **`test-transfer`, shared: `GET raw /raw/big-header?bytes=102380`**, on all five: it was a 200
  with its one `X-Big` header, and is now `(refused header-limit 23)`. The plan's second case: its
  status line, 17 bytes, and its line of 102,389 bytes take the count to 102,406.
- **`test-transfer`, varying: `GET raw /raw/many-headers?count=50000`**, on all five: each row's
  answer, a 200 of 50,000 headers on 7.85.0, 56 on 8.5.0, 100 on 8.20.0 and 8.23.0, is now
  `(refused header-limit 23)`, the 1,001st line refused. The plan's first case.
- **`test-transfer`, class, by the row: the same case**, on every lane but 7.85.0, whose row
  answers a response and so has no class test: the row's code's class (send-receive for 8.5.0's 56,
  too-large for 100) against the raised `header-limit 23`, of `&curl-too-large`. The same cause.
- **`test-conditions`: "the transfer-error reasons are exactly perform-failed, ...,
  body-not-replayable, in order"**, on all five: the list now ends in `header-limit`. The plan's
  §3.7 expects the written-out lists to grow; it is not among §3.3's two cases, so it is named here.

Nothing else answered differently: the other 39 suites passed on every lane with a header callable
on every transfer. `make test` ran no suite under Valgrind; the cost under the gate is item 2's.
