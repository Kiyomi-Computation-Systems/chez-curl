#!r6rs
;; PURE. Imports no library that loads a shared object.
(library (site pages)
  (export pages page-file-name)
  (import (rnrs))

  ;; pages : (Listof (Pairof String String))
  ;; The nav's single source of order and labels: each docs/ file and its
  ;; label, the home page first, then docs/README.md's "The pages" list, in
  ;; its order and under its labels. tests/check-site.sps asserts the file
  ;; set here equals docs/*.md, and the rest equals that list.
  (define pages
    '(("README.md"                . "Home")
      ("quickstart.md"            . "Quick start")
      ("high-level.md"            . "The high level")
      ("headers-and-json.md"      . "Headers and JSON")
      ("redirects-and-retries.md" . "Redirects and retries")
      ("auth-and-proxies.md"      . "Auth and proxies")
      ("cookies.md"               . "Cookies")
      ("http-version.md"          . "Choosing the HTTP version")
      ("streams.md"               . "Streams")
      ("groups.md"                . "Groups")
      ("low-level.md"             . "The low level")
      ("errors.md"                . "Errors")
      ("tls-and-environment.md"   . "TLS and the environment")
      ("libcurl-versions.md"      . "What varies by libcurl")
      ("hatch.md"                 . "The hatch")
      ("reference.md"             . "Reference")))

  ;; page-file-name : String -> String
  ;; The file a page is written to: README.md, the home page, as index.html,
  ;; and any other page.md as page.html.  tests/check-site.sps holds every
  ;; relative link to these names.
  (define (page-file-name name)
    (if (string=? name "README.md")
        "index.html"
        (string-append (substring name 0 (- (string-length name) 3)) ".html"))))
