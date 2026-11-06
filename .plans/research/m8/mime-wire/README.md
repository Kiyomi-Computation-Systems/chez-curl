# M8 research: what a mime body puts on the wire

Measured 2026-11-06 for the M8 plan, area multipart ([ADR-0038](../../../decisions/0038-m8s-scope.md),
decision 1). It records what each libcurl sends for a `curl_mime` body set by `MIMEPOST`, beside the
headers and options a chez-curl transfer sets today. It reports what libcurl does. It recommends
nothing.

## In short

- **The head is the same on all five lanes.** libcurl sends `POST`, `Content-Type:
  multipart/form-data; boundary=B` and a `Content-Length` (never chunked) for data parts and a
  regular file's part. There is no `Expect` up to 1 MiB, over HTTP/1.1 and HTTP/2 alike. `B` is 24
  dashes and then 16 lower-case hex characters on 7.85.0 (40 in all). On 8.5.0, 8.20.0 and 8.23.0
  it is 24 dashes and 22 alphanumerics (46).
- **Today's blank `Content-Type:` breaks the form on every lane.** With it, libcurl sends
  `Content-Type: ; boundary=B`, a parameter with no media type. Every part's disposition also
  becomes `attachment`, not `form-data`. `Content-Type;` does the same. The body still parses by
  `B`. The blank `Expect:` removes libcurl's own `Expect`.
- **A caller's `Content-Type` keeps its media type, and libcurl always appends `; boundary=B`.**
  A value with a boundary of its own goes out with two `boundary=` parameters, the caller's first,
  so a reader that takes the first one cannot parse the body. A data part that holds the caller's
  delimiter then reads, to a reader that skips a preamble, as a part the caller wrote. Any media
  type but `multipart/form-data` turns every part's disposition to `attachment`.
- **`Expect: 100-continue` comes past 1 MiB alone, and over HTTP/1.1 alone.** It goes out at
  1,048,577 bytes, not at 1,048,575, 1,025 or 1,023. A caller's `Expect: 100-continue` is sent and
  waited on at every size, over HTTP/2 too, on all five lanes. With no 100 the wait is 1000.3 to
  1006.0 ms by default, and 299.6 to 303.3 ms at `EXPECT_100_TIMEOUT_MS` 300. At 0 there is no
  wait.
- **Part metadata.** By default a name or filename has `"`, CR and LF percent-encoded, and every
  other byte sent raw, `%` among them, so `a%22b` and `a"b` arrive alike. Under
  `CURLMIMEOPT_FORMESCAPE`, `\` and `"` get a backslash, and CR and LF go out raw, splitting the
  header, on 7.85.0, 8.5.0 and 8.20.0. 8.23.0 refuses that transfer with 43 and sends nothing. A
  part's type is sent raw everywhere: CR LF in it writes a header of the caller's own into the
  part, on every lane, under both options.
- **Twins: the last body option set wins, with one split.** `UPLOAD 1` and then `MIMEPOST` sends a
  PUT of stdin on 7.85.0 (libcurl's default read callback), and the mime body on 8.5.0 and later.
  `UPLOAD 1` or `POST 1` set after `MIMEPOST` reads stdin on every lane. `POSTFIELDSIZE` and
  `POSTFIELDSIZE_LARGE` do nothing beside `MIMEPOST`, and a read callback beside it is never
  called.
- **`CURLINFO_REQUEST_SIZE` counts the head alone on 7.85.0 and 8.5.0, and the head and the body
  on 8.20.0 and 8.23.0.** `SIZE_UPLOAD_T` and `CONTENT_LENGTH_UPLOAD_T` are the bytes the server
  read, on every lane.
- **No cell split between runs.** Every case ran twice on each lane, and the Expect case three
  times. One order races and changes nothing sent: at `EXPECT_100_TIMEOUT_MS` 0, whether a 100
  reaches libcurl before its first body byte. Apple's 8.7.1 is not measured yet: `mac.sh` is
  written, and the maintainer runs it.

## What was run

`probe.c` drives libcurl's multi interface in the engine's turn: `curl_multi_perform`,
`curl_multi_info_read`, then `curl_multi_poll` for at most 1000 ms. Each transfer runs on a fresh
multi handle, so no connection is reused, and gets the options a chez-curl transfer sets today
(`src/curl/private/transfer.sls`, `set-transfer-options!`):

- the pins: `PROTOCOLS_STR` and `REDIR_PROTOCOLS_STR` `http,https`, `NOSIGNAL` 1, `MAXREDIRS` 30,
  and `QUICK_EXIT` 1 where libcurl knows it;
- `ERRORBUFFER`, the URL by `CURLU`, `WRITEFUNCTION`, and `PROXY` `""`;
- on https: `SSL_VERIFYPEER` 1, `SSL_VERIFYHOST` 2, `CAINFO`, and `CAPATH` cleared;
- on each multi handle: `CURLMOPT_QUICK_EXIT` 1 where it is known, and `CURLMOPT_PIPELINING` 0 on
  8.7.x (the Mac).

Then the case sets its body and headers. `VERBOSE` and a debug callback watch every transfer.
They record the head libcurl says it sent, its text, and the time from the head to the first body
byte (`wait_ms`). They change nothing sent: over HTTP/1.1, the head the server read equals the
head libcurl reports, byte for byte, in every transfer that sent one (the checks below).

The probe's stdin is a file holding `PROBE-STDIN-MARKER`, rewound before each transfer, so a body
that libcurl's default read callback took from stdin shows it (`stdin=1`). The read callback some
twins set gives `READFUNCTION-BODY\n` (`readfn=1`).

`server.mjs` is a stand-in on Node's standard library alone. Every face runs one handler, which
reads the whole body by its framing and answers 200, `ok\n`:

| face | scheme | what it serves |
|---|---|---|
| `h1` | http | HTTP/1.1, parsed by hand from the bytes |
| `tlsh1` | https | ALPN `http/1.1` only, then the `h1` handler |
| `tlsh2` | https | ALPN `h2`, so libcurl's default (`2TLS`) speaks HTTP/2; `node:http2` |
| `h2c` | http | HTTP/2 by prior knowledge (the probe sets `HTTP_VERSION` `2_PRIOR_KNOWLEDGE`) |
| `ctl` | http | control, never logged: each transfer's lines, by its tag |

What the stand-in logs for each request:

- the head: over HTTP/1.1, the whole head as it arrived; over HTTP/2, every header in
  `rawHeaders`' order;
- the body: its framing, its length, its SHA-256, and when its first and last bytes came;
- the whole body, when it is 8 KiB or less;
- the body read strictly by the first `boundary=` sent (`mp`);
- the same body read as RFC 2046 lets a reader, a preamble skipped (`mpl`);
- every part's header lines as they arrived (`pline`).

On the query, `cont=1` answers an `Expect: 100-continue` with 100 as the head arrives, and `cont=0`
never does. A body not whole 4 s after its head is answered anyway and logged (`incomplete=1`).

Escaping, everywhere: printable ASCII as is, `\` as `\\` and `"` as `\"`, CR as `\r` and LF as
`\n`, and any other byte as `\xNN`.

The cases (each a probe run, `probe.c`'s header):

| case | question | what it does | faces | transfers |
|---|---|---|---|---|
| H | 1, 2, 8 | one data part, two, and a file part (`f.txt`, 512 bytes); no `HTTPHEADER`, then today's blanks | all four | 24 |
| T | 3 | two data parts beside a caller's `Content-Type` and `Expect:` | all four | 24 |
| E | 4, 8 | bodies of 1,023, 1,025, 1,048,575 and 1,048,577 bytes; no header, `Expect:`, or a caller's `Expect: 100-continue`; `cont` 1 and 0; `EXPECT_100_TIMEOUT_MS` unset, 300 and 0 | all four | 290 |
| M | 5 | a part's name, filename or type set to each of 20 values, a part `z` after it; `MIME_OPTIONS` unset and `FORMESCAPE` | `h1` | 120 |
| D | 6 | defaults and side effects | `h1` | 24 |
| W | 7 | `MIMEPOST` beside each body and method option, in each order | `h1` | 29 |
| S | 9 | 1, 2 and 8 data parts of 100 bytes, and a file part beside a data part | all four | 16 |

E's sizes are the whole body's. A calibration transfer first sends a 0-byte part, and its
`CONTENT_LENGTH_UPLOAD_T` is subtracted from each size to give the data. That overhead is 136
bytes on 7.85.0 and 148 on the others (`D1:1363`, `D1:14954`, `X1:1112`). Every E body arrived at
exactly its size: 288 of 288 in each of the fifteen lane-runs, the planted `tmo-65836` aside
(`tables.mjs`'s checks).

**The lanes**, run from the repository's root, on CPUs 0-5 (`taskset`; Docker's `--cpuset-cpus`):

```sh
taskset -c 0-5 scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m8/mime-wire/run.sh guix-8.20.0' < /dev/null > .plans/research/m8/mime-wire/results/guix-8.20.0.log 2>&1
sh .plans/research/m8/mime-wire/docker.sh > .plans/research/m8/mime-wire/results/docker.log 2>&1
```

| lane | where | libcurl | TLS, nghttp2 | headers | Node |
|---|---|---|---|---|---|
| F `floor-7.85.0` | Docker `ubuntu:24.04` (`sha256:68ee2200…`), `--network none` | `build/e1/ci/curl-floor` 7.85.0 | OpenSSL 3.0.13, 1.59.0 | its own | 20.10.0 |
| O `ubuntu-openssl-8.5.0` | same | `libcurl4t64` 8.5.0-2ubuntu10.16 | OpenSSL 3.0.13, 1.59.0 | `libcurl4-openssl-dev` | 24.18.0 (Guix store) |
| G `ubuntu-gnutls-8.5.0` | same | `libcurl3t64-gnutls` 8.5.0-2ubuntu10.16 | GnuTLS 3.8.3, 1.59.0 | as O | 24.18.0 |
| X `guix-8.20.0` | Guix container | the profile's 8.20.0 | GnuTLS 3.8.13, 1.69.0 | the profile's | 24.18.0 |
| C `current-8.23.0` | Docker, as F | `build/verify/c823/lane1/curl-current` 8.23.0 | OpenSSL 3.0.13, 1.59.0 | its own | 24.18.0 |
| Mac `mac-8.7.1` | the maintainer's Mac | Apple's 8.7.1 by `-lcurl` | SecureTransport | the SDK's | asdf's |

The image, the packages, the loopback-only network and the six CPUs are `D1:1-10`. The version
lines are `D1:13`, `D1:13629`, `D1:26861`, `D1:38685` and `X1:3`, and each lane's headers match its
runtime. Every lane ran on Linux x86_64.

**Logs** (`results/`), and the keys used below:

| key | file | runs |
|---|---|---|
| `X1`, `X2` | `guix-8.20.0.log`, `guix-8.20.0-2.log` | lane X, every case; same line numbers |
| `D1`, `D2` | `docker.log`, `docker-2.log` | lanes F, O, G and C in that order, every case; same line numbers |
| `X3`, `D3` | `guix-8.20.0-E3.log`, `docker-E3.log` | a third run of case E alone, every lane |
| `M` | `mac-8.7.1.log` | not yet run: `mac.sh` writes it, two runs |

A citation names the first run. `tables.mjs` holds every cell to every run, and found none that
differs.

**Checks** (`tables.mjs`'s last section; rerun it to see them):

- A lane-run is one lane's one log: ten full runs and five E3 runs.
- Every probe run ended `exit=0`: 7 in each full run, and 1 in each E3 run.
- Every transfer has a `done` line: 527 in each full run, and 290 in each E3 run.
- No transfer gave up, no log fetch failed, no request was still open at a fetch, and the server
  wrote nothing on stderr.
- Every transfer that sent a request sent one, never two.
- Over HTTP/1.1 the head the server read equals the head libcurl reports, in all 351 (F, O, G, X)
  or 341 (C) per run, and 146 per E3 run.
- Over HTTP/2 every request's `content-length` equals the DATA bytes read (question 8).
- No setopt and no `curl_mime_*` call answered other than 0.
- The only non-zero codes are 8.23.0's ten 43s (question 5).
- The only incomplete body is the planted `tmo-65836` transfer (question 4). Every other E body
  arrived at its size.

**The instrument, seen failing:**

- the strict parse fails on a caller's boundary, and the lenient one finds a smuggled part
  (`D1:816`, `D1:915`);
- the stdin marker shows in two twins (question 7);
- the read callback's marker shows (`readfn=1`);
- the 4 s bound fires (`X1:7358`);
- a 100 is seen (`t_100`) only where `cont=1` and an `Expect` went out.

## Question 1: the head

Each cell holds for both runs of every lane. `B` is libcurl's random boundary, and `CL=body`
means `Content-Length` equals the bytes the server read.

| body | face | what went out |
|---|---|---|
| one data part `a`=`alpha` | every face | `POST`; `Content-Type: multipart/form-data; boundary=B`; `CL=body`; no `Expect`; parses, 1 part |
| two data parts | every face | the same; 2 parts |
| a file part, `f.txt` | every face | the same; 1 part, `Content-Disposition: form-data; name="f"; filename="f.txt"`, `Content-Type: text/plain`, 512 bytes, the file's SHA-256 |

- **The bytes**, 7.85.0, `D1:244` and `D1:249`:

  ```
  POST /echo?... HTTP/1.1\r\nHost: 127.0.0.1:33431\r\nAccept: */*\r\nContent-Length: 242\r\nContent-Type: multipart/form-data; boundary=------------------------c4665bf29fe9bc22\r\n\r\n
  --------------------------c4665bf29fe9bc22\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nalpha\r\n--------------------------c4665bf29fe9bc22\r\nContent-Disposition: form-data; name=\"b\"\r\n\r\nbravo-bravo\r\n--------------------------c4665bf29fe9bc22--\r\n
  ```

  8.20.0's, the same shape with `boundary=------------------------IrI9iAnBjrDDIhXOiqjo26` (`X1:193`,
  `X1:198`). The order of the headers is the same on every lane.
- **The boundary:** F `24 dashes + 16 hex` (40 characters); O, G, X and C `24 dashes + 22
  alphanumerics` (46). The `Content-Type`'s boundary is the one the body uses, in every H transfer.
- **The sizes:** one part, F 141 and the rest 153; two parts, F 242 and the rest 260; the file,
  F 692 and the rest 704. The 6-character difference is per delimiter.
- **The file part** arrived whole (512 bytes, SHA-256 `a6c62a340c7a1a1e…`, `D1:14087`).

## Question 2: today's blanks

`HTTPHEADER` holds `Content-Type:` and `Expect:`, as a transfer with a body sets them today
(`transfer.sls`, `sent-header-lines`).

| body | every face, every lane |
|---|---|
| one data part | `Content-Type: ; boundary=B`; `CL=body`; no `Expect`; parses, 1 part; disposition **`attachment`** |
| two data parts | the same; 2 parts, both `attachment` |
| a file part | the same; `Content-Disposition: attachment; name="f"; filename="f.txt"` |

- **The boundary is not lost; the media type and `form-data` are.** 7.85.0 sends `content-type=";
  boundary=------------------------07d69a0e1addd7d6"` (`D1:359`). Its body reads
  `Content-Disposition: attachment; name=\"a\"` (`D1:363`). 8.23.0 does the same (`D1:38976`,
  `D1:38980`), and so does 8.20.0 over h2c, `content-type: ; boundary=...` (`X1:358`).
- **Each part is 1 byte longer:** `attachment` against `form-data`, so the bodies are 154, 262 and
  705 bytes against 153, 260 and 704.
- **The blank `Expect:`** removes libcurl's own `Expect` at 1,048,577 bytes, on every face and
  lane (question 4).

## Question 3: a caller's `Content-Type`

Two data parts, `HTTPHEADER` the caller's line and then `Expect:`.

| the caller's line | what went out, every face and lane | strict parse by the first boundary | lenient parse | dispositions |
|---|---|---|---|---|
| `Content-Type: multipart/form-data` | `multipart/form-data; boundary=B` | ok, 2 parts | 2: `a`, `b` | `form-data` |
| `... multipart/form-data; boundary=caller-boundary-0123456789` | `multipart/form-data; boundary=caller-boundary-0123456789; boundary=B` | **fails**: the body does not begin with the caller's delimiter | none | `form-data` (by the body's bytes) |
| the same, a part's data holding `--caller-boundary-0123456789` and a part | as above | fails | **1 part, `smuggled`** | `form-data` (by the body's bytes) |
| `Content-Type: multipart/mixed` | `multipart/mixed; boundary=B` | ok, 2 parts | 2 | **`attachment`** |
| `Content-Type: text/plain` | `text/plain; boundary=B` | ok, 2 parts | 2 | **`attachment`** |
| `Content-Type;` | `; boundary=B` | ok, 2 parts | 2 | **`attachment`** |

- The two-boundary header is `D1:811`. The strict parse failing on it is `D1:816`. The smuggled
  part is `D1:915` on 7.85.0 (a 90-byte preamble) and `D1:39442` on 8.23.0 (96).
- `multipart/mixed` on 8.5.0 (GnuTLS) is `D1:27696`. `text/plain` on 8.5.0 (OpenSSL) is
  `D1:14716`. `Content-Type;` on 8.20.0 is `X1:1004` and `X1:1008`.
- libcurl appends `; boundary=B` to whatever the caller names, even `text/plain`.

## Question 4: `Expect: 100-continue`

One data part, the whole body of each size. "Sent" is the server's view; the wait is from the
head to the first body byte, by libcurl's debug callback. Every cell holds on all five lanes, in
all three runs.

| body | no `HTTPHEADER` | `Expect:` | caller's `Expect: 100-continue` |
|---|---|---|---|
| 1,023 | not sent | not sent | sent, on every face |
| 1,025 | not sent | not sent | sent, on every face |
| 1,048,575 | not sent | not sent | sent, on every face |
| 1,048,577 | **sent on `h1` and `tlsh1`; not on `tlsh2` or `h2c`** | not sent | sent, on every face |

Where it was sent:

| server | `EXPECT_100_TIMEOUT_MS` unset | 300 | 0 |
|---|---|---|---|
| `cont=1`: answers 100 at once | the body follows the 100, 0.1 to 0.3 ms after the head over HTTP/1.1 and 0.1 to 0.7 ms over HTTP/2 (270 transfers); never before it | the same: 0.1 to 0.3 and 0.1 to 0.8 ms (270) | **no wait** (at most 0.4 ms, 270): the body starts before the 100, or in the same 0.1 ms tick, but for 3 of 24 transfers on G over HTTP/2 |
| `cont=0`: never answers 100 | **waits 1000.3 to 1006.0 ms**, then sends (270) | **299.6 to 303.3 ms** (270) | no wait (at most 0.9 ms, 270) |

Each count is every transfer of that cell where an `Expect` went out: 18 per lane-run, over five
lanes and three runs (`tables.mjs`, "Q4 every transfer an Expect went out on", with the order per
lane at 0). At 0 the order of the 100 and the first body byte is a race under 0.4 ms. It changes
nothing sent.

- **The threshold is 1 MiB:** 1,048,575 goes out without `Expect` (7.85.0 `D1:5566`, 8.20.0
  `X1:4546`), and 1,048,577 with it (`D1:7451`, `X1:6077`). 1,025 goes out without (`D1:3636`).
- **libcurl's own `Expect` is HTTP/1.1 only.** At 1,048,577 bytes the HTTP/2 heads carry
  `content-length` and no `expect` (7.85.0 `D1:7511`, 8.23.0 `D1:44961`).
- **A caller's `Expect: 100-continue` holds HTTP/2 too:** 7.85.0 sends `expect: 100-continue` over
  h2c and waits 1004 ms for a 1,023-byte body (`D1:3075`, `D1:3073`), as 8.20.0 does over `tlsh2`
  (`X1:2485`). Over HTTP/2 the stand-in's 100 (an informational `:status 100`) ends the wait too.
- **The waits per row** are `tables.mjs`'s "Q4 the waits", over all three runs. The default wait
  was 1000.3 to 1006.0 ms on every lane, and 300 gave 299.6 to 303.3 ms.
- **The setting's range:**
  - `EXPECT_100_TIMEOUT_MS` -1 is refused with 43 on every lane, and 65535, 65536 and 70000 are
    taken with 0 (`D1:9029` for F, `D1:22445`, `D1:34333`, `D1:46214`, `X1:7364`).
  - At 65836, 300 ms past 65535, the wait is not truncated to 300 ms. The stand-in's 4 s bound
    answered first, with the body unsent, on every lane (`X1:7352`, `X1:7358`; F `D1:9017`).
  - Whether 65836 is clamped to 65535 or kept was not waited for. 8.20.0's and 8.23.0's source
    clamps it to 0xffff (`lib/setopt.c`, `value_range`), and 7.85.0's and 8.5.0's keep the `long`.
- **That planted transfer ended 0, status 200,** with `size_upload` 0 against
  `content_length_upload` 1048577. libcurl took the early 200 as the answer and never sent the
  body (`X1:7352`).

## Question 5: part metadata bytes

Each value is `a`, the byte, `b`, unless named; the field is set alone, and a part `z`=`zz`
follows. Over `h1`. Below, each line is part 1's header lines as they arrived, `|` between lines.
Every cell holds on all five lanes, in both runs, unless it names lanes.

**The name** (the filename is the same, inside `; filename="..."` after `name="n"`):

| value | `MIME_OPTIONS` unset | `FORMESCAPE` |
|---|---|---|
| `"` | `name="a%22b"` | `name="a\"b"` |
| `\` | `name="a\b"` | `name="a\\b"` |
| CR | `name="a%0Db"` | F O G X: `name="a` CR `b"`, raw. C: **43, nothing sent** |
| LF | `name="a%0Ab"` | F O G X: raw LF. C: 43 |
| CR LF | `name="a%0D%0Ab"` | F O G X: `name="a` \| `b"`, **the line split**. C: 43 |
| tab, 0x01, 0x1F, 0x7F | raw (`\x09`, `\x01`, `\x1f`, `\x7f`) | raw |
| `;`, `=`, `%`, space | raw | raw |
| `é` (C3 A9), raw E9 | raw (`\xc3\xa9`, `\xe9`) | raw |
| empty | `name=""` | `name=""` |
| `a%22b` | `name="a%22b"`, **the same as `a"b`** | `name="a%22b"` |
| `a` CR LF `X-Injected: 1` | `name="a%0D%0AX-Injected: 1"` | F O G X: `name="a` \| `X-Injected: 1"`. C: 43 |
| `a` CR LF CR LF `INJECTED-DATA` | `name="a%0D%0A%0D%0AINJECTED-DATA"` | F O G X: the headers end at `name="a`, and `INJECTED-DATA"` begins the part's data. C: 43 |
| `a"; filename="evil.sh` | `name="a%22; filename=%22evil.sh"` | `name="a\"; filename=\"evil.sh"` |

**The type** (`Content-Type:` in the part), the same under both options on every lane:

| value | the part's lines |
|---|---|
| `"`, `\`, `;`, `=`, `%`, space, tab, 0x01, 0x1F, 0x7F, `é`, raw E9 | `Content-Type: a` the byte `b`, raw |
| CR, LF | raw: `Content-Type: a\rb`, `Content-Type: a\nb` |
| CR LF | `Content-Type: a` \| `b`: **a line of its own** |
| empty | `Content-Type: ` |
| `a` CR LF `X-Injected: 1` | `Content-Type: a` \| **`X-Injected: 1`** |
| `a` CR LF CR LF `INJECTED-DATA` | `Content-Type: a`; the part's data is `INJECTED-DATA\r\n\r\nv` |
| `a"; filename="evil.sh` | `Content-Type: a"; filename="evil.sh` |

- **The citations, on 7.85.0:**
  - `name="a%22b"` (`D1:9056`), `a%22b` the same (`D1:9440`), and `\` raw (`D1:9080`);
  - raw E9 (`D1:9392`), and CR LF encoded (`D1:9152`);
  - under `FORMESCAPE`, the split (`D1:10615`), with 8.20.0's `X-Injected` line at `X1:9185`;
  - the type's injected header (`D1:10444`; 8.23.0 `D1:47571`), and its injected data
    (`D1:10467`).
- **8.23.0's 43** comes before any request: no head, no server line (`D1:47671`). It holds for CR
  or LF in a name or filename under `FORMESCAPE` alone, the ten M transfers that hold one.
  8.23.0's source refuses such a value in the backslash strategy (`lib/mime.c:1762-1765`). The
  sources of 7.85.0, 8.5.0, 8.7.1 and 8.20.0 hold no such check.
- **No `curl_mime_name`, `curl_mime_filename` or `curl_mime_type` call refused a value:** each
  answered 0, the NUL-free ones measured here.
- **The bytes that let a caller write a header of their own:**
  - CR LF in a part's type, on every lane, under both options;
  - CR LF in a name or filename under `FORMESCAPE`, on 7.85.0, 8.5.0 and 8.20.0.

  A lone CR or LF goes out raw in the same places.
- **Writing a part of their own.** The caller cannot do it through the name, filename or type,
  because the delimiter is libcurl's random `B`. CR LF CR LF in the type moves bytes into the
  part's data, not into a new part. A caller's boundary in `Content-Type` does it (question 3).

## Question 6: defaults

Over `h1`; every cell holds on all five lanes, in both runs. The citations are 7.85.0's (`D1`).

| part | its header lines | data | line |
|---|---|---|---|
| data, no type | `Content-Disposition: form-data; name="a"` | 5 | `D1:11985` |
| file `t.txt`, no type | `...; name="f"; filename="t.txt"` \| `Content-Type: text/plain` | 19 | `D1:12007` |
| file `t.html` | `filename="t.html"` \| `Content-Type: text/html` | 14 | |
| file `t.bin` | `filename="t.bin"` \| `Content-Type: application/octet-stream` | 10 | `D1:12053` |
| file `t`, no extension | `filename="t"` \| `Content-Type: application/octet-stream` | 16 | `D1:12076` |
| data, filename `d.txt` | `...; name="a"; filename="d.txt"` \| `Content-Type: text/plain` | 5 | `D1:12099` |
| data, filename `d.html` | `filename="d.html"` \| `Content-Type: text/html` | 5 | |
| data, filename `d.bin`, or `d` | `filename="d.bin"`, no `Content-Type` | 5 | `D1:12122` |
| data, no name | `Content-Disposition: form-data` | 4 | `D1:12189` |
| data, no name, filename `x.txt` | `Content-Disposition: form-data; filename="x.txt"` \| `Content-Type: text/plain` | 4 | |
| two parts, one name | `name="dup"` twice, both sent | 3, 3 | `D1:12234` |
| `curl_mime_filedata` of `FILES/a/b/c.txt` | `name="f"; filename="c.txt"` \| `Content-Type: text/plain` | 16 | `D1:12258` |
| the same, then `curl_mime_filename(part, NULL)` | `name="f"` alone: **no filename and no type** | 16 | `D1:12281` |
| `t.bin` by `filedata`, then the filename withdrawn | `name="f"` alone | 10 | |
| `filedata`, then filename `other.bin` | `filename="other.bin"` \| `Content-Type: text/plain`, **the path's type** | 16 | `D1:12325` |
| filename `first.bin`, then `filedata` | `filename="c.txt"`: `filedata` replaced it | 16 | `D1:12348` |
| file `t.txt`, type `application/x-chez` | `filename="t.txt"` \| `Content-Type: application/x-chez` | 19 | |
| data, type `text/plain` given | `name="a"` \| `Content-Type: text/plain` | 5 | `D1:12394` |
| a mime with no parts | the body is `--B--\r\n` alone (46 bytes on 7.85.0) | | `D1:12416` |
| a part with a name and no data call | `name="nodata"`, 0 bytes | 0 | `D1:12437` |
| data of 0 bytes | `name="e"`, 0 bytes | 0 | |
| `"abc\0def"`, `CURL_ZERO_TERMINATED` | 3 bytes, `abc` | 3 | `D1:12481` |
| `"abc\0def"`, 7 bytes | 7 bytes, the NUL sent | 7 | `D1:12503` |

**Where a part's type comes from.** The rules below fit every row above, and match
`Curl_mime_prepare_headers` in 7.85.0's source (`lib/mime.c:1787-1821`):

- A data part's type comes from its filename's extension alone. A part with no filename, or with
  an extension libcurl does not know, gets no type.
- A file part's type comes from its filename's extension, else its path's, else
  `application/octet-stream` when it has a filename.
- A `text/plain` found that way is dropped from a part with no filename: the withdrawn row.

## Question 7: methods and twins

One data part `a`=`alpha`; no `HTTPHEADER`; over `h1`. "Mime" is the multipart body with
`Content-Type: multipart/form-data; boundary=B` and `CL=body`. Every cell holds on all five
lanes, in both runs, unless it names lanes. The citations are 7.85.0's `req` lines.

| options, in the order set | method | body | line |
|---|---|---|---|
| `CUSTOMREQUEST` `PUT`, `PATCH`, `DELETE` or `GET`, then `MIMEPOST` | that method | mime | `D1:12522`, `D1:12566`, `D1:13106` |
| `NOBODY` 1, then `MIMEPOST` | POST | mime | `D1:12588` |
| `MIMEPOST`, then `NOBODY` 1 | HEAD | none: no `Content-Type`, no length | `D1:12609` |
| `UPLOAD` 1, then `MIMEPOST` | **F: PUT. O G X C: POST** | **F: stdin, chunked, `Expect: 100-continue`, no `Content-Type`. O G X C: mime** | F `D1:12630`; O `D1:25894`; X `X1:10814` |
| `MIMEPOST`, then `UPLOAD` 1 | PUT | **stdin**, chunked (19 and 0), `Expect: 100-continue` | `D1:12651` |
| `MIMEPOST`, then `READFUNCTION`, `INFILESIZE` 18, `UPLOAD` 1 | PUT | the read callback's 18 bytes; F with `Expect: 100-continue`, O G X C without | `D1:12672`, `D1:25934` |
| `MIMEPOST` and `READFUNCTION` with `INFILESIZE` 18, either order | POST | mime; the read callback is never called (`read_calls=0`) | `D1:12691` |
| `POSTFIELDS`, `COPYPOSTFIELDS` or the engine's pair (`POSTFIELDSIZE_LARGE` 18, `COPYPOSTFIELDS`), then `MIMEPOST` | POST | mime | `D1:12735`, `D1:12815` |
| `MIMEPOST`, then any of those | POST | **that body**, `Content-Type: application/x-www-form-urlencoded` | `D1:12756`, `D1:12796`, `D1:12836` |
| `POSTFIELDSIZE` 5, either order; `POSTFIELDSIZE_LARGE` 5 or -1 after | POST | mime, its own length | `D1:12877`, `D1:12921` |
| `HTTPPOST`, then `MIMEPOST` | POST | mime (`a`) | `D1:12943` |
| `MIMEPOST`, then `HTTPPOST` | POST | the `HTTPPOST` form, part `hp` | `D1:12965`, `D1:12971` |
| `POST` 1, then `MIMEPOST` | POST | mime | `D1:12987` |
| `MIMEPOST`, then `POST` 1 | POST | **stdin**, chunked, `application/x-www-form-urlencoded`, `Expect: 100-continue` | `D1:13011` |
| `MIMEPOST`, then `POST` 0 or `HTTPGET` 1 | GET | none | `D1:13029`, `D1:13047` |
| `HTTPGET` 1, then `MIMEPOST` | POST | mime | |
| `MIMEPOST`, then `MIMEPOST` `NULL` | POST | none: `Content-Length: 0`, no `Content-Type` | `D1:13087` |

- **One body at a time.** `MIMEPOST`, `POSTFIELDS`, `COPYPOSTFIELDS`, `HTTPPOST`, `UPLOAD` and
  `POST` 1 each pick the body. The last one set wins, but for 7.85.0's `UPLOAD` before `MIMEPOST`.
- **Two twins read stdin through libcurl's default read callback**, with no read callback set:
  `UPLOAD` 1 or `POST` 1 after `MIMEPOST`, on every lane. 7.85.0 also reads it for `UPLOAD` 1
  before `MIMEPOST`.

## Question 8: framing over HTTP/2

From H and E on `tlsh2` (ALPN `h2`) and `h2c` (prior knowledge). Every cell holds on all five
lanes, in all their runs.

- **`content-length` is always sent,** and equals the DATA bytes the server read, in every
  request over HTTP/2: 2,480 over the fifteen lane-runs (`tables.mjs`'s checks). 7.85.0's head is `:method: POST | :path: ... | :scheme: https |
  :authority: ... | accept: */* | content-length: 141 | content-type: multipart/form-data;
  boundary=...` (`D1:94`). 8.20.0 sends the pseudo-headers in another order, `:method`, `:scheme`,
  `:authority`, `:path` (`X1:64`).
- **No `expect` from libcurl's own rule,** at any size (`D1:7511`, `D1:44961`). A caller's
  `Expect: 100-continue` is sent as `expect: 100-continue` and waited on (question 4).
- **The blank's `content-type: ; boundary=...`** went through node's HTTP/2 server without a
  stream error (`X1:358`).
- **DATA:** 1,048,577 bytes, each byte read, on every lane. The stand-in counts Node's `data`
  events, not frames, so the frame count is not measured.

## Question 9: size

`CURLINFO_REQUEST_SIZE`, against the head bytes the server read over HTTP/1.1, and `SIZE_UPLOAD_T`
and `CONTENT_LENGTH_UPLOAD_T`, against the body bytes it read. Every cell holds on both runs of
each lane.

| lane | `REQUEST_SIZE` over HTTP/1.1 | over HTTP/2 | `SIZE_UPLOAD_T`, `CONTENT_LENGTH_UPLOAD_T` |
|---|---|---|---|
| F 7.85.0 | the head's bytes, exactly | about the head's size | the body's bytes |
| O, G 8.5.0 | the head's bytes, exactly | about the head's size | the body's bytes |
| X 8.20.0, C 8.23.0 | **the head's bytes plus the body's** | about the head plus the body | the body's bytes |

- **One part of 100 bytes, over `h1`:**
  - F: `request_size` 190, head 190, body 237 (`D1:13131`, `D1:13133`);
  - O: 196, head 196, body 249 (`D1:26370`);
  - X: 445, head 196, body 249 (`X1:11298`, `X1:11300`);
  - C: 445 (`D1:49944`).
- **Over `tlsh2`:** F 191 (`D1:13193`), X 446 (`X1:11341`).
- **The relation holds for 1, 2 and 8 parts, a file part, and E's bodies up to 1,048,577 bytes**
  (X: `request_size` 1048820 for a head of 243 and a body of 1,048,577).
- **Each attempt counts.** Every transfer here ran on a fresh multi handle and sent one request. On
  a reused connection, 8.23.0 resends to dead connections, so the size sums each attempt
  (AGENTS.md's trap; ADR-0022, amended). That case was not run.

## Not measured

- **Apple's 8.7.1:** `mac.sh` is written and `sh -n` clean; the maintainer runs it. The trap list
  says 8.7.0 and 8.7.1 answer `REQUEST_SIZE` 0 for every transfer, so question 9's row there is
  expected to read 0.
- **Whether `EXPECT_100_TIMEOUT_MS` 65836 is clamped to 65535 or kept:** that needs a 65 s wait per
  lane. Truncation to 300 ms is ruled out (question 4).
- **HTTP/2 DATA frame counts:** Node exposes reads, not frames.
- **A part's own headers (`curl_mime_headers`), encoders, nested and streamed parts:** out of M8's
  scope (ADR-0038).
- **A file that is not regular, or that fails to open during the transfer:** not this probe's
  question (ADR-0038's context names both).
- **Linux arm64 and macOS amd64:** no lane runs there.

## Rerun

From the repository's root:

```sh
# lane X, twice (a run is about 40 s)
taskset -c 0-5 scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m8/mime-wire/run.sh guix-8.20.0' < /dev/null > .plans/research/m8/mime-wire/results/guix-8.20.0.log 2>&1
# lanes F, O, G and C (about 2.5 min; the first run fetches the apt packages into build/m8/mime-wire/apt)
sh .plans/research/m8/mime-wire/docker.sh > .plans/research/m8/mime-wire/results/docker.log 2>&1
# one case alone: CASES=E inside the container's sh -c, or before docker.sh
# the Mac
sh .plans/research/m8/mime-wire/mac.sh
# the tables and the checks, from every log in results/ (Node 20 or later; the container's will do)
scripts/guix-env sh -c 'node .plans/research/m8/mime-wire/tables.mjs' < /dev/null
```

`tables.mjs` prints each question's cells per lane, "all" where every lane agrees, and `SPLIT` for
a cell a lane's runs disagree on. Its last section is the checks above.
