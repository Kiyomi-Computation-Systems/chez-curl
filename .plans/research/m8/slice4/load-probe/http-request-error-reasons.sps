(import (chezscheme) (http-client))
(display (if (procedure? http-request-error-reasons) "procedure" "value"))
(newline)
