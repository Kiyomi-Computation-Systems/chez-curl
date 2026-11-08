(import (chezscheme) (http-client))
(display (if (procedure? http-get) "procedure" "value"))
(newline)
