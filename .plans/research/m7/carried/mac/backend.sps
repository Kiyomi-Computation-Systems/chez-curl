;;; mac/backend.sps: the TLS backend chez-curl records, the one name in
;;; ssl_version not in parentheses after its curl_global_init (ADR-0024), with
;;; CURL_SSL_BACKEND as the process has it. Prints two lines. From the
;;; repository's root:
;;;   chez --libdirs src --script .plans/research/m7/carried/mac/backend.sps
(import (chezscheme))

(define env (getenv "CURL_SSL_BACKEND"))
(printf "chez: CURL_SSL_BACKEND ~a\n" (or env "(unset)"))
;; The first reference loads libcurl; eval keeps a refusal inside the guard.
(printf "chez: loaded-tls-backend ~s\n"
        (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e))))
          (eval '(loaded-tls-backend)
                (environment '(chezscheme) '(only (curl private native) loaded-tls-backend)))))
