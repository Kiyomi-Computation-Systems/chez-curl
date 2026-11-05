# M7 slice 4 research: the cookie jar, through the engine

Measured 2026-11-03 for M7 slice 4 ([plan](../../../2026-11-02-m7-plan.md), sections 3.5 and 6.3;
[ADR-0035](../../../decisions/0035-the-cookie-jar-is-libcurls-shared.md)). Every transfer went
through chez-curl's engine, on a prototype copy of `src/` with a cookie jar on the engine's thread;
the hatch's answers on main ran on main's `src/`. Five Linux libcurls ran every item twice, then
item 1 once more under the memory gate's Valgrind. It reports what libcurl and the prototype did.
It designs nothing and names no public procedure. The C probe this builds on is
[`../cookies/`](../cookies/), and the plan review's is [`../review/`](../review/); what they settled
by C is not argued again.

Lanes: **F** `floor-7.85.0`, **O** `ubuntu-openssl-8.5.0`, **G** `ubuntu-gnutls-8.5.0`, **X**
`guix-8.20.0`, **C** `current-8.23.0`. Citations are `FILE:LINE` in `results/`, run 1 unless named
`-2`. `docker-N.log` holds F, O, G and C in that order. `tables.mjs --cite=ITEM/CASE` prints every
lane-run's line for a case; `tables.mjs` rebuilds every table below from the logs alone.

## In short

- **Item 1, the lifetime.** On all five, both runs: 200 transfers, 20 at once, ran 200 of 200 with
  the jar, at most 19 holding it at a sample, and the read-out after held 201 lines, `common` 199,
  or 198 on F's first run, the value of one of the last to finish (`guix-8.20.0-1.log:1213-1215,
  1416`; table 1). A load, a submit and a read-out queued in
  one hold ran in that order: the transfer sent the loaded cookie (`:1427`), and the read-out,
  carried out before the transfer's exchange, held the loaded line alone (`:1430`). A close while
  two transfers held the jar answered `closing` at once (`:1442`); a `Set-Cookie` that arrived
  after it was stored in the closing share (`:1456`); the share was freed once, by the last
  release, `curl_share_cleanup` answering 0 (`:1466`, `(release 0 0)`); a submit after was refused
  `cookie-jar-closed` (`:1465`). 500 crossings of a close and a submit on two threads reached all
  three outcomes on every lane-run, ran 242 to 246, refused at submit 245 to 253, refused at
  set-up 4 to 9, with no other outcome and every jar closed with no holder after
  (`guix-8.20.0-1.log:2947`, `docker-1.log:2962, 11776, 20591, 29414`, and the `-2` twins). Stop
  freed a live jar and a closing one (`guix-8.20.0-1.log:2963-2967`). Pooled HTTP/1.1 and HTTP/2
  connections opened by transfers that held the jar carried transfers after the share was freed,
  and a new jar's after them, on one connection each (`guix-8.20.0-1.log:2972-3003`,
  `docker-1.log:2987-3018`). The counters read zero
  after every case but (g), on every lane-run (table Lanes). (g): `curl_share_cleanup` answered 2,
  `CURLSHE_IN_USE`, while an easy handle that held the share was added to a live multi handle,
  before and after its transfer, and after that multi handle's cleanup, which answered 0; it left
  one easy handle and one share counted (`guix-8.20.0-1.log:3021-3033`), and freeing the easy
  handle let the share go (`:3058-3059`). Under Valgrind: 0 errors, nothing definitely or
  possibly lost in item 1's lifetime part; (g)'s abandoned handle and share are possibly lost,
  8,307 bytes in 37 blocks, which the gate's options do not count
  (`valgrind-ubuntu-openssl-8.5.0.log:3058-3062, 3089-3093`).
- **Item 2, `curl_share_setopt`.** `SHARE 2` (`CURL_LOCK_DATA_COOKIE`) answers 0 and is the one
  value that carries a cookie to a second transfer, on all five (table 2). 0, 1, 8, 9, 99 and -1
  answer 1, `CURLSHE_BAD_OPTION`, everywhere; 3, 4 and 5 answer 0 and carry nothing; 6 (PSL)
  answers 5, `CURLSHE_NOT_BUILT_IN`, on F and C, the lanes without libpsl, and 0 on O, G and X; 7
  (HSTS) answers 1 on F, which predates it, and 0 on O, G, X and C (`docker-1.log:3123, 3129`,
  `:29575, 29581`, `guix-8.20.0-1.log:3108, 3114`). `UNSHARE 2` after `SHARE 2` answers 0 and stops
  the carrying (`docker-1.log:3399`); a share a handle holds answers 2 to every setopt and to
  cleanup (`guix-8.20.0-1.log:3149-3151`).
- **Item 3, the order.** `SHARE` then `COOKIEFILE ""` and the other order stored and sent the same
  lines on all five (table 3). Both 8.5.0 lanes called `fopen("")` once per transfer in either
  order, 3 for 3 transfers (`docker-1.log:12449, 12482, 21264, 21297`); F, X and C none
  (`docker-1.log:3635, 30087`, `guix-8.20.0-1.log:3620`); the watch's detector saw libcurl's own
  `fopen` of a cookie file on every lane (table 3).
- **Item 4, loading lines.** The rule accepts many lines libcurl drops, rewrites, or keeps unlike
  by version: 68 rows of table 4x. One line it accepts breaks the host it matches: a loaded cookie
  whose `name=value` passes the Cookie header's cap, first in libcurl's order, leaves the request
  head unterminated, `Cookie: \r\n` and nothing after, and the transfer waits for its timeout, 28,
  on all five (`value-8200`, `value-100000`, `two-lines-big-name-longer`; table 4). Every line the
  rule accepts loaded back the same from its read-out on every lane: no round trip failed (table
  4x).
- **Item 5, reading out.** The rule refuses read-out lines on F, O and G alone: a server's
  `Path=`, `Path=TRUE` and `Path=FALSE` read out as an empty path or a path `TRUE`/`FALSE`, and on F
  a tab in a name or a value reads out as eight fields (table 5x). X and C read out nothing the
  rule refuses.
- **Item 6, the cost.** A load of 50,000 lines in one message held the engine's thread 9.4 to 13.3
  s for one domain and 22.5 to 27.4 s spread over 1,000 domains; a read-out of 50,000 took 1.7 to
  2.6 s, and the second 5.1 to 6.4 s; 10,000 lines took 0.24 to 0.50 s to load and 0.06 to 0.19 s
  to read (table 6, `docker-1.log:7341, 7373`). Almost all of a load is libcurl's own setopt.
- **Item 7, a caller's `Host` and `Cookie`.** A caller's `Host: b.localhost`, in any case, with or
  without a port, on a request to `a.localhost`, sent the jar's `b.localhost` cookie and stored the
  answer's cookie for `b.localhost`, over HTTP/1.1 and HTTP/2 (where it became `:authority`), on
  all five (table 7, `docker-1.log:7401, 7633`). A caller's `Cookie` header went out as a second
  header, or a second HTTP/2 `cookie` field, beside the jar's; `COOKIE` by the hatch joined the
  jar's line, and beside a caller's header was dropped; `("Cookie" . "")` sent an empty second
  `Cookie:` header, or an empty field (table 7).
- **Item 8, HTTP/2.** The jar's cookies went as one `cookie` field, `c2=1; c1=1; c0=1`, not
  crumbs, on all five (`docker-1.log:7872`). Two streams on one connection each stored their
  cookies, and the next stream sent both (`docker-1.log:7889`).
- **Item 9, requests inside a transfer.** The Digest round's second request carried the cookie its
  401 set, and the resend after a 417 carried the cookie the 417 set, on all five (table 9).
- **Item 10, the twins.** On main the hatch takes `COOKIE`, `COOKIELIST` and `COOKIESESSION` and
  `HSTS_CTRL`; it refuses `COOKIEFILE`, `COOKIEJAR` and `HSTS` as owned and `SHARE` by its type
  (`guix-8.20.0-1.log:17-27`). Beside a jar, `COOKIELIST` reaches past its transfer: `ALL` and
  `SESS` cleared the shared jar for every holder, and a Netscape or `Set-Cookie:` line loaded into
  it; `COOKIE` went out on its transfer alone; `COOKIESESSION` and `HSTS_CTRL` changed nothing the
  jar held (table 10).
- **Item 11, what the share holds.** A share of cookies alone carried no `Strict-Transport-Security`
  entry: the second, `http://`, transfer went out plaintext on all five. The control, a share that
  also set `CURL_LOCK_DATA_HSTS`, carried it on O, G, X and C, even with `HSTS_CTRL` set on neither
  transfer; F refused the lock value, 1, and carried nothing (table 11). The brief named 8.20.0 and
  8.23.0; every lane ran it, and what 7.85.0 and 8.5.0 know of `CURL_LOCK_DATA_HSTS` is that:
  7.85.0 has no such value (its `include/curl/curl.h:2874-2885` ends at PSL), and both 8.5.0s share it as 8.20.0
  and 8.23.0 do.
- **Item 12, IPv6 loopback.** `::1` is up in the Guix container and in Docker `ubuntu:24.04` with
  `--network none` and with Docker's default network, and Node listens on it in each
  (`guix-8.20.0-1.log:3, 13`, `docker-1.log:14, 24`, `netcheck-docker-default.log:2-5`).
  `tests/origin.mjs` listens on `127.0.0.1` alone (`guix-8.20.0-1.log:4`). Against a server on
  `127.0.0.1` alone, `a.localhost` reached it on every lane at a sub-millisecond connect; on a
  server on both, 7.85.0 reached `127.0.0.1` and the rest `::1`; a server on `::1` alone was
  reached by `a.localhost`, `localhost` and `[::1]` and refused `127.0.0.1` (table 12).

## Lanes

| Lane | libcurl | TLS | Node | Cite |
|---|---|---|---|---|
| F `floor-7.85.0` | `build/e1/ci/curl-floor/lib/libcurl.so.4.8.0` | OpenSSL 3.0.13 | 20.10.0 | `docker-1.log:25` |
| O `ubuntu-openssl-8.5.0` | `/usr/lib/x86_64-linux-gnu/libcurl.so.4.8.0`, 8.5.0-2ubuntu10.16 | OpenSSL 3.0.13 | 20.10.0 | `docker-1.log:5, 9, 8851` |
| G `ubuntu-gnutls-8.5.0` | `/usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4.8.0`, 8.5.0-2ubuntu10.16 | GnuTLS 3.8.3 | 20.10.0 | `docker-1.log:4, 6, 17662` |
| X `guix-8.20.0` | `/gnu/store/67lpb…-curl-8.20.0/lib/libcurl.so.4.8.0` | GnuTLS 3.8.13 | 24.18.0 | `guix-8.20.0-1.log:14` |
| C `current-8.23.0` | `build/verify/c823/lane1/curl-current/lib/libcurl.so.4.8.0` | OpenSSL 3.0.13 | 20.10.0 | `docker-1.log:26477` |

- All x86_64, kernel Linux 7.1.1. Docker `ubuntu:24.04` is image `sha256:68ee2200…`, Ubuntu
  24.04.5, with `--network none`, loopback alone (`docker-1.log:1-3`). Chez is spike E1's threaded
  build in Docker, the profile's in the container.
- `all.sh` ran the two runs one after the other, the Guix lane then the four Docker lanes each
  time, then Valgrind, the controls and the network check, nothing else on the machine.
- Every lane-run ran 16 parts, every one exiting 0, and 358 cases (table Lanes).
- Hashes the logs record (`guix-8.20.0-1.log:5-12`, the same on every lane-run): `src/` libraries
  `649e7a86…` (main at `a075629`), the prototype's `f70df92d…`, `jar.sps` `1b030702…`, `main.sps`
  `9462e716…`, `standin.mjs` `8a6aeaf5…`, `fswatch.c` `db847402…`, `prototype.diff` `4cf15b93…`,
  `prototype.py` `d4e99b17…`.

## The prototype

`make-prototype.sh` copies `src/` to `build/m7s4/src` and applies `prototype.py`; it fails unless
the diff, per file with fixed labels, is byte for byte `prototype.diff` (7 files, 34 lines removed,
451 added). What it adds:

1. `curl_share_init`, `curl_share_cleanup`, and `curl_share_setopt` through `bind-variadic` with an
   `int`: 7.85.0's `share.c:74, 127` and 8.20.0's `curl_share.c` read `va_arg(param, int)` for
   `SHARE` and `UNSHARE`, as does 8.7.1's `share.c:76, 141`. `CURLINFO_COOKIELIST` through
   `curl_easy_getinfo`, its list counted as `slist` and owned in the call's critical section,
   walked by a `curl_slist` ftype, `curl_slist_free_all` after.
2. The constants, from the headers: `CURLSHOPT_SHARE` 1, `UNSHARE` 2, `CURL_LOCK_DATA_COOKIE` 2,
   `HSTS` 7, `CURLSHE_OK` 0, `IN_USE` 2, `CURLINFO_COOKIELIST` 0x400000 + 28.
3. A `share` kind in `(curl private counters)`; a share is counted and owned in the critical
   section of `curl_share_init`, and counted down and forgotten in that of a cleanup that answers
   0, as a multi handle is.
4. The jar, on the engine's thread: a record of its engine, its share, a handle of its own, its
   state (pending, live, closing, closed, abandoned), its holder count and a log of every cleanup
   and close. Make, read out, load and close are messages queued beside submits; a turn now takes
   submits and jar messages in the order queued (today's turn sets up every submit, then cancels,
   then resumes; those keep their place). `set-up!` refuses a jar not live, or another engine's,
   `cookie-jar-closed` or `cookie-jar-engine`, as the token's outcome; `submit` makes the same
   checks first, as an early refusal. A close sets closing and frees the jar at once when no one
   holds it; the last release frees a closing jar. `shut-down!` answers queued jar messages
   `stopped`, and frees every jar once every live transfer is out; `fail-engine!` answers them
   `failed`, releases the holds of transfers it freed, keeps those of handles it abandoned, and
   marks a jar whose share stays in use `abandoned`.
5. A `cookie-jar` request key: `SHARE` at the jar's share, then `COOKIEFILE ""`, set with the
   request's other settings before the TLS settings; `set-jar-order!`, prototype-only, switches the
   order process-wide, for item 3.
6. Lines in and out as bytevectors: a load hands each one to `COOKIELIST` as a counted,
   NUL-terminated copy, and refuses one holding a 0 byte, before anything is queued.

Prototype-only, for the measurement: a make that takes a list of `curl_share_setopt` calls in place
of `SHARE COOKIE` (items 2 and 11); a peek, a read-out a closing jar answers; a probe that calls
`curl_share_cleanup` with the jar's handle attached or detached (item 1 (c)). The reasons
`cookie-jar-engine`, `cookie-jar-closed` and `cookie-line` join `curl-request-error-reasons`.
Nothing refuses a caller's `Cookie` or `Host` beside a jar, since item 7 measures them; the hatch is
unchanged.

### Where section 3.5 could not be followed as written

- **The record holds the jar's handle too.** Section 3.5 lists engine, share, state and holder
  count; its own "handle the engine keeps for the jar's messages, attached to the share" must be
  freed before the share, since `curl_share_cleanup` answers 2 while any handle holds it, the jar's
  own among them (`guix-8.20.0-1.log:1440`, the probe with the handle attached).
- **The jar's record type lives in `(curl private transfer)`.** The request key checks its value at
  construction, and the transfer library cannot import the engine's, which imports it.
- **The count rises after `start-transfer!` returns,** in the hold that records the live transfer,
  not before: a `start-transfer!` that raises has already freed its easy handle, detaching the
  share, and no `take-out!` follows to lower a count raised first.
- **`fail-engine!` does not go through `take-out!`,** so it lowers the count itself for each
  transfer it frees, and leaves it for each handle it abandons, whose share then stays in use.
- **"Taken in the order queued" needed the turn's first loop changed** to set up submits and carry
  out jar messages in one pass. A read-out queued after a submit, in the same turn, still reads
  the jar before that transfer's exchange, which the perform after the turn's messages runs
  (`guix-8.20.0-1.log:1430`).

## What bears on each open question

**The `cookie-line` rule** (section 3.5: seven tab-separated fields, `#HttpOnly_` allowed before
the domain, no field holding 0x00 to 0x1F or 0x7F, no field empty but the value, the path not
`TRUE` or `FALSE`), evaluated as written in `jar.sps`'s `rule`, two readings of `#HttpOnly_`:
literal, the first field as split, prefix and all; stripped, the domain after it.

- Every load answered `CURLE_OK`, 0, whatever libcurl did with the line (table 4).
- **Accepted, and dropped on every lane:** a domain starting `#` but `#HttpOnly_`, or
  `#HttpOnly_#HttpOnly_`, `#httponly_`, `#HTTPONLY_`; a domain starting `Set-Cookie:` or
  `set-cookie:` (`docker-1.log:5696, 5708`); an expiry `abc`, `-1`, or one past `2^63 - 1`
  (`docker-1.log:6284`).
- **Accepted, and rewritten on every lane:** any tail-match or secure field but `TRUE` (any ASCII
  case) reads out `FALSE`, so `F\x80ALSE`, `yes`, `1`, `0`, `true`'s case and spaces are lost;
  bytes after the expiry's digits are dropped (`0\x80`, `0;`, `0x10` read `0`); a leading dot with
  tail-match `FALSE` is dropped; `TRUE` adds a leading dot (table 4x).
- **Accepted, and kept unlike by version:** a path `rel`, `true`, or with leading spaces is kept as
  given on F, O and G and becomes `/` on X and C (`docker-1.log:6125`); an expiry `+5`, `1e3`,
  leading spaces before it, or `1` (in the past) is listed on F, O and G and dropped on X and C
  (`docker-1.log:6217, 6308`; 8.20.0 parses the field with `curlx_str_number`, `cookie.c:733`,
  where 7.85.0 used `curlx_strtoofft`, `cookie.c:952-953`); `#HttpOnly_` with nothing after it
  reads out `#HttpOnly_FALSE\tFALSE\t/…` on F, O and G, the empty domain gone and `FALSE` in its
  place, and with the domain empty on X and C (`docker-1.log:5627`): 7.85.0 splits the line with
  `strtok_r`, `cookie.c:895, 902`, which merges empty fields, and so does 8.7.1, `cookie.c:883,
  890` (8.5.0's source is not in the tree). The literal reading accepts that line; the stripped
  one refuses it, `empty`.
- **Accepted, and the transfer hangs:** a value of 8,200 or 100,000 bytes, alone or before a
  shorter-named cookie, makes the request to its host send `Cookie: \r\n` and stop, the head never
  ended, and fail at its timeout, 28, on all five (`docker-1.log:6568, 6586, 6693`, the stand-in's
  report of the unterminated head after each). An 8,100-byte value went out whole
  (`docker-1.log:6551`), and a 9,000-byte one behind a shorter name was left out with the rest
  sent (`docker-1.log:6710`). Both are libcurl's own `Restricted outgoing cookies due to header
  size` path (7.85.0 `http.c:2755`, 8.20.0 `http.c:2573`); Set-Cookie cannot make such a cookie
  (the C probe's 4,096-byte caps), so only a load can.
- **Refused, and libcurl agrees or the split is the rule's purpose:** 0x01, 0x1F and 0x7F stay in
  a name or a value before 8.23.0 (`docker-1.log:5343`), and 8.23.0 drops those lines; in a domain
  or a path they stay on all five. A CR or an LF cuts a name or a value where it stands, and drops
  a line that holds one in its domain or path (table 4). Empty fields split by version: an
  empty tail-match field is `FALSE` on F, O and G, `TRUE` on X and C; an empty secure field drops
  the line on F, O and G and reads `TRUE` on X and C; an empty path is `/` on F, O and G and drops
  the line on X and C; an empty name reads out as name `val` on F, O and G and as an empty name on X
  and C (`docker-1.log:6063, 6079, 6183, 6415`).
- **Kept and never sent where it should match:** a domain `[::1]` is never sent to `http://[::1]/`
  (`docker-1.log:5800`); a domain with a port is never sent; neither does a domain holding a byte
  above 0x7F match its host (table 4).
- **The round trip:** every line read out loaded back into a fresh jar and read out the same, on
  every lane, both runs (table 4, "round trip same").
- **NUL:** `call-with-c-string` and `call-with-latin-1-c-string` both refuse a line holding U+0000
  as `&curl-embedded-nul` before libcurl sees it, and the prototype's load refuses a 0 byte before
  anything is queued (`docker-1.log:3682`).

**Bytes above 0x7F**, as read out: a name or a value holding 0x80, 0xE9, 0xFF or UTF-8 é, from a
`Set-Cookie` or a load, reads out byte for byte, alike on all five, and is sent so (table 5,
`docker-1.log:6844-6928`; table 4). Nothing re-encodes them.

**Every read-out line the rule refuses:** on F, O and G, `Path=` (empty path), `Path=TRUE` and
`Path=FALSE` (`docker-1.log:7121, 7145, 7157`); on F alone, a tab in a name or a value, eight fields
(`docker-1.log:6753, 6765`). X and C read those out as `/`, or drop them. Both runs agree.

**The forms of a caller's `Host` and `Cookie` the refusal must cover:** `Host`, `host` and `HOST`,
with or without a port, any port, move both the cookies sent and the host stored, over HTTP/1.1 and
HTTP/2 (table 7). `Cookie` in any case is sent beside the jar's; `("Cookie" . "")` is sent too, as
an empty header or field (`docker-1.log:7543, 7775`). The hatch's `COOKIE` is a third form: it
joins the jar's line (`docker-1.log:7503, 7735`). The removal form `Cookie:` cannot be written
through chez-curl's headers, where an empty value is sent as `Cookie;`.

**Which twins reach past their transfer:** `COOKIELIST`, every form: `ALL` emptied the shared jar,
so the next transfer sent only what arrived after; `SESS` dropped its session cookies; a Netscape
or `Set-Cookie:` line loaded into it, and every later holder sent it (`docker-1.log:8040, 8075,
8193, 8235`). `FLUSH` and `RELOAD` changed nothing. `COOKIE`, `COOKIESESSION` and `HSTS_CTRL` did
not (`:8000, 8277, 8317`). `SHARE`, `COOKIEFILE` and `COOKIEJAR` are refused by the hatch today.

**`curl_share_setopt`'s variadic value, for `make check-variadic` on the Mac:** an answer of 0
alone cannot show that 2 arrived, since 3, 4 and 5 answer 0 too, and 6 and 7 do on some builds
(table 2). What tells them apart, alike on all five: `SHARE 2` answers 0 and a cookie set by one
transfer is sent by the next through the share, which no other value 0 to 9 does; `SHARE 99` and
`SHARE -1` answer 1; and `UNSHARE 2` after it answers 0 and stops the carrying, which `UNSHARE` of
any other value does not (table 2, `docker-1.log:3201, 3399`). A binding that hands libcurl another
int than the one given shows as 2 not carrying, or 99 not refused.

**The order on each transfer:** either order gave the same; neither stores, sends or opens anything
the other does not (item 3).

**Section 3.5's lifetime, under Valgrind too:** the holder count ended at zero in every case; the
share was freed once, at the release that left a closing jar unheld, answering 0, in every case
that closed a held jar (`guix-8.20.0-1.log:1466, 2966`); libcurl itself refuses a cleanup while any
handle holds the share, the planted control shows that refusal where a free comes too early
(below); stop and the crossings left no jar and no count. Under the gate's Valgrind on O, item 1's
lifetime part reported 0 errors and nothing lost, the crossings ran 250 and refused 250 at submit,
none at set-up within the 15 ms window (`valgrind-ubuntu-openssl-8.5.0.log:2986, 3059-3062`), the
control reaching a set-up refusal there too (`:2992`).

**The load's and read-out's cost on the engine's thread:** seconds for tens of thousands of lines,
with nothing else running on the engine meanwhile (item 6); a load of 10,000 lines took a quarter
to half a second. The data say a bound, or a load spread over turns, is needed if a caller's list
can be long.

**How the origin should listen:** it listens on `127.0.0.1` alone today; every libcurl from 8.5.0
tries `::1` first for `*.localhost`, is refused, and falls back within the same sub-millisecond
connect (table 12, `v4-a.localhost`); `::1` is up on every lane this repository runs, Docker's
default network included. Listening on both would make 8.5.0 and later reach `::1` and 7.85.0
`127.0.0.1` (table 12, `o-a.localhost`), as the C probe's stand-in found.

## Against ADR-0035 and section 3.5

- **Decision 4's "a load takes only lines libcurl keeps alike on every version" does not hold for
  the rule as written.** The rule passes lines libcurl drops on every lane, rewrites on every lane,
  and keeps unlike by version (above, table 4x), and one, a cookie past the header cap, that
  leaves every request to its host hanging. What does hold: every accepted line that libcurl kept
  read out and loaded back the same.
- **"What is read out loads back the same, but on 7.85.0 for a cookie whose name or value holds a
  tab" is incomplete:** on 7.85.0 and both 8.5.0s a server's `Path=`, `Path=TRUE` or `Path=FALSE`
  reads out a line the load refuses (table 5x).
- **Decision 6 and section 3.5's `Host`:** confirmed by measurement, where the plan had source
  alone: a caller's `Host` moves the cookies sent and the host stored on all five, over both HTTP
  versions.
- Nothing else measured contradicts ADR-0035 or section 3.5. The share's in-use answers, the
  order's indifference, a share of cookies alone carrying no HSTS, and the twins' reach agree with
  them.

## Checks on the instrument

Each watched failing (`controls-guix-8.20.0.log`, run by `controls.sh`):

1. **The stand-in's report of the Cookie headers.** Its self-test writes four Cookie headers of
   every byte class raw and two HTTP/2 crumbs, and reads the report back: ok as it is; a copy whose
   report drops each header's last byte fails every line, exit 1 (`controls-guix-8.20.0.log:5-13`).
   Every lane-run's own self-test passed (table Lanes).
2. **The read-out walk against libcurl's own file.** A scratch handle with `COOKIEJAR` in the run's
   directory, six lines loaded, one transfer (libcurl writes the file only once a transfer has
   started, 8.20.0 `cookie.c:1614-1619`), `FLUSH`: its six lines and the walk's agree, and a jar
   loaded with the same lines reads out the same six, on all five (`docker-1.log:8790, 8816`,
   table 4 none failing). A copy of the prototype whose walk stops before the last element prints
   `DIFFERS file=6 walk=5` and `jar=5` (`controls-guix-8.20.0.log:18-25`).
3. **Item 1's lifetime.** A copy whose close frees the share at once, whatever holds it, logs
   `(close 2 2)`: `curl_share_cleanup` refused, 2, with two holders; the prototype as it is logs
   no cleanup until `(release 0 0)` (`controls-guix-8.20.0.log:30-45`).
4. **Item 1 (d).** All three outcomes on every native lane-run (above); the control reaches each on
   purpose, and `cookie-jar-engine` too (`guix-8.20.0-1.log:2952-2955`).
5. **Item 11.** The control share with `CURL_LOCK_DATA_HSTS` carried the entry on O, G, X and C
   (`docker-1.log:17290`, `guix-8.20.0-1.log:8426`, `docker-1.log:34855`); on F it is refused, so
   item 11 has no carrying control there.
6. **Item 12.** The server on `::1` alone was reached at `[::1]` on every lane, and the same server
   refused `127.0.0.1`, code 7 (`docker-1.log:8680, 8671`).

The file watch (`fswatch.c`, `LD_PRELOAD`) has its own detector: a cookie file libcurl opens on a
scratch transfer, logged on all five (table 3).

## Splits

Between the two runs, after `tables.mjs --splits` normalises ports, tags, connection numbers,
times and epoch expiries, ten cases differ, all of them races by design: item 1 (a)'s completion
order on each lane, and item 1 (d)'s crossings, whose counts are above. No other case line differs.
Between lanes, the splits are those named in each item above and in the tables.

## Traps hit, and how to reproduce them

- **A Chez `foreign-procedure` of `fopen` does not reach an `LD_PRELOAD` interposer.** With
  libcurl loaded, Chez resolved `fopen` through libcurl's own handle, and the call never reached the
  preloaded `fopen`; with nothing loaded, Chez had no entry for it. Reproduce:
  `LD_PRELOAD=build/m7s4/fswatch.so FSWATCH_LOG=/tmp/x scheme --program P` where P calls
  `(foreign-procedure "fopen" (string string) uptr)`. A detector must make the library itself call
  it: here, a cookie file libcurl opens.
- **Node's `TLSSocket` over a `net.Socket` reads the socket's handle, not its stream:** a first
  chunk given back by `unshift` (to sniff TLS from plaintext) is lost, and the handshake never
  starts. Wrapping the socket in a plain `Duplex` works, on Node 20.10.0 and 24.18.0.
- **A stand-in that answers 417 to every `Expect: 100-continue` loops libcurl:** the resend carries
  the caller's `Expect` again, and the transfer ends 47 after 30 rounds. Answer 417 once per request.
- **A `Set-Cookie` written on every answer of an auth round lands on the 401 too,** and the second
  request then carries the final answer's cookie; write the final answer's cookies on it alone.
- **A cookie past the Cookie header's cap looks like a server that never answers:** libcurl sends an
  unterminated head and waits for its timeout. A stand-in that logs complete heads alone reports
  nothing; it must report the bytes a connection held as it closed.
- **libcurl writes a cookie file only once a transfer has started** (`cookies->running`), so a check
  of `FLUSH` before any transfer reads no file.
- **A twin's effect on "another transfer that holds the jar" depends on whether that one's request
  has gone:** `COOKIELIST ALL` set up before it is sent empties what it sends. Poll the stand-in for
  the other request before the twin.
- **A regex that normalises numbers fails after an escaped tab:** in `\x091793847049`, `\b` sees
  `9` then `1`, no boundary. Anchor on the escape.
- **A Node self-test that runs its client with `execSync` blocks the server in the same process.**

## Not measured, and why

- **The Mac (8.7.1).** `mac.sh` runs items 1, 2, 4, 5, 7, 8 and 12, twice with the default
  LibreSSL and twice with `CURL_SSL_BACKEND=secure-transport`; it was not run, the Mac being the
  maintainer's.
- **Cookie files, a real public suffix, `Secure` over `https://` beyond item 11, the high level**:
  out of scope.
- **The exact cap:** an 8,100-byte value went whole and an 8,200-byte one hung; nothing between
  was tried.

## Files

| File | What it is |
|---|---|
| `make-prototype.sh`, `prototype.py`, `prototype.diff` | The prototype: the copy, the patch, the recorded diff. |
| `jar.sps` | The program, in parts; its header lists them and the output's lines. |
| `main.sps` | Item 10's half on main's `src/`. |
| `standin.mjs` | The stand-in, Node's standard library alone; `--selftest` checks its report. |
| `fswatch.c` | The file watch, built in the Guix container, preloaded for item 3 on Linux. |
| `run.sh`, `docker.sh`, `all.sh`, `controls.sh`, `mac.sh` | One lane; the Docker lanes and the network check; everything; the controls; the Mac. |
| `tables.mjs` | Every table from the logs: `node tables.mjs [TABLE,...]`, `--splits`, `--valgrind`, `--cite=ITEM/CASE`. |
| `results/` | `guix-8.20.0-{1,2}.log`, `docker-{1,2}.log`, `valgrind-ubuntu-openssl-8.5.0.log`, `controls-guix-8.20.0.log`, `netcheck-docker-default.log`. |

Rerun, from the repository's root, on the host (Docker and git there, builds in the container):

```sh
sh .plans/research/m7/slice4/all.sh 1 2 valgrind controls netcheck
# one lane: scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL CHEZ=$CHEZ sh .plans/research/m7/slice4/run.sh guix-8.20.0' < /dev/null
#           sh .plans/research/m7/slice4/docker.sh floor-7.85.0 [PART...]
build/verify/m3s2/node20/node .plans/research/m7/slice4/tables.mjs > tables.md
NODE="$(asdf which node)" sh .plans/research/m7/slice4/mac.sh      # on the Mac
```

## The tables

`tables.mjs` prints them all from the logs; four are copied below, the rest stay its output, so
they cannot drift from the logs. Its tables:
Lanes; 1 (the lifetime); 2 (the answers, and what each share carries); 3 (the order); 4 (each
line), 4x (the rule's gaps); 5 (each Set-Cookie's read-out), 5x (the lines the rule refuses); 6
(the cost); 7 (Host and Cookie); 8 (HTTP/2); 9 (rounds); 10 (the twins); 11 (HSTS); 12 (IPv6).

## Selected tables

Copied from `tables.mjs 2,3,9,11` as it printed them from the kept logs; the rest it prints on
demand. A cell bold is "run 1 / run 2"; "same" repeats the first lane's cell.

### Table: Item 2: curl_share_setopt's answers (CURLSHcode: 0 OK, 1 BAD_OPTION, 2 IN_USE, 5 NOT_BUILT_IN)

| call | cite | F | O | G | X | C |
|---|---|---|---|---|---|---|
| SHARE 0 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 0 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 0 after SHARE 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| SHARE 1 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 1 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 1 after SHARE 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| SHARE 2 on a fresh share | F docker-1.log:3086 | 0 | same | same | same | same |
| UNSHARE 2 on a fresh share | F docker-1.log:3086 | 0 | same | same | same | same |
| UNSHARE 2 after SHARE 2 | F docker-1.log:3086 | 0 | same | same | same | same |
| SHARE 3 on a fresh share | F docker-1.log:3086 | 0 | same | same | same | same |
| UNSHARE 3 on a fresh share | F docker-1.log:3086 | 0 | same | same | same | same |
| UNSHARE 3 after SHARE 2 | F docker-1.log:3086 | 0 | same | same | same | same |
| SHARE 4 on a fresh share | F docker-1.log:3086 | 0 | same | same | same | same |
| UNSHARE 4 on a fresh share | F docker-1.log:3086 | 0 | same | same | same | same |
| UNSHARE 4 after SHARE 2 | F docker-1.log:3086 | 0 | same | same | same | same |
| SHARE 5 on a fresh share | F docker-1.log:3086 | 0 | same | same | same | same |
| UNSHARE 5 on a fresh share | F docker-1.log:3086 | 0 | same | same | same | same |
| UNSHARE 5 after SHARE 2 | F docker-1.log:3086 | 0 | same | same | same | same |
| SHARE 6 on a fresh share | F docker-1.log:3086 | 5 | 0 | 0 | 0 | 5 |
| UNSHARE 6 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 6 after SHARE 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| SHARE 7 on a fresh share | F docker-1.log:3086 | 1 | 0 | 0 | 0 | 0 |
| UNSHARE 7 on a fresh share | F docker-1.log:3086 | 1 | 0 | 0 | 0 | 0 |
| UNSHARE 7 after SHARE 2 | F docker-1.log:3086 | 1 | 0 | 0 | 0 | 0 |
| SHARE 8 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 8 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 8 after SHARE 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| SHARE 9 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 9 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 9 after SHARE 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| SHARE 99 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 99 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE 99 after SHARE 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| SHARE -1 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE -1 on a fresh share | F docker-1.log:3086 | 1 | same | same | same | same |
| UNSHARE -1 after SHARE 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| option 0 (NONE), value 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| option 6 (LAST), value 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| option 99, value 2 | F docker-1.log:3086 | 1 | same | same | same | same |
| a share a handle holds: SHARE 3, UNSHARE 2 | F docker-1.log:3086 | 2 | same | same | same | same |
| a share a handle holds: UNSHARE 2 | F docker-1.log:3086 | 2 | same | same | same | same |
| a share a handle holds: cleanup | F docker-1.log:3086 | 2 | same | same | same | same |
| cleanup once the handle is cleaned up | F docker-1.log:3086 | 0 | same | same | same | same |

### Table: Item 2: what a share set so carries between two transfers (make's codes; what the second sent)

| share | cite | F | O | G | X | C |
|---|---|---|---|---|---|---|
| carry-SHARE-0 | F docker-1.log:3169 | (((1 0 1)) 0); second sent none | same | same | same | same |
| carry-SHARE-1 | F docker-1.log:3185 | (((1 1 1)) 0); second sent none | same | same | same | same |
| carry-SHARE-2 | F docker-1.log:3201 | (((1 2 0)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-3 | F docker-1.log:3219 | (((1 3 0)) 0); second sent none | same | same | same | same |
| carry-SHARE-4 | F docker-1.log:3235 | (((1 4 0)) 0); second sent none | same | same | same | same |
| carry-SHARE-5 | F docker-1.log:3251 | (((1 5 0)) 0); second sent none | same | same | same | same |
| carry-SHARE-6 | F docker-1.log:3267 | (((1 6 5)) 0); second sent none | (((1 6 0)) 0); second sent none | (((1 6 0)) 0); second sent none | (((1 6 0)) 0); second sent none | (((1 6 5)) 0); second sent none |
| carry-SHARE-7 | F docker-1.log:3283 | (((1 7 1)) 0); second sent none | (((1 7 0)) 0); second sent none | (((1 7 0)) 0); second sent none | (((1 7 0)) 0); second sent none | (((1 7 0)) 0); second sent none |
| carry-SHARE-8 | F docker-1.log:3299 | (((1 8 1)) 0); second sent none | same | same | same | same |
| carry-SHARE-9 | F docker-1.log:3315 | (((1 9 1)) 0); second sent none | same | same | same | same |
| carry-SHARE-99 | F docker-1.log:3331 | (((1 99 1)) 0); second sent none | same | same | same | same |
| carry-SHARE--1 | F docker-1.log:3347 | (((1 -1 1)) 0); second sent none | same | same | same | same |
| carry-SHARE-2-UNSHARE-0 | F docker-1.log:3363 | (((1 2 0) (2 0 1)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-2-UNSHARE-1 | F docker-1.log:3381 | (((1 2 0) (2 1 1)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-2-UNSHARE-2 | F docker-1.log:3399 | (((1 2 0) (2 2 0)) 0); second sent none | same | same | same | same |
| carry-SHARE-2-UNSHARE-3 | F docker-1.log:3415 | (((1 2 0) (2 3 0)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-2-UNSHARE-4 | F docker-1.log:3433 | (((1 2 0) (2 4 0)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-2-UNSHARE-5 | F docker-1.log:3451 | (((1 2 0) (2 5 0)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-2-UNSHARE-6 | F docker-1.log:3469 | (((1 2 0) (2 6 1)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-2-UNSHARE-7 | F docker-1.log:3487 | (((1 2 0) (2 7 1)) 0); second sent "Cookie: k=1" | (((1 2 0) (2 7 0)) 0); second sent "Cookie: k=1" | (((1 2 0) (2 7 0)) 0); second sent "Cookie: k=1" | (((1 2 0) (2 7 0)) 0); second sent "Cookie: k=1" | (((1 2 0) (2 7 0)) 0); second sent "Cookie: k=1" |
| carry-SHARE-2-UNSHARE-8 | F docker-1.log:3505 | (((1 2 0) (2 8 1)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-2-UNSHARE-9 | F docker-1.log:3523 | (((1 2 0) (2 9 1)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-2-UNSHARE-99 | F docker-1.log:3541 | (((1 2 0) (2 99 1)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-SHARE-2-UNSHARE--1 | F docker-1.log:3559 | (((1 2 0) (2 -1 1)) 0); second sent "Cookie: k=1" | same | same | same | same |
| carry-none | F docker-1.log:3577 | (() 0); second sent none | same | same | same | same |

### Table: Item 3: SHARE then COOKIEFILE "", against COOKIEFILE "" then SHARE

| row | cite | F | O | G | X | C |
|---|---|---|---|---|---|---|
| detector: empty-path or detector opens | F docker-1.log:3598 | 1 | same | same | same | same |
| share-first: empty-path or detector opens | F docker-1.log:3605 | 0 | 3 | 3 | 0 | 0 |
| share-first: transfer 1 sent | F docker-1.log:3605 | none | same | same | same | same |
| share-first: transfer 2 sent | F docker-1.log:3605 | "Cookie: o2=loaded; od=1; o1=1" | same | same | same | same |
| share-first: transfer 3 sent | F docker-1.log:3605 | "Cookie: od=1" | same | same | same | same |
| share-first: read-out at the end | F docker-1.log:3605 | .a.localhost\x09TRUE\x09/\x09FALSE\x090\x09od\x091 ; a.localhost\x09FALSE\x09/\x09FALSE\x090\x09o1\x091 ; a.localhost\x09FALSE\x09/\x09FALSE\x090\x09o2\x09loaded ; b.a.localhost\x09FALSE\x09/\x09FALSE\x090\x09o3\x091 | same | same | same | same |
| file-first: empty-path or detector opens | F docker-1.log:3638 | 0 | 3 | 3 | 0 | 0 |
| file-first: transfer 1 sent | F docker-1.log:3638 | none | same | same | same | same |
| file-first: transfer 2 sent | F docker-1.log:3638 | "Cookie: o2=loaded; od=1; o1=1" | same | same | same | same |
| file-first: transfer 3 sent | F docker-1.log:3638 | "Cookie: od=1" | same | same | same | same |
| file-first: read-out at the end | F docker-1.log:3638 | .a.localhost\x09TRUE\x09/\x09FALSE\x090\x09od\x091 ; a.localhost\x09FALSE\x09/\x09FALSE\x090\x09o1\x091 ; a.localhost\x09FALSE\x09/\x09FALSE\x090\x09o2\x09loaded ; b.a.localhost\x09FALSE\x09/\x09FALSE\x090\x09o3\x091 | same | same | same | same |

### Table: Item 9: the requests libcurl makes inside one transfer

| case | cite | F | O | G | X | C |
|---|---|---|---|---|---|---|
| digest-401-sets-a-cookie | F docker-1.log:7918 | ok status=200 version=http/1.1; #1 401 sent none; #2 200 auth "digest" valid sent "Cookie: d401=1"; read out a.localhost\x09FALSE\x09/\x09FALSE\x090\x09d200\x091 ; a.localhost\x09FALSE\x09/\x09FALSE\x090\x09d401\x091 | same | same | same | same |
| expect-417-sets-a-cookie | F docker-1.log:7936 | ok status=200 version=http/1.1; #1 417 expect sent none; #2 200 expect sent "Cookie: e417=1"; read out a.localhost\x09FALSE\x09/\x09FALSE\x090\x09e200\x091 ; a.localhost\x09FALSE\x09/\x09FALSE\x090\x09e417\x091 | same | same | same | same |

### Table: Item 11: Strict-Transport-Security on an https:// transfer, then an http:// transfer to that host

| case | cite | F | O | G | X | C |
|---|---|---|---|---|---|---|
| cookie-share | F docker-1.log:8461 | make ok (((1 2 0)) 0); first https; second, an http:// URL, arrived as http | same | same | same | same |
| control-share-with-hsts | F docker-1.log:8479 | make ok (((1 2 0) (1 7 1)) 0); first https; second, an http:// URL, arrived as http | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https |
| share-with-hsts-second-without-ctrl | F docker-1.log:8497 | make ok (((1 2 0) (1 7 1)) 0); first https; second, an http:// URL, arrived as http | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https |
| share-with-hsts-no-ctrl-either | F docker-1.log:8515 | make ok (((1 2 0) (1 7 1)) 0); first https; second, an http:// URL, arrived as http | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https | make ok (((1 2 0) (1 7 0)) 0); first https; second, an http:// URL, arrived as https |
| no-jar | F docker-1.log:8533 | make ok none; first https; second, an http:// URL, arrived as http | same | same | same | same |
