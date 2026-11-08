## /home/kishu/src/chez-curl/.plans/research/m8/slice3/results/test-proto-floor.log

- check-seam: src/curl/private/transfer.sls: (curl private transfer) imports current-directory from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
- check-seam: FAILED (problems: 1)
- check-seam-exit=2
- suites: 42, failed or hung: 31

### tests/test-auth.sps: FAIL tests/test-auth.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-call-checks.sps: FAIL tests/test-call-checks.sps (exit 1); 19 failing, 19 by the kind alone


### tests/test-check-seam.sps: FAIL tests/test-check-seam.sps (exit 1); 1 failing, 0 by the kind alone

- allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  - expected: `(critical-section current-directory current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-`
  - actual:   `(critical-section current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-second with-mutex)`

### tests/test-collect-safe.sps: FAIL tests/test-collect-safe.sps (exit 1); 1 failing, 0 by the kind alone

- src/ holds to the table: no violation
  - expected: `()`
  - actual:   `((no-row "curl_mime_init" "src/curl/private/native.sls") (no-row "curl_mime_free" "src/curl/private/native.sls") (no-row "curl_mime_addpart" "src/curl/private/native.sls") (no-row "curl_mime_name" "src/curl/private/native.sls") (no-row "curl_mime_data" "src/curl/private/native.sls") (no-row "curl_mime_filedata" "src/curl/private/native.sls") (no-row "curl_mime_filename" "src/curl/private/native.sls") (no-row "curl_mime_type" "src/curl/private/native.sls") (no-row "curl_formfree" "src/curl/private/native.sls") (no-row "curl_formadd" "src/curl/private/native.sls"))`

### tests/test-conditions.sps: FAIL tests/test-conditions.sps (exit 1); 2 failing, 0 by the kind alone

- the request-error reasons are exactly embedded-nul, line-break, not-latin-1, not-a-token, surrounding-whitespace, duplicates-field, framing-header, owned-option, unsupported-type, unknown-option, repeated-option, unknown-key, repeated-key, missing-value, body-not-allowed, pkcs11-url, environment-override, keychain-fallback, stream-with-rounds, body-length-without-stream, body-length-mismatch, prio
  - expected: `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
  - actual:   `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
- the transfer-error reasons are exactly perform-failed, body-limit, callback-raised, setopt-failed, unknown-option, no-handle, cancelled, stopped, pause-failed, body-length-mismatch, body-not-replayable and header-limit, in order
  - expected: `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit)`
  - actual:   `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit part-file mime-failed)`

### tests/test-constants.sps: FAIL tests/test-constants.sps (exit 1); 16 failing, 0 by the kind alone

- constants.sls exports curlform-copyname, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-copycontents, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-end, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-ok, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-disabled, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- prototype-rows has a row for every entry point src/ binds, and src/ binds every row's entry
  - expected: `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_formadd" "curl_formfree" "curl_free" "curl_global_init" "curl_mime_addpart" "curl_mime_data" "curl_mime_filedata" "curl_mime_filename" "curl_mime_free" "curl_mime_init" "curl_mime_name" "curl_mime_type" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_`
  - actual:   `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_free" "curl_global_init" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_wakeup" "curl_share_cleanup" "curl_share_init" "curl_share_setopt" "curl_slist_append" "curl_slist_free_all" "curl_url" "curl_url_cleanup" "curl_url_get" "curl_url_set" "curl_url`
- prototype: "curl_mime_init" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_free" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_addpart" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_name" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_data" bound through bind-required as (uptr uptr size_t) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filedata" bound through bind-blocking as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filename" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_type" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formfree" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formadd" bound through bind-variadic as (uptr uptr int uptr int uptr int) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`

### tests/test-cookies.sps: FAIL tests/test-cookies.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-curl-testing.sps: FAIL tests/test-curl-testing.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-engine.sps: FAIL tests/test-engine.sps (exit 1); 33 failing, 33 by the kind alone


### tests/test-group.sps: FAIL tests/test-group.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-headers.sps: FAIL tests/test-headers.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-http-client.sps: FAIL tests/test-http-client.sps (exit 1); 11 failing, 11 by the kind alone


### tests/test-library-loading.sps: FAIL tests/test-library-loading.sps (exit 1); 56 failing, 39 by the kind alone

- decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.7Gajfa/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy ssl-null: a NULL ssl_version is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.7Gajfa/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/ssl-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/ssl-null.so" override "7.85.0" 480512 1073807373 #f "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-null: a NULL host is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.7Gajfa/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/host-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/host-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" #f) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-utf8: a host past ASCII is read as UTF-8: décoy-λ€
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.7Gajfa/host-utf8.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "décoy-λ€") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/host-utf8.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/host-utf8.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "décoy-λ€") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy protocols: a protocol list is read whole, in its order: https, dict, http
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.7Gajfa/protocols.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols "https" "dict" "http") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/protocols.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/protocols.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy multissl: the report keeps ssl_version as curl_version_info named it before the init, and loaded-tls-backend is the backend in use after it, DecoyTLS, read by a second call
  - expected: `(0 (0 ((loaded . "/tmp/curl-testing.7Gajfa/multissl.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyFirst/1.0 (DecoyTLS/1.0)") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1075904525) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(`
  - actual:   `(0 (1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/multissl.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/multissl.so" override "7.85.0" 480512 1073807373 "DecoyFirst/1.0 (DecoyTLS/1.0)" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.7Ga`
- decoy accepted, with --backend: one backend, named alike before and after the init
  - expected: `(0 ((loaded . "/tmp/curl-testing.7Gajfa/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1073807373) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.7Gajfa/accepted.so\"") `
- decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.7Gajfa/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/options-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "/tmp/curl-testing.7Gajfa/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/headers-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
  - expected: `(0 1 ((reason . load-failed) (path . "/tmp/curl-testing.7Gajfa/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library "/tmp/curl-testing.7Gajfa/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init()")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/easy-init-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
  - expected: `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.7Gajfa/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.7Gajfa/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_heade`
  - actual:   `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/sticks.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.7Gajfa/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
  - expected: `(0 ((loaded . "/tmp/curl-testing.7Gajfa/marked.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/marked.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/marked.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_setopt: a library without curl_easy_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.7Gajfa/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_getinfo: a library without curl_easy_getinfo is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_easy_getinfo") (candidates) (library "/tmp/curl-testing.7Gajfa/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_multi_setopt: a library without curl_multi_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_multi_setopt") (candidates) (library "/tmp/curl-testing.7Gajfa/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_share_setopt: a library without curl_share_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/lacks-curl_share_setopt.so") (source . override) (detail . "curl_share_setopt") (candidates) (library "/tmp/curl-testing.7Gajfa/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.7Gajfa/lacks-curl_share_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.7Gajfa/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  - expected: `(0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/curl-testing.7Gajfa/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")`
  - actual:   `(1 "" "chez-curl: libcurl refused\n(reason . missing-api)\n  path:       /tmp/curl-testing.7Gajfa/accepted.so\n  source:     override\n  detail:     curl_mime_init\n  version:    7.85.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL\n")`

### tests/test-mailbox.sps: FAIL tests/test-mailbox.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-memory-safety.sps: FAIL tests/test-memory-safety.sps (exit 1); 59 failing, 58 by the kind alone

- native-kinds: block, easy, url, slist, curl-string, transfer, multi and share, in that order
  - expected: `(block easy url slist curl-string transfer multi share)`
  - actual:   `(block easy url slist curl-string transfer multi share mime)`

### tests/test-native.sps: FAIL tests/test-native.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-printed.sps: FAIL tests/test-printed.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-proxy.sps: FAIL tests/test-proxy.sps (exit 1); 9 failing, 9 by the kind alone


### tests/test-redirect.sps: FAIL tests/test-redirect.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-request.sps: FAIL tests/test-request.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-retry.sps: FAIL tests/test-retry.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream-call.sps: FAIL tests/test-stream-call.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream.sps: FAIL tests/test-stream.sps (exit 1); 14 failing, 14 by the kind alone


### tests/test-transfer-tls.sps: FAIL tests/test-transfer-tls.sps (exit 1); 43 failing, 42 by the kind alone

- the checks hand the plan their snapshot: request-checks' let* binds ca-file to (ca-file-copy who (curl-request-ca-file request)), checks that copy, first, as (check-ca-environment who 'ca-file ca-file (curl-request-verify request)) and answers it, ca-file standing four times there, the field's name among them; prepare-transfer takes it from (request-checks 'curl-submit request), make-plan takes ca
  - expected: `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading)))) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`
  - actual:   `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading))) multipart) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`

### tests/test-transfer.sps: FAIL tests/test-transfer.sps (exit 1); 128 failing, 125 by the kind alone

- owned-option-names, written out: the options the transfer always sets, QUICK_EXIT and MAXREDIRS among them, and the pins' bitmasks; then each request field's, a streamed body's POST and UPLOAD, its read, seek and prerequest callables and their data, and FRESH_CONNECT, stream-buffer's header callable and its data, HEADERFUNCTION and HEADERDATA, body-length's INFILESIZE_LARGE, http-version's HTTP_VE
  - expected: `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "PASSWORD" "`
  - actual:   `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "`
- request-field-options, written out: url's CURLU; method's NOBODY and CUSTOMREQUEST, and a streamed body's POST and UPLOAD; headers' HTTPHEADER; body's POSTFIELDSIZE_LARGE and COPYPOSTFIELDS, then a streamed one's READFUNCTION, READDATA, SEEKFUNCTION, SEEKDATA, PREREQFUNCTION, PREREQDATA and FRESH_CONNECT; user-agent's USERAGENT; timeout-ms's TIMEOUT_MS; connect-timeout-ms's CONNECTTIMEOUT_MS; body
  - expected: `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credentials "HTTPAUTH`
  - actual:   `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credential`
- every option set-transfer-options! sets is an owned option, written as a literal or through field-option, but for those set by (car setting): three in the loop over method-settings' answer for the plan's method, body and body-length, two, a string's and a number's, in the loop over proxy-settings' answer for the plan's proxy, proxy CA file and proxy verification, one in the loop over version-setti
  - expected: `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 3) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`
  - actual:   `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 4) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`

### tests/test-unsupported.sps: FAIL tests/test-unsupported.sps (exit 1); 28 failing, 28 by the kind alone


### tests/test-upload.sps: FAIL tests/test-upload.sps (exit 1); 6 failing, 6 by the kind alone


### tests/test-url-location.sps: FAIL tests/test-url-location.sps (exit 1); 195 failing, 195 by the kind alone


### tests/test-url-parts.sps: FAIL tests/test-url-parts.sps (exit 1); 135 failing, 135 by the kind alone


### tests/test-url.sps: FAIL tests/test-url.sps (exit 1); 117 failing, 117 by the kind alone


### tests/test-version.sps: FAIL tests/test-version.sps (exit 1); 3 failing, 3 by the kind alone


## /home/kishu/src/chez-curl/.plans/research/m8/slice3/results/test-proto-openssl.log

- check-seam: src/curl/private/transfer.sls: (curl private transfer) imports current-directory from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
- check-seam: FAILED (problems: 1)
- check-seam-exit=2
- suites: 42, failed or hung: 31

### tests/test-auth.sps: FAIL tests/test-auth.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-call-checks.sps: FAIL tests/test-call-checks.sps (exit 1); 19 failing, 19 by the kind alone


### tests/test-check-seam.sps: FAIL tests/test-check-seam.sps (exit 1); 1 failing, 0 by the kind alone

- allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  - expected: `(critical-section current-directory current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-`
  - actual:   `(critical-section current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-second with-mutex)`

### tests/test-collect-safe.sps: FAIL tests/test-collect-safe.sps (exit 1); 1 failing, 0 by the kind alone

- src/ holds to the table: no violation
  - expected: `()`
  - actual:   `((no-row "curl_mime_init" "src/curl/private/native.sls") (no-row "curl_mime_free" "src/curl/private/native.sls") (no-row "curl_mime_addpart" "src/curl/private/native.sls") (no-row "curl_mime_name" "src/curl/private/native.sls") (no-row "curl_mime_data" "src/curl/private/native.sls") (no-row "curl_mime_filedata" "src/curl/private/native.sls") (no-row "curl_mime_filename" "src/curl/private/native.sls") (no-row "curl_mime_type" "src/curl/private/native.sls") (no-row "curl_formfree" "src/curl/private/native.sls") (no-row "curl_formadd" "src/curl/private/native.sls"))`

### tests/test-conditions.sps: FAIL tests/test-conditions.sps (exit 1); 2 failing, 0 by the kind alone

- the request-error reasons are exactly embedded-nul, line-break, not-latin-1, not-a-token, surrounding-whitespace, duplicates-field, framing-header, owned-option, unsupported-type, unknown-option, repeated-option, unknown-key, repeated-key, missing-value, body-not-allowed, pkcs11-url, environment-override, keychain-fallback, stream-with-rounds, body-length-without-stream, body-length-mismatch, prio
  - expected: `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
  - actual:   `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
- the transfer-error reasons are exactly perform-failed, body-limit, callback-raised, setopt-failed, unknown-option, no-handle, cancelled, stopped, pause-failed, body-length-mismatch, body-not-replayable and header-limit, in order
  - expected: `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit)`
  - actual:   `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit part-file mime-failed)`

### tests/test-constants.sps: FAIL tests/test-constants.sps (exit 1); 16 failing, 0 by the kind alone

- constants.sls exports curlform-copyname, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-copycontents, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-end, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-ok, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-disabled, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- prototype-rows has a row for every entry point src/ binds, and src/ binds every row's entry
  - expected: `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_formadd" "curl_formfree" "curl_free" "curl_global_init" "curl_mime_addpart" "curl_mime_data" "curl_mime_filedata" "curl_mime_filename" "curl_mime_free" "curl_mime_init" "curl_mime_name" "curl_mime_type" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_`
  - actual:   `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_free" "curl_global_init" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_wakeup" "curl_share_cleanup" "curl_share_init" "curl_share_setopt" "curl_slist_append" "curl_slist_free_all" "curl_url" "curl_url_cleanup" "curl_url_get" "curl_url_set" "curl_url`
- prototype: "curl_mime_init" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_free" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_addpart" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_name" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_data" bound through bind-required as (uptr uptr size_t) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filedata" bound through bind-blocking as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filename" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_type" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formfree" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formadd" bound through bind-variadic as (uptr uptr int uptr int uptr int) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`

### tests/test-cookies.sps: FAIL tests/test-cookies.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-curl-testing.sps: FAIL tests/test-curl-testing.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-engine.sps: FAIL tests/test-engine.sps (exit 1); 35 failing, 35 by the kind alone


### tests/test-group.sps: FAIL tests/test-group.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-headers.sps: FAIL tests/test-headers.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-http-client.sps: FAIL tests/test-http-client.sps (exit 1); 11 failing, 11 by the kind alone


### tests/test-library-loading.sps: FAIL tests/test-library-loading.sps (exit 1); 56 failing, 39 by the kind alone

- decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.e8GAFW/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy ssl-null: a NULL ssl_version is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.e8GAFW/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/ssl-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/ssl-null.so" override "7.85.0" 480512 1073807373 #f "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-null: a NULL host is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.e8GAFW/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/host-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/host-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" #f) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-utf8: a host past ASCII is read as UTF-8: décoy-λ€
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.e8GAFW/host-utf8.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "décoy-λ€") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/host-utf8.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/host-utf8.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "décoy-λ€") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy protocols: a protocol list is read whole, in its order: https, dict, http
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.e8GAFW/protocols.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols "https" "dict" "http") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/protocols.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/protocols.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy multissl: the report keeps ssl_version as curl_version_info named it before the init, and loaded-tls-backend is the backend in use after it, DecoyTLS, read by a second call
  - expected: `(0 (0 ((loaded . "/tmp/curl-testing.e8GAFW/multissl.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyFirst/1.0 (DecoyTLS/1.0)") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1075904525) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(`
  - actual:   `(0 (1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/multissl.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/multissl.so" override "7.85.0" 480512 1073807373 "DecoyFirst/1.0 (DecoyTLS/1.0)" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.e8G`
- decoy accepted, with --backend: one backend, named alike before and after the init
  - expected: `(0 ((loaded . "/tmp/curl-testing.e8GAFW/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1073807373) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.e8GAFW/accepted.so\"") `
- decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.e8GAFW/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/options-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "/tmp/curl-testing.e8GAFW/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/headers-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
  - expected: `(0 1 ((reason . load-failed) (path . "/tmp/curl-testing.e8GAFW/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library "/tmp/curl-testing.e8GAFW/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init()")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/easy-init-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
  - expected: `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.e8GAFW/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.e8GAFW/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_heade`
  - actual:   `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/sticks.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.e8GAFW/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
  - expected: `(0 ((loaded . "/tmp/curl-testing.e8GAFW/marked.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/marked.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/marked.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_setopt: a library without curl_easy_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.e8GAFW/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_getinfo: a library without curl_easy_getinfo is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_easy_getinfo") (candidates) (library "/tmp/curl-testing.e8GAFW/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_multi_setopt: a library without curl_multi_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_multi_setopt") (candidates) (library "/tmp/curl-testing.e8GAFW/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_share_setopt: a library without curl_share_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/lacks-curl_share_setopt.so") (source . override) (detail . "curl_share_setopt") (candidates) (library "/tmp/curl-testing.e8GAFW/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.e8GAFW/lacks-curl_share_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.e8GAFW/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  - expected: `(0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/curl-testing.e8GAFW/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")`
  - actual:   `(1 "" "chez-curl: libcurl refused\n(reason . missing-api)\n  path:       /tmp/curl-testing.e8GAFW/accepted.so\n  source:     override\n  detail:     curl_mime_init\n  version:    7.85.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL\n")`

### tests/test-mailbox.sps: FAIL tests/test-mailbox.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-memory-safety.sps: FAIL tests/test-memory-safety.sps (exit 1); 59 failing, 58 by the kind alone

- native-kinds: block, easy, url, slist, curl-string, transfer, multi and share, in that order
  - expected: `(block easy url slist curl-string transfer multi share)`
  - actual:   `(block easy url slist curl-string transfer multi share mime)`

### tests/test-native.sps: FAIL tests/test-native.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-printed.sps: FAIL tests/test-printed.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-proxy.sps: FAIL tests/test-proxy.sps (exit 1); 9 failing, 9 by the kind alone


### tests/test-redirect.sps: FAIL tests/test-redirect.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-request.sps: FAIL tests/test-request.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-retry.sps: FAIL tests/test-retry.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream-call.sps: FAIL tests/test-stream-call.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream.sps: FAIL tests/test-stream.sps (exit 1); 14 failing, 14 by the kind alone


### tests/test-transfer-tls.sps: FAIL tests/test-transfer-tls.sps (exit 1); 43 failing, 42 by the kind alone

- the checks hand the plan their snapshot: request-checks' let* binds ca-file to (ca-file-copy who (curl-request-ca-file request)), checks that copy, first, as (check-ca-environment who 'ca-file ca-file (curl-request-verify request)) and answers it, ca-file standing four times there, the field's name among them; prepare-transfer takes it from (request-checks 'curl-submit request), make-plan takes ca
  - expected: `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading)))) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`
  - actual:   `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading))) multipart) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`

### tests/test-transfer.sps: FAIL tests/test-transfer.sps (exit 1); 128 failing, 125 by the kind alone

- owned-option-names, written out: the options the transfer always sets, QUICK_EXIT and MAXREDIRS among them, and the pins' bitmasks; then each request field's, a streamed body's POST and UPLOAD, its read, seek and prerequest callables and their data, and FRESH_CONNECT, stream-buffer's header callable and its data, HEADERFUNCTION and HEADERDATA, body-length's INFILESIZE_LARGE, http-version's HTTP_VE
  - expected: `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "PASSWORD" "`
  - actual:   `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "`
- request-field-options, written out: url's CURLU; method's NOBODY and CUSTOMREQUEST, and a streamed body's POST and UPLOAD; headers' HTTPHEADER; body's POSTFIELDSIZE_LARGE and COPYPOSTFIELDS, then a streamed one's READFUNCTION, READDATA, SEEKFUNCTION, SEEKDATA, PREREQFUNCTION, PREREQDATA and FRESH_CONNECT; user-agent's USERAGENT; timeout-ms's TIMEOUT_MS; connect-timeout-ms's CONNECTTIMEOUT_MS; body
  - expected: `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credentials "HTTPAUTH`
  - actual:   `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credential`
- every option set-transfer-options! sets is an owned option, written as a literal or through field-option, but for those set by (car setting): three in the loop over method-settings' answer for the plan's method, body and body-length, two, a string's and a number's, in the loop over proxy-settings' answer for the plan's proxy, proxy CA file and proxy verification, one in the loop over version-setti
  - expected: `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 3) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`
  - actual:   `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 4) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`

### tests/test-unsupported.sps: FAIL tests/test-unsupported.sps (exit 1); 28 failing, 28 by the kind alone


### tests/test-upload.sps: FAIL tests/test-upload.sps (exit 1); 6 failing, 6 by the kind alone


### tests/test-url-location.sps: FAIL tests/test-url-location.sps (exit 1); 195 failing, 195 by the kind alone


### tests/test-url-parts.sps: FAIL tests/test-url-parts.sps (exit 1); 135 failing, 135 by the kind alone


### tests/test-url.sps: FAIL tests/test-url.sps (exit 1); 127 failing, 127 by the kind alone


### tests/test-version.sps: FAIL tests/test-version.sps (exit 1); 3 failing, 3 by the kind alone


## /home/kishu/src/chez-curl/.plans/research/m8/slice3/results/test-proto-gnutls.log

- check-seam: src/curl/private/transfer.sls: (curl private transfer) imports current-directory from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
- check-seam: FAILED (problems: 1)
- check-seam-exit=2
- suites: 42, failed or hung: 31

### tests/test-auth.sps: FAIL tests/test-auth.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-call-checks.sps: FAIL tests/test-call-checks.sps (exit 1); 19 failing, 19 by the kind alone


### tests/test-check-seam.sps: FAIL tests/test-check-seam.sps (exit 1); 1 failing, 0 by the kind alone

- allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  - expected: `(critical-section current-directory current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-`
  - actual:   `(critical-section current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-second with-mutex)`

### tests/test-collect-safe.sps: FAIL tests/test-collect-safe.sps (exit 1); 1 failing, 0 by the kind alone

- src/ holds to the table: no violation
  - expected: `()`
  - actual:   `((no-row "curl_mime_init" "src/curl/private/native.sls") (no-row "curl_mime_free" "src/curl/private/native.sls") (no-row "curl_mime_addpart" "src/curl/private/native.sls") (no-row "curl_mime_name" "src/curl/private/native.sls") (no-row "curl_mime_data" "src/curl/private/native.sls") (no-row "curl_mime_filedata" "src/curl/private/native.sls") (no-row "curl_mime_filename" "src/curl/private/native.sls") (no-row "curl_mime_type" "src/curl/private/native.sls") (no-row "curl_formfree" "src/curl/private/native.sls") (no-row "curl_formadd" "src/curl/private/native.sls"))`

### tests/test-conditions.sps: FAIL tests/test-conditions.sps (exit 1); 2 failing, 0 by the kind alone

- the request-error reasons are exactly embedded-nul, line-break, not-latin-1, not-a-token, surrounding-whitespace, duplicates-field, framing-header, owned-option, unsupported-type, unknown-option, repeated-option, unknown-key, repeated-key, missing-value, body-not-allowed, pkcs11-url, environment-override, keychain-fallback, stream-with-rounds, body-length-without-stream, body-length-mismatch, prio
  - expected: `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
  - actual:   `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
- the transfer-error reasons are exactly perform-failed, body-limit, callback-raised, setopt-failed, unknown-option, no-handle, cancelled, stopped, pause-failed, body-length-mismatch, body-not-replayable and header-limit, in order
  - expected: `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit)`
  - actual:   `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit part-file mime-failed)`

### tests/test-constants.sps: FAIL tests/test-constants.sps (exit 1); 16 failing, 0 by the kind alone

- constants.sls exports curlform-copyname, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-copycontents, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-end, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-ok, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-disabled, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- prototype-rows has a row for every entry point src/ binds, and src/ binds every row's entry
  - expected: `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_formadd" "curl_formfree" "curl_free" "curl_global_init" "curl_mime_addpart" "curl_mime_data" "curl_mime_filedata" "curl_mime_filename" "curl_mime_free" "curl_mime_init" "curl_mime_name" "curl_mime_type" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_`
  - actual:   `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_free" "curl_global_init" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_wakeup" "curl_share_cleanup" "curl_share_init" "curl_share_setopt" "curl_slist_append" "curl_slist_free_all" "curl_url" "curl_url_cleanup" "curl_url_get" "curl_url_set" "curl_url`
- prototype: "curl_mime_init" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_free" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_addpart" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_name" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_data" bound through bind-required as (uptr uptr size_t) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filedata" bound through bind-blocking as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filename" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_type" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formfree" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formadd" bound through bind-variadic as (uptr uptr int uptr int uptr int) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`

### tests/test-cookies.sps: FAIL tests/test-cookies.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-curl-testing.sps: FAIL tests/test-curl-testing.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-engine.sps: FAIL tests/test-engine.sps (exit 1); 35 failing, 35 by the kind alone


### tests/test-group.sps: FAIL tests/test-group.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-headers.sps: FAIL tests/test-headers.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-http-client.sps: FAIL tests/test-http-client.sps (exit 1); 11 failing, 11 by the kind alone


### tests/test-library-loading.sps: FAIL tests/test-library-loading.sps (exit 1); 56 failing, 39 by the kind alone

- decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.SeL0sn/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy ssl-null: a NULL ssl_version is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.SeL0sn/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/ssl-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/ssl-null.so" override "7.85.0" 480512 1073807373 #f "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-null: a NULL host is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.SeL0sn/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/host-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/host-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" #f) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-utf8: a host past ASCII is read as UTF-8: décoy-λ€
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.SeL0sn/host-utf8.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "décoy-λ€") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/host-utf8.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/host-utf8.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "décoy-λ€") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy protocols: a protocol list is read whole, in its order: https, dict, http
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.SeL0sn/protocols.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols "https" "dict" "http") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/protocols.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/protocols.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy multissl: the report keeps ssl_version as curl_version_info named it before the init, and loaded-tls-backend is the backend in use after it, DecoyTLS, read by a second call
  - expected: `(0 (0 ((loaded . "/tmp/curl-testing.SeL0sn/multissl.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyFirst/1.0 (DecoyTLS/1.0)") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1075904525) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(`
  - actual:   `(0 (1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/multissl.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/multissl.so" override "7.85.0" 480512 1073807373 "DecoyFirst/1.0 (DecoyTLS/1.0)" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.SeL`
- decoy accepted, with --backend: one backend, named alike before and after the init
  - expected: `(0 ((loaded . "/tmp/curl-testing.SeL0sn/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1073807373) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.SeL0sn/accepted.so\"") `
- decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.SeL0sn/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/options-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "/tmp/curl-testing.SeL0sn/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/headers-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
  - expected: `(0 1 ((reason . load-failed) (path . "/tmp/curl-testing.SeL0sn/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library "/tmp/curl-testing.SeL0sn/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init()")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/easy-init-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
  - expected: `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.SeL0sn/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.SeL0sn/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_heade`
  - actual:   `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/sticks.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.SeL0sn/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
  - expected: `(0 ((loaded . "/tmp/curl-testing.SeL0sn/marked.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/marked.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/marked.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_setopt: a library without curl_easy_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.SeL0sn/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_getinfo: a library without curl_easy_getinfo is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_easy_getinfo") (candidates) (library "/tmp/curl-testing.SeL0sn/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_multi_setopt: a library without curl_multi_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_multi_setopt") (candidates) (library "/tmp/curl-testing.SeL0sn/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_share_setopt: a library without curl_share_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/lacks-curl_share_setopt.so") (source . override) (detail . "curl_share_setopt") (candidates) (library "/tmp/curl-testing.SeL0sn/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.SeL0sn/lacks-curl_share_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.SeL0sn/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  - expected: `(0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/curl-testing.SeL0sn/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")`
  - actual:   `(1 "" "chez-curl: libcurl refused\n(reason . missing-api)\n  path:       /tmp/curl-testing.SeL0sn/accepted.so\n  source:     override\n  detail:     curl_mime_init\n  version:    7.85.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL\n")`

### tests/test-mailbox.sps: FAIL tests/test-mailbox.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-memory-safety.sps: FAIL tests/test-memory-safety.sps (exit 1); 59 failing, 58 by the kind alone

- native-kinds: block, easy, url, slist, curl-string, transfer, multi and share, in that order
  - expected: `(block easy url slist curl-string transfer multi share)`
  - actual:   `(block easy url slist curl-string transfer multi share mime)`

### tests/test-native.sps: FAIL tests/test-native.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-printed.sps: FAIL tests/test-printed.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-proxy.sps: FAIL tests/test-proxy.sps (exit 1); 9 failing, 9 by the kind alone


### tests/test-redirect.sps: FAIL tests/test-redirect.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-request.sps: FAIL tests/test-request.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-retry.sps: FAIL tests/test-retry.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream-call.sps: FAIL tests/test-stream-call.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream.sps: FAIL tests/test-stream.sps (exit 1); 14 failing, 14 by the kind alone


### tests/test-transfer-tls.sps: FAIL tests/test-transfer-tls.sps (exit 1); 43 failing, 42 by the kind alone

- the checks hand the plan their snapshot: request-checks' let* binds ca-file to (ca-file-copy who (curl-request-ca-file request)), checks that copy, first, as (check-ca-environment who 'ca-file ca-file (curl-request-verify request)) and answers it, ca-file standing four times there, the field's name among them; prepare-transfer takes it from (request-checks 'curl-submit request), make-plan takes ca
  - expected: `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading)))) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`
  - actual:   `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading))) multipart) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`

### tests/test-transfer.sps: FAIL tests/test-transfer.sps (exit 1); 128 failing, 125 by the kind alone

- owned-option-names, written out: the options the transfer always sets, QUICK_EXIT and MAXREDIRS among them, and the pins' bitmasks; then each request field's, a streamed body's POST and UPLOAD, its read, seek and prerequest callables and their data, and FRESH_CONNECT, stream-buffer's header callable and its data, HEADERFUNCTION and HEADERDATA, body-length's INFILESIZE_LARGE, http-version's HTTP_VE
  - expected: `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "PASSWORD" "`
  - actual:   `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "`
- request-field-options, written out: url's CURLU; method's NOBODY and CUSTOMREQUEST, and a streamed body's POST and UPLOAD; headers' HTTPHEADER; body's POSTFIELDSIZE_LARGE and COPYPOSTFIELDS, then a streamed one's READFUNCTION, READDATA, SEEKFUNCTION, SEEKDATA, PREREQFUNCTION, PREREQDATA and FRESH_CONNECT; user-agent's USERAGENT; timeout-ms's TIMEOUT_MS; connect-timeout-ms's CONNECTTIMEOUT_MS; body
  - expected: `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credentials "HTTPAUTH`
  - actual:   `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credential`
- every option set-transfer-options! sets is an owned option, written as a literal or through field-option, but for those set by (car setting): three in the loop over method-settings' answer for the plan's method, body and body-length, two, a string's and a number's, in the loop over proxy-settings' answer for the plan's proxy, proxy CA file and proxy verification, one in the loop over version-setti
  - expected: `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 3) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`
  - actual:   `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 4) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`

### tests/test-unsupported.sps: FAIL tests/test-unsupported.sps (exit 1); 28 failing, 28 by the kind alone


### tests/test-upload.sps: FAIL tests/test-upload.sps (exit 1); 6 failing, 6 by the kind alone


### tests/test-url-location.sps: FAIL tests/test-url-location.sps (exit 1); 195 failing, 195 by the kind alone


### tests/test-url-parts.sps: FAIL tests/test-url-parts.sps (exit 1); 135 failing, 135 by the kind alone


### tests/test-url.sps: FAIL tests/test-url.sps (exit 1); 127 failing, 127 by the kind alone


### tests/test-version.sps: FAIL tests/test-version.sps (exit 1); 3 failing, 3 by the kind alone


## /home/kishu/src/chez-curl/.plans/research/m8/slice3/results/test-proto-guix-8.20.0.log

- check-seam: src/curl/private/transfer.sls: (curl private transfer) imports current-directory from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
- check-seam: FAILED (problems: 1)
- check-seam-exit=2
- suites: 42, failed or hung: 31

### tests/test-auth.sps: FAIL tests/test-auth.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-call-checks.sps: FAIL tests/test-call-checks.sps (exit 1); 19 failing, 19 by the kind alone


### tests/test-check-seam.sps: FAIL tests/test-check-seam.sps (exit 1); 1 failing, 0 by the kind alone

- allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  - expected: `(critical-section current-directory current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-`
  - actual:   `(critical-section current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-second with-mutex)`

### tests/test-collect-safe.sps: FAIL tests/test-collect-safe.sps (exit 1); 1 failing, 0 by the kind alone

- src/ holds to the table: no violation
  - expected: `()`
  - actual:   `((no-row "curl_mime_init" "src/curl/private/native.sls") (no-row "curl_mime_free" "src/curl/private/native.sls") (no-row "curl_mime_addpart" "src/curl/private/native.sls") (no-row "curl_mime_name" "src/curl/private/native.sls") (no-row "curl_mime_data" "src/curl/private/native.sls") (no-row "curl_mime_filedata" "src/curl/private/native.sls") (no-row "curl_mime_filename" "src/curl/private/native.sls") (no-row "curl_mime_type" "src/curl/private/native.sls") (no-row "curl_formfree" "src/curl/private/native.sls") (no-row "curl_formadd" "src/curl/private/native.sls"))`

### tests/test-conditions.sps: FAIL tests/test-conditions.sps (exit 1); 2 failing, 0 by the kind alone

- the request-error reasons are exactly embedded-nul, line-break, not-latin-1, not-a-token, surrounding-whitespace, duplicates-field, framing-header, owned-option, unsupported-type, unknown-option, repeated-option, unknown-key, repeated-key, missing-value, body-not-allowed, pkcs11-url, environment-override, keychain-fallback, stream-with-rounds, body-length-without-stream, body-length-mismatch, prio
  - expected: `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
  - actual:   `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
- the transfer-error reasons are exactly perform-failed, body-limit, callback-raised, setopt-failed, unknown-option, no-handle, cancelled, stopped, pause-failed, body-length-mismatch, body-not-replayable and header-limit, in order
  - expected: `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit)`
  - actual:   `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit part-file mime-failed)`

### tests/test-constants.sps: FAIL tests/test-constants.sps (exit 1); 16 failing, 0 by the kind alone

- constants.sls exports curlform-copyname, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-copycontents, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-end, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-ok, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-disabled, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- prototype-rows has a row for every entry point src/ binds, and src/ binds every row's entry
  - expected: `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_formadd" "curl_formfree" "curl_free" "curl_global_init" "curl_mime_addpart" "curl_mime_data" "curl_mime_filedata" "curl_mime_filename" "curl_mime_free" "curl_mime_init" "curl_mime_name" "curl_mime_type" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_`
  - actual:   `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_free" "curl_global_init" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_wakeup" "curl_share_cleanup" "curl_share_init" "curl_share_setopt" "curl_slist_append" "curl_slist_free_all" "curl_url" "curl_url_cleanup" "curl_url_get" "curl_url_set" "curl_url`
- prototype: "curl_mime_init" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_free" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_addpart" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_name" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_data" bound through bind-required as (uptr uptr size_t) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filedata" bound through bind-blocking as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filename" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_type" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formfree" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formadd" bound through bind-variadic as (uptr uptr int uptr int uptr int) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`

### tests/test-cookies.sps: FAIL tests/test-cookies.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-curl-testing.sps: FAIL tests/test-curl-testing.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-engine.sps: FAIL tests/test-engine.sps (exit 1); 35 failing, 35 by the kind alone


### tests/test-group.sps: FAIL tests/test-group.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-headers.sps: FAIL tests/test-headers.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-http-client.sps: FAIL tests/test-http-client.sps (exit 1); 11 failing, 11 by the kind alone


### tests/test-library-loading.sps: FAIL tests/test-library-loading.sps (exit 1); 58 failing, 41 by the kind alone

- decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.orBGxO/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy ssl-null: a NULL ssl_version is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.orBGxO/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/ssl-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/ssl-null.so" override "7.85.0" 480512 1073807373 #f "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-null: a NULL host is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.orBGxO/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/host-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/host-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" #f) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-utf8: a host past ASCII is read as UTF-8: décoy-λ€
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.orBGxO/host-utf8.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "décoy-λ€") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/host-utf8.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/host-utf8.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "décoy-λ€") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy protocols: a protocol list is read whole, in its order: https, dict, http
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.orBGxO/protocols.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols "https" "dict" "http") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/protocols.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/protocols.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy multissl: the report keeps ssl_version as curl_version_info named it before the init, and loaded-tls-backend is the backend in use after it, DecoyTLS, read by a second call
  - expected: `(0 (0 ((loaded . "/tmp/curl-testing.orBGxO/multissl.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyFirst/1.0 (DecoyTLS/1.0)") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1075904525) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(`
  - actual:   `(0 (1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/multissl.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/multissl.so" override "7.85.0" 480512 1073807373 "DecoyFirst/1.0 (DecoyTLS/1.0)" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.orB`
- decoy accepted, with --backend: one backend, named alike before and after the init
  - expected: `(0 ((loaded . "/tmp/curl-testing.orBGxO/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1073807373) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.orBGxO/accepted.so\"") `
- decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.orBGxO/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/options-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "/tmp/curl-testing.orBGxO/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/headers-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
  - expected: `(0 1 ((reason . load-failed) (path . "/tmp/curl-testing.orBGxO/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library "/tmp/curl-testing.orBGxO/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init()")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/easy-init-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
  - expected: `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.orBGxO/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.orBGxO/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_heade`
  - actual:   `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/sticks.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.orBGxO/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
  - expected: `(0 ((loaded . "/tmp/curl-testing.orBGxO/marked.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/marked.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/marked.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_setopt: a library without curl_easy_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.orBGxO/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_getinfo: a library without curl_easy_getinfo is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_easy_getinfo") (candidates) (library "/tmp/curl-testing.orBGxO/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_multi_setopt: a library without curl_multi_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_multi_setopt") (candidates) (library "/tmp/curl-testing.orBGxO/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_share_setopt: a library without curl_share_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/lacks-curl_share_setopt.so") (source . override) (detail . "curl_share_setopt") (candidates) (library "/tmp/curl-testing.orBGxO/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.orBGxO/lacks-curl_share_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.orBGxO/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  - expected: `(0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/curl-testing.orBGxO/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")`
  - actual:   `(1 "" "chez-curl: libcurl refused\n(reason . missing-api)\n  path:       /tmp/curl-testing.orBGxO/accepted.so\n  source:     override\n  detail:     curl_mime_init\n  version:    7.85.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL\n")`

### tests/test-mailbox.sps: FAIL tests/test-mailbox.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-memory-safety.sps: FAIL tests/test-memory-safety.sps (exit 1); 59 failing, 58 by the kind alone

- native-kinds: block, easy, url, slist, curl-string, transfer, multi and share, in that order
  - expected: `(block easy url slist curl-string transfer multi share)`
  - actual:   `(block easy url slist curl-string transfer multi share mime)`

### tests/test-native.sps: FAIL tests/test-native.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-printed.sps: FAIL tests/test-printed.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-proxy.sps: FAIL tests/test-proxy.sps (exit 1); 9 failing, 9 by the kind alone


### tests/test-redirect.sps: FAIL tests/test-redirect.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-request.sps: FAIL tests/test-request.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-retry.sps: FAIL tests/test-retry.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream-call.sps: FAIL tests/test-stream-call.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream.sps: FAIL tests/test-stream.sps (exit 1); 14 failing, 14 by the kind alone


### tests/test-transfer-tls.sps: FAIL tests/test-transfer-tls.sps (exit 1); 43 failing, 42 by the kind alone

- the checks hand the plan their snapshot: request-checks' let* binds ca-file to (ca-file-copy who (curl-request-ca-file request)), checks that copy, first, as (check-ca-environment who 'ca-file ca-file (curl-request-verify request)) and answers it, ca-file standing four times there, the field's name among them; prepare-transfer takes it from (request-checks 'curl-submit request), make-plan takes ca
  - expected: `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading)))) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`
  - actual:   `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading))) multipart) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`

### tests/test-transfer.sps: FAIL tests/test-transfer.sps (exit 1); 128 failing, 125 by the kind alone

- owned-option-names, written out: the options the transfer always sets, QUICK_EXIT and MAXREDIRS among them, and the pins' bitmasks; then each request field's, a streamed body's POST and UPLOAD, its read, seek and prerequest callables and their data, and FRESH_CONNECT, stream-buffer's header callable and its data, HEADERFUNCTION and HEADERDATA, body-length's INFILESIZE_LARGE, http-version's HTTP_VE
  - expected: `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "PASSWORD" "`
  - actual:   `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "`
- request-field-options, written out: url's CURLU; method's NOBODY and CUSTOMREQUEST, and a streamed body's POST and UPLOAD; headers' HTTPHEADER; body's POSTFIELDSIZE_LARGE and COPYPOSTFIELDS, then a streamed one's READFUNCTION, READDATA, SEEKFUNCTION, SEEKDATA, PREREQFUNCTION, PREREQDATA and FRESH_CONNECT; user-agent's USERAGENT; timeout-ms's TIMEOUT_MS; connect-timeout-ms's CONNECTTIMEOUT_MS; body
  - expected: `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credentials "HTTPAUTH`
  - actual:   `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credential`
- every option set-transfer-options! sets is an owned option, written as a literal or through field-option, but for those set by (car setting): three in the loop over method-settings' answer for the plan's method, body and body-length, two, a string's and a number's, in the loop over proxy-settings' answer for the plan's proxy, proxy CA file and proxy verification, one in the loop over version-setti
  - expected: `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 3) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`
  - actual:   `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 4) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`

### tests/test-unsupported.sps: FAIL tests/test-unsupported.sps (exit 1); 28 failing, 28 by the kind alone


### tests/test-upload.sps: FAIL tests/test-upload.sps (exit 1); 6 failing, 6 by the kind alone


### tests/test-url-location.sps: FAIL tests/test-url-location.sps (exit 1); 195 failing, 195 by the kind alone


### tests/test-url-parts.sps: FAIL tests/test-url-parts.sps (exit 1); 135 failing, 135 by the kind alone


### tests/test-url.sps: FAIL tests/test-url.sps (exit 1); 118 failing, 118 by the kind alone


### tests/test-version.sps: FAIL tests/test-version.sps (exit 1); 3 failing, 3 by the kind alone


## /home/kishu/src/chez-curl/.plans/research/m8/slice3/results/test-proto-current.log

- check-seam: src/curl/private/transfer.sls: (curl private transfer) imports current-directory from (chezscheme), but allowed-chez-names in tests/check-seam.sps does not list it
- check-seam: FAILED (problems: 1)
- check-seam-exit=2
- suites: 42, failed or hung: 31

### tests/test-auth.sps: FAIL tests/test-auth.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-call-checks.sps: FAIL tests/test-call-checks.sps (exit 1); 19 failing, 19 by the kind alone


### tests/test-check-seam.sps: FAIL tests/test-check-seam.sps (exit 1); 1 failing, 0 by the kind alone

- allowed-chez-names is exactly the names the libraries under src/ import from (chezscheme)
  - expected: `(critical-section current-directory current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-`
  - actual:   `(critical-section current-time define-ftype disable-interrupts display-condition dynamic-wind enable-interrupts file-regular? foreign-alloc foreign-callable foreign-callable-entry-point foreign-entry foreign-entry? foreign-free foreign-procedure foreign-ref foreign-sizeof fork-thread format format-condition? ftype-ref ftype-set! ftype-sizeof get-thread-id getenv load-shared-object lock-object machine-type make-ftype-pointer make-mutex make-pseudo-random-generator make-time pseudo-random-generator-next! scheme-version scheme-version-number sleep threaded? time-nanosecond time-second with-mutex)`

### tests/test-collect-safe.sps: FAIL tests/test-collect-safe.sps (exit 1); 1 failing, 0 by the kind alone

- src/ holds to the table: no violation
  - expected: `()`
  - actual:   `((no-row "curl_mime_init" "src/curl/private/native.sls") (no-row "curl_mime_free" "src/curl/private/native.sls") (no-row "curl_mime_addpart" "src/curl/private/native.sls") (no-row "curl_mime_name" "src/curl/private/native.sls") (no-row "curl_mime_data" "src/curl/private/native.sls") (no-row "curl_mime_filedata" "src/curl/private/native.sls") (no-row "curl_mime_filename" "src/curl/private/native.sls") (no-row "curl_mime_type" "src/curl/private/native.sls") (no-row "curl_formfree" "src/curl/private/native.sls") (no-row "curl_formadd" "src/curl/private/native.sls"))`

### tests/test-conditions.sps: FAIL tests/test-conditions.sps (exit 1); 2 failing, 0 by the kind alone

- the request-error reasons are exactly embedded-nul, line-break, not-latin-1, not-a-token, surrounding-whitespace, duplicates-field, framing-header, owned-option, unsupported-type, unknown-option, repeated-option, unknown-key, repeated-key, missing-value, body-not-allowed, pkcs11-url, environment-override, keychain-fallback, stream-with-rounds, body-length-without-stream, body-length-mismatch, prio
  - expected: `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
  - actual:   `(embedded-nul line-break not-latin-1 not-a-token surrounding-whitespace duplicates-field framing-header owned-option unsupported-type unknown-option repeated-option unknown-key repeated-key missing-value body-not-allowed pkcs11-url environment-override keychain-fallback stream-with-rounds body-length-without-stream body-length-mismatch prior-knowledge-over-https credentials-bytes credentials-empty credentials-beside-userinfo credentials-beside-authorization digest-with-stream prior-knowledge-through-proxy proxy-url proxy-scheme proxy-url-parts proxy-authorization-header proxy-tls-without-https`
- the transfer-error reasons are exactly perform-failed, body-limit, callback-raised, setopt-failed, unknown-option, no-handle, cancelled, stopped, pause-failed, body-length-mismatch, body-not-replayable and header-limit, in order
  - expected: `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit)`
  - actual:   `(perform-failed body-limit callback-raised setopt-failed unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable header-limit part-file mime-failed)`

### tests/test-constants.sps: FAIL tests/test-constants.sps (exit 1); 16 failing, 0 by the kind alone

- constants.sls exports curlform-copyname, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-copycontents, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curlform-end, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-ok, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- constants.sls exports curl-formadd-disabled, and constant-rows has a row for it
  - expected: `row`
  - actual:   `no-row`
- prototype-rows has a row for every entry point src/ binds, and src/ binds every row's entry
  - expected: `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_formadd" "curl_formfree" "curl_free" "curl_global_init" "curl_mime_addpart" "curl_mime_data" "curl_mime_filedata" "curl_mime_filename" "curl_mime_free" "curl_mime_init" "curl_mime_name" "curl_mime_type" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_`
  - actual:   `("curl_easy_cleanup" "curl_easy_getinfo" "curl_easy_header" "curl_easy_init" "curl_easy_nextheader" "curl_easy_option_by_name" "curl_easy_pause" "curl_easy_setopt" "curl_easy_strerror" "curl_free" "curl_global_init" "curl_multi_add_handle" "curl_multi_cleanup" "curl_multi_info_read" "curl_multi_init" "curl_multi_perform" "curl_multi_poll" "curl_multi_remove_handle" "curl_multi_setopt" "curl_multi_strerror" "curl_multi_wakeup" "curl_share_cleanup" "curl_share_init" "curl_share_setopt" "curl_slist_append" "curl_slist_free_all" "curl_url" "curl_url_cleanup" "curl_url_get" "curl_url_set" "curl_url`
- prototype: "curl_mime_init" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_free" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_addpart" bound through bind-required as (uptr) -> uptr fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_name" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_data" bound through bind-required as (uptr uptr size_t) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filedata" bound through bind-blocking as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_filename" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_mime_type" bound through bind-required as (uptr uptr) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formfree" bound through bind-required as (uptr) -> void fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`
- prototype: "curl_formadd" bound through bind-variadic as (uptr uptr int uptr int uptr int) -> int fits a declaration its row gives
  - expected: `fits`
  - actual:   `no-row`

### tests/test-cookies.sps: FAIL tests/test-cookies.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-curl-testing.sps: FAIL tests/test-curl-testing.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-engine.sps: FAIL tests/test-engine.sps (exit 1); 35 failing, 35 by the kind alone


### tests/test-group.sps: FAIL tests/test-group.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-headers.sps: FAIL tests/test-headers.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-http-client.sps: FAIL tests/test-http-client.sps (exit 1); 11 failing, 11 by the kind alone


### tests/test-library-loading.sps: FAIL tests/test-library-loading.sps (exit 1); 56 failing, 39 by the kind alone

- decoy accepted: the control loads, calling curl_global_init exactly once, after the version
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.AVCgX8/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy ssl-null: a NULL ssl_version is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.AVCgX8/ssl-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . #f) (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/ssl-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/ssl-null.so" override "7.85.0" 480512 1073807373 #f "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-null: a NULL host is reported as #f
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.AVCgX8/host-null.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . #f) (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/host-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/host-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" #f) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy host-utf8: a host past ASCII is read as UTF-8: décoy-λ€
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.AVCgX8/host-utf8.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "décoy-λ€") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/host-utf8.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/host-utf8.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "décoy-λ€") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy protocols: a protocol list is read whole, in its order: https, dict, http
  - expected: `(0 0 ((loaded . "/tmp/curl-testing.AVCgX8/protocols.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols "https" "dict" "http") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/protocols.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/protocols.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy multissl: the report keeps ssl_version as curl_version_info named it before the init, and loaded-tls-backend is the backend in use after it, DecoyTLS, read by a second call
  - expected: `(0 (0 ((loaded . "/tmp/curl-testing.AVCgX8/multissl.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyFirst/1.0 (DecoyTLS/1.0)") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1075904525) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(`
  - actual:   `(0 (1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/multissl.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/multissl.so" override "7.85.0" 480512 1073807373 "DecoyFirst/1.0 (DecoyTLS/1.0)" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.AVC`
- decoy accepted, with --backend: one backend, named alike before and after the init
  - expected: `(0 ((loaded . "/tmp/curl-testing.AVCgX8/accepted.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (backend . "DecoyTLS/1.0") (features-after . 1073807373) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/accepted.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/accepted.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (backend raised "Exception in chez-curl: the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL with irritant \"/tmp/curl-testing.AVCgX8/accepted.so\"") `
- decoy options-off: no option by name is missing-api, naming curl_easy_option_by_name
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/options-off.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.AVCgX8/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/options-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/options-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy headers-off: CURLHE_NOT_BUILT_IN is missing-api, naming curl_easy_header
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/headers-off.so") (source . override) (detail . "curl_easy_header") (candidates) (library "/tmp/curl-testing.AVCgX8/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/headers-off.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/headers-off.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy easy-init-null: curl_easy_init answering NULL is load-failed, and curl_easy_header never runs
  - expected: `(0 1 ((reason . load-failed) (path . "/tmp/curl-testing.AVCgX8/easy-init-null.so") (source . override) (detail . "curl_easy_init returned NULL") (candidates) (library "/tmp/curl-testing.AVCgX8/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init()")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/easy-init-null.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/easy-init-null.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- a refusal sticks: CHEZ_CURL_LIBCURL changed between references loads nothing new
  - expected: `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/sticks.so") (source . override) (detail . "curl_easy_option_by_name") (candidates) (library "/tmp/curl-testing.AVCgX8/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.AVCgX8/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_heade`
  - actual:   `(0 0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/sticks.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/sticks.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (then-override . "/tmp/curl-testing.AVCgX8/sticks-then.so") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . absent) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy marked: a build with DECOY_MARKER, once loaded, shows its marker to foreign-entry?
  - expected: `(0 ((loaded . "/tmp/curl-testing.AVCgX8/marked.so") (source . override) (version . "7.85.0") (version-num . 480512) (features . 1073807373) (ssl-version . "DecoyTLS/1.0") (host . "decoy-host") (protocols) (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9) curl_easy_option_by_name(URL) curl_easy_init() curl_easy_header(handle,Content-Type,0,1,-1,hout) curl_easy_cleanup(handle)")) "")`
  - actual:   `(1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/marked.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/marked.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (marker . present) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_setopt: a library without curl_easy_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_easy_setopt") (candidates) (library "/tmp/curl-testing.AVCgX8/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/lacks-curl_easy_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/lacks-curl_easy_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_easy_getinfo: a library without curl_easy_getinfo is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_easy_getinfo") (candidates) (library "/tmp/curl-testing.AVCgX8/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/lacks-curl_easy_getinfo.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/lacks-curl_easy_getinfo.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_multi_setopt: a library without curl_multi_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_multi_setopt") (candidates) (library "/tmp/curl-testing.AVCgX8/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/lacks-curl_multi_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/lacks-curl_multi_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- decoy lacks-curl_share_setopt: a library without curl_share_setopt is missing-api, naming it
  - expected: `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/lacks-curl_share_setopt.so") (source . override) (detail . "curl_share_setopt") (candidates) (library "/tmp/curl-testing.AVCgX8/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
  - actual:   `(0 1 ((reason . missing-api) (path . "/tmp/curl-testing.AVCgX8/lacks-curl_share_setopt.so") (source . override) (detail . "curl_mime_init") (candidates) (library "/tmp/curl-testing.AVCgX8/lacks-curl_share_setopt.so" override "7.85.0" 480512 1073807373 "DecoyTLS/1.0" "decoy-host") (again same same) (counts (block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)) (calls . "curl_version_info(9) curl_global_init(3) curl_version_info(9)")) "")`
- preflight, the accepted decoy: exit 0, naming its path, version, TLS, features and host
  - expected: `(0 "chez-curl: libcurl loaded and accepted\n  path:     /tmp/curl-testing.AVCgX8/accepted.so (override)\n  version:  7.85.0\n  TLS:      DecoyTLS/1.0\n  features: ipv6 ssl libz http2 threadsafe\n  host:     decoy-host\n" "")`
  - actual:   `(1 "" "chez-curl: libcurl refused\n(reason . missing-api)\n  path:       /tmp/curl-testing.AVCgX8/accepted.so\n  source:     override\n  detail:     curl_mime_init\n  version:    7.85.0\n  TLS:        DecoyTLS/1.0\n  features:   ipv6 ssl libz http2 threadsafe\n  candidates: none\n  remedy:     the library has no curl_mime_init, so it is not a libcurl chez-curl can use; name another with CHEZ_CURL_LIBCURL\n")`

### tests/test-mailbox.sps: FAIL tests/test-mailbox.sps (exit 1); 4 failing, 4 by the kind alone


### tests/test-memory-safety.sps: FAIL tests/test-memory-safety.sps (exit 1); 59 failing, 58 by the kind alone

- native-kinds: block, easy, url, slist, curl-string, transfer, multi and share, in that order
  - expected: `(block easy url slist curl-string transfer multi share)`
  - actual:   `(block easy url slist curl-string transfer multi share mime)`

### tests/test-native.sps: FAIL tests/test-native.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-printed.sps: FAIL tests/test-printed.sps (exit 1); 1 failing, 1 by the kind alone


### tests/test-proxy.sps: FAIL tests/test-proxy.sps (exit 1); 9 failing, 9 by the kind alone


### tests/test-redirect.sps: FAIL tests/test-redirect.sps (exit 1); 2 failing, 2 by the kind alone


### tests/test-request.sps: FAIL tests/test-request.sps (exit 1); 13 failing, 13 by the kind alone


### tests/test-retry.sps: FAIL tests/test-retry.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream-call.sps: FAIL tests/test-stream-call.sps (exit 1); 3 failing, 3 by the kind alone


### tests/test-stream.sps: FAIL tests/test-stream.sps (exit 1); 14 failing, 14 by the kind alone


### tests/test-transfer-tls.sps: FAIL tests/test-transfer-tls.sps (exit 1); 43 failing, 42 by the kind alone

- the checks hand the plan their snapshot: request-checks' let* binds ca-file to (ca-file-copy who (curl-request-ca-file request)), checks that copy, first, as (check-ca-environment who 'ca-file ca-file (curl-request-verify request)) and answers it, ca-file standing four times there, the field's name among them; prepare-transfer takes it from (request-checks 'curl-submit request), make-plan takes ca
  - expected: `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading)))) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`
  - actual:   `((ca-file (ca-file-copy who (curl-request-ca-file request))) (check-ca-environment who (quote ca-file) ca-file (curl-request-verify request)) (values url fields ca-file credentials (if reading (car reading) proxy) proxy-ca-file (unshared-tunnel-settings version-number scheme (and reading #t) (and reading (caddr reading))) (stops-multiplexing? version-number (and reading #t) (and reading (caddr reading))) multipart) 4 (request-checks (quote curl-submit) request) (ca-file (curl-request-verify request)) 2 ((immutable ca-file) (immutable verify)))`

### tests/test-transfer.sps: FAIL tests/test-transfer.sps (exit 1); 128 failing, 125 by the kind alone

- owned-option-names, written out: the options the transfer always sets, QUICK_EXIT and MAXREDIRS among them, and the pins' bitmasks; then each request field's, a streamed body's POST and UPLOAD, its read, seek and prerequest callables and their data, and FRESH_CONNECT, stream-buffer's header callable and its data, HEADERFUNCTION and HEADERDATA, body-length's INFILESIZE_LARGE, http-version's HTTP_VE
  - expected: `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "PASSWORD" "`
  - actual:   `("URL" "PROTOCOLS_STR" "REDIR_PROTOCOLS_STR" "PROTOCOLS" "REDIR_PROTOCOLS" "NOSIGNAL" "QUICK_EXIT" "MAXREDIRS" "WRITEFUNCTION" "WRITEDATA" "ERRORBUFFER" "CURLU" "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD" "HTTPHEADER" "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST" "USERAGENT" "TIMEOUT_MS" "CONNECTTIMEOUT_MS" "MAXFILESIZE_LARGE" "CAINFO" "CAPATH" "SSL_VERIFYPEER" "SSL_VERIFYHOST" "PROXY" "NOPROXY" "FORBID_REUSE" "HEADERFUNCTION" "HEADERDATA" "INFILESIZE_LARGE" "HTTP_VERSION" "HTTPAUTH" "USERNAME" "`
- request-field-options, written out: url's CURLU; method's NOBODY and CUSTOMREQUEST, and a streamed body's POST and UPLOAD; headers' HTTPHEADER; body's POSTFIELDSIZE_LARGE and COPYPOSTFIELDS, then a streamed one's READFUNCTION, READDATA, SEEKFUNCTION, SEEKDATA, PREREQFUNCTION, PREREQDATA and FRESH_CONNECT; user-agent's USERAGENT; timeout-ms's TIMEOUT_MS; connect-timeout-ms's CONNECTTIMEOUT_MS; body
  - expected: `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credentials "HTTPAUTH`
  - actual:   `((url "CURLU") (method "NOBODY" "CUSTOMREQUEST" "POST" "UPLOAD") (headers "HTTPHEADER") (body "POSTFIELDSIZE_LARGE" "COPYPOSTFIELDS" "READFUNCTION" "READDATA" "SEEKFUNCTION" "SEEKDATA" "PREREQFUNCTION" "PREREQDATA" "FRESH_CONNECT" "MIMEPOST") (user-agent "USERAGENT") (timeout-ms "TIMEOUT_MS") (connect-timeout-ms "CONNECTTIMEOUT_MS") (body-limit "MAXFILESIZE_LARGE") (ca-file "CAINFO" "CAPATH") (verify "SSL_VERIFYPEER" "SSL_VERIFYHOST") (proxy "PROXY" "NOPROXY" "FORBID_REUSE") (stream-buffer "HEADERFUNCTION" "HEADERDATA") (body-length "INFILESIZE_LARGE") (http-version "HTTP_VERSION") (credential`
- every option set-transfer-options! sets is an owned option, written as a literal or through field-option, but for those set by (car setting): three in the loop over method-settings' answer for the plan's method, body and body-length, two, a string's and a number's, in the loop over proxy-settings' answer for the plan's proxy, proxy CA file and proxy verification, one in the loop over version-setti
  - expected: `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 3) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`
  - actual:   `(() (((method-settings (plan-method plan) (plan-body plan) (plan-body-length plan)) 4) ((proxy-settings (plan-proxy plan) (plan-proxy-ca-file plan) (plan-proxy-verify plan)) 2) ((version-settings (plan-http-version plan)) 1) ((credentials-settings (plan-credentials plan)) 2) ((jar-settings (plan-share plan)) 2)))`

### tests/test-unsupported.sps: FAIL tests/test-unsupported.sps (exit 1); 28 failing, 28 by the kind alone


### tests/test-upload.sps: FAIL tests/test-upload.sps (exit 1); 6 failing, 6 by the kind alone


### tests/test-url-location.sps: FAIL tests/test-url-location.sps (exit 1); 195 failing, 195 by the kind alone


### tests/test-url-parts.sps: FAIL tests/test-url-parts.sps (exit 1); 135 failing, 135 by the kind alone


### tests/test-url.sps: FAIL tests/test-url.sps (exit 1); 118 failing, 118 by the kind alone


### tests/test-version.sps: FAIL tests/test-version.sps (exit 1); 3 failing, 3 by the kind alone


