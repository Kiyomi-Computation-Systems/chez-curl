A cell `=` is the same as the row's first; one in bold is two runs that disagree, run 1 / run 2.

### Item 2 (b): what goes on the wire for each userinfo form, through `p-open` (`i2b`)

A cell: the outcome, then the `Proxy-Authorization` p-open decoded, user:password with each byte outside `!`..`~` as `\xHH`, or `–` for none sent; `no request` when no face got one; `DIRECT` when the origin got the request straight, and the proxy nothing.

| case | F | O |
|---|---|---|
| form=none transport=absolute | 200; – | = |
| form=none transport=connect | 200; – | = |
| form=at transport=absolute | 200; – | 200; : |
| form=at transport=connect | 200; – | 200; : |
| form=colon-at transport=absolute | 200; – | 200; : |
| form=colon-at transport=connect | 200; – | 200; : |
| form=u-at transport=absolute | 200; u: | = |
| form=u-at transport=connect | 200; u: | = |
| form=u-colon-at transport=absolute | 200; u: | = |
| form=u-colon-at transport=connect | 200; u: | = |
| form=colon-p-at transport=absolute | 200; :p | = |
| form=colon-p-at transport=connect | 200; :p | = |
| form=u-p-at transport=absolute | 200; u:p | = |
| form=u-p-at transport=connect | 200; u:p | = |
| form=user-3A transport=absolute | 200; a:b:p | = |
| form=user-3A transport=connect | 200; a:b:p | = |
| form=pass-3A transport=absolute | 200; u:p:q | = |
| form=pass-3A transport=connect | 200; u:p:q | = |
| form=user-0D0A transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-0D0A transport=connect | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=pass-0D0A transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=pass-0D0A transport=connect | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-00 transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-00 transport=connect | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=pass-00 transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=pass-00 transport=connect | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-01 transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-01 transport=connect | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-09 transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-09 transport=connect | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-1F transport=absolute | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-1F transport=connect | 200; DIRECT: the origin got it, the proxy nothing | = |
| form=user-20 transport=absolute | 200; u\x20x:p | = |
| form=user-20 transport=connect | 200; u\x20x:p | = |
| form=user-7F transport=absolute | 200; u\x7fx:p | = |
| form=user-7F transport=connect | 200; u\x7fx:p | = |
| form=pass-7F transport=absolute | 200; u:p\x7fx | = |
| form=pass-7F transport=connect | 200; u:p\x7fx | = |
| form=utf8-pct transport=absolute | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss | = |
| form=utf8-pct transport=connect | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss | = |
| form=user-FF transport=absolute | 200; u\xffx:p | = |
| form=user-FF transport=connect | 200; u\xffx:p | = |
| form=pass-FF transport=absolute | 200; u:p\xffx | = |
| form=pass-FF transport=connect | 200; u:p\xffx | = |
| form=pct-25 transport=absolute | 200; u%x:p%q | = |
| form=pct-25 transport=connect | 200; u%x:p%q | = |
| form=utf8-raw transport=absolute | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss | = |
| form=utf8-raw transport=connect | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss | = |
| form=noscheme-u-p transport=absolute | 200; u:p | = |
| form=noscheme-u-p transport=connect | 200; u:p | = |

### Item 3: the pooled tunnel (`i3`)

Two transfers on one engine through one proxy that takes Basic for alice and bob, the first as alice. `sequential`: the second submitted once the first is done; `batch`: both submitted in one hold of the engine. A cell: `reused` when the second request rode the first's origin connection (for a tunnel: inside the first's tunnel; for absolute form: on the first's proxy connection, whose upstream it is), else `new`; then the second's outcome; then each request the proxy got for the second, with the credentials it carried (`no request`: the proxy got none for it).

| case | F | O |
|---|---|---|
| mode=connect-https order=sequential flags=plain second=same | reused; 200; no request | = |
| mode=connect-https order=sequential flags=plain second=other | reused; 200; no request | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=connect-https order=sequential flags=plain second=wrong | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-https order=sequential flags=plain second=none | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=connect-https order=sequential flags=fresh-second second=same | new; 200; CONNECT PA=alice:s3cret→200 | = |
| mode=connect-https order=sequential flags=fresh-second second=other | new; 200; CONNECT PA=bob:hunter2→200 | = |
| mode=connect-https order=sequential flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-https order=sequential flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=connect-https order=sequential flags=forbid-first second=same | new; 200; CONNECT PA=alice:s3cret→200 | = |
| mode=connect-https order=sequential flags=forbid-first second=other | new; 200; CONNECT PA=bob:hunter2→200 | = |
| mode=connect-https order=sequential flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-https order=sequential flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=tunnel-http order=sequential flags=plain second=same | reused; 200; no request | = |
| mode=tunnel-http order=sequential flags=plain second=other | reused; 200; no request | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=tunnel-http order=sequential flags=plain second=wrong | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=tunnel-http order=sequential flags=plain second=none | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=tunnel-http order=sequential flags=fresh-second second=same | new; 200; CONNECT PA=alice:s3cret→200 | = |
| mode=tunnel-http order=sequential flags=fresh-second second=other | new; 200; CONNECT PA=bob:hunter2→200 | = |
| mode=tunnel-http order=sequential flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=tunnel-http order=sequential flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=tunnel-http order=sequential flags=forbid-first second=same | new; 200; CONNECT PA=alice:s3cret→200 | = |
| mode=tunnel-http order=sequential flags=forbid-first second=other | new; 200; CONNECT PA=bob:hunter2→200 | = |
| mode=tunnel-http order=sequential flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=tunnel-http order=sequential flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=absolute-http order=sequential flags=plain second=same | reused; 200; abs PA=alice:s3cret | = |
| mode=absolute-http order=sequential flags=plain second=other | reused; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 |
| mode=absolute-http order=sequential flags=plain second=wrong | new; 407; abs PA=alice:wrong→407 | = |
| mode=absolute-http order=sequential flags=plain second=none | new; 407; abs PA=–→407 | = |
| mode=absolute-http order=sequential flags=fresh-second second=same | new; 200; abs PA=alice:s3cret | = |
| mode=absolute-http order=sequential flags=fresh-second second=other | new; 200; abs PA=bob:hunter2 | = |
| mode=absolute-http order=sequential flags=fresh-second second=wrong | new; 407; abs PA=alice:wrong→407 | = |
| mode=absolute-http order=sequential flags=fresh-second second=none | new; 407; abs PA=–→407 | = |
| mode=absolute-http order=sequential flags=forbid-first second=same | new; 200; abs PA=alice:s3cret | = |
| mode=absolute-http order=sequential flags=forbid-first second=other | new; 200; abs PA=bob:hunter2 | = |
| mode=absolute-http order=sequential flags=forbid-first second=wrong | new; 407; abs PA=alice:wrong→407 | = |
| mode=absolute-http order=sequential flags=forbid-first second=none | new; 407; abs PA=–→407 | = |
| mode=https-proxy-connect-https order=sequential flags=plain second=same | reused; 200; no request | = |
| mode=https-proxy-connect-https order=sequential flags=plain second=other | reused; 200; no request | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=https-proxy-connect-https order=sequential flags=plain second=wrong | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=https-proxy-connect-https order=sequential flags=plain second=none | reused; 200; no request | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=same | new; 200; CONNECT PA=alice:s3cret→200 | = |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=other | new; 200; CONNECT PA=bob:hunter2→200 | = |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=same | new; 200; CONNECT PA=alice:s3cret→200 | = |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=other | new; 200; CONNECT PA=bob:hunter2→200 | = |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=https-proxy-absolute-http order=sequential flags=plain second=same | reused; 200; abs PA=alice:s3cret | = |
| mode=https-proxy-absolute-http order=sequential flags=plain second=other | reused; 200; abs PA=bob:hunter2 | new; 200; abs PA=bob:hunter2 |
| mode=https-proxy-absolute-http order=sequential flags=plain second=wrong | new; 407; abs PA=alice:wrong→407 | = |
| mode=https-proxy-absolute-http order=sequential flags=plain second=none | new; 407; abs PA=–→407 | = |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=same | new; 200; abs PA=alice:s3cret | = |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=other | new; 200; abs PA=bob:hunter2 | = |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=wrong | new; 407; abs PA=alice:wrong→407 | = |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=none | new; 407; abs PA=–→407 | = |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=same | new; 200; abs PA=alice:s3cret | = |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=other | new; 200; abs PA=bob:hunter2 | = |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=wrong | new; 407; abs PA=alice:wrong→407 | = |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=none | new; 407; abs PA=–→407 | = |
| mode=connect-h2 order=sequential flags=plain second=same | reused stream=3; 200 h2; no request | = |
| mode=connect-h2 order=sequential flags=plain second=other | reused stream=3; 200 h2; no request | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 |
| mode=connect-h2 order=sequential flags=plain second=wrong | reused stream=3; 200 h2; no request | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=sequential flags=plain second=none | reused stream=3; 200 h2; no request | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=sequential flags=fresh-second second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = |
| mode=connect-h2 order=sequential flags=fresh-second second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = |
| mode=connect-h2 order=sequential flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=sequential flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=sequential flags=forbid-first second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = |
| mode=connect-h2 order=sequential flags=forbid-first second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = |
| mode=connect-h2 order=sequential flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=sequential flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=batch flags=plain second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = |
| mode=connect-h2 order=batch flags=plain second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = |
| mode=connect-h2 order=batch flags=plain second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=batch flags=plain second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=batch flags=fresh-second second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = |
| mode=connect-h2 order=batch flags=fresh-second second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = |
| mode=connect-h2 order=batch flags=fresh-second second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=batch flags=fresh-second second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=batch flags=forbid-first second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 | = |
| mode=connect-h2 order=batch flags=forbid-first second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 | = |
| mode=connect-h2 order=batch flags=forbid-first second=wrong | new; 56 send-receive sent=134; CONNECT PA=alice:wrong→407 | new; 56 send-receive sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=batch flags=forbid-first second=none | new; 56 send-receive sent=89; CONNECT PA=–→407 | new; 56 send-receive sent=0; CONNECT PA=–→407 |

### Item 4: a refused CONNECT, and the same proxies by absolute form (`i4`)

A cell: the status chez-curl's response carries, or the failure: code, class, request size; then the error buffer.

| case | F | O |
|---|---|---|
| proxy=403 transport=absolute | 403 | = |
| proxy=403 transport=connect | 56 send-receive sent=89; "Received HTTP code 403 from proxy after CONNECT" | 56 send-receive sent=0; "CONNECT tunnel failed, response 403" |
| proxy=407-none transport=absolute | 407 | = |
| proxy=407-none transport=connect | 56 send-receive sent=89; "Received HTTP code 407 from proxy after CONNECT" | 56 send-receive sent=0; "CONNECT tunnel failed, response 407" |
| proxy=407-wrong transport=absolute | 407 | = |
| proxy=407-wrong transport=connect | 56 send-receive sent=134; "Received HTTP code 407 from proxy after CONNECT" | 56 send-receive sent=0; "CONNECT tunnel failed, response 407" |
| proxy=502 transport=absolute | 502 | = |
| proxy=502 transport=connect | 56 send-receive sent=89; "Received HTTP code 502 from proxy after CONNECT" | 56 send-receive sent=0; "CONNECT tunnel failed, response 502" |
| proxy=close transport=absolute | 52 send-receive sent=120; "Empty reply from server" | = |
| proxy=close transport=connect | 56 send-receive sent=89; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" |
| proxy=partial transport=absolute | 52 send-receive sent=121; "Empty reply from server" | = |
| proxy=partial transport=connect | 56 send-receive sent=89; "Proxy CONNECT aborted" | 56 send-receive sent=0; "Proxy CONNECT aborted" |
| proxy=refused transport=absolute | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Connection refused" | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Couldn't connect to server" |
| proxy=refused transport=connect | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Connection refused" | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <refused> after N ms: Couldn't connect to server" |

### Item 4: the high level's retry through each (`i4high`)

`http-get` and `http-post`, with the policy (attempts 3, the default statuses and methods, backoff 20 ms, jitter off) and with none. A cell: what the call answered or raised (`transfers=` its `&http-exchange`'s count), then the requests the proxy logged.

| case | F | O |
|---|---|---|
| proxy=403 transport=absolute method=get retry=policy | 403; proxy got 1 | = |
| proxy=403 transport=absolute method=get retry=none | 403; proxy got 1 | = |
| proxy=403 transport=absolute method=post retry=policy | 403; proxy got 1 | = |
| proxy=403 transport=absolute method=post retry=none | 403; proxy got 1 | = |
| proxy=403 transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=403 transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=403 transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=403 transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=407-none transport=absolute method=get retry=policy | 407; proxy got 1 | = |
| proxy=407-none transport=absolute method=get retry=none | 407; proxy got 1 | = |
| proxy=407-none transport=absolute method=post retry=policy | 407; proxy got 1 | = |
| proxy=407-none transport=absolute method=post retry=none | 407; proxy got 1 | = |
| proxy=407-none transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=407-none transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=407-none transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=407-none transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=407-wrong transport=absolute method=get retry=policy | 407; proxy got 1 | = |
| proxy=407-wrong transport=absolute method=get retry=none | 407; proxy got 1 | = |
| proxy=407-wrong transport=absolute method=post retry=policy | 407; proxy got 1 | = |
| proxy=407-wrong transport=absolute method=post retry=none | 407; proxy got 1 | = |
| proxy=407-wrong transport=connect method=get retry=policy | 56 send-receive sent=134 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=407-wrong transport=connect method=get retry=none | 56 send-receive sent=134 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=407-wrong transport=connect method=post retry=policy | 56 send-receive sent=134 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=407-wrong transport=connect method=post retry=none | 56 send-receive sent=134 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=502 transport=absolute method=get retry=policy | 502; proxy got 1 | = |
| proxy=502 transport=absolute method=get retry=none | 502; proxy got 1 | = |
| proxy=502 transport=absolute method=post retry=policy | 502; proxy got 1 | = |
| proxy=502 transport=absolute method=post retry=none | 502; proxy got 1 | = |
| proxy=502 transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=502 transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=502 transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=502 transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=close transport=absolute method=get retry=policy | 52 send-receive sent=121 transfers=3; proxy got 3 | = |
| proxy=close transport=absolute method=get retry=none | 52 send-receive sent=121 transfers=1; proxy got 1 | = |
| proxy=close transport=absolute method=post retry=policy | 52 send-receive sent=204 transfers=1; proxy got 1 | = |
| proxy=close transport=absolute method=post retry=none | 52 send-receive sent=204 transfers=1; proxy got 1 | = |
| proxy=close transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=close transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=close transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=close transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=partial transport=absolute method=get retry=policy | 52 send-receive sent=121 transfers=3; proxy got 3 | = |
| proxy=partial transport=absolute method=get retry=none | 52 send-receive sent=121 transfers=1; proxy got 1 | = |
| proxy=partial transport=absolute method=post retry=policy | 52 send-receive sent=204 transfers=1; proxy got 1 | = |
| proxy=partial transport=absolute method=post retry=none | 52 send-receive sent=204 transfers=1; proxy got 1 | = |
| proxy=partial transport=connect method=get retry=policy | 56 send-receive sent=89 transfers=3; proxy got 3 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=partial transport=connect method=get retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=partial transport=connect method=post retry=policy | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=partial transport=connect method=post retry=none | 56 send-receive sent=89 transfers=1; proxy got 1 | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=refused transport=absolute method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 0 | = |
| proxy=refused transport=absolute method=get retry=none | 7 connect sent=0 transfers=1; proxy got 0 | = |
| proxy=refused transport=absolute method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 0 | = |
| proxy=refused transport=absolute method=post retry=none | 7 connect sent=0 transfers=1; proxy got 0 | = |
| proxy=refused transport=connect method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 0 | = |
| proxy=refused transport=connect method=get retry=none | 7 connect sent=0 transfers=1; proxy got 0 | = |
| proxy=refused transport=connect method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 0 | = |
| proxy=refused transport=connect method=post retry=none | 7 connect sent=0 transfers=1; proxy got 0 | = |

### Item 5: TLS inside TLS, ten times each per run (`i5stall`)

`timeout-ms` 10,000, through `tp-good` (`https-via-http`: through plaintext `p-open`). A cell: each outcome and how many of the ten gave it.

| case | F | O |
|---|---|---|
| case=https-via-https | 10× 200 | = |
| case=http-via-https | 10× 200 | = |
| case=h2-via-https | **7× 200 h2, 3× 28 timeout sent=154 / 3× 28 timeout sent=154, 7× 200 h2** | 10× 200 h2 |
| case=https-via-http | 10× 200 | = |
