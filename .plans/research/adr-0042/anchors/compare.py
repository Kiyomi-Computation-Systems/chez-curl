# compare.py PROBE-OUT GITHUB-DIR: each docs page's heading anchors, GitHub's
# rendering (github/PAGE.html, each anchor's href after a heading-element)
# against the site's rule and test-docs's, page by page, in order.
import html, re, sys, urllib.parse
probe, gh = sys.argv[1:]
rules = {}
for line in open(probe, encoding="utf-8"):
    parts = line.rstrip("\n").split(" ")
    if parts[0] in ("site", "test-docs"):
        rules.setdefault(parts[0], {})[parts[1]] = parts[2:]
pages = sorted(rules["test-docs"])
total = 0; bad = 0
for page in pages:
    text = open(f"{gh}/{page}.html", encoding="utf-8").read()
    ids = [urllib.parse.unquote(html.unescape(m)) for m in
           re.findall(r'class="heading-element"[^>]*>.*?<a id="user-content-[^"]*" class="anchor"[^>]*href="#([^"]*)"', text, re.S)]
    total += len(ids)
    for rule in ("site", "test-docs"):
        got = rules[rule].get(page)
        if got != ids:
            bad += 1
            print(f"DIFFERS {rule} {page}")
            print("  github:", ids)
            print("  rule:  ", got)
print(f"compare: {len(pages)} pages, {total} headings on GitHub; {bad} page-rule pairs differ")
sys.exit(1 if bad else 0)
