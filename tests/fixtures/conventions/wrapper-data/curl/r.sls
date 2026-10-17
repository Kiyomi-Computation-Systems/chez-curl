;; No #!r6rs: Chez refuses box syntax in that mode. A box literal holding a
;; known wrapper's use is data, and its name stray.
(library (curl r)
  (export r)
  (import (rnrs))

  (define r #&(bind-required "curl_easy_init" () uptr #f)))
