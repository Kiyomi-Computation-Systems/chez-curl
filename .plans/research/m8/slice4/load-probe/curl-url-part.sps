(import (chezscheme) (curl))
(display (if (procedure? curl-url-part) "procedure" "value"))
(newline)
