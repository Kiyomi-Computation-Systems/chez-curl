(import (chezscheme) (curl))
(display (if (procedure? curl-request-error-reasons) "procedure" "value"))
(newline)
