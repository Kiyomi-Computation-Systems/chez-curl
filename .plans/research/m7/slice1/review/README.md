# M7 slice 1's review probes (2026-11-02)

The slice's adversarial review (Opus, read-only) wrote these to check two claims; I reran each on
Guix's 8.20.0 (`*-rerun.log`), and each matched its log but for the ports. Both ran on the
slice's tree before `ALTSVC_CTRL` was owned: on the final tree the hatch refuses it, and
`altsvc417.sps`'s cases with it raise `owned-option`.

```sh
scripts/guix-env sh -c 'make deps && $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m7/slice1/review/altsvc417.sps' < /dev/null
scripts/guix-env sh -c 'make deps && $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m7/slice1/review/pool.sps' < /dev/null
```

- **`altsvc417`:** a `post` with a caller's `Expect: 100-continue` to a TLS face that answers
  417 with `Alt-Svc`, then 200. With the hatch's `ALTSVC_CTRL` 24 alone, no `ALTSVC` file, the
  transfer's resend went to the alternative: face c, another port, at `#f` and at `http/1.1`;
  face d over HTTP/2 at `#f`. Without it every case ended on face a. So `ALTSVC_CTRL` moves a
  request inside one transfer, which the measurement, reading it across transfers, could not
  see.
- **`pool`:** on one engine, a request by prior knowledge to h2c, then one with the version
  `#f` or `http/2` to h2c, reads HTTP/2 over the pooled connection, where the same request alone
  fails 1; `http/1.1` does not reuse it. Measured on 8.20.0 alone.
