
(import (http-client))

(call-with-http-session
 (lambda (s)
   (call-with-response-port s 'get "http://127.0.0.1:44637/big" 'timeout-ms 60000
     (lambda (response port)
       (http-response-status response)    ; the head: status, headers, history
       (let loop ()
         (let ((bytes (get-bytevector-some port)))
           (unless (eof-object? bytes)
             (loop))))))))
