(library (curl two-a) (export a) (import (rnrs)) (define a 1))
(library (curl two-b) (export b) (import (rnrs) (http-client target)) (define b 1))
