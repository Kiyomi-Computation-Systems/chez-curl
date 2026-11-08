#!r6rs
;;; (http-client private conditions): the high level's conditions (the M5
;;; plan, section 3.3). (http-client) exports the types, their predicates
;;; and their accessors; the constructors are this library's alone.
;;;
;;;   &http-error           the base of the high level's own, under (curl)'s
;;;                         &curl-error, so a caller who catches that
;;;                         catches these too
;;;   &http-request-error   a key or a value the high level checks itself,
;;;                         refused: field, value and reason
;;;   &http-redirect-error  a redirect the rules refuse to follow: reason,
;;;                         the response that named it, and its Location
;;;   &http-timeout         a call's timeout-ms passed: the bound, in ms
;;;   &http-group-error     a request group's call refused or ended by the
;;;                         group: reason, wrong-thread, closed or cancelled
;;;   &http-exchange        not an error: the context compounded onto
;;;                         whatever a call raises, under &condition, so a
;;;                         low-level failure that carries it is still no
;;;                         http-error?
;;;
;;; Tests assert the type, the reason and the fields, never a message.
(library (http-client private conditions)
  (export &http-error make-http-error http-error?
          &http-request-error make-http-request-error http-request-error?
          http-request-error-field http-request-error-value http-request-error-reason
          http-request-error-reasons
          &http-redirect-error make-http-redirect-error http-redirect-error?
          http-redirect-error-reason http-redirect-error-response http-redirect-error-location
          http-redirect-error-reasons
          &http-timeout make-http-timeout http-timeout? http-timeout-timeout-ms
          &http-group-error make-http-group-error http-group-error? http-group-error-reason
          http-group-error-reasons
          &http-exchange make-http-exchange http-exchange? http-exchange-method
          http-exchange-url http-exchange-history http-exchange-transfers
          kind-of shown-value shown-key checked-accessor)
  (import (curl)
          (rnrs))

  ;; --- a caller's value, as a refusal names it -------------------------------------

  ;; kind-of : Any -> Symbol
  ;; X's kind: string, list, number, boolean, char, symbol, bytevector,
  ;; vector, procedure or other. Pure.
  (define (kind-of x)
    (cond ((string? x) 'string)
          ((or (pair? x) (null? x)) 'list)
          ((number? x) 'number)
          ((boolean? x) 'boolean)
          ((char? x) 'char)
          ((symbol? x) 'symbol)
          ((bytevector? x) 'bytevector)
          ((vector? x) 'vector)
          ((procedure? x) 'procedure)
          (else 'other)))

  ;; shown-atom? : Any -> Boolean
  ;; Whether X is a symbol, a number, a boolean, a char or (): none holds a
  ;; URL, a header, credentials or a body.
  (define (shown-atom? x)
    (or (symbol? x) (number? x) (boolean? x) (char? x) (null? x)))

  ;; shown-value : Any -> Any
  ;; X as a refusal or an assertion names a caller's value where another
  ;; belongs: itself when it is shown-atom?, or a proper list of them, a
  ;; policy's statuses or methods; else (kind K), K its kind-of, never the
  ;; value: a string, or a list holding one, can be a URL, a header,
  ;; credentials or a body. A proxy URL or a credentials list handed where
  ;; a key or another value belongs was printed whole (M7 slice 3's
  ;; review). Pure.
  (define (shown-value x)
    (if (or (shown-atom? x) (and (list? x) (for-all shown-atom? x)))
        x
        (list 'kind (kind-of x))))

  ;; shown-key : Any -> Any
  ;; X as a key's refusal names it: itself when it is a symbol, as a key is;
  ;; else (kind K), K its kind-of, a number's among them. Pure.
  (define (shown-key x)
    (if (symbol? x) x (list 'kind (kind-of x))))

  ;; checked-accessor : Symbol (Any -> Boolean) String (Any -> Any) -> (Any -> Any)
  ;; ACCESSOR, a record's or a condition type's, for WHO: called on what
  ;; PREDICATE holds; anything else an assertion violation from WHO, "not
  ;; WHAT", naming it by shown-value, never the value. Chez's own check
  ;; named what it refused, so (curl-request-url "http://u:PW@h/") printed
  ;; the password (ADR-0036, amended 2026-11-03).
  (define (checked-accessor who predicate what accessor)
    (lambda (x)
      (unless (predicate x)
        (assertion-violation who (string-append "not " what) (shown-value x)))
      (accessor x)))

  ;; make-http-error : -> &http-error
  ;; http-error? : Any -> Boolean
  (define-condition-type &http-error &curl-error
    make-http-error http-error?)

  ;; http-request-error-reasons : (Listof Symbol)
  ;; Why the high level refuses a key or a value of its own (the M5 plan,
  ;; section 3.2). Every other value is checked by the low level, whose
  ;; &curl-request-error, or assertion violation, passes through.
  ;;
  ;;   unknown-key           a key make-http-session, or a call, does not take
  ;;   repeated-key          a key given twice to one call
  ;;   missing-value         a key given last, with no value after it
  ;;   body-and-form         a call given both body and form
  ;;   multipart-beside-body a call given multipart beside body or form
  ;;   body-not-allowed      a body, a form or a multipart body with get or
  ;;                         head, which send none
  ;;   not-a-body            a body that is neither a bytevector nor a string
  ;;   not-name-value-pairs  a form or params that is not a list of pairs,
  ;;                         each of a name and a value, both strings
  ;;   not-a-redirect-count  a redirects that is neither an exact natural
  ;;                         nor #f
  ;;   not-a-boolean         an allow-downgrade, or a policy's jitter, that
  ;;                         is neither #t nor #f
  ;;   not-a-retry-policy    a retry that is neither a policy, made by
  ;;                         make-http-retry, nor #f
  ;;   not-an-attempt-count  a policy's attempts that is no exact integer of
  ;;                         1 or more
  ;;   not-a-backoff         a policy's backoff-ms or max-backoff-ms that is
  ;;                         no exact natural
  ;;   not-a-status-list     a policy's statuses that is no list of exact
  ;;                         integers from 400 to 599
  ;;   not-a-method-list     a policy's methods that is no list of get, head,
  ;;                         post, put, patch and delete
  ;;   not-a-limit           a request group's or http-parallel's limit that
  ;;                         is neither an exact positive integer nor #f
  ;;   stream-in-group       a producer as the body of a group's call, go's or
  ;;                         http-parallel's: a group's calls share one thread,
  ;;                         which a producer's wait would hold (the M6 plan,
  ;;                         sections 3.6 and 9)
  ;;   body-length-mismatch  a producer's piece that would take its body past
  ;;                         its body-length, refused before any of it is put,
  ;;                         once the transfer is cancelled (ADR-0031, amended)
  (define http-request-error-reasons
    '(unknown-key repeated-key missing-value body-and-form multipart-beside-body
      body-not-allowed not-a-body
      not-name-value-pairs not-a-redirect-count not-a-boolean not-a-retry-policy
      not-an-attempt-count not-a-backoff not-a-status-list not-a-method-list not-a-limit
      stream-in-group body-length-mismatch))

  ;; The fields:
  ;;
  ;;   field   Symbol: key, for unknown-key, repeated-key and missing-value;
  ;;           form, for body-and-form; multipart, for
  ;;           multipart-beside-body; body, form or multipart, for
  ;;           body-not-allowed, whichever the call gave, in that order;
  ;;           body, for not-a-body; form or params,
  ;;           for not-name-value-pairs; redirects, for not-a-redirect-count;
  ;;           allow-downgrade or jitter, for not-a-boolean; retry, for
  ;;           not-a-retry-policy; attempts, for not-an-attempt-count;
  ;;           backoff-ms or max-backoff-ms, for not-a-backoff; statuses,
  ;;           for not-a-status-list; methods, for not-a-method-list; limit,
  ;;           for not-a-limit; body, the producer, for stream-in-group and
  ;;           body-length-mismatch
  ;;   value   the key as given, for a key's refusal, but a key that is no
  ;;           symbol, named by its kind, (kind K), shown-key's; the method,
  ;;           for body-not-allowed; for every other reason but
  ;;           body-and-form and multipart-beside-body, the value as given
  ;;           where it is a symbol, a
  ;;           number, a boolean, a char or (), else its kind, (kind K),
  ;;           shown-value's: a value where another belongs can be a URL,
  ;;           credentials or a body (M7 slice 3's review); #f, for
  ;;           body-and-form and multipart-beside-body
  ;;   reason  one of http-request-error-reasons
  (define-condition-type &http-request-error &http-error
    unchecked-make-http-request-error http-request-error?
    (field unchecked-http-request-error-field)
    (value unchecked-http-request-error-value)
    (reason unchecked-http-request-error-reason))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03).
  (define http-request-error-field
    (checked-accessor 'http-request-error-field http-request-error? "a &http-request-error" unchecked-http-request-error-field))
  (define http-request-error-value
    (checked-accessor 'http-request-error-value http-request-error? "a &http-request-error" unchecked-http-request-error-value))
  (define http-request-error-reason
    (checked-accessor 'http-request-error-reason http-request-error? "a &http-request-error" unchecked-http-request-error-reason))

  ;; make-http-request-error : Symbol Any Symbol -> &http-request-error
  ;; Refuses a REASON that is not one of http-request-error-reasons with an
  ;; assertion violation, so a misspelt reason cannot reach a caller who
  ;; tests for the right one.
  (define (make-http-request-error field value reason)
    (unless (memq reason http-request-error-reasons)
      (assertion-violation 'make-http-request-error
                           "not a reason the high level refuses a key or a value for"
                           reason))
    (unchecked-make-http-request-error field value reason))

  ;; http-request-error? : Any -> Boolean
  ;; http-request-error-field : &http-request-error -> Symbol
  ;; http-request-error-value : &http-request-error -> Any
  ;; http-request-error-reason : &http-request-error -> Symbol

  ;; http-redirect-error-reasons : (Listof Symbol)
  ;; Why a redirect is not followed (the M5 plan, section 3.4; ADR-0027):
  ;;
  ;;   too-many-redirects  the call had followed its redirects' bound, and
  ;;                       this response would redirect once more
  ;;   bad-location        the Location could not be made a URL: a URL
  ;;                       function of (curl) refused it, whose
  ;;                       &curl-url-error is compounded with this one, or it
  ;;                       names a scheme that is not http or https, with none
  ;;   insecure-redirect   from an https URL to an http one, which the call
  ;;                       did not allow
  ;;   body-not-replayable a redirect whose next request keeps a body a
  ;;                       producer streams, once that producer counts as
  ;;                       called: the drive called it, or libcurl had asked
  ;;                       for the body by a head. A streamed body is sent at
  ;;                       most once (ADR-0032, decision 3, amended)
  (define http-redirect-error-reasons
    '(too-many-redirects bad-location insecure-redirect body-not-replayable))

  ;; The fields:
  ;;
  ;;   reason    one of http-redirect-error-reasons
  ;;   response  the response that named the redirect, an http-response,
  ;;             with the call's history before it
  ;;   location  its first Location header's value, as the response holds
  ;;             it, or #f
  (define-condition-type &http-redirect-error &http-error
    unchecked-make-http-redirect-error http-redirect-error?
    (reason unchecked-http-redirect-error-reason)
    (response unchecked-http-redirect-error-response)
    (location unchecked-http-redirect-error-location))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03).
  (define http-redirect-error-reason
    (checked-accessor 'http-redirect-error-reason http-redirect-error? "a &http-redirect-error" unchecked-http-redirect-error-reason))
  (define http-redirect-error-response
    (checked-accessor 'http-redirect-error-response http-redirect-error? "a &http-redirect-error" unchecked-http-redirect-error-response))
  (define http-redirect-error-location
    (checked-accessor 'http-redirect-error-location http-redirect-error? "a &http-redirect-error" unchecked-http-redirect-error-location))

  ;; make-http-redirect-error : Symbol Response (U String #f) -> &http-redirect-error
  ;; Refuses a REASON that is not one of http-redirect-error-reasons with an
  ;; assertion violation, as make-http-request-error refuses its own.
  (define (make-http-redirect-error reason response location)
    (unless (memq reason http-redirect-error-reasons)
      (assertion-violation 'make-http-redirect-error
                           "not a reason the high level refuses a redirect for" reason))
    (unchecked-make-http-redirect-error reason response location))

  ;; http-redirect-error? : Any -> Boolean
  ;; http-redirect-error-reason : &http-redirect-error -> Symbol
  ;; http-redirect-error-response : &http-redirect-error -> Response
  ;; http-redirect-error-location : &http-redirect-error -> (U String #f)

  ;; make-http-timeout : Positive-Integer -> &http-timeout
  ;; http-timeout? : Any -> Boolean
  ;; http-timeout-timeout-ms : &http-timeout -> Positive-Integer
  ;; A call's timeout-ms passed: TIMEOUT-MS is that bound. When libcurl's 28
  ;; was the bound's, its &curl-timeout is compounded with it (the M5 plan,
  ;; section 3.3).
  (define-condition-type &http-timeout &http-error
    make-http-timeout http-timeout?
    (timeout-ms unchecked-http-timeout-timeout-ms))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03).
  (define http-timeout-timeout-ms
    (checked-accessor 'http-timeout-timeout-ms http-timeout? "a &http-timeout" unchecked-http-timeout-timeout-ms))

  ;; http-group-error-reasons : (Listof Symbol)
  ;; Why a request group refuses an operation, or ended a call (the M5 plan,
  ;; section 3.7):
  ;;
  ;;   wrong-thread  go, http-await, http-pending-done? or
  ;;                 http-pending-cancel called from a thread other than
  ;;                 the one that made the group: a group is its thread's
  ;;   closed        go called once the group's procedure has returned or
  ;;                 escaped
  ;;   cancelled     the await of a call that http-pending-cancel ended, or
  ;;                 that its group ended as it escaped: compounded with the
  ;;                 call's &http-exchange, and with its transfer's own
  ;;                 condition when a transfer was live and ended with one
  (define http-group-error-reasons '(wrong-thread closed cancelled))

  ;; The field:
  ;;
  ;;   reason  one of http-group-error-reasons
  (define-condition-type &http-group-error &http-error
    unchecked-make-http-group-error http-group-error?
    (reason unchecked-http-group-error-reason))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03).
  (define http-group-error-reason
    (checked-accessor 'http-group-error-reason http-group-error? "a &http-group-error" unchecked-http-group-error-reason))

  ;; make-http-group-error : Symbol -> &http-group-error
  ;; Refuses a REASON that is not one of http-group-error-reasons with an
  ;; assertion violation, as make-http-request-error refuses its own.
  (define (make-http-group-error reason)
    (unless (memq reason http-group-error-reasons)
      (assertion-violation 'make-http-group-error
                           "not a reason a request group refuses or ends a call for" reason))
    (unchecked-make-http-group-error reason))

  ;; http-group-error? : Any -> Boolean
  ;; http-group-error-reason : &http-group-error -> Symbol

  ;; make-http-exchange : Any Any (Listof Response) Natural -> &http-exchange
  ;; http-exchange? : Any -> Boolean
  ;; http-exchange-method : &http-exchange -> Any
  ;; http-exchange-url : &http-exchange -> Any
  ;; http-exchange-history : &http-exchange -> (Listof Response)
  ;; http-exchange-transfers : &http-exchange -> Natural
  ;; A call's context: its method and URL as the caller gave them, the
  ;; responses before the last that redirected, oldest first, and how many
  ;; transfers it submitted that the engine took, each retry's among them.
  ;; Under &condition, not &http-error: it
  ;; is compounded onto what a call raises, the low level's conditions
  ;; among it (the M5 plan, section 3.3).
  (define-condition-type &http-exchange &condition
    make-http-exchange http-exchange?
    (method unchecked-http-exchange-method)
    (url unchecked-http-exchange-url)
    (history unchecked-http-exchange-history)
    (transfers unchecked-http-exchange-transfers))

  ;; Each accessor checks its argument first: anything else is an assertion
  ;; violation from the accessor, naming it by its kind, shown-value's,
  ;; never printed, as Chez's own check printed it (ADR-0036, amended
  ;; 2026-11-03).
  (define http-exchange-method
    (checked-accessor 'http-exchange-method http-exchange? "a &http-exchange" unchecked-http-exchange-method))
  (define http-exchange-url
    (checked-accessor 'http-exchange-url http-exchange? "a &http-exchange" unchecked-http-exchange-url))
  (define http-exchange-history
    (checked-accessor 'http-exchange-history http-exchange? "a &http-exchange" unchecked-http-exchange-history))
  (define http-exchange-transfers
    (checked-accessor 'http-exchange-transfers http-exchange? "a &http-exchange" unchecked-http-exchange-transfers)))
