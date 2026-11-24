import re, glob, os, sys
os.chdir(sys.argv[1])
BS = chr(92)
for f in glob.glob('*.lua') + glob.glob('Guides/*.lua') + glob.glob('*.toc'):
    b = open(f, 'rb').read()
    if b.startswith(b'\xef\xbb\xbf'):
        print('BOM:', f)
    b.decode('utf-8')
print('BOM/utf8 check done')
for f in glob.glob('Guides/*.lua') + ['Trainers.lua']:
    s = open(f, encoding='utf-8').read()
    # strip strings, then comments
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '"':
            j = i + 1
            while s[j] != '"':
                if s[j] == BS:
                    j += 1
                j += 1
            out.append('""')
            i = j + 1
            continue
        if s.startswith('--', i):
            j = s.find('\n', i)
            i = len(s) if j < 0 else j
            continue
        out.append(c)
        i += 1
    s = ''.join(out)
    probs = []
    pats = [r'\}\s*\n\s*\{', r'(\d|""|\}|true|false)[ \t]+[A-Za-z_]+\s*=', r'(\d|""|\}|true|false)[ \t]*\n\s*[A-Za-z_]+\s*=']
    for pat in pats:
        for m in re.finditer(pat, s):
            probs.append((s.count('\n', 0, m.start()) + 1, m.group(0)))
    print(f, 'comma problems:', probs or 'none')
