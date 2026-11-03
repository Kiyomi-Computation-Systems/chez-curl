#!r6rs
;;; The high level's own URL normalization beside an empty userinfo: does
;;; curl-url-part's url keep the @, so a call refuses as the low level does?
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program build/m7s2-review/hl-userinfo.sps' < /dev/null
(import (rnrs) (only (chezscheme) format) (curl))
(display (format "libcurl ~a~%" (libcurl-info-version (loaded-libcurl))))
(for-each (lambda (u)
            (display (format "~s -> url ~s user ~s password ~s~%" u
                             (guard (e (#t 'raised)) (curl-url-part u 'url))
                             (guard (e (#t 'raised)) (curl-url-part u 'user))
                             (guard (e (#t 'raised)) (curl-url-part u 'password)))))
          '("http://@127.0.0.1:1/" "http://:@127.0.0.1:1/" "http://:p@127.0.0.1:1/" "http://u@127.0.0.1:1/" "http://u:@127.0.0.1:1/"))
