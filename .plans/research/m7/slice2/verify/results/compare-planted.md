
### The hatch, on main's `src/` and on the prototype (`r` lines)

A cell: `attached`, or the refusal's reason, or `condition` for an assertion violation (the option takes a string).

| case | tree | X |
|---|---|---|
| USERNAME | main | refused owned-option |
| PASSWORD | main | refused owned-option |
| HTTPAUTH | main | attached |
| HTTPAUTH-beside-stream-buffer | main | refused stream-with-rounds |
| HTTPAUTH-beside-body-stream | main | attached |
| PROXYAUTH-beside-stream-buffer | main | refused stream-with-rounds |
| XOAUTH2_BEARER | main | attached |
| AWS_SIGV4 | main | attached |
| XOAUTH2_BEARER-CR | main | refused line-break |
| XOAUTH2_BEARER-LF | main | refused line-break |
| XOAUTH2_BEARER-NUL | main | refused embedded-nul |
| XOAUTH2_BEARER-bytes | main | condition: takes a string |
| XOAUTH2_BEARER-bytes-NUL | main | condition: takes a string |
| USERNAME-bytes | main | refused owned-option |
| LOGIN_OPTIONS | main | attached |
| DISALLOW_USERNAME_IN_URL | main | attached |
| UNRESTRICTED_AUTH | main | attached |
| NETRC_FILE | main | attached |
| NETRC | main | refused owned-option |
| SASL_AUTHZID | main | attached |
| SASL_IR | main | attached |
| SERVICE_NAME | main | attached |
| KEEP_SENDING_ON_ERROR | main | attached |
| FAILONERROR | main | attached |
| USERPWD | main | refused owned-option |
| PROXYAUTH | main | attached |
| USERNAME | prototype | attached |
| PASSWORD | prototype | attached |
| HTTPAUTH | prototype | attached |
| HTTPAUTH-beside-stream-buffer | prototype | attached |
| HTTPAUTH-beside-body-stream | prototype | attached |
| PROXYAUTH-beside-stream-buffer | prototype | refused stream-with-rounds |
| XOAUTH2_BEARER | prototype | attached |
| AWS_SIGV4 | prototype | attached |
| XOAUTH2_BEARER-CR | prototype | refused line-break |
| XOAUTH2_BEARER-LF | prototype | refused line-break |
| XOAUTH2_BEARER-NUL | prototype | refused embedded-nul |
| XOAUTH2_BEARER-bytes | prototype | attached |
| XOAUTH2_BEARER-bytes-NUL | prototype | refused embedded-nul |
| USERNAME-bytes | prototype | attached |
| LOGIN_OPTIONS | prototype | attached |
| DISALLOW_USERNAME_IN_URL | prototype | attached |
| UNRESTRICTED_AUTH | prototype | attached |
| NETRC_FILE | prototype | attached |
| NETRC | prototype | refused owned-option |
| SASL_AUTHZID | prototype | attached |
| SASL_IR | prototype | attached |
| SERVICE_NAME | prototype | attached |
| KEEP_SENDING_ON_ERROR | prototype | attached |
| FAILONERROR | prototype | attached |
| USERPWD | prototype | refused owned-option |
| PROXYAUTH | prototype | attached |

### Item 1: each scheme, each case (`i1` lines)

A cell: each request at the stand-in, in order: its `Authorization` scheme (– none), the stand-in's verdict (✓ valid, ✗ refused), its status, `{N}` the body bytes it read; then ⇒ the final status, or the code. Every case ran on a fresh engine.

| scheme | case | method | face | X |
|---|---|---|---|---|
| basic | right | get | http, https, h2 | Basic✓/200 ⇒ 200 |
| basic | right | post | http, https, h2 | Basic✓/200{1024} ⇒ 200 |
| basic | wrong | get | http, https, h2 | Basic✗/401 ⇒ 401 |
| basic | wrong | post | http, https, h2 | Basic✗/401{1024} ⇒ 401 |
| basic | other | get | http, https, h2 | Basic✓/401 ⇒ 401 |
| basic | other | post | http, https, h2 | Basic✓/401{1024} ⇒ 401 |
| basic | none | get | http, https, h2 | Basic✓/401 ⇒ 401 |
| basic | none | post | http, https, h2 | Basic✓/401{1024} ⇒ 401 |
| basic | open | get | http, https, h2 | Basic✓/200 ⇒ 200 |
| basic | open | post | http, https, h2 | Basic✓/200{1024} ⇒ 200 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-512-256-auth, digest-SHA-512-256-none | right | get | http, https, h2 | –/401 → Digest✓/200 ⇒ 200 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-512-256-auth, digest-SHA-512-256-none | right | post | http, https, h2 | –/401 → Digest✓/200{1024} ⇒ 200 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-512-256-auth, digest-SHA-512-256-none | wrong | get | http, https, h2 | –/401 → Digest✗/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-512-256-auth, digest-SHA-512-256-none | wrong | post | http, https, h2 | –/401 → Digest✗/401{1024} ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | other | get | http, https, h2 | –/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | other | post | http, https, h2 | –/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | none | get | http, https, h2 | –/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | none | post | http, https, h2 | –/401 ⇒ 401 |
| digest-MD5-auth, digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | open | get | http, https, h2 | –/200 ⇒ 200 |
| digest-MD5-auth | open | post | http | **–/200 → –/200{1024} ⇒ 200 / –/200 → –/200{1024} ⇒ 500** |
| digest-MD5-none, digest-MD5-sess-auth, digest-MD5-sess-none, digest-SHA-256-auth, digest-SHA-256-none, digest-SHA-256-sess-auth, digest-SHA-256-sess-none, digest-SHA-512-256-auth, digest-SHA-512-256-none | open | post | http, https, h2 | –/200 → –/200{1024} ⇒ 200 |
| digest-MD5-sess-none, digest-SHA-256-sess-none | right | get | http, https, h2 | –/401 ⇒ 401 |
| digest-MD5-sess-none, digest-SHA-256-sess-none | right | post | http, https, h2 | –/401 ⇒ 401 |
| digest-MD5-sess-none, digest-SHA-256-sess-none | wrong | get | http, https, h2 | –/401 ⇒ 401 |
| digest-MD5-sess-none, digest-SHA-256-sess-none | wrong | post | http, https, h2 | –/401 ⇒ 401 |
| bearer | right | get | http, https, h2 | Bearer✓/200 ⇒ 200 |
| bearer | right | post | http, https, h2 | Bearer✓/200{1024} ⇒ 200 |
| bearer | wrong | get | http, https, h2 | Bearer✗/401 ⇒ 401 |
| bearer | wrong | post | http, https, h2 | Bearer✗/401{1024} ⇒ 401 |
| bearer | other | get | http, https, h2 | Bearer✓/401 ⇒ 401 |
| bearer | other | post | http, https, h2 | Bearer✓/401{1024} ⇒ 401 |
| bearer | none | get | http, https, h2 | Bearer✓/401 ⇒ 401 |
| bearer | none | post | http, https, h2 | Bearer✓/401{1024} ⇒ 401 |
| bearer | open | get | http, https, h2 | Bearer✓/200 ⇒ 200 |
| bearer | open | post | http, https, h2 | Bearer✓/200{1024} ⇒ 200 |
| digest-MD5-auth | open | post | https, h2 | –/200 → –/200{1024} ⇒ 200 |

### Item 1: the `Authorization` sent, whole (`i1`, right credentials, get)

A cell: the value of the last request's `Authorization`, as the stand-in received it; for Digest, the nonce, cnonce, response and uri replaced by N, CN, R and U (each verified by the stand-in, `ok` in item 1's table).

| scheme | face | X |
|---|---|---|
| basic | http, https, h2 | `Basic dXNlcjpwYXNz` |
| digest-MD5-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5` |
| digest-MD5-none | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=MD5` |
| digest-MD5-sess-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=MD5-sess` |
| digest-MD5-sess-none | http, https, h2 | `none` |
| digest-SHA-256-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256` |
| digest-SHA-256-none | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-256` |
| digest-SHA-256-sess-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-256-sess` |
| digest-SHA-256-sess-none | http, https, h2 | `none` |
| digest-SHA-512-256-auth | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, cnonce=CN, nc=00000001, qop=auth, response=R, opaque="opq5ccb", algorithm=SHA-512-256` |
| digest-SHA-512-256-none | http, https, h2 | `Digest username="user", realm="chez-curl-test", nonce=N, uri=U, response=R, opaque="opq5ccb", algorithm=SHA-512-256` |
| bearer | http, https, h2 | `Bearer tok123` |

### Item 5 (a): Digest's second request and the first's connection (from `i1`, right credentials)

A cell: for each Digest variant with a second request, `same` when it rode the first's connection, else `other`, counted: 8 of the 10 variants per face and method send one (`-sess` without `qop` does not).

| method | face | X |
|---|---|---|
| get | http, https, h2 | same ×8 |
| post | http, https, h2 | same ×8 |

### Item 2: streams (`i2` lines)

A cell: the outcome; the requests at the stand-in, `{whole}` or `{part}` of the 256 KiB body it read (`closed` when the client closed first); for a streamed body the producer's last put (`end`: every piece taken, then the end; `done`: the transfer had ended; `#f`: its 3 s bound passed), for a streamed response the head the token published and the body bytes read. How much of a body cut short the stand-in read races; the counts are in the next table.

| scheme | case | kind | when | face | X |
|---|---|---|---|---|---|
| basic | right | sized | normal | http, h2 | 200; Basic✓/200{whole}; last put end |
| basic | right | chunked | normal | http, h2 | 200; Basic✓/200{whole}; last put end |
| basic | right | response | normal | http, h2 | 200; Basic✓/200; head 200, read 262144 |
| bearer | right | sized | normal | http, h2 | 200; Bearer✓/200{whole}; last put end |
| bearer | right | chunked | normal | http, h2 | 200; Bearer✓/200{whole}; last put end |
| bearer | right | response | normal | http, h2 | 200; Bearer✓/200; head 200, read 262144 |
| basic | wrong | sized | early | http, h2 | 401; Basic✗/401 at head{part, closed}; last put done |
| basic | wrong | sized | mid | http, h2 | 401; Basic✗/401 mid-body{part, closed}; last put done |
| basic | wrong | sized | normal | http, h2 | 401; Basic✗/401{whole}; last put end |
| basic | wrong | chunked | early | http, h2 | 401; Basic✗/401 at head{part, closed}; last put done |
| basic | wrong | chunked | mid | http, h2 | 401; Basic✗/401 mid-body{part, closed}; last put done |
| basic | wrong | chunked | normal | http, h2 | 401; Basic✗/401{whole}; last put end |
| basic | wrong | response | normal | http, h2 | 401; Basic✗/401; head 401, read 11 |
| bearer | wrong | sized | early | http, h2 | 401; Bearer✗/401 at head{part, closed}; last put done |
| bearer | wrong | sized | mid | http, h2 | 401; Bearer✗/401 mid-body{part, closed}; last put done |
| bearer | wrong | sized | normal | http, h2 | 401; Bearer✗/401{whole}; last put end |
| bearer | wrong | chunked | early | http, h2 | 401; Bearer✗/401 at head{part, closed}; last put done |
| bearer | wrong | chunked | mid | http, h2 | 401; Bearer✗/401 mid-body{part, closed}; last put done |
| bearer | wrong | chunked | normal | http, h2 | 401; Bearer✗/401{whole}; last put end |
| bearer | wrong | response | normal | http, h2 | 401; Bearer✗/401; head 401, read 11 |
| digest | right | sized | normal | http, h2 | 200; –/401 → Digest✓/200{whole}; last put end |
| digest | right | sized | early | http, h2 | 200; –/401 at head → Digest✓/200{whole}; last put end |
| digest | wrong | sized | normal | http, h2 | 401; –/401 → Digest✗/401{whole}; last put end |
| digest | wrong | sized | early | http, h2 | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done |
| digest | right | chunked | normal | http, h2 | 200; –/401 → Digest✓/200{whole}; last put end |
| digest | right | chunked | early | http, h2 | 200; –/401 at head → Digest✓/200{whole}; last put end |
| digest | wrong | chunked | normal | http, h2 | 401; –/401 → Digest✗/401{whole}; last put end |
| digest | wrong | chunked | early | http, h2 | 401; –/401 at head → Digest✗/401 at head{part, closed}; last put done |
| digest | right | response | normal | http, h2 | 200; –/401 → Digest✓/200; head 401, read 262144 |
| digest | wrong | response | normal | http, h2 | 401; –/401 → Digest✗/401; head 401, read 11 |

### Item 2: times and bytes, run 1; run 2 (not compared)

A cell: ms from the submit to the end; for a streamed body the bytes the puts committed (`curl-token-body-count`); the bytes the stand-in read per request.

| case | X |
|---|---|
| basic | right | sized | normal | http | 9.9 ms, put 262144, got 262144; 9.3 ms, put 262144, got 262144 |
| basic | right | chunked | normal | http | 17.0 ms, put 262144, got 262144; 5.8 ms, put 262144, got 262144 |
| basic | right | response | normal | http | 2.9 ms, got 0; 7.4 ms, got 0 |
| bearer | right | sized | normal | http | 6.5 ms, put 262144, got 262144; 8.4 ms, put 262144, got 262144 |
| bearer | right | chunked | normal | http | 6.4 ms, put 262144, got 262144; 8.5 ms, put 262144, got 262144 |
| bearer | right | response | normal | http | 2.9 ms, got 0; 3.4 ms, got 0 |
| basic | right | sized | normal | h2 | 8.3 ms, put 262144, got 262144; 9.7 ms, put 262144, got 262144 |
| basic | right | chunked | normal | h2 | 7.5 ms, put 262144, got 262144; 9.8 ms, put 262144, got 262144 |
| basic | right | response | normal | h2 | 28.5 ms, got 0; 21.7 ms, got 0 |
| bearer | right | sized | normal | h2 | 13.8 ms, put 262144, got 262144; 9.3 ms, put 262144, got 262144 |
| bearer | right | chunked | normal | h2 | 8.5 ms, put 262144, got 262144; 9.2 ms, put 262144, got 262144 |
| bearer | right | response | normal | h2 | 23.5 ms, got 0; 28.9 ms, got 0 |
| basic | wrong | sized | early | http | 2.1 ms, put 114688, got 49152(closed); 2.0 ms, put 98304, got 32768(closed) |
| basic | wrong | sized | mid | http | 3.3 ms, put 163840, got 98304(closed); 2.1 ms, put 131072, got 65536(closed) |
| basic | wrong | sized | normal | http | 6.9 ms, put 262144, got 262144; 5.8 ms, put 262144, got 262144 |
| basic | wrong | chunked | early | http | 2.0 ms, put 98304, got 32768(closed); 1.5 ms, put 114688, got 49152(closed) |
| basic | wrong | chunked | mid | http | 3.2 ms, put 163840, got 98304(closed); 2.8 ms, put 180224, got 114688(closed) |
| basic | wrong | chunked | normal | http | 5.1 ms, put 262144, got 262144; 4.9 ms, put 262144, got 262144 |
| basic | wrong | response | normal | http | 0.5 ms, got 0; 1.0 ms, got 0 |
| bearer | wrong | sized | early | http | 1.6 ms, put 147456, got 81920(closed); 1.5 ms, put 114688, got 49152(closed) |
| bearer | wrong | sized | mid | http | 2.7 ms, put 180224, got 114688(closed); 3.3 ms, put 163840, got 98304(closed) |
| bearer | wrong | sized | normal | http | 4.7 ms, put 262144, got 262144; 4.8 ms, put 262144, got 262144 |
| bearer | wrong | chunked | early | http | 1.4 ms, put 114688, got 49152(closed); 1.6 ms, put 131072, got 65536(closed) |
| bearer | wrong | chunked | mid | http | 2.6 ms, put 163840, got 98304(closed); 1.6 ms, put 131072, got 65536(closed) |
| bearer | wrong | chunked | normal | http | 4.7 ms, put 262144, got 262144; 5.8 ms, put 262144, got 262144 |
| bearer | wrong | response | normal | http | 0.6 ms, got 0; 0.5 ms, got 0 |
| basic | wrong | sized | early | h2 | 3.3 ms, put 131072, got 65535(closed); 4.3 ms, put 65536, got 65535(closed) |
| basic | wrong | sized | mid | h2 | 4.7 ms, put 114688, got 65536(closed); 5.7 ms, put 245760, got 131070(closed) |
| basic | wrong | sized | normal | h2 | 7.5 ms, put 262144, got 262144; 7.5 ms, put 262144, got 262144 |
| basic | wrong | chunked | early | h2 | 3.5 ms, put 131072, got 65535(closed); 4.1 ms, put 131072, got 65535(closed) |
| basic | wrong | chunked | mid | h2 | 3.9 ms, put 163840, got 131070(closed); 5.2 ms, put 196608, got 131070(closed) |
| basic | wrong | chunked | normal | h2 | 7.1 ms, put 262144, got 262144; 6.1 ms, put 262144, got 262144 |
| basic | wrong | response | normal | h2 | 3.6 ms, got 0; 3.5 ms, got 0 |
| bearer | wrong | sized | early | h2 | 3.4 ms, put 147456, got 65535(closed); 3.7 ms, put 131072, got 65535(closed) |
| bearer | wrong | sized | mid | h2 | 5.0 ms, put 131072, got 65536(closed); 5.4 ms, put 212992, got 131070(closed) |
| bearer | wrong | sized | normal | h2 | 5.6 ms, put 262144, got 262144; 7.0 ms, put 262144, got 262144 |
| bearer | wrong | chunked | early | h2 | 3.3 ms, put 131072, got 65535(closed); 3.9 ms, put 65536, got 65535(closed) |
| bearer | wrong | chunked | mid | h2 | 5.2 ms, put 180224, got 114688(closed); 6.6 ms, put 212992, got 131070(closed) |
| bearer | wrong | chunked | normal | h2 | 7.4 ms, put 262144, got 262144; 5.9 ms, put 262144, got 262144 |
| bearer | wrong | response | normal | h2 | 3.5 ms, got 0; 3.5 ms, got 0 |
| digest | right | sized | normal | http | 7.7 ms, put 262144, got 0+262144; 7.0 ms, put 262144, got 0+262144 |
| digest | right | sized | early | http | 6.9 ms, put 262144, got 0+262144; 6.7 ms, put 262144, got 0+262144 |
| digest | wrong | sized | normal | http | 6.9 ms, put 262144, got 0+262144; 7.0 ms, put 262144, got 0+262144 |
| digest | wrong | sized | early | http | 3.1 ms, put 196608, got 0+131072(closed); 3.3 ms, put 196608, got 0+131072(closed) |
| digest | right | chunked | normal | http | 6.5 ms, put 262144, got 0+262144; 6.0 ms, put 262144, got 0+262144 |
| digest | right | chunked | early | http | 7.1 ms, put 262144, got 0+262144; 5.5 ms, put 262144, got 0+262144 |
| digest | wrong | chunked | normal | http | 6.5 ms, put 262144, got 0+262144; 7.0 ms, put 262144, got 0+262144 |
| digest | wrong | chunked | early | http | 3.0 ms, put 212992, got 0+147456(closed); 2.9 ms, put 212992, got 0+147456(closed) |
| digest | right | response | normal | http | 4.6 ms, got 0+0; 2.1 ms, got 0+0 |
| digest | wrong | response | normal | http | 3.6 ms, got 0+0; 4.4 ms, got 0+0 |
| digest | right | sized | normal | h2 | 8.8 ms, put 262144, got 0+262144; 13.3 ms, put 262144, got 0+262144 |
| digest | right | sized | early | h2 | 9.4 ms, put 262144, got 0+262144; 8.2 ms, put 262144, got 0+262144 |
| digest | wrong | sized | normal | h2 | 9.9 ms, put 262144, got 0+262144; 7.5 ms, put 262144, got 0+262144 |
| digest | wrong | sized | early | h2 | 5.2 ms, put 131072, got 0+65535(closed); 4.9 ms, put 147456, got 0+65535(closed) |
| digest | right | chunked | normal | h2 | 8.0 ms, put 262144, got 0+262144; 9.5 ms, put 262144, got 0+262144 |
| digest | right | chunked | early | h2 | 8.9 ms, put 262144, got 0+262144; 10.0 ms, put 262144, got 0+262144 |
| digest | wrong | chunked | normal | h2 | 10.3 ms, put 262144, got 0+262144; 8.9 ms, put 262144, got 0+262144 |
| digest | wrong | chunked | early | h2 | 6.0 ms, put 196608, got 0+65535(closed); 4.3 ms, put 163840, got 0+65535(closed) |
| digest | right | response | normal | h2 | 26.7 ms, got 0+0; 23.1 ms, got 0+0 |
| digest | wrong | response | normal | h2 | 3.7 ms, got 0+0; 4.5 ms, got 0+0 |

### Item 3: empty values (`i3` lines)

A cell: each request's credentials as the stand-in decoded them; then the requests in order, as in item 1; ⇒ the final status or code.

| scheme | user | pass | token | face | X |
|---|---|---|---|---|---|
| basic | empty | empty | tok | http, h2 | Basic ":"; Basic✓/200 ⇒ 200 |
| basic | user | empty | tok | http, h2 | Basic "user:"; Basic✓/200 ⇒ 200 |
| basic | empty | pass | tok | http, h2 | Basic ":pass"; Basic✓/200 ⇒ 200 |
| digest | empty | empty | tok | http, h2 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 |
| digest | user | empty | tok | http, h2 | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| digest | empty | pass | tok | http, h2 | – → Digest username=""; –/401 → Digest✓/200 ⇒ 200 |
| bearer | user | pass | empty | http | Bearer ""; Bearer✓/200 ⇒ 200 |
| bearer | user | pass | empty | h2 | –; –/401 ⇒ 401 |

### Item 4: hostile and edge bytes, `a` BYTE `b` (`i4` lines)

A cell: what the stand-in received, escaped as `\xNN` (for Digest the `username` parameter, unquoted, and any `username*`); the verdict, the stand-in's own arithmetic on the bytes set (`valid`, `refused`, or Digest's `bad(...)` list); `+header N` for a header name no request otherwise carries, a header of its own; `bare CR or LF in head`; ⇒ the final status or code; `no request reached the stand-in` when none did, and `nothing sent` when the failure's request size is 0.

| field | scheme | byte | face | X |
|---|---|---|---|---|
| user | basic | x | http, h2 | Basic "axb:pass"; valid ⇒ 200 |
| user | basic | 01 | http, h2 | Basic "a\x01b:pass"; valid ⇒ 200 |
| user | basic | tab | http, h2 | Basic "a\x09b:pass"; valid ⇒ 200 |
| user | basic | lf | http, h2 | Basic "a\x0ab:pass"; valid ⇒ 200 |
| user | basic | cr | http, h2 | Basic "a\x0db:pass"; valid ⇒ 200 |
| user | basic | 1f | http, h2 | Basic "a\x1fb:pass"; valid ⇒ 200 |
| user | basic | sp | http, h2 | Basic "a b:pass"; valid ⇒ 200 |
| user | basic | dquote | http, h2 | Basic "a"b:pass"; valid ⇒ 200 |
| user | basic | comma | http, h2 | Basic "a,b:pass"; valid ⇒ 200 |
| user | basic | colon | http, h2 | Basic "a:b:pass" (user "a" by the first colon); valid ⇒ 200 |
| user | basic | backslash | http, h2 | Basic "a\\b:pass"; valid ⇒ 200 |
| user | basic | 7f | http, h2 | Basic "a\x7fb:pass"; valid ⇒ 200 |
| user | basic | 80 | http, h2 | Basic "a\x80b:pass"; valid ⇒ 200 |
| user | basic | ff | http, h2 | Basic "a\xffb:pass"; valid ⇒ 200 |
| user | basic | latin1-u-umlaut | http, h2 | Basic "a\xfcb:pass"; valid ⇒ 200 |
| user | basic | utf8-u-umlaut | http, h2 | Basic "a\xc3\xbcb:pass"; valid ⇒ 200 |
| user | basic | crlf-header | http, h2 | Basic "a\x0d\x0aX-Injected: 1b:pass" (user "a\x0d\x0aX-Injected" by the first colon); valid ⇒ 200 |
| user | digest | x | http, h2 | – → Digest username="axb"; valid ⇒ 200 |
| user | digest | 01 | http | – → Digest username="a\x01b"; valid ⇒ 200 |
| user | digest | tab | http, h2 | – → Digest username="a\x09b"; valid ⇒ 200 |
| user | digest | lf | http | – → Digest username="a\x0ab"; valid bare CR or LF in head ⇒ 200 |
| user | digest | cr | http | – → Digest username="a\x0db"; valid bare CR or LF in head ⇒ 200 |
| user | digest | 1f | http | – → Digest username="a\x1fb"; valid ⇒ 200 |
| user | digest | sp | http, h2 | – → Digest username="a b"; valid ⇒ 200 |
| user | digest | dquote | http, h2 | – → Digest username="a"b"; valid ⇒ 200 |
| user | digest | comma | http, h2 | – → Digest username="a,b"; valid ⇒ 200 |
| user | digest | colon | http, h2 | – → Digest username="a:b"; valid ⇒ 200 |
| user | digest | backslash | http, h2 | – → Digest username="a\\b"; valid ⇒ 200 |
| user | digest | 7f | http | – → Digest username="a\x7fb"; valid ⇒ 200 |
| user | digest | 80 | http, h2 | – → Digest username="a\x80b"; valid ⇒ 200 |
| user | digest | ff | http, h2 | – → Digest username="a\xffb"; valid ⇒ 200 |
| user | digest | latin1-u-umlaut | http, h2 | – → Digest username="a\xfcb"; valid ⇒ 200 |
| user | digest | utf8-u-umlaut | http, h2 | – → Digest username="a\xc3\xbcb"; valid ⇒ 200 |
| user | digest | crlf-header | http, h2 | – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) +header x-injected ⇒ 401 |
| pass | basic | x | http, h2 | Basic "user:axb"; valid ⇒ 200 |
| pass | basic | 01 | http, h2 | Basic "user:a\x01b"; valid ⇒ 200 |
| pass | basic | tab | http, h2 | Basic "user:a\x09b"; valid ⇒ 200 |
| pass | basic | lf | http, h2 | Basic "user:a\x0ab"; valid ⇒ 200 |
| pass | basic | cr | http, h2 | Basic "user:a\x0db"; valid ⇒ 200 |
| pass | basic | 1f | http, h2 | Basic "user:a\x1fb"; valid ⇒ 200 |
| pass | basic | sp | http, h2 | Basic "user:a b"; valid ⇒ 200 |
| pass | basic | dquote | http, h2 | Basic "user:a"b"; valid ⇒ 200 |
| pass | basic | comma | http, h2 | Basic "user:a,b"; valid ⇒ 200 |
| pass | basic | colon | http, h2 | Basic "user:a:b" (user "user" by the first colon); valid ⇒ 200 |
| pass | basic | backslash | http, h2 | Basic "user:a\\b"; valid ⇒ 200 |
| pass | basic | 7f | http, h2 | Basic "user:a\x7fb"; valid ⇒ 200 |
| pass | basic | 80 | http, h2 | Basic "user:a\x80b"; valid ⇒ 200 |
| pass | basic | ff | http, h2 | Basic "user:a\xffb"; valid ⇒ 200 |
| pass | basic | latin1-u-umlaut | http, h2 | Basic "user:a\xfcb"; valid ⇒ 200 |
| pass | basic | utf8-u-umlaut | http, h2 | Basic "user:a\xc3\xbcb"; valid ⇒ 200 |
| pass | basic | crlf-header | http, h2 | Basic "user:a\x0d\x0aX-Injected: 1b" (user "user" by the first colon); valid ⇒ 200 |
| pass | digest | x | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | 01 | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | tab | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | lf | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | cr | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | 1f | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | sp | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | dquote | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | comma | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | colon | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | backslash | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | 7f | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | 80 | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | ff | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | latin1-u-umlaut | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | utf8-u-umlaut | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| pass | digest | crlf-header | http, h2 | – → Digest username="user"; valid ⇒ 200 |
| token | bearer | x | http, h2 | Bearer "axb"; valid ⇒ 200 |
| token | bearer | 01 | http | Bearer "a\x01b"; valid ⇒ 200 |
| token | bearer | tab | http, h2 | Bearer "a\x09b"; valid ⇒ 200 |
| token | bearer | lf | http | Bearer "a\x0ab"; valid bare CR or LF in head ⇒ 200 |
| token | bearer | cr | http | Bearer "a\x0db"; valid bare CR or LF in head ⇒ 200 |
| token | bearer | 1f | http | Bearer "a\x1fb"; valid ⇒ 200 |
| token | bearer | sp | http, h2 | Bearer "a b"; valid ⇒ 200 |
| token | bearer | dquote | http, h2 | Bearer "a"b"; valid ⇒ 200 |
| token | bearer | comma | http, h2 | Bearer "a,b"; valid ⇒ 200 |
| token | bearer | colon | http, h2 | Bearer "a:b"; valid ⇒ 200 |
| token | bearer | backslash | http, h2 | Bearer "a\\b"; valid ⇒ 200 |
| token | bearer | 7f | http | Bearer "a\x7fb"; valid ⇒ 200 |
| token | bearer | 80 | http, h2 | Bearer "a\x80b"; valid ⇒ 200 |
| token | bearer | ff | http, h2 | Bearer "a\xffb"; valid ⇒ 200 |
| token | bearer | latin1-u-umlaut | http, h2 | Bearer "a\xfcb"; valid ⇒ 200 |
| token | bearer | utf8-u-umlaut | http, h2 | Bearer "a\xc3\xbcb"; valid ⇒ 200 |
| token | bearer | crlf-header | http, h2 | Bearer "a"; refused +header x-injected ⇒ 401 |
| user | basic | utf8-string | http, h2 | Basic "\xc3\xbcser:pass"; valid ⇒ 200 |
| user | digest | utf8-string | http, h2 | – → Digest username="\xc3\xbcser"; valid ⇒ 200 |
| user | basic | nul-string | http, h2 | refused embedded-nul, no request reached the stand-in |
| user | basic | nul-bytes | http, h2 | refused embedded-nul, no request reached the stand-in |
| pass | digest | nul-string | http, h2 | refused embedded-nul, no request reached the stand-in |
| pass | digest | nul-bytes | http, h2 | refused embedded-nul, no request reached the stand-in |
| token | bearer | nul-string | http, h2 | refused embedded-nul, no request reached the stand-in |
| token | bearer | nul-bytes | http, h2 | refused embedded-nul, no request reached the stand-in |
| user | digest | 01 | h2 | – → –; no Authorization arrived ⇒ 401 |
| user | digest | lf | h2 | –; no Authorization arrived ⇒ fails 43 |
| user | digest | cr | h2 | – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) ⇒ 401 |
| user | digest | 1f | h2 | – → –; no Authorization arrived ⇒ 401 |
| user | digest | 7f | h2 | – → –; no Authorization arrived ⇒ 401 |
| token | bearer | 01 | h2 | –; no Authorization arrived ⇒ 401 |
| token | bearer | lf | h2 | fails 43, nothing sent, no request reached the stand-in |
| token | bearer | cr | h2 | Bearer "a"; refused ⇒ 401 |
| token | bearer | 1f | h2 | –; no Authorization arrived ⇒ 401 |
| token | bearer | 7f | h2 | –; no Authorization arrived ⇒ 401 |

### Item 4: lengths (`i4len` lines)

A cell: the outcome (a setopt refusal names its code); the stand-in's verdict on the bytes it received, and their length.

| field | scheme | length | face | X |
|---|---|---|---|---|
| pass | basic | 8192 | http, h2 | 200; valid, header 10938 bytes; Basic✓/200 |
| pass | basic | 65536 | http | 200; valid, header 87394 bytes; Basic✓/200 |
| pass | basic | 1048576 | http, h2 | fails 100, nothing sent; nothing sent |
| pass | basic | 8000000 | http, h2 | fails 27, nothing sent; nothing sent |
| pass | basic | 8000001 | http, h2 | setopt 43 PASSWORD; nothing sent |
| pass | digest | 8192 | http, h2 | 200; valid; –/401 → Digest✓/200 |
| pass | digest | 65536 | http, h2 | 200; valid; –/401 → Digest✓/200 |
| pass | digest | 1048576 | http, h2 | 200; valid; –/401 → Digest✓/200 |
| pass | digest | 8000000 | http, h2 | fails 27; no Authorization; –/401 |
| pass | digest | 8000001 | http, h2 | setopt 43 PASSWORD; nothing sent |
| token | bearer | 8192 | http, h2 | 200; valid, header 8199 bytes; Bearer✓/200 |
| token | bearer | 65536 | http | 200; valid, header 65543 bytes; Bearer✓/200 |
| token | bearer | 1048576 | http, h2 | fails 100, nothing sent; nothing sent |
| token | bearer | 8000000 | http, h2 | fails 27, nothing sent; nothing sent |
| token | bearer | 8000001 | http, h2 | setopt 43 XOAUTH2_BEARER; nothing sent |
| pass | basic | 65536 | h2 | fails 55; nothing sent |
| token | bearer | 65536 | h2 | fails 55; nothing sent |

### Item 4: control bytes over h2, in libcurl's own trace (`i4trace` lines)

The h2 face's HTTP/2 stack drops a field holding a control byte before the stand-in sees it, so these cases ran again with `VERBOSE`. A cell: each `authorization` field libcurl's trace shows it handing HTTP/2 (`[HTTP/2] [N] [...]` from 8.5.0, `h2h3 [...]` on 7.85.0), escaped, the nonce and response cut; then the outcome, and the stand-in's view as in item 4.

| field | scheme | byte | face | X |
|---|---|---|---|---|
| user | digest | x | h2 | `Digest username="axb", ...`; – → Digest username="axb"; valid ⇒ 200 |
| user | digest | 01 | h2 | `Digest username="a\x01b", ...`; – → –; no Authorization arrived ⇒ 401 |
| user | digest | tab | h2 | `Digest username="a\x09b", ...`; – → Digest username="a\x09b"; valid ⇒ 200 |
| user | digest | lf | h2 | no authorization field traced; –; no Authorization arrived ⇒ fails 43 |
| user | digest | cr | h2 | `Digest username="a`; – → Digest username=""a"; bad(nonce-unknown,realm,uri,opaque,algorithm-echo,username,qop,nc,cnonce,response) ⇒ 401 |
| user | digest | 1f | h2 | `Digest username="a\x1fb", ...`; – → –; no Authorization arrived ⇒ 401 |
| user | digest | 7f | h2 | `Digest username="a\x7fb", ...`; – → –; no Authorization arrived ⇒ 401 |
| user | digest | 80 | h2 | `Digest username="a\x80b", ...`; – → Digest username="a\x80b"; valid ⇒ 200 |
| token | bearer | x | h2 | `Bearer axb`; Bearer "axb"; valid ⇒ 200 |
| token | bearer | 01 | h2 | `Bearer a\x01b`; –; no Authorization arrived ⇒ 401 |
| token | bearer | tab | h2 | `Bearer a\x09b`; Bearer "a\x09b"; valid ⇒ 200 |
| token | bearer | lf | h2 | no authorization field traced; fails 43, nothing sent, no request reached the stand-in |
| token | bearer | cr | h2 | `Bearer a`; Bearer "a"; refused ⇒ 401 |
| token | bearer | 1f | h2 | `Bearer a\x1fb`; –; no Authorization arrived ⇒ 401 |
| token | bearer | 7f | h2 | `Bearer a\x7fb`; –; no Authorization arrived ⇒ 401 |
| token | bearer | 80 | h2 | `Bearer a\x80b`; Bearer "a\x80b"; valid ⇒ 200 |

### Item 5 (b): a caller's `Expect: 100-continue`, a 64 KiB `post` (`i5expect` lines)

Modes: `417`, the stand-in answers 417 to every request carrying it; `417once`, to the first alone; `401`, a head that would fail is answered 401 before any 100. A cell: the requests, as in item 1 (`{none sent}`: the next bytes began a request), ⇒ the final status or code. Every transfer's timeout-ms is 5,000.

| scheme | case | mode | face | X |
|---|---|---|---|---|
| basic | right | 417 | http, https | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 |
| basic | right | 417once | http, https | Basic/417 at head{none sent}·E → Basic✓/200{65536}·E ⇒ 200 |
| basic | right | 401 | http, https, h2 | Basic✓/200{65536}·E ⇒ 200 |
| basic | wrong | 417 | http, https | 30 × Basic/417 at head{none sent}·E → Basic/417 at head{0, closed}·E ⇒ fails 47 |
| basic | wrong | 417once | http, https | Basic/417 at head{none sent}·E → Basic✗/401 at head{0, closed}·E ⇒ 401 |
| basic | wrong | 401 | http, https | Basic✗/401 at head{0, closed}·E ⇒ 401 |
| bearer | right | 417 | http, https | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 |
| bearer | right | 417once | http, https | Bearer/417 at head{none sent}·E → Bearer✓/200{65536}·E ⇒ 200 |
| bearer | right | 401 | http, https, h2 | Bearer✓/200{65536}·E ⇒ 200 |
| bearer | wrong | 417 | http, https | 30 × Bearer/417 at head{none sent}·E → Bearer/417 at head{0, closed}·E ⇒ fails 47 |
| bearer | wrong | 417once | http, https | Bearer/417 at head{none sent}·E → Bearer✗/401 at head{0, closed}·E ⇒ 401 |
| bearer | wrong | 401 | http, https | Bearer✗/401 at head{0, closed}·E ⇒ 401 |
| digest | right | 417 | http, https, h2 | –/417 at head·E ⇒ 417 |
| digest | right | 417once | http, https, h2 | –/417 at head·E ⇒ 417 |
| digest | right | 401 | http, https, h2 | –/401·E → Digest✓/200{65536}·E ⇒ 200 |
| digest | wrong | 417 | http, https, h2 | –/417 at head·E ⇒ 417 |
| digest | wrong | 417once | http, https, h2 | –/417 at head·E ⇒ 417 |
| digest | wrong | 401 | http, https | –/401·E → Digest✗/401 at head{0, closed}·E ⇒ 401 |
| basic | right | 417 | h2 | 31 × Basic/417 at head{0, closed}·E ⇒ fails 47 |
| basic | right | 417once | h2 | Basic/417 at head{0, closed}·E → Basic✓/200{65536}·E ⇒ 200 |
| basic | wrong | 417 | h2 | 31 × Basic/417 at head{0, closed}·E ⇒ fails 47 |
| basic | wrong | 417once | h2 | Basic/417 at head{0, closed}·E → Basic✗/401{65536}·E ⇒ 401 |
| basic | wrong | 401 | h2 | Basic✗/401{65536}·E ⇒ 401 |
| bearer | right | 417 | h2 | 31 × Bearer/417 at head{0, closed}·E ⇒ fails 47 |
| bearer | right | 417once | h2 | Bearer/417 at head{0, closed}·E → Bearer✓/200{65536}·E ⇒ 200 |
| bearer | wrong | 417 | h2 | 31 × Bearer/417 at head{0, closed}·E ⇒ fails 47 |
| bearer | wrong | 417once | h2 | Bearer/417 at head{0, closed}·E → Bearer✗/401{65536}·E ⇒ 401 |
| bearer | wrong | 401 | h2 | Bearer✗/401{65536}·E ⇒ 401 |
| digest | wrong | 401 | h2 | –/401·E → Digest✗/401{65536}·E ⇒ 401 |

### Item 5 (c): the first valid request (or two) answered 401 again (`i5stale` lines)

Digest's second 401 carries `stale=true` and a new nonce; Basic's and Bearer's carry the route's challenge. A cell as in item 1.

| scheme | stale | face | X |
|---|---|---|---|
| digest | 1 | http, h2 | –/401 → Digest✓/401 → Digest✓/200 ⇒ 200 |
| digest | 2 | http, h2 | –/401 → Digest✓/401 → Digest✓/401 → Digest✓/200 ⇒ 200 |
| basic | 1 | http, h2 | Basic✓/401 ⇒ 401 |
| bearer | 1 | http, h2 | Bearer✓/401 ⇒ 401 |

### Item 5 (d): the private follow, a 302 from the first hop (`i5follow` lines)

A cell: each request, with its connection as a letter (A, B ... in order of first use; another letter is another connection), as in item 1, ⇒ the final status. The first hop is `http://127.0.0.1` (`localhost` in `localhost-to-ip`), the h2 face in `h2-same-origin`; `http-to-https-same-port` changes the scheme alone, on one port.

| scheme | target | UNRESTRICTED_AUTH | X |
|---|---|---|---|
| basic | same-origin | off | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 |
| basic | same-origin | on | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 |
| basic | other-port | off | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | other-port | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | ip-to-localhost | off | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | ip-to-localhost | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | localhost-to-ip | off | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | localhost-to-ip | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | http-to-https-same-port | off | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | http-to-https-same-port | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | http-to-https-face | off | A:Basic✓/302 → B:–/401 ⇒ 401 |
| basic | http-to-https-face | on | A:Basic✓/302 → B:Basic✓/200 ⇒ 200 |
| basic | h2-same-origin | off | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 |
| basic | h2-same-origin | on | A:Basic✓/302 → A:Basic✓/200 ⇒ 200 |
| digest | same-origin | off | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 |
| digest | same-origin | on | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 |
| digest | other-port | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | other-port | on | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | ip-to-localhost | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | ip-to-localhost | on | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | localhost-to-ip | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | localhost-to-ip | on | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | http-to-https-same-port | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | http-to-https-same-port | on | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | http-to-https-face | off | A:–/401 → A:Digest✓/302 → B:–/401 ⇒ 401 |
| digest | http-to-https-face | on | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 200 |
| digest | h2-same-origin | off | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 |
| digest | h2-same-origin | on | A:–/401 → A:Digest✓/302 → A:Digest✓/200 ⇒ 200 |
| bearer | same-origin | off | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 |
| bearer | same-origin | on | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 |
| bearer | other-port | off | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | other-port | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | ip-to-localhost | off | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | ip-to-localhost | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | localhost-to-ip | off | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | localhost-to-ip | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | http-to-https-same-port | off | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | http-to-https-same-port | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | http-to-https-face | off | A:Bearer✓/302 → B:–/401 ⇒ 401 |
| bearer | http-to-https-face | on | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 200 |
| bearer | h2-same-origin | off | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 |
| bearer | h2-same-origin | on | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 200 |

### Items 5 and 8: the address each request to `localhost` reached (`i5follow`, `i8` lines)

A cell: each request's peer address at the stand-in, in order; every face listens on 127.0.0.1 and on ::1 at one port.

| item | scheme | target | UNRESTRICTED_AUTH | X |
|---|---|---|---|---|
| i5follow | basic | ip-to-localhost | off | 127.0.0.1, [::1] |
| i5follow | basic | ip-to-localhost | on | 127.0.0.1, [::1] |
| i5follow | basic | localhost-to-ip | off | [::1], 127.0.0.1 |
| i5follow | basic | localhost-to-ip | on | [::1], 127.0.0.1 |
| i5follow | digest | ip-to-localhost | off | 127.0.0.1, 127.0.0.1, [::1] |
| i5follow | digest | ip-to-localhost | on | 127.0.0.1, 127.0.0.1, [::1], [::1] |
| i5follow | digest | localhost-to-ip | off | [::1], [::1], 127.0.0.1 |
| i5follow | digest | localhost-to-ip | on | [::1], [::1], 127.0.0.1, 127.0.0.1 |
| i5follow | bearer | ip-to-localhost | off | 127.0.0.1, [::1] |
| i5follow | bearer | ip-to-localhost | on | 127.0.0.1, [::1] |
| i5follow | bearer | localhost-to-ip | off | [::1], 127.0.0.1 |
| i5follow | bearer | localhost-to-ip | on | [::1], 127.0.0.1 |
| i8 | basic | other-host | - | 127.0.0.1, [::1] |
| i8 | digest | other-host | - | 127.0.0.1, 127.0.0.1, [::1], [::1] |
| i8 | bearer | other-host | - | 127.0.0.1, [::1] |

### Item 6: transfers on one engine (`i6` lines)

A cell: each request of the step, its connection a letter shared by the case's two steps (A, B ... in order of first use), as in item 1, ⇒ its final status. `together`: both submitted in one batch; `after-head`: the second submitted once the first's head was in.

| case | scheme | face | step | X |
|---|---|---|---|---|
| digest-twice | digest | http, https, h2 | 1 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| digest-twice | digest | http, https, h2 | 2 | – → Digest username="user"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| other-credentials | basic | http, https, h2 | 1 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 |
| other-credentials | basic | http, https, h2 | 2 | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200 |
| then-none | basic | http, https, h2 | 1 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 |
| then-none | basic | http, https, h2 | 2 | –; A:–/200 ⇒ 200 |
| other-credentials | digest | http, https, h2 | 1 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| other-credentials | digest | http, https, h2 | 2 | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| then-none | digest | http, https, h2 | 1 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| then-none | digest | http, https, h2 | 2 | –; A:–/200 ⇒ 200 |
| other-credentials | bearer | http, https, h2 | 1 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 |
| other-credentials | bearer | http, https, h2 | 2 | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200 |
| then-none | bearer | http, https, h2 | 1 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 |
| then-none | bearer | http, https, h2 | 2 | –; A:–/200 ⇒ 200 |
| together | basic | h2 | 1 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200 |
| together | basic | h2 | 2 | Basic "bob:pw-b"; B:Basic✓/200 ⇒ 200 |
| after-head | basic | h2 | 1 | Basic "alice:pw-a"; A:Basic✓/200 ⇒ 200; head 200 |
| after-head | basic | h2 | 2 | Basic "bob:pw-b"; A:Basic✓/200 ⇒ 200; first done at second's end #f |
| together | digest | h2 | 1 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200 |
| together | digest | h2 | 2 | – → Digest username="bob"; B:–/401 → A:Digest✓/200 ⇒ 200 |
| after-head | digest | h2 | 1 | – → Digest username="alice"; A:–/401 → A:Digest✓/200 ⇒ 200; head 401 |
| after-head | digest | h2 | 2 | – → Digest username="bob"; A:–/401 → A:Digest✓/200 ⇒ 200; first done at second's end #f |
| together | bearer | h2 | 1 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200 |
| together | bearer | h2 | 2 | Bearer "tok-b"; B:Bearer✓/200 ⇒ 200 |
| after-head | bearer | h2 | 1 | Bearer "tok-a"; A:Bearer✓/200 ⇒ 200; head 200 |
| after-head | bearer | h2 | 2 | Bearer "tok-b"; A:Bearer✓/200 ⇒ 200; first done at second's end #f |

### Item 7: the twins (`i7` lines)

A cell: the requests' credentials as the stand-in decoded them (an `AWS4-HMAC-SHA256` header named by its scheme), and `+header N (#K)` for a header no request otherwise carries, with the requests that carried it; the requests, as in item 1 (a verdict ✗ on `AWS4` is the stand-in knowing no such scheme); ⇒ the final status or code. Every case is a `get` to the `http` face with the route's challenge for the scheme, but where named: `AWS_SIGV4-*` to an open route, `*-post` a 64 KiB `post`, `early-401-*` a 1 MiB `post` answered 401 at its head, `stream-*` a streamed 256 KiB body answered 401 at its head.

| twin | scheme | face | X |
|---|---|---|---|
| control | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=* | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=PLAIN | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| DISALLOW_USERNAME_IN_URL=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| AWS_SIGV4-after | basic | http | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 |
| FAILONERROR=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| FAILONERROR=1-wrong | basic | http | Basic "user:wrong"; Basic✗/401 ⇒ fails 22 |
| NETRC_FILE-beside | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| control | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=* | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=PLAIN | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| DISALLOW_USERNAME_IN_URL=1 | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| AWS_SIGV4-after | digest | http | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 |
| FAILONERROR=1 | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| FAILONERROR=1-wrong | digest | http | – → Digest username="user"; –/401 → Digest✗/401 ⇒ fails 22 |
| NETRC_FILE-beside | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| control | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=* | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| LOGIN_OPTIONS=AUTH=PLAIN | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| DISALLOW_USERNAME_IN_URL=1 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| AWS_SIGV4-after | bearer | http | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 |
| FAILONERROR=1 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| FAILONERROR=1-wrong | bearer | http | Bearer "wrong"; Bearer✗/401 ⇒ fails 22 |
| NETRC_FILE-beside | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| AWS_SIGV4-before | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| AWS_SIGV4-alone | none | http | AWS4-HMAC-SHA256 +header x-amz-date (#1) +header x-amz-content-sha256 (#1); AWS4✗/200 ⇒ 200 |
| userinfo-control | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| userinfo-DISALLOW_USERNAME_IN_URL=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| userinfo-digest-control | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| userinfo-digest-DISALLOW_USERNAME_IN_URL=1 | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| NETRC_FILE-alone | none | http | –; –/401 ⇒ 401 |
| NETRC_FILE-HTTPAUTH-basic | basic | http | –; –/401 ⇒ 401 |
| NETRC_FILE-HTTPAUTH-digest | digest | http | –; –/401 ⇒ 401 |
| NETRC_FILE-userinfo-user | basic | http | Basic "netuser:"; Basic✗/401 ⇒ 401 |
| control-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| SASL_AUTHZID-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| SASL_IR-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| SERVICE_NAME-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| KEEP_SENDING_ON_ERROR-post | digest | http | – → Digest username="user"; –/401 → Digest✓/200{65536} ⇒ 200 |
| early-401-control | basic | http | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401 |
| early-401-KEEP_SENDING_ON_ERROR=1 | basic | http | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401 |
| early-401-control | digest | http | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 |
| early-401-KEEP_SENDING_ON_ERROR=1 | digest | http | – → Digest username="user"; –/401 at head → Digest✗/401 at head{whole} ⇒ 401 |
| MAXREDIRS=0 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| MAXREDIRS=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| MAXREDIRS=1-stale | basic | http | Basic "user:pass"; Basic✓/401 ⇒ 401 |
| AUTOREFERER=1 | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| SERVICE_NAME | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| SASL_AUTHZID | basic | http | Basic "user:pass"; Basic✓/200 ⇒ 200 |
| MAXREDIRS=0 | digest | http | –; –/401 ⇒ fails 47 |
| MAXREDIRS=1 | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| MAXREDIRS=1-stale | digest | http | – → Digest username="user"; –/401 → Digest✓/401 ⇒ fails 47 |
| AUTOREFERER=1 | digest | http | – → Digest username="user" +header referer (#2); –/401 → Digest✓/200 ⇒ 200 |
| SERVICE_NAME | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| SASL_AUTHZID | digest | http | – → Digest username="user"; –/401 → Digest✓/200 ⇒ 200 |
| MAXREDIRS=0 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| MAXREDIRS=1 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| MAXREDIRS=1-stale | bearer | http | Bearer "tok123"; Bearer✓/401 ⇒ 401 |
| AUTOREFERER=1 | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| SERVICE_NAME | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| SASL_AUTHZID | bearer | http | Bearer "tok123"; Bearer✓/200 ⇒ 200 |
| MAXREDIRS=0-expect417once | basic | http | Basic dXNlcjpwYXNz; Basic/417 at head{0, closed}·E ⇒ fails 47 |
| MAXREDIRS=-1-expect417 | basic | http | 40 × Basic dXNlcjpwYXNz → ...; 40 × Basic/417 at head{none sent}·E → over 1,000 more, the last Basic/417 at head{0, closed} (over 1,000 requests) ⇒ fails 100 |
| SERVICE_NAME-alone-HTTPAUTH-basic | basic | http | –; –/200 ⇒ 200 |
| SASL_AUTHZID-alone-HTTPAUTH-basic | basic | http | –; –/200 ⇒ 200 |
| stream-early-401-control | basic | http, h2 | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done |
| stream-early-401-KEEP_SENDING_ON_ERROR=1 | basic | http | Basic "user:wrong"; Basic✗/401 at head{whole} ⇒ 401; last put end |
| stream-early-401-KEEP_SENDING_ON_ERROR=1 | basic | h2 | Basic "user:wrong"; Basic✗/401 at head{part, closed} ⇒ 401; last put done |

### Item 8: a redirect's hops built by hand on one engine (`i8` lines)

Step 1 is a `get` to `http://127.0.0.1` answered 302 once the credentials pass; step 2 a fresh transfer on the same engine to the `Location`, with the same credentials by the hatch. A cell: each request of the two steps, its connection a letter (the same letter in step 2 is step 1's pooled connection), as in item 1; ⇒ each step's final status.

| scheme | target | X |
|---|---|---|
| basic | same-origin-other-path | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 |
| basic | other-port | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 |
| basic | other-host | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 |
| basic | http-to-https-same-port | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 |
| basic | http-to-https-face | A:Basic✓/302 → B:Basic✓/200 ⇒ 302, 200 |
| digest | same-origin-other-path | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 |
| digest | other-port | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 |
| digest | other-host | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 |
| digest | http-to-https-same-port | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 |
| digest | http-to-https-face | A:–/401 → A:Digest✓/302 → B:–/401 → B:Digest✓/200 ⇒ 302, 200 |
| bearer | same-origin-other-path | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 |
| bearer | other-port | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 |
| bearer | other-host | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 |
| bearer | http-to-https-same-port | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 |
| bearer | http-to-https-face | A:Bearer✓/302 → B:Bearer✓/200 ⇒ 302, 200 |
| basic | userinfo-location | A:Basic✓/302 → A:Basic✓/200 ⇒ 302, 200 |
| digest | userinfo-location | A:–/401 → A:Digest✓/302 → A:–/401 → A:Digest✓/200 ⇒ 302, 200 |
| bearer | userinfo-location | A:Bearer✓/302 → A:Bearer✓/200 ⇒ 302, 200 |

### Item 8: what each hop's credentials decoded to (`i8` lines)

A cell: each request's credentials as the stand-in decoded them, in order, across the two steps.

| scheme | target | X |
|---|---|---|
| basic | same-origin-other-path | Basic "user:pass" → Basic "user:pass" |
| basic | other-port | Basic "user:pass" → Basic "user:pass" |
| basic | other-host | Basic "user:pass" → Basic "user:pass" |
| basic | http-to-https-same-port | Basic "user:pass" → Basic "user:pass" |
| basic | http-to-https-face | Basic "user:pass" → Basic "user:pass" |
| digest | same-origin-other-path | – → Digest username="user" → – → Digest username="user" |
| digest | other-port | – → Digest username="user" → – → Digest username="user" |
| digest | other-host | – → Digest username="user" → – → Digest username="user" |
| digest | http-to-https-same-port | – → Digest username="user" → – → Digest username="user" |
| digest | http-to-https-face | – → Digest username="user" → – → Digest username="user" |
| bearer | same-origin-other-path | Bearer "tok123" → Bearer "tok123" |
| bearer | other-port | Bearer "tok123" → Bearer "tok123" |
| bearer | other-host | Bearer "tok123" → Bearer "tok123" |
| bearer | http-to-https-same-port | Bearer "tok123" → Bearer "tok123" |
| bearer | http-to-https-face | Bearer "tok123" → Bearer "tok123" |
| basic | userinfo-location | Basic "user:pass" → Basic "user:pass" |
| digest | userinfo-location | – → Digest username="user" → – → Digest username="user" |
| bearer | userinfo-location | Bearer "tok123" → Bearer "tok123" |

### Item 8: today's origin rule, by `exchange-step` (`o` lines)

A 302 from A to the Location B, the request carrying `Authorization`, `Cookie` and `X-Other`. A cell: the headers the next request keeps (dropped ones are another origin's), and the parts `curl-url-part` gave B (scheme, host, port).

| A | Location B | X |
|---|---|---|
| http://h.example/a | http://h.example:80/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) |
| http://h.example:80/a | http://h.example/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) |
| https://h.example/a | https://h.example:443/b | next ("Authorization" "Cookie" "X-Other"); B ("https" "h.example" 443) |
| http://h.example/a | http://H.EXAMPLE/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "H.EXAMPLE" 80) |
| http://h.example/a | http://h.example:8080/b | next ("X-Other"); B ("http" "h.example" 8080) |
| http://h.example/a | https://h.example/b | next ("X-Other"); B ("https" "h.example" 443) |
| http://h.example/a | https://h.example:80/b | next ("X-Other"); B ("https" "h.example" 80) |
| http://127.0.0.1/a | http://localhost/b | next ("X-Other"); B ("http" "localhost" 80) |
| http://h.example/a | /b | next ("Authorization" "Cookie" "X-Other"); B (refused "Exception in chez-curl: Bad scheme with irritant \"/b\"") |
| http://[::1]/a | http://[::1]:80/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "[::1]" 80) |
| http://u:p@h.example/a | http://h.example/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) |
| http://h.example/a | http://u:p@h.example/b | next ("Authorization" "Cookie" "X-Other"); B ("http" "h.example" 80) |

### Checks, each lane-run

| lane | run | exits | self-test | counts | transfers | hung | tags still open 3 s on | error lines |
|---|---|---|---|---|---|---|---|---|
| X | 1 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
| X | 2 | 13 parts, all 0 | standin selftest ok 13; standin selftest exit=0 | 13 native, 0 nonzero | 945 | 0 | 0 | 0 |
