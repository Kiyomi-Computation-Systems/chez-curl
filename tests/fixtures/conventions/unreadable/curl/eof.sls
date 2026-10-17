(library (curl eof) (export) (import (rnrs)))
#!eof
(define hidden (foreign-procedure __collect_safe "curl_easy_init" () uptr))
