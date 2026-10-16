(library (http-client target) (export hello) (import (rnrs))
  (define (hello) 'reached-http-client))
