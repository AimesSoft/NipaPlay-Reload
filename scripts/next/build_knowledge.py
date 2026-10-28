#!/usr/bin/env python3
"""Build the installed, curated documentation snapshot (no network or secrets)."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
DOCUMENTS = [
    'README.md', 'QUICKSTART.md', 'USER_GUIDE.md', 'NIPA_CAPABILITIES.md',
    'CAPABILITIES.md', 'ARCHITECTURE.md', 'DATA_AND_RECOVERY.md',
    'OBSERVABILITY_CONTRACT.md', 'DSH_ADVANCED_CONFIG.md', 'HEADLESS.md',
    'KNOWN_ISSUES.md', 'KNOWLEDGE.md',
    'development/ACTION_REFERENCE.md', 'development/ACTION_COVERAGE.md',
    'development/guides/README.md', 'development/guides/playback.md',
    'development/guides/mesh.md', 'development/guides/media-identity.md',
    'development/guides/subtitles-danmaku.md',
]
OUTPUT = ROOT / 'assets/next/knowledge/catalog.json'


def git(*args):
    try:
        return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def build(version=None, commit=None, dirty=None):
    if version is None:
        version = re.search(r'^version:\s*(\S+)', (ROOT / 'pubspec.yaml').read_text(), re.M)[1]
    head = git('rev-parse', 'HEAD')
    commit = commit or head or None
    # Never let an external clean stamp hide untracked knowledge/source inputs.
    state = git('status', '--porcelain', '--untracked-files=all', '--',
                'lib', 'packages', 'docs/next', 'assets/next/agent',
                'assets/next/harness', 'scripts/next', 'pubspec.yaml', 'pubspec.lock',
                ':(exclude)**/__pycache__/**')
    dirty = (True if dirty is True else None) if state is None or head is None else (
        dirty is True or bool(state) or commit != head)
    documents = []
    for name in DOCUMENTS:
        path = 'docs/next/' + name
        content = (ROOT / path).read_text(encoding='utf-8')
        if len(content.encode()) > 512 * 1024:
            raise ValueError(f'Document exceeds 512 KiB: {path}')
        documents.append(dict(id=path, title=content.splitlines()[0].lstrip('# '),
                              kind='reference' if name.startswith('development/') else 'current',
                              sha256=hashlib.sha256(content.encode()).hexdigest(), content=content))
    # Source references are navigation candidates, never synthesized Action schemas.
    reference = (ROOT / 'docs/next/development/ACTION_REFERENCE.md').read_text()
    actions = {}
    for line in reference.splitlines():
        match = re.match(r'\| `([a-z][a-z0-9_.]+)` \|', line)
        if not match:
            continue
        actions[match[1]] = sorted(set(re.findall(r'\]\(\.\./\.\./\.\./([^)#]+)', line)))
    digest = hashlib.sha256(json.dumps(
        {'documents': [(d['id'], d['sha256']) for d in documents], 'actions': actions},
        ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return dict(formatVersion=1, appVersion=version, sourceCommit=commit,
                sourceDirty=dirty, contentRevision=digest, documents=documents, actions=actions)


def write(output=OUTPUT, **kwargs):
    payload = json.dumps(build(**kwargs), ensure_ascii=False, indent=2) + '\n'
    if len(payload.encode()) > 4 * 1024 * 1024:
        raise ValueError('Knowledge snapshot exceeds 4 MiB')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(payload, encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, default=OUTPUT)
    parser.add_argument('--version')
    parser.add_argument('--check', action='store_true', help='Check source content, independent of build provenance')
    args = parser.parse_args()
    if args.check:
        old = json.loads(args.output.read_text())
        new = build()
        if any(old[key] != new[key] for key in ('formatVersion', 'contentRevision', 'documents', 'actions')):
            raise SystemExit('Knowledge snapshot is stale; run python3 scripts/next/build_knowledge.py')
        print(f'Knowledge snapshot matches {len(new["documents"])} documents')
    else:
        write(args.output, version=args.version)
        print(f'Wrote {args.output}')


if __name__ == '__main__':
    main()
