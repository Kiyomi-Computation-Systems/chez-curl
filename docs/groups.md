# Groups: many calls at once

**One engine thread runs many requests.** A session's engine is one thread,
and it drives every transfer submitted to it at once. So to make many
requests at once you need no thread per request: start them all from your
one thread, and wait for them.

At the high level, a request group does it, and `http-parallel` does it for a
list. At the low level, submit many requests to one engine and await their
tokens, or take them from a mailbox ([The low level](low-level.md)).

```scheme example=examples/group.sps
    ;; http-parallel: a list of calls, at most two at once; the responses
    ;; come back in the list's order, whichever ends first.
    (write (map http-response-status
                (http-parallel session
                               (list (list 'get (url "/status/200"))
                                     (list 'get (url "/status/201"))
                                     (list 'get (url "/status/404")))
                               'limit 2)))
    (newline)
    ;; A group: go starts a call and hands back its pending at once;
    ;; http-await gives its response.
    (call-with-request-group session
      (lambda (go)
        (let* ((a (go 'get (url "/status/202")))
               (b (go 'get (url "/status/203"))))
          (write (list (http-response-status (http-await a))
                       (http-response-status (http-await b))))
          (newline))))))
```

```text output=examples/expected/group.out
(200 201 404)
(202 203)
```

## A request group

`(call-with-request-group SESSION KEY VALUE ... PROC)` calls PROC with `go`,
on your thread.

- **`(go METHOD URL KEY VALUE ...)`** starts a call, as `http-request` takes
  one, and answers its pending at once. Its method, keys and URL are checked
  first: a refusal raises from `go`, and starts nothing.
- **`http-await`** gives a pending's response, or raises its failure, the same
  any number of times. **`http-pending-done?`** moves the group on one turn
  and tells whether the call has ended. **`http-pending-cancel`** ends it as
  cancelled.
- **Whichever call your thread waits for, it drives them all,** so one call's
  redirect or retry goes on while you await another.
- **`limit`** caps how many calls run at once. The rest wait their turn, first
  in, first out, each on its own clock from its `go`: a bound that passes
  while it waits fails it with `&http-timeout`. A call keeps its slot through
  every redirect, retry and wait.
- **The group waits for every call before it returns,** and then raises the
  first failure you never awaited. A call you cancelled raises nothing.
- **If PROC escapes,** the group cancels every call, waits for each transfer
  to end, and lets the escape go on. A stalled name lookup can hold that wait
  on some libcurls ([What varies](libcurl-versions.md#engines-and-groups)). A
  second Ctrl-C during it gives up, and leaves those transfers running.
- **Only the thread that made a group may use it:** another raises
  `&http-group-error`, `wrong-thread`. A `go` once PROC has returned raises
  `closed`, and the await of a cancelled call raises `cancelled`.
- **A group takes no producer:** `go` refuses one, `stream-in-group`.
- **Inside a Chez engine,** an expiry ends the whole group: once resumed, its
  awaits raise `cancelled`, and a new `go` raises `closed`.
- **None of it may run inside a critical section.**

## `http-parallel`

`(http-parallel SESSION SPECS KEY VALUE ...)` runs each spec, `(METHOD URL
KEY VALUE ...)`, in one group, its one key `limit`, and answers the responses
in the specs' order.

- **It checks every call before it sends any,** as a submit would check it.
- **The first call to fail raises,** as it raised, once every other is
  cancelled and its transfer has ended.

## What can still fail partway

Once calls run, each is its own: what becomes of one is its answer alone,
never raised by `go`. A submit can still refuse a call after its checks
passed: a stopped or failed engine; a file part no longer a regular file,
`part-file`; or a redirect's next request, or a retry, refused as any request
would be, `prior-knowledge-over-https`, `credentials-beside-userinfo` or
`proxy-tls-in-tls` ([Redirects and retries](redirects-and-retries.md)).
