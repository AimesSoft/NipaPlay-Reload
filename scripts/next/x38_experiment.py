#!/usr/bin/env python3
"""Disposable copied demo library; direct worktree binary, quiet, PID cleanup."""
import gzip
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
from http.server import ThreadingHTTPServer
import urllib.parse
import urllib.request

from x23_vm import LabVM
from x38_protocol import Provider

workspace = Path(__file__).resolve().parents[2]
wait_only = '--wait-only' in sys.argv
timeout_only = '--timeout-only' in sys.argv
dispatch_only = '--dispatch-only' in sys.argv
reuse_only = '--reuse-only' in sys.argv
recovery = '--recovery-only' in sys.argv
controls = '--controls' in sys.argv or wait_only or recovery or timeout_only or dispatch_only or reuse_only
evidence = workspace / 'docs/next/evidence/x38' / ('reuse' if reuse_only else 'timeout' if timeout_only else
    'dispatch' if dispatch_only else 'wait' if wait_only else
    'recovery' if recovery else 'controls' if controls else 'deepseek')
evidence.mkdir(parents=True, exist_ok=True)
profile = 'x38-' + ('controls-' if controls else 'real-') + str(os.getpid())
profiles = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles'
source = profiles / 'demo'
root = profiles / profile
assert not root.exists()
root.mkdir(mode=0o700)
home = root / 'codex-home'
home.mkdir(mode=0o700)
app = vm = endpoint = server = None
records = []
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def record(label, value):
    records.append({'at': time.time(), 'label': label, 'value': value})
    (evidence / 'timeline.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(value, ensure_ascii=False), flush=True)


def until(predicate, seconds=180):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        assert app.poll() is None, 'owned app exited'
        time.sleep(.5)
    raise RuntimeError('observation deadline reached')


def call(action, inputs):
    with opener.open(urllib.request.Request(endpoint['url'],
        data=json.dumps({'operation': 'call', 'action': action, 'input': inputs}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']}), timeout=60) as response:
        result = json.load(response)
    assert result['status'] == 'completed', (action, result)
    return result['result']


def helpers():
    return [job for job in call('task.list', {'type': 'agent.helper'})['jobs']
            if job.get('source') == 'codexNative']


def idle():
    return vm.chat('status')['liveness']['status'] not in ('inProgress', 'starting')


def returns():
    return call('followup.list', {})['followups']


def ready():
    global vm, endpoint
    if not (root / 'endpoint.json').exists():
        return False
    endpoint = json.loads((root / 'endpoint.json').read_text())
    try:
        vm = LabVM(root / 'app.log')
        header = vm.chat('status')['header']
        return header['threadId'] and header['model']
    except RuntimeError:
        return False


try:
    for name in ['data', 'support', 'cache']:
        if (source / name).exists():
            shutil.copytree(source / name, root / name,
                ignore=shutil.ignore_patterns('*.db', '*.db-wal', '*.db-shm'))
            for database in (source / name).rglob('*.db'):
                target = root / database.relative_to(source)
                target.parent.mkdir(parents=True, exist_ok=True)
                with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as original:
                    with sqlite3.connect(target) as copied:
                        original.backup(copied)
    if (source / 'credential-vault.json').exists():
        shutil.copy2(source / 'credential-vault.json', root / 'credential-vault.json')
    prefs = json.loads((source / 'preferences.json').read_text())
    prefs = json.loads(json.dumps(prefs).replace(str(source), str(root)))
    prefs.update({'flutter.labs_enable_agent_endpoint': True, 'flutter.labs_use_next_interface': False,
                  'flutter.next_harness_path': str(root / 'harness'), 'flutter.auto_sync_enabled': False,
                  'flutter.downloader_enabled': False})
    (root / 'preferences.json').write_text(json.dumps(prefs))
    harness = root / 'harness'
    shutil.copytree(workspace / 'assets/next/harness', harness)
    (harness / 'nipa').chmod(0o755)
    subprocess.run(['git', 'init', '--quiet', '--template=', '--initial-branch=main'], cwd=harness, check=True)
    with (harness / 'AGENTS.md').open('a') as stream:
        stream.write('\n## 本次实验环境\n这是 demo 片库的独立临时副本，不是用户真实数据目录。'
            '只读查询片库与弹幕，不导入、不改绑定、不改设置、不播放。'
            '/Volumes/Media 是用户授权的只读挂载，不写、不删、不改名、不复制整部，不寻找账号、不重挂载。'
            '工作文件只写在这个 harness；不读取其他 profile、用户真实数据或钥匙串。'
            '\n当前对话里的“这部”是《莉可丽丝：友谊是时间的窃贼》，'
            'workId=work-dcd42b10aa57e918860e51adbff47c206896639bdb20cfbc286870d8df7593aa，共六集。\n')
    if controls:
        server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        config = ('model="deepseek-v4.1-flash"\nmodel_provider="fixture"\n'
            '[features]\nmulti_agent=true\n[model_providers.fixture]\nname="fixture"\nwire_api="responses"\n'
            'base_url="http://127.0.0.1:%d/v1"\n' % server.server_port)
    else:
        config = (source / 'codex-home/config.toml').read_text()
        config = config.replace(str(source), str(root))
        config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
        shutil.copy2(source / 'codex-home/auth.json', home / 'auth.json')
    (home / 'config.toml').write_text(config)
    (home / 'config.toml').chmod(0o600)
    shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
    hosts = ['127.0.0.1', 'localhost'] + [urllib.parse.urlparse(url).hostname
        for url in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"', config)]
    env = dict(os.environ, NIPAPLAY_PROFILE=profile, CODEX_HOME=str(home),
        CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'), SSL_CERT_FILE=str(root / 'system-ca.pem'),
        NO_PROXY=','.join(hosts), no_proxy=','.join(hosts))
    env.pop('NIPAPLAY_LAB_QUIET', None)
    with (root / 'app.log').open('w') as output:
        app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
            env=env, stdout=output, stderr=subprocess.STDOUT)
    until(ready)
    assert vm.rpc('getVM')['pid'] == app.pid
    record('launch', {'pid': app.pid, 'profile': profile, 'header': vm.chat('status')['header']})
    record('copied-library', call('media.library.work', {
        'workId': 'work-dcd42b10aa57e918860e51adbff47c206896639bdb20cfbc286870d8df7593aa'}))
    if reuse_only:
        record('reuse-turn', vm.chat('turn', text='PROBE:spawn-fast'))
        until(lambda: helpers() and helpers()[0]['state'] == 'succeeded')
        until(idle)
        record('first-turn-receipt', helpers()[0])
        record('second-turn', vm.chat('turn', text='PROBE:second ' + helpers()[0]['threadId']))
        until(lambda: len(helpers()) == 2 and all(job['state'] == 'succeeded' for job in helpers()))
        until(lambda: len(returns()) == 2 and all(row['state'] == 'completed' for row in returns()))
        record('reused-thread-receipts', {'helpers': helpers(), 'followups': returns(),
            'child': vm.chat('read', threadId=helpers()[0]['threadId'])})
        sys.exit(0)
    if dispatch_only:
        record('parent-idle-before-dispatch', vm.chat('status'))
        record('script-dispatch', call('agent.dispatch', {'title': '脚本只读检查', 'instruction': 'CHILD:FAST'}))
        until(lambda: returns() and returns()[-1]['state'] == 'completed')
        record('script-dispatch-return', {'jobs': call('task.list', {'type': 'agent.helper'})['jobs'],
            'followups': returns()})
        sys.exit(0)
    if timeout_only:
        record('wait-timeout-turn', vm.chat('turn', text='PROBE:spawn-wait-timeout'))
        until(lambda: helpers())
        until(idle)
        record('timeout-did-not-consume', {'helper': helpers()[-1], 'followups': returns()})
        Provider.release.set()
        until(lambda: returns() and returns()[-1]['state'] == 'completed')
        record('result-returned-after-timeout', {'helper': helpers()[-1], 'followups': returns()})
        sys.exit(0)
    if wait_only:
        record('wait-user-turn', vm.chat('turn', text='PROBE:spawn-wait'))
        until(lambda: helpers() and helpers()[-1]['state'] == 'succeeded')
        until(idle)
        until(lambda: returns() and returns()[-1]['state'] == 'cancelled')
        record('wait-result-not-resent', {'helper': helpers()[-1], 'followup': returns()[-1],
            'parent': vm.chat('read', threadId=vm.chat('status')['header']['mainThreadId'])})
        sys.exit(0)
    prompt = 'PROBE:spawn' if controls else '派个帮手去把这部每一集的弹幕情况查一遍（每集有没有、多少条），查完告诉我。你这边先别等它。'
    record('user-turn', vm.chat('turn', text=prompt))
    until(lambda: helpers(), seconds=600)
    record('native-helper-visible', helpers())
    if recovery:
        until(lambda: helpers()[0].get('startedAt'))
        record('before-restart', helpers())
        vm.chat('close')
        app.terminate()
        app.wait(timeout=20)
        record('stopped-owned-pid', {'pid': app.pid, 'returncode': app.returncode})
        with (root / 'app-restarted.log').open('w') as output:
            app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                env=env, stdout=output, stderr=subprocess.STDOUT)
        shutil.move(root / 'app.log', root / 'app-before-restart.log')
        (root / 'app.log').symlink_to(root / 'app-restarted.log')
        until(ready)
        assert vm.rpc('getVM')['pid'] == app.pid
        until(lambda: helpers()[0]['state'] in ['succeeded', 'cancelled', 'failed'])
        until(lambda: returns() and returns()[0]['state'] == 'completed')
        record('recovered', {'helper': helpers(), 'followups': returns(),
            'parent': vm.chat('read', threadId=vm.chat('status')['header']['mainThreadId'])})
        sys.exit(0)
    if controls:
        until(idle)
        record('parent-ended-child-running', {'parent': vm.chat('status'), 'jobs': helpers()})
        record('parent-busy-turn', vm.chat('turn', text='PROBE:busy'))
        Provider.release.set()
        until(lambda: helpers()[0]['state'] == 'succeeded')
        until(lambda: returns() and returns()[0]['state'] == 'ready')
        record('result-queued-while-parent-busy', returns())
        Provider.parent_release.set()
    until(lambda: any(row['state'] == 'completed' for row in returns()), seconds=600)
    record('delivered-followups', returns())
    record('completed-helper', helpers())
    main = vm.chat('status')['header']['mainThreadId']
    record('parent-after-return', vm.chat('read', threadId=main))
    until(idle)
    count = len(helpers())
    if controls:
        Provider.release.clear()
    prompt = 'PROBE:spawn' if controls else '再派一个帮手只读核对这部每集的弹幕条数和来源。你这边先别等它。'
    record('cancel-user-turn', vm.chat('turn', text=prompt))
    until(lambda: len(helpers()) > count and helpers()[-1]['state'] in ['running', 'cancelling'], seconds=600)
    victim = helpers()[-1]
    until(lambda: vm.chat('status')['threads'].get(victim['threadId'], {}).get('turnId'))
    record('before-task-cancel', victim)
    record('task-cancel', call('task.cancel', {'jobId': victim['jobId']}))
    until(lambda: helpers()[-1]['state'] == 'cancelled')
    record('cancelled-helper', helpers()[-1])
    record('interrupted-child-history', vm.chat('read', threadId=victim['threadId']))
    if controls:
        Provider.release.set()
    until(lambda: all(row['state'] in ['completed', 'cancelled'] for row in returns()), seconds=600)
    record('all-returns', returns())
    if controls:
        until(idle)
        count = len(helpers())
        record('wait-user-turn', vm.chat('turn', text='PROBE:spawn-wait'))
        until(lambda: len(helpers()) > count and helpers()[-1]['state'] == 'succeeded')
        until(idle)
        until(lambda: returns()[-1]['state'] == 'cancelled')
        record('wait-result-not-resent', {'helper': helpers()[-1], 'followup': returns()[-1],
            'parent': vm.chat('read', threadId=main)})
except Exception as error:
    record('observation-error', str(error))
    raise
finally:
    Provider.release.set()
    Provider.parent_release.set()
    if app is not None and app.poll() is None:
        if vm is not None:
            try:
                vm.chat('close')
            except RuntimeError:
                pass
        app.terminate()
        app.wait(timeout=20)
    if (root / 'chat-events.jsonl').exists():
        with gzip.open(evidence / 'chat.jsonl.gz', 'wb') as output:
            output.write((root / 'chat-events.jsonl').read_bytes())
    if endpoint is not None:
        for path in evidence.glob('*'):
            content = gzip.open(path, 'rt').read() if path.suffix == '.gz' else path.read_text(errors='replace')
            assert endpoint['token'] not in content
    shutil.rmtree(root)
    if server is not None:
        server.shutdown()
    (evidence / 'cleanup.json').write_text(json.dumps({'pid': None if app is None else app.pid,
        'returncode': None if app is None else app.returncode, 'profileRemoved': not root.exists()}))
