A cell `=` is the same as the row's first; one in bold is two runs that disagree, run 1 / run 2.

### The hatch and the proxy field, on main and on the prototype (`refusals`)

A cell: `attached` (the hatch took it), `made` (the field took it), the refusal's reason, or `condition` for an assertion violation.

| case | X |
|---|---|
| main PROXY | refused owned-option |
| main NOPROXY | refused owned-option |
| main PROXY_CAINFO | refused owned-option |
| main PROXY_CAPATH | refused owned-option |
| main PROXY_CAPATH-clear | refused owned-option |
| main PROXY_SSL_VERIFYPEER | refused owned-option |
| main PROXY_SSL_VERIFYHOST | refused owned-option |
| main HTTPPROXYTUNNEL | attached |
| main SUPPRESS_CONNECT_HEADERS | attached |
| main PROXY_SERVICE_NAME | attached |
| main PROXY_SERVICE_NAME-clear | condition: takes a string |
| main SOCKS5_AUTH | attached |
| main HAPROXYPROTOCOL | attached |
| main HAPROXY_CLIENT_IP | attached |
| main PROXYAUTH | attached |
| main PROXYUSERPWD | attached |
| main PROXYUSERNAME | attached |
| main PROXYPASSWORD | attached |
| main PROXYHEADER | refused owned-option |
| main HEADEROPT | refused owned-option |
| main PRE_PROXY | refused owned-option |
| main PROXYTYPE | refused owned-option |
| main PROXYPORT | refused owned-option |
| main FRESH_CONNECT | refused owned-option |
| main FORBID_REUSE | attached |
| main VERBOSE | attached |
| main CAPATH-clear | refused owned-option |
| main USERAGENT-clear | refused owned-option |
| main field-proxy "http://127.0.0.1:1" | condition: not a proxy value |
| main session-proxy "http://127.0.0.1:1" | condition: not a proxy value |
| main field-proxy environment | made |
| main session-proxy environment | made |
| main field-proxy #f | made |
| main session-proxy #f | made |
| main field-proxy "" | condition: not a proxy value |
| main session-proxy "" | condition: not a proxy value |
| prototype PROXY | refused owned-option |
| prototype NOPROXY | attached |
| prototype PROXY_CAINFO | attached |
| prototype PROXY_CAPATH | attached |
| prototype PROXY_CAPATH-clear | attached |
| prototype PROXY_SSL_VERIFYPEER | attached |
| prototype PROXY_SSL_VERIFYHOST | attached |
| prototype HTTPPROXYTUNNEL | attached |
| prototype SUPPRESS_CONNECT_HEADERS | attached |
| prototype PROXY_SERVICE_NAME | attached |
| prototype PROXY_SERVICE_NAME-clear | attached |
| prototype SOCKS5_AUTH | attached |
| prototype HAPROXYPROTOCOL | attached |
| prototype HAPROXY_CLIENT_IP | attached |
| prototype PROXYAUTH | attached |
| prototype PROXYUSERPWD | attached |
| prototype PROXYUSERNAME | attached |
| prototype PROXYPASSWORD | attached |
| prototype PROXYHEADER | refused owned-option |
| prototype HEADEROPT | refused owned-option |
| prototype PRE_PROXY | refused owned-option |
| prototype PROXYTYPE | refused owned-option |
| prototype PROXYPORT | refused owned-option |
| prototype FRESH_CONNECT | attached |
| prototype FORBID_REUSE | attached |
| prototype VERBOSE | attached |
| prototype CAPATH-clear | refused owned-option |
| prototype USERAGENT-clear | refused owned-option |
| prototype field-proxy "http://127.0.0.1:1" | made |
| prototype session-proxy "http://127.0.0.1:1" | made |
| prototype field-proxy environment | made |
| prototype session-proxy environment | made |
| prototype field-proxy #f | made |
| prototype session-proxy #f | made |
| prototype field-proxy "" | made |
| prototype session-proxy "" | made |

### Item 5: curl_easy_setopt's answer to each proxy TLS setting, on a scratch handle (`setopts`)

A cell: the CURLcode, 0 OK, 4 CURLE_NOT_BUILT_IN, 48 CURLE_UNKNOWN_OPTION; `unknown` when the libcurl knows no option by the name.

| case | X |
|---|---|
| PROXY_CAINFO the ca.pem | 0 |
| PROXY_CAPATH #f | 0 |
| PROXY_CAPATH the cadir | 0 |
| PROXY_CAINFO #f | 0 |
| PROXY_SSL_VERIFYPEER 0 | 0 |
| PROXY_SSL_VERIFYPEER 1 | 0 |
| PROXY_SSL_VERIFYHOST 0 | 0 |
| PROXY_SSL_VERIFYHOST 2 | 0 |
| CAINFO the ca.pem | 0 |
| CAPATH #f | 0 |
| CAPATH the cadir | 0 |
| HAPROXY_CLIENT_IP "10.1.2.3" | 0 |
| NOPROXY "" | 0 |

### Item 2 (a): curl-url-part of each proxy URL, on main's src/ (`i2a`)

A cell: scheme, user, password, host, port, path, query and fragment as curl-url-part answers them (`–` absent; zoneid after the host when present), or the refusal. `<p-open>` is that face's port.

| case | X |
|---|---|
| port-http | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| noport-http | `http` u=– pw=– h=127.0.0.1 port=80 path=/ q=– f=– |
| noport-https | `https` u=– pw=– h=127.0.0.1 port=443 path=/ q=– f=– |
| port80 | `http` u=– pw=– h=127.0.0.1 port=80 path=/ q=– f=– |
| port443 | `https` u=– pw=– h=127.0.0.1 port=443 path=/ q=– f=– |
| upper-scheme | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| no-scheme | url-error reason=bad-scheme code=27 |
| foo | url-error reason=unsupported-scheme code=5 |
| ftp | `ftp` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| socks5 | url-error reason=unsupported-scheme code=5 |
| path-a | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/a q=– f=– |
| path-slash | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| query | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=q=1 f=– |
| query-nopath | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=q=1 f=– |
| fragment | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=f |
| fragment-nopath | `http` u=– pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=f |
| ipv6 | `http` u=– pw=– h=[::1] port=<p-open> path=/ q=– f=– |
| ipv6-zone | `http` u=– pw=– h=[fe80::1]%eth0 port=<p-open> path=/ q=– f=– |
| ipv6-zone-lo | `http` u=– pw=– h=[::1]%lo port=<p-open> path=/ q=– f=– |
| ui-at | `http` u= pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-colon-at | `http` u= pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-u-at | `http` u=u pw=– h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-u-colon-at | `http` u=u pw= h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-colon-p-at | `http` u= pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-u-p-at | `http` u=u pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-user-3A | `http` u=a%3Ab pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-pass-3A | `http` u=u pw=p%3Aq h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-user-0D0A | `http` u=u%0D%0Ax pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-pass-0D0A | `http` u=u pw=p%0D%0Ax h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-user-00 | `http` u=u%00x pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-pass-00 | `http` u=u pw=p%00x h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-user-01 | `http` u=u%01x pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-user-09 | `http` u=u%09x pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-user-1F | `http` u=u%1Fx pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-user-20 | `http` u=u%20x pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-user-7F | `http` u=u%7Fx pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-pass-7F | `http` u=u pw=p%7Fx h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-utf8-pct | `http` u=%C3%A9l%C3%A8ve pw=p%C3%A4ss h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-user-FF | `http` u=u%FFx pw=p h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-pass-FF | `http` u=u pw=p%FFx h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-pct-25 | `http` u=u%25x pw=p%25q h=127.0.0.1 port=<p-open> path=/ q=– f=– |
| ui-utf8-raw | `http` u=\xc3\xa9l\xc3\xa8ve pw=p\xc3\xa4ss h=127.0.0.1 port=<p-open> path=/ q=– f=– |

The URLs, in order: `port-http` http://127.0.0.1:<p-open>; `noport-http` http://127.0.0.1; `noport-https` https://127.0.0.1; `port80` http://127.0.0.1:80; `port443` https://127.0.0.1:443; `upper-scheme` HTTP://127.0.0.1:<p-open>; `no-scheme` 127.0.0.1:<p-open>; `foo` foo://127.0.0.1:<p-open>; `ftp` ftp://127.0.0.1:<p-open>; `socks5` socks5://127.0.0.1:<p-open>; `path-a` http://127.0.0.1:<p-open>/a; `path-slash` http://127.0.0.1:<p-open>/; `query` http://127.0.0.1:<p-open>/?q=1; `query-nopath` http://127.0.0.1:<p-open>?q=1; `fragment` http://127.0.0.1:<p-open>/#f; `fragment-nopath` http://127.0.0.1:<p-open>#f; `ipv6` http://[::1]:<p-open>; `ipv6-zone` http://[fe80::1%25eth0]:<p-open>; `ipv6-zone-lo` http://[::1%25lo]:<p-open>; `ui-at` http://@127.0.0.1:<p-open>; `ui-colon-at` http://:@127.0.0.1:<p-open>; `ui-u-at` http://u@127.0.0.1:<p-open>; `ui-u-colon-at` http://u:@127.0.0.1:<p-open>; `ui-colon-p-at` http://:p@127.0.0.1:<p-open>; `ui-u-p-at` http://u:p@127.0.0.1:<p-open>; `ui-user-3A` http://a%3Ab:p@127.0.0.1:<p-open>; `ui-pass-3A` http://u:p%3Aq@127.0.0.1:<p-open>; `ui-user-0D0A` http://u%0D%0Ax:p@127.0.0.1:<p-open>; `ui-pass-0D0A` http://u:p%0D%0Ax@127.0.0.1:<p-open>; `ui-user-00` http://u%00x:p@127.0.0.1:<p-open>; `ui-pass-00` http://u:p%00x@127.0.0.1:<p-open>; `ui-user-01` http://u%01x:p@127.0.0.1:<p-open>; `ui-user-09` http://u%09x:p@127.0.0.1:<p-open>; `ui-user-1F` http://u%1Fx:p@127.0.0.1:<p-open>; `ui-user-20` http://u%20x:p@127.0.0.1:<p-open>; `ui-user-7F` http://u%7Fx:p@127.0.0.1:<p-open>; `ui-pass-7F` http://u:p%7Fx@127.0.0.1:<p-open>; `ui-utf8-pct` http://%C3%A9l%C3%A8ve:p%C3%A4ss@127.0.0.1:<p-open>; `ui-user-FF` http://u%FFx:p@127.0.0.1:<p-open>; `ui-pass-FF` http://u:p%FFx@127.0.0.1:<p-open>; `ui-pct-25` http://u%25x:p%25q@127.0.0.1:<p-open>; `ui-utf8-raw` http://\xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss@127.0.0.1:<p-open>.

### Item 1: a named proxy beside the environment (`i1`)

The named proxy is `p-open`; the variables name `p-other`. A cell: where the request went (`p-open`, `p-other`, or `direct`: only the origin logged it), the form (`abs`, `CONNECT`), the response, and for h2 the ALPN the origin chose.

| case | X |
|---|---|
| none absolute-http noproxy=empty | p-open abs; 200 |
| none absolute-http noproxy=unset | p-open abs; 200 |
| none connect-https noproxy=empty | p-open CONNECT; 200 |
| none connect-https noproxy=unset | p-open CONNECT; 200 |
| none connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 |
| none connect-h2 noproxy=unset | p-open CONNECT; 200 h2 alpn=h2 |
| none direct-http noproxy=control | direct; 200 |
| none environment-http noproxy=control | direct; 200 |
| none environment-https noproxy=control | direct; 200 |
| no_proxy-host absolute-http noproxy=empty | p-open abs; 200 |
| no_proxy-host absolute-http noproxy=unset | direct; 200 |
| no_proxy-host connect-https noproxy=empty | p-open CONNECT; 200 |
| no_proxy-host connect-https noproxy=unset | direct; 200 |
| no_proxy-host connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 |
| no_proxy-host connect-h2 noproxy=unset | direct; 200 h2 alpn=h2 |
| no_proxy-host direct-http noproxy=control | direct; 200 |
| no_proxy-host environment-http noproxy=control | direct; 200 |
| no_proxy-host environment-https noproxy=control | direct; 200 |
| NO_PROXY-host absolute-http noproxy=empty | p-open abs; 200 |
| NO_PROXY-host absolute-http noproxy=unset | direct; 200 |
| NO_PROXY-host connect-https noproxy=empty | p-open CONNECT; 200 |
| NO_PROXY-host connect-https noproxy=unset | direct; 200 |
| NO_PROXY-host connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 |
| NO_PROXY-host connect-h2 noproxy=unset | direct; 200 h2 alpn=h2 |
| NO_PROXY-host direct-http noproxy=control | direct; 200 |
| NO_PROXY-host environment-http noproxy=control | direct; 200 |
| NO_PROXY-host environment-https noproxy=control | direct; 200 |
| no_proxy-star absolute-http noproxy=empty | p-open abs; 200 |
| no_proxy-star absolute-http noproxy=unset | direct; 200 |
| no_proxy-star connect-https noproxy=empty | p-open CONNECT; 200 |
| no_proxy-star connect-https noproxy=unset | direct; 200 |
| no_proxy-star connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 |
| no_proxy-star connect-h2 noproxy=unset | direct; 200 h2 alpn=h2 |
| no_proxy-star direct-http noproxy=control | direct; 200 |
| no_proxy-star environment-http noproxy=control | direct; 200 |
| no_proxy-star environment-https noproxy=control | direct; 200 |
| proxy-vars absolute-http noproxy=empty | p-open abs; 200 |
| proxy-vars absolute-http noproxy=unset | p-open abs; 200 |
| proxy-vars connect-https noproxy=empty | p-open CONNECT; 200 |
| proxy-vars connect-https noproxy=unset | p-open CONNECT; 200 |
| proxy-vars connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 |
| proxy-vars connect-h2 noproxy=unset | p-open CONNECT; 200 h2 alpn=h2 |
| proxy-vars direct-http noproxy=control | direct; 200 |
| proxy-vars environment-http noproxy=control | p-other abs; 200 |
| proxy-vars environment-https noproxy=control | p-other CONNECT; 200 |
| all_proxy absolute-http noproxy=empty | p-open abs; 200 |
| all_proxy absolute-http noproxy=unset | p-open abs; 200 |
| all_proxy connect-https noproxy=empty | p-open CONNECT; 200 |
| all_proxy connect-https noproxy=unset | p-open CONNECT; 200 |
| all_proxy connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 |
| all_proxy connect-h2 noproxy=unset | p-open CONNECT; 200 h2 alpn=h2 |
| all_proxy direct-http noproxy=control | direct; 200 |
| all_proxy environment-http noproxy=control | p-other abs; 200 |
| all_proxy environment-https noproxy=control | p-other CONNECT; 200 |
| proxy-vars-no_proxy-host absolute-http noproxy=empty | p-open abs; 200 |
| proxy-vars-no_proxy-host absolute-http noproxy=unset | direct; 200 |
| proxy-vars-no_proxy-host connect-https noproxy=empty | p-open CONNECT; 200 |
| proxy-vars-no_proxy-host connect-https noproxy=unset | direct; 200 |
| proxy-vars-no_proxy-host connect-h2 noproxy=empty | p-open CONNECT; 200 h2 alpn=h2 |
| proxy-vars-no_proxy-host connect-h2 noproxy=unset | direct; 200 h2 alpn=h2 |
| proxy-vars-no_proxy-host direct-http noproxy=control | direct; 200 |
| proxy-vars-no_proxy-host environment-http noproxy=control | direct; 200 |
| proxy-vars-no_proxy-host environment-https noproxy=control | direct; 200 |

Each child's environment, its first line, on every lane-run (the libcurl path and the run's temporary directory left out), and how many lane-runs printed it:

- named `none`: `env 1 CHEZ_CURL_LIBCURL=…` (2)
- named `no_proxy-host`: `env 2 CHEZ_CURL_LIBCURL=… no_proxy=127.0.0.1` (2)
- named `NO_PROXY-host`: `env 2 CHEZ_CURL_LIBCURL=… NO_PROXY=127.0.0.1` (2)
- named `no_proxy-star`: `env 2 CHEZ_CURL_LIBCURL=… no_proxy=*` (2)
- named `proxy-vars`: `env 3 CHEZ_CURL_LIBCURL=… http_proxy=http://127.0.0.1:<p-other> https_proxy=http://127.0.0.1:<p-other>` (2)
- named `all_proxy`: `env 2 CHEZ_CURL_LIBCURL=… all_proxy=http://127.0.0.1:<p-other>` (2)
- named `proxy-vars-no_proxy-host`: `env 4 CHEZ_CURL_LIBCURL=… http_proxy=http://127.0.0.1:<p-other> https_proxy=http://127.0.0.1:<p-other> no_proxy=127.0.0.1` (2)
- tlsenv `certfile-ca`: `env 2 CHEZ_CURL_LIBCURL=… SSL_CERT_FILE=TMP/pki/ca.pem` (2)
- tlsenv `certfile-other`: `env 2 CHEZ_CURL_LIBCURL=… SSL_CERT_FILE=TMP/pki/other-ca.pem` (2)
- tlsenv `certdir-cadir`: `env 2 CHEZ_CURL_LIBCURL=… SSL_CERT_DIR=TMP/pki/cadir` (2)

### Item 2 (b): what goes on the wire for each userinfo form, through `p-open` (`i2b`)

A cell: the outcome, then the `Proxy-Authorization` p-open decoded, user:password with each byte outside `!`..`~` as `\xHH`, or `–` for none sent; `no request` when no face got one; `DIRECT` when the origin got the request straight, and the proxy nothing.

| case | X |
|---|---|
| form=none transport=absolute | 200; – |
| form=none transport=connect | 200; – |
| form=at transport=absolute | 200; : |
| form=at transport=connect | 200; : |
| form=colon-at transport=absolute | 200; : |
| form=colon-at transport=connect | 200; : |
| form=u-at transport=absolute | 200; u: |
| form=u-at transport=connect | 200; u: |
| form=u-colon-at transport=absolute | 200; u: |
| form=u-colon-at transport=connect | 200; u: |
| form=colon-p-at transport=absolute | 200; :p |
| form=colon-p-at transport=connect | 200; :p |
| form=u-p-at transport=absolute | 200; u:p |
| form=u-p-at transport=connect | 200; u:p |
| form=user-3A transport=absolute | 200; a:b:p |
| form=user-3A transport=connect | 200; a:b:p |
| form=pass-3A transport=absolute | 200; u:p:q |
| form=pass-3A transport=connect | 200; u:p:q |
| form=user-0D0A transport=absolute | **3 – sent=0; no request / 7 – sent=0; no request** |
| form=user-0D0A transport=connect | 3 – sent=0; no request |
| form=pass-0D0A transport=absolute | 3 – sent=0; no request |
| form=pass-0D0A transport=connect | 3 – sent=0; no request |
| form=user-00 transport=absolute | 3 – sent=0; no request |
| form=user-00 transport=connect | 3 – sent=0; no request |
| form=pass-00 transport=absolute | 3 – sent=0; no request |
| form=pass-00 transport=connect | 3 – sent=0; no request |
| form=user-01 transport=absolute | 3 – sent=0; no request |
| form=user-01 transport=connect | 3 – sent=0; no request |
| form=user-09 transport=absolute | 3 – sent=0; no request |
| form=user-09 transport=connect | 3 – sent=0; no request |
| form=user-1F transport=absolute | 3 – sent=0; no request |
| form=user-1F transport=connect | 3 – sent=0; no request |
| form=user-20 transport=absolute | 200; u\x20x:p |
| form=user-20 transport=connect | 200; u\x20x:p |
| form=user-7F transport=absolute | 200; u\x7fx:p |
| form=user-7F transport=connect | 200; u\x7fx:p |
| form=pass-7F transport=absolute | 200; u:p\x7fx |
| form=pass-7F transport=connect | 200; u:p\x7fx |
| form=utf8-pct transport=absolute | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss |
| form=utf8-pct transport=connect | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss |
| form=user-FF transport=absolute | 200; u\xffx:p |
| form=user-FF transport=connect | 200; u\xffx:p |
| form=pass-FF transport=absolute | 200; u:p\xffx |
| form=pass-FF transport=connect | 200; u:p\xffx |
| form=pct-25 transport=absolute | 200; u%x:p%q |
| form=pct-25 transport=connect | 200; u%x:p%q |
| form=utf8-raw transport=absolute | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss |
| form=utf8-raw transport=connect | 200; \xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss |
| form=noscheme-u-p transport=absolute | 200; u:p |
| form=noscheme-u-p transport=connect | 200; u:p |

### Item 2 (c): the port a proxy URL names, and none (Docker, root) (`i2c`)

Listeners: `p80` on 80 and `p1080` on 1080, plaintext open proxies; `tp443` on 443, an open proxy over TLS. A cell: the face that got the connection, and the outcome. Lane X did not run it: its stand-in has no low ports.

| case |  |
|---||

### Item 3: the pooled tunnel (`i3`)

Two transfers on one engine through one proxy that takes Basic for alice and bob, the first as alice. `sequential`: the second submitted once the first is done; `batch`: both submitted in one hold of the engine. A cell: `reused` when the second request rode the first's origin connection (for a tunnel: inside the first's tunnel; for absolute form: on the first's proxy connection, whose upstream it is), else `new`; then the second's outcome; then each request the proxy got for the second, with the credentials it carried (`no request`: the proxy got none for it).

| case | X |
|---|---|
| mode=connect-https order=sequential flags=plain second=same | reused; 200; no request |
| mode=connect-https order=sequential flags=plain second=other | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=connect-https order=sequential flags=plain second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-https order=sequential flags=plain second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-https order=sequential flags=fresh-second second=same | new; 200; CONNECT PA=alice:s3cret→200 |
| mode=connect-https order=sequential flags=fresh-second second=other | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=connect-https order=sequential flags=fresh-second second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-https order=sequential flags=fresh-second second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-https order=sequential flags=forbid-first second=same | new; 200; CONNECT PA=alice:s3cret→200 |
| mode=connect-https order=sequential flags=forbid-first second=other | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=connect-https order=sequential flags=forbid-first second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-https order=sequential flags=forbid-first second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=tunnel-http order=sequential flags=plain second=same | reused; 200; no request |
| mode=tunnel-http order=sequential flags=plain second=other | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=tunnel-http order=sequential flags=plain second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=tunnel-http order=sequential flags=plain second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=tunnel-http order=sequential flags=fresh-second second=same | new; 200; CONNECT PA=alice:s3cret→200 |
| mode=tunnel-http order=sequential flags=fresh-second second=other | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=tunnel-http order=sequential flags=fresh-second second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=tunnel-http order=sequential flags=fresh-second second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=tunnel-http order=sequential flags=forbid-first second=same | new; 200; CONNECT PA=alice:s3cret→200 |
| mode=tunnel-http order=sequential flags=forbid-first second=other | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=tunnel-http order=sequential flags=forbid-first second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=tunnel-http order=sequential flags=forbid-first second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=absolute-http order=sequential flags=plain second=same | reused; 200; abs PA=alice:s3cret |
| mode=absolute-http order=sequential flags=plain second=other | new; 200; abs PA=bob:hunter2 |
| mode=absolute-http order=sequential flags=plain second=wrong | new; 407; abs PA=alice:wrong→407 |
| mode=absolute-http order=sequential flags=plain second=none | new; 407; abs PA=–→407 |
| mode=absolute-http order=sequential flags=fresh-second second=same | new; 200; abs PA=alice:s3cret |
| mode=absolute-http order=sequential flags=fresh-second second=other | new; 200; abs PA=bob:hunter2 |
| mode=absolute-http order=sequential flags=fresh-second second=wrong | new; 407; abs PA=alice:wrong→407 |
| mode=absolute-http order=sequential flags=fresh-second second=none | new; 407; abs PA=–→407 |
| mode=absolute-http order=sequential flags=forbid-first second=same | new; 200; abs PA=alice:s3cret |
| mode=absolute-http order=sequential flags=forbid-first second=other | new; 200; abs PA=bob:hunter2 |
| mode=absolute-http order=sequential flags=forbid-first second=wrong | new; 407; abs PA=alice:wrong→407 |
| mode=absolute-http order=sequential flags=forbid-first second=none | new; 407; abs PA=–→407 |
| mode=https-proxy-connect-https order=sequential flags=plain second=same | reused; 200; no request |
| mode=https-proxy-connect-https order=sequential flags=plain second=other | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=https-proxy-connect-https order=sequential flags=plain second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=https-proxy-connect-https order=sequential flags=plain second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=same | new; 200; CONNECT PA=alice:s3cret→200 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=other | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=https-proxy-connect-https order=sequential flags=fresh-second second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=same | new; 200; CONNECT PA=alice:s3cret→200 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=other | new; 200; CONNECT PA=bob:hunter2→200 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=https-proxy-connect-https order=sequential flags=forbid-first second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=https-proxy-absolute-http order=sequential flags=plain second=same | new; 200; abs PA=alice:s3cret |
| mode=https-proxy-absolute-http order=sequential flags=plain second=other | new; 200; abs PA=bob:hunter2 |
| mode=https-proxy-absolute-http order=sequential flags=plain second=wrong | new; 407; abs PA=alice:wrong→407 |
| mode=https-proxy-absolute-http order=sequential flags=plain second=none | new; 407; abs PA=–→407 |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=same | new; 200; abs PA=alice:s3cret |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=other | new; 200; abs PA=bob:hunter2 |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=wrong | new; 407; abs PA=alice:wrong→407 |
| mode=https-proxy-absolute-http order=sequential flags=fresh-second second=none | new; 407; abs PA=–→407 |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=same | new; 200; abs PA=alice:s3cret |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=other | new; 200; abs PA=bob:hunter2 |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=wrong | new; 407; abs PA=alice:wrong→407 |
| mode=https-proxy-absolute-http order=sequential flags=forbid-first second=none | new; 407; abs PA=–→407 |
| mode=connect-h2 order=sequential flags=plain second=same | reused stream=3; 200 h2; no request |
| mode=connect-h2 order=sequential flags=plain second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 |
| mode=connect-h2 order=sequential flags=plain second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=sequential flags=plain second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=sequential flags=fresh-second second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 |
| mode=connect-h2 order=sequential flags=fresh-second second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 |
| mode=connect-h2 order=sequential flags=fresh-second second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=sequential flags=fresh-second second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=sequential flags=forbid-first second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 |
| mode=connect-h2 order=sequential flags=forbid-first second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 |
| mode=connect-h2 order=sequential flags=forbid-first second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=sequential flags=forbid-first second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=batch flags=plain second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 |
| mode=connect-h2 order=batch flags=plain second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 |
| mode=connect-h2 order=batch flags=plain second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=batch flags=plain second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=batch flags=fresh-second second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 |
| mode=connect-h2 order=batch flags=fresh-second second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 |
| mode=connect-h2 order=batch flags=fresh-second second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=batch flags=fresh-second second=none | new; 7 connect sent=0; CONNECT PA=–→407 |
| mode=connect-h2 order=batch flags=forbid-first second=same | new stream=1; 200 h2; CONNECT PA=alice:s3cret→200 |
| mode=connect-h2 order=batch flags=forbid-first second=other | new stream=1; 200 h2; CONNECT PA=bob:hunter2→200 |
| mode=connect-h2 order=batch flags=forbid-first second=wrong | new; 7 connect sent=0; CONNECT PA=alice:wrong→407 |
| mode=connect-h2 order=batch flags=forbid-first second=none | new; 7 connect sent=0; CONNECT PA=–→407 |

### Item 4: a refused CONNECT, and the same proxies by absolute form (`i4`)

A cell: the status chez-curl's response carries, or the failure: code, class, request size; then the error buffer.

| case | X |
|---|---|
| proxy=403 transport=absolute | 403 |
| proxy=403 transport=connect | 7 connect sent=0; "CONNECT tunnel failed, response 403" |
| proxy=407-none transport=absolute | 407 |
| proxy=407-none transport=connect | 7 connect sent=0; "CONNECT tunnel failed, response 407" |
| proxy=407-wrong transport=absolute | 407 |
| proxy=407-wrong transport=connect | 7 connect sent=0; "CONNECT tunnel failed, response 407" |
| proxy=502 transport=absolute | 502 |
| proxy=502 transport=connect | 7 connect sent=0; "CONNECT tunnel failed, response 502" |
| proxy=close transport=absolute | 52 send-receive sent=120; "Empty reply from server" |
| proxy=close transport=connect | 56 send-receive sent=0; "Proxy CONNECT aborted" |
| proxy=partial transport=absolute | 52 send-receive sent=121; "Empty reply from server" |
| proxy=partial transport=connect | 56 send-receive sent=0; "Proxy CONNECT aborted" |
| proxy=refused transport=absolute | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <o-raw> via 127.0.0.1 after N ms: Could not connect to server" |
| proxy=refused transport=connect | 7 connect sent=0; "Failed to connect to 127.0.0.1 port <o-tls> via 127.0.0.1 after N ms: Could not connect to server" |

### Item 4: the high level's retry through each (`i4high`)

`http-get` and `http-post`, with the policy (attempts 3, the default statuses and methods, backoff 20 ms, jitter off) and with none. A cell: what the call answered or raised (`transfers=` its `&http-exchange`'s count), then the requests the proxy logged.

| case | X |
|---|---|
| proxy=403 transport=absolute method=get retry=policy | 403; proxy got 1 |
| proxy=403 transport=absolute method=get retry=none | 403; proxy got 1 |
| proxy=403 transport=absolute method=post retry=policy | 403; proxy got 1 |
| proxy=403 transport=absolute method=post retry=none | 403; proxy got 1 |
| proxy=403 transport=connect method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=403 transport=connect method=get retry=none | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=403 transport=connect method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=403 transport=connect method=post retry=none | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=407-none transport=absolute method=get retry=policy | 407; proxy got 1 |
| proxy=407-none transport=absolute method=get retry=none | 407; proxy got 1 |
| proxy=407-none transport=absolute method=post retry=policy | 407; proxy got 1 |
| proxy=407-none transport=absolute method=post retry=none | 407; proxy got 1 |
| proxy=407-none transport=connect method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=407-none transport=connect method=get retry=none | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=407-none transport=connect method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=407-none transport=connect method=post retry=none | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=407-wrong transport=absolute method=get retry=policy | 407; proxy got 1 |
| proxy=407-wrong transport=absolute method=get retry=none | 407; proxy got 1 |
| proxy=407-wrong transport=absolute method=post retry=policy | 407; proxy got 1 |
| proxy=407-wrong transport=absolute method=post retry=none | 407; proxy got 1 |
| proxy=407-wrong transport=connect method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=407-wrong transport=connect method=get retry=none | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=407-wrong transport=connect method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=407-wrong transport=connect method=post retry=none | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=502 transport=absolute method=get retry=policy | 502; proxy got 1 |
| proxy=502 transport=absolute method=get retry=none | 502; proxy got 1 |
| proxy=502 transport=absolute method=post retry=policy | 502; proxy got 1 |
| proxy=502 transport=absolute method=post retry=none | 502; proxy got 1 |
| proxy=502 transport=connect method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=502 transport=connect method=get retry=none | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=502 transport=connect method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 3 |
| proxy=502 transport=connect method=post retry=none | 7 connect sent=0 transfers=1; proxy got 1 |
| proxy=close transport=absolute method=get retry=policy | 52 send-receive sent=121 transfers=3; proxy got 3 |
| proxy=close transport=absolute method=get retry=none | 52 send-receive sent=121 transfers=1; proxy got 1 |
| proxy=close transport=absolute method=post retry=policy | 52 send-receive sent=204 transfers=1; proxy got 1 |
| proxy=close transport=absolute method=post retry=none | 52 send-receive sent=204 transfers=1; proxy got 1 |
| proxy=close transport=connect method=get retry=policy | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=close transport=connect method=get retry=none | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=close transport=connect method=post retry=policy | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=close transport=connect method=post retry=none | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=partial transport=absolute method=get retry=policy | 52 send-receive sent=121 transfers=3; proxy got 3 |
| proxy=partial transport=absolute method=get retry=none | 52 send-receive sent=121 transfers=1; proxy got 1 |
| proxy=partial transport=absolute method=post retry=policy | 52 send-receive sent=204 transfers=1; proxy got 1 |
| proxy=partial transport=absolute method=post retry=none | 52 send-receive sent=204 transfers=1; proxy got 1 |
| proxy=partial transport=connect method=get retry=policy | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=partial transport=connect method=get retry=none | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=partial transport=connect method=post retry=policy | 56 send-receive sent=0 transfers=3; proxy got 3 |
| proxy=partial transport=connect method=post retry=none | 56 send-receive sent=0 transfers=1; proxy got 1 |
| proxy=refused transport=absolute method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 0 |
| proxy=refused transport=absolute method=get retry=none | 7 connect sent=0 transfers=1; proxy got 0 |
| proxy=refused transport=absolute method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 0 |
| proxy=refused transport=absolute method=post retry=none | 7 connect sent=0 transfers=1; proxy got 0 |
| proxy=refused transport=connect method=get retry=policy | 7 connect sent=0 transfers=3; proxy got 0 |
| proxy=refused transport=connect method=get retry=none | 7 connect sent=0 transfers=1; proxy got 0 |
| proxy=refused transport=connect method=post retry=policy | 7 connect sent=0 transfers=3; proxy got 0 |
| proxy=refused transport=connect method=post retry=none | 7 connect sent=0 transfers=1; proxy got 0 |

### Item 5: the proxy's leaves, verification on and off (`i5leaves`)

An `https://` proxy with `PROXY_CAINFO` the run CA and `PROXY_CAPATH` cleared; `off` adds `PROXY_SSL_VERIFYPEER` 0 and `PROXY_SSL_VERIFYHOST` 0. A cell: the outcome; for a failure, whether the proxy logged a request.

| case | X |
|---|---|
| leaf=good verify=on transport=absolute | 200 |
| leaf=good verify=on transport=connect | 200 |
| leaf=good verify=off transport=absolute | 200 |
| leaf=good verify=off transport=connect | 200 |
| leaf=expired verify=on transport=absolute | 60 tls sent=0; proxy requests 0 |
| leaf=expired verify=on transport=connect | 60 tls sent=0; proxy requests 0 |
| leaf=expired verify=off transport=absolute | 200 |
| leaf=expired verify=off transport=connect | 200 |
| leaf=wrong-host verify=on transport=absolute | 60 tls sent=0; proxy requests 0 |
| leaf=wrong-host verify=on transport=connect | 60 tls sent=0; proxy requests 0 |
| leaf=wrong-host verify=off transport=absolute | 200 |
| leaf=wrong-host verify=off transport=connect | 200 |
| leaf=untrusted verify=on transport=absolute | 60 tls sent=0; proxy requests 0 |
| leaf=untrusted verify=on transport=connect | 60 tls sent=0; proxy requests 0 |
| leaf=untrusted verify=off transport=absolute | 200 |
| leaf=untrusted verify=off transport=connect | 200 |

### Item 5: the origin's TLS settings against the proxy's (`i5sep`)

Through `tp-good` to the `o-tls` origin by CONNECT. `proxy-bad`: `PROXY_CAINFO` the other CA; `origin-bad`: the origin's `ca-file` the other CA; `noverify`: that side's verification off. A cell: the outcome; which side refused it (`at proxy`: no CONNECT logged; `at origin`: the CONNECT passed).

| case | X |
|---|---|
| sep=both-good | 200 |
| sep=origin-bad | 60 tls sent=0; at origin |
| sep=proxy-bad | 60 tls sent=0; at proxy |
| sep=origin-noverify-proxy-bad | 60 tls sent=0; at proxy |
| sep=proxy-noverify-origin-bad | 60 tls sent=0; at origin |
| sep=both-off | 200 |
| sep=origin-verify-off-proxy-good | 200 |

### Item 5: SSL_CERT_FILE and SSL_CERT_DIR beside a PROXY_CAINFO, in a child's environment (`i5env`)

An `http://` origin through `tp-good`. `certfile-ca`: `SSL_CERT_FILE` the run CA; `certfile-other`: the other CA; `certdir-cadir`: `SSL_CERT_DIR` the run CA's hashed directory. `run-ca` and `other-ca`: `PROXY_CAINFO`, with `PROXY_CAPATH` cleared; `other-ca-capath-default`: not cleared.

| case | X |
|---|---|
| certfile-ca proxyca=run-ca | 200 |
| certfile-ca proxyca=other-ca | 200 |
| certfile-ca proxyca=other-ca-capath-default | 200 |
| certfile-other proxyca=run-ca | 60 tls sent=0 |
| certfile-other proxyca=other-ca | 60 tls sent=0 |
| certfile-other proxyca=other-ca-capath-default | 60 tls sent=0 |
| certdir-cadir proxyca=run-ca | 200 |
| certdir-cadir proxyca=other-ca | 200 |
| certdir-cadir proxyca=other-ca-capath-default | 200 |

### Item 5: TLS inside TLS, ten times each per run (`i5stall`)

`timeout-ms` 10,000, through `tp-good` (`https-via-http`: through plaintext `p-open`). A cell: each outcome and how many of the ten gave it.

| case | X |
|---|---|
| case=https-via-https | 10× 200 |
| case=http-via-https | 10× 200 |
| case=h2-via-https | 10× 200 h2 |
| case=https-via-http | 10× 200 |

### Item 6: the twins, beside a named proxy (`i6`)

Through `p-open`, the caller's headers `X-Caller: m7s3` and `Proxy-Authorization: Basic YWxpY2U6czNjcmV0`. A cell: each request in the order the stand-in logged it, `FACE: FORM` with the header names it carried (not Host, Accept), `PA=` its Proxy-Authorization; a PROXY protocol line and where it arrived; then the response chez-curl read: status, its header names, and for a streamed one the head's.

| case | X |
|---|---|
| twin=base transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] |
| twin=base transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] |
| twin=base transport=connect-stream | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] head 200 [X-Origin,Content-Length] |
| twin=HTTPPROXYTUNNEL-1 transport=absolute | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] |
| twin=HTTPPROXYTUNNEL-1 transport=absolute-stream | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] head 200 [X-Origin,Content-Length] |
| twin=HTTPPROXYTUNNEL-1 transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] |
| twin=HTTPPROXYTUNNEL-0 transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] |
| twin=HTTPPROXYTUNNEL-0 transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] |
| twin=SUPPRESS_CONNECT_HEADERS transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] |
| twin=SUPPRESS_CONNECT_HEADERS transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] |
| twin=SUPPRESS_CONNECT_HEADERS transport=connect-stream | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] head 200 [X-Origin,Content-Length] |
| twin=SUPPRESS_CONNECT_HEADERS-tunnel transport=absolute | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] |
| twin=SUPPRESS_CONNECT_HEADERS-tunnel transport=absolute-stream | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] head 200 [X-Origin,Content-Length] |
| twin=PROXY_SERVICE_NAME transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] |
| twin=PROXY_SERVICE_NAME transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] |
| twin=SOCKS5_AUTH transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller] → 200 [X-Origin,Content-Length] |
| twin=SOCKS5_AUTH transport=connect | p-open: CONNECT PA=– [Proxy-Connection] ; o-tls: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization] → 200 [X-Origin,Content-Length] |
| twin=HAPROXYPROTOCOL transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller]; PROXY line at p-open: PROXY TCP4 127.0.0.1 127.0.0.1 # <p-open> → 200 [X-Origin,Content-Length] |
| twin=HAPROXYPROTOCOL transport=connect | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "GnuTLS, handshake failed: The TLS connection was non-properly terminated." |
| twin=HAPROXYPROTOCOL-tunnel transport=absolute | p-open: CONNECT PA=– [Proxy-Connection] ; o-raw: GET (tunnel) PA=alice:s3cret [X-Caller,Proxy-Authorization]; PROXY line at o-raw: PROXY TCP4 127.0.0.1 127.0.0.1 # <p-open>; PROXY line inside the tunnel → 200 [X-Origin,Content-Length] |
| twin=HAPROXY_CLIENT_IP transport=absolute | p-open: GET abs PA=alice:s3cret [Proxy-Connection,X-Caller,Proxy-Authorization] ; o-raw: GET (forwarded) [X-Caller]; PROXY line at p-open: PROXY TCP4 10.1.2.3 10.1.2.3 # <p-open> → 200 [X-Origin,Content-Length] |
| twin=HAPROXY_CLIENT_IP transport=connect | p-open: CONNECT PA=– [Proxy-Connection]; PROXY line inside the tunnel → 35 tls sent=0 "GnuTLS, handshake failed: The TLS connection was non-properly terminated." |

### Item 7: prior knowledge to the h2c origin through a named proxy (`i7`)

A cell: each request the stand-in logged (`h2 GET`: an HTTP/2 stream), then the response's status and version.

| case | X |
|---|---|
| case=direct | o-h2c: h2 GET → 200 ⇒ 200 h2 |
| case=plain-proxy | p-open: GET abs PA=– → 200 ⇒ 200 |
| case=tunnel | p-open: CONNECT PA=– → 200 ; o-h2c: h2 GET (tunnel) → 200 ⇒ 200 h2 |

### Item 8: the high level's proxy, hop by hop (`i8`)

The session's proxy is `p-basic` as alice; `call-proxy-other` names it as bob; credentials are `ouser`/`opass` at the origin. A cell: each request in the order the stand-in logged it, `FACE: FORM`, `(tunnel)` or `(forwarded)` for an origin reached through the proxy, `PA=` the Proxy-Authorization the proxy decoded, `A=` the Authorization the origin got, `→` its answer; then what the call answered.

| case | X |
|---|---|
| case=session-proxy origin=http to=- scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 200 ⇒ 200 |
| case=session-proxy origin=https to=- scheme=- | p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) → 200 ⇒ 200 |
| case=call-proxy-other origin=http to=- scheme=- | p-basic: GET abs PA=bob:hunter2 ; o-raw: GET (forwarded) → 200 ⇒ 200 |
| case=call-proxy-other origin=https to=- scheme=- | p-basic: CONNECT PA=bob:hunter2 → 200 ; o-tls: GET (tunnel) → 200 ⇒ 200 |
| case=call-proxy-none origin=http to=- scheme=- | o-raw: GET → 200 ⇒ 200 |
| case=call-proxy-environment origin=http to=- scheme=- | o-raw: GET → 200 ⇒ 200 |
| case=call-proxy-on-none-session origin=http to=- scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 200 ⇒ 200 |
| case=redirect origin=- to=same-origin scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 302 ; p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 200 ⇒ 200 after 302 |
| case=redirect origin=- to=other-http scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 302 ; p-basic: GET abs PA=alice:s3cret ; o-raw2: GET (forwarded) → 200 ⇒ 200 after 302 |
| case=redirect origin=- to=other-https scheme=- | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 302 ; p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) → 200 ⇒ 200 after 302 |
| case=credentials origin=http to=- scheme=basic | p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 200 ⇒ 200 |
| case=credentials origin=https to=- scheme=basic | p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) A=Basic ouser:opass → 200 ⇒ 200 |
| case=credentials origin=http to=- scheme=digest | p-basic: GET abs PA=alice:s3cret ; o-raw: GET (forwarded) → 401 ; p-basic: GET abs PA=alice:s3cret A=Digest ; o-raw: GET (forwarded) A=Digest → 200 ⇒ 200 |
| case=credentials origin=https to=- scheme=digest | p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) → 401 ; o-tls: GET (tunnel) A=Digest → 200 ⇒ 200 |
| case=credentials-redirect origin=- to=same-origin scheme=basic | p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 302 ; p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 200 ⇒ 200 after 302 |
| case=credentials-redirect origin=- to=other-http scheme=basic | p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 302 ; p-basic: GET abs PA=alice:s3cret ; o-raw2: GET (forwarded) → 200 ⇒ 200 after 302 |
| case=credentials-redirect origin=- to=other-https scheme=basic | p-basic: GET abs PA=alice:s3cret A=Basic ouser:opass ; o-raw: GET (forwarded) A=Basic ouser:opass → 302 ; p-basic: CONNECT PA=alice:s3cret → 200 ; o-tls: GET (tunnel) → 200 ⇒ 200 after 302 |

### Item 9: REQUEST_SIZE of proxied transfers (`i9`)

`limit=none`: the transfer as it is, its outcome; `limit=1`: the same request with `body-limit` 1, which fails 63 once the response head says its length, after the whole request went: its `sent=` is `REQUEST_SIZE`. Then the bytes the stand-in got from libcurl: each head's length, and the body's, at the proxy and at the origin (through a tunnel; a forwarded request is the proxy's).

| case | X |
|---|---|
| route=direct-http method=get limit=none | 200; origin 65 |
| route=direct-http method=get limit=1 | 63 too-large sent=65; origin 65 |
| route=direct-http method=post limit=none | 200; origin 86+62 |
| route=direct-http method=post limit=1 | 63 too-large sent=148; origin 86+62 |
| route=direct-https method=get limit=none | 200; origin 65 |
| route=direct-https method=get limit=1 | 63 too-large sent=65; origin 65 |
| route=direct-https method=post limit=none | 200; origin 86+62 |
| route=direct-https method=post limit=1 | 63 too-large sent=148; origin 86+62 |
| route=absolute-open method=get limit=none | 200; proxy 117 |
| route=absolute-open method=get limit=1 | 63 too-large sent=118; proxy 118 |
| route=absolute-open method=post limit=none | 200; proxy 139+62 |
| route=absolute-open method=post limit=1 | 63 too-large sent=201; proxy 139+62 |
| route=connect-open method=get limit=none | 200; proxy 89, origin 66 |
| route=connect-open method=get limit=1 | 63 too-large sent=66; proxy 89, origin 66 |
| route=connect-open method=post limit=none | 200; proxy 89, origin 87+62 |
| route=connect-open method=post limit=1 | 63 too-large sent=149; proxy 89, origin 87+62 |
| route=absolute-basic method=get limit=none | 200; proxy 163 |
| route=absolute-basic method=get limit=1 | 63 too-large sent=163; proxy 163 |
| route=absolute-basic method=post limit=none | 200; proxy 184+62 |
| route=absolute-basic method=post limit=1 | 63 too-large sent=246; proxy 184+62 |
| route=connect-basic method=get limit=none | 200; proxy 134, origin 66 |
| route=connect-basic method=get limit=1 | 63 too-large sent=66; proxy 134, origin 66 |
| route=connect-basic method=post limit=none | 200; proxy 134, origin 87+62 |
| route=connect-basic method=post limit=1 | 63 too-large sent=149; proxy 134, origin 87+62 |

### The wire check's cases (`wire`)

A cell: the outcome. `wire.mjs` compares each head libcurl's trace shows with the stand-in's.

| case | X |
|---|---|
| case=absolute-basic | 200 |
| case=connect-basic | 200 |
| case=tunnel-basic | 200 |
| case=absolute-bytes | 200 |
| case=connect-utf8 | 200 |
| case=absolute-https-proxy | 200 |

### What split

- i2b form=user-0D0A transport=absolute guix-8.20.0: 3 – sent=0; no request / 7 – sent=0; no request
