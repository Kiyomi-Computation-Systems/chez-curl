# Request mutation log (M4 slice 1)

Each mutant of the first table was applied to a fresh copy of the tree, one at a time, by
`build/m4s1/mut.sh`, a scratch script, and its suites ran there in the container (Chez
10.4.0, libcurl 8.20.0). A mutant passes only if its suites exit 0 on it. The runner first
stopped after five of the list, the container's shell having read the rest of it from stdin
(`traps.md`); the rest ran once it gave each command `/dev/null`.

## The request, the classes and the constants

| Mutant | Change | Failed |
|---|---|---|
| `no-expect-suppression` | no `Expect:` for a body | `sent-header-lines`, written out; the 1,048,577-byte body, whose head now carries `Expect` |
| `no-ctype-suppression` | no `Content-Type:` for a body | `sent-header-lines`; each method's head, byte for byte |
| `delete-always-body` | `delete` without a body sends an empty one | the same two |
| `post-no-empty-body` | `post`, `put` and `patch` without a body send none | the same two |
| `copy-before-size` | `COPYPOSTFIELDS` set before `POSTFIELDSIZE_LARGE` | every byte value, the 1,048,577-byte body and the request's own headers: libcurl copied the body before it was told its size |
| `no-body-copy` | the plan keeps the caller's bytevector | the body copied at submit |
| `connect-as-total` | the connect timeout sent as `TIMEOUT_MS` | its control: the transfer pausing 1 s mid-body ended 28 |
| `no-connect-timeout` | the connect timeout never set | the stalled handshake took the whole bound, past 5 s |
| `timings-all-total` | every timing read from `TOTAL_TIME_T` | the timings' order |
| `timings-first-byte-is-total` | `first-byte` read from `TOTAL_TIME_T` | `timing-infos`, written out, and the timings' order |
| `request-size-zero` | a `perform-failed` carries a request size of 0 | a failure's class and request size |
| `failure-unclassed` | a failed transfer raises the base type | the connect timeout's class, and every failure's |
| `move-56` | 56 out of send-receive | `curl-code-class`, by its row, and the perform-failed of each code, by its row |
| `body-limit-base` | `body-limit` raises the base type | the reasons' rule; the body limit's failure |
| `no-repeated-check` | a key given twice is taken | `repeated-key`; `curl-request-with`'s refusals |
| `missing-before-unknown` | `missing-value` checked before `unknown-key` | an unknown key with no value is `unknown-key` |
| `no-body-not-allowed` | a body taken with `get` and `head` | `body-not-allowed`; `curl-request-with`'s refusals |
| `always-follow` | `FOLLOWLOCATION` set on every transfer | no redirect followed |
| `with-drops-private` | `curl-request-with` drops the fault and following | the private constructors |
| `too-large-value` | `curle-too-large` at 99 | `curle-too-large is CURLE_TOO_LARGE`, from the container's 8.20.0 headers |
| `named-case-sensitive` | the request's own headers matched by case | `sent-header-lines` |
| `class-no-code-check` | a class's constructor takes any code | each class's constructor's refusals |
| `drop-101` | 101 out of tls | `curl-code-class` and the perform-failed of each code, by 101's row |
| `setup-size-nonzero` | a set-up refusal carries a request size of 1 | a failure's class and request size: the refused setopt |
| `ended-size-zero` | a cancelled or stopped transfer carries a request size of 0 | first: nothing, `test-request` read no cancel. Then a token cancelled while queued |
| `put-lowercase` | `CUSTOMREQUEST` at `put` | each method's head, and every byte value through `put` |
| `connect-type-unchecked` | the connect timeout's type unchecked | the wrong types; `curl-request-with`'s refusals |

## Not killed, by design

- **A NULL for an empty body,** in place of the one-byte block. NULL and `""` send the same
  request on every libcurl measured (the M4 plan, §2), and with a size of 0 libcurl reads none
  of it, so no test on the wire can tell them apart. The block is there because libcurl's
  setopt reads NULL as "use the read callback", whose default reads stdin (ADR-0023, amended).
- **The `long` reader for a timing,** in place of the `off_t` one. Every platform chez-curl
  supports is LP64, where a `long` and a `curl_off_t` are both 64 bits, so the two readers
  answer alike; the plan reads `off_t` so that no reader is right by accident.

## The migration agent's, in its own copy

The agent that moved the transfer and engine suites to the new request ran these, each
reverted after; I reran the first two in a copy of my own, and each failed as it reported.

| Mutant | Change | Failed |
|---|---|---|
| `move-56` | 56 from send-receive to protocol | three shared scenarios' class checks, `reset-after-pause`, `bad-chunk-size` and `reset-mid-body`, and `class-of`'s reader |
| `move-100-out` | 100 out of too-large | 8.20.0's row: both `big-header` scenarios and `many-headers`, each `(perform-failed 100 none)` |
| `body-limit-unclassed` | the body limit's rule removed | the 12 body-limit edges and the limit-6, fault-3 row |
| `sizes-swapped` | a set-up refusal's request size #f, a cancel's and a stop's 0 | the unknown-option, setopt-failed and seam refusals, the CA file's setopt, `test-engine`'s unknown option, 7 cancels and stops, and 3 stall children |
| `all-timeouts` | every unclassed failure raised as a timeout | the 3 callback-raised fault rows, and the unknown-option, setopt-failed, cancelled and stopped class checks |

## After the slice's review

The review (Opus, read-only) found the connect timeout's bound loose, `delete` with an empty
body and a raise's request size untested, and two twins unowned. Each check it asked for was
written, and these mutants then failed it, in a fresh copy:

| Mutant | Change | Failed |
|---|---|---|
| `connect-ten-times` | the connect timeout sent at ten times its value | the stalled handshake, bound to 300 ms to 2 s |
| `connect-whole-seconds` | sent as `CONNECTTIMEOUT`, in seconds rounded up | first, the stalled handshake, bound to 300 to 900 ms. Ubuntu's Valgrind took 990 ms there, so the bound became 2 s, which this mutant passes; then `test-transfer's reader of `set-transfer-options!`, form by form |
| `delete-empty-as-none` | `delete` with an empty body sends none | `sent-header-lines`; each method's head |
| `callback-size-zero` | a raise in the callable carries a request size of 0 | a failure's class and request size |
| `crlf-not-owned` | `CRLF` out of `owned-option-names` | the list, written out |
| `request-size-zero-again` | `request-size-zero`, rerun on the engines of their own | a failure's class and request size |
