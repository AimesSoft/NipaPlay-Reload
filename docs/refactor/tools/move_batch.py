#!/usr/bin/env python3
"""move_batch.py — 阶段一批次搬移引擎（NipaPlay → packages/nipaplay_core）

用法: python move_batch.py <manifest.json> [--dry-run]

manifest 格式:
{
  "batch": "batch-1-models",
  "moves": [ {"from": "lib/models/bangumi_model.dart",
              "to": "packages/nipaplay_core/lib/src/models/bangumi_model.dart"} ]
}

行为:
1. 闭包预检: 待搬文件的每个 import/export/part 解析到 lib 内路径,
   目标必须在 (本批 moves ∪ 已搬集合 moved_state.json) 内, 否则拒绝并打印链路。
2. part 完整性: 带 part 的库与其 part 文件必须同批; part 文件的宿主库必须同批。
3. git mv 搬移 (保留历史)。
4. 全库 import 改写: lib/ test/ packages/nipaplay_core/lib/ 下所有 .dart,
   把指向已搬文件的 import/export/part URI 改写为 package:nipaplay_core/src/...,
   保留 as/show/hide/deferred 后缀与引号风格。
5. 更新 moved_state.json。

核心不变量: 只改 URI, 不改任何逻辑。
"""
import json
import os
import posixpath
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
STATE_FILE = os.path.join(REPO, 'docs', 'refactor', 'tools', 'moved_state.json')
SCAN_ROOTS = ['lib', 'test', os.path.join('packages', 'nipaplay_core', 'lib')]
APP_PKG = 'package:nipaplay/'
CORE_PKG = 'package:nipaplay_core/'
CORE_LIB = os.path.join('packages', 'nipaplay_core', 'lib')

DIRECTIVE_RE = re.compile(
    r"^(\s*(?:@Deprecated\([^\)]*\)\s*)?(?:import|export|part)\s+)(['\"])([^'\"]+)\2(.*)$")


def to_posix(p):
    return p.replace('\\', '/')


def lib_rel(path_under_repo):
    """repo 相对路径 -> lib 内相对路径 (不在 lib 内返回 None)"""
    p = to_posix(path_under_repo)
    if p.startswith('lib/'):
        return p[4:]
    return None


def resolve_uri(importing_librel, uri):
    """返回该 URI 指向的 lib 内相对路径; dart:/外部包/解析不到 -> None"""
    if uri.startswith('dart:'):
        return None
    if uri.startswith(APP_PKG):
        return uri[len(APP_PKG):]
    if uri.startswith('package:'):
        return None
    if importing_librel is None:
        return None
    base = posixpath.dirname(importing_librel)
    target = posixpath.normpath(posixpath.join(base, uri))
    if target.startswith('../') or target.startswith('/'):
        return None
    return target


def scan_dart_files():
    out = []
    for root in SCAN_ROOTS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(REPO, root)):
            dirnames[:] = [d for d in dirnames if d not in ('.dart_tool', 'build')]
            for fn in filenames:
                if fn.endswith('.dart'):
                    full = os.path.join(dirpath, fn)
                    out.append((full, to_posix(os.path.relpath(full, REPO))))
    return out


def parse_directives(text):
    """[(line_no, match, uri)]"""
    res = []
    for i, line in enumerate(text.splitlines()):
        m = DIRECTIVE_RE.match(line)
        if m:
            res.append((i, m, m.group(3)))
    return res


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    dry = '--dry-run' in sys.argv
    manifest = json.load(open(sys.argv[1], encoding='utf-8'))
    moves = [(to_posix(m['from']), to_posix(m.get('to') or ('packages/nipaplay_core/lib/' + to_posix(m['from'])[4:]))) for m in manifest['moves']]
    batch = manifest.get('batch', 'unnamed')

    state = {'moved': []}
    if os.path.exists(STATE_FILE):
        state = json.load(open(STATE_FILE, encoding='utf-8'))
    already = set(state['moved'])

    # --- 基本校验 ---
    moving = {}
    for entry_src, entry_dst in moves:
        src = entry_src
        lr = lib_rel(src)
        if lr is None:
            sys.exit(f'[FAIL] 源不在 lib/ 下: {src}')
        dst = entry_dst or ('packages/nipaplay_core/lib/' + lr)
        if not os.path.exists(os.path.join(REPO, src)):
            sys.exit(f'[FAIL] 源不存在: {src}')
        if lr in already:
            sys.exit(f'[FAIL] {src} 已在之前批次搬过')
        if lr in moving:
            sys.exit(f'[FAIL] 重复条目: {src}')
        moving[lr] = (src, dst)
    print(f'[batch {batch}] 待搬 {len(moves)} 个文件')

    # --- part 完整性 ---
    lib_files = {}
    for full, rel in scan_dart_files():
        lr = lib_rel(rel)
        if lr:
            lib_files[lr] = full
    for lr, (src, _dst) in moving.items():
        text = open(os.path.join(REPO, src), encoding='utf-8').read()
        for _i, _m, uri in parse_directives(text):
            if _m.group(1).rstrip().endswith('part') and not _m.group(1).rstrip().endswith('export'):
                pass
            t = resolve_uri(lr, uri)
            if t and t in lib_files and t not in moving and t not in already:
                # import 依赖留观文件: 仅当目标是本文件的 part 或宿主时才是完整性问题
                is_part_decl = re.match(r"^\s*part\s+['\"]", '')
                pass
        # part 声明检查
        for line in text.splitlines():
            pm = re.match(r"^\s*part\s+['\"]([^'\"]+)['\"]\s*;", line)
            if pm:
                t = resolve_uri(lr, pm.group(1))
                if t and t not in moving:
                    sys.exit(f'[FAIL] part 完整性: {src} 的 part {t} 不在本批')
            om = re.match(r"^\s*part of\s+['\"]([^'\"]+)['\"]\s*;", line)
            if om:
                t = resolve_uri(lr, om.group(1))
                if t and t not in moving:
                    sys.exit(f'[FAIL] part 完整性: {src} 是 part, 宿主 {t} 不在本批')

    # --- 闭包预检 ---
    failures = []
    for lr, (src, _dst) in moving.items():
        text = open(os.path.join(REPO, src), encoding='utf-8').read()
        for _i, _m, uri in parse_directives(text):
            t = resolve_uri(lr, uri)
            if t is None or not t.endswith('.dart'):
                continue
            if t not in lib_files:
                continue  # 不存在的目标留给 analyzer 报
            if t not in moving and t not in already:
                failures.append((src, uri, t))
    if failures:
        print('[FAIL] 闭包预检发现未搬依赖 (按约束 6 暂停, 请人工决策):')
        for src, uri, t in failures:
            print(f'  {src}  --{uri}-->  {t}')
        sys.exit(1)

    if dry:
        print('[dry-run] 预检通过, 未执行搬移')
        return

    # --- git mv ---
    for src, dst in moves:
        dst_full = os.path.join(REPO, dst)
        os.makedirs(os.path.dirname(dst_full), exist_ok=True)
        r = subprocess.run(['git', 'mv', src, dst], cwd=REPO,
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f'[FAIL] git mv {src} -> {dst}: {r.stderr.strip()}')
    print(f'[batch {batch}] git mv 完成 {len(moves)} 个文件')

    # --- import 改写 ---
    # uri -> 新 package uri 的映射 (按 lib 内旧路径)
    rewrite_map = {}
    for lr, (_src, _dst) in moving.items():
        import posixpath as _pp
        new_rel = _pp.relpath(_dst, CORE_LIB)
        rewrite_map[lr] = CORE_PKG + new_rel
    # 已搬文件的映射也要保留 (改写本批文件内部对老批次的 package:nipaplay 引用)
    for old in already:
        pass  # 老批次文件已被改写过, 无需再映射

    total_files = 0
    total_subs = 0
    # 当前仓库路径 -> 搬移前 librel (供搬移文件自身按原位置解析相对 import)
    current_to_old = {}
    for lr, (src, dst) in moving.items():
        current_to_old[to_posix(dst)] = lr
    for full, rel in scan_dart_files():
        with open(full, encoding='utf-8') as f:
            text = f.read()
        rel_posix = to_posix(rel)
        # 搬移后的文件按搬移前的 lib 位置解析其 import
        importer_librel = current_to_old.get(rel_posix, lib_rel(rel_posix))
        lines = text.split('\n')
        changed = False
        for idx, line in enumerate(lines):
            m = DIRECTIVE_RE.match(line)
            if not m:
                continue
            uri = m.group(3)
            t = resolve_uri(importer_librel, uri)
            new_uri = rewrite_map.get(t) if t else None
            if not new_uri:
                continue
            newline = line[:m.start(3)] + new_uri + line[m.end(3):]
            if newline != line:
                lines[idx] = newline
                changed = True
                total_subs += 1
        if changed:
            with open(full, 'w', encoding='utf-8', newline='') as f:
                f.write('\n'.join(lines))
            total_files += 1
    print(f'[batch {batch}] import 改写: {total_files} 个文件, {total_subs} 处')

    # --- 状态 ---
    state['moved'] = sorted(already | set(moving.keys()))
    state.setdefault('batches', []).append(
        {'batch': batch, 'count': len(moves), 'files': sorted(moving.keys())})
    with open(STATE_FILE, 'w', encoding='utf-8') as f:
        json.dump(state, f, ensure_ascii=False, indent=1)
    print(f'[batch {batch}] 状态已记录 -> moved_state.json')


if __name__ == '__main__':
    main()
