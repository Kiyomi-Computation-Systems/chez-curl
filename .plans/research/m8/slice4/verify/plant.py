import sys, re, shutil, subprocess, os
W='/home/kishu/src/chez-curl/build/m8s4-mine'
name=sys.argv[1]
t=f'{W}/t-{name}'
subprocess.run(['rsync','-a','--delete',f'{W}/base/',t+'/'],check=True)
def edit(path, fn):
    p=f'{t}/{path}'; s=open(p).read(); s2=fn(s); assert s2!=s, name; open(p,'w').write(s2)
if name=='org-byte':
    edit('README.org', lambda s: s.replace('(define base (cadr (command-line)))','(define base (cadr (command-line))) ',1) if False else s.replace("(display (http-response-status response))","(display (http-response-status  response))",1))
elif name=='no-info':
    def f(s):
        s=s.replace('```scheme example=examples/multipart.sps\n','```\n',1)
        i=s.index('```\n',s.index('## ')); return s
    edit('docs/high-level.md', lambda s: re.sub(r'```scheme example=examples/multipart.sps\n(.*?\n)', lambda m: '```\n'+m.group(1).replace('(','(  ',1), s, count=1, flags=re.S))
elif name=='gap':
    def f(s):
        m=re.search(r'```scheme example=examples/errors.sps\n((?:.*\n)*?)```', s)
        lines=m.group(1).split('\n')
        assert len(lines)>4
        del lines[2]
        return s[:m.start(1)]+'\n'.join(lines)+s[m.end(1):]
    edit('docs/errors.md', f)
print('planted', name)
