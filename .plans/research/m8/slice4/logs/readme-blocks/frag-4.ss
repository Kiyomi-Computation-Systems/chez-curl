(import (curl))
(define engine (make-curl-engine))
(define jar (make-curl-cookie-jar engine))
(curl-token-await (curl-submit engine (make-curl-request "https://example.com/login"
                                                         'cookie-jar jar)))
(curl-cookie-jar-cookies jar)            ; its cookies, as lines
(curl-cookie-jar-load! jar saved-lines)  ; put lines back in
(curl-cookie-jar-close! jar)
(display "ok block 4 ran to its end") (newline)
