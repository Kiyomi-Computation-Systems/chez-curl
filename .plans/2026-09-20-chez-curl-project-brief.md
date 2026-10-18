# chez-curl: a libcurl-backed async HTTP client for Chez Scheme — project brief

Date: 2026-09-20
Status: accepted for M0 and M1. [ADR-0001 to ADR-0017](decisions/) record what was settled (from 2026-10-04). [The harness plan](2026-10-04-harness-plan.md) says what M0 copies from the siblings, and [the M1 plan](2026-10-18-m1-plan.md) how M1 builds §7. This brief is kept in step with them; where it and a record disagree, the record wins. ADR-0013 stays Proposed until spike E1 (§5)
Consumers: Chez applications that need to *make* HTTP requests; the first is ad-hoc scripting. `chez-http-server`'s black-box lane does not use it (ADR-0011)
Dependencies: libcurl ≥ 7.85.0, any TLS backend (ADR-0003); Chez ≥ 10.4.0, threaded (ADR-0001). No C shim: nothing is compiled (ADR-0001). **Not** chez-libuv, **not** chez-httparse — see §3.
Evidence behind this brief: measured on the maintainer's Mac 2026-09-20 — system libcurl 8.7.1, `Features: alt-svc AsynchDNS GSS-API HSTS HTTP2 HTTPS-proxy IPv6 Kerberos Largefile libz MultiSSL NTLM SPNEGO SSL threadsafe UnixSockets`; SDK headers include `curl.h multi.h easy.h urlapi.h header.h options.h`; `pkg-config --libs libcurl` → `-lcurl`; `(threaded?)` → `#t` on Chez 10.4.1. Plus chez-http-server's E5 spike series, run through chez-libuv's binding on macOS arm64 and cited in §5. The Linux development host (Guix Chez 10.4.0, Guix libcurl 8.20.0 with GnuTLS, no Node outside Guix) was measured on 2026-10-04; those numbers live in ADR-0001, ADR-0002, ADR-0005 and ADR-0006.

## 1. Goal

A client that reads like Drakma or Racket's `http-easy` at the top, sits on libcurl at the bottom,
and gives real concurrency without asking the caller to think about an event loop.

```
        application: (get s "https://example.com/x")  ·  (http-parallel s reqs)
                               │
        ┌──────────────────────┴───────────────────────┐
        │  (http-client ...)   THE HIGH LEVEL          │
        │  session, request/response records,          │
        │  blocking calls, redirect + retry policy,    │
        │  the thread sugar                            │
        ├──────────────────────────────────────────────┤
        │  (curl ...)          THE LOW LEVEL           │
        │  easy/multi handles, setopt/getinfo,         │
        │  the engine thread, completion callbacks     │
        ├──────────────────────────────────────────────┤
        │  foreign-procedure   varargs setopt/getinfo, │
        │  (ADR-0001, no C)    options API, ftypes     │
        └──────────────────────┬───────────────────────┘
                          libcurl ≥ 7.85
                     (TLS, HTTP/2, pooling, DNS)
```

Two layers, one repository, with the seam drawn hard enough that `(curl ...)` could
split into its own repo later if it earns one. ADR-0007 settled D1 this way, and `make
check-seam` enforces the seam by reading every library's imports.

## 2. What is settled

These are the answers given before work started. ADR-0012 records items 1–3 and the
caller-code rule of §5, ADR-0002 records item 5, and ADR-0001 reversed item 6.

1. **A standalone engine thread, no chez-libuv.** `curl_multi_poll` runs on one dedicated
   Chez thread that owns the multi handle. Completions marshal back to callers through Chez
   condition variables. This needs no `uv_poll` bindings (chez-libuv does not have them),
   imposes no loop-affinity rules from another library, and leaves a chez-libuv bridge as a
   later, optional library if the client ever wants to live inside the server's loop
   (ADR-0012).
2. **Every libcurl handle is owned by the engine thread.** Callers never touch an easy or
   multi handle; they submit a request record to a queue and get a completion. libcurl is
   thread-safe only under exactly this discipline. The invariant is the mirror of
   chez-libuv's ADR-0019, and it is enforced the same way: an operational verb called off
   the engine thread raises a named condition, `&curl-wrong-thread`, rather than corrupting
   a handle (ADR-0012).
3. **The high level blocks; concurrency does not cost threads.** `(get s url)` blocks the
   calling Chez thread on a condition variable, exactly like `http-easy`. But because the
   engine multiplexes, *N concurrent requests need one engine thread, not N caller threads* —
   `http-parallel` submits N requests and blocks one caller. Caller threads exist to let the
   caller interleave their own work, not to buy I/O concurrency. This is the single most
   important thing to get into the README (ADR-0012).
4. **Thread sugar is part of v1** (§6.3): a session with guaranteed cleanup, a bounded
   request group with guaranteed join, and a streaming-response form that closes what it opens.
5. **TLS by whatever the linked libcurl provides.** Not OpenSSL specifically. At init we
   require `CURL_VERSION_SSL` and refuse to load without it (`no-ssl`, ADR-0002); we read the
   backend from `curl_version_info` and expose it. Apple's libcurl on the Mac reports
   `MultiSSL`, so `curl_global_sslset` can select among compiled-in backends when a caller
   cares; the Guix libcurl on the Linux host is GnuTLS only.
6. **No C shim** — reversed by ADR-0001. This item first chose a shim like chez-libuv's,
   chiefly for the variadic problem. Chez 10's `(__varargs_after n)` solves that, and §4
   says how the shim's other jobs are done without compiling anything.
7. **v1 carries the full feature surface:** streaming bodies both directions, HTTP/2,
   cookies, auth, proxies, and `multipart/form-data`. This is a wide v1 — see §9.

## 3. Why this is its own repository, and what it deliberately does not reuse

- It is a client. `chez-http-server` is an origin server, its thesis is a pure connection
  state machine, and the two share no code — only a corpus of HTTP facts. Neither depends on
  the other's tests (ADR-0011).
- **It does not use chez-httparse.** libcurl parses the response, and since 7.83 exposes it
  structurally through `curl_easy_header` (`header.h` is present in the SDK; on by default
  from 7.84, and probed at load by ADR-0003). Writing a HEADERFUNCTION and re-parsing with
  our own parser would add a second source of truth for no gain. Surprising given the
  family, worth saying out loud, and it is the honest cost of choosing libcurl over a
  libuv-based client.
- **It does not use uriparse either** (ADR-0008, settling D2). libcurl ships `curl_url`
  in `urlapi.h`. Using it means what we validate and what curl actually fetches can never
  disagree; using uriparse would mean a second URL grammar in the process and a real class of
  bug where we accept a URL curl rejects, or the two disagree about the host. `curl_url`
  parses, checks and resolves every URL, and the transfer takes the parsed handle itself. A
  caller who wants uriparse's strict RFC 3986 verdict runs it first.
- It is **not** a scraping framework, a REST-client generator, or a JSON library. The
  response carries bytes and headers; decoding is the caller's.
- It is **not** a libcurl completion. We bind the HTTP/HTTPS surface, and every transfer is
  pinned to http and https (ADR-0003). FTP, SMTP, LDAP and the rest of curl's protocol list
  stay unbound. Options we do not wrap are reachable through a typed escape hatch,
  `(curl unsupported)`, which refuses pointers, callbacks and the options chez-curl owns
  (ADR-0009).

## 4. No C shim (ADR-0001)

This section first argued for a shim with three jobs, all of them chez-libuv's shim's jobs.
Each is now done without compiling anything:

1. **The variadic problem.** `curl_easy_setopt` and `curl_easy_getinfo` are variadic. Chez
   10's `(__varargs_after n)` binds them directly, once per value type, so no typed C
   wrappers are needed.
2. **The constant table.** The loaded libcurl names its own options: `curl_easy_option_by_name`
   gives each `CURLOPT_*` id and its value type. The remaining constants (`CURLE_*`,
   `CURLINFO_*`, `CURLM_*`, `CURL_HTTP_VERSION_*` and the rest) are Scheme definitions,
   checked against libcurl's headers by a C program compiled at test time. The compiler is a
   test oracle, never an install dependency.
3. **Struct layout.** `CURLMsg`, `struct curl_header` and the other structs Scheme reads are
   `define-ftype`s, checked by the same program with `sizeof` and `offsetof`. `curl_waitfd`
   is not needed: `curl_multi_wakeup` wakes the poll without an extra descriptor.

Callbacks never needed the shim. Chez's `foreign-callable` gives us a function pointer
directly, which is how WRITEFUNCTION, READFUNCTION, SEEKFUNCTION and XFERINFOFUNCTION get
bound. What they need instead is §5.

## 5. The one hard design question, and it is already half-answered

**Does the engine thread blocking in `curl_multi_poll` freeze GC for every other Chez thread?**

This is the same question chez-libuv answered for `uv_run` (its ADR-0019), on the strength
of chez-http-server's E5 spike series, all run on macOS arm64. The answer was expensive to
find and is worth inheriting rather than rediscovering:

- Before the fix, a loop thread blocked in `uv_run` held the collect interlock. Behind a
  300 ms poll, a worker thread's 28 ms of allocation took **10,272 ms** (spike E5c).
- Declaring the blocking call `__collect_safe` removed it entirely: 23–35 ms, at baseline,
  whatever the loop thread is doing (spike E5g, against chez-libuv v0.6.0).
- The cost is about 60 ns per callback conversion (spike E5f).

So: `curl_multi_poll` **must** be `(foreign-procedure __collect_safe "curl_multi_poll" …)`,
and so must every callback libcurl can invoke from inside a `__collect_safe` call; Chez's
user guide makes that the rule. In the multi interface the transfer callbacks fire inside
`curl_multi_perform`, which curl documents as non-blocking, not inside the poll. ADR-0013
records the rule, Proposed until M3's spike (E1) reproduces the E5c/E5g measurement against
curl rather than libuv, on Linux, and records the numbers, because inheriting a conclusion is
not the same as having measured it.

The second half of the question is new: **libcurl's write callback runs on the engine thread.**
If a caller's body consumer is a Scheme procedure, caller code executes on the I/O thread —
a hazard with no analogue in the server. v1's answer is that the write callback only copies
into a bounded buffer and signals; consumers drain from their own thread. Backpressure uses
`CURL_WRITEFUNC_PAUSE` with `curl_easy_pause` to resume (M6); the resume is a message to the
engine, which calls `curl_easy_pause` itself (ADR-0012).

## 6. The two layers

### 6.1 `(curl ...)` — the low level

Mirrors libcurl. Request records in, completion callbacks out, no policy. An easy handle's
lifetime is the engine's business; the caller sees an opaque request token that can be
cancelled. This layer knows nothing about sessions, redirects or retries. `(curl)` is its
public library; `(curl private ...)` holds the internals and `(curl unsupported)` the
escape hatch (ADR-0010).

### 6.2 `(http-client ...)` — the high level

The Drakma / `http-easy` surface. A `session` owns the engine, a connection pool and default
options; `(get s url)`, `(post s url #:json …)`, `(request s method url …)` block and return a
`response` record (status, headers, body, final URL, timing). Redirect policy, retry with
backoff, auth and cookie jars live here, because they are policy and the low level has none.
`(http-client)` is its public library, and it reaches the low level only through `(curl)`
(ADR-0007, ADR-0010).

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
and **no test touches the public internet.** On the Linux host the development container has
no network, so the environment enforces that (ADR-0006).

- A local origin server able to produce, on demand: chunked bodies, close-delimited bodies,
  every redirect status, slow drips, oversized headers, HTTP/2, and deliberate protocol
  errors. Node can serve this in one file: `tests/origin.mjs`, standard library only,
  Node ≥ 20 (ADR-0005). The Mac has Node 20.10.0; on the Linux host Node comes from the
  development container.
- A generated test CA plus a leaf certificate, so TLS is exercised for real — including the
  failure lane: expired, wrong-host, untrusted, and a verification-off escape hatch. The
  material is generated per run with the `openssl` command line, so nothing in the
  repository can expire (ADR-0005).
- With no client yet, a byte probe with no HTTP code checks the instrument, and `openssl`
  checks the certificates (ADR-0005, amended).
- A drift guard on the linked libcurl: version, feature bits and TLS backend asserted, so an
  OS or package update that swaps the library or its backend fails a test instead of a user.
  Discovery reports exactly what it loaded (ADR-0002), and `make test` fails on any libcurl
  with no recorded row (ADR-0017).

## 8. Milestones

- **M0 — skeleton, discovery, and the feature gate.** The pinned development container
  (ADR-0006); a Makefile with `help`, `build`, `dev`, `test` and `clean`; finding and loading
  libcurl (ADR-0002) with the floor and API checks (ADR-0003); the header-checked constants
  and struct layouts (ADR-0001); `curl_global_init`, once; `curl_version_info` read into a
  Scheme record; the named refusals, `no-ssl` among them; and the harness copied from the
  siblings, memory gate included (ADR-0014, ADR-0015, the harness plan).
- **M1 — the instrument, with no client.** §7 in full: local server, test CA, drift guard.
- **M2 — one blocking request, plaintext and TLS.** `curl_easy_perform` on the calling thread —
  deliberately *not* the multi interface. Proves the FFI, the variadic setopt bindings,
  `curl_easy_header`, getinfo and TLS in one milestone, with nothing async to confuse a
  failure. Its call and callbacks are `__collect_safe` (ADR-0013).
- **M3 — the engine.** The multi handle, the dedicated thread, `curl_multi_poll` under
  `__collect_safe`, the submission queue, completion marshalling, cancellation, and the
  affinity refusal (ADR-0012). **Carries spike E1** (§5, ADR-0013). The hard milestone;
  everything after it is surface.
- **M4 — request and response records, and the low-level async API.** Completion callbacks,
  run on a caller's thread and never the engine's (ADR-0012), timeouts, error taxonomy mapping
  `CURLE_*` to conditions.
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
   asserts thread identity inside a body consumer, not just a comment. ADR-0012 makes that
   test part of the design.
3. **TLS backend variance.** Backend-agnostic means the test lane must pass on at least two
   backends or the claim is untested. Apple's libcurl on the Mac is SecureTransport-backed
   with LibreSSL also compiled in (`MultiSSL`); SecureTransport uses the keychain while
   OpenSSL- and GnuTLS-backed builds want a CA bundle path, and that difference reaches the
   public API the moment someone passes a custom CA. Upstream curl marks Secure Transport
   deprecated from 8.15.0, so that split is Apple's alone. Linux CI can still cover two
   backends: the runner's OpenSSL-backed libcurl by discovery, and Debian's GnuTLS build
   through `CHEZ_CURL_LIBCURL` (ADR-0002).
4. **Two sources of URL truth** — retired: D2 went to `curl_url` (ADR-0008), so there is one.
5. **libcurl version floor.** The floor is 7.85.0, for `CURLOPT_PROTOCOLS_STR` (ADR-0003).
   Below it: `curl_multi_poll` 7.66, `curl_multi_wakeup` 7.68, `curl_easy_option_by_name`
   7.73, `curl_easy_header` 7.83 (on by default from 7.84). Anything older fails at load with
   `below-floor` rather than a mysterious symbol error, and a build that switches off an API
   fails with `missing-api`.

## 10. Decisions

D1–D5 were this brief's open questions. D6–D11 were raised on 2026-10-04, while checking the
brief against the Linux development host. All are settled.

| Decision | Record | Outcome |
|---|---|---|
| D1 — one repository or two | ADR-0007 | One repository, two libraries; `make check-seam` enforces the seam |
| D2 — `curl_url` or uriparse | ADR-0008 | `curl_url` only; the transfer takes the parsed handle |
| D3 — the escape hatch | ADR-0009 | A typed hatch, `(curl unsupported)`, in the low level only |
| D4 — the names | ADR-0010 | `chez-curl`; `(curl)` and `(http-client)` |
| D5 — chez-http-server's black-box lane | ADR-0011 | No dependency in either direction |
| D6 — shim or no shim | ADR-0001 | No shim; Chez ≥ 10.4.0, threaded |
| D7 — finding libcurl | ADR-0002 | `CHEZ_CURL_LIBCURL`, else one candidate list per world |
| D8 — the test server's runtime | ADR-0005 | One Node file, standard library only |
| D9 — Windows | ADR-0004 | Not supported |
| D10 — the libcurl floor | ADR-0003 | 7.85.0, with the options and header APIs probed at load |
| D11 — the development environment | ADR-0006 | A pinned Guix container with no network |

§2's settled answers and §5's rules are recorded too: ADR-0012 (the engine owns every
transfer handle) and ADR-0013 (`__collect_safe`, Proposed until spike E1). The harness plan
adds ADR-0014 (Valgrind is the memory gate, and must be seen to fail) and ADR-0015 (SRFI-64
from vendored chez-srfi pinned in `Akku.lock`, with the suite rules as checks).
