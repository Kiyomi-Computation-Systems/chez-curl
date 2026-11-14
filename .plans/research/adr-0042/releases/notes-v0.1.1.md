A documentation release: the libraries are 0.1.0's, unchanged.

### Changed

- **Running the examples.** Each example's head comment, README.org, the
  [docs index](docs/README.md#the-examples), the [quick start](docs/quickstart.md)
  and each page with an example say to start the test server first, with
  `node tests/origin.mjs`, and to give an example the address after `"http":` in
  the line it prints: `raw`'s and `h2c`'s speak other protocols. `json-api.sps`
  alone needs `make deps`, and `src:build/scheme-libs` as its library path.
- **Node.js** runs only the test server, which the tests and the examples call:
  a program using chez-curl never needs it. The tests also need `openssl` and GNU
  `timeout`.
- **Installing** clones the release's tag, in README.org and the quick start,
  not `main`.
- README.org's mentions of libcurl link [its site](https://curl.se/libcurl/), and
  its Status names no version.
