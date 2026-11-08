(make-curl-request "https://example.com/" 'credentials '(basic "user" "pass"))
(make-curl-request "https://example.com/" 'credentials '(digest "user" "pass"))
(make-curl-request "https://example.com/" 'credentials '(bearer "token"))
