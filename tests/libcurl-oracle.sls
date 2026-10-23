#!r6rs
;;; (libcurl-oracle): what a libcurl says about itself, read by a C program
;;; compiled at test time, tests/libcurl-oracle.c. The suites that check
;;; what chez-curl reports compare it with this: tests/test-library-loading.sps
;;; (through the probe and the preflight) and tests/test-native.sps (in its
;;; own process).
;;;
;;;   libcurl-oracle   the five fields, read from the library at a path
;;;   libcurl-protocols-oracle
;;;                    its protocol list, likewise
;;;   oracle-fields    their names, in the order both sides print them
;;;   c-compiler       $CC as a command's words, for every compile
;;;   split-words      a string cut at whitespace
;;;
;;; Test-only: it lives in tests/, which make test puts on Chez's library
;;; path, not in src/.
(library (libcurl-oracle)
  (export libcurl-oracle libcurl-protocols-oracle oracle-fields c-compiler split-words)
  (import (rnrs)
          (curl-testing))

  ;; oracle-fields : (Listof Symbol)
  ;; What the oracle reads from curl_version_info_data: version,
  ;; version_num, features, ssl_version and host.
  (define oracle-fields '(version version-num features ssl-version host))

  ;; split-words : String -> (Listof String)
  ;; TEXT cut at each run of spaces, tabs and newlines, empty pieces
  ;; dropped.
  (define (split-words text)
    (let loop ((i 0) (start 0) (found '()))
      (define (piece) (if (> i start) (cons (substring text start i) found) found))
      (cond ((= i (string-length text)) (reverse (piece)))
            ((memv (string-ref text i) '(#\space #\tab #\newline))
             (loop (+ i 1) (+ i 1) (piece)))
            (else (loop (+ i 1) start found)))))

  ;; c-compiler : (String -> (U String #f)) -> (Listof String)
  ;; The C compiler as a command's first words: CC, read with GETENV, split
  ;; at whitespace, so CC='ccache gcc' runs ccache with gcc as its first
  ;; argument; ("cc") when CC is unset or blank.
  (define (c-compiler getenv)
    (let ((words (split-words (or (getenv "CC") ""))))
      (if (null? words) '("cc") words)))

  ;; libcurl-oracle : (String -> (U String #f)) String
  ;;                  -> (U (Listof (Pairof Symbol Any)) (List 'no-oracle Symbol Any))
  ;; Compiles tests/libcurl-oracle.c with (c-compiler GETENV) into a fresh
  ;; directory from call-with-temp-directory, runs it on PATH, and answers
  ;; what it printed, read as data: (FIELD . VALUE) for each of oracle-fields,
  ;; in order. Anything else is (no-oracle STEP EVIDENCE), naming the step that
  ;; went wrong: compile, run, output (that is not the five fields), or
  ;; raised, with the text of a raise, which includes mktemp's answer being
  ;; refused. It never raises. The directory is removed, a raise included.
  (define (libcurl-oracle getenv path)
    (guard (e (#t (list 'no-oracle 'raised (describe e))))
      (call-with-temp-directory
       (lambda (dir)
         (run-oracle getenv (string-append dir "/libcurl-oracle") path)))))

;; libcurl-protocols-oracle : (String -> (U String #f)) String
  ;;                            -> (U (Listof String) (List 'no-oracle Symbol Any))
  ;; The protocol names curl_version_info_data's protocols holds, in order,
  ;; read in C from the library at PATH: tests/libcurl-oracle.c PATH
  ;; protocols. Anything else is (no-oracle STEP EVIDENCE), as for
  ;; libcurl-oracle. It never raises.
  (define (libcurl-protocols-oracle getenv path)
    (guard (e (#t (list 'no-oracle 'raised (describe e))))
      (call-with-temp-directory
       (lambda (dir)
         (let* ((program (string-append dir "/libcurl-oracle"))
                (compiled (capture-command
                           (append (c-compiler getenv)
                                   (list "-o" program "tests/libcurl-oracle.c" "-ldl")))))
           (if (not (= (car compiled) 0))
               (list 'no-oracle 'compile compiled)
               (let ((ran (capture-command (list program path "protocols"))))
                 (if (not (= (car ran) 0))
                     (list 'no-oracle 'run ran)
                     (let ((data (read-all (cadr ran))))
                       (if (and (list? data) (= (length data) 1) (list? (car data))
                                (for-all string? (car data)))
                           (car data)
                           (list 'no-oracle 'output (cadr ran))))))))))))

  (define (run-oracle getenv program path)
    (let ((compiled (capture-command
                     (append (c-compiler getenv)
                             (list "-o" program "tests/libcurl-oracle.c" "-ldl")))))
      (if (not (= (car compiled) 0))
          (list 'no-oracle 'compile compiled)
          (let ((ran (capture-command (list program path))))
            (if (not (= (car ran) 0))
                (list 'no-oracle 'run ran)
                (let ((data (read-all (cadr ran))))
                  (if (and (list? data)
                           (= (length data) (length oracle-fields))
                           (for-all (lambda (datum field)
                                      (and (pair? datum) (eq? (car datum) field)))
                                    data oracle-fields))
                      data
                      (list 'no-oracle 'output (cadr ran)))))))))

  ;; read-all : String -> (U (Listof Any) #f)
  ;; TEXT read as a sequence of data, or #f when it does not read.
  (define (read-all text)
    (guard (e (#t #f))
      (let ((port (open-string-input-port text)))
        (let loop ((data '()))
          (let ((datum (read port)))
            (if (eof-object? datum)
                (reverse data)
                (loop (cons datum data)))))))))
