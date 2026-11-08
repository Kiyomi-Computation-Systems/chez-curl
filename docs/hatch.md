# The hatch: `(curl unsupported)`

`(curl unsupported)` attaches a libcurl option to a request by its name, for
anything the request's own keys do not cover:

```scheme fragment
(import (rnrs) (curl) (curl unsupported))

(curl-request-with-options
 (make-curl-request "https://example.com/")
 '(("LOW_SPEED_LIMIT" . 1000) ("LOW_SPEED_TIME" . 30)))
```

It answers a new request, with the options after any it carried.
`curl-request-with` keeps them. The high level takes no hatch options.

## What it is

- **It is unsupported.** No promise it stays the same. An option is set last,
  after every option chez-curl sets, so one can change what chez-curl tests.
- **A name is libcurl's,** without `CURLOPT_`, in any case.
- **A value is plain data,** as the option's type says: an exact integer for a
  long, an enumerated or an `off_t` option, a string, a list of strings, or a
  bytevector for a blob, which libcurl copies. A value of the wrong shape or
  range is an assertion violation.
- **It is checked when you attach it,** and the request keeps its own copy, so
  changing your string later changes nothing. libcurl still judges the value
  as the transfer is set up: one it refuses fails the transfer,
  `setopt-failed`, naming the option.
- **`VERBOSE` and `NOPROGRESS` write to your program's stderr.** `VERBOSE`
  writes every header it sends, a password in one too.
- **A path is opened as given,** unchecked: `/dev/stdin` names your program's
  stdin.

## What it refuses

A refusal is `&curl-request-error`, field `options`, naming the option:

| Reason | What |
|---|---|
| `unknown-option` | a name the loaded libcurl does not know |
| `unsupported-type` | an option that takes a pointer, an object or a callback |
| `embedded-nul`, `line-break` | a string, or a string of a list, holding NUL, or CR or LF |
| `repeated-option` | an option the request carries already, by any of its names |
| `owned-option` | an option chez-curl owns, compared by its id, so an alias too |

chez-curl owns:

- **every option it sets,** for every transfer or for a request's key: the
  URL, the method, the body, the headers, the timeouts, the TLS checks, the
  proxy, the credentials, the cookie jar, the HTTP version, the callbacks,
  and `MAXREDIRS`, pinned at 30;
- **each one's twin,** an option that does the same job another way:
  `TIMEOUT`, `MAXFILESIZE`, `POSTFIELDS`, `PORT`, `USERPWD`, `NETRC`, `HSTS`,
  `PRE_PROXY`, `PROXYHEADER`, every `PROXY_` TLS option, and the rest;
- **two that would undo its own work:** `MIME_OPTIONS`, which changes how a
  multipart part's name and filename are escaped, and
  `SUPPRESS_CONNECT_HEADERS`, which hides a proxy's `CONNECT` answer from the
  cap on response headers;
- **a few that reach past your request:** `COOKIEFILE`, `COOKIEJAR` and
  `RESUME_FROM`, which can read stdin or write stdout; `COOKIELIST`, which
  reaches a jar every holder shares; `RESOLVE`, which steers later requests;
  `DOH_URL`, which skips the `proxy` key; `SSLENGINE_DEFAULT`, which sets
  OpenSSL's default for the whole process; and `CONNECT_ONLY`, which sends no
  request.

By topic, it refuses, besides:

- **credentials:** `HTTPAUTH`, `USERNAME`, `PASSWORD`, `XOAUTH2_BEARER`,
  `AWS_SIGV4`, `USERPWD` and `NETRC`;
- **proxies:** `PROXY`, `NOPROXY`, `PROXYAUTH`, `PROXYUSERPWD`,
  `PROXYUSERNAME`, `PROXYPASSWORD`, `HTTPPROXYTUNNEL`, `HAPROXYPROTOCOL`,
  `HAPROXY_CLIENT_IP`, `FORBID_REUSE`, `PRE_PROXY`, `PROXYPORT`, `PROXYTYPE`,
  `PROXYHEADER`, `HEADEROPT`, `SUPPRESS_CONNECT_HEADERS` and every `PROXY_`
  TLS option;
- **cookies:** `SHARE`, `COOKIE`, `COOKIEFILE`, `COOKIEJAR`, `COOKIELIST` and
  `COOKIESESSION`: `COOKIELIST` would clear or fill the jar of every transfer
  that holds it;
- **the HTTP version:** `HTTP_VERSION`, `SSL_ENABLE_ALPN`, `ALTSVC` and
  `ALTSVC_CTRL`, which can change the version or the server a request
  reaches;
- **the response:** `HEADERFUNCTION`, `HEADERDATA`, `WRITEFUNCTION`,
  `HEADER` and the other callbacks.

On 7.85.0, which does not know `HAPROXY_CLIENT_IP` or `QUICK_EXIT`, those
are refused `unknown-option`.

## What stays the hatch's

These were measured, and stay attachable:

- `FAILONERROR`, which makes a wrong password's 401 a failure, code 22;
  `AUTOREFERER`, `KEEP_SENDING_ON_ERROR`, `UNRESTRICTED_AUTH`,
  `DISALLOW_USERNAME_IN_URL`, `LOGIN_OPTIONS`, `SASL_AUTHZID`, `SASL_IR`,
  `SERVICE_NAME` and `NETRC_FILE`, each changing nothing the `credentials` key
  sends;
- `PIPEWAIT`, `HTTP09_ALLOWED` and `HTTP200ALIASES`, whose alias status line
  the cap counts as a header line;
- `HTTP_TRANSFER_DECODING`: at 0 a chunked body's trailers stay in the body,
  where `body-limit` bounds them, and none is kept as a header;
- `CONNECT_TO`, which moves the host and port a request reaches, a proxy's
  `CONNECT` among them; a jar's cookies still follow the URL's host;
- `HSTS_CTRL`, `PROXY_SERVICE_NAME`, `SOCKS5_AUTH` and `EXPECT_100_TIMEOUT_MS`.

A blob option's answer can [vary by TLS library](libcurl-versions.md#the-hatch).
