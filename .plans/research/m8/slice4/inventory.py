#!/usr/bin/env python3
"""inventory.py: writes inventory.sexp, one list per export of (curl),
(curl unsupported) and (http-client), for M8 slice 4's docs.

Read-only over the tree. It takes:
  - logs/kinds.txt, each export and its kind as Chez saw it (kinds.sps);
  - each public library's export form, for each export's comment block, its
    signature line(s), the prose under it, and the block's citations;
  - RAISES below, written by hand from reading the code, each with a
    citation, and COMMENT_VS_CODE, where the comment and the code disagree.

Run from the repository root: python3 .plans/research/m8/slice4/inventory.py
"""
import re
import sys

ROOT = "."
OUT = ".plans/research/m8/slice4/inventory.sexp"
KINDS = ".plans/research/m8/slice4/logs/kinds.txt"

# --- the comment blocks ------------------------------------------------------

def export_form(path, start, end):
    """Lines START..END (1-based, inclusive) of PATH, numbered."""
    with open(path) as f:
        lines = f.read().split("\n")
    return [(i, lines[i - 1]) for i in range(start, end + 1)]

COMMENT = re.compile(r"^\s*;;( ?)(.*)$")
SECTION = re.compile(r"^\s*;; ---\s*(.*?)\s*-*\s*$")

def blocks(numbered):
    """Each comment block and the names that follow it: (section, block,
    names), block a list of (line, text after ';; ')."""
    out = []
    section = None
    block = []
    names = []
    for n, line in numbered:
        s = line.strip()
        m = SECTION.match(line)
        if m and s.startswith(";; ---"):
            if names:
                out.append((section, block, names))
                block, names = [], []
            section = (n, m.group(1))
            continue
        if s.startswith(";;"):
            if names:
                out.append((section, block, names))
                block, names = [], []
            c = COMMENT.match(line)
            block.append((n, c.group(2)))
            continue
        if not s:
            continue
        for tok in re.split(r"[\s()]+", s):
            if tok and tok not in ("export", "library", "(library"):
                names.append((n, tok))
    if names:
        out.append((section, block, names))
    return out

IDENT = r"[&a-zA-Z0-9!?*+<>=/-]+"

def sig_start(text, name):
    """Whether TEXT starts a signature for NAME: 'NAME : ...', a grouped
    'A, B, NAME :' line, or a condition type's 'NAME: ...'."""
    t = text.strip()
    if re.match(re.escape(name) + r" :( |$)", t):
        return True
    if name.startswith("&") and t.startswith(name + ":"):
        return True
    m = re.match(r"^((?:" + IDENT + r", )+" + IDENT + r") :", t)
    if m and name in [x.strip() for x in m.group(1).split(",")]:
        return True
    return False

def any_sig(text):
    t = text.strip()
    return bool(re.match(r"^" + IDENT + r" :( |$)", t)
                or re.match(r"^(?:" + IDENT + r", )+" + IDENT + r" :", t)
                or re.match(r"^&" + IDENT + r":", t))

def signature_and_prose(block, name, kind):
    """NAME's signature lines and the prose under it, from BLOCK, and the
    block's lines before its first signature."""
    idx = None
    for i, (n, t) in enumerate(block):
        if sig_start(t, name):
            idx = i
            break
    first = None
    for i, (n, t) in enumerate(block):
        if any_sig(t) and not t.startswith("  "):
            first = i
            break
        if any_sig(t):
            first = i
            break
    intro = block[:first] if first is not None else block[:]
    if idx is None:
        return None, [], intro
    sig = [block[idx]]
    j = idx + 1
    joined = block[idx][1]
    if kind == "procedure":
        while j < len(block) and "->" not in joined:
            sig.append(block[j])
            joined += " " + block[j][1]
            j += 1
    prose = []
    while j < len(block) and not (any_sig(block[j][1]) and not block[j][1].startswith("   ")):
        prose.append(block[j])
        j += 1
    return sig, prose, intro

CITE = re.compile(
    r"ADR-\d{4}"
    r"|[Tt]he M\d+ plan(?:, sections? [\d.]+(?: (?:and|to) [\d.]+)?)?"
    r"|M\d+ plan(?:, sections? [\d.]+(?: (?:and|to) [\d.]+)?)?"
    r"|\bM\d+ slice \d+(?:'s review)?"
    r"|\bslice \d+(?:'s (?:second )?review)?"
    r"|the slice's (?:review|measurement)"
    r"|\.plans/[^\s,;)]+|research/[^\s,;)]+"
    r"|\d{4}-\d{2}-\d{2}"
    r"|traps\.md|AGENTS\.md"
    r"|decided by the maintainer")

def cites(lines):
    found = []
    for n, t in lines:
        for m in CITE.finditer(t):
            found.append((n, m.group(0)))
    return found

# --- the data written by hand --------------------------------------------------

LOAD = ("&curl-library-unavailable",
        "invalid-override not-found load-failed below-floor no-ssl missing-api",
        "src/curl/private/native.sls:200-203 (raised again at every later reference); "
        "discovery.sls:68,81; native.sls:310,574,588,615,707; verify.sls:36,41,61,64",
        "at the first reference to the binding in a program, before the program's body: "
        "logs/load-probe.txt")
NOLOAD = ("none-at-load", "", "logs/load-probe.txt",
          "the binding loads nothing: its library defines condition or record types alone "
          "(curl.sls:15, libcurl-info.sls:7-10)")

def av(cite, note):
    return ("assertion-violation", "", cite, note)

def cre(reasons, cite, note=""):
    return ("&curl-request-error", reasons, cite, note)

CHECKED = "src/curl/private/conditions.sls:141-145"
HCHECKED = "src/http-client/private/conditions.sls:87-91"

REQUEST_CHECKS = [
    av("src/curl/private/transfer.sls:1214-1263 (checked-request); 497-517 (headers); "
       "774-791 (credentials); 1352,1393-1417 (multipart shape)",
       "a value of the wrong type or shape, named by its kind"),
    cre("unknown-key missing-value repeated-key", "src/curl/private/transfer.sls:875-878",
        "field key, first of all"),
    cre("body-not-allowed", "src/curl/private/transfer.sls:1264-1265", "field body"),
    cre("body-length-without-stream", "src/curl/private/transfer.sls:1266-1267"),
    cre("stream-with-rounds", "src/curl/private/transfer.sls:1268-1269, 1730-1732",
        "beside the private follow field, or an Expect header holding 100-continue"),
    cre("not-a-token proxy-authorization-header embedded-nul line-break not-latin-1 "
        "surrounding-whitespace duplicates-field framing-header",
        "src/curl/private/transfer.sls:520-538 (snapshot), 403-428",
        "fields header-name, header-value or user-agent"),
    cre("credentials-bytes credentials-empty credentials-beside-authorization digest-with-stream",
        "src/curl/private/transfer.sls:836-855", "field credentials"),
    cre("cookie-beside-jar", "src/curl/private/transfer.sls:1657-1662", "field header-name"),
    cre("multipart-content-type", "src/curl/private/transfer.sls:1469-1473", "field header-name"),
    cre("multipart-empty part-bytes part-empty part-file",
        "src/curl/private/transfer.sls:1355, 1313-1321, 1368-1384, 1450-1458",
        "field body, value (part I FIELD); part-file for a path empty, holding U+0000, or "
        "naming no regular file by stat once resolved against current-directory"),
    cre("embedded-nul pkcs11-url", "src/curl/private/transfer.sls:594-608",
        "fields ca-file and proxy-ca-file"),
]

SUBMIT_CHECKS = [
    av("src/curl/private/transfer.sls:4282-4283", "not a request"),
    ("(as make-curl-request)", "", "src/curl/private/transfer.sls:4284-4302",
     "the header, CA file, credentials, Expect, cookie and multipart checks again, on the "
     "submit's own copies: snapshot, ca-file-copy, credentials-copy, path-copy, "
     "check-expect-round, check-credentials, check-cookie-beside-jar, "
     "check-multipart-content-type, multipart-copy"),
    cre("multipart-unsupported", "src/curl/private/transfer.sls:4300, 4334-4340",
        "field body, value multipart, irritants the load's mime probe"),
    cre("part-file", "src/curl/private/transfer.sls:4302, 1452, 1457-1458",
        "a path not absolute, or no regular file by stat again"),
    cre("environment-override keychain-fallback", "src/curl/private/transfer.sls:4303, 4309, 689-706",
        "fields ca-file and proxy-ca-file"),
    cre("proxy-url proxy-scheme proxy-url-parts credentials-bytes credentials-empty",
        "src/curl/private/transfer.sls:4304, 4461-4523", "field proxy, never the URL"),
    cre("https-proxy-unsupported", "src/curl/private/transfer.sls:4305-4306, 4541-4543"),
    cre("proxy-tls-without-https-proxy", "src/curl/private/transfer.sls:4307-4308, 4553-4558",
        "fields proxy-ca-file and proxy-verify"),
    ("&curl-url-error", "scheme-not-http embedded-nul not-utf-8 malformed-input and libcurl's CURLUcode names",
     "src/curl/private/transfer.sls:4310-4317; url.sls:265-270, 95-98, 118-119, 135-137, 156-157",
     "the URL's parse and scheme"),
    cre("credentials-beside-userinfo", "src/curl/private/transfer.sls:4316, 4604-4606"),
    cre("prior-knowledge-over-https", "src/curl/private/transfer.sls:4318, 4617-4619"),
    cre("prior-knowledge-through-proxy", "src/curl/private/transfer.sls:4319, 4568-4570"),
    cre("proxy-tls-in-tls", "src/curl/private/transfer.sls:4320, 4579-4588",
        "Ubuntu's 8.5.0 with GnuTLS, and 7.85.0 unless http/1.1 is asked"),
]

URL_COMMON = [
    av("src/curl/private/url.sls:92-93", "a URL that is no string"),
    ("&curl-url-error", "libcurl's CURLUcode names (or #f for a code the floor lacks)",
     "src/curl/private/url.sls:76-77, 156-157, 176-178", "libcurl's refusal"),
    ("&curl-url-error", "embedded-nul", "src/curl/private/url.sls:95-98", "a string holding U+0000"),
    ("&curl-url-error", "not-utf-8", "src/curl/private/url.sls:132-137", "an answer whose bytes are not UTF-8"),
    ("&curl-url-error", "malformed-input", "src/curl/private/url.sls:117-119",
     "a URL past 8,000,000 chars, at once, as libcurl refuses it"),
]

RESPONSE_OUTCOME = [
    ("&curl-transfer-error", "perform-failed body-limit header-limit callback-raised setopt-failed "
     "unknown-option no-handle cancelled stopped pause-failed body-length-mismatch body-not-replayable "
     "part-file mime-failed",
     "src/curl/private/engine.sls:870-872; conditions.sls:918-931 (classed by code: &curl-timeout, "
     "&curl-connect-error, &curl-send-receive-error, &curl-tls-error, &curl-protocol-error, "
     "&curl-too-large)", "the outcome, raised"),
    ("&curl-engine-error", "failed", "src/curl/private/engine.sls:2194-2234", "every token a failed engine held"),
    cre("cookie-jar-closed cookie-jar-engine", "src/curl/private/engine.sls:2055-2059",
        "a jar closed across the submit, as the transfer is set up"),
]

def tok(*more):
    return [LOAD, av("src/curl/private/engine.sls:578-579", "not a token")] + list(more)

DEADLINE = av("src/curl/private/engine.sls:265-267", "a bound that is no natural number of ms")
CRIT = av("src/curl/private/engine.sls:230-233, 247-248", "a wait inside a critical section")
STREAM = av("src/curl/private/engine.sls:889-893", "a token whose request does not stream its response")
UPLOAD = av("src/curl/private/engine.sls:1123-1127", "a token whose request does not stream its body")
JARS = ("&curl-engine-error", "stopped failed", "src/curl/private/engine.sls:1426-1440",
        "the jar's engine stopping, stopped or failed")

HTTP_CALL = [
    LOAD,
    ("&http-exchange (compounded)", "", "src/http-client.sls:635-661",
     "every raise of the call carries the call's method, URL, history and transfer count"),
    av("src/http-client.sls:595-596, 644", "not a session"),
    ("&curl-url-error", "malformed-input", "src/http-client.sls:649-650", "a URL past 8,000,000 chars"),
    ("&http-request-error", "unknown-key missing-value repeated-key", "src/http-client/private/call.sls:120-131", "field key"),
    ("&http-request-error", "not-a-body", "src/http-client/private/call.sls:569-574", "field body"),
    ("&http-request-error", "not-name-value-pairs", "src/http-client/private/call.sls:597-600", "field form or params"),
    ("&http-request-error", "not-a-redirect-count not-a-boolean not-a-retry-policy",
     "src/http-client/private/call.sls:297-318, 675-677"),
    ("&http-request-error", "body-and-form", "src/http-client/private/call.sls:679-680", "field form"),
    ("&http-request-error", "multipart-beside-body", "src/http-client/private/call.sls:681-683", "field multipart"),
    ("&http-request-error", "body-not-allowed", "src/http-client/private/call.sls:684-686",
     "field body, form or multipart, value the method"),
    ("(make-curl-request's refusals)", "", "src/http-client/private/call.sls:704-708, 729-753",
     "the merged request, as the low level raises them: its assertion violations and &curl-request-error"),
    ("&curl-url-error", "", "src/http-client/private/call.sls:725-728", "params appended, the URL read back"),
    av("src/http-client/private/drive.sls:274-305", "a call made inside a critical section, before anything is submitted"),
    ("&http-timeout", "", "src/http-client/private/exchange.sls:494, 521, 566-568, 1154",
     "the call's timeout-ms passed; compounded with &curl-timeout when libcurl's 28 was the bound's"),
    ("&http-redirect-error", "too-many-redirects bad-location insecure-redirect body-not-replayable",
     "src/http-client/private/exchange.sls:707-730", "bad-location compounded with the URL function's &curl-url-error"),
    ("(curl-submit's refusals, each hop's)", "", "src/curl/private/transfer.sls:4281-4326",
     "a hop's prior-knowledge-over-https, credentials-beside-userinfo or proxy-tls-in-tls among them"),
    ("(the token's outcome)", "", "src/curl/private/engine.sls:870-872",
     "&curl-transfer-error and its classes, &curl-engine-error"),
]

PRODUCER = [
    av("src/http-client/private/drive.sls:631-640", "a producer's answer that is no bytevector of a byte or more nor the eof object"),
    ("&http-request-error", "body-length-mismatch", "src/http-client/private/drive.sls:615-627",
     "field body, value the producer"),
]

RAISES = {
    "loaded-libcurl": [LOAD],
    "make-curl-request": [LOAD] + REQUEST_CHECKS,
    "curl-request-with": [LOAD, av("src/curl/private/transfer.sls:1791-1792", "not a request")]
                         + REQUEST_CHECKS + [("note", "", "src/curl/private/transfer.sls:1749-1759, 1220-1221",
                                              "a multipart body it is not given is kept, not copied or stat'd again")],
    "curl-request?": [LOAD],
    "curl-url-part": [LOAD] + URL_COMMON + [av("src/curl/private/url.sls:363-364", "a part it does not read")],
    "curl-url-append-query": [LOAD] + URL_COMMON + [
        ("&curl-url-error", "query-not-kept", "src/curl/private/url.sls:441-443", "PART would not come back as written, one holding #")],
    "curl-url-resolve": [LOAD] + URL_COMMON + [
        ("&curl-url-error", "embedded-nul", "src/curl/private/url.sls:463-466", "a bytevector holding 0x00, named as Latin-1")],
    "curl-url-with-fragment": [LOAD] + URL_COMMON + [
        av("src/curl/private/url.sls:560-561", "a fragment that is no string, bytevector or #f"),
        ("&curl-url-error", "embedded-nul", "src/curl/private/url.sls:463-466", "a bytevector holding 0x00")],
    "curl-response?": [LOAD],
    "make-curl-engine": [LOAD, av("src/curl/private/engine.sls:787, 230-233", "inside a critical section"),
                         ("&curl-engine-error", "failed", "src/curl/private/engine.sls:793-796",
                          "its thread made no multi handle")],
    "curl-engine?": [LOAD],
    "curl-engine-stop": [LOAD, av("src/curl/private/engine.sls:1393", "not an engine"),
                         av("src/curl/private/engine.sls:1394", "inside a critical section")],
    "curl-submit": [LOAD, av("src/curl/private/engine.sls:826-833",
                             "not an engine, a mailbox, a callback; a callback without a mailbox")]
                   + SUBMIT_CHECKS + [
        ("&curl-engine-error", "stopped failed", "src/curl/private/engine.sls:850-851"),
        cre("cookie-jar-engine cookie-jar-closed", "src/curl/private/engine.sls:842-845", "field cookie-jar")],
    "curl-request-check": [LOAD] + SUBMIT_CHECKS + [
        ("note", "", "src/curl/private/transfer.sls:4632-4634", "who curl-request-check; no engine's or jar's refusal")],
    "make-curl-cookie-jar": [LOAD, av("src/curl/private/engine.sls:1468-1469", "not an engine; inside a critical section"),
                             JARS,
                             ("&error (Chez's, no &curl-error)", "", "src/curl/private/engine.sls:1655-1673",
                              "curl_share_init or curl_easy_init NULL, or a curl_share_setopt code"),
                             ("&curl-transfer-error", "setopt-failed", "src/curl/private/transfer.sls:2871-2872, 2443-2445",
                              "SHARE refused on the jar's own handle")],
    "curl-cookie-jar?": [LOAD],
    "curl-cookie-jar-cookies": [LOAD, av("src/curl/private/engine.sls:1483-1484", "not a jar; inside a critical section"),
                                JARS, cre("cookie-jar-closed", "src/curl/private/engine.sls:1625, 1637-1639", "field cookie-jar"),
                                ("&error (Chez's, no &curl-error)", "", "src/curl/private/transfer.sls:2916-2918",
                                 "CURLINFO_COOKIELIST answered a code")],
    "curl-cookie-jar-load!": [LOAD, av("src/curl/private/engine.sls:1501-1502; transfer.sls:2844-2853",
                                       "not a jar; inside a critical section; lines not a list of strings"),
                              cre("cookie-line", "src/curl/private/transfer.sls:2854-2862",
                                  "field lines, value the line's index; nothing loaded"),
                              JARS, cre("cookie-jar-closed", "src/curl/private/engine.sls:1629, 1637-1639"),
                              ("&error (Chez's, no &curl-error)", "", "src/curl/private/transfer.sls:2895-2897",
                               "CURLOPT_COOKIELIST answered a code; the lines before it loaded")],
    "curl-cookie-jar-close!": [LOAD, av("src/curl/private/engine.sls:1517-1518", "not a jar; inside a critical section"), JARS],
    "curl-token?": [LOAD],
    "curl-token-await": tok(av("src/curl/private/engine.sls:864", "inside a critical section"), *RESPONSE_OUTCOME),
    "curl-token-wait": tok(DEADLINE, CRIT),
    "curl-token-cancel": tok(),
    "curl-token-done?": tok(),
    "curl-token-outcome": tok(),
    "curl-token-head-wait": tok(STREAM, DEADLINE, CRIT),
    "curl-token-head": tok(STREAM),
    "curl-head?": [LOAD],
    "curl-token-next-piece": tok(STREAM, DEADLINE, av("src/curl/private/engine.sls:976", "a wait inside a critical section")),
    "curl-token-body-port": tok(STREAM, av("src/curl/private/engine.sls:1007-1008", "a second port of the token"),
                                ("(its reads) the outcome's condition", "", "src/curl/private/engine.sls:1035-1037",
                                 "a transfer that failed, every read after"),
                                ("&curl-wrong-thread", "", "src/curl/private/engine.sls:1010-1017",
                                 "a read that reaches read!, or a close, from another thread"),
                                av("src/curl/private/engine.sls:1039", "a read that waits inside a critical section")),
    "curl-token-room-wait": tok(UPLOAD, DEADLINE, CRIT),
    "curl-token-put-piece!": tok(UPLOAD, av("src/curl/private/engine.sls:1200-1201", "a piece that is no bytevector of a byte or more"),
                                 av("src/curl/private/engine.sls:1223-1224", "a put after curl-token-end-body! on a live token"),
                                 DEADLINE, av("src/curl/private/engine.sls:1233", "a wait inside a critical section"),
                                 cre("body-length-mismatch", "src/curl/private/engine.sls:1216-1222",
                                     "field body-length; the piece not taken; the transfer then fails so")),
    "curl-token-end-body!": tok(UPLOAD),
    "curl-token-body-count": tok(UPLOAD),
    "make-curl-mailbox": [LOAD],
    "curl-mailbox?": [LOAD],
    "curl-mailbox-take": [LOAD, av("src/curl/private/engine.sls:1290-1291", "not a mailbox"), DEADLINE, CRIT],
    "curl-mailbox-deliver": [LOAD, av("src/curl/private/engine.sls:1290-1291", "not a mailbox"), DEADLINE, CRIT,
                             ("(the callback's raise)", "", "src/curl/private/engine.sls:1349-1350", "leaves through it")],
    "curl-request-with-options": [LOAD, av("src/curl/private/transfer.sls:3047, 2957-2967, 2992-3023",
                                           "not a request; options not (NAME . VALUE) pairs; a value of the wrong shape or range"),
                                  cre("embedded-nul unknown-option owned-option unsupported-type repeated-option line-break",
                                      "src/curl/private/transfer.sls:3054-3061, 2994-2996, 2973-2980",
                                      "field options, value the option's name as given"),
                                  ("(curl-request-with's checks of the request's own fields)", "",
                                   "src/curl/private/transfer.sls:3051", "")],
    # (http-client)
    "make-http-session": [LOAD,
        ("&http-request-error", "unknown-key missing-value repeated-key", "src/http-client/private/call.sls:120-131"),
        ("&http-request-error", "not-a-redirect-count not-a-boolean not-a-retry-policy",
         "src/http-client/private/call.sls:297-318, 338-339", "fields redirects, allow-downgrade, retry"),
        ("&http-request-error", "not-a-boolean", "src/http-client/private/call.sls:345-352", "field cookies"),
        ("(make-curl-request's refusals)", "", "src/http-client/private/call.sls:559-561", "its request keys, as raised"),
        ("(make-curl-engine's refusals)", "", "src/http-client.sls:668"),
        ("(with cookies) make-curl-cookie-jar's and cookie-beside-jar", "", "src/http-client/private/call.sls:527-533",
         "the engine it made stopped first")],
    "http-session?": [LOAD],
    "http-session-close": [LOAD, av("src/http-client.sls:595-596, 685", "not a session"),
                           ("(curl-engine-stop's refusals)", "", "src/http-client.sls:686", "inside a critical section")],
    "call-with-http-session": [LOAD, av("src/http-client.sls:689-691, 698-700", "no procedure last"),
                               ("(make-http-session's refusals)", "", "src/http-client.sls:701"),
                               ("(PROC's raise)", "", "src/http-client.sls:702-705", "after the session's close")],
    "http-session-cookies": [LOAD, av("src/http-client.sls:673-676", "not a session; a session without cookies"),
                             ("(curl-cookie-jar-cookies' refusals)", "", "src/http-client.sls:678-679",
                              "&curl-engine-error stopped for a closed session")],
    "http-session-load-cookies!": [LOAD, av("src/http-client.sls:673-676", "not a session; a session without cookies"),
                                   ("(curl-cookie-jar-load!'s refusals)", "", "src/http-client.sls:681-682",
                                    "cookie-line; &curl-engine-error stopped for a closed session")],
    "http-request": HTTP_CALL + PRODUCER,
    "call-with-response-port": [av("src/http-client.sls:728-736", "no procedure last, before anything else"),
                                av("src/http-client/private/call.sls:690-693", "a stream-buffer of #f")] + HTTP_CALL + PRODUCER + [
        ("(its port's reads) the transfer's condition, compounded", "", "src/http-client/private/drive.sls:900-940",
         "with &http-exchange, and &http-timeout for the bound's 28"),
        av("src/http-client/private/drive.sls:919, 929, 938", "a read from another thread, from the producer, or inside a critical section")],
    "make-http-retry": [LOAD,
        ("&http-request-error", "unknown-key missing-value repeated-key", "src/http-client/private/call.sls:452, 120-131"),
        ("&http-request-error", "not-an-attempt-count not-a-backoff not-a-boolean not-a-status-list not-a-method-list",
         "src/http-client/private/call.sls:455-481", "each field its key, in retry-keys' order")],
    "http-retry?": [LOAD],
    "call-with-request-group": [LOAD, av("src/http-client.sls:747; drive.sls:1128-1131", "inside a critical section, before anything"),
        av("src/http-client.sls:748-759", "no session, no procedure last"),
        ("&http-request-error", "unknown-key missing-value repeated-key not-a-limit", "src/http-client/private/call.sls:366-375"),
        ("(go) the call's checks, as http-request's", "", "src/http-client.sls:763-764",
         "compounded with &http-exchange; stream-in-group for a producer (call.sls:687-689)"),
        ("&http-group-error", "wrong-thread closed", "src/http-client/private/drive.sls:1188-1210",
         "go from another thread, or once PROC has returned"),
        ("(the join) the first call to fail no await answered", "", "src/http-client.sls:410-416", "as the call raised it")],
    "http-pending?": [LOAD],
    "http-await": [LOAD, av("src/http-client/private/drive.sls:1199-1201", "not a pending"),
                   ("&http-group-error", "wrong-thread", "src/http-client/private/drive.sls:1204-1210, 1739"),
                   av("src/http-client/private/drive.sls:1740, 1128-1131", "inside a critical section"),
                   ("(the call's failure)", "", "src/http-client/private/drive.sls:1752-1756", "as http-request raises it"),
                   ("&http-group-error", "cancelled", "src/http-client/private/drive.sls:1756, 1700-1720",
                    "a cancelled call, with its &http-exchange and its transfer's condition")],
    "http-pending-done?": [LOAD, av("src/http-client/private/drive.sls:1199-1201", "not a pending"),
                           ("&http-group-error", "wrong-thread", "src/http-client/private/drive.sls:1765"),
                           av("src/http-client/private/drive.sls:1766", "inside a critical section")],
    "http-pending-cancel": [LOAD, av("src/http-client/private/drive.sls:1199-1201", "not a pending"),
                            ("&http-group-error", "wrong-thread", "src/http-client/private/drive.sls:1784")],
    "http-parallel": [LOAD, av("src/http-client.sls:802", "inside a critical section, before anything"),
                      av("src/http-client.sls:803", "not a session"),
                      ("&http-request-error", "unknown-key missing-value repeated-key not-a-limit", "src/http-client.sls:804"),
                      av("src/http-client.sls:775-793", "specs, or a spec, not a list of a method, a URL, then keys"),
                      ("(each spec's call checks, as http-request's, then curl-request-check's)", "",
                       "src/http-client.sls:806-813, 653", "compounded with &http-exchange; stream-in-group for a producer"),
                      ("(the first call to fail)", "", "src/http-client.sls:474-476", "once the rest are cancelled and ended")],
    "http-response-header": [LOAD, av("src/http-client/private/exchange.sls:270-273", "not a response; a name that is no string")],
    "http-response-text": [LOAD, av("src/http-client/private/exchange.sls:286-292", "not a response; a body of #f")],
}

for v in ("http-get", "http-head", "http-post", "http-put", "http-patch", "http-delete"):
    RAISES[v] = [("(as http-request)", "", "src/http-client.sls:818-823", "")] + HTTP_CALL + PRODUCER

def accessor_entry(name, lib):
    if lib == "(curl)":
        if name.startswith("libcurl-info-"):
            return [NOLOAD, av("src/curl/private/libcurl-info.sls:73-77", "not a libcurl-info")]
        if name.startswith("curl-request-"):
            if name in ("curl-request-credentials", "curl-request-proxy", "curl-request-proxy-ca-file"):
                return [LOAD, av("src/curl/private/transfer.sls:1182-1201", "not a request")]
            return [LOAD, av("src/curl/private/transfer.sls:1134-1170", "not a request (checked-accessor)")]
        if name.startswith("curl-response-"):
            return [LOAD, av("src/curl/private/transfer.sls:1902-1913", "not a response")]
        if name.startswith("curl-head-"):
            return [LOAD, av("src/curl/private/transfer.sls:3244-3251", "not a head")]
        return [NOLOAD, av(CHECKED, "an argument of another kind, named by its kind")]
    if lib == "(http-client)":
        if name.startswith("http-response-"):
            return [LOAD, av("src/http-client/private/exchange.sls:251-264", "not a response")]
        return [NOLOAD, av(HCHECKED, "an argument of another kind, named by its kind")]
    return None

COMMENT_VS_CODE = {
    "curl-too-large?": "disagree: curl.sls:543 lists '63, 100, and the body limit'; the code classes header-limit too "
                       "(conditions.sls:31, 868-871, 921-923)",
    "&curl-too-large": "disagree: curl.sls:543 omits header-limit, which conditions.sls:921-923 classes too-large",
    "http-request-error-reasons": "disagree: http-client.sls:526-536 lists 17 reasons and omits body-length-mismatch, "
                                  "which the list holds (http-client/private/conditions.sls:136-141) and "
                                  "http-client.sls:271-272 names",
    "curl-url-with-fragment": "partly: the shared comment's 'a part that would not come back as written, one holding #' "
                              "(curl.sls:266-267) is curl-url-append-query's alone (url.sls:441-443); "
                              "curl-url-with-fragment makes no such check (url.sls:553-571)",
    "curl-url-part": "partly: the comment names no refusal for a PART it does not read, an assertion violation "
                     "(url.sls:363-364); the shared 'would not come back as written' clause is not this one's",
    "curl-url-resolve": "partly: the shared 'would not come back as written' clause (curl.sls:266-267) is not this one's",
    "curl-token-outcome": "partly: 'never raises' (curl.sls:383); it raises an assertion violation for what is no token "
                          "(engine.sls:560, 578-579), as every token procedure does",
    "make-curl-engine": "partly: the comment (curl.sls:292-294) names neither the refusal inside a critical section "
                        "(engine.sls:787) nor &curl-engine-error failed when its thread fails (engine.sls:793-796; "
                        "the private comment, engine.sls:617-621, names the second)",
    "curl-engine-stop": "partly: the comment (curl.sls:296-301) omits the refusal inside a critical section (engine.sls:1394)",
    "curl-submit": "partly: the comment (curl.sls:302-306) names only the callback without a mailbox; the request's "
                   "refusals are make-curl-request's comment's (curl.sls:192-198), the engine's curl-engine-stop's "
                   "(curl.sls:298-301), the jar's the cookie-jar key's (curl.sls:188-191); the private comment "
                   "(engine.sls:801-817) lists them all",
    "curl-request-check": "partly: the comment (curl.sls:308-313) lists the headers', user agent's, credentials', CA "
                          "file's, environment's, URL's and userinfo's checks; the code runs request-checks whole "
                          "(transfer.sls:4281-4326): the proxy's, the multipart body's (multipart-unsupported, part-file, "
                          "multipart-content-type), prior knowledge's, proxy-tls-in-tls, cookie-beside-jar and "
                          "stream-with-rounds too",
    "make-curl-request": "partly: (curl)'s comment names the multipart rules but not their reasons (part-bytes, "
                         "part-empty, multipart-empty, part-file, multipart-content-type); the headers' refusals "
                         "(not-a-token, embedded-nul, line-break, not-latin-1, surrounding-whitespace, duplicates-field, "
                         "framing-header) and the CA file's embedded-nul are named only in transfer.sls's private comment "
                         "(911-919, 1063-1082, 585-589); the reason symbols are listed in conditions.sls:340-529",
    "curl-request-with": "agree: the url key and the kept multipart body are named (curl.sls:199-205); its refusals "
                         "are make-curl-request's, as for that one",
    "make-curl-cookie-jar": "partly: the comment (curl.sls:322-329) names the engine's refusal; libcurl's refusals "
                            "raise Chez's &error, not a chez-curl condition (engine.sls:1655-1673), which no public "
                            "comment says",
    "curl-cookie-jar-load!": "partly: a COOKIELIST code raises Chez's &error (transfer.sls:2895-2897), not a "
                             "chez-curl condition; the public comment does not say so",
    "curl-cookie-jar-cookies": "partly: a CURLINFO_COOKIELIST code raises Chez's &error (transfer.sls:2916-2918); the "
                               "public comment does not say so",
    "&curl-embedded-nul": "note: a backstop behind the URL's and the request's own U+0000 checks (url.sls:95-98, "
                          "transfer.sls:599-602, 3054): a caller meets &curl-url-error or &curl-request-error "
                          "embedded-nul first (tests/test-url.sps:570-576)",
    "curl-embedded-nul?": "note: see &curl-embedded-nul",
    "curl-embedded-nul-string": "note: see &curl-embedded-nul",
    "curl-transfer-error-request-size": "agree: the multipart clause matches conditions.sls:706-708",
    "http-pending-cancel": "agree: no critical-section refusal is claimed, and none is made (drive.sls:1781-1791)",
}

def topic_of(name, lib, section):
    sec = section[1] if section else ""
    if lib == "(curl unsupported)":
        return "the hatch"
    if lib == "(curl)":
        if name == "loaded-libcurl" or name.startswith("libcurl-info"):
            return "TLS and the environment: finding libcurl"
        if name.startswith("&") or name.endswith("?") and any(name.startswith(p) for p in (
                "curl-error", "curl-library-unavailable", "curl-wrong-thread", "curl-embedded-nul", "curl-url-error",
                "curl-request-error", "curl-transfer-error", "curl-timeout", "curl-connect-error",
                "curl-send-receive-error", "curl-tls-error", "curl-protocol-error", "curl-too-large",
                "curl-engine-error")):
            return "errors"
        for p in ("curl-library-unavailable-", "curl-wrong-thread-", "curl-embedded-nul-", "curl-url-error-",
                  "curl-request-error-", "curl-transfer-error-", "curl-engine-error-"):
            if name.startswith(p):
                return "errors"
        if "URLs" in sec:
            return "URLs (no topic in the plan's list)"
        if "request (" in sec or name in ("curl-request?",):
            return "the low level: requests"
        if "response" in sec and "streamed" not in sec:
            return "the low level: tokens (a response)"
        if "engine" in sec:
            return "the low level: engines"
        if "cookie jar" in sec:
            return "the low level: jars"
        if "streamed" in sec:
            return "the low level: streams"
        if "token" in sec or "mailbox" in sec:
            return "the low level: tokens"
    if lib == "(http-client)":
        if name.startswith("&") or "-error" in name or name.startswith("http-timeout") or name.startswith("http-exchange") \
                or name == "http-error?":
            return "errors"
        if name in ("http-session-cookies", "http-session-load-cookies!"):
            return "the high level: cookies"
        if "session" in name:
            return "the high level: sessions"
        if name in ("call-with-response-port",):
            return "the high level: streams"
        if "retry" in name:
            return "the high level: redirects and retries"
        if name in ("call-with-request-group", "http-pending?", "http-await", "http-pending-done?",
                    "http-pending-cancel", "http-parallel"):
            return "the high level: groups"
        if name.startswith("http-response") or name.startswith("http-") :
            return "the high level: verbs"
    return "?"

# --- writing -------------------------------------------------------------------

def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def lines_sexp(lines):
    return "(" + " ".join("(%d %s)" % (n, q(t)) for n, t in lines) + ")"

def main():
    kinds = {}
    order = []
    with open(KINDS) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            m = re.match(r"^\(\((curl unsupported|curl|http-client)\) (\S+) (\S+)", line)
            lib, name, kind = "(" + m.group(1) + ")", m.group(2), m.group(3).rstrip(")")
            if name.startswith("&"):
                kind = "condition-type"
            kinds[(lib, name)] = kind
            order.append((lib, name))
    sources = {
        "(curl)": ("src/curl.sls", 21, 556),
        "(http-client)": ("src/http-client.sls", 158, 585),
        "(curl unsupported)": ("src/curl/unsupported.sls", 32, 46),
    }
    headers = {"(curl)": ("src/curl.sls", 2, 19), "(http-client)": ("src/http-client.sls", 2, 156),
               "(curl unsupported)": ("src/curl/unsupported.sls", 2, 26)}
    found = {}
    for lib, (path, a, b) in sources.items():
        if lib == "(curl unsupported)":
            numbered = export_form(path, a, b)
            block = [(n, COMMENT.match(t).group(2)) for n, t in numbered if COMMENT.match(t)]
            found[(lib, "curl-request-with-options")] = (path, None, block, ["curl-request-with-options"])
            continue
        for section, block, names in blocks(export_form(path, a, b)):
            for n, name in names:
                found[(lib, name)] = (path, section, block, [x for _, x in names])
    out = []
    out.append(";; inventory.sexp: every export of (curl), (curl unsupported) and (http-client), on")
    out.append(";; feat/m8-docs at fb62a0b (main), as Chez's library-exports lists them (logs/exports.txt),")
    out.append(";; each its kind as Chez evaluates it (kinds.sps, logs/kinds.txt). Written by inventory.py from")
    out.append(";; the export forms and a hand-written table of what each raises, each with a code citation.")
    out.append(";; Each entry: (export NAME (library L) (kind K) (topic T) (signature-at F:N) (signature")
    out.append(";; LINES) (prose LINES) (block-intro LINES) (group NAMES) (section (N TEXT)) (raises")
    out.append(";; (TYPE REASONS CITATION NOTE) ...) (comment-vs-code TEXT) (cites ((N TEXT) ...))).")
    out.append(";; LINES are ((LINE TEXT) ...), TEXT the comment after ';; ' verbatim. cites lists each")
    out.append(";; ADR, plan, slice, research path, date or record the entry's comment, block or section")
    out.append(";; names: the reference must copy none. Every binding also refuses an unthreaded Chez or one")
    out.append(";; older than 10.4.0 at import, a syntax violation (require-threaded.sls:79-89).")
    missing = []
    for lib, name in order:
        kind = kinds[(lib, name)]
        hit = found.get((lib, name))
        if not hit:
            missing.append((lib, name))
            continue
        path, section, block, group = hit
        sig, prose, intro = signature_and_prose(block, name, "procedure" if kind == "procedure" else kind)
        raises = RAISES.get(name)
        if raises is None:
            raises = accessor_entry(name, lib)
        if raises is None:
            if kind == "condition-type":
                raises = [NOLOAD, ("none", "", "", "a condition type: syntax, not a procedure")]
            elif kind == "value":
                raises = [NOLOAD, ("none", "", "", "a list of symbols")]
            elif name.endswith("?") and lib == "(http-client)" and name.startswith("http-") and kind == "procedure":
                raises = [NOLOAD, ("none", "", "", "a predicate")]
            elif name.endswith("?"):
                raises = [NOLOAD, ("none", "", "", "a predicate")]
            else:
                raises = [("UNKNOWN", "", "", "")]
        # A predicate of a record that imports native loads it (load-probe): fix up by library.
        if name in ("curl-request?", "curl-response?", "curl-engine?", "curl-cookie-jar?", "curl-token?",
                    "curl-head?", "curl-mailbox?", "http-session?", "http-retry?", "http-pending?", "http-response?"):
            raises = [LOAD]
        cv = COMMENT_VS_CODE.get(name, "agree, as far as read")
        all_lines = (sig or []) + prose + intro + ([section] if section else [])
        entry_cites = cites(all_lines)
        sigat = "%s:%d" % (path, sig[0][0]) if sig else "none"
        raises = [tuple(x) + ("",) * (4 - len(x)) for x in raises]
        r = " ".join("(%s %s %s %s)" % (q(t), q(rs), q(c), q(nt)) for (t, rs, c, nt) in raises)
        out.append("(export %s" % name)
        out.append("  (library %s) (kind %s) (topic %s)" % (lib, kind, q(topic_of(name, lib, section))))
        out.append("  (signature-at %s)" % q(sigat))
        out.append("  (signature %s)" % (lines_sexp(sig) if sig else "()"))
        out.append("  (prose %s)" % lines_sexp(prose))
        out.append("  (block-intro %s)" % lines_sexp(intro))
        out.append("  (group (%s))" % " ".join(group))
        out.append("  (section %s)" % ("(%d %s)" % (section[0], q(section[1])) if section else "#f"))
        out.append("  (raises %s)" % r)
        out.append("  (comment-vs-code %s)" % q(cv))
        out.append("  (cites %s))" % lines_sexp(entry_cites))
    with open(OUT, "w") as f:
        f.write("\n".join(out) + "\n")
    if missing:
        print("no block for:", missing, file=sys.stderr)
        sys.exit(1)
    print("wrote", OUT, len(order), "exports")

main()
