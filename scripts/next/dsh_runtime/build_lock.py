#!/usr/bin/env python3
"""Builds assets/next/agent/dsh-runtime.json: what NipaPlay downloads to run
Nipa on DeepSeek Harness (DSH), pinned by SHA-256.

Inputs
  --source  an ordinary `npm install @deepseek-ai/dsh@<version>` directory
            (with its package-lock.json). It is the reference tree the
            package versions and their resolution come from.
  --trace   files listing every module a running Nipa loaded (trace.py), one
            file:// URL per line. Only packages that were loaded, plus the
            third-party packages they declare, are kept; packages that exist
            for rows `dshDisabledRows` turns off, and SDKs of providers Nipa
            never talks to, stay out.
  --cache   where registry tarballs are kept between runs.

Output: one entry per install path (a package hoisted to the most common
version of its name; other versions nested under the package that needs
them), each pointing at a registry tarball with its SHA-256 and size. Node.js
archives come from nodejs.org, pinned to the SHA-256 in its SHASUMS256.txt.
Nothing here is fetched at run time without a pinned digest.
"""
import argparse, base64, collections, hashlib, json, os, pathlib, re, sys, urllib.request

REGISTRY = 'https://registry.npmjs.org'
NODE_VERSION = '24.22.0'
# Packages Nipa never loads and that only exist because a provider SDK or an
# interactive terminal lists them. Anything that *was* loaded stays regardless.
EXCLUDE = [
    r'^node-pty$', r'^@google/genai$', r'^@anthropic-ai/sdk$', r'^@aws-sdk/', r'^@smithy/',
    r'^@aws-crypto/', r'^@aws/', r'^google-auth-library$', r'^gaxios$', r'^gcp-metadata$',
    r'^protobufjs$', r'^@protobufjs/', r'^@types/', r'^koffi$', r'^@koromix/', r'^fontkit$',
    r'^brotli$', r'^web-streams-polyfill$', r'^@deepseek-ai/libreoffice-kit',
]


def name_of(path):
    return path.rsplit('node_modules/', 1)[-1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source', required=True)
    ap.add_argument('--trace', required=True, nargs='+')
    ap.add_argument('--cache', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--shasums')
    ap.add_argument('--platforms', nargs='+', default=['macos-arm64'],
                    help='the platform keys whose package list was traced and tested')
    ap.add_argument('--os', nargs='+', default=['darwin'],
                    help="npm os names whose optional native packages are kept (darwin, linux, win32); "
                         "trace each of them and pass every trace file")
    args = ap.parse_args()
    src = pathlib.Path(args.source).expanduser()
    lock = json.load(open(src / 'package-lock.json'))['packages']

    def lookup(loc, name):
        while True:
            cand = (loc + '/' if loc else '') + 'node_modules/' + name
            if cand in lock:
                return cand
            if not loc:
                return None
            i = loc.rfind('/node_modules/')
            loc = loc[:i] if i >= 0 else ''

    def platform_ok(e):
        o, c = e.get('os'), e.get('cpu')
        return (not o or bool(set(args.os) & set(o))) and (not c or bool({'arm64', 'x64'} & set(c)))

    # Packages that were used: something other than package.json was loaded or
    # read. DSH's plugin discovery reads every installed package.json, which
    # says nothing about whether the package is needed.
    touched = collections.defaultdict(set)
    for t in args.trace:
        for line in open(t):
            line = line.strip()
            if not line.startswith('file://'):
                continue
            path = line[7:]
            ms = list(re.finditer(r'node_modules/((?:@[^/]+/)?[^/]+)', path))
            if not ms:
                continue
            rel = os.path.relpath(path[:ms[-1].end()], str(src))
            if rel in lock:
                touched[rel].add(path[ms[-1].end() + 1:])
    traced = {k for k, files in touched.items() if files - {'package.json'}}
    root = 'node_modules/@deepseek-ai/dsh'
    traced.add(root)
    excluded = [re.compile(p) for p in EXCLUDE]

    def is_excluded(path):
        n = name_of(path)
        return any(r.search(n) for r in excluded)

    # Selected packages = traced + third-party dependencies of what is kept.
    selected = set(traced)
    queue = list(traced)
    while queue:
        k = queue.pop()
        if k == root:
            continue
        e = lock[k]
        deps = list(e.get('dependencies', {})) + list(e.get('optionalDependencies', {}))
        for n in deps:
            t = lookup(k, n)
            if t is None or not platform_ok(lock[t]) or t in selected:
                continue
            if t in traced or (not n.startswith('@deepseek-ai/') and not is_excluded(t)):
                selected.add(t)
                queue.append(t)

    # Nodes are (name, version); edges are what each node's package.json asks
    # for, answered the way the reference tree answered them.
    def node_of(path):
        return (name_of(path), lock[path]['version'])

    rep = {}  # node -> a reference path
    for k in selected:
        rep.setdefault(node_of(k), k)
    edges = collections.defaultdict(set)
    for k in selected:
        e = lock[k]
        asks = list(e.get('dependencies', {})) + list(e.get('optionalDependencies', {}))
        asks += [n for n in e.get('peerDependencies', {})
                 if not e.get('peerDependenciesMeta', {}).get(n, {}).get('optional')]
        for n in asks:
            t = lookup(k, n)
            if t in selected:
                edges[node_of(k)].add(node_of(t))
    dependents = collections.Counter()
    for a, bs in edges.items():
        for b in bs:
            dependents[b] += 1
    # Whatever was loaded must resolve from the top: plugins are loaded by
    # name, from the loader, not through a dependency of DSH.
    top = sorted({node_of(k) for k in traced if name_of(k).startswith('@deepseek-ai/')})
    for node in top:
        dependents[node] += 1
    hoisted = {}
    for (n, v), c in sorted(dependents.items(), key=lambda kv: (-kv[1], kv[0][1])):
        hoisted.setdefault(n, v)

    # Layout.
    placed = {}  # path -> node

    def parent_of(path):
        i = path.rfind('/node_modules/')
        return path[:i] if i >= 0 else ''

    def find(loc, name):
        while True:
            cand = (loc + '/' if loc else '') + 'node_modules/' + name
            if cand in placed:
                return cand
            if not loc:
                return None
            loc = parent_of(loc)

    def place(loc, node):
        n, v = node
        hit = find(loc, n)
        if hit is not None and placed[hit] == node:
            return
        root_slot = 'node_modules/' + n
        # The hoisted version goes to the top unless a nearer copy of another
        # version would shadow it for this package.
        slot = root_slot if hoisted[n] == v and hit is None else \
            (loc + '/' if loc else '') + 'node_modules/' + n
        if slot in placed:
            raise SystemExit(f'conflict at {slot}: {placed[slot]} vs {node}')
        placed[slot] = node
        for dep in sorted(edges.get(node, ())):
            place(slot, dep)

    for node in top:
        place('', node)
    for path, node in placed.items():
        for dep in edges.get(node, ()):
            hit = find(path, dep[0])
            if hit is None or placed[hit] != dep:
                raise SystemExit(f'{path} would resolve {dep[0]} to {hit and placed[hit]}, not {dep}')

    # Tarballs.
    cache = pathlib.Path(args.cache).expanduser()
    cache.mkdir(parents=True, exist_ok=True)
    infos = {}

    def tarball(node):
        if node in infos:
            return infos[node]
        n, v = node
        path = rep[node]
        e = lock[path]
        base = n.split('/')[-1]
        url = f'{REGISTRY}/{n}/-/{base}-{v}.tgz'
        file = cache / f'{n.replace("/", "__")}-{v}.tgz'
        want = e['integrity']
        algo, b64 = want.split('-', 1)
        if not file.exists():
            with urllib.request.urlopen(url, timeout=120) as r, open(str(file) + '.part', 'wb') as f:
                f.write(r.read())
            os.rename(str(file) + '.part', file)
        data = file.read_bytes()
        got = base64.b64encode(hashlib.new(algo, data).digest()).decode()
        if got != b64:
            raise SystemExit(f'integrity mismatch for {n}@{v}')
        infos[node] = {'url': f'{n}/-/{base}-{v}.tgz', 'sha256': hashlib.sha256(data).hexdigest(),
                       'bytes': len(data), 'license': e.get('license')}
        return infos[node]

    packages = []
    for path in sorted(placed):
        n, v = placed[path]
        t = tarball((n, v))
        entry = {'path': path, 'name': n, 'version': v, **{k: t[k] for k in ('url', 'sha256', 'bytes')}}
        e = lock[rep[(n, v)]]
        if e.get('os'):
            entry['os'] = e['os']
        if e.get('cpu'):
            entry['cpu'] = e['cpu']
        packages.append(entry)

    # Node.js.
    shasums = open(args.shasums).read() if args.shasums else urllib.request.urlopen(
        f'https://nodejs.org/dist/v{NODE_VERSION}/SHASUMS256.txt', timeout=60).read().decode()
    digest = {line.split()[1]: line.split()[0] for line in shasums.splitlines() if line.strip()}
    def size_of(url):
        req = urllib.request.Request(url, method='HEAD')
        with urllib.request.urlopen(req, timeout=60) as r:
            return int(r.headers['Content-Length'])
    nodes = {}
    for key, arch, kind in [('macos-arm64', 'darwin-arm64', 'tar'), ('macos-x64', 'darwin-x64', 'tar'),
                            ('linux-arm64', 'linux-arm64', 'tar'), ('linux-x64', 'linux-x64', 'tar'),
                            ('windows-arm64', 'win-arm64', 'file'), ('windows-x64', 'win-x64', 'file')]:
        if kind == 'tar':
            name = f'node-v{NODE_VERSION}-{arch}.tar.gz'
            nodes[key] = {'url': f'https://nodejs.org/dist/v{NODE_VERSION}/{name}', 'sha256': digest[name],
                          'bytes': size_of(f'https://nodejs.org/dist/v{NODE_VERSION}/{name}'), 'archive': 'tar',
                          'executable': f'node-v{NODE_VERSION}-{arch}/bin/node'}
        else:
            name = f'{arch}/node.exe'
            nodes[key] = {'url': f'https://nodejs.org/dist/v{NODE_VERSION}/{name}', 'sha256': digest[name],
                          'bytes': size_of(f'https://nodejs.org/dist/v{NODE_VERSION}/{name}'), 'archive': 'file', 'executable': 'node.exe'}

    dsh_version = lock[root]['version']
    out = {
        'schema': 1,
        'dsh': dsh_version,
        'node': {'version': NODE_VERSION, 'assets': nodes},
        'registry': REGISTRY,
        # The packages above were traced on macOS; the others have no entry
        # until they are traced and tested on that platform.
        'platforms': args.platforms,
        'packages': packages,
    }
    pathlib.Path(args.out).write_text(json.dumps(out, indent=1, ensure_ascii=False) + '\n')
    uniq = {p['sha256']: p['bytes'] for p in packages}
    print(f'{len(packages)} install paths, {len(uniq)} tarballs, {sum(uniq.values()) / 1e6:.1f} MB to download')


if __name__ == '__main__':
    main()
