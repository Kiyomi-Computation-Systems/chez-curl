# extract.py TAG VERSION OUT: the CHANGELOG entry for VERSION as TAG holds it,
# from the line after its heading to its last line, blank lines trimmed.
import re, subprocess, sys
tag, version, out = sys.argv[1:]
text = subprocess.run(["git", "show", f"{tag}:CHANGELOG.md"], check=True,
                      capture_output=True, text=True).stdout
lines = text.split("\n")
heads = [i for i, l in enumerate(lines) if re.match(r"## \[", l)]
start = [i for i in heads if lines[i].startswith(f"## [{version}] - ")]
assert len(start) == 1, start
s = start[0]
later = [i for i in heads if i > s]
refs = [i for i, l in enumerate(lines) if re.match(r"\[[^\]]+\]: https://", l) and i > s]
end = min(later + refs + [len(lines)])
body = lines[s + 1:end]
while body and body[0].strip() == "": body.pop(0)
while body and body[-1].strip() == "": body.pop()
open(out, "w").write("\n".join(body) + "\n")
print(out, len("\n".join(body) + "\n"), "bytes;", lines[s])
