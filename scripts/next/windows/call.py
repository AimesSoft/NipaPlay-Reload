"""call.py ACTION [json-or-@file] -- python nipa call ACTION, JSON passed through a file (no shell quoting)."""
import json, os, subprocess, sys, tempfile
action = sys.argv[1]
raw = sys.argv[2] if len(sys.argv) > 2 else '{}'
if not raw.startswith('@'):
    f = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8')
    f.write(raw); f.close(); raw = '@' + f.name
env = dict(os.environ, PYTHONUTF8='1')
r = subprocess.run([sys.executable, r'D:\nipaplay-next\win-next\lab\winlab\harness\nipa', 'call' if not action.startswith('query:') else 'query', action.replace('query:', ''), raw], capture_output=True, text=True, encoding='utf-8', env=env)
out = r.stdout.strip()
try:
    out = json.dumps(json.loads(out), ensure_ascii=False, indent=1)
except Exception:
    pass
print(out[:int(os.environ.get('CALL_MAX', '6000'))])
if r.stderr.strip(): print('STDERR', r.stderr[:1000])
