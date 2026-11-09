#!r6rs
;;; probe-jsonparse.sps: what (jsonparse easy) answers for the bodies the
;;; Headers and JSON page talks about. Run from the repository's root:
;;;   $CHEZ --libdirs src:build/scheme-libs --program .plans/research/m8/slice5/build/probe-jsonparse.sps
(import (rnrs) (jsonparse easy))

(define (try label thunk)
  (write (list label
               (guard (e ((json-error? e) (list 'json-error (json-error-reason e) (json-error-offset e)))
                         (#t (list 'raised (condition-message e))))
                 (list 'value (thunk)))))
  (newline))

(try "json->bytevector of the example's value"
     (lambda () (utf8->string (json->bytevector '(("name" . "Ada") ("langs" . #("Scheme" "C")))))))
(try "its length" (lambda () (bytevector-length (json->bytevector '(("name" . "Ada") ("langs" . #("Scheme" "C")))))))
(try "status 200 text" (lambda () (bytevector->json (string->utf8 "status 200\n"))))
(try "not found text" (lambda () (bytevector->json (string->utf8 "not found\n"))))
(try "invalid UTF-8 inside a string" (lambda () (bytevector->json #vu8(34 97 255 34))))
(try "a leading BOM" (lambda () (bytevector->json #vu8(#xEF #xBB #xBF 123 125))))
(try "empty" (lambda () (bytevector->json #vu8())))
(try "trailing comma" (lambda () (bytevector->json (string->utf8 "[1,]"))))
(try "string->json of the text with U+FFFD" (lambda () (string->json (utf8->string #vu8(34 97 255 34)))))
(try "json-ref missing" (lambda () (json-ref (string->json "{\"a\":1}") "b")))
(try "json-ref default" (lambda () (json-ref (string->json "{\"a\":1}") "b" 'default 'none)))
(try "null" (lambda () (bytevector->json (string->utf8 "{\"a\":null}"))))
