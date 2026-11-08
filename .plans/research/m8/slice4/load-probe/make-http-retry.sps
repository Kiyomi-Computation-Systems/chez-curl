(import (chezscheme) (http-client))
(display (if (procedure? make-http-retry) "procedure" "value"))
(newline)
