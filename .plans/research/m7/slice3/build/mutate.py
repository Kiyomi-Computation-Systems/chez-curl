#!/usr/bin/env python3
"""build/m7s3b/mutate.py: make a mutant copy of the tree.

  mutate.py NAME FILE OLD NEW      (OLD and NEW read from files OLD and NEW)

Copies the working tree (no build/, .git or .plans/research) to
build/m7s3b/mut/NAME, then replaces OLD, which must stand exactly once in
FILE there, by NEW. Prints the copy's path."""
import os, subprocess, sys
name, rel, oldf, newf = sys.argv[1:5]
root = os.getcwd()
dest = os.path.join(root, 'build/m7s3b/mut', name)
os.makedirs(dest, exist_ok=True)
subprocess.run(['rsync', '-a', '--delete', '--exclude', '/build', '--exclude', '/.git',
                '--exclude', '/.plans/research', './', dest + '/'], check=True)
path = os.path.join(dest, rel)
text = open(path).read()
old = open(oldf).read()
new = open(newf).read()
n = text.count(old)
if n != 1:
    sys.exit(f'mutate: {name}: OLD stands {n} times in {rel}')
open(path, 'w').write(text.replace(old, new))
print(dest)
