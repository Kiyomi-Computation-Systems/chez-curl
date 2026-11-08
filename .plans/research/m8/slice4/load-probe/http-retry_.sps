(import (chezscheme) (http-client))
(display (if (procedure? http-retry?) "procedure" "value"))
(newline)
