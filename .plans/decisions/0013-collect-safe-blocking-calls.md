# ADR-0013: Calls that can block are `__collect_safe`, and so is every callback they can invoke

- **Status:** Accepted 2026-10-24, from spike E1 (M3 slice 1), with the amendment that ends
  this record. Proposed from 2026-10-04 until then. Amended 2026-10-16 with the attribute suite
  (M0 slice 4), and with what a binding may hand C from Chez's heap (M0 slice 5). Amended
  2026-10-17 with what the reader holds the binding macros to (M0 slice 6). Amended
  2026-10-23 with M2 slice 1's rows, and with how control leaves the write callable (M2 slice 2).
  Amended 2026-10-24: `curl_multi_perform` can block (the M3 plan). Amended 2026-10-30:
  `curl_easy_pause` and the header callable (M6 slice 1). Amended 2026-10-31: the read, seek
  and prerequest callables (M6 slice 2).
- **Date:** 2026-10-04
- **Corrected:** 2026-10-04. The E5 series is chez-http-server's, not chez-libuv's. Its
  figures are restated from that spike report, which ran on macOS only.
- **Scope:** chez-curl v1: every foreign procedure and foreign callable
- **Settles:** the brief's §5 rule, provisionally until spike E1, and then as amended
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

Provisional until E1. E1 accepted it on 2026-10-24, with the amendment that ends this record:
read each decision below with it.

1. **A libcurl call that can block is a `__collect_safe` foreign procedure.** Known now:
   `curl_multi_poll` and `curl_easy_perform`. E1 classifies the rest, starting with the
   cleanup paths `CURLOPT_QUICK_EXIT` describes: `curl_multi_remove_handle` and
   `curl_easy_cleanup`.
2. **A callback is `__collect_safe` when libcurl can invoke it from inside a
   `__collect_safe` call** (CSUG). M2's transfer callbacks run inside `curl_easy_perform`,
   so they are.
3. **Calls that cannot block stay plain.** That covers setopt, getinfo, the `curl_url`
   family and `memcpy` (ADR-0001). It covers `curl_multi_perform` too, which curl documents
   as non-blocking, until E1 says otherwise. (E1 said otherwise: `curl_multi_perform` can
   block.) A callback fired only from plain calls stays plain.
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

## Amendment, 2026-10-17: what the reader holds the binding macros to (M0 slice 6)

- **The hole.** The reader held every occurrence of `foreign-procedure` to account, but held
  the known wrappers only where their name headed a form. Slice 6's review bound
  `curl_easy_setopt` with no `(__varargs_after 2)` three ways, and each passed `make test`:
  - the use inside quasiquote, which the reader reads as data;
  - an `identifier-syntax` alias of `bind-required`;
  - `bind-required` handed to another macro as an argument.

  The last also bound a plain `curl_easy_perform` with an unmarked `u8*`, against decision 4
  and the slice 5 amendment, and `test-collect-safe` passed 67/67. The hole dated from
  slice 4.
- **A wrapper's name is now an occurrence,** held to two places: the head of a use in code,
  and the name its one `define-syntax` defines. Code is outside data and outside every macro,
  since a head inside a macro can still be reached as data. Anywhere else, the name is
  `stray`: as an argument, in data, in a macro, bound as a name, or in an export or import.
  So no library exports a wrapper, and none reaches one under another name.
- **A row may name its binder,** `(bound-by NAME)`, after any mark. A binding of its entry
  made any other way is `wrong-binder`. ADR-0001's four variadic rows name `bind-variadic`.
- **Every macro `src/` defines is a row of `known-macros`:** its name, its kind and its file.
  A macro can take apart a form it is handed, and bind what it rebuilds, while the reader
  reads the form as written. Each of these bound an entry the reader never saw, with
  `make test` green, in the fix rounds' probes: a new macro rewriting a use's entry, and a
  `syntax-case` taking its own template apart.
  - A `define-syntax` at a library body's top level must name a row and stand in its file:
    `macro-unlisted`, `macro-elsewhere`.
  - Any other `define-syntax` is `macro-nested`, and every `let-syntax` and `letrec-syntax`
    is `macro-local`.
  - The kinds are `binder` (the known wrappers) and `plain`. Fixtures may use a third,
    `any`, held to its place and file only. The live suite pins `src/`'s table by hand, so
    `src/` cannot use `any`.
- **A binder's pattern takes no operand apart.** Every element but its parameter list is a
  symbol. A pattern like `(_ entry (arg ...) result (w e . rest))` could rebuild a use
  handed to it, and the reader had never looked.
- **A plain macro may not build a binding or touch its input.** It holds:
  - no `foreign-procedure`, `foreign-callable` or wrapper name (`plain-macro-binds`);
  - none of `syntax-case`, `with-syntax`, `syntax->datum` or `datum->syntax`
    (`plain-macro-takes-apart`);
  - for `syntax-rules`, only flat patterns, `(_ id ...)` (`plain-macro-pattern`).

  A procedural one has more rules:
  - It is exactly `(lambda (ID) BODY ...)` (`plain-macro-transformer`).
  - ID stands only as the last argument of a `syntax-violation` call
    (`plain-macro-input`).
  - `syntax-violation` stands only at the head of a call in tail position
    (`plain-macro-raise`). In a `guard`, a handler can take the input back out of the
    condition with `syntax-violation-form`. A `let` can also rebind the name.
  - Its library imports only whole `(rnrs ...)` libraries, never `(rnrs eval)`, and
    `(only (chezscheme) ...)` (`plain-macro-import`). Otherwise another library's
    `syntax-violation`, or a procedure that builds a binding from strings, gets in.
  Each route was probed: handed `(foreign-procedure "labs" ...)`, Chez answered
  `no entry for "abs"`. Today's plain macros, `load-step` and `require-supported-chez`,
  pass as written.
- **A flat pattern still let a use hand a macro its head.** A scoped review of the fix
  rounds gave `load-step` a second clause, `((_ head operand ...) (head operand ...))`.
  native.sls then wrote `(load-step define-syntax bind-quietly ...)`, and bound an entry
  through the macro that defined. `test-collect-safe` passed 102/102, and Chez bound the
  hidden entry. Two rules close it:
  - `define-syntax`, `let-syntax` and `letrec-syntax` are occurrences. Each stands only at
    the head of a form written in code, and is `stray` anywhere else;
  - no pattern variable heads a form in a listed macro's template (`macro-pattern-head`).
    The one exception is a binder's `foreign-procedure` parameter list, `(arg ...)`, which
    is types and never evaluated.
- **A `case` clause's datum list is data.** The reader had walked it as code, and counted a
  binding there that Chez never makes.
- **What the rest rests on.** Chez refuses a raw symbol in a transformer's output, so a built
  name needs `datum->syntax`. It also refuses a second `syntax-violation` beside a whole
  `(rnrs)`. `check-seam`'s allowlist keeps `eval`, `expand` and `interpret` out of `src/`,
  and its rules (h) and (i) keep every library a `src/` library imports in `src/`, where
  this reader reads it (ADR-0007, amended).
- **Limit: a phantom.** A plain macro that quotes an operand, `((_ tag expr) (quote expr))`,
  makes the reader count a binding Chez never makes. Alone it hides nothing, and no route
  that hides a binding is known open. The reader's header names it with the other limits.
- **For M2, measured on small trees,** these rules will need reviewed additions:
  - a callable must be the whole right-hand side of a `define` with a symbol name. A
    callable in a `let`, one made by a factory procedure, and two through `define-values`
    were each refused as `callable-not-defined`;
  - a helper macro with a nested pattern, such as `(with-easy-handle (h) body ...)`, is
    refused as `plain-macro-pattern`. No kind admits one yet;
  - `curl_easy_perform` needs a third binder, whose template carries `__collect_safe`.
- **Evidence:** the fix rounds of the
  [variadic mutation log](../variadic-mutation-log.md): 74 cases on a snapshot identical to
  the tree. Its 72 mutations are each killed by name, PH1 shows the phantom above, and the
  unchanged tree passes.

## Amendment, 2026-10-23: M2 slice 1's rows

- **New `cannot-block` rows:** `strlen`, and the URL API's six, `curl_url`, `curl_url_set`,
  `curl_url_get`, `curl_url_cleanup`, `curl_url_strerror` and `curl_free`. Decision 3 names the
  `curl_url` family as calls that cannot block.
- **`memcpy`'s row carries the first `bytevector-crossing` mark,** quoting ADR-0001: "One checked
  wrapper owns every copy between a bytevector and foreign memory." It stays plain. Two
  conventions fixtures that had used `memcpy` as an unmarked crossing now bind a fixture entry of
  their own.
- **`test-collect-safe` writes out what it holds:** the reader's whole type universe, and this
  slice's rows, each in full. A row and the binding it holds can no longer be loosened together.
- **No new string crossing.** Every string chez-curl hands libcurl from M2 on goes through foreign
  memory (ADR-0001, amended 2026-10-23), so the two `string-not-kept` rows stay the only ones.

## Amendment, 2026-10-23: how control leaves the write callable (M2 slice 2)

M2 slice 2 binds `curl_easy_perform` through `bind-blocking`, a binder whose template
carries `__collect_safe`. Its row reads `(bound-by bind-blocking)`. The transfer's one
callable, `write-body`, is `__collect_safe` too, and locked. Without the lock, the suite's
paced collector failed it 3 runs of 3. The reviews then found three ways control can leave
the callable other than by its return.

- **Caller code's continuations.** A raise inside the callable is caught by its guard. But
  an outer continuation invoked from the test hook, or a stale one from an earlier chunk,
  left the callable. `curl_easy_cleanup` then ran while libcurl was still inside its
  callback. 744 bytes were definitely lost under the gate's Valgrind, with a socket left
  open, and every count read zero. **Now the hook runs in a `dynamic-wind`** whose after
  thunk turns any exit but a return into a raise, which the guard records.
- **Asynchronous handlers.** An engine's expiry inside the callable did the same. So does
  a timer-interrupt handler, or a keyboard interrupt followed by `reset`.
  - **First fix, measured, then reversed:** `curl_easy_perform` in a `critical-section`. It
    moved the expiry to after perform returned. But then the thread put off its own collect
    requests until the transfer ended:
    - an 80 MB body in 4 KiB writes grew the peak heap by 472 MB, against 344 MB without it;
    - Ctrl-C went unanswered until the transfer ended, which with no timeout may be never.
  - **Decided, by the maintainer: escapes are allowed, and counted.** chez-curl never
    calls libcurl on a handle whose perform was left without its return:
    `curl_easy_cleanup` must not run while a call on the same handle is still running. That
    handle stays counted as `easy`, so a suite fails on it. libcurl's connection leaks with
    it: about 8 KB, and its sockets, one per escape on 8.20.0 and nearer three on 7.85.0
    (98 for 35 escapes). What libcurl can no longer read, the header list, the error
    buffer, the `CURLU` and the key, is freed.
  - **Why:** the critical section's costs fall on every transfer, and an escape needs a
    handler that escapes. M3 moves transfers to an engine thread that runs no caller code and
    no handlers, so this covers only M2's blocking path.
- **The windows around every native object.** An escape between making an object and
  recording it, its count, a table entry, or the variable its free reads, leaked it for good.
  So did one between taking a mutex and entering `with-mutex`'s own `dynamic-wind`: that
  mutex stays held, and every other thread blocks on it. So each make-and-record, and each
  free-and-unrecord, is one critical section: a `(dynamic-wind #t ...)` extent or a
  `critical-section`. Every mutex is held through `locked`, which is `critical-section`
  around `with-mutex`. These sections are short, and make no foreign call that can block.
- **How the escapes are tested.** A deliberate escape leaks, and the gate's Valgrind would
  fail on it, so a child Chez process, `tests/transfer-escapes.sps`, runs them and prints each
  case. `test-transfer` requires each one to have completed with zero counts, expired outside
  perform with zero counts, or escaped inside it with one `easy` counted. Both kinds of expiry
  must occur, and a whole transfer must escape inside more often than one refused at
  connect, which has no callback. Without that last rule, the sweep passed with the critical
  section put back, on the two escapes that fall around the call itself. A test in the child
  arms a timer inside a drip and requires its handler to run before the transfer ends, so the
  critical section cannot come back unseen.
- **An escape between setting the performing mark and entering C, or between returning and
  clearing it, counts as inside.** It leaks a handle that cleanup could have freed, the
  conservative side.
- **Limits, stated rather than fixed:**
  - a transfer cannot be paused by an engine and resumed: its extents refuse re-entry;
  - an engine that expires inside the test hook dies, `no engine active`: the hook's refusal
    raises during the engine's own unwind. The hook is a private test seam, and M3's callable
    runs no caller code;
  - an escape during the library body's load wedges `(curl private native)` for the
    process, since `load-step` records raises, not escapes. A program that imports `(curl)`
    loads it before its body runs.


## Amendment, 2026-10-24: `curl_multi_perform` can block (the M3 plan)

Decision 3 kept `curl_multi_perform` plain "until E1 says otherwise". The M3 plan measured
otherwise before planning, and it is raised here, as this record asks of a contradicting
finding.

- **A transfer's own timeout during a stalled name lookup blocks inside one
  `curl_multi_perform` call for about 9 s,** on 7.85.0 and Ubuntu's 8.5.0, with OpenSSL and
  with GnuTLS. `curl_multi_remove_handle` blocks as long on a cancel there, and on 8.20.0
  `curl_multi_cleanup` does ([ADR-0019](0019-a-stalled-lookup-does-not-stall-the-engine.md)).
  Under decision 1 all three are `__collect_safe`, through `bind-blocking`, with
  `curl_multi_poll`. That is ADR-0019's decision 3.
- **A plain wait costs far more than the E5 series showed.** Chez checks a pending collection
  only when a thread's event counter, 1000 ticks, runs out, and a loop that waits in a plain
  `curl_multi_poll` spends about one tick per wait. So another thread's collection waited
  about 500 polls. Beside a plain poll of 1, 3 and 10 ms, a worker's 14 ms of allocation took
  5.4 s, 15.9 s and 54.4 s. At 300 ms, E5c's timer, that extrapolates to about 27 minutes,
  against 10.3 s in E5c; those runs were killed at 30 to 120 s, 6 of 6. With the poll
  `__collect_safe`, it took 14.1–15.5 ms. The safe poll and the plain 1 ms poll measured the
  same on the four Linux libcurls, and the rest ran on 8.20.0.
- **A `__collect_safe` callable may be entered from a plain call.** Chez 10.4.0's callable
  entry saves the thread's state from `S_activate_thread` and restores exactly it on exit, so
  inside an active thread both are no-ops (`c/thread.c`, `s/x86_64.ss`, `s/arm64.ss`). In the
  container, on 8.20.0, a `__collect_safe` write callable fired from a plain
  `curl_multi_perform` delivered every byte, 3 runs of 3, beside a thread that collected about 1,000 times a run. Write callbacks
  fired inside `curl_multi_perform` only, never inside `curl_multi_poll`.
- **This record stays Proposed.** Spike E1, M3's first slice, reruns each of these from
  committed programs, and accepts or amends this record from its findings. The rows that
  quote decision 3 move then.

## Amendment, 2026-10-24: accepted, from spike E1 (M3 slice 1)

Spike E1 ran decision 5's four questions from programs committed under
[`.plans/research/e1/`](../research/e1/), twice on each of the four Linux libcurls: Guix's
8.20.0 in the container, the floor's 7.85.0, and Ubuntu's 8.5.0 with OpenSSL and with
GnuTLS. The container cannot stall a name lookup, so the lookups also ran on Guix's 8.20.0
from the store, in Docker. A read-only review then sent `lookup`, `interrupt` and the load
race back for two more runs on each lane. The [findings](../research/e1/findings.md) decide
this record. It is accepted, with these amendments.

- **`curl_multi_perform`, `curl_multi_remove_handle` and `curl_multi_cleanup` can block, so
  each is `__collect_safe`.** While a name lookup stalled, each returned 9 to 10 s after the
  transfer began. libcurl documents the wait as its resolver thread's
  (`CURLOPT_QUICK_EXIT(3)`, quoted in ADR-0019); E1 saw no thread itself:
  - `curl_multi_remove_handle`, taking the transfer apart, on 7.85.0 and 8.5.0;
  - one `curl_multi_perform`, at the transfer's own timeout, on the same libcurls;
  - `curl_multi_cleanup` on 8.20.0.

  With `curl_multi_poll` and `curl_easy_perform`, these are decision 1's calls. Decision 3's
  sentence on `curl_multi_perform` no longer holds, and its row moves.
- **These stay plain: `curl_multi_init`, `curl_multi_add_handle`, `curl_multi_wakeup`,
  `curl_multi_info_read`, and `curl_easy_cleanup` of a handle removed from a multi handle the
  caller made.** None took a millisecond in any run, stalled or not. That settles decision 1's
  open question on `curl_easy_cleanup` for the engine, which removes every handle before it
  cleans it up: the wait `CURLOPT_QUICK_EXIT` describes is in the removal, or in the multi
  handle's cleanup. ADR-0019 sets both quick-exit options where libcurl knows them.
- **`curl_easy_cleanup` after `curl_easy_perform` can block.** On 8.20.0, during a stalled
  lookup, it waited 9,045–9,046 ms, 2 runs of 2, and none with `QUICK_EXIT` set. On the other
  libcurls the wait was inside `curl_easy_perform`. M2's blocking path binds
  `curl_easy_cleanup` plain, inside a critical section, and sets no `QUICK_EXIT`, so on 8.20.0
  it breaks decision 1 there. Slice 2 deletes that path (the M3 plan, §5.4), and with it the
  only cleanup of a handle `curl_easy_perform` ran. The maintainer chose on 2026-10-25 to
  leave it until then, rather than set `QUICK_EXIT` on M2's transfers now: the path is
  private, nothing is released, and no suite can stall a lookup before slice 3.
- **Decision 2 holds.** A transfer's write callback fired inside `curl_multi_perform` and
  nowhere else: 352 of 352 callbacks in each run, none inside `curl_multi_poll`, and all on
  the engine's thread. So the engine's write callable is `__collect_safe`, as its perform is.
- **One callable may serve a `__collect_safe` call and a plain one** (decision 5's last
  question). A `__collect_safe` callable's entry saves the thread's state from
  `S_activate_thread`, and its exit restores exactly that, so inside an active thread both are
  no-ops (Chez 10.4.0's `c/thread.c`, `s/x86_64.ss`, `s/arm64.ss`). Four transfers delivered
  every byte, while another thread collected about 1,000 times a run, with a `__collect_safe`
  callable inside a plain `curl_multi_perform`, with both plain, and with both
  `__collect_safe`. The control CSUG rules out, a plain callable inside a `__collect_safe`
  perform, crashed Chez in 8 invocations of 8 ("nonrecoverable invalid memory reference"), so
  the runs can tell a pairing that fails.
- **A plain wait holds a collection for up to about 500 waits** (decision 5's first
  question), whatever each wait's length. Chez reads a pending collection only when a thread's
  1000-tick event counter runs out, and a loop round a plain `curl_multi_poll` spent about 2
  ticks a turn, so about every 500 polls. A lone collection waited 51 to 466 polls, by when it
  was asked. Collections close together waited nearly all of it: beside a plain poll of 1 ms, a
  worker's 15 ms of allocation, 11 collections, took 5.4 s. Spending more ticks per turn of
  the loop shortened the wait in proportion. Beside a `__collect_safe` poll, the worker took
  what it took with no engine thread.
- **Not measured:** macOS, Linux on arm64, Valgrind, TLS transfers, a slow connect, and every
  callback but the write callback.

## Amendment, 2026-10-25: a wait holds its mutex through a critical `dynamic-wind` (M3 slice 2)

The 2026-10-23 amendment holds every mutex through `locked`, `critical-section` around
`with-mutex`. The M3 plan then had await wait in timed waits of 100 ms, each in its own
critical section through `locked` (§3.4), from spike E1's Ctrl-C finding. Slice 2 measured
that before building it, from scratch programs.

- **A wait inside a critical section holds every other thread's collections until it ends.**
  Chez 10.4.0's `condition-wait` deactivates its thread only when interrupts are enabled
  (`DISABLECOUNT(tc) == 0`, `c/thread.c`), and so does a `mutex-acquire` that blocks
  (`c/prim5.c`). A thread waiting inside `critical-section` stays active, and a collection
  waits for every active thread. On Guix's Chez and on CI's, 2 runs each:
  - while the main thread waited 3 s in such waits, a worker asking for a collection every
    20 ms made 30 of them, each waiting a median 80 ms, at most 100 ms. With the waits below,
    it made 150, a median 0.0 ms, at most 0.7 ms;
  - in a prototype engine, 30 transfers awaited that way took 612 to 1,535 ms on the four
    Linux libcurls, and 7.6 to 17.6 ms awaited as below. Single awaits took exactly 100 or
    200 ms: the engine's thread was held in a collection that waited for the caller's wait.
- **Decided, by the maintainer: a wait holds its mutex through a critical `dynamic-wind`.**
  Its before thunk takes the mutex and its after thunk releases it, each with interrupts
  off, and an escape runs the after thunk the same way (`cwind` and `$do-wind`, `s/4.ss`).
  So no escape falls between taking the mutex and the record that releases it, as with
  `locked`. The timed wait runs in the body, with interrupts on, so the thread is inactive
  while it waits. Ctrl-C still runs within one wait, since the after thunk's end runs
  pending events at once: the handler ran at 1,101 ms, against 1,103 to 1,104 ms in a
  critical section, and 3,003 to 3,017 ms with no critical section at all.
- **`locked` stays for every hold that does not wait.** Such a hold is short, and makes no
  foreign call that can block. A thread blocked taking a mutex inside `locked` stays active
  too, so no hold may wait.
- **The wait is held by behaviour.** `test-engine` requires a worker's collections beside a
  caller awaiting a slow transfer to finish within a bound, a check watched failing on the
  critical-section wait. `check-seam` lets `(curl private engine)` import `mutex-acquire` and
  `mutex-release`.

## Amendment, 2026-10-25: M2's escapes ended with M2's path, and the engine is bound (M3 slice 2)

- **The 2026-10-23 amendment's escape rules ended with M2's blocking path.** Slice 2 deleted
  `perform-transfer`, the `curl_easy_perform` binding and its row. The engine's write callable
  runs no procedure a caller supplied, so the hook's `dynamic-wind`, the performing mark and
  the escape child, `tests/transfer-escapes.sps`, went with them. Chez sends Ctrl-C to the
  main thread alone, and the engine's thread sets no timer and runs no engine, so nothing
  escapes inside its perform but through `collect-request-handler`, which is process-wide:
  a caller's handler that escapes could run on the engine's thread (the M3 plan, §3.6). What stays is the window rule: each native object is made, or
  freed, in one critical section with its record, now the transfer's live record, and every
  hold of a mutex that does not wait is `locked`'s.
- **The four multi calls that can block are bound through `bind-blocking`,** and their rows
  name it. `curl_multi_poll` is the engine's wait, so it is `__collect_safe`. `curl_multi_init`, `curl_multi_add_handle`,
  `curl_multi_wakeup` and `curl_multi_info_read` are bound plain through `bind-required`, as
  E1 classed them, and so is `curl_multi_strerror`, which cannot block. The callable's row
  cites decision 2 as E1 held it: it fires inside `curl_multi_perform`.
- **A blocking free may run in a critical section.** A `__collect_safe` call deactivates its
  thread whatever its disable count (`Sdeactivate_thread`, `c/thread.c`), so the engine frees
  its multi handle in the critical section that counts it down, and other threads' collections
  go on while `curl_multi_cleanup` waits.

## Amendment, 2026-10-25: a wait polls, and holds no mutex (M3 slice 2, after its review)

The first 2026-10-25 amendment had a wait hold its mutex through a critical `dynamic-wind`.
The slice's adversarial review found that it deadlocks, and the maintainer chose again.

- **The wound wait deadlocks the process.** A critical `dynamic-wind` enables interrupts
  once its before thunk has taken the mutex, and its body runs with them on, so a waiter
  that holds the engine's mutex can join a collection's rendezvous holding it. A second
  thread blocked taking that mutex with interrupts off, in `locked` or in another waiter's
  before thunk, stays active, since a blocked `mutex-acquire` deactivates only with
  interrupts on (`c/prim5.c`). The collection waits for it, and it waits for the holder.
  Reproduced: four caller threads, each submitting and awaiting in a loop, hung within 1 s,
  3 runs of 3. No check had two threads waiting while a collection ran.
- **Decided, by the maintainer: a wait polls.** It holds no mutex while it waits, and uses
  no condition variable. Each read of the state it waits for is a short hold through
  `locked`, and between reads it sleeps, 50 µs at first, doubling to 10 ms. Chez's `sleep`
  deactivates its thread when interrupts are on, and sets the thread's trap, so a pending
  Ctrl-C runs as it wakes (`s_nanosleep`, `c/prim5.c`). So every hold of every mutex is
  `locked`'s, short, with interrupts off, and none waits: a thread blocked taking one waits
  only for a holder that cannot join a collection. This supersedes the wait rules of the
  two amendments above.
- **A wait needs interrupts on, and refuses to start without them.** With interrupts off,
  `sleep` leaves its thread active, so a collection waits for it, the engine's thread parks
  in that collection, and the token never completes: an await inside `critical-section`
  hung its process, killed at 30 s (the fix's scoped review). So `curl-token-await`,
  `curl-engine-stop` and `make-curl-engine` each raise an assertion violation before they
  do anything when interrupts are off, read from `disable-interrupts`' count.
  - **Measured:** no hang with 4 threads for 10 s, about 234,000 transfers, and 8 threads for
    30 s; and the review's tight probe, an awaiter beside a thread polling the same token. In
    the container, `test-engine` passed, its collection bound and its Ctrl-C child among its
    checks. Under the gate's Valgrind, which runs one thread at a time, 4 threads made 5,226
    transfers in 10 s and finished cleanly.
  - **The alternative, rejected:** take the mutex by trying, never blocking, with pending
    events run between tries. It kept prompt wakeups and about 20% more throughput in a
    tight local loop, but it spins under contention. Under Valgrind the same 4-thread run
    made 607 transfers in 10 s and never finished, killed at 600 s.
  - **Its costs:** a completion is seen up to the current sleep late, 10 ms at most once a
    wait has slept about 13 ms, 50 × (2^8 − 1) µs, and a waiter wakes up to 100 times a
    second. A child holds both: five 500 ms drips each returned within 30 ms of a watcher
    seeing them done, and a 2 s await spent under 2% of its time on the CPU. A sleep of 1 s
    or more cannot be asked for: `make-time` refuses nanoseconds past 10^9.
- **check-seam** no longer lets any library import `mutex-acquire`, `mutex-release`,
  `make-condition`, `condition-wait` or `condition-broadcast`, since none is needed.
  `(curl private engine)` imports `sleep`, and alone imports `disable-interrupts` and
  `enable-interrupts`, to ask whether a wait may start.

## Amendment, 2026-10-30: `curl_easy_pause` and the header callable (M6 slice 1)

M6 streams a response (ADR-0030). Its first slice binds `curl_easy_pause` and makes a second
callable, the header callable, `read-head`.

- **`curl_easy_pause` blocks on nothing,** but it runs the write and header callables, and from
  8.20.0 libcurl's content decoders, before it returns (the M6 plan, §2.2). Slice 1 measured a
  gzip body under the hatch's `ACCEPT_ENCODING`, paused 1 s, on the five Linux libcurls
  ([research](../research/m6/slice1/)): the longest call took 21.647 ms. Bound plain, a
  collection another thread asked for during a call ended up to 7.024 ms after the call
  returned; bound `__collect_safe`, 1.271 ms. So it is bound `__collect_safe`, through
  `bind-blocking`, and its row names that wrapper, as the four multi calls' do. The engine
  calls it holding no mutex and outside any critical section (ADR-0012, amended 2026-10-29).
- **The header callable** is `__collect_safe`, since `curl_multi_perform` and `curl_easy_pause`
  fire it; it is locked where it is defined and never unlocked, held to `curl_write_callback`'s
  typedef, and its whole body runs under a guard that records what is raised and answers 0, as
  the write callable's does. It runs no procedure a caller supplied.

## Amendment, 2026-10-31: the read, seek and prerequest callables (M6 slice 2)

M6's second slice streams a request's body (ADR-0030, ADR-0032) through three more callables in
`(curl private transfer)`: the read callable `read-body`, held to `curl_read_callback`'s typedef;
the seek callable `seek-body`, to `curl_seek_callback`'s; and the prerequest callable
`prereq-body`, to `curl_prereq_callback`'s. libcurl fires each inside `curl_multi_perform`, a
`__collect_safe` call; `curl_easy_pause` calls none of them, by the source (the M6 plan, §2.2),
and slice 2's measurement saw no read inside it in 320 transfers of 320 (its `check`). So each is
`__collect_safe`, as the write and header callables are, locked where it is defined and never
unlocked, and handed the transfer's key as its data, so no Scheme object crosses into C. Each
whole body runs under a guard that records what is raised and answers the value that refuses the
transfer: `CURL_READFUNC_ABORT`, `CURL_SEEKFUNC_CANTSEEK` and `CURL_PREREQFUNC_ABORT`. None runs
a procedure a caller supplied. `test-constants` holds each typedef, and `test-collect-safe` each
row.

A private test seam, `make-curl-engine-holding-prereq`, sleeps inside the prerequest callable, so
a test can hold the engine's thread between connect and send, as a collection could. The turn
calls `curl_multi_perform` outside every critical section and hold, so the sleep holds no mutex,
and the seam checks interrupts are on first, so the sleep deactivates the thread and other
threads' collections go on. No caller's engine has it.

