#!/usr/bin/env python3
"""Summarize only previously captured, redacted evidence; no experiment rerun."""
from pathlib import Path
import collections
import gzip
import json

root = Path(__file__).resolve().parents[2] / 'docs/next/evidence/x49'
requests = json.load(gzip.open(root / 'provider-inputs.json.gz', 'rt'))
timeline = json.loads((root / 'timeline.json').read_text())


def text(item):
    return '\n'.join(part.get('text', '') for part in item.get('content', [])
                     if isinstance(part, dict))


def selection(label):
    return [row for row in requests if row['label'] == label]


summary = {'requests': len(requests), 'cache': [], 'compaction': [],
           'deletionPrefixes': [], 'hookRuns': [], 'secretChecks': []}
for run in range(1, 4):
    for injection in [True, False]:
        rows = []
        for step in range(1, 4):
            request = selection('cache-%d-%s-%d' % (run, injection, step))[0]
            usage = request['usage']
            total = usage['input_tokens']
            hits = usage['input_tokens_details']['cached_tokens']
            rows.append({'step': step, 'input': total, 'hits': hits,
                         'rate': hits / total,
                         'hasInjection': any('<nipa_memory>' in text(i) for i in request['input'])})
        summary['cache'].append({'run': run, 'injection': injection, 'turns': rows})
    request = selection('after-compact-%d' % run)[0]
    contents = [text(i) for i in request['input']]
    compact = next(t for t in contents if t.startswith('Another language model started'))
    hook = next(t for t in contents if '<nipa_memory>' in t)
    summary['compaction'].append({
        'run': run, 'summaryCharacters': len(compact),
        'originalPreferenceUserMessage': any(t.startswith('我今晚只想轻松点') for t in contents),
        'originalProbeUserMessage': any('请运行 python3 -c' in t for t in contents),
        'oldAssistantItems': sum(i.get('role') == 'assistant' for i in request['input']),
        'oldToolOutputs': sum(i.get('type') == 'function_call_output' for i in request['input']),
        'freshHookCharacters': len(hook),
        'summary': compact,
        'freshHook': hook,
    })
    before = selection('new-session-%d' % run)[-1]['input']
    after = selection('after-delete-%d' % run)[0]['input']
    summary['deletionPrefixes'].append({'run': run, 'priorItems': len(before),
        'unchanged': after[:len(before)] == before,
        'noticeInNewInput': text(after[-1]).startswith('NipaPlay 记忆变化：')})
    for line in gzip.open(root / ('chat-%d.jsonl.gz' % run), 'rt'):
        message = json.loads(line)['m']
        if message.get('method') == 'hook/completed':
            event = message['params']
            summary['hookRuns'].append({'run': run, 'threadId': event['threadId'],
                'turnId': event['turnId'], 'status': event['run']['status'],
                'durationMs': event['run']['durationMs']})
summary['secretChecks'] = [row['value'] for row in timeline
                          if row['label'].startswith('secret-not-in-memory-')]
for injection in [True, False]:
    rows = [turn for cohort in summary['cache'] if cohort['injection'] == injection
            for turn in cohort['turns']]
    steady = [row for row in rows if row['step'] > 1]
    summary['cache'].append({'aggregate': True, 'injection': injection,
        'allTurnsRate': sum(r['hits'] for r in rows) / sum(r['input'] for r in rows),
        'laterTurnsRate': sum(r['hits'] for r in steady) / sum(r['input'] for r in steady)})
for folder, file in [('supplement', 'chat-4.jsonl.gz'), ('restart', 'chat-5.jsonl.gz')]:
    if not (root / folder / file).exists():
        continue
    completed = []
    for line in gzip.open(root / folder / file, 'rt'):
        message = json.loads(line)['m']
        if message.get('method') == 'hook/completed':
            completed.append({'turnId': message['params']['turnId'],
                              'status': message['params']['run']['status'],
                              'durationMs': message['params']['run']['durationMs']})
    summary[folder + 'Hooks'] = completed
(root / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
print(json.dumps({key: value for key, value in summary.items() if key != 'compaction'},
                 ensure_ascii=False, indent=2))
