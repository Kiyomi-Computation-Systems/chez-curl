# Quick start

From a clone to a first request.

## What you need

A threaded Chez Scheme and a libcurl built with TLS, at the versions
[README.org's Requirements](../README.org) name. Node.js is for the tests and
the examples' test server alone.

## Get it

```sh
git clone --branch v0.1.1 https://github.com/Kiyomi-Computation-Systems/chez-curl.git
```

There is no build step. chez-curl is Scheme source that loads libcurl when
your program runs. `src/` holds its three libraries: `(http-client)`,
`(curl)` and `(curl unsupported)`.

## Put it on the library path

Put `src` on Chez's library path, and nothing else:

```sh
scheme --libdirs /path/to/chez-curl/src --program app.sps
```

or set it once:

```sh
export CHEZSCHEMELIBDIRS=/path/to/chez-curl/src
```

Homebrew installs Chez as `chez`: use that name in place of `scheme`.

## Point it at a libcurl, when you need to

chez-curl finds the system's libcurl itself: Guix's profile on Guix, the
usual library directories elsewhere on Linux, and Apple's on macOS. To load
another, set `CHEZ_CURL_LIBCURL` to its absolute path. Check what it found:

```sh
echo '(import (curl)) (display (libcurl-info-version (loaded-libcurl)))' | scheme -q --libdirs src
```

When libcurl is refused, at that load, the error says why: see
[TLS and the environment](tls-and-environment.md).

## A first call

```scheme example=examples/quick-start.sps
(import (rnrs) (http-client))

(define base (cadr (command-line)))

(call-with-http-session
 (lambda (session)
   (let ((response (http-get session (string-append base "/status/200"))))
     (display (http-response-status response))
     (newline)
     (display (http-response-text response)))))
```

- `call-with-http-session` makes a session, hands it to your procedure, and
  closes it after.
- `http-get` blocks until the response comes, and answers it whatever the
  status.

Run it against the test server. In one terminal, from the clone's root:

```sh
node tests/origin.mjs
```

It prints one line, such as `{"node":...,"http":"127.0.0.1:40001",...}`, and
serves until its input ends: Ctrl-D, or Ctrl-C. Leave it running. The address
after `"http":` is the one an example takes; `raw` and `h2c` are other faces,
which speak other protocols. The system picks each port, a new one at each
start, so use the one yours prints. The example takes its base URL,
`http://127.0.0.1:40001` here, with no trailing `/`, since it adds its own
path. In another terminal:

```sh
scheme --libdirs src --program examples/quick-start.sps http://127.0.0.1:40001
```

```text output=examples/expected/quick-start.out
200
status 200
```

Against any server, the URL is yours:

```scheme fragment
(import (rnrs) (http-client))

(call-with-http-session
 (lambda (session)
   (display (http-response-status (http-get session "https://example.com/")))))
```

## Running the tests

The suites need two submodules, a pinned SRFI library and jsonparse, which
one example uses, and Node.js, `openssl` and GNU `timeout`:

```sh
git submodule update --init --recursive
make test
```

`make help` lists every target. On a Guix host, `scripts/guix-env make test`
runs them in a pinned container.

## Next

- [The high level](high-level.md): sessions, verbs, bodies, forms, multipart.
- [Errors](errors.md): what a call raises, and how to catch it.
- [The docs' index](README.md): every page, and the examples.
