(import (chezscheme) (curl))
(display (if (procedure? curl-error?) "procedure" "value"))
(newline)
