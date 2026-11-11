#!r6rs
;;; The docs' rules, held for README.org and every docs/*.md page:
;;;
;;; - every block names its language: a Markdown block scheme, sh or text;
;;;   an Org block a src block of one of them, or a quote, a verse, a center
;;;   or a comment block, so no code hides in an example block;
;;; - every Scheme block is an example's text, its lines a run of whole
;;;   consecutive lines of the example file it names, byte for byte; or a
;;;   fragment, every datum of which Chez's read reads. A block that says
;;;   neither, names no example, names one that is not there, or that no
;;;   fence closes fails, by its page and its line;
;;; - every text block says nothing after text, or names the expected
;;;   output it shows, examples/expected/NAME.out, which is there, its lines
;;;   a run of that file's whole, consecutive lines, byte for byte;
;;; - every name written as one of chez-curl's, one beginning curl-, http-,
;;;   make-curl-, make-http-, call-with-curl-, call-with-http-, &curl- or
;;;   &http-, in a fragment or in a prose code span, is an export of (curl),
;;;   (curl unsupported) or (http-client), a key of the code's key lists, a
;;;   reason of an exported reasons list, a part of a public library's name,
;;;   or, in a fragment, a name the fragment binds;
;;; - every relative link names a file or directory of the checkout, and its
;;;   #anchor, when it has one and names a page, names a heading of that
;;;   page by GitHub's rule; no link, nor any text, points into .plans/;
;;; - docs/README.md, the index, links every other docs/*.md page, and every
;;;   page it links is there; README.org links docs/README.md, and every
;;;   page the index links; the index's examples table, whose first column
;;;   is headed Example, links from each row the example its code names, and
;;;   names every example;
;;; - no page says ADR- or ADR and a space, then a digit; "not yet",
;;;   "unreleased", "on main" or "TODO"; "slice" and a digit; M and a digit,
;;;   then "slice"; or a date written YYYY-MM-DD: in any case, a line's end
;;;   between two words read as a space;
;;; - every run line of an example a page writes, in a block or a code span,
;;;   the words scheme, --libdirs, LIBDIRS, --program and examples/NAME.sps
;;;   in a row, names the LIBDIRS NAME's own head comment names in its run
;;;   line;
;;; - every code span in the first column of a table whose first header
;;;   cell is Reason or Reasons is a reason the code defines: a member of a
;;;   list whose name ends -reasons that (curl private conditions) or
;;;   (http-client private conditions) exports.
;;;
;;; Out of its reach, with no oracle but a reader's reading of the code: a
;;; fragment whose comment gives a wrong answer, and prose that says
;;; something wrong, a reason table's account of what a reason means among
;;; it. A wrong claim in prose stays a reader's to catch.
;;;
;;; The oracles: the checkout's files, read as bytes; Chez's own read; the
;;; names the three public libraries export, as Chez's library-exports lists
;;; them, their reasons lists' values, and the key lists of (curl private
;;; transfer) and (http-client private call); and the pages, read as a
;;; reader reads them. A Markdown page is CommonMark:
;;; a fenced block opens on a line of up to three spaces, then three or more
;;; backticks or tildes and an info string, and closes only on a fence of
;;; its own character, at least as long, and nothing after; its lines lose
;;; up to its fence's indent; one no fence closes runs to the page's end.
;;; Its language is its info string's first word, in any case. An HTML
;;; comment block, from a line that opens one to the line that holds -->, is
;;; neither prose nor block. Its links are each inline link and image,
;;; [text](target), and each reference definition, [label]: target, of its
;;; prose, outside code; its headings, its ATX headings outside blocks. An
;;; Org page's blocks run from #+begin_NAME to #+end_NAME, in any case; a
;;; src block's language is its first word after #+begin_src, in any case;
;;; its links are [[target]] and [[target][text]], outside blocks; its code
;;; is each =code= and ~code~ of a line; its headings, its lines of stars
;;; and a space. A heading's anchor, by GitHub's rule: its text, a link
;;; read as its text, inline code's marks and * dropped, in lower case,
;;; every char but a letter, a mark, a digit, a connector, a space or a -
;;; dropped, each space made a -; a second heading of one anchor takes -1,
;;; a third -2.
;;;
;;; A Scheme block says what it is by its info string, after scheme:
;;; Markdown's `example=examples/NAME.sps` or `fragment`, Org's
;;; `:example examples/NAME.sps` or `:fragment`, and nothing else; a text
;;; block by Markdown's `output=examples/expected/NAME.out` or Org's
;;; `:output examples/expected/NAME.out`, or nothing. The reader and each
;;; rule's procedure are held on texts of the suite's own first.
;;;
;;; Pages are read as Latin-1, one char per byte, so a block's lines are
;;; compared with its file's as bytes; a fragment's text, and a heading's,
;;; is read as UTF-8. make test runs every suite from the repository root.
;;; Each computation that can raise runs under a guard that answers what
;;; was raised, since SRFI-64 turns a raise in the actual expression into
;;; #f; no expected value is #f.
(import (rnrs)
        (rnrs eval)
        (srfi :64)
        (curl-testing)
        (only (chezscheme) directory-list file-regular? library-exports)
        (only (curl private conditions) curl-request-error-reasons)
        (only (http-client private conditions) http-request-error-reasons)
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

;; slurp-bytes : String -> String — the file's bytes, each one char, as Latin-1 reads them.
(define (slurp-bytes path)
  (let ((bytes (call-with-port (open-file-input-port path) get-bytevector-all)))
    (if (eof-object? bytes)
        ""
        (list->string (map integer->char (bytevector->u8-list bytes))))))

;; latin-1->utf-8 : String -> String — a Latin-1 string's bytes, read as UTF-8.
(define (latin-1->utf-8 s)
  (utf8->string (u8-list->bytevector (map char->integer (string->list s)))))

;; text-lines : String -> (Listof String) — the text split at each newline.
(define (text-lines s)
  (let loop ((cs (string->list s)) (line '()) (out '()))
    (cond ((null? cs) (reverse (cons (list->string (reverse line)) out)))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse line)) out)))
          (else (loop (cdr cs) (cons (car cs) line) out)))))

;; file-lines : String -> (Listof String) — the text's lines, a newline that ends it ending its last.
(define (file-lines s)
  (let ((ls (text-lines s)))
    (if (and (pair? ls) (string=? (car (reverse ls)) ""))
        (reverse (cdr (reverse ls)))
        ls)))

;; joined : (Listof String) -> String — the lines, each ended by a newline.
(define (joined lines)
  (apply string-append (map (lambda (l) (string-append l "\n")) lines)))

;; blank? : Char -> Boolean — a space or a tab.
(define (blank? c) (or (char=? c #\space) (char=? c #\tab)))

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

;; words : String -> (Listof String) — the runs of characters between blanks.
(define (words s)
  (filter (lambda (w) (not (string=? w "")))
          (split (list->string (map (lambda (c) (if (blank? c) #\space c)) (string->list s))) #\space)))

;; ascii-downcase : String -> String — A to Z folded to a to z, and no other character.
(define (ascii-downcase s)
  (list->string (map (lambda (c) (if (and (char<=? #\A c) (char<=? c #\Z))
                                     (integer->char (+ (char->integer c) 32))
                                     c))
                     (string->list s))))

;; --- Markdown: blocks, prose and links -----------------------------------------------

;; A block of a page: its line, its language, the words of its info string
;; after the language, its lines, and whether a fence closes it.
(define-record-type block (fields line language info lines closed?))

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

;; unindent : String Nat -> String — the line without up to N of its leading spaces.
(define (unindent line n)
  (let ((k (min n (run line 0 #\space)))) (substring line k (string-length line))))

;; comment-start? : String -> Boolean — the line opens an HTML comment block: up to three spaces, then <!--.
(define (comment-start? line)
  (let ((indent (run line 0 #\space)))
    (and (<= indent 3) (starts? (substring line indent (string-length line)) "<!--"))))

;; make-block-of : (List Char Nat Nat String) Nat (Listof String) Boolean -> Block
(define (make-block-of open line lines closed?)
  (let ((ws (words (cadddr open))))
    (make-block line (if (null? ws) "" (ascii-downcase (car ws))) (if (null? ws) '() (cdr ws))
                lines closed?)))

;; markdown : String -> (Pair (Listof Block) (Listof String))
;; The page's fenced blocks, in order, and its prose: every other line, as
;; a blank line for each line of a block, its fences or an HTML comment
;; block, so the prose keeps the page's line numbers.
(define (markdown text)
  (let loop ((ls (file-lines text)) (n 1) (open #f) (start 0) (body '()) (comment #f) (blocks '()) (prose '()))
    (cond ((null? ls)
           (cons (reverse (if open (cons (make-block-of open start (reverse body) #f) blocks) blocks))
                 (reverse prose)))
          (open
           (if (closes? (car ls) open)
               (loop (cdr ls) (+ n 1) #f 0 '() #f (cons (make-block-of open start (reverse body) #t) blocks)
                     (cons "" prose))
               (loop (cdr ls) (+ n 1) open start (cons (unindent (car ls) (caddr open)) body) #f blocks
                     (cons "" prose))))
          (comment (loop (cdr ls) (+ n 1) #f 0 '() (not (search (car ls) "-->" 0)) blocks (cons "" prose)))
          ((comment-start? (car ls))
           (loop (cdr ls) (+ n 1) #f 0 '()
                 (not (search (car ls) "-->" (+ (search (car ls) "<!--" 0) 4))) blocks (cons "" prose)))
          ((fence (car ls)) => (lambda (f) (loop (cdr ls) (+ n 1) f n '() #f blocks (cons "" prose))))
          (else (loop (cdr ls) (+ n 1) #f 0 '() #f blocks (cons (car ls) prose))))))

;; code-ranges : String -> (Listof (Pair Nat Nat))
;; Where each `code` span of the text begins and ends (CommonMark §6.1): a
;; run of backticks opens one, and the next run of exactly as many closes
;; it; a run that none closes is text, and so is a backtick after a
;; backslash.
(define (code-ranges text)
  (let ((n (string-length text)))
    ;; closer : Nat Nat -> (U Nat #f) — where the next run of exactly K backticks from I begins.
    (define (closer i k)
      (cond ((>= i n) #f)
            ((char=? (string-ref text i) #\`)
             (let ((m (run text i #\`))) (if (= m k) i (closer (+ i m) k))))
            (else (closer (+ i 1) k))))
    (let loop ((i 0) (out '()))
      (cond ((>= i n) (reverse out))
            ((and (char=? (string-ref text i) #\\) (< (+ i 1) n)) (loop (+ i 2) out))
            ((char=? (string-ref text i) #\`)
             (let* ((k (run text i #\`)) (j (closer (+ i k) k)))
               (if j (loop (+ j k) (cons (cons i (+ j k)) out)) (loop (+ i k) out))))
            (else (loop (+ i 1) out))))))

;; without-code : String -> String — the text with each code span made spaces, its line ends kept.
(define (without-code text)
  (let ((cs (string->list text)) (ranges (code-ranges text)))
    (let loop ((cs cs) (i 0) (out '()))
      (if (null? cs)
          (list->string (reverse out))
          (loop (cdr cs) (+ i 1)
                (cons (if (and (not (char=? (car cs) #\newline))
                               (exists (lambda (r) (and (<= (car r) i) (< i (cdr r)))) ranges))
                          #\space
                          (car cs))
                      out))))))

;; destination : String -> String — a link's target, without the angle brackets around it.
(define (destination s)
  (if (and (starts? s "<") (ends? s ">")) (substring s 1 (- (string-length s) 1)) s))

;; markdown-links : (Listof String) -> (Listof String)
;; The target of each inline link and image of the prose, [text](target),
;; outside code: what follows "](" up to a blank, a line's end or the ")"
;; that ends it; then each reference definition's, a line of up to three
;; spaces, then [label]: and its target, a label beginning ^ being a
;; footnote's.
(define (markdown-links prose)
  (let ((s (without-code (joined prose))))
    (append
     (let loop ((i 0) (out '()))
       (let ((j (search s "](" i)))
         (if (not j)
             (reverse out)
             (let end ((k (+ j 2)))
               (if (or (>= k (string-length s)) (memv (string-ref s k) '(#\) #\space #\tab #\newline)))
                   (loop k (cons (destination (substring s (+ j 2) k)) out))
                   (end (+ k 1)))))))
     (fold-right
      (lambda (line out)
        (let* ((indent (run line 0 #\space))
               (rest (substring line (min indent (string-length line)) (string-length line)))
               (close (search rest "]:" 0)))
          (if (and (<= indent 3) (starts? rest "[") (not (starts? rest "[^")) close
                   (pair? (words (substring rest (+ close 2) (string-length rest)))))
              (cons (destination (car (words (substring rest (+ close 2) (string-length rest))))) out)
              out)))
      '() (text-lines s)))))

;; --- Org: blocks and links -------------------------------------------------------

;; org-keyword : String String -> (U String #f)
;; The rest of the line after KEYWORD, such as #+begin_, when the line,
;; past its blanks, begins with it in any case; else #f.
(define (org-keyword line keyword)
  (let ((s (trim line)))
    (and (starts? (ascii-downcase s) keyword) (substring s (string-length keyword) (string-length s)))))

;; org : String -> (Pair (Listof Block) (Listof String))
;; The page's blocks, in order, and its prose: every line outside a block,
;; a block's lines and its #+begin_ and #+end_ lines being blank lines. A
;; block runs from #+begin_NAME to #+end_NAME, NAME in any case; a src
;; block's language is the first word after #+begin_src, "" for none, and
;; its info the words after that; any other block's language is # and its
;; NAME, and its info the words after NAME. One no #+end_ closes runs to
;; the page's end.
(define (org text)
  (let loop ((ls (file-lines text)) (n 1) (open #f) (start 0) (body '()) (blocks '()) (prose '()))
    (let ((finish (lambda (closed?)
                    (let ((ws (cadr open)))
                      (cons (if (string=? (car open) "src")
                                (make-block start (if (null? ws) "" (ascii-downcase (car ws)))
                                            (if (null? ws) '() (cdr ws)) (reverse body) closed?)
                                (make-block start (string-append "#" (car open)) ws (reverse body) closed?))
                            blocks)))))
      (cond ((null? ls) (cons (reverse (if open (finish #f) blocks)) (reverse prose)))
            (open
             (let ((end (org-keyword (car ls) "#+end_")))
               (if (and end (string=? (ascii-downcase (trim end)) (car open)))
                   (loop (cdr ls) (+ n 1) #f 0 '() (finish #t) (cons "" prose))
                   (loop (cdr ls) (+ n 1) open start (cons (car ls) body) blocks (cons "" prose)))))
            ((org-keyword (car ls) "#+begin_")
             => (lambda (rest)
                  (let ((ws (words rest)))
                    (if (null? ws)
                        (loop (cdr ls) (+ n 1) #f 0 '() blocks (cons (car ls) prose))
                        (loop (cdr ls) (+ n 1) (list (ascii-downcase (car ws)) (cdr ws)) n '() blocks
                              (cons "" prose))))))
            (else (loop (cdr ls) (+ n 1) #f 0 '() blocks (cons (car ls) prose)))))))

;; org-links : (Listof String) -> (Listof String)
;; The target of each [[target]] and [[target][text]] link of the prose.
(define (org-links prose)
  (let ((s (joined prose)))
    (let loop ((i 0) (out '()))
      (let ((j (search s "[[" i)))
        (if (not j)
            (reverse out)
            (let end ((k (+ j 2)))
              (cond ((>= k (string-length s)) (reverse out))
                    ((char=? (string-ref s k) #\]) (loop k (cons (substring s (+ j 2) k) out)))
                    (else (end (+ k 1))))))))))

;; --- links, resolved ------------------------------------------------------------

;; scheme-like? : String -> Boolean — the target begins with a URI scheme and a colon, as https: or mailto: does.
(define (scheme-like? target)
  (let ((colon (search target ":" 0)))
    (and colon (> colon 0)
         (char-alphabetic? (string-ref target 0))
         (for-all (lambda (c) (or (char-alphabetic? c) (char-numeric? c) (memv c '(#\+ #\- #\.))))
                  (string->list (substring target 0 colon))))))

;; relative-path : String Boolean -> (U String #f)
;; A link's file, when it names one of the checkout: its #fragment and
;; ?query dropped, and for an Org link a file: before it and a ::search
;; after it; #f for a link with a scheme, a place on its own page, # or
;; for Org *, or nothing.
(define (relative-path target org?)
  (let* ((t (if (and org? (starts? target "file:")) (substring target 5 (string-length target)) target))
         (t (if org? (let ((k (search t "::" 0))) (if k (substring t 0 k) t)) t))
         (cut (lambda (t c) (let ((k (search t c 0))) (if k (substring t 0 k) t))))
         (t (cut (cut t "#") "?")))
    (and (not (string=? t ""))
         (not (starts? target "#"))
         (not (and org? (starts? target "*")))
         (not (scheme-like? t))
         t)))

;; resolve : String String -> (U String #f)
;; PATH, relative to the directory DIR of the checkout ("" for its root),
;; as a path from the root: its . and empty segments dropped, each ..
;; taking off the segment before; #f when it climbs out of the root, or is
;; absolute.
(define (resolve dir path)
  (and (not (starts? path "/"))
       (let loop ((segments (append (if (string=? dir "") '() (split dir #\/)) (split path #\/)))
                  (out '()))
         (cond ((null? segments)
                (if (null? out) "" (fold-left (lambda (acc s) (if (string=? acc "") s (string-append acc "/" s)))
                                             "" (reverse out))))
               ((member (car segments) '("" ".")) (loop (cdr segments) out))
               ((string=? (car segments) "..") (and (pair? out) (loop (cdr segments) (cdr out))))
               (else (loop (cdr segments) (cons (car segments) out)))))))

;; into-plans? : String -> Boolean — the resolved path is .plans, or under it.
(define (into-plans? path)
  (or (string=? path ".plans") (starts? path ".plans/")))

;; --- what a Scheme block says ---------------------------------------------------

;; marker : Block Boolean -> (U (List 'example String) (List 'fragment) (List 'none))
;; What the block's info says it is: Markdown's example=PATH or fragment,
;; Org's :example PATH or :fragment, alone; else none.
(define (marker b org?)
  (let ((info (block-info b)))
    (cond ((equal? info (if org? '(":fragment") '("fragment"))) '(fragment))
          ((and org? (= (length info) 2) (string=? (car info) ":example")) (list 'example (cadr info)))
          ((and (not org?) (= (length info) 1) (starts? (car info) "example="))
           (list 'example (substring (car info) 8 (string-length (car info)))))
          (else '(none)))))

;; example-path? : String -> Boolean — written as an example: examples/, then a name, ending .sps, with no . or .. segment.
(define (example-path? path)
  (let ((segments (split path #\/)))
    (and (starts? path "examples/")
         (ends? path ".sps")
         (> (string-length path) (string-length "examples/.sps"))
         (for-all (lambda (s) (not (member s '("" "." "..")))) segments))))

;; run-of? : (Listof String) (Listof String) -> Boolean
;; Whether LINES, holding a line that is not blank, are a run of whole
;; consecutive lines of FILE, each equal, char for char.
(define (run-of? lines file)
  (and (exists (lambda (l) (not (string=? (trim l) ""))) lines)
       (let try ((rest file))
         (and (>= (length rest) (length lines))
              (or (let same ((a lines) (b rest))
                    (or (null? a) (and (string=? (car a) (car b)) (same (cdr a) (cdr b)))))
                  (try (cdr rest)))))))

;; datums : String -> (U (Listof Any) #f) — every datum Chez's read reads from the text; #f when a read raises.
(define (datums text)
  (guard (e (#t #f))
    (let ((p (open-string-input-port text)))
      (let loop ((out '()))
        (let ((d (read p)))
          (if (eof-object? d) (reverse out) (loop (cons d out))))))))

;; --- what a text block says -------------------------------------------------------

;; output-of : Block Boolean -> (U (List 'output String) (List 'none) (List 'other))
;; What a text block's info says: nothing; Markdown's output=PATH or Org's
;; :output PATH, alone; or something else.
(define (output-of b org?)
  (let ((info (block-info b)))
    (cond ((null? info) '(none))
          ((and org? (= (length info) 2) (string=? (car info) ":output")) (list 'output (cadr info)))
          ((and (not org?) (= (length info) 1) (starts? (car info) "output="))
           (list 'output (substring (car info) 7 (string-length (car info)))))
          (else '(other)))))

;; output-path? : String -> Boolean — written as an expected output: examples/expected/, a name, ending .out, with no . or .. segment.
(define (output-path? path)
  (and (starts? path "examples/expected/")
       (ends? path ".out")
       (> (string-length path) (string-length "examples/expected/.out"))
       (for-all (lambda (s) (not (member s '("" "." "..")))) (split path #\/))))

;; --- tables ---------------------------------------------------------------------

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

;; table-rows : (Listof String) String -> (U (Listof String) #f)
;; The body rows of the prose's first table whose header's first cell is
;; FIRST: a row with a bar over a delimiter row of as many cells, then each
;; row up to a blank line or a line with no bar; #f for no such table.
(define (table-rows prose first)
  (let scan ((ls prose))
    (cond ((or (null? ls) (null? (cdr ls))) #f)
          ((and (has-bar? (car ls)) (delimiter-row? (cadr ls))
                (= (length (cells (car ls))) (length (cells (cadr ls))))
                (equal? (car (cells (car ls))) first))
           (let rows ((ls (cddr ls)) (out '()))
             (if (or (null? ls) (string=? (trim (car ls)) "") (not (has-bar? (car ls))))
                 (reverse out)
                 (rows (cdr ls) (cons (car ls) out)))))
          (else (scan (cdr ls))))))

;; tables-headed : (Listof String) (Listof String) -> (Listof (Listof String))
;; The body rows of every table of the prose whose header's first cell is
;; one of FIRSTS, each read as table-rows reads one, the tables in order.
(define (tables-headed prose firsts)
  (let scan ((ls prose) (out '()))
    (cond ((or (null? ls) (null? (cdr ls))) (reverse out))
          ((and (has-bar? (car ls)) (delimiter-row? (cadr ls))
                (= (length (cells (car ls))) (length (cells (cadr ls))))
                (member (car (cells (car ls))) firsts))
           (let rows ((rest (cddr ls)) (acc '()))
             (if (or (null? rest) (string=? (trim (car rest)) "") (not (has-bar? (car rest))))
                 (scan rest (cons (reverse acc) out))
                 (rows (cdr rest) (cons (car rest) acc)))))
          (else (scan (cdr ls) out)))))

;; first-cell-code : String -> (Listof String)
;; The text of each code span of a table row's first cell, in order, its
;; backticks dropped; none for a row of no cell.
(define (first-cell-code row)
  (let ((cs (cells row)))
    (if (null? cs)
        '()
        (let ((cell (car cs)))
          (map (lambda (r) (let ((k (run cell (car r) #\`))) (substring cell (+ (car r) k) (- (cdr r) k))))
               (code-ranges cell))))))

;; --- names in code ---------------------------------------------------------------

;; markdown-code : (Listof String) -> (Listof (Pair Nat String))
;; Each code span of the prose, outside blocks, as its line and its text,
;; its backticks dropped.
(define (markdown-code prose)
  (let ((s (joined prose)))
    (map (lambda (r)
           (let* ((k (run s (car r) #\`))
                  (line (+ 1 (length (filter (lambda (c) (char=? c #\newline))
                                             (string->list (substring s 0 (car r))))))))
             (cons line (substring s (+ (car r) k) (- (cdr r) k)))))
         (code-ranges s))))

;; org-markup-char? : Char -> Boolean — a char that may follow an Org code span's close.
(define (org-markup-char? c) (memv c (string->list " \t-.,:;!?'\")}]")))

;; org-code : (Listof String) -> (Listof (Pair Nat String))
;; Each =code= and ~code~ of the prose's lines, as its line and its text:
;; the mark at a line's start or after a blank or one of ({['", its text
;; neither beginning nor ending with a blank, the same mark closing it at
;; the line's end or before a blank or a mark of punctuation.
(define (org-code prose)
  (let loop ((ls prose) (n 1) (out '()))
    (if (null? ls)
        (reverse out)
        (let* ((s (car ls)) (len (string-length s)))
          (let scan ((i 0) (out out))
            (if (>= i len)
                (loop (cdr ls) (+ n 1) out)
                (let ((c (string-ref s i)))
                  (if (and (memv c '(#\= #\~))
                           (or (= i 0) (memv (string-ref s (- i 1)) (string->list " \t({['\"")))
                           (< (+ i 1) len) (not (blank? (string-ref s (+ i 1)))))
                      (let close ((j (+ i 2)))
                        (cond ((>= j len) (scan (+ i 1) out))
                              ((and (char=? (string-ref s j) c) (not (blank? (string-ref s (- j 1))))
                                    (or (= (+ j 1) len) (org-markup-char? (string-ref s (+ j 1)))))
                               (scan (+ j 1) (cons (cons n (substring s (+ i 1) j)) out)))
                              (else (close (+ j 1)))))
                      (scan (+ i 1) out)))))))))

;; name-char? : Char -> Boolean — a char of a Scheme name as the pages write them.
(define (name-char? c)
  (or (char-alphabetic? c) (char-numeric? c) (memv c (string->list "-!?*<>=/+&%$^_.@:"))))

;; name-tokens : String -> (Listof String)
;; The runs of name chars of the text, each without the . and : that end it.
(define (name-tokens s)
  (let ((tidy (lambda (t)
                (let back ((k (string-length t)))
                  (if (and (> k 0) (memv (string-ref t (- k 1)) '(#\. #\:))) (back (- k 1)) (substring t 0 k))))))
    (let loop ((cs (string->list s)) (tok '()) (out '()))
      (let ((flush (lambda () (if (null? tok) out (cons (tidy (list->string (reverse tok))) out)))))
        (cond ((null? cs) (reverse (flush)))
              ((name-char? (car cs)) (loop (cdr cs) (cons (car cs) tok) out))
              (else (loop (cdr cs) '() (flush))))))))

;; name-prefixes : (Listof String) — how a name of chez-curl's begins.
(define name-prefixes
  '("curl-" "http-" "make-curl-" "make-http-" "call-with-curl-" "call-with-http-" "&curl-" "&http-"))

;; chez-curl-like? : String -> Boolean
(define (chez-curl-like? s) (exists (lambda (p) (starts? s p)) name-prefixes))

;; symbols-of : Any -> (Listof Symbol) — every symbol in the datum, pairs and vectors walked.
(define (symbols-of d)
  (cond ((symbol? d) (list d))
        ((pair? d) (append (symbols-of (car d)) (symbols-of (cdr d))))
        ((vector? d) (apply append (map symbols-of (vector->list d))))
        (else '())))

;; formals : Any -> (Listof Symbol) — the symbols of a formals list, an improper one's rest among them.
(define (formals f)
  (cond ((symbol? f) (list f))
        ((pair? f) (append (formals (car f)) (formals (cdr f))))
        (else '())))

;; bound : Any -> (Listof Symbol)
;; The names the datum binds, anywhere in it: a define's or a
;; define-syntax's name and formals; a lambda's and a case-lambda's
;; formals; a let's, a named let's, a let*'s, a letrec's or a
;; let-values' names; a guard's variable.
(define (bound d)
  (if (not (pair? d))
      '()
      (append
       (let ((head (car d)) (rest (cdr d)))
         (cond ((not (pair? rest)) '())
               ((memq head '(define define-syntax))
                (if (or (pair? (car rest)) (symbol? (car rest))) (formals (car rest)) '()))
               ((eq? head 'lambda) (formals (car rest)))
               ((eq? head 'case-lambda)
                (apply append (map (lambda (c) (if (pair? c) (formals (car c)) '())) (filter pair? rest))))
               ((memq head '(let let* letrec letrec* let-values let*-values))
                (let* ((named (symbol? (car rest)))
                       (bindings (if named (if (pair? (cdr rest)) (cadr rest) '()) (car rest))))
                  (append (if named (list (car rest)) '())
                          (if (list? bindings)
                              (apply append (map (lambda (b) (if (pair? b) (formals (car b)) '())) bindings))
                              '()))))
               ((and (eq? head 'guard) (pair? (car rest)) (symbol? (caar rest))) (list (caar rest)))
               (else '())))
       (let walk ((x d))
         (cond ((pair? x) (append (bound (car x)) (walk (cdr x))))
               (else '()))))))

;; --- run lines -------------------------------------------------------------------

;; run-lines-in : String -> (Listof (Pair String String))
;; Each run line of an example the text holds, the words scheme, --libdirs,
;; LIBDIRS, --program and examples/NAME.sps in a row, a line's end read as
;; a blank, as (NAME . LIBDIRS), in order.
(define (run-lines-in text)
  (let loop ((ws (words (list->string (map (lambda (c) (if (char=? c #\newline) #\space c)) (string->list text)))))
             (out '()))
    (if (< (length ws) 5)
        (reverse out)
        (let ((path (list-ref ws 4)))
          (if (and (string=? (car ws) "scheme") (string=? (cadr ws) "--libdirs") (string=? (list-ref ws 3) "--program")
                   (starts? path "examples/") (ends? path ".sps") (> (string-length path) 13))
              (loop (cdr ws) (cons (cons (substring path 9 (- (string-length path) 4)) (caddr ws)) out))
              (loop (cdr ws) out))))))

;; head-libdirs : String -> (U String #f)
;; The LIBDIRS examples/NAME.sps's head comment names: the word after
;; --libdirs in the one line of its head, the ;;; lines after its first up
;; to any other, that holds --program; #f for no such file, a head with no
;; such line or more than one, or a line with no word after --libdirs.
(define (head-libdirs name)
  (let ((path (string-append "examples/" name ".sps")))
    (and (file-regular? path)
         (let* ((ls (file-lines (slurp-bytes path)))
                (head (let loop ((ls (if (pair? ls) (cdr ls) '())) (out '()))
                        (if (and (pair? ls) (starts? (car ls) ";;;")) (loop (cdr ls) (cons (car ls) out)) (reverse out))))
                (runs (filter (lambda (l) (member "--program" (words l))) head)))
           (and (= (length runs) 1)
                (let ((tail (member "--libdirs" (words (car runs)))))
                  (and tail (pair? (cdr tail)) (cadr tail))))))))

;; page-run-lines : Page -> (Listof (List Symbol Nat String String))
;; Each run line of an example in the page's blocks, every language's, and
;; in its prose's code spans, as (block LINE NAME LIBDIRS) or (code LINE
;; NAME LIBDIRS), LINE the block's or the span's.
(define (page-run-lines p)
  (append
   (apply append
          (map (lambda (b) (map (lambda (r) (list 'block (block-line b) (car r) (cdr r)))
                                (run-lines-in (joined (block-lines b)))))
               (page-blocks p)))
   (apply append
          (map (lambda (lc) (map (lambda (r) (list 'code (car lc) (car r) (cdr r))) (run-lines-in (cdr lc))))
               (if (page-org? p) (org-code (page-prose p)) (markdown-code (page-prose p)))))))

;; --- headings and anchors --------------------------------------------------------

;; atx-heading : String -> (U String #f)
;; The line as an ATX heading (CommonMark §4.2), its text, trimmed, a
;; closing run of # after a blank dropped; #f for any other line.
(define (atx-heading line)
  (let* ((indent (run line 0 #\space)) (n (string-length line)))
    (and (<= indent 3) (< indent n) (char=? (string-ref line indent) #\#)
         (let ((level (run line indent #\#)))
           (and (<= level 6)
                (let ((after (+ indent level)))
                  (and (or (= after n) (blank? (string-ref line after)))
                       (let* ((text (trim (substring line after n)))
                              (m (string-length text))
                              (closing (let back ((j m)) (if (and (> j 0) (char=? (string-ref text (- j 1)) #\#)) (back (- j 1)) j))))
                         (cond ((= closing 0) "")
                               ((and (< closing m) (blank? (string-ref text (- closing 1)))) (trim (substring text 0 closing)))
                               (else text))))))))))

;; org-heading : String -> (U String #f) — the line as an Org heading, stars then a space, its text; #f for any other.
(define (org-heading line)
  (let ((k (run line 0 #\*)))
    (and (> k 0) (< k (string-length line)) (char=? (string-ref line k) #\space)
         (trim (substring line k (string-length line))))))

;; link-text : String -> String
;; The text with each Markdown link or image, [text](target), read as its
;; text, and each Org link, [[target][text]] or [[target]], as its text.
(define (link-text s)
  (let loop ((cs (string->list s)) (out '()))
    (cond ((null? cs) (list->string (reverse out)))
          ((and (char=? (car cs) #\[) (pair? (cdr cs)) (char=? (cadr cs) #\[))
           (let* ((rest (list->string (cddr cs))) (close (search rest "]]" 0)))
             (if close
                 (let* ((inner (substring rest 0 close)) (mid (search inner "][" 0))
                        (text (if mid (substring inner (+ mid 2) (string-length inner)) inner)))
                   (loop (string->list (substring rest (+ close 2) (string-length rest))) (append (reverse (string->list text)) out)))
                 (loop (cdr cs) (cons (car cs) out)))))
          ((char=? (car cs) #\[)
           (let* ((rest (list->string (cdr cs))) (mid (search rest "](" 0)))
             (if mid
                 (let ((close (search rest ")" (+ mid 2))))
                   (if close
                       (loop (string->list (substring rest (+ close 1) (string-length rest)))
                             (append (reverse (string->list (substring rest 0 mid))) out))
                       (loop (cdr cs) (cons (car cs) out))))
                 (loop (cdr cs) (cons (car cs) out)))))
          ((and (char=? (car cs) #\!) (pair? (cdr cs)) (char=? (cadr cs) #\[)) (loop (cdr cs) out))
          (else (loop (cdr cs) (cons (car cs) out))))))

;; slug : String -> String
;; A heading's anchor, by GitHub's rule, before a repeat's number: its
;; text with links read as their text, and every `, *, = and ~ dropped; in
;; lower case; every char but a letter, a mark, a digit, a connector, a
;; space or a - dropped; each space a -.
(define (slug text)
  (let* ((t (list->string (filter (lambda (c) (not (memv c '(#\` #\* #\= #\~)))) (string->list (link-text text)))))
         (t (list->string (map char-downcase (string->list t)))))
    (list->string
     (map (lambda (c) (if (char=? c #\space) #\- c))
          (filter (lambda (c)
                    (or (char=? c #\space) (char=? c #\-)
                        (memq (char-general-category c) '(Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc))))
                  (string->list t))))))

;; anchors : (Listof String) -> (Listof String)
;; The anchors of headings with these texts, in order: a repeat of an
;; anchor takes -1, the next -2, each made anew until it is unique.
(define (anchors texts)
  (let loop ((ts texts) (seen '()))
    (if (null? ts)
        (reverse seen)
        (let ((base (slug (car ts))))
          (let try ((k 0))
            (let ((a (if (= k 0) base (string-append base "-" (number->string k)))))
              (if (member a seen) (try (+ k 1)) (loop (cdr ts) (cons a seen)))))))))

;; page-anchors : String -> (Listof String)
;; The anchors of the file at PATH, a Markdown or an Org page: its
;; headings' texts, outside blocks, read as UTF-8.
(define (page-anchors path)
  (let* ((text (slurp-bytes path)) (org? (ends? path ".org"))
         (prose (if org? (cdr (org text)) (cdr (markdown text)))))
    (anchors (map latin-1->utf-8 (filter (lambda (x) x) (map (if org? org-heading atx-heading) prose))))))

;; --- stale words -----------------------------------------------------------------

;; word-char? : Char -> Boolean — an ASCII letter or digit.
(define (word-char? c)
  (or (and (char<=? #\a c) (char<=? c #\z)) (and (char<=? #\A c) (char<=? c #\Z))
      (and (char<=? #\0 c) (char<=? c #\9))))

;; letter? : Char -> Boolean — an ASCII letter.
(define (letter? c) (or (and (char<=? #\a c) (char<=? c #\z)) (and (char<=? #\A c) (char<=? c #\Z))))

;; normalized : String -> (Pair String (Vectorof Nat))
;; The text, A to Z folded, each run of blanks and line ends one space; and
;; for each of its chars, the line it came from.
(define (normalized text)
  (let loop ((cs (string->list text)) (line 1) (white #f) (out '()) (lines '()))
    (cond ((null? cs) (cons (ascii-downcase (list->string (reverse out))) (list->vector (reverse lines))))
          ((or (blank? (car cs)) (char=? (car cs) #\newline) (char=? (car cs) #\return))
           (let ((next (if (char=? (car cs) #\newline) (+ line 1) line)))
             (if white
                 (loop (cdr cs) next #t out lines)
                 (loop (cdr cs) next #t (cons #\space out) (cons line lines)))))
          (else (loop (cdr cs) line #f (cons (car cs) out) (cons line lines))))))

;; digit? : Char -> Boolean — an ASCII digit.
(define (digit? c) (and (char<=? #\0 c) (char<=? c #\9)))

;; digits-at : String Nat -> Nat — how many ASCII digits begin at I.
(define (digits-at s i)
  (let loop ((j i)) (if (and (< j (string-length s)) (digit? (string-ref s j))) (loop (+ j 1)) (- j i))))

;; at? : String Nat String -> Boolean — whether PAT begins at I.
(define (at? s i pat)
  (let ((k (string-length pat)))
    (and (<= (+ i k) (string-length s))
         (let loop ((j 0)) (or (= j k) (and (char=? (string-ref s (+ i j)) (string-ref pat j)) (loop (+ j 1))))))))

;; stale-rules : (Listof (Pair String (String Nat -> Boolean)))
;; Each stale phrase, by its name, with whether it begins at a place of the
;; text, which is in lower case: adr- or adr and a space, then a digit, no
;; letter before; not yet, no word char after; unreleased anywhere; on
;; main, no word char either side; todo, no letter before; slice, then a
;; digit, or a space and a digit, no letter before; m, a digit or more,
;; then a space and slice, no letter before; a date, four digits, -, two,
;; -, two, no digit either side.
(define stale-rules
  (let ((no-letter-before (lambda (s i) (or (= i 0) (not (letter? (string-ref s (- i 1)))))))
        (no-word-at (lambda (s i) (or (>= i (string-length s)) (not (word-char? (string-ref s i))))))
        (digit-at (lambda (s i) (and (< i (string-length s)) (digit? (string-ref s i))))))
    (list (cons "adr-" (lambda (s i) (and (at? s i "adr-") (no-letter-before s i) (digit-at s (+ i 4)))))
          (cons "adr " (lambda (s i) (and (at? s i "adr ") (no-letter-before s i) (digit-at s (+ i 4)))))
          (cons "not yet" (lambda (s i) (and (at? s i "not yet") (no-word-at s (+ i 7)))))
          (cons "unreleased" (lambda (s i) (at? s i "unreleased")))
          (cons "on main" (lambda (s i) (and (at? s i "on main") (or (= i 0) (not (word-char? (string-ref s (- i 1)))))
                                             (no-word-at s (+ i 7)))))
          (cons "todo" (lambda (s i) (and (at? s i "todo") (no-letter-before s i))))
          (cons "slice" (lambda (s i) (and (at? s i "slice") (no-letter-before s i)
                                           (or (digit-at s (+ i 5)) (and (at? s (+ i 5) " ") (digit-at s (+ i 6)))))))
          (cons "m-slice" (lambda (s i) (and (at? s i "m") (no-letter-before s i)
                                             (let ((k (digits-at s (+ i 1))))
                                               (and (> k 0) (at? s (+ i 1 k) " slice"))))))
          (cons "date" (lambda (s i) (and (or (= i 0) (not (digit? (string-ref s (- i 1)))))
                                          (= (digits-at s i) 4) (at? s (+ i 4) "-")
                                          (= (digits-at s (+ i 5)) 2) (at? s (+ i 7) "-")
                                          (= (digits-at s (+ i 8)) 2)))))))

;; stale : String -> (Listof (Pair Nat String))
;; Each stale phrase the text says, as its line and the phrase's name, in
;; order of the rules, then of the text.
(define (stale text)
  (let* ((n (normalized text)) (s (car n)) (lines (cdr n)) (len (string-length s)))
    (apply append
           (map (lambda (rule)
                  (let loop ((i 0) (out '()))
                    (if (>= i len)
                        (reverse out)
                        (loop (+ i 1) (if ((cdr rule) s i) (cons (cons (vector-ref lines i) (car rule)) out) out)))))
                stale-rules))))

;; noted : String (Listof Any) -> (Listof Any)
;; The items, written on stderr after WHAT when there are any.
(define (noted what xs)
  (unless (null? xs)
    (let ((p (current-error-port)))
      (put-string p what)
      (for-each (lambda (x) (put-string p "\n  ") (write x p)) xs)
      (put-char p #\newline)
      (flush-output-port p)))
  xs)

;; guarded : (-> Any) -> Any — THUNK's answer, or (raised WHAT).
(define (guarded thunk) (guard (e (#t (list 'raised (describe e)))) (thunk)))

;; --- the reader, on texts of the suite's own ----------------------------------------------

;; A Markdown page of blocks of each kind: fences of both characters and of
;; more than three, an indented one, one that holds a shorter fence or the
;; other character's, and one no fence closes.
(define markdown-page
  (joined
   '("Some text."
     "```scheme example=examples/a.sps"
     "(display 1)"
     "```"
     "~~~~ Scheme fragment"
     "```"
     "~~~"
     "still inside"
     "~~~~"
     "  ````sh"
     "  echo hi"
     "     indented more"
     "  ```"
     "  ````"
     "<!--"
     "```scheme"
     "-->"
     "```text"
     "plain"
     "~~~ not closed by tildes"
     "```   "
     "``` scheme"
     "no marker"
     "````"
     "``scheme not a fence"
     "````scheme fragment"
     "unclosed at the end")))

;; What markdown must take from it, each block as (line language info lines closed?).
(define markdown-expected
  '((2 "scheme" ("example=examples/a.sps") ("(display 1)") #t)
    (5 "scheme" ("fragment") ("```" "~~~" "still inside") #t)
    (10 "sh" () ("echo hi" "   indented more" "```") #t)
    (18 "text" () ("plain" "~~~ not closed by tildes") #t)
    (22 "scheme" () ("no marker") #t)
    (26 "scheme" ("fragment") ("unclosed at the end") #f)))

;; block-shown : Block -> List
(define (block-shown b)
  (list (block-line b) (block-language b) (block-info b) (block-lines b) (block-closed? b)))

;; An Org page of src blocks, in any case, a src line inside another block,
;; blocks of other kinds, an indented block and one nothing closes.
(define org-page
  (joined
   '("* Heading"
     "#+begin_src scheme :example examples/a.sps"
     "(display 1)"
     "#+end_src"
     "#+BEGIN_SRC Scheme :fragment"
     "'(a b)"
     "#+END_SRC"
     "#+begin_example"
     "#+begin_src scheme"
     "inside an example block"
     "#+end_example"
     "#+begin_src sh"
     "ls"
     "#+end_src"
     "  #+begin_src scheme"
     "  indented"
     "  #+end_src"
     "#+begin_src"
     "no language"
     "#+end_src"
     "#+begin_quote"
     "A quote."
     "#+end_quote"
     "#+begin_src scheme :fragment"
     "unclosed")))

(define org-expected
  '((2 "scheme" (":example" "examples/a.sps") ("(display 1)") #t)
    (5 "scheme" (":fragment") ("'(a b)") #t)
    (8 "#example" () ("#+begin_src scheme" "inside an example block") #t)
    (12 "sh" () ("ls") #t)
    (15 "scheme" () ("  indented") #t)
    (18 "" () ("no language") #t)
    (21 "#quote" () ("A quote.") #t)
    (24 "scheme" (":fragment") ("unclosed") #f)))

;; A Markdown page of links: inline, an image with a title, external, on the
;; page, in code, reference definitions, a footnote, in a block, in a
;; comment.
(define markdown-links-page
  (joined
   '("See [a](a.md), ![img](img/x.png \"title\"), [ext](https://e.com/), [here](#h),"
     "`[code](code.md)` and [docs](../docs/README.md#top)."
     "[ref]: ref.md"
     "   [ref2]: <ref2.md>"
     "[^1]: a footnote, not a link"
     "```text"
     "[in](block.md)"
     "```"
     "<!-- [hidden](hidden.md) -->")))

(define markdown-links-expected
  '("a.md" "img/x.png" "https://e.com/" "#h" "../docs/README.md#top" "ref.md" "ref2.md"))

;; An Org page of links: a file: link, an external one, a bare path, a
;; heading's, a search, and one in a block.
(define org-links-page
  (joined
   '("[[file:LICENSE][LICENSE]] and [[https://x.example/][y]]"
     "[[docs/README.md]] [[*Heading]] [[./a.org::*x][a]]"
     "#+begin_src scheme :fragment"
     "[[in-block.md]]"
     "#+end_src")))

(define org-links-expected
  '("file:LICENSE" "https://x.example/" "docs/README.md" "*Heading" "./a.org::*x"))

;; Links, each with the page's directory and whether it is Org, and the
;; path relative-path and resolve make of it, or none.
(define resolve-cases
  '((("docs" #f "a.md") "docs/a.md")
    (("docs" #f "../README.org") "README.org")
    (("docs" #f "./b.md?q=1#x") "docs/b.md")
    (("docs" #f "../examples/") "examples")
    (("docs" #f "../../outside.md") none)
    (("docs" #f "/etc/passwd") none)
    (("docs" #f "https://e.com/a.md") none)
    (("docs" #f "mailto:a@b.example") none)
    (("docs" #f "#h") none)
    (("" #t "file:LICENSE") "LICENSE")
    (("" #t "./docs/README.md") "docs/README.md")
    (("" #t "file:a.org::*x") "a.org")
    (("" #t "*Heading") none)
    (("" #t "https://x.example/") none)
    (("docs" #f "../.plans/progress.md") ".plans/progress.md")))

;; The example's lines a block is tried against, and each block with
;; whether it is a run of them.
(define example-file '("(import (rnrs))" "" "(display \"x\")" "(newline)"))
(define run-cases
  '((("(display \"x\")" "(newline)") run)
    (("(newline)") run)
    (("(import (rnrs))" "") run)
    (("(import (rnrs))" "(display \"x\")") no-run)
    (("(display \"x\") ") no-run)
    (("(display \"y\")") no-run)
    (("(newline)" "(more)") no-run)
    (("") no-run)
    (() no-run)))

;; A text that says each stale phrase, and near misses that are none.
(define stale-text
  (joined
   '("This is NOT"
     "YET done, and cannot yet be."
     "See adr-0038, Adr-1, not ADR-x, nor cadr-1."
     "An Unreleased feature, merged On Main today."
     "The version maintained by, on mainland, on main."
     "todos, ToDo, mastodon."
     "Ends ADR-"
     "ADR 0035 and radr 5, and ADR x."
     "In M7 slice 4, a slice of bread, slices, slice3."
     "Decided 2026-11-04, not 12026-11-04, 2026-11-045 or 1.2.3-4."
     "A dream7 slice.")))

(define stale-expected
  '((3 . "adr-") (3 . "adr-")
    (8 . "adr ")
    (1 . "not yet") (2 . "not yet")
    (4 . "unreleased")
    (4 . "on main") (5 . "on main")
    (6 . "todo") (6 . "todo")
    (9 . "slice") (9 . "slice")
    (9 . "m-slice")
    (10 . "date")))

;; A block's language, whether its page is Org, and whether it is named.
(define language-cases
  '((("scheme" #f) named) (("sh" #f) named) (("text" #f) named) (("" #f) unnamed) (("scm" #f) unnamed)
    (("#quote" #f) unnamed) (("scheme" #t) named) (("text" #t) named) (("" #t) unnamed)
    (("#quote" #t) named) (("#verse" #t) named) (("#center" #t) named) (("#comment" #t) named)
    (("#example" #t) unnamed) (("#export" #t) unnamed) (("lisp" #t) unnamed)))

;; A text block's info, whether its page is Org, and what it says.
(define output-cases
  '(((("output=examples/expected/a.out") #f) (output "examples/expected/a.out"))
    ((() #f) (none))
    ((("output=") #f) (output ""))
    ((("fragment") #f) (other))
    ((("output=examples/expected/a.out" "more") #f) (other))
    (((":output" "examples/expected/a.out") #t) (output "examples/expected/a.out"))
    ((("output=examples/expected/a.out") #t) (other))
    (((":output") #t) (other))
    (((":output" "examples/expected/a.out") #f) (other))
    ((() #t) (none))))

;; Paths, and whether each is written as an expected output.
(define output-path-cases
  '(("examples/expected/quick-start.out" yes) ("examples/expected/.out" no) ("examples/quick-start.out" no)
    ("examples/expected/../a.out" no) ("examples/expected/a.txt" no) ("examples/expected/sub/a.out" yes)))

;; Prose with an examples table, a second table of the same header, and
;; one of another.
(define table-prose
  '("Text."
    ""
    "| What | Example |"
    "|--|--|"
    "| x | y |"
    ""
    "| Example | What it shows |"
    "|---|---|"
    "| [`a.sps`](../examples/a.sps) | one |"
    "| [`b.sps`](../examples/c.sps) | two, \\| escaped |"
    "| `d.sps` | no link |"
    "Not a row."
    "| [`e.sps`](../examples/e.sps) | after the end |"))

(define table-expected
  '(("| [`a.sps`](../examples/a.sps) | one |"
     "| [`b.sps`](../examples/c.sps) | two, \\| escaped |"
     "| `d.sps` | no link |")
    (("a.sps" . "examples/a.sps") ("b.sps" . "examples/c.sps") ("d.sps" . #f))))

;; Prose with code spans, one across a line's end, one of two backticks.
(define code-prose '("A `curl-get` and `two" "lines` and ``a `b` c``." "No code."))
(define code-expected '((1 . "curl-get") (1 . "two\nlines") (2 . "a `b` c")))

;; Org prose with code and verbatim, and marks that open none.
(define org-code-prose '("Use =(curl)= and ~http-get~, not a=b=c nor = x =." "=a= b ~c~ x=y= z"))
(define org-code-expected '((1 . "(curl)") (1 . "http-get") (2 . "a") (2 . "c")))

;; A fragment's forms, and the names they bind, sorted.
(define bound-forms
  '((define (f a . rest) (let loop ((i 0) (j 1)) (lambda (k) k)))
    (let-values (((x y) (values 1 2))) x)
    (guard (e (#t e)) 1)
    (define g 1)
    (case-lambda ((m) m) ((m n) n))
    (list 'quoted (curl-get h))))
(define bound-expected '(a e f g i j k loop m n rest x y))

;; Heading texts, and their anchors by GitHub's rule.
(define anchor-texts
  '("The hatch: `(curl unsupported)`" "Multipart" "Multipart" "What's new \x2014; in 8.20.0?"
    "[Linked](x.md) *bold* _under_" "\xDC;n\xEF;code Stra\xDF;e" "a  b" "Requirements"))
(define anchor-expected
  '("the-hatch-curl-unsupported" "multipart" "multipart-1" "whats-new--in-8200"
    "linked-bold-_under_" "\xFC;n\xEF;code-stra\xDF;e" "a--b" "requirements"))

;; --- the pages -------------------------------------------------------------------

;; The pages: README.org, then every docs/*.md, by name.
(define page-names
  (guarded
   (lambda ()
     (cons "README.org"
           (map (lambda (f) (string-append "docs/" f))
                (list-sort string<?
                           (filter (lambda (f) (and (ends? f ".md") (file-regular? (string-append "docs/" f))))
                                   (directory-list "docs"))))))))

;; A page: its name, its directory, whether it is Org, its text, its
;; blocks, its links, and its prose, the lines outside its blocks.
(define-record-type page (fields name dir org? text blocks links prose))

;; read-page : String -> Page
(define (read-page name)
  (let* ((org? (ends? name ".org"))
         (text (slurp-bytes name))
         (read (if org? (org text) (markdown text))))
    (make-page name (if (starts? name "docs/") "docs" "") org? text (car read)
               (if org? (org-links (cdr read)) (markdown-links (cdr read))) (cdr read))))

(define pages
  (guarded (lambda () (if (list? page-names) (map read-page page-names) page-names))))

(define (pages-ok?) (and (list? pages) (pair? pages) (for-all page? pages)))

(define (the-pages) (if (pages-ok?) pages '()))

;; scheme-blocks : -> (Listof (Pair Page Block)) — every Scheme block of every page, with its page.
(define (scheme-blocks)
  (apply append
         (map (lambda (p)
                (map (lambda (b) (cons p b))
                     (filter (lambda (b) (string=? (block-language b) "scheme")) (page-blocks p))))
              (the-pages))))

;; where : (Pair Page Block) -> (List String Nat) — a block as a failure names it: its page and its line.
(define (where pb) (list (page-name (car pb)) (block-line (cdr pb))))

;; marked : (Pair Page Block) -> (U (List 'example String) (List 'fragment) (List 'none))
(define (marked pb) (marker (cdr pb) (page-org? (car pb))))

;; examples-named : -> (Listof (Pair (Pair Page Block) String)) — each block that names a well-formed example path, with it.
(define (examples-named)
  (fold-right (lambda (pb out)
                (let ((m (marked pb)))
                  (if (and (eq? (car m) 'example) (example-path? (cadr m))) (cons (cons pb (cadr m)) out) out)))
              '() (scheme-blocks)))

;; relative-links : Page -> (Listof (Pair String (U String #f)))
;; Each of the page's links to the checkout, with its path from the root,
;; or #f when it climbs out.
(define (relative-links p)
  (fold-right (lambda (target out)
                (let ((path (relative-path target (page-org? p))))
                  (if path (cons (cons target (resolve (page-dir p) path)) out) out)))
              '() (page-links p)))

;; index : -> (U Page #f) — docs/README.md, read.
(define (index) (find (lambda (p) (string=? (page-name p) "docs/README.md")) (the-pages)))

;; text-blocks : -> (Listof (Pair Page Block)) — every text block of every page, with its page.
(define (text-blocks)
  (apply append
         (map (lambda (p)
                (map (lambda (b) (cons p b))
                     (filter (lambda (b) (string=? (block-language b) "text")) (page-blocks p))))
              (the-pages))))

;; outputs-named : -> (Listof (Pair (Pair Page Block) String)) — each text block that names a well-formed output path, with it.
(define (outputs-named)
  (fold-right (lambda (pb out)
                (let ((m (output-of (cdr pb) (page-org? (car pb)))))
                  (if (and (eq? (car m) 'output) (output-path? (cadr m))) (cons (cons pb (cadr m)) out) out)))
              '() (text-blocks)))

;; language-named? : String Boolean -> Boolean
;; Whether a block of that language names one a rule reads: scheme, sh or
;; text; on an Org page, a src block of one, or a quote, a verse, a center
;; or a comment block.
(define (language-named? language org?)
  (or (and (member language '("scheme" "sh" "text")) #t)
      (and org? (member language '("#quote" "#verse" "#center" "#comment")) #t)))

;; The three public libraries.
(define public-libraries '((curl) (curl unsupported) (http-client)))

;; known-names : (U (List (Listof String) (Listof String) (Listof String) (Listof String)) (List 'raised String))
;; The names a page may write as chez-curl's: the three libraries' exports,
;; as library-exports lists them; the keys of the code's key lists, and url,
;; curl-request-with's; the reasons of each exported list whose name ends
;; -reasons; and the parts of the libraries' names.
(define known-names
  (guarded
   (lambda ()
     (let* ((exports (apply append
                            (map (lambda (l) (environment l) (map symbol->string (library-exports l)))
                                 public-libraries)))
            (reasons (apply append
                            (map (lambda (l)
                                   (apply append
                                          (map (lambda (n)
                                                 (let ((v (eval n (environment l))))
                                                   (if (and (list? v) (for-all symbol? v)) (map symbol->string v) '())))
                                               (filter (lambda (n) (ends? (symbol->string n) "-reasons"))
                                                       (library-exports l)))))
                                 public-libraries)))
            (keys (map symbol->string
                       (append '(url) request-keys session-keys call-keys port-keys group-keys retry-keys)))
            (parts (map symbol->string (apply append public-libraries))))
       (list exports keys reasons parts)))))

(define (known-names-ok?)
  (and (list? known-names) (= (length known-names) 4) (for-all list? known-names)
       (for-all pair? (list (car known-names) (cadr known-names) (caddr known-names)))))

;; known? : String -> Boolean — the name is one a page may write as chez-curl's.
(define (known? name)
  (and (known-names-ok?) (exists (lambda (names) (member name names)) known-names) #t))

;; condition-libraries : the libraries whose lists hold every reason.
(define condition-libraries '((curl private conditions) (http-client private conditions)))

;; code-reasons : (U (Listof String) (List 'raised String))
;; Every reason the code defines: each member of each list either library
;; exports whose name ends -reasons, as library-exports lists them.
(define code-reasons
  (guarded
   (lambda ()
     (apply append
            (map (lambda (l)
                   (apply append
                          (map (lambda (n)
                                 (let ((v (eval n (environment l))))
                                   (if (and (list? v) (for-all symbol? v)) (map symbol->string v) '())))
                               (filter (lambda (n) (ends? (symbol->string n) "-reasons")) (library-exports l)))))
                 condition-libraries)))))

;; code-reasons-ok? : -> Boolean
;; Whether code-reasons was read, and holds every reason of the two lists
;; this suite imports by name, so a reading that found fewer lists fails.
(define (code-reasons-ok?)
  (and (list? code-reasons) (for-all string? code-reasons)
       (for-all (lambda (r) (and (member (symbol->string r) code-reasons) #t))
                (append curl-request-error-reasons http-request-error-reasons))))

;; block-line-of : Block String -> Nat — the page's line of the block's first line that holds NAME as a name; the block's own line for none.
(define (block-line-of b name)
  (let loop ((ls (block-lines b)) (n (+ (block-line b) 1)))
    (cond ((null? ls) (block-line b))
          ((member name (name-tokens (latin-1->utf-8 (car ls)))) n)
          (else (loop (cdr ls) (+ n 1))))))

;; unknown-names : Page -> (Listof (List String Nat String))
;; Each name written as chez-curl's that no rule knows, in the page's
;; fragments, unless the fragment binds it, and in its prose's code, as
;; (page line name), each once.
(define (unknown-names p)
  (let* ((in-fragments
          (apply append
                 (map (lambda (b)
                        (let ((d (datums (latin-1->utf-8 (joined (block-lines b))))))
                          (if (not d)
                              '()
                              (let ((own (map symbol->string (bound d))))
                                (map (lambda (n) (list (page-name p) (block-line-of b n) n))
                                     (filter (lambda (n) (and (chez-curl-like? n) (not (known? n)) (not (member n own))))
                                             (map symbol->string (symbols-of d))))))))
                      (filter (lambda (b) (and (string=? (block-language b) "scheme")
                                               (eq? (car (marker b (page-org? p))) 'fragment)))
                              (page-blocks p)))))
         (in-code
          (apply append
                 (map (lambda (lc)
                        (map (lambda (n) (list (page-name p) (car lc) n))
                             (filter (lambda (n) (and (chez-curl-like? n) (not (known? n))))
                                     (name-tokens (latin-1->utf-8 (cdr lc))))))
                      (if (page-org? p) (org-code (page-prose p)) (markdown-code (page-prose p)))))))
    (let loop ((xs (append in-fragments in-code)) (out '()))
      (cond ((null? xs) (reverse out))
            ((member (car xs) out) (loop (cdr xs) out))
            (else (loop (cdr xs) (cons (car xs) out)))))))

;; anchor-of : Page String -> (U (Pair String String) #f)
;; A link's file, as a path from the root, and its anchor, when it has
;; one: # alone names the page itself; an Org link's file: is dropped, and
;; one with a ::search names none.
(define (anchor-of p target)
  (let* ((t (if (and (page-org? p) (starts? target "file:")) (substring target 5 (string-length target)) target))
         (hash (search t "#" 0)))
    (and hash (not (search t "::" 0))
         (let ((frag (substring t (+ hash 1) (string-length t)))
               (file (substring t 0 hash)))
           (cond ((string=? file "") (cons (page-name p) frag))
                 ((relative-path file #f) => (lambda (path) (let ((r (resolve (page-dir p) path))) (and r (cons r frag)))))
                 (else #f))))))

;; example-rows : (Listof String) -> (Listof (Pair String (U String #f)))
;; Each row of an examples table as the name its first cell's code gives
;; and the path from the root its one link names, from docs/; #f for a
;; cell that holds no one code span and one link.
(define (example-rows rows)
  (map (lambda (row)
         (let* ((cell (car (cells row)))
                (ranges (code-ranges cell))
                (names (map (lambda (r) (let ((k (run cell (car r) #\`))) (substring cell (+ (car r) k) (- (cdr r) k)))) ranges))
                (targets (markdown-links (list cell))))
           (cons (if (= (length names) 1) (car names) cell)
                 (and (= (length names) 1) (= (length targets) 1)
                      (let ((path (relative-path (car targets) #f))) (and path (resolve "docs" path)))))))
       rows))

;; --- the reader's tests --------------------------------------------------------------

(test-begin "docs")

(test-equal "the Markdown reader takes each fenced block, its fences of either kind and any length, its language in any case, its info and its lines, and closes it only on its own kind, as long or longer"
  markdown-expected
  (guarded (lambda () (map block-shown (car (markdown markdown-page))))))

(test-equal "the Org reader takes each src block, #+begin_src to #+end_src in any case, and nothing inside another block"
  org-expected
  (guarded (lambda () (map block-shown (car (org org-page))))))

(test-equal "the Markdown reader takes each inline link, image and reference definition of the prose, and none in code, a block or a comment"
  markdown-links-expected
  (guarded (lambda () (markdown-links (cdr (markdown markdown-links-page))))))

(test-equal "the Org reader takes each link of the prose, and none in a block"
  org-links-expected
  (guarded (lambda () (org-links (cdr (org org-links-page))))))

(test-equal "a link is resolved from its page's directory to a path of the checkout, and one with a scheme, on its own page, or out of the checkout names none"
  resolve-cases
  (guarded
   (lambda ()
     (map (lambda (c)
            (let* ((dir (car (car c))) (org? (cadr (car c))) (target (caddr (car c)))
                   (path (relative-path target org?))
                   (resolved (and path (resolve dir path))))
              (list (car c) (or resolved 'none))))
          resolve-cases))))

(test-equal "an example block is a run of its example's whole, consecutive lines, char for char, with a line that is not blank"
  run-cases
  (guarded (lambda () (map (lambda (c) (list (car c) (if (run-of? (car c) example-file) 'run 'no-run))) run-cases))))

(test-equal "a block's info says example and a path, or fragment, alone, and anything else says nothing"
  '((example "examples/a.sps") (fragment) (none) (none) (none) (example "") (fragment) (example "examples/a.sps") (none) (none))
  (guarded
   (lambda ()
     (map (lambda (c) (marker (make-block 1 "scheme" (car c) '() #t) (cadr c)))
          '((("example=examples/a.sps") #f) (("fragment") #f) (() #f) (("Fragment") #f)
            (("fragment" "extra") #f) (("example=") #f)
            ((":fragment") #t) ((":example" "examples/a.sps") #t) (("fragment") #t) ((":example") #t))))))

(test-equal "an example's path is examples/, a name, then .sps, with no . or .. segment"
  '(yes no no no no no yes)
  (guarded
   (lambda ()
     (map (lambda (p) (if (example-path? p) 'yes 'no))
          '("examples/quick-start.sps" "examples/.sps" "examples/../src/curl.sls" "src/a.sps"
            "examples/a.scm" "examples/./a.sps" "examples/sub/a.sps")))))

(test-equal "a fragment reads when every datum of it reads, and not when one does not"
  '((1 2 (a b)) unread unread)
  (guarded (lambda () (map (lambda (t) (or (datums t) 'unread)) '("1 2 (a b)" "(a b" "#<procedure>")))))

(test-equal "the stale phrases are found in any case, across a line's end, and near misses are not"
  stale-expected
  (guarded (lambda () (stale stale-text))))

(test-equal "a block names its language when it is scheme, sh or text, and on an Org page a quote, a verse, a center or a comment"
  language-cases
  (guarded (lambda () (map (lambda (c) (list (car c) (if (language-named? (car (car c)) (cadr (car c))) 'named 'unnamed)))
                           language-cases))))

(test-equal "a text block's info says nothing, or output and a path alone, and anything else says something else"
  output-cases
  (guarded (lambda () (map (lambda (c) (list (car c) (output-of (make-block 1 "text" (car (car c)) '() #t) (cadr (car c)))))
                           output-cases))))

(test-equal "an expected output's path is examples/expected/, a name, then .out, with no . or .. segment"
  output-path-cases
  (guarded (lambda () (map (lambda (c) (list (car c) (if (output-path? (car c)) 'yes 'no))) output-path-cases))))

(test-equal "the reader takes the first table whose first column is headed Example, its rows up to its end, and each row's code and link"
  table-expected
  (guarded (lambda () (let ((rows (table-rows table-prose "Example"))) (list rows (example-rows rows))))))

;; Prose with a Reason table, a table of another header, and a Reasons
;; table that a line with no bar ends.
(define reason-prose
  '("| Reason | What |" "|---|---|" "| `a` | one |" "| `b`, `c`: d | two |" ""
    "| What | Reason |" "|--|--|" "| `x` | y |" ""
    "| Reasons | Page |" "|:--|--|" "| `e` | f |" "Not a row." "| `g` | after |"))

(test-equal "the reader takes every table headed Reason or Reasons, and each code span of each row's first cell"
  '(("a") ("b" "c") ("e"))
  (guarded (lambda () (map first-cell-code (apply append (tables-headed reason-prose '("Reason" "Reasons")))))))

;; Text with run lines of examples, one across a line's end, and near misses.
(define run-line-text
  (string-append "scheme --libdirs src:x --program\nexamples/b.sps URL\n"
                 "scheme --libdirs src --program examples/a.sps http://h\n"
                 "scheme --libdirs src --program app.sps\n"
                 "chez --libdirs src --program examples/c.sps\n"
                 "scheme --program examples/d.sps --libdirs src\n"
                 "scheme --libdirs src --program examples/.sps\n"))

(test-equal "the reader takes each run line of an example, scheme --libdirs LIBDIRS --program examples/NAME.sps, a line's end inside one among it, and no other"
  '(("b" . "src:x") ("a" . "src"))
  (guarded (lambda () (run-lines-in run-line-text))))

(test-equal "the Markdown reader takes each code span of the prose, a line's end inside one among it, with its line"
  code-expected
  (guarded (lambda () (markdown-code code-prose))))

(test-equal "the Org reader takes each =code= and ~verbatim~ of the prose, with its line, and no mark that opens none"
  org-code-expected
  (guarded (lambda () (org-code org-code-prose))))

(test-equal "a code span's names are its runs of name chars, each without the . or : that ends it"
  '("curl-url-part" "URL" "port" "&curl-error" "http-get" "x:y" "http://a.b")
  (guarded (lambda () (name-tokens "(curl-url-part URL 'port) &curl-error, http-get. x:y http://a.b"))))

(test-equal "a fragment binds the names its defines, lambdas, lets, let-values, case-lambdas and guards bind, and no other"
  bound-expected
  (guarded (lambda ()
             (let loop ((ns (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) (bound bound-forms)))
                        (out '()))
               (cond ((null? ns) (reverse out))
                     ((and (pair? out) (eq? (car out) (car ns))) (loop (cdr ns) out))
                     (else (loop (cdr ns) (cons (car ns) out))))))))

(test-equal "a heading's anchor is GitHub's: a link read as its text, marks and punctuation dropped, in lower case, spaces made -, a repeat numbered"
  anchor-expected
  (guarded (lambda () (anchors anchor-texts))))

;; --- the pages are read ------------------------------------------------------------

(test-equal "README.org, docs/README.md and the other pages are read"
  'read
  (cond ((not (list? page-names)) page-names)
        ((not (pages-ok?)) pages)
        ((not (member "docs/README.md" page-names)) 'no-docs/README.md)
        ((< (length page-names) 3) (list 'too-few-pages page-names))
        ((not (known-names-ok?)) (list 'known-names known-names))
        (else 'read)))

(test-equal "the scan finds the pages' Scheme blocks, an example among them"
  'found
  (if (exists (lambda (pb) (eq? (car (marked pb)) 'example)) (scheme-blocks))
      'found
      (list 'no-example-block (map where (scheme-blocks)))))

;; --- the Scheme blocks -------------------------------------------------------------

(test-equal "every Scheme block says what it is: an example, naming a file under examples/, or a fragment"
  '()
  (noted "a Scheme block that says neither, or names no example, as (page line info):"
         (fold-right (lambda (pb out)
                       (let ((m (marked pb)))
                         (if (or (eq? (car m) 'none) (and (eq? (car m) 'example) (not (example-path? (cadr m)))))
                             (cons (append (where pb) (list (block-info (cdr pb)))) out)
                             out)))
                     '() (scheme-blocks))))

(test-equal "every example a Scheme block names is a file of the checkout"
  '()
  (noted "a Scheme block naming an example that is not there, as (page line path):"
         (fold-right (lambda (e out)
                       (if (file-regular? (cdr e)) out (cons (append (where (car e)) (list (cdr e))) out)))
                     '() (examples-named))))

(test-equal "every example block is a run of its example's whole, consecutive lines, byte for byte"
  '()
  (noted "an example block that is no run of its example's lines, as (page line path):"
         (fold-right (lambda (e out)
                       (if (and (file-regular? (cdr e))
                                (not (run-of? (block-lines (cdr (car e))) (file-lines (slurp-bytes (cdr e))))))
                           (cons (append (where (car e)) (list (cdr e))) out)
                           out))
                     '() (examples-named))))

(test-equal "every fragment reads as Scheme data, every datum, and holds one"
  '()
  (noted "a fragment that does not read, or holds no datum, as (page line):"
         (fold-right (lambda (pb out)
                       (if (eq? (car (marked pb)) 'fragment)
                           (let ((d (datums (latin-1->utf-8 (joined (block-lines (cdr pb)))))))
                             (if (and d (pair? d)) out (cons (where pb) out)))
                           out))
                     '() (scheme-blocks))))

(test-equal "every Scheme block ends: a fence of its own, or #+end_src, closes it"
  '()
  (noted "a Scheme block nothing closes, as (page line):"
         (map where (filter (lambda (pb) (not (block-closed? (cdr pb)))) (scheme-blocks)))))

;; --- the links -------------------------------------------------------------------

(test-equal "every relative link in README.org and docs/ names a file or directory of the checkout"
  '()
  (noted "a link to nothing in the checkout, as (page target):"
         (apply append
                (map (lambda (p)
                       (fold-right (lambda (l out)
                                     (if (and (cdr l) (file-exists? (if (string=? (cdr l) "") "." (cdr l))))
                                         out
                                         (cons (list (page-name p) (car l)) out)))
                                   '() (relative-links p)))
                     (the-pages)))))

(test-equal "no link in README.org or docs/ points into .plans/"
  '()
  (noted "a link into .plans/, as (page target):"
         (apply append
                (map (lambda (p)
                       (fold-right (lambda (l out)
                                     (if (and (cdr l) (into-plans? (cdr l))) (cons (list (page-name p) (car l)) out) out))
                                   '() (relative-links p)))
                     (the-pages)))))

(test-equal "no page's text names .plans/"
  '()
  (noted "a line naming .plans/, as (page line):"
         (apply append
                (map (lambda (p)
                       (let loop ((ls (text-lines (page-text p))) (n 1) (out '()))
                         (cond ((null? ls) (reverse out))
                               ((search (ascii-downcase (car ls)) ".plans/" 0)
                                (loop (cdr ls) (+ n 1) (cons (list (page-name p) n) out)))
                               (else (loop (cdr ls) (+ n 1) out)))))
                     (the-pages)))))

;; --- the index -------------------------------------------------------------------

(test-equal "docs/README.md links every other page of docs/"
  '()
  (noted "a page of docs/ the index does not link:"
         (let ((i (index)))
           (if (not i)
               '(no-index)
               (let ((linked (map cdr (relative-links i))))
                 (filter (lambda (n) (and (starts? n "docs/") (not (string=? n "docs/README.md"))
                                          (not (member n linked))))
                         page-names))))))

(test-equal "every page docs/README.md links is there"
  '()
  (noted "a page the index links that is not there, as its target:"
         (let ((i (index)))
           (if (not i)
               '(no-index)
               (map car (filter (lambda (l) (and (ends? (car (split (car l) #\#)) ".md")
                                                 (not (and (cdr l) (file-regular? (cdr l))))))
                                (relative-links i)))))))

(test-equal "README.org links docs/README.md"
  'linked
  (let ((readme (find (lambda (p) (string=? (page-name p) "README.org")) (the-pages))))
    (cond ((not readme) 'no-README.org)
          ((exists (lambda (l) (equal? (cdr l) "docs/README.md")) (relative-links readme)) 'linked)
          (else (list 'not-linked (page-links readme))))))

;; --- what no page says ---------------------------------------------------------------

(test-equal "no page says ADR- or ADR and a digit, not yet, unreleased, on main, TODO, slice and a digit, M and a digit then slice, or a date, in any case"
  '()
  (noted "a stale phrase, as (page line phrase):"
         (apply append
                (map (lambda (p) (map (lambda (s) (list (page-name p) (car s) (cdr s))) (stale (page-text p))))
                     (the-pages)))))

;; --- the languages and the outputs -------------------------------------------------

(test-equal "every block names its language: scheme, sh or text, and on an Org page a src block of one, or a quote, a verse, a center or a comment"
  '()
  (noted "a block that names no language a rule reads, as (page line language):"
         (apply append
                (map (lambda (p)
                       (map (lambda (b) (list (page-name p) (block-line b) (block-language b)))
                            (filter (lambda (b) (not (language-named? (block-language b) (page-org? p)))) (page-blocks p))))
                     (the-pages)))))

(test-equal "every text block says nothing more, or names an expected output under examples/expected/"
  '()
  (noted "a text block whose info names no expected output, as (page line info):"
         (fold-right (lambda (pb out)
                       (let ((m (output-of (cdr pb) (page-org? (car pb)))))
                         (if (or (eq? (car m) 'other) (and (eq? (car m) 'output) (not (output-path? (cadr m)))))
                             (cons (append (where pb) (list (block-info (cdr pb)))) out)
                             out)))
                     '() (text-blocks))))

(test-equal "every expected output a text block names is a file of the checkout"
  '()
  (noted "a text block naming an output that is not there, as (page line path):"
         (fold-right (lambda (e out)
                       (if (file-regular? (cdr e)) out (cons (append (where (car e)) (list (cdr e))) out)))
                     '() (outputs-named))))

(test-equal "every output block is a run of its expected file's whole, consecutive lines, byte for byte"
  '()
  (noted "an output block that is no run of its file's lines, as (page line path):"
         (fold-right (lambda (e out)
                       (if (and (file-regular? (cdr e))
                                (not (run-of? (block-lines (cdr (car e))) (file-lines (slurp-bytes (cdr e))))))
                           (cons (append (where (car e)) (list (cdr e))) out)
                           out))
                     '() (outputs-named))))

;; --- the names in code ---------------------------------------------------------------

(test-equal "every name written as chez-curl's, in a fragment or a prose code span, is an export, a key, a reason, a library's, or the fragment's own"
  '()
  (noted "a name written as chez-curl's that is none of them, as (page line name):"
         (apply append (map unknown-names (the-pages)))))

;; --- the anchors and the lists --------------------------------------------------------

(test-equal "every link's anchor names a heading of the page it links, by GitHub's rule"
  '()
  (noted "a link whose anchor names no heading of its page, as (page target):"
         (let ((cache '()))
           (apply append
                  (map (lambda (p)
                         (fold-right
                          (lambda (target out)
                            (let ((a (anchor-of p target)))
                              (if (and a (or (ends? (car a) ".md") (ends? (car a) ".org")) (file-regular? (car a)))
                                  (let ((known (or (let ((hit (assoc (car a) cache))) (and hit (cdr hit)))
                                                   (let ((as (page-anchors (car a)))) (set! cache (cons (cons (car a) as) cache)) as))))
                                    (if (member (cdr a) known) out (cons (list (page-name p) target) out)))
                                  out)))
                          '() (page-links p)))
                       (the-pages))))))

(test-equal "README.org links every page docs/README.md links"
  '()
  (noted "a page the index links and README.org does not:"
         (let ((i (index)) (readme (find (lambda (p) (string=? (page-name p) "README.org")) (the-pages))))
           (if (not (and i readme))
               '(no-index-or-readme)
               (let ((listed (map cdr (relative-links readme))))
                 (fold-right (lambda (l out)
                               (if (and (cdr l) (starts? (cdr l) "docs/") (ends? (cdr l) ".md")
                                        (not (member (cdr l) listed)) (not (member (cdr l) out)))
                                   (cons (cdr l) out)
                                   out))
                             '() (relative-links i)))))))

(test-equal "each row of the index's examples table links the example its code names"
  '()
  (noted "a row of the examples table whose link is not the example its code names, as (name path):"
         (let* ((i (index)) (rows (and i (table-rows (page-prose i) "Example"))))
           (if (not rows)
               '(no-examples-table)
               (fold-right (lambda (r out)
                             (if (equal? (cdr r) (string-append "examples/" (car r))) out (cons (list (car r) (cdr r)) out)))
                           '() (example-rows rows))))))

(test-equal "the index's examples table names every example, and nothing else"
  '()
  (noted "an example the table leaves out, or a name it gives that is no example:"
         (let* ((i (index)) (rows (and i (table-rows (page-prose i) "Example"))))
           (if (not rows)
               '(no-examples-table)
               (let ((names (map car (example-rows rows)))
                     (examples (filter (lambda (f) (and (ends? f ".sps") (file-regular? (string-append "examples/" f))))
                                       (directory-list "examples"))))
                 (append (map (lambda (e) (list 'left-out e)) (filter (lambda (e) (not (member e names))) examples))
                         (map (lambda (n) (list 'no-example n)) (filter (lambda (n) (not (member n examples))) names))))))))

;; --- run lines and reasons ------------------------------------------------------------

(test-equal "every run line of an example a page writes, in a block or a code span, names the library path that example's head comment names; the scan finds one of each"
  '(block code ())
  (let ((found (apply append (map (lambda (p) (map (lambda (r) (cons (page-name p) r)) (page-run-lines p)))
                                  (the-pages)))))
    (list (if (exists (lambda (f) (eq? (cadr f) 'block)) found) 'block 'no-block)
          (if (exists (lambda (f) (eq? (cadr f) 'code)) found) 'code 'no-code)
          (noted "a run line naming another library path than its example's head, as (page where line name libdirs head):"
                 (fold-right (lambda (f out)
                               (let ((head (head-libdirs (list-ref f 3))))
                                 (if (equal? head (list-ref f 4)) out (cons (append f (list head)) out))))
                             '() found)))))

(test-equal "every code span in the first column of a table headed Reason or Reasons is a reason a -reasons list of the code's holds; the scan finds some"
  '(checked ())
  (if (not (code-reasons-ok?))
      (list 'code-reasons code-reasons)
      (let* ((spans (apply append
                           (map (lambda (p)
                                  (if (page-org? p)
                                      '()
                                      (map (lambda (c) (list (page-name p) c))
                                           (apply append
                                                  (map first-cell-code
                                                       (apply append (tables-headed (page-prose p) '("Reason" "Reasons"))))))))
                                (the-pages))))
             (bad (filter (lambda (s) (not (member (cadr s) code-reasons))) spans)))
        (list (if (pair? spans) 'checked 'none-found)
              (noted "a reason table's first-column code that no -reasons list holds, as (page code):" bad)))))

(test-end "docs")

(exit (suite-exit-status runner))
