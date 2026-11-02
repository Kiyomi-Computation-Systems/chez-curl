#!r6rs
;;; (auth-testing): what the auth suites compute for themselves, never read
;;; from the test origin (M7 slice 2; the M7 plan, section 5.2): MD5 (RFC
;;; 1321) and SHA-256 (FIPS 180-4) of a bytevector, as lower-case hex;
;;; base64 (RFC 4648); and a Digest response, RFC 7616's arithmetic, RFC
;;; 2069's without a qop. tests/test-auth.sps holds each to its published
;;; vectors, and tests/test-origin.sps and tests/test-auth.sps write the
;;; Authorization headers they expect with it, so the origin's verifier
;;; and libcurl's arithmetic both meet a third, written here.
;;;
;;;   md5-hex          Bytevector -> String
;;;   sha256-hex       Bytevector -> String
;;;   base64-encode    Bytevector -> String
;;;   digest-response  Symbol Bytevector String Bytevector String (U String #f)
;;;                    (U String #f) (U String #f) String String -> String
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path, not in src/.
(library (auth-testing)
  (export md5-hex sha256-hex base64-encode digest-response)
  (import (rnrs))

  ;; --- 32-bit words ------------------------------------------------------------

  ;; w+ : Natural ... -> Natural
  ;; The sum of the words, modulo 2^32.
  (define (w+ . words) (bitwise-and (apply + words) #xFFFFFFFF))

  ;; rotl : Natural Natural -> Natural
  ;; WORD rotated left by N bits, within 32.
  (define (rotl word n)
    (bitwise-and (bitwise-ior (bitwise-arithmetic-shift-left word n)
                              (bitwise-arithmetic-shift-right word (- 32 n)))
                 #xFFFFFFFF))

  ;; rotr : Natural Natural -> Natural
  (define (rotr word n) (rotl word (- 32 n)))

  ;; wnot : Natural -> Natural
  (define (wnot word) (bitwise-xor word #xFFFFFFFF))

  ;; hex-of : (Listof Natural) Natural (Natural Natural -> Natural) -> String
  ;; Each of WORDS as four bytes, by BYTE-AT, as lower-case hex.
  (define (hex-of words byte-at)
    (apply string-append
           (map (lambda (word)
                  (apply string-append
                         (map (lambda (i)
                                (let ((b (byte-at word i)))
                                  (string (string-ref "0123456789abcdef" (div b 16))
                                          (string-ref "0123456789abcdef" (mod b 16)))))
                              '(0 1 2 3))))
                words)))

  ;; padded : Bytevector (Natural Bytevector Natural -> Void) -> Bytevector
  ;; BYTES, then 0x80, then zeros to 56 bytes modulo 64, then the bit length
  ;; in eight bytes, written by PUT-LENGTH at the offset given.
  (define (padded bytes put-length)
    (let* ((n (bytevector-length bytes))
           (total (* 64 (div (+ n 8 64) 64)))
           (out (make-bytevector total 0)))
      (bytevector-copy! bytes 0 out 0 n)
      (bytevector-u8-set! out n #x80)
      (put-length (* 8 n) out (- total 8))
      out))

  ;; --- MD5 (RFC 1321) -------------------------------------------------------------

  ;; md5-k : Vector
  ;; RFC 1321, section 3.4: the integer part of 4294967296 times abs(sin(i)),
  ;; i from 1 to 64, in radians.
  (define md5-k
    (vector #xd76aa478 #xe8c7b756 #x242070db #xc1bdceee #xf57c0faf #x4787c62a #xa8304613 #xfd469501
            #x698098d8 #x8b44f7af #xffff5bb1 #x895cd7be #x6b901122 #xfd987193 #xa679438e #x49b40821
            #xf61e2562 #xc040b340 #x265e5a51 #xe9b6c7aa #xd62f105d #x02441453 #xd8a1e681 #xe7d3fbc8
            #x21e1cde6 #xc33707d6 #xf4d50d87 #x455a14ed #xa9e3e905 #xfcefa3f8 #x676f02d9 #x8d2a4c8a
            #xfffa3942 #x8771f681 #x6d9d6122 #xfde5380c #xa4beea44 #x4bdecfa9 #xf6bb4b60 #xbebfbc70
            #x289b7ec6 #xeaa127fa #xd4ef3085 #x04881d05 #xd9d4d039 #xe6db99e5 #x1fa27cf8 #xc4ac5665
            #xf4292244 #x432aff97 #xab9423a7 #xfc93a039 #x655b59c3 #x8f0ccc92 #xffeff47d #x85845dd1
            #x6fa87e4f #xfe2ce6e0 #xa3014314 #x4e0811a1 #xf7537e82 #xbd3af235 #x2ad7d2bb #xeb86d391))

  ;; md5-shifts : Vector
  ;; Each step's rotation, four per round, each round's four repeated.
  (define md5-shifts
    (list->vector
     (apply append
            (map (lambda (four) (append four four four four))
                 '((7 12 17 22) (5 9 14 20) (4 11 16 23) (6 10 15 21))))))

  ;; md5-hex : Bytevector -> String
  (define (md5-hex bytes)
    (let ((message (padded bytes (lambda (bits out at)
                                   (bytevector-u64-set! out at bits (endianness little))))))
      (let block ((at 0) (a0 #x67452301) (b0 #xefcdab89) (c0 #x98badcfe) (d0 #x10325476))
        (if (= at (bytevector-length message))
            (hex-of (list a0 b0 c0 d0)
                    (lambda (word i) (bitwise-and (bitwise-arithmetic-shift-right word (* 8 i)) #xFF)))
            (let step ((i 0) (a a0) (b b0) (c c0) (d d0))
              (if (= i 64)
                  (block (+ at 64) (w+ a0 a) (w+ b0 b) (w+ c0 c) (w+ d0 d))
                  (let-values (((f g)
                                (cond ((< i 16) (values (bitwise-ior (bitwise-and b c) (bitwise-and (wnot b) d)) i))
                                      ((< i 32) (values (bitwise-ior (bitwise-and d b) (bitwise-and (wnot d) c))
                                                        (mod (+ (* 5 i) 1) 16)))
                                      ((< i 48) (values (bitwise-xor b c d) (mod (+ (* 3 i) 5) 16)))
                                      (else (values (bitwise-xor c (bitwise-ior b (wnot d)))
                                                    (mod (* 7 i) 16))))))
                    (let ((word (bytevector-u32-ref message (+ at (* 4 g)) (endianness little))))
                      (step (+ i 1) d
                            (w+ b (rotl (w+ a f (vector-ref md5-k i) word) (vector-ref md5-shifts i)))
                            b c)))))))))

  ;; --- SHA-256 (FIPS 180-4) ---------------------------------------------------------

  ;; root-word : Natural Natural -> Natural
  ;; The first 32 bits of the fractional part of PRIME's ROOTth root, square
  ;; or cube, by exact integer arithmetic: the root of PRIME times
  ;; 2^(32 ROOT), taken down, modulo 2^32 (FIPS 180-4, sections 4.2.2 and
  ;; 5.3.3).
  (define (root-word prime root)
    (let* ((n (* prime (expt 2 (* 32 root))))
           (r (if (= root 2)
                  (let-values (((s rest) (exact-integer-sqrt n))) s)
                  (let loop ((x (expt 2 (+ 1 (div (+ (bitwise-length n) 2) 3)))))
                    (let ((y (div (+ (* 2 x) (div n (* x x))) 3)))
                      (if (>= y x)
                          (let fix ((x x))
                            (cond ((> (* x x x) n) (fix (- x 1)))
                                  ((<= (* (+ x 1) (+ x 1) (+ x 1)) n) (fix (+ x 1)))
                                  (else x)))
                          (loop y)))))))
      (mod r (expt 2 32))))

  ;; primes : Natural -> (Listof Natural)
  ;; The first N primes.
  (define (primes n)
    (let loop ((k 2) (found '()))
      (if (= (length found) n)
          (reverse found)
          (loop (+ k 1)
                (if (exists (lambda (p) (= (mod k p) 0)) found) found (cons k found))))))

  (define sha256-k (list->vector (map (lambda (p) (root-word p 3)) (primes 64))))
  (define sha256-h0 (map (lambda (p) (root-word p 2)) (primes 8)))

  ;; sha256-hex : Bytevector -> String
  (define (sha256-hex bytes)
    (let ((message (padded bytes (lambda (bits out at)
                                   (bytevector-u64-set! out at bits (endianness big)))))
          (w (make-vector 64 0)))
      (let block ((at 0) (h sha256-h0))
        (if (= at (bytevector-length message))
            (hex-of h (lambda (word i)
                        (bitwise-and (bitwise-arithmetic-shift-right word (* 8 (- 3 i))) #xFF)))
            (begin
              (let fill ((t 0))
                (when (< t 64)
                  (vector-set! w t
                               (if (< t 16)
                                   (bytevector-u32-ref message (+ at (* 4 t)) (endianness big))
                                   (let ((w15 (vector-ref w (- t 15))) (w2 (vector-ref w (- t 2))))
                                     (w+ (bitwise-xor (rotr w2 17) (rotr w2 19)
                                                      (bitwise-arithmetic-shift-right w2 10))
                                         (vector-ref w (- t 7))
                                         (bitwise-xor (rotr w15 7) (rotr w15 18)
                                                      (bitwise-arithmetic-shift-right w15 3))
                                         (vector-ref w (- t 16))))))
                  (fill (+ t 1))))
              (let round ((t 0) (v h))
                (if (= t 64)
                    (block (+ at 64) (map w+ h v))
                    (let* ((a (list-ref v 0)) (b (list-ref v 1)) (c (list-ref v 2)) (d (list-ref v 3))
                           (e (list-ref v 4)) (f (list-ref v 5)) (g (list-ref v 6)) (hh (list-ref v 7))
                           (t1 (w+ hh (bitwise-xor (rotr e 6) (rotr e 11) (rotr e 25))
                                   (bitwise-xor (bitwise-and e f) (bitwise-and (wnot e) g))
                                   (vector-ref sha256-k t) (vector-ref w t)))
                           (t2 (w+ (bitwise-xor (rotr a 2) (rotr a 13) (rotr a 22))
                                   (bitwise-xor (bitwise-and a b) (bitwise-and a c) (bitwise-and b c)))))
                      (round (+ t 1) (list (w+ t1 t2) a b c (w+ d t1) e f g))))))))))

  ;; --- base64 (RFC 4648, section 4) ---------------------------------------------------

  (define base64-alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

  ;; base64-encode : Bytevector -> String
  ;; BYTES in base64, padded with =.
  (define (base64-encode bytes)
    (let ((n (bytevector-length bytes)))
      (call-with-string-output-port
       (lambda (out)
         (let loop ((i 0))
           (when (< i n)
             (let* ((b0 (bytevector-u8-ref bytes i))
                    (b1 (if (< (+ i 1) n) (bytevector-u8-ref bytes (+ i 1)) 0))
                    (b2 (if (< (+ i 2) n) (bytevector-u8-ref bytes (+ i 2)) 0))
                    (word (+ (* b0 65536) (* b1 256) b2))
                    (char (lambda (shift) (string-ref base64-alphabet
                                                      (bitwise-and (bitwise-arithmetic-shift-right word shift) 63)))))
               (put-char out (char 18))
               (put-char out (char 12))
               (put-char out (if (< (+ i 1) n) (char 6) #\=))
               (put-char out (if (< (+ i 2) n) (char 0) #\=))
               (loop (+ i 3)))))))))

  ;; --- Digest (RFC 7616, section 3.4.1; RFC 2069) --------------------------------------

  ;; digest-response : Symbol Bytevector String Bytevector String (U String #f)
  ;;                   (U String #f) (U String #f) String String -> String
  ;; The response for HASH, md5 or sha-256, the USER's and PASSWORD's bytes
  ;; in REALM, NONCE, and with a QOP of auth its CNONCE and NC, for METHOD
  ;; and URI: H(H(user:realm:password):nonce:nc:cnonce:qop:H(method:uri)),
  ;; or with QOP #f H(H(user:realm:password):nonce:H(method:uri)), each H
  ;; in lower-case hex, the strings' chars all below 256, one byte each.
  (define (digest-response hash user realm password nonce cnonce nc qop method uri)
    (let* ((h (case hash
                ((md5) md5-hex)
                ((sha-256) sha256-hex)
                (else (assertion-violation 'digest-response "a hash is md5 or sha-256" hash))))
           (octets (lambda (s) (u8-list->bytevector (map char->integer (string->list s)))))
           (join (lambda parts
                   (let ((all (map (lambda (p) (if (bytevector? p) p (octets p))) parts)))
                     (let ((out (make-bytevector (apply + (map bytevector-length all)))))
                       (fold-left (lambda (at p)
                                    (bytevector-copy! p 0 out at (bytevector-length p))
                                    (+ at (bytevector-length p)))
                                  0 all)
                       out))))
           (ha1 (h (join user ":" realm ":" password)))
           (ha2 (h (join method ":" uri))))
      (if qop
          (h (join ha1 ":" nonce ":" nc ":" cnonce ":" qop ":" ha2))
          (h (join ha1 ":" nonce ":" ha2))))))
