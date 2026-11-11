#!/usr/bin/env python3
"""Build the review's plant directories under build/m8s6-review/plants/.

Each plant is a directory holding Akku.manifest, Akku.lock and CHANGELOG.md,
copied from the tree and changed as the plant says; a reader plant also holds
its own changed copy of tests/test-manifest.sps. Nothing in the tree is
written.
"""
import os
import shutil
import sys

ROOT = "/home/kishu/src/chez-curl"
BASE = os.path.join(ROOT, "build/m8s6-review/plants")

def read(path):
    with open(os.path.join(ROOT, path), "r", encoding="utf-8", newline="") as f:
        return f.read()

MANIFEST = read("Akku.manifest")
LOCK = read("Akku.lock")
CHANGELOG = read("CHANGELOG.md")
SUITE = read("tests/test-manifest.sps")

UNREL = "## [Unreleased]\n\n"
REL = "## [0.1.0] - 2026-11-10\n"
LINKS = "[Unreleased]: "
assert CHANGELOG.count(UNREL) == 1 and CHANGELOG.count(REL) == 1 and CHANGELOG.count(LINKS) == 1

NEW = "## [0.2.0] - 2026-12-01\n\n### Added\n\n- A later release.\n\n"

def bump_manifest(version):
    old = '(akku-package ("chez-curl" "0.1.0")'
    assert MANIFEST.count(old) == 1
    return MANIFEST.replace(old, '(akku-package ("chez-curl" "%s")' % version)

def insert_after_unreleased(text, block):
    return text.replace(UNREL, UNREL + block, 1)

def before_links(text, block):
    return text.replace(LINKS, block + LINKS, 1)

def sub(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new, 1)

# name -> (manifest, changelog or None for no file, suite or None for the tree's, what it is)
shape = {
    "a00-control": (MANIFEST, CHANGELOG, None,
                    "the tree's three files, unchanged"),
    "a01-manifest-alone": (bump_manifest("0.2.0"), CHANGELOG, None,
                           "Akku.manifest bumped to 0.2.0, the changelog not"),
    "a02-changelog-alone": (MANIFEST, insert_after_unreleased(CHANGELOG, NEW), None,
                            "a 0.2.0 entry added, the manifest left at 0.1.0"),
    "a03-both-bumped": (bump_manifest("0.2.0"), insert_after_unreleased(CHANGELOG, NEW), None,
                        "both bumped to 0.2.0 (control: must pass)"),
    "a04-no-unreleased": (MANIFEST, sub(CHANGELOG, UNREL, ""), None,
                          "the [Unreleased] heading removed"),
    "a05-newer-no-date": (MANIFEST, insert_after_unreleased(CHANGELOG, "## [0.2.0]\n\n- x\n\n"), None,
                          "a newer heading with no date, above 0.1.0, manifest 0.1.0"),
    "a06-yanked-latest": (MANIFEST, sub(CHANGELOG, REL, "## [0.1.0] - 2026-11-10 [YANKED]\n"), None,
                          "0.1.0 marked [YANKED], as Keep a Changelog writes it"),
    "a07-yanked-older": (bump_manifest("0.2.0"),
                         sub(insert_after_unreleased(CHANGELOG, NEW), REL, "## [0.1.0] - 2026-11-10 [YANKED]\n"),
                         None, "0.2.0 released, 0.1.0 below it marked [YANKED], manifest 0.2.0"),
    "a08-h3-new-release": (MANIFEST, insert_after_unreleased(CHANGELOG, "### [0.2.0] - 2026-12-01\n\n- x\n\n"), None,
                           "a 0.2.0 entry written at ### (wrong level), manifest left at 0.1.0"),
    "a09-indented-heading": (MANIFEST, insert_after_unreleased(CHANGELOG, " ## [0.2.0] - 2026-12-01\n\n- x\n\n"), None,
                             "a 0.2.0 heading indented one space (CommonMark still an h2), manifest 0.1.0"),
    "a10-appended-at-bottom": (MANIFEST, before_links(CHANGELOG, "## [0.2.0] - 2026-12-01\n\n- x\n\n"), None,
                               "a 0.2.0 entry appended after 0.1.0 (oldest place), manifest 0.1.0"),
    "a11-duplicate-version": (MANIFEST, insert_after_unreleased(CHANGELOG, "## [0.1.0] - 2026-12-01\n\n- x\n\n"), None,
                              "a new entry that reuses 0.1.0, above the old 0.1.0, manifest 0.1.0"),
    "a12-version-goes-down": (bump_manifest("0.0.9"), insert_after_unreleased(CHANGELOG, "## [0.0.9] - 2026-12-01\n\n- x\n\n"), None,
                              "a newer entry numbered 0.0.9, above 0.1.0, manifest 0.0.9"),
    "a13-date-not-a-date": (MANIFEST, sub(CHANGELOG, REL, "## [0.1.0] - 2026-13-45\n"), None,
                            "0.1.0 dated 2026-13-45"),
    "a14-crlf": (MANIFEST, CHANGELOG.replace("\n", "\r\n"), None,
                 "the changelog with CRLF line ends"),
    "a15-bom": (MANIFEST, "﻿" + CHANGELOG, None,
                "the changelog with a leading byte-order mark"),
    "a16-empty": (MANIFEST, "", None, "an empty changelog (main's before this branch)"),
    "a17-missing": (MANIFEST, None, None, "no CHANGELOG.md at all"),
    "a18-prerelease": (MANIFEST, insert_after_unreleased(CHANGELOG, "## [0.2.0-rc.1] - 2026-12-01\n\n- x\n\n"), None,
                       "a SemVer pre-release heading above 0.1.0"),
    "a19-fenced-example": (bump_manifest("9.9.9"),
                           insert_after_unreleased(CHANGELOG, "```markdown\n## [9.9.9] - 2026-01-01\n```\n\n"), None,
                           "a fenced code block in [Unreleased] holding a release heading, manifest 9.9.9"),
}

def suite_sub(old, new):
    assert SUITE.count(old) == 1, old
    return SUITE.replace(old, new, 1)

reader = {
    "b01-last-release": (suite_sub("        (release-version (cadr headings)))))",
                                   "        (release-version (car (reverse headings))))))"),
                         "latest-release takes the last release heading, not the first"),
    "b02-skip-malformed": (suite_sub("""    (for-each (lambda (heading)
                (unless (release-version heading)
                  (assertion-violation 'latest-release "not a release heading" heading)))
              (cdr headings))
    (if (null? (cdr headings))
        'none
        (release-version (cadr headings)))))""",
                                     """    (let ((releases (filter release-version (cdr headings))))
      (if (null? releases)
          'none
          (release-version (car releases))))))"""),
                           "a malformed heading is skipped, the first well-formed one taken"),
    "b03-no-unreleased-check": (suite_sub("""    (unless (and (pair? headings) (string=? (car headings) "## [Unreleased]"))
      (assertion-violation 'latest-release "the first heading is not ## [Unreleased]"
                           (if (pair? headings) (car headings) 'no-heading)))""",
                                          """    (unless (pair? headings)
      (assertion-violation 'latest-release "the first heading is not ## [Unreleased]" 'no-heading))"""),
                                "the first heading need not be [Unreleased]"),
    "b04-date-skips-8-9": (suite_sub("         (or (= i 10)", "         (or (>= i 8)"),
                           "date? leaves positions 8 and 9 unchecked"),
    "b05-date-skips-7": (suite_sub("""             (and (if (memv i '(4 7))""",
                                   """             (and (if (= i 7) #t (if (memv i '(4))""").replace(
                                       """                      (ascii-digit? (string-ref text i)))
                  (loop (+ i 1)))))))""",
                                       """                      (ascii-digit? (string-ref text i))))
                  (loop (+ i 1)))))))""", 1),
                         "date? leaves position 7, the second hyphen, unchecked"),
    "b06-version-char-numeric": (suite_sub("       (for-all ascii-digit? (string->list text))",
                                           "       (for-all char-numeric? (string->list text))"),
                                 "version-number? takes char-numeric? digits"),
    "b07-leading-zero-ok": (suite_sub("""       (or (= (string-length text) 1)
           (not (char=? (string-ref text 0) #\\0)))))""", "       #t))"),
                            "version-number? takes a leading zero"),
    "b08-no-separator-check": (suite_sub("""                       (starts-with? tail " - ")
""", ""),
                               "release-version does not check the \" - \" separator"),
    "b09-unreleased-only-is-false": (suite_sub("        'none\n        (release-version (cadr headings)))))",
                                               "        #f\n        (release-version (cadr headings)))))"),
                                     "latest-release answers #f, not 'none, for [Unreleased] alone"),
    "b10-last-heading-unchecked": (suite_sub("""              (cdr headings))
    (if (null? (cdr headings))""",
                                             """              (let ((rest (cdr headings))) (if (null? rest) rest (reverse (cdr (reverse rest))))))
    (if (null? (cdr headings))"""),
                                   "latest-release does not check the last (oldest) heading"),
    "b11-filter-on-bracket": (suite_sub("""  (let ((headings (filter (lambda (line) (starts-with? line "## ")) lines)))""",
                                        """  (let ((headings (filter (lambda (line) (starts-with? line "## [")) lines)))"""),
                              "only `## [` lines count as headings"),
    "b12-cut-drops-empty": (suite_sub("""           (loop (- i 1) i (cons (substring text (+ i 1) end) found)))""",
                                      """           (loop (- i 1) i (if (= (+ i 1) end) found (cons (substring text (+ i 1) end) found))))"""),
                            "cut-at drops empty fields after a separator"),
    "b13-version-takes-empty": (suite_sub("  (and (> (string-length text) 0)\n       (for-all ascii-digit?",
                                          "  (and (>= (string-length text) 0)\n       (for-all ascii-digit?"),
                                "version-number? takes an empty number"),
    "b14-heading-filter-two-hashes": (suite_sub("""  (let ((headings (filter (lambda (line) (starts-with? line "## ")) lines)))""",
                                                """  (let ((headings (filter (lambda (line) (starts-with? line "##")) lines)))"""),
                                      "every line starting ## counts, ### among them"),
    "b15-max-version": (suite_sub("        (release-version (cadr headings)))))",
                                  """        (let loop ((best (release-version (cadr headings))) (rest (cddr headings)))
          (if (null? rest) best
              (loop (let ((v (release-version (car rest)))) (if (string>? v best) v best)) (cdr rest)))))))"""),
                         "latest-release takes the greatest version string, not the first heading"),
}

def write(path, text):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)

def main():
    if os.path.exists(BASE):
        sys.exit("plants exist already: " + BASE)
    os.makedirs(BASE)
    index = []
    for name, (manifest, changelog, suite, what) in shape.items():
        d = os.path.join(BASE, name)
        os.makedirs(d)
        write(os.path.join(d, "Akku.manifest"), manifest)
        write(os.path.join(d, "Akku.lock"), LOCK)
        if changelog is not None:
            write(os.path.join(d, "CHANGELOG.md"), changelog)
        index.append("%s\tshape\t%s" % (name, what))
    for name, (suite, what) in reader.items():
        assert suite != SUITE, name
        d = os.path.join(BASE, name)
        os.makedirs(d)
        write(os.path.join(d, "Akku.manifest"), MANIFEST)
        write(os.path.join(d, "Akku.lock"), LOCK)
        write(os.path.join(d, "CHANGELOG.md"), CHANGELOG)
        write(os.path.join(d, "test-manifest.sps"), suite)
        index.append("%s\treader\t%s" % (name, what))
    write(os.path.join(BASE, "index.tsv"), "\n".join(index) + "\n")
    print(len(index), "plants")

main()
