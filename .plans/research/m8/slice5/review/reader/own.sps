(import (rnrs) (http-client) (jsonparse easy))
(write (json-ref (bytevector->json (string->utf8 "{\"a\":[1,2]}")) "a" 1))
(newline)
