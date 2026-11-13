# chez-curl

An HTTP client for [Chez Scheme](https://cisco.github.io/ChezScheme/), built
on [libcurl](https://curl.se/libcurl/).

It has two levels, and a program may use either, or both:

- **`(http-client)`, the high level.** A session, and a call per request:
  `http-get`, `http-post` and the rest. It follows redirects by its own rules,
  retries by a policy you give it, keeps cookies, and streams both ways.
- **`(curl)`, the low level.** A request is data. An engine runs it on a
  thread of its own and hands you a token, which gives you the response.
  `(http-client)` is built on it.

## Ideas to keep in mind

- **A status is data.** A 404 or a 503 is an answer, not an error. A call
  raises when it was refused, when its transfer failed, when an answer passed
  a limit you set, and when it met a redirect it will not follow
  ([Errors](errors.md)).
- **One engine thread runs many requests.** To make many at once you need no
  thread per request: a group, or many tokens, on your one thread.
- **What you pass is checked before it is sent,** and a refusal names the
  field and the reason, never your password or your cookie.
- **Close what you open.** A session, an engine and a cookie jar hold native
  objects: `call-with-http-session` closes its session for you.
- **libcurl's version shows through** in a few places, each one listed.

## The pages

- [Quick start](quickstart.md): from a clone to a first request.
- [The high level](high-level.md): sessions, verbs, responses, bodies,
  forms, multipart, params, timeouts and limits.
- [Headers and JSON](headers-and-json.md): setting a request's headers,
  reading a response's, and calling a JSON API.
- [Redirects and retries](redirects-and-retries.md): what a call follows, and
  what a policy retries.
- [Auth and proxies](auth-and-proxies.md): credentials, and proxies by URL
  and by the environment.
- [Cookies](cookies.md): a session's cookies, and jars.
- [Choosing the HTTP version](http-version.md): HTTP/1.1, HTTP/2, and prior
  knowledge.
- [Streams](streams.md): reading a response, and sending a body, as each
  goes.
- [Groups](groups.md): many calls at once on one thread.
- [The low level](low-level.md): engines, requests, tokens, mailboxes, and
  URLs.
- [Errors](errors.md): each condition type and reason, and how to handle one.
- [TLS and the environment](tls-and-environment.md): CA files, the variables
  read, and finding libcurl.
- [What varies by libcurl](libcurl-versions.md): every behaviour that differs
  by version, as measured.
- [The hatch](hatch.md): `(curl unsupported)`, for libcurl options chez-curl
  does not wrap.
- [Reference](reference.md): every export, its type, what it raises.

## The examples

[`examples/`](../examples) holds eleven small programs to copy from. Each
calls the test server, `tests/origin.mjs`, a Node program in this
repository, so start it first, in a terminal of its own, and leave it
running. It prints one line of addresses, a new port at each start: an
example takes the one after `"http":`, not `raw`'s or `h2c`'s, which speak
other protocols. Run an example from the repository's root, with its base URL:
`http://`, that address, and no trailing `/`, since each example adds its
own paths. `json-api.sps` alone
needs jsonparse, a submodule ([Headers and JSON](headers-and-json.md#a-json-api)),
and runs as `scheme --libdirs src:build/scheme-libs --program examples/json-api.sps URL`.

```sh
node tests/origin.mjs        # first: prints {"node":...,"http":"127.0.0.1:PORT",...}; Ctrl-D ends it
scheme --libdirs src --program examples/quick-start.sps http://127.0.0.1:PORT
```

| Example | What it shows |
|---|---|
| [`quick-start.sps`](../examples/quick-start.sps) | one `http-get` |
| [`form-and-params.sps`](../examples/form-and-params.sps) | params on a query, and a form as a body |
| [`json-api.sps`](../examples/json-api.sps) | headers on a session and a call, and a JSON API, with jsonparse; it alone needs `make deps`, and `src:build/scheme-libs` as its library path |
| [`multipart.sps`](../examples/multipart.sps) | a multipart body of a string, bytes and a file |
| [`session-retries.sps`](../examples/session-retries.sps) | a session's defaults, a redirect, and a retry policy |
| [`stream-download.sps`](../examples/stream-download.sps) | a response read from a port as it arrives |
| [`stream-upload.sps`](../examples/stream-upload.sps) | at the low level, a body put a piece at a time |
| [`group.sps`](../examples/group.sps) | `http-parallel`, and a request group |
| [`cookie-jar.sps`](../examples/cookie-jar.sps) | at the low level, a cookie jar: kept, sent, read out, loaded |
| [`errors.sps`](../examples/errors.sps) | a status as data; a timeout, a body too large and a refused request |
| [`engine-and-tokens.sps`](../examples/engine-and-tokens.sps) | at the low level, an engine, tokens and a mailbox |

`make test` runs every example twice against one test server, and holds
each run's output to [`examples/expected/`](../examples/expected).
