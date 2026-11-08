(import (chezscheme) (curl))
(display (if (procedure? libcurl-info?) "procedure" "value"))
(newline)
