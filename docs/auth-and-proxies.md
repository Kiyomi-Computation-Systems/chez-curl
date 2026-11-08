# Auth and proxies

How to send a server's credentials, and how to go through a proxy. Both
levels take the same keys: a request's at the low level, a session's or a
call's at the high level.

## Credentials

`credentials` names one scheme, and what it sends:

```scheme fragment
(make-curl-request "https://example.com/" 'credentials '(basic "user" "pass"))
(make-curl-request "https://example.com/" 'credentials '(digest "user" "pass"))
(make-curl-request "https://example.com/" 'credentials '(bearer "token"))
(http-get session "https://example.com/" 'credentials '(basic "user" "pass"))
```

- **Basic and Bearer** go out on the first request.
- **Digest** sends a bare request first, and its credentials once the server
  answers with a challenge: a second request inside the transfer. So a
  request with a body, a `post` or a `put`, to a server that never
  challenges is sent twice, the first time with no body. Which Digest
  algorithms work [varies by libcurl](libcurl-versions.md#auth).
- **Each string is sent as UTF-8.** libcurl 8.23.0 percent-encodes a Digest
  user name's bytes outside ASCII and still hashes the raw ones, so a server
  refuses a non-ASCII Digest user name from it.
- **A wrong password is no failure:** you get the server's 401.
- **No length is checked.** libcurl sends what fits: a 1 MiB Basic password
  or Bearer token fails before anything is sent, with libcurl's own code,
  which [varies by libcurl](libcurl-versions.md#auth).

**Refused when you make the request,** `&curl-request-error`:

| Reason | What |
|---|---|
| `credentials-bytes` | a control character, U+0000 to U+001F or U+007F, in any string, which libcurl would write into the header as it is; or a `:` in a Basic user name, where Basic ends the user |
| `credentials-empty` | an empty token, or a user and a password both empty |
| `credentials-beside-authorization` | credentials beside your own `Authorization` header: libcurl would send one or both |
| `digest-with-stream` | Digest beside a streamed body or response: its second request would break the stream. Basic and Bearer stream fine |

**Refused when you submit:** credentials beside a URL that holds a user or a
password, `credentials-beside-userinfo`. Give them one way. Whether an empty
`@` counts [varies by libcurl](libcurl-versions.md#auth).

A refusal never holds your secret, only its scheme and part, such as
`(basic password)`.

**At the high level,** a session's and a call's `credentials` are the same
key: a call's replaces its session's, `#f` too. A redirect keeps them within
one origin, and drops them for another, as it drops `Authorization`. A
redirect within the origin to a URL holding a user or a password fails the
call, `credentials-beside-userinfo`.

**A transfer makes at most 30 requests inside itself,** an auth round's, a
stale Digest challenge's and a 417's resend among them. So a server that
answers 417, or a stale challenge, for ever ends it with 47; or sooner with
`header-limit`, when those answers' heads together pass the cap on response
headers ([Errors](errors.md)). libcurl's resend of a request a dead
connection lost does not count.

## Proxies

`proxy` names how a request reaches the server:

- **`environment`, the default,** goes through the proxy a variable names
  (below), or direct when none does.
- **`#f`** goes direct, whatever the variables say.
- **A URL,** `http://` or `https://`, takes every transfer through that proxy.
  `no_proxy`, `NO_PROXY` and the proxy variables send nothing around it.

```scheme fragment
(make-curl-request "https://example.com/" 'proxy "http://proxy.example:3128")
(make-curl-request "https://example.com/"
                   'proxy "https://user:pass@proxy.example"
                   'proxy-ca-file "/etc/ssl/proxy-ca.pem")
```

- **A proxy URL's credentials are its user and password,** percent-decoded,
  sent by Basic on the first request.
- **An `http://` request goes to the proxy whole;** an `https://` one goes
  through a `CONNECT` tunnel, the proxy seeing only the `CONNECT`.
- **A proxy URL with no port gets its scheme's,** 80 or 443, on every libcurl.
- **An `https://` proxy's TLS is its own.** `proxy-ca-file` is its only CA
  file, else libcurl's own store, and `proxy-verify`, `#t` by default, checks
  its certificate and name. A request's `ca-file` and `verify` never reach the
  proxy, nor these the server. A `proxy-ca-file` is refused against the
  environment as a `ca-file` is ([TLS and the environment](tls-and-environment.md)).

**Refused when you submit,** naming the field, never the URL, which can hold
a password:

| Reason | What |
|---|---|
| `proxy-url` | a URL that does not parse, or whose user or password holds a `%` not followed by two hex digits |
| `proxy-scheme` | a scheme but `http` or `https`, `socks5://` among them |
| `proxy-url-parts` | a path, a query or a fragment |
| `credentials-bytes` | a user or password that decodes to a control byte, or to bytes that are not UTF-8, or a user that decodes to a `:` |
| `credentials-empty` | a user and a password both empty |
| `proxy-tls-without-https-proxy` | a `proxy-ca-file`, or `proxy-verify #f`, beside any proxy but an `https://` URL |
| `prior-knowledge-through-proxy` | `http/2-prior-knowledge`, which libcurl ignores through a proxy |
| `https-proxy-unsupported` | an `https://` proxy on a libcurl built without HTTPS-proxy support, which would write the whole URL into its error buffer |
| `proxy-tls-in-tls` | an `https://` URL through an `https://` proxy where TLS inside TLS stalls until the timeout: Ubuntu's 8.5.0 with GnuTLS always, and 7.85.0 unless the request asks `http/1.1` |

**Refused when you make the request:** a `Proxy-Authorization` header, in any
case, `proxy-authorization-header`: inside a tunnel libcurl would send it to
the server. A proxy's credentials go in its URL.

**A refused `CONNECT`** fails the transfer with libcurl's code, which
[varies by libcurl](libcurl-versions.md#proxies).
`curl-transfer-error-connect-code` holds the proxy's status, 403, 407, 502
and the like, on every version. A retry policy treats it as a response with
that status, so the default one never retries a 403 or a 407.

**Tunnels before libcurl 8.19.0** are never shared: each `https://` request
through a proxy URL opens a connection of its own, and with credentials
closes it as it ends, so no later request rides a tunnel someone's
credentials opened. Credentials in a proxy URL there also stop HTTP/2
multiplexing on that engine, for good, from its first such request: no two
requests share a connection at once. A request that starts after another
ended can still reuse its connection.

**At the high level,** sessions and calls take `proxy`, `proxy-ca-file` and
`proxy-verify`. A call's replaces its session's, and a call that names its
own `proxy` drops the session's `proxy-ca-file` and `proxy-verify`. Every
request a redirect makes goes through the same proxy, another server's too,
with the proxy's credentials.

## The environment's proxy

With `proxy environment`, libcurl reads the variables for each transfer:
`http_proxy`, `https_proxy`, `HTTPS_PROXY`, `all_proxy` and `ALL_PROXY` name
the proxy, and `no_proxy` and `NO_PROXY` list hosts that go direct.
`HTTP_PROXY`, upper case, is ignored.

- **Its user and password are libcurl's to read;** chez-curl checks none of
  it. One that decodes to a control byte, `%00` to `%1F`, sends some
  libcurls around the proxy, direct ([What varies](libcurl-versions.md#proxies)).
  Put a proxy's credentials in a request's proxy URL, which is checked.
- **Its `https://` proxy is checked against libcurl's own store:** on Guix,
  the one `SSL_CERT_FILE` names. `proxy-ca-file` and `proxy-verify` belong to
  a proxy URL.
- **Through a proxy that does not tunnel,** an `http://` request's, libcurl
  ignores prior knowledge and sends HTTP/1.1 to the proxy. Beside a proxy URL
  that is refused when you submit; beside the environment's, nothing knows a
  proxy is there.
- **No submit knows the environment's proxy,** so a stalling TLS-inside-TLS
  proxy a variable names is not refused.

## The hatch

`(curl unsupported)` refuses every libcurl option the keys on this page set,
and their twins: [The hatch](hatch.md) lists them, and the few it leaves.
