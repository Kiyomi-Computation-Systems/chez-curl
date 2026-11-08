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
;;;   by hand beside it. The head routes' blocks (M8 slice 2) are decoded by
;;;   this suite's own HPACK decoder, RFC 7541's static table, dynamic table
;;;   and Huffman code, and compared whole with its own lists of fields; the
;;;   large ones, past Node's default send limit, show the faces raise it.
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
        (auth-testing)
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
  (let ((block (request-block scheme method path headers)))
    (join (append (list preface (frame SETTINGS 0 0 #vu8())
                        (frame HEADERS (if body END-HEADERS (+ END-HEADERS END-STREAM)) 1 block))
                  (if body (list (frame DATA END-STREAM 1 (octets body))) '())))))

;; request-block : String String String (Listof (Pair String String)) -> Bytevector
;; The HPACK block of request's HEADERS frame.
(define (request-block scheme method path headers)
  (join (append
         (list (u8-list->bytevector (list (if (string=? method "GET") #x82 #x83)
                                          (if (string=? scheme "http") #x86 #x87)
                                          #x04))
               (hpack-text path)
               #vu8(#x01)
               (hpack-text "localhost"))
         (map (lambda (pair) (join (list #vu8(#x00) (hpack-text (car pair)) (hpack-text (cdr pair)))))
              headers))))

;; h2-start : String String String (Listof (Pair String String)) -> Bytevector
;; As request with a body, up to its DATA: the preface, an empty SETTINGS
;; frame, and the HEADERS frame, END_HEADERS alone, leaving stream 1 open.
(define (h2-start scheme method path headers)
  (join (list preface (frame SETTINGS 0 0 #vu8())
              (frame HEADERS END-HEADERS 1 (request-block scheme method path headers)))))

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

;; spawned-probe : Origin Symbol Bytevector Natural (Listof String) -> (-> Probe)
;; The wire probe of BYTES to FACE, with OPTIONS, idle bound IDLE ms, started
;; through open-process-ports, not capture-command, so that this thread can
;; make another exchange while it waits: on the Mac, two threads' system
;; calls run one after the other (traps.md). Answers a thunk that reads the
;; probe's output to its end, closes its pipes, and parses it.
(define (spawned-probe o face bytes idle options)
  (let ((f (origin-face o face)))
    (let-values (((to from err pid)
                  (open-process-ports
                   (apply string-append "exec " (shell-word node) " tests/wire-probe.mjs"
                          (append (map (lambda (w) (string-append " " (shell-word w))) options)
                                  (list " --deadline " (number->string (wire-probe-deadline))
                                        " " (shell-word (car f)) " " (number->string (cdr f))
                                        " " (shell-word (hex bytes)) " " (number->string idle))))
                   (buffer-mode block) #f)))
      (lambda ()
        (let ((out (get-bytevector-all from)))
          (for-each (lambda (port) (guard (e (#t #f)) (close-port port))) (list to from err))
          (parse-wire-probe (if (eof-object? out) "" (latin-1 out))))))))

;; stopped-probe : Origin Symbol Bytevector Natural (Listof String) -> (List Probe Integer)
;; The wire probe of BYTES to FACE, with OPTIONS, idle bound IDLE ms, started
;; as spawned-probe starts it, with the origin stopped (SIGSTOP to its pid)
;; from 300 ms after this thread reads the probe's (connected MS) line until
;; 3000 ms after, then continued (SIGCONT), whatever is raised meanwhile.
;; Answers the probe, and STOPPED: when the kill -STOP returned, less when
;; the probe was spawned, less MS, by this process's clock, so at least how
;; long after the probe connected, by the probe's clock, the origin was
;; stopped, Node's start, the 300 ms pause oversleeping, and the kill's own
;; spawn and return all included. With OPTIONS' --split OFFSET:2000,
;; STOPPED under 2000 shows the stop began before the probe sent its rest,
;; 2000 ms after it connected by its clock: 342 to 390 ms natively and
;; beside busy loops, and 372 to 377 ms under Valgrind
;; (research/m7/carried/review, m3). It raises when a kill fails, or when no
;; connected line comes within 10 s.
(define (stopped-probe o face bytes idle options)
  (let ((f (origin-face o face))
        (spawned (now-ms)))
    (let-values (((to from err pid)
                  (open-process-ports
                   (apply string-append "exec " (shell-word node) " tests/wire-probe.mjs"
                          (append (map (lambda (w) (string-append " " (shell-word w))) options)
                                  (list " --deadline " (number->string (wire-probe-deadline))
                                        " " (shell-word (car f)) " " (number->string (cdr f))
                                        " " (shell-word (hex bytes)) " " (number->string idle))))
                   (buffer-mode block) #f)))
      (define (kill-origin signal)
        (car (capture-command (list "kill" signal (number->string (origin-pid o))))))
      (define (connected-ms text)
        (let ((datum (guard (e (#t #f)) (read (open-string-input-port text)))))
          (and (pair? datum) (eq? (car datum) 'connected) (pair? (cdr datum)) (integer? (cadr datum))
               (memv #\newline (string->list text))
               (cadr datum))))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (let ((deadline (+ (now-ms) 10000)))
            (let read-connected ((text ""))
              (cond
                ((connected-ms text)
                 => (lambda (ms)
                      (let ((stopped #f)
                            (stopped-at #f)
                            (continued #f))
                        (pause-ms 300)
                        (dynamic-wind
                          (lambda () #f)
                          (lambda ()
                            (set! stopped (kill-origin "-STOP"))
                            (set! stopped-at (- (now-ms) spawned ms))
                            (pause-ms 2700))
                          (lambda () (when stopped (set! continued (kill-origin "-CONT")))))
                        (unless (and (eqv? stopped 0) (eqv? continued 0))
                          (error 'stopped-probe "a kill of the origin failed" stopped continued))
                        (let ((rest (get-bytevector-all from)))
                          (list (parse-wire-probe (string-append text (if (eof-object? rest) "" (latin-1 rest))))
                                stopped-at)))))
                ((> (now-ms) deadline) (error 'stopped-probe "the probe wrote no connected line within 10 s" text))
                ((input-port-ready? from)
                 (let ((b (get-bytevector-some from)))
                   (if (eof-object? b)
                       (error 'stopped-probe "the probe ended before its connected line" text)
                       (read-connected (string-append text (latin-1 b))))))
                (else (pause-ms 5) (read-connected text))))))
        (lambda () (for-each (lambda (port) (guard (e (#t #f)) (close-port port))) (list to from err)))))))

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

;; --- the sinks' summaries (the M6 plan, slice 2) -----------------------------
;; This suite's own copy of test-origin.sps's: a summary line holds times,
;; which no run can fix, the G of gap=G@B and each list entry's T. shape
;; writes each as ~ once it is a time as the origin writes one, so a test
;; asserts the rest of the line, and the response around it, whole, and
;; judges the times by bounds.

;; digit? : Char -> Boolean
(define (digit? c) (and (char<=? #\0 c) (char<=? c #\9)))

;; time? : String -> Boolean
;; Whether TEXT is ms to one decimal: digits, no leading zero but a lone 0,
;; a dot, one digit.
(define (time? text)
  (let ((n (string-length text)))
    (and (>= n 3)
         (char=? (string-ref text (- n 2)) #\.)
         (digit? (string-ref text (- n 1)))
         (for-all digit? (string->list (substring text 0 (- n 2))))
         (or (= n 3) (not (char=? (string-ref text 0) #\0))))))

;; tenths : String -> Integer
(define (tenths text)
  (let ((n (string-length text)))
    (+ (* 10 (string->number (substring text 0 (- n 2)))) (string->number (substring text (- n 1) n)))))

;; split-text : String Char -> (Listof String)
(define (split-text text sep)
  (let loop ((i 0) (start 0) (pieces '()))
    (cond ((= i (string-length text)) (reverse (cons (substring text start i) pieces)))
          ((char=? (string-ref text i) sep) (loop (+ i 1) (+ i 1) (cons (substring text start i) pieces)))
          (else (loop (+ i 1) start pieces)))))

;; join-text : (Listof String) String -> String
(define (join-text pieces sep)
  (if (null? pieces)
      ""
      (fold-left (lambda (joined piece) (string-append joined sep piece)) (car pieces) (cdr pieces))))

;; shape : String -> (List String (Listof String))
;; A summary line TEXT with the G of its gap=G@B and the T of each of its
;; list's T:N as ~, each one time? takes, and those times, in order.
(define (shape text)
  (let ((times '()))
    (define (timed t)
      (if (time? t) (begin (set! times (cons t times)) "~") t))
    (define (each-in-order proc items)
      (let loop ((rest items) (done '()))
        (if (null? rest) (reverse done) (let ((d (proc (car rest)))) (loop (cdr rest) (cons d done))))))
    (let ((shaped
           (each-in-order
            (lambda (word)
              (cond ((starts? "gap=" word)
                     (let ((parts (split-text (substring word 4 (string-length word)) #\@)))
                       (if (= (length parts) 2) (string-append "gap=" (timed (car parts)) "@" (cadr parts)) word)))
                    ((starts? "list=" word)
                     (string-append
                      "list="
                      (join-text (each-in-order
                                  (lambda (entry)
                                    (let ((parts (split-text entry #\:)))
                                      (if (= (length parts) 2) (string-append (timed (car parts)) ":" (cadr parts)) entry)))
                                  (split-text (substring word 5 (string-length word)) #\,))
                                 ",")))
                    (else word)))
            (split-text text #\space))))
      (list (join-text shaped " ") (reverse times)))))

;; fill : String (Listof String) -> String
;; TEMPLATE with each ~ the next of TIMES, while they last.
(define (fill template times)
  (let loop ((chars (string->list template)) (times times) (out '()))
    (cond ((null? chars) (list->string (reverse out)))
          ((and (char=? (car chars) #\~) (pair? times))
           (loop (cdr chars) (cdr times) (append (reverse (string->list (car times))) out)))
          (else (loop (cdr chars) times (cons (car chars) out))))))

;; shape-response : String -> (List String (Listof String))
;; A whole HTTP/1.1 response TEXT, its head's Content-Length line written
;; Content-Length: L when it is the body's length, and its body shaped; and
;; the body's times.
(define (shape-response text)
  (let ((at (let loop ((i 0))
              (cond ((> (+ i 4) (string-length text)) #f)
                    ((string=? (substring text i (+ i 4)) "\r\n\r\n") i)
                    (else (loop (+ i 1)))))))
    (if (not at)
        (list text '())
        (let* ((body (substring text (+ at 4) (string-length text)))
               (length-line (string-append "Content-Length: " (number->string (string-length body))))
               ;; Each line but the last keeps its CR.
               (lines (map (lambda (line)
                             (cond ((string=? line length-line) "Content-Length: L")
                                   ((string=? line (string-append length-line "\r")) "Content-Length: L\r")
                                   (else line)))
                           (split-text (substring text 0 at) #\newline)))
               (shaped (shape body)))
          (list (string-append (join-text lines "\n") "\r\n\r\n" (car shaped)) (cadr shaped))))))

;; sink-exchange : Origin Symbol String Natural (U #f List) -> List
;; TEXT sent to FACE, as exchange sends it: the response shaped, how the
;; connection ended, and the response's times.
(define (sink-exchange o face text idle tls)
  (let ((got (exchange o face text idle tls)))
    (if (eq? (car got) 'raised)
        got
        (let ((shaped (shape-response (car got))))
          (list (car shaped) (cadr got) (cadr shaped))))))

;; split-probe : Origin Symbol Bytevector Natural Natural Natural (Listof String) -> Probe
;; The probe, with OPTIONS and --split OFFSET:MS, against FACE: BYTES' first
;; OFFSET, then, MS ms after the kernel took them, the rest. It raises when
;; the probe does not exit 0, or parse-wire-probe refuses its output.
(define (split-probe o face bytes offset ms idle options)
  (let* ((f (origin-face o face))
         (answer (capture-command
                  (append (list node "tests/wire-probe.mjs") options
                          (list "--split" (string-append (number->string offset) ":" (number->string ms))
                                (car f) (number->string (cdr f)) (hex bytes) (number->string idle))))))
    (unless (= (car answer) 0) (error 'split-probe "the probe did not exit 0" answer))
    (parse-wire-probe (cadr answer))))

;; post : String String ... -> String
(define (post target . headers)
  (apply string-append "POST " target " HTTP/1.1\r\nHost: 127.0.0.1\r\n" (append headers (list "\r\n"))))

;; digit-code : Char -> (Pair Natural Natural)
;; A decimal digit's HPACK Huffman code (RFC 7541, appendix B), as its bits
;; and their value: 0 to 2 are 5 bits, 00000 to 00010, and 3 to 9 six,
;; 011001 to 011111.
(define (digit-code c)
  (let ((d (- (char->integer c) 48)))
    (if (< d 3) (cons 5 d) (cons 6 (+ 22 d)))))

;; huffman-digits : String -> Bytevector
;; TEXT, decimal digits, in HPACK's Huffman code, the last byte padded with
;; 1 bits.
(define (huffman-digits text)
  (let loop ((chars (string->list text)) (value 0) (bits 0))
    (if (null? chars)
        (let* ((pad (mod (- 8 (mod bits 8)) 8))
               (all (+ (* value (expt 2 pad)) (- (expt 2 pad) 1)))
               (n (div (+ bits pad) 8)))
          (let collect ((j 0) (bytes '()))
            (if (= j n)
                (u8-list->bytevector (reverse bytes))
                (collect (+ j 1) (cons (mod (div all (expt 256 (- n 1 j))) 256) bytes)))))
        (let ((code (digit-code (car chars))))
          (loop (cdr chars) (+ (* value (expt 2 (car code))) (cdr code)) (+ bits (car code)))))))

;; content-length-field : Natural -> Bytevector
;; content-length N as nghttp2 writes it: static name 28 without indexing,
;; 0x0f 0x0d, then the digits, Huffman-coded only when that is shorter, as
;; measured on Node 20.10.0 and 24.18.0: 600 is 0x82 0x70 0x00, and 11, 164,
;; 165, 166 and 167 are their digits as they are.
(define (content-length-field n)
  (let* ((digits (number->string n))
         (huffman (huffman-digits digits)))
    (if (< (bytevector-length huffman) (string-length digits))
        (join (list #vu8(#x0f #x0d) (u8-list->bytevector (list (+ #x80 (bytevector-length huffman)))) huffman))
        (join (list #vu8(#x0f #x0d) (u8-list->bytevector (list (string-length digits))) (octets digits))))))

;; h2-sink : Bytevector String -> (List String (U Symbol List) Natural)
;; From BYTES a probe got for one sink request on stream 1: its DATA, the
;; summary, shaped; whether BYTES are whole the answer that summary makes,
;; :status 200 and its content-length, then the summary, with TEMPLATE's ~
;; each of the summary's times in turn; and how many times it held.
(define (h2-sink bytes template)
  (let* ((data (assv 1 (data-by-stream bytes)))
         (shaped (shape (if data (cdr data) "")))
         (body (fill template (cadr shaped)))
         (want (answer (join (list #vu8(#x88) (content-length-field (string-length body)))) body)))
    (list (car shaped)
          (if (bytevector=? want bytes) 'whole-frames (list 'frames (hex bytes) 'want (hex want)))
          (length (cadr shaped)))))

;; The SHA-256 values, computed on the host (sha256sum, and Python's
;; hashlib, agreeing), never by the origin.
(define sha-p10 "1f825aa2f0020ef7cf91dfa30da4668d791c5d4824fc8e41354b89ec05795ab3")
(define sha-p10-bad7 "140d0e63c9a8ee404243d667825bb70b26fdb28e3dbed1daef57f17fe12fc931")
(define sha-abcdefg "7d1a54127b222502f5b79b5fb0803061152a44f92b37e23c6527baf665d4da9a")
(define sha-body "230d8358dc8e8890b4c58deeb62912ee2f20357ae92a5cc861b98e68fe31acb5")

;; seen-text : Natural -> (List String Symbol)
;; An HTTP/1.1 face's answer to /seen with Connection: close.
(define (seen-text c)
  (let ((body (string-append "seen " (number->string c) "\n")))
    (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: " (number->string (string-length body))
                         "\r\nConnection: close\r\n\r\n" body)
          'eof)))

;; h2-seen : Natural -> (List String Symbol)
;; An HTTP/2 face's answer to /seen as h2-exchange reads it: content-length
;; 7, its one digit as it is.
(define (h2-seen c)
  (list (hex (answer #vu8(#x88 #x0f #x0d 1 #x37) (string-append "seen " (number->string c) "\n"))) 'eof))

(define h2-not-found (lambda () (list (hex (answer #vu8(#x8d #x0f #x0d 2 #x31 #x30) "not found\n")) 'eof)))

;; --- the parts route (M8 slice 3) --------------------------------------------
;; parts-body : String
;; Two parts, boundary BND, then the closing delimiter and CR LF: a, its data
;; hi|, a backslash and 0x01; f, a filename and a type, the pattern's 300
;; bytes. Its SHA-256 and each part's first 16 hex digits were computed on
;; the host (sha256sum, and Python's hashlib, agreeing), never by the origin.
(define parts-body
  (string-append "--BND\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nhi|\\" (string (integer->char 1))
                 "\r\n--BND\r\nContent-Disposition: form-data; name=\"f\"; filename=\"p.bin\"\r\n"
                 "Content-Type: application/octet-stream\r\n\r\n" (pattern-text 300) "\r\n--BND--\r\n"))
(define sha-parts "6454d8e0ec08abcb72817eedcf3a0387bc99943457ed00a3c524da70615a4792")

;; parts-report : String String -> String
;; /parts' report for parts-body, on FACE, its Expect EXPECT.
(define (parts-report face expect)
  (string-append "parts " face " method=POST cl=478 te=- expect=" expect
                 " ct=multipart/form-data;_boundary=BND bytes=478 sha256=" sha-parts
                 " boundary=BND preamble=0 closed=1 epilogue=2 count=2\n"
                 "part 0 headers=Content-Disposition: form-data; name=\"a\" len=5 sha256=2430cdfdae1a3ce9"
                 " pattern=bad@0 data=hi\\x7c\\\\\\x01\n"
                 "part 1 headers=Content-Disposition: form-data; name=\"f\"; filename=\"p.bin\"|"
                 "Content-Type: application/octet-stream len=300 sha256=43f9b5d59eb10881 pattern=ok data=-\n"))

;; status-100-block : Bytevector
;; :status 100 as nghttp2 writes it, a literal with incremental indexing of
;; static name 8, 0x48, its digits Huffman-coded when that is shorter, as
;; content-length-field takes them: 1 and 0 are 5 bits each, so 100 is two
;; bytes, not three.
(define status-100-block
  (let ((huffman (huffman-digits "100")))
    (if (< (bytevector-length huffman) 3)
        (join (list #vu8(#x48) (u8-list->bytevector (list (+ #x80 (bytevector-length huffman)))) huffman))
        (join (list #vu8(#x48 #x03) (octets "100"))))))

;; parts-h2-answer : String Boolean -> Bytevector
;; The whole frames an HTTP/2 face sends for one parts request on stream 1:
;; its SETTINGS and the ACK of the client's; when CONTINUE, a HEADERS frame
;; of :status 100; then :status 200 and its content-length, and DATA holding
;; REPORT, which ends the stream.
(define (parts-h2-answer report continue)
  (join (append (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8()))
                (if continue (list (frame HEADERS END-HEADERS 1 status-100-block)) '())
                (list (frame HEADERS END-HEADERS 1 (join (list #vu8(#x88) (content-length-field (string-length report)))))
                      (frame DATA END-STREAM 1 (octets report))))))

(define (parts-scenarios o)
  (define ct "Content-Type: multipart/form-data; boundary=BND\r\n")
  (define sized (string-append "Content-Length: " (number->string (string-length parts-body)) "\r\n"))
  (define released '("HTTP/1.1 200 OK\r\nContent-Length: 9\r\nConnection: close\r\n\r\nreleased\n" eof))
  (define (http-answer report)
    (string-append "HTTP/1.1 200 OK\r\nContent-Length: " (number->string (string-length report))
                   "\r\nConnection: close\r\n\r\n" report))
  (test-equal "https /parts, two parts by Content-Length: the report, parts https, whole, then eof"
    (list (http-answer (parts-report "https" "-")) 'eof)
    (exchange o 'https (string-append (post "/parts?key=tp-https" ct sized close) parts-body) 2000 http1-tls))
  (test-equal "https /parts with Expect: 100-continue: a 100 at once, then the report"
    (list (string-append "HTTP/1.1 100 Continue\r\n\r\n" (http-answer (parts-report "https" "100-continue"))) 'eof)
    (exchange o 'https (string-append (post "/parts?key=tp-https-continue" ct sized "Expect: 100-continue\r\n" close)
                                      parts-body)
              2000 http1-tls))
  (for-each
   (lambda (face scheme tls options)
     (define (named what) (string-append (symbol->string face) " " what))
     (define (key what) (string-append (symbol->string face) "-parts-" what))
     (define (half-closed bytes)
       (parameterize ((wire-probe-tls tls)) (wire-probe-half-close o face bytes 2000)))
     (define pairs '(("content-length" . "478") ("content-type" . "multipart/form-data; boundary=BND")))
     (test-equal (named "POST /parts, two parts in one DATA frame: the report, whole frames, then eof; /seen then reads 1")
       (list (hex (parts-h2-answer (parts-report (symbol->string face) "-") #f)) 'eof (h2-seen 1))
       (guard (e (#t (list 'raised (describe e))))
         (let* ((p (half-closed (request scheme "POST" (string-append "/parts?key=" (key "one")) pairs parts-body)))
                (seen (h2-exchange o face (request scheme "GET" (string-append "/seen?key=" (key "one")) '() #f) tls)))
           (list (hex (probe-bytes p)) (probe-end p) seen))))
     (test-equal (named "POST /parts?fail=1: the first request of its key answered :status 503 with its report, the second 200")
       (list (list 'status 503 (parts-report (symbol->string face) "-")) (list 'status 200 (parts-report (symbol->string face) "-")))
       (guard (e (#t (list 'raised (describe e))))
         (in-order (lambda (n)
                     (let* ((p (half-closed (request scheme "POST" (string-append "/parts?key=" (key "fail") "&fail=1")
                                                     pairs parts-body)))
                            (bytes (probe-bytes p))
                            (data (assv 1 (data-by-stream bytes))))
                       ;; :status 200 is 0x88; 503 a literal of static name
                       ;; 8, 0x48, then its three digits, as 413's is.
                       (list 'status
                             (cond ((= (bytevector-u8-ref bytes 27) #x88) 200)
                                   ((and (= (bytevector-u8-ref bytes 27) #x48)
                                         (equal? (map (lambda (i) (bytevector-u8-ref bytes i)) '(28 29 30 31))
                                                 '(3 53 48 51)))
                                    503)
                                   (else (list 'headers (hex bytes))))
                             (if data (cdr data) 'no-data))))
                   '(1 2))))
     (test-equal (named "POST /parts with expect 100-continue: a HEADERS frame of :status 100 at once, then the report, whole frames")
       (list (hex (parts-h2-answer (parts-report (symbol->string face) "100-continue") #t)) 'eof)
       (guard (e (#t (list 'raised (describe e))))
         (let ((p (half-closed (request scheme "POST" (string-append "/parts?key=" (key "continue"))
                                        (append pairs '(("expect" . "100-continue"))) parts-body))))
           (list (hex (probe-bytes p)) (probe-end p)))))
     ;; With hold=1 the 100 waits for /raw/release?key=K, sent to the raw
     ;; face 800 ms after the probe starts; the probe's DATA follows 2000 ms
     ;; after its HEADERS, so the 100's HEADERS, at offset 18, comes alone,
     ;; 500 ms after the probe connected at least, and the report only once
     ;; the DATA has ended the stream.
     (test-equal (named "POST /parts?hold=1 with expect 100-continue, its DATA 2000 ms after its HEADERS: counted as its HEADERS arrive, its 100 only once /raw/release names its key, 800 ms on; then the report, whole frames")
       (list (h2-seen 1) released 'held-until-released
             (list (hex (parts-h2-answer (parts-report (symbol->string face) "100-continue") #t)) 'eof))
       (guard (e (#t (list 'raised (describe e))))
         (let* ((first (h2-start scheme "POST" (string-append "/parts?key=" (key "hold") "&hold=1")
                                 (append pairs '(("expect" . "100-continue")))))
                (finish (spawned-probe o face (join (list first (frame DATA END-STREAM 1 (octets parts-body)))) 6000
                                       (append (list "--half-close" "--split"
                                                     (string-append (number->string (bytevector-length first)) ":2000"))
                                               options)))
                (seen (begin (pause-ms 400)
                             (h2-exchange o face (request scheme "GET" (string-append "/seen?key=" (key "hold")) '() #f)
                                          tls)))
                (release (begin (pause-ms 400)
                                (exchange o 'raw (get (string-append "/raw/release?key=" (key "hold"))) 2000 #f)))
                (p (finish))
                (head-at (arrival (probe-arrivals p) 18)))
           (list seen release
                 (if (and head-at (probe-connected p) (>= (- head-at (probe-connected p)) 500))
                     'held-until-released
                     (list 'connected (probe-connected p) 'head-at head-at))
                 (list (hex (probe-bytes p)) (probe-end p)))))))
   '(h2c h2) '("http" "https") (list #f h2-tls) '(() ("--tls" "localhost" "--alpn" "h2"))))

(define (sink-scenarios o)
  (define p10 (pattern-text 10))
  (define bad7 (string-append (substring p10 0 7) "x" (substring p10 8 10)))
  (define not-found-close
    '("HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n" eof))

  ;; --- https: /sink and /seen over TLS, and the routes it does not serve
  (test-equal "https /sink: 10 bytes, byte 7 an x: the summary, sink https, pattern=bad@7, one arrival, then eof; /seen then reads 1"
    (list (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: L\r\nConnection: close\r\n\r\n"
                               "sink https method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10-bad7
                               " pattern=bad@7 arrivals=1 gap=~@0 seen=1\n")
                'eof 1)
          (seen-text 1))
    (let* ((r (sink-exchange o 'https (string-append (post "/sink?key=ts-https" "Content-Length: 10\r\n" close) bad7)
                             2000 http1-tls))
           (seen (exchange o 'https (get "/seen?key=ts-https" close) 2000 http1-tls)))
      (list (if (= (length r) 3) (list (car r) (cadr r) (length (caddr r))) r) seen)))
  (test-equal "https: /close-after is http's alone, and /answer and /refuse HTTP/2's: each 404, the refuse counting nothing"
    (list not-found-close not-found-close not-found-close (seen-text 0))
    (let* ((a (exchange o 'https (get "/close-after?then=fin" close) 2000 http1-tls))
           (b (exchange o 'https (get "/answer?status=200" close) 2000 http1-tls))
           (c (exchange o 'https (get "/refuse?key=ts-https-refuse&at=0" close) 2000 http1-tls))
           (d (exchange o 'https (get "/seen?key=ts-https-refuse" close) 2000 http1-tls)))
      (list a b c d)))

  ;; --- raw-tls: /raw/sink and /raw/answer over TLS. The probe's one write
  ;; is one TLS record, one data event, the head's.
  (test-equal "raw-tls /raw/sink, 10 bytes of the pattern: the summary, sink raw-tls, one arrival at 0.0 ms, then eof; HTTP/2's /seen reads its count"
    (list (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: L\r\nConnection: close\r\n\r\n"
                               "sink raw-tls method=POST cl=10 te=- expect=- ct=- bytes=10 sha256=" sha-p10
                               " pattern=ok arrivals=1 gap=~@0 seen=1\n")
                'eof '("0.0"))
          (h2-seen 1))
    (let* ((r (sink-exchange o 'raw-tls (string-append (post "/raw/sink?key=ts-rawtls" "Content-Length: 10\r\n") p10)
                             2000 http1-tls))
           (seen (h2-exchange o 'h2 (request "https" "GET" "/seen?key=ts-rawtls" '() #f) h2-tls)))
      (list r seen)))
  (test-equal "raw-tls /raw/answer?status=413&close=1, a body after its head: the answer, Connection: close, then eof"
    '("HTTP/1.1 413 Answer\r\nContent-Length: 11\r\nConnection: close\r\n\r\nanswer 413\n" eof)
    (exchange o 'raw-tls (string-append (post "/raw/answer?status=413&close=1" "Content-Length: 10\r\n") p10) 2000 http1-tls))

  ;; --- HTTP/2, on h2c and h2. Each answer's HEADERS, measured on Node
  ;; 20.10.0 and 24.18.0, which agree: :status 200 0x88; :status 413 and
  ;; 599 a literal with incremental indexing of static name 8, 0x48, then
  ;; the three digits as they are, 0x03 and them, Huffman being no shorter;
  ;; content-length as content-length-field writes it.
  (for-each
   (lambda (face scheme tls options)
     (define (named what) (string-append (symbol->string face) " " what))
     (define (key what) (string-append (symbol->string face) "-" what))
     (define (half-closed bytes)
       (parameterize ((wire-probe-tls tls)) (wire-probe-half-close o face bytes 2000)))
     (test-equal (named "POST /sink?list=1, 7 bytes in one DATA frame, with a Content-Type: the summary, whole frames, its one arrival listed, then eof")
       (list (string-append "sink " (symbol->string face) " method=POST cl=7 te=- expect=- ct=text/plain;_charset=x bytes=7 sha256="
                            sha-abcdefg " pattern=bad@0 arrivals=1 gap=~@0 seen=1 list=~:7\n")
             'whole-frames 2 'eof)
       (guard (e (#t (list 'raised (describe e))))
         (let ((p (half-closed (request scheme "POST" (string-append "/sink?key=" (key "one") "&list=1")
                                        '(("content-length" . "7") ("content-type" . "text/plain; charset=x"))
                                        "abcdefg"))))
           (append (h2-sink (probe-bytes p) (string-append "sink " (symbol->string face) " method=POST cl=7 te=- expect=- ct=text/plain;_charset=x bytes=7 sha256="
                                                           sha-abcdefg " pattern=bad@0 arrivals=1 gap=~@0 seen=1 list=~:7\n"))
                   (list (probe-end p))))))
     (test-equal (named "GET /seen: 1 for the key /sink counted, and 0 for one never counted")
       (list (h2-seen 1) (h2-seen 0))
       (let* ((one (h2-exchange o face (request scheme "GET" (string-append "/seen?key=" (key "one")) '() #f) tls))
              (never (h2-exchange o face (request scheme "GET" (string-append "/seen?key=" (key "never")) '() #f) tls)))
         (list one never)))
     ;; DATA of 3 bytes, then, 300 ms on, DATA of 4 that ends the stream: the
     ;; longest wait is before the second, 3 bytes in; half the split, as a
     ;; lower bound.
     ;; The first DATA's event comes a little after the headers', so G, the
     ;; wait before the second, is the second's time less the first's.
     (test-equal (named "POST /sink?list=1, its DATA split 3 then 4 bytes, 300 ms apart: two arrivals, gap=G@3, G the second's time less the first's, 150 ms or more")
       (list (string-append "sink " (symbol->string face) " method=POST cl=7 te=- expect=- ct=- bytes=7 sha256="
                            sha-abcdefg " pattern=bad@0 arrivals=2 gap=~@3 seen=1 list=~:3,~:4\n")
             'whole-frames 3 'eof 'gap-between-the-two 'gap-long-enough)
       (guard (e (#t (list 'raised (describe e))))
         (let* ((template (string-append "sink " (symbol->string face) " method=POST cl=7 te=- expect=- ct=- bytes=7 sha256="
                                         sha-abcdefg " pattern=bad@0 arrivals=2 gap=~@3 seen=1 list=~:3,~:4\n"))
                (first (join (list (h2-start scheme "POST" (string-append "/sink?key=" (key "gap") "&list=1")
                                             '(("content-length" . "7")))
                                   (frame DATA 0 1 (octets "abc")))))
                (p (split-probe o face (join (list first (frame DATA END-STREAM 1 (octets "defg"))))
                                (bytevector-length first) 300 2000 (cons "--half-close" options)))
                (data (assv 1 (data-by-stream (probe-bytes p))))
                (times (cadr (shape (if data (cdr data) "")))))
           (append (h2-sink (probe-bytes p) template)
                   (list (probe-end p)
                         (if (and (= (length times) 3)
                                  (= (tenths (car times)) (- (tenths (caddr times)) (tenths (cadr times)))))
                             'gap-between-the-two (list 'times times))
                         (if (and (= (length times) 3) (>= (tenths (car times)) 1500)) 'gap-long-enough
                             (list 'times times)))))))
     ;; The answer's frames end before the body is sent, 300 ms on, and the
     ;; stream stays open for it: the probe's half-close, after the body,
     ;; ends the connection.
     (test-equal (named "POST /answer?status=413, its HEADERS without END_STREAM: the answer, whole frames, before its DATA is sent 300 ms on; eof only after")
       (list (list (hex (answer #vu8(#x48 #x03 #x34 #x31 #x33 #x0f #x0d 2 #x31 #x31) "answer 413\n")) 'eof)
             'answered-before 'ended-after)
       (guard (e (#t (list 'raised (describe e))))
         (let* ((first (h2-start scheme "POST" "/answer?status=413" '(("content-length" . "5"))))
                (p (split-probe o face (join (list first (frame DATA END-STREAM 1 (octets "hello"))))
                                (bytevector-length first) 300 2000 (cons "--half-close" options)))
                (last (arrival (probe-arrivals p) (- (bytevector-length (probe-bytes p)) 1))))
           (list (list (hex (probe-bytes p)) (probe-end p))
                 (if (and last (< (- last (probe-connected p)) 300)) 'answered-before
                     (list 'connected (probe-connected p) 'last last))
                 (if (>= (- (probe-ended p) (probe-connected p)) 300) 'ended-after
                     (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
     ;; 204 carries no body and no content-length, as /status's does.
     (test-equal (named "GET /answer: 200 and 599 with content-length and answer S, 204 its HEADERS alone, ending the stream")
       (list (list (hex (answer #vu8(#x88 #x0f #x0d 2 #x31 #x31) "answer 200\n")) 'eof)
             (list (hex (answer #vu8(#x48 #x03 #x35 #x39 #x39 #x0f #x0d 2 #x31 #x31) "answer 599\n")) 'eof)
             (list (hex (answer #vu8(#x89) #f)) 'eof))
       (let* ((a (h2-exchange o face (request scheme "GET" "/answer?status=200" '() #f) tls))
              (b (h2-exchange o face (request scheme "GET" "/answer?status=599" '() #f) tls))
              (c (h2-exchange o face (request scheme "GET" "/answer?status=204" '() #f) tls)))
         (list a b c)))
     ;; With hold=KEY the answer waits for /raw/release?key=KEY, sent to the
     ;; raw face 1000 ms after the probe starts, while the probe runs in a
     ;; process of its own: the origin's SETTINGS frames come at once, the
     ;; answer's HEADERS, at offset 18, only once the release is made, 500 ms
     ;; after the probe connected at least. The probe's DATA follows 4000 ms
     ;; after its HEADERS, ending the stream, then its half-close, which ends
     ;; the connection.
     (test-equal (named "POST /answer?status=200&hold=KEY, its HEADERS without END_STREAM: the answer, whole frames, only once /raw/release?key=KEY, from the raw face 1000 ms on, has answered released; eof once the probe has sent its DATA")
       (list (list (hex (answer #vu8(#x88 #x0f #x0d 2 #x31 #x31) "answer 200\n")) 'eof)
             'held-until-released
             '("HTTP/1.1 200 OK\r\nContent-Length: 9\r\nConnection: close\r\n\r\nreleased\n" eof))
       (guard (e (#t (list 'raised (describe e))))
         (let* ((first (h2-start scheme "POST" (string-append "/answer?status=200&hold=" (key "hold"))
                                 '(("content-length" . "5"))))
                (finish (spawned-probe o face (join (list first (frame DATA END-STREAM 1 (octets "hello")))) 6000
                                       (append (list "--half-close" "--split"
                                                     (string-append (number->string (bytevector-length first)) ":4000"))
                                               options)))
                (released (begin (pause-ms 1000)
                                 (exchange o 'raw (get (string-append "/raw/release?key=" (key "hold"))) 2000 #f)))
                (p (finish))
                (head-at (arrival (probe-arrivals p) 18)))
           (list (list (hex (probe-bytes p)) (probe-end p))
                 (if (and head-at (probe-connected p) (>= (- head-at (probe-connected p)) 500))
                     'held-until-released
                     (list 'connected (probe-connected p) 'head-at head-at))
                 released))))
     ;; RST_STREAM on stream 1, its code REFUSED_STREAM, 7, and nothing else
     ;; for the stream; then the next request for the key is read whole and
     ;; answered as /sink, the second counted.
     (test-equal (named "POST /refuse?at=0, its HEADERS alone: RST_STREAM REFUSED_STREAM on stream 1 and nothing else, then eof; the key's next request answered as /sink, seen=2")
       (list (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                                    (frame RST-STREAM 0 1 #vu8(0 0 0 7)))))
                   'eof)
             (list (string-append "sink " (symbol->string face) " method=POST cl=4 te=- expect=- ct=- bytes=4 sha256="
                                  sha-body " pattern=bad@0 arrivals=1 gap=~@0 seen=2\n")
                   'whole-frames 1 'eof))
       (guard (e (#t (list 'raised (describe e))))
         (let* ((target (string-append "/refuse?key=" (key "r0") "&at=0"))
                (refused (h2-exchange o face (h2-start scheme "POST" target '(("content-length" . "4"))) tls))
                (p (half-closed (request scheme "POST" target '(("content-length" . "4")) "body"))))
           (list refused
                 (append (h2-sink (probe-bytes p) (string-append "sink " (symbol->string face) " method=POST cl=4 te=- expect=- ct=- bytes=4 sha256="
                                                                 sha-body " pattern=bad@0 arrivals=1 gap=~@0 seen=2\n"))
                         (list (probe-end p)))))))
     ;; DATA of 3 bytes, then, 300 ms on, DATA of 4: at=5 refuses only once
     ;; the second has come.
     (test-equal (named "POST /refuse?at=5, its DATA split 3 then 4 bytes, 300 ms apart: RST_STREAM REFUSED_STREAM only after the second, then eof; the key's next request answered as /sink, seen=2")
       (list (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                                    (frame RST-STREAM 0 1 #vu8(0 0 0 7)))))
                   'eof)
             'refused-after
             (list (string-append "sink " (symbol->string face) " method=POST cl=7 te=- expect=- ct=- bytes=7 sha256="
                                  sha-abcdefg " pattern=bad@0 arrivals=1 gap=~@0 seen=2\n")
                   'whole-frames 1 'eof))
       (guard (e (#t (list 'raised (describe e))))
         (let* ((target (string-append "/refuse?key=" (key "r5") "&at=5"))
                (first (join (list (h2-start scheme "POST" target '(("content-length" . "7"))) (frame DATA 0 1 (octets "abc")))))
                (refused (split-probe o face (join (list first (frame DATA END-STREAM 1 (octets "defg"))))
                                      (bytevector-length first) 300 2000 (cons "--half-close" options)))
                (reset-at (arrival (probe-arrivals refused) 18))
                (p (half-closed (request scheme "POST" target '(("content-length" . "7")) "abcdefg"))))
           (list (list (hex (probe-bytes refused)) (probe-end refused))
                 (if (and reset-at (>= (- reset-at (probe-connected refused)) 300)) 'refused-after
                     (list 'connected (probe-connected refused) 'reset-at reset-at))
                 (append (h2-sink (probe-bytes p) (string-append "sink " (symbol->string face) " method=POST cl=7 te=- expect=- ct=- bytes=7 sha256="
                                                                 sha-abcdefg " pattern=bad@0 arrivals=1 gap=~@0 seen=2\n"))
                         (list (probe-end p)))))))
     ;; DATA of exactly N bytes, 3, and the stream left open: refused at it.
     (test-equal (named "POST /refuse?at=3, DATA of 3 bytes and the stream left open: RST_STREAM REFUSED_STREAM on stream 1, then eof")
       (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                              (frame RST-STREAM 0 1 #vu8(0 0 0 7)))))
             'eof)
       (h2-exchange o face (join (list (h2-start scheme "POST" (string-append "/refuse?key=" (key "r3") "&at=3")
                                                 '(("content-length" . "7")))
                                       (frame DATA 0 1 (octets "abc"))))
                    tls))
     ;; The request and the client's end in one read (research/m7/carried/
     ;; races): the preface, then, 2000 ms on, the SETTINGS and HEADERS of
     ;; POST /refuse?at=0 and the probe's half-close, while the origin is
     ;; stopped, from 300 ms after the probe connected to 3000 ms after. Over
     ;; TLS the HEADERS record and the close_notify then come in one read. The
     ;; refusal first writes the SETTINGS ACK, a TLS write that completes only
     ;; at the next immediate, and the RST_STREAM waits for it; Node's own end
     ;; of the TLS socket, at the close_notify, came before that, and the
     ;; frame was never written. Main's origin lost it on h2 10 times of 10
     ;; in the races' forced loop, and h2c 0 of 10 (research/m7/carried/
     ;; races, results/loop/stop0-main.log); this test failed with main's
     ;; origin in each of its three kept runs, mutant o0's (results/mutants/
     ;; there, build/carried-races/out/ and research/m7/carried/verify/
     ;; mutants/), where unstopped CI's floor job and the memory gate met it
     ;; as a race. h2c reads its FIN in a read of its own, after the data,
     ;; and passed either way.
     (test-equal (named "POST /refuse?at=0, its SETTINGS, HEADERS and half-close sent while the origin is stopped, then continued: RST_STREAM REFUSED_STREAM on stream 1, then eof; the stop began before the request went, and the answer came after it")
       (list (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                                    (frame RST-STREAM 0 1 #vu8(0 0 0 7)))))
                   'eof)
             'stopped-before-the-request 'answered-after-the-stop)
       (guard (e (#t (list 'raised (describe e))))
         (let* ((r (stopped-probe o face (h2-start scheme "POST" (string-append "/refuse?key=" (key "stopped") "&at=0")
                                                   '(("content-length" . "4")))
                                  4000 (append (list "--half-close" "--split" "24:2000") options)))
                (p (car r))
                (ack-at (arrival (probe-arrivals p) 9)))
           (list (list (hex (probe-bytes p)) (probe-end p))
                 (if (< (cadr r) 2000) 'stopped-before-the-request (list 'stopped-at (cadr r)))
                 (if (and ack-at (probe-connected p) (>= (- ack-at (probe-connected p)) 2900))
                     'answered-after-the-stop
                     (list 'connected (probe-connected p) 'ack-at ack-at))))))
     (test-equal (named "POST /refuse?at=100, a first request whose 7 bytes end short of 100: answered as /sink, seen=1")
       (list (string-append "sink " (symbol->string face) " method=POST cl=7 te=- expect=- ct=- bytes=7 sha256="
                            sha-abcdefg " pattern=bad@0 arrivals=1 gap=~@0 seen=1\n")
             'whole-frames 1 'eof)
       (guard (e (#t (list 'raised (describe e))))
         (let ((p (half-closed (request scheme "POST" (string-append "/refuse?key=" (key "short") "&at=100")
                                        '(("content-length" . "7")) "abcdefg"))))
           (append (h2-sink (probe-bytes p) (string-append "sink " (symbol->string face) " method=POST cl=7 te=- expect=- ct=- bytes=7 sha256="
                                                           sha-abcdefg " pattern=bad@0 arrivals=1 gap=~@0 seen=1\n"))
                   (list (probe-end p))))))
     (test-equal (named "a query /sink, /seen, /answer or /refuse refuses, and /close-after, an HTTP/1.1 route: each 404, a refused /refuse counting nothing")
       (append (map (lambda (n) (h2-not-found)) '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18)) (list (h2-seen 0)))
       (let loop ((targets (list "/sink" "/sink?key=" "/sink?key=k&list=0" "/seen" "/seen?key=k&x=1" "/answer"
                                 "/answer?status=199" "/answer?status=600" "/answer?status=200&status=200"
                                 "/answer?status=200&hold=" "/answer?status=200&hold=a%2Fb"
                                 "/answer?status=200&hold=h&hold=h"
                                 (string-append "/refuse?key=" (key "refused"))
                                 (string-append "/refuse?key=" (key "refused") "&at=268435457")
                                 (string-append "/refuse?key=" (key "refused") "&at=0&at=0")
                                 "/refuse?at=0" "/close-after?then=fin" "/close-after?then=kill"
                                 (string-append "/seen?key=" (key "refused"))))
                  (answers '()))
         (if (null? targets)
             (reverse answers)
             (loop (cdr targets) (cons (h2-exchange o face (request scheme "GET" (car targets) '() #f) tls) answers))))))
   '(h2c h2) '("http" "https") (list #f h2-tls) '(() ("--tls" "localhost" "--alpn" "h2"))))

;; --- the stream calls' routes (the M6 plan, slice 3) -----------------------------
;; This suite's own copies of test-origin.sps's helpers for them, and what
;; HTTP/2 needs besides: a frame reader, and HPACK's Huffman code for the
;; characters a summary line holds, to read the sink header nghttp2 codes.

(define sha-empty "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

;; early-text : String (U String #f) Boolean -> String
;; The answer /raw/answer-at and /raw/arm write, by hand: HTTP/1.1 S Early,
;; a Location of TO when given, Content-Length: 10, Connection: close when
;; CLOSE?, and the body early S.
(define (early-text status to close?)
  (string-append "HTTP/1.1 " status " Early\r\n"
                 (if to (string-append "Location: " to "\r\n") "")
                 "Content-Length: 10\r\n"
                 (if close? "Connection: close\r\n" "")
                 "\r\nearly " status "\n"))

;; in-order : (Any -> Any) (Listof Any) -> (Listof Any)
;; PROC of each of ITEMS, called first to last: map calls its procedure in
;; no fixed order.
(define (in-order proc items)
  (let loop ((rest items) (answers '()))
    (if (null? rest)
        (reverse answers)
        (let ((answer (proc (car rest))))
          (loop (cdr rest) (cons answer answers))))))

;; same-text : String String -> (U 'same (List 'differs Natural Natural))
;; Whether GOT is WANT, or where they part, and GOT's length.
(define (same-text want got)
  (if (string=? want got)
      'same
      (let loop ((i 0))
        (if (and (< i (string-length want)) (< i (string-length got))
                 (char=? (string-ref want i) (string-ref got i)))
            (loop (+ i 1))
            (list 'differs i (string-length got))))))

;; without-cr : String -> String
(define (without-cr line)
  (let ((n (string-length line)))
    (if (and (> n 0) (char=? (string-ref line (- n 1)) #\return)) (substring line 0 (- n 1)) line)))

;; seq-response : String -> (List String (U Symbol List) (Listof String))
;; A /raw/seq response TEXT: its head, its CRLF CRLF left off, the Sink
;; line's times written ~ as shape writes them; whether its body is the
;; first N bytes of the pattern, N its Content-Length; and those times.
(define (seq-response text)
  (let ((at (let loop ((i 0))
              (cond ((> (+ i 4) (string-length text)) #f)
                    ((string=? (substring text i (+ i 4)) "\r\n\r\n") i)
                    (else (loop (+ i 1)))))))
    (if (not at)
        (list text 'no-head '())
        (let* ((times '())
               (lines (in-order (lambda (line)
                                  (if (starts? "Sink: " line)
                                      (let ((shaped (shape (substring (without-cr line) 6 (string-length (without-cr line))))))
                                        (set! times (cadr shaped))
                                        (string-append "Sink: " (car shaped)
                                                       (if (string=? line (without-cr line)) "" "\r")))
                                      line))
                                (split-text (substring text 0 at) #\newline)))
               (body (substring text (+ at 4) (string-length text)))
               (length-line (exists (lambda (line) (and (starts? "Content-Length: " line) (without-cr line))) lines))
               (n (and length-line (string->number (substring length-line 16 (string-length length-line))))))
          (list (join-text lines "\n")
                (if n (same-text (pattern-text n) body) 'no-length)
                times)))))

;; uploader : String
;; Node's own client, run as node -e UPLOADER KIND HOST PORT BYTES, KIND
;; raw, raw-tls, h2c or h2: it posts BYTES bytes of the pattern to the
;; face's mirror, sized, 65511 bytes a write, each awaited until its socket
;; or stream takes it, reading nothing, until every write is taken, or none
;; has been for 500 ms; then it reads, writes the rest, and reads the
;; answer to its end. It prints (uploaded STALL TAKEN "HEAD" GOT CHECK):
;; STALL is stalled and the bytes taken then, or whole; TAKEN the bytes
;; taken in all; HEAD the response's head, or over HTTP/2 its :status and
;; content-length; GOT the body's bytes; CHECK ok when each byte i is i mod
;; 251, else the first that is not. An error prints (failed CODE), and 30 s
;; on it prints (deadline); either exits 1.
(define uploader
  (string-append
   "const net = require('node:net'); const tls = require('node:tls'); const http2 = require('node:http2');"
   "const [kind, host, port, totalText] = process.argv.slice(1);"
   "const total = Number(totalText);"
   "const block = Buffer.alloc(65511); for (let i = 0; i < block.length; i++) block[i] = i % 251;"
   "let taken = 0, last = performance.now(), stall = null, got = 0, bad = null, head = null, buf = Buffer.alloc(0);"
   "let out = null, resume = null, watch = null;"
   "const fail = (code) => { console.log(`(failed ${code})`); process.exit(1); };"
   "setTimeout(() => { console.log('(deadline)'); process.exit(1); }, 30000);"
   "const take = (chunk) => { for (let i = 0; i < chunk.length; i++) if (bad === null && chunk[i] !== (got + i) % 251) bad = got + i; got += chunk.length; };"
   "const pump = () => {"
   "  if (taken >= total) { if (kind.startsWith('h2')) out.end(); return; }"
   "  const n = Math.min(block.length, total - taken);"
   "  out.write(block.subarray(0, n), (err) => { if (!err) { taken += n; last = performance.now(); pump(); } });"
   "};"
   "const start = () => {"
   "  last = performance.now();"
   "  watch = setInterval(() => {"
   "    if (taken >= total || performance.now() - last >= 500) {"
   "      clearInterval(watch); stall = taken < total ? `stalled ${taken}` : 'whole'; resume();"
   "    }"
   "  }, 20);"
   "  pump();"
   "};"
   "const done = () => { console.log(`(uploaded ${stall} ${taken} ${JSON.stringify(head)} ${got} ${bad === null ? 'ok' : bad})`); process.exit(0); };"
   "if (kind.startsWith('raw')) {"
   "  out = kind === 'raw' ? net.connect(Number(port), host)"
   "    : tls.connect({ host, port: Number(port), servername: 'localhost', rejectUnauthorized: false, ALPNProtocols: ['http/1.1'] });"
   "  out.on('data', (chunk) => {"
   "    if (head === null) {"
   "      buf = Buffer.concat([buf, chunk]); const at = buf.indexOf('\\r\\n\\r\\n'); if (at < 0) return;"
   "      head = buf.subarray(0, at).toString('latin1'); chunk = buf.subarray(at + 4);"
   "    }"
   "    take(chunk);"
   "  });"
   "  out.pause();"
   "  out.on('end', done);"
   "  out.on('error', (err) => fail(err.code));"
   "  resume = () => out.resume();"
   "  out.on(kind === 'raw' ? 'connect' : 'secureConnect', () => {"
   "    out.write(`POST /raw/mirror HTTP/1.1\\r\\nHost: 127.0.0.1\\r\\nContent-Length: ${total}\\r\\n\\r\\n`); start();"
   "  });"
   "} else {"
   "  const session = http2.connect(`${kind === 'h2c' ? 'http' : 'https'}://${host}:${port}`, { servername: 'localhost', rejectUnauthorized: false });"
   "  session.on('error', (err) => fail(err.code));"
   "  out = session.request({ ':method': 'POST', ':path': '/mirror', 'content-length': String(total) });"
   "  out.on('response', (h) => { head = `:status ${h[':status']} content-length ${h['content-length']}`; });"
   "  out.on('data', take);"
   "  out.pause();"
   "  out.on('end', () => { session.close(); done(); });"
   "  out.on('error', (err) => fail(err.code));"
   "  resume = () => out.resume();"
   "  session.on('connect', start);"
   "}"))

;; upload : Origin Symbol Natural -> List
;; The uploader's line against FACE's mirror, BYTES bytes, read as data, its
;; STALL's bytes written short-of-the-end when they are past 0 and short of
;; BYTES; or (exit STATUS STDOUT STDERR) when it did not exit 0.
(define (upload o face bytes)
  (guard (e (#t (list 'raised (describe e))))
    (let* ((f (origin-face o face))
           (r (capture-command (list node "-e" uploader (symbol->string face) (car f)
                                     (number->string (cdr f)) (number->string bytes)))))
      (if (not (= (car r) 0))
          (list 'exit r)
          (let ((line (read (open-string-input-port (cadr r)))))
            (if (and (list? line) (> (length line) 3) (eq? (cadr line) 'stalled)
                     (integer? (caddr line)) (< 0 (caddr line) bytes))
                (cons* (car line) 'stalled 'short-of-the-end (cdddr line))
                line))))))

;; slice : Bytevector Natural Natural -> Bytevector
(define (slice bytes start end)
  (let ((b (make-bytevector (- end start))))
    (bytevector-copy! bytes start b 0 (- end start))
    b))

;; h2-frame-list : Bytevector -> (Listof (List Natural Natural Natural Bytevector))
;; BYTES' frames, read one after another: each one's type, flags, stream
;; and payload, the last cut short when BYTES are.
(define (h2-frame-list bytes)
  (let loop ((at 0) (found '()))
    (if (> (+ at 9) (bytevector-length bytes))
        (reverse found)
        (let* ((u8 (lambda (i) (bytevector-u8-ref bytes (+ at i))))
               (n (+ (* 65536 (u8 0)) (* 256 (u8 1)) (u8 2)))
               (stream (+ (* 16777216 (mod (u8 5) 128)) (* 65536 (u8 6)) (* 256 (u8 7)) (u8 8))))
          (loop (+ at 9 n)
                (cons (list (u8 3) (u8 4) stream
                            (slice bytes (+ at 9) (min (+ at 9 n) (bytevector-length bytes))))
                      found))))))

;; huffman-codes : (Listof (Pair Char String))
;; HPACK's Huffman code (RFC 7541, appendix B) for the characters a
;; summary line holds, as bits. Checked against what nghttp2 wrote for
;; /status/200 and for two summary lines, on Node 20.10.0.
(define huffman-codes
  '((#\space . "010100") (#\% . "010101") (#\- . "010110") (#\. . "010111") (#\/ . "011000")
    (#\0 . "00000") (#\1 . "00001") (#\2 . "00010") (#\3 . "011001") (#\4 . "011010")
    (#\5 . "011011") (#\6 . "011100") (#\7 . "011101") (#\8 . "011110") (#\9 . "011111")
    (#\: . "1011100") (#\; . "11111011") (#\= . "100000") (#\@ . "1111111111010") (#\A . "100001")
    (#\B . "1011101") (#\C . "1011110") (#\D . "1011111") (#\E . "1100000") (#\F . "1100001")
    (#\G . "1100010") (#\H . "1100011") (#\I . "1100100") (#\J . "1100101") (#\K . "1100110")
    (#\L . "1100111") (#\M . "1101000") (#\N . "1101001") (#\O . "1101010") (#\P . "1101011")
    (#\Q . "1101100") (#\R . "1101101") (#\S . "1101110") (#\T . "1101111") (#\U . "1110000")
    (#\V . "1110001") (#\W . "1110010") (#\X . "11111100") (#\Y . "1110011") (#\Z . "11111101")
    (#\_ . "100010") (#\, . "11111010") (#\a . "00011") (#\b . "100011") (#\c . "00100")
    (#\d . "100100") (#\e . "00101") (#\f . "100101") (#\g . "100110") (#\h . "100111")
    (#\i . "00110") (#\j . "1110100") (#\k . "1110101") (#\l . "101000") (#\m . "101001")
    (#\n . "101010") (#\o . "00111") (#\p . "101011") (#\q . "1110110") (#\r . "101100")
    (#\s . "01000") (#\t . "01001") (#\u . "101101") (#\v . "1110111") (#\w . "1111000")
    (#\x . "1111001") (#\y . "1111010") (#\z . "1111011") (#\" . "1111111001")))

;; huffman-text : Bytevector -> (U String #f)
;; BYTES, in HPACK's Huffman code, decoded by huffman-codes; #f for a code
;; none of them is, or padding that is not under 8 bits, every one a 1.
(define (huffman-text bytes)
  (let* ((bits (apply string-append
                      (map (lambda (b)
                             (let ((digits (number->string b 2)))
                               (string-append (make-string (- 8 (string-length digits)) #\0) digits)))
                           (bytevector->u8-list bytes))))
         (n (string-length bits)))
    (let loop ((at 0) (chars '()))
      (let ((hit (find (lambda (code)
                         (let ((k (string-length (cdr code))))
                           (and (<= (+ at k) n) (string=? (substring bits at (+ at k)) (cdr code)))))
                       huffman-codes)))
        (cond (hit (loop (+ at (string-length (cdr hit))) (cons (car hit) chars)))
              ((and (< (- n at) 8) (for-all (lambda (c) (char=? c #\1)) (string->list (substring bits at n))))
               (list->string (reverse chars)))
              (else #f))))))

;; --- HPACK, decoded (M8 slice 2): the head routes' blocks -------------------

;; hpack-static : (Vector (Pair String String))
;; RFC 7541's static table, appendix A: entry I at index I, 1 to 61.
(define hpack-static
  (list->vector
   (cons #f
         (map (lambda (e) (if (pair? e) e (cons e "")))
              '(":authority" (":method" . "GET") (":method" . "POST") (":path" . "/")
                (":path" . "/index.html") (":scheme" . "http") (":scheme" . "https")
                (":status" . "200") (":status" . "204") (":status" . "206") (":status" . "304")
                (":status" . "400") (":status" . "404") (":status" . "500") "accept-charset"
                ("accept-encoding" . "gzip, deflate") "accept-language" "accept-ranges" "accept"
                "access-control-allow-origin" "age" "allow" "authorization" "cache-control"
                "content-disposition" "content-encoding" "content-language" "content-length"
                "content-location" "content-range" "content-type" "cookie" "date" "etag" "expect"
                "expires" "from" "host" "if-match" "if-modified-since" "if-none-match" "if-range"
                "if-unmodified-since" "last-modified" "link" "location" "max-forwards"
                "proxy-authenticate" "proxy-authorization" "range" "referer" "refresh" "retry-after"
                "server" "set-cookie" "strict-transport-security" "transfer-encoding" "user-agent"
                "vary" "via" "www-authenticate")))))

;; huffman-table : Hashtable
;; huffman-codes, keyed by a code's value times 64 plus its length in bits.
(define huffman-table
  (let ((table (make-eqv-hashtable)))
    (for-each (lambda (code)
                (hashtable-set! table (+ (* 64 (string->number (cdr code) 2)) (string-length (cdr code)))
                                (car code)))
              huffman-codes)
    table))

;; huffman-decode : Bytevector -> (U String #f)
;; BYTES in HPACK's Huffman code, as huffman-text reads them, bit by bit:
;; #f for a code huffman-codes lacks, or padding that is not under 8 bits of
;; 1s.
(define (huffman-decode bytes)
  (let loop ((i 0) (bit 7) (code 0) (k 0) (chars '()))
    (if (= i (bytevector-length bytes))
        (and (< k 8) (= code (- (expt 2 k) 1)) (list->string (reverse chars)))
        (let* ((b (bitwise-and (bitwise-arithmetic-shift-right (bytevector-u8-ref bytes i) bit) 1))
               (code (+ (* 2 code) b))
               (k (+ k 1))
               (next-i (if (= bit 0) (+ i 1) i))
               (next-bit (if (= bit 0) 7 (- bit 1)))
               (char (hashtable-ref huffman-table (+ (* 64 code) k) #f)))
          (cond (char (loop next-i next-bit 0 0 (cons char chars)))
                ((> k 30) #f)
                (else (loop next-i next-bit code k chars)))))))

;; hpack-integer : Bytevector Natural Natural -> (U (Pair Natural Natural) #f)
;; The integer at AT with a BITS-bit prefix (RFC 7541, 5.1), and where it
;; ends; #f when BLOCK ends first.
(define (hpack-integer block at bits)
  (and (< at (bytevector-length block))
       (let* ((top (- (expt 2 bits) 1))
              (first (bitwise-and (bytevector-u8-ref block at) top)))
         (if (< first top)
             (cons first (+ at 1))
             (let loop ((i (+ at 1)) (n top) (shift 1))
               (and (< i (bytevector-length block))
                    (let* ((b (bytevector-u8-ref block i))
                           (n (+ n (* shift (mod b 128)))))
                      (if (>= b 128) (loop (+ i 1) n (* shift 128)) (cons n (+ i 1))))))))))

;; hpack-literal : Bytevector Natural -> (U (Pair String Natural) #f)
;; The string literal at AT, decoded, and where it ends.
(define (hpack-literal block at)
  (let ((s (hpack-string block at)))
    (and s
         (let* ((bytes (slice block (cadr s) (caddr s)))
                (text (if (car s) (huffman-decode bytes) (latin-1 bytes))))
           (and text (cons text (caddr s)))))))

;; hpack-decode : Bytevector (Pair (Listof (Pair String String)) Natural)
;;                -> (U (Pair (Listof (Pair String String)) (Pair (Listof ...) Natural)) #f)
;; BLOCK's fields, in order, and the dynamic table after it, TABLE being the
;; one before: its entries, newest first, and their size, each entry's name
;; and value bytes and 32, evicted oldest first past 4,096 bytes, the size
;; a client's empty SETTINGS leaves it (RFC 7541, 4.1 and 4.4). Indexed
;; fields, literals with and without indexing, and size updates; #f for
;; anything else, or an index no table holds.
(define (hpack-decode block table)
  (define (entry index entries)
    (cond ((<= 1 index 61) (vector-ref hpack-static index))
          ((< (- index 62) (length entries)) (list-ref entries (- index 62)))
          (else #f)))
  (define (added entries size field)
    (let ((n (+ (string-length (car field)) (string-length (cdr field)) 32)))
      (let trim ((kept (cons field entries)) (total (+ size n)))
        (if (and (> total 4096) (pair? kept))
            (let ((last (list-ref kept (- (length kept) 1))))
              (trim (let take ((rest kept) (k (- (length kept) 1)))
                      (if (= k 0) '() (cons (car rest) (take (cdr rest) (- k 1)))))
                    (- total (string-length (car last)) (string-length (cdr last)) 32)))
            (cons kept total)))))
  (let loop ((at 0) (fields '()) (entries (car table)) (size (cdr table)))
    (if (= at (bytevector-length block))
        (cons (reverse fields) (cons entries size))
        (let ((b (bytevector-u8-ref block at)))
          (cond
            ((>= b 128)
             (let* ((i (hpack-integer block at 7)) (e (and i (entry (car i) entries))))
               (and e (loop (cdr i) (cons e fields) entries size))))
            ((>= b 32)
             (let* ((incremental (>= b 64))
                    (i (hpack-integer block at (if incremental 6 5))))
               (cond
                 ((not i) #f)
                 ((not incremental) (loop (cdr i) fields entries size))
                 (else
                  (let* ((name (if (= (car i) 0)
                                   (hpack-literal block (cdr i))
                                   (let ((e (entry (car i) entries))) (and e (cons (car e) (cdr i))))))
                         (value (and name (hpack-literal block (cdr name)))))
                    (and value
                         (let* ((field (cons (car name) (car value)))
                                (grown (added entries size field)))
                           (loop (cdr value) (cons field fields) (car grown) (cdr grown)))))))))
            (else
             (let* ((i (hpack-integer block at 4))
                    (name (and i (if (= (car i) 0)
                                     (hpack-literal block (cdr i))
                                     (let ((e (entry (car i) entries))) (and e (cons (car e) (cdr i)))))))
                    (value (and name (hpack-literal block (cdr name)))))
               (and value (loop (cdr value) (cons (cons (car name) (car value)) fields) entries size)))))))))

;; h2-heads : Bytevector -> List
;; What BYTES, a probe's of one request on stream 1, carry there: each
;; header block, a HEADERS frame's payload and the CONTINUATION frames'
;; after it, decoded in order with one dynamic table, as fields; each
;; block's bytes; whether END_STREAM came; the DATA payloads, joined, as
;; text; and every other frame type stream 1 or the connection carried
;; past SETTINGS, RST_STREAM and GOAWAY among them. (unread ...) for a
;; block it cannot decode.
(define CONTINUATION 9)
(define (h2-heads bytes)
  (let loop ((frames (h2-frame-list bytes)) (blocks '()) (sizes '()) (open #f) (table (cons '() 0))
             (ended #f) (data '()) (others '()))
    (define (closed)
      (if open
          (let ((decoded (hpack-decode open table)))
            (and decoded (list (car decoded) (bytevector-length open) (cdr decoded))))
          (list #f #f table)))
    (if (null? frames)
        (let ((last (closed)))
          (if (not last)
              (list 'unread (hex bytes))
              (list (reverse (if open (cons (car last) blocks) blocks))
                    (reverse (if open (cons (cadr last) sizes) sizes))
                    ended (latin-1 (join (reverse data))) (reverse others))))
        (let* ((f (car frames)) (type (car f)) (flags (cadr f)) (stream (caddr f)) (payload (cadddr f)))
          (cond
            ((and (= type CONTINUATION) open)
             (loop (cdr frames) blocks sizes (join (list open payload)) table ended data others))
            (else
             (let ((last (closed)))
               (if (not last)
                   (list 'unread (hex bytes))
                   (let ((blocks (if open (cons (car last) blocks) blocks))
                         (sizes (if open (cons (cadr last) sizes) sizes))
                         (table (caddr last)))
                     (cond
                       ((and (= type HEADERS) (= stream 1))
                        (loop (cdr frames) blocks sizes payload table (or ended (odd? flags)) data others))
                       ((and (= type DATA) (= stream 1))
                        (loop (cdr frames) blocks sizes #f table (or ended (odd? flags)) (cons payload data) others))
                       ((= type SETTINGS) (loop (cdr frames) blocks sizes #f table ended data others))
                       (else (loop (cdr frames) blocks sizes #f table ended data
                                   (cons (list type flags stream) others)))))))))))))

;; head-fields : Natural Natural -> (Listof (Pair String String))
;; The generated fields of an HTTP/2 head of N lines of LINE bytes, as the
;; head routes make them, written here: x-000001 on, each value v repeated
;; to LINE less the name, ": " and CR LF.
(define (head-fields n line)
  (let loop ((i n) (found '()))
    (if (= i 0)
        found
        (let ((digits (number->string i)))
          (loop (- i 1)
                (cons (cons (string-append "x-" (make-string (- 6 (string-length digits)) #\0) digits)
                            (make-string (- line 12) #\v))
                      found))))))

;; hpack-string : Bytevector Natural -> (U (List Boolean Natural Natural) #f)
;; The string literal at AT in BLOCK: whether it is Huffman-coded, and where
;; its bytes start and end; its length a 7-bit prefix integer (RFC 7541,
;; 5.1). #f when BLOCK ends first.
(define (hpack-string block at)
  (and (< at (bytevector-length block))
       (let* ((first (bytevector-u8-ref block at))
              (huffman? (>= first 128)))
         (let loop ((i (+ at 1)) (n (mod first 128)) (shift 1) (more? (= (mod first 128) 127)))
           (cond ((and more? (< i (bytevector-length block)))
                  (let ((b (bytevector-u8-ref block i)))
                    (loop (+ i 1) (+ n (* shift (mod b 128))) (* shift 128) (>= b 128))))
                 (more? #f)
                 ((<= (+ i n) (bytevector-length block)) (list huffman? i (+ i n)))
                 (else #f))))))

;; h2-seq : Bytevector String Natural -> (List String (U Symbol List) Natural)
;; From BYTES a probe got for one /seq request on stream 1: the sink
;; header's value, decoded and shaped; whether BYTES are whole the answer
;; it makes, :status 200 indexed, 0x88, the sink header as a literal with
;; incremental indexing of a new name, 0x40, its name sink in Huffman code,
;; 0x83 41 aa eb, then the value as it came, then content-length N, then N
;; bytes of the pattern in one DATA frame that ends the stream; and how
;; many times the value held.
(define (h2-seq bytes n)
  (let* ((frames (h2-frame-list bytes))
         (headers (find (lambda (f) (and (= (car f) HEADERS) (= (caddr f) 1))) frames))
         (block (and headers (cadddr headers)))
         (named (and block (> (bytevector-length block) 6)
                     (bytevector=? (slice block 0 6) #vu8(#x88 #x40 #x83 #x41 #xaa #xeb))))
         (value (and named (hpack-string block 6)))
         (text (and value (let ((bytes (slice block (cadr value) (caddr value))))
                            (if (car value) (huffman-text bytes) (latin-1 bytes)))))
         (shaped (and text (shape text))))
    (if (not shaped)
        (list 'unread (hex bytes) 0)
        (let ((want (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                                (frame HEADERS END-HEADERS 1 (join (list (slice block 0 (caddr value))
                                                                         (content-length-field n))))
                                (frame DATA END-STREAM 1 (octets (pattern-text n)))))))
          (list (car shaped)
                (if (bytevector=? want bytes) 'whole-frames (list 'frames (hex bytes) 'want (hex want)))
                (length (cadr shaped)))))))

(define (duplex-scenarios o)
  (define p10 (pattern-text 10))
  (define tls1-options '("--tls" "localhost" "--alpn" "http/1.1"))

  ;; --- raw-tls: the stream calls' scripts over TLS
  (test-equal "raw-tls /raw/answer-at?status=303&after=0&to=%2Fx&close=1, a body after its head: the answer, its Location, Connection: close, then eof"
    (list (early-text "303" "/x" #t) 'eof)
    (exchange o 'raw-tls (string-append (post "/raw/answer-at?status=303&after=0&to=%2Fx&close=1" "Content-Length: 10\r\n") p10)
              2000 http1-tls))
  (test-equal "raw-tls /raw/answer-at?status=413&after=5, the body's first 4 bytes with the head and the rest 300 ms on: the answer, no Connection, only once the rest is sent, then eof"
    (list (list (early-text "413" #f #f) 'eof) 'after-the-rest)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((head (post "/raw/answer-at?status=413&after=5" "Content-Length: 10\r\n"))
             (p (split-probe o 'raw-tls (octets (string-append head p10)) (+ (string-length head) 4) 300 2000 tls1-options))
             (first (arrival (probe-arrivals p) 0)))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and first (>= (- first (probe-connected p)) 300)) 'after-the-rest
                  (list 'connected (probe-connected p) 'first first))))))
  (test-equal "raw-tls /raw/mirror: 10 bytes by Content-Length back whole; a chunked body's pieces back, each its own chunk; then eof"
    (list (list (string-append "HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\n" p10) 'eof)
          (list (string-append "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
                               "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n")
                'eof))
    (list (exchange o 'raw-tls (string-append (post "/raw/mirror" "Content-Length: 10\r\n") p10) 2000 http1-tls)
          (exchange o 'raw-tls (string-append (post "/raw/mirror" "Transfer-Encoding: chunked\r\n")
                                              "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n")
                    2000 http1-tls)))
  (test-equal "raw-tls /raw/mirror, 64 MiB to a client that reads nothing: its upload stalls past 0 and short of the end; once it reads, the rest goes, and the whole body comes back"
    (list 'uploaded 'stalled 'short-of-the-end 67108864
          "HTTP/1.1 200 OK\r\nContent-Length: 67108864\r\nConnection: close" 67108864 'ok)
    (upload o 'raw-tls 67108864))
  (test-equal "raw-tls /raw/seq?key=ts-seq&bytes=600, a GET: Sink: the summary, sink raw-tls, Content-Length: 600, then the pattern's 600 bytes, then eof"
    (list (string-append "HTTP/1.1 200 OK\r\nSink: sink raw-tls method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                         " pattern=ok arrivals=0 gap=- seen=1\r\nContent-Length: 600\r\nConnection: close")
          'same '() 'eof)
    (let ((got (exchange o 'raw-tls (get "/raw/seq?key=ts-seq&bytes=600") 2000 http1-tls)))
      (if (eq? (car got) 'raised) got (append (seq-response (car got)) (list (cadr got))))))
  ;; Over TLS each write is a record, and arrives as a chunk of its own.
  (test-equal "raw-tls /raw/retry, how=status, slow=300: the failure's head and its body's first byte, then the rest 150 ms or more after it, then eof"
    (list (list "HTTP/1.1 503 Retry\r\nContent-Length: 10\r\nConnection: close\r\n\r\nattempt 1\n" 'eof)
          'rest-after-the-first)
    (guard (e (#t (list 'raised (describe e))))
      (let* ((p (parameterize ((wire-probe-tls http1-tls))
                  (wire-probe o 'raw-tls (octets (get "/raw/retry?key=ts-slow&fail=1&how=status&code=503&slow=300")) 2000)))
             (head (string-length "HTTP/1.1 503 Retry\r\nContent-Length: 10\r\nConnection: close\r\n\r\n"))
             (first (arrival (probe-arrivals p) head))
             (rest (arrival (probe-arrivals p) (+ head 1))))
        (list (list (latin-1 (probe-bytes p)) (probe-end p))
              (if (and first rest (>= (* 2 (- rest first)) 300)) 'rest-after-the-first
                  (list 'first first 'rest rest (probe-arrivals p)))))))
  ;; The arm is the raw face's alone: armed from raw-tls with mode=keep,
  ;; raw-tls's next connection plays its script, and raw's next gets the
  ;; answer, then the end once its request is read.
  (test-equal "raw-tls /raw/arm?status=307&mode=keep&to=%2Fk arms the raw face alone: raw-tls's next connection plays its script; raw's next gets the answer, its Location, no Connection, then eof once its request is read"
    (list '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n" eof)
          '("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n" eof)
          (list (early-text "307" "/k" #f) 'eof))
    (in-order (lambda (thunk) (thunk))
              (list (lambda () (exchange o 'raw-tls (get "/raw/arm?status=307&mode=keep&to=%2Fk") 2000 http1-tls))
                    (lambda () (exchange o 'raw-tls (get "/raw/content-length") 2000 http1-tls))
                    (lambda () (exchange o 'raw (get "/raw/content-length") 2000 #f)))))

  ;; --- HTTP/2, on h2c and h2: /answer-at, /mirror and /seq. The HPACK
  ;; nghttp2 writes, measured on Node 20.10.0: :status 303 a literal with
  ;; incremental indexing of static name 8, its digits as they are, 0x48
  ;; 0x03; location as /redirect's; content-length as content-length-field
  ;; writes it.
  (for-each
   (lambda (face scheme tls options)
     (define (named what) (string-append (symbol->string face) " " what))
     (define (key what) (string-append (symbol->string face) "-" what))
     (define (half-closed bytes)
       (parameterize ((wire-probe-tls tls)) (wire-probe-half-close o face bytes 2000)))
     (define early-200 (answer (join (list #vu8(#x88) (content-length-field 10))) "early 200\n"))
     (test-equal (named "GET /answer-at?status=303&after=0&to=%2Fstatus%2F200: :status 303, location, content-length 10 and early 303, whole frames, then eof; 204 its HEADERS alone")
       (list (list (hex (answer (join (list #vu8(#x48 #x03 #x33 #x30 #x33)
                                            #vu8(#x0f #x1f #x88 #x61 #x09 #x1a #x6d #x43 #x02 #x00 #x3f)
                                            (content-length-field 10)))
                                "early 303\n"))
                   'eof)
             (list (hex (answer #vu8(#x89) #f)) 'eof))
       (list (h2-exchange o face (request scheme "GET" "/answer-at?status=303&after=0&to=%2Fstatus%2F200" '() #f) tls)
             (h2-exchange o face (request scheme "GET" "/answer-at?after=0&status=204" '() #f) tls)))
     ;; DATA of 3 bytes, then, 300 ms on, DATA of 4 that ends the stream.
     (test-equal (named "POST /answer-at?status=200&after=3, its DATA split 3 then 4 bytes, 300 ms apart: the answer, whole frames, before the second; eof only after it")
       (list (list (hex early-200) 'eof) 'answered-before 'ended-after)
       (guard (e (#t (list 'raised (describe e))))
         (let* ((first (join (list (h2-start scheme "POST" "/answer-at?status=200&after=3" '(("content-length" . "7")))
                                   (frame DATA 0 1 (octets "abc")))))
                (p (split-probe o face (join (list first (frame DATA END-STREAM 1 (octets "defg"))))
                                (bytevector-length first) 300 2000 (cons "--half-close" options)))
                (last (arrival (probe-arrivals p) (- (bytevector-length (probe-bytes p)) 1))))
           (list (list (hex (probe-bytes p)) (probe-end p))
                 (if (and last (< (- last (probe-connected p)) 300)) 'answered-before
                     (list 'connected (probe-connected p) 'last last))
                 (if (>= (- (probe-ended p) (probe-connected p)) 300) 'ended-after
                     (list 'connected (probe-connected p) 'ended (probe-ended p)))))))
     (test-equal (named "POST /answer-at?status=200&after=5, its DATA split 3 then 4 bytes, 300 ms apart: the answer, whole frames, only after the second")
       (list (list (hex early-200) 'eof) 'answered-after)
       (guard (e (#t (list 'raised (describe e))))
         (let* ((first (join (list (h2-start scheme "POST" "/answer-at?status=200&after=5" '(("content-length" . "7")))
                                   (frame DATA 0 1 (octets "abc")))))
                (p (split-probe o face (join (list first (frame DATA END-STREAM 1 (octets "defg"))))
                                (bytevector-length first) 300 2000 (cons "--half-close" options)))
                (headers-at (arrival (probe-arrivals p) 18)))
           (list (list (hex (probe-bytes p)) (probe-end p))
                 (if (and headers-at (>= (- headers-at (probe-connected p)) 300)) 'answered-after
                     (list 'connected (probe-connected p) 'headers-at headers-at))))))
     ;; A body shorter than N, its stream ended: answered at its end.
     (test-equal (named "POST /answer-at?status=200&after=100, 7 bytes that end the stream: the answer at the stream's end, whole frames, then eof")
       (list (hex early-200) 'eof)
       (h2-exchange o face (request scheme "POST" "/answer-at?status=200&after=100" '(("content-length" . "7")) "abcdefg") tls))
     (test-equal (named "a query /answer-at refuses: each 404")
       (map (lambda (n) (h2-not-found)) '(1 2 3 4 5 6 7 8 9 10 11 12 13 14))
       (in-order (lambda (target) (h2-exchange o face (request scheme "GET" target '() #f) tls))
                 '("/answer-at" "/answer-at?status=200" "/answer-at?after=0" "/answer-at?status=199&after=0"
                   "/answer-at?status=600&after=0" "/answer-at?status=200&after=268435457" "/answer-at?status=200&after=01"
                   "/answer-at?status=200&after=0&to=" "/answer-at?status=200&after=0&to=%zz"
                   "/answer-at?status=200&after=0&to=a%20b" "/answer-at?status=200&after=0&to=%2Fa&to=%2Fb"
                   "/answer-at?status=200&status=200&after=0" "/answer-at?status=200&after=0&close=1"
                   "/answer-at?status=200&after=0&x")))

     ;; /mirror: each DATA frame back as it comes, then an empty DATA frame
     ;; that ends the stream, at the request's end (measured). That frame
     ;; goes once the last write has gone, so a client's half-close sent
     ;; with its last DATA can end the session first: it did once under
     ;; load. So these probes never half-close; they read until 500 ms
     ;; pass with no data.
     (test-equal (named "POST /mirror: with content-length 7, :status 200 and that content-length, the DATA back, then an empty DATA ending the stream; without one, no content-length; a GET, the empty DATA alone; the connection then idle")
       (list (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                                    (frame HEADERS END-HEADERS 1 (join (list #vu8(#x88) (content-length-field 7))))
                                    (frame DATA 0 1 (octets "abcdefg")) (frame DATA END-STREAM 1 #vu8()))))
                   'timeout)
             (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                                    (frame HEADERS END-HEADERS 1 #vu8(#x88))
                                    (frame DATA 0 1 (octets "abcdefg")) (frame DATA END-STREAM 1 #vu8()))))
                   'timeout)
             (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                                    (frame HEADERS END-HEADERS 1 #vu8(#x88)) (frame DATA END-STREAM 1 #vu8()))))
                   'timeout))
       (in-order (lambda (bytes)
                   (guard (e (#t (list 'raised (describe e))))
                     (let ((p (parameterize ((wire-probe-tls tls)) (wire-probe o face bytes 500))))
                       (list (hex (probe-bytes p)) (probe-end p)))))
                 (list (request scheme "POST" "/mirror" '(("content-length" . "7")) "abcdefg")
                       (request scheme "POST" "/mirror" '() "abcdefg")
                       (request scheme "GET" "/mirror" '() #f))))
     (test-equal (named "POST /mirror, its DATA split 3 then 4 bytes, 300 ms apart: the first 3 back before the second is sent, whole frames, the connection then idle")
       (list (list (hex (join (list (frame SETTINGS 0 0 #vu8()) (frame SETTINGS ACK 0 #vu8())
                                    (frame HEADERS END-HEADERS 1 (join (list #vu8(#x88) (content-length-field 7))))
                                    (frame DATA 0 1 (octets "abc")) (frame DATA 0 1 (octets "defg"))
                                    (frame DATA END-STREAM 1 #vu8()))))
                   'timeout)
             'first-back-before)
       (guard (e (#t (list 'raised (describe e))))
         (let* ((first (join (list (h2-start scheme "POST" "/mirror" '(("content-length" . "7"))) (frame DATA 0 1 (octets "abc")))))
                (p (split-probe o face (join (list first (frame DATA END-STREAM 1 (octets "defg"))))
                                (bytevector-length first) 300 500 options))
                (back (arrival (probe-arrivals p) (+ 9 9 9 5 9 3 -1))))
           (list (list (hex (probe-bytes p)) (probe-end p))
                 (if (and back (< (- back (probe-connected p)) 300)) 'first-back-before
                     (list 'connected (probe-connected p) 'back back))))))
     (test-equal (named "POST /mirror, 16 MiB from a client that reads nothing: its upload stalls past 0 and short of the end, the stream's writes and so its reads paused; once it reads, the rest goes, and the whole body comes back")
       (list 'uploaded 'stalled 'short-of-the-end 16777216 ":status 200 content-length 16777216" 16777216 'ok)
       (upload o face 16777216))
     (test-equal (named "GET /mirror with a query: 404")
       (list (h2-not-found) (h2-not-found))
       (list (h2-exchange o face (request scheme "GET" "/mirror?x=1" '() #f) tls)
             (h2-exchange o face (request scheme "GET" "/mirror?" '() #f) tls)))

     ;; /seq: the sink header's value is Huffman-coded, so h2-seq decodes
     ;; it, and holds the rest of the frames whole.
     (test-equal (named "GET /seq?bytes=0: :status 200, sink holding the summary of no body, content-length 0, an empty DATA ending the stream, whole frames")
       (list (string-append "sink " (symbol->string face) " method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                            " pattern=ok arrivals=0 gap=- seen=1")
             'whole-frames 0 'eof)
       (guard (e (#t (list 'raised (describe e))))
         (let ((p (half-closed (request scheme "GET" (string-append "/seq?key=" (key "seq0") "&bytes=0") '() #f))))
           (append (h2-seq (probe-bytes p) 0) (list (probe-end p))))))
     (test-equal (named "POST /seq?bytes=600, 7 bytes: sink holding their summary, content-length 600, then the pattern's 600 bytes, whole frames; the key's second request seen=2, and /seen then reads 2")
       (list (list (string-append "sink " (symbol->string face) " method=POST cl=7 te=- expect=- ct=- bytes=7 sha256="
                                  sha-abcdefg " pattern=bad@0 arrivals=1 gap=~@0 seen=1")
                   'whole-frames 1 'eof)
             (list (string-append "sink " (symbol->string face) " method=GET cl=- te=- expect=- ct=- bytes=0 sha256=" sha-empty
                                  " pattern=ok arrivals=0 gap=- seen=2")
                   'whole-frames 0 'eof)
             (h2-seen 2))
       (guard (e (#t (list 'raised (describe e))))
         (in-order (lambda (thunk) (thunk))
                   (list (lambda ()
                           (let ((p (half-closed (request scheme "POST" (string-append "/seq?key=" (key "seq600") "&bytes=600")
                                                          '(("content-length" . "7")) "abcdefg"))))
                             (append (h2-seq (probe-bytes p) 600) (list (probe-end p)))))
                         (lambda ()
                           (let ((p (half-closed (request scheme "GET" (string-append "/seq?bytes=1&key=" (key "seq600")) '() #f))))
                             (append (h2-seq (probe-bytes p) 1) (list (probe-end p)))))
                         (lambda () (h2-exchange o face (request scheme "GET" (string-append "/seen?key=" (key "seq600")) '() #f) tls))))))
     (test-equal (named "a query /seq refuses: each 404, counting nothing")
       (append (map (lambda (n) (h2-not-found)) '(1 2 3 4 5 6 7 8)) (list (h2-seen 0)))
       (in-order (lambda (target) (h2-exchange o face (request scheme "GET" target '() #f) tls))
                 (list "/seq" (string-append "/seq?key=" (key "seq-refused"))
                       "/seq?bytes=1" (string-append "/seq?key=" (key "seq-refused") "&bytes=268435457")
                       (string-append "/seq?key=" (key "seq-refused") "&bytes=01")
                       (string-append "/seq?key=" (key "seq-refused") "&bytes=1&bytes=1")
                       (string-append "/seq?key=" (key "seq-refused") "&bytes=1&x=1")
                       "/seq?key=&bytes=1"
                       (string-append "/seen?key=" (key "seq-refused"))))))
   '(h2c h2) '("http" "https") (list #f h2-tls) '(() ("--tls" "localhost" "--alpn" "h2"))))

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
  ;; The head routes (M8 slice 2; ADR-0040), decoded: each block's fields
  ;; whole, against this suite's own list; END_STREAM; the body; and no other
  ;; frame. The large ones are past Node's default send limit, 64 KiB, which
  ;; both faces raise: at the default the head is never sent, and the trailer
  ;; block is dropped or the stream reset, by Node's version (traps.md). A
  ;; trailer block goes in a write of its own after the head, and the large
  ;; head in several, which a client's half-close can cut, as it cuts a long
  ;; body's (h2EndNext's comment): under the memory gate's load h2 lost the
  ;; trailers of /head?n=2&tn=6000 so (M8 slice 2's build). Those rows' probe
  ;; does not half-close: it reads until it has been idle, and ends there.
  (let ((digest "Digest realm=\"chez-curl-test\", qop=\"auth\", nonce=\"n0\", algorithm=MD5")
        (cl0 '("content-length" . "0")))
    (for-each
     (lambda (face scheme tls)
       (define (heads path headers)
         (guard (e (#t (list 'raised (describe e))))
           (let ((p (parameterize ((wire-probe-tls tls))
                      (if (string-contains? path "tn=")
                          (wire-probe o face (request scheme "GET" path headers #f) 1000)
                          (wire-probe-half-close o face (request scheme "GET" path headers #f) 2000)))))
             (append (let ((h (h2-heads (probe-bytes p))))
                       (if (eq? (car h) 'unread) h (list (car h) (caddr h) (cadddr h) (car (cddddr h)))))
                     (list (probe-end p))))))
       (for-each
        (lambda (row)
          (test-equal (string-append (symbol->string face) " GET " (car row) (cadr row)
                                     ": each block's fields, whole, END_STREAM, the body, no other frame, then "
                                     (if (string-contains? (car row) "tn=") "idle" "eof"))
            (append (caddr row) (list (if (string-contains? (car row) "tn=") 'timeout 'eof)))
            (heads (car row) (if (null? (cdddr row)) '() (cadddr row)))))
        (list (list "/head?n=3" "" (list (list (cons '(":status" . "200") (cons cl0 (head-fields 2 16)))) #t "" '()))
              (list "/head" "" (list (list (list '(":status" . "200") cl0)) #t "" '()))
              (list "/head?n=2&tn=2" ""
                    (list (list (cons '(":status" . "200") (head-fields 2 16)) (head-fields 2 16)) #t "" '()))
              (list "/head?pre=103:2:20&n=2" ""
                    (list (list (cons '(":status" . "103") (head-fields 2 20))
                                (cons '(":status" . "200") (cons cl0 (head-fields 1 16))))
                          #t "" '()))
              (list "/head?n=1&big=20&bigch=X" ""
                    (list (list (list '(":status" . "200") cl0 '("x-big" . "XXXXXXXXXXX"))) #t "" '()))
              (list "/head-auth?a.n=2&b.n=3" ""
                    (list (list (list '(":status" . "401") (cons "www-authenticate" digest) cl0
                                      (car (head-fields 1 16))))
                          #t "" '()))
              (list "/head-auth?a.n=2&b.n=3" ", with an Authorization, unchecked"
                    (list (list (cons '(":status" . "200") (cons cl0 (head-fields 2 16)))) #t "" '())
                    '(("authorization" . "Digest anything")))
              (list "/head?x=1" ", a parameter it does not take"
                    (list (list '((":status" . "404") ("content-length" . "10"))) #t "not found\n" '()))
              (list "/head?n=2&line=32&hname=1" ", hname, the raw face's alone"
                    (list (list '((":status" . "404") ("content-length" . "10"))) #t "not found\n" '()))
              (list "/head?n=2&tn=1&tname=1" ", tname, the raw face's alone"
                    (list (list '((":status" . "404") ("content-length" . "10"))) #t "not found\n" '()))
              (list "/head-auth?a.n=2&b.v10=1" ", v10, the raw face's alone"
                    (list (list '((":status" . "404") ("content-length" . "10"))) #t "not found\n" '()))
              (list "/proxy-arm?n=1" ", an HTTP/1.1 route"
                    (list (list '((":status" . "404") ("content-length" . "10"))) #t "not found\n" '())))))
     '(h2c h2) '("http" "https") (list #f h2-tls))
    ;; The large ones, 6,000 lines of 16 bytes in a head and in a trailer
    ;; block, each block past 64 KiB on the wire: compared whole, but shown
    ;; as same or the first field that differs.
    (for-each
     (lambda (face scheme tls)
       (for-each
        (lambda (row)
          (test-equal (string-append (symbol->string face) " GET " (car row)
                                     ": every field of each block, as this suite lists them, the last block past 64 KiB, END_STREAM, no other frame, then idle")
            '(same past-64-kib #t "" () timeout)
            (guard (e (#t (list 'raised (describe e))))
              (let* ((p (parameterize ((wire-probe-tls tls))
                          (wire-probe o face (request scheme "GET" (car row) '() #f) 2000)))
                     (h (h2-heads (probe-bytes p))))
                (if (eq? (car h) 'unread)
                    (list 'unread (bytevector-length (probe-bytes p)) (probe-end p))
                    (list (if (equal? (car h) (cadr row))
                              'same
                              (list 'blocks (map length (car h)) 'want (map length (cadr row))))
                          (let ((sizes (cadr h)))
                            (if (and (pair? sizes) (> (list-ref sizes (- (length sizes) 1)) 65536))
                                'past-64-kib
                                (list 'sizes sizes)))
                          (caddr h) (cadddr h) (car (cddddr h)) (probe-end p)))))))
        (list (list "/head?n=6000" (list (cons '(":status" . "200") (cons cl0 (head-fields 5999 16)))))
              (list "/head?n=2&tn=6000"
                    (list (cons '(":status" . "200") (head-fields 2 16)) (head-fields 6000 16))))))
     '(h2c h2) '("http" "https") (list #f h2-tls)))
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

  ;; --- the sinks
  (sink-scenarios o)

  ;; --- the parts route
  (parts-scenarios o)

  ;; --- the stream calls' routes
  (duplex-scenarios o)

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

;; --- the auth route over TLS (M7 slice 2; the M7 plan, section 5.2) ---------------
;; Each test runs on an origin of its own, so the https face's handshakes and
;; h2's sessions are numbered from 1 there. Each log is read by the http
;; face, whose answer tests/test-origin.sps holds. The Authorization headers
;; are written here, by (auth-testing).

;; tls-origin : (Origin -> Any) -> (U (List 'returned Any) (List 'raised String))
(define (tls-origin proc)
  (outcome (lambda () (parameterize ((origin-pki pki)) (call-with-origin proc)))))

;; auth-closed : String (Listof String) String -> String
;; An HTTP/1.1 face's whole response with Connection: close.
(define (auth-closed status-line headers body)
  (string-append status-line "\r\n"
                 (apply string-append (map (lambda (h) (string-append h "\r\n")) headers))
                 "Content-Length: " (number->string (string-length body)) "\r\nConnection: close\r\n\r\n" body))

;; auth-log-text : String (Listof String) -> (List String Symbol)
;; The http face's /auth-log answer for KEY's LINES.
(define (auth-log-text key lines)
  (list (auth-closed "HTTP/1.1 200 OK" '()
                     (apply string-append "log " key " " (number->string (length lines)) "\n"
                            (map (lambda (l) (string-append l "\n")) lines)))
        'eof))

;; auth-logged : Origin String -> (List String Symbol)
(define (auth-logged o key)
  (exchange o 'http (get (string-append "/auth-log?key=" key) close) 2000 #f))

(test-equal "the auth route over https: no credentials, a 401 with Basic's challenge; Basic, 200; a Digest challenge, its nonce the query's, and the response computed here, 200; each request on its own handshake, logged face=https"
  (let ((uri "/auth?key=hb&ch=digest&nonce=n1&qop=none"))
    (list 'returned
          (list (list (auth-closed "HTTP/1.1 401 Unauthorized" '("WWW-Authenticate: Basic realm=\"chez-curl-test\"") "unauthorized\n") 'eof)
                (list (auth-closed "HTTP/1.1 200 OK" '() "auth ok\n") 'eof)
                (list (auth-closed "HTTP/1.1 401 Unauthorized"
                                   '("WWW-Authenticate: Digest realm=\"chez-curl-test\", nonce=\"n1\", opaque=\"opq5ccb\", algorithm=MD5")
                                   "unauthorized\n")
                      'eof)
                (list (auth-closed "HTTP/1.1 200 OK" '() "auth ok\n") 'eof)
                (auth-log-text "hb"
                               (list "request 1 face=https conn=1 method=GET body=0 verdict=none status=401 authorization=-"
                                     "request 2 face=https conn=2 method=GET body=0 verdict=ok status=200 authorization=Basic dXNlcjpwYXNz"
                                     "request 3 face=https conn=3 method=GET body=0 verdict=none status=401 authorization=-"
                                     (string-append "request 4 face=https conn=4 method=GET body=0 verdict=ok status=200 authorization="
                                                    "Digest username=\"user\", realm=\"chez-curl-test\", nonce=\"n1\", uri=\"" uri
                                                    "\", response=\""
                                                    (digest-response 'md5 (octets "user") "chez-curl-test" (octets "pass") "n1"
                                                                     #f #f #f "GET" uri)
                                                    "\", opaque=\"opq5ccb\", algorithm=MD5"))))))
  (tls-origin
   (lambda (o)
     (let* ((uri "/auth?key=hb&ch=digest&nonce=n1&qop=none")
            (digest (string-append "Authorization: Digest username=\"user\", realm=\"chez-curl-test\", nonce=\"n1\", uri=\""
                                   uri "\", response=\""
                                   (digest-response 'md5 (octets "user") "chez-curl-test" (octets "pass") "n1" #f #f #f "GET" uri)
                                   "\", opaque=\"opq5ccb\", algorithm=MD5\r\n"))
            (a (exchange o 'https (get "/auth?key=hb&ch=basic" close) 2000 http1-tls))
            (b (exchange o 'https (get "/auth?key=hb&ch=basic" "Authorization: Basic dXNlcjpwYXNz\r\n" close) 2000 http1-tls))
            (c (exchange o 'https (get uri close) 2000 http1-tls))
            (d (exchange o 'https (get uri digest close) 2000 http1-tls))
            (log (auth-logged o "hb")))
       (list a b c d log)))))

;; The answers' HEADERS, measured on Node 20.10.0 and 24.18.0: :status 200
;; 0x88; content-length 8 a literal without indexing of static name 28,
;; 0x0f 0x0d, its one digit as it is; the 401's :status a literal with
;; incremental indexing of static name 8, 0x48, then "401" in two bytes of
;; Huffman code, 0x82 0x68 0x01; www-authenticate a literal with
;; incremental indexing of static name 61, 0x7d, its value 22 bytes of
;; Huffman code, 0x96, Bearer realm="chez-curl-test", as Node's own HTTP/2
;; client decoded them (build/m7s2b/hpack/decode.mjs, on 24.18.0); then
;; content-length 13, its two digits as they are.
(test-equal "the auth route over h2: no credentials, a 401 with Bearer's challenge in www-authenticate; Bearer, 200; each its own session, logged face=h2"
  (list 'returned
        (list (list (hex (answer (u8-list->bytevector
                                  '(#x48 #x82 #x68 #x01
                                    #x7d #x96 #xba #x51 #xd8 #x5b #x14 #xb0 #xa3 #xa2 #x98 #x3f #x92 #x4e
                                    #x5f #x6b #x12 #xdb #x28 #x59 #x25 #x42 #x7f #x9f
                                    #x0f #x0d #x02 #x31 #x33))
                                 "unauthorized\n"))
                    'eof)
              (list (hex (answer #vu8(#x88 #x0f #x0d 1 #x38) "auth ok\n")) 'eof)
              (auth-log-text "h2b"
                             (list "request 1 face=h2 conn=1 method=GET body=0 verdict=none status=401 authorization=-"
                                   "request 2 face=h2 conn=2 method=GET body=0 verdict=ok status=200 authorization=Bearer tok123"))))
  (tls-origin
   (lambda (o)
     (let* ((a (h2-exchange o 'h2 (request "https" "GET" "/auth?key=h2b&ch=bearer" '() #f) h2-tls))
            (b (h2-exchange o 'h2 (request "https" "GET" "/auth?key=h2b&ch=bearer" '(("authorization" . "Bearer tok123")) #f)
                            h2-tls))
            (log (auth-logged o "h2b")))
       (list a b log)))))

;; --- the proxy over TLS (M7 slice 3; the M7 plan, section 6.2) --------------------
;; Each https face serves the proxy too, so it stands in for an https://
;; proxy; the probe speaks TLS to it and verifies nothing, so the expired,
;; wrong-host and untrusted faces serve as well, failing a client that
;; verifies them. Each test runs on an origin of its own, its proxy's
;; connections numbered from 1 there. Its log is read by the http face,
;; whose answer tests/test-origin.sps holds.

;; tls-proxy-log : Origin -> Any
;; /proxy-log?from=0's body on the http face, once the proxy holds no
;; connection open, waited for up to 5 s.
(define (tls-proxy-log o)
  (let ((deadline (+ (now-ms) 5000)))
    (let loop ()
      (let* ((a (exchange o 'http (get "/proxy-log?from=0" close) 2000 #f))
             (text (and (pair? a) (string? (car a))
                        (let find ((i 0))
                          (cond ((> (+ i 4) (string-length (car a))) #f)
                                ((string=? (substring (car a) i (+ i 4)) "\r\n\r\n")
                                 (substring (car a) (+ i 4) (string-length (car a))))
                                (else (find (+ i 1))))))))
        (cond ((not text) a)
              ((or (>= (now-ms) deadline)
                   (let ((k (string-length " open 0\n")))
                     (let scan ((i 0))
                       (and (<= (+ i k) (string-length text))
                            (or (string=? (substring text i (+ i k)) " open 0\n") (scan (+ i 1)))))))
               text)
              (else (pause-ms 20) (loop)))))))

;; tls-connect-text : String . String -> String
;; A CONNECT of TARGET, its Host, then HEADERS, each a whole line.
(define (tls-connect-text target . headers)
  (apply string-append "CONNECT " target " HTTP/1.1\r\nHost: " target "\r\n" (append headers (list "\r\n"))))

(test-equal "the proxy over TLS: on the https face, a CONNECT to the http face, a GET behind it, the tunnel's 200, then the face's answer; on the expired, wrong-host and untrusted faces alike, which a verifying client refuses; a refusal, 503, the connection kept; Basic for localhost, alice's passing; the log names each face, each inner request through its connection"
  '(returned same)
  (tls-origin
   (lambda (o)
     (let* ((http (string-append "127.0.0.1:" (number->string (cdr (origin-face o 'http)))))
            (local (string-append "localhost:" (number->string (cdr (origin-face o 'http)))))
            (alice (string-append "Proxy-Authorization: Basic " (base64-encode (octets "alice:s3cret")) "\r\n"))
            (behind (get "/status/200" close))
            (passed (list (string-append "HTTP/1.1 200 Connection Established\r\n\r\n"
                                         "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nstatus 200\n")
                          'eof))
            (head (lambda (text) (number->string (string-length text))))
            (want (list passed passed passed passed
                        (list "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 10\r\n\r\nproxy 503\n" 'timeout)
                        passed
                        (string-append
                         "proxy-log 17 open 0\n"
                         "connect https conn=1 target=" http " answer=200 head=" (head (tls-connect-text http)) " auth=-\n"
                         "inner http via=1 method=GET target=/status/200\n"
                         "close https conn=1\n"
                         "connect https-expired conn=2 target=" http " answer=200 head=" (head (tls-connect-text http)) " auth=-\n"
                         "inner http via=2 method=GET target=/status/200\n"
                         "close https-expired conn=2\n"
                         "connect https-wrong-host conn=3 target=" http " answer=200 head=" (head (tls-connect-text http)) " auth=-\n"
                         "inner http via=3 method=GET target=/status/200\n"
                         "close https-wrong-host conn=3\n"
                         "connect https-untrusted conn=4 target=" http " answer=200 head=" (head (tls-connect-text http)) " auth=-\n"
                         "inner http via=4 method=GET target=/status/200\n"
                         "close https-untrusted conn=4\n"
                         "connect https conn=5 target=refuse-503.invalid:443 answer=503 head="
                         (head (tls-connect-text "refuse-503.invalid:443")) " auth=-\n"
                         "close https conn=5\n"
                         "connect https conn=6 target=" local " answer=200 head=" (head (tls-connect-text local alice))
                         " auth=basic:alice:s3cret\n"
                         "inner http via=6 method=GET target=/status/200\n"
                         "close https conn=6\n")))
            (one (lambda (face text idle)
                   (let ((a (exchange o face text idle http1-tls)))
                     (tls-proxy-log o)
                     a)))
            ;; In turn, by let*: each probe's lines before the next's.
            (a (one 'https (string-append (tls-connect-text http) behind) 2000))
            (b (one 'https-expired (string-append (tls-connect-text http) behind) 2000))
            (c (one 'https-wrong-host (string-append (tls-connect-text http) behind) 2000))
            (d (one 'https-untrusted (string-append (tls-connect-text http) behind) 2000))
            (e (one 'https (tls-connect-text "refuse-503.invalid:443") 300))
            (f (one 'https (string-append (tls-connect-text local alice) behind) 2000))
            (got (list a b c d e f (tls-proxy-log o))))
       (if (equal? want got) 'same (list 'want want 'got got))))))

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
  "usage: node tests/wire-probe.mjs [--reset | --half-close] [--tls SERVERNAME [--alpn LIST]] [--split OFFSET:MS] [--deadline MS] HOST PORT HEX IDLE-MS\n")

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

(define origin-usage "usage: node tests/origin.mjs [--pki DIR | --selftest [PLANT]]\n")

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
