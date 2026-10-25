import json, os, subprocess, sys
root = r'D:\nipaplay-next\win-next\lab\winlab\harness'
env = dict(os.environ, NIPAPLAY_ENDPOINT_FILE=r'D:\nipaplay-next\win-next\lab\winlab\endpoint.json', NIPAPLAY_CHAT='')
stdin = json.dumps({'session_id': 's1', 'transcript_path': None, 'cwd': root, 'hook_event_name': 'SessionStart', 'source': 'startup', 'model': None})
for label, extra in (('without PYTHONUTF8', {'PYTHONUTF8': '0', 'PYTHONIOENCODING': ''}), ('with PYTHONUTF8', {'PYTHONUTF8': '1'})):
    e = dict(env, **extra)
    if not e.get('PYTHONIOENCODING'): e.pop('PYTHONIOENCODING', None)
    r = subprocess.run(['python', os.path.join(root, 'hooks', 'session_start.py')], input=stdin.encode('utf-8'), capture_output=True, env=e, cwd=root)
    out = r.stdout.decode('utf-8', errors='replace')
    try:
        text = json.loads(out)['hookSpecificOutput']['additionalContext']
        print(label, 'exit', r.returncode, 'ok, len', len(text), 'has CJK:', any('\u4e00' <= c <= '\u9fff' for c in text), 'replacement chars:', text.count('\ufffd'))
    except Exception as ex:
        print(label, 'exit', r.returncode, 'bad json:', type(ex).__name__, out[:100].encode('unicode_escape')[:120], r.stderr.decode('utf-8', 'replace')[-200:])
