
(import (http-client))

(call-with-http-session
 (lambda (s)
   (let ((file (open-file-input-port "/tmp/big.bin")))
     (http-put s "http://127.0.0.1:44637/big.bin"
               'body (lambda () (get-bytevector-some file))   ; the eof object ends it
               'timeout-ms 60000))))
