#!r6rs
;;; docs/reference.md holds one entry for every export of the three public
;;; libraries, (curl), (curl unsupported) and (http-client), and nothing
;;; else: each under its own library's section, with the type of each
;;; procedure and value it names, what it raises, and a link to the guide
;;; page that explains it.
;;;
;;; The oracles: the names each library exports, as Chez's library-exports
;;; lists them, never as the libraries' text writes them; and what each name
;;; is, as Chez evaluates it in its library's environment: syntax, which a
;;; condition type's name is; a procedure; or any other value. And the page,
;;; read as CommonMark is: its ATX headings and its prose, outside fenced
;;; blocks and HTML comments; the lines of each fenced block whose info
;;; string's first word is text, in any case; and each inline link of its
;;; prose, outside code.
;;;
;;; The shape the page is held to:
;;; - a ## heading begins with one library's name in code, as
;;;   "## `(curl)`: engines", and the entries after it, up to the next ##
;;;   or # heading, are that library's;
;;; - a ### heading is an entry: the names it lists, each in code,
;;;   comma-separated, as "### `&curl-error`, `curl-error?`"; the entry runs
;;;   to the next heading of level 1, 2 or 3;
;;; - an entry's text blocks hold a line "NAME : TYPE" for each procedure and
;;;   value it names, starting with the name: a line that starts with a
;;;   blank goes on from the one before; a procedure's TYPE holds ->, and a
;;;   value's does not;
;;; - an entry's prose holds a sentence that begins "Raises", at a
;;;   paragraph's start or after a . ! or ?, and an inline link to a page of
;;;   docs/ other than reference.md, which exists; each link to a page names
;;;   it by its title, its first # heading, or the title's part before ": ";
;;; - the entry of each procedure that takes keys holds a table whose first
;;;   column is headed Key, its rows' first cells naming, each in code,
;;;   exactly the keys the code checks that procedure's against: the lists
;;;   (curl private transfer) and (http-client private call) define, the
;;;   oracle here; no other entry holds such a table.
;;; Every ## heading and every ### heading must keep that shape: one that
;;; does not fails, by its line. The reader is held to all of it on pages of
;;; the suite's own before it reads docs/reference.md.
;;;
;;; Out of its reach, with no oracle but a reader's reading of the code: a type
;;; that is wrong, so long as a procedure's holds -> and a value's does not; a
;;; Raises sentence that names the wrong refusals; and a link to the wrong page,
;;; under that page's title.
;;;
;;; make test runs every suite from the repository root. Each computation
;;; that can raise runs under a guard that answers what was raised, since
;;; SRFI-64 turns a raise in the actual expression into #f; no expected
;;; value is #f.
(import (rnrs)
        (rnrs eval)
        (rnrs mutable-strings)
        (srfi :64)
        (curl-testing)
        (only (chezscheme) library-exports file-regular? mkdir)
        (only (curl private transfer) request-keys)
        (only (http-client private call) session-keys call-keys port-keys group-keys retry-keys))

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

;; --- reading text ----------------------------------------------------------------

;; slurp : String -> String — the file's text, as UTF-8.
(define (slurp path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    get-string-all))

;; text-lines : String -> (Listof String) — the text split at each newline.
(define (text-lines s)
  (let loop ((cs (string->list s)) (line '()) (out '()))
    (cond ((null? cs) (reverse (cons (list->string (reverse line)) out)))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse line)) out)))
          (else (loop (cdr cs) (cons (car cs) line) out)))))

;; joined : (Listof String) -> String — the lines, each ended by a newline.
(define (joined lines)
  (apply string-append (map (lambda (l) (string-append l "\n")) lines)))

;; blank? : Char -> Boolean — a space or a tab.
(define (blank? c) (or (char=? c #\space) (char=? c #\tab)))

;; white? : Char -> Boolean — a blank or a line's end.
(define (white? c) (or (blank? c) (char=? c #\newline)))

;; trim : String -> String — without the blanks at either end.
(define (trim s)
  (let* ((n (string-length s))
         (i (let loop ((i 0)) (if (and (< i n) (blank? (string-ref s i))) (loop (+ i 1)) i)))
         (j (let loop ((j n)) (if (and (> j i) (blank? (string-ref s (- j 1)))) (loop (- j 1)) j))))
    (substring s i j)))

;; starts? : String String -> Boolean
(define (starts? s prefix)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

;; ends? : String String -> Boolean
(define (ends? s suffix)
  (let ((n (string-length s)) (k (string-length suffix)))
    (and (>= n k) (string=? (substring s (- n k) n) suffix))))

;; search : String String Nat -> (U Nat #f) — where PAT next begins in S, from I.
(define (search s pat i)
  (let ((n (string-length s)) (k (string-length pat)))
    (let loop ((i i))
      (cond ((> (+ i k) n) #f)
            ((string=? (substring s i (+ i k)) pat) i)
            (else (loop (+ i 1)))))))

;; run : String Nat Char -> Nat — how many of C begin at I.
(define (run s i c)
  (let loop ((j i))
    (if (and (< j (string-length s)) (char=? (string-ref s j) c)) (loop (+ j 1)) (- j i))))

;; split : String Char -> (Listof String) — the string split at each C.
(define (split s c)
  (let loop ((cs (string->list s)) (piece '()) (out '()))
    (cond ((null? cs) (reverse (cons (list->string (reverse piece)) out)))
          ((char=? (car cs) c) (loop (cdr cs) '() (cons (list->string (reverse piece)) out)))
          (else (loop (cdr cs) (cons (car cs) piece) out)))))

;; one-word? : String -> Boolean — not empty, and no blank inside it.
(define (one-word? s)
  (and (> (string-length s) 0) (not (exists blank? (string->list s)))))

;; --- code spans ------------------------------------------------------------------

;; code-ranges : String -> (Listof (List Nat Nat String))
;; Each `code` span of the text (CommonMark §6.1), in order: where its
;; opening run of backticks begins, where its closing run ends, and its
;; text. A run of backticks opens a span, and the next run of exactly as
;; many closes it; a run that none closes is text, and so is a backtick
;; after a backslash. A span's line endings read as spaces, and one space
;; each side is dropped when both are there and it is not all spaces.
(define (code-ranges text)
  (let ((n (string-length text)))
    ;; closer : Nat Nat -> (U Nat #f) — where the next run of exactly K backticks from I begins.
    (define (closer i k)
      (cond ((>= i n) #f)
            ((char=? (string-ref text i) #\`)
             (let ((m (run text i #\`))) (if (= m k) i (closer (+ i m) k))))
            (else (closer (+ i 1) k))))
    ;; span-text : String -> String
    (define (span-text s)
      (let* ((s (list->string (map (lambda (c) (if (char=? c #\newline) #\space c)) (string->list s))))
             (m (string-length s)))
        (if (and (>= m 2) (char=? (string-ref s 0) #\space) (char=? (string-ref s (- m 1)) #\space)
                 (not (for-all (lambda (c) (char=? c #\space)) (string->list s))))
            (substring s 1 (- m 1))
            s)))
    (let loop ((i 0) (out '()))
      (cond ((>= i n) (reverse out))
            ((and (char=? (string-ref text i) #\\) (< (+ i 1) n)) (loop (+ i 2) out))
            ((char=? (string-ref text i) #\`)
             (let* ((k (run text i #\`)) (j (closer (+ i k) k)))
               (if j
                   (loop (+ j k) (cons (list i (+ j k) (span-text (substring text (+ i k) j))) out))
                   (loop (+ i k) out))))
            (else (loop (+ i 1) out))))))

;; code-spans : String -> (Listof String) — the text of each code span, in order.
(define (code-spans text) (map caddr (code-ranges text)))

;; only-span : String -> (U String #f) — the text of `x`, written as one code span and nothing else; else #f.
(define (only-span s)
  (let ((ranges (code-ranges s)))
    (and (= (length ranges) 1)
         (= (car (car ranges)) 0)
         (= (cadr (car ranges)) (string-length s))
         (caddr (car ranges)))))

;; without-code : String -> String
;; The text with each code span, its backticks among it, made spaces, and
;; its line endings kept: what is left is the text a reader sees as prose.
(define (without-code text)
  (let ((s (string-copy text)))
    (for-each (lambda (r)
                (let loop ((i (car r)))
                  (when (< i (cadr r))
                    (unless (char=? (string-ref s i) #\newline) (string-set! s i #\space))
                    (loop (+ i 1)))))
              (code-ranges text))
    s))

;; --- blocks, headings and prose ------------------------------------------------------

;; fence : String -> (U (List Char Nat Nat String) #f)
;; The line as a fence that opens a block (CommonMark §4.5): up to three
;; spaces, then three or more backticks or tildes; its character, how many,
;; its indent, and its info string, trimmed. A backtick fence's info string
;; holds no backtick.
(define (fence line)
  (let ((indent (run line 0 #\space)) (n (string-length line)))
    (and (<= indent 3) (< indent n)
         (let ((c (string-ref line indent)))
           (and (memv c '(#\` #\~))
                (let* ((k (run line indent c))
                       (info (trim (substring line (+ indent k) n))))
                  (and (>= k 3)
                       (not (and (char=? c #\`) (memv #\` (string->list info))))
                       (list c k indent info))))))))

;; closes? : String (List Char Nat Nat String) -> Boolean
;; Whether the line closes the block OPEN opened: up to three spaces, then
;; OPEN's character, at least as many, then blanks alone.
(define (closes? line open)
  (let ((indent (run line 0 #\space)))
    (and (<= indent 3)
         (let ((k (run line indent (car open))))
           (and (>= k (cadr open))
                (string=? (trim (substring line (+ indent k) (string-length line))) ""))))))

;; language : String -> String — an info string's first word, in lower case; "" for none.
(define (language info)
  (let ((words (filter (lambda (w) (not (string=? w ""))) (split info #\space))))
    (if (null? words) "" (string-downcase (car words)))))

;; unindent : String Nat -> String — the line without up to N of its leading spaces.
(define (unindent line n)
  (let ((k (min n (run line 0 #\space)))) (substring line k (string-length line))))

;; heading : String -> (U (Pair Nat String) #f)
;; The line as an ATX heading (CommonMark §4.2): up to three spaces, one to
;; six #, then a blank or the line's end; its level, and its text, trimmed,
;; a closing run of # after a blank dropped.
(define (heading line)
  (let* ((indent (run line 0 #\space)) (n (string-length line)))
    (and (<= indent 3) (< indent n) (char=? (string-ref line indent) #\#)
         (let ((level (run line indent #\#)))
           (and (<= level 6)
                (let ((after (+ indent level)))
                  (and (or (= after n) (blank? (string-ref line after)))
                       (let* ((text (trim (substring line after n)))
                              (m (string-length text))
                              (closing (let back ((j m)) (if (and (> j 0) (char=? (string-ref text (- j 1)) #\#)) (back (- j 1)) j))))
                         (cons level
                               (cond ((= closing 0) "")
                                     ((and (< closing m) (blank? (string-ref text (- closing 1))))
                                      (trim (substring text 0 closing)))
                                     (else text)))))))))))

;; comment-start? : String -> Boolean — the line opens an HTML comment block: up to three spaces, then <!--.
(define (comment-start? line)
  (let ((indent (run line 0 #\space)))
    (and (<= indent 3) (starts? (substring line indent (string-length line)) "<!--"))))

;; items : String -> (Listof Item)
;; The page, as a reader reads it, in order: (heading LEVEL TEXT LINE) for
;; an ATX heading, (prose TEXT LINE) for any other line outside a block,
;; and (block LANGUAGE LINES LINE) for a fenced block, its lines without up
;; to its fence's indent, at its opening fence's line. A block no fence
;; closes runs to the page's end. An HTML comment block, from a line that
;; opens one to the line that holds -->, is none of them.
(define (items text)
  (let loop ((ls (text-lines text)) (n 1) (open #f) (start 0) (body '()) (comment #f) (out '()))
    (cond ((null? ls)
           (reverse (if open (cons (list 'block (language (cadddr open)) (reverse body) start) out) out)))
          (open
           (if (closes? (car ls) open)
               (loop (cdr ls) (+ n 1) #f 0 '() #f
                     (cons (list 'block (language (cadddr open)) (reverse body) start) out))
               (loop (cdr ls) (+ n 1) open start (cons (unindent (car ls) (caddr open)) body) #f out)))
          (comment (loop (cdr ls) (+ n 1) #f 0 '() (not (search (car ls) "-->" 0)) out))
          ((comment-start? (car ls))
           (loop (cdr ls) (+ n 1) #f 0 '() (not (search (car ls) "-->" (+ (search (car ls) "<!--" 0) 4))) out))
          ((fence (car ls)) => (lambda (f) (loop (cdr ls) (+ n 1) f n '() #f out)))
          ((heading (car ls)) => (lambda (h) (loop (cdr ls) (+ n 1) #f 0 '() #f (cons (list 'heading (car h) (cdr h) n) out))))
          (else (loop (cdr ls) (+ n 1) #f 0 '() #f (cons (list 'prose (car ls) n) out))))))

;; --- the page's entries -------------------------------------------------------------

;; An entry: the names its heading lists, the library its section names or
;; #f, its heading's line, the lines of its text blocks, and its prose lines.
(define-record-type entry (fields names library line texts prose))

;; section-library : String (Listof String) -> (U String #f)
;; The library a ## heading's text names: its first code span, at its
;; start, when that is one of LIBRARIES; else #f.
(define (section-library text libraries)
  (let ((ranges (code-ranges text)))
    (and (pair? ranges) (= (car (car ranges)) 0)
         (let ((name (caddr (car ranges)))) (and (member name libraries) name)))))

;; listed-names : String -> (U (Listof String) #f)
;; The names a ### heading's text lists: split at each comma, each piece
;; trimmed and one code span of one word; #f when any piece is not.
(define (listed-names text)
  (let ((pieces (map (lambda (p) (only-span (trim p))) (split text #\,))))
    (and (for-all (lambda (p) (and p (one-word? p))) pieces) pieces)))

;; read-page : String (Listof String) -> (Pair (Listof Entry) (Listof (List Nat String)))
;; The page's entries, in order, and each heading its shape refuses, as
;; its line and its text: a ## heading that does not begin with one of
;; LIBRARIES in code, and a ### heading that is no list of names in code.
;; An entry's library is its nearest ## heading's; one after a # heading,
;; or a refused ## heading, before the next ## heading, has none. A block,
;; or a heading of level 4 to 6, ends the paragraph before it, as a blank
;; line does.
(define (read-page text libraries)
  (let loop ((is (items text)) (library #f) (current #f) (out '()) (refused '()))
    (let ((done (lambda () (if current (cons (finish current) out) out))))
      (if (null? is)
          (cons (reverse (done)) (reverse refused))
          (let ((i (car is)))
            (case (car i)
              ((heading)
               (let ((level (cadr i)) (text (caddr i)) (line (cadddr i)))
                 (cond ((= level 1) (loop (cdr is) #f #f (done) refused))
                       ((= level 2)
                        (let ((l (section-library text libraries)))
                          (loop (cdr is) l #f (done) (if l refused (cons (list line text) refused)))))
                       ((= level 3)
                        (let ((names (listed-names text)))
                          (if names
                              (loop (cdr is) library (list names library line '() '()) (done) refused)
                              (loop (cdr is) library #f (done) (cons (list line text) refused)))))
                       (else (loop (cdr is) library (add (add (add current "") text) "") out refused)))))
              ((block)
               (loop (cdr is) library
                     (add (if (string=? (cadr i) "text") (add-all current (caddr i)) current) "")
                     out refused))
              (else (loop (cdr is) library (add current (cadr i)) out refused))))))))

;; add : (U List #f) String -> (U List #f) — the entry being read, with a prose line more.
(define (add current line)
  (and current
       (list (car current) (cadr current) (caddr current) (cadddr current)
             (cons line (car (cddddr current))))))

;; add-all : (U List #f) (Listof String) -> (U List #f) — the entry being read, with a text block's lines more.
(define (add-all current lines)
  (and current
       (list (car current) (cadr current) (caddr current)
             (append (reverse lines) (cadddr current)) (car (cddddr current)))))

;; finish : List -> Entry
(define (finish current)
  (make-entry (car current) (cadr current) (caddr current)
              (reverse (cadddr current)) (reverse (car (cddddr current)))))

;; typed : (Listof String) -> (Listof (Pair String String))
;; Each NAME : TYPE line of a text block's lines, in order: a line that
;; starts with no blank and holds " : ", NAME before it one word and TYPE
;; after it, trimmed, not empty.
(define (typed lines)
  (fold-right
   (lambda (line out)
     (let ((i (search line " : " 0)))
       (if (and i (> (string-length line) 0) (not (blank? (string-ref line 0)))
                (one-word? (substring line 0 i))
                (not (string=? (trim (substring line (+ i 3) (string-length line))) "")))
           (cons (cons (substring line 0 i) (trim (substring line (+ i 3) (string-length line)))) out)
           out)))
   '() lines))

;; paragraphs : (Listof String) -> (Listof String)
;; The runs of prose lines between blank lines, each joined.
(define (paragraphs lines)
  (let loop ((ls lines) (para '()) (out '()))
    (let ((flush (lambda () (if (null? para) out (cons (joined (reverse para)) out)))))
      (cond ((null? ls) (reverse (flush)))
            ((string=? (trim (car ls)) "") (loop (cdr ls) '() (flush)))
            (else (loop (cdr ls) (cons (car ls) para) out))))))

;; raises? : (Listof String) -> Boolean
;; Whether the prose holds a sentence that begins Raises, outside code: the
;; word at a paragraph's start, or after a . ! or ? and a blank or a line's
;; end; then a blank or the paragraph's end.
(define (raises? lines)
  (exists
   (lambda (para)
     (let ((p (without-code para)))
       (let scan ((i 0))
         (let ((at (search p "Raises" i)))
           (and at
                (or (and (or (= (+ at 6) (string-length p)) (white? (string-ref p (+ at 6))))
                         (let back ((j at))
                           (cond ((= j 0) #t)
                                 ((white? (string-ref p (- j 1))) (back (- j 1)))
                                 (else (and (< j at) (memv (string-ref p (- j 1)) '(#\. #\! #\?)) #t)))))
                    (scan (+ at 1))))))))
   (paragraphs lines)))

;; links : (Listof String) -> (Listof String)
;; The target of each inline link and image of the prose, [text](target),
;; outside code: what follows "](" up to a blank, a line's end or the ")"
;; that ends it.
(define (links lines)
  (let ((s (without-code (joined lines))))
    (let loop ((i 0) (out '()))
      (let ((j (search s "](" i)))
        (if (not j)
            (reverse out)
            (let end ((k (+ j 2)))
              (if (or (>= k (string-length s)) (memv (string-ref s k) '(#\) #\space #\tab #\newline)))
                  (loop k (cons (substring s (+ j 2) k) out))
                  (end (+ k 1)))))))))

;; page-link? : String String -> Boolean
;; Whether TARGET names a page of the directory DOCS other than
;; reference.md, which exists there: no scheme, no leading / or #, no .
;; or .. segment but a leading ./, its path, without its #fragment, ending
;; .md, and DOCS/path a regular file.
(define (page-link? docs target)
  (let* ((hash (search target "#" 0))
         (path (if hash (substring target 0 hash) target))
         (path (if (starts? path "./") (substring path 2 (string-length path)) path))
         (segments (split path #\/)))
    (and (not (search target ":" 0))
         (not (starts? path "/"))
         (not (string=? path ""))
         (for-all (lambda (s) (not (member s '("" "." "..")))) segments)
         (ends? path ".md")
         (not (string=? path "reference.md"))
         (file-regular? (string-append docs "/" path)))))

;; procedure-type? : String -> Boolean — the type holds ->, as a procedure's does.
(define (procedure-type? type) (and (search type "->" 0) #t))

;; labelled-links : (Listof String) -> (Listof (Pair String String))
;; Each inline link of the prose, outside code, as its text and its
;; target: the text from the [ before "](" to it, the target as links
;; takes it.
(define (labelled-links lines)
  (let* ((text (joined lines)) (s (without-code text)))
    (let loop ((i 0) (out '()))
      (let ((j (search s "](" i)))
        (if (not j)
            (reverse out)
            (let ((open (let back ((k (- j 1))) (cond ((< k 0) #f) ((char=? (string-ref s k) #\[) k) (else (back (- k 1)))))))
              (let end ((k (+ j 2)))
                (if (or (>= k (string-length s)) (memv (string-ref s k) '(#\) #\space #\tab #\newline)))
                    (loop k (if open
                                (cons (cons (substring text (+ open 1) j) (substring s (+ j 2) k)) out)
                                out))
                    (end (+ k 1))))))))))

;; page-title : String -> (U String #f) — the page's first # heading's text, outside its blocks; #f for none.
(define (page-title text)
  (let ((h (find (lambda (i) (and (eq? (car i) 'heading) (= (cadr i) 1))) (items text))))
    (and h (caddr h))))

;; titled? : String String -> Boolean — TEXT is the title, or the title's part before its first ": ".
(define (titled? text title)
  (or (string=? text title)
      (let ((k (search title ": " 0))) (and k (string=? text (substring title 0 k))))))

;; has-bar? : String -> Boolean
(define (has-bar? line) (and (memv #\| (string->list line)) #t))

;; cells : String -> (Listof String)
;; A table row's cells (GitHub's tables): the row split at each bar not
;; escaped, in code too, its outer bars optional; each cell trimmed, \|
;; read as |.
(define (cells row)
  (let* ((s (trim row))
         (parts (let loop ((cs (string->list s)) (cell '()) (out '()))
                  (cond ((null? cs) (reverse (cons (list->string (reverse cell)) out)))
                        ((and (char=? (car cs) #\\) (pair? (cdr cs)) (char=? (cadr cs) #\|))
                         (loop (cddr cs) (cons #\| cell) out))
                        ((char=? (car cs) #\|) (loop (cdr cs) '() (cons (list->string (reverse cell)) out)))
                        (else (loop (cdr cs) (cons (car cs) cell) out)))))
         (inner (let ((p (if (starts? s "|") (cdr parts) parts)))
                  (if (and (ends? s "|") (not (ends? s "\\|")) (pair? p)) (reverse (cdr (reverse p))) p))))
    (map trim inner)))

;; delimiter-row? : String -> Boolean — a row of cells each of - alone, a colon either side or not.
(define (delimiter-row? line)
  (and (has-bar? line)
       (let ((cs (cells line)))
         (and (pair? cs)
              (for-all (lambda (c)
                         (let* ((c (if (starts? c ":") (substring c 1 (string-length c)) c))
                                (c (if (ends? c ":") (substring c 0 (- (string-length c) 1)) c)))
                           (and (> (string-length c) 0) (for-all (lambda (ch) (char=? ch #\-)) (string->list c)))))
                       cs)))))

;; key-tables : (Listof String) -> (U (Listof String) #f)
;; The keys the prose's key tables name: of every table whose header's
;; first cell is Key, over a delimiter row of as many cells, each body row's
;; first cell's code spans, in order, up to a blank line or a line with no
;; bar; #f when the prose holds no such table.
(define (key-tables lines)
  (let scan ((ls lines) (found #f))
    (cond ((or (null? ls) (null? (cdr ls))) (and found (reverse found)))
          ((and (has-bar? (car ls)) (delimiter-row? (cadr ls))
                (= (length (cells (car ls))) (length (cells (cadr ls))))
                (equal? (car (cells (car ls))) "Key"))
           (let rows ((ls (cddr ls)) (found (or found '())))
             (if (or (null? ls) (string=? (trim (car ls)) "") (not (has-bar? (car ls))))
                 (scan ls found)
                 (rows (cdr ls) (append (reverse (code-spans (car (cells (car ls))))) found)))))
          (else (scan (cdr ls) found)))))

;; --- the oracle ------------------------------------------------------------------

;; The three public libraries, each with its name as the page writes it.
(define libraries
  '(("(curl)" . (curl)) ("(curl unsupported)" . (curl unsupported)) ("(http-client)" . (http-client))))

;; exports-of : (Listof Symbol) -> (U (Listof String) (List 'raised String))
;; The names the library exports, as Chez's library-exports lists them,
;; sorted; the library is first imported into an environment, so Chez has
;; it. Or (raised WHAT) for a raise.
(define (exports-of library)
  (guard (e (#t (list 'raised (describe e))))
    (environment library)
    (list-sort string<? (map symbol->string (library-exports library)))))

;; kind : (Listof Symbol) String -> (U 'syntax 'procedure 'value (List 'raised String))
;; What NAME is, as Chez evaluates it in the library's environment: syntax,
;; when evaluating it is a syntax violation, as a condition type's name
;; is; a procedure; a value; or (raised WHAT) for any other raise.
(define (kind library name)
  (guard (e ((syntax-violation? e) 'syntax)
            (#t (list 'raised (describe e))))
    (let ((v (eval (string->symbol name) (environment library))))
      (if (procedure? v) 'procedure 'value))))

;; keyed : (Listof (Pair String (Listof Symbol)))
;; Each exported procedure that takes keys of its own, with the list the
;; code checks them against: request-keys for make-curl-request, and it
;; with url for curl-request-with, as transfer.sls's request-settings call
;; there makes it; session-keys, call-keys, port-keys, retry-keys and
;; group-keys of the high level. The verbs take http-request's, and their
;; entry names no keys of its own.
(define keyed
  (list (cons "make-curl-request" request-keys)
        (cons "curl-request-with" (cons 'url request-keys))
        (cons "make-http-session" session-keys)
        (cons "http-request" call-keys)
        (cons "call-with-response-port" port-keys)
        (cons "make-http-retry" retry-keys)
        (cons "call-with-request-group" group-keys)
        (cons "http-parallel" group-keys)))

;; noted : String (Listof Any) -> (Listof Any)
;; The items, written on stderr after WHAT when there are any: SRFI-64's
;; runner names a failed check, and the hook above its values.
(define (noted what xs)
  (unless (null? xs)
    (let ((p (current-error-port)))
      (put-string p what)
      (for-each (lambda (x) (put-string p "\n  ") (write x p)) xs)
      (put-char p #\newline)
      (flush-output-port p)))
  xs)

;; --- the reader, on pages of the suite's own ---------------------------------------------

;; A page with an entry of each shape, headings and entries hidden in
;; blocks and a comment, and headings the shape refuses.
(define structure-page
  (joined
   '("# A page"
     ""
     "Prose naming `zeta` before any section."
     ""
     "### `orphan`"
     ""
     "## `(curl)`: the first"
     ""
     "### `alpha`, `beta?`"
     ""
     "```text"
     "alpha : Nat -> Nat"
     "  a line that goes on"
     "~~~"
     "beta? : Any -> Boolean"
     "```"
     ""
     "~~~~ Text"
     "### `hidden-in-tildes`"
     "~~~"
     "## `(http-client)`: inside"
     "```"
     "gamma : Nat"
     "~~~~"
     ""
     "<!--"
     "### `hidden-in-comment`"
     "-->"
     ""
     "### `gamma` ###"
     ""
     "```scheme fragment"
     "delta : Nat"
     "```"
     ""
     "## `(http-client)`: the second"
     ""
     "  ### `delta`"
     ""
     "#### A sub-heading inside an entry"
     ""
     "    ### `indented-code`"
     ""
     "````TEXT"
     "delta : -> Nat"
     "```"
     "omega : Nat"
     "````"
     ""
     "## Notes"
     ""
     "### `epsilon`"
     ""
     "### `eta` and more"
     ""
     "### `theta`, iota"
     ""
     "## `(curl unsupported)`"
     ""
     "### `kappa`")))

;; What read-page must take from it: each entry as its names, its library,
;; its line and its type lines; and the refused headings. The tilde block
;; is a text block of alpha's entry, so its last line is one of alpha's.
(define structure-expected
  '(((("orphan") #f 5 ())
     (("alpha" "beta?") "(curl)" 9
      (("alpha" . "Nat -> Nat") ("beta?" . "Any -> Boolean") ("gamma" . "Nat")))
     (("gamma") "(curl)" 30 ())
     (("delta") "(http-client)" 38 (("delta" . "-> Nat") ("omega" . "Nat")))
     (("epsilon") #f 52 ())
     (("kappa") "(curl unsupported)" 60 ()))
    ((50 "Notes") (54 "`eta` and more") (56 "`theta`, iota"))))

;; shown : String -> List — read-page's answer for the text, each entry as structure-expected writes it.
(define (shown text)
  (let ((read (read-page text (map car libraries))))
    (list (map (lambda (e) (list (entry-names e) (entry-library e) (entry-line e) (typed (entry-texts e))))
               (car read))
          (cdr read))))

;; A page whose entries' prose holds a Raises sentence or something like
;; one, and links inside and outside code and blocks.
(define prose-page
  (joined
   '("## `(curl)`: prose"
     ""
     "### `a`"
     ""
     "Gives a. Raises nothing. See [Streams](streams.md)."
     ""
     "### `b`"
     ""
     "It raises nothing, and `Raises` is code, `[Code](code.md)` too. Praises it."
     "Raisesx is no word of it, nor ```Raises here```."
     ""
     "```text"
     "Raises nothing. [Block](block.md)"
     "```"
     ""
     "### `c`"
     ""
     "The first line"
     "ends here?"
     "Raises an assertion violation: see [Out](https://example.com/), [Here](#c)"
     "and ![Groups](groups.md#go)."
     ""
     "### `d`"
     ""
     "A paragraph with no stop"
     ""
     "Raises"
     ""
     "### `e`"
     ""
     "A paragraph with no stop"
     "Raises nothing, as part of it."
     ""
     "### `f`"
     ""
     "A paragraph with no stop"
     "```text"
     "f : Nat"
     "```"
     "Raises nothing, after a block that ends the paragraph."
     ""
     "### `g`"
     ""
     "A paragraph with no stop"
     "#### A sub-heading with no stop"
     "Raises nothing, after a sub-heading.")))

;; What the reader must take from it: each entry's first name, whether it
;; has a Raises sentence, and its links.
(define prose-expected
  '(("a" has-raises ("streams.md"))
    ("b" no-raises ())
    ("c" has-raises ("https://example.com/" "#c" "groups.md#go"))
    ("d" has-raises ())
    ("e" no-raises ())
    ("f" has-raises ())
    ("g" has-raises ())))

(define (prose-shown text)
  (map (lambda (e)
         (list (car (entry-names e))
               (if (raises? (entry-prose e)) 'has-raises 'no-raises)
               (links (entry-prose e))))
       (car (read-page text (map car libraries)))))

;; The link targets page-link? is tried on, each with what it must answer,
;; in a directory of the suite's own that holds streams.md, reference.md,
;; a directory named dir.md and sub/page.md.
(define link-cases
  '(("streams.md" page) ("./streams.md" page) ("streams.md#reading" page) ("sub/page.md" page)
    ("missing.md" not-page) ("reference.md" not-page) ("./reference.md" not-page)
    ("reference.md#x" not-page) ("../streams.md" not-page) ("sub/../streams.md" not-page)
    ("/streams.md" not-page) ("https://example.com/streams.md" not-page) ("#streams" not-page)
    ("dir.md" not-page) ("streams" not-page) ("" not-page)))

;; Prose with key tables: two keys in one cell, an escaped bar in a cell,
;; a table whose first column is not Key, a second key table, and a line
;; after one that ends it.
(define key-prose
  '("Some prose."
    ""
    "| Key | Type | Default |"
    "|:--|:--|:--|"
    "| `a`, `b` | `(U a b)` or `c\\|d` | x |"
    "| `c` | t | y |"
    ""
    "| Name | Key |"
    "|--|--|"
    "| `z` | `w` |"
    ""
    "| Key | Type |"
    "|--|--|"
    "| `d` | t |"
    "not a row"
    "| `e` | t |"))

;; Prose with links, each as labelled-links must take it.
(define labelled-prose
  '("See [The low level](low-level.md), [`code`](x.md), and `[in](code.md)`;"
    "and [Groups](groups.md#go)."))

(define labelled-expected
  '(("The low level" . "low-level.md") ("`code`" . "x.md") ("Groups" . "groups.md#go")))

;; Link texts, each with a title, and whether the text names the page by it.
(define title-cases
  '((("Groups" "Groups: many calls at once") titled)
    (("Groups: many calls at once" "Groups: many calls at once") titled)
    (("The hatch" "The hatch: `(curl unsupported)`") titled)
    (("Group" "Groups: many calls at once") untitled)
    (("many calls at once" "Groups: many calls at once") untitled)
    (("What can go wrong" "Errors") untitled)
    (("Errors " "Errors") untitled)))

;; A page whose title is its first # heading outside a block.
(define titled-page
  (joined '("Prose first." "```" "# not the title" "```" "## A section" "# The title" "# Another")))

;; --- the page -------------------------------------------------------------------

;; page-text : (U String (List 'raised String)) — docs/reference.md's text.
(define page-text
  (guard (e (#t (list 'raised (describe e))))
    (slurp "docs/reference.md")))

;; The exports of each library, by its name as the page writes it.
(define exported
  (map (lambda (l) (cons (car l) (exports-of (cdr l)))) libraries))

(define (exports-ok?) (for-all (lambda (x) (and (list? (cdr x)) (pair? (cdr x)) (string? (cadr x)))) exported))

;; Every export, as (LIBRARY NAME KIND), in the libraries' order.
(define every-export
  (if (exports-ok?)
      (apply append
             (map (lambda (l)
                    (map (lambda (name) (list (car l) name (kind (cdr l) name)))
                         (cdr (assoc (car l) exported))))
                  libraries))
      '()))

;; The page as read, or #f when it could not be.
(define page
  (and (string? page-text)
       (guard (e (#t #f)) (read-page page-text (map car libraries)))))

(define page-entries (if page (car page) '()))

;; Each name the page's entries name, with its entry, in order.
(define named
  (apply append (map (lambda (e) (map (lambda (n) (cons n e)) (entry-names e))) page-entries)))

;; exporter : String -> (U String #f) — the library that exports NAME, as the page writes it; #f for none.
(define (exporter name)
  (let ((hit (find (lambda (x) (string=? (cadr x) name)) every-export)))
    (and hit (car hit))))

;; kind-of : String -> (U 'syntax 'procedure 'value (List 'raised String) #f)
;; What the exported NAME is, as Chez evaluates it; #f for no export.
(define (kind-of name)
  (let ((hit (find (lambda (x) (string=? (cadr x) name)) every-export)))
    (and hit (caddr hit))))

;; heading-of : Entry -> (List Nat (Listof String)) — an entry as a failure names it: its line and its names.
(define (heading-of e) (list (entry-line e) (entry-names e)))

;; --- the reader ------------------------------------------------------------------

(test-begin "reference")

(test-equal "the reader takes each entry's names, its library, its line and its type lines, and the headings the shape refuses, and nothing from a block, a comment or code"
  structure-expected
  (guard (e (#t (list 'raised (describe e)))) (shown structure-page)))

(test-equal "the reader finds a sentence that begins Raises, and each link, in an entry's prose alone, outside code"
  prose-expected
  (guard (e (#t (list 'raised (describe e)))) (prose-shown prose-page)))

(test-equal "a link names a page of docs/ when it names, by a path of its own, a .md file there other than reference.md"
  link-cases
  (guard (e (#t (list 'raised (describe e))))
    (call-with-temp-directory
     (lambda (dir)
       (for-each (lambda (f) (call-with-output-file (string-append dir "/" f) (lambda (p) (put-string p "x\n"))))
                 '("streams.md" "reference.md"))
       (mkdir (string-append dir "/dir.md"))
       (mkdir (string-append dir "/sub"))
       (call-with-output-file (string-append dir "/sub/page.md") (lambda (p) (put-string p "x\n")))
       (map (lambda (c) (list (car c) (if (page-link? dir (car c)) 'page 'not-page))) link-cases)))))

(test-equal "the reader takes the keys of every key table's rows, every code span of a row's first cell, and none of another table"
  '(("a" "b" "c" "d") none)
  (guard (e (#t (list 'raised (describe e))))
    (list (key-tables key-prose) (or (key-tables '("No table here." "| `a` | b |")) 'none))))

(test-equal "the reader takes each link's text and target, outside code"
  labelled-expected
  (guard (e (#t (list 'raised (describe e)))) (labelled-links labelled-prose)))

(test-equal "a link's text names a page by its title, or by the title's part before a colon, and by nothing else"
  title-cases
  (guard (e (#t (list 'raised (describe e))))
    (map (lambda (c) (list (car c) (if (titled? (car (car c)) (cadr (car c))) 'titled 'untitled))) title-cases)))

(test-equal "a page's title is its first # heading outside a block"
  "The title"
  (guard (e (#t (list 'raised (describe e)))) (page-title titled-page)))

;; --- the oracle, and the page read -------------------------------------------------

(test-equal "the three libraries' exports are read, Chez evaluates each, and docs/reference.md reads and holds entries"
  'read
  (cond ((not (exports-ok?)) (list 'exports exported))
        ((exists (lambda (x) (pair? (caddr x))) every-export)
         (list 'kinds (filter (lambda (x) (pair? (caddr x))) every-export)))
        ((not (string? page-text)) page-text)
        ((not page) 'the-page-does-not-read)
        ((null? page-entries) 'the-page-holds-no-entry)
        (else 'read)))

;; --- the page's shape --------------------------------------------------------------

(test-equal "every ## heading of docs/reference.md begins with a library's name in code, and every ### heading lists names in code"
  '()
  (noted "docs/reference.md's headings the shape refuses, by line:" (if page (cdr page) '(unread))))

;; --- the entries, against the exports ------------------------------------------------

(test-equal "every export of (curl), (curl unsupported) and (http-client) has an entry in docs/reference.md"
  '()
  (noted "exported, and docs/reference.md has no entry for:"
         (map (lambda (x) (list (car x) (cadr x)))
              (filter (lambda (x) (not (assoc (cadr x) named))) every-export))))

(test-equal "every entry is under the section of the library that exports what it names"
  '()
  (noted "named under another library's section than its own, as (name section exporter line):"
         (fold-right (lambda (n out)
                       (let ((owner (exporter (car n)))
                             (own (let ((l (assoc (entry-library (cdr n)) exported))) (if l (cdr l) '()))))
                         (if (and owner (not (member (car n) own)))
                             (cons (list (car n) (entry-library (cdr n)) owner (entry-line (cdr n))) out)
                             out)))
                     '() named)))

(test-equal "no entry names anything the three libraries do not export"
  '()
  (noted "named by docs/reference.md, and exported by none of the three, as (name line):"
         (fold-right (lambda (n out) (if (exporter (car n)) out (cons (list (car n) (entry-line (cdr n))) out)))
                     '() named)))

(test-equal "no name has more than one entry"
  '()
  (noted "named by more than one entry, as (name lines):"
         (fold-right (lambda (n out)
                       (let ((lines (map (lambda (m) (entry-line (cdr m)))
                                         (filter (lambda (m) (string=? (car m) (car n))) named))))
                         (if (and (> (length lines) 1) (not (assoc (car n) out)))
                             (cons (list (car n) lines) out)
                             out)))
                     '() named)))

;; --- what each entry holds ----------------------------------------------------------

(test-equal "each procedure and value an entry names has its NAME : TYPE line in the entry's text block"
  '()
  (noted "a procedure or a value with no NAME : TYPE line in its entry's text block, as (name kind line):"
         (fold-right (lambda (n out)
                       (let ((k (kind-of (car n))))
                         (if (and (memq k '(procedure value)) (not (assoc (car n) (typed (entry-texts (cdr n))))))
                             (cons (list (car n) k (entry-line (cdr n))) out)
                             out)))
                     '() named)))

(test-equal "each procedure's type holds ->, and each value's does not, as Chez evaluates each"
  '()
  (noted "a type its kind refuses, as (name kind type):"
         (fold-right (lambda (n out)
                       (let ((k (kind-of (car n))) (t (assoc (car n) (typed (entry-texts (cdr n))))))
                         (if (and t (memq k '(procedure value))
                                  (not (eq? (procedure-type? (cdr t)) (eq? k 'procedure))))
                             (cons (list (car n) k (cdr t)) out)
                             out)))
                     '() named)))

(test-equal "each entry has a sentence that begins Raises"
  '()
  (noted "an entry with no sentence that begins Raises, as (line names):"
         (map heading-of (filter (lambda (e) (not (raises? (entry-prose e)))) page-entries))))

(test-equal "each entry links a page of docs/ that exists, other than reference.md"
  '()
  (noted "an entry that links no page of docs/ but reference.md, as (line names):"
         (map heading-of
              (filter (lambda (e) (not (exists (lambda (t) (page-link? "docs" t)) (links (entry-prose e)))))
                      page-entries))))

(test-equal "each entry's link to a page of docs/ names the page by its title, or the title's part before a colon"
  '()
  (noted "a link whose text is not its page's title, as (line text target title):"
         (apply append
                (map (lambda (e)
                       (fold-right
                        (lambda (l out)
                          (if (page-link? "docs" (cdr l))
                              (let* ((path (car (split (cdr l) #\#)))
                                     (path (if (starts? path "./") (substring path 2 (string-length path)) path))
                                     (title (guard (x (#t #f)) (page-title (slurp (string-append "docs/" path))))))
                                (if (and title (titled? (car l) title))
                                    out
                                    (cons (list (entry-line e) (car l) (cdr l) title) out)))
                              out))
                        '() (labelled-links (entry-prose e))))
                     page-entries))))

;; --- the key tables, against the code's lists -----------------------------------------

;; keys-of : String -> (U (Listof String) #f) — the key tables' keys in the entry that names NAME; #f for none.
(define (keys-of name)
  (let ((hit (assoc name named)))
    (and hit (key-tables (entry-prose (cdr hit))))))

(test-equal "the entry of each procedure that takes keys holds a key table naming every key it takes"
  '()
  (noted "a procedure whose key tables leave out keys it takes, as (procedure keys):"
         (fold-right (lambda (k out)
                       (let* ((taken (map symbol->string (cdr k))) (named-keys (keys-of (car k))))
                         (cond ((not named-keys) (cons (list (car k) 'no-key-table) out))
                               ((filter (lambda (key) (not (member key named-keys))) taken)
                                => (lambda (missing) (if (null? missing) out (cons (list (car k) missing) out))))
                               (else out))))
                     '() keyed)))

(test-equal "a key table names no key its procedure does not take, and each key once"
  '()
  (noted "a key table naming a key its procedure does not take, or one twice, as (procedure keys):"
         (fold-right (lambda (k out)
                       (let* ((taken (map symbol->string (cdr k))) (named-keys (or (keys-of (car k)) '()))
                              (extra (filter (lambda (key) (not (member key taken))) named-keys))
                              (twice (let loop ((ks named-keys) (seen '()) (twice '()))
                                       (cond ((null? ks) (reverse twice))
                                             ((member (car ks) seen) (loop (cdr ks) seen (cons (car ks) twice)))
                                             (else (loop (cdr ks) (cons (car ks) seen) twice))))))
                         (if (and (null? extra) (null? twice))
                             out
                             (cons (list (car k) (append extra twice)) out))))
                     '() keyed)))

(test-equal "no entry but a procedure's that takes keys holds a key table"
  '()
  (noted "an entry with a key table that names no procedure taking keys, as (line names):"
         (map heading-of
              (filter (lambda (e) (and (key-tables (entry-prose e))
                                       (not (exists (lambda (n) (assoc n keyed)) (entry-names e)))))
                      page-entries))))

(test-end "reference")

(exit (suite-exit-status runner))
