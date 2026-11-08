(import (curl))
(make-curl-request "https://example.com/" 'http-version 'http/2)
(display "ok block 1 ran to its end") (newline)
