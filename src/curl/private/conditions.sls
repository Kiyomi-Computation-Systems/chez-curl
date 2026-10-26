#!r6rs
;;; (curl private conditions): chez-curl's condition types. Every one is a
;;; &curl-error, so a caller can catch the family or one member.
;;;
;;;   &curl-error                 the base, under &error
;;;   &curl-library-unavailable   libcurl was refused (ADR-0002, ADR-0003)
;;;   &curl-wrong-thread          an engine-owned handle used from another
;;;                               thread (ADR-0012)
;;;   &curl-embedded-nul          a string C would read short: it holds
;;;                               U+0000 (M2 plan, section 3.3)
;;;   &curl-url-error             a URL refused: by libcurl's URL API, or by
;;;                               chez-curl's own checks (ADR-0008)
;;;   &curl-request-error         a request's field refused, before anything
;;;                               native is made (M2 plan, section 5.3)
;;;   &curl-transfer-error        a transfer that failed: libcurl's code and
;;;                               texts, and what the write callable recorded
;;;                               (M2 plan, sections 3.7 and 5.3), or one
;;;                               cancelled or stopped (M3 plan, section 3.4)
;;;   &curl-engine-error          an engine that has stopped, or failed, and
;;;                               the condition it failed with (M3 plan,
;;;                               sections 3.4 and 3.7)
;;;
;;; A raise may compound one with &who, &message and &irritants, so that
;;; the default handler prints readable text. Tests assert the reason symbol
;;; and the fields, never that text.
(library (curl private conditions)
  (export &curl-error make-curl-error curl-error?

          &curl-library-unavailable make-curl-library-unavailable
          curl-library-unavailable?
          curl-library-unavailable-reason curl-library-unavailable-path
          curl-library-unavailable-source curl-library-unavailable-detail
          curl-library-unavailable-candidates
          curl-library-unavailable-library
          curl-library-unavailable-reasons

          &curl-wrong-thread make-curl-wrong-thread curl-wrong-thread?
          curl-wrong-thread-who curl-wrong-thread-expected
          curl-wrong-thread-actual

          &curl-embedded-nul make-curl-embedded-nul curl-embedded-nul?
          curl-embedded-nul-string

          &curl-url-error make-curl-url-error curl-url-error?
          curl-url-error-input curl-url-error-reason curl-url-error-code
          curl-url-error-message curl-url-code-reason

          &curl-request-error make-curl-request-error curl-request-error?
          curl-request-error-field curl-request-error-value curl-request-error-reason
          curl-request-error-reasons

          &curl-transfer-error make-curl-transfer-error curl-transfer-error?
          curl-transfer-error-reason curl-transfer-error-code curl-transfer-error-option
          curl-transfer-error-strerror curl-transfer-error-error-buffer
          curl-transfer-error-recorded curl-transfer-error-reasons

          &curl-engine-error make-curl-engine-error curl-engine-error?
          curl-engine-error-reason curl-engine-error-condition curl-engine-error-reasons)
  (import (curl private require-threaded)
          (rnrs)
          (curl private libcurl-info)
          (curl private constants))

  ;; make-curl-error : -> &curl-error
  ;; curl-error? : Any -> Boolean
  (define-condition-type &curl-error &error
    make-curl-error curl-error?)

  ;; --- &curl-library-unavailable ---------------------------------------------

  ;; curl-library-unavailable-reasons : (Listof Symbol)
  ;; Why a libcurl was refused. They are the contract: tests and CI assert
  ;; these symbols, never the message (ADR-0002, ADR-0003).
  ;;
  ;;   invalid-override  CHEZ_CURL_LIBCURL is set, but not to an absolute path
  ;;   not-found         no candidate exists
  ;;   load-failed       the loader refused the chosen path
  ;;   below-floor       the library is older than 7.85.0
  ;;   no-ssl            the library lacks CURL_VERSION_SSL
  ;;   missing-api       the options API or the header API is built out
  (define curl-library-unavailable-reasons
    '(invalid-override not-found load-failed below-floor no-ssl missing-api))

  ;; The fields:
  ;;
  ;;   reason      one of curl-library-unavailable-reasons
  ;;   path        (U String #f): the library refused, #f when none was chosen
  ;;   source      (U Symbol #f): where the path came from, one of
  ;;               (curl private discovery)'s libcurl-sources, or #f
  ;;   detail      by reason: the override's value (invalid-override), the
  ;;               loader's message (load-failed), the version string
  ;;               (below-floor, no-ssl), the API's C name (missing-api),
  ;;               #f (not-found)
  ;;   candidates  (Listof String): every path checked, in order (not-found)
  ;;   library     (U Libcurl-Info #f): what the library reported, for a
  ;;               refusal made after curl_version_info was read
  ;;               (below-floor, no-ssl, missing-api for any entry point
  ;;               but curl_version_info, and load-failed from
  ;;               curl_global_init or curl_easy_init); #f before that
  ;;               (ADR-0002, decision 4)
  (define-condition-type &curl-library-unavailable &curl-error
    unchecked-make-curl-library-unavailable curl-library-unavailable?
    (reason curl-library-unavailable-reason)
    (path curl-library-unavailable-path)
    (source curl-library-unavailable-source)
    (detail curl-library-unavailable-detail)
    (candidates curl-library-unavailable-candidates)
    (library curl-library-unavailable-library))

  ;; make-curl-library-unavailable : Symbol (U String #f) (U Symbol #f) Any
  ;;                                 (Listof String) (U Libcurl-Info #f)
  ;;                                 -> &curl-library-unavailable
  ;; Refuses a REASON that is not one of the six, and a LIBRARY that is
  ;; neither a libcurl-info nor #f, with an assertion violation, so a
  ;; misspelt reason cannot reach a caller who tests for the right one.
  (define (make-curl-library-unavailable reason path source detail candidates library)
    (unless (memq reason curl-library-unavailable-reasons)
      (assertion-violation 'make-curl-library-unavailable
                           "not a reason chez-curl refuses a libcurl for"
                           reason))
    (unless (or (not library) (libcurl-info? library))
      (assertion-violation 'make-curl-library-unavailable
                           "a refusal's library is a libcurl-info or #f"
                           library))
    (unchecked-make-curl-library-unavailable reason path source detail candidates
                                             library))

  ;; curl-library-unavailable? : Any -> Boolean
  ;; curl-library-unavailable-reason : &curl-library-unavailable -> Symbol
  ;; curl-library-unavailable-path : &curl-library-unavailable -> (U String #f)
  ;; curl-library-unavailable-source : &curl-library-unavailable -> (U Symbol #f)
  ;; curl-library-unavailable-detail : &curl-library-unavailable -> Any
  ;; curl-library-unavailable-candidates : &curl-library-unavailable
  ;;                                       -> (Listof String)
  ;; curl-library-unavailable-library : &curl-library-unavailable
  ;;                                    -> (U Libcurl-Info #f)

  ;; --- &curl-wrong-thread ----------------------------------------------------

  ;; make-curl-wrong-thread : Symbol Integer Integer -> &curl-wrong-thread
  ;; curl-wrong-thread? : Any -> Boolean
  ;; curl-wrong-thread-who : &curl-wrong-thread -> Symbol
  ;; curl-wrong-thread-expected : &curl-wrong-thread -> Integer
  ;; curl-wrong-thread-actual : &curl-wrong-thread -> Integer
  ;; An operation on an engine-owned handle ran on another thread: WHO is the
  ;; operation, EXPECTED the owner's get-thread-id, ACTUAL the caller's
  ;; (ADR-0012).
  (define-condition-type &curl-wrong-thread &curl-error
    make-curl-wrong-thread curl-wrong-thread?
    (who curl-wrong-thread-who)
    (expected curl-wrong-thread-expected)
    (actual curl-wrong-thread-actual))

  ;; --- &curl-embedded-nul ----------------------------------------------------

  ;; make-curl-embedded-nul : String -> &curl-embedded-nul
  ;; curl-embedded-nul? : Any -> Boolean
  ;; curl-embedded-nul-string : &curl-embedded-nul -> String
  ;; STRING holds U+0000, so C, which reads a string to its first NUL, would
  ;; read it short. Refused before anything is allocated (M2 plan, section
  ;; 3.3).
  (define-condition-type &curl-embedded-nul &curl-error
    make-curl-embedded-nul curl-embedded-nul?
    (string curl-embedded-nul-string))

  ;; --- &curl-url-error ---------------------------------------------------------

  ;; The fields:
  ;;
  ;;   input    the string refused
  ;;   reason   (U Symbol #f): for libcurl's refusal, its CURLUcode's name in
  ;;            (curl private constants)'s curlue-codes, ok and the floor's
  ;;            others, or #f for a code that list lacks, a later libcurl's;
  ;;            for chez-curl's own, one of its two reasons:
  ;;              scheme-not-http  the URL parsed, but its scheme is neither
  ;;                               http nor https (ADR-0008, decision 2)
  ;;              embedded-nul     the input holds U+0000, which libcurl
  ;;                               would read as its end
  ;;   code     (U Integer #f): libcurl's CURLUcode, or #f for chez-curl's
  ;;            own refusals
  ;;   message  (U String #f): curl_url_strerror's text, or chez-curl's own
  ;;
  ;; Tests assert the reason and the code, never the message.
  ;;
  ;; make-curl-url-error : Any Any Any Any -> &curl-url-error
  ;; curl-url-error? : Any -> Boolean
  ;; curl-url-error-input : &curl-url-error -> String
  ;; curl-url-error-reason : &curl-url-error -> (U Symbol #f)
  ;; curl-url-error-code : &curl-url-error -> (U Integer #f)
  ;; curl-url-error-message : &curl-url-error -> (U String #f)
  ;; The constructor checks nothing, so building a refusal never raises: a
  ;; code a later libcurl answers must still reach the caller.
  (define-condition-type &curl-url-error &curl-error
    make-curl-url-error curl-url-error?
    (input curl-url-error-input)
    (reason curl-url-error-reason)
    (code curl-url-error-code)
    (message curl-url-error-message))

  ;; --- &curl-request-error -------------------------------------------------------

  ;; curl-request-error-reasons : (Listof Symbol)
  ;; Why a request's field is refused (M2 plan, section 5.3):
  ;;
  ;;   embedded-nul  a value holds U+0000, which C would read as its end
  ;;   line-break    a value holds CR or LF, which would end its header line
  ;;   not-latin-1   a value holds a char above U+00FF, which has no byte:
  ;;                 header strings are Latin-1, both ways (ADR-0001,
  ;;                 amended 2026-10-23)
  ;;   not-a-token   a header name is empty, or holds a char that is no
  ;;                 tchar (RFC 9110, section 5.6.2)
  ;;   surrounding-whitespace
  ;;                 a value's first or last char is SP, HTAB, VT or FF:
  ;;                 RFC 9110 field values have none, and libcurl drops a
  ;;                 value of whitespace alone, and trims what it reads
  ;;   duplicates-field
  ;;                 a header named User-Agent, in any case, beside a user
  ;;                 agent given as its own field: libcurl lets the header
  ;;                 win; or a second header named Host, in any case:
  ;;                 libcurl sends only the first
  ;;   framing-header
  ;;                 a header named Content-Length or Transfer-Encoding, in
  ;;                 any case: libcurl frames the message, and M2 sends no
  ;;                 body, so a server would wait for one
  ;;   owned-option  an option the test seam may not set: chez-curl sets it,
  ;;                 a request field sets it, or it is the twin of one that
  ;;                 does, compared by id (ADR-0009, amended 2026-10-23)
  ;;   unsupported-type
  ;;                 an option the test seam may not set for its type: only
  ;;                 long, enumerated values and off_t, so no address passes
  ;;
  ;; A value is scanned left to right, and its first offending char decides;
  ;; only when none offends are its ends checked.
  (define curl-request-error-reasons
    '(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field
      framing-header owned-option unsupported-type))

  ;; The fields:
  ;;
  ;;   field   Symbol: the field refused, header-name, header-value,
  ;;           user-agent, ca-file, or options, the test seam's
  ;;   value   the string refused, whole, or the option's name
  ;;   reason  one of curl-request-error-reasons
  (define-condition-type &curl-request-error &curl-error
    unchecked-make-curl-request-error curl-request-error?
    (field curl-request-error-field)
    (value curl-request-error-value)
    (reason curl-request-error-reason))

  ;; make-curl-request-error : Symbol Any Symbol -> &curl-request-error
  ;; Refuses a REASON that is not one of the eight with an assertion
  ;; violation, as make-curl-library-unavailable does.
  (define (make-curl-request-error field value reason)
    (unless (memq reason curl-request-error-reasons)
      (assertion-violation 'make-curl-request-error
                           "not a reason chez-curl refuses a request's field for"
                           reason))
    (unchecked-make-curl-request-error field value reason))

  ;; curl-request-error? : Any -> Boolean
  ;; curl-request-error-field : &curl-request-error -> Symbol
  ;; curl-request-error-value : &curl-request-error -> Any
  ;; curl-request-error-reason : &curl-request-error -> Symbol

  ;; --- &curl-transfer-error ------------------------------------------------------

  ;; curl-transfer-error-reasons : (Listof Symbol)
  ;; Why a transfer failed (M2 plan, section 5.3; M3 plan, section 3.4):
  ;;
  ;;   perform-failed   the transfer ended with a CURLcode, which
  ;;                    curl_multi_info_read gave the engine, and the write
  ;;                    callable recorded nothing
  ;;   body-limit       the callable refused a chunk past the body limit
  ;;   callback-raised  something raised inside the callable, which recorded it
  ;;   setopt-failed    curl_easy_setopt answered a code, for the option named
  ;;   unknown-option   the loaded libcurl does not know the option named
  ;;   no-handle        curl_easy_init answered NULL
  ;;   cancelled        the caller cancelled it before it ended (M3 plan,
  ;;                    section 3.5)
  ;;   stopped          its engine stopped before it ended
  (define curl-transfer-error-reasons
    '(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle
      cancelled stopped))

  ;; The fields:
  ;;
  ;;   reason        one of curl-transfer-error-reasons
  ;;   code          (U Integer #f): the CURLcode, a number, since codes
  ;;                 past the floor's have no name; #f when libcurl answered
  ;;                 none (unknown-option, no-handle, cancelled, stopped)
  ;;   option        (U String #f): the option's name, without CURLOPT_
  ;;   strerror      (U String #f): curl_easy_strerror's text for the code
  ;;   error-buffer  (U String #f): CURLOPT_ERRORBUFFER's text, read as
  ;;                 Latin-1, or #f when it is empty
  ;;   recorded      what the callable recorded: the raised object for
  ;;                 callback-raised, else #f
  ;;
  ;; Tests assert the reason, the code, the option and the recorded object,
  ;; never the texts.
  (define-condition-type &curl-transfer-error &curl-error
    unchecked-make-curl-transfer-error curl-transfer-error?
    (reason curl-transfer-error-reason)
    (code curl-transfer-error-code)
    (option curl-transfer-error-option)
    (strerror curl-transfer-error-strerror)
    (error-buffer curl-transfer-error-error-buffer)
    (recorded curl-transfer-error-recorded))

  ;; make-curl-transfer-error : Symbol (U Integer #f) (U String #f) (U String #f)
  ;;                            (U String #f) Any -> &curl-transfer-error
  ;; Refuses a REASON that is not one of the eight with an assertion
  ;; violation. It checks nothing else, so a code a later libcurl answers
  ;; still reaches the caller.
  (define (make-curl-transfer-error reason code option strerror error-buffer recorded)
    (unless (memq reason curl-transfer-error-reasons)
      (assertion-violation 'make-curl-transfer-error
                           "not a reason a chez-curl transfer fails for"
                           reason))
    (unchecked-make-curl-transfer-error reason code option strerror error-buffer recorded))

  ;; curl-transfer-error? : Any -> Boolean
  ;; curl-transfer-error-reason : &curl-transfer-error -> Symbol
  ;; curl-transfer-error-code : &curl-transfer-error -> (U Integer #f)
  ;; curl-transfer-error-option : &curl-transfer-error -> (U String #f)
  ;; curl-transfer-error-strerror : &curl-transfer-error -> (U String #f)
  ;; curl-transfer-error-error-buffer : &curl-transfer-error -> (U String #f)
  ;; curl-transfer-error-recorded : &curl-transfer-error -> Any

  ;; --- &curl-engine-error -------------------------------------------------------

  ;; curl-engine-error-reasons : (Listof Symbol)
  ;; Why an engine refused a message, or failed a transfer (M3 plan, sections
  ;; 3.4 and 3.7):
  ;;
  ;;   stopped  the engine was stopped: a submit after its stop
  ;;   failed   something raised inside the engine's loop: every transfer it
  ;;            held, and a later submit, carries the condition
  (define curl-engine-error-reasons '(stopped failed))

  ;; The fields:
  ;;
  ;;   reason     one of curl-engine-error-reasons
  ;;   condition  what the loop raised, for failed; #f for stopped
  ;;
  ;; Tests assert the reason and the condition, never the message.
  (define-condition-type &curl-engine-error &curl-error
    unchecked-make-curl-engine-error curl-engine-error?
    (reason curl-engine-error-reason)
    (condition curl-engine-error-condition))

  ;; make-curl-engine-error : Symbol Any -> &curl-engine-error
  ;; Refuses a REASON that is not one of the two with an assertion violation.
  (define (make-curl-engine-error reason condition)
    (unless (memq reason curl-engine-error-reasons)
      (assertion-violation 'make-curl-engine-error
                           "not a reason a chez-curl engine refuses or fails for"
                           reason))
    (unchecked-make-curl-engine-error reason condition))

  ;; curl-engine-error? : Any -> Boolean
  ;; curl-engine-error-reason : &curl-engine-error -> Symbol
  ;; curl-engine-error-condition : &curl-engine-error -> Any

  ;; curl-url-code-reason : Any -> (U Symbol #f)
  ;; CODE's name in curlue-codes, or #f for anything else: a later
  ;; libcurl's code, or no code at all. It never raises.
  (define (curl-url-code-reason code)
    (let loop ((codes curlue-codes))
      (cond ((null? codes) #f)
            ((eqv? (cdar codes) code) (caar codes))
            (else (loop (cdr codes)))))))
