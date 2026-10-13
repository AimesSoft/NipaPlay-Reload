#!/usr/bin/env python3
"""Expose saved evidence for human scoring; no model calls or provider data."""
import gzip
import json
import re
from pathlib import Path

evidence = Path(__file__).resolve().parents[2] / 'docs/next/evidence/x50'
rows = []
for task in ('metadata', 'helper'):
    for version in ('old', 'new'):
        for repeat in (1, 2, 3):
            folder = evidence / f'{task}-{version}-{repeat}'
            trace = folder / 'trace.json.gz'
            if not trace.exists():
                continue
            saved = json.loads(gzip.open(trace, 'rt').read())
            result = json.loads((folder / 'summary.json').read_text())
            commands, replies, errors = [], [], []
            for event in saved['events']:
                if event.get('method') != 'item/completed':
                    continue
                item = event['params']['item']
                if item['type'] == 'commandExecution':
                    commands.append(item)
                    output = item.get('aggregatedOutput') or ''
                    if ('./nipa' in item['command'] and
                        (re.search(r'"status"\s*:\s*"failed"', output) or
                         'NipaPlay HTTP 404' in output)):
                        errors.append({'command': item['command'], 'output': output[:1800]})
                if item['type'] == 'agentMessage':
                    replies.append(item['text'])
            actual = saved['result']
            if task == 'metadata':
                overview = actual['after']['fields']['overview']
                completed = (result['naturalEnd'] and overview['language'].startswith('zh') and
                             bool(re.search(r'[\u4e00-\u9fff]', overview['value'])))
                observed = overview
            else:
                completed = (result['naturalEnd'] and len(actual['thread']['turns']) >= 2 and
                             any(j['state'] == 'succeeded' for j in actual['helpers']['jobs']))
                observed = {'expected': [2, 0, 3, 0, 0, 0], 'parentReplies': [i['text']
                    for t in actual['thread']['turns'] for i in t['items'] if i['type'] == 'agentMessage']}
                completion_order = ['parent' if e['params']['threadId'] == result['header']['threadId'] else 'helper'
                    for e in saved['events'] if e.get('method') == 'turn/completed']
                observed['completionOrder'] = completion_order
                observed['parentEndedBeforeHelper'] = bool(completion_order and completion_order[0] == 'parent')
            possible_writes = [i['command'] for i in commands if re.search(
                r'\bnipa (?:call|--device.*call) (?:download\.(?:add|delete)|.*\.delete|followup\.register|settings\.(?:set|reset))', i['command'])]
            row = {k: result[k] for k in ('version', 'task', 'repeat', 'seedBytes', 'seconds', 'turns', 'naturalEnd', 'usage', 'cacheHitRate')}
            row.update(completed=completed, commandExecutions=len(commands), failedCapabilityCalls=len(errors),
                failedCalls=errors, observed=observed, authorizationReviewCandidates=possible_writes)
            row['wrongInputOrUnknownCapability'] = sum('"unavailable"' not in e['output'] for e in errors)
            rows.append(row)
            print(folder.name, 'completed', completed, 'commands', len(commands), 'failed calls', len(errors))
(evidence / 'evaluation.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2))
