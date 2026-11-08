(import (chezscheme) (curl unsupported))
(display (if (procedure? curl-request-with-options) "procedure" "value"))
(newline)
