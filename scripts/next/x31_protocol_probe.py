#!/usr/bin/env python3
"""Probe empty-rollout persistence, without any model turn."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

root = Path(tempfile.mkdtemp(prefix='x31-rpc-', dir='/tmp/nipa-next'))
home = root / 'codex-home'
home.mkdir(mode=0o700)
config = (Path.home() / '.codex/config.toml').read_text()
config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
(home / 'config.toml').write_text(config)
(home / 'config.toml').chmod(0o600)
shutil.copy2(Path.home() / '.codex/auth.json', home / 'auth.json')
shutil.copy2('/etc/ssl/cert.pem', root / 'ca.pem')
env = os.environ.copy()
env.update(CODEX_HOME=str(home), CODEX_CA_CERTIFICATE=str(root / 'ca.pem'), SSL_CERT_FILE=str(root / 'ca.pem'))
process = None
counter = 0
records = []


def rpc(method, params):
    global counter
    counter += 1
    process.stdin.write(json.dumps({'id': counter, 'method': method, 'params': params}) + '\n')
    process.stdin.flush()
    while True:
        message = json.loads(process.stdout.readline())
        if message.get('id') == counter:
            return message


def launch():
    global process
    process = subprocess.Popen(['codex', 'app-server'], cwd=root, env=env, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    rpc('initialize', {'clientInfo': {'name': 'x31-probe', 'version': '1'}})
    process.stdin.write('{"method":"initialized","params":{}}\n')
    process.stdin.flush()


def stop():
    process.terminate()
    process.wait(timeout=10)


try:
    launch()
    for named in [False, True]:
        response = rpc('thread/start', {'cwd': str(root), 'approvalPolicy': 'never', 'sandbox': 'danger-full-access'})
        thread = response['result']['thread']
        identifier = thread['id']
        exists_before = Path(thread['path']).exists()
        if named:
            rpc('thread/name/set', {'threadId': identifier, 'name': 'NipaPlay 主会话'})
        records.append({'named': named, 'id': identifier,
                        'rolloutBeforeName': exists_before, 'rolloutAfterName': Path(thread['path']).exists()})
    stop()
    launch()
    for record in records:
        response = rpc('thread/resume', {'threadId': record['id'], 'cwd': str(root),
                                       'approvalPolicy': 'never', 'sandbox': 'danger-full-access'})
        record['resumeError'] = response.get('error')
        record['resumedId'] = response.get('result', {}).get('thread', {}).get('id')
    print(json.dumps(records, ensure_ascii=False, indent=2))
finally:
    if process is not None and process.poll() is None:
        stop()
    shutil.rmtree(root)
