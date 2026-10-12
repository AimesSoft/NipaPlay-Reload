#!/usr/bin/env python3
"""apk_size_report.py — APK 体积构成拆解（同口径，可复用于任意 APK 对比）

用法:
    python apk_size_report.py <apk路径> [<apk路径2> ...]

输出每个 APK 的:
  - 总体积（压缩后，即分发口径）
  - 按模块分组：lib/<abi> / dex / assets / res / resources.arsc / other
  - 最大的 N 个文件（未压缩大小，便于定位膨胀点）

设计说明:
  - 用「压缩后大小」做占比，与用户下载量口径一致；
  - lib 按 ABI 分组，便于发现"三 ABI 全打"这类问题；
  - 对每个 APK 独立统计，可直接对比不同产品（如竞品 APK）。
"""
import collections
import os
import sys
import zipfile


def analyze(apk, top_n=12):
    if not os.path.exists(apk):
        print(f'[skip] 不存在: {apk}')
        return
    z = zipfile.ZipFile(apk)
    total = os.path.getsize(apk)
    groups = collections.Counter()
    detail = collections.Counter()

    for info in z.infolist():
        n = info.filename
        c = info.compress_size
        if n.startswith('lib/'):
            parts = n.split('/')
            abi = parts[1] if len(parts) > 2 else '?'
            groups[f'lib/{abi}'] += c
            detail[n] += info.file_size
        elif n.startswith('assets/'):
            groups['assets'] += c
            detail[n] += info.file_size
        elif n.startswith('res/'):
            groups['res'] += c
        elif n.endswith('.dex'):
            groups['dex'] += c
            detail[n] += info.file_size
        elif n == 'resources.arsc':
            groups['resources.arsc'] += c
        else:
            groups['other'] += c

    print(f'\n===== {os.path.basename(apk)}: {total / 1024 / 1024:.1f} MB =====')
    print(f'{"模块":<24}{"压缩后 MB":>12}{"占比":>8}')
    for k, v in groups.most_common():
        print(f'{k:<24}{v / 1024 / 1024:>12.2f}{v / total * 100:>7.1f}%')
    print(f'  -- 最大的 {top_n} 个文件（未压缩）--')
    for n, s in detail.most_common(top_n):
        print(f'    {s / 1024 / 1024:>8.2f} MB  {n}')


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    for apk in sys.argv[1:]:
        analyze(apk)


if __name__ == '__main__':
    main()
