(import (curl))

(define engine (make-curl-engine))
(define token
  (curl-submit engine (make-curl-request "https://example.com/big"
                                         'stream-buffer 65536)))

(curl-token-head-wait token 10000)        ; the head comes first
(curl-head-status (curl-token-head token))

(let loop ()
  (let ((piece (curl-token-next-piece token 10000)))
    (when (bytevector? piece)             ; the eof object at the end
      (loop))))

(curl-token-outcome token)                ; the response, its body #f, or the failure
