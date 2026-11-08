(import (chezscheme) (http-client))
(display (if (procedure? http-error?) "procedure" "value"))
(newline)
