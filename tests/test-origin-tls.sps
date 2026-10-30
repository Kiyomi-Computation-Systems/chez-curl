#!r6rs
;;; The suite for the test instrument's TLS and HTTP/2 faces (M1 plan,
;;; section 8; ADR-0005, amended): the origin, tests/origin.mjs, with --pki,
;;; as the byte probe, tests/wire-probe.mjs, and openssl see it, and the TLS
;;; material, tests/make-test-pki.sh, it serves. No check here uses libcurl or
;;; the curl command line.
;;;
;;; One PKI per run, made by make-test-pki at the start. Every expected output
;;; is written here, by hand, never read from origin.mjs: changing a face's
;;; bytes or leaf there fails a test here. Each scenario's test asserts the
;;; whole bytes received and how the connection ended.
;;;
;;; - The certificates are checked by openssl, portably (ADR-0005, amended):
;;;   s_client's verify errors and final code against the run CA, the ALPN it
;;;   was given, the leaf it was served, by which file holds it, and that
;;;   leaf's SAN line. No check reads a hostname code: LibreSSL has none.
;;; - Over TLS, the https faces serve http's bytes, and raw-tls raw's, as
;;;   test-origin.sps holds them: this suite has its own copy.
;;; - The HTTP/2 frames are built here from type, flags, stream and payload,
;;;   the length being the payload's. A request is the connection preface,
;;;   an empty SETTINGS frame and a HEADERS frame, then DATA for a body, its
;;;   HPACK plain literals, sent with --half-close. Each answer's HPACK is
;;;   what nghttp2 writes in Node 20.10.0 and 24.18.0, measured, and decoded
;;;   by hand beside it.
;;;
;;; make test runs it from the repository root, with CHEZ, NODE and OPENSSL
;;; exported. Each computation that can raise runs under a guard that names
;;; what was raised: SRFI-64 turns a raise in the actual expression into #f,
;;; and dies on one in an expected expression or a top-level definition. The
;;; tests against one origin run inside a definition, and its verdict is a
;;; test after: SRFI-64 keeps one result per runner.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (only (chezscheme) current-directory current-time directory-list getenv input-port-ready?
              machine-type make-time open-process-ports parameterize sleep time-nanosecond
              time-second))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

(test-begin "origin-tls")

;; --- helpers ----------------------------------------------------------------

(define node (let ((n (getenv "NODE"))) (if (and n (not (string=? n ""))) n "node")))

;; outcome : (-> Any) -> (U (List 'returned Any) (List 'raised String))
(define (outcome thunk)
  (guard (e (#t (list 'raised (describe e))))
    (list 'returned (thunk))))

;; latin-1 : Bytevector -> String
(define (latin-1 bytes)
  (list->string (map integer->char (bytevector->u8-list bytes))))

;; octets : String -> Bytevector
;; Each character, all below 256, as the byte of its code.
(define (octets text)
  (u8-list->bytevector (map char->integer (string->list text))))

;; hex : Bytevector -> String
(define (hex bytes)
  (apply string-append
         (map (lambda (b)
                (string (string-ref "0123456789abcdef" (div b 16))
                        (string-ref "0123456789abcdef" (mod b 16))))
              (bytevector->u8-list bytes))))

;; join : (Listof Bytevector) -> Bytevector
(define (join pieces)
  (u8-list->bytevector (apply append (map bytevector->u8-list pieces))))

;; shell-word : String -> String
(define (shell-word s)
  (call-with-string-output-port
   (lambda (p)
     (put-char p #\')
     (string-for-each (lambda (c) (if (char=? c #\') (put-string p "'\\''") (put-char p c))) s)
     (put-char p #\'))))

;; pause-ms : Natural -> Unit
(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; now-ms : -> Integer
(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

;; write-file : String String -> Unit
(define (write-file path text)
  (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (p) (put-string p text))))

;; replace-all : String String String -> String
;; TEXT with each FROM, not empty, left to right, written as TO: a path of
;; this run's written as a fixed word, so an expected text holds none.
(define (replace-all text from to)
  (let ((n (string-length from)))
    (let loop ((i 0) (acc '()))
      (cond ((> (+ i n) (string-length text))
             (apply string-append (reverse (cons (substring text i (string-length text)) acc))))
            ((string=? (substring text i (+ i n)) from) (loop (+ i n) (cons to acc)))
            (else (loop (+ i 1) (cons (string (string-ref text i)) acc)))))))

;; stdout-lines : String -> (Listof String)
;; TEXT's lines, each without its newline.
(define (stdout-lines text)
  (let loop ((chars (string->list text)) (line '()) (lines '()))
    (cond ((null? chars) (reverse (if (null? line) lines (cons (list->string (reverse line)) lines))))
          ((char=? (car chars) #\newline) (loop (cdr chars) '() (cons (list->string (reverse line)) lines)))
          (else (loop (cdr chars) (cons (car chars) line) lines)))))

;; starts? : String String -> Boolean
(define (starts? start s)
  (and (<= (string-length start) (string-length s))
       (string=? start (substring s 0 (string-length start)))))

;; trim-spaces : String -> String
;; S without its leading spaces.
(define (trim-spaces s)
  (let loop ((i 0))
    (if (and (< i (string-length s)) (char=? (string-ref s i) #\space)) (loop (+ i 1)) (substring s i (string-length s)))))

;; arrival : (Listof (Pair Natural Natural)) Natural -> (U Natural #f)
;; When the chunk holding byte INDEX arrived, by the probe's clock.
(define (arrival arrivals index)
  (let loop ((rest arrivals) (ms #f))
    (if (and (pair? rest) (<= (caar rest) index))
        (loop (cdr rest) (cdar rest))
        ms)))

;; string-contains? : String String -> Boolean
(define (string-contains? text part)
  (let ((n (string-length part)))
    (let loop ((i 0))
      (and (<= (+ i n) (string-length text))
           (or (string=? (substring text i (+ i n)) part) (loop (+ i 1)))))))

;; linux? : Boolean
;; Whether this Chez runs on Linux: its machine types end in le.
(define linux?
  (let ((m (symbol->string (machine-type))))
    (and (>= (string-length m) 2) (string=? (substring m (- (string-length m) 2) (string-length m)) "le"))))

;; get : String String ... -> String
;; A GET request head for TARGET, with these header lines after Host.
(define (get target . headers)
  (apply string-append "GET " target " HTTP/1.1\r\nHost: 127.0.0.1\r\n"
         (append headers (list "\r\n"))))

(define close "Connection: close\r\n")

;; exchange : Origin Symbol String Natural (U #f List) -> (List String End)
;; Sends TEXT to FACE, with wire-probe-tls TLS, and answers the whole bytes
;; received, as text, and how the connection ended; (raised TEXT) on a raise.
(define (exchange origin face text idle tls)
  (guard (e (#t (list 'raised (describe e))))
    (let ((p (parameterize ((wire-probe-tls tls)) (wire-probe origin face (octets text) idle))))
      (list (latin-1 (probe-bytes p)) (probe-end p)))))

;; The TLS a probe speaks to each face: SNI localhost, and the protocol each
;; offers by ALPN.
(define http1-tls '("localhost" "http/1.1"))
(define h2-tls '("localhost" "h2"))

;; probe-at : String Natural Natural -> End
;; How a connection to HOST:PORT ends, sending nothing, through the probe
;; program itself, for an address no Origin of this process names.
(define (probe-at host port idle)
  (let ((answer (capture-command (list node "tests/wire-probe.mjs" host (number->string port)
                                       "" (number->string idle)))))
    (if (= (car answer) 0)
        (probe-end (parse-wire-probe (cadr answer)))
        (list 'probe-failed answer))))

;; --- the PKI: one per run ---------------------------------------------------

(define pki-made (outcome make-test-pki))
(define pki (and (eq? (car pki-made) 'returned) (cadr pki-made)))

(test-equal "make-test-pki makes this run's PKI"
  'returned
  (car pki-made))

;; pki-file : String -> String
(define (pki-file name) (string-append pki "/" name))

(define the-ten
  '("ca.pem" "expired.key" "expired.pem" "good.key" "good.pem" "other-ca.pem"
    "untrusted.key" "untrusted.pem" "wrong-host.key" "wrong-host.pem"))

(test-equal "the material: the PKI directory holds exactly the ten files"
  the-ten
  (guard (e (#t (list 'raised (describe e))))
    (list-sort string<? (directory-list pki))))

;; The script's refusals, each exit 2 with nothing made. Each runs the script
;; make-test-pki runs, test-pki-script.
(define pki-usage
  "usage: tests/make-test-pki.sh DIR, where DIR is an existing, empty directory\n")

(test-equal "the material: each refusal exits 2, naming its problem, and writes nothing to stdout"
  (list (list 2 "" (string-append "make-test-pki: it takes 1 argument, and was given 0\n" pki-usage))
        (list 2 "" (string-append "make-test-pki: it takes 1 argument, and was given 2\n" pki-usage))
        (list 2 "" (string-append "make-test-pki: NOT/no-such is not a directory\n" pki-usage))
        (list 2 "" (string-append "make-test-pki: NOT/full is not empty\n" pki-usage))
        '(full ("kept")))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((full (string-append dir "/full"))
             (named (lambda (answer) (list (car answer) (cadr answer) (replace-all (caddr answer) dir "NOT")))))
         (capture-command (list "mkdir" full))
         (write-file (string-append full "/kept") "kept\n")
         (append
          (map (lambda (args) (named (apply bounded "sh" (test-pki-script) args)))
               (list '()
                     (list (string-append dir "/a") (string-append dir "/b"))
                     (list (string-append dir "/no-such"))
                     (list full)))
          (list (list 'full (directory-list full)))))))))

(test-equal "the material: a failing openssl command exits 1, with what openssl wrote on stderr"
  '(1 "" "make-test-pki: failed: OPENSSL ecparam -name prime256v1 -genkey -noout -out ca.key\nfailing openssl: ecparam\n")
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((stand-in (string-append dir "/openssl"))
             (out (string-append dir "/out")))
         (write-file stand-in "#!/bin/sh\necho \"failing openssl: $1\" >&2\nexit 1\n")
         (capture-command (list "chmod" "+x" stand-in))
         (capture-command (list "mkdir" out))
         (let ((answer (bounded "env" (string-append "OPENSSL=" stand-in) "sh" (test-pki-script) out)))
           (list (car answer) (cadr answer) (replace-all (caddr answer) stand-in "OPENSSL"))))))))

;; script-path : -> String
;; test-pki-script as an absolute path, for a run from another directory.
(define (script-path)
  (let ((script (test-pki-script)))
    (if (and (positive? (string-length script)) (char=? (string-ref script 0) #\/))
        script
        (string-append (current-directory) "/" script))))

;; in-relative-dir : String (String ...) -> (List (List Integer String String) (Listof String))
;; The script run from DIR on the relative path rel, an empty directory
;; there, with ENV's NAME=VALUE words before it, and what rel holds after.
(define (in-relative-dir dir . env)
  (capture-command (list "mkdir" (string-append dir "/rel")))
  (let ((answer (apply bounded "env" (append env (list "sh" "-c" "cd \"$1\" && exec sh \"$2\" rel" "sh" dir (script-path))))))
    (list answer (list-sort string<? (directory-list (string-append dir "/rel"))))))

(test-equal "the material: a relative DIR: exit 0, nothing said, and exactly the ten files in it, no work/ left"
  (list '(0 "" "") the-ten)
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory (lambda (dir) (in-relative-dir dir)))))

(test-equal "the material: a relative DIR and an openssl that fails: exit 1, the failure on stderr, and nothing left in DIR, work/ included"
  '((1 "" "make-test-pki: failed: false ecparam -name prime256v1 -genkey -noout -out ca.key\n") ())
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory (lambda (dir) (in-relative-dir dir "OPENSSL=false")))))

;; The facts the script's header claims, from x509 -text's trimmed lines as
;; certificate-text reads them: OpenSSL 3.5.7 and 3.0.11 and LibreSSL 3.3.6
;; write them alike (measured). Never a Subject or Issuer line: OpenSSL 3.0
;; writes CN = x, and 3.5 and LibreSSL CN=x.
(define certificates '("ca" "other-ca" "good" "expired" "wrong-host" "untrusted"))

;; certificate-lines : String -> (Listof String)
(define (certificate-lines name) (certificate-text (pki-file (string-append name ".pem"))))

(test-equal "the material: every CA and leaf has an EC P-256 key, and its issuer's one signature, read twice, in the signed part and outside it, is ECDSA with SHA-256"
  (map (lambda (name) (list name '("prime256v1") '("(256 bit)") '("ecdsa-with-SHA256" "ecdsa-with-SHA256")))
       certificates)
  (map (lambda (name)
         (guard (e (#t (list name 'raised (describe e))))
           (let ((lines (certificate-lines name)))
             (list name (certificate-values lines "ASN1 OID:") (certificate-values lines "Public-Key:")
                   (certificate-values lines "Signature Algorithm:")))))
       certificates))

;; The names, through certificate-names, which reads OpenSSL 3.0's CN = x as
;; the CN=x OpenSSL 3.5 and LibreSSL 3.3.6 write (measured on all three):
;; every leaf one subject, which names no host, each CA its own issuer, and
;; each leaf its CA's.
(test-equal "the material: every leaf's Subject is CN=chez-curl test leaf, each CA's Subject and Issuer its own CN, and each leaf's Issuer its CA's"
  '(("ca" ("CN=chez-curl test CA") ("CN=chez-curl test CA"))
    ("other-ca" ("CN=chez-curl untrusted CA") ("CN=chez-curl untrusted CA"))
    ("good" ("CN=chez-curl test leaf") ("CN=chez-curl test CA"))
    ("expired" ("CN=chez-curl test leaf") ("CN=chez-curl test CA"))
    ("wrong-host" ("CN=chez-curl test leaf") ("CN=chez-curl test CA"))
    ("untrusted" ("CN=chez-curl test leaf") ("CN=chez-curl untrusted CA")))
  (map (lambda (name)
         (guard (e (#t (list name 'raised (describe e))))
           (let ((lines (certificate-lines name)))
             (list name (certificate-names lines "Subject:") (certificate-names lines "Issuer:")))))
       certificates))

;; openssl reads the clock once for Not Before and again for Not After, so a
;; second can tick between the two: 172801 s is two days too.
(test-equal "the material: every CA and every leaf but expired is valid for two days, its Not After 172800 s after its Not Before, or 172801 s when a second ticked between openssl's two clock reads"
  (map (lambda (name) (list name 'two-days)) (filter (lambda (name) (not (string=? name "expired"))) certificates))
  (map (lambda (name)
         (guard (e (#t (list name 'raised (describe e))))
           (let* ((lines (certificate-lines name))
                  (before (certificate-values lines "Not Before:"))
                  (after (certificate-values lines "Not After :")))
             (list name (if (and (= (length before) 1) (= (length after) 1))
                            (let ((seconds (- (certificate-time (car after)) (certificate-time (car before)))))
                              (if (memv seconds '(172800 172801)) 'two-days seconds))
                            (list 'dates before after))))))
       (filter (lambda (name) (not (string=? name "expired"))) certificates)))

(test-equal "the material: expired is valid only from Jan  1 00:00:00 2000 GMT to Jan  2 00:00:00 2000 GMT, as x509 -text spaces them"
  '(("Jan  1 00:00:00 2000 GMT") ("Jan  2 00:00:00 2000 GMT"))
  (guard (e (#t (list 'raised (describe e))))
    (let ((lines (certificate-lines "expired")))
      (list (certificate-values lines "Not Before:") (certificate-values lines "Not After :")))))

;; --- the faces, against one origin with this run's PKI -----------------------

;; The leaves, by name, and the files a served certificate is looked for in.
(define leaf-names '(good expired wrong-host untrusted ca other-ca))

;; served-as : String -> (U Symbol (List 'none String))
;; Which of the PKI's files holds the certificate CERT, as base64 text.
(define (served-as cert)
  (let loop ((names leaf-names))
    (cond ((null? names) (list 'none cert))
          ((string=? cert (pem-certificate (pki-file (string-append (symbol->string (car names)) ".pem"))))
           (car names))
          (else (loop (cdr names))))))

(define good-san "DNS:localhost, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1")

;; peer-row : Origin Symbol String -> List
;; What openssl s_client, with SNI localhost, trusting CA and offering
;; h2,http/1.1 by ALPN, says of FACE: its verify errors, final code, ALPN,
;; which file holds the leaf it was served, that leaf's SAN, and whether
;; that leaf was the whole chain served.
(define (peer-row o face ca)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((p (s-client o face "localhost" (pki-file ca) "h2,http/1.1"))
           (leaf (served-as (peer-leaf p))))
      (list (peer-verify-errors p) (peer-verify-code p) (peer-alpn p) leaf
            (if (symbol? leaf) (certificate-san (pki-file (string-append (symbol->string leaf) ".pem"))) 'no-file)
            (if (equal? (peer-chain p) (list (peer-leaf p)))
                'its-leaf-alone
                (list 'chain (map served-as (peer-chain p))))))))

;; alpn-outcome : Origin Symbol String -> List
;; What s_client, offering OFFER alone by ALPN, gets from FACE: (chosen X),
;; or, when it did not exit 0, (refused STATUS ALPN-LINE CERTIFICATE ALERT),
;; from its stdout and stderr. A face with no TLS at all also gives a
;; refusal, No ALPN negotiated, and no certificate; only a TLS refusal
;; writes "alert number 120" on stderr, OpenSSL 3.5.7 and 3.0.11 and
;; LibreSSL 3.3.6 alike (measured: .plans/tls-mutation-log.md, section 5.2).
(define (alpn-outcome o face offer)
  (guard (e ((and (who-condition? e) (eq? (condition-who e) 's-client) (irritants-condition? e)
                  (assq 'status (condition-irritants e)))
             (let ((lines (stdout-lines (cdr (assq 'stdout (condition-irritants e))))))
               (list 'refused (cdr (assq 'status (condition-irritants e)))
                     (cond ((member "No ALPN negotiated" lines) 'no-alpn-negotiated)
                           ((exists (lambda (l) (starts? "ALPN protocol:" l)) lines) 'an-alpn-protocol)
                           (else 'no-alpn-line))
                     (if (member "-----BEGIN CERTIFICATE-----" lines) 'a-certificate 'no-certificate)
                     (let ((err (cdr (assq 'stderr (condition-irritants e)))))
                       (if (string-contains? err "alert number 120") 'alert-120 (list 'stderr err))))))
            (#t (list 'raised (describe e))))
    (let ((p (s-client o face "localhost" (pki-file "ca.pem") offer)))
      (list 'chosen (or (peer-alpn p) 'none)))))

;; peer-fields : Peer -> List
(define (peer-fields p)
  (list (peer-verify-errors p) (peer-verify-code p) (peer-alpn p) (peer-chain p)))

;; The HTTP/2 frames: a frame is its payload's length, in 24 bits, its type,
;; flags, and stream, in 31 bits, then the payload.
(define (frame type flags stream payload)
  (let ((n (bytevector-length payload)))
    (join (list (u8-list->bytevector
                 (list (div n 65536) (mod (div n 256) 256) (mod n 256) type flags
                       (div stream 16777216) (mod (div stream 65536) 256) (mod (div stream 256) 256)
                       (mod stream 256)))
                payload))))

(define DATA 0)
(define HEADERS 1)
(define RST-STREAM 3)
(define SETTINGS 4)
(define GOAWAY 7)
(define END-STREAM 1)
(define ACK 1)
(define END-HEADERS 4)

(define preface (octets "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"))

;; hpack-text : String -> Bytevector
;; A string literal with no Huffman coding: its length, under 127, then its
;; bytes.
(define (hpack-text s) (join (list (u8-list->bytevector (list (string-length s))) (octets s))))

;; request : String String String (Listof (Pair String String)) (U String #f) -> Bytevector
;; What a client sends: the preface, an empty SETTINGS frame, and a HEADERS
;; frame on stream 1, :method METHOD, :scheme SCHEME, :path PATH, :authority
;; localhost, then HEADERS' pairs, ending the stream unless BODY, which then
;; follows in one DATA frame that ends it. HPACK: :method GET is static entry
;; 2, 0x82, and POST 3, 0x83; :scheme http 6, 0x86, and https 7, 0x87; :path
;; and :authority are literals without indexing of static names 4 and 1, 0x04
;; and 0x01; every other pair a literal without indexing of a new name, 0x00.
(define (request scheme method path headers body)
  (let ((block (join (append
                      (list (u8-list->bytevector (list (if (string=? method "GET") #x82 #x83)
                                                       (if (string=? scheme "http") #x86 #x87)
                                                       #x04))
                            (hpack-text path)
                            #vu8(#x01)
                            (hpack-text "localhost"))
                      (map (lambda (pair) (join (list #vu8(#x00) (hpack-text (car pair)) (hpack-text (cdr pair)))))
                           headers)))))
    (join (append (list preface (frame SETTINGS 0 0 #vu8())
                        (frame HEADERS (if body END-HEADERS (+ END-HEADERS END-STREAM)) 1 block))
                  (if body (list (frame DATA END-STREAM 1 (octets body))) '())))))

;; answer : Bytevector (U String #f) -> Bytevector
;; What the origin sends back on stream 1, after its SETTINGS and the ACK of
;; the client's: a HEADERS frame holding BLOCK, then DATA holding BODY, which
;; ends the stream, or, with no BODY, HEADERS alone, ending it.
(define (answer block body)
  (join (append (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                      (frame HEADERS (if body END-HEADERS (+ END-HEADERS END-STREAM)) 1 block))
                (if body (list (frame DATA END-STREAM 1 (octets body))) '()))))

;; The HTTP/2 rows: what to ask, given the scheme, and what comes back. The
;; HPACK nghttp2 writes:
;;   0x88, 0x89, 0x8b, 0x8d  :status 200, 204, 304, 404: static entries 8,
;;                           9, 11 and 13, indexed
;;   0x48 0x82 H             :status as a literal with incremental indexing of
;;                           static name 8, its value H, two bytes of Huffman
;;                           code: 10 1b is "205", 64 02 "302"
;;   0x0f 0x0d LEN DIGITS    content-length, static name 28 (15 + 13), a
;;                           literal without indexing
;;   0x0f 0x1f 0x88 H        location, static name 46 (15 + 31), a literal
;;                           without indexing, its value 8 bytes of Huffman
;;                           code: 61 09 1a 6d 43 02 00 3f is "/status/200"
(define (h2-rows scheme)
  (let ((echoed (string-append ":method: POST\n:scheme: " scheme "\n:path: /echo?x=1\n:authority: localhost\n"
                               "x-two: a\n\nbody")))
    (list
     (list "GET /status/200" (request scheme "GET" "/status/200" '() #f)
           (answer #vu8(#x88 #x0f #x0d 2 #x31 #x31) "status 200\n"))
     (list "GET /status/204, no content-length and no body" (request scheme "GET" "/status/204" '() #f)
           (answer #vu8(#x89) #f))
     (list "GET /status/205, content-length 0 and no body" (request scheme "GET" "/status/205" '() #f)
           (answer #vu8(#x48 #x82 #x10 #x1b #x0f #x0d 1 #x30) #f))
     (list "GET /status/304, no content-length and no body" (request scheme "GET" "/status/304" '() #f)
           (answer #vu8(#x8b) #f))
     (list "GET /nowhere, 404" (request scheme "GET" "/nowhere" '() #f)
           (answer #vu8(#x8d #x0f #x0d 2 #x31 #x30) "not found\n"))
     (list "GET /chunked, an HTTP/1.1 route, 404" (request scheme "GET" "/chunked" '() #f)
           (answer #vu8(#x8d #x0f #x0d 2 #x31 #x30) "not found\n"))
     (list "GET /redirect/302?to=%2Fstatus%2F200, location decoded"
           (request scheme "GET" "/redirect/302?to=%2Fstatus%2F200" '() #f)
           (answer #vu8(#x48 #x82 #x64 #x02 #x0f #x1f #x88 #x61 #x09 #x1a #x6d #x43 #x02 #x00 #x3f
                        #x0f #x0d 2 #x31 #x33)
                   "redirect 302\n"))
     (list "POST /echo?x=1 with a header and a body: each pair, pseudo-headers included, in order, then the body"
           (request scheme "POST" "/echo?x=1" '(("x-two" . "a")) "body")
           (answer (join (list #vu8(#x88 #x0f #x0d 2)
                               (octets (number->string (string-length echoed)))))
                   echoed))
     ;; The stream routes (the M6 plan, section 4.2): content-length 600 is
     ;; a Huffman literal, 0x82 70 00; a body under 16384 bytes is one DATA
     ;; frame. A longer body's frames, written a write at a time, end the
     ;; stream as the writes' drains fall, so its END_STREAM races the
     ;; probe's half-close; tests/test-stream.sps reads such bodies whole.
     (list "GET /pattern/600: :status 200, content-length 600, then the body, byte i being i mod 251"
           (request scheme "GET" "/pattern/600" '() #f)
           (answer #vu8(#x88 #x0f #x0d #x82 #x70 #x00) (pattern-text 600)))
     ;; :status 100 and 103 are literals with incremental indexing of static
     ;; name 8, 0x48, their values Huffman: 08 01 is "100", 08 19 "103";
     ;; link is static name 45 with incremental indexing, 0x6d, its value 27
     ;; bytes of Huffman code, 0x9b.
     (list "GET /early: a 100's HEADERS, a 103's with its link, then :status 200, content-length 6, and early"
           (request scheme "GET" "/early" '() #f)
           (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                       (frame HEADERS END-HEADERS 1 #vu8(#x48 #x82 #x08 #x01))
                       (frame HEADERS END-HEADERS 1
                              (u8-list->bytevector
                               '(#x48 #x82 #x08 #x19 #x6d #x9b #xff #xf8 #xc2 #x13 #xea #x82 #xae #x44 #x23 #xfe
                                 #xfe #xd4 #xb0 #xb4 #x41 #x5d #x85 #xa0 #xe3 #x93 #xed #x41 #xa2 #x04 #x27
                                 #xd5 #x05)))
                       (frame HEADERS END-HEADERS 1 #vu8(#x88 #x0f #x0d 1 #x36))
                       (frame DATA END-STREAM 1 (octets "early\n")))))
     (list "GET /connects, an HTTP/1.1 route, 404" (request scheme "GET" "/connects" '() #f)
           (answer #vu8(#x8d #x0f #x0d 2 #x31 #x30) "not found\n"))
     (list "GET /pattern/600?delay=60001, out of range, 404" (request scheme "GET" "/pattern/600?delay=60001" '() #f)
           (answer #vu8(#x8d #x0f #x0d 2 #x31 #x30) "not found\n")))))

;; pattern-text : Natural -> String
;; The first N bytes of the stream routes' body, byte i being i mod 251, as
;; Latin-1 text, written here, never read from the origin.
(define (pattern-text n)
  (let loop ((i (- n 1)) (chars '()))
    (if (< i 0)
        (list->string chars)
        (loop (- i 1) (cons (integer->char (mod i 251)) chars)))))

;; connection-number : Bytevector -> (U Natural #f)
;; K from the frames of an answer to /connection: the DATA frame's
;; "connection K\n", after the SETTINGS, the ACK and the HEADERS of
;; :status 200 and content-length; #f for any other bytes.
(define (connection-number bytes)
  (let ((before (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())))))
    (and (> (bytevector-length bytes) (+ (bytevector-length before) 9))
         (let* ((rest (let ((r (make-bytevector (- (bytevector-length bytes) (bytevector-length before)))))
                        (bytevector-copy! bytes (bytevector-length before) r 0 (bytevector-length r))
                        r))
                (headers-length (+ 9 (bytevector-u8-ref rest 2)))
                (data-at headers-length))
           (and (> (bytevector-length rest) (+ data-at 9))
                (= (bytevector-u8-ref rest 3) HEADERS)
                (= (bytevector-u8-ref rest (+ data-at 3)) DATA)
                (let* ((n (bytevector-u8-ref rest (+ data-at 2)))
                       (text (list->string (map integer->char
                                                (let loop ((i 0) (found '()))
                                                  (if (= i n) (reverse found)
                                                      (loop (+ i 1) (cons (bytevector-u8-ref rest (+ data-at 9 i)) found))))))))
                  (and (> (string-length text) 12)
                       (string=? (substring text 0 11) "connection ")
                       (char=? (string-ref text (- (string-length text) 1)) #\newline)
                       (string->number (substring text 11 (- (string-length text) 1))))))))))

;; data-by-stream : Bytevector -> (Listof (Pairof Natural String))
;; Each stream's DATA payloads in BYTES, frames read one after another,
;; joined as Latin-1 text, by stream, in the order each stream first sends
;; one.
(define (data-by-stream bytes)
  (let loop ((at 0) (found '()))
    (if (> (+ at 9) (bytevector-length bytes))
        (reverse found)
        (let* ((n (+ (* 65536 (bytevector-u8-ref bytes at)) (* 256 (bytevector-u8-ref bytes (+ at 1)))
                     (bytevector-u8-ref bytes (+ at 2))))
               (type (bytevector-u8-ref bytes (+ at 3)))
               (stream (+ (* 16777216 (mod (bytevector-u8-ref bytes (+ at 5)) 128))
                          (* 65536 (bytevector-u8-ref bytes (+ at 6)))
                          (* 256 (bytevector-u8-ref bytes (+ at 7))) (bytevector-u8-ref bytes (+ at 8))))
               (text (if (<= (+ at 9 n) (bytevector-length bytes))
                         (list->string (let chars ((i 0) (cs '()))
                                         (if (= i n) (reverse cs)
                                             (chars (+ i 1) (cons (integer->char (bytevector-u8-ref bytes (+ at 9 i))) cs)))))
                         "")))
          (loop (+ at 9 n)
                (if (= type DATA)
                    (let ((entry (assv stream found)))
                      (if entry
                          (map (lambda (e) (if (eq? e entry) (cons stream (string-append (cdr e) text)) e)) found)
                          (cons (cons stream text) found)))
                    found))))))

;; h2-exchange : Origin Symbol Bytevector (U #f List) -> (List String End)
;; Sends BYTES to FACE with --half-close, and answers the bytes received, as
;; hex, and how the connection ended.
(define (h2-exchange o face bytes tls)
  (guard (e (#t (list 'raised (describe e))))
    (let ((p (parameterize ((wire-probe-tls tls)) (wire-probe-half-close o face bytes 2000))))
      (list (hex (probe-bytes p)) (probe-end p)))))

;; The new faces, and how a probe opens a connection to each and then waits.
(define tls-faces '(https https-expired https-wrong-host https-untrusted raw-tls h2))
(define new-faces (cons 'h2c tls-faces))
(define every-face (append '(http raw) new-faces))

;; The bytes http writes, and raw's, as test-origin.sps holds them.
(define status-200-close
  "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n")
(define echo-request
  (string-append "POST /echo?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Two: a\r\nx-lower: b\r\n"
                 "Content-Length: 4\r\nConnection: close\r\n\r\nbody"))
(define echo-response
  (string-append "HTTP/1.1 200 OK\r\nContent-Length: 101\r\nConnection: close\r\n\r\n"
                 "POST /echo?x=1 HTTP/1.1\nHost: 127.0.0.1\nX-Two: a\nx-lower: b\n"
                 "Content-Length: 4\nConnection: close\n\nbody"))
(define bad-request
  '("HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof))

;; A partial ClientHello: a TLS handshake record's header, then the start of
;; a ClientHello that says it is longer.
(define partial-client-hello #vu8(#x16 #x03 #x01 #x00 #xc8 #x01 #x00 #x00 #xc4 #x03 #x03))

(define (scenarios o)
  ;; --- the certificates, by openssl: one row per TLS face
  (for-each
   (lambda (row)
     (let ((face (car row)))
       (test-equal (string-append (symbol->string face) ": s_client, trusting the run CA, sees verify errors "
                                  (call-with-string-output-port (lambda (p) (write (cadr row) p)))
                                  ", code " (number->string (caddr row)) ", ALPN " (cadddr row)
                                  ", the " (symbol->string (list-ref row 4))
                                  " leaf served, alone, no chain after it, and its SAN")
         (append (cdr row) '(its-leaf-alone))
         (peer-row o face "ca.pem"))))
   (list (list 'https '() 0 "http/1.1" 'good good-san)
         (list 'https-expired '(10) 10 "http/1.1" 'expired good-san)
         (list 'https-wrong-host '() 0 "http/1.1" 'wrong-host "DNS:wrong-host.invalid")
         (list 'https-untrusted '(20 21) 21 "http/1.1" 'untrusted good-san)
         (list 'raw-tls '() 0 "http/1.1" 'good good-san)
         (list 'h2 '() 0 "h2" 'good good-san)))
  (test-equal "trust: the untrusted leaf verifies against the second CA, with no error, and the good leaf does not"
    (list (list '() 0 "http/1.1" 'untrusted good-san 'its-leaf-alone)
          (list '(20 21) 21 "http/1.1" 'good good-san 'its-leaf-alone))
    (list (peer-row o 'https-untrusted "other-ca.pem")
          (peer-row o 'https "other-ca.pem")))

  ;; --- no SNI. libcurl sends none to an IP URL, and s_client sends none to
  ;; an IP address without -servername: OpenSSL 3.5.7 and 3.0.11 and
  ;; LibreSSL 3.3.6 alike, by a face's log (measured).
  (test-equal "no SNI: every TLS face, reached at its IP address with no -servername, so with no SNI, serves the Peer it serves with SNI localhost"
    (map (lambda (face) (list face 'same-peer)) tls-faces)
    (map (lambda (face)
           (guard (e (#t (list face 'raised (describe e))))
             (let ((with (peer-fields (s-client o face "localhost" (pki-file "ca.pem") "h2,http/1.1")))
                   (without (peer-fields (s-client o face #f (pki-file "ca.pem") "h2,http/1.1"))))
               (list face (if (equal? with without) 'same-peer (list 'with with 'without without))))))
         tls-faces))

  ;; --- each face's ALPN set, pinned. Offered one protocol alone, a face
  ;; that accepts it chooses it; one that does not refuses the handshake with
  ;; a no_application_protocol alert, 120: s_client then exits 1, writes No
  ;; ALPN negotiated and no certificate, and "alert number 120" on stderr,
  ;; which a face with no TLS, or a refusal without that alert, does not. Node 20.10.0 and 24.18.0 alike,
  ;; every face, with OpenSSL 3.5.7 and 3.0.11 and LibreSSL 3.3.6 (measured:
  ;; .plans/tls-mutation-log.md, section 4.2).
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) ": its ALPN set pinned, offered each of h2, http/1.1 and an unknown protocol alone")
       (map (lambda (offer)
              (list offer (if (string=? offer (if (eq? face 'h2) "h2" "http/1.1"))
                              (list 'chosen offer)
                              '(refused 1 no-alpn-negotiated no-certificate alert-120))))
            '("h2" "http/1.1" "zz-unknown"))
       (map (lambda (offer) (list offer (alpn-outcome o face offer))) '("h2" "http/1.1" "zz-unknown"))))
   tls-faces)

  ;; --- the session tickets. With stdin ending 300 ms late, OpenSSL 3 reads
  ;; the two TLS 1.3 tickets Node sends, and prints a block for each, with a
  ;; Verify return code of its own; LibreSSL prints none (both measured).
  ;; parse-s-client must read the same Peer from either.
  (test-equal "https-untrusted, stdin ending 300 ms late so that OpenSSL reads the session tickets: exit 0, the Peer the normal run reads, one more Verify return code line than ticket lines, and the tickets this checker prints"
    '(0 same-peer one-more-code-line tickets-as-measured)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((address (origin-face o 'https-untrusted))
             (ran (bounded "sh" "-c" "(sleep 0.3) | exec \"$0\" \"$@\"" (openssl-program) "s_client"
                           "-connect" (string-append (car address) ":" (number->string (cdr address)))
                           "-servername" "localhost" "-CAfile" (pki-file "ca.pem") "-showcerts"
                           "-alpn" "h2,http/1.1"))
             (late (peer-fields (parse-s-client (cadr ran) (caddr ran))))
             (now (peer-fields (s-client o 'https-untrusted "localhost" (pki-file "ca.pem") "h2,http/1.1")))
             (lines (stdout-lines (cadr ran)))
             (codes (length (filter (lambda (line) (starts? "Verify return code:" (trim-spaces line))) lines)))
             (tickets (length (filter (lambda (line) (string=? line "Post-Handshake New Session Ticket arrived:"))
                                      lines)))
             (checker (cadr (bounded (openssl-program) "version"))))
        (list (car ran)
              (if (equal? late now) 'same-peer (list 'peers late now))
              (if (= codes (+ tickets 1)) 'one-more-code-line (list 'codes codes 'tickets tickets))
              (if (or (and (starts? "OpenSSL " checker) (= tickets 2))
                      (and (starts? "LibreSSL " checker) (= tickets 0)))
                  'tickets-as-measured
                  (list 'tickets tickets checker))))))

  ;; --- the https faces serve http's bytes, verifying nothing
  (for-each
   (lambda (face)
     (test-equal (string-append (symbol->string face) " over TLS: GET /status/200 gets http's bytes, then eof")
       (list status-200-close 'eof)
       (exchange o face (get "/status/200" close) 2000 http1-tls))
     (test-equal (string-append (symbol->string face) " over TLS: an /echo with a body gets http's bytes, then eof")
       (list echo-response 'eof)
       (exchange o face echo-request 2000 http1-tls)))
   '(https https-expired https-wrong-host https-untrusted))

  ;; --- raw-tls plays raw's scripts, byte for byte
  (for-each
   (lambda (row)
     (test-equal (string-append "raw-tls " (car row) ": the whole bytes, then " (symbol->string (caddr row)))
       (list (cadr row) (caddr row))
       (exchange o 'raw-tls (get (car row)) (if (eq? (caddr row) 'timeout) 150 2000) http1-tls)))
   '(("/raw/content-length" "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)
     ("/raw/chunked" "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n1\r\n\n\r\n0\r\n\r\n" eof)
     ("/raw/close-delimited" "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nhello\n" eof)
     ("/raw/http10" "HTTP/1.0 200 OK\r\n\r\nhello\n" eof)
     ("/raw/drip?bytes=4&gap=20" "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabcd" eof)
     ("/raw/stall-after-head" "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n" timeout)
     ("/raw/short-body" "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" eof)
     ("/raw/reset-mid-body" "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello" reset)
     ("/raw/reset-after-pause?ms=1" "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello wor" reset)
     ("/raw/bare-lf" "HTTP/1.1 200 OK\nContent-Length: 6\n\nhello\n" eof)
     ("/raw/nope" "HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n" eof)))
  ;; Timing over TLS is judged between arrivals. TLS hands the reader each
  ;; record as a chunk of its own, even when TCP joined them, so a byte that
  ;; arrives alone says nothing here. With Nagle's algorithm on raw-tls's
  ;; TCP socket, the first two body bytes of this drip arrived 0 to 2 ms
  ;; apart, every other gap about 20 ms; without it, no gap was under 19 ms,
  ;; idle or under 24 busy loops (measured: .plans/tls-mutation-log.md,
  ;; section 3.3). So each gap must be at least half the drip's.
  ;; And, as on raw, body byte i comes at least (i+1) x 20 ms after the probe
  ;; connected: the origin waits the gap before each byte, and the request
  ;; goes only once the handshake is done.
  (test-equal "raw-tls /raw/drip?bytes=8&gap=20: the whole bytes, then eof, each body byte read at least 10 ms after the one before it, and byte i at least (i+1) x 20 ms after connecting"
    (list "HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nabcdefgh" 'eof 'spaced 'each-late-enough)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (string-length "HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\n"))
             (p (parameterize ((wire-probe-tls http1-tls))
                  (wire-probe o 'raw-tls (octets (get "/raw/drip?bytes=8&gap=20")) 2000)))
             (times (map (lambda (i) (arrival (probe-arrivals p) (+ head i))) '(0 1 2 3 4 5 6 7))))
        (list (latin-1 (probe-bytes p)) (probe-end p)
              (if (and (for-all integer? times)
                       (let loop ((ts times))
                         (or (null? (cdr ts)) (and (>= (- (cadr ts) (car ts)) 10) (loop (cdr ts))))))
                  'spaced
                  (list 'arrivals times))
              (if (and (for-all integer? times)
                       (let loop ((ts times) (i 0))
                         (or (null? ts)
                             (and (>= (- (car ts) (probe-connected p)) (* (+ i 1) 20)) (loop (cdr ts) (+ i 1))))))
                  'each-late-enough
                  (list 'connected (probe-connected p) 'arrivals times))))))
  (test-equal "raw-tls /raw/echo: the request head's exact bytes as the body"
    (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: 60\r\n\r\n"
                         "GET /raw/echo HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Spaced:  a b \r\n\r\n")
          'eof)
    (exchange o 'raw-tls (string-append (get "/raw/echo" "X-Spaced:  a b \r\n") "a body") 2000 http1-tls))
  (let ((padded (lambda (total)
                  (let ((before "GET /raw/content-length HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Pad: ")
                        (after "\r\n\r\n"))
                    (string-append before
                                   (make-string (- total (string-length before) (string-length after)) #\a)
                                   after)))))
    (test-equal "raw-tls: a head of 65536 bytes is served, and one of 65537 gets the fixed 400"
      (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof) bad-request)
      (list (exchange o 'raw-tls (padded 65536) 2000 http1-tls)
            (exchange o 'raw-tls (padded 65537) 2000 http1-tls))))
  (test-equal "raw-tls: a client that half-closes over TLS after a drip's request gets the whole drip"
    '("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc" eof)
    (guard (e (#t (list 'raised (describe e))))
      (let ((p (parameterize ((wire-probe-tls http1-tls))
                 (wire-probe-half-close o 'raw-tls (octets (get "/raw/drip?bytes=3&gap=50")) 2000))))
        (list (latin-1 (probe-bytes p)) (probe-end p)))))

  ;; --- HTTP/2, on h2c by prior knowledge, and on h2 over TLS
  (for-each
   (lambda (face scheme tls)
     (for-each
      (lambda (row)
        (test-equal (string-append (symbol->string face) " " (car row) ": the whole frames, then eof")
          (list (hex (caddr row)) 'eof)
          (h2-exchange o face (cadr row) tls)))
      (h2-rows scheme)))
   '(h2c h2) '("http" "https") (list #f h2-tls))
  ;; /connection numbers each connection among its face's: two connections
  ;; one after the other answer K and K + 1, with :status 200 and
  ;; content-length first; with delay, the HEADERS come at once and the
  ;; DATA after it, the probe kept reading, not half-closed, until idle.
  (for-each
   (lambda (face scheme tls)
     (test-equal (string-append (symbol->string face) " GET /connection: two connections, one after the other, answer connection K and connection K + 1, then eof; with delay=300, its HEADERS at once, its DATA 300 ms or more after the probe connected")
       '(numbered consecutive delayed)
       (guard (e (#t (list 'raised (describe e))))
         (let* ((one (parameterize ((wire-probe-tls tls))
                       (wire-probe-half-close o face (request scheme "GET" "/connection" '() #f) 2000)))
                (two (parameterize ((wire-probe-tls tls))
                       (wire-probe-half-close o face (request scheme "GET" "/connection" '() #f) 2000)))
                (k1 (connection-number (probe-bytes one)))
                (k2 (connection-number (probe-bytes two)))
                (late (parameterize ((wire-probe-tls tls))
                        (wire-probe o face (request scheme "GET" "/connection?delay=300" '() #f) 600)))
                (k3 (connection-number (probe-bytes late)))
                (data-at (+ 9 9 9 (bytevector-u8-ref (probe-bytes late) 20))))
           (list (if (and k1 (eq? (probe-end one) 'eof)) 'numbered (list (hex (probe-bytes one)) (probe-end one)))
                 (if (and k1 k2 (= k2 (+ k1 1))) 'consecutive (list k1 k2))
                 (if (and k3 (= k3 (+ k2 1))
                          (>= (- (arrival (probe-arrivals late) data-at) (probe-connected late)) 300))
                     'delayed
                     (list k3 (probe-arrivals late) (probe-connected late))))))))
   '(h2c h2) '("http" "https") (list #f h2-tls))
  ;; Two streams on one connection answer one K: the number is the
  ;; connection's, not the stream's.
  (for-each
   (lambda (face scheme tls)
     (test-equal (string-append (symbol->string face) " GET /connection twice on one connection, streams 1 and 3: each answers connection K, one K")
       '(one-connection)
       (guard (e (#t (list 'raised (describe e))))
         (let* ((once (request scheme "GET" "/connection" '() #f))
                ;; The HEADERS frame's block, as request wrote it for stream 1:
                ;; literals without indexing, so stream 3 may send it again.
                (block-at (+ (bytevector-length preface) 9 9))
                (block (let ((b (make-bytevector (- (bytevector-length once) block-at))))
                         (bytevector-copy! once block-at b 0 (bytevector-length b))
                         b))
                (p (parameterize ((wire-probe-tls tls))
                     (wire-probe-half-close o face (join (list once (frame HEADERS (+ END-HEADERS END-STREAM) 3 block)))
                                            2000)))
                (data (data-by-stream (probe-bytes p)))
                (one (assv 1 data))
                (three (assv 3 data)))
           (list (if (and one three (> (string-length (cdr one)) 11)
                          (string=? (substring (cdr one) 0 11) "connection ")
                          (string=? (cdr one) (cdr three)))
                     'one-connection
                     (list data (probe-end p))))))))
   '(h2c h2) '("http" "https") (list #f h2-tls))
  ;; Without the unknownProtocol listener, Node writes such a client an
  ;; HTTP/1.0 403, "Missing ALPN Protocol", then closes (measured): these
  ;; bytes would not be empty.
  (test-equal "h2: a client offering no ALPN is connected, then destroyed with no byte written: eof, within 1000 ms of the probe's start"
    '("" eof within-1000-ms)
    (guard (e (#t (list 'raised (describe e))))
      (let ((p (parameterize ((wire-probe-tls '("localhost"))) (wire-probe o 'h2 #vu8() 1000))))
        (list (latin-1 (probe-bytes p)) (probe-end p)
              (if (<= (probe-ended p) 1000) 'within-1000-ms (list 'ended (probe-ended p)))))))
  ;; Node 24.18.0's server refuses the handshake with a no_application_protocol
  ;; alert; Node 20.10.0's ends the connection before the client's handshake
  ;; is done (both measured). Before the handshake ends, only the probe's
  ;; deadline bounds it, so the time is the probe's own.
  (test-equal "h2: a client offering only http/1.1 is refused, as one of the two ways measured, within 1000 ms of the probe's start"
    '(refused-as-measured within-1000-ms)
    (guard (e (#t (list 'raised (describe e))))
      (let ((p (parameterize ((wire-probe-tls http1-tls)) (wire-probe o 'h2 #vu8() 1000))))
        (list (if (member (list (latin-1 (probe-bytes p)) (probe-end p))
                          '(("" (refused "ERR_SSL_TLSV1_ALERT_NO_APPLICATION_PROTOCOL")) ("" (refused "EOF"))))
                  'refused-as-measured
                  (list (latin-1 (probe-bytes p)) (probe-end p)))
              (if (<= (probe-ended p) 1000) 'within-1000-ms (list 'ended (probe-ended p)))))))

  ;; --- bad clients end only their own connection
  (for-each
   (lambda (row)
     (let ((face (car row)) (next (cadr row)) (want (caddr row)))
       (test-equal (string-append "a bad client: plaintext sent to " (symbol->string face)
                                  " ends at once, within 1000 ms of connecting, with nothing sent back, and the next request is served")
         (list '("" eof within-1000-ms) want)
         (let ((plain (guard (e (#t (list 'raised (describe e))))
                        (let ((p (wire-probe o face (octets (get "/status/200" close)) 2000)))
                          (list (latin-1 (probe-bytes p)) (probe-end p)
                                (if (<= (- (probe-ended p) (probe-connected p)) 1000)
                                    'within-1000-ms
                                    (list 'connected (probe-connected p) 'ended (probe-ended p))))))))
           (pause-ms 50)
           (list plain (next))))
       (test-equal (string-append "a bad client: a partial ClientHello, then a reset, on " (symbol->string face)
                                  " ends only its connection, and the next request is served")
         (list '("" reset-sent) want)
         (guard (e (#t (list 'raised (describe e))))
           (let ((p (wire-probe-reset o face partial-client-hello)))
             (pause-ms 100)
             (list (list (latin-1 (probe-bytes p)) (probe-end p)) (next)))))))
   (list (list 'https (lambda () (exchange o 'https (get "/status/200" close) 2000 http1-tls))
               (list status-200-close 'eof))
         (list 'raw-tls (lambda () (exchange o 'raw-tls (get "/raw/content-length") 2000 http1-tls))
               '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof))
         (list 'h2 (lambda () (h2-exchange o 'h2 (request "https" "GET" "/status/200" '() #f) h2-tls))
               (list (hex (answer #vu8(#x88 #x0f #x0d 2 #x31 #x31) "status 200\n")) 'eof))))

  ;; --- bad HTTP/2 clients end only their own stream or session, on h2c and h2
  ;; - A stream the client resets with PROTOCOL_ERROR (1) is an error on that
  ;;   stream: the origin answers nothing on it, and its half-close ends the
  ;;   connection. Without the stream's error listener, the origin dies.
  ;; - An HTTP/1.1 request is a session error: SETTINGS, then GOAWAY, its last
  ;;   stream 0 and its code INTERNAL_ERROR (2), as Node 20.10.0 and 24.18.0
  ;;   both write it (measured), then the end.
  (for-each
   (lambda (face scheme tls)
     (let ((next (lambda () (h2-exchange o face (request scheme "GET" "/status/200" '() #f) tls)))
           (served (list (hex (answer #vu8(#x88 #x0f #x0d 2 #x31 #x31) "status 200\n")) 'eof)))
       (test-equal (string-append "a bad HTTP/2 client on " (symbol->string face)
                                  ": a stream it resets with PROTOCOL_ERROR gets no answer, and the next request is served")
         (list (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())))) 'eof) served)
         (let ((reset (h2-exchange o face
                                   (join (list preface (frame SETTINGS 0 0 #vu8())
                                               (frame HEADERS END-HEADERS 1
                                                      (join (list (u8-list->bytevector
                                                                   (list #x83 (if (string=? scheme "http") #x86 #x87) #x04))
                                                                  (hpack-text "/echo") #vu8(#x01) (hpack-text "localhost"))))
                                               (frame RST-STREAM 0 1 #vu8(0 0 0 1))))
                                   tls)))
           (pause-ms 50)
           (list reset (next))))
       (test-equal (string-append "a bad HTTP/2 client on " (symbol->string face)
                                  ": an HTTP/1.1 request ends its session with GOAWAY, and the next request is served")
         (list (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame GOAWAY 0 0 #vu8(0 0 0 0 0 0 0 2))))) 'eof)
               served)
         (let ((bad (guard (e (#t (list 'raised (describe e))))
                      (let ((p (parameterize ((wire-probe-tls tls))
                                 (wire-probe o face (octets (get "/status/200" close)) 2000))))
                        (list (hex (probe-bytes p)) (probe-end p))))))
           (pause-ms 50)
           (list bad (next))))))
   '(h2c h2) '("http" "https") (list #f h2-tls))

  ;; --- lifecycle: loopback
  (test-equal "loopback only: every face's announced address is 127.0.0.1"
    (map (lambda (face) "127.0.0.1") every-face)
    (map (lambda (face) (car (origin-face o face))) every-face))
  (unless linux? (test-skip 1))
  (test-equal "loopback by connection, on Linux: each new face refuses 127.0.0.2, so it listens on 127.0.0.1 alone (skipped elsewhere)"
    (map (lambda (face) '(refused "ECONNREFUSED")) new-faces)
    (map (lambda (face) (probe-at "127.0.0.2" (cdr (origin-face o face)) 200)) new-faces)))

(define scenarios-outcome
  (outcome (lambda ()
             (parameterize ((origin-pki pki))
               (call-with-origin (lambda (o) (scenarios o) 'done))))))

(test-equal "the scenarios' origin starts with the PKI, serves them all, and stops"
  '(returned done)
  scenarios-outcome)

;; --- the probe: TLS's SNI and ALPN, and its refusals ----------------------------

;; An origin whose raw face is TLS, with the good leaf, and that tells each
;; client the SNI it sent, the protocol ALPN chose, and the protocols it
;; offered, in its order, or none. Its ALPNCallback sees the client's list
;; (Node 20.10.0 and 24.18.0, measured), and chooses the first of yy and zz
;; the client offered, or refuses: Node's own choice goes by the server's
;; order, which would hide a probe that reversed its list. The probes run one
;; at a time, so one variable carries each list to its connection.
(define (sni-reporter)
  (string-append
   "import tls from 'node:tls';\n"
   "import { readFileSync } from 'node:fs';\n"
   "let offered = 'none';\n"
   "const server = tls.createServer({ key: readFileSync(" (call-with-string-output-port (lambda (p) (write (pki-file "good.key") p)))
   "), cert: readFileSync(" (call-with-string-output-port (lambda (p) (write (pki-file "good.pem") p)))
   "), ALPNCallback: ({ protocols }) => { offered = protocols.join(','); return ['yy', 'zz'].find((p) => protocols.includes(p)); } }, (s) => {\n"
   "  s.on('error', () => s.destroy());\n"
   "  s.end(`${s.servername} ${s.alpnProtocol} ${offered}\\n`);\n"
   "  offered = 'none';\n"
   "}).listen(0, '127.0.0.1', () => {\n"
   "  const face = `127.0.0.1:${server.address().port}`;\n"
   "  process.stdout.write(JSON.stringify({ node: process.version, pid: process.pid, http: face, raw: face, h2c: face }) + '\\n');\n"
   "  process.stdin.resume();\n"
   "  process.stdin.on('end', () => process.exit(0));\n"
   "});\n"))

(test-equal "the probe's --tls sends SERVERNAME as SNI, and --alpn offers its protocols, every one, in order: the only one the server takes first, last, and in the middle"
  '(("sni.example yy yy\n" eof) ("localhost yy yy,xx\n" eof) ("localhost zz xx,zz\n" eof) ("localhost yy xx,yy,ww\n" eof)
    ("localhost false none\n" eof))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (let ((path (string-append dir "/sni-reporter.mjs")))
         (write-file path (sni-reporter))
         (parameterize ((origin-script path))
           (call-with-origin
            (lambda (o)
              (map (lambda (tls) (exchange o 'raw "" 2000 tls))
                   '(("sni.example" "yy") ("localhost" "yy" "xx") ("localhost" "xx" "zz") ("localhost" "xx" "yy" "ww")
                     ("localhost")))))))))))

(define probe-usage
  "usage: node tests/wire-probe.mjs [--reset | --half-close] [--tls SERVERNAME [--alpn LIST]] [--deadline MS] HOST PORT HEX IDLE-MS\n")

(test-equal "the probe refuses each misuse of --tls and --alpn with exit 2, its problem and its usage on stderr"
  (map (lambda (problem) (list 2 "" (string-append "wire-probe: " problem "\n" probe-usage)))
       '("--tls takes a DNS name, and \"127.0.0.1\" is an IP address, which SNI cannot carry"
         "--tls takes a DNS name, and \"::1\" is an IP address, which SNI cannot carry"
         "--tls takes a DNS name, and was given \"local host\""
         "--tls takes a DNS name, and was given \"\""
         "--tls takes SERVERNAME, a DNS name"
         "--alpn is given only with --tls"
         "--alpn takes protocols separated by commas, and was given \"h2,\""
         "--alpn takes protocols separated by commas, and was given \"\""
         "--alpn takes LIST, protocols separated by commas"
         "--reset and --tls cannot both be given: a reset under a TLS socket reaches the server as a FIN"
         "--alpn names a protocol twice, in \"h2,http/1.1,h2\""))
  (map (lambda (args) (apply bounded node "tests/wire-probe.mjs" args))
       '(("--tls" "127.0.0.1" "127.0.0.1" "1" "" "100")
         ("--tls" "::1" "127.0.0.1" "1" "" "100")
         ("--tls" "local host" "127.0.0.1" "1" "" "100")
         ("--tls" "" "127.0.0.1" "1" "" "100")
         ("--tls")
         ("--alpn" "h2" "127.0.0.1" "1" "" "100")
         ("--tls" "localhost" "--alpn" "h2," "127.0.0.1" "1" "" "100")
         ("--tls" "localhost" "--alpn" "" "127.0.0.1" "1" "" "100")
         ("--tls" "localhost" "--alpn")
         ("--reset" "--tls" "localhost" "127.0.0.1" "1" "" "100")
         ("--tls" "localhost" "--alpn" "h2,http/1.1,h2" "127.0.0.1" "1" "" "100"))))

(test-equal "wire-probe-reset refuses to run under wire-probe-tls, before running a probe"
  '(assertion-violation wire-probe-reset ("the probe has no reset over TLS, and wire-probe-tls is set"
                                           ("localhost")))
  (guard (e ((and (assertion-violation? e) (who-condition? e) (message-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (list (condition-message e) (car (condition-irritants e)))))
            (#t (list 'other (describe e))))
    (parameterize ((wire-probe-tls '("localhost")))
      ;; No origin: one that ran would answer, not raise.
      (wire-probe-reset 'no-origin 'https #vu8()))
    'no-raise))

;; --- the origin's own refusals, and its announcement -----------------------------

(define origin-usage "usage: node tests/origin.mjs [--pki DIR]\n")

(test-equal "an unreadable PKI file exits 2, naming the file, with nothing on stdout"
  (list (list 2 "" (string-append "origin: cannot read the PKI file DIR/good.key: ENOENT\n" origin-usage))
        (list 2 "" (string-append "origin: cannot read the PKI file DIR/no-such/good.pem: ENOENT\n" origin-usage)))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (for-each (lambda (name)
                   (unless (string=? name "good.key")
                     (capture-command (list "cp" (pki-file name) (string-append dir "/" name)))))
                 the-ten)
       (map (lambda (pki-dir)
              (let ((answer (bounded node "tests/origin.mjs" "--pki" pki-dir)))
                (list (car answer) (cadr answer) (replace-all (caddr answer) dir "DIR"))))
            (list dir (string-append dir "/no-such")))))))

(test-equal "a certificate and a key that do not match: the origin exits 2, naming both files, with nothing on stdout"
  (list 2 "" (string-append "origin: the PKI files DIR/good.pem and DIR/good.key are not a certificate and its key: "
                            "ERR_OSSL_X509_KEY_VALUES_MISMATCH\n" origin-usage))
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (for-each (lambda (name)
                   (capture-command (list "cp" (pki-file (if (string=? name "good.key") "expired.key" name))
                                          (string-append dir "/" name))))
                 the-ten)
       (let ((answer (bounded node "tests/origin.mjs" "--pki" dir)))
         (list (car answer) (cadr answer) (replace-all (caddr answer) dir "DIR")))))))

(test-equal "with --pki and stdin at its end from the start, it announces its eleven keys in order, then exits 0, writing nothing to stderr"
  '(0 ("node" "pid" "http" "raw" "h2c" "https" "https-expired" "https-wrong-host" "https-untrusted" "raw-tls" "h2") "")
  (guard (e (#t (list 'raised (describe e))))
    (let* ((answer (bounded node "tests/origin.mjs" "--pki" pki))
           (out (cadr answer))
           (n (string-length out)))
      (list (car answer)
            (if (and (> n 0) (char=? (string-ref out (- n 1)) #\newline))
                (map car (read-announcement (substring out 0 (- n 1))))
                (list 'no-line out))
            (caddr answer)))))

;; --- lifecycle: the stop -----------------------------------------------------------
;; An end proves the stop only when nothing but the origin's stop can
;; explain it: its destroy, or its exit, which closes every socket alike at
;; the TCP level, so no check here tells the two apart. Three other things
;; end connections, and the check rules out each by its mechanism:
;;
;; - Node's own server.close(). It ends some waiting states with nothing
;;   tracked, so an end there proves nothing; each face here also waits in
;;   states it does not end. Untracked, close() ends, by face (measured on
;;   Node 24.18.0 and 20.10.0, .plans/tls-mutation-log.md, section 4.2):
;;     https*   idle after a whole keep-alive response, within 1 ms, on both;
;;              never TCP with nothing sent, a partial ClientHello, the
;;              handshake done, a partial head, a body still to come
;;     raw-tls  nothing, on both: a net.Server's close() ends no connection
;;     h2       on 24, every session within 3 ms: the handshake done, a
;;              partial preface, the preface done; on 20, nothing; on both,
;;              never TCP with nothing sent, a partial ClientHello, or a
;;              stream open with its request body still to come
;;   tests/test-origin.sps holds the plaintext faces to the same.
;; - An idle timer, or a handshake timeout, of the face's own: it ends a
;;   connection some L ms after its last activity. So every probe must still
;;   hold its state, (connected ...) and exactly that state's bytes and no
;;   end, when it is read once more just before PROC returns. And the call
;;   must return within B, 500 ms, of PROC's return, by this process's
;;   monotonic clock: the origin exits only once every face's close() has
;;   seen each of its connections end, so every connection ended within B of
;;   the stop. Two sets of probes, the second opened 700 ms, more than B,
;;   after the first holds its states, then leave no L that ends both sets
;;   inside that window: one set would end before the stop, or the other
;;   more than B after it.
;;
;; - One schedule that ends every connection at once: a reap at a phase
;;   fixed from the origin's start, or a shed once enough are open. The two
;;   sets do not rule it out, so the check runs twice, each time on a fresh
;;   origin, the second holding both sets 700 ms, more than B, longer before
;;   the stop: a schedule fixed to the origin's start, or to the sets'
;;   opening, cannot fall inside both windows.
;;
;; B is three times the slowest measured, 150 ms under 24 busy loops; idle it
;; was 35 to 43 ms, and 49 to 76 ms with Chez under Valgrind
;; (.plans/tls-mutation-log.md, section 4.2). The stop ends a connection
;; with a FIN, or with a reset when the client's bytes are still unread, as
;; a starved origin can leave them: both are the stop's.
;;
;; The states held are those the table below names. Some a client can leave
;; a face in are not held by any check: an HTTP/2 response its client's
;; flow-control window holds back, a TLS handshake whose whole ClientHello
;; came but not the client's Finished, and a response the client does not
;; read.

;; The TLS faces' waiting states: a name, the face, the probe's options, the
;; bytes it sends and the bytes it gets before the stop, both as hex. A
;; plaintext probe's connection to a TLS face is connected before any
;; handshake.
(define tls1 '("--tls" "localhost" "--alpn" "http/1.1"))
(define tls2 '("--tls" "localhost" "--alpn" "h2"))
(define settings-hex (hex (frame SETTINGS 0 0 #vu8())))
(define settings-ack-hex (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())))))

(define tls-waiting-states
  (append
   (apply append
          (map (lambda (face)
                 (list (list "TCP, nothing sent" face '() "" "")
                       (list "a partial ClientHello" face '() (hex partial-client-hello) "")
                       (list "the handshake done, nothing sent" face tls1 "" "")
                       (list "a partial request head" face tls1
                             (hex (octets "GET /status/200 HTTP/1.1\r\nHost: 127.0.0.1\r\n")) "")
                       (list "idle after a whole keep-alive response" face tls1
                             (hex (octets (get "/status/200")))
                             (hex (octets "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: keep-alive\r\n\r\nstatus 200\n")))
                       (list "a request head sent, its body still to come" face tls1
                             (hex (octets "POST /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 10\r\n\r\nhello")) "")))
               '(https https-expired https-wrong-host https-untrusted)))
   (list (list "TCP, nothing sent" 'raw-tls '() "" "")
         (list "a partial ClientHello" 'raw-tls '() (hex partial-client-hello) "")
         (list "the handshake done, nothing sent" 'raw-tls tls1 "" "")
         (list "a partial request head" 'raw-tls tls1 (hex (octets "GET /raw/content-length HTTP/1.1\r\n")) "")
         (list "a stalled script, before its head" 'raw-tls tls1 (hex (octets (get "/raw/stall-before-head"))) "")
         (list "a stalled script, after its head" 'raw-tls tls1 (hex (octets (get "/raw/stall-after-head")))
               (hex (octets "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n")))
         ;; pause-mid-body waits 60 s between its writes: longer than any
         ;; stop, on a slow machine too (2.9 to 5 s on one or two CPUs with
         ;; Valgrind, measured by the review).
         (list "a script playing, between two of its writes" 'raw-tls tls1
               (hex (octets (get "/raw/pause-mid-body?ms=60000")))
               (hex (octets "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello")))
         (list "a script playing, between two of its writes, the client half-closed" 'raw-tls
               (cons "--half-close" tls1)
               (hex (octets (get "/raw/pause-mid-body?ms=60000")))
               (hex (octets "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello")))
         (list "TCP, nothing sent" 'h2 '() "" "")
         (list "a partial ClientHello" 'h2 '() (hex partial-client-hello) "")
         (list "the handshake done, nothing sent" 'h2 tls2 "" settings-hex)
         (list "a partial connection preface" 'h2 tls2 (hex (octets "PRI * HTTP/2.0\r\n")) settings-hex)
         (list "the connection preface done, nothing more" 'h2 tls2
               (hex (join (list preface (frame SETTINGS 0 0 #vu8())))) settings-ack-hex)
         (list "a stream open, its request body still to come" 'h2 tls2
               (hex (join (list preface (frame SETTINGS 0 0 #vu8())
                                (frame HEADERS END-HEADERS 1
                                       (join (list #vu8(#x83 #x87 #x04) (hpack-text "/echo") #vu8(#x01)
                                                   (hpack-text "localhost")))))))
               settings-ack-hex))))

;; A Probe here is a vector: #(STATE TO FROM ERR PID TEXT PIPE-ENDED)
(define (probe-state p) (vector-ref p 0))
(define (probe-from p) (vector-ref p 2))
(define (probe-pid p) (vector-ref p 4))
(define (probe-text p) (vector-ref p 5))

;; spawn : Origin State -> Probe
(define (spawn o state)
  (let-values (((to from err pid)
                (open-process-ports
                 (apply string-append
                        "exec " (shell-word node) " tests/wire-probe.mjs"
                        (append (map (lambda (w) (string-append " " (shell-word w))) (caddr state))
                                (list " 127.0.0.1 " (number->string (cdr (origin-face o (cadr state))))
                                      " " (shell-word (cadddr state)) " 20000")))
                 (buffer-mode block) #f)))
    (vector state to from err pid "" #f)))

;; drain! : Probe -> Unit
;; Appends to the probe's text all its pipe holds now, never waiting.
(define (drain! p)
  (let loop ()
    (when (and (not (vector-ref p 6)) (input-port-ready? (probe-from p)))
      (let ((bytes (get-bytevector-some (probe-from p))))
        (if (eof-object? bytes)
            (vector-set! p 6 #t)
            (begin (vector-set! p 5 (string-append (probe-text p) (latin-1 bytes))) (loop)))))))

;; lines-of : String -> (U (Listof Any) #f)
;; TEXT's whole lines read as data; #f when its last line is not whole.
(define (lines-of text)
  (and (or (zero? (string-length text)) (char=? (string-ref text (- (string-length text) 1)) #\newline))
       (guard (e (#t #f))
         (let ((port (open-string-input-port text)))
           (let loop ((found '()))
             (let ((d (read port))) (if (eof-object? d) (reverse found) (loop (cons d found)))))))))

;; held : Probe -> (U 'waiting 'settling List)
;; Whether the probe holds its state: (connected MS), then data lines that
;; hold exactly its BEFORE bytes, and no end. settling when its lines so far
;; are a start of that; anything else, as evidence.
(define (held p)
  (let* ((text (probe-text p))
         (want (list-ref (probe-state p) 4))
         (data (lines-of text)))
    (cond ((not data) 'settling)
          ((null? data) 'settling)
          ((not (and (pair? (car data)) (eq? (caar data) 'connected))) (list 'not-connected text))
          ((not (for-all (lambda (d) (and (list? d) (= (length d) 4) (eq? (car d) 'data))) (cdr data)))
           (list 'ended text))
          (else
           (let ((got (apply string-append (map cadddr (cdr data)))))
             (cond ((string=? got want) 'waiting)
                   ((and (< (string-length got) (string-length want))
                         (string=? got (substring want 0 (string-length got))))
                    'settling)
                   (else (list 'received text))))))))

;; open-set : Origin (Listof State) -> (Listof Probe)
;; One probe per state, from open-process-ports, so that it holds no pipe
;; of the origin's, each read until it holds its state, within 10000 ms.
(define (open-set o states)
  (let ((probes '()))
    (for-each (lambda (state) (set! probes (append probes (list (spawn o state))))) states)
    (let ((deadline (+ (now-ms) 10000)))
      (let loop ()
        (for-each drain! probes)
        (when (and (< (now-ms) deadline)
                   (exists (lambda (p) (eq? (held p) 'settling)) probes))
          (pause-ms 5)
          (loop))))
    probes))

;; kill-probes : (Listof Probe) -> Unit
(define (kill-probes probes)
  (for-each (lambda (p)
              (capture-command (list "kill" "-9" (number->string (probe-pid p))))
              (for-each (lambda (port) (guard (e (#t #f)) (close-port port)))
                        (list (vector-ref p 1) (vector-ref p 2) (vector-ref p 3))))
            probes))

;; stop-check : (Listof State) ((Origin -> Any) -> Any) Natural Natural -> (List Natural (Listof List))
;; Set A, then, GAP ms after set A holds its states, set B, against the
;; origin CALL starts; HOLD ms after set B holds its states, each probe read
;; once more, and PROC returns. The answer: the ms from PROC's return to the
;; call's, and, for each probe, set A's then set B's, its state's name and
;; face, whether it held its state then, and how its connection ended.
(define (stop-check states call gap hold)
  (let ((all '()) (stopped-at #f))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let* ((before
                (call
                 (lambda (o)
                   (let* ((a (open-set o states))
                          (a-held (now-ms)))
                     (set! all a)
                     (pause-ms (max 0 (- (+ a-held gap) (now-ms))))
                     (let ((b (open-set o states)))
                       (set! all (append a b))
                       (pause-ms hold)
                       (for-each drain! all)
                       (let ((verdicts (map held all)))
                         (set! stopped-at (now-ms))
                         verdicts))))))
               (took (- (now-ms) stopped-at))
               (deadline (+ (now-ms) 2000)))
          (let loop ()
            (for-each drain! all)
            (when (and (< (now-ms) deadline) (exists (lambda (p) (not (vector-ref p 6))) all))
              (pause-ms 5)
              (loop)))
          (list took
                (map (lambda (p held-then)
                       (list (car (probe-state p)) (cadr (probe-state p)) held-then
                             (guard (e (#t (list 'unparsed (describe e))))
                               (probe-end (parse-wire-probe (probe-text p))))))
                     all before))))
      (lambda () (kill-probes all)))))

;; stop-verdict : (List Natural (Listof List)) -> List
(define (stop-verdict result)
  (list (if (<= (car result) 500) 'within-500-ms (list 'took (car result)))
        (map (lambda (row)
               (list (car row) (cadr row) (caddr row)
                     (if (memq (cadddr row) '(eof reset)) 'ended-by-the-stop (cadddr row))))
             (cadr result))))

(for-each
 (lambda (hold name)
   (test-equal (string-append "stopping ends every connection to a TLS face, in each waiting state its table names: " name
                              ", each still holding its state as PROC returns, the call returning within 500 ms of PROC, and each probe's end the stop's")
     (list 'returned
           (list 'within-500-ms
                 (map (lambda (state) (list (car state) (cadr state) 'waiting 'ended-by-the-stop))
                      (append tls-waiting-states tls-waiting-states))))
     (outcome (lambda ()
                (stop-verdict
                 (stop-check tls-waiting-states
                             (lambda (proc) (parameterize ((origin-pki pki)) (call-with-origin proc)))
                             700 hold))))))
 '(0 700)
 '("two sets of probes, the second opened 700 ms after the first holds its states, the stop at once"
   "the same on a fresh origin, both sets held 700 ms longer before the stop"))

;; --- the probe: a reset that arrives with the last bytes, over TLS ------------

;; signal-probe : Probe String -> Integer
;; kill's exit status, sending the probe SIGNAL, as -STOP or -CONT.
(define (signal-probe p signal)
  (car (capture-command (list "kill" signal (number->string (probe-pid p))))))

;; stopped-across : Origin -> List
;; What the probe saw of raw-tls's reset-after-pause?ms=1000 when it is
;; stopped (SIGSTOP) from the moment it holds the script's first write until
;; 3000 ms later, then continued: the bytes, its end, and whether the last
;; bytes were read at least 2000 ms after the first, so only after the stop.
;; The script's last record and the reset under it both come during the
;; stop, so the probe wakes to find them waiting at once. libuv before 1.52
;; then reports an end and never reads the reset; on Node 20.10.0 it did in
;; 50 runs of 50 (measured).
(define (stopped-across o)
  (let ((probes '())
        (first-write "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello"))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (set! probes (open-set o (list (list "reset after a pause" 'raw-tls tls1
                                             (hex (octets (get "/raw/reset-after-pause?ms=1000")))
                                             (hex (octets first-write))))))
        (let ((p (car probes)))
          (if (not (eq? (held p) 'waiting))
              (list 'not-held (probe-text p))
              (let* ((stopped (signal-probe p "-STOP"))
                     (continued (begin (pause-ms 3000) (signal-probe p "-CONT")))
                     (deadline (+ (now-ms) 10000)))
                (let loop ()
                  (drain! p)
                  (when (and (not (vector-ref p 6)) (< (now-ms) deadline))
                    (pause-ms 5)
                    (loop)))
                (if (not (and (eqv? stopped 0) (eqv? continued 0)))
                    (list 'kill stopped continued)
                    (let* ((answer (parse-wire-probe (probe-text p)))
                           (n (string-length first-write))
                           (first (arrival (probe-arrivals answer) (- n 1)))
                           (last (arrival (probe-arrivals answer) n)))
                      (list (latin-1 (probe-bytes answer)) (probe-end answer)
                            (if (and first last (>= (- last first) 2000))
                                'read-after-the-stop
                                (list 'first first 'last last)))))))))
      (lambda () (kill-probes probes)))))

(test-equal "the probe, stopped across raw-tls /raw/reset-after-pause?ms=1000's last write and reset, then continued: the whole bytes, then reset, the last bytes read only after the stop"
  (list 'returned (list "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello wor" 'reset 'read-after-the-stop))
  (outcome (lambda () (parameterize ((origin-pki pki)) (call-with-origin stopped-across)))))

(test-equal "exits on stdin's end: once call-with-origin returns, every face refuses connections"
  (list 'returned (map (lambda (face) '("" (refused "ECONNREFUSED"))) every-face))
  (outcome
   (lambda ()
     (let ((o (parameterize ((origin-pki pki)) (call-with-origin (lambda (o) o)))))
       (map (lambda (face) (exchange o face "" 200 #f)) every-face)))))

(test-end "origin-tls")

(exit (suite-exit-status runner))
