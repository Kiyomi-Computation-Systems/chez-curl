(import (chezscheme) (curl))
(display (if (procedure? curl-response?) "procedure" "value"))
(newline)
