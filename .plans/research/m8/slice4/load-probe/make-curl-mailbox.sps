(import (chezscheme) (curl))
(display (if (procedure? make-curl-mailbox) "procedure" "value"))
(newline)
