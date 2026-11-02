# M7 cookie probe: libcurl's cookie engine, measured

2026-11-02, for the M7 plan. ADR-0033, decision 3: one in-memory jar per session, read out
and loaded as data, no file paths. This reports what libcurl does on each lane. It designs
nothing.

## Files

| File | What it is |
|---|---|
| `probe.c` | 37 cases, each on its own multi handle, stepped as the engine steps it. Each transfer gets a fresh easy handle with the engine's options. |
| `server.mjs` | The stand-in: Node's standard library alone. Raw HTTP/1.1 on one port, on `127.0.0.1` and `::1`. It writes the `Set-Cookie` lines the query names, byte for byte. Its body reports the request's `Cookie` headers whole. |
| `run.sh` | Builds the probe against one libcurl and its own headers, starts the stand-in, runs every case. |
| `docker.sh` | Runs `run.sh` in Docker `ubuntu:24.04` on four lanes. |
| `mac.sh` | The Mac's run, for the maintainer. Not yet run. |
| `compare.sh` | Normalises the logs. It diffs each lane's two runs (splits), and each lane against guix-8.20.0 (what varies). |
| `results/` | `guix-8.20.0.log`, `guix-8.20.0-2.log`, `docker.log`, `docker-2.log`, `compare.txt` |

Run from the repository's root:

```sh
scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/cookies/run.sh guix-8.20.0' < /dev/null
sh .plans/research/m7/cookies/docker.sh build/verify/c823/lane1/curl-current
sh .plans/research/m7/cookies/compare.sh > .plans/research/m7/cookies/results/compare.txt
NODE="$(asdf which node)" sh .plans/research/m7/cookies/mac.sh      # on the Mac
```

## How to read the citations

* `G n` is line n of `results/guix-8.20.0.log`. `D n` is line n of `results/docker.log`, and
  `G2` and `D2` are the second runs.
* In `D`, lines 10–1864 are floor-7.85.0, 1865–3901 ubuntu-openssl-8.5.0, 3902–5938
  ubuntu-gnutls-8.5.0, and 5939–7787 current-8.23.0. Both runs have the same layout.
* `C n` is line n of `results/compare.txt`.
* **The rule for "every lane":** `C 1–10` shows each lane's two runs agree. They were compared
  with ports, temporary names, clock readings and absolute expiry times taken out.
* `C 11–976` compares each lane's first run against guix-8.20.0's, in a cookie view. The view
  sorts each jar listing, since its order moves with the hash table. It counts the address
  each transfer reached, and 8.5.0's `fopen("")` calls, apart.
* A row whose lines do not appear in `C 11–976` gave the same lines on all five lanes, both
  runs. A row that varies names its lanes.
* Log lines escape bytes outside 0x20–0x7e as `\xHH`. The probe writes a tab as `\t`, and the
  server's report writes it as `\x09`.

## Lanes

Every lane ran 37 cases, each case exiting 0, twice (`G 1839`, `D 1864`, `D 3901`, `D 5938`,
`D 7787`). In all four logs, every transfer ended code 0, and none reached the probe's 10 s
bound: no `gave-up` line, and no `done code=` but 0.

| Lane | libcurl file | Version, TLS | PSL bit | Node | Headers | Cite |
|---|---|---|---|---|---|---|
| guix-8.20.0 | `/gnu/store/67lpb…-curl-8.20.0/lib/libcurl.so.4.8.0` | 8.20.0, GnuTLS 3.8.13, libpsl 0.21.5 | 1 | 24.18.0 | its profile's | `G 1–5` |
| floor-7.85.0 | `build/e1/ci/curl-floor/lib/libcurl.so.4.8.0` | 7.85.0, OpenSSL 3.0.13 | 0 | 20.10.0 | the build's | `D 10–15` |
| ubuntu-openssl-8.5.0 | `/usr/lib/x86_64-linux-gnu/libcurl.so.4.8.0` (8.5.0-2ubuntu10.16) | 8.5.0, OpenSSL 3.0.13, libpsl 0.21.2 | 1 | 24.18.0 | libcurl4-openssl-dev 8.5.0 | `D 3–6, 1865–1870` |
| ubuntu-gnutls-8.5.0 | `/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4.8.0` | 8.5.0, GnuTLS 3.8.3, libpsl 0.21.2 | 1 | 24.18.0 | the same 8.5.0 headers | `D 3902–3907` |
| current-8.23.0 | `build/verify/c823/lane1/curl-current/lib/libcurl.so.4.8.0` | 8.23.0, OpenSSL 3.0.13 | 0 | 24.18.0 | the build's | `D 5939–5944` |

* All five lanes are x86_64, on kernel Linux 7.1.1. The Docker lanes run Ubuntu 24.04.5, image
  `sha256:68ee2200…` (`D 1`).
* The Guix lane runs in the `scripts/guix-env` container, which has no `/etc/os-release`.
* Both 8.5.0 lanes gave the same cookie lines (`C 965–976`: only the file and TLS lines
  differ).

**localhost resolves inside libcurl, on every lane.**

* By source, `lib/hostip.c` (`lib/vdns/hostip.c` in 8.23.0) answers `localhost` and any name
  ending `.localhost` itself, with no lookup. This holds in 7.85.0, 8.7.1, 8.20.0 and 8.23.0;
  8.5.0's source was not read.
* By measurement, the system resolver fails `a.localhost`, `b.a.localhost`, `b.localhost` and
  `c.a.localhost` with rc -3, yet libcurl reaches each name (Guix `G 17–42`). Docker's
  resolver was pointed at a server that is not there (`D 8`), and it fails the same way there
  (floor `D 26–30`; every Docker lane alike, `C`).
* On every lane the stand-in bound both `::1` and `127.0.0.1`
  (`G 7`, `D 16, 1872, 3909, 5946`).
* 8.5.0, 8.20.0 and 8.23.0 reached `::1` for every `localhost` name: 161 transfers to `::1`
  and 11 to `127.0.0.1`, the latter all to the literal `127.0.0.1`. 7.85.0 reached
  `127.0.0.1` (170) and `::1` only for `[::1]` (2) (`C 340–344`). This matches 7.85.0's
  source, which lists 127.0.0.1 first, where 8.7.1, 8.20.0 and 8.23.0 list ::1 first.

## 1. One jar shared across easy handles

The setup: a `curl_share` with `CURL_LOCK_DATA_COOKIE`, no lock callbacks, one thread. Each
transfer is a fresh easy handle on one multi handle.

* T1 to `a.localhost` sets `host1=v1` and `dom1=v1; Domain=a.localhost`.
* T2 goes to `a.localhost`, T3 to `b.a.localhost`, T4 to `localhost`.

Every lane gave the same lines.

| Case | What is stored | What T2, T3 and T4 sent | Cite |
|---|---|---|---|
| Share, and `COOKIEFILE ""` on each | T1's jar holds 2 | T2 `Cookie: host1=v1; dom1=v1`; T3 `Cookie: dom1=v1`; T4 none | `G 56, 65, 75, 84` |
| No share, `COOKIEFILE ""` on each | T1's own jar holds 2; T2's jar holds 0 | none | `G 97, 105–106` |
| Share, no `COOKIEFILE` on any | T1's jar holds 0: the `Set-Cookie` is dropped | none | `G 130, 136` |
| Share, `COOKIEFILE ""` on T1 alone | the jar holds 2, readable through T2 | T2 sent none: a handle without the engine sends nothing, though the jar holds its cookies | `G 162, 170–171` |
| Share, `COOKIEFILE ""` on T2–T4 alone | T1's jar holds 0 | none | `G 202, 208` |

**Two transfers live at once (S-live).**

* A answers at once. B answers 600 ms on. C is added at 250 ms and answers 800 ms after its
  request. A sets `la` and `same=A`, B sets `lb` and `same=B`, C sets `lc`.
* At 400 ms the jar, read through B's live handle, held A's two cookies (`G 228–231`).
* C's request carried A's cookies: `Cookie: same=A; la=1` (`G 252`).
* At 1000 ms, through C's live handle, the jar held `la`, `lb` and `same=B` (`G 232–236`).
* D, after all three: `Cookie: same=B; lc=1; lb=1; la=1` (`G 263`).
* A, B and C each ended code 0 (`G 237, 242, 247`). Every lane gave the same lines.

**`curl_share_cleanup`.** Every lane gave the same answers:

| When | Answer | Cite |
|---|---|---|
| h1 done, still attached | 2, `CURLSHE_IN_USE`; the jar stays readable through h1 | `G 278–279` |
| h1 cleaned up, h2 attached | 2 | `G 281` |
| h2 detached by `CURLOPT_SHARE` NULL | 0. h2's jar then reads n=0, and a transfer on h2 after that sent no `Cookie` and read n=0. | `G 284–286, 291–292` |
| A handle live in the multi, at 200 ms | 2 | `G 294` |
| That handle done and cleaned up | 0 | `G 302` |

## 2. The Set-Cookie matrix

Stored lines are `CURLINFO_COOKIELIST`'s, whole. Sent lines are the stand-in's report, whole.

### Domain

| Set by | Attribute | Stored | Sent to | Cite |
|---|---|---|---|---|
| `a.localhost` | none | `a.localhost FALSE` (host-only) | `a.localhost` only | `G 311–322` |
| `a.localhost` | `Domain=a.localhost`, `.a.localhost` | `.a.localhost TRUE` | `a.localhost`, `b.a.localhost` | `G 313–314, 322, 328` |
| `a.localhost` | `Domain=A.LOCALHOST` | `.A.LOCALHOST TRUE` | `a.localhost`, `b.a.localhost` | `G 316, 322, 328` |
| `a.localhost` | `Domain=` (empty) | host-only | `a.localhost` | `G 315` |
| `a.localhost` | `Domain=localhost`, `.localhost` | **PSL lanes** (8.20.0, both 8.5.0): dropped. **No-PSL lanes** (7.85.0, 8.23.0): `.localhost TRUE` | no-PSL: `localhost` only; no lane sent it to `b.localhost` | `G 311, 333`; `D 321–322, 345`; `D 6256–6257, 6275`; `D 350, 6280` |
| `a.localhost` | `Domain=b.a.localhost` (a child), `b.localhost`, `example.com`, `127.0.0.1` | dropped, every lane | none | `G 311` (n=5) |
| `b.a.localhost` | `Domain=a.localhost`, `.a.localhost` (a parent) | `.a.localhost TRUE` | `b.a.localhost`, `a.localhost`, `c.a.localhost` | `G 353–374` |
| `b.a.localhost` | `Domain=localhost` | PSL lanes: dropped; no-PSL lanes: `.localhost TRUE`, sent to `localhost` | — | `G 379`; `C 44–53, 931–940` |
| `localhost` | `Domain=localhost`, `.localhost` | 8.20.0, 7.85.0, 8.23.0: `.localhost TRUE`. 8.5.0: `localhost FALSE`, host-only | `localhost` only, every lane: not `a.localhost`, not `b.a.localhost` | `G 391, 398, 403, 408`; `D 405`; `D 2287`; `D 6335` |
| `localhost` | `Domain=a.localhost` | dropped | — | `G 389` (n=3) |
| `127.0.0.1` | none, `Domain=127.0.0.1` | `127.0.0.1 FALSE`, both | `127.0.0.1` only | `G 423–431, 436` |
| `127.0.0.1` | `Domain=127.0.0.2`, `localhost`, `0.0.1` | dropped | — | `G 423` (n=2) |

**A `localhost` domain cookie never reaches `*.localhost`.** It holds on every lane, for
cookies set and for cookies loaded (`I-setcookie`, `G 1023, 1043`).

* By source, the jar hashes each cookie by its domain's last two labels. Every version read,
  7.85.0 to 8.23.0, does this (`cookiehash`, `get_top_domain`).
* So a `localhost` cookie and a request to `b.localhost` look in different buckets.
* Domain matching across hosts on this stand-in shows only with three labels:
  `Domain=a.localhost` reaching `b.a.localhost`.
* A host whose bucket happened to collide would see the cookie. None of the names used here
  did.

### Path

Set at `localhost/a/b/page`. Cite `G 447–515`; 7.85.0 is `D 460–469`, 8.5.0 `D 2350–2359`, and
`C 55–106, 413–464`.

| Attribute | Stored path, 8.20.0 and 8.23.0 | Stored path, 7.85.0 and 8.5.0 |
|---|---|---|
| none | `/a/b` | `/a/b/` |
| `Path=/a/` | `/a` | `/a/` |
| `Path=rel` | `/` | `rel`, which was sent to every path probed |
| `Path=` | `/a/b` | empty, which was sent to every path probed |
| `/a`, `/a/b`, `/x`, `/`, `/A` | as given | as given |

* Matching is by `/`-boundary prefix and case-sensitive, on every lane.
* `/a` matches `/a`, `/a/`, `/a/bc` and below. It does not match `/ab`. `/A` matches `/A`
  only. 8.20.0's lines:
  * `to:/ab` sent `Cookie: p_root=1; p_rel=1`.
  * `to:/a/b/c` sent `Cookie: p_empty=1; p_def=1; p_ab=1; p_aslash=1; p_a=1; p_root=1; p_rel=1`.
* On 7.85.0 and 8.5.0 the Cookie lines differ too: they hold `p_rel` and `p_empty` everywhere,
  in another order (`C 68–106, 426–464`).

### Secure over http://

Cite `G 525–575`; every lane gave the same lines.

| Set by | `Secure` cookie stored? | Sent back over http? |
|---|---|---|
| `localhost` | yes, `TRUE` | yes, `Cookie: nsec_lh=1; sec_lh=1` |
| `127.0.0.1` | yes | yes, `Cookie: nsec_ip=1; sec_ip=1` |
| `a.localhost` | no: dropped at set (jar n=3, no `sec_a`, `G 533`) | — |
| `a.localhost`, by `COOKIELIST` (Netscape `TRUE`, or `Set-Cookie: …; Secure`) | yes (`G 554–555`) | no: `Cookie: nsec_a=1` (`G 569`) |

### Expires and Max-Age

Set at `localhost`. `exp_delta` is the expiry less the time of reading.

| Attribute | 8.20.0, 8.23.0 | 7.85.0, both 8.5.0 | Cite |
|---|---|---|---|
| `Expires` 1 day ahead; `Max-Age=86400` | 86400 | 86400 | `G 586, 590` |
| `Expires` 399 days ahead | 34473600 | 34473600 | `G 589` |
| `Expires` 401 or 1000 days ahead; `Max-Age=86400000` | capped: 34560030 (`G 587`), 34560027 (`G2 587`), 34560030 and 34560009 (8.23.0, `D 6531`, `D2 6531`) | not capped: 34646400 and 86400000 | `D 601–606`, `D 2508–2512` |
| `Max-Age=99999999999999999999` | capped likewise | expiry `9223372036854775807` | `G 592`; `D 607`, `D 2513` |
| `Expires` in the past; `Max-Age=0`; `Expires` ahead with `Max-Age=0` | not stored | not stored | `G 585` (n=10) |
| `Max-Age=-1` | not stored | **7.85.0: a session cookie, and sent.** 8.5.0: not stored | `D 604, 616`; `C 110–128` |
| `Max-Age=60` with `Expires` in the past | 60: Max-Age wins | 60 | `G 593` |
| `Expires=notadate` | a session cookie | a session cookie | `G 594` |

* The cap is 400 days, 34560000 s. By 8.20.0's source (`cap_expires`), it adds 30 s and
  rounds down to a whole minute.
* Of the capped cookies, all were sent (`G 601`).

### HttpOnly, SameSite, prefixes, unknown attributes

Cite `G 611–628`; every lane gave the same lines, except one row.

* `HttpOnly` and `httponly` are stored as `#HttpOnly_localhost …`, and both are sent over
  http.
* `SameSite=Strict`, `Lax`, `None` and `Bogus` are all stored and all sent. No line records
  SameSite.
* `__Secure-` without `Secure` is dropped. `__Host-` with `Secure` and `Path=/` is kept, and so
  is `__Host-` with no Path set at `/`.
* `__Host-dom=1; Secure; Path=/; Domain=localhost` is dropped on 8.20.0, 7.85.0 and 8.23.0.
  Both 8.5.0 lanes keep it as `localhost FALSE`, host-only, and send it (`D 2544, 2553`;
  `C 491–499`). That fits 8.5.0 turning `Domain=localhost` into host-only (above).
* `Foo=bar` and `Partitioned` are ignored. The cookie is kept.

### Overwrite and delete

* **A duplicate name** (set on `a.localhost`; every lane gave the same lines):
  * A second `dup=` with the same domain and path replaces the first: `dup=1`, then `dup=2`.
    So does a second one in the same response: `dup2=a; dup2=b` keeps `b`.
  * The replaced cookie moves to the end of the listing (`G 638–657`).
  * The same name with another path keeps both, and `/p` sent
    `Cookie: pd=1; dup2=b; dup=2; dd=dom; dd=host; pd=2`.
  * Host-only `dd=host` beside `dd=dom; Domain=a.localhost` keeps both. `b.a.localhost` sent
    `Cookie: dd=dom` (`G 663–675`).
* **Deletion** (`M-delete`, `G 685–723`):
  * `Max-Age=0` deleted the cookie on every lane, and so did `Expires` 1970.
  * A deletion with no Path, aimed at a cookie of `Path=/p`, deleted nothing: `del_path`
    stayed.
  * `Max-Age=-1` deleted on 8.x. On 7.85.0 it replaced the value with `gone` as a session
    cookie, and it was sent (`D 726, 733`).
* **A deleted cookie can still be listed.**
  * On 7.85.0 and 8.5.0, a cookie deleted by the last `Set-Cookie` of a response stays in
    `CURLINFO_COOKIELIST` with expiry `1`. It is not sent (`R-del`: `D 1776`, `D 3806`;
    `C 328–332, 604–608`; `M-delete` on 8.5.0: `D 2645, 2653`).
  * On 8.20.0 and 8.23.0 it is gone from the listing at once (`G 1752`).

### Invalid lines, other header forms, bytes above 0x7F

* **Invalid lines** (`M-invalid`, `G 733–746`).
  * Dropped on every lane: an empty line, `=noname`, `noequals`, `;;;`, a control byte
    0x01 and DEL 0x7f in a value, and `Domain=..localhost`.
  * Also dropped: name+value of 4100 bytes (`v_4101`), a 4096-byte name, and a line of 5026
    bytes.
  * Name+value of 4090 bytes (`v_4090`) is kept, and sent.
  * Kept, and sent as stored: `n v=1` (a space in the name), `sp=a b`, `lead=padded` (blanks
    trimmed), `quote="q v"` (quotes kept), `semi=a` (the rest read as an attribute), `empty=`.
  * **A tab in a name or a value:** dropped on 8.x. 7.85.0 keeps both, and its listing lines
    then hold an extra tab: `localhost\tFALSE\t/\tFALSE\t0\tn\tt\t1` and `…\ttabv\ta\tb`. It
    sent them too (`D 751–752, 764`; `C 143–153`).
* **Header forms** (`G 756–767`, every lane gave the same lines).
  * `set-cookie:`, `SET-COOKIE:`, no space after the colon, and many spaces are all read.
  * `Set-Cookie:` with nothing after it, and `Set-Cookie2:`, are ignored.
  * `Set-Cookie: hf_a=1, hf_b=2` is one cookie, value `1, hf_b=2`.
* **Bytes above 0x7F** (`G 778–788`, every lane gave the same lines). Values `caf\xc3\xa9`,
  `\xe9`, `\xff\xfe` and `a\xe2\x80\x8bb`, and the name `n\xc3\xa9`, are stored and sent byte
  for byte: `Cookie: hb_latin=\xe9; hb_utf8=caf\xc3\xa9; hb_mid=a\xe2\x80\x8bb; hb_ff=\xff\xfe; n\xc3\xa9=1`.

### Caps

Every lane gave the same values.

| What | Measured | Cite |
|---|---|---|
| `Set-Cookie` lines kept from one response | 50 of 60: `ma_0` to `ma_49`, the first 50 | `G 794–800` |
| Cookies sent in one request | 150. Of 200 for the host, the three oldest responses' (`mb0_`–`mb2_`, not `mb3_`), and the same of 1000 (`md0_`–`md2_`). | `G 815–821, 917–923` |
| Bytes of `Cookie` sent | 8 of 30 cookies of 1000-byte values: a header line of 8070 bytes, all from the newest response (`mc2_`). By source the limit is 8190 bytes: of the `Cookie` line in 8.20.0 and 8.23.0, and of the request head built so far in 7.85.0. A ninth cookie passed neither. | `G 837–838` |
| Cookies in the jar | no cap seen: 1280 held | `G 917` |

## 3. Import and export as data

**Netscape lines by `CURLOPT_COOKIELIST`** (`I-netscape`, `G 928–997`).

* Every lane gave the same lines, except the listing's order, which moves with the hash table.
* Every line answered `rc=0`, kept or not, the dropped ones too.
* Read-out lines are `domain\tTAILMATCH\tpath\tSECURE\texpiry\tname\tvalue`, with
  `#HttpOnly_` before the domain when HttpOnly.
* A tail-matching domain is read out with a leading dot: `localhost\tTRUE…` came back as
  `.localhost\tTRUE…`, and `a.localhost\tTRUE…` as `.a.localhost\tTRUE…` (`G 944, 950`).
* Kept:
  * a session line (expiry 0), and a `#HttpOnly_` line;
  * a 6-field line (`ns_novalue`), read out with an empty value and a trailing tab
    (`G 949`);
  * an expiry of 99999999999, not capped (`G 951`).
* Dropped: an expiry of 1 (in the past), spaces in place of tabs, a `#` comment, and 8 fields.
* Sent: `localhost/` got
  `Cookie: ns_httponly=v3; ns_novalue=; ns_dottail=v2; ns_lhtail=v10; ns_sess=v1; ns_far=v13`
  (`G 957`).
* `ns_secpath`, `Secure` with `Path=/p`, went to `localhost/p` over http (`G 963`).
* `ns_tail` went to `a.localhost` and `b.a.localhost`; `ns_ip` to `127.0.0.1` (`G 969–992`).

**`Set-Cookie:` lines by `CURLOPT_COOKIELIST`** (`I-setcookie`, `G 1020–1071`). Every lane
gave the same lines.

* The prefix is read in any case (`set-cookie:`), and with no space after the colon.
* `Domain=localhost` is stored `.localhost TRUE` on every lane, PSL ones too. By 8.23.0's
  source, a `COOKIELIST` line is added with `COOKIE_NOPSL`.
* `Secure` is kept.
* **A line with no `Domain` is stored, and never listed** (n=6 of 8 lines, no
  `sc_nodomain`). It went only to IP hosts:
  * `127.0.0.1/` sent `Cookie: sc_ip=v7; sc_nodomain=v1`, and `[::1]/` sent
    `Cookie: sc_nodomain=v1` (`G 1059–1071`).
  * Not `localhost`, `a.localhost` or `b.localhost`.
  * Its `Path=/p` twin went to `127.0.0.1/p` alone.
* By source, a cookie with no domain hashes into bucket 0 with IP-address hosts, and matches
  any host it is compared with.

**The commands, with no file set** (`I-commands`, `G 1093–1153`).

* The handle held the share and `COOKIEFILE ""`; no `COOKIEJAR` was set. Every command
  answered `rc=0`.
* Every lane did the same to the jar:
  * `SESS` drops the session cookies (4 to 2, `G 1093, 1099`).
  * `FLUSH` and `RELOAD` change nothing (`G 1103, 1107`).
  * `ALL` empties it (`G 1111`), and the next transfer sent no `Cookie` (`G 1116`).
  * `RELOAD` after a transfer on the handle changes nothing (`G 1133`).
  * Lower-case `sess` and `all` work (`G 1137, 1140`).
  * On a bare handle, with no share and no `COOKIEFILE`, each command and `BOGUS` answered 0
    and left an empty jar (`G 1149–1150`).
* Files and streams:
  * No case wrote stdout or stderr (each case's `stdout-bytes=0 stderr-bytes=0`, e.g.
    `G 1153`).
  * None read stdin (`stdin-left=26`, all of the 26-byte pipe, e.g. `G 1152`).
  * None left an entry in its working directory (`cwd-entries=[]`).
* `fopen("")` on 8.5.0 alone:
  * On 8.20.0, 7.85.0 and 8.23.0, the file watch saw no call in any case but `X-detector` and
    `F-flush-control`.
  * Both 8.5.0 lanes called `fopen("")` at every transfer start where the handle had
    `COOKIEFILE ""`, and at each `RELOAD` (`D 3098`; `C 543–545`; per-case counts in `C`). An
    empty name opens nothing.
* The detectors work: `X-detector` read stdin (`stdin-left=0`), wrote 13 bytes to each of
  stdout and stderr, and its `fopen` was seen (`G 8–12`).

**`FLUSH` with a file** (`F-flush-control`, the one `COOKIEJAR` case, in a scratch directory;
`G 1325–1354`).

* On 8.20.0 and 8.23.0, `FLUSH` before any transfer wrote nothing (`G 1325`).
* On 7.85.0 and 8.5.0 it wrote the three-line header with no cookies (`C 275–282, 563–573`).
* After the transfer, `FLUSH` wrote the jar through a temporary file and a rename
  (`G 1331–1341`).
* `curl_easy_cleanup` wrote it again (`G 1345`).

**Read out and loaded back** (`I-roundtrip`).

* The jar was filled by `Set-Cookie` (host-only, domain, path, HttpOnly, persistent,
  `a b`, `caf\xc3\xa9`, empty, quoted) and by `COOKIELIST`.
* It was read out, each line loaded into a fresh share, and read out again. On every lane the
  second read gave the same 13 lines in the same order (`identical_lines=13 same_order=1`,
  `G 1219`, `D 1237, 3217, 5254, 7163`).
* Both shares then sent the same `Cookie` lines (`G 1219`ff).
* What did not survive: the domain-less `Set-Cookie: rt_nodomain=7` was never listed, so it
  cannot be read out.

**The order of `COOKIELIST` and `CURLOPT_SHARE`** (`I-order`, every lane).

* A line loaded before the handle took the share was in the handle's own jar (n=1). Attaching
  the share dropped it (n=0); it was never sent.
* A line loaded after attaching went to the share and was sent: `Cookie: after_share=1`
  (`G 1274–1286`).

**The share with no `COOKIEFILE`** (`I-noengine`, every lane).

* With the share attached, a loaded line was readable through the handle (`G 1299–1300`).
* That handle's own transfer sent no `Cookie` and dropped the response's `Set-Cookie`
  (`G 1298`).
* The next handle, with `COOKIEFILE ""`, sent `Cookie: ne_imp=1` (`G 1306`).
* A bare handle, no share and no file, given a `COOKIELIST` line alone, turned its engine on.
  It sent `Cookie: bare_imp=1` and stored the response's cookie (`G 1315–1316`).

## 4. A caller's own cookies beside the jar

* The jar held `n=jar` for `localhost`, which shares the caller's name `n`, and `j=jar` for
  `a.localhost`, a different name.
* Every lane gave the same lines (`G 1375–1593`).
* Lines are as the stand-in received them, in order. `@localhost` rows are first; `@a.localhost`
  rows are the same with `j=jar` in place of `n=jar` (`G 1483–1586`).

| Caller's setting | `Cookie` headers sent to `localhost` | Cite |
|---|---|---|
| none | `Cookie: n=jar` | `G 1376` |
| `HTTPHEADER` `Cookie: n=caller` | `Cookie: n=jar`, then `Cookie: n=caller`: two headers | `G 1384–1386` |
| `CURLOPT_COOKIE` `n=opt` | `Cookie: n=jar; n=opt`: one header, jar first | `G 1395` |
| `CURLOPT_COOKIE` `n=opt1; o=opt2` | `Cookie: n=jar; n=opt1; o=opt2` | `G 1454` |
| both of the above | `Cookie: n=jar`, `Cookie: n=caller`: `CURLOPT_COOKIE` dropped | `G 1403–1405` |
| `HTTPHEADER` `Cookie:` (removal form) | `Cookie: n=jar`: the jar's header is not removed | `G 1414` |
| `Cookie:` with `CURLOPT_COOKIE` `n=opt` | `Cookie: n=jar`: `CURLOPT_COOKIE` dropped | `G 1463` |
| `HTTPHEADER` `Cookie;` (empty form) | `Cookie: n=jar`, `Cookie:` | `G 1423–1424` |
| `HTTPHEADER` `cookie: n=caller` | `Cookie: n=jar`, `cookie: n=caller` | `G 1433–1434` |
| two `Cookie:` lines | three headers: the jar's, then both | `G 1443–1445` |
| no jar: `CURLOPT_COOKIE`, or `HTTPHEADER` | `Cookie: n=opt`, or `Cookie: n=caller` | `G 1472, 1478` |

No caller cookie entered the jar: it held the same 2 lines after every row (`G 1593`).

## 5. Redirects done by the client

* T0 to `a.localhost/pre` sets `pre=a` (host-only) and `pdom=1; Domain=a.localhost`.
* T1 answers a 3xx with its own `Set-Cookie`s. The probe reads `CURLINFO_REDIRECT_URL` and runs
  T2 there, on a fresh handle with the same share.
* Every lane gave the same lines, with three exceptions. PSL decides `on3xx_lh`. 7.85.0 and
  8.5.0 store `rq`'s path as `/dir/`. And they still list the deleted `pre`.

| Case | T1's `Set-Cookie`s, stored? | T2's URL and what it sent | Cite |
|---|---|---|---|
| 302 to `b.localhost` | `on3xx=1` stored. `on3xx_lh; Domain=localhost`: PSL lanes drop it, no-PSL lanes store `.localhost TRUE` (`D 1636, 7563`) | `http://b.localhost:PORT/land`: no `Cookie` on any lane. Back on `a.localhost`: `Cookie: on3xx=1; pdom=1; pre=a`. | `G 1612–1634` |
| 302 to `/other/land` (relative) | `rp; Path=/other`, and `rq` (path `/dir`; 7.85.0 and 8.5.0 `/dir/`) | `http://a.localhost:PORT/other/land`: `Cookie: rp=1; pdom=1; pre=a` | `G 1656–1669`; `C 316–326` |
| 301 to `b.a.localhost` | `sub; Domain=a.localhost` | `Cookie: pdom=1; sub=1`: not `pre` | `G 1704–1716` |
| 303 to `/land`, deleting `pre` | `pre` deleted (listed with expiry 1 on 7.85.0 and 8.5.0) | `Cookie: pdom=1` | `G 1749–1759`; `D 1776, 3806` |
| 307 from `localhost` to `127.0.0.1` | `lh_only` stored for `localhost` | `http://127.0.0.1:PORT/land`: no `Cookie` | `G 1788–1798` |

* As a comparison, R-cross's hops followed by libcurl itself (`FOLLOWLOCATION` 1) also sent no
  `Cookie` to `b.localhost`, and left the same jar (`G 1830–1831`; `C 334–338`).

## What varies by version or by PSL

| Behaviour | 7.85.0 (no PSL) | 8.5.0 (PSL) | 8.20.0 (PSL) | 8.23.0 (no PSL) |
|---|---|---|---|---|
| `Domain=localhost` from `a.localhost` | kept | dropped | dropped | kept |
| `Domain=localhost` from `localhost` | `.localhost TRUE` | host-only | `.localhost TRUE` | `.localhost TRUE` |
| `__Host-` with `Domain=localhost` | dropped | kept | dropped | dropped |
| Default path, and `Path=/a/` | `/a/b/`, `/a/` | `/a/b/`, `/a/` | `/a/b`, `/a` | `/a/b`, `/a` |
| `Path=rel` and `Path=` | stored as given; sent to every path | likewise | `/`, and the default | `/`, and the default |
| 400-day cap on expiry | no | no | yes | yes |
| `Max-Age=-1` | a session cookie, sent | deleted | deleted | deleted |
| A tab in a name or a value | kept | dropped | dropped | dropped |
| A just-deleted cookie in `COOKIELIST` | listed, expiry 1 | listed, expiry 1 | gone | gone |
| `FLUSH` before any transfer, with a jar file | writes a header | writes a header | writes nothing | writes nothing |
| `fopen("")` for `COOKIEFILE ""` | no | at each transfer and `RELOAD` | no | no |
| Address reached for `localhost` names | `127.0.0.1` | `::1` | `::1` | `::1` |

* One row splits along the PSL bit, across versions: `Domain=localhost` from `a.localhost`
  (and from `b.a.localhost`, and on a 3xx). There PSL, not version, is the variable.
* The `localhost`-from-`localhost` and `__Host-` rows set 8.5.0 apart alone. 8.5.0 is a PSL
  lane, but 8.20.0, also PSL, agrees with the no-PSL lanes. The probe cannot say whether
  version or PSL handling makes 8.5.0's difference.
* Every other row splits by version.
* Both 8.5.0 lanes agree throughout (`C 965–976`).

## Splits

None. After normalising (`compare.sh`), each lane's two runs agree (`C 1–10`). Before it, the
runs differed only in:

* ports and temporary names;
* expiry readings taken in a different second, for instance the cap's 34560030 against
  34560009;
* absolute expiry times.

## Not measured, and why

* **The Mac (Apple's 8.7.1).** `mac.sh` is written, not run:
  `NODE="$(asdf which node)" sh .plans/research/m7/cookies/mac.sh`. Its file watch is Linux's
  alone, an `fopen`/`open` interposer, so on macOS only the stream and working-directory checks
  speak to item 3.
* **`Secure` over `https://`.** The stand-in is plaintext. The brief asks only for `http://`.
* **A share across threads, with lock callbacks.** The engine has one thread.
* **A real public suffix** (`Domain=co.uk` and the like) needs non-local names, which only
  `RESOLVE` would give, and `RESOLVE` fills the multi handle's DNS cache. PSL shows here only
  through `localhost`.
* **A `localhost` domain cookie reaching a `*.localhost` host by a hash collision.** No name
  used collided. That it would is source reading alone.
* **The cookie host taken from a caller's `Host:` header** (`aptr.cookiehost` in `http.c`).
  This is source reading only; it was not in the work list.
* **8.5.0's source** is not in the tree, so its rows rest on measurement alone. Ubuntu may
  patch it.
* **`CURLOPT_COOKIESESSION`** was not measured.
