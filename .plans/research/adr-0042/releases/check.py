# check.py ID NOTES TAG TITLE: the release's stored fields against what was asked.
import json, subprocess, sys
rid, notes, tag, title = sys.argv[1:]
r = json.loads(subprocess.run(["gh", "api", f"repos/Kiyomi-Computation-Systems/chez-curl/releases/{rid}"],
                              check=True, capture_output=True, text=True).stdout)
want = open(notes, encoding="utf-8").read()
body = r["body"]
print("tag", r["tag_name"], "name ok" if r["name"] == title else "NAME DIFFERS",
      "draft", r["draft"], "prerelease", r["prerelease"])
print("body bytes", len(body.encode()), "notes bytes", len(want.encode()))
if body == want: print("ok: body is the notes, byte for byte")
elif body == want.rstrip("\n"): print("body is the notes less the final newline")
else:
    import difflib
    print("BODY DIFFERS"); sys.stdout.writelines(list(difflib.unified_diff(want.splitlines(True), body.splitlines(True)))[:20])
