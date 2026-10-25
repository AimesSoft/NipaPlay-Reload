import json, subprocess, sys, time, os
L = r'D:\nipaplay-next\win-next\lab\winlab\logs\run.log'
def nx(*a):
    r = subprocess.run([sys.executable, r'D:\nipaplay-next\win-next\scripts\nx.py', L, *a], capture_output=True, text=True, encoding='utf-8')
    if r.returncode: raise SystemExit(r.stdout + r.stderr)
    return json.loads(r.stdout)
nx('say', 'text=' + ' '.join(sys.argv[1:]))
t0 = time.time()
while time.time() - t0 < 300:
    time.sleep(3)
    c = nx('status')['chat']
    if not c['running'] and not c['loading'] and c['turns'] and c['turns'][-1]['status'] != 'inProgress':
        break
turn = c['turns'][-1]
print(json.dumps(turn, ensure_ascii=False, indent=1))
