import re, sys, glob
def strip(src):
    out=[];i=0;n=len(src)
    while i<n:
        if src.startswith('--[[',i) or src.startswith('--[==[',i):
            j=src.find(']]',i); i=j+2; continue
        if src.startswith('--',i):
            j=src.find('\n',i); i = n if j<0 else j; continue
        if src.startswith('[[',i):
            j=src.find(']]',i); out.append('""'); i=j+2; continue
        c=src[i]
        if c in '"\'':
            j=i+1
            while src[j]!=c:
                if src[j]==chr(92): j+=1
                if src[j]=='\n': print("  unterminated string at", src.count('\n',0,i)+1); break
                j+=1
            out.append('""'); i=j+1; continue
        out.append(c); i+=1
    return ''.join(out)
ok=True
for f in sys.argv[1:]:
    s=strip(open(f,encoding='utf-8').read())
    words=re.findall(r'\b(function|if|do|repeat|end|until|then|elseif|for|while)\b',s)
    opn=sum(words.count(w) for w in ('function','if','do','repeat'))
    cls=words.count('end')+words.count('until')
    ifs=words.count('if')+words.count('elseif'); thens=words.count('then')
    fw=words.count('for')+words.count('while')
    p=(s.count('(')-s.count(')'), s.count('{')-s.count('}'), s.count('[')-s.count(']'))
    status = 'OK' if (opn==cls and ifs==thens and p==(0,0,0) and words.count('do')>=fw) else 'PROBLEM'
    if status!='OK': ok=False
    print(f"{status} {f.split('/')[-1]}: open={opn} close={cls} if/then={ifs}/{thens} for+while={fw} do={words.count('do')} parens={p}")
sys.exit(0 if ok else 1)
