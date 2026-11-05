# Draft: curl bug report, for the maintainer to file

A draft, written 2026-11-04 from the logs beside it; nothing here has been sent. File it at
<https://github.com/curl/curl/issues>, editing as you see fit.

---

**Title:** A cookie larger than the Cookie header cap leaves the request head unterminated, and
the transfer hangs until its timeout

### I did this

One cookie whose name and value together pass `MAX_COOKIE_HEADER_LEN` (8190), loaded with
`CURLOPT_COOKIELIST`, then a GET to a server that logs the bytes it receives:

```c
CURL *h = curl_easy_init();
curl_easy_setopt(h, CURLOPT_URL, "http://127.0.0.1:PORT/");
curl_easy_setopt(h, CURLOPT_COOKIEFILE, "");
curl_easy_setopt(h, CURLOPT_COOKIELIST,
                 "127.0.0.1\tFALSE\t/\tFALSE\t0\tnm\tvvvv...");  /* a value of 8,200 bytes */
curl_easy_setopt(h, CURLOPT_TIMEOUT, 3L);
curl_easy_perform(h);
```

(the whole program is `cap.c`, its server `cap-server.mjs`). The server receives:

```
GET /?n=8200 HTTP/1.1\r\n
Host: 127.0.0.1:PORT\r\n
Accept: */*\r\n
Cookie: \r\n
```

and no blank line after it, so it waits for the rest of the head; curl waits for the response,
and the transfer ends 28 at its timeout, or never without one. With a value of 8,170 bytes the
head is whole and the cookie is sent.

### I expected the following

The cookie left out, as libcurl does for a later cookie that would pass the cap ("Restricted
outgoing cookies due to header size"), and a well-formed head with no `Cookie` header.

### Why

In `Curl_http_cookies` (8.20.0 `lib/http.c:2557-2600`), the loop writes `Cookie: ` before the
first cookie, then finds that cookie past the cap and breaks with `count` still 0. The line's
`\r\n` is written only `if(count && !result)`, so none is; the head's own closing `\r\n` then ends
the `Cookie:` line, and the head has no end. Writing `Cookie: ` only once a cookie is known to fit,
or ending the line whenever the prefix was written, would fix it.

A server cannot store such a cookie through `Set-Cookie`, whose name and value are held to
`MAX_NAME` (4096), and a cookie file's line is held to `MAX_COOKIE_LINE` (5000): curl's own tool
exits 100 on one past it, so the tool does not show this. `CURLOPT_COOKIELIST` took Netscape
lines of 100,000 bytes.

On 7.85.0 the cap counts the head built before the `Cookie` line too (`lib/http.c:2755`), so a
cookie a server set, 4,003 bytes, beside a URL path of 4,200 bytes hangs the same way
(`cap-url.c`); 8.5.0 and 8.23.0 count the `Cookie` line alone, and sent that one whole.

### curl/libcurl version

Measured with the program above on: 7.85.0 (OpenSSL 3.0.13), Ubuntu 24.04's 8.5.0 (OpenSSL and
GnuTLS), 8.20.0 (GnuTLS 3.8.13), 8.23.0 (OpenSSL 3.0.13); the code is the same in 8.7.1 and
8.23.0 (`lib/http.c:2631`).

### operating system

Linux x86_64, Ubuntu 24.04 and Guix.

---

Logs: [`results/cap-c-guix-8.20.0.log`](results/cap-c-guix-8.20.0.log),
[`results/cap-c-docker.log`](results/cap-c-docker.log),
[`results/cap-url-docker.log`](results/cap-url-docker.log).
