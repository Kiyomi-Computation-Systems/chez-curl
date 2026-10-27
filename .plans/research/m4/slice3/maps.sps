#!r6rs
;;; M4 slice 3's measurement of a loaded libcurl's file: which path the
;;; kernel maps it from, when it is loaded through a symlink (the M4 plan,
;;; section 3.6; ADR-0024, amended: "the loaded library's resolved path").
;;;
;;;   maps.sps PATH
;;;
;;; Loads PATH with load-shared-object, asks foreign-entry for
;;; curl_version_info's address, and prints the pathname of the line of
;;; /proc/self/maps whose range holds it, and that of libc.so.6, ADR-0002's
;;; world: (given PATH) (mapped PATH-OR-#f) (libc PATH-OR-#f). A load that
;;; fails prints (load-failed MESSAGE).
(import (chezscheme))

(define path (car (command-line-arguments)))

;; line-fields : String -> (List Natural Natural (U String #f))
;; A maps line's start and end, read as hex, and its pathname, from its
;; first / to its end.
(define (line-fields line)
  (let* ((dash (let loop ((i 0)) (if (char=? (string-ref line i) #\-) i (loop (+ i 1)))))
         (space (let loop ((i dash)) (if (char=? (string-ref line i) #\space) i (loop (+ i 1)))))
         (slash (let loop ((i 0))
                  (cond ((= i (string-length line)) #f)
                        ((char=? (string-ref line i) #\/) i)
                        (else (loop (+ i 1)))))))
    (list (string->number (substring line 0 dash) 16)
          (string->number (substring line (+ dash 1) space) 16)
          (and slash (substring line slash (string-length line))))))

(define (maps-lines)
  (call-with-input-file "/proc/self/maps"
    (lambda (port)
      (let loop ((found '()))
        (let ((line (get-line port)))
          (if (eof-object? line) (reverse found) (loop (cons line found))))))))

(define (basename p)
  (let loop ((i (- (string-length p) 1)))
    (cond ((< i 0) p)
          ((char=? (string-ref p i) #\/) (substring p (+ i 1) (string-length p)))
          (else (loop (- i 1))))))

(write (list 'given path))
(newline)
(guard (e (#t (write (list 'load-failed (if (message-condition? e) (condition-message e) e)))
              (newline)
              (exit 0)))
  (load-shared-object path))
(let* ((address (foreign-entry "curl_version_info"))
       (fields (map line-fields (maps-lines)))
       (holding (find (lambda (f) (and (<= (car f) address) (< address (cadr f)))) fields))
       (libc (find (lambda (f) (and (caddr f) (string=? (basename (caddr f)) "libc.so.6"))) fields)))
  (write (list 'mapped (and holding (caddr holding))))
  (newline)
  (write (list 'libc (and libc (caddr libc))))
  (newline))
