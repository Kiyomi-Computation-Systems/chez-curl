(import (http-client))

(call-with-http-session
 (lambda (s)
   (let ((file (open-file-input-port "big.bin")))
     (http-put s "https://example.com/big.bin"
               'body (lambda () (get-bytevector-some file))   ; the eof object ends it
               'timeout-ms 60000))))
(display "ok block 9 ran to its end") (newline)
