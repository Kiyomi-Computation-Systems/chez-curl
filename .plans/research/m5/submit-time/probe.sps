;; M5 slice 1 review (2026-10-27): how long a submit runs inside the drive's
;; critical section, for a body of 1, 64 and 256 MB. The submit copies the
;; body there (prepare-transfer). Run from the repository's root, in the
;; container: scripts/guix-env sh -c '$CHEZ --libdirs src -q --program .plans/research/m5/submit-time/probe.sps'
(import (chezscheme) (curl))
(define (now-ms) (let ((t (current-time 'time-monotonic))) (+ (* (time-second t) 1000.) (/ (time-nanosecond t) 1e6))))
(define engine (make-curl-engine))
(for-each
 (lambda (mb)
   (let* ((body (make-bytevector (* mb 1024 1024) 65))
          (req (make-curl-request "http://127.0.0.1:1/" 'method 'post 'body body))
          (t0 (now-ms))
          (tok (critical-section (curl-submit engine req)))
          (t1 (now-ms)))
     (printf "body ~a MB: submit inside critical-section ~,1f ms\n" mb (- t1 t0))
     (guard (e (#t #f)) (curl-token-await tok))))
 '(1 64 256))
(curl-engine-stop engine)
