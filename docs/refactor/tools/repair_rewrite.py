#!/usr/bin/env python3
"""repair_rewrite.py — 用 HEAD 内容重放 import 改写, 修复首次批次的行合并损伤。"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import move_batch as mb  # noqa: E402


def git_show_head(path):
    r = subprocess.run(['git', 'show', 'HEAD:' + path], cwd=mb.REPO,
                       capture_output=True)
    if r.returncode != 0:
        return None
    return r.stdout.decode('utf-8', errors='replace')


def main():
    state = json.load(open(mb.STATE_FILE, encoding='utf-8'))
    moved = set(state['moved'])
    rewrite_map = {lr: mb.CORE_PKG + lr for lr in moved}
    prefix = mb.to_posix(mb.CORE_LIB) + '/'
    debug = '-v' in sys.argv

    repaired = unchanged = skipped = 0
    for full, rel in mb.scan_dart_files():
        rel_posix = mb.to_posix(rel)
        old_librel = None
        if rel_posix.startswith(prefix):
            core_rel = rel_posix[len(prefix):]
            if core_rel.startswith('src/'):
                core_rel = core_rel[len('src/'):]
            if core_rel in moved:
                old_librel = core_rel
        if old_librel:
            head_path = 'lib/' + old_librel
            importer = old_librel
        else:
            head_path = rel_posix
            importer = mb.lib_rel(rel_posix)
        head_text = git_show_head(head_path)
        if head_text is None:
            skipped += 1
            if debug:
                print('skip(no-HEAD):', rel_posix)
            continue
        lines = head_text.split('\n')
        changed = False
        for idx, line in enumerate(lines):
            m = mb.DIRECTIVE_RE.match(line)
            if not m:
                continue
            t = mb.resolve_uri(importer, m.group(3))
            new_uri = rewrite_map.get(t) if t else None
            if not new_uri:
                continue
            lines[idx] = line[:m.start(3)] + new_uri + line[m.end(3):]
            changed = True
        if not changed:
            unchanged += 1
            continue
        with open(full, 'w', encoding='utf-8', newline='') as f:
            f.write('\n'.join(lines))
        repaired += 1
        if debug:
            print('rewrote:', rel_posix)
    print(f'重放完成: 改写 {repaired}, 无需改动 {unchanged}, 跳过 {skipped}')


if __name__ == '__main__':
    main()
