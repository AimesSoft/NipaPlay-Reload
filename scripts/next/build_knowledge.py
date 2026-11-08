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
    'README.md',
    'start/install.md', 'start/setup-nipa.md', 'start/first-day.md',
    'use/nipa.md', 'use/library.md', 'use/playback.md', 'use/downloads.md',
    'use/home.md', 'use/devices.md', 'use/examples.md', 'use/subscriptions.md',
    'advanced/automation.md', 'advanced/dsh-config.md', 'advanced/data-and-recovery.md',
    'advanced/headless.md',
    'help/faq.md', 'help/troubleshooting.md', 'help/known-issues.md',
    'development/principles.md', 'development/ARCHITECTURE.md',
    'development/CAPABILITIES.md', 'development/KNOWLEDGE.md',
    'development/OBSERVABILITY_CONTRACT.md',
    'development/ACTION_REFERENCE.md', 'development/ACTION_COVERAGE.md',
    'development/guides/README.md', 'development/guides/playback.md',
    'development/guides/mesh.md', 'development/guides/media-identity.md',
    'development/guides/subtitles-danmaku.md',
    'development/guides/downloads-sources.md', 'development/guides/library-presentation.md',
    'development/guides/automation-memory.md', 'development/guides/maintenance-accounts.md',
    'development/UI_CAPABILITIES.md', 'development/TOOL_GUIDANCE.md',
    'development/reference/README.md', 'development/reference/media-model.md',
    'development/reference/execution-model.md', 'development/reference/device-model.md',
    'development/reference/agent-model.md',
]
CONCEPTS = ('development/reference/', 'development/ARCHITECTURE.md', 'development/principles.md')
TOOL_REFERENCES = ('development/CAPABILITIES.md', 'development/ACTION_REFERENCE.md',
                   'development/TOOL_GUIDANCE.md')
# Every public Action family must have a task entry. This is a navigation
# check, not a claim that every operation has been executed or semantically audited.
FAMILY_GUIDES = {}
for guide, families in {
    'playback': 'playback history',
    'mesh': 'mesh',
    'media-identity': 'media db',
    'subtitles-danmaku': 'subtitle danmaku',
    'downloads-sources': 'download subscription',
    'library-presentation': 'ui appearance',
    'automation-memory': 'activity agent chat events followup memory program task',
    'maintenance-accounts': 'voice accounts app backup cache credentials secrets diagnostics discover network notification plugins settings share shortcuts state storage sync webdav_quick',
}.items():
    for family in families.split():
        FAMILY_GUIDES[family] = 'development/guides/' + guide + '.md'
FAMILY_GUIDES.update({'knowledge': 'development/KNOWLEDGE.md', 'capability': 'development/TOOL_GUIDANCE.md',
                      'window': 'development/guides/maintenance-accounts.md'})

OUTPUT = ROOT / 'assets/next/knowledge/catalog.json'


def git(*args):
    try:
        return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def build(version=None, commit=None, dirty=None):
    if version is None:
        version = re.search(r'^version:\s*(\S+)', (ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)[1]
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
                              kind=('concept' if name.startswith(CONCEPTS)
                                    else 'guide' if name.startswith('development/guides/')
                                    else 'tool-reference' if name in TOOL_REFERENCES
                                    else 'reference' if name.startswith('development/') else 'current'),
                              sha256=hashlib.sha256(content.encode()).hexdigest(), content=content))
    # Source references are navigation candidates, never synthesized Action schemas.
    reference = (ROOT / 'docs/next/development/ACTION_REFERENCE.md').read_text(encoding='utf-8')
    actions = {}
    for line in reference.splitlines():
        match = re.match(r'\| `([a-z][a-z0-9_.]+)` \|', line)
        if not match:
            continue
        actions[match[1]] = sorted(set(re.findall(r'\]\(\.\./\.\./\.\./([^)#]+)', line)))
    for action in actions:
        family = action.split('.')[0]
        guide = FAMILY_GUIDES.get(family)
        if guide not in DOCUMENTS:
            raise ValueError(f'Action family has no installed task entry: {family}')
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
        old = json.loads(args.output.read_text(encoding='utf-8'))
        new = build()
        if any(old[key] != new[key] for key in ('formatVersion', 'contentRevision', 'documents', 'actions')):
            raise SystemExit('Knowledge snapshot is stale; run python3 scripts/next/build_knowledge.py')
        print(f'Knowledge snapshot matches {len(new["documents"])} documents')
    else:
        write(args.output, version=args.version)
        print(f'Wrote {args.output}')


if __name__ == '__main__':
    main()
