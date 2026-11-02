# The M7 plan's review probe (2026-11-02)

The plan's adversarial review (Opus, read-only) wrote this probe to check claims the four probes
did not cover. It runs once per lane, through the easy interface, not the engine's loop: spot
checks, not table rows. I reran its Guix lane (`results-guix-rerun.log`), and it matched the
review's log but for the lane's name and the port.

```sh
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL CURL_INCLUDE=$GUIX_ENVIRONMENT/include sh .plans/research/m7/review/run.sh guix-8.20.0' < /dev/null
```

The Docker lanes ran in `ubuntu:24.04`, each against its own headers;
`results-floor-7.85.0-docker.log` is the floor.

| Case | What it shows |
|---|---|
| `bearer-crlf` | a Bearer token holding CR LF writes a header of its own, `X-Injected: 1`, on all five |
| `digest-user-crlf` | the same bytes as a Digest user name inject on four lanes; 8.23.0 percent-encodes them |
| `authz-beside-basic`, `authz-beside-bearer` | with a caller's `Authorization` header, libcurl sends only the caller's, and drops its own credentials |
| `authz-beside-digest` | Digest's second request carries two `Authorization` headers, libcurl's and the caller's |
| `awssigv4-after-basic` | `AWS_SIGV4` set after `HTTPAUTH` Basic replaces Basic with an `AWS4-HMAC-SHA256` signature |
| `cookie-ctl01` | a loaded cookie value holding 0x01 is stored and sent raw before 8.23.0, and dropped, rc 0, on 8.23.0 |
| `cookie-empty-name` | an empty-name Netscape line loads as name `v` on 7.85.0 and 8.5.0, and as an empty name on 8.20.0 and 8.23.0 |
| `cookie-cr` | a CR cuts the value, silently, on all five |
| `url …` lines | what `curl_url` reports as the user and password of `http://@h/`, `http://:@h/`, `http://u@h/` and `http://:p@h/`: 7.85.0 reports no user where 8.5.0 and later report `""` |
