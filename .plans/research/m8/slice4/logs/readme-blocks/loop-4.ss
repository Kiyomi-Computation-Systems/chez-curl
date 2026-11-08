(import (curl))
(define engine (make-curl-engine))
(define jar (make-curl-cookie-jar engine))
(curl-token-await (curl-submit engine (make-curl-request "http://127.0.0.1:44637/login"
                                                         'cookie-jar jar)))
(curl-cookie-jar-cookies jar)            ; its cookies, as lines
(curl-cookie-jar-load! jar (curl-cookie-jar-cookies jar))  ; put lines back in
(curl-cookie-jar-close! jar)
