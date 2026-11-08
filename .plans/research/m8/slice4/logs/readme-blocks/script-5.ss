(import (curl) (curl unsupported))

(curl-request-with-options
 (make-curl-request "https://example.com/")
 '(("LOW_SPEED_TIME" . 30)))
(display "ok block 5 ran to its end") (newline)
