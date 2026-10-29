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
          &http-exchange make-http-exchange http-exchange? http-exchange-method
          http-exchange-url http-exchange-history http-exchange-transfers)
  (import (curl)
          (rnrs))

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
  ;;   body-not-allowed      a body or a form with get or head, which send none
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
  (define http-request-error-reasons
    '(unknown-key repeated-key missing-value body-and-form body-not-allowed not-a-body
      not-name-value-pairs not-a-redirect-count not-a-boolean not-a-retry-policy
      not-an-attempt-count not-a-backoff not-a-status-list not-a-method-list))

  ;; The fields:
  ;;
  ;;   field   Symbol: key, for unknown-key, repeated-key and missing-value;
  ;;           form, for body-and-form; body or form, for body-not-allowed,
  ;;           whichever the call gave; body, for not-a-body; form or params,
  ;;           for not-name-value-pairs; redirects, for not-a-redirect-count;
  ;;           allow-downgrade or jitter, for not-a-boolean; retry, for
  ;;           not-a-retry-policy; attempts, for not-an-attempt-count;
  ;;           backoff-ms or max-backoff-ms, for not-a-backoff; statuses,
  ;;           for not-a-status-list; methods, for not-a-method-list
  ;;   value   the key as given, for a key's refusal; the method, for
  ;;           body-not-allowed; the value as given, for every other reason
  ;;           but body-and-form; #f, for body-and-form
  ;;   reason  one of http-request-error-reasons
  (define-condition-type &http-request-error &http-error
    unchecked-make-http-request-error http-request-error?
    (field http-request-error-field)
    (value http-request-error-value)
    (reason http-request-error-reason))

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
  (define http-redirect-error-reasons
    '(too-many-redirects bad-location insecure-redirect))

  ;; The fields:
  ;;
  ;;   reason    one of http-redirect-error-reasons
  ;;   response  the response that named the redirect, an http-response,
  ;;             with the call's history before it
  ;;   location  its first Location header's value, as the response holds
  ;;             it, or #f
  (define-condition-type &http-redirect-error &http-error
    unchecked-make-http-redirect-error http-redirect-error?
    (reason http-redirect-error-reason)
    (response http-redirect-error-response)
    (location http-redirect-error-location))

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
    (timeout-ms http-timeout-timeout-ms))

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
    (method http-exchange-method)
    (url http-exchange-url)
    (history http-exchange-history)
    (transfers http-exchange-transfers)))
