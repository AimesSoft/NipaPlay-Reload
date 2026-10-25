import json, os, subprocess, sys, tempfile, time
H = r'D:\nipaplay-next\win-next\lab\winlab\harness'
NIPA = os.path.join(H, 'nipa')
env = dict(os.environ, PYTHONUTF8='1')
open(os.path.join(H, 'hooks', 'playback.started.py'), 'w', encoding='utf-8').write(
    'import json, sys\nev = json.load(sys.stdin)\nopen("hook-ran.txt", "w", encoding="utf-8").write(ev["data"]["path"] + "\\n")\nprint("hook saw", ev["data"]["path"])\n')
def call(action, data):
    f = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8'); f.write(json.dumps(data, ensure_ascii=False)); f.close()
    r = subprocess.run([sys.executable, NIPA, 'call', action, '@' + f.name], capture_output=True, text=True, encoding='utf-8', env=env); os.unlink(f.name)
    return json.loads(r.stdout)
call('playback.open', {'path': r'D:\nipaplay-next\win-next\media\awkward\普通 目录\Big Buck Bunny 【测试】.mp4'})
time.sleep(4)
jobs = call('task.list', {'type': 'harness.hook'})['result']['jobs']
for j in jobs:
    print(j['state'], json.dumps((j.get('receipt') or {}).get('details'), ensure_ascii=False)[:400])
print(open(os.path.join(H, 'hook-ran.txt'), encoding='utf-8').read())
