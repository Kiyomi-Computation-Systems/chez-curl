# chez-curl: a libcurl-backed async HTTP client for Chez Scheme — project brief

Date: 2026-09-20
Status: draft — nothing accepted yet; the open decisions at the end need sign-off before M0
Consumers: Chez applications that need to *make* HTTP requests; the first is ad-hoc scripting and the black-box lane of `chez-http-server`
Dependencies: libcurl ≥ 7.84 (any TLS backend), a C shim of our own, Chez 10.4.1 threaded. **Not** chez-libuv, **not** chez-httparse — see §3.
Evidence behind this brief: measured on this machine 2026-09-20 — system libcurl 8.7.1, `Features: alt-svc AsynchDNS GSS-API HSTS HTTP2 HTTPS-proxy IPv6 Kerberos Largefile libz MultiSSL NTLM SPNEGO SSL threadsafe UnixSockets`; SDK headers include `curl.h multi.h easy.h urlapi.h header.h options.h`; `pkg-config --libs libcurl` → `-lcurl`; `(threaded?)` → `#t` on Chez 10.4.1. Plus the chez-libuv E5 spike series, cited in §5.

## 1. Goal

A client that reads like Drakma or Racket's `http-easy` at the top, sits on libcurl at the bottom,
and gives real concurrency without asking the caller to think about an event loop.

```
        application: (get s "https://example.com/x")  ·  (http-parallel s reqs)
                               │
        ┌──────────────────────┴───────────────────────┐
        │  (http client ...)   THE HIGH LEVEL          │
        │  session, request/response records,          │
        │  blocking calls, redirect + retry policy,    │
        │  the thread sugar                            │
        ├──────────────────────────────────────────────┤
        │  (curl ...)          THE LOW LEVEL           │
        │  easy/multi handles, setopt/getinfo,         │
        │  the engine thread, completion callbacks     │
        ├──────────────────────────────────────────────┤
        │  libcurl-shim.c      non-variadic wrappers,  │
        │                      constant + offset table │
        └──────────────────────┬───────────────────────┘
                          libcurl ≥ 7.84
                     (TLS, HTTP/2, pooling, DNS)
```

Two layers, one repository, with the seam drawn hard enough that `(curl ...)` could
split into its own repo later if it earns one (open decision D1).

## 2. What is settled

These are the answers already given; each becomes a decision record at M0.

1. **A standalone engine thread, no chez-libuv.** `curl_multi_poll` runs on one dedicated
   Chez thread that owns the multi handle. Completions marshal back to callers through Chez
   condition variables. This needs no `uv_poll` bindings (chez-libuv does not have them),
   imposes no loop-affinity rules from another library, and leaves a chez-libuv bridge as a
   later, optional library if the client ever wants to live inside the server's loop.
2. **Every libcurl handle is owned by the engine thread.** Callers never touch an easy or
   multi handle; they submit a request record to a queue and get a completion. libcurl is
   thread-safe only under exactly this discipline. The invariant is the mirror of
   chez-libuv's ADR-0019, and it is enforced the same way: an operational verb called off
   the engine thread raises a named condition rather than corrupting a handle.
3. **The high level blocks; concurrency does not cost threads.** `(get s url)` blocks the
   calling Chez thread on a condition variable, exactly like `http-easy`. But because the
   engine multiplexes, *N concurrent requests need one engine thread, not N caller threads* —
   `http-parallel` submits N requests and blocks one caller. Caller threads exist to let the
   caller interleave their own work, not to buy I/O concurrency. This is the single most
   important thing to get into the README.
4. **Thread sugar is part of v1** (§6.3): a session with guaranteed cleanup, a bounded
   request group with guaranteed join, and a streaming-response form that closes what it opens.
5. **TLS by whatever the linked libcurl provides.** Not OpenSSL specifically. At init we
   require `CURL_VERSION_SSL` and refuse to load without it; we read the backend from
   `curl_version_info` and expose it. The system libcurl here reports `MultiSSL`, so
   `curl_global_sslset` can select among compiled-in backends when a caller cares.
6. **A C shim, following chez-libuv's.** Its `src/libuv-shim.c` is 327 lines and exists to
   hand constants and struct layouts across; ours does the same job plus the variadic
   problem (§4).
7. **v1 carries the full feature surface:** streaming bodies both directions, HTTP/2,
   cookies, auth, proxies, and `multipart/form-data`. This is a wide v1 — see §9.

## 3. Why this is its own repository, and what it deliberately does not reuse

- It is a client. `chez-http-server` is an origin server, its thesis is a pure connection
  state machine, and the two share no code — only a corpus of HTTP facts.
- **It does not use chez-httparse.** libcurl parses the response, and since 7.83 exposes it
  structurally through `curl_easy_header` (`header.h` is present in the SDK). Writing a
  HEADERFUNCTION and re-parsing with our own parser would add a second source of truth for
  no gain. Surprising given the family, worth saying out loud, and it is the honest cost of
  choosing libcurl over a libuv-based client.
- **It probably does not use uriparse either** (open decision D2). libcurl ships `curl_url`
  in `urlapi.h`. Using it means what we validate and what curl actually fetches can never
  disagree; using uriparse means a second URL grammar in the process and a real class of bug
  where we accept a URL curl rejects, or the two disagree about the host. Recommendation:
  `curl_url` on the request path, with uriparse available as an opt-in strict RFC 3986
  validator for callers who want that verdict.
- It is **not** a scraping framework, a REST-client generator, or a JSON library. The
  response carries bytes and headers; decoding is the caller's.
- It is **not** a libcurl completion. We bind the HTTP/HTTPS surface. FTP, SMTP, LDAP and the
  rest of curl's protocol list stay unbound, with an escape hatch (D3) for raw setopt.

## 4. The C shim, and why there is one

Three jobs, all of them chez-libuv's shim's jobs:

1. **The variadic problem.** `curl_easy_setopt` and `curl_easy_getinfo` are variadic, which
   Chez's `foreign-procedure` cannot express. The shim exposes typed wrappers:
   `setopt_long`, `setopt_str`, `setopt_ptr`, `setopt_off_t`, `setopt_blob`, and the
   `getinfo_*` mirror. This is what every libcurl binding in every language does.
2. **The constant table.** `CURLOPT_*`, `CURLINFO_*`, `CURLE_*`, `CURLM_*`, `CURL_HTTP_VERSION_*`
   and the rest, looked up by name and compiler-derived, exactly like
   `chez_uv_constant_table` in `libuv-shim.c`. Values are never hard-coded in Scheme.
3. **Struct layout.** `CURLMsg` (what `curl_multi_info_read` returns) and `curl_waitfd`
   need field offsets, not guessed ones.

Callbacks do **not** need the shim. Chez's `foreign-callable` gives us a function pointer
directly, which is how WRITEFUNCTION, READFUNCTION, SEEKFUNCTION and XFERINFOFUNCTION get
bound. What they need instead is §5.

## 5. The one hard design question, and it is already half-answered

**Does the engine thread blocking in `curl_multi_poll` freeze GC for every other Chez thread?**

This is the same question chez-libuv answered for `uv_run`, and the answer there was
expensive to find and is worth inheriting rather than rediscovering:

- Before the fix, a loop thread blocked in `uv_run` held the collect interlock, and a worker
  thread's ~24 ms of allocation took **10.2 seconds** (spike E5c).
- Declaring the blocking call `__collect_safe` removed it entirely: 23–33 ms, at baseline,
  whatever the loop thread is doing (spike E5g, at the v0.6.0 pin).
- The cost is ~60–65 ns per callback conversion (spike E5f).

So: `curl_multi_poll` **must** be `(foreign-procedure __collect_safe "curl_multi_poll" …)`,
and so must every callback trampoline that libcurl invokes from the engine thread. M3 carries
a spike (E1) that reproduces the E5c/E5g measurement against curl rather than libuv and
records the numbers, because inheriting a conclusion is not the same as having measured it.

The second half of the question is new: **libcurl's write callback runs on the engine thread.**
If a caller's body consumer is a Scheme procedure, caller code executes on the I/O thread —
a hazard with no analogue in the server. v1's answer is that the write callback only copies
into a bounded buffer and signals; consumers drain from their own thread. Backpressure uses
`CURL_WRITEFUNC_PAUSE` with `curl_easy_pause` to resume (M6).

## 6. The two layers

### 6.1 `(curl ...)` — the low level

Mirrors libcurl. Request records in, completion callbacks out, no policy. An easy handle's
lifetime is the engine's business; the caller sees an opaque request token that can be
cancelled. This layer knows nothing about sessions, redirects or retries.

### 6.2 `(http client ...)` — the high level

The Drakma / `http-easy` surface. A `session` owns the engine, a connection pool and default
options; `(get s url)`, `(post s url #:json …)`, `(request s method url …)` block and return a
`response` record (status, headers, body, final URL, timing). Redirect policy, retry with
backoff, auth and cookie jars live here, because they are policy and the low level has none.

### 6.3 The thread sugar

```scheme
;; the session owns the engine thread and the pool; cleanup is guaranteed
(call-with-http-session opts (lambda (s) ...))

;; a bounded group: every request joined before it returns, on the happy path
;; and on an exception. No thread is spawned per request — the engine multiplexes.
(call-with-request-group s
  (lambda (go)
    (let ((a (go req-a)) (b (go req-b)))
      (values (await a) (await b)))))

;; the common case, one line
(http-parallel s (list req ...))        ; -> (list response ...)

;; streaming, closing what it opens
(call-with-response-port s req (lambda (port) ...))
```

`call-with-request-group` is the piece worth designing carefully: it is a nursery, and its
contract is that it does not return while a submitted request is still live, including when
the body raises.

## 7. The test instrument comes first

Same discipline as `chez-http-server` M1: the instrument lands before the thing it measures,
and **no test touches the public internet.**

- A local origin server able to produce, on demand: chunked bodies, close-delimited bodies,
  every redirect status, slow drips, oversized headers, HTTP/2, and deliberate protocol
  errors. Node v20.10.0 is on this machine and can serve this in one file.
- A generated test CA plus a leaf certificate, so TLS is exercised for real — including the
  failure lane: expired, wrong-host, untrusted, and a verification-off escape hatch.
- A drift guard on the linked libcurl: version, feature bits and TLS backend asserted, so a
  Homebrew upgrade or an OS update that swaps the backend fails a test instead of a user.

## 8. Milestones

- **M0 — skeleton, shim, and the feature gate.** Makefile with `build`/`dev`/`test`/`clean`,
  the shim compiling, the constant table, `curl_global_init`, `curl_version_info` read into a
  Scheme record, and a hard refusal to load without `CURL_VERSION_SSL`.
- **M1 — the instrument, with no client.** §7 in full: local server, test CA, drift guard.
- **M2 — one blocking request, plaintext and TLS.** `curl_easy_perform` on the calling thread —
  deliberately *not* the multi interface. Proves the FFI, the setopt wrappers,
  `curl_easy_header`, getinfo and TLS in one milestone, with nothing async to confuse a failure.
- **M3 — the engine.** The multi handle, the dedicated thread, `curl_multi_poll` under
  `__collect_safe`, the submission queue, completion marshalling, cancellation, and the
  affinity refusal. **Carries spike E1** (§5). The hard milestone; everything after it is surface.
- **M4 — request and response records, and the low-level async API.** Completion callbacks,
  timeouts, error taxonomy mapping `CURLE_*` to conditions.
- **M5 — the high level.** Sessions, the verb API, redirect and retry policy, and the §6.3
  thread sugar.
- **M6 — streaming bodies and backpressure.** Both directions, `CURL_WRITEFUNC_PAUSE` /
  `curl_easy_pause`, and the rule that caller code never runs on the engine thread.
- **M7 — HTTP/2, cookies, auth, proxies.** Mostly setopt surface once M3 exists; the work is
  the test lane, not the binding.
- **M8 — multipart/form-data, docs, release.** `curl_mime`, README.org, API docs, v0.1.0 tag.

## 9. Standing risks

1. **v1 is wide.** Streaming, HTTP/2, cookies, auth, proxies and multipart is most of what
   Drakma and `http-easy` offer, chosen all at once. The sequencing above puts the engine at
   M3 so the feature surface is additive, but M6–M8 are each a real milestone and the honest
   expectation is that v1 is a long v1, not that these are free because libcurl has them.
2. **Caller code on the engine thread.** The worst bug this design can have, and it will be
   tempting every time a callback wants to hand a caller a byte. §5's rule needs a test that
   asserts thread identity inside a body consumer, not just a comment.
3. **TLS backend variance.** Backend-agnostic means the test lane must pass on at least two
   backends or the claim is untested. The system libcurl here is SecureTransport-backed with
   LibreSSL also compiled in (`MultiSSL`); SecureTransport uses the keychain while
   OpenSSL-backed builds want a CA bundle path, and that difference reaches the public API
   the moment someone passes a custom CA.
4. **Two sources of URL truth** if D2 goes the other way.
5. **libcurl version floor.** `curl_multi_poll` needs 7.68, `curl_easy_header` needs 7.83,
   `CURL_VERSION_THREADSAFE` needs 7.84. The floor is 7.84; anything older fails at init with
   a named refusal rather than a mysterious symbol error.

## 10. Open decisions, for sign-off before M0

- **D1 — one repository or two?** The house style is one repo per thesis (chez-libuv is
  "transport only, no policy"). That argues for `chez-curl` (bindings + engine) and
  `chez-http-easy` (policy + sugar) as separate repos. Recommendation: **one repo, two
  libraries, hard seam**, and split only if the low level acquires a consumer of its own.
- **D2 — `curl_url` or uriparse?** Recommendation: `curl_url`, for the no-divergence reason
  in §3, with uriparse opt-in.
- **D3 — the escape hatch.** Do we expose raw `setopt` for options we have not wrapped?
  Recommendation: yes, in `(curl ...)` only, documented as unsupported surface, never
  reachable from `(http client ...)`.
- **D4 — the name.** `chez-curl` for the repo, `(curl ...)` and `(http client ...)` for the
  libraries. Alternatives: `chez-http-client`, or `chez-http-easy` if the high level is the
  headline.
- **D5 — does chez-http-server's black-box lane depend on this?** It would be a good first
  consumer and a real test of both, but it couples two projects' schedules. Recommendation:
  no dependency before this reaches v0.1.0.
