"""Open the awkward-path files (Chinese, spaces, brackets, 250 characters deep) with every kernel."""
import json, os, subprocess, sys, tempfile, time
NIPA = r'D:\nipaplay-next\win-next\lab\winlab\harness\nipa'
env = dict(os.environ, PYTHONUTF8='1')
def call(action, data=None):
    f = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8'); f.write(json.dumps(data or {}, ensure_ascii=False)); f.close()
    r = subprocess.run([sys.executable, NIPA, 'call', action, '@' + f.name], capture_output=True, text=True, encoding='utf-8', env=env)
    os.unlink(f.name)
    try: return json.loads(r.stdout)
    except Exception: return {'status': 'unparsed', 'out': r.stdout[:300]}
def state():
    r = call('playback.state'); return (r.get('result') or {}).get('state', r.get('result') or {})
base = r'D:\nipaplay-next\win-next\media\awkward'
files = []
for root, _, names in os.walk(base):
    for n in names:
        if n.endswith(('.mkv', '.mp4')): files.append(os.path.join(root, n))
print(len(files), 'files; lengths', [len(f) for f in files])
out = {}
for path in files:
    for kernel in ('mdk', 'media_kit', 'erika', 'video_player'):
        r = call('playback.open', {'path': path})
        st = state()
        if st.get('kernel', {}).get('id') != kernel:
            call('playback.reopen_with_kernel', {'sessionId': st.get('sessionId'), 'kernel': kernel}); time.sleep(2)
        time.sleep(3)
        st = state()
        out.setdefault(os.path.basename(path), {})[kernel] = {'kernel': st.get('kernel', {}).get('id'), 'status': st.get('status'), 'positionMs': st.get('positionMs'), 'hasVideo': st.get('hasVideo'), 'error': st.get('error'), 'pathLen': len(path)}
print(json.dumps(out, ensure_ascii=False, indent=1))
