(import (chezscheme) (curl))
(display (if (procedure? make-curl-request) "procedure" "value"))
(newline)
