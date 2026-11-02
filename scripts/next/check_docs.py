#!/usr/bin/env python3
"""Check the Next documentation tree (no network).

1. Every relative link in docs/next outside archive/ resolves, and every
   #anchor into a Markdown file names one of its headings.
2. Following links from docs/next/README.md never reaches archive/.
3. Documents packaged into the knowledge catalog neither link archive/ nor
   name experiment reports.
"""
import collections
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs/next'
ARCHIVE = DOCS / 'archive'
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'scripts/next'))
from build_knowledge import DOCUMENTS  # noqa: E402

FENCE = re.compile(r'^(```|~~~).*?^\1', re.M | re.S)
CODE = re.compile(r'`[^`\n]*`')
LINK = re.compile(r'!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')
HEADING = re.compile(r'^(#{1,6})\s+(.+?)\s*#*\s*$', re.M)
REPORT = re.compile(r'\b[XY]\d+[A-Z]?_REPORT\b')


def prose(text):
    return CODE.sub('', FENCE.sub('', text))


def slug(heading):
    text = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', heading)
    text = re.sub(r'<[^>]+>', '', text).strip().lower()
    text = re.sub(r'[^\w\- ]', '', text)
    return text.replace(' ', '-')


def anchors(path, cache={}):
    if path not in cache:
        seen = collections.Counter()
        found = set()
        for match in HEADING.finditer(FENCE.sub('', path.read_text(encoding='utf-8'))):
            base = slug(match[2])
            found.add(base if seen[base] == 0 else f'{base}-{seen[base]}')
            seen[base] += 1
        cache[path] = found
    return cache[path]


def links(path):
    for match in LINK.finditer(prose(path.read_text(encoding='utf-8'))):
        target = match[1]
        if re.match(r'^[a-z][a-z0-9+.-]*:', target, re.I):
            continue
        file, _, anchor = target.partition('#')
        yield (path if not file else (path.parent / file).resolve()), anchor


def inside(path, folder):
    try:
        path.relative_to(folder)
        return True
    except ValueError:
        return False


def main():
    problems = []
    pages = sorted(p for p in DOCS.rglob('*.md') if not inside(p, ARCHIVE))
    for page in pages:
        name = page.relative_to(ROOT)
        for target, anchor in links(page):
            if not target.exists():
                problems.append(f'{name}: missing {target.relative_to(ROOT) if inside(target, ROOT) else target}')
            elif anchor and target.suffix == '.md' and anchor not in anchors(target):
                problems.append(f'{name}: no heading #{anchor} in {target.relative_to(ROOT)}')

    start = (DOCS / 'README.md').resolve()
    queue, reached = collections.deque([start]), {start: None}
    while queue:
        page = queue.popleft()
        for target, _ in links(page):
            if target.suffix != '.md' or not target.exists() or not inside(target, DOCS) or target in reached:
                continue
            reached[target] = page
            if inside(target, ARCHIVE):
                problems.append(f'{target.relative_to(ROOT)} is reachable from docs/next/README.md '
                                f'(via {page.relative_to(ROOT)})')
                continue
            queue.append(target)

    for name in DOCUMENTS:
        page = DOCS / name
        text = prose(page.read_text(encoding='utf-8'))
        for target, _ in links(page):
            if inside(target, ARCHIVE):
                problems.append(f'docs/next/{name}: packaged knowledge links {target.relative_to(ROOT)}')
        for report in sorted(set(REPORT.findall(text))):
            problems.append(f'docs/next/{name}: packaged knowledge names {report}')

    for problem in problems:
        print(problem)
    print(f'Pages checked: {len(pages)}; reachable from README: {len(reached)}; '
          f'packaged: {len(DOCUMENTS)}; problems: {len(problems)}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
