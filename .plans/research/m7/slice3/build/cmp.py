import re,collections,sys
def load(path, multi):
    lanes=collections.OrderedDict(); cur=None
    for line in open(path, encoding='latin-1'):
        line=line.rstrip('\n')
        if multi and line.startswith('== '):
            cur=line[3:]; lanes[cur]=collections.OrderedDict(); continue
        if not multi and cur is None:
            cur='guix'; lanes[cur]=collections.OrderedDict()
        if line.startswith('('):
            m=re.match(r'\("([^"]*)" (\S+) (\S+) (.*)$', line)
            if m: lanes[cur][(m.group(1),m.group(2),m.group(3))]=m.group(4)
    return lanes
L=load(sys.argv[1],True)
L.update(load(sys.argv[2],False))
order=['floor','openssl','gnutls','guix','current']
keys=list(L['guix'].keys())
show_all = len(sys.argv)>3
for k in keys:
    vals=[L[l].get(k,'MISSING') for l in order]
    if show_all or len(set(vals))>1:
        print(k)
        if len(set(vals))==1: print('    all', vals[0][:300])
        else:
            for l,v in zip(order,vals): print('   ',l,v[:300])
