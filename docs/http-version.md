# Choosing the HTTP version

A request's `http-version` asks for one. Sessions and calls take it too: a
call's replaces its session's, and a redirect keeps it.

```scheme fragment
(make-curl-request "https://example.com/" 'http-version 'http/2)
(http-get session "http://127.0.0.1:8080/" 'http-version 'http/2-prior-knowledge)
```

- **`#f`, the default,** lets libcurl choose: HTTP/2 over `https://` when the
  server offers it, else HTTP/1.1.
- **`http/1.1`** asks for HTTP/1.1 alone. A server that speaks only HTTP/2
  refuses it.
- **`http/2`** gets HTTP/2 over `https://` when the server offers it, agreed in
  the TLS handshake, else HTTP/1.1. Over `http://` it sends HTTP/1.1, with no
  `Upgrade`.
- **`http/2-prior-knowledge`** speaks HTTP/2 from the first byte, to an
  `http://` server you know speaks it.
  - With an `https://` URL it is refused when you submit,
    `prior-knowledge-over-https`: use `http/2` there. A redirect to
    `https://` fails the call the same way.
  - An HTTP/1.1 server fails it, with a code that
    [varies by libcurl](libcurl-versions.md#the-http-version), and on timing.
  - Beside a proxy URL it is refused when you submit,
    `prior-knowledge-through-proxy`. Through the environment's proxy, when
    the request does not tunnel, libcurl ignores it and sends HTTP/1.1 to the
    proxy ([Auth and proxies](auth-and-proxies.md)).

`curl-response-http-version` and `http-response-http-version` tell which
version answered: `http/1.0`, `http/1.1`, `http/2` or `http/3`.

## Connections

- **Requests started together open a connection each.** chez-curl never sets
  libcurl's `PIPEWAIT`, so they do not wait to share one HTTP/2 connection. A
  request started later reuses an open one.
- **Two prior-knowledge requests batched together** share one connection on
  libcurl 7.85.0, and open two from 8.5.0.
- **On libcurl 8.7.0 and 8.7.1, the Mac's,** the engine turns multiplexing
  off, so a request started while another runs opens its own connection.
  There one failing or paused HTTP/2 stream would fail the others sharing its
  connection.
- **A reused connection keeps its version.** Over `http://`, a request with
  `#f` or `http/2` to a server the engine already holds an HTTP/2 connection
  to, made by prior knowledge, reuses it, and reads HTTP/2.

## The hatch

`(curl unsupported)` refuses the options that set or change the version:
[The hatch](hatch.md) lists them, and the few it leaves.
