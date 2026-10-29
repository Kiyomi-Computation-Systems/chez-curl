# M6 source reading: libcurl pause, streaming bodies, headers; Chez custom ports

Every answer below is **read, not measured**. Nothing was built or run.

Kept 2026-10-29 for the M6 plan, §2.2. The `scratchpad/m6/src/` trees it names, upstream 8.5.0 and a
treeless clone of curl's history, were downloads in the planning session's scratch directory,
not kept. The measurements that test these readings are in [`pause/`](pause/) and
[`ports/`](ports/).

## Trees and how to read the citations

Citations take the form `curl-X.Y.Z/path:line`. They point into these trees:

| Version | Tree | Note |
|---|---|---|
| 7.85.0 | `build/verify/current/curl-7.85.0` | the floor |
| 8.5.0 | `scratchpad/m6/src/curl-8.5.0` | upstream tarball, downloaded. **Ubuntu 24.04's build carries Debian/Ubuntu patches that nobody read.** Every 8.5.0 answer is for upstream 8.5.0. |
| 8.7.1 | `build/m4s3/src/curl-8.7.1` | upstream. **Apple's 8.7.1 may carry patches we cannot see.** |
| 8.8.0 | `build/m4s3/src/curl-8.8.0` | read only to date one 8.7.1 finding |
| 8.20.0 | `build/verify/current/curl-8.20.0` | Guix |
| 8.23.0 | `build/verify/current/curl-8.23.0` | |
| Chez 10.4.1 | `/gnu/store/vrdaswvmyj8rlzhs76w71zh3yzyddxpn-chez-scheme-10.4.1-checkout` | 10.4.0 is in the store too, at `/gnu/store/s39m4qaswcwmbbfqk24vv2hrlxsrbv46-chez-scheme-10.4.0-checkout`. The port sources are byte-identical between the two (checked with `cmp`: `s/io.ss`, `s/io-types.ss`, `s/library.ss`, `s/cpprim.ss`, `c/new-io.c`, `c/types.h`). |

Paths without a tree prefix are relative to the curl tree named in the same row or sentence.

**The code changes shape three times across the supported range.** These names recur below:

- **7.85.0 and 8.5.0: `tempwrite`.** Paused bytes go into `data->state.tempwrite[3]`, one dynbuf per *type* (body, header, ...), each capped at `DYN_PAUSE_BUFFER` (64 MiB). The data has already been content-decoded.
- **8.7.1: `cw-out`.** The last client writer, `lib/cw-out.c`, keeps an ordered list of buffers. Their total is capped at 64 MiB, and going over gives `CURLE_TOO_LARGE` (100). The data has already been decoded.
- **8.20.0 and 8.23.0: `cw-pause` plus `cw-out`.**
  - A "pause" writer, `lib/cw-pause.c`, sits *before* content decoding and holds raw bytes. In 8.20.0 it is always installed. In 8.23.0 it is installed only when a decoder is.
  - Pause is now a rate-limit block (`Curl_rlimit_block`), and the whole transfer loop honours it.
  - `cw-out` still caps decoded bytes at 64 MiB.

---

## Provenance

| Sections | Read by | Spot-checked by me |
|---|---|---|
| 1, 2, 3, 6, 7 | me | — |
| 4, 5 | a sub-agent, on Opus | the masks; 8.7.1's `has_used_cb`, length cap, PAUSE path and the two discarded results; 8.20.0's PAUSE path; 8.23.0's conncache stamp and 1 s skip; the Expect threshold; the PREREQ call site |
| 8 | a sub-agent, on Opus | four release tags with `git tag --contains`, and the buggy code for #12632, #21671, #13752 and #19653 in our trees |
| 9 | a sub-agent, on Opus | the `read!` and `write!` checks, the buffer size, `get-bytevector-some`, the thread-safety comment, and the 10.4.0 vs 10.4.1 `cmp` |

Two of my own section 1 claims were wrong in my first draft. The bug-history sub-agent's #12632 and #21671 flagged them; I then confirmed both in the trees, and the text above is corrected:

- 8.5.0's socket filter puts a paused socket back in the poll set.
- 8.20.0's TLS filter does the same.

---

## 1. Write pause

### 1a. Where the refused bytes are kept

| Version | Where | Cap, and what happens when it is exceeded |
|---|---|---|
| 7.85.0 | `chop_write` hands the refused chunk *and everything after it in the same write* (`ptr, len` from the refused chunk on) to `pausewrite` (`lib/sendf.c:569-577`). That appends to `tempwrite[i]` for the same type (`sendf.c:474-520`, append at `:513`). While paused, every later write goes straight to `pausewrite` (`sendf.c:543-544`). | 64 MiB per type (`lib/dynbuf.h:77`), then `CURLE_OUT_OF_MEMORY` (27) (`sendf.c:513-514`). Three types at most, else 27 (`sendf.c:499-501`). |
| 8.5.0 | The same, now keyed by type and `paused_body` (`lib/sendf.c:219-265`, append `:260`, refused chunk `:328-336`, already paused `:292-293`). | 64 MiB per type (`lib/dynbuf.h:81`), then 27. |
| 8.7.1 | `cw-out`. A write returning `CURL_WRITEFUNC_PAUSE` sets `KEEP_RECV_PAUSE` and stops (`lib/cw-out.c:220-230`). The unwritten rest is appended to an ordered list (`cw_out_do_write`, `cw_out_append`). Body bytes merge into the last buffer when it is a body buffer. **Every header write gets its own buffer** ("replay headers exactly as they came in"). | Total of all buffers ≤ 64 MiB, then `CURLE_TOO_LARGE` (100) (`cw-out.c:318-319`). |
| 8.20.0 | Two places. `cw-out` holds the unwritten rest of the refused chunk (`lib/cw-out.c:195-207`, which calls `Curl_xfer_pause_recv(data, TRUE)`). Raw bytes that arrive later are held by `cw-pause`, before decoding (`lib/cw-pause.c:142-205`). `cw-pause` is installed for every transfer, *behind* the download writer (`lib/sendf.c:335-347`). | `cw-out`: 64 MiB, then 100 (`cw-out.c:352-354`). `cw-pause`: a bufq with a soft limit, "should take everything up to OOM" (`cw-pause.c:48-53`, `:185-187`). |
| 8.23.0 | The same split. `cw-pause` is now added only when a writer flagged `CURL_CW_FLAG_BLOWUP` is (a content decoder: `lib/sendf.c:488-500`, `lib/content_encoding.c:300,363,498,613`). It became a FIFO with a tail pointer (`cw-pause.c:102-210`). **Without `ACCEPT_ENCODING` there is no `cw-pause`, and `cw-out` holds everything.** | `cw-out`: 64 MiB, then 100 (`cw-out.c:358-360`, `lib/curlx/dynbuf.h:67`). |

### 1b. Is the socket still read while paused?

**HTTP/1.1, over TCP and over TLS: no, on every version.**

1. The read loop stops after the read whose bytes paused.
   - 7.85.0: `lib/transfer.c:855-858`.
   - 8.5.0: `lib/transfer.c:716-719`.
   - 8.7.1: `lib/transfer.c:293-294`.
   - 8.20.0: the next pass of the loop sees the download rate limit blocked and breaks before it reads (`lib/transfer.c:251-264`, `Curl_rlimit_avail` returns 0 when blocked, `lib/ratelimit.c:198-202`).
   - 8.23.0: the same, `lib/transfer.c:250-262`.
2. The socket then leaves the poll set.
   - 7.85.0: `Curl_single_getsock` requires `(keepon & KEEP_RECVBITS) == KEEP_RECV` (`lib/transfer.c:1360`).
   - 8.5.0: the same test, `lib/transfer.c:1246`.
   - 8.7.1: `CURL_WANT_RECV` in `perform_getsock` (`lib/multi.c:1077`, `lib/urldata.h:597-598`).
   - 8.20.0: `multi_adjust_pollset` removes `IN` while the limit is blocked (`lib/multi.c:986-997`).
   - 8.23.0: the same, `lib/multi.c:968-979`.
   - Each perform also skips the read: `Curl_readwrite` with `fd_read = BAD` (7.85.0 `transfer.c:1181-1184`), `Curl_sendrecv` returning early when blocked (8.20.0 `transfer.c:361`, 8.23.0 `transfer.c:360`).
   - **But a connection filter can put the socket back, so the poll returns at once whenever bytes wait in the kernel. That is a busy loop, though reads stay skipped:**
     - **8.5.0:** `Curl_conn_adjust_pollset` runs after `Curl_single_getsock` (`lib/multi.c`, `multi_getsock`, the `MSTATE_PERFORMING` case). The socket filter adds `POLLIN` for *any* connected socket (`lib/cf-socket.c:1244-1248`). Fixed in 8.6.0 by 8e2d7b9f, which added the `!ctx->active` test that 8.7.1 has (`curl-8.7.1/lib/cf-socket.c:1249-1255`). Issue #12632.
     - **8.20.0 over TLS:** the TLS filter adds `POLLIN` while its `io_need` says read (`lib/vtls/vtls.c:545-565`). Nothing stops `Curl_conn_adjust_pollset` calling the filters for a blocked transfer (`lib/cfilters.c:884-897`). Fixed in 8.21.0 by 5e4e6296, which skips the filters once connected when the transfer's pollset is empty. Issue #21671. The reporter's case is `curl_multi_perform` + `curl_multi_poll` + `CURL_WRITEFUNC_PAUSE` over TLS, which is our loop.
     - **7.85.0, 8.7.1 and 8.23.0:** no such path found.
3. **So libcurl holds at most one receive buffer's worth.** That is `BUFFERSIZE`, default `READBUFFER_SIZE` = 16 KiB (7.85.0 `lib/url.c:630`, 8.23.0 `lib/url.c:414`), plus what decoding makes of it (1d). Everything else waits in the kernel socket buffer, and TCP flow control pushes back on the server.
4. **Over TLS**, the TLS library may already have read and decrypted a record past what curl took. It holds that data until the next read. On unpause libcurl forces a read so that it is not stranded:
   - 7.85.0: `conn->cselect_bits = IN|OUT` (`lib/easy.c:1155-1157`).
   - 8.5.0: `easy.c:1112-1114`.
   - 8.7.1: `data->state.select_bits` (`easy.c:1138-1141`).
   - 8.20.0 and 8.23.0: `Curl_multi_mark_dirty` (8.20.0 `easy.c:1172`). The receive loop also marks the transfer dirty when input is buffered (8.20.0 `transfer.c:313-319`).

**HTTP/2: only to serve other streams, and how much the paused stream then buffers differs by version.**

- With one stream on the connection, the paused transfer's socket is not polled and its reads are skipped, as in h1.
  - 7.85.0: `http2_getsock` adds `READSOCK` only when not paused (`lib/http2.c:111-114`).
  - 8.5.0 and later: the h2 filter's pollset starts from `CURL_WANT_RECV` or the pollset rules above (8.5.0 `lib/http2.c:2313-2335`, 8.20.0 `lib/http2.c` `cf_h2_adjust_pollset`).
- With *other active streams* on the same connection, their reads also process DATA frames for the paused stream.

Per version:

| Version | Stream window | On a write pause | Where the paused stream's DATA goes |
|---|---|---|---|
| 7.85.0 | Initial window 32 MiB (`HTTP2_HUGE_WINDOW_SIZE`, `lib/http2.c:64`, `:1218-1219`). nghttp2's automatic window updates are on: no `no_auto_window_update`. | `pausewrite` calls `Curl_http2_stream_pause(TRUE)`, which sets the stream's local window to 0 and sends (`lib/sendf.c:488`, `lib/http2.c:2161-2190`). | DATA is copied into the transfer's buffer. When that is full, `NGHTTP2_ERR_PAUSE` stops nghttp2 for the *whole connection* (`http2.c:850-878`). A sibling stream's recv then returns `CURLE_AGAIN` while `pause_stream_id` is set (`http2.c:1738-1754`). **Unsure: a paused stream may stall its siblings.** |
| 8.5.0 | 10 MiB (`H2_STREAM_WINDOW_SIZE`, `lib/http2.c:72`, `:101-102`). Automatic window updates are off (`http2.c:344`). | `pausewrite` → `Curl_conn_ev_data_pause(TRUE)` (`sendf.c:233`) → `http2_data_pause`: window 0 (`http2.c:2418-2460`). | The per-stream `recvbuf` (`http2.c:1300`). That is consumed only when the transfer reads (`http2.c:1974`), so the window closes by itself. The paused stream buffers **≤ about 10 MiB**. |
| 8.7.1 | 10 MiB (`http2.c:72`, `:101-102`). Automatic window updates are off (`http2.c:331`). | **Nothing closes the window.** `cw-out` only sets `KEEP_RECV_PAUSE` (`cw-out.c:229`). The only caller of `Curl_conn_ev_data_pause` is the *unpause* in `easy.c:1123`. `http2.c` has no other pause check: grep finds only `http2_data_pause` itself, `:2392-2461`. | DATA goes straight into `Curl_xfer_write_resp`, so into `cw-out`'s buffer, and is **consumed at once**: `nghttp2_session_consume`, `http2.c:1255-1259`. The window stays open. **With an active sibling stream, the paused stream's buffer can grow past 10 MiB until it reaches 64 MiB and fails with 100.** The same holds in 8.8.0, where `easy.c`'s unpause is again the only caller (`curl-8.8.0/lib/transfer.c:413`). |
| 8.20.0 | Starts at 64 KiB and is raised to 10 MiB after the head (`lib/http2.c:69-75`, `cf_h2_update_local_win` `:309-357`, called from `h2_xfer_write_resp_hd` `:900-912`). Automatic window updates are off (`http2.c:471`). | `Curl_xfer_pause_recv` → `Curl_conn_ev_data_pause` (`transfer.c:926-934`) → `http2_data_pause`, which sets `write_paused` and a desired window of 0 (`http2.c:2636-2660`). `h2_xfer_write_resp` notices the pause too (`http2.c:932-943`). | Straight into the writer stack, so into `cw-pause` or `cw-out`, and consumed (`http2.c:1294-1297`). With the window at 0 the server can send only what was already granted: **≤ about 10 MiB**. |
| 8.23.0 | The same as 8.20.0 (`http2.c:67-73`, `:327-375`). | The same (`transfer.c:885-894`, `http2.c:2626-2650`, `:970-981`). | The same. |

The docs lag the code here. 8.5.0 to 8.20.0's `curl_easy_pause` page still says h2 announces "a 32 megabyte window" (e.g. 8.20.0 `docs/libcurl/curl_easy_pause.md:94-95`). 8.23.0's says 10 MB (`curl_easy_pause.md:91-101`).

### 1c. How much can be buffered

- **h1:** one receive buffer, 16 KiB by default. `BUFFERSIZE` can raise it to `CURL_MAX_READ_SIZE`: 512 KiB on 7.85.0 (`include/curl/curl.h:235`), 10 MiB from 8.5.0 (`include/curl/curl.h:244`). Add what decoding makes of that buffer (1d).
- **h2:** the stream window (table above). 7.85.0's is 32 MiB. 8.5.0, 8.20.0 and 8.23.0 hold ≤ about 10 MiB. 8.7.1 has no bound below 64 MiB when siblings are active.
- **The hard caps:** 64 MiB per type on 7.85.0 and 8.5.0 (error 27). 64 MiB total in `cw-out` on 8.7.1, 8.20.0 and 8.23.0 (error 100). 8.20.0 and 8.23.0's `cw-pause` has no hard cap.

### 1d. Content decoding (`ACCEPT_ENCODING`)

- **7.85.0 to 8.7.1:** decoding happens *before* the pause buffer.
  - The inflate loop decompresses all of the input it was handed, writing each output chunk downstream, and never checks for a pause (7.85.0 `lib/content_encoding.c:186-215`, `DSIZ` = 16 KiB `:55`).
  - So one 16 KiB receive buffer is decoded in full into the pause buffer. Deflate tops out near 1032:1, so that is about 16 MiB, under the 64 MiB cap.
  - A larger `BUFFERSIZE` could pass the cap and fail with 27 on 7.85.0 and 8.5.0, or 100 on 8.7.1.
  - 7.85.0's own manual says to avoid pausing with automatic decompression (`docs/libcurl/curl_easy_pause.3`, "MEMORY USE"), and 8.23.0's repeats it.
- **8.20.0:** `cw-pause` sits before the decoders. While decoding, it hands them **4 KiB of raw input at a time** and stops once the client has paused (`cw-pause.c:142-172`, `CW_PAUSE_DEC_WRITE_CHUNK` `:37`). It buffers the rest raw. At most about 4 KiB × the ratio of decoded data can pile up in `cw-out`.
- **8.23.0:** the same, but `cw-pause` exists only with a decoder. When it exists, it always feeds body bytes in 4 KiB pieces (`cw-pause.c:157-172`).

### 1e. Delivery on unpause

**From inside `curl_easy_pause`, on every version.** The buffered bytes go to the write callback, and to the header callback for any buffered head lines, *before* `curl_easy_pause` returns:

- 7.85.0: `Curl_client_write` of each `tempwrite` slot (`easy.c:1103-1131`).
- 8.5.0: `Curl_client_unpause` → `chop_write` (`easy.c:1085-1089`, `sendf.c:422-450`).
- 8.7.1: `Curl_cw_out_flush` (`easy.c:1122-1126`, `cw-out.c:429-432`).
- 8.20.0: `Curl_xfer_pause_recv(FALSE)` → `Curl_cwriter_unpause` → `Curl_cw_out_unpause`. That flushes `cw-pause` through the decoders, then `cw-out` (`transfer.c:926-934`, `sendf.c:510-513`, `cw-out.c:492-505`).
- 8.23.0: `Curl_cwriter_unpause` → `Curl_cwriter_flush` over the whole stack (`sendf.c:528-532`, `cw-pause.c:102-147`, `cw-out.c:462-480`).

**So decoders run inside `curl_easy_pause` on 8.20.0 and 8.23.0.** A decoding error can come back as `curl_easy_pause`'s result.

Data still in the kernel, the TLS library or nghttp2 arrives at the **next perform**. Every version makes that perform come at once:

- 7.85.0 to 8.7.1: `Curl_expire(data, 0, EXPIRE_RUN_NOW)` (7.85.0 `easy.c:1149`, 8.5.0 `:1106`, 8.7.1 `:1133`).
- 8.20.0 and 8.23.0: `Curl_multi_mark_dirty` (8.20.0 `easy.c:1172`, 8.23.0 `:1234`). `multi_timeout` gives 0 when any handle is dirty (8.20.0 `multi.c:107-110`).
- `curl_multi_poll` caps its wait at `multi_timeout` (7.85.0 `multi.c:1222-1223`, 8.5.0 `:1181-1182`, 8.7.1 `:1274-1275`, 8.20.0 `:1620-1621`, 8.23.0 `:1609`).
- **So the engine's next `curl_multi_poll` after an unpause returns at once.** It does not wait the 1000 ms.

**Chunk size.** The body goes to the write callback in pieces of **at most `CURL_MAX_WRITE_SIZE` = 16 KiB**, on every version, unpause included:

- 7.85.0: `sendf.c:561`.
- 8.5.0: `sendf.c:320`.
- 8.7.1: `cw-out.c:171`.
- 8.20.0: `cw-out.c:153`.
- 8.23.0: `cw-out.c:153`.

`BUFFERSIZE` bounds receive sizes, not callback sizes.

- **8.20.0 with decoding, and 8.23.0 with decoding:** `cw-pause` feeds 4 KiB of *raw* input at a time. The callback still sees decoded pieces of up to 16 KiB.

**The same chunk, or merged with later data?**

- **Body, merged, on every version.** The refused bytes are the head of the next delivery. The pieces after the pause are cut at 16 KiB boundaries from the merged buffer, so they need not match the refused chunk's length.
  - 7.85.0 and 8.5.0: one buffer per type, appended to (`sendf.c:505-514` / `:253-262`), replayed through `chop_write`.
  - 8.7.1 to 8.23.0: a body buffer takes later body bytes until a header buffer comes between them (`cw_out_append`).
- **Bound:** 64 MiB, as in 1c.

**Head lines buffered across a pause:**

- 7.85.0 and 8.5.0 merge every buffered header write of one type into one slot. They replay it as **one header callback call holding several lines** (`chop_write` writes `optr, olen` whole, 7.85.0 `sendf.c:604-607`).
- They also push the replayed text to the headers API a second time, because `Curl_headers_push` sits in `chop_write` (7.85.0 `sendf.c:590-602`, 8.5.0 `sendf.c:345-357`). **Unsure**: that should duplicate or garble `curl_easy_header` entries. It matters only if a header callback pauses, or trailers arrive while paused.
- 8.7.1 and later keep one buffer per header write, and push headers in their own writer, `hds-collect`, before `cw-out` (8.23.0 `lib/headers.c:412-428`, 8.7.1 `headers.c:353-376`).

**A transfer cannot finish while paused with bytes buffered.** It ends only after the unpause delivers them:

- 7.85.0: `done` needs `KEEP_RECV_PAUSE` clear (`transfer.c:1336-1337`).
- 8.20.0: `req.done && !Curl_cwriter_is_paused` (`multi.c:2084`).
- 8.23.0: `multi.c:2095`.

---

## 2. `curl_easy_pause` itself

| | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| Entry | `lib/easy.c:1067` | `easy.c:1046` | `easy.c:1082` | `easy.c:1133` | `easy.c:1194`, inside an API guard (`CURL_EAPI_ENTER`) |
| No connection (`!data->conn`) | `CURLE_BAD_FUNCTION_ARGUMENT` (43) (`:1073-1076`) | 43 (`:1053-1056`) | 43 (`:1089-1092`) | 43 (`:1141-1144`) | 43 (`:1204-1208`) |
| State unchanged | returns `CURLE_OK` early (`:1086-1090`) | the same (`:1068-1072`) | the same (`:1104-1108`) | no early return: nothing toggles. If not blocked, it still marks the transfer dirty and resets the low-speed clock (`:1168-1176`). | the same (`:1230-1238`) |
| Unpause receive | h2 window back to 32 MiB plus a send (`:1104`, `http2.c:2161-2190`). Replays `tempwrite` (`:1106-1131`). | `Curl_conn_ev_data_pause(FALSE)` (h2 window plus egress), then `Curl_client_unpause` (`:1085-1090`) | the same, then `Curl_cw_out_flush` (`:1122-1126`) | `Curl_xfer_pause_recv`: rate-limit unblock, flush the writers, `Curl_conn_ev_data_pause`, progress (`transfer.c:926-934`) | the same (`transfer.c:885-894`) |
| Unpause send | mime-only unpause (`:1094-1099`) | the same (`:1075-1080`) | `Curl_creader_unpause` (`:1110-1116`) | `Curl_xfer_pause_send` → `Curl_creader_unpause` (`transfer.c:916-924`) | `transfer.c:875-883` |
| Timers and wakeups | `Curl_expire(0, EXPIRE_RUN_NOW)` and `Curl_update_timer`, which calls `CURLMOPT_TIMERFUNCTION` if set (`:1146-1161`). `Curl_updatesocket`, which calls `CURLMOPT_SOCKETFUNCTION` if set (`:1164-1167`). | the same (`:1103-1124`) | the same (`:1130-1151`) | `Curl_multi_mark_dirty`. `Curl_update_timer` on a change. `Curl_multi_ev_assess_xfer` (socket callback) on a change (`:1168-1184`). | the same (`:1230-1244`) |
| Low-speed clock | reset when not pausing both ways (`:1152`) | `:1109` | `:1136` | `:1170` | `:1232` |

None of them calls `curl_multi_wakeup`. The engine calls `curl_easy_pause` on its own thread between turns, so the dirty mark or `EXPIRE_RUN_NOW` is enough: the next poll returns at once (1e).

**Can it block?** Not by design, on any version.

- The h2 window update is sent through the non-blocking egress path: 7.85.0 `h2_session_send` (`http2.c:2184-2186`), 8.5.0 and later `h2_progress_egress`, result ignored (8.5.0 `http2.c:2443`).
- It takes no lock. 8.23.0's guard checks a call stack and does not wait (`lib/api.c:187-300`).
- **It does call client code: the write callback and the header callback, with decoders between them on 8.20.0 and 8.23.0.** It never calls the read callback (4a). Our callbacks must not wait.

**Can it call the callbacks before it returns?** Yes:

- **Write and header callbacks:** whenever bytes were buffered (1e).
- **The read callback:** never. The read resumes at the next perform (4a).
- **Re-pausing from inside the replay is allowed.**
  - 7.85.0 and 8.5.0 copy the slots out first ("to allow for immediate re-pausing", 7.85.0 `easy.c:1108-1114`, 8.5.0 `sendf.c:428-438`).
  - 8.7.1 and later stop flushing when a write pauses again (`cw-out.c:217-230`, `cw_out_flush_chain`).

**A failure during the replay comes back as `curl_easy_pause`'s result. What then happens to the transfer differs:**

- **7.85.0 and 8.5.0:** the slots are freed whatever the outcome (`easy.c:1121-1129`), so the transfer goes on without those bytes. The engine must fail the transfer itself.
- **8.20.0 and 8.23.0:** `cw-out` marks itself errored, and later writes fail (8.20.0 `cw-out.c:416-424`, `:486-489`).
- **8.7.1:** has no errored flag (it arrived with issue #13337, per the 8.20.0 comment `cw-out.c:417-418`). What happens next is unsure.

**Rule for the engine:** treat any non-zero result from `curl_easy_pause` as the transfer's failure, then remove the handle.

**What the docs forbid:**

- All versions: "you cannot call this function from another thread" (7.85.0 `docs/libcurl/curl_easy_pause.3`; 8.23.0 `curl_easy_pause.md:40-42`). The engine thread is the multi's thread, so that holds.
- `file://` cannot be paused.
- From 8.5.0 the docs allow calls from inside every callback except `CURLMOPT_SOCKETFUNCTION` (8.5.0 `curl_easy_pause.3:37`; 8.23.0 `.md:29-31`). 8.23.0 enforces it: `easy_pause` has `no_event_cb` set (`lib/api.c:55`).

**A transfer that is not paused** gets `CURLE_OK` with no effect (see "State unchanged" above).

**A handle already removed, or already completed:**

- `curl_multi_remove_handle` → `multi_done` detaches the connection.
- So does reaching `MSTATE_COMPLETED`: 8.20.0 `init_completed` calls `Curl_detach_connection` (`multi.c:116-123`).
- After either, `data->conn` is NULL, so `curl_easy_pause` returns **43**, `CURLE_BAD_FUNCTION_ARGUMENT`, on every version.
- That includes a transfer that **timed out while paused** (section 3): a resume message that comes after it gets 43. The engine should treat a resume for a finished token as a no-op, and not report it as an error.
- The handle must still be a live easy handle. After `curl_easy_cleanup` the call is a use-after-free.

---

## 3. A paused transfer and its clocks

**`CURLOPT_TIMEOUT_MS` still fires while paused, on time, with nothing arriving. This holds on every version.**

1. The deadline is armed as a timer when the transfer starts connecting:
   - 7.85.0: `Curl_expire(.., data->set.timeout, EXPIRE_TIMEOUT)` (`multi.c:1900-1901`).
   - 8.20.0: `multi.c:2533-2534`.
   - 8.23.0: `multi.c:2496`.
2. `curl_multi_poll` wakes for the earliest timer (the citations in 1e).
3. `curl_multi_perform` runs *every* transfer it holds, paused ones included:
   - 7.85.0: the loop over `multi->easyp` (`multi.c:2678-2690`).
   - 8.7.1: the same.
   - 8.20.0 and 8.23.0: the `process` bitset (8.20.0 `multi.c` `multi_perform`, 8.23.0 the same).
4. `multi_runsingle` checks the deadline first, for every state from `CONNECT` up to `COMPLETED`, before any pause logic:
   - 7.85.0 `multi.c:1855-1872`, `multi_handle_timeout` at `:1637-1684`.
   - 8.20.0 `multi.c:2510-2514`.
   - 8.23.0 `multi.c:2776-2783`.

The result is `CURLE_OPERATION_TIMEDOUT` (28), and the connection is closed.

**Consequence: `TIMEOUT_MS` counts the consumer's stall time.** A body that has fully arrived but sits paused in libcurl still times out, because the transfer cannot complete while paused (1e). For streaming, the engine probably wants no total timeout, or one owned by the engine, or one documented as covering consumer time too.

**The low-speed check:**

| | Skipped while receive is paused | Skipped while send is paused |
|---|---|---|
| 7.85.0 | yes (`lib/speedcheck.c:44-46`) | **no** |
| 8.5.0 | yes (`speedcheck.c:44-46`) | **no** |
| 8.7.1 | yes (`speedcheck.c:44-46`) | **no** |
| 8.20.0 | yes (`lib/progress.c:137-140`) | yes |
| 8.23.0 | yes (`progress.c:135-138`) | yes |

So on 7.85.0, 8.5.0 and 8.7.1, an upload whose read callback is paused, waiting on an empty producer, with `LOW_SPEED_LIMIT` and `LOW_SPEED_TIME` set, should fail with 28 ("Operation too slow") after `LOW_SPEED_TIME`. Every version resets the low-speed clock on unpause (section 2). The docs say only "A paused transfer is excluded from low speed cancels", without naming a direction (7.85.0 `curl_easy_pause.3`; 8.23.0 `.md:52-54`).

---

## 4. Read pause

A sub-agent read this section. Lines marked † I re-read myself.

### 4a. Resuming

**The masks.** `CURLPAUSE_RECV` is 1, `CURLPAUSE_SEND` is 4, and `CURLPAUSE_RECV_CONT`, `CURLPAUSE_SEND_CONT` and `CURLPAUSE_CONT` are all **0**, on every version †(7.85.0 `include/curl/curl.h:3092-3099`; 8.23.0 `curl.h:3284-3291`).

- The argument is the complete new state, so `SEND_CONT` *is* `CONT`: it unpauses both directions.
- To resume sending while receive stays paused, pass `CURLPAUSE_RECV`.
- **The engine must keep both pause bits for each transfer and pass both on every call.**

**`curl_easy_pause` never calls the read callback, on any version.** The read resumes at the next `curl_multi_perform`.

- 7.85.0 and 8.5.0: `Curl_mime_unpause` touches mime bodies only (7.85.0 `easy.c:1094-1099`).
- 8.7.1: `Curl_creader_unpause` hits the default no-op (`easy.c:1110-1116`).
- 8.20.0 and 8.23.0: `cr_in` only clears `is_paused` (8.20.0 `sendf.c:888-890`).
- A resume that arrives before the PAUSE return is a no-op (section 2).

**Where the next read happens:**

- **h1 with Content-Length, and h1 chunked:**
  - 7.85.0: PAUSE sets `KEEP_SEND_PAUSE` and backs out the chunk-prefix room (`transfer.c:244-262`). `readwrite_upload` breaks out (`:1006-1009`).
  - 8.5.0: `transfer.c:250-268`, `:861-864`.
  - 8.7.1: `cr_in_read` sets `KEEP_SEND_PAUSE` †(`sendf.c:670-681`). `readwrite_upload` returns early (`transfer.c:353-354`). The chunk encoder emits nothing for a 0-byte read that is not EOS (`http_chunks.c:541-590`).
  - 8.20.0 and 8.23.0: `Curl_xfer_pause_send(TRUE)` †(8.20.0 `sendf.c:697-712`; 8.23.0 `sendf.c:717-732`). Then `Curl_req_send_more` skips the read (`request.c:463-466`).
- **h2:** the body source returns `NGHTTP2_ERR_DEFERRED`, and a later send resumes it.
  - 7.85.0: `http2.c:1184-1187`, resumed at `:1875-1877` / `:1900-1905`.
  - 8.5.0: `http2.c:1588-1591`, resumed at `:2212-2214`.
  - 8.7.1: `http2.c:1557-1560`, resumed at `:2175`.
  - 8.20.0: `http2.c:1625-1629`, resumed at `:2066-2071`.
  - 8.23.0: `http2.c:1636-1640`, resumed at `:2036`.
  - No version was found that cannot resume. All of them resume only at the next perform.
  - 7.85.0 and 8.5.0 rely on the forced `IN|OUT` select bits. **Unsure** on a busy multiplexed connection.
- **8.5.0 has a stall** with one direction paused (`select_bits_paused`, fixed in 8.6.0 by cdd905a9; section 8). An h2 transfer whose read is paused may stop processing receive events.

### 4b. When the read callback is first called

- 7.85.0 and 8.5.0: in `PERFORM`, after the request head was sent.
- 8.7.1 and later: during `DO`, inside `Curl_req_send`. The first call shares the send buffer with the request head (5c).
- **`CURL_READFUNC_PAUSE` is allowed on the very first call, on every version.**

### 4c. Framing

| Setup | h1.1 | HTTP/1.0 | h2 |
|---|---|---|---|
| `POST` + `POSTFIELDSIZE_LARGE` -1 | `Transfer-Encoding: chunked` | error 25 ("Chunky upload is not supported by HTTP 1.0") | no Content-Length. DATA frames; END_STREAM after the callback's 0 |
| `POST` + N | `Content-Length: N` | `Content-Length: N` | `content-length: N`; END_STREAM with the last byte |
| `UPLOAD` (PUT) + `INFILESIZE_LARGE` -1 | chunked | 25 | as -1 above |
| `UPLOAD` + N | `Content-Length: N` | the same | as N above |
| `CUSTOMREQUEST` beside either | replaces only the method word; framing follows POST or PUT | | |

Citations:

- **Chunked for -1:** 7.85.0 `http.c:2351-2376`; 8.5.0 `:2488-2513`; 8.7.1 `:2120-2140`; 8.20.0 `:2397-2416`; 8.23.0 `:2455-2475`.
- **Error 25:** 7.85.0 `:2366`; 8.5.0 `:2503`; 8.7.1 `:2130`; 8.20.0 `:2406`; 8.23.0 `:2464`.
- **Content-Length:** 7.85.0 `http.c:2408`, `:2550`; 8.5.0 `:2562`, `:2691`; 8.7.1 `:2213`; 8.20.0 `:2487`; 8.23.0 `:2514`.
- **h2 drops Transfer-Encoding and keeps Content-Length:** 7.85.0 `h2h3.c:111`; 8.5.0 `http.c:4828`; 8.7.1 `:4250`; 8.20.0 `:4880`; 8.23.0 `:4953`.
- **h2 END_STREAM:** 7.85.0 `http2.c:1463-1482`, `:1960`; 8.5.0 `:1649-1670`, `:2069`; 8.7.1 `:1618-1640`, `:2029`; 8.20.0 and 8.23.0 through the eos flag (`http2.c:1625` / `:1638`).
- **Method:** UPLOAD gives PUT and POST gives POST (`Curl_http_method`; 7.85.0 `http.c:2032-2071`).
  - 7.85.0's `set.upload` sticks, so POST set after UPLOAD still sends PUT (`http.c:2038-2039`; fixed in 7.86.0, #9507).
  - From 8.5.0 the upload state follows from the method (8.5.0 `transfer.c:1280`).
- **An empty body, size 0, never calls the read callback:** 7.85.0 `http.c:2440`, `:2674`, `:2692`; 8.5.0 `:2797`; 8.7.1 `:2025`, `:2040`; 8.20.0 `:2292-2305`; 8.23.0 `:2374-2387`.
- **A user `Content-Length:` header:** libcurl adds none of its own but still reads by the size option. With -1 on h1 the result is *both* Content-Length and chunked.
- **A user `Transfer-Encoding: chunked`:**
  - 7.85.0 and 8.5.0: chunked, and N is ignored.
  - 8.7.1: chunked, but it stops at N. That is #13229, fixed in 8.8.0. **Unsure:** over h2, chunk framing may go inside the DATA frames (`http.c:2191-2195` vs `:2744`).
  - 8.20.0 and 8.23.0: chunked. N is disregarded for POST and kept for PUT (8.20.0 `http.c:2316-2329`).
- **An empty `Transfer-Encoding:` or `Content-Length:` header** removes libcurl's own header and sends nothing in its place, on every version (7.85.0 `transfer.c:99-114`, `http.c:1878-1888`). The body is then unframed.
- **Advice:** chez-curl should use only the size options, and never send framing headers of its own.

### 4d. `Expect: 100-continue`

**When libcurl adds it.** The threshold is 1 MiB †(`EXPECT_100_THRESHOLD`, 7.85.0 `lib/http.h:163`; 8.23.0 `http.h:151`).

| Version | POST | PUT | Where |
|---|---|---|---|
| 7.85.0 | size > 1 MiB or unknown (`http.c:2577`) | **any non-zero size** †(`http.c:2418-2422`; fixed in 8.0.0, #10740) | h1.1 only, never h2 (`:1720-1721`) |
| 8.5.0 | > 1 MiB or unknown, for both methods (`http.c:2518-2539`) | the same | `:1702-1703` |
| 8.7.1 | the same (`http.c:2145-2178`) | the same | |
| 8.20.0 | the same | the same | only when the version is exactly 1.1 (`:2441-2446`) |
| 8.23.0 | the same | the same | `:2499-2504` |

- **An empty `Expect:` header in `HTTPHEADER` removes it, on every version** (7.85.0 `http.c:1725-1729`, `:2572-2576`; 8.20.0 `:2436-2439`).
- **`EXPECT_100_TIMEOUT_MS` defaults to 1000** (7.85.0 `url.c:628` … 8.23.0 `url.c:412`). On timeout libcurl sends the body anyway (7.85.0 `transfer.c:1239-1259`; 8.23.0 `http.c:1580-1590`).
- **The read callback is never called before the 100 arrives or the timeout ends.**
- **A 417 makes libcurl retry once without Expect**, on every version.
  - The retry is a `FOLLOW_REDIR`, so it counts against `MAXREDIRS`: with 0 the result is 47.
  - Once body bytes were sent, 8.5.0 and later close the connection and rewind. 7.85.0 does neither. **Unsure:** it probably sends the rest of the stream.
- **A final response of 300 or more before the body ends:** libcurl stops sending, closes the connection afterwards and marks the upload done, unless `KEEP_SENDING_ON_ERROR` is set (7.85.0 `http.c:4120-4137` … 8.23.0 `:4139-4149`).
- **Unsure, and a hang risk on 7.85.0, 8.5.0 and 8.7.1:** such a response while the read is *paused* may not complete the transfer until the engine unpauses or a timeout fires. A producer that waits on the response would deadlock.
- **Unsure:** a 2xx before the 100 ends the transfer with the body unsent on 7.85.0 to 8.7.1. On 8.20.0 and 8.23.0 the body is sent after the 1 s timeout.
- **Advice:** send `Expect:` empty, unless the engine wants 417 handling.

### 4e. What 0 and `CURL_READFUNC_ABORT` mean

- **0 with Content-Length N, before N bytes:**
  - 7.85.0 and 8.5.0: libcurl stops sending, silently (7.85.0 `transfer.c:1010-1015`; 8.5.0 `:865-869`). The server waits.
  - 8.7.1, 8.20.0 and 8.23.0: **`CURLE_READ_ERROR` (26)**, "client read function EOF fail" †(8.7.1 `sendf.c:650-656`; 8.20.0 `:675-686`; 8.23.0 `:695-706`).
- **0 in chunked framing** sends `0\r\n\r\n` (7.85.0 `transfer.c:296-358`; 8.23.0 `http_chunks.c:511-522`).
- **0 on h2** sends END_STREAM.
- **`CURL_READFUNC_ABORT`** gives **42** in every framing (7.85.0 `transfer.c:239-243`; 8.23.0 `sendf.c:708-715`).
- **A return larger than the buffer** gives 26 ("funny value").
- **The buffer offered:**
  - 7.85.0 and 8.5.0 do *not* shrink it to the bytes still owed. A callback that fills it can send bytes past N.
  - 8.7.1 and later offer at most the bytes owed †(8.7.1 `sendf.c:633-640`).
- **After a 0:**
  - 7.85.0 can call the callback again after a 0. That was fixed in 8.5.0, by 6a095da1. It was a git-fetch hang.
  - 8.5.0 and later never call it again after a 0.

### 4f. The read callback's buffer size

`UPLOAD_BUFFERSIZE`: default 65536, minimum 16384, maximum 2 MiB (7.85.0 `urldata.h:177-179`; 8.23.0 `urldata.h:132-134`). Values outside the range are clamped. 8.20.0 and later refuse a negative one with 43.

| Version | Sizes for a plain body | Sizes for a chunked body |
|---|---|---|
| 7.85.0 and 8.5.0 | `UPLOAD_BUFFERSIZE` minus a leftover of under 2048 bytes: 63489 to 65536 by default. Not reduced by the bytes owed (7.85.0 `transfer.c:919-995`). | `UPLOAD_BUFFERSIZE` − 12 = 65524 (`transfer.c:213`) |
| 8.7.1, 8.20.0 and 8.23.0 | the free room in one `UPLOAD_BUFFERSIZE` send chunk, capped at the bytes owed. The first call shares the chunk with the request head, so it sees 65536 minus the head's length. Range 1 to 65536 (8.20.0 `bufq.c:84-101`). | 1024 when the room is under 1024; otherwise min(room, 65536) − 12. Range 1012 to 65524, never above 65524 whatever `UPLOAD_BUFFERSIZE` says (8.23.0 `http_chunks.c:484-485`) |

h2 adds no bound of its own. nghttp2 cuts at most 16 KiB frames from what libcurl holds.

---

## 5. Rewind

A sub-agent read this section. Lines marked † I re-read myself.

**When libcurl rewinds:**

| Version | Trigger | When | Failure |
|---|---|---|---|
| 7.85.0 | eager, and only if body bytes were *sent* (`writebytecount` > 0): `Curl_retry_request` (`transfer.c:1909-1917`), auth via `http_perhapsrewind` (`http.c:442-565`, `:620`), Location only with follow on (`:3645`) | at once | On the `RECV_ERROR` resend path, a failed rewind still reports **56**: the earlier error wins (`multi.c:2413-2416`). Elsewhere **65**. |
| 8.5.0 | the same triggers set `rewindbeforesend` (`transfer.c:1816-1821`, `http.c:625-629`), plus a 417 while sending | lazily, at `PROTOCONNECT` (`multi.c:2076-2078`, `readrewind` `:1731-1806`) | **65** (`multi.c:2099-2104`) |
| 8.7.1 | every retry and auth round asks for one (`transfer.c:1090`, `http.c:438`). **It runs only if the callback was ever called, even if that call only returned PAUSE** †(`sendf.c:646`, `has_used_cb` check at `:791-793`) | in the follow step, in `Curl_client_start` †(`sendf.c:142-162`) | **Unsure, and serious:** the error may be dropped. `Curl_req_soft_reset` is called and its result ignored †(`transfer.c:915`). `Curl_init_do`'s result is ignored too †(`url.c:3761`). The transfer may then call the read callback again *without rewinding*. **Measure on the Mac, where Apple may have patched this.** |
| 8.20.0 | as 8.7.1 (`transfer.c:700`, `http.c:414`, `sendf.c:671`, `:823`) | `sendf.c:95-114` | **65** (`http.c:1287`, `:1389-1390`) |
| 8.23.0 | as 8.7.1 (`transfer.c:659`, `http.c:423`, `sendf.c:691`, `:845`) | `sendf.c:96-115` | **65** (`http.c:1438`, `:1451-1452`) |

**What libcurl calls to rewind, in order:**

1. `SEEKFUNCTION(0, SEEK_SET)`.
2. Otherwise `IOCTLFUNCTION(CURLIOCMD_RESTARTREAD)`.
3. Otherwise `fseek`, but only with the default `fread` reader.
4. Otherwise **65, `CURLE_SEND_FAIL_REWIND`**.

Any non-zero seek result, `CURL_SEEKFUNC_CANTSEEK` included, gives 65 here. CANTSEEK's "work around" path serves only resume-from (8.7.1 `sendf.c:723-784`).

**What makes libcurl resend:**

- **A dead reused connection.** libcurl resends when the connection was reused and no response byte has arrived, whatever was sent. This covers `RECV_ERROR` or a done in PERFORM, `SEND_ERROR` in DO, and h2 `HTTP_1_1_REQUIRED`. A `SEND_ERROR` in PERFORM is **not** resent and gives 55. After 5 tries the result is 55.
- **h2 `REFUSED_STREAM` or GOAWAY** when no bytes were received (7.85.0 `http2.c:1529-1534` … 8.23.0 `:1712`).
- **`HTTP_1_1_REQUIRED` on a fresh connection.** **Unsure:** libcurl may redo the request over h1 *without* a rewind, so the body would go on from mid-stream (7.85.0 `multi.c:2428-2445`; 8.23.0 `:2050-2071`).
- **Auth.** Multi-pass schemes send a zero-length probe first, so the callback is not used for it. A 401 in the middle of a body rewinds.
- **Redirects** rewind only with `FOLLOWLOCATION` on. Here it is off, so a 3xx in the middle of a body takes the stop-and-close path of 4d.
- **A body of which nothing was read needs no rewind:**
  - 7.85.0 and 8.5.0: "nothing *sent*".
  - 8.7.1 and later: "callback never called".
  - Because of 4b, **on 8.7.1 and later a resend of a body of 1 MiB or less without Expect needs a SEEKFUNCTION, or it fails with 65.** The callback has already been called by then, during DO.
- **Unsure, on 7.85.0 and 8.5.0:** bytes the callback produced but libcurl had not sent are dropped on a resend (7.85.0 `url.c:4219`).

**8.23.0's unchecked reuse.**

- A connection's `lastchecked_ms` is stamped when it goes back to the pool †(`lib/conncache.c:956-958`).
- `Curl_cpool_conn_seems_healthy` returns TRUE without a probe within 1000 ms of that †(`conncache.c:1041-1052`), called from `url.c:1069-1074`.
- 8.20.0 and earlier always probe an idle connection: 8.20.0 `url.c:1255` → `:627-675`; 8.7.1 `url.c:1296`; 8.5.0 `url.c:1294`; 7.85.0 `url.c:1222`.
- The change arrived in 8.22.0 (2f1e94ea). It was fixed after 8.23.0 by ef6b17cf, "conncache: poll an idle connection for pending input on every reuse". **This is the root of ADR-0020's trap.**

**So on 8.23.0, libcurl's own resends, and with them rewinds, are more frequent.** For a streamed body on a connection that died under 1 s after its last use:

- size of 1 MiB or less, no SEEKFUNCTION: **65**;
- with a SEEKFUNCTION: one seek, `(0, SEEK_SET)`, and the producer must replay;
- chunked, or over 1 MiB (Expect holds the callback back): the resend succeeds with no seek;
- an EPIPE while sending in PERFORM: **55**;
- **56** only if response bytes had arrived.

**A guard for every version: `CURLOPT_PREREQFUNCTION`.** It runs at `MSTATE_DO` for each attempt, after any seek †(8.23.0 `multi.c:2159-2165`; 7.85.0 `multi.c:2124`; 8.5.0 `:2125`; 8.7.1 `:2129`; 8.20.0 `:2148`).

- Returning `CURL_PREREQFUNC_ABORT` ends the transfer with 42.
- So a producer that cannot replay can refuse a second attempt, which closes the "resend without rewind" holes above.
- The callback takes no easy handle. The engine would key it by `PREREQDATA`.
## 6. Header callback

**Calls per head line, h1.** One call per line, on every version: the status line, each field line, and the empty line that ends the head.

- 7.85.0: each line goes through `Curl_client_write(CLIENTWRITE_HEADER|...)` (`lib/http.c:4356`). The empty line goes through `http.c:4049-4056`.
- 8.23.0: field lines at `http.c:4459`. The empty line via `http_write_header` (`http.c:1694-1718`, called at `:4188` for a 1xx and at `:4294` for the final head).
- **The empty line is delivered as the server sent it.** Usually that is `"\r\n"`, but a bare `"\n"` is accepted too (7.85.0 `http.c:3931`; 8.23.0 `http.c:4313`).

**Calls per head line, h2.** Synthesised, on every version, and fed through the same h1 parser, so there is one call per line:

- the status line `"HTTP/2 <code> \r\n"`, **with a space before CRLF**;
- `"<name>: <value>\r\n"` for each field, the name as sent (lower case in h2);
- `"\r\n"` at the end of every HEADERS frame.

| Version | Status line | Field lines | Empty line |
|---|---|---|---|
| 7.85.0 | `http2.c:1102-1109` | `:1133` | `:764` |
| 8.5.0 | `http2.c:1499-1506` | `:1530` | `:1056` |
| 8.7.1 | `http2.c:1468-1475` | `:1499` | `:1011` |
| 8.20.0 | `http2.c:1532-1536` | `:1563` | `:996` |
| 8.23.0 | `http2.c:1549-1553` | `:1580` | `:1036` |

**1xx heads (100 Continue, 103 Early Hints): yes, every head ends with its own empty-line call.**

- h1: the 1xx empty line is written like any other, with `CLIENTWRITE_1XX`. The parser then starts a new head (7.85.0 `http.c:3940-3990` and `:4049-4056`; 8.23.0 `http.c:4185-4192` and `http_on_1xx_response`).
- h2: each 1xx HEADERS frame gets its `"\r\n"` (7.85.0 `http2.c:758-766`; 8.23.0 `http2.c:1027-1036`).
- **It is exactly `"\r\n"` on h2.** On h1 it is whatever line ending the server sent.

**Can the first write callback come before the final head's empty line?** No, on every version, with `CURLOPT_HEADER` off.

- 8.23.0: body bytes are written only once the head parse returns with `req.header` FALSE (`http.c:4683-4735`). The final empty line is written inside that parse (`http.c:4292-4294`).
- 7.85.0: the same order in `Curl_http_readwrite_headers`.
- Across a pause, buffered head and body bytes replay in arrival order:
  - 7.85.0 and 8.5.0: by slot, in creation order. The head's slot is created first.
  - 8.7.1 and later: an ordered list.
- One exception exists: HTTP/0.9-style "not a header" data is written as body (8.23.0 `http.c:4695-4703`). It is off by default.

**May `curl_easy_header` and `curl_easy_nextheader` be called from inside a header or write callback?** Yes, on every version.

- The docs say so: "fine to call from within libcurl callbacks. It will always return the state of the headers at the time it is called" (7.85.0 `docs/libcurl/curl_easy_header.3:78-80`; 8.23.0 `curl_easy_header.md:76-78`).
- 8.23.0's guard table allows both, along with `getinfo`, from inside callbacks (`lib/api.c:52-54`).
- A line is stored **before** the header callback sees it:
  - 7.85.0: `Curl_headers_push` precedes the call (`sendf.c:590-607`).
  - 8.7.1 and later: the `hds-collect` writer sits before `cw-out` (8.23.0 `headers.c:412-428`).
  - So inside the callback for `X: y`, `curl_easy_header("X")` finds it.

**What `request` -1 gives mid-transfer:** the current request, meaning the headers stored so far for it.

- -1 maps to `data->state.requests` (7.85.0 `headers.c:82-85`; 8.23.0 `headers.c:85-90`).
- The counter is zeroed per transfer (8.23.0 `transfer.c:494`).
- It is bumped for every follow that is not `FOLLOW_FAKE` (7.85.0 `transfer.c:1583-1584`; 8.23.0 `http.c:1396-1397`). With `FOLLOWLOCATION` off, a `Location` is `FOLLOW_FAKE` and bumps nothing.
- **`FOLLOW_RETRY`, libcurl's own resend, does bump it, and so does an auth round** (`newurl` → `FOLLOW_REDIR`). So -1 after a resend or an auth round is the new request. The header callback will have seen *both* heads.
- Stored headers stay until the next transfer on the handle starts (`Curl_headers_cleanup` in pretransfer: 7.85.0 `transfer.c:1538`).

**How `CURLH_1XX` headers are kept apart:** by type, not by request number.

- 1xx heads share the final head's request number, stored with type `CURLH_1XX` (7.85.0 `sendf.c:590-597`; 8.23.0 `headers.c:416-420`).
- `CURLH_HEADER` alone excludes them.
- **Two 1xx heads in one request (100, then 103) cannot be told apart** through the API. The header callback is the only way to split them.

**8.7.1 analyses the head late.** It writes the final empty line to the header callback *before* it analyses the response:

- the write is at `lib/http.c:3759`, `http_on_response` at `:3775`;
- 8.23.0 writes it afterwards (`http.c:4294`);
- 7.85.0 calls `Curl_http_size` before the write (`http.c:4011`, write `:4054`).

So in 8.7.1's callback for the empty line, `CURLINFO_CONTENT_LENGTH_DOWNLOAD_T` and similar infos still read -1. Fixed in 8.9.0 by 17af2bca ("http: write last header line late", #13752). Read the head's infos after the callback for the empty line returns, not inside it.

**`CURLINFO_RESPONSE_CODE` from inside the callback:**

- It is set when each status line is parsed, *before* that line is written to the header callback:
  - 7.85.0: `Curl_http_statusline` (`http.c:3701-3706`), called at `:4326`, before the write at `:4356`.
  - 8.23.0: `http_statusline` at `http.c:4433` (sets it at `:3797`), before the write at `:4459`.
  - h2 status lines take the same path.
- So in the callback for a 1xx status line and its fields, it reads that 1xx code. From the final status line on, it reads the final code.
- 8.23.0 allows `getinfo` from callbacks (`api.c:52`).

---

## 7. Cancel while paused

**`curl_multi_remove_handle` does nothing special for a paused handle, on any version.** Here is what it does, in order:

1. It counts the handle premature, because `mstate < MSTATE_COMPLETED`:
   - 7.85.0: `multi.c:791`.
   - 8.23.0: `multi.c:782`.
2. It calls `streamclose` on the connection, for states past `DO`:
   - 7.85.0: `multi.c:801-806`.
   - 8.5.0: `multi.c:847`.
   - 8.7.1: `multi.c:863`.
   - 8.20.0: `multi.c:822`.
   - 8.23.0: `multi.c:787-788`.
3. It calls `multi_done(premature)`.

**Are the buffered bytes freed?** Yes, without calling any callback:

- 7.85.0: `multi_done` frees `tempwrite` (`multi.c:680-685`).
- 8.5.0: `Curl_client_cleanup` (`multi.c:700`).
- 8.7.1: `Curl_req_done(aborted=TRUE)` skips the flush and resets the client writers, freeing `cw-out` (`request.c:96-104`, `multi.c:717`).
- 8.20.0 and 8.23.0: the same, freeing `cw-out` and `cw-pause`. 8.20.0 `request.c:103-111`, `multi.c:749`; 8.23.0 `request.c:102-110`, `multi.c:733`.

**Is the connection kept or closed?**

- **h1: closed**, never pooled. A premature done on a connection that is not multiplexed is disconnected:
  - 7.85.0: `multi.c:704-709` (`premature && !(handler->flags & PROTOPT_STREAM)`).
  - 8.5.0: `:747`.
  - 8.7.1: `:764`.
  - 8.20.0: `:628`.
  - 8.23.0: `:629`.
- **h2: the stream is reset and the connection is kept** for its other streams.

No protocol-level drain happens either way.

---

## 8. Known bugs, 7.86.0 to 8.23.0

### How this was compiled

A sub-agent compiled this list. Its sources:

- **The changelog.** https://curl.se/changes.html: 6,762 entries from 7.86.0 to 8.23.0. It searched them by term and read the 866 hits.
- **Commit history.** A treeless clone of curl/curl from 7.85.0 to master, in `scratchpad/m6/src/curl.git`. First releases come from `git tag --contains`.
- **Fixes after 8.23.0.** The pending release notes, https://curl.se/dev/release-notes.html.
- **About 50 GitHub issues.**

Its working files are in `scratchpad/m6/src/` (`changes.html`, `range.tsv`, `hits.tsv`, `issues/`).

**What I verified myself:**

- **Release tags.** I re-ran `git tag --contains` for four commits. Each first appears where the table says:
  - 8e2d7b9f in curl-8_6_0;
  - 5e4e6296 in curl-8_21_0;
  - 17af2bca in curl-8_9_0;
  - b5265b24 in curl-8_18_0.
- **The buggy code in our trees,** for four of the bugs:
  - #12632: `curl-8.5.0/lib/cf-socket.c:1244-1248`;
  - #21671: `curl-8.20.0/lib/cfilters.c:884-897`, against the fix diff;
  - #13752: `curl-8.7.1/lib/http.c:3759` vs `:3775`;
  - #19653: the `speedcheck.c` lines in section 3.

**How to read the table:**

- "Carriers" lists the supported versions that ought to have the bug, among 7.85.0, 8.5.0, 8.7.1, 8.20.0 and 8.23.0.
- "(src)" means the carrier was inferred from reading source, not taken from the commit. "?" means unsure.
- **8.7.1** means upstream 8.7.1. Apple may have backported fixes, and nobody can see that.
- **8.5.0.** The Launchpad changelog for Ubuntu noble, up to 8.5.0-2ubuntu10.16, lists only security patches and one LDAP crash fix. None of them is in this table. That is the changelog text; nobody read the patches.

### The ones that bite M6

| Fixed in | Fix | What the bug did | Carriers |
|---|---|---|---|
| 8.6.0 | `http: adjust_pollset fix`, 8e2d7b9f, #12632 | A paused transfer's socket stayed in the poll set. Effects: a busy loop, or the pause buffer filling until error 27. | 8.5.0 |
| 8.6.0 | `transfer: make the select_bits_paused condition check both directions`, cdd905a9 | With one direction paused, the transfer loop returned early on every event. h2 transfers using `READFUNC_PAUSE` stuck. | 8.5.0 |
| 8.21.0 | `cfilters: fix busy loop on blocked transfers`, 5e4e6296, #21671 | A paused TLS transfer spun at 100% CPU. The report's case is perform, poll and `WRITEFUNC_PAUSE`: our loop. | 8.20.0 |
| 8.8.0 | `http2: emit RST when client write fails`, 1302aa6b, #13292 | An error from the write callback on one h2 stream killed the whole connection. | 8.7.1 |
| 8.8.0 | `content_encoding: … pass through 0-length writes`, b30d694a, #13209 | Decoders failed the final 0-length EOS write with 23. That write is common on h2. | 8.7.1 |
| 8.8.0 | `cw-out: improved error handling`, 270a25c0, #13337 | After a pause and resume, the write callback was called again after it had returned `CURL_WRITEFUNC_ERROR`. | 8.7.1 (7.85.0 and 8.5.0 ?) |
| 8.8.0 | `request: paused upload on completed download, assess connection`, cfc65fd1, #13260 | Download done and upload paused: a connection close went unnoticed. | 8.7.1 |
| 8.8.0 | `http: with chunked POST forced, disable length check on read callback`, 721941aa, #13229 | A user `Transfer-Encoding: chunked` plus `READFUNCTION` plus a POST size: the body was cut at the size. | 8.7.1 |
| 8.9.0 | `http: write last header line late`, 17af2bca, #13752 | The final empty header line reached the header callback before the head was analysed. `CONTENT_LENGTH_DOWNLOAD_T` and similar read -1. | 8.7.1 |
| 8.9.0 | `transfer: do not use EXPIRE_NOW while blocked`, 3841569e, #13908 | A busy loop while paused. | 8.7.1 ? (src) |
| 8.12.0 | `http2: fix data_pending check`, 5b73a7b6, #16084 | The poll returned at once, repeatedly, during h2 uploads. | 8.5.0, 8.7.1 (src) |
| 8.13.0 | `client writer: handle pause before decoding`, f7870081, #16280 | Pause plus gzip overflowed the 64 MiB post-decode pause buffer. This fix brought in `cw-pause`. | 7.85.0, 8.5.0, 8.7.1 |
| 8.15.0 | `http2: do not delay RST send on aborted transfer`, 1454aa17, #17611 | After a timeout or abort, the RST_STREAM sat unsent. | 8.5.0, 8.7.1 |
| 8.18.0 | `speedcheck: do not trigger low speed cancel on transfers with CURL_READFUNC_PAUSE`, b5265b24, #19653 | `LOW_SPEED_LIMIT` aborted uploads paused by the read callback. | 7.85.0, 8.5.0, 8.7.1 |
| 8.5.0 | `transfer: avoid calling the read callback again after EOF`, 6a095da1 | The read callback could be called again after it returned 0. | 7.85.0 |
| 8.3.0 | `transfer: also stop the sending on closed connection`, 95a865b4, #11769 | A paused or chunked upload did not end when the connection was lost. | 7.85.0 ? |
| after 8.23.0 | `conncache: poll an idle connection for pending input on every reuse`, ef6b17cf | An idle connection was reused unchecked within 1 s of its last check (section 5). | 8.23.0. Started in 8.22.0, 2f1e94ea. |
| after 8.23.0 | `setopt: keep a paused transfer paused when the speed limit is changed`, a8b9f531 | Setting `MAX_RECV_SPEED` or `MAX_SEND_SPEED` on a paused transfer unpaused it. | 8.20.0, 8.23.0 |
| after 8.23.0 | `cw-pause: only pass EOS with the last flushed piece`, f29c5d3f, #23461 | A buffered EOS was flushed as several EOS writes. | 8.20.0, 8.23.0 |

### (a) Pause and unpause: the rest

| Fixed in | Fix | What the bug did | Carriers |
|---|---|---|---|
| 7.88.1 | `http2: buffer/pausedata and output flush fix`, 3103de20, #10529 | Corrupt multiplexed h2 downloads. | none (from 7.88.0) |
| 7.88.1 | `http2: set drain on stream end`, 87ed650d, #10530 | Data pending at END_STREAM was never read. | none (from 7.88.0) |
| 8.1.0 | `http2: always EXPIRE_RUN_NOW unpaused http/2 transfers`, 5622e431, #11005 | An unpaused h2 transfer was not run again. | none. 7.85.0 already expires (src). |
| 8.4.0 | `h2: testcase and fix for pausing h2 streams`, 6b9a591b, #11982 | Paused h2 transfers with no Content-Length were reported complete without all their data. | 7.85.0 ? |
| 8.4.0 | `curl_easy_pause: set "in callback" true on exit if true`, dc4e885f, #12059 | An unpause inside a callback cleared the in-callback flag. | 7.85.0 ? |
| 8.5.0 | `transfer: abort pause send when connection is marked for closing`, 6a0dc7cf, #12428 | A paused send never ended after the server closed. | 7.85.0 |
| 8.7.0 | `multi: fix multi_sock handling of select_bits`, f274fc5c, #12971 | `curl_multi_socket_action` only. | none |
| 8.9.0 | `transfer: conn close on paused upload`, 30de937b, #13740 | A follow-up to #13260. Short known-length bodies were not failed. | none (8.8.0 only) |
| 8.9.0 | `multi: fix pollset during RESOLVING phase`, 480883cf, #14047 | Moved the write-unpause into `curl_easy_pause`. Matters to socket-callback users. | ? |
| 8.10.1 | `transfer: fix sendrecv() without interim poll`, a33bcc9b, #14898 | A paused transfer never progressed without a poll in between. | none (8.10.0 only) |
| 8.14.0 | `http2: fix stream window size after unpausing`, 5fbd78eb, #16955 | nghttp2 ignored the WINDOW_UPDATE sent on unpause, and the transfer stalled. | none (8.10.0 to 8.13.x) |
| 8.17.0 | `cw-out: fix EAGAIN handling on pause`, 7e91f24c, #19334 | h2 transfers that paused from the write callback failed with 23. | none (8.16.0 only) |
| 8.17.0 | `mime: fix unpausing of readers`, 40f7cd2b, #18848 | A MIME read callback that paused was never called again. | 8.7.1 ? (MIME only) |
| 8.18.0 | `ratelimit: redesign`, 24b36fdd, #19384 | Context, not a fix: pause became a blocked rate limiter. | n/a |
| 8.19.0 | `easy: reset pausing when resetting request`, 078b3031, #20641 | A handle removed and re-added while paused never reconnected. | none (8.18.x only) |
| 8.21.0 | `multi: handle pause in multi socket callback`, 5ab34cba, #21748 | A pause from `SOCKETFUNCTION` was a use-after-free. Since 8.22.0 it is refused (#22179). | 8.20.0, socket-callback users only |
| 8.23.0 | `cw-out: avoid O(n^2) …`; `cw-pause: fix O(N^2) list traversal`, #22896, #22968 | Quadratic CPU when many writes buffer while paused. | 8.20.0; 8.7.1 for cw-out ? |
| 8.23.0 | `cw-out: recheck callbacks for each call`, 8940c143, #23085 | A callback replaced mid-flush was not used. | 8.7.1 ?, 8.20.0 ? |
| after 8.23.0 | `cw-out: avoid nested flush when unpausing from a callback`, e88cd7e1 | Reverted (fa83ab1f); still open on master. | ? |
| 8.22.0, not in the changelog | b41c28e7 and ab8d771d: client writer and reader tweaks | `cw-pause` installed only while decoding (as read in section 1). | n/a |

### (b) h2, TLS and buffers while paused

| Fixed in | Fix | What the bug did | Carriers |
|---|---|---|---|
| 8.1.0 | `http2: enlarge the connection window`, de4b0164, #10988 | The connection stalled when most of its streams were paused. | none (7.85.0 ?) |
| 8.1.0 | `http2: do flow window accounting for cancelled streams`, a9b7f72b, #11052 | Data buffered for an aborted stream never returned to the connection window. | 7.85.0 ? |
| 8.1.0 | `multi: free up more data earleier in DONE`, 81b2b577, #10971 | A leak when cancelling a paused h2 transfer. | 7.85.0 ? |
| 8.9.0 | `transfer: set CSELECT_IN if there is data pending`, cb5c7039, #13695 | Stalls when buffered data sat below curl with the socket not readable. Mostly SSH. | 7.85.0, 8.5.0, 8.7.1 |
| 8.10.0 | `gnutls: send all data`, 6354b35d, #14722 | A send wrote one record per call. | 7.85.0 and 8.5.0 GnuTLS builds ? |
| 8.11.0 | `http2: auto reset stream on server eos`, fe2a7202, #15316 | After a 413 with END_STREAM, curl kept uploading for minutes, then failed with 18. | 7.85.0, 8.5.0, 8.7.1 ? |
| 8.16.0 | `openssl: check SSL_write() length on retries`, ec4c5591, #18121 | A blocked SSL_write retried with a different length failed. | 7.85.0, 8.5.0, 8.7.1 OpenSSL and LibreSSL builds ? |
| 8.23.0 | `http2: fix reset after 1xx response`, 790a2192, #23104 | A reset after a 1xx was treated as if the final head had arrived. | all before ? |
| after 8.23.0 | `http2: do not let a rate limit enlarge the stream window`, c4b341c4 | A very high `MAX_RECV_SPEED` gave a flow-control error. | 8.20.0, 8.23.0 |
| SecureTransport: 7.88.0, 8.0.0 | #10227, #10717 | Partial IO reported as noErr; wrong receive codes. | 7.85.0 SecureTransport builds |

### (c) Read callbacks, uploads, rewind, Expect

| Fixed in | Fix | What the bug did | Carriers |
|---|---|---|---|
| 7.86.0 | `setopt: when POST is set, reset the 'upload' field`, #9507 | POST set after UPLOAD stayed a PUT. | 7.85.0 |
| 7.87.0 | `lib: rewind BEFORE request instead of AFTER previous`, 1b397318, #9735 | A 301 that turned a POST into a GET still rewound, and gave 65 on input that cannot seek. | 7.85.0 |
| 7.88.0 | `HTTP/[23]: continue upload when state.drain is set`, 3de3ea6a, #10433 | An h2 upload stalled once the response arrived first. | 7.85.0 |
| 8.0.0 | `http: don't send 100-continue for short PUT requests`, #10740 | See 4d. | 7.85.0 |
| 8.3.0 | `http: close the connection after a late 417 is received`, #11678 | The connection was reused after a partly sent body. | 7.85.0 |
| 8.5.0 | `http: avoid Expect: 100-continue if Upgrade: is used`, #12022 | h2c only. | 7.85.0 |
| 8.9.0 | `sendf: fix CRLF conversion of input`, #14165 | `CURLOPT_CRLF` only. | 8.7.1 ? |
| 8.10.0 | `cfilters: send flush`; `http2: improved upload eos handling`, #14271, #14253 | h2 upload EOS stalls. | 8.5.0 ?, 8.7.1 ? |
| 8.13.0 | `request: clear sendbuf_hds_len …`; `sendf: line conversion do not change infilesize`, #16573 | Wrong header length on retries; CRLF only. | 8.7.1 ? |
| 8.14.1 | `http: fail early when rewind of input failed when following redirects`, 71bb004c, #17472 | A 307 or 308 with a body ignored a failed rewind and reported success. | 8.5.0, 8.7.1 (7.85.0 ?). Follow on only. |
| 8.16.0 | `libcurl: reset rewind flag in curl_easy_reset()`, a93113b5, #18206 | After a 65, every request on a reset handle failed with 65. | 8.7.1 |
| 8.21.0 | `http: prefer chunked encoding over Content-Length: 0`, #21706 | Commit only, no description. | ? |
| 8.23.0 | `http2: don't send a CURLE_SEND_ERROR after a valid http2 response`, 11df32bc, #22984 | An early full response, then the final send on the closed stream gave 55. | 8.20.0 (8.5.0 ?, 8.7.1 ?) |
| after 8.23.0 | `transfer: drop a pending read rewind when a new transfer starts`, acf8a65b | Stale readers left after a failed redirect with a body. | 8.20.0, 8.23.0 ? |
| 8.1.x to 8.3.0 | h2 upload rework regressions (#11165, #11194, #11342, #11247, #11485, #11756) | Introduced and fixed inside 8.1.0 to 8.3.0. | none |

### (d) The header callback and the headers API

| Fixed in | Fix | What the bug did | Carriers |
|---|---|---|---|
| 7.86.0 | `headers: reset the requests counter at transfer start`, 9c9e8393, #9424 | Request indexes were off on a reused handle. | 7.85.0 |
| 8.0.0 | `headers: make curl_easy_header and nextheader return different buffers`, 05616379, #10704 | Using both in one loop clobbered results. | 7.85.0 |
| 8.1.0 | `headers: clear (possibly) lingering pointer in init`, #11101 | A stale `prev` pointer on handle reuse. | 7.85.0 |
| 8.3.0 | `headers: accept leading whitespaces on first response header`, #11605 | Behaviour change: 7.85.0 rejects. | 7.85.0 |
| 8.6.0 | `headers: make sure the trailing newline is not stored`, a9e128d5 | `"hdr: \r\n"` stored the value `"\r"`. | 8.5.0 |
| 8.9.0 | #13752 | See "The ones that bite M6". | 8.7.1 |
| 8.13.0 | `http2: reset stream on response header error`, #16535, #16544 | Header errors only sent GOAWAY. | 7.85.0, 8.5.0, 8.7.1 ? |
| 8.18.0 | `http: unfold response headers earlier`, #19949 | **Behaviour change:** from 8.18.0 the header callback gets folded headers unfolded. 7.85.0, 8.5.0 and 8.7.1 pass the raw lines. | differs |
| 8.21.0 | `http: reject spurious CR bytes in headers`, #21882 | Behaviour change: now an error. | differs |
| 8.23.0 | `http2: limit trailers and headers count`; `http: reject empty header names`, #23165, #23292 | Limits. | — |

### (e) Decoding, removing handles, timeouts

| Fixed in | Fix | What the bug did | Carriers |
|---|---|---|---|
| 8.21.0 | `content_encoding: timeout during slow decoding`, #21603 | A decompression bomb ran past `CURLOPT_TIMEOUT`. | 7.85.0, 8.5.0, 8.7.1, 8.20.0 |
| 8.5.0, 8.6.0 | `HTTP/2: handle detach of ongoing transfers`; `http2: improved on_stream_close/data_done handling`, #12356, #10936 | Use-after-free when a stream's easy handle was cleaned up before the connection. | 8.5.0 (7.85.0 ?) |
| 8.13.0 | `multi: start the loop over when handles are removed`, #16588 | Possible use of removed nodes. | 7.85.0, 8.5.0, 8.7.1 ? |
| 8.18.0 | `speedlimit: also reset on send unpausing`, #19687 | Probably 8.18.0-dev only. | none ? |

### `docs/KNOWN_BUGS`

- **8.23.0:** `KNOWN_BUGS.md` and `KNOWN_RISKS.md` say nothing about pause, read callbacks, rewind, the headers API or h2 flow control. The nearest entry: "HTTP/2 frames while in the connection pool kill reuse", also 17.2 in 7.85.0, 8.5.0 and 8.7.1.
- **7.85.0 adds** entries that are gone by 8.20.0:
  - 1.5 "Expect-100 meets 417". It looks stale; every tree retries on a 417.
  - 1.6 "Unnecessary close when 401 received waiting for 100".
  - 1.7 "Deflate error after all content was received" (#2719).
  - 1.11 "CURLOPT_SEEKFUNCTION not called with CURLFORM_STREAM" (#768).
  - 17.4 "Connection failures with parallel HTTP/2" (#5611).
## 9. Chez custom binary ports

The details come from a sub-agent. Spot-checked lines are marked †.

1. **`read!` takes `(bv start count)`, with count ≥ 1.**
   - **Fewer bytes than count is fine.** The result is checked as a fixnum in [0, count] †(`s/io.ss:722-726`).
   - **A return of 0 means EOF**, and nothing else does †(`io.ss:728-735`, `:794-797`). A custom port has no non-blocking mode (`io.ss:3695`). So "no data yet" can only be expressed by **blocking** inside `read!`.
   - An out-of-range or non-fixnum result raises a non-continuable `&assertion`: "invalid result ~s from read! on ~s" †(`io.ss:725`).
   - **EOF is not sticky.** Chez calls `read!` again after a 0, by a pattern that depends on the operation (`io.ss:754-756`, `:777-781`, `:3800-3804`, `:3843-3846`). So `read!` must keep returning 0 after the end.
   - `input-port-ready?` on an empty custom port raises (`io.ss:3645-3650`).
2. **Count is either of two things:**
   - the port buffer, `custom-port-buffer-size`, default **128**, read once when the port is made †(`io.ss:94-95`, `:3698`). get-u8, lookahead-u8 and port-eof? use it.
   - the caller's count, or `(file-buffer-size)`, for the `get-bytevector-*` calls. The default is `$c-bufsiz` = `max(BUFSIZ, 4096)` (`c/types.h:71-75`): about 8192 on glibc and 4096 on macOS. **Unsure until measured.**
3. **`write!` is looped by `bv-write!` until every byte is accepted** †(`io.ss:737-745`).
   - A 0 is accepted, and the loop simply calls again with the same arguments, so it spins. `write!` must block, not return 0.
   - `write!` is never called with count 0, so the body's end must come through `close`.
   - The output buffer is 128 bytes, usable 127 (`io.ss:4928-4931`).
   - A `put-bytevector` larger than the room left, or larger than 256 bytes, hands `write!` **the caller's own bytevector** (`io.ss:815-830`).
4. **`close` runs only from `close-port` or `call-with-port`, once** (`io.ss:844-851`, `:4906-4910`).
   - No guardian or finalizer exists for custom ports. A dropped port never closes and never flushes its up to 127 buffered bytes (`io.ss:378-397`, `7.ss:830`).
   - If `close` raises, the port stays open.
   - An output port flushes before closing. If `write!` raises there, `close` is never called.
5. **How the get operations use `read!`:**
   - `get-bytevector-some` calls `read!` **once** into a fresh bytevector of `file-buffer-size`, then truncates it. It returns the buffered bytes instead when there are any †(`io.ss:3872-3881`).
   - `get-bytevector-some!` calls it at most once.
   - `get-bytevector-n` and `get-bytevector-n!` loop until n bytes or EOF (`io.ss:3787-3870`).
   - `get-bytevector-all` loops until a 0.
6. **Chez holds no lock, opens no critical section and disables no interrupts around `read!` and `write!`** (`io.ss:125-131`, `:3643-3696`, `:4882-4927`). Chez says custom-port handlers are neither thread-safe nor task-safe †(`s/io-types.ss:17-28`; `csug/threads.stex:670-697`).
   - **So `read!` runs in whatever interrupt and mutex state its caller had.** A `get-*` called inside `critical-section` or `with-mutex` puts `read!`'s sleep-poll inside it: the project's wait-in-critical-section deadlock.
   - The threaded and `--nothreads` builds share this code (no `if-feature pthreads` in these paths).
7. **Hazards for a `read!` that waits:**
   - **(a) A `close-port` from another thread is not blocked, and races the read.** On the port-buffer path, a later inline `get-u8` can return bytes from a closed port (`io.ss:734`, `cpprim.ss:4234-4246`). The flag word is updated read-modify-write, so a closed bit could be lost. **Unsure how likely.**
   - **(b) A raise from `read!` is allowed, and the port stays consistent**, because all bookkeeping happens after `read!` returns. But inside one `get-bytevector-n` or `get-bytevector-n!` call, bytes from earlier `read!` calls are lost (`io.ss:3795-3809`). A Ctrl-C handler that escapes from `read!`'s sleep-poll counts as such a raise.
   - **(c) A raise from `write!` can duplicate bytes** on the next flush, because the buffer index is reset only after full success (`io.ss:811-812`, `:826-829`, `:836-838`).
   - **(d) No re-entrancy guard exists.**
   - **(e) Event checks between `read!`'s return and the port's bookkeeping.** Where they fall decides whether a timer or interrupt can lose bytes `read!` already took. **Unsure**; the sub-agent's H10 below is the probe.
## Hypotheses to measure

### How each case is laid out

Each case is one probe. It gives the protocol, the setup, what to watch, and the prediction.

**The defaults.** Every case runs on the chez-curl engine loop unless it says otherwise:

- perform, info_read, then poll for up to 1000 ms;
- `curl_easy_pause` called on the engine thread, outside any callback;
- `FOLLOWLOCATION` 0, `NOSIGNAL` 1.

"Inside pause" means callbacks that run while `curl_easy_pause` is on the stack. A flag set around the call shows it.

**How a prediction is written:** `7.85.0 / 8.5.0 / 8.7.1 / 8.20.0 / 8.23.0`, with "all" when the five agree. Everything here is read, not measured.

### The write side

**W1. Refused bytes come back.**
- **Protocol:** h1 over TCP.
- **Setup:** a 1 MiB Content-Length body sent at once. The write callback returns PAUSE on its first call; the engine unpauses after 200 ms.
- **Watch:**
  - whether the first callback after the pause starts with the refused bytes;
  - each callback's size;
  - whether those callbacks run inside pause;
  - whether the body arrives intact.
- **Predicted:** all five: re-delivered inside pause, starting with the refused bytes. Every call is at most 16384 bytes. The pieces after the pause may differ from the refused chunk's length. The body is intact.

**W2. The socket stops being read.**
- **Protocol:** h1 over TCP.
- **Setup:** the server writes 64 MiB as fast as it can. Pause on the first write, hold 3 s, then unpause.
- **Watch:**
  - how many bytes the server managed to write during the hold (it should block once the kernel buffers fill);
  - how many bytes are delivered inside pause.
- **Predicted:** all five: the server blocks after kernel buffers only. Inside pause libcurl delivers one receive buffer's worth: at most 16 KiB, minus what was delivered before the pause.

**W3. Busy loop while paused, TCP.**
- **Protocol:** h1 over TCP.
- **Setup:** W2.
- **Watch:** the number of engine turns, or `curl_multi_poll` returns, per second during the hold.
- **Predicted:** about 1 / **busy, thousands** (#12632) / about 1 / about 1 / about 1.

**W4. Busy loop while paused, TLS.**
- **Protocol:** h1 over TLS.
- **Setup:** W2.
- **Watch:** W3.
- **Predicted:** about 1 / **busy** / about 1 / **busy** (#21671; unsure, it depends on the TLS state) / about 1.

**W5. The h2 window while paused, one stream.**
- **Protocol:** h2 over TLS.
- **Setup:** the server tries to send 40 MiB on one stream. Pause on the first write, hold 3 s.
- **Watch:**
  - at the server: how many DATA bytes it could send, and whether flow control or TCP stopped it;
  - at the client: the bytes delivered inside pause.
- **Predicted:**
  - **The server is stopped by** TCP (window 32 MiB) / h2 flow control, at no more than 10 MiB / TCP (the window stays open) / h2, at no more than the granted window / h2, at no more than the granted window.
  - **Inside pause:** a small amount on every version, since no transfer reads (unsure for 8.5.0's `recvbuf`).

**W6. h2 with a sibling stream.**
- **Protocol:** h2 over TLS.
- **Setup:** streams A and B on one connection. Pause A and let B run for 5 s while the server sends A 80 MiB.
- **Watch:**
  - B's progress;
  - A's result, and the bytes delivered inside pause at A's unpause.
- **Predicted:**
  - **B:** may stall (unsure) / flows / flows / flows / flows.
  - **A's buffer:** unsure / at most 10 MiB / **grows until 64 MiB, then A fails with 100** / at most 10 MiB / at most 10 MiB.

**W7. Content decoding while paused.**
- **Protocol:** h1 over TCP.
- **Setup:** a gzip body that decodes about 1000:1 to 200 MiB, with `ACCEPT_ENCODING ""`. Pause on the first write, hold 1 s, unpause.
- **Watch:** the bytes delivered inside pause.
- **Predicted:** up to about 16 MiB (one 16 KiB receive, decoded) / the same / the same / up to about 4 MiB (4 KiB raw at a time) / up to about 4 MiB.

**W8. W7 with `BUFFERSIZE` 524288.**
- **Protocol:** h1 over TCP.
- **Setup:** W7.
- **Watch:** the result.
- **Predicted:** **27** / **27** / **100** / OK / OK.

**W9. Unpause starts at once.**
- **Protocol:** h1 over TCP.
- **Setup:** W2. After the unpause, time the gap until the next poll returns.
- **Watch:** that gap, which shows whether a wakeup is needed.
- **Predicted:** all five: under 10 ms. Every version arms a timer of 0 (`EXPIRE_RUN_NOW` or dirty).

**W10. `TIMEOUT_MS` while paused.**
- **Protocol:** h1 over TCP.
- **Setup:** `TIMEOUT_MS` 1500. A 100 KiB body arrives at once. Pause on the first write and never unpause.
- **Watch:** the result code, and when `CURLMSG_DONE` comes.
- **Predicted:** all five: 28, at 1500 ms plus a few ms, not at a 1000 ms poll step.

**W11. A full body held by a pause.**
- **Protocol:** h1 over TCP.
- **Setup:** a 1 KiB body, `TIMEOUT` 0. Pause on the first write; unpause after 500 ms.
- **Watch:** when `CURLMSG_DONE` comes.
- **Predicted:** all five: only after the unpause and its replay.

**W12. Low speed while receive is paused.**
- **Protocol:** h1 over TCP.
- **Setup:** `LOW_SPEED_LIMIT` 1000 and `LOW_SPEED_TIME` 1. Pause receive for 3 s.
- **Watch:** the result.
- **Predicted:** all five: no 28.

**W13. Pause on a finished handle.**
- **Protocol:** any.
- **Setup:** call `curl_easy_pause(CONT)` after `CURLMSG_DONE`, and again after `curl_multi_remove_handle`.
- **Watch:** the return code.
- **Predicted:** all five: 43, both times.

**W14. Pause with no change.**
- **Protocol:** any.
- **Setup:** `curl_easy_pause(CONT)` on a transfer that is not paused.
- **Watch:** the return code, and whether any callback runs.
- **Predicted:** all five: 0, and no callbacks.

**W15. An error during the replay.**
- **Protocol:** h1 over TCP.
- **Setup:** pause, then unpause; inside pause the callback returns 0, the wrong count.
- **Watch:**
  - `curl_easy_pause`'s result;
  - what the next perform does.
- **Predicted:**
  - **`curl_easy_pause`:** all five: 23.
  - **The next perform:** the transfer goes on and more body arrives (unsure) / the same (unsure) / unsure / it fails with 23 / it fails with 23.

**W16. Cancel while paused.**
- **Protocol:** h1 over TCP, then h2.
- **Setup:** pause with bytes buffered, then `curl_multi_remove_handle`.
- **Watch:**
  - write callbacks after the remove;
  - leaks, counted by the gate's counters and Valgrind;
  - what the server sees.
- **Predicted:** all five:
  - no callbacks and no leak;
  - h1: the server sees FIN, and the connection is never reused;
  - h2: RST_STREAM, and the connection stays up.
  - 8.5.0 and 8.7.1 may send the RST late (#17611).

**W17. Decoders and the 0-length end write on h2.**
- **Protocol:** h2 over TLS.
- **Setup:** a gzip body with `ACCEPT_ENCODING ""`, and no pause.
- **Watch:** the result.
- **Predicted:** OK / OK / **23** after the whole body (#13209; Apple may have patched it) / OK / OK.

**W18. A write error on one h2 stream.**
- **Protocol:** h2 over TLS.
- **Setup:** two streams on one connection. A's write callback returns `CURL_WRITEFUNC_ERROR`.
- **Watch:** B's result.
- **Predicted:** OK (unsure) / OK / **B fails** (#13292) / OK / OK.

### The header side

**H1. h1 head lines.**
- **Protocol:** h1 over TCP.
- **Setup:** a response of `100 Continue`, then `103` with `Link:`, then `200` with 3 fields, all CRLF. Read `RESPONSE_CODE` in every callback.
- **Watch:**
  - one header callback per line;
  - an exact `"\r\n"` call ending each of the 3 heads;
  - the code read in each callback.
- **Predicted:** all five: 3 + 1 + 2 + 1 + 4 + 1 calls. The codes read are 100 for the 100 head, 103 for the 103 head, and 200 from the 200 status line on.

**H2. h2 head lines.**
- **Protocol:** h2 over TLS.
- **Setup:** H1's heads, without the 100.
- **Watch:** the exact bytes of each line.
- **Predicted:** all five:
  - `"HTTP/2 103 \r\n"` and `"HTTP/2 200 \r\n"`, each with the space before CRLF;
  - field names in lower case;
  - `"\r\n"` after each head.

**H3. A bare-LF server.**
- **Protocol:** h1 over TCP.
- **Setup:** head lines that end in `\n`.
- **Watch:** the last header call.
- **Predicted:** all five: it holds exactly `"\n"`.

**H4. The headers API from inside the callback.**
- **Protocol:** h1 over TCP.
- **Setup:** H1. Inside each header callback, call `curl_easy_header(name, 0, CURLH_HEADER, -1)` and the same with `CURLH_1XX`.
- **Watch:** what each call finds.
- **Predicted:** all five:
  - the line being delivered is already findable;
  - `CURLH_HEADER` never shows 1xx fields;
  - the 100 and 103 fields are both under `CURLH_1XX`, and cannot be told apart.

**H5. Content length inside the callback for the empty line.**
- **Protocol:** h1 over TCP.
- **Setup:** `Content-Length: 1234`. Read `CONTENT_LENGTH_DOWNLOAD_T` in the callback for the final `"\r\n"`.
- **Watch:** the value read.
- **Predicted:** 1234 / 1234 / **-1** (#13752) / 1234 / 1234.

**H6. Head before body.**
- **Protocol:** h1 and h2.
- **Setup:** log the order of all callbacks.
- **Watch:** whether any write callback comes before the final head's empty line.
- **Predicted:** all five: none.

**H7. A pause from the header callback (only if M6 ever does it).**
- **Protocol:** h1 over TCP.
- **Setup:** the header callback pauses on the first field line; unpause later.
- **Watch:**
  - the lines replayed;
  - what `curl_easy_nextheader` then lists.
- **Predicted:**
  - **Replay:** several lines in one call, and the headers API may list some twice (unsure) / the same (unsure) / one call per line / one per line / one per line.

### The read side

The upload sub-agent's cases come first, under new numbers. The low-speed and Expect cases are mine.

**R1. Resume path, Content-Length.**
- **Protocol:** h1 over TCP.
- **Setup:** POST with CL 200000 and `Expect:`. The callback gives 1000 bytes, then PAUSE; the engine resumes with `CONT`.
- **Watch:**
  - whether a read callback runs inside pause;
  - when the next read happens;
  - whether the body is intact.
- **Predicted:** all five: no read inside pause; the next read in the next perform; the body intact.

**R2. Resume path, chunked.**
- **Protocol:** h1 over TCP.
- **Setup:** R1 with size -1.
- **Watch:** whether a `0\r\n` appears at any pause; the body.
- **Predicted:** all five: none, and the body intact.

**R3. Resume path, h2.**
- **Protocol:** h2 over TLS.
- **Setup:** POST N, and POST -1. Pause three times, once on the very first call.
- **Watch:** content-length; END_STREAM on the last DATA; the body.
- **Predicted:** all five: content-length only with N, END_STREAM on the last DATA, the body intact.

**R4. The pause mask.**
- **Protocol:** h1 over TCP.
- **Setup:** pause both callbacks. Resume with `CURLPAUSE_RECV`, then with `CONT`.
- **Watch:** the write callback and the upload after each call.
- **Predicted:** all five:
  - after `CURLPAUSE_RECV`: no write callback, and the upload goes on;
  - after `CONT`: write callbacks inside pause.

**R5. The first read.**
- **Protocol:** h1 over TCP.
- **Setup:** CL 1000 and `Expect:`. Log the read callback's first call against the bytes the server has received.
- **Watch:** whether the head reached the server before the first read.
- **Predicted:** after the head / after the head / during DO, so the head goes out with the first read / the same as 8.7.1 / the same as 8.7.1.

**R6. The Expect matrix.**
- **Protocol:** h1 over TCP.
- **Setup:** PUT 10, PUT -1, POST 10, POST -1, POST 1048576 and POST 1048577; then each with `Expect:`; then over h2; then HTTP/1.0 with -1.
- **Watch:** the Expect header; the result.
- **Predicted:**
  - **PUT 10:** Expect / none / none / none / none.
  - **PUT -1, POST -1, POST 1048577:** Expect on all five.
  - **POST 10, POST 1048576:** none on all five.
  - **With `Expect:`, and over h2:** none on all five.
  - **HTTP/1.0 with -1:** 25 on all five.

**R7. The Expect timeout.**
- **Protocol:** h1 over TCP.
- **Setup:** the server never sends a 100. Default timeout, then `EXPECT_100_TIMEOUT_MS` 200.
- **Watch:** the delay to the first read.
- **Predicted:** all five: about 1000 ms, then about 200 ms.

**R8. An early 417.**
- **Protocol:** h1 over TCP.
- **Setup:** POST -1; the server answers 417 at once.
- **Watch:** the requests the server sees; any read before the second request; any seek.
- **Predicted:** all five: two requests, the second without Expect, no read before it, no seek. With `MAXREDIRS` 0: 47.

**R9. A late 417.**
- **Protocol:** h1 over TCP.
- **Setup:** after the timeout, with body bytes sent, and a SEEKFUNCTION that logs.
- **Watch:** whether the seek is called; the result without a SEEKFUNCTION.
- **Predicted:**
  - **Seek called:** no / yes / yes / yes / yes.
  - **Without one:** the body resent from mid-stream (unsure) / 65 / unsure / 65 / 65.

**R10. An early 413 while the read is paused.**
- **Protocol:** h1 over TCP, keep-alive and close variants; then h2.
- **Setup:** the producer never resumes.
- **Watch:** whether `CURLMSG_DONE` comes within 3 s without an unpause.
- **Predicted:** **no** / **no** / **no** / yes / yes. Unsure on all five. h2 is unsure on the first three.

**R11. A 200 before the 100.**
- **Protocol:** h1 over TCP.
- **Setup:** POST -1, keep-alive.
- **Watch:** whether the read callback is ever called.
- **Predicted:** no / no / no / yes, after about 1 s / yes. Unsure.

**R12. A short body.**
- **Protocol:** h1, then h2.
- **Setup:** CL 1000; the callback gives 500 bytes, then 0.
- **Watch:** the result.
- **Predicted:**
  - **h1:** a stall until the server or `TIMEOUT` (28) / the same / **26** / 26 / 26.
  - **h2:** an early END_STREAM, outcome unsure / the same / 26 / 26 / 26.

**R13. Buffer size per call.**
- **Protocol:** h1 and h2.
- **Setup:** log `nitems` for CL 300000, for chunked, for h2, and with `UPLOAD_BUFFERSIZE` 16384.
- **Watch:** each call's size.
- **Predicted:**
  - **Plain:** 65536 every time, even at the tail / the same / first call 65536 minus the head, last call the bytes owed / the same as 8.7.1 / the same as 8.7.1.
  - **Chunked:** 65524 / 65524 / from 1012 to 65524 / the same / the same.
  - **At 16384:** 16384 or 16372 / the same / at most 16384 / the same / the same.

**R14. An overrun.**
- **Protocol:** h1 over TCP.
- **Setup:** CL 1000; the callback fills 1500 bytes of the offered buffer.
- **Watch:** the bytes on the wire; the result.
- **Predicted:** 1500 bytes sent / 1500 bytes sent / only 1000 offered, so it cannot overrun / the same / the same.

**R15. Low speed while send is paused.**
- **Protocol:** h1 over TCP.
- **Setup:** `LOW_SPEED_LIMIT` 1 and `LOW_SPEED_TIME` 2. The read callback pauses and the producer stays silent for 5 s.
- **Watch:** the result.
- **Predicted:** **28 at about 2 s** / 28 / 28 / no error / no error (#19653).

**R16. A dead reused connection under 1 s.**
- **Protocol:** h1 over TCP.
- **Setup:** the server sends FIN 100 ms after each response. The next POST, CL 1000 with no Expect and no SEEKFUNCTION, starts 300 ms later.
- **Watch:** the result; any seek.
- **Predicted:**
  - **No SEEKFUNCTION:** OK, on a new connection / OK / OK / OK / **65**.
  - **With a SEEKFUNCTION, 8.23.0:** one seek, then OK.
  - **Chunked, 8.23.0:** OK, with no seek.

**R17. A reset mid-body on a reused connection.**
- **Protocol:** h1 over TCP.
- **Setup:** the connection passed the check, then the server sends RST after the head and some body. No SEEKFUNCTION.
- **Watch:** the result.
- **Predicted:** 56 / 65 / **unsure: may go on without a rewind, giving 26 or a truncated chunked body** / 65 / 65.
- **Run on the Mac too.**

**R18. PREREQFUNCTION calls.**
- **Protocol:** h1 over TCP.
- **Setup:** count calls during R8, R16 and R17.
- **Watch:** the number of calls, and their order against the seek.
- **Predicted:** all five: one per attempt, after any seek.

**R19. h2 `REFUSED_STREAM` after DATA.**
- **Protocol:** h2 over TLS.
- **Setup:** no SEEKFUNCTION.
- **Watch:** the result.
- **Predicted:** 56 / 65 / unsure / 65 / 65.

**R20. h2 `HTTP_1_1_REQUIRED` after DATA.**
- **Protocol:** h2 over TLS, on a fresh connection.
- **Setup:** none beyond the reset.
- **Watch:** whether the request is redone over h1, any seek, where the body starts.
- **Predicted:** all five: redone over h1 with no seek, and the body starts mid-stream. Unsure.

**R21. A user `Transfer-Encoding: chunked`.**
- **Protocol:** h1, then h2 over TLS.
- **Setup:** POST N with the header set by the user.
- **Watch:** where the body stops on h1; the DATA frames on h2.
- **Predicted:**
  - **h1:** reads until 0 / until 0 / **stops at N** (#13229) / until 0 / until 0.
  - **h2:** plain bytes / plain / chunk framing inside DATA (unsure) / plain / plain.

**R22. An empty body.**
- **Protocol:** h1 over TCP.
- **Setup:** POST size 0, and PUT size 0.
- **Watch:** read callback calls; the header sent.
- **Predicted:** all five: never called, and `Content-Length: 0`.

**R23. Paused upload, finished download, closed connection.**
- **Protocol:** h1 over TCP.
- **Setup:** the server sends a full response and closes while the read is paused.
- **Watch:** whether `CURLMSG_DONE` comes without an unpause.
- **Predicted:** unsure / unsure / **no** (#13260) / yes / yes.

### Chez custom ports

These do not depend on libcurl. They run on Chez 10.4.0; its port code is identical to 10.4.1's.

**C1. What `read!` is handed.**
- **Setup:** a `read!` that logs `count`, `start`, `(bytevector-length bv)` and whether `bv` is the same object each time. Drive it with `get-u8`, `lookahead-u8`, `get-bytevector-some`, `get-bytevector-some!` with 1000, `get-bytevector-n` with 10 and with 20000, and `get-bytevector-all`.
- **Predicted:**
  - **The port buffer:** count 128, start 0, on the same bytevector.
  - **`get-bytevector-some`:** one call, count `(file-buffer-size)`. That should be 8192 on glibc and 4096 on macOS (unsure).
  - **`get-bytevector-n` 10:** calls with the counts left (10, 9, …).
- **Also print:** `(file-buffer-size)`.

**C2. EOF is not sticky.**
- **Setup:** a `read!` that returns 0, then 3 bytes, then 0.
- **Watch:** the number of `read!` calls.
- **Predicted:** `read!` is called again after a 0. The exact pattern for each operation is in section 9.

**C3. A bad result.**
- **Setup:** `read!` returns count+1, then -1, then 1.0, then `'x`.
- **Predicted:** each raises `&assertion` with "invalid result", and the port stays usable.

**C4. When `write!` is called.**
- **Setup:** log `write!` calls.
- **Predicted:**
  - 127 `put-u8` make no call, and the 128th makes one of 128 bytes;
  - `put-bytevector` of 256 bytes passes the caller's own bytevector;
  - flushing an empty buffer makes no call;
  - a `write!` that returns 0 is called again at once.

**C5. A raising `write!` duplicates bytes.**
- **Setup:** put 50 bytes, then 300 bytes with a `write!` that raises on the 300. Then flush with one that succeeds.
- **Predicted:** the 50 bytes arrive twice. A `close-port` after a raising flush never calls `close`.

**C6. No close at GC or exit.**
- **Setup:** custom ports dropped and collected.
- **Predicted:** `close` and `write!` are never called.

**C7. `close-port` from another thread during `read!`.**
- **Setup:** one thread's `read!` sleep-polls; another thread closes the port.
- **Predicted:**
  - `close` runs while `read!` is running;
  - a later inline `get-u8` returns bytes from the closed port;
  - `get-bytevector-some` raises.

**C8. Interrupt state inside `read!`.**
- **Setup:** inside `read!`, `(let ([n (disable-interrupts)]) (enable-interrupts) n)`. Call `get-u8` plainly, then inside `critical-section`.
- **Predicted:** 1, then 2. A collection another thread asks for finishes while `read!` sleeps.

**C9. A raise inside `get-bytevector-n`.**
- **Setup:** a `read!` that gives 3 bytes, then raises, under `get-bytevector-n` 10.
- **Predicted:** the 3 bytes are lost.
- **Contrast:** under `get-bytevector-some!`, nothing is lost.

**C10. A timer expiring as `read!` returns (unsure).**
- **Setup:** sweep a `set-timer` handler that escapes across the moment `read!` returns, under `get-bytevector-some` and under `get-bytevector-some!`.
- **Watch:** any loss of bytes `read!` returned.
- **Predicted:** a loss is possible only on the `get-bytevector-some` path.
