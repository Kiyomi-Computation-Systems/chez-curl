(import (curl))
(make-curl-request "https://example.com/" 'proxy "http://proxy.example:3128")
(make-curl-request "https://example.com/"
                   'proxy "https://user:pass@proxy.example"
                   'proxy-ca-file "/etc/ssl/proxy-ca.pem")
(display "ok block 3 ran to its end") (newline)
