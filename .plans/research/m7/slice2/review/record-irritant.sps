#!r6rs
;;; Against the refusal-holds-record mutant: the refusal test-auth's leaked
;;; reads as clean prints the secret.
;;;   scripts/guix-env sh -c '$CHEZ --libdirs build/m7s2-review/mut/refusal-holds-record/src:tests:build/scheme-libs --program build/m7s2-review/record-irritant.sps' < /dev/null
(import (rnrs) (only (chezscheme) display-condition) (curl))
(guard (e (#t (display-condition e) (newline)))
  (make-curl-request "http://127.0.0.1:1/" 'credentials '(basic "s3cretUser" "s3cretPass")
                     'headers '(("Authorization" . "x"))))
