(import (curl))

(define engine (make-curl-engine))
(define token
  (curl-submit engine (make-curl-request "https://example.com/upload"
                                         'method 'put 'body 'stream
                                         'body-length 11)))

(curl-token-room-wait token 10000)        ; #t once libcurl asks for the body
(curl-token-put-piece! token (string->utf8 "hello "))
(curl-token-put-piece! token (string->utf8 "world"))
(curl-token-end-body! token)
(curl-token-await token)                  ; the response, or the failure
