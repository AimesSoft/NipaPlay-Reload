import re
import collections
import sys

pat = re.compile(r'^(error|warning|info) - (.+) - (.+?):(\d+):(\d+) - (\S+)$')
src, dst = sys.argv[1], sys.argv[2]
counts = collections.Counter()
byfile = collections.Counter()
lib_lines = []
for line in open(src, encoding='utf-8', errors='replace'):
    m = pat.match(line.strip())
    if not m:
        continue
    sev, msg, path, l, c, code = m.groups()
    norm = path.replace(chr(92), '/')
    top = norm.split('/')[0]
    counts[(top, sev)] += 1
    if not norm.startswith(('third_party/', 'packages/', 'build/')):
        lib_lines.append(line.rstrip())
        byfile[norm] += 1
for k in sorted(counts):
    print(k, counts[k])
open(dst, 'w', encoding='utf-8').write('\n'.join(lib_lines) + '\n')
print('lib+test issues:', len(lib_lines))
for f, n in byfile.most_common(20):
    print(n, f)
