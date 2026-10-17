;; No #!r6rs: Chez refuses box syntax in that mode. A box literal is data.
(library (curl r)
  (export r)
  (import (rnrs))

  (define r #&(foreign-procedure "curl_multi_poll" (uptr uptr unsigned int uptr) int)))
