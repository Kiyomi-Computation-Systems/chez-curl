#!r6rs
;;; The suite for Akku.manifest and Akku.lock, which no tool checks for us
;;; (ADR-0015). It reads both as data and compares whole values:
;;;
;;;   - the package has no depends clause: the libraries bind libcurl
;;;     directly and need no Scheme library at runtime (ADR-0001), and
;;;     chez-srfi is the suites' own, not a consumer's;
;;;   - it has no scripts clause: Akku's script mechanism prompts on every
;;;     install, and nothing here builds (see Akku.manifest);
;;;   - its depends/dev is exactly chez-srfi, in the range that names the
;;;     pinned version;
;;;   - Akku.lock's chez-srfi url holds that version.
;;;
;;; make test runs every suite from the repository root, where both files
;;; are.
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f.
(import (rnrs)
        (srfi :64)
        (curl-testing))

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

;; read-data : String -> (Listof Any)
;; Every datum in the file at PATH, but its (import ...) forms. Chez's reader
;; skips the #!r6rs line itself.
(define (read-data path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    (lambda (port)
      (let loop ((found '()))
        (let ((datum (read port)))
          (cond ((eof-object? datum) (reverse found))
                ((and (pair? datum) (eq? (car datum) 'import)) (loop found))
                (else (loop (cons datum found)))))))))

;; the-form : Symbol String -> Any
;; The one form in the file at PATH whose first element is HEAD. It raises
;; unless there is exactly one, so a file without the form fails a test and
;; never passes one by having nothing in it.
(define (the-form head path)
  (let ((forms (filter (lambda (datum) (and (pair? datum) (eq? (car datum) head)))
                       (read-data path))))
    (if (= (length forms) 1)
        (car forms)
        (assertion-violation 'the-form "expected exactly one form" head path
                             (length forms)))))

;; package-clauses : Symbol -> (Listof Any)
;; Every clause named NAME in Akku.manifest's akku-package form, whole:
;; (NAME . body).
(define (package-clauses name)
  (filter (lambda (clause) (and (pair? clause) (eq? (car clause) name)))
          (cddr (the-form 'akku-package "Akku.manifest"))))

;; manifest-version : -> String
;; The version Akku.manifest asks chez-srfi for: the range in its depends/dev,
;; without the ^.
(define (manifest-version)
  (let ((range (cadr (cadr (car (package-clauses 'depends/dev))))))
    (substring range 1 (string-length range))))

;; lock-urls : String -> (Listof String)
;; The url of every project named NAME in Akku.lock.
(define (lock-urls name)
  (map (lambda (project) (cadr (assq 'url (cdr (assq 'location project)))))
       (filter (lambda (project) (equal? (assq 'name project) (list 'name name)))
               (cdr (the-form 'projects "Akku.lock")))))

;; contains? : String String -> Boolean
;; Whether PART occurs in WHOLE.
(define (contains? whole part)
  (let ((n (string-length whole)) (m (string-length part)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring whole i (+ i m)) part) #t)
            (else (loop (+ i 1)))))))

(test-begin "manifest")

(test-equal "Akku.manifest has no depends clause"
  '()
  (package-clauses 'depends))

(test-equal "Akku.manifest has no scripts clause"
  '()
  (package-clauses 'scripts))

(test-equal "Akku.manifest's depends/dev is exactly chez-srfi, in the range that names the pinned version"
  '((depends/dev ("chez-srfi" "^0.0.0-akku.181.7879b52")))
  (package-clauses 'depends/dev))

;; One url, and it holds the version.
(test-equal "Akku.lock's chez-srfi url holds the version Akku.manifest asks for"
  '(#t)
  (map (lambda (url) (contains? url (manifest-version)))
       (lock-urls "chez-srfi")))

(test-end "manifest")

(exit (suite-exit-status runner))
