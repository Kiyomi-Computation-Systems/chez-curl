;;; url-cap.sps [LENGTH ...]: what a call raises for a URL of LENGTH chars
;;; (8,000,000 and 8,000,001 unless given), http://127.0.0.1:9/ then a's,
;;; at each entry: http-get, call-with-response-port and http-parallel of one
;;; spec, on a session of its own. Prints
;;;   (cap LIBCURL ENTRY LENGTH MS DESCRIPTION)
;;; MS the call's time, start to raise; DESCRIPTION each simple condition's
;;; type name, in order, then the &curl-url-error's reason, code, message
;;; and input's length, the who, the message and the irritants, and the
;;; &http-exchange's method, URL length, history and transfers; or what the
;;; call answered. Run from a copy's root.
(import (chezscheme) (curl) (http-client) (curl private counters))

(define version (libcurl-info-version (loaded-libcurl)))
(define (now-ns)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000000000) (time-nanosecond t))))
(define (ms ns) (/ (round (/ ns 10000.0)) 100.0))

(define lengths
  (if (null? (command-line-arguments))
      '(8000000 8000001)
      (map string->number (command-line-arguments))))

(define (url-of n)
  (let ((head "http://127.0.0.1:9/"))
    (string-append head (make-string (- n (string-length head)) #\a))))

(define (described e)
  (if (condition? e)
      (list (map (lambda (c) (record-type-name (record-rtd c))) (simple-conditions e))
            (and (curl-url-error? e)
                 (list 'url-error (curl-url-error-reason e) (curl-url-error-code e)
                       (curl-url-error-message e) (string-length (curl-url-error-input e))))
            (and (curl-transfer-error? e)
                 (list 'transfer-error (curl-transfer-error-reason e) (curl-transfer-error-code e)))
            (and (who-condition? e) (list 'who (condition-who e)))
            (and (message-condition? e) (list 'message (condition-message e)))
            (and (irritants-condition? e) (list 'irritants (condition-irritants e)))
            (and (http-exchange? e)
                 (list 'exchange (http-exchange-method e) (string-length (http-exchange-url e))
                       (http-exchange-history e) (http-exchange-transfers e))))
      (list 'non-condition e)))

(for-each
 (lambda (n)
   (let ((url (url-of n)))
     (for-each
      (lambda (entry)
        (let* ((session (make-http-session 'timeout-ms 20000 'proxy #f))
               (t0 (now-ns))
               (r (guard (e (#t (list 'raised (described e))))
                    (case entry
                      ((request) (list 'returned (http-response-status (http-get session url))))
                      ((port) (list 'returned (call-with-response-port session 'get url
                                                (lambda (r p) (http-response-status r)))))
                      (else (list 'returned (map http-response-status
                                                 (http-parallel session (list (list 'get url)))))))))
               (t1 (now-ns)))
          (http-session-close session)
          (write (list 'cap version entry n (ms (- t1 t0)) r))
          (newline)
          (flush-output-port (current-output-port))))
      '(request port parallel))))
 lengths)
(write (list 'counts (native-counts)))
(newline)
