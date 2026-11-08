(import (chezscheme) (http-client))
(display (if (procedure? http-response?) "procedure" "value"))
(newline)
