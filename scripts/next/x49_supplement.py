#!/usr/bin/env python3
"""Only final recent sorting/budgets, resume hooks and settings facts."""
from pathlib import Path

source = Path(__file__).with_name('x49_experiment.py').read_text()
exec(compile(source.split('\ntry:\n    for run in range', 1)[0],
             str(Path(__file__).with_name('x49_experiment.py')), 'exec'))
primary_evidence = evidence
evidence = evidence / 'supplement'
evidence.mkdir(exist_ok=True)
shutil.copy2(primary_evidence / 'hook-trust-probe.json', evidence / 'hook-trust-probe.json')

try:
    launch(4)
    for repetition in range(1, 4):
        previous = vm.chat('status')['header']['threadId']
        turn('older-%d' % repetition, '目前在准备旧片单%d；只回复收到，不要工具。' % repetition)
        newer = vm.chat('start')['thread']['id']
        turn('newer-%d' % repetition, '刚才在准备周六电影夜新片单%d；只回复收到，不要工具。' % repetition)
        vm.chat('resume', threadId=previous)
        context = call('memory.context', {'threadId': previous})
        record('most-recent-after-resume-%d' % repetition, {
            'source': context['recent']['sourceThreadId'], 'expected': newer,
            'matched': context['recent']['sourceThreadId'] == newer})
        call('settings.set', {'key': 'danmaku.opacity', 'value': .55 + .05 * repetition,
             'reason': '实验用户偏好：弹幕透明度第%d次确认' % repetition})
        pending = call('followup.register', {'when': {'event': 'playback.started'},
              'title': '待播放后复核片单%d' % repetition,
              'instruction': '播放开始后再核对；这是实验的等待事实。'})['followup']
        call('activity.report', {'title': '刚确认周六片单%d' % repetition,
             'source': 'x49-supplement', 'facts': {'original': '原始观察%d' % repetition}})
        context = call('memory.context', {'threadId': previous})
        record('facts-%d' % repetition, context)
        assert any(row['key'] == 'danmaku.opacity' and row['reason'].endswith('%d次确认' % repetition)
                   for row in context['settings'])
        assert '待播放后复核片单' in context['recent']['text']
        assert len(context['recent']['text']) <= 3000
        turn('resume-%d' % repetition, '只回复恢复完成；不要工具。')
        # Force both resident files over the cap through direct file writes.
        preference = root / 'harness/memory/preferences.md'
        index = root / 'harness/memory/MEMORY.md'
        old_pref, old_index = preference.read_text(), index.read_text()
        preference.write_text('测' * 3000)
        index.write_text('索' * 3000)
        context = call('memory.context', {})
        record('resident-limits-%d' % repetition, {
            'preferencesTailNotice': context['preferences'].split('\n')[-1],
            'indexTailNotice': context['index'].split('\n')[-1],
            'recentCharacters': len(context['recent']['text']),
            'recentOmitted': context['recent']['omitted']})
        assert '810 UTF-8 字节未注入' in context['preferences']
        assert '810 UTF-8 字节未注入' in context['index']
        preference.write_text(old_pref)
        index.write_text(old_index)
        call('followup.cancel', {'id': pending['id']})
        vm.chat('start')
    stop(4)
finally:
    if app is not None:
        stop(4)
    server.shutdown()
    server.server_close()
    with gzip.open(evidence / 'provider-inputs.json.gz', 'wt') as stream:
        json.dump(captures, stream, ensure_ascii=False)
