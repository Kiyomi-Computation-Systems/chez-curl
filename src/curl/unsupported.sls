#!r6rs
;;; (curl unsupported): the escape hatch (ADR-0009; the M4 plan, section
;;; 3.7). It attaches libcurl options chez-curl does not wrap to a request,
;;; by name, and the engine sets them last, after every option chez-curl
;;; sets itself. It is unsupported surface: it carries no compatibility
;;; promise, and an option set through it can change behaviour chez-curl
;;; does not test.
;;;
;;; Each option is checked as it is attached, against the loaded libcurl's
;;; own table, and the request keeps a copy of its value, the one checked:
;;;   - its name must be one the loaded libcurl knows;
;;;   - its type must be long, enumerated values, off_t, a string, a string
;;;     list or a blob, which hand libcurl no address of the caller's: no
;;;     object, callback pointer or function;
;;;   - its value must fit that type: an exact integer a C long holds, one a
;;;     curl_off_t holds, a string, a list of strings, or a bytevector;
;;;   - no string, nor any string of a list, may hold U+0000, CR or LF;
;;;   - it must be neither an option chez-curl owns nor an owned setting's
;;;     twin, compared by id, so an alias is refused too;
;;;   - the request must not carry it already, by any of its names.
;;;
;;; No (curl ...) library may import this one, nor any (http-client ...)
;;; library: make check-seam holds both (ADR-0007, ADR-0009). The procedure
;;; is defined in (curl private transfer), which exports it too, beside the
;;; request's constructor it needs; tests/test-unsupported.sps holds that no
;;; export of (curl) is bound to it, under any name.
(library (curl unsupported)
  (export curl-request-with-options)
  (import (curl private require-threaded)
          (only (curl private transfer) curl-request-with-options))

  ;; curl-request-with-options : Request (Listof (Pairof String Any)) -> Request
  ;; (curl-request-with-options REQUEST ((NAME . VALUE) ...)): a new
  ;; request, REQUEST's fields and the options it carries kept, with each
  ;; option attached after them, in order. NAME is the option's name
  ;; without CURLOPT_, in any case, as curl_easy_option_by_name reads it.
  ;; VALUE is an exact integer for a long, an enumerated-value or an off_t
  ;; option, a string for a string one, a list of strings for a string
  ;; list, and a bytevector for a blob, which libcurl copies. A refusal of a
  ;; name or a string is a &curl-request-error, field options, naming the
  ;; option, with one of the reasons embedded-nul, unknown-option,
  ;; owned-option, unsupported-type, repeated-option or line-break; a value
  ;; of the wrong shape or range is an assertion violation. curl-request-with
  ;; keeps the options a request carries. A libcurl that refuses a value as
  ;; the transfer is set up fails the transfer, setopt-failed, naming the
  ;; option.
  )
