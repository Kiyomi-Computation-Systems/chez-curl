# ADR-0013: Calls that can block are `__collect_safe`, and so is every callback they can invoke

- **Status:** Proposed. It binds as written until spike E1 (M3) records its measurements.
  It is then accepted, or amended to fit them.
- **Date:** 2026-10-04
- **Scope:** chez-curl v1: every foreign procedure and foreign callable
- **Settles:** the brief's §5 rule, provisionally
- **Related:**
  - brief §5 and §8 (M2, M3 and spike E1);
  - chez-libuv ADR-0019, whose first decision this mirrors, and ADR-0002, which was held
    until its spike's evidence came in;
  - [ADR-0001](0001-bind-libcurl-directly.md) (`memcpy` is a plain call);
  - [ADR-0012](0012-engine-thread-owns-every-handle.md) (the engine).

## Context

Chez's collector is stop-the-world. The user guide (CSUG 10.4.1 §4.3) says
`__collect_safe` "allows concurrent collection by deactivating the current thread … when
the foreign procedure is called". A thread blocked in a plain foreign call stays active,
so every other thread's collection waits for it. The brief cites chez-libuv's measurements:

| Spike | Setup | Result |
|---|---|---|
| E5c | a worker allocating beside a loop thread blocked in a plain `uv_run` | ~24 ms of allocation took 10.2 s |
| E5g | the same, with `uv_run` declared `__collect_safe` | 23–33 ms |
| E5f | the cost of the declaration | ~60–65 ns per callback conversion |

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
     the call declared plain and then `__collect_safe` (chez-libuv's E5c and E5g);
   - which libcurl calls block;
   - which call each callback fires from;
   - whether one callback may serve both a `__collect_safe` call and a plain one. CSUG does
     not say, and M2's and M3's paths may share callbacks.

   Its findings file decides whether this record is accepted or amended.

### Rejected

- **Every callback `__collect_safe`, as the brief worded it.** That pays ~60 ns per call
  where no `__collect_safe` call can invoke the callback. And CSUG does not say such a
  callback is safe when entered from a plain call, so E1 tests that first.
- **Accepting now on chez-libuv's numbers.** The brief rules it out.
- **No `__collect_safe` at all.** E5c measured what that costs: 10.2 s.

## Consequences

- **M2 starts with `curl_easy_perform` and its callbacks declared `__collect_safe`.**
- **The cost is small where the rule applies.** It is ~60–65 ns per callback conversion
  (E5f), against write chunks of up to 16 KiB (`CURL_MAX_WRITE_SIZE`, 16384).
- **Contradicting findings get raised, not worked around.** A finding during M2 or M3 that
  contradicts this record is raised and ruled on, not quietly worked around.
- **`global-constraints.md` marks these rules provisional** until E1 lands.
