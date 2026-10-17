# ADR-0013: Calls that can block are `__collect_safe`, and so is every callback they can invoke

- **Status:** Proposed. It binds as written until spike E1 (M3) records its measurements.
  It is then accepted, or amended to fit them. Amended 2026-10-16 with the attribute suite
  (M0 slice 4), and with what a binding may hand C from Chez's heap (M0 slice 5).
- **Date:** 2026-10-04
- **Corrected:** 2026-10-04. The E5 series is chez-http-server's, not chez-libuv's. Its
  figures are restated from that spike report, which ran on macOS only.
- **Scope:** chez-curl v1: every foreign procedure and foreign callable
- **Settles:** the brief's §5 rule, provisionally
- **Related:**
  - brief §5 and §8 (M2, M3 and spike E1);
  - chez-libuv ADR-0019, whose first decision this mirrors, and ADR-0002, which was held
    until its spike's evidence came in;
  - chez-http-server's `.plans/research/spike/spike-control-flow.md`, home of the E5 series;
  - [ADR-0001](0001-bind-libcurl-directly.md) (`memcpy` is a plain call);
  - [ADR-0012](0012-engine-thread-owns-every-handle.md) (the engine).

## Context

Chez's collector is stop-the-world. The user guide (CSUG 10.4.1 §4.3) says
`__collect_safe` "allows concurrent collection by deactivating the current thread … when
the foreign procedure is called". A thread blocked in a plain foreign call stays active,
so every other thread's collection waits for it.

chez-http-server's E5 spike series measured this through chez-libuv's binding, on macOS
arm64 with Chez 10.4.1. chez-libuv's ADR-0019 rests on these numbers:

| Spike | Setup | Result |
|---|---|---|
| E5c | a worker allocating beside a loop thread blocked in a plain `uv_run`, with a 300 ms timer | 10,272 ms, against a 28 ms baseline |
| E5g | E5c rerun against chez-libuv v0.6.0, where `uv_run` is `__collect_safe` | 23–35 ms |
| E5f | the cost of the declaration, 5 million callbacks per trial | "about 60 ns per callback" (plain ~180–190 ns, `__collect_safe` ~235–250 ns) |

The same guide gives two rules that bind here:

- **Callbacks inherit the declaration.** "If a foreign procedure with `__collect_safe` can
  invoke callables, then each callable should also be declared with `__collect_safe` so that
  the callable reactivates the thread."
- **Strings and bytevectors are unsafe in two kinds of call.** They are unsafe passed to a
  `__collect_safe` procedure, and unsafe passed to any procedure that re-enters Scheme
  through a callable before returning. Either way, a collection can move them.

Four things curl documents decide where each rule applies:

- `curl_multi_poll` "blocks until activity is detected".
- `curl_multi_perform` "performs transfers … in a non-blocking fashion".
- `curl_easy_perform` runs a whole transfer, callbacks included, inside one call.
- `CURLOPT_QUICK_EXIT` exists to skip "lengthy cleanups … [of] a resolver thread" after a
  DNS timeout. So by default, cleanup can wait.

ADR-0001's probe declared `curl_easy_perform` `__collect_safe` on Chez 10.4.0, and it
worked. No callbacks were set.

The brief requires its own measurement: "inheriting a conclusion is not the same as having
measured it". That is spike E1, carried by M3.

## Decision

Provisional until E1.

1. **A libcurl call that can block is a `__collect_safe` foreign procedure.** Known now:
   `curl_multi_poll` and `curl_easy_perform`. E1 classifies the rest, starting with the
   cleanup paths `CURLOPT_QUICK_EXIT` describes: `curl_multi_remove_handle` and
   `curl_easy_cleanup`.
2. **A callback is `__collect_safe` when libcurl can invoke it from inside a
   `__collect_safe` call** (CSUG). M2's transfer callbacks run inside `curl_easy_perform`,
   so they are.
3. **Calls that cannot block stay plain.** That covers setopt, getinfo, the `curl_url`
   family and `memcpy` (ADR-0001). It covers `curl_multi_perform` too, which curl documents
   as non-blocking, until E1 says otherwise. A callback fired only from plain calls stays
   plain.
4. **A call that can block, or can invoke a callback, never receives a Scheme object as an
   argument.** It gets handles, foreign memory and immediate values. For example,
   `curl_multi_poll`'s `numfds` and `curl_multi_perform`'s `running_handles` point to
   memory from `foreign-alloc`, freed afterwards.
5. **Spike E1 (M3) measures, against curl:**
   - a worker thread's allocation time while the engine blocks in `curl_multi_poll`, with
     the call declared plain and then `__collect_safe` (chez-http-server's E5c and E5g);
   - which libcurl calls block;
   - which call each callback fires from;
   - whether one callback may serve both a `__collect_safe` call and a plain one. CSUG does
     not say, and M2's and M3's paths may share callbacks.

   E1 runs on Linux, which the E5 series never did. Every claim is run twice. Its programs
   are committed beside its findings file, which decides whether this record is accepted
   or amended.

### Rejected

- **Every callback `__collect_safe`, as the brief worded it.** That pays ~60 ns per call
  where no `__collect_safe` call can invoke the callback. And CSUG does not say such a
  callback is safe when entered from a plain call, so E1 tests that first.
- **Accepting now on the E5 numbers.** The brief rules it out, and those numbers come from
  macOS only.
- **No `__collect_safe` at all.** E5c measured what that costs: 10,272 ms instead of 28 ms.

## Consequences

- **M2 starts with `curl_easy_perform` and its callbacks declared `__collect_safe`.**
- **The cost is small where the rule applies.** It is about 60 ns per callback conversion
  (E5f), against write chunks of up to 16 KiB (`CURL_MAX_WRITE_SIZE`, 16384).
- **Contradicting findings get raised, not worked around.** A finding during M2 or M3 that
  contradicts this record is raised and ruled on, not quietly worked around.
- **`global-constraints.md` marks these rules provisional** until E1 lands.

## Amendment, 2026-10-16: the attribute suite (M0 slice 4)

- **`make test` checks these rules.** `tests/test-collect-safe.sps` reads `src/` as data
  and holds every `foreign-procedure` and `foreign-callable` to the table in
  `tests/foreign-conventions.sls`.
  - Each row names an entry point, or a callable by the name it is defined as.
  - It gives the conventions, compared as a set, and quotes a sentence of a decision record.
    The suite finds that sentence in the record, so a row goes stale when its sentence
    changes. When E1 amends this record, the rows that quote it must be revisited.
- **Every occurrence of the two names is accounted for.** Each must be one of these:
  - in the `(only (chezscheme) ...)` import;
  - the head of a form whose entry is a string literal;
  - the head of the template of a known wrapper, today `bind-required`.

  Anything else fails, quoted occurrences included. A callable must be the whole right-hand
  side of `(define name ...)`. A new binding macro joins `known-wrappers`, and every binding
  needs a row.
- **Rows exist before their bindings.** `curl_easy_perform` and `curl_multi_poll` are
  `__collect_safe`, and `curl_multi_perform` and `memcpy` are plain. So if M2 binds
  `perform` plain, the suite fails at once.
- **`curl_easy_cleanup` is plain for now.** The load's header probe cleans up a fresh handle
  that never connected. Its row quotes decision 1's open question, which E1 settles.
- **Function ftypes would bind outside this check,** through `make-ftype-pointer` with an
  entry point's name or a procedure. Three checks keep `define-ftype` out of every other
  library (ADR-0007, amended):
  - `check-seam` lets only `(curl private layouts)` import it, and no library re-export a
    Chez name;
  - `test-constants` holds layouts to struct `define-ftype` forms alone, with no macro;
  - `test-constants` also holds the rule's entry to that one library.
- **Out of reach:** a name built at expansion, through `string->symbol` and
  `datum->syntax`. `src/` uses neither for this.
- **Chez checks decision 4 for strings only.** Measured on the pinned Chez 10.4.0, a
  `__collect_safe` foreign procedure with a `string` or `utf-8` parameter is refused at
  expansion, with `string argument not allowed with __collect_safe procedure`. `u8*` and
  `scheme-object` parameters, and a `string` result, are accepted without complaint. So a
  bytevector passed to a blocking call would get past Chez. Extending the table to
  parameter types would close that gap.
- **M2 must add `foreign-callable` to `check-seam`'s `allowed-chez-names`.** It is not on
  the list today.

## Amendment, 2026-10-16: what a binding may hand C from Chez's heap (M0 slice 5)

- **`test-collect-safe` reads every type as an allowlist.** That covers every parameter and
  result, of procedures, callables and wrapper uses alike.
  - The immediate and address types allowed are those CSUG 10.4.0 §4.2 lists:
    `integer-8` to `integer-64` and their `unsigned-` forms, `double-float`, `single-float`,
    `double`, `float`, `short`, `unsigned-short`, `int`, `unsigned`, `unsigned-int`, `long`,
    `unsigned-long`, `long-long`, `unsigned-long-long`, `ptrdiff_t`, `size_t`, `ssize_t`,
    `iptr`, `uptr`, `void*`, `fixnum`, `boolean`, `stdbool`, `char`, `wchar_t` and `wchar`.
    `void` is allowed as a result only.
  - Also allowed: `(* NAME)` or `(& NAME)`, where `(curl private layouts)` defines NAME with
    `define-ftype`.
  - Anything else fails as unreadable. That includes types the pinned Chez accepts but this
    list leaves out: `integer-24` to `integer-56`, `ptr` (CSUG's alias for `scheme-object`),
    `utf-16` and `utf-32`, `ftype-pointer` and `ftype-scheme-object-pointer`. A binding that
    needs one adds it here by amendment.
- **A macro's pattern variable is never a type or a convention.** A reviewer supplied `u8*` as
  a macro argument, and a reader that knew only the bad types let it through. The allowlist
  alone still passed a pattern variable spelt `uptr`, and Chez then copied one bytevector into
  another. So every symbol in a `syntax-rules`, `syntax-case`, `with-syntax` or
  `identifier-syntax` pattern counts as a pattern variable. Used as a type, it fails as
  unreadable, and used as a convention, it fails as `conventions-from-pattern`. This
  over-approximates: a literal or keyword spelt like a type is refused too.
- **The other types are crossings: they hand C a pointer into Chez's heap,** where Valgrind
  sees nothing (ADR-0014, amended). They come in three kinds:
  - **A bytevector's data:** a `u8*`, `u16*` or `u32*` parameter, or a callable's result of
    those types. Only a row marked `(bytevector-crossing CITATION)` may have one, and M2's
    checked wrapper adds the first (ADR-0001, amended). A procedure's `u8*` result, and a
    callable's `u8*` parameter, are no crossing, since Chez copies C's bytes into a fresh
    bytevector.
  - **A string:** a `string`, `utf-8`, `utf-16le`, `utf-16be`, `utf-32le`, `utf-32be` or
    `wstring` parameter, or a callable's result of those types. A procedure's string result,
    and a callable's string parameter, are copies, and no crossing. Chez makes the copy in its
    own heap, so a callee that keeps the pointer reads garbage once the collector has moved
    or reused it. libcurl keeps some: it does not copy `CURLOPT_POSTFIELDS`, and it writes
    into `CURLOPT_ERRORBUFFER`. So only a row marked `(string-not-kept CITATION)` may have
    one, citing a sentence that its callee keeps no pointer. A string libcurl keeps goes
    through foreign memory.
  - **A Scheme object itself:** `scheme-object`. No row may have one, marked or not.

  Each is its own violation: `bytevector-crossing`, `string-crossing` and `scheme-object`.
  A row carries one mark at most, of either kind.
- **What the callees keep.** `curl_easy_option_by_name` and `curl_easy_header` read their
  name argument during the call, and keep no pointer to it.

  Their rows carry `(string-not-kept ...)` marks quoting that sentence. The live suite holds
  `src/` to exactly those two marks and those two crossings.
- **A marked row is never `__collect_safe`.** That closes, for crossings, the gap the slice 4
  amendment named: Chez enforced decision 4 for strings only, and a bytevector could reach a
  blocking call.
- **For M2:** a callable's code object must be locked with `lock-object` while C holds its
  entry point. Nothing checks that yet.
