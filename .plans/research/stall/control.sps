;;; M3 slice 3: part of the Mac probe's control (ADR-0019, amended
;;; 2026-10-25). Run under the stand-in by run.sh: prints which preload
;;; variable reached this Chez, so a probe can tell a variable dropped on
;;; the way, by SIP or a wrapper, from a stand-in that loaded and stalled
;;; nothing. gai-control.c makes the positive control's call.
(import (chezscheme))

(printf "control: DYLD_INSERT_LIBRARIES ~s, LD_PRELOAD ~s\n"
        (getenv "DYLD_INSERT_LIBRARIES") (getenv "LD_PRELOAD"))
